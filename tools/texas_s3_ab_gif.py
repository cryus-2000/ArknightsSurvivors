#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""德克萨斯 S3 方案 A / B 示意 GIF（11-06 用户「S3 要不然设置成攻击一次回一次原地呢，会不会显得没那么奇怪」）：只用 Python，不开 Godot。
两边都是一刀一道（fx/texas_s3_single_slash 的画法），差在本体：
  A（现方案，fx/texas_s3_hide_captain）：原地不画本体，脚下半透明小菱形；本体只在最近一刀的落点定格（rift_pose 0.6 秒）；S3 结束残影回位淡入。
  B（来回）：每一刀从原地闪身出去（残影拖尾）→ 斩 → 闪身回原地（残影）；两刀之间原地是她本人。
节奏按 game/data/characters/texas.json 的真实数值：rift_lead 0.24、rift_gap 0.26、rift_hold 0.32（末刀前多停）、rift_n 5、rift_pose 0.6、rift_len 170、rift_ext 0.6（一刀一道 ×1.6）；
一轮斩完（末刀 + pose）才起下一轮（seg_texas.tx_update），所以两轮首尾相接。
B 的来回拍数：--out_b / --hit_b / --back_b（15 fps 拍）；缺省 1 / 1 / 1——2–3 拍放不进 0.26 秒（= 3.9 拍）的出刀间隔，见报告。
用法：python tools/texas_s3_ab_gif.py [--out 目录] [--out_b 1 --hit_b 1 --back_b 1]
"""
import argparse, importlib.util, json, math, os, random

import numpy as np
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("s3g", os.path.join(HERE, "texas_s3_slash_gif.py"))
G = importlib.util.module_from_spec(spec)
spec.loader.exec_module(G)
ROOT = G.ROOT
_TJ = json.load(open(os.path.join(ROOT, "game", "data", "characters", "texas.json"), encoding="utf-8"))


def _find(x):
    if isinstance(x, dict):
        if "rift_lead" in x:
            return x
        for v in x.values():
            r = _find(v)
            if r:
                return r
    elif isinstance(x, list):
        for v in x:
            r = _find(v)
            if r:
                return r
    return None


TX = _find(_TJ)
LEAD, GAP, HOLD, N, POSE, LEN, EXT = TX["rift_lead"], TX["rift_gap"], TX["rift_hold"], TX["rift_n"], TX["rift_pose"], TX["rift_len"], TX["rift_ext"]
W, H = 640, 360
G.W, G.H = W, H
O = (170, 250)
G.O = O
ENEMIES = [(330, 170), (400, 230), (360, 300), (450, 150), (300, 250), (470, 290), (420, 100)]
G.ENEMIES = ENEMIES
FPS = 30
S3_T0 = 0.1
ROUND_LEN = LEAD + (N - 1) * GAP + HOLD + POSE        # 一轮：末刀出手后 pose 才结束
T_S3_END = S3_T0 + 2 * ROUND_LEN + 0.1
T_END = T_S3_END + 0.7
B = 1.0 / 15.0


def cut_times():
    out = []
    for r in range(2):
        t0 = S3_T0 + r * ROUND_LEN
        out.append([t0 + LEAD + k * GAP + (HOLD if k == N - 1 else 0.0) for k in range(N)])
    return out


ROUNDS = cut_times()
G.ROUNDS = ROUNDS


def build():
    rng = random.Random(5)
    cuts = []
    for ri, rd in enumerate(ROUNDS):
        frm = O
        for k, t in enumerate(rd):
            e = ENEMIES[(k + ri * 3) % len(ENEMIES)]
            last = k == N - 1
            L = LEN * (1.3 if last else 1.0)
            dr = math.atan2(e[1] - O[1], e[0] - O[0])
            sgn = 1 if k % 2 == 0 else -1
            ua = dr + sgn * (0.6 + 0.12 * k)
            u = (math.cos(ua), math.sin(ua))
            p0 = (e[0] - u[0] * L / 2, e[1] - u[1] * L / 2)
            p1 = (e[0] + u[0] * L / 2, e[1] + u[1] * L / 2)
            if k % 2 == 1:
                p0, p1 = p1, p0
            ud = ((p1[0] - p0[0]) / L, (p1[1] - p0[1]) / L)
            ext = L * EXT * 1.6
            a = (p0[0] - ud[0] * ext, p0[1] - ud[1] * ext)
            c = (p1[0] + ud[0] * ext, p1[1] + ud[1] * ext)
            life = TX["rift_scar"] + 0.08
            sparks = []
            for i in range(10 if last else 7):
                ang = rng.uniform(0, math.tau)
                sp = rng.uniform(60, 170)
                sparks.append((math.cos(ang) * sp, math.sin(ang) * sp * 0.72 - 40, rng.uniform(0.18, 0.34), rng.random() < 0.5))
            cuts.append({"t": t, "e": e, "lines": [{"a": a, "c": c, "w": 3 if last else 2, "hold": max(1, round(life * 15)), "st": 3, "t0": t}],
                         "p1": p1, "p0": p0, "from": frm, "last": last, "round": ri, "sparks": sparks})
            frm = p1
    return cuts


def body_plan(cuts, mode, ob, hb, bb):
    """返回 (draws, trails)：draws(t) → [(pos, flip, alpha)]；trails = [(a, b, t0)]"""
    trails = []
    if mode == "A":
        for c in cuts:
            trails.append((c["from"], c["p1"], c["t"]))
        trails.append((cuts[-1]["p1"], O, T_S3_END))

        def draws(t):
            if not (S3_T0 <= t < T_S3_END):
                if t >= T_S3_END:
                    return [(O, False, max(0.15, min(1.0, (t - T_S3_END) / 0.18)))]
                return [(O, False, 1.0)]
            past = [c for c in cuts if c["t"] <= t]
            if past:
                c = past[-1]
                age = t - c["t"]
                if age < POSE:
                    k = min(1.0, max(0.0, (1 - age / POSE) / 0.3))
                    return [(c["p1"], c["p1"][0] < c["p0"][0], 0.35 + 0.65 * k)]
            return []
        return draws, trails
    # B：每刀 出（ob 拍）→ 落点站 hb 拍 → 回（bb 拍）；下一刀的「出」先到就直接截断回程（如实）
    segs = []   # (t_from, t_to, where)  where = "O" / cut / ("tr", a, b)
    ts = [c["t"] for c in cuts]
    for i, c in enumerate(cuts):
        dep = c["t"] - ob * B
        stay_end = c["t"] + hb * B
        back_end = stay_end + bb * B
        nxt = (ts[i + 1] - ob * B) if i + 1 < len(cuts) else 1e9
        segs.append((dep, c["t"], ("go", O, c)))
        segs.append((c["t"], min(stay_end, nxt), ("at", c)))
        if stay_end < nxt:
            segs.append((stay_end, min(back_end, nxt), ("back", c, O)))
            trails.append((c["p1"], O, stay_end))
        trails.append((O, c["p1"], dep))

    def draws(t):
        for a, b, w in segs:
            if a <= t < b:
                if w[0] == "at":
                    c = w[1]
                    return [(c["p1"], c["p1"][0] < c["p0"][0], 1.0)]
                return []   # 闪身途中：只有残影
        return [(O, False, 1.0)]
    return draws, trails


def scene(t, mode, cuts, plan, A, bg):
    import numpy as np
    draws, trails = plan
    img = bg.copy()
    px = np.asarray(img).astype(float)
    gl = np.zeros((H, W, 3))
    for e in ENEMIES:
        hit = any(0 <= t - c["t"] < 0.08 and c["e"] == e for c in cuts)
        pe = A["en"][int(t * 6) % 4]
        if hit:
            pe = G.tint(pe, (3, 3, 3), 1.0)
        im2 = Image.fromarray(px.clip(0, 255).astype(np.uint8))
        ImageDraw.Draw(im2).ellipse([e[0] - 11, e[1] - 3, e[0] + 11, e[1] + 4], fill=(16, 20, 22, 255))
        im2.alpha_composite(pe, (e[0] - pe.width // 2, e[1] - pe.height + 6))
        px = np.asarray(im2).astype(float)
    if mode == "A" and S3_T0 <= t < T_S3_END:
        G.pos_mark(px, t)
    img = Image.fromarray(px.clip(0, 255).astype(np.uint8))
    for p, fl, al in draws(t):
        spr = A["atk"][4] if p != O else A["idle"][int(t * 8) % 7]
        G.put(img, spr, p, fl, al)
    for a, b, t0 in trails:
        age = t - t0
        if 0 <= age < 0.26 and math.dist(a, b) >= 8:
            fade = 1 - age / 0.26
            for i in range(4):
                u = (i + 1) / 5
                G.put(img, A["atk"][4], (round(a[0] + (b[0] - a[0]) * u), round(a[1] + (b[1] - a[1]) * u)), b[0] < a[0], fade * (0.18 + 0.32 * u), (0.55, 0.72, 1.0))
    px = np.asarray(img).astype(float)
    lamps = []
    for c in cuts:
        for it in c["lines"]:
            f = int(math.floor(t * 15) - math.floor(it["t0"] * 15))
            if f >= 0:
                G.draw_line(px, gl, it, f)
        if 0 <= t - c["t"] < 2 / 15:
            lamps.append((c["e"][0], c["e"][1] - G.TX_H, 200, 0.9))
        age = t - c["t"]
        for s in c["sparks"]:
            vx, vy, life, hot = s[:4]
            if 0 <= age < life:
                x = c["e"][0] + vx * age
                y = c["e"][1] - 20 + vy * age + 260 * age * age
                k = age / life
                G.cell(px, x, y, G.TX_C[7] if (hot and k < 0.4) else (G.TX_C[6] if k < 0.6 else G.TX_C[5]))
                if hot and k < 0.5:
                    G.glow(gl, x, y, (1.0, 0.8, 0.5), 0.5)
    yy, xx = np.mgrid[0:H, 0:W]
    for lx, ly, lr, li in lamps:
        d = np.sqrt(((xx - lx) / lr) ** 2 + ((yy - ly - G.TX_H) / (lr * 0.6)) ** 2)
        k = np.clip(1 - d, 0, 1) ** 2 * li * 70
        px[..., 0] += k
        px[..., 1] += k * 0.62
        px[..., 2] += k * 0.28
    if gl.any():
        from PIL import ImageFilter
        g8 = Image.fromarray((np.clip(gl, 0, 1) * 255).astype(np.uint8))
        px[..., :3] += np.asarray(g8.filter(ImageFilter.GaussianBlur(3))).astype(float)[..., :3] * 2.2 + np.asarray(g8.filter(ImageFilter.GaussianBlur(8))).astype(float)[..., :3] * 3.0
    return Image.fromarray(px.clip(0, 255).astype(np.uint8)).convert("RGB")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join(G.MAIN, "Claude outputs", "texas_s3_ab_1106"))
    ap.add_argument("--out_b", type=int, default=1)
    ap.add_argument("--hit_b", type=int, default=1)
    ap.add_argument("--back_b", type=int, default=1)
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    od = os.path.join(ROOT, "game", "art", "operators", "texas")
    A = {"atk": G.sheet(os.path.join(od, "op_texas_s3_dash@2x.png"), 8), "idle": G.sheet(os.path.join(od, "op_texas_idle@2x.png"), 7),
         "en": G.sheet(os.path.join(ROOT, "game", "art", "enemies", "offspring", "e_offspring@2x.png"), 4)}
    bg = G.background()
    cuts = build()
    pa = body_plan(cuts, "A", 0, 0, 0)
    pb = body_plan(cuts, "B", a.out_b, a.hit_b, a.back_b)
    # 报告：每刀间隔 + B 在原地站了多久
    ts = [c["t"] for c in cuts]
    print("出刀时刻（秒）：", ", ".join("%.2f" % x for x in ts))
    for i in range(1, len(ts)):
        dt = ts[i] - ts[i - 1]
        stand = dt - (a.out_b + a.hit_b + a.back_b) * B
        print("刀 %d→%d 间隔 %.2f 秒 = %.1f 帧@60 / %.1f 帧@30 / %.1f 拍@15；B 两刀之间在原地站 %.2f 秒（%.1f 帧@30）"
              % (i, i + 1, dt, dt * 60, dt * 30, dt * 15, max(0.0, stand), max(0.0, stand) * 30))
    font = ImageFont.truetype(G.FONT, 14)
    frames = []
    for i in range(int(T_END * FPS)):
        t = i / FPS
        L = scene(t, "A", cuts, pa, A, bg)
        R = scene(t, "B", cuts, pb, A, bg)
        sh = Image.new("RGB", (W * 2 + 6, H + 44), (12, 12, 16))
        sh.paste(L, (0, 44))
        sh.paste(R, (W + 6, 44))
        d = ImageDraw.Draw(sh)
        d.text((8, 4), "A 现方案：原地隐藏 + 脚下小菱形，本体在落点定格", fill=(230, 230, 230), font=font)
        d.text((W + 14, 4), "B 来回：每刀闪出 %d 拍 → 斩（站 %d 拍）→ 闪回 %d 拍" % (a.out_b, a.hit_b, a.back_b), fill=(255, 220, 160), font=font)
        d.text((8, 24), "%.2f 秒  出刀间隔 %.2f 秒（末刀前 %.2f），原速 30 fps，Python 示意非实机" % (t, GAP, GAP + HOLD), fill=(150, 150, 150), font=font)
        frames.append(sh)
    for sc in (1, 2):
        fr = frames if sc == 1 else [f.resize((f.width * 2, f.height * 2), Image.NEAREST) for f in frames]
        pal = fr[int(0.5 * FPS)].quantize(colors=220, method=Image.MEDIANCUT)
        q = [f.quantize(palette=pal, dither=Image.NONE) for f in fr]
        path = os.path.join(a.out, "texas_s3_ab_%dx.gif" % sc)
        q[0].save(path, save_all=True, append_images=q[1:], duration=int(1000 / FPS), loop=0, disposal=1)
        print(path, len(q), "帧", "%.0f KB" % (os.path.getsize(path) / 1024))


if __name__ == "__main__":
    main()
