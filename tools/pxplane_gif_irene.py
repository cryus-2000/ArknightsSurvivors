#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""艾丽妮转平面（docs/272）送审 GIF：上 GCP 前先给用户看，只用 Python、不开 Godot。

帧条读 tools/pxplane_bake_irene.py 烤出的 game/art/fx/pxp/pxp_ir_*.png + game/data/pxp_irene.json（与游戏同一份）；
刺击光刃、贯穿、手炮弹道、剑气细刺、提灯光圈 / 光尘 / 提灯用 tools/pxplane_irene_art.py 里与 fx_pxplane_ir.gd 同算法的 Python 版逐格画。
摆法照游戏：刺击长 153、每 0.8 秒一刺、两段（第 2 段晚 3 拍）；裂潮半径 153 × 1.3、半角 0.8；裂潮余波半径 150、半角 0.785；判决半径 160，
随后 0.35 秒起每 0.25 秒一发手炮（半径 40）；起风浮空 1.0 秒高 26、裂潮浮空 2.0 秒高 34、判决浮空 4 秒高 44、挑刺 0.4 秒高 10、余波 0.8 秒高 30。
浮空的怪：画面上抬到浮空高度，脚下影子随高度缩小变淡，悬停时上下浮动 1 美术像素（只画）。
每招一张：E0 / E1 / E2 左右并排（只放实际存在的档）；上半 1 倍（实机大小：1 美术像素 = 2 屏幕像素）、下半 2 倍放大；15 fps 原速循环。
光照近似：整体压暗到 AMBIENT，命中 / 爆点挂一盏短照地光；热芯（emit 点）近似发光层加一层柔光。

用法：python tools/pxplane_gif_irene.py [--only atk,s1] [--out 目录]
"""
import argparse, json, math, os, sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pxplane_irene_art as A

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAIN = os.path.dirname(os.path.dirname(os.path.dirname(ROOT))) if ".claude" in ROOT else ROOT
PX = 2
W, H = 440, 270
GROUND = (36, 46, 48)
DIRS = [-90, -45, 0, 45, 90]
FONT = "C:/Windows/Fonts/msyh.ttc"
AMBIENT = 0.8
GOLD_L = (1.0, 0.85, 0.5)
TIDE_L = (0.5, 0.75, 1.0)
SQ = 0.72
LEN = 153.0
DUMP = set()
DUMP_ONLY = False


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
        self.meta = {k: v for k, v in json.load(open(os.path.join(ROOT, "game", "data", "pxp_irene.json"), encoding="utf-8")).items() if k != "_doc"}
        self.tex = {}

    def frame(self, k, fi, loop=False):
        m = self.meta[k]
        n = m["n"]
        if loop:
            fi %= n
        if fi < 0 or fi >= n:
            return None
        if k not in self.tex:
            self.tex[k] = Image.open(os.path.join(ROOT, "game", "art", "fx", "pxp", "pxp_ir_%s.png" % k.replace("_d-", "_dm").lower())).convert("RGBA")
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
        self.items = []      # 帧条件
        self.rt = []         # 运行时件 {kind, t0, ...}
        self.enemies = [{"p": (float(x), float(y)), "dead": 10 ** 9, "air": []} for x, y in enemies]
        self.op = op
        self.lead = lead
        self.lights = []
        self.lamp = None     # 提灯（起拍, 止拍, raised）
        self.qi = []

    def add(self, k, tk, gp, flip=False, gd=False, gy=None, loop=False, until=None, fe=None):
        self.items.append({"k": k, "t0": tk, "gp": snap(gp), "flip": flip, "gd": gd, "gy": gp[1] if gy is None else gy, "loop": loop, "until": until, "fe": fe})

    def light(self, at, r, i, tk, n=2, col=GOLD_L):
        self.lights.append((at[0], at[1] + 6, r, i, tk, n, col))

    def launch(self, ei, tk, dur, h):
        if ei is None:
            return
        self.enemies[ei]["air"].append((tk, int(round(dur * 15)), h))

    def air_h(self, ei, tk):
        h = 0.0
        for (t0, n, hh) in self.enemies[ei]["air"]:
            if t0 <= tk < t0 + n:
                k = (tk - t0) / n
                h = max(h, math.sin(k * math.pi) * hh)
        return h

    def epos(self, ei, tk, lift=True):
        e = self.enemies[ei]
        return (e["p"][0], e["p"][1] - (self.air_h(ei, tk) if lift else 0.0))

    def nearest(self, src, maxd=1e9, tk=0):
        best = None
        for ei, e in enumerate(self.enemies):
            if e["dead"] <= tk:
                continue
            d = math.hypot(e["p"][0] - src[0], e["p"][1] - src[1])
            if d < maxd and (best is None or d < best[0]):
                best = (d, ei)
        return best[1] if best else None

    def thrust(self, tk, tg, gust=False, stage=1, L=LEN, launch=None):
        """一段刺击：朝 tg 号敌人，带宽 26 内的都刺中（穿透）；返回刺中的（由近到远）"""
        e = self.enemies[tg]
        org = (self.op[0], self.op[1] - 12)
        dx, dy = e["p"][0] - org[0], e["p"][1] - org[1]
        dl = math.hypot(dx, dy) or 1.0
        d = (dx / dl, dy / dl)
        hits = []
        for ei, q in enumerate(self.enemies):
            if q["dead"] <= tk:
                continue
            vx, vy = q["p"][0] - org[0], q["p"][1] - org[1]
            al = vx * d[0] + vy * d[1]
            pe = abs(-vx * d[1] + vy * d[0])
            if -10 < al < L + 10 and pe < 13 + 10:
                hits.append((al, ei))
        hits.sort()
        self.rt.append({"kind": "lance", "t0": tk, "d": d, "L": L / 2.0, "gust": gust, "stage": stage})
        for _, ei in hits[:3]:
            self.rt.append({"kind": "pierce", "t0": tk, "d": d, "e": ei})
        if hits:
            q = self.enemies[hits[0][1]]
            self.light((q["p"][0], q["p"][1] - 6), 90 if not gust else 130, 0.5 if not gust else 0.7, tk)
        return [ei for _, ei in hits]

    def cannon(self, tk, ei):
        mz = (self.op[0] + 12, self.op[1] - 30)
        self.add("muz", tk, mz, gy=self.op[1] + 1)
        tp = self.epos(ei, tk + 1)
        self.rt.append({"kind": "tracer", "t0": tk, "a": mz, "b": (tp[0], tp[1] - 10)})
        p = self.enemies[ei]["p"]
        self.add("boom_up", tk + 1, (p[0], p[1] - self.air_h(ei, tk + 1)), gy=p[1] + 1)
        self.add("boom_gd", tk + 1, p, gd=True)
        self.light((p[0], p[1] - 10), 110, 0.6, tk + 1)

    def cleave(self, tk, tg, kind, R_w, half, dur=2.0, h=34, maxn=8):
        e = self.enemies[tg]
        ang = math.atan2(e["p"][1] - self.op[1], e["p"][0] - self.op[0])
        hits = []
        for ei, q in enumerate(self.enemies):
            dx, dy = q["p"][0] - self.op[0], q["p"][1] - self.op[1]
            da = abs((math.atan2(dy, dx) - ang + math.pi) % math.tau - math.pi)
            dist = math.hypot(dx, dy)
            if dist < R_w + 8 and da < half + 0.1:
                hits.append((dist, ei))
        hits.sort()
        d, fl = pick_dir(math.degrees(ang))
        if kind == "s2":
            R = near(A.S2_R, R_w / 2)
            self.add("s2_r%d_e%d_up_d%d" % (R, max(1, self.t), d), tk, self.op, fl, gy=self.op[1] + 1)
            self.add("s2_r%d_gd_d%d" % (R, d), tk, self.op, fl, gd=True)
            self.light((self.op[0] + math.cos(ang) * R_w * 0.6, self.op[1] + math.sin(ang) * R_w * 0.6), 180, 0.75, tk + 1, 3)
        else:
            R = near(A.FIN_R, R_w / 2)
            self.add("fin_r%d_up_d%d" % (R, d), tk, self.op, fl, gy=self.op[1] + 1)
            self.add("fin_r%d_gd_d%d" % (R, d), tk, self.op, fl, gd=True)
            self.light((self.op[0] + math.cos(ang) * R_w * 0.6, self.op[1] + math.sin(ang) * R_w * 0.6), 150, 0.7, tk + 1, 2)
        out = [ei for _, ei in hits[:maxn]]
        for ei in out:
            self.launch(ei, tk + 1, dur, h)
        return out


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

    def pts(origin, lst):
        for q in lst:
            if len(q) == 4 and isinstance(q[3], bool):
                put_px(origin[0] + q[0] * PX, origin[1] + q[1] * PX, q[2], glow=q[3])
            else:
                put_px(origin[0] + q[0] * PX, origin[1] + q[1] * PX, q[2], a=q[3])

    def strip(k, fi, gp, flip=False, loop=False):
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
        l, t = int(left), int(top)
        if l >= W or t >= H or l + big.width <= 0 or t + big.height <= 0:
            return
        img.alpha_composite(big, dest=(max(0, l), max(0, t)), source=(max(0, -l), max(0, -t)))
        for q in m["emit"][fi2]:
            x = q[0] if not flip else m["w"] - 1 - q[0]
            ed.rectangle([l + x * PX, t + q[1] * PX, l + x * PX + PX - 1, t + q[1] * PX + PX - 1], fill=tuple(int(q[2][i:i + 2], 16) for i in (0, 2, 4)))

    def item_on(it):
        return tk >= it["t0"] and (it["until"] is None or tk < it["until"])

    def item_pos(it):
        if it["fe"] is not None:   # 跟着那只（浮空时跟着抬）
            ei, oy = it["fe"]
            p = col.epos(ei, tk)
            return snap((p[0], p[1] + oy))
        return it["gp"]

    # 地面层：敌人影子（浮空时缩小变淡）、贴地件、刺击投影 / 潮痕、提灯光圈
    for ei, e in enumerate(col.enemies):
        if tk >= e["dead"]:
            continue
        h = col.air_h(ei, tk)
        hk = max(0.5, 1.0 - h / 50.0)
        rx, ry = 9 * hk, 4 * hk
        x, y = e["p"]
        ImageDraw.Draw(img).ellipse([x - rx, y + 4 - ry, x + rx, y + 4 + ry], fill=(18, 22, 24, 255) if hk > 0.8 else (24, 30, 32, 255))
    for it in col.items:
        if it["gd"] and item_on(it):
            strip(it["k"], tk - it["t0"] if not it["loop"] else tk, item_pos(it), it["flip"], it["loop"])
    for r in col.rt:
        f = tk - r["t0"]
        if r["kind"] == "lance" and 0 <= f <= 6:
            pts(snap(col.op), A.lance_gd(r["L"], r["d"], f, col.t, r["gust"]))
        if r["kind"] == "lampring" and 0 <= f < r["n"]:
            pts(snap(r["c"]), A.lamp_ring(r["r"], tk, f / 15.0, r["n"] / 15.0))

    # 排序层
    sort = []
    for ei, e in enumerate(col.enemies):
        if tk < e["dead"]:
            sort.append((e["p"][1], "e", ei))
    sort.append((col.op[1], "op", None))
    if col.lead:
        sort.append((col.lead[1], "lead", None))
    for it in col.items:
        if not it["gd"] and item_on(it):
            gy = it["gy"]
            if it["fe"] is not None:
                gy = col.enemies[it["fe"][0]]["p"][1] + 1
            sort.append((gy + 1, "it", it))
    for r in col.rt:
        f = tk - r["t0"]
        if f < 0:
            continue
        if r["kind"] == "lance" and f <= 5:
            tip = (col.op[0] + r["d"][0] * r["L"] * 2, col.op[1] + r["d"][1] * r["L"] * 2)
            sort.append((max(col.op[1], tip[1]) + 1, "lance", r))
        elif r["kind"] == "pierce" and f <= 2:
            sort.append((col.enemies[r["e"]]["p"][1] + 1, "pierce", r))
        elif r["kind"] == "tracer" and f <= 1:
            sort.append((max(r["a"][1], r["b"][1]) + 20, "tracer", r))
        elif r["kind"] == "motes" and f < r["n"]:
            sort.append((r["c"][1] + 1, "motes", r))
        elif r["kind"] == "link_lance" and f <= 5:
            sort.append((max(r["a"][1], r["b"][1]) + 1, "llance", r))
    for q in col.qi:
        if q["t0"] <= tk < q["t1"]:
            u = (tk - q["t0"]) / 15.0
            p = (q["p0"][0] + q["v"][0] * u, q["p0"][1] + q["v"][1] * u)
            sort.append((p[1] + 1, "qi", (q, p)))
    sort.sort(key=lambda s: s[0])
    for _, kind, v in sort:
        if kind == "e":
            p = col.epos(v, tk)
            bob = 0
            for (t0, n, hh) in col.enemies[v]["air"]:
                if t0 + 3 <= tk < t0 + n - 4 and ((tk // 3 + v) % 2):
                    bob = 2
            img.alpha_composite(ENEMY, dest=(int(p[0] - ENEMY.width // 2), int(p[1] - bob - ENEMY.height + 6)))
        elif kind == "op":
            img.alpha_composite(OPS["irene"], dest=snap((col.op[0] - 64, col.op[1] - 120)))
            if col.lamp and col.lamp[0] <= tk < col.lamp[1]:
                lp = (col.op[0] + 16, col.op[1] - (56 if col.lamp[2] else 22))
                pts(snap(lp), A.lantern(tk, col.lamp[2]))
                col_lt = (lp[0], lp[1] + 30)
        elif kind == "lead":
            img.alpha_composite(OPS["texas"], dest=snap((col.lead[0] - 64, col.lead[1] - 120)))
        elif kind == "it":
            strip(v["k"], tk - v["t0"] if not v["loop"] else tk, item_pos(v), v["flip"], v["loop"])
        elif kind == "lance":
            pts(snap(col.op), A.lance(v["L"], v["d"], tk - v["t0"], col.t, v["gust"]))
        elif kind == "llance":
            a, b = v["a"], v["b"]
            dx, dy = b[0] - a[0], b[1] - a[1]
            L = math.hypot(dx, dy)
            pts(snap(a), A.lance(L / 2.0, (dx / L, dy / L), tk - v["t0"], 2, False, link=True))
        elif kind == "pierce":
            p = col.epos(v["e"], tk)
            pts(snap((p[0], p[1] - 6)), A.pierce(v["d"], tk - v["t0"], col.t))
        elif kind == "tracer":
            a, b = v["a"], v["b"]
            pp = A.tracer((0, 0), ((b[0] - a[0]) / 2.0, (b[1] - a[1]) / 2.0), tk - v["t0"])
            pts(snap(a), pp)
        elif kind == "motes":
            pts(snap(v["c"]), A.lamp_motes(v["r"], tk, 1.3))
        elif kind == "qi":
            q, p = v
            vl = math.hypot(*q["v"]) or 1
            pts(snap((p[0], p[1] - 16)), A.qi_needle((q["v"][0] / vl, q["v"][1] / vl), col.t, tk))
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
        if tk in DUMP:   # 自查用：--dump 3,5 把这几拍的整张存成 PNG
            sheet.save(path.replace(".gif", "_t%02d.png" % tk))
    if DUMP_ONLY:
        return
    pick = frames[:: max(1, len(frames) // 12)][:12]   # 调色板取多帧拼图（只取一帧会丢掉别的帧才有的潮水蓝）
    mos = Image.new("RGB", (frames[0].width, frames[0].height * len(pick)))
    for i, fr in enumerate(pick):
        mos.paste(fr, (0, i * frames[0].height))
    pal = mos.quantize(colors=255, method=Image.MEDIANCUT)
    q = [f.quantize(palette=pal, dither=Image.NONE) for f in frames]
    dur = [70 if i % 3 != 1 else 60 for i in range(len(q))]
    q[0].save(path, save_all=True, append_images=q[1:], duration=dur, loop=0, optimize=False, disposal=1)
    print(os.path.basename(path), len(q), "帧", "%.0f KB" % (os.path.getsize(path) / 1024))


# ---------------------------------------------------------------- 每招的摆法

E_MAIN = [(214, 150), (250, 140), (232, 176), (282, 158), (262, 118), (300, 190), (320, 140), (204, 112), (340, 170), (300, 100)]
TIERS = {"atk": (0, 1, 2), "s1": (0, 1, 2), "s2": (1, 2), "s3": (2,), "late": (0, 1, 2)}


def _atk_round(c, tk, tg, fin=False, pick=False):
    """普攻一轮：第 1 段 + 3 拍后第 2 段（精二每第 3 轮第 2 段换裂潮余波 + 0.15 秒后手炮追击浮空的 2 名；精一第 2 段首中挑刺）"""
    hits = c.thrust(tk, tg, stage=1)
    if c.t >= 2:
        for ei in hits[:1]:
            if c.air_h(ei, tk) > 0:
                c.cannon(tk + 1, ei)   # 追诉
    if fin:
        out = c.cleave(tk + 3, tg, "fin", 150.0, 0.785, dur=0.8, h=30, maxn=99)
        air = [ei for ei in out][:2]
        for j, ei in enumerate(air):
            c.cannon(tk + 5 + j, ei)
        return
    h2 = c.thrust(tk + 3, tg, stage=2)
    if pick and h2:
        c.launch(h2[0], tk + 4, 0.4, 10)
        c.add("pick_up", tk + 4, c.enemies[h2[0]]["p"], gy=c.enemies[h2[0]]["p"][1] + 1, fe=(h2[0], 0))


def sc_atk(t):
    c = Col(t, E_MAIN, op=(110, 150))
    for k, (tk, tg) in enumerate([(2, 0), (14, 3), (26, 1), (38, 2), (50, 0)]):
        _atk_round(c, tk, tg, fin=(t >= 2 and k == 2), pick=(t >= 1 and k in (0, 3)))
    return c


def sc_s1(t):
    c = Col(t, E_MAIN, op=(110, 150))
    hits = c.thrust(3, 0, gust=True)
    if hits:
        e0 = hits[0]
        c.launch(e0, 4, 1.0, 26)
        p = c.enemies[e0]["p"]
        c.add("gust_e%d_up" % t, 4, p, gy=p[1] + 1)
        if t >= 1:
            c.add("gust_gd", 4, p, gd=True)
        c.light((p[0], p[1] - 10), 140, 0.75, 4, 3, TIDE_L)
    c.thrust(6, 0, gust=True, stage=2)
    _atk_round(c, 30, 3)
    return c


def sc_s2(t):
    c = Col(t, E_MAIN, op=(110, 150))
    c.cleave(3, 0, "s2", LEN * 1.3, 0.8, dur=2.0, h=34)
    _atk_round(c, 26, 3)
    _atk_round(c, 40, 0)
    return c


def sc_s3(t):
    c = Col(t, E_MAIN, op=(190, 150))
    R = near(A.S3_R, 160 / 2)
    c.add("s3_r%d_gd" % R, 2, c.op, gd=True)
    c.add("s3_r%d_up" % R, 2, c.op, gy=c.op[1] + 1)
    c.light((c.op[0], c.op[1] - 16), 220, 0.85, 2, 3)
    c.lamp = (0, 64, True)
    for ei, e in enumerate(c.enemies):
        if math.hypot(e["p"][0] - c.op[0], e["p"][1] - c.op[1]) < 168:
            c.launch(ei, 3, 4.0, 44)
    order = [0, 3, 1, 4, 2, 6, 7, 5, 9, 8, 0, 3]
    for i in range(12):
        tk = 2 + 5 + int(i * 3.75)
        c.cannon(tk, order[i])
    return c


def sc_late(t):
    c = Col(t, E_MAIN, op=(100, 150))
    for tk, tg in [(2, 0), (22, 3)]:
        _atk_round(c, tk, tg)
        e = c.enemies[tg]
        a0 = math.atan2(e["p"][1] - c.op[1], e["p"][0] - c.op[0])
        n = t + 1
        for j in range(n):
            off = 0.0 if j == 0 else math.radians(12) * (1 if j % 2 else -1) * (1 + (j - 1) // 2)
            a = a0 + off
            skip = LEN * 1.15 * 0.7
            dist = LEN * 1.15 * 1.6
            p0 = (c.op[0] + math.cos(a) * skip, c.op[1] + math.sin(a) * skip)
            v = (math.cos(a) * 520, math.sin(a) * 520)
            c.qi.append({"t0": tk, "t1": tk + int((dist - skip) / 520 * 15) + 1, "p0": p0, "v": v})
    return c


def sc_branch():
    """分支 / 节点（不分档，精二）：严律刺印 + 卷风（起风卷起周围）+ 卷风·追斩 + 二度裂潮 + 裂潮·三度 + 响应起风"""
    c = Col(2, E_MAIN, op=(150, 150))
    h = c.thrust(2, 0)
    if h:   # 严律：第 1 段首中停顿 0.3 秒，头顶刺印
        p = c.enemies[h[0]]["p"]
        c.add("brand", 2, p, gy=p[1] + 1, loop=True, until=2 + 7, fe=(h[0], -32))
    c.thrust(5, 0, stage=2)
    h = c.thrust(16, 3, gust=True)   # 起风 + 卷风
    if h:
        e0 = h[0]
        c.launch(e0, 17, 1.0, 26)
        p = c.enemies[e0]["p"]
        c.add("gust_e2_up", 17, p, gy=p[1] + 1)
        c.add("gust_gd", 17, p, gd=True)
        c.add("gale_r35_gd", 17, p, gd=True)
        c.add("gale_r35_up", 17, p, gy=p[1] + 1)
        for ei, e in enumerate(c.enemies):
            if ei != e0 and math.hypot(e["p"][0] - p[0], e["p"][1] - p[1]) < 76:
                c.launch(ei, 17, 0.8, 20)
    c.add("nova_up", 28, c.op, gy=c.op[1] + 1)   # 卷风·追斩（起风 0.8 秒后）
    c.light((c.op[0], c.op[1] - 20), 160, 0.7, 28, 2)
    c.cleave(40, 1, "s2", LEN * 1.3, 0.8)          # 裂潮
    c.cleave(45, 2, "s2", LEN * 1.3, 0.8)          # 二度裂潮（0.35 秒后重新瞄准）
    c.add("tide3_up", 51, c.op, gy=c.op[1] + 1)    # 裂潮·三度（0.7 秒后）
    c.add("tide3_gd", 51, c.op, gd=True)
    c.light((c.op[0], c.op[1] - 10), 180, 0.75, 51, 3, TIDE_L)
    c.add("gale_r45_gd", 66, c.op, gd=True)        # 响应「起风」（切归队）
    c.add("gale_r45_up", 66, c.op, gy=c.op[1] + 1)
    return c


def sc_link():
    c = Col(2, E_MAIN, op=(110, 150), lead=(80, 190))
    cz = (270, 150)
    r = 150.0
    c.lamp = (0, 14, False)
    c.rt.append({"kind": "lampring", "t0": 1, "n": 14, "c": cz, "r": r / 2})
    c.rt.append({"kind": "motes", "t0": 1, "n": 14, "c": cz, "r": r / 2})
    c.light(cz, 190, 0.7, 1, 12)
    tg = c.nearest(cz)
    tp = c.enemies[tg]["p"]
    d = ((tp[0] - c.op[0]), (tp[1] - c.op[1]))
    dl = math.hypot(*d)
    d = (d[0] / dl, d[1] / dl)
    fp = (c.op[0], c.op[1] - 0)
    tp2 = (tp[0] + d[0] * 110, tp[1] + d[1] * 110)
    c.rt.append({"kind": "link_lance", "t0": 7, "a": fp, "b": tp2})
    for ei, e in enumerate(c.enemies):
        vx, vy = e["p"][0] - fp[0], e["p"][1] - fp[1]
        al = vx * d[0] + vy * d[1]
        if 0 < al < dl + 110 and abs(-vx * d[1] + vy * d[0]) < 30:
            c.rt.append({"kind": "pierce", "t0": 7, "d": d, "e": ei})
    c.light(((fp[0] + tp2[0]) / 2, (fp[1] + tp2[1]) / 2), 160, 0.7, 7, 2)
    return c


NAMES = {"atk": "普攻「刺剑」", "s1": "S1「起风」", "s2": "S2「裂潮」", "s3": "S3「判决」", "late": "后期额外攻击「光刺」"}
SCENES = {"atk": (sc_atk, 64, (220, 140)), "s1": (sc_s1, 46, (200, 130)), "s2": (sc_s2, 56, (220, 140)), "s3": (sc_s3, 64, (220, 120)), "late": (sc_late, 40, (230, 140))}


def main():
    global ENEMY, OPS
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    ap.add_argument("--dump", default="")
    ap.add_argument("--out", default=os.path.join(MAIN, "Claude outputs", "pxplane_irene_1105", "gif"))
    a = ap.parse_args()
    global DUMP, DUMP_ONLY
    DUMP = set(int(x) for x in a.dump.split(",") if x)
    DUMP_ONLY = bool(DUMP)
    os.makedirs(a.out, exist_ok=True)
    lib = Lib()
    en = sprite(os.path.join(ROOT, "game", "art", "enemies", "offspring", "e_offspring@2x.png"), 4)
    arr = np.asarray(en).astype(np.float32)
    arr[..., :3] = arr[..., :3] * 0.32 + np.array([10, 12, 14])
    ENEMY = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")
    OPS = {"irene": sprite(os.path.join(ROOT, "game", "art", "operators", "irene", "op_irene_idle@2x.png"), 8),
           "texas": sprite(os.path.join(ROOT, "game", "art", "operators", "texas", "op_texas_idle@2x.png"), 7)}
    only = set(x for x in a.only.split(",") if x)
    title = "艾丽妮 · 转平面 · 15 fps 原速"
    for name, (fn, n, zc) in SCENES.items():
        if only and name not in only:
            continue
        cols = [("%s  精英 %d" % (NAMES[name], t), fn(t)) for t in TIERS[name]]
        gif(lib, cols, n, os.path.join(a.out, "irene_%s.gif" % name), title, zc)
    if not only or "branch" in only:
        gif(lib, [("节点：严律 / 起风+卷风 / 卷风·追斩 / 二度裂潮 / 裂潮·三度 / 响应起风（不分档）", sc_branch())], 80, os.path.join(a.out, "irene_branch.gif"), title, (210, 140))
    if not only or "link" in only:
        gif(lib, [("连携技「提灯一照」（link/v2 缺省，不分档）", sc_link())], 26, os.path.join(a.out, "irene_link.gif"), title, (210, 150))


if __name__ == "__main__":
    main()
