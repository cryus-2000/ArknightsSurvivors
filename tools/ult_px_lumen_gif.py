#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""流明终结技 Q「灯火不灭 · 灯塔」转平面送审（docs/255 §9，ult/px_plane）：只用 Python、不开 Godot。

时间轴照游戏（ult_moves_c._lu_start / _lu_step，招式游戏时间 t）：
  超必杀暂停 5 拍（共用演出）→ t 0–0.2 灯塔光柱升起 + 预备（光点往中心收、圈内压暗）→
  t 0.2 光圈炸开 = 整招最大的一下：[A 版：冲击帧两拍「白底黑剪影 / 黑底白剪影」]→ 中心小亮核 2 拍 + 照地灯打满 + 轻震 3px / 0.12 秒 →
  厚冲击环 0.25 秒推到判定边缘 R（502 世界像素）、推过的地面闪一下、粒子云往外喷、被扫到的怪炸成自身颜色的像素（崩解）→
  慢动作：炸开后 0.5 秒放到 0.3 倍速，再用 0.15 秒加速回 1 倍 →
  t 0.45–2.2 两道灯塔光束旋转（1 秒一圈）、每 0.5 秒一跳（圈边一亮 + 圈内的怪身上一团闪烁粒子云）→ t 2.2 光柱从上往下熄灭 → 余辉 2 秒。
配色（「终结技用甲色」）：光柱 / 光束 / 冲击环钢蓝白（house.js OP.lumen 7 阶），灯芯一点灯火橙 #ff9640。红色不用。
1 特效像素 = 1 美术像素（屏上 2×2），15 fps 节拍，贴地层压扁 0.72。散布全按坐标哈希，不抽随机数。

两版：A = 照任务单在最大一下加冲击帧；B = 不加冲击帧（用户 10-31「流明不加冲击帧，他应该是比较温柔的」），慢动作两版都有。
输出：<out>/ult_lumen_A_1x.gif、ult_lumen_B_1x.gif、ult_lumen_A_x2.gif（中心 2 倍）、frames_A/、frames_B/（逐帧 PNG）、timeline.json（每帧的真实时间 / 游戏时间，配音效用）。
用法：python tools/ult_px_lumen_gif.py [--out 目录]
"""
import argparse, json, math, os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAIN = os.path.dirname(os.path.dirname(os.path.dirname(ROOT))) if ".claude" in ROOT else ROOT
PX = 2
W, H = 1280, 760
C = (640, 430)
SY = 0.72
R_W = 502.0          # 光圈判定半径（世界像素）
R = R_W / PX         # 美术像素
GROUND = (30, 40, 46)
FONT = "C:/Windows/Fonts/msyh.ttc"
CL = ["#121a2a", "#1d3150", "#2a5282", "#4285ad", "#7fb2d6", "#c4e0f2", "#ffffff"]
AC = "#ff9640"
T_BOOM = 0.2
T_EXP = 0.25
T_END = 2.25
SLOW_K, SLOW_T, RAMP_T = 0.3, 0.5, 0.15


def hx(s):
    s = s.lstrip("#")
    return tuple(int(s[i:i + 2], 16) for i in (0, 2, 4))


def hf(x, y=0, k=0):
    v = math.sin(x * 127.1 + y * 311.7 + k * 74.7) * 43758.5453
    return v - math.floor(v)


def snap(v):
    return (int(round(v[0] / 2) * 2), int(round(v[1] / 2) * 2))


def ease_out(x):
    x = max(0.0, min(1.0, x))
    return 1 - (1 - x) ** 3


# ---------------------------------------------------------------- 时间轴：[(真实时间, 阶段, 游戏时间 t, 冲击帧拍)]

def timeline(hf_on):
    out = []
    rt = 0.0
    dt = 1 / 15
    for i in range(5):
        out.append((rt, "sf", -1.0, -1)); rt += dt
    t = 0.0
    while t < T_BOOM - 1e-6:
        out.append((rt, "cast", t, -1)); rt += dt; t += dt
    t = T_BOOM
    if hf_on:
        out.append((rt, "cast", t, 0)); rt += dt
        out.append((rt, "cast", t, 1)); rt += dt
    # 慢动作：炸开后 SLOW_T 秒游戏时间放到 SLOW_K 倍速，再 RAMP_T 秒真实时间加速回 1 倍
    while t < T_BOOM + SLOW_T - 1e-6:
        out.append((rt, "cast", t, -1)); rt += dt; t += dt * SLOW_K
    n = max(1, int(round(RAMP_T * 15)))
    for i in range(n):
        out.append((rt, "cast", t, -1)); rt += dt; t += dt * (SLOW_K + (1 - SLOW_K) * (i + 1) / n)
    while t < T_END + 2.0:
        out.append((rt, "cast", t, -1)); rt += dt; t += dt
    return out


# ---------------------------------------------------------------- 场景

def load_sprite(path, n=None, fi=0):
    im = Image.open(path).convert("RGBA")
    if n is None:
        n = max(1, round(im.width / im.height))
    fw = im.width // n
    return im.crop((fi * fw, 0, (fi + 1) * fw, im.height))


def enemies():
    out = []
    kinds = [("offspring", (0.6, 0.9, 0.5)), ("slider", (0.45, 0.7, 1.0)), ("bone", (0.85, 0.9, 0.85)), ("stone", (0.7, 0.7, 0.75))]
    for i in range(40):
        a = hf(i, 21) * math.tau
        r = 80 + 520 * math.sqrt(hf(i, 22))
        p = (C[0] + math.cos(a) * r, C[1] + math.sin(a) * r * SY)
        if not (20 < p[0] < W - 20 and 60 < p[1] < H - 10):
            continue
        d = math.hypot((p[0] - C[0]), (p[1] - C[1]) / SY)
        out.append({"p": p, "k": kinds[i % 4], "d": d, "die": d <= R_W and hf(i, 3) < 0.62, "i": i})
    return out


ENS = enemies()


def ring_r(tau):
    """冲击环半径（世界像素）：0.16R → R，先快后慢"""
    return R_W * (0.16 + 0.84 * ease_out(tau / T_EXP))


def hit_tau(d):
    """冲击环推到距离 d 的时刻（爆后游戏秒）"""
    if d <= R_W * 0.16:
        return 0.0
    u = (d / R_W - 0.16) / 0.84
    return T_EXP * (1 - (1 - min(1.0, u)) ** (1 / 3))


# ---------------------------------------------------------------- 画面件（美术像素点：(x, y, 颜色, 发光?)）

def pillar(t, Hpx=310):
    """灯塔光柱（立起层）：脚底往上冲，外缘钢蓝、身子冰蓝、芯白，往上逐阶变暗；熄灭从上往下"""
    pts = []
    if t < 0:
        return pts
    rise = ease_out(t / 0.2)
    top = Hpx * rise
    cut = 0.0
    if t > 2.2:
        cut = min(1.0, (t - 2.2) / 0.3)
    y_lo = top * cut   # 熄灭：从上往下收
    bt = int(math.floor(t * 15))
    for y in range(0, int(top) + 1):
        if y > top - y_lo:
            continue
        v = y / Hpx
        hw = 9 - 3 * v + (1 if hf(y, bt, 3) > 0.8 else 0)
        m = int(round(hw))
        for q in range(-m, m + 1):
            a = abs(q)
            if a <= 1:
                ci = 6 if v < 0.7 else 5
            elif a <= m * 0.45:
                ci = 5
            elif a < m:
                ci = 4
            else:
                ci = 3
            ci -= (1 if v > 0.55 else 0) + (1 if v > 0.85 else 0)
            pts.append((q, -y, CL[max(2, ci)], a <= 1 and y % 3 == 0 and v < 0.8))
    if cut < 1:
        for yy in range(-1, 2):
            for xx in range(-2, 3):
                if abs(xx) + abs(yy) <= 2:
                    pts.append((xx, -2 + yy, AC if abs(xx) + abs(yy) <= 1 else CL[6], True))
    return pts


def prep(t):
    """预备 2 拍（t 0.067–0.2）：24 颗光点从 0.5–0.8R 往中心吸"""
    pts = []
    k = (t - (T_BOOM - 2 / 15)) / (2 / 15)
    if k < 0 or k > 1:
        return pts
    for i in range(24):
        a = i * 2.39996
        r0 = R * (0.5 + 0.3 * hf(i, 1))
        rr = r0 * (1 - ease_out(k) * 0.9)
        x, y = math.cos(a) * rr, math.sin(a) * rr * SY
        pts.append((x, y - 6, CL[6] if k > 0.5 else CL[5], True))
        pts.append((x - math.cos(a) * 2, y - 6 - math.sin(a) * 2 * SY, CL[4], False))
    return pts


def core(tau):
    """中心小亮核 2 拍（三层压扁小椭圆 + 灯火橙芯）——不做大块平涂"""
    if tau < 0 or tau >= 2 / 15:
        return []
    pts = []
    rx = 14
    for y in range(-rx, rx + 1):
        for x in range(-rx, rx + 1):
            q = math.hypot(x / rx, y / (rx * SY))
            if q > 1:
                continue
            ci = 6 if q < 0.45 else 5 if q < 0.75 else 4
            pts.append((x, y - 6, CL[ci], q < 0.75))
    for x, y in ((0, 0), (1, 0), (-1, 0), (0, 1), (0, -1)):
        pts.append((x, y - 6, AC, True))
    return pts


def shock_ring(tau):
    """压扁厚冲击环 8 格（前沿白、往后冰蓝 / 钢蓝），推到 R 后 2 拍淡掉；环后 6–14 格地面一闪"""
    pts = []
    if tau < 0:
        return pts, []
    rr = ring_r(tau) / PX
    fade = 0.0 if tau <= T_EXP else (tau - T_EXP) / (2 / 15)
    if fade >= 1:
        return pts, []
    th = 8 * (1 - 0.5 * fade)
    n = int(2 * math.pi * rr / 0.9)
    flash = []
    for j in range(n):
        an = j * 2 * math.pi / n
        ca, sa = math.cos(an), math.sin(an)
        jag = 0.8 * hf(j // 3, 7)
        for k in range(int(th) + 1):
            r = rr - k + jag
            ci = 6 if k < 2 else 5 if k < 4 else 4 if k < 6 else 3
            if fade > 0.5:
                ci -= 1
            pts.append((ca * r, sa * r * SY, CL[ci], k < 2 and j % 3 == 0))
        if j % 2 == 0 and fade == 0:
            for k in range(6, 15, 3):
                r = rr - th - k
                if r > 4:
                    flash.append((ca * r, sa * r * SY, CL[4], 0.5 * (1 - (k - 6) / 9)))
    return pts, flash


def cloud(age, seed, size, n, life=1.2, warm=0.1):
    """闪烁粒子云：n 颗 1–2 格小亮点 0.35 秒内往外炸开铺满半径 size，之后逐拍闪烁、往上漂、越剩越少"""
    pts = []
    if age < 0 or age > life:
        return pts
    bt = int(math.floor(age * 15))
    k = ease_out(age / 0.35)
    for i in range(n):
        h1, h2, h3 = hf(i, seed, 1), hf(i, seed, 2), hf(i, seed, 3)
        if age > 0.35 and h3 < (age - 0.35) / (life - 0.35):
            continue
        if (bt + i) % 3 == 0 and age > 0.2:
            continue   # 闪烁
        a = h1 * math.tau
        r = size * math.sqrt(h2) * k
        x, y = math.cos(a) * r, math.sin(a) * r * SY - age * 12 * h3
        c = AC if h3 < warm else (CL[6] if h3 > 0.75 else CL[5] if h3 > 0.4 else CL[4])
        sz = 2 if h1 > 0.66 else 1
        pts.append((x, y, c, h3 > 0.6, sz))
    return pts


def beam(t, s):
    """灯塔光束（立起）：从光柱灯口（离地 60 格）斜落到判定边缘，窄 → 宽、整道连续；1 秒一圈"""
    pts = []
    el = t - (T_BOOM + T_EXP)
    if el < 0 or t > 2.2:
        return pts, None
    fade = min(1.0, el / 0.15) * (1.0 if t < 2.0 else max(0.0, (2.2 - t) / 0.2))
    a = (t - T_BOOM) * math.tau / 1.0 + math.pi * s
    d = (math.cos(a), math.sin(a) * SY)
    src = (0.0, -60.0)
    tip = (d[0] * R, d[1] * R - 3)
    L = math.hypot(tip[0] - src[0], tip[1] - src[1])
    du = ((tip[0] - src[0]) / L, (tip[1] - src[1]) / L)
    nv = (-du[1], du[0])
    w1 = 9.0 * (0.35 + 0.65 * fade)
    sstep = 0.0
    while sstep <= L:
        u = sstep / L
        w = 1.0 + (w1 - 1.0) * u
        if u > 0.88:
            w *= 1 - (u - 0.88) / 0.12 * 0.6
        m = int(round(w))
        far = (1 if u > 0.75 else 0) + (1 if fade < 0.5 else 0)
        cx, cy = src[0] + du[0] * sstep, src[1] + du[1] * sstep
        q = -float(m)
        while q <= m:
            aq = abs(q)
            ci = (6 if u < 0.35 else 5) if aq <= 1 else 5 if aq < max(1, int(m * 0.5)) else 4 if aq < m - 0.5 else 3
            pts.append((cx + nv[0] * q, cy + nv[1] * q, CL[max(2, ci - far)], aq <= 1 and u < 0.6 and int(sstep) % 3 == 0))
            q += 0.5
        sstep += 0.5
    trace = []
    for k in range(int(R * 0.2), int(R)):
        trace.append((d[0] * k, d[1] * k, CL[3] if k > R * 0.45 else CL[2], False))
    return pts + trace, (d[0] * R * 0.55 * PX, d[1] * R * 0.55 * PX)


def edge_pulse(age):
    """每 0.5 秒一跳：判定圈边几段亮弧原地闪 3 拍（不外扩）"""
    pts = []
    if age < 0 or age > 0.2:
        return pts
    a = 1 - age / 0.2
    for seg in range(5):
        c0 = seg * math.tau / 5 + 0.3
        for j in range(60):
            an = c0 + (j - 30) / 30 * 0.45
            for k in range(2):
                r = R - k * 1.2
                if hf(j, seg, k) < a:
                    pts.append((math.cos(an) * r, math.sin(an) * r * SY, CL[5 if k == 0 else 3], k == 0 and j % 4 == 0))
    return pts


def disintegrate(age, e, spr):
    """崩解：怪物身体炸成自身颜色的像素（按贴图像素往外喷，有重量、落地停一下熄灭）+ 22 颗怪物代表色喷散（头两拍带白芯）"""
    pts = []
    if age < 0 or age > 1.0:
        return pts
    dx, dy = e["p"][0] - C[0], (e["p"][1] - C[1]) / SY
    dl = math.hypot(dx, dy) or 1
    ox, oy = dx / dl, dy / dl * SY
    arr = spr["px"]
    for j, (sx, sy, col) in enumerate(arr):
        h1, h2 = hf(j, e["i"], 1), hf(j, e["i"], 2)
        sp = 40 + 70 * h1
        vx = ox * sp + (h2 - 0.5) * 50
        vy = oy * sp - 40 - 50 * h2
        tl = _land_t(sy, vy, 160.0, 4.0)   # 落地即停（不在地上横滑）
        ta = min(age, tl)
        x = sx + vx * ta
        y = min(4.0, sy + vy * ta + 160 * ta * ta)
        if age > tl + 0.25 or (age > 0.5 and hf(j, e["i"], 5) < (age - 0.5) / 0.5):
            continue
        pts.append((x, y, col if age > 0.13 else CL[6] if j % 5 == 0 else col, False))
    ec = tuple(int(255 * v) for v in e["k"][1])
    shades = ["#%02x%02x%02x" % tuple(min(255, int(c * f)) for c in ec) for f in (1.25, 1.0, 0.6)]
    for j in range(22):
        h1, h2, h3 = hf(j, e["i"], 11), hf(j, e["i"], 12), hf(j, e["i"], 13)
        sp = 70 + 90 * h1
        vy0 = oy * sp - 60 * h3
        tl = _land_t(-10.0, vy0, 200.0, 4.0)
        ta = min(age, tl)
        x = ox * sp * ta + (h2 - 0.5) * 60 * ta
        y = min(4.0, -10 + vy0 * ta + 200 * ta * ta)
        if age > tl + 0.2 or (age > 0.5 and h3 < (age - 0.5) / 0.5):
            continue
        c = CL[6] if age < 2 / 15 and j % 3 == 0 else shades[j % 3]
        pts.append((x, y, c, age < 0.2, 2 if h1 > 0.5 else 1))
    return pts


def _land_t(y0, vy, gk, yg):
    """y0 + vy·t + gk·t² = yg 的正根（落地时刻）"""
    c = y0 - yg
    disc = vy * vy - 4 * gk * c
    if disc < 0:
        return 99.0
    t1 = (-vy + math.sqrt(disc)) / (2 * gk)
    return t1 if t1 > 0 else 99.0


def afterglow(t):
    pts = []
    if t < T_END:
        return pts
    a = max(0.0, 1 - (t - T_END) / 2.0)
    if a <= 0:
        return pts
    for seg in range(4):
        c0 = seg * math.tau / 4 + 0.8
        for j in range(80):
            an = c0 + (j - 40) / 40 * 0.6
            if hf(j, seg, 9) < a:
                r = R * 0.85
                pts.append((math.cos(an) * r, math.sin(an) * r * SY, CL[3], False))
    for i in range(14):   # 光点慢慢往上飘
        ph = (t - T_END + hf(i, 2) * 1.2) % 1.2
        an = hf(i, 4) * math.tau
        rr = R * 0.8 * math.sqrt(hf(i, 5))
        y = math.sin(an) * rr * SY - ph * 40
        if hf(i, 6) < a:
            pts.append((math.cos(an) * rr, y, AC if i % 4 == 0 else CL[5], True))
    return pts


# ---------------------------------------------------------------- 一帧

SPR = {}


def render(rt, ph, t, hfk, shake_on=True):
    img = Image.new("RGBA", (W, H), GROUND + (255,))
    g = np.asarray(img).copy()
    nz = np.random.default_rng(7).integers(-5, 6, size=(H // 2, W // 2, 1))
    g[..., :3] = np.clip(g[..., :3].astype(int) + np.repeat(np.repeat(nz, 2, 0), 2, 1), 0, 255)
    img = Image.fromarray(g.astype(np.uint8), "RGBA")
    emit = Image.new("RGB", (W, H), (0, 0, 0))
    ed = ImageDraw.Draw(emit)
    dr = ImageDraw.Draw(img)
    tau = t - T_BOOM if ph == "cast" else -1.0
    sh = (0, 0)
    if shake_on and 0 <= tau < 0.12:
        sh = (int(3 * math.sin(tau * 160)), int(3 * math.cos(tau * 210)))
    o = (C[0] + sh[0], C[1] + sh[1])

    def put(x, y, c, glow=False, a=1.0, sz=1):
        x, y = snap((x, y))
        if not (0 <= x < W - 1 and 0 <= y < H - 1):
            return
        cc = hx(c) if isinstance(c, str) else c
        if a < 1.0:
            base = img.getpixel((x, y))
            cc = tuple(int(base[i] * (1 - a) + cc[i] * a) for i in range(3))
        dr.rectangle([x, y, x + PX * sz - 1, y + PX * sz - 1], fill=tuple(cc[:3]) + (255,))
        if glow:
            ed.rectangle([x, y, x + PX * sz - 1, y + PX * sz - 1], fill=tuple(cc[:3]))

    def pts(org, lst):
        for q in lst:
            put(org[0] + q[0] * PX, org[1] + q[1] * PX, q[2], glow=q[3] if len(q) > 3 and isinstance(q[3], bool) else False, sz=q[4] if len(q) > 4 else 1)

    if hfk >= 0:   # 冲击帧（A 版）：整屏底 + 剪影（光柱 + 亮核 + 起始冲击环 + 流明）
        bg = (235, 230, 220) if hfk == 0 else (5, 5, 8)
        fg = (0, 0, 0) if hfk == 0 else (255, 255, 255)
        im2 = Image.new("RGB", (W, H), bg)
        d2 = ImageDraw.Draw(im2)
        sil = pillar(0.2) + core(0.0) + shock_ring(0.0)[0]
        for q in sil:
            x, y = snap((C[0] + q[0] * PX, C[1] + q[1] * PX))
            d2.rectangle([x, y, x + 1, y + 1], fill=fg)
        lum = SPR["lumen"]
        m = Image.new("RGB", lum.size, fg)
        im2.paste(m, snap((C[0] - lum.width // 2, C[1] - lum.height + 8)), lum.split()[3])
        return im2

    lights = []
    # ---- 地面层
    if 0 <= tau:
        rp, fl = shock_ring(tau)
        for q in fl:
            put(o[0] + q[0] * PX, o[1] + q[1] * PX, q[2], a=q[3])
    if ph == "cast" and T_BOOM - 2 / 15 <= t < T_BOOM + 0.2:   # 预备压暗：圈内暗椭圆
        kd = min(1.0, (t - (T_BOOM - 2 / 15)) / (2 / 15)) * (1.0 if t < T_BOOM else max(0.0, 1 - (t - T_BOOM) / 0.2))
        ov = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        ImageDraw.Draw(ov).ellipse([C[0] - R_W, C[1] - R_W * SY, C[0] + R_W, C[1] + R_W * SY], fill=(0, 0, 6, int(255 * 0.3 * kd)))
        img.alpha_composite(ov)
        dr = ImageDraw.Draw(img)
    if ph == "cast":
        for s in (0, 1):
            bp, lp = beam(t, s)
            for q in bp:
                if not q[3] and q[2] in (CL[2], CL[3]) and abs(q[1]) < 400 and q[1] > -50:   # 地面光痕
                    pass
        pts(o, edge_pulse(((t - 0.5) % 0.5) if 0.5 <= t <= 2.05 else -1))
        pts(o, afterglow(t))
    for e in ENS:   # 影子
        dr.ellipse([e["p"][0] - 10, e["p"][1] + 1, e["p"][0] + 10, e["p"][1] + 7], fill=(16, 20, 24, 255))
    # ---- 立起层（简化排序：怪 → 流明 → 光柱 / 特效）
    for e in ENS:
        age = tau - hit_tau(e["d"]) if tau >= 0 else -1
        if e["die"] and age >= 0:
            continue
        spr = SPR[e["k"][0]]
        im = spr["img"]
        if 0 <= age < 2 / 15 and e["d"] <= R_W:   # 被扫到的那一下闪白
            arr = np.asarray(im).copy()
            arr[..., :3] = np.clip(arr[..., :3].astype(int) + 140, 0, 255)
            im = Image.fromarray(arr, "RGBA")
        img.alpha_composite(im, dest=snap((e["p"][0] - im.width // 2, e["p"][1] - im.height + 6)))
    dr = ImageDraw.Draw(img)
    lum = SPR["lumen"]
    img.alpha_composite(lum, dest=snap((C[0] - lum.width // 2, C[1] - lum.height + 8)))
    dr = ImageDraw.Draw(img)
    if ph == "cast":
        pts(o, prep(t))
        pts(o, pillar(t))
        lights.append((C[0], C[1] - 40, 200, 0.45 * (1 if t < 2.2 else max(0, 1 - (t - 2.2) / 0.3)), (0.85, 0.95, 1.1)))
        for s in (0, 1):
            bp, lp = beam(t, s)
            pts(o, bp)
            if lp:
                lights.append((C[0] + lp[0], C[1] + lp[1], 90, 0.45, (0.85, 0.95, 1.1)))
        if tau >= 0:
            pts(o, core(tau))
            pts(o, shock_ring(tau)[0])
            pts((o[0], o[1] - 12), cloud(tau, 777, R * 0.6, 160))
            if tau < 2 / 15:
                lights.append((C[0], C[1], 240, 0.95, (0.85, 0.95, 1.15)))
            elif tau < 0.6:
                lights.append((C[0], C[1], 320, 0.6 * (1 - (tau - 2 / 15) / 0.47), (0.8, 0.92, 1.1)))
            for e in ENS:
                age = tau - hit_tau(e["d"])
                if e["die"]:
                    pts(e["p"], disintegrate(age, e, SPR[e["k"][0]]))
            for k in range(4):   # 每 0.5 秒一跳：圈内还活着的怪身上一团闪烁粒子云（路上用粒子云，不用烟团）
                tk = 0.5 * (k + 1)
                if tk <= t < tk + 0.8:
                    for e in ENS:
                        if not e["die"] and e["d"] <= R_W:
                            pts((e["p"][0], e["p"][1] - 16), cloud(t - tk, e["i"] * 5 + k, 18, 20, life=0.7))
    # ---- 光照 + 发光
    glow = np.asarray(emit.filter(ImageFilter.GaussianBlur(3))).astype(np.float32) * 0.55
    base = np.asarray(img.convert("RGB")).astype(np.float32) * 0.8
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    lit = np.zeros((H, W, 3), np.float32)
    for (lx, ly, lr, li, lc) in lights:
        dd = np.sqrt((xx - lx) ** 2 + ((yy - ly) / SY) ** 2) / lr
        lit += (li * np.clip(1.0 - dd, 0.0, 1.0) ** 2)[..., None] * np.array(lc, np.float32)
    out = np.clip(base * (1.0 + lit * 1.3) + lit * 40.0 + glow, 0, 255)
    if ph == "sf":   # 超必杀暂停（共用演出）：世界压暗，流明不压暗
        k = np.full((H, W, 1), 0.35, np.float32)
        y0, x0 = int(C[1] - lum.height + 8), int(C[0] - lum.width // 2)
        k[max(0, y0):y0 + lum.height, max(0, x0):x0 + lum.width] = 1.0
        out = out * k
    return Image.fromarray(out.astype(np.uint8), "RGB")


def label(t, ph, hfk):
    if ph == "sf":
        return "起手（超必杀暂停，共用演出）"
    if hfk >= 0:
        return "冲击帧（A 版）"
    if t < T_BOOM:
        return "灯塔光柱升起 · 预备（光点往中心收、圈内压暗）"
    if t < T_BOOM + SLOW_T:
        return "光圈炸开（最大一下）· 慢动作 0.3 倍 · 冲击环推到判定边缘 · 崩解"
    if t < 2.2:
        return "灯塔光束旋转 · 每 0.5 秒一跳"
    return "光柱熄灭 · 余辉"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join(MAIN, "Claude outputs", "ult_px_lumen_1105"))
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    SPR["lumen"] = load_sprite(os.path.join(ROOT, "game", "art", "operators", "lumen", "op_lumen_idle@2x.png"), 8)
    for nm in ("offspring", "slider", "bone", "stone"):
        p = os.path.join(ROOT, "game", "art", "enemies", nm, "e_%s@2x.png" % nm)
        if not os.path.exists(p):
            p = os.path.join(ROOT, "game", "art", "enemies", "offspring", "e_offspring@2x.png")
        im = load_sprite(p)
        arr = np.asarray(im).astype(np.float32)
        dim = arr.copy()
        dim[..., :3] = dim[..., :3] * 0.55 + 8
        im_d = Image.fromarray(np.clip(dim, 0, 255).astype(np.uint8), "RGBA")
        small = im.resize((im.width // PX, im.height // PX), Image.NEAREST)
        sa = np.asarray(small)
        px = []
        for yy in range(sa.shape[0]):
            for xx in range(sa.shape[1]):
                if sa[yy, xx, 3] > 128 and (xx + yy) % 2 == 0:
                    px.append((xx - sa.shape[1] / 2, yy - sa.shape[0] + 3, "#%02x%02x%02x" % tuple(int(v) for v in sa[yy, xx, :3])))
        SPR[nm] = {"img": im_d, "px": px}
    font = ImageFont.truetype(FONT, 20)
    meta = {}
    for ver, hf_on in (("A", True), ("B", False)):
        tl = timeline(hf_on)
        fdir = os.path.join(a.out, "frames_" + ver)
        os.makedirs(fdir, exist_ok=True)
        big, small = [], []
        for k, (rt, ph, t, hfk) in enumerate(tl):
            im = render(rt, ph, t, hfk)
            im.save(os.path.join(fdir, "f%03d.png" % k))
            sheet = im.copy()
            d = ImageDraw.Draw(sheet)
            d.text((12, 8), "流明终结技「灯塔」· 转平面 %s 版（%s）· 1 倍 · 15 fps 原速 · %s" % (ver, "最大一下加冲击帧" if hf_on else "不加冲击帧", label(t, ph, hfk)),
                   fill=(20, 20, 20) if hfk == 0 else (235, 225, 200), font=font)
            big.append(sheet)
            small.append(im.crop((C[0] - 320, C[1] - 250, C[0] + 320, C[1] + 110)).resize((1280, 720), Image.NEAREST))
        meta[ver] = [{"rt": round(rt, 4), "ph": ph, "t": round(t, 4), "hf": hfk} for rt, ph, t, hfk in tl]
        outs = [(big, "ult_lumen_%s_1x.gif" % ver)] + ([(small, "ult_lumen_%s_x2.gif" % ver)] if ver == "A" else [])
        for frames, nm in outs:
            pick = frames[:: max(1, len(frames) // 12)][:12]
            mos = Image.new("RGB", (frames[0].width, frames[0].height * len(pick)))
            for i, fr in enumerate(pick):
                mos.paste(fr, (0, i * frames[0].height))
            pal = mos.quantize(colors=255, method=Image.MEDIANCUT)
            q = [f.quantize(palette=pal, dither=Image.NONE) for f in frames]
            dur = [70 if i % 3 != 1 else 60 for i in range(len(q))]
            q[0].save(os.path.join(a.out, nm), save_all=True, append_images=q[1:], duration=dur, loop=0, optimize=False, disposal=1)
            print(nm, len(q), "帧", "%.1f 秒" % (len(q) / 15), "%.0f KB" % (os.path.getsize(os.path.join(a.out, nm)) / 1024), flush=True)
    json.dump(meta, open(os.path.join(a.out, "timeline.json"), "w", encoding="utf-8"), ensure_ascii=False)


if __name__ == "__main__":
    main()
