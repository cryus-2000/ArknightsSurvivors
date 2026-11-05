#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""流明终结技「只改颜色」（11-05 用户「流明能不能只是在原本的改个颜色？」，开关 ult/px_plane_lumen）用的两张帧条换色：
  fx_beacon_ignite@2x.png（脚下灯塔点亮，8 帧）、fx_lumen_beam_flare@2x.png（光柱顶上星芒，5 帧）
暖黄 → 普攻 / 技能定稿的钢蓝 7 阶（house.js OP.lumen）：按亮度映射到 #2a5282 … #ffffff，alpha（含原版的棋盘格半透明）一个像素不动；
点亮帧条正中心最亮的一小团换成灯火橙 #ff9640（「灯芯留一点灯火橙」）。输出 *_lm@2x.png，帧数 / 尺寸 / 原点同原图。
用法：python tools/ult_lumen_recolor.py
"""
import os

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FX = os.path.join(ROOT, "game", "art", "fx")
RAMP = np.array([[0x2a, 0x52, 0x82], [0x42, 0x85, 0xad], [0x7f, 0xb2, 0xd6], [0xc4, 0xe0, 0xf2], [0xff, 0xff, 0xff]], np.float32)
AC = np.array([0xff, 0x96, 0x40], np.float32)


def recolor(name, n, core=False):
    im = Image.open(os.path.join(FX, name + "@2x.png")).convert("RGBA")
    a = np.asarray(im).astype(np.float32)
    lum = (a[..., 0] * 0.3 + a[..., 1] * 0.55 + a[..., 2] * 0.15) / 255.0
    idx = np.clip((lum - 0.35) / 0.62, 0, 1) * (len(RAMP) - 1)
    lo = np.floor(idx).astype(int)
    hi = np.minimum(lo + 1, len(RAMP) - 1)
    f = (idx - lo)[..., None]
    rgb = RAMP[lo] * (1 - f) + RAMP[hi] * f
    if core:   # 每帧正中心最亮的一小团 → 灯火橙
        fw = im.width // n
        yy, xx = np.mgrid[0:im.height, 0:im.width]
        cx = (xx % fw) - fw / 2
        cy = yy - im.height / 2
        m = (np.hypot(cx, cy) < fw * 0.035) & (lum > 0.9) & (a[..., 3] > 128)
        rgb[m] = AC
    out = np.concatenate([np.clip(rgb, 0, 255), a[..., 3:4]], axis=2).astype(np.uint8)
    p = os.path.join(FX, name + "_lm@2x.png")
    Image.fromarray(out, "RGBA").save(p, optimize=True)
    print(p, im.size)


if __name__ == "__main__":
    recolor("fx_beacon_ignite", 8, core=True)
    recolor("fx_lumen_beam_flare", 5)
