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


def pair_rival(A):
    w = B.World(11, A)
    C = (430, 192)
    L = 250
    d1 = (math.cos(math.radians(28)), math.sin(math.radians(28)) * 0.75)
    d2 = (math.cos(math.radians(-28)), math.sin(math.radians(-28)) * 0.75)
    a1, c1 = (C[0] - d1[0] * L, C[1] - d1[1] * L), (C[0] + d1[0] * L, C[1] + d1[1] * L)
    a2, c2 = (C[0] - d2[0] * L, C[1] - d2[1] * L), (C[0] + d2[0] * L, C[1] + d2[1] * L)
    w.kill_seg(0.3, 0.1, a1, c1, 40)
    w.kill_seg(0.5, 0.1, a2, c2, 40)
    w.kill_circle(0.82, C, 95)
    sp = B.Sparks()
    rng = random.Random(4)
    PT, PL = pal(TX), pal(LP)

    def fx(cv, t):
        if t >= 0.25:
            B.slash(cv, a1, c1, t, 0.25, 0.12, 0.8, 0.4, PT, 3)
        if t >= 0.47:
            B.slash(cv, a2, c2, t, 0.47, 0.12, 0.6, 0.4, PL, 3)
        if 0.95 <= t:
            scorch_x(cv, (C[0], C[1] + 6), 110, min(1.0, (t - 0.95) / 0.6), TX, LP)
        if 0.78 <= t < 0.95:   # 新帧条：交锋十字（两道弧形刀光在交点对撞 → 两色星芒）
            k = (t - 0.78) / 0.17
            crescent(cv, (C[0] - 8, C[1] - 4), 62, math.radians(200), math.radians(340), 6, TX, min(1, k * 1.6))
            crescent(cv, (C[0] + 8, C[1] + 22), 62, math.radians(160), math.radians(20), 6, LP, min(1, k * 1.6))
            if k > 0.45:
                clash_star(cv, (C[0], C[1] - 14), 44, TX, LP)
                cv.lamp(C[0], C[1], 110, (255, 220, 200), 55)
        if 0.95 <= t < 1.4:
            shards(cv, (C[0], C[1] - 14), (t - 0.95) / 0.45, TX, LP)

    keys = [(0.32, "起手：两人残影沿两道斩线交错冲过（代码画）"), (0.86, "主冲击：交点两道弧刃对撞（新帧条）"),
            (1.08, "余韵：碎刃四散 + 地上交叉焦痕（新帧条）"), (1.45, "收尾：焦痕冷却断开，十字里的怪清空")]
    out = []
    for t, lab in keys:
        cv0 = B.Canvas(B.background().convert("RGBA"))
        img = frame(A, w, t, lambda cv, tt: None, [("lappland", (B.SQUAD[0] - 34, B.SQUAD[1] - 26), "run"), ("texas", B.SQUAD, "run")]).convert("RGBA")
        cv = B.Canvas(img)
        if 0.22 <= t < 0.45:
            cv = ghost(cv, A, "texas", a1, c1, (t - 0.22) / 0.18, TX)
        fx(cv, t)
        out.append((cv.finish(), lab, (250, 70, 610, 320)))
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

    keys = [(0.6, "起手：能天使残影跃起，一路扫射标出航线（代码画）"), (1.05, "主冲击前：急件箱从高处坠向航线尽头（新帧条）"),
            (1.2, "主冲击：箱子落地炸开，琥珀爆光 + 木板四散（新帧条）"), (1.4, "余韵：贴地冲击环 + 两团暗烟（新帧条），德克萨斯残影沿线斩过")]
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
        if t >= 1.3:
            cv = ghost(cv, A, "texas", P(L0), P(L1), (t - 1.3) / 0.2, TX)
            B.slash(cv, P(L0), P(L1), t, 1.32, 0.08, 0.5, 0.3, pal(TX), 2)
        out.append((cv.finish(), lab, (150, 60, 620, 320)))
    return out


def pair_inq(A):
    w = B.World(37, A)
    C = (420, 196)
    R = 120
    for i, a in enumerate((-12, 48, 108)):
        d = (math.cos(math.radians(a)), math.sin(math.radians(a)) * SQ)
        w.kill_seg(0.55 + 0.17 * i, 0.08, (C[0] - d[0] * (R + 30), C[1] - d[1] * (R + 30)), (C[0] + d[0] * (R + 30), C[1] + d[1] * (R + 30)), 22)
    w.kill_circle(1.28, C, R, SQ)
    PI = pal(IR)

    def lamp_ring(cv, t, k):
        n = int(R * 6.6)
        for i in range(n):
            a = i / n * math.tau + t * 0.2
            seg = (a % (math.tau / 10)) / (math.tau / 10)
            if seg < 0.72:
                cv.cell(C[0] + math.cos(a) * R * k, C[1] + math.sin(a) * R * k * SQ, LM[5] if seg < 0.5 else LM[4])

    keys = [(0.4, "起手：流明举灯，钢蓝光圈张开（代码画）"), (0.78, "三刺：艾丽妮残影沿刺线贯穿光圈（代码画）"),
            (1.3, "主冲击：审判光柱从天砸进圈心，灯印亮起（新帧条）"), (1.6, "余韵：灯印放射刻度断开，光尘上飘，圈内清空")]
    out = []
    for t, lab in keys:
        img = frame(A, w, t, lambda cv, tt: None, [("lumen", (B.SQUAD[0] - 34, B.SQUAD[1] - 26), "atk"), ("irene", B.SQUAD, "run")]).convert("RGBA")
        cv = B.Canvas(img)
        if t < 1.25:
            cv.lamp(C[0], C[1], R, (90, 160, 220), 18, SQ)
            lamp_ring(cv, t, min(1, (t - 0.05) / 0.3))
        for i, a in enumerate((-12, 48, 108)):
            d = (math.cos(math.radians(a)), math.sin(math.radians(a)) * SQ)
            p0, p1 = (C[0] - d[0] * (R + 30), C[1] - d[1] * (R + 30)), (C[0] + d[0] * (R + 30), C[1] + d[1] * (R + 30))
            ts = 0.55 + 0.17 * i
            B.slash(cv, p0, p1, t, ts, 0.06, 0.3, 0.2, PI, 3)
            if 0 <= t - ts < 0.15:
                cv = ghost(cv, A, "irene", p0, p1, (t - ts) / 0.1, IR)
        if t >= 1.2:
            k = min(1, (t - 1.2) / 0.5)
            seal(cv, C, R * 0.85, k, t)
            pillar(cv, (C[0], C[1]), k, top=0)
        out.append((cv.finish(), lab, (230, 40, 620, 300)))
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
