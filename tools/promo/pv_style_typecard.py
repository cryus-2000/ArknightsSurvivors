"""PV 字卡样张（docs/327 鹰角 PV 风格规范 §4 的落地示例）。

出两张 1920×1080：
  typecard_end.png   结尾卡 / 标题卡：主标题 + 副标题 + 英文标签 + 结尾行动语 + 同人声明
  typecard_word.png  大字卡 + 干员名字条 + 角落终结技标名 + 旁白字幕（同一画面里按真实字号排）

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


# ————————————————————— 结尾卡 / 标题卡 —————————————————————
def end_card(out):
    img = deep_bg(seed=11, light=(0.72, 0.30))
    d = ImageDraw.Draw(img)

    # 左侧留给主视觉 / 干员剪影（样张只画占位框，成片放 3D 水月或主视觉）
    for i in range(0, 760, 24):
        d.line((150, 200 + i, 150, 212 + i), fill=(40, 60, 72))
        d.line((820, 200 + i, 820, 212 + i), fill=(40, 60, 72))
    for i in range(0, 670, 24):
        d.line((150 + i, 200, 162 + i, 200), fill=(40, 60, 72))
        d.line((150 + i, 960, 162 + i, 960), fill=(40, 60, 72))
    tracked(d, (485, 568), "KEY VISUAL", latin(14), (60, 84, 96), 0.4, "m")

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

    # 行动语：Noto Sans SC 700，40 px，青色小底条
    cta = "B站 Toy 点开即玩"
    f_cta = sans(40, 700)
    tw = d.textlength(cta, font=f_cta) + 40 * 0.08 * (len(cta) - 1)
    bx0, by0 = cx - tw / 2 - 28, 812
    d.rectangle((bx0, by0, bx0 + tw + 56, by0 + 68), fill=(94, 230, 230))
    tracked(d, (cx, by0 + 6), cta, f_cta, BG_DEEP, 0.08, "m")

    # 左下：同人声明（Noto Sans SC 400，20 px，字距 0.1 em，INK_DIM）
    tracked(d, (96, 990), "明日方舟同人作品 · 非官方", sans(20, 400), INK_DIM, 0.1)
    tracked(d, (96, 1018), "ARKNIGHTS FAN WORK  //  NOT AFFILIATED WITH HYPERGRYPH", latin(13), (110, 126, 138), 0.32)
    # 右上：微型代码标签（Montserrat SemiBold 14 px，字距 0.4 em，50% 灰）
    tracked(d, (W - 96, 70), "PV.01  //  DEEP-SEA DIVE", latin(14), (120, 138, 150), 0.4, "r")
    tracked(d, (W - 96, 94), "2026.11", latin(14), (120, 138, 150), 0.4, "r")

    img = _add_noise(img, Image.effect_noise((W, H), 30).point(lambda v: 128 + (v - 128) * 0.22))
    img.save(out)


# ————————————————————— 大字卡 + 名字条 + 字幕 —————————————————————
def word_card(out):
    img = deep_bg(seed=23, light=(0.25, 0.22))
    d = ImageDraw.Draw(img)

    # ① 大字卡主字：Noto Serif SC 400（细衬线），180 px，竖排，放左三分线
    vertical(d, (560, 170), "灯火", serif(180, 400), INK, gap=0.04)
    # 注释小字：Noto Serif SC 400，38 px，竖排在主字右下，70% 亮度
    vertical(d, (700, 372), "将熄未熄", serif(38, 400), INK_DIM, gap=0.1)
    # 英文微标签：Montserrat SemiBold 14 px，字距 0.4 em，贴细线
    d.line((470, 160, 470, 600), fill=(70, 90, 100), width=1)
    tracked(d, (480, 616), "LAMPLIGHT  //  01", latin(14), (120, 138, 150), 0.4)

    # ② 干员名字条（右侧）：英文代号做底纹大字，中文名压上去
    nx = 1180
    tracked(d, (nx - 20, 250), "MIZUKI", latin(170, True), (24, 48, 60), 0.02)   # 底纹：同色系暗一档，不抢主体
    d.rectangle((nx, 330, nx + 8, 470), fill=CYAN)                            # 竖色条
    tracked(d, (nx + 36, 318), "水月", serif(96, 700), INK, 0.08)
    tracked(d, (nx + 40, 448), "特种 · 伏击客", sans(26, 500), INK_DIM, 0.12)
    tracked(d, (nx + 40, 494), "SPECIALIST  //  AMBUSHER", latin(15), (120, 138, 150), 0.4)

    # ③ 角落终结技标名（右下）：Noto Sans SC 700 32 px + 英文 13 px
    rx, ry = W - 96, 820
    tracked(d, (rx, ry), "浊心斯卡蒂", sans(32, 700), INK, 0.1, "r")
    d.line((rx - 230, ry + 50, rx, ry + 50), fill=CYAN, width=2)
    tracked(d, (rx, ry + 60), "ULTIMATE  //  SKADI THE CORRUPTING HEART", latin(13), (120, 138, 150), 0.32, "r")

    # ④ 旁白字幕：中文 Noto Sans SC 500 36 px，英文 Noto Sans 400 24 px，居中，y≈90%
    f_sub = sans(36, 500)
    f_sub_en = sans(24, 400)
    zh = "灯火还亮着，就还有人在走。"
    en = "As long as the lamp is lit, someone is still walking."
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
    print("ok", out)
