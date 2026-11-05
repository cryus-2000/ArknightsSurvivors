#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""给 GCP 出的三栏对比图（cmp_<招>_e<档>.png，docs/256）在左边拼上「0 原作」一栏（docs/258）。只用 PIL，不开 Godot。

原作参照只在本机（Claude outputs/<干员>_ref/*_keyframes.png，PRTS 解包回放的关键帧拼图，3 列 × 4 行），不进 git、不上 GCP。
按 --pick 选每招取哪一格（行, 列），缩放到三栏图同高，贴在最左。输出 <名>_ref.png，原图不动。

用法：
    python tools/pxplane_refcol.py --cmp "<GCP 下载目录>" --ref "E:/ArknightsSurvivors/Claude outputs/logos_ref" --out "<输出目录>" \
        --pick "atk=logos_attack_ref_keyframes.png:2,2;s1=logos_s2_synecdoche_ref_keyframes.png:2,2;s2=logos_s1_perish_ref_keyframes.png:2,2;s3=logos_s3_acuity_ref_keyframes.png:1,2"
"""
import argparse, glob, os

import numpy as np
from PIL import Image, ImageDraw, ImageFont

FONT = "C:/Windows/Fonts/msyh.ttc"


def panels(path):
    """按深色标题条切出 4 行 × 3 列的格子"""
    im = Image.open(path).convert("RGB")
    a = np.asarray(im).astype(int)
    H, W, _ = a.shape
    dark = a[:, W // 2 - 200:W // 2 + 200].mean(axis=(1, 2)) < 30
    runs, s = [], None
    for y, v in enumerate(dark):
        if v and s is None:
            s = y
        if not v and s is not None:
            if y - s > 4:
                runs.append((s, y))
            s = None
    runs = [r for r in runs if r[0] > 25]   # 去掉页头
    merged = []
    for r in runs:   # 相邻的两段标题条（中间夹一条细线）合并
        if merged and r[0] - merged[-1][1] < 20:
            merged[-1] = (merged[-1][0], r[1])
        else:
            merged.append(r)
    rows = []
    for i, (h0, h1) in enumerate(merged):
        y1 = merged[i + 1][0] if i + 1 < len(merged) else H
        rows.append((h0, h1, y1))
    cw = W // 3
    return im, rows, cw


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--cmp", required=True)
    ap.add_argument("--ref", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--pick", required=True)
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    pick = {}
    for part in a.pick.split(";"):
        k, v = part.split("=")
        f, rc = v.split(":")
        r, c = [int(x) for x in rc.split(",")]
        pick[k] = (f, r, c)
    f30 = ImageFont.truetype(FONT, 30)
    f24 = ImageFont.truetype(FONT, 24)
    for path in sorted(glob.glob(os.path.join(a.cmp, "cmp_*.png"))):
        base = os.path.basename(path)[:-4]
        if base.endswith("_ref"):
            continue
        mv = base.split("_")[1]
        if mv not in pick:
            continue
        f, r, c = pick[mv]
        im, rows, cw = panels(os.path.join(a.ref, f))
        h0, h1, y1 = rows[r]
        cell = im.crop((c * cw, h1 + 10, (c + 1) * cw, y1))
        sheet = Image.open(path).convert("RGB")
        W, H = sheet.size
        ch = H - 56
        cell = cell.resize((int(cell.width * ch / cell.height), ch), Image.LANCZOS)
        out = Image.new("RGB", (W + cell.width + 4, H), (12, 12, 16))
        out.paste(sheet, (cell.width + 4, 0))
        out.paste(cell, (0, 56))
        d = ImageDraw.Draw(out)
        d.text((12, 8), "0 原作（PRTS 解包回放，只作参照）", fill=(230, 230, 230), font=f30)
        d.rectangle((8, 64, 8 + cell.width - 16, 104), fill=(0, 0, 0))
        d.text((16, 68), "原作参照（%s 第 %d 行第 %d 格）" % (f.replace("_keyframes.png", ""), r + 1, c + 1), fill=(255, 255, 255), font=f24)
        out.save(os.path.join(a.out, base + "_ref.png"))
        print(base + "_ref.png", out.size)


if __name__ == "__main__":
    main()
