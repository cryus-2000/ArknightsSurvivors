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
SOUL = ["#120e1a", "#262034", "#3e3452", "#5e5276", "#8a7ea6", "#b8aed2", "#e8e2f6"]
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
    return (int(s[0:2], 16), int(s[2:4], 16), int(s[4:6], 16), 255)


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

def boom_up(R, v=0):
    """实心爆团：第 0 拍白热团 + 放射刺；1–2 拍火团（橙白芯）；3–6 拍冷成焦褐、顶上黑烟成团散开。宽 ≤ R"""
    seed = 11 + v * 101 + R
    puffs = _puffs(R, seed, 9 + R // 4)
    frames = []
    for f in range(7):
        b = Buf()
        if f == 0:
            _flash(b, 0, -R * 0.4, R * 0.62, 7, 0.98, R, seed)
        else:
            _draw_puffs(b, puffs, f, seed, cool=0.17)
            if f <= 2:   # 热芯（第 1 拍白热、第 2 拍暗金，读作「实心」）
                blob(b, 0, -R * 0.3, R * (0.34 - 0.1 * f), 1.0 - 0.2 * (f - 1), seed + 50, squash=0.8)
            if f >= 3:   # 冒顶黑烟（第 3 拍起，成团散开）
                for j in range(3):
                    sx = (j - 1) * R * 0.32 + (hf(j, 1, seed) - 0.5) * R * 0.15
                    sy = -R * (0.75 + 0.12 * (f - 2) + 0.1 * hf(j, 2, seed))
                    blob(b, sx, sy, R * (0.18 + 0.03 * f), 0.0, seed + 70 + j, smoke=True, dissolve=max(0.0, (f - 3) * 0.3))
        frames.append(b)
    return frames


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


def pop_up():
    """被合并掉的爆炸：一小团火 → 烟（4 拍）"""
    frames = []
    for f in range(4):
        b = Buf()
        if f == 0:
            _flash(b, 0, -5, 3.5, 4, 0.9, POP_R, 3)
        else:
            blob(b, 0, -5 - f * 2, 3 + f, 0.85 - 0.3 * f, 5, dissolve=max(0.0, (f - 1) * 0.35))
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

def shade_up():
    """残影：灰紫人形从地里浮出（0.25 秒 = 4 拍），两点淡紫眼，头顶两缕火舌跳动"""
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
                edge = abs(x) >= int(half)
                c = SOUL[3] if edge and x < 0 else (SOUL[2] if edge else SOUL[1])
                if y == 0:
                    c = SOUL[0]
                b.put(x, y, c)
        ey = top + 5
        if rise >= 0.75:
            b.put(-2, ey, SOUL[6])
            b.put(2, ey, SOUL[6])
            b.put(-2, ey + 1, SOUL[4])
            b.put(2, ey + 1, SOUL[4])
        for j, dx in enumerate((-2, 2)):
            L = 3 + ((f + j) % 2) * 2
            for s in range(L):
                b.put(dx + (1 if (s + f) % 3 == 0 else 0) * (1 if j else -1), top - 1 - s, SOUL[5] if s < 2 else SOUL[4])
        frames.append(b)
    return frames


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


def smz_up():
    """魂炮出膛：一团暗紫烟（3 拍）"""
    frames = []
    for f in range(3):
        b = Buf()
        blob(b, 0, -1 - f, 2.2 + f * 0.8, 0.6 - 0.25 * f, 17, soul=True, dissolve=max(0.0, (f - 1) * 0.4))
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

def pillar_up(R, tier):
    """第 0 拍：落点一道白热竖柱（高 1.4R）+ 地面白热扁团；1–2 拍火团沿柱往上堆、顶上成蘑菇帽；3–7 拍冷成焦褐、黑烟帽升起散开。
    精一：0.13 秒后外圈三处小殉爆（在 0.8R 上）；精二：灰紫魂火绕柱盘旋上升。宽 ≤ R"""
    seed = 131 + R
    Hc = R * 1.35
    col = []
    nc = 9 + R // 5
    for i in range(nc):
        u = (i + 0.5) / nc
        col.append(((hf(i, 2, seed) - 0.5) * R * 0.16, (hf(i, 3, seed) - 0.5) * R * 0.1, R * 0.1 + u * Hc * 0.82, R * (0.09 + 0.05 * hf(i, 4, seed)) * (1.0 - 0.35 * u), 1.0 - 0.3 * u, R * 0.06))   # 11-05 协调人：中段收细
    cap = [((hf(i, 5, seed) - 0.5) * R * 0.75, (hf(i, 6, seed) - 0.5) * R * 0.15, Hc * (0.85 + 0.12 * hf(i, 7, seed)), R * (0.18 + 0.1 * hf(i, 8, seed)), 0.7, R * 0.07) for i in range(6)]
    base = _puffs(R, seed + 3, 6, spread=0.62, hmin=0.05, hmax=0.15, rmin=0.16, rmax=0.26, flat=True)
    subs = [(math.tau * (k / 3.0) + 0.6, ) for k in range(3)]
    frames = []
    for f in range(8):
        b = Buf()
        if f == 0:
            for y in range(int(Hc)):
                u = y / Hc
                hw = R * 0.12 * (1.0 - 0.5 * u) + 1
                for x in range(-int(hw), int(hw) + 1):
                    b.put(x, -y, FIRE[0] if abs(x) < hw * 0.55 else FIRE[1])
            blob(b, 0, -2, R * 0.42, 1.0, seed, squash=0.45)
            _flash(b, 0, -R * 0.1, 0.1, 6, 0.9, R, seed)
        else:
            _draw_puffs(b, base, f, seed + 3, cool=0.24)
            _draw_puffs(b, col, f, seed + 5, cool=0.19, rise_k=1.3)
            _draw_puffs(b, cap, f, seed + 9, cool=0.17, rise_k=1.6)
            if f >= 3:
                for j in range(2):
                    blob(b, (j - 0.5) * R * 0.4, -Hc * (1.05 + 0.08 * (f - 3)), R * (0.18 + 0.025 * f), 0.0, seed + 40 + j, smoke=True, dissolve=max(0.0, (f - 4) * 0.22))
        if 1 <= f <= 5:   # 沿柱往上窜的火舌（细，1–2 像素，逐拍错开）
            for j in range(5):
                x0 = (j - 2) * R * 0.07 + (hf(j, f, seed) - 0.5) * 2
                y0 = -R * 0.15 - (f - 1) * R * 0.18 - hf(j, 2, seed) * R * 0.3
                L = int(R * (0.35 + 0.25 * hf(j, f + 3, seed)))
                for s_ in range(L):
                    u = s_ / max(1, L)
                    if f >= 4 and vnoise(j * 5, s_, seed + f, 2.0) < (f - 3) * 0.35:
                        continue
                    xx = x0 + math.sin(u * 4.0 + j + f) * 1.4
                    c = FIRE[1] if u < 0.25 else (FIRE[2] if u < 0.6 else FIRE[3])
                    b.put(xx, y0 - s_, c)
                    if u < 0.4 and j % 2 == 0:
                        b.put(xx + 1, y0 - s_, FIRE[2])
        if tier >= 1 and 2 <= f <= 5:   # 精一：外圈三处小殉爆
            k = f - 2
            for s, in subs:
                x, y = gpt(R * 0.8, s)
                if k == 0:
                    _flash(b, x, y - 4, 2.6, 4, 0.9, 7, seed + int(s * 10))
                else:
                    blob(b, x, y - 4 - k * 2, 2.5 + k, 0.85 - 0.3 * k, seed + int(s * 10), dissolve=max(0.0, (k - 1) * 0.35))
        if tier >= 2 and 1 <= f <= 6:   # 精二：灰紫魂火绕柱盘旋上升
            for j in range(2):
                for s in range(10):
                    u = (s + f * 3) / 30.0
                    if u > 1.0:
                        continue
                    a = u * 9.0 + j * math.pi
                    x = math.cos(a) * R * 0.3
                    y = -u * Hc * 1.05 + math.sin(a) * R * 0.08
                    c = SOUL[6] if s == 9 else (SOUL[5] if s > 6 else SOUL[3])
                    b.put(x, y, c)
        frames.append(b)
    return frames


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

def dome_up(R):
    """地毯轰炸：一团贴地的扁爆——第 0 拍贴地白热扁盘 + 低放射，1–2 拍一圈矮火团（高 ≤ 0.3R）往外滚，3–5 拍冷成一圈低黑烟散开"""
    seed = 171 + R
    ring = []
    n = 10 + R // 5
    for i in range(n):
        a = i * math.tau / n + hf(i, 1, seed) * 0.3
        ring.append((a, R * (0.45 + 0.4 * hf(i, 2, seed)), R * (0.14 + 0.08 * hf(i, 3, seed)), 1.0 - 0.3 * hf(i, 4, seed)))
    frames = []
    for f in range(6):
        b = Buf()
        if f == 0:
            blob(b, 0, -R * 0.08, R * 0.75, 1.0, seed, squash=0.42)
            _flash(b, 0, -R * 0.08, 0.1, 10, 1.0, R, seed)
        else:
            k = f - 1
            items = sorted(ring, key=lambda q: math.sin(q[0]))
            for (a, rr, pr, h0) in items:
                rr2 = min(R * 1.0 - pr * 0.6, rr * (1.0 + 0.08 * k))
                x, y = gpt(rr2, a)
                heat = h0 - 0.23 * k
                dis = max(0.0, (0.3 - heat) * 2.0 + (k - 2) * 0.15) if heat < 0.3 else 0.0
                if dis < 0.98:
                    blob(b, x, y - pr * 0.6 - k * 1.2, pr * (1.0 + 0.1 * k), max(0.0, heat), seed + int(a * 50), dissolve=dis, squash=0.8)
            if k <= 1:
                blob(b, 0, -R * 0.06, R * (0.4 - 0.15 * k), 0.95 - 0.3 * k, seed + 1, squash=0.42)
        frames.append(b)
    return frames


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

def dawn_up(R):
    """第 0 拍：贴地一道横贯 0.95R 的白热地平线 + 升起的半圆光穹（宽 0.85R、高 0.5R）；1–2 拍光穹里翻滚火团、柱心往上冲；
    3–8 拍外沿一圈黑烟环往外滚、中心蘑菇烟柱升起、成团散开。宽 ≤ R"""
    seed = 211 + R
    core = _puffs(R, seed, 14 + R // 6, spread=0.62, hmin=0.08, hmax=0.42, rmin=0.14, rmax=0.24)
    col = [((hf(i, 1, seed) - 0.5) * R * 0.22, 0.0, R * (0.3 + 0.9 * hf(i, 2, seed)), R * (0.1 + 0.06 * hf(i, 3, seed)), 0.95 - 0.3 * hf(i, 2, seed), R * 0.05) for i in range(10)]
    nr = 14 + R // 8
    rim = [(i * math.tau / nr + hf(i, 4, seed) * 0.25, R * (0.06 + 0.07 * hf(i, 5, seed))) for i in range(nr)]
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
            Wd, Hd = R * 0.85, R * 0.5
            for y in range(int(Hd) + 1):
                hw = Wd * math.sqrt(max(0.0, 1.0 - (y / Hd) ** 2))
                for x in range(-int(hw), int(hw) + 1):
                    dd = math.hypot(x / Wd, y / Hd)
                    c = FIRE[1] if dd < 0.45 else (FIRE[2] if dd < 0.8 else FIRE[3])   # 11-05 协调人：第一拍压暗一档
                    b.put(x, -2 - y, c)
        else:
            k = f - 1
            # 烟环：外沿往外滚（地面压扁），后半圈先画
            if k >= 1:
                for (a, pr) in sorted(rim, key=lambda q: math.sin(q[0])):
                    rr = R * (0.55 + 0.08 * k) * (0.92 + 0.12 * hf(int(a * 40), 6, seed))
                    rr = min(rr, R * 1.0 - pr)
                    x, y = gpt(rr, a)
                    dis = max(0.0, (k - 2) * 0.24)
                    if dis < 0.98:
                        blob(b, x, y - pr * 0.8 - k * 1.5, pr * (1.0 + 0.12 * k), max(0.0, 0.5 - 0.2 * k), seed + int(a * 40), dissolve=dis)
            _draw_puffs(b, core, f, seed, cool=0.16, grow=0.06)
            _draw_puffs(b, col, f, seed + 2, cool=0.14, rise_k=1.8)
            if k >= 2:
                for j in range(3):
                    blob(b, (j - 1) * R * 0.18, -R * (1.0 + 0.1 * (k - 2)) - j * 3, R * (0.16 + 0.02 * k), 0.0, seed + 90 + j, smoke=True, dissolve=max(0.0, (k - 4) * 0.22))
            if k == 0:   # 第 1 拍地平线余辉
                W = R * 0.8
                for x in range(-int(W), int(W) + 1, 1):
                    if hf(x, 1, seed) < 0.75:
                        b.put_if_empty(x, 0, FIRE[2] if abs(x) < W * 0.6 else FIRE[4])
        frames.append(b)
    return frames


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

def lk_up(R):
    """落地：第 0 拍一道从天上插进地面的黑红亮线（弹道最后一段）+ 地面白芯团；1–2 拍矮火裙 + 往上溅的碎块；3–5 拍黑红烟成团散开。宽 ≤ 0.8R"""
    seed = 307 + R
    puffs = _puffs(R, seed, 7, spread=0.45, hmin=0.1, hmax=0.35, rmin=0.24, rmax=0.36)
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
            blob(b, 0, -2, R * 0.38, 1.0, seed, squash=0.5)
        else:
            _draw_puffs(b, puffs, f, seed, cool=0.2)
            if f <= 2:
                for k in range(6):   # 往上溅的碎块（V 形）
                    a = -math.pi / 2 + (k - 2.5) * 0.35
                    d = R * (0.25 + 0.2 * f) * (0.8 + 0.4 * hf(k, 1, seed))
                    x, y = math.cos(a) * d, math.sin(a) * d - 2 + f * f * 2
                    b.put(x, y, SMOKE[1])
                    b.put(x + 1, y, SMOKE[2])
                    b.put(x, y - 1, FIRE[3] if f == 1 else SMOKE[2])
        frames.append(b)
    return frames


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
