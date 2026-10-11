# -*- coding: utf-8 -*-
"""T5a 选中色对照（docs/67 §11.7，2026-10-12 用户：「琥珀色是不是不太好看」）。

只是概念图，不改游戏代码。T5a 标题（选中「集结出发」）与 T5a 难度内页各出 4 种选中处理，其余完全不动：
  S1 现有强调黄 UI.C_ACC #FFCE00 平涂（不渐变）+ 深字，保留像素光晕；
  S2 生物荧光青白：磁贴保持深藏青抖动底，2 px 亮青像素边 + 青色光晕 + 白字，潮线发青光；
     暖色只留在「灯火日志」的小灯图标上；
  S3 淡灯金 #F2E3B3 平涂 + 深字，光晕更弱；
  S4 反白 #EEF3F6 平涂 + 深藏青字 + 细青边。

复用 tools/concept_title_ui_v4.py：替换其中的 tile_base / tile / lamp_log，难度页单独按方案重画选中卡。

用法：
    python tools/concept_title_ui_v4_sel.py

输出（不入库）：主仓库 build/title_redesign/v4/sel/
    contact_sheet_sel.png      总览：上行标题 / 下行难度页；列 = 原琥珀、S1–S4
    title_T5a_S1..S4.png / diff_T5a_S1..S4.png
"""
import os, sys

import numpy as np
from PIL import Image, ImageDraw

TOOLS = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, TOOLS)
import concept_title_ui_v4 as v4  # noqa: E402
from concept_title_ui_v4 import (snap, stair, edge_of, dith, paint, solid, glow, ripple, ptxt, put_icon,  # noqa: E402
                                 lamp_icon, dpanel, c3, MENU, SUBS, WATER, FOAM, EDGE, N_TONES, INK_D, ps)
from concept_title_ui import W, over, contact_sheet  # noqa: E402
from concept_title_ui_v2 import CY, CY_DIM, TXT, TXT2, text  # noqa: E402

OUT = os.path.join(v4.OUT4, "sel")

C_ACC = (255, 206, 0)          # game/scripts/ui.gd UI.C_ACC = Color(1.0, 0.808, 0.0)
CYB = (110, 240, 255)          # S2 生物荧光亮青
PALE_GOLD = (242, 227, 179)    # S3 淡灯金
NEAR_WHITE = (238, 243, 246)   # S4 反白
NAVY_INK = (10, 28, 52)        # S4 深藏青字

GLOW_A = dict(steps=(0.08, 0.3, 0.6), a=(48, 96, 150))     # T5a 原值

# 每个方案：fill=None 表示保持深藏青抖动底；edge_w 以像素格（P=2 → 2 px）计
SCHEMES = {
    "S1": dict(name="S1 强调黄 #FFCE00 平涂", fill=C_ACC, edge=(255, 230, 110), edge_w=1,
               glow=C_ACC, glow_a=(40, 80, 128), txt=INK_D, sub=(64, 52, 8), idx=INK_D, ico=INK_D, ico2=(120, 88, 0),
               foam=FOAM, foam_a=230, tide_glow=None, accent=C_ACC, accent_hi=(255, 230, 110), cool_log=False),
    "S2": dict(name="S2 生物荧光青白", fill=None, tones=[(24, 56, 88), (13, 34, 62), (6, 16, 34)], edge=CYB, edge_w=1,
               glow=(70, 210, 240), glow_a=(40, 84, 140), txt=(255, 255, 255), sub=(170, 214, 230), idx=CYB,
               ico=(255, 255, 255), ico2=CYB, foam=(200, 255, 255), foam_a=255, tide_glow=(90, 230, 255),
               accent=CYB, accent_hi=(220, 252, 255), cool_log=True),
    "S3": dict(name="S3 淡灯金 #F2E3B3 平涂", fill=PALE_GOLD, edge=(255, 246, 220), edge_w=1,
               glow=PALE_GOLD, glow_a=(24, 48, 84), txt=INK_D, sub=(78, 70, 52), idx=INK_D, ico=INK_D, ico2=(130, 108, 60),
               foam=FOAM, foam_a=230, tide_glow=None, accent=PALE_GOLD, accent_hi=(255, 246, 220), cool_log=False),
    "S4": dict(name="S4 反白 #EEF3F6 + 细青边", fill=NEAR_WHITE, edge=(60, 200, 228), edge_w=1,
               glow=(90, 200, 230), glow_a=(18, 36, 64), txt=NAVY_INK, sub=(70, 92, 112), idx=(24, 130, 160),
               ico=NAVY_INK, ico2=(30, 150, 180), foam=FOAM, foam_a=230, tide_glow=None,
               accent=(60, 200, 228), accent_hi=NEAR_WHITE, cool_log=False),
}
SC = SCHEMES["S1"]   # 当前方案（render() 里切换）


def _mask_img(img, m, x0, y0):
    gm = Image.new("L", img.size, 0)
    gm.paste(Image.fromarray((m * 255).astype(np.uint8), "L"), (x0, y0))
    return gm


def sel_body(img, x0, y0, m, V, w, h):
    """选中磁贴 / 卡片的底：光晕 + 平涂或藏青抖动"""
    glow(img, _mask_img(img, m, x0, y0), SC["glow"], V["glow_r"], V["glow_steps"], SC["glow_a"], cell=V["P"] * 2)
    if SC["fill"] is None:
        nt = len(SC["tones"]) - 1
        lv = dith(x0, y0, w, h, V["dP"], lambda cx, cy: np.clip((cy / h * 0.8 + cx / w * 0.2) * nt * 1.15 - 0.05, 0, nt))
        paint(img, x0, y0, m, lv, SC["tones"], 248)
    else:
        solid(img, x0, y0, m, SC["fill"])


def sel_edge(img, x0, y0, m, P):
    e = edge_of(m, P * SC["edge_w"])
    solid(img, x0, y0, e, SC["edge"])


# ---------------------------------------------------------------- 替换 v4.tile_base（只改选中分支）
_orig_tile_base = v4.tile_base


def tile_base(img, box, sel, V, size, s=1.0):
    if not sel:
        return _orig_tile_base(img, box, sel, V, size, s)
    P = V["P"]
    x0, y0, x1, y1 = [snap(v, P) for v in box]
    w, h = x1 - x0, y1 - y0
    n = V["n"] if size != "small" else max(2, V["n"] - 1)
    m = stair(w, h, P, n)
    sel_body(img, x0, y0, m, V, w, h)
    crest = None
    if V["tide"]:
        frac = V["tide_sel"][size]
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
        top = wm & ~np.roll(wm, P, axis=0) & (depth < P / max(1.0, h - base) + 1e-6)
        if SC["tide_glow"]:
            # S2：潮线发光——浪尖下方两格做一层青色像素光
            band = wm & (ys < wy + 3 * P)
            glow(img, _mask_img(img, band, x0, y0), SC["tide_glow"], 4, (0.15, 0.45), (60, 110), cell=P)
            solid(img, x0, y0, top, SC["foam"] + (SC["foam_a"],))
        else:
            foam = top & (((gx * 7) % 11) > 1)
            solid(img, x0, y0, foam, SC["foam"] + (SC["foam_a"],))
        crest = y0 + base
    sel_edge(img, x0, y0, m, P)
    return (x0, y0, x1, y1), m, crest


# ---------------------------------------------------------------- 替换 v4.tile（选中时文字 / 图标颜色按方案）
def tile(img, box, i, sel, V, size, s=1.0):
    P = V["P"]
    (x0, y0, x1, y1), m, crest = tile_base(img, box, sel, V, size, s)
    cn, en, ic = MENU[i]
    if sel:
        txt, sub, idx, ico, ico2 = SC["txt"], SC["sub"], SC["idx"], SC["ico"], SC["ico2"]
        ink = SC["edge"] if SC["fill"] is None else SC["txt"]     # 预览框描边 / 进度条
    else:
        txt, sub, idx, ico, ico2 = TXT, TXT2, CY, (200, 226, 238), CY
        ink = CY
    fs = V["fs"]
    d = ImageDraw.Draw(img)

    def icon_at(cx, cy, k):
        put_icon(img, ic, cx, cy, k, ico, ico2)

    if size == "big":
        w_ = ptxt(img, (x0 + 24 * s, y0 + 24 * s), "%02d" % (i + 1), ps(2, s), idx, 1, "lm")
        ptxt(img, (x0 + 24 * s + w_ + 10 * s, y0 + 24 * s), "// OPERATION", fs, sub, 1, "lm")
        text(img, (x0 + 22 * s, y0 + 76 * s), cn, int(44 * s), txt, "lm", bold=True)
        ptxt(img, (x0 + 26 * s, y0 + 114 * s), en, ps(2, s), txt, 2, "lm")
        text(img, (x0 + 24 * s, y0 + 144 * s), SUBS[0], int(15 * s), sub, "lm")
        px0, py0, px1, py1 = snap(x1 - 196 * s, P), snap(y0 + 18 * s, P), snap(x1 - 18 * s, P), snap(y0 + 108 * s, P)
        pm = stair(px1 - px0, py1 - py0, P, 2)
        if sel:
            if SC["fill"] is None:
                solid(img, px0, py0, pm, (4, 10, 22, 150))
            solid(img, px0, py0, edge_of(pm, P), ink)
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
                d.rectangle([bx, by, bx + snap(16 * s, P) - 1, by + 3 * P - 1], fill=ink)
            else:
                d.rectangle([bx, by, bx + snap(16 * s, P) - 1, by + 3 * P - 1], outline=(ink if sel else CY_DIM))
        text(img, (px0 + 12 * s, py0 + 76 * s), "水月 · 三人编队", int(12 * s), sub, "lm")
        icx, icy = x1 - 70 * s, (crest - 26 * s) if crest else y1 - 44 * s
        if sel and crest:
            ripple(img, icx, crest, P, s, m, (x0, y0), col=SC["foam"])
        icon_at(icx, icy, V["ik"])
        ecol = SC["foam"] if (sel and crest) else sub
        ptxt(img, (x1 - 22 * s, y1 - 14 * s), "ENTER / PAD A", fs, ecol, 1, "rm")
    elif size == "mid":
        ptxt(img, (x0 + 18 * s, y0 + 20 * s), "%02d" % (i + 1), ps(2, s), idx, 1, "lm")
        icon_at(x1 - 30 * s, y0 + 30 * s, V["ik_mid"])
        text(img, (x0 + 18 * s, y0 + 54 * s), cn, int(24 * s), txt, "lm", bold=True)
        ptxt(img, (x0 + 20 * s, y0 + 78 * s), en, fs, txt, 2, "lm")
        if s >= 1:
            text(img, (x0 + 18 * s, y0 + 96 * s), SUBS[i], int(12 * s), sub, "lm")
        if sel and crest:
            ripple(img, x1 - 50 * s, crest, P, s * 0.8, m, (x0, y0), col=SC["foam"])
    else:
        icon_at(x0 + 26 * s, (y0 + y1) / 2 - 3 * s, V["ik_small"])
        text(img, (x0 + 48 * s, (y0 + y1) / 2 - 9 * s), cn, int(17 * s), txt, "lm", bold=True)
        ptxt(img, (x0 + 49 * s, (y0 + y1) / 2 + 10 * s), en, fs, sub, 1, "lm")
        ptxt(img, (x1 - 10 * s, y0 + 12 * s), "%02d" % (i + 1), fs, idx, 1, "rm")
        if sel and crest:
            ripple(img, x0 + 26 * s, crest, P, s * 0.6, m, (x0, y0), col=SC["foam"])


# ---------------------------------------------------------------- 替换 v4.lamp_log（只有 S2 改冷色，灯图标本身保持暖色）
_orig_lamp_log = v4.lamp_log


def lamp_log(img, x, y, V, s=1.0, compact=False):
    if not SC["cool_log"]:
        return _orig_lamp_log(img, x, y, V, s, compact)
    P = V["P"]
    w, h = (380 if compact else 548) * s, 32 * s
    (x0, y0, x1, y1), m = dpanel(img, (x, y, x + w, y + h), V)
    lit = [(0, 0, 0, 0), (20, 46, 70, 200), (28, 76, 100, 220), (44, 120, 140, 230)]
    reach = V["lamp_reach"] * s
    lv = dith(x0, y0, x1 - x0, y1 - y0, V["dP"], lambda cx, cy: np.clip(3.2 - np.hypot(cx - 18 * s, (cy - h / 2) * 2.2) / reach * 3, 0, 3))
    paint(img, x0, y0, m & (lv > 0) & ~edge_of(m, P), lv, lit)
    k = 2 if s >= 1 else 1
    img.alpha_composite(lamp_icon(k), (int(x0 + 18 * s - 8 * k), int(y0 + h / 2 - 8 * k)))
    cy = y0 + h / 2
    xx = x0 + 38 * s
    xx += text(img, (xx, cy), "灯火日志", int(14 * s), (220, 250, 255), "lm", bold=True) + 8 * s
    if not compact:
        xx += ptxt(img, (xx, cy), "LAMP LOG", 1, CY_DIM, 1, "lm") + 14 * s
    items = [("已解锁干员", "18/18"), ("最高潮位", "VIII"), ("总局数", "37")]
    fsz = V["fs"] + (1 if s >= 1 else 0)
    for lab, v in items:
        ptxt(img, (xx, cy), "·", 1, CY_DIM, 0, "lm")
        xx += 12 * s
        xx += text(img, (xx, cy), lab, int(12 * s), TXT2, "lm") + 6 * s
        xx += ptxt(img, (xx, cy), v, fsz, TXT, 1, "lm") + 14 * s


# ---------------------------------------------------------------- 难度页：先画原版，再把选中卡 / 指针 / 出发按钮按方案重画
def diff_sel(sel=1):
    V = v4.VARIANTS["a"]
    P = V["P"]
    img = c3.stage()
    over(img, lambda d: d.rectangle([0, 0, W, img.height], fill=(2, 6, 16, 120)))
    # 复制 v4.diff_T5 的布局；只有选中卡、指针、出发按钮不同
    ptxt(img, (28, 34), "OPERATION // DIFFICULTY", 1, CY, 1, "lm")
    text(img, (28, 62), "选择潮位", 26, TXT, "lm", bold=True)
    ptxt(img, (148, 64), "TIDE LEVEL", 2, TXT2, 2, "lm")
    gx0, gy0, gx1, gy1 = 40, 112, 132, 640
    (bx0, by0, bx1, by1), gm = dpanel(img, (gx0, gy0, gx1, gy1), V, n=3)
    ys = {0: 560, 1: 380, 2: 200}
    lvl = ys[sel]
    h, w = gm.shape
    yy, xx = np.mgrid[0:h, 0:w]
    gxx = (xx + bx0) // P
    wave = (np.round(np.sin(gxx * 0.7) * 0.8) * P).astype(int)
    wy = (lvl - by0) + wave
    wm = gm & (yy >= wy) & ~edge_of(gm, P)
    wl = dith(bx0, by0, w, h, P, lambda cx, cy: np.clip((cy - (lvl - by0)) / 260 * 2.2, 0, 2))
    paint(img, bx0, by0, wm, wl, WATER, 240)
    top = wm & ~np.roll(wm, P, axis=0)
    if SC["tide_glow"]:
        band = wm & (yy < wy + 3 * P)
        glow(img, _mask_img(img, band, bx0, by0), SC["tide_glow"], 4, (0.15, 0.45), (60, 110), cell=P)
    solid(img, bx0, by0, top, SC["foam"] + (SC["foam_a"],))
    d = ImageDraw.Draw(img)
    for yv in range(by0 + 8 * P, by1 - 4 * P, 4 * P):
        L = 7 * P if (yv - by0) % (16 * P) == 0 else 3 * P
        d.rectangle([bx0 + 3 * P, yv, bx0 + 3 * P + L - 1, yv + P - 1], fill=CY_DIM)
    ripple(img, (bx0 + bx1) / 2, lvl, P, 0.9, gm, (bx0, by0), col=SC["foam"])
    for i, (nm, en, num, desc) in enumerate(v4.TIERS):
        y = ys[i]
        s_ = i == sel
        x0, y0, x1, y1 = [snap(v, P) for v in (156, y - 44, 556, y + 44)]
        m = stair(x1 - x0, y1 - y0, P, 3)
        if s_:
            sel_body(img, x0, y0, m, V, x1 - x0, y1 - y0)
            sel_edge(img, x0, y0, m, P)
            tc, sc_ = SC["txt"], SC["sub"]
            d.polygon([(bx1 + 2, y), (x0 - 4, y - 8), (x0 - 4, y + 8)], fill=SC["accent"])
        else:
            lv = dith(x0, y0, x1 - x0, y1 - y0, P, lambda cx, cy: np.clip(cy / (y1 - y0) * 2.2, 0, 2))
            paint(img, x0, y0, m, lv, N_TONES, 230)
            solid(img, x0, y0, edge_of(m, P), EDGE)
            tc, sc_ = TXT, TXT2
            d.rectangle([bx1 + 4, y - 1, x0 - 6, y], fill=CY_DIM)
        ptxt(img, (x0 + 22, (y0 + y1) / 2), num, 4, (SC["idx"] if s_ else tc), 1, "lm")
        wn = text(img, (x0 + 140, y0 + 30), nm, 22, tc, "lm", bold=True)
        if num != "0":
            ptxt(img, (x0 + 150 + wn, y0 + 30), num, 2, tc, 1, "lm")
        ptxt(img, (x0 + 142, y0 + 54), en, 1, tc, 2, "lm")
        text(img, (x0 + 140, y0 + 72), desc, 13, sc_, "lm")
        ptxt(img, (x1 - 14, y0 + 16), "LV %s" % ("0" if num == "0" else {"IV": "4", "VIII": "8"}[num]), 1, sc_, 1, "rm")
    ptxt(img, (gx0 + (gx1 - gx0) / 2, gy1 + 18), "TIDE", 1, TXT2, 1, "mm")
    rx0, ry0, rx1, ry1 = 612, 100, 1252, 600
    dpanel(img, (rx0, ry0, rx1, ry1), V, n=3, alpha=236)
    ptxt(img, (rx0 + 24, ry0 + 24), "TIER FILE // MODIFIERS", 1, CY, 1, "lm")
    text(img, (rx0 + 24, ry0 + 54), v4.TIERS[sel][3], 18, TXT, "lm")
    effs = [("敌人生命", "+20%"), ("敌人造成的伤害", "+20%"), ("Boss 生命", "+15%"), ("受击时灯火损失", "+30%"), ("灯油掉落", "-30%"),
            ("源石锭掉落", "-10%"), ("Boss 预警最多缩短", "15%"), ("大群规模", "+20%"), ("小怪控制提前到", "5:00"), ("寒霜 2 层即冻结", "")]
    for i, (a, b) in enumerate(effs):
        col, row = i // 5, i % 5
        bx = rx0 + 24 + col * 304
        by = ry0 + 84 + row * 80
        (cx0, cy0, cx1, cy1), _ = dpanel(img, (bx, by, bx + 288, by + 68), V, tones=[(16, 34, 58), (10, 22, 42)], n=2)
        ptxt(img, (cx0 + 14, cy0 + 16), "MOD %02d" % (i + 1), 1, CY_DIM, 1, "lm")
        text(img, (cx0 + 14, cy0 + 42), a, 15, TXT, "lm")
        if b:
            ptxt(img, (cx1 - 14, cy0 + 40), b, 2, TXT, 1, "rm")
        d.rectangle([cx0 + 2 * P, cy1 - 3 * P, cx1 - 2 * P - 1, cy1 - 3 * P + P - 1], fill=(40, 110, 130))
    (ox0, oy0, ox1, oy1), om = dpanel(img, (rx0, 620, rx0 + 300, 680), V, n=3)
    solid(img, ox0, oy0, edge_of(om, P), SC["accent"])
    text(img, (ox0 + 72, (oy0 + oy1) / 2), "出发", 24, TXT, "lm", bold=True)
    put_icon(img, "deploy", ox0 + 36, (oy0 + oy1) / 2, 2, SC["accent"], SC["accent_hi"])
    ptxt(img, (ox1 - 16, (oy0 + oy1) / 2), "ENTER", 1, TXT2, 1, "rm")
    (bx0_, by0_, bx1_, by1_), _ = dpanel(img, (rx0 + 320, 628, rx0 + 470, 672), V, n=2)
    text(img, (bx0_ + 20, (by0_ + by1_) / 2), "返回", 15, TXT, "lm")
    ptxt(img, (bx1_ - 14, (by0_ + by1_) / 2), "ESC", 1, TXT2, 1, "rm")
    ptxt(img, (W - 28, 700), "↑↓ CHANGE TIDE", 1, TXT2, 1, "rm")
    v4.jelly(img, 576, 150, 2, 0.6)
    v4.motes(img, [(586, 300, 1), (570, 470, 0), (594, 560, 1)], 2)
    return img


def main():
    global SC
    os.makedirs(OUT, exist_ok=True)
    orig_t, orig_d = v4.title_T5("a"), v4.diff_T5(1)      # 原琥珀（未替换前）
    v4.tile_base, v4.tile, v4.lamp_log = tile_base, tile, lamp_log
    titles, diffs = [("原版：灯火暖色渐变", orig_t)], [("原版：灯火暖色渐变", orig_d)]
    for key, sc in SCHEMES.items():
        SC = sc
        t, df = v4.title_T5("a"), diff_sel(1)
        for nm, im in (("title_T5a_" + key, t), ("diff_T5a_" + key, df)):
            p = os.path.join(OUT, nm + ".png")
            im.convert("RGB").save(p)
            print("写出", p)
        titles.append((sc["name"], t))
        diffs.append((sc["name"], df))
    contact_sheet([("标题", titles), ("难度页", diffs)],
                  "T5a 选中色对照：原版暖色 / S1 强调黄 / S2 荧光青白 / S3 淡灯金 / S4 反白  docs/67 §11.7",
                  os.path.join(OUT, "contact_sheet_sel.png"))


if __name__ == "__main__":
    main()
