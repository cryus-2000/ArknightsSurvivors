#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""水月终结技 Q（水母群）转平面画面送审 GIF（docs/261 §8，ult/px_plane）：只用 Python、不开 Godot。

以原版为底（ult_moves_b._mz_* + ult_fx_c.mz_jelly_*，ult/mz_jelly 缺省开），时间轴、位置、节奏照原版：
  超必杀暂停 → 起手慢放（共用）→ 0–0.55 秒 9 只水母沿横扫半圆错开升起 → 0.32–0.77 秒各自压缩、全屏渐暗 →
  0.77 秒全部一起炸开（= 冲击帧，整招最大的那一下）→ 冲击帧两拍（白底黑剪影 / 黑底白剪影）→ 顿帧 → 0.25 倍慢放 0.6 秒 → 0.15 秒缓回 → 缠住漏网 → 收尾。
往上加的：水母换成海月水母像素画（用户 11-05「水月的水母应该是海月水母」）；压缩时每只一圈往里收的压扁细环 + 光点吸入；
  炸开那一下：每只中心小亮核 2 拍 + 一圈压扁厚冲击环 3–4 拍外推、推过的地面一闪 + 原版那团闪烁粒子云（换本人配色、收到像素格）+
  群心大冲击环推到横扫半径；被打中的怪炸成自身颜色的像素（崩解）；照地光；轻震 3px / 0.12 秒；漏网的缠绕改像素触手圈。
画法都按 1 特效像素 = 1 美术像素（2 世界像素）、15 fps 节拍、贴地压扁 0.72；不抽随机数，散布按坐标哈希。

输出（主仓库 Claude outputs/ult_px_mizuki_1105/）：ult_mizuki_1x.gif（1 倍整屏）、ult_mizuki_x2.gif（中心 2 倍）、new_frames/（逐帧 PNG）。
用法：python tools/ult_px_mizuki_gif.py [--out 目录]
"""
import argparse, json, math, os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAIN = os.path.dirname(os.path.dirname(os.path.dirname(ROOT))) if ".claude" in ROOT else ROOT
PX = 2
AW, AH = 640, 360              # 美术像素画布（= 1280 × 720 世界像素）
CX, CY = 320, 205              # 水月脚底（美术像素）
SQ = 0.72
FONT = "C:/Windows/Fonts/msyh.ttc"

def hx(s):
    s = s.lstrip("#")
    return (int(s[0:2], 16) / 255, int(s[2:4], 16) / 255, int(s[4:6], 16) / 255)

C8 = [hx(c) for c in ["#070a22", "#111a52", "#1e2f8f", "#3150c8", "#5a7cf0", "#9aa8ff", "#cfd6ff", "#ffffff"]]   # OP.mizuki（同 ak-mizuki-pp.js）
CY_ = hx("#6fe8ff")
CYL = hx("#c4f7ff")
AC = hx("#b98cff")
WHITE = (1.0, 1.0, 1.0)

# 原版参数（ult_moves_b._mz_start / ult_fx_c.mz_jelly_start）
R_W = 700.0                    # ult/mz_r（世界像素）
R = R_W / 2                    # 美术像素
HALF = math.radians(232) / 2   # ult/mz_arc
T0, TS = 0.15, 0.5             # ult/mz_rise、ult/mz_sweep
T_BURST = T0 + TS + 0.12       # jl_c1 = 0.77
JN = 9
AIM = -math.pi / 2             # 朝上放（录像里多数朝上）


def hsh(x, y, k=0):
    n = (int(x) * 374761393 + int(y) * 668265263 + int(k) * 2147483647) & 0xffffffff
    n = (n ^ (n >> 13)) * 1274126177 & 0xffffffff
    return (n ^ (n >> 16)) & 0xffffffff


def hf(x, y, k=0):
    return hsh(x, y, k) / 4294967295.0


class Cv:
    """美术像素画布：put（不透明 / 半透明叠）、emit（发光点，最后统一做柔光）"""
    def __init__(self):
        self.a = np.zeros((AH, AW, 3), np.float32)
        self.al = np.zeros((AH, AW), np.float32)   # 覆盖度（straight alpha），合成时盖在地面上
        self.g = np.zeros((AH, AW, 3), np.float32)

    def put(self, x, y, c, al=1.0):
        x, y = int(round(x)), int(round(y))
        if 0 <= x < AW and 0 <= y < AH and al > 0:
            a0 = self.al[y, x]
            na = al + a0 * (1 - al)
            self.a[y, x] = (np.array(c, np.float32) * al + self.a[y, x] * a0 * (1 - al)) / max(1e-6, na)
            self.al[y, x] = na

    def emit(self, x, y, c, k=0.8):
        x, y = int(round(x)), int(round(y))
        if 0 <= x < AW and 0 <= y < AH:
            self.g[y, x] += np.array(c, np.float32) * k


# ================================================================ 海月水母（同 ak-mizuki-pp.js aurelia，放大到终结技尺寸）
def aurelia(cv, cx, cy, Rb, ph, al=1.0, sil=None, bright=0.0, glow=True):
    """扁碟形半透明伞 + 四个马蹄形生殖腺环（苜蓿形，荧光紫）+ 伞沿细缘须 + 四条褶边口腕。sil = 纯色剪影（冲击帧）"""
    hh = max(2.0, Rb * 0.46)
    sag = Rb * 0.08
    def topY(u):
        return cy - hh * max(0.0, 1 - u * u) ** 0.6
    def botY(u):
        return cy + sag * (1 - u * u)
    body = tuple(min(1.0, c + (1 - c) * bright) for c in CY_)
    rim = CYL if bright < 0.5 else WHITE
    Ri = int(Rb)
    for x in range(-Ri, Ri + 1):
        u = x / Rb
        y0, y1 = int(round(topY(u))), int(round(botY(u)))
        for y in range(y0, y1 + 1):
            edge = y in (y0, y1) or abs(x) >= Ri - 0.5
            if sil is not None:
                cv.put(cx + x, y, sil, 1.0)
                continue
            if edge:
                cv.put(cx + x, y, rim, al)
                if glow and y == y0 and (x % 3 == 0):
                    cv.emit(cx + x, y, rim, 0.5 * al)
            elif y <= y0 + 1 and -0.65 < u < -0.1:
                cv.put(cx + x, y, WHITE, al)
                if glow:
                    cv.emit(cx + x, y, WHITE, 0.6 * al)
            else:
                cv.put(cx + x, y, body, 0.55 * al)
    # 四个马蹄形生殖腺环
    gy, rgx, rgy, rh = cy - hh * 0.42, Rb * 0.3, hh * 0.42, max(0.8, Rb * 0.16)
    for k in range(4):
        a = k / 4 * math.tau
        gx, gyy = cx + math.cos(a) * rgx, gy + math.sin(a) * rgy
        b = 0.0
        while b < math.tau:
            rel = (b - (a + math.pi)) % math.tau
            if 0.6 <= rel <= math.tau - 0.6:
                px_, py_ = gx + math.cos(b) * rh, gyy + math.sin(b) * rh * 0.7
                cv.put(px_, py_, sil if sil is not None else AC, 1.0 if sil is not None else al)
                if glow and sil is None:
                    cv.emit(px_, py_, AC, 0.55 * al)
            b += 0.35 / rh
    # 缘须
    for x in range(-Ri + 1, Ri):
        y = int(round(botY(x / Rb))) + 1
        L = 1 + ((x + 9) % 2) + (1 if Rb >= 20 and x % 3 == 0 else 0)
        for s in range(L):
            cv.put(cx + x, y + s, sil if sil is not None else (rim if s == 0 else C8[4]), 1.0 if sil is not None else al)
    # 口腕
    L = max(2.0, Rb * 1.15)
    for i in range(4):
        x0 = cx + (i / 3 - 0.5) * Rb * 0.5
        for s in range(1, int(L) + 1):
            x = x0 + math.sin(s * 0.45 + i * 1.7 + ph) * (0.8 + 2.2 * s / L)
            y = botY(0) + s
            w = 2 if s < L * 0.6 else 1
            for d in range(w):
                cv.put(x + d, y, sil if sil is not None else (CYL if d == 0 else C8[5]), 1.0 if sil is not None else al)
            if s % 3 == 1 and sil is None:
                cv.put(x + (-1 if i < 2 else 2), y, AC, al * 0.9)   # 褶边点荧光紫


# ================================================================ 水母位置（照 mz_jelly_start：沿扫过的半圆错开，0.3–0.85 R）
def jellies():
    a0 = AIM - HALF
    span = HALF * 2
    out = []
    for i in range(JN):
        hh = hf(i, 7, 1)
        ang = a0 + span * (i + 0.2 + 0.6 * hh) / JN
        d = R * (0.3 + 0.55 * hf(i, 7, 2))
        p = (CX + math.cos(ang) * d, CY + math.sin(ang) * d * SQ)
        Rb = 26 + 10 * hf(i, 7, 3)          # 伞半宽（美术像素）：原版贴图高 105–150 世界像素，这里伞 + 口腕总高约同
        out.append({"p": p, "d0": 0.04 * i + 0.1 * hh, "ph": hh * math.tau, "Rb": Rb, "fs": 1 if hf(i, 7, 4) < 0.5 else -1})
    return out


# ================================================================ 压缩那一段：往里收的压扁细环 + 光点吸入（原版 core / ring 收拢 → 像素版）
def shrink_ring(cv, c, r, al):
    n = int(r * 6.4) + 8
    for q in range(n):
        if (q * 7) % 5 == 0:
            continue
        t = q / n * math.tau
        cv.put(c[0] + math.cos(t) * r, c[1] + math.sin(t) * r * SQ, CYL, al)


# ================================================================ 炸开：亮核 / 冲击环 / 粒子云 / 崩解（同 docs/275 §1.2–1.3 的做法，配色换水月）
SHOCK_T = 3.5 / 15


def core(cv, c, bf, big=1.0):
    """中心小亮核（2 拍）：十字星芒 + 小实心（不平涂大圆）"""
    if bf < 0 or bf > 1:
        return
    r = (7 if bf == 0 else 5) * big
    for y in range(-int(r), int(r) + 1):
        for x in range(-int(r), int(r) + 1):
            d = math.hypot(x, y / SQ)
            if d <= r * 0.45:
                cv.put(c[0] + x, c[1] + y - 10, WHITE if bf == 0 else CYL, 1.0)
                cv.emit(c[0] + x, c[1] + y - 10, WHITE, 1.0)
            elif d <= r * 0.7 and (x == 0 or y == 0):
                cv.put(c[0] + x, c[1] + y - 10, CYL, 1.0)
    L = int(r * 2.4)
    for s in range(int(r * 0.5), L):   # 四芒
        k = 1 - s / L
        col = WHITE if k > 0.5 else CYL
        for dx, dy in ((s, 0), (-s, 0), (0, s * SQ), (0, -s * SQ)):
            cv.put(c[0] + dx, c[1] + dy - 10, col, 1.0)
            if k > 0.5:
                cv.emit(c[0] + dx, c[1] + dy - 10, col, 0.8)


def shock(cv, c, r0, r1, tau, thick=5, ground=True, main=True):
    """压扁厚冲击环：r0 → r1（先快后慢），厚 thick 格（白 → 青 → 紫），环后地面一闪；到边后 2 拍淡掉"""
    if tau < 0 or tau > SHOCK_T + 2 / 15:
        return
    us = min(1.0, tau / SHOCK_T)
    rr = r0 + (r1 - r0) * (1 - (1 - us) ** 2)
    fade = 1.0 if tau < SHOCK_T else max(0.0, 1 - (tau - SHOCK_T) / (2 / 15))
    if main:
        cols = [WHITE, WHITE, CYL, CY_, AC, C8[4], C8[3]][:thick] if tau < SHOCK_T else [CYL, CY_, AC, C8[4], C8[3], C8[2], C8[2]][:thick]
    else:   # 每只水母那一圈：细、青紫，不抢群心大环
        cols = [CYL, CY_, AC][:thick] if tau < SHOCK_T else [CY_, AC, C8[3]][:thick]
    n = int(rr * 6.6) + 16
    for q in range(n):
        t = q / n * math.tau
        if hf(q, int(r1), 31) < 0.08 + 0.5 * (1 - fade):   # 断口，越到边越碎
            continue
        cx, cy = math.cos(t), math.sin(t) * SQ
        for j in range(thick):
            cv.put(c[0] + cx * (rr - j), c[1] + cy * (rr - j), cols[j], fade)
            if j < 2 and tau < SHOCK_T:
                cv.emit(c[0] + cx * (rr - j), c[1] + cy * (rr - j), cols[j], 0.6 * fade)
        if ground and tau < SHOCK_T:   # 推过的地面一闪
            for j2 in range(thick + 2, thick + 10, 2):
                if (q + j2) % 3 == 0:
                    continue
                cv.put(c[0] + cx * (rr - j2), c[1] + cy * (rr - j2), C8[3], 0.45 * (1 - j2 / (thick + 10)))


def cloud(cv, c, age, sd, size, n=60):
    """原版那团闪烁粒子云（PF.particles ult_burst）→ 像素闪点：按面积铺满、往外炸开、逐拍闪烁、漂上去、越剩越少"""
    if age < 0 or age > 1.2:
        return
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
        x, y = c[0] + math.cos(a) * r, c[1] + math.sin(a) * r * SQ - 14 - age * 12 * hf(k, sd, 83)
        hc = hf(k, sd, 85)
        col = CYL if hc < 0.3 else CY_ if hc < 0.55 else AC if hc < 0.8 else C8[5]
        if age > 0.6:
            col = CY_ if col == CYL else C8[4] if col == CY_ else col
        sz = 2 if k % 3 == 0 else 1
        for dy in range(sz):
            for dx in range(sz):
                cv.put(x + dx, y + dy, col, 1.0)
        if col == CYL and age < 0.3:
            cv.emit(x, y, col, 0.7)


def spray(cv, c, age, sd, out_ang, k, col):
    """怪物崩解：代表色像素沿冲击方向喷散（游戏里另叠引擎 kill_burst 按贴图像素碎开）"""
    if age < 0 or age > 1.3:
        return
    def lt(c0, a):
        return tuple(min(1.0, x + (1 - x) * a) for x in c0)
    cols = [lt(col, 0.45), lt(col, 0.15), col, tuple(x * 0.7 for x in col)]
    for q in range(int(22 * min(1.4, k))):
        ang = out_ang + (hf(q, sd, 71) - 0.5) * 2.2
        spd = (30 + 70 * hf(q, sd, 72)) * k
        vh = 30 + 60 * hf(q, sd, 73)
        G = 260.0
        tl = 2 * vh / G
        t = min(age, 0.9)
        tt = min(t, tl)
        h = max(0.0, vh * tt - 0.5 * G * tt * tt) if t < tl else 0.0
        cc = WHITE if (age < 2 / 15 and q % 3 == 0) else cols[q % 4]
        al = 1.0 if age < 0.9 else max(0.0, (1.3 - age) / 0.4)
        x, y = c[0] + math.cos(ang) * spd * tt, c[1] - 6 + math.sin(ang) * spd * tt * SQ - h
        sz = 2 if q % 3 != 2 else 1
        for dy in range(sz):
            for dx in range(sz):
                cv.put(x + dx, y + dy, cc, al)


def shatter(cv, spr, anc, p, age, sd, out_ang):
    """引擎原有击杀碎屑（optical_particles.kill_burst）的示意：按怪物贴图像素碎开、沿冲击方向飞散、落地停一下熄灭"""
    if age < 0 or age > 1.0:
        return
    h, w = spr.shape[:2]
    x0, y0 = p[0] - w * anc[0], p[1] - h * anc[1]
    k = 0
    for yy in range(0, h, 2):
        for xx in range(0, w, 2):
            if spr[yy, xx, 3] < 0.5:
                continue
            k += 1
            a = out_ang + (hf(xx, yy, sd) - 0.5) * 1.6
            sp = 40 + 80 * hf(yy, xx, sd + 1)
            vh = 20 + 50 * hf(xx + yy, sd, 3)
            t = min(age, 0.7)
            tl = 2 * vh / 260.0
            tt = min(t, tl)
            hgt = max(0.0, vh * tt - 130.0 * tt * tt) if t < tl else 0.0
            x = x0 + xx + math.cos(a) * sp * tt
            y = y0 + yy + math.sin(a) * sp * tt * SQ - hgt
            c = tuple(spr[yy, xx, :3])
            if age < 2 / 15:
                c = tuple(min(1.0, v + 0.5) for v in c)
            al = 1.0 if age < 0.7 else (1.0 - age) / 0.3
            cv.put(x, y, c, al)
            cv.put(x + 1, y, c, al)


def coil(cv, e, t, er):
    """漏网缠绕（原版 fx_mizuki_bind_ring 1.2 秒）→ 同 S2 的像素触手圈（1.25 圈矮螺旋，一勒一松）"""
    f = int(t * 15) % 6
    sq_ = [0, 1, 1.5, 1, 0, -0.5][f]
    rx = er + 2 - sq_ * 0.6
    ry = rx * SQ * 0.62
    TURN = math.tau * 1.25
    a = 0.0
    while a < TURN:
        z = 3 + a / TURN * 5
        s = math.sin(a)
        x, y = e[0] + math.cos(a) * rx, e[1] + s * ry - z
        front = s > 0
        w = 3 - a / TURN * 1.2
        for d in np.arange(0, w, 0.5):
            ci = 1 if d < 0.8 else (3 if front else 2) if d < w - 1 else (5 if front else 3)
            cv.put(x, y + d - w / 2, C8[ci], 1.0)
        if front and int(a * 3) % 4 == 0:
            cv.put(x, y, AC, 1.0)
        a += 0.5 / rx


# ================================================================ 场景
def ground_img():
    t = Image.open(os.path.join(ROOT, "game/art/world/terrain/terrain_regions.png")).convert("RGB")
    tile = t.crop((0, 0, 32, 32))
    bg = Image.new("RGB", (AW, AH))
    for y in range(0, AH, 32):
        for x in range(0, AW, 32):
            bg.paste(tile, (x, y))
    return np.asarray(bg).astype(np.float32) / 255.0


def frames_of(path, n):
    im = Image.open(path).convert("RGBA")
    fw = im.width // n
    return [im.crop((i * fw, 0, (i + 1) * fw, im.height)) for i in range(n)]


ENEMY_DEFS = {"runner": ("game/art/enemies/runner/e_runner@2x.png", 4, (0.56, 0.875), (0.55, 0.62, 0.8)),
              "slider": ("game/art/enemies/slider/e_slider@2x.png", 4, (0.5, 0.85), (0.45, 0.7, 1.0)),
              "skimmer": ("game/art/enemies/skimmer/e_skimmer@2x.png", 4, (0.5, 0.85), (0.4, 0.9, 0.9))}


def enemy_sprites():
    out = {}
    for k, (p, n, anc, col) in ENEMY_DEFS.items():
        fp = os.path.join(ROOT, p)
        if not os.path.exists(fp):
            continue
        fr = frames_of(fp, n)[0]
        fr = fr.resize((max(1, fr.width * 3 // 8), max(1, fr.height * 3 // 8)), Image.NEAREST)   # @2x → 美术像素 × 体型 1.5
        out[k] = (np.asarray(fr).astype(np.float32) / 255.0, anc, col)
    return out


def enemies():
    es = []
    kinds = list(ENEMY_DEFS)
    for i in range(30):
        a = AIM - HALF + 2 * HALF * hf(i, 3, 1)
        d = R * (0.18 + 0.78 * math.sqrt(hf(i, 3, 2)))
        p = (CX + math.cos(a) * d, CY + math.sin(a) * d * SQ)
        if not (8 < p[0] < AW - 8 and 14 < p[1] < AH - 4):
            continue
        es.append({"p": p, "k": kinds[i % len(kinds)], "id": i, "grab": i % 5 == 0})
    return es


def blit(img, spr, x, y, anc, dark=None, al=1.0):
    a = spr[..., 3:4] * al
    h, w = spr.shape[:2]
    x0, y0 = int(round(x - w * anc[0])), int(round(y - h * anc[1]))
    xa, ya, xb, yb = max(0, x0), max(0, y0), min(AW, x0 + w), min(AH, y0 + h)
    if xa >= xb or ya >= yb:
        return
    s = spr[ya - y0:yb - y0, xa - x0:xb - x0]
    aa = a[ya - y0:yb - y0, xa - x0:xb - x0]
    rgb = s[..., :3] if dark is None else np.broadcast_to(np.array(dark, np.float32), s[..., :3].shape)
    img[ya:yb, xa:xb] = img[ya:yb, xa:xb] * (1 - aa) + rgb * aa


# ================================================================ 时间轴（拍 → 阶段 + 招式游戏时间 + 冲击帧拍）
SF, WU = 5, 8


def timeline():
    out = [("sf", 0.0, -1)] * SF + [("wu", (i + 1) / WU, -1) for i in range(WU)]
    t = 0.0
    while t < T_BURST - 1e-6:
        out.append(("cast", t, -1))
        t += 1 / 15
    t = T_BURST
    out += [("cast", t, 0), ("cast", t, 1)]          # 冲击帧两拍
    out += [("cast", t, -1)] * 2                      # 顿帧 0.16 秒（ult/mz_burst_stop）
    for i in range(9):                                # 0.25 倍慢放 0.6 秒（ult/imp_slow_t 0.45 + 水月 0.15）
        t += 0.25 / 15
        out.append(("cast", t, -1))
    for i in range(2):                                # 0.15 秒缓回（任务单口径）
        t += (0.25 + 0.75 * (i + 1) / 2) / 15
        out.append(("cast", t, -1))
    while t < T_BURST + 1.5:
        t += 1 / 15
        out.append(("cast", t, -1))
    return out


def render(ph, t, hfb, JL, ES, SPR, mz_frames, G):
    img = G.copy()
    cv = Cv()
    dim = 0.0
    if ph == "sf":
        dim = 0.55
    elif ph == "wu":
        dim = 0.35
    elif t < T_BURST:
        kd = min(1.0, max(0.0, (t - (T_BURST - 0.45)) / 0.45))
        dim = 0.5 * kd * kd                            # 原版：压缩时全屏渐暗（蓄力反差）
    tb = t - T_BURST                                   # 炸开后的游戏秒
    shake = (0, 0)
    if ph == "cast" and 0 <= tb < 0.12 and hfb < 0:
        shake = (int(round(1.5 * math.sin(tb * 90))), int(round(1.0 * math.cos(tb * 70))))   # 3 世界像素 ≈ 1.5 美术像素
    # 地面与单位
    if dim > 0:
        img *= (1 - dim)
    for e in sorted(ES, key=lambda e: e["p"][1]):
        spr, anc, col = SPR[e["k"]]
        dead = ph == "cast" and tb >= 0 and not e["grab"]
        if dead:
            continue
        blit(img, spr, e["p"][0], e["p"][1], anc)
    mzi = mz_frames[int((t if ph == "cast" else 0) * 6.75) % len(mz_frames)]
    blit(img, mzi, CX, CY, (0.5, 151 / 192))
    if ph == "wu":   # 起手：共用的脚下光圈收紧 + 本人色光点往身上收（这里只示意）
        for i in range(14):
            a = math.tau * i / 14 + t * 3
            r = 60 * (1 - t) + 6
            cv.put(CX + math.cos(a) * r, CY - 20 + math.sin(a) * r * SQ, CYL)
            cv.emit(CX + math.cos(a) * r, CY - 20 + math.sin(a) * r * SQ, CYL, 0.6)
    if ph == "cast":
        if tb < 0:
            # 水母升起 / 漂浮 / 压缩（原版 mz_jelly_step）
            kp = min(1.0, max(0.0, (t - (T_BURST - 0.45)) / 0.45))
            kq = kp * kp
            for j in JL:
                k = min(1.0, max(0.0, (t - j["d0"]) / 0.55))
                if k <= 0:
                    continue
                ke = 1 - (1 - k) ** 2
                bob = 20 * (1 - ke) + 2.5 * math.sin(t * 2.2 + j["ph"])
                p = (j["p"][0], j["p"][1] + bob)
                Rb = j["Rb"] * (1 - 0.6 * kq)
                Rb = max(6, round(Rb / 2) * 2)          # 压缩按整格一档档缩（不小数缩放）
                aurelia(cv, p[0], p[1] - 30, Rb + 1.5 * math.sin(t * (5 + 20 * kp) + j["ph"]), j["ph"] + t * 6, al=0.85 * ke, bright=0.6 * kq)
                if kp > 0:
                    shrink_ring(cv, (p[0], p[1] - 30 + Rb * 0.3), 47 * (1 - kp) + 9, 0.8 * kp)
                    for m in range(6):                 # 光点吸入
                        a = math.tau * (m + hf(m, j["Rb"], 5)) / 6 + t * 2
                        r = 40 * (1 - kp) * (0.6 + 0.4 * hf(m, j["Rb"], 6)) + 4
                        x, y = p[0] + math.cos(a) * r, p[1] - 30 + math.sin(a) * r * SQ
                        cv.put(x, y, CYL)
                        cv.emit(x, y, CYL, 0.7)
        else:
            # 冲击帧之后：炸开
            if hfb < 0:
                bf = int(tb * 15 + 1e-6)
                for i, j in enumerate(JL):
                    c = (j["p"][0], j["p"][1] - 18)
                    if bf == 0:   # 伞盖一鼓（同冲击帧剪影的 1.45 倍）：白亮一拍
                        aurelia(cv, j["p"][0], j["p"][1] - 30, j["Rb"] * 0.4 * 1.45, j["ph"], al=1.0, bright=1.0)
                    cloud(cv, c, tb, i * 13 + 5, 45 + 20 * hf(i, 7, 9), n=520)   # 原版每只 600 粒的闪烁粒子云（整招的主体，原样保留体量）：像素闪点、本人配色
                    shock(cv, (j["p"][0], j["p"][1]), 8, 75 + 30 * hf(i, 7, 8), tb, thick=2, ground=False, main=False)
                    core(cv, c, bf)
                shock(cv, (CX, CY), R * 0.45, R * 1.02, tb - 1 / 15, thick=7)   # 群心大冲击环推到横扫半径（原版 ring R × 1.05 碎环）
                for e in ES:
                    if e["grab"]:
                        continue
                    _, _, col = SPR[e["k"]]
                    ang = math.atan2(e["p"][1] - CY, e["p"][0] - CX)
                    spray(cv, e["p"], tb, e["id"] * 7 + 1, ang, 1.6, col)
                    spr, anc, _ = SPR[e["k"]]
                    shatter(cv, spr, anc, e["p"], tb, e["id"] * 3 + 2, ang)   # 崩解：怪物本色像素沿冲击方向喷散
            # 漏网缠绕
            for e in ES:
                if e["grab"] and tb < 1.2:
                    coil(cv, e["p"], tb, 8)
    # 合成
    img[:] = img * (1 - cv.al[..., None]) + cv.a * cv.al[..., None]
    if hfb >= 0:   # 冲击帧：第 1 拍白底黑剪影、第 2 拍黑底白剪影（剪影 = 9 只水母放大 1.45 倍）
        bg, fg = (WHITE, (0.02, 0.02, 0.05)) if hfb == 0 else ((0.02, 0.02, 0.05), WHITE)
        img[:] = bg
        cv2 = Cv()
        for j in JL:
            aurelia(cv2, j["p"][0], j["p"][1] - 30, j["Rb"] * 0.4 * 1.45, j["ph"], sil=fg)
        img[:] = img * (1 - cv2.al[..., None]) + cv2.a * cv2.al[..., None]
        return img, None, shake
    return img, cv.g, shake


def compose(img, glow, shake, scale=PX):
    im = Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8), "RGB").resize((AW * scale, AH * scale), Image.NEAREST)
    if glow is not None and glow.max() > 0:
        g = Image.fromarray((np.clip(glow, 0, 1) * 255).astype(np.uint8), "RGB").resize((AW * scale, AH * scale), Image.NEAREST).filter(ImageFilter.GaussianBlur(3 * scale))
        a = np.asarray(im).astype(np.float32) + np.asarray(g).astype(np.float32) * 1.1
        im = Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), "RGB")
    if shake != (0, 0):
        im = im.transform(im.size, Image.AFFINE, (1, 0, -shake[0] * scale, 0, 1, -shake[1] * scale))
    return im


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join(MAIN, "Claude outputs", "ult_px_mizuki_1105"))
    a = ap.parse_args()
    os.makedirs(os.path.join(a.out, "new_frames"), exist_ok=True)
    G = ground_img()
    JL = jellies()
    ES = enemies()
    SPR = enemy_sprites()
    ES = [e for e in ES if e["k"] in SPR]
    mz = [np.asarray(f).astype(np.float32) / 255.0 for f in frames_of(os.path.join(ROOT, "game/art/operators/mizuki/mizuki_runtime_idle@2x.png"), 36)]
    mz = [np.asarray(Image.fromarray((f * 255).astype(np.uint8), "RGBA").resize((86, 86), Image.NEAREST)).astype(np.float32) / 255.0 for f in mz]
    f1, f2 = [], []
    fnt = ImageFont.truetype(FONT, 16)
    lab = {"sf": "超必杀暂停", "wu": "起手慢放（共用）"}
    for n, (ph, t, hfb) in enumerate(timeline()):
        img, glow, sh = render(ph, t, hfb, JL, ES, SPR, mz, G)
        im = compose(img, glow, sh)
        d = ImageDraw.Draw(im)
        txt = lab.get(ph) or ("冲击帧 第 %d 拍" % (hfb + 1) if hfb >= 0 else ("招式 %.2f 秒" % t + ("（慢放）" if 0 <= t - T_BURST <= 0.6 and ph == "cast" else "")))
        d.text((10, 8), "水月终结技 · 转平面（示意场景）  " + txt, fill=(225, 230, 240), font=fnt)
        im.save(os.path.join(a.out, "new_frames", "f_%04d.png" % n))
        f1.append(im)
        cx2, cy2 = CX * PX, CY * PX - 60
        f2.append(im.crop((cx2 - 320, cy2 - 180, cx2 + 320, cy2 + 180)).resize((1280, 720), Image.NEAREST))
    for fr, name in ((f1, "ult_mizuki_1x.gif"), (f2, "ult_mizuki_x2.gif")):
        q = [f.quantize(colors=255, method=Image.MEDIANCUT, dither=Image.NONE) for f in fr]
        q[0].save(os.path.join(a.out, name), save_all=True, append_images=q[1:], duration=int(1000 / 15), loop=0, disposal=1)
    print("帧数", len(f1), "→", a.out)


if __name__ == "__main__":
    main()
