#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""歌蕾蒂娅转平面的送审 GIF（docs/263；协调人 11-05 新流程：上 GCP 前先给用户看 GIF，只用 Python、不开 Godot）。

按游戏里的摆法拼每招一张 GIF（版式同 pxplane-siege 会话的 pxplane_gif.py）：
  - E0 / E1 / E2 左右并排（只放实际存在的档）；连携技单独一张；
  - 背景游戏地面色，打在几只怪（深色剪影）上，干员本体用 idle 第 0 帧；
  - 每栏上半 1 倍（= 实机大小：1 美术像素 = 2 屏幕像素），下半 2 倍放大；
  - 15 fps 原速循环（一拍 = 一帧，帧时长 70 / 60 / 70 毫秒交替，平均 66.7）。
帧条用 tools/pxplane_bake_gladiia.py 烘出的同一批 PNG；运行时线状件（链、钩头、拖痕、裂断翻卷浪与暗沟、沉底锁链）
按 game/scripts/render/fx_pxplane_gl.gd 的同一算法逐美术像素画（这里是 Python 抄写，改一边要同步另一边）。
玩法时序按 gladiia.json / seg_ulpianus 的钩索：飞 dist/900 秒（0.1–0.24）→ 绷紧 0.12 → 拖 0.22（kr = 1-(1-k)²）→ 到位。
贴地层先画；立起层、怪、干员按脚底 y 排序；链与钩头在上层；热芯（emit）近似发光层加一层柔光。场景压暗 / 受光不模拟。

用法：python tools/pxplane_gif_gladiia.py [--only atk,s1] [--out 目录]
"""
import argparse, json, math, os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAIN = os.path.dirname(os.path.dirname(os.path.dirname(ROOT))) if ".claude" in ROOT else ROOT
PX = 2
W, H = 440, 270
OX, OY = 110, 175
GROUND = (36, 46, 48)
SY = 0.72
FONT = "C:/Windows/Fonts/msyh.ttc"
DIRS = [-90, -45, 0, 45, 90]


def hx(s):
    s = s.lstrip("#")
    return tuple(int(s[i:i + 2], 16) for i in (0, 2, 4)) + (255,)


C = [hx(c) for c in ["#0d1a2e", "#182f51", "#294a78", "#3a65a0", "#4c80c7", "#8bacdb", "#c9d9ee", "#ffffff"]]
CH = [hx(c) for c in ["#243246", "#5c7090", "#8798b3", "#dbe2ec", "#f6f8fb"]]
ACC = hx("#b3a8ee")
ACC2 = hx("#7a6cc8")
HIT_R = [38, 52, 66]
S1_R = [35, 48, 61]


def h_(x):
    return math.fmod(math.sin(x * 12.9898 + 78.233) * 43758.5453, 1.0) % 1.0


def vn(x):
    i = math.floor(x)
    f = x - i
    f = f * f * (3 - 2 * f)
    return h_(i) + (h_(i + 1.0) - h_(i)) * f


def snap(v):
    return (round(v[0] / 2) * 2, round(v[1] / 2) * 2)


def bucket(v, opts):
    return min(opts, key=lambda q: abs(q - v))


def pick_dir(ang):
    a = (math.degrees(ang) + 180) % 360 - 180
    flip = False
    if abs(a) > 90:
        a = (180 - a + 180) % 360 - 180
        flip = True
    best = 0
    for d in DIRS:
        if abs(a - d) < abs(a - best):
            best = d
    return best, flip


class Lib:
    def __init__(self):
        m = json.load(open(os.path.join(ROOT, "game", "data", "pxp_gladiia.json"), encoding="utf-8"))
        self.meta = {"gl_" + k: v for k, v in m.items() if k != "_doc"}
        self.tex = {}

    def frame(self, k, fi, loop=False):
        m = self.meta[k]
        n = m["n"]
        if loop:
            fi %= n
        if fi < 0 or fi >= n:
            return None
        if k not in self.tex:
            self.tex[k] = Image.open(os.path.join(ROOT, "game", "art", "fx", "pxp", "pxp_%s.png" % k.replace("_d-", "_dm"))).convert("RGBA")
        w, hh = m["w"], m["h"]
        return self.tex[k].crop((fi * w, 0, (fi + 1) * w, hh)), m


# ---------------------------------------------------------------- 画布：世界坐标（相对干员脚底）→ 画面像素

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
        if len(c) == 4 and c[3] < 255:
            self.img.alpha_composite(Image.new("RGBA", (2, 2), c), dest=(int(x), int(y))) if 0 <= x < W - 1 and 0 <= y < H - 1 else None
        else:
            self.d.rectangle([x, y, x + 1, y + 1], fill=c)

    def glow(self, p, c):
        x, y = snap((OX + p[0], OY + p[1]))
        self.ed.rectangle([x, y, x + 1, y + 1], fill=c[:3])

    def strip(self, lib, k, fi, gp, flip=False, loop=False):
        r = lib.frame(k, fi, loop)
        if r is None:
            return
        fr, m = r
        if flip:
            fr = fr.transpose(Image.FLIP_LEFT_RIGHT)
        gx, gy = snap((OX + gp[0], OY + gp[1]))
        left = gx - (m["w"] - m["ox"]) * PX if flip else gx - m["ox"] * PX
        top = gy - m["oy"] * PX
        big = fr.resize((fr.width * PX, fr.height * PX), Image.NEAREST)
        L, T = int(left), int(top)
        self.img.alpha_composite(big, dest=(max(0, L), max(0, T)), source=(max(0, -L), max(0, -T)))
        pts = m["emit"][fi % len(m["emit"])] if m["emit"] else []
        for q in pts:
            x = q[0] if not flip else m["w"] - 1 - q[0]
            self.ed.rectangle([L + x * PX, T + q[1] * PX, L + x * PX + 1, T + q[1] * PX + 1], fill=tuple(int(q[2][i:i + 2], 16) for i in (0, 2, 4)))

    def sprite(self, im, foot, anchor):
        x, y = OX + foot[0] - anchor[0], OY + foot[1] - anchor[1]
        self.img.alpha_composite(im, dest=(int(round(x / 2) * 2), int(round(y / 2) * 2)))

    def final(self):
        glow = np.asarray(self.emit.filter(ImageFilter.GaussianBlur(4))).astype(np.float32) * 0.9
        base = np.asarray(self.img.convert("RGB")).astype(np.float32)
        return Image.fromarray(np.clip(base + glow, 0, 255).astype(np.uint8), "RGB")


# ---------------------------------------------------------------- 运行时线状件（同 fx_pxplane_gl.gd）

def line(a, b):
    out, last = [], None
    n = int(math.ceil(max(abs(b[0] - a[0]), abs(b[1] - a[1])) / 2.0))
    for i in range(n + 1):
        k = i / max(1.0, n)
        q = (round((a[0] + (b[0] - a[0]) * k) / 2) * 2, round((a[1] + (b[1] - a[1]) * k) / 2) * 2)
        if q != last:
            out.append(q)
            last = q
    return out


def norm(v):
    L = math.hypot(*v)
    return (v[0] / L, v[1] / L) if L > 1e-6 else (1.0, 0.0)


def chain(cv, a, b, heavy, flash, s2):
    pts = line(a, b)
    dv = norm((b[0] - a[0], b[1] - a[1]))
    off = (round(-dv[1] * 2 / 2) * 2, round(dv[0] * 2 / 2) * 2)
    for i, q in enumerate(pts):
        c = CH[4] if flash else (CH[3] if i % 3 == 0 else CH[2])
        if s2 and not flash and i % 6 == 3:
            c = ACC
        cv.px(q, c)
        if heavy:
            cv.px((q[0] + off[0], q[1] + off[1]), CH[0] if not flash else CH[3])
    if flash and pts:
        cv.glow(pts[-1], CH[4])


def rot(v, a):
    return (v[0] * math.cos(a) - v[1] * math.sin(a), v[0] * math.sin(a) + v[1] * math.cos(a))


def head(cv, p, d, heavy):
    L, bl = (6, 4) if heavy else (4, 3)
    for s in range(L + 1):
        cv.px((p[0] - d[0] * s * 2, p[1] - d[1] * s * 2), C[7] if s == 0 else C[6])
    for sg in (-1, 1):
        bd = rot((-d[0], -d[1]), 0.62 * sg)
        for s in range(1, bl + 1):
            cv.px((p[0] + bd[0] * s * 2, p[1] + bd[1] * s * 2), C[5] if s < bl else C[4])
    cv.glow(p, C[7])


def wake(cv, it, t, e):
    if t < it["t0"]:
        return
    fr, cur = it["from"], e["pos"]
    L = math.hypot(cur[0] - fr[0], cur[1] - fr[1])
    if L < 4:
        return
    d = ((cur[0] - fr[0]) / L, (cur[1] - fr[1]) / L)
    nr = norm((-d[1], d[0] * SY))
    fade = min(1.0, max(0.0, (t - it["t1"]) / 0.45))
    sd = it["sd"]
    for j in range(int(L / 2)):
        back = j * 2.0
        q = (cur[0] - d[0] * back, cur[1] - d[1] * back + 2)
        w = min(10.0, 2.0 + back / 5.0)
        k = back / max(1.0, L)
        if h_(back * 0.37 + sd) > 0.25 + fade * 0.75:
            cv.px(q, C[1])
        for sg in (-1.0, 1.0):
            if h_(back * 1.3 + sd + sg * 7.0) > 0.35 + 0.4 * k + fade * 0.65:
                cv.px((q[0] + nr[0] * w * sg, q[1] + nr[1] * w * sg), C[7] if back < 8 and fade <= 0 else (C[6] if k < 0.5 else C[5]))


CYAN = hx("#6ec6d8")
PART_ZIP, PART_LIFE = 0.25, 0.7


def wave_col(cv, bp, out, u, H, tier, sd, tongue=True):
    rise = 1 - (1 - min(1.0, max(0.0, u / 0.1))) ** 3
    fall = min(1.0, max(0.0, (u - 0.45) / 0.25))
    curl = min(1.0, max(0.0, u / 0.3))
    hp = int(round(H * rise * (1 - fall)))
    if hp >= 1:
        for z in range(hp + 1):
            kz = z / max(1.0, hp)
            c = C[2] if kz < 0.3 else (C[4] if kz < 0.6 else (CYAN if kz < 0.85 else C[6]))
            if tier >= 2 and 0.25 < kz < 0.6 and h_(sd * 0.7 + z * 1.3) > 0.55:
                c = ACC2
            if 0.2 < kz < 0.8 and h_(sd * 0.3 + z * 0.9 + u * 15.0) > 0.86:
                c = C[5]
            lean = kz * kz * 4.0 * curl
            cv.px((bp[0] + out[0] * lean, bp[1] + out[1] * lean - 2 * z), c)
        if tongue and curl > 0.3 and u < 0.36:
            top = (bp[0] + out[0] * 4 * curl, bp[1] + out[1] * 4 * curl - 2 * hp)
            tl = (1 if abs(out[1]) > 0.7 else 2) + int(h_(sd) * 2.0)
            for q in range(tl):
                cv.px((top[0] + out[0] * 2 * (q + 1), top[1] + out[1] * 2 * (q + 1)), C[7])
            cv.px((top[0] + out[0] * 2 * tl, top[1] + out[1] * 2 * tl + 2), C[6])
            if h_(sd * 1.9 + math.floor(u * 15.0)) > 0.72:
                cv.glow((top[0] + out[0] * 2, top[1] + out[1] * 2), C[7])
                cv.px((top[0] + out[0] * 2, top[1] + out[1] * 2 - 2), C[7])
    if 0.32 < u < 0.62 and h_(sd * 0.57) > 0.4:
        v = u - 0.32
        dp = (bp[0] + out[0] * (8 + 70 * v), bp[1] + out[1] * (8 + 70 * v) - 2 * H * 0.85 - 40 * v + 420 * v * v)
        if dp[1] < bp[1]:
            cv.px(dp, ACC if tier >= 2 and h_(sd * 2.3) > 0.7 else C[6])
            if h_(sd * 3.1) > 0.5:
                cv.px((dp[0] + 2, dp[1]), C[5])


def part(cv, it, t):
    tier, a, d, L = it["tier"], it["a"], it["d"], it["L"]
    nr = norm((-d[1], d[0] * SY))
    hmax = [10.0, 13.0, 17.0][tier]
    s = it["s0"]
    while s < it["s1"]:
        u = t - it["t0"] - PART_ZIP * (s / max(1.0, L))
        if 0 <= u < PART_LIFE:
            taper = min(1.0, max(0.0, (s - 28) / 30)) * min(1.0, max(0.0, (L - 8 - s) / 24))
            for layer in range(2 if tier >= 2 else 1):
                lu = u - 0.06 * layer
                if lu < 0:
                    continue
                for sg in (-1.0, 1.0):
                    gv = vn(s / 14.0 + sg * 1.7 + layer * 3.1)
                    if gv < 0.3:
                        continue
                    hs = vn(s / 9.0 + sg * 3.0 + layer)
                    off = 14.0 + 8.0 * layer
                    bp = (a[0] + d[0] * s + nr[0] * sg * off * (1 + 0.12 * hs), a[1] + d[1] * s + nr[1] * sg * off * (1 + 0.12 * hs))
                    hl = hmax * (1 - 0.45 * layer)
                    wave_col(cv, bp, (nr[0] * sg, nr[1] * sg), lu, hl * (0.6 + 0.4 * hs) * (0.4 + 0.6 * taper) * min(1.0, max(0.3, (gv - 0.3) / 0.08)), tier, s + sg * 31.0 + layer * 7.0, gv > 0.36)
        s += 2.0


def trench(cv, it, t):
    u = t - it["t0"]
    gone = min(1.0, max(0.0, (u - 0.45) / 0.55))
    tier = it["tier"]
    a, d, L = it["a"], it["d"], it["L"]
    nr = norm((-d[1], d[0] * SY))
    w = 8.0 + 6.0 * (1 - (1 - min(1.0, max(0.0, u / 0.15))) ** 3) + 14.0 * min(1.0, max(0.0, (u - 0.5) / 0.45))
    s = 28.0
    while s < L - 8:
        base = (a[0] + d[0] * s, a[1] + d[1] * s + 2)
        if h_(s * 0.41) > 0.2 + 0.8 * gone:
            cv.px(base, C[0])
        for sg in (-1.0, 1.0):
            q = h_(s * 0.9 + sg * 5.0)
            if q > 0.3 + 0.7 * gone:
                c = C[5] if q > 0.6 else C[2]
                if tier >= 2 and h_(s * 1.7 + sg) > 0.9:
                    c = ACC
                cv.px((base[0] + nr[0] * sg * w, base[1] + nr[1] * sg * w), c)
            if tier >= 1 and h_(s * 1.3 + sg * 9.0) > 0.78 + 0.22 * gone:
                cv.px((base[0] + nr[0] * sg * (w + 3), base[1] + nr[1] * sg * (w + 3)), C[6])
        s += 2.0


def sunk(cv, a, c, gone):
    a = (a[0], a[1] + 2)
    c = (c[0], c[1] + 2)
    for i, q in enumerate(line(a, c)):
        hq = h_(i * 0.53 + a[0] * 0.01)
        if hq < gone:
            continue
        cv.px(q, CH[1] if i % 3 == 0 else CH[0])
        if hq > 0.86:
            cv.px((q[0], q[1] - 2), C[6])


# ---------------------------------------------------------------- 场景：按 15 fps 拍推进的小模拟（只为摆画面，数值同 gladiia.json）

class Scene:
    def __init__(self, lib, tier, enemies, n):
        self.lib, self.tier, self.n = lib, tier, n
        self.en = [{"pos": tuple(p), "r": 14.0, "id": i} for i, p in enumerate(enemies)]
        self.items = []      # 帧条件 {k, tk0, gp, ly, flip, sk, loop}
        self.rt = []         # 运行时件
        self.hooks = []      # {from, to, tgt, heavy, tk0}
        self.state = []      # 状态件 (函数: tk -> list)
        self.events = []     # (tk, 函数)
        self.s2 = None       # (tk0, tk1)
        self.ops = (0.0, 0.0)

    def T(self, tk):
        return tk / 15.0

    def add(self, k, tk, gp, ly, flip=False, sk=0.0, loop=False):
        self.items.append({"k": "gl_" + k, "tk": tk, "gp": gp, "ly": ly, "flip": flip, "sk": sk, "loop": loop})

    def ring3(self, k, tk, gp, ra):
        dz = ra * 2 * SY
        self.add(k + "_up", tk, gp, "up", sk=dz)
        self.add(k + "_gd", tk, gp, "gd")

    def pair(self, k, tk, gp):
        self.add(k + "_up", tk, gp, "up")
        self.add(k + "_gd", tk, gp, "gd")

    def hook(self, tk, tgt_i, heavy=False, n_drag=2, front=110.0, ra=None):
        """掷钩：飞 → 落地（水刺 + 拖痕起点）→ 绷紧 → 拖 → 到位；返回到位拍"""
        hand = (33.0, -33.0)
        tgt = self.en[tgt_i]
        to = tgt["pos"]
        dist = math.hypot(to[0] - hand[0], to[1] - hand[1])
        fly = min(0.24, max(0.1, dist / 900.0))
        t0 = self.T(tk)
        hk = {"from": hand, "to": to, "heavy": heavy, "t0": t0, "fly": fly, "taut": 0.12, "drag": 0.22, "dr": []}
        self.hooks.append(hk)
        t_imp = t0 + fly
        tk_imp = int(math.floor(t_imp * 15.0))
        ra = ra or (70.0 if heavy else 77.0) * 0.5
        if heavy:
            self.pair("s1hit_r%d_e%d" % (bucket(ra, S1_R), self.tier), tk_imp, to)
            self.parting(tk_imp, (0.0, 0.0), to)
        else:
            self.pair("hit_r%d_e%d" % (bucket(ra, HIT_R), self.tier), tk_imp, to)
        hk["tk_imp"] = tk_imp
        # 拖：一线上至多 n_drag 名（这里取目标 + 离线最近的一名）
        a = (0.0, 0.0)
        L = math.hypot(*to)
        d = (to[0] / L, to[1] / L)
        fr = (d[0] * front, d[1] * front)
        cands = sorted([e for e in self.en if e is tgt or self._on_line(e, d, L)], key=lambda e: math.hypot(*e["pos"]))
        got = [e for e in cands if math.hypot(*e["pos"]) > front][:n_drag]
        t_drag = t_imp + 0.12
        for i, e in enumerate(got):
            side = (1.0 if i % 2 == 1 else -1.0) * math.ceil(i / 2.0)
            spot = (fr[0] + d[0] * 7 + -d[1] * side * 14 + d[0] * abs(side) * 6, fr[1] + d[1] * 7 + d[0] * side * 14 + d[1] * abs(side) * 6)
            hk["dr"].append({"e": e, "from": None, "spot": spot})
            self.rt.append({"kind": "wake", "e": e, "from": None, "t0": t_drag, "t1": t_drag + 0.22, "sd": e["id"] * 0.37, "life": 0.22 + 0.45})
        hk["t_drag"] = t_drag
        hk["front"] = fr
        hk["t_arr"] = t_drag + 0.22
        tk_arr = int(math.floor(hk["t_arr"] * 15.0))
        for e in got[:3]:
            self.events.append((tk_arr, lambda e=e, heavy=heavy: self.pair(("s1arr_e%d" if heavy else "arr_e%d") % self.tier, tk_arr, e["pos"])))
        return tk_arr, fr

    def _on_line(self, e, d, L):
        p = e["pos"]
        s = p[0] * d[0] + p[1] * d[1]
        off = abs(p[0] * -d[1] + p[1] * d[0])
        return 0 <= s <= L and off <= 52 + e["r"]

    def parting(self, tk, a, c):
        L = math.hypot(c[0] - a[0], c[1] - a[1])
        d = ((c[0] - a[0]) / L, (c[1] - a[1]) / L)
        s = 28.0
        while s < L - 8:
            s1 = min(L - 8, s + 32)
            mid = (a[0] + d[0] * (s + s1) / 2, a[1] + d[1] * (s + s1) / 2)
            self.rt.append({"kind": "part", "a": a, "d": d, "s0": s, "s1": s1, "L": L, "tier": self.tier, "t0": tk / 15.0, "life": PART_ZIP + PART_LIFE, "gy": mid[1] + 1})
            s = s1
        self.rt.append({"kind": "trench", "a": a, "d": d, "L": L, "tier": self.tier, "t0": tk / 15.0, "life": 1.0})

    def step_enemies(self, t):
        for hk in self.hooks:
            for dg in hk["dr"]:
                if t >= hk["t_drag"] and dg["from"] is None:
                    dg["from"] = dg["e"]["pos"]
                    for w in self.rt:
                        if w["kind"] == "wake" and w["e"] is dg["e"] and w["from"] is None:
                            w["from"] = dg["from"]
                if dg["from"] is not None and t <= hk["t_arr"] + 0.001:
                    k = min(1.0, max(0.0, (t - hk["t_drag"]) / 0.22))
                    kr = 1 - (1 - k) * (1 - k)
                    dg["e"]["pos"] = (dg["from"][0] + (dg["spot"][0] - dg["from"][0]) * kr, dg["from"][1] + (dg["spot"][1] - dg["from"][1]) * kr)

    def hook_head(self, hk, t):
        """链头位置与阶段（同 _hw5_hooks）"""
        if t < hk["t0"] or t > hk["t_arr"]:
            return None
        if t < hk["t0"] + hk["fly"]:
            k = (t - hk["t0"]) / hk["fly"]
            p = (hk["from"][0] + (hk["to"][0] - hk["from"][0]) * k, hk["from"][1] + (hk["to"][1] - hk["from"][1]) * k - math.sin(k * math.pi) * 24)
            return p, "fly"
        if t < hk["t_drag"]:
            return hk["to"], "taut"
        k = min(1.0, (t - hk["t_drag"]) / 0.22)
        kr = 1 - (1 - k) * (1 - k)
        return (hk["to"][0] + (hk["front"][0] - hk["to"][0]) * kr, hk["to"][1] + (hk["front"][1] - hk["to"][1]) * kr), "drag"


ENEMY = None
OPSPR = None


def render(sc, tk):
    t = tk / 15.0
    lib = sc.lib
    sc.step_enemies(t)
    for (etk, fn) in list(sc.events):
        if etk == tk:
            fn()
    cv = Canvas()
    sortables = []
    # 状态件 / 地面层
    for st in sc.state:
        for (k, gp, ly, fi, loop, sk) in st(tk):
            if ly == "gd":
                cv.strip(lib, k, fi, gp, False, loop)
            else:
                sortables.append((OY + gp[1] + 1 + sk, "strip", (k, fi, gp, False, loop)))
    for it in sc.items:
        if tk < it["tk"]:
            continue
        if it["ly"] == "gd":
            cv.strip(lib, it["k"], tk - it["tk"], it["gp"], it["flip"])
        else:
            sortables.append((OY + it["gp"][1] + 1 + it["sk"], "strip", (it["k"], tk - it["tk"], it["gp"], it["flip"], False)))
    for it in sc.rt:
        if t < it["t0"] or t > it["t0"] + it["life"] + 0.02:
            continue
        if it["kind"] == "wake" and it["from"] is not None:
            wake(cv, it, t, it["e"])
        elif it["kind"] == "trench":
            trench(cv, it, t)
        elif it["kind"] == "sunk":
            sunk(cv, it["a"], it["c"], it["gone"](t))
        elif it["kind"] == "part":
            sortables.append((OY + it["gy"], "part", it))
    for e in sc.en:
        sortables.append((OY + e["pos"][1], "enemy", e))
    sortables.append((OY + 0.0, "op", None))
    sortables.sort(key=lambda s: s[0])
    for _, kind, v in sortables:
        if kind == "enemy":
            cv.sprite(ENEMY, v["pos"], (ENEMY.width // 2, ENEMY.height - 6))
        elif kind == "part":
            part(cv, v, t)
        elif kind == "op":
            cv.sprite(OPSPR, (0, 0), (64, 120))
        else:
            k, fi, gp, fl, loop = v
            cv.strip(lib, k, fi, gp, fl, loop)
    # 上层：链 + 钩头
    s2 = sc.s2 is not None and sc.s2[0] <= tk < sc.s2[1]
    for hk in sc.hooks:
        r = sc.hook_head(hk, t)
        if r is None:
            continue
        p, ph = r
        p = (p[0], p[1] - 6)
        flash = ph == "taut" and tk == hk["tk_imp"]
        if ph == "taut" and tk == hk["tk_imp"] + 0:
            flash = True
        chain(cv, hk["from"], p, hk["heavy"], flash, s2)
        if ph == "drag":
            for dg in hk["dr"]:
                e = dg["e"]
                chain(cv, p, (e["pos"][0], e["pos"][1] - 7), False, False, s2)
        dv = norm((hk["to"][0] - hk["from"][0], hk["to"][1] - hk["from"][1]))
        head(cv, p, (-dv[0], -dv[1]) if ph == "drag" else dv, hk["heavy"])
    for lc in getattr(sc, "lchains", []):
        lc(cv, t)
    return cv.final()


def gif(columns, n_ticks, path, title, zoom_c, note=""):
    font = ImageFont.truetype(FONT, 15)
    sfont = ImageFont.truetype(FONT, 12)
    head_h = 28
    frames = []
    for tk in range(n_ticks):
        sheet = Image.new("RGB", (W * len(columns) + 4 * (len(columns) - 1), head_h + H + 4 + H + 18), (14, 16, 18))
        d = ImageDraw.Draw(sheet)
        for ci, (lab, sc) in enumerate(columns):
            x0 = ci * (W + 4)
            im = render(sc, tk)
            sheet.paste(im, (x0, head_h))
            zx, zy = OX + zoom_c[0], OY + zoom_c[1]
            crop = im.crop((int(zx - W / 4), int(zy - H / 4), int(zx + W / 4), int(zy + H / 4))).resize((W, H), Image.NEAREST)
            sheet.paste(crop, (x0, head_h + H + 4))
            d.text((x0 + 6, 5), lab, fill=(235, 225, 200), font=font)
            d.text((x0 + 6, head_h + H + 4 + H + 2), "上：1 倍（实机大小）  下：2 倍放大" + note, fill=(140, 140, 140), font=sfont)
        d.text((sheet.width - 6 - d.textlength(title, font=sfont), 8), title, fill=(150, 150, 150), font=sfont)
        frames.append(sheet)
    pal = frames[len(frames) // 2].quantize(colors=255, method=Image.MEDIANCUT)
    q = [f.quantize(palette=pal, dither=Image.NONE) for f in frames]
    dur = [70 if i % 3 != 1 else 60 for i in range(len(q))]
    q[0].save(path, save_all=True, append_images=q[1:], duration=dur, loop=0, optimize=False, disposal=1)
    print(path, len(q), "帧")


# ---------------------------------------------------------------- 每招的摆法

PACK = [(196, -26), (232, 8), (178, 30), (250, -40), (214, 44), (150, -8)]


def sc_atk(lib, el, late=False):
    sc = Scene(lib, el, PACK, 36)
    tk_arr, fr = sc.hook(2, 3)
    if el >= 2:   # 精二「冲撞」：到位那一刻身前一圈往外走的碎浪（ram_delay 0.5 秒 ≈ 到位）
        sc.ring3("ram", tk_arr, fr, 40)
    tk_arr2, fr2 = sc.hook(19, 1)
    if el >= 2:
        sc.ring3("ram", tk_arr2, fr2, 40)
    if late:   # late_shape「扩散」：被钩中的那只身边一圈小浪
        for hk in sc.hooks:
            sc.ring3("splash", hk["tk_imp"], hk["to"], 30)
    return sc


def sc_late(lib, el):
    sc = Scene(lib, el, PACK, 36)
    # 后期范围成长（late_shape 控场 +25% / 档、范围卡）：判定半径变大，落地件挑大一档（52 / 66）；每次落地带「扩散」小浪
    for tk0, ti, ra in ((2, 3, 52), (19, 1, 66)):
        tk_arr, fr = sc.hook(tk0, ti, ra=ra)
        hk = sc.hooks[-1]
        sc.ring3("splash", hk["tk_imp"], hk["to"], 30)
        if el >= 2:
            sc.ring3("ram", tk_arr, fr, 40)
    return sc


def sc_s1(lib, el):
    sc = Scene(lib, el, PACK, 34)
    sc.hook(2, 3, heavy=True)
    return sc


def sc_s2(lib, el):
    sc = Scene(lib, el, PACK, 36)
    sc.s2 = (1, 999)
    sc.add("s2cast_e%d_bk" % el, 1, (0.0, 0.0), "up", sk=-66.0)
    sc.add("s2cast_e%d_up" % el, 1, (0.0, 0.0), "up")
    sc.add("s2cast_e%d_gd" % el, 1, (0.0, 0.0), "gd")
    sc.state.append(lambda tk, el=el: [("gl_s2aura_e%d_gd" % el, (0.0, 2.0), "gd", tk, True, 0.0)] if tk >= 1 else [])
    for tk0, ti in ((12, 3), (29, 1)):
        sc.hook(tk0, ti)
        sc.ring3("s2pull_e%d" % el, tk0, (0.0, 0.0), 80)
    return sc


def sc_s3(lib):
    c = (190.0, -6.0)
    ens = [(c[0] + 52 * math.cos(a), c[1] + 52 * math.sin(a) * SY) for a in (0.3, 1.5, 2.6, 3.9, 5.1)] + [(120.0, 40.0)]
    sc = Scene(lib, 2, ens, 46)
    open_tk, close_tk = 2, 36
    base = [tuple(e["pos"]) for e in sc.en]

    def st(tk):
        out = []
        if open_tk <= tk < close_tk:
            age = tk - open_tk
            dz = 65 * 2 * SY
            if age < 5:
                out += [("gl_s3open_gd", c, "gd", age, False, 0.0), ("gl_s3open_bk", c, "up", age, False, -dz), ("gl_s3open_up", c, "up", age, False, dz)]
            else:
                out += [("gl_s3loop_gd", c, "gd", tk, True, 0.0), ("gl_s3loop_bk", c, "up", tk, True, -dz), ("gl_s3loop_up", c, "up", tk, True, dz)]
        return out
    sc.state.append(st)
    for k in range(1, 4):   # 每 0.75 秒一跳
        sc.add("s3tick_gd", open_tk + int(11.25 * k), c, "gd")
    dz = 65 * 2 * SY
    sc.add("s3close_bk", close_tk, c, "up", sk=-dz)
    sc.add("s3close_up", close_tk, c, "up", sk=dz)
    sc.add("s3close_gd", close_tk, c, "gd")

    def pull(tk):   # 涡内的怪每跳往中心拉 22，收尾拽 60（画面上按拍缓动）
        for i, e in enumerate(sc.en[:5]):
            b = base[i]
            jumps = sum(1 for k in range(1, 4) if tk >= open_tk + int(11.25 * k))
            dist = 22 * jumps + (60 if tk >= close_tk else 0)
            L = math.hypot(b[0] - c[0], b[1] - c[1])
            kk = min(0.85, dist / max(1.0, L))
            e["pos"] = (b[0] + (c[0] - b[0]) * kk, b[1] + (c[1] - b[1]) * kk)
    sc.events += [(tk, (lambda tk=tk: pull(tk))) for tk in range(46)]
    return sc


def sc_link(lib):
    c = (150.0, 0.0)
    r = 150.0
    ens = [(c[0] + 200 * math.cos(a), c[1] + 200 * math.sin(a) * SY) for a in (-0.9, -0.2, 0.5, 1.2)]
    sc = Scene(lib, 1, ens, 30)
    t0 = 3
    sc.lchains = []
    starts = [tuple(e["pos"]) for e in sc.en]

    def mv(tk):
        t = (tk - t0) / 15.0
        for i, e in enumerate(sc.en):
            b = starts[i]
            to = (c[0] + (b[0] - c[0]) / math.hypot(b[0] - c[0], b[1] - c[1]) * r * 0.45, c[1] + (b[1] - c[1]) / math.hypot(b[0] - c[0], b[1] - c[1]) * r * 0.45)
            k = min(1.0, max(0.0, (t - 0.14) / 0.36))
            kk = 1 - (1 - 0.22) ** (k * 22)   # nudge 每帧 22%（约 60 帧 / 秒 × 0.36 秒）
            e["pos"] = (b[0] + (to[0] - b[0]) * kk, b[1] + (to[1] - b[1]) * kk)
    sc.events += [(tk, (lambda tk=tk: mv(tk))) for tk in range(30)]
    for i, e in enumerate(sc.en):
        sc.rt.append({"kind": "wake", "e": e, "from": starts[i], "t0": (t0 / 15.0) + 0.14, "t1": t0 / 15.0 + 0.5, "sd": i * 0.37, "life": 0.95})
    land_tk = t0 + int(round(0.5 * 15))
    sc.ring3("link", land_tk, c, 75)

    def lchain(cv, t):
        u = t - t0 / 15.0
        if u < 0 or u > 1.0:
            return
        hand = (0.0, -20.0)
        for e in sc.en:
            tgt = (e["pos"][0], e["pos"][1] - 7)
            k = min(1.0, max(0.0, u / 0.14))
            tip = (hand[0] + (tgt[0] - hand[0]) * k, hand[1] + (tgt[1] - hand[1]) * k)
            if u < 0.5:
                chain(cv, hand, tip, False, 0.14 <= u < 0.2, False)
                dd = norm((tgt[0] - hand[0], tgt[1] - hand[1]))
                head(cv, tip, dd if u < 0.14 else (-dd[0], -dd[1]), False)
            else:
                gone = min(1.0, (u - 0.5) / 0.5)
                for i, q in enumerate(line(hand, tgt)):
                    if h_(i * 0.61 + e["id"]) > gone:
                        cv.px(q, CH[2] if i % 3 else CH[1])
    sc.lchains.append(lchain)
    return sc


def sc_nodes(lib, which):
    sc = Scene(lib, 1, PACK[:4], 30)
    if which == "slash":   # 回收斩：到位同帧前方扇形横扫（挂在人身上）
        tk_arr, fr = sc.hook(2, 3)
        d, fl = pick_dir(math.atan2(-26, 196))
        sc.add("slash_up_d%d" % d, tk_arr, (0.0, 0.0), "up", flip=fl)
        sc.add("slash_gd_d%d" % d, tk_arr, (0.0, 0.0), "gd", flip=fl)
    elif which == "chain":   # 怒海：锁链沉底 2 秒；怒海·暗涌：到期沿钩线每 40 冒一柱
        tk_arr, fr = sc.hook(2, 3)
        a, cpt = (0.0, 0.0), (250.0, -40.0)
        t_arr = tk_arr / 15.0
        sc.rt.append({"kind": "sunk", "a": (0.0, 0.0), "c": (fr[0], fr[1]), "t0": t_arr, "life": 0.9, "gone": lambda t, t_arr=t_arr: min(1.0, max(0.0, 1 - (t_arr + 0.9 - t) / 0.4))})
        L = math.hypot(*fr)
        d = (fr[0] / L, fr[1] / L)
        for i in range(1, int(L // 40) + 1):
            sc.pair("geyser", tk_arr + 13 + i, (d[0] * 40 * i, d[1] * 40 * i))
    elif which == "pop":   # 深海的庇护·反震：护盾破裂时队长处一圈水波
        sc.ring3("pop", 3, (0.0, 0.0), 60)
    return sc


def main():
    global ENEMY, OPSPR
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    ap.add_argument("--out", default=os.path.join(MAIN, "Claude outputs", "pxplane_gladiia_1105", "gif"))
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    lib = Lib()
    im = Image.open(os.path.join(ROOT, "game", "art", "enemies", "offspring", "e_offspring@2x.png")).convert("RGBA")
    en = im.crop((0, 0, im.width // 4, im.height))
    arr = np.asarray(en).astype(np.float32)
    arr[..., :3] = arr[..., :3] * 0.32 + np.array([10, 12, 14])
    ENEMY = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")
    op = Image.open(os.path.join(ROOT, "game", "art", "operators", "gladiia", "op_gladiia_idle@2x.png")).convert("RGBA")
    OPSPR = op.crop((0, 0, op.width // 8, op.height))
    title = "歌蕾蒂娅 · 转平面 · 15 fps 原速"
    jobs = {
        "atk": lambda: gif([("普攻「钩索」 精英 %d" % el + ("（锚定）" if el == 1 else "（冲撞）" if el == 2 else ""), sc_atk(lib, el)) for el in (0, 1, 2)], 36, os.path.join(a.out, "gladiia_atk.gif"), title, (150, -10)),
        "s1": lambda: gif([("S1「缺水的大洋裂断」 精英 %d" % el, sc_s1(lib, el)) for el in (0, 1, 2)], 34, os.path.join(a.out, "gladiia_s1.gif"), title, (130, -14)),
        "s2": lambda: gif([("S2「缺水的掌握怒海」 精英 %d" % el, sc_s2(lib, el)) for el in (1, 2)], 36, os.path.join(a.out, "gladiia_s2.gif"), title, (40, -20)),
        "s3": lambda: gif([("S3「缺水的碎漩狂舞」 精英 2（起 → 每跳 → 收）", sc_s3(lib))], 46, os.path.join(a.out, "gladiia_s3.gif"), title, (190, -36)),
        "link": lambda: gif([("连携技「聚拢」（技能连携 v2 缺省版）", sc_link(lib))], 30, os.path.join(a.out, "gladiia_link.gif"), title, (150, -10)),
        "late": lambda: gif([("后期额外攻击：范围成长 + 「扩散」 精英 %d" % el, sc_late(lib, el)) for el in (0, 1, 2)], 36, os.path.join(a.out, "gladiia_late.gif"), title, (190, -10)),
        "nodes": lambda: gif([("成长节点「回收斩」", sc_nodes(lib, "slash")), ("「怒海」锁链 → 「暗涌」水柱", sc_nodes(lib, "chain")), ("「深海的庇护·反震」", sc_nodes(lib, "pop"))], 30, os.path.join(a.out, "gladiia_nodes.gif"), title, (90, -10)),
    }
    only = set(x for x in a.only.split(",") if x)
    for k, fn in jobs.items():
        if not only or k in only:
            fn()


if __name__ == "__main__":
    main()
