"""PV 字卡样张（docs/327 鹰角 PV 风格规范 §4 的落地示例）。

出两张 1920×1080：
  typecard_end.png   结尾卡 / 标题卡：左侧一束光 + 主标题 + 副标题 + 英文标签 + 行动语 + 同人声明
  typecard_word.png  画面标注 + 角落终结技标名 + 旁白字幕
  typecard_intro.png 干员出场：暗场一束光 + 像素干员 + 底部居中名字（§16，不加面板 / 色块）（同一画面里按真实字号排）

字体全部是 SIL OFL 1.1（可免费商用、可嵌入成片）：
  Noto Serif SC（思源宋体同源）可变字重 200–900
  Noto Sans SC（思源黑体同源）可变字重 100–900
  Montserrat（仓库 game/fonts，OFL_Montserrat.txt）
系统里装了 Noto Serif/Sans SC VF 就用（全字库）；没有就退回仓库里的子集字体。

用法：python tools/promo/pv_style_typecard.py <输出目录>
"""
import math
import os
import random
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
WIN = os.environ.get("WINDIR", "C:/Windows") + "/Fonts/"
W, H = 1920, 1080

# —— 色板（docs/327 §5.2）——
BG_DEEP = (5, 9, 18)        # #050912 深海底，和标题页 boot_views.BG 同色
BG_MID = (12, 26, 40)       # #0C1A28
INK = (236, 241, 244)       # #ECF1F4 主文字（不用纯白）
INK_DIM = (150, 166, 178)   # #96A6B2 次级文字
CYAN = (94, 230, 230)       # #5EE6E6 水月青（标题页 CYAN），全片唯一强调色
RED = (214, 64, 72)         # #D64048 只给 Boss / 危险提示，本样张不用


def _font(path_candidates, size, wght=None):
    for p in path_candidates:
        if os.path.exists(p):
            f = ImageFont.truetype(p, size)
            if wght is not None:
                try:
                    f.set_variation_by_axes([wght])
                except Exception:
                    pass
            return f
    raise FileNotFoundError(path_candidates)


def serif(size, wght=400):
    return _font([WIN + "NotoSerifSC-VF.ttf", ROOT + "/game/fonts/serif.ttf"], size, wght)


def sans(size, wght=400):
    return _font([WIN + "NotoSansSC-VF.ttf", ROOT + "/game/fonts/ui_regular.ttf"], size, wght)


def latin(size, bold=False):
    name = "montserrat_bold.ttf" if bold else "montserrat_semibold.ttf"
    return _font([ROOT + "/game/fonts/" + name], size)


def tracked(draw, xy, text, font, fill, tracking=0.0, anchor="l"):
    """按字距画一行。tracking 以 em 计（0.2 = 字号的 20%）。anchor: l / m / r（水平），y 是基线上方的顶边。"""
    sp = font.size * tracking
    widths = [draw.textlength(ch, font=font) for ch in text]
    total = sum(widths) + sp * (len(text) - 1)
    x, y = xy
    if anchor == "m":
        x -= total / 2
    elif anchor == "r":
        x -= total
    for ch, w in zip(text, widths):
        draw.text((x, y), ch, font=font, fill=fill)
        x += w + sp
    return total


def vertical(draw, xy, text, font, fill, gap=0.06):
    x, y = xy
    for ch in text:
        draw.text((x, y), ch, font=font, fill=fill, anchor="mt")
        y += font.size * (1 + gap)


def deep_bg(seed=7, light=(0.30, 0.38)):
    """深海底：竖向渐变 + 一束顶光 + 焦散细线 + 暗角 + 颗粒。"""
    rnd = random.Random(seed)
    img = Image.new("RGB", (W, H), BG_DEEP)
    px = img.load()
    lx, ly = light
    for y in range(H):
        t = y / H
        for x in range(0, W):
            # 竖向：上略亮下更深
            r = BG_MID[0] * (1 - t) + BG_DEEP[0] * t
            g = BG_MID[1] * (1 - t) + BG_DEEP[1] * t
            b = BG_MID[2] * (1 - t) + BG_DEEP[2] * t
            # 一束偏左上的柔光（只占画面 ~15% 面积）
            d = math.hypot((x / W - lx) * 1.6, (y / H - ly))
            k = max(0.0, 1 - d / 0.55) ** 2.2
            r += 26 * k
            g += 52 * k
            b += 60 * k
            # 暗角
            v = math.hypot(x / W - 0.5, (y / H - 0.5) * 1.15)
            vig = 1 - 0.75 * min(1, max(0, (v - 0.32) / 0.42)) ** 1.6
            px[x, y] = (int(r * vig), int(g * vig), int(b * vig))
    # 焦散细线：几条极淡的弯曲亮线
    ov = Image.new("L", (W, H), 0)
    od = ImageDraw.Draw(ov)
    for _ in range(26):
        x0 = rnd.uniform(0, W)
        y0 = rnd.uniform(0, H * 0.7)
        pts = []
        a = rnd.uniform(0, math.tau)
        for i in range(14):
            a += rnd.uniform(-0.5, 0.5)
            x0 += math.cos(a) * 30
            y0 += math.sin(a) * 18
            pts.append((x0, y0))
        od.line(pts, fill=rnd.randint(10, 26), width=1)
    ov = ov.filter(ImageFilter.GaussianBlur(1.2))
    img = Image.composite(Image.new("RGB", (W, H), (120, 220, 230)), img, ov)
    # 海雪颗粒
    sd = ImageDraw.Draw(img)
    for _ in range(420):
        x, y = rnd.uniform(0, W), rnd.uniform(0, H)
        s = rnd.choice([1, 1, 1, 2])
        c = rnd.randint(40, 110)
        sd.ellipse((x, y, x + s, y + s), fill=(c, c + 10, c + 14))
    return img


def _add_noise(img, n):
    """胶片颗粒：n 是以 128 为零点的灰度噪声图，逐通道叠加。"""
    import PIL.ImageChops as IC
    return Image.merge("RGB", [IC.add(c, n, 1.0, -128) for c in img.split()])


def chroma(img, px=2):
    """边缘色散：R 往左、B 往右各挪 px，只用在白闪 / 故障帧和标题入场的前 4 帧。"""
    r, g, b = img.split()
    r = r.transform(img.size, Image.AFFINE, (1, 0, px, 0, 1, 0))
    b = b.transform(img.size, Image.AFFINE, (1, 0, -px, 0, 1, 0))
    return Image.merge("RGB", (r, g, b))


def guides(d, label=True):
    """安全区参考线（只在样张上画，成片不画）。"""
    m_x, m_y = 96, 54  # 5% 动作安全区
    d.rectangle((m_x, m_y, W - m_x, H - m_y), outline=(60, 80, 90))
    if label:
        d.text((m_x + 6, m_y + 4), "5% SAFE", font=latin(12), fill=(70, 95, 105))


SPRITE = ROOT + "/game/art/operators/mizuki/mizuki_runtime_idle@1x.png"


def pixel_sprite(scale):
    """取水月待机第 1 帧，裁到内容，整数倍最近邻放大（全片同一倍数，§16.2）。"""
    sheet = Image.open(SPRITE).convert("RGBA")
    fh = sheet.height
    fr = sheet.crop((0, 0, fh, fh))
    fr = fr.crop(fr.getbbox())
    return fr.resize((fr.width * scale, fr.height * scale), Image.NEAREST)


def spotlight(img, cx, top, floor_y, cone_w, scale=6):
    """一束顶光：光锥（近乎纯色的梯形）+ 地面椭圆光圈 + 光里的像素干员。"""
    cone = Image.new("L", (W, H), 0)
    cd = ImageDraw.Draw(cone)
    cd.polygon([(cx - 40, top - 400), (cx + 40, top - 400), (cx + cone_w / 2, floor_y), (cx - cone_w / 2, floor_y)], fill=34)
    cd.ellipse((cx - cone_w / 2, floor_y - 46, cx + cone_w / 2, floor_y + 46), fill=70)
    cone = cone.filter(ImageFilter.GaussianBlur(3))
    img.paste((150, 225, 235), (0, 0), cone)
    sp = pixel_sprite(scale)
    img.paste(sp, (int(cx - sp.width / 2), int(floor_y - sp.height + 10)), sp)


def intro_card(out):
    """干员出场：整片暗 + 一束光 + 居中像素干员；名字底部居中小号（N1–N3）。"""
    img = Image.new("RGB", (W, H), BG_DEEP)
    spotlight(img, W // 2, 140, 820, 620, scale=8)
    d = ImageDraw.Draw(img)
    # 遮幅 2.39:1
    d.rectangle((0, 0, W, 138), fill=(0, 0, 0))
    d.rectangle((0, H - 138, W, H), fill=(0, 0, 0))
    # N1 中文名 Noto Serif SC 600 44 px 字距 0.2；N2 英文 Montserrat 14 px 0.4；N3 职业 · 分支 Sans 20 px
    tracked(d, (W / 2, 846), "水月", serif(44, 600), INK, 0.2, "m")
    tracked(d, (W / 2, 908), "MIZUKI", latin(14), INK_DIM, 0.4, "m")
    tracked(d, (W / 2, 932), "特种 · 伏击客", sans(20, 400), (120, 138, 150), 0.12, "m")
    img = _add_noise(img, Image.effect_noise((W, H), 30).point(lambda v: 128 + (v - 128) * 0.22))
    img.save(out)


# ————————————————————— 结尾卡 / 标题卡 —————————————————————
def end_card(out):
    img = Image.new("RGB", (W, H), BG_DEEP)   # 只留一盏光（左侧光锥），背景不再另打柔光
    d = ImageDraw.Draw(img)

    # 左侧：画面本身的纯色几何（一束光锥 + 地面光圈 + 像素干员），不画框、不加面板
    spotlight(img, 470, 300, 880, 760)
    d = ImageDraw.Draw(img)

    cx = int(W * 0.62)          # 版式重心放在右侧三分线附近（左侧留给主视觉 / 干员剪影）
    # 主标题：Noto Serif SC 600，132 px，字距 0.12 em
    f_title = serif(132, 600)
    tracked(d, (cx, 356), "方舟幸存者", f_title, INK, 0.12, "m")
    # 英文主标签：Montserrat Bold 30 px，全大写，字距 0.42 em
    tracked(d, (cx, 548), "ARKNIGHTS  SURVIVORS", latin(30, True), INK, 0.42, "m")
    # 细线 + 菱形（水月青）
    d.line((cx - 330, 600, cx - 22, 600), fill=CYAN, width=2)
    d.line((cx + 22, 600, cx + 330, 600), fill=CYAN, width=2)
    d.polygon([(cx, 591), (cx + 9, 600), (cx, 609), (cx - 9, 600)], fill=CYAN)
    # 副标题：Noto Serif SC 400，48 px，字距 0.32 em
    tracked(d, (cx, 636), "水月与深蓝之树", serif(48, 400), INK, 0.32, "m")
    # 副标题英文：Noto Serif（拉丁大写）400，24 px，字距 0.5 em，INK_DIM
    tracked(d, (cx, 712), "MIZUKI & CAERULA ARBOR", serif(24, 400), INK_DIM, 0.5, "m")

    # 行动语：Noto Sans SC 600，36 px，青色字，不加底条（§16）
    tracked(d, (cx, 790), "B站 Toy 点开即玩", sans(36, 600), CYAN, 0.12, "m")

    # 左下：同人声明（Noto Sans SC 400，20 px，字距 0.1 em，INK_DIM）
    tracked(d, (96, 990), "明日方舟同人作品 · 非官方", sans(20, 400), INK_DIM, 0.1)
    tracked(d, (96, 1018), "ARKNIGHTS FAN WORK  //  NOT AFFILIATED WITH HYPERGRYPH", latin(13), (110, 126, 138), 0.32)
    # 右上：微型代码标签（Montserrat SemiBold 14 px，字距 0.4 em，50% 灰）
    tracked(d, (W - 96, 70), "PV.01  //  DEEP-SEA DIVE", latin(14), (120, 138, 150), 0.4, "r")
    tracked(d, (W - 96, 94), "2026.11", latin(14), (120, 138, 150), 0.4, "r")

    img = _add_noise(img, Image.effect_noise((W, H), 30).point(lambda v: 128 + (v - 128) * 0.22))
    img.save(out)


# ————————————————————— 画面标注 + 角落标名 + 字幕 —————————————————————
def word_card(out):
    img = deep_bg(seed=23, light=(0.25, 0.22))
    d = ImageDraw.Draw(img)

    # ① 画面标注（压在实机画面上，指着一个对象）：圆环标记 + 折线 + 中文 28 px + 英文 13 px + 说明 22 px
    tx, ty = 520, 470                                   # 被标注对象（样张里是占位圆）
    d.ellipse((tx - 46, ty - 46, tx + 46, ty + 46), outline=(60, 84, 96), width=1)
    d.ellipse((tx - 30, ty - 30, tx + 30, ty + 30), outline=CYAN, width=2)
    d.line((tx + 22, ty - 22, tx + 90, ty - 90, tx + 300, ty - 90), fill=CYAN, width=1)
    tracked(d, (tx + 100, ty - 132), "集火目标", sans(28, 500), INK, 0.1)
    tracked(d, (tx + 100, ty - 80), "FOCUS TARGET  //  ELITE", latin(13), (120, 138, 150), 0.4)
    tracked(d, (tx + 100, ty - 56), "指挥圆盘选中后，全队优先攻击", sans(22, 400), INK_DIM, 0.06)

    # ③ 角落终结技标名（右下）：Noto Sans SC 700 32 px + 英文 13 px
    rx, ry = W - 96, 820
    tracked(d, (rx, ry), "浊心斯卡蒂", sans(32, 700), INK, 0.1, "r")
    d.line((rx - 230, ry + 50, rx, ry + 50), fill=CYAN, width=2)
    tracked(d, (rx, ry + 60), "ULTIMATE  //  SKADI THE CORRUPTING HEART", latin(13), (120, 138, 150), 0.32, "r")

    # ④ 旁白字幕：中文 Noto Sans SC 500 36 px，英文 Noto Sans 400 24 px，居中，y≈90%
    f_sub = sans(36, 500)
    f_sub_en = sans(24, 400)
    zh = "招募干员，组成小队一起作战。"
    en = "Recruit operators and fight as a squad."
    for (txt, f, col, y) in ((en, f_sub_en, INK_DIM, 924), (zh, f_sub, INK, 958)):
        # 柔阴影代替描边
        sh = Image.new("L", (W, H), 0)
        ImageDraw.Draw(sh).text((W / 2, y), txt, font=f, fill=180, anchor="mt")
        sh = sh.filter(ImageFilter.GaussianBlur(4))
        img.paste((0, 0, 0), (0, 0), sh.point(lambda v: v * 0.7))
        d = ImageDraw.Draw(img)
        d.text((W / 2, y), txt, font=f, fill=col, anchor="mt")

    img = _add_noise(img, Image.effect_noise((W, H), 30).point(lambda v: 128 + (v - 128) * 0.22))
    img.save(out)


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "."
    os.makedirs(out, exist_ok=True)
    end_card(os.path.join(out, "typecard_end.png"))
    word_card(os.path.join(out, "typecard_word.png"))
    intro_card(os.path.join(out, "typecard_intro.png"))
    print("ok", out)
