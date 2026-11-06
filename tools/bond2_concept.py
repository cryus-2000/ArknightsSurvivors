#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""羁绊技新画面构思：关键帧草图（docs/296，11-06 用户「没有新画面的话其实不太好看」「先构思一下给我看看」）。只用 Python，不开 Godot。
每对 4 帧（起手 / 主冲击 / 余韵 / 收尾），画在一群怪上；新烤帧条的部分（宿敌交锋十字与焦痕、企鹅物流空投急件箱、灯下审决审判光柱与灯印）按 1 美术像素 = 1 像素逐格画，
代码画的部分（斩线、曳光、残影、颗粒、照地光）沿用 tools/bond_v2_gif.py。色阶取各人转平面定稿色（fx_pxplane / _lp / _exu / _ir / lumen）。
用法：python tools/bond2_concept.py [--out 目录]  → bond2_concept_<对>_1x.png / _2x.png
"""
import argparse, math, os, random, sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bond_v2_gif as B

ROOT, MAIN = B.ROOT, B.MAIN
W, H = B.W, B.H
SQ = 0.72


def ramp(hexes):
    return [tuple(int(h[i:i + 2], 16) for i in (1, 3, 5)) for h in hexes]


TX = ramp(["#2c1406", "#5a2808", "#9c4610", "#e2781c", "#ffac3c", "#ffdc9c", "#ffffff"])
LP = ramp(["#15121f", "#2b2542", "#4a4274", "#7b70b4", "#b3aae4", "#e4e0ff", "#ffffff"])
EX = ramp(["#2a100c", "#5c2418", "#a8402a", "#f07048", "#ffa880", "#ffe0cc", "#ffffff"])
IR = ramp(["#1a0c28", "#3a1a58", "#6a32a0", "#9d58e0", "#cf98ff", "#f0e2ff", "#ffffff"])
LM = ramp(["#121a2a", "#1d3150", "#2a5282", "#4285ad", "#7fb2d6", "#c4e0f2", "#ffffff"])
WOOD = ramp(["#1e140c", "#3a2614", "#6b4a2a", "#8a6236", "#b48850"])
SMOKE = ramp(["#16181c", "#262a30", "#3a4048", "#555c66"])


def pal(r):
    return {"core": r[6], "side": r[4], "deep": r[2], "glow": tuple(c / 255 for c in r[4])}


def gl(c):
    return tuple(x / 255 for x in c)


# ---------------------------------------------------------------- 新烤帧条（草图：逐格画）

def crescent(cv, c, r, a0, a1, thick, R, k, flip=False):
    """弧形刀光：从 a0 扫到 a0 + (a1 - a0) × k；中段最厚、两头收尖；芯近白、两侧本人色、外缘中间色"""
    n = int(abs(a1 - a0) * r * 1.3)
    for i in range(int(n * k) + 1):
        u = i / max(1, n)
        a = a0 + (a1 - a0) * u
        prof = math.sin(math.pi * u) ** 0.7
        th = max(1, round(thick * prof))
        for j in range(-th - 1, th + 2):
            rr = r + j
            x, y = c[0] + math.cos(a) * rr, c[1] + math.sin(a) * rr * 0.8
            q = abs(j) / (th + 1)
            col = (255, 255, 255) if q < 0.35 else (R[5] if q < 0.65 else (R[4] if q < 0.9 else R[3]))
            cv.cell(x, y, col)
            if q < 0.35 and i % 2 == 0:
                cv.glow(x, y, gl(R[5]), 0.7)


def clash_star(cv, c, s, RA, RB):
    """交锋星芒：两色四芒（横 A 竖 B），芯 3×3 白"""
    for i in range(-s, s + 1):
        k = abs(i) / s
        ca = (255, 255, 255) if k < 0.25 else (RA[5] if k < 0.6 else RA[4])
        cb = (255, 255, 255) if k < 0.25 else (RB[5] if k < 0.6 else RB[4])
        cv.cell(c[0] + i, c[1], ca)
        cv.cell(c[0], c[1] + i * 0.6, cb)
        if abs(i) < s * 0.5:
            cv.cell(c[0] + i * 0.7, c[1] + i * 0.7 * 0.6, RA[5] if i < 0 else RB[5])
            cv.cell(c[0] + i * 0.7, c[1] - i * 0.7 * 0.6, RB[5] if i < 0 else RA[5])
        if abs(i) % 2 == 0:
            cv.glow(c[0] + i, c[1], (1, 0.95, 0.9), 1.0)
    for dx in (-1, 0, 1):
        for dy in (-1, 0, 1):
            cv.cell(c[0] + dx, c[1] + dy, (255, 255, 255))


def shards(cv, c, k, RA, RB, seed=3):
    """碎刃：两色三角碎片向外飞、往下落"""
    rng = random.Random(seed)
    for i in range(16):
        a = rng.uniform(0, math.tau)
        sp = rng.uniform(50, 110)
        x = c[0] + math.cos(a) * sp * k
        y = c[1] + math.sin(a) * sp * k * 0.7 + 40 * k * k
        R = RA if i % 2 == 0 else RB
        sz = 5 if i % 3 else 7
        col = R[5] if k < 0.5 else R[4]
        for t in range(sz):
            for u in range(sz - t):
                cv.cell(x + u - t * 0.5, y + t, col if t == 0 else R[3])


def scorch_x(cv, c, L, k, RA, RB):
    """贴地交叉焦痕：两道锯齿裂痕（暗一阶 + 余烬点），k 0→1 逐渐冷却断开"""
    rng = random.Random(5)
    for (d, R) in (((0.88, 0.47 * SQ), RA), ((0.88, -0.47 * SQ), RB)):
        jit = 0.0
        for i in range(-L, L + 1):
            jit += rng.uniform(-0.6, 0.6)
            jit = max(-2, min(2, jit))
            if k > 0.5 and (i * 7 + 3) % 5 < (k - 0.5) * 8:
                continue
            x, y = c[0] + d[0] * i, c[1] + d[1] * i + jit
            cv.cell(x, y + 1, R[1])
            cv.cell(x, y + 2, R[1])
            cv.cell(x, y, R[3] if k < 0.3 else (R[2] if k < 0.6 else R[1]))
            if i % 9 == 0 and k < 0.8:
                cv.cell(x, y - 1, R[4])
                cv.glow(x, y - 1, gl(R[4]), 0.5)


def crate(cv, p, k_fall, phase):
    """急件箱（26×20 美术像素）：木箱 + 琥珀色捆带 + 红橙角标；phase 0 下落（上方速度线）/ 1 落地压扁"""
    w, h = 26, 20 if phase == 0 else 14
    x0, y0 = p[0] - w // 2, p[1] - h
    for y in range(h):
        for x in range(w):
            edge = x in (0, w - 1) or y in (0, h - 1)
            col = WOOD[1] if edge else (WOOD[3] if (y % 3) else WOOD[2])
            if x in (7, 8, 17, 18):
                col = TX[4] if not edge else TX[3]
            if y in (2, 3) and 2 <= x <= 5:
                col = EX[3]
            cv.cell(x0 + x, y0 + y, col)
    if phase == 0:
        for i in range(7):
            for j in range(16 + i * 4):
                cv.cell(p[0] - 11 + i * 3.5, y0 - 3 - j, EX[4] if j < 4 else EX[3], max(0.0, 1 - j / 22))
        cv.glow(p[0], y0 - 2, gl(EX[4]), 1.0)


def crate_burst(cv, p, k):
    """箱子炸开：白芯琥珀爆光（3 圈像素圆）→ 木板四散（带旋转的 4×2 小块）→ 两团暗烟往上；k 0..1"""
    r0 = 10 + 46 * min(1, k * 2)
    if k < 0.45:
        for rr in range(int(r0)):
            q = rr / r0
            col = (255, 255, 255) if q < 0.35 else (TX[5] if q < 0.65 else (TX[4] if q < 0.85 else EX[3]))
            n = int(rr * 6) + 1
            for i in range(n):
                a = i / n * math.tau
                cv.cell(p[0] + math.cos(a) * rr, p[1] - 10 + math.sin(a) * rr * SQ, col)
        cv.glow(p[0], p[1] - 6, (1, 0.85, 0.6), 3.0)
    rng = random.Random(9)
    for i in range(16):
        a = rng.uniform(math.pi * 1.05, math.pi * 1.95)
        sp = rng.uniform(60, 130)
        x = p[0] + math.cos(a) * sp * k
        y = p[1] - 6 + math.sin(a) * sp * k + 70 * k * k
        horiz = (i + int(k * 10)) % 2 == 0
        for u in range(7 if horiz else 3):
            for v in range(3 if horiz else 7):
                cv.cell(x + u, y + v, WOOD[3] if u + v else WOOD[4])
    if k > 0.25:
        for j, ox in enumerate((-8, 7)):
            kk = (k - 0.25) / 0.75
            rr = 9 + 14 * kk
            cy = p[1] - 10 - 18 * kk - j * 4
            for yy in range(-int(rr), int(rr) + 1):
                for xx in range(-int(rr), int(rr) + 1):
                    if xx * xx + yy * yy <= rr * rr and (xx + yy) % 2 == 0:
                        cv.cell(p[0] + ox + xx, cy + yy, SMOKE[2] if yy < 0 else SMOKE[1], 0.85 * (1 - kk * 0.6))


def blast_ring(cv, p, k, R):
    """贴地冲击环（压扁），k 0..1 外扩、断开"""
    rr = 16 + 80 * k
    n = int(rr * 6)
    for i in range(n):
        if k > 0.5 and (i * 7) % 10 < (k - 0.5) * 16:
            continue
        a = i / n * math.tau
        x, y = p[0] + math.cos(a) * rr, p[1] + math.sin(a) * rr * SQ
        cv.cell(x, y, R[5] if k < 0.3 else R[4])
        cv.cell(x, y + 1, R[2])


def pillar(cv, c, k, top=0):
    """审判光柱（24 美术像素宽，从画面上沿砸到地面）：芯白、内层艾丽妮淡紫、外层流明钢蓝；k 0..1 = 落下 → 最亮 → 收窄"""
    if k < 0.2:
        y1 = top + (c[1] - top) * (k / 0.2)
        wdt = 6
    else:
        y1 = c[1]
        wdt = 12 if k < 0.5 else max(1, int(12 * (1 - (k - 0.5) / 0.5)))
    for y in range(int(top), int(y1)):
        flick = 1 if (y // 3) % 2 == 0 else 0
        for x in range(-wdt, wdt + 1):
            q = abs(x) / (wdt + 0.5)
            col = (255, 255, 255) if q < 0.3 else (IR[5] if q < 0.55 else (LM[5] if q < 0.8 else LM[4]))
            if q > 0.8 and flick:
                col = LM[3]
            cv.cell(c[0] + x, y, col)
        if y % 3 == 0:
            cv.glow(c[0], y, (0.9, 0.85, 1.0), 1.4)
    if k >= 0.2:
        cv.lamp(c[0], c[1], 90, (180, 200, 255), 45 * (1 - k))


def seal(cv, c, r, k, t):
    """灯印（贴地）：钢蓝外圈 + 12 道放射刻度（艾丽妮紫）+ 内圈；k 0..1 张开 → 亮 → 断开"""
    al = min(1.0, k * 3) * (1 - max(0.0, (k - 0.7) / 0.3))
    for rr, col, dash in ((r, LM[5], 0), (r - 3, LM[3], 1), (r * 0.55, IR[4], 0)):
        n = int(rr * 6.5)
        for i in range(n):
            a = i / n * math.tau + t * 0.3
            if dash and i % 4 == 3:
                continue
            cv.cell(c[0] + math.cos(a) * rr, c[1] + math.sin(a) * rr * SQ, col, al)
    for i in range(12):
        a = i / 12 * math.tau + t * 0.3
        for j in range(int(r * 0.6), int(r - 4)):
            cv.cell(c[0] + math.cos(a) * j, c[1] + math.sin(a) * j * SQ, IR[5] if i % 3 == 0 else IR[3], al)
        cv.glow(c[0] + math.cos(a) * r, c[1] + math.sin(a) * r * SQ, gl(LM[4]), 0.6 * al)


# ---------------------------------------------------------------- 场景

def kill_all(w, t, test):
    for e in w.es:
        if w.alive(e, t) and test(w.pos(e, t)):
            e["kt"] = t


def frame(A, w, t, draw_fx, ops):
    img = B.background().convert("RGBA")
    w.draw(img, t)
    for op, foot, anim in ops:
        B.put_op(img, A[op + "_" + anim][int(t * 12) % 8], foot)
    cv = B.Canvas(img)
    draw_fx(cv, t)
    return cv.finish()


def ghost(img_cv, A, op, a, b, u, R):
    """残影（代码画，已在游戏里）：本人出手帧半透明 + 偏本人色，身后 3 层越来越淡"""
    im = img_cv.finish().convert("RGBA")
    for j in range(3, -1, -1):
        uj = u - 0.15 * j
        if uj < 0:
            continue
        p = (a[0] + (b[0] - a[0]) * uj, a[1] + (b[1] - a[1]) * uj)
        al = 0.85 if j == 0 else 0.35 * (1 - j / 4)
        mul = tuple(1 + (c / 255 - 1) * 0.35 for c in R[4])
        B.put_op(im, A[op + "_atk"][4], p, b[0] < a[0], al, mul)
    return B.Canvas(im)


def chevron(cv, c, off, half, side, R, thick=7, brk=0.0):
    """巨型尖括号（宿敌主形）：side = -1 左边一只「>」朝右合、+1 右边一只「<」朝左合；
    尖端在 c.x + side × off，两臂张开 half；臂上芯白、两侧本人色、外缘中间色；brk > 0 时臂断成段往下掉"""
    tip = (c[0] + side * off, c[1])
    for arm in (-1, 1):
        end = (tip[0] + side * half, c[1] + arm * half * SQ)
        n = int(math.dist(tip, end))
        for i in range(n + 1):
            u = i / n
            if brk > 0 and int(u * 8) % 2 == 1:
                continue
            drop = brk * brk * 60 * (0.5 + u) if brk > 0 else 0
            x = tip[0] + (end[0] - tip[0]) * u
            y = tip[1] + (end[1] - tip[1]) * u + drop
            th = max(2, round(thick * (1 - 0.6 * u)))
            for j in range(-th, th + 1):
                q = abs(j) / th
                col = (255, 255, 255) if q < 0.3 else (R[5] if q < 0.6 else (R[4] if q < 0.85 else R[3]))
                cv.cell(x, y + j, col)
            if i % 3 == 0 and brk == 0:
                cv.glow(x, y, gl(R[5]), 0.8)


def diamond_wave(cv, c, r, k, RA, RB):
    """菱形冲击波（合拢那一下）：上半 A 色、下半 B 色，压扁菱形外扩、断开"""
    for i in range(int(r * 4)):
        u = i / (r * 4)
        a = u * 4
        seg = int(a)
        f = a - seg
        pts = [(r, 0), (0, r * SQ), (-r, 0), (0, -r * SQ), (r, 0)]
        x = pts[seg][0] + (pts[seg + 1][0] - pts[seg][0]) * f
        y = pts[seg][1] + (pts[seg + 1][1] - pts[seg][1]) * f
        if k > 0.5 and (i * 7) % 10 < (k - 0.5) * 16:
            continue
        R = RA if y < 0 else RB
        cv.cell(c[0] + x, c[1] + y, R[5] if k < 0.3 else R[4])
        cv.cell(c[0] + x, c[1] + y + 1, R[2])


def pair_rival(A):
    w = B.World(11, A)
    C = (430, 192)
    HALF = 120
    w.kill_circle(0.72, C, 150, 0.62)
    PT, PL = pal(TX), pal(LP)

    def fx(cv, t):
        if t < 0.7:   # 两只尖括号从两侧合拢（新帧条）
            k = min(1.0, max(0.0, (t - 0.2) / 0.5)) ** 1.6
            off = 230 * (1 - k) + 6
            chevron(cv, C, off, HALF, -1, TX)
            chevron(cv, C, off, HALF, 1, LP)
        elif t < 0.82:   # 咬合：两只尖端顶在一起 + 中缝两色星芒
            chevron(cv, C, 6, HALF, -1, TX)
            chevron(cv, C, 6, HALF, 1, LP)
            clash_star(cv, (C[0], C[1]), 30, TX, LP)
            cv.lamp(C[0], C[1], 150, (255, 220, 200), 60)
        else:   # 菱形冲击波外扩 + 括号断成段掉落
            k = min(1.0, (t - 0.82) / 0.5)
            diamond_wave(cv, C, 40 + 150 * k, k, TX, LP)
            chevron(cv, C, 6 + 30 * k, HALF, -1, TX, brk=k)
            chevron(cv, C, 6 + 30 * k, HALF, 1, LP, brk=k)

    keys = [(0.45, "起手：两人残影从两侧冲出，两只巨型尖括号张开（新帧条）"), (0.6, "合拢：琥珀「>」与淡紫「<」把怪群夹在中间往里收"),
            (0.76, "咬合：尖端顶住，中缝两色星芒，夹住的一片全吃伤害"), (1.1, "余韵：菱形冲击波外扩、括号断成段掉落，中间清空")]
    out = []
    for t, lab in keys:
        img = frame(A, w, t, lambda cv, tt: None, [("lappland", (B.SQUAD[0] - 34, B.SQUAD[1] - 26), "run"), ("texas", B.SQUAD, "run")]).convert("RGBA")
        cv = B.Canvas(img)
        if t < 0.7:
            k = min(1.0, max(0.0, (t - 0.2) / 0.5)) ** 1.6
            off = 230 * (1 - k) + 6
            cv = ghost(cv, A, "texas", (C[0] - off - 40, C[1] + 10), (C[0] - off - 20, C[1] + 10), 1.0, TX)
            cv = ghost(cv, A, "lappland", (C[0] + off + 40, C[1] + 10), (C[0] + off + 20, C[1] + 10), 1.0, LP)
        fx(cv, t)
        out.append((cv.finish(), lab, (200, 50, 660, 330)))
    return out


def pair_penguin(A):
    w = B.World(23, A)
    S = (B.SQUAD[0] + 30, B.SQUAD[1] - 10)
    ang = math.radians(-7)
    dv = (math.cos(ang), math.sin(ang))
    nv = (-dv[1], dv[0])
    L0, L1, HW = 60, 420, 50
    P = lambda s, o=0.0: (S[0] + dv[0] * s + nv[0] * o, S[1] + dv[1] * s + nv[1] * o)
    drop = P(330)
    for i in range(30):
        s = L0 + (L1 - L0) * i / 29
        w.kill_circle(0.3 + i * 0.02, P(s, ((i * 0.618) % 1 * 2 - 1) * (HW - 10)), 14, 0.7)
    w.kill_circle(1.1, drop, 80)
    PE = pal(EX)

    def lane(cv, t):
        for side in (-1, 1):
            for i in range(0, L1 - L0):
                if (i // 5) % 2:
                    continue
                p = P(L0 + i, side * HW)
                cv.cell(*p, EX[4])
                cv.cell(p[0], p[1] - side, EX[3])

    def tracers(cv, t):
        for i in range(30):
            ts = 0.3 + i * 0.02
            age = t - ts
            s = L0 + (L1 - L0) * i / 29
            p = P(s, ((i * 0.618) % 1 * 2 - 1) * (HW - 10))
            if 0 <= age < 0.06:
                src = (S[0] - 10, S[1] - 60)
                u = age / 0.06
                hx, hy = src[0] + (p[0] - src[0]) * u, src[1] + (p[1] - src[1]) * u
                dd = math.dist(src, p)
                for k in range(16):
                    cv.cell(hx - (p[0] - src[0]) / dd * k, hy - (p[1] - src[1]) / dd * k, EX[6] if k < 3 else EX[4], 1 - k / 18)
            elif 0.06 <= age < 0.14:
                for j in (-1, 0, 1):
                    cv.cell(p[0] + j, p[1], (255, 255, 255))
                    cv.cell(p[0], p[1] + j, (255, 255, 255))

    keys = [(0.6, "起手：能天使残影跃起，一路扫射标出航线（代码画）"), (1.05, "主冲击前：急件箱从高处坠向航线尽头（新帧条），德克萨斯残影冲去接应"),
            (1.2, "主冲击：箱子落地炸开，琥珀爆光 + 木板四散（新帧条）"), (1.4, "余韵：贴地冲击环 + 两团暗烟（新帧条），木板落地")]
    out = []
    for t, lab in keys:
        img = frame(A, w, t, lambda cv, tt: None, [("exusiai", (B.SQUAD[0] - 30, B.SQUAD[1] - 28), "atk" if t < 1.0 else "run"), ("texas", B.SQUAD, "run")]).convert("RGBA")
        cv = B.Canvas(img)
        if t < 1.0:
            cv = ghost(cv, A, "exusiai", (S[0] - 10, S[1] - 40), (S[0] - 10, S[1] - 40), 1.0, EX)
        lane(cv, t)
        tracers(cv, t)
        if 0.9 <= t < 1.1:
            k = (t - 0.9) / 0.2
            crate(cv, (drop[0], drop[1] - 150 * (1 - k)), k, 0)
        elif 1.1 <= t < 1.6:
            k = (t - 1.1) / 0.5
            if k < 0.08:
                crate(cv, drop, 1, 1)
            blast_ring(cv, drop, min(1, k * 1.6), TX)
            crate_burst(cv, drop, k)
        if 0.85 <= t < 1.1:   # 德克萨斯残影冲去接应（不画斩线）
            cv = ghost(cv, A, "texas", P(L0), (drop[0] - 30, drop[1]), (t - 0.85) / 0.2, TX)
        out.append((cv.finish(), lab, (150, 60, 620, 320)))
    return out


def lattice(cv, c, r, k, t, sweep):
    """灯格（灯下审决主形）：提灯的窗格投到地上，变成一张压扁的方格光网（只画格线和交点，不铺底色）；
    格线流明钢蓝、交点艾丽妮紫亮点；sweep 0..1 = 审判时一行一行从远到近闪白；k > 0.75 后格线断开"""
    cell = 18
    al = min(1.0, k * 3)
    brk = max(0.0, (k - 0.75) / 0.25)
    for gy in range(-r, r + 1, cell):
        for gx in range(-r, r + 1):
            if gx * gx + (gy) * (gy) > r * r:
                continue
            if brk > 0 and (gx * 13 + gy) % 10 < brk * 9:
                continue
            hot = sweep > 0 and abs((gy + r) / (2 * r) - sweep) < 0.12
            cv.cell(c[0] + gx, c[1] + gy * SQ, (255, 255, 255) if hot else LM[4], al)
    for gx in range(-r, r + 1, cell):
        for gy in range(-r, r + 1):
            if gx * gx + gy * gy > r * r:
                continue
            if brk > 0 and (gy * 13 + gx) % 10 < brk * 9:
                continue
            hot = sweep > 0 and abs((gy + r) / (2 * r) - sweep) < 0.12
            cv.cell(c[0] + gx, c[1] + gy * SQ, (255, 255, 255) if hot else LM[3], al)
    for gy in range(-r, r + 1, cell):
        for gx in range(-r, r + 1, cell):
            if gx * gx + gy * gy > r * r:
                continue
            p = (c[0] + gx, c[1] + gy * SQ)
            for d in ((0, 0), (1, 0), (-1, 0), (0, 1), (0, -1)):
                cv.cell(p[0] + d[0], p[1] + d[1], IR[5] if d == (0, 0) else IR[3], al)
            if (gx + gy) % (cell * 2) == 0:
                cv.glow(*p, gl(IR[4]), 0.5 * al)


def big_lantern(cv, p, k):
    """头顶提灯（灯下审决起手，帧条）：一盏 22×30 美术像素的提灯在圈心上空亮起，灯框流明钢蓝、灯芯白、四面窗格"""
    w, h = 22, 30
    x0, y0 = int(p[0] - w / 2), int(p[1] - h)
    for y in range(h):
        for x in range(w):
            frame = x in (0, 1, w - 2, w - 1) or y in (0, 1, h - 2, h - 1) or x in (10, 11) or y in (14, 15)
            if frame:
                cv.cell(x0 + x, y0 + y, LM[3] if (x + y) % 5 else LM[4])
            else:
                d = math.hypot(x - w / 2, y - h / 2) / (w / 2)
                cv.cell(x0 + x, y0 + y, (255, 255, 255) if d < 0.35 else (IR[5] if d < 0.6 else LM[5]), min(1.0, k * 2))
    for x in range(-4, 5):
        cv.cell(p[0] + x, y0 - 2, LM[3])
    cv.cell(p[0], y0 - 4, LM[4])
    cv.glow(p[0], y0 + h / 2, (0.85, 0.9, 1.0), 3.0 * k)


def pair_inq(A):
    w = B.World(37, A)
    C = (420, 196)
    R = 130
    w.kill_circle(1.15, C, R, SQ)

    keys = [(0.35, "起手：圈心上空亮起一盏大提灯（新帧条），流明举灯"), (0.7, "投影：灯的窗格投到地上，变成一张方格光网（新帧条）"),
            (1.05, "审判：光网从远到近一行行闪白，艾丽妮残影从灯下贯穿而过"), (1.45, "余韵：格线断开、交点紫光上飘，网里清空")]
    out = []
    for t, lab in keys:
        img = frame(A, w, t, lambda cv, tt: None, [("lumen", (B.SQUAD[0] - 34, B.SQUAD[1] - 26), "atk"), ("irene", B.SQUAD, "run")]).convert("RGBA")
        cv = B.Canvas(img)
        if t < 1.25:
            big_lantern(cv, (C[0], C[1] - 90), min(1.0, (t - 0.15) / 0.2))
        if t >= 0.5:
            k = min(1.0, (t - 0.5) / 1.0)
            sweep = (t - 0.95) / 0.25 if 0.95 <= t < 1.2 else 0
            lattice(cv, C, R, k, t, sweep)
        if 0.95 <= t < 1.2:
            cv = ghost(cv, A, "irene", (C[0] - R, C[1] + 20), (C[0] + R, C[1] - 10), (t - 0.95) / 0.15, IR)
        out.append((cv.finish(), lab, (230, 30, 620, 300)))
    return out


PAIRS = {"rival": ("宿敌 · 十字旧怨", pair_rival), "penguin": ("企鹅物流 · 急件航线", pair_penguin), "inq": ("灯下审决 · 提灯宣判", pair_inq)}


def sheet(title, keys, sc):
    font = ImageFont.truetype(B.FONTB, 15 * sc)
    fs = ImageFont.truetype(B.FONT, 11 * sc)
    cw, ch = 0, 0
    crops = []
    for img, lab, box in keys:
        c = img.crop(box)
        if sc > 1:
            c = c.resize((c.width * sc, c.height * sc), Image.NEAREST)
        crops.append((c, lab))
        cw = max(cw, c.width)
        ch = max(ch, c.height)
    gap = 6 * sc
    out = Image.new("RGB", (cw * 2 + gap * 3, 34 * sc + (ch + 22 * sc) * 2 + gap * 2), (12, 12, 16))
    d = ImageDraw.Draw(out)
    d.text((gap, 8 * sc), title + "  ·  新画面构思关键帧（Python 草图，非实机；1 美术像素 = %d 像素）" % sc, fill=(235, 235, 235), font=font)
    for i, (c, lab) in enumerate(crops):
        x = gap + (i % 2) * (cw + gap)
        y = 34 * sc + (i // 2) * (ch + 22 * sc + gap)
        out.paste(c, (x, y))
        d.text((x, y + ch + 4 * sc), "%d  %s" % (i + 1, lab), fill=(200, 200, 200), font=fs)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join(MAIN, "Claude outputs", "bond_v2_1106", "concept"))
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    A = B.load_assets()
    for key, (title, fn) in PAIRS.items():
        keys = fn(A)
        for sc in (1, 2):
            p = os.path.join(a.out, "bond2_concept_%s_%dx.png" % (key, sc))
            sheet(title, keys, sc).save(p)
            print(p)


if __name__ == "__main__":
    main()
