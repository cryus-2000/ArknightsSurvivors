# -*- coding: utf-8 -*-
"""片头 70–77 小节整段（用户 11-08 按 pv-style 参考板：礁石 → 鱼群 → 水母 → 海嗣潮，77 drop 闪白）。
  70–73  第一镜（pv_open1.py 出的帧，原样接入）
  73–74  入水 · 鱼群：镜头往下沉（画面上移），73 切点一下水色闪
  74–75  水母：缓推向右三分线上的水母
  75–77  海嗣潮：从近处拉远（1.4 → 1.0，expo_out），最后 8 帧闪白接 77 drop
三段用 Veo 从参考图生成的 4 秒动态，各取一段原速；镜头运动后期做，最后统一 4×4 像素化。
  python tools/promo/pv_open.py <第一镜帧目录> <鱼群帧目录> <水母帧目录> <海嗣潮帧目录> <输出目录>
"""
import glob, os, sys
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from pv2d import W, H, FPS, BAR, track, ease_io, expo_out, finish

SHOT1, FISH, JELLY, SWARM, OUT = sys.argv[1:6]
B = lambda k: int(round(k * BAR * FPS))
SRC_FPS = 24
os.makedirs(OUT, exist_ok=True)
frames = lambda d: sorted(glob.glob(os.path.join(d, "*.png")))
s1, fish, jelly, swarm = frames(SHOT1), frames(FISH), frames(JELLY), frames(SWARM)


def cam(im, cx, cy, z):
    im = im.resize((W, H), Image.LANCZOS) if im.size != (W, H) else im
    cw, ch = W / z, H / z
    x0 = min(max(0, cx - cw / 2), W - cw)
    y0 = min(max(0, cy - ch / 2), H - ch)
    return im.crop((int(x0), int(y0), int(x0 + cw), int(y0 + ch))).resize((W, H), Image.LANCZOS)


def pixel(im, px=4):
    s = im.convert("RGB").resize((W // px, H // px), Image.BOX)
    s = s.quantize(colors=96, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).convert("RGB")
    return s.resize((W, H), Image.NEAREST)


def src(lst, k, start=0.3):
    return Image.open(lst[min(len(lst) - 1, int(start * SRC_FPS + k / FPS * SRC_FPS))]).convert("RGB")


NF = B(7)
for i in range(NF):
    if i < B(3):
        Image.open(s1[min(i, len(s1) - 1)]).save(os.path.join(OUT, "o%04d.png" % i))
        continue
    tint = None
    if i < B(4):                       # 鱼群：往下沉
        k = i - B(3)
        u = k / (B(4) - B(3))
        fr = cam(src(fish, k), 960, track([(0, 440), (1, 640)], u, ease_io), 1.2)
        if k < 8:
            tint = ((150, 200, 230), 0.45 * (1 - k / 8))
    elif i < B(5):                     # 水母：缓推
        k = i - B(4)
        u = k / (B(5) - B(4))
        fr = cam(src(jelly, k), 960 + 150 * ease_io(u), 540 - 80 * ease_io(u), 1.0 + 0.18 * ease_io(u))
    else:                              # 海嗣潮：拉远 + 闪白
        k = i - B(5)
        u = expo_out(k / (B(7) - B(5)))
        fr = cam(src(swarm, k, 0.2), 960, 600 - 60 * u, 1.4 - 0.4 * u)
        if NF - i <= 8:
            tint = ((245, 248, 250), (8 - (NF - i)) / 8)
    fr = pixel(fr)
    if tint:
        fr = Image.blend(fr, Image.new("RGB", (W, H), tint[0]), tint[1])
    finish(fr, i).save(os.path.join(OUT, "o%04d.png" % i))
print(NF)
