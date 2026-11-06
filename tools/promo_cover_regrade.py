# -*- coding: utf-8 -*-
"""商店封面 11-07（用户：在 Toy 那版基础上只调色）：art/promo/toy/toy_poster_shadow_1014_4x3_notext.png 调色 + 游戏内像素标题字。
只动背景的蓝：按色相（蓝带）× 明度（暗部）加权，人物的肤色 / 绿裙 / 提灯 / 亮部基本不动，免得偏离 PRTS 设定色（docs/87 §4.3）。
  G1 标题页青灰：蓝推向标题页的青灰（深水母版），降饱和、压暗部
  G2 青光提灯：蓝推青，提灯暖光加一圈，暗部更深，冷暖对比
  G3 原色微调：色相不动，只降一点饱和、加对比
用法：python tools/promo_cover_regrade.py <输出目录> [--grades G1,G2,G3] [--sheet <路径>]
"""
import os, sys, argparse
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import promo_cover_1107 as C

ROOT = C.ROOT
SRC = os.path.join(ROOT, "art", "promo", "toy", "toy_poster_shadow_1014_4x3_notext.png")
LANTERN = (522, 478)   # 提灯中心（1200×900 原图坐标）

GRADES = {
    "G1": dict(hue_to=0.53, hue_amt=0.75, sat=0.62, dark_gamma=1.18, lift=(0, 4, 6), lamp=0.0,
               name="G1 标题页青灰：蓝推向标题页的青灰，降饱和、压暗部"),
    "G2": dict(hue_to=0.52, hue_amt=0.6, sat=0.75, dark_gamma=1.28, lift=(0, 2, 4), lamp=0.55,
               name="G2 青光提灯：蓝推青、暗部更深，提灯暖光冷暖对比"),
    "G3": dict(hue_to=None, hue_amt=0.0, sat=0.82, dark_gamma=1.12, lift=(0, 0, 0), lamp=0.0,
               name="G3 原色微调：色相不动，只降饱和、加对比"),
}


def rgb_to_hsv(a):
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    mx, mn = a.max(-1), a.min(-1)
    d = mx - mn
    h = np.zeros_like(mx)
    m = d > 1e-6
    rr = m & (mx == r)
    gg = m & (mx == g) & ~rr
    bb = m & ~rr & ~gg
    h[rr] = ((g - b)[rr] / d[rr]) % 6
    h[gg] = (b - r)[gg] / d[gg] + 2
    h[bb] = (r - g)[bb] / d[bb] + 4
    h = h / 6.0
    s = np.where(mx > 1e-6, d / np.maximum(mx, 1e-6), 0)
    return h, s, mx


def hsv_to_rgb(h, s, v):
    i = np.floor(h * 6).astype(int) % 6
    f = h * 6 - np.floor(h * 6)
    p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
    out = np.zeros(h.shape + (3,))
    for k, (a, b, c) in enumerate([(v, t, p), (q, v, p), (p, v, t), (p, q, v), (t, p, v), (v, p, q)]):
        m = i == k
        out[m] = np.stack([a[m], b[m], c[m]], -1)
    return out


def grade(img, g):
    a = np.asarray(img.convert("RGB")).astype(np.float64) / 255.0
    h, s, v = rgb_to_hsv(a)
    # 权重：蓝带（色相 0.55–0.72，约 200°–260°）× 暗部（明度 < 0.75 渐入）
    band = np.clip(1 - np.abs(h - 0.635) / 0.11, 0, 1)
    band = np.clip(band * 1.6, 0, 1)
    dark = np.clip((0.8 - v) / 0.35, 0, 1)
    # 上半幅的水面光带是亮蓝，按明度不会被选中：顶部 35% 渐入全权重（人物都在下半幅，不受影响）
    yy = np.linspace(0, 1, a.shape[0])[:, None] * np.ones((1, a.shape[1]))
    top = np.clip((0.40 - yy) / 0.20, 0, 1)
    w = band * np.maximum(dark, top)
    if g["hue_to"] is not None:
        h = h + (g["hue_to"] - h) * g["hue_amt"] * w
    s = s * (1 - (1 - g["sat"]) * w)
    v = np.where(w > 0, v ** (1 + (g["dark_gamma"] - 1) * w), v)
    out = hsv_to_rgb(h % 1.0, np.clip(s, 0, 1), np.clip(v, 0, 1))
    out = out + np.array(g["lift"]) / 255.0 * w[..., None]
    res = Image.fromarray((np.clip(out, 0, 1) * 255 + 0.5).astype(np.uint8), "RGB").convert("RGBA")
    if g["lamp"] > 0:
        W, H = res.size
        r = 230
        lg = C.radial((2 * r, 2 * r), r, (255, 170, 80), g["lamp"])
        C.add_light(res, lg, (LANTERN[0] * W // 1200 - r, LANTERN[1] * H // 900 - r))
    return res


def compose(kind, gname):
    src = Image.open(SRC).convert("RGBA")
    g = GRADES[gname]
    if kind == "toy":
        img = grade(src, g)
        C.top_shade(img, 0.22, 0.45)
        place_title(img, 3, 46, 92)
    else:
        # 630×500（1.26）：从 1200×900 截 1134×900，再缩
        x0 = 20
        img = grade(src.crop((x0, 0, x0 + 1134, 900)), g).resize((630, 500), Image.LANCZOS)
        C.top_shade(img, 0.24, 0.45)
        place_title(img, 2, 20, 30)
    return img.convert("RGB")


def place_title(img, k, x, y):
    lg = C.logo(k)
    C.shine(img, lg, (40, 120, 150), 8 * k, 0.9, (x, y))
    img.alpha_composite(lg, (x, y))
    nt = C.notice(max(1, k - 1) if k > 2 else k)
    img.alpha_composite(nt, (x + lg.width - nt.width - 2 * k, y + lg.height + k))


def sheet(res, path):
    f = ImageFont.truetype(C.PC.K.FONT_UI, 26)
    fs = ImageFont.truetype(C.PC.K.FONT_UI, 16)
    gs = [gk for gk in GRADES if (gk, "toy") in res]
    rows = [("原图", Image.open(os.path.join(ROOT, "art/promo/toy/toy_poster_shadow_1014_4x3.png")).convert("RGB"), None)]
    RH = 44 + 540 + 30
    W = 1357 + 500
    out = Image.new("RGB", (W, 20 + RH * (len(gs) + 1)), (18, 22, 30))
    dr = ImageDraw.Draw(out)
    allrows = [("现版 Toy（10-14）", None, rows[0][1])] + [(GRADES[gk]["name"], res[(gk, "itch")], res[(gk, "toy")]) for gk in gs]
    for r, (label, it, ty) in enumerate(allrows):
        y = 20 + r * RH
        dr.text((20, y), label, font=f, fill=(230, 236, 240))
        y += 44
        if it is not None:
            out.paste(it, (20, y))
        out.paste(ty.resize((667, 500), Image.LANCZOS), (670, y))
        x = 1357
        u1, u2 = C.thumbs(ty, "toy")
        if it is not None:
            t1, t2 = C.thumbs(it, "itch")
            dr.text((x, y - 4), "缩略图 itch 315×250 / 158×125", font=fs, fill=(160, 170, 180))
            out.paste(t1, (x, y + 16)); out.paste(t2, (x + 325, y + 16 + 125))
        dr.text((x, y + 272), "缩略图 Toy 320×240 / 160×120", font=fs, fill=(160, 170, 180))
        out.paste(u1, (x, y + 292)); out.paste(u2, (x + 330, y + 292 + 120))
    out.save(path)
    print(path)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out")
    ap.add_argument("--grades", default="G1,G2,G3")
    ap.add_argument("--sheet")
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    res = {}
    for gk in a.grades.split(","):
        for kind in ("itch", "toy"):
            im = compose(kind, gk)
            p = os.path.join(a.out, "%s_%s_%dx%d.png" % (gk, kind, im.width, im.height))
            im.save(p)
            res[(gk, kind)] = im
    if a.sheet:
        sheet(res, a.sheet)


if __name__ == "__main__":
    main()
