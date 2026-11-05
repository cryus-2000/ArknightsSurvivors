#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""乌尔比安转平面的送审 GIF（docs/266；协调人 11-05 流程：上 GCP 前先给用户看 GIF，只用 Python、不开 Godot）。

  - E0 / E1 / E2 左右并排（只放实际存在的档）；连携技单独一张；
  - 背景游戏地面色，怪物深色剪影，干员本体用 idle 第 0 帧；
  - 每栏上半 1 倍（= 实机大小：1 美术像素 = 2 屏幕像素），下半 2 倍放大（以落点为中心）；
  - 15 fps 原速循环（帧时长 70 / 60 / 70 毫秒交替）。
帧条直接取 tools/pxplane_bake_ulpianus.py 生成的同一批帧；锁链、水沟、冲锋尾迹、暗流通路、水泡、后期冲击波
按 game/scripts/render/fx_pxplane_ul.gd 的同一算法逐美术像素画（这里是 Python 抄写，改一边要同步另一边）。
锚用干员自己的锚贴图（op_ulpianus_anchor_native）。玩法时序按 ulpianus.json / seg_ulpianus：掷锚 s1_throw 0.16 → 咬地 → 拽回 dist/900（0.16–0.34）→ 停 0.14 → 重砸。
GIF 不含：场景压暗 / 受光、Noita 水滴颗粒与照地光（运行时）、受击闪色与打击感包（顿帧、轻震）。

用法：python tools/pxplane_gif_ulpianus.py [--only atk,s1] [--out 目录]
"""
import argparse, json, math, os, sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pxplane_bake_ulpianus as BK

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAIN = os.path.dirname(os.path.dirname(os.path.dirname(ROOT))) if ".claude" in ROOT else ROOT
PX = 2
W, H = 440, 270
OX, OY = 150, 170
GROUND = (36, 46, 48)
SY = 0.72
FONT = "C:/Windows/Fonts/msyh.ttc"
FPS = 15


def hx(s):
    s = s.lstrip("#")
    return tuple(int(s[i:i + 2], 16) for i in (0, 2, 4)) + (255,)


C = [hx(c) for c in ["#070a1e", "#0c1235", "#1b2a66", "#2c4397", "#4463c8", "#7b93e6", "#c0cbf6", "#ffffff"]]
DUST = [hx(c) for c in ["#131528", "#212842", "#323c5e", "#4a5781", "#6b7ba6", "#9eabcf"]]
WAKE_TAIL = 0.4


def h_(x):
    return math.fmod(math.sin(x * 12.9898 + 78.233) * 43758.5453, 1.0) % 1.0


def snap(v):
    return (round(v[0] / 2) * 2, round(v[1] / 2) * 2)


def bucket(v, opts):
    return min(opts, key=lambda q: abs(q - v))


def norm(v):
    L = math.hypot(v[0], v[1])
    return (v[0] / L, v[1] / L) if L > 1e-6 else (1.0, 0.0)


def lerp(a, b, k):
    return (a[0] + (b[0] - a[0]) * k, a[1] + (b[1] - a[1]) * k)


class Lib:
    def __init__(self):
        self.raw = BK.lib()
        self.cache = {}

    def frame(self, k, fi):
        frames, m = self.raw[k]
        if fi < 0 or fi >= m["n"]:
            return None, m
        ck = (k, fi)
        if ck not in self.cache:
            im = Image.fromarray(frames[fi], "RGBA")
            self.cache[ck] = im.resize((im.width * PX, im.height * PX), Image.NEAREST)
        return self.cache[ck], m

    def emit(self, k, fi):
        frames, m = self.raw[k]
        a = frames[fi]
        ys, xs = np.nonzero(a[..., 3] > 0)
        out = []
        for y, x in zip(ys, xs):
            r, g, b = (int(v) for v in a[y, x, :3])
            if (0.299 * r + 0.587 * g + 0.114 * b) / 255.0 > 0.86:
                out.append((x, y, (r, g, b)))
        return out[:48]


class Canvas:
    def __init__(self):
        rng = np.random.default_rng(7)
        g = np.zeros((H, W, 4), np.int32)
        g[..., :3] = GROUND
        g[..., 3] = 255
        nz = rng.integers(-5, 6, size=(H // 2, W // 2, 1))
        g[..., :3] += np.repeat(np.repeat(nz, 2, 0), 2, 1)
        self.img = Image.fromarray(np.clip(g, 0, 255).astype(np.uint8), "RGBA")
        self.d = ImageDraw.Draw(self.img)
        self.emit = Image.new("RGB", (W, H), (0, 0, 0))
        self.ed = ImageDraw.Draw(self.emit)

    def px(self, p, c):
        x, y = snap((OX + p[0], OY + p[1]))
        self.d.rectangle([x, y, x + 1, y + 1], fill=c)

    def pxa(self, p, c, a):
        """半透明的一个美术像素（2×2），按 a 混到底图上"""
        x, y = snap((OX + p[0], OY + p[1]))
        if not (0 <= x < W - 1 and 0 <= y < H - 1):
            return
        for dx in (0, 1):
            for dy in (0, 1):
                o = self.img.getpixel((x + dx, y + dy))
                self.img.putpixel((x + dx, y + dy), tuple(int(o[i] * (1 - a) + c[i] * a) for i in range(3)) + (255,))

    def glow(self, p, c):
        x, y = snap((OX + p[0], OY + p[1]))
        self.ed.rectangle([x, y, x + 1, y + 1], fill=c[:3])

    def strip(self, lib, k, fi, gp):
        im, m = lib.frame(k, fi)
        if im is None:
            return
        x = int(OX + gp[0] - m["ox"] * PX)
        y = int(OY + gp[1] - m["oy"] * PX)
        self.img.alpha_composite(im, dest=(x, y)) if 0 <= x and 0 <= y and x + im.width <= W and y + im.height <= H else self._paste_clip(im, x, y)
        for (ex, ey, c) in lib.emit(k, fi):
            self.ed.rectangle([x + ex * PX, y + ey * PX, x + ex * PX + 1, y + ey * PX + 1], fill=c)

    def _paste_clip(self, im, x, y):
        layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        layer.paste(im, (x, y), im)
        self.img.alpha_composite(layer)

    def sprite(self, im, x, y):
        self._paste_clip(im, int(x), int(y))

    def final(self):
        gl = self.emit.filter(ImageFilter.GaussianBlur(3))
        base = np.asarray(self.img.convert("RGB"), np.int32)
        add = np.asarray(gl, np.int32)
        return Image.fromarray(np.clip(base + add * 0.8 + np.asarray(self.emit, np.int32) * 0.3, 0, 255).astype(np.uint8))


# ---------------------------------------------------------------- 运行时件（抄 fx_pxplane_ul.gd）

def chain(cv, a, b, taut, tier, thin, T):
    L = math.hypot(b[0] - a[0], b[1] - a[1])
    if L < 2:
        return
    d = ((b[0] - a[0]) / L, (b[1] - a[1]) / L)
    nv = (-d[1], d[0])
    n = int(L / PX)
    beat = int(math.floor(T * 15))
    glint = (n - (beat * 5) % max(1, n + 8)) if taut == 2 else -99
    for i in range(n + 1):
        p = (a[0] + d[0] * i * PX, a[1] + d[1] * i * PX)
        if thin:
            cv.px(p, DUST[2] if i % 3 else DUST[4])
            continue
        m = i % 4
        body = DUST[4] if taut > 0 else DUST[3]
        hi = DUST[5] if taut > 0 else DUST[4]
        if taut == 3:
            body, hi = C[6], C[7]
            if i % 3 == 0:
                cv.glow(p, C[6])
        elif abs(i - glint) <= 1:
            body, hi = C[6], C[7]
            cv.glow(p, C[6])
        elif tier >= 2 and m == 2 and (i // 4 + beat) % 5 == 0:
            hi = C[6]
        if m in (0, 1):
            cv.px((p[0] + nv[0] * PX, p[1] + nv[1] * PX), body)
            cv.px((p[0] - nv[0] * PX, p[1] - nv[1] * PX), DUST[2])
        elif m == 2:
            cv.px(p, hi)
        else:
            cv.px(p, DUST[2])


def vwake(cv, frm, to, w, fade, sd):
    L = math.hypot(to[0] - frm[0], to[1] - frm[1])
    if L < 6:
        return
    d = ((to[0] - frm[0]) / L, (to[1] - frm[1]) / L)
    nv = norm((-d[1], d[0] * SY))
    n = int(L / PX)
    foam = [C[6], C[5], C[4]][fade]
    dark = [C[2], C[1], C[1]][fade]
    for i in range(n):
        u = i / max(1, n)
        p = (frm[0] + d[0] * i * PX, frm[1] + d[1] * i * PX)
        spread = (1.0 - u) * (4.0 + 3.0 * w) + 1.5
        if h_(i * 0.71 + sd) > 0.18:
            cv.px((p[0] + nv[0] * spread * PX, p[1] + nv[1] * spread * PX), foam)
            cv.px((p[0] - nv[0] * spread * PX, p[1] - nv[1] * spread * PX), foam if h_(i * 1.3 + sd) > 0.25 else C[5])
        if i % 2 == 0:
            cv.px(p, dark)


def trail(cv, a, b_full, age, dur, cool_t=0.8, ease_out=False):
    """S3 深海拖痕（抄 fx_pxplane_ul._draw_zip）"""
    k = min(1.0, max(0.0, age / max(0.001, dur)))
    b = lerp(a, b_full, k * (2 - k) if ease_out else k * k)
    L = math.hypot(b[0] - a[0], b[1] - a[1])
    if L < 4:
        return
    d = ((b[0] - a[0]) / L, (b[1] - a[1]) / L)
    nv = norm((-d[1], d[0] * SY))
    cool = max(0.0, age - dur) / cool_t
    n = int(L / PX)
    for i in range(n):
        p = (a[0] + d[0] * i * PX, a[1] + d[1] * i * PX)
        fresh = (n - i) < 8 and cool <= 0
        if h_(i * 0.61 + 2.3) < cool * 1.2 - 0.2:
            continue
        cv.px(p, C[0] if cool < 0.6 else C[1])
        if cool < 0.75:
            cv.px((p[0] + nv[0] * PX, p[1] + nv[1] * PX), C[1])
            cv.px((p[0] - nv[0] * PX, p[1] - nv[1] * PX), C[1])
        if cool < 0.45 and h_(i * 0.37 + 5.1) > 0.3:
            cv.px((p[0] + nv[0] * 2 * PX, p[1] + nv[1] * 2 * PX), C[5] if fresh else C[2])
        if cool < 0.45 and h_(i * 0.83 + 1.7) > 0.3:
            cv.px((p[0] - nv[0] * 2 * PX, p[1] - nv[1] * 2 * PX), C[6] if fresh else C[3])


def ring(cv, c, R, rot, tone, tier, T):
    """S2 锁链环（抄 fx_pxplane_ul._ring）"""
    n = max(8, int(math.tau * R / 5.0))
    body = DUST[4] if tone == 1 else DUST[3]
    hi = DUST[5] if tone == 1 else DUST[4]
    gl = int(math.floor(T * 15)) % n if tier >= 2 else -1
    for i in range(n):
        a = rot + math.tau * i / n
        p = snap((c[0] + math.cos(a) * R * PX, c[1] + math.sin(a) * R * SY * PX))
        h2 = hi
        if i == gl:
            h2 = C[6]
            cv.glow((p[0], p[1] - PX), C[6])
        if i % 2 == 0:
            for x in (-1, 0, 1):
                cv.px((p[0] + x * PX, p[1]), body)
                cv.px((p[0] + x * PX, p[1] - PX), h2)
            cv.px((p[0], p[1] + PX), DUST[0])
        else:
            cv.px(p, DUST[2])
            cv.px((p[0], p[1] - PX), body)


def qib(cv, c, v, tier, gone, sd, brk=0.17):
    """后期冲击波原地碎开（抄 fx_pxplane_ul._draw_qib）：先站一下，再塌成水点"""
    if gone < 0.0 or gone > brk + 0.015:
        return
    u = gone / brk
    if u < 0.45:
        crest(cv, snap(c), norm(v), tier, False, sd, 1.0 - u * 0.6, False)
        return
    d = norm(v)
    nv = norm((-d[1], d[0] * SY))
    c = snap(c)
    half = 12 + 3 * tier
    v2 = (u - 0.45) / 0.55
    for s_ in range(-half, half + 1):
        w = 1.0 - (s_ / half) ** 2
        hs = h_(s_ * 1.7 + sd)
        base = (c[0] + nv[0] * s_ * PX + d[0] * v2 * 6 * hs * PX, c[1] + nv[1] * s_ * PX + d[1] * v2 * 6 * hs * PX)
        cv.px(base, C[1] if v2 < 0.6 else C[0])
        if hs < v2 * 0.8:
            continue
        z = (6.0 + 3.0 * tier) * w * (1 - v2) * (0.6 + 0.4 * hs)
        top = (base[0], base[1] - z * PX)
        cv.px(top, C[6] if v2 < 0.5 else C[5])
        if w > 0.5:
            cv.px((top[0] + PX, top[1]), C[5])


def rift(cv, a, b, age, sd):
    L = math.hypot(b[0] - a[0], b[1] - a[1])
    if L < 4:
        return
    d = ((b[0] - a[0]) / L, (b[1] - a[1]) / L)
    nv = norm((-d[1], d[0] * SY))
    grow = min(1.0, max(0.0, age / 0.12))
    fade = 0 if age < 0.3 else (1 if age < 0.55 else 2)
    n = int(L * grow / PX)
    for i in range(n):
        u = i / max(1.0, L / PX)
        o = math.sin(sd * 10.0 + i * 0.4) * 1.5 * PX
        p = (a[0] + d[0] * i * PX + nv[0] * o, a[1] + d[1] * i * PX + nv[1] * o)
        w = 1.0 + 1.5 * math.sin(u * math.pi)
        cv.px(p, [C[0], C[1], C[1]][fade])
        if w > 1.6:
            cv.px((p[0] + nv[0] * PX, p[1] + nv[1] * PX), [C[1], C[1], C[2]][fade])
        if h_(i * 0.53 + sd) > 0.35:
            cv.px((p[0] + nv[0] * (w + 1) * PX, p[1] + nv[1] * (w + 1) * PX), [C[6], C[5], C[3]][fade])
        if h_(i * 0.91 + sd * 2.0) > 0.45:
            cv.px((p[0] - nv[0] * (w + 0.5) * PX, p[1] - nv[1] * (w + 0.5) * PX), [C[5], C[4], C[2]][fade])


def bub(cv, a, age, sd):
    beat = int(math.floor(age * 15))
    for j in range(2):
        b0 = int(h_(sd + j) * 4.0) + j * 3
        bage = beat - b0
        if bage < 0 or bage > 6:
            continue
        x = (h_(sd * 3.0 + j) - 0.5) * 12.0 + math.sin(bage * 0.9 + sd) * 1.5
        p = snap((a[0] + x * PX * 0.5, a[1] - 6.0 - bage * 5.0))
        if bage == 6:
            for q in ((-2, 0), (2, 0), (0, -2), (0, 2)):
                cv.px((p[0] + q[0] * PX, p[1] + q[1] * PX), C[5])
            continue
        for q in ((-1, -1), (0, -1), (1, -1), (-1, 0), (1, 0), (-1, 1), (0, 1), (1, 1)):
            cv.px((p[0] + q[0] * PX, p[1] + q[1] * PX), C[6] if q[1] < 0 else C[5])
        cv.px((p[0] - PX, p[1] - PX), C[7])
        cv.glow((p[0] - PX, p[1] - PX), C[6])


def qi(cv, c, v, tier, hot, dying, sd, T):
    crest(cv, snap(c), norm(v), tier, hot, sd, 1.0, True)


def crest(cv, c, d, tier, hot, sd, k, wake):
    """抄 fx_pxplane_ul._crest"""
    nv = norm((-d[1], d[0] * SY))
    half = 12 + 3 * tier
    Hh = (9.0 + 3.0 * tier) * k
    th = 5 + tier
    for s in range(-half, half + 1):
        u = s / half
        hh0 = Hh * (1 - u * u) * (0.75 + 0.5 * h_(s * 0.7 + sd))
        for j in range(th - 1, -1, -1):
            base = (c[0] + nv[0] * s * PX - d[0] * j * PX, c[1] + nv[1] * s * PX - d[1] * j * PX)
            hh = int(round(hh0 * (1.0 - 0.6 * j / th)))
            cv.px(base, C[1])
            for z in range(hh):
                col = (C[6] if z >= hh - 2 else C[5]) if j == 0 else (C[4] if j < th - 2 else C[3])
                cv.px((base[0], base[1] - (z + 1) * PX), col)
            if j == 0 and hh > 0:
                top = (base[0], base[1] - (hh + 1) * PX)
                cv.px(top, C[7])
                if abs(s) * 2 < half and (hot or s % 2 == 0):
                    cv.glow(top, C[6])
    if wake:
        for j in range(th + 1, th + 12):
            p = (c[0] - d[0] * j * PX, c[1] - d[1] * j * PX)
            w = half * (1.0 - (j - th) / 14.0)
            if h_(j + sd) > 0.25:
                cl = C[5] if j < th + 6 else C[4]
                cv.px((p[0] + nv[0] * w * PX, p[1] + nv[1] * w * PX), cl)
                cv.px((p[0] - nv[0] * w * PX, p[1] - nv[1] * w * PX), cl)



ORCA = [hx(c) for c in ["#0d0f15", "#262c38", "#4a5781", "#e8ecf4", "#b4bccc", "#5c6577"]]
ORCA_LEAP = 0.18


def orca_head(S, P, land, dur, t):
    """抄 seg_ulpianus.orca_head（玩法路径结算与画面共用）"""
    sw = dur - ORCA_LEAP
    if t <= sw:
        k = min(1.0, max(0.0, t / max(0.001, sw)))
        return lerp(S, P, k * (2 - k))
    return lerp(P, land, min(1.0, max(0.0, (t - sw) / ORCA_LEAP)))


WC = [hx(c) for c in ["#14306a", "#3a7ccc", "#6fb0ec", "#d6eeff"]]
ORCA_K = 1.45
ORCA_H = 64.0


def orca_cell(u, w, beat):
    """抄 fx_pxplane_ul._orca_cell（头圆钝、背鳍高竖直、眼后白斑 3、腹部浅色带 4）"""
    if u > 21 or u < -23:
        return -1
    tw = math.sin(beat * 1.8) * 1.5 if u < -12 else 0.0
    w -= tw
    if u >= 4:
        hh = 7.5 * max(0.0, 1 - ((u - 4) / 17.0) ** 3) ** 0.33
    elif u >= -10:
        hh = 7.5 * math.sqrt(max(0.0, 1 - ((u - 4) / 18.0) ** 2))
    elif u >= -18:
        hh = 1.6 + (4.8 - 1.6) * (u + 18) / 8.0
    else:
        hh = 1.4 + (-18 - u) * 1.3
        if abs(w) < 1.0 and u < -21:
            return -1
    fin = 0.0
    if -3 < u < 3:
        fin = 14.0 * min((u + 3) / 1.5, (3 - u) / 3.5)
    if w > hh + fin or w < -hh:
        return -1
    if w > hh:
        return 0
    if ((u - 11) / 4.0) ** 2 + ((w - 2.4) / 1.5) ** 2 <= 1.0:
        return 3
    if w < -hh * 0.45 and -7 < u < 18:
        return 4
    return 1 if w > -hh * 0.2 else 2


def orca_bubble(u, w, beat):
    for i in range(4):
        cu = (12.0 - beat * 2.5 + i * 11.0) % 34.0 - 18.0
        cw = math.sin(i * 1.7) * 3.0
        du, dw = u - cu, w - cw
        d2 = du * du + dw * dw
        if d2 < 0.5:
            return 0
        if d2 < 2.6:
            return 2 if (du < -0.4 and dw > 0.4) else 1
    return 0


def draw_orca(cv, gp, z, pitch, dv, clip, T, ghost=0):
    """S3 虎鲸（docs/266 §16）：生图剪影 + 程序水，算法在 tools/pxplane_orcamask_ulpianus.py（读游戏里的 pxp_ul_orcam_* 帧条）"""
    import pxplane_orcamask_ulpianus as OM
    OM.draw_whale(cv, gp, z, pitch, dv, clip, T, ghost)


def draw_orca_v11(cv, gp, z, pitch, dv, clip, T, ghost=0):
    """抄 fx_pxplane_ul._draw_orca（鲸形水体：实心主体、3–4 阶蓝、后段透明、残影）"""
    gp = snap(gp)
    e = norm((dv[0], dv[1] * SY))
    flip = 1.0 if e[0] >= 0 else -1.0
    a = pitch * flip
    e = (e[0] * math.cos(a) - e[1] * math.sin(a), e[0] * math.sin(a) + e[1] * math.cos(a))
    n = (-e[1], e[0])
    if n[1] > 0:
        n = (-n[0], -n[1])
    beat = int(math.floor(T * 15))
    if not clip and ghost == 0 and z > 6:
        sk = min(1.0, max(0.45, 1 - z / 160.0))
        rx, ry = 22 * sk, 6 * sk
        for iy in range(-int(ry), int(ry) + 1):
            for ix in range(-int(rx), int(rx) + 1):
                if (ix / rx) ** 2 + (iy / ry) ** 2 <= 1:
                    cv.pxa((gp[0] + ix * PX, gp[1] + iy * PX), C[0], 0.45)
    if clip:   # 破水：一道水弧把头顶出来
        for i in range(-18, 19):
            a2 = i / 18.0
            hgt = 11.0 * math.sqrt(max(0.0, 1 - a2 * a2))
            p0 = (gp[0] + e[0] * i * PX, gp[1] + e[1] * i * PX)
            cv.px((p0[0], p0[1] - hgt * PX), WC[3])
            for zz in range(int(hgt)):
                cv.pxa((p0[0], p0[1] - zz * PX), WC[1], 0.7)
            if abs(i) > 12 and h_(i + beat) > 0.4:
                sg = 1 if i > 0 else -1
                cv.px((p0[0] + sg * 2 * PX, p0[1] - (hgt + 3 + h_(i * 1.7 + beat) * 6) * PX), WC[2])
    c = snap((gp[0], gp[1] - z - 10))
    K = ORCA_K
    ga = [1.0, 0.35, 0.18][min(2, ghost)]
    dot = lambda q, v: q[0] * v[0] + q[1] * v[1]
    for jy in range(-26, 27):
        for ix in range(-40, 41):
            q = (ix, jy)
            u, w = dot(q, e) / K, dot(q, n) / K
            k = orca_cell(u, w, beat)
            if k < 0:
                continue
            pp = (c[0] + ix * PX, c[1] + jy * PX)
            if clip and pp[1] > gp[1] - 2:
                continue
            if ghost > 0:
                cv.pxa(pp, WC[1], ga)
                continue
            up = orca_cell(dot((ix, jy - 1), e) / K, dot((ix, jy - 1), n) / K, beat) < 0
            dn = orca_cell(dot((ix, jy + 1), e) / K, dot((ix, jy + 1), n) / K, beat) < 0
            rear = u < -8
            al = 1.0
            if up:
                col = WC[3]
                if u > 12 or k == 0:
                    cv.glow(pp, WC[3])
            elif dn:
                col = WC[0]
            elif u > 17 or k == 3:
                col = WC[3]
            elif k == 4:
                col = WC[2]
            else:
                col = WC[1]
                fl = h_(math.floor(u * 0.6 + beat * 1.5) * 0.37 + math.floor(w * 0.5))
                if fl > 0.82:
                    col, al = WC[2], 0.8
            if rear and not up:
                al *= 0.55
            if al >= 0.999:
                cv.px(pp, col)
            else:
                cv.pxa(pp, col, al)


def telegraph(cv, c, R, T):
    """抄 fx_pxplane_ul._telegraph：落点判定半径上一道断续细环"""
    n = int(math.tau * R / 2.0)
    beat = int(math.floor(T * 15))
    for i in range(n):
        if ((i + beat) // 3) % 2 == 1:
            continue
        a = math.tau * i / n
        cv.px((c[0] + math.cos(a) * R * PX, c[1] + math.sin(a) * R * SY * PX), C[4])


def draw_swing(cv, c, dv, age, T):
    """抄 fx_pxplane_ul._draw_swing（挥锚带水弧）"""
    hs = norm((dv[0], dv[1] * SY))
    piv = (c[0], c[1] - 20)
    Ra = 30.0
    kk = min(1.0, max(0.0, age / 0.1))
    th_h = -0.75 + (2.5 + 0.75) * (1 - (1 - kk) ** 2)
    fade = 0 if age < 0.1 else (1 if age < 0.15 else 2)
    th0 = max(-0.75, th_h - 1.9)
    steps = int((th_h - th0) * Ra / PX) + 1
    for i in range(steps):
        th = th_h - i * PX / Ra
        v = i / max(1, steps)
        p = (piv[0] + hs[0] * math.cos(th) * Ra, piv[1] + hs[1] * math.cos(th) * Ra - math.sin(th) * Ra)
        col = C[5] if v < 0.35 else (C[4] if v < 0.7 else C[3])
        if fade == 1:
            col = C[5] if v < 0.5 else C[4]
        elif fade == 2:
            if h_(i * 0.7) < 0.5:
                continue
            col = C[4]
        cv.px(p, col)
        if v < 0.5 and fade == 0:
            R2 = Ra + PX
            cv.px((piv[0] + hs[0] * math.cos(th) * R2, piv[1] + hs[1] * math.cos(th) * R2 - math.sin(th) * R2), C[5])
            if v < 0.12:
                cv.glow(p, C[6])
    if fade < 2:
        beat = int(math.floor(T * 15))
        for j in range(5):
            th2 = th_h - h_(j * 2.3 + beat) * 1.2
            out = Ra + 4 + h_(j + beat * 0.9) * 10
            cv.px((piv[0] + hs[0] * math.cos(th2) * out, piv[1] + hs[1] * math.cos(th2) * out - math.sin(th2) * out), C[6] if j % 2 == 0 else C[5])


# ---------------------------------------------------------------- 本体 / 怪 / 锚

_SPR = {}


def op_sprite():
    if "op" not in _SPR:
        im = Image.open(os.path.join(ROOT, "game", "art", "operators", "ulpianus", "op_ulpianus_idle@2x.png")).convert("RGBA")
        fw = im.width // 8
        _SPR["op"] = im.crop((0, 0, fw, im.height))
    return _SPR["op"]


def anchor_img(ang):
    key = ("an", round(math.degrees(ang) / 15) * 15)
    if key not in _SPR:
        im = Image.open(os.path.join(ROOT, "game", "art", "operators", "ulpianus", "op_ulpianus_anchor_native@2x.png")).convert("RGBA")
        piv = (0.3355619 * im.width, 0.5011066 * im.height)
        big = Image.new("RGBA", (im.width * 2, im.height * 2), (0, 0, 0, 0))
        big.paste(im, (int(im.width - piv[0]), int(im.height - piv[1])))
        _SPR[key] = big.rotate(-key[1], resample=Image.NEAREST)
    return _SPR[key]


def draw_anchor(cv, p, d):
    im = anchor_img(math.atan2(d[1], d[0]))
    cv.sprite(im, OX + p[0] - im.width // 2, OY + p[1] - im.height // 2)


def draw_enemy(cv, e):
    x, y = snap((OX + e["p"][0], OY + e["p"][1]))
    r = e.get("r", 9)
    big = r > 12
    col = (14, 16, 22, 255)
    cv.d.ellipse([x - r, y - 3, x + r, y + 3], fill=(18, 24, 26, 255))
    cv.d.ellipse([x - r + 2, y - r * 2 + 2, x + r - 2, y - 1], fill=col)
    cv.d.ellipse([x - r // 2 - 1, y - r * 2 - 6, x + r // 2 + 1, y - r * 2 + 4], fill=col)
    if big:
        cv.d.rectangle([x - 3, y - r * 2 - 9, x + 3, y - r * 2 - 6], fill=(60, 30, 36, 255))


# ---------------------------------------------------------------- 场景（玩法时序的近似）

HAND = (14, -30)


class Scene:
    """items：帧条 {k, t0, gp, ly} 与运行时件；enemies：[{p0, path(t)→p}]；tether(t) → 锁链与锚的画法"""

    def __init__(self, tier, dur, focus):
        self.tier, self.dur, self.focus = tier, dur, focus
        self.items, self.enemies, self.overs, self.opos = [], [], [], (lambda T: (0.0, 0.0))
        self.ox = 150
        self.oy = 170
        self.h = 270

    def strip(self, k, t0, gp, ly):
        self.items.append({"k": "ul_" + k, "t0": t0, "gp": gp, "ly": ly})

    def pair(self, k, t0, gp):
        self.strip(k + "_up", t0, gp, "up")
        self.strip(k + "_gd", t0, gp, "gd")


def fi_of(T, t0):
    return int(math.floor(T * 15 + 1e-6)) - int(math.floor(t0 * 15 + 1e-6))


def render_scene(sc, lib, T):
    cv = Canvas()
    op = sc.opos(T)
    # 贴地层
    for it in sc.items:
        if T < it["t0"]:
            continue
        if it["ly"] == "gd" and "k" in it:
            cv.strip(lib, it["k"], fi_of(T, it["t0"]), it["gp"])
        elif it["ly"] == "rt_gd":
            it["fn"](cv, T)
    # 排序层：怪 / 干员 / 立起帧条 / 立起运行时件
    srt = []
    for e in sc.enemies:
        p = e["path"](T)
        if p is not None:
            srt.append((p[1], 0, lambda cv=cv, p=p, e=e: draw_enemy(cv, {"p": p, "r": e.get("r", 9)})))
    spr = op_sprite()
    srt.append((op[1], 1, lambda: cv.sprite(spr, OX + op[0] - 64, OY + op[1] - 120)))
    for it in sc.items:
        if T < it["t0"]:
            continue
        if it["ly"] == "up" and "k" in it:
            srt.append((it["gp"][1] + 1, 2, lambda it=it: cv.strip(lib, it["k"], fi_of(T, it["t0"]), it["gp"])))
        elif it["ly"] == "rt_up":
            gy = it["gy"]
            if getattr(sc, "orca_gy", None) and sc.orca_gy[0] is it:
                gy = sc.orca_gy[1](T)
            srt.append((gy, 2, lambda it=it: it["fn"](cv, T)))
    srt.sort(key=lambda q: (q[0], q[1]))
    for _y, _k, fn in srt:
        fn()
    for fn in sc.overs:
        fn(cv, T, op)
    return cv.final()


def column_frames(sc, lib):
    global OX, OY, H
    OX, OY, H = sc.ox, sc.oy, sc.h
    n = int(round(sc.dur * FPS))
    out = []
    for f in range(n):
        T = f / FPS
        fx, fy = sc.focus_fn(T) if getattr(sc, "focus_fn", None) else sc.focus
        im = render_scene(sc, lib, T)
        cx, cy = OX + fx, OY + fy
        cw, ch = W // 2, H // 2
        x0 = int(min(max(0, cx - cw // 2), W - cw))
        y0 = int(min(max(0, cy - ch // 2 - 10), H - ch))
        zoom = im.crop((x0, y0, x0 + cw, y0 + ch)).resize((W, H), Image.NEAREST)
        col = Image.new("RGB", (W, H * 2 + 2), (10, 12, 14))
        col.paste(im, (0, 0))
        col.paste(zoom, (0, H + 2))
        out.append(col)
    return out


def assemble(cols, labels, title):
    font = ImageFont.truetype(FONT, 15) if os.path.exists(FONT) else ImageFont.load_default()
    n = max(len(c) for c in cols)
    frames = []
    for f in range(n):
        im = Image.new("RGB", (len(cols) * (W + 6) - 6, cols[0][0].height + 26), (10, 12, 14))
        d = ImageDraw.Draw(im)
        for i, c in enumerate(cols):
            im.paste(c[f % len(c)], (i * (W + 6), 26))
            d.text((i * (W + 6) + 6, 4), "%s · %s（上 1 倍 / 下 2 倍）" % (title, labels[i]), fill=(220, 226, 236), font=font)
        frames.append(im.convert("P", palette=Image.ADAPTIVE, colors=255))
    return frames


def save_gif(frames, path):
    durs = [70 if i % 3 != 1 else 60 for i in range(len(frames))]
    frames[0].save(path, save_all=True, append_images=frames[1:], duration=durs, loop=0, disposal=1, optimize=False)


# ---------------------------------------------------------------- 各招

def static_enemy(p, r=9):
    return {"path": lambda T, p=p: p, "r": r}


def sc_atk(tier):
    """普攻锚击（reach 89，落点 front 0.55）+ 撼地（150 / 精二 180）；精一收链（外圈两只被拉向落点 20）"""
    sc = Scene(tier, 1.4, (56, -10))
    c = (49, 0)
    sc.pair("atk_r44_e%d" % tier, 0.1, c)
    sc.strip("quake_r%d_gd" % (90 if tier >= 2 else 75), 0.1, (0, 0), "gd")
    for p in ((70, -14), (40, 18), (88, 10)):
        sc.enemies.append(static_enemy(p))
    if tier >= 1:
        for p0 in ((150, -40), (140, 40)):
            dv = norm((c[0] - p0[0], c[1] - p0[1]))
            sc.enemies.append({"path": lambda T, p0=p0, dv=dv: lerp(p0, (p0[0] + dv[0] * 20, p0[1] + dv[1] * 20), min(1, max(0, (T - 0.1) / 0.15))), "r": 9})
    else:
        sc.enemies.append(static_enemy((150, -40)))
    return sc


def tether_scene(sc, t_throw, to, hooked, slam_r, front_d=34, s1=True):
    """S1：掷锚 → 咬地 → 拽回（锁链）→ 停 → 重砸"""
    d = norm(to)
    hand = HAND
    dist = math.hypot(to[0], to[1])
    tb = t_throw + 0.16
    reel = min(0.34, max(0.16, dist / 900.0))
    th = tb + reel
    ts = th + 0.14
    front = (d[0] * front_d, d[1] * front_d)
    spots = []
    for i, p0 in enumerate(hooked):
        side = (1.0 if i % 2 == 1 else -1.0) * math.ceil(i / 2.0)
        spots.append((front[0] + d[0] * 4.5 + (-d[1]) * side * 16 + d[0] * abs(side) * 6, front[1] + d[1] * 4.5 + d[0] * side * 16 + d[1] * abs(side) * 6))

    def epath(i, p0):
        def f(T):
            if T < tb:
                return p0
            k = min(1.0, (T - tb) / reel)
            kr = 1 - (1 - k) * (1 - k)
            return lerp(p0, spots[i], kr)
        return f
    for i, p0 in enumerate(hooked):
        sc.enemies.append({"path": epath(i, p0), "r": 11 if i == 0 else 9})
    sc.pair("bite_r14", tb, to)
    if sc.tier >= 1:
        for i, p0 in enumerate(hooked):
            ep = epath(i, p0)
            sc.items.append({"ly": "rt_gd", "t0": tb, "fn": lambda cv, T, ep=ep, p0=p0, i=i: vwake(cv, p0, ep(min(T, th)), 1 + sc.tier, 0 if T < th else (1 if T < th + WAKE_TAIL * 0.5 else 2), i * 0.37) if T < th + WAKE_TAIL else None})
    c = (d[0] * 89 * 0.55, d[1] * 89 * 0.55)
    sc.pair("s1_r%d_e%d" % (bucket(slam_r / 2, [45, 56, 68]), sc.tier), ts, c)

    def over(cv, T, op):
        if T < t_throw or T >= ts:
            return
        if T < tb:
            k = (T - t_throw) / 0.16
            travel = k * k * (2 - k)
            pa = (hand[0] + (to[0] - hand[0]) * travel, hand[1] + (to[1] - hand[1]) * travel - math.sin(k * math.pi) * 10)
            chain(cv, hand, pa, 1, sc.tier, False, T)
            draw_anchor(cv, pa, d)
            return
        if T < th:
            k = (T - tb) / reel
            kr = 1 - (1 - k) * (1 - k)
            ph = lerp(to, front, kr)
            ph = (ph[0], ph[1] - 6)
            chain(cv, hand, ph, 2, sc.tier, False, T)
            for i, p0 in enumerate(hooked):
                ep = epath(i, p0)(T)
                chain(cv, ph, (ep[0], ep[1] - 5), 2, sc.tier, False, T)
            draw_anchor(cv, ph, (-d[0], -d[1]))
            return
        ph = (front[0], front[1] - 6)
        chain(cv, hand, ph, 1, sc.tier, False, T)
        draw_anchor(cv, ph, (-d[0], -d[1]))
    sc.overs.append(over)
    return ts


def sc_s1(tier):
    sc = Scene(tier, 1.6, (60, -6))
    to = (190, -20)
    ts = tether_scene(sc, 0.1, to, [(196, -16), (180, -6)], 90)
    sc.enemies.append(static_enemy((60, 24)))
    return sc


def sc_s1_branch(kind):
    sc = Scene(2, 1.8, (90, -6))
    to = (190, -20)
    if kind == "rift":
        ts = tether_scene(sc, 0.1, to, [(196, -16), (180, -6)], 90)
        tb = 0.26
        sd = 0.31
        sc.items.append({"ly": "rt_gd", "t0": tb, "fn": lambda cv, T: rift(cv, (0, 0), to, T - tb, sd) if T - tb < 0.8 else None})
        L = math.hypot(*to)
        s = 20.0
        k = 0
        while s < L and k < 12:
            q = lerp((0, 0), to, s / L)
            sc.items.append({"ly": "rt_up", "t0": tb, "gy": q[1] + 1, "fn": lambda cv, T, q=q, k=k: bub(cv, q, T - tb, h_(q[0] + q[1] * 1.7)) if 0 <= T - tb < 0.8 else None})
            s += 34
            k += 1
        for p in ((80, -10), (120, -14)):
            sc.enemies.append({"path": lambda T, p=p: (p[0], p[1] - (math.sin(min(1, max(0, (T - tb) / 0.8)) * math.pi) * 30 if T > tb else 0)), "r": 9})
    else:   # 不容挣脱 + 绞杀
        ts = tether_scene(sc, 0.1, to, [(196, -16), (180, -6)], 90)
        t2 = 0.1 + 0.6
        sc.pair("s1_r68_e2", t2 + 0.0, (49, -5))

        def over(cv, T, op):
            if T < ts:
                return
            for i, p in enumerate(((36, -10), (44, 10))):
                tight = i == 0
                chain(cv, HAND, (p[0], p[1] - 5), 1 if tight else 0, 2, not tight, T)
        sc.overs.append(over)
    return sc


def sc_s2(tier):
    sc = Scene(tier, 1.8, (0, -10))
    t0 = 0.1

    def ringfn(cv, T):
        age = T - t0
        if age < 0:
            return
        if age < 0.9:   # 起手：从脚下扩到锚击半径再收回
            u = min(1.0, age / 0.33)
            rr = 24 + (68 - 24) * (1 - (1 - u) ** 2) if age < 0.55 else 68 + (24 - 68) * min(1.0, (age - 0.55) / 0.3)
            ring(cv, (0, 2), rr, math.floor(T * 15) * 0.09, 1 if age < 0.55 else 0, tier, T)
        ring(cv, (0, 2), 24, math.floor(T * 15) * 0.02, 0, tier, T)   # 常驻
    sc.items.append({"ly": "rt_gd", "t0": 0.0, "fn": ringfn})
    sc.pair("atk_r68_e%d" % tier, 1.0, (75, 0))
    sc.strip("quake_r%d_gd" % (90 if tier >= 2 else 75), 1.0, (0, 0), "gd")
    for p in ((96, -12), (60, 16), (120, 20), (-80, 30)):
        sc.enemies.append(static_enemy(p))
    return sc


def sc_s3():
    """S3 虎鲸（docs/266 §8，改玩法）：本人不动。掷锚那 0.22 秒虎鲸在身前 20 处从水里冒出来；之后沿直线游到落点前 24
    （时长 = 距离/900 夹 0.12–0.36，先快后慢，路径上每个敌人吃一次），再跃起 0.18 秒砸下 = 落地重击（爆白 → 水团 → 潮水退去）；身后深海拖痕"""
    sc = Scene(2, 1.9, (150, -16))
    sc.ox = 70
    sc.oy, sc.h = 330, 420   # 鲸外框 200 世界像素、跃起 64：画框加高
    to = (250, -24)
    d = norm(to)
    t0 = 0.1
    tb = t0 + 0.22
    land = (to[0] - d[0] * 18, to[1] - d[1] * 18)
    S = (d[0] * 20, d[1] * 20)
    P = (land[0] - d[0] * 24, land[1] - d[1] * 24)
    dur = min(0.36, max(0.12, math.hypot(P[0] - S[0], P[1] - S[1]) / 900.0)) + ORCA_LEAP
    sw = dur - ORCA_LEAP
    tl = tb + dur
    sc.pair("bite_r22", t0, S)   # 破水
    sc.items.append({"ly": "rt_up", "t0": t0, "gy": 1.5, "fn": lambda cv, T: draw_swing(cv, (0, 0), d, T - t0, T) if 0 <= T - t0 < 0.2 else None})   # 挥锚带水弧（短而急）
    bt = tl * 15
    t0b = (math.ceil(bt) if bt - math.floor(bt) > 0.5 else math.floor(bt)) / 15.0   # 同 fx_pxplane_ul._beat_t0
    sc.strip("s3_up", t0b, land, "up")
    sc.strip("s3_gd", t0b, land, "gd")
    sc.items.append({"ly": "rt_up", "t0": t0b, "gy": land[1] + 3, "fn": lambda cv, T: shatter_fn(cv, T)})
    path_es = [(70, -6), (130, -14), (180, -18)]
    for p in path_es:   # 路径上：虎鲸经过时被撞开一点（画面上的轻击退近似）
        def ep(T, p=p):
            if T < tb:
                return p
            hd = orca_head(S, P, land, dur, min(T - tb, sw))
            passed = (hd[0] - p[0]) * d[0] + (hd[1] - p[1]) * d[1] > 0
            return (p[0], p[1] + (6 if passed else 0))
        sc.enemies.append({"path": ep, "r": 9})
    for p in ((246, -20), (210, 6), (280, -60), (190, -60)):
        sc.enemies.append(static_enemy(p, 11 if p == (246, -20) else 9))

    B = 1 / 15.0

    def pose(T):   # 抄 fx_pxplane_ul._orca_pose_t（按 15 fps 节拍取）
        if t0 <= T < tb:
            tt = T - t0
            tbr = 0.22 - 2 * B
            if tt < tbr:
                return None
            k = min(1.0, (tt - tbr) / (2 * B))
            return S, -22 + 26 * k, -0.55, True
        if tb <= T < tl:
            tt = T - tb
            hd = orca_head(S, P, land, dur, tt)
            t_slam = dur - B
            t_hold = t_slam - 2 * B
            if tt < t_hold:
                s0 = min(1.0, tt / max(0.001, t_hold))
                return hd, 14 + (ORCA_H - 14) * (1 - (1 - s0) ** 2), -0.75 + 0.75 * s0, False
            if tt < t_slam:
                return hd, ORCA_H + (2 if tt < t_hold + B else 0), 0.08, False
            return hd, ORCA_H * 0.35, 1.3, False
        return None

    def fn_g(gi):
        def fn(cv, T):
            Tq = math.floor(T * 15 + 1e-6) / 15.0 - gi * B
            ps = pose(Tq)
            if ps and pose(math.floor(T * 15 + 1e-6) / 15.0):
                draw_orca(cv, ps[0], ps[1], ps[2], d, ps[3], T, gi)
        return fn
    for gi in (2, 1):
        sc.items.append({"ly": "rt_up", "t0": t0, "gy": -0.01 * gi, "fn": fn_g(gi), "gi": gi})
    sc.items.append({"ly": "rt_gd", "t0": t0, "fn": lambda cv, T: telegraph(cv, land, 70, T) if t0 <= T < tl else None})

    def fn(cv, T):
        ps = pose(math.floor(T * 15 + 1e-6) / 15.0)
        if ps:
            draw_orca(cv, ps[0], ps[1], ps[2], d, ps[3], T)
    def pose4(Tt):   # 拖尾用：(gp, z, pitch, clip)
        ps = pose(math.floor(Tt * 15 + 1e-6) / 15.0) if Tt >= t0 else None
        return ps

    def trail_fn(cv, T):
        import pxplane_orcamask_ulpianus as OM
        if t0 <= T < tl + 0.6:
            OM.draw_trail(cv, pose4, math.floor(T * 15 + 1e-6) / 15.0, d)
    sc.items.append({"ly": "rt_up", "t0": t0, "gy": -2.0, "fn": trail_fn})

    def shatter_fn(cv, T):
        import pxplane_orcamask_ulpianus as OM
        k = int(math.floor(T * 15 + 1e-6)) - int(math.floor(t0b * 15 + 1e-6))
        if 0 <= k <= 1:
            OM.draw_shatter(cv, land, d, k)
    it = {"ly": "rt_up", "t0": t0, "gy": 0.0, "fn": fn}
    sc.items.append(it)
    sc.orca_gy = (it, lambda T: (pose(math.floor(T * 15 + 1e-6) / 15.0)[0][1] + 1) if pose(math.floor(T * 15 + 1e-6) / 15.0) else 0.0)

    def focus(T):   # 2 倍图跟着虎鲸（含跃起高度），落地后对准落点，不裁出画框
        ps = pose(math.floor(T * 15 + 1e-6) / 15.0)
        if ps:
            return ps[0][0], ps[0][1] - ps[1] * 0.6 - 20
        return (land[0], land[1] - 10) if T >= tl else (S[0], S[1] - 10)
    sc.focus_fn = focus
    return sc


def sc_nodes(kind):
    sc = Scene(1, 1.4, (0, -6) if kind == "whirl" else (56, -6))
    if kind == "whirl":
        sc.strip("whirl_r65_gd", 0.1, (0, 0), "gd")
        for a in range(5):
            ang = a * 1.3
            sc.enemies.append(static_enemy((math.cos(ang) * 110, math.sin(ang) * 110 * SY)))
    else:
        c = (49, 0)
        sc.pair("atk_r44_e1", 0.1, c)
        sc.strip("quake_r75_gd", 0.1, (0, 0), "gd")
        sc.pair("echo_r50", 0.3, c)
        for p in ((70, -14), (40, 18), (100, 10)):
            sc.enemies.append(static_enemy(p))
    return sc


def sc_e2throw():
    """精二每第 3 下掷锚（hookshot：飞 dist/900 → 落地 → 绷紧 0.2 → 沿线拖回 0.18 → 到位）"""
    sc = Scene(2, 1.7, (120, -6))
    sc.ox = 90
    to = (240, -10)
    d = norm(to)
    dist = math.hypot(*to)
    fly = min(0.24, max(0.1, dist / 900.0))
    t0 = 0.1
    ti = t0 + fly
    tt = ti + 0.2
    tdr = tt + 0.18
    sc.pair("bite_r22", ti, to)
    sc.strip("echo_r50_gd", ti, to, "gd")
    front = (d[0] * 60, d[1] * 60)
    line = [(120, -6), (170, -4), (210, -14)]
    for i, p0 in enumerate(line):
        def ep(T, p0=p0, i=i):
            if T < tt:
                return p0
            k = min(1.0, (T - tt) / 0.18)
            return lerp(p0, (front[0] + i * 6, front[1] + (i - 1) * 10), 1 - (1 - k) ** 2)
        sc.enemies.append({"path": ep, "r": 9})
        sc.items.append({"ly": "rt_gd", "t0": tt, "fn": lambda cv, T, ep=ep, p0=p0, i=i: vwake(cv, p0, ep(min(T, tdr)), 2, 0 if T < tdr else (1 if T < tdr + 0.2 else 2), i * 0.37) if T < tdr + WAKE_TAIL else None})
    sc.strip("small_r16_gd", tdr, front, "gd")

    def over(cv, T, op):
        if T < t0 or T > tdr + 0.05:
            return
        if T < ti:
            p = lerp(HAND, to, (T - t0) / fly)
            p = (p[0], p[1] - 6)
            chain(cv, HAND, p, 0, 2, False, T)
            draw_anchor(cv, p, d)
            return
        if T < tt:
            p = (to[0], to[1] - 6)
            chain(cv, HAND, p, 2, 2, False, T)
            draw_anchor(cv, p, d)
            return
        k = min(1.0, (T - tt) / 0.18)
        p = lerp(to, front, 1 - (1 - k) ** 2)
        p = (p[0], p[1] - 6)
        chain(cv, HAND, p, 2, 2, False, T)
        draw_anchor(cv, p, (-d[0], -d[1]))
    sc.overs.append(over)
    return sc


def sc_link():
    """连携 v2「掷锚」：锚 0.2 秒飞到区域主目标（精英）→ 钉住 1.5 秒；180 内小怪 0.5 秒里被拖向它"""
    sc = Scene(1, 1.6, (150, -6))
    sc.ox = 90
    tp = (165, -10)
    t0 = 0.1
    tpin = t0 + 0.2
    sc.enemies.append(static_enemy(tp, 13))
    sc.strip("pin_gd", tpin, tp, "gd")
    sc.pair("bite_r22", tpin, tp)
    for i, p0 in enumerate(((90, -40), (250, 26), (120, 44), (230, -50))):
        def ep(T, p0=p0):
            if T < tpin:
                return p0
            q = p0
            n = int(min(0.5, T - tpin) * 60)
            for _ in range(n):
                q = (q[0] + (tp[0] - q[0]) * 0.12 * 0.25, q[1] + (tp[1] - q[1]) * 0.12 * 0.25)
            return q
        sc.enemies.append({"path": ep, "r": 8})
        sc.items.append({"ly": "rt_gd", "t0": tpin, "fn": lambda cv, T, ep=ep, p0=p0, i=i: vwake(cv, p0, ep(min(T, tpin + 0.5)), 1, 0 if T < tpin + 0.5 else (1 if T < tpin + 0.7 else 2), i * 0.37) if T < tpin + 0.5 + WAKE_TAIL else None})
    fp = (0, -20)
    d = norm((tp[0] - fp[0], tp[1] - fp[1]))

    def over(cv, T, op):
        age = T - t0
        if age < 0 or age > 0.7:
            return
        if age < 0.2:
            q = lerp(fp, tp, age / 0.2)
            chain(cv, fp, q, 1, 1, False, T)
            draw_anchor(cv, q, d)
            return
        chain(cv, fp, (tp[0], tp[1] - 6), 2, 1, False, T)
        draw_anchor(cv, (tp[0], tp[1] - 6), d)
    sc.overs.append(over)
    return sc


def sc_qi(tier):
    """后期冲击波（late_shape 近战扩域的额外一击，锚类 blunt）：从刀光边缘（reach × 0.7）飞出，520 / 秒，飞到 reach × 1.6"""
    sc = Scene(tier, 0.8, (110, -6))
    reach = 89 * (1 + 0.15 * (tier + 1))
    skip = reach * 0.7
    dist = reach * 1.6
    life = (dist - skip) / 520.0
    t0 = 0.1
    for p in ((150, -6), (190, 6), (60, 14)):   # 只画冲击波本身（同一下的锚击水冠见 atk，叠在一起看不清冲击波）
        sc.enemies.append(static_enemy(p))
    v = (500.0, -60.0)

    def fn(cv, T):
        age = T - t0
        if age < 0 or age > life:
            return
        tick = math.floor(T * 15) / 15.0   # 15 fps 跳格
        a2 = max(0.0, tick - t0)
        p = (skip + v[0] * a2 * 0.995, v[1] * a2 * 0.995 * (skip and 1))
        qi(cv, p, v, tier, age < 1 / 15.0, life - age < 0.07, 0.3, T)

    def fnb(cv, T):   # 玩法上消失后原地碎开
        tick_end = math.floor((t0 + life) * 15) / 15.0
        a2 = max(0.0, tick_end - t0)
        p = (skip + v[0] * a2 * 0.995, v[1] * a2 * 0.995)
        qib(cv, p, v, tier, T - (t0 + life), 0.47)   # 玩法上没了以后原地再立 0.17 秒
    sc.items.append({"ly": "rt_up", "t0": t0, "gy": 0.5, "fn": fn})
    sc.items.append({"ly": "rt_up", "t0": t0, "gy": 0.6, "fn": fnb})
    return sc


SCENES = {
    "atk": ("普攻锚击", [("E0", lambda: sc_atk(0)), ("E1 收链", lambda: sc_atk(1)), ("E2 暗涡", lambda: sc_atk(2))]),
    "s1": ("S1 必须促成的接触", [("E0", lambda: sc_s1(0)), ("E1 拖拽水沟", lambda: sc_s1(1)), ("E2", lambda: sc_s1(2))]),
    "s1_branch": ("S1 分支", [("通路洞开", lambda: sc_s1_branch("rift")), ("不容挣脱 + 绞杀", lambda: sc_s1_branch("leash"))]),
    "s2": ("S2 必须维系的界限", [("E1", lambda: sc_s2(1)), ("E2 冷光", lambda: sc_s2(2))]),
    "s3": ("S3 虎鲸（本人不动）", [("E2", sc_s3)]),
    "e2throw": ("精二掷锚 / 锚链应答", [("E2", sc_e2throw)]),
    "nodes": ("成长", [("锁链回旋", lambda: sc_nodes("whirl")), ("定点爆破", lambda: sc_nodes("blast"))]),
    "qi": ("后期冲击波（late_shape）", [("E0", lambda: sc_qi(0)), ("E1", lambda: sc_qi(1)), ("E2", lambda: sc_qi(2))]),
    "link": ("连携技「掷锚」", [("link/v2", sc_link)]),
}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    ap.add_argument("--out", default=os.path.join(MAIN, "Claude outputs", "pxplane_ulpianus_1105", "gif"))
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    lib = Lib()
    only = set(a.only.split(",")) if a.only else None
    for key, (title, cols) in SCENES.items():
        if only and key not in only:
            continue
        fr = [column_frames(fn(), lib) for _lab, fn in cols]
        frames = assemble(fr, [lab for lab, _ in cols], title)
        path = os.path.join(a.out, "ulpianus_%s.gif" % key)
        save_gif(frames, path)
        print(path, len(frames), "帧", "%.0f KB" % (os.path.getsize(path) / 1024))


if __name__ == "__main__":
    main()
