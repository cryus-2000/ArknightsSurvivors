#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""乌尔比安「转平面」帧条烘焙（docs/266，开关 fx/px_plane）：纯 Python 逐美术像素生成，进 game/art/fx/pxp/pxp_ul_*.png。

和前几批不同：不经 pixelfx 库（build/pixelfx），在这里直接按目标尺寸逐格画（同一套口径：1 帧条像素 = 1 美术像素、15 fps、
贴地层生成时已按 SY = 0.72 压扁、立起层竖直、原点 = 脚底 / 地面点、色层不含光晕、最亮的像素出 emit 点表）。
送审 GIF（tools/pxplane_gif_ulpianus.py）直接 import 本文件取同一批帧。

意象：重锚、锁链、深海（和推进之王的锤击裂地区分：这里不画裂网，砸下去是海水）。
  - 普攻「锚击」：锚落点炸起一圈不规则的**水冠**（一股股水往外斜着冲起、顶上碎成水珠落回）+ 地上**锚印**（深色湿印 + 一圈白沫往外推）；
    精一「收链」：锚印外圈几道**白沫拖痕往落点收**（玩法：外圈敌人被拉向落点）；精二：锚印里多一个**深渊暗涡**（三条暗涡臂 + 血纹暗段 + 浅色水光，转着收）。
    每一下同时「撼地」：以他为心一圈 1 美术像素的**细涟漪**往外推到撼地半径（断续、压扁），不画裂缝。
  - S1「必须促成的接触」：主角是锁链（运行时画）；钩回后重砸 = **中心一柱水**冲起、顶上分叉碎开 + 小水冠；精一起拖拽水沟（运行时）。
  - S2「必须维系的界限」：起手**锁链在脚下盘成一圈界限**（一节节亮起，绕一圈），中心锚插地一小柱水；精二链上多一道**跑圈的冷光**。
  - S3「必须开辟的通路」：冲锋（运行时：脚下破浪 + V 字尾迹）；落地 = 大号不规则水冠 + 地上**漩涡**（四条暗水臂往里旋）+ 外圈细涟漪推到判定半径。
  - 锁链回旋（成长）：地上一圈**被甩出去的水弧**（螺旋水沫，一拍一拍扫满一圈）。
  - 定点爆破（成长）：同一落点**回涌**（一圈水珠落回 + 细涟漪）。
  - 连携「掷锚」：锚钉下处**海水往锚回卷**（三道涟漪往中心收、越收越快）+ 小水花。
色：OP.ulpianus 审定 7 阶（组长 C 11-04）+ 压底；锁链用 OP.ulpianus_dust 冷灰 6 阶；精二暗涡用 OP.ulpianus_blood 暗段（只用最暗几阶，不出亮红）。

用法（仓库根目录）：python tools/pxplane_bake_ulpianus.py [--only 键前缀] [--no-import]
"""
import argparse, json, math, os, random

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_ART = os.path.join(ROOT, "game", "art", "fx", "pxp")
OUT_META = os.path.join(ROOT, "game", "data", "pxp_ulpianus.json")
PREFIX = "ul_"
FPS = 15
SY = 0.72
EMIT_MAX = 48


def hx(s):
    s = s.lstrip("#")
    return (int(s[0:2], 16), int(s[2:4], 16), int(s[4:6], 16), 255)


# OP.ulpianus（审定）+ 压底
C = [hx(c) for c in ["#070a1e", "#0c1235", "#1b2a66", "#2c4397", "#4463c8", "#7b93e6", "#c0cbf6", "#ffffff"]]
DUST = [hx(c) for c in ["#131528", "#212842", "#323c5e", "#4a5781", "#6b7ba6", "#9eabcf"]]
BLOOD = [hx(c) for c in ["#1c0710", "#33101c", "#4d1626", "#6b1e33"]]
FOAM = C[6]
WHITE = C[7]


def h1(x):
    return math.fmod(math.sin(x * 12.9898 + 78.233) * 43758.5453, 1.0) % 1.0


def vn(x):
    i = math.floor(x)
    f = x - i
    f = f * f * (3 - 2 * f)
    return h1(i) + (h1(i + 1.0) - h1(i)) * f


class Fr:
    """一帧画布（美术像素）；原点 (ox, oy) = 脚底 / 地面点"""

    def __init__(self, w, h, ox, oy):
        self.a = np.zeros((h, w, 4), np.uint8)
        self.w, self.h, self.ox, self.oy = w, h, ox, oy

    def put(self, x, y, c, over=True):
        xi = int(round(x + self.ox))
        yi = int(round(y + self.oy))
        if 0 <= xi < self.w and 0 <= yi < self.h:
            if not over and self.a[yi, xi, 3] > 0:
                return
            self.a[yi, xi] = c

    def get_a(self, x, y):
        xi = int(round(x + self.ox))
        yi = int(round(y + self.oy))
        if 0 <= xi < self.w and 0 <= yi < self.h:
            return int(self.a[yi, xi, 3])
        return 0


def ease_out(u):
    u = min(1.0, max(0.0, u))
    return 1 - (1 - u) * (1 - u)


# ================================================================ 立起层

def draw_jet(f, bx, by, out_x, hgt, w, lean, cols, top_white):
    """一股水：从地面点 (bx, by) 往上 hgt 美术像素，顶端往外斜 lean；cols = 下 → 上的色阶"""
    n = max(1, int(hgt))
    for i in range(n):
        u = i / max(1, n - 1)
        x = bx + out_x * lean * u * u * hgt
        y = by - i
        ww = max(1, int(round(w * (1.0 - 0.55 * u))))
        ci = min(len(cols) - 1, int(u * len(cols)))
        c = cols[ci]
        if top_white and u > 0.82:
            c = WHITE
        for k in range(ww):
            xx = x + k - (ww - 1) / 2.0
            # 受光：左侧亮一阶
            cc = c
            if k == 0 and ww > 1 and ci + 1 < len(cols):
                cc = cols[ci + 1]
            f.put(xx, y, cc)


def star(f, fi, R, seed, up_k=1.0):
    """命中爆闪（原作 attack_hit / skill_hit 的蓝白尖刺）：第 0 拍白芯 + 6–9 根尖刺（根部 2 格、尖 1 格，横向的压扁），第 1 拍缩一半、降一阶，第 2 拍起没有"""
    if fi > 1:
        return
    rnd = random.Random(seed + 77)
    k = 1.0 if fi == 0 else 0.55
    n = rnd.randint(6, 9)
    for i in range(n):
        a = (i + rnd.uniform(-0.3, 0.3)) * math.tau / n
        L = R * rnd.uniform(0.35, 0.75) * k
        dx, dy = math.cos(a), math.sin(a) * SY
        if dy < -0.3:
            dy *= 1.0 + 0.6 * up_k   # 往上的刺长一点（立起来）
        for j in range(int(L)):
            u = j / max(1.0, L)
            c = WHITE if (u < 0.35 and fi == 0) else (C[6] if u < 0.7 else C[5])
            if fi == 1:
                c = C[6] if u < 0.4 else C[5]
            x, y = dx * j, dy * j - 4
            f.put(x, y, c)
            if u < 0.4:
                f.put(x + (1 if abs(dy) > abs(dx) else 0), y + (0 if abs(dy) > abs(dx) else 1), c)
    rr = 3 if fi == 0 else 2
    for dx in range(-rr - 1, rr + 2):
        for dy in range(-rr, rr + 1):
            if dx * dx * 0.7 + dy * dy < rr * rr + 1:
                f.put(dx, dy - 4, WHITE if fi == 0 else C[6])


def bubbles(f, fi, R, seed, n, t0=2):
    """水泡（原作的标志）：3×3 小环 + 1 格高光，从水冠里慢慢往上飘、左右晃，到寿破成四个散点"""
    if fi < t0:
        return
    for i in range(n):
        dr = random.Random(seed * 29 + i)
        a = dr.random() * math.tau
        r = R * dr.uniform(0.1, 0.6)
        life = dr.randint(5, 8)
        age = fi - t0 - dr.randint(0, 2)
        if age < 0 or age >= life:
            continue
        x = math.cos(a) * r + math.sin(age * 0.9 + i) * 1.5
        y = math.sin(a) * r * SY - 6 - age * dr.uniform(2.5, 4.0)
        if age == life - 1:
            for q in ((-2, 0), (2, 0), (0, -2), (0, 2)):
                f.put(x + q[0], y + q[1], C[5])
            continue
        if dr.random() < 0.5:
            for q in ((-1, -1), (0, -1), (1, -1), (-1, 0), (1, 0), (-1, 1), (0, 1), (1, 1)):
                f.put(x + q[0], y + q[1], C[5] if q[1] >= 0 else C[6])
            f.put(x - 1, y - 1, WHITE)
        else:
            f.put(x, y, C[6])
            f.put(x + 1, y, C[5])
            f.put(x, y - 1, WHITE)


def crown(f, fi, R, H, nj, seed, tier, flash=True):
    """锚落点水冠：第 0–1 拍尖刺爆闪；1–3 拍一圈参差的水裙冲起（顶边白沫、近半圈亮、断口多）、上面几股水舌往外斜；
    4 拍起水裙塌下、水舌碎成水珠落回；之后水泡往上飘"""
    rnd = random.Random(seed)
    if flash:
        star(f, fi, R, seed)
    t = fi / FPS
    rise = 0.12 + 0.02 * tier
    rr0 = R * 0.5
    if 1 <= fi <= 3:   # 水裙：矮、断口多（主角是水舌），第 3 拍塌一半、第 4 拍没了，不留一圈「碗边」
        u = ease_out(fi / 2.0) if fi <= 2 else 0.45
        n = max(30, int(rr0 * 7))
        pts = []
        for i in range(n):
            a = math.tau * i / n
            if vn(a * 3.0 + seed) < 0.36:   # 断口
                continue
            hh = H * 0.3 * u * (0.45 + 0.9 * vn(a * 4.0 + seed * 1.7))
            rr = rr0 * (1.0 + 0.15 * (fi / 6.0))
            pts.append((math.sin(a), a, rr, hh))
        pts.sort()
        for (_s, a, rr, hh) in pts:
            bx, by = math.cos(a) * rr, math.sin(a) * rr * SY
            far = math.sin(a) < 0
            lean = math.cos(a) * 0.35
            for z in range(int(hh)):
                v = z / max(1.0, hh)
                ci = (2 + int(v * 3)) if far else (3 + int(v * 3))
                if z >= int(hh) - 1:
                    ci = 6 if fi <= 3 else 5
                if math.cos(a) < -0.3 and not far:
                    ci = min(7, ci + 1)
                f.put(bx + lean * z, by - z, C[min(7, ci)])
    jets = []
    a0 = rnd.random() * math.tau
    for j in range(nj):
        a = a0 + math.tau * (j + rnd.uniform(-0.3, 0.3)) / nj
        if rnd.random() < 0.3:
            continue
        rr = rr0 * rnd.uniform(0.85, 1.15)
        jets.append((a, rr, rnd.uniform(0.55, 1.0), rnd.choice([2, 3, 3]), rnd.uniform(0.35, 0.7)))
    jets.sort(key=lambda q: math.sin(q[0]))
    for (a, rr, hk, w, lean) in jets:
        if fi == 0:
            continue
        bx, by = math.cos(a) * rr, math.sin(a) * rr * SY
        hmax = H * hk
        far = math.sin(a) < 0
        cols = [C[3], C[4], C[5], C[6]] if far else [C[4], C[5], C[6], C[6]]
        T = rise + 1.0 / FPS
        if t <= T:
            draw_jet(f, bx, by, math.cos(a), hmax * ease_out(t / T), w, lean, cols, fi <= 2)
        else:
            tt = t - T
            hh = hmax * max(0.0, 1.0 - tt / 0.2) ** 1.5
            if hh >= 2:
                draw_jet(f, bx, by, math.cos(a), hh, max(1, w - 1), lean, cols[:-1], False)
            for d in range(2 + int(hk * 3)):
                dr = random.Random(seed * 131 + int(a * 1000) + d)
                vx = math.cos(a) * dr.uniform(10, 26) + dr.uniform(-5, 5)   # 水珠落回不出判定圈（画面 ≤ 判定 × 1.1）
                vy0 = dr.uniform(5, 30)
                x = bx + math.cos(a) * lean * hmax + vx * tt
                z = hmax * dr.uniform(0.75, 1.0) + vy0 * tt - 0.5 * 300 * tt * tt
                y = by + math.sin(a) * SY * abs(vx) * 0.4 * tt
                if z > 0:
                    f.put(x, y - z, FOAM if d % 3 == 0 else C[5])
                    f.put(x, y - z + 1, C[4])
                elif tt < 0.45:
                    f.put(x, y, C[3])
                    f.put(x + 1, y, C[2])
    bubbles(f, fi, R, seed, int(3 + tier * 2 + R // 20))


def column(f, fi, Wd, H, seed):
    """S1 重砸：一团水从地面炸起（越往上越散开的不规则水团，不是柱子），顶上分成几根水舌往外翻、碎成水珠；0.5 秒塌完"""
    rnd = random.Random(seed)
    t = fi / FPS
    star(f, fi, Wd * 2.2, seed, 1.6)
    rise = 0.14
    if fi == 0:
        return
    hh = H * ease_out(t / rise) if t <= rise else H * max(0.0, 1.0 - (t - rise) / 0.28) ** 1.3
    # 一束五六股水从落点炸起（底窄、往上散开、高低不齐），不是一根柱子
    for k in range(6):
        dr = random.Random(seed * 11 + k)
        a = (k - 2.5) * 0.32 + dr.uniform(-0.1, 0.1)
        hk = dr.uniform(0.55, 1.0) if k not in (2, 3) else 1.0
        bx = (k - 2.5) * 1.2
        cols = [C[4], C[5], C[6], C[6]] if k % 2 == 0 else [C[3], C[4], C[5], C[6]]
        draw_jet(f, bx, 0, math.sin(a) * 2.2, hh * hk, 3 if k in (2, 3) else 2, abs(math.sin(a)) * 0.9 + 0.05, cols, fi <= 2)
    if t > 0.05:
        tt = t - 0.05
        for k in range(5):
            ang = -math.pi / 2 + (k - 2) * 0.5 + rnd.uniform(-0.15, 0.15)
            L = min(1.0, tt / 0.16) * rnd.uniform(8, 15)
            for i in range(int(L)):
                u = i / max(1.0, L)
                x = math.cos(ang) * i * 1.3
                y = -hh + math.sin(ang) * i + 0.07 * i * i
                f.put(x, y, FOAM if u > 0.4 else C[5])
                if u < 0.5:
                    f.put(x + 1, y, C[5])
            if tt > 0.1:
                for d in range(3):
                    dr = random.Random(seed * 7 + k * 13 + d)
                    t2 = tt - 0.1
                    x = math.cos(ang) * (L * 1.3 + dr.uniform(10, 30) * t2 * 4)
                    z = hh - math.sin(ang) * L + dr.uniform(0, 20) * t2 - 0.5 * 320 * t2 * t2
                    if z > 0:
                        f.put(x, -z, FOAM if d == 0 else C[5])
    bubbles(f, fi, Wd * 2, seed, 5, t0=3)


def spray_low(f, fi, R, seed, n=10):
    """低矮的一圈水沫（贴地弹起的水珠）"""
    t = fi / FPS
    for d in range(n):
        dr = random.Random(seed * 17 + d)
        a = dr.random() * math.tau
        r = R * dr.uniform(0.6, 1.0)
        z = dr.uniform(30, 60) * t - 0.5 * 320 * t * t + dr.uniform(0, 3)
        if z > 0:
            f.put(math.cos(a) * r, math.sin(a) * r * SY - z, FOAM if d % 3 == 0 else C[5])


# ================================================================ 贴地层

def ellipse_pts(R, n=None):
    n = n or max(24, int(R * 6))
    for i in range(n):
        a = math.tau * i / n
        yield a, math.cos(a) * R, math.sin(a) * R * SY


def ripple(f, fi, R, seed, n_beats=7, r0=0.3, gap=0.32, inner=True, col_hi=None):
    """细涟漪：1 美术像素白沫线（断续）+ 内侧一格暗水；从 r0·R 推到 R（ease-out），后两拍降阶淡掉"""
    u = ease_out((fi + 1) / (n_beats - 2))
    if fi >= n_beats:
        return
    rr = R * (r0 + (1 - r0) * u)
    fade = max(0, fi - (n_beats - 3))
    hi = col_hi or FOAM
    cl = [hi, C[5], C[4], C[3]][min(3, fade)]
    dk = [C[2], C[1], C[1], C[1]][min(3, fade)]
    for a, x, y in ellipse_pts(rr):
        if vn(a * 5.0 + seed * 3.1 + fi * 0.7) < gap:
            continue
        f.put(x, y, cl)
        if inner:
            k = (rr - 1.4) / rr
            f.put(x * k, y * k + 0.0, dk, over=False)


def blob(f, R, seed, cols, k=1.0):
    """不规则湿印（压扁）：cols[0] 外圈，cols[-1] 中心"""
    for yy in range(-int(R * SY) - 2, int(R * SY) + 3):
        for xx in range(-int(R) - 2, int(R) + 3):
            a = math.atan2(yy / SY, xx)
            d = math.hypot(xx, yy / SY)
            rr = R * k * (0.75 + 0.4 * vn(a * 2.2 + seed))
            if d < rr:
                e = d / rr
                ci = min(len(cols) - 1, int((1 - e) * len(cols)))
                f.put(xx, yy, cols[ci])


def splat(f, fi, R, seed, tier, pull_R=0.0):
    """锚印：深色湿印 + 一圈白沫往外推；精一外圈白沫拖痕往里收；精二暗涡"""
    life = 9
    if fi >= life:
        return
    if fi <= 2:   # 湿印：前三拍实心（外圈一阶亮边），之后只剩断续的暗边
        blob(f, R * 0.36, seed, [C[3], C[2], C[1]] if fi == 0 else [C[2], C[1]], 1.0)
    elif fi <= 5:
        for a, x, y in ellipse_pts(R * 0.36 * (1 + 0.05 * fi)):
            if vn(a * 4.0 + seed + fi) < 0.3 + 0.1 * (fi - 3):
                continue
            k = 0.75 + 0.4 * vn(a * 2.2 + seed)
            f.put(x * k, y * k, C[2] if fi < 5 else C[1])
    # 白沫碎点往外推
    rnd = random.Random(seed + 5)
    u = ease_out((fi + 1) / 6.0)
    for i in range(int(R * 1.1)):
        a = rnd.random() * math.tau
        r = R * (0.45 + 0.45 * u) * rnd.uniform(0.8, 1.05)
        if fi > 6 and rnd.random() < 0.6:
            continue
        c = FOAM if rnd.random() < 0.35 and fi < 4 else (C[5] if fi < 6 else C[4])
        f.put(math.cos(a) * r, math.sin(a) * r * SY, c)
    if tier >= 2 and fi < 9:
        # 深渊暗涡：三条暗涡臂（深色水 + 血纹暗段芯）转着往里收，臂外沿一线浅色水光
        rot = fi * 0.5
        for arm in range(3):
            for s in range(26):
                v = s / 25.0
                a = arm * math.tau / 3 + rot + v * 2.8
                r = R * 0.55 * (1.0 - v * 0.85)
                x, y = math.cos(a) * r, math.sin(a) * r * SY
                f.put(x * 1.06, y * 1.06, C[0] if fi < 7 else C[1])
                f.put(x, y, BLOOD[3] if fi < 6 else BLOOD[2])
                f.put(x * 0.93, y * 0.93, BLOOD[2] if fi < 6 else BLOOD[1])
                if s % 3 == 0 and fi < 7:
                    f.put(x * 1.13, y * 1.13, C[6] if fi < 3 else C[5])
    if pull_R > 0 and fi < 7:
        # 收链：外圈几道白沫拖痕往落点收（头亮尾暗）
        rr = random.Random(seed + 9)
        n = 6
        for i in range(n):
            a = (i + rr.uniform(-0.25, 0.25)) * math.tau / n
            rs = pull_R * rr.uniform(0.92, 1.0)
            re = R * 0.8
            head = rs - (rs - re) * ease_out((fi + 1) / 5.0)
            ca, sa = math.cos(a), math.sin(a)
            for s in range(12):
                r = head + s * 1.4
                if r > rs:
                    break
                c = WHITE if s == 0 and fi < 3 else (FOAM if s < 2 else (C[5] if s < 6 else C[3]))
                if fi >= 5:
                    c = C[5] if s == 0 else C[3]
                x, y = ca * r, sa * r * SY
                f.put(x, y, c)
                f.put(x - sa, y + ca * SY, c if s < 6 else C[2])   # 2 格宽


def whirl_gd(f, fi, R, seed):
    """锁链回旋：被甩出去的水弧——一拍扫 72°、5 拍满一圈；扫过的部分往外漂、变稀"""
    rnd = random.Random(seed)
    a0 = rnd.random() * math.tau
    sweep = min(1.0, (fi + 1) / 5.0) * math.tau
    for i in range(int(R * 7)):
        s = i / (R * 7) * sweep
        age = (sweep - s) / math.tau * 5.0 / FPS   # 这一点被扫到之后过了多久（秒）
        if age > 0.42:
            continue
        a = a0 + s
        dr = random.Random(seed * 3 + i)
        r = R * (0.8 + 0.6 * age) + dr.uniform(-2.5, 2.5)
        if dr.random() < age * 1.8:
            continue
        c = FOAM if age < 0.08 else (C[5] if age < 0.2 else C[4])
        f.put(math.cos(a) * r, math.sin(a) * r * SY, c)
        if age < 0.12 and dr.random() < 0.5:
            f.put(math.cos(a) * (r - 1.5), math.sin(a) * (r - 1.5) * SY, C[3], over=False)


def chain_ring(f, fi, R, seed, tier):
    """S2 起手：锁链在脚下盘成一圈（从正前方开始一节节亮起，5 拍绕满），之后冷却、10 拍后淡掉；精二多一道跑圈的冷光"""
    if fi >= 13:
        return
    n = int(math.tau * R / 4.0)
    shown = n * min(1.0, (fi + 1) / 5.0)
    for i in range(n):
        if i > shown:
            break
        a = math.pi / 2 + math.tau * i / n
        x, y = round(math.cos(a) * R), round(math.sin(a) * R * SY)
        age = (shown - i) / max(1.0, n) * 5.0 + max(0, fi - 4)
        hot = age < 1.0
        if fi >= 10:
            body, hi = DUST[1], DUST[2]
        elif hot:
            body, hi = DUST[5], WHITE
        else:
            body, hi = DUST[3], DUST[5]
        tx, ty = -math.sin(a), math.cos(a) * SY   # 切向
        if i % 2 == 0:   # 正面链节：4×3 的扁环（中间空）
            for q in ((-2, 0), (2, 0), (-1, -1), (0, -1), (1, -1), (-1, 1), (0, 1), (1, 1)):
                px = x + q[0] * (1 if abs(tx) > 0.5 else 0) + q[1] * (0 if abs(tx) > 0.5 else 1) * 0
                f.put(x + q[0], y + q[1], hi if q[1] < 0 else body)
            f.put(x, y + 2, DUST[0], over=False)
        else:            # 侧面链节：一横 3 格
            for q in (-1, 0, 1):
                f.put(x + q, y, body)
            f.put(x, y - 1, hi if hot else DUST[2])
            f.put(x, y + 1, DUST[0], over=False)
    if tier >= 2 and 3 <= fi < 11:
        k = (fi - 3) / 7.0
        for j in range(5):
            a = math.pi / 2 + math.tau * (k - j * 0.012)
            f.put(math.cos(a) * R, math.sin(a) * R * SY - 1, WHITE if j == 0 else C[6])
    # 内侧一圈淡水痕（2 格暗边，界限的内沿）
    if fi < 10:
        for a, x, y in ellipse_pts(R - 3):
            if vn(a * 4 + seed) < 0.45:
                continue
            f.put(x, y, C[2] if fi < 7 else C[1], over=False)


def vortex_gd(f, fi, R, seed):
    """S3 落地漩涡：四条暗水臂往里旋（白沫顶边），外圈细涟漪推到 R"""
    life = 12
    if fi >= life:
        return
    rot = fi * 0.45
    fade = max(0, fi - 7)
    for arm in range(4):
        for s in range(int(R * 1.4)):
            v = s / (R * 1.4)
            a = arm * math.tau / 4 + rot + v * 3.4
            r = R * 0.85 * (1.0 - v * 0.9)
            x, y = math.cos(a) * r, math.sin(a) * r * SY
            if fade >= 4:
                continue
            f.put(x, y, [C[1], C[1], C[0], C[0]][fade])
            f.put(x * 0.96, y * 0.96, [C[2], C[1], C[1], C[0]][fade], over=False)
            if s % 4 == 0 and fade < 2:
                f.put(x * 1.04, y * 1.04, FOAM if fi < 3 else C[5])
    ripple(f, fi, R, seed, n_beats=9, r0=0.35, gap=0.3)


def inward(f, fi, R, seed):
    """连携掷锚：三道涟漪从外往锚收（越收越快），每道白沫断续；第 9 拍收完"""
    for k in range(3):
        u = (fi - k * 1.5) / 7.0
        if u < 0 or u > 1:
            continue
        rr = R * (1.0 - u * u) + 3
        cl = FOAM if u > 0.6 else C[5]
        for a, x, y in ellipse_pts(rr):
            if vn(a * 6 + seed + k * 2.3) < 0.38:
                continue
            f.put(x, y, cl)
            kk = (rr + 1.5) / rr
            f.put(x * kk, y * kk, C[2], over=False)


# ================================================================ 件表

def variants():
    """(键, 种类, 参数, 帧数, 层)：美术像素 = 世界 / 2"""
    v = []
    # 普攻锚击：判定半径 reach 89 / S2 后 105 × 1.3 = 136；late_shape 近战扩域每档 +15%（→ 约 110 / 170）。按 44 / 56 / 68 / 84 四档预生成
    for R in (44, 56, 68, 84):
        for el in (0, 1, 2):
            v.append(("atk_r%d_e%d_up" % (R, el), "crown", {"R": R, "H": int(R * (0.62 + 0.1 * el)), "nj": 10 + 2 * el + R // 14, "tier": el, "seed": 11 + R + el}, 9, "up"))
            v.append(("atk_r%d_e%d_gd" % (R, el), "splat", {"R": R, "tier": el, "pull": R * 1.43 if el >= 1 else 0.0, "seed": 21 + R}, 9, "gd"))
    # 撼地（每一下普攻以自身为心 quake_r 150 / 精二 180；late_shape 放大）：细涟漪
    for R in (75, 90, 105, 125):
        v.append(("quake_r%d_gd" % R, "ripple", {"R": R, "beats": 7, "r0": 0.35, "gap": 0.42, "seed": 31 + R}, 7, "gd"))
    # 定点爆破（blast2_r 100）回涌：一圈落回的水珠 + 细涟漪；连携 / 钩索到位 / 余震的小涟漪
    for R in (50, 60, 72):
        v.append(("echo_r%d_up" % R, "spray", {"R": R, "n": 12, "seed": 41 + R}, 7, "up"))
        v.append(("echo_r%d_gd" % R, "ripple", {"R": R, "beats": 6, "r0": 0.55, "gap": 0.3, "seed": 43 + R}, 6, "gd"))
    for R in (16, 25):
        v.append(("small_r%d_gd" % R, "ripple", {"R": R, "beats": 5, "r0": 0.3, "gap": 0.2, "seed": 47 + R}, 5, "gd"))
    # 锚咬地 / 钩索落地（小水花）
    for R, H in ((14, 16), (22, 24)):
        v.append(("bite_r%d_up" % R, "crown", {"R": R, "H": H, "nj": 7 + R // 4, "tier": 0, "seed": 51 + R}, 8, "up"))
        v.append(("bite_r%d_gd" % R, "splat", {"R": R, "tier": 0, "pull": 0.0, "seed": 53 + R}, 8, "gd"))
    # 锁链回旋（whirl_r 130）
    for R in (65, 78):
        v.append(("whirl_r%d_gd" % R, "whirl", {"R": R, "seed": 61 + R}, 8, "gd"))
    # S1 重砸（s1_r 90 → 45；绞杀 reach_skill 105 × 1.3 = 136 → 68）
    for R in (45, 56, 68):
        for el in (0, 1, 2):
            v.append(("s1_r%d_e%d_up" % (R, el), "s1", {"R": R, "H": 30 + 6 * el + R // 6, "tier": el, "seed": 71 + R + el}, 10, "up"))
            v.append(("s1_r%d_e%d_gd" % (R, el), "splat", {"R": R, "tier": el, "pull": 0.0, "seed": 73 + R}, 9, "gd"))
    # S2 起手（锁链界限：半径 = 生效后的锚击半径 136 → 68）
    for el in (1, 2):
        v.append(("s2_e%d_gd" % el, "ring", {"R": 68, "tier": el, "seed": 81}, 13, "gd"))
        v.append(("s2_e%d_up" % el, "s2up", {"tier": el, "seed": 83}, 9, "up"))
    # S3 落地（s3_r 140 → 70）
    v.append(("s3_up", "crown", {"R": 70, "H": 50, "nj": 24, "tier": 2, "seed": 91}, 10, "up"))
    v.append(("s3_gd", "vortex", {"R": 70, "seed": 93}, 12, "gd"))
    # 连携掷锚钉下（拖 180 内的小怪 → 90）
    v.append(("pin_gd", "inward", {"R": 90, "seed": 97}, 10, "gd"))
    return v


def size_of(kind, p):
    R = p.get("R", 10)
    if kind in ("crown", "s1"):
        H = p.get("H", 20) + 30
        return int(R * 2 + 70), int(H + R * SY + 16), int(R + 35), int(H + 2)
    if kind == "spray":
        return int(R * 2 + 12), int(R * SY * 2 + 40), int(R + 6), int(R * SY + 34)
    if kind == "s2up":
        return 50, 60, 25, 52
    pr = p.get("pull", 0.0) or 0.0
    RR = max(R, pr) * (1.5 if kind == "whirl" else 1.0) + 6
    return int(RR * 2 + 4), int(RR * SY * 2 + 6), int(RR + 2), int(RR * SY + 3)


def render(kind, p, n):
    w, h, ox, oy = size_of(kind, p)
    frames = []
    for fi in range(n):
        f = Fr(w, h, ox, oy)
        if kind == "crown":
            crown(f, fi, p["R"], p["H"], p["nj"], p["seed"], p["tier"])
            if p["tier"] >= 1 and p["R"] >= 40:
                spray_low(f, fi, p["R"] * 0.9, p["seed"] + 3, 6 + 3 * p["tier"])
        elif kind == "s1":
            crown(f, fi, p["R"] * 0.7, p["H"] * 0.45, 9 + p["tier"] * 2, p["seed"], p["tier"], flash=False)
            column(f, fi, 9 + p["tier"] * 2, p["H"], p["seed"] + 1)
        elif kind == "splat":
            splat(f, fi, p["R"], p["seed"], p["tier"], p.get("pull", 0.0))
        elif kind == "ripple":
            ripple(f, fi, p["R"], p["seed"], p["beats"], p["r0"], p["gap"])
        elif kind == "spray":
            spray_low(f, fi, p["R"], p["seed"], p["n"])
        elif kind == "whirl":
            whirl_gd(f, fi, p["R"], p["seed"])
        elif kind == "ring":
            chain_ring(f, fi, p["R"], p["seed"], p["tier"])
        elif kind == "s2up":
            column(f, fi, 5 + p["tier"], 22 + 4 * p["tier"], p["seed"])
        elif kind == "vortex":
            vortex_gd(f, fi, p["R"], p["seed"])
        elif kind == "inward":
            inward(f, fi, p["R"], p["seed"])
        frames.append(f.a)
    return frames, (w, h, ox, oy)


def emit_pts(a, seed):
    ys, xs = np.nonzero(a[..., 3] > 0)
    pts = []
    for y, x in zip(ys, xs):
        r, g, b = (int(v) for v in a[y, x, :3])
        luma = (0.299 * r + 0.587 * g + 0.114 * b) / 255.0
        if luma > 0.86:
            pts.append([int(x), int(y), "#%02x%02x%02x" % (r, g, b)])
    if len(pts) > EMIT_MAX:
        rnd = random.Random(seed)
        rnd.shuffle(pts)
        pts = sorted(pts[:EMIT_MAX])
    return pts


def bake_one(key, kind, p, n):
    frames, (w, h, ox, oy) = render(kind, p, n)
    strip = np.concatenate(frames, axis=1)
    meta = {"n": n, "fps": FPS, "w": w, "h": h, "ox": ox, "oy": oy, "loop": False,
            "emit": [emit_pts(fr, hash(key) & 0xffff) for fr in frames]}
    return strip, meta


def lib(only=None):
    """GIF 脚本用：{键（带 ul_ 前缀）: (帧列表 RGBA ndarray, meta)}，不写盘"""
    out = {}
    for key, kind, p, n, _ly in variants():
        if only and not key.startswith(only):
            continue
        frames, (w, h, ox, oy) = render(kind, p, n)
        out[PREFIX + key] = (frames, {"n": n, "fps": FPS, "w": w, "h": h, "ox": ox, "oy": oy})
    return out


IMPORT_TMPL = """[remap]

importer="texture"
type="CompressedTexture2D"
path="res://.godot/imported/{f}-{hsh}.ctex"
metadata={{
"vram_texture": false
}}

[deps]

source_file="res://art/fx/pxp/{f}"
dest_files=["res://.godot/imported/{f}-{hsh}.ctex"]

[params]

compress/mode=0
compress/high_quality=false
compress/lossy_quality=0.7
compress/uastc_level=0
compress/rdo_quality_loss=0.0
compress/hdr_compression=1
compress/normal_map=0
compress/channel_pack=0
mipmaps/generate=false
mipmaps/limit=-1
roughness/mode=0
roughness/src_normal=""
process/channel_remap/red=0
process/channel_remap/green=1
process/channel_remap/blue=2
process/channel_remap/alpha=3
process/fix_alpha_border=true
process/premult_alpha=false
process/normal_map_invert_y=false
process/hdr_as_srgb=false
process/hdr_clamp_exposure=false
process/size_limit=0
detect_3d/compress_to=1
"""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    ap.add_argument("--no-import", action="store_true")
    a = ap.parse_args()
    import hashlib
    os.makedirs(OUT_ART, exist_ok=True)
    meta = {"_doc": "docs/266 乌尔比安转平面帧条（tools/pxplane_bake_ulpianus.py 生成，键不含 ul_ 前缀；fx_pxplane METAS 加前缀）"}
    if a.only and os.path.exists(OUT_META):
        meta.update(json.load(open(OUT_META, encoding="utf-8")))
    total = 0
    for key, kind, p, n, _ly in variants():
        if a.only and not key.startswith(a.only):
            continue
        strip, m = bake_one(key, kind, p, n)
        fn = "pxp_%s%s.png" % (PREFIX, key)
        path = os.path.join(OUT_ART, fn)
        Image.fromarray(strip, "RGBA").save(path, optimize=True)
        total += os.path.getsize(path)
        meta[key] = m
        if not a.no_import:
            imp = path + ".import"
            if not os.path.exists(imp):
                hsh = hashlib.md5(("res://art/fx/pxp/" + fn).encode()).hexdigest()
                open(imp, "w", encoding="utf-8", newline="\n").write(IMPORT_TMPL.format(f=fn, hsh=hsh))
    with open(OUT_META, "w", encoding="utf-8", newline="\n") as fo:
        json.dump(meta, fo, ensure_ascii=False, separators=(",", ":"))
    print("帧条 %d 张，%.1f KB" % (len([k for k in meta if k != "_doc"]), total / 1024.0))


if __name__ == "__main__":
    main()
