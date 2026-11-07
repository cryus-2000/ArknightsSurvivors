# -*- coding: utf-8 -*-
"""看片：clips 下各段 mp4 每 step 秒抽一张缩略图拼联络表（标 帧号 / 游戏秒），并列出 pv.log 里落在这段的事件（终结技、冲击帧、选卡、灯标、刷怪）。

  python tools/promo/review.py <局>[,<局>…] [--step 0.5] [--only seg_03]
输出：<主仓库>/Claude outputs/pv_1108/work/review_<局>_<段>.jpg；事件打印到终端
"""
import glob, json, os, re, subprocess, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from pv import CLIPS, WORK, ffmpeg, FPS
import fx


def events(run):
    p = os.path.join(CLIPS, "%s_pv.log" % run)
    ev = []
    if os.path.exists(p):
        for l in open(p, encoding="utf-8", errors="replace"):
            if l.startswith(("PVEV", "PVSEG", "PVEND", "PVEXT")):
                ev.append(l.strip())
    return ev


def sheet(mp4, step, out):
    js = mp4[:-4] + ".sfx.json"
    ts = json.load(open(js, encoding="utf-8"))["ts"] if os.path.exists(js) else []
    tw, th = 384, 216
    raw = subprocess.run([ffmpeg(), "-v", "error", "-i", mp4, "-vf", "fps=%g,scale=%d:%d" % (1 / step, tw, th), "-f", "rawvideo", "-pix_fmt", "rgb24", "-"],
                         capture_output=True).stdout
    n = len(raw) // (tw * th * 3)
    cols = 8
    im = Image.new("RGB", (cols * tw, ((n + cols - 1) // cols) * th), (0, 0, 0))
    d = ImageDraw.Draw(im)
    f = fx.font(20)
    for i in range(n):
        fr = Image.frombuffer("RGB", (tw, th), raw[i * tw * th * 3:(i + 1) * tw * th * 3])
        x, y = (i % cols) * tw, (i // cols) * th
        im.paste(fr, (x, y))
        k = int(round(i * step * FPS))
        lab = "f%d  %.2fs" % (k, ts[k]) if k < len(ts) else "f%d" % k
        d.text((x + 6, y + 4), lab, font=f, fill=(255, 255, 0), stroke_width=2, stroke_fill=(0, 0, 0))
    im.save(out, quality=80)
    return n, len(ts)


if __name__ == "__main__":
    runs = sys.argv[1].split(",")
    step = float(sys.argv[sys.argv.index("--step") + 1]) if "--step" in sys.argv else 0.5
    only = sys.argv[sys.argv.index("--only") + 1] if "--only" in sys.argv else ""
    os.makedirs(WORK, exist_ok=True)
    for run in runs:
        for l in events(run):
            print(run, l)
        for mp4 in sorted(glob.glob(os.path.join(CLIPS, "%s_seg_*.mp4" % run))):
            if only and only not in mp4:
                continue
            out = os.path.join(WORK, "review_" + os.path.basename(mp4)[:-4] + ".jpg")
            n, nt = sheet(mp4, step, out)
            print(out, n, "张", nt, "帧")
