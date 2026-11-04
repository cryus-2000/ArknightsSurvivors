#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""斯卡蒂「转平面」帧条烘焙（docs/246，开关 fx/px_plane）：用 pixelfx 库按目标尺寸逐件生成，裁边后进 game/art/fx/pxp/。

效果源：tools/pixelfx_fx/water/ak-skadi-pp.js（拷进本机 pixelfx 库 build/pixelfx 的 src/fx/water/ 再跑 tools/ak_layers.mjs）。
每件出：
  pxp_<键>.png        单行帧条，色层（直通 alpha，不含光晕）：游戏里当普通物体画，吃场景光（压暗 / 受光）；
  data/pxp_skadi.json 帧数、fps、帧尺寸、原点（脚底 / 地面点），以及每帧的 emit 点表（最亮的热芯像素：进光学层发光通道）。
raw（旧做法对照，fx/px_plane = 2）：色层 + 光层烤成一张（光晕变成颜色），游戏里旋转 + 小数缩放直接贴。

用法（仓库根目录）：python tools/pxplane_bake.py [--only 键前缀]
"""
import argparse, json, os, shutil, subprocess, sys
from concurrent.futures import ThreadPoolExecutor

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PFX = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(ROOT))) if ".claude" in ROOT else os.path.dirname(ROOT), "build", "pixelfx")
if not os.path.isdir(PFX):
    PFX = os.path.join(ROOT, "build", "pixelfx")
SRC = os.path.join(ROOT, "tools", "pixelfx_fx", "water", "ak-skadi-pp.js")
OUT_ART = os.path.join(ROOT, "game", "art", "fx", "pxp")
OUT_META = os.path.join(ROOT, "game", "data", "pxp_skadi.json")
TMP = os.path.join(ROOT, "build", "pxp_bake")
FPS = 15                       # 统一动画时钟（协调人 11-05）：一律 15 fps，时长不对增删帧
DIRS = [-90, -45, 0, 45, 90]   # 平面角；另一半（135 / 180 / -135）游戏里水平翻转
EMIT_LUMA = 0.95               # 色层亮度 ≥ 这个的像素算热芯（只取白热：定帧头部、冠部白沫；精二海绿点缀另算）
EMIT_MAX = 48                  # 每帧 emit 点上限（均匀抽）


def variants():
    v = []
    T = [0, 1, 2]
    # 普攻横扫：半径 56（reach 112 / 2）、弧 2.8；三档体量 / 刀光幕高
    for el in T:
        for d in DIRS:
            for ly in ("up", "gd"):
                v.append(("basic_e%d_%s_d%d" % (el, ly, d), {"part": "ribbon", "layer": ly, "R": [56, 60, 64][el], "span": 2.8, "W": [12, 14, 16][el], "dir": d, "el": el, "dur": 0.3}, 0.34))
    # 迅捷打击·γ型：半径 73（132 × 1.1 / 2）、弧 3.5
    for el in T:
        for d in DIRS:
            for ly in ("up", "gd"):
                v.append(("s1_e%d_%s_d%d" % (el, ly, d), {"part": "ribbon", "layer": ly, "R": [73, 78, 84][el], "span": 3.5, "W": [16, 18, 21][el], "H0": 12, "dir": d, "el": el, "dur": 0.36, "style": "s1"}, 0.4))
    # 全方向旋斩：异乡之舞第三下（62）、涌潮悲歌（92）
    for el in T:
        for ly in ("up", "gd"):
            v.append(("spin_e%d_%s" % (el, ly), {"part": "spin", "layer": ly, "R": [62, 66, 70][el], "W": [12, 14, 16][el], "el": el, "dur": 0.36}, 0.4))
    for ly in ("up", "gd"):
        v.append(("spin_s3_%s" % ly, {"part": "spin", "layer": ly, "R": 92, "W": 20, "H0": 12, "el": 2, "dur": 0.4, "seed": 7, "style": "s3"}, 0.47))
    # 水柱：破浪下劈（精一普攻，落点）/ 跃浪击（S2）
    for el in (1, 2):
        v.append(("leap_e%d_up" % el, {"part": "splash", "layer": "up", "R": 40, "H": [40, 48][el - 1], "el": el}, 0.5))
        v.append(("leap_e%d_gd" % el, {"part": "splash", "layer": "gd", "R": 65, "el": el}, 0.5))
        for d in DIRS:   # S2 跃浪击：前方弧形水墙（立起、卷倒、拍下），不是月牙
            for ly in ("up", "gd"):
                v.append(("s2_e%d_%s_d%d" % (el, ly, d), {"part": "curtain", "layer": ly, "R": 42, "H": [38, 48][el - 1], "span": [1.9, 2.3][el - 1], "dir": d, "el": el, "seed": 5}, 0.56))
    # 涌潮水环 / 悲歌起手：贴地冲击环
    for el in T:
        v.append(("pulse_e%d_gd" % el, {"part": "ring", "layer": "gd", "R": 60, "el": el}, 0.5))
    for el in (0, 1, 2):   # 涌潮（S1 分支一 / 悲歌每秒一圈）：矮水涌往外推
        for ly in ("up", "gd"):
            v.append(("swell_e%d_%s" % (el, ly), {"part": "swell", "layer": ly, "R": 60, "H": [7, 9, 11][el], "el": el, "dur": 0.45}, 0.5))
    for ly in ("up", "gd"):
        v.append(("swell2_%s" % ly, {"part": "swell", "layer": ly, "R": 62, "H": 15, "el": 2, "dur": 0.5, "seed": 8}, 0.56))   # 怒涛第二圈：更高 + 海绿
        v.append(("backwash_%s" % ly, {"part": "backwash", "layer": ly, "R": 75, "el": 2, "dur": 0.75}, 0.76))   # 回澜：海水倒卷回脚下，汇中心冲起水柱
        v.append(("nutao_%s" % ly, {"part": "curtain", "layer": ly, "R": 90, "H": 52, "span": 5.6, "dir": 90, "el": 2, "seed": 11, "dur": 0.6}, 0.66))   # 怒涛：悲歌结束环身大碎浪
    for el in (0, 1, 2):   # late_shape 额外剑气 = 水刃：竖直小浪头（同潮刃意象），按精英档变大；循环
        for d in DIRS:
            v.append(("qi_e%d_up_d%d" % (el, d), {"part": "blade", "layer": "up", "R": [18, 22, 26][el], "H": [10, 13, 16][el], "dir": d, "el": el, "seed": 12}, 0.4))
    for ly in ("up", "gd"):   # 连携技「落潮横扫」：整圈白刃大月牙 + 脚下一圈矮浪往外推
        v.append(("combo_spin_%s" % ly, {"part": "spin", "layer": ly, "R": 58, "W": 18, "H0": 12, "el": 1, "dur": 0.4, "seed": 13, "style": "s1"}, 0.47))
        v.append(("combo_swell_%s" % ly, {"part": "swell", "layer": ly, "R": 66, "H": 13, "el": 1, "dur": 0.42, "seed": 14}, 0.5))
    v.append(("s3cast_gd", {"part": "ring", "layer": "gd", "R": 92, "el": 2, "seed": 9}, 0.5))
    v.append(("s3cast_up", {"part": "splash", "layer": "up", "R": 70, "H": 90, "el": 2, "seed": 9}, 0.56))   # 悲歌起手：身边冲起的大水柱
    v.append(("pool_gd", {"part": "pool", "layer": "gd", "R": 70, "seed": 6}, 0.4))   # 悲歌持续：脚下积水（循环）
    # 潮刃（精二）/ 跃浪浪墙：竖直浪头（循环 0.3 秒）
    for d in DIRS:
        for ly in ("up", "gd"):
            v.append(("blade_%s_d%d" % (ly, d), {"part": "blade", "layer": ly, "R": 26, "H": 16, "dir": d, "el": 2}, 0.4))
    for el in (1, 2):   # 「跃浪」浪墙：推进途中每两拍在浪头生成一道小碎浪（11-05 用户「海浪溃散的感觉」，不再是整块平移的浪幕）
        for d in DIRS:
            for ly in ("up", "gd"):
                v.append(("wallbrk_e%d_%s_d%d" % (el, ly, d), {"part": "curtain", "layer": ly, "R": 36, "H": [24, 30][el - 1], "span": 2.0, "dir": d, "el": el, "seed": 4 + d % 7, "dur": 0.42}, 0.47))
    # raw：旧做法（正俯视 / 正圆、光晕烤进颜色），游戏里旋转 + 小数缩放
    for el in T:
        v.append(("raw_basic_e%d" % el, {"part": "ribbon", "view": "raw", "R": 56, "span": 2.8, "W": [12, 14, 16][el], "dir": 0, "el": el, "dur": 0.3}, 0.34))
        v.append(("raw_s1_e%d" % el, {"part": "ribbon", "view": "raw", "R": 73, "span": 3.5, "W": [16, 18, 21][el], "dir": 0, "el": el, "dur": 0.36}, 0.4))
        v.append(("raw_spin_e%d" % el, {"part": "spin", "view": "raw", "R": 62, "W": [12, 14, 16][el], "el": el, "dur": 0.36}, 0.4))
        v.append(("raw_ring_e%d" % el, {"part": "ring", "view": "raw", "R": 60, "el": el}, 0.5))
    for el in (1, 2):
        v.append(("raw_splash_e%d" % el, {"part": "splash", "view": "raw", "R": 56, "H": [60, 74][el - 1], "el": el, "seed": 5}, 0.56))
    v.append(("raw_blade", {"part": "blade", "view": "raw", "R": 26, "H": 16, "el": 2}, 0.4))
    return v


def render(key, opts, dur):
    d = os.path.join(TMP, key)
    os.makedirs(d, exist_ok=True)
    o = dict(opts)
    o.setdefault("dur", min(0.46, dur - 0.04))
    p = subprocess.run(["node", "tools/ak_layers.mjs", "water/ak-skadi-pp", "--out", d, "--fps", str(FPS), "--opts", json.dumps(o)], cwd=PFX, capture_output=True, text=True)
    if p.returncode != 0:
        raise RuntimeError(key + ": " + p.stderr[-400:])
    return key, d, dur


def bake(key, d, dur):
    meta = json.load(open(os.path.join(d, "meta.json")))
    fw, fh = meta["frameSize"]
    n = meta["frames"]
    fps = meta["fps"]
    ox, oy = meta["pivot"]
    col = np.asarray(Image.open(os.path.join(d, "color.png")).convert("RGBA")).astype(np.float32) / 255.0
    lit = np.asarray(Image.open(os.path.join(d, "light.png")).convert("RGB")).astype(np.float32) / 255.0
    loop = key.startswith(("blade_", "raw_blade", "pool", "qi_"))
    nf = min(n, int(round(dur * fps)))
    if loop:
        nf = int(round(0.4 * fps))   # 循环 0.4 秒 = 6 帧
    frames = [col[:, i * fw:(i + 1) * fw] for i in range(nf)]
    lights = [lit[:, i * fw:(i + 1) * fw] for i in range(nf)]
    raw = key.startswith("raw_")
    if raw:   # 光晕烤进颜色（旧帧条的做法）：rgb = 色 × a + 光，alpha = max(a, 光亮度)
        out = []
        for c, l in zip(frames, lights):
            a = c[..., 3:4]
            rgb = np.clip(c[..., :3] * a + l * 0.9, 0, 1)
            al = np.clip(np.maximum(a[..., 0], l.max(axis=2) * 0.9), 0, 1)
            safe = np.where(al > 0.001, al, 1.0)[..., None]
            out.append(np.concatenate([np.clip(rgb / safe, 0, 1), al[..., None]], axis=2))
        frames = out
    # 去掉空的尾帧（一次性件）
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
        acc = (np.abs(c[..., 0] - 0x5f / 255) < 0.02) & (np.abs(c[..., 1] - 0xf0 / 255) < 0.02)
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
    Image.fromarray((strip * 255 + 0.5).astype(np.uint8), "RGBA").save(os.path.join(OUT_ART, "pxp_%s.png" % key), optimize=True)
    return key, {"n": len(frames), "fps": fps, "w": int(w), "h": int(h), "ox": int(ox - x0), "oy": int(oy - y0), "loop": loop, "emit": emit}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    ap.add_argument("--jobs", type=int, default=6)
    a = ap.parse_args()
    shutil.copy(SRC, os.path.join(PFX, "src", "fx", "water", "ak-skadi-pp.js"))
    os.makedirs(OUT_ART, exist_ok=True)
    os.makedirs(TMP, exist_ok=True)
    vs = [x for x in variants() if x[0].startswith(a.only)]
    reg = json.load(open(OUT_META, encoding="utf-8")) if os.path.exists(OUT_META) and a.only else {}
    with ThreadPoolExecutor(a.jobs) as ex:
        rs = list(ex.map(lambda x: render(*x), vs))
    for key, d, dur in rs:
        k, m = bake(key, d, dur)
        if m is None:
            print("空", k)
            continue
        reg[k] = m
        print("%-22s %2d 帧 %3d×%3d emit %d" % (k, m["n"], m["w"], m["h"], max((len(e) for e in m["emit"]), default=0)))
    reg = {k: reg[k] for k in sorted(reg)}
    reg["_doc"] = "docs/246 斯卡蒂转平面帧条（tools/pxplane_bake.py 生成，勿手改）：n 帧数、fps、w×h 帧尺寸（美术像素）、ox / oy 原点（脚底地面点）、loop、emit 每帧热芯点 [x, y, 颜色]"
    json.dump(reg, open(OUT_META, "w", encoding="utf-8"), ensure_ascii=False, separators=(",", ":"))
    print("共 %d 件" % (len(reg) - 1))


if __name__ == "__main__":
    main()
