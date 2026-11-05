#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""铃兰转平面（docs/271）送审 GIF：上 GCP 前先给用户看，只用 Python、不开 Godot。

帧条直接读 tools/pxplane_bake_suzuran.py 烤出的 game/art/fx/pxp/pxp_sz_*.png + game/data/pxp_suzuran.json（与游戏同一份）；
狐火弹、光域边、传火线、连携追迹用 tools/pxplane_suzuran_art.py 里与 fx_pxplane_sz.gd 同算法的 Python 版逐格画。
摆法照游戏（seg_suzuran.gd）：每 1 秒一次普攻、狐火 330 / 秒追踪（转向 7）、从杖头 (34, −42) 发出、命中溅射 26；
光域半径 (85 + 15 × 精英) × (1 / 1.6 暖光 / 2.2 狐火渺然)；围炉狐火在 0.55 椭圆上绕；狐火渺然每 0.9 秒一处落点。
每招一张：E0 / E1 / E2 左右并排（只放实际存在的档）；上半 1 倍（实机大小：1 美术像素 = 2 屏幕像素）、下半 2 倍放大；15 fps 原速循环。
光照近似：整体压暗到 AMBIENT，命中 / 爆点挂一盏短照地光；热芯（emit 点）近似发光层加一层柔光。Noita 颗粒不画（游戏里另有）。

用法：python tools/pxplane_gif_suzuran.py [--only atk,s1] [--out 目录]
"""
import argparse, json, math, os, sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pxplane_suzuran_art as A

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAIN = os.path.dirname(os.path.dirname(os.path.dirname(ROOT))) if ".claude" in ROOT else ROOT
PX = 2
GROUND = (36, 46, 48)
DIRS = [-90, -45, 0, 45, 90]
FONT = "C:/Windows/Fonts/msyh.ttc"
AMBIENT = 0.8
FOX_L = (0.94, 0.85, 0.63)   # 米金照地光（同 data/fx_pxplane/suzuran.json light #f0d8a0）
HEAL_L = (0.6, 1.0, 0.75)


def pick_dir(ang_deg):
    a = (ang_deg + 180) % 360 - 180
    flip = False
    if abs(a) > 90:
        a = (180 - a + 180) % 360 - 180
        flip = True
    best = 0
    for d in DIRS:
        if abs(a - d) < abs(a - best):
            best = d
    return best, flip


def snap(v):
    return (round(v[0] / 2) * 2, round(v[1] / 2) * 2)


def fit(arr, v):
    best = arr[0]
    for x in arr:
        if x <= v * 1.1 and x > best:
            best = x
    return best


class Lib:
    def __init__(self):
        self.meta = {k: v for k, v in json.load(open(os.path.join(ROOT, "game", "data", "pxp_suzuran.json"), encoding="utf-8")).items() if k != "_doc"}
        self.tex = {}

    def frame(self, k, fi, loop=False):
        m = self.meta[k]
        n = m["n"]
        if loop:
            fi %= n
        if fi < 0 or fi >= n:
            return None
        if k not in self.tex:
            self.tex[k] = Image.open(os.path.join(ROOT, "game", "art", "fx", "pxp", "pxp_sz_%s.png" % k.replace("_d-", "_dm").lower())).convert("RGBA")
        w, h = m["w"], m["h"]
        return self.tex[k].crop((fi * w, 0, (fi + 1) * w, h)), m


def sprite(path, n):
    im = Image.open(path).convert("RGBA")
    fw = im.width // n
    return im.crop((0, 0, fw, im.height))


class Col:
    """一栏的时间轴（拍 = 1/15 秒），坐标一律世界像素"""

    def __init__(self, tier, enemies, op=(120, 150), lead=None, size=(420, 260)):
        self.t = tier
        self.W, self.H = size
        self.items = []
        self.enemies = [[float(x), float(y), 10 ** 9] for x, y in enemies]
        self.op = op
        self.face = 1
        self.lead = lead
        self.lights = []
        self.rt = {}          # 拍 → [(排序 y, 种类, 数据)]
        self.aura = None      # (起拍, 止拍, 半径（美术像素）, mode) 列表
        self.auras = []
        self.brands = []      # (敌人, 起拍, 止拍)
        self.seals = []
        self.wisps = 2
        self.tails = tier >= 2
        self.hearth = None    # (起拍, 止拍, 半径世界像素)
        self.edge = []        # (起拍, 止拍, n, 小 / 中)
        self.beat = {}
        self.conv = {}        # 拍 → 汇聚度（三火归一）

    def lp(self):
        return self.lead or self.op

    def add(self, k, tk, gp, gd=False, gy=None, loop=False, until=None, flip=False):
        self.items.append({"k": k, "t0": tk, "gp": snap(gp), "flip": flip, "gd": gd, "gy": gp[1] if gy is None else gy, "loop": loop, "until": until})

    def light(self, at, r, i, tk, n=2, col=FOX_L):
        self.lights.append((at[0], at[1] + 6, r, i, tk, n, col))

    def put_rt(self, tk, y, kind, data):
        self.rt.setdefault(tk, []).append((y, kind, data))

    def tip(self):
        return (self.op[0] + 34 * self.face, self.op[1] - 42)

    def pop(self, tk, ei, stamp=False):
        e = self.enemies[ei]
        self.add("hit_up", tk, (e[0], e[1]), gy=e[1] + 1)
        self.add("hit_gd", tk, (e[0], e[1]), gd=True)
        if stamp:
            self.add("stamp_gd", tk, (e[0], e[1]), gd=True)
        self.light((e[0], e[1] - 12), 90, 0.62 if stamp else 0.5, tk)

    def bolts(self, tk, n, targets, big=False, brand=False, seal=False):
        """一次普攻：n 团狐火（同 seg_suzuran：朝目标偏 ±0.6 rad 发出，追踪转向 7 rad/秒），命中炸开；返回各发命中的拍"""
        tp = self.tip()
        hits = []
        for k in range(n):
            ei = targets[k % len(targets)]
            e = self.enemies[ei]
            d0 = math.atan2(e[1] - self.op[1], e[0] - self.op[0]) + 0.6 * (1 if k % 2 == 0 else -1) * (1.0 + 0.3 * (k // 2))
            p = [tp[0], tp[1]]
            v = [math.cos(d0) * 330, math.sin(d0) * 330]
            t = 0.0
            dt = 1 / 60.0
            hit_t = None
            seen = {}
            while t < 1.6:
                want = math.atan2(e[1] - p[1], e[0] - p[0])
                cur = math.atan2(v[1], v[0])
                da = (want - cur + math.pi) % math.tau - math.pi
                da = max(-7 * dt, min(7 * dt, da))
                cur += da
                v = [math.cos(cur) * 330, math.sin(cur) * 330]
                p = [p[0] + v[0] * dt, p[1] + v[1] * dt]
                t += dt
                ftk = tk + int(t * 15)
                if math.hypot(e[0] - p[0], e[1] - p[1]) < 7 + 10:
                    hit_t = ftk
                    break
                seen[ftk] = (tuple(p), (v[0] / 330, v[1] / 330))
            for ftk, (pp, vv) in seen.items():
                if hit_t is None or ftk < hit_t:
                    if big:   # 全力以赴：出手 0.3 秒内沿各自出射方向多推 22（扇形错开，同 fx_pxplane_sz._bolt_pos）
                        kk = max(0.0, 1.0 - (ftk - tk) / 15.0 / 0.3)
                        pp = (pp[0] + math.cos(d0) * 22 * kk, pp[1] + math.sin(d0) * 22 * kk)
                    self.put_rt(ftk, pp[1] + 4, "bolt", (pp, vv, big))
            if hit_t is not None:
                self.pop(hit_t, ei, stamp=big)
                if brand:
                    self.brands.append((ei, hit_t, hit_t + 30))
                if seal:
                    self.seals.append((ei, hit_t, hit_t + 8))
                hits.append(hit_t)
        return hits

    def bigfox(self, tk, ei, trail=False, splash=False):
        """三火归一：大狐火从杖头朝目标直线 340 / 秒贯穿；路上的敌人各炸一下；trail = 精二拖尾火苗"""
        tp = self.tip()
        e = self.enemies[ei]
        d = (e[0] - tp[0], e[1] - 8 - tp[1])
        L = math.hypot(*d)
        d = (d[0] / L, d[1] / L)
        dk, fl = pick_dir(math.degrees(math.atan2(d[1], d[0])))
        self.light(tp, 120, 0.6, tk)
        done = set()
        last = None
        for f in range(int(1.3 * 15)):
            p = (tp[0] + d[0] * 340 * f / 15, tp[1] + d[1] * 340 * f / 15)
            if not (0 < p[0] < self.W and 0 < p[1] < self.H):
                break
            self.put_rt(tk + f, p[1] + 8, "strip", ("bigfox_d%d" % dk, snap(p), fl, f))
            for j, q in enumerate(self.enemies):
                if j in done or q[2] <= tk + f:
                    continue
                if math.hypot(q[0] - p[0], q[1] - p[1]) < 14 + 10:
                    done.add(j)
                    self.pop(tk + f, j)
                    if splash:
                        self.add("splash_gd", tk + f, (q[0], q[1]), gd=True)
                        self.light((q[0], q[1] - 8), 80, 0.4, tk + f)
            if trail and (last is None or math.hypot(p[0] - last[0], p[1] - last[1]) >= 22):
                last = p
                for ff in range(15):
                    u = ff / 15
                    lv = 0 if u < 0.4 else (1 if u < 0.75 else 2)
                    self.put_rt(tk + f + ff, p[1] + 6, "tuft", (snap((p[0], p[1] + 6)), lv * 4 + (tk + f + ff) % 4))


# ---------------------------------------------------------------- 绘制

def render(lib, col, tk):
    W, H = col.W, col.H
    img = Image.new("RGBA", (W, H), GROUND + (255,))
    rng = np.random.default_rng(7)
    g = np.asarray(img).copy()
    nz = rng.integers(-5, 6, size=(H // 2, W // 2, 1))
    g[..., :3] = np.clip(g[..., :3].astype(int) + np.repeat(np.repeat(nz, 2, 0), 2, 1), 0, 255)
    img = Image.fromarray(g.astype(np.uint8), "RGBA")
    emit = Image.new("RGB", (W, H), (0, 0, 0))
    ed = ImageDraw.Draw(emit)
    dr = ImageDraw.Draw(img)

    def put_px(x, y, c, glow=False, a=1.0):
        x, y = snap((x, y))
        cc = A.hx(c) if isinstance(c, str) else c
        if a < 1.0:
            base = img.getpixel((min(W - 1, max(0, x)), min(H - 1, max(0, y))))
            cc = tuple(int(base[i] * (1 - a) + cc[i] * a) for i in range(3)) + (255,)
        dr.rectangle([x, y, x + PX - 1, y + PX - 1], fill=cc)
        if glow:
            ed.rectangle([x, y, x + PX - 1, y + PX - 1], fill=cc[:3])

    def strip(k, fi, gp, flip=False, loop=False, alpha=None):
        r = lib.frame(k, fi, loop)
        if r is None:
            return
        fr, m = r
        fi2 = fi % m["n"] if loop else fi
        if flip:
            fr = fr.transpose(Image.FLIP_LEFT_RIGHT)
        gx, gy = gp
        left = gx - (m["w"] - m["ox"]) * PX if flip else gx - m["ox"] * PX
        top = gy - m["oy"] * PX
        big = fr.resize((fr.width * PX, fr.height * PX), Image.NEAREST)
        if alpha is not None:
            a = np.asarray(big).copy()
            a[..., 3] = (a[..., 3] * alpha).astype(np.uint8)
            big = Image.fromarray(a, "RGBA")
        l, t = int(left), int(top)
        if l >= W or t >= H or l + big.width <= 0 or t + big.height <= 0:
            return
        img.alpha_composite(big, dest=(max(0, l), max(0, t)), source=(max(0, -l), max(0, -t)))
        if alpha is None or alpha > 0.5:
            for q in m["emit"][fi2]:
                x = q[0] if not flip else m["w"] - 1 - q[0]
                ed.rectangle([l + x * PX, t + q[1] * PX, l + x * PX + PX - 1, t + q[1] * PX + PX - 1], fill=tuple(int(q[2][i:i + 2], 16) for i in (0, 2, 4)))

    def on(it):
        return tk >= it["t0"] and (it["until"] is None or tk < it["until"])

    # 地面层：光域边
    for (a0, a1, R, mode) in col.auras:
        if a0 <= tk < a1:
            c0 = snap((col.op[0], col.op[1] + 4))
            for (x, y, c) in A.aura_ring(R, tk, mode):
                put_px(c0[0] + x * PX, c0[1] + y * PX, c)
    for (ei, a0, a1) in col.brands:
        e = col.enemies[ei]
        if a0 <= tk < a1 and tk < e[2]:
            strip("brand_gd", tk + ei, snap((e[0], e[1] + 7)), loop=True, alpha=min(1.0, (a1 - tk) / 4.5))
    for (ei, a0, a1) in col.seals:
        e = col.enemies[ei]
        if a0 <= tk < a1:
            strip("seal_gd", tk, snap((e[0], e[1] + 4)), loop=True, alpha=min(1.0, (a1 - tk) / 2.25))
    for it in col.items:
        if it["gd"] and on(it):
            strip(it["k"], tk - it["t0"] if not it["loop"] else tk, it["gp"], it["flip"], it["loop"])

    # 排序层
    sort = []
    for e in col.enemies:
        if tk < e[2]:
            sort.append((e[1], "e", e))
    sort.append((col.op[1], "op", None))
    if col.lead:
        sort.append((col.lead[1], "lead", None))
    flare = any(it["k"] == "tails_flare" and on(it) and tk - it["t0"] < lib.meta["tails_flare"]["n"] for it in col.items)
    if col.tails and not flare:
        sort.append((col.op[1] - 2, "raw", ("tails", tk, snap(col.op), col.face < 0, True)))
    conv = col.conv.get(tk, 0.0)
    tp = col.tip()
    nw = 0 if col.t >= 2 else col.wisps   # 精二只留九尾常驻
    for k in range(nw):
        an = tk / 15.0 * 1.6 + k * math.tau / col.wisps
        gy = col.op[1] + math.sin(an) * 13
        pp = (col.op[0] + math.cos(an) * 40, col.op[1] - 22 + math.sin(an) * 13)
        if k < 3 and conv > 0:
            if conv > 0.85:
                continue
            pp = (pp[0] + (tp[0] - pp[0]) * conv * conv, pp[1] + (tp[1] - pp[1]) * conv * conv)
        sort.append((gy + 1, "raw", ("fl_s", tk + k, snap((pp[0], pp[1] + 4)), False, True)))
    if conv > (0.2 if nw == 0 else 0.5):
        sort.append((col.op[1] + 2, "raw", ("gather", tk, snap(tp), False, True)))
    for (a0, a1, n, big) in col.edge:
        if a0 <= tk < a1:
            R = [A_ for A_ in col.auras if A_[0] <= tk < A_[1]]
            if not R:
                continue
            rad = R[0][2] * 2
            for k in range(n):
                an = tk / 15.0 * 0.8 + k * math.tau / n
                ep = (col.op[0] + math.cos(an) * rad, col.op[1] + 4 + math.sin(an) * rad * A.SQ)
                sort.append((ep[1], "raw", ("fl_m" if big else "fl_s", tk + k, snap(ep), False, True)))
    if col.hearth and col.hearth[0] <= tk < col.hearth[1]:
        rad = col.hearth[2]
        for k in range(6):
            an = tk / 15.0 * 0.8 + k * math.tau / 6
            hp = (col.op[0] + 4 + math.cos(an) * rad, col.op[1] + 4 + math.sin(an) * rad * A.SQ_H)
            sort.append((hp[1], "raw", ("fl_l", tk + k, snap(hp), False, True)))
    for it in col.items:
        if not it["gd"] and on(it):
            sort.append((it["gy"] + 1, "it", it))
    for (y, kind, data) in col.rt.get(tk, []):
        sort.append((y, kind, data))
    sort.sort(key=lambda s: s[0])
    for _, kind, v in sort:
        if kind == "e":
            img.alpha_composite(ENEMY, dest=(int(v[0] - ENEMY.width // 2), int(v[1] - ENEMY.height + 6)))
        elif kind == "op":
            sp = OPS["suzuran"] if col.face > 0 else OPS["suzuran"].transpose(Image.FLIP_LEFT_RIGHT)
            img.alpha_composite(sp, dest=snap((col.op[0] - 64, col.op[1] - 119)))
        elif kind == "lead":
            img.alpha_composite(OPS["texas"], dest=snap((col.lead[0] - 64, col.lead[1] - 120)))
        elif kind == "it":
            strip(v["k"], tk - v["t0"] if not v["loop"] else tk, v["gp"], v["flip"], v["loop"])
        elif kind == "raw":
            k, fi, gp, fl, lp = v
            strip(k, fi, snap(gp), fl, lp)
        elif kind == "strip":
            k, gp, fl, fi = v
            strip(k, fi, gp, fl, True)
        elif kind == "tuft":
            gp, fi = v
            strip("tuft", fi, gp)
        elif kind == "bolt":
            p, d, big = v
            nv = (-d[1], d[0])
            hd = snap(p)
            for (s, w, c) in A.fox_bolt(d, tk, big):
                put_px(hd[0] - d[0] * s * PX + nv[0] * w * PX, hd[1] - d[1] * s * PX + nv[1] * w * PX, c, glow=(s == 0 and w == 0))
        elif kind == "pass":
            a, b, f = v
            a0 = snap((a[0], a[1] - 12))
            for (x, y, c) in A.pass_line((b[0] - a0[0]) / PX, (b[1] - 12 - a0[1]) / PX, f):
                put_px(a0[0] + x * PX, a0[1] + y * PX, c)
        elif kind == "lk":
            hist = v
            for k in range(len(hist) - 1):
                p0, p1 = hist[k], hist[k + 1]
                m = int(max(abs(p1[0] - p0[0]), abs(p1[1] - p0[1])) / PX)
                c = A.P[2] if k < len(hist) - 3 else A.F[4]
                for i in range(m):
                    if (i + k) % 2 == 1 and k < len(hist) - 3:
                        continue
                    u = i / max(1, m)
                    put_px(p0[0] + (p1[0] - p0[0]) * u, p0[1] + (p1[1] - p0[1]) * u, c)
            hd = hist[-1]
            if len(hist) >= 2 and hist[-2] != hd:
                dx, dy = hd[0] - hist[-2][0], hd[1] - hist[-2][1]
                L = math.hypot(dx, dy)
                d = (dx / L, dy / L)
            else:
                d = (0, -1)
            nv = (-d[1], d[0])
            for (s, w, c) in A.fox_bolt(d, tk, True):
                put_px(hd[0] - d[0] * s * PX + nv[0] * w * PX, hd[1] - d[1] * s * PX + nv[1] * w * PX, c, glow=(s == 0 and w == 0))
    glow = np.asarray(emit.filter(ImageFilter.GaussianBlur(3))).astype(np.float32) * 0.55
    base = np.asarray(img.convert("RGB")).astype(np.float32) * AMBIENT
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    lit = np.zeros((H, W, 3), np.float32)
    for (lx, ly, lr, li, lt0, ln, lc) in col.lights:
        if lt0 <= tk < lt0 + ln:
            k = li * (1.0 - (tk - lt0) / (ln + 0.5))
            dd = np.sqrt((xx - lx) ** 2 + ((yy - ly) / 0.72) ** 2) / lr
            lit += (k * np.clip(1.0 - dd, 0.0, 1.0) ** 2)[..., None] * np.array(lc, np.float32)
    base = base * (1.0 + lit * 1.3) + lit * 40.0
    return Image.fromarray(np.clip(base + glow, 0, 255).astype(np.uint8), "RGB")


def gif(lib, columns, n_ticks, path, title, zoom_c):
    font = ImageFont.truetype(FONT, 15)
    sfont = ImageFont.truetype(FONT, 12)
    head = 28
    W, H = columns[0][1].W, columns[0][1].H
    frames = []
    for tk in range(n_ticks):
        sheet = Image.new("RGB", (W * len(columns) + 4 * (len(columns) - 1), head + H + 4 + H + 18), (14, 16, 18))
        d = ImageDraw.Draw(sheet)
        for ci, (lab, col) in enumerate(columns):
            x0 = ci * (W + 4)
            im = render(lib, col, tk)
            sheet.paste(im, (x0, head))
            zx, zy = zoom_c
            sheet.paste(im.crop((int(zx - W / 4), int(zy - H / 4), int(zx + W / 4), int(zy + H / 4))).resize((W, H), Image.NEAREST), (x0, head + H + 4))
            d.text((x0 + 6, 5), lab, fill=(235, 225, 200), font=font)
            d.text((x0 + 6, head + H + 4 + H + 2), "上：1 倍（实机大小）  下：2 倍放大", fill=(140, 140, 140), font=sfont)
        if len(columns) > 1:
            d.text((sheet.width - 6 - d.textlength(title, font=sfont), 8), title, fill=(150, 150, 150), font=sfont)
        frames.append(sheet)
    pal = frames[len(frames) // 2].quantize(colors=255, method=Image.MEDIANCUT)
    q = [f.quantize(palette=pal, dither=Image.NONE) for f in frames]
    dur = [70 if i % 3 != 1 else 60 for i in range(len(q))]
    q[0].save(path, save_all=True, append_images=q[1:], duration=dur, loop=0, optimize=False, disposal=1)
    print(os.path.basename(path), len(q), "帧", "%.0f KB" % (os.path.getsize(path) / 1024))


# ---------------------------------------------------------------- 每招的摆法

E_MAIN = [(286, 150), (306, 124), (300, 178), (338, 146), (330, 104), (350, 190), (370, 160), (262, 112), (372, 120), (250, 190)]
TIERS = {"atk": (0, 1, 2), "s1": (0, 1, 2), "s2": (1, 2), "s3": (2,), "late": (0, 1, 2)}


def aura_r(t, k=1.0):
    return int(round((85 + 15 * t) * k * 0.5))


def sc_atk(t):
    c = Col(t, E_MAIN, op=(110, 150))
    c.auras.append((0, 999, aura_r(t), 0))
    c.edge.append((0, 999, 6, False))
    c.wisps = 2 + (1 if t >= 1 else 0)
    for k, tk in enumerate([3, 18, 33, 48]):
        tg = [(0, 3), (1, 2), (3, 0), (2, 1)][k]
        if t >= 2:   # 精二九尾祈愿：每一次都三火归一（狐火 3 发 → 一团大狐火）
            for f in range(6):
                c.conv[tk - 6 + f] = min(1.0, (f + 1) / 6.0)
            c.bigfox(tk, tg[0], trail=True)
        else:
            c.bolts(tk, 2 + (1 if t >= 1 else 0), list(tg), brand=t >= 1)
    return c


def sc_s1(t):
    c = Col(t, E_MAIN, op=(110, 150))
    c.auras.append((0, 999, aura_r(t), 0))
    c.edge.append((0, 999, 6, False))
    c.wisps = 2 + (1 if t >= 1 else 0)
    c.add("s1sig_gd", 3, (c.op[0], c.op[1] + 4), gd=True)
    c.light((c.op[0], c.op[1] - 16), 140, 0.7, 3, 3)
    if t >= 1:
        c.add("s1col_up", 6, c.tip(), gy=c.op[1] + 2)
    if t >= 2:
        c.add("tails_flare", 6, c.op, gy=c.op[1] - 2, until=6 + 6)
    c.light(c.tip(), 100, 0.55, 6)
    c.bolts(6, 5, [0, 3, 1, 2, 4], big=True, brand=t >= 1)
    return c


def sc_s2(t):
    c = Col(t, E_MAIN, op=(150, 140), lead=(110, 176))
    rad = (85 + 15 * t) * 1.6
    R = fit(A.S2_R, rad * 0.5)
    c.auras.append((0, 3, aura_r(t), 0))
    c.auras.append((3, 999, aura_r(t, 1.6), 1))
    c.edge.append((0, 3, 6, False))
    c.edge.append((3, 999, 6, True))
    c.wisps = 3
    cc = (c.op[0], c.op[1] + 4)
    c.add("s2_r%d_gd" % R, 3, cc, gd=True)
    c.add("s2_r%d_b" % R, 3, cc, gy=cc[1] - 3)
    c.add("s2_r%d_f" % R, 3, cc, gy=cc[1] + 1)
    c.light((c.op[0], c.op[1] - 16), min(240, rad), 0.75, 3, 3)
    for k in range(1, 4):   # 暖光期间每秒回复队长：头顶落三朵小铃铛
        tk = 3 + 15 * k
        c.add("heal_up", tk, c.lead, gy=c.lead[1] + 1)
        c.add("heal_gd", tk, c.lead, gd=True)
        c.light((c.lead[0], c.lead[1] - 24), 90, 0.45, tk, 2, HEAL_L)
    c.bolts(26, 3, [1, 2])
    return c


def sc_s3(t):
    c = Col(t, [(x + 120, y + 60) for x, y in E_MAIN] + [(150, 330), (520, 300), (500, 90)], op=(300, 210), lead=(250, 250), size=(620, 420))
    rad = (85 + 15 * t) * 2.2
    R = fit(A.S3_R, rad * 0.5)
    c.auras.append((0, 3, aura_r(t), 0))
    c.auras.append((3, 999, int(round(rad * 0.5)), 2))
    c.edge.append((0, 3, 6, False))
    c.edge.append((3, 999, 9, True))
    c.wisps = 3
    cc = (c.op[0], c.op[1] + 4)
    c.add("s3_r%d_gd" % R, 3, cc, gd=True)
    c.add("s3_r%d_b" % R, 3, cc, gy=cc[1] - 3)
    c.add("s3_r%d_f" % R, 3, cc, gy=cc[1] + 1)
    c.light((c.op[0], c.op[1] - 16), 220, 0.85, 3, 3)
    for j, tk in enumerate([18, 31, 45, 58]):   # 每 0.9 秒一处狐火落点（游戏里位置是画面随机）
        a = j * 2.3 + 0.5
        rr = rad * (0.35 + 0.15 * j)
        at = (c.op[0] + math.cos(a) * rr, c.op[1] + math.sin(a) * rr * 0.55 + 4)
        c.add("drop_up", tk, at, gy=at[1] + 1)
        c.add("drop_gd", tk, at, gd=True)
        c.light((at[0], at[1] - 8), 90, 0.5, tk + 3)
    for k in range(1, 5):
        tk = 3 + 15 * k
        c.add("heal_up", tk, c.lead, gy=c.lead[1] + 1)
        c.add("heal_gd", tk, c.lead, gd=True)
        c.light((c.lead[0], c.lead[1] - 24), 90, 0.45, tk, 2, HEAL_L)
    return c


def sc_late(t):
    """后期：三火归一（节点）大狐火 + 扩散（late_shape 升级卡，命中处一圈火环）；精二多拖尾火苗"""
    c = Col(t, E_MAIN, op=(110, 150))
    c.auras.append((0, 999, aura_r(t), 0))
    c.edge.append((0, 999, 6, False))
    c.wisps = 3
    for tk, tg in [(8, 0), (30, 2)]:
        for f in range(6):
            c.conv[tk - 6 + f] = min(1.0, (f + 1) / 6.0)
        c.bigfox(tk, tg, trail=t >= 2, splash=True)
    return c


def sc_branch():
    """节点 / 分支（精二）：狐火点点（附着 + 传火 + 灼烧圈）、画地为牢（金封印）、围炉（光域边大狐火）、围炉·添薪（火环爆发）、响应「祈愿」（队长处光域闪一下）"""
    c = Col(1, E_MAIN, op=(130, 150), lead=(90, 196))
    c.tails = False
    rad = (85 + 15) * 1.6
    c.auras.append((0, 999, aura_r(1, 1.6), 1))
    c.hearth = (0, 999, rad)
    c.wisps = 3
    hits = c.bolts(3, 3, [0, 3, 1])
    # 狐火点点：命中后附在那只头上 2 秒，每 0.5 秒灼烧 + 传一次火
    for h, ei in zip(hits, [0, 3, 1]):
        for ff in range(30):
            e = c.enemies[ei]
            c.put_rt(h + ff, e[1] + 1, "raw", ("fl_m", h + ff + ei, snap((e[0], e[1] - 11)), False, True))
    if hits:
        h0 = hits[0]
        for kk in range(3):
            c.add("att_gd", h0 + 8 + kk * 8, c.enemies[0], gd=True)
        a, b = c.enemies[0], c.enemies[7]
        for f in range(3):
            c.put_rt(h0 + 8 + f, max(a[1], b[1]) + 1, "pass", ((a[0], a[1]), (b[0], b[1]), f))
        for ff in range(22):
            c.put_rt(h0 + 9 + ff, b[1] + 1, "raw", ("fl_m", h0 + ff, snap((b[0], b[1] - 11)), False, True))
    # 画地为牢：全力以赴命中定身 → 金封印
    c.add("s1sig_gd", 34, (c.op[0], c.op[1] + 4), gd=True)
    c.bolts(36, 5, [2, 4, 5, 6, 8], big=True, seal=True)
    # 围炉·添薪
    Rh = fit(A.HB_R, (85 + 15) * 1.3 * 0.5)
    cc = (c.op[0], c.op[1] + 4)
    c.add("hb_r%d_gd" % Rh, 60, cc, gd=True)
    c.add("hb_r%d_b" % Rh, 60, cc, gy=cc[1] - 3)
    c.add("hb_r%d_f" % Rh, 60, cc, gy=cc[1] + 1)
    c.light((c.op[0], c.op[1] - 16), 160, 0.7, 60, 3)
    # 响应「祈愿」：队长开技能 → 队长处光域闪一下
    Rp = fit(A.PRAY_R, 85 * 0.5)
    lc = (c.lead[0], c.lead[1] + 4)
    c.add("pray_r%d_gd" % Rp, 78, lc, gd=True)
    c.add("pray_r%d_b" % Rp, 78, lc, gy=lc[1] - 3)
    c.add("pray_r%d_f" % Rp, 78, lc, gy=lc[1] + 1)
    c.light((c.lead[0], c.lead[1] - 16), 100, 0.6, 78, 3)
    return c


def sc_link():
    """连携「狐火」（link/v2 缺省）：四团狐火绕她转一圈（0.35 秒）再各追向区域内一只（0.25 秒），身后拖浅金追迹，命中炸开"""
    c = Col(2, E_MAIN, op=(130, 150), lead=(90, 190))
    c.tails = True
    c.auras.append((0, 999, aura_r(2), 0))
    c.wisps = 3
    t0 = 4
    ts = [0, 1, 2, 3]
    hist = [[], [], [], []]
    T1, T2 = 0.35, 0.25
    for f in range(int((T1 + T2) * 15) + 2):
        t = f / 15.0
        for j in range(4):
            a = math.tau * (j / 4.0 + min(t, T1) / T1)
            orb = (c.op[0] + math.cos(a) * 40, c.op[1] - 24 + math.sin(a) * 40)
            q = orb
            if t >= T1:
                e = c.enemies[ts[j]]
                to = (e[0], e[1] - 12)
                u = min(1.0, (t - T1) / T2)
                q = (orb[0] + (to[0] - orb[0]) * u, orb[1] + (to[1] - orb[1]) * u)
            hist[j].append(snap(q))
            hist[j] = hist[j][-6:]
            if t < T1 + T2:
                c.put_rt(t0 + f, hist[j][-1][1] + 26, "lk", list(hist[j]))
    th = t0 + int((T1 + T2) * 15)
    for j in range(4):
        c.pop(th, ts[j])
    c.light((c.op[0], c.op[1] - 24), 100, 0.5, t0)
    return c


NAMES = {"atk": "普攻「狐火」", "s1": "S1「全力以赴」", "s2": "S2「儿时的舞乐」", "s3": "S3「狐火渺然」", "late": "后期：三火归一 + 扩散"}
SCENES = {"atk": (sc_atk, 64, (200, 140)), "s1": (sc_s1, 45, (200, 140)), "s2": (sc_s2, 64, (150, 140)), "s3": (sc_s3, 72, (300, 200)), "late": (sc_late, 50, (200, 140))}


def main():
    global ENEMY, OPS
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    ap.add_argument("--out", default=os.path.join(MAIN, "Claude outputs", "pxplane_suzuran_1105", "gif"))
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    lib = Lib()
    en = sprite(os.path.join(ROOT, "game", "art", "enemies", "offspring", "e_offspring@2x.png"), 4)
    arr = np.asarray(en).astype(np.float32)
    arr[..., :3] = arr[..., :3] * 0.32 + np.array([10, 12, 14])
    ENEMY = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")
    OPS = {"suzuran": sprite(os.path.join(ROOT, "game", "art", "operators", "suzuran", "op_suzuran_idle@2x.png"), 8),
           "texas": sprite(os.path.join(ROOT, "game", "art", "operators", "texas", "op_texas_idle@2x.png"), 7)}
    only = set(x for x in a.only.split(",") if x)
    title = "铃兰 · 转平面 · 15 fps 原速"
    for name, (fn, n, zc) in SCENES.items():
        if only and name not in only:
            continue
        cols = [("%s  精英 %d" % (NAMES[name], t), fn(t)) for t in TIERS[name]]
        gif(lib, cols, n, os.path.join(a.out, "suzuran_%s.gif" % name), title, zc)
    if not only or "branch" in only:
        gif(lib, [("节点 / 分支：狐火点点 · 画地为牢 · 围炉 · 添薪 · 响应「祈愿」", sc_branch())], 92, os.path.join(a.out, "suzuran_branch.gif"), title, (180, 150))
    if not only or "link" in only:
        gif(lib, [("连携技「狐火」（link/v2 缺省，不分档）", sc_link())], 30, os.path.join(a.out, "suzuran_link.gif"), title, (190, 140))


if __name__ == "__main__":
    main()
