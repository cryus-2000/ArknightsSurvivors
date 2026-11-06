"""维什戴尔转平面（docs/274）的像素图形：炮击爆团 / 余震 / 残影 / 火柱 / 地毯轰炸 / 巨炮黎明的帧条，以及运行时件（炮弹、准星、残影标记）的同一套画法（Python 版）。
tools/pxplane_bake_wisadel.py 用它烤帧条（game/art/fx/pxp/pxp_wd_*.png + game/data/pxp_wisadel.json），
tools/pxplane_gif_wisadel.py 用它拼送审 GIF；运行时件在游戏里由 fx_pxplane_wd.gd 逐格画，算法与本文件 shell_px() / reticle_px() / mark_px() 一一对应，改一边要改另一边。
单位：美术像素（游戏里 1 美术像素 = g.PX = 2 世界像素）；原点 = 地面点，y 向下为正（往上抬写负数）。全部确定性（抖动用坐标哈希，不用随机数）。

配色（用户口径：原作红黑，但红色只给危险）：
- 爆炸 FIRE：橙白热芯 → 暗金 → 橙 → 焦褐（不进红）；
- 黑烟 SMOKE：近黑紫灰；
- 魂灵之影 SOUL：灰紫（残影、殉爆、魂炮、标记）；
- 余震 DUST：土褐灰尘 + 地缝里一线暗金；
- 炮弹 IRON：黑铁。"""
import math

FIRE = ["#fff0e4", "#ffa868", "#f04a24", "#c41e18", "#8e1010", "#5c0a0c", "#360608", "#1a0305"]   # 11-05 用户：炮击要原作的黑红（原作 wisdel_*_hit：纯红 + 暗血红 + 近黑，橙火星）；偏橙的血红，和敌方预警粉红 #ff2667 拉开
SMOKE = ["#0c0607", "#180a0c", "#26100f", "#381a18", "#4e2a28"]
SOUL = ["#14040680", "#2a080cb0", "#3e0c12c0", "#7a141c", "#b82228", "#e8443c", "#ffb0a0"]   # 11-05 用户「紫色是不是不需要」：魂灵之影改黑红体系——暗红半透明身（前三阶带透明度）+ 红描边，比主炮暗、薄
DUST = ["#1e1414", "#34221e", "#4e3430", "#6e4c44", "#8e6a5e"]
IRON = ["#141012", "#2a2226", "#463c40", "#6a5e60"]
SCORCH = ["#100606", "#1a0a0a", "#261010"]
SQ = 0.72   # 贴地压扁（combat.GROUND_Y）
DIRS = [-90, -45, 0, 45, 90]

# 尺寸档（美术像素 = 判定半径 ÷ 2）。游戏挑「不超过判定 × 1.1」的最大一档
BOOM_R = [22, 26, 30, 34, 38, 43, 48]          # 普攻爆团（aoe 66 × op_range，精一 × 1.15；礼尚往来 × 0.85）
S1_R = [44, 50, 56, 62]                        # 定点清算强化炮（× 1.375）
S2_R = [44, 48, 54, 60]                        # 饱和复仇（× 1.25，精一起）
S3_R = [84, 95, 106, 118]                      # 爆裂黎明巨炮（× 2.5，精二）
Q_R = [32, 38, 44, 52, 60, 70, 82, 96, 112, 130, 150]   # 余震（爆炸 × 1.2；余响再 × 1.25）
SB_R = [18, 22, 26, 30, 34, 38]                # 残影殉爆 / 魂炮落点 / 连携殉爆
POP_R = 8                                      # 被合并掉的爆炸（同屏封顶）：一小团火


def hx(s):
    s = s.lstrip("#")
    return (int(s[0:2], 16), int(s[2:4], 16), int(s[4:6], 16), int(s[6:8], 16) if len(s) >= 8 else 255)


def hsh(x, y, k=0):
    return ((int(x) * 73856093) ^ (int(y) * 19349663) ^ (int(k) * 83492791)) & 0xFFFF


def hf(x, y, k=0):
    return hsh(x, y, k) / 65535.0


def h2(x, y, k=0):
    """整数混合哈希（同 fx_pxplane.Fxr_h 的做法），没有条纹"""
    v = (int(x) * 374761393 + int(y) * 668265263 + int(k) * 2147483647) & 0xFFFFFFFF
    v = ((v ^ (v >> 13)) * 1274126177) & 0xFFFFFFFF
    v ^= v >> 16
    return (v & 0xFFFF) / 65535.0


def vnoise(x, y, k=0, cell=3.0):
    """值噪声（cell 像素一格、双线性插值）：成团的消散图案"""
    fx, fy = x / cell, y / cell
    x0, y0 = math.floor(fx), math.floor(fy)
    tx, ty = fx - x0, fy - y0
    tx, ty = tx * tx * (3 - 2 * tx), ty * ty * (3 - 2 * ty)
    a = h2(x0, y0, k) * (1 - tx) + h2(x0 + 1, y0, k) * tx
    b = h2(x0, y0 + 1, k) * (1 - tx) + h2(x0 + 1, y0 + 1, k) * tx
    return a * (1 - ty) + b * ty


class Buf:
    """一帧：{(x, y): '#rrggbb'}，原点相对坐标"""
    def __init__(self):
        self.p = {}

    def put(self, x, y, c):
        self.p[(int(round(x)), int(round(y)))] = c

    def put_if_empty(self, x, y, c):
        k = (int(round(x)), int(round(y)))
        if k not in self.p:
            self.p[k] = c

    def line(self, x0, y0, x1, y1, c, keep=False):
        n = max(1, int(math.ceil(max(abs(x1 - x0), abs(y1 - y0)))))
        for i in range(n + 1):
            u = i / n
            (self.put_if_empty if keep else self.put)(x0 + (x1 - x0) * u, y0 + (y1 - y0) * u, c)


def gpt(r, a, lift=0.0):
    """地面极坐标 → 画面（压扁 SQ）"""
    return (r * math.cos(a), r * math.sin(a) * SQ - lift)


# ================================================================ 体积团（火团 / 烟团）：受光面左上，按热度取色，冷了成团消散（不用网点）

def blob(b, cx, cy, r, heat, seed, smoke=False, dissolve=0.0, soul=False, squash=1.0):
    """一个圆团：r 半径；heat 1 = 白热 → 0 = 冷（火团冷到 0.3 以下转烟）；dissolve 0..1 按坐标噪声挖掉（成团散开）"""
    ri = int(math.ceil(r))
    for y in range(-ri, ri + 1):
        for x in range(-ri, ri + 1):
            yy = y / squash
            d = math.hypot(x, yy)
            edge = r * (0.86 + 0.14 * vnoise(cx + x, cy + y, seed, 2.0))
            if d > edge:
                continue
            if dissolve > 0.0 and vnoise(cx + x, cy + y, seed + 7) < dissolve * (0.55 + 0.45 * d / max(1.0, r)):
                continue
            lit = (-x * 0.6 - yy * 0.8) / max(1.0, r)        # 左上受光
            if soul:
                k = 2.4 + 2.0 * heat + lit * 1.2 - d / max(1.0, r) * 1.0
                c = SOUL[max(0, min(6, int(round(k))))]
            elif smoke or heat < 0.3:
                k = 1.3 + lit * 1.6 + heat * 2.0 - (0.8 if d > edge - 1.3 else 0.0)
                c = SMOKE[max(0, min(4, int(round(k))))]
            else:
                k = (1.0 - heat) * 4.6 - lit * 1.9 + (d / max(1.0, r)) * 0.8 + (1.3 if d > edge - 1.3 else 0.0)   # 外缘暗一阶：团与团分得开
                c = FIRE[max(0, min(7, int(round(k))))]
            b.put(cx + x, cy + y, c)


def _puffs(R, seed, n, spread=0.78, hmin=0.12, hmax=0.55, rmin=0.2, rmax=0.36, flat=False):
    """爆团里的火团：[(地面 x, 地面 y, 初始高度, 半径, 初始热度, 上升速度)]"""
    out = []
    for i in range(n):
        a = hf(i, 1, seed) * math.tau
        rr = R * spread * math.sqrt(hf(i, 2, seed))
        pr = R * (rmin + (rmax - rmin) * hf(i, 3, seed))
        x, y = rr * math.cos(a), rr * math.sin(a) * SQ
        lim = R * 1.02 - pr
        if abs(x) > lim:
            x = math.copysign(lim, x)
        h = R * (hmin + (hmax - hmin) * hf(i, 4, seed)) * (0.35 if flat else 1.0)
        heat = 1.0 - 0.55 * rr / max(1.0, R * spread) - 0.1 * hf(i, 5, seed)
        out.append((x, y, h, pr, heat, R * (0.05 + 0.06 * hf(i, 6, seed))))
    return out


def _draw_puffs(b, puffs, f, seed, cool=0.2, grow=0.07, smoke_from=2, rise_k=1.0):
    order = sorted(range(len(puffs)), key=lambda i: puffs[i][1])
    for i in order:
        x, y, h, pr, heat, rs = puffs[i]
        hh = heat - cool * (f - 1)
        r = pr * (1.0 + grow * (f - 1))
        hy = h + rs * (f - 1) * rise_k * (1.6 if hh < 0.3 else 1.0)
        dis = 0.0
        if hh < 0.3:
            dis = min(1.0, (0.3 - hh) * 1.9 + (f - smoke_from) * 0.12)
        if dis >= 0.98:
            continue
        blob(b, x, y - hy, r, max(0.0, hh), seed + i, dissolve=dis)


def _flash(b, cx, cy, r, rays=6, ray_k=0.95, R=None, seed=0):
    """第 0 拍：实心白热团 + 一圈放射短刺（压扁，伸到 R × ray_k）"""
    ri = int(math.ceil(r))
    for y in range(-ri, ri + 1):
        for x in range(-ri, ri + 1):
            d = math.hypot(x, y)
            if d > r * (0.9 + 0.1 * h2(x, y, seed)):
                continue
            c = FIRE[0] if d < r * 0.55 else (FIRE[1] if d < r * 0.8 else FIRE[2])
            b.put(cx + x, cy + y, c)
    R = R or r * 1.6
    for k in range(rays):
        a = k * math.tau / rays + hf(k, 9, seed) * 0.5
        L = R * ray_k * (0.75 + 0.25 * hf(k, 8, seed))
        for s in range(int(r * 0.7), int(L)):
            u = s / L
            px, py = cx + math.cos(a) * s, cy + math.sin(a) * s * SQ
            b.put(px, py, FIRE[1] if u < 0.6 else FIRE[3])
            if u < 0.45:
                b.put(px, py + 1, FIRE[2])


# ================================================================ 普攻爆团（立起层）+ 焦痕（贴地层）

def scorch_gd(R, shock=False):
    """焦痕：不规整的断续暗边 + 2 格更暗内边 + 稀疏暗斑 + 4 道裂缝（先暗金后冷暗）；shock = 精二外圈一道往外推的细热环。
    游戏里最后一帧再停 0.8 秒淡掉"""
    seed = 31 + R
    frames = []
    nf = 6
    for f in range(nf):
        b = Buf()
        Re = R * 0.82
        steps = int(Re * 6)
        for i in range(steps):
            a = i * math.tau / steps
            rr = Re * (0.88 + 0.16 * hf(i // 3, 1, seed))
            if hf(i // 4, 2, seed) < 0.18:
                continue
            for w in range(2):
                x, y = gpt(rr - w, a)
                b.put(x, y, SCORCH[2] if w == 0 else SCORCH[1])
            x, y = gpt(rr - 2, a)
            b.put_if_empty(x, y, SCORCH[0])
        for i in range(int(R * R * 0.35)):
            a = hf(i, 3, seed) * math.tau
            rr = Re * math.sqrt(hf(i, 4, seed)) * 0.9
            x, y = gpt(rr, a)
            b.put_if_empty(x, y, SCORCH[0] if hf(i, 5, seed) < 0.6 else SCORCH[1])
        hot = [FIRE[2], FIRE[3], FIRE[4], FIRE[5], FIRE[6], SCORCH[2]][f]
        for k in range(4):
            a = k * math.tau / 4 + hf(k, 6, seed) * 1.2
            L = Re * (0.45 + 0.35 * hf(k, 7, seed))
            x0, y0 = gpt(R * 0.12, a)
            s = R * 0.12
            while s < L:
                s += 2.0
                x1, y1 = gpt(s, a + (vnoise(k * 9, s, seed, 6.0) - 0.5) * 0.5)
                b.line(x0, y0, x1, y1, hot if s < L * 0.7 else FIRE[6])
                x0, y0 = x1, y1
        if shock and f <= 2:
            Rs = R * [0.62, 0.86, 1.0][f]
            col = [FIRE[1], FIRE[2], FIRE[4]][f]
            steps2 = int(Rs * 6)
            for i in range(steps2):
                if hf(i // 5, 9, seed + f) < 0.2:
                    continue
                a = i * math.tau / steps2
                x, y = gpt(Rs, a)
                b.put(x, y, col)
        frames.append(b)
    return frames


def xpop_up():
    """后期额外弹命中：暗金小星芒 + 一点火（3 拍）"""
    frames = []
    for f in range(3):
        b = Buf()
        L = [6, 4, 2][f]
        cols = [FIRE[0], FIRE[2], FIRE[4]]
        for (dx, dy) in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            for s in range(L):
                b.put(dx * s, -6 + dy * s * 0.8, cols[min(2, f + (1 if s > L // 2 else 0))])
        if f < 2:
            blob(b, 0, -6, 2 - f * 0.5, 0.9, 9)
        frames.append(b)
    return frames


# ================================================================ 余震（贴地）：土尘冲击圈往外推 + 地缝一线暗金。不着火、不发红

def quake_gd(R):
    seed = 53 + R
    frames = []
    nc = max(6, R // 6)
    for f in range(6):
        b = Buf()
        # 地缝：放射短裂缝，第 0–1 拍缝里一线暗金
        for k in range(nc):
            a = k * math.tau / nc + hf(k, 1, seed) * 0.4
            r0 = R * (0.25 + 0.2 * hf(k, 2, seed))
            r1 = R * (0.55 + 0.3 * hf(k, 3, seed))
            col = FIRE[3] if f == 0 else (FIRE[5] if f == 1 else (DUST[0] if f < 5 else SCORCH[2]))
            x0, y0 = gpt(r0, a)
            s = r0
            while s < r1:
                s += 2.0
                a2 = a + (vnoise(k * 9, s, seed, 5.0) - 0.5) * 0.3
                x1, y1 = gpt(s, a2)
                b.line(x0, y0, x1, y1, col)
                if f <= 1 and s < r1 - 2:
                    b.put_if_empty(x1, y1 + 1, DUST[0])
                x0, y0 = x1, y1
        # 土尘冲击圈：前沿从 0.45R 推到 1.0R，尘团矮、压扁，冷了散开
        if f <= 4:
            Rf = R * [0.5, 0.72, 0.88, 0.97, 1.0][f]
            n = int(Rf * 0.55)
            for i in range(n):
                a = i * math.tau / n + hf(i, 4, seed) * 0.2
                if hf(i, 5, seed + f // 2) < 0.15:
                    continue
                x, y = gpt(Rf * (0.94 + 0.06 * hf(i, 6, seed)), a)
                pr = 1.6 + 1.8 * hf(i, 7, seed) + 0.4 * f
                h = 1.0 + f * 0.8
                dis = max(0.0, (f - 2) * 0.3)
                ri = int(math.ceil(pr))
                for yy in range(-ri, ri + 1):
                    for xx in range(-ri, ri + 1):
                        if math.hypot(xx, yy / 0.7) > pr:
                            continue
                        if dis and vnoise(x + xx, y + yy, seed + 3) < dis:
                            continue
                        lit = (-xx * 0.6 - yy * 0.8) / max(1.0, pr)
                        c = DUST[max(0, min(4, int(round(2.4 + lit * 1.4 - f * 0.3))))]
                        b.put(x + xx, y - h + yy, c)
        frames.append(b)
    return frames


# ================================================================ 魂灵之影：残影（立起）/ 殉爆（立起）/ 魂炮出膛

def sblast_up(R, link=False):
    """残影殉爆 / 魂炮落点：第 0 拍灰紫碎影往心里收（内爆），第 1 拍暗紫核心爆开 + 往上窜的灰紫火舌，2–5 拍火舌升起、成团散成暗烟；底下一圈压扁的细环"""
    seed = 91 + R + (500 if link else 0)
    frames = []
    nt = 4 + R // 8
    for f in range(6):
        b = Buf()
        if f == 0:
            n = 8 + R // 4
            for k in range(n):
                a = k * math.tau / n + hf(k, 1, seed) * 0.3
                r0, r1 = R * 0.7, R * 0.35
                for s in range(int(r1), int(r0)):
                    x, y = gpt(s, a, R * 0.3)
                    b.put(x, y, SOUL[4] if s < r1 + 3 else SOUL[2])
            blob(b, 0, -R * 0.3, R * 0.16, 0.5, seed, soul=True)
        else:
            k = f - 1
            # 底环
            if k <= 2:
                Rr = R * [0.7, 0.9, 1.0][k]
                steps = int(Rr * 6)
                for i in range(steps):
                    if hf(i // 4, 2, seed + k) < 0.25:
                        continue
                    x, y = gpt(Rr, i * math.tau / steps)
                    b.put(x, y, [SOUL[4], SOUL[3], SOUL[2]][k])
            # 核心
            if k <= 1:
                blob(b, 0, -R * 0.3, R * (0.34 - 0.08 * k), 1.0 - 0.4 * k, seed + 3, soul=True)
            # 火舌
            for j in range(nt):
                a = hf(j, 3, seed) * math.tau
                rr = R * 0.55 * math.sqrt(hf(j, 4, seed))
                x0, y0 = gpt(rr, a)
                L = R * (0.45 + 0.4 * hf(j, 5, seed))
                h0 = R * 0.15 + k * R * 0.12
                w = 1.5 + 1.5 * hf(j, 6, seed)
                dis = max(0.0, (k - 1) * 0.28)
                for s in range(int(L)):
                    u = s / L
                    if dis and vnoise(j * 7, s, seed + 9, 2.5) < dis * (0.5 + u):
                        continue
                    yy = y0 - h0 - s
                    xx = x0 + math.sin(u * 3.0 + j) * 1.5
                    ww = max(0.5, w * (1.0 - u))
                    for dx in range(-int(ww), int(ww) + 1):
                        heat = (1.0 - u) * (1.0 - 0.25 * k)
                        c = SOUL[max(1, min(5, int(round(1.6 + heat * 3.4 - abs(dx) * 0.8))))] if k < 4 else SMOKE[2 + (dx == 0)]
                        b.put(xx + dx, yy, c)
        frames.append(b)
    return frames


# ================================================================ 出膛火（立起、跟她）：5 个平面角

def muzzle_up(deg, big=False):
    """炮口焰：第 0 拍白芯短锥 + 两侧小喷，第 1 拍橙锥变短 + 烟团，第 2–3 拍烟。big = 巨炮（长一倍、烟多）"""
    a = math.radians(deg)
    d = (math.cos(a), math.sin(a) * SQ)
    nv = (-d[1], d[0])
    L = 22 if big else 11
    frames = []
    for f in range(4 if not big else 5):
        b = Buf()
        if f <= 1:
            Lf = L * (1.0 if f == 0 else 0.55)
            for s in range(int(Lf)):
                u = s / Lf
                hw = (2.4 if big else 1.6) * (1.0 - u) + 0.4
                for w in range(-int(hw), int(hw) + 1):
                    c = (FIRE[0] if abs(w) < hw * 0.5 and u < 0.6 else FIRE[2]) if f == 0 else (FIRE[3] if abs(w) < hw * 0.5 else FIRE[4])
                    b.put(d[0] * s + nv[0] * w, d[1] * s + nv[1] * w, c)
            if f == 0:
                for sgn in (-1, 1):
                    for s in range(3 if not big else 6):
                        b.put(d[0] * 2 + nv[0] * sgn * (2 + s), d[1] * 2 + nv[1] * sgn * (2 + s), FIRE[2] if s < 2 else FIRE[4])
        if f >= 1:
            k = f - 1
            for j in range(2 if not big else 4):
                ox = d[0] * (3 + j * 4) + nv[0] * (j % 2 * 2 - 1) * 2
                oy = d[1] * (3 + j * 4) - k * 2 - j
                blob(b, ox, oy, (2.2 if not big else 3.4) + k * 0.9, 0.0, 61 + j, smoke=True, dissolve=max(0.0, k * 0.3 - 0.1))
        frames.append(b)
    return frames


def glint_up(big=False):
    """技能起手：炮口一枚暗金四芒星（S1 / S2；big = S3 装填：外加两团蒸汽）"""
    frames = []
    for f in range(5):
        b = Buf()
        L = [5, 8, 6, 4, 2][f] + (3 if big else 0)
        for (dx, dy) in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            for s in range(L):
                c = FIRE[0] if s < 2 else (FIRE[2] if s < L * 0.7 else FIRE[4])
                b.put(dx * s, dy * s, c)
        for (dx, dy) in ((1, 1), (-1, 1), (1, -1), (-1, -1)):
            for s in range(1, max(1, L // 3)):
                b.put(dx * s, dy * s, FIRE[2])
        if big and f >= 1:
            for j in (-1, 1):
                blob(b, j * (5 + f), -2 - f * 2, 2.5 + f * 0.7, 0.0, 77 + j, smoke=True, dissolve=max(0.0, (f - 2) * 0.3))
        frames.append(b)
    return frames


# ================================================================ S1 定点清算：处刑火柱（立起）

def bracket_px(r, beat):
    """S1 强化炮落点准星：四角括号（地面，压扁），半径 r（美术像素），随拍往里收一格。返回 [(x, y, 颜色)]"""
    out = []
    rr = r - (beat % 3)
    for k in range(4):
        a = math.pi / 4 + k * math.pi / 2
        cx, cy = rr * math.cos(a), rr * math.sin(a) * SQ
        sx, sy = (1 if math.cos(a) > 0 else -1), (1 if math.sin(a) > 0 else -1)
        for s in range(4):
            out.append((round(cx - sx * s), round(cy), FIRE[2] if s == 0 else FIRE[3]))
            out.append((round(cx), round(cy - sy * s), FIRE[3]))
    return out


# ================================================================ S2 饱和复仇：贴地扁爆（立起，矮）+ 放射焦星（贴地）

def star_gd(R, flames=False):
    """放射焦星：8–10 道黑色放射焦痕（从 0.25R 到 1.0R，越外越细），第 0–1 拍道缝里暗金；flames = 精二：焦痕上留 5 簇小地火（跳 9 拍）"""
    seed = 191 + R
    n = 8 + R // 20
    frames = []
    nf = 6 if not flames else 10
    for f in range(nf):
        b = Buf()
        for k in range(n):
            a = k * math.tau / n + (hf(k, 1, seed) - 0.5) * 0.4
            r0, r1 = R * 0.22, R * (0.8 + 0.18 * hf(k, 2, seed))
            s = r0
            while s < r1:
                u = (s - r0) / (r1 - r0)
                w = max(0, int(round(2.2 * (1.0 - u))))
                x, y = gpt(s, a)
                for dw in range(-w, w + 1):
                    nx, ny = -math.sin(a) * dw, math.cos(a) * dw * SQ
                    b.put(x + nx, y + ny, SCORCH[0] if abs(dw) < w else SCORCH[1])
                if f <= 1 and u < 0.6:
                    b.put(x, y, FIRE[3] if f == 0 else FIRE[5])
                s += 1.0
        for i in range(int(R * 0.9)):
            a = hf(i, 3, seed) * math.tau
            x, y = gpt(R * 0.25 * math.sqrt(hf(i, 4, seed)), a)
            b.put_if_empty(x, y, SCORCH[0])
        if flames and f >= 1:
            for j in range(5):
                a = j * math.tau / 5 + 0.3
                x, y = gpt(R * (0.45 + 0.25 * hf(j, 5, seed)), a)
                L = [0, 5, 6, 4, 5, 3, 4, 2, 3, 1][f] + (j % 2)
                if f >= 8:
                    L = max(0, L - 1)
                for s in range(L):
                    c = FIRE[1] if s == 0 else (FIRE[2] if s < L * 0.5 else FIRE[4])
                    b.put(x + ((s + f + j) % 3 == 0), y - s, c)
                    if s < L * 0.4:
                        b.put(x + 1, y - s, FIRE[3])
        frames.append(b)
    return frames


# ================================================================ S3 爆裂黎明：巨炮（地平线白光 + 升起的光穹 + 烟环）

def dawn_gd(R):
    """巨炮落点地面：冲击环往外推（第 0–2 拍）+ 12 道放射裂缝（先暗金后冷）+ 焦痕（最后一帧停 0.8 秒淡掉）"""
    seed = 233 + R
    frames = []
    for f in range(7):
        b = Buf()
        sc = scorch_gd(int(R * 0.7))[min(5, f)]
        b.p.update(sc.p)
        for k in range(12):
            a = k * math.tau / 12 + hf(k, 1, seed) * 0.3
            r0, r1 = R * 0.3, R * (0.7 + 0.25 * hf(k, 2, seed))
            x0, y0 = gpt(r0, a)
            s = r0
            col = [FIRE[1], FIRE[2], FIRE[4], FIRE[5], FIRE[6], SCORCH[2], SCORCH[2]][f]
            while s < r1:
                s += 2.0
                a2 = a + (vnoise(k * 9, s, seed, 6.0) - 0.5) * 0.3
                x1, y1 = gpt(s, a2)
                b.line(x0, y0, x1, y1, col if s < r1 * 0.8 else SCORCH[1])
                x0, y0 = x1, y1
        if f <= 2:
            Rs = R * [0.7, 0.88, 1.0][f]
            steps = int(Rs * 6)
            for i in range(steps):
                if hf(i // 6, 3, seed + f) < 0.15:
                    continue
                x, y = gpt(Rs, i * math.tau / steps)
                b.put(x, y, [FIRE[0], FIRE[1], FIRE[3]][f])
                if f < 2:
                    b.put(x, y + 1, FIRE[3])
        frames.append(b)
    return frames


# ================================================================ 运行时件（游戏里 fx_pxplane_wd.gd 同算法逐格画）

def shell_px(dx, dy, kind, beat):
    """炮弹：沿飞行方向 (dx, dy) 单位向量；返回 [(沿向 q（0 = 弹头，正数往后）, 法向 w, 颜色)]。
    kind：n 普通 / s1 强化 / g 巨炮 / soul 魂炮 / x 后期小弹"""
    out = []
    if kind == "g":
        head, tail = 3, [FIRE[1], FIRE[2], FIRE[2], FIRE[3], FIRE[3], FIRE[4], FIRE[5], SMOKE[3], SMOKE[2]]
        body = IRON
    elif kind == "s1":
        head, tail = 2, [FIRE[2], FIRE[2], FIRE[3], FIRE[4], FIRE[5], SMOKE[3]]
        body = IRON
    elif kind == "soul":
        head, tail = 1, [SOUL[4], SOUL[3], SOUL[2]]
        body = [SOUL[1], SOUL[2], SOUL[3], SOUL[5]]
    elif kind == "x":
        head, tail = 1, [FIRE[3], FIRE[5]]
        body = IRON
    else:
        head, tail = 1, [FIRE[2], FIRE[3], FIRE[5], SMOKE[3]]
        body = IRON
    for q in range(-head, head + 1):
        for w in range(-head, head + 1):
            if abs(q) + abs(w) > head + (1 if head >= 2 else 0):
                continue
            c = body[1] if w < 0 else body[0]
            if q == -head:
                c = FIRE[1] if kind != "soul" else SOUL[6]
            elif q == -head + 1 and w <= 0:
                c = body[3] if kind != "soul" else SOUL[5]
            out.append((q, w, c))
    for i, c in enumerate(tail):
        q = head + 1 + i
        wob = 0 if kind in ("x",) else (1 if (beat + i) % 4 == 0 else (-1 if (beat + i) % 4 == 2 else 0))
        out.append((q, wob if i > 1 else 0, c))
        if kind == "g" and i < 5:
            out.append((q, 1, FIRE[3] if i < 3 else FIRE[4]))
            out.append((q, -1, FIRE[3] if i < 3 else FIRE[4]))
        elif kind == "s1" and i < 3:
            out.append((q, 1 if i % 2 == 0 else -1, FIRE[3]))
    return out


def reticle_px(r, k, beat):
    """落点准星（地面，炮弹在路上时）：1 美术像素断续扁圈，半径从 1.1r 收到 r（k = 飞行进度 0..1），每拍转一格；4 道短刻度。返回 [(x, y, 颜色)]"""
    out = []
    rr = r * (1.1 - 0.1 * k)
    n = max(24, int(rr * 6.3 / 2))
    col = FIRE[4] if k < 0.6 else FIRE[3]
    for i in range(n):
        if (i + beat) % 4 == 3:
            continue
        a = i * math.tau / n
        out.append((round(rr * math.cos(a)), round(rr * math.sin(a) * SQ), col))
    for j in range(4):
        a = j * math.pi / 2
        for s in range(3):
            out.append((round((rr - 2 - s) * math.cos(a)), round((rr - 2 - s) * math.sin(a) * SQ), FIRE[2] if s == 0 else col))
    return out


def mark_px(beat, gift=False):
    """残影标记（悬在敌人头上）：灰紫小魂火 5 宽 7 高 + 两点淡紫眼，按拍跳；gift = 精一「好礼」：脚边一粒暗金。返回 [(x, y, 颜色)]，原点 = 标记中心"""
    out = []
    bob = 1 if (beat // 3) % 2 else 0
    rows = [(-3, 0), (-2, 1), (-1, 2), (0, 2), (1, 2), (2, 1), (3, 1)]
    for (y, hw) in rows:
        for x in range(-hw, hw + 1):
            edge = abs(x) == hw
            c = SOUL[3] if edge else SOUL[1]
            if y <= -2:
                c = SOUL[4] if (beat + x) % 2 == 0 else SOUL[3]
            out.append((x, y - bob, c))
    out.append((-1, 0 - bob, SOUL[6]))
    out.append((1, 0 - bob, SOUL[6]))
    out.append((((beat // 2) % 3) - 1, -4 - bob, SOUL[5]))
    if gift:
        out.append((3, 3 - bob, FIRE[2]))
        out.append((4, 3 - bob, FIRE[4]))
        out.append((3, 4 - bob, FIRE[4]))
    return out


# ================================================================ 连携「天降厚礼」：炮弹从天而降 + 一圈圈余震

def lk_gd(R):
    """余震涟漪：三道细环依次从中心往外推（第 1 / 3 / 5 拍起，各推 3 拍到 0.55 / 0.8 / 1.0R），环上带几粒尘；中心一块焦斑。共 9 拍"""
    seed = 331 + R
    frames = []
    for f in range(9):
        b = Buf()
        for i in range(int(R * R * 0.12)):
            a = hf(i, 1, seed) * math.tau
            x, y = gpt(R * 0.3 * math.sqrt(hf(i, 2, seed)), a)
            b.put_if_empty(x, y, SCORCH[0] if hf(i, 3, seed) < 0.6 else SCORCH[1])
        for k in range(3):
            st = 1 + 2 * k
            u = f - st
            if u < 0 or u > 3:
                continue
            Rr = R * [0.55, 0.8, 1.0][k] * [0.55, 0.8, 0.95, 1.0][u]
            col = [FIRE[2], FIRE[3], FIRE[5], FIRE[6]][u]
            steps = int(Rr * 6)
            for i in range(steps):
                if hf(i // 4, 5, seed + k) < 0.12 + 0.12 * u:
                    continue
                x, y = gpt(Rr, i * math.tau / steps)
                b.put(x, y, col)
                if u <= 1 and i % 7 == 0:
                    b.put(x, y - 1, DUST[3])
        frames.append(b)
    return frames


def drop_px(beat):
    """连携下坠炮弹（竖直往下）：弹头 3×3 黑铁 + 下端亮芯，上方一道 14 格黑红尾迹（中间 3 格宽、往上收细）。返回 [(x, y, 颜色)]，原点 = 弹头中心"""
    out = []
    for y in range(-1, 2):
        for x in range(-1, 2):
            out.append((x, y, IRON[1] if x < 0 else IRON[0]))
    out.append((0, 2, FIRE[0]))
    out.append((-1, 1, FIRE[2]))
    out.append((1, 1, FIRE[3]))
    tail = [FIRE[1], FIRE[2], FIRE[2], FIRE[2], FIRE[3], FIRE[3], FIRE[3], FIRE[4], FIRE[4], FIRE[4], FIRE[5], FIRE[5], FIRE[5], FIRE[6], FIRE[6], SMOKE[3], SMOKE[3], SMOKE[2], SMOKE[2], SMOKE[2], SMOKE[1], SMOKE[1]]
    for i, c in enumerate(tail):
        y = -2 - i
        wob = 1 if (beat + i) % 4 == 0 and i > 8 else (-1 if (beat + i) % 4 == 2 and i > 8 else 0)
        out.append((wob, y, c))
        if i < 10:
            out.append((-1, y, FIRE[4] if i < 3 else FIRE[5]))
            out.append((1, y, FIRE[4] if i < 3 else FIRE[5]))
    return out


# ================================================================ 11-05 第三版：粒子为主（用户「太实了，没有原作那种粒子感，烟雾太多」）
# 原作 wisdel_*_hit：中心一团很短的红光，之后是一圈往外甩的细长红火星（带尾）+ 几粒黑点，几乎没有烟。
# 这里：热芯只亮 1–2 拍；之后是一簇往外飞的红 / 亮橙火星（1 像素粗、2–5 格短尾，越飞越暗）+ 少量黑碎点；烟只留 2–3 小团、带红边、0.4 秒内散完。

def _spark_set(R, seed, n, dmin=0.45, dmax=1.0, hmax=0.6, h0=0.25, up=None, dark=0.22):
    """火星表：[(角度, 落点距离, 起始高度, 抛高, 寿命比例 0..1, 是否黑碎点)]"""
    out = []
    for i in range(n):
        a = h2(i, 1, seed) * math.tau
        if up is not None:   # 往上喷：地面散开小
            d = R * up * math.sqrt(h2(i, 2, seed))
        else:
            d = R * (dmin + (dmax - dmin) * math.sqrt(h2(i, 2, seed)))
        out.append((a, d, R * h0 * h2(i, 3, seed), R * hmax * (0.3 + 0.7 * h2(i, 4, seed)), 0.55 + 0.45 * h2(i, 5, seed), h2(i, 6, seed) < dark))
    return out


def _spark_pos(sp, u):
    a, d, h0, H, life, dk = sp
    k = 1.0 - (1.0 - u) * (1.0 - u)          # 先快后慢
    h = h0 * (1.0 - u) + 4.0 * H * u * (1.0 - u)
    return d * k * math.cos(a), d * k * math.sin(a) * SQ - h


def _draw_sparks(b, sparks, f, nf, start=1, tail=0.14, cy=0.0, cols=None):
    """第 start 拍起飞，按 u = (f − start + 1) / (nf − start) 走；每颗画一段从 u − tail 到 u 的线（亮头、暗尾）"""
    cols = cols or FIRE
    if f < start:
        return
    u = (f - start + 1) / max(1, nf - start)
    for sp in sparks:
        if u > sp[4]:
            continue
        ul = u / sp[4]
        x1, y1 = _spark_pos(sp, u)
        if sp[5]:   # 黑碎点：2×2，不带尾
            for dx in (0, 1):
                for dy in (0, 1):
                    b.put(x1 + dx, y1 + dy + cy, SMOKE[1] if dx == 0 else SMOKE[2])
            continue
        x0, y0 = _spark_pos(sp, max(0.0, u - tail))
        head = cols[1] if ul < 0.3 else (cols[2] if ul < 0.6 else cols[3])
        mid = cols[3] if ul < 0.5 else cols[4]
        end = cols[5]
        n = max(1, int(math.ceil(max(abs(x1 - x0), abs(y1 - y0)))))
        for i in range(n + 1):
            t = i / n
            c = end if t < 0.35 else (mid if t < 0.75 else head)
            b.put(x0 + (x1 - x0) * t, y0 + (y1 - y0) * t + cy, c)
        b.put(x1, y1 + cy, head)


def _red_smoke(b, cx, cy, r, f0, f, seed, life=4):
    """一小团黑烟：边缘一圈暗红（受热），往上飘、life 拍内成团散完（0.4 秒以内）"""
    k = f - f0
    if k < 0 or k >= life:
        return
    rr = r * (1.0 + 0.18 * k)
    yy = cy - k * r * 0.35
    dis = k / float(life) * 0.95
    ri = int(math.ceil(rr))
    for y in range(-ri, ri + 1):
        for x in range(-ri, ri + 1):
            d = math.hypot(x, y)
            edge = rr * (0.85 + 0.15 * vnoise(cx + x, cy + y, seed, 2.0))
            if d > edge:
                continue
            if dis > 0.0 and vnoise(cx + x, yy + y, seed + 7) < dis * (0.6 + 0.4 * d / max(1.0, rr)):
                continue
            if d > edge - 1.3:
                c = FIRE[5] if (y < 0) else FIRE[6]
            else:
                lit = (-x * 0.6 - y * 0.8) / max(1.0, rr)
                c = SMOKE[max(0, min(3, int(round(1.4 + lit * 1.3))))]
            b.put(cx + x, yy + y, c)


def _core(b, cx, cy, r, f, hot=True):
    """热芯：第 0 拍亮橙红实团（白芯很小），第 1 拍缩一半变红，第 2 拍起没有。hot = False（普攻，11-05 用户怕后期闪眼）：整体降一档、没有白热"""
    if f >= 2 or f < 0:
        return
    rr = r * (1.0 if f == 0 else 0.55)
    ri = int(math.ceil(rr))
    for y in range(-ri, ri + 1):
        for x in range(-ri, ri + 1):
            d = math.hypot(x, y)
            if d > rr * (0.88 + 0.12 * h2(x, y, 5)):
                continue
            u = d / max(1.0, rr)
            o = 0 if hot else 1
            if f == 0:
                c = FIRE[0 + o] if u < 0.3 else (FIRE[1 + o] if u < 0.65 else FIRE[2 + o])
            else:
                c = FIRE[1 + o] if u < 0.35 else (FIRE[2 + o] if u < 0.7 else FIRE[3 + o])
            b.put(cx + x, cy + y, c)


def n_boom(R):
    return 12 + R // 3


def boom_up(R, k=1.0):
    """普攻：热芯 2 拍（降一档、小一号，没有白热）→ 一圈往外甩的红 / 橙火星（带短尾，头也降一档）+ 黑碎点。共 6 拍，宽 ≤ R。
    k = 火星比例（同屏火星封顶时游戏挑 _h 半量 / _q 四分之一的帧条）"""
    seed = 11 + R
    sparks = _spark_set(R, seed, max(3, int(n_boom(R) * k)), dmin=0.4, dmax=0.98, hmax=0.55, h0=0.35)
    frames = []
    dim = FIRE[1:] + [FIRE[7]]
    for f in range(6):
        b = Buf()
        _core(b, 0, -R * 0.3, R * 0.26, f, hot=False)
        if f == 0:
            for q in range(8):   # 第 0 拍一圈细长放射刺（原作的放射红线）
                a = q * math.tau / 8 + h2(q, 9, seed) * 0.4
                L = R * (0.5 + 0.3 * h2(q, 8, seed))
                for s_ in range(int(R * 0.27), int(L)):
                    b.put(math.cos(a) * s_, -R * 0.3 + math.sin(a) * s_ * SQ, FIRE[3] if s_ < L * 0.7 else FIRE[5])
        _draw_sparks(b, sparks, f, 6, cols=dim)
        frames.append(b)
    return frames


def pop_up():
    """被合并掉的爆炸：一小点热芯 + 6 颗火星（4 拍）"""
    sparks = _spark_set(POP_R, 3, 6, dmin=0.5, dmax=1.0, hmax=0.8, h0=0.5, dark=0.0)
    frames = []
    for f in range(4):
        b = Buf()
        _core(b, 0, -4, 2.5, f)
        _draw_sparks(b, sparks, f, 4, tail=0.25)
        frames.append(b)
    return frames


def n_pillar(R):
    return (14 + R // 5) + (6 + R // 8)


def pillar_up(R, tier, k=1.0):
    """S1 处刑火柱：第 0 拍一道细白热竖柱（高 1.35R）+ 地面热芯；之后火星沿柱往上喷泉（地面散开 ≤ 0.3R、抛高到 1.25R）+ 一圈贴地火星到 0.92R，
    细火舌沿柱往上窜；顶上 2 小团红边黑烟。精一：外圈三处小火星簇；精二：一缕暗红魂火绕柱盘旋上升。共 8 拍"""
    seed = 131 + R
    Hc = R * 1.35
    jet = _spark_set(R, seed, max(3, int((14 + R // 5) * k)), up=0.3, hmax=1.25, h0=0.15, dark=0.12)
    ring = _spark_set(R, seed + 3, max(2, int((6 + R // 8) * k)), dmin=0.5, dmax=0.92, hmax=0.25, h0=0.1, dark=0.3)
    subs = [math.tau * (k / 3.0) + 0.6 for k in range(3)]
    sub_sp = _spark_set(8, seed + 5, 6, dmin=0.4, dmax=1.0, hmax=0.9, h0=0.4, dark=0.0)
    frames = []
    for f in range(8):
        b = Buf()
        if f <= 1:
            hc = Hc if f == 0 else Hc * 0.6
            for y in range(int(hc)):
                u = y / hc
                hw = (R * 0.05 * (1.0 - 0.5 * u) + 1) * (1.0 if f == 0 else 0.6)
                for x in range(-int(hw), int(hw) + 1):
                    b.put(x, -y, (FIRE[0] if abs(x) < hw * 0.5 and u < 0.6 else FIRE[1]) if f == 0 else (FIRE[2] if u < 0.5 else FIRE[3]))
        _core(b, 0, -3, R * 0.26, f)
        _draw_sparks(b, jet, f, 8, tail=0.12)
        _draw_sparks(b, ring, f, 8, tail=0.16)
        if 1 <= f <= 5:   # 细火舌沿柱往上窜
            for j in range(4):
                x0 = (j - 1.5) * R * 0.06
                y0 = -R * 0.1 - (f - 1) * R * 0.2 - h2(j, 2, seed) * R * 0.3
                L = int(R * (0.3 + 0.2 * h2(j, f + 3, seed)))
                for s_ in range(L):
                    u = s_ / max(1, L)
                    if f >= 4 and vnoise(j * 5, s_, seed + f, 2.0) < (f - 3) * 0.4:
                        continue
                    b.put(x0 + math.sin(u * 4.0 + j + f) * 1.3, y0 - s_, FIRE[1] if u < 0.25 else (FIRE[2] if u < 0.6 else FIRE[3]))
        if tier >= 1 and 2 <= f <= 5:
            for s0 in subs:
                x, y = gpt(R * 0.8, s0)
                bb = Buf()
                _core(bb, 0, -3, 2.2, f - 2)
                _draw_sparks(bb, sub_sp, f - 2, 4, start=0, tail=0.25)
                for (px_, py_), c in bb.p.items():
                    b.put(x + px_, y + py_, c)
        if tier >= 2 and 1 <= f <= 6:
            for s_ in range(14):
                u = (s_ + f * 3) / 30.0
                if u > 1.0:
                    continue
                a = u * 9.0
                c = SOUL[6] if s_ == 13 else (SOUL[5] if s_ > 9 else SOUL[4])
                b.put(math.cos(a) * R * 0.3, -u * Hc * 1.05 + math.sin(a) * R * 0.08, c)
        frames.append(b)
    return frames


def n_dome(R):
    return 16 + R // 4


def dome_up(R, k=1.0):
    """S2 地毯轰炸：第 0 拍贴地扁热芯（0.55R）+ 低放射；之后一大圈贴着地皮往外掠的火星（抛高 ≤ 0.12R）到 0.95R + 黑碎点；1 小团红边烟。6 拍"""
    seed = 171 + R
    sparks = _spark_set(R, seed, max(3, int(n_dome(R) * k)), dmin=0.55, dmax=0.95, hmax=0.12, h0=0.08, dark=0.25)
    frames = []
    for f in range(6):
        b = Buf()
        if f <= 1:
            rr = R * (0.55 if f == 0 else 0.3)
            for y in range(-int(rr * 0.45), int(rr * 0.45) + 1):
                for x in range(-int(rr), int(rr) + 1):
                    d = math.hypot(x / rr, y / (rr * 0.45))
                    if d > 1.0:
                        continue
                    c = (FIRE[0] if d < 0.35 else (FIRE[1] if d < 0.7 else FIRE[2])) if f == 0 else (FIRE[2] if d < 0.6 else FIRE[3])
                    b.put(x, y - R * 0.06, c)
            if f == 0:
                for k in range(10):
                    a = k * math.tau / 10 + h2(k, 9, seed) * 0.3
                    for s_ in range(int(R * 0.55), int(R * 0.9)):
                        b.put(math.cos(a) * s_, math.sin(a) * s_ * SQ - R * 0.06, FIRE[2] if s_ < R * 0.75 else FIRE[4])
        _draw_sparks(b, sparks, f, 6, tail=0.2)
        frames.append(b)
    return frames


def n_dawn(R):
    return 40 + R // 8


def dawn_up(R, k=1.0):
    """S3 爆裂黎明：第 0 拍贴地白热地平线 + 升起的光穹（已压暗一档）；第 1 拍光穹缩成矮热芯；之后一大圈往外甩的火星（到 0.98R、抛高到 0.7R）+ 黑碎点，
    外沿 4 小团红边烟 0.4 秒散完。共 8 拍"""
    seed = 211 + R
    sparks = _spark_set(R, seed, max(4, int(n_dawn(R) * k)), dmin=0.3, dmax=0.98, hmax=0.7, h0=0.3, dark=0.25)
    frames = []
    for f in range(8):
        b = Buf()
        if f == 0:
            W = R * 0.95
            for x in range(-int(W), int(W) + 1):
                u = abs(x) / W
                b.put(x, 0, FIRE[0] if u < 0.35 else (FIRE[1] if u < 0.75 else FIRE[2]))
                if u < 0.85:
                    b.put(x, -1, FIRE[1] if u < 0.5 else FIRE[2])
                if u < 0.5:
                    b.put(x, 1, FIRE[2])
        if f <= 1:
            Wd, Hd = R * (0.85 if f == 0 else 0.45), R * (0.5 if f == 0 else 0.25)
            for y in range(int(Hd) + 1):
                hw = Wd * math.sqrt(max(0.0, 1.0 - (y / Hd) ** 2))
                for x in range(-int(hw), int(hw) + 1):
                    dd = math.hypot(x / Wd, y / Hd)
                    if f == 0:
                        c = FIRE[1] if dd < 0.45 else (FIRE[2] if dd < 0.8 else FIRE[3])
                    else:
                        c = FIRE[2] if dd < 0.5 else FIRE[3]
                    b.put(x, -2 - y, c)
        _draw_sparks(b, sparks, f, 8, tail=0.13)
        frames.append(b)
    return frames


def _bolt(b, x0, y0, a, L, seed, cols):
    """一道电弧（原作 shandian_14）：按 3 格一步折线走，每步按哈希偏 ±0.7 弧度；中途分一叉。cols = (芯, 边)"""
    x, y = x0, y0
    s = 0.0
    k = 0
    while s < L:
        a2 = a + (h2(k, 1, seed) - 0.5) * 1.4
        x1, y1 = x + math.cos(a2) * 3.0, y + math.sin(a2) * 3.0 * SQ
        b.line(x, y, x1, y1, cols[0])
        b.put_if_empty(x1, y1 + 1, cols[1])
        if k == 2 and L > 14:
            ab = a2 + (0.9 if h2(k, 2, seed) < 0.5 else -0.9)
            xb, yb = x1, y1
            for j in range(int(L * 0.25 / 3)):
                ab2 = ab + (h2(j, 3, seed) - 0.5) * 1.2
                xb2, yb2 = xb + math.cos(ab2) * 3.0, yb + math.sin(ab2) * 3.0 * SQ
                b.line(xb, yb, xb2, yb2, cols[1])
                xb, yb = xb2, yb2
        x, y = x1, y1
        s += 3.0
        k += 1


def _burst(b, cx, cy, R, f, seed, n_sp=12, big=True):
    """一团原作式爆点（skill_03_hit）：贴地白热芯 + 十字白闪（大爆加斜向四芒）+ 一圈不规整红刺。f = 这团自己的第几拍（0–2 有画面）"""
    if f < 0 or f > 2:
        return
    if f <= 1 or big:   # 热芯：大爆撑 3 拍（白 → 橙白 → 红），小爆 2 拍
        rr = R * ([0.32, 0.22, 0.12][f] if big else [0.3, 0.16][f])
        ri = int(math.ceil(rr))
        for y in range(-ri, ri + 1):
            for x in range(-ri, ri + 1):
                d = math.hypot(x, y / SQ)
                if d > rr * (0.86 + 0.14 * h2(x, y, seed)):
                    continue
                u = d / max(1.0, rr)
                if f == 0:
                    c = FIRE[0] if u < 0.45 else (FIRE[1] if u < 0.75 else FIRE[2])
                elif f == 1:
                    c = FIRE[0] if u < 0.2 else (FIRE[1] if u < 0.55 else (FIRE[2] if u < 0.85 else FIRE[3]))
                else:
                    c = FIRE[2] if u < 0.45 else (FIRE[3] if u < 0.8 else FIRE[4])
                b.put(cx + x, cy + y, c)
    # 十字白闪：横长竖短（贴地压扁），大爆第 0 拍再加斜向四芒；越往外越暗
    W = R * ([1.2, 0.8, 0.4][f] if big else [0.8, 0.45, 0.0][f])
    H = W * 0.5
    th = [2, 1, 1][f] if big else 1
    for s_ in range(int(R * 0.18), int(W)):
        u = s_ / max(1.0, W)
        c = [FIRE[0] if u < 0.4 else (FIRE[1] if u < 0.7 else FIRE[3]), FIRE[1] if u < 0.5 else FIRE[3], FIRE[3] if u < 0.5 else FIRE[5]][f]
        for sg in (-1, 1):
            b.put(cx + sg * s_, cy, c)
            if u < 0.35 * th:
                b.put(cx + sg * s_, cy - 1, FIRE[1] if f == 0 else FIRE[2])
                b.put(cx + sg * s_, cy + 1, FIRE[1] if f == 0 else FIRE[2])
    for s_ in range(int(R * 0.14), int(H)):
        u = s_ / max(1.0, H)
        c = [FIRE[0] if u < 0.45 else FIRE[2], FIRE[1] if u < 0.5 else FIRE[3], FIRE[3]][f]
        b.put(cx, cy - s_, c)
        b.put(cx, cy + s_ * 0.6, c)
    if big and f == 0:
        for q in range(4):
            a = math.pi / 4 + q * math.pi / 2
            L = R * 0.6
            for s_ in range(int(R * 0.2), int(L)):
                u = s_ / L
                b.put(cx + math.cos(a) * s_, cy + math.sin(a) * s_ * SQ, FIRE[1] if u < 0.5 else FIRE[3])
    # 红刺：大爆两波（第 0 拍粗刺、第 1 拍再扎出一圈细刺），角度 / 长短 / 粗细按哈希定
    waves = [(0, n_sp, 0.0)] + ([(1, n_sp, math.pi / n_sp)] if big else [])
    for w0, n, off in waves:
        k = f - w0
        if k < 0 or k > 2:
            continue
        for q in range(n):
            a = q * math.tau / n + off + (h2(q, 9 + w0, seed) - 0.5) * 0.45
            L = R * (0.7 + 0.38 * h2(q, 8 + w0, seed)) * (1.0 if w0 == 0 else 0.85)
            r0 = R * [0.26, 0.52, 0.8][k]
            r1 = L * [0.84, 1.0, 1.05][k]
            if r1 <= r0 + 2:
                continue
            wd0 = ([3, 2, 1][k] if h2(q, 7 + w0, seed) > 0.35 else [2, 1, 1][k]) if w0 == 0 else 1
            for s_ in range(int(r0), int(r1)):
                u = (s_ - r0) / max(1.0, r1 - r0)
                c = [FIRE[1] if u < 0.25 else (FIRE[2] if u < 0.6 else (FIRE[3] if u < 0.85 else FIRE[5])), FIRE[2] if u < 0.4 else (FIRE[3] if u < 0.75 else FIRE[5]), FIRE[4] if u < 0.5 else FIRE[6]][k]
                px, py = cx + math.cos(a) * s_, cy * (1.0 - 0.5 * u) + math.sin(a) * s_ * SQ
                ww = max(1, int(round(wd0 * (1.0 - u))))
                for t in range(ww):
                    b.put(px - math.sin(a) * (t - ww // 2), py + math.cos(a) * (t - ww // 2) * SQ, c)


def dawn2_up(R, k=1.0):
    """S3 爆裂黎明（11-07 用户「半圆有点奇怪」→ 照原作 wisdel_skill_03_hit / hit_02 / hit_03 重做，去掉自创的地平线 + 光穹；同日「爆炸要华丽点」）：
    主爆 3 拍（贴地白热芯 → 橙白 → 红；横长竖短十字白闪 + 斜向四芒；粗红刺一波、第 1 拍再扎出一圈细刺）；
    电弧（原作 shandian）6 → 5 → 3 → 1 道，带分叉；第 3–5 拍外圈依次连环炸开 3 团小爆（同一种爆点，小一号）；
    火星从第 1 拍起往外甩、尾巴长一点。共 9 拍。原作 huan_yanhei 烟环不进帧条（游戏里本来叠红色体积雾 / 烟团）；地面冲击环 / 裂缝 / 焦痕仍是 dawn_gd"""
    seed = 211 + R
    sparks = _spark_set(R, seed, max(4, int(n_dawn(R) * k)), dmin=0.3, dmax=1.0, hmax=0.8, h0=0.3, dark=0.2)
    cy = -R * 0.12
    subs = []
    for q in range(3):   # 连环小爆：落点外圈 0.5–0.65R，三个方向错开
        a = q * math.tau / 3 + 0.5 + (h2(q, 2, seed) - 0.5) * 0.8
        x, y = gpt(R * (0.5 + 0.15 * h2(q, 3, seed)), a)
        subs.append((x, y - R * 0.06, 3 + q))
    nf = 9
    frames = []
    for f in range(nf):
        b = Buf()
        _burst(b, 0, cy, R, f, seed, n_sp=14, big=True)
        if f <= 3:
            nb = [6, 5, 3, 1][f]
            cols = [(FIRE[0], FIRE[1]), (FIRE[0], FIRE[2]), (FIRE[1], FIRE[3]), (FIRE[3], FIRE[5])][f]
            for q in range(nb):
                a = q * math.tau / 6 + 0.3 + (h2(q, 5, seed + f) - 0.5) * 0.7
                _bolt(b, 0, cy, a, R * (0.55 + 0.4 * h2(q, 6, seed + f)), seed * 7 + q * 13 + f * 101, cols)
        for (x, y, f0) in subs:
            _burst(b, x, y, R * 0.42, f - f0, seed + int(f0) * 31, n_sp=8, big=False)
            if f == f0:
                _bolt(b, x, y, h2(f0, 7, seed) * math.tau, R * 0.3, seed + f0 * 17, (FIRE[0], FIRE[2]))
        _draw_sparks(b, sparks, f, nf, tail=0.18)
        frames.append(b)
    return frames


def n_lk(R):
    return 12 + R // 3


def lk_up(R, k=1.0):
    """连携落地：第 0 拍一道插进地面的亮线（弹道最后一段）+ 地面热芯；之后火星往上溅成 V 形（地面散开 ≤ 0.55R、抛高到 1.1R）+ 黑碎点；1 小团红边烟。6 拍"""
    seed = 307 + R
    sparks = _spark_set(R, seed, max(3, int(n_lk(R) * k)), up=0.55, hmax=1.1, h0=0.1, dark=0.25)
    frames = []
    for f in range(6):
        b = Buf()
        if f == 0:
            for y in range(int(R * 1.6)):
                u = y / (R * 1.6)
                b.put(0, -y, FIRE[0] if u < 0.3 else (FIRE[2] if u < 0.7 else FIRE[4]))
                if u < 0.5:
                    b.put(-1, -y, FIRE[3])
                    b.put(1, -y, FIRE[3])
        _core(b, 0, -2, R * 0.3, f)
        _draw_sparks(b, sparks, f, 6, tail=0.12)
        frames.append(b)
    return frames


def shade_up():
    """残影（黑红）：暗红半透明人形从地里浮出（4 拍），一圈红描边，两点亮红眼，头顶两缕红火舌"""
    frames = []
    W, Hh = 7, 21
    for f in range(4):
        b = Buf()
        rise = [0.4, 0.75, 1.0, 1.0][f]
        top = -int(Hh * rise)
        for y in range(top, 1):
            u = (y - top) / max(1, -top + 1)
            half = W * (0.45 + 0.55 * min(1.0, u * 1.6)) if u < 0.75 else W * (1.0 - (u - 0.75) * 0.8)
            half = max(1.0, half)
            for x in range(-int(half), int(half) + 1):
                edge = abs(x) >= int(half) or y == top
                b.put(x, y, SOUL[4] if edge else (SOUL[1] if u > 0.3 else SOUL[2]))
        if rise >= 0.75:
            ey = top + 5
            b.put(-2, ey, SOUL[6])
            b.put(2, ey, SOUL[6])
        for j, dx in enumerate((-2, 2)):
            L = 3 + ((f + j) % 2) * 2
            for s_ in range(L):
                b.put(dx + (1 if (s_ + f) % 3 == 0 else 0) * (1 if j else -1), top - 1 - s_, SOUL[5] if s_ < 2 else SOUL[4])
        frames.append(b)
    return frames


def smz_up():
    """魂炮出膛：一小团暗红烟 + 3 颗红火星（3 拍）"""
    sparks = _spark_set(4, 17, 3, dmin=0.6, dmax=1.0, hmax=0.6, h0=0.3, dark=0.0)
    frames = []
    for f in range(3):
        b = Buf()
        _red_smoke(b, 0, -2, 2.2, 0, f, 17, life=3)
        _draw_sparks(b, sparks, f, 3, start=0, tail=0.3)
        frames.append(b)
    return frames
