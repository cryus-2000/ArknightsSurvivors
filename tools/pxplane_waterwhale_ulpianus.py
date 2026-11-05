#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""乌尔比安 S3「纯水做的鲸」程序生成试样（docs/266 §13 B 路线，用户 11-05「纯水做的鲸鱼，而不是鲸鱼套着一层水」）。

不依赖生图：虎鲸剪影只当遮罩（圆头、高背鳍、尾鳍；沿用 fx_pxplane_ul._orca_cell 的外形，眼斑 / 腹带区域不再区分），
里面填按 15 fps 节拍往后流的水纹（3 阶蓝，半透明，透出地面）；上沿是一排往后卷的浪尖 + 断续白沫，下沿稀白沫；
边缘每拍往外甩水滴（2–3 拍落下、缩成一点消失）；尾柄之后不画尾鳍实形，散成几股往后拖的水流。没有眼睛、花纹、描边。
只出试样（静帧 + 整招 GIF），还没接进游戏；用户点头后再照这个算法改 fx_pxplane_ul._draw_orca。

用法：python tools/pxplane_waterwhale_ulpianus.py [--out 目录]
"""
import argparse, math, os, sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pxplane_gif_ulpianus as G

PX = 2
SY = 0.72
K = 1.45
WATER = [(20, 58, 120), (44, 112, 196), (110, 182, 236)]   # 深 / 中 / 浅水
FOAM = (214, 240, 255)
FOAM2 = (150, 210, 245)


def h_(x):
    return G.h_(x)


def shape(u, w, beat):
    """剪影遮罩（1 = 水体，0 = 外面）：圆头往前收、身体饱满、尾柄细、背鳍高而往后弯（鳍尖后掠）；
    尾鳍（u < -17）是散开的水，越往后越稀、按节拍变"""
    if u > 21 or u < -24:
        return 0
    tw = math.sin(beat * 1.8) * 1.5 if u < -12 else 0.0
    w -= tw
    if u >= 4:
        hh = 7.5 * max(0.0, 1 - ((u - 4) / 17.0) ** 2.4) ** (1 / 2.4)
    elif u >= -10:
        hh = 7.5 * math.sqrt(max(0.0, 1 - ((u - 4) / 18.0) ** 2))
    elif u >= -18:
        hh = 1.6 + (4.6 - 1.6) * (u + 18) / 8.0
    else:
        hh = 1.4 + (-18 - u) * 1.3
        if abs(w) < 1.0 and u < -21:
            return 0
    if -hh <= w <= hh:
        if u < -17.0 and h_(math.floor(u * 1.3) * 3.7 + math.floor(w * 1.5) * 1.9 + beat * 0.53) < (-17.0 - u) / 7.0:
            return 0
        return 1
    if w > hh:   # 背鳍：高 13，中线随高度往后弯，越高越细
        hgt = w - hh
        if hgt > 13:
            return 0
        uc = 0.5 - 0.06 * hgt * hgt
        half = 3.6 * (1 - hgt / 13.0) + 0.4
        return 1 if abs(u - uc) <= half else 0
    return 0


def draw_water_whale(cv, gp, z, pitch, dv, clip, T, ghost=0):
    gp = G.snap(gp)
    e = G.norm((dv[0], dv[1] * SY))
    flip = 1.0 if e[0] >= 0 else -1.0
    a = pitch * flip
    e = (e[0] * math.cos(a) - e[1] * math.sin(a), e[0] * math.sin(a) + e[1] * math.cos(a))
    n = (-e[1], e[0])
    if n[1] > 0:
        n = (-n[0], -n[1])
    beat = int(math.floor(T * 15))
    dot = lambda q, v: q[0] * v[0] + q[1] * v[1]
    c = G.snap((gp[0], gp[1] - z - 10))
    if not clip and ghost == 0 and z > 6:   # 地上的水影
        sk = min(1.0, max(0.45, 1 - z / 160.0))
        rx, ry = 22 * sk, 6 * sk
        for iy in range(-int(ry), int(ry) + 1):
            for ix in range(-int(rx), int(rx) + 1):
                if (ix / rx) ** 2 + (iy / ry) ** 2 <= 1:
                    cv.pxa((gp[0] + ix * PX, gp[1] + iy * PX), (8, 20, 40), 0.4)
    ga = [1.0, 0.35, 0.18][min(2, ghost)]
    for jy in range(-28, 29):
        for ix in range(-42, 43):
            q = (ix, jy)
            u, w = dot(q, e) / K, dot(q, n) / K
            if not shape(u, w, beat):
                continue
            pp = (c[0] + ix * PX, c[1] + jy * PX)
            if clip and pp[1] > gp[1] - 2:
                continue
            if ghost:
                cv.pxa(pp, WATER[1], 0.3 * ga)
                continue
            up = not shape(dot((ix, jy - 1), e) / K, dot((ix, jy - 1), n) / K, beat)
            dn = not shape(dot((ix, jy + 1), e) / K, dot((ix, jy + 1), n) / K, beat)
            if up:   # 上沿：断续白沫（往后流）
                if h_(math.floor(u * 0.8 + beat * 1.6) * 1.37) > 0.28:
                    cv.px(pp, FOAM)
                    if ix % 2 == 0:
                        cv.glow(pp, FOAM2)
                else:
                    cv.pxa(pp, WATER[2], 0.9)
                continue
            if dn:
                if h_(math.floor(u * 0.7 + beat * 1.3) * 2.1) > 0.6:
                    cv.pxa(pp, FOAM2, 0.85)
                else:
                    cv.pxa(pp, WATER[0], 0.8)
                continue
            # 体内：顺体往后流的细长水流线（沿体长拉长、按节拍往后走），其余是半透明的水；下三分之一深一阶
            lane = math.floor(w * 0.9 + 2.5 * math.sin(u * 0.13 - beat * 0.35))
            seg = h_(math.floor((u + beat * 2.5) / 7.0) * 1.91 + lane * 0.77)
            if lane % 3 == 0 and seg > 0.35:
                cv.pxa(pp, WATER[2], 0.85)
            elif w < -2.0:
                cv.pxa(pp, WATER[0], 0.6)
            else:
                cv.pxa(pp, WATER[1], 0.55)
    if ghost or clip:
        return
    # 上沿浪尖：沿背脊每 5 格一个往后卷的小尖（2–3 格），按节拍往后移
    for s in range(-16, 20):
        u = s + (-(beat * 2) % 5)
        if u % 5:
            continue
        # 找这个 u 处的背脊高度
        top = None
        for wv in range(16, -2, -1):
            if shape(u, wv, beat):
                top = wv
                break
        if top is None:
            continue
        base = (u * K * e[0] + top * K * n[0], u * K * e[1] + top * K * n[1])
        for j in range(1, 3 + (s % 2)):
            p = (c[0] + (base[0] + n[0] * j - e[0] * j * 0.9) * PX, c[1] + (base[1] + n[1] * j - e[1] * j * 0.9) * PX)
            cv.px(p, FOAM if j < 2 else FOAM2)
    # 甩出的水滴：从背、背鳍、尾巴往外 / 往后飞，3 拍一轮，落下缩成一点
    for i in range(14):
        ph = (beat + i) % 3
        seed = i * 7.3 + (beat - ph) * 0.61
        u0 = -16 + h_(seed) * 34
        w0 = 6 + h_(seed + 1) * 6
        out = 2 + ph * 3 + h_(seed + 2) * 2
        back = ph * 3
        q = (u0 * K - back, w0 * K + out - ph * ph * 1.2)
        p = (c[0] + (q[0] * e[0] + q[1] * n[0]) * PX, c[1] + (q[0] * e[1] + q[1] * n[1]) * PX)
        col = FOAM if ph == 0 else (FOAM2 if ph == 1 else WATER[2])
        cv.px(p, col)
        if ph == 0 and i % 3 == 0:
            cv.px((p[0] + PX, p[1]), FOAM2)
    # 尾部散成水流：4 股往后拖、正弦摆，越往后越稀，末端甩成水滴（接在散开的尾鳍后面）
    for k in range(4):
        wofs = (k - 1.5) * 2.2
        for j in range(26):
            uu = -21 - j
            wob = math.sin(j * 0.35 - beat * 1.4 + k * 1.3) * (1 + j * 0.12)
            if h_(j * 0.9 + k * 3.1 + beat * 0.37) < j / 30.0:
                continue
            q = (uu * K, (wofs + wob) * K * 0.8)
            p = (c[0] + (q[0] * e[0] + q[1] * n[0]) * PX, c[1] + (q[0] * e[1] + q[1] * n[1]) * PX)
            col = WATER[2] if j < 8 else (FOAM2 if j % 4 == 0 else WATER[1])
            cv.pxa(p, col, 0.9 if j < 12 else 0.7)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join(G.MAIN, "Claude outputs", "pxplane_ulpianus_1105", "orca_gen"))
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    G.draw_orca = draw_water_whale   # 换掉整招 GIF 里的鲸
    lib = G.Lib()
    # 静帧：最高点，水平朝右，画面中央；1 倍 + 3 倍
    cv = G.Canvas()
    G.OX, G.OY = 220, 200
    draw_water_whale(cv, (0, 0), 50, 0.05, (1.0, 0.0), False, 0.4)
    im = cv.final()
    crop = im.crop((100, 40, 340, 200)).resize((720, 480), Image.NEAREST)
    st = Image.new("RGB", (im.width + 720 + 20, 500), (10, 12, 14))
    st.paste(im, (0, 0))
    st.paste(crop, (im.width + 20, 10))
    st.save(os.path.join(a.out, "waterwhale_still.png"))
    # 整招 GIF（同 pxplane_gif_ulpianus 的 s3 场景）
    G.OX, G.OY = 150, 170
    fr = [G.column_frames(G.sc_s3(), lib)]
    frames = G.assemble(fr, ["程序生成·纯水鲸（试样）"], "S3 虎鲸")
    G.save_gif(frames, os.path.join(a.out, "waterwhale_s3.gif"))
    print("ok", a.out)


if __name__ == "__main__":
    main()
