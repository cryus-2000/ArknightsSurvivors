"""主界面视觉方案样图（docs/125 §7，10-22 用户参照图 build/ui_ref/title_ref_1022.png：像素夜海、银河、灯塔一点暖光、青色荧光浪线、水母）。

只出样图、不改游戏代码：背景是参照图的临时裁切（正式像素背景之后交 Codex 画），界面按寻访 hh_style 语言用 PIL 画。
  A  = 保留 T5a 版式（Logo + 磁贴菜单 + 封面干员 + 页脚），只换背景气质
  B  = 明日方舟式非对称：左侧竖排菜单（大号中文 + 像素描边英文 + 编号）、右侧留给场景、灯塔当视觉锚点、顶栏难度档与凭证数
  C  = B 的手机横屏（1480×720，--touch 的版面 1280×623）
用法：python -X utf8 tools/probes/title_ref_mock.py
输出：主仓库 build/ak_mock/title_ref_{A,B,C_phone}.png 与总览 title_ref_sheet.jpg
"""
import os
import re
import subprocess
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
COMMON = os.path.dirname(os.path.abspath(subprocess.run(["git", "rev-parse", "--git-common-dir"], cwd=ROOT, capture_output=True, text=True).stdout.strip()
                                         if os.path.isabs(subprocess.run(["git", "rev-parse", "--git-common-dir"], cwd=ROOT, capture_output=True, text=True).stdout.strip())
                                         else os.path.join(ROOT, subprocess.run(["git", "rev-parse", "--git-common-dir"], cwd=ROOT, capture_output=True, text=True).stdout.strip())))
REF = os.path.join(COMMON, "build", "ui_ref", "title_ref_1022.png")
OUT = os.path.join(COMMON, "build", "ak_mock")
FONT = os.path.join(ROOT, "game", "fonts", "ui.ttf")
INK = (17, 19, 24)
LIGHT = (223, 226, 230)
CYB = (56, 214, 240)
YEL = (255, 206, 0)
MUTE = (150, 156, 166)
NAVY = (8, 16, 30)
WARM = (255, 196, 110)

# 5×7 像素字（同 game/scripts/screens/tide_ui.gd 的 GLYPHS）
_src = open(os.path.join(ROOT, "game", "scripts", "screens", "tide_ui.gd"), encoding="utf8").read()
GLYPHS = {m.group(1): [int(x, 16) for x in m.group(2).split()] for m in re.finditer(r'"(.)": "([0-9A-F ]{20})"', _src)}


def font(sz):
    return ImageFont.truetype(FONT, sz)


def text(d, xy, s, sz, col, anchor="la", bold=False):
    f = font(sz)
    if bold:
        d.text(xy, s, font=f, fill=col, anchor=anchor, stroke_width=1, stroke_fill=col)
    else:
        d.text(xy, s, font=f, fill=col, anchor=anchor)


def spaced(d, xy, s, sz, col, gap=4):
    x, y = xy
    f = font(sz)
    for ch in s:
        d.text((x, y), ch, font=f, fill=col)
        x += d.textlength(ch, font=f) + gap
    return x - xy[0]


def px_text(img, xy, s, k, col, outline=None, fill_col=None):
    """像素字：k = 每个字像素的屏幕像素；outline 给定时画描边（中间填 fill_col，None = 透明）"""
    lay = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(lay)
    x0, y0 = xy

    def glyphs(ox, oy, c):
        x = x0 + ox
        for ch in s.upper():
            g = GLYPHS.get(ch)
            if g:
                for r in range(7):
                    for cc in range(5):
                        if g[r] & (1 << (4 - cc)):
                            d.rectangle([x + cc * k, y0 + oy + r * k, x + cc * k + k - 1, y0 + oy + r * k + k - 1], fill=c)
            x += (3 if ch == " " else 6) * k
    if outline:
        o = max(1, k // 3)
        for dx, dy in ((-o, 0), (o, 0), (0, -o), (0, o), (-o, -o), (o, o), (-o, o), (o, -o)):
            glyphs(dx, dy, outline)
        glyphs(0, 0, fill_col if fill_col else (0, 0, 0, 0))
        if not fill_col:   # 透明芯：把芯挖空
            hole = Image.new("RGBA", img.size, (0, 0, 0, 0))
            hd = ImageDraw.Draw(hole)
            x = x0
            for ch in s.upper():
                g = GLYPHS.get(ch)
                if g:
                    for r in range(7):
                        for cc in range(5):
                            if g[r] & (1 << (4 - cc)):
                                hd.rectangle([x + cc * k, y0 + r * k, x + cc * k + k - 1, y0 + r * k + k - 1], fill=(255, 255, 255, 255))
                x += (3 if ch == " " else 6) * k
            a = lay.split()[3].point(lambda v: v)
            lay.putalpha(Image.composite(Image.new("L", img.size, 0), a, hole.split()[3]))
    else:
        glyphs(0, 0, col)
    img.alpha_composite(lay)


def bg(w, h, mirror=False):
    """参照图临时裁切：等比放大铺满再居中裁（B / C 镜像，让灯塔落在右侧、亮浪线落在左下菜单后面压暗）"""
    im = Image.open(REF).convert("RGBA")
    if mirror:
        im = im.transpose(Image.FLIP_LEFT_RIGHT)
    k = max(w / im.width, h / im.height)
    im = im.resize((round(im.width * k), round(im.height * k)), Image.NEAREST)
    x = (im.width - w) // 2
    y = (im.height - h) // 2
    return im.crop((x, y, x + w, y + h)), k, x, y


def note(img, xy, s, sz=12):
    """样图标注（青色虚线框小字），正式版没有"""
    d = ImageDraw.Draw(img)
    f = font(sz)
    w = d.textlength(s, font=f)
    x, y = xy
    d.rectangle([x - 6, y - 4, x + w + 6, y + sz + 6], fill=(4, 10, 18, 200), outline=CYB)
    d.text((x, y), s, font=f, fill=CYB)


def emblem(d, c, r, col):
    """本作徽记：菱形 + 一道浪"""
    x, y = c
    d.polygon([(x, y - r), (x + r, y), (x, y + r), (x - r, y)], outline=col, width=2)
    pts = [(x - r * 0.6 + i * r * 0.12, y + 0.18 * r * (1 if i % 2 else -1)) for i in range(11)]
    d.line(pts, fill=col, width=2)


def voucher(d, c, s=1.0):
    x, y = c
    d.rectangle([x - 18 * s, y - 10 * s, x + 18 * s, y + 10 * s], fill=(240, 244, 248), outline=INK, width=2)
    d.rectangle([x - 15 * s, y - 7 * s, x - 10 * s, y + 7 * s], fill=CYB)
    d.rectangle([x - 4 * s, y + 3 * s, x + 14 * s, y + 6 * s], fill=(40, 90, 200))


def paste_op(img, foot, k):
    """封面干员（水月待机第 0 帧 @2x，整数倍）"""
    p = os.path.join(ROOT, "art", "incoming", "mizuki_runtime_idle@2x.png")
    if not os.path.exists(p):
        return
    st = Image.open(p).convert("RGBA")
    fw = st.width // 36
    fr = st.crop((0, 0, fw, st.height))
    bb = fr.getbbox()
    fr = fr.crop(bb).resize(((bb[2] - bb[0]) * k, (bb[3] - bb[1]) * k), Image.NEAREST)
    img.alpha_composite(fr, (int(foot[0] - fr.width / 2), int(foot[1] - fr.height)))


# ---------------------------------------------------------------- A：T5a 版式只换背景
def make_a():
    W, H = 1280, 720
    img, k, ox, oy = bg(W, H)
    d = ImageDraw.Draw(img)
    # 左侧压暗一条（读字），不改版式
    sh = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(sh).rectangle([0, 0, 520, H], fill=(2, 6, 14, 120))
    img.alpha_composite(sh)
    logo = Image.open(os.path.join(ROOT, "art", "incoming", "logo.png")).convert("RGBA")
    img.alpha_composite(logo, (40, 36))
    tiles = [[("01", "集结出发", "OPERATION", 440, 96)], [("02", "图鉴", "ARCHIVE", 214, 70), ("03", "Boss 演练", "TRIAL", 214, 70)],
             [("04", "操作说明", "GUIDE", 138, 56), ("05", "设置", "SETTINGS", 138, 56), ("06", "退出", "EXIT", 138, 56)]]
    y = 200
    for row in tiles:
        x = 40
        for i, (no, cn, en, w, h) in enumerate(row):
            sel = no == "01"
            fill = (238, 243, 246, 235) if sel else (12, 26, 48, 215)
            lay = Image.new("RGBA", (W, H), (0, 0, 0, 0))
            ld = ImageDraw.Draw(lay)
            ld.rectangle([x, y, x + w, y + h], fill=fill, outline=(60, 200, 228) if sel else (44, 98, 124), width=2 if sel else 1)
            img.alpha_composite(lay)
            ink = (10, 28, 52) if sel else (228, 236, 244)
            if sel:
                # 选中块底部潮线（T5s S4）
                d.rectangle([x + 2, y + h - 12, x + w - 2, y + h - 2], fill=(30, 92, 116))
                d.line([(x + 2, y + h - 12), (x + w - 2, y + h - 12)], fill=(200, 255, 255), width=2)
            px_text(img, (x + 12, y + 10), no, 2, (24, 130, 160) if sel else (96, 224, 232))
            csz = 30 if sel else (18 if h > 60 else 15)
            text(d, (x + 12, y + h - (18 if sel else 12)), cn, csz, ink, anchor="ls", bold=True)
            cw = d.textlength(cn, font=font(csz))
            if h > 60:
                px_text(img, (int(x + 22 + cw), y + h - (18 if sel else 12) - 14), en, 2, (70, 92, 112) if sel else (138, 160, 182))
            x += w + 12
        y += row[0][4] + 12
    paste_op(img, (W * 0.72, H - 132), 2)
    text(d, (W - 260, H - 70), "◇ 更换封面干员  V", 14, (200, 220, 230))
    text(d, (40, H - 30), "明日方舟同人作品 · 非商业 · 与鹰角网络无关 · 致谢与声明 C · V2.0", 12, (150, 170, 190))
    note(img, (760, 40), "A：保留 T5a 版式，只换背景（背景为参照图临时裁切，正式像素背景交 Codex）")
    note(img, (430 * k / 1.25 + 40, 300), "灯塔暖光：一点脉动（2.4 秒呼吸）")
    note(img, (760, 520), "浪线荧光呼吸 + 水母慢漂（常驻动效）")
    return img.convert("RGB")


# ---------------------------------------------------------------- B / C：明日方舟式非对称
MENU = [("01", "集结出发", "DEPLOY"), ("02", "选人", "OPERATOR"), ("03", "图鉴", "ARCHIVE"), ("04", "寻访", "HEADHUNT"), ("05", "认知塑造", "COGNITION"), ("06", "设置", "SETTINGS")]


def make_b(W=1280, H=720, phone=False):
    img, k, ox, oy = bg(W, H, mirror=True)
    s = 1.18 if phone else 1.0
    # 主题色只铺斜块（S3）：左侧深藏青斜板 + 一道青细斜线
    lay = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ld = ImageDraw.Draw(lay)
    pw = int(500 * s)
    ld.polygon([(0, 0), (pw, 0), (pw - 170, H), (0, H)], fill=(4, 10, 20, 205))
    ld.polygon([(pw + 6, 0), (pw + 12, 0), (pw - 158, H), (pw - 164, H)], fill=CYB + (200,))
    ld.polygon([(pw + 40, 0), (pw + 44, 0), (pw - 126, H), (pw - 130, H)], fill=(60, 200, 228, 70))
    img.alpha_composite(lay)
    d = ImageDraw.Draw(img)
    # 巨型描边英文（S1），压在夜空里
    px_text(img, (int(560 * s) if not phone else 560, 60), "DEEP TIDE", 16 if not phone else 13, None, outline=(200, 230, 255, 60))
    # 顶栏：徽记 + 小 Logo / 难度档 / 凭证
    th = int(56 * s)
    tb = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(tb).rectangle([0, 0, W, th], fill=(3, 7, 14, 170))
    img.alpha_composite(tb)
    d.line([(0, th), (W, th)], fill=(255, 255, 255, 90), width=1)
    emblem(d, (int(34 * s), th // 2), int(14 * s), (200, 255, 255))
    spaced(d, (int(58 * s), th // 2 - int(9 * s)), "RHODES ISLAND  //  NIGHT SEA", int(11 * s), (200, 220, 230), 3)
    tiers = [("常规", False), ("高压", True), ("深潮", False)]
    x = W - int(560 * s)
    text(d, (x - int(56 * s), th // 2), "潮位", int(13 * s), MUTE, anchor="lm")
    for nm, on in tiers:
        w = int(86 * s)
        d.polygon([(x + 10, th // 2 - int(15 * s)), (x + w, th // 2 - int(15 * s)), (x + w - 10, th // 2 + int(15 * s)), (x, th // 2 + int(15 * s))],
                  fill=CYB if on else (12, 22, 34), outline=None if on else (90, 120, 140))
        text(d, (x + w // 2, th // 2), nm, int(15 * s), INK if on else (200, 215, 225), anchor="mm", bold=on)
        x += w + 6
    voucher(d, (W - int(190 * s), th // 2), s)
    text(d, (W - int(162 * s), th // 2), "寻访凭证 ×3", int(16 * s), (230, 240, 245), anchor="lm", bold=True)
    # 左侧竖排菜单：编号 + 大号中文 + 像素描边英文；选中 = 浅色斜条 + 青竖条
    y = th + int(34 * s) if not phone else th + 18
    step = int(84 * s) if not phone else int((H - th - 70) / len(MENU))
    for i, (no, cn, en) in enumerate(MENU):
        sel = i == 0
        if sel:
            sel_l = Image.new("RGBA", (W, H), (0, 0, 0, 0))
            sd = ImageDraw.Draw(sel_l)
            sd.polygon([(0, y - 6), (int(430 * s), y - 6), (int(410 * s), y + step - 14), (0, y + step - 14)], fill=LIGHT + (240,))
            img.alpha_composite(sel_l)
            d.rectangle([0, y - 6, 6, y + step - 14], fill=CYB)
        ink = INK if sel else (232, 238, 244)
        px_text(img, (int(30 * s), y + 6), no, 2, (24, 130, 160) if sel else (96, 224, 232))
        text(d, (int(66 * s), y - 4), cn, int((40 if sel else 30) * s), ink, bold=True)
        cw = d.textlength(cn, font=font(int((40 if sel else 30) * s)))
        px_text(img, (int(66 * s + cw + 16), y + int(14 * s)), en, 3 if not phone else 2, None,
                outline=(80, 90, 100, 255) if sel else (150, 175, 195, 200), fill_col=None)
        if no == "04":
            d.ellipse([int(66 * s + cw + 2), y - 8, int(66 * s + cw + 22), y + 12], fill=CYB)
            text(d, (int(66 * s + cw + 12), y + 2), "3", 12, INK, anchor="mm", bold=True)
        y += step
    spaced(d, (int(30 * s), H - int(46 * s) if not phone else H - 34), "试炼（测试版）  ·  BOSS TRIAL", int(12 * s), (140, 160, 175), 2)
    if not phone:
        text(d, (int(30 * s), H - 22), "明日方舟同人作品 · 非商业 · 与鹰角网络无关", 11, (120, 140, 155))
    # 封面干员站在右侧礁石上（原尺寸 2 倍），灯塔是视觉锚点
    paste_op(img, (W * 0.80, H * 0.86), 2)
    lh_x = W - (365 * k - ox)   # 镜像后灯塔位置
    lh_y = 345 * k - oy
    if not phone:
        note(img, (int(lh_x) - 150, int(lh_y) - 70), "灯塔 = 视觉锚点（暖光一点、2.4 秒呼吸）")
        note(img, (760, 150), "水母慢漂（上下 6 px / 8 秒，横向随机漂）")
        note(img, (40, int(H * 0.83) - 120), "浪线荧光呼吸（压在暗斜板下，只透一点青光）")
        note(img, (760, H - 40), "背景为参照图临时裁切（左右镜像），正式像素背景交 Codex")
    else:
        note(img, (W - 520, H - 34), "C：手机横屏（--touch 版面 1280×623），菜单行高 ≥ 44 pt", 13)
    return img.convert("RGB")


def main():
    os.makedirs(OUT, exist_ok=True)
    a = make_a()
    b = make_b()
    c = make_b(1280, 623, phone=True)
    a.save(os.path.join(OUT, "title_ref_A.png"))
    b.save(os.path.join(OUT, "title_ref_B.png"))
    c.save(os.path.join(OUT, "title_ref_C_phone.png"))
    W = 640
    ims = [a, b, c]
    hs = [round(im.height * W / im.width) for im in ims]
    sheet = Image.new("RGB", (W * 2, hs[0] + max(hs[1:])), (0, 0, 0))
    sheet.paste(a.resize((W, hs[0]), Image.LANCZOS), (0, 0))
    sheet.paste(b.resize((W, hs[1]), Image.LANCZOS), (W, 0))
    sheet.paste(c.resize((W, hs[2]), Image.LANCZOS), (W // 2, hs[0]))
    sheet.save(os.path.join(OUT, "title_ref_sheet.jpg"), quality=88)
    print("ok", OUT)


main()
