#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""逻各斯「转平面」帧条烘焙（docs/258，开关 fx/px_plane；做法同流明 tools/pxplane_bake_lumen.py）。

平面版效果源：tools/pixelfx_fx/arcane/ak-logos-pp.js；旧做法对照（fx/px_plane = 2）直接用旧放开版原文件 tools/pixelfx_fx/logos_ul_ref/ak-logos-ul-*.js
（11-04 放开版，取自 claude/pixelfx-ul-logos），色层 + 光层烤成一张。都拷进本机 pixelfx 库 build/pixelfx 的 src/fx/arcane/ 再跑 tools/ak_layers.mjs。
出：game/art/fx/pxp/pxp_lg_<键>.png + game/data/pxp_logos.json（帧数 / fps / 尺寸 / 原点 / loop / emit 点表）。
线状件（彗星弹、提喻咒文行、连缀咒文链、咒域边、连携字环）在游戏里逐格画，不出帧条。

用法（仓库根目录）：python tools/pxplane_bake_logos.py [--only 键前缀]
"""
import argparse, json, os, shutil, subprocess, sys
from concurrent.futures import ThreadPoolExecutor

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PFX = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(ROOT))) if ".claude" in ROOT else os.path.dirname(ROOT), "build", "pixelfx")
if not os.path.isdir(PFX):
    PFX = os.path.join(ROOT, "build", "pixelfx")
SRC = os.path.join(ROOT, "tools", "pixelfx_fx", "arcane", "ak-logos-pp.js")
OLD = os.path.join(ROOT, "tools", "pixelfx_fx", "logos_ul_ref")
OUT_ART = os.path.join(ROOT, "game", "art", "fx", "pxp")
OUT_META = os.path.join(ROOT, "game", "data", "pxp_logos.json")
TMP = os.path.join(ROOT, "build", "pxp_bake_logos")
FPS = 15
EMIT_LUMA = 0.95
EMIT_LUMA_HIT = 0.86
EMIT_MAX = 48
ACC = (0xa4, 0x87, 0xff)   # 精二点缀紫：也进发光层


def variants():
    """(键, 效果 id, opts, 时长秒, 循环)"""
    v = []
    PP = "arcane/ak-logos-pp"
    for el in (0, 1, 2):
        for ly in ("up", "gd"):
            v.append(("hit_e%d_%s" % (el, ly), PP, {"part": "hit", "layer": ly, "el": el, "seed": 4}, 0.73, False))
        v.append(("hits_e%d_up" % el, PP, {"part": "hit", "layer": "up", "el": el, "seed": 6, "k": 0.6}, 0.4, False))   # 小一号（额外弹 / 天赋 / 咒域每跳 / 连缀）
        v.append(("tick_e%d_up" % el, PP, {"part": "tick", "layer": "up", "el": el, "seed": 5}, 0.4, False))
        v.append(("fire_e%d_up" % el, PP, {"part": "fire", "layer": "up", "el": el, "seed": 3}, 0.53, False))
    for el in (1, 2):
        for ly in ("up", "gd"):
            v.append(("exec_e%d_%s" % (el, ly), PP, {"part": "exec", "layer": ly, "el": el, "seed": 8}, 0.8, False))
    v.append(("s3open_up", PP, {"part": "s3open", "layer": "up", "el": 2, "seed": 9}, 0.8, False))
    # raw：旧放开版原文件（光晕烤进颜色），游戏里旋转 + 小数缩放直接贴
    INK = "arcane/ak-logos-ul-ink"
    for el in (0, 1, 2):
        v.append(("raw_hit_e%d" % el, INK, {"move": "atk_hit", "elite": el}, 0.73, False))
        v.append(("raw_start_e%d" % el, INK, {"move": "atk_start", "elite": el}, 0.53, False))
        v.append(("raw_bolt_e%d" % el, INK, {"move": "atk_bolt", "elite": el}, 0.4, True))
        v.append(("raw_tick_e%d" % el, "arcane/ak-logos-ul-s1", {"move": "tick", "elite": el}, 0.6, False))
    v.append(("raw_link", "arcane/ak-logos-ul-mark", {"move": "link", "elite": 2}, 0.5, False))
    v.append(("raw_seal", "arcane/ak-logos-ul-mark", {"move": "seal", "elite": 2}, 0.8, False))
    v.append(("raw_epitaph", "arcane/ak-logos-ul-mark", {"move": "epitaph", "elite": 2}, 0.8, False))
    v.append(("raw_lock", "arcane/ak-logos-ul-markloop", {"move": "lock", "elite": 2}, 0.8, True))
    v.append(("raw_field", "arcane/ak-logos-ul-field", {"deg": 100, "R": 150}, 0.8, True))
    return v


def render(key, fx, opts, dur, loop):
    d = os.path.join(TMP, key)
    os.makedirs(d, exist_ok=True)
    o = dict(opts)
    if fx.endswith("-pp"):
        o.setdefault("dur", 1.2)
    p = subprocess.run(["node", "tools/ak_layers.mjs", fx, "--out", d, "--fps", str(FPS), "--opts", json.dumps(o)], cwd=PFX, capture_output=True, text=True)
    if p.returncode != 0:
        raise RuntimeError(key + ": " + p.stderr[-600:])
    return key, d, dur, loop


def bake(key, d, dur, loop):
    meta = json.load(open(os.path.join(d, "meta.json")))
    fw, fh = meta["frameSize"]
    n = meta["frames"]
    fps = meta["fps"]
    ox, oy = meta["pivot"]
    col = np.asarray(Image.open(os.path.join(d, "color.png")).convert("RGBA")).astype(np.float32) / 255.0
    lit = np.asarray(Image.open(os.path.join(d, "light.png")).convert("RGB")).astype(np.float32) / 255.0
    nf = max(1, min(n, int(round(dur * fps))))
    frames = [col[:, i * fw:(i + 1) * fw] for i in range(nf)]
    lights = [lit[:, i * fw:(i + 1) * fw] for i in range(nf)]
    raw = key.startswith("raw_")
    if raw:
        out = []
        for c, l in zip(frames, lights):
            a = c[..., 3:4]
            rgb = np.clip(c[..., :3] * a + l * 0.9, 0, 1)
            al = np.clip(np.maximum(a[..., 0], l.max(axis=2) * 0.9), 0, 1)
            safe = np.where(al > 0.001, al, 1.0)[..., None]
            out.append(np.concatenate([np.clip(rgb / safe, 0, 1), al[..., None]], axis=2))
        frames = out
    while not loop and len(frames) > 1 and frames[-1][..., 3].max() <= 0.0:
        frames.pop()
    alpha = np.max(np.stack([f[..., 3] for f in frames]), axis=0)
    ys, xs = np.nonzero(alpha > 0.0)
    if len(xs) == 0:
        return key, None
    x0, x1, y0, y1 = max(0, xs.min() - 1), min(fw, xs.max() + 2), max(0, ys.min() - 1), min(fh, ys.max() + 2)
    w, h = x1 - x0, y1 - y0
    strip = np.zeros((h, w * len(frames), 4), np.float32)
    emit = []
    for i, f in enumerate(frames):
        c = f[y0:y1, x0:x1]
        strip[:, i * w:(i + 1) * w] = c
        if raw:
            emit.append([])
            continue
        luma = c[..., 0] * 0.2126 + c[..., 1] * 0.7152 + c[..., 2] * 0.0722
        acc = (np.abs(c[..., 0] - ACC[0] / 255) < 0.03) & (np.abs(c[..., 1] - ACC[1] / 255) < 0.03)
        thr = EMIT_LUMA_HIT if key.startswith(("hit_", "hits_", "tick_")) else EMIT_LUMA   # docs/270：命中帧核心辉光 27 → ≥ 30，命中件的亮芯阶（#dce0ff）也进发光层
        m = (c[..., 3] > 0.5) & ((luma >= thr) | acc)
        py, px = np.nonzero(m)
        idx = np.arange(len(px))
        if len(idx) > EMIT_MAX:
            idx = idx[np.linspace(0, len(idx) - 1, EMIT_MAX).astype(int)]
        pts = []
        for j in idx:
            r, g_, b = c[py[j], px[j], :3]
            pts.append([int(px[j]), int(py[j]), "%02x%02x%02x" % (int(r * 255), int(g_ * 255), int(b * 255))])
        emit.append(pts)
    Image.fromarray((strip * 255 + 0.5).astype(np.uint8), "RGBA").save(os.path.join(OUT_ART, "pxp_lg_%s.png" % key.replace("_d-", "_dm").lower()), optimize=True)
    return key, {"n": len(frames), "fps": fps, "w": int(w), "h": int(h), "ox": int(ox - x0), "oy": int(oy - y0), "loop": loop, "emit": emit}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    ap.add_argument("--jobs", type=int, default=6)
    a = ap.parse_args()
    dst = os.path.join(PFX, "src", "fx", "arcane")
    shutil.copy(SRC, os.path.join(dst, "ak-logos-pp.js"))
    for f in os.listdir(OLD):
        if f.endswith(".js"):
            shutil.copy(os.path.join(OLD, f), os.path.join(dst, f))
    os.makedirs(OUT_ART, exist_ok=True)
    os.makedirs(TMP, exist_ok=True)
    vs = [x for x in variants() if x[0].startswith(a.only)]
    reg = json.load(open(OUT_META, encoding="utf-8")) if os.path.exists(OUT_META) and a.only else {}
    reg.pop("_doc", None)
    with ThreadPoolExecutor(a.jobs) as ex:
        rs = list(ex.map(lambda x: render(*x), vs))
    for key, d, dur, loop in rs:
        k, m = bake(key, d, dur, loop)
        if m is None:
            print("空", k)
            continue
        reg[k] = m
        print("%-22s %2d 帧 %3d×%3d emit %d" % (k, m["n"], m["w"], m["h"], max((len(e) for e in m["emit"]), default=0)))
    reg = {k: reg[k] for k in sorted(reg)}
    reg["_doc"] = "docs/258 逻各斯转平面帧条（tools/pxplane_bake_logos.py 生成，勿手改）：键对应 art/fx/pxp/pxp_lg_<键>.png；n 帧数、fps、w×h（美术像素）、ox / oy 原点、loop、emit 每帧热芯点 [x, y, 颜色]"
    json.dump(reg, open(OUT_META, "w", encoding="utf-8"), ensure_ascii=False, separators=(",", ":"))
    print("共 %d 件" % (len(reg) - 1))


if __name__ == "__main__":
    main()
