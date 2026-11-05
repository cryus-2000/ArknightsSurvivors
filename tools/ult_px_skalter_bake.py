#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""浊心斯卡蒂终结技配色对齐（docs/260 §10）：把原版红色贴图（光束 / 爆闪 / 爆炸 / 领域花纹）按亮度重映射到深海蓝 7 阶（SK_B），
透明度、形状、帧排布一律不动；接近白的像素保留白，饱和度很低的灰保持灰（只换色相）。游戏里 ult/px_plane = 1 时换用 *_db 版。
用法：python tools/ult_px_skalter_bake.py"""
import os
import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FX = os.path.join(ROOT, "game", "art", "fx")
SK_B = np.array([(0x07, 0x0d, 0x22), (0x0e, 0x1d, 0x4a), (0x18, 0x34, 0x86), (0x27, 0x52, 0xc4), (0x4f, 0x80, 0xec), (0x9d, 0xbc, 0xff), (0xff, 0xff, 0xff)], np.float32) / 255.0
NAMES = ["fx_sk_beam", "fx_sk_flash", "fx_sk_blast", "fx_ult_skalter_domain_back"]


def ramp(l):
    x = np.clip(l, 0.0, 1.0) * (len(SK_B) - 1)
    i = np.clip(np.floor(x).astype(int), 0, len(SK_B) - 2)
    f = (x - i)[..., None]
    return SK_B[i] * (1 - f) + SK_B[i + 1] * f


def main():
    for n in NAMES:
        src = os.path.join(FX, n + "@2x.png")
        im = np.asarray(Image.open(src).convert("RGBA")).astype(np.float32) / 255.0
        rgb, a = im[..., :3], im[..., 3:4]
        mx, mn = rgb.max(axis=2), rgb.min(axis=2)
        sat = np.where(mx > 1e-4, (mx - mn) / np.maximum(mx, 1e-4), 0.0)
        lum = 0.2126 * rgb[..., 0] + 0.7152 * rgb[..., 1] + 0.0722 * rgb[..., 2]
        v = np.clip(mx * 0.75 + lum * 0.6, 0.0, 1.0)   # 红色的亮度主要在 R 通道，按最大值 + 亮度取明暗
        blue = ramp(v)
        k = np.clip(sat * 1.6, 0.0, 1.0)[..., None]   # 越饱和越换成蓝；接近白 / 灰的保留原色
        out = rgb * (1 - k) + blue * k
        Image.fromarray((np.concatenate([np.clip(out, 0, 1), a], axis=2) * 255 + 0.5).astype(np.uint8), "RGBA").save(os.path.join(FX, n + "_db@2x.png"), optimize=True)
        print(n + "_db", im.shape[1], "x", im.shape[0])


if __name__ == "__main__":
    main()
