#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""艾雅法拉终结技「海底火山」只改颜色（docs/259 §8，开关 ult/px_plane_eyjafjalla，缺省关）。

11-06 协调人转用户口径：原版的画面、节奏、体量、音效全部不动，只把配色对齐到这次普攻 / 技能定稿的那套熔岩色阶。
做法：原版贴图（fx_ey_*@2x.png）里「暖色」像素（红 / 橙 / 黄，饱和度够）按亮度映射到她的熔岩 9 阶，纯红 / 深红一律落到偏橙的暖红上（红色只留给危险）；
灰黑的岩壳、蒸汽、浮石暗面不动。输出同目录 fx_ey_<名>_pxe@2x.png（+ .import），游戏里开关开着时换用。程序色（粒子 / 灯 / 形状）在 ult_moves_b._eyc 里用同一个映射。
用法：python tools/ult_eyja_recolor.py [--preview <png>]
"""
import argparse, hashlib, os, random

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FX = os.path.join(ROOT, "game", "art", "fx")
NAMES = ["fount", "bomb", "pool", "pumice", "steam", "fork1", "fork2", "fork3", "fork4"]
# 熔岩 9 阶（暗 → 亮）：house.js OP.eyjafjalla 7 阶 + 橙黄热芯，同普攻 / 技能帧条
RAMP = np.array([[0x1a, 0x07, 0x05], [0x4a, 0x11, 0x0a], [0x8f, 0x1d, 0x0d], [0xd2, 0x33, 0x0f], [0xf6, 0x56, 0x1a], [0xff, 0x8a, 0x3d], [0xff, 0xaa, 0x45], [0xff, 0xd5, 0x9a], [0xff, 0xf0, 0xe0]], np.float32)


RAMP_L = (0.2126 * RAMP[:, 0] + 0.7152 * RAMP[:, 1] + 0.0722 * RAMP[:, 2]) / 255.0


def remap(rgb):
    """rgb: (..., 3) 0–255 float。暖色像素换到熔岩阶上「亮度相同」的位置（只换色相、不提亮也不压暗）；
    纯红这类亮度低但很亮的饱和色按 0.35·最大通道 托底，免得发光的熔岩被压成暗红。灰黑岩壳 / 蒸汽 / 暗褐岩面原样"""
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    mx = np.maximum(np.maximum(r, g), b)
    mn = np.minimum(np.minimum(r, g), b)
    sat = (mx - mn) / np.maximum(mx, 1.0)
    warm = (r >= g) & (g >= b - 8) & (sat > 0.3) & ((mx > 120) | (sat > 0.75))
    lum = (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255.0
    key = np.maximum(lum, 0.35 * mx / 255.0)
    t = np.interp(key, RAMP_L, np.arange(len(RAMP), dtype=np.float32))
    i0 = np.floor(t).astype(int)
    i1 = np.minimum(i0 + 1, len(RAMP) - 1)
    f = (t - i0)[..., None]
    mapped = RAMP[i0] * (1 - f) + RAMP[i1] * f
    out = rgb.copy()
    out[warm] = mapped[warm]
    return out


def write_import(png):
    tmpl = open(os.path.join(FX, "fx_ey_pool@2x.png.import"), encoding="utf-8").read()
    dst = png + ".import"
    if os.path.exists(dst):
        return
    name = os.path.basename(png)
    rp = "res://art/fx/" + name
    h = hashlib.md5(rp.encode()).hexdigest()
    old_uid = tmpl.split('uid="')[1].split('"')[0]
    uid = "uid://" + "".join(random.choice("abcdefghijklmnopqrstuvwxy0123456789") for _ in range(13))
    old_path = tmpl.split('source_file="')[1].split('"')[0]
    old_dest = tmpl.split('path="')[1].split('"')[0]
    s = tmpl.replace(old_uid, uid).replace(old_dest, "res://.godot/imported/%s-%s.ctex" % (name, h)).replace(old_path, rp)
    s = "".join(l for l in s.splitlines(True) if not l.startswith("uid="))   # （11-07：不写 uid 行，Godot --import 时按规范生成；脚本自己拼的 36 进制 uid 会带 z / 9，被 Godot 改写或撞号，见 asset_lint U1 / U2）
    open(dst, "w", encoding="utf-8", newline="\n").write(s)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--preview", default="")
    a = ap.parse_args()
    rows = []
    for n in NAMES:
        src = os.path.join(FX, "fx_ey_%s@2x.png" % n)
        im = np.asarray(Image.open(src).convert("RGBA")).astype(np.float32)
        out = im.copy()
        out[..., :3] = remap(im[..., :3])
        dst = os.path.join(FX, "fx_ey_%s_pxe@2x.png" % n)
        Image.fromarray(np.clip(out, 0, 255).astype(np.uint8), "RGBA").save(dst, optimize=True)
        write_import(dst)
        rows.append((Image.open(src).convert("RGBA"), Image.open(dst).convert("RGBA")))
        print(n, "→", os.path.basename(dst))
    if a.preview:
        H = 220
        cells = []
        for s, d in rows:
            k = H / max(s.height, 1)
            w = max(1, int(s.width * k))
            cells.append((s.resize((w, H), Image.NEAREST), d.resize((w, H), Image.NEAREST)))
        W = sum(c[0].width + 8 for c in cells)
        sheet = Image.new("RGBA", (W, H * 2 + 8), (34, 38, 46, 255))
        x = 0
        for s, d in cells:
            sheet.alpha_composite(s, (x, 0))
            sheet.alpha_composite(d, (x, H + 8))
            x += s.width + 8
        sheet.save(a.preview)


if __name__ == "__main__":
    main()
