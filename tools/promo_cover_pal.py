# -*- coding: utf-8 -*-
"""itch 封面过渡版 F（界面与美术 2026-10-01）：自有 6 色限定调色板（同 art/requests/v16_codex_cover.md），Codex 肖像到货前先用。
构图（与参考图区分开）：斯卡蒂半身在左、面朝右侧点亮的引航灯标，暖光从灯标打到她脸上；灯标脚下一圈溟痕触须和海嗣轮廓沿海浪线错落；
标题一行横排在右上（右对齐），英文与声明在其下。整幅最后按 4×4 有序抖动量化到 6 色——硬边、无抗锯齿、无半透明。
Codex 肖像到货后把 bust 层换成 art/incoming/cover_v16/cover_skadi.png（头像沿灯光弧线排开），其余不变。
用法：python tools/promo_cover_pal.py [输出目录，缺省 build/promo] [--size 630x500|960x400]
"""
import os, sys, random
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import promo_keyart as K
import promo_cover as C
import promo_cover_bust as B

ROOT = K.ROOT
# v16 调色板：深海蓝黑 / 灯火暖橙 / 米白灰蓝，各两阶
PAL = [(11, 20, 32), (28, 46, 64), (184, 90, 34), (242, 154, 58), (138, 154, 168), (232, 226, 208)]
NAVY0, NAVY1, ORANGE0, ORANGE1, GREY, CREAM = PAL
BAYER = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]], dtype=np.float32) / 16.0 - 0.5


def quantize(img, spread=34.0):
    """4×4 有序抖动量化到 PAL：每个像素加 Bayer 偏移后取最近色（棋盘格过渡，像素画常用的做法）"""
    a = np.asarray(img.convert("RGB"), dtype=np.float32)
    h, w, _ = a.shape
    th = np.tile(BAYER, (h // 4 + 1, w // 4 + 1))[:h, :w][..., None] * spread
    a = a + th
    pal = np.array(PAL, dtype=np.float32)
    # 感知加权的距离（绿权重大），免得肤色被拉成灰蓝
    wgt = np.array([0.30, 0.59, 0.11], dtype=np.float32) * 3.0
    d = (((a[:, :, None, :] - pal[None, None, :, :]) ** 2) * wgt).sum(-1)
    idx = d.argmin(-1)
    return Image.fromarray(pal[idx].astype(np.uint8), "RGB")


def compose(W=630, H=500):
    s = H / 500.0
    wide = W / H > 1.6
    img = Image.new("RGBA", (W, H))
    d = ImageDraw.Draw(img)
    for y in range(H):
        t = y / (H - 1)
        c = tuple(int(NAVY0[i] + (NAVY1[i] - NAVY0[i]) * (0.25 + 0.75 * (1 - abs(t - 0.55) * 1.8)) ) for i in range(3))
        d.line([(0, y), (W, y)], fill=c + (255,))
    sea_y = int(H * 0.80)
    # 灯标：画面右侧偏中，暖光大圈（量化后变成暖橙 / 深橙 / 蓝黑的同心抖动环）
    lx = int(W * (0.66 if not wide else 0.60))
    bk = K.up(K.frame("prop_beacon", 2, 1, trim=True), max(1, int(round(4 * s))))
    bx, by = lx - bk.width // 2, sea_y + int(6 * s) - bk.height
    lamp = (lx, by + int(bk.height * 0.2))
    img = K.add(img, K.radial((W, H), lamp, int(250 * s), ORANGE0, 80), (0, 0))
    img = K.add(img, K.radial((W, H), lamp, int(80 * s), ORANGE1, 120), (0, 0))
    # 海嗣轮廓：沿海浪线错落（灯光里的逆光剪影）
    rnd = random.Random(9)
    for i in range(9):
        name = rnd.choice(B.WALL)
        f = B.solid(K.frame(name, 2, 0, trim=True))
        if rnd.random() < 0.5:
            f = f.transpose(Image.FLIP_LEFT_RIGHT)
        e = K.up(f, max(1, int(round(rnd.choice([2, 3, 3, 4]) * s))))
        ex = int(W * (0.30 + i * 0.085)) + rnd.randint(-20, 20) - e.width // 2
        ey = sea_y - e.height + rnd.randint(int(4 * s), int(26 * s))
        B.rim(img, e, ORANGE1, 1.0 * s, 8.0, (ex, ey))
        img.alpha_composite(K.tint(e, NAVY0), (ex, ey))
    # 海面 + 灯标
    img.alpha_composite(Image.new("RGBA", (W, H - sea_y), NAVY0 + (255,)), (0, sea_y))
    img.alpha_composite(bk, (bx, by))
    img = K.add(img, K.radial((W, H), lamp, int(26 * s), CREAM, 255), (0, 0))
    # 底部溟痕触须：现有「水月触手群」帧条压成蓝黑剪影 + 灰蓝高光，沿底边错落铺一排
    mass = K.load("fx_mizuki_tentacle_mass@2x")
    fw = mass.width // 6
    x, i = -int(30 * s), 0
    while x < W:
        fr = mass.crop((fw * [2, 1, 4, 3][i % 4], 0, fw * ([2, 1, 4, 3][i % 4] + 1), mass.height))
        bb = fr.getbbox()
        fr = fr.crop(bb) if bb else fr
        t = K.up(fr, max(1, int(round(2 * s))))
        lum = t.convert("L")
        col = Image.new("RGBA", t.size, NAVY1 + (255,))
        col.paste(Image.new("RGBA", t.size, GREY + (255,)), (0, 0), lum.point(lambda v: 255 if v > 200 else 0))
        col.putalpha(t.split()[3])
        img.alpha_composite(col, (x, H - t.height + int(10 * s)))
        x += t.width - int(36 * s)
        i += 1
    # 斯卡蒂半身：左侧，面朝灯标（@2x 待机帧本来朝右）；受光边暖橙
    f = K.frame("op_skadi_idle@2x", 4, 0, trim=True)
    bust = f.crop((0, 0, f.width, int(f.height * 0.62)))
    k = max(1, int(round(8 * s)))
    bu = K.up(bust, k)
    ox = int(W * (0.30 if not wide else 0.27)) - bu.width // 2
    oy = H - bu.height + int(4 * s)
    B.rim(img, bu, ORANGE1, 1.6 * s, 6.0, (ox + int(3 * s), oy))
    img.alpha_composite(bu, (ox, oy))
    img = B.eye_glow(img, ox, oy, k, B.VARIANTS["E"]["eyes"], ORANGE1, s * 0.55)
    # 暗角
    vig = Image.new("L", (W, H), 0)
    ImageDraw.Draw(vig).ellipse((-W * 0.15, -H * 0.2, W * 1.15, H * 1.15), fill=255)
    vig = vig.filter(ImageFilter.GaussianBlur(60 * s))
    dark = Image.new("RGBA", (W, H), NAVY0 + (255,))
    dark.putalpha(vig.point(lambda v: int((255 - v) * 0.8)))
    img.alpha_composite(dark)
    out = quantize(img).convert("RGBA")
    # 标题：一行横排、右上、右对齐（字直接用调色板色，不参与抖动）
    m = int(26 * s)
    t1 = C.pixel_text(C.TITLE, 17, max(1, int(round(3 * s))), CREAM, GREY, outline=NAVY0)
    t2 = C.pixel_text(C.TITLE_EN, 9, max(1, int(round(2 * s))), ORANGE1, ORANGE0, outline=NAVY0)
    out.alpha_composite(t1, (W - m - t1.width, m))
    out.alpha_composite(t2, (W - m - t2.width, m + t1.height + int(6 * s)))
    f3 = ImageFont.truetype(K.FONT_UI, max(10, int(11 * s)))
    dd = ImageDraw.Draw(out)
    dd.fontmode = "1"
    bb = dd.textbbox((0, 0), C.TINY, font=f3)
    dd.text((W - m - (bb[2] - bb[0]), m + t1.height + t2.height + int(12 * s)), C.TINY, font=f3, fill=GREY)
    return out.convert("RGB")


if __name__ == "__main__":
    args = sys.argv[1:]
    out = args[0] if args and not args[0].startswith("--") else os.path.join(ROOT, "build", "promo")
    os.makedirs(out, exist_ok=True)
    size = args[args.index("--size") + 1] if "--size" in args else "630x500"
    W, H = (int(x) for x in size.split("x"))
    im = compose(W, H)
    p = os.path.join(out, "cover_F_%dx%d.png" % (W, H))
    im.save(p, optimize=True)
    cols = len(set(im.get_flattened_data()))
    print(p, "colors", cols)
    small = im.resize((W // 2, H // 2), Image.LANCZOS)
    small.save(os.path.join(out, "cover_F_%dx%d_thumb.png" % (W, H)))
