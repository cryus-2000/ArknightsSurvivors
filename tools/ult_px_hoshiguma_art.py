"""星熊终结技「般若反震」转平面画面（docs/254 §8，开关 ult/px_plane）的像素图形（Python 版，送审 GIF 用；点头后逐函数移植成 game/scripts/run/ult_px_ho.gd）。
单位：美术像素（1 美术像素 = 2 世界像素）；坐标相对给定原点（星熊脚底）；全部确定性（坐标哈希，不用随机数）。
配色同她的普攻 / 技能（docs/254 §1）：PRTS 发色青绿 8 阶（JD）为主，盾钢灰（ST），蓄势升温用暖金（AM，原画面是红，按「红只给危险」换成暖金），碎石尘土暗土（DU）。
返回 [(x, y, 颜色, 发光 / 不透明度[, 边长])]：第 4 项 bool = 发光（进光学发光层），float = 不透明度。
招式时间轴照 ult_moves_c._ho_start / _ho_step（玩法不动）：0 秒盾砸地 + 吸怪；0–1.5 秒挡住（每 0.3 秒一圈裂纹）；1.5 秒反震炸开（判定半径 R = 502 世界 = 251 美术）。"""
import math

JD = ["#050f0c", "#0b1e19", "#123a31", "#1d5e50", "#2f8a76", "#58c4ab", "#b4f0e2", "#ffffff"]
ST = ["#141519", "#262a31", "#3f4652", "#646d7c", "#98a2b2", "#d6dce6"]
AM = ["#2a1a08", "#5a3610", "#94601a", "#d2922a", "#f2bf4c", "#fbe3a6"]
DU = ["#1a1712", "#2e2920", "#4a4234", "#6e6450", "#968a70"]
SQ = 0.72
HOLD = 1.5
TICK = 0.3
SH = (14, 0)          # 盾「般若」立在她身前（右）的脚点


def hsh(x, y, k=0):
    """整数混合哈希（相邻输入也不出规律，粒子云不排成同心圈）；GDScript 版照同一组常数"""
    h = (int(x) * 374761393 + int(y) * 668265263 + int(k) * 2246822519) & 0xFFFFFFFF
    h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
    return (h ^ (h >> 16)) & 0xFFFF


def hf(x, y, k=0):
    return hsh(x, y, k) / 65535.0


def heat(t):
    """蓄势热度 0 → 1（挡的 1.5 秒里青绿往暖金走）"""
    return max(0.0, min(1.0, t / HOLD))


# ================================================================ 盾阵六边形（贴地，压扁）：r 半径，w 线宽，rot 旋转；返回边上的点
def hex_pts(r, rot=0.0, w=2, col=None, a=1.0, gap_seed=None):
    out = []
    vs = [(math.cos(rot + k * math.pi / 3), math.sin(rot + k * math.pi / 3)) for k in range(6)]
    n = max(6, int(r * 1.2))
    for k in range(6):
        x0, y0 = vs[k]
        x1, y1 = vs[(k + 1) % 6]
        for i in range(n):
            u = i / n
            if gap_seed is not None and hf(k * 97 + i, gap_seed, 3) < 0.12:
                continue
            x, y = (x0 + (x1 - x0) * u), (y0 + (y1 - y0) * u)
            for j in range(w):
                rr = r - j
                c = col[j] if isinstance(col, list) else col
                out.append((round(x * rr), round(y * rr * SQ), c, a))
    return out


# ================================================================ 蓄力（起手慢放；原点 = 脚底）：青绿光点往盾心收，脚下六边形细线收紧
def windup(wk, bt):
    out = []
    for i in range(18):
        a = math.tau * (i + hf(i, 3, 1)) / 18 + wk * 2.0
        r = (60 + 30 * hf(i, 3, 2)) * (1 - wk) ** 1.3 + 3
        x, y = SH[0] + math.cos(a) * r, -20 + math.sin(a) * r * SQ
        out.append((x, y, JD[7] if wk > 0.6 and i % 3 == 0 else JD[6], wk > 0.6))
        out.append((x - math.cos(a) * 2, y - math.sin(a) * 2 * SQ, JD[4], 0.8))
    out += hex_pts(70 - 30 * wk, 0.2, 1, JD[5], 0.5 + 0.5 * wk)
    return out


# ================================================================ 盾（立起，挡的期间）：盾形外缘一圈光，越挡越亮、青绿往暖金走；原点 = 脚底
def shield_rim(t, hot_frac=None):
    out = []
    k = heat(t) if hot_frac is None else hot_frac
    HW, HH = 10, 26
    for zi in range(0, HH * 2 + 1):
        z = zi / 2
        u = z / HH
        half = HW * (1 - 0.35 * (1 - u) ** 2) if u > 0.25 else HW * (0.55 + 1.8 * u)
        for s in (-1, 1):
            x = SH[0] + s * half
            c = AM[4] if k > 0.6 else JD[6] if k < 0.3 else AM[5]
            out.append((round(x), round(-z - 2), c, k > 0.3))
    for x in range(-HW + 2, HW - 1):
        out.append((SH[0] + x, -HH - 2, JD[7] if k < 0.5 else AM[5], True))
    if k > 0.4:   # 盾面上的裂纹（挡得越久越多）
        for i in range(int(2 + 6 * k)):
            a = hf(i, 5, 1) * math.pi
            for s in range(int(3 + 6 * hf(i, 5, 2))):
                out.append((SH[0] + round(math.cos(a) * s), round(-14 - math.sin(a) * s * 0.8), AM[4] if k > 0.7 else JD[6], True))
    return out


# ================================================================ 地面裂网（盾下往外跑，挡的每一跳长一截；反震时撑到 0.8 R）
def crack_paths(stage_len, seed, n=9):
    paths = []
    for j in range(n):
        a = math.tau * (j + (hf(j, seed, 1) - 0.5) * 0.7) / n
        x, y = SH[0] + math.cos(a) * 8, math.sin(a) * 8
        L = stage_len * (0.6 + 0.5 * hf(j, seed, 2))
        pts = [(x, y, 0.0)]
        s = 0.0
        while s < L:
            a += (hf(int(s * 3), j * 31 + seed, 3) - 0.5) * (0.35 if stage_len < 100 else 0.7)   # 反震的大裂缝更不规整
            x += math.cos(a)
            y += math.sin(a)
            s += 1
            pts.append((x, y, s / max(1.0, stage_len)))
        paths.append(pts)
        if hf(j, seed, 4) > 0.45:
            k = int(len(pts) * (0.35 + 0.3 * hf(j, seed, 5)))
            bx, by, f0 = pts[k]
            ba = a + (0.8 if hf(j, seed, 6) > 0.5 else -0.8)
            bp = [(bx, by, f0)]
            for s2 in range(int(L * 0.4)):
                ba += (hf(s2, j * 13 + seed, 7) - 0.5) * 0.35
                bx += math.cos(ba)
                by += math.sin(ba)
                bp.append((bx, by, f0 + s2 / max(1.0, stage_len)))
            paths.append(bp)
    return paths


def cracks(t, boom_t=None):
    """t = 招式时间。挡的期间：第 i 跳（0.3 秒一跳）长到 22 + 14 i，芯色青绿 → 暖金；反震后：长到 0.8 R、白热 → 暖金 → 冷成暗土，2 秒淡掉"""
    out = []
    if t < 0:
        return out
    if boom_t is None or t < boom_t:
        stage = min(5, int(t / TICK))
        L = 22 + 14 * stage
        grow = min(1.0, (t - stage * TICK) / 0.08) if stage < 5 else 1.0
        k = heat(t)
        core = JD[6] if k < 0.35 else AM[4] if k < 0.75 else AM[5]
        cur = (22 * grow) if stage == 0 else (22 + 14 * (stage - 1) + 14 * grow)   # 这一跳从上一跳的长度长到这一跳
        for p in crack_paths(L, 5):
            for (x, y, f) in p:
                if f * L > cur:
                    break
                out.append((round(x), round(y * SQ), core, k > 0.35))
                out.append((round(x), round(y * SQ) + 1, DU[0], 0.85))
        return out
    age = t - boom_t
    if age > 2.0:
        return out
    R = 251.0
    L = R * 0.8
    grow = min(1.0, age / 0.12)
    for p in crack_paths(L, 5, 11):
        for (x, y, f) in p:
            if f > grow * 1.05:
                break
            if age > 0.7 and hf(int(x), int(y), 9) < (age - 0.7) / 1.3:
                continue
            c = "#ffffff" if age < 0.07 else AM[5] if age < 0.25 else AM[3] if age < 0.6 else DU[2]
            out.append((round(x), round(y * SQ), c, age < 0.4))
            if f < 0.5:
                out.append((round(x), round(y * SQ) + 1, DU[0], 0.85))
    return out


# ================================================================ 挡的每一跳：盾前一小团粒子云（青绿 + 暖金），六边形闪一下
def tick_cloud(age, seed, k):
    out = []
    if age < 0 or age > 0.5:
        return out
    u = min(1.0, age / 0.2)
    for q in range(26):
        if hf(q, seed, 4) < age / 0.5:
            continue
        a = math.tau * hf(q, seed, 1)
        r = 22 * math.sqrt(hf(q, seed, 2)) * (1 - (1 - u) ** 2)
        x, y = SH[0] + math.cos(a) * r, -16 + math.sin(a) * r * SQ - age * 14
        hc = hf(q, seed, 3)
        c = JD[7] if hc < 0.3 else (AM[4] if hc < 0.3 + 0.5 * k else JD[6])
        out.append((x, y, c, age < 0.2 and hc < 0.3, 2 if q % 3 == 0 else 1))
    return out


# ================================================================ 反震（最大那一下）：预备 2 拍 → 亮核 2 拍 → 六边形冲击环 3.5 拍推到 R → 粒子云往外喷 + 盾甲碎片
PREP_T = 2 / 15
SHOCK_T = 3.5 / 15


def shock_at(R, d):
    """冲击环推到距中心 d 的时刻（相对反震，秒）：怪物崩解按它往外起"""
    k = min(1.0, max(0.0, (d / R - 0.5) / 0.5))
    return (1 - math.sqrt(1 - k)) * SHOCK_T


def prep(age_before):
    """反震前最后 2 拍：光点从外往盾心吸（游戏里另画一层 0.28 压暗椭圆）；age_before = 距反震还剩几秒"""
    out = []
    if age_before > PREP_T or age_before < 0:
        return out
    k = 1 - age_before / PREP_T
    for i in range(24):
        a = math.tau * (i + hf(i, 11, 1)) / 24 + k * 1.2
        r = (120 + 60 * hf(i, 11, 2)) * (1 - k) ** 1.4 + 3
        x, y = SH[0] + math.cos(a) * r, -16 + math.sin(a) * r * SQ
        out.append((x, y, AM[5] if k > 0.5 else JD[6], k > 0.5))
        out.append((x - math.cos(a) * 3, y - math.sin(a) * 3 * SQ, JD[4], 0.7))
    return out


def core(bf):
    """亮核 2 拍（只留中心小一圈，不平涂大圆）：[(rx, 颜色)] 由外到内；中心在盾心"""
    if bf < 0 or bf > 1:
        return []
    rx = 18 if bf == 0 else 12   # 只留盾心小一团（不平涂大圆）；体量靠六边形冲击环 + 粒子云
    return [(rx, JD[5] if bf == 0 else JD[4]), (rx * 0.7, AM[4] if bf == 0 else JD[6]), (rx * 0.42, "#ffffff" if bf == 0 else AM[5])]


def shock_hex(R, tau):
    """冲击环 = 盾阵六边形（星熊的识别）：厚 8 格（白 → 青绿 → 暖金外沿），0.5 R → R 先快后慢；环后 6–16 格地面一闪；到边后 2 拍淡掉"""
    out = []
    if tau < 0 or tau > SHOCK_T + 2 / 15:
        return out
    us = min(1.0, tau / SHOCK_T)
    rr = R * (0.5 + 0.5 * (1 - (1 - us) ** 2)) * 1.08   # 六边形边心距比外接圆小，乘一点让边推到判定边
    fade = 1.0 if tau < SHOCK_T else max(0.0, 1 - (tau - SHOCK_T) / (2 / 15))
    cols = ["#ffffff", "#ffffff", JD[7], JD[7], JD[6], JD[6], JD[6], JD[5], JD[5], AM[4], AM[4], AM[3]] if tau < SHOCK_T else [JD[6], JD[6], JD[5], JD[5], JD[5], JD[4], JD[4], AM[3], AM[3], AM[3], AM[2], AM[2]]
    out += hex_pts(rr, 0.0, 12, cols, fade, gap_seed=None)   # 厚 12 格（原版是一整圈厚石尘环，这里靠厚度撑体量）
    tau2 = tau - 1 / 15   # 内圈第二层盾阵：错开 30°、晚一拍、暖金，推到 0.82 R（同原版两层六边形）
    if 0 <= tau2 <= SHOCK_T + 2 / 15:
        u2 = min(1.0, tau2 / SHOCK_T)
        r2 = R * (0.4 + 0.42 * (1 - (1 - u2) ** 2)) * 1.08
        f2 = 1.0 if tau2 < SHOCK_T else max(0.0, 1 - (tau2 - SHOCK_T) / (2 / 15))
        out += hex_pts(r2, math.pi / 6, 6, [AM[5], AM[4], AM[4], AM[3], AM[3], AM[2]], f2)
    if tau < SHOCK_T:   # 环后地面一闪（稀疏）
        for p in hex_pts(rr - 9, 0.0, 1, JD[4], 1.0):
            if (p[0] + p[1]) % 3 == 0:
                continue
            out.append((p[0], p[1], JD[4], 0.4))
        for p in hex_pts(rr - 14, 0.0, 1, JD[3], 1.0):
            if (p[0] * 3 + p[1]) % 4 != 0:
                continue
            out.append((p[0], p[1], JD[3], 0.3))
    return out


def cloud(age, sd, size, n):
    """粒子云（闪烁小亮点，按面积铺满往外炸开、逐拍闪、漂上去、越剩越少；不用烟团）：青绿 / 白 / 暖金"""
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
        c = "#ffffff" if hc < 0.25 else JD[6] if hc < 0.65 else AM[4] if hc < 0.85 else JD[5]
        if age > 0.6:
            c = JD[6] if c == "#ffffff" else JD[5] if c == JD[6] else AM[3] if c == AM[4] else c
        out.append((x, y, c, c == "#ffffff" and age < 0.3, 2 if k % 3 == 0 else 1))
    return out


def shards(age):
    """盾甲碎片：18 片钢灰实心块（2–3 格，亮顶边），从盾心往外甩、受重力落地、停一下熄灭（docs/270 爆发档一簇 ≤ 25）"""
    out = []
    if age < 0 or age > 1.1:
        return out
    G = 300.0
    for q in range(18):
        a = math.tau * (q + hf(q, 21, 1) * 0.6) / 18
        spd = 90 + 90 * hf(q, 21, 2)
        vh = 50 + 70 * hf(q, 21, 3)
        tl = 2 * vh / G
        t = min(age, tl)
        h = max(0.0, vh * t - 0.5 * G * t * t)
        x, y = SH[0] + math.cos(a) * spd * t, math.sin(a) * spd * t * SQ - 14 - h + 14 * min(1.0, t / tl)
        sz = 3 if q % 3 == 0 else 2
        al = 1.0 if age < 0.8 else max(0.0, (1.1 - age) / 0.3)
        c = "#ffffff" if age < 0.07 else ST[4]
        for dx in range(sz):
            for dy in range(sz):
                out.append((round(x) + dx, round(y) + dy, (ST[5] if dy == 0 else c if dy == 0 else ST[3]) if age >= 0.07 else c, al))
    return out


def spray(age, sd, out_ang, k, col):
    """怪物崩解：怪物代表色像素往外喷（亮 / 本色 / 暗 + 头两拍白芯），有重量、落地、停一下熄灭；同艾丽妮 docs/275 §1.0。col = (r, g, b) 0–1；返回 [(x, y, (r,g,b,a), 发光, 边长)]"""
    res = []
    if age < 0 or age > 1.3:
        return res
    def lt(c, a):
        return tuple(min(1.0, x + (1 - x) * a) for x in c)
    def dk(c, a):
        return tuple(x * (1 - a) for x in c)
    cols = [lt(col, 0.45), lt(col, 0.15), col, dk(col, 0.3)]
    for q in range(int(22 * min(1.4, k))):
        ang = out_ang + (hf(q, sd, 71) - 0.5) * 2.0
        spd = (40 + 80 * hf(q, sd, 72)) * k
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


def pull_streak(dx, dy, age, col):
    """吸怪：被拉过来的怪身后一道残影（本色 → 青绿，0.25 秒）。dx, dy = 拉动的位移（美术像素，从旧位置指向新位置）"""
    out = []
    if age < 0 or age > 0.25:
        return out
    L = math.hypot(dx, dy) or 1.0
    n = int(L)
    for i in range(0, n, 2):
        u = i / n
        if u < age / 0.25:
            continue
        c = JD[6] if u > 0.7 else JD[4]
        out.append((round(-dx * (1 - u)), round(-dy * (1 - u)) - 8, c, 0.4 + 0.6 * u))
    return out
