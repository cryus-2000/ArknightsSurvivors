#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""德克萨斯 S3 示意 GIF（11-06 用户「S3 每一次斩击可以是更加明显的一道斩击」「不要太粗，但是要亮」「给我看 gif 就行，不用跑 gcp」）：只用 Python，不开 Godot。
左：现在（每刀一条细主刀痕 + 2–3 条只画不判的细斩线 + 目标处落剑；两轮次元斩之间本体在原地冒出来跑）；
右：fx/texas_s3_hide_captain + fx/texas_s3_single_slash 都开（每刀一道细而亮的斩线：芯 2 格 / 末刀 3 格近白、两侧一格淡琥珀、命中两拍过曝 + 辉光 + 照地光、
到点一拍断掉；命中点火星；隐身期间原地脚下半透明小菱形；结束时瞬移残影回原位 + 淡入）。
画法照搬 render/fx_pxplane.gd 的 _tx_draw_line（style 2）/ _tx_draw_line1（style 3）与 seg_texas.gd 的 _tx_pos_mark，15 fps 节拍、2 px 格；GIF 30 fps 原速。
用法：python tools/texas_s3_slash_gif.py [--out 目录]   → texas_s3_slash_1x.gif / texas_s3_slash_2x.gif
"""
import argparse, json, math, os, random

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAIN = os.path.dirname(os.path.dirname(os.path.dirname(ROOT))) if ".claude" in ROOT else ROOT
FONT = "C:/Windows/Fonts/msyh.ttc"
M = json.load(open(os.path.join(ROOT, "game", "data", "pxp_texas.json"), encoding="utf-8"))
TX_C = [(0x12, 0x08, 0x04), (0x2c, 0x14, 0x06), (0x5a, 0x28, 0x08), (0x9c, 0x46, 0x10), (0xe2, 0x78, 0x1c), (0xff, 0xac, 0x3c), (0xff, 0xdc, 0x9c), (0xff, 0xff, 0xff)]
PX = 2
TX_H = 24
W, H = 380, 230
O = (110, 160)           # 队长逻辑位置（原地）
FPS = 30
T_END = 3.4
S3 = (0.15, 2.95)        # 剑雨滂沱持续
ROUNDS = [[0.25, 0.43, 0.61, 0.79, 0.97], [1.75, 1.93, 2.11, 2.29, 2.47]]
POSE = 0.12
ENEMIES = [(250, 120), (300, 150), (275, 185), (330, 105), (225, 165), (318, 195)]


def sheet(path, n):
    im = Image.open(path).convert("RGBA")
    fw = im.width // n
    return [im.crop((i * fw, 0, (i + 1) * fw, im.height)) for i in range(n)]


def strip(k):
    m = M[k]
    im = Image.open(os.path.join(ROOT, "game", "art", "fx", "pxp", "pxp_%s.png" % k)).convert("RGBA")
    return [im.crop((f * m["w"], 0, (f + 1) * m["w"], m["h"])).resize((m["w"] * 2, m["h"] * 2), Image.NEAREST) for f in range(m["n"])], m


def build_cuts(new):
    rng = random.Random(5)
    cuts = []
    for ri, rd in enumerate(ROUNDS):
        n = len(rd)
        frm = O
        for k, t in enumerate(rd):
            e = ENEMIES[(k + ri * 2) % len(ENEMIES)]
            last = k == n - 1
            L = 72.0 * (1.3 if last else 1.0)
            dr = math.atan2(e[1] - O[1], e[0] - O[0])
            sgn = 1 if k % 2 == 0 else -1
            ua = dr + sgn * (0.6 + 0.12 * k)
            u = (math.cos(ua), math.sin(ua))
            p0 = (e[0] - u[0] * L / 2, e[1] - u[1] * L / 2)
            p1 = (e[0] + u[0] * L / 2, e[1] + u[1] * L / 2)
            if k % 2 == 1:
                p0, p1 = p1, p0
            ud = ((p1[0] - p0[0]) / L, (p1[1] - p0[1]) / L)
            ext = L * 0.6 * (1.6 if new else 1.0)
            a = (p0[0] - ud[0] * ext, p0[1] - ud[1] * ext)
            c = (p1[0] + ud[0] * ext, p1[1] + ud[1] * ext)
            life = 0.22 + (0.08 if new else 0.0)
            lines = []
            if new:
                lines.append({"a": a, "c": c, "w": 3 if last else 2, "hold": max(1, round(life * 15)), "st": 3, "t0": t})
            else:
                lines.append({"a": a, "c": c, "w": 2 if last else 1, "hold": max(1, round(life * 15)), "st": 2, "t0": t})
                for xi in range(2 + (1 if last else 0)):
                    xa = math.atan2(ud[1], ud[0]) + (1 if (k + xi) % 2 == 0 else -1) * rng.uniform(0.35, 1.35)
                    xu = (math.cos(xa), math.sin(xa))
                    xc = (e[0] + rng.uniform(-18, 18), e[1] + rng.uniform(-12, 12))
                    xl = L * rng.uniform(0.7, 1.2) + ext
                    lines.append({"a": (xc[0] - xu[0] * xl / 2, xc[1] - xu[1] * xl / 2), "c": (xc[0] + xu[0] * xl / 2, xc[1] + xu[1] * xl / 2),
                                  "w": 1, "hold": max(1, round(life * rng.uniform(0.8, 1.0) * 15)), "st": 2, "t0": t})
            sparks = []
            if new:
                for i in range(10 if last else 7):
                    ang = rng.uniform(0, math.tau)
                    sp = rng.uniform(60, 170)
                    sparks.append((math.cos(ang) * sp, math.sin(ang) * sp * 0.72 - 40, rng.uniform(0.18, 0.34), rng.random() < 0.5))
                for q in (0.25, 0.75):
                    pq = (a[0] + (c[0] - a[0]) * q, a[1] + (c[1] - a[1]) * q - TX_H)
                    for i in range(2):
                        sparks.append(((ud[0] * (1 if q > 0.5 else -1)) * rng.uniform(60, 120), rng.uniform(-50, -10), rng.uniform(0.2, 0.3), True, pq))
            else:
                for i in range(4):
                    ang = rng.uniform(0, math.tau)
                    sp = rng.uniform(50, 110)
                    sparks.append((math.cos(ang) * sp, math.sin(ang) * sp * 0.72 - 30, rng.uniform(0.15, 0.25), False))
            cuts.append({"t": t, "e": e, "lines": lines, "p1": p1, "p0": p0, "from": frm, "last": last, "round": ri, "sparks": sparks, "fl": (k % 2) == 0})
            frm = p1
    return cuts


def cell(px, x, y, col, a=1.0):
    x = int(math.floor(x / PX) * PX)
    y = int(math.floor(y / PX) * PX)
    if 0 <= x < W - 1 and 0 <= y < H - 1:
        px[y:y + PX, x:x + PX, :3] = px[y:y + PX, x:x + PX, :3] * (1 - a) + np.array(col[:3], dtype=float) * a


def glow(gl, x, y, col, s=1.0):
    x, y = int(x), int(y)
    if 0 <= x < W and 0 <= y < H:
        gl[y, x] += np.array(col) * s


def draw_line(px, gl, it, f):
    a, c = it["a"], it["c"]
    L = math.dist(a, c)
    if L < 4:
        return
    dv = ((c[0] - a[0]) / L, (c[1] - a[1]) / L)
    nv = (-dv[1], dv[0])
    n = max(2, int(L / PX))
    hold, w = it["hold"], it["w"]
    if it["st"] == 3:   # _tx_draw_line1
        if f > hold:
            return
        hot = f <= 1
        broke = f == hold and f > 1
        core = (255, 255, 250) if hot else (255, 242, 220)
        side = TX_C[6] if hot else TX_C[5]
        for i in range(n + 1):
            u = i / n
            prof = math.sin(math.pi * min(1, max(0, u * 0.94 + 0.03))) ** 0.6
            if broke and math.fmod(i * 0.618034 + 0.2, 1.0) < 0.5:
                continue
            cw = max(1, round(w * prof))
            qx = a[0] + dv[0] * i * PX - nv[0] * (cw // 2) * PX
            qy = a[1] + dv[1] * i * PX - TX_H - nv[1] * (cw // 2) * PX
            for k in range(cw):
                cell(px, qx + nv[0] * k * PX, qy + nv[1] * k * PX, core)
            if prof > 0.25:
                cell(px, qx - nv[0] * PX, qy - nv[1] * PX, side)
                cell(px, qx + nv[0] * cw * PX, qy + nv[1] * cw * PX, side)
            if hot and prof > 0.2:
                glow(gl, qx, qy, (1.0, 0.88, 0.66), 1.0)
            elif i % 2 == 0 and prof > 0.4 and not broke:
                glow(gl, qx, qy, (0.8, 0.6, 0.4), 0.6)
        return
    # style 2（_tx_draw_line）
    if f > hold + 1:
        return
    broke = f >= hold
    for i in range(n + 1):
        u = i / n
        prof = math.sin(math.pi * min(1, max(0, u * 0.92 + 0.04))) ** 0.5
        if broke and math.fmod(i * 0.618034 + f * 0.31, 1.0) < (0.45 if f == hold else 0.75):
            continue
        qx = a[0] + dv[0] * i * PX
        qy = a[1] + dv[1] * i * PX - TX_H
        cw = w if prof > 0.55 else 1
        core = TX_C[7] if f == 0 else (TX_C[6] if not broke else TX_C[5])
        side = TX_C[5] if f == 0 else (TX_C[4] if not broke else TX_C[3])
        for k in range(cw):
            cell(px, qx + nv[0] * k * PX, qy + nv[1] * k * PX, core)
        if prof > 0.3:
            cell(px, qx - nv[0] * PX, qy - nv[1] * PX, side)
            cell(px, qx + nv[0] * cw * PX, qy + nv[1] * cw * PX, side)
            if prof > 0.7 and f <= 1:
                cell(px, qx + nv[0] * (cw + 1) * PX, qy + nv[1] * (cw + 1) * PX, TX_C[3])
        if f == 0 and i % 2 == 0 and prof > 0.4:
            glow(gl, qx, qy, (1.0, 0.85, 0.6), 0.8)


def pos_mark(px, t):
    cx = math.floor(O[0] / 2) * 2
    cy = math.floor(O[1] / 2) * 2 + 2
    br = 0.42 + 0.12 * math.sin(int(t * 15) * 0.7)
    for y in range(-3, 4):
        hw = 6 - 2 * abs(y)
        for x in range(-hw, hw + 1):
            onedge = abs(x) == hw or (abs(x) == hw - 1 and abs(y) == 3)
            if onedge:
                cell(px, cx + x * 2, cy + y * 2, (255, 184, 92), br)
            else:
                cell(px, cx + x * 2, cy + y * 2, (31, 20, 13), br * 0.7)


def tint(im, col, al):
    a = np.asarray(im).astype(float).copy()
    a[..., 0] *= col[0]
    a[..., 1] *= col[1]
    a[..., 2] *= col[2]
    a[..., 3] *= al
    return Image.fromarray(a.clip(0, 255).astype(np.uint8))


def put(img, spr, p, flip=False, al=1.0, col=(1, 1, 1)):
    s = spr.transpose(Image.FLIP_LEFT_RIGHT) if flip else spr
    if al < 1.0 or col != (1, 1, 1):
        s = tint(s, col, al)
    img.alpha_composite(s, (int(p[0] - s.width // 2), int(p[1] - s.height + 34)))


def scene(t, new, cuts, A, bg):
    img = bg.copy()
    px = np.asarray(img).astype(float)
    gl = np.zeros((H, W, 3))
    lamps = []
    hide = new and S3[0] <= t < S3[1]
    # 敌人（命中后 0.06 秒白闪）
    for e in ENEMIES:
        hit = any(0 <= t - c["t"] < 0.08 and c["e"] == e for c in cuts)
        put_e = A["en"][int(t * 6) % 4]
        if hit:
            put_e = tint(put_e, (3, 3, 3), 1.0)
        img2 = Image.fromarray(px.clip(0, 255).astype(np.uint8))
        ImageDraw.Draw(img2).ellipse([e[0] - 11, e[1] - 3, e[0] + 11, e[1] + 4], fill=(16, 20, 22, 255))
        img2.alpha_composite(put_e, (e[0] - put_e.width // 2, e[1] - put_e.height + 6))
        px = np.asarray(img2).astype(float)
    if hide:
        pos_mark(px, t)
    img = Image.fromarray(px.clip(0, 255).astype(np.uint8))
    # 本体
    rnd_active = [r for r in ROUNDS if r[0] <= t <= r[-1] + POSE + 0.04]
    flash = [c for c in cuts if 0 <= t - c["t"] < POSE or (hide and 0 <= t - c["t"] < POSE)]
    if flash:
        c = flash[-1]
        k = min(1.0, max(0.0, (1 - (t - c["t"]) / POSE) / 0.3))
        put(img, A["atk"][4], c["p1"], c["p1"][0] < c["p0"][0], 0.35 + 0.65 * k)
    elif not rnd_active:
        if not new or t < S3[0]:
            put(img, A["run"][int(t * 12) % 8], O)
        elif t >= S3[1]:
            k = min(1.0, (t - S3[1]) / 0.18)
            put(img, A["run"][int(t * 12) % 8], O, False, max(0.15, k))
    # 瞬移残影
    trails = [(c["from"], c["p1"], c["t"]) for c in cuts]
    for r in ROUNDS:
        lastc = [c for c in cuts if c["t"] == r[-1]][0]
        if not new:
            trails.append((lastc["p1"], O, r[-1] + POSE + 0.04))
    if new:
        trails.append(([c for c in cuts][-1]["p1"], O, S3[1]))
    for a, b, t0 in trails:
        age = t - t0
        if 0 <= age < 0.26 and math.dist(a, b) >= 8:
            fade = 1 - age / 0.26
            for i in range(4):
                u = (i + 1) / 5
                put(img, A["atk"][4], (round(a[0] + (b[0] - a[0]) * u), round(a[1] + (b[1] - a[1]) * u)), b[0] < a[0], fade * (0.18 + 0.32 * u), (0.55, 0.72, 1.0))
    px = np.asarray(img).astype(float)
    # 落剑（旧）
    if not new:
        for c in cuts:
            f = int(math.floor((t - c["t"]) * 15))
            if 0 <= f < A["sw_m"]["n"]:
                gd = A["swg"][f]
                up = A["sw"][f]
                if c["fl"]:
                    gd, up = gd.transpose(Image.FLIP_LEFT_RIGHT), up.transpose(Image.FLIP_LEFT_RIGHT)
                im = Image.fromarray(px.clip(0, 255).astype(np.uint8))
                m1, m2 = A["swg_m"], A["sw_m"]
                im.alpha_composite(gd, (int(c["e"][0] - (gd.width - m1["ox"] * 2 if c["fl"] else m1["ox"] * 2)), int(c["e"][1] - m1["oy"] * 2)))
                im.alpha_composite(up, (int(c["e"][0] - (up.width - m2["ox"] * 2 if c["fl"] else m2["ox"] * 2)), int(c["e"][1] - m2["oy"] * 2)))
                px = np.asarray(im).astype(float)
    # 刀痕
    for c in cuts:
        for it in c["lines"]:
            f = int(math.floor(t * 15) - math.floor(it["t0"] * 15))
            if f >= 0:
                draw_line(px, gl, it, f)
        if new and 0 <= t - c["t"] < 2 / 15:
            lamps.append((c["e"][0], c["e"][1] - TX_H, 200, 0.9))
        elif not new and 0 <= t - c["t"] < 0.1:
            lamps.append((c["e"][0], c["e"][1] - 20, 130, 0.45))
    # 火星 / 碎屑
    for c in cuts:
        age = t - c["t"]
        for s in c["sparks"]:
            vx, vy, life, hot = s[:4]
            base = s[4] if len(s) > 4 else (c["e"][0], c["e"][1] - 20)
            if 0 <= age < life:
                x = base[0] + vx * age
                y = base[1] + vy * age + 260 * age * age
                k = age / life
                col = TX_C[7] if (hot and k < 0.4) else (TX_C[6] if k < 0.6 else TX_C[5])
                cell(px, x, y, col)
                if hot and k < 0.5:
                    glow(gl, x, y, (1.0, 0.8, 0.5), 0.5)
    # 照地光（加色、压扁椭圆）
    yy, xx = np.mgrid[0:H, 0:W]
    for lx, ly, lr, li in lamps:
        d = np.sqrt(((xx - lx) / lr) ** 2 + ((yy - ly - TX_H) / (lr * 0.6)) ** 2)
        k = np.clip(1 - d, 0, 1) ** 2 * li * 70
        px[..., 0] += k * 1.0
        px[..., 1] += k * 0.62
        px[..., 2] += k * 0.28
    # 辉光
    if gl.any():
        g8 = Image.fromarray((np.clip(gl, 0, 1) * 255).astype(np.uint8))
        b1 = np.asarray(g8.filter(ImageFilter.GaussianBlur(3))).astype(float)
        b2 = np.asarray(g8.filter(ImageFilter.GaussianBlur(8))).astype(float)
        px[..., :3] += b1[..., :3] * 2.2 + b2[..., :3] * 3.0
    return Image.fromarray(px.clip(0, 255).astype(np.uint8)).convert("RGB")


def background():
    rng = np.random.default_rng(3)
    a = np.zeros((H, W, 4), dtype=np.uint8)
    a[..., 0], a[..., 1], a[..., 2], a[..., 3] = 34, 44, 50, 255
    n = rng.integers(0, 6, (H // 2, W // 2))
    a[..., :3] = a[..., :3] + np.repeat(np.repeat(n, 2, 0), 2, 1)[..., None].astype(np.uint8)
    return Image.fromarray(a)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join(MAIN, "Claude outputs", "texas_s3_slash_1106"))
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    od = os.path.join(ROOT, "game", "art", "operators", "texas")
    sw, swm = strip("tx_sw_s26_e2_l0_up")
    swg, swgm = strip("tx_sw_s26_e2_gd")
    A = {"atk": sheet(os.path.join(od, "op_texas_s3_dash@2x.png"), 8), "run": sheet(os.path.join(od, "op_texas_run@2x.png"), 8),
         "en": sheet(os.path.join(ROOT, "game", "art", "enemies", "offspring", "e_offspring@2x.png"), 4), "sw": sw, "sw_m": swm, "swg": swg, "swg_m": swgm}
    bg = background()
    old, new = build_cuts(False), build_cuts(True)
    font = ImageFont.truetype(FONT, 13)
    frames = []
    for i in range(int(T_END * FPS)):
        t = i / FPS
        L = scene(t, False, old, A, bg)
        R = scene(t, True, new, A, bg)
        sh = Image.new("RGB", (W * 2 + 6, H + 40), (12, 12, 16))
        sh.paste(L, (0, 40))
        sh.paste(R, (W + 6, 40))
        d = ImageDraw.Draw(sh)
        d.text((6, 3), "旧：每刀几道细斩线 + 落剑；两轮之间原地冒出本体", fill=(230, 230, 230), font=font)
        d.text((W + 12, 3), "新：一刀一道（细、亮）；原地只留脚下小菱形", fill=(255, 220, 160), font=font)
        d.text((6, 21), "%.2f 秒（原速 30 fps，示意：Python 照搬画法，非实机）" % t, fill=(150, 150, 150), font=font)
        frames.append(sh)
    for sc in (1, 2):
        fr = frames if sc == 1 else [f.resize((f.width * 2, f.height * 2), Image.NEAREST) for f in frames]
        pal = fr[int(0.3 * FPS)].quantize(colors=220, method=Image.MEDIANCUT)
        q = [f.quantize(palette=pal, dither=Image.NONE) for f in fr]
        path = os.path.join(a.out, "texas_s3_slash_%dx.gif" % sc)
        q[0].save(path, save_all=True, append_images=q[1:], duration=int(1000 / FPS), loop=0, disposal=1)
        print(path, len(q), "帧", "%.0f KB" % (os.path.getsize(path) / 1024))


if __name__ == "__main__":
    main()
