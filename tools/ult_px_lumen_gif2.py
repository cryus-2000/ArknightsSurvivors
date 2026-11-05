#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""流明终结技 Q「灯塔」送审第二版（ult_brief.md 第 9 条，11-05 晚）：以原版为底，配色对齐普攻 / 技能定稿，只往上叠。只用 Python、不开 Godot。

原版（ult_moves_c._lu_start / _lu_step，v3 暖光）逐件复刻，造型、节奏、体量不动：
  光柱两层光带（外 86 宽 0.45、内 30 宽 0.85）+ 起手刃光（22 宽、0.4 秒）+ 脚下「灯塔点亮」帧条 fx_beacon_ignite + 顶上星芒 fx_lumen_beam_flare；
  t 0.2 光圈炸开：两道扩散环（18 宽 40 → R、0.5 秒；6 宽 R × 0.92、晚 0.05 秒）+ 判定圈铺底（0.2、0.45 秒）+ 12 道放射线（0.22 秒）+ 屏震；
  两道旋转扇形光束（半角 0.07、1 秒一圈、2 秒）；每 0.5 秒一跳：0.75R → R 的圈 + 20 颗方块光点；余辉：0.85R 铺底 + 4 宽圈，熄灭后 2 秒褪掉；后半段光点往上飘。
改的只有：
  ① 配色：暖黄 / 金（LU_WARM #ffb85c、LU_HI #ffeec7）→ 普攻 / 技能定稿的钢蓝 7 阶（house.js OP.lumen），灯火橙 #ff9640 只留在灯芯；两张帧条按亮度映射到钢蓝色阶；
  ② 画法：原版棋盘格半透明（大扩散环、铺底）换成真 alpha；线、点、帧条落在美术像素格上（帧条按整数倍放大、15 fps 换帧）；
  ③ 最大那一下（t 0.2）叠加：[A 版] 冲击帧两拍 → 0.5 秒 0.3 倍慢动作 + 0.15 秒缓回；照地灯打满；被扩散环扫到、被打死的怪炸成自身颜色的像素（崩解）。
左边原版：GCP 实录（Claude outputs/render-ultinv2-integ/lumen_ult.mp4，integ 现行，15 fps 抽帧），按「超必杀暂停起点」和「最大那一下」两处对齐；右边新版是示意场景。
输出：<out>/ult_lumen_v2_A.gif、ult_lumen_v2_B.gif、ult_lumen_v2_side_A.gif（左原版 / 右新版）、ult_lumen_v2_side_B.gif
用法：python tools/ult_px_lumen_gif2.py [--out 目录]
"""
import argparse, math, os, sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ult_px_lumen_gif as G

ROOT, MAIN, PX, W, H, C, SY, R_W, R = G.ROOT, G.MAIN, G.PX, G.W, G.H, G.C, G.SY, G.R_W, G.R
CL, AC, hx, hf, snap, ease_out = G.CL, G.AC, G.hx, G.hf, G.snap, G.ease_out
T_BOOM, T_END = G.T_BOOM, G.T_END
RING_T = 0.5   # 原版扩散环 0.5 秒（判定前沿 0.25 秒，画面环慢一倍；崩解跟着看得见的环）
TEX = {}


def dechecker(a):
    """原版帧条里的棋盘格半透明（@2x 贴图上 2×2 一格交替透明）→ 真 alpha：预乘后取 4×4 邻域均值；
    只替换「和邻域 alpha 差得多」的像素（抖动区），实心区和外轮廓不动"""
    al = a[..., 3:4] / 255.0
    pm = np.concatenate([a[..., :3] * al, al], axis=2)
    k = np.zeros_like(pm)
    for dy in (-2, -1, 0, 1):
        for dx in (-2, -1, 0, 1):
            k += np.roll(np.roll(pm, dy, 0), dx, 1)
    k /= 16.0
    mixed = (k[..., 3] > 0.12) & (k[..., 3] < 0.88)   # 邻域里一半透明一半不透明 = 棋盘格
    out = np.where(mixed[..., None], k, pm)
    aa = np.clip(out[..., 3:4], 1e-6, 1)
    return np.concatenate([out[..., :3] / aa, out[..., 3:4] * 255.0], axis=2)


def recolor(im):
    """暖黄帧条 → 钢蓝色阶：先去棋盘格（真 alpha），再按亮度映射到 CL[2..6]，最亮那档白"""
    a = dechecker(np.asarray(im.convert("RGBA")).astype(np.float32))
    lum = (a[..., 0] * 0.3 + a[..., 1] * 0.55 + a[..., 2] * 0.15) / 255.0
    ramp = np.array([hx(c) for c in CL[2:]], np.float32)
    idx = np.clip((lum * 0.95 - 0.12) * (len(ramp) - 1), 0, len(ramp) - 1)   # 往下压：只有最亮的芯到白，外圈留在冰蓝 / 钢蓝（保留原版的层次）
    lo = np.floor(idx).astype(int)
    hi = np.minimum(lo + 1, len(ramp) - 1)
    f = (idx - lo)[..., None]
    rgb = ramp[lo] * (1 - f) + ramp[hi] * f
    rgb = np.round(rgb / 16) * 16   # 收成色阶，不留渐变糊
    out = np.concatenate([np.clip(rgb, 0, 255), a[..., 3:4]], axis=2)
    return Image.fromarray(out.astype(np.uint8), "RGBA")


def strip_frames(name, n):
    im = Image.open(os.path.join(ROOT, "game", "art", "fx", name + "@2x.png")).convert("RGBA")
    fw = im.width // n
    return [recolor(im.crop((i * fw, 0, (i + 1) * fw, im.height))) for i in range(n)]


def ring_at(tau):
    return 40.0 + (R_W - 40.0) * ease_out(tau / RING_T)


def hit_tau2(d):
    if d <= 40:
        return 0.0
    u = min(1.0, (d - 40.0) / (R_W - 40.0))
    return RING_T * (1 - (1 - u) ** (1 / 3))


def render(rt, ph, t, hfk):
    img = Image.new("RGBA", (W, H), G.GROUND + (255,))
    g = np.asarray(img).copy()
    nz = np.random.default_rng(7).integers(-5, 6, size=(H // 2, W // 2, 1))
    g[..., :3] = np.clip(g[..., :3].astype(int) + np.repeat(np.repeat(nz, 2, 0), 2, 1), 0, 255)
    img = Image.fromarray(g.astype(np.uint8), "RGBA")
    emit = Image.new("RGB", (W, H), (0, 0, 0))
    ed = ImageDraw.Draw(emit)
    tau = t - T_BOOM if ph == "cast" else -1.0
    sh = (0, 0)
    if 0 <= tau < 0.12:
        sh = (int(3 * math.sin(tau * 160)), int(3 * math.cos(tau * 210)))
    o = (C[0] + sh[0], C[1] + sh[1])
    lum = G.SPR["lumen"]

    if hfk >= 0:   # A 版冲击帧：剪影 = 光柱 + 点亮太阳 + 扩散环起点 + 流明
        bg = (235, 230, 220) if hfk == 0 else (5, 5, 8)
        fg = (0, 0, 0) if hfk == 0 else (255, 255, 255)
        im2 = Image.new("RGB", (W, H), bg)
        d2 = ImageDraw.Draw(im2)
        d2.rectangle([C[0] - 43, 0, C[0] + 43, C[1] + 10], fill=fg)
        sun = TEX["ignite"][3]
        m = Image.new("RGB", (sun.width * 2, sun.height * 2), fg)
        im2.paste(m, snap((C[0] - sun.width, C[1] - sun.height)), sun.resize((sun.width * 2, sun.height * 2), Image.NEAREST).split()[3])
        rr = ring_at(0.0)
        d2.ellipse([C[0] - rr - 9, C[1] - (rr + 9) * SY, C[0] + rr + 9, C[1] + (rr + 9) * SY], outline=fg, width=18)
        mm = Image.new("RGB", lum.size, fg)
        im2.paste(mm, snap((C[0] - lum.width // 2, C[1] - lum.height + 8)), lum.split()[3])
        return im2

    ov = Image.new("RGBA", (W, H), (0, 0, 0, 0))   # 真 alpha 的面（铺底、扇形、光带）
    od = ImageDraw.Draw(ov)

    def ell(r, col, a):
        od.ellipse([o[0] - r, o[1] - r * SY, o[0] + r, o[1] + r * SY], fill=hx(col) + (int(255 * a),))

    def ring_line(r, w, col, a):
        if a <= 0 or r <= 1:
            return
        od.ellipse([o[0] - r - w / 2, o[1] - (r + w / 2) * SY, o[0] + r + w / 2, o[1] + (r + w / 2) * SY], outline=hx(col) + (int(255 * a),), width=max(2, int(round(w / 2)) * 2))

    lights = []
    if ph == "cast":
        # ---- 地面层：判定圈铺底（原版 0.2、0.45 秒；棋盘格 → 真 alpha）
        if 0 <= tau < 0.45:
            ell(R_W, CL[4], 0.2 * (1 - tau / 0.45))
        # 余辉铺底 + 圈（随光柱慢慢亮，熄灭后 2 秒褪）
        kg = min(1.0, max(0.0, (t - T_BOOM) / 2.0)) ** 2 * (3 - 2 * min(1.0, max(0.0, (t - T_BOOM) / 2.0)))
        if t >= T_END:
            kg = max(0.0, 1 - (t - T_END) / 2.0)
        if t >= T_BOOM:
            ell(R_W * 0.85, CL[4], 0.12 * kg)
            ring_line(R_W * 0.85, 4, CL[5], 0.55 * kg)
        # 扇形光束（原版半角 0.07、填 0.22×fade + 0.05；1 秒一圈）
        el = t - T_BOOM
        if 0 <= el <= 2.0:
            fade = 1 - el / 2.0
            for s in (0, 1):
                ba = el * math.tau + math.pi * s
                pts = [(o[0], o[1])]
                for k in range(9):
                    an = ba - 0.07 + 0.14 * k / 8
                    pts.append((o[0] + math.cos(an) * R_W, o[1] + math.sin(an) * R_W * SY))
                od.polygon(pts, fill=hx(CL[5]) + (int(255 * (0.22 * fade + 0.05)),))
                for an in (ba - 0.07, ba + 0.07):   # 边一格亮线（像素格）
                    for k in range(0, int(R), 1):
                        q = (o[0] + math.cos(an) * k * PX, o[1] + math.sin(an) * k * PX * SY)
                        if k % 2 == 0:
                            G_put(img, ed, q, CL[4] if k > R * 0.4 else CL[5], False)
        # 每 0.5 秒一跳：0.75R → R 的圈（0.3 秒）+ 20 颗方块光点（0.35 秒）
        for k in range(4):
            tk = T_BOOM + 0.5 * (k + 1)
            age = t - tk
            if 0 <= age < 0.35:
                if age < 0.3:
                    ring_line(R_W * (0.75 + 0.25 * age / 0.3), 5, CL[5], 0.8 * (1 - age / 0.3))
                for j in range(20):
                    an = j * math.tau / 20 + k * 0.4
                    q = (o[0] + math.cos(an) * R_W * 0.9, o[1] + math.sin(an) * R_W * 0.9 * SY - age * 20)
                    if (int(age * 15) + j) % 3 != 2:
                        for dx in (0, 2):
                            for dy in (0, 2):
                                G_put(img, ed, (q[0] + dx, q[1] + dy), CL[6] if age < 0.1 else CL[5], True)
    img.alpha_composite(ov)
    ov = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    od = ImageDraw.Draw(ov)
    dr = ImageDraw.Draw(img)
    for e in G.ENS:   # 影子
        dr.ellipse([e["p"][0] - 10, e["p"][1] + 1, e["p"][0] + 10, e["p"][1] + 7], fill=(16, 20, 24, 255))
    for e in G.ENS:
        age = tau - hit_tau2(e["d"]) if tau >= 0 else -1
        if e["die"] and age >= 0:
            continue
        im = G.SPR[e["k"][0]]["img"]
        if 0 <= age < 2 / 15 and e["d"] <= R_W:
            arr = np.asarray(im).copy()
            arr[..., :3] = np.clip(arr[..., :3].astype(int) + 140, 0, 255)
            im = Image.fromarray(arr, "RGBA")
        img.alpha_composite(im, dest=snap((e["p"][0] - im.width // 2, e["p"][1] - im.height + 6)))
    img.alpha_composite(lum, dest=snap((C[0] - lum.width // 2, C[1] - lum.height + 8)))
    if ph == "cast":
        # ---- 光柱（原版两层光带 dur + 0.3 / + 0.25 秒；起手刃光 0.4 秒）
        pa = 1.0 if t < 2.3 else max(0.0, 1 - (t - 2.3) / 0.25)
        if pa > 0:
            od.rectangle([o[0] - 43, 0, o[0] + 43, o[1] + 10], fill=hx(CL[4]) + (int(255 * 0.45 * pa),))
            od.rectangle([o[0] - 15, 0, o[0] + 15, o[1] + 6], fill=hx(CL[5]) + (int(255 * 0.85 * pa),))
        if t < 0.4:
            gw = 11 * min(1.0, t / 0.15 + 0.2) * (1 - max(0.0, (t - 0.25) / 0.15))
            od.rectangle([o[0] - gw, 0, o[0] + gw, o[1] + 20], fill=hx(CL[6]) + (240,))
        img.alpha_composite(ov)
        ov = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        od = ImageDraw.Draw(ov)
        for y in range(0, o[1], 6):   # 光柱芯进发光层
            ed.rectangle([o[0] - 4, y, o[0] + 3, y + 3], fill=hx(CL[6]))
        # 脚下灯塔点亮帧条（原版 sc 3 → 整数 2 倍；16 fps → 15 fps 换帧）
        fi = int(math.floor(t * 15))
        if 0 <= fi < len(TEX["ignite"]):
            s = TEX["ignite"][fi]
            s2 = s.resize((s.width * 2, s.height * 2), Image.NEAREST)
            img.alpha_composite(s2, dest=snap((o[0] - s2.width // 2, o[1] - s2.height // 2)))
            ed.ellipse([o[0] - 18, o[1] - 14, o[0] + 18, o[1] + 14], fill=hx(CL[6]))
        if pa > 0:   # 顶上星芒（循环）
            s = TEX["flare"][int(math.floor(t * 15)) % len(TEX["flare"])]
            s2 = s.resize((s.width * 2, s.height * 2), Image.NEAREST)
            img.alpha_composite(s2, dest=snap((o[0] - s2.width // 2, 40 - s2.height // 2)))
        dr = ImageDraw.Draw(img)
        # 灯芯一点灯火橙
        for xx in (-2, 0, 2):
            dr.rectangle([o[0] + xx, o[1] - 4, o[0] + xx + 1, o[1] - 3], fill=hx(AC) + (255,))
        if tau >= 0:
            # 两道扩散环（原版棋盘格 → 真 alpha；前沿 1 美术像素白）
            if tau < RING_T:
                rr = ring_at(tau)
                ring_line(rr, 18, CL[4], 0.85 * (1 - 0.4 * tau / RING_T))
                ring_line(rr + 8, 2, CL[6], 1.0)
            if 0.05 <= tau < RING_T + 0.05:
                rr2 = 40 + (R_W * 0.92 - 40) * ease_out((tau - 0.05) / RING_T)
                ring_line(rr2, 6, CL[5], 0.9)
            if tau < 0.22:   # 12 道放射线（原版 2 宽、0.22 秒）
                for j in range(12):
                    dv = (math.cos(j * math.tau / 12 + 0.13), math.sin(j * math.tau / 12 + 0.13) * SY)
                    for k in range(25, int(R * 0.85)):
                        G_put(img, ed, (o[0] + dv[0] * k * PX, o[1] + dv[1] * k * PX), CL[5] if k < R * 0.5 else CL[4], k % 3 == 0)
            img.alpha_composite(ov)
            dr = ImageDraw.Draw(img)
            # 新加：崩解（被环扫到、被打死的怪）
            for e in G.ENS:
                if e["die"]:
                    age = tau - hit_tau2(e["d"])
                    for q in G.disintegrate(age, e, G.SPR[e["k"][0]]):
                        G_put(img, ed, (e["p"][0] + q[0] * PX, e["p"][1] + q[1] * PX), q[2], q[3] if isinstance(q[3], bool) else False, q[4] if len(q) > 4 else 1)
            # 新加：照地灯打满 2 拍，之后 0.5 秒褪
            if tau < 2 / 15:
                lights.append((C[0], C[1], 260, 0.95, (0.85, 0.95, 1.15)))
            elif tau < 0.65:
                lights.append((C[0], C[1], 340, 0.6 * (1 - (tau - 2 / 15) / 0.52), (0.8, 0.92, 1.1)))
        # 光点往上飘（原版后半段）
        if T_BOOM + 0.8 <= t < T_END + 1.5:
            for i in range(24):
                ph2 = (t + hf(i, 2) * 1.2) % 1.2
                an = hf(i, 4) * math.tau
                rr = R_W * 0.8 * math.sqrt(hf(i, 5))
                G_put(img, ed, (o[0] + math.cos(an) * rr, o[1] + math.sin(an) * rr * SY - ph2 * 60), AC if i % 6 == 0 else CL[5], True)
        lights.append((C[0], C[1] - 40, 220, 0.5 * (1 if t < 2.3 else max(0.0, 1 - (t - 2.3) / 0.3)), (0.85, 0.95, 1.1)))
    glow = np.asarray(emit.filter(ImageFilter.GaussianBlur(3))).astype(np.float32) * 0.5
    base = np.asarray(img.convert("RGB")).astype(np.float32) * 0.8
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    lit = np.zeros((H, W, 3), np.float32)
    for (lx, ly, lr, li, lc) in lights:
        dd = np.sqrt((xx - lx) ** 2 + ((yy - ly) / SY) ** 2) / lr
        lit += (li * np.clip(1.0 - dd, 0.0, 1.0) ** 2)[..., None] * np.array(lc, np.float32)
    out = np.clip(base * (1.0 + lit * 1.2) + lit * 30.0 + glow, 0, 255)
    if ph == "sf":
        k = np.full((H, W, 1), 0.35, np.float32)
        y0, x0 = int(C[1] - lum.height + 8), int(C[0] - lum.width // 2)
        k[max(0, y0):y0 + lum.height, max(0, x0):x0 + lum.width] = 1.0
        out = out * k
    return Image.fromarray(out.astype(np.uint8), "RGB")


def G_put(img, ed, p, c, glow=False, sz=1):
    x, y = snap(p)
    if not (0 <= x < W - 1 and 0 <= y < H - 1):
        return
    cc = hx(c) if isinstance(c, str) else c
    ImageDraw.Draw(img).rectangle([x, y, x + PX * sz - 1, y + PX * sz - 1], fill=tuple(cc[:3]) + (255,))
    if glow:
        ed.rectangle([x, y, x + PX * sz - 1, y + PX * sz - 1], fill=tuple(cc[:3]))


def orig_frames():
    d = os.path.join(MAIN, "Claude outputs", "render-ultinv2-integ", "lumen_frames")
    return [os.path.join(d, f) for f in sorted(os.listdir(d))]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join(MAIN, "Claude outputs", "ult_px_lumen_1105"))
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    G.load_assets() if hasattr(G, "load_assets") else None
    TEX["ignite"] = strip_frames("fx_beacon_ignite", 8)
    TEX["flare"] = strip_frames("fx_lumen_beam_flare", 5)
    font = ImageFont.truetype(G.FONT, 20)
    orig = orig_frames()
    O_SF, O_BOOM = 28, 48   # 原版实录：超必杀暂停起点、最大那一下（亮度跳变帧）
    for ver, hf_on in (("A", True), ("B", False)):
        tl = G.timeline(hf_on)
        frames, side = [], []
        boom_k = next(k for k, f in enumerate(tl) if f[1] == "cast" and f[2] >= T_BOOM - 1e-6)
        for k, (rt, ph, t, hfk) in enumerate(tl):
            im = render(rt, ph, t, hfk)
            sheet = im.copy()
            d = ImageDraw.Draw(sheet)
            d.text((12, 8), "流明终结技 · 新版 %s（%s）· 以原版为底：配色对齐钢蓝 + 真 alpha + 最大一下叠加 · %s" % (ver, "最大一下加冲击帧" if hf_on else "不加冲击帧", G.label(t, ph, hfk)),
                   fill=(20, 20, 20) if hfk == 0 else (235, 225, 200), font=font)
            frames.append(sheet)
            # 并排：左原版（按超必杀起点 / 最大一下两处对齐，最大一下之后按游戏时间推进；慢动作段原版是原速，所以左边先走完）
            if ph == "sf":
                oi = O_SF + k
            elif k < boom_k:
                oi = O_SF + 5 + int(round((O_BOOM - O_SF - 5) * (k - 5) / max(1, boom_k - 5)))
            else:
                oi = O_BOOM + int(round((t - T_BOOM) * 15))
            oi = min(len(orig) - 1, oi)
            left = Image.open(orig[oi]).convert("RGB").resize((640, 360))
            right = im.crop((0, 20, W, 740)).resize((640, 360))
            sd = Image.new("RGB", (1290, 400), (12, 12, 16))
            sd.paste(left, (0, 40))
            sd.paste(right, (650, 40))
            dd = ImageDraw.Draw(sd)
            dd.text((8, 8), "原版（integ 现行，GCP 实录）", fill=(230, 230, 230), font=font)
            dd.text((658, 8), "新版 %s · %s" % (ver, G.label(t, ph, hfk)), fill=(230, 230, 230), font=font)
            side.append(sd)
        for fr, nm in ((frames, "ult_lumen_v2_%s.gif" % ver), (side, "ult_lumen_v2_side_%s.gif" % ver)):
            pick = fr[:: max(1, len(fr) // 12)][:12]
            mos = Image.new("RGB", (fr[0].width, fr[0].height * len(pick)))
            for i, f in enumerate(pick):
                mos.paste(f, (0, i * fr[0].height))
            pal = mos.quantize(colors=255, method=Image.MEDIANCUT)
            q = [f.quantize(palette=pal, dither=Image.NONE) for f in fr]
            dur = [70 if i % 3 != 1 else 60 for i in range(len(q))]
            q[0].save(os.path.join(a.out, nm), save_all=True, append_images=q[1:], duration=dur, loop=0, optimize=False, disposal=1)
            print(nm, len(q), "帧", "%.0f KB" % (os.path.getsize(os.path.join(a.out, nm)) / 1024), flush=True)
        os.makedirs(os.path.join(a.out, "v2_frames_" + ver), exist_ok=True)
        for k, f in enumerate(frames):
            f.save(os.path.join(a.out, "v2_frames_%s" % ver, "f%03d.png" % k))


if __name__ == "__main__":
    main()
