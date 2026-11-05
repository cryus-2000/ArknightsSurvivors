#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""塞雷娅转平面（docs/269）送审 GIF：上 GCP 前先给用户看，只用 Python、不开 Godot。

帧条直接读 tools/pxplane_bake_saria.py 烤出的 game/art/fx/pxp/pxp_sa_*.png + game/data/pxp_saria.json（与游戏同一份）；
注射器 / 碎晶片弹体、阻挡圈、晶柱墙脚、钙化斑用 tools/pxplane_saria_art.py 里与 fx_pxplane_sa.gd 同算法的 Python 版逐格画。
摆法照游戏：盾击判定原点 = 脚底、半径 98（精二满格环冲 110、晶柱环半径 110 × 0.55 椭圆 6 根 2 秒）、出拳间隔 0.9 秒；
S3 区域半径 180、10 个晶柱槽（4 个贴身 + 6 个散布）、晶柱长出 0.4 秒 / 碰碎 0.3 秒 / 3 秒后原位重长；治疗特效在队长身上（这里队长 = 德克萨斯）。
每招一张：E0 / E1 / E2 左右并排（只放实际存在的档）；上半 1 倍（实机大小：1 美术像素 = 2 屏幕像素）、下半 2 倍放大；15 fps 原速循环。
光照近似：整体压暗到 AMBIENT，命中 / 爆点挂一盏短照地光；热芯（emit 点）近似发光层加一层柔光。

用法：python tools/pxplane_gif_saria.py [--only atk,s1] [--out 目录]
"""
import argparse, json, math, os, sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pxplane_saria_art as A

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAIN = os.path.dirname(os.path.dirname(os.path.dirname(ROOT))) if ".claude" in ROOT else ROOT
PX = 2
W, H = 420, 260
GROUND = (36, 46, 48)
DIRS = [-90, -45, 0, 45, 90]
FONT = "C:/Windows/Fonts/msyh.ttc"
AMBIENT = 0.8
AMBER_L = (1.0, 0.75, 0.45)
HEAL_L = (0.5, 1.0, 0.65)
SQ = 0.72


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
        self.meta = {k: v for k, v in json.load(open(os.path.join(ROOT, "game", "data", "pxp_saria.json"), encoding="utf-8")).items() if k != "_doc"}
        self.tex = {}

    def frame(self, k, fi, loop=False):
        m = self.meta[k]
        n = m["n"]
        if loop:
            fi %= n
        if fi < 0 or fi >= n:
            return None
        if k not in self.tex:
            self.tex[k] = Image.open(os.path.join(ROOT, "game", "art", "fx", "pxp", "pxp_sa_%s.png" % k.replace("_d-", "_dm"))).convert("RGBA")
        w, h = m["w"], m["h"]
        return self.tex[k].crop((fi * w, 0, (fi + 1) * w, h)), m


def sprite(path, n):
    im = Image.open(path).convert("RGBA")
    fw = im.width // n
    return im.crop((0, 0, fw, im.height))


class Col:
    """一栏的时间轴（拍 = 1/15 秒），坐标一律世界像素"""

    def __init__(self, tier, enemies, op=(120, 150), lead=None):
        self.t = tier
        self.items = []
        self.shots = []      # {kind, p0, v, t0, t1}
        self.enemies = [[float(x), float(y), 10 ** 9] for x, y in enemies]
        self.op = op
        self.lead = lead     # 队长位置（治疗 / 连携画在队长身上）；None = 塞雷娅自己是队长
        self.lights = []
        self.spots = []      # 钙化斑 (敌人序号, 起拍, 止拍)
        self.guard = True
        self.field = None    # (起拍, 止拍)
        self.posts = None    # (起拍, 止拍, [点], small)
        self.slots = []      # 晶柱槽 {pos, events: [(拍, 状态)]}
        self.orbs = 0
        self.orb_broken = {}
        self.hot = None
        self.beat = {}

    def lp(self):
        return self.lead or self.op

    def add(self, k, tk, gp, flip=False, gd=False, gy=None, loop=False, until=None, alpha=None):
        self.items.append({"k": k, "t0": tk, "gp": snap(gp), "flip": flip, "gd": gd, "gy": gp[1] if gy is None else gy, "loop": loop, "until": until, "alpha": alpha})

    def light(self, at, r, i, tk, n=2, col=AMBER_L):
        self.lights.append((at[0], at[1] + 6, r, i, tk, n, col))

    def bash(self, tk, tg, calc=False, reach=98.0):
        """一记盾击：朝 tg 号敌人，扇形内的都打到"""
        e = self.enemies[tg]
        ang = math.atan2(e[1] - self.op[1], e[0] - self.op[0])
        R = near(A.BASH_R, reach * 0.5)
        d, fl = pick_dir(math.degrees(ang))
        hits = []
        for ei, q in enumerate(self.enemies):
            if q[2] <= tk:
                continue
            dx, dy = q[0] - self.op[0], q[1] - self.op[1]
            dist = math.hypot(dx, dy)
            da = abs((math.atan2(dy, dx) - ang + math.pi) % math.tau - math.pi)
            if dist < reach + 8 and da < 1.1:
                hits.append((dist, ei))
        hits.sort()
        if calc:
            self.add("cbash_r%d_d%d" % (R, d), tk, self.op, fl, gy=self.op[1])
        else:
            self.add("bash_r%d_e%d_up_d%d" % (R, min(self.t, 1), d), tk, self.op, fl, gy=self.op[1])
            self.add("bash_r%d_gd_d%d" % (R, d), tk, self.op, fl, gd=True)
        key = "hita" if calc else ("hitc" if self.t >= 1 else "hit")
        for _, ei in hits[:3]:
            q = self.enemies[ei]
            hd, hfl = pick_dir(math.degrees(math.atan2(q[1] - self.op[1], q[0] - self.op[0])))
            self.add("%s_d%d" % (key, hd), tk + 1, (q[0], q[1] - 6), hfl, gy=q[1] + 1)
            if self.t >= 1 and not calc:
                self.spots.append((ei, tk + 1, tk + 31))
        if hits:
            q = self.enemies[hits[0][1]]
            self.light((q[0], q[1] - 6), 80 + 10 * self.t, 0.55, tk + 1)
        return [ei for _, ei in hits]

    def suit(self, tk, reach=110.0):
        R = near(A.SUIT_R, reach * 0.5)
        self.add("suit_r%d_gd" % R, tk, self.op, gd=True)
        self.add("suit_up", tk, self.op, gy=self.op[1])
        for ei, q in enumerate(self.enemies):
            if math.hypot(q[0] - self.op[0], q[1] - self.op[1]) < reach + 8 and q[2] > tk:
                hd, hfl = pick_dir(math.degrees(math.atan2(q[1] - self.op[1], q[0] - self.op[0])))
                self.add("hitc_d%d" % hd, tk + 1, (q[0], q[1] - 6), hfl, gy=q[1] + 1)
        self.light((self.op[0], self.op[1] - 20), 120, 0.8, tk, 3)
        pts = []
        for k in range(6):
            an = k * math.tau / 6
            pts.append((self.op[0] + math.cos(an) * 110, self.op[1] + math.sin(an) * 110 * 0.55))
        self.posts = (tk, tk + 30, pts, False)
        for k, p in enumerate(pts):
            self.add("pilB%d_brk" % (k % 3), tk + 30, p, gy=p[1] + 1)

    def heal(self, tk, s):
        c = self.lp()
        if s == 2:
            self.add("s2_e%d_gd" % max(1, self.t), tk, c, gd=True)
            self.add("s2_up", tk, c, gy=c[1] + 1)
        else:
            self.add("s1_gd", tk, c, gd=True)
            self.add("s1_e%d_up" % self.t, tk, c, gy=c[1] + 1)
        self.light((c[0], c[1] - 20), 100, 0.5, tk, 3, HEAL_L)

    def shoot(self, tk, kind, src, tg, spd):
        e = self.enemies[tg]
        aim = (e[0], e[1] - 16)
        d = math.hypot(aim[0] - src[0], aim[1] - src[1])
        n = max(1, math.ceil(d / (spd / 15.0)))
        self.shots.append({"kind": kind, "p0": src, "p1": aim, "t0": tk, "t1": tk + n})
        self.add("syrhit" if kind == "syringe" else "chip", tk + n, aim, gy=e[1] + 1)
        return tk + n

    def orb_ground(self, tk, k):
        an = tk / 15.0 * 2.2 + k * math.tau / max(1, self.orbs)
        return (self.op[0] + math.cos(an) * 70, self.op[1] + math.sin(an) * 70 + 2)


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
        img.alpha_composite(big, dest=(max(0, l), max(0, t)), source=(max(0, -l), max(0, -t)))
        if alpha is None or alpha > 0.5:
            for q in m["emit"][fi2]:
                x = q[0] if not flip else m["w"] - 1 - q[0]
                ed.rectangle([l + x * PX, t + q[1] * PX, l + x * PX + PX - 1, t + q[1] * PX + PX - 1], fill=tuple(int(q[2][i:i + 2], 16) for i in (0, 2, 4)))

    def item_on(it):
        if tk < it["t0"] or (it["until"] is not None and tk >= it["until"]):
            return False
        return True

    # 地面层
    if col.field and col.field[0] <= tk < col.field[1]:
        dur = col.field[1] - col.field[0]
        u = tk - col.field[0]
        al = min(1.0, u / 4.5) * min(1.0, (dur - u) / 9.0)
        lp = col.lp()
        strip("field_gd", tk, snap((lp[0], lp[1] + 4)), loop=True, alpha=al)
    if col.guard:
        lp = snap((col.lp()[0], col.lp()[1] + 4))
        for (x, y, c) in A.guard_ring(31, tk):
            put_px(lp[0] + x * PX, lp[1] + y * PX, c, a=0.85)
    if col.posts and col.posts[0] <= tk < col.posts[1]:
        pts = col.posts[2]
        for k in range(len(pts)):
            a2, b2 = pts[k], pts[(k + 1) % len(pts)]
            m = int(math.hypot(b2[0] - a2[0], b2[1] - a2[1]) / PX)
            for i in range(m):
                if (i + tk) % 4 == 3:
                    continue
                u = i / max(1, m)
                put_px(a2[0] + (b2[0] - a2[0]) * u, a2[1] + (b2[1] - a2[1]) * u, A.AMB[3] if i % 2 == 0 else A.AMB[2])
    for k in range(col.orbs):
        if col.orb_broken.get(k, (0, -1))[0] <= tk < col.orb_broken.get(k, (0, -1))[1]:
            continue
        gp = snap(col.orb_ground(tk, k))
        for dx in (-2, 0, 2):
            put_px(gp[0] + dx, gp[1], A.SHADOW, a=0.7)
    for it in col.items:
        if it["gd"] and item_on(it):
            strip(it["k"], tk - it["t0"] if not it["loop"] else tk, it["gp"], it["flip"], it["loop"], it["alpha"])

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
    if col.posts and col.posts[0] <= tk < col.posts[1]:
        u = tk - col.posts[0]
        nm = "pilS" if col.posts[3] else "pilB"
        for k, p in enumerate(col.posts[2]):
            if u < 4:
                sort.append((p[1] + 1, "raw", ("%s%d_rise" % (nm, k % 3), u, p, k % 2 == 1, False)))
            else:
                sort.append((p[1] + 1, "raw", ("%s%d_idle" % (nm, k % 3), tk + k, p, k % 2 == 1, True)))
    for si, sl in enumerate(col.slots):
        st, t0 = None, None
        for (et, es) in sl["ev"]:
            if et <= tk:
                st, t0 = es, et
        if st is None or st == 3:
            continue
        v = si % 2
        u = (tk - t0) / 15.0
        if st == 0:
            sort.append((sl["pos"][1] + 1, "raw", ("cal%d_grow" % v, min(5, int(u / 0.4 * 6)), sl["pos"], sl["flip"], False)))
        elif st == 1:
            sort.append((sl["pos"][1] + 1, "raw", ("cal%d_idle" % v, tk + si, sl["pos"], sl["flip"], True)))
        else:
            sort.append((sl["pos"][1] + 1, "raw", ("cal%d_brk" % v, min(4, int(u / 0.3 * 5)), sl["pos"], sl["flip"], False)))
    for k in range(col.orbs):
        if col.orb_broken.get(k, (0, -1))[0] <= tk < col.orb_broken.get(k, (0, -1))[1]:
            continue
        gp = col.orb_ground(tk, k)
        hp = snap((gp[0], gp[1] - 16 + round(math.sin(tk / 15.0 * 3.0 + k)) * 2))
        sort.append((gp[1] + 1, "raw", ("orb", tk + k, hp, False, True)))
    if col.hot and col.hot[0] <= tk < col.hot[1] and col.t >= 2:
        lp = col.lp()
        sort.append((lp[1] + 2, "raw", ("hot_aura", tk, snap(lp), False, True)))
    for s in col.shots:
        if s["t0"] <= tk < s["t1"]:
            u = (tk - s["t0"]) / max(1, s["t1"] - s["t0"])
            p = (s["p0"][0] + (s["p1"][0] - s["p0"][0]) * u, s["p0"][1] + (s["p1"][1] - s["p0"][1]) * u)
            sort.append((p[1] + 16, "shot", (s, p)))
    sort.sort(key=lambda s: s[0])
    for _, kind, v in sort:
        if kind == "e":
            img.alpha_composite(ENEMY, dest=(int(v[0] - ENEMY.width // 2), int(v[1] - ENEMY.height + 6)))
        elif kind == "op":
            img.alpha_composite(OPS["saria"], dest=snap((col.op[0] - 64, col.op[1] - 120)))
        elif kind == "lead":
            img.alpha_composite(OPS["texas"], dest=snap((col.lead[0] - 64, col.lead[1] - 120)))
        elif kind == "it":
            strip(v["k"], tk - v["t0"] if not v["loop"] else tk, v["gp"], v["flip"], v["loop"], v["alpha"])
        elif kind == "raw":
            k, fi, gp, fl, lp = v
            strip(k, fi, snap(gp), fl, lp)
        elif kind == "shot":
            s, p = v
            dx, dy = s["p1"][0] - s["p0"][0], s["p1"][1] - s["p0"][1]
            L = math.hypot(dx, dy) or 1
            d = (dx / L, dy / L)
            nv = (-d[1], d[0])
            hd = snap(p)
            pts = A.syringe(d) if s["kind"] == "syringe" else A.shard(d, tk)
            for (q, w, c) in pts:
                put_px(hd[0] - d[0] * q * PX + nv[0] * w * PX, hd[1] - d[1] * q * PX + nv[1] * w * PX, c, glow=q == 0)
    for (ei, a0, a1) in col.spots:   # 钙化斑：两粒琥珀碎晶
        e = col.enemies[ei]
        if not (a0 <= tk < a1) or tk >= e[2]:
            continue
        al = min(1.0, (a1 - tk) / 6.0)
        for qi in range(2):
            sd = ei * 1.37 + qi * 2.1
            c = snap((e[0] + math.sin(sd) * 10 * 0.55, e[1] - 10 * (0.35 + 0.4 * ((sd * 0.7) % 1.0)) - 4))
            hot = tk - a0 < 2
            put_px(c[0], c[1], A.AMB[6] if hot else A.AMB[5], a=al)
            put_px(c[0] + 2, c[1], A.AMB[4] if hot else A.AMB[3], a=al)
            put_px(c[0], c[1] + 2, A.AMB[2], a=al)
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

E_MAIN = [(196, 150), (214, 128), (210, 176), (250, 146), (244, 112), (262, 186), (300, 156), (176, 116), (292, 124), (320, 186)]
TIERS = {"atk": (0, 1, 2), "s1": (0, 1, 2), "s2": (1, 2), "s3": (2,), "late": (0, 1, 2)}


def sc_atk(t):
    c = Col(t, E_MAIN)
    seq = [(2, 0), (16, 2), (30, 1), (44, 0)]
    for k, (tk, tg) in enumerate(seq):
        if t >= 2 and k == 1:   # 精二：护服满格这一拳变成环冲 + 晶柱环
            c.suit(tk)
        else:
            c.bash(tk, tg)
    return c


def sc_s1(t):
    c = Col(t, E_MAIN, op=(110, 120), lead=(130, 168))
    c.heal(3, 1)
    src = (110 + 8, 120 - 24)
    for j, tg in enumerate([0, 3, 2]):   # 急救针剂（节点）：同时朝附近 3 名敌人掷出
        c.shoot(4, "syringe", src, tg, 460.0)
    c.bash(26, 0)
    return c


def sc_s2(t):
    c = Col(t, E_MAIN, op=(110, 120), lead=(130, 168))
    c.heal(3, 2)
    c.hot = (3, 3 + 75)
    for k in range(1, 4):
        c.add("hot_tick", 3 + 15 * k, c.lead, gy=c.lead[1] + 1)
    c.bash(30, 0)
    return c


def sc_s3(t):
    c = Col(t, E_MAIN, op=(150, 140), lead=None)
    c.add("s3cast_gd", 2, c.op, gd=True)
    c.add("s3cast_up", 2, c.op, gy=c.op[1] + 1)
    c.light((c.op[0], c.op[1] - 16), 200, 0.8, 2, 3)
    c.field = (2, 2 + 120)
    pos = []
    for k in range(10):
        if k < 4:
            an = k * math.tau / 4 + 0.4
            p = (c.op[0] + math.cos(an) * 52, c.op[1] + math.sin(an) * 52 * 0.55 + 4)
        else:
            an = (k * 2.39996) % math.tau
            rr = 180 * (0.45 + 0.4 * ((k * 0.618) % 1.0))
            p = (c.op[0] + math.cos(an) * rr, c.op[1] + math.sin(an) * rr * 0.55 + 4)
        pos.append(p)
    for k, p in enumerate(pos):
        t0 = 2 + round(0.08 * k * 15)
        ev = [(t0, 0), (t0 + 6, 1)]
        if k in (1, 6, 8):   # 被敌人碰碎 → 3 秒后原位重长
            tb = 20 + k * 3
            ev += [(tb, 2), (tb + 5, 3), (tb + 5 + 45, 0), (tb + 5 + 51, 1)]
        c.slots.append({"pos": p, "ev": ev, "flip": k % 3 == 0})
    for tk, tg in [(10, 0), (24, 3), (38, 2), (52, 1)]:   # 钙质化期间空手拳：碎晶喷射
        c.bash(tk, tg, calc=True)
    for tk, k, tg in [(30, 5, 6), (48, 7, 4)]:   # 碎晶（节点）：击碎一根晶柱，碎片飞向区域内敌人
        c.slots[k]["ev"] += [(tk, 2), (tk + 5, 3)]
        for j, tg2 in enumerate([tg, (tg + 3) % len(E_MAIN)]):
            c.shoot(tk, "shard", (c.slots[k]["pos"][0], c.slots[k]["pos"][1] - 16), tg2, 560.0)
    return c


def sc_late(t):
    c = Col(t, E_MAIN, op=(100, 150))
    for tk, tg in [(2, 0), (22, 3)]:
        c.bash(tk, tg)
        e = c.enemies[tg]
        a0 = math.atan2(e[1] - c.op[1], e[0] - c.op[0])
        n = t + 1
        for j in range(n):   # 额外剑气：每档 +1 道，扇形错开 12°
            a = a0 + math.radians(12) * (j - (n - 1) / 2) * 1.5
            skip = 98 * 0.7
            dist = 98 * 1.6
            p = (c.op[0] + math.cos(a) * skip, c.op[1] + math.sin(a) * skip)
            s = 0
            step = 20.0
            spd = 520.0 / 15.0
            k = 0
            while s < dist - skip:
                s += step
                k += 1
                bt = tk + int(s / spd)
                side = 4 if k % 2 == 0 else -4
                sp = (p[0] + math.cos(a) * s - math.sin(a) * side, p[1] + math.sin(a) * s + math.cos(a) * side)
                c.add("qspk_e%d_v%d" % (t, k % 2), bt, sp, gy=sp[1] + 1)
    return c


def sc_branch():
    """分支 / 节点（不分档，精二）：环绕钙晶 + 碎晶（击碎一枚射向敌人）+ 晶簇爆开 + 碎晶·崩落 + 晶垒（站定升起 4 根小晶柱）"""
    c = Col(2, E_MAIN, op=(150, 146))
    c.orbs = 5
    c.orb_broken = {2: (8, 23)}
    p = c.orb_ground(8, 2)
    c.add("orbbrk", 8, (p[0], p[1] - 16), gy=p[1] + 16)
    for tg in (0, 3, 1):
        c.shoot(8, "shard", (p[0], p[1] - 16), tg, 560.0)
    c.bash(20, 0)
    c.add("markb_up", 21, c.enemies[0], gy=c.enemies[0][1] + 1)
    c.add("markb_gd", 21, c.enemies[0], gd=True)
    c.add("shat2_r45_up", 34, c.op, gy=c.op[1] + 1)
    c.add("shat2_r45_gd", 34, c.op, gd=True)
    pts = []
    for k in range(4):
        an = k * math.tau / 4
        pts.append((c.op[0] + math.cos(an) * 70, c.op[1] + math.sin(an) * 70 * 0.55))
    c.posts = (40, 40 + 45, pts, True)
    for k, q in enumerate(pts):
        c.add("pilS%d_brk" % (k % 3), 85, q, gy=q[1] + 1)
    return c


def sc_link():
    c = Col(2, E_MAIN, op=(100, 120), lead=(150, 160))
    cz = (240, 150)
    c.add("lk_b", 3, c.lead, gy=c.lead[1] - 1)
    c.add("lk_f", 3, c.lead, gy=c.lead[1] + 1)
    for j in range(7):
        a = j * 2.39996
        rr = 150 * (0.25 + 0.55 * ((j * 0.618) % 1.0))
        c.add("lk_patch_v%d" % (j % 3), 3, (cz[0] + math.cos(a) * rr, cz[1] + math.sin(a) * rr), gd=True)
    c.light((c.lead[0], c.lead[1] - 20), 110, 0.55, 3, 3)
    return c


NAMES = {"atk": "普攻「盾击」", "s1": "S1「急救」（+ 急救针剂节点）", "s2": "S2「药物配置」", "s3": "S3「钙质化」", "late": "后期额外攻击「晶刺地波」"}
SCENES = {"atk": (sc_atk, 60, (200, 140)), "s1": (sc_s1, 40, (150, 130)), "s2": (sc_s2, 50, (140, 130)), "s3": (sc_s3, 66, (180, 130)), "late": (sc_late, 40, (190, 140))}


def main():
    global ENEMY, OPS
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    ap.add_argument("--out", default=os.path.join(MAIN, "Claude outputs", "pxplane_saria_1105", "gif"))
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    lib = Lib()
    en = sprite(os.path.join(ROOT, "game", "art", "enemies", "offspring", "e_offspring@2x.png"), 4)
    arr = np.asarray(en).astype(np.float32)
    arr[..., :3] = arr[..., :3] * 0.32 + np.array([10, 12, 14])
    ENEMY = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")
    OPS = {"saria": sprite(os.path.join(ROOT, "game", "art", "operators", "saria", "op_saria_idle@2x.png"), 8),
           "texas": sprite(os.path.join(ROOT, "game", "art", "operators", "texas", "op_texas_idle@2x.png"), 7)}
    only = set(x for x in a.only.split(",") if x)
    title = "塞雷娅 · 转平面 · 15 fps 原速"
    for name, (fn, n, zc) in SCENES.items():
        if only and name not in only:
            continue
        cols = [("%s  精英 %d" % (NAMES[name], t), fn(t)) for t in TIERS[name]]
        gif(lib, cols, n, os.path.join(a.out, "saria_%s.gif" % name), title, zc)
    if not only or "branch" in only:
        gif(lib, [("节点：环绕钙晶 / 碎晶 / 晶簇 / 崩落 / 晶垒（不分档）", sc_branch())], 90, os.path.join(a.out, "saria_branch.gif"), title, (170, 140))
    if not only or "link" in only:
        gif(lib, [("连携技「钙质护盾」（link/v2 缺省，不分档）", sc_link())], 30, os.path.join(a.out, "saria_link.gif"), title, (190, 150))


if __name__ == "__main__":
    main()
