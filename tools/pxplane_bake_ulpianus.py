#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""乌尔比安「转平面」帧条烘焙（docs/266，开关 fx/px_plane）：纯 Python 逐美术像素生成，进 game/art/fx/pxp/pxp_ul_*.png。

和前几批不同：不经 pixelfx 库（build/pixelfx），在这里直接按目标尺寸逐格画（同一套口径：1 帧条像素 = 1 美术像素、15 fps、
贴地层生成时已按 SY = 0.72 压扁、立起层竖直、原点 = 脚底 / 地面点、色层不含光晕、最亮的像素出 emit 点表）。
送审 GIF（tools/pxplane_gif_ulpianus.py）直接 import 本文件取同一批帧。

意象：重锚、锁链、深海（和推进之王的锤击裂地区分：这里不画裂网，砸下去是海水）。
  - 普攻「锚击」：锚落点爆闪 + 一把短促、不规则的**水团**飞起落回（11-05 用户「太像触手」后不画细长水舌）+ 地上**锚印**（深色湿印 + 一圈白沫往外推）；
    精一「收链」：锚印外圈几道**白沫拖痕往落点收**（玩法：外圈敌人被拉向落点）；精二：锚印里多一个**深渊暗涡**（三条暗涡臂 + 血纹暗段 + 浅色水光，转着收）。
    每一下同时「撼地」：以他为心一圈 1 美术像素的**细涟漪**往外推到撼地半径（断续、压扁），不画裂缝。
  - S1「必须促成的接触」：主角是锁链（运行时画）；钩回后重砸 = **中心一柱水**冲起、顶上分叉碎开 + 小水冠；精一起拖拽水沟（运行时）。
  - S2「必须维系的界限」：锁链环（运行时画，fx_pxplane_ul._ring）——起手从脚下扩到锚击半径，之后脚下一圈实心链环慢慢转（常驻）。
  - S3「必须开辟的通路」：掷锚 → 咬地 → 锁链绷直一闪 → 本体沿锁链冲过去留下深海拖痕（运行时）→ 落地重击（爆闪 + 一大把水团 + 细涟漪推到判定半径）+ 冷却水花（一处处小水花依次蹦起，白 → 蓝 → 暗）。
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

def star(f, fi, R, seed, up_k=1.0, cap=14.0):
    """命中爆闪（原作 attack_hit / skill_hit 的蓝白尖刺）：第 0 拍白芯 + 6–8 根短直刺（根部 2 格、尖 1 格，横向的压扁），第 1 拍缩一半、降一阶，第 2 拍起没有"""
    if fi > 1:
        return
    rnd = random.Random(seed + 77)
    k = 1.0 if fi == 0 else 0.5
    n = rnd.randint(6, 8)
    for i in range(n):
        a = (i + rnd.uniform(-0.3, 0.3)) * math.tau / n
        L = min(cap, R * rnd.uniform(0.22, 0.42)) * k
        dx, dy = math.cos(a), math.sin(a) * SY
        if dy < -0.3:
            dy *= 1.0 + 0.4 * up_k
        for j in range(int(L)):
            u = j / max(1.0, L)
            c = WHITE if (u < 0.4 and fi == 0) else (C[6] if u < 0.75 else C[5])
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
    """水泡（原作的标志）：3×3 小环 + 1 格高光，从落点慢慢往上飘、左右晃，到寿破成四个散点"""
    if fi < t0:
        return
    for i in range(n):
        dr = random.Random(seed * 29 + i)
        a = dr.random() * math.tau
        r = R * dr.uniform(0.1, 0.5)
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


GRAV = 1000.0   # 水团重力（美术像素 / 秒²）：重一点，飞起落回不超过约 0.4 秒（短促）


def clumps(f, fi, R, H, n, seed, cone=1.0, t_delay=0.0, size=(2.0, 3.6)):
    """短促、不规则的水团：每团是一小坨 2–4 格的不规则水（顶亮底暗），按抛物线飞起落回，越飞越小；
    落地处摊成一小片白沫、再降阶成一点暗水。水平速度按「落点不出 R」夹住。cone < 1 时往上收（S1 的一束）"""
    t = fi / FPS - t_delay
    if t < 0:
        return
    for j in range(n):
        dr = random.Random(seed * 53 + j)
        a = dr.random() * math.tau
        rr = R * dr.uniform(0.1, 0.45) * cone
        hp = H * dr.uniform(0.3, 1.0)
        vz = math.sqrt(2 * GRAV * max(1.0, hp))
        tmax = 2 * vz / GRAV
        vh = min(dr.uniform(18, 46) * cone, (R * 0.98 - rr) / tmax)
        d0 = dr.uniform(0.0, 0.05)
        tt = t - d0
        if tt < 0:
            continue
        dist = rr + vh * tt
        x, y = math.cos(a) * dist, math.sin(a) * dist * SY
        z = vz * tt - 0.5 * GRAV * tt * tt
        if z > 0:
            s = max(1, int(round(dr.uniform(size[0], size[1]) * (1.0 - 0.6 * tt / tmax))))
            for px in range(-s, s + 1):
                for py in range(-s, s + 1):
                    if px * px + py * py > s * s + 0.5:
                        continue
                    if s >= 2 and h1(px * 3.1 + py * 7.7 + j + fi * 0.3) < 0.25:   # 边缘缺几格，不规则
                        continue
                    ci = 6 if py < 0 else (5 if py == 0 else 4)
                    if fi <= 1 and py < 0:
                        ci = 7
                    if px < 0 and py <= 0:
                        ci = min(7, ci + 1)   # 左上受光
                    f.put(x + px, y - z + py, C[ci])
            if s >= 2 and dr.random() < 0.6:   # 甩出的单颗水滴
                f.put(x - math.cos(a) * (s + 2), y - z + s + 1, C[5])
        else:
            land = tt - tmax
            if land < 0.12:
                for q in (-1, 0, 1):
                    f.put(x + q, y, FOAM if q == 0 else C[5])
            elif land < 0.36:
                f.put(x, y, C[3])


def skirt(f, fi, R, seed):
    """贴地一圈很矮的水裙（1–3 格），只在第 1–2 拍，断口多，顶上白沫"""
    if fi not in (1, 2):
        return
    rr = R * (0.3 + 0.06 * fi)
    for a, x, y in ellipse_pts(rr):
        if vn(a * 3.0 + seed) < 0.4:
            continue
        hh = 1 + int(2.5 * vn(a * 5.0 + seed * 1.3)) - (fi - 1)
        for z in range(max(1, hh)):
            f.put(x, y - z, C[4] if z == 0 else C[5])
        f.put(x, y - max(1, hh), FOAM)


def crown(f, fi, R, H, nj, seed, tier, flash=True):
    """锚落点水花（11-05 用户第二轮「水花有点太像触手」后改）：第 0–1 拍尖刺爆闪 + 一圈很矮的水裙，
    主体是一把短促、不规则的水团往外飞起落回（不画细长弯曲的水舌）；落地成白沫点；之后水泡往上飘"""
    if flash:
        star(f, fi, R, seed)
    skirt(f, fi, R, seed)
    clumps(f, fi, R, H, nj, seed)
    bubbles(f, fi, R, seed, int(3 + tier * 2 + R // 20))


def column(f, fi, Wd, H, seed):
    """S1 重砸：一大团水从落点往上炸（水团都往上收成一束、个头大），不是柱子也不是细条；落回成白沫点"""
    star(f, fi, Wd * 2.2, seed, 1.6)
    if fi == 0:
        return
    clumps(f, fi, Wd * 1.6, H, 14, seed + 5, cone=0.45)
    clumps(f, fi, Wd * 1.6, H * 0.6, 8, seed + 9, cone=0.8, t_delay=0.03)
    bubbles(f, fi, Wd * 2, seed, 5, t0=3)


def cool_spots(R, seed, n=14):
    rnd = random.Random(seed + 31)
    out = []
    for i in range(n):
        a = rnd.random() * math.tau
        r = R * math.sqrt(rnd.uniform(0.15, 0.85))
        out.append((math.cos(a) * r, math.sin(a) * r * SY, rnd.randint(1, 6)))
    return out


def teardrop(f, x, y, vx, vy, size, cols):
    """尖尾泪滴：头圆（size 格）在前，尾巴顺着速度反方向收尖（2×size 格）"""
    L = math.hypot(vx, vy)
    dx, dy = (vx / L, vy / L) if L > 1e-6 else (1.0, 0.0)
    rr = max(0, size - 1)
    for px in range(-rr, rr + 1):
        for py in range(-rr, rr + 1):
            if px * px + py * py <= rr * rr + 0.5:
                f.put(x + px, y + py, cols[0])
    for i in range(1, size * 2 + 1):
        f.put(x - dx * (rr + i), y - dy * (rr + i), cols[1] if i <= size else cols[2])


def crown_spikes(f, R0, hmax, seed, fi, cols):
    """一圈往上掀的不规则尖水花（水冠）：底在半径 R0 的压扁圆上，每根 2 格宽、尖朝外斜，高低不一"""
    rnd = random.Random(seed)
    n = 22
    for i in range(n):
        a = (i + rnd.uniform(-0.3, 0.3)) * math.tau / n
        h = hmax * rnd.uniform(0.45, 1.0)
        bx, by = math.cos(a) * R0, math.sin(a) * R0 * SY
        lean = math.cos(a) * 0.45
        for z in range(int(h)):
            u = z / max(1.0, h)
            c = cols[0] if u > 0.7 else (cols[1] if u > 0.3 else cols[2])
            x = bx + lean * z
            f.put(x, by - z, c)
            if u < 0.55:
                f.put(x + (1 if math.cos(a) >= 0 else -1), by - z, cols[2])


W4 = [(16, 64, 156, 255), (24, 150, 226, 255), (96, 214, 250, 255), (206, 250, 255, 255)]   # 同鲸身（fx_pxplane_ul.W4）：深海蓝 / 饱和青 / 亮青 / 亮青白


def s3_impact_up(f, fi, R, seed):
    """S3 鲸砸地水爆（立起；docs/266 §17，协调人 11-05「砸下去那一刻反而变弱了，颜色也和鲸对不上」）：
    全用鲸身的四阶青蓝。第 0 帧：中心一大团实心亮团（宽约 0.6R、上半亮青白）+ 一圈往上掀的粗水花（3 格宽，半径 0.6R，尖亮青白）——
    砸地那一拍的水量不少于鲸身；第 1 帧：水冠更高、往外开，大水团（3–5 格）开始往外炸；第 2–3 帧：水冠塌、水团飞；
    第 2 帧起一次甩出 18 颗 1–3 格带尾的水珠，第 5–7 帧落回成白沫点"""
    rnd = random.Random(seed)
    R0 = R * 0.6
    if fi == 0 or fi == 1:
        rx, ry = (R0 * 0.8, 14) if fi == 0 else (R0 * 0.6, 10)
        for dx in range(-int(rx) - 1, int(rx) + 2):
            for dy in range(-ry * 2 - 2, 3):
                d2 = (dx / rx) ** 2 + ((dy + ry) / ry) ** 2
                if d2 < 1.0:
                    c = W4[3] if (d2 < 0.5 or fi == 0) else W4[2]
                    if fi == 0 and d2 < 0.3:
                        c = WHITE
                    f.put(dx, dy, c)
    if fi <= 2:   # 粗水冠：一圈厚的不规则水（0.7–1.0 倍冠半径之间都填），顶边参差、隔几处冲出粗尖；后半圈先画、前半圈盖上
        hmax = [18, 24, 12][fi]   # 第 3 帧起不留一圈「碗」
        rr0 = R0 * [1.0, 1.1, 1.18][fi]
        cols = []
        n = 200   # 相邻两列挨着，不留竖条缝
        for i in range(n):
            a = math.tau * i / n
            nz = vn(a * 4.0 + seed * 0.7)
            spike = vn(a * 9.0 + seed * 1.9) > 0.68
            hgt = hmax * (0.3 + 0.55 * nz) * (1.6 if spike else 1.0)
            for rk in (0.72, 0.8, 0.88, 0.96, 1.04):
                cols.append((math.sin(a), a, rr0 * rk, hgt * (1.0 - abs(rk - 0.9) * 1.2), spike))
        cols.sort(key=lambda q: q[0])
        for (_s, a, rr, hgt, spike) in cols:
            bx, by = math.cos(a) * rr, math.sin(a) * rr * SY
            lean = math.cos(a) * 0.45
            far = math.sin(a) < 0
            for z in range(max(1, int(hgt))):
                u = z / max(1.0, hgt)
                c = W4[3] if u > 0.7 else (W4[2] if u > 0.3 else W4[1])
                if far and u < 0.5:
                    c = W4[1] if u > 0.15 else W4[0]
                f.put(bx + lean * z, by - z, c)
    if 1 <= fi <= 4:   # 大水团往外炸（3–5 格，顶亮底暗）
        t = (fi - 1) / FPS
        for j in range(16):
            dr = random.Random(seed * 31 + j)
            a = dr.random() * math.tau
            r0 = R0 * dr.uniform(0.5, 0.9)
            vh = dr.uniform(60, 110)
            vz = dr.uniform(70, 140)
            dist = min(R * 0.98, r0 + vh * t)
            z = vz * t - 0.5 * 900 * t * t + 6
            if z < 0:
                continue
            x, y = math.cos(a) * dist, math.sin(a) * dist * SY - z
            s = max(1, int(round(dr.uniform(3, 5) * (1 - 0.25 * (fi - 1)))))
            for px in range(-s, s + 1):
                for py in range(-s, s + 1):
                    if px * px + py * py <= s * s:
                        f.put(x + px, y + py, W4[3] if py < 0 else (W4[2] if py == 0 else W4[1]))
    if fi >= 2:   # 18 颗带尾水珠，第 5 帧起落回成白沫点
        for j in range(18):
            dr = random.Random(seed * 53 + j)
            a = dr.random() * math.tau
            r1 = R * dr.uniform(0.6, 0.95)
            k = fi - 2
            if k <= 2:
                rr = R0 + (r1 - R0) * (k + 1) / 3.0
                z = [14, 10, 4][k] * dr.uniform(0.7, 1.3)
                x, y = math.cos(a) * rr, math.sin(a) * rr * SY - z
                size = max(1, 3 - k - (j % 2))
                teardrop(f, x, y, math.cos(a) * 3, math.sin(a) * SY * 3 + 2 + k, size, (W4[3], W4[2], W4[1]))
            elif k <= 5:
                x, y = math.cos(a) * r1, math.sin(a) * r1 * SY
                c = [W4[3], W4[2], W4[1]][k - 3]
                f.put(x, y, c)
                if k == 3:
                    f.put(x + 1, y, W4[2])


def s3_impact_gd(f, fi, R, seed):
    """S3 鲸砸地（贴地）：冲击环降为次要——和鲸同色的青色 2 格粗、带白沫断点，0–3 帧推到判定半径后淡掉；
    落点一片浅青水面（亮边 + 内侧淡青，不涂深色），保持约 0.6 秒（第 0–8 帧），之后一段段断开退去（第 9–14 帧）"""
    if fi <= 4:
        rr = R * [0.35, 0.62, 0.84, 1.0, 1.0][fi]
        for a, x, y in ellipse_pts(rr):
            if vn(a * 7.0 + seed + fi) < (0.12 if fi < 3 else 0.45):
                continue
            white = vn(a * 3.3 + seed * 2.1 + fi) > 0.8
            col = W4[3] if white else (W4[2] if fi < 3 else W4[1])
            f.put(x, y, col)
            k = (rr - 1.0) / rr
            f.put(x * k, y * k, col if fi < 3 else W4[1])
    if fi > 14:
        return
    wr = R * (0.55 if fi <= 8 else 0.55 * max(0.2, 1.0 - (fi - 8) / 7.0))
    gap = 0.0 if fi <= 8 else 0.12 * (fi - 8)
    for a, x, y in ellipse_pts(wr):
        if vn(a * 4.0 + seed * 1.3 + fi * 0.5) < gap:
            continue
        k = 0.88 + 0.16 * vn(a * 2.5 + seed)
        f.put(x * k, y * k, W4[3] if fi < 11 else W4[2], over=False)
        kk = (wr * k - 1.3) / max(1.0, wr)
        f.put(x * kk, y * kk, W4[2] if fi < 11 else W4[1], over=False)
    if fi <= 8:   # 水面里几条淡青水纹（不平涂）
        for j in range(6):
            dr = random.Random(seed + j)
            a0 = dr.random() * math.tau
            rr = wr * dr.uniform(0.3, 0.8)
            for s in range(10):
                a = a0 + s * 0.08
                if (s + fi) % 3:
                    f.put(math.cos(a) * rr, math.sin(a) * rr * SY, W4[1], over=False)


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
            v.append(("atk_r%d_e%d_up" % (R, el), "crown", {"R": R, "H": int(R * (0.42 + 0.06 * el)), "nj": 14 + 3 * el + R // 10, "tier": el, "seed": 11 + R + el}, 9, "up"))
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
    # S2 锁链界限：运行时画（fx_pxplane_ul._ring，会转），没有帧条
    # S3 落地（s3_r 140 → 70）
    for R in (70, 85):   # s3_r 140 / 虎鲸范围 s3_orca_r 170（docs/266 §20）
        v.append(("s3_r%d_up" % R, "s3up", {"R": R, "H": 40, "seed": 91}, 8, "up"))
        v.append(("s3_r%d_gd" % R, "s3gd", {"R": R, "seed": 91}, 15, "gd"))
    # 连携掷锚钉下（拖 180 内的小怪 → 90）
    v.append(("pin_gd", "inward", {"R": 90, "seed": 97}, 10, "gd"))
    return v


def size_of(kind, p):
    R = p.get("R", 10)
    if kind in ("crown", "s1", "s3up"):
        H = p.get("H", 20) + 30
        return int(R * 2 + 70), int(H + R * SY + 16), int(R + 35), int(H + 2)
    if kind == "spray":
        return int(R * 2 + 12), int(R * SY * 2 + 40), int(R + 6), int(R * SY + 34)
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
        elif kind == "s3up":
            s3_impact_up(f, fi, p["R"], p["seed"])
        elif kind == "s3gd":
            s3_impact_gd(f, fi, p["R"], p["seed"])
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
