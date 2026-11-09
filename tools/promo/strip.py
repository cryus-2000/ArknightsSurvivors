# -*- coding: utf-8 -*-
"""看片细节：python tools/promo/strip.py <clips 下 mp4> <起始帧> [张数 24] [间隔帧 10] [输出名]  → work/strip_<名>.jpg（6 列，标帧号）"""
import os, subprocess, sys
from PIL import Image, ImageDraw
from pv import CLIPS, WORK, ffmpeg
mp4, f0 = sys.argv[1], int(sys.argv[2])
n = int(sys.argv[3]) if len(sys.argv) > 3 else 24
st = int(sys.argv[4]) if len(sys.argv) > 4 else 10
name = sys.argv[5] if len(sys.argv) > 5 else "%s_%d" % (mp4[:12], f0)
raw = subprocess.run([ffmpeg(), "-v", "error", "-ss", "%.3f" % (f0 / 60), "-i", os.path.join(CLIPS, mp4), "-vf", "fps=%g,scale=384:216" % (60 / st),
                      "-frames:v", str(n), "-f", "rawvideo", "-pix_fmt", "rgb24", "-"], capture_output=True).stdout
k = len(raw) // (384 * 216 * 3)
sh = Image.new("RGB", (384 * 6, 216 * ((k + 5) // 6)))
d = ImageDraw.Draw(sh)
for i in range(k):
    sh.paste(Image.frombuffer("RGB", (384, 216), raw[i * 248832:(i + 1) * 248832]), ((i % 6) * 384, (i // 6) * 216))
    d.text(((i % 6) * 384 + 5, (i // 6) * 216 + 5), "f%d" % (f0 + i * st), fill=(255, 255, 0))
out = os.path.join(WORK, "strip_%s.jpg" % name)
sh.save(out, quality=80)
print(out)
