#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""艾丽妮终结技「宣判」转平面画面（docs/275，ult/px_plane）送审 GIF：只用 Python、不开 Godot。
画法读 tools/ult_px_irene_art.py（与 game/scripts/run/ult_px_ir.gd 同算法）。时间轴照游戏：
超必杀暂停 0.35 秒（世界压暗）→ 起手慢放 0.5 秒（蓄力）→ 招式（ult_moves_c._irv_step，游戏时间）：
0.1 秒盖章（纹章 + 光链）→ 0.18–0.78 秒 6 刀穿梭 → 0.85 秒起由近到远连环爆 → 1.25 秒收尾斩击（冲击帧两拍：白底黑剪影 / 黑底白剪影，
随后顿帧 + 0.25 倍慢放 0.45 秒 + 0.35 秒缓回）→ 纹章 1.4 秒冷却淡掉、裂缝 2 秒。
输出（15 fps 原速）：ult_irene_1x.gif（1 倍整屏）、ult_irene_x2.gif（中心 2 倍）、ult_irene_new_frames/（逐帧 PNG，给并排对照用）。
用法：python tools/ult_px_irene_gif.py [--out 目录]
"""
import argparse, math, os, sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ult_px_irene_art as A
from pxplane_saria_art import hx

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAIN = os.path.dirname(os.path.dirname(os.path.dirname(ROOT))) if ".claude" in ROOT else ROOT
PX = 2
W, H = 1240, 860
C = (620, 420)
GROUND = (36, 46, 48)
FONT = "C:/Windows/Fonts/msyh.ttc"
R_W = 550.0
R = R_W / 2
VIOLET_L = (0.8, 0.6, 1.0)


def snap(v):
    return (round(v[0] / 2) * 2, round(v[1] / 2) * 2)


def sprite(path, n, fi=0):
    im = Image.open(path).convert("RGBA")
    fw = im.width // n
    return im.crop((fi * fw, 0, (fi + 1) * fw, im.height))


def hsh(x, y, k=0):
    return A.hsh(x, y, k)


# ---------------------------------------------------------------- 时间轴（拍 → 阶段 + 游戏时间）

SF = 5          # 超必杀暂停 5 拍（0.33 秒）
WU = 8          # 起手慢放 8 拍（0.53 秒）
T_FIN = 1.25    # 收尾斩击（招式游戏时间）


def timeline():
    """[(阶段, 招式游戏时间 t 或起手进度, 冲击帧拍 0/1/-1)]"""
    out = []
    for i in range(SF):
        out.append(("sf", 0.0, -1))
    for i in range(WU):
        out.append(("wu", (i + 1) / WU, -1))
    t = 0.0
    while t < T_FIN - 1e-6:
        out.append(("cast", t, -1))
        t += 1 / 15
    t = T_FIN
    out.append(("cast", t, 0))
    out.append(("cast", t, 1))
    for i in range(3):   # 顿帧
        out.append(("cast", t, -1))
    for i in range(7):   # 0.25 倍慢放 0.45 秒
        t += 0.25 / 15
        out.append(("cast", t, -1))
    for i in range(5):   # 0.35 秒缓回
        t += (0.25 + 0.75 * (i + 1) / 5) / 15
        out.append(("cast", t, -1))
    while t < T_FIN + 1.9:
        t += 1 / 15
        out.append(("cast", t, -1))
    return out


# ---------------------------------------------------------------- 场景（世界坐标）

def enemies():
    out = []
    for i in range(22):
        a = i * 2.39996 + 0.4
        r = 120 + 400 * ((i * 0.618) % 1.0)
        out.append((C[0] + math.cos(a) * r, C[1] + math.sin(a) * r * 0.62))
    return out


ENS = enemies()
VS = 0.37
DV = (math.cos(VS * math.pi), math.sin(VS * math.pi))


def pins():
    lst = []
    for i, e in enumerate(ENS):
        d = math.hypot(e[0] - C[0], e[1] - C[1])
        lst.append({"e": i, "d": d})
    lst.sort(key=lambda p: p["d"])
    for n, p in enumerate(lst):
        e = ENS[p["e"]]
        L = p["d"] or 1.0
        ta = math.atan2((e[1] - C[1]) / A.SQ, e[0] - C[0])   # 纹章是压扁的椭圆：起点落在椭圆边上
        p["rim"] = (C[0] + math.cos(ta) * R_W * 0.97, C[1] + math.sin(ta) * R_W * 0.97 * A.SQ)
        p["delay"] = 0.02 * (n % 6)
        p["chain"] = n < 18
        p["tb"] = 0.85 + 0.4 * p["d"] / R_W
    return lst


PINS = pins()


def dashes():
    out = []
    pos = C
    for j in range(6):
        a0 = VS * math.tau + j * math.tau * 0.62
        rr = R_W * (0.65 + 0.2 * A.hf(j, 3, 1))
        np_ = (C[0] + math.cos(a0) * rr, C[1] + math.sin(a0) * rr * 0.72)
        out.append({"t": 0.18 + 0.1 * j, "a": pos, "b": np_})
        pos = np_
    return out


DASH = dashes()


def her_pos(t):
    p = C
    for d in DASH:
        if t >= d["t"]:
            p = d["b"]
    if t >= 0.78:
        p = C
    return p


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
        if not (0 <= x < W and 0 <= y < H):
            return
        cc = hx(c) if isinstance(c, str) else c
        if a < 1.0:
            base = img.getpixel((x, y))
            cc = tuple(int(base[i] * (1 - a) + cc[i] * a) for i in range(3)) + (255,)
        dr.rectangle([x, y, x + PX * sz - 1, y + PX * sz - 1], fill=cc)
        if glow:
            ed.rectangle([x, y, x + PX - 1, y + PX - 1], fill=cc[:3])

    def pts(o, lst):
        for q in lst:
            if isinstance(q[3], bool):
                put(o[0] + q[0] * PX, o[1] + q[1] * PX, q[2], glow=q[3], sz=int(q[4]) if len(q) > 4 else 1)
            else:
                put(o[0] + q[0] * PX, o[1] + q[1] * PX, q[2], a=q[3])

    if hfk >= 0:   # 冲击帧：整屏底 + 剪影（只有收尾斩击 + 主裂缝）
        bg = (235, 230, 220) if hfk == 0 else (5, 5, 8)
        fg = "#000000" if hfk == 0 else "#ffffff"
        im2 = Image.new("RGB", (W, H), bg)
        d2 = ImageDraw.Draw(im2)
        for lst, o in ((A.final_blade(R, DV, 0.0, sil=True), C), (A.crack(R, math.atan2(DV[1], DV[0]), 0.05, 3), C), (A.crack(R, math.atan2(DV[1], DV[0]) + math.pi, 0.05, 4), C)):
            for q in lst:
                x, y = snap((o[0] + q[0] * PX, o[1] + q[1] * PX))
                d2.rectangle([x, y, x + 1, y + 1], fill=fg)
        return im2

    ct = t if ph == "cast" else -1.0
    lights = []
    # ---- 地面层
    if ct >= 0.1:
        fade = None if ct < T_FIN else ct - T_FIN
        md = A.seal_mod(ct - 0.1, fade)
        if md is not None:
            arr = np.asarray(SEAL).astype(np.float32)
            arr[..., 0] = np.clip(arr[..., 0] * md[0], 0, 255)
            arr[..., 1] = np.clip(arr[..., 1] * md[1], 0, 255)
            arr[..., 2] = np.clip(arr[..., 2] * md[2], 0, 255)
            arr[..., 3] = arr[..., 3] * md[3]
            sim = Image.fromarray(arr.astype(np.uint8), "RGBA").resize((SEAL.width * PX, SEAL.height * PX), Image.NEAREST)
            img.alpha_composite(sim, dest=(int(C[0] - sim.width // 2), int(C[1] - sim.height // 2)))
            dr = ImageDraw.Draw(img)
    if ct >= T_FIN:
        ang = math.atan2(DV[1], DV[0])
        pts(C, A.crack(R, ang, ct - T_FIN, 3))
        pts(C, A.crack(R, ang + math.pi, ct - T_FIN, 4))
        for k, side in enumerate((-1, 1)):
            o2 = (C[0] + DV[0] * R_W * 0.25 * side, C[1] + DV[1] * R_W * 0.25 * side)
            pts(o2, A.crack(R * 0.7, ang + (math.pi if side < 0 else 0) + side * 0.12, ct - T_FIN - 0.04, 9 + k, 1.8))
    for p in PINS:   # 爆点灼痕在 boom 里（贴地部分画在一起）
        pass
    for e in ENS:
        dr.ellipse([e[0] - 10, e[1] + 1, e[0] + 10, e[1] + 7], fill=(18, 22, 24, 255))
    # ---- 排序层（简化：敌人 → 她 → 特效）
    for i, e in enumerate(ENS):
        img.alpha_composite(ENEMY, dest=(int(e[0] - ENEMY.width // 2), int(e[1] - ENEMY.height + 6)))
    hp = her_pos(ct) if ct >= 0 else C
    img.alpha_composite(OPS["irene"], dest=snap((hp[0] - 64, hp[1] - 120)))
    if ph == "wu":
        pts(C, A.windup(t, tk))
    if ct >= 0:
        if ct < 0.1:   # 盖章前一拍：灯芯亮
            pts(C, A.windup(1.0, tk))
        for p in PINS:   # 光链
            if not p["chain"] or ct < 0.1 + p["delay"]:
                continue
            e = ENS[p["e"]]
            tgt = ((e[0] - p["rim"][0]) / PX, (e[1] - 10 - p["rim"][1]) / PX)
            grow = (ct - 0.1 - p["delay"]) / 0.12
            br = None if ct < p["tb"] else ct - p["tb"]
            pts(p["rim"], A.chain(tgt, grow, br))
        for j, d in enumerate(DASH):   # 穿梭斩线 + 细线 + 落点水花
            f = int(math.floor((ct - d["t"]) * 15))
            a0 = d["a"]
            b0 = d["b"]
            L = math.hypot(b0[0] - a0[0], b0[1] - a0[1]) or 1
            dv = ((b0[0] - a0[0]) / L, (b0[1] - a0[1]) / L)
            sa = (a0[0] - dv[0] * 30, a0[1] - dv[1] * 30 - 20)
            sb = (b0[0] + dv[0] * 40, b0[1] + dv[1] * 40 - 20)
            pts(sa, A.blade(((sb[0] - sa[0]) / PX, (sb[1] - sa[1]) / PX), f, 4.0, 1))
            pts((a0[0], a0[1] - 20), A.thread(((b0[0] - a0[0]) / PX, (b0[1] - a0[1]) / PX), ct - d["t"]))
            pts(b0, A.splash(dv[0], dv[1], f))
        for p in PINS:   # 连环爆
            f = int(math.floor((ct - p["tb"]) * 15))
            if 0 <= f <= 6:
                e = ENS[p["e"]]
                pts(e, A.boom(f, big=p["d"] < R_W * 0.5))
                pts((e[0], e[1] - 16), A.cloud(ct - p["tb"], p["e"] * 3 + 1, 48 if p["d"] < R_W * 0.5 else 40, 60))
                for q in range(3):
                    gr = A.grain(ct - p["tb"], p["e"] * 7 + q, "shard" if q < 2 else "drop")
                    if gr:
                        put(e[0] + gr[0] * PX, e[1] - 8 + gr[1] * PX, gr[2], sz=gr[3] // 2 or 1)
        if ct >= T_FIN:   # 收尾斩击
            age = ct - T_FIN
            pts(C, A.final_blade(R, DV, age))
            # 收尾大爆（同 ult_px_ir._draw_blast）：预备压暗 + 光点吸入 → 亮核 2 拍 → 冲击环
            if age < A.BLAST_T + 0.2:
                kd = min(1.0, age / A.BLAST_T) * (1.0 if age < A.BLAST_T else max(0.0, 1 - (age - A.BLAST_T) / 0.2))
                if kd > 0:
                    ov = Image.new("RGBA", (W, H), (0, 0, 0, 0))
                    ImageDraw.Draw(ov).ellipse([C[0] - R_W * 1.05, C[1] - R_W * 1.05 * A.SQ, C[0] + R_W * 1.05, C[1] + R_W * 1.05 * A.SQ], fill=(0, 0, 5, int(255 * 0.28 * kd)))
                    img.alpha_composite(ov)
                    dr = ImageDraw.Draw(img)
            pts(C, A.blast_prep(R, age))
            if age >= A.BLAST_T:
                tau = age - A.BLAST_T
                for rx, col in A.blast_core(R, int(math.floor(tau * 15))):
                    dr.ellipse([C[0] - rx * PX, C[1] - 12 - rx * PX * A.SQ, C[0] + rx * PX, C[1] - 12 + rx * PX * A.SQ], fill=hx(col))
                if 0 <= tau < 2 / 15:
                    lights.append((C[0], C[1], 240, 0.9, (1.0, 0.85, 1.25)))
                pts(C, A.shock_ring(R, tau))
                pts((C[0], C[1] - 12), A.cloud(tau, 777, R * 0.6, 160))
            nv = (-DV[1], DV[0])
            for i in range(7):
                x = (i - 3) / 3
                bp = (C[0] + DV[0] * R_W * x * 0.95 + nv[0] * (A.hf(i, 1, 2) - 0.5) * 30, C[1] + DV[1] * R_W * x * 0.95 + nv[1] * (A.hf(i, 1, 2) - 0.5) * 30)
                dl = 0.08 + 0.04 * abs(x) * 3
                f = int(math.floor((age - dl) * 15))
                pts(bp, A.boom(f, s=2.4))
                pts((bp[0], bp[1] - 16), A.cloud(age - dl, 500 + i, 50, 60))
            # 崩解（用户 11-05「碎石和尘土比原版薄，少了崩解感」）：尘墙先画、碎石压在上面
            for q in range(A.SLAB_N):
                side = 1 if q % 2 else -1
                x = ((q // 2) - (A.SLAB_N // 2 - 1) / 2) / ((A.SLAB_N // 2 - 1) / 2)
                sp = (C[0] + DV[0] * R_W * x * 0.95 + nv[0] * side * 6, C[1] + DV[1] * R_W * x * 0.95 + nv[1] * side * 6)
                pts(sp, A.slab(age - A.shock_at(R, abs(x) * 0.95 * R), 200 + q, (nv[0] * side, nv[1] * side)))
    # ---- 光照
    if ct >= 0.1:
        k = max(0.0, 1.0 - (ct - 0.1) / 2.0)
        lights.append((C[0], C[1], R_W * 0.5, 0.6 * k, VIOLET_L))
    if T_FIN <= ct < T_FIN + 0.6:
        lights.append((C[0], C[1], 320, 0.7 * (1 - (ct - T_FIN) / 0.6), (0.95, 0.62, 0.8)))
    if ph == "wu":
        lights.append((C[0] + 20, C[1] - 56, 90, 0.4 * t, VIOLET_L))
    glow = np.asarray(emit.filter(ImageFilter.GaussianBlur(3))).astype(np.float32) * 0.55
    amb = 0.8
    base = np.asarray(img.convert("RGB")).astype(np.float32) * amb
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    lit = np.zeros((H, W, 3), np.float32)
    for (lx, ly, lr, li, lc) in lights:
        dd = np.sqrt((xx - lx) ** 2 + ((yy - ly) / 0.72) ** 2) / lr
        lit += (li * np.clip(1.0 - dd, 0.0, 1.0) ** 2)[..., None] * np.array(lc, np.float32)
    base = base * (1.0 + lit * 1.3) + lit * 40.0
    out = np.clip(base + glow, 0, 255)
    if ph == "sf":   # 超必杀暂停：压暗到约 35%，她不压暗（共用演出，没改）
        m = np.zeros((H, W), np.float32)
        Image.fromarray(m)
        k = np.full((H, W, 1), 0.35, np.float32)
        y0, x0 = int(C[1] - 120), int(C[0] - 64)
        k[max(0, y0):y0 + 128, max(0, x0):x0 + 128] = 1.0
        out = out * k
    if ph == "wu":
        out = out * 0.75
    return Image.fromarray(out.astype(np.uint8), "RGB")


def main():
    global ENEMY, OPS, SEAL
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join(MAIN, "Claude outputs", "ult_px_irene_1105"))
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    fdir = os.path.join(a.out, "new_frames")
    os.makedirs(fdir, exist_ok=True)
    en = sprite(os.path.join(ROOT, "game", "art", "enemies", "offspring", "e_offspring@2x.png"), 4)
    arr = np.asarray(en).astype(np.float32)
    arr[..., :3] = arr[..., :3] * 0.32 + np.array([10, 12, 14])
    ENEMY = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")
    OPS = {"irene": sprite(os.path.join(ROOT, "game", "art", "operators", "irene", "op_irene_idle@2x.png"), 8)}
    SEAL = Image.open(os.path.join(ROOT, "game", "art", "fx", "pxp", "pxp_ult_ir_seal.png")).convert("RGBA")
    font = ImageFont.truetype(FONT, 18)
    tl = timeline()
    names = {"sf": "起手（超必杀暂停，共用演出）", "wu": "蓄力（起手慢放）", "cast": "释放"}
    big, small = [], []
    for tk, (ph, t, hfk) in enumerate(tl):
        im = render(tk, ph, t, hfk)
        lab = names[ph]
        if ph == "cast":
            lab = "定罪" if t < 0.18 else "行刑（穿梭 6 刀）" if t < 0.85 else "连环爆" if t < T_FIN else ("冲击帧（保留）" if hfk >= 0 else "收尾斩击 → 纹章冷却")
        im.save(os.path.join(fdir, "f%03d.png" % tk))
        sheet = im.copy()
        d = ImageDraw.Draw(sheet)
        d.text((10, 8), "艾丽妮「宣判」· 转平面版 · 1 倍 · 15 fps 原速 · " + lab, fill=(235, 225, 200) if hfk != 0 else (20, 20, 20), font=font)
        big.append(sheet)
        cx, cy = C
        small.append(im.crop((cx - 300, cy - 210, cx + 300, cy + 210)).resize((1200, 840), Image.NEAREST))
    for frames, nm in ((big, "ult_irene_1x.gif"), (small, "ult_irene_x2.gif")):
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
