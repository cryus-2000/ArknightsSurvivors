#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""转平面三栏对比前面补「原作」一栏（docs/256 §4：原作参照图只在本机，不上 GCP、不进 git）。只用 Python，不开 Godot。

原作参照：tools/ref_fx 解包回放出的关键帧拼图 <ref>/<件>/*_keyframes.png（4×2 格，每格一个时刻）。挑每张拼图里「最亮最满」的那一格，
裁到有内容的范围，缩放进一栏，贴在三栏图左边，标「⓪ 原作参照（解包回放，近似）」。

用法：python tools/pxplane_refcol.py --op eyjafjalla --ref "Claude outputs/eyjafjalla_ref" --cmp <GCP 下载目录> --out <交付目录>
"""
import argparse, glob, os

import numpy as np
from PIL import Image, ImageDraw, ImageFont

FONT = "C:/Windows/Fonts/msyh.ttc"
# 每名干员：三栏图前缀 → 原作参照件（子目录）
MAP = {
    "eyjafjalla": {"cmp_atk": "attack_hit", "cmp_s1": "attack_hit", "cmp_s2": "s2_hit", "cmp_s3": "s3_hit", "cmp_link": "s3_hit"},
}


def best_cell(path):
    im = Image.open(path).convert("RGB")
    W, H = im.size
    cw, ch = W // 4, H // 2
    best, bs = None, -1.0
    for j in range(2):
        for i in range(4):
            c = im.crop((i * cw, j * ch + 24, (i + 1) * cw, (j + 1) * ch))
            a = np.asarray(c, dtype=np.float32)
            bg = np.median(a.reshape(-1, 3), axis=0)
            d = np.abs(a - bg).sum(axis=2)
            s = float((d > 60).sum()) + float(d.max()) * 0.0
            if s > bs:
                bs, best = s, (c, d)
    c, d = best
    ys, xs = np.nonzero(d > 40)
    if len(xs):
        pad = 24
        c = c.crop((max(0, xs.min() - pad), max(0, ys.min() - pad), min(c.width, xs.max() + pad), min(c.height, ys.max() + pad)))
    return c


def add_col(cmp_path, ref_img, out_path, x2=False):
    im = Image.open(cmp_path).convert("RGB")
    W3, H = im.size
    head = 56
    colw = (W3 - 8) // 3
    ph = H - head
    r = ref_img.copy()
    k = min(colw / r.width, ph / r.height)
    r = r.resize((max(1, int(r.width * k)), max(1, int(r.height * k))), Image.LANCZOS)
    panel = Image.new("RGB", (colw, ph), (34, 37, 46))
    panel.paste(r, ((colw - r.width) // 2, (ph - r.height) // 2))
    dd = ImageDraw.Draw(panel)
    f = ImageFont.truetype(FONT, 20 if x2 else 22)
    dd.rectangle((0, 0, colw, 34), fill=(12, 12, 16))
    dd.text((10, 5), "0 原作参照（解包回放，近似）", fill=(230, 230, 230), font=f)
    out = Image.new("RGB", (W3 + colw + 4, H), (12, 12, 16))
    out.paste(im.crop((0, 0, W3, head)), (0, 0))
    out.paste(panel, (0, head))
    out.paste(im.crop((0, head, W3, H)), (colw + 4, head))
    out.save(out_path, optimize=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--op", default="eyjafjalla")
    ap.add_argument("--ref", required=True)
    ap.add_argument("--cmp", required=True)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    cache = {}
    for f in sorted(glob.glob(os.path.join(a.cmp, "cmp_*.png"))):
        name = os.path.basename(f)
        pre = next((p for p in MAP[a.op] if name.startswith(p + "_") or name.startswith(p + ".")), None)
        if pre is None:
            continue
        sub = MAP[a.op][pre]
        if sub not in cache:
            ks = glob.glob(os.path.join(a.ref, sub, "*_keyframes.png"))
            if not ks:
                continue
            cache[sub] = best_cell(ks[0])
        add_col(f, cache[sub], os.path.join(a.out, name), name.endswith("_x2.png"))
        print("原作一栏", name, "←", sub)


if __name__ == "__main__":
    main()
