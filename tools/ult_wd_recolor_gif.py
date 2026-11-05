#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""维什戴尔终结技「只改颜色」送审 GIF（docs/274 §8）：左原版 / 右 ult/px_plane_wisadel = 1，只用 Python、不开 Godot。
摆法照 ult_moves_b._wd_start / _wd_step：6 排 × 3 发，排距 170、带宽 840、炮弹半径 175，第 k 排在 0.15 + 0.1k 秒落地，余震晚 0.35 秒；
每发 = 爆裂帧条（4 帧 12 fps，× 1.9 × 0.65–1.45 随机大小 / 转角 / 镜像 / 偏移 ≤ 0.4 rr / 起爆错开 ≤ 0.14 秒）+ 弹坑（back 层）+ 约三分之一的粒子团；
落地前天上拖线 + 预兆细环。随机项用本脚本自己的哈希（游戏里是 PF.h），两栏同一套，只差颜色。整屏按 0.6 缩小（看颜色用；形状同原版）。
用法：python tools/ult_wd_recolor_gif.py [--out 目录]"""
import argparse, math, os

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAIN = os.path.dirname(os.path.dirname(os.path.dirname(ROOT))) if ".claude" in ROOT else ROOT
FX = os.path.join(ROOT, "game", "art", "fx")
W, H = 1040, 720
OP = (90.0, 360.0)
RR, HW = 175.0, 420.0
FONT = "C:/Windows/Fonts/msyh.ttc"
GROUND = (36, 46, 48)


def h(x):
    v = math.sin(x * 127.1 + 311.7) * 43758.5453
    return v - math.floor(v)


def frames(name, n):
    im = Image.open(os.path.join(FX, name)).convert("RGBA")
    fw = im.width // n
    return [im.crop((i * fw, 0, (i + 1) * fw, im.height)) for i in range(n)]


def shells():
    out = []
    for k in range(6):
        along = -40.0 + 170.0 * k
        for j in range(3):
            lat = (j - 1.0) * (HW - RR * 0.82) + (18.0 if k % 2 == 1 else -18.0)
            out.append((k, (OP[0] + along, OP[1] + lat), 0.15 + 0.1 * k))
    return out


def tint(im, col):
    a = np.asarray(im).astype(np.float32)
    a[..., :3] *= np.array(col[:3], np.float32)
    if len(col) > 3:
        a[..., 3] *= col[3]
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), "RGBA")


def paste_c(img, sp, c, sc, ang=0.0, flip=False, alpha=1.0):
    s = sp.resize((max(1, int(sp.width * sc)), max(1, int(sp.height * sc))), Image.NEAREST)
    if flip:
        s = s.transpose(Image.FLIP_LEFT_RIGHT)
    if ang:
        s = s.rotate(-math.degrees(ang), resample=Image.NEAREST, expand=True)
    if alpha < 1.0:
        a = np.asarray(s).copy()
        a[..., 3] = (a[..., 3] * alpha).astype(np.uint8)
        s = Image.fromarray(a, "RGBA")
    img.alpha_composite(s, (int(c[0] - s.width / 2), int(c[1] - s.height / 2)))


def render(t, new, T):
    img = Image.new("RGBA", (W, H), GROUND + (255,))
    d = ImageDraw.Draw(img)
    ring_col = (196, 30, 24) if new else (242, 56, 51)
    line_col = (255, 168, 104) if new else (255, 217, 153)
    spark = (240, 74, 36) if new else (242, 25, 25)
    spray = (240, 74, 36) if new else (255, 153, 76)
    for i in range(36):   # 敌人剪影
        ex, ey = 200 + h(i * 3.1) * 760, 90 + h(i * 7.7) * 540
        d.ellipse([ex - 9, ey - 16, ex + 9, ey + 4], fill=(18, 22, 24))
    crater = T["crater"]
    for k, p, ts in shells():   # 弹坑（back 层）
        hp2 = h(p[0] * 0.013 + p[1] * 0.029 + k)
        rk = 0.65 + 0.8 * h(hp2 * 31.0)
        pv = (p[0] + math.cos(h(hp2 * 17) * 6.283) * RR * 0.4 * h(hp2 * 23), p[1] + math.sin(h(hp2 * 17) * 6.283) * RR * 0.4 * h(hp2 * 23))
        if t >= ts:
            age = t - ts
            life = 0.35 + 1.6
            al = min(1.0, (life - age) / 0.6)
            if al > 0:
                cool = min(1.0, age / 0.6)
                col = (1.0, 0.75 + 0.0 * cool, 0.72) if True else None
                paste_c(img, tint(crater[int(hp2 * 97) % 4], (1.0 - 0.4 * cool, 0.75 - 0.2 * cool, 0.72 - 0.17 * cool)), pv, RR * 1.1 * rk / 120.0, hp2 * 5.0, alpha=al)
    for k, p, ts in shells():   # 预兆环 + 天降拖线
        if t < ts + 0.05:
            r = RR * 0.5
            d.ellipse([p[0] - r, p[1] - r, p[0] + r, p[1] + r], outline=ring_col, width=2)
        if ts - 0.1 <= t < ts:
            u = (t - (ts - 0.1)) / 0.1
            a = (p[0] - 90 + 60 * u * 1.0, p[1] - 520 + 350 * u)
            b = (a[0] + 30, a[1] + 170)
            d.line([a, b], fill=line_col, width=6)
    burst = T["burst"]
    for k, p, ts in shells():   # 爆裂帧条 + 粒子团 + 火星
        hp2 = h(p[0] * 0.013 + p[1] * 0.029 + k)
        rk = 0.65 + 0.8 * h(hp2 * 31.0)
        pv = (p[0] + math.cos(h(hp2 * 17) * 6.283) * RR * 0.4 * h(hp2 * 23), p[1] + math.sin(h(hp2 * 17) * 6.283) * RR * 0.4 * h(hp2 * 23))
        bdl = 0.0 if k == 0 else 0.14 * h(hp2 * 41)
        age = t - ts - bdl
        if 0 <= age < 4 / 12.0:
            paste_c(img, burst[min(3, int(age * 12))], pv, 1.9 * rk, (hp2 - 0.5) * 1.2, h(hp2 * 7) < 0.5)
        if hp2 < 0.35 and 0 <= age < 0.6:
            n = 36 if new else 60
            for i in range(n):
                a = h(i * 1.7 + hp2 * 9) * 6.283
                rr = RR * 0.7 * rk * math.sqrt(h(i * 2.3 + hp2)) * min(1.0, age / 0.25)
                if h(i * 5.1 + int(t * 15)) < 0.25 + age:
                    continue
                x, y = pv[0] + math.cos(a) * rr, pv[1] + math.sin(a) * rr * 0.8
                d.rectangle([x, y, x + 2, y + 2], fill=spark)
        if 0 <= t - ts < 0.3:
            for i in range(6):
                a = h(i * 3.3 + k) * 6.283
                rr = 30 + 520 * 0.3 * (t - ts) / 0.3 * h(i * 1.9 + k)
                x, y = p[0] + math.cos(a) * rr, p[1] + math.sin(a) * rr * 0.7
                d.line([x, y, x - math.cos(a) * 8, y - math.sin(a) * 6], fill=spray, width=2)
    img.alpha_composite(T["op"], (int(OP[0] - 64), int(OP[1] - 120)))
    if t < 0.12:
        paste_c(img, T["mz"][min(9, int(t * 20))], (OP[0] + 40, OP[1] - 20), 2.0)
    return img.convert("RGB")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join(MAIN, "Claude outputs", "pxplane_wisadel_1105", "gif"))
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    op = Image.open(os.path.join(ROOT, "game", "art", "operators", "wisadel", "op_wisadel_attack@2x.png")).convert("RGBA")
    op = op.crop((0, 0, op.height, op.height))
    T0 = {"burst": frames("fx_wd_cannon@2x.png", 4), "crater": frames("fx_ws_crater@2x.png", 4), "mz": frames("fx_cannon_burst.png", 10), "op": op}
    T1 = dict(T0, burst=frames("fx_wd_cannon_br@2x.png", 4), mz=frames("fx_cannon_burst_br.png", 10))
    font = ImageFont.truetype(FONT, 22)
    sc = 0.6
    out = []
    for f in range(36):
        t = f / 15.0
        L = render(t, False, T0)
        R = render(t, True, T1)
        sheet = Image.new("RGB", (int(W * sc) * 2 + 6, int(H * sc) + 34 + 22), (14, 16, 18))
        sheet.paste(L.resize((int(W * sc), int(H * sc)), Image.LANCZOS), (0, 34))
        sheet.paste(R.resize((int(W * sc), int(H * sc)), Image.LANCZOS), (int(W * sc) + 6, 34))
        dd = ImageDraw.Draw(sheet)
        dd.text((8, 5), "原版（ult/px_plane_wisadel = 0）", fill=(230, 225, 210), font=font)
        dd.text((int(W * sc) + 14, 5), "只改颜色（= 1）：黑红、去紫、粒子 60 → 36", fill=(230, 225, 210), font=font)
        dd.text((8, int(H * sc) + 38), "%.2f 秒 · 15 fps 原速 · 整屏 0.6 倍（看颜色用）· Python 示意，形状 / 节奏照 ult_moves_b._wd_*" % t, fill=(150, 150, 150), font=ImageFont.truetype(FONT, 14))
        out.append(sheet)
    mos = Image.new("RGB", (out[0].width, out[0].height * 4))
    for i, k in enumerate((3, 6, 9, 14)):
        mos.paste(out[k], (0, i * out[0].height))
    pal = mos.quantize(colors=255, method=Image.MEDIANCUT)
    q = [f.quantize(palette=pal, dither=Image.NONE) for f in out]
    p = os.path.join(a.out, "wisadel_ult_recolor.gif")
    q[0].save(p, save_all=True, append_images=q[1:], duration=67, loop=0)
    out[6].save(os.path.join(a.out, "wisadel_ult_recolor_peak.png"))
    print(p, "%.0f KB" % (os.path.getsize(p) / 1024))


if __name__ == "__main__":
    main()
