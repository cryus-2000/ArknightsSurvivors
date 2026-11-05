#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""安洁莉娜转平面（docs/267）送审 GIF：上 GCP 前先给用户看（协调人 11-05 流程），只用 Python、不开 Godot。

帧条直接读 tools/pxplane_bake_angelina.py 烤出的 game/art/fx/pxp/pxp_an_*.png + game/data/pxp_angelina.json（与游戏同一份）；
弹尾 / 弹药珠 / 连携碎片尾迹用与 fx_pxplane_ang.gd 同算法的 Python 版逐格画。
摆法照游戏：杖头 = 脚底 (+34, −80)，弹速 380 / 秒、弧高 26，落点半径 75（S1 ×1.4）、拉拢半径 100、拉拢 40（S1 ×2）；
失重井 1.2 秒、每 0.4 秒拉 12、井心 30 内托起 22；微粒场半径 150、环带 110、每 0.5 秒整形；反重力场 220、每 0.2 秒托起 30 并向心；
连携引力环区域 150、碎片 0.45 秒从 r + 150 收到 0.4 r。敌人位移按时间插值近似（只为看图）。
每招一张：E0 / E1 / E2 左右并排（只放实际存在的档）；上半 1 倍（实机大小：1 美术像素 = 2 屏幕像素）、下半 2 倍放大；15 fps 原速循环。
光照近似：整体压暗到 AMBIENT，落点 / 起手各挂一盏短照地光（紫色径向提亮）；热芯（emit 点）近似发光层加一层柔光。

用法：python tools/pxplane_gif_angelina.py [--only atk,s1] [--out 目录]
"""
import argparse, json, math, os, sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pxplane_ang_art as A

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAIN = os.path.dirname(os.path.dirname(os.path.dirname(ROOT))) if ".claude" in ROOT else ROOT
PX = 2
GROUND = (36, 46, 48)
FONT = "C:/Windows/Fonts/msyh.ttc"
AMBIENT = 0.8
LIGHT_COL = (0.75, 0.6, 1.0)
MZ = (34, -80)
BSPD = 380.0 / 15.0
SQ = 0.72


def snap(v):
    return (round(v[0] / 2) * 2, round(v[1] / 2) * 2)


class Lib:
    def __init__(self):
        self.meta = {k: v for k, v in json.load(open(os.path.join(ROOT, "game", "data", "pxp_angelina.json"), encoding="utf-8")).items() if k != "_doc"}
        self.tex = {}

    def frame(self, k, fi, loop=False):
        m = self.meta[k]
        n = m["n"]
        if loop:
            fi %= n
        if fi < 0 or fi >= n:
            return None
        if k not in self.tex:
            self.tex[k] = Image.open(os.path.join(ROOT, "game", "art", "fx", "pxp", "pxp_an_%s.png" % k)).convert("RGBA")
        w, h = m["w"], m["h"]
        return self.tex[k].crop((fi * w, 0, (fi + 1) * w, h)), m


def sprite(path, n):
    im = Image.open(path).convert("RGBA")
    fw = im.width // n
    return im.crop((0, 0, fw, im.height))


def ease_out(u):
    return 1 - (1 - u) * (1 - u)


class Col:
    """一栏的时间轴（拍 = 1/15 秒），坐标一律世界像素。"""

    def __init__(self, tier, enemies, op=(80, 170), W=400, H=250):
        self.t = tier
        self.W, self.H = W, H
        self.op = op
        self.items = []      # 帧条件 {k, t0, gp, flip, gd, gy, loop, until}
        self.shots = []      # {p0, g0, p1, t0, t1, big}
        self.moves = []      # 敌人位移 (序号, 起拍, 拍数, dx, dy)
        self.lifts = []      # 托起 (序号, 起拍, 止拍, 高度)
        self.lights = []     # (x, y, 半径, 强度, 起拍, 拍数)
        self.pips = []       # (起拍, 止拍, n)
        self.links = []      # (c, r, t0)
        self.wells = []      # (c, t0)
        self.loops = []      # (k, gp, 起拍, 止拍, gy) 状态件
        self.e0 = [[float(x), float(y)] for x, y in enemies]
        self.flipped = 0

    def epos(self, i, tk):
        x, y = self.e0[i]
        for (j, t0, n, dx, dy) in self.moves:
            if j == i and tk >= t0:
                u = min(1.0, (tk - t0) / max(1, n))
                x += dx * ease_out(u)
                y += dy * ease_out(u)
        return x, y

    def eair(self, i, tk):
        h = 0.0
        for (j, t0, t1, hh) in self.lifts:
            if j == i and t0 <= tk < t1:
                k = min(1.0, (tk - t0) / 2.25, (t1 - tk) / 3.0)
                h = max(h, hh * (1 - (1 - k) * (1 - k)))
        return h

    def add(self, k, tk, gp, gd=False, flip=False, gy=None, loop=False, until=None):
        self.items.append({"k": k, "t0": tk, "gp": snap(gp), "flip": flip, "gd": gd, "gy": gp[1] if gy is None else gy, "loop": loop, "until": until})

    def pull(self, tk, c, r, dist, n=4):
        """把半径 r 内的敌人往 c 拉 dist（不越过中心）"""
        for i in range(len(self.e0)):
            x, y = self.epos(i, tk)
            d = math.hypot(x - c[0], y - c[1])
            if d <= r + 10 and d > 1:
                m = min(dist, max(0.0, d - 12))
                self.moves.append((i, tk, n, (c[0] - x) / d * m, (c[1] - y) / d * m))

    def shoot(self, tk, c, mode="n"):
        """一发重力弹：飞行（弹速 380）→ 落点画面 + 拉拢 + 精一停顿 + 精二失重井；返回落地拍"""
        p0 = (self.op[0] + MZ[0], self.op[1] + MZ[1])
        g0 = (self.op[0] + MZ[0], self.op[1])
        dist = math.hypot(c[0] - self.op[0], c[1] - self.op[1])
        n = max(2, round(dist / BSPD))
        self.shots.append({"p0": p0, "g0": g0, "p1": c, "t0": tk, "t1": tk + n, "big": mode == "s1"})
        lt = tk + n
        z = 0
        self.add("land_%s_e%d_z%d_up" % (mode, self.t, z), lt, c, gy=c[1] + 24)   # 同游戏 sk 24
        self.add("land_%s_e%d_z%d_gd" % (mode, self.t, z), lt, c, gd=True)
        self.lights.append((c[0], c[1] - 6, 110 if mode == "s1" else 80, 0.75 if mode == "s1" else 0.55, lt, 2))
        self.pull(lt, c, 100, 40 * (2 if mode == "s1" else 1))
        if self.t >= 2:   # 失重井：每 0.4 秒再拉 12、井心托起
            self.wells.append((c, lt))
            for q in range(3):
                bt = lt + 2 + q * 6
                self.pull(bt, c, 90, 12, 3)
                for i in range(len(self.e0)):
                    x, y = self.epos(i, bt + 2)
                    if math.hypot(x - c[0], y - c[1]) < 30 + 10:
                        self.lifts.append((i, bt, bt + 7, 22))
        return lt


# ---------------------------------------------------------------- 绘制

def render(lib, col, tk, ENEMY, OP):
    W, H = col.W, col.H
    img = Image.new("RGBA", (W, H), GROUND + (255,))
    rng = np.random.default_rng(7)
    g = np.asarray(img).copy()
    noise_ = rng.integers(-5, 6, size=(H // 2, W // 2, 1))
    g[..., :3] = np.clip(g[..., :3].astype(int) + np.repeat(np.repeat(noise_, 2, 0), 2, 1), 0, 255)
    img = Image.fromarray(g.astype(np.uint8), "RGBA")
    emit = Image.new("RGB", (W, H), (0, 0, 0))
    ed = ImageDraw.Draw(emit)
    dr = ImageDraw.Draw(img)

    def put_px(x, y, c, glow=False):
        x, y = snap((x, y))
        dr.rectangle([x, y, x + PX - 1, y + PX - 1], fill=c)
        if glow:
            ed.rectangle([x, y, x + PX - 1, y + PX - 1], fill=c[:3])

    def strip(k, fi, gp, flip=False, loop=False):
        r = lib.frame(k, fi, loop)
        if r is None:
            return
        fr, m = r
        if flip:
            fr = fr.transpose(Image.FLIP_LEFT_RIGHT)
        gx, gy = gp
        left = gx - (m["w"] - m["ox"]) * PX if flip else gx - m["ox"] * PX
        top = gy - m["oy"] * PX
        big = fr.resize((fr.width * PX, fr.height * PX), Image.NEAREST)
        l, t = int(left), int(top)
        img.alpha_composite(big, dest=(max(0, l), max(0, t)), source=(max(0, -l), max(0, -t)))
        for q in m["emit"][fi % m["n"]]:
            x = q[0] if not flip else m["w"] - 1 - q[0]
            ed.rectangle([l + x * PX, t + q[1] * PX, l + x * PX + PX - 1, t + q[1] * PX + PX - 1], fill=tuple(int(q[2][i:i + 2], 16) for i in (0, 2, 4)))

    # 贴地层：状态件（环带 / 场边）→ 一次性贴地件 → 井 → 悬浮竖线 → 弹投影
    for (k, gp, t0, t1, gy) in col.loops:
        if k.endswith("_gd") and t0 <= tk < t1:
            strip(k, tk, gp, loop=True)
    for it in col.items:
        if it["gd"] and tk >= it["t0"]:
            strip(it["k"], tk - it["t0"], it["gp"], it["flip"])
    for (c, t0) in col.wells:
        if tk >= t0:
            strip("well_z0_gd", tk - t0, snap(c))
    na = 0
    for i in range(len(col.e0)):
        h = col.eair(i, tk)
        if h > 4 and na < 12:
            na += 1
            x, y = col.epos(i, tk)
            strip("float_l_gd", tk + i, snap((x, y + 14 * 0.8)), loop=True)
    for s in col.shots:
        if s["t0"] <= tk < s["t1"]:
            k = (tk - s["t0"]) / (s["t1"] - s["t0"])
            gx = s["g0"][0] + (s["p1"][0] - s["g0"][0]) * k
            gy = s["g0"][1] + (s["p1"][1] - s["g0"][1]) * k
            strip("orb_sh_gd", 0, snap((gx, gy)))
    # 立起层：按脚底 y 排序
    sort = []
    for i in range(len(col.e0)):
        x, y = col.epos(i, tk)
        sort.append((y, "e", (i, x, y)))
    sort.append((col.op[1], "op", None))
    for (k, gp, t0, t1, gy) in col.loops:
        if k.endswith("_up") and t0 <= tk < t1:
            sort.append((gy, "loop", (k, gp)))
    for it in col.items:
        if not it["gd"] and tk >= it["t0"]:
            sort.append((it["gy"] + 1, "strip", it))
    for s in col.shots:
        if s["t0"] <= tk < s["t1"]:
            sort.append((s["p1"][1], "orb", s))
    for (t0, t1, n) in col.pips:
        if t0 <= tk < t1:
            sort.append((col.op[1] + 0.5, "pips", n))
    for (c, r, t0) in col.links:
        if t0 <= tk < t0 + 7:
            for j in range(3):
                q = link_pos(c, r, (tk - t0) / 15.0, j)
                sort.append((q[1] + 14, "lks", (c, r, t0, j)))
    sort.sort(key=lambda s: s[0])
    for _, kind, v in sort:
        if kind == "e":
            i, x, y = v
            h = col.eair(i, tk)
            ex, ey = snap((x, y))
            if h > 0:   # 影子随高度缩小变淡（同 world.gd + fx_pxplane_ang.air_look）
                hk = max(0.5, min(1.0, 1 - h / 50.0))
                rr = 14 * 0.9 * hk
                sh = Image.new("RGBA", (W, H), (0, 0, 0, 0))
                ImageDraw.Draw(sh).ellipse([ex - rr, ey + 11 - rr * 0.45, ex + rr, ey + 11 + rr * 0.45], fill=(0, 0, 0, int(255 * 0.35 * (0.4 + 0.6 * hk))))
                img.alpha_composite(sh)
                bob = 2 if (h > 18 and ((tk // 3 + i) % 2 == 1)) else 0
                ey -= int(round(h / 2) * 2) + bob
            img.alpha_composite(ENEMY, dest=(int(ex - ENEMY.width // 2), int(ey - ENEMY.height + 6)))
        elif kind == "op":
            img.alpha_composite(OP, dest=snap((col.op[0] - 64, col.op[1] - 120)))
        elif kind == "loop":
            strip(v[0], tk, v[1], loop=True)
        elif kind == "strip":
            strip(v["k"], tk - v["t0"], v["gp"], v["flip"])
        elif kind == "orb":
            s = v
            n = s["t1"] - s["t0"]
            k = (tk - s["t0"]) / n

            def arc(kk):
                return (s["p0"][0] + (s["p1"][0] - s["p0"][0]) * kk, s["p0"][1] + (s["p1"][1] - s["p0"][1]) * kk - math.sin(kk * math.pi) * 26)
            for (q, ci) in A.trail_px(None):   # 弹尾（每帧位移 1/4 拍的近似：采样间隔同游戏 0.05）
                kk = k - 0.05 * q * (15.0 / 15.0) * 1.0
                if kk > 0:
                    p = arc(kk)
                    put_px(p[0], p[1], A.hx(A.V[ci]))
            strip("orb_s1_e%d" % col.t if s["big"] else "orb_e%d" % col.t, tk, snap(arc(k)), loop=True)
        elif kind == "pips":
            head = snap((col.op[0], col.op[1] - 92))
            for (x, y, c) in A.pips_px(v, tk):
                put_px(head[0] + x * PX, head[1] + y * PX, A.hx(c), glow=c == A.V[7])
        elif kind == "lks":
            c, r, t0, j = v
            age = (tk - t0) / 15.0
            for (q, ci) in A.link_trail():   # 相邻采样点连线（同游戏）
                a2 = age - 0.01 * q
                if a2 <= 0:
                    break
                pa = link_pos(c, r, a2 + 0.01, j)
                pb = link_pos(c, r, a2, j)
                ns = max(1, int(math.hypot(pb[0] - pa[0], pb[1] - pa[1]) / PX))
                for s in range(ns + 1):
                    put_px(pa[0] + (pb[0] - pa[0]) * s / ns, pa[1] + (pb[1] - pa[1]) * s / ns, A.hx(A.V[ci]))
            strip("lk_shard_up", tk + j, snap(link_pos(c, r, age, j)), loop=True)
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


def link_pos(c, r, age, j):
    k = min(1.0, max(0.0, age / 0.45))
    rr = r + 150 + (r * 0.4 - r - 150) * k
    a = math.tau * (k + j / 3.0)
    return (c[0] + math.cos(a) * rr, c[1] + math.sin(a) * rr - 14)


def gif(lib, columns, n_ticks, path, title, zoom_c, ENEMY, OP):
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
            im = render(lib, col, tk, ENEMY, OP)
            sheet.paste(im, (x0, head))
            zx, zy = zoom_c
            sheet.paste(im.crop((int(zx - W / 4), int(zy - H / 4), int(zx + W / 4), int(zy + H / 4))).resize((W, H), Image.NEAREST), (x0, head + H + 4))
            d.text((x0 + 6, 5), lab, fill=(235, 225, 200), font=font)
            d.text((x0 + 6, head + H + 4 + H + 2), "上：1 倍（实机大小）  下：2 倍放大", fill=(140, 140, 140), font=sfont)
        d.text((sheet.width - 6 - d.textlength(title, font=sfont), 8), title, fill=(150, 150, 150), font=sfont)
        frames.append(sheet)
    pal = frames[len(frames) // 2].quantize(colors=255, method=Image.MEDIANCUT)
    q = [f.quantize(palette=pal, dither=Image.NONE) for f in frames]
    dur = [70 if i % 3 != 1 else 60 for i in range(len(q))]
    q[0].save(path, save_all=True, append_images=q[1:], duration=dur, loop=0, optimize=False, disposal=1)
    print(path, len(q), "帧", "%.0f KB" % (os.path.getsize(path) / 1024))


# ---------------------------------------------------------------- 每招的摆法

E_MAIN = [(250, 150), (276, 140), (264, 172), (300, 158), (232, 128), (318, 186), (296, 120), (226, 176), (336, 146), (210, 150)]
TIERS = {"atk": (0, 1, 2), "s1": (0, 1, 2), "s2": (1, 2), "s3": (2,), "late": (0, 1, 2)}


def sc_atk(t):
    c = Col(t, E_MAIN)
    c.shoot(2, (262, 152))
    c.shoot(19, (284, 160))
    c.shoot(36, (258, 146))
    return c


def sc_s1(t):
    c = Col(t, E_MAIN)
    mz = (c.op[0] + MZ[0], c.op[1] + MZ[1])
    c.add("s1cast_up", 1, mz, gy=c.op[1] + 0.2)
    c.lights.append((mz[0], mz[1], 90, 0.5, 1, 2))
    l1 = c.shoot(5, (262, 152), "s1")
    l2 = c.shoot(22, (284, 160), "s1")
    l3 = c.shoot(39, (258, 146), "s1")
    c.pips = [(2, 5, 3), (5, 22, 2), (22, 39, 1)]
    return c


def sc_s2(t):
    c = Col(t, [(80 + 150 * math.cos(a), 170 + 150 * math.sin(a) * 0.62) for a in (-0.5, -0.1, 0.35, 0.8, -0.9, 2.6, 3.4, 1.4, -1.6, 0.1)], op=(170, 140))
    cen = c.op
    c.add("bandop_z0_gd", 1, cen, gd=True)
    c.loops.append(("band_z0_gd", snap(cen), 6, 999, cen[1]))
    # 每 0.5 秒（7.5 拍）把场内敌人往环带 110 整形；绸带隔一拍出一次
    for q, bt in enumerate([1, 8, 16, 23, 31, 38]):
        for i in range(len(c.e0)):
            x, y = c.epos(i, bt)
            d = math.hypot(x - cen[0], y - cen[1])
            if 1 < d <= 150 + 10:
                gap = d - 110
                m = min(30, abs(gap))
                sgn = -1 if gap > 0 else 1
                c.moves.append((i, bt, 4, (x - cen[0]) / d * m * sgn, (y - cen[1]) / d * m * sgn))
        if q % 2 == 0:
            c.add("rib_e%d_z0_r%d_gd" % (t, [0, 90, 180, 270][(q // 2) % 4]), bt, cen, gd=True, flip=(q // 8) % 2 == 1)
    return c


def sc_s3(t):
    c = Col(t, E_MAIN + [(150, 120), (120, 215)], op=(150, 160))
    cen = c.op
    c.add("liftop_z0_gd", 1, cen, gd=True)
    c.add("blades_cast_up", 1, cen, gy=cen[1] - 2)
    c.loops.append(("lift_z0_gd", snap(cen), 7, 999, cen[1]))
    c.loops.append(("blades_up", snap(cen), 5, 999, cen[1] - 2))
    c.lights.append((cen[0], cen[1] - 40, 150, 0.6, 1, 2))
    for i in range(len(c.e0)):
        x, y = c.e0[i]
        if math.hypot(x - cen[0], y - cen[1]) <= 220:
            c.lifts.append((i, 2 + i % 3, 999, 30))
            c.moves.append((i, 2, 55, (cen[0] - x) * 0.3, (cen[1] - y) * 0.3))
    for bt in range(6, 60, 6):   # 碎石：每 6 拍 3 块（坐标哈希，同游戏 _rocks）
        for j in range(3):
            h1 = A.hf(bt // 6, j, 7)
            h2 = A.hf(bt // 6, j, 13)
            a = math.tau * (j / 3.0 + h1 * 0.3)
            rr = 220 * 0.85 * (0.3 + 0.65 * h2)
            at = (cen[0] + math.cos(a) * rr, cen[1] + math.sin(a) * rr * 0.72)
            c.add("rock_v%d_up" % ((bt // 6 + j) % 3), bt, at)
    return c


def sc_late(t):
    c = Col(t, E_MAIN)
    for k, bt in enumerate((2, 20, 38)):
        cc = [(262, 152), (284, 160), (258, 146)][k]
        lt = c.shoot(bt, cc)
        c.add("echo_z0_gd", lt + 5, cc, gd=True)             # 双重引力（0.3 秒后再拉一次）
        c.pull(lt + 5, cc, 100, 20)
        x, y = E_MAIN[[1, 3, 0][k]]
        c.add("splash_gd", lt, (x, y), gd=True)              # 扩散
        if k == 1:   # 致密：叠向中心 → 0.3 秒后坍缩爆开
            c.add("dense_in_gd", lt, cc, gd=True)
            c.add("dense_pop_up", lt + 5, cc, gy=cc[1] + 1)
            c.lights.append((cc[0], cc[1] - 8, 100, 0.6, lt + 5, 2))
    return c


def sc_link():
    W, H = 760, 660
    cen = (420, 330)
    ring = [(cen[0] + 260 * math.cos(a), cen[1] + 200 * math.sin(a)) for a in [i * 0.63 for i in range(10)]]
    inner = [(cen[0] + 50 * math.cos(a), cen[1] + 40 * math.sin(a)) for a in (0.3, 2.2, 4.1)]
    c = Col(2, ring + inner, op=(140, 360), W=W, H=H)
    c.links.append((cen, 150, 3))
    for i in range(len(ring)):   # 区域外 180 内的敌人一路带进来（到 0.45 r）
        x, y = ring[i]
        d = math.hypot(x - cen[0], y - cen[1])
        to = (cen[0] + (x - cen[0]) / d * 150 * 0.45, cen[1] + (y - cen[1]) / d * 150 * 0.45)
        c.moves.append((i, 3, 7, to[0] - x, to[1] - y))
    c.add("lk_land_up", 10, cen, gy=cen[1] + 1)
    c.add("lk_land_gd", 10, cen, gd=True)
    c.lights.append((cen[0], cen[1] - 12, 150, 0.7, 10, 2))
    return c


NAMES = {"atk": "普攻「重力弹」", "s1": "S1「秘杖·速充模式」", "s2": "S2「秘杖·微粒模式」", "s3": "S3「秘杖·反重力模式」", "late": "后期：扩散 + 双重引力 + 致密"}
SCENES = {"atk": (sc_atk, 52, (262, 150)), "s1": (sc_s1, 54, (262, 140)), "s2": (sc_s2, 48, (250, 140)), "s3": (sc_s3, 60, (180, 140)),
          "late": (sc_late, 52, (262, 150))}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    ap.add_argument("--out", default=os.path.join(MAIN, "Claude outputs", "pxplane_angelina_1105", "gif"))
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    lib = Lib()
    en = sprite(os.path.join(ROOT, "game", "art", "enemies", "offspring", "e_offspring@2x.png"), 4)
    arr = np.asarray(en).astype(np.float32)
    arr[..., :3] = arr[..., :3] * 0.32 + np.array([10, 12, 14])
    ENEMY = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")
    OP = sprite(os.path.join(ROOT, "game", "art", "operators", "angelina", "op_angelina_idle@2x.png"), 8)
    only = set(x for x in a.only.split(",") if x)
    title = "安洁莉娜 · 转平面 · 15 fps 原速"
    for name, (fn, n, zc) in SCENES.items():
        if only and name not in only:
            continue
        cols = [("%s  精英 %d" % (NAMES[name], t), fn(t)) for t in TIERS[name]]
        gif(lib, cols, n, os.path.join(a.out, "angelina_%s.gif" % name), title, zc, ENEMY, OP)
    if not only or "link" in only:
        gif(lib, [("连携技「引力环」（不分档）", sc_link())], 24, os.path.join(a.out, "angelina_link.gif"), title, (420, 330), ENEMY, OP)


if __name__ == "__main__":
    main()
