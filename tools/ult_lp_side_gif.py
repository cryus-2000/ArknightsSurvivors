#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""拉普兰德终结技原版 / 新版并排 GIF（docs/273 §8）：读 GCP 上 tools/ult_rec.py 录的两段实机录像（同种子、同参数，开关 ult/px_plane_lappland 0 / 1），
按「冲击帧」那一刻对齐（整屏最亮的一帧），截出前后各一段，左原版右新版，裁到主体附近，15 fps。只用 Python，不开 Godot。
新版开着慢动作，冲击帧之后比原版长；并排时原版那边冲击帧后用最后一帧补齐。
用法：python tools/ult_lp_side_gif.py --orig <原版.mp4> --new <新版.mp4> --out <gif> [--pre 1.4] [--post 2.2]"""
import argparse, os, subprocess, tempfile

import imageio_ffmpeg
import numpy as np
from PIL import Image, ImageDraw, ImageFont

FONT = "C:/Windows/Fonts/msyh.ttc"


def frames(mp4, fps):
    d = tempfile.mkdtemp()
    subprocess.run([imageio_ffmpeg.get_ffmpeg_exe(), "-y", "-loglevel", "error", "-i", mp4, "-vf", "fps=%d" % fps, os.path.join(d, "f_%04d.png")], check=True)
    fs = sorted(os.listdir(d))
    return [Image.open(os.path.join(d, f)).convert("RGB") for f in fs]


def flash_idx(fr):
    lum = [float(np.asarray(f, dtype=np.float32).mean()) for f in fr]
    return int(np.argmax(lum))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--orig", required=True)
    ap.add_argument("--new", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--fps", type=int, default=15)
    ap.add_argument("--pre", type=float, default=2.6)
    ap.add_argument("--post", type=float, default=2.4)
    ap.add_argument("--crop", default="0.18,0.12,0.86,0.86", help="裁剪框（相对宽高：左,上,右,下）")
    ap.add_argument("--w", type=int, default=560)
    a = ap.parse_args()
    fo, fn = frames(a.orig, a.fps), frames(a.new, a.fps)
    io, inn = flash_idx(fo), flash_idx(fn)
    pre, post = int(a.pre * a.fps), int(a.post * a.fps)
    W, H = fo[0].size
    l, t, r, b = [float(x) for x in a.crop.split(",")]
    box = (int(l * W), int(t * H), int(r * W), int(b * H))
    sc = a.w / (box[2] - box[0])
    ch = int((box[3] - box[1]) * sc)
    font = ImageFont.truetype(FONT, 18)
    out = []
    for k in range(-pre, post):
        po = fo[max(0, min(len(fo) - 1, io + k))]
        pn = fn[max(0, min(len(fn) - 1, inn + k))]
        sheet = Image.new("RGB", (a.w * 2 + 6, ch + 34), (12, 12, 16))
        d = ImageDraw.Draw(sheet)
        for i, (im, lab) in enumerate([(po, "原版（ult/px_plane 关）"), (pn, "新版：紫白配色 + 收尾大爆 / 崩解 / 慢动作")]):
            sheet.paste(im.crop(box).resize((a.w, ch), Image.LANCZOS), (i * (a.w + 6), 34))
            d.text((i * (a.w + 6) + 8, 6), lab, fill=(235, 230, 250), font=font)
        out.append(sheet)
    pal = out[len(out) // 2].quantize(colors=255, method=Image.MEDIANCUT)
    q = [f.quantize(palette=pal, dither=Image.NONE) for f in out]
    q[0].save(a.out, save_all=True, append_images=q[1:], duration=int(1000 / a.fps), loop=0, disposal=1)
    print(a.out, len(q), "帧", "%.1f MB" % (os.path.getsize(a.out) / 1048576), "冲击帧 原版第 %d / 新版第 %d 帧" % (io, inn))


if __name__ == "__main__":
    main()
