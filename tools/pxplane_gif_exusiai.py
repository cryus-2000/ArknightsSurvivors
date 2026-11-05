#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""能天使转平面（docs/262）送审 GIF：上 GCP 前先给用户看（协调人 11-05 新流程），只用 Python、不开 Godot。

帧条直接读 tools/pxplane_bake_exusiai.py 烤出的 game/art/fx/pxp/pxp_ex_*.png + game/data/pxp_exusiai.json（与游戏同一份）；
弹体 / 连锁细线 / 连携曳光用 tools/pxplane_exu_art.py 里与 fx_pxplane_exu.gd 同算法的 Python 版逐格画。
摆法照游戏：枪口 = 脚底 (+30, −35)，瞄准点 = 敌人脚底上 10，弹速 520 / 秒，速射间隔 0.35 秒、扫射 0.2 秒、过载 4 连射间隔 0.06 秒；
同屏封顶同游戏（枪口焰每人 1 个、命中火花每拍 ≤ 3（技能 4）、同时 ≤ 8 团、额外弹 / 连锁每拍 ≤ 3）。
每招一张：E0 / E1 / E2 左右并排（只放实际存在的档）；上半 1 倍（实机大小：1 美术像素 = 2 屏幕像素）、下半 2 倍放大；15 fps 原速循环。
光照近似：整体压暗到 AMBIENT（实机环境光把色层压暗），枪口 / 命中各挂一盏短照地光（暖色径向提亮，1–2 拍）；热芯（emit 点）近似发光层加一层柔光。
后坐：开火那一拍干员本体往后挪 1 美术像素（同游戏 fx_pxplane_exu.kick）。

用法：python tools/pxplane_gif_exusiai.py [--only atk,s1] [--out 目录]
"""
import argparse, json, math, os, sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pxplane_exu_art as A

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAIN = os.path.dirname(os.path.dirname(os.path.dirname(ROOT))) if ".claude" in ROOT else ROOT
PX = 2
W, H = 400, 250
OX, OY = 70, 160
GROUND = (36, 46, 48)
DIRS = [-90, -45, 0, 45, 90]
FONT = "C:/Windows/Fonts/msyh.ttc"
SPD = 520.0 / 15.0          # 每拍弹体位移（世界像素）
AMBIENT = 0.8               # 场景压暗（近似实机环境光）
LIGHT_COL = (1.0, 0.72, 0.5)
MZ = (30, -35)
AIM_Y = -10


def pick_dir(ang):
    a = (ang + 180) % 360 - 180
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


class Lib:
    def __init__(self):
        self.meta = {k: v for k, v in json.load(open(os.path.join(ROOT, "game", "data", "pxp_exusiai.json"), encoding="utf-8")).items() if k != "_doc"}
        self.tex = {}

    def frame(self, k, fi, loop=False):
        m = self.meta[k]
        n = m["n"]
        if loop:
            fi %= n
        if fi < 0 or fi >= n:
            return None
        if k not in self.tex:
            self.tex[k] = Image.open(os.path.join(ROOT, "game", "art", "fx", "pxp", "pxp_ex_%s.png" % k.replace("_d-", "_dm"))).convert("RGBA")
        w, h = m["w"], m["h"]
        return self.tex[k].crop((fi * w, 0, (fi + 1) * w, h)), m


def sprite(path, n):
    im = Image.open(path).convert("RGBA")
    fw = im.width // n
    return im.crop((0, 0, fw, im.height))


class Col:
    """一栏的时间轴（拍 = 1/15 秒）。坐标一律世界像素（画面内绝对坐标）。"""

    def __init__(self, tier, enemies, mates=False):
        self.t = tier
        self.items = []     # 帧条件 {k, t0, gp, flip, gd, gy, loop, until}
        self.buls = []      # {p0, v, t0, t1, kind, small, tracer}
        self.lines = []     # {kind, a, b, t0, i}
        self.grains = []    # 弹壳 / 火星 {p, v, t0, col}
        self.enemies = [[float(x), float(y), 10 ** 9] for x, y in enemies]   # x, y, 倒下的拍
        self.mates = []
        self.halo_on = False
        self.fire_ticks = []
        self.halo_s3 = None
        self.barrel = None
        self.beat = {}
        self.op = (OX, OY)
        self.lights = []    # (x, y, 半径, 强度, 起拍, 拍数)
        self.vc = 0
        if mates:
            self.mates = [(OX - 34, OY - 26, "texas"), (OX - 30, OY + 26, "lumen")]

    def count(self, key, tk, cap):
        k = (key, tk)
        self.beat[k] = self.beat.get(k, 0) + 1
        return self.beat[k] <= cap

    def add(self, k, tk, gp, flip=False, gd=False, gy=None, loop=False, until=None, tag=""):
        self.items.append({"k": k, "t0": tk, "gp": snap(gp), "flip": flip, "gd": gd, "gy": gp[1] if gy is None else gy, "loop": loop, "until": until, "tag": tag})

    def live_hits(self, tk):
        n = 0
        for it in self.items:
            if it["tag"] == "hit" and it["t0"] <= tk < it["t0"] + 4:
                n += 1
        return n

    def hit(self, tk, key, at, gy, cap=3, ckey="hit", ang=0.0):
        for it in self.items:   # 同一只身上 2 拍内只留一团（同游戏 _fresh_near）
            if it["tag"] == "hit" and 0 <= tk - it["t0"] < 2 and math.hypot(it["gp"][0] - at[0], it["gp"][1] - at[1]) < 10:
                return
        if not self.count(ckey, tk, cap) or self.live_hits(tk) >= 8:
            return
        d, fl = pick_dir(math.degrees(ang))
        self.add(key + "_d%d" % d, tk, at, fl, gy=gy, tag="hit")
        if self.count("hl", tk, 1):
            self.lights.append((at[0], at[1] + 6, 55 + 10 * self.t, 0.55, tk, 2))

    def muzzle(self, tk, mode, ang, mz=None):
        for it in self.items:
            if it["tag"] == "mz" and (it["until"] is None or it["until"] > tk):
                it["until"] = tk
        tt = max(self.t, {"n": 0, "s1": 0, "s2": 1, "s3": 2, "g": 1}[mode])
        d, fl = pick_dir(math.degrees(ang))
        m = mz or (self.op[0] + MZ[0], self.op[1] + MZ[1])
        self.vc += 1
        self.add("mz_%s_e%d_v%d_d%d" % (mode, tt, self.vc % 2, d), tk, m, fl, gy=self.op[1], tag="mz")
        if self.vc % 3 == 0:
            self.add("smoke_up", tk, m, gy=self.op[1])
        if self.count("casing", tk, 1):
            a = -2.4 + (tk % 3) * 0.15
            self.grains.append({"p": (m[0] - 4, m[1]), "v": (math.cos(a) * 60, -120 - (tk % 2) * 30), "t0": tk, "gy": self.op[1] + 2, "col": ["#ffd86a", "#a8741a"]})
        if self.count("ml", tk, 1):
            self.lights.append((m[0] + 6, m[1] + 30, 80 + 12 * tt, 0.8, tk, 1))
        self.fire_ticks.append(tk)

    def shoot(self, tk, targets, mode="n", kinds=None, pierce=0, small=False, tracer_k=None, hit_mode=None, rng=330.0, cap=3, mark_k=None):
        """一轮：每个目标一发（targets = 敌人序号或 (角度, None) 扇形）；返回各发命中拍"""
        mz = (self.op[0] + MZ[0], self.op[1] + MZ[1])
        first = None
        outs = []
        for j, tg in enumerate(targets):
            if isinstance(tg, tuple):   # 扇形：按角度直线飞
                ang = tg[0]
                d = (math.cos(ang), math.sin(ang))
            else:
                e = self.enemies[tg]
                aim = (e[0], e[1] + AIM_Y)
                ang = math.atan2(aim[1] - mz[1], aim[0] - mz[0])
                d = (math.cos(ang), math.sin(ang))
            if first is None:
                first = ang
            # 沿线命中（按距离），穿透 pierce
            hits = []
            for ei, e in enumerate(self.enemies):
                rel = (e[0] - mz[0], e[1] + AIM_Y - mz[1])
                s = rel[0] * d[0] + rel[1] * d[1]
                dist = abs(rel[0] * d[1] - rel[1] * d[0])
                if 0 < s < rng and dist < 12 + 6:
                    hits.append((s, ei))
            hits.sort()
            hits = [h for h in hits if tk + math.ceil(h[0] / SPD) < self.enemies[h[1]][2]][: pierce + 1]
            end = hits[-1][0] if len(hits) > pierce else rng
            t1 = tk + max(1, math.ceil(end / SPD))
            kind = kinds[j] if kinds else mode
            self.buls.append({"p0": mz, "v": (d[0] * SPD, d[1] * SPD), "t0": tk, "t1": t1, "kind": kind, "small": small, "tracer": tracer_k is not None and j in tracer_k, "back": (j % 4) * 3 if kind == "g" else 0})
            th = []
            for s, ei in hits:
                ht = tk + max(1, math.ceil(s / SPD))
                e = self.enemies[ei]
                hm = hit_mode(j, ei) if callable(hit_mode) else (hit_mode or mode)
                key = "hit_full" if hm == "full" else ("hit_x" if hm == "x" else "hit_%s_e%d" % (hm, max(self.t, {"n": 0, "s1": 0, "s2": 1, "s3": 2, "g": 1}[hm])))
                self.hit(ht, key, (e[0], e[1] + AIM_Y), e[1] + 1, cap=cap if hm != "x" else 3, ckey="hit" if hm != "x" else "xh", ang=ang)
                if mark_k is not None and j in mark_k:
                    self.add("mark_gd", ht, (e[0], e[1]), gd=True)
                th.append((ht, ei))
            outs.append(th)
        self.muzzle(tk, mode, first)
        return outs

    def kill(self, ei, tk):
        self.enemies[ei][2] = min(self.enemies[ei][2], tk)


# ---------------------------------------------------------------- 绘制

def render(lib, col, tk):
    img = Image.new("RGBA", (W, H), GROUND + (255,))
    rng = np.random.default_rng(7)
    g = np.asarray(img).copy()
    noise_ = rng.integers(-5, 6, size=(H // 2, W // 2, 1))
    g[..., :3] = np.clip(g[..., :3].astype(int) + np.repeat(np.repeat(noise_, 2, 0), 2, 1), 0, 255)
    img = Image.fromarray(g.astype(np.uint8), "RGBA")
    emit = Image.new("RGB", (W, H), (0, 0, 0))
    ed = ImageDraw.Draw(emit)
    dr = ImageDraw.Draw(img)

    def put_px(im_draw, x, y, c, glow=False):
        x, y = snap((x, y))
        im_draw.rectangle([x, y, x + PX - 1, y + PX - 1], fill=c)
        if glow:
            ed.rectangle([x, y, x + PX - 1, y + PX - 1], fill=c[:3] if isinstance(c, tuple) else c)

    def strip(it):
        if tk < it["t0"] or (it["until"] is not None and tk >= it["until"]):
            return None
        r = lib.frame(it["k"], tk - it["t0"] if not it["loop"] else tk, it["loop"])
        if r is None:
            return None
        fr, m = r
        if it["flip"]:
            fr = fr.transpose(Image.FLIP_LEFT_RIGHT)
        gx, gy = it["gp"]
        left = gx - (m["w"] - m["ox"]) * PX if it["flip"] else gx - m["ox"] * PX
        top = gy - m["oy"] * PX
        fi = (tk - it["t0"]) if not it["loop"] else tk % m["n"]
        return fr.resize((fr.width * PX, fr.height * PX), Image.NEAREST), (int(left), int(top)), m["emit"][fi], m, it["flip"]

    def comp(p):
        big, (l, t), pts, m, fl = p
        img.alpha_composite(big, dest=(max(0, l), max(0, t)), source=(max(0, -l), max(0, -t)))
        for q in pts:
            x = q[0] if not fl else m["w"] - 1 - q[0]
            ed.rectangle([l + x * PX, t + q[1] * PX, l + x * PX + PX - 1, t + q[1] * PX + PX - 1], fill=tuple(int(q[2][i:i + 2], 16) for i in (0, 2, 4)))

    for it in col.items:
        if it["gd"]:
            p = strip(it)
            if p:
                comp(p)
    sort = []
    for e in col.enemies:
        if tk < e[2]:
            sort.append((e[1], "e", e))
    sort.append((col.op[1], "op", None))
    for m in col.mates:
        sort.append((m[1], "mate", m))
        if col.halo_on:
            sort.append((m[1] + 0.5, "strip", {"k": "halo_up", "t0": 0, "gp": snap((m[0], m[1] - 72)), "flip": False, "loop": True, "until": None}))
            fts = [f for f in col.fire_ticks if 0 <= tk - f < 3]
            if fts:
                sort.append((m[1] + 0.6, "strip", {"k": "halo_fire_up", "t0": max(fts), "gp": snap((m[0], m[1] - 72)), "flip": False, "loop": False, "until": None}))
    if col.halo_s3 and col.halo_s3[0] <= tk < col.halo_s3[1]:
        sort.append((col.op[1] + 0.5, "strip", {"k": "halo_s3_up", "t0": 0, "gp": snap((col.op[0], col.op[1] - 80)), "flip": False, "loop": True, "until": None}))
    for it in col.items:
        if not it["gd"]:
            sort.append((it["gy"] + 1, "strip", it))
    for b in col.buls:
        if b["t0"] <= tk < b["t1"]:
            u = tk - b["t0"]
            p = (b["p0"][0] + b["v"][0] * u, b["p0"][1] + b["v"][1] * u)
            sort.append((p[1] + 20, "bul", (b, p)))
    for ln in col.lines:
        if ln["t0"] <= tk < ln["t0"] + 3:
            sort.append((ln["gy"], "line", ln))
    sort.sort(key=lambda s: s[0])
    for _, kind, v in sort:
        if kind == "e":
            img.alpha_composite(ENEMY, dest=(int(v[0] - ENEMY.width // 2), int(v[1] - ENEMY.height + 6)))
        elif kind == "op":
            kick = -PX if tk in col.fire_ticks else 0
            img.alpha_composite(OPS["exusiai"], dest=snap((col.op[0] - 64 + kick, col.op[1] - 120)))
        elif kind == "mate":
            img.alpha_composite(OPS[v[2]], dest=snap((v[0] - 64, v[1] - 120)))
        elif kind == "strip":
            p = strip(v)
            if p:
                comp(p)
        elif kind == "bul":
            b, p = v
            d = (b["v"][0] / SPD, b["v"][1] / SPD)
            buf = A.bullet(b["kind"], col.t, d, tk, b["small"], b["tracer"], b.get("back", 0))
            hd = snap(p)
            for (x, y), c in buf.p.items():
                cc = A.hx(c)
                put_px(dr, hd[0] + x * PX, hd[1] + y * PX, cc, glow=c == "#ffffff")
        elif kind == "line":
            f = tk - v["t0"]
            a, b2 = v["a"], v["b"]
            if v["kind"] == "ltr":
                L = math.hypot(b2[0] - a[0], b2[1] - a[1]) / PX
                dd = ((b2[0] - a[0]) / (L * PX), (b2[1] - a[1]) / (L * PX))
                buf = A.tracer_line(L, f, v["i"])
                for (s, w), c in buf.p.items():
                    nv = (-dd[1], dd[0])
                    put_px(dr, a[0] + (dd[0] * s - nv[0] * w) * PX, a[1] + (dd[1] * s - nv[1] * w) * PX, A.hx(c), glow=c == "#ffffff")
            else:   # 连锁细线（同 fx_pxplane_exu draw_rt "line"）
                n = max(1, int(math.hypot(b2[0] - a[0], b2[1] - a[1]) / PX))
                for i in range(n + 1):
                    u = i / n
                    if f == 2 and u < 0.5:
                        continue
                    rp = A.RAMP["n"] if i % 2 == 0 else A.GOLD
                    put_px(dr, a[0] + (b2[0] - a[0]) * u, a[1] + (b2[1] - a[1]) * u, A.hx(rp[5 if f == 0 else 4]), glow=f == 0 and i % 4 == 0)
    for gr in col.grains:   # 弹壳：抛物线、落地停 6 拍
        u = (tk - gr["t0"]) / 15.0
        if u < 0 or u > 0.9:
            continue
        x = gr["p"][0] + gr["v"][0] * u
        y = gr["p"][1] + gr["v"][1] * u + 0.5 * 900 * u * u
        landed = y >= gr["gy"]
        if landed:   # 落地弹一下：反弹 0.4、再落下停住
            disc = gr["v"][1] ** 2 + 2 * 900 * (gr["gy"] - gr["p"][1])
            tl = (-gr["v"][1] + math.sqrt(max(0.0, disc))) / 900
            ub = u - tl
            vb = math.sqrt(max(0.0, disc)) * 0.4
            hb = vb * ub - 0.5 * 900 * ub * ub
            x = gr["p"][0] + gr["v"][0] * (tl + min(ub, 2 * vb / 900) * 0.5)
            y = gr["gy"] - max(0.0, hb)
            landed = hb <= 0
        dr.rectangle([*snap((x, y)), snap((x, y))[0] + PX - 1, snap((x, y))[1] + PX - 1], fill=A.hx(gr["col"][1] if landed else gr["col"][0]))
    if col.barrel and col.barrel[0] <= tk < col.barrel[1]:
        m = (col.op[0] + MZ[0], col.op[1] + MZ[1])
        c = A.hx(A.RAMP["s2"][4 if tk % 2 == 0 else 3])
        for q in ((0, 0), (2, 0), (0, 2), (2, 2)):
            put_px(dr, m[0] + q[0], m[1] + q[1], c, glow=True)
    glow = np.asarray(emit.filter(ImageFilter.GaussianBlur(3))).astype(np.float32) * 0.55
    base = np.asarray(img.convert("RGB")).astype(np.float32) * AMBIENT
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    lit = np.zeros((H, W), np.float32)
    for (lx, ly, lr, li, lt0, ln) in col.lights:
        if lt0 <= tk < lt0 + ln:
            k = li * (1.0 - (tk - lt0) / (ln + 0.5))
            dd = np.sqrt((xx - lx) ** 2 + ((yy - ly) / 0.72) ** 2) / lr
            lit += k * np.clip(1.0 - dd, 0.0, 1.0) ** 2
    lc = np.array(LIGHT_COL, np.float32)
    base = base * (1.0 + lit[..., None] * 1.3 * lc) + lit[..., None] * 40.0 * lc
    return Image.fromarray(np.clip(base + glow, 0, 255).astype(np.uint8), "RGB")


def gif(lib, columns, n_ticks, path, title, zoom_c):
    font = ImageFont.truetype(FONT, 15)
    sfont = ImageFont.truetype(FONT, 12)
    head = 28
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
    print(path, len(q), "帧", "%.0f KB" % (os.path.getsize(path) / 1024))


# ---------------------------------------------------------------- 每招的摆法

E_MAIN = [(200, 150), (226, 140), (214, 172), (252, 158), (240, 128), (276, 170), (290, 144), (186, 120), (262, 196), (310, 160)]
E_LINE = [(170, 128), (205, 133), (240, 138), (275, 143), (215, 175), (250, 185), (300, 120)]
TIERS = {"atk": (0, 1, 2), "s1": (0, 1, 2), "s2": (1, 2), "s3": (2,), "mag": (1, 2), "late": (0, 1, 2)}


def stack_kind(n):
    """精一穿甲连射：同一目标第 n 发（从 1 起）的弹体层数（max 10，三档）"""
    if n <= 1:
        return "n"
    return "t%d" % min(3, max(1, math.ceil((n - 1) / 10 * 3 - 0.001)))


def sc_atk(t):
    c = Col(t, E_MAIN, mates=True)
    c.halo_on = t >= 2
    tg = [0, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 0]
    cnt = {}
    for k, tk in enumerate(range(1, 45, 4)):
        e = tg[k % len(tg)]
        cnt[e] = cnt.get(e, 0) + 1
        n = cnt[e]
        kind = stack_kind(n) if t >= 1 else "n"
        full = t >= 1 and n >= 10
        c.shoot(tk, [e], "n", kinds=[kind], hit_mode="full" if full else "n")
    return c


def sc_s1(t):
    c = Col(t, E_LINE)
    c.add("ring_s1_gd", 1, c.op, gd=True)
    for k, tk in enumerate(range(4, 34, 5)):
        c.shoot(tk, [k % 2], "s1", pierce=3, cap=4)
    return c


def sc_s2(t):
    c = Col(t, E_MAIN, mates=True)
    c.halo_on = t >= 2
    c.barrel = (1, 36)
    for k, tk in enumerate(range(1, 36, 3)):
        c.shoot(tk, [[0, 1, 2, 3, 0, 4][k % 6]], "s2")
    c.add("steam_up", 37, (c.op[0] + MZ[0], c.op[1] + MZ[1]), gy=c.op[1])
    return c


def sc_s3(t):
    c = Col(t, E_MAIN, mates=True)
    c.halo_on = True
    c.add("ring_s3_gd", 1, c.op, gd=True)
    c.add("halo_fire_up", 1, (c.op[0], c.op[1] - 80), gy=c.op[1] + 0.4)
    c.halo_s3 = (2, 60)
    for k, tk in enumerate(range(4, 44, 6)):
        for j in range(4):
            c.shoot(tk + j, [[0, 4, 3, 1][k % 4]], "s3", cap=4)
    return c


def sc_mag(t):
    c = Col(t, E_MAIN, mates=True)
    c.halo_on = t >= 2
    c.shoot(2, [0], "n")
    mz = (c.op[0] + MZ[0], c.op[1] + MZ[1])
    a0 = math.atan2(E_MAIN[0][1] + AIM_Y - mz[1], E_MAIN[0][0] - mz[0])
    fan = [(a0 + math.radians(-25 + 50 * i / 7), None) for i in range(8)]
    c.shoot(8, fan, "g", pierce=1, cap=5)
    c.shoot(20, [1], "n")
    return c


def sc_late(t):
    c = Col(t, E_MAIN)
    for k, tk in enumerate(range(1, 40, 5)):
        main = c.shoot(tk, [k % 3], "n", tracer_k=[0] if k % 4 == 2 else None, mark_k=[0] if k % 4 == 2 else None)
        for x in range(t + 1):   # 额外弹：每档 +1 发，射向另一名敌人
            c.shoot(tk + 1, [(k + x + 3) % len(E_MAIN)], "n", small=True, hit_mode="x")
        if main and main[0]:
            ht, ei = main[0][0]
            nx = (ei + 5) % len(E_MAIN)
            if k % 2 == 0 and c.count("ch", ht, 3):   # 连锁弹射
                a = (E_MAIN[ei][0], E_MAIN[ei][1] - 16)
                b = (E_MAIN[nx][0], E_MAIN[nx][1] - 16)
                c.lines.append({"kind": "chain", "a": a, "b": b, "t0": ht, "gy": E_MAIN[nx][1] + 1})
                c.hit(ht, "hit_x", b, E_MAIN[nx][1] + 1, ckey="xh", ang=math.atan2(b[1] - a[1], b[0] - a[0]))
            if k % 3 == 1:   # 扩散溅射
                c.add("ring_splash_gd", ht, E_MAIN[ei], gd=True)
    c.add("ring_frag_gd", 30, E_MAIN[2], gd=True)   # 跳弹·碎裂（击杀处弹片）
    c.kill(2, 30)
    return c


def sc_link():
    c = Col(2, E_MAIN, mates=True)
    c.halo_on = True
    fp = (c.op[0], c.op[1] - 20)
    zone = (250, 160)
    base = math.atan2(zone[1] - fp[1], zone[0] - fp[0])
    L = math.hypot(zone[0] - fp[0], zone[1] - fp[1]) + 250
    for i in range(8):
        tk = 2 + int(i * 0.03 * 15)
        a = base + math.radians((i % 4 - 1.5) * 5.3 * (1 if i % 2 == 0 else -1))
        tp = (fp[0] + math.cos(a) * L, fp[1] + math.sin(a) * L)
        c.lines.append({"kind": "ltr", "a": fp, "b": tp, "t0": tk, "i": i, "gy": fp[1] + 20})
        c.muzzle(tk, "g", a, mz=fp)
        hs = []
        for ei, e in enumerate(c.enemies):
            rel = (e[0] - fp[0], e[1] - fp[1])
            s = rel[0] * math.cos(a) + rel[1] * math.sin(a)
            if 0 < s < L and abs(rel[0] * math.sin(a) - rel[1] * math.cos(a)) < 14 + 5:
                hs.append((s, ei))
        hs.sort()
        for s, ei in hs[:2]:
            e = c.enemies[ei]
            dd2, fl2 = pick_dir(math.degrees(a))
            c.add("hit_%s_e2_d%d" % ("n" if i % 2 == 0 else "g", dd2), tk + max(0, round(3 * s / L)), (e[0], e[1] - 11), fl2, gy=e[1] + 1, tag="hit")
    return c


NAMES = {"atk": "普攻「速射」", "s1": "S1「冲锋模式」", "s2": "S2「扫射模式」", "s3": "S3「过载模式」", "mag": "天赋「快速弹匣」倾泻", "late": "后期额外攻击（late_shape）"}
SCENES = {"atk": (sc_atk, 48, (200, 140)), "s1": (sc_s1, 40, (190, 130)), "s2": (sc_s2, 48, (150, 130)), "s3": (sc_s3, 50, (170, 120)),
          "mag": (sc_mag, 34, (170, 140)), "late": (sc_late, 46, (220, 150))}


def load_sprites():
    """怪物剪影 + 干员待机第 0 帧（终结技 GIF 也用）"""
    en = sprite(os.path.join(ROOT, "game", "art", "enemies", "offspring", "e_offspring@2x.png"), 4)
    arr = np.asarray(en).astype(np.float32)
    arr[..., :3] = arr[..., :3] * 0.32 + np.array([10, 12, 14])
    enemy = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")
    ops = {"exusiai": sprite(os.path.join(ROOT, "game", "art", "operators", "exusiai", "op_exusiai_idle@2x.png"), 8),
           "texas": sprite(os.path.join(ROOT, "game", "art", "operators", "texas", "op_texas_idle@2x.png"), 7),
           "lumen": sprite(os.path.join(ROOT, "game", "art", "operators", "lumen", "op_lumen_idle@2x.png"), 8)}
    return enemy, ops


def main():
    global ENEMY, OPS
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    ap.add_argument("--out", default=os.path.join(MAIN, "Claude outputs", "pxplane_exusiai_1105", "gif"))
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    lib = Lib()
    en = sprite(os.path.join(ROOT, "game", "art", "enemies", "offspring", "e_offspring@2x.png"), 4)
    arr = np.asarray(en).astype(np.float32)
    arr[..., :3] = arr[..., :3] * 0.32 + np.array([10, 12, 14])
    ENEMY = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")
    OPS = {"exusiai": sprite(os.path.join(ROOT, "game", "art", "operators", "exusiai", "op_exusiai_idle@2x.png"), 8),
           "texas": sprite(os.path.join(ROOT, "game", "art", "operators", "texas", "op_texas_idle@2x.png"), 7),
           "lumen": sprite(os.path.join(ROOT, "game", "art", "operators", "lumen", "op_lumen_idle@2x.png"), 8)}
    only = set(x for x in a.only.split(",") if x)
    title = "能天使 · 转平面 · 15 fps 原速"
    for name, (fn, n, zc) in SCENES.items():
        if only and name not in only:
            continue
        cols = [("%s  精英 %d" % (NAMES[name], t), fn(t)) for t in TIERS[name]]
        gif(lib, cols, n, os.path.join(a.out, "exusiai_%s.gif" % name), title, zc)
    if not only or "link" in only:
        gif(lib, [("连携技「穿透扫射」（不分档）", sc_link())], 20, os.path.join(a.out, "exusiai_link.gif"), title, (150, 140))


if __name__ == "__main__":
    main()
