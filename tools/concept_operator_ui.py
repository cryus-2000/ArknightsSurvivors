# -*- coding: utf-8 -*-
"""干员选择 / 干员图鉴 概念图（docs/58，2026-10-11）：参考《明日方舟》干员界面的版式，用本项目像素资产画 PNG。
只用 art/incoming 的 op_*_idle(@2x) / player_idle(@2x)、skill_*、growth_*、_trial_icons/relic_* 与 game/fonts；不用原作任何图片。
不是游戏代码，只是给用户看的概念图。

用法：
  python tools/concept_operator_ui.py [输出目录]            缺省 build/concept/operator_ui：A 版三张（带编号标注）
  python tools/concept_operator_ui.py --variant=B [输出目录]  只出某一美术方向（A / B / C / D / E），不带标注
  python tools/concept_operator_ui.py --variant=all [输出目录] 缺省 build/concept/operator_ui/variants：全部方向 + 对比总览 contact_sheet.png
美术方向（docs/58 §7）：
  A 现版（暗面板 + 单切角 + 青色出击）   B 水月 / 集成战略（docs/37 语汇：无切角、紫金细饰线、深海渐变 + 触须浪纹、圆角标签）
  C 罗德岛终端（浅灰白面板黑字、黑细线、斜向色带、黄黑警示条、英文微型标签）
  D 极简像素（640×360 画布 ×2、≤16 色界面调色板、粗像素九宫格边框、点阵标题、名册两行网格）
  E 深海档案（仅图鉴：纸本病历卡 + 拍立得照片 + 衬线字 + 红印章）
"""
import os, sys, json, glob, math, random
from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageChops
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import promo_keyart as K
from promo_roster import font_for

ROOT = K.ROOT
ART = K.ART
CHAR_DIR = os.path.join(ROOT, "game", "data", "characters")
FONT_SERIF = os.path.join(ROOT, "game", "fonts", "serif.ttf")

# ui.gd 语义色（docs/37 §2；PURPLE 不改）
CYAN = (54, 226, 220)
CYAN_DIM = (92, 158, 163)
GOLD = (244, 192, 78)
RED = (255, 61, 139)
PURPLE = (168, 133, 255)
VIOLET = (124, 107, 255)
GREEN = (47, 211, 160)
STEEL = (126, 152, 184)
TAB_HP = (23, 143, 166)
TAB_LAMP = (184, 135, 10)
YEL = (255, 206, 0)       # C 罗德岛终端的警示黄
CLASS_COL = {"先锋": (255, 199, 89), "近卫": (140, 191, 255), "重装": (255, 184, 97), "狙击": (255, 107, 97),
             "术师": (255, 128, 56), "医疗": (140, 255, 153), "辅助": (255, 217, 128), "特种": (191, 153, 255)}
CLASS_ORDER = ["先锋", "近卫", "重装", "狙击", "术师", "医疗", "辅助", "特种"]
CLASS_GLYPH = {"先锋": "flag", "近卫": "blade", "重装": "shield", "狙击": "cross", "术师": "orb", "医疗": "plus", "辅助": "wave", "特种": "diamond"}

# ---------- 美术方向（主题） ----------
THEMES = {
    "A": dict(text=(242, 244, 245), sub=(154, 163, 173), ink=(10, 12, 16), line=(255, 255, 255, 41),
              fill=(6, 10, 16, 215), fill_sel=(8, 24, 30, 235), card=(6, 10, 16, 215), strip=(0, 0, 0, 170), strip_text=(242, 244, 245),
              track=(255, 255, 255, 30), glyph=(200, 205, 210), head_font=None, desc="现版：暗面板 + 单切角 + 青色出击"),
    "B": dict(text=(242, 244, 245), sub=(160, 168, 190), ink=(10, 12, 16), line=(168, 133, 255, 80),
              fill=(10, 16, 28, 205), fill_sel=(22, 26, 52, 230), card=(10, 20, 30, 220), strip=(4, 8, 16, 190), strip_text=(242, 244, 245),
              track=(255, 255, 255, 30), glyph=(200, 205, 225), head_font=None, desc="水月 / 集成战略：无切角、紫金饰线、深海渐变"),
    "C": dict(text=(22, 24, 28), sub=(92, 96, 104), ink=(22, 24, 28), line=(22, 24, 28, 200),
              fill=(250, 250, 250, 235), fill_sel=(255, 247, 206, 245), card=(238, 240, 242, 255), strip=(22, 24, 28, 255), strip_text=(250, 250, 250),
              track=(0, 0, 0, 40), glyph=(22, 24, 28), head_font=None, desc="罗德岛终端：浅色面板黑字、斜向色带、黄黑警示条"),
    "D": dict(desc="极简像素：≤16 色、粗像素九宫格边框、点阵标题、两行网格名册"),
    "E": dict(text=(56, 42, 30), sub=(122, 102, 80), ink=(56, 42, 30), line=(110, 88, 64, 200),
              fill=(247, 240, 224, 250), fill_sel=(252, 246, 230, 255), card=(244, 236, 218, 255), strip=(86, 66, 48, 235), strip_text=(247, 240, 224),
              track=(110, 88, 64, 50), glyph=(86, 66, 48), head_font=FONT_SERIF, desc="深海档案：纸本病历卡 + 拍立得 + 红印章（图鉴）"),
}
V = "A"
T = THEMES["A"]
CALLOUTS = True


def set_theme(v):
    global V, T
    V = v
    T = THEMES[v]


try:
    from fontTools.ttLib import TTFont
    _SERIF_CMAP = TTFont(FONT_SERIF).getBestCmap()
except Exception:
    _SERIF_CMAP = {}


def serif(size, s=""):
    """衬线字缺字（娅、鲨…）时整词退回 UI 字体"""
    if all(ord(ch) in _SERIF_CMAP for ch in s if not ch.isspace()):
        return ImageFont.truetype(FONT_SERIF, size)
    return font_for(s, size)


def F(size, s="汉", head=False):
    if head and T.get("head_font") and all(ord(ch) in _SERIF_CMAP for ch in (s or "") if not ch.isspace()):
        return ImageFont.truetype(T["head_font"], size)
    return font_for(s or "汉", size)


def roster():
    out = []
    for f in sorted(glob.glob(os.path.join(CHAR_DIR, "*.json"))):
        cid = os.path.basename(f)[:-5]
        d = json.load(open(f, encoding="utf-8"))
        tex = "player_idle@2x" if cid == "mizuki" else "op_%s_idle@2x" % cid
        if not os.path.exists(os.path.join(ART, tex + ".png")):
            continue
        d["_tex"] = tex
        d["_id"] = cid
        out.append(d)
    # 原作按稀有度排；本作没有稀有度，按职业顺序 + 水月（封面干员）优先
    out.sort(key=lambda d: (0 if d["_id"] == "mizuki" else 1, CLASS_ORDER.index(d.get("class")) if d.get("class") in CLASS_ORDER else 9))
    return out


def frame(tex, i=0):
    return K.frame(tex, 4, i, trim=True)


def icon(name):
    p = os.path.join(ART, name + ".png")
    if not os.path.exists(p):
        p = os.path.join(ART, "_trial_icons", name + ".png")
    return Image.open(p).convert("RGBA") if os.path.exists(p) else None


def layer(img):
    return Image.new("RGBA", img.size, (0, 0, 0, 0))


def wrap(s, size, width):
    f = F(size, s)
    out, cur = [], ""
    for ch in s:
        if f.getlength(cur + ch) > width:
            out.append(cur)
            cur = ch
        else:
            cur += ch
    out.append(cur)
    return out


# ---------- 基本笔触 ----------
def cut_poly(x0, y0, x1, y1, cut=10, corners="tr"):
    pts = [(x0 + cut, y0) if "tl" in corners else (x0, y0), (x1 - cut, y0) if "tr" in corners else (x1, y0)]
    if "tr" in corners:
        pts.append((x1, y0 + cut))
    pts.append((x1, y1 - cut) if "br" in corners else (x1, y1))
    if "br" in corners:
        pts.append((x1 - cut, y1))
    pts.append((x0 + cut, y1) if "bl" in corners else (x0, y1))
    if "bl" in corners:
        pts.append((x0, y1 - cut))
    if "tl" in corners:
        pts.append((x0, y0 + cut))
    return pts


def diamond(d, c, r, col):
    x, y = c
    d.polygon([(x, y - r), (x + r, y), (x, y + r), (x - r, y)], fill=col)


def hazard(img, box, a=YEL, b=(22, 24, 28), step=10):
    """黄黑警示斜条"""
    x0, y0, x1, y1 = [int(v) for v in box]
    tile = Image.new("RGBA", (x1 - x0, y1 - y0), a + (255,))
    d = ImageDraw.Draw(tile)
    h = y1 - y0
    for x in range(-h, x1 - x0 + h, step * 2):
        d.polygon([(x, h), (x + step, h), (x + step + h, 0), (x + h, 0)], fill=b + (255,))
    img.alpha_composite(tile, (x0, y0))


def panel(img, box, sel=False, accent=None, cut=10, corners="tr", fill=None, shadow=True):
    """面板：按美术方向换画法"""
    x0, y0, x1, y1 = [int(v) for v in box]
    fill = fill or (T["fill_sel"] if sel else T["fill"])
    ov = layer(img)
    d = ImageDraw.Draw(ov)
    if V == "A":
        pts = cut_poly(x0, y0, x1, y1, cut, corners)
        d.polygon(pts, fill=fill)
        d.line([pts[0], pts[1]], fill=(255, 255, 255, 36))
        d.polygon(pts, outline=(accent + (255,)) if (sel and accent) else T["line"])
        img.alpha_composite(ov)
        if accent:
            dd = ImageDraw.Draw(img)
            L = min(28, (x1 - x0) // 4)
            dd.line([(x0, y0), (x0 + L, y0)], fill=accent, width=2)
            dd.line([(x0, y0), (x0, y0 + L)], fill=accent, width=2)
    elif V == "B":
        d.rounded_rectangle([x0, y0, x1, y1], 4, fill=fill, outline=(accent + (230,)) if (sel and accent) else T["line"])
        if x1 - x0 > 60 and y1 - y0 > 40:
            d.rounded_rectangle([x0 + 3, y0 + 3, x1 - 3, y1 - 3], 3, outline=(255, 255, 255, 16))
        d.line([(x0 + 6, y0 + 1), (x1 - 6, y0 + 1)], fill=(255, 255, 255, 30))
        img.alpha_composite(ov)
        if accent or sel:
            dd = ImageDraw.Draw(img)
            diamond(dd, (x0 + 1, y0 + 1), 4, GOLD)
            diamond(dd, (x1 - 1, y0 + 1), 4, GOLD)
            if x1 - x0 > 120:
                dd.line([(x0 + 10, y0), (x0 + 40, y0)], fill=GOLD, width=1)
                dd.line([(x1 - 40, y0), (x1 - 10, y0)], fill=GOLD, width=1)
    elif V == "C":
        if shadow:
            d.rectangle([x0 + 3, y0 + 3, x1 + 3, y1 + 3], fill=(0, 0, 0, 40))
        d.rectangle([x0, y0, x1, y1], fill=fill, outline=(22, 24, 28, 255), width=2 if sel else 1)
        img.alpha_composite(ov)
        if sel:
            ImageDraw.Draw(img).rectangle([x0, y0, x0 + 4, y1], fill=YEL)
        elif accent:
            ImageDraw.Draw(img).rectangle([x0, y0, x0 + 24, y0 + 3], fill=(22, 24, 28))
    elif V == "E":
        if shadow:
            d.rectangle([x0 + 3, y0 + 4, x1 + 3, y1 + 4], fill=(40, 28, 16, 60))
        d.rectangle([x0, y0, x1, y1], fill=fill, outline=T["line"])
        if y1 - y0 > 60:
            for yy in range(y0 + 26, y1 - 6, 18):
                d.line([(x0 + 8, yy), (x1 - 8, yy)], fill=(120, 150, 170, 26))
        img.alpha_composite(ov)
        if sel:
            ImageDraw.Draw(img).rectangle([x0, y0, x1, y1], outline=(178, 40, 40), width=2)


def text(img, xy, s, size, col=None, anchor="la", bold=False, head=False):
    d = ImageDraw.Draw(img)
    col = T["text"] if col is None else col
    f = F(size, s, head)
    d.text(xy, s, font=f, fill=col, anchor=anchor, stroke_width=1 if (bold and size >= 18) else 0, stroke_fill=col)
    return d.textlength(s, font=f)


def en(img, xy, s, size, col=None, spacing=2, anchor="la", italic=True):
    """压缩斜体英文（UI.en）"""
    col = T["sub"] if col is None else col
    f = ImageFont.truetype(K.FONT_UI, size)
    w = sum(f.getlength(ch) + spacing for ch in s)
    tmp = Image.new("RGBA", (int(w) + 8, size + 8), (0, 0, 0, 0))
    d = ImageDraw.Draw(tmp)
    x = 2
    for ch in s:
        d.text((x, 2), ch, font=f, fill=col)
        x += f.getlength(ch) + spacing
    tmp = tmp.resize((max(1, int(tmp.width * 0.84)), tmp.height), Image.LANCZOS)
    if italic:
        tmp = tmp.transform(tmp.size, Image.AFFINE, (1, 0.18, -0.18 * tmp.height / 2, 0, 1, 0), Image.BILINEAR)
    ax, ay = xy
    if anchor == "ra":
        ax -= tmp.width
    elif anchor == "ma":
        ax -= tmp.width // 2
    img.alpha_composite(tmp, (int(ax), int(ay) - 2))
    return tmp.width


def micro(img, xy, s):
    """英文微型标签（C 罗德岛终端 / E 档案才画）"""
    if V in ("C", "E"):
        en(img, xy, s, 8, T["sub"], 2, italic=False)


def chip(img, xy, s, col, size=11, solid=False):
    """标签片"""
    d = ImageDraw.Draw(img)
    f = F(size, s)
    w = d.textlength(s, font=f) + 14
    x, y = xy
    h = size + 8
    ov = layer(img)
    od = ImageDraw.Draw(ov)
    if V == "A":
        od.rectangle([x, y, x + w, y + h], fill=col + (255,) if solid else (0, 0, 0, 150))
        img.alpha_composite(ov)
        d.rectangle([x, y, x + 2, y + h], fill=col)
        d.text((x + 8, y + 4), s, font=f, fill=(10, 12, 16) if solid else T["text"])
    elif V == "B":
        w += 4
        od.rounded_rectangle([x, y, x + w, y + h], h // 2, fill=col + (255,) if solid else (0, 0, 0, 130), outline=col + (220,))
        img.alpha_composite(ov)
        d.text((x + w / 2, y + h / 2), s, font=f, fill=(10, 12, 16) if solid else T["text"], anchor="mm")
    elif V == "C":
        if solid:
            od.rectangle([x, y, x + w, y + h], fill=(22, 24, 28, 255))
        else:
            od.rectangle([x, y, x + w, y + h], fill=(255, 255, 255, 230), outline=(22, 24, 28, 255))
        img.alpha_composite(ov)
        if solid:
            d.rectangle([x, y + h - 3, x + w, y + h], fill=col)
        d.text((x + 7, y + 4), s, font=f, fill=(250, 250, 250) if solid else (22, 24, 28))
    elif V == "E":
        od.rectangle([x, y, x + w, y + h], outline=(178, 40, 40, 220) if solid else T["line"], width=1)
        img.alpha_composite(ov)
        d.text((x + 7, y + 4), s, font=f, fill=(178, 40, 40) if solid else T["text"])
    return w + 6


def tab_head(img, xy, s, col, size=10):
    """小标签头（数值上方的彩色底白字）"""
    d = ImageDraw.Draw(img)
    f = F(size, s)
    w = d.textlength(s, font=f) + 10
    x, y = xy
    if V == "C":
        col = (22, 24, 28)
    elif V == "E":
        col = (110, 88, 64)
    if V == "B":
        d.rounded_rectangle([x, y, x + w, y + size + 5], 3, fill=col)
    else:
        d.rectangle([x, y, x + w, y + size + 5], fill=col)
    d.text((x + 5, y + 2), s, font=f, fill=(255, 255, 255) if V != "E" else (247, 240, 224))
    return w


def glyph(img, c, r, kind, col, width=2):
    """职业线性图标（几何示意）"""
    d = ImageDraw.Draw(img)
    x, y = c
    if kind == "blade":
        d.line([(x - r, y + r), (x + r, y - r)], fill=col, width=width)
        d.line([(x - r * 0.3, y + r), (x + r, y + r * 0.3)], fill=col, width=width)
    elif kind == "shield":
        d.polygon([(x - r, y - r), (x + r, y - r), (x + r, y + r * 0.2), (x, y + r), (x - r, y + r * 0.2)], outline=col, width=width)
    elif kind == "cross":
        d.ellipse([x - r, y - r, x + r, y + r], outline=col, width=width)
        d.line([(x - r, y), (x + r, y)], fill=col, width=width)
        d.line([(x, y - r), (x, y + r)], fill=col, width=width)
    elif kind == "orb":
        d.ellipse([x - r * 0.7, y - r * 0.7, x + r * 0.7, y + r * 0.7], outline=col, width=width)
        d.polygon([(x, y - r), (x + r, y + r * 0.8), (x - r, y + r * 0.8)], outline=col, width=1)
    elif kind == "plus":
        d.rectangle([x - r * 0.3, y - r, x + r * 0.3, y + r], fill=col)
        d.rectangle([x - r, y - r * 0.3, x + r, y + r * 0.3], fill=col)
    elif kind == "wave":
        d.line([(x - r + i * r / 4.0, y + (r * 0.5 if i % 2 else -r * 0.5)) for i in range(9)], fill=col, width=width)
    elif kind == "diamond":
        d.polygon([(x, y - r), (x + r, y), (x, y + r), (x - r, y)], outline=col, width=width)
    elif kind == "flag":
        d.line([(x - r * 0.7, y - r), (x - r * 0.7, y + r)], fill=col, width=width)
        d.polygon([(x - r * 0.7, y - r), (x + r, y - r * 0.5), (x - r * 0.7, y)], fill=col)


def star_row(img, xy, n, col=GOLD, size=7, gap=3):
    """精英阶段菱形（代替原作稀有度星）"""
    d = ImageDraw.Draw(img)
    x, y = xy
    for i in range(n):
        diamond(d, (x + i * (size + gap) + size / 2, y + size / 2), size / 2, col)


def ring(img, c, r, frac, col, width=3):
    d = ImageDraw.Draw(img)
    x, y = c
    d.arc([x - r, y - r, x + r, y + r], 0, 360, fill=T["track"], width=width)
    d.arc([x - r, y - r, x + r, y + r], -90, -90 + 360 * frac, fill=col, width=width)


def callout(img, xy, n, col=GOLD):
    """编号标注（只在概念图 A 上）"""
    if not CALLOUTS:
        return
    d = ImageDraw.Draw(img)
    x, y = xy
    d.ellipse([x - 12, y - 12, x + 12, y + 12], fill=(0, 0, 0, 255))
    d.ellipse([x - 11, y - 11, x + 11, y + 11], fill=col)
    d.text((x, y + 1), str(n), font=ImageFont.truetype(K.FONT_UI, 14), fill=(20, 16, 8), anchor="mm")


def tab_bar(img, box, names, on, col, size=14):
    """信息面板页签"""
    x0, y0, x1, y1 = box
    d = ImageDraw.Draw(img)
    tw = (x1 - x0) / len(names)
    for i, nm in enumerate(names):
        a = i == on
        tx0 = x0 + i * tw
        cx = tx0 + tw / 2
        cy = (y0 + y1) / 2
        if V == "A":
            if a:
                d.polygon([(tx0, y0), (tx0 + tw, y0), (tx0 + tw, y1), (tx0 + 8, y1), (tx0, y1 - 8)], fill=col)
            text(img, (cx, cy), nm, size, T["ink"] if a else T["sub"], anchor="mm")
        elif V == "B":
            if a:
                ov = layer(img)
                ImageDraw.Draw(ov).rectangle([tx0 + 2, y0 + 2, tx0 + tw - 2, y1], fill=VIOLET + (60,))
                img.alpha_composite(ov)
                d.line([(tx0 + 10, y1 - 1), (tx0 + tw - 10, y1 - 1)], fill=VIOLET, width=2)
                diamond(d, (cx, y1 - 1), 3, GOLD)
            text(img, (cx, cy), nm, size, T["text"] if a else T["sub"], anchor="mm")
        elif V == "C":
            if a:
                d.rectangle([tx0, y0, tx0 + tw, y1], fill=(22, 24, 28))
            en(img, (tx0 + 6, y0 + 3), "%02d" % (i + 1), 7, YEL if a else T["sub"], 1, italic=False)
            text(img, (cx, cy + 2), nm, size, (250, 250, 250) if a else T["text"], anchor="mm")
        elif V == "E":
            fill = (247, 240, 224) if a else (222, 210, 186)
            d.polygon([(tx0 + 2, y1), (tx0 + 8, y0 + (0 if a else 4)), (tx0 + tw - 8, y0 + (0 if a else 4)), (tx0 + tw - 2, y1)], fill=fill, outline=(110, 88, 64))
            text(img, (cx, cy + 1), nm, size, T["text"] if a else T["sub"], anchor="mm", head=True)
    if V == "C":
        d.line([(x0, y1), (x1, y1)], fill=(22, 24, 28), width=2)
    elif V != "E":
        d.line([(x0, y1), (x1, y1)], fill=T["line"])


def big_button(img, box, s, sub=None, size=22):
    """右下主按钮（原作「开始行动」）"""
    x0, y0, x1, y1 = box
    d = ImageDraw.Draw(img)
    ink = (8, 20, 24)
    cy = (y0 + y1) / 2 - (7 if sub else 0)
    if V == "A":
        d.polygon(cut_poly(x0, y0, x1, y1, 14, "tl br"), fill=CYAN)
        d.polygon(cut_poly(x0 + 3, y0 + 3, x1 - 3, y1 - 3, 12, "tl br"), outline=(255, 255, 255, 110))
    elif V == "B":
        d.rounded_rectangle([x0 - 4, y0 - 4, x1 + 4, y1 + 4], 9, outline=GOLD, width=1)
        d.rounded_rectangle([x0, y0, x1, y1], 6, fill=CYAN)
        diamond(d, (x0 - 4, (y0 + y1) / 2), 5, GOLD)
        diamond(d, (x1 + 4, (y0 + y1) / 2), 5, GOLD)
    elif V == "C":
        d.rectangle([x0 + 4, y0 + 4, x1 + 4, y1 + 4], fill=(0, 0, 0, 255))
        d.rectangle([x0, y0, x1, y1], fill=YEL, outline=(22, 24, 28), width=2)
        hazard(img, (x0 + 2, y0 + 2, x0 + 34, y1 - 1))
        ink = (22, 24, 28)
        en(img, (x1 - 8, y0 + 4), "START OPERATION", 8, ink, 2, anchor="ra", italic=False)
        cy += 4
    mid = (x0 + x1) / 2 + (14 if V == "C" else 0)
    d.text((mid, cy), s, font=F(size, s), fill=ink, anchor="mm", stroke_width=1, stroke_fill=ink)
    if sub:
        d.text((mid, cy + 22), sub, font=F(10, sub), fill=ink, anchor="mm")


def small_btn(img, box, s):
    x0, y0, x1, y1 = box
    panel(img, box, cut=6, shadow=False)
    text(img, ((x0 + x1) / 2, (y0 + y1) / 2), s, 12, anchor="mm")


# ---------- 背景 ----------
def backdrop(W, H, accent, op=None):
    img = Image.new("RGBA", (W, H))
    d = ImageDraw.Draw(img)
    if V == "A":
        top, bot = (6, 9, 16), (12, 20, 32)
        for y in range(H):
            t = y / (H - 1)
            d.line([(0, y), (W, y)], fill=tuple(int(top[i] + (bot[i] - top[i]) * t) for i in range(3)) + (255,))
        img.alpha_composite(K.radial((W, H), (int(W * 0.68), int(H * 0.5)), int(H * 0.75), accent, 40))
        ov = layer(img)
        od = ImageDraw.Draw(ov)
        for x in range(-H, W, 28):
            od.line([(x, H), (x + H, 0)], fill=(255, 255, 255, 6), width=1)
        img.alpha_composite(ov)
    elif V == "B":
        # 深海青 → 深紫的斜向渐变 + 下方浪纹 + 两侧触须剪影 + 灯火暖光点
        c0, c1 = (6, 30, 40), (30, 14, 52)
        base = Image.new("RGBA", (W, H))
        px = base.load()
        for y in range(0, H, 2):
            for x in range(0, W, 2):
                t = min(1.0, max(0.0, (x / W) * 0.55 + (1 - y / H) * 0.45))
                c = tuple(int(c0[i] + (c1[i] - c0[i]) * t) for i in range(3)) + (255,)
                px[x, y] = c
                px[x + 1, y] = c
                px[x, y + 1] = c
                px[x + 1, y + 1] = c
        img = base
        img.alpha_composite(K.radial((W, H), (int(W * 0.62), int(H * 0.45)), int(H * 0.7), (90, 200, 220), 45))
        ov = layer(img)
        od = ImageDraw.Draw(ov)
        for k in range(9):
            yb = int(H * 0.55 + k * 26)
            od.line([(x, yb + 6 * math.sin(x / 70.0 + k * 1.3)) for x in range(0, W + 10, 10)], fill=(140, 230, 240, 14 + k), width=1)
        rnd = random.Random(3)
        for side, n in ((0, 4), (1, 4)):
            for i in range(n):
                x = (rnd.randint(-40, 160) if side == 0 else W - rnd.randint(-40, 160))
                y = H + 20
                ang = -math.pi / 2 + (0.35 if side == 0 else -0.35) + rnd.uniform(-0.3, 0.3)
                wdt = rnd.uniform(14, 22)
                L = rnd.randint(260, 460)
                ph = rnd.uniform(0, 6)
                prev = (x, y)
                for s in range(0, L, 6):
                    a = ang + 0.5 * math.sin(s / 60.0 + ph) * (s / L)
                    nx, ny = prev[0] + 6 * math.cos(a), prev[1] + 6 * math.sin(a)
                    od.line([prev, (nx, ny)], fill=(120, 80, 200, 26), width=max(1, int(wdt * (1 - s / L))))
                    prev = (nx, ny)
        ov = ov.filter(ImageFilter.GaussianBlur(1.2))
        img.alpha_composite(ov)
        ov = layer(img)
        od = ImageDraw.Draw(ov)
        for i in range(60):
            x, y = rnd.randint(0, W), rnd.randint(0, H)
            r = rnd.choice([1, 1, 2])
            od.ellipse([x - r, y - r, x + r, y + r], fill=(255, 220, 150, rnd.randint(30, 90)))
        img.alpha_composite(ov)
    elif V == "C":
        d.rectangle([0, 0, W, H], fill=(226, 228, 231, 255))
        ov = layer(img)
        od = ImageDraw.Draw(ov)
        for x in range(0, W, 32):
            od.line([(x, 0), (x, H)], fill=(0, 0, 0, 10))
        for y in range(0, H, 32):
            od.line([(0, y), (W, y)], fill=(0, 0, 0, 10))
        # 斜向色带（职业色）+ 一道黑细带
        od.polygon([(560, H), (800, H), (1010, 0), (770, 0)], fill=accent + (210,))
        od.polygon([(818, H), (836, H), (1046, 0), (1028, 0)], fill=(22, 24, 28, 230))
        od.polygon([(470, H), (490, H), (700, 0), (680, 0)], fill=(22, 24, 28, 40))
        img.alpha_composite(ov)
        if op:
            # 背后超大英文名（描边）
            f = ImageFont.truetype(K.FONT_UI, 170)
            ov = layer(img)
            ImageDraw.Draw(ov).text((420, 90), op.get("en", ""), font=f, fill=(0, 0, 0, 0), stroke_width=2, stroke_fill=(22, 24, 28, 40))
            img.alpha_composite(ov)
    elif V == "E":
        rnd = random.Random(7)
        base = Image.new("RGBA", (W, H), (214, 200, 172, 255))
        noise = Image.effect_noise((W, H), 18).convert("L")
        tint = Image.new("RGBA", (W, H), (120, 96, 64, 255))
        tint.putalpha(noise.point(lambda v: max(0, v - 110) // 3))
        base.alpha_composite(tint)
        img = base
        ov = layer(img)
        od = ImageDraw.Draw(ov)
        for i in range(5):
            x, y = rnd.randint(0, W), rnd.randint(0, H)
            r = rnd.randint(40, 90)
            od.ellipse([x - r, y - r, x + r, y + r], outline=(120, 90, 50, 22), width=3)
        img.alpha_composite(ov.filter(ImageFilter.GaussianBlur(1.5)))
    return img


def keyart(img, op, box, scale):
    """半身「立绘」：待机帧整数倍最近邻放大，底部渐隐"""
    f = frame(op["_tex"], 0)
    big = K.up(f, scale)
    x0, y0, x1, y1 = box
    if V != "E":
        a = big.split()[3]
        mask = Image.new("L", big.size, 255)
        md = ImageDraw.Draw(mask)
        h = big.height
        for y in range(int(h * 0.72), h):
            md.line([(0, y), (big.width, y)], fill=max(0, int(255 * (1 - (y - h * 0.72) / (h * 0.28)))))
        big.putalpha(ImageChops.multiply(a, mask))
    cx = (x0 + x1) // 2
    px, py = cx - big.width // 2, y1 - big.height
    col = CLASS_COL.get(op.get("class"), CYAN)
    if V == "C":
        sh = K.tint(big, (22, 24, 28))
        sh.putalpha(sh.split()[3].point(lambda v: v * 70 // 255))
        img.alpha_composite(sh, (px + 14, py + 10))
    elif V == "B":
        K.put_glow(img, big, (150, 220, 240), 12, 0.5, (px, py))
    elif V == "A":
        K.put_glow(img, big, col, 10, 0.55, (px, py))
    img.alpha_composite(big, (px, py))


def polaroid(img, box, op, scale):
    """E：拍立得照片 + 胶带 + 红印章"""
    x0, y0, x1, y1 = box
    ph = Image.new("RGBA", (x1 - x0, y1 - y0), (0, 0, 0, 0))
    d = ImageDraw.Draw(ph)
    d.rectangle([0, 0, ph.width - 1, ph.height - 1], fill=(250, 248, 242, 255), outline=(150, 130, 100, 255))
    inner = (14, 14, ph.width - 14, ph.height - 60)
    g = Image.new("RGBA", (inner[2] - inner[0], inner[3] - inner[1]))
    gd = ImageDraw.Draw(g)
    for y in range(g.height):
        t = y / g.height
        gd.line([(0, y), (g.width, y)], fill=(int(30 + 30 * t), int(56 + 40 * t), int(70 + 40 * t), 255))
    sp = K.up(frame(op["_tex"], 0), scale)
    g.alpha_composite(sp, (g.width // 2 - sp.width // 2, g.height - sp.height + 6))
    ph.alpha_composite(g, inner[:2])
    d.text((ph.width // 2, ph.height - 32), "%s · %s" % (op["name"], op.get("en", "")), font=serif(18, op["name"]), fill=(56, 42, 30), anchor="mm")
    ph = ph.rotate(-2.2, expand=True, resample=Image.BICUBIC)
    sh = Image.new("RGBA", ph.size, (40, 28, 16, 0))
    sh.putalpha(ph.split()[3].point(lambda v: v * 80 // 255))
    img.alpha_composite(sh.filter(ImageFilter.GaussianBlur(4)), (x0 + 6, y0 + 8))
    img.alpha_composite(ph, (x0, y0))
    for (tx, ty, ang) in ((x0 + 20, y0 - 8, 28), (x1 - 70, y0 - 6, -24)):
        tp = Image.new("RGBA", (80, 24), (236, 222, 170, 170))
        tp = tp.rotate(ang, expand=True)
        img.alpha_composite(tp, (tx, ty))
    stamp(img, (x1 - 120, y1 - 150), "已归档")


def stamp(img, xy, s):
    st = Image.new("RGBA", (130, 64), (0, 0, 0, 0))
    d = ImageDraw.Draw(st)
    d.rounded_rectangle([3, 3, 126, 60], 6, outline=(178, 40, 40, 200), width=3)
    d.text((65, 33), s, font=serif(28, s), fill=(178, 40, 40, 200), anchor="mm")
    st = st.rotate(14, expand=True, resample=Image.BICUBIC)
    img.alpha_composite(st, xy)


# ---------- 组件 ----------
def op_card(img, box, op, selected=False, name_size=13, elite=0):
    """名册干员卡：左上职业、右上精英菱形、底部名字条"""
    x0, y0, x1, y1 = box
    col = CLASS_COL.get(op.get("class"), CYAN)
    if V == "A":
        panel(img, box, sel=selected, accent=col if selected else None, cut=8)
    elif V == "B":
        ov = layer(img)
        ImageDraw.Draw(ov).rounded_rectangle([x0, y0, x1, y1], 5, fill=T["fill_sel"] if selected else T["card"], outline=(VIOLET + (255,)) if selected else T["line"], width=2 if selected else 1)
        img.alpha_composite(ov)
        if selected:
            diamond(ImageDraw.Draw(img), ((x0 + x1) / 2, y0), 5, GOLD)
    elif V == "C":
        d = ImageDraw.Draw(img)
        if selected:
            d.rectangle([x0 + 4, y0 + 4, x1 + 4, y1 + 4], fill=(0, 0, 0))
        d.rectangle([x0, y0, x1, y1], fill=(255, 255, 255) if selected else T["card"], outline=(22, 24, 28), width=2 if selected else 1)
        d.rectangle([x0 + 1, y0 + 1, x1 - 1, y0 + 4], fill=col)
    elif V == "E":
        panel(img, box, sel=selected)
    f = frame(op["_tex"], 0)
    k = max(1, min(3, int((y1 - y0 - 46) / f.height)))
    sp = K.up(f, k)
    px = (x0 + x1) // 2 - sp.width // 2
    py = y1 - 24 - sp.height
    if py < y0 + 4:
        sp = sp.crop((0, (y0 + 4) - py, sp.width, sp.height))
        py = y0 + 4
    if selected and V in ("A", "B"):
        ov = layer(img)
        ImageDraw.Draw(ov).ellipse([px - 6, y1 - 40, px + sp.width + 6, y1 - 20], fill=(col if V == "A" else VIOLET) + (60,))
        img.alpha_composite(ov)
    img.alpha_composite(sp, (px, py))
    d = ImageDraw.Draw(img)
    if V == "B":
        ov = layer(img)
        ImageDraw.Draw(ov).rounded_rectangle([x0 + 2, y1 - 22, x1 - 2, y1 - 2], 4, fill=T["strip"])
        img.alpha_composite(ov)
    else:
        d.rectangle([x0 + 1, y1 - 22, x1 - 1, y1 - 1], fill=T["strip"])
    if selected and V == "C":
        d.rectangle([x0 + 1, y1 - 5, x1 - 1, y1 - 1], fill=YEL)
    text(img, ((x0 + x1) // 2, y1 - 12), op["name"], name_size, T["strip_text"], anchor="mm", head=(V == "E"))
    gc = col if V in ("A", "B") else T["glyph"]
    glyph(img, (x0 + 12, y0 + 14), 6, CLASS_GLYPH.get(op.get("class"), "diamond"), gc)
    star_row(img, (x1 - 8 - elite * 9, y0 + 8), elite, GOLD if V != "C" else (22, 24, 28), 6, 3)


def skill_row(img, xy, w, op, i, selected=False, manual=False, stage_lbl="招募", compact=False):
    """技能行：图标 + 名字 / 英文 + 充能 SP 环 + 解锁阶段 + 手动 / 自动"""
    sk = op["skills"][i]
    x, y = xy
    col = CLASS_COL.get(op.get("class"), CYAN)
    h = 46 if compact else 58
    panel(img, (x, y, x + w, y + h), sel=selected, accent=(col if V == "A" else VIOLET) if selected else None, cut=8, shadow=False)
    ic = icon(sk.get("icon", ""))
    side = 32 if not compact else 28
    ix = x + (14 if V == "C" else 10)
    if ic:
        img.alpha_composite(ic.resize((side, side), Image.NEAREST), (int(ix), int(y + (h - side) // 2)))
    d = ImageDraw.Draw(img)
    d.rectangle([ix, y + h - 12, ix + 14, y + h - 2], fill=(0, 0, 0, 200))
    d.text((ix + 7, y + h - 7), "S%d" % (i + 1), font=F(9), fill=(242, 244, 245), anchor="mm")
    tx = ix + side + 10
    text(img, (tx, y + 7), sk["name"], 15 if not compact else 13)
    en(img, (tx + 2, y + (28 if not compact else 24)), sk.get("en", ""), 9, T["sub"], 1)
    rx = x + w - 30
    rc = (CYAN if manual else GOLD) if V in ("A", "B") else ((22, 24, 28) if V == "C" else (178, 40, 40))
    ring(img, (rx, y + h // 2), 13, 0.72, rc, 3)
    text(img, (rx, y + h // 2), "%d" % int(sk.get("sp", 0)), 11, anchor="mm")
    text(img, (rx, y + h - 6), "SP", 7, T["sub"], anchor="mm")
    if manual:
        chip(img, (rx - 100, y + 8), "手动 Q", CYAN if V != "C" else YEL, 10, solid=True)
        text(img, (rx - 24, y + h - 16), "队友时自动", 9, T["sub"], anchor="ra")
    else:
        chip(img, (rx - 82, y + 8), "自动", T["sub"], 10)
        text(img, (rx - 24, y + h - 16), stage_lbl, 9, col if V in ("A", "B") else T["sub"], anchor="ra")
    return h


def title_bar(img, W, h, en_s, cn_s, col, subs=()):
    """顶栏标题"""
    d = ImageDraw.Draw(img)
    ov = layer(img)
    od = ImageDraw.Draw(ov)
    if V == "A":
        od.rectangle([0, 0, W, h], fill=(0, 0, 0, 120))
        img.alpha_composite(ov)
        d.line([(0, h), (W, h)], fill=T["line"])
        d.polygon([(0, 0), (250, 0), (236, h), (0, h)], fill=col)
        en(img, (18, 8), en_s, 11, T["ink"], 3)
        text(img, (18, 24), cn_s, 20, T["ink"])
        x = 262
    elif V == "B":
        od.rectangle([0, 0, W, h], fill=(4, 8, 18, 140))
        img.alpha_composite(ov)
        for i in range(W):
            a = int(110 * (1 - abs(i - W / 2) / (W / 2)))
            d.point((i, h), fill=PURPLE + (a,))
        # 节点标签条：左段彩色压缩英文，右段暗底中文
        d.rounded_rectangle([16, 12, 16 + 150, h - 12], 3, fill=VIOLET)
        en(img, (26, 19), en_s, 11, (255, 255, 255), 2)
        w = text(img, (182, h / 2), cn_s, 20, anchor="lm")
        diamond(d, (16, h / 2), 5, GOLD)
        x = 182 + w + 20
    elif V == "C":
        od.rectangle([0, 0, W, h], fill=(250, 250, 250, 240))
        img.alpha_composite(ov)
        d.line([(0, h), (W, h)], fill=(22, 24, 28), width=2)
        d.rectangle([0, 0, 252, h], fill=(22, 24, 28))
        hazard(img, (252, 0, 276, h))
        en(img, (18, 7), en_s, 11, YEL, 3, italic=False)
        text(img, (18, 24), cn_s, 20, (250, 250, 250))
        x = 290
    elif V == "E":
        img.alpha_composite(ov)
        text(img, (24, 10), cn_s, 26, head=True)
        en(img, (150, 22), en_s, 9, T["sub"], 3, italic=False)
        d.line([(16, h), (W - 16, h)], fill=(110, 88, 64), width=2)
        d.line([(16, h + 4), (W - 16, h + 4)], fill=(110, 88, 64), width=1)
        x = 240
    for i, s in enumerate(subs):
        text(img, (x, 14 + i * 16), s, 12 if i == 0 else 11, T["sub"])


def rail(img, x0, y0, step, cur, col):
    """左侧职业筛选轨"""
    d = ImageDraw.Draw(img)
    x1 = x0 + 44
    y1 = y0 + 8 * step + 12
    if V == "B":
        ov = layer(img)
        ImageDraw.Draw(ov).rounded_rectangle([x0, y0, x1, y1], 22, fill=T["fill"], outline=T["line"])
        img.alpha_composite(ov)
    else:
        panel(img, (x0, y0, x1, y1), cut=8, shadow=False)
    for i, c in enumerate(["全部"] + CLASS_ORDER[:7]):
        cy = y0 + 14 + i * step + 14
        on = c == cur
        cc = CLASS_COL.get(c, T["text"])
        if on:
            if V == "A":
                d.rectangle([x0 + 2, cy - 18, x1 - 2, cy + 18], fill=col + (60,))
                d.rectangle([x0 + 2, cy - 18, x0 + 4, cy + 18], fill=col)
            elif V == "B":
                d.ellipse([x0 + 4, cy - 19, x1 - 4, cy + 19], fill=VIOLET)
            elif V == "C":
                d.rectangle([x0 + 2, cy - 18, x1 - 2, cy + 18], fill=(22, 24, 28))
            elif V == "E":
                d.rectangle([x0 + 2, cy - 18, x1 - 2, cy + 18], outline=(178, 40, 40), width=2)
        gc = (cc if V in ("A",) else (250, 250, 250) if V in ("B", "C") else (178, 40, 40)) if on else T["glyph"]
        if c == "全部":
            text(img, ((x0 + x1) / 2, cy), "全", 13, (250, 250, 250) if (on and V == "C") else T["text"], anchor="mm")
        else:
            glyph(img, ((x0 + x1) / 2, cy - 4), 8, CLASS_GLYPH[c], gc)
            text(img, ((x0 + x1) / 2, cy + 12), c, 9, gc if on else T["sub"], anchor="mm")


def foot(img, W, H, s):
    d = ImageDraw.Draw(img)
    d.rectangle([W - 420, H - 16, W, H], fill=(0, 0, 0, 200))
    d.text((W - 6, H - 8), s, font=F(9), fill=(154, 163, 173), anchor="rm")


def name_block(img, x, y, op, col, big=44):
    text(img, (x, y), op["name"], big, bold=True, head=(V == "E"))
    en(img, (x + 4, y + big + 10), op.get("en", ""), 14, col if V in ("A", "B") else T["sub"], 4)
    cx = x + 2
    cy = y + big + 34
    cx += chip(img, (cx, cy), op.get("class", ""), col, 12, solid=(V in ("C", "E")))
    for tg in op.get("gallery", {}).get("tags", []):
        cx += chip(img, (cx, cy), tg, PURPLE, 11)
    return cy + 30


# ---------- 图：干员选择 ----------
def compose_select(W=1280, H=720, sel_id="skadi"):
    ops = roster()
    op = next(o for o in ops if o["_id"] == sel_id)
    col = CLASS_COL.get(op.get("class"), CYAN)
    img = backdrop(W, H, col, op)
    keyart(img, op, (560, 40, 960, 580), 5)
    title_bar(img, W, 54, "OPERATOR SELECT", "选择开局干员", col, ("主控 1 名；其余干员在探索中通过升级招募", "下一步：选择难度"))
    chip(img, (W - 372, 18), "难度 Ⅳ 潮汐已涨", STEEL, 11)
    chip(img, (W - 250, 18), "封面干员 水月", PURPLE, 11)
    small_btn(img, (W - 120, 14, W - 16, 42), "返回  Esc")
    rail(img, 14, 68, 46, op.get("class"), col)
    # 底部横向名册
    ry0 = H - 170
    d = ImageDraw.Draw(img)
    ov = layer(img)
    band = {"A": (0, 0, 0, 150), "B": (4, 8, 18, 150), "C": (250, 250, 250, 230), "E": (0, 0, 0, 0)}[V]
    ImageDraw.Draw(ov).rectangle([0, ry0 - 6, W, H], fill=band)
    img.alpha_composite(ov)
    d.line([(0, ry0 - 6), (W, ry0 - 6)], fill=T["line"] if V != "C" else (22, 24, 28), width=1 if V != "C" else 2)
    en(img, (70, ry0 - 2), "ROSTER  13 / 13", 9, T["sub"], 2)
    text(img, (182, ry0 - 2), "排序：职业 ▼", 10, T["sub"])
    text(img, (W - 230, ry0 - 2), "◀ ▶ / 滚轮 切换    Enter 下一步", 10, T["sub"])
    cw, chh, gap = 82, 112, 8
    x = 70
    for o in ops[:10]:
        on = o["_id"] == sel_id
        op_card(img, (x, ry0 + 14 - (8 if on else 0), x + cw, ry0 + 14 + chh), o, selected=on, name_size=12, elite=(2 if on else 0))
        x += cw + gap
    text(img, (x + 6, ry0 + 70), "▶", 16, T["sub"])
    text(img, (x + 6, ry0 + 92), "还有 3 名", 10, T["sub"])
    # 名字块 + 定位
    micro(img, (92, 284), "OPERATOR // 01")
    yb = name_block(img, 90, 300, op, col)
    text(img, (92, yb - 2), op.get("gallery", {}).get("desc", ""), 12, T["sub"])
    # 信息面板
    px0, py0, px1, py1 = 968, 68, W - 16, ry0 - 18
    panel(img, (px0, py0, px1, py1), accent=col if V == "A" else VIOLET, cut=12)
    micro(img, (px0, py0 - 12), "OPERATOR DATA // SKILL")
    tab_bar(img, (px0, py0, px1, py0 + 34), ["属性", "技能", "编队"], 1, col)
    y = py0 + 46
    base = op.get("base", {})
    for i, (k, v) in enumerate([("攻击", str(base.get("atk", "—"))), ("间隔", "%.2fs" % base.get("cd", 0)), ("射程", str(base.get("reach", "—"))), ("生命", "主控 100")]):
        sx = px0 + 14 + i * 72
        tab_head(img, (sx, y), k, TAB_HP if i < 3 else TAB_LAMP, 9)
        text(img, (sx, y + 18), v, 13)
    y += 46
    d.line([(px0 + 12, y), (px1 - 12, y)], fill=T["line"])
    y += 10
    for i in range(3):
        y += skill_row(img, (px0 + 10, y), px1 - px0 - 20, op, i, selected=(i == 2), manual=(i == 2), stage_lbl=["招募", "精英一", "精英二"][i]) + 8
    sk = op["skills"][2]
    lines = wrap("主控按 Q 释放；作为队友自动。" + sk.get("desc", ""), 11, px1 - px0 - 28)
    for i, ln in enumerate(lines[:3]):
        text(img, (px0 + 14, y + 2 + i * 16), ln if not (i == 2 and len(lines) > 3) else ln[:-1] + "…", 11, T["sub"])
    y += 4 + 16 * min(3, len(lines)) + 6
    chip(img, (px0 + 14, y), "天赋", col, 10, solid=(V == "C"))
    text(img, (px0 + 60, y + 1), op.get("talent", {}).get("name", "") + "  精英一解锁", 12)
    # 编队条
    sq = (92, 440)
    tab_head(img, sq, "编队", (90, 70, 190), 9)
    for i in range(3):
        bx, by = sq[0] + i * 94, sq[1] + 20
        panel(img, (bx, by, bx + 84, by + 56), sel=(i == 0 and V != "C"), accent=VIOLET if i == 0 else None, cut=8, shadow=False)
        if i == 0:
            spr = frame(op["_tex"], 0)
            img.alpha_composite(spr, (bx + 6, by + 56 - spr.height - 4))
            d.rectangle([bx + 1, by + 1, bx + 34, by + 15], fill=VIOLET)
            text(img, (bx + 5, by + 2), "主控", 10, (255, 255, 255))
            text(img, (bx + 66, by + 34), op["name"], 10, anchor="mm")
        else:
            text(img, (bx + 42, by + 22), "队友 %d" % i, 11, T["sub"], anchor="mm")
            text(img, (bx + 42, by + 40), "探索中招募", 9, T["sub"], anchor="mm")
    big_button(img, (1030, ry0 + 36, W - 16, ry0 + 112), "出击  ›", "ENTER / 手柄 A  ·  下一步选择难度", 24)
    callout(img, (238, 12), 1)
    callout(img, (36, 62), 2)
    callout(img, (62, ry0 + 8), 3)
    callout(img, (760, 100), 4)
    callout(img, (82, 284), 5)
    callout(img, (px0 - 8, py0 + 4), 6)
    callout(img, (80, 436), 7)
    callout(img, (1024, ry0 + 30), 8)
    foot(img, W, H, "概念图 %s · 干员选择 · %s" % (V, T["desc"]))
    return img


# ---------- 图：干员图鉴（战绩页已按用户 10-11 反馈去掉） ----------
def compose_codex(W=1280, H=720, sel_id="wisadel"):
    ops = roster()
    op = next(o for o in ops if o["_id"] == sel_id)
    col = CLASS_COL.get(op.get("class"), CYAN)
    img = backdrop(W, H, col, op)
    d = ImageDraw.Draw(img)
    # 顶部图鉴大页签
    tabs = [("干员", "OPERATOR"), ("敌人", "ENEMY"), ("精英", "ELITE"), ("Boss", "BOSS"), ("道具", "ITEM"), ("藏品", "RELIC"), ("结局", "ENDING")]
    if V == "E":
        title_bar(img, W, 50, "RHODES ISLAND MEDICAL DEPT. // ARCHIVE", "干员档案", col)
        x = 470
        for i, (cn, e) in enumerate(tabs):
            text(img, (x, 16), cn, 15, T["text"] if i == 0 else T["sub"], head=True)
            if i == 0:
                d.line([(x - 2, 38), (x + 34, 38)], fill=(178, 40, 40), width=2)
            x += 74
    else:
        ov = layer(img)
        ImageDraw.Draw(ov).rectangle([0, 0, W, 50], fill={"A": (0, 0, 0, 130), "B": (4, 8, 18, 150), "C": (250, 250, 250, 240)}[V])
        img.alpha_composite(ov)
        d.line([(0, 50), (W, 50)], fill=T["line"] if V != "C" else (22, 24, 28), width=1 if V != "C" else 2)
        if V == "C":
            d.rectangle([0, 0, 98, 50], fill=(22, 24, 28))
        en(img, (18, 8), "ARCHIVE", 11, YEL if V == "C" else (col if V == "A" else PURPLE), 3)
        text(img, (18, 24), "图鉴", 18, (250, 250, 250) if V == "C" else T["text"])
        x = 110
        for i, (cn, e) in enumerate(tabs):
            on = i == 0
            w = 96
            ink = T["text"]
            if on:
                if V == "A":
                    d.polygon([(x, 0), (x + w, 0), (x + w - 10, 50), (x, 50)], fill=col)
                    ink = T["ink"]
                elif V == "B":
                    d.rounded_rectangle([x + 2, 8, x + w - 4, 44], 4, fill=VIOLET)
                    diamond(d, (x + w / 2, 47), 4, GOLD)
                elif V == "C":
                    d.rectangle([x, 0, x + w, 50], fill=YEL)
                    d.rectangle([x, 46, x + w, 50], fill=(22, 24, 28))
            text(img, (x + 12, 9), cn, 14, ink if on else T["text"])
            en(img, (x + 12, 30), e, 8, ink if on else T["sub"], 1)
            x += w + 6
        text(img, (W - 150, 25), "已收录 13 / 13", 11, T["sub"], anchor="lm")
        small_btn(img, (W - 70, 12, W - 16, 38), "Esc")
    # 职业轨 + 网格
    rail(img, 14, 64, 44, op.get("class"), col)
    gx, gy = 70, 64
    gh = 28 + 4 * 118 + 26
    panel(img, (gx, gy, gx + 4 * 92 + 10, gy + gh), cut=10, fill={"A": (4, 8, 12, 170), "B": (6, 10, 20, 170), "C": (250, 250, 250, 200), "E": (232, 220, 196, 230)}[V])
    en(img, (gx + 10, gy + 8), "OPERATORS", 9, T["sub"], 2)
    text(img, (gx + 80, gy + 7), "按职业 ▼   13 名", 10, T["sub"])
    for i, o in enumerate(ops):
        cx = gx + 8 + (i % 4) * 92
        cy = gy + 28 + (i // 4) * 118
        op_card(img, (cx, cy, cx + 84, cy + 110), o, selected=(o["_id"] == sel_id), name_size=12, elite=[2, 1, 2, 0, 1, 2, 2, 1, 0, 2, 1, 2, 2][i % 13])
    cx, cy = gx + 8 + 92, gy + 28 + 3 * 118
    panel(img, (cx, cy, cx + 84, cy + 110), cut=8, shadow=False)
    text(img, (cx + 42, cy + 50), "?", 28, T["sub"], anchor="mm")
    text(img, (cx + 42, cy + 96), "未解锁", 11, T["sub"], anchor="mm")
    text(img, (gx + 4 * 92 // 2 + 8, gy + gh - 16), "滚轮 / 上滑翻页", 10, T["sub"], anchor="mm")
    # 立绘 + 名字块 + 档案小表
    lore = json.load(open(os.path.join(ROOT, "game", "data", "lore.json"), encoding="utf-8")).get(sel_id, {})
    prof = lore.get("profile", {}) if isinstance(lore, dict) else {}
    if V == "E":
        polaroid(img, (480, 70, 850, 470), op, 3)
        y = 500
        micro(img, (472, y - 14), "PERSONNEL FILE // %s" % op.get("en", ""))
        for k, v in list(prof.items())[:4]:
            text(img, (472, y), k, 13, T["sub"], head=True)
            text(img, (552, y), str(v), 13, head=True)
            d.line([(548, y + 18), (840, y + 18)], fill=(110, 88, 64, 120))
            y += 24
        cx = 472
        y += 6
        cx += chip(img, (cx, y), op.get("class", ""), col, 12, solid=True)
        for tg in op.get("gallery", {}).get("tags", []):
            cx += chip(img, (cx, y), tg, PURPLE, 11)
        fy = 640
    else:
        keyart(img, op, (480, 54, 870, 436), 4)
        micro(img, (472, 426), "OPERATOR // %s" % op.get("en", ""))
        name_block(img, 470, 440, op, col)
        y = 548
        for k, v in list(prof.items())[:4]:
            text(img, (472, y), k, 11, T["sub"])
            text(img, (536, y), str(v), 11)
            y += 17
        fy = 626
    for i, fm in enumerate(["待机", "移动", "攻击", "技能", "精二"]):
        fx = 472 + i * 58
        on = i == 0
        if V == "B":
            d.rounded_rectangle([fx, fy, fx + 52, fy + 24], 12, fill=VIOLET if on else (6, 10, 16), outline=VIOLET if on else T["line"])
        elif V == "C":
            d.rectangle([fx, fy, fx + 52, fy + 24], fill=(22, 24, 28) if on else (250, 250, 250), outline=(22, 24, 28))
        elif V == "E":
            d.rectangle([fx, fy, fx + 52, fy + 24], outline=(178, 40, 40) if on else (110, 88, 64), width=2 if on else 1)
        else:
            panel(img, (fx, fy, fx + 52, fy + 24), cut=6, fill=col + (255,) if on else None, shadow=False)
        text(img, (fx + 26, fy + 12), fm, 11, ((250, 250, 250) if V in ("B", "C") else (178, 40, 40) if V == "E" else T["ink"]) if on else T["text"], anchor="mm")
    text(img, (472, fy + 34), "点按钮切换演示动作（现有图鉴功能保留）", 10, T["sub"])
    # 右侧信息面板：档案 / 技能 / 成长 / 藏品契合
    px0, py0, px1, py1 = 880, 64, W - 16, H - 22
    panel(img, (px0, py0, px1, py1), accent=col if V == "A" else VIOLET, cut=12)
    tab_bar(img, (px0, py0, px1, py0 + 34), ["档案", "技能", "成长", "藏品契合"], 2, col, 13)
    y = py0 + 48
    en(img, (px0 + 14, y), "GROWTH PATH", 9, col if V in ("A", "B") else T["sub"], 2)
    text(img, (px0 + 110, y - 1), "局内升级时按此顺序出现成长卡", 10, T["sub"])
    y += 22
    nodes = op.get("progression", [])[:7]
    lx = px0 + 30
    d.line([(lx, y + 8), (lx, y + 8 + 50 * len(nodes) - 30)], fill=T["line"], width=2)
    gicons = ["growth_hp", "growth_armor", "growth_dodge", "growth_pickup", "growth_b_range", "growth_b_count"]
    for i, n in enumerate(nodes):
        ny = y + i * 50
        is_elite = n.get("type") == "elite"
        if V == "C":
            ncol = YEL if is_elite else (22, 24, 28)
        elif V == "E":
            ncol = (178, 40, 40) if is_elite else (110, 88, 64)
        else:
            ncol = GOLD if is_elite else (col if V == "A" else PURPLE)
        d.ellipse([lx - 7, ny + 1, lx + 7, ny + 15], fill=ncol if i < 3 else (T["fill"][:3]), outline=(22, 24, 28) if V == "C" else ncol, width=2)
        ic = icon(n.get("icon", "")) or icon(("skill_%s_s%d" % (sel_id, 2 if n.get("level") == 1 else 3)) if is_elite else gicons[i % len(gicons)])
        bx = lx + 18
        panel(img, (bx, ny - 6, px1 - 14, ny + 36), sel=(is_elite and V != "E"), accent=ncol if is_elite else None, cut=8, shadow=False)
        if ic:
            img.alpha_composite(ic.resize((28, 28), Image.NEAREST), (bx + (12 if V == "C" else 8), ny + 1))
        text(img, (bx + 48, ny - 2), n.get("name", ""), 13)
        sub = ("精英化 · 解锁 S%d / 天赋" % (2 if n.get("level") == 1 else 3)) if is_elite else ("成长节点 · 本局已取" if i < 3 else "成长节点 · 未取")
        text(img, (bx + 48, ny + 16), sub, 10, (GOLD if V in ("A", "B") else (178, 40, 40) if V == "E" else T["text"]) if is_elite else T["sub"])
        if i < 3:
            star_row(img, (px1 - 32, ny + 10), 1, GREEN if V != "E" else (178, 40, 40), 8)
    y += 50 * len(nodes) + 4
    d.line([(px0 + 12, y), (px1 - 12, y)], fill=T["line"])
    y += 12
    tab_head(img, (px0 + 14, y), "藏品契合", (90, 70, 190), 9)
    text(img, (px0 + 80, y + 1), "按 hit_sources 推算 · 远程 / 物理 / 范围", 9, T["sub"])
    y += 22
    rel = ["relic_10", "relic_11", "relic_13", "relic_18", "relic_2", "relic_103", "relic_104", "relic_125", "relic_147", "relic_230"]
    for i, rid in enumerate(rel):
        ic = icon(rid)
        bx = px0 + 14 + (i % 7) * 46
        by = y + (i // 7) * 44
        panel(img, (bx, by, bx + 38, by + 38), sel=(i < 2), accent=GOLD if i < 2 else None, cut=6, shadow=False)
        if ic:
            img.alpha_composite(ic.resize((32, 32), Image.NEAREST), (bx + 3, by + 3))
    text(img, (px0 + 14 + 3 * 46 + 6, y + 56), "+9 件 · 点开看全表", 11, T["sub"])
    callout(img, (104, 44), 1)
    callout(img, (36, 58), 2)
    callout(img, (gx + 4 * 92 + 6, gy + 4), 2)
    callout(img, (462, 424), 3)
    callout(img, (px0 - 8, py0 + 4), 4)
    callout(img, (px0 + 6, py0 + 46), 5)
    callout(img, (px1 - 20, y - 6), 6)
    callout(img, (462, 622), 7)
    foot(img, W, H, "概念图 %s · 干员图鉴 · %s" % (V, T["desc"]))
    return img


# ---------- 图：手机（触屏，只出 A） ----------
def compose_phone(W=740, H=360, sel_id="skadi"):
    ops = roster()
    op = next(o for o in ops if o["_id"] == sel_id)
    col = CLASS_COL.get(op.get("class"), CYAN)
    img = backdrop(W, H, col, op)
    d = ImageDraw.Draw(img)
    keyart(img, op, (330, 10, 490, 300), 3)
    d.polygon([(0, 0), (150, 0), (140, 34), (0, 34)], fill=col)
    text(img, (10, 9), "选择开局干员", 15, T["ink"])
    small_btn(img, (W - 70, 6, W - 8, 28), "返回")
    panel(img, (8, 40, 150, H - 8), cut=8, fill=(4, 8, 12, 180))
    for i, o in enumerate(ops[:6]):
        cx = 14 + (i % 2) * 68
        cy = 48 + (i // 2) * 94
        op_card(img, (cx, cy, cx + 62, cy + 88), o, selected=(o["_id"] == sel_id), name_size=11)
    text(img, (79, H - 16), "▼ 上滑还有 7 名", 9, T["sub"], anchor="mm")
    name_block(img, 162, 196, op, col, 30)
    px0, py0, px1, py1 = 470, 40, W - 8, H - 72
    panel(img, (px0, py0, px1, py1), accent=col, cut=10)
    tab_bar(img, (px0, py0, px1, py0 + 26), ["属性", "技能", "编队"], 1, col, 12)
    y = py0 + 34
    for i in range(3):
        y += skill_row(img, (px0 + 8, y), px1 - px0 - 16, op, i, selected=(i == 2), manual=(i == 2), stage_lbl=["招募", "精英一", "精英二"][i], compact=True) + 6
    text(img, (px0 + 10, y + 2), "点技能行看说明 · 主控 S3 点技能键释放", 9, T["sub"])
    big_button(img, (W - 190, H - 64, W - 8, H - 10), "出击  ›", None, 18)
    text(img, (162, H - 44), "编队：主控 + 2 名队友（探索中招募）", 10, T["sub"])
    callout(img, (150, 44), 1)
    callout(img, (px0 - 6, py0 + 2), 2)
    callout(img, (W - 196, H - 68), 3)
    foot(img, W, H, "概念图 C · 手机触屏 · 740×360 · 仅示意")
    return img


# ---------- D 极简像素：640×360 画布画边框 / 精灵 / 点阵标题，×2 放大后再叠正文 ----------
PAL = [(8, 8, 12), (16, 18, 22), (28, 32, 40), (48, 56, 70), STEEL, (154, 163, 173), (242, 244, 245), CYAN,
       CYAN_DIM, GOLD, RED, VIOLET, PURPLE, GREEN, TAB_HP, TAB_LAMP]   # 界面 16 色（精灵与技能图标不计）


class Pix:
    def __init__(self, w=640, h=360):
        self.lo = Image.new("RGBA", (w, h), PAL[1] + (255,))
        self.d = ImageDraw.Draw(self.lo)
        self.d.fontmode = "1"      # 点阵：不抗锯齿
        self.ops = []

    def frame(self, box, edge=PAL[4], fill=PAL[2], sel=False):
        """粗像素九宫格：外黑描边 2px、缺角、内亮边 1px、顶部高光、底部阴影"""
        x0, y0, x1, y1 = box
        d = self.d
        d.rectangle([x0 + 2, y0, x1 - 2, y1], fill=PAL[0])
        d.rectangle([x0, y0 + 2, x1, y1 - 2], fill=PAL[0])
        d.rectangle([x0 + 1, y0 + 1, x1 - 1, y1 - 1], fill=PAL[0])
        e = CYAN if sel else edge
        d.rectangle([x0 + 2, y0 + 2, x1 - 2, y1 - 2], fill=e)
        d.rectangle([x0 + 3, y0 + 3, x1 - 3, y1 - 3], fill=fill)
        d.line([(x0 + 4, y0 + 4), (x1 - 4, y0 + 4)], fill=PAL[3])
        d.line([(x0 + 4, y1 - 4), (x1 - 4, y1 - 4)], fill=PAL[1])
        if sel:
            for (cx, cy) in ((x0 + 3, y0 + 3), (x1 - 4, y0 + 3), (x0 + 3, y1 - 4), (x1 - 4, y1 - 4)):
                d.rectangle([cx, cy, cx + 1, cy + 1], fill=GOLD)

    def head(self, xy, s, size, col=PAL[6], anchor="la"):
        """点阵标题：小字号无抗锯齿 + 1px 硬阴影，放大后成为 2px 像素块"""
        f = F(size, s)
        x, y = xy
        self.d.text((x + 1, y + 1), s, font=f, fill=PAL[0], anchor=anchor)
        self.d.text((x, y), s, font=f, fill=col, anchor=anchor)

    def t(self, xy, s, size, col=PAL[6], anchor="la"):
        self.ops.append(("t", (xy[0] * 2, xy[1] * 2), s, size, col, anchor))

    def im(self, im, xy):
        self.ops.append(("i", im, (int(xy[0] * 2), int(xy[1] * 2))))

    def render(self):
        img = self.lo.resize((self.lo.width * 2, self.lo.height * 2), Image.NEAREST)
        d = ImageDraw.Draw(img)
        for op in self.ops:
            if op[0] == "t":
                _, xy, s, size, col, anchor = op
                d.text(xy, s, font=F(size, s), fill=col, anchor=anchor)
            else:
                img.alpha_composite(op[1], op[2])
        return img


def compose_select_pixel(sel_id="skadi"):
    ops = roster()
    op = next(o for o in ops if o["_id"] == sel_id)
    P = Pix()
    d = P.d
    # 背景：4×4 Bayer 抖动的上暗下亮
    bay = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]
    for y in range(360):
        for x in range(640):
            t = y / 360.0 * 16
            if bay[y % 4][x % 4] < t * 0.55:
                d.point((x, y), fill=PAL[2])
    for y in range(40, 240, 6):
        for x in range((y // 6 % 2) * 3, 640, 24):
            d.point((x, y), fill=PAL[3])
    # 顶栏
    P.frame((4, 4, 214, 28), edge=CYAN)
    P.head((12, 9), "选择开局干员", 12)
    P.t((222, 9), "主控 1 名；其余干员在探索中通过升级招募 · 下一步：选择难度", 11, PAL[5])
    P.frame((572, 4, 636, 24))
    P.t((604, 14), "返回 Esc", 11, PAL[6], "mm")
    # 立绘：1× 待机帧 ×4，像素描边 + 地面影子
    small = K.frame(op["_tex"].replace("@2x", ""), 4, 0, trim=True)
    big = K.up(small, 4)
    a = big.split()[3].point(lambda v: 255 if v > 0 else 0)
    out = Image.new("RGBA", (big.width + 4, big.height + 4), (0, 0, 0, 0))
    edge = Image.new("RGBA", big.size, CYAN_DIM + (255,))
    for dx, dy in ((0, 2), (4, 2), (2, 0), (2, 4)):
        out.paste(edge, (dx, dy), a)
    out.alpha_composite(big, (2, 2))
    cx, by = 330, 234
    d.ellipse([cx - 50, by - 6, cx + 50, by + 4], fill=PAL[0])
    P.lo.alpha_composite(out, (cx - out.width // 2, by - out.height + 2))
    # 名字块
    P.head((14, 80), op["name"], 24)
    P.t((16, 116), op.get("en", ""), 12, CYAN)
    x = 14
    for i, tg in enumerate([op.get("class", "")] + op.get("gallery", {}).get("tags", [])):
        w = int(F(11, tg).getlength(tg) / 2) + 8
        d.rectangle([x, 130, x + w, 140], fill=PAL[0])
        d.rectangle([x, 130, x + 1, 140], fill=CYAN if i == 0 else PURPLE)
        P.t((x + 4, 131), tg, 11, PAL[6])
        x += w + 3
    P.t((14, 146), op.get("gallery", {}).get("desc", ""), 11, PAL[5])
    # 编队
    P.head((14, 164), "编队", 11, VIOLET)
    for i in range(3):
        bx = 14 + i * 46
        P.frame((bx, 178, bx + 42, 210), edge=VIOLET if i == 0 else PAL[3])
        if i == 0:
            sp = K.frame("op_%s_idle" % sel_id, 4, 0, trim=True)
            sp = sp.crop((0, 0, sp.width, min(sp.height, 26)))
            P.lo.alpha_composite(sp, (bx + 21 - sp.width // 2, 182))
            d.rectangle([bx + 3, 200, bx + 22, 207], fill=VIOLET)
            P.t((bx + 5, 200), "主控", 9, PAL[6])
        else:
            P.t((bx + 21, 194), "队友 %d" % i, 10, PAL[5], "mm")
    # 信息面板
    px0, py0, px1, py1 = 432, 32, 636, 238
    P.frame((px0, py0, px1, py1))
    tw = (px1 - px0 - 8) // 3
    for i, nm in enumerate(["属性", "技能", "编队"]):
        tx = px0 + 4 + i * tw
        if i == 1:
            d.rectangle([tx, py0 + 4, tx + tw - 2, py0 + 18], fill=CYAN)
            P.head((tx + tw // 2, py0 + 11), nm, 11, PAL[1], "mm")
        else:
            P.head((tx + tw // 2, py0 + 11), nm, 11, PAL[5], "mm")
    d.line([(px0 + 4, py0 + 19), (px1 - 4, py0 + 19)], fill=PAL[3])
    base = op.get("base", {})
    for i, (k, v) in enumerate([("攻击", str(base.get("atk", "—"))), ("间隔", "%.2fs" % base.get("cd", 0)), ("射程", str(base.get("reach", "—"))), ("生命", "100")]):
        sx = px0 + 8 + i * 48
        d.rectangle([sx, py0 + 24, sx + 18, py0 + 30], fill=TAB_HP if i < 3 else TAB_LAMP)
        P.t((sx + 1, py0 + 24), k, 8, PAL[6])
        P.t((sx, py0 + 32), v, 12, PAL[6])
    y = py0 + 46
    for i in range(3):
        sk = op["skills"][i]
        P.frame((px0 + 4, y, px1 - 4, y + 30), sel=(i == 2), fill=PAL[2] if i != 2 else (20, 40, 48))
        ic = icon(sk.get("icon", ""))
        if ic:
            P.im(ic, (px0 + 9, y + 7))
        P.t((px0 + 28, y + 6), sk["name"], 13, PAL[6])
        P.t((px0 + 28, y + 18), sk.get("en", ""), 8, PAL[5])
        # 像素 SP 条（8 格）
        for k in range(8):
            d.rectangle([px1 - 46 + k * 5, y + 20, px1 - 43 + k * 5, y + 23], fill=(GOLD if i < 2 else CYAN) if k < 6 else PAL[3])
        P.t((px1 - 10, y + 7), "SP %d" % int(sk.get("sp", 0)), 9, PAL[6], "ra")
        tag = "手动 Q" if i == 2 else ["招募", "精英一"][i] + "·自动"
        P.t((px1 - 10, y + 13), "", 9)
        if i == 2:
            d.rectangle([px1 - 76, y + 6, px1 - 50, y + 13], fill=CYAN)
            P.t((px1 - 74, y + 6), tag, 9, PAL[1])
        else:
            P.t((px1 - 50, y + 6), tag, 9, PAL[5], "ra")
        y += 34
    lines = wrap("主控按 Q 释放；作为队友自动。" + op["skills"][2].get("desc", ""), 10, (px1 - px0 - 14) * 2)
    for i, ln in enumerate(lines[:2]):
        P.t((px0 + 7, y + i * 8), ln if i < 1 else ln[:-1] + "…", 10, PAL[5])
    d.rectangle([px0 + 7, y + 19, px0 + 22, y + 25], fill=CYAN_DIM)
    P.t((px0 + 8, y + 19), "天赋", 9, PAL[1])
    P.t((px0 + 26, y + 19), op.get("talent", {}).get("name", "") + "  精英一解锁", 10, PAL[6])
    # 职业筛选（横排）+ 两行网格名册
    fy = 242
    for i, c in enumerate(["全"] + CLASS_ORDER[:7]):
        fx = 4 + i * 30
        on = c == op.get("class")
        d.rectangle([fx, fy, fx + 27, fy + 9], fill=CYAN if on else PAL[0])
        P.t((fx + 14, fy + 5), c, 9, PAL[1] if on else PAL[5], "mm")
    cw, ch = 52, 50
    for i in range(14):
        cx = 4 + (i % 7) * (cw + 2)
        cy = 256 + (i // 7) * (ch + 2)
        if i >= len(ops):
            P.frame((cx, cy, cx + cw, cy + ch), edge=PAL[3], fill=PAL[1])
            P.head((cx + cw // 2, cy + ch // 2), "?", 12, PAL[3], "mm")
            continue
        o = ops[i]
        on = o["_id"] == sel_id
        P.frame((cx, cy, cx + cw, cy + ch), sel=on, fill=(20, 40, 48) if on else PAL[2])
        sp = K.frame(o["_tex"].replace("@2x", ""), 4, 0, trim=True)
        sp = sp.crop((0, 0, sp.width, min(sp.height, ch - 16)))
        P.lo.alpha_composite(sp, (cx + cw // 2 - sp.width // 2, cy + ch - 13 - sp.height))
        d.rectangle([cx + 3, cy + ch - 12, cx + cw - 3, cy + ch - 3], fill=PAL[0])
        P.t((cx + cw // 2, cy + ch - 7), o["name"], 11, PAL[6] if on else PAL[5], "mm")
        cc = CLASS_COL.get(o.get("class"))
        d.rectangle([cx + 5, cy + 5, cx + 8, cy + 8], fill=min(PAL[4:], key=lambda p: sum((p[k] - cc[k]) ** 2 for k in range(3))))
    # 出击按钮
    P.frame((396, 262, 636, 336), edge=PAL[6], fill=CYAN)
    d.rectangle([399, 265, 633, 267], fill=(150, 245, 240))
    P.head((516, 290), "出击 ▶", 18, PAL[1], "mm")
    P.t((516, 318), "ENTER / 手柄 A · 下一步选择难度", 11, PAL[1], "mm")
    P.t((396, 250), "◀ ▶ ▲ ▼ 选择    Enter 出击", 10, PAL[5])
    img = P.render()
    foot(img, 1280, 720, "概念图 D · 干员选择 · " + THEMES["D"]["desc"])
    return img


# ---------- 对比总览 ----------
def contact_sheet(tiles, out_path, title):
    tw, th = 640, 360
    gap, lab = 16, 40
    cols = 3
    rows = (len(tiles) + cols - 1) // cols
    W = cols * tw + (cols + 1) * gap
    H = 70 + rows * (th + lab + gap) + gap
    sheet = Image.new("RGB", (W, H), (12, 14, 18))
    d = ImageDraw.Draw(sheet)
    d.text((gap, 22), title, font=font_for(title, 26), fill=(242, 244, 245))
    d.text((W - gap, 30), "同一内容与骨架，只换美术语言 · 1280×720 缩到一半", font=font_for("同", 14), fill=(154, 163, 173), anchor="ra")
    for i, (letter, desc, im) in enumerate(tiles):
        c, r = i % cols, i // cols
        x = gap + c * (tw + gap)
        y = 70 + r * (th + lab + gap)
        sheet.paste(im.convert("RGB").resize((tw, th), Image.LANCZOS), (x, y))
        d.rectangle([x, y + th, x + tw, y + th + lab], fill=(24, 28, 36))
        d.rectangle([x, y + th, x + 40, y + th + lab], fill=CYAN)
        d.text((x + 20, y + th + lab / 2), letter, font=ImageFont.truetype(K.FONT_UI, 22), fill=(8, 20, 24), anchor="mm")
        d.text((x + 52, y + th + lab / 2), desc, font=font_for(desc, 15), fill=(242, 244, 245), anchor="lm")
    sheet.save(out_path)


def render_variant(v, out):
    """出某一方向的图；返回 {名字: 图}"""
    global CALLOUTS
    CALLOUTS = False
    res = {}
    if v == "D":
        res["select_D"] = compose_select_pixel()
    else:
        set_theme(v)
        if v != "E":
            res["select_" + v] = compose_select()
        res["codex_" + v] = compose_codex()
    for k, im in res.items():
        im.convert("RGB").save(os.path.join(out, "concept_%s.png" % k))
    return res


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    var = next((a.split("=", 1)[1] for a in sys.argv[1:] if a.startswith("--variant=")), None)
    if var is None:
        out = args[0] if args else os.path.join(ROOT, "build", "concept", "operator_ui")
        os.makedirs(out, exist_ok=True)
        set_theme("A")
        compose_select().convert("RGB").save(os.path.join(out, "concept_op_select.png"))
        compose_codex().convert("RGB").save(os.path.join(out, "concept_op_codex.png"))
        compose_phone().convert("RGB").save(os.path.join(out, "concept_op_select_phone.png"))
        print("写入", out)
        sys.exit(0)
    out = args[0] if args else os.path.join(ROOT, "build", "concept", "operator_ui", "variants")
    os.makedirs(out, exist_ok=True)
    vs = ["A", "B", "C", "D", "E"] if var == "all" else [var.upper()]
    allim = {}
    for v in vs:
        allim.update(render_variant(v, out))
    if var == "all":
        sel = [("A", "现版：暗面板 + 单切角 + 青色出击", allim["select_A"]),
               ("B", "水月 / 集成战略：无切角、紫金饰线、深海渐变", allim["select_B"]),
               ("C", "罗德岛终端：浅色面板黑字、斜色带、黄黑警示条", allim["select_C"]),
               ("D", "极简像素：≤16 色九宫格边框、两行网格名册", allim["select_D"]),
               ("B", "图鉴 · 水月：成长时间线 + 藏品契合", allim["codex_B"]),
               ("C", "图鉴 · 罗德岛终端", allim["codex_C"])]
        contact_sheet(sel, os.path.join(out, "contact_sheet.png"), "干员选择 / 图鉴 · 美术方向对比")
        contact_sheet([("A", "图鉴 · 现版（去掉战绩）", allim["codex_A"]), ("B", "图鉴 · 水月 / 集成战略", allim["codex_B"]),
                       ("C", "图鉴 · 罗德岛终端", allim["codex_C"]), ("E", "图鉴 · 深海档案（纸本病历卡）", allim["codex_E"])],
                      os.path.join(out, "contact_sheet_codex.png"), "干员图鉴 · 美术方向对比")
    print("写入", out, sorted(allim))
