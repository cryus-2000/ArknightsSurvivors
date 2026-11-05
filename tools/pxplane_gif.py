#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""转平面看图：把几组图鉴演示连拍（tools/pxplane_shots.py demo 的 f_*.png）并排做成 GIF（docs/260）。不开 Godot。
用法：python tools/pxplane_gif.py <输出.gif> <标签1>=<帧目录1> [<标签2>=<帧目录2> ...] [--crop x,y,w,h] [--fps 15]"""
import argparse, glob, os
from PIL import Image, ImageDraw, ImageFont


def font(sz):
    for p in ("C:/Windows/Fonts/msyh.ttc", "msyh.ttc", "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc"):
        try:
            return ImageFont.truetype(p, sz)
        except OSError:
            pass
    return ImageFont.load_default()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out")
    ap.add_argument("cols", nargs="+")
    ap.add_argument("--crop", default="320,180,640,360")
    ap.add_argument("--fps", type=float, default=15.0)
    a = ap.parse_args()
    x, y, w, h = [int(v) for v in a.crop.split(",")]
    cols = []
    for c in a.cols:
        lab, d = c.split("=", 1)
        cols.append((lab, sorted(glob.glob(os.path.join(d, "f_*.png")))))
    n = min(len(fs) for _, fs in cols)
    f = font(22)
    frames = []
    for i in range(n):
        sheet = Image.new("RGB", (w * len(cols) + 4 * (len(cols) - 1), h), (12, 12, 16))
        for k, (lab, fs) in enumerate(cols):
            im = Image.open(fs[i]).convert("RGB").crop((x, y, x + w, y + h))
            d = ImageDraw.Draw(im)
            d.rectangle((6, 6, 18 + int(d.textlength(lab, font=f)), 38), fill=(0, 0, 0))
            d.text((12, 8), lab, fill=(255, 255, 255), font=f)
            sheet.paste(im, (k * (w + 4), 0))
        frames.append(sheet.quantize(colors=255, method=Image.MEDIANCUT))
    os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
    frames[0].save(a.out, save_all=True, append_images=frames[1:], duration=int(1000 / a.fps), loop=0, optimize=False)
    print("GIF", a.out, n, "帧", "%.1f MB" % (os.path.getsize(a.out) / 1048576.0))


if __name__ == "__main__":
    main()
