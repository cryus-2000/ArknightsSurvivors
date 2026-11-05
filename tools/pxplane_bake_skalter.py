#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""浊心斯卡蒂「转平面」对照帧条烘焙（docs/260，开关 fx/px_plane）。

浊心斯卡蒂的转平面版（fx/px_plane = 1）主形全部运行时画（render/fx_pxplane.gd 浊心斯卡蒂段：判定半径连续变化，烤成帧条只能整数倍放大、对不上半径），
所以这里只烤旧做法对照（fx/px_plane = 2）：直接用旧放开版原文件 tools/pixelfx_fx/skalter_ul_ref/ak-skalter-ul-*.js（11-04 放开版，取自本机 pixelfx 库），
色层 + 光层烤成一张，游戏里按歌域半径小数缩放直接贴。拷进本机 pixelfx 库 build/pixelfx 的 src/fx/water/ 再跑 tools/ak_layers.mjs。
出：game/art/fx/pxp/pxp_sk_<键>.png + game/data/pxp_skalter.json（帧数 / fps / 尺寸 / 原点 / loop / emit 点表）。

用法（仓库根目录）：python tools/pxplane_bake_skalter.py [--only 键前缀]
"""

import argparse, json, os, shutil, subprocess, sys
from concurrent.futures import ThreadPoolExecutor

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PFX = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(ROOT))) if ".claude" in ROOT else os.path.dirname(ROOT), "build", "pixelfx")
if not os.path.isdir(PFX):
    PFX = os.path.join(ROOT, "build", "pixelfx")
OLD = os.path.join(ROOT, "tools", "pixelfx_fx", "skalter_ul_ref")
OUT_ART = os.path.join(ROOT, "game", "art", "fx", "pxp")
OUT_META = os.path.join(ROOT, "game", "data", "pxp_skalter.json")
TMP = os.path.join(ROOT, "build", "pxp_bake_skalter")
FPS = 15
EMIT_LUMA = 0.95
EMIT_MAX = 48
ACC = (0xdc, 0x40, 0x48)   # 酒红亮段（只转平面版用；对照件不出 emit）


def variants():
    """(键, 效果 id, opts, 时长秒, 循环)"""
    v = []
    for el in (0, 1, 2):
        v.append(("raw_wave_e%d" % el, "water/ak-skalter-ul-wave", {"elite": el, "R": 95}, 0.75, False))
        v.append(("raw_s1_e%d" % el, "water/ak-skalter-ul-s1", {"elite": el}, 1.05, False))
    for el in (1, 2):
        v.append(("raw_s2_e%d" % el, "water/ak-skalter-ul-s2", {"elite": el}, 1.05, False))
    v.append(("raw_s3_e2", "water/ak-skalter-ul-s3", {"elite": 2}, 1.45, False))
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
        m = (c[..., 3] > 0.5) & ((luma >= EMIT_LUMA) | acc)
        py, px = np.nonzero(m)
        idx = np.arange(len(px))
        if len(idx) > EMIT_MAX:
            idx = idx[np.linspace(0, len(idx) - 1, EMIT_MAX).astype(int)]
        pts = []
        for j in idx:
            r, g_, b = c[py[j], px[j], :3]
            pts.append([int(px[j]), int(py[j]), "%02x%02x%02x" % (int(r * 255), int(g_ * 255), int(b * 255))])
        emit.append(pts)
    Image.fromarray((strip * 255 + 0.5).astype(np.uint8), "RGBA").save(os.path.join(OUT_ART, "pxp_sk_%s.png" % key), optimize=True)
    return key, {"n": len(frames), "fps": fps, "w": int(w), "h": int(h), "ox": int(ox - x0), "oy": int(oy - y0), "loop": loop, "emit": emit}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    ap.add_argument("--jobs", type=int, default=6)
    a = ap.parse_args()
    dst = os.path.join(PFX, "src", "fx", "water")
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
    reg["_doc"] = "docs/260 浊心斯卡蒂旧做法对照帧条（tools/pxplane_bake_skalter.py 生成，勿手改）：键对应 art/fx/pxp/pxp_sk_<键>.png（游戏里加前缀 sk_）；n 帧数、fps、w×h（美术像素）、ox / oy 原点、loop、emit 每帧热芯点 [x, y, 颜色]"
    json.dump(reg, open(OUT_META, "w", encoding="utf-8"), ensure_ascii=False, separators=(",", ":"))
    print("共 %d 件" % (len(reg) - 1))


if __name__ == "__main__":
    main()
