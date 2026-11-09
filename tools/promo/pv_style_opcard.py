"""干员出场样张（docs/327 §17：按鹰角活动 PV「NEW OPERATOR」段改成像素版）。

出两张：
  opcard_name.png      名字卡：像素海底背景 + 像素干员 + 超大英文代号 + 中文名 / 职业 / 编号小字簇
  opcard_sequence.jpg  一位干员出场：镜头贴近、剪影亮起 → 拉开后代号故障出字 → 小字淡入定格 → 实机技能

用法：python tools/promo/pv_style_opcard.py <输出目录> [实机截图路径]
字体同 pv_style_typecard（Noto Serif/Sans SC VF + 仓库 Montserrat，OFL）。英文代号用窄粗体
Oswald 700（缺省）或 Bebas Neue（环境变量 PV_NAME_FONT=bebas），字体在 tools/promo/fonts（SIL OFL 1.1，11-08 用户同意下载）。
"""
import os
import random
import sys

from PIL import Image, ImageChops, ImageDraw, ImageEnhance, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pv_style_typecard as tc  # noqa: E402

W, H = tc.W, tc.H
ART = tc.ROOT + "/game/art"
FACE = os.environ.get("PV_NAME_FONT", "oswald")
NAME_PX = {"oswald": 236, "bebas": 250}   # 字号使字高 ≈ 175 px
LB = 131  # 2.35:1 遮幅，上下各 131 px（实测官方新干员段 2.35:1）


def frame(path, idx, size):
    sh = Image.open(path).convert("RGBA")
    fr = sh.crop((idx * size, 0, idx * size + size, size))
    return fr.crop(fr.getbbox())


def px(im, k):
    return im.resize((im.width * k, im.height * k), Image.NEAREST)


FONTS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fonts")


def display(size, face="oswald"):
    """大号英文代号用的窄粗体（tools/promo/fonts，SIL OFL 1.1）：oswald = Oswald 700，bebas = Bebas Neue。"""
    from PIL import ImageFont
    if face == "bebas":
        return ImageFont.truetype(os.path.join(FONTS, "BebasNeue-Regular.ttf"), size)
    f = ImageFont.truetype(os.path.join(FONTS, "Oswald-VF.ttf"), size)
    f.set_variation_by_axes([700])
    return f


def condensed_text(text, font, fill, squeeze=0.78, tracking=0.02):
    """画一行字再横向压缩，冒充窄体（成片换真正的窄体字）。"""
    tmp = Image.new("RGBA", (int(font.size * len(text) * 1.2), int(font.size * 1.4)), (0, 0, 0, 0))
    d = ImageDraw.Draw(tmp)
    tc.tracked(d, (0, 0), text, font, fill, tracking)
    tmp = tmp.crop(tmp.getbbox())
    return tmp.resize((int(tmp.width * squeeze), tmp.height), Image.LANCZOS)


def checker(d, x, y, s=10, col=(236, 241, 244)):
    """官方卡角落那种 2×2 小方格（每格 s px）。"""
    d.rectangle((x, y, x + s, y + s), fill=col)
    d.rectangle((x + s, y + s, x + 2 * s, y + 2 * s), fill=col)


def sea_snow(img, n, seed, rmin=1, rmax=3, alpha=(60, 160)):
    rnd = random.Random(seed)
    lay = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(lay)
    for _ in range(n):
        x, y = rnd.uniform(0, W), rnd.uniform(LB, H - LB)
        s = rnd.choice(range(rmin, rmax + 1)) * 4      # 方块像素颗粒，4 px 一格
        d.rectangle((x, y, x + s, y + s), fill=(200, 240, 245, rnd.randint(*alpha)))
    img.alpha_composite(lay)


def background(seed=5):
    bg = Image.open(ART + "/ui/title_deep/bg.png").convert("RGB")
    bg = bg.resize((bg.width * 5, bg.height * 5), Image.NEAREST)          # 428×240 → 2140×1200，整数倍
    bg = bg.crop(((bg.width - W) // 2, (bg.height - H) // 2, (bg.width - W) // 2 + W, (bg.height - H) // 2 + H))
    bg = ImageEnhance.Color(bg).enhance(0.75)
    img = bg.convert("RGBA")
    # 一束青白顶光（画面里唯一的大亮形）
    shaft = Image.new("L", (W, H), 0)
    ImageDraw.Draw(shaft).polygon([(1180, LB), (1420, LB), (1620, H - LB), (1000, H - LB)], fill=46)
    shaft = shaft.filter(ImageFilter.GaussianBlur(30))
    img.paste((170, 235, 240, 255), (0, 0), shaft)
    # 远处水母（标题页素材，整数倍），压暗当背景
    for i, (x, y, k) in enumerate(((300, 210, 2), (760, 160, 1), (1700, 260, 2))):
        j = Image.open(ART + "/ui/title_deep/jelly_%d.png" % (i % 3)).convert("RGBA")
        j = px(j, k)
        j.putalpha(j.getchannel("A").point(lambda a: int(a * 0.35)))
        img.alpha_composite(j, (x, y))
    sea_snow(img, 140, seed)
    return img


def letterbox(img):
    d = ImageDraw.Draw(img)
    d.rectangle((0, 0, W, LB), fill=(0, 0, 0, 255))
    d.rectangle((0, H - LB, W, H), fill=(0, 0, 0, 255))


def name_card(glitch=False, text=True, lit=1.0):
    """lit < 1：人物压成剪影（出场第一拍）；text=False：还没出字。"""
    img = background()
    # 像素干员：技能攻击帧，整数倍最近邻放大（全片统一一个倍数）
    raw = frame(ART + "/operators/mizuki/mizuki_runtime_skill_attack@2x.png", 3, 192)
    k = max(1, int((H - 2 * LB) * 0.88) // raw.height)          # 整数倍，人物约占画面高 88%（官方立绘几乎顶天立地）
    op = px(raw, k)
    ox, oy = 1300 - op.width // 2, H - LB - op.height - 16
    # 人物对准光束：光束底边中心 = 人物脚下中心（1300），脚下一圈地面光
    gl = Image.new("L", (W, H), 0)
    ImageDraw.Draw(gl).ellipse((1300 - 300, H - LB - 70, 1300 + 300, H - LB + 10), fill=int(90 * max(lit, 0.3)))
    img.paste((170, 235, 240, 255), (0, 0), gl.filter(ImageFilter.GaussianBlur(14)))
    if lit < 1.0:
        dark = Image.new("RGBA", op.size, (6, 14, 24, 255))
        dark.putalpha(op.getchannel("A"))
        op = Image.blend(dark, op, lit)
        op.putalpha(dark.getchannel("A"))
    # 青色边光：剪影向左上偏 6 px 垫在后面
    rim = Image.new("RGBA", op.size, (94, 230, 230, 0))
    rim.putalpha(op.getchannel("A"))
    img.alpha_composite(rim, (ox - 6, oy - 6))
    img.alpha_composite(op, (ox, oy))
    # 前景：近处大颗方块海雪（虚）
    fg = Image.new("RGBA", img.size, (0, 0, 0, 0))
    fd = ImageDraw.Draw(fg)
    for (x, y, s) in ((120, 760, 36), (1760, 300, 28), (1560, 820, 44), (420, 220, 24)):
        fd.rectangle((x, y, x + s, y + s), fill=(200, 240, 245, 70))
    img.alpha_composite(fg.filter(ImageFilter.GaussianBlur(6)))

    d = ImageDraw.Draw(img)
    if not text:
        letterbox(img)
        return tc._add_noise(img.convert("RGB"), Image.effect_noise((W, H), 30).point(lambda v: 128 + (v - 128) * 0.2))
    checker(d, 120, 236)
    checker(d, 160, 270, 8)
    tc.tracked(d, (124, 330), "‹  集成战略 · 水月与深蓝之树  ›", tc.sans(22, 500), tc.INK, 0.08)
    # 超大英文代号：窄粗体，字高 ≈ 180 px（官方实测 165–180），占画宽 ≈ 40%
    nm = condensed_text("MIZUKI", display(NAME_PX[FACE], FACE), tc.INK + (255,), 1.0, 0.04)
    nx, ny = 112, 372
    if glitch:
        tint = Image.new("RGBA", nm.size, (94, 230, 230, 255))
        tint.putalpha(nm.getchannel("A").point(lambda a: int(a * 0.8)))
        img.alpha_composite(tint, (nx + 14, ny))
        rnd = random.Random(3)
        hh = nm.height // 5
        for k in range(5):
            sl = nm.crop((0, k * hh, nm.width, (k + 1) * hh))
            img.alpha_composite(sl, (nx + rnd.randint(-40, 40), ny + k * hh))
    else:
        img.alpha_composite(nm, (nx, ny))
    y2 = ny + nm.height + 34
    tc.tracked(d, (124, y2), "水月", tc.serif(56, 700), tc.INK, 0.2)
    icon = Image.open(ART + "/ui/professions/special.png").convert("RGBA")
    img.alpha_composite(icon, (300, y2 + 14))
    tc.tracked(d, (356, y2 + 22), "特种 · 伏击客", tc.sans(22, 500), tc.INK_DIM, 0.1)
    tc.tracked(d, (124, y2 + 92), "示例小字：这一行写这名干员在本作里做什么（按 docs/76，写事实）", tc.sans(18, 400), (150, 166, 178), 0.04)
    rx = 1560
    tc.tracked(d, (rx, 560), "OPERATOR  01", tc.latin(22, True), tc.INK, 0.12)
    d.line((rx, 594, rx + 240, 594), fill=tc.INK, width=2)
    tc.tracked(d, (rx, 606), "SPECIALIST  //  AMBUSHER", tc.latin(13), (150, 166, 178), 0.3)
    tc.tracked(d, (W - 112, H - LB - 40), "01 / 04", tc.latin(14), (150, 166, 178), 0.4, "r")
    letterbox(img)
    img = tc._add_noise(img.convert("RGB"), Image.effect_noise((W, H), 30).point(lambda v: 128 + (v - 128) * 0.2))
    return img


def glitch_frame(base):
    """故障转场一帧：横带错位 + RGB 分离 + 扫描线。"""
    im = base.copy()
    rnd = random.Random(4)
    for _ in range(14):
        y = rnd.randint(LB, H - LB - 40)
        h = rnd.randint(8, 60)
        band = im.crop((0, y, W, y + h))
        im.paste(band, (rnd.randint(-120, 120), y))
    r, g, b = im.split()
    im = Image.merge("RGB", (ImageChops.offset(r, 10, 0), g, ImageChops.offset(b, -10, 0)))
    d = ImageDraw.Draw(im)
    for y in range(LB, H - LB, 4):
        d.line((0, y, W, y), fill=(0, 0, 0), width=1)
    return im


def sequence(card, glitch_card, gameplay_path):
    half = (960, 540)
    if gameplay_path and os.path.exists(gameplay_path):
        gp = Image.open(gameplay_path).convert("RGB")
    else:
        gp = Image.new("RGB", (W, H), (20, 30, 40))
    # ② 贴近：从拉开后的画面里裁人物附近（相当于镜头推近 1.6 倍），人物还是剪影
    sil = name_card(text=False, lit=0.25)
    cw, ch = int(W / 1.6), int(H / 1.6)
    close = sil.crop((1300 - cw // 2, H - ch - 40, 1300 + cw // 2, H - 40)).resize((W, H), Image.NEAREST)
    panels = [
        (close.resize(half, Image.LANCZOS), "① 镜头贴近，人物剪影在光里亮起", "无字；0.8 s 内拉开"),
        (glitch_card.resize(half, Image.LANCZOS), "② 拉开到位后代号故障出字", "第 30 帧起，4–6 帧故障"),
        (card.resize(half, Image.LANCZOS), "③ 小字淡入，定格到 1 小节末", "故障转场 → 这名干员的实机"),
        (gp.resize(half, Image.LANCZOS), "④ 实机：这名干员放技能", "0.5–1 小节，叠海雪 + 暗角；再转下一位"),
    ]
    out = Image.new("RGB", (1920, 1240), (14, 18, 24))
    d = ImageDraw.Draw(out)
    tc.tracked(d, (40, 22), "干员出场（先出场后技能：名字卡 1 小节 → 实机技能 0.5–1 小节）", tc.sans(28, 600), tc.INK, 0.02)
    for i, (im, t1, t2) in enumerate(panels):
        x, y = (i % 2) * 960, 80 + (i // 2) * 580
        out.paste(im, (x, y))
        tc.tracked(d, (x + 20, y + 546), t1 + "　" + t2, tc.sans(20, 500), tc.INK, 0.02)
    return out


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "."
    gp = sys.argv[2] if len(sys.argv) > 2 else None
    os.makedirs(out, exist_ok=True)
    card = name_card()
    card.save(os.path.join(out, "opcard_name.png"))
    sequence(card, name_card(glitch=True), gp).save(os.path.join(out, "opcard_sequence.jpg"), quality=90)
    print("ok", out)
