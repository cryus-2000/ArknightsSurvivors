"""干员出场样张（docs/327 §17：按鹰角活动 PV「NEW OPERATOR」段改成像素版）。

出两张：
  opcard_name.png      名字卡：像素海底背景 + 像素干员 + 超大英文代号 + 中文名 / 职业 / 编号小字簇
  opcard_sequence.jpg  一位干员的四拍：实机放技能 → 名字卡（故障出字）→ 技能特写 → 故障转场

用法：python tools/promo/pv_style_opcard.py <输出目录> [实机截图路径]
字体同 pv_style_typecard（Noto Serif/Sans SC VF + 仓库 Montserrat，OFL）。英文代号成片建议换窄体粗体
（Oswald / Bebas Neue，OFL，需下载、先问用户）；样张里用 Montserrat Bold 横向压到 78% 代替。
"""
import os
import random
import sys

from PIL import Image, ImageChops, ImageDraw, ImageEnhance, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pv_style_typecard as tc  # noqa: E402

W, H = tc.W, tc.H
ART = tc.ROOT + "/game/art"
LB = 131  # 2.35:1 遮幅，上下各 131 px（实测官方新干员段 2.35:1）


def frame(path, idx, size):
    sh = Image.open(path).convert("RGBA")
    fr = sh.crop((idx * size, 0, idx * size + size, size))
    return fr.crop(fr.getbbox())


def px(im, k):
    return im.resize((im.width * k, im.height * k), Image.NEAREST)


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


def name_card(glitch=False):
    img = background()
    # 像素干员：技能攻击帧，整数倍最近邻放大（全片统一一个倍数）
    raw = frame(ART + "/operators/mizuki/mizuki_runtime_skill_attack@2x.png", 3, 192)
    k = max(1, int((H - 2 * LB) * 0.88) // raw.height)          # 整数倍，人物约占画面高 88%（官方立绘几乎顶天立地）
    op = px(raw, k)
    ox, oy = 1300 - op.width // 2, H - LB - op.height - 16
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
    checker(d, 120, 236)
    checker(d, 160, 270, 8)
    tc.tracked(d, (124, 330), "‹  集成战略 · 水月与深蓝之树  ›", tc.sans(22, 500), tc.INK, 0.08)
    # 超大英文代号：窄粗体，字高 ≈ 180 px（官方实测 165–180），占画宽 ≈ 40%
    nm = condensed_text("MIZUKI", tc.latin(230, True), tc.INK + (255,), 0.78, 0.04)
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


def skill_closeup():
    """技能特写：像素放大到 12 倍只露上半身 + 斜向速度线。"""
    img = Image.new("RGBA", (W, H), (6, 14, 24, 255))
    lay = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(lay)
    rnd = random.Random(9)
    for _ in range(46):
        y = rnd.uniform(0, H)
        L = rnd.uniform(300, 1100)
        x = rnd.uniform(-200, W)
        d.line((x, y, x + L, y - L * 0.35), fill=(94, 230, 230, rnd.randint(30, 110)), width=rnd.choice((2, 4, 8)))
    img.alpha_composite(lay)
    op = px(frame(ART + "/operators/mizuki/mizuki_runtime_skill_attack@2x.png", 5, 192), 12)
    img.alpha_composite(op, (W // 2 - op.width // 2 + 120, 120))
    d = ImageDraw.Draw(img)
    tc.tracked(d, (W - 140, H - LB - 70), "水月", tc.serif(40, 700), tc.INK, 0.2, "r")
    letterbox(img)
    return img.convert("RGB")


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
    panels = [
        (gp.resize(half, Image.LANCZOS), "① 实机：这名干员放技能", "0.5 小节（0.8 s），叠海雪 + 暗角"),
        (glitch_card.resize(half, Image.LANCZOS), "② 名字卡：代号故障式出字", "进场 4–6 帧故障，定格 1 小节"),
        (skill_closeup().resize(half, Image.LANCZOS), "③ 技能特写：像素放大 + 速度线", "0.5 小节，对重拍"),
        (glitch_frame(card).resize(half, Image.LANCZOS), "④ 故障转场 → 下一位", "2–3 帧"),
    ]
    out = Image.new("RGB", (1920, 1240), (14, 18, 24))
    d = ImageDraw.Draw(out)
    tc.tracked(d, (40, 22), "干员出场四拍（一位约 2 小节 ≈ 3.3 s；参照 2026 感谢庆典 PV 89.5–95.5 s）", tc.sans(28, 600), tc.INK, 0.02)
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
