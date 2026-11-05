#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""艾雅法拉终结技「海底火山」转平面版的本机样稿（docs/259 §7）：只用 Python + 本机 pixelfx 库出帧条，按原终结技的时序合成 GIF，不开 Godot。

时序照 ult_moves_b._ey_start / _ey_step（不动）：0–0.4 秒蓄压（裂网爬开）→ 0.4 秒喷发（顿帧 + 冲击帧整屏白 + 黑剪影，保留）
→ 0.55–1.0 秒 38 发火山弹从斜上方砸下、落地小爆团 + 浮石 → 熔岩池（半径 300 世界像素）0.9 秒漫开、到 3.2 秒判定结束再留 1.6 秒结壳淡掉。
画面：1 美术像素 = 2 屏幕像素，15 fps 节拍；贴地层压扁 0.72；最亮的芯做一层辉光（模拟游戏里的发光层），其余靠本色。
用法：python tools/ult_eyja_mock.py --out <目录> [--orig <原版 mp4>]
"""
import argparse, json, math, os, subprocess, sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import pxplane_bake_eyja as BK   # noqa: E402

W, H, PX = 640, 360, 2
FPS = 15
ART = os.path.join(ROOT, "game", "art")
FONT = "C:/Windows/Fonts/msyh.ttc"


def h(x):
    return (math.sin(x * 12.9898 + 78.233) * 43758.5453) % 1.0


def strips(tmp):
    """本样稿要用的帧条：终结技件按大尺寸现烤，其余用游戏里已烤好的 pxp_ey_*"""
    BK.TMP = tmp
    need = [("ucrack", {"part": "ucrack", "layer": "gd", "el": 2, "R": 221, "seed": 11}, 1.5, False),
            ("ufount", {"part": "ufount", "layer": "up", "el": 2, "R": 165, "seed": 12}, 1.2, False),
            ("pumice", {"part": "pumice", "layer": "gd", "el": 2, "R": 4, "seed": 13, "dur": 2.6}, 2.6, False),
            ("pool", {"part": "upool", "layer": "gd", "el": 2, "R": 150, "k": 0, "seed": 9, "dur": 1.2}, 1.2, True),
            ("poolc", {"part": "upool", "layer": "gd", "el": 2, "R": 150, "k": 0.8, "seed": 9, "dur": 1.2}, 1.2, True),
            ("poolup", {"part": "lavaup", "layer": "up", "el": 2, "R": 150, "k": 1, "seed": 9, "dur": 1.2}, 1.2, True)]
    out = {}
    for key, o, dur, loop in need:
        k, d, du, lp = BK.render(key, o, dur, loop)
        meta = json.load(open(os.path.join(d, "meta.json")))
        fw, fh = meta["frameSize"]
        col = Image.open(os.path.join(d, "color.png")).convert("RGBA")
        n = min(meta["frames"], int(round(du * FPS)))
        out[key] = {"fr": [col.crop((i * fw, 0, (i + 1) * fw, fh)) for i in range(n)], "o": tuple(meta["pivot"]), "loop": lp}
    gm = json.load(open(os.path.join(ROOT, "game", "data", "pxp_eyjafjalla.json"), encoding="utf-8"))
    for key in ["splash_r22_up", "splash_r22_gd", "s3boom_r38_up", "s3boom_r38_gd"] + ["ball_rock_d%d" % d for d in (-90, -45, 0, 45, 90)]:
        m = gm[key]
        im = Image.open(os.path.join(ART, "fx", "pxp", "pxp_ey_%s.png" % key.replace("_d-", "_dm"))).convert("RGBA")
        out[key] = {"fr": [im.crop((i * m["w"], 0, (i + 1) * m["w"], m["h"])) for i in range(m["n"])], "o": (m["ox"], m["oy"]), "loop": m["loop"]}
    return out


def pick_dir(ang):
    a = math.degrees(math.atan2(math.sin(ang), math.cos(ang)))
    flip = False
    if abs(a) > 90:
        a = 180 - a if a > 0 else -180 - a
        flip = True
    best = min((-90, -45, 0, 45, 90), key=lambda d: abs(a - d))
    return best, flip


def put(canvas, S, key, fi, x, y, flip=False, alpha=1.0, sil=None):
    s = S[key]
    n = len(s["fr"])
    if s["loop"]:
        fi %= n
    elif fi < 0 or fi >= n:
        return
    im = s["fr"][fi]
    ox, oy = s["o"]
    if flip:
        im = im.transpose(Image.FLIP_LEFT_RIGHT)
        ox = im.width - 1 - ox
    if alpha < 1.0:
        a = np.asarray(im).copy()
        a[..., 3] = (a[..., 3] * alpha).astype(np.uint8)
        im = Image.fromarray(a)
    canvas.alpha_composite(im, (int(round(x - ox)), int(round(y - oy))))
    if sil is not None:
        sil.alpha_composite(im, (int(round(x - ox)), int(round(y - oy))))


def background():
    rng = np.random.default_rng(3)
    base = np.zeros((H, W, 3), np.float32)
    base[:] = (22, 34, 42)
    n = rng.random((H // 8 + 1, W // 8 + 1))
    n = np.kron(n, np.ones((8, 8)))[:H, :W]
    base += (n[..., None] - 0.5) * np.array([10, 12, 14])
    sp = rng.random((H, W)) > 0.996
    base[sp] = (60, 78, 88)
    return Image.fromarray(np.clip(base, 0, 255).astype(np.uint8)).convert("RGBA")


def sprites():
    ey = Image.open(os.path.join(ART, "operators", "eyjafjalla", "op_eyjafjalla_idle@1x.png")).convert("RGBA").crop((0, 0, 64, 64))
    en = []
    for p in ("floater/e_floater@2x.png", "duck/e_duck@2x.png"):
        im = Image.open(os.path.join(ART, "enemies", p)).convert("RGBA")
        fh = im.height
        fr = im.crop((0, 0, fh, fh))
        en.append(fr.resize((fh // 2, fh // 2), Image.NEAREST))
    return ey, en


def bloom(img):
    a = np.asarray(img.convert("RGB")).astype(np.float32)
    luma = a[..., 0] * 0.2126 + a[..., 1] * 0.7152 + a[..., 2] * 0.0722
    m = np.where(luma[..., None] > 200, a, 0)
    g = Image.fromarray(m.astype(np.uint8)).filter(ImageFilter.GaussianBlur(5))
    out = np.clip(a + np.asarray(g).astype(np.float32) * 0.55, 0, 255)
    return Image.fromarray(out.astype(np.uint8))


EYC = [(26, 7, 5), (74, 17, 10), (143, 29, 13), (210, 51, 15), (246, 86, 26), (255, 138, 61), (255, 240, 224), (255, 170, 69)]   # 熔岩 7 阶 + 橙黄热芯


# ---------------------------------------------------------------- 时间：实时帧 → 招式游戏时间（冲击帧停 2 拍 → 慢放 0.3 倍 0.5 游戏秒 → 0.15 秒加速回 1 倍）
T_IMP = 0.40          # 喷发（最大那一下）的游戏时刻
HF_REAL = 2 / FPS     # 冲击帧两拍（顿住）
SLOW_K, SLOW_G, RAMP = 0.3, 0.5, 0.15


def game_t(r):
    r = round(r * FPS * 1000) / (FPS * 1000)   # 帧时刻取整，免得浮点把冲击帧拉成 3 拍
    if r < T_IMP - 1e-6:
        return r, "pre"
    r -= T_IMP
    if r < HF_REAL - 1e-6:
        return T_IMP, "hf"
    r -= HF_REAL
    sr = SLOW_G / SLOW_K
    if r < sr:
        return T_IMP + r * SLOW_K, "slow"
    r -= sr
    if r < RAMP:   # 0.3 → 1 线性加速
        return T_IMP + SLOW_G + SLOW_K * r + (1 - SLOW_K) * r * r / (2 * RAMP), "ramp"
    r -= RAMP
    return T_IMP + SLOW_G + RAMP * (1 + SLOW_K) / 2 + r, "post"


def real_of(g):
    """游戏时间 → 实时（音效清单用）"""
    lo, hi = 0.0, 10.0
    for _ in range(40):
        m = (lo + hi) / 2
        if game_t(m)[0] < g:
            lo = m
        else:
            hi = m
    return hi


def px(img, x, y, c, a=255):
    x, y = int(round(x)), int(round(y))
    if 0 <= x < W and 0 <= y < H:
        img.putpixel((x, y), (c[0], c[1], c[2], a))


def ring(img, cx, cy, r, th, cols, sy=0.72, segs=None):
    """压扁的厚冲击环：外亮内暗（颜色阶代替透明度），th 像素厚"""
    n = int(2 * math.pi * r * 1.2) + 8
    for i in range(n):
        an = i / n * math.tau
        if segs is not None and not segs(an):
            continue
        for q in range(int(th)):
            rr = r - q
            c = cols[min(len(cols) - 1, q * len(cols) // max(1, int(th)))]
            px(img, cx + math.cos(an) * rr, cy + math.sin(an) * rr * sy, c)


class Spark:
    """粒子云 / 崩解像素：位置（含高度 z）、速度、寿命、颜色序列、闪烁"""
    __slots__ = ("x", "y", "z", "vx", "vy", "vz", "t0", "life", "cols", "sz", "g", "fl", "seed")

    def __init__(s, x, y, z, vx, vy, vz, t0, life, cols, sz=1, g=0.0, fl=True, seed=0.0):
        s.x, s.y, s.z, s.vx, s.vy, s.vz, s.t0, s.life, s.cols, s.sz, s.g, s.fl, s.seed = x, y, z, vx, vy, vz, t0, life, cols, sz, g, fl, seed

    def draw(s, img, t):
        a = t - s.t0
        if a < 0 or a > s.life:
            return
        k = a / s.life
        drag = (1 - math.exp(-3.0 * a)) / 3.0   # 往外喷、越飞越慢
        x = s.x + s.vx * drag
        y = s.y + s.vy * drag
        z = max(0.0, s.z + s.vz * drag - 0.5 * s.g * a * a)
        if s.fl and h(s.seed + int(t * FPS) * 0.37) < 0.25 + 0.5 * k:   # 逐拍闪烁、越剩越少
            return
        c = s.cols[min(len(s.cols) - 1, int(k * len(s.cols)))]
        for dx in range(s.sz):
            for dy in range(s.sz):
                px(img, x + dx, y - z + dy, c)


def cloud(t0, cx, cy, n, rad, life, seed, cols=None, up=6.0):
    """闪烁粒子云（原版 ult_burst 的做法，换成她的熔岩配色）：按面积均匀铺开往外炸，之后逐拍闪烁、往上漂"""
    cols = cols or [EYC[6], EYC[7], EYC[5], EYC[4], EYC[3]]
    out = []
    for i in range(n):
        a = h(seed + i * 1.7) * math.tau
        r = math.sqrt(h(seed + i * 3.1)) * rad
        out.append(Spark(cx, cy, 2.0, math.cos(a) * r * 3.0, math.sin(a) * r * 3.0 * 0.72, up + 14 * h(seed + i * 5.3), t0 + 0.02 * h(seed + i), life * (0.7 + 0.5 * h(seed + i * 7.1)),
                         cols, 2 if h(seed + i * 9.9) < 0.33 else 1, 0.0, True, seed + i))
    return out


def disintegrate(t0, sprite, fx, fy, dirx, diry, seed, k=1.0):
    """崩解：怪物身体按自身贴图像素炸开（同引擎 kill_burst），再加一圈本色像素顺着冲击方向往外喷；有重量、落地"""
    out = []
    a = np.asarray(sprite)
    ys, xs = np.nonzero(a[..., 3] > 128)
    if len(xs) == 0:
        return out
    step = max(1, len(xs) // 60)
    w, hh = sprite.width, sprite.height
    for j in range(0, len(xs), step):
        c = tuple(int(v) for v in a[ys[j], xs[j], :3])
        sx, sy = fx - w / 2 + xs[j], fy - hh + 4 + ys[j]
        rnd = h(seed + j * 0.31)
        sp = (40 + 70 * rnd) * k
        vx = dirx * sp + (xs[j] - w / 2) * 2.2
        vy = diry * sp * 0.72 + (ys[j] - hh / 2) * 0.8
        out.append(Spark(sx, fy, (fy - sy), vx, vy, 30 + 40 * h(seed + j), t0 + 0.02 * rnd, 0.9 + 0.4 * rnd, [c], 1, 160.0, False, seed + j))
    # 本色像素：亮 / 本色 / 暗三阶 + 头两拍白芯
    mean = a[ys, xs, :3].mean(axis=0)
    base = tuple(int(v) for v in mean)
    lite = tuple(min(255, int(v * 1.5 + 30)) for v in mean)
    dark = tuple(int(v * 0.55) for v in mean)
    for j in range(int(22 * k)):
        an = math.atan2(diry, dirx) + (h(seed + j * 2.3) - 0.5) * 1.6
        sp = (60 + 90 * h(seed + j * 4.1)) * k
        out.append(Spark(fx, fy, 10 + 8 * h(seed + j), math.cos(an) * sp, math.sin(an) * sp * 0.72, 40 + 50 * h(seed + j * 6.7), t0, 0.8 + 0.4 * h(seed + j * 8.3),
                         [(255, 255, 255), lite, base, base, dark], 2 if j % 3 == 0 else 1, 200.0, False, seed + j))
    return out


def warm_light(img_rgb, cx, cy, r, k):
    """照地灯：一盏本人色点光（近似 optical 照地，加色），压扁成椭圆"""
    if k <= 0:
        return img_rgb
    a = np.asarray(img_rgb).astype(np.float32)
    yy, xx = np.mgrid[0:H, 0:W]
    d = np.sqrt(((xx - cx) / r) ** 2 + ((yy - cy) / (r * 0.72)) ** 2)
    f = np.clip(1 - d, 0, 1) ** 1.6 * k
    a += f[..., None] * np.array([120, 55, 18]) * (0.35 + a / 255 * 0.9)
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))


def render(S, out_dir):
    bg = background()
    ey, en = sprites()
    C = (400, 200)   # 落点（美术像素）
    R = 295.0        # 判定半径 590 世界像素
    ex = (170, 236)  # 艾雅法拉脚底
    rng = np.random.default_rng(5)
    foes = []
    for i in range(22):
        a = rng.random() * math.tau
        r = math.sqrt(rng.random()) * 185
        foes.append([C[0] + math.cos(a) * r, C[1] + math.sin(a) * r * 0.72, i % 2, None])   # 最后一项 = 崩解时刻
    bombs = []
    for i in range(38):
        rr = R * 0.97 * math.sqrt((i + 0.5) / 38)
        an = i * 2.39996 + 0.4
        p = (C[0] + math.cos(an) * rr, C[1] + math.sin(an) * rr)
        hb = h(p[0] * 0.017 + p[1] * 0.031)
        p0 = (p[0] - 70 - 60 * hb, p[1] - 210 - 80 * h(hb * 5))
        bombs.append((p, p0, 0.55 + 0.45 * i / 38 + 0.06 * h(hb * 37), hb))
    sparks = []
    # 冲击环 3.5 拍（游戏时间）推到判定边缘；怪物在冲击环到达时崩解
    RING_T = 3.5 / FPS
    r_shock = lambda g: R * (0.18 + 0.82 * (1 - (1 - min(1.0, (g - T_IMP) / RING_T)) ** 2))
    for fo in foes:
        d = math.hypot(fo[0] - C[0], (fo[1] - C[1]) / 0.72)
        if d <= R:
            k = 0.0
            while r_shock(T_IMP + k) < d and k < RING_T:
                k += 0.005
            fo[3] = T_IMP + k
            dx, dy = (fo[0] - C[0]), (fo[1] - C[1]) / 0.72
            L = math.hypot(dx, dy) or 1
            sparks += disintegrate(fo[3], en[fo[2]], fo[0], fo[1], dx / L, dy / L, 100 + d, 1.0)
    sparks += cloud(T_IMP + 2 / FPS, C[0], C[1] - 10, 160, R * 0.6 / 3.0, 1.2, 7.0)   # 往外喷的大粒子云
    for i, (p, p0, tl, hb) in enumerate(bombs):   # 火山弹落点：闪烁粒子云（不用烟团）
        sparks += cloud(tl, p[0], p[1] - 3, 26, 5.0, 0.8, 300 + i * 13)
    pull = [(C[0] + math.cos(h(i * 3.3) * math.tau) * R * (0.55 + 0.25 * h(i * 7.7)), C[1] + math.sin(h(i * 3.3) * math.tau) * R * (0.55 + 0.25 * h(i * 7.7)) * 0.72) for i in range(40)]
    frames, gtimes = [], []
    T = 6.4
    for fi in range(int(T * FPS)):
        r_t = fi / FPS
        t, ph = game_t(r_t)
        gtimes.append(t)
        gf = int(t * FPS)
        cv = bg.copy()
        sil = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        # —— 预备：喷发前 2 拍光点往中心吸、圈内压暗
        dk = 0.0
        if T_IMP - 2 / FPS <= t < T_IMP:
            dk = 0.28
        elif ph in ("hf",) or (T_IMP <= t < T_IMP + 2 / FPS):
            dk = 0.18
        if dk > 0:
            ov = Image.new("RGBA", (W, H), (0, 0, 0, 0))
            ImageDraw.Draw(ov).ellipse((C[0] - R * 0.8, C[1] - R * 0.8 * 0.72, C[0] + R * 0.8, C[1] + R * 0.8 * 0.72), fill=(0, 0, 0, int(255 * dk)))
            cv.alpha_composite(ov)
        put(cv, S, "ucrack", gf, *C, sil=sil if ph == "hf" else None)
        if t >= T_IMP:
            pa = min(1.0, (t - T_IMP) / 0.9)
            fade = 1.0 - max(0.0, (t - 3.2) / 1.6)
            if fade > 0:
                put(cv, S, "pool" if t < 3.2 else "poolc", gf, *C, alpha=pa * fade)
            # 冲击环（压扁、厚、亮）+ 推过的地面闪一下
            ka = (t - T_IMP) / RING_T
            if 0 <= ka <= 1.0 + 2 / FPS / RING_T:
                rr = r_shock(t)
                fadek = 1.0 if ka <= 1.0 else 0.5
                ring(cv, C[0], C[1], rr + 8, 4, [(150, 70, 30)] if fadek > 0.6 else [(90, 40, 20)])   # 环后一圈地面闪
                ring(cv, C[0], C[1], rr, 8 if fadek > 0.6 else 4, [EYC[6], EYC[7], EYC[5], EYC[5], EYC[4], EYC[3]] if fadek > 0.6 else [EYC[4], EYC[3]])
        for p, p0, tl, hb in bombs:
            if t >= tl:
                put(cv, S, "pumice", int((t - tl) * FPS), p[0], p[1] + 1)
        # 立起层（按脚底 y）
        ups = [(ex[1], "ey", None)]
        for fo in foes:
            if fo[3] is None or t < fo[3]:
                ups.append((fo[1], "foe", fo))
        if t >= T_IMP:
            ups.append((C[1] + 2, "fount", None))
            if t <= 4.8:
                ups.append((C[1] + 1, "poolup", None))
        for p, p0, tl, hb in bombs:
            if tl - 0.16 <= t < tl:
                ups.append((p[1] - 1, "bomb", (p, p0, tl)))
        ups.sort(key=lambda u: u[0])
        for _, kind, d in ups:
            if kind == "ey":
                cv.alpha_composite(ey, (ex[0] - 32, ex[1] - 60))
                sil.alpha_composite(ey, (ex[0] - 32, ex[1] - 60))
            elif kind == "foe":
                im = en[d[2]]
                cv.alpha_composite(im, (int(d[0] - im.width / 2), int(d[1] - im.height + 4)))
                sil.alpha_composite(im, (int(d[0] - im.width / 2), int(d[1] - im.height + 4)))
            elif kind == "fount":
                put(cv, S, "ufount", int((t - T_IMP) * FPS), *C)
            elif kind == "poolup":
                put(cv, S, "poolup", gf, *C)
            elif kind == "bomb":
                p, p0, tl = d
                k = 1 - (tl - t) / 0.16
                pos = (p0[0] + (p[0] - p0[0]) * k, p0[1] + (p[1] - p0[1]) * k)
                dd, fl = pick_dir(math.atan2(p[1] - p0[1], p[0] - p0[0]))
                put(cv, S, "ball_rock_d%d" % dd, gf, pos[0], pos[1] - 6, fl)
        # 预备：光点吸进中心
        if T_IMP - 2 / FPS <= t < T_IMP:
            k = (t - (T_IMP - 2 / FPS)) / (2 / FPS)
            for (x0, y0) in pull:
                x, y = x0 + (C[0] - x0) * k, y0 + (C[1] - y0) * k
                px(cv, x, y - 8, EYC[7]); px(cv, x + 1, y - 8, EYC[5])
        # 亮核：中心小一圈（不平涂大圆），亮 2 拍
        if T_IMP <= t < T_IMP + 2 / FPS:
            for yy in range(-9, 10):
                for xx in range(-13, 14):
                    q = math.hypot(xx / 13, yy / 9) * (0.85 + 0.3 * h(xx * 0.7 + yy * 1.3))
                    if q <= 1:
                        px(cv, C[0] + xx, C[1] - 14 + yy, EYC[6] if q < 0.45 else (EYC[7] if q < 0.75 else EYC[5]))
        for sp in sparks:
            sp.draw(cv, t)
        img = bloom(cv)
        # 照地灯：亮核那 2 拍打满（240 世界像素 = 120 美术像素），之后 0.15 秒衰减
        lk = 0.0
        if t >= T_IMP:
            lk = 1.0 if t < T_IMP + 2 / FPS else max(0.0, 1 - (t - T_IMP - 2 / FPS) / 0.15)
        img = warm_light(img, C[0], C[1], 120, lk)
        if ph == "hf":   # 冲击帧两拍（保留）：第 1 拍白底黑剪影，第 2 拍黑底白剪影
            m = np.asarray(sil)[..., 3] > 100
            first = (r_t - T_IMP) < 0.5 / FPS
            a = np.full((H, W, 3), 245 if first else 10, np.uint8)
            a[m] = (12, 8, 10) if first else (245, 240, 236)
            img = Image.fromarray(a)
        # 轻震 3 世界像素 / 0.12 秒（亮核起）
        if T_IMP <= t < T_IMP + 0.12 * SLOW_K + 1e-6 or (ph == "slow" and r_t - T_IMP - HF_REAL < 0.12):
            sh = 2 if fi % 2 == 0 else -2
            img = img.transform(img.size, Image.AFFINE, (1, 0, sh / PX, 0, 1, -sh / PX))
        frames.append(img.resize((W * PX, H * PX), Image.NEAREST))
    return frames, gtimes


# ---------------------------------------------------------------- 音效（素材只用仓库已有的 Sonniss GDC 2026 免版税录音，不用原作客户端音源）
SON = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(ROOT))) if ".claude" in ROOT else os.path.dirname(ROOT), "build", "sfx_lib", "sonniss_gdc2026", "extracted")
SFX = [   # (槽, 文件, 截取起点 秒, 截取长度, 音高, 音量 dB, 低通 Hz, 游戏时刻 / 实时标记, 说明)
    ("起手", "Epic Stock Media - Elemental Mutation Whooshes and Impacts/FIREWhsh_Whoosh Fire Deep Growl Monster Saturated Crisp 03_ESM_EMWI.wav", 0.35, 0.75, 0.9, -12, 3000, ("g", 0.0), "火焰低吼呼啸，降半音、去刺"),
    ("蓄压", "Epic Stock Media - Elemental Mutation Whooshes and Impacts/WATRImpt_Impact Water Deep Submerge Bubble Drown Ship Hit 05_ESM_EMWI.wav", 0.0, 0.45, 0.75, -16, 2500, ("g", 0.02), "海底深水闷泡（海底火山的压力往上顶）"),
    ("最大爆炸", "Federico Soler - Effective Trailer Booms Vol. 2/EffectiveTrailer_Booms_Vol2_075.wav", 0.0, 3.6, 0.85, -5, 6000, ("hf", 0.0), "预告片级低频轰，降调 0.85 配慢放，3.6 秒长尾淡出"),
    ("最大爆炸·碎块", "Cinematic Sound Design - Colossal Impacts/Woosh Debris.wav", 0.2, 1.4, 0.8, -13, 4000, ("hf", 0.14), "地壳碎块崩飞的呼啸，压低频带"),
    ("火山弹", "Epic Stock Media - Anime Game/EXPLDsgn_Explosion Small Blast Enemy Death Crunchy Boom Cartoon Noisy Crash Impact Delay 03_ESM_AG.wav", 0.0, 0.5, 0.8, -19, 3500, ("bombs", 0.0), "小爆，三档音高轮换（0.72 / 0.8 / 0.9），0.07 秒节流，同原版 bomb_1–3 的节奏"),
    ("熔岩池", "344 Audio - Haunting Ambiences Vol. 5/FIRECrkl_Fire Crackling, Popping, Witch's Cauldron_344 Audio_Haunting Ambiences Vol 5.wav", 4.0, 3.2, 0.8, -15, 3500, ("g", 1.0), "熔岩冒泡噼啪（女巫锅），2.2 秒后淡出"),
    ("收尾", "344 Audio - Elemental Palette Designed Vol. 1/WATRMisc_Water, Liquid Impact, Bubble, Sci Fi, Hit 04_344 Audio_Elemental Palette Designed Vol 1.wav", 0.0, 1.0, 0.6, -17, 2500, ("g", 3.2), "判定结束、熔岩结壳：一记降调的闷泡收住"),
]


def load_wav(path, st, dur, pitch, db, lp):
    import imageio_ffmpeg
    ff = imageio_ffmpeg.get_ffmpeg_exe()
    sr = 44100
    af = "atrim=start=%g:duration=%g,asetrate=%d,aresample=%d,lowpass=f=%d,afade=t=out:st=%g:d=%g" % (st, dur / pitch, int(sr * pitch), sr, lp, max(0.0, dur * 0.65), dur * 0.35)
    p = subprocess.run([ff, "-loglevel", "error", "-i", path, "-ac", "1", "-af", af, "-f", "s16le", "-ar", str(sr), "-"], capture_output=True)
    a = np.frombuffer(p.stdout, np.int16).astype(np.float32) / 32768
    return a * (10 ** (db / 20))


def mix_audio(gtimes, bombs_t, path):
    sr = 44100
    total = int(len(gtimes) / FPS * sr) + sr
    out = np.zeros(total, np.float32)
    rows = []
    hf_real = T_IMP
    for slot, f, st, dur, pitch, db, lp, (kind, off), note in SFX:
        full = os.path.join(SON, f)
        ts = []
        if kind == "g":
            ts = [real_of(off)]
        elif kind == "hf":
            ts = [hf_real + off]
        elif kind == "bombs":
            last = -9.0
            for i, tl in enumerate(sorted(bombs_t)):
                rt = real_of(tl)
                if rt - last >= 0.07:
                    ts.append(rt)
                    last = rt
        for i, rt in enumerate(ts):
            pp = pitch * ([0.9, 1.0, 1.12][i % 3] if kind == "bombs" else 1.0)
            a = load_wav(full, st, dur, pp, db, lp)
            s = int(rt * sr)
            e = min(total, s + len(a))
            out[s:e] += a[:e - s]
        rows.append((slot, os.path.basename(f), ts[0] if ts else 0.0, len(ts), db, pitch, lp, note))
    pk = np.abs(out).max()
    if pk > 0.89:   # 软限幅到 −1 dBFS
        out = np.tanh(out / 0.89) * 0.89
    import wave
    w = wave.open(path, "wb")
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(sr)
    w.writeframes((np.clip(out, -1, 1) * 32767).astype(np.int16).tobytes())
    w.close()
    return rows


def label(im, s):
    d = ImageDraw.Draw(im)
    f = ImageFont.truetype(FONT, 26)
    d.rectangle((0, 0, d.textlength(s, font=f) + 20, 40), fill=(10, 10, 14))
    d.text((10, 4), s, fill=(235, 235, 235), font=f)
    return im


def save_gif(frames, path, scale=1.0):
    fr = [f.resize((int(f.width * scale), int(f.height * scale)), Image.NEAREST) if scale != 1.0 else f for f in frames]
    pal = [f.convert("P", palette=Image.ADAPTIVE, colors=200) for f in fr]
    pal[0].save(path, save_all=True, append_images=pal[1:], duration=int(1000 / FPS), loop=0, optimize=True, disposal=1)
    print(path, len(fr), "帧", "%.1f MB" % (os.path.getsize(path) / 1048576))


def orig_frames(mp4, n, t_imp):
    """原版录像（GCP ult_rec，30 帧）：找冲击帧（整屏最白的那一帧），按 15 fps 取 n 帧，让冲击帧和新版对齐"""
    import imageio_ffmpeg
    ff = imageio_ffmpeg.get_ffmpeg_exe()
    tmp = os.path.join(os.path.dirname(mp4), "_of")
    os.makedirs(tmp, exist_ok=True)
    subprocess.run([ff, "-loglevel", "error", "-y", "-i", mp4, "-vf", "fps=15,scale=1280:720", os.path.join(tmp, "f%04d.png")], check=True)
    fs = sorted(os.listdir(tmp))
    br = [np.asarray(Image.open(os.path.join(tmp, f)).convert("L").resize((64, 36))).mean() for f in fs]
    ki = int(np.argmax(br))
    st = ki - int(round(t_imp * FPS))
    out = []
    for i in range(n):
        j = min(len(fs) - 1, max(0, st + i))
        out.append(Image.open(os.path.join(tmp, fs[j])).convert("RGB"))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--orig", default="")
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    S = strips(os.path.join(ROOT, "build", "ult_eyja_mock"))
    fr, gt = render(S, a.out)
    lab = [label(f.copy(), "艾雅法拉 终结技「海底火山」· 转平面样稿（本机合成，15 fps，含冲击帧与慢放）") for f in fr]
    save_gif(lab, os.path.join(a.out, "ult_eyja_new.gif"), 0.75)
    # 带音效的预览 mp4（GIF 没有声音）
    bombs_t = [0.55 + 0.45 * i / 38 for i in range(38)]
    wav = os.path.join(a.out, "ult_eyja_new_sfx.wav")
    rows = mix_audio(gt, bombs_t, wav)
    import imageio_ffmpeg
    ff = imageio_ffmpeg.get_ffmpeg_exe()
    tmp = os.path.join(ROOT, "build", "ult_eyja_mock", "_nf")
    os.makedirs(tmp, exist_ok=True)
    for i, f in enumerate(lab):
        f.save(os.path.join(tmp, "f%04d.png" % i))
    subprocess.run([ff, "-loglevel", "error", "-y", "-framerate", str(FPS), "-i", os.path.join(tmp, "f%04d.png"), "-i", wav, "-c:v", "libx264", "-pix_fmt", "yuv420p", "-r", "30", "-crf", "24",
                    "-c:a", "aac", "-b:a", "160k", "-shortest", os.path.join(a.out, "ult_eyja_new_sfx.mp4")], check=True)
    with open(os.path.join(a.out, "sfx_list.md"), "w", encoding="utf-8") as fo:
        fo.write("# 艾雅法拉终结技（转平面样稿）音效清单\n\n时间 = 出招起点后的实时秒数（含冲击帧 2 拍与 0.3 倍慢放）；素材全是仓库已有的 Sonniss GDC 2026 免版税录音（build/sfx_lib/sonniss_gdc2026），不含原作客户端音源。\n\n")
        fo.write("| 槽 | 文件 | 第几秒 | 次数 | 音量 dB | 音高 | 低通 Hz | 说明 |\n|---|---|---|---|---|---|---|---|\n")
        for slot, name, t0, n, db, pitch, lp, note in rows:
            fo.write("| %s | %s | %.2f | %d | %d | %.2f | %d | %s |\n" % (slot, name, t0, n, db, pitch, lp, note))
    print("音效清单", os.path.join(a.out, "sfx_list.md"))
    if a.orig:
        of = orig_frames(a.orig, len(fr), T_IMP)
        both = []
        for o, n in zip(of, fr):
            im = Image.new("RGB", (1280 * 2 + 8, 720), (10, 10, 14))
            im.paste(label(o.copy(), "① 当前游戏（GCP 实录，integ-1105）"), (0, 0))
            im.paste(label(n.copy(), "② 转平面样稿（本机合成）"), (1288, 0))
            both.append(im)
        save_gif(both, os.path.join(a.out, "ult_eyja_before_after.gif"), 0.5)


if __name__ == "__main__":
    main()
