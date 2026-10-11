# -*- coding: utf-8 -*-
"""标题页 T5「自有风格」概念图（docs/67 §11，2026-10-12 用户：「能不能在T4B的基础上设计出我们自己的风格」）。

只是给人看的概念图，不改游戏代码。保留 T4b 的骨架（右侧大小分级磁贴群、沙滩上放大的封面干员、四角信息），
把从原作借来的外观（警示黄、平行四边形、警示斜纹、罗德岛式折角、平滑磨砂）换成本作自己的视觉语言：

  颜色：选中 = 灯火琥珀（全屏唯一的暖色）+ 像素光晕；其余深海藏青 / 青；
  形状：像素阶梯切角；磁贴底部一条潮线，选中的那块水位上涨 + 水面涟漪；
  质感：Bayer 有序抖动的 2–3 阶藏青渐变（不用平滑模糊玻璃）；
  字体：编号 / 英文 / 难度数字用 5×7 像素字（这里现画的位图字，仓库 game/fonts 里没有像素字体），中文仍用粗体 ui.ttf；
  图标：16×16 像素图标，最近邻放大；
  生物：磁贴之间漂两只水母 + 几点生物荧光；
  命名：档案条 → 灯火日志（已解锁干员 / 最高潮位 / 总局数）；更新横幅 → 漂流瓶便笺。

  - T5a：以上全部，适中；
  - T5b：加强版：磁贴做成潮位尺 / 声呐面板（左缘刻度、声呐弧、顶部标签页），抖动更粗，灯火光更强；
  - T5c：克制版：只换切角 + 琥珀 + 像素字，保留 T4b 的平滑深色磨砂与线条图标；
  - T5a 选中「图鉴」、T5a 手机 740×360、T5a 难度内页（潮位尺选档）。

底图、人物站位、Logo 复用 tools/concept_title_ui_v3.py（T4b）。

用法：
    python tools/concept_title_ui_v4.py

输出（不入库）：主仓库 build/title_redesign/v4/
    contact_sheet_v4.png                     总览（先看这张）：T4b / T5a / T5b / T5c + 变体 + 手机
    title_T5a.png / title_T5b.png / title_T5c.png
    title_T5a_sel2.png / title_T5a_phone.png / diff_T5a.png
"""
import math, os, random, sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

TOOLS = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, TOOLS)
import concept_title_ui as c1  # noqa: E402
import concept_title_ui_v3 as c3  # noqa: E402
from concept_title_ui import W, H, PW, PH, over, logo, contact_sheet  # noqa: E402
from concept_title_ui_v2 import NAVY, CY, CY_DIM, TXT, TXT2, text  # noqa: E402

OUT4 = os.path.join(c1.OUT, "v4")

# ---------------------------------------------------------------- 色板（概念令牌）
AMBER = (255, 176, 64)        # 灯火琥珀：选中 / 灯，全屏唯一的暖色
AMBER_HI = (255, 222, 150)
AMBER_TONES = [(255, 204, 112), (246, 170, 66), (222, 134, 44)]     # 选中磁贴抖动：上亮下深
INK_D = (8, 20, 38)           # 琥珀上的深墨
N_TONES = [(18, 40, 68), (11, 26, 48), (6, 14, 30)]                 # 藏青三阶：上浅下深
N_TONES_B = [(26, 56, 88), (14, 32, 58), (6, 14, 30)]               # T5b：对比更强
WATER = [(30, 92, 116), (18, 62, 88), (10, 38, 62)]                 # 潮水三阶
FOAM = (176, 246, 242)
EDGE = (44, 98, 124)          # 磁贴阶梯描边
JELLY = (120, 220, 236)

BAYER = (np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]) + 0.5) / 16.0

# ---------------------------------------------------------------- 5×7 像素字（现画；编号、英文、难度数字用）
_G = {
    "A": "0E 11 11 1F 11 11 11", "B": "1E 11 11 1E 11 11 1E", "C": "0E 11 10 10 10 11 0E", "D": "1E 11 11 11 11 11 1E",
    "E": "1F 10 10 1E 10 10 1F", "F": "1F 10 10 1E 10 10 10", "G": "0E 11 10 17 11 11 0F", "H": "11 11 11 1F 11 11 11",
    "I": "0E 04 04 04 04 04 0E", "J": "07 02 02 02 02 12 0C", "K": "11 12 14 18 14 12 11", "L": "10 10 10 10 10 10 1F",
    "M": "11 1B 15 15 11 11 11", "N": "11 11 19 15 13 11 11", "O": "0E 11 11 11 11 11 0E", "P": "1E 11 11 1E 10 10 10",
    "Q": "0E 11 11 11 15 12 0D", "R": "1E 11 11 1E 14 12 11", "S": "0F 10 10 0E 01 01 1E", "T": "1F 04 04 04 04 04 04",
    "U": "11 11 11 11 11 11 0E", "V": "11 11 11 11 11 0A 04", "W": "11 11 11 15 15 15 0A", "X": "11 11 0A 04 0A 11 11",
    "Y": "11 11 11 0A 04 04 04", "Z": "1F 01 02 04 08 10 1F",
    "0": "0E 11 13 15 19 11 0E", "1": "04 0C 04 04 04 04 0E", "2": "0E 11 01 02 04 08 1F", "3": "1F 02 04 02 01 11 0E",
    "4": "02 06 0A 12 1F 02 02", "5": "1F 10 1E 01 01 11 0E", "6": "06 08 10 1E 11 11 0E", "7": "1F 01 02 04 08 08 08",
    "8": "0E 11 11 0E 11 11 0E", "9": "0E 11 11 0F 01 02 0C",
    "/": "01 01 02 04 08 10 10", ".": "00 00 00 00 00 0C 0C", ":": "00 0C 0C 00 0C 0C 00", "-": "00 00 00 1F 00 00 00",
    "+": "00 04 04 1F 04 04 00", "%": "18 19 02 04 08 13 03", ">": "08 04 02 01 02 04 08", "<": "02 04 08 10 08 04 02",
    "#": "0A 0A 1F 0A 1F 0A 0A", "↑": "04 0E 15 04 04 04 04", "↓": "04 04 04 04 15 0E 04", "←": "00 04 08 1F 08 04 00",
    "→": "00 04 02 1F 02 04 00", "·": "00 00 00 0C 0C 00 00", "x": "00 00 11 0A 04 0A 11",
}
GLYPH = {k: [int(h, 16) for h in v.split()] for k, v in _G.items()}


def ps(n, s):
    """像素字倍数随布局缩放取整（手机 0.62 倍时 2→1、3→2）"""
    return max(1, int(round(n * s)))


def ptxt(img, xy, s, sc=1, col=TXT, track=1, anchor="lm"):
    """像素字：每个字 5×7 格，sc 倍整数放大，字距 track 格；anchor 同 PIL 的两字母（l/m/r + t/m/b）"""
    sc = max(1, int(sc))
    s = s.upper()
    adv = lambda ch: ((3 if ch == " " else 5) + 1 + track) * sc  # noqa: E731
    w = sum(adv(ch) for ch in s) - (1 + track) * sc
    x, y = xy
    if anchor[0] == "m":
        x -= w / 2
    elif anchor[0] == "r":
        x -= w
    if anchor[1] == "m":
        y -= 7 * sc / 2
    elif anchor[1] == "b":
        y -= 7 * sc
    x, y = int(round(x)), int(round(y))
    d = ImageDraw.Draw(img)
    for ch in s:
        rows = GLYPH.get(ch)
        if rows:
            for r, bits in enumerate(rows):
                for c in range(5):
                    if bits & (1 << (4 - c)):
                        d.rectangle([x + c * sc, y + r * sc, x + c * sc + sc - 1, y + r * sc + sc - 1], fill=col)
        x += adv(ch)
    return w


# ---------------------------------------------------------------- 16×16 像素图标（索引色画在小画布上，最近邻放大）
def _icon16(kind):
    im = Image.new("L", (16, 16), 0)
    d = ImageDraw.Draw(im)
    if kind == "deploy":
        for i in range(3):
            x = 2 + i * 4
            for t in (0, 1):
                d.line([(x + t, 3), (x + 4 + t, 7), (x + 4 + t, 8), (x + t, 12)], fill=1)
    elif kind == "gallery":
        d.rectangle([1, 3, 14, 12], outline=1)
        d.line([(7, 3), (7, 12)], fill=1)
        d.line([(8, 3), (8, 12)], fill=1)
        for yy in (5, 7, 9):
            d.line([(3, yy), (5, yy)], fill=2)
            d.line([(10, yy), (12, yy)], fill=2)
    elif kind == "boss":
        d.ellipse([2, 2, 13, 13], outline=1)
        for a, b in (((7, 0), (7, 4)), ((8, 0), (8, 4)), ((7, 11), (7, 15)), ((8, 11), (8, 15)),
                     ((0, 7), (4, 7)), ((0, 8), (4, 8)), ((11, 7), (15, 7)), ((11, 8), (15, 8))):
            d.line([a, b], fill=1)
        d.rectangle([7, 7, 8, 8], fill=2)
    elif kind == "guide":
        d.rectangle([2, 5, 13, 11], outline=1)
        d.line([(1, 6), (1, 12)], fill=1)
        d.line([(14, 6), (14, 12)], fill=1)
        d.line([(3, 7), (3, 9)], fill=0)
        d.line([(4, 8), (6, 8)], fill=2)
        d.line([(5, 7), (5, 9)], fill=2)
        d.point([(10, 7), (12, 9)], fill=2)
    elif kind == "settings":
        d.ellipse([3, 3, 12, 12], outline=1)
        for r in ((7, 1, 8, 2), (7, 13, 8, 14), (1, 7, 2, 8), (13, 7, 14, 8), (3, 3, 4, 4), (11, 3, 12, 4), (3, 11, 4, 12), (11, 11, 12, 12)):
            d.rectangle(r, fill=1)
        d.rectangle([6, 6, 9, 9], outline=2)
    elif kind == "exit":
        d.line([(9, 2), (2, 2), (2, 13), (9, 13)], fill=1)
        d.line([(9, 2), (9, 4)], fill=1)
        d.line([(9, 11), (9, 13)], fill=1)
        d.rectangle([6, 7, 13, 8], fill=2)
        d.line([(11, 5), (14, 8)], fill=2)
        d.line([(11, 10), (14, 7)], fill=2)
    elif kind == "info":
        d.ellipse([1, 1, 14, 14], outline=1)
        d.rectangle([7, 6, 8, 11], fill=2)
        d.rectangle([7, 3, 8, 4], fill=2)
    elif kind == "full":
        for sx, sy in ((1, 1), (14, 1), (1, 14), (14, 14)):
            dx, dy = (1 if sx == 1 else -1), (1 if sy == 1 else -1)
            d.line([(sx, sy), (sx + dx * 4, sy)], fill=1)
            d.line([(sx, sy), (sx, sy + dy * 4)], fill=1)
    elif kind == "lamp":       # 灯：吊环、灯罩、玻璃、火苗、底座
        d.rectangle([7, 0, 8, 0], fill=1)
        d.rectangle([6, 1, 9, 1], fill=1)
        d.rectangle([4, 2, 11, 3], fill=1)
        d.rectangle([5, 4, 10, 11], outline=1)
        d.rectangle([6, 5, 9, 10], fill=4)
        d.rectangle([7, 6, 8, 10], fill=2)
        d.rectangle([6, 8, 9, 10], fill=2)
        d.rectangle([7, 8, 8, 9], fill=3)
        d.rectangle([4, 12, 11, 13], fill=1)
    elif kind == "bottle":     # 漂流瓶：瓶身、纸卷、瓶颈、软木塞
        d.rectangle([1, 5, 10, 11], outline=1)
        d.point([(1, 5), (1, 11)], fill=0)
        d.rectangle([3, 7, 8, 9], fill=2)
        d.rectangle([11, 7, 13, 9], outline=1)
        d.rectangle([14, 7, 15, 9], fill=3)
        d.point([(2, 6), (3, 6)], fill=4)
    return im


def picon(kind, k, pal):
    """pal：索引 → RGBA；返回放大 k 倍的 RGBA 图标"""
    src = np.array(_icon16(kind))
    out = np.zeros((16, 16, 4), np.uint8)
    for idx, col in pal.items():
        c = col if len(col) == 4 else col + (255,)
        out[src == idx] = c
    return Image.fromarray(out, "RGBA").resize((16 * k, 16 * k), Image.NEAREST)


def put_icon(img, kind, cx, cy, k, col, col2=None):
    ic = picon(kind, k, {1: col, 2: col2 or col})
    img.alpha_composite(ic, (int(cx - 8 * k), int(cy - 8 * k)))


def lamp_icon(k):
    return picon("lamp", k, {1: (176, 196, 210), 2: AMBER, 3: (255, 248, 220), 4: (120, 70, 30)})


JELLY_SPR = [
    "....####....",
    "..########..",
    ".##++######.",
    ".#++#######.",
    "############",
    "#.#.#..#.#.#",
    ".:..:..:..:.",
    ".:..:..:..:.",
    "..:..::..:..",
    "..:...:..:..",
    ".:....:...:.",
    ".:...:....:.",
]


def jelly(img, x, y, k, a=1.0, col=JELLY):
    """像素水母 + 一圈像素化的柔光"""
    pal = {"#": col + (int(190 * a),), "+": (230, 255, 255, int(255 * a)), ":": (90, 180, 220, int(140 * a))}
    sp = Image.new("RGBA", (14, 14), (0, 0, 0, 0))
    body = np.zeros((14, 14), bool)
    for r, row in enumerate(JELLY_SPR):
        for c, ch in enumerate(row):
            if ch in pal:
                sp.putpixel((c + 1, r + 1), pal[ch])
                body[r + 1, c + 1] = ch != ":"
    # 伞盖一圈 1 格深色描边，压在亮背景（巨树倒影）上也认得出
    ring = np.zeros_like(body)
    for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        ring |= np.roll(np.roll(body, dy, 0), dx, 1)
    ring &= ~body
    for r, c in zip(*np.nonzero(ring)):
        if sp.getpixel((int(c), int(r)))[3] == 0:
            sp.putpixel((int(c), int(r)), (4, 12, 30, int(200 * a)))
    sp = sp.resize((14 * k, 14 * k), Image.NEAREST)
    g = Image.new("L", img.size, 0)
    ImageDraw.Draw(g).ellipse([x - 2 * k, y - 2 * k, x + 16 * k, y + 10 * k], fill=255)
    glow(img, g, col, k * 3, (0.1, 0.35, 0.7), tuple(int(v * a) for v in (34, 60, 90)), cell=k * 2)
    img.alpha_composite(sp, (int(x - k), int(y - k)))


def motes(img, pts, k, col=JELLY):
    d = ImageDraw.Draw(img)
    for (x, y, b) in pts:
        if b:
            over(img, lambda dd: dd.rectangle([x - k, y - k, x + 2 * k - 1, y + 2 * k - 1], fill=col + (60,)))
        d.rectangle([x, y, x + k - 1, y + k - 1], fill=(200, 255, 255))


# ---------------------------------------------------------------- 阶梯切角 / 抖动 / 光晕
def snap(v, P):
    return int(round(v / P)) * P


def stair(w, h, P, n, tab=None):
    """阶梯切角形状（bool h×w）：四角各 n 级、每级 P 像素；tab=(tw, th) 在左上方伸出一个标签页"""
    m = np.ones((h, w), bool)
    for k in range(n):
        ins = (n - k) * P
        for ys in (slice(k * P, (k + 1) * P), slice(h - (k + 1) * P, h - k * P)):
            m[ys, :ins] = False
            m[ys, w - ins:] = False
    return m


def edge_of(m, P):
    e = m.copy()
    for dy, dx in ((P, 0), (-P, 0), (0, P), (0, -P)):
        sh = np.zeros_like(m)
        ys = slice(max(dy, 0), m.shape[0] + min(dy, 0))
        yd = slice(max(-dy, 0), m.shape[0] + min(-dy, 0))
        xs = slice(max(dx, 0), m.shape[1] + min(dx, 0))
        xd = slice(max(-dx, 0), m.shape[1] + min(-dx, 0))
        sh[ys, xs] = m[yd, xd]
        e &= sh
    return m & ~e


def dith(x0, y0, w, h, P, vfun):
    """返回每个像素的抖动档位（int h×w）：vfun(cx, cy) 在格心取值（0..len-1，可为小数），Bayer 4×4 定阈"""
    ys, xs = np.mgrid[0:h, 0:w]
    gx, gy = (xs + x0) // P, (ys + y0) // P
    cx, cy = gx * P + P / 2 - x0, gy * P + P / 2 - y0
    v = vfun(cx, cy)
    thr = BAYER[gy % 4, gx % 4]
    return (np.floor(v) + ((v - np.floor(v)) > thr)).astype(int)


def paint(img, x0, y0, m, lv, tones, a=255):
    h, w = m.shape
    arr = np.zeros((h, w, 4), np.uint8)
    lv = np.clip(lv, 0, len(tones) - 1)
    for i, t in enumerate(tones):
        sel = m & (lv == i)
        arr[sel] = t + (a,) if len(t) == 3 else t
    img.alpha_composite(Image.fromarray(arr, "RGBA"), (x0, y0))


def solid(img, x0, y0, m, col):
    h, w = m.shape
    arr = np.zeros((h, w, 4), np.uint8)
    arr[m] = col + (255,) if len(col) == 3 else col
    img.alpha_composite(Image.fromarray(arr, "RGBA"), (x0, y0))


def glow(img, mask, col, rad, steps=(0.1, 0.3, 0.6), alphas=(40, 80, 120), cell=4):
    """像素光晕：模糊后按几档台阶量化，再按 cell 像素块化（看起来是一圈圈像素光而不是平滑辉光）"""
    b = mask.filter(ImageFilter.GaussianBlur(rad))
    a = np.array(b, float) / 255.0
    out = np.zeros(a.shape, np.uint8)
    for st, al in zip(steps, alphas):
        out[a > st] = al
    q = Image.fromarray(out, "L")
    q = q.resize((max(1, img.width // cell), max(1, img.height // cell)), Image.NEAREST).resize(img.size, Image.NEAREST)
    lay = Image.new("RGBA", img.size, col + (0,))
    lay.putalpha(q)
    img.alpha_composite(lay)


# ---------------------------------------------------------------- 一块磁贴的底（阶梯切角 + 抖动 / 磨砂 + 潮线）
def tile_base(img, box, sel, V, size, s=1.0):
    P = V["P"]
    x0, y0, x1, y1 = [snap(v, P) for v in box]
    w, h = x1 - x0, y1 - y0
    n = V["n"] if size != "small" else max(2, V["n"] - 1)
    m = stair(w, h, P, n)
    # 选中：琥珀像素光晕（先画，在磁贴底下）
    if sel:
        gm = Image.new("L", img.size, 0)
        gm.paste(Image.fromarray((m * 255).astype(np.uint8), "L"), (x0, y0))
        if V["smooth"]:
            b = gm.filter(ImageFilter.GaussianBlur(10 * s))
            lay = Image.new("RGBA", img.size, AMBER + (0,))
            lay.putalpha(b.point(lambda v: int(v * 0.6)))
            img.alpha_composite(lay)
        else:
            glow(img, gm, AMBER, V["glow_r"] * s, V["glow_steps"], V["glow_a"], cell=P * 2)
    if V["smooth"]:
        # T5c：保留 T4b 的平滑深色磨砂，只是外形换成阶梯切角
        mk = Image.fromarray((m * 255).astype(np.uint8), "L")
        full = Image.new("L", img.size, 0)
        full.paste(mk, (x0, y0))
        img.paste(img.filter(ImageFilter.GaussianBlur(8 * s)), (0, 0), full)
        if sel:
            solid(img, x0, y0, m, AMBER)
        else:
            solid(img, x0, y0, m, (12, 24, 44, 196))
    else:
        tones = AMBER_TONES if sel else V["tones"]
        nt = len(tones) - 1
        lv = dith(x0, y0, w, h, V["dP"], lambda cx, cy: np.clip((cy / h * 0.8 + cx / w * 0.2) * nt * 1.15 - 0.05, 0, nt))
        paint(img, x0, y0, m, lv, tones, 255 if sel else V["alpha"])
    # 潮线：底部一条像素波浪，选中的那块水位上涨
    crest = None
    if V["tide"]:
        frac = V["tide_sel"][size] if sel else V["tide_rest"][size]
        base = h - max(3 * P, snap(h * frac, P))
        ys, xs = np.mgrid[0:h, 0:w]
        gx = (xs + x0) // P
        wave = (np.round(np.sin(gx * 0.45 + y0 * 0.1) * 0.8 + np.sin(gx * 0.17 + 1.3) * 0.6) * P).astype(int)
        wy = base + wave
        wm = m & (ys >= wy)
        depth = (ys - wy) / max(1.0, h - base)
        wl = dith(x0, y0, w, h, V["dP"], lambda cx, cy: np.clip((cy - base) / max(1.0, h - base) * 2.4, 0, 2))
        wl[~wm] = -1
        paint(img, x0, y0, wm, wl, WATER, 236)
        # 浪尖：顶一排浅色像素，隔几格断开（泡沫）
        top = wm & ~np.roll(wm, P, axis=0) & (depth < P / max(1.0, h - base) + 1e-6)
        foam = top & (((gx * 7) % 11) > 1)
        solid(img, x0, y0, foam, FOAM + ((230 if sel else 150),))
        crest = y0 + base
    # 阶梯描边
    e = edge_of(m, P if not V["smooth"] else 1)
    if sel:
        solid(img, x0, y0, e, AMBER_HI)
    else:
        solid(img, x0, y0, e, EDGE + (200,))
        # 左上角一小段亮青，代替原来的罗德岛折角
        tl = e.copy()
        tl[snap(h * 0.28, P):, :] = False
        tl[:, snap(w * 0.18, P):] = False
        solid(img, x0, y0, tl, CY)
    return (x0, y0, x1, y1), m, crest


def ripple(img, cx, cy, P, k, tile_m, tile_xy, col=FOAM):
    """水面涟漪：三圈压扁的像素椭圆，越外越淡、断续"""
    x0, y0 = tile_xy
    h, w = tile_m.shape
    lay = np.zeros((h, w, 4), np.uint8)
    for j, r in enumerate((12 * k, 24 * k, 38 * k)):
        al = (220, 150, 80)[j]
        for t in range(0, 360, 4):
            if (t // 20 + j) % 4 == 3:
                continue
            a = math.radians(t)
            px, py = snap(cx + math.cos(a) * r - x0, P), snap(cy + math.sin(a) * r * 0.28 - y0, P)
            if 0 <= px < w - P and 0 <= py < h - P and tile_m[py, px]:
                lay[py:py + P, px:px + P] = col + (al,)
    img.alpha_composite(Image.fromarray(lay, "RGBA"), (x0, y0))


def sonar(img, box, m, cx, cy, P, col=(120, 220, 236), a=46, step=22):
    """T5b：声呐弧（点状像素同心弧），剪在磁贴形状里"""
    x0, y0, x1, y1 = box
    h, w = m.shape
    lay = np.zeros((h, w, 4), np.uint8)
    for r in range(step, int(math.hypot(w, h)), step):
        for t in range(0, 360, max(1, int(360 * P * 1.6 / (2 * math.pi * r)))):
            aa = math.radians(t)
            px, py = snap(cx + math.cos(aa) * r - x0, P), snap(cy + math.sin(aa) * r - y0, P)
            if 0 <= px < w - P and 0 <= py < h - P and m[py, px]:
                lay[py:py + P, px:px + P] = col + (a,)
    img.alpha_composite(Image.fromarray(lay, "RGBA"), (x0, y0))


def gauge(img, box, P, col, crest, sel):
    """T5b：左缘潮位尺刻度 + 水位指针"""
    x0, y0, x1, y1 = box
    d = ImageDraw.Draw(img)
    gx = x0 + 3 * P
    for i, yy in enumerate(range(y0 + 6 * P, y1 - 3 * P, 3 * P)):
        L = 4 * P if i % 4 == 0 else 2 * P
        d.rectangle([gx, yy, gx + L - 1, yy + P - 1], fill=col)
    if crest is not None:
        c = INK_D if sel else AMBER
        d.polygon([(gx + 5 * P, crest), (gx + 8 * P, crest - 2 * P), (gx + 8 * P, crest + 2 * P)], fill=c)


# ---------------------------------------------------------------- 磁贴内容
MENU = c3.MENU
SUBS = c3.SUBS


def tile(img, box, i, sel, V, size, s=1.0):
    P = V["P"]
    (x0, y0, x1, y1), m, crest = tile_base(img, box, sel, V, size, s)
    cn, en, ic = MENU[i]
    if sel:
        txt, sub, idx, ico, ico2 = INK_D, (44, 40, 40), INK_D, INK_D, (90, 60, 30)
    else:
        txt, sub, idx, ico, ico2 = TXT, TXT2, CY, (200, 226, 238), CY
    fs = V["fs"]  # 像素字基准倍数
    k_big = V["ik"]
    if V["sonar"]:
        if size == "big":
            sonar(img, (x0, y0, x1, y1), m, x1 - 70 * s, crest or y1, P, INK_D if sel else (120, 220, 236), 70 if sel else 64, int(22 * s))
        elif size == "mid":
            sonar(img, (x0, y0, x1, y1), m, x1 - 30 * s, y0 + 30 * s, P, INK_D if sel else (120, 220, 236), 60 if sel else 52, int(14 * s))
        # 扫描线：每隔 2 格压暗一行（声呐屏）
        sl = m.copy()
        sl[(np.arange(m.shape[0]) // P) % 2 == 0, :] = False
        solid(img, x0, y0, sl & ~edge_of(m, P), (0, 0, 0, 34))
        # 顶部铭牌：一条更深的标签带 + 序列号（像潮位站仪表面板）
        hb = m.copy()
        hb[4 * P:, :] = False
        hb[:, : 3 * P] = False
        solid(img, x0, y0, hb & ~edge_of(m, P), (INK_D + (60,)) if sel else (2, 8, 20, 150))
        if size != "small":
            ptxt(img, (x1 - 10 * P, y0 + 2 * P), "TG-%02d" % (i + 1), 1, (INK_D if sel else CY_DIM), 1, "rm")
    if V["gauge"] and size != "small":
        gauge(img, (x0, y0, x1, y1), P, (INK_D if sel else CY_DIM), crest, sel)
    ox = 10 * P if (V["gauge"] and size != "small") else 0
    d = ImageDraw.Draw(img)

    def icon_at(cx, cy, k):
        if V["pixicon"]:
            put_icon(img, ic, cx, cy, k, ico, ico2)
        else:
            c3.icon(d, ic, cx, cy, 7 * k, ico, 2)

    if size == "big":
        w_ = ptxt(img, (x0 + 24 * s + ox, y0 + 24 * s), "%02d" % (i + 1), ps(2, s), idx, 1, "lm")
        ptxt(img, (x0 + 24 * s + ox + w_ + 10 * s, y0 + 24 * s), "// OPERATION", fs, sub, 1, "lm")
        text(img, (x0 + 22 * s + ox, y0 + 76 * s), cn, int(44 * s), txt, "lm", bold=True)
        ptxt(img, (x0 + 26 * s + ox, y0 + 114 * s), en, ps(2, s), txt, 2, "lm")
        text(img, (x0 + 24 * s + ox, y0 + 144 * s), SUBS[0], int(15 * s), sub, "lm")
        # 上次出发：小潮位预览
        px0, py0, px1, py1 = snap(x1 - 196 * s, P), snap(y0 + 18 * s, P), snap(x1 - 18 * s, P), snap(y0 + 108 * s, P)
        pm = stair(px1 - px0, py1 - py0, P, 2)
        if sel:
            solid(img, px0, py0, edge_of(pm, P), INK_D)
        else:
            solid(img, px0, py0, pm, (4, 10, 22, 170))
            solid(img, px0, py0, edge_of(pm, P), EDGE)
        ptxt(img, (px0 + 12 * s, py0 + 14 * s), "LAST DEPLOY", fs, sub, 1, "lm")
        wv = ptxt(img, (px0 + 12 * s, py0 + 38 * s), "IV", ps(3, s), txt, 1, "lm")
        text(img, (px0 + 22 * s + wv, py0 + 38 * s), "波涛迭起", int(15 * s), txt, "lm", bold=True)
        for k in range(3):
            bx = snap(px0 + 12 * s + k * 22 * s, P)
            by = snap(py0 + 56 * s, P)
            if k < 2:
                d.rectangle([bx, by, bx + snap(16 * s, P) - 1, by + 3 * P - 1], fill=(INK_D if sel else CY))
            else:
                d.rectangle([bx, by, bx + snap(16 * s, P) - 1, by + 3 * P - 1], outline=(INK_D if sel else CY_DIM))
        text(img, (px0 + 12 * s, py0 + 76 * s), "水月 · 三人编队", int(12 * s), sub, "lm")
        icx, icy = x1 - 70 * s, (crest - 26 * s) if crest else y1 - 44 * s
        if sel and crest:
            ripple(img, icx, crest, P, s, m, (x0, y0))
        icon_at(icx, icy, k_big)
        ecol = FOAM if (sel and crest) else sub
        ptxt(img, (x1 - 22 * s, y1 - 14 * s), "ENTER / PAD A", fs, ecol, 1, "rm")
    elif size == "mid":
        ptxt(img, (x0 + 18 * s + ox, y0 + 20 * s), "%02d" % (i + 1), ps(2, s), idx, 1, "lm")
        icx, icy = x1 - 30 * s, y0 + 30 * s
        icon_at(icx, icy, V["ik_mid"])
        text(img, (x0 + 18 * s + ox, y0 + 54 * s), cn, int(24 * s), txt, "lm", bold=True)
        ptxt(img, (x0 + 20 * s + ox, y0 + 78 * s), en, fs, txt, 2, "lm")
        if s >= 1:
            text(img, (x0 + 18 * s + ox, y0 + 96 * s), SUBS[i], int(12 * s), sub, "lm")
        if sel and crest:
            ripple(img, x1 - 50 * s, crest, P, s * 0.8, m, (x0, y0))
    else:
        icon_at(x0 + 26 * s, (y0 + y1) / 2 - 3 * s, V["ik_small"])
        text(img, (x0 + 48 * s, (y0 + y1) / 2 - 9 * s), cn, int(17 * s), txt, "lm", bold=True)
        ptxt(img, (x0 + 49 * s, (y0 + y1) / 2 + 10 * s), en, fs, sub, 1, "lm")
        ptxt(img, (x1 - 10 * s, y0 + 12 * s), "%02d" % (i + 1), fs, idx, 1, "rm")
        if sel and crest:
            ripple(img, x0 + 26 * s, crest, P, s * 0.6, m, (x0, y0))


def cluster(img, x0, y0, w, sel, V, s=1.0, n_small=3, hint=True):
    boxes, yb = c3.cluster_boxes(x0, y0, w, s, n_small)
    sizes = ["big", "mid", "mid"] + ["small"] * n_small
    # 先画全部未选中，再画选中（光晕盖在邻居上方一点，像灯照过去）
    for i, b in enumerate(boxes):
        if i != sel:
            tile(img, b, i, False, V, sizes[i], s)
    if V.get("lamp_hang"):
        # T5b：一盏灯吊在选中磁贴上方，跟着焦点移动；灯光是一圈台阶式像素光
        bx0, by0, bx1, _ = boxes[sel]
        lx, ly = int(bx0 + (bx1 - bx0) * 0.62), int(by0 - 22 * s)
        lm = Image.new("L", img.size, 0)
        ImageDraw.Draw(lm).ellipse([lx - 30 * s, ly - 24 * s, lx + 30 * s, ly + 36 * s], fill=255)
        glow(img, lm, AMBER, 16 * s, (0.08, 0.25, 0.5, 0.8), (30, 60, 100, 150), cell=V["P"] * 2)
        d = ImageDraw.Draw(img)
        for yy in range(int(ly - 60 * s), int(ly - 16 * s), 2 * V["P"]):
            d.rectangle([lx - 1, yy, lx, yy + V["P"] - 1], fill=CY_DIM)
        k = 2 if s >= 1 else 1
        img.alpha_composite(lamp_icon(k), (lx - 8 * k, int(ly - 8 * k)))
    tile(img, boxes[sel], sel, True, V, sizes[sel], s)
    if hint:
        ptxt(img, (x0 + w, yb + 20 * s), "↑↓←→ SELECT   ENTER CONFIRM", V["fs"], TXT2, 1, "rm")
    return boxes


# ---------------------------------------------------------------- 四角
def dpanel(img, box, V, tones=None, alpha=None, n=2):
    """通用深海抖动小面板（T5c 用磨砂）"""
    P = V["P"]
    x0, y0, x1, y1 = [snap(v, P) for v in box]
    m = stair(x1 - x0, y1 - y0, P, n)
    if V["smooth"]:
        full = Image.new("L", img.size, 0)
        full.paste(Image.fromarray((m * 255).astype(np.uint8), "L"), (x0, y0))
        img.paste(img.filter(ImageFilter.GaussianBlur(6)), (0, 0), full)
        solid(img, x0, y0, m, NAVY + (alpha or 170,))
    else:
        t = tones or V["tones"]
        nt = len(t) - 1
        lv = dith(x0, y0, x1 - x0, y1 - y0, V["dP"], lambda cx, cy: np.clip(cy / (y1 - y0) * nt * 1.1, 0, nt))
        paint(img, x0, y0, m, lv, t, alpha or V["alpha"])
    solid(img, x0, y0, edge_of(m, P if not V["smooth"] else 1), EDGE + (180,))
    return (x0, y0, x1, y1), m


def lamp_log(img, x, y, V, s=1.0, compact=False):
    """左上：灯火日志（灯照亮的一行日志）"""
    P = V["P"]
    w, h = (380 if compact else 548) * s, 32 * s
    (x0, y0, x1, y1), m = dpanel(img, (x, y, x + w, y + h), V)
    if not V["smooth"]:
        # 灯照：从左端的灯往右，琥珀抖动渐渐褪进藏青
        lit = [(0, 0, 0, 0), (40, 34, 44, 200), (96, 64, 40, 220), (176, 112, 48, 230)]
        reach = V["lamp_reach"] * s
        lv = dith(x0, y0, x1 - x0, y1 - y0, V["dP"], lambda cx, cy: np.clip(3.2 - np.hypot(cx - 18 * s, (cy - h / 2) * 2.2) / reach * 3, 0, 3))
        mm = m & (lv > 0) & ~edge_of(m, P)
        paint(img, x0, y0, mm, lv, lit)
        lm = Image.new("L", img.size, 0)
        ImageDraw.Draw(lm).ellipse([x0 + 4 * s, y0 + 2 * s, x0 + 32 * s, y0 + h - 2 * s], fill=255)
        glow(img, lm, AMBER, 6 * s, (0.1, 0.4), (50, 90), cell=P * 2)
    k = 2 if s >= 1 else 1
    li = lamp_icon(k)
    img.alpha_composite(li, (int(x0 + 18 * s - 8 * k), int(y0 + h / 2 - 8 * k)))
    cy = y0 + h / 2
    xx = x0 + 38 * s
    xx += text(img, (xx, cy), "灯火日志", int(14 * s), AMBER_HI, "lm", bold=True) + 8 * s
    if not compact:
        xx += ptxt(img, (xx, cy), "LAMP LOG", 1, (176, 150, 120), 1, "lm") + 14 * s
    items = [("干员", "18/18"), ("潮位", "VIII"), ("局数", "37")] if compact else [("已解锁干员", "18/18"), ("最高潮位", "VIII"), ("总局数", "37")]
    fsz = V["fs"] + (1 if s >= 1 else 0)
    for lab, v in items:
        ptxt(img, (xx, cy), "·", 1, CY_DIM, 0, "lm")
        xx += 12 * s
        xx += text(img, (xx, cy), lab, int(12 * s), TXT2, "lm") + 6 * s
        xx += ptxt(img, (xx, cy), v, fsz, TXT, 1, "lm") + 14 * s


def corner_icons_px(img, x1, y, V, s=1.0, keys=True):
    """像素图标版：16×16 按 2× 放进方块（手机 1×）"""
    P = V["P"]
    k = snap(36 * s, P)
    ik = 2 if s >= 1 else 1
    for j, (kind, key) in enumerate((("settings", "ESC"), ("info", "C"), ("full", "F11"))):
        bx = snap(x1 - k - j * (k + 8 * s), P)
        dpanel(img, (bx, y, bx + k, y + k), V, n=2)
        if V["pixicon"]:
            put_icon(img, kind, bx + k / 2, y + k / 2, ik, TXT, CY)
        else:
            c3.icon(ImageDraw.Draw(img), kind, bx + k / 2, y + k / 2, 9 * s, TXT, 2)
        if keys:
            ptxt(img, (bx + k / 2, y + k + 9 * s), key, 1, TXT2, 1, "mm")
    ptxt(img, (x1 - 3 * (k + 8 * s) - 6 * s, y + k / 2), "V2.1", V["fs"], TXT2, 1, "rm")


PAPER = [(164, 172, 170), (150, 160, 160), (134, 146, 148)]   # 去饱和的旧纸（偏海水灰，不抢琥珀）
P_INK = (26, 38, 52)


def bottle_note(img, x, y, w, h, V, s=1.0):
    """左下：漂流瓶便笺（本版更新）"""
    P = V["P"]
    x0, y0, x1, y1 = [snap(v, P) for v in (x, y, x + w, y + h)]
    m = stair(x1 - x0, y1 - y0, P, 2)
    # 底边撕纸：随机阶梯
    rnd = random.Random(7)
    for cx in range(0, x1 - x0, P):
        cut = rnd.choice((0, 0, 1, 1, 2)) * P
        if cut:
            m[(y1 - y0) - cut:, cx:cx + P] = False
    over(img, lambda d: d.rectangle([x0 + 4 * s, y0 + 5 * s, x1 + 4 * s, y1 + 3 * s], fill=(0, 4, 12, 120)))
    if V["smooth"]:
        solid(img, x0, y0, m, PAPER[0] + (235,))
    else:
        lv = dith(x0, y0, x1 - x0, y1 - y0, V["dP"], lambda cx, cy: np.clip((cy / (y1 - y0)) * 1.6 + (cx / (x1 - x0)) * 0.6, 0, 2))
        paint(img, x0, y0, m, lv, PAPER, 245)
    # 横格线
    d = ImageDraw.Draw(img)
    for yy in range(int(y0 + 30 * s), int(y1 - 6 * s), max(P * 2, int(22 * s))):
        over(img, lambda dd: dd.line([(x0 + 10 * s, yy + 10 * s), (x1 - 12 * s, yy + 10 * s)], fill=(90, 110, 120, 90), width=1))
    k = 2 if s >= 1 else 1
    bt = picon("bottle", k, {1: (60, 96, 110), 2: (220, 224, 214), 3: (118, 108, 96), 4: (230, 250, 250)})
    img.alpha_composite(bt, (int(x0 + 10 * s), int(y0 + 14 * s - 8 * k)))
    ptxt(img, (x0 + 10 * s + 16 * k + 8 * s, y0 + 14 * s), "DRIFT NOTE  V2.1", 1, (60, 86, 100), 1, "lm")
    text(img, (x1 - 12 * s, y0 + 14 * s), "漂流瓶", int(11 * s), (60, 86, 100), "rm")
    text(img, (x0 + 12 * s, y0 + 40 * s), "新干员 浊心斯卡蒂 等 5 位", int(16 * s), P_INK, "lm", bold=True)
    if h > 60 * s:
        text(img, (x0 + 12 * s, y0 + 64 * s), "德克萨斯 · 星熊 · 能天使 · 安洁莉娜", int(12 * s), (56, 70, 84), "lm")
    # 翻页：三颗像素点
    for j in range(3):
        cx = snap(x1 - 40 * s + j * 10 * s, P)
        d.rectangle([cx, y1 - 14 * s, cx + 2 * P - 1, y1 - 14 * s + 2 * P - 1], fill=(P_INK if j == 0 else (110, 124, 132)))


def news_plain(img, x, y, w, h, V, s=1.0):
    """T5c：便笺也走深色磨砂（克制版只换外形与字体）"""
    (x0, y0, x1, y1), m = dpanel(img, (x, y, x + w, y + h), V)
    k = 2 if s >= 1 else 1
    img.alpha_composite(picon("bottle", k, {1: CY_DIM, 2: (210, 220, 220), 3: (120, 130, 140), 4: TXT}), (int(x0 + 12 * s), int(y0 + 15 * s - 8 * k)))
    ptxt(img, (x0 + 12 * s + 16 * k + 8 * s, y0 + 15 * s), "DRIFT NOTE  V2.1", 1, CY, 1, "lm")
    text(img, (x0 + 14 * s, y0 + 40 * s), "新干员 浊心斯卡蒂 等 5 位", int(16 * s), TXT, "lm", bold=True)
    if h > 60 * s:
        text(img, (x0 + 14 * s, y0 + 64 * s), "德克萨斯 · 星熊 · 能天使 · 安洁莉娜", int(12 * s), TXT2, "lm")


def cover_tag(img, x, y, V, s=1.0):
    ptxt(img, (x, y), "COVER // ASSISTANT", 1, CY, 1, "lm")
    w = text(img, (x, y + 22 * s), "水月", int(18 * s), TXT, "lm", bold=True)
    ptxt(img, (x + w + 8 * s, y + 22 * s), "MIZUKI", 1, TXT2, 2, "lm")


def cover_switch(img, x1, y, V, s=1.0):
    yy = y + 38 * s
    ptxt(img, (x1, yy), "V", V["fs"], CY, 1, "rm")
    w = text(img, (x1 - 20 * s, yy), "更换封面干员", int(17 * s), TXT, "rm", bold=True)
    ix = x1 - 20 * s - w - 22 * s
    d = ImageDraw.Draw(img)
    P = V["P"]
    # 像素菱形
    pts = [(ix + dx * P, yy + dy * P) for dx, dy in ((0, -4), (1, -3), (2, -2), (3, -1), (4, 0), (3, 1), (2, 2), (1, 3), (0, 4), (-1, 3), (-2, 2), (-3, 1), (-4, 0), (-3, -1), (-2, -2), (-1, -3))]
    for (px, py) in pts:
        d.rectangle([px, py, px + P - 1, py + P - 1], fill=TXT)
    over(img, lambda dd: dd.line([(ix - 4 * P, yy + 22 * s), (x1, yy + 22 * s)], fill=TXT2 + (90,), width=1))
    d.rectangle([ix - 4 * P, yy + 21 * s, ix - 4 * P + 26 * s, yy + 21 * s + P - 1], fill=CY)


# ---------------------------------------------------------------- 变体参数
VARIANTS = {
    "a": dict(P=2, dP=2, n=3, smooth=False, tones=N_TONES, alpha=232, tide=True,
              tide_rest=dict(big=0.07, mid=0.09, small=0.10), tide_sel=dict(big=0.22, mid=0.22, small=0.24),
              glow_r=12, glow_steps=(0.08, 0.3, 0.6), glow_a=(48, 96, 150), pixicon=True, ik=3, ik_mid=2, ik_small=2,
              fs=1, jelly=True, sonar=False, gauge=False, lamp_reach=90),
    "b": dict(P=2, dP=3, n=4, smooth=False, tones=N_TONES_B, alpha=240, tide=True,
              tide_rest=dict(big=0.10, mid=0.12, small=0.14), tide_sel=dict(big=0.24, mid=0.26, small=0.28),
              glow_r=22, glow_steps=(0.05, 0.18, 0.4, 0.7), glow_a=(28, 56, 96, 150), pixicon=True, ik=3, ik_mid=2, ik_small=2,
              fs=1, jelly=True, sonar=True, gauge=True, lamp_reach=150, lamp_hang=True),
    "c": dict(P=2, dP=2, n=3, smooth=True, tones=N_TONES, alpha=200, tide=False,
              tide_rest={}, tide_sel={}, glow_r=0, glow_steps=(), glow_a=(), pixicon=False, ik=3, ik_mid=2, ik_small=2,
              fs=1, jelly=False, sonar=False, gauge=False, lamp_reach=0),
}


def deep_life(img, V, s=1.0, phone=False):
    """磁贴缝里的水母与生物荧光（坐标手摆在磁贴之间的空隙 / 磁贴群外缘）"""
    if not V["jelly"]:
        return
    k = V["P"] if not phone else 1
    if phone:
        jelly(img, 390, 180, 1, 0.9)
        jelly(img, 560, 28, 1, 0.6)
        motes(img, [(398, 120, 1), (712, 244, 0), (520, 56, 1), (380, 250, 0)], 1)
    else:
        jelly(img, 1238, 318, 2, 0.9)
        jelly(img, 1180, 84, 2, 0.55)
        jelly(img, 736, 452, 2, 0.8)
        if V["sonar"]:
            jelly(img, 880, 84, 1, 0.7)
        motes(img, [(748, 250, 1), (742, 470, 0), (1010, 345, 1), (1252, 300, 0), (900, 112, 1), (1040, 474, 0), (760, 610, 1)], k)


# ---------------------------------------------------------------- 标题 T5
def title_T5(var="a", sel=0):
    V = VARIANTS[var]
    img = c3.stage()
    c3.place(img, "doctor_idle", 3, (418, 604), k=0.8, bbox=c3.BB_DOC)
    c3.place(img, "player_idle", 4, (556, 628), bbox=c3.BB_MIZ)
    img.alpha_composite(logo(0.42), (26, 20))
    ptxt(img, (262, 50), "MIZUKI & CAERULA ARBOR".replace("&", "+"), 1, TXT2, 1, "lm")
    text(img, (262, 70), "水月与深蓝之树", 13, TXT, "lm")
    lamp_log(img, 24, 96, V)
    corner_icons_px(img, 1256, 20, V)
    cluster(img, 768, 128, 480, sel, V)
    deep_life(img, V)
    cover_tag(img, 452, 650, V)
    cover_switch(img, 740, 636, V, 0.82)
    if V["smooth"]:
        news_plain(img, 24, 562, 330, 92, V)
    else:
        bottle_note(img, 24, 560, 330, 96, V)
    text(img, (24, 700), "明日方舟同人作品 · 非商业 · 与鹰角网络无关 · 致谢与声明 C", 11, TXT2, "lm")
    return img


def title_T5_phone(var="a", sel=0):
    V = dict(VARIANTS[var])
    V.update(P=1, dP=1, n=3, ik=2, ik_mid=1, ik_small=1, glow_r=8)
    img = c3.stage(phone=True)
    c3.place(img, "doctor_idle", 2, (232, 300), k=0.8, bbox=c3.BB_DOC)
    c3.place(img, "player_idle", 3, (316, 318), bbox=c3.BB_MIZ)
    img.alpha_composite(logo(0.24), (12, 10))
    lamp_log(img, 12, 48, V, 0.62, compact=True)
    corner_icons_px(img, 730, 10, V, 0.72, keys=False)
    cluster(img, 404, 62, 326, sel, V, s=0.62, n_small=2, hint=False)
    deep_life(img, V, phone=True)
    if V["smooth"]:
        news_plain(img, 12, 294, 176, 38, V, 0.62)
    else:
        bottle_note(img, 12, 292, 176, 40, V, 0.62)
    cover_switch(img, 392, 312, V, 0.62)
    text(img, (12, 350), "同人作品 · 非商业 · 致谢 C", 9, TXT2, "lm")
    return img


# ---------------------------------------------------------------- 难度内页（T5a）：潮位尺选档
TIERS = [("波涛迭起", "RISING TIDE", "0", "海洋的真容，才刚刚显露。"),
         ("波涛迭起", "RISING TIDE IV", "IV", "暗礁更多，灯火更难守住。"),
         ("波涛迭起", "RISING TIDE VIII", "VIII", "大海不再留情。")]


def diff_T5(sel=1):
    V = VARIANTS["a"]
    P = V["P"]
    img = c3.stage()
    over(img, lambda d: d.rectangle([0, 0, W, H], fill=(2, 6, 16, 120)))
    # 顶栏：返回 + 标题
    ptxt(img, (28, 34), "OPERATION // DIFFICULTY", 1, CY, 1, "lm")
    text(img, (28, 62), "选择潮位", 26, TXT, "lm", bold=True)
    ptxt(img, (148, 64), "TIDE LEVEL", 2, TXT2, 2, "lm")
    # 左：潮位尺（整块就是选档器：水位停在所选档）
    gx0, gy0, gx1, gy1 = 40, 112, 132, 640
    (bx0, by0, bx1, by1), gm = dpanel(img, (gx0, gy0, gx1, gy1), V, n=3)
    ys = {0: 560, 1: 380, 2: 200}       # 三档刻度高度：标准 / Ⅳ / Ⅷ
    lvl = ys[sel]
    # 水
    h, w = gm.shape
    yy, xx = np.mgrid[0:h, 0:w]
    gxx = (xx + bx0) // P
    wave = (np.round(np.sin(gxx * 0.7) * 0.8) * P).astype(int)
    wy = (lvl - by0) + wave
    wm = gm & (yy >= wy) & ~edge_of(gm, P)
    wl = dith(bx0, by0, w, h, P, lambda cx, cy: np.clip((cy - (lvl - by0)) / 260 * 2.2, 0, 2))
    paint(img, bx0, by0, wm, wl, WATER, 240)
    top = wm & ~np.roll(wm, P, axis=0)
    solid(img, bx0, by0, top, FOAM + (230,))
    d = ImageDraw.Draw(img)
    for yv in range(by0 + 8 * P, by1 - 4 * P, 4 * P):
        L = 7 * P if (yv - by0) % (16 * P) == 0 else 3 * P
        d.rectangle([bx0 + 3 * P, yv, bx0 + 3 * P + L - 1, yv + P - 1], fill=CY_DIM)
    ripple(img, (bx0 + bx1) / 2, lvl, P, 0.9, gm, (bx0, by0))
    # 档位卡（潮位尺右边，对齐刻度）
    for i, (nm, en, num, desc) in enumerate(TIERS):
        y = ys[i]
        s_ = i == sel
        box = (156, y - 44, 556, y + 44)
        lmask = Image.new("L", img.size, 0)
        x0, y0, x1, y1 = [snap(v, P) for v in box]
        m = stair(x1 - x0, y1 - y0, P, 3)
        if s_:
            lmask.paste(Image.fromarray((m * 255).astype(np.uint8), "L"), (x0, y0))
            glow(img, lmask, AMBER, 12, (0.08, 0.3, 0.6), (36, 72, 120), cell=P * 2)
            lv = dith(x0, y0, x1 - x0, y1 - y0, P, lambda cx, cy: np.clip(cy / (y1 - y0) * 2.2, 0, 2))
            paint(img, x0, y0, m, lv, AMBER_TONES)
            solid(img, x0, y0, edge_of(m, P), AMBER_HI)
            tc, sc_ = INK_D, (44, 40, 40)
            # 刻度连线：琥珀指针从卡片指到水位
            d.polygon([(bx1 + 2, y), (x0 - 4, y - 8), (x0 - 4, y + 8)], fill=AMBER)
        else:
            lv = dith(x0, y0, x1 - x0, y1 - y0, P, lambda cx, cy: np.clip(cy / (y1 - y0) * 2.2, 0, 2))
            paint(img, x0, y0, m, lv, N_TONES, 230)
            solid(img, x0, y0, edge_of(m, P), EDGE)
            tc, sc_ = TXT, TXT2
            d.rectangle([bx1 + 4, y - 1, x0 - 6, y], fill=CY_DIM)
        ptxt(img, (x0 + 22, (y0 + y1) / 2), num, 4, tc, 1, "lm")
        wn = text(img, (x0 + 140, y0 + 30), nm, 22, tc, "lm", bold=True)
        if num != "0":
            ptxt(img, (x0 + 150 + wn, y0 + 30), num, 2, tc, 1, "lm")
        ptxt(img, (x0 + 142, y0 + 54), en, 1, tc, 2, "lm")
        text(img, (x0 + 140, y0 + 72), desc, 13, sc_, "lm")
        ptxt(img, (x1 - 14, y0 + 16), "LV %s" % ("0" if num == "0" else {"IV": "4", "VIII": "8"}[num]), 1, sc_, 1, "rm")
    ptxt(img, (gx0 + (gx1 - gx0) / 2, gy1 + 18), "TIDE", 1, TXT2, 1, "mm")
    # 右：档位文件（修正项）
    rx0, ry0, rx1, ry1 = 612, 100, 1252, 600
    dpanel(img, (rx0, ry0, rx1, ry1), V, n=3, alpha=236)
    ptxt(img, (rx0 + 24, ry0 + 24), "TIER FILE // MODIFIERS", 1, CY, 1, "lm")
    text(img, (rx0 + 24, ry0 + 54), TIERS[sel][3], 18, TXT, "lm")
    effs = [("敌人生命", "+20%"), ("敌人造成的伤害", "+20%"), ("Boss 生命", "+15%"), ("受击时灯火损失", "+30%"), ("灯油掉落", "-30%"),
            ("源石锭掉落", "-10%"), ("Boss 预警最多缩短", "15%"), ("大群规模", "+20%"), ("小怪控制提前到", "5:00"), ("寒霜 2 层即冻结", "")]
    for i, (a, b) in enumerate(effs):
        col, row = i // 5, i % 5
        bx = rx0 + 24 + col * 304
        by = ry0 + 84 + row * 80
        (cx0, cy0, cx1, cy1), cm = dpanel(img, (bx, by, bx + 288, by + 68), V, tones=[(16, 34, 58), (10, 22, 42)], n=2)
        ptxt(img, (cx0 + 14, cy0 + 16), "MOD %02d" % (i + 1), 1, CY_DIM, 1, "lm")
        text(img, (cx0 + 14, cy0 + 42), a, 15, TXT, "lm")
        if b:
            ptxt(img, (cx1 - 14, cy0 + 40), b, 2, TXT, 1, "rm")
        # 每张卡底下一条细潮线
        d.rectangle([cx0 + 2 * P, cy1 - 3 * P, cx1 - 2 * P - 1, cy1 - 3 * P + P - 1], fill=(40, 110, 130))
    # 出发 / 返回
    (ox0, oy0, ox1, oy1), om = dpanel(img, (rx0, 620, rx0 + 300, 680), V, n=3)
    solid(img, ox0, oy0, edge_of(om, P), AMBER)
    text(img, (ox0 + 72, (oy0 + oy1) / 2), "出发", 24, TXT, "lm", bold=True)
    put_icon(img, "deploy", ox0 + 36, (oy0 + oy1) / 2, 2, AMBER, AMBER_HI)
    ptxt(img, (ox1 - 16, (oy0 + oy1) / 2), "ENTER", 1, TXT2, 1, "rm")
    (bx0_, by0_, bx1_, by1_), _ = dpanel(img, (rx0 + 320, 628, rx0 + 470, 672), V, n=2)
    text(img, (bx0_ + 20, (by0_ + by1_) / 2), "返回", 15, TXT, "lm")
    ptxt(img, (bx1_ - 14, (by0_ + by1_) / 2), "ESC", 1, TXT2, 1, "rm")
    ptxt(img, (W - 28, 700), "↑↓ CHANGE TIDE", 1, TXT2, 1, "rm")
    jelly(img, 576, 150, 2, 0.6)
    motes(img, [(586, 300, 1), (570, 470, 0), (594, 560, 1)], 2)
    return img


# ---------------------------------------------------------------- 总览
def main():
    os.makedirs(OUT4, exist_ok=True)
    t4b = Image.open(os.path.join(c1.OUT, "v3", "title_T4b.png")).convert("RGBA")
    t4b_phone = Image.open(os.path.join(c1.OUT, "v3", "title_T4b_phone.png")).convert("RGBA")
    outs = {
        "title_T5a": title_T5("a"),
        "title_T5b": title_T5("b"),
        "title_T5c": title_T5("c"),
        "title_T5a_sel2": title_T5("a", sel=1),
        "title_T5a_phone": title_T5_phone("a"),
        "diff_T5a": diff_T5(1),
    }
    for k, im in outs.items():
        p = os.path.join(OUT4, k + ".png")
        im.convert("RGB").save(p)
        print("写出", p)
    contact_sheet([
        ("标题", [("T4b（§10 推荐，原作外观）", t4b), ("T5a：自有风格，适中（推荐）", outs["title_T5a"]),
                ("T5b：加强版，潮位尺 / 声呐面板", outs["title_T5b"]), ("T5c：克制版，切角 + 灯火暖光 + 像素字", outs["title_T5c"])]),
        ("T5a 变体", [("T5a 选中「图鉴」：中号磁贴水位上涨", outs["title_T5a_sel2"]), ("T5a 难度内页：潮位尺选档", outs["diff_T5a"])]),
        ("手机", [("T4b 手机 740×360", t4b_phone), ("T5a 手机 740×360", outs["title_T5a_phone"])]),
    ], "T5 自有风格（T4b 骨架 + 灯火暖光 / 阶梯切角 / 抖动 / 像素字 / 潮线）  docs/67 §11", os.path.join(OUT4, "contact_sheet_v4.png"))


if __name__ == "__main__":
    main()
