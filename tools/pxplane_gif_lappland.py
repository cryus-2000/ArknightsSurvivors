#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""拉普兰德转平面（docs/273）送审 GIF：上 GCP 前先给用户看，只用 Python、不开 Godot。

帧条读 tools/pxplane_bake_lappland.py 烤出的 game/art/fx/pxp/pxp_lp_*.png + game/data/pxp_lappland.json（与游戏同一份）；
剑气细针、狼首弹拖尾 / 晶片、命中斩痕、封招符印、观察刻痕用 tools/pxplane_lappland_art.py 里与 fx_pxplane_lp.gd 同算法的 Python 版逐格画。
摆法照游戏：普攻扇形半径 100、半角 1.3、间隔 0.8 秒；精一每第 5 下狼之舞（半径 120）；精二每下两道交叉剑气（±12°，飞 200，速度 500，命中第一名即消失）；
狼魂期间每下多掷一道狼首弹；噤声同一敌人刻满 3 道 → 十字斩 + 封印 3 秒；天赋封印 1.5 秒（精一起）。
每招一张：E0 / E1 / E2 左右并排（只放实际存在的档）；上半 1 倍（实机：1 美术像素 = 2 屏幕像素）、下半 2 倍；15 fps 原速循环。
光照近似：整体压暗到 AMBIENT，命中 / 爆点挂一盏短照地光；热芯（emit 点）近似发光层加一层柔光。

用法：python tools/pxplane_gif_lappland.py [--only atk,s1] [--out 目录]
"""
import argparse, json, math, os, sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pxplane_lappland_art as A

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAIN = os.path.dirname(os.path.dirname(os.path.dirname(ROOT))) if ".claude" in ROOT else ROOT
PX = 2
W, H = 420, 260
GROUND = (36, 46, 48)
DIRS = [-90, -45, 0, 45, 90]
FONT = "C:/Windows/Fonts/msyh.ttc"
AMBIENT = 0.8
LIT = (0.78, 0.74, 1.0)
SQ = 0.72
REACH, HALF = 100.0, 1.3


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


def near(arr, v):
    return min(arr, key=lambda x: abs(x - v))


class Lib:
    def __init__(self):
        self.meta = {k: v for k, v in json.load(open(os.path.join(ROOT, "game", "data", "pxp_lappland.json"), encoding="utf-8")).items() if k != "_doc"}
        self.tex = {}

    def frame(self, k, fi, loop=False):
        m = self.meta[k]
        n = m["n"]
        if loop:
            fi %= n
        if fi < 0 or fi >= n:
            return None
        if k not in self.tex:
            self.tex[k] = Image.open(os.path.join(ROOT, "game", "art", "fx", "pxp", "pxp_lp_%s.png" % k.replace("_d-", "_dm").lower())).convert("RGBA")
        w, h = m["w"], m["h"]
        return self.tex[k].crop((fi * w, 0, (fi + 1) * w, h)), m


def sprite(path, n):
    im = Image.open(path).convert("RGBA")
    fw = im.width // n
    return im.crop((0, 0, fw, im.height))


class Col:
    """一栏的时间轴（拍 = 1/15 秒），坐标一律世界像素"""

    def __init__(self, tier, enemies, op=(120, 150), lead=None, elites=(0, 3)):
        self.t = tier
        self.elites = set(elites)   # 精英（画大一号；封招锁链环只画精英 / Boss）
        self.items = []
        self.enemies = [[float(x), float(y), 10 ** 9] for x, y in enemies]
        self.op = op
        self.lead = lead
        self.lights = []
        self.cuts = []       # (敌人序号, 拍, 斜向, 交叉)
        self.seals = []      # (敌人序号, 起拍, 止拍)
        self.tally = {}      # 敌人序号 → [(拍, 层数)]
        self.needles = []    # {p0, d, t0, t1, kind: far/twin/wolf/big/qi, tier}
        self.chains = []     # (a, b, 拍)
        self.aura = None
        self.scars = []      # (a, b, 拍)
        self.links = []      # (sp, ep, t0, t1, d)
        self.swing_n = 0

    def add(self, k, tk, gp, flip=False, gd=False, gy=None, loop=False, until=None):
        self.items.append({"k": k, "t0": tk, "gp": snap(gp), "flip": flip, "gd": gd, "gy": gp[1] if gy is None else gy, "loop": loop, "until": until})

    def light(self, at, r, i, tk, n=2):
        self.lights.append((at[0], at[1] + 6, r, i, tk, n, LIT))

    def alive(self, tk):
        return [ei for ei, q in enumerate(self.enemies) if q[2] > tk]

    def nearest(self, tk, frm=None, r=9999):
        frm = frm or self.op
        best = None
        for ei in self.alive(tk):
            q = self.enemies[ei]
            d = math.hypot(q[0] - frm[0], q[1] - frm[1])
            if d < r and (best is None or d < best[0]):
                best = (d, ei)
        return best[1] if best else None

    def hit_cut(self, tk, ei, x=False):
        q = self.enemies[ei]
        rd = (q[0] - self.op[0], q[1] - self.op[1])
        L = math.hypot(*rd) or 1
        tg = (-rd[1] / L, rd[0] / L)
        rot = -0.45 if tg[0] * tg[1] >= 0 else 0.45
        c, s = math.cos(rot), math.sin(rot)
        self.cuts.append((ei, tk, (tg[0] * c - tg[1] * s, tg[0] * s + tg[1] * c), x))

    def seal(self, ei, tk, dur):
        self.seals.append((ei, tk, tk + int(dur * 15)))

    def swing(self, tk, tg=None, heavy=False, mirror=False, reach=REACH, half=HALF, seal_dur=1.5):
        """一记双刃横扫；返回命中的敌人"""
        tg = self.nearest(tk) if tg is None else tg
        e = self.enemies[tg]
        ang = math.atan2(e[1] - self.op[1], e[0] - self.op[0])
        R = near(A.ATK_R, reach * 0.5)
        d, fl = pick_dir(math.degrees(ang))
        v = "h" if heavy else ("m" if mirror else "e%d" % self.t)
        self.add("atk_r%d_%s_up_d%d" % (R, v, d), tk, self.op, fl, gy=self.op[1])
        self.add("atk_r%d_gd_d%d" % (R, d), tk, self.op, fl, gd=True)
        hits = []
        for ei in self.alive(tk):
            q = self.enemies[ei]
            dx, dy = q[0] - self.op[0], q[1] - self.op[1]
            da = abs((math.atan2(dy, dx) - ang + math.pi) % math.tau - math.pi)
            if math.hypot(dx, dy) < reach + 8 and da < half:
                hits.append((math.hypot(dx, dy), ei))
        hits.sort()
        for _, ei in hits[:3]:
            self.hit_cut(tk + 1, ei, self.t >= 2)
        if self.t >= 1:
            for _, ei in hits:
                self.seal(ei, tk + 1, seal_dur)
        if hits:
            q = self.enemies[hits[0][1]]
            self.light((q[0], q[1] - 8), 110, 0.55, tk + 1)
        if self.t >= 2 and not mirror and not heavy:   # 精二双生刃：两道交叉剑气
            for f in (-12, 12):
                self.needle(tk, ang + math.radians(f), "twin")
        return [ei for _, ei in hits]

    def needle(self, tk, ang, kind, dist=200.0, spd=500.0, tier=None):
        d = (math.cos(ang), math.sin(ang))
        p0 = (self.op[0], self.op[1])
        t1 = tk + int(dist / spd * 15) + 1
        hit_t = None
        for s in range(1, int(dist), 4):   # 命中第一名即消失（狼首穿透：只记第一下的命中闪）
            p = (p0[0] + d[0] * s, p0[1] + d[1] * s)
            for ei in self.alive(tk):
                q = self.enemies[ei]
                if math.hypot(q[0] - p[0], q[1] - p[1]) < 14:
                    hit_t = (tk + int(s / spd * 15) + 1, ei)
                    break
            if hit_t:
                break
        if hit_t and kind not in ("wolf", "big"):
            t1 = hit_t[0]
        nd = {"p0": p0, "d": d, "t0": tk, "t1": t1, "spd": spd, "kind": kind, "tier": self.t if tier is None else tier}
        self.needles.append(nd)
        if hit_t:
            q = self.enemies[hit_t[1]]
            self.add("star", hit_t[0], (q[0], q[1] - 16))
            if kind != "wolf":   # 剑气命中：斩痕炸开（交叉）
                self.cuts.append((hit_t[1], hit_t[0], (-d[1], d[0]), True))
            self.light((q[0], q[1] - 12), 90, 0.45, hit_t[0])
        return nd

    def dance(self, tk, r=120.0):
        R = near(A.DANCE_R, r * 0.5)
        self.add("dance_r%d_up" % R, tk, self.op, gy=self.op[1] + 1)
        self.add("dance_r%d_gd" % R, tk, self.op, gd=True)
        hits = [ei for ei in self.alive(tk) if math.hypot(self.enemies[ei][0] - self.op[0], self.enemies[ei][1] - self.op[1]) < r + 8]
        for ei in hits[:4]:
            self.hit_cut(tk + 1, ei, True)
        for ei in hits:
            self.seal(ei, tk + 1, 2.0)
        self.light((self.op[0], self.op[1] - 10), 170, 0.75, tk, 3)


# ---------------------------------------------------------------- 绘制

def render(lib, col, tk):
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
        if not (0 <= x < W and 0 <= y < H):
            return
        cc = A.hx(c) if isinstance(c, str) else c
        if a < 1.0:
            base = img.getpixel((x, y))
            cc = tuple(int(base[i] * (1 - a) + cc[i] * a) for i in range(3)) + (255,)
        dr.rectangle([x, y, x + PX - 1, y + PX - 1], fill=cc)
        if glow:
            ed.rectangle([x, y, x + PX - 1, y + PX - 1], fill=cc[:3])

    def strip(k, fi, gp, flip=False, loop=False, alpha=None):
        if k == "star":   # 剑气命中：四角星（运行时同 fx_pxplane_lp._star）
            if 0 <= fi < 3:
                L = [4, 3, 2][fi]
                for s in range(-L, L + 1):
                    c = A.LP[6] if abs(s) < 2 else A.LP[4]
                    put_px(gp[0] + s * PX, gp[1], c, glow=abs(s) < 2 and fi == 0)
                    put_px(gp[0], gp[1] + s * PX, c, glow=abs(s) < 2 and fi == 0)
            return
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
            arr = np.asarray(big).copy()
            arr[..., 3] = (arr[..., 3] * alpha).astype(np.uint8)
            big = Image.fromarray(arr, "RGBA")
        l, t = int(left), int(top)
        img.alpha_composite(big, dest=(max(0, l), max(0, t)), source=(max(0, -l), max(0, -t)))
        for q in (m["emit"][fi2] if alpha is None else []):
            x = q[0] if not flip else m["w"] - 1 - q[0]
            ed.rectangle([l + x * PX, t + q[1] * PX, l + x * PX + PX - 1, t + q[1] * PX + PX - 1], fill=tuple(int(q[2][i:i + 2], 16) for i in (0, 2, 4)))

    def item_on(it):
        return tk >= it["t0"] and (it["until"] is None or tk < it["until"])

    # 地面层
    if col.aura and col.aura[0] <= tk < col.aura[1]:
        strip("s2_aura", tk, snap(col.op), loop=True)
    for it in col.items:
        if it["gd"] and item_on(it):
            strip(it["k"], tk - it["t0"] if not it["loop"] else tk, it["gp"], it["flip"], it["loop"])
    for (a, b, t0) in col.scars:   # 连携斩痕 / 精一后期剑气的地面细划痕：一道淡紫细线，冷却变暗断开
        age = tk - t0
        if 0 <= age < 9:
            n = int(math.hypot(b[0] - a[0], b[1] - a[1]) / PX)
            for i in range(n):
                if age > 4 and A.hf(i, age) < (age - 4) * 0.2:
                    continue
                u = i / max(1, n)
                put_px(a[0] + (b[0] - a[0]) * u, a[1] + (b[1] - a[1]) * u, A.LP[5] if age < 2 else (A.LP[3] if age < 5 else A.LP[2]))
    for nd in col.needles:   # 剑气贴地影子
        if nd["kind"] != "wolf" and nd["t0"] <= tk < nd["t1"]:
            s0 = (tk - nd["t0"]) / 15.0 * nd["spd"]
            p = (nd["p0"][0] + nd["d"][0] * s0, nd["p0"][1] + nd["d"][1] * s0)
            dd, fl = pick_dir(math.degrees(math.atan2(nd["d"][1], nd["d"][0])))
            strip("qish_%s_d%d" % (nd["kind"], dd), 0, snap(p), fl, loop=True)
    for nd in col.needles:   # 精一后期剑气：身后地上一道细划痕（跟到剑气当前位置）
        if nd["kind"] == "qi" and nd["tier"] >= 1 and nd["t0"] <= tk < nd["t1"] + 6:
            u = min(tk, nd["t1"]) - nd["t0"]
            s1 = u / 15.0 * nd["spd"]
            for s in range(10, int(s1), PX):
                if tk >= nd["t1"] and A.hf(s, tk) < (tk - nd["t1"]) * 0.18:
                    continue
                put_px(nd["p0"][0] + nd["d"][0] * s, nd["p0"][1] + nd["d"][1] * s, A.LP[3] if s1 - s < 30 else A.LP[2])

    # 排序层
    sort = []
    for e in col.enemies:
        if tk < e[2]:
            sort.append((e[1], "e", e))
    sort.append((col.op[1], "op", None))
    if col.lead:
        sort.append((col.lead[1], "lead", None))
    for it in col.items:
        if not it["gd"] and item_on(it):
            sort.append((it["gy"] + 1, "it", it))
    for nd in col.needles:
        if nd["t0"] <= tk < nd["t1"]:
            s = (tk - nd["t0"]) / 15.0 * nd["spd"]
            p = (nd["p0"][0] + nd["d"][0] * s, nd["p0"][1] + nd["d"][1] * s)
            sort.append((p[1] + 1, "nd", (nd, p)))
    for (sp, ep, t0, t1, dd) in col.links:
        if t0 <= tk < t1:
            u = (tk - t0) / max(1, t1 - t0)
            sort.append((sp[1] + (ep[1] - sp[1]) * u + 1, "lk", (sp, ep, u, dd)))
    sort.sort(key=lambda s: s[0])
    for _, kind, v in sort:
        if kind == "e":
            spr = ENEMY_E if col.enemies.index(v) in col.elites else ENEMY
            img.alpha_composite(spr, dest=(int(v[0] - spr.width // 2), int(v[1] - spr.height + 6)))
        elif kind == "op":
            img.alpha_composite(OPS["lappland"], dest=snap((col.op[0] - 64, col.op[1] - 120)))
        elif kind == "lead":
            img.alpha_composite(OPS["texas"], dest=snap((col.lead[0] - 64, col.lead[1] - 120)))
        elif kind == "it":
            strip(v["k"], tk - v["t0"] if not v["loop"] else tk, v["gp"], v["flip"], v["loop"])
        elif kind == "lk":
            sp, ep, u, dd = v
            p = snap((sp[0] + (ep[0] - sp[0]) * u, sp[1] + (ep[1] - sp[1]) * u))
            d, fl = pick_dir(math.degrees(math.atan2(dd[1], dd[0])))
            strip("link_d%d" % d, 0, p, fl, loop=True)
        elif kind == "nd":
            nd, p = v
            d = nd["d"]
            nv = (-d[1], d[0])
            hd = snap((p[0], p[1] - 16))
            if nd["kind"] == "wolf":
                dd, fl = pick_dir(math.degrees(math.atan2(d[1], d[0])))
                strip("wolf_e%d_d%d" % (max(1, nd["tier"]), dd), tk, snap(p), fl, loop=True)
                trail = A.needle(14, 1, nd["tier"])   # 狼首身后一道细尾
                for (s, w, c, gl) in trail:
                    put_px(hd[0] - d[0] * (s + 8) * PX + nv[0] * w * PX, hd[1] - d[1] * (s + 8) * PX + nv[1] * w * PX, c)
                if nd["tier"] >= 2:   # 精二：沿途掉菱形晶片
                    trav = (tk - nd["t0"]) / 15.0 * nd["spd"]
                    for k in range(int(trav // 24)):
                        sk = k * 24 + 12
                        age = (trav - sk) / nd["spd"] * 15
                        if age > 7:
                            continue
                        q = (nd["p0"][0] + d[0] * sk + (A.hf(k, 1) - 0.5) * 10, nd["p0"][1] + d[1] * sk - 16 + age * 2.2)
                        for (dx, dy, c) in ((0, -1, A.WOLF[5]), (0, 0, A.WOLF[4]), (-1, 0, A.WOLF[3]), (1, 0, A.WOLF[3]), (0, 1, A.WOLF[3])):
                            put_px(q[0] + dx * PX, q[1] + dy * PX, c)
            else:   # 月牙剑气（贴地低飞）+ 身后两道残光
                dd, fl = pick_dir(math.degrees(math.atan2(d[1], d[0])))
                k = "qi_%s_d%d" % (nd["kind"], dd)
                gap = 7 if nd["kind"] != "big" else 10
                for gi, al in ((2, 0.22), (1, 0.45)):
                    if tk - nd["t0"] >= gi:
                        strip(k, tk, snap((p[0] - d[0] * gap * gi, p[1] - d[1] * gap * gi)), fl, loop=True, alpha=al)
                strip(k, tk, snap(p), fl, loop=True)
                if nd["kind"] == "qi" and nd["tier"] >= 2:   # 精二后期剑气：旁边一道晚半拍的小回声
                    strip(k, tk, snap((p[0] - d[0] * 12 - d[1] * 8, p[1] - d[1] * 12 + d[0] * 8)), fl, loop=True, alpha=0.5)
    # 命中斩痕（跟着被砍的那只）
    for (ei, t0, dv, x) in col.cuts:
        f = tk - t0
        e = col.enemies[ei]
        if 0 <= f <= 2:
            c0 = snap((e[0], e[1] - 6))
            for (dx, dy, c, gl) in A.cut_px(f, 7 + 2 * col.t, dv, x):
                put_px(c0[0] + dx * PX, c0[1] + dy * PX, c, glow=gl)
    # 观察刻痕（S3）
    for ei, evs in col.tally.items():
        e = col.enemies[ei]
        cur = None
        for (t0, n) in evs:
            if t0 <= tk:
                cur = (t0, n)
        if cur and cur[1] > 0 and tk < e[2]:
            c0 = snap((e[0], e[1] - 34))
            for (dx, dy, c, gl) in A.tally_px(cur[1], tk - cur[0] < 2):
                put_px(c0[0] + dx * PX, c0[1] + dy * PX, c, glow=gl)
    # 封招符印（头顶）
    for (ei, t0, t1) in col.seals:
        e = col.enemies[ei]
        if ei not in col.elites:
            continue
        if t0 <= tk < t1 and tk < e[2] and not any(s0 <= tk < s1 and s0 > t0 for (ej, s0, s1) in col.seals if ej == ei):
            c0 = snap((e[0], e[1] - 66 - (10 if ei in col.tally else 0)))
            for (dx, dy, c, a, gl) in A.chain_px(tk - t0, (t1 - t0) / 15.0, (t1 - tk) / 15.0):
                put_px(c0[0] + dx * PX, c0[1] + dy * PX, c, glow=gl, a=a)
    for (a, b, t0) in col.chains:   # 封印传染：死亡处到新目标的细虚线
        age = tk - t0
        if 0 <= age < 4:
            n = int(math.hypot(b[0] - a[0], b[1] - a[1]) / PX)
            for i in range(n):
                if (i + age) % 3 == 2:
                    continue
                u = i / max(1, n)
                put_px(a[0] + (b[0] - a[0]) * u, a[1] + (b[1] - a[1]) * u - 12, A.LP[6] if age < 2 else A.LP[4], glow=age == 0 and i % 4 == 0)
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
            d.text((x0 + 6, 5), lab, fill=(225, 220, 245), font=font)
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

E_MAIN = [(196, 150), (214, 126), (206, 178), (250, 146), (246, 108), (262, 190), (310, 156), (178, 112), (300, 120), (330, 192)]
E_FAR = [(300, 120), (330, 170), (360, 140), (310, 210), (370, 96)]
TIERS = {"atk": (0, 1, 2), "s1": (0, 1, 2), "s2": (1, 2), "s3": (2,), "late": (0, 1, 2)}


def sc_atk(t):
    c = Col(t, E_MAIN)
    for k in range(5):
        tk = 2 + 12 * k
        if t >= 1 and k == 4:   # 精一起每第 5 下：狼之舞
            c.dance(tk)
        else:
            c.swing(tk, tg=[0, 2, 1, 3, 0][k])
    return c


def sc_far():
    """领主远掷（近战触及外）+ 追猎 + 反斩大剑气（不分档；精一，封印照常）"""
    c = Col(1, E_FAR, op=(110, 150), elites=(1,))
    for k, tg in enumerate([0, 1, 2]):
        tk = 2 + 15 * k
        e = c.enemies[tg]
        c.needle(tk, math.atan2(e[1] - c.op[1], e[0] - c.op[0]), "far")
    c.add("arm_gd", 46, c.op, gd=True)   # 日晷格挡 → 反斩待命
    c.add("block_up", 44, c.op, gy=c.op[1] + 1)
    e = c.enemies[3]
    c.needle(52, math.atan2(e[1] - c.op[1], e[0] - c.op[0]), "big", dist=260)
    return c


def sc_s1(t):
    c = Col(t, E_MAIN, op=(110, 130), lead=(140, 176))
    c.add("s1_e%d_gd" % t, 2, c.op, gd=True)
    if t >= 2:
        c.add("s1_up", 2, c.op, gy=c.op[1] + 1)
    c.light((c.op[0], c.op[1] - 10), 110, 0.5, 2, 3)
    c.add("block_up", 26, c.lead, gy=c.lead[1] + 1)   # 日晷格挡：队长身前双刃交叉一闪
    c.light((c.lead[0], c.lead[1] - 16), 90, 0.6, 26)
    c.swing(36, tg=0)
    return c


def sc_s2(t):
    c = Col(t, E_MAIN, op=(110, 150))
    c.add("s2_up", 2, c.op, gy=c.op[1] + 1)
    c.add("s2_gd", 2, c.op, gd=True)
    c.light((c.op[0], c.op[1] - 14), 150, 0.6, 2, 3)
    c.aura = (2, 80)
    for k in range(5):
        tk = 14 + 12 * k
        hits = c.swing(tk, tg=[0, 3, 1, 2, 0][k])
        e = c.enemies[c.nearest(tk)]
        c.needle(tk, math.atan2(e[1] - c.op[1], e[0] - c.op[0]), "wolf")
    return c


def sc_s3(t):
    c = Col(t, E_MAIN, op=(120, 150))
    c.add("s3_up", 2, c.op, gy=c.op[1] + 1)
    c.add("s3_gd", 2, c.op, gd=True)
    c.light((c.op[0], c.op[1] - 20), 170, 0.7, 2, 3)
    cnt = {}
    for k in range(5):
        tk = 12 + 12 * k
        hits = c.swing(tk, tg=[0, 0, 2, 0, 2][k])
        for ei in hits:
            n = cnt.get(ei, 0) + 1
            if n >= 3:   # 刻满：十字斩 + 封印 3 秒，层数清零
                e = c.enemies[ei]
                c.add("xcut_up", tk + 1, (e[0], e[1]), gy=e[1] + 1)
                c.light((e[0], e[1] - 18), 170, 0.85, tk + 1, 3)
                c.seal(ei, tk + 1, 3.0)
                n = 0
            cnt[ei] = n
            c.tally.setdefault(ei, []).append((tk + 1, n))
    return c


def sc_late(t):
    c = Col(t, E_MAIN, op=(100, 150))
    for tk, tg in [(2, 0), (22, 3)]:
        c.swing(tk, tg=tg)
        e = c.enemies[tg]
        a0 = math.atan2(e[1] - c.op[1], e[0] - c.op[0])
        for j in (-1, 1):   # 后期额外剑气：扇形左右错开
            c.needle(tk + 1, a0 + math.radians(20) * j, "qi", dist=170, spd=520, tier=t)
    return c


def sc_branch():
    """分支招（精二，不分档）：双刃连斩补刀 / 断喝 / 断喝·传染 / 日晷·回敬"""
    c = Col(1, E_MAIN, op=(150, 146))
    c.swing(2, tg=0)
    c.swing(4, tg=0, mirror=True)   # 双刃连斩：0.12 秒后反向补一刀
    R = near(A.BARK_R, 150 * 0.5)
    c.add("bark_r%d_gd" % R, 20, c.op, gd=True)   # 断喝：狼嚎声波
    c.light((c.op[0], c.op[1] - 10), 180, 0.7, 20, 3)
    for ei in c.alive(20):
        q = c.enemies[ei]
        if math.hypot(q[0] - c.op[0], q[1] - c.op[1]) < 158:
            c.seal(ei, 21, 2.0)
    e = c.enemies[0]   # 断喝·传染：被封印的 0 号死亡，封印扩散到附近
    c.enemies[0][2] = 36
    c.add("spread_up", 36, (e[0], e[1]), gy=e[1] + 1)
    for ej in (1, 3, 2):
        q = c.enemies[ej]
        c.chains.append(((e[0], e[1]), (q[0], q[1]), 36))
        c.seal(ej, 37, 2.0)
    c.add("block_up", 48, c.op, gy=c.op[1] + 1)   # 日晷·回敬：格挡 → 原地反斩
    c.swing(50, tg=3, heavy=True, reach=130, half=math.radians(70))
    return c


def sc_link():
    c = Col(2, E_MAIN, op=(70, 150), lead=(120, 190))
    cz, r = (250, 150), 110.0
    d0 = (1.0, 0.0)
    sp = (cz[0] - d0[0] * (r + 30), cz[1])
    ep = (cz[0] + d0[0] * (r + 50), cz[1])
    c.op = snap(sp)
    c.links.append((sp, ep, 3, 3 + 4, d0))
    c.scars.append((sp, ep, 7))
    c.light((cz[0], cz[1] - 10), 160, 0.6, 3, 5)
    return c


NAMES = {"atk": "普攻「双刃」", "s1": "S1「日晷」", "s2": "S2「狼魂」", "s3": "S3「噤声」", "late": "后期额外攻击（剑气）"}
SCENES = {"atk": (sc_atk, 66, (200, 140)), "s1": (sc_s1, 46, (140, 150)), "s2": (sc_s2, 76, (190, 140)), "s3": (sc_s3, 76, (190, 140)), "late": (sc_late, 40, (190, 140))}


def main():
    global ENEMY, ENEMY_E, OPS
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    ap.add_argument("--out", default=os.path.join(MAIN, "Claude outputs", "pxplane_lappland_1105", "gif"))
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    lib = Lib()
    en = sprite(os.path.join(ROOT, "game", "art", "enemies", "offspring", "e_offspring@2x.png"), 4)
    arr = np.asarray(en).astype(np.float32)
    arr[..., :3] = arr[..., :3] * 0.32 + np.array([10, 12, 14])
    ENEMY = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")
    ENEMY_E = ENEMY.resize((int(ENEMY.width * 1.6) // 2 * 2, int(ENEMY.height * 1.6) // 2 * 2), Image.NEAREST)
    OPS = {"lappland": sprite(os.path.join(ROOT, "game", "art", "operators", "lappland", "op_lappland_idle@2x.png"), 8),
           "texas": sprite(os.path.join(ROOT, "game", "art", "operators", "texas", "op_texas_idle@2x.png"), 7)}
    only = set(x for x in a.only.split(",") if x)
    title = "拉普兰德 · 转平面 · 15 fps 原速"
    for name, (fn, n, zc) in SCENES.items():
        if only and name not in only:
            continue
        cols = [("%s  精英 %d" % (NAMES[name], t), fn(t)) for t in TIERS[name]]
        gif(lib, cols, n, os.path.join(a.out, "lappland_%s.gif" % name), title, zc)
    if not only or "far" in only:
        gif(lib, [("领主远掷 → 格挡 → 日晷·反斩大剑气（不分档）", sc_far())], 70, os.path.join(a.out, "lappland_far.gif"), title, (200, 150))
    if not only or "branch" in only:
        gif(lib, [("分支：双刃连斩 / 断喝 / 断喝·传染 / 日晷·回敬", sc_branch())], 66, os.path.join(a.out, "lappland_branch.gif"), title, (200, 140))
    if not only or "link" in only:
        gif(lib, [("连携技「月牙剑气」（link/v2 缺省，不分档）", sc_link())], 24, os.path.join(a.out, "lappland_link.gif"), title, (240, 150))


if __name__ == "__main__":
    main()
