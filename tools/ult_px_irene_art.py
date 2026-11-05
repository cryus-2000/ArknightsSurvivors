"""艾丽妮终结技「宣判」转平面画面（docs/275，开关 ult/px_plane）的像素图形（Python 版）：纹章、光链、穿梭斩线、连环爆、收尾斩击、裂缝、崩解（碎石 slab / 尘墙 plume）、蓄力。
游戏里由 game/scripts/run/ult_px_ir.gd 逐格画，算法与本文件一一对应，改一边要改另一边；tools/ult_px_irene_gif.py 用它拼送审 GIF。
单位：美术像素（1 美术像素 = 2 世界像素）；坐标相对给定原点；全部确定性（坐标哈希，不用随机数）。
配色：白 + 亮紫为主（LT，与 docs/272 普攻 / 技能同一色阶），深海蓝潮水作辅色（TIDE），裂缝冷下去用暗紫灰（COOL），尘土灰（DUST）。
返回 [(x, y, 颜色, 发光 / 不透明度)]：第 4 项是 bool = 发光（进光学发光层），是 float = 不透明度。"""
import math

LT = ["#1a0c28", "#3a1a58", "#6a32a0", "#9d58e0", "#cf98ff", "#f0e2ff", "#ffffff"]
TIDE = ["#050b1a", "#0b1a38", "#143062", "#21508c", "#3f80bc", "#90c4ea", "#e6f6ff"]
COOL = ["#16121c", "#2a2430", "#423a4a"]
DUST = ["#2a2a30", "#3e3c44", "#56545c", "#6e6c74"]
NAVY = "#0c1430"
SQ = 0.72


def hsh(x, y, k=0):
    return ((int(x) * 73856093) ^ (int(y) * 19349663) ^ (int(k) * 83492791)) & 0xFFFF


def hf(x, y, k=0):
    return hsh(x, y, k) / 65535.0


def _star(out, x, y, arm, c0, c1, c2):
    out.append((x, y, c0, True))
    for i in range(1, arm + 1):
        c = c1 if i < arm else c2
        out += [(x + i, y, c, False), (x - i, y, c, False), (x, y + i, c, False), (x, y - i, c, False)]


# ================================================================ 蓄力（起手慢放；原点 = 她的脚底）

def windup(wk, bt):
    """提灯举起处（头顶上方）16 粒紫白光点螺旋收进灯里，越近越亮；脚下压扁细光圈从 36 收到 11（美术像素），越收越亮"""
    out = []
    lx, ly = 10, -28
    for i in range(16):
        h1, h2 = hf(i, 3, 1), hf(i, 5, 2)
        k = min(1.0, max(0.0, wk * (1.2 + 0.6 * h2) - 0.25 * h1))
        if k <= 0.0 or k >= 1.0:
            continue
        a = math.tau * (i + h1) / 16 + k * 2.2
        d = (36 + 40 * h2) * (1 - k) ** 1.6 + 2
        x, y = lx + math.cos(a) * d, ly + math.sin(a) * d * 0.8
        c = LT[6] if k > 0.7 else LT[5] if k > 0.4 else LT[4]
        out.append((x, y, c, k > 0.7))
        if k < 0.6:   # 尾巴
            out.append((x - math.cos(a + 0.6) * 2, y - math.sin(a + 0.6) * 1.6, LT[3], False))
    r = 36 - 25 * (1 - (1 - wk) ** 2)
    n = int(r * 6.6) + 8
    for q in range(n):
        t = q / n * math.tau
        if (q + bt) % 5 == 4:
            continue
        out.append((round(r * math.cos(t)), round(r * math.sin(t) * SQ * 0.55), LT[5] if wk > 0.6 else LT[4], 0.5 + 0.5 * wk))
    if wk > 0.5:   # 灯芯越来越亮
        _star(out, lx, ly + 3, 1 + int(wk * 2.5), LT[6], LT[5], LT[4])
    return out


# ================================================================ 纹章（烤好的线稿 pxp_ult_ir_seal.png，tools/ult_px_irene_bake.py；用户 10-31 认可的纹章图案）

def seal_mod(age, fade):
    """纹章的调色（乘色 r, g, b, a）：盖章头两拍提亮（白一点），之后半透明 0.42 常亮；收尾冷却 1.4 秒（先变暗紫、再淡掉）。age = 盖章后秒数"""
    if age < 0:
        return None
    if fade is not None:
        u = min(1.0, fade / 1.4)
        if u >= 1.0:
            return None
        k = 1.0 - 0.45 * u
        return (k * 0.9, k * 0.85, k, 0.42 * (1.0 - u))
    if age < 2 / 15:
        return (1.35, 1.3, 1.35, 0.95)
    if age < 4 / 15:
        return (1.15, 1.1, 1.15, 0.75)
    return (1.0, 1.0, 1.0, 0.42)


# ================================================================ 光链（原点 = 纹章边上的起点 rim；tgt = 被锁那只的相对位置）

def chain(tgt, grow, broken):
    """grow：0..1 链节沿线伸出（0.12 秒）；broken：断开后的秒数（None = 没断）。链节 = 2 格一节，白 / 亮紫交替，节间空 1 格；
    扎中处一颗小十字；断开时链节往两侧崩散、下落、变暗（0.3 秒）"""
    out = []
    tx, ty = tgt
    L = math.hypot(tx, ty) or 1.0
    dx, dy = tx / L, ty / L
    nx, ny = -dy, dx
    n = int(L)
    if broken is None:
        m = int(n * min(1.0, grow))
        for i in range(m):
            ph = i % 3
            if ph == 2:
                continue
            c = LT[6] if ph == 0 else LT[4]
            out.append((dx * i, dy * i, c, ph == 0 and i % 6 == 0))
            out.append((dx * i + nx, dy * i + ny, LT[5] if ph == 0 else LT[3], False))   # 链节 2 格粗
        if grow >= 1.0:
            _star(out, tx, ty, 2, LT[6], LT[5], LT[4])
        return out
    if broken > 0.3:
        return out
    u = broken / 0.3
    for i in range(0, n, 3):
        side = 1 if hsh(i, 7, 5) % 2 else -1
        sp = 2 + 6 * hf(i, 7, 6)
        x = dx * i + nx * side * sp * u
        y = dy * i + ny * side * sp * u + 14 * u * u * (0.5 + hf(i, 7, 7))
        out.append((x, y, LT[5] if u < 0.4 else LT[3] if u < 0.75 else LT[2], False))
    return out


# ================================================================ 斩线（两头收尖的实心光刃；原点 = a）

def blade(b, f, w=3.0, hot_frames=1):
    """a → b 一刀：第 0..hot 拍满亮（白芯 + 淡紫 + 亮紫外缘，中间最宽 w），之后变窄成亮线、再从 a 端往 b 端熄灭（共 hot + 3 拍）"""
    out = []
    bx, by = b
    L = math.hypot(bx, by) or 1.0
    dx, dy = bx / L, by / L
    nx, ny = -dy, dx
    if f < 0 or f > hot_frames + 3:
        return out
    cells = {}
    if f <= hot_frames:
        n = int(L * 2)
        for i in range(n + 1):
            u = i / n
            hw = w * math.sin(math.pi * u) ** 0.6
            m = int(math.ceil(hw * 2))
            for j in range(-m, m + 1):
                ww = j / 2.0
                if abs(ww) > hw + 0.25:
                    continue
                k = abs(ww) / max(0.6, hw)
                if k < 0.34 or hw < 0.9:
                    c, gl = LT[6], True
                elif k < 0.62:
                    c, gl = LT[5], False
                elif k < 0.86:
                    c, gl = LT[4], False
                else:
                    c, gl = LT[3], False
                cells[(round(dx * L * u + nx * ww), round(dy * L * u + ny * ww))] = (c, gl)
    else:
        g2 = f - hot_frames
        lo = [0.0, 0.0, 0.4, 0.75][g2]
        for i in range(int(L) + 1):
            u = i / max(1.0, L)
            if u < lo or (g2 == 3 and i % 2):
                continue
            c = LT[6] if g2 == 1 else LT[5] if g2 == 2 else LT[4]
            cells[(round(dx * i), round(dy * i))] = (c, g2 == 1)
    return [(x, y, c, gl) for (x, y), (c, gl) in cells.items()]


def thread(b, age, life=0.4):
    """穿梭留下的细紫线（1 格，虚实交替），life 秒内从两头往中间淡掉"""
    out = []
    if age < 0 or age > life:
        return out
    bx, by = b
    L = math.hypot(bx, by) or 1.0
    u0 = age / life
    for i in range(int(L) + 1):
        u = i / L
        if abs(u - 0.5) > 0.5 * (1 - u0):
            continue
        if i % 3 == 2:
            continue
        out.append((bx * u, by * u, LT[4] if u0 < 0.5 else LT[3], 0.9 * (1 - u0 * 0.5)))
    return out


def splash(dirx, diry, f):
    """穿梭落点溅起一小撮潮水（辅色）：几粒水珠往后甩起落下 + 根部白沫，4 拍"""
    out = []
    if f < 0 or f > 3:
        return out
    for q in range(5):
        a = math.atan2(-diry, -dirx) + (q - 2) * 0.5
        rr = 3 + f * 2.5 + q % 2
        x = math.cos(a) * rr
        y = math.sin(a) * rr * SQ - (6 - (f - 1.5) ** 2 * 2.2) - q % 2
        out.append((x, y, TIDE[6] if f <= 1 else TIDE[5] if f == 2 else TIDE[4], False))
    if f <= 2:
        for q in range(-2, 3):
            out.append((q, 0, TIDE[6] if f == 0 else TIDE[5], False))
    return out


# ================================================================ 连环爆 / 斩击上的爆（原点 = 爆心脚下）

def boom(f, big=False, s=None):
    """紫白星爆：第 0 拍白芯团；第 1–2 拍四道长芒 + 四道短斜芒（亮紫）+ 外圈碎光；第 3–5 拍碎光往外散、变暗；地上一圈暗紫灼点。7 拍"""
    out = []
    cy = -8
    if s is None:
        s = 1.4 if big else 1.0
    if f < 0 or f > 6:
        return out
    if f == 0:
        r = int(3 * s)
        for dx in range(-r, r + 1):
            for dy in range(-r, r + 1):
                if abs(dx) + abs(dy) <= r:
                    out.append((dx, cy + dy, LT[6] if abs(dx) + abs(dy) <= r - 1 else LT[5], True))
    if 1 <= f <= 2:
        L1 = int((10 if f == 1 else 7) * s)
        L2 = int((5 if f == 1 else 3) * s)
        for (ux, uy, L) in ((1, 0, L1), (-1, 0, L1), (0, 1, L1 * 0.6), (0, -1, L1), (1, 1, L2), (-1, 1, L2), (1, -1, L2), (-1, -1, L2)):
            for i in range(int(L) + 1):
                u = i / max(1, L)
                c = LT[6] if u < 0.35 else LT[5] if u < 0.7 else LT[4]
                out.append((ux * i, cy + uy * i, c, u < 0.35))
        for dx in range(-2, 3):
            for dy in range(-2, 3):
                if abs(dx) + abs(dy) <= 2:
                    out.append((dx, cy + dy, LT[6], True))
    if 2 <= f <= 5:
        for q in range(10):
            a = q / 10 * math.tau + hf(q, 3, 8)
            rr = (5 + (f - 1) * 4 * (0.7 + 0.6 * hf(q, 3, 9))) * s
            y = cy + math.sin(a) * rr * 0.7 + (f - 2) ** 2 * 0.8
            c = LT[5] if f == 2 else LT[4] if f == 3 else LT[3] if f == 4 else LT[2]
            out.append((math.cos(a) * rr, y, c, False))
            if q % 3 == 0 and f <= 4:
                out.append((math.cos(a) * rr * 0.8, y + 1, TIDE[5], False))
    if f >= 1:   # 地上灼点
        R = int(6 * s)
        for q in range(14):
            if hsh(q, 5, 10) % 3 == 0:
                continue
            t = q / 14 * math.tau
            out.append((round(R * math.cos(t)), round(R * math.sin(t) * SQ), LT[2] if f < 4 else LT[1], 0.8))
    return out


# ================================================================ 收尾斩击（原点 = 纹章中心；d = 斩向单位向量；R 美术像素）

def final_blade(R, d, age, sil=False):
    """横贯纹章的一刀（出手一帧到位）：深蓝宽影（半宽 6）+ 白芯主刃（中间最宽 3，两头收尖）+ 亮紫外缘 + 一条亮紫细刃；
    0.35 秒内主刃变窄、宽影淡掉，细刃留到 0.6 秒。sil = 冲击帧剪影：只要主刃形状（返回颜色由调用方换）"""
    out = []
    dx, dy = d
    nx, ny = -dy, dx
    L = R * 1.1
    if age > 0.6:
        return out
    n = int(L * 2 * 2)
    k_main = 1.0 if age < 0.1 else max(0.0, 1.0 - (age - 0.1) / 0.25)
    for i in range(n + 1):
        u = i / n
        s = -L + 2 * L * u
        taper = math.sin(math.pi * u) ** 0.5
        if not sil and age < 0.45:   # 宽影
            hw0 = 10 * taper
            for j in range(-int(hw0), int(hw0) + 1):
                if abs(j) < 5 * taper * k_main:
                    continue
                if (i + j) % 2 and age > 0.2:
                    continue
                out.append((dx * s + nx * j, dy * s + ny * j, NAVY, 0.55 * (1 - age / 0.45)))
        hw = 5.0 * taper * k_main
        if hw >= 0.3 or sil:
            hw = max(hw, 2.5 * taper) if sil else hw
            m = int(math.ceil(hw * 2))
            for j in range(-m, m + 1):
                ww = j / 2.0
                if abs(ww) > hw + 0.25:
                    continue
                kk = abs(ww) / max(0.6, hw)
                c = LT[6] if kk < 0.4 else LT[5] if kk < 0.7 else LT[4]
                out.append((round(dx * s + nx * ww), round(dy * s + ny * ww), c, kk < 0.4 and not sil))
        if not sil and age <= 0.6 and abs(u - 0.5) < 0.47 * (1 - age / 0.8):   # 细刃
            out.append((round(dx * s - nx * 7), round(dy * s - ny * 7), LT[4], False))
    return out


def crack(R, ang, age, seed, life=2.0):
    """斩线下的地裂（贴地，压扁）：一条主裂从中心往外长出（0.12 秒），折线抖动 + 3 条短分叉；先白 / 亮紫热亮，0.5 秒冷成暗紫灰，life 秒内淡掉。
    返回 [(x, y, 颜色, 不透明度)]，原点 = 纹章中心"""
    out = []
    if age < 0 or age > life:
        return out
    grow = min(1.0, age / 0.12)
    L = R * 1.1 * grow
    al = 1.0 if age < life - 0.6 else max(0.0, (life - age) / 0.6)
    hot = age < 0.8

    def col(w):
        if age < 0.25:
            return LT[6] if w == 0 else LT[5]
        if hot:
            return LT[5] if w == 0 else LT[3]
        return COOL[2] if w == 0 else COOL[1]
    pts = []
    x, y = 0.0, 0.0
    step = 5
    k = 0
    while math.hypot(x, y) < L:
        a = ang + (hf(k, seed, 11) - 0.5) * 0.5
        x += math.cos(a) * step
        y += math.sin(a) * step * SQ
        pts.append((x, y))
        k += 1
    prev = (0.0, 0.0)
    for i, p in enumerate(pts):
        m = int(max(abs(p[0] - prev[0]), abs(p[1] - prev[1]))) + 1
        for q in range(m):
            u = q / m
            px_, py_ = prev[0] + (p[0] - prev[0]) * u, prev[1] + (p[1] - prev[1]) * u
            out.append((round(px_), round(py_), col(0), al))
            if i < len(pts) * 0.85:   # 大半段 2 格宽
                out.append((round(px_), round(py_) + 1, col(1), al))
        if i % 6 == 3 and i < len(pts) - 2:   # 分叉
            fa = ang + (0.7 if hsh(i, seed, 12) % 2 else -0.7)
            fl = 6 + 8 * hf(i, seed, 13)
            for s in range(int(fl)):
                out.append((round(p[0] + math.cos(fa) * s), round(p[1] + math.sin(fa) * s * SQ), col(1), al * 0.9))
        prev = p
    return out


# ================================================================ Noita 颗粒（解析轨迹：有重量、落地、停一下熄灭）

def grain(age, seed, kind="shard"):
    """一颗颗粒的位置与颜色（相对出生点，美术像素）：shard 紫白碎光 2 格 / rock 碎石 2–3 格 / drop 潮水水珠 2 格。
    返回 None = 已熄灭；否则 (x, y, 颜色, 边长)"""
    life = {"shard": 0.8, "rock": 1.0, "drop": 0.85}[kind]
    land = {"shard": 0.3, "rock": 0.5, "drop": 0.4}[kind]
    if age < 0 or age > life + land:
        return None
    a = hf(seed, 1, 31) * math.tau
    spd = 20 + 40 * hf(seed, 2, 32)
    vh = 30 + 50 * hf(seed, 3, 33)
    G = 260.0
    t = min(age, life)
    x = math.cos(a) * spd * t
    y = math.sin(a) * spd * t * SQ
    h = max(0.0, vh * t - 0.5 * G * t * t)
    t_land = 2 * vh / G
    if t >= t_land:
        x = math.cos(a) * spd * t_land
        y = math.sin(a) * spd * t_land * SQ
        h = 0.0
    landed = t >= t_land
    if kind == "shard":
        c = LT[6] if age < 0.15 else LT[5] if age < 0.4 else LT[3]
        sz = 2
    elif kind == "rock":
        c = (LT[4] if age < 0.2 else DUST[3]) if not landed else DUST[2]
        sz = 4 if seed % 2 else 3
    else:
        c = TIDE[5] if not landed else TIDE[3]
        sz = 2
    return (x, y - h, c, sz)


def hx3(s):
    s = s.lstrip("#")
    return (int(s[0:2], 16), int(s[2:4], 16), int(s[4:6], 16))


# ================================================================ 收尾斩击后的崩解（11-05 用户「碎石和尘土比原版薄，少了原作那种崩解感」）
# 节奏：0–0.12 裂缝爆亮长出 → 0.06 起地面块沿裂缝掀起（离中心越远越晚）→ 0.12 起两侧尘墙冲起翻卷 → 约 0.5 秒碎石落地、弹一下、部分碎成小块 → 0.45 秒起尘土塌下散开，0.8 秒散完。
WARM = ["#211d1a", "#332d28", "#4a423b", "#655b52", "#8a8076", "#aea398"]   # 地面暖灰（尘 / 碎石）
SLAB_N = 12       # 地面块总数（两侧合计）：配角，11-05 改主角为怪物崩解后减半
PLUME_N = 8       # 每侧尘墙团数（配角，压暗）


def slab(age, seed, nd=(1.0, 0.0)):
    """一块地面碎石（原点 = 它在裂缝边上的出生点；返回 [(x, y, 颜色, 不透明度)]）：4–8 格实心不规则块，暗面 + 亮顶边（刚掀起时被斩光照成亮紫边）；
    掀起（上抛 + 往裂缝外侧飞）→ 落地 → 弹一下 → 停住；三分之一落地时碎成 3 小块；1.5 秒内淡掉"""
    out = []
    if age < 0 or age > 1.5:
        return out
    w = 5 + int(4 * hf(seed, 1, 41))
    h = max(3, int(w * (0.55 + 0.3 * hf(seed, 2, 42))))
    spd = 14 + 30 * hf(seed, 3, 43)   # 往裂缝外侧（nd = 地面法向）飞，带一点沿裂缝的偏
    tang = -6 + 12 * hf(seed, 4, 44)
    vx = nd[0] * spd - nd[1] * tang
    vy = (nd[1] * spd + nd[0] * tang) * SQ
    vh = 100 + 60 * hf(seed, 5, 45)
    G = 320.0
    t1 = 2 * vh / G
    vh2 = vh * 0.28
    t2 = 2 * vh2 / G
    al = 1.0 if age < 1.2 else max(0.0, (1.5 - age) / 0.3)
    if age < t1:
        t = age
        x, y, z = vx * t, vy * t, vh * t - 0.5 * G * t * t
    elif age < t1 + t2:
        t = age - t1
        x, y, z = vx * (t1 + t * 0.4), vy * (t1 + t * 0.4), vh2 * t - 0.5 * G * t * t
    else:
        x, y, z = vx * (t1 + t2 * 0.4), vy * (t1 + t2 * 0.4), 0.0
    landed = age >= t1
    lit = age < 0.18
    if landed and seed % 3 == 0:   # 碎成 3 小块
        tt = age - t1
        for q in range(3):
            a = q * 2.1 + hf(seed, q, 46)
            d = min(1.0, tt / 0.25) * (3 + 3 * hf(seed, q, 47))
            zz = max(0.0, 8 * tt - 30 * tt * tt) if tt < 0.27 else 0.0
            cx, cy = x + math.cos(a) * d, y + math.sin(a) * d * SQ - zz
            for dx in range(2):
                for dy in range(2):
                    out.append((cx + dx, cy + dy, WARM[3] if dy == 0 else WARM[1], al))
        return out
    rot = 1 if hf(seed, 6, 48) > 0.5 else 0
    for dx in range(w):
        for dy in range(h):
            if (dx in (0, w - 1)) and (dy in (0, h - 1)) and hsh(dx, dy, seed) % 2:
                continue   # 缺角（不规则）
            if dy == 0:
                c = LT[4] if lit else WARM[4]
            elif dx == (w - 1 if rot else 0):
                c = WARM[1]
            else:
                c = WARM[3] if dy == 1 else WARM[2]
            out.append((x - w / 2 + dx, y - z - h + dy, c, al))
    if not landed:   # 空中：地上一点影子
        out.append((x, y + 1, WARM[0], 0.6 * al))
        out.append((x + 1, y + 1, WARM[0], 0.6 * al))
    return out


def plume(age, seed, nside):
    """一团尘墙（原点 = 裂缝边上的根部；nside = 往外的地面法向）：6 团尘块冲起、边翻卷边长大（0.12–0.4 秒），顶边带一点白紫光；
    0.4 秒后塌下、往外摊开、变淡，0.8 秒散完。返回 [(x, y, 颜色, 不透明度)]"""
    out = []
    if age < 0 or age > 0.8:
        return out
    up = min(1.0, age / 0.3)
    fall = max(0.0, (age - 0.4) / 0.4)
    for b in range(6):
        h0 = hf(seed, b, 51)
        H = (10 + 18 * h0) * (1 - (1 - up) ** 2) * (1 - 0.75 * fall)
        r = 3 + 4 * up + 3 * fall + 2 * h0
        curl = math.sin(age * 9 + b * 1.7) * (1 + 2 * up)
        spread = (3 + 6 * h0) * up + 10 * fall
        tx, ty = -nside[1], nside[0]   # 沿裂缝方向铺开
        along = (b - 2.5) * 3.5
        bx = nside[0] * spread + tx * along + curl
        by = (nside[1] * spread + ty * along) * SQ - H
        al = 0.5 * (1 - fall) ** 1.3   # 配角：压暗，不盖住怪物崩解
        if al <= 0.03:
            continue
        ri = int(math.ceil(r))
        for dx in range(-ri, ri + 1):
            for dy in range(-ri, ri + 1):
                d = math.hypot(dx, dy * 1.2)
                ang8 = int((math.atan2(dy, dx) + math.pi) / math.tau * 8) % 8
                rr = r * (0.8 + 0.35 * hf(b * 8 + ang8, seed, 52))   # 边缘起伏（不成正圆）
                if d > rr or (d > rr * 0.7 and hsh(dx + b, dy, seed + int(age * 15)) % 4 == 0):
                    continue
                top = dy < -rr * 0.45
                if top and age < 0.25:
                    c = LT[4] if d > rr * 0.5 else LT[5]
                elif d > rr * 0.75:
                    c = WARM[2]
                elif top:
                    c = WARM[5]
                else:
                    c = WARM[4] if d < rr * 0.4 else WARM[3]
                out.append((bx + dx, by + dy, c, al))
    return out


# ================================================================ 收尾大爆（11-05 用户看实机录像：「感觉缺少最后的爆炸的冲击力」；同 ult_px_ir.gd _draw_blast）
BLAST_T = 2 / 15    # 预备 2 拍：光点往中心吸、周围压暗
SHOCK_T = 3.5 / 15  # 冲击环从半径一半推到判定边缘


def shock_at(R, d):
    """冲击环推到距中心 d（美术像素）的时刻（相对收尾斩击，秒）；碎石 / 尘墙按它往外起"""
    k = min(1.0, max(0.0, (d / R - 0.5) / 0.5))
    return BLAST_T + (1 - math.sqrt(1 - k)) * SHOCK_T


def blast_prep(R, fa):
    """预备：20 粒光点从 0.55–0.8 R 往中心吸（游戏里另画一层 0.28 的压暗椭圆）"""
    out = []
    if fa >= BLAST_T:
        return out
    k = fa / BLAST_T
    for i in range(20):
        a = math.tau * (i + hf(i, 9, 61)) / 20 + k * 1.5
        r = R * (0.55 + 0.25 * hf(i, 9, 62)) * (1 - k) ** 1.4 + 2
        x, y = math.cos(a) * r, math.sin(a) * r * SQ - 10
        out.append((x, y, LT[6] if k > 0.5 else LT[5], k > 0.5))
        out.append((x - math.cos(a) * 2, y - math.sin(a) * 2 * SQ, LT[4], False))
    return out


def blast_core(R, bf):
    """亮核（2 拍）：三层实心椭圆，外亮紫 → 淡紫 → 白芯，半径 0.5 R（第 2 拍 0.44 R、暗一阶）。返回 [(rx, 颜色)] 由外到内"""
    if bf < 0 or bf > 1:
        return []
    rx = R * (0.5 if bf == 0 else 0.44)
    return [(rx, LT[4] if bf == 0 else LT[3]), (rx * 0.78, LT[5] if bf == 0 else LT[4]), (rx * 0.52, LT[6] if bf == 0 else LT[5])]


def shock_ring(R, tau):
    """冲击环：半径 0.5 R → R（先快后慢），厚 5 格（白 → 紫），环后 6–14 格地面一闪；到边后 2 拍淡掉"""
    out = []
    if tau < 0 or tau > SHOCK_T + 2 / 15:
        return out
    us = min(1.0, tau / SHOCK_T)
    rr = R * (0.5 + 0.5 * (1 - (1 - us) ** 2))
    fade = 1.0 if tau < SHOCK_T else max(0.0, 1 - (tau - SHOCK_T) / (2 / 15))
    cols = [LT[6], LT[6], LT[5], LT[4], LT[3]] if tau < SHOCK_T else [LT[5], LT[4], LT[3], LT[2], LT[2]]
    n = int(rr * 6.6) + 16
    for q in range(n):
        t = q / n * math.tau
        cx, cy = math.cos(t), math.sin(t) * SQ
        for j in range(5):
            out.append((round(cx * (rr - j)), round(cy * (rr - j)), cols[j], fade))
        if tau < SHOCK_T:
            for j2 in range(6, 15, 2):
                if (q + j2) % 3 == 0:
                    continue
                out.append((round(cx * (rr - j2)), round(cy * (rr - j2)), LT[3], 0.45 * (1 - j2 / 15)))
    return out


# ================================================================ 怪物崩解喷散（同 ult_px_ir.gd _draw_sprays；游戏里另叠引擎原有的按怪物贴图像素碎开 kill_burst）
SPRAY_N = 22


def spray(age, sd, out_ang, k, col):
    """怪物代表色像素喷散：col = (r, g, b) 0–1；返回 [(x, y, (r,g,b,a), 发光, 边长)]"""
    res = []
    if age < 0 or age > 1.3:
        return res
    def lt(c, a):
        return tuple(min(1.0, x + (1 - x) * a) for x in c)
    def dk(c, a):
        return tuple(x * (1 - a) for x in c)
    cols = [lt(col, 0.45), lt(col, 0.15), col, dk(col, 0.3)]
    for q in range(int(SPRAY_N * min(1.4, k))):
        ang = out_ang + (hf(q, sd, 71) - 0.5) * 2.2
        spd = (30 + 70 * hf(q, sd, 72)) * k
        vh = 30 + 60 * hf(q, sd, 73)
        G = 260.0
        t_land = 2 * vh / G
        t = min(age, 0.9)
        tt = min(t, t_land)
        h = max(0.0, vh * tt - 0.5 * G * tt * tt) if t < t_land else 0.0
        c = cols[q % 4]
        hot = age < 2 / 15 and q % 3 == 0
        if hot:
            c = (1.0, 1.0, 1.0)
        al = 1.0 if age < 0.9 else max(0.0, (1.3 - age) / 0.4)
        res.append((math.cos(ang) * spd * tt, math.sin(ang) * spd * tt * SQ - h, c + (al,), hot, 2 if q % 3 != 2 else 1))
    return res
