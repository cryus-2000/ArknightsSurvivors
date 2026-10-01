# -*- coding: utf-8 -*-
"""itch 封面 / 横幅（界面与美术 2026-10-01，用户要求重做）：只用本项目像素资产，辅助函数沿用 promo_keyart。
构图（630×500）：竖向三层——上 1/3 标题（「方舟幸存者」一行等大像素字 + Arknights Survivors + 极小声明），
中间主体（主控站在点亮的引航灯标旁，暖光打亮她和脚下；冷色 Boss 轮廓从暗处压过来），下 1/3 近景涨潮的深海。
在原尺寸上直接排版、像素整数倍放大（不先画大图再缩，缩略图上颗粒和剪影更清楚）。
用法：python tools/promo_cover.py [输出目录，缺省 build/promo] [--variant A|B|C|all] [--size 630x500|960x400] [--sheet]
  A 斯卡蒂 + 骑士　B 水月 + 泡影　C 水月单人 + 灯标（无 Boss，极简）；--sheet 三个变体 + 315×250 缩略图并排一张对照图
"""
import os, sys, random
from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageChops
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import promo_keyart as K

ROOT = K.ROOT
TITLE = "方舟幸存者"
TITLE_EN = "ARKNIGHTS SURVIVORS"
TINY = "明日方舟同人 · 免费"
VARIANTS = {
    "A": {"op": "op_skadi_idle@2x", "boss": "knight", "name": "斯卡蒂 + 骑士"},
    "B": {"op": "player_idle@2x", "boss": "paranoia", "name": "水月 + 泡影"},
    "C": {"op": "player_idle@2x", "boss": None, "name": "水月单人 + 灯标（极简）"},
}
WARM = (255, 196, 118)
COLD = (90, 190, 235)


def pixel_text(text, size, k, fill, shade, outline=(3, 6, 12)):
    """像素字：ui.ttf 关抗锯齿在小字号上渲染，再最近邻放大 k 倍；上亮下暗两段色（像素游戏标题的常见做法），1 像素描边 + 向下 1 像素投影"""
    f = ImageFont.truetype(K.FONT_UI, size)
    bb = f.getbbox(text)
    w, h = bb[2] - bb[0] + 4, bb[3] - bb[1] + 5
    m = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(m)
    d.fontmode = "1"
    d.text((2 - bb[0], 2 - bb[1]), text, font=f, fill=255)
    m = m.point(lambda v: 255 if v > 127 else 0)
    # 描边 = 掩码向八邻域各扩 1 像素；投影 = 描边再下移 1 像素
    ol = m.filter(ImageFilter.MaxFilter(3))
    out = Image.new("RGBA", (w, h + 1), (0, 0, 0, 0))
    out.paste(Image.new("RGBA", (w, h), outline + (255,)), (0, 1), ol)
    out.paste(Image.new("RGBA", (w, h), outline + (255,)), (0, 0), ol)
    body = Image.new("RGBA", (w, h), fill + (255,))
    lower = Image.new("RGBA", (w, h), shade + (255,))
    split = Image.new("L", (w, h), 0)
    ImageDraw.Draw(split).rectangle((0, int(h * 0.58), w, h), fill=255)
    body.paste(lower, (0, 0), split)
    out.paste(body, (0, 0), m)
    return K.up(out, k)


def background(W, H):
    img = Image.new("RGBA", (W, H))
    d = ImageDraw.Draw(img)
    top, mid, bot = (2, 4, 10), (8, 20, 36), (3, 8, 16)
    for y in range(H):
        t = y / (H - 1)
        if t < 0.62:
            u = t / 0.62
            c = tuple(int(top[i] + (mid[i] - top[i]) * u) for i in range(3))
        else:
            u = (t - 0.62) / 0.38
            c = tuple(int(mid[i] + (bot[i] - mid[i]) * u) for i in range(3))
        d.line([(0, y), (W, y)], fill=c + (255,))
    # 远处的几道冷色光柱（深海里从上方透下来的光），给上半幅一点层次但不抢标题
    rays = Image.new("L", (W, H), 0)
    rd = ImageDraw.Draw(rays)
    rnd = random.Random(3)
    for _ in range(5):
        x = rnd.uniform(0.05, 0.95) * W
        wdt = rnd.uniform(0.03, 0.07) * W
        rd.polygon([(x, 0), (x + wdt, 0), (x + wdt * 2.2 - W * 0.12, H * 0.7), (x - W * 0.12, H * 0.7)], fill=rnd.randint(18, 30))
    rays = rays.filter(ImageFilter.GaussianBlur(W * 0.02))
    rl = Image.new("RGBA", (W, H), (70, 140, 190, 0))
    rl.putalpha(rays)
    img.alpha_composite(rl)
    return img


def boss(img, kind, W, H, s, cx, foot):
    """Boss 剪影：深色压暗 + 冷色（骑士）/ 洋红（泡影）边光，从主体身后右上方压过来"""
    if kind == "knight":
        # 冲锋形态 @2x（长枪平端、披风拖成蓝焰），翻转成面朝主控（向左）冲过来
        bf = K.frame("e_knight_charge_form@2x", 4, 1, trim=True).transpose(Image.FLIP_LEFT_RIGHT)
        b = K.up(bf, max(1, int(round(2 * s))))
        bx, by = int(cx - b.width * 0.45), foot - b.height
        # 冷光：一圈柔光 + 2 像素硬边光；本体压暗但留六成原色（本来就是冷蓝，剪影和披风焰都读得出）
        K.put_glow(img, b, (50, 130, 210), 12 * s, 1.8, (bx, by))
        K.put_glow(img, b, (150, 220, 255), 1.5 * s, 9.0, (bx, by))
        img.alpha_composite(K.tint(b, (8, 14, 28), keep=0.6), (bx, by))
        # 枪尖寒光
        tip = K.radial((W, H), (bx + int(b.width * 0.02), by + int(b.height * 0.30)), int(18 * s), (190, 235, 255), 170)
        return K.add(img, tip, (0, 0))
    bf = K.frame("e_paranoia_phase2@2x", 2, 0, trim=True)
    b = K.up(bf, max(1, int(round(2 * s))))
    bx, by = int(cx - b.width * 0.5), foot - b.height
    K.put_glow(img, b, (200, 40, 170), 7 * s, 3.4, (bx, by))
    img.alpha_composite(K.tint(b, (10, 5, 18), keep=0.14), (bx, by))
    lum = b.convert("L").point(lambda v: 0 if v < 120 else int((v - 120) * 1.9))
    lum = ImageChops.multiply(lum, b.split()[3])
    hi = Image.new("RGBA", b.size, (255, 90, 190, 0))
    hi.putalpha(lum.point(lambda v: int(v * 0.7)))
    return K.add(img, hi, (bx, by))


def sea(img, W, H, s, y0, near):
    """海面：远处一层细浪（y0），近景一层大浪（near=True 时压到画面底部 1/3）"""
    wave = K.load("fx_skadi_wave@2x")
    fw = wave.width // 6
    img.alpha_composite(Image.new("RGBA", (W, H - y0), (4, 14, 24, 255)), (0, y0))
    kw = max(1, int(round(1 * s)))
    x, i = -10, 0
    while x < W:
        f = K.tint(K.up(wave.crop((fw * (i % 3 + 1), 0, fw * (i % 3 + 2), wave.height)), kw), (18, 48, 66), keep=0.18)
        img.alpha_composite(f, (x, y0 - f.height + int(10 * s)))
        x += f.width - int(16 * s)
        i += 1
    if near:
        kn = max(1, int(round(2 * s)))
        x, i = -int(30 * s), 1
        yb = H + int(6 * s)
        while x < W:
            f = K.tint(K.up(wave.crop((fw * (i % 3 + 1), 0, fw * (i % 3 + 2), wave.height)), kn), (7, 22, 34), keep=0.10)
            img.alpha_composite(f, (x, yb - f.height))
            x += f.width - int(40 * s)
            i += 1
    bub = K.load("fx_mire_bubble")
    rnd = random.Random(11)
    for _ in range(6):
        b = K.tint(K.up(bub.crop((0, 0, bub.height, bub.height)), max(1, int(round(1.5 * s)))), (150, 70, 190), keep=0.4)
        img.alpha_composite(b, (rnd.randrange(0, W - b.width), rnd.randrange(int(H * 0.86), H - b.height)))
    return img


def compose(variant, W=630, H=500):
    v = VARIANTS[variant]
    s = H / 500.0
    wide = W / H > 1.6
    img = background(W, H)
    foot = int(H * 0.80)                 # 主体脚线（中层底边）
    shore_y = int(H * 0.75)
    # 主体位置：封面居中偏左（Boss 在右）；C 无 Boss 居中；横幅主体靠右、标题在左
    if wide:
        cx = int(W * 0.66)
    else:
        cx = int(W * (0.42 if v["boss"] else 0.5))
    # 灯标在主控左边（暖光从左打来），Boss 在右
    bk = K.frame("prop_beacon", 2, 1, trim=True)
    beacon = K.up(bk, max(1, int(round(4 * s))))
    bxc = cx - int(88 * s)
    bx, by = bxc - beacon.width // 2, foot + int(4 * s) - beacon.height
    lamp = (bxc, by + int(beacon.height * 0.2))
    # 暖光：大范围底光 + 灯室强光（先铺，Boss 剪影压在上面，不被洗成褐色）
    img.alpha_composite(K.radial((W, H), lamp, int(170 * s), WARM, 115))
    img.alpha_composite(K.radial((W, H), (cx - int(40 * s), foot - int(40 * s)), int(130 * s), WARM, 85))
    if v["boss"]:
        bcx = cx + int((175 if v["boss"] == "knight" else 185) * s)
        if wide:
            bcx = cx + int(190 * s)
        img = boss(img, v["boss"], W, H, s, bcx, shore_y + int((36 if v["boss"] == "knight" else 56) * s))   # 脚线压到海面下：从涨潮的海里升起
    img = sea(img, W, H, s, shore_y, near=True)
    # 脚下礁石平台：暖光照亮的一块深色地面，主体站在上面
    rock = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(rock).ellipse((cx - int(150 * s), foot - int(12 * s), cx + int(90 * s), foot + int(24 * s)), fill=(20, 24, 30, 255))
    img.alpha_composite(rock)
    img = K.add(img, K.radial((W, H), (cx - int(30 * s), foot), int(70 * s), (255, 170, 90), 70), (0, 0))
    # 灯标
    K.put_glow(img, beacon, WARM, 6 * s, 1.2, (bx, by))
    img.alpha_composite(beacon, (bx, by))
    img = K.add(img, K.radial((W, H), lamp, int(34 * s), (255, 236, 180), 255), (0, 0))
    # 主控：@2x 待机帧 ×3（整数倍），左侧暖边光、右侧冷边光
    op = K.up(K.frame(v["op"], 4, 0, trim=True), max(1, int(round(3 * s))))
    ox, oy = cx - op.width // 2, foot - op.height
    sh = Image.new("RGBA", (int(op.width * 0.9), int(14 * s)), (0, 0, 0, 0))
    ImageDraw.Draw(sh).ellipse((0, 0, sh.width - 1, sh.height - 1), fill=(0, 0, 0, 190))
    img.alpha_composite(sh.filter(ImageFilter.GaussianBlur(3 * s)), (cx - sh.width // 2, foot - int(8 * s)))
    if v["boss"]:
        K.put_glow(img, op, COLD, 4 * s, 1.6, (ox + int(3 * s), oy))
    K.put_glow(img, op, (255, 170, 80), 4 * s, 2.2, (ox - int(3 * s), oy - int(1 * s)))
    img.alpha_composite(op, (ox, oy))
    # 暗角：四角压黑，中间主体最亮（缩略图上不发灰的关键是黑位够深）
    vig = Image.new("L", (W, H), 0)
    ImageDraw.Draw(vig).ellipse((-W * 0.2, -H * 0.1, W * 1.2, H * 1.15), fill=255)
    vig = vig.filter(ImageFilter.GaussianBlur(70 * s))
    dark = Image.new("RGBA", (W, H), (0, 0, 0, 255))
    dark.putalpha(vig.point(lambda v: int((255 - v) * 0.75)))
    img.alpha_composite(dark)
    # 标题
    margin = int(28 * s)
    kt = max(1, int(round(4 * s)))
    t1 = pixel_text(TITLE, 17, kt, (248, 250, 252), (150, 225, 240))
    t2 = pixel_text(TITLE_EN, 9, max(1, int(round(2 * s))), (255, 206, 130), (230, 160, 90))
    t3f = ImageFont.truetype(K.FONT_UI, max(10, int(12 * s)))
    if wide:
        tx = margin + int(10 * s)
        ty = int(H * 0.26)
        img.alpha_composite(t1, (tx, ty))
        img.alpha_composite(t2, (tx + int(4 * s), ty + t1.height + int(8 * s)))
        d = ImageDraw.Draw(img)
        d.text((tx + int(6 * s), ty + t1.height + t2.height + int(18 * s)), TINY, font=t3f, fill=(160, 172, 182, 255))
    else:
        tx = (W - t1.width) // 2
        ty = margin
        K.put_glow(img, t1, (60, 180, 220), 10 * s, 0.5, (tx, ty))
        img.alpha_composite(t1, (tx, ty))
        img.alpha_composite(t2, ((W - t2.width) // 2, ty + t1.height + int(8 * s)))
        d = ImageDraw.Draw(img)
        bb = d.textbbox((0, 0), TINY, font=t3f)
        d.text(((W - (bb[2] - bb[0])) // 2, ty + t1.height + t2.height + int(16 * s)), TINY, font=t3f, fill=(150, 162, 174, 255))
    return img.convert("RGB")


def sheet(out):
    """三个变体 + 各自 315×250 缩略图并排对照"""
    f = ImageFont.truetype(K.FONT_UI, 20)
    cols = []
    for k in "ABC":
        big = compose(k)
        small = big.resize((315, 250), Image.LANCZOS)
        c = Image.new("RGB", (630, 500 + 250 + 70), (18, 20, 26))
        c.paste(big, (0, 40))
        c.paste(small, (0, 550))
        d = ImageDraw.Draw(c)
        d.text((8, 8), "%s  %s" % (k, VARIANTS[k]["name"]), font=f, fill=(235, 240, 245))
        d.text((325, 550), "← 315×250 卡片缩略", font=f, fill=(150, 160, 170))
        cols.append(c)
    W = sum(c.width for c in cols) + 20 * (len(cols) - 1)
    im = Image.new("RGB", (W, cols[0].height), (10, 12, 16))
    x = 0
    for c in cols:
        im.paste(c, (x, 0))
        x += c.width + 20
    p = os.path.join(out, "cover_variants_sheet.png")
    im.save(p, optimize=True)
    print(p)


if __name__ == "__main__":
    args = sys.argv[1:]
    out = args[0] if args and not args[0].startswith("--") else os.path.join(ROOT, "build", "promo")
    os.makedirs(out, exist_ok=True)
    var = args[args.index("--variant") + 1] if "--variant" in args else "all"
    size = args[args.index("--size") + 1] if "--size" in args else "630x500"
    W, H = (int(x) for x in size.split("x"))
    for k in ("ABC" if var == "all" else var):
        p = os.path.join(out, "cover_%s_%dx%d.png" % (k, W, H))
        compose(k, W, H).save(p, optimize=True)
        print(p)
    if "--sheet" in args:
        sheet(out)
