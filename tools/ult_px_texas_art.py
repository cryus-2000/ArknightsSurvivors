"""德克萨斯终结技 Q 转平面画面（docs/257 §8，开关 ult/px_plane）的像素图形（Python 版，送审 GIF 用；接进游戏时 game/scripts/run/ult_px_tx.gd 逐函数对应）。
招式时间轴、判定、伤害一律照 ult_moves._tx_*：0–0.5 秒刀网一道道显现、她沿每道斩线闪身划过 → 0.6 秒落到圆心 → 0.75 秒斩线齐出（冲击帧）→ 收刀冲回原位。
单位：美术像素（1 美术像素 = 2 世界像素）；坐标相对给定原点；全部确定性（坐标哈希，不用随机数）。
配色同她的普攻 / 技能（docs/257 §1）：源石剑琥珀 8 阶 TX + 精二冷青刃光 ACC；尘 / 焦痕暗土。
返回 [(x, y, 颜色, 发光 / 不透明度[, 边长])]：第 4 项是 bool = 发光（进光学发光层），是 float = 不透明度。"""
import math

TX = ["#120804", "#2c1406", "#5a2808", "#9c4610", "#e2781c", "#ffac3c", "#ffdc9c", "#ffffff"]
ACC = "#9fe3ff"
DU = ["#18140f", "#2c261d", "#463d2f", "#6a5e4a"]
SQ = 0.72


def hsh(x, y, k=0):
    return ((int(x) * 73856093) ^ (int(y) * 19349663) ^ (int(k) * 83492791)) & 0xFFFF


def hf(x, y, k=0):
    return hsh(x, y, k) / 65535.0


def _line_cells(b):
    """原点 → b（美术像素）沿线的格子：[(x, y, u 0..1)]"""
    L = math.hypot(b[0], b[1])
    n = max(2, int(L))
    return [(b[0] * i / n, b[1] * i / n, i / n) for i in range(n + 1)], (b[0] / max(L, 1), b[1] / max(L, 1))


# ================================================================ 起手蓄力（共用演出的转平面版；原点 = 她的脚底）
def windup(wk, bt):
    """14 粒琥珀光点螺旋收向剑柄，越近越亮；脚下压扁细光圈收紧"""
    out = []
    for i in range(14):
        a = math.tau * i / 14 + wk * 2.4
        r = 46 * (1 - wk) ** 1.3 + 3
        x, y = math.cos(a) * r + 6, math.sin(a) * r * SQ - 16
        out.append((x, y, TX[6] if wk > 0.6 else TX[5], wk > 0.6))
    rr = 34 * (1 - 0.6 * wk)
    for q in range(int(rr * 6)):
        if (q + bt) % 4 == 0:
            continue
        t = q / int(rr * 6) * math.tau
        out.append((math.cos(t) * rr, math.sin(t) * rr * SQ, TX[4], 0.8))
    return out


# ================================================================ 刀网发丝线（斩开前的预兆：一道琥珀细线，逐拍轻闪）
def hairline(b, age, life):
    out = []
    if age < 0 or age > life:
        return out
    cells, _ = _line_cells(b)
    fr = int(age * 15)
    for x, y, u in cells:
        if hf(int(x), int(y), fr) < 0.18:
            continue
        out.append((x, y, TX[5] if age < 2 / 15 else TX[4], 0.85))
    return out


# ================================================================ 闪身身影线（沿斩线划过；同普攻冲刺的直线刀光，芯 2 格）
def dashline(b, f):
    out = []
    if f < 0 or f > 3:
        return out
    cells, (dx, dy) = _line_cells(b)
    nx, ny = -dy, dx
    for i, (x, y, u) in enumerate(cells):
        prof = math.sin(math.pi * min(1.0, max(0.0, u * 0.94 + 0.03))) ** 0.5
        if f >= 2 and hf(i, f, 7) < (0.45 if f == 2 else 0.75):
            continue
        core = TX[7] if f == 0 else (TX[6] if f == 1 else TX[5])
        side = TX[5] if f == 0 else (TX[4] if f == 1 else TX[3])
        w = 2 if prof > 0.55 else 1
        for k in range(w):
            out.append((x + nx * k, y + ny * k, core, f == 0 and (i % 2 == 0)))
        if prof > 0.3:
            out.append((x - nx, y - ny, side, 1.0))
            out.append((x + nx * w, y + ny * w, side, 1.0))
    return out


# ================================================================ 主斩线（0.75 秒齐出；白芯 + 琥珀辉光边，两头收尖；停 0.2 秒后从两头往中间收、0.7 秒淡掉）
HOLD = 0.2
FADE = 0.7


def cut_blade(b, age, sil=False):
    out = []
    if age < 0 or age > HOLD + FADE:
        return out
    cells, (dx, dy) = _line_cells(b)
    nx, ny = -dy, dx
    hot = age < 2 / 15
    k = 0.0 if age < HOLD else (age - HOLD) / FADE        # 0 → 1 收掉
    for i, (x, y, u) in enumerate(cells):
        prof = math.sin(math.pi * u) ** 0.6
        if k > 0 and abs(u - 0.5) * 2 > 1 - k:             # 从两头往中间收
            continue
        hw = max(0.5, 3.0 * prof * (1 - 0.75 * k))
        j = -hw
        while j <= hw:
            q = abs(j) / hw
            if sil:
                out.append((x + nx * j, y + ny * j, "#000000", True))
            else:
                if q < 0.34:
                    c = TX[7] if (hot or k < 0.15) else TX[6]
                elif q < 0.7:
                    c = TX[6] if hot else TX[5]
                else:
                    c = TX[5] if hot else TX[4]
                if k > 0.5:
                    c = TX[5] if q < 0.34 else TX[4]
                out.append((x + nx * j, y + ny * j, c, q < 0.34 and (hot or i % 2 == 0)))
            j += 0.5
        if not sil and age < HOLD and prof > 0.6 and i % 9 == 4:   # 刃上冷青刃光点（精二点缀，同普攻）
            out.append((x - nx * (hw + 1), y - ny * (hw + 1), ACC, True))
    return out


def ground_scar(b, age):
    """贴地焦痕（代替原帧条 fx_ult_texas_scar_back）：刀痕正下方一道暗琥珀 → 焦黑，1.8 秒内一节节断开"""
    out = []
    if age < 0 or age > 1.8:
        return out
    cells, (dx, dy) = _line_cells(b)
    brk = max(0.0, (age - 0.5) / 1.3)
    for i, (x, y, u) in enumerate(cells):
        if u < 0.04 or u > 0.96 or hf(i, 3, 11) < brk:
            continue
        c = TX[4] if age < 0.12 else TX[3] if age < 0.35 else TX[2] if age < 0.8 else DU[1]
        out.append((x, y + 3, c, 0.9))
    return out


# ================================================================ 粒子云（路上的爆 = 闪烁粒子云，不用烟；同艾丽妮 cloud，换琥珀色）
def cloud(age, sd, size, n=-1):
    out = []
    if age < 0 or age > 1.2:
        return out
    if n < 0:
        n = min(60, int(30 + size * 0.6))
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
        c = TX[7] if hc < 0.3 else TX[6] if hc < 0.62 else TX[5] if hc < 0.9 else ACC
        if age > 0.6:
            c = TX[6] if c == TX[7] else TX[5] if c == TX[6] else TX[4] if c == TX[5] else c
        out.append((x, y, c, c == TX[7] and age < 0.3, 2 if k % 3 == 0 else 1))
    return out


# ================================================================ 最大那一下（斩开后的大爆）：2 拍预备 → 亮核 2 拍 + 满亮灯 → 厚冲击环 3.5 拍推到判定边缘 → 粒子云往外喷
BLAST_T = 2 / 15
SHOCK_T = 3.5 / 15


def shock_at(R, d):
    k = min(1.0, max(0.0, (d / R - 0.5) / 0.5))
    return BLAST_T + (1 - math.sqrt(1 - k)) * SHOCK_T


def blast_prep(R, fa):
    """预备：24 粒光点从 0.55–0.85 R 沿斩线方向往中心收（游戏里另画一层 0.3 的压暗椭圆）"""
    out = []
    if fa >= BLAST_T:
        return out
    k = fa / BLAST_T
    for i in range(24):
        a = math.tau * (i + hf(i, 9, 61)) / 24 + k * 0.9
        r = R * (0.55 + 0.3 * hf(i, 9, 62)) * (1 - k) ** 1.4 + 2
        x, y = math.cos(a) * r, math.sin(a) * r * SQ - 10
        out.append((x, y, TX[7] if k > 0.5 else TX[6], k > 0.5))
        out.append((x - math.cos(a) * 3, y - math.sin(a) * 3 * SQ, TX[5], False))
    return out


def blast_core(R, bf):
    """亮核 2 拍：只留中心小一圈（0.12 R）的十字星芒 + 实心芯，不平涂大椭圆；体量靠冲击环和粒子云"""
    out = []
    if bf < 0 or bf > 1:
        return out
    rx = R * (0.07 if bf == 0 else 0.05)   # 只留中心一小团实心芯（不做大椭圆）；体量靠星芒、冲击环、粒子云
    j = -rx
    while j <= rx:
        i = -rx * SQ
        while i <= rx * SQ:
            d = math.hypot(j / rx, i / (rx * SQ))
            if d <= 1.0:
                c = TX[7] if d < 0.55 else TX[6] if d < 0.85 else TX[5]
                if bf == 1:
                    c = TX[6] if d < 0.55 else TX[5]
                out.append((j, i - 12, c, d < 0.4))
            i += 1
        j += 1
    arm = int(R * (0.42 if bf == 0 else 0.3))          # 四道星芒（刀光的形）：横长竖短，两头收尖
    for s in range(-arm, arm + 1):
        w = 1.0 - abs(s) / arm
        c = TX[7] if w > 0.6 else TX[6] if w > 0.3 else TX[5]
        out.append((s, -12, c, w > 0.5))
        if abs(s) < arm * 0.45:
            out.append((0, s * SQ - 12, c, w > 0.5))
    return out


def shock_ring(R, tau):
    """压扁的厚冲击环：0.5 R → R（先快后慢），厚 8 格（白 → 琥珀），环后地面一闪；到边后 2 拍淡掉"""
    out = []
    if tau < 0 or tau > SHOCK_T + 2 / 15:
        return out
    us = min(1.0, tau / SHOCK_T)
    rr = R * (0.5 + 0.5 * (1 - (1 - us) ** 2))
    fade = 1.0 if tau < SHOCK_T else max(0.0, 1 - (tau - SHOCK_T) / (2 / 15))
    cols = [TX[7], TX[7], TX[7], TX[6], TX[6], TX[5], TX[5], TX[4]] if tau < SHOCK_T else [TX[6], TX[6], TX[5], TX[5], TX[4], TX[4], TX[3], TX[3]]
    n = int(rr * 6.6) + 16
    for q in range(n):
        t = q / n * math.tau
        cx, cy = math.cos(t), math.sin(t) * SQ
        if hf(q, 5, 33) < 0.06:                       # 偶有缺口，不是死板整圈
            continue
        for j in range(8):
            out.append((round(cx * (rr - j)), round(cy * (rr - j)), cols[j], fade))
        if tau < SHOCK_T:
            for j2 in range(9, 20, 2):
                if (q + j2) % 3 == 0:
                    continue
                out.append((round(cx * (rr - j2)), round(cy * (rr - j2)), TX[4], 0.4 * (1 - j2 / 20)))
    return out


# ================================================================ 怪物崩解喷散（怪物代表色像素；游戏里另叠引擎原有的 kill_burst 按贴图像素碎开）
SPRAY_N = 22


def spray(age, sd, out_ang, k, col):
    res = []
    if age < 0 or age > 1.3:
        return res
    def lt(c, a):
        return tuple(min(1.0, x + (1 - x) * a) for x in c)
    def dk(c, a):
        return tuple(x * (1 - a) for x in c)
    cols = [lt(col, 0.45), lt(col, 0.15), col, dk(col, 0.3)]
    for q in range(int(SPRAY_N * min(1.4, k))):
        ang = out_ang + (hf(q, sd, 71) - 0.5) * 2.6
        spd = (15 + 125 * hf(q, sd, 72) ** 1.5) * k   # 速度拉开（不排成一道弧）
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
