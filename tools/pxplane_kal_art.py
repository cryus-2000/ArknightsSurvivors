#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""凯尔希 + Mon3tr 转平面帧条（docs/265，fx/px_plane）：程序逐像素画，不用 pixelfx 库、不开 Godot。

口径同 docs/246：1 帧条像素 = 1 美术像素（游戏里 × g.PX = 2 世界像素）；15 fps；贴地层生成时按 SY = 0.72 压扁；
立起层竖直（腰高的东西按 SY 压扁后抬高）；原点 (ox, oy) = 地面点（脚底）。emit = 每帧热芯像素 [x, y, 颜色]，≤ 48 点。
色：Mon3tr 黑 / 墨绿 / 荧光绿（攻击）；治疗是骨白 + 薄荷（不用红，和攻击的荧光黄绿分开）。

输出：game/art/fx/pxp/pxp_ka_<键>.png（横排帧）+ game/data/pxp_kaltsit.json（键不带前缀，fx_pxplane METAS 加 ka_）。
用法：python tools/pxplane_kal_art.py
"""
import json, math, os, random

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_ART = os.path.join(ROOT, "game", "art", "fx", "pxp")
OUT_META = os.path.join(ROOT, "game", "data", "pxp_kaltsit.json")
SY = 0.72

# Mon3tr（攻击）：黑 → 墨绿 → 荧光绿 → 热白
M = {
    "k": (9, 13, 10), "d1": (17, 36, 23), "d2": (30, 62, 34), "m1": (52, 104, 38), "m2": (104, 176, 44),
    "f": (170, 242, 62), "h": (230, 255, 168), "w": (255, 255, 255),
}
# 治疗：薄荷 + 骨白（不用红；和荧光黄绿拉开：偏冷、低饱和）
HC = {"d": (24, 66, 52), "m": (70, 168, 124), "l": (160, 232, 196), "b": (238, 246, 228), "w": (255, 255, 255)}
HOT = {M["h"], M["w"], HC["b"], HC["w"], M["f"]}

META = {}


def hx(c):
    return "%02x%02x%02x" % c


class Strip:
    """n 帧 × (w, h)；原点 (ox, oy)。"""

    def __init__(self, n, w, h, ox, oy, loop=False):
        self.n, self.w, self.h, self.ox, self.oy, self.loop = n, w, h, ox, oy, loop
        self.a = np.zeros((n, h, w, 4), np.uint8)

    def put(self, f, x, y, c, a=255, over=True):
        x, y = int(round(x)), int(round(y))
        if 0 <= f < self.n and 0 <= x < self.w and 0 <= y < self.h:
            if not over and self.a[f, y, x, 3] > 0:
                return
            self.a[f, y, x, :3] = c
            self.a[f, y, x, 3] = a

    # 地面点（相对原点，美术像素；y 已是压扁后的）→ 画布
    def gput(self, f, gx, gy, c, a=255, lift=0.0, over=True):
        self.put(f, self.ox + gx, self.oy + gy - lift, c, a, over)

    def save(self, key, emit_hot=True):
        os.makedirs(OUT_ART, exist_ok=True)
        img = np.concatenate([self.a[i] for i in range(self.n)], axis=1)
        Image.fromarray(img, "RGBA").save(os.path.join(OUT_ART, "pxp_ka_%s.png" % key.replace("_d-", "_dm")))
        emit = []
        for i in range(self.n):
            pts = []
            if emit_hot:
                ys, xs = np.nonzero(self.a[i, :, :, 3] > 200)
                for y, x in zip(ys, xs):
                    c = tuple(int(v) for v in self.a[i, y, x, :3])
                    if c in (M["h"], M["w"], HC["w"], HC["b"]):
                        pts.append([int(x), int(y), hx(c)])
                if len(pts) > 48:
                    step = len(pts) / 48.0
                    pts = [pts[int(j * step)] for j in range(48)]
            emit.append(pts)
        META[key] = {"n": self.n, "fps": 15, "w": self.w, "h": self.h, "ox": self.ox, "oy": self.oy, "loop": self.loop, "emit": emit}


def seg_px(p0, p1):
    """两点间逐像素（含端点）"""
    x0, y0 = p0
    x1, y1 = p1
    n = int(max(abs(x1 - x0), abs(y1 - y0))) + 1
    return [(x0 + (x1 - x0) * i / max(1, n - 1), y0 + (y1 - y0) * i / max(1, n - 1)) for i in range(n)]


# ================================================================ Mon3tr 爪击（三道平行爪痕，腰高、按 SY 压扁、朝右；左边水平翻转）
CLAW_R = [109, 128, 161, 200]     # 判定外沿（世界像素 = reach + pad）分档；游戏里取 ≤ (reach + pad) × 1.1 的最大一档
LIFT = 7                          # 腰高（美术像素，= fx_origin −14 世界）


def rake(Rw, sw):
    """三道平行爪痕（不是同心圈）：在 Mon3tr 前方 0.5–0.9 R 处、腰高，斜着一道道划下去；
    三道沿法线平移错开（不按半径缩放），微弯、中段厚两头针尖。sw = 0：右上 → 左下；1：左上 → 右下（双爪第二下交叉）。
    返回 (up, gd_e0 阴影, gd_e1 阴影 + 犁痕)"""
    R = Rw / 2.0
    C = (R * 0.62, 0.0)                       # 爪痕中心（地面点，美术像素）
    half = R * 0.40                           # 半长（屏幕坐标，已含压扁后的纵向）；两端落在判定外沿以内
    ang = math.radians(112 if sw == 0 else 68)   # 屏幕里的笔画方向（向下偏左 / 偏右）
    D = (math.cos(ang), math.sin(ang))
    Nn = (-D[1], D[0])
    bow = R * 0.07 * (1 if sw == 0 else -1)
    gap = 4.0 + R * 0.025
    strokes = [(-gap, 2, -0.06), (0.0, 3, 0.0), (gap, 2, 0.06)]
    w = int(R + 10)
    h = int(2 * R * SY + LIFT + 14)
    ox, oy = 3, int(R * SY + LIFT + 6)
    up = Strip(5, w, h, ox, oy)
    gw = int(2 * R * SY + 10)
    gd0 = Strip(4, w, gw, ox, int(R * SY + 5))
    gd1 = Strip(10, w, gw, ox, int(R * SY + 5))
    N = 160

    def pt(off, u, sh):
        t = (u - 0.5 + sh) * 2 * half
        b = bow * math.sin(math.pi * u)
        return (C[0] + D[0] * t + Nn[0] * (off + b), C[1] + D[1] * t + Nn[1] * (off + b))

    for si, (off, T, sh) in enumerate(strokes):
        for f in range(5):
            reveal = [0.55, 1.0, 1.0, 1.0, 1.0][f]
            tk = [T, T, T, max(1, T - 1), 1][f]
            for i in range(N):
                u = i / (N - 1)
                if u > reveal:
                    continue
                s_ = math.sin(math.pi * u)
                tt = max(1, int(round(tk * s_ ** 0.6 + 0.3)))
                if s_ < 0.15:
                    tt = 1
                if f == 4 and (i // 5) % 3 == 0:
                    continue
                x, y = pt(off, u, sh)
                for k in range(tt):
                    # 亮边在挥出方向的前沿（法线 −），往后一阶阶变暗
                    xx, yy = x - Nn[0] * k, y - Nn[1] * k
                    if f == 0:
                        c = M["w"] if (k == 0 and u > reveal - 0.14) else (M["h"] if k == 0 else M["f"])
                    elif f == 1:
                        c = M["w"] if k == 0 else (M["h"] if k == 1 else M["f"])
                    elif f == 2:
                        c = M["h"] if k == 0 else M["f"]
                    elif f == 3:
                        c = M["f"] if k == 0 else M["m2"]
                    else:
                        c = M["m1"] if k == 0 else M["d2"]
                    up.gput(f, xx, yy, c, lift=LIFT)
                if f <= 2 and s_ > 0.2:   # 后沿墨绿暗边（亮地面也读得出）
                    up.gput(f, x - Nn[0] * tt, y - Nn[1] * tt, M["d1"], lift=LIFT, over=False)
            # 投影阴影（同形贴地）
            if f <= 3:
                for i in range(N):
                    u = i / (N - 1)
                    x, y = pt(off, u, sh)
                    tt = max(1, int(round(T * math.sin(math.pi * u) ** 0.6)))
                    for k in range(tt):
                        al = [60, 85, 65, 35][f]
                        gd0.gput(f, x - Nn[0] * k, y - Nn[1] * k, (0, 0, 0), al)
                        gd1.gput(f, x - Nn[0] * k, y - Nn[1] * k, (0, 0, 0), al)
        # 精一犁痕：每道爪痕中段在地上留一道短沟（黑芯 + 一侧荧光边），停 10 拍逐渐熄
        for f in range(10):
            for i in range(N):
                u = i / (N - 1)
                if not (0.3 <= u <= 0.7):
                    continue
                if f < 2 and u > 0.3 + (f + 1) * 0.22:
                    continue
                x, y = pt(off, u, sh)
                gd1.gput(f, x, y, M["k"], 230 if f < 7 else 150)
                rim = M["f"] if f < 3 else (M["m2"] if f < 6 else M["d2"])
                if f < 9 and (f < 6 or i % 2 == 0):
                    gd1.gput(f, x - Nn[0], y - Nn[1], rim, 255 if f < 7 else 160)
    return up, gd0, gd1


def melt_claw(Rw, sw):
    """S3 熔毁爪：一道粗重的黑芯月牙（荧光外刃 + 热白刃线），刃上往下滴荧光熔滴。"""
    R = Rw / 2.0
    A = math.radians(70)
    tilt = math.radians(10 if sw == 0 else -10)
    r = R * 0.86
    w = int(R + 8)
    h = int(2 * R * SY + LIFT + 14)
    ox, oy = 3, int(R * SY + LIFT + 4)
    up = Strip(7, w, h, ox, oy)
    gd = Strip(7, w, int(2 * R * SY + 8), ox, int(R * SY + 4))
    N = 260
    rnd = random.Random(31 + sw)
    drips = [(rnd.uniform(0.2, 0.8), rnd.uniform(0.0, 1.0)) for _ in range(7)]
    for f in range(7):
        reveal = 0.65 if f == 0 else 1.0
        T = [6, 7, 6, 5, 3, 2, 1][f]
        for i in range(N):
            u = i / (N - 1)
            uu = u if sw == 0 else 1.0 - u
            if uu > reveal:
                continue
            th = -A + 2 * A * u + tilt * (u - 0.5) * 2
            s = math.sin(math.pi * u) ** 0.55
            tt = max(1, int(round(T * s)))
            if f >= 5 and (i // 3) % 2 == 0:
                continue
            for k in range(tt):
                gx, gy = (r - k) * math.cos(th), (r - k) * math.sin(th) * SY
                if k == 0:
                    c = M["w"] if f <= 1 else (M["h"] if f == 2 else (M["f"] if f <= 4 else M["m2"]))
                elif k == 1 and f <= 4:
                    c = M["f"] if f <= 2 else M["m2"]
                elif k == tt - 1 and tt > 2:
                    c = M["k"]
                elif k <= 3:
                    c = M["m1"] if f <= 3 else M["d2"]
                else:
                    c = M["d2"] if f <= 3 else M["d1"]
                up.gput(f, gx, gy, c, lift=LIFT)
            # 阴影 + 焦痕
            for k in range(max(1, int(round(6 * s)))):
                gx, gy = (r - k) * math.cos(th), (r - k) * math.sin(th) * SY
                gd.gput(f, gx, gy, M["k"] if f >= 2 and k < 2 else (0, 0, 0), [80, 110, 160, 150, 120, 80, 50][f])
        # 熔滴：从刃上落下（有重量），落地成荧光点
        if f >= 2:
            for (du, dv) in drips:
                th = -A + 2 * A * du
                gx, gy = r * math.cos(th), r * math.sin(th) * SY
                t = f - 2 + dv
                drop = 0.9 * t * t
                if drop < LIFT:
                    up.gput(f, gx, gy - 0, M["f"] if t < 2 else M["m2"], lift=LIFT - drop)
                    up.gput(f, gx, gy, M["m2"], lift=LIFT - drop + 1)
                else:
                    gd.gput(f, gx, gy, M["f"] if f < 5 else M["m1"])
    return up, gd


# ================================================================ 晶刺（精二爪击命中 / 清创）：3 根黑晶刺从敌人脚下戳出来
def crystal(st, f, gx, gy, hgt, wid, lean, hot=False, crack=False, lift=0.0):
    """竖直菱柱晶体：左面墨绿方格、右面黑、棱荧光、尖热白"""
    for yy in range(int(hgt)):
        t = yy / max(1, hgt - 1)
        half = wid * (math.sin(math.pi * min(1.0, t * 1.15)) ** 0.7) * 0.5
        if t > 0.86:
            half = wid * 0.5 * (1 - t) / 0.14 * 0.6
        cx = gx + lean * yy
        for xx in range(-int(round(half)), int(round(half)) + 1):
            if crack and (xx + yy) % 4 == 0:
                continue
            if xx < 0:
                c = M["m1"] if ((xx + yy) // 2) % 2 == 0 else M["d2"]
            elif xx == 0:
                c = M["f"]
            else:
                c = M["d1"] if (yy % 3) else M["d2"]
            if abs(xx) == int(round(half)) and abs(xx) > 0:
                c = M["k"]   # 外轮廓一圈黑（亮地面 / 怪身上也读得出）
            st.gput(f, cx + xx, gy, c, lift=lift + yy)
        if yy == int(hgt) - 1:
            st.gput(f, cx, gy, M["w"] if hot else M["h"], lift=lift + yy)


def spike():
    up = Strip(6, 24, 24, 12, 21)
    gd = Strip(6, 24, 9, 12, 4)
    shards = [(0, 0, 12, 4, 0.0), (-4, 1, 8, 3, -0.35), (4, 1, 7, 3, 0.4)]
    for f in range(6):
        k = [0.5, 1.0, 1.0, 0.95, 0.8, 0.0][f]
        for (dx, dy, hh, ww, ln) in shards:
            if f == 5:
                for j in range(3):
                    up.gput(f, dx + (j - 1) * 2 + ln * 6, dy, M["d1"] if j else M["m1"], lift=1 + j % 2)
                continue
            crystal(up, f, dx, dy, max(2, hh * k), ww, ln, hot=f == 1, crack=f == 4)
        for a in (0.3, 2.2, 4.0):
            L = [3, 5, 5, 4, 3, 2][f]
            for i in range(L):
                gd.gput(f, math.cos(a) * (i + 2), math.sin(a) * (i + 2) * SY, M["k"], 200 if f < 4 else 110)
    return up, gd


# ================================================================ 精一扑击落地（半径 40）：腰高交叉爪 X + 地上四道爪印
def pounce():
    up = Strip(5, 48, 46, 12, 36)   # 交叉爪在落点前方 10（朝右；朝左水平翻转），伸到半径 40 以内，不被 Mon3tr 身体挡
    for f in range(5):
        for sgn in (1, -1):
            ang = math.radians(62 if sgn > 0 else 118)
            D = (math.cos(ang), math.sin(ang))
            Nn = (-D[1], D[0])
            N = 60
            for i in range(N):
                u = i / (N - 1)
                if f == 0 and u > (0.55 if sgn > 0 else 0.35):
                    continue
                t = (u - 0.5) * 24
                b = 3 * math.sin(math.pi * u) * sgn
                x, y = 10 + D[0] * t + Nn[0] * b, D[1] * t + Nn[1] * b
                sm = math.sin(math.pi * u)
                T = [3, 3, 3, 2, 1][f]
                tt = max(1, int(round(T * sm ** 0.6 + 0.2)))
                if f == 4 and (i // 4) % 2 == 0:
                    continue
                for k in range(tt):
                    if f <= 1:
                        c = M["w"] if k == 0 else (M["h"] if k == 1 else M["f"])
                    elif f == 2:
                        c = M["h"] if k == 0 else M["f"]
                    elif f == 3:
                        c = M["f"] if k == 0 else M["m2"]
                    else:
                        c = M["m1"]
                    up.put(f, up.ox + x - Nn[0] * k, up.oy - 14 + y - Nn[1] * k, c)
                if f <= 2 and sm > 0.2:
                    up.put(f, up.ox + x - Nn[0] * tt, up.oy - 14 + y - Nn[1] * tt, M["d1"], over=False)
    gd = Strip(9, 44, 26, 22, 13)
    for f in range(9):
        for a in (0.62, 2.52, 3.76, 5.66):
            L = 12 if f > 0 else 6
            for i in range(4, 4 + L):
                gx, gy = math.cos(a) * i, math.sin(a) * i * SY
                gd.gput(f, gx, gy, M["k"], 230 if f < 6 else 140)
                if f < 7 and i % (1 if f < 4 else 2) == 0:
                    rim = M["f"] if f < 3 else (M["m2"] if f < 5 else M["d2"])
                    gd.gput(f, gx - math.sin(a), gy + math.cos(a) * SY, rim)
    return up, gd


# ================================================================ 精二回防 / 护主落地（半径 100）：一圈黑骨刺破土 + 贴地冲击环
def guard_land(Rw=100):
    R = Rw / 2.0
    rr = R * 0.74
    w = int(2 * R + 10)
    h_up = int(2 * R * SY + 32)
    bk = Strip(7, w, h_up, w // 2, int(R * SY + 26))
    fr = Strip(7, w, h_up, w // 2, int(R * SY + 26))
    gd = Strip(8, w, int(2 * R * SY + 8), w // 2, int(R * SY + 4))
    rnd = random.Random(5)
    sp = [(i * 2 * math.pi / 11 + rnd.uniform(-0.12, 0.12), rnd.uniform(10, 16), rnd.uniform(0.85, 1.05)) for i in range(11)]
    for f in range(7):
        k = [0.45, 1.0, 1.0, 0.9, 0.7, 0.35, 0.0][f]
        for (a, hh, rk) in sorted(sp, key=lambda s: math.sin(s[0])):
            gx, gy = rr * rk * math.cos(a), rr * rk * math.sin(a) * SY
            st = bk if math.sin(a) < 0 else fr
            if f == 6:
                st.gput(f, gx, gy, M["d1"])
                st.gput(f, gx + 1, gy, M["k"])
                continue
            crystal(st, f, gx, gy, max(2, hh * k), 6, math.cos(a) * 0.18, hot=f == 1, crack=f >= 4)
    for f in range(8):
        r = R * [0.55, 0.78, 0.92, 1.0, 1.0, 1.0, 1.0, 1.0][f]
        n = int(2 * math.pi * r * 1.3)
        for i in range(n):
            a = 2 * math.pi * i / n
            gx, gy = r * math.cos(a), r * math.sin(a) * SY
            if f <= 3:
                gd.gput(f, gx, gy, M["f"] if f <= 1 else M["m2"])
                gd.gput(f, gx * (r - 1) / r, gy * (r - 1) / r, M["d1"], 200)
            elif (i + f) % [1, 2, 3, 4, 5][f - 3] == 0:
                gd.gput(f, gx, gy, M["d2"] if f < 6 else M["d1"], 200 if f < 6 else 120)
    return bk, fr, gd


# ================================================================ 治疗（不分攻击色）：E0 贴地缝合环；E1 + 胸前骨白十字；E2 + 竖直下针光柱
def heal_ring():
    gd = Strip(8, 34, 24, 17, 12)
    for f in range(8):
        r = [9, 12, 14, 14, 14, 14, 14, 14][f]
        n = int(2 * math.pi * r * 1.4)
        for i in range(n):
            a = 2 * math.pi * i / n
            if f >= 5 and (i // 2) % (f - 3) != 0:
                continue
            c = HC["b"] if f == 2 else (HC["l"] if f <= 3 else HC["m"] if f <= 5 else HC["d"])
            gd.gput(f, r * math.cos(a), r * math.sin(a) * SY, c)
        if f <= 5:   # 缝合针脚：6 道垂直于环的小短线
            for j in range(6):
                a = 2 * math.pi * j / 6 + 0.26
                for d in (-1, 0, 1):
                    gd.gput(f, (r + d) * math.cos(a), (r + d) * math.sin(a) * SY, HC["b"] if f <= 2 else HC["l"])
    return gd


def heal_cross():
    """骨白十字：头顶上方（不被身体挡），臂宽 3、边长 11，薄荷描边；往上飘一点后熄"""
    up = Strip(9, 15, 64, 7, 62)
    for f in range(9):
        y0 = 50 + min(f, 6) * 0.6
        if f >= 7 and f % 2 == 1:
            continue
        for x in range(-6, 7):
            for y in range(-6, 7):
                if not (abs(x) <= 2 or abs(y) <= 2):
                    continue
                edge = abs(x) == 6 or abs(y) == 6 or (abs(x) == 3 and abs(y) > 2) or (abs(y) == 3 and abs(x) > 2) or (abs(x) == 2 and abs(y) > 2 and abs(y) == 6) 
                inner = abs(x) <= 2 and abs(y) <= 5 or abs(y) <= 2 and abs(x) <= 5
                if not inner and not edge:
                    continue
                c = HC["m"] if (edge or not inner) else (HC["w"] if f <= 1 else HC["b"])
                if f >= 5:
                    c = HC["d"] if (edge or not inner) else HC["l"]
                up.gput(f, x, y, c, lift=y0)
    return up


def heal_column():
    """下针光柱：一道细光从高处落到目标脚下，随即撑成 3 宽的竖直光柱，再从下往上收"""
    up = Strip(7, 11, 64, 5, 62)
    H_ = 54
    for f in range(7):
        if f == 0:
            for y in range(H_ - 20, H_):
                up.gput(f, 0, 0, HC["w"], lift=y)
            continue
        wid = [0, 1, 1, 1, 0, 0, 0][f]
        bot = [0, 0, 0, 0, 12, 24, 36][f]
        for y in range(int(bot), H_ - (f - 1) * 3):
            for x in range(-wid, wid + 1):
                c = HC["w"] if (x == 0 and f <= 2) else (HC["b"] if x == 0 else HC["l"])
                if f >= 3:
                    c = HC["l"] if x == 0 else HC["m"]
                if f >= 5:
                    c = HC["m"]
                if f >= 4 and y % 2:
                    continue
                up.gput(f, x, 0, c, lift=y)
    return up


# ================================================================ S1 结构加固：队长身边一圈骨肋从地上长出、往头顶合拢（前 / 后半圈分两张排序）
def s1_ribs(seal):
    R0 = 18
    apex = 38
    bk = Strip(8, 46, 52, 23, 46)
    fr = Strip(8, 46, 52, 23, 46)
    n = 8
    for f in range(8):
        grow = [0.3, 0.6, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0][f]
        cut = [0, 0, 0, 0, 0, 0.35, 0.7, 1.01][f]
        for j in range(n):
            a = 2 * math.pi * j / n + 0.2
            st = bk if math.sin(a) < 0 else fr
            bx, by = R0 * math.cos(a), R0 * math.sin(a) * SY
            N = 60
            for i in range(N):
                u = i / (N - 1)
                if u > grow or u < cut:
                    continue
                # 肋骨弧：外鼓的二次曲线，从地面点到头顶
                bulge = math.sin(math.pi * u) * 5
                x = bx * (1 - u) + (bx / R0) * bulge * (1 - u)
                y = by * (1 - u)
                lift = apex * (1 - (1 - u) ** 1.6)
                c = HC["b"] if (f == 2 or (u > grow - 0.15 and f < 2)) else HC["l"]
                if f >= 4:
                    c = HC["l"] if f < 6 else HC["m"]
                st.gput(f, x, y, c, lift=lift)
                st.gput(f, x + (1 if bx < 0 else -1), y, HC["d"], lift=lift, over=False)
        if seal and 3 <= f <= 5:   # 精二：合拢处一枚骨白结扣（十字星）
            L = [4, 3, 2][f - 3]
            for d in range(-L, L + 1):
                fr.gput(f, d, 0, HC["w"] if abs(d) < 2 else HC["b"], lift=apex)
                fr.gput(f, 0, 0, HC["w"] if abs(d) < 2 else HC["b"], lift=apex + d)
    return bk, fr


def s1_hex():
    gd = Strip(10, 50, 34, 25, 17)
    R = 21
    for f in range(10):
        r = R * min(1.0, 0.6 + f * 0.2)
        if f >= 7 and f % 2:
            continue
        pts = [(r * math.cos(math.pi / 3 * i + 0.52), r * math.sin(math.pi / 3 * i + 0.52) * SY) for i in range(7)]
        c = HC["b"] if f <= 1 else (HC["l"] if f <= 4 else HC["m"] if f <= 7 else HC["d"])
        for i in range(6):
            for (x, y) in seg_px(pts[i], pts[i + 1]):
                gd.gput(f, x, y, c)
            if i % 2 == 0 and f <= 6:
                for (x, y) in seg_px((pts[i][0] * 0.55, pts[i][1] * 0.55), pts[i]):
                    gd.gput(f, x, y, HC["m"] if f > 2 else HC["l"])
    return gd


# ================================================================ S2 战术协同（Mon3tr 身上）：三道荧光 ^ 指令符上升 + 脚下六角环；精二再加竖直热流
def s2_cmd():
    up = Strip(8, 22, 64, 11, 60)
    for f in range(8):
        for j in range(3):
            y = 22 + j * 6 + f * 2.4
            if f >= 5 + j * 0 and (f + j) % 2 and f >= 6:
                continue
            if f < j:
                continue
            for i in range(-5, 6):
                yy = y - (5 - abs(i)) * 0.9
                c = M["h"] if (abs(i) <= 1 and f <= 3) else (M["f"] if f <= 4 else M["m2"])
                up.gput(f, i, 0, c, lift=yy)
                up.gput(f, i, 0, M["d1"], lift=yy - 1, over=False)
    return up


def s2_streaks():
    up = Strip(8, 40, 64, 20, 60)
    rnd = random.Random(12)
    ss = [(rnd.uniform(-15, 15), rnd.uniform(-5, 5), rnd.uniform(0, 3)) for _ in range(6)]
    for f in range(8):
        for (x, y, ph) in ss:
            t = f - ph
            if t < 0:
                continue
            base = 6 + t * 5
            L = 6
            for i in range(L):
                c = M["h"] if i == L - 1 and t < 3 else (M["f"] if t < 4 else M["m2"])
                up.gput(f, x, y, c, lift=base + i)
    return up


def hex_ring(R, col_hi, col_lo, n=8):
    gd = Strip(n, int(2 * R + 8), int(2 * R * SY + 8), int(R + 4), int(R * SY + 4))
    for f in range(n):
        r = R * min(1.0, 0.7 + f * 0.15)
        pts = [(r * math.cos(math.pi / 3 * i), r * math.sin(math.pi / 3 * i) * SY) for i in range(7)]
        for i in range(6):
            for (x, y) in seg_px(pts[i], pts[i + 1]):
                if f >= n - 3 and (int(x) + int(y)) % 2:
                    continue
                gd.gput(f, x, y, col_hi if f <= 2 else col_lo)
    return gd


# ================================================================ S3 熔毁：起手竖直爆柱；持续期间 Mon3tr 身边竖直热流（循环，跟着走）
def s3_cast():
    up = Strip(8, 40, 80, 20, 76)
    for f in range(8):
        Hh = [30, 64, 66, 60, 50, 40, 30, 20][f]
        Wd = [3, 7, 6, 5, 3, 2, 1, 1][f]
        for y in range(int(Hh)):
            t = y / max(1, Hh)
            half = Wd * (1 - t ** 2)
            for x in range(-int(half) - 1, int(half) + 2):
                if f >= 4 and (x + y) % 3 == 0:
                    continue
                edge = abs(x) >= half
                c = M["f"] if edge else (M["d1"] if abs(x) > 1 else (M["h"] if f == 1 else M["f"] if f <= 2 else M["m1"]))
                up.gput(f, x, 0, c, lift=y)
        if f >= 2:   # 爆柱散成上升热流
            for j in range(6):
                x = (j - 2.5) * 5
                for i in range(5):
                    up.gput(f, x, 0, M["f"] if i < 2 else M["m2"], lift=10 + (f - 2) * 7 + i + j * 3)
    gd = Strip(8, 56, 40, 28, 20)
    for f in range(8):
        r = [12, 18, 22, 23, 23, 23, 23, 23][f]
        n = int(2 * math.pi * r * 1.3)
        for i in range(n):
            a = 2 * math.pi * i / n
            if f >= 5 and i % 2:
                continue
            gd.gput(f, r * math.cos(a), r * math.sin(a) * SY, M["f"] if f <= 2 else (M["m2"] if f <= 4 else M["d2"]))
            gd.gput(f, (r - 1) * math.cos(a), (r - 1) * math.sin(a) * SY, M["k"], 180)
    return up, gd


def s3_aura():
    up = Strip(12, 44, 60, 22, 54, loop=True)
    rnd = random.Random(3)
    ss = [(rnd.choice([-1, 1]) * rnd.uniform(9, 17), rnd.uniform(-4, 4), j * 3, rnd.randint(4, 7)) for j in range(4)]
    ash = [(rnd.uniform(-14, 14), rnd.uniform(-3, 3), j * 6) for j in range(2)]
    for f in range(12):
        for (x, y, ph, L) in ss:
            t = (f - ph) % 12
            base = 2 + t * 3.6
            for i in range(L):
                lift = base + i
                c = M["h"] if (i == L - 1 and t < 4) else (M["f"] if t < 5 else (M["m2"] if t < 8 else M["d2"]))
                if t >= 10:
                    continue
                up.gput(f, x + math.sin((lift + ph) * 0.3) * 1.2, y, c, lift=lift)
        for (x, y, ph) in ash:
            t = (f - ph) % 12
            up.gput(f, x + t * 0.3, y, M["k"], lift=6 + t * 2.6)
            up.gput(f, x + t * 0.3 + 1, y, M["d1"], lift=6 + t * 2.6)
    gd = Strip(12, 40, 26, 20, 13, loop=True)
    for f in range(12):
        r = 15
        n = int(2 * math.pi * r * 1.3)
        for i in range(n):
            a = 2 * math.pi * i / n
            on = (i + f * 2) % 9 < 2
            gd.gput(f, r * math.cos(a), r * math.sin(a) * SY, M["f"] if on else M["d2"], 255 if on else 150)
    return up, gd


# ================================================================ 熔毁 / 不毁重构：一枚墨绿结晶长出 → 爆亮 → 碎成黑绿碎晶往外飞落；贴地冲击环
def melt(Rw, big):
    R = Rw / 2.0
    ch, cw = (30, 14) if big else (20, 9)
    w = int(2 * R + 12)
    up = Strip(12, w, int(2 * R * SY + ch + 30), w // 2, int(R * SY + ch + 22))
    gd = Strip(12, w, int(2 * R * SY + 8), w // 2, int(R * SY + 4))
    rnd = random.Random(77 if big else 78)
    shards = [(rnd.uniform(0, 2 * math.pi), rnd.uniform(0.35, 0.9), rnd.uniform(8, 22), rnd.choice([0, 1, 1])) for _ in range(14 if big else 9)]
    for f in range(12):
        if f <= 2:
            k = [0.45, 1.0, 1.0][f]
            crystal(up, f, 0, 0, ch * k, cw, 0.0, hot=f == 1, crack=False, lift=4)
            if f == 2:   # 裂纹
                for y in range(4, int(ch) - 2, 3):
                    up.gput(f, (y % 5) - 2, 0, M["h"], lift=4 + y)
        elif f == 3:   # 爆亮：实心白芯团
            rb = cw * 0.9
            for yy in range(-int(rb) - 2, int(rb) + 3):
                for xx in range(-int(rb) - 2, int(rb) + 3):
                    d = math.hypot(xx, yy)
                    if d <= rb:
                        up.gput(f, xx, 0, M["w"] if d < rb * 0.55 else M["h"], lift=int(4 + ch * 0.45) + yy)
                    elif d <= rb + 2:
                        up.gput(f, xx, 0, M["f"], lift=int(4 + ch * 0.45) + yy)
        if f >= 3:   # 碎晶飞出（平面向外 + 高度抛物线）
            t = (f - 3) / 8.0
            for (a, dist, vz, dark) in shards:
                d = dist * R * min(1.0, t * 1.6)
                z = 4 + ch * 0.45 + vz * t * 3 - 70 * t * t
                gx, gy = d * math.cos(a), d * math.sin(a) * SY
                if z <= 0:
                    if f < 11:
                        up.gput(f, gx, gy, M["d1"] if dark else M["m1"])
                    continue
                c = M["k"] if dark else (M["f"] if f < 6 else M["m1"])
                for (dx, dz) in ((0, 0), (1, 0), (0, 1)):
                    up.gput(f, gx + dx, gy, c, lift=z + dz)
                if not dark and f < 6:
                    up.gput(f, gx, gy, M["h"], lift=z + 1)
    for f in range(12):
        if f < 3:   # 蓄势：脚下暗圈收紧
            r = R * [0.3, 0.24, 0.18][f]
            n = int(2 * math.pi * r * 1.2) + 4
            for i in range(n):
                a = 2 * math.pi * i / n
                gd.gput(f, r * math.cos(a), r * math.sin(a) * SY, M["m2"] if f == 2 else M["d2"])
            continue
        r = R * [0.35, 0.62, 0.84, 0.97, 1.0, 1.0, 1.0, 1.0, 1.0][f - 3]
        n = int(2 * math.pi * r * 1.3)
        for i in range(n):
            a = 2 * math.pi * i / n
            gx, gy = r * math.cos(a), r * math.sin(a) * SY
            if f <= 6:
                gd.gput(f, gx, gy, M["h"] if f == 3 else (M["f"] if f <= 5 else M["m2"]))
                for k in (1, 2):
                    gd.gput(f, gx * (r - k) / r, gy * (r - k) / r, M["d1"] if k == 1 else M["k"], 220)
            elif (i + f) % (f - 5) == 0:
                gd.gput(f, gx, gy, M["d2"] if f < 10 else M["d1"], 200 if f < 10 else 110)
        # 焦心：中心一摊暗斑
        rc = 9 if big else 6
        for yy in range(-rc, rc + 1):
            for xx in range(-rc, rc + 1):
                if xx * xx + (yy / SY) ** 2 <= rc * rc and (xx * 3 + yy * 7 + f) % 5 != 0:
                    gd.gput(f, xx, yy, M["k"], max(0, 200 - (f - 3) * 20), over=False)
    return up, gd


def echo_ring(Rw):
    R = Rw / 2.0
    gd = Strip(7, int(2 * R + 8), int(2 * R * SY + 8), int(R + 4), int(R * SY + 4))
    for f in range(7):
        r = R * [0.5, 0.75, 0.92, 1.0, 1.0, 1.0, 1.0][f]
        n = int(2 * math.pi * r * 1.3)
        for i in range(n):
            a = 2 * math.pi * i / n
            gx, gy = r * math.cos(a), r * math.sin(a) * SY
            if f <= 3:
                gd.gput(f, gx, gy, M["f"] if f <= 1 else M["m2"])
                gd.gput(f, gx * (r - 1) / r, gy * (r - 1) / r, M["k"], 200)
            elif (i + f) % (f - 2) == 0:
                gd.gput(f, gx, gy, M["d2"], 190 if f < 6 else 110)
    return gd


def echo_spray():
    up = Strip(7, 40, 40, 20, 34)
    rnd = random.Random(9)
    sh = [(rnd.uniform(0, 2 * math.pi), rnd.uniform(6, 16), rnd.uniform(10, 18), rnd.choice([0, 1])) for _ in range(7)]
    for f in range(7):
        t = f / 6.0
        for (a, d, vz, dark) in sh:
            gx, gy = d * t * 1.4 * math.cos(a), d * t * 1.4 * math.sin(a) * SY
            z = 6 + vz * t * 2.2 - 40 * t * t
            if z < 0:
                up.gput(f, gx, gy, M["d1"])
                continue
            c = M["k"] if dark else (M["f"] if f < 3 else M["m1"])
            up.gput(f, gx, gy, c, lift=z)
            up.gput(f, gx + 1, gy, c, lift=z)
    return up


def smolder(Rw):
    R = Rw / 2.0
    gd = Strip(8, int(2 * R + 8), int(2 * R * SY + 8), int(R + 4), int(R * SY + 4))
    rnd = random.Random(int(Rw))
    for f in range(8):
        n = int(2 * math.pi * R * 1.3)
        for i in range(n):
            a = 2 * math.pi * i / n
            if (i * 7 + f * 3) % 5 >= 2:
                continue
            al = 150 if f < 6 else 80
            on = rnd.random() < 0.12
            gd.gput(f, R * math.cos(a), R * math.sin(a) * SY, M["m2"] if on else M["d2"], 230 if on else al)
    return gd


# ================================================================ 连携「Mon3tr 掩护」：朝敌一侧一道半圈骨刺墙 + 往外推的贴地推波（5 个平面角，另一半翻转）
def link(dirdeg):
    R = 32
    a0 = math.radians(dirdeg)
    w, h = 96, 84
    up = Strip(9, w, h, w // 2, 52)
    gd = Strip(7, w, 60, w // 2, 30)
    rnd = random.Random(40 + dirdeg)
    sp = []
    for j in range(7):
        a = a0 + math.radians(-66 + 132 * j / 6) + rnd.uniform(-0.06, 0.06)
        sp.append((a, rnd.uniform(11, 17)))
    for f in range(9):
        k = [0.5, 1.0, 1.0, 1.0, 1.0, 0.85, 0.6, 0.3, 0.0][f]
        for (a, hh) in sorted(sp, key=lambda s: math.sin(s[0])):
            gx, gy = R * math.cos(a), R * math.sin(a) * SY
            if f == 8:
                up.gput(f, gx, gy, M["d1"])
                continue
            crystal(up, f, gx, gy, max(2, hh * k), 6, math.cos(a) * 0.25, hot=f == 1, crack=f >= 6)
    for f in range(7):
        r = 32 + f * 4
        for i in range(60):
            a = a0 + math.radians(-60 + 120 * i / 59)
            gx, gy = r * math.cos(a), r * math.sin(a) * SY
            if f >= 4 and i % 2:
                continue
            gd.gput(f, gx, gy, M["f"] if f <= 1 else (M["m2"] if f <= 3 else M["d2"]))
            gd.gput(f, gx - math.cos(a), gy - math.sin(a) * SY, M["k"], 170)
    return up, gd


IMPORT_TPL = open(os.path.join(ROOT, "game", "art", "fx", "pxp", "pxp_backwash_gd.png.import"), encoding="utf-8").read() if os.path.exists(os.path.join(ROOT, "game", "art", "fx", "pxp", "pxp_backwash_gd.png.import")) else None


def _uid():
    n = random.SystemRandom().getrandbits(62)
    cs = "abcdefghijklmnopqrstuvwxyz0123456789"
    out = ""
    while True:
        out = cs[n % 36] + out
        n //= 36
        if n == 0:
            return "uid://" + out


def write_imports():
    """新帧条的 .import（同其他 pxp 帧条：无损、无 mipmap）；已有的保留原 uid"""
    import hashlib, re
    if IMPORT_TPL is None:
        return
    for k in META:
        fn = "pxp_ka_%s.png" % k.replace("_d-", "_dm")
        ip = os.path.join(OUT_ART, fn + ".import")
        if os.path.exists(ip):
            continue
        res = "res://art/fx/pxp/" + fn
        t = IMPORT_TPL
        t = re.sub(r'uid="uid://[a-z0-9]+"', 'uid="%s"' % _uid(), t)
        t = re.sub(r"pxp_backwash_gd\.png-[0-9a-f]{32}", fn + "-" + hashlib.md5(res.encode()).hexdigest(), t)
        t = t.replace("pxp_backwash_gd.png", fn)
        with open(ip, "w", encoding="utf-8", newline="\n") as f:
            f.write(t)


def main():
    for Rw in CLAW_R:
        for sw in (0, 1):
            up, g0, g1 = rake(Rw, sw)
            up.save("claw_r%d_s%d_up" % (Rw, sw))
            g0.save("claw_r%d_s%d_gd" % (Rw, sw), emit_hot=False)
            g1.save("claw_r%d_s%d_gd1" % (Rw, sw), emit_hot=False)
            mu, mg = melt_claw(Rw, sw)
            mu.save("mclaw_r%d_s%d_up" % (Rw, sw))
            mg.save("mclaw_r%d_s%d_gd" % (Rw, sw), emit_hot=False)
    u, g = spike()
    u.save("spike_up")
    g.save("spike_gd", emit_hot=False)
    u, g = pounce()
    u.save("pounce_up")
    g.save("pounce_gd", emit_hot=False)
    bk, fr, g = guard_land(100)
    bk.save("guard_bk_up")
    fr.save("guard_fr_up")
    g.save("guard_gd", emit_hot=False)
    heal_ring().save("heal_gd")
    heal_cross().save("heal_cross_up")
    heal_column().save("heal_col_up")
    for seal in (False, True):
        bk, fr = s1_ribs(seal)
        if not seal:
            bk.save("s1rib_bk_up")
            fr.save("s1rib_fr_up")
        else:
            fr.save("s1rib_fr2_up")
    s1_hex().save("s1hex_gd", emit_hot=False)
    s2_cmd().save("s2cmd_up")
    s2_streaks().save("s2str_up")
    hex_ring(16, M["f"], M["m2"]).save("s2hex_gd", emit_hot=False)
    u, g = s3_cast()
    u.save("s3cast_up")
    g.save("s3cast_gd", emit_hot=False)
    u, g = s3_aura()
    u.save("s3aura_up")
    g.save("s3aura_gd", emit_hot=False)
    for Rw, big in ((130, True), (70, False)):
        u, g = melt(Rw, big)
        u.save("melt_r%d_up" % Rw)
        g.save("melt_r%d_gd" % Rw, emit_hot=False)
    for Rw in (70, 87, 105, 130, 162, 195):
        echo_ring(Rw).save("echo_r%d_gd" % Rw, emit_hot=False)
    echo_spray().save("echo_up")
    for Rw in (105, 130):
        smolder(Rw).save("smol_r%d_gd" % Rw, emit_hot=False)
    for d in (-90, -45, 0, 45, 90):
        u, g = link(d)
        u.save("link_up_d%d" % d)
        g.save("link_gd_d%d" % d, emit_hot=False)
    out = {"_doc": "docs/265 凯尔希转平面帧条（tools/pxplane_kal_art.py 程序生成）：键在游戏里加前缀 ka_，对应 art/fx/pxp/pxp_ka_<键>.png；n 帧数、fps、w / h（美术像素）、ox / oy 原点（地面点）、loop、emit 每帧热芯点 [x, y, 颜色]"}
    out.update(META)
    with open(OUT_META, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, separators=(",", ":"))
    write_imports()
    tot = sum(os.path.getsize(os.path.join(OUT_ART, "pxp_ka_%s.png" % k.replace("_d-", "_dm"))) for k in META)
    print(len(META), "张帧条，共 %.0f KB" % (tot / 1024))


if __name__ == "__main__":
    main()
