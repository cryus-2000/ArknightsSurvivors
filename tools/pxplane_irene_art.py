"""艾丽妮转平面（docs/272）的像素图形：刺剑光刃 / 裂潮 / 裂潮余波 / 判决 / 手炮 / 起风，以及运行时件（刺击光刃、弹道、剑气细刺、提灯光圈）的同一套画法（Python 版）。
tools/pxplane_bake_irene.py 用它烤帧条（game/art/fx/pxp/pxp_ir_*.png + game/data/pxp_irene.json），
tools/pxplane_gif_irene.py 用它拼送审 GIF；运行时件在游戏里由 fx_pxplane_ir.gd 逐格画，算法与本文件 lance() / tracer() / qi_needle() / lamp_ring() 一一对应，改一边要改另一边。
单位：美术像素（游戏里 1 美术像素 = g.PX = 2 世界像素）。全部确定性（不用随机数，抖动用坐标哈希）。

意象（深海审判、光与潮；11-05 用户改定：白 + 亮紫光刃为主，深蓝潮水作辅色，金色只留手提灯）：
- 光刃 LT：白 → 亮紫（刺剑、裂潮刀光、判决光矛、手炮火光；11-05 用户改定主基调白 + 亮紫）；手提灯 LAMP 金色作点缀；
- 潮水 TIDE：深海蓝 → 白沫（刺击潮痕、裂潮水花、起风水旋）。不用红。
每招招牌不同：普攻 = 细长穿刺光刃；S1 = 粗白光刃 + 目标脚下卷起一道水旋；S2 = 金色大月牙劈开潮水（月牙外沿一排水花炸开）；
裂潮余波 = 细薄新月；S3 = 地面审判光环 + 环上竖起一圈光矛 + 提灯光柱；手炮 = 弹道细线 + 小爆 + 黑烟。"""
import math

from pxplane_saria_art import Buf, hx, hsh, hf

LT = ["#1a0c28", "#3a1a58", "#6a32a0", "#9d58e0", "#cf98ff", "#f0e2ff", "#ffffff"]   # 白 + 亮紫（11-05 用户：主基调白色 + 亮紫色，依据见 docs/272 §1）
LAMP = ["#1c1408", "#4a3612", "#8c6a26", "#cfa24a", "#efd08a", "#fff0c6", "#ffffff"]   # 金：只留给手提灯（点缀）
TIDE = ["#050b1a", "#0b1a38", "#143062", "#21508c", "#3f80bc", "#90c4ea", "#e6f6ff"]
SMOKE = ["#141418", "#24242a", "#3a383e", "#56525a"]
SHADOW = "#0e1218"
SQ = 0.72
WAIST = 10       # 刀光 / 光刃离地高度（美术像素）
LANCE_H = 11     # 刺击光刃离地高度

# 尺寸档（美术像素 = 判定半径 ÷ 2；范围成长放大时游戏挑最近一档，只整数放大）
S2_R = [100, 116, 132]    # 裂潮：153 × op_range × 1.3
FIN_R = [75, 87, 99]      # 裂潮余波：tide_r 150 × op_range
S3_R = [80, 93, 106]      # 判决：s3_r 160 × op_range
GALE_R = [35, 45]         # 卷风 70 / 响应起风 90
TIDE3_R = 75              # 裂潮·三度：tide_r 150
GALE2_R = 70              # 卷风·追斩：gale_r 70 × 2
BOOM_R = 20               # 手炮小爆：cannon_r 40


def _gpt(r, a, lift=0.0):
    return (r * math.cos(a), r * math.sin(a) * SQ - lift)


def _star(b, x, y, arm, cols, keep=False):
    """四芒小星：中心白，臂沿屏幕横竖（cols = [芯, 臂近, 臂远]）"""
    put = b.put_if_empty if keep else b.put
    put(x, y, cols[0])
    for i in range(1, arm + 1):
        c = cols[1] if i < arm else cols[2]
        for dx, dy in ((i, 0), (-i, 0), (0, i), (0, -i)):
            put(x + dx, y + dy, c)


# ================================================================ 运行时件（游戏 fx_pxplane_ir.gd 同算法）

def lance(L, d, f, tier, gust=False, link=False):
    """刺击光锥（运行时逐格画；11-05 用户第二版「光刺不明显、要重新设计」）：原点 = 她的脚底，沿世界方向 d 刺到判定长度 L（美术像素），离地 LANCE_H。
    第 0 拍：她身前只闪一颗四芒星（精二 / 起风八芒 + 一圈光点）；第 1–2 拍：光锥一下贯穿到全长——**根宽头尖的实心块面**，白芯 + 淡紫 + 亮紫外缘；
    之后收成一条变窄的亮线，再从根部熄灭，最后只剩刃尖几点。gust = 起风：根更宽（6 格）、长 1.1 倍、亮态多停一拍。
    精一：刃尖往前崩出三道短碎芒（在判定长度 1.1 倍以内）。返回 [(x, y, 颜色, 发光)]，坐标相对脚底（美术像素，已含抬高）"""
    dx, dy = d
    nx, ny = -dy, dx
    out = []
    hot_f = 3 if gust else 2
    if f < 0 or f > hot_f + 3:
        return out
    if gust:
        L = L * 1.1
    s0 = 4.0
    W0 = 6.0 if (gust or link) else 3.5
    hx0, hy0 = dx * (s0 + 6), dy * (s0 + 6) - LANCE_H - 1
    cells = {}

    def put(x, y, c, glow=False, keep=False):
        k = (int(round(x)), int(round(y)))
        if keep and k in cells:
            return
        cells[k] = (c, glow)

    if 1 <= f <= hot_f:   # 实心光锥
        Lc = L
        n = int((Lc - s0) * 2) + 1
        for i in range(n + 1):
            u = i / n
            s = s0 + (Lc - s0) * u
            ur = (s - s0) / max(1.0, L - s0)   # 按全长算锥度（第 0 拍是半截锥）
            hw = W0 * (1.0 - ur) ** 0.85
            if ur < 0.06:
                hw *= 0.7 + 5.0 * ur
            m = int(math.ceil(hw * 2))
            for j in range(-m, m + 1):
                w = j / 2.0
                if abs(w) > hw + 0.25:
                    continue
                k = abs(w) / max(0.6, hw)
                if k < 0.34 or hw < 0.9:
                    c, gl = LT[6], (i + j) % 2 == 0   # 白芯隔一格出 emit（docs/272 §6）
                elif k < 0.62:
                    c, gl = LT[5], False
                elif k < 0.86:
                    c, gl = LT[4], False
                else:
                    c, gl = LT[3], False
                put(dx * s + nx * w, dy * s - LANCE_H + ny * w, c, gl)
    elif f > hot_f:   # 收成亮线，从根部熄灭
        g2 = f - hot_f   # 1 / 2 / 3
        lo = [0.0, 0.0, 0.4, 0.75][g2]
        n = int(L - s0)
        for i in range(n + 1):
            u = i / n
            if u < lo:
                continue
            s = s0 + (L - s0) * u
            if g2 == 3 and i % 2:
                continue
            c = LT[6] if g2 == 1 and u < 0.95 else (LT[5] if g2 <= 2 else LT[4])
            put(dx * s, dy * s - LANCE_H, c, g2 == 1)
            if g2 == 1 and u < 0.6 and (gust or link):
                put(dx * s + nx, dy * s - LANCE_H + ny, LT[4])
                put(dx * s - nx, dy * s - LANCE_H - ny, LT[4])
    # 出手星芒
    if f <= 1 and not link:
        arm = [6 if (gust or tier >= 2) else 5, 2][f]
        b = Buf()
        _star(b, hx0, hy0, arm, [LT[6], LT[5], LT[4]])
        if f == 0:
            for q in (-1, 1):
                b.put_if_empty(hx0 + q, hy0, LT[6])
                b.put_if_empty(hx0, hy0 + q, LT[6])
            if tier >= 2 or gust:   # 精二 / 起风：斜向四芒（八芒）+ 一圈光点
                for q in range(1, 3):
                    for sx, sy in ((1, 1), (1, -1), (-1, 1), (-1, -1)):
                        b.put_if_empty(hx0 + sx * q, hy0 + sy * q, LT[5] if q == 1 else LT[4])
                for q in range(8):
                    a = q / 8 * math.tau
                    b.put_if_empty(hx0 + round(math.cos(a) * 6), hy0 + round(math.sin(a) * 6), LT[4])
        for (x, y), c in b.p.items():
            put(x, y, c, c == LT[6])
    # 精一：刃尖崩出三道短碎芒
    if tier >= 1 and not link and hot_f <= f <= hot_f + 1:
        tx, ty = dx * L, dy * L - LANCE_H
        for q, sp in enumerate((-0.45, 0.0, 0.45)):
            a = math.atan2(dy, dx) + sp
            r0 = 1 + (f - hot_f) * 2
            for k in range(3 if f == hot_f else 2):
                rr = r0 + k
                if rr > L * 0.1 + 2:
                    break
                put(tx + math.cos(a) * rr, ty + math.sin(a) * rr, LT[6] if k == 0 and f == hot_f else LT[4], keep=True)
    return [(x, y, c, gl) for (x, y), (c, gl) in cells.items()]


def lance_gd(L, d, f, tier, gust=False):
    """刺击的贴地部分：光锥在地上的投影阴影（亮态各拍）；起风另有一道潮痕（刺击线两侧两条压扁细水纹 + 几点白沫，6 拍淡掉）。普攻不画水"""
    dx, dy = d
    out = []
    if gust:
        L = L * 1.1
    n = max(4, int(L))
    hot_f = 3 if gust else 2
    if 1 <= f <= hot_f:
        for i in range(int(n * 0.15), int(n * 0.9)):
            out.append((dx * i, dy * i, SHADOW, 0.5))
    if gust and f <= 5:
        gx, gy = -dy, dx * SQ
        gl = math.hypot(gx, gy) or 1.0
        gx, gy = gx / gl, gy / gl
        cols = [TIDE[5], TIDE[5], TIDE[4], TIDE[3], TIDE[3], TIDE[2]]
        for side in (-1, 1):
            for i in range(int(n * 0.28), n):
                u = i / n
                if u > 0.3 + 0.7 * min(1.0, (f + 1) / 2.0):
                    continue
                if hsh(i // 3, side, 41 + f // 2) % 4 == 0:
                    continue
                if f >= 4 and (i + f) % 2:
                    continue
                off = 3.5 + 2.0 * u + 0.6 * f + (1 if (i // 4) % 2 else 0)
                out.append((dx * i + gx * off * side, dy * i + gy * off * side, cols[f], 1.0))
    return out


def charge(d, f, tier):
    """起风蓄光（出手前 0.2 秒，3 拍）：身前出手点四周 8 粒光点往里收拢，越收越亮，第 2 拍聚成一团白芯。原点 = 她的脚底"""
    dx, dy = d
    hx0, hy0 = dx * 10, dy * 10 - LANCE_H - 1
    out = []
    if f < 0 or f > 2:
        return out
    rr = [16, 9, 3][f]
    for q in range(8):
        a = q / 8 * math.tau + f * 0.5
        x, y = hx0 + math.cos(a) * rr, hy0 + math.sin(a) * rr
        out.append((x, y, LT[4] if f == 0 else LT[5], f == 2))
        out.append((x + 1, y, LT[3] if f == 0 else LT[4], False))
        if f < 2:
            out.append((hx0 + math.cos(a) * (rr + 2), hy0 + math.sin(a) * (rr + 2), LT[3], False))
    for dx2, dy2 in ((0, 0), (1, 0), (-1, 0), (0, 1), (0, -1)):
        if f == 0 and (dx2 or dy2):
            continue
        out.append((hx0 + dx2, hy0 + dy2, LT[6] if f >= 1 else LT[5], True))
    return out


def pierce(d, f, tier):
    """被贯穿的那只身上闪一个小十字（2 拍）：白芯、臂端亮紫。原点 = 被刺中处"""
    out = []
    if f < 0 or f > 1:
        return out
    arm = 3 if f == 0 else 2
    b = Buf()
    _star(b, 0, 0, arm, [LT[6], LT[5] if f == 0 else LT[4], LT[4] if f == 0 else LT[3]])
    for (x, y), c in b.p.items():
        out.append((x, y, c, c == LT[6]))
    return out


def tracer(p0, p1, f):
    """手炮弹道（运行时）：枪口 → 目标的一道 1 像素金白细线，第 0 拍全长（近端稀疏）、第 1 拍只剩后 35%（目标那头），之后消失"""
    out = []
    x0, y0 = p0
    x1, y1 = p1
    n = max(2, int(max(abs(x1 - x0), abs(y1 - y0))))
    if f > 1:
        return out
    for i in range(n + 1):
        u = i / n
        if f == 1 and u < 0.65:
            continue
        if u < 0.25 and i % 2:
            continue
        c = LT[6] if u > 0.8 else (LT[5] if u > 0.4 else LT[3])
        if f == 1:
            c = LT[4] if u > 0.85 else LT[2]
        out.append((x0 + (x1 - x0) * u, y0 + (y1 - y0) * u, c, f == 0 and u > 0.8))
    return out


def qi_needle(d, tier, bt):
    """后期剑气（thrust 类，运行时）：一枚飞行的金白细刺——白尖 + 金身，身后一串深蓝水珠拖尾；精一拖尾更长、精二刺尖一颗小星。原点 = 剑气位置（已抬高）"""
    dx, dy = d
    nx, ny = -dy, dx
    out = []
    L = 6 + 3 * tier
    for s in range(L):
        c = LT[6] if s == 0 else (LT[5] if s < 3 else LT[4] if s < L - 2 else LT[3])
        out.append((-dx * s, -dy * s, c, s <= 1))
        if 1 <= s <= 2 + tier:
            out.append((-dx * s + nx, -dy * s + ny, LT[3], False))
    tl = 5 + 4 * tier
    for s in range(L, L + tl):
        if (s + bt) % 3 == 0:
            continue
        w = 1 if (s // 2 + bt) % 2 else -1
        out.append((-dx * s + nx * w * (0 if s < L + 2 else 1), -dy * s + ny * w * (0 if s < L + 2 else 1), TIDE[5] if s < L + 3 else TIDE[4] if s < L + 6 else TIDE[3], False))
    if tier >= 2:
        b = Buf()
        _star(b, dx * 1, dy * 1, 1 + (bt % 2), [LT[6], LT[5], LT[3]])
        for (x, y), c in b.p.items():
            out.append((x, y, c, c == LT[6]))
    return out


def lamp_ring(r, bt, age, life):
    """连携「提灯一照」区域（运行时，贴地）：只画边——断续金边（每 2 拍转一格）+ 内侧 2 格暗金内边，淡入淡出；r 美术像素。返回 [(x, y, 颜色, 不透明度)]"""
    out = []
    al = min(1.0, age / 0.15) * min(1.0, (life - age) / 0.3)
    if al <= 0.0:
        return out
    n = int(r * 6.6)
    rot = (bt // 2) % 32 / 32.0 * math.tau / 10.0
    for q in range(n):
        t = q / n * math.tau
        seg = ((t - rot) % (math.tau / 10.0)) / (math.tau / 10.0)
        x, y = round(r * math.cos(t)), round(r * math.sin(t) * SQ)
        if seg < 0.72:
            out.append((x, y, LT[5] if seg < 0.5 else LT[4], al))
        x2, y2 = round((r - 2) * math.cos(t)), round((r - 2) * math.sin(t) * SQ)
        if q % 2 == 0:
            out.append((x2, y2, LT[2], al * 0.8))
    return out


def lamp_motes(r, bt, seed):
    """提灯照亮区域里往上飘的金色光尘（运行时，立起，确定性）：12 粒，各自 0.6 秒一个周期"""
    out = []
    for k in range(12):
        a = (k * 2.39996 + seed) % math.tau
        rr = r * (0.2 + 0.75 * hf(k, int(seed * 10), 5))
        ph = (bt + k * 3) % 9
        x = round(rr * math.cos(a))
        y = round(rr * math.sin(a) * SQ) - 2 - ph * 2
        c = LT[6] if ph < 2 else LT[5] if ph < 5 else LT[3]
        out.append((x, y, c, ph < 2))
        if ph < 4:
            out.append((x, y + 1, LT[3], False))
    return out


def lantern(bt, raised):
    """手提灯（S3 / 连携期间她手里的提灯，状态件）：小灯笼框 + 灯芯，灯芯每 2 拍闪一下。原点 = 提灯挂点"""
    b = Buf()
    for y in range(1, 6):
        b.put(-2, y, LAMP[2])
        b.put(2, y, LAMP[2])
    for x in range(-2, 3):
        b.put(x, 0, LAMP[3])
        b.put(x, 6, LAMP[2])
    b.put(0, -1, LAMP[3])
    hot = (bt // 2) % 2 == 0
    for y in range(2, 5):
        for x in range(-1, 2):
            b.put(x, y, LAMP[6] if (x == 0 and y == 3) or hot and abs(x) + abs(y - 3) <= 1 else LAMP[5])
    return [(x, y, c, c == LAMP[6]) for (x, y), c in b.p.items()]


# ================================================================ 帧条（烤）

def _moon(b, R, a, half, th, v_lo, v_hi, ramp, lift, inner_dim=False, sweep=1):
    """腰高月牙（地面平面里的弧，压扁后抬到 lift）：外缘 1 像素白刃线，往里一阶阶变暗，最厚处偏刀头；v ∈ [v_lo, v_hi] 才画（扫出 / 收刀）"""
    n = max(16, int(R * half * 2.2))
    for i in range(n + 1):
        v = i / n
        if v < v_lo or v > v_hi:
            continue
        t = a + (-half + 2 * half * v) * sweep
        w = th * (math.sin(math.pi * min(1.0, v * 1.15)) ** 0.8)
        w = max(0.0, w)
        tw = int(round(w))
        for j in range(tw + 1):
            x, y = _gpt(R - j, t, lift)
            if j == 0:
                c = ramp[6] if 0.08 < v < 0.95 else ramp[5]
            elif j == 1:
                c = ramp[6] if tw >= 6 and 0.15 < v < 0.9 else ramp[5]
            elif j == 2 and tw >= 6:
                c = ramp[5]
            elif j >= tw - 1 and tw >= 3:
                if inner_dim and hsh(i, j, 7) % 3 == 0:
                    continue
                c = ramp[2]
            else:
                c = ramp[4] if j <= tw * 0.5 else ramp[3]
            b.put(x, y, c)


def _spray(b, x0, y0, out_dx, out_dy, h, f, seed, scale=1.0):
    """一簇水花（不是柱）：从地面点往上、往外分两三股水流甩出（抛物线，根部 2 格粗、往上收细），顶上一团白沫；f 是这簇自己的拍子（0 起）。
    0：冒出半高；1：最高、白沫头最亮；2：沫头碎成水珠往外飞；3：水珠下落、流变短；4：只剩地上几点沫"""
    if f < 0 or f > 4:
        return
    streams = 2 + (seed % 2)
    for s in range(streams):
        lean = (s - (streams - 1) / 2.0) * 0.8 + (hf(seed, s, 3) - 0.5) * 0.6
        hh = h * (0.75 + 0.5 * hf(seed, s, 5)) * scale
        top = [0.55, 1.0, 0.85, 0.5, 0.0][f]
        m = int(hh * top)

        def at(u):
            return (x0 + out_dx * u * hh * 0.45 + lean * u * hh * 0.35, y0 + out_dy * u * hh * 0.25 - hh * u * (1.2 - 0.6 * u))
        for k in range(m):
            u = k / max(1.0, hh)
            x, y = at(u)
            if f >= 2 and k < m * 0.5 and (k + s) % 2:
                continue
            c = TIDE[6] if (k >= m - 2 or u > 0.6) else (TIDE[5] if u > 0.3 else TIDE[4])
            b.put(x, y, c)
            if u < 0.55 and f <= 2:
                b.put(x + 1, y, TIDE[5] if u > 0.25 else TIDE[3])
        hx_, hy_ = at(top if f <= 1 else 0.85)
        if f <= 1:   # 白沫头
            for dx, dy in ((0, 0), (1, 0), (-1, 0), (0, -1), (1, -1), (0, 1)):
                if f == 0 and dy == -1:
                    continue
                b.put(hx_ + dx, hy_ + dy, TIDE[6] if dy <= 0 else TIDE[5])
        else:   # 碎开的水珠（2 格）往外飞、下落
            for q in range(4):
                fx = hx_ + (q - 1.5) * 2.2 + out_dx * (f - 1) * 3 + lean * 2
                fy = hy_ + (f - 2) * (2 + q) + (q % 2) * 2
                c = TIDE[6] if f == 2 else TIDE[5] if f == 3 else TIDE[4]
                b.put(fx, fy, c)
                b.put(fx + 1, fy, TIDE[5] if f <= 3 else TIDE[3])
    if f <= 3:   # 根部白沫
        for q in range(-3, 4):
            if hsh(q, seed, 9) % 3 == 0:
                continue
            b.put_if_empty(x0 + q, y0 - (1 if abs(q) < 2 else 0), TIDE[6] if f <= 1 else TIDE[5])


def s2_up(R, tier, deg):
    """S2「裂潮」：腰高金色大月牙（外缘白刃线，最厚 6 格）一拍扫出；月牙前沿的地面上一排水花被劈开炸起（高低不一、往外甩、碎成白沫落下）。
    精二：月牙内侧晚一拍跟一道深蓝潮刃（光在前、潮在后）。8 拍"""
    a = math.radians(deg)
    half = 0.8 * 0.92
    fr = []
    spec = [(0.0, 0.62, 8), (0.0, 1.0, 9), (0.12, 1.0, 7), (0.35, 1.0, 4), (0.65, 1.0, 2), None, None, None]
    ks = 9 + R // 20
    for f in range(8):
        b = Buf()
        sp = spec[f]
        for k in range(ks):   # 水花（先画，月牙盖在上面）
            v = (k + 0.5) / ks + (hf(k, R, 1) - 0.5) * 0.06
            t = a - half + 2 * half * v
            if hsh(k, R, 2) % 5 == 0:
                continue
            rr = R + 2 + 4 * hf(k, R, 4)
            x0, y0 = _gpt(rr, t)
            fk = f - 1 - int(v * 2)   # 扫到哪儿哪儿先炸
            h = 9 + 9 * hf(k, R, 6)
            _spray(b, x0, y0, math.cos(t), math.sin(t), h, fk, hsh(k, R, 8))
        if sp is not None:
            lo, hi, th = sp
            m = Buf()
            _moon(m, R, a, half, th, lo, hi, LT, WAIST, inner_dim=f >= 2)
            if tier >= 2 and 1 <= f <= 4:
                _moon(m, R - th - 2, a, half * 0.92, max(1, th - 3), max(0.0, lo - 0.1), hi, TIDE, WAIST, inner_dim=True)
            if f == 0:   # 刀头热白
                x, y = _gpt(R - 2, a - half + 2 * half * 0.62, WAIST)
                _star(m, x, y, 2, [LT[6], LT[5], LT[4]])
            b.merge(m)
        fr.append(b)
    return fr


def s2_gd(R, deg):
    """裂潮贴地：月牙投影阴影（前 4 拍）+ 月牙前方往外漫开的一摊碎白沫（噪声取阈值，越来越稀直到散掉）+ 两道压扁细水纹"""
    a = math.radians(deg)
    half = 0.8 * 0.92
    fr = []
    for f in range(8):
        b = Buf()
        if f <= 3:
            n = int(R * half * 2)
            for i in range(n):
                if f >= 2 and i % 2:
                    continue
                x, y = _gpt(R - 3, a - half + 2 * half * i / n)
                b.put(x, y, SHADOW)
        if f >= 2:
            thr = 0.55 + 0.08 * (f - 2)
            spread = 3 + (f - 2) * 2.5
            n = int(R * half * 2.4)
            for i in range(n):
                t = a - half + 2 * half * i / n
                for j in range(int(spread)):
                    if hf(i, j, 31 + f // 2) < thr:
                        continue
                    x, y = _gpt(R + 1 + j, t)
                    b.put(x, y, TIDE[6] if j < spread * 0.4 and f <= 4 else TIDE[5] if f <= 5 else TIDE[4])
            for rr, cc in ((R + spread + 2, TIDE[4]), (R - 6, TIDE[3])):
                for i in range(n):
                    if (i // 3 + f) % 3 == 0:
                        continue
                    x, y = _gpt(rr + (1 if (i // 5) % 2 else 0), a - half * 0.9 + 1.8 * half * i / n)
                    b.put_if_empty(x, y, cc)
        fr.append(b)
    return fr


def fin_up(R, deg):
    """精二「裂潮余波」（每第 3 刺收尾）：一道细薄的新月（两边都是弧，最厚 3 格，白多金少，冷亮），扫出极快；刀尖甩出一线深蓝水珠。6 拍"""
    a = math.radians(deg)
    half = 0.785 * 0.92
    fr = []
    spec = [(0.0, 0.75, 3), (0.0, 1.0, 3), (0.2, 1.0, 2), (0.5, 1.0, 1), (0.8, 1.0, 1), None]
    for f, sp in enumerate(spec):
        b = Buf()
        if sp is not None:
            lo, hi, th = sp
            _moon(b, R, a, half, th, lo, hi, LT, WAIST)
            # 新月内弧：内侧再挖掉一道（两边都是弧）
            n = int(R * half * 2.2)
            for i in range(n + 1):
                v = i / n
                if v < lo or v > hi:
                    continue
                t = a - half + 2 * half * v
                w = th * (math.sin(math.pi * v) ** 0.8)
                x, y = _gpt(R - w - 1, t, WAIST)
                if hsh(i, f, 3) % 3:
                    b.put_if_empty(x, y, TIDE[4] if f <= 1 else TIDE[3])
        if 1 <= f <= 4:   # 刀尖甩出的水珠线
            for q in range(4):
                v = 1.0 + 0.04 * q
                t = a - half + 2 * half * v
                x, y = _gpt(R + 1 + q * 0.5, t, WAIST - (f - 1) * 1.5 + q * 0.5)
                b.put(x, y + (f - 1) * q * 0.7, TIDE[5] if q < 2 else TIDE[4])
        fr.append(b)
    return fr


def fin_gd(R, deg):
    a = math.radians(deg)
    half = 0.785 * 0.92
    fr = []
    for f in range(6):
        b = Buf()
        if f <= 2:
            n = int(R * half * 2)
            for i in range(n):
                if f >= 1 and i % 2:
                    continue
                x, y = _gpt(R - 2, a - half + 2 * half * i / n)
                b.put(x, y, SHADOW)
        if 1 <= f <= 4:
            n = int(R * half * 1.2)
            for i in range(n):
                if hf(i, f, 51) < 0.7 + 0.06 * f:
                    continue
                x, y = _gpt(R + 1 + hf(i, 3, 52) * 3, a - half + 2 * half * i / n)
                b.put(x, y, TIDE[5] if f <= 2 else TIDE[4])
        fr.append(b)
    return fr


def s3_gd(R):
    """S3「判决」贴地：审判光环从 0.25R 推到 R（4 拍），2 格金白边 + 2 格暗金内边（颜色阶代替透明度），到边后断开、变暗、散掉。9 拍"""
    fr = []
    rs = [0.25, 0.55, 0.8, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0]
    for f in range(9):
        b = Buf()
        rr = R * rs[f]
        n = int(rr * 6.6) + 8
        for q in range(n):
            t = q / n * math.tau
            if f >= 4 and hsh(q // 3, f, 61) % (2 if f < 7 else 1 + f - 5) != 0:
                continue
            cols = [LT[6], LT[5], LT[2], LT[1]] if f <= 3 else ([LT[4], LT[3], LT[1]] if f <= 5 else [LT[3], LT[2]])
            jit = 1 if hsh(q // 5, 3, 62) % 3 == 0 else 0   # 边上随机鼓出 1 格（不成规整圆）
            if f <= 3 and hsh(q // 4, f, 63) % 9 == 0:
                continue
            for j, c in enumerate(cols):
                x, y = round((rr + jit - j) * math.cos(t)), round((rr + jit - j) * math.sin(t) * SQ)
                b.put_if_empty(x, y, c)
        if f <= 2:   # 脚下一圈热白（冲击起点）
            for q in range(24):
                t = q / 24 * math.tau
                b.put_if_empty(round(6 * math.cos(t)), round(6 * math.sin(t) * SQ), LT[5])
        fr.append(b)
    return fr


def s3_up(R):
    """S3 立起：光环推过的地方一圈竖起光矛（高低不一 10–26 格、白尖金身、根部一点深蓝水沫），光矛从下往上收掉；
    她头顶提灯处一道细光柱（宽 3，高 46）落下又收起。9 拍"""
    fr = []
    rs = [0.25, 0.55, 0.8, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0]
    k_n = 14 + R // 10
    for f in range(9):
        b = Buf()
        for k in range(k_n):
            if hsh(k, R, 71) % 6 == 0:
                continue
            t = (k + hf(k, R, 72) * 0.6) / k_n * math.tau
            rk = R * (0.86 + 0.14 * hf(k, R, 73))
            born = 0 if rk <= R * rs[0] else next((i for i, r in enumerate(rs) if R * r >= rk), 3)
            age = f - born
            if age < 0 or age > 4:
                continue
            h = 12 + 18 * hf(k, R, 74)
            x0, y0 = round(rk * math.cos(t)), round(rk * math.sin(t) * SQ)
            top = [0.6, 1.0, 1.0, 1.0, 1.0][age]
            bot = [0.0, 0.0, 0.35, 0.65, 0.9][age]
            for y in range(int(h * bot), int(h * top)):
                u = y / h
                c = LT[6] if u > 0.82 and age <= 2 else LT[5] if u > 0.6 else LT[4] if u > 0.3 else LT[3]
                if age >= 3:
                    c = LT[4] if u > 0.8 else LT[2]
                b.put(x0, y0 - y, c)
                if u < 0.9 and age <= 3:   # 光矛 2 格：左亮右暗，矛尖收成 1 格
                    b.put(x0 + 1, y0 - y, LT[3] if age <= 2 else LT[2])
            if age <= 1:
                b.put(x0 - 1, y0, TIDE[5])
                b.put(x0 + 1, y0, TIDE[6] if age == 0 else TIDE[4])
        if f <= 5:   # 提灯光柱（她头顶）
            top = [46, 46, 46, 38, 24, 10][f]
            for y in range(28, 28 + top):
                if f >= 3 and y % 3 == 0:
                    continue
                b.put(0, -y, LT[6] if f <= 2 else LT[5])
                if f <= 3:
                    b.put(-1, -y, LT[4])
                    b.put(1, -y, LT[4] if f <= 2 else LT[3])
        fr.append(b)
    return fr


def boom_up():
    """手炮小爆（原点 = 落点脚下）：一团热白 → 金色火团 + 四散火星 → 暗烟往上团起散掉。7 拍"""
    fr = []
    for f in range(7):
        b = Buf()
        cy = -6
        if f == 0:
            for dx in range(-3, 4):
                for dy in range(-3, 4):
                    if abs(dx) + abs(dy) <= 3:
                        b.put(dx, cy + dy, LT[6] if abs(dx) + abs(dy) <= 1 else LT[5])
        elif f <= 2:
            r = 4 + f
            for dx in range(-r, r + 1):
                for dy in range(-r, r + 1):
                    d = math.hypot(dx, dy * 1.15)
                    if d > r or hsh(dx, dy, 80 + f) % 5 == 0:
                        continue
                    c = LT[6] if d < 1.5 and f == 1 else LT[5] if d < r * 0.45 else LT[4] if d < r * 0.75 else LT[3]
                    b.put(dx, cy + dy - f, c)
            for q in range(6):
                a = q / 6 * math.tau + 0.3
                rr = 6 + 3 * f
                b.put(round(math.cos(a) * rr), round(cy - f + math.sin(a) * rr * 0.8), LT[5] if f == 1 else LT[4])
        if f >= 2:   # 暗烟
            for q in range(5):
                a = q / 5 * math.tau + 0.9
                rr = 2 + (f - 2) * 1.5
                px = round(math.cos(a) * rr)
                py = round(cy - 4 - (f - 2) * 2.5 + math.sin(a) * rr * 0.6)
                s = 2 if f < 5 else 1
                for dx in range(-s, s + 1):
                    for dy in range(-s + 1, s):
                        if hsh(dx + q, dy, 90 + f) % 4 == 0:
                            continue
                        b.put_if_empty(px + dx, py + dy, SMOKE[3] if dy < 0 and f < 5 else SMOKE[2] if f < 6 else SMOKE[1])
        fr.append(b)
    return fr


def boom_gd():
    """小爆贴地：一圈断续的灼痕（cannon_r，压扁；三四段弧、粗细不一，不成整圈）+ 暗灼点，6 拍淡掉"""
    fr = []
    R = BOOM_R
    for f in range(6):
        b = Buf()
        rr = R * [0.4, 0.75, 0.9, 0.95, 0.95, 0.95][f]
        n = int(rr * 6.6)
        for q in range(n):
            t = q / n * math.tau
            seg = (t / math.tau * 4.0 + hf(int(t * 3), 7, 94) * 0.3) % 1.0
            if seg > (0.62 if f <= 1 else 0.45):
                continue
            if f >= 3 and hsh(q // 2, f, 95) % 2:
                continue
            c = LT[5] if f == 0 else LT[3] if f == 1 else LT[1] if f <= 3 else SMOKE[1]
            b.put(round(rr * math.cos(t)), round(rr * math.sin(t) * SQ), c)
        for q in range(7):
            if f < 1:
                break
            a = q * 2.1
            rr2 = 3 + (q * 5) % 9
            b.put_if_empty(round(math.cos(a) * rr2), round(math.sin(a) * rr2 * SQ), SMOKE[1])
        fr.append(b)
    return fr


def muzzle():
    """枪口火光（她手边的手炮）：3 拍，四芒白芯 → 金 → 一点余火"""
    fr = []
    for f in range(3):
        b = Buf()
        if f == 0:
            _star(b, 0, 0, 3, [LT[6], LT[5], LT[4]])
            b.put(1, -1, LT[5])
            b.put(-1, 1, LT[5])
        elif f == 1:
            _star(b, 0, 0, 2, [LT[5], LT[4], LT[3]])
        else:
            b.put(0, 0, LT[3])
            b.put(0, -2, SMOKE[3])
        fr.append(b)
    return fr


def gust_up(tier):
    """S1「起风」：被刺中的第一个敌人脚下卷起一道水旋把它掀起——两股螺旋（深蓝水流 + 金白风线）从地面盘旋往上，
    顶部甩出白沫；精二多一圈往外甩的水珠。原点 = 敌人脚底。9 拍"""
    fr = []
    H = 34
    for f in range(9):
        b = Buf()
        top = min(H, 8 + f * 8) if f <= 4 else H
        bot = 0 if f <= 4 else (f - 4) * 7
        for strand in range(2):
            for y in range(bot, top):
                u = y / H
                rad = 5 + 9 * u
                ang = y * 0.42 + strand * math.pi + f * 0.9
                x = round(math.cos(ang) * rad)
                front = math.sin(ang) > 0
                if strand == 0:
                    c = TIDE[5] if front else TIDE[3]
                    if y >= top - 2 and f <= 5:
                        c = TIDE[6]
                else:
                    if y % 2 and not front:
                        continue
                    if front and y < top - 3:
                        b.put(x, -y - 1, LT[4])
                    c = LT[6] if front and y > top - 5 else LT[5] if front else LT[3]
                (b.put if front else b.put_if_empty)(x, -y, c)
                if strand == 0 and y < top - 2:   # 水流 2 格粗（后半圈暗一阶）
                    b.put_if_empty(x + (1 if math.cos(ang) >= 0 else -1), -y, TIDE[4] if front else TIDE[2])
        if 3 <= f <= 6:   # 顶部碎沫
            for q in range(5):
                a = q / 5 * math.tau + f
                rr = 6 + (f - 3) * 3
                b.put(round(math.cos(a) * rr), round(-H + 2 + math.sin(a) * 2 + (f - 3) * 2), TIDE[6] if f <= 4 else TIDE[4])
        if tier >= 2 and 4 <= f <= 8:   # 精二：往外甩的水珠
            for q in range(8):
                a = q / 8 * math.tau + 0.4
                rr = 8 + (f - 4) * 4
                yy = -H * 0.6 + (f - 4) ** 2 * 1.2
                b.put(round(math.cos(a) * rr), round(yy + math.sin(a) * rr * 0.4), TIDE[5] if f <= 6 else TIDE[4])
        fr.append(b)
    return fr


def gust_gd(tier):
    """起风贴地：脚下一圈压扁的细水纹往外推（精一起才有，S1 的新元素）。7 拍"""
    fr = []
    for f in range(7):
        b = Buf()
        for ring in range(2 if tier >= 1 else 0):
            rr = 6 + f * 3 - ring * 5
            if rr < 3:
                continue
            n = int(rr * 6.6)
            for q in range(n):
                if hsh(q // 2, ring, 101 + f // 2) % 4 == 0:
                    continue
                t = q / n * math.tau
                c = TIDE[6] if f <= 1 else TIDE[5] if f <= 3 else TIDE[4] if f <= 5 else TIDE[3]
                b.put(round(rr * math.cos(t)), round(rr * math.sin(t) * SQ), c)
        fr.append(b)
    return fr


def pick_up():
    """精一「挑刺」：第 2 段首中的那只身下一道往上挑的金色细弧（竖直，从下往上扫），带两粒水珠。原点 = 敌人脚底。5 拍"""
    fr = []
    for f in range(5):
        b = Buf()
        lo, hi = [(0, 0.6), (0, 1.0), (0.3, 1.0), (0.6, 1.0), (0.85, 1.0)][f]
        n = 22
        for i in range(n + 1):
            v = i / n
            if v < lo or v > hi:
                continue
            a = -math.pi * 0.15 + math.pi * 0.7 * v
            x = round(-7 * math.cos(a) + 3)
            y = round(-2 - 18 * v)
            c = LT[6] if f <= 1 and v > 0.5 else LT[5] if f <= 2 else LT[3]
            b.put(x, y, c)
            if v > 0.3 and f <= 2:
                b.put(x + 1, y, LT[4])
        if 1 <= f <= 3:
            b.put(5, -18 + f * 2, TIDE[5])
            b.put(-2, -14 + f * 2, TIDE[4])
        fr.append(b)
    return fr


def gale_gd(R):
    """「卷风」/ 响应「起风」贴地：一圈三道螺旋水纹往里卷（压扁），断口多，7 拍从外往里收"""
    fr = []
    for f in range(7):
        b = Buf()
        for arm in range(3):
            for i in range(60):
                u = i / 60
                rr = R * (1.0 - 0.75 * u) * (1.0 - 0.06 * f)
                if rr < 3:
                    continue
                t = arm * math.tau / 3 + u * 2.6 + f * 0.35
                if hsh(i // 3, arm, 111 + f) % 4 == 0:
                    continue
                if u > 0.25 + 0.12 * f and f < 5:
                    pass
                c = TIDE[5] if u < 0.35 else TIDE[4] if u < 0.7 else LT[4]
                if f >= 5:
                    c = TIDE[3]
                b.put(round(rr * math.cos(t)), round(rr * math.sin(t) * SQ), c)
        fr.append(b)
    return fr


def gale_up(R):
    """卷风立起：环上几道往上飘的细风线（金白短竖线，越飘越短）。7 拍"""
    fr = []
    k_n = 8 + R // 8
    for f in range(7):
        b = Buf()
        for k in range(k_n):
            t = (k + hf(k, R, 121) * 0.5) / k_n * math.tau
            rr = R * (0.55 + 0.4 * hf(k, R, 122))
            x0, y0 = round(rr * math.cos(t)), round(rr * math.sin(t) * SQ)
            lift = f * 3 + 2
            ln = max(0, 6 - f)
            for y in range(ln):
                b.put(x0, y0 - lift - y, LT[5] if y == ln - 1 and f <= 2 else TIDE[5] if y < ln // 2 else LT[4])
        fr.append(b)
    return fr


def nova_up(R):
    """「卷风·追斩」：以她为心向四周 10 道短光刺（腰高、地面平面里放射，压扁），一拍刺出一拍收。5 拍"""
    fr = []
    for f in range(5):
        b = Buf()
        for k in range(10):
            t = k / 10 * math.tau + 0.2
            r0 = R * [0.2, 0.35, 0.6, 0.8, 0.9][f]
            r1 = R * [0.6, 1.0, 1.0, 1.0, 1.0][f]
            n = int(r1 - r0)
            for i in range(n):
                u = i / max(1, n)
                x, y = _gpt(r0 + i, t, WAIST)
                c = LT[6] if u > 0.8 and f <= 1 else LT[5] if u > 0.4 else LT[3]
                if f >= 3:
                    c = LT[3] if u > 0.6 else LT[2]
                    if i % 2:
                        continue
                b.put(x, y, c)
        fr.append(b)
    return fr


def tide3_up(R):
    """「裂潮·三度」：以她为心一整圈潮水被劈开——环上一圈水花炸起（高低错落、断口多），碎成白沫落下。8 拍"""
    fr = []
    ks = 26
    for f in range(8):
        b = Buf()
        for k in range(ks):
            if hsh(k, R, 131) % 4 == 0:
                continue
            t = (k + hf(k, R, 132) * 0.6) / ks * math.tau
            rr = R * (0.88 + 0.12 * hf(k, R, 133))
            x0, y0 = _gpt(rr, t)
            fk = f - int(hf(k, R, 134) * 2)
            _spray(b, x0, y0, math.cos(t), math.sin(t), 8 + 8 * hf(k, R, 135), fk, hsh(k, R, 136), 0.9)
        fr.append(b)
    return fr


def tide3_gd(R):
    """裂潮·三度贴地：环外漫开的碎白沫 + 一道压扁细水纹（只画边，不铺满）"""
    fr = []
    for f in range(8):
        b = Buf()
        n = int(R * 6.6)
        spread = 2 + f * 1.5
        thr = 0.6 + 0.05 * f
        for q in range(n):
            t = q / n * math.tau
            for j in range(int(spread)):
                if hf(q, j, 141 + f // 2) < thr:
                    continue
                x, y = _gpt(R + j, t)
                b.put(x, y, TIDE[6] if f <= 2 else TIDE[5] if f <= 5 else TIDE[4])
            if (q // 4 + f) % 3:
                x, y = _gpt(R - 3, t)
                b.put_if_empty(x, y, TIDE[3])
        fr.append(b)
    return fr


def brand_up():
    """「严律」停顿印记（状态件，循环）：被停住那只头顶一颗金白四芒刺印，每 2 拍明暗一次"""
    fr = []
    for f in range(4):
        b = Buf()
        hot = f < 2
        _star(b, 0, 0, 3 if hot else 2, [LT[6] if hot else LT[5], LT[5] if hot else LT[4], LT[3]])
        for dx, dy in ((2, 2), (-2, 2), (2, -2), (-2, -2)):
            b.put(dx, dy, LT[3])
        fr.append(b)
    return fr
