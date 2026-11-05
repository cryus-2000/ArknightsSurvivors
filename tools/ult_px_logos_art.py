#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""逻各斯终结技「句点」转平面画面（docs/258 §9，开关 ult/px_plane）：像素图形 Python 版 + 送审 GIF。只用 Python、不开 Godot。
用户点头后逐函数移植成 game/scripts/run/ult_px_lo.gd（两边一一对应）。模板见 docs/275 §5（艾丽妮试点）。

招式（ult_moves_c._lo_start / _lo_step / _lo_implode_v4，判定 / 时序 / 伤害不动）：确认释放 → 0.5 秒起手 → 时停（全屏去色 + 配乐压低）、
她面前一个圆形咒域（圆心在瞄准方向 330、半径 550 世界像素），域内每只敌人头顶浮现咒文，1.2 秒慢慢写满 →
1.2 秒「句点」：处决 / 咒文伤害同时结算，冲击帧（保留），随后整片真空压缩爆开（整招唯一、也是最大的一下）。

转平面画法（单位：美术像素 = 2 世界像素；贴地层压扁 SQ = 0.72；15 fps 节拍；坐标哈希，不用随机数）：
- 咒域：圆形贴地域，渐变填充（亮蓝边往中心渐暗，同 S3 定稿 docs/258 第三轮）+ 断续 2 格亮边 + 域内随机冒出的弯曲咒文段（同 S3 第七轮）。
- 标记：每只敌人头顶一段弯曲咒文（6 字左右，螺旋 / 波浪 / 弯钩 / 外甩四种曲线），按离她远近错开、一个个写出来再扭一下，每三字一个暗紫辉光。
- 冲击帧：白底黑剪影 / 黑底白剪影两拍（保留），剪影 = 所有标记咒文 + 咒域边。
- 最大那一下（只有这一下有冲击帧和慢动作）：2 拍预备（标记咒文往各自中心收拢、光点往圆心吸、圈内压暗）→ 圆心小亮核 2 拍 + 照地灯打满 + 轻震 →
  厚冲击环 3.5 拍推到咒域边（环后地面一闪）→ 圆心往外喷一团粒子云；冲击环扫到每个标记时那里炸一团闪烁粒子云（原版「ult_burst_s」粒子团，加强、换本人色）；
  被处决的怪物在冲击环扫到时整只炸成自身颜色的像素（引擎原有 kill_burst + 本色像素顺着冲击方向往外喷）。
- 收尾：咒域 0.6 秒淡掉，颜色随爆开回来（去色收回），几段咒文碎成细丝飘散。"""
import argparse, math, os, sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAIN = os.path.dirname(os.path.dirname(os.path.dirname(ROOT))) if ".claude" in ROOT else ROOT
PX = 2
SQ = 0.72
C = ["#28355f", "#495694", "#6a78ca", "#8c99ff", "#b4bdff", "#dce0ff", "#ffffff"]   # 同 fx_pxplane LG_C（house.js OP.logos）
INK = ["#0b0d22", "#161c3e"]
AC = "#a487ff"
GLOW = "#6a4fc0"
GL = ["111010010010011", "101111001001001", "110001010100011", "010111010010110", "100110101100111",
      "011100111001110", "101101010101101", "111100110100100", "010010111000101", "110101110100100"]
FILL = [(INK[0], 0.34), (INK[1], 0.34), (C[0], 0.32), (C[1], 0.33), (C[2], 0.36), (C[3], 0.38), (C[4], 0.38)]
TM = 1.2              # 咒文写满 → 句点（ult/lo_mark_v4）
BLAST_T = 2 / 15      # 预备 2 拍
CORE_T = 2 / 15       # 亮核 2 拍
SHOCK_T = 3.5 / 15    # 冲击环推到边 3.5 拍


def hx(s):
    s = s.lstrip("#")
    return tuple(int(s[i:i + 2], 16) for i in (0, 2, 4))


def h(i):
    return (math.sin(i * 12.9898) * 43758.5453) % 1.0


def hf(x, y, k=0):
    """坐标哈希 0–1（正弦哈希；整数异或哈希对连续序号分布不匀，粒子云会排成同心弧）"""
    return (math.sin(x * 12.9898 + y * 78.233 + k * 37.719) * 43758.5453) % 1.0


def ign(x, y):
    return (52.9829189 * ((0.06711056 * x + 0.00583715 * y) % 1.0)) % 1.0


def smooth(a, b, x):
    t = min(1.0, max(0.0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)


# ================================================================ 图形（返回美术像素坐标的点表，原点由调用方给）

def fill_tex(R):
    """咒域渐变：整盘（压扁椭圆）RGBA，1 贴图像素 = 1 美术像素（同 fx_pxplane._lg_fill，圆形版）"""
    RY = int(math.ceil(R * SQ))
    im = np.zeros((2 * RY + 1, 2 * R + 1, 4), np.uint8)
    n = len(FILL)
    for y in range(-RY, RY + 1):
        for x in range(-R, R + 1):
            q = math.hypot(x / R, y / (R * SQ))
            if q > 1:
                continue
            ang = math.atan2(y / SQ, x)
            v = q ** 2.4 * (n - 1) + (ign(x + 4000, y + 4000) - 0.5) * 1.15 + 0.35 * math.sin(ang * 5 + q * 7) * 0.5
            k = max(0, min(n - 1, int(math.floor(v + 0.5))))
            col, a = FILL[k]
            im[y + RY, x + R] = hx(col) + (int(a * 255),)
    return Image.fromarray(im, "RGBA")


def edge(R, pulse=False):
    """咒域边：2 格（外亮内墨），按噪声断续加厚"""
    out = []
    n = int(math.tau * R)
    for i in range(n):
        a = math.tau * i / n
        hv = h(i * 31 + 7)
        cx, cy = math.cos(a), math.sin(a) * SQ
        out.append((cx * R, cy * R, C[6] if pulse else (C[5] if hv > 0.66 else C[4]), 1.0))
        if hv > 0.45:
            out.append((cx * (R + 1), cy * (R + 1), C[4], 1.0))
        out.append((cx * (R - 1.2), cy * (R - 1.2), INK[1] if hv > 0.3 else C[1], 1.0))
    return out


def seg_path(sd, x0, y0, head0, n, typ, sg):
    """一段咒文的曲线（未压扁的地面坐标）：龟形走法每步 4 像素；0 螺旋收拢 / 1 波浪 / 2 弯钩 / 3 往外甩（同 fx_pxplane._lg_seg_path）"""
    x, y, head = x0, y0, head0
    pts = []
    for j in range(n):
        pts.append((x, y, head))
        if typ == 0:
            k = sg * (0.28 + 0.05 * j)
        elif typ == 1:
            k = 0.55 * math.sin(j * 1.1 + sd) * sg
        elif typ == 2:
            k = 0.05 * sg if j < n * 0.5 else 0.62 * sg
        else:
            k = 0.10 * sg
        head += k
        x += math.cos(head) * 4.0
        y += math.sin(head) * 4.0
    return pts


def write_glyphs(pts, lt, t_write, hold_to, sd, glow_every=3, squash=True):
    """一段咒文逐字写出（第一拍白、写出后扭一下），hold_to 之后从头到尾逐字褪；返回 [(x, y, 字号, 颜色, 不透明度, 辉光)]"""
    out = []
    n = len(pts)
    for j, (x, y, hd) in enumerate(pts):
        tin = t_write * j / max(1, n)
        tout = hold_to + 0.05 * j
        if lt < tin or lt > tout + 0.12:
            continue
        al = min(1.0, max(0.0, 1 - (lt - tout) / 0.12))
        age = lt - tin
        wig = round(math.sin(age * 22) * 1.2) if age < 0.27 else 0
        gx, gy = x - math.sin(hd) * wig, y + math.cos(hd) * wig
        if squash:
            gy *= SQ
        glow = (j + sd) % glow_every == 0
        col = C[6] if age < 1 / 15 else (AC if glow else C[5])
        out.append((gx, gy, sd + j * 3, col, al, glow and age >= 1 / 15 and al > 0.5))
    return out


def mark_path(sd):
    """敌人头顶那一段咒文的曲线（原点 = 标记中心）"""
    typ = int(h(sd + 9) * 4)
    n = 5 + int(h(sd + 3) * 3)        # 5–7 字
    sg = 1 if h(sd + 7) < 0.5 else -1
    head = (h(sd + 6) - 0.5) * 0.9 + (math.pi if h(sd + 5) < 0.5 else 0.0)
    pts = seg_path(sd, 0, 0, head, n, typ, sg)
    mx = sum(p[0] for p in pts) / n
    my = sum(p[1] for p in pts) / n
    return [(p[0] - mx, p[1] - my, p[2]) for p in pts]


def field_seg(sd, R):
    """咒域里随机冒出的咒文段（同 S3 第七轮）：位置按段号 + 轮次固定种子"""
    typ = int(h(sd + 9) * 4)
    n = 6 + int(h(sd + 3) * 5)
    a0 = math.tau * h(sd + 1)
    rf = 0.30 + 0.5 * h(sd + 2)
    x, y = math.cos(a0) * R * rf, math.sin(a0) * R * rf
    head = a0 + (math.pi / 2 if h(sd + 5) < 0.5 else -math.pi / 2) + (h(sd + 6) - 0.5) * 0.8
    if typ == 3:
        head = a0 + (h(sd + 6) - 0.5) * 0.6
    return seg_path(sd, x, y, head, n, typ, 1 if h(sd + 7) < 0.5 else -1)


def shock_at(R, d):
    k = min(1.0, max(0.0, (d / R - 0.5) / 0.5))
    return BLAST_T + (1 - math.sqrt(1 - k)) * SHOCK_T


def shock_ring(R, tau):
    """厚冲击环：半径 0.5 R → R（先快后慢），8 格（白 → 淡蓝 → 本色），环后 6–14 格地面一闪；到边后 2 拍淡掉"""
    out = []
    if tau < 0 or tau > SHOCK_T + 2 / 15:
        return out
    us = min(1.0, tau / SHOCK_T)
    rr = R * (0.5 + 0.5 * (1 - (1 - us) ** 2))
    fade = 1.0 if tau < SHOCK_T else max(0.0, 1 - (tau - SHOCK_T) / (2 / 15))
    cols = [C[6], C[6], C[6], C[5], C[5], C[4], C[4], C[3]] if tau < SHOCK_T else [C[5], C[5], C[4], C[4], C[3], C[3], C[2], C[2]]
    n = int(rr * 6.6) + 16
    for q in range(n):
        t = q / n * math.tau
        cx, cy = math.cos(t), math.sin(t) * SQ
        for j in range(8):
            out.append((round(cx * (rr - j)), round(cy * (rr - j)), cols[j], fade))
        if tau < SHOCK_T:
            for j2 in range(9, 18, 2):
                if (q + j2) % 3 == 0:
                    continue
                out.append((round(cx * (rr - j2)), round(cy * (rr - j2)), C[3], 0.45 * (1 - j2 / 18)))
    return out


def core(R, bf):
    """圆心亮核（2 拍）：一小团实心亮芯（0.06 R，白芯 + 淡蓝边）+ 一颗细长四芒星芒（横 0.4 R、竖 0.28 R，1–2 格粗）；不用平涂大椭圆，体量靠冲击环和粒子云。
    返回点表 [(x, y, 颜色, 发光)]"""
    out = []
    if bf < 0 or bf > 1:
        return out
    rc = R * (0.06 if bf == 0 else 0.045)
    for y in range(-int(rc * SQ) - 1, int(rc * SQ) + 2):
        for x in range(-int(rc) - 1, int(rc) + 2):
            q = math.hypot(x / rc, y / (rc * SQ))
            if q <= 1:
                out.append((x, y, (C[6] if q < 0.6 else C[5]) if bf == 0 else (C[5] if q < 0.6 else C[4]), q < 0.6))
    for (dx, dy, L) in ((1, 0, 0.4), (-1, 0, 0.4), (0, -1, 0.28), (0, 1, 0.2)):
        n = int(R * L * (1.0 if bf == 0 else 0.7))
        for i in range(int(rc), n):
            v = i / n
            c = C[6] if v < 0.4 and bf == 0 else C[5] if v < 0.7 else C[3]
            out.append((dx * i, dy * i * SQ, c, v < 0.4))
            if v < 0.3:
                out.append((dx * i + dy, dy * i * SQ + dx, C[4], False))
    return out


def cloud(age, sd, size, n=60):
    """闪烁粒子云（原版 ult_burst_s 粒子团加强、换本人色）：按面积铺开 → 逐拍闪烁、漂上去、越剩越少，1.2 秒散完；1–2 格闪点"""
    out = []
    if age < 0 or age > 1.2:
        return out
    fr = int(age * 15)
    u = min(1.0, age / 0.35)
    grow = 1 - (1 - u) ** 2
    for k in range(n):
        if age > 0.25 and (fr + k) % 3 == 0:
            continue
        if hf(k, sd, 84) < age / 1.2:
            continue
        a = math.tau * hf(k, sd, 81)
        r = size * math.sqrt(hf(k, sd, 82)) * grow + age * 4
        x, y = math.cos(a) * r, math.sin(a) * r * SQ - age * 10 * hf(k, sd, 83)
        hc = hf(k, sd, 85)
        c = C[6] if hc < 0.3 else C[5] if hc < 0.65 else C[4] if hc < 0.85 else AC
        if age > 0.6:
            c = C[5] if c == C[6] else C[4] if c == C[5] else c
        out.append((x, y, c, c == C[6] and age < 0.3, 2 if k % 3 == 0 else 1))
    return out


def spray(age, sd, out_ang, k, col):
    """怪物本色像素喷散（同艾丽妮 docs/275 §1.0）：col = (r, g, b) 0–1"""
    res = []
    if age < 0 or age > 1.3:
        return res
    lt = lambda c, a: tuple(min(1.0, x + (1 - x) * a) for x in c)
    dk = lambda c, a: tuple(x * (1 - a) for x in c)
    cols = [lt(col, 0.45), lt(col, 0.15), col, dk(col, 0.3)]
    for q in range(int(22 * min(1.4, k))):
        ang = out_ang + (hf(q, sd, 71) - 0.5) * 2.2
        spd = (30 + 70 * hf(q, sd, 72)) * k
        vh = 30 + 60 * hf(q, sd, 73)
        G = 260.0
        t_land = 2 * vh / G
        tt = min(min(age, 0.9), t_land)
        hgt = max(0.0, vh * tt - 0.5 * G * tt * tt) if min(age, 0.9) < t_land else 0.0
        c = cols[q % 4]
        hot = age < 2 / 15 and q % 3 == 0
        if hot:
            c = (1.0, 1.0, 1.0)
        al = 1.0 if age < 0.9 else max(0.0, (1.3 - age) / 0.4)
        res.append((math.cos(ang) * spd * tt, math.sin(ang) * spd * tt * SQ - hgt, c + (al,), hot, 2 if q % 3 != 2 else 1))
    return res


# ================================================================ 送审 GIF

W, H = 1400, 900
ORG = (230, 470)            # 她的脚底（世界像素 = 屏幕像素）
D = (1.0, 0.0)
CC = (ORG[0] + 330, ORG[1])
R_W = 550.0
R = int(R_W / PX)           # 275 美术像素
TIP = (ORG[0] + 40, ORG[1] - 36)
GROUND = (36, 46, 48)
FONT = "C:/Windows/Fonts/msyh.ttc"


def enemies():
    out = []
    for i in range(30):
        a = math.tau * h(i * 3.1 + 0.7)
        r = 60 + 460 * math.sqrt(h(i * 5.3 + 1.9))
        p = (CC[0] + math.cos(a) * r, CC[1] + math.sin(a) * r * SQ)
        out.append({"p": p, "d": math.hypot(p[0] - CC[0], (p[1] - CC[1]) / SQ), "kill": i % 4 != 3, "sd": 101 + i * 7})
    return out


ENS = enemies()


def timeline():
    """真实时间 15 fps 一帧：[(阶段, 招式游戏时间, 冲击帧拍 -1/0/1, 是否起震)]。慢动作 = 同一游戏时间拍子重复（游戏里 floor(g.t × 15) 也是这样）"""
    out = []
    for i in range(8):   # 起手 0.5 秒
        out.append(("wu", (i + 1) / 8, -1))
    t = 0.0
    while t < TM - 1e-6:
        out.append(("cast", t, -1))
        t += 1 / 15
    t = TM
    out += [("cast", t, 0), ("cast", t, 1)]   # 冲击帧两拍（保留）
    out += [("hold", t, -1)] * 2               # 顿帧（世界停住，压暗吸气）
    for i in range(8):                         # 慢动作：0.3 倍 0.5 秒
        t += 0.3 / 15
        out.append(("cast", t, -1))
    for i in range(2):                         # 0.15 秒加速回 1 倍
        t += (0.3 + 0.7 * (i + 1) / 2) / 15
        out.append(("cast", t, -1))
    while t < TM + 1.7:
        t += 1 / 15
        out.append(("cast", t, -1))
    return out


def render(ph, t, hfk, sprites, ftex):
    ENEMY, LOGOS = sprites
    img = Image.new("RGBA", (W, H), GROUND + (255,))
    g = np.asarray(img).copy()
    rng = np.random.default_rng(7)
    nz = rng.integers(-5, 6, size=(H // 2, W // 2, 1))
    g[..., :3] = np.clip(g[..., :3].astype(int) + np.repeat(np.repeat(nz, 2, 0), 2, 1), 0, 255)
    img = Image.fromarray(g.astype(np.uint8), "RGBA")
    emit = Image.new("RGB", (W, H), (0, 0, 0))
    ed = ImageDraw.Draw(emit)
    dr = ImageDraw.Draw(img)

    def put(x, y, c, glow=False, a=1.0, sz=1):
        x, y = round(x / 2) * 2, round(y / 2) * 2
        if not (0 <= x < W - 4 and 0 <= y < H - 4):
            return
        cc = hx(c) if isinstance(c, str) else tuple(int(v * 255) for v in c[:3])
        if len(c) == 4 and not isinstance(c, str):
            a = a * c[3]
        if a < 1.0:
            base = img.getpixel((x, y))
            cc = tuple(int(base[i] * (1 - a) + cc[i] * a) for i in range(3))
        dr.rectangle([x, y, x + PX * sz - 1, y + PX * sz - 1], fill=cc + (255,))
        if glow:
            ed.rectangle([x, y, x + PX * sz - 1, y + PX * sz - 1], fill=cc[:3])

    def glyph(x, y, gi, col, a=1.0, glow=False):
        s = GL[gi % len(GL)]
        x0, y0 = round(x / 2) * 2 - PX, round(y / 2) * 2 - 2 * PX
        for k in range(15):
            if s[k] == "1":
                put(x0 + (k % 3) * PX, y0 + (k // 3) * PX, col, glow=glow, a=a)

    ct = t if ph in ("cast", "hold") else -1.0
    age = ct - TM if ct >= TM else -1.0   # 爆开后的游戏秒
    killed = lambda e: e["kill"] and age >= shock_at(R, e["d"] / PX)

    # ---- 冲击帧：整屏底 + 剪影（全部标记咒文 + 咒域边）
    if hfk >= 0:
        bg = (235, 232, 226) if hfk == 0 else (5, 5, 8)
        fg = (0, 0, 0) if hfk == 0 else (255, 255, 255)
        im2 = Image.new("RGB", (W, H), bg)
        d2 = ImageDraw.Draw(im2)
        def sp(x, y):
            x, y = round(x / 2) * 2, round(y / 2) * 2
            d2.rectangle([x, y, x + 1, y + 1], fill=fg)
        for q in edge(R):
            sp(CC[0] + q[0] * PX, CC[1] + q[1] * PX)
        for e in ENS:
            m = (e["p"][0], e["p"][1] - 46)
            for j, (gx, gy, hd) in enumerate(mark_path(e["sd"])):
                gs = GL[(e["sd"] + j * 3) % len(GL)]
                for k in range(15):
                    if gs[k] == "1":
                        sp(m[0] + gx * PX - PX + (k % 3) * PX, m[1] + gy * SQ * PX - 2 * PX + (k // 3) * PX)
        return im2

    # ---- 地面层：咒域填充 + 边
    if ct >= 0:
        fin = min(1.0, ct / 0.3)
        fout = 1.0 if age < BLAST_T + CORE_T else max(0.0, 1 - (age - BLAST_T - CORE_T) / 0.6)
        a_f = fin * fout
        if a_f > 0:
            arr = np.asarray(ftex).astype(np.float32)
            arr[..., 3] *= a_f
            ft = Image.fromarray(arr.astype(np.uint8), "RGBA").resize((ftex.width * PX, ftex.height * PX), Image.NEAREST)
            img.alpha_composite(ft, dest=(int(CC[0] - ft.width // 2), int(CC[1] - ft.height // 2)))
            dr = ImageDraw.Draw(img)
            for q in edge(R, pulse=False):
                put(CC[0] + q[0] * PX, CC[1] + q[1] * PX, q[2], a=a_f)
    # 敌人影子 + 本体（处决的在冲击环扫到时崩解，不再画本体）
    for e in ENS:
        if killed(e):
            continue
        dr.ellipse([e["p"][0] - 10, e["p"][1] + 1, e["p"][0] + 10, e["p"][1] + 7], fill=(18, 22, 24, 255))
    for e in ENS:
        if killed(e):
            continue
        img.alpha_composite(ENEMY, dest=(int(e["p"][0] - ENEMY.width // 2), int(e["p"][1] - ENEMY.height + 6)))
    img.alpha_composite(LOGOS, dest=(round((ORG[0] - 64) / 2) * 2, round((ORG[1] - 120) / 2) * 2))
    dr = ImageDraw.Draw(img)
    lights = []

    # ---- 起手：笔尖光点螺旋收进来 + 身边一段咒文开始写
    if ph == "wu":
        for i in range(12):
            a = math.tau * i / 12 + t * 3
            r = 40 * (1 - t) ** 1.3 + 2
            put(TIP[0] + math.cos(a) * r * PX, TIP[1] + math.sin(a) * r * SQ * PX, C[6] if t > 0.6 else C[4], glow=t > 0.6)
        pts = seg_path(5, -14, -30, -0.4, 7, 1, 1)
        for (gx, gy, gi, col, al, gw) in write_glyphs(pts, t * 0.5, 0.45, 9.0, 5):
            glyph(ORG[0] + gx * PX, ORG[1] + gy * PX, gi, col, al, gw)
        lights.append((TIP[0], TIP[1], 90, 0.35 * t, (0.7, 0.72, 1.1)))

    if ct >= 0:
        # 域内随机咒文段（同 S3 第七轮：同屏 4 段，逐字写出、停一会儿、逐字褪）
        if age < BLAST_T:
            tb = math.floor(ct * 15) / 15
            for ks in range(4):
                P = 2.1 + 0.23 * (ks % 3)
                lt0 = tb + P * ks / 4
                cyc = math.floor(lt0 / P)
                lt = lt0 - cyc * P
                sd = ks * 977 + cyc * 131
                pts = field_seg(sd, R)
                n = len(pts)
                hold = 0.06 * n + 0.8 + 0.4 * h(sd + 8)
                for (gx, gy, gi, col, al, gw) in write_glyphs(pts, lt, 0.06 * n, hold, sd):
                    if math.hypot(gx, gy / SQ) > R * 0.95:
                        continue
                    glyph(CC[0] + gx * PX, CC[1] + gy * PX, gi, col, al * 0.85, gw)
        # 标记：每只头顶一段弯曲咒文，按远近错开写出；句点后 2 拍往各自中心收拢
        for e in ENS:
            m = (e["p"][0], e["p"][1] - 46)
            dl = 0.4 * min(1.0, e["d"] / (R_W * 2))
            pts = mark_path(e["sd"])
            if age < 0:
                for (gx, gy, gi, col, al, gw) in write_glyphs(pts, ct - dl, (TM - dl) * 0.8, 9.0, e["sd"]):
                    glyph(m[0] + gx * PX, m[1] + gy * PX, gi, col, al, gw)
            elif age < BLAST_T:
                k = (age / BLAST_T) ** 1.5
                for j, (gx, gy, hd) in enumerate(pts):
                    glyph(m[0] + gx * (1 - k) * PX, m[1] + gy * SQ * (1 - k) * PX, e["sd"] + j * 3, C[6] if k > 0.5 else C[5], 1.0, k > 0.5)
                for q in range(2):   # 光点往圆心吸
                    u = min(1.0, k * 1.2 + 0.1 * q)
                    put(m[0] + (CC[0] - m[0]) * u, m[1] + (CC[1] - 12 - m[1]) * u, C[6], glow=True)
        if ct < TM:
            lights.append((CC[0], CC[1], R_W * 0.6, 0.25 * min(1.0, ct / 0.3), (0.62, 0.66, 1.15)))
    if age >= 0:
        # 预备压暗
        if age < BLAST_T + 0.2:
            kd = min(1.0, age / BLAST_T) * (1.0 if age < BLAST_T else max(0.0, 1 - (age - BLAST_T) / 0.2))
            if kd > 0 or ph == "hold":
                ov = Image.new("RGBA", (W, H), (0, 0, 0, 0))
                ImageDraw.Draw(ov).ellipse([CC[0] - R_W * 1.05, CC[1] - R_W * 1.05 * SQ, CC[0] + R_W * 1.05, CC[1] + R_W * 1.05 * SQ], fill=(0, 0, 5, int(255 * 0.28 * max(kd, 0.6 if ph == "hold" else 0))))
                img.alpha_composite(ov)
                dr = ImageDraw.Draw(img)
        if age >= BLAST_T:
            tau = age - BLAST_T
            for q in core(R, int(math.floor(tau * 15))):
                put(CC[0] + q[0] * PX, CC[1] - 12 + q[1] * PX, q[2], glow=q[3])
            if 0 <= tau < CORE_T:
                lights.append((CC[0], CC[1], 240, 0.9, (0.85, 0.85, 1.3)))
            for q in shock_ring(R, tau):
                put(CC[0] + q[0] * PX, CC[1] + q[1] * PX, q[2], a=q[3])
            for q in cloud(tau, 777, R * 0.6, 160):
                put(CC[0] + q[0] * PX, CC[1] - 12 + q[1] * PX, q[2], glow=q[3], sz=q[4])
        # 冲击环扫到每个标记：那里一团闪烁粒子云；处决的怪整只崩解成本色像素
        for i, e in enumerate(ENS):
            ta = age - shock_at(R, e["d"] / PX)
            if ta < 0:
                continue
            m = (e["p"][0], e["p"][1] - 40)
            if i < 24:
                for q in cloud(ta, e["sd"], 40, 60):
                    put(m[0] + q[0] * PX, m[1] + q[1] * PX, q[2], glow=q[3], sz=q[4])
            if e["kill"]:
                oa = math.atan2((e["p"][1] - CC[1]) / SQ, e["p"][0] - CC[0])
                for q in spray(ta, e["sd"], oa, 1.6, ECOL):
                    put(e["p"][0] + q[0] * PX, e["p"][1] - 14 + q[1] * PX, q[2], glow=q[3], sz=q[4])
                for (px_, py_, col) in KB:   # 引擎原有的按贴图像素碎开（kill_burst）近似
                    a2 = oa + (hf(px_, py_, e["sd"]) - 0.5) * 2.6
                    sp = 40 + 90 * hf(py_, px_, e["sd"] + 1)
                    tt = min(ta, 0.8)
                    vh = 40 + 50 * hf(px_ + 3, py_, e["sd"])
                    hgt = max(0.0, vh * tt - 130 * tt * tt)
                    al = 1.0 if ta < 0.6 else max(0.0, (1.0 - ta) / 0.4)
                    if al > 0:
                        put(e["p"][0] + (px_ + math.cos(a2) * sp * tt) * PX * 0.5, e["p"][1] - 20 + (py_ + math.sin(a2) * sp * tt * SQ - hgt) * PX * 0.5, col + (al,))
        # 收尾：几段咒文碎成细丝飘散
        if age > 0.4:
            for ks in range(3):
                sd = 4000 + ks * 53
                pts = field_seg(sd, int(R * 0.8))
                for (gx, gy, gi, col, al, gw) in write_glyphs(pts, age - 0.4, 0.2, 0.5 + 0.2 * ks, sd):
                    glyph(CC[0] + gx * PX, CC[1] + gy * PX - (age - 0.4) * 20, gi, C[4], al * 0.7)
        if BLAST_T + CORE_T <= age < 1.0:
            lights.append((CC[0], CC[1], R_W * 0.7, 0.55 * (1 - (age - BLAST_T - CORE_T) / 0.8), (0.65, 0.65, 1.2)))

    # ---- 光照 + 发光层 + 去色（时停）
    glow = np.asarray(emit.filter(ImageFilter.GaussianBlur(3))).astype(np.float32) * 0.6
    base = np.asarray(img.convert("RGB")).astype(np.float32) * 0.8
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    lit = np.zeros((H, W, 3), np.float32)
    for (lx, ly, lr, li, lc) in lights:
        dd = np.sqrt((xx - lx) ** 2 + ((yy - ly) / 0.72) ** 2) / lr
        lit += (li * np.clip(1.0 - dd, 0.0, 1.0) ** 2)[..., None] * np.array(lc, np.float32)
    base = base * (1.0 + lit * 1.3) + lit * 40.0
    out = np.clip(base + glow, 0, 255)
    # 时停去色：从她往外扩的去色波（0.6 秒扫过，原有的反色 / 去色波，后处理着色器，不改），爆开那一下 0.25 秒收回
    ds = 0.0
    if ph == "wu":
        ds = 0.0
    elif ct >= 0:
        ds = 0.55 * min(1.0, ct / 0.4) if age < 0 else (0.55 if ph == "hold" else 0.55 * max(0.0, 1 - age / 0.25))
    if ds > 0:
        wave = 1.0 if ct > 0.6 else (np.sqrt((xx - ORG[0]) ** 2 + ((yy - ORG[1]) / 0.72) ** 2) < ct / 0.6 * 1400)[..., None].astype(np.float32)
        lum = out.mean(axis=2, keepdims=True)
        out = out * (1 - ds * wave) + lum * ds * wave
    if ph == "hold":
        out = out * 0.85
    return Image.fromarray(out.astype(np.uint8), "RGB")


def sprite(path, n, fi=0):
    im = Image.open(path).convert("RGBA")
    fw = im.width // n
    return im.crop((fi * fw, 0, (fi + 1) * fw, im.height))


def main():
    global ECOL, KB
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join(MAIN, "Claude outputs", "ult_px_logos_1105"))
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    fdir = os.path.join(a.out, "new_frames")
    os.makedirs(fdir, exist_ok=True)
    en = sprite(os.path.join(ROOT, "game", "art", "enemies", "offspring", "e_offspring@2x.png"), 4)
    arr = np.asarray(en).astype(np.float32)
    op = arr[..., 3] > 128
    ECOL = tuple((arr[op][:, :3].mean(axis=0) / 255).tolist())
    ys, xs = np.nonzero(op[::2, ::2])
    KB = [(int(x - op.shape[1] // 4), int(y - op.shape[0] // 4), tuple((arr[y * 2, x * 2, :3] / 255).tolist())) for y, x in list(zip(ys, xs))[::5]]
    arr[..., :3] = arr[..., :3] * 0.32 + np.array([10, 12, 14])
    ENEMY = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")
    LOGOS = sprite(os.path.join(ROOT, "game", "art", "operators", "logos", "op_logos_idle@2x.png"), 8)
    ftex = fill_tex(R)
    font = ImageFont.truetype(FONT, 18)
    tl = timeline()
    big, small, labs = [], [], []
    for tk, (ph, t, hfk) in enumerate(tl):
        im = render(ph, t, hfk, (ENEMY, LOGOS), ftex)
        if ph == "wu":
            lab = "起手（0.5 秒）"
        elif hfk >= 0:
            lab = "句点 · 冲击帧（保留）"
        elif ph == "hold":
            lab = "顿帧"
        elif t < TM:
            lab = "时停 · 咒文写满"
        else:
            ag = t - TM
            lab = "预备（收拢 / 压暗，慢动作）" if ag < BLAST_T else "爆开 · 亮核 + 冲击环" if ag < BLAST_T + SHOCK_T + CORE_T else "崩解 / 收尾"
        labs.append(lab)
        im.save(os.path.join(fdir, "f%03d.png" % tk))
        sheet = im.crop((80, 40, 1160, 860))
        dd = ImageDraw.Draw(sheet)
        dd.text((10, 8), "逻各斯终结技「句点」· 转平面版 · 1 倍 · 15 fps 原速 · " + lab, fill=(235, 225, 200) if hfk != 0 else (20, 20, 20), font=font)
        big.append(sheet)
        small.append(im.crop((CC[0] - 300, CC[1] - 210, CC[0] + 300, CC[1] + 210)).resize((1200, 840), Image.NEAREST))
    for frames, nm in ((big, "ult_logos_1x.gif"), (small, "ult_logos_x2.gif")):
        pick = frames[:: max(1, len(frames) // 12)][:12]
        mos = Image.new("RGB", (frames[0].width, frames[0].height * len(pick)))
        for i, fr in enumerate(pick):
            mos.paste(fr, (0, i * frames[0].height))
        pal = mos.quantize(colors=255, method=Image.MEDIANCUT)
        q = [f.quantize(palette=pal, dither=Image.NONE) for f in frames]
        q[0].save(os.path.join(a.out, nm), save_all=True, append_images=q[1:], duration=67, loop=0, optimize=True)
        print(nm, len(q), "帧", "%.0f KB" % (os.path.getsize(os.path.join(a.out, nm)) / 1024))
    return tl


if __name__ == "__main__":
    main()
