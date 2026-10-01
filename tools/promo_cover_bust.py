# -*- coding: utf-8 -*-
"""itch 封面 · 半身特写版（界面与美术 2026-10-01，用户要求仿《黎明前 20 分钟》封面气质）：只用本项目像素资产。
要素：主角半身特写占满画面（@2x 待机帧裁上半身、整数倍最近邻放大，像素块就是风格），脸和眼睛是视觉中心、眼睛单独发光；
暗色近单色底 + 单一强调色；身后密集海嗣剪影压过来（纯黑剪影 + 强调色边光）；粗颗粒噪点 + 暗角；标题粗体像素字压在底部深色条上。
用法：python tools/promo_cover_bust.py [输出目录，缺省 build/promo] [--variant D|E|all] [--size 630x500|960x400] [--sheet]
  D 水月 + 溟痕洋红　E 斯卡蒂 + 灯火暖橙；--sheet 两版 + 315×250 缩略并排对照
"""
import os, sys, random
from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageChops
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import promo_keyart as K
import promo_cover as C

ROOT = K.ROOT
VARIANTS = {
    # eyes：trim 后帧里两只眼睛的像素坐标（按眼睛颜色在帧里检出的像素团中心）；crop：保留上身的比例
    "D": {"op": "player_idle@2x", "accent": (236, 64, 178), "eyes": [(23, 22.7), (29.7, 22.7)], "crop": 0.62, "name": "水月 + 溟痕洋红"},
    "E": {"op": "op_skadi_idle@2x", "accent": (255, 150, 60), "eyes": [(29.7, 20.7), (35, 21)], "crop": 0.60, "name": "斯卡蒂 + 灯火暖橙"},
}
# 身后的海嗣墙：只用海嗣（不用人形 Boss），基础帧条都是 2 帧
WALL = ["e_runner", "e_skimmer", "e_floater", "e_slider", "e_offspring", "e_founder", "e_tracer", "e_reaper", "e_path",
        "e_izumik", "e_paranoia", "e_tracer", "e_reaper", "e_skimmer", "e_floater", "e_runner"]   # 轮廓有辨识度的多放几只


def rim(img, im, col, radius, strength, xy):
    """彩色外光：整张填 col、只用模糊后的 alpha（promo_keyart.glow 把贴图合到透明底上，图外的 RGB 是黑的，小半径时只剩一圈黑晕）"""
    pad = int(radius * 3) + 2
    a = Image.new("L", (im.width + pad * 2, im.height + pad * 2), 0)
    a.paste(im.split()[3], (pad, pad))
    a = a.filter(ImageFilter.GaussianBlur(radius)).point(lambda v: min(255, int(v * strength)))
    g = Image.new("RGBA", a.size, col + (0,))
    g.putalpha(a)
    img.alpha_composite(g, (int(xy[0]) - pad, int(xy[1]) - pad))


def solid(im):
    """怪物墙用：去掉帧里半透明的地面阴影（alpha < 150），否则剪影下面会多出一块灰方框"""
    im = im.copy()
    im.putalpha(im.split()[3].point(lambda v: 255 if v >= 150 else 0))
    return im


def grain(img, s, amount=10, block=2):
    """粗颗粒：按 block 像素一格的单色噪点（加减同量，亮部不发脏）"""
    W, H = img.size
    rnd = random.Random(5)
    bw, bh = W // block + 1, H // block + 1
    n = Image.new("L", (bw, bh))
    n.putdata([128 + rnd.randint(-amount, amount) for _ in range(bw * bh)])
    n = n.resize((bw * block, bh * block), Image.NEAREST).crop((0, 0, W, H))
    rgb = img.convert("RGB")
    up = ImageChops.add(rgb, Image.merge("RGB", [n.point(lambda v: max(0, v - 128))] * 3))
    return ImageChops.subtract(up, Image.merge("RGB", [n.point(lambda v: max(0, 128 - v))] * 3)).convert("RGBA")


def wall(img, W, H, s, accent, cx, top, bottom):
    """海嗣墙：从后往前三层，越靠前越大越密；纯黑剪影 + 强调色边光（逆光）"""
    rnd = random.Random(21)
    layers = [(3, 12, 0.6), (4, 9, 0.85), (5, 6, 1.0)]   # (放大倍数, 个数, 边光强度)
    for k, count, rim_k in layers:
        kk = max(1, int(round(k * s)))
        for _ in range(count):
            name = rnd.choice(WALL)
            f = K.frame(name, 2, rnd.randrange(2), trim=True)
            if rnd.random() < 0.5:
                f = f.transpose(Image.FLIP_LEFT_RIGHT)
            b = K.up(solid(f), kk)
            # 横向铺满，纵向集中在主角肩部以上到底部之间；中间（主角身后）更密
            x = int(rnd.uniform(-0.1, 1.0) * W)
            if rnd.random() < 0.45:
                x = int(cx + rnd.uniform(-0.35, 0.35) * W) - b.width // 2
            y = int(rnd.uniform(top, bottom) * H) - b.height // 2
            # 1–2 像素硬边光（每只都画：近处的压住远处的，交界处也有一道亮线，读得出一只只的轮廓）
            rim(img, b, accent, 1.2 * s, 6.0 * rim_k, (x, y))
            img.alpha_composite(K.tint(b, (5, 5, 10), keep=0.10), (x, y))
    return img


def eye_glow(img, ox, oy, k, eyes, accent, s):
    for ex, ey in eyes:
        c = (ox + int((ex + 0.5) * k), oy + int((ey + 0.5) * k))
        img = K.add(img, K.radial(img.size, c, int(26 * s), accent, 140), (0, 0))
        img = K.add(img, K.radial(img.size, c, int(6 * s), (255, 255, 255), 120), (0, 0))
    return img


def compose(variant, W=630, H=500):
    v = VARIANTS[variant]
    acc = v["accent"]
    s = H / 500.0
    wide = W / H > 1.6
    # 底：深海蓝黑近单色，中心略亮
    img = Image.new("RGBA", (W, H))
    d = ImageDraw.Draw(img)
    for y in range(H):
        t = y / (H - 1)
        c = (int(6 + 6 * (1 - abs(t - 0.45) * 2)), int(10 + 10 * (1 - abs(t - 0.45) * 2)), int(16 + 14 * (1 - abs(t - 0.45) * 2)))
        d.line([(0, y), (W, y)], fill=c + (255,))
    band_h = int(112 * s)
    cx = int(W * (0.68 if wide else 0.5))
    # 主角身后一团强调色逆光（只用这一种强调色）
    img = K.add(img, K.radial((W, H), (cx, int(H * 0.40)), int(300 * s), acc, 46), (0, 0))
    haze = Image.new("L", (W, H), 0)
    ImageDraw.Draw(haze).rectangle((0, int(H * 0.30), W, int(H * 0.56)), fill=26)
    haze = haze.filter(ImageFilter.GaussianBlur(50 * s))
    hl = Image.new("RGBA", (W, H), acc + (0,))
    hl.putalpha(haze)
    img = K.add(img, hl, (0, 0))
    img = wall(img, W, H, s, acc, cx, 0.42, 0.88)
    # 主角半身：@2x 待机帧 trim 后裁上身，整数倍放大（9 倍：头部约占画面 40%）
    f = K.frame(v["op"], 4, 0, trim=True)
    bust = f.crop((0, 0, f.width, int(f.height * v["crop"])))
    k = max(1, int(round(9 * s)))
    b = K.up(bust, k)
    ox = cx - b.width // 2
    oy = H - band_h + int(14 * s) - b.height
    # 轮廓：一道强调色细边光，把主角从怪物墙里切出来
    rim(img, b, acc, 1.4 * s, 5.0, (ox, oy))
    img.alpha_composite(b, (ox, oy))
    img = eye_glow(img, ox, oy, k, v["eyes"], acc, s)
    # 暗角 + 颗粒（暗角先压，颗粒最后加，黑位也有颗粒）
    vig = Image.new("L", (W, H), 0)
    ImageDraw.Draw(vig).ellipse((-W * 0.12, -H * 0.15, W * 1.12, H * 1.1), fill=255)
    vig = vig.filter(ImageFilter.GaussianBlur(60 * s))
    dark = Image.new("RGBA", (W, H), (0, 0, 0, 255))
    dark.putalpha(vig.point(lambda v: int((255 - v) * 0.7)))
    img.alpha_composite(dark)
    # 底部标题条：深色条 + 顶边一道强调色细线
    band = Image.new("RGBA", (W, band_h), (3, 4, 8, 236))
    img.alpha_composite(band, (0, H - band_h))
    ImageDraw.Draw(img).rectangle((0, H - band_h, W, H - band_h + max(1, int(2 * s))), fill=acc + (255,))
    img = grain(img, s)
    t1 = C.pixel_text(C.TITLE, 17, max(1, int(round(4 * s))), (250, 250, 250), (205, 210, 216))
    t2 = C.pixel_text(C.TITLE_EN, 9, max(1, int(round(2 * s))), acc, tuple(int(c * 0.75) for c in acc))
    gap = int(6 * s)
    ty = H - band_h + (band_h - t1.height - gap - t2.height) // 2
    if wide:
        tx = int(32 * s)
        img.alpha_composite(t1, (tx, ty))
        img.alpha_composite(t2, (tx + int(4 * s), ty + t1.height + gap))
    else:
        img.alpha_composite(t1, ((W - t1.width) // 2, ty))
        img.alpha_composite(t2, ((W - t2.width) // 2, ty + t1.height + gap))
    # 极小声明：右上角
    f3 = ImageFont.truetype(K.FONT_UI, max(10, int(11 * s)))
    dd = ImageDraw.Draw(img)
    bb = dd.textbbox((0, 0), C.TINY, font=f3)
    dd.text((W - (bb[2] - bb[0]) - int(14 * s), int(12 * s)), C.TINY, font=f3, fill=(150, 156, 166, 255))
    return img.convert("RGB")


def sheet(out, keys="DE"):
    f = ImageFont.truetype(K.FONT_UI, 20)
    cols = []
    for k in keys:
        big = compose(k)
        small = big.resize((315, 250), Image.LANCZOS)
        c = Image.new("RGB", (630, 500 + 250 + 70), (18, 20, 26))
        c.paste(big, (0, 40))
        c.paste(small, (0, 550))
        d = ImageDraw.Draw(c)
        d.text((8, 8), "%s  %s" % (k, VARIANTS[k]["name"]), font=f, fill=(235, 240, 245))
        d.text((325, 550), "← 315×250 卡片缩略", font=f, fill=(150, 160, 170))
        cols.append(c)
    im = Image.new("RGB", (sum(c.width for c in cols) + 20 * (len(cols) - 1), cols[0].height), (10, 12, 16))
    x = 0
    for c in cols:
        im.paste(c, (x, 0))
        x += c.width + 20
    p = os.path.join(out, "cover_bust_sheet.png")
    im.save(p, optimize=True)
    print(p)


if __name__ == "__main__":
    args = sys.argv[1:]
    out = args[0] if args and not args[0].startswith("--") else os.path.join(ROOT, "build", "promo")
    os.makedirs(out, exist_ok=True)
    var = args[args.index("--variant") + 1] if "--variant" in args else "all"
    size = args[args.index("--size") + 1] if "--size" in args else "630x500"
    W, H = (int(x) for x in size.split("x"))
    for k in ("DE" if var == "all" else var):
        p = os.path.join(out, "cover_%s_%dx%d.png" % (k, W, H))
        compose(k, W, H).save(p, optimize=True)
        print(p)
    if "--sheet" in args:
        sheet(out)
