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
BODY = 100           # 体长（美术像素，= 200 世界像素，按 A3 吻到尾鳍末端的外框宽算；用户 11-05：落点水爆始终是最大的那一下）
STEP = 15            # 遮罩旋转档（度）
# 水色 4 阶（比上一版亮、通透）：深 / 中 / 浅 / 最亮（进发光层）
W4 = [(16, 64, 156), (24, 150, 226), (96, 214, 250), (206, 250, 255)]   # 照 A3：深海蓝 / 饱和青 / 亮青 / 亮青白（比上一版高两阶）
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


def bake(pose_path, base_angle, sc):
    """→ {角度档: (art 掩码 bool, art 亮度 0..1)}；角度 = 屏幕上体长方向（0 = 朝右水平，正 = 往下转）；sc = 原图像素 → 美术像素"""
    m, lum = key_mask(pose_path)
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
        vals = la[ma >= 0.5]
        if vals.size:   # 在身体内按分位数拉开明暗（缩小后亮带和暗带会混成中间调）
            lo, hi = np.percentile(vals, 20), np.percentile(vals, 97)
            la = (la - lo) / max(0.05, hi - lo)
        out[ang] = (ma >= 0.5, np.clip(la, 0, 1))
    return out


MASKS = {}
GAME_ART = os.path.join(G.ROOT, "game", "art", "fx", "pxp")


def mask_png(pose, ang):
    return os.path.join(GAME_ART, "pxp_ul_orcam_%s_a%s.png" % (pose, ("m%d" % -ang) if ang < 0 else str(ang)))


def masks():
    """体长按 A3 吻到尾鳍末端的外框宽算：BODY 美术像素；D3 用同一比例（同一批生图的同一个鲸，大小一致）。
    游戏里的帧条（pxp_ul_orcam_*.png：RGB = 亮度、A = 遮罩）在就读它（GIF 与游戏同一份数据），不在就从生图原图现烘"""
    if not MASKS and os.path.exists(mask_png("apex", 0)):
        for pose in ("apex", "dive"):
            MASKS[pose] = {}
            for ang in range(-90, 91, STEP):
                a = np.asarray(Image.open(mask_png(pose, ang)).convert("RGBA"))
                MASKS[pose][ang] = (a[..., 3] >= 128, a[..., 0].astype(np.float32) / 255.0)
        return MASKS
    if not MASKS:
        m, _ = key_mask(os.path.join(SRC, "v3_apex3_3_raw.png"))
        sc = BODY / float(m.shape[1])
        MASKS["sc"] = sc
        MASKS["apex"] = bake(os.path.join(SRC, "v3_apex3_3_raw.png"), 0.0, sc)
        MASKS["dive"] = bake(os.path.join(SRC, "v3_dive3_3_raw.png"), 40.0, sc)
    return MASKS


def h_(x):
    return G.h_(x)


def draw_shape_whale(cv, gp, z, pitch, dv, clip, T, ghost=0):
    """gp 地面点、z 离地高度、pitch（正 = 头朝下）、dv 前进方向（地面）。按 15° 档取遮罩逐格画（docs/266 §16，抄进 fx_pxplane_ul._draw_orca）：
    通透的水壳：最暗 / 次暗两阶半透明（α 0.35 / 0.45），只有细而稀的亮带、浪边、漩涡、气泡是实的；
    浪边上沿与鳍尖亮、腹部下沿断开变淡；每拍 6–10 颗 1–3 像素带短尾的水珠往后往上飞；尾后一股上粗下细的水柱连到地面，落地处一小圈水花"""
    gp = G.snap(gp)
    e0 = G.norm((dv[0], dv[1] * SY))
    flip = e0[0] < 0
    base = math.degrees(math.atan2(e0[1], abs(e0[0])))
    ang = base + math.degrees(pitch)
    pose = "dive" if pitch > 0.6 else "apex"
    q = int(round(ang / STEP)) * STEP
    q = max(-90, min(90, q))
    mk, lum = masks()[pose][q]
    h, w = mk.shape
    beat = int(math.floor(T * 15))
    th = math.radians(q)
    e = (math.cos(th), math.sin(th))
    n = (math.sin(th), -math.cos(th))
    sx = -1 if flip else 1
    c = G.snap((gp[0], gp[1] - z - h))
    cx, cy = w // 2, h // 2
    if not clip and ghost == 0 and z > 6:   # 地上的水影（随高度缩放）
        sk = min(1.0, max(0.45, 1 - z / 220.0))
        rx, ry = 30 * sk, 7 * sk
        for iy in range(-int(ry), int(ry) + 1):
            for ix in range(-int(rx), int(rx) + 1):
                if (ix / rx) ** 2 + (iy / ry) ** 2 <= 1:
                    cv.pxa((gp[0] + ix * PX, gp[1] + iy * PX), (10, 30, 70), 0.4)
    ga = [1.0, 0.3, 0.15][min(2, ghost)]
    flow = (beat * 2) % 12
    top_pts, tail_pt = [], None
    best_tail = 1e9
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
                cv.pxa(pp, W4[1], 0.3 * ga)
                continue
            u = ox * e[0] + oy * e[1]
            vv = ox * n[0] + oy * n[1]
            if u < best_tail:
                best_tail, tail_pt = u, (xx, y)
            topedge = y == 0 or not mk[y - 1, x]
            botedge = y == h - 1 or not mk[y + 1, x]
            sideedge = x == 0 or not mk[y, x - 1] or x == w - 1 or not mk[y, x + 1]
            if topedge:   # 上沿：实、亮
                cv.px(pp, W4[3])
                top_pts.append((xx, y))
                if x % 2 == 0:
                    cv.glow(pp, W4[3])
                continue
            if botedge:   # 腹部下沿：断开、变淡
                if h_(x * 0.9 + beat * 0.5) > 0.45:
                    cv.pxa(pp, W4[2], 0.55)
                continue
            if sideedge:
                cv.px(pp, W4[2])
                continue
            sxp = int(round(x + e[0] * flow))
            syp = int(round(y + e[1] * flow))
            L = lum[syp, sxp] if (0 <= sxp < w and 0 <= syp < h and mk[syp, sxp]) else lum[y, x]
            L = 0.65 * L + 0.35 * lum[y, x]
            # 亮带细而稀：只有亮度峰（> 0.7）且落在稀疏的流线上才画实色，其余是透明的水
            lane = math.floor(vv * 0.8 + 2.2 * math.sin(u * 0.13 - beat * 0.35))
            if L > 0.5 and lane % 2 == 0:
                cv.px(pp, W4[3] if L > 0.7 else W4[2])
                if L > 0.7 and (x + y + beat) % 3 == 0:
                    cv.glow(pp, W4[3])
            elif L > 0.22:
                cv.pxa(pp, W4[1], 0.5)
            else:
                cv.pxa(pp, W4[0], 0.4)
    if ghost or clip or not top_pts:
        return
    # 3 个小漩涡（实）
    for i, fu in enumerate((0.7, 0.45, 0.22)):
        ux = (fu - 0.5) * w
        vy = (-1 if i == 1 else 1) * h * 0.06
        px0 = cx + (ux * e[0] + vy * n[0]) * sx
        py0 = cy + ux * e[1] + vy * n[1]
        xi, yi = int(px0), int(py0)
        xm = (w - 1 - xi) if flip else xi
        if not (0 <= xm < w and 0 <= yi < h and mk[yi, xm]):
            continue
        rot = beat * 0.9 + i * 2.1
        for j in range(7):
            a = rot + j * 0.75
            r = 1.0 + j * 0.42
            cv.px((c[0] + (px0 - cx + math.cos(a) * r) * PX, c[1] + (py0 - cy + math.sin(a) * r * 0.8) * PX), W4[3] if j > 4 else W4[2])
    # 2–3 个往上漂的气泡（亮环 3×3 / 1 格）
    for i in range(3):
        ph = (beat + i * 3) % 8
        fx_ = 0.3 + 0.2 * i
        bx0 = cx + (fx_ - 0.5) * w * e[0] * sx
        by0 = cy + (fx_ - 0.5) * w * e[1] - ph * 1.6
        xm = int((w - 1 - bx0) if flip else bx0)
        if not (0 <= xm < w and 0 <= int(by0) < h and mk[int(by0), xm]):
            continue
        p = (c[0] + (bx0 - cx) * PX, c[1] + (by0 - cy) * PX)
        if i % 2 == 0:
            for qx, qy in ((-1, 0), (1, 0), (0, -1), (0, 1)):
                cv.px((p[0] + qx * PX, p[1] + qy * PX), W4[3])
        else:
            cv.px(p, W4[3])
    # 每拍 6–10 颗水珠（1–3 像素、带短尾），从上沿 / 鳍尖往后往上飞，3 拍落下
    nd = 6 + int(h_(beat * 0.91) * 5)
    top_sorted = sorted(top_pts, key=lambda p: p[1])
    for k in range(nd):
        for ph in range(3):
            sd = k * 3.7 + (beat - ph) * 0.41
            src = top_sorted[k] if k < 2 and k < len(top_sorted) else top_pts[int(h_(sd + 5.0) * len(top_pts)) % len(top_pts)]
            xx, y = src
            back = 2 + ph * 3 + h_(sd) * 4
            upz = 2 + ph * 3 - ph * ph * 1.3 + h_(sd + 1) * 3
            p = (c[0] + (xx - cx - e[0] * back * sx) * PX, c[1] + (y - cy - upz - e[1] * back) * PX)
            size = 1 + int(h_(sd + 2) * 3)
            size = max(1, size - ph)
            col = W4[3] if ph == 0 else (W4[2] if ph == 1 else W4[1])
            for qx in range(size):
                for qy in range(size):
                    cv.px((p[0] + qx * PX, p[1] + qy * PX), col)
            for t in range(1, 3):   # 短尾（逆着飞行方向）
                cv.px((p[0] + (e[0] * sx * t) * PX, p[1] + (t * 0.8 + e[1] * t) * PX), W4[2])
    # 尾后水柱（加粗、上粗下细）连到地面，落地处一小圈水花
    if tail_pt is None:
        return
    tx, ty = tail_pt
    t0 = (c[0] + (tx - cx) * PX, c[1] + (ty - cy) * PX)
    t1 = (gp[0] - e0[0] * 40, gp[1] - e0[1] * 40)
    for j in range(40):
        k = j / 39.0
        bx = t0[0] + (t1[0] - t0[0]) * k + (-e[0] * sx) * 20 * math.sin(k * math.pi) * PX
        by = t0[1] + (t1[1] - t0[1]) * k * k
        wob = math.sin(j * 0.5 - beat * 1.6) * 1.5
        half = 6.0 - 4.0 * k
        for s in range(-int(half) - 1, int(half) + 2):
            p = (bx + (wob + s) * PX, by)
            if abs(s) > half:
                if h_(j * 1.1 + s + beat) > 0.5:
                    cv.px(p, W4[3])
            elif (j + s + beat) % 5 == 0:
                cv.px(p, W4[3])
            else:
                cv.pxa(p, W4[2], 0.55)
    for i in range(16):   # 落地一小圈水花
        a = math.tau * i / 16 + beat * 0.3
        r = 6 + (beat % 3) * 2
        p = (t1[0] + math.cos(a) * r * PX, t1[1] + math.sin(a) * r * SY * PX - (2 if i % 3 == 0 else 0) * PX)
        if h_(i * 1.7 + beat) > 0.3:
            cv.px(p, W4[3] if i % 2 == 0 else W4[2])


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


def draw_whale(cv, gp, z, pitch, dv, clip, T, ghost=0):
    """整招用的入口（同 fx_pxplane_ul._draw_orca）：破水时先拉一段水柱、鲸头朝上在柱子上方"""
    if clip:
        if ghost == 0:
            breach_column(cv, G.snap(gp), T, min(1.0, max(0.0, (z + 22) / 26.0)))
        draw_shape_whale(cv, gp, z + 6, -0.8, dv, False, T, ghost)
        return
    draw_shape_whale(cv, gp, z, pitch, dv, clip, T, ghost)


def bake_game():
    """把两个姿态 × 13 档角度的遮罩写进游戏帧条（RGB = 亮度、A = 遮罩，1 美术像素一格）+ .import"""
    import hashlib
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import pxplane_bake_ulpianus as BK
    MASKS.clear()
    m, _ = key_mask(os.path.join(SRC, "v3_apex3_3_raw.png"))
    sc = BODY / float(m.shape[1])
    tot = 0
    for pose, path, base in (("apex", "v3_apex3_3_raw.png", 0.0), ("dive", "v3_dive3_3_raw.png", 40.0)):
        bk = bake(os.path.join(SRC, path), base, sc)
        for ang, (mk, lum) in bk.items():
            a = np.zeros(mk.shape + (4,), np.uint8)
            v = (np.clip(lum, 0, 1) * 255).astype(np.uint8)
            a[..., 0] = a[..., 1] = a[..., 2] = v
            a[..., 3] = np.where(mk, 255, 0)
            fn = mask_png(pose, ang)
            Image.fromarray(a, "RGBA").save(fn, optimize=True)
            tot += os.path.getsize(fn)
            imp = fn + ".import"
            if not os.path.exists(imp):
                b = os.path.basename(fn)
                hsh = hashlib.md5(("res://art/fx/pxp/" + b).encode()).hexdigest()
                open(imp, "w", encoding="utf-8", newline=chr(10)).write(BK.IMPORT_TMPL.format(f=b, hsh=hsh))
    print("遮罩帧条 26 张，%.1f KB" % (tot / 1024.0))
    MASKS.clear()


def main():
    if "--bake" in sys.argv:
        bake_game()
        return
    m = masks()
    # 整招 GIF：替换 S3 场景里的鲸；破水段另加水柱
    G.draw_orca = draw_whale
    lib = G.Lib()
    fr = [G.column_frames(G.sc_s3(), lib)]   # 画框高 420（sc_s3 里设）
    frames = G.assemble(fr, ["生图剪影 + 程序水（试样）"], "S3 虎鲸")
    G.save_gif(frames, os.path.join(OUT, "shapewhale_s3.gif"))
    # 静帧对照：A3 原图 | 程序水 1 倍 | 4 倍
    G.H = 270
    cv = G.Canvas()
    G.OX, G.OY = 200, 262
    draw_shape_whale(cv, (0, 0), 30, 0.0, (1.0, 0.0), False, 0.4)
    still = cv.final()
    arr2 = np.asarray(still).astype(int)
    diff = np.abs(arr2 - np.array(G.GROUND)[None, None, :]).sum(2) > 40
    ys, xs = np.nonzero(diff)
    x0, x1, y0, y1 = max(0, xs.min() - 6), min(still.width, xs.max() + 6), max(0, ys.min() - 6), min(still.height, ys.max() + 6)
    crop = still.crop((x0, y0, x1, y1))
    k4 = max(1, min(880 // crop.width, 520 // crop.height))
    crop = crop.resize((crop.width * k4, crop.height * k4), Image.NEAREST)
    a3 = Image.open(os.path.join(SRC, "v3_apex3_3_raw.png")).convert("RGB")
    arr = np.asarray(a3).astype(int)
    mag = (arr[..., 0] > 140) & (arr[..., 2] > 140) & (arr[..., 1] < 120) & (np.abs(arr[..., 0] - arr[..., 2]) < 90)
    bgc = np.zeros_like(arr); bgc[:] = (36, 46, 48)
    a3 = Image.fromarray(np.where(mag[..., None], bgc, arr).astype(np.uint8)); a3.thumbnail((880, 520))
    font = ImageFont.truetype("C:/Windows/Fonts/msyh.ttc", 20)
    sheet = Image.new("RGB", (880 * 2 + 30, 520 + 300 + 70), (14, 16, 20))
    d = ImageDraw.Draw(sheet)
    sheet.paste(a3, (10, 36)); d.text((14, 6), "A3 生图原图（只取剪影和明暗走向）", fill=(220, 226, 236), font=font)
    sheet.paste(crop, (900, 36)); d.text((904, 6), "程序水 · %d 倍" % k4, fill=(220, 226, 236), font=font)
    sheet.paste(still, (10, 590)); d.text((14, 562), "程序水 · 1 倍（实机大小）", fill=(220, 226, 236), font=font)
    sheet.save(os.path.join(OUT, "shapewhale_still.png"))
    print("ok")


if __name__ == "__main__":
    main()
