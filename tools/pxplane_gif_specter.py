#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""归溟幽灵鲨转平面（docs/268）交审前预览：只用 Python 把帧条（game/art/fx/pxp/pxp_su_*.png + data/pxp_specter_unchained.json）
和运行时件（火星、替身残影、连携斩线、锯鸣点）拼成 GIF，不开 Godot。

每招一张：E0 / E1 / E2 左右并排（只放该招实际存在的档），连携单独一张；游戏地面色背景 + 怪物剪影；
上半 1 倍（1 特效像素 = 2 屏幕像素，同游戏），下半同一时刻以她为中心的 2 倍局部；15 fps 原速循环。
摆放照 fx_pxplane_su.gd：锯环分前后半圈（后半圈排在她身后、前半圈排在身前），贴地件在最下层，立起件和单位按脚底 y 排序；
热芯 emit 点加一层柔光（近似光学发光层；实机还会被场景压暗 / 受光）。

用法（仓库根目录）：python tools/pxplane_gif_specter.py [--out 目录] [--only atk,s1,...]
"""
import argparse, json, math, os, random

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAIN = os.path.dirname(os.path.dirname(os.path.dirname(ROOT))) if ".claude" in ROOT else ROOT
PX = 2
FPS = 15
SY = 0.72
PW, PH = 400, 300
META = json.load(open(os.path.join(ROOT, "game", "data", "pxp_specter_unchained.json"), encoding="utf-8"))
_cache = {}

SPK = [(255, 243, 204), (255, 210, 122), (255, 160, 74), (227, 105, 42), (138, 61, 29)]
GH = [(14, 56, 70), (42, 124, 150), (108, 205, 228), (198, 244, 255)]
AB = [(6, 10, 21), (13, 24, 50), (23, 47, 94), (35, 77, 148), (58, 119, 194), (120, 175, 230), (196, 226, 250), (255, 255, 255)]


def strip(k):
    if k not in _cache:
        m = META[k]
        im = Image.open(os.path.join(ROOT, "game", "art", "fx", "pxp", "pxp_su_%s.png" % k.replace("_d-", "_dm"))).convert("RGBA")
        w, h = m["w"], m["h"]
        _cache[k] = [im.crop((i * w, 0, (i + 1) * w, h)).resize((w * PX, h * PX), Image.NEAREST) for i in range(m["n"])]
    return _cache[k]


def snap(x, y):
    return (round(x / 2) * 2, round(y / 2) * 2)


def font(sz):
    for f in ("C:/Windows/Fonts/msyhl.ttc", "C:/Windows/Fonts/msyh.ttc"):
        if os.path.exists(f):
            return ImageFont.truetype(f, sz)
    return ImageFont.load_default()


def ground():
    t = Image.open(os.path.join(ROOT, "game", "art", "world", "terrain", "terrain_regions.png")).convert("RGBA")
    tile = t.crop((0, 0, 32, 32)).resize((64, 64), Image.NEAREST)
    bg = Image.new("RGBA", (PW, PH), (24, 45, 55, 255))
    for y in range(0, PH, 64):
        for x in range(0, PW, 64):
            bg.alpha_composite(tile, (x, y))
    return bg


def _frames(path, n):
    im = Image.open(path).convert("RGBA")
    fw = im.width // n
    return [im.crop((i * fw, 0, (i + 1) * fw, im.height)) for i in range(n)]


OPD = os.path.join(ROOT, "game/art/operators/specter_unchained")
SU_IDLE = _frames(os.path.join(OPD, "op_specter_unchained_idle@2x.png"), 8)
SU_ATK = _frames(os.path.join(OPD, "op_specter_unchained_attack@2x.png"), 12)
SU_ATK3 = _frames(os.path.join(OPD, "op_specter_unchained_attack_s3@2x.png"), 12)
SU_DOLL = _frames(os.path.join(OPD, "op_specter_unchained_doll@2x.png"), 4)
SU_DAP = _frames(os.path.join(OPD, "op_specter_unchained_doll_appear@2x.png"), 8)
SU_DSP = _frames(os.path.join(OPD, "op_specter_unchained_doll_spin@2x.png"), 8)
SU_DVA = _frames(os.path.join(OPD, "op_specter_unchained_doll_vanish@2x.png"), 8)
EN = {
    "runner": (_frames(os.path.join(ROOT, "game/art/enemies/runner/e_runner@2x.png"), 4)[0], (0.56, 0.875)),
    "slider": (_frames(os.path.join(ROOT, "game/art/enemies/slider/e_slider@2x.png"), 4)[0], (0.5, 0.85)),
}


def silhouette(im):
    a = np.asarray(im)[..., 3]
    out = np.zeros((im.height, im.width, 4), np.uint8)
    out[..., 0], out[..., 1], out[..., 2] = 9, 14, 20
    out[..., 3] = (a > 40) * 235
    return Image.fromarray(out, "RGBA")


EN_S = {k: (silhouette(v[0]).resize((v[0].width * 3 // 4, v[0].height * 3 // 4), Image.NEAREST), v[1]) for k, v in EN.items()}


def tint(im, col, a):
    """替身残影：本体当前帧按替身青着色（乘色）+ 整体透明度（同 fx_pxplane_su 的 Color(0.45, 0.95, 1.15, a)）"""
    arr = np.asarray(im).astype(np.float32)
    arr[..., 0] = np.clip(arr[..., 0] * col[0], 0, 255)
    arr[..., 1] = np.clip(arr[..., 1] * col[1], 0, 255)
    arr[..., 2] = np.clip(arr[..., 2] * col[2], 0, 255)
    arr[..., 3] *= a
    return Image.fromarray(arr.astype(np.uint8), "RGBA")


def comp(img, fr, x, y):
    x0, y0 = max(0, -x), max(0, -y)
    x1, y1 = min(fr.width, img.width - x), min(fr.height, img.height - y)
    if x1 <= x0 or y1 <= y0:
        return
    img.alpha_composite(fr.crop((x0, y0, x1, y1)), (x + x0, y + y0))


def pick_dir(ang):
    a = (math.degrees(ang) + 180) % 360 - 180
    flip = False
    if abs(a) > 90:
        a = (180 - a + 180) % 360 - 180
        flip = True
    best = min([-90, -45, 0, 45, 90], key=lambda d: abs(a - d))
    return best, flip


def bucket(v, opts):
    return min(opts, key=lambda o: abs(o - v))


class Panel:
    def __init__(self, label, me=(200, 175), face=1, tier=0):
        self.label, self.me, self.face, self.tier = label, me, face, tier
        self.items, self.enemies, self.swings, self.sparks, self.rt = [], [], [], [], []
        self.s3 = None
        self.move = None   # t → 位置（S2 残影演示）
        self.hidden = []   # (t0, t1) 本体不画（替身期间）

    def pos(self, t):
        return self.move(t) if self.move else self.me

    def en(self, x, y, kind="runner", r=20):
        e = {"pos": (x, y), "kind": kind, "r": r}
        self.enemies.append(e)
        return e

    def add(self, k, t0, gp, ly="up", flip=False, sk=0.0, loop=False, life=None, follow=False):
        if k not in META:
            raise KeyError(k)
        it = {"k": k, "t0": t0, "gp": gp, "ly": ly, "flip": flip, "sk": sk, "loop": loop, "life": life}
        if follow:
            it["fo"] = (gp[0] - self.me[0], gp[1] - self.me[1])
        self.items.append(it)

    # ---- 照 fx_pxplane_su.gd 的摆法
    def ring(self, sty, r_world, t0, rev=False, es=(), heavy=False):
        R = bucket(r_world / 2.0, RING_R[sty])
        k = "saw_%s_r%d" % (sty, R)
        sk = R * 2 * SY * 0.8
        self.add(k + "_bk_up", t0, self.me, "up", rev, -sk, follow=True)
        self.add(k + "_fr_up", t0, self.me, "up", rev, sk, follow=True)
        if k + "_gd" in META:
            self.add(k + "_gd", t0, self.me, "gd", rev, follow=True)
        if heavy:
            self.add("gouge_r%d_gd" % bucket(r_world / 2.0, RING_R["h"]), t0, self.me, "gd", rev)
        self.hit_sparks(t0, es, rev, 5 if heavy else 2, heavy)

    def hit_sparks(self, t0, es, rev, n, heavy=False):
        rnd = random.Random(int(t0 * 1000) + len(self.sparks))
        lst = sorted(es, key=lambda e: math.hypot(e["pos"][0] - self.me[0], e["pos"][1] - self.me[1]))[:5 if not heavy else 6]
        for e in lst:
            ex, ey = e["pos"]
            hx, hy = ex, ey - e["r"] * 0.5
            rd = (ex - self.me[0], ey - self.me[1])
            L = max(1.0, math.hypot(*rd))
            tg = (-rd[1] / L, rd[0] / L)
            if rev:
                tg = (-tg[0], -tg[1])
            for i in range(n):
                sp = rnd.uniform(150, 260) * (1.25 if heavy else 1.0)
                a = math.atan2(tg[1], tg[0]) + rnd.uniform(-0.5, 0.5)
                self.sparks.append({"t0": t0, "p": (hx, hy), "v": (math.cos(a) * sp + rd[0] / L * 40, math.sin(a) * sp * 0.8 - rnd.uniform(40, 120)),
                                    "gy": ey + 2, "life": rnd.uniform(0.25, 0.4)})


RING_R = {}
for k in META:
    if k.startswith("saw_") and k.endswith("_bk_up"):
        p = k.split("_")
        RING_R.setdefault(p[1], []).append(int(p[2][1:]))
RING_R["h"] = sorted(RING_R["h"])


def spark_state(s, t):
    """同 fx_pxplane_su._spark_step：屏幕坐标积分，重力 760、阻尼 2.2，落到 gy 以下熄灭"""
    u = t - s["t0"]
    if u < 0 or u > s["life"]:
        return None
    x, y = s["p"]
    vx, vy = s["v"]
    dt = 1 / 60
    k = 0.0
    while k < u:
        x += vx * dt
        y += vy * dt
        vy += 760 * dt
        vx *= (1 - 2.2 * dt)
        vy *= (1 - 2.2 * dt)
        k += dt
        if y > s["gy"]:
            return None
    return (x, y, vx, vy, u / s["life"])


def draw_spark(img, st):
    x, y, vx, vy, a = st
    c = SPK[0] if a < 0.2 else (SPK[1] if a < 0.45 else (SPK[2] if a < 0.75 else SPK[3]))
    c2 = SPK[min(4, (0 if a < 0.2 else 1 if a < 0.45 else 2 if a < 0.75 else 3) + 1)]
    L = max(1.0, math.hypot(vx, vy))
    d = ImageDraw.Draw(img)
    p = snap(x, y)
    q = snap(x - vx / L * 2, y - vy / L * 2)
    d.rectangle([q[0], q[1], q[0] + 1, q[1] + 1], fill=c2 + (255,))
    d.rectangle([p[0], p[1], p[0] + 1, p[1] + 1], fill=c + (255,))
    return p, c


def draw_line_px(img, a, b, cols, teeth=False, t=0, glow=None):
    """连携斩线：沿线逐美术像素（2 世界像素）画，白芯 + 两侧替身青；teeth = 一侧每 6 格一个锯齿尖（同 fx_pxplane_su._draw_cut_line）"""
    d = ImageDraw.Draw(img)
    L = math.hypot(b[0] - a[0], b[1] - a[1])
    n = int(L / 2)
    dx, dy = (b[0] - a[0]) / max(1, L), (b[1] - a[1]) / max(1, L)
    nx, ny = -dy, dx
    for i in range(n + 1):
        u = i / max(1, n)
        w = 1.0 - abs(u - 0.6) / 0.6
        x, y = a[0] + dx * i * 2, a[1] + dy * i * 2
        if cols[0] is not None and w > 0.15:
            p = snap(x, y)
            d.rectangle([p[0], p[1], p[0] + 1, p[1] + 1], fill=cols[0] + (255,))
            if glow is not None and i % 2 == 0:
                glow.append((p, cols[0]))
        if cols[1] is not None and w > 0.35:
            for s in (-1, 1):
                p = snap(x + nx * 2 * s, y + ny * 2 * s)
                d.rectangle([p[0], p[1], p[0] + 1, p[1] + 1], fill=cols[1] + (255,))
        if teeth and cols[1] is not None and i % 6 == 0 and 0.1 < u < 0.95:
            for k in (2, 3):
                p = snap(x + nx * 2 * k + dx * 2 * (k - 2), y + ny * 2 * k + dy * 2 * (k - 2))
                d.rectangle([p[0], p[1], p[0] + 1, p[1] + 1], fill=cols[1] + (255,))


def vwake(img, a, b, u):
    """同 fx_pxplane_su._draw_cut_scars：鲨鳍划水的 V 形水痕，尖在斩线末端"""
    d_ = ImageDraw.Draw(img)
    L = math.hypot(b[0] - a[0], b[1] - a[1])
    dx, dy = (b[0] - a[0]) / L, (b[1] - a[1]) / L
    nx, ny = -dy, dx * SY
    for i in range(int(L / 2) + 1):
        s_ = i * 2
        k = s_ / L
        if i % 3 == 2 or k > 0.85:
            continue
        c = (230, 243, 255) if k < 0.2 else (AB[5] if k < 0.45 else AB[3])
        if u > 0.5:
            c = AB[4] if k < 0.3 else AB[2]
        for sd in (-1, 1):
            p = snap(b[0] - dx * s_ + nx * sd * s_ * 0.16, b[1] - dy * s_ + ny * sd * s_ * 0.16)
            d_.rectangle([p[0], p[1], p[0] + 1, p[1] + 1], fill=c + (255,))


def render(P, t):
    img = ground()
    glow = np.zeros((PH, PW, 3), np.float32)
    gl_pts = []
    mepos = P.pos(t)

    def gp_of(it):
        if "fo" in it:
            return snap(mepos[0] + it["fo"][0], mepos[1] + it["fo"][1])
        return snap(*it["gp"])

    def draw_item(it):
        fi = int(math.floor(t * FPS + 1e-6)) - int(math.floor(it["t0"] * FPS + 1e-6))
        frs = strip(it["k"])
        m = META[it["k"]]
        if it["loop"]:
            if t < it["t0"] or t > it["t0"] + (it["life"] or 99):
                return
            fi = int(math.floor(t * FPS + 1e-6)) % len(frs)
        elif fi < 0 or fi >= len(frs):
            return
        fr = frs[fi]
        gx, gy = gp_of(it)
        if it["flip"]:
            fr = fr.transpose(Image.FLIP_LEFT_RIGHT)
            left = gx - (m["w"] - m["ox"]) * PX
        else:
            left = gx - m["ox"] * PX
        top = gy - m["oy"] * PX
        comp(img, fr, int(left), int(top))
        for q in (m["emit"][fi] if fi < len(m["emit"]) else []):
            x = q[0] if not it["flip"] else m["w"] - 1 - q[0]
            X, Y = int(left + x * PX), int(top + q[1] * PX)
            if 0 <= X < PW - 1 and 0 <= Y < PH - 1:
                c = int(q[2], 16)
                glow[Y:Y + 2, X:X + 2] += np.array([(c >> 16) & 255, (c >> 8) & 255, c & 255], np.float32) / 255.0 * 0.8

    for it in P.items:
        if it["ly"] == "gd":
            draw_item(it)
    for fn in P.rt:
        if getattr(fn, "floor", False):
            fn(img, t, gl_pts)
    draws = []
    for it in P.items:
        if it["ly"] == "up":
            g = gp_of(it)
            draws.append((g[1] + 1 + it["sk"], lambda it=it: draw_item(it)))
    for e in P.enemies:
        sil, (ax, ay) = EN_S[e["kind"]]
        x, y = e["pos"]
        draws.append((y, lambda sil=sil, ax=ax, ay=ay, x=x, y=y: comp(img, sil, int(x - sil.width * ax), int(y - sil.height * ay))))
    if not any(a <= t < b for a, b in P.hidden):
        im, (fx, fy) = su_sprite(P, t)
        draws.append((mepos[1], lambda im=im, fx=fx, fy=fy: comp(img, im, int(mepos[0] - fx), int(mepos[1] - fy))))
    for fn in P.rt:
        if not getattr(fn, "floor", False):
            for y, f2 in fn(img, t, gl_pts):
                draws.append((y, f2))
    for _, fn in sorted(draws, key=lambda d: d[0]):
        fn()
    for s in P.sparks:   # 火星画在上层
        st = spark_state(s, t)
        if st:
            p, c = draw_spark(img, st)
            if st[4] < 0.45:
                gl_pts.append((p, c))
    for p, c in gl_pts:
        X, Y = p
        if 0 <= X < PW - 1 and 0 <= Y < PH - 1:
            glow[Y:Y + 2, X:X + 2] += np.array(c, np.float32) / 255.0 * 0.8
    g = Image.fromarray(np.clip(glow * 255, 0, 255).astype(np.uint8), "RGB").filter(ImageFilter.GaussianBlur(3))
    a = np.asarray(img).astype(np.float32)
    a[..., :3] = np.clip(a[..., :3] + np.asarray(g).astype(np.float32) * 0.9, 0, 255)
    return Image.fromarray(a.astype(np.uint8), "RGBA")


def su_sprite(P, t):
    im = SU_IDLE[int(t * 4.36) % 8]
    feet = (64, 120)
    for s, heavy in P.swings:
        if s - 0.21 <= t < s + 0.7:
            fr = SU_ATK3 if heavy else SU_ATK
            k = min(11, int((t - s + 0.21) / 0.076))
            im = fr[k]
            feet = (96, 152)
    if P.face < 0:
        im = im.transpose(Image.FLIP_LEFT_RIGHT)
        feet = (im.width - feet[0], feet[1])
    return im, feet


def make_gif(panels, L, path, title, focus=None):
    n = int(round(L * FPS))
    out = []
    W = PW * len(panels) + 4 * (len(panels) - 1)
    for i in range(n):
        t = i / FPS
        canvas = Image.new("RGBA", (W, 24 + PH + 20 + PH), (10, 12, 18, 255))
        d = ImageDraw.Draw(canvas)
        d.text((8, 3), title, fill=(220, 225, 240, 255), font=font(14))
        d.text((8, 24 + PH + 2), "下：同一时刻 2 倍局部（以她为中心）", fill=(150, 160, 185, 255), font=font(12))
        for j, P in enumerate(panels):
            fr = render(P, t)
            lab = fr.copy()
            ImageDraw.Draw(lab).text((8, 6), P.label, fill=(205, 214, 255, 255), font=font(13))
            canvas.alpha_composite(lab, (j * (PW + 4), 24))
            c = focus[j] if focus else P.pos(t)
            x0 = int(min(max(0, c[0] - PW / 4), PW / 2))
            y0 = int(min(max(0, c[1] - 30 - PH / 4), PH / 2))
            z = fr.crop((x0, y0, x0 + PW // 2, y0 + PH // 2)).resize((PW, PH), Image.NEAREST)
            canvas.alpha_composite(z, (j * (PW + 4), 24 + PH + 20))
        out.append(canvas.convert("RGB"))
    q = [f.quantize(colors=255, method=Image.MEDIANCUT, dither=Image.NONE) for f in out]
    dur = [70 if i % 3 != 2 else 60 for i in range(n)]   # GIF 以 10 ms 计：70 / 70 / 60 平均 66.7 ms = 15 fps
    q[0].save(path, save_all=True, append_images=q[1:], duration=dur, loop=0, disposal=1, optimize=False)
    print(path, n, "帧", "%.1f MB" % (os.path.getsize(path) / 1e6))


# ---------------------------------------------------------------- 场景
def ring_enemies(P, R=102, spread=1.0):
    cx, cy = P.me
    es = []
    pts = [(0.75, -20), (0.55, 40), (0.85, 120), (0.6, 170), (0.9, 220), (0.5, 280), (0.95, 330), (1.4, 10), (1.5, 200)]
    for i, (k, a) in enumerate(pts):
        rr = R * k * spread
        es.append(P.en(cx + rr * math.cos(math.radians(a)), cy + rr * math.sin(math.radians(a)) * 0.8, "runner" if i % 2 else "slider", 20 if i % 2 else 22))
    return es


def in_r(P, es, r):
    return [e for e in es if math.hypot(e["pos"][0] - P.me[0], e["pos"][1] - P.me[1]) <= r + e["r"]]


def mv_atk():
    ps = []
    labels = ["E0  锯环：前倾锯齿每拍转、白热刀头弧扫过；命中火星",
              "E1  + 卷刃：起手外圈一道往里收的水纹",
              "E2  + 锯齿甩水珠；每第 3 圈替身闪现"]
    for t in (0, 1, 2):
        P = Panel(labels[t], tier=t)
        es = ring_enemies(P)
        hit = in_r(P, es, 102)
        swings = (0.3, 1.1, 1.9) if t == 2 else (0.3, 1.1)
        for i, sw in enumerate(swings):
            P.swings.append((sw, False))
            P.ring("w" if t == 2 else "n", 102, sw, rev=(i % 2 == 1), es=hit)
            if t >= 1:
                P.add("curl_r80_gd", sw - 0.2, P.me, "gd")
        if t == 2:   # 第 3 圈：替身在敌群最密处（右侧）现身 → 3 次脉冲 → 碎成泡沫
            doll_flash(P, 2.0, (P.me[0] + 120, P.me[1] - 10), es)
        ps.append(P)
    return ps, 3.0 if True else 1.6, "普攻「锯刃」环斩（半径 102）：每升一档多一个新元素"


def doll_flash(P, t0, c, es):
    ap, gap = 0.25, 0.15
    P.add("flin_up", t0, c, "up")
    for k in range(3):
        P.add("flpulse_gd", t0 + ap + 0.08 + k * gap, c, "gd")
    P.add("flout_up", t0 + ap + 0.3, c, "up")
    near = [e for e in es if math.hypot(e["pos"][0] - c[0], e["pos"][1] - c[1]) < 140][:4]
    for k in range(3):
        for e in near[:2]:
            P.sparks.append({"t0": t0 + ap + 0.08 + k * gap, "p": (e["pos"][0], e["pos"][1] - 10), "v": (0, -60), "gy": e["pos"][1] + 2, "life": 0.01})

    def body(img, t, gl):
        u = t - t0
        if u < 0 or u > ap + 0.3 + 0.3:
            return []
        if u < ap:
            im = SU_DAP[min(7, int(u / ap * 8))]
        elif u < ap + 0.3:
            im = SU_DSP[min(7, int((u - ap) / 0.3 * 8))]
        else:
            im = SU_DVA[min(7, int((u - ap - 0.3) / 0.3 * 8))]
        im = im.transpose(Image.FLIP_LEFT_RIGHT)
        tinted = tint(im, (0.92, 0.96, 1.1), 1.0)
        return [(c[1] + 24, lambda: comp(img, tinted, int(c[0] - 64), int(c[1] - 120)))]
    P.rt.append(body)


def mv_s1():
    ps = []
    labels = ["E0  光柱落下 + 脚下符环；期间深海暗焰",
              "E1  + 脚下水冠",
              "E2  + 两片鲨鳍绕身游"]
    for t in (0, 1, 2):
        P = Panel(labels[t], tier=t)
        es = ring_enemies(P)
        hit = in_r(P, es, 102)
        P.add("s1col_up", 0.1, P.me, "up", sk=-2, follow=True)
        P.add("s1rune_gd", 0.1, P.me, "gd", follow=True)
        if t >= 1:
            P.add("s1crown_up", 0.15, P.me, "up", sk=3, follow=True)
        P.add("s1aura_up", 0.35, P.me, "up", sk=1, loop=True, life=9, follow=True)
        if t >= 2:
            P.add("s1fin_bk_up", 0.35, P.me, "up", sk=-30, loop=True, life=9, follow=True)
            P.add("s1fin_fr_up", 0.35, P.me, "up", sk=30, loop=True, life=9, follow=True)
        for i, sw in enumerate((0.9, 2.1)):
            P.swings.append((sw, False))
            P.ring("w" if t == 2 else "n", 102, sw, rev=i % 2 == 1, es=hit)
            if t >= 1:
                P.add("curl_r80_gd", sw - 0.2, P.me, "gd")
        ps.append(P)
    return ps, 2.8, "S1「生存的技巧」（攻击强化 8 秒）：起手光柱、期间暗焰（原红火改深海蓝，红只给危险）"


def ghost_echo(P, t_on, t_off):
    """S2 期间身后两道替身残影：取 0.1 / 0.2 秒前的位置与帧，替身青乘色、透明度 0.42 / 0.24"""
    def fn(img, t, gl):
        if not (t_on <= t < t_off):
            return []
        out = []
        for lag, a in ((0.24, 0.3), (0.12, 0.5)):
            tt = max(t_on, t - lag)
            p = P.pos(tt)
            im, (fx, fy) = su_sprite(P, tt)
            ti = tint(im, (0.45, 0.95, 1.15), a)
            out.append((p[1] - 0.5, lambda ti=ti, p=p, fx=fx, fy=fy: comp(img, ti, int(p[0] - fx), int(p[1] - fy))))
        return out
    P.rt.append(fn)


def mv_s2():
    ps = []
    labels = ["", "E1  起手白闪 + 冒泡；期间身后两道替身残影", "E2  + 环斩时朝最近敌人一记鲨口咬合"]
    for t in (1, 2):
        P = Panel(labels[t], me=(130, 175), tier=t)
        P.move = lambda tt: (110 + 200 * min(1.0, max(0.0, (tt - 0.4) / 1.6)), 175)
        es = [P.en(300, 140), P.en(330, 190, "slider", 22), P.en(250, 215), P.en(180, 120, "slider", 22)]
        P.add("s2cast_up", 0.1, P.me, "up", sk=2, follow=True)
        P.add("s2cast_gd", 0.1, P.me, "gd", follow=True)
        ghost_echo(P, 0.15, 9)
        for i, sw in enumerate((0.75, 1.5, 2.25)):   # S2 攻速 +60%：环斩间隔约 0.75 秒
            P.swings.append((sw, False))
            P.ring("n", 102, sw, rev=i % 2 == 1, es=[e for e in es if math.hypot(e["pos"][0] - P.pos(sw)[0], e["pos"][1] - P.pos(sw)[1]) < 125])
            if t >= 2:
                tgt = min(es, key=lambda e: math.hypot(e["pos"][0] - P.pos(sw)[0], e["pos"][1] - P.pos(sw)[1]))
                ang = math.atan2(tgt["pos"][1] - P.pos(sw)[1], tgt["pos"][0] - P.pos(sw)[0])
                d, flip = pick_dir(ang)
                P.add("s2bite_up_d%d" % d, sw, P.me, "up", flip, math.sin(ang) * 46.0, follow=True)
        ps.append(P)
    # 第三格：S2 结束倒下 → 替身跟随（替身光环每秒一圈）
    P = Panel("S2 结束：本体倒下 → 水花里替身起身，光环每秒一圈", me=(200, 175), tier=2)
    es = ring_enemies(P, 150)
    P.add("dollin_up", 0.3, P.me, "up", sk=1)
    for k in range(2):
        P.add("dollpulse_gd", 1.1 + k * 1.0, P.me, "gd")
    P.hidden.append((0.3, 99))

    def doll(img, t, gl):
        if t < 0.35:
            return []
        im = SU_DOLL[int((t - 0.35) * 4) % 4].transpose(Image.FLIP_LEFT_RIGHT)
        return [(P.me[1] + 2, lambda: comp(img, im, int(P.me[0] - 48), int(P.me[1] - 92)))]
    P.rt.append(doll)
    ps.append(P)
    return ps, 2.8, "S2「生存的渴望」（精一解锁）：替身意象，残影与本体分色（替身青）"


def mv_s3():
    P = Panel("E2  起手大浪绕身；期间重锯：齿尖橙热、火星多、地上切向锯痕", me=(200, 170), tier=2)
    es = ring_enemies(P, 153)
    hit = in_r(P, es, 153)
    P.add("s3wave_bk_up", 0.1, P.me, "up", sk=-60, follow=True)
    P.add("s3wave_fr_up", 0.1, P.me, "up", sk=60, follow=True)
    P.add("s3wave_gd", 0.1, P.me, "gd")
    for i, sw in enumerate((0.9, 2.0)):
        P.swings.append((sw, True))
        P.ring("h", 153, sw, rev=i % 2 == 1, es=hit, heavy=True)
    P2 = Panel("对照：同一时刻的普攻锯环（E2，半径 102）", me=(200, 170), tier=2)
    es2 = ring_enemies(P2, 102)
    for i, sw in enumerate((0.9, 2.0)):
        P2.swings.append((sw, False))
        P2.ring("w", 102, sw, rev=i % 2 == 1, es=in_r(P2, es2, 102))
    return [P, P2], 2.8, "S3「生存的重压」（精二解锁，环斩范围 ×1.5、更慢更重）"


def hum_dots(P, n, mx):
    def fn(img, t, gl):
        d = ImageDraw.Draw(img)
        full = n >= mx
        for q in range(mx):
            an = 2 * math.pi * q / mx - math.pi / 2
            x, y = snap(P.me[0] + math.cos(an) * 30, P.me[1] + 6 + math.sin(an) * 30 * SY)
            on = q < n
            c = (GH[3] if int(t * 7.5) % 2 == 0 else GH[2]) if full else (AB[6] if on else AB[2])
            d.rectangle([x, y, x + 1, y + 1], fill=c + (255,))
        return
    fn.floor = True
    P.rt.append(fn)


def blades(P, t0, dirs):
    def fn(img, t, gl):
        out = []
        for i, dg in enumerate(dirs):
            u = t - (t0 + i * 0.08)
            if u < 0 or u > 200 / 720:
                continue
            a = math.radians(dg)
            p = (P.me[0] + math.cos(a) * (24 + 720 * u), P.me[1] - 8 + math.sin(a) * (24 + 720 * u))
            d, flip = pick_dir(a)
            k = "blade_up_d%d" % d
            m = META[k]
            fr = strip(k)[int(math.floor(t * FPS)) % m["n"]]
            if flip:
                fr = fr.transpose(Image.FLIP_LEFT_RIGHT)
            gp = snap(p[0], p[1] + 8)
            left = gp[0] - ((m["w"] - m["ox"]) if flip else m["ox"]) * PX
            out.append((gp[1], lambda fr=fr, left=left, gp=gp, m=m: comp(img, fr, int(left), int(gp[1] - m["oy"] * PX))))
        return out
    P.rt.append(blades_fn := fn)


def mv_nodes():
    A = Panel("双重回转：0.15 秒后小一号、抬高一截的锯反转，和主锯环错位交叠", tier=1)
    es = ring_enemies(A)
    for sw in (0.3, 1.5):
        A.swings.append((sw, False))
        A.ring("n", 102, sw, es=in_r(A, es, 102))
        A.ring("d", 102 * 0.7, sw + 0.15, rev=True, es=[])
    B = Panel("血色潮痕：环斩留一圈潮痕 1.5 秒（深海青，只画边）", tier=1)
    es = ring_enemies(B)
    for sw in (0.3, 1.5):
        B.swings.append((sw, False))
        B.ring("n", 102, sw, es=in_r(B, es, 102))
        B.add("tide_r51_gd", sw, B.me, "gd", loop=True, life=1.5)
    C = Panel("锯鸣：攒满 12 点 → 旋锯 0.6 秒（每 0.15 秒一圈）", tier=1)
    es = ring_enemies(C, 133)
    hum_dots(C, 12, 12)
    for k in range(4):
        C.swings.append((0.3 + k * 0.15, False))
        C.ring("s", 133, 0.3 + k * 0.15, rev=k % 2 == 1, es=in_r(C, es, 133)[:3])
    D = Panel("锯鸣·共振：旋锯期间甩水刃，收尾震地（半径 160）", tier=1)
    es = ring_enemies(D, 133)
    for k in range(4):
        D.swings.append((0.3 + k * 0.15, False))
        D.ring("s", 133, 0.3 + k * 0.15, rev=k % 2 == 1, es=in_r(D, es, 133)[:3])
    blades(D, 0.45, [-20, 160, 60])
    D.add("quake_gd", 0.95, D.me, "gd")
    D.add("quake_up", 0.95, D.me, "up", sk=2)
    E = Panel("困兽：S1 期间队长受击 → 立即追加一圈", tier=1)
    es = ring_enemies(E)
    E.swings.append((0.3, False))
    E.ring("n", 102, 0.3, es=in_r(E, es, 102))
    E.add("echo_gd", 0.3, E.me, "gd")
    return [A, B, C, D, E], 2.0, "分支招：双重回转 / 血色潮痕 / 锯鸣 / 锯鸣·共振 / 困兽"


def mv_qi():
    ps = []
    for t in (0, 1, 2):
        P = Panel(["E0  锯盘飞出（钢齿每拍转）", "E1  齿尖橙热 + 火星尾", "E2  + 外圈水沫"][t], me=(110, 175), tier=t)
        es = [P.en(300, 150), P.en(330, 200, "slider", 22), P.en(260, 120, "slider", 22)]

        def fn(img, t_, gl, P=P, t=t):
            out = []
            for i, ang in enumerate((-0.25, 0.15)):
                u = t_ - (0.3 + i * 0.5)
                if u < 0 or u > 0.55:
                    continue
                p = (P.me[0] + math.cos(ang) * (30 + 420 * u), P.me[1] + math.sin(ang) * (30 + 420 * u))
                k = "qi_e%d_up" % t
                m = META[k]
                fr = strip(k)[int(math.floor(t_ * FPS)) % m["n"]]
                gp = snap(p[0], p[1])
                out.append((gp[1], lambda fr=fr, gp=gp, m=m: comp(img, fr, int(gp[0] - m["ox"] * PX), int(gp[1] - m["oy"] * PX))))
                if t >= 1 and int(t_ * 60) % 3 == 0:
                    P.sparks.append({"t0": t_, "p": (p[0] - math.cos(ang) * 10, p[1] - 16), "v": (-math.cos(ang) * 90, -40), "gy": p[1] + 2, "life": 0.22})
            return out
        P.rt.append(fn)
        ps.append(P)
    return ps, 1.6, "后期剑气（growth/late_shape 给近战的额外一击）：锯盘"


def mv_link():
    P = Panel("link/v2 缺省版（不分档）：替身残影冲过 → 带锯齿的斩线 → 鲨鳍划水的 V 形水痕", me=(80, 190))
    es = [P.en(200, 140), P.en(240, 175, "slider", 22), P.en(280, 150), P.en(300, 200, "slider", 22), P.en(220, 210)]
    fp = (80, 190)
    tp = (360, 150)
    T = 0.2
    t0 = 0.3

    def fn(img, t, gl):
        out = []
        u = t - t0
        if 0 <= u < T:   # 冲：3 道替身残影（按冲刺进度排开）
            for g, a in ((0, 0.7), (1, 0.45), (2, 0.22)):
                k = max(0.0, u / T - g * 0.18)
                q = (fp[0] + (tp[0] - fp[0]) * k, fp[1] + (tp[1] - fp[1]) * k)
                im = SU_ATK[6]
                ti = tint(im, (0.45, 0.95, 1.15), a)
                out.append((q[1], lambda ti=ti, q=q: comp(img, ti, int(q[0] - 96), int(q[1] - 152))))
        return out
    P.rt.append(fn)

    def cut(img, t, gl):
        u = t - t0 - T
        if u < 0:
            return
        f = int(math.floor(t * FPS)) - int(math.floor((t0 + T) * FPS))
        if f >= 1 and u < 0.9 and (f % 2 == 0 or u < 0.5):
            vwake(img, (fp[0], fp[1] + 2), (tp[0], tp[1] + 2), u)
        if f <= 2:
            cols = [((255, 255, 255), GH[2]), (GH[3], GH[2]), (GH[2], GH[1])][f]
            draw_line_px(img, fp, tp, cols, teeth=True, glow=gl)
    cut.floor = False

    def cut_up(img, t, gl):
        return [(9999, lambda: cut(img, t, gl))]
    P.rt.append(cut_up)
    for q in range(4):
        pp = (fp[0] + (tp[0] - fp[0]) * (0.3 + 0.18 * q), fp[1] + (tp[1] - fp[1]) * (0.3 + 0.18 * q))
        rnd = random.Random(q)
        for i in range(4):
            a = rnd.uniform(-2.6, -0.5)
            sp = rnd.uniform(140, 240)
            P.sparks.append({"t0": t0 + T, "p": (pp[0], pp[1] - 10), "v": (math.cos(a) * sp, math.sin(a) * sp), "gy": pp[1] + 4, "life": rnd.uniform(0.25, 0.4)})
    P.hidden = []
    return [P], 1.6, "连携「替身斩」（skill_link l_specter，本人不动）"


MOVES = {"atk": mv_atk, "s1": mv_s1, "s2": mv_s2, "s3": mv_s3, "nodes": mv_nodes, "qi": mv_qi, "link": mv_link}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join(MAIN, "Claude outputs", "pxplane_specter_unchained_1105", "gif"))
    ap.add_argument("--only", default="")
    ap.add_argument("--still", type=float, default=-1.0, help="只出这一时刻的静帧 PNG（自查用）")
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    for k, fn in MOVES.items():
        if a.only and k not in a.only.split(","):
            continue
        ps, L, title = fn()
        if a.still >= 0:
            row = Image.new("RGBA", (PW * len(ps) + 4 * (len(ps) - 1), PH), (0, 0, 0, 255))
            for j, P in enumerate(ps):
                row.alpha_composite(render(P, a.still), (j * (PW + 4), 0))
            row.save(os.path.join(a.out, "still_%s_%.2f.png" % (k, a.still)))
            continue
        make_gif(ps, L, os.path.join(a.out, "specter_%s.gif" % k), title)


if __name__ == "__main__":
    main()
