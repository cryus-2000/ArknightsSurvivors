#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""实机局的成长节点提示选前 / 选后同帧对照（docs/310 §8）：同一局 node_cue 关 / 开各跑一遍、按帧截图，
逐帧算差，挑差最大的若干帧（相邻帧至少隔 --gap 帧），每帧以差异重心裁 1 倍原尺寸的 --w × --h 小块，上排选前、下排选后拼一张。

用法：python3 tools/cue_real_sheet.py <选前目录> <选后目录> <输出.png> [--top 6] [--gap 30] [--w 420] [--h 300]
"""
import argparse, glob, os, re
from PIL import Image, ImageChops, ImageDraw


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("d0")
    ap.add_argument("d1")
    ap.add_argument("out")
    ap.add_argument("--top", type=int, default=6)
    ap.add_argument("--gap", type=int, default=30)
    ap.add_argument("--w", type=int, default=420)
    ap.add_argument("--h", type=int, default=300)
    a = ap.parse_args()
    fr = lambda p: int(re.findall(r"(\d+)", os.path.basename(p))[-1])
    f0 = {fr(p): p for p in glob.glob(os.path.join(a.d0, "*.png"))}
    f1 = {fr(p): p for p in glob.glob(os.path.join(a.d1, "*.png"))}
    sc = []
    for k in sorted(set(f0) & set(f1)):
        x = ImageChops.difference(Image.open(f0[k]).convert("RGB"), Image.open(f1[k]).convert("RGB")).convert("L").point(lambda v: 255 if v > 40 else 0)
        bb = x.getbbox()
        if not bb:
            continue
        n = x.histogram()[255]
        sc.append((n, k, bb))
    sc.sort(reverse=True)
    pick = []
    for n, k, bb in sc:
        if all(abs(k - q[1]) >= a.gap for q in pick):
            pick.append((n, k, bb))
        if len(pick) >= a.top:
            break
    pick.sort(key=lambda q: q[1])
    print("帧数 %d，有差 %d，挑 %s" % (len(set(f0) & set(f1)), len(sc), [(k, n) for n, k, bb in pick]))
    if not pick:
        return
    W, H = a.w, a.h
    sheet = Image.new("RGB", (W * len(pick) + 4 * (len(pick) - 1), H * 2 + 4), (0, 0, 0))
    for c, (n, k, bb) in enumerate(pick):
        im0 = Image.open(f0[k]).convert("RGB")
        cx, cy = (bb[0] + bb[2]) // 2, (bb[1] + bb[3]) // 2
        x0 = max(0, min(im0.width - W, cx - W // 2))
        y0 = max(0, min(im0.height - H, cy - H // 2))
        for row, im in enumerate((im0, Image.open(f1[k]).convert("RGB"))):
            cr = im.crop((x0, y0, x0 + W, y0 + H))
            ImageDraw.Draw(cr).text((4, 4), ("before" if row == 0 else "after") + " f%d" % k, fill=(255, 255, 0))
            sheet.paste(cr, (c * (W + 4), row * (H + 4)))
    sheet.save(a.out)


if __name__ == "__main__":
    main()
