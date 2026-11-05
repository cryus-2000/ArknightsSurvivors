#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""乌尔比安 S3「生图作形状约束 + 程序水」试样（docs/266 §14，用户 11-05「把生图的当作形状约束，然后来做我们自己的」）。

1. 形状：从生图抠剪影当遮罩——空中 A3（Claude outputs/.../orca_gen/v3_apex3_3_raw.png）、俯冲 D3（v3_dive3_3_raw.png）；
   洋红底抠图 → 取最大连通块（水滴、水花不要，由程序画）→ 补洞 → 按体长 64 美术像素（128 世界像素）缩放；
   预生成 15° 一档的旋转遮罩（高分辨率旋转后按格覆盖率 ≥ 0.5 取样到 1 倍像素格，边缘不糊），游戏里同样按档取（不在运行时旋转贴图）。
   同时取生图的亮度到同一格子，内部流线的明暗按它走（沿背、沿腹的亮带）。
2. 内部：半透明流动水纹（4 阶蓝，最亮一阶进发光层），细长流线沿体长往后按 15 fps 节拍走。
3. 边缘：上沿断续白沫浪尖；背鳍尖、尾鳍末端每拍碎出水花、甩出水滴；尾后散成 4 股水流。没有眼睛、花纹、描边。
4. 动画：沿弧线移动；破水 = A3 转到头朝上 + 一段从地面拉出的水柱；划弧时 A3 从 −45° 转平；顶点停；下砸切 D3。
5. 落地水爆：沿用 s3_up / s3_gd 帧条（第八轮）。
只出 Python 试样（整招 GIF + 静帧对照）；用户点头后再把遮罩烘进帧条、照这个算法改 fx_pxplane_ul._draw_orca。

用法：python tools/pxplane_orcamask_ulpianus.py
"""
import math, os, sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pxplane_gif_ulpianus as G

SRC = os.path.join(G.MAIN, "Claude outputs", "pxplane_ulpianus_1105", "orca_gen")
OUT = SRC
PX = 2
SY = 0.72
BODY = 64            # 体长（美术像素）
STEP = 15            # 遮罩旋转档（度）
# 水色 4 阶（比上一版亮、通透）：深 / 中 / 浅 / 最亮（进发光层）
W4 = [(36, 96, 186), (64, 146, 224), (128, 202, 248), (214, 242, 255)]
FOAM = (226, 246, 255)


def key_mask(path):
    """洋红底抠图 → 最大连通块的掩码 + 亮度（0..1），按物体外框裁"""
    im = np.asarray(Image.open(path).convert("RGB")).astype(int)
    r, g, b = im[..., 0], im[..., 1], im[..., 2]
    mag = (r > 140) & (b > 140) & (g < 120) & (np.abs(r - b) < 90)
    fg = ~mag
    # 最大连通块（4 邻接，逐行扫描的简易标号）
    from collections import deque
    H, W = fg.shape
    lab = np.zeros((H, W), np.int32)
    best, best_n, cur = 0, 0, 0
    for y in range(0, H, 3):
        for x in range(0, W, 3):
            if fg[y, x] and lab[y, x] == 0:
                cur += 1
                n = 0
                dq = deque([(y, x)])
                lab[y, x] = cur
                while dq:
                    cy, cx = dq.popleft()
                    n += 1
                    for ny, nx in ((cy + 1, cx), (cy - 1, cx), (cy, cx + 1), (cy, cx - 1)):
                        if 0 <= ny < H and 0 <= nx < W and fg[ny, nx] and lab[ny, nx] == 0:
                            lab[ny, nx] = cur
                            dq.append((ny, nx))
                if n > best_n:
                    best, best_n = cur, n
    m = lab == best
    # 补洞：从边上灌水，灌不到的背景就是洞
    bg = ~m
    seen = np.zeros_like(bg)
    dq = deque([(0, 0)])
    seen[0, 0] = True
    while dq:
        cy, cx = dq.popleft()
        for ny, nx in ((cy + 1, cx), (cy - 1, cx), (cy, cx + 1), (cy, cx - 1)):
            if 0 <= ny < H and 0 <= nx < W and bg[ny, nx] and not seen[ny, nx]:
                seen[ny, nx] = True
                dq.append((ny, nx))
    m = m | (bg & ~seen)
    ys, xs = np.nonzero(m)
    y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
    lum = (0.299 * r + 0.587 * g + 0.114 * b) / 255.0
    return m[y0:y1, x0:x1].astype(np.float32), lum[y0:y1, x0:x1].astype(np.float32)


def principal_len(m):
    ys, xs = np.nonzero(m > 0.5)
    pts = np.stack([xs, ys], 1).astype(float)
    pts -= pts.mean(0)
    ev, vec = np.linalg.eigh(np.cov(pts.T))
    ax = vec[:, -1]
    proj = pts @ ax
    return proj.max() - proj.min(), math.degrees(math.atan2(ax[1], ax[0]))


def bake(pose_path, base_angle):
    """→ {角度档: (art 掩码 bool, art 亮度, 中心偏移)}；角度 = 屏幕上体长方向（0 = 朝右水平，正 = 往下转）"""
    m, lum = key_mask(pose_path)
    L, _ = principal_len(m)
    sc = BODY / L
    mi = Image.fromarray((m * 255).astype(np.uint8))
    li = Image.fromarray((lum * 255).astype(np.uint8))
    out = {}
    for ang in range(-90, 91, STEP):
        rot = ang - base_angle   # 生图本来的倾角
        mr = mi.rotate(-rot, resample=Image.BILINEAR, expand=True)
        lr = li.rotate(-rot, resample=Image.BILINEAR, expand=True)
        w = max(1, int(round(mr.width * sc)))
        h = max(1, int(round(mr.height * sc)))
        ma = np.asarray(mr.resize((w, h), Image.BOX)).astype(np.float32) / 255.0
        la = np.asarray(lr.resize((w, h), Image.BOX)).astype(np.float32) / 255.0
        la = np.where(ma > 0.05, la / np.maximum(ma, 0.05), 0.0)
        out[ang] = (ma >= 0.5, np.clip(la, 0, 1))
    return out


MASKS = {}


def masks():
    if not MASKS:
        MASKS["apex"] = bake(os.path.join(SRC, "v3_apex3_3_raw.png"), 0.0)
        _, dang = principal_len(key_mask(os.path.join(SRC, "v3_dive3_3_raw.png"))[0])
        MASKS["dive"] = bake(os.path.join(SRC, "v3_dive3_3_raw.png"), 40.0)
    return MASKS


def h_(x):
    return G.h_(x)


def draw_shape_whale(cv, gp, z, pitch, dv, clip, T, ghost=0):
    """gp 地面点、z 离地高度、pitch（正 = 头朝下）、dv 前进方向（地面）。按 15° 档取遮罩逐格画"""
    gp = G.snap(gp)
    e0 = G.norm((dv[0], dv[1] * SY))
    flip = e0[0] < 0
    base = math.degrees(math.atan2(e0[1], abs(e0[0])))   # 朝右时的地面方向角
    ang = base + math.degrees(pitch)
    pose = "dive" if pitch > 0.6 else "apex"
    q = int(round(ang / STEP)) * STEP
    q = max(-90, min(90, q))
    mk, lum = masks()[pose][q]
    h, w = mk.shape
    beat = int(math.floor(T * 15))
    th = math.radians(q)
    e = (math.cos(th), math.sin(th))
    n = (math.sin(th), -math.cos(th))   # 朝上的法线（朝右时）
    c = G.snap((gp[0], gp[1] - z - 12))
    if not clip and ghost == 0 and z > 6:   # 地上的水影（随高度缩放）
        sk = min(1.0, max(0.45, 1 - z / 160.0))
        rx, ry = 24 * sk, 6 * sk
        for iy in range(-int(ry), int(ry) + 1):
            for ix in range(-int(rx), int(rx) + 1):
                if (ix / rx) ** 2 + (iy / ry) ** 2 <= 1:
                    cv.pxa((gp[0] + ix * PX, gp[1] + iy * PX), (10, 26, 52), 0.4)
    cx, cy = w // 2, h // 2   # 整数中心：保持在 2 世界像素格上（半格会让相邻两行取整到同一行、出条纹）
    ga = [1.0, 0.3, 0.15][min(2, ghost)]
    edge_pts = []
    for y in range(h):
        for x in range(w):
            if not mk[y, x]:
                continue
            xx = (w - 1 - x) if flip else x
            ox, oy = x - cx, y - cy
            pp = (c[0] + (xx - cx) * PX, c[1] + oy * PX)
            if clip and pp[1] > gp[1] - 2:
                continue
            if ghost:
                cv.pxa(pp, W4[1], 0.35 * ga)
                continue
            u = ox * e[0] + oy * e[1]
            vv = ox * n[0] + oy * n[1]
            up = y == 0 or not mk[y - 1, x]
            dn = y == h - 1 or not mk[y + 1, x]
            if up:
                edge_pts.append((xx, y, u, vv))
                if h_(math.floor(u * 0.8 + beat * 1.6) * 1.37 + 0.3) > 0.25:
                    cv.px(pp, FOAM)
                    if x % 2 == 0:
                        cv.glow(pp, W4[3])
                else:
                    cv.pxa(pp, W4[2], 0.9)
                continue
            if dn:
                cv.pxa(pp, W4[2] if h_(math.floor(u * 0.7 + beat * 1.3) * 2.1) > 0.55 else W4[1], 0.75)
                continue
            # 内部：生图亮度定底（亮带沿背 / 腹），细长流线按节拍往后走；半透明
            L = lum[y, x]
            lane = math.floor(vv * 0.9 + 2.2 * math.sin(u * 0.13 - beat * 0.35))
            seg = h_(math.floor((u + beat * 2.5) / 7.0) * 1.91 + lane * 0.77)
            if lane % 3 == 0 and seg > 0.4:
                col, a = (W4[3], 0.9) if L > 0.62 else (W4[2], 0.85)
                if L > 0.62 and seg > 0.8:
                    cv.glow(pp, W4[3])
            elif L > 0.55:
                col, a = W4[2], 0.6
            elif L > 0.38:
                col, a = W4[1], 0.55
            else:
                col, a = W4[0], 0.5
            cv.pxa(pp, col, a)
    if ghost or clip or not edge_pts:
        return
    # 背鳍尖、尾鳍末端每拍碎出水花 / 甩水滴：取上沿里最高的几点（鳍尖）和体长方向最靠后的几点（尾）
    tip = sorted(edge_pts, key=lambda p: p[1])[:3]
    tail = sorted(edge_pts, key=lambda p: p[2])[:4]
    for k, (xx, y, u, vv) in enumerate(tip + tail):
        for j in range(3):
            ph = (beat + j + k) % 3
            sd = k * 3.7 + j * 1.3 + (beat - ph) * 0.41
            back = (2 + ph * 3 + h_(sd) * 3)
            up = (2 + ph * 2 - ph * ph * 0.8 + h_(sd + 1) * 2)
            dx = -e[0] * back * (-1 if flip else 1) + n[0] * up * (-1 if flip else 1)
            dy = -e[1] * back + n[1] * up
            p = (c[0] + (xx - cx + dx) * PX, c[1] + (y - cy + dy) * PX)
            cv.px(p, FOAM if ph == 0 else (W4[2] if ph == 1 else W4[1]))
    # 尾后散成 4 股水流
    tx, ty = tail[0][0], tail[0][1]
    for k in range(4):
        for j in range(24):
            wob = math.sin(j * 0.35 - beat * 1.4 + k * 1.3) * (1 + j * 0.1)
            if h_(j * 0.9 + k * 3.1 + beat * 0.37) < j / 28.0:
                continue
            bx = -e[0] * (j + 1) * (-1 if flip else 1) + n[0] * ((k - 1.5) * 1.8 + wob) * (-1 if flip else 1)
            by = -e[1] * (j + 1) + n[1] * ((k - 1.5) * 1.8 + wob)
            p = (c[0] + (tx - cx + bx) * PX, c[1] + (ty - cy + by) * PX)
            cv.pxa(p, W4[2] if j < 8 else (FOAM if j % 5 == 0 else W4[1]), 0.85 if j < 12 else 0.65)


def breach_column(cv, gp, T, k):
    """破水时从地面拉出的一段水柱（连着尾巴），边上白沫，k = 破水进度 0..1"""
    beat = int(math.floor(T * 15))
    hgt = 10 + 24 * k
    for z in range(int(hgt)):
        half = 5 - z * 0.08 + math.sin(z * 0.5 - beat) * 1.0
        for x in range(-int(half), int(half) + 1):
            p = (gp[0] + x * PX + z * 0.5 * PX, gp[1] - z * PX)
            edge = abs(x) >= int(half)
            if edge:
                cv.px(p, FOAM if h_(z * 1.3 + beat) > 0.4 else W4[2])
            else:
                cv.pxa(p, W4[2] if (x + z + beat) % 5 == 0 else W4[1], 0.6)
    for j in range(8):
        a = h_(j * 2.1 + beat) * math.pi
        r = 6 + h_(j + beat * 0.7) * 10
        cv.px((gp[0] + math.cos(a) * r * PX * (1 if j % 2 else -1), gp[1] - math.sin(a) * r * PX * 0.8), FOAM if j % 2 else W4[2])


def main():
    m = masks()
    # 整招 GIF：替换 S3 场景里的鲸；破水段另加水柱
    orig_draw = G.draw_orca

    def draw(cv, gp, z, pitch, dv, clip, T, ghost=0):
        if clip:
            k = min(1.0, max(0.0, (z + 22) / 26.0))
            breach_column(cv, G.snap(gp), T, k)
            draw_shape_whale(cv, gp, z + 6, -0.8, dv, False, T, ghost)   # 头朝上、整只在柱子上方
            return
        draw_shape_whale(cv, gp, z, pitch, dv, clip, T, ghost)
    G.draw_orca = draw
    lib = G.Lib()
    G.OX, G.OY = 150, 170
    fr = [G.column_frames(G.sc_s3(), lib)]
    frames = G.assemble(fr, ["生图剪影 + 程序水（试样）"], "S3 虎鲸")
    G.save_gif(frames, os.path.join(OUT, "shapewhale_s3.gif"))
    # 静帧对照：A3 原图 | 程序水 1 倍 | 4 倍
    cv = G.Canvas()
    G.OX, G.OY = 220, 200
    draw_shape_whale(cv, (0, 0), 50, 0.0, (1.0, 0.0), False, 0.4)
    still = cv.final()
    crop = still.crop((110, 60, 330, 190)).resize((880, 520), Image.NEAREST)
    a3 = Image.open(os.path.join(SRC, "v3_apex3_3_raw.png")).convert("RGB")
    arr = np.asarray(a3).astype(int)
    mag = (arr[..., 0] > 140) & (arr[..., 2] > 140) & (arr[..., 1] < 120) & (np.abs(arr[..., 0] - arr[..., 2]) < 90)
    bgc = np.zeros_like(arr); bgc[:] = (36, 46, 48)
    a3 = Image.fromarray(np.where(mag[..., None], bgc, arr).astype(np.uint8)); a3.thumbnail((880, 520))
    font = ImageFont.truetype("C:/Windows/Fonts/msyh.ttc", 20)
    sheet = Image.new("RGB", (880 * 2 + 30, 520 + 300 + 70), (14, 16, 20))
    d = ImageDraw.Draw(sheet)
    sheet.paste(a3, (10, 36)); d.text((14, 6), "A3 生图原图（只取剪影和明暗走向）", fill=(220, 226, 236), font=font)
    sheet.paste(crop, (900, 36)); d.text((904, 6), "程序水 · 4 倍局部", fill=(220, 226, 236), font=font)
    sheet.paste(still, (10, 590)); d.text((14, 562), "程序水 · 1 倍（实机大小）", fill=(220, 226, 236), font=font)
    sheet.save(os.path.join(OUT, "shapewhale_still.png"))
    print("ok")


if __name__ == "__main__":
    main()
