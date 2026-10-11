# -*- coding: utf-8 -*-
"""标题页 / 局外菜单 T1′ 修订概念图（docs/67 §9，2026-10-11 用户：「T1目前的颜色和结构是不是有点奇怪」）。

只是给人看的概念图，不改游戏代码。底图沿用 tools/concept_title_ui.py 截好的现状（主仓库 build/title_redesign/shots/，
没有就先跑 `python tools/concept_title_ui.py --capture`），绘制工具（字体 / 微型代码 / 平行四边形 / Logo）直接复用 v1。

T1′ 的改动（相对 T1 档案终端）：
  - 标题 keyart 全幅不动（巨树、Logo、水月与博士、封面干员切换都在原位），不再左移、不再切走右侧 1/3；
  - 菜单放在左侧一条深海蓝磨砂竖条上（背景高斯模糊 + 深海蓝 0.74 + 1 px 青色细边），去掉「主界面」白块、警示条、状态行；
  - 菜单行图鉴式：小编号 + 中文 + 宽字距小英文；选中 = 平行四边形高亮。a 版选中用警示黄（黄色只给选中项），b 版选中用白底 + 青色编号块；
  - 内页（难度 / 设置 / 致谢）：左侧面板（标题竖条「长宽」成面板，右边舞台保留巨树和人物），两种底：
      A 深色磨砂（背景模糊 + 深海蓝 0.85，浅色字）；B 先把整屏背景压暗 + 模糊，再盖一块近白面板（0.94，墨色字）。
    难度两种都出，设置用 A、致谢用 B；
  - 手机 740×360：T1′a 标题 + 难度（A）。

用法：
    python tools/concept_title_ui_v2.py

输出（不入库）：主仓库 build/title_redesign/v2/
    contact_sheet_v2.png   总览（先看这张）
    title_T1p_a.png / title_T1p_b.png              桌面标题 T1′a（黄选中）/ T1′b（白 + 青选中）
    diff_T1p_A.png / diff_T1p_B.png                难度 A 深色磨砂 / B 压暗模糊 + 近白面板
    settings_T1p_A.png / credits_T1p_B.png         设置（A）/ 致谢与声明（B）
    title_T1p_a_phone.png / diff_T1p_A_phone.png   手机 740×360
"""
import math, os, sys

from PIL import Image, ImageDraw, ImageFilter

TOOLS = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, TOOLS)
import concept_title_ui as c1  # noqa: E402
from concept_title_ui import (F, W, H, PW, PH, YEL, INK, SUB, MENU, MENU_SUB,  # noqa: E402
                              over, code, para, logo, emblem, dim, keyart, wrap, contact_sheet)

OUT2 = os.path.join(c1.OUT, "v2")


def text(img, xy, s, size, col=INK, anchor="la", bold=False):
    """同 v1，但描边加粗只给 22 号以上（小字号加描边会糊成一团）"""
    return c1.text(img, xy, s, size, col, anchor, bold and size >= 22)

# ---------------------------------------------------------------- 深海色板（概念令牌）
NAVY = (8, 16, 32)            # 磨砂底
NAVY_CARD = (20, 36, 62)      # 深色面板里的行卡
CY = (96, 224, 232)           # 青色强调（细边、编号、刻度）
CY_DIM = (70, 140, 160)
TXT = (228, 236, 244)         # 深底正文
TXT2 = (138, 160, 182)        # 深底次要
TEAL = (18, 124, 146)         # 浅底上的青色强调（B 版）
PAPER = (244, 246, 249)       # B 版近白面板
WHITE_SEL = (238, 247, 250)   # T1′b 选中底

THEMES = {
    "A": dict(txt=TXT, sub=TXT2, acc=CY, line=CY + (46,), card=NAVY_CARD + (235,), card_ol=(52, 92, 122), bar=CY_DIM,
              big=(242, 247, 250), tab_ol=TXT2, btn_ol=TXT, tag=(30, 54, 88), tag_txt=TXT, link=(120, 200, 240)),
    "B": dict(txt=INK, sub=SUB, acc=TEAL, line=(22, 24, 28, 50), card=(255, 255, 255, 255), card_ol=(200, 206, 214), bar=TEAL,
              big=INK, tab_ol=INK, btn_ol=INK, tag=(14, 34, 58), tag_txt=(236, 242, 248), link=(30, 96, 160)),
}


def frost(img, pts, col, a, blur=10):
    """磨砂：多边形区域换成高斯模糊后的背景，再盖一层半透明底色"""
    bl = img.filter(ImageFilter.GaussianBlur(blur))
    m = Image.new("L", img.size, 0)
    ImageDraw.Draw(m).polygon(pts, fill=255)
    img.paste(bl, (0, 0), m)
    over(img, lambda d: d.polygon(pts, fill=col + (a,)))


def soft_shadow(img, x, w, a=70):
    """竖条右侧的柔和投影（让竖条浮在 keyart 上，而不是贴片）"""
    def f(d):
        for i in range(w):
            d.line([(x + i, 0), (x + i, img.height)], fill=(0, 4, 12, int(a * (1 - i / w) ** 2)))
    over(img, f)


# ---------------------------------------------------------------- 标题 T1′
def menu_v2(img, x0, y0, w, step, sel, variant, fs=20, en=8, skew=12, sub=True, items=MENU, idx=10, lx=40):
    """深底竖排菜单：小编号 + 中文 + 宽字距小英文；选中 = 平行四边形（a 黄 / b 白 + 青编号块）"""
    d = ImageDraw.Draw(img)
    h = step - 10
    for i, (cn, e) in enumerate(items):
        y = y0 + i * step + (22 if (sub and i > sel) else 0)
        cy = y + h / 2
        if i == sel:
            over(img, lambda dd: para(dd, (x0 + 4, y + 4, x0 + w + 4, y + h + 4), skew, fill=(0, 0, 0, 90)))
            if variant == "a":
                para(d, (x0, y, x0 + w, y + h), skew, fill=YEL)
                ic, lc, ec = INK, INK, INK
            else:
                para(d, (x0, y, x0 + w, y + h), skew, fill=WHITE_SEL)
                para(d, (x0, y, x0 + 34 + skew, y + h), skew, fill=CY)
                ic, lc, ec = NAVY, NAVY, TEAL
            code(img, (x0 + 10 + skew * 0.6, cy), "%02d" % (i + 1), idx, ic, 1, "lm")
            text(img, (x0 + lx + 8, cy), cn, fs, lc, "lm", bold=True)
            code(img, (x0 + w - skew - 12, cy), e, en, ec, 2, "rm")
        else:
            code(img, (x0 + 10 + skew * 0.6, cy), "%02d" % (i + 1), idx, CY_DIM, 1, "lm")
            text(img, (x0 + lx + 8, cy), cn, fs - 2, TXT, "lm")
            code(img, (x0 + w - skew - 12, cy), e, en - 1, TXT2, 2, "rm")
            over(img, lambda dd: dd.line([(x0 + lx + 8, y + h + 4), (x0 + w - 16, y + h + 4)], fill=CY + (34,), width=1))
    if sub:
        y = y0 + sel * step + h + 6
        text(img, (x0 + lx + 8, y + 7), MENU_SUB[sel], 13, TXT2, "lm")
    return y0 + sel * step, h


def cover_switch(img, x1, y, scale=1.0, label=True):
    """封面干员切换：保持现版的样子与位置（右下，keyart 上，无底板）"""
    s = scale
    if label:
        code(img, (x1, y), "COVER OPERATOR  ·  V", int(8 * s), CY, 3, "rm")
    yy = y + 38 * s
    w = text(img, (x1 - 34 * s, yy), "更换封面干员", int(17 * s), TXT, "rm", bold=True)
    text(img, (x1 - 4 * s, yy), "》", int(17 * s), CY, "rm")
    ix = x1 - 34 * s - w - 22 * s
    d = ImageDraw.Draw(img)
    r = 9 * s
    d.polygon([(ix, yy - r), (ix + r, yy), (ix, yy + r), (ix - r, yy)], outline=TXT, width=2)
    over(img, lambda dd: dd.line([(ix - r, yy + 22 * s), (x1, yy + 22 * s)], fill=TXT2 + (90,), width=1))
    d.line([(ix - r, yy + 22 * s), (ix - r + 26 * s, yy + 22 * s)], fill=CY, width=2)


SW = 420   # 桌面竖条宽


def title_v2(variant="a", sel=0):
    img = keyart()
    pts = [(0, 0), (SW, 0), (SW, H), (0, H)]
    soft_shadow(img, SW, 70)
    frost(img, pts, NAVY, 168, 9)
    # 细边：整条 1 px 青色 40 %，选中行那一段亮起来（灯标光束落点，docs/62 §3.1）
    over(img, lambda d: d.line([(SW, 0), (SW, H)], fill=CY + (110,), width=1))
    emblem(img, (48, 44), 7, (190, 206, 216))
    code(img, (64, 44), "ARKNIGHTS FAN GAME  //  ROGUELIKE", 8, TXT2, 2, "lm")
    img.alpha_composite(logo(0.7), (34, 68))
    code(img, (42, 178), "ARKNIGHTS  SURVIVORS", 11, (214, 226, 234), 5, "lm")
    text(img, (42, 204), "水月与深蓝之树", 14, TXT, "lm")
    code(img, (152, 204), "MIZUKI & CAERULA ARBOR", 8, TXT2, 2, "lm")
    d = ImageDraw.Draw(img)
    over(img, lambda dd: dd.line([(42, 232), (378, 232)], fill=CY + (60,), width=1))
    d.polygon([(378, 228), (382, 232), (378, 236), (374, 232)], fill=CY)
    ys, hh = menu_v2(img, 26, 254, 370, 54, sel, variant)
    d.line([(SW, ys - 4), (SW, ys + hh + 4)], fill=CY, width=3)
    code(img, (42, 640), "W / S  ·  ↑ ↓  SELECT     ENTER  CONFIRM", 8, TXT2, 2, "lm")
    text(img, (42, 670), "明日方舟同人作品 · 非商业 · 致谢与声明 C", 12, TXT2, "lm")
    cover_switch(img, 1232, 618)
    code(img, (W - 48, 694), "v2.0", 9, TXT2, 2, "rm")
    return img


PSW = 262  # 手机竖条宽（740×360 设计坐标）


def title_v2_phone(variant="a", sel=0):
    img = keyart(phone=True)
    soft_shadow(img, PSW, 40)
    frost(img, [(0, 0), (PSW, 0), (PSW, PH), (0, PH)], NAVY, 168, 6)
    over(img, lambda d: d.line([(PSW, 0), (PSW, PH)], fill=CY + (110,), width=1))
    img.alpha_composite(logo(0.42), (16, 14))
    text(img, (20, 86), "水月与深蓝之树", 11, TXT, "lm")
    code(img, (106, 86), "MIZUKI & CAERULA", 6, TXT2, 1, "lm")
    ys, hh = menu_v2(img, 12, 104, 238, 47, sel, variant, fs=17, en=7, skew=9, sub=False, items=MENU[:5], idx=8, lx=26)
    ImageDraw.Draw(img).line([(PSW, ys - 3), (PSW, ys + hh + 3)], fill=CY, width=2)
    cover_switch(img, PW - 14, 270, 0.78, label=False)
    code(img, (PW - 14, 350), "同人作品 · 非商业 · 致谢 C     v2.0", 6, TXT2, 1, "rm")
    return img


# ---------------------------------------------------------------- 内页（左侧面板 = 标题竖条「长宽」）
def stage(theme, phone=False):
    """内页底：A = keyart 压暗到 0.7；B = 整屏先模糊 + 压暗到 0.45（再盖近白面板）"""
    img = keyart(phone=phone)
    if theme == "A":
        return dim(img, 0.7)
    return dim(img.filter(ImageFilter.GaussianBlur(5 if phone else 7)), 0.45)


def panel(img, theme, xt, xb, blur=10):
    pts = [(0, 0), (xt, 0), (xb, img.height), (0, img.height)]
    soft_shadow(img, xb, 50 if img.width > 800 else 30)
    if theme == "A":
        frost(img, pts, NAVY, 217, blur)
        over(img, lambda d: d.line([(xt, 0), (xb, img.height)], fill=CY + (150,), width=1))
    else:
        over(img, lambda d: d.polygon(pts, fill=PAPER + (240,)))
        ImageDraw.Draw(img).line([(xt, 0), (xb, img.height)], fill=TEAL, width=2)


def page_head(img, th, x, y, en_s, cn_s, cn=26, bar_h=40):
    t = THEMES[th]
    ImageDraw.Draw(img).rectangle([x, y, x + 3, y + bar_h], fill=t["acc"])
    code(img, (x + 16, y + bar_h * 0.2), en_s, 8 if cn > 18 else 6, t["sub"], 2, "lm")
    text(img, (x + 16, y + bar_h * 0.68), cn_s, cn, t["txt"], "lm", bold=True)


def tabs(img, th, x, y, names, sel, w, h=34, skew=10, fs=16, gap=8):
    t = THEMES[th]
    d = ImageDraw.Draw(img)
    for i, (cn, e) in enumerate(names):
        bx = x + i * (w + gap)
        on = i == sel
        if on:
            para(d, (bx, y, bx + w, y + h), skew, fill=YEL)
        else:
            para(d, (bx, y, bx + w, y + h), skew, outline=t["tab_ol"], width=1)
        col, sc = (INK, INK) if on else (t["txt"], t["sub"])
        code(img, (bx + skew + 6, y + h * 0.28), "%02d" % (i + 1), 6 if h < 30 else 7, sc, 1, "lm")
        text(img, (bx + skew + (20 if h < 30 else 26), y + h / 2 + 1), cn, fs, col, "lm", bold=on)
        if w > 140:
            code(img, (bx + w - skew - 10, y + h / 2 + 1), e, 7, sc, 2, "rm")
    over(img, lambda dd: dd.line([(x, y + h + 6), (x + len(names) * (w + gap) - gap, y + h + 6)], fill=t["line"], width=1))


def card(img, th, box, sel=False):
    t = THEMES[th]
    x0, y0, x1, y1 = box
    over(img, lambda dd: dd.rectangle(box, fill=t["card"]))
    d = ImageDraw.Draw(img)
    d.rectangle(box, outline=t["card_ol"], width=1)
    d.rectangle([x0, y0, x0 + 3, y1], fill=YEL if sel else t["bar"])


def button_go(img, th, x, y, w, h, label="出发", hint="ENTER  //  PAD A", fs=26):
    d = ImageDraw.Draw(img)
    over(img, lambda dd: para(dd, (x + 4, y + 4, x + w + 4, y + h + 4), 16, fill=(0, 0, 0, 90)))
    para(d, (x, y, x + w, y + h), 16 if h > 40 else 11, fill=YEL)
    text(img, (x + 34, y + h / 2), label, fs, INK, "lm", bold=True)
    if hint:
        code(img, (x + w - 26, y + h / 2), hint, 8, INK, 2, "rm")


def button_back(img, th, x, y, w, h, label="返回  Esc", fs=15):
    t = THEMES[th]
    para(ImageDraw.Draw(img), (x, y, x + w, y + h), 12 if h > 34 else 9, outline=t["btn_ol"], width=1)
    text(img, (x + w / 2, y + h / 2), label, fs, t["txt"], "mm")


EFFS = [("敌人生命", "+20%"), ("敌人造成的伤害", "+20%"), ("Boss 生命", "+15%"), ("受击时灯火损失", "+30%"), ("灯油掉落", "−30%"),
        ("源石锭掉落", "−10%"), ("Boss 预警最多缩短", "15%"), ("大群规模", "+20%"), ("小怪控制提前到", "5:00"), ("寒霜 2 层即冻结", "")]
TIERS = [("标准", "STANDARD"), ("Ⅳ", "TIER IV"), ("Ⅷ", "TIER VIII")]


def tide(img, x0, lvl, gx, marks, scale=1.0, a=60):
    """舞台上的潮位（docs/62 §3.3）：水升到所选档刻度，右缘刻度 + 黄菱形游标"""
    s = scale
    w_ = img.width

    def water(dd):
        pts = [(x0, img.height)] + [(x, lvl + 5 * s * math.sin(x / (34 * s)) + 2 * s * math.sin(x / (12 * s) + 1)) for x in range(int(x0), w_ + 8, 6)] + [(w_, img.height)]
        dd.polygon(pts, fill=(40, 130, 160, a))
        dd.line(pts[1:-1], fill=(150, 236, 240, 150), width=2 if s > 0.8 else 1)
    over(img, water)
    d = ImageDraw.Draw(img)
    top, bot = marks[2][1] - 20 * s, marks[0][1] + 20 * s
    over(img, lambda dd: dd.line([(gx, top), (gx, bot)], fill=(220, 230, 236, 160), width=1))
    for i, (lab, yy) in enumerate(marks):
        on = abs(yy - lvl) < 1
        d.line([(gx - 16 * s, yy), (gx, yy)], fill=(230, 236, 240), width=2 if on else 1)
        text(img, (gx - 22 * s, yy), lab, int(14 * s), YEL if on else (200, 208, 214), "rm")
    r = 7 * s
    d.polygon([(gx + 4 * s, lvl), (gx + 4 * s + r, lvl - r), (gx + 4 * s + 2 * r, lvl), (gx + 4 * s + r, lvl + r)], fill=YEL)


def diff_v2(th="A"):
    t = THEMES[th]
    img = stage(th)
    tide(img, 700, 440, 1236, [("≈", 560), ("Ⅳ", 440), ("Ⅷ", 320)], a=55 if th == "A" else 45)
    xt, xb = 760, 716
    panel(img, th, xt, xb)
    page_head(img, th, 40, 34, "OPERATION  //  DIFFICULTY", "选择难度")
    tabs(img, th, 40, 100, TIERS, 1, 196)
    # 档位摘要：大号罗马数字用强调色（不用黄：黄只给选中 / 主操作）
    text(img, (40, 230), "Ⅳ", 76, t["acc"], "ls", bold=True)
    text(img, (138, 186), "波涛迭起 · Ⅳ", 24, t["txt"], "lm", bold=True)
    code(img, (140, 212), "RISING TIDE IV  //  TIER 02 / 03", 8, t["sub"], 2, "lm")
    text(img, (138, 236), "暗礁更多，灯火更难守住。", 15, t["sub"], "lm")
    for i, (a, b) in enumerate(EFFS):
        col, row = i // 5, i % 5
        bx, by = 40 + col * 322, 268 + row * 56
        card(img, th, (bx, by, bx + 306, by + 48))
        code(img, (bx + 14, by + 12), "MOD %02d" % (i + 1), 6, t["sub"], 2, "lm")
        text(img, (bx + 14, by + 32), a, 15, t["txt"], "lm")
        if b:
            text(img, (bx + 294, by + 26), b, 22, t["big"], "rm", bold=True)
    button_go(img, th, 40, 576, 300, 56)
    button_back(img, th, 360, 584, 150, 40)
    code(img, (40, 688), "← →  CHANGE TIER      ENTER  DEPLOY      ESC  BACK", 8, t["sub"], 2, "lm")
    return img


def diff_v2_phone(th="A"):
    t = THEMES[th]
    img = stage(th, phone=True)
    tide(img, 430, 210, 718, [("≈", 280), ("Ⅳ", 210), ("Ⅷ", 140)], scale=0.7)
    xt, xb = 470, 446
    panel(img, th, xt, xb, 6)
    page_head(img, th, 16, 12, "OPERATION  //  DIFFICULTY", "选择难度", cn=17, bar_h=30)
    tabs(img, th, 16, 50, TIERS, 1, 128, h=28, skew=8, fs=14, gap=6)
    text(img, (16, 122), "Ⅳ", 36, t["acc"], "ls", bold=True)
    text(img, (62, 101), "波涛迭起 · Ⅳ", 15, t["txt"], "lm", bold=True)
    text(img, (170, 101), "暗礁更多，灯火更难守住。", 11, t["sub"], "lm")
    for i, (a, b) in enumerate(EFFS):
        col, row = i // 5, i % 5
        bx, by = 16 + col * 210, 132 + row * 34
        card(img, th, (bx, by, bx + 200, by + 30))
        text(img, (bx + 10, by + 15), a, 12, t["txt"], "lm")
        if b:
            text(img, (bx + 192, by + 15), b, 15, t["big"], "rm", bold=True)
    button_go(img, th, 16, 308, 190, 42, hint="", fs=19)
    button_back(img, th, 222, 312, 110, 34, label="返回", fs=13)
    return img


def settings_v2(th="A"):
    t = THEMES[th]
    img = stage(th)
    xt, xb = 820, 776
    panel(img, th, xt, xb)
    page_head(img, th, 40, 34, "SYSTEM  //  SETTINGS", "设置")
    tabs(img, th, 40, 100, [("声音", "SOUND"), ("画面", "DISPLAY"), ("游戏", "GAMEPLAY")], 0, 196)
    for k, s in enumerate("QE"):
        x = 660 + k * 30
        ImageDraw.Draw(img).rectangle([x, 106, x + 22, 128], outline=t["sub"], width=1)
        text(img, (x + 11, 117), s, 11, t["sub"], "mm")
    rows = [("主音量", "MASTER", 8), ("音乐", "MUSIC", 6), ("音效", "SFX", 9), ("语音", "VOICE", 7)]
    d = ImageDraw.Draw(img)
    x1 = 740
    for i, (cn, e, v) in enumerate(rows):
        y = 172 + i * 72
        sel = i == 0
        card(img, th, (40, y, x1, y + 60), sel=sel)
        if sel:
            over(img, lambda dd: dd.rectangle([44, y + 1, x1 - 1, y + 59], fill=(70, 110, 160, 70)))
        text(img, (64, y + 30), cn, 19, t["txt"], "lm", bold=sel)
        code(img, (150, y + 30), e, 7, t["sub"], 2, "lm")
        sx = 300
        text(img, (sx - 18, y + 30), "◀", 13, t["txt"], "mm")
        for k in range(10):
            on = k < v
            fill = (YEL if sel else t["acc"]) if on else None
            para(d, (sx + k * 30, y + 19, sx + k * 30 + 24, y + 41), 5, fill=fill, outline=t["card_ol"] if not on else fill)
        text(img, (sx + 312, y + 30), "▶", 13, t["txt"], "mm")
        text(img, (x1 - 20, y + 31), str(v * 10), 24, t["big"], "rm", bold=True)
    over(img, lambda dd: dd.line([(40, 610), (x1, 610)], fill=t["line"], width=1))
    button_back(img, th, 40, 630, 170, 42, fs=16)
    code(img, (236, 651), "Q / E  PAGE    ↑ ↓  SELECT    ← →  ADJUST", 8, t["sub"], 2, "lm")
    return img


def credits_v2(th="B"):
    t = THEMES[th]
    img = stage(th)
    xt, xb = 900, 856
    panel(img, th, xt, xb)
    page_head(img, th, 40, 34, "ARCHIVE  //  CREDITS & DISCLAIMER", "致谢与声明")
    rows = [("同人声明", "《方舟幸存者》是《明日方舟》的非官方同人作品，免费、非商业。角色、世界观、名称与「水月与深蓝之树」的设定均属于鹰角网络（Hypergryph），本作与鹰角网络无关。", ""),
            ("明日方舟游戏数据", "藏品名称、编号与敌人设定的核对参考自社区整理的游戏数据仓库。", "https://github.com/Kengxxiao/ArknightsGameData"),
            ("PRTS Wiki", "机制与文案参考。", "https://prts.wiki"),
            ("像素美术", "角色、敌人、场景与特效为根据《明日方舟》游戏美术二次创作的像素画，由 Claude（Anthropic）与 ChatGPT / Codex（OpenAI）程序化绘制。", ""),
            ("引擎", "Godot Engine 4.7（MIT 许可）。", "https://godotengine.org")]
    d = ImageDraw.Draw(img)
    x0, bx = 40, 220
    tw = 770 - bx
    y = 104
    for i, (lab, body, link) in enumerate(rows):
        para(d, (x0, y, x0 + 170, y + 28), 8, fill=t["tag"])
        code(img, (x0 + 14, y + 14), "%02d" % (i + 1), 7, CY, 1, "lm")
        text(img, (x0 + 34, y + 14), lab, 13, t["tag_txt"], "lm")
        lines = wrap(body, 17, tw)
        for k, ln in enumerate(lines):
            text(img, (bx, y + 2 + k * 27), ln, 17, t["txt"])
        yy = y + 2 + len(lines) * 27
        if link:
            text(img, (bx, yy + 2), link, 14, t["link"])
            yy += 24
        y = yy + 16
    over(img, lambda dd: dd.rectangle([808, 104, 812, 596], fill=t["line"]))
    d.rectangle([808, 104, 812, 270], fill=t["acc"])
    over(img, lambda dd: dd.line([(x0, 610), (800, 610)], fill=t["line"], width=1))
    text(img, (x0, 636), "如有侵权请通过小红书 菜月colafax（373145407）联系作者，将立即处理。", 14, t["sub"], "lm")
    code(img, (x0, 664), "WHEEL / ↑ ↓ / PGUP PGDN  SCROLL", 8, t["sub"], 2, "lm")
    button_back(img, th, 630, 626, 170, 42, fs=16)
    return img


# ---------------------------------------------------------------- 总览
def main():
    os.makedirs(OUT2, exist_ok=True)
    cur = Image.open(os.path.join(c1.OUT, "current_title.png")).convert("RGBA")
    old_t1 = Image.open(os.path.join(c1.OUT, "title_T1_split.png")).convert("RGBA")
    old_diff = Image.open(os.path.join(c1.OUT, "diff_C4.png")).convert("RGBA")
    old_phone = Image.open(os.path.join(c1.OUT, "title_T1_phone.png")).convert("RGBA")
    outs = {
        "title_T1p_a": title_v2("a"),
        "title_T1p_b": title_v2("b"),
        "diff_T1p_A": diff_v2("A"),
        "diff_T1p_B": diff_v2("B"),
        "settings_T1p_A": settings_v2("A"),
        "credits_T1p_B": credits_v2("B"),
        "title_T1p_a_phone": title_v2_phone("a"),
        "diff_T1p_A_phone": diff_v2_phone("A"),
    }
    for k, im in outs.items():
        p = os.path.join(OUT2, k + ".png")
        im.convert("RGB").save(p)
        print("写出", p)
    contact_sheet([
        ("标题", [("现状（方案 A 时间轴菜单）", cur), ("旧 T1：keyart 左移 + 右侧灰面板", old_t1),
                ("T1'a：全幅 keyart + 左侧深海磨砂竖条，选中黄（推荐）", outs["title_T1p_a"]), ("T1'b：同上，选中白底 + 青编号", outs["title_T1p_b"])]),
        ("难度", [("旧 C4（灰面板透出人物）", old_diff), ("A 深色磨砂面板（推荐）", outs["diff_T1p_A"]),
                ("B 背景压暗模糊 + 近白面板", outs["diff_T1p_B"]), ("A 手机 740×360", outs["diff_T1p_A_phone"])]),
        ("内页 / 手机", [("设置：A 深色磨砂（局内暂停可共用）", outs["settings_T1p_A"]), ("致谢与声明：B 近白面板（长文阅读）", outs["credits_T1p_B"]),
                     ("旧 T1 手机", old_phone), ("T1'a 手机 740×360", outs["title_T1p_a_phone"])]),
    ], "T1' 修订：全幅 keyart + 深海磨砂竖条（docs/67 §9）", os.path.join(OUT2, "contact_sheet_v2.png"))


if __name__ == "__main__":
    main()
