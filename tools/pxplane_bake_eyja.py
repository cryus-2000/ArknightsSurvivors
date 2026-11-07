#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""艾雅法拉「转平面」帧条烘焙（docs/259，开关 fx/px_plane；做法同流明 tools/pxplane_bake_lumen.py）。

效果源：tools/pixelfx_fx/fire/ak-eyjafjalla-pp.js（part 选件、layer 选层 up / gd / raw）；拷进本机 pixelfx 库 build/pixelfx 的 src/fx/fire/ 再跑 tools/ak_layers.mjs。
旧做法对照（fx/px_plane = 2）：同一形状不压扁（layer raw），色层 + 光层烤成一张，游戏里旋转 + 小数缩放直接贴。
出：game/art/fx/pxp/pxp_ey_<键>.png + game/data/pxp_eyjafjalla.json（帧数 / fps / 尺寸 / 原点 / loop / emit 点表）+ 缺的 .png.import。

用法（仓库根目录）：python tools/pxplane_bake_eyja.py [--only 键前缀]
"""
import argparse, hashlib, json, os, random, shutil, subprocess
from concurrent.futures import ThreadPoolExecutor

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PFX = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(ROOT))) if ".claude" in ROOT else os.path.dirname(ROOT), "build", "pixelfx")
if not os.path.isdir(PFX):
    PFX = os.path.join(ROOT, "build", "pixelfx")
SRC = os.path.join(ROOT, "tools", "pixelfx_fx", "fire", "ak-eyjafjalla-pp.js")
OUT_ART = os.path.join(ROOT, "game", "art", "fx", "pxp")
OUT_META = os.path.join(ROOT, "game", "data", "pxp_eyjafjalla.json")
TMP = os.path.join(ROOT, "build", "pxp_bake_eyja")
FPS = 15
EMIT_LUMA = 0.93
EMIT_MAX = 48
ACC = (0xff, 0xaa, 0x45)   # 橙黄热芯也进发光层
PRE = "ey_"
TMPL = os.path.join(OUT_ART, "pxp_lm_burst_gd.png.import")

# 尺寸档（美术像素半径；游戏里按判定半径 / 2 挑最近一档）
BOOM_R = (26, 34, 44, 56)
S1_R = (40, 52, 66)
IG_R = (44, 56)
S3_R = (38, 46)
POOL_R = (25, 30)
LAVA_R = (30, 36)
SPL_R = (15, 22)
DIRS = (-90, -45, 0, 45, 90)
# 弹体：(名, 头半径, 岩壳, 速度系数)。fire 精零火球 / lava 精一熔岩弹 / pow 二重咏唱强化弹 / ign 点燃弹 / rock 火山弹·熔岩天降 / chip 小熔岩块（火星迸溅、星火燎原、额外弹）/ boulder 连携熔岩块
BALLS = (("fire", 3, 0, 0.32), ("lava", 3.5, 1, 0.32), ("pow", 4.5, 0, 0.36), ("ign", 6, 0, 0.4), ("rock", 5, 1, 0.3), ("chip", 2.5, 1, 0.28), ("boulder", 9, 1, 0.3))


def variants():
    """(键, opts, 时长秒, 循环)"""
    v = []
    for R in BOOM_R:
        for el in (0, 1, 2):
            for ly in ("up", "gd"):
                v.append(("boom_r%d_e%d_%s" % (R, el, ly), {"part": "boom", "layer": ly, "el": el, "R": R, "seed": 3}, 0.6, False))
    for R in S1_R:
        for el in (0, 1, 2):
            for ly in ("up", "gd"):
                v.append(("s1boom_r%d_e%d_%s" % (R, el, ly), {"part": "s1boom", "layer": ly, "el": el, "R": R, "seed": 5}, 0.8, False))
    for R in IG_R:
        for el in (1, 2):
            v.append(("ignite_r%d_e%d_up" % (R, el), {"part": "ignite", "layer": "up", "el": el, "R": R, "seed": 4}, 0.8, False))
            v.append(("ignite_r%d_e%d_gd" % (R, el), {"part": "ignite", "layer": "gd", "el": el, "R": R, "seed": 4}, 1.0, False))
    for R in S3_R:
        for ly in ("up", "gd"):
            v.append(("s3boom_r%d_%s" % (R, ly), {"part": "s3boom", "layer": ly, "el": 2, "R": R, "seed": 7}, 0.9, False))
    for R in POOL_R:
        v.append(("pool_r%d_gd" % R, {"part": "lava", "layer": "gd", "el": 2, "R": R, "k": 0.7, "seed": 8, "dur": 1.2}, 1.2, True))
    for R in LAVA_R:
        v.append(("lava_r%d_gd" % R, {"part": "lava", "layer": "gd", "el": 2, "R": R, "k": 1, "seed": 9, "dur": 1.2}, 1.2, True))
    for R in SPL_R:
        for ly in ("up", "gd"):
            v.append(("splash_r%d_%s" % (R, ly), {"part": "splash", "layer": ly, "el": 0, "R": R, "seed": 6}, 0.5, False))
    for el in (0, 1, 2):
        v.append(("s1cast_e%d_up" % el, {"part": "s1cast", "layer": "up", "el": el, "R": 20, "seed": 2}, 0.6, False))
    v.append(("s1cast_e2_gd", {"part": "s1cast", "layer": "gd", "el": 2, "R": 20, "seed": 2}, 0.6, False))
    for ly in ("up", "gd"):
        v.append(("s3cast_%s" % ly, {"part": "s3cast", "layer": ly, "el": 2, "R": 40, "seed": 4}, 0.8, False))
    v.append(("aura_gd", {"part": "aura", "layer": "gd", "el": 2, "R": 30, "seed": 3, "dur": 1.2}, 1.2, True))
    for R in POOL_R:
        v.append(("lavaup_p%d_up" % R, {"part": "lavaup", "layer": "up", "el": 2, "R": R, "k": 0.7, "seed": 8, "dur": 1.2}, 1.2, True))
    for R in LAVA_R:
        v.append(("lavaup_l%d_up" % R, {"part": "lavaup", "layer": "up", "el": 2, "R": R, "k": 1, "seed": 9, "dur": 1.2}, 1.2, True))
    # 火球 / 熔岩块（库里 fire/fireball，按 5 个平面角生成，另一半水平翻转；循环 1.2 秒）
    for name, R, crust, k in BALLS:
        for d in DIRS:
            v.append(("ball_%s_d%d" % (name, d), {"part": "ball", "layer": "up", "el": 0, "R": R, "crust": crust, "k": k, "ang": d, "seed": 5}, 1.2, True))
    # raw：同一形状不压扁、光晕烤进颜色（旧做法对照）
    for el in (0, 1, 2):
        v.append(("raw_boom_e%d" % el, {"part": "boom", "layer": "raw", "el": el, "R": 30, "seed": 3}, 0.6, False))
    v.append(("raw_s1boom", {"part": "s1boom", "layer": "raw", "el": 1, "R": 44, "seed": 5}, 0.8, False))
    v.append(("raw_ignite", {"part": "ignite", "layer": "raw", "el": 2, "R": 47, "seed": 4}, 0.8, False))
    v.append(("raw_s3boom", {"part": "s3boom", "layer": "raw", "el": 2, "R": 38, "seed": 7}, 0.9, False))
    v.append(("raw_lava", {"part": "lava", "layer": "raw", "el": 2, "R": 30, "seed": 9, "dur": 1.2}, 1.2, True))
    v.append(("raw_splash", {"part": "splash", "layer": "raw", "el": 0, "R": 18, "seed": 6}, 0.5, False))
    v.append(("raw_s1cast", {"part": "s1cast", "layer": "raw", "el": 1, "R": 20, "seed": 2}, 0.6, False))
    v.append(("raw_s3cast", {"part": "s3cast", "layer": "raw", "el": 2, "R": 40, "seed": 4}, 0.8, False))
    return v


def render(key, opts, dur, loop):
    d = os.path.join(TMP, key)
    os.makedirs(d, exist_ok=True)
    o = dict(opts)
    o.setdefault("dur", 1.2)
    p = subprocess.run(["node", "tools/ak_layers.mjs", "fire/ak-eyjafjalla-pp", "--out", d, "--fps", str(FPS), "--opts", json.dumps(o)], cwd=PFX, capture_output=True, text=True)
    if p.returncode != 0:
        raise RuntimeError(key + ": " + p.stderr[-600:])
    return key, d, dur, loop


def write_import(name):
    """缺 .png.import 时按流明那份模板补（Godot 的导入路径 = 文件名 + 源路径 md5；uid 随机）"""
    dst = os.path.join(OUT_ART, name + ".import")
    if os.path.exists(dst) or not os.path.exists(TMPL):
        return
    s = open(TMPL, encoding="utf-8").read()
    rp = "res://art/fx/pxp/" + name
    h = hashlib.md5(rp.encode()).hexdigest()
    old_uid = s.split('uid="')[1].split('"')[0]
    uid = "uid://" + "".join(random.choice("abcdefghijklmnopqrstuvwxy0123456789") for _ in range(13))
    s = s.replace("pxp_lm_burst_gd.png-e01c49fe74ab656f2185741f162156ce", name + "-" + h).replace("res://art/fx/pxp/pxp_lm_burst_gd.png", rp).replace(old_uid, uid)
    s = "".join(l for l in s.splitlines(True) if not l.startswith("uid="))   # （11-07：不写 uid 行，Godot --import 时按规范生成；脚本自己拼的 36 进制 uid 会带 z / 9，被 Godot 改写或撞号，见 asset_lint U1 / U2）
    open(dst, "w", encoding="utf-8", newline="\n").write(s)


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
        acc = (np.abs(c[..., 0] - ACC[0] / 255) < 0.03) & (np.abs(c[..., 1] - ACC[1] / 255) < 0.03) & (np.abs(c[..., 2] - ACC[2] / 255) < 0.03)
        m = (c[..., 3] > 0.5) & (luma >= EMIT_LUMA)   # 11-05 首轮：橙黄热芯也进发光层时整团被吹白，只留最白的芯
        py, px = np.nonzero(m)
        idx = np.arange(len(px))
        if len(idx) > EMIT_MAX:
            idx = idx[np.linspace(0, len(idx) - 1, EMIT_MAX).astype(int)]
        pts = []
        for j in idx:
            r, g_, b = c[py[j], px[j], :3]
            pts.append([int(px[j]), int(py[j]), "%02x%02x%02x" % (int(r * 255), int(g_ * 255), int(b * 255))])
        emit.append(pts)
    name = "pxp_%s%s.png" % (PRE, key.replace("_d-", "_dm"))   # 负方向文件名写 dm（asset_lint N1；游戏 _tex 同样映射）
    Image.fromarray((strip * 255 + 0.5).astype(np.uint8), "RGBA").save(os.path.join(OUT_ART, name), optimize=True)
    write_import(name)
    return key, {"n": len(frames), "fps": fps, "w": int(w), "h": int(h), "ox": int(ox - x0), "oy": int(oy - y0), "loop": loop, "emit": emit}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    ap.add_argument("--jobs", type=int, default=6)
    a = ap.parse_args()
    shutil.copy(SRC, os.path.join(PFX, "src", "fx", "fire", "ak-eyjafjalla-pp.js"))
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
    reg["_doc"] = "docs/259 艾雅法拉转平面帧条（tools/pxplane_bake_eyja.py 生成，勿手改）：键（游戏里加前缀 ey_）对应 art/fx/pxp/pxp_ey_<键>.png；n 帧数、fps、w×h（美术像素）、ox / oy 原点、loop、emit 每帧热芯点 [x, y, 颜色]"
    json.dump(reg, open(OUT_META, "w", encoding="utf-8"), ensure_ascii=False, separators=(",", ":"))
    print("共 %d 件" % (len(reg) - 1))


if __name__ == "__main__":
    main()
