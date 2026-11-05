#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""德克萨斯终结技 Q 转平面画面（docs/257 §8，ult/px_plane）送审 GIF：只用 Python、不开 Godot。
画法读 tools/ult_px_texas_art.py。时间轴照游戏（ult_moves._tx_*，游戏时间）：
超必杀暂停 0.33 秒 → 起手慢放 0.53 秒 → 0–0.5 秒刀网一道道显现、她沿每道斩线闪身划过 → 0.6 秒落到圆心 →
0.75 秒斩线齐出：冲击帧两拍（白底黑剪影 / 黑底白剪影）→ 预备 2 拍（光点往中心收、圈内压暗）→ 最大那一下：亮核 2 拍 + 满亮灯 + 轻震 3px，
慢动作 0.53 秒（0.3 倍速）+ 0.2 秒缓回，冲击环 3.5 拍推到判定边缘，被斩的怪按冲击环到达时刻崩解成自身颜色的像素 → 斩线淡掉 → 收刀冲回原位。
输出（15 fps）：ult_texas_1x.gif（1 倍整屏）、ult_texas_x2.gif（中心 2 倍）、new_frames/（逐帧 PNG，给并排对照用）、timeline.json（每帧的阶段 / 真实秒数，配音效清单用）。
用法：python tools/ult_px_texas_gif.py [--out 目录]
"""
import argparse, json, math, os, sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ult_px_texas_art as A

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAIN = os.path.dirname(os.path.dirname(os.path.dirname(ROOT))) if ".claude" in ROOT else ROOT
PX = 2
W, H = 1400, 900
C = (700, 470)
HOME = (C[0] - 300, C[1] + 110)
GROUND = (34, 44, 50)
FONT = "C:/Windows/Fonts/msyh.ttc"
R_W = 605.0          # ult/tx_r（世界像素）
R = R_W / 2          # 美术像素
T_CUT = 0.75
AMBER_L = (1.0, 0.62, 0.25)


def hx(s):
    s = s.lstrip("#")
    return tuple(int(s[i:i + 2], 16) for i in (0, 2, 4))


def snap(v):
    return (round(v[0] / 2) * 2, round(v[1] / 2) * 2)


def sprite(path, n, fi=0):
    im = Image.open(path).convert("RGBA")
    fw = im.width // n
    return im.crop((fi * fw, 0, (fi + 1) * fw, im.height))


# ---------------------------------------------------------------- 时间轴
SF, WU = 5, 8


def timeline():
    """[(阶段, 招式游戏时间, 冲击帧拍 0/1/-1, 真实秒)]"""
    out = []
    rt = 0.0
    def add(ph, t, hfk):
        nonlocal rt
        out.append((ph, t, hfk, rt))
        rt += 1 / 15
    for i in range(SF):
        add("sf", 0.0, -1)
    for i in range(WU):
        add("wu", (i + 1) / WU, -1)
    t = 0.0
    while t < T_CUT - 1e-6:
        add("cast", t, -1)
        t += 1 / 15
    t = T_CUT
    add("cast", t, 0)
    add("cast", t, 1)
    for i in range(2):                     # 预备 2 拍（原速）
        t += 1 / 15
        add("cast", t, -1)
    for i in range(8):                     # 慢动作：亮核起 0.53 秒、0.3 倍速
        t += 0.3 / 15
        add("cast", t, -1)
    for k in (0.5, 0.75):                  # 缓回 0.13 秒
        t += k / 15
        add("cast", t, -1)
    while t < T_CUT + 1.6:
        t += 1 / 15
        add("cast", t, -1)
    return out


# ---------------------------------------------------------------- 场景（世界坐标）
def lines():
    n = 6
    base = 0.0 + 0.35
    out = []
    for i in range(n):
        ang = base + math.pi * i / n + 0.12 * ((i * 5) % 3 - 1)
        d = (math.cos(ang), math.sin(ang))
        off = (((i * 37) % 9) - 4.0) / 4.0 * R_W * 0.4
        ln = 2.0 * math.sqrt(max(0.0, R_W * R_W - off * off)) * 0.98
        mid = (C[0] - d[1] * off, C[1] + d[0] * off)
        out.append(((mid[0] - d[0] * ln / 2, mid[1] - d[1] * ln / 2), (mid[0] + d[0] * ln / 2, mid[1] + d[1] * ln / 2)))
    return out


LINES = lines()
N = len(LINES)


def dashes():
    out = []
    pos = HOME
    for i, (p0, p1) in enumerate(LINES):
        near0 = math.dist(pos, p0) <= math.dist(pos, p1)
        a, b = (p0, p1) if near0 else (p1, p0)
        out.append({"t": i * 0.5 / N, "a": a, "b": b, "from": pos})
        pos = b
    out.append({"t": 0.6, "a": pos, "b": C, "from": pos})
    return out


DASH = dashes()
T_RET = T_CUT + A.HOLD + 0.3 - 0.12


def her_pos(t):
    p = HOME
    for d in DASH:
        if t >= d["t"]:
            p = d["b"]
    if t >= T_RET:
        p = HOME
    return p


def enemies():
    out = []
    for i in range(30):
        a = i * 2.39996 + 0.7
        r = 90 + 560 * ((i * 0.618) % 1.0)
        out.append((C[0] + math.cos(a) * r, C[1] + math.sin(a) * r * 0.7))
    return out


ENS = enemies()
HIT = [i for i, e in enumerate(ENS) if math.dist(e, C) <= R_W]


# ---------------------------------------------------------------- 绘制
def render(tk, ph, t, hfk):
    img = Image.new("RGBA", (W, H), GROUND + (255,))
    rng = np.random.default_rng(7)
    g = np.asarray(img).copy()
    nz = rng.integers(-5, 6, size=(H // 2, W // 2, 1))
    g[..., :3] = np.clip(g[..., :3].astype(int) + np.repeat(np.repeat(nz, 2, 0), 2, 1), 0, 255)
    img = Image.fromarray(g.astype(np.uint8), "RGBA")
    emit = Image.new("RGB", (W, H), (0, 0, 0))
    ed = ImageDraw.Draw(emit)
    dr = ImageDraw.Draw(img)

    def put(x, y, c, glow=False, a=1.0, sz=1):
        x, y = snap((x, y))
        if not (0 <= x < W - 2 and 0 <= y < H - 2):
            return
        if isinstance(c, str):
            cc = hx(c)
        elif isinstance(c[0], float):
            cc = tuple(int(v * 255) for v in c[:3])
            a = a * (c[3] if len(c) > 3 else 1.0)
        else:
            cc = c[:3]
        if a < 1.0:
            base = img.getpixel((x, y))
            cc = tuple(int(base[i] * (1 - a) + cc[i] * a) for i in range(3))
        dr.rectangle([x, y, x + PX * sz - 1, y + PX * sz - 1], fill=tuple(cc) + (255,))
        if glow:
            ed.rectangle([x, y, x + PX * sz - 1, y + PX * sz - 1], fill=tuple(cc))

    def pts(o, lst):
        for q in lst:
            sz = int(q[4]) if len(q) > 4 else 1
            if isinstance(q[3], bool):
                put(o[0] + q[0] * PX, o[1] + q[1] * PX, q[2], glow=q[3], sz=sz)
            else:
                put(o[0] + q[0] * PX, o[1] + q[1] * PX, q[2], a=q[3], sz=sz)

    def rel(a, b):
        return ((b[0] - a[0]) / PX, (b[1] - a[1]) / PX)

    if hfk >= 0:   # 冲击帧（保留）：整屏底 + 剪影 = 6 道主斩线
        bg = (235, 230, 220) if hfk == 0 else (5, 5, 8)
        fg = "#000000" if hfk == 0 else "#ffffff"
        im2 = Image.new("RGB", (W, H), bg)
        d2 = ImageDraw.Draw(im2)
        for (p0, p1) in LINES:
            for q in A.cut_blade(rel(p0, p1), 0.0, sil=True):
                x, y = snap((p0[0] + q[0] * PX, p0[1] + q[1] * PX))
                d2.rectangle([x, y, x + 1, y + 1], fill=fg)
        hp = C
        d2.rectangle([hp[0] - 10, hp[1] - 56, hp[0] + 10, hp[1]], fill=fg)
        return im2

    ct = t if ph == "cast" else -1.0
    age = ct - T_CUT if ct >= T_CUT else -1.0
    lights = []
    # ---- 地面层：焦痕
    if age >= 0:
        for (p0, p1) in LINES:
            pts(p0, A.ground_scar(rel(p0, p1), age))
    # 预备压暗
    if 0 <= age < A.BLAST_T + 0.2:
        kd = min(1.0, age / A.BLAST_T) * (1.0 if age < A.BLAST_T else max(0.0, 1 - (age - A.BLAST_T) / 0.2))
        if kd > 0:
            ov = Image.new("RGBA", (W, H), (0, 0, 0, 0))
            ImageDraw.Draw(ov).ellipse([C[0] - R_W * 1.02, C[1] - R_W * 1.02 * A.SQ, C[0] + R_W * 1.02, C[1] + R_W * 1.02 * A.SQ], fill=(0, 0, 5, int(255 * 0.3 * kd)))
            img.alpha_composite(ov)
            dr = ImageDraw.Draw(img)
    # ---- 怪物（崩解：冲击环推到它的那一拍起整只炸开，之后不再画）
    for i, e in enumerate(ENS):
        broke = i in HIT and age >= 0 and age >= A.shock_at(R, math.dist(e, C) / PX)
        if broke:
            continue
        dr.ellipse([e[0] - 10, e[1] + 1, e[0] + 10, e[1] + 7], fill=(16, 20, 22, 255))
        img.alpha_composite(ENEMY, dest=(int(e[0] - ENEMY.width // 2), int(e[1] - ENEMY.height + 6)))
    dr = ImageDraw.Draw(img)
    hp = her_pos(ct) if ct >= 0 else HOME
    spr = OPS["attack"] if (ct >= 0 and any(0 <= ct - d["t"] < 0.2 for d in DASH)) else OPS["idle"]
    img.alpha_composite(spr, dest=snap((hp[0] - spr.width // 2, hp[1] - spr.height + 8)))
    dr = ImageDraw.Draw(img)
    if ph == "wu":
        pts(HOME, A.windup(t, tk))
    if ct >= 0:
        for i, (p0, p1) in enumerate(LINES):   # 刀网发丝线（显现到斩开）
            ti = i * 0.5 / N
            if ti <= ct < T_CUT:
                pts(p0, A.hairline(rel(p0, p1), ct - ti, T_CUT - ti))
        for j, d in enumerate(DASH):   # 闪身身影线 + 起步那一小团粒子云（代替原来的尘团）
            f = int(math.floor((ct - d["t"]) * 15))
            a0, b0 = d["a"], d["b"]
            L = math.dist(a0, b0) or 1
            dv = ((b0[0] - a0[0]) / L, (b0[1] - a0[1]) / L)
            sa = (a0[0] - dv[0] * 20, a0[1] - dv[1] * 20 - 24)
            sb = (b0[0] + dv[0] * 20, b0[1] + dv[1] * 20 - 24)
            pts(sa, A.dashline(rel(sa, sb), f))
            pts((a0[0], a0[1] - 6), A.cloud(ct - d["t"], 40 + j, 16, 24))
            if 0 <= ct - d["t"] < 0.1:
                lights.append((b0[0], b0[1] - 20, 110, 0.35, AMBER_L))
        if age >= 0:   # 主斩线 + 沿刀痕的粒子云（代替原来的拖影带和烟尘团）
            for i, (p0, p1) in enumerate(LINES):
                pts(p0, A.cut_blade(rel(p0, p1), age))
                for k in range(3):
                    hk = A.hf(i, k, 5)
                    p = (p0[0] + (p1[0] - p0[0]) * (0.2 + 0.3 * k + 0.12 * (hk - 0.5)), p0[1] + (p1[1] - p0[1]) * (0.2 + 0.3 * k + 0.12 * (hk - 0.5)))
                    pts((p[0], p[1] - 16), A.cloud(age - 0.03 * k, 300 + i * 3 + k, 36 + 14 * hk, 50))
            # 最大那一下
            pts(C, A.blast_prep(R, age))
            if age >= A.BLAST_T:
                tau = age - A.BLAST_T
                pts(C, A.blast_core(R, int(math.floor(tau * 15))))
                if tau < 2 / 15:
                    lights.append((C[0], C[1], 240, 0.85, (1.0, 0.75, 0.45)))   # docs/270 爆发档上限：半径 240、强度 0.85
                pts(C, A.shock_ring(R, tau))
                pts((C[0], C[1] - 12), A.cloud(tau, 777, R * 0.6, 160))
            # 崩解：被斩的怪在冲击环推到它时整只炸开（贴图像素碎开 + 本色喷散）
            for i in HIT:
                e = ENS[i]
                ta = A.shock_at(R, math.dist(e, C) / PX)
                ea = age - ta
                if ea < 0 or ea > 1.3:
                    continue
                ang = math.atan2((e[1] - C[1]) / A.SQ, e[0] - C[0])
                for (bx, by, col) in EPIX:   # 引擎 kill_burst 的样子：按贴图像素（美术像素块）往外炸开、受重力、淡掉
                    k = A.hf(bx, by, i)
                    k2 = A.hf(by, bx, i + 7)
                    sp = 30 + 150 * k2
                    da = (k - 0.5) * 2.6
                    vx, vy = math.cos(ang + da) * sp, math.sin(ang + da) * sp * A.SQ - 40 - 90 * A.hf(bx, i, by)
                    x = e[0] + bx + vx * ea
                    y = e[1] + by + vy * ea + 220 * ea * ea
                    if ea > 0.7 and A.hf(bx, by, 9) < (ea - 0.7) / 0.6:
                        continue
                    put(x, y, col, a=1.0 if ea < 0.8 else max(0.0, (1.3 - ea) / 0.5))
                pts((e[0], e[1] - 14), A.spray(ea, i, ang, 1.4, ECOL))
        if T_RET <= ct < T_RET + 0.27:   # 收刀冲回原位
            f = int(math.floor((ct - T_RET) * 15))
            sa, sb = (C[0], C[1] - 24), (HOME[0], HOME[1] - 24)
            pts(sa, A.dashline(rel(sa, sb), f))
            pts((C[0], C[1] - 6), A.cloud(ct - T_RET, 91, 16, 24))
    # ---- 光照
    if 0 <= age < 0.12:
        lights.append((C[0], C[1], 320, 0.7 * (1 - age / 0.12), AMBER_L))
    if ph == "wu":
        lights.append((HOME[0] + 6, HOME[1] - 40, 90, 0.4 * t, AMBER_L))
    glow = np.asarray(emit.filter(ImageFilter.GaussianBlur(3))).astype(np.float32) * 0.45
    base = np.asarray(img.convert("RGB")).astype(np.float32) * 0.8
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    lit = np.zeros((H, W, 3), np.float32)
    for (lx, ly, lr, li, lc) in lights:
        dd = np.sqrt((xx - lx) ** 2 + ((yy - ly) / 0.72) ** 2) / lr
        lit += (li * np.clip(1.0 - dd, 0.0, 1.0) ** 2)[..., None] * np.array(lc, np.float32)
    base = base * (1.0 + lit * 1.3) + lit * 40.0
    out = np.clip(base + glow, 0, 255)
    if ph == "sf":   # 超必杀暂停：压暗到约 35%，她不压暗（共用演出，没改）
        k = np.full((H, W, 1), 0.35, np.float32)
        y0, x0 = int(HOME[1] - 120), int(HOME[0] - 64)
        k[max(0, y0):y0 + 128, max(0, x0):x0 + 128] = 1.0
        out = out * k
    if ph == "wu":
        out = out * 0.75
    im = Image.fromarray(out.astype(np.uint8), "RGB")
    if age >= A.BLAST_T and age - A.BLAST_T < 0.12:   # 轻震 3px / 0.12 秒
        sx = 3 if int((age - A.BLAST_T) * 50) % 2 == 0 else -3
        im = Image.fromarray(np.roll(np.asarray(im), sx, axis=1))
    return im


def phase_name(ph, t, hfk):
    if ph == "sf":
        return "起手（超必杀暂停，共用演出）"
    if ph == "wu":
        return "蓄力（起手慢放）"
    if hfk >= 0:
        return "冲击帧（保留）"
    if t < 0.5:
        return "刀网显现 · 沿斩线闪身"
    if t < T_CUT:
        return "落到圆心"
    a = t - T_CUT
    if a < A.BLAST_T:
        return "预备：往中心收、压暗"
    if a < A.BLAST_T + 0.2:
        return "最大那一下：亮核 + 冲击环 + 崩解（慢动作）"
    if t < T_RET:
        return "崩解 · 斩线淡去"
    return "收刀冲回原位"


def main():
    global ENEMY, OPS, EPIX, ECOL
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join(MAIN, "Claude outputs", "ult_px_texas_1105"))
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    fdir = os.path.join(a.out, "new_frames")
    os.makedirs(fdir, exist_ok=True)
    en = sprite(os.path.join(ROOT, "game", "art", "enemies", "offspring", "e_offspring@2x.png"), 4)
    arr = np.asarray(en).astype(np.float32)
    arr[..., :3] = arr[..., :3] * 0.5 + np.array([8, 10, 12])
    ENEMY = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")
    ea = np.asarray(ENEMY)
    ys, xs = np.nonzero(ea[..., 3] > 128)
    EPIX = [(int(x) - ENEMY.width // 2, int(y) - ENEMY.height + 6, tuple(int(v) for v in ea[y, x, :3])) for y, x in zip(ys, xs) if x % 2 == 0 and y % 2 == 0 and (x * 7 + y * 3) % 4 == 0]
    m = ea[..., 3] > 128
    ECOL = tuple(float(v) / 255 for v in ea[m][:, :3].mean(axis=0) * 1.25)
    ECOL = tuple(min(1.0, v) for v in ECOL)
    od = os.path.join(ROOT, "game", "art", "operators", "texas")
    OPS = {"idle": sprite(os.path.join(od, "op_texas_idle@2x.png"), 7), "attack": sprite(os.path.join(od, "op_texas_attack@2x.png"), 8, 3)}
    font = ImageFont.truetype(FONT, 18)
    tl = timeline()
    big, small, meta = [], [], []
    for tk, (ph, t, hfk, rt) in enumerate(tl):
        im = render(tk, ph, t, hfk)
        lab = phase_name(ph, t, hfk)
        im.save(os.path.join(fdir, "f%03d.png" % tk))
        meta.append({"i": tk, "ph": ph, "t": round(t, 4), "hf": hfk, "real": round(rt, 4), "label": lab})
        sheet = im.copy()
        d = ImageDraw.Draw(sheet)
        d.text((10, 8), "德克萨斯终结技 · 转平面版 · 1 倍 · 15 fps 原速 · " + lab, fill=(235, 225, 200) if hfk != 0 else (20, 20, 20), font=font)
        big.append(sheet)
        cx, cy = C
        small.append(im.crop((cx - 320, cy - 220, cx + 320, cy + 220)).resize((1280, 880), Image.NEAREST))
    json.dump(meta, open(os.path.join(a.out, "timeline.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=0)
    for frames, nm in ((big, "ult_texas_1x.gif"), (small, "ult_texas_x2.gif")):
        pick = frames[:: max(1, len(frames) // 12)][:12]
        mos = Image.new("RGB", (frames[0].width, frames[0].height * len(pick)))
        for i, fr in enumerate(pick):
            mos.paste(fr, (0, i * frames[0].height))
        pal = mos.quantize(colors=255, method=Image.MEDIANCUT)
        q = [f.quantize(palette=pal, dither=Image.NONE) for f in frames]
        dur = [70 if i % 3 != 1 else 60 for i in range(len(q))]
        q[0].save(os.path.join(a.out, nm), save_all=True, append_images=q[1:], duration=dur, loop=0, optimize=False, disposal=1)
        print(nm, len(q), "帧", "%.0f KB" % (os.path.getsize(os.path.join(a.out, nm)) / 1024))


if __name__ == "__main__":
    main()
