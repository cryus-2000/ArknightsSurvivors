#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""归溟幽灵鲨转平面（docs/268）帧条生成：纯 Python 逐像素画（不依赖 pixelfx 库 / node / Godot）。

出：game/art/fx/pxp/pxp_su_<键>.png（横向帧条，1 帧条像素 = 1 美术像素，15 fps）+ game/data/pxp_specter_unchained.json
（同 pxp_skadi.json 的格式：n / fps / w / h / ox / oy / loop / emit）+ 缺的 .png.import。fx_pxplane.gd 读键时加前缀 su_。

意象：深海 + 替身 + 镰锯。锯刃要读得出转动和锯齿（11-05 用户「技能要更突出锯子」）：
  · 普攻环斩 = 腰高的一圈锯环（平面压扁 0.72，前后半圈分两张，按脚底 y 和单位排序）：锯齿是前倾的三角齿，每拍往转动方向挪 0.42 个齿距，
    出手两拍有一段白热的「刀头弧」沿转动方向扫过；锯环下方贴地一圈断续的接触影。
  · 精一 = 起手外圈一道往里收的水纹（卷刃）；精二 = 锯齿甩出水珠（新元素），另有替身闪现。
  · S1 = 头顶落下一道光柱 + 脚下一圈断续符环；期间身边深蓝暗焰（代替原来的红色火焰，红色只给危险）；精一加脚下贴地的不规则水花 + 鳍尖破水，精二加两片绕身游的鲨鳍。
  · S2 = 脚下一道横向白闪 + 冒泡；期间身后两道替身残影（运行时画，青白色，与本体区分）；精二加身后幽蓝触须。
  · S3 = 起手一圈大浪卷起绕身（浪顶白沫、断口、不是墙）；期间重锯：齿尖烧成橙热、火星多、地上留切向的锯痕（先橙后冷）。
色：深海蓝 8 阶 AB、钢 6 阶 ST、火星橙 5 阶 SP（不用危险粉红）、替身青 4 阶 GH。

用法：python tools/pxplane_su_art.py [--only 前缀] [--sheet 预览图]
"""
import argparse, hashlib, json, math, os, random

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_ART = os.path.join(ROOT, "game", "art", "fx", "pxp")
OUT_META = os.path.join(ROOT, "game", "data", "pxp_specter_unchained.json")
TMPL = os.path.join(OUT_ART, "pxp_backwash_gd.png.import")
FPS = 15
SY = 0.72   # combat.GROUND_Y


def hx(s):
    s = s.lstrip("#")
    return (int(s[0:2], 16), int(s[2:4], 16), int(s[4:6], 16), 255)


AB = [hx(c) for c in ["#060a15", "#0d1832", "#172f5e", "#234d94", "#3a77c2", "#78afe6", "#c4e2fa", "#ffffff"]]
ST = [hx(c) for c in ["#1a1e27", "#383f4d", "#677081", "#98a1b0", "#cbd1db", "#f1f3f7"]]
SP = [hx(c) for c in ["#fff3cc", "#ffd27a", "#ffa04a", "#e3692a", "#8a3d1d"]]
GH = [hx(c) for c in ["#0e3846", "#2a7c96", "#6ccde4", "#c6f4ff"]]
FOAM = hx("#e6f3ff")
SHADOW = hx("#070c16")
HOT = {AB[7], SP[0], SP[1], GH[3], FOAM}


class Cv:
    def __init__(self, w, h):
        self.w, self.h = w, h
        self.a = np.zeros((h, w, 4), np.uint8)

    def put(self, x, y, c):
        x, y = int(round(x)), int(round(y))
        if 0 <= x < self.w and 0 <= y < self.h and c is not None:
            self.a[y, x] = c

    def get(self, x, y):
        x, y = int(round(x)), int(round(y))
        if 0 <= x < self.w and 0 <= y < self.h:
            return self.a[y, x]
        return None


def hsh(*v):
    h = hashlib.md5(("|".join(str(x) for x in v)).encode()).digest()
    return h[0] / 255.0


# ================================================================ 锯环

STYLES = {
    #        齿高 带宽 齿距 带色(内暗,中,外亮)        齿色(背光,受光,齿尖)       转速(齿距/拍) 热弧
    "n": dict(H=5, bt=4, gap=13.0, band=(AB[3], AB[4], AB[5]), tooth=(ST[2], ST[4], ST[5]), spin=0.42, hot=(AB[7], AB[6], AB[5]), shadow=True),
    "w": dict(H=5, bt=4, gap=13.0, band=(AB[3], AB[4], AB[5]), tooth=(ST[2], ST[4], ST[5]), spin=0.42, hot=(AB[7], AB[6], AB[5]), shadow=True, wet=True),
    "h": dict(H=7, bt=5, gap=15.0, band=(AB[1], AB[2], AB[4]), tooth=(ST[2], ST[4], SP[1]), spin=0.36, hot=(SP[0], SP[1], SP[2]), shadow=True, heavy=True),
    "g": dict(H=3, bt=2, gap=11.0, band=(GH[0], GH[1], GH[2]), tooth=(GH[1], GH[2], GH[3]), spin=0.42, hot=(GH[3], GH[2], GH[2]), shadow=False),
    # 双重回转（11-05 用户「和旋锯拉开」）：反向第二圈是一枚小一号、抬高一截的锯，和主锯环错位交叠着反转（齿更密、替身青锯身 + 钢齿）
    "d": dict(H=5, bt=3, gap=9.0, band=(GH[0], GH[1], GH[2]), tooth=(ST[2], ST[4], GH[3]), spin=0.5, hot=(GH[3], GH[3], GH[2]), shadow=True, lift=17),
    "s": dict(H=5, bt=4, gap=13.0, band=(AB[3], GH[1], GH[2]), tooth=(ST[3], GH[2], GH[3]), spin=0.55, hot=(GH[3], GH[3], GH[2]), shadow=True, whirl=True),
}
LIFT = 7      # 锯环中心离地（美术像素，腰高）
RING_N = 5


def tooth_h(u, H):
    """锯齿截面：缓坡升到齿尖（u 0 → 0.72），陡面落下（0.72 → 0.86），之后是齿根"""
    if u < 0.72:
        return H * (u / 0.72)
    if u < 0.86:
        return H * (1.0 - (u - 0.72) / 0.14)
    return 0.0


def ring_frames(R, sty, n=RING_N):
    S = STYLES[sty]
    H, bt, gap = S["H"], S["bt"], S["gap"]
    pad = 16 if (S.get("wet") or S.get("heavy")) else 4
    rx = R + H + pad
    ry = int(math.ceil((R + H) * SY)) + pad
    W = 2 * rx + 1
    lift = S.get("lift", LIFT)
    Hh = 2 * ry + lift + 3
    cx, cy = rx, ry
    ox, oy = cx, cy + lift
    N = max(16, int(round(2 * math.pi * R / gap)))
    dth = 2 * math.pi / N
    backs, fronts = [], []
    sc_f = [0.86, 1.0, 1.0, 1.0, 0.97]
    span_f = [math.radians(210), math.radians(130), math.radians(50), 0, 0]
    bright_f = [2, 2, 1, 0, -1]
    keep_f = [1.0, 1.0, 1.0, 0.72, 0.38]
    th0 = math.radians(20)
    for f in range(n):
        back, front = Cv(W, Hh), Cv(W, Hh)
        Rf = R * sc_f[min(f, 4)]
        phase = f * S["spin"] * dth
        head = th0 + f * math.radians(78)
        span = span_f[min(f, 4)]
        br = bright_f[min(f, 4)]
        keep = keep_f[min(f, 4)]
        btf = bt if f < 3 else max(1, bt - (f - 2))
        for y in range(Hh):
            for x in range(W):
                dx, dy = x - cx, y - cy
                dyp = dy / SY
                rho = math.hypot(dx, dyp)
                if rho < Rf - btf - 7 or rho > Rf + H + 1:
                    continue
                th = math.atan2(dyp, dx)
                tgt = back if dy < 0 else front
                lit = math.cos(th - math.radians(-135))   # 左上受光
                # 热弧：head 之后 span 弧度（沿转动方向的尾巴）
                hot = -1.0
                if span > 0:
                    da = (head - th) % (2 * math.pi)
                    if da < span:
                        hot = da / span
                u = ((th - phase) / dth) % 1.0
                k = int(math.floor((th - phase) / dth)) % N
                tooth_on = hsh(sty, R, k, "keep") < keep
                c = None
                if Rf - btf < rho <= Rf:
                    # 锯身带：外沿一格高光、内沿暗
                    if rho > Rf - 1:
                        c = S["band"][2] if lit > -0.2 else S["band"][1]
                    elif rho > Rf - btf + 1:
                        c = S["band"][1]
                    else:
                        c = S["band"][0]
                    if br <= 0 and rho <= Rf - 1:
                        c = S["band"][0]
                    if br < 0 and hsh(x, y, f) < 0.45:
                        c = None
                    if hot >= 0 and c is not None:
                        c = S["hot"][0] if hot < 0.3 else (S["hot"][1] if hot < 0.65 else S["hot"][2])
                elif Rf < rho <= Rf + H and tooth_on:
                    h = tooth_h(u, H)
                    if rho - Rf <= h:
                        tip = (rho - Rf) > h * 0.55
                        if tip:
                            c = S["tooth"][2] if (lit > -0.3 or br >= 2) else S["tooth"][1]
                        else:
                            c = S["tooth"][1] if lit > 0.0 else S["tooth"][0]
                        if dy < 0 and not tip:
                            c = S["tooth"][0]
                        if hot >= 0 and hot < 0.5 and tip:
                            c = S["hot"][0]
                        if S.get("heavy") and f >= 3 and tip:
                            c = SP[3] if f == 3 else ST[3]
                        if 0.72 <= u < 0.86 and not tip and not S.get("whirl"):
                            c = ST[1] if sty != "g" else GH[0]   # 陡面暗一阶：齿形更清楚
                    elif rho - Rf <= h + 1.0 and h > 0.5 and sty != "g":
                        c = SHADOW   # 齿外一圈暗边：在亮地面上也读得出齿
                elif Rf - btf - 6 <= rho <= Rf - btf and br >= 1:
                    # 速度纹：每齿后面拖一段（读出转动方向；锯身扫过的一圈，不平涂）
                    dep = Rf - btf - rho
                    if u < 0.62 - dep * 0.07 and hsh(sty, k, "sl") < 0.8:
                        c = (S["band"][1] if dep < 3 else S["band"][0]) if not S.get("whirl") else (GH[1] if dep < 3 else AB[2])
                        if hot >= 0 and hot < 0.5 and dep < 3:
                            c = S["hot"][2]
                if c is not None:
                    tgt.put(x, y, c)
        # 旋锯：内圈一道回声环（虚线）
        if S.get("whirl") and f < 4:
            for i in range(int(2 * math.pi * R * 0.82 / 2)):
                th = i * 2.0 / (R * 0.82) + phase * 1.6
                if (i // 3) % 2 == 0:
                    continue
                x = cx + R * 0.82 * math.cos(th)
                y = cy + R * 0.82 * math.sin(th) * SY
                (back if y < cy else front).put(x, y, GH[2] if f < 2 else GH[1])
        if S.get("wet") and 1 <= f <= 4:
            _spray(back, front, cx, cy, R, f, R)
        if S.get("heavy") and f <= 3:
            _ring_sparks(back, front, cx, cy, R + H, f, R, head)
        backs.append(back)
        fronts.append(front)
    return backs, fronts, ox, oy


def heavy_frames(R, n=RING_N):
    """S3 重锯（11-05 用户「S3 的锯齿可以更加明显一点」）：齿少、大、尖的三角齿。
    锯身外沿收到 R−4，齿从锯身伸出 11 格，齿尖在 R+7（画面外沿 ≤ 判定 ×1.1）；齿尖一格白高光、上段橙热、中段钢、齿根压暗，
    齿外 + 锯身内沿各一圈 1 格暗描边；每拍往转动方向挪 0.45 个齿距，上一拍的齿位留一道暗残影（看得出往哪边转，
    整齿距一挪反而看着不动）；热弧经过的齿尖甩火星。前后半圈分两张"""
    H, bt, tin = 11, 4, 4
    pad = 18
    rx = R + 7 + pad
    ry = int(math.ceil((R + 7) * SY)) + pad
    W = 2 * rx + 1
    Hh = 2 * ry + LIFT + 3
    cx, cy = rx, ry
    ox, oy = cx, cy + LIFT
    N = max(16, int(round(2 * math.pi * R / 22.0)))
    dth = 2 * math.pi / N
    spin = 0.45
    sc_f = [0.88, 1.0, 1.0, 1.0, 0.97]
    span_f = [math.radians(200), math.radians(130), math.radians(60), 0, 0]
    keep_f = [1.0, 1.0, 1.0, 0.8, 0.45]
    th0 = math.radians(20)

    def prof(u):
        if u < 0.62:
            return H * u / 0.62
        if u < 0.74:
            return H * (1.0 - (u - 0.62) / 0.12)
        return 0.0
    backs, fronts = [], []
    for f in range(n):
        back, front = Cv(W, Hh), Cv(W, Hh)
        Rb = (R - tin) * sc_f[f]
        phase = f * spin * dth
        head = th0 + f * math.radians(78)
        span = span_f[f]
        keep = keep_f[f]
        for y in range(Hh):
            for x in range(W):
                dx, dy = x - cx, y - cy
                rho = math.hypot(dx, dy / SY)
                if rho < Rb - bt - 2 or rho > Rb + H + 1.5:
                    continue
                th = math.atan2(dy / SY, dx)
                tgt = back if dy < 0 else front
                lit = math.cos(th - math.radians(-135))
                hot = -1.0
                if span > 0:
                    da = (head - th) % (2 * math.pi)
                    if da < span:
                        hot = da / span
                u = ((th - phase) / dth) % 1.0
                k = int(math.floor((th - phase) / dth)) % N
                on = hsh("h", R, k, "keep") < keep
                c = None
                if Rb - bt < rho <= Rb:   # 锯身
                    c = AB[4] if (rho > Rb - 1 and lit > -0.2) else (AB[2] if rho > Rb - bt + 1 else AB[1])
                    if hot >= 0:
                        c = SP[1] if hot < 0.3 else (SP[2] if hot < 0.7 else SP[3])
                    if f == 4 and hsh(x, y, "hf") < 0.45:
                        c = None
                elif Rb - bt - 1 < rho <= Rb - bt:
                    c = SHADOW   # 锯身内沿暗描边
                elif rho > Rb:
                    hgt = rho - Rb
                    h = prof(u) if on else 0.0
                    if h > 0 and hgt <= h:
                        q = hgt / h
                        apex = 0.5 < u < 0.68
                        if q > 0.82 and apex:
                            c = AB[7] if f <= 3 else ST[4]   # 齿尖一格白高光
                        elif q > 0.55:
                            c = (SP[1] if f <= 1 else SP[2]) if f <= 2 else (SP[3] if f == 3 else ST[3])
                        elif q > 0.22:
                            c = ST[4] if lit > 0.0 else ST[3]
                        else:
                            c = ST[1]   # 齿根压暗
                        if u >= 0.62 and q <= 0.82:
                            c = ST[2] if q > 0.22 else ST[1]   # 陡面暗
                    elif h > 0 and hgt <= h + 1.0:
                        c = SHADOW   # 齿外暗描边
                    elif f <= 3:   # 上一拍齿位的暗残影（读出转向）
                        up = ((th - phase + spin * dth) / dth) % 1.0
                        kp = int(math.floor((th - phase + spin * dth) / dth)) % N
                        hp = prof(up) if hsh("h", R, kp, "keep") < keep else 0.0
                        if hp > 0 and hgt <= hp * 0.85:
                            c = AB[2] if hgt > hp * 0.4 else AB[1]
                if c is not None:
                    tgt.put(x, y, c)
        if f <= 3:
            _ring_sparks(back, front, cx, cy, R + 6, f, R, head)
            _ring_sparks(back, front, cx, cy, R + 6, f, R + 1, head - 0.8)
        backs.append(back)
        fronts.append(front)
    return backs, fronts, ox, oy


def _spray(back, front, cx, cy, R, f, seed):
    """精二：齿尖顺切线甩出的水珠（受重力往下落），越来越稀"""
    rnd = random.Random(seed * 7 + 3)
    for i in range(14):
        te = rnd.uniform(0, 2 * math.pi)
        sp = rnd.uniform(3.0, 4.5)
        if f > 2 and rnd.random() < 0.35 * (f - 2):
            continue
        tt = f - 0.6
        # 切向（顺时针 = th 增大）+ 少量外向
        tx, ty = -math.sin(te), math.cos(te) * SY
        nx, ny = math.cos(te), math.sin(te) * SY
        px = cx + R * math.cos(te) + (tx * sp + nx * 1.2) * tt
        py = cy + R * math.sin(te) * SY + (ty * sp + ny * 1.2) * tt + 0.9 * tt * tt
        tgt = back if math.sin(te) < 0 else front
        tgt.put(px, py, FOAM if f <= 2 else AB[6])
        tgt.put(px - tx * 1.2, py - ty * 1.2, AB[5])
        if f <= 2:
            tgt.put(px - tx * 2.3, py - ty * 2.3, AB[4])


def _ring_sparks(back, front, cx, cy, R, f, seed, head):
    """重锯：热弧经过处的齿尖甩出橙色火星线（切向飞、受重力）"""
    rnd = random.Random(seed * 13 + 5)
    for i in range(18):
        te = head - rnd.uniform(0.0, 1.6) - 0.3
        sp = rnd.uniform(3.0, 6.0)
        tt = f + 0.5 + rnd.uniform(0, 0.5)
        if rnd.random() < 0.2 * f:
            continue
        tx, ty = -math.sin(te), math.cos(te) * SY
        px = cx + R * math.cos(te) + tx * sp * tt
        py = cy + R * math.sin(te) * SY + ty * sp * tt + 0.8 * tt * tt - 2
        tgt = back if math.sin(te) < 0 else front
        cols = [SP[0], SP[1], SP[2], SP[3]]
        for q in range(3):
            tgt.put(px - tx * q, py - ty * q, cols[min(3, q + f)])


def ring_shadow(R, sty, n=4):
    """锯环正下方贴地的一圈断续接触影（脚底为原点）"""
    rx = R + 6
    ry = int(math.ceil(R * SY)) + 4
    W, Hh = 2 * rx + 1, 2 * ry + 1
    out = []
    for f in range(n):
        cv = Cv(W, Hh)
        Rf = R * (0.86 if f == 0 else 1.0) * 0.96
        steps = int(2 * math.pi * Rf)
        for i in range(steps):
            th = i / Rf
            if (i // 4) % 3 == 2 or (f >= 2 and (i // 4) % 2 == 1):
                continue
            cv.put(rx + Rf * math.cos(th), ry + Rf * math.sin(th) * SY, SHADOW)
        out.append(cv)
    return out, rx, ry


def gouges(R, n=8):
    """重锯：地上 6 道切向锯痕（先橙白，再橙、暗橙，冷成暗沟，断成一节节散掉）"""
    rx = R + 4
    ry = int(math.ceil(R * SY)) + 4
    W, Hh = 2 * rx + 1, 2 * ry + 1
    rnd = random.Random(R * 31)
    gs = []
    for i in range(6):
        a0 = i * math.pi / 3 + rnd.uniform(-0.3, 0.3)
        rr = R * rnd.uniform(0.62, 0.92)
        L = rnd.uniform(0.22, 0.38)
        gs.append((a0, rr, L))
    cols = [SP[0], SP[1], SP[2], SP[3], SP[4], AB[1], AB[1], AB[0]]
    out = []
    for f in range(n):
        cv = Cv(W, Hh)
        for gi, (a0, rr, L) in enumerate(gs):
            steps = int(rr * L)
            for s in range(steps):
                u = s / max(1, steps - 1)
                if f >= 5 and hsh(gi, s, "br") < 0.25 * (f - 4):
                    continue
                th = a0 + u * L
                w = 1 if (u < 0.15 or u > 0.85) else 2
                x = rx + rr * math.cos(th)
                y = ry + rr * math.sin(th) * SY
                c = cols[min(len(cols) - 1, f + (1 if u > 0.7 else 0))]
                cv.put(x, y, c)
                if w == 2:
                    cv.put(x, y + 1, AB[0] if f >= 2 else SP[3])
        out.append(cv)
    return out, rx, ry


# ================================================================ 卷刃 / 震地 / 回声 / 替身脉冲（贴地环类）

def broken_ring(cv, cx, cy, R, col, col2=None, seed=0, gapk=0.25, inner=None, wob=0.0):
    steps = int(2 * math.pi * R)
    for i in range(steps):
        th = i / R
        seg = int(th * 5.0 + hsh(seed, "o") * 5)
        if hsh(seed, seg) < gapk:
            continue
        rr = R + wob * math.sin(th * 7 + seed)
        x = cx + rr * math.cos(th)
        y = cy + rr * math.sin(th) * SY
        cv.put(x, y, col)
        if col2 is not None and (i % 5) < 3:
            cv.put(x, y + 1, col2)
        if inner is not None:
            cv.put(cx + (rr - 2) * math.cos(th), cy + (rr - 2) * math.sin(th) * SY, inner)


def ground_canvas(R, pad=4):
    rx = int(R) + pad
    ry = int(math.ceil(R * SY)) + pad
    return Cv(2 * rx + 1, 2 * ry + 1), rx, ry


def curl_frames(R):
    """精一卷刃：外圈两道往里收的水纹（越收越快、越亮），零星白沫"""
    out = []
    for f in range(6):
        cv, cx, cy = ground_canvas(R)
        k = [0.0, 0.07, 0.16, 0.27, 0.38, 0.47][f]
        r1 = R * (1.0 - k)
        cols = [AB[4], AB[5], AB[5], AB[6], AB[5], AB[4]]
        broken_ring(cv, cx, cy, r1, cols[f], seed=3 + f // 2, gapk=0.3 if f < 4 else 0.55, wob=1.0)
        if f >= 1:
            broken_ring(cv, cx, cy, r1 + 4 + f, AB[3], seed=11, gapk=0.5 + 0.08 * f)
        rnd = random.Random(f * 3 + 1)
        for i in range(8 if f < 4 else 3):
            th = rnd.uniform(0, 2 * math.pi)
            cv.put(cx + r1 * math.cos(th), cy + r1 * math.sin(th) * SY - 1, FOAM)
        out.append(cv)
    return out, cx, cy


def pulse_frames(R, cols, n=5, seed=1, start=0.3, inner=GH[0]):
    """替身闪现法术脉冲 / 替身光环：从 start×R 外扩到 R 的断续环（只画边 + 内侧一格暗边）"""
    out = []
    for f in range(n):
        cv, cx, cy = ground_canvas(R)
        u = f / max(1, n - 1)
        rr = R * (start + (1.0 - start) * (1 - (1 - u) ** 2))
        c = cols[min(len(cols) - 1, f)]
        broken_ring(cv, cx, cy, rr, c, seed=seed + f // 2, gapk=0.28 + 0.14 * u, inner=inner if f < n - 1 else None, wob=1.2)
        if f <= 1:
            broken_ring(cv, cx, cy, rr * 0.62, cols[0], seed=seed + 9, gapk=0.45)
        out.append(cv)
    return out, cx, cy


def quake_gd(R):
    """锯鸣·共振收尾震地：落点一圈不规整裂网（先白后青、冷成暗）+ 环边白沫"""
    out = []
    rnd = random.Random(77)
    cracks = []
    for i in range(9):
        a = i * 2 * math.pi / 9 + rnd.uniform(-0.25, 0.25)
        pts = [(0.18, a)]
        rr, aa = 0.18, a
        while rr < 0.95:
            rr += rnd.uniform(0.1, 0.18)
            aa += rnd.uniform(-0.22, 0.22)
            pts.append((min(rr, 0.97), aa))
        cracks.append(pts)
    cols = [AB[7], GH[3], GH[2], AB[4], AB[3], AB[2], AB[1], AB[1]]
    for f in range(8):
        cv, cx, cy = ground_canvas(R)
        for ci, pts in enumerate(cracks):
            for j in range(len(pts) - 1):
                (r0, a0), (r1, a1) = pts[j], pts[j + 1]
                if f >= 5 and hsh(ci, j, "q") < 0.3 * (f - 4):
                    continue
                L = int(R * (r1 - r0) * 1.4) + 2
                for s in range(L):
                    u = s / L
                    rr = (r0 + (r1 - r0) * u) * R
                    aa = a0 + (a1 - a0) * u
                    cv.put(cx + rr * math.cos(aa), cy + rr * math.sin(aa) * SY, cols[min(7, f + (1 if j > 2 else 0))])
        if f <= 3:
            broken_ring(cv, cx, cy, R * (0.85 + 0.05 * f), FOAM if f < 2 else AB[5], seed=5 + f, gapk=0.3, inner=AB[2])
        out.append(cv)
    return out, cx, cy


def tide_frames(R):
    """血色潮痕（只画边 + 淡内边，深海青；循环 8 拍：边上的水光点慢慢绕）"""
    out = []
    for f in range(8):
        cv, cx, cy = ground_canvas(R)
        broken_ring(cv, cx, cy, R, GH[1], seed=21, gapk=0.12, inner=GH[0])
        for q in range(6):
            th = q * math.pi / 3 + f * math.pi / 24
            x = cx + R * math.cos(th)
            y = cy + R * math.sin(th) * SY
            cv.put(x, y, GH[2])
            cv.put(x + 1, y, GH[2])
        rr = R * (0.5 + 0.4 * (f / 8.0))
        broken_ring(cv, cx, cy, rr, GH[0], seed=40 + f, gapk=0.55)
        out.append(cv)
    return out, cx, cy


# ================================================================ 立起件：光柱、水冠、暗焰、鲨鳍、白闪、冒泡、触须、大浪、水花、泡沫、水刃、锯盘

def up_canvas(w, h, ox, oy):
    return Cv(w, h), ox, oy


def s1_column():
    """S1 起手：头顶落下一道光柱（白芯 2 格 + 冰蓝两侧），砸到脚下爆一下就收"""
    W, Hh = 23, 118
    ox, oy = 11, 112
    out = []
    for f in range(6):
        cv = Cv(W, Hh)
        top = [0, 0, 20, 52, 84, 999][f]
        half = [4, 3, 2, 1, 1, 0][f]
        for y in range(top, oy + 1):
            for dx in range(-half - 1, half + 2):
                ad = abs(dx)
                if ad <= half - 1 or (half <= 1 and ad == 0):
                    c = AB[7] if f <= 1 else AB[6]
                elif ad <= half:
                    c = AB[6] if f <= 1 else AB[5]
                else:
                    c = AB[4] if f <= 2 else None
                if c is not None and not (f >= 3 and hsh(y, dx, f) < 0.2):
                    cv.put(ox + dx, y, c)
        if f <= 2:   # 砸地一下：横向白闪
            w = [10, 7, 4][f]
            for dx in range(-w, w + 1):
                cv.put(ox + dx, oy, AB[7] if abs(dx) < w - 2 else AB[5])
                if abs(dx) < w - 3:
                    cv.put(ox + dx, oy - 1, AB[6])
        out.append(cv)
    return out, ox, oy


def s1_runes(R):
    """S1 脚下符环：断续的 2 格环 + 一圈刻度（转一点点），8 拍收"""
    out = []
    for f in range(8):
        cv, cx, cy = ground_canvas(R, 6)
        if f >= 6 and f % 2:
            out.append(cv)
            continue
        c = AB[7] if f == 0 else (AB[5] if f < 4 else AB[4])
        broken_ring(cv, cx, cy, R, c, col2=AB[3], seed=8, gapk=0.2, inner=AB[2] if f < 5 else None)
        for q in range(12):
            th = q * math.pi / 6 + f * 0.03
            for s in range(3):
                rr = R - 4 - s
                cv.put(cx + rr * math.cos(th), cy + rr * math.sin(th) * SY, AB[4] if f < 5 else AB[3])
        out.append(cv)
    return out, cx, cy


def foot_splash():
    """S1 精一（11-05 用户「脚下的水冠有点奇怪」，取代立起的一圈水冠）：贴地、不规则的几簇短水花往外溅开——
    每簇方向 / 大小 / 起跳时刻都不同，水滴低低抛出落地成白沫点；一侧一道鲨鳍尖破水划过、身后甩起一小片水花。
    贴地层另出一两道压扁的细涟漪（s1splash_gd）。原点 = 脚底，6 拍"""
    W, Hh = 83, 38
    ox, oy = 41, 28
    rnd = random.Random(41)
    clusters = []
    for q in range(5):
        a = q * 2 * math.pi / 5 + rnd.uniform(-0.5, 0.5)
        clusters.append((a, rnd.uniform(10, 16), rnd.uniform(0.0, 1.2), rnd.randint(3, 6), rnd.uniform(0.7, 1.3)))
    out = []
    for f in range(6):
        cv = Cv(W, Hh)
        for ci, (a, r0, d0, nd, sz) in enumerate(clusters):
            t = f - d0
            if t < 0:
                continue
            bx = ox + r0 * math.cos(a)
            by = oy + r0 * math.sin(a) * SY
            for k in range(nd):   # 这一簇的水滴：往外低抛
                aa = a + (hsh(ci, k, "a") - 0.5) * 0.9
                sp = (2.2 + 2.5 * hsh(ci, k, "s")) * sz
                hv = (3.0 + 4.0 * hsh(ci, k, "h")) * sz
                x = bx + math.cos(aa) * sp * t
                hgt = hv * t - 1.6 * t * t
                y = by + math.sin(aa) * SY * sp * t
                if hgt < 0:
                    if t < 4.5:
                        cv.put(x, y, FOAM if t < 3 else AB[5])   # 落地成白沫点
                    continue
                cv.put(x, y - hgt, FOAM if t < 1.5 else AB[6])
                if t < 2.5:
                    cv.put(x - math.cos(aa), y - hgt + 1, AB[5])
            if t < 2.5:   # 簇根一小撮白沫
                for k in range(-2, 3):
                    if hsh(ci, k, f) < 0.7:
                        cv.put(bx + k * math.cos(a + 1.57), by + k * math.sin(a + 1.57) * SY, FOAM if t < 1.5 else AB[5])
        # 鲨鳍尖破水：从右后方往右前方划过，鳍尖 3 格高，身后甩水
        if 1 <= f <= 4:
            u = (f - 1) / 3.0
            fx_ = ox + 14 + 10 * u
            fy_ = oy - 2 + 4 * u
            for s_ in range(4):
                for xx in range(-2 + s_ // 2, 2 - s_ // 3):
                    cv.put(fx_ + xx, fy_ - s_, AB[5] if xx >= 0 else AB[2])
            for k in range(1, 6):
                cv.put(fx_ - 2 - k, fy_ + 1 - (1 if k % 2 else 0) - max(0, 3 - k) * (1 - u), FOAM if k < 3 else AB[5])
        out.append(cv)
    return out, ox, oy


def foot_ripples():
    """S1 精一贴地：一两道压扁的细涟漪，断续、不同心，往外慢慢走"""
    out = []
    for f in range(6):
        cv, cx, cy = ground_canvas(26, 4)
        r1 = 9 + f * 3.0
        if f < 5:
            broken_ring(cv, cx + 1, cy, r1, AB[5] if f < 3 else AB[4], seed=51, gapk=0.4 + 0.06 * f)
        if 1 <= f:
            broken_ring(cv, cx - 2, cy + 1, r1 * 0.7 + 2, AB[4] if f < 4 else AB[3], seed=57, gapk=0.5 + 0.06 * f)
        out.append(cv)
    return out, cx, cy


def s1_aura(tier):
    """S1 期间：身边几缕往上飘的深海暗焰（代替原来的红火，红只给危险），循环 8 拍；精二另有鲨鳍（单独一张）"""
    W, Hh = 49, 64
    ox, oy = 24, 60
    out = []
    for f in range(8):
        cv = Cv(W, Hh)
        for q in range(6):
            th = q * 2 * math.pi / 6 + 0.4
            bx = ox + 15 * math.cos(th)
            by = oy - 3 + 6 * math.sin(th)
            hh = 18 + 10 * hsh(q, "h")
            ph = (f / 8.0 + hsh(q, "p")) % 1.0
            for s in range(int(hh)):
                u = s / hh
                if (u + ph) % 1.0 > 0.72:
                    continue
                sway = 1.6 * math.sin(u * 5.0 + f * 0.8 + q)
                w = 1 if u > 0.45 else 2
                c = AB[7] if u > 0.8 else (AB[6] if u > 0.45 else AB[5])
                for dx in range(w):
                    cv.put(bx + sway + dx, by - s, c)
        out.append(cv)
    return out, ox, oy


def fins():
    """S1 精二：两片鲨鳍绕她游（贴地椭圆 r 28），鳍形 = 前缘凸、后缘凹、鳍尖往后掠，高 12；鳍脚一线白沫 + 身后 V 字尾迹；分前后两张（循环 8 拍）"""
    W, Hh = 79, 48
    ox, oy = 39, 36
    R = 28
    H = 12
    backs, fronts = [], []
    for f in range(8):
        b, fr = Cv(W, Hh), Cv(W, Hh)
        for q in range(2):
            th = f * 2 * math.pi / 8 + q * math.pi
            x0 = ox + R * math.cos(th)
            y0 = oy + R * math.sin(th) * SY
            tgt = b if math.sin(th) < 0 else fr
            sg = 1 if -math.sin(th) >= 0 else -1   # 顺时针游：屏幕上的横向朝向
            for s_ in range(H + 1):
                v = s_ / H
                lead = 5 - 8 * v ** 0.8
                trail = -5 + 2 * v * v
                for xx in range(int(math.floor(trail)), int(math.ceil(lead)) + 1):
                    if xx < trail - 0.3 or xx > lead + 0.3:
                        continue
                    c = AB[2]
                    if xx >= lead - 1.0:
                        c = AB[5]   # 前缘受光
                    elif xx <= trail + 0.8:
                        c = AB[1]
                    tgt.put(x0 + xx * sg, y0 - s_, c)
            for xx in range(-7, 8):   # 鳍脚白沫
                if xx % 3 != 2:
                    tgt.put(x0 + xx * sg, y0 + 1, FOAM if abs(xx) < 5 else AB[5])
            for s_ in range(1, 8):   # V 字尾迹
                for side in (-1, 1):
                    tt = th - s_ * 0.085
                    rr = R + side * s_ * 0.6
                    tg2 = b if math.sin(tt) < 0 else fr
                    tg2.put(ox + rr * math.cos(tt), oy + rr * math.sin(tt) * SY + 1, FOAM if s_ < 4 else AB[5])
        backs.append(b)
        fronts.append(fr)
    return backs, fronts, ox, oy


def s2_cast():
    """S2 起手：脚下一道横向白闪（原作 0.05 秒那一下）+ 几颗气泡往上冒"""
    W, Hh = 61, 70
    ox, oy = 30, 66
    out = []
    rnd = random.Random(5)
    bubbles = [(rnd.uniform(-14, 14), rnd.uniform(0, 3), rnd.uniform(2.5, 4.5), rnd.choice([1, 2])) for _ in range(7)]
    for f in range(9):
        cv = Cv(W, Hh)
        if f <= 3:
            w = [14, 26, 22, 12][f]
            for dx in range(-w, w + 1):
                ad = abs(dx) / w
                cv.put(ox + dx, oy - 1, AB[7] if ad < 0.5 else (AB[6] if ad < 0.8 else AB[5]))
                if ad < 0.3 and f <= 1:
                    cv.put(ox + dx, oy - 2, AB[7])
                    cv.put(ox + dx, oy, AB[6])
        for i, (bx, d, sp, sz) in enumerate(bubbles):
            t = f - d
            if t < 0 or t > 6:
                continue
            x = ox + bx + 1.5 * math.sin(t + i)
            y = oy - 6 - t * sp * 2.2
            c = AB[6] if t < 4 else AB[5]
            if sz == 1:
                cv.put(x, y, c)
            else:
                for (ax, ay) in ((0, -1), (-1, 0), (1, 0), (0, 1)):
                    cv.put(x + ax, y + ay, c)
        out.append(cv)
    return out, ox, oy


def tentacles():
    """S2 精二：身后三道幽蓝触须从地里卷上来（循环 8 拍，身后排序）"""
    W, Hh = 71, 70
    ox, oy = 35, 64
    out = []
    for f in range(8):
        cv = Cv(W, Hh)
        for q in range(3):
            bx = ox + (q - 1) * 16
            L = 46 + 8 * (q % 2)
            for s in range(L):
                u = s / L
                sway = (5 + 4 * u) * math.sin(u * 4.2 + f * 2 * math.pi / 8 + q * 1.9) * u
                curl = (q - 1) * 10 * u * u
                x = bx + sway + curl
                y = oy - 2 - s
                w = 4 if u < 0.35 else (3 if u < 0.7 else 2)
                for dx in range(w):
                    c = (GH[0] if dx == 0 else GH[1]) if dx < w - 1 else GH[2]
                    if u > 0.85:
                        c = GH[3]
                    cv.put(x + dx - w // 2, y, c)
                if u < 0.6 and s % 7 == 3:
                    cv.put(x - w // 2 - 1, y, GH[1])   # 吸盘暗点
        out.append(cv)
    return out, ox, oy


def shark_bite(deg, n=5):
    """S2 精二（11-05 用户「拿鲨鱼来点意象」，取代触须）：环斩时朝最近的敌人一记鲨口咬合——上下两道带锯齿的颌弧从张开到合拢（铰点在靠她一侧），
    合上那一拍齿尖白闪，之后变稀散掉。替身青颌 + 白齿。原点 = 她的脚底；deg 平面角（0 = 向右）"""
    W, Hh = 131, 95
    ox, oy = 65, 60
    d = math.radians(deg)
    fx, fy = math.cos(d), math.sin(d) * SY
    L = math.hypot(fx, fy)
    fx, fy = fx / L, fy / L
    D = 38.0
    cx, cy = ox + fx * D, oy - 12 + fy * D
    hs = 1 if fx >= -0.05 else -1      # 铰点在靠她的一侧（屏幕横向）
    out = []
    gaps = [14, 9, 3, 0, 0]
    for f in range(n):
        cv = Cv(W, Hh)
        gp_ = gaps[f]
        for side in (-1, 1):   # -1 上颌 / 1 下颌
            for i in range(-18, 19):
                u = i / 18.0
                # 从铰点（靠她一侧）到颌尖开口越来越大
                op = gp_ * (0.5 + 0.5 * ((u * hs) + 1) / 2)
                bow = 6.5 * (1 - u * u)
                yb = cy + side * (op + bow)
                x = cx + i
                if f == 4 and hsh(i, side, "bf") < 0.5:
                    continue
                for t_ in range(3):   # 颌身 3 格厚（往外）
                    c = GH[1] if t_ == 2 else GH[2]
                    if f == 3:
                        c = GH[3] if t_ < 2 else GH[2]
                    cv.put(x, yb + side * t_, c)
                if i % 4 == 0 and abs(u) < 0.92:   # 齿：朝内的三角尖
                    for k in range(1, 4):
                        c = AB[7] if (f >= 2 and k == 3) else GH[3]
                        if f == 4:
                            c = GH[2]
                        cv.put(x, yb - side * k, c)
                        if k == 1:
                            cv.put(x + 1, yb - side * k, c)
        if f == 3:   # 合拢的一拍：齿缝一线白闪
            for i in range(-17, 18):
                cv.put(cx + i, cy, AB[7] if abs(i) < 12 else GH[3])
        out.append(cv)
    return out, ox, oy


def splash(scale=1.0, n=7, seed=1, foam=True):
    """水花（替身现身 / 倒下时）：一股不规则水柱冲起、顶端碎成水珠落下，白沫"""
    W = int(48 * scale) | 1
    Hh = int(62 * scale)
    ox, oy = W // 2, Hh - 4
    rnd = random.Random(seed)
    drops = [(rnd.uniform(-1, 1), rnd.uniform(0.6, 1.0), rnd.uniform(0, 1)) for _ in range(22)]
    out = []
    for f in range(n):
        cv = Cv(W, Hh)
        hgt = [14, 30, 40, 36, 24, 10, 0, 0, 0][f] * scale
        for s in range(int(hgt)):
            u = s / max(1, hgt)
            w = (6 - 4 * u) * scale
            for dx in range(-int(w), int(w) + 1):
                edge = abs(dx) >= w - 1
                jag = hsh(s, dx, seed) < 0.18 * u
                if jag:
                    continue
                c = AB[6] if not edge else AB[4]
                if f <= 1 and abs(dx) < 2:
                    c = AB[7]
                cv.put(ox + dx + 1.5 * math.sin(u * 5 + seed), oy - s, c)
        for i, (vx, vy, d) in enumerate(drops):
            t = f - 1 - d
            if t < 0:
                continue
            x = ox + vx * 14 * scale * t / 2.0
            y = oy - hgt * 0.8 - vy * 18 * scale * t + 4.5 * t * t
            if y > oy:
                continue
            cv.put(x, y, FOAM if t < 2 else AB[5])
        if foam and f >= 1:
            broken_ring(cv, ox, oy, (7 + f * 2) * scale, FOAM if f < 4 else AB[5], seed=seed + 3, gapk=0.3 + 0.07 * f)
        out.append(cv)
    return out, ox, oy


def foam_burst(seed=3, n=6, R=16):
    """碎成泡沫：一团白沫 + 泡泡往外散、往上飘"""
    W, Hh = 2 * R + 17, 2 * R + 30
    ox, oy = W // 2, Hh - 6
    rnd = random.Random(seed)
    bs = [(rnd.uniform(0, 2 * math.pi), rnd.uniform(0.4, 1.0), rnd.choice([1, 1, 2])) for _ in range(20)]
    out = []
    for f in range(n):
        cv = Cv(W, Hh)
        u = f / (n - 1)
        for i, (a, sp, sz) in enumerate(bs):
            if hsh(i, f, seed) < u * 0.6:
                continue
            rr = R * sp * (0.3 + 0.9 * u)
            x = ox + rr * math.cos(a)
            y = oy - 18 + rr * math.sin(a) * 0.8 - 10 * u * sp
            c = FOAM if u < 0.4 else (AB[6] if u < 0.7 else AB[5])
            if sz == 1:
                cv.put(x, y, c)
            else:
                for (ax, ay) in ((0, -1), (-1, 0), (1, 0), (0, 1)):
                    cv.put(x + ax, y + ay, c)
        out.append(cv)
    return out, ox, oy


def _noise1(seed, x):
    """一维平滑噪声（节点哈希 + 线性插值）"""
    i = int(math.floor(x))
    f = x - i
    return hsh(seed, i) * (1 - f) + hsh(seed, i + 1) * f


def big_wave(R):
    """S3 起手（11-05 用户「水墙改进一下」：不能是一整块立起来的板子）：浪头断成 6 段，每段是一个隆起的浪包——
    背面缓坡、浪顶往外卷出白唇、高低和起浪时刻各不同、段与段之间留缺口；整段往外推（0.78R → R），
    第 3 拍起浪顶碎成水花和水滴往外甩、受重力落下，浪包从两头塌下去。贴地的压扁细涟漪另出（s3wave_gd）。分前后半圈，8 拍"""
    pad = 22
    rx = R + pad + 4
    ryy = int(math.ceil(R * SY)) + pad
    top = 24
    W, Hh = 2 * rx + 1, 2 * ryy + top + 4
    cx, cy = rx, ryy + top
    ox, oy = cx, cy
    rnd = random.Random(R * 3 + 1)
    segs = []
    a0 = rnd.uniform(0, 1)
    for q in range(6):
        span = rnd.uniform(0.55, 0.8)
        segs.append((a0, span, rnd.uniform(14, 22), rnd.randint(0, 1)))
        a0 += span + rnd.uniform(0.25, 0.45)
    backs, fronts = [], []
    for f in range(8):
        b, fr = Cv(W, Hh), Cv(W, Hh)
        for si, (sa, span, Hs, d0) in enumerate(segs):
            ft = f - d0
            if ft < 0:
                continue
            hk = [0.5, 0.9, 1.0, 0.8, 0.55, 0.3, 0.12, 0.0, 0.0][min(8, ft)]
            rr = R * (0.78 + 0.22 * min(1.0, ft / 3.0))
            steps = int(span * rr * 1.3)
            for i in range(steps):
                u = i / max(1, steps - 1)
                th = sa + u * span
                env = math.sin(u * math.pi) ** 0.8 * (0.7 + 0.3 * _noise1(("seg", si), u * 5))
                if ft >= 3:   # 从两头塌：包络变窄
                    env *= max(0.0, 1.0 - (abs(u - 0.5) * 2) ** 0.6 * 0.35 * (ft - 2))
                hh = Hs * hk * env
                x0 = cx + rr * math.cos(th)
                y0 = cy + rr * math.sin(th) * SY
                back = math.sin(th) < 0
                tgt = b if back else fr
                for s_ in range(int(hh)):
                    v = s_ / max(1.0, hh)
                    lean = 5.0 * v * v
                    xx = x0 + math.cos(th) * lean
                    yy = y0 - s_ + math.sin(th) * SY * lean
                    if back:
                        c = AB[2] if v < 0.5 else AB[3]
                    else:
                        c = AB[3] if v < 0.4 else AB[4]
                        if 0.5 < v < 0.75 and (i // 3) % 3 == 0:
                            c = AB[5]
                    if v > 0.8:
                        c = FOAM if ft < 5 else AB[5]
                    elif v > 0.7 and not back:
                        c = AB[2]
                    if ft >= 4 and hsh(si, i, s_, f) < 0.2 * (ft - 3):
                        continue
                    tgt.put(xx, yy, c)
                if hh > 4:   # 白唇往外卷 2 格
                    for q in (1, 2):
                        tgt.put(x0 + math.cos(th) * (5.0 + q), y0 - hh + 1 + q * 0.6 + math.sin(th) * SY * (5.0 + q), FOAM if ft < 5 else AB[6])
                if ft >= 2 and hh > 2:   # 浪顶碎成水花 / 水滴往外甩
                    for q in range(3):
                        if hsh(si, i, q, "spr") < 0.16:
                            tt = ft - 1.5 + q * 0.3
                            sx = x0 + math.cos(th) * (6 + 4.5 * tt)
                            sy = y0 - hh - 3 * tt + 1.3 * tt * tt + math.sin(th) * SY * (6 + 4.5 * tt)
                            tgt.put(sx, sy, FOAM if tt < 2.5 else AB[6])
                            if tt < 2:
                                tgt.put(sx - math.cos(th), sy + 1, AB[5])
        backs.append(b)
        fronts.append(fr)
    return backs, fronts, ox, oy


def wet_ring(R, n=8):
    """S3 起手贴地：两三道压扁的细涟漪（断续、不同心，往外走），浪脚处零星白沫"""
    out = []
    for f in range(n):
        cv, cx, cy = ground_canvas(R + 6, 6)
        u = f / (n - 1)
        if f < n - 1:
            broken_ring(cv, cx, cy, R * (0.78 + 0.22 * u), AB[5] if f < 4 else AB[4], seed=31, gapk=0.42 + 0.05 * f, wob=1.2)
        if 1 <= f < n - 1:
            broken_ring(cv, cx + 2, cy - 1, R * (0.62 + 0.2 * u), AB[4] if f < 5 else AB[3], seed=37, gapk=0.5 + 0.05 * f)
        if 2 <= f:
            broken_ring(cv, cx - 3, cy + 1, R * (0.45 + 0.2 * u), AB[3], seed=43, gapk=0.6 + 0.04 * f)
        if f <= 4:
            rnd = random.Random(f + 9)
            for i in range(8):
                th = rnd.uniform(0, 2 * math.pi)
                cv.put(cx + R * (0.8 + 0.2 * u) * math.cos(th), cy + R * (0.8 + 0.2 * u) * math.sin(th) * SY, FOAM)
        out.append(cv)
    return out, cx, cy


def water_blade(deg, n=2):
    """锯鸣·共振的水刃：往前飞的水月牙（凸面朝前），白芯、蓝身、两头甩白沫；deg 平面角（0 = 向右，正 = 往下）"""
    W, Hh = 37, 37
    ox, oy = 18, 30   # 原点 = 地面点；刃身在地面上方 12
    d = math.radians(deg)
    dx, dy = math.cos(d), math.sin(d) * SY
    L = math.hypot(dx, dy)
    dx, dy = dx / L, dy / L
    nx, ny = -dy, dx
    out = []
    for f in range(n):
        cv = Cv(W, Hh)
        cxp, cyp = ox, oy - 12
        for i in range(-9, 10):
            u = i / 9.0
            th = 1.0 - u * u
            back = -6.0 * u * u
            for s in range(int(1 + 3 * th)):
                x = cxp + nx * i * 1.05 + dx * (back - s)
                y = cyp + ny * i * 1.05 + dy * (back - s)
                c = AB[7] if s == 0 and abs(u) < 0.6 else (AB[6] if s <= 1 else AB[4])
                cv.put(x, y, c)
        for t in (-1, 1):   # 两头甩白沫
            x = cxp + nx * t * 10 - dx * (7 + f * 2)
            y = cyp + ny * t * 10 - dy * (7 + f * 2)
            cv.put(x, y, FOAM)
            cv.put(x - dx * 2, y - dy * 2, AB[5])
        # 地上淡影
        for i in range(-6, 7):
            cv.put(ox + nx * i, oy + ny * i * 0.5, SHADOW if i % 3 else None)
        out.append(cv)
    return out, ox, oy


def qi_disc(tier, n=4):
    """后期剑气（late_shape 给的额外一击）= 横着飞出去的锯盘：压扁的带齿圆盘，齿每拍转；精一齿尖橙热，精二外圈一圈水沫"""
    R = 11
    H = 3
    pad = 5
    W = 2 * (R + H + pad) + 1
    Hh = int(2 * (R + H + pad) * SY) + 16
    cx = W // 2
    cy = int((R + H + pad) * SY) + 2
    ox, oy = cx, cy + 12
    N = 12
    dth = 2 * math.pi / N
    out = []
    for f in range(n):
        cv = Cv(W, Hh)
        ph = f * 0.45 * dth
        for y in range(Hh):
            for x in range(W):
                ddx, ddy = x - cx, (y - cy) / SY
                rho = math.hypot(ddx, ddy)
                if rho > R + H + 0.5:
                    continue
                th = math.atan2(ddy, ddx)
                lit = math.cos(th - math.radians(-135))
                c = None
                if rho <= 2.2:
                    c = AB[5] if tier < 2 else GH[3]
                elif rho <= R - 2:
                    c = ST[2] if lit < 0.2 else ST[3]
                    if R - 4 < rho <= R - 2 and lit > 0.3:
                        c = ST[4]
                    # 盘面四道镂空（读出转动）
                    if abs(((th - ph * 2) / (math.pi / 2)) % 1.0 - 0.5) < 0.08 and rho > 3.5:
                        c = ST[1]
                elif rho <= R:
                    c = ST[4] if lit > -0.2 else ST[3]
                else:
                    u = ((th - ph) / dth) % 1.0
                    if rho - R <= tooth_h(u, H) + 0.3:
                        c = (SP[1] if tier >= 1 else ST[5]) if lit > -0.4 else (SP[2] if tier >= 1 else ST[3])
                if c is not None:
                    cv.put(x, y, c)
        if tier >= 2:
            broken_ring(cv, cx, cy, R + H + 3, AB[5], seed=f + 4, gapk=0.45)
        # 地上一小块影
        for i in range(-6, 7):
            if i % 4 != 3:
                cv.put(ox + i, oy, SHADOW)
        out.append(cv)
    return out, ox, oy


# ================================================================ 输出

def emit_pts(cv, cap=48):
    a = cv.a
    pts = []
    hot = np.zeros(a.shape[:2], bool)
    for c in HOT:
        hot |= (a[..., 0] == c[0]) & (a[..., 1] == c[1]) & (a[..., 2] == c[2]) & (a[..., 3] > 0)
    ys, xs = np.nonzero(hot)
    idx = list(range(len(xs)))
    if len(idx) > cap:
        step = len(idx) / cap
        idx = [int(i * step) for i in range(cap)]
    for i in idx:
        c = a[ys[i], xs[i]]
        pts.append([int(xs[i]), int(ys[i]), "%02x%02x%02x" % (c[0], c[1], c[2])])
    return pts


def write_import(name):
    dst = os.path.join(OUT_ART, name + ".import")
    if os.path.exists(dst) or not os.path.exists(TMPL):
        return
    s = open(TMPL, encoding="utf-8").read()
    rp = "res://art/fx/pxp/" + name
    h = hashlib.md5(rp.encode()).hexdigest()
    old_src = s.split('source_file="')[1].split('"')[0]
    old_dest = s.split('dest_files=["')[1].split('"')[0]
    old_uid = s.split('uid="')[1].split('"')[0]
    new_dest = "res://.godot/imported/%s-%s.ctex" % (name, h)
    uid = "uid://" + "".join(random.Random(name).choice("abcdefghijklmnopqrstuvwxy0123456789") for _ in range(13))
    s = s.replace(old_dest, new_dest).replace(old_src, rp).replace(old_uid, uid)
    open(dst, "w", encoding="utf-8", newline="\n").write(s)


META = {}


def save(key, frames, ox, oy, loop=False):
    w, h = frames[0].w, frames[0].h
    sheet = np.concatenate([f.a for f in frames], axis=1)
    name = "pxp_su_%s.png" % key.replace("_d-", "_dm")
    Image.fromarray(sheet, "RGBA").save(os.path.join(OUT_ART, name), optimize=True)
    write_import(name)
    META[key] = {"n": len(frames), "fps": FPS, "w": w, "h": h, "ox": int(ox), "oy": int(oy), "loop": bool(loop), "emit": [emit_pts(f) for f in frames]}


RING_R = {"n": [51, 58, 66], "w": [51, 58, 66], "d": [36, 41, 46, 53], "s": [66, 76, 88], "h": [76, 88, 100]}
DIRS = [-90, -45, 0, 45, 90]


def build(only=""):
    def want(k):
        return only == "" or k.startswith(only)
    for sty, rs in RING_R.items():
        for R in rs:
            k = "saw_%s_r%d" % (sty, R)
            if not want(k):
                continue
            b, fr, ox, oy = heavy_frames(R) if sty == "h" else ring_frames(R, sty)
            save(k + "_bk_up", b, ox, oy)
            save(k + "_fr_up", fr, ox, oy)
            if STYLES[sty]["shadow"]:
                sh, sx, sy = ring_shadow(R, sty)
                save(k + "_gd", sh, sx, sy)
    for R in RING_R["h"]:
        if want("gouge"):
            gg, gx, gy = gouges(R)
            save("gouge_r%d_gd" % R, gg, gx, gy)
    for R in [51, 58, 66, 76, 88, 100]:
        if want("tide"):
            tt, tx, ty = tide_frames(R)
            save("tide_r%d_gd" % R, tt, tx, ty, loop=True)
    if want("curl"):
        for R in [80, 90]:
            cc, cx, cy = curl_frames(R)
            save("curl_r%d_gd" % R, cc, cx, cy)
    if want("echo"):
        ee, ex, ey = pulse_frames(51, [AB[7], AB[6], AB[5]], n=3, seed=4, start=0.8, inner=AB[2])
        save("echo_gd", ee, ex, ey)
    if want("quake"):
        qq, qx, qy = quake_gd(80)
        save("quake_gd", qq, qx, qy)
        ss, sx, sy = splash(1.2, 8, seed=9)
        save("quake_up", ss, sx, sy)
    if want("s1"):
        c1, x1, y1 = s1_column()
        save("s1col_up", c1, x1, y1)
        rr, rx, ry = s1_runes(60)
        save("s1rune_gd", rr, rx, ry)
        cr, cx, cy = foot_splash()
        save("s1splash_up", cr, cx, cy)
        rp, rx2, ry2 = foot_ripples()
        save("s1splash_gd", rp, rx2, ry2)
        au, ax, ay = s1_aura(0)
        save("s1aura_up", au, ax, ay, loop=True)
        fb, ff, fx, fy = fins()
        save("s1fin_bk_up", fb, fx, fy, loop=True)
        save("s1fin_fr_up", ff, fx, fy, loop=True)
    if want("s2"):
        s2, x2, y2 = s2_cast()
        save("s2cast_up", s2, x2, y2)
        p2, px2, py2 = pulse_frames(22, [AB[7], AB[6], AB[5], AB[4]], n=4, seed=6, start=0.4, inner=None)
        save("s2cast_gd", p2, px2, py2)
        for dg in DIRS:
            bb, bx, by = shark_bite(dg)
            save("s2bite_up_d%d" % dg, bb, bx, by)
    if want("s3"):
        wb, wf, wx, wy = big_wave(76)
        save("s3wave_bk_up", wb, wx, wy)
        save("s3wave_fr_up", wf, wx, wy)
        wr, rx3, ry3 = wet_ring(76)
        save("s3wave_gd", wr, rx3, ry3)
    if want("doll"):
        si, sx, sy = splash(1.0, 7, seed=2)
        save("dollin_up", si, sx, sy)
        dp, dx, dy = pulse_frames(84, [GH[3], GH[2], GH[2], GH[1], GH[1], GH[0]], n=6, seed=12, start=0.86)
        save("dollpulse_gd", dp, dx, dy)
        fo, fx, fy = foam_burst(7, 6, 14)
        save("dollout_up", fo, fx, fy)
    if want("fl"):
        si, sx, sy = splash(0.8, 5, seed=4)
        save("flin_up", si, sx, sy)
        pp, px_, py_ = pulse_frames(70, [GH[3], GH[3], GH[2], GH[1]], n=4, seed=15, start=0.2)
        save("flpulse_gd", pp, px_, py_)
        fo, fx, fy = foam_burst(11, 6, 18)
        save("flout_up", fo, fx, fy)
    if want("blade"):
        for dg in DIRS:
            bb, bx, by = water_blade(dg)
            save("blade_up_d%d" % dg, bb, bx, by, loop=True)
    if want("qi"):
        for t in range(3):
            qq, qx, qy = qi_disc(t)
            save("qi_e%d_up" % t, qq, qx, qy, loop=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    a = ap.parse_args()
    old = {}
    if a.only and os.path.exists(OUT_META):
        old = json.load(open(OUT_META, encoding="utf-8"))
    build(a.only)
    old.update(META)
    old["_doc"] = "docs/268 归溟幽灵鲨转平面帧条（tools/pxplane_su_art.py 生成，勿手改）：n 帧数、fps、w×h 帧尺寸（美术像素）、ox / oy 原点（脚底地面点）、loop、emit 每帧热芯点 [x, y, 颜色]"
    keys = sorted(k for k in old if k != "_doc")
    out = {"_doc": old["_doc"]}
    for k in keys:
        out[k] = old[k]
    with open(OUT_META, "w", encoding="utf-8", newline="\n") as f:
        json.dump(out, f, ensure_ascii=False, separators=(",", ":"))
    print("strips", len(keys))


if __name__ == "__main__":
    main()
