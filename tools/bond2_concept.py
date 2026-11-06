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


def half_diamond(cv, c, r, side, R, thick=5, brk=0.0):
    """半边菱形冲击波：side = -1 往左推（尖朝左，琥珀），+1 往右推（尖朝右，淡紫）；两臂从中线上下两点连到尖端"""
    tip = (c[0] + side * r, c[1])
    for arm in (-1, 1):
        st = (c[0], c[1] + arm * r * SQ)
        n = int(math.dist(st, tip)) + 1
        for i in range(n + 1):
            u = i / n
            if brk > 0 and (i * 7) % 10 < brk * 9:
                continue
            x = st[0] + (tip[0] - st[0]) * u
            y = st[1] + (tip[1] - st[1]) * u
            th = max(1, round(thick * (0.5 + 0.5 * u)))
            for j in range(th):
                q = j / max(1, th)
                col = (255, 255, 255) if q < 0.34 and brk < 0.3 else (R[5] if q < 0.67 else R[4])
                cv.cell(x - side * j, y, col)
            cv.cell(x - side * th, y, R[2])
            if i % 4 == 0 and brk < 0.5:
                cv.glow(x, y, gl(R[5]), 0.7)


def diamond_spark(cv, c, s, RA, RB):
    """刀锋相交的菱形火花：实心菱形（左半琥珀、右半淡紫，芯白）+ 横向长尖、竖向短尖 + 楔形碎火星"""
    for dy in range(-s, s + 1):
        hw = int((s - abs(dy)) * 1.4)
        for dx in range(-hw, hw + 1):
            q = (abs(dx) / 1.4 + abs(dy)) / s
            R = RA if dx < 0 else RB
            col = (255, 255, 255) if q < 0.45 else (R[5] if q < 0.75 else R[4])
            cv.cell(c[0] + dx, c[1] + dy * 0.8, col)
    for i in range(s * 3):
        k = i / (s * 3)
        cv.cell(c[0] - s * 1.4 - i, c[1], RA[5] if k < 0.5 else RA[4])
        cv.cell(c[0] + s * 1.4 + i, c[1], RB[5] if k < 0.5 else RB[4])
    for i in range(int(s * 1.2)):
        cv.cell(c[0], c[1] - s * 0.8 - i, (255, 255, 255) if i < 4 else RA[5])
        cv.cell(c[0], c[1] + s * 0.8 + i, (255, 255, 255) if i < 4 else RB[5])
    cv.glow(c[0], c[1], (1, 0.95, 0.9), 4.0)


def wedges(cv, c, k, RA, RB):
    rng = random.Random(7)
    for i in range(18):
        side = -1 if i % 2 == 0 else 1
        a = rng.uniform(-0.9, 0.9) + (math.pi if side < 0 else 0)
        sp = rng.uniform(60, 140)
        x = c[0] + math.cos(a) * sp * k
        y = c[1] + math.sin(a) * sp * k * 0.7 + 50 * k * k
        R = RA if side < 0 else RB
        for t in range(4):
            for u in range(4 - t):
                cv.cell(x + side * u, y + t - 2, R[5] if t == 0 else R[3])


def pair_rival(A):
    w = B.World(11, A)
    C = (430, 196)
    for e in w.es:   # 余波扫到哪只哪只倒：菱形距离 d（|dx| + |dy| / SQ）对上冲击波半径 30 + 190k
        p = w.pos(e, 0.7)
        d = math.hypot(p[0] - C[0], (p[1] - C[1]) / SQ)   # 第五轮：圆形冲击波
        if d <= 220:
            e["kt"] = 0.6 if d < 34 else 0.72 + (d - 30) / 190 * 0.5
    TXp, LPp = (C[0] - 26, C[1] + 22), (C[0] + 26, C[1] + 22)

    keys = [(0.3, "冲上：两人残影从两侧相向冲进怪群（各自攻击帧）"), (0.62, "相交定格：刀锋相撞停一拍，交点两色星芒（左琥珀 / 右淡紫）"),
            (0.85, "余波：冲击波从交锋点向四周散开（左半琥珀、右半淡紫），扫到即倒"), (1.4, "收尾：冲击波断开，火星落地，两人残影淡出，圈里清空")]
    out = []
    for t, lab in keys:
        img = frame(A, w, t, lambda cv, tt: None, [("lappland", (B.SQUAD[0] - 34, B.SQUAD[1] - 26), "run"), ("texas", B.SQUAD, "run")]).convert("RGBA")
        cv = B.Canvas(img)
        if t < 0.55:
            u = min(1.0, t / 0.5)
            cv = ghost(cv, A, "texas", (C[0] - 230, C[1] + 22), TXp, u, TX)
            cv = ghost(cv, A, "lappland", (C[0] + 230, C[1] + 22), LPp, u, LP)
        else:
            im = cv.finish().convert("RGBA")
            al = 1.0 if t < 1.0 else max(0.0, 1 - (t - 1.0) / 0.4)
            B.put_op(im, A["texas_atk"][5], TXp, False, al)
            B.put_op(im, A["lappland_atk"][5], LPp, True, al)
            cv = B.Canvas(im)
        if 0.55 <= t < 0.72:
            clash_star(cv, (C[0], C[1] - 10), 34, TX, LP)
            cv.lamp(C[0], C[1], 140, (255, 225, 210), 55)
        if t >= 0.72:
            k = min(1.0, (t - 0.72) / 0.5)
            r = 30 + 190 * k
            brk = max(0.0, (k - 0.6) / 0.4)
            shock_ring(cv, (C[0], C[1]), r, k, TX, LP)
            wedges(cv, (C[0], C[1] - 10), k, TX, LP)
        out.append((cv.finish(), lab, (180, 50, 680, 330)))
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


# ---------------------------------------------------------------- 11-06 第四轮：企鹅物流开车 / 灯下审决两个新方向

CAR = ramp(["#0e1014", "#1c2028", "#2e3440", "#48505e", "#6c7686"])   # 车身深灰（不是原作涂装，草图用）


def car(cv, p, ang, k_bounce=0):
    """俯视 3/4 小车（56×30 美术像素）：深灰车身、琥珀腰线（德克萨斯）、红橙车顶灯（能天使）、四个轮子"""
    w, h = 56, 30
    ca, sa = math.cos(ang), math.sin(ang)

    def put(x, y, col):
        X = p[0] + (x - w / 2) * ca - (y - h / 2) * sa * SQ
        Y = p[1] + (x - w / 2) * sa + (y - h / 2) * ca * SQ - k_bounce
        cv.cell(X, Y, col)

    for y in range(h):
        for x in range(w):
            rx, ry = abs(x - w / 2 + 0.5) / (w / 2), abs(y - h / 2 + 0.5) / (h / 2)
            if rx > 0.92 and ry > 0.75:
                continue
            col = CAR[2]
            if rx > 0.9 or ry > 0.85:
                col = CAR[0]
            elif ry < 0.55 and (x / w) >= 0.62:
                col = CAR[4] if (x + y) % 6 else (200, 220, 235)   # 挡风玻璃（朝前）
            elif ry < 0.5:
                col = CAR[3]
            if abs(y - h / 2) in (9, 10) and rx < 0.85:
                col = TX[4]
            put(x, y, col)
    for wx in (8, w - 14):
        for wy in (-2, h - 1):
            for dx in range(6):
                for dy in range(3):
                    put(wx + dx, wy + dy, (14, 14, 16))
    for dx in range(4):
        put(w * 0.35 + dx, h / 2 - 1, EX[4])
        put(w * 0.35 + dx, h / 2, EX[5])


def skid(cv, pts, k):
    for i in range(1, len(pts)):
        a, b = pts[i - 1], pts[i]
        n = int(math.dist(a, b)) + 1
        for j in range(n):
            u = j / n
            x, y = a[0] + (b[0] - a[0]) * u, a[1] + (b[1] - a[1]) * u
            if k > 0.5 and (i * 31 + j) % 7 < (k - 0.5) * 10:
                continue
            for o in (-10, 10):
                cv.cell(x, y + o * SQ, (20, 18, 16), 0.9)


def dust(cv, p, k, seed):
    rng = random.Random(seed)
    for i in range(6):
        ox, oy = rng.uniform(-30, -10), rng.uniform(-6, 6)
        rr = 3 + 7 * k
        for yy in range(-int(rr), int(rr) + 1):
            for xx in range(-int(rr), int(rr) + 1):
                if xx * xx + yy * yy <= rr * rr and (xx + yy) % 2 == 0:
                    cv.cell(p[0] + ox + xx - 20 * k, p[1] + oy + yy - 6 * k, SMOKE[3] if yy < 0 else SMOKE[2], 0.7 * (1 - k))


def pair_penguin_car(A):
    w = B.World(23, A)
    path = [(120, 250), (260, 225), (400, 200), (520, 190), (600, 160)]
    seg = [math.dist(path[i], path[i + 1]) for i in range(len(path) - 1)]

    def at(u):
        s = u * sum(seg)
        for i, l in enumerate(seg):
            if s <= l or i == len(seg) - 1:
                f = min(1.0, s / l)
                return (path[i][0] + (path[i + 1][0] - path[i][0]) * f, path[i][1] + (path[i + 1][1] - path[i][1]) * f), math.atan2(path[i + 1][1] - path[i][1], path[i + 1][0] - path[i][0])
            s -= l
        return path[-1], 0.0

    T0, T1 = 0.2, 1.3
    for e in w.es:   # 碾过：车身 38 内；车顶扫射：95 内三只里倒一只
        for i in range(60):
            u = i / 59
            p, _ = at(u)
            d = math.dist(p, w.pos(e, T0 + u * (T1 - T0)))
            if d < 38 or (d < 95 and int(e["p0"][0] * 7 + e["p0"][1]) % 3 == 0):
                e["kt"] = T0 + u * (T1 - T0) + (0.0 if d < 38 else 0.08)
                break
    keys = [(0.35, "上车：德克萨斯开车冲进怪群，能天使站在车顶"), (0.75, "碾过 + 扫射：车身撞开挡路的，能天使朝四周一圈开枪"),
            (1.15, "甩尾：车头一摆，扬起尘土，车后两道胎痕"), (1.55, "收尾：车开出画面，胎痕留在清空的路上")]
    out = []
    for t, lab in keys:
        img = frame(A, w, t, lambda cv, tt: None, []).convert("RGBA")
        cv = B.Canvas(img)
        u = min(1.0, max(0.0, (t - T0) / (T1 - T0)))
        trail = [at(i / 40 * u)[0] for i in range(41)]
        if u > 0.02:
            skid(cv, trail, max(0.0, (t - 1.3) / 0.5))
        if t < 1.45:
            p, ang = at(u)
            if t > 1.0:
                ang += 0.35 * min(1.0, (t - 1.0) / 0.15)
            dust(cv, p, (t * 3) % 1, int(t * 15))
            car(cv, p, ang, 2 if int(t * 15) % 2 else 0)
            im = cv.finish().convert("RGBA")
            B.put_op(im, A["texas_run"][0], (p[0] + 6, p[1] - 4), False, 1.0)
            B.put_op(im, A["exusiai_atk"][int(t * 12) % 8], (p[0] - 8, p[1] - 20), False, 1.0)
            cv = B.Canvas(im)
            if 0.4 <= t < 1.2:   # 车顶一圈扫射：8 个方向
                src = (p[0] - 8, p[1] - 40)
                for k in range(8):
                    a = k / 8 * math.tau + t * 6
                    for j in range(18):
                        cv.cell(src[0] + math.cos(a) * (24 + j), src[1] + math.sin(a) * (24 + j) * SQ, EX[6] if j < 4 else EX[4], 1 - j / 20)
                    cv.glow(src[0] + math.cos(a) * 24, src[1] + math.sin(a) * 24 * SQ, gl(EX[5]), 1.0)
        out.append((cv.finish(), lab, (80, 60, 640, 330)))
    return out


def silhouette(spr, R, stretch=3.2, ang=-20):
    """人影：本人帧做成平涂剪影（艾丽妮暗紫 + 一格亮紫描边），拉长、斜躺在地上"""
    a = np.asarray(spr).copy()
    m = a[..., 3] > 40
    out = np.zeros_like(a)
    out[m] = (*R[1], 220)
    edge = m & ~(np.roll(m, 1, 0) & np.roll(m, -1, 0) & np.roll(m, 1, 1) & np.roll(m, -1, 1))
    out[edge] = (*R[4], 255)
    im = Image.fromarray(out).resize((spr.width, max(1, int(spr.height * stretch))), Image.NEAREST)
    return im.rotate(ang, expand=True, resample=Image.NEAREST)


def pair_inq_shadow(A):
    w = B.World(37, A)
    L = (300, 230)
    for e in w.es:
        p = w.pos(e, 1.0)
        if 330 < p[0] < 620 and abs((p[1] - 215)) < 60:
            e["kt"] = 1.3 + (p[0] - 330) / 1500
    keys = [(0.35, "灯起：流明在怪群边上举灯，艾丽妮站进灯光里"), (0.7, "灯下之影：灯把艾丽妮的影子拉长，横躺着压过一大片怪"),
            (1.05, "审决：影子跟本人同步挥剑，影子盖住的怪头顶亮紫印"), (1.45, "收尾：灯一闪熄，影子收回，被影子压过的一片同时倒下")]
    out = []
    for t, lab in keys:
        img = frame(A, w, t, lambda cv, tt: None, []).convert("RGBA")
        cv = B.Canvas(img)
        cv.lamp(L[0] - 30, L[1] - 30, 160, (120, 180, 230), 30 if t < 1.3 else 60)
        im = cv.finish().convert("RGBA")
        if 0.5 <= t < 1.4:
            fr = A["irene_atk"][4 if t < 0.95 else 6]
            st = 4.2 if t < 1.25 else max(1.0, 4.2 - (t - 1.25) * 20)
            sh = silhouette(fr, IR, st, -90)
            im.alpha_composite(sh, (int(L[0] + 14), int(L[1] - sh.height * 0.5)))
        B.put_op(im, A["lumen_atk"][2], (L[0] - 40, L[1] - 10))
        B.put_op(im, A["irene_atk"][4 if t < 0.95 else 6], (L[0] + 4, L[1] + 4))
        cv = B.Canvas(im)
        if 0.95 <= t < 1.32:
            for e in w.es:
                if e["kt"] and e["kt"] > t:
                    p = w.pos(e, t)
                    for d in ((0, 0), (1, 0), (-1, 0), (0, 1), (0, -1)):
                        cv.cell(p[0] + d[0], p[1] - 22 + d[1], IR[5] if d == (0, 0) else IR[3])
        out.append((cv.finish(), lab, (180, 60, 660, 320)))
    return out


def lantern_small(cv, p, lit):
    for y in range(12):
        for x in range(8):
            fr = x in (0, 7) or y in (0, 11)
            cv.cell(p[0] - 4 + x, p[1] - 12 + y, LM[3] if fr else ((255, 255, 255) if lit and 2 < y < 9 and 2 < x < 5 else (LM[5] if lit else LM[1])))
    for y in range(10):
        cv.cell(p[0], p[1] + y, LM[2])
    if lit:
        cv.glow(p[0], p[1] - 6, gl(LM[5]), 2.0)


def pair_inq_lamps(A):
    w = B.World(37, A)
    C = (420, 196)
    R = 140
    pts = [(C[0] + math.cos(-math.pi / 2 + i / 7 * math.tau) * R, C[1] + math.sin(-math.pi / 2 + i / 7 * math.tau) * R * SQ) for i in range(7)]
    w.kill_circle(1.1, C, R * 0.9, SQ)
    keys = [(0.45, "布灯：七盏提灯沿圈插在地上，一盏接一盏点亮"), (0.8, "连线：七灯点齐，灯与灯之间连成一个七角星（流明钢蓝）"),
            (1.05, "审决：七角星一闪白，艾丽妮残影从星心贯穿，星里的怪受审"), (1.6, "收尾：灯熄，星线断开，星里清空")]
    out = []
    for t, lab in keys:
        img = frame(A, w, t, lambda cv, tt: None, [("lumen", (B.SQUAD[0] - 34, B.SQUAD[1] - 26), "atk"), ("irene", B.SQUAD, "run")]).convert("RGBA")
        cv = B.Canvas(img)
        nlit = min(7, int((t - 0.2) / 0.07) + 1) if t >= 0.2 else 0
        if t >= 0.72:
            k = min(1.0, (t - 0.72) / 0.1)
            brk = max(0.0, (t - 1.25) / 0.3)
            for i in range(7):
                a, b = pts[i], pts[(i + 3) % 7]
                D = math.dist(a, b)
                for j in range(int(D * k)):
                    if brk and (j * 7 + i) % 10 < brk * 9:
                        continue
                    x = a[0] + (b[0] - a[0]) * j / D
                    y = a[1] + (b[1] - a[1]) * j / D
                    hot = 1.0 <= t < 1.12
                    cv.cell(x, y, (255, 255, 255) if hot else LM[5])
                    cv.cell(x, y + 1, IR[3] if hot else LM[2])
                    if j % 6 == 0:
                        cv.glow(x, y, gl(LM[5] if not hot else IR[5]), 0.6)
        for i, p in enumerate(pts):
            lantern_small(cv, p, i < nlit and t < 1.35)
        if 1.0 <= t < 1.2:
            cv = ghost(cv, A, "irene", (C[0] - R, C[1]), (C[0] + R, C[1]), (t - 1.0) / 0.15, IR)
        out.append((cv.finish(), lab, (230, 50, 620, 320)))
    return out


# ---------------------------------------------------------------- 11-06 第五轮：对砍冲击波散开 / 立体车 / 灯塔照海

def shock_ring(cv, c, r, k, RA, RB):
    """对砍余波：从交锋点向外散开的冲击波——粗环（左半琥珀、右半淡紫，芯白）+ 外侧一圈淡的气浪 + 贴地尘环；k > 0.6 后断开"""
    brk = max(0.0, (k - 0.6) / 0.4)
    for rr, th, dim in ((r, 5, 1.0), (r * 1.12, 2, 0.45)):
        n = int(rr * 7)
        for i in range(n):
            if brk and (i * 7) % 10 < brk * 10:
                continue
            a = i / n * math.tau
            R = RA if math.cos(a) < 0 else RB
            for j in range(th):
                x = c[0] + math.cos(a) * (rr - j)
                y = c[1] + math.sin(a) * (rr - j) * SQ
                q = j / th
                col = (255, 255, 255) if q < 0.3 and dim == 1.0 and k < 0.4 else (R[5] if q < 0.6 else R[4])
                cv.cell(x, y, col, dim)
            if i % 6 == 0 and dim == 1.0 and brk < 0.5:
                cv.glow(c[0] + math.cos(a) * rr, c[1] + math.sin(a) * rr * SQ, gl(R[5]), 0.7)
    n = int(r * 0.9 * 6)   # 贴地尘环（暗，紧跟在后）
    for i in range(n):
        if (i * 3) % 5 == 0:
            continue
        a = i / n * math.tau
        cv.cell(c[0] + math.cos(a) * r * 0.88, c[1] + math.sin(a) * r * 0.88 * SQ + 2, SMOKE[2], 0.8 * (1 - k))


def car3(cv, p, ang_k, bounce=0):
    """立体小车（俯视 3/4，72×50 美术像素）：车顶 + 车身侧面（朝镜头那面暗一档）+ 前后挡风玻璃 + 四个轮子 + 车顶警示灯；
    车身深灰、琥珀腰线（德克萨斯色）、红橙顶灯（能天使色）；ang_k = 甩尾时车头上翘的量（草图只做水平朝右）"""
    W_, D = 72, 22          # 车长、车宽（俯视深度）
    Hs = 16                 # 侧面高度
    x0 = int(p[0] - W_ / 2)
    yb = int(p[1] - bounce)  # 车底线
    skew = int(ang_k * 10)
    def px(x, y, c, a=1.0):
        cv.cell(x0 + x, y - (x * skew) // W_, c, a)
    # 影子
    for x in range(-2, W_ + 2):
        for y in range(4):
            px(x, yb + 2 + y, (10, 10, 12), 0.6)
    # 侧面（朝镜头）
    for x in range(W_):
        for y in range(Hs):
            col = CAR[1] if y > Hs - 4 else CAR[2]
            if y in (5, 6):
                col = TX[4] if 4 < x < W_ - 4 else CAR[2]
            if 14 < x < 30 and 1 <= y <= 4 or 34 < x < 52 and 1 <= y <= 4:
                col = (150, 180, 200) if (x + y) % 5 else (210, 230, 240)   # 侧窗
            if x in (0, W_ - 1):
                col = CAR[0]
            px(x, yb - y, col)
    # 车顶（往上、往后缩）
    for x in range(6, W_ - 10):
        for y in range(D):
            col = CAR[3] if y > 2 else CAR[4]
            if x > W_ - 22:
                col = (170, 200, 220) if (x + y) % 6 else (220, 235, 245)  # 前挡风（朝前）
            if x < 14:
                col = (120, 140, 160)   # 后窗
            px(x, yb - Hs - y + (D // 3) - 2, col)
    # 顶灯
    for dx in range(-3, 4):
        px(W_ // 2 - 6 + dx, yb - Hs - D + 4, EX[4] if abs(dx) < 2 else EX[3])
    cv.glow(x0 + W_ // 2 - 6, yb - Hs - D + 4, gl(EX[5]), 1.4)
    # 轮子
    for wx in (10, W_ - 18):
        for dx in range(10):
            for dy in range(6):
                r = math.hypot(dx - 4.5, (dy - 2.5) * 1.6)
                if r < 5:
                    px(wx + dx, yb + dy - 3, (16, 16, 18) if r > 2 else CAR[3])


def pair_penguin_car3(A):
    w = B.World(23, A)
    path_y = lambda x: 250 - (x - 120) * 0.17
    T0, T1 = 0.2, 1.3
    X0, X1 = 100, 640
    for e in w.es:
        for i in range(60):
            u = i / 59
            x = X0 + (X1 - X0) * u
            p = w.pos(e, T0 + u * (T1 - T0))
            d = math.hypot(p[0] - x, (p[1] - path_y(x)) / SQ)
            if d < 44 or (d < 110 and int(e["p0"][0] * 7 + e["p0"][1]) % 3 == 0):
                e["kt"] = T0 + u * (T1 - T0) + (0.0 if d < 44 else 0.08)
                break
    keys = [(0.35, "上车：德克萨斯开车冲进怪群，能天使站在车顶"), (0.75, "碾过 + 扫射：车撞开挡路的，能天使朝四周一圈开枪"),
            (1.15, "甩尾：车头一摆，扬起尘土"), (1.55, "收尾：车开远，胎痕留在清空的路上")]
    out = []
    for t, lab in keys:
        img = frame(A, w, t, lambda cv, tt: None, []).convert("RGBA")
        cv = B.Canvas(img)
        u = min(1.0, max(0.0, (t - T0) / (T1 - T0)))
        x = X0 + (X1 - X0) * u
        p = (x, path_y(x))
        trail = [(X0 + (x - X0) * i / 40, path_y(X0 + (x - X0) * i / 40)) for i in range(41)]
        if u > 0.02:
            skid(cv, trail, max(0.0, (t - 1.3) / 0.5))
        if t < 1.45:
            dust(cv, (p[0] - 30, p[1]), (t * 3) % 1, int(t * 15))
            car3(cv, p, min(1.0, max(0.0, (t - 1.0) / 0.15)) if t > 1.0 else 0.0, 2 if int(t * 15) % 2 else 0)
            im = cv.finish().convert("RGBA")
            B.put_op(im, A["texas_run"][0], (p[0] + 12, p[1] - 30), False, 1.0)     # 驾驶位（从侧窗露出上半身，草图直接叠在车顶前部）
            B.put_op(im, A["exusiai_atk"][int(t * 12) % 8], (p[0] - 8, p[1] - 44), False, 1.0)
            cv = B.Canvas(im)
            if 0.4 <= t < 1.2:
                src = (p[0] - 8, p[1] - 66)
                for k in range(8):
                    a = k / 8 * math.tau + t * 6
                    for j in range(20):
                        cv.cell(src[0] + math.cos(a) * (22 + j), src[1] + math.sin(a) * (22 + j) * SQ, EX[6] if j < 4 else EX[4], 1 - j / 22)
                    cv.glow(src[0] + math.cos(a) * 22, src[1] + math.sin(a) * 22 * SQ, gl(EX[5]), 1.0)
        out.append((cv.finish(), lab, (80, 40, 640, 330)))
    return out


def lighthouse(cv, p, k):
    """灯塔虚像（流明身后升起，32×110 美术像素）：钢蓝塔身、白芯灯室；k 0..1 升起 + 亮"""
    h = int(110 * min(1.0, k * 1.5))
    for y in range(h):
        wd = 7 + int((y / 110) * 6)
        for x in range(-wd, wd + 1):
            band = (y // 14) % 2 == 0
            col = LM[3] if band else LM[2]
            if abs(x) == wd:
                col = LM[4]
            cv.cell(p[0] + x, p[1] - y + (110 - h) * 0, col, 0.85)
    if k > 0.4:
        for y in range(12):
            for x in range(-9, 10):
                d = math.hypot(x, (y - 6) * 1.3) / 10
                cv.cell(p[0] + x, p[1] - 110 - y, (255, 255, 255) if d < 0.4 else (LM[5] if d < 0.8 else LM[4]))
        cv.glow(p[0], p[1] - 116, (0.9, 0.95, 1.0), 4.0)


def sweep_beam(cv, o, ang, R, spread=0.28):
    """旋转灯塔光束：从灯室发出的一道扇形光（只画两条边缘亮线 + 稀疏光尘，不铺底），贴地压扁"""
    for side in (-1, 1):
        a = ang + side * spread / 2
        for j in range(int(R)):
            x, y = o[0] + math.cos(a) * j, o[1] + math.sin(a) * j * SQ
            cv.cell(x, y, LM[5] if j < R * 0.7 else LM[4], 0.9)
            if j % 8 == 0:
                cv.glow(x, y, gl(LM[5]), 0.5)
    rng = random.Random(int(ang * 100))
    for i in range(70):
        j = rng.uniform(20, R)
        a = ang + rng.uniform(-spread / 2, spread / 2)
        cv.cell(o[0] + math.cos(a) * j, o[1] + math.sin(a) * j * SQ, (255, 255, 255) if i % 5 == 0 else LM[5], 0.8)


def pair_inq_lighthouse(A):
    w = B.World(37, A)
    O = (300, 230)
    R = 330
    A0, A1 = -1.2, 0.9   # 光束从左上扫到右下（弧度）
    for e in w.es:
        p = w.pos(e, 0.8)
        d = math.hypot(p[0] - O[0], (p[1] - O[1]) / SQ)
        a = math.atan2((p[1] - O[1]) / SQ, p[0] - O[0])
        if d < R and A0 <= a <= A1:
            e["kt"] = 0.45 + (a - A0) / (A1 - A0) * 0.7 + 0.05
    keys = [(0.3, "点灯：流明身后升起灯塔虚像（「伊比利亚之眼」），灯室亮起"), (0.7, "照海：灯塔光束扫过怪群，被照到的怪头顶亮紫印"),
            (0.95, "守岸：艾丽妮残影追着光束一路刺过，照到的逐个受审倒下"), (1.4, "收尾：光束扫完熄灭，灯塔虚像淡去，扇形里清空")]
    out = []
    for t, lab in keys:
        img = frame(A, w, t, lambda cv, tt: None, [("lumen", (O[0] - 30, O[1] + 10), "atk"), ("irene", (O[0] - 60, O[1] + 30), "run")]).convert("RGBA")
        cv = B.Canvas(img)
        k = min(1.0, t / 0.35) * (1 - max(0.0, (t - 1.25) / 0.3))
        lighthouse(cv, (O[0] - 6, O[1] - 4), k)
        if 0.4 <= t < 1.25:
            ang = A0 + (A1 - A0) * min(1.0, (t - 0.4) / 0.75)
            sweep_beam(cv, (O[0] - 6, O[1] - 30), ang, R)
            for e in w.es:
                if e["kt"] and t - 0.25 < e["kt"] and e["kt"] > t:
                    pp = w.pos(e, t)
                    a = math.atan2((pp[1] - O[1]) / SQ, pp[0] - O[0])
                    if a <= ang:
                        for d in ((0, 0), (1, 0), (-1, 0), (0, 1), (0, -1)):
                            cv.cell(pp[0] + d[0], pp[1] - 22 + d[1], IR[5] if d == (0, 0) else IR[3])
            if t >= 0.6:
                ang2 = A0 + (A1 - A0) * min(1.0, (t - 0.55) / 0.75)
                tip = (O[0] + math.cos(ang2) * R * 0.6, O[1] + math.sin(ang2) * R * 0.6 * SQ)
                cv = ghost(cv, A, "irene", (tip[0] - 40, tip[1]), tip, 1.0, IR)
        out.append((cv.finish(), lab, (170, 20, 660, 320)))
    return out


# ---------------------------------------------------------------- 11-06 第六轮：灯塔重画

ROCK = ramp(["#0c1014", "#1a2026", "#2a323a", "#3c4650"])


def lighthouse2(cv, p, k, al=0.92):
    """灯塔虚像（48×160 美术像素）：礁石底座 → 收分塔身（钢蓝两色横带、左亮右暗、一列小窗）→ 观景回廊（栏杆 + 外挑平台）
    → 灯室（四面窗格、白芯灯）→ 穹顶 + 风向针。k 0..1 = 从下往上显形；整体半透明（虚像），轮廓一格亮边"""
    base_y = p[1]
    H = 160
    vis = int(H * min(1.0, k * 1.4))
    def put(x, y, c, a=al):
        if y >= H - vis:
            cv.cell(p[0] + x, base_y - H + y, c, a)
    # 礁石底座（y 140..160）
    for y in range(140, 160):
        hw = 26 - (159 - y) // 2 + (3 if y > 152 else 0)
        for x in range(-hw, hw + 1):
            col = ROCK[2] if (x * 3 + y) % 7 else ROCK[3]
            if abs(x) >= hw - 1 or y == 159:
                col = ROCK[1]
            put(x, y, col)
    # 塔身（y 52..140，从 15 收到 10）
    for y in range(52, 140):
        hw = 10 + int((y - 52) / 88 * 6)
        band = ((y - 52) // 16) % 2 == 0
        for x in range(-hw, hw + 1):
            light = x < 0
            col = (LM[4] if light else LM[3]) if band else (LM[2] if light else LM[1])
            if abs(x) == hw:
                col = LM[5] if x < 0 else LM[2]
            put(x, y, col)
        if y in (70, 71, 72, 98, 99, 100, 124, 125, 126):
            for x in (-2, -1, 0, 1):
                put(x, y, (255, 230, 170) if k > 0.6 else LM[1])
    # 回廊平台（y 46..52）+ 栏杆（y 38..46）
    for y in range(46, 52):
        for x in range(-16, 17):
            put(x, y, LM[4] if y == 46 else LM[2])
    for y in range(38, 46):
        for x in range(-15, 16):
            if x % 3 == 0 or y == 38:
                put(x, y, LM[3])
    # 灯室（y 14..38）：四面窗格 + 灯芯
    for y in range(14, 38):
        for x in range(-9, 10):
            frame = abs(x) == 9 or y in (14, 37) or x in (-3, 3)
            if frame:
                put(x, y, LM[2])
            else:
                d = math.hypot(x, (y - 26) * 0.8) / 9
                lit = k > 0.6
                put(x, y, ((255, 255, 255) if d < 0.4 else (LM[5] if d < 0.75 else LM[4])) if lit else LM[1], 1.0)
    # 穹顶 + 风向针
    for y in range(4, 14):
        hw = 2 + (y - 4)
        for x in range(-hw, hw + 1):
            put(x, y, LM[3] if x < 0 else LM[2])
    for y in range(0, 4):
        put(0, y, LM[4])
    if k > 0.6:
        cv.glow(p[0], base_y - H + 26, (0.95, 0.97, 1.0), 5.0)


def beam_cone(cv, o, ang, R, spread=0.34):
    """旋转光锥：灯室发出的一束扇形光——两条亮边 + 中线 + 抖动点阵（棋盘格隔点画，不铺实心底），离灯越远越稀；贴地压扁"""
    for side in (-1, 0, 1):
        a = ang + side * spread / 2
        for j in range(int(R)):
            if side == 0 and j % 3:
                continue
            x, y = o[0] + math.cos(a) * j, o[1] + math.sin(a) * j * SQ
            cv.cell(x, y, (255, 255, 255) if side == 0 or j < R * 0.4 else LM[5], 0.9 if side else 0.7)
            if j % 10 == 0 and side:
                cv.glow(x, y, gl(LM[5]), 0.5)
    rng = random.Random(3)
    for i in range(int(R * 3)):
        j = rng.uniform(10, R)
        a = ang + rng.uniform(-spread / 2, spread / 2)
        if rng.random() > 1.1 - j / R:
            x, y = o[0] + math.cos(a) * j, o[1] + math.sin(a) * j * SQ
            if (int(x) + int(y)) % 2 == 0:
                cv.cell(x, y, LM[5], 0.55)


def pair_inq_lighthouse2(A):
    w = B.World(37, A)
    O = (300, 236)
    R = 330
    A0, A1 = -1.1, 0.85
    for e in w.es:
        p = w.pos(e, 0.8)
        d = math.hypot(p[0] - O[0], (p[1] - O[1]) / SQ)
        a = math.atan2((p[1] - O[1]) / SQ, p[0] - O[0])
        if d < R and A0 <= a <= A1:
            e["kt"] = 0.45 + (a - A0) / (A1 - A0) * 0.7 + 0.05
    keys = [(0.3, "点灯：流明身后从礁石上升起灯塔虚像，灯室亮起"), (0.7, "照海：灯室转动，光锥扫过怪群，照到的头顶亮紫印"),
            (0.95, "守岸：艾丽妮残影追着光锥刺过，照到的逐个受审倒下"), (1.4, "收尾：光锥扫完，灯塔虚像从上往下淡去，扇形里清空")]
    out = []
    for t, lab in keys:
        img = frame(A, w, t, lambda cv, tt: None, [("lumen", (O[0] + 26, O[1] + 18), "atk"), ("irene", (O[0] + 4, O[1] + 40), "run")]).convert("RGBA")
        cv = B.Canvas(img)
        k = min(1.0, t / 0.3)
        al = 0.92 * (1 - max(0.0, (t - 1.25) / 0.35))
        if al > 0.02:
            lighthouse2(cv, (O[0] - 20, O[1] + 10), k, al)
        lamp = (O[0] - 20, O[1] + 10 - 160 + 26)
        if 0.4 <= t < 1.25:
            ang = A0 + (A1 - A0) * min(1.0, (t - 0.4) / 0.75)
            beam_cone(cv, lamp, ang, R)
            for e in w.es:
                if e["kt"] and t - 0.25 < e["kt"] and e["kt"] > t:
                    pp = w.pos(e, t)
                    a = math.atan2((pp[1] - O[1]) / SQ, pp[0] - O[0])
                    if a <= ang:
                        for d in ((0, 0), (1, 0), (-1, 0), (0, 1), (0, -1)):
                            cv.cell(pp[0] + d[0], pp[1] - 22 + d[1], IR[5] if d == (0, 0) else IR[3])
            if t >= 0.6:
                ang2 = A0 + (A1 - A0) * min(1.0, (t - 0.55) / 0.75)
                tip = (O[0] + math.cos(ang2) * R * 0.6, O[1] + math.sin(ang2) * R * 0.6 * SQ)
                cv = ghost(cv, A, "irene", (tip[0] - 40, tip[1]), tip, 1.0, IR)
        out.append((cv.finish(), lab, (170, 20, 660, 320)))
    return out


# ---------------------------------------------------------------- 11-06 第七轮：灯塔按用户参考图（黑塔 + 堡垒基座 + 金色徽记 + 栅格灯室暖光）

BLK = ramp(["#07080a", "#101216", "#1a1d23", "#272b33", "#3a3f4a"])
LAMPG = ramp(["#1c1408", "#4a3612", "#8c6a26", "#cfa24a", "#efd08a", "#fff0c6", "#ffffff"])   # 艾丽妮手提灯的暖金（docs/272 LAMP）


def lighthouse3(cv, p, k, al=0.95):
    """灯塔虚像（约 96×190 美术像素）：堡垒基座（城垛 + 两角小塔楼 + 正面金色徽记）→ 细高黑色塔身（收分、左缘一格受光边）
    → 顶部箍环 → 竖栅格灯室（暖橙白光从栅格间透出）→ 尖顶。k 0..1 从下往上显形，灯室在 k > 0.6 后点亮"""
    H = 190
    vis = int(H * min(1.0, k * 1.4))
    lit = k > 0.6

    def put(x, y, c, a=al):
        if y >= H - vis:
            cv.cell(p[0] + x, p[1] - H + y, c, a)

    # 基座（y 150..190）：主墙 + 城垛 + 两角塔楼
    for y in range(158, 190):
        hw = 40 + (y - 158) // 6
        for x in range(-hw, hw + 1):
            col = BLK[1] if (x + y) % 11 else BLK[2]
            if abs(x) >= hw - 1:
                col = BLK[0]
            if y == 158 or x == -hw:
                col = LAMPG[2] if lit else BLK[3]
            put(x, y, col)
    for y in range(152, 158):   # 城垛
        for x in range(-40, 41):
            if (x // 4) % 2 == 0:
                put(x, y, BLK[2] if y > 152 else BLK[3])
    for cx in (-38, 38):        # 两角塔楼
        for y in range(140, 158):
            for x in range(-7, 8):
                put(cx + x, y, BLK[2] if x < 0 else BLK[1])
        for y in range(135, 140):
            for x in range(-7, 8):
                if (x // 3) % 2 == 0:
                    put(cx + x, y, BLK[3])
    # 正面金色徽记（展翅形，12×7）
    for y in range(7):
        for x in range(-7, 8):
            wing = abs(x) >= 2 and y <= 4 - (abs(x) - 2) // 2 + 1 and y >= (abs(x) - 2) // 3
            body = abs(x) <= 1 and 1 <= y <= 6
            if wing or body:
                put(x, 166 + y, LAMPG[4] if (x + y) % 3 else LAMPG[5], 1.0)
    if lit:
        cv.glow(p[0], p[1] - H + 169, gl(LAMPG[4]), 0.8)
    # 塔身（y 40..152）：从 7 收到 12 半宽
    for y in range(40, 152):
        hw = 7 + int((y - 40) / 112 * 6)
        for x in range(-hw, hw + 1):
            col = BLK[2] if x < -hw // 3 else BLK[1]
            if x == -hw:
                col = LAMPG[3] if lit else BLK[4]   # 灯室暖光打在塔身左缘：一格暖金受光边，黑塔在暗地面上不融
            elif x == -hw + 1 and lit:
                col = LAMPG[1]
            elif x == hw:
                col = BLK[0]
            put(x, y, col)
        if y in (90, 91):
            put(0, y, BLK[4])
    # 顶部箍环（y 34..40）
    for y in range(34, 40):
        for x in range(-9, 10):
            put(x, y, BLK[3] if y in (34, 39) else BLK[2])
    # 栅格灯室（y 8..34）：竖栏 + 横档，栏间透暖光
    for y in range(8, 34):
        for x in range(-9, 10):
            bar = abs(x) == 9 or x % 3 == 0 or y in (8, 20, 33)
            if bar:
                put(x, y, BLK[1] if not lit else BLK[2], 1.0)
            else:
                d = math.hypot(x, (y - 21) * 0.6) / 10
                col = ((255, 255, 255) if d < 0.3 else (LAMPG[5] if d < 0.6 else LAMPG[4])) if lit else BLK[0]
                put(x, y, col, 1.0)
    # 尖顶
    for y in range(0, 8):
        hw = max(0, (y - 2) // 2)
        for x in range(-hw, hw + 1):
            put(x, y, LAMPG[4] if lit and x == 0 else BLK[2])
    if lit:
        cv.glow(p[0], p[1] - H + 21, (1.0, 0.9, 0.7), 6.0)


def beam_warm(cv, o, ang, R, spread=0.34):
    """暖金光锥（同灯室光色）：两条亮边 + 中线 + 棋盘格抖动点阵，越远越稀，不铺实心底"""
    for side in (-1, 0, 1):
        a = ang + side * spread / 2
        for j in range(int(R)):
            if side == 0 and j % 3:
                continue
            x, y = o[0] + math.cos(a) * j, o[1] + math.sin(a) * j * SQ
            cv.cell(x, y, (255, 255, 255) if side == 0 or j < R * 0.35 else LAMPG[5], 0.9 if side else 0.7)
            if j % 10 == 0 and side:
                cv.glow(x, y, gl(LAMPG[5]), 0.5)
    rng = random.Random(3)
    for i in range(int(R * 4)):
        j = rng.uniform(10, R)
        a = ang + rng.uniform(-spread / 2, spread / 2)
        if rng.random() > 1.15 - j / R:
            x, y = o[0] + math.cos(a) * j, o[1] + math.sin(a) * j * SQ
            if (int(x) + int(y)) % 2 == 0:
                cv.cell(x, y, LAMPG[5], 0.6)


def pair_inq_lighthouse3(A):
    w = B.World(37, A)
    O = (290, 240)
    R = 340
    A0, A1 = -1.0, 0.85
    for e in w.es:
        p = w.pos(e, 0.8)
        d = math.hypot(p[0] - O[0], (p[1] - O[1]) / SQ)
        a = math.atan2((p[1] - O[1]) / SQ, p[0] - O[0])
        if d < R and A0 <= a <= A1:
            e["kt"] = 0.45 + (a - A0) / (A1 - A0) * 0.7 + 0.05
    keys = [(0.3, "点灯：流明身后升起灯塔虚像（黑塔、堡垒基座、金色徽记），栅格灯室亮起"), (0.7, "照海：灯室转动，暖金光锥扫过怪群，照到的头顶亮紫印"),
            (0.95, "守岸：艾丽妮残影追着光锥刺过，照到的逐个受审倒下"), (1.4, "收尾：光锥扫完，灯塔虚像淡去，扇形里清空")]
    out = []
    for t, lab in keys:
        img = frame(A, w, t, lambda cv, tt: None, [("lumen", (O[0] + 50, O[1] + 22), "atk"), ("irene", (O[0] + 26, O[1] + 44), "run")]).convert("RGBA")
        cv = B.Canvas(img)
        k = min(1.0, t / 0.3)
        al = 0.95 * (1 - max(0.0, (t - 1.25) / 0.35))
        if al > 0.02:
            lighthouse3(cv, (O[0] - 30, O[1] + 14), k, al)
        lamp = (O[0] - 30, O[1] + 14 - 190 + 21)
        if 0.4 <= t < 1.25:
            ang = A0 + (A1 - A0) * min(1.0, (t - 0.4) / 0.75)
            beam_warm(cv, lamp, ang, R)
            for e in w.es:
                if e["kt"] and t - 0.25 < e["kt"] and e["kt"] > t:
                    pp = w.pos(e, t)
                    a = math.atan2((pp[1] - O[1]) / SQ, pp[0] - O[0])
                    if a <= ang:
                        for d in ((0, 0), (1, 0), (-1, 0), (0, 1), (0, -1)):
                            cv.cell(pp[0] + d[0], pp[1] - 22 + d[1], IR[5] if d == (0, 0) else IR[3])
            if t >= 0.6:
                ang2 = A0 + (A1 - A0) * min(1.0, (t - 0.55) / 0.75)
                tip = (O[0] + math.cos(ang2) * R * 0.6, O[1] + math.sin(ang2) * R * 0.6 * SQ)
                cv = ghost(cv, A, "irene", (tip[0] - 40, tip[1]), tip, 1.0, IR)
        out.append((cv.finish(), lab, (150, 0, 660, 330)))
    return out


# ---------------------------------------------------------------- 11-06 第七轮：愚人号（艾丽妮 × 归溟幽灵鲨）

GH = ramp(["#0e3846", "#2a7c96", "#6ccde4", "#c6f4ff", "#e8fbff", "#f4fdff", "#ffffff"])   # 归溟幽灵鲨幽灵青（fx_pxplane_su.GH 延长）
HULL = ramp(["#060a15", "#0d1832", "#172f5e", "#234d94", "#3a77c2"])                       # 深海蓝（fx_pxplane_su.AB 前段）


def ghost_ship(cv, p, k, al=0.85):
    """幽灵船（侧视，约 160×110 美术像素，船首朝右）：深船舷（上沿幽灵青描边、一排舷窗）、尖船首上翘 + 船首像、船尾楼、
    主桅 + 两面破帆（青色半透明、有破洞）；整体半透明，k 控制淡入淡出"""
    a = al * k
    W_ = 160
    deck = p[1] - 30
    for x in range(W_):
        u = x / W_
        top = deck - (10 if u < 0.18 else 0) - (int((u - 0.8) / 0.2 * 16) if u > 0.8 else 0)   # 船尾楼高、船首上翘
        bot = deck + 26 - int(((u - 0.45) * 2.2) ** 2 * 18)
        if u > 0.82:
            bot = min(bot, top + 4 + int((1 - u) / 0.18 * 20))
        for y in range(int(top), int(bot)):
            col = HULL[2] if y < deck + 10 else HULL[1]
            if y == int(top):
                col = GH[3]
            elif y == int(bot) - 1:
                col = GH[1]
            elif y == deck + 6 and x % 10 < 5 and 0.2 < u < 0.78:
                col = GH[2]
            elif (x + y) % 9 == 0:
                col = HULL[3]
            cv.cell(p[0] - W_ / 2 + x, y, col, a)
    for i in range(14):   # 船首像（斜出）
        cv.cell(p[0] + W_ / 2 + i * 0.8, deck - 16 - i * 0.6, GH[3], a)
        cv.cell(p[0] + W_ / 2 + i * 0.8, deck - 15 - i * 0.6, GH[2], a)
    mx = p[0] - 6
    for y in range(int(deck - 92), int(deck)):   # 主桅
        cv.cell(mx, y, HULL[3], a)
        cv.cell(mx + 1, y, HULL[2], a)
    for (y0, y1, w0, w1) in ((deck - 86, deck - 54, 34, 44), (deck - 50, deck - 18, 44, 56)):   # 两面横帆
        for y in range(int(y0), int(y1)):
            f = (y - y0) / (y1 - y0)
            hw = int(w0 + (w1 - w0) * f) // 2
            for x in range(-hw, hw + 1):
                if (x * 7 + y * 3) % 23 < 2 or (f > 0.75 and (x + y) % 4 == 0):
                    continue
                cv.cell(mx + x + int(6 * f), y, GH[2] if (x + y) % 5 else GH[3], a * 0.7)
    cv.glow(p[0], deck - 40, gl(GH[2]), 1.2 * k)


def wake(cv, p, length, k):
    for i in range(int(length)):
        x = p[0] - 75 - i
        if (i * 7) % 5 == 0:
            continue
        for s in (-1, 1):
            y = p[1] + s * (4 + i * 0.12) * SQ
            cv.cell(x, y, (235, 245, 250) if i < 30 else GH[2], max(0.0, 0.9 - i / length) * (1 - k))


def helix(cv, c, r, t, k):
    """携手旋舞的拖尾：紫（艾丽妮）、青（幽灵鲨）两条带子绕同一圆心缠成双螺旋——各自半径按正弦交替起伏、彼此交错"""
    n = int(r * 7)
    for i in range(int(n * k)):
        u = i / n
        a = u * math.tau * 1.2 + t * 4
        for R, ph in ((IR, 0.0), (GH, math.pi)):
            rr = r * (0.82 + 0.18 * math.sin(u * math.tau * 3 + ph))
            x, y = c[0] + math.cos(a) * rr, c[1] + math.sin(a) * rr * SQ
            front = math.sin(u * math.tau * 3 + ph) > 0
            col = R[5] if front else R[3]
            cv.cell(x, y, col)
            cv.cell(x, y + 1, R[2] if R is IR else R[1])
            if front and i % 5 == 0:
                cv.glow(x, y, gl(R[4]), 0.6)


def linked_rings(cv, c, r, k):
    """并肩落刃：两只交扣的环（紫 / 青）在落点外扩、断开"""
    brk = max(0.0, (k - 0.6) / 0.4)
    for R, dx in ((IR, -r * 0.35), (GH, r * 0.35)):
        rr = r * (0.5 + 0.5 * k)
        n = int(rr * 7)
        for i in range(n):
            if brk and (i * 7) % 10 < brk * 10:
                continue
            a = i / n * math.tau
            x, y = c[0] + dx * (0.5 + 0.5 * k) + math.cos(a) * rr, c[1] + math.sin(a) * rr * SQ
            for j in range(3):
                cv.cell(x, y + j - 1, (255, 255, 255) if j == 1 and k < 0.3 else (R[5] if j == 1 else R[3]))


def pair_fools(A):
    if "specter_unchained_atk" not in A:
        od = os.path.join(ROOT, "game", "art", "operators", "specter_unchained")
        A["specter_unchained_atk"] = B.frames_of(os.path.join(od, "op_specter_unchained_attack@1x.png"), fw=96)
        A["specter_unchained_run"] = B.frames_of(os.path.join(od, "op_specter_unchained_run@1x.png"), 8)
        A["specter_unchained_idle"] = B.frames_of(os.path.join(od, "op_specter_unchained_idle@1x.png"), 8)
    w = B.World(37, A)
    C = (440, 200)
    for e in w.es:
        p = w.pos(e, 0.5)
        if abs(p[1] - 200) < 46 and p[0] < 470:
            e["kt"] = 0.15 + max(0.0, (p[0] - 180)) / 290 * 0.35
        elif math.hypot(p[0] - C[0], (p[1] - C[1]) / SQ) < 120:
            e["kt"] = 0.75 + math.hypot(p[0] - C[0], (p[1] - C[1]) / SQ) / 120 * 0.15
        elif math.hypot(p[0] - C[0] - 30, (p[1] - C[1] - 10) / SQ) < 170:
            e["kt"] = 1.1
    keys = [(0.3, "驶来：幽灵船「愚人号」劈开怪群驶过，甲板上两人背靠背"), (0.8, "携手旋舞：幽灵鲨牵起艾丽妮的手一起转，紫青两条拖尾缠成双螺旋卷走一圈"),
            (1.12, "并肩落刃：两人一起跃下，落点炸开两只交扣的环"), (1.5, "收尾：船隐入雾里，两人背靠背收势，路上和圈里清空")]
    out = []
    for t, lab in keys:
        img = frame(A, w, t, lambda cv, tt: None, []).convert("RGBA")
        cv = B.Canvas(img)
        sx = 150 + 290 * min(1.0, t / 0.55)
        shp = (sx, 210)
        if t < 1.45:
            sk = min(1.0, t / 0.15) * (1 - max(0.0, (t - 1.0) / 0.45))
            wake(cv, shp, 120, max(0.0, (t - 0.6) / 0.8))
            ghost_ship(cv, shp, sk)
        im = cv.finish().convert("RGBA")
        if t < 0.6:   # 甲板上背靠背
            B.put_op(im, A["irene_idle"][0], (shp[0] + 26, shp[1] - 34), True, 0.95)
            B.put_op(im, A["specter_unchained_idle"][0], (shp[0] + 50, shp[1] - 34), False, 0.95)
        elif t < 1.0:   # 携手旋舞：两人隔着圆心对转
            a = (t - 0.6) * 9
            r = 26
            p1 = (C[0] + math.cos(a) * r, C[1] + math.sin(a) * r * SQ)
            p2 = (C[0] - math.cos(a) * r, C[1] - math.sin(a) * r * SQ)
            B.put_op(im, A["irene_atk"][4], p1, math.cos(a) > 0, 0.9, (1.05, 0.95, 1.15))
            B.put_op(im, A["specter_unchained_atk"][6], p2, math.cos(a) < 0, 0.9, (0.85, 1.05, 1.15))
        else:   # 落刃 → 背靠背收势
            al = 1.0 if t < 1.35 else max(0.3, 1 - (t - 1.35) / 0.4)
            B.put_op(im, A["irene_atk"][6], (C[0] - 14, C[1] + 6), True, al)
            B.put_op(im, A["specter_unchained_atk"][8], (C[0] + 14, C[1] + 6), False, al)
        cv = B.Canvas(im)
        if 0.6 <= t < 1.05:
            helix(cv, C, 110, t, min(1.0, (t - 0.6) / 0.3))
        if 1.0 <= t < 1.45:
            linked_rings(cv, (C[0], C[1] + 10), 150, min(1.0, (t - 1.0) / 0.45))
        if t >= 1.3:   # 收势：两人之间一点小星芒
            for d in ((0, 0), (1, 0), (-1, 0), (0, 1), (0, -1), (2, 0), (-2, 0)):
                cv.cell(C[0] + d[0], C[1] - 30 + d[1], (255, 255, 255) if d == (0, 0) else IR[5] if d[0] < 0 else GH[3])
            cv.glow(C[0], C[1] - 30, (0.9, 0.9, 1.0), 1.5)
        out.append((cv.finish(), lab, (100, 30, 660, 320)))
    return out


# ---------------------------------------------------------------- 11-07：潮下授课 · 链上疾驰（乌尔比安 × 斯卡蒂）

UL = ramp(["#0c1235", "#1b2a66", "#2c4397", "#4463c8", "#7b93e6", "#c0cbf6", "#ffffff"])   # fx_pxplane_ul.C（乌尔比安审定色）
SKR = ramp(["#3a0d1b", "#5e1424", "#86202d", "#a8323c", "#dc4048", "#ffb4bc", "#ffffff"])  # 斯卡蒂酒红（fx_pxplane SK_R）


def big_chain(cv, a, b, k_len, taut, t, snap=0.0, red_to=0.0):
    """授课锚链：比乌尔比安普攻锁链粗一档的方环链（每节 8×5，一横一竖交替），绷直时微微抖、绷到头亮一格；snap > 0 时从锚端往回收、断节飞散"""
    L = math.dist(a, b)
    dv = ((b[0] - a[0]) / L, (b[1] - a[1]) / L)
    nv = (-dv[1], dv[0])
    n = int(L * k_len)
    i = 0
    while i < n:
        if snap and i > n * (1 - snap):
            break
        sag = 0 if taut else math.sin(math.pi * i / max(1, n)) * 18
        jit = (1 if (i // 8 + int(t * 30)) % 2 else -1) if taut else 0
        cx, cy = a[0] + dv[0] * i, a[1] + dv[1] * i + sag + jit
        horiz = (i // 12) % 2 == 0
        red = red_to > 0 and i / max(1, n) < red_to
        P = SKD if red else UL
        for u in range(12):
            for v in range(7 if horiz else 4):
                edge = u in (0, 1, 10, 11) or v in (0, 1, (5 if horiz else 2), (6 if horiz else 3))
                if not edge:
                    continue
                x = cx + dv[0] * u + nv[0] * (v - 3)
                y = cy + dv[1] * u + nv[1] * (v - 3) * (1 if horiz else 0.5)
                cv.cell(x, y, ((255, 255, 255) if v in (0, 1) else P[5]) if red else (P[5] if v in (0, 1) else (P[4] if horiz else P[3])))
        if (taut and i % 24 == 0) or red:
            cv.glow(cx, cy, gl(P[4]), 0.9 if red else 0.5)
        i += 12


def big_anchor(cv, p):
    """钉进地面的锚（24×30）：锚杆 + 横档 + 两只锚爪，冷蓝，砸地处一圈碎石"""
    for y in range(-30, 0):
        cv.cell(p[0], p[1] + y, UL[4])
        cv.cell(p[0] + 1, p[1] + y, UL[3])
    for x in range(-7, 8):
        cv.cell(p[0] + x, p[1] - 24, UL[4])
    for s in (-1, 1):
        for i in range(10):
            cv.cell(p[0] + s * (2 + i), p[1] - i * 0.6, UL[5] if i < 3 else UL[4])
            cv.cell(p[0] + s * (2 + i), p[1] - i * 0.6 + 1, UL[2])
    for i in range(3):
        cv.cell(p[0] - 1 + i, p[1] - 31, UL[5])
    cv.glow(p[0], p[1] - 10, gl(UL[4]), 1.2)


def spray(cv, p, k, seed):
    """斯卡蒂拖剑溅起的水花（深海蓝，往后、往上）"""
    rng = random.Random(seed)
    for i in range(36):
        vx = -rng.uniform(30, 120)
        vy = -rng.uniform(20, 70)
        x = p[0] + vx * k
        y = p[1] + vy * k + 120 * k * k
        for dx in range(2):
            for dy in range(2):
                cv.cell(x + dx, y + dy, SKD[5] if i % 3 == 0 else SKD[4])
        if i % 4 == 0:
            cv.glow(x, y, gl(SKD[4]), 0.6)


def pair_lesson_chain(A):
    for o, n in (("ulpianus", 8), ("skadi", 8)):
        if o + "_atk" not in A:
            od = os.path.join(ROOT, "game", "art", "operators", o)
            A[o + "_atk"] = B.frames_of(os.path.join(od, "op_%s_attack@1x.png" % o), n)
            A[o + "_run"] = B.frames_of(os.path.join(od, "op_%s_run@1x.png" % o), 8)
            A[o + "_idle"] = B.frames_of(os.path.join(od, "op_%s_idle@1x.png" % o), 8)
    w = B.World(23, A)
    S = (B.SQUAD[0] + 10, B.SQUAD[1] - 10)
    E = (610, 168)
    T_throw, T_slide0, T_slide1 = (0.15, 0.4), 0.55, 1.05
    for e in w.es:
        p = w.pos(e, 0.7)
        d, u = B.seg_dist(p, S, E)
        if d < 34:
            e["kt"] = T_slide0 + u * (T_slide1 - T_slide0)
        elif d < 70 and int(e["p0"][0] * 5 + e["p0"][1]) % 2 == 0:
            e["kt"] = T_slide0 + u * (T_slide1 - T_slide0) + 0.06
    keys = [(0.3, "示范：乌尔比安把锚掷向怪群另一头，锚链跟着甩出去"), (0.5, "绷链：锚钉进地面，锚链横跨怪群一下绷直"),
            (0.85, "疾驰：斯卡蒂踩上锚链一路滑过去，拖剑溅起蓝白水花，链两侧的怪被扫倒"), (1.35, "收链：斯卡蒂在锚边落地，锚链往回收、断节飞散")]
    out = []
    for t, lab in keys:
        img = frame(A, w, t, lambda cv, tt: None, []).convert("RGBA")
        cv = B.Canvas(img)
        if t >= T_throw[0]:
            kl = min(1.0, (t - T_throw[0]) / (T_throw[1] - T_throw[0]))
            taut = t >= T_throw[1] + 0.05
            snap = max(0.0, (t - 1.15) / 0.3)
            a_end = (S[0] + (E[0] - S[0]) * kl, S[1] + (E[1] - S[1]) * kl - (1 - kl) * kl * 80)
            red_to = min(1.0, max(0.0, (t - T_slide0) / (T_slide1 - T_slide0))) if t < 1.15 else 0.0
            big_chain(cv, (S[0], S[1] - 20), (E[0], E[1] - 6) if taut else a_end, 1.0, taut, t, snap, red_to)
            if kl >= 1.0:
                big_anchor(cv, E)
        im = cv.finish().convert("RGBA")
        B.put_op(im, A["ulpianus_atk"][3 if t < 0.5 else 5], (S[0] - 14, S[1] + 6), False, 1.0)
        if T_slide0 <= t < T_slide1 + 0.1:
            u = min(1.0, (t - T_slide0) / (T_slide1 - T_slide0))
            sp = (S[0] + (E[0] - S[0]) * u, S[1] + (E[1] - S[1]) * u - 20)
            for j in range(3, 0, -1):
                uj = max(0.0, u - 0.08 * j)
                B.put_op(im, A["skadi_atk"][4], (S[0] + (E[0] - S[0]) * uj, S[1] + (E[1] - S[1]) * uj - 20), False, 0.25 * (1 - j / 4), (0.85, 0.95, 1.15))
            B.put_op(im, A["skadi_atk"][4], sp, False, 0.95)
            cv = B.Canvas(im)
            spray(cv, (sp[0] - 10, sp[1] + 14), (t * 5) % 1, int(t * 15))
            for i in range(int(math.dist(S, sp))):   # 剑尖划过的地面红痕（贴地、暗）
                if i % 3:
                    continue
                q = (S[0] + (sp[0] - S[0]) * i / max(1, math.dist(S, sp)), S[1] + (sp[1] + 20 - S[1]) * i / max(1, math.dist(S, sp)) + 8)
                cv.cell(q[0], q[1], SKD[2], 0.8)
        else:
            if t >= T_slide1 + 0.1:
                B.put_op(im, A["skadi_atk"][6], (E[0] - 20, E[1] + 4), True, 1.0)
            else:
                B.put_op(im, A["skadi_run"][int(t * 12) % 8], (S[0] - 40, S[1] + 18), False, 1.0)
            cv = B.Canvas(im)
        out.append((cv.finish(), lab, (90, 50, 650, 320)))
    return out


# ---------------------------------------------------------------- 11-07：愚人号 · 双剑对舞（艾丽妮 × 归溟幽灵鲨）

def fig8(c, rx, ry, u):
    """「8」字舞步路线（伯努利双纽线），u 0..1 走一整圈"""
    a = u * math.tau
    d = 1 + math.sin(a) ** 2
    return (c[0] + rx * math.cos(a) / d, c[1] + ry * math.sin(a) * math.cos(a) / d * 2 * SQ)


def footprint(cv, p, R, left, k, burst=0.0):
    """发光脚印（3×5 椭圆 + 一格脚跟），左右脚错开 4 像素；burst > 0 时炸成一圈小火星"""
    ox = -2 if left else 2
    if burst <= 0:
        for y in range(8):
            for x in range(5):
                if (x in (0, 4) and y in (0, 1, 7)) or (y == 5 and x in (0, 4)):
                    continue
                cv.cell(p[0] + ox + x - 2, p[1] + y - 4, (255, 255, 255) if (k >= 1.0 and 1 <= x <= 3 and y < 3) else (R[5] if y < 4 else R[4]), k)
        cv.glow(p[0] + ox, p[1], gl(R[4]), 0.8 * k)
    else:
        rr = 3 + 20 * burst
        for i in range(8):
            a = i / 8 * math.tau
            cv.cell(p[0] + math.cos(a) * rr, p[1] + math.sin(a) * rr * SQ, (255, 255, 255) if burst < 0.3 else R[5], 1 - burst)
        if burst < 0.4:
            cv.glow(p[0], p[1], gl(R[5]), 1.2)


def tip_spark(cv, p, R):
    for d in ((0, 0), (1, 0), (-1, 0), (0, 1), (0, -1), (2, 0), (-2, 0), (0, -2)):
        cv.cell(p[0] + d[0], p[1] + d[1], (255, 255, 255) if d == (0, 0) else R[5])
    cv.glow(p[0], p[1], gl(R[5]), 1.0)


def pair_fools_dance(A):
    if "specter_unchained_atk" not in A:
        od = os.path.join(ROOT, "game", "art", "operators", "specter_unchained")
        A["specter_unchained_atk"] = B.frames_of(os.path.join(od, "op_specter_unchained_attack@1x.png"), fw=96)
        A["specter_unchained_idle"] = B.frames_of(os.path.join(od, "op_specter_unchained_idle@1x.png"), 8)
    w = B.World(37, A)
    C = (430, 200)
    RX, RY = 190, 70
    T0, T1 = 0.25, 1.05      # 跳一圈「8」字
    NST = 40                 # 每人脚印数
    steps = []
    for who, R, ph in (("irene", IR, 0.0), ("specter_unchained", GH, 0.5)):
        for i in range(NST):
            u = i / NST
            steps.append({"who": who, "R": R, "u": u, "p": fig8(C, RX, RY, (u + ph) % 1.0), "t": T0 + u * (T1 - T0), "left": i % 2 == 0})
    for e in w.es:
        p = w.pos(e, 1.2)
        if any(math.dist(p, s["p"]) < 42 for s in steps):
            e["kt"] = 1.25 + 0.0003 * (p[0] - 200)
    keys = [(0.18, "相邀：两人从「8」字两端走进怪群，相对伸手（不要船）"), (0.7, "对舞：两人沿「8」字舞步一左一右交替出刀，每一步留下一枚发光脚印（紫 / 青）"),
            (1.15, "合拍：两人在 8 字中心相遇，剑尖轻碰，手牵手收势，满地脚印一齐亮"), (1.42, "余韵：所有脚印同时炸开，舞步路线上的怪一齐倒下")]
    out = []
    for t, lab in keys:
        img = frame(A, w, t, lambda cv, tt: None, []).convert("RGBA")
        cv = B.Canvas(img)
        for who, R, ph in (("irene", IR, 0.0), ("specter_unchained", GH, 0.5)):   # 舞步路线：一条淡点线把脚印连起来
            if t < 1.25:
                uu = min(1.0, max(0.0, (t - T0) / (T1 - T0)))
                for i in range(int(400 * uu)):
                    if i % 4:
                        continue
                    q = fig8(C, RX, RY, (i / 400 + ph) % 1.0)
                    cv.cell(q[0], q[1] + 3, R[3], 0.6)
        for s in steps:
            if t >= s["t"]:
                if t < 1.25:
                    flash = 1.1 <= t < 1.25
                    footprint(cv, s["p"], s["R"], s["left"], 1.0 if flash else 0.8)
                else:
                    footprint(cv, s["p"], s["R"], s["left"], 1.0, min(1.0, (t - 1.25) / 0.25))
        im = cv.finish().convert("RGBA")
        if T0 <= t < T1:
            u = (t - T0) / (T1 - T0)
            for who, R, ph, fr in (("irene", IR, 0.0, 4 + int(t * 15) % 3), ("specter_unchained", GH, 0.5, 5 + int(t * 15) % 4)):
                p = fig8(C, RX, RY, (u + ph) % 1.0)
                q = fig8(C, RX, RY, (u + ph + 0.01) % 1.0)
                spr = A[who + "_atk"][fr]
                B.put_op(im, spr, (p[0], p[1] + 6), q[0] < p[0], 0.92, tuple(1 + (c / 255 - 1) * 0.25 for c in R[4]))
            cv = B.Canvas(im)
            for who, R, ph in (("irene", IR, 0.0), ("specter_unchained", GH, 0.5)):
                p = fig8(C, RX, RY, (u + ph) % 1.0)
                if int(t * 15) % 2 == 0:
                    tip_spark(cv, (p[0] + 14, p[1] - 18), R)
        else:
            if t >= T1:
                B.put_op(im, A["irene_atk"][6], (C[0] - 12, C[1] + 6), False, 1.0)
                B.put_op(im, A["specter_unchained_atk"][8], (C[0] + 12, C[1] + 6), True, 1.0)
            else:
                B.put_op(im, A["irene_idle"][0], fig8(C, RX, RY, 0.0), True, 0.95)
                B.put_op(im, A["specter_unchained_idle"][0], fig8(C, RX, RY, 0.5), False, 0.95)
            cv = B.Canvas(im)
            if t >= T1:
                tip_spark(cv, (C[0], C[1] - 26), IR)
                for d in range(-3, 4):   # 两人之间牵着的手：一点紫青相接的亮线
                    cv.cell(C[0] + d, C[1] - 10, IR[5] if d < 0 else GH[3])
        out.append((cv.finish(), lab, (180, 60, 680, 320)))
    return out


# ---------------------------------------------------------------- 11-07：剩下四对深海猎人 + 斯卡蒂改深海蓝

SKD = ramp(["#050c1e", "#0b1a3a", "#1c3c80", "#3a64c4", "#598cf2", "#cddcfb", "#ffffff"])   # 斯卡蒂深海蓝（data/fx_pxplane/skadi.json，docs/246）
GLC = ramp(["#0d1a2e", "#182f51", "#294a78", "#3a65a0", "#4c80c7", "#8bacdb", "#c9d9ee"])   # 歌蕾蒂娅（fx_pxplane_gl.C）
ABY = ramp(["#030509", "#060a15", "#0d1832", "#172f5e", "#234d94"])                       # 深渊底色


def need(A, *ops):
    for o in ops:
        if o + "_atk" in A:
            continue
        od = os.path.join(ROOT, "game", "art", "operators", o)
        if o == "specter_unchained":
            A[o + "_atk"] = B.frames_of(os.path.join(od, "op_%s_attack@1x.png" % o), fw=96)
        else:
            A[o + "_atk"] = B.frames_of(os.path.join(od, "op_%s_attack@1x.png" % o), 8)
        A[o + "_run"] = B.frames_of(os.path.join(od, "op_%s_run@1x.png" % o), 8)
        A[o + "_idle"] = B.frames_of(os.path.join(od, "op_%s_idle@1x.png" % o), 8)


def sink(w, test, t0, t1):
    for e in w.es:
        p = w.pos(e, t0)
        r = test(p)
        if r is not None:
            e["kt"] = t0 + (t1 - t0) * r


# ---- 引潮夺命 · 海沟
def trench(cv, a, b, k, close=0.0):
    """海沟：一道锯齿形裂谷（深渊底色、内壁暗蓝、上沿歌蕾蒂娅亮蓝描边 + 白沫点），k 0..1 从一头裂到另一头、宽度张开；close > 0 合拢"""
    L = math.dist(a, b)
    dv = ((b[0] - a[0]) / L, (b[1] - a[1]) / L)
    nv = (-dv[1], dv[0])
    rng = random.Random(11)
    jit = [rng.uniform(-3, 3) for _ in range(int(L) + 2)]
    for i in range(int(L * min(1.0, k * 1.4))):
        u = i / L
        hw = (14 + 6 * math.sin(u * 9.0)) * math.sin(math.pi * u) ** 0.5 * min(1.0, k * 1.6) * (1 - close)
        if hw < 1:
            continue
        cx = a[0] + dv[0] * i + nv[0] * jit[i]
        cy = a[1] + dv[1] * i + nv[1] * jit[i] * SQ
        for j in range(-int(hw), int(hw) + 1):
            q = abs(j) / hw
            col = ABY[0] if q < 0.5 else (ABY[2] if q < 0.8 else GLC[2])
            cv.cell(cx + nv[0] * j, cy + nv[1] * j * SQ, col)
        for s in (-1, 1):
            ex, ey = cx + nv[0] * hw * s, cy + nv[1] * hw * s * SQ
            cv.cell(ex, ey, GLC[5])
            if i % 5 == 0:
                cv.cell(ex, ey - 1, (230, 240, 250))
                cv.glow(ex, ey, gl(GLC[5]), 0.4)


def pair_tide_trench(A):
    need(A, "gladiia", "specter_unchained")
    w = B.World(29, A)
    a, b = (250, 150), (620, 240)
    def test(p):
        d, u = B.seg_dist(p, a, b)
        return u if d < 70 else None
    sink(w, test, 0.6, 1.0)
    keys = [(0.35, "引潮：歌蕾蒂娅残影甩钩一拉，地面沿钩线裂开一道海沟"), (0.7, "吞没：两侧的怪被潮水拖进沟里往下沉"),
            (0.95, "夺命：归溟幽灵鲨残影在沟里来回穿梭，青色残像折返三趟"), (1.35, "收尾：海沟合拢，只剩一道湿痕，沟两侧清空")]
    out = []
    for t, lab in keys:
        img = frame(A, w, t, lambda cv, tt: None, [("gladiia", (B.SQUAD[0], B.SQUAD[1]), "atk" if t < 0.5 else "run")]).convert("RGBA")
        cv = B.Canvas(img)
        k = min(1.0, max(0.0, (t - 0.25) / 0.3))
        close = max(0.0, (t - 1.15) / 0.2)
        if t < 1.4:
            trench(cv, a, b, k, close)
        else:
            for i in range(int(math.dist(a, b))):
                if i % 3 == 0:
                    u = i / math.dist(a, b)
                    cv.cell(a[0] + (b[0] - a[0]) * u, a[1] + (b[1] - a[1]) * u, GLC[2], 0.7)
        if t >= 0.75 and t < 1.15:
            u = ((t - 0.75) / 0.4 * 3) % 2
            u = u if u <= 1 else 2 - u
            cv = ghost(cv, A, "specter_unchained", a, (a[0] + (b[0] - a[0]) * u, a[1] + (b[1] - a[1]) * u), 1.0, GH)
        out.append((cv.finish(), lab, (120, 40, 660, 320)))
    return out


# ---- 漩涡钉锚 · 作战推演
def plan_arrow(cv, a, b, k, R, flash=False):
    """推演箭头：粗箭杆（3 格）+ 大三角箭头，从 a 往 b 画出去；flash 时芯白"""
    L = math.dist(a, b)
    dv = ((b[0] - a[0]) / L, (b[1] - a[1]) / L)
    nv = (-dv[1], dv[0])
    n = int(L * k)
    for i in range(0, n, 1):
        if (i // 6) % 3 == 2 and not flash:
            continue
        x, y = a[0] + dv[0] * i, a[1] + dv[1] * i
        for j in (-1, 0, 1):
            cv.cell(x + nv[0] * j, y + nv[1] * j, (255, 255, 255) if flash and j == 0 else (R[5] if j == 0 else R[4]))
    if k >= 1.0:
        for s in range(14):
            hw = (14 - s) * 0.7
            cx, cy = b[0] - dv[0] * (14 - s), b[1] - dv[1] * (14 - s)
            for j in range(-int(hw), int(hw) + 1):
                cv.cell(cx + nv[0] * j, cy + nv[1] * j, (255, 255, 255) if flash else (R[5] if abs(j) < hw - 1 else R[3]))
        cv.glow(b[0], b[1], gl(R[5]), 0.8)


def pair_vortex_plan(A):
    need(A, "gladiia", "ulpianus")
    w = B.World(41, A)
    C = (440, 200)
    starts = [(C[0] + math.cos(a) * 190, C[1] + math.sin(a) * 190 * SQ) for a in (math.pi * 0.95, math.pi * 1.35, math.pi * 1.75, math.pi * 0.2, math.pi * 0.6)]
    tips = [(C[0] + (s[0] - C[0]) * 0.28, C[1] + (s[1] - C[1]) * 0.28) for s in starts]
    def test(p):
        d = math.hypot(p[0] - C[0], (p[1] - C[1]) / SQ)
        return 0.0 if d < 190 else None
    sink(w, test, 1.0, 1.0)
    keys = [(0.45, "推演：地上亮出作战推演图，歌蕾蒂娅的箭头一支支从外往里画"), (0.8, "收拢：五支箭头指向中心，怪被潮水顺着箭头推着往里聚"),
            (1.02, "落锚：乌尔比安的锚依次砸在每个箭头尖上"), (1.4, "收尾：推演图熄灭，锚坑留在原地，圈里清空")]
    out = []
    for t, lab in keys:
        img = frame(A, w, t, lambda cv, tt: None, [("gladiia", (B.SQUAD[0], B.SQUAD[1]), "run"), ("ulpianus", (B.SQUAD[0] - 34, B.SQUAD[1] - 26), "run")]).convert("RGBA")
        # 箭头推怪往里：草图里把怪画得往中心挪
        cv = B.Canvas(img)
        for i, (s, tp) in enumerate(zip(starts, tips)):
            k = min(1.0, max(0.0, (t - 0.2 - i * 0.08) / 0.2))
            if k > 0 and t < 1.3:
                plan_arrow(cv, s, tp, k, GLC, flash=0.95 <= t < 1.05)
        for i, tp in enumerate(tips):
            ts = 0.95 + i * 0.03
            if t >= ts:
                big_anchor(cv, tp)
                if t < ts + 0.15:
                    blast_ring(cv, tp, (t - ts) / 0.15, UL)
        out.append((cv.finish(), lab, (200, 40, 680, 330)))
    return out


# ---- 双鳍 · 背鳍巡游
def fin(cv, p, R, k=1.0, left=False):
    """背鳍（14×18 美术像素，后掠三角）+ 前方白色破浪 + 身后一对水线"""
    for y in range(36):
        w_ = int((36 - y) * 0.75)
        for x in range(w_):
            xx = (-x if left else x) - (y * 0.5 if not left else -y * 0.5)
            col = (255, 255, 255) if x < 2 and y > 20 else (R[5] if x < 4 else (R[4] if x < w_ - 3 else R[3]))
            cv.cell(p[0] + xx, p[1] - y, col, k)
    for i in range(18):
        for j in range(2):
            cv.cell(p[0] + (i - 9), p[1] + 1 + j, (235, 245, 250), k)
    cv.glow(p[0], p[1] - 12, gl(R[5]), 1.2 * k)


def fin_wake(cv, pts, R):
    for i, p in enumerate(pts):
        if i % 2:
            continue
        a = i / len(pts)
        for j in range(-3, 4):
            cv.cell(p[0], p[1] + j, (225, 238, 248) if abs(j) == 3 or a > 0.75 else R[4], 0.35 + 0.6 * a)


def pair_fins(A):
    need(A, "skadi", "specter_unchained")
    w = B.World(43, A)
    C = (440, 200)
    R = 150
    def path(u, ph, sgn):
        a = sgn * u * math.tau * 2 + ph
        rr = R * (0.75 + 0.25 * math.sin(u * math.tau * 2 + ph))
        return (C[0] + math.cos(a) * rr, C[1] + math.sin(a) * rr * SQ)
    def test(p):
        d = math.hypot(p[0] - C[0], (p[1] - C[1]) / SQ)
        return 0.6 if d < R * 1.05 else None
    sink(w, test, 0.55, 0.6)
    keys = [(0.3, "下潜：两片背鳍（斯卡蒂深海蓝 / 幽灵鲨幽灵青）从地面下划出"), (0.65, "巡游：两片背鳍绕着怪群交错游两圈，身后拖白色破浪，圈里的怪被卷倒"),
            (1.0, "跃出：两人从背鳍下同时跃出水面，在圈心交错一下"), (1.35, "收尾：两人落回地下，破浪散成水痕，圈里清空")]
    out = []
    T0, T1 = 0.2, 0.9
    for t, lab in keys:
        img = frame(A, w, t, lambda cv, tt: None, []).convert("RGBA")
        cv = B.Canvas(img)
        u = min(1.0, max(0.0, (t - T0) / (T1 - T0)))
        for R_, ph, sgn in ((SKD, 0.0, 1), (GH, math.pi, -1)):
            pts = [path(u * i / 60, ph, sgn) for i in range(61)]
            fin_wake(cv, pts, R_)
            if t < T1 + 0.05:
                p = pts[-1]
                q = path(min(1.0, u + 0.01), ph, sgn)
                fin(cv, p, R_, 1.0, q[0] < p[0])
        if 0.92 <= t < 1.2:
            im = cv.finish().convert("RGBA")
            h = math.sin(math.pi * (t - 0.92) / 0.28) * 40
            B.put_op(im, A["skadi_atk"][4], (C[0] - 18, C[1] - h), False, 0.95)
            B.put_op(im, A["specter_unchained_atk"][6], (C[0] + 18, C[1] - h), True, 0.95)
            cv = B.Canvas(im)
            blast_ring(cv, C, (t - 0.92) / 0.28, SKD)
        out.append((cv.finish(), lab, (220, 50, 660, 320)))
    return out


# ---- 群猎 · 暗潮合围
def tide_ring(cv, c, r, k):
    """暗潮环：一圈深色潮水（宽 20，深渊底 + 亮蓝浪唇 + 白沫），从外往里收；k 0..1"""
    n = int(r * 7)
    for i in range(n):
        a = i / n * math.tau
        lip = r + 3 * math.sin(a * 9 + k * 12)
        for j in range(0, 22):
            rr = lip + j
            x, y = c[0] + math.cos(a) * rr, c[1] + math.sin(a) * rr * SQ
            col = (235, 245, 250) if j < 2 and (i % 3) else (SKD[4] if j < 4 else (ABY[3] if j < 9 else ABY[1]))
            cv.cell(x, y, col, 0.95 if j < 9 else 0.75)
        if i % 9 == 0:
            cv.glow(c[0] + math.cos(a) * lip, c[1] + math.sin(a) * lip * SQ, gl(SKD[5]), 0.5)


def pair_hunt(A):
    need(A, "skadi", "gladiia", "specter_unchained", "ulpianus")
    w = B.World(47, A)
    C = (440, 200)
    def test(p):
        d = math.hypot(p[0] - C[0], (p[1] - C[1]) / SQ)
        return 0.0 if d < 210 else None
    sink(w, test, 1.05, 1.05)
    hunters = [("skadi", SKD, math.pi * 1.0), ("gladiia", GLC, math.pi * 1.5), ("specter_unchained", GH, 0.0), ("ulpianus", UL, math.pi * 0.5)]
    keys = [(0.35, "涌潮：一圈暗色潮水从四面涌进来，把怪群围住"), (0.75, "合围：潮水往里收，浪唇翻着白沫"),
            (1.0, "群猎：四名深海猎人的残影同时从潮水里跃出，扑向圈心"), (1.4, "收尾：潮水在圈心合拢溅起，退去后圈里清空")]
    out = []
    for t, lab in keys:
        img = frame(A, w, t, lambda cv, tt: None, []).convert("RGBA")
        cv = B.Canvas(img)
        if t < 1.1:
            r = 260 - 170 * min(1.0, max(0.0, (t - 0.2) / 0.8))
            tide_ring(cv, C, r, t)
        elif t < 1.5:
            blast_ring(cv, C, (t - 1.1) / 0.4, SKD)
        if 0.9 <= t < 1.12:
            u = (t - 0.9) / 0.2
            for o, R_, a in hunters:
                s = (C[0] + math.cos(a) * 110, C[1] + math.sin(a) * 110 * SQ)
                cv = ghost(cv, A, o, s, (C[0] + math.cos(a) * 20, C[1] + math.sin(a) * 20 * SQ), u, R_)
        out.append((cv.finish(), lab, (180, 20, 700, 340)))
    return out


PAIRS = {"lesson_chain": ("潮下授课 · 链上疾驰（乌尔比安 × 斯卡蒂）", pair_lesson_chain), "fools_dance": ("愚人号 · 双剑对舞（艾丽妮 × 归溟幽灵鲨）", pair_fools_dance), "tide_trench": ("引潮夺命 · 海沟（歌蕾蒂娅 × 归溟幽灵鲨）", pair_tide_trench), "vortex_plan": ("漩涡钉锚 · 作战推演（歌蕾蒂娅 × 乌尔比安）", pair_vortex_plan), "fins": ("双鳍 · 背鳍巡游（斯卡蒂 × 归溟幽灵鲨）", pair_fins), "hunt": ("群猎 · 暗潮合围（深海猎人 ≥ 3）", pair_hunt)}


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
