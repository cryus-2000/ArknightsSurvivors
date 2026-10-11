# -*- coding: utf-8 -*-
"""干员选择 / 干员图鉴 概念图（docs/58，2026-10-11）：参考《明日方舟》干员界面的版式，用本项目像素资产 + 方案 A「潮汐航线」配色画三张 PNG。
只用 art/incoming 的 op_*_idle@2x / player_idle@2x、skill_*、growth_*、_trial_icons/relic_* 与 game/fonts/ui.ttf；不用原作任何图片。
不是游戏代码，只是给用户看的概念图。

用法：python tools/concept_operator_ui.py [输出目录，缺省 build/concept/operator_ui]
输出：concept_op_select.png（1280×720）、concept_op_codex.png（1280×720）、concept_op_select_phone.png（740×360）
"""
import os, sys, json, glob, math
from PIL import Image, ImageDraw, ImageFont, ImageFilter
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import promo_keyart as K
from promo_roster import font_for

ROOT = K.ROOT
ART = K.ART
CHAR_DIR = os.path.join(ROOT, "game", "data", "characters")

# ui.gd 语义色（docs/37 §2；PURPLE 不改）
BG = (16, 18, 22)
LINE = (255, 255, 255, 41)
CYAN = (54, 226, 220)
GOLD = (244, 192, 78)
RED = (255, 61, 139)
PURPLE = (168, 133, 255)
VIOLET = (124, 107, 255)
GREEN = (47, 211, 160)
TEXT = (242, 244, 245)
SUB = (154, 163, 173)
STEEL = (126, 152, 184)
CLASS_COL = {"先锋": (255, 199, 89), "近卫": (140, 191, 255), "重装": (255, 184, 97), "狙击": (255, 107, 97),
             "术师": (255, 128, 56), "医疗": (140, 255, 153), "辅助": (255, 217, 128), "特种": (191, 153, 255)}
CLASS_ORDER = ["先锋", "近卫", "重装", "狙击", "术师", "医疗", "辅助", "特种"]
CLASS_EN = {"先锋": "VANGUARD", "近卫": "GUARD", "重装": "DEFENDER", "狙击": "SNIPER", "术师": "CASTER", "医疗": "MEDIC", "辅助": "SUPPORTER", "特种": "SPECIALIST"}
# 职业线性图标（白线简化符号：和 HUD 一样不用原作图片，用几何形状示意）
CLASS_GLYPH = {"先锋": "flag", "近卫": "blade", "重装": "shield", "狙击": "cross", "术师": "orb", "医疗": "plus", "辅助": "wave", "特种": "diamond"}


def F(size, text=""):
    return font_for(text or "汉", size)


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
    # 原作按稀有度排；本作没有稀有度，按职业顺序 + 主控优先（水月是封面干员）
    out.sort(key=lambda d: (0 if d["_id"] == "mizuki" else 1, CLASS_ORDER.index(d.get("class", "特种")) if d.get("class") in CLASS_ORDER else 9))
    return out


def frame(tex, i=0):
    return K.frame(tex, 4, i, trim=True)


def icon(name):
    p = os.path.join(ART, name + ".png")
    if not os.path.exists(p):
        p = os.path.join(ART, "_trial_icons", name + ".png")
    return Image.open(p).convert("RGBA") if os.path.exists(p) else None


# ---------- 绘图小件 ----------
def layer(img):
    return Image.new("RGBA", img.size, (0, 0, 0, 0))


def cut_poly(x0, y0, x1, y1, cut=10, corners="tr"):
    """斜切角矩形（原作面板的切角）：corners 里有 tl/tr/bl/br 哪几个就切哪几个"""
    pts = []
    pts.append((x0 + cut, y0) if "tl" in corners else (x0, y0))
    pts.append((x1 - cut, y0) if "tr" in corners else (x1, y0))
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


def panel(img, box, fill=(10, 14, 20, 200), edge=LINE, cut=10, corners="tr", accent=None, accent_len=28):
    """炭灰半透明平面板 + 1px 细边 + 左上角一段强调色（docs/37 §3 frame），加原作式切角"""
    x0, y0, x1, y1 = box
    ov = layer(img)
    d = ImageDraw.Draw(ov)
    pts = cut_poly(x0, y0, x1, y1, cut, corners)
    d.polygon(pts, fill=fill)
    # 顶部一线高光
    d.line([pts[0], pts[1]], fill=(255, 255, 255, 36), width=1)
    d.polygon(pts, outline=edge)
    img.alpha_composite(ov)
    if accent:
        dd = ImageDraw.Draw(img)
        dd.line([(x0, y0), (x0 + accent_len, y0)], fill=accent, width=2)
        dd.line([(x0, y0), (x0, y0 + accent_len)], fill=accent, width=2)


def text(img, xy, s, size, col=TEXT, anchor="la", bold=False):
    d = ImageDraw.Draw(img)
    f = F(size, s)
    d.text(xy, s, font=f, fill=col, anchor=anchor, stroke_width=1 if (bold and size >= 18) else 0, stroke_fill=col if bold else None)
    return d.textlength(s, font=f)


def en(img, xy, s, size, col=SUB, spacing=2, anchor="la"):
    """压缩斜体英文（ui.gd UI.en：字距拉开 + 横向压缩）"""
    f = ImageFont.truetype(K.FONT_UI, size)
    w = sum(f.getlength(ch) + spacing for ch in s)
    tmp = Image.new("RGBA", (int(w) + 8, size + 8), (0, 0, 0, 0))
    d = ImageDraw.Draw(tmp)
    x = 2
    for ch in s:
        d.text((x, 2), ch, font=f, fill=col)
        x += f.getlength(ch) + spacing
    tmp = tmp.resize((int(tmp.width * 0.84), tmp.height), Image.LANCZOS)
    # 轻微斜体
    tmp = tmp.transform(tmp.size, Image.AFFINE, (1, 0.18, -0.18 * tmp.height / 2, 0, 1, 0), Image.BILINEAR)
    ax, ay = xy
    if anchor == "ra":
        ax -= tmp.width
    elif anchor == "ma":
        ax -= tmp.width // 2
    img.alpha_composite(tmp, (int(ax), int(ay) - 2))
    return tmp.width


def chip(img, xy, s, col, size=11, dark=True):
    """标签片：暗底 + 左侧色条（ui.gd UI.chip）"""
    d = ImageDraw.Draw(img)
    f = F(size, s)
    w = d.textlength(s, font=f) + 14
    x, y = xy
    h = size + 8
    ov = layer(img)
    od = ImageDraw.Draw(ov)
    od.rectangle([x, y, x + w, y + h], fill=(0, 0, 0, 150) if dark else col + (255,))
    img.alpha_composite(ov)
    d.rectangle([x, y, x + 2, y + h], fill=col)
    d.text((x + 8, y + 4), s, font=f, fill=TEXT if dark else (10, 12, 16))
    return w + 6


def tab_head(img, xy, s, col, size=10):
    """小标签头：彩色底白字，放在数值正上方（UI.tab）"""
    d = ImageDraw.Draw(img)
    f = F(size, s)
    w = d.textlength(s, font=f) + 10
    x, y = xy
    d.rectangle([x, y, x + w, y + size + 5], fill=col)
    d.text((x + 5, y + 2), s, font=f, fill=(255, 255, 255))
    return w


def glyph(img, c, r, kind, col, width=2):
    """职业线性图标（白线几何，示意用）"""
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
        pts = [(x - r + i * r / 4.0, y + (r * 0.5 if i % 2 else -r * 0.5)) for i in range(9)]
        d.line(pts, fill=col, width=width)
    elif kind == "diamond":
        d.polygon([(x, y - r), (x + r, y), (x, y + r), (x - r, y)], outline=col, width=width)
    elif kind == "flag":
        d.line([(x - r * 0.7, y - r), (x - r * 0.7, y + r)], fill=col, width=width)
        d.polygon([(x - r * 0.7, y - r), (x + r, y - r * 0.5), (x - r * 0.7, y)], fill=col)


def star_row(img, xy, n, col=GOLD, size=7, gap=3):
    """稀有度 / 精英阶段用的小菱形（本作没有稀有度，用「精英阶段」0–2 代替原作的星）"""
    d = ImageDraw.Draw(img)
    x, y = xy
    for i in range(n):
        cx = x + i * (size + gap) + size / 2
        d.polygon([(cx, y), (cx + size / 2, y + size / 2), (cx, y + size), (cx - size / 2, y + size / 2)], fill=col)
    return n * (size + gap)


def ring(img, c, r, frac, col, width=3, track=(255, 255, 255, 30)):
    d = ImageDraw.Draw(img)
    x, y = c
    d.arc([x - r, y - r, x + r, y + r], 0, 360, fill=track, width=width)
    d.arc([x - r, y - r, x + r, y + r], -90, -90 + 360 * frac, fill=col, width=width)


def callout(img, xy, n, col=GOLD):
    """编号标注：金色圆 + 深色数字（只在概念图上，不进游戏）"""
    d = ImageDraw.Draw(img)
    x, y = xy
    r = 11
    d.ellipse([x - r - 1, y - r - 1, x + r + 1, y + r + 1], fill=(0, 0, 0, 255))
    d.ellipse([x - r, y - r, x + r, y + r], fill=col)
    f = ImageFont.truetype(K.FONT_UI, 14)
    d.text((x, y + 1), str(n), font=f, fill=(20, 16, 8), anchor="mm")


def big_button(img, box, s, col=CYAN, size=22, sub=None):
    """原作「开始行动」式的大按钮：右下斜切、实色底深字"""
    x0, y0, x1, y1 = box
    d = ImageDraw.Draw(img)
    d.polygon(cut_poly(x0, y0, x1, y1, 14, "tl br"), fill=col)
    d.polygon(cut_poly(x0 + 3, y0 + 3, x1 - 3, y1 - 3, 12, "tl br"), outline=(255, 255, 255, 110))
    f = F(size, s)
    d.text(((x0 + x1) / 2, (y0 + y1) / 2 - (6 if sub else 0)), s, font=f, fill=(8, 20, 24), anchor="mm", stroke_width=1, stroke_fill=(8, 20, 24))
    if sub:
        d.text(((x0 + x1) / 2, (y0 + y1) / 2 + 14), sub, font=F(10, sub), fill=(8, 20, 24), anchor="mm")


def backdrop(W, H, accent=CYAN):
    """深海底：上深下更深 + 右侧一团强调色雾 + 原作式斜向细条纹"""
    img = Image.new("RGBA", (W, H))
    d = ImageDraw.Draw(img)
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
    return img


def keyart(img, op, box, scale, fade=True, dim=1.0):
    """半身立绘：待机帧整数倍最近邻放大，底部向背景渐隐（原作立绘压在界面后面）"""
    f = frame(op["_tex"], 0)
    big = K.up(f, scale)
    if dim < 1.0:
        big = Image.blend(Image.new("RGBA", big.size, (0, 0, 0, 0)), big, dim)
    x0, y0, x1, y1 = box
    # 底部渐隐
    if fade:
        a = big.split()[3]
        mask = Image.new("L", big.size, 255)
        md = ImageDraw.Draw(mask)
        h = big.height
        for y in range(int(h * 0.72), h):
            v = int(255 * (1 - (y - h * 0.72) / (h * 0.28)))
            md.line([(0, y), (big.width, y)], fill=max(0, v))
        from PIL import ImageChops
        big.putalpha(ImageChops.multiply(a, mask))
    cx = (x0 + x1) // 2
    px, py = cx - big.width // 2, y1 - big.height
    col = CLASS_COL.get(op.get("class"), CYAN)
    K.put_glow(img, big, col, 10, 0.55, (px, py))
    img.alpha_composite(big, (px, py))
    return (px, py, px + big.width, py + big.height)


def op_card(img, box, op, selected=False, leader=False, dimmed=False, name_size=13, elite=0):
    """底部名册里的干员卡（原作：竖卡、左上职业、上方星级、底部名字条）"""
    x0, y0, x1, y1 = box
    col = CLASS_COL.get(op.get("class"), CYAN)
    fill = (8, 24, 30, 235) if selected else (6, 10, 16, 215)
    panel(img, box, fill=fill, edge=col + (255,) if selected else LINE, cut=8, corners="tr", accent=col if selected else None, accent_len=18)
    f = frame(op["_tex"], 0)
    k = max(1, int((y1 - y0 - 46) / f.height))
    k = min(k, 3)
    sp = K.up(f, k)
    if dimmed:
        sp = Image.blend(Image.new("RGBA", sp.size, (0, 0, 0, 0)), sp, 0.45)
    px = (x0 + x1) // 2 - sp.width // 2
    py = y1 - 26 - sp.height
    if selected:
        ov = layer(img)
        ImageDraw.Draw(ov).ellipse([px - 6, y1 - 40, px + sp.width + 6, y1 - 20], fill=col + (50,))
        img.alpha_composite(ov)
    img.alpha_composite(sp, (px, py))
    # 名字条
    d = ImageDraw.Draw(img)
    d.rectangle([x0 + 1, y1 - 22, x1 - 1, y1 - 1], fill=(0, 0, 0, 170))
    text(img, ((x0 + x1) // 2, y1 - 11), op["name"], name_size, TEXT if not dimmed else SUB, anchor="mm")
    # 左上职业图标 + 右上精英菱形
    glyph(img, (x0 + 12, y0 + 12), 6, CLASS_GLYPH.get(op.get("class"), "diamond"), col)
    star_row(img, (x1 - 8 - elite * 9, y0 + 7), elite, GOLD, 6, 3)
    if leader:
        d.rectangle([x0 + 1, y0 + 1, x0 + 40, y0 + 15], fill=VIOLET)
        text(img, (x0 + 5, y0 + 2), "主控", 10, (255, 255, 255))


def skill_row(img, xy, w, op, i, selected=False, manual=False, stage_lbl="招募", compact=False):
    """技能行（原作技能页：左图标 + 名字 / SP + 说明），本作：充能 SP + 解锁阶段 + 手动 / 自动"""
    sk = op["skills"][i]
    x, y = xy
    col = CLASS_COL.get(op.get("class"), CYAN)
    h = 46 if compact else 58
    panel(img, (x, y, x + w, y + h), fill=(14, 36, 42, 220) if selected else (6, 10, 16, 180), edge=col + (255,) if selected else LINE, cut=8, corners="tr")
    ic = icon(sk.get("icon", ""))
    side = 32 if not compact else 28
    if ic:
        img.alpha_composite(ic.resize((side, side), Image.NEAREST), (int(x + 10), int(y + (h - side) // 2)))
    d = ImageDraw.Draw(img)
    d.rectangle([x + 10, y + h - 12, x + 24, y + h - 2], fill=(0, 0, 0, 200))
    text(img, (x + 17, y + h - 7), "S%d" % (i + 1), 9, TEXT, anchor="mm")
    tx = x + 10 + side + 10
    text(img, (tx, y + 7), sk["name"], 15 if not compact else 13, TEXT)
    en(img, (tx + 2, y + (28 if not compact else 24)), sk.get("en", ""), 9, SUB, 1)
    # 右侧：SP 环 + 模式标签
    rx = x + w - 30
    ring(img, (rx, y + h // 2), 13, 0.72, GOLD if not manual else CYAN, 3)
    text(img, (rx, y + h // 2), "%d" % int(sk.get("sp", 0)), 11, TEXT, anchor="mm")
    text(img, (rx, y + h - 6), "SP", 7, SUB, anchor="mm")
    cx = rx - 24
    if manual:
        cx -= chip(img, (cx - 54, y + 8), "手动 Q", CYAN, 10, dark=False)
        text(img, (cx - 6, y + h - 16), "队友时自动", 9, SUB, anchor="ra")
    else:
        cx -= chip(img, (cx - 40, y + 8), "自动", SUB, 10)
    text(img, (rx - 24, y + h - 16 if not manual else y + h - 28), stage_lbl, 9, col, anchor="ra") if not manual else None
    return h


# ---------- 图 A：干员选择 ----------
def compose_select(W=1280, H=720, sel_id="skadi"):
    ops = roster()
    op = next(o for o in ops if o["_id"] == sel_id)
    col = CLASS_COL.get(op.get("class"), CYAN)
    img = backdrop(W, H, col)
    # ① 立绘（压在界面后面，右侧 1/3）
    keyart(img, op, (560, 40, 960, 580), 5)
    # ② 顶栏：标题条 + 右上灯火 / 难度 / 返回
    ov = layer(img)
    ImageDraw.Draw(ov).rectangle([0, 0, W, 54], fill=(0, 0, 0, 120))
    img.alpha_composite(ov)
    d = ImageDraw.Draw(img)
    d.line([(0, 54), (W, 54)], fill=LINE)
    d.polygon([(0, 0), (250, 0), (236, 54), (0, 54)], fill=col + (255,))
    en(img, (18, 8), "OPERATOR SELECT", 11, (10, 12, 16), 3)
    text(img, (18, 24), "选择开局干员", 20, (10, 12, 16))
    text(img, (262, 20), "主控 1 名；其余干员在探索中通过升级招募", 12, SUB)
    text(img, (262, 36), "下一步：选择难度", 11, SUB)
    chip(img, (W - 372, 18), "难度 Ⅳ 潮汐已涨", STEEL, 11)
    chip(img, (W - 250, 18), "封面干员 水月", PURPLE, 11)
    panel(img, (W - 120, 14, W - 16, 42), fill=(6, 10, 16, 200), edge=LINE, cut=6, corners="tr")
    text(img, (W - 68, 28), "返回  Esc", 12, TEXT, anchor="mm")
    # ③ 左侧职业筛选轨（原作左侧职业栏）
    panel(img, (14, 68, 58, 68 + 8 * 46 + 12), fill=(6, 10, 16, 190), edge=LINE, cut=8, corners="tr")
    for i, c in enumerate(["全部"] + CLASS_ORDER[:7]):
        cy = 68 + 14 + i * 46 + 14
        on = (c == op.get("class"))
        if on:
            d.rectangle([16, cy - 18, 56, cy + 18], fill=col + (60,))
            d.rectangle([16, cy - 18, 18, cy + 18], fill=col)
        if c == "全部":
            text(img, (36, cy), "全", 13, TEXT, anchor="mm")
        else:
            glyph(img, (36, cy - 4), 8, CLASS_GLYPH[c], CLASS_COL[c] if on else (200, 205, 210))
            text(img, (36, cy + 12), c, 9, CLASS_COL[c] if on else SUB, anchor="mm")
    # ④ 底部横向名册
    ry0 = H - 170
    ov = layer(img)
    ImageDraw.Draw(ov).rectangle([0, ry0 - 6, W, H], fill=(0, 0, 0, 150))
    img.alpha_composite(ov)
    d.line([(0, ry0 - 6), (W, ry0 - 6)], fill=LINE)
    en(img, (70, ry0 - 2), "ROSTER  13 / 13", 9, SUB, 2)
    text(img, (70 + 112, ry0 - 2), "排序：职业 ▼", 10, SUB)
    text(img, (W - 230, ry0 - 2), "◀ ▶ / 滚轮 切换    Enter 下一步", 10, SUB)
    cw, chh, gap = 82, 112, 8
    x = 70
    for o in ops[:10]:
        on = o["_id"] == sel_id
        box = (x, ry0 + 14 - (8 if on else 0), x + cw, ry0 + 14 + chh)
        op_card(img, box, o, selected=on, name_size=12, elite=(2 if on else 0))
        x += cw + gap
    text(img, (x + 6, ry0 + 70), "▶", 16, SUB)
    text(img, (x + 6, ry0 + 92), "还有 3 名", 10, SUB)
    # ⑤ 名字块（原作：大字名 + 英文 + 职业 / 子职业 + 标签）
    text(img, (90, 300), op["name"], 44, TEXT, bold=True)
    en(img, (94, 354), op.get("en", ""), 14, col, 4)
    cx = 92
    cx += chip(img, (cx, 378), op.get("class", ""), col, 12)
    for tg in op.get("gallery", {}).get("tags", []):
        cx += chip(img, (cx, 378), tg, PURPLE, 11)
    text(img, (92, 408), op.get("gallery", {}).get("desc", ""), 12, SUB)
    # ⑥ 右侧信息面板：页签 属性 / 技能 / 编队
    px0, py0, px1, py1 = 968, 68, W - 16, ry0 - 18
    panel(img, (px0, py0, px1, py1), fill=(6, 10, 16, 215), edge=LINE, cut=12, corners="tr", accent=col)
    tabs = ["属性", "技能", "编队"]
    tw = (px1 - px0) // 3
    for i, tname in enumerate(tabs):
        on = (i == 1)
        tx0 = px0 + i * tw
        if on:
            d.polygon([(tx0, py0), (tx0 + tw, py0), (tx0 + tw, py0 + 34), (tx0 + 8, py0 + 34), (tx0, py0 + 26)], fill=col + (255,))
        text(img, (tx0 + tw // 2, py0 + 17), tname, 14, (10, 12, 16) if on else SUB, anchor="mm", bold=on)
    d.line([(px0, py0 + 34), (px1, py0 + 34)], fill=LINE)
    # 属性缩略行（原作技能页顶端也带一行属性）
    y = py0 + 46
    base = op.get("base", {})
    stats = [("攻击", str(base.get("atk", "—"))), ("间隔", "%.2fs" % base.get("cd", 0)), ("射程", str(base.get("reach", "—"))), ("生命", "主控 100")]
    for i, (k, v) in enumerate(stats):
        sx = px0 + 14 + i * 72
        tab_head(img, (sx, y), k, (20, 90, 110) if i < 3 else (180, 120, 10), 9)
        text(img, (sx, y + 18), v, 13, TEXT)
    y += 46
    d.line([(px0 + 12, y), (px1 - 12, y)], fill=LINE)
    y += 10
    stages = ["招募", "精英一", "精英二"]
    for i in range(3):
        manual = (i == 2)
        y += skill_row(img, (px0 + 10, y), px1 - px0 - 20, op, i, selected=(i == 2), manual=manual, stage_lbl=stages[i]) + 8
    # 选中技能说明
    sk = op["skills"][2]
    desc = ("主控按 Q 释放；作为队友自动。" if manual else "") + sk.get("desc", "")
    lines = []
    f = F(11)
    cur = ""
    for ch in desc:
        if d.textlength(cur + ch, font=f) > (px1 - px0 - 28):
            lines.append(cur)
            cur = ch
        else:
            cur += ch
    lines.append(cur)
    for i, ln in enumerate(lines[:4]):
        text(img, (px0 + 14, y + 2 + i * 16), ln if i < 3 or len(lines) <= 4 else ln[:-1] + "…", 11, SUB)
    y += 4 + 16 * min(4, len(lines)) + 6
    # 天赋
    tl = op.get("talent", {})
    chip(img, (px0 + 14, y), "天赋", col, 10)
    text(img, (px0 + 60, y + 1), tl.get("name", "") + "  精英一解锁", 12, TEXT)
    # ⑦ 编队条（主控 + 两名队友位，队友探索中招募）
    sq0 = (92, 440)
    tab_head(img, sq0, "编队", (90, 70, 190), 9)
    for i in range(3):
        bx = sq0[0] + i * 94
        by = sq0[1] + 20
        if i == 0:
            panel(img, (bx, by, bx + 84, by + 56), fill=(10, 20, 30, 220), edge=VIOLET + (255,), cut=8, corners="tr")
            spr = K.up(frame(op["_tex"], 0), 1)
            img.alpha_composite(spr, (bx + 6, by + 56 - spr.height - 4))
            d.rectangle([bx + 1, by + 1, bx + 34, by + 15], fill=VIOLET)
            text(img, (bx + 5, by + 2), "主控", 10, (255, 255, 255))
            text(img, (bx + 66, by + 34), op["name"], 10, TEXT, anchor="mm")
        else:
            panel(img, (bx, by, bx + 84, by + 56), fill=(6, 10, 16, 160), edge=LINE, cut=8, corners="tr")
            text(img, (bx + 42, by + 22), "队友 %d" % i, 11, SUB, anchor="mm")
            text(img, (bx + 42, by + 40), "探索中招募", 9, SUB, anchor="mm")
    # ⑧ 右下大按钮（原作「开始行动」）
    big_button(img, (1030, ry0 + 36, W - 16, ry0 + 112), "出击  ›", CYAN, 24, "ENTER / 手柄 A  ·  下一步选择难度")
    # 标注编号
    callout(img, (238, 12), 1)
    callout(img, (36, 62), 2)
    callout(img, (62, ry0 + 8), 3)
    callout(img, (760, 100), 4)
    callout(img, (82, 284), 5)
    callout(img, (px0 - 8, py0 + 4), 6)
    callout(img, (80, 436), 7)
    callout(img, (1024, ry0 + 30), 8)
    foot(img, W, H, "概念图 A · 干员选择 · 1280×720 · 仅示意，不是游戏截图")
    return img


def foot(img, W, H, s):
    d = ImageDraw.Draw(img)
    d.rectangle([W - 400, H - 16, W, H], fill=(0, 0, 0, 200))
    text(img, (W - 6, H - 8), s, 9, SUB, anchor="rm")


# ---------- 图 B：干员图鉴 ----------
def compose_codex(W=1280, H=720, sel_id="wisadel"):
    ops = roster()
    op = next(o for o in ops if o["_id"] == sel_id)
    col = CLASS_COL.get(op.get("class"), CYAN)
    img = backdrop(W, H, col)
    d = ImageDraw.Draw(img)
    # ① 顶部图鉴大页签（干员 / 敌人 / 精英 / Boss / 道具 / 藏品 / 结局）
    ov = layer(img)
    ImageDraw.Draw(ov).rectangle([0, 0, W, 50], fill=(0, 0, 0, 130))
    img.alpha_composite(ov)
    d.line([(0, 50), (W, 50)], fill=LINE)
    en(img, (18, 8), "ARCHIVE", 11, col, 3)
    text(img, (18, 24), "图鉴", 18, TEXT)
    tabs = [("干员", "OPERATOR"), ("敌人", "ENEMY"), ("精英", "ELITE"), ("Boss", "BOSS"), ("道具", "ITEM"), ("藏品", "RELIC"), ("结局", "ENDING")]
    x = 110
    for i, (cn, e) in enumerate(tabs):
        on = (i == 0)
        w = 96
        if on:
            d.polygon([(x, 0), (x + w, 0), (x + w - 10, 50), (x, 50)], fill=col + (255,))
        text(img, (x + 12, 8), cn, 14, (10, 12, 16) if on else TEXT, bold=on)
        en(img, (x + 12, 30), e, 8, (10, 12, 16) if on else SUB, 1)
        x += w + 6
    text(img, (W - 150, 25), "已收录 13 / 13", 11, SUB, anchor="lm")
    panel(img, (W - 70, 12, W - 16, 38), fill=(6, 10, 16, 200), edge=LINE, cut=6, corners="tr")
    text(img, (W - 43, 25), "Esc", 11, TEXT, anchor="mm")
    # ② 左侧职业筛选轨 + 名册网格（原作干员列表：按职业筛选、竖卡网格）
    panel(img, (14, 64, 58, 64 + 8 * 44 + 10), fill=(6, 10, 16, 190), edge=LINE, cut=8, corners="tr")
    for i, c in enumerate(["全部"] + CLASS_ORDER[:7]):
        cy = 64 + 12 + i * 44 + 14
        on = (c == op.get("class"))
        if on:
            d.rectangle([16, cy - 18, 56, cy + 18], fill=col + (60,))
            d.rectangle([16, cy - 18, 18, cy + 18], fill=col)
        if c == "全部":
            text(img, (36, cy), "全", 13, TEXT, anchor="mm")
        else:
            glyph(img, (36, cy - 4), 8, CLASS_GLYPH[c], CLASS_COL[c] if on else (200, 205, 210))
            text(img, (36, cy + 12), c, 9, CLASS_COL[c] if on else SUB, anchor="mm")
    gx, gy = 70, 64
    panel(img, (gx, gy, gx + 4 * 92 + 10, gy + 28 + 4 * 118 + 26), fill=(4, 8, 12, 170), edge=LINE, cut=10, corners="tr")
    text(img, (gx + 4 * 92 // 2 + 8, gy + 28 + 4 * 118 + 10), "滚轮 / 上滑翻页", 10, SUB, anchor="mm")
    en(img, (gx + 10, gy + 8), "OPERATORS", 9, SUB, 2)
    text(img, (gx + 10 + 70, gy + 7), "按职业 ▼   13 名", 10, SUB)
    for i, o in enumerate(ops):
        cx = gx + 8 + (i % 4) * 92
        cy = gy + 28 + (i // 4) * 118
        on = o["_id"] == sel_id
        op_card(img, (cx, cy, cx + 84, cy + 110), o, selected=on, name_size=12, elite=[2, 1, 2, 0, 1, 2, 2, 1, 0, 2, 1, 2, 2][i % 13])
    # 第 4 行只有一张，补一个「？」待解锁示意
    cx = gx + 8 + 1 * 92
    cy = gy + 28 + 3 * 118
    panel(img, (cx, cy, cx + 84, cy + 110), fill=(6, 10, 16, 140), edge=LINE, cut=8, corners="tr")
    text(img, (cx + 42, cy + 50), "?", 28, SUB, anchor="mm")
    text(img, (cx + 42, cy + 96), "未解锁", 11, SUB, anchor="mm")
    # ③ 立绘 + 名字块
    keyart(img, op, (480, 54, 870, 436), 4)
    text(img, (470, 440), op["name"], 44, TEXT, bold=True)
    en(img, (474, 494), op.get("en", ""), 14, col, 4)
    cx = 472
    cx += chip(img, (cx, 518), op.get("class", ""), col, 12)
    for tg in op.get("gallery", {}).get("tags", []):
        cx += chip(img, (cx, 518), tg, PURPLE, 11)
    # 档案小表（原作档案页的「性别 / 出身地 / 种族 / 所属」）
    lore = json.load(open(os.path.join(ROOT, "game", "data", "lore.json"), encoding="utf-8")).get(sel_id, {})
    prof = lore.get("profile", {}) if isinstance(lore, dict) else {}
    y = 548
    for k, v in list(prof.items())[:4]:
        text(img, (472, y), k, 11, SUB)
        text(img, (536, y), str(v), 11, TEXT)
        y += 17
    # 形态 / 演示切换（现图鉴已有：待机 / 移动 / 攻击 / 技能 演示）
    fy = 626
    for i, fm in enumerate(["待机", "移动", "攻击", "技能", "精二"]):
        fx = 472 + i * 58
        on = (i == 0)
        panel(img, (fx, fy, fx + 52, fy + 24), fill=col + (255,) if on else (6, 10, 16, 190), edge=col + (255,) if on else LINE, cut=6, corners="tr")
        text(img, (fx + 26, fy + 12), fm, 11, (10, 12, 16) if on else TEXT, anchor="mm")
    text(img, (472, 660), "点卡片切换演示动作（现有图鉴功能保留）", 10, SUB)
    # ④ 右侧信息面板：档案 / 技能 / 成长 / 藏品契合 / 战绩
    px0, py0, px1, py1 = 880, 64, W - 16, H - 16
    panel(img, (px0, py0, px1, py1), fill=(6, 10, 16, 215), edge=LINE, cut=12, corners="tr", accent=col)
    tabs = ["档案", "技能", "成长", "藏品契合", "战绩"]
    tw = (px1 - px0) // 5
    for i, tname in enumerate(tabs):
        on = (i == 2)
        tx0 = px0 + i * tw
        if on:
            d.polygon([(tx0, py0), (tx0 + tw, py0), (tx0 + tw, py0 + 34), (tx0 + 8, py0 + 34), (tx0, py0 + 26)], fill=col + (255,))
        text(img, (tx0 + tw // 2, py0 + 17), tname, 13, (10, 12, 16) if on else SUB, anchor="mm", bold=on)
    d.line([(px0, py0 + 34), (px1, py0 + 34)], fill=LINE)
    # ⑤ 成长页：节点时间线（招募 → 自定义节点 → 精英一 → … → 精英二），节点图标用 growth_* / 技能图标
    y = py0 + 48
    en(img, (px0 + 14, y), "GROWTH PATH", 9, col, 2)
    text(img, (px0 + 110, y - 1), "局内升级时按此顺序出现成长卡", 10, SUB)
    y += 22
    nodes = op.get("progression", [])
    lx = px0 + 30
    d.line([(lx, y + 8), (lx, y + 8 + 50 * len(nodes))], fill=LINE, width=2)
    gicons = ["growth_hp", "growth_armor", "growth_dodge", "growth_pickup", "growth_b_range", "growth_b_count"]
    for i, n in enumerate(nodes[:7]):
        ny = y + i * 50
        is_elite = n.get("type") == "elite"
        ncol = GOLD if is_elite else col
        d.ellipse([lx - 7, ny + 1, lx + 7, ny + 15], fill=ncol if i < 3 else (20, 26, 34), outline=ncol, width=2)
        ic = icon(n.get("icon", "")) or icon(("skill_%s_s%d" % (sel_id, min(3, i // 2 + 1))) if is_elite else gicons[i % len(gicons)])
        bx = lx + 18
        panel(img, (bx, ny - 6, px1 - 14, ny + 36), fill=(14, 36, 42, 200) if i < 3 else (6, 10, 16, 150), edge=ncol + (255,) if is_elite else LINE, cut=8, corners="tr")
        if ic:
            img.alpha_composite(ic.resize((28, 28), Image.NEAREST), (bx + 8, ny + 1))
        text(img, (bx + 44, ny - 2), n.get("name", ""), 13, TEXT)
        sub = ("精英化 · 解锁 S%d / 天赋" % (2 if n.get("level") == 1 else 3)) if is_elite else "成长节点 · 本局已取" if i < 3 else "成长节点 · 未取"
        text(img, (bx + 44, ny + 16), sub, 10, GOLD if is_elite else SUB)
        if i < 3:
            star_row(img, (px1 - 30, ny + 10), 1, GREEN, 8)
    y += 50 * min(7, len(nodes)) + 6
    d.line([(px0 + 12, y), (px1 - 12, y)], fill=LINE)
    # ⑥ 藏品契合（缩略）：与该干员伤害来源相配的藏品（affects.gd 口径）
    y += 10
    tab_head(img, (px0 + 14, y), "藏品契合", (90, 70, 190), 9)
    text(img, (px0 + 80, y + 1), "按 hit_sources 推算 · 远程 / 物理 / 范围", 9, SUB)
    y += 22
    for i, rid in enumerate(["relic_10", "relic_11", "relic_13", "relic_18", "relic_2"]):
        ic = icon(rid)
        bx = px0 + 14 + i * 40
        panel(img, (bx, y, bx + 34, y + 34), fill=(6, 10, 16, 200), edge=GOLD + (255,) if i < 2 else LINE, cut=6, corners="tr")
        if ic:
            img.alpha_composite(ic.resize((28, 28), Image.NEAREST), (bx + 3, y + 3))
    text(img, (px0 + 14 + 5 * 40 + 6, y + 10), "+12 件", 11, SUB)
    y += 44
    # ⑦ 战绩（缩略）
    tab_head(img, (px0 + 14, y), "战绩", (180, 120, 10), 9)
    y += 20
    for i, (k, v) in enumerate([("出击", "27 局"), ("通关", "9 次"), ("最佳", "18:42"), ("最高档", "第 8 档")]):
        sx = px0 + 14 + i * 88
        text(img, (sx, y), k, 10, SUB)
        text(img, (sx, y + 14), v, 15, TEXT, bold=True)
    callout(img, (104, 44), 1)
    callout(img, (36, 58), 2)
    callout(img, (gx + 4 * 92 + 6, gy + 4), 2)
    callout(img, (462, 424), 3)
    callout(img, (px0 - 8, py0 + 4), 4)
    callout(img, (px0 + 6, py0 + 46), 5)
    callout(img, (px1 - 20, y - 70), 6)
    callout(img, (px1 - 20, y - 6), 7)
    callout(img, (462, 622), 8)
    foot(img, W, H, "概念图 B · 干员图鉴 · 1280×720 · 仅示意，不是游戏截图")
    return img


# ---------- 图 C：手机（触屏）版式 ----------
def compose_phone(W=740, H=360, sel_id="skadi"):
    ops = roster()
    op = next(o for o in ops if o["_id"] == sel_id)
    col = CLASS_COL.get(op.get("class"), CYAN)
    img = backdrop(W, H, col)
    d = ImageDraw.Draw(img)
    keyart(img, op, (330, 10, 490, 300), 3)
    d.polygon([(0, 0), (150, 0), (140, 34), (0, 34)], fill=col + (255,))
    text(img, (10, 9), "选择开局干员", 15, (10, 12, 16), bold=True)
    panel(img, (W - 70, 6, W - 8, 28), fill=(6, 10, 16, 200), edge=LINE, cut=6, corners="tr")
    text(img, (W - 39, 17), "返回", 11, TEXT, anchor="mm")
    # 左侧竖向名册（触屏：拇指区在两侧，名册放左、按钮放右）
    panel(img, (8, 40, 150, H - 8), fill=(4, 8, 12, 180), edge=LINE, cut=8, corners="tr")
    for i, o in enumerate(ops[:6]):
        cx = 14 + (i % 2) * 68
        cy = 48 + (i // 2) * 94
        on = o["_id"] == sel_id
        op_card(img, (cx, cy, cx + 62, cy + 88), o, selected=on, name_size=11)
    text(img, (79, H - 16), "▼ 上滑还有 7 名", 9, SUB, anchor="mm")
    # 名字块
    text(img, (162, 196), op["name"], 30, TEXT, bold=True)
    en(img, (164, 232), op.get("en", ""), 11, col, 3)
    cx = 162
    cx += chip(img, (cx, 250), op.get("class", ""), col, 11)
    for tg in op.get("gallery", {}).get("tags", [])[:2]:
        cx += chip(img, (cx, 250), tg, PURPLE, 10)
    # 右侧面板：页签 + 技能三行（紧凑）
    px0, py0, px1, py1 = 470, 40, W - 8, H - 72
    panel(img, (px0, py0, px1, py1), fill=(6, 10, 16, 215), edge=LINE, cut=10, corners="tr", accent=col)
    tw = (px1 - px0) // 3
    for i, tname in enumerate(["属性", "技能", "编队"]):
        on = (i == 1)
        tx0 = px0 + i * tw
        if on:
            d.polygon([(tx0, py0), (tx0 + tw, py0), (tx0 + tw, py0 + 26), (tx0 + 6, py0 + 26), (tx0, py0 + 20)], fill=col + (255,))
        text(img, (tx0 + tw // 2, py0 + 13), tname, 12, (10, 12, 16) if on else SUB, anchor="mm", bold=on)
    y = py0 + 34
    for i in range(3):
        y += skill_row(img, (px0 + 8, y), px1 - px0 - 16, op, i, selected=(i == 2), manual=(i == 2), stage_lbl=["招募", "精英一", "精英二"][i], compact=True) + 6
    text(img, (px0 + 10, y + 2), "点技能行看说明 · 主控 S3 点技能键释放", 9, SUB)
    big_button(img, (W - 190, H - 64, W - 8, H - 10), "出击  ›", CYAN, 18)
    text(img, (162, H - 44), "编队：主控 + 2 名队友（探索中招募）", 10, SUB)
    callout(img, (150, 44), 1)
    callout(img, (px0 - 6, py0 + 2), 2)
    callout(img, (W - 196, H - 68), 3)
    foot(img, W, H, "概念图 C · 手机触屏 · 740×360 · 仅示意")
    return img


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 and not sys.argv[1].startswith("--") else os.path.join(ROOT, "build", "concept", "operator_ui")
    os.makedirs(out, exist_ok=True)
    compose_select().convert("RGB").save(os.path.join(out, "concept_op_select.png"))
    compose_codex().convert("RGB").save(os.path.join(out, "concept_op_codex.png"))
    compose_phone().convert("RGB").save(os.path.join(out, "concept_op_select_phone.png"))
    print("写入", out)
