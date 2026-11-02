# -*- coding: utf-8 -*-
"""PV 小样的术曲式排版 / 转场元素（PIL + numpy，1920x1080）"""
import os, sys, math, functools
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter

WT = os.path.dirname(os.path.dirname(os.path.abspath(__file__))).replace(os.sep, "/")   # 仓库根
sys.path.insert(0, WT + "/tools")
W, H, FPS = 1920, 1080, 30
P = 60 / 145.99          # 一拍
FONT = WT + "/game/fonts/ui.ttf"
CYAN = (54, 226, 220)
PURPLE = (168, 133, 255)
WHITE = (240, 244, 246)
RHINE = (236, 236, 230)   # 莱茵白底
INK = (8, 12, 18)
NAVY = (6, 10, 18)


@functools.lru_cache(None)
def font(sz):
    return ImageFont.truetype(FONT, sz)


@functools.lru_cache(None)
def glyph(ch, sz, col, hollow=False, stroke=0):
    f = font(sz)
    bb = f.getbbox(ch, stroke_width=max(stroke, 6 if hollow else 0))
    pad = 16
    im = Image.new("RGBA", (bb[2] - bb[0] + pad * 2, bb[3] - bb[1] + pad * 2), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    o = (pad - bb[0], pad - bb[1])
    if hollow:
        d.text(o, ch, font=f, fill=col + (255,), stroke_width=6, stroke_fill=col + (255,))
        d.text(o, ch, font=f, fill=(0, 0, 0, 0))
    else:
        d.text(o, ch, font=f, fill=col + (255,), stroke_width=stroke, stroke_fill=INK + (255,))
    return im


def ease_out(x):
    x = min(1.0, max(0.0, x))
    return 1 - (1 - x) ** 3


def paste_scaled(base, im, cx, cy, s, alpha=1.0):
    if s <= 0.01 or alpha <= 0.01:
        return
    w, h = max(1, int(im.width * s)), max(1, int(im.height * s))
    g = im.resize((w, h), Image.BILINEAR)
    if alpha < 1.0:
        a = g.getchannel("A").point(lambda v: int(v * alpha))
        g.putalpha(a)
    base.alpha_composite(g, (int(cx - w / 2), int(cy - h / 2)))


def slam_text(base, text, t, cx, cy, sz, col, step=P / 2, ghost=CYAN, gap=0.0, stroke=0):
    """逐字砸出：第 k 个字在 k*step 秒落下（从 2.2 倍缩到 1 倍、0.09 秒），身后一个空心描边残影放大淡出；字距 gap 倍字号"""
    chars = list(text)
    f = font(sz)
    ws = [f.getlength(c) + sz * gap for c in chars]
    x = cx - sum(ws) / 2
    for k, c in enumerate(chars):
        mx = x + ws[k] / 2
        x += ws[k]
        if c == " ":
            continue
        dt = t - k * step
        if dt < 0:
            continue
        g = glyph(c, sz, col, stroke=stroke)
        land = 0.09
        if dt < land:
            s = 2.2 - 1.2 * ease_out(dt / land)
            paste_scaled(base, g, mx, cy, s, dt / land)
        else:
            if ghost is not None and dt < 0.45:
                gh = glyph(c, sz, ghost, hollow=True)
                u = (dt - land) / 0.36
                paste_scaled(base, gh, mx + 18 * u + 10, cy + 10 * u + 6, 1.0 + 0.5 * u, 1 - u)
            jit = 6 if dt < land + 1 / FPS else 0
            paste_scaled(base, g, mx + jit, cy - jit, 1.0)


def text_w(text, sz, gap=0.0):
    f = font(sz)
    return sum(f.getlength(c) + sz * gap for c in text)


def label(base, text, x, y, sz=34, bg=RHINE, fg=INK, alpha=1.0, slide=1.0):
    """莱茵白底黑字小标签（左侧一道青条）；slide 0–1 从左边扫入"""
    f = font(sz)
    tw = f.getlength(text)
    bw, bh = int(tw + 44), int(sz * 1.5)
    lay = Image.new("RGBA", (bw + 12, bh), (0, 0, 0, 0))
    d = ImageDraw.Draw(lay)
    cut = int(bw * ease_out(slide))
    d.rectangle((0, 0, 8, bh), fill=CYAN + (255,))
    d.polygon([(12, 0), (12 + cut, 0), (12 + cut - 10, bh), (12, bh)], fill=bg + (255,))
    if slide > 0.6:
        d.text((30, (bh - sz) // 2 - sz * 0.12), text, font=f, fill=fg + (255,))
    if alpha < 1:
        lay.putalpha(lay.getchannel("A").point(lambda v: int(v * alpha)))
    base.alpha_composite(lay, (int(x), int(y)))


def slash_bars(base, t, dur, cols, ang=-0.32, out=False):
    """斜切条：几条纯色斜带从左往右扫过（入场盖住 / 出场露出）；t 0–dur"""
    d = ImageDraw.Draw(base)
    n = len(cols)
    sk = math.tan(ang) * H
    for i, c in enumerate(cols):
        delay = i * 0.05
        u = ease_out((t - delay) / max(0.01, dur - (n - 1) * 0.05))
        if out:
            x0 = -300 + (W + 700) * u
            x1 = W + 400
        else:
            x0 = -400
            x1 = -400 + (W + 800) * u
        if x1 <= x0:
            continue
        d.polygon([(x0, 0), (x1, 0), (x1 + sk, H), (x0 + sk, H)], fill=c)


def diamond_mask(r):
    m = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(m)
    cx, cy = W / 2, H / 2
    d.polygon([(cx, cy - r), (cx + r, cy), (cx, cy + r), (cx - r, cy)], fill=255)
    return m


def flash(arr, a, col=(255, 255, 255)):
    if a <= 0:
        return arr
    return (arr.astype(np.float32) * (1 - a) + np.array(col, np.float32) * a).astype(np.uint8)


def invert(arr):
    return 255 - arr


def punch(img, s):
    """镜头推一下：放大 s 倍居中裁"""
    if s <= 1.001:
        return img
    w, h = int(W * s), int(H * s)
    g = img.resize((w, h), Image.BILINEAR)
    return g.crop(((w - W) // 2, (h - H) // 2, (w - W) // 2 + W, (h - H) // 2 + H))


def grid(base, col, step=96, a=40, off=0):
    d = ImageDraw.Draw(base)
    for x in range(-step + off % step, W + step, step):
        d.line([(x, 0), (x, H)], fill=col + (a,), width=1)
    for y in range(0, H, step):
        d.line([(0, y), (W, y)], fill=col + (a,), width=1)
