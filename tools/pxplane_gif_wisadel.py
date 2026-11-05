#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""维什戴尔转平面（docs/274）送审 GIF：上 GCP 前先给用户看，只用 Python、不开 Godot。

帧条直接读 tools/pxplane_bake_wisadel.py 烤出的 game/art/fx/pxp/pxp_wd_*.png + game/data/pxp_wisadel.json（与游戏同一份）；
炮弹、落点准星、四角括号、残影标记用 tools/pxplane_wisadel_art.py 里与 fx_pxplane_wd.gd 同算法的 Python 版逐格画。
摆法照游戏：炮口 = 脚底 + (14, −34)，炮弹 1500 px/s、最高拱 18；爆炸半径 66（精一起 × 1.15 = 76），余震 0.45 秒后 × 1.2；
精一被炸死的敌人留残影 0.25 秒后殉爆（× 0.8）、主目标挂标记；精二两个魂灵之影悬在肩后，每发炮击跟一炮（落点画成 0.7 的暗红殉爆）；
S1 三发强化炮 × 1.375；S2 × 1.25（攻击间隔 × 0.8，后半段 4 连发）；S3 巨炮 × 2.5、间隔 × 0.6。
每招一张：E0 / E1 / E2 左右并排（只放实际存在的档）；上半 1 倍（实机大小：1 美术像素 = 2 屏幕像素）、下半 2 倍放大；15 fps 原速循环。
光照近似：整体压暗到 AMBIENT，爆点挂一盏短照地光；热芯（emit 点）近似发光层加一层柔光。Noita 颗粒在 GIF 里按同材质近似画（rock 碎块 / ember 火星）。

用法：python tools/pxplane_gif_wisadel.py [--only atk,s1] [--out 目录]
"""
import argparse, json, math, os, sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pxplane_wisadel_art as A

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAIN = os.path.dirname(os.path.dirname(os.path.dirname(ROOT))) if ".claude" in ROOT else ROOT
PX = 2
GROUND = (36, 46, 48)
FONT = "C:/Windows/Fonts/msyh.ttc"
AMBIENT = 0.8
FIRE_L = (1.0, 0.42, 0.28)
SOUL_L = (0.8, 0.22, 0.2)
SQ = 0.72
TIP = (14, -34)


def pick_dir(ang_deg):
    a = (ang_deg + 180) % 360 - 180
    flip = False
    if abs(a) > 90:
        a = (180 - a + 180) % 360 - 180
        flip = True
    best = 0
    for d in A.DIRS:
        if abs(a - d) < abs(a - best):
            best = d
    return best, flip


def snap(v):
    return (round(v[0] / 2) * 2, round(v[1] / 2) * 2)


def pick(arr, r_world):
    best = arr[0]
    for x in arr:
        if x * 2 <= r_world * 1.1 + 0.01:
            best = x
    return best


class Lib:
    def __init__(self):
        self.meta = {k: v for k, v in json.load(open(os.path.join(ROOT, "game", "data", "pxp_wisadel.json"), encoding="utf-8")).items() if k != "_doc"}
        self.tex = {}

    def frame(self, k, fi):
        m = self.meta[k]
        if fi < 0 or fi >= m["n"]:
            return None
        if k not in self.tex:
            self.tex[k] = Image.open(os.path.join(ROOT, "game", "art", "fx", "pxp", "pxp_wd_%s.png" % k.replace("_d-", "_dm").lower())).convert("RGBA")
        w, h = m["w"], m["h"]
        return self.tex[k].crop((fi * w, 0, (fi + 1) * w, h)), m


def sprite(path, n, i=0):
    im = Image.open(path).convert("RGBA")
    fw = im.width // n
    return im.crop((fw * i, 0, fw * (i + 1), im.height))


class Grain:
    def __init__(self, mat, gp, h, v, vh, life, sz, t0):
        self.mat, self.gp, self.h, self.v, self.vh, self.life, self.sz, self.t0 = mat, gp, h, v, vh, life, sz, t0


class Col:
    """一栏的时间轴（拍 = 1/15 秒），坐标一律世界像素"""

    def __init__(self, tier, enemies, op=(90, 170), W=440, H=280):
        self.t = tier
        self.W, self.H = W, H
        self.items = []      # 帧条件
        self.shells = []     # {kind, from, to, t0, t1, r, s1}
        self.enemies = [[float(x), float(y), 10 ** 9] for x, y in enemies]
        self.op = op
        self.lights = []
        self.marks = []      # (敌人序号, 起拍, 止拍, gift)
        self.lines = []      # (a, b, 拍, 括号)
        self.grains = []
        self.souls = tier >= 2
        self.seed = 7 + tier
        self.drops = []      # 连携下坠炮弹 (落点, 起拍)
        self.fogs = []       # 贴地薄雾 (c, r, 起拍, 拍数)
        self.lib = None      # 挑火星档用（同屏火星封顶 60，同 fx_pxplane_wd._up_sp）
        self.emit_log = {}

    def add(self, k, tk, gp, flip=False, gd=False, gy=None, hold=False):
        self.items.append({"k": k, "t0": tk, "gp": snap(gp), "flip": flip, "gd": gd, "gy": gp[1] if gy is None else gy, "hold": hold})

    def add_sp(self, k, tk, gp, gy=None):
        """带火星的帧条：同屏火星总数 ≤ 60，放不下全量换 _h / _q（同游戏）"""
        live = sum(it.get("nsp", 0) for it in self.items if it.get("nsp") and it["t0"] <= tk < it["t0"] + LIB.meta[it["k"]]["n"])
        pick = k
        for suf in ("", "_h", "_q"):
            if k + suf not in LIB.meta:
                continue
            pick = k + suf
            if live + LIB.meta[pick].get("nsp", 0) <= 60:
                break
        self.add(pick, tk, gp, gy=gy)
        self.items[-1]["nsp"] = LIB.meta[pick].get("nsp", 0)

    def fog(self, tk, c, r, life_s):
        """贴地薄雾：和近处还在的合并（刷新、取大），至多 6 片"""
        R2 = r * 0.9
        for i, (fc, fr, f0, fl) in enumerate(self.fogs):
            if math.hypot(fc[0] - c[0], fc[1] - c[1]) < max(fr, R2) * 0.6 and tk - f0 < fl:
                self.fogs[i] = (fc, max(fr, R2), tk, max(fl, round(life_s * 15)))
                return
        self.fogs.append((tuple(c), R2, tk, round(life_s * 15)))

    def light(self, at, r, i, tk, n=2, col=FIRE_L):
        self.lights.append((at[0], at[1] + 6, r, i, tk, n, col))

    def grain(self, mat, at, gy, n, tk, spd=1.0):
        rnd = np.random.default_rng(self.seed + tk * 31 + int(at[0]))
        self.seed += 1
        for i in range(n):
            a = rnd.uniform(0, math.tau)
            sp = rnd.uniform(50, 130) * spd if mat == "rock" else rnd.uniform(170, 320) * spd
            vh = rnd.uniform(110, 230) if mat == "rock" else rnd.uniform(60, 180)
            sz = 4 + 2 * int(rnd.random() < 0.5) if mat == "rock" else 2 + 2 * int(rnd.random() < 0.5)
            self.grains.append(Grain(mat, (at[0], gy), max(0.0, gy - at[1]), (math.cos(a) * sp, math.sin(a) * sp * SQ), vh, rnd.uniform(0.8, 1.2) * (1.0 if mat == "rock" else 0.42), sz, tk))

    def soul_pos(self, k):
        side = -1 if k == 0 else 1
        return (self.op[0] + side * 32 - 6, self.op[1] - 78)

    def hits(self, c, r, tk):
        return [i for i, e in enumerate(self.enemies) if e[2] > tk and math.hypot(e[0] - c[0], (e[1] - c[1])) < r + 10]

    def fire(self, tk, tg, kind="n", size=1.0, frm=None, s1=False, kill=(), quake=True):
        """一发炮弹：tg = 敌人序号或坐标；kind n / g（巨炮）/ exec（S2）/ soul；kill = 这发炸死的敌人序号"""
        to = self.enemies[tg][:2] if isinstance(tg, int) else tg
        own = frm is None
        if own:
            frm = (self.op[0] + TIP[0], self.op[1] + TIP[1])
        dist = math.hypot(to[0] - frm[0], to[1] - frm[1])
        n = max(1, round(min(0.3, max(0.08, dist / 1500.0)) * 15))
        base_r = 66 * (1.15 if self.t >= 1 else 1.0)
        r = base_r * size
        self.shells.append({"kind": kind, "from": frm, "to": to, "t0": tk, "t1": tk + n, "r": r, "s1": s1})
        if own:
            d, fl = pick_dir(math.degrees(math.atan2(to[1] - frm[1], to[0] - frm[0])))
            self.add(("mzg_d%d" if kind == "g" else "mz_d%d") % d, tk, frm, fl, gy=self.op[1] + 1)
        else:
            self.add("smz", tk, frm, gy=frm[1] + 80)
        land = tk + n
        self.boom(land, to, r, kind, s1)
        for ei in kill:
            self.enemies[ei][2] = land
            if self.t >= 1 and kind != "soul":
                e = self.enemies[ei]
                self.add("shade", land, (e[0], e[1]), gy=e[1] + 1)
                self.boom(land + 4, (e[0], e[1]), r * 0.8, "shade")
        if self.t >= 1 and isinstance(tg, int) and kind != "soul" and tg not in kill:
            self.marks.append((tg, land, land + 60, True))
        if kind == "soul" and isinstance(tg, int) and tg not in kill:
            self.marks.append((tg, land, land + 60, False))
        if quake:
            self.boom(land + 7, to, r * 1.2, "quake", rings=False)
        if own and self.souls and kind in ("n", "g"):
            for k in range(2):
                near = [i for i, e in enumerate(self.enemies) if e[2] > tk and i != tg and math.hypot(e[0] - to[0], e[1] - to[1]) < 120]
                pick_e = near[k] if k < len(near) else tg
                st = tk + 1 + k * 1 + 1
                self.fire(st, pick_e, "soul", 1.0, frm=self.soul_pos(k), quake=False)
        return land

    def boom(self, tk, c, r, kind, s1=False, rings=False):
        c = tuple(c)
        if kind == "quake":
            if rings:
                for j in range(3):
                    self.add("q_r%d" % pick(A.Q_R, r * [0.6, 0.8, 1.0][j]), tk + 2 * j, c, gd=True)
            else:
                self.add("q_r%d" % pick(A.Q_R, r), tk, c, gd=True)
            self.light((c[0], c[1] - 6), min(140, max(80, r * 0.9)), 0.38, tk)
            self.grain("rock", (c[0], c[1] - 4), c[1] + 2, 2, tk)
        elif kind in ("shade", "soul"):
            sb = pick(A.SB_R, r * (0.7 if kind == "soul" else 1.0))
            self.add("sb_r%d" % sb, tk, c, gy=c[1] + 1)
            self.light((c[0], c[1] - 16), min(140, max(90, r * 1.4)), 0.55, tk, col=SOUL_L)
            self.grain("rock", (c[0], c[1] - 12), c[1] + 2, 2 if kind == "soul" else 3, tk)
        elif kind == "g":
            s3 = pick(A.S3_R, r)
            self.add_sp("dawn_r%d" % s3, tk, c, gy=c[1] + 2)
            self.fog(tk, c, r, 0.8)
            self.add("dawng_r%d" % s3, tk, c, gd=True, hold=True)
            self.light((c[0], c[1] - 30), min(230, r * 1.15), 0.85, tk, 3)
            self.grain("rock", (c[0], c[1] - 40), c[1] + 2, 6, tk, 1.4)
            self.grain("streak", (c[0], c[1] - 30), c[1] + 2, 10, tk, 1.4)
        elif kind == "exec":
            s2 = pick(A.S2_R, r)
            self.add_sp("dome_r%d" % s2, tk, c, gy=c[1] + 1)
            self.fog(tk, c, r, 0.6)
            self.add("st_r%d_e%d" % (s2, 2 if self.t >= 2 else 1), tk, c, gd=True, hold=True)
            self.light((c[0], c[1] - 12), min(180, r * 1.6), 0.68, tk)
            self.grain("rock", (c[0], c[1] - 14), c[1] + 2, 2, tk, 1.2)
            self.grain("streak", (c[0], c[1] - 10), c[1] + 2, 6, tk, 1.2)
        elif s1:
            p1 = pick(A.S1_R, r)
            self.add_sp("pil_r%d_e%d" % (p1, self.t), tk, c, gy=c[1] + 2)
            self.fog(tk, c, r, 0.7)
            self.add("sc_r%d" % pick([22, 26, 30, 34, 38, 43, 48, 50, 56, 62], r), tk, c, gd=True, hold=True)
            self.light((c[0], c[1] - 36), min(190, r * 1.7), 0.75, tk)
            self.grain("rock", (c[0], c[1] - 30), c[1] + 2, 4, tk, 1.25)
            self.grain("streak", (c[0], c[1] - 24), c[1] + 2, 8, tk, 1.25)
        else:
            bk = pick(A.BOOM_R, r)
            self.add_sp("boom_r%d" % bk, tk, c, gy=c[1] + 1)
            self.fog(tk, c, r, 0.55)
            self.add(("sc2_r%d" if self.t >= 2 else "sc_r%d") % bk, tk, c, gd=True, hold=True)
            self.light((c[0], c[1] - 20), min(150, max(100, r * 1.6)), 0.6, tk)
            self.grain("rock", (c[0], c[1] - 18), c[1] + 2, 2, tk)
            self.grain("streak", (c[0], c[1] - 14), c[1] + 2, 4, tk)


# ---------------------------------------------------------------- 绘制

ENEMY = OP = SOUL_SPR = LIB = None


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

    def strip(k, fi, gp, flip=False, alpha=None):
        r = lib.frame(k, fi)
        if r is None:
            return
        fr, m = r
        if flip:
            fr = fr.transpose(Image.FLIP_LEFT_RIGHT)
        gx, gy = gp
        left = gx - (m["w"] - m["ox"]) * PX if flip else gx - m["ox"] * PX
        top = gy - m["oy"] * PX
        big = fr.resize((fr.width * PX, fr.height * PX), Image.NEAREST)
        if alpha is not None and alpha < 1.0:
            a = np.asarray(big).copy()
            a[..., 3] = (a[..., 3] * alpha).astype(np.uint8)
            big = Image.fromarray(a, "RGBA")
        l, t = int(left), int(top)
        if l >= W or t >= H or l + big.width <= 0 or t + big.height <= 0:
            return
        img.alpha_composite(big, dest=(max(0, l), max(0, t)), source=(max(0, -l), max(0, -t)))
        if alpha is None or alpha > 0.5:
            for q in m["emit"][fi]:
                x = q[0] if not flip else m["w"] - 1 - q[0]
                ed.rectangle([l + x * PX, t + q[1] * PX, l + x * PX + PX - 1, t + q[1] * PX + PX - 1], fill=tuple(int(q[2][i:i + 2], 16) for i in (0, 2, 4)))

    def draw_item(it):
        fi = tk - it["t0"]
        if fi < 0:
            return
        n = lib.meta[it["k"]]["n"]
        if it["hold"]:
            age = (fi - n) / 15.0
            if age > 0.8:
                return
            strip(it["k"], min(fi, n - 1), it["gp"], it["flip"], max(0.0, 1.0 - age / 0.8) if age > 0 else None)
        else:
            strip(it["k"], fi, it["gp"], it["flip"])

    # 地面层：准星 / 括号 / 弹影 / 贴地件
    for s in col.shells:
        if s["t0"] <= tk < s["t1"]:
            k = (tk - s["t0"]) / max(1, s["t1"] - s["t0"])
            c0 = snap(s["to"])
            if s["kind"] not in ("soul", "x"):
                for (x, y, c) in A.reticle_px(s["r"] * 0.5, k, tk):
                    put_px(c0[0] + x * PX, c0[1] + y * PX, c)
                if s["s1"] or s["kind"] == "exec":
                    for (x, y, c) in A.bracket_px(s["r"] * 0.25, tk):
                        put_px(c0[0] + x * PX, c0[1] + y * PX, c)
            lift = 82 if s["kind"] == "soul" else (18 if s["kind"] == "x" else 34)
            gx = s["from"][0] + (s["to"][0] - s["from"][0]) * k
            gy = s["from"][1] + lift + (s["to"][1] - s["from"][1] - lift) * k
            for dx in (-2, 0, 2):
                put_px(gx + dx, gy, A.SMOKE[0], a=0.55)
    if col.fogs:
        arr = np.asarray(img).astype(np.float32)
        yy0, xx0 = np.mgrid[0:H, 0:W].astype(np.float32)
        acc = np.zeros((H, W), np.float32)
        for (fc, fr, f0, fl) in col.fogs:
            if not (f0 <= tk < f0 + fl):
                continue
            u = (tk - f0) / fl
            a = 0.2 * (1 - u * u) * min(1.0, (tk - f0) / 1.2 + 0.3)
            rr = fr * (0.75 + 0.25 * math.sqrt(u))
            dd = np.sqrt((xx0 - fc[0]) ** 2 + ((yy0 - fc[1]) / 0.72) ** 2)
            for q in range(3):
                acc += (dd <= rr * (1 - 0.28 * q)) * (a / 3.0)
        acc = np.clip(acc, 0, 1)[..., None]
        arr[..., :3] = arr[..., :3] * (1 - acc) + np.array([77, 10, 10], np.float32) * acc
        img = Image.fromarray(arr.astype(np.uint8), "RGBA")
        dr = ImageDraw.Draw(img)
    for (dc, d0) in col.drops:
        if d0 <= tk < d0 + 6:
            kd = min(1.0, (tk - d0) / 5.25)
            c0 = snap(dc)
            for (x, y, c) in A.reticle_px(30, kd, tk):
                put_px(c0[0] + x * PX, c0[1] + y * PX, c)
    for it in col.items:
        if it["gd"]:
            draw_item(it)

    # 排序层
    sort = []
    for e in col.enemies:
        if tk < e[2]:
            sort.append((e[1], "e", e))
    sort.append((col.op[1], "op", None))
    if col.souls:
        for k in range(2):
            sp = col.soul_pos(k)
            sort.append((col.op[1] - 1, "soul", (sp, k)))
    for it in col.items:
        if not it["gd"]:
            sort.append((it["gy"] + 1, "it", it))
    for s in col.shells:
        if s["t0"] <= tk < s["t1"]:
            k = (tk - s["t0"]) / max(1, s["t1"] - s["t0"])
            lift = 82 if s["kind"] == "soul" else (18 if s["kind"] == "x" else 34)
            sort.append((s["from"][1] + lift + (s["to"][1] - s["from"][1] - lift) * k + 1, "shell", (s, k)))
    for (dc, d0) in col.drops:
        if d0 <= tk < d0 + 6:
            sort.append((dc[1] + 1, "drop", (dc, d0)))
    sort.sort(key=lambda s: s[0])
    for _, kind, v in sort:
        if kind == "e":
            img.alpha_composite(ENEMY, dest=(int(v[0] - ENEMY.width // 2), int(v[1] - ENEMY.height + 6)))
        elif kind == "op":
            img.alpha_composite(OP, dest=snap((col.op[0] - 64, col.op[1] - 120)))
        elif kind == "soul":
            (sx, sy), k = v
            sy += round(math.sin(tk / 15.0 * 2.2 + k * 2.0) * 2) * 2
            img.alpha_composite(SOUL_SPR, dest=snap((sx - SOUL_SPR.width // 2, sy - SOUL_SPR.height // 2)))
        elif kind == "it":
            draw_item(v)
        elif kind == "drop":
            (dc, d0) = v
            u = min(1.0, (tk - d0) / 5.25)
            hd = snap((dc[0], dc[1] - 240 * (1 - u * u) - 6))
            for (x, y, c) in A.drop_px(tk):
                put_px(hd[0] + x * PX, hd[1] + y * PX, c, glow=1 <= y <= 2)
        elif kind == "shell":
            s, k = v
            fr, to = s["from"], s["to"]
            dist = math.hypot(to[0] - fr[0], to[1] - fr[1]) or 1.0
            p = (fr[0] + (to[0] - fr[0]) * k, fr[1] + (to[1] - fr[1]) * k - math.sin(k * math.pi) * min(18, dist * 0.05))
            d = ((to[0] - fr[0]) / dist, (to[1] - fr[1]) / dist)
            nv = (-d[1], d[0])
            hd = snap(p)
            kk = "x" if s["kind"] == "x" else "g" if s["kind"] == "g" else ("soul" if s["kind"] == "soul" else ("s1" if s["s1"] or s["kind"] == "exec" else "n"))
            for (q, w, c) in A.shell_px(d[0], d[1], kk, tk):
                put_px(hd[0] - d[0] * q * PX + nv[0] * w * PX, hd[1] - d[1] * q * PX + nv[1] * w * PX, c, glow=q <= -1 and abs(w) <= 1)
    # 颗粒（近似 fx_recipe 的 rock / ember）
    for gr in col.grains:
        age = (tk - gr.t0) / 15.0
        if age < 0 or age > gr.life + 0.5:
            continue
        g_ = 1100.0 if gr.mat == "rock" else 520.0
        tt = min(age, gr.life)
        h = gr.h + gr.vh * tt - 0.5 * g_ * tt * tt
        landed = h <= 0
        if landed:
            tl = max(0.0, (gr.vh + math.sqrt(max(0.0, gr.vh ** 2 + 2 * g_ * gr.h))) / g_)
            tt = min(tt, tl)
            h = 0
            if age - tl > 0.55:
                continue
        x = gr.gp[0] + gr.v[0] * tt
        y = gr.gp[1] + gr.v[1] * tt - h
        u = min(1.0, age / gr.life)
        if gr.mat == "rock":
            c = "#8e2418" if u < 0.12 else "#2e2224"
        else:
            c = "#ffa868" if u < 0.2 else ("#c41e18" if u < 0.55 else "#6a1410")
        sz = gr.sz
        xx, yy = snap((x, y))
        if gr.mat != "rock" and not landed:   # 火星线：沿速度方向拖一小段（同 fx_recipe streak）
            vx, vy = gr.v[0], gr.v[1] - (gr.vh - g_ * tt)
            vl = math.hypot(vx, vy) or 1.0
            tl = max(4.0, min(18.0, vl * 0.05))
            dr.line([xx, yy, xx - vx / vl * tl, yy - vy / vl * tl], fill=A.hx(c), width=max(2, sz // 2 * 2))
            continue
        dr.rectangle([xx, yy, xx + sz - 1, yy + (sz if not landed else max(2, sz - 2)) - 1], fill=A.hx(c))
    # 残影标记
    for (ei, a0, a1, gift) in col.marks:
        e = col.enemies[ei]
        if not (a0 <= tk < a1) or tk >= e[2]:
            continue
        c0 = snap((e[0], e[1] - 12 - 18))
        for (x, y, c) in A.mark_px(tk + ei, gift):
            put_px(c0[0] + x * PX, c0[1] + y * PX, c)
    for (a, b, t0, br) in col.lines:
        f = tk - t0
        if 0 <= f <= 2:
            n = max(1, int(math.hypot(b[0] - a[0], b[1] - a[1]) / PX))
            for i in range(n + 1):
                if f == 2 and i % 2:
                    continue
                put_px(a[0] + (b[0] - a[0]) * i / n, a[1] + (b[1] - a[1]) * i / n, [A.FIRE[1], A.FIRE[3], A.FIRE[5]][f], glow=f == 0)
            if br:
                for (x, y, c) in A.bracket_px(10, tk):
                    put_px(snap(b)[0] + x * PX, snap(b)[1] + y * PX, c)
    col.emit_log[tk] = int((np.asarray(emit).max(axis=2) > 0).sum() / (PX * PX))   # 这一拍的 emit 点数（美术像素）
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
        d.text((sheet.width - 6 - d.textlength(title, font=sfont), head + H + 4 + H + 2), title, fill=(150, 150, 150), font=sfont)
        frames.append(sheet)
    pick_ = frames[:: max(1, len(frames) // 8)]
    mos = Image.new("RGB", (pick_[0].width, pick_[0].height * len(pick_)))
    for i, f in enumerate(pick_):
        mos.paste(f, (0, i * f.height))
    pal = mos.quantize(colors=255, method=Image.MEDIANCUT)
    q = [f.quantize(palette=pal, dither=Image.NONE) for f in frames]
    dur = [70 if i % 3 != 1 else 60 for i in range(len(q))]
    q[0].save(path, save_all=True, append_images=q[1:], duration=dur, loop=0, optimize=False, disposal=1)
    print(os.path.basename(path), len(q), "帧", "%.0f KB" % (os.path.getsize(path) / 1024))


# ---------------------------------------------------------------- 每招的摆法

E_MAIN = [(250, 160), (276, 140), (268, 196), (310, 170), (300, 120), (332, 206), (350, 150), (226, 130), (340, 110), (222, 196)]
TIERS = {"atk": (0, 1, 2), "s1": (0, 1, 2), "s2": (1, 2), "s3": (2,), "late": (0, 1, 2)}


def sc_atk(t):
    c = Col(t, E_MAIN)
    c.fire(2, 0, kill=(7,) if t >= 1 else ())
    c.fire(23, 3, kill=(4,) if t >= 1 else ())
    c.fire(44, 2)
    return c


def sc_s1(t):
    c = Col(t, E_MAIN)
    c.add("glint", 1, (c.op[0] + TIP[0], c.op[1] + TIP[1]), gy=c.op[1] + 2)
    c.light((c.op[0] + TIP[0], c.op[1] + TIP[1]), 80, 0.55, 1)
    for k, (tk, tg) in enumerate([(4, 0), (25, 3), (46, 5)]):
        c.fire(tk, tg, size=1.375, s1=True, kill=((7,) if k == 0 else ((4,) if k == 1 else ())) if t >= 1 else ())
    return c


def sc_s2(t):
    c = Col(t, E_MAIN)
    c.add("glint", 1, (c.op[0] + TIP[0], c.op[1] + TIP[1]), gy=c.op[1] + 2)
    c.fire(3, 0, "exec", 1.25, kill=(7,))
    for j, tg in enumerate([3, 6, 2, 9]):   # 后半段：随机索敌 4 连发（间隔 0.2 秒）
        c.fire(20 + 3 * j, tg, "exec", 1.25)
    return c


def sc_s3(t):
    c = Col(t, [(330, 150), (360, 128), (352, 180), (390, 160), (300, 120), (400, 196), (300, 186), (420, 136)], op=(80, 160), W=520, H=320)
    c.add("glintb", 1, (c.op[0] + TIP[0], c.op[1] + TIP[1]), gy=c.op[1] + 2)
    c.light((c.op[0] + TIP[0], c.op[1] + TIP[1]), 100, 0.55, 1)
    c.fire(4, (330, 160), "g", 2.5, kill=(4, 6))
    c.fire(17, (350, 168), "g", 2.5, kill=(0, 2))
    return c


def sc_late(t):
    c = Col(t, E_MAIN)
    for tk, tg in [(2, 0), (23, 3)]:
        c.fire(tk, tg, quake=True)
        n = 1 + t   # 额外弹：每档多一发，射向另外的敌人
        for j in range(n):
            e = c.enemies[[7, 6, 9][j]]
            frm = (c.op[0], c.op[1] - 18)
            dist = math.hypot(e[0] - frm[0], e[1] + 0 - frm[1])
            ln = max(1, round(dist / 560.0 * 15))
            c.shells.append({"kind": "x", "from": frm, "to": (e[0], e[1] - 18), "t0": tk + 1 + j, "t1": tk + 1 + j + ln, "r": 10, "s1": False})
            c.add("xpop", tk + 1 + j + ln, (e[0], e[1]), gy=e[1] + 1)
            if j == 0:
                c.grain("streak", (e[0], e[1] - 12), e[1] + 2, 2, tk + 1 + j + ln)
                c.light((e[0], e[1] - 10), 80, 0.4, tk + 1 + j + ln)
    return c


def sc_branch():
    """节点（精二）：余烬未冷（余震三圈）+ 续燃（落点吸向残影：引线 + 括号）+ 礼尚往来（第二发打次优目标）+ 余响（同一处再震一次，× 1.25）"""
    c = Col(2, E_MAIN)
    c.souls = False
    land = c.fire(2, 0, size=1.375, s1=True, kill=(7,), quake=False)
    c.boom(land + 7, c.enemies[0][:2], 66 * 1.15 * 1.375 * 1.2, "quake", rings=True)
    c.lines.append(((c.enemies[3][0] + 30, c.enemies[3][1] + 10), tuple(c.enemies[3][:2]), 24, True))
    land2 = c.fire(24, 3, size=1.375, s1=True, quake=False)
    c.boom(land2 + 7, c.enemies[3][:2], 66 * 1.15 * 1.375 * 1.2, "quake", rings=True)
    land3 = c.fire(46, 2)
    c.fire(46, 9, size=0.85)
    c.boom(land3 + 7 + 4, c.enemies[2][:2], 66 * 1.15 * 1.2 * 1.25, "quake")
    return c


def sc_link():
    """连携「天降厚礼」（skill_link l_wisadel，link/v2 缺省，不分档）：队长技能后 1 秒内区域里倒下的敌人处，0.35 秒后炸开（半径 60）。
    画面：她朝天开一炮 → 每个死者处一发炮弹拖着黑红尾迹从天上砸下（落点准星收拢）→ 落地矮爆 + 三道余震涟漪依次推开"""
    c = Col(2, E_MAIN)
    c.souls = False
    c.add("mzg_d-90", 1, (c.op[0] + 4, c.op[1] - 48), gy=c.op[1] + 1)
    c.light((c.op[0] + 4, c.op[1] - 48), 100, 0.55, 1)
    for j, (ei, tk) in enumerate([(0, 4), (3, 7), (2, 9), (5, 13)]):
        e = c.enemies[ei]
        c.enemies[ei][2] = tk
        c.drops.append(((e[0], e[1]), tk))
        c.add_sp("lk_up", tk + 5, (e[0], e[1]), gy=e[1] + 1)
        c.fog(tk + 5, (e[0], e[1]), 60, 0.6)
        c.add("lk_gd", tk + 5, (e[0], e[1]), gd=True)
        if j % 2 == 0:
            c.light((e[0], e[1] - 16), 130, 0.7, tk + 5)
        c.grain("rock", (e[0], e[1] - 14), e[1] + 2, 3, tk + 5, 1.2)
        c.grain("streak", (e[0], e[1] - 10), e[1] + 2, 3, tk + 5, 1.2)
    return c


def sc_late8():
    """8:00 后期混战近似（只看刺眼程度）：960×540 1 倍，45 只敌人，精二维什戴尔 + 魂灵之影 + 礼尚往来 + 后期额外弹，攻速约 0.8 秒一发，余震、残影殉爆照常"""
    rnd = np.random.default_rng(800)
    en = [(float(rnd.uniform(380, 900)), float(rnd.uniform(140, 500))) for _ in range(45)]
    c = Col(2, en, op=(220, 320), W=960, H=540)
    alive = list(range(len(en)))
    tk = 2
    while tk < 70:
        ts = sorted(alive, key=lambda i: math.hypot(en[i][0] - 220, en[i][1] - 320))
        if len(ts) < 3:
            break
        k1 = [ts[3]] if len(ts) > 6 and tk % 3 == 0 else []
        for i in k1:
            alive.remove(i)
        c.fire(tk, ts[0], kill=tuple(k1))
        c.fire(tk, ts[2], size=0.85, quake=True)
        for j in range(3):
            e = c.enemies[ts[4 + j]]
            frm = (c.op[0], c.op[1] - 18)
            ln = max(1, round(math.hypot(e[0] - frm[0], e[1] - frm[1]) / 560.0 * 15))
            c.shells.append({"kind": "x", "from": frm, "to": (e[0], e[1] - 18), "t0": tk + 1 + j, "t1": tk + 1 + j + ln, "r": 10, "s1": False})
            c.add("xpop", tk + 1 + j + ln, (e[0], e[1]), gy=e[1] + 1)
        tk += 12
    return c


NAMES = {"atk": "普攻「炮击」（精一：残影 / 标记，精二：魂炮）", "s1": "S1「定点清算」", "s2": "S2「饱和复仇」", "s3": "S3「爆裂黎明」", "late": "后期额外弹"}
SCENES = {"atk": (sc_atk, 66, (290, 150)), "s1": (sc_s1, 66, (290, 140)), "s2": (sc_s2, 50, (290, 150)), "s3": (sc_s3, 45, (340, 140)), "late": (sc_late, 44, (280, 150))}


def main():
    global ENEMY, OP, SOUL_SPR, LIB
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    ap.add_argument("--out", default=os.path.join(MAIN, "Claude outputs", "pxplane_wisadel_1105", "gif"))
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    lib = Lib()
    LIB = lib
    en = sprite(os.path.join(ROOT, "game", "art", "enemies", "offspring", "e_offspring@2x.png"), 4)
    arr = np.asarray(en).astype(np.float32)
    arr[..., :3] = arr[..., :3] * 0.32 + np.array([10, 12, 14])
    ENEMY = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")
    OP = sprite(os.path.join(ROOT, "game", "art", "operators", "wisadel", "op_wisadel_idle@2x.png"), 8)
    SOUL_SPR = sprite(os.path.join(ROOT, "game", "art", "operators", "wisadel", "op_wisadel_soul_native_idle@2x.png"), 24)
    only = set(x for x in a.only.split(",") if x)
    title = "维什戴尔 · 转平面 · 15 fps 原速"
    for name, (fn, n, zc) in SCENES.items():
        if only and name not in only:
            continue
        cols = [("%s  精英 %d" % (NAMES[name], t), fn(t)) for t in TIERS[name]]
        gif(lib, cols, n, os.path.join(a.out, "wisadel_%s.gif" % name), title, zc)
    if not only or "branch" in only:
        gif(lib, [("节点：余烬未冷（三圈余震）/ 续燃（吸向残影）/ 礼尚往来 / 余响（精二）", sc_branch())], 66, os.path.join(a.out, "wisadel_branch.gif"), title, (290, 160))
    if "late8" in only:   # 8:00 后期混战 1 倍截图 + emit 每拍点数 p90（近似；实测要 GCP fx_audit）
        col = sc_late8()
        best, frames = None, []
        for tk in range(70):
            im = render(lib, col, tk)
            frames.append(im)
        em = [col.emit_log[t] for t in range(12, 70)]
        p90 = sorted(em)[int(len(em) * 0.9)]
        k = max(range(12, 70), key=lambda t: col.emit_log[t] + 0 * t)
        for t, name in ((k, "late8_peak"), (40, "late8_t40")):
            frames[t].save(os.path.join(a.out, "wisadel_%s.png" % name))
        gif_frames = [f.quantize(colors=255, method=Image.MEDIANCUT) for f in frames[10:70]]
        gif_frames[0].save(os.path.join(a.out, "wisadel_late8.gif"), save_all=True, append_images=gif_frames[1:], duration=67, loop=0)
        print("late8 emit/拍 p90 = %d，峰值 %d（拍 %d），均值 %.1f" % (p90, col.emit_log[k], k, sum(em) / len(em)))
    if not only or "link" in only:
        gif(lib, [("连携技「天降厚礼」（link/v2 缺省，不分档）", sc_link())], 40, os.path.join(a.out, "wisadel_link.gif"), title, (290, 160))


if __name__ == "__main__":
    main()
