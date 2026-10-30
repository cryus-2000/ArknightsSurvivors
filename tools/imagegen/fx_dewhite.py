# -*- coding: utf-8 -*-
"""特效贴图去白（docs/208 H4，10-31）：近白 / 低饱和像素按明度分位映射到该干员主色 5 级色阶，白只留最亮约 4% 的芯；
饱和的像素（原本就有颜色的点缀，如塞雷娅结晶里的琥珀）不动。透明度不动，帧条宽高不动（纯换色）。

用法：python tools/imagegen/fx_dewhite.py <名> <色阶名> [--core 0.04] [--sat 0.25] [--out <新名>]
      名 = game/art/fx/<名>@2x.png；--out 另存为新贴图（做变体）；不给就覆盖原图。
色阶见 RAMPS（暗 → 亮，最后一级是芯，亮度 ≤ 0.9）。"""
import argparse, colorsys, sys
from pathlib import Path
import numpy as np
from PIL import Image

RAMPS = {
    "irene": ["#1E2A4A", "#35588A", "#5E92C4", "#9CC6E8", "#D2E8F2"],      # 艾丽妮：冷钢蓝（原月弧的蓝边加饱和）
    "lappland": ["#1C2A48", "#34568C", "#6690C8", "#A2C6E6", "#D4E6F2"],   # 拉普兰德：冷蓝剑气
    "saria_ice": ["#22344A", "#456E8C", "#7EA6BE", "#B4D0DC", "#DCE8EC"],  # 塞雷娅结晶：冰蓝暗面（琥珀点缀保留）
    "saria_amber": ["#3A2A1C", "#7A5A34", "#B8925A", "#DCC08C", "#ECDCB8"],  # 塞雷娅结晶变体：暖琥珀
    "saria_teal": ["#1C3836", "#3C6A64", "#72A49A", "#A8CCC2", "#D6E8E2"],  # 塞雷娅结晶变体：青灰
    "suzuran": ["#5A3A12", "#A06E2A", "#CE9C46", "#E6C274", "#F0DCAA"],     # 铃兰九尾：狐火金
}


def hexc(h):
    return [int(h[i:i + 2], 16) for i in (1, 3, 5)]


def dewhite(src, ramp, core=0.04, sat_keep=0.25):
    im = Image.open(src).convert("RGBA")
    a = np.asarray(im).astype(float)
    rgb = a[..., :3] / 255.0
    al = a[..., 3]
    mx = rgb.max(-1)
    mn = rgb.min(-1)
    sat = np.where(mx > 0, (mx - mn) / np.maximum(mx, 1e-6), 0.0)
    lum = 0.2126 * rgb[..., 0] + 0.7152 * rgb[..., 1] + 0.0722 * rgb[..., 2]
    m = (al > 0) & (sat < sat_keep) & (lum > 0.15)   # 深色描边不动
    if not m.any():
        return im, 0
    # 按明度数值分位分档（保留原图的明暗结构，不出噪点）；同亮度大片落进芯（超过 2 × core）时整片降一档，芯只留真正最亮的少数
    q = lum[m]
    cuts = np.quantile(q, [0.25, 0.55, 0.8, 1.0 - core])
    idx = np.digitize(lum, cuts)
    top = m & (idx >= 4)
    if top.sum() > 2 * core * m.sum():
        idx[top] = 3
    pal = np.array([hexc(h) for h in RAMPS[ramp]], float)
    out = a.copy()
    out[m, :3] = pal[idx[m]]
    # 饱和像素也压一下亮度上限（≤ 0.9）
    keep = (al > 0) & ~m
    cap = 0.9 * 255
    over = out[..., :3].max(-1)
    sc = np.where(keep & (over > cap), cap / np.maximum(over, 1), 1.0)
    out[..., :3] *= sc[..., None]
    return Image.fromarray(out.clip(0, 255).astype(np.uint8)), int(m.sum())


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("name"); ap.add_argument("ramp", choices=sorted(RAMPS))
    ap.add_argument("--core", type=float, default=0.04); ap.add_argument("--sat", type=float, default=0.25)
    ap.add_argument("--out", default="")
    a = ap.parse_args()
    fx = Path(__file__).resolve().parents[2] / "game" / "art" / "fx"
    src = fx / f"{a.name}@2x.png"
    im, n = dewhite(src, a.ramp, a.core, a.sat)
    dst = fx / f"{(a.out or a.name)}@2x.png"
    im.save(dst)
    print(dst.name, "改色像素", n)


if __name__ == "__main__":
    main()
