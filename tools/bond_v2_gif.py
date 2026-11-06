#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""羁绊技 v2 示意 GIF（docs/294，11-06）：只用 Python，不开 Godot。
三对：宿敌（德克萨斯 × 拉普兰德）「十字旧怨」、企鹅物流（德克萨斯 × 能天使）「急件航线」、灯下审决（艾丽妮 × 流明）「提灯宣判」。
每张 = 解锁演出卡（约 1.1 秒）→ 第一次释放 → 余波；背景是一群向小队逼近的怪（约 90 只），看「一眼看懂、覆盖一片」。
1 倍 = 640×360（相当于 1280×720 实机画面的一半，像素格 1 px）；2 倍 = 最近邻放大。干员 / 敌人贴图直接用游戏里的帧条，特效按 pixelfx 主形 + Noita 辉光画。
用法：python tools/bond_v2_gif.py [--out 目录] [--only rival,penguin,inq]
"""
import argparse, json, math, os, random

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAIN = os.path.dirname(os.path.dirname(os.path.dirname(ROOT))) if ".claude" in ROOT else ROOT
FONT = "C:/Windows/Fonts/msyh.ttc"
FONTB = "C:/Windows/Fonts/msyhbd.ttc"
W, H = 640, 360
HDR = 24
FPS = 30
T_END = 4.6
CARD = (0.35, 1.55)   # 演出卡出现 / 消失
T0 = 1.45             # 第一次释放
SQUAD = (150, 215)    # 队长脚底

# 角色色（游戏内现用色，和 PRTS 立绘一致：skill_link.gd / melee_impact.gd）
TX = {"core": (255, 242, 220), "side": (255, 172, 60), "deep": (156, 70, 16), "glow": (1.0, 0.72, 0.38)}           # 德克萨斯琥珀 #ffac3c
LP = {"core": (232, 226, 255), "side": (168, 150, 255), "deep": (96, 84, 170), "glow": (0.62, 0.56, 1.0)}         # 拉普兰德淡紫灰
EX = {"core": (255, 226, 206), "side": (255, 115, 89), "deep": (150, 40, 30), "glow": (1.0, 0.45, 0.32)}            # 能天使红橙
IR = {"core": (246, 248, 255), "side": (255, 217, 115), "deep": (150, 120, 60), "glow": (0.95, 0.9, 0.75)}          # 艾丽妮银白 + 淡金
LU = {"core": (225, 248, 255), "side": (153, 230, 255), "deep": (40, 110, 140), "glow": (0.5, 0.88, 1.0)}           # 流明青


def frames_of(path, n=None, fw=None, scale=1.0):
    im = Image.open(path).convert("RGBA")
    if fw is None:
        fw = im.width // n
    n = im.width // fw
    out = [im.crop((i * fw, 0, (i + 1) * fw, im.height)) for i in range(n)]
    if scale != 1.0:
        out = [f.resize((max(1, int(f.width * scale)), max(1, int(f.height * scale))), Image.NEAREST) for f in out]
    return out


def tint(im, mul=(1, 1, 1), add=(0, 0, 0), al=1.0):
    a = np.asarray(im).astype(float).copy()
    for c in range(3):
        a[..., c] = a[..., c] * mul[c] + add[c] * (a[..., 3] > 0)
    a[..., 3] *= al
    return Image.fromarray(a.clip(0, 255).astype(np.uint8))


def clamp(x, a=0.0, b=1.0):
    return a if x < a else (b if x > b else x)


def seg_dist(p, a, c):
    ax, ay = c[0] - a[0], c[1] - a[1]
    L2 = ax * ax + ay * ay
    u = clamp(((p[0] - a[0]) * ax + (p[1] - a[1]) * ay) / L2) if L2 > 0 else 0.0
    return math.dist(p, (a[0] + ax * u, a[1] + ay * u)), u


class Canvas:
    def __init__(self, img):
        self.px = np.asarray(img.convert("RGB")).astype(float)
        self.gl = np.zeros((H, W, 3))

    def cell(self, x, y, col, a=1.0):
        x, y = int(math.floor(x)), int(math.floor(y))
        if 0 <= x < W and 0 <= y < H:
            self.px[y, x] = self.px[y, x] * (1 - a) + np.array(col, dtype=float) * a

    def glow(self, x, y, col, s=1.0):
        x, y = int(x), int(y)
        if 0 <= x < W and 0 <= y < H:
            self.gl[y, x] += np.array(col) * s

    def lamp(self, lx, ly, r, col, inten, squash=0.6):
        yy, xx = np.mgrid[0:H, 0:W]
        d = np.sqrt(((xx - lx) / r) ** 2 + ((yy - ly) / (r * squash)) ** 2)
        k = np.clip(1 - d, 0, 1) ** 2 * inten
        for c in range(3):
            self.px[..., c] += k * col[c] / 255.0

    def finish(self):
        if self.gl.any():
            g8 = Image.fromarray((np.clip(self.gl, 0, 1) * 255).astype(np.uint8))
            b1 = np.asarray(g8.filter(ImageFilter.GaussianBlur(1.6))).astype(float)
            b2 = np.asarray(g8.filter(ImageFilter.GaussianBlur(4.5))).astype(float)
            self.px += b1 * 1.6 + b2 * 2.4
        return Image.fromarray(self.px.clip(0, 255).astype(np.uint8))


def slash(cv, a, c, t, t0, dur, hold, fade, pal, w=2, glow_s=1.0):
    """pixelfx 式斩线：芯近白、两侧一格角色色；生长时头部最亮，满长后保持，再断成碎段消失（_tx_draw_line1 同口径）。"""
    if t < t0:
        return
    L = math.dist(a, c)
    grow = clamp((t - t0) / dur)
    age = t - (t0 + dur)
    if age > hold + fade:
        return
    brk = clamp((age - hold) / fade) if age > hold else 0.0
    dv = ((c[0] - a[0]) / L, (c[1] - a[1]) / L)
    nv = (-dv[1], dv[0])
    n = int(L * grow)
    fresh = age < 0.12
    for i in range(n + 1):
        u = i / L
        prof = math.sin(math.pi * clamp(u * 0.94 + 0.03)) ** 0.6
        if brk > 0 and math.fmod(i * 0.618034 + 0.17 * int(t * 15), 1.0) < brk * 1.05:
            continue
        cw = max(1, round(w * prof))
        head = grow < 1 and i > n - 10
        core = (255, 255, 255) if (fresh or head) else pal["core"]
        side = pal["side"] if not brk else pal["deep"]
        qx = a[0] + dv[0] * i - nv[0] * (cw // 2)
        qy = a[1] + dv[1] * i - nv[1] * (cw // 2)
        for k in range(cw):
            cv.cell(qx + nv[0] * k, qy + nv[1] * k, core)
        if prof > 0.2:
            cv.cell(qx - nv[0], qy - nv[1], side)
            cv.cell(qx + nv[0] * cw, qy + nv[1] * cw, side)
        if (fresh or head) and prof > 0.2:
            cv.glow(qx, qy, pal["glow"], 0.9 * glow_s)
        elif i % 3 == 0 and not brk:
            cv.glow(qx, qy, pal["glow"], 0.35 * glow_s)


def ring(cv, c, r, pal, t, al=1.0, dash=True, squash=0.62, w=2):
    """地面描边圆（不填充：docs/293 L2 大面积半透明填充最糊）。"""
    n = int(2 * math.pi * r * 1.2)
    for i in range(n):
        ang = i / n * math.tau
        seg = int((ang + t * 0.8) / (math.tau / 36))
        if dash and seg % 3 == 2:
            continue
        x = c[0] + math.cos(ang) * r
        y = c[1] + math.sin(ang) * r * squash
        cv.cell(x, y, pal["core"], al)
        cv.cell(x, y + 1, pal["side"], al * 0.8)
        if w > 2:
            cv.cell(x, y - 1, pal["side"], al * 0.6)
        if i % 4 == 0:
            cv.glow(x, y, pal["glow"], 0.4 * al)


class Sparks:
    def __init__(self):
        self.ps = []

    def burst(self, t0, p, n, pal, rng, sp=(30, 110), life=(0.2, 0.45), up=30):
        for _ in range(n):
            ang = rng.uniform(0, math.tau)
            s = rng.uniform(*sp)
            self.ps.append((t0, p, math.cos(ang) * s, math.sin(ang) * s * 0.7 - up, rng.uniform(*life), pal))

    def draw(self, cv, t):
        for t0, p, vx, vy, life, pal in self.ps:
            age = t - t0
            if 0 <= age < life:
                x = p[0] + vx * age
                y = p[1] + vy * age + 140 * age * age
                k = age / life
                col = (255, 255, 255) if k < 0.3 else (pal["core"] if k < 0.6 else pal["side"])
                cv.cell(x, y, col)
                if k < 0.5:
                    cv.glow(x, y, pal["glow"], 0.45)


class World:
    """一群怪：缓慢向小队逼近；kill(t, …) 登记死亡时刻（命中白闪 2 拍 → 死亡帧条）。"""

    def __init__(self, seed, A):
        rng = random.Random(seed)
        self.A = A
        self.es = []
        cl = [((430, 190), 85, 70, 46), ((540, 120), 30, 45, 30), ((520, 290), 25, 45, 28)]
        for (cx, cy), n, sx, sy in cl:
            for _ in range(n):
                self._add(rng, (rng.gauss(cx, sx), rng.gauss(cy, sy)))
        for _ in range(18):
            self._add(rng, (rng.uniform(300, 630), rng.uniform(40, 350)))
        self.es.sort(key=lambda e: e["p0"][1])

    def _add(self, rng, p):
        x, y = clamp(p[0], 250, 636), clamp(p[1], 36, 352)
        d = math.dist((x, y), SQUAD) or 1
        v = ((SQUAD[0] - x) / d * 9, (SQUAD[1] - y) / d * 9)
        kind = "off" if rng.random() < 0.7 else "sli"
        self.es.append({"p0": (x, y), "v": v, "kind": kind, "ph": rng.randrange(8), "kt": None, "lit": None, "flip": rng.random() < 0.5})

    def pos(self, e, t):
        tt = min(t, e["kt"]) if e["kt"] is not None else t
        return (e["p0"][0] + e["v"][0] * tt, e["p0"][1] + e["v"][1] * tt)

    def alive(self, e, t):
        return e["kt"] is None or e["kt"] > t

    def kill_seg(self, t0, dur, a, c, width, jitter=0.0, rng=None):
        out = []
        for e in self.es:
            if not self.alive(e, t0):
                continue
            d, u = seg_dist(self.pos(e, t0 + dur * 0.5), a, c)
            if d < width / 2:
                e["kt"] = t0 + dur * u + (rng.uniform(0, jitter) if rng else 0)
                out.append(e)
        return out

    def kill_circle(self, t0, c, r, squash=0.62, jitter=0.0, rng=None, cond=None):
        out = []
        for e in self.es:
            if not self.alive(e, t0) or (cond and not cond(e)):
                continue
            p = self.pos(e, t0)
            if math.hypot((p[0] - c[0]) / r, (p[1] - c[1]) / (r * squash)) < 1:
                e["kt"] = t0 + (rng.uniform(0, jitter) if rng else 0)
                out.append(e)
        return out

    def draw(self, img, t, lit_fn=None):
        A = self.A
        d = ImageDraw.Draw(img)
        for e in self.es:
            p = self.pos(e, t)
            k = "off" if e["kind"] == "off" else "sli"
            if e["kt"] is not None and t >= e["kt"]:
                f = int((t - e["kt"]) * 15)
                dl = A[k + "_die"]
                if f >= len(dl):
                    continue
                spr = dl[f]
                if f < 2:
                    spr = tint(spr, (1, 1, 1), (255, 255, 255))
            else:
                spr = A[k][(int(t * 8) + e["ph"]) % len(A[k])]
                d.ellipse([p[0] - 8, p[1] - 2, p[0] + 8, p[1] + 3], fill=(18, 22, 25))
                if lit_fn and lit_fn(e, t):
                    spr = tint(spr, (0.95, 1.1, 1.2), (0, 18, 30))
            if e["flip"]:
                spr = spr.transpose(Image.FLIP_LEFT_RIGHT)
            if not (e["kt"] is not None and t >= e["kt"] and int((t - e["kt"]) * 15) < 2):
                spr = tint(spr, (0.78, 0.8, 0.84))
            img.alpha_composite(spr, (int(p[0] - spr.width // 2), int(p[1] - spr.height + 6)))


def put_op(img, spr, foot, flip=False, al=1.0, mul=(1, 1, 1)):
    s = spr.transpose(Image.FLIP_LEFT_RIGHT) if flip else spr
    if al < 1 or mul != (1, 1, 1):
        s = tint(s, mul, (0, 0, 0), al)
    img.alpha_composite(s, (int(foot[0] - s.width // 2), int(foot[1] - s.height // 2 - 15)))


def background():
    rng = np.random.default_rng(3)
    a = np.zeros((H, W, 4), dtype=np.uint8)
    a[..., 0], a[..., 1], a[..., 2], a[..., 3] = 30, 40, 46, 255
    n = rng.integers(0, 6, (H // 2, W // 2))
    a[..., :3] = a[..., :3] + np.repeat(np.repeat(n, 2, 0), 2, 1)[..., None].astype(np.uint8)
    for _ in range(40):   # 稀疏暗斑
        x, y = rng.integers(0, W - 8), rng.integers(0, H - 4)
        a[y:y + 4, x:x + 8, :3] = (a[y:y + 4, x:x + 8, :3] * 0.85).astype(np.uint8)
    return Image.fromarray(a)


# ---------------------------------------------------------------- 演出卡
def unlock_card(img, t, A, pair, palA, palB, tag, name, line):
    if not (CARD[0] <= t < CARD[1] + 0.25):
        return img
    a_in = clamp((t - CARD[0]) / 0.18)
    a_out = clamp((t - CARD[1]) / 0.25)
    k = a_in * (1 - a_out)
    px = np.asarray(img.convert("RGB")).astype(float)
    px *= 1 - 0.45 * k
    y0, y1 = 118, 236
    xs = np.arange(W)
    # 两色带：左 A 色、右 B 色，在中线交汇（只有一条带，不铺满屏）
    sl = clamp((t - CARD[0]) / 0.22)
    for y in range(y0, y1):
        edge = min(y - y0, y1 - 1 - y)
        if edge < 0:
            continue
        ea = 0.55 if edge > 2 else 0.95
        left = np.clip((W * 0.5 * sl - xs) / (W * 0.5), 0, 1) ** 0.7
        right = np.clip((xs - W * (1 - 0.5 * sl)) / (W * 0.5), 0, 1) ** 0.7
        colA = np.array(palA["deep"], dtype=float)
        colB = np.array(palB["deep"], dtype=float)
        if edge <= 1:
            colA, colB = np.array(palA["side"], float), np.array(palB["side"], float)
        px[y, :, :] = px[y, :, :] * (1 - ea * k * left[:, None]) + colA * ea * k * left[:, None]
        px[y, :, :] = px[y, :, :] * (1 - ea * k * right[:, None]) + colB * ea * k * right[:, None]
    out = Image.fromarray(px.clip(0, 255).astype(np.uint8)).convert("RGBA")
    # 两人半身（idle 首帧 ×2）从两侧滑入
    ease = 1 - (1 - sl) ** 3
    for i, (op, x_from, x_to, flip) in enumerate(((pair[0], -60, 120, False), (pair[1], W + 60, W - 120, True))):
        s = A[op + "_idle"][0].resize((A[op + "_idle"][0].width * 2, A[op + "_idle"][0].height * 2), Image.NEAREST)
        if flip:
            s = s.transpose(Image.FLIP_LEFT_RIGHT)
        s = tint(s, (1, 1, 1), (0, 0, 0), k)
        x = x_from + (x_to - x_from) * ease
        out.alpha_composite(s, (int(x - s.width // 2), int((y0 + y1) // 2 - s.height // 2 - 4)))
    d = ImageDraw.Draw(out)
    f1 = ImageFont.truetype(FONT, 11)
    f2 = ImageFont.truetype(FONTB, 26)
    f3 = ImageFont.truetype(FONT, 12)
    kt = clamp((t - CARD[0] - 0.12) / 0.15) * (1 - a_out)
    if kt > 0:
        a8 = int(255 * kt)
        cx = W // 2
        d.text((cx, y0 + 18), "羁绊技解锁 · " + tag, fill=(235, 235, 235, a8), font=f1, anchor="mm")
        d.text((cx, (y0 + y1) // 2 + 2), name, fill=(255, 255, 255, a8), font=f2, anchor="mm", stroke_width=2, stroke_fill=(20, 18, 24, a8))
        d.text((cx, y1 - 20), line, fill=(220, 220, 220, a8), font=f3, anchor="mm")
    return out


# ---------------------------------------------------------------- 三招
def scene_rival(A, rng):
    """宿敌「十字旧怨」：两人从两侧斜穿怪群，两道巨刃在最密处交成一个大 X，交点炸开。"""
    w = World(11, A)
    C = (430, 192)
    L = 250
    d1 = (math.cos(math.radians(28)), math.sin(math.radians(28)))
    d2 = (math.cos(math.radians(-28)), math.sin(math.radians(-28)))
    a1, c1 = (C[0] - d1[0] * L, C[1] - d1[1] * L * 0.75), (C[0] + d1[0] * L, C[1] + d1[1] * L * 0.75)
    a2, c2 = (C[0] - d2[0] * L, C[1] - d2[1] * L * 0.75), (C[0] + d2[0] * L, C[1] + d2[1] * L * 0.75)
    t1, t2, tx = T0 + 0.25, T0 + 0.47, T0 + 0.78
    sp = Sparks()
    w.kill_seg(t1, 0.16, a1, c1, 44, 0.04, rng)
    w.kill_seg(t2, 0.16, a2, c2, 44, 0.04, rng)
    w.kill_circle(tx, C, 100, jitter=0.1, rng=rng)
    for e in w.es:
        if e["kt"] is not None and e["kt"] < tx + 0.2:
            pal = TX if e["kt"] < t2 else (LP if e["kt"] < tx else (TX if rng.random() < 0.5 else LP))
            sp.burst(e["kt"], w.pos(e, e["kt"]), 2, pal, rng, (20, 70), (0.15, 0.3))
    sp.burst(tx, C, 26, TX, rng, (60, 170), (0.25, 0.5), 40)
    sp.burst(tx, C, 26, LP, rng, (60, 170), (0.25, 0.5), 40)

    def draw(img, t):
        w.draw(img, t)
        tex_pos, lap_pos = (SQUAD[0], SQUAD[1]), (SQUAD[0] - 34, SQUAD[1] - 26)
        # 本体：出手时瞬身到线的起点，结束回位
        if t1 - 0.06 <= t < t1 + 0.22:
            u = clamp((t - t1) / 0.16)
            put_op(img, A["texas_atk"][4], (a1[0] + (c1[0] - a1[0]) * u, a1[1] + (c1[1] - a1[1]) * u))
        elif not (t1 + 0.22 <= t < tx + 0.3):
            put_op(img, A["texas_run"][int(t * 12) % 8], tex_pos)
        if t2 - 0.06 <= t < t2 + 0.22:
            u = clamp((t - t2) / 0.16)
            put_op(img, A["lappland_atk"][4], (a2[0] + (c2[0] - a2[0]) * u, a2[1] + (c2[1] - a2[1]) * u))
        elif not (t2 + 0.22 <= t < tx + 0.3):
            put_op(img, A["lappland_run"][int(t * 12) % 8], lap_pos)
        # 回位淡入
        if tx + 0.3 <= t < tx + 0.5:
            k = (t - tx - 0.3) / 0.2
            put_op(img, A["texas_run"][0], tex_pos, al=k)
            put_op(img, A["lappland_run"][0], lap_pos, al=k)
        cv = Canvas(img)
        # 残影
        for (a, c, tt, op, pal) in ((a1, c1, t1, "texas", (1.0, 0.8, 0.55)), (a2, c2, t2, "lappland", (0.8, 0.78, 1.0))):
            age = t - tt
            if 0 <= age < 0.32:
                pass
        if CARD[1] - 0.1 < t < T0 + 0.25:
            # 起手预兆：交点一个小菱形亮点（0.25 秒）
            k = clamp((t - (CARD[1] - 0.1)) / 0.2)
            for i in range(-3, 4):
                cv.cell(C[0] + i, C[1], (255, 255, 255), 0.6 * k)
                cv.cell(C[0], C[1] + i, (255, 255, 255), 0.6 * k)
            cv.glow(C[0], C[1], (1, 1, 1), 1.2 * k)
        slash(cv, a1, c1, t, t1, 0.16, 0.75, 0.35, TX, 3)
        slash(cv, a2, c2, t, t2, 0.16, 0.53, 0.35, LP, 3)
        if 0 <= t - tx < 0.12:
            cv.lamp(C[0], C[1], 110, (255, 200, 150), 70 * (1 - (t - tx) / 0.12))
        if 0 <= t - tx < 0.22:   # 交点：两道短亮十字（各取一人色）
            k = 1 - (t - tx) / 0.22
            for i in range(-22, 23):
                cv.cell(C[0] + i, C[1] + i * 0.55, (255, 255, 255) if abs(i) < 8 else TX["side"], k)
                cv.cell(C[0] + i, C[1] - i * 0.55, (255, 255, 255) if abs(i) < 8 else LP["side"], k)
                if i % 2 == 0:
                    cv.glow(C[0] + i, C[1], (1.0, 0.9, 0.85), 0.8 * k)
        if 0 <= t - tx < 0.3:
            ring(cv, C, 30 + (t - tx) * 300, TX if int(t * 30) % 2 else LP, t, 1 - (t - tx) / 0.3, dash=False)
        sp.draw(cv, t)
        return cv.finish()
    return draw, w


def scene_penguin(A, rng):
    """企鹅物流「急件航线」：能天使朝最密方向打出一条航线（两侧细线 + 一路曳光扫射），德克萨斯的剑沿航线依次落下炸开。"""
    w = World(23, A)
    S = (SQUAD[0] + 30, SQUAD[1] - 10)
    ang = math.radians(-7)
    dv = (math.cos(ang), math.sin(ang))
    nv = (-dv[1], dv[0])
    L0, L1, HW = 60, 470, 54
    P = lambda s, o=0.0: (S[0] + dv[0] * s + nv[0] * o, S[1] + dv[1] * s + nv[1] * o)
    sp = Sparks()
    shots = []
    tb = T0 + 0.25
    for i in range(64):
        s = L0 + (L1 - L0) * (i / 63) ** 0.9 + rng.uniform(-10, 10)
        o = rng.uniform(-HW + 6, HW - 6)
        shots.append((tb + i * 0.016, P(s, o)))
    swords = []
    for i in range(6):
        s = L0 + 40 + i * (L1 - L0 - 60) / 5
        swords.append((T0 + 0.75 + i * 0.09, P(s, rng.uniform(-10, 10)), i == 5))
    for ts, p in shots:
        sp.burst(ts + 0.07, p, 2, EX, rng, (20, 60), (0.12, 0.25), 20)
        w.kill_circle(ts + 0.07, p, 13, 0.7, 0.03, rng)
    for ts, p, big in swords:
        sp.burst(ts + 0.12, p, 14 if big else 8, TX, rng, (40, 140), (0.2, 0.42), 35)
        w.kill_circle(ts + 0.12, p, 52 if big else 40, 0.62, 0.05, rng)
    for e in w.es:   # 航线内余下的统一结算（伤害按带状判定，画面只是没被弹点到的也倒下）
        if w.alive(e, T0 + 1.5):
            p = w.pos(e, T0 + 1.5)
            q = (p[0] - S[0], p[1] - S[1])
            s, o = q[0] * dv[0] + q[1] * dv[1], q[0] * nv[0] + q[1] * nv[1]
            if L0 < s < L1 and abs(o) < HW:
                e["kt"] = T0 + 0.75 + (s - L0) / (L1 - L0) * 0.5 + rng.uniform(0.05, 0.12)

    def draw(img, t):
        w.draw(img, t)
        firing = T0 <= t < T0 + 1.3
        put_op(img, (A["exusiai_atk"] if firing else A["exusiai_run"])[int(t * 12) % 8], (SQUAD[0] - 30, SQUAD[1] - 28))
        put_op(img, A["texas_run"][int(t * 12) % 8], SQUAD)
        cv = Canvas(img)
        # 航线两侧细线：从小队往外画出去（0.25 秒），保持到剑落完
        tl = T0
        if tl <= t < T0 + 2.0:
            grow = clamp((t - tl) / 0.25)
            fade = 1 - clamp((t - (T0 + 1.6)) / 0.4)
            for side in (-1, 1):
                n = int((L1 - L0) * grow)
                for i in range(0, n, 1):
                    if (i // 6) % 2 == 1:
                        continue
                    p = P(L0 + i, side * HW)
                    cv.cell(p[0], p[1], EX["side"], 0.95 * fade)
                    cv.cell(p[0], p[1] + 1, EX["deep"], 0.7 * fade)
                    if i % 6 == 0:
                        cv.glow(p[0], p[1], EX["glow"], 0.3 * fade)
            # 终点箭头（像素「>」）
            if grow >= 1:
                for j in range(-8, 9):
                    p = P(L1 + 8 - abs(j), j * 1.2)
                    cv.cell(p[0], p[1], EX["core"], fade)
        # 曳光：从枪口斜上方飞入落点
        for ts, p in shots:
            age = t - ts
            if 0 <= age < 0.07:
                u = age / 0.07
                src = (SQUAD[0] - 30 + (p[0] - SQUAD[0]) * 0.3, SQUAD[1] - 140)
                hx, hy = src[0] + (p[0] - src[0]) * u, src[1] + (p[1] - src[1]) * u
                ddx, ddy = p[0] - src[0], p[1] - src[1]
                dd = math.hypot(ddx, ddy)
                for k in range(16):
                    cv.cell(hx - ddx / dd * k, hy - ddy / dd * k, EX["core"] if k < 4 else EX["side"], 1 - k / 18)
                    cv.cell(hx - ddx / dd * k + 1, hy - ddy / dd * k, EX["side"], 0.6 - k / 30)
                cv.glow(hx, hy, EX["glow"], 1.0)
            elif 0.07 <= age < 0.14:
                for i in range(-1, 2):
                    cv.cell(p[0] + i, p[1], (255, 255, 255))
                    cv.cell(p[0], p[1] + i, (255, 255, 255))
                cv.glow(p[0], p[1], EX["glow"], 1.4)
        # 剑：从高处直落（竖直亮线），落地两拍过曝 + 照地光 + 短十字
        for ts, p, big in swords:
            age = t - ts
            h = 120
            if 0 <= age < 0.12:
                u = age / 0.12
                y = p[1] - h * (1 - u)
                for k in range(44 if big else 34):
                    cv.cell(p[0], y - k, TX["core"] if k < 10 else TX["side"], 1 - k / 46)
                    cv.cell(p[0] - 1, y - k, TX["side"], 0.8 - k / 50)
                    cv.cell(p[0] + 1, y - k, TX["side"] if k < 20 else TX["deep"], 0.8 - k / 50)
                cv.glow(p[0], y, TX["glow"], 1.0)
            elif 0.12 <= age < 0.5:
                a2 = age - 0.12
                if a2 < 0.08:
                    cv.lamp(p[0], p[1], 70 if big else 50, (255, 170, 80), 60 * (1 - a2 / 0.08))
                L = 44 if big else 32
                slash(cv, (p[0] - L, p[1] - L * 0.5), (p[0] + L, p[1] + L * 0.5), t, ts + 0.12, 0.04, 0.14, 0.18, TX, 3 if big else 2, 0.8)
                slash(cv, (p[0] - L, p[1] + L * 0.5), (p[0] + L, p[1] - L * 0.5), t, ts + 0.12, 0.04, 0.14, 0.18, TX, 3 if big else 2, 0.8)
                # 剑身插在地上 0.38 秒
                for k in range(24):
                    cv.cell(p[0], p[1] - k, TX["core"] if k > 18 else TX["side"], max(0, 1 - a2 / 0.38))
                    cv.cell(p[0] + 1, p[1] - k, TX["deep"], max(0, 0.8 - a2 / 0.38))
        sp.draw(cv, t)
        return cv.finish()
    return draw, w


def scene_inq(A, rng):
    """灯下审决「提灯宣判」：流明提灯照出一大圈光，圈里的怪全部被照亮；艾丽妮三道刺穿圈内，最后光里剩下的一齐受审倒下。"""
    w = World(37, A)
    C = (420, 196)
    R = 132
    SQ = 0.62
    tr, t_th, t_v = T0 + 0.05, [T0 + 0.55, T0 + 0.72, T0 + 0.89], T0 + 1.25
    sp = Sparks()
    lit_at = T0 + 0.35
    in_ring = lambda e: math.hypot((w.pos(e, lit_at)[0] - C[0]) / R, (w.pos(e, lit_at)[1] - C[1]) / (R * SQ)) < 1
    for e in w.es:
        if in_ring(e):
            e["lit"] = lit_at
    angs = [math.radians(a) for a in (-12, 48, 108)]
    lines = []
    for i, a in enumerate(angs):
        d = (math.cos(a), math.sin(a) * SQ)
        p0 = (C[0] - d[0] * (R + 30), C[1] - d[1] * (R + 30))
        p1 = (C[0] + d[0] * (R + 30), C[1] + d[1] * (R + 30))
        if i % 2:
            p0, p1 = p1, p0
        lines.append((p0, p1))
        for e in w.kill_seg(t_th[i], 0.1, p0, p1, 26, 0.03, rng):
            sp.burst(e["kt"], w.pos(e, e["kt"]), 2, IR, rng, (20, 60), (0.15, 0.3))
    judged = w.kill_circle(t_v, C, R, SQ, 0.12, rng, cond=lambda e: e["lit"] is not None)
    for e in judged:
        sp.burst(e["kt"] + 0.08, w.pos(e, e["kt"]), 3, LU if rng.random() < 0.5 else IR, rng, (20, 70), (0.15, 0.32), 25)

    def lit_fn(e, t):
        return e["lit"] is not None and t >= e["lit"] and t < t_v + 0.6

    def draw(img, t):
        lum = (SQUAD[0] - 34, SQUAD[1] - 26)
        cv0 = Canvas(img)
        on = T0 <= t < t_v + 0.9
        if on:
            grow = clamp((t - tr) / 0.3)
            fade = 1 - clamp((t - (t_v + 0.4)) / 0.5)
            # 圈内照地光（低亮度，加色；后期按 docs/293 L3 降）
            cv0.lamp(C[0], C[1], max(1, R * grow), (90, 190, 255), 26 * fade, SQ)
        img = cv0.finish().convert("RGBA")
        w.draw(img, t, lit_fn)
        put_op(img, (A["lumen_atk"] if on else A["lumen_run"])[int(t * 10) % 8], lum)
        thr = any(0 <= t - tt < 0.16 for tt in t_th)
        if not (t_th[0] - 0.02 <= t < t_v + 0.25):
            put_op(img, A["irene_run"][int(t * 12) % 8], SQUAD)
        cv = Canvas(img)
        if on:
            grow = clamp((t - tr) / 0.3)
            fade = 1 - clamp((t - (t_v + 0.4)) / 0.5)
            # 灯：流明头顶一点 + 一道细光引到圈心（只在张开时）
            lp = (lum[0] + 6, lum[1] - 34)
            for i in range(-1, 2):
                cv.cell(lp[0] + i, lp[1], LU["core"], fade)
                cv.cell(lp[0], lp[1] + i, LU["core"], fade)
            cv.glow(lp[0], lp[1], LU["glow"], 1.6 * fade)
            if t < tr + 0.35:
                n = 60
                for i in range(n):
                    u = i / n
                    if u > grow:
                        break
                    cv.cell(lp[0] + (C[0] - lp[0]) * u, lp[1] + (C[1] - lp[1]) * u, LU["side"], 0.5)
            ring(cv, C, R * (1 - (1 - grow) ** 3), LU, t, fade, dash=True, squash=SQ, w=3)
            ring(cv, C, R * (1 - (1 - grow) ** 3) * 0.9, LU, -t, 0.35 * fade, dash=True, squash=SQ)
        # 三道刺：本体沿线一闪而过
        for i, (p0, p1) in enumerate(lines):
            slash(cv, p0, p1, t, t_th[i], 0.1, 0.32, 0.25, IR, 2)
            if 0 <= t - t_th[i] < 0.14:
                u = clamp((t - t_th[i]) / 0.1)
                im = cv.finish().convert("RGBA")
                put_op(im, A["irene_atk"][5], (p0[0] + (p1[0] - p0[0]) * u, p0[1] + (p1[1] - p0[1]) * u), p1[0] < p0[0])
                cv = Canvas(im)
        # 宣判：光里剩下的每只头顶落一道短银光
        for e in judged:
            age = t - e["kt"]
            if 0 <= age < 0.16:
                p = w.pos(e, e["kt"])
                u = clamp(age / 0.06)
                for k in range(int(22 * u)):
                    cv.cell(p[0], p[1] - 40 + k, IR["core"] if k > 14 else IR["side"], 1 - age / 0.16)
                cv.glow(p[0], p[1] - 14, IR["glow"], 1.0 * (1 - age / 0.16))
        if 0 <= t - t_v < 0.1:
            cv.lamp(C[0], C[1], R, (200, 230, 255), 45 * (1 - (t - t_v) / 0.1), SQ)
        if t_v + 0.2 <= t < t_v + 0.45:
            put_op_k = (t - t_v - 0.2) / 0.25
            im = cv.finish().convert("RGBA")
            put_op(im, A["irene_run"][0], SQUAD, al=put_op_k)
            cv = Canvas(im)
        sp.draw(cv, t)
        return cv.finish()
    return draw, w


SCENES = {
    "rival": (scene_rival, ("texas", "lappland"), TX, LP, "宿敌", "十字旧怨", "德克萨斯 × 拉普兰德 · 两道剑刃交成十字，交点炸开"),
    "penguin": (scene_penguin, ("exusiai", "texas"), EX, TX, "企鹅物流", "急件航线", "能天使 × 德克萨斯 · 一路扫射清出航线，剑沿线落下"),
    "inq": (scene_inq, ("lumen", "irene"), LU, IR, "灯下审决", "提灯宣判", "流明 × 艾丽妮 · 灯光照出的一圈，刺穿后一齐受审"),
}


def load_assets():
    od = os.path.join(ROOT, "game", "art", "operators")
    ed = os.path.join(ROOT, "game", "art", "enemies")
    A = {}
    for o in ("texas", "lappland", "exusiai", "irene", "lumen"):
        A[o + "_run"] = frames_of(os.path.join(od, o, "op_%s_run@1x.png" % o), 8)
        A[o + "_idle"] = frames_of(os.path.join(od, o, "op_%s_idle@1x.png" % o), n=7 if o == "texas" else 8)
        A[o + "_atk"] = frames_of(os.path.join(od, o, "op_%s_attack@1x.png" % o), 8)
    A["off"] = frames_of(os.path.join(ed, "offspring", "e_offspring@2x.png"), fw=80, scale=0.5)
    A["off_die"] = frames_of(os.path.join(ed, "offspring", "e_offspring_death@2x.png"), fw=80, scale=0.5)
    A["sli"] = frames_of(os.path.join(ed, "slider", "e_slider@2x.png"), fw=68, scale=0.5)
    A["sli_die"] = frames_of(os.path.join(ed, "slider", "e_slider_death@2x.png"), fw=68, scale=0.5)
    return A


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join(MAIN, "Claude outputs", "bond_v2_1106"))
    ap.add_argument("--only", default="rival,penguin,inq")
    ap.add_argument("--still", default="", help="只出单帧 PNG（秒，逗号分隔），调试用")
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    A = load_assets()
    bg = background()
    fh = ImageFont.truetype(FONT, 12)
    for key in a.only.split(","):
        fn, pair, pa, pb, tag, name, line = SCENES[key]
        draw, world = fn(A, random.Random(7))
        frames = []
        ts = [float(s) for s in a.still.split(",")] if a.still else [i / FPS for i in range(int(T_END * FPS))]
        for t in ts:
            img = draw(bg.copy().convert("RGBA"), t).convert("RGBA")
            img = unlock_card(img, t, A, pair, pa, pb, tag, name, line)
            sh = Image.new("RGB", (W, H + HDR), (12, 12, 16))
            sh.paste(img.convert("RGB"), (0, HDR))
            d = ImageDraw.Draw(sh)
            d.text((6, 4), "羁绊技示意 · %s「%s」 · %.2f 秒 · 原速 30 fps · Python 绘制，非实机" % (tag, name, t), fill=(200, 200, 200), font=fh)
            frames.append(sh)
        if a.still:
            for t, f in zip(ts, frames):
                p = os.path.join(a.out, "bond_%s_%.2f.png" % (key, t))
                f.save(p)
                print(p)
            continue
        for sc in (1, 2):
            fr = frames if sc == 1 else [f.resize((f.width * 2, f.height * 2), Image.NEAREST) for f in frames]
            probe = Image.new("RGB", (fr[0].width, fr[0].height * 4))
            for i, tt in enumerate((0.9, T0 + 0.3, T0 + 0.8, T0 + 1.3)):
                probe.paste(fr[min(len(fr) - 1, int(tt * FPS))], (0, fr[0].height * i))
            pal = probe.quantize(colors=250, method=Image.MEDIANCUT)
            q = [f.quantize(palette=pal, dither=Image.NONE) for f in fr]
            path = os.path.join(a.out, "bond_%s_%dx.gif" % (key, sc))
            q[0].save(path, save_all=True, append_images=q[1:], duration=int(1000 / FPS), loop=0, disposal=1)
            print(path, len(q), "帧", "%.0f KB" % (os.path.getsize(path) / 1024))


if __name__ == "__main__":
    main()
