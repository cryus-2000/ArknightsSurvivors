"""拉普兰德转平面（docs/273）的像素图形：纯 Python，tools/pxplane_bake_lappland.py 用它烤帧条（game/art/fx/pxp/pxp_lp_*.png + game/data/pxp_lappland.json），
tools/pxplane_gif_lappland.py 用它拼送审 GIF。运行时件（剑气细针、狼首弹的拖尾 / 晶片、命中斩痕、封招符印、观察刻痕、连携斩痕）在游戏里由
fx_pxplane_lp.gd 逐格画，算法与本文件 needle() / cut_px() / chain_px() / tally_px() 一一对应，改一边要改另一边。
单位：美术像素（游戏里 1 美术像素 = g.PX = 2 世界像素）。全部确定性（抖动用坐标哈希）。

配色（原作 whitew_* 参照：贴图全是冷灰白，普攻是两段细月牙刀光，S2 是黑白狼首弹 + 菱形晶片 + 烟；Claude outputs/pixelfx_ul_lappland/original_moves.md）：
- LP：冷紫灰 → 白 7 阶（剑光；任务单「紫白剑光」）；
- WOLF：黑紫 → 灰白（S2 狼魂：狼首、烟、晶片）。
- 封招：精英 / Boss 头顶一圈断开的紫色锁链环（11-05 用户认不出原来的「方块加线」符印）；剑气 = 贴地低飞的紫白月牙。不用红（红只给危险）。"""
import math

LP = ["#15121f", "#2b2542", "#4a4274", "#7b70b4", "#b3aae4", "#e4e0ff", "#ffffff"]
WOLF = ["#0a090f", "#1b1828", "#2e2a40", "#4d4862", "#8a8698", "#cfcdd8", "#ffffff"]
SHADOW = "#100e16"
QV = ["#ffffff", "#d6ccff", "#9a86ea", "#5c4ca8"]   # 剑气 / 锁链：更紫的一组（刃线白 → 紫）
SQ = 0.72   # 贴地压扁（combat.GROUND_Y）
WAIST = 5   # 腰高（美术像素；判定原点 脚底 + (0, −10) 世界像素）

# 尺寸档（美术像素 = 判定半径 ÷ 2）：范围成长放大时游戏挑最近的一档（只整数放大，不做小数缩放）
ATK_R = [44, 50, 58, 68]      # 普攻双刃（reach 100 × op_range；回敬 130 落在 58 / 68）
DANCE_R = [60, 70, 84]        # 精一狼之舞（dance_r 120）
BARK_R = [75, 90]             # 断喝（bark_r 150）
S3_R = 96                     # 噤声起手环（s3_ring 200 内）
DIRS = [-90, -45, 0, 45, 90]


def hx(s):
    s = s.lstrip("#")
    return (int(s[0:2], 16), int(s[2:4], 16), int(s[4:6], 16), 255)


def hsh(x, y, k=0):
    return ((int(x) * 73856093) ^ (int(y) * 19349663) ^ (int(k) * 83492791)) & 0xFFFF


def hf(x, y, k=0):
    return hsh(x, y, k) / 65535.0


class Buf:
    """一帧：{(x, y): '#rrggbb'}，原点 = 脚底"""
    def __init__(self):
        self.p = {}

    def put(self, x, y, c):
        self.p[(int(round(x)), int(round(y)))] = c

    def put_if_empty(self, x, y, c):
        self.p.setdefault((int(round(x)), int(round(y))), c)

    def line(self, x0, y0, x1, y1, c, keep=False):
        n = max(1, int(math.ceil(max(abs(x1 - x0), abs(y1 - y0)))))
        for i in range(n + 1):
            u = i / n
            (self.put_if_empty if keep else self.put)(x0 + (x1 - x0) * u, y0 + (y1 - y0) * u, c)


def _ang_d(a, b):
    return (a - b + math.pi) % math.tau - math.pi


# ================================================================ 月牙（腰高水平刀痕：地面平面上的弧，压扁后抬到腰高）

def crescent(b, R, d, span, thick, prog, fade, cols, lift=WAIST, ccw=True, r_in=0.0, seed=0, edge=True):
    """R 外半径；d 朝向（弧度，平面角）；span 半张角；thick 最厚处（像素，按地面半径量）；
    prog 0–1 刀尖扫到哪（从刀尾往前）；fade 0–1 整道变薄变暗；cols = [刃线, 亮, 中, 暗]；
    厚度：中段厚、两头针尖，最厚处偏刀头（ccw = 逆时针扫）"""
    if prog <= 0.0:
        return
    th_k = 1.0 - 0.75 * fade
    Rb = int(R) + 3
    for y in range(int(-Rb * SQ - lift - 2), int(Rb * SQ - lift + 3)):
        for x in range(-Rb - 1, Rb + 2):
            gx, gy = x, (y + lift) / SQ
            r = math.hypot(gx, gy)
            if r > R + 0.5 or r < R - thick - 1:
                continue
            a = math.atan2(gy, gx)
            da = _ang_d(a, d)
            if abs(da) > span:
                continue
            u = (da + span) / (2 * span)   # 0 刀尾 → 1 刀头
            if not ccw:
                u = 1.0 - u
            if u > prog:
                continue
            w = math.sin(math.pi * min(1.0, u * 1.05)) ** 0.8 * (0.55 + 0.45 * u)
            th = max(0.6, thick * w * th_k)
            dr = R - r
            if dr > th:
                continue
            if fade > 0.0 and hf(x, y, seed) < fade * 0.55 * (dr / max(1.0, th) + 0.3):
                continue   # 收刀：整道一起变稀，不留细尾
            if edge and dr < 1.0 and (prog < 1.0 or fade < 0.5):
                c = cols[0] if fade < 0.35 else cols[1]
            elif dr < th * 0.45:
                c = cols[1] if fade < 0.5 else cols[2]
            else:
                c = cols[2] if fade < 0.4 else cols[3]
            if r_in > 0.0 and r < r_in:
                continue
            b.put(x, y, c)


def atk_frames(R, d_deg, t, heavy=False, mirror=False):
    """普攻「双刃」：两道细月牙交错（外刀白刃 + 内刀晚一拍、暗一阶），5 拍收完。
    heavy = 回敬（更厚更亮）；mirror = 双刃连斩的补刀（反向扫、略小）"""
    d = math.radians(d_deg)
    span = 1.2
    out = []
    th = (4.5 if not heavy else 6.5) + 0.8 * t
    hot = [LP[6], LP[5], LP[4], LP[3]]
    sub = [LP[5], LP[4], LP[3], LP[2]]
    plan = [(0.6, 0.0, 0.0, 0.0), (1.0, 0.0, 0.55, 0.0), (1.0, 0.35, 1.0, 0.2), (1.0, 0.7, 1.0, 0.6), (1.0, 0.92, 1.0, 0.9)]
    Rm = R * (0.92 if mirror else 1.0)
    for i, (p1, f1, p2, f2) in enumerate(plan):
        b = Buf()
        ccw = not mirror
        crescent(b, Rm * 0.74, d + (0.12 if ccw else -0.12), span * 0.9, th * 0.75, p2, f2, sub, ccw=ccw, seed=i + 7)   # 内刀（晚一拍）
        crescent(b, Rm, d, span, th, p1, f1, hot, ccw=ccw, seed=i)
        if i == 0:   # 出手第一帧刀头刃光：刀尖外一道径向短亮线
            a = d + span * (0.2 if ccw else -0.2)
            for s in range(3):
                rr = Rm + 1 + s
                b.put(rr * math.cos(a), rr * math.sin(a) * SQ - WAIST, LP[6] if s < 2 else LP[4])
        out.append(b)
    return out


def atk_gd(R, d_deg):
    """刀痕投影：地上一道淡暗弧（3 拍）"""
    d = math.radians(d_deg)
    out = []
    for i in range(4):
        b = Buf()
        crescent(b, R * 0.95, d, 1.15, 2.0, 1.0, 0.3 * i, [SHADOW, SHADOW, SHADOW, SHADOW], lift=0, seed=31 + i, edge=False)
        out.append(b)
    return out


# ================================================================ 精一「狼之舞」旋身斩：两道刀光首尾相追转一整圈 + 地上爪痕

def dance_frames(R):
    out = []
    hot = [LP[6], LP[5], LP[4], LP[3]]
    sub = [LP[5], LP[4], LP[3], LP[2]]
    for i in range(6):
        b = Buf()
        rot = i * 1.15
        fade = 0.0 if i < 2 else (i - 1) / 5.0
        for k, cols in ((0, hot), (1, sub)):
            d = rot + k * math.pi
            crescent(b, R * (1.0 if k == 0 else 0.9), d, 1.35, 6.5 if k == 0 else 4.5, 1.0, fade, cols, ccw=True, seed=i * 3 + k)
        out.append(b)
    return out


def dance_gd(R):
    """地上 5 组三道爪痕，从脚下往外划开（狼）；8 拍：划开 → 暗 → 断开褪掉"""
    out = []
    for i in range(8):
        b = Buf()
        prog = min(1.0, (i + 1) / 2.0)
        for k in range(5):
            a = k * math.tau / 5 + 0.3
            for j in (-1, 0, 1):
                a2 = a + j * 0.09
                r0, r1 = R * 0.35, R * (0.35 + 0.6 * prog)
                n = int(r1 - r0)
                for s in range(n):
                    r = r0 + s
                    if i >= 4 and hf(k * 7 + j, s, i) < (i - 3) * 0.22:
                        continue
                    c = LP[5] if i == 0 else (LP[3] if i < 3 else LP[2] if i < 6 else LP[1])
                    if s > n - 3 and i < 2:
                        c = LP[6]
                    b.put(r * math.cos(a2), r * math.sin(a2) * SQ, c)
        out.append(b)
    return out


# ================================================================ 命中斩痕 / 封招符印 / 观察刻痕（运行时逐格画；这里给 GIF 用的同算法版）

def cut_px(f, L, d, x=False):
    """斩痕第 f 拍（0–2）：沿 d（单位向量）一道 1 像素白芯斜线，两侧浅紫，两头收尖。返回 [(dx, dy, 颜色, 发光)]"""
    out = []
    dirs = [d]
    if x:
        c, s = math.cos(1.25), math.sin(1.25)
        dirs.append((d[0] * c - d[1] * s, d[0] * s + d[1] * c))
    core = LP[6] if f == 0 else LP[5]
    side = LP[4] if f == 0 else LP[3]
    Lf = L * [1.0, 0.8, 0.5][f]
    m = int(Lf)
    for dv in dirs:
        nv = (-dv[1], dv[0])
        for i in range(-m, m + 1):
            if f == 2 and abs(i) < m - 2:
                continue
            w = 1.0 - abs(i) / (m + 1)
            px = (round(dv[0] * i), round(dv[1] * i))
            out.append((px[0], px[1], core if w > 0.25 else side, f == 0 and w > 0.4 and i % 2 == 0))
            if f == 0 and w > 0.55:
                out.append((round(px[0] + nv[0]), round(px[1] + nv[1]), side, False))
    return out


# 封招符印（7×7）：菱形符框 + 中心点；斩线从左上到右下，两半错开一格（被斩断）
_SIG = sorted({(round(4 * math.cos(k * math.tau / 24)), round(4 * math.sin(k * math.tau / 24))) for k in range(24)})   # 符印圆环（十字斩第 0 拍 / 传染碎片）
CHAIN_R = 6        # 封招锁链环半径（美术像素）
CHAIN_GAP = -0.8   # 断口方向（右上）


def chain_px(age_tk, total_s, left_s):
    """封招锁链环（只画精英 / Boss）：头顶一圈紫色锁链环，右上一道断口；断口两端出现时闪白，之后每秒闪一下；
    封印期间断口慢慢张大、两半往外错开、整圈渐淡，最后 0.3 秒褪掉。返回 [(dx, dy, 颜色, 不透明度, 发光)]，原点 = 环心"""
    out = []
    crack = max(0.0, min(1.0, 1.0 - left_s / max(0.1, total_s)))
    al = max(0.0, min(1.0, left_s / 0.3)) * (1.0 - 0.45 * crack)
    gap = 0.22 + 0.75 * crack                    # 断口半张角（弧度）
    drift = round(1.6 * crack)                   # 两半往外错开
    flash = age_tk < 3 or (age_tk % 15) < 1
    n = 48
    gx, gy = math.cos(CHAIN_GAP), math.sin(CHAIN_GAP)
    seen = set()
    for k in range(n):
        a = k * math.tau / n
        da = _ang_d(a, CHAIN_GAP)
        if abs(da) < gap:
            continue
        side = 1 if da > 0 else -1
        ox, oy = -gy * side * drift, gx * side * drift   # 垂直断口方向错开
        for rr, kind in ((CHAIN_R + 1.6, "o"), (CHAIN_R - 1.6, "o"), (CHAIN_R + 0.5, "c"), (CHAIN_R - 0.5, "c")):
            x, y = round(rr * math.cos(a) + ox), round(rr * math.sin(a) + oy)
            if (x, y, kind) in seen:
                continue
            seen.add((x, y, kind))
            if kind == "o":
                out.append((x, y, SHADOW, 0.75 * al, False))
            else:
                end = abs(da) < gap + 0.45
                link = (k // 3) % 2 == 0
                if end and flash:
                    out.append((x, y, LP[6], al, True))
                else:
                    out.append((x, y, (LP[5] if rr > CHAIN_R else LP[4]) if link else QV[2], al, False))
    # 去掉被链身盖住的暗边（暗边只留在外侧 / 内侧）
    body = {(x, y) for (x, y, c, a2, gl) in out if c != SHADOW}
    return [q for q in out if not (q[2] == SHADOW and (q[0], q[1]) in body)]


def tally_px(n, fresh):
    """S3 观察刻痕：头顶 n 道斜竖短刻（3 道 = 叠满）；fresh = 新叠的那道白热。原点 = 中间那道的底"""
    out = []
    for k in range(n):
        x0 = (k - (n - 1) / 2.0) * 3
        hot = fresh and k == n - 1
        for s in range(5):
            out.append((round(x0 + s * 0.4), -s, LP[6] if hot else (LP[5] if s >= 1 else LP[4]), hot))
        out.append((round(x0) + 1, 0, SHADOW, False))
    return out


def needle(L, w, tier, big=False):
    """剑气细针（沿方向逐格）：[(s 往后, n 法向, 颜色, 发光)]。头 2 格白热，后面渐暗收尖；big = 反斩大剑气（两道平行 + 宽芯）"""
    out = []
    for s in range(L):
        u = s / L
        c = LP[6] if s < 2 else (LP[5] if u < 0.35 else (LP[4] if u < 0.65 else LP[3]))
        out.append((s, 0, c, s < 2))
        if u < 0.45 and s >= 1:
            out.append((s, 1, LP[4] if u < 0.25 else LP[3], False))
            if w >= 2:
                out.append((s, -1, LP[3], False))
    if big:
        for side in (-3, 3):
            for s in range(1, int(L * 0.7)):
                out.append((s, side, LP[5] if s < 3 else LP[3], s < 2))
    return out


# ================================================================ S1 日晷：脚下刻度盘（断续细环 + 12 刻度）；精一加一根转一圈的晷针；精二加上飘三角光点

def s1_gd(t):
    out = []
    R = 26
    for i in range(12):
        b = Buf()
        k = min(1.0, (i + 1) / 3.0)
        al_fade = max(0.0, (i - 7) / 4.0)
        for q in range(int(R * 6.6)):
            a = q / (R * 6.6) * math.tau
            if (q // 4) % 3 == 2:
                continue   # 断续
            if a > k * math.tau + 0.01:
                continue
            if al_fade > 0 and hf(q, i, 3) < al_fade:
                continue
            b.put(R * math.cos(a), R * math.sin(a) * SQ, LP[4] if i < 6 else LP[3])
        for m in range(12):   # 刻度
            a = m * math.tau / 12
            if a > k * math.tau or (al_fade > 0 and hf(m, i, 5) < al_fade):
                continue
            L = 4 if m % 3 == 0 else 2
            for s in range(L):
                rr = R - 1 - s
                b.put(rr * math.cos(a), rr * math.sin(a) * SQ, LP[6] if (m % 3 == 0 and i < 4) else LP[5])
        if t >= 1 and 1 <= i <= 9:   # 晷针：从脚下指向刻度，转一圈
            a = -math.pi / 2 + (i - 1) / 8.0 * math.tau
            for s in range(2, R - 3):
                b.put(s * math.cos(a), s * math.sin(a) * SQ, LP[6] if s > R - 8 else LP[5])
            b.put((R + 1) * math.cos(a), (R + 1) * math.sin(a) * SQ, LP[6])
        out.append(b)
    return out


def s1_up():
    """精二：8 枚小三角光点从刻度盘上飘（10 拍）"""
    out = []
    for i in range(10):
        b = Buf()
        for k in range(8):
            a = k * math.tau / 8 + 0.2
            x = 24 * math.cos(a)
            y = 24 * math.sin(a) * SQ - (i * 2.2 + (k % 3) * 2)
            if i > 6 and hf(k, i) < (i - 6) / 4.0:
                continue
            c = LP[6] if i < 4 else LP[5]
            b.put(x, y, c)
            b.put(x - 1, y + 1, LP[4])
            b.put(x + 1, y + 1, LP[4])
        out.append(b)
    return out


def block_up():
    """日晷格挡：队长身前两刃交叉成 X 一闪 + 一圈细火花（5 拍）"""
    out = []
    for i in range(5):
        b = Buf()
        L = [7, 9, 9, 7, 4][i]
        for sgn in (-1, 1):
            for s in range(-L, L + 1):
                c = LP[6] if (i < 2 and abs(s) < L - 1) else (LP[5] if i < 3 else LP[3])
                b.put(s, -16 + sgn * s * 0.9, c)
        if i < 3:
            r = 4 + 4 * i
            for q in range(8):
                a = q * math.tau / 8 + 0.2
                b.put(r * math.cos(a), -16 + r * math.sin(a), LP[6] if i == 0 else LP[4])
        out.append(b)
    return out


# ================================================================ S2 狼魂：起手双刃左右展开 + 脚下黑烟环；狼首弹（张口双耳，黑白）

def s2_up():
    out = []
    for i in range(8):
        b = Buf()
        k = min(1.0, (i + 1) / 2.5)
        fade = max(0.0, (i - 4) / 4.0)
        for sgn in (-1, 1):
            a = -math.pi / 2 + sgn * (0.35 + 0.55 * k)   # 两刃从背后往两侧张开
            L = int(32 * (0.6 + 0.4 * k))
            for s in range(4, L):
                if fade > 0 and hf(s, sgn, i) < fade:
                    continue
                x, y = s * math.cos(a) + sgn * 3, -14 + s * math.sin(a) * 0.9
                c = LP[6] if s > L - 4 and i < 4 else (LP[5] if s > L * 0.5 else LP[4])
                b.put(x, y, c)
                b.put(x + sgn, y, LP[4] if s > L * 0.4 else LP[3])
                if s < L * 0.6:
                    b.put(x - sgn, y + 1, WOLF[2])
        out.append(b)
    return out


def s2_gd():
    """脚下黑烟环：不规则烟团往外摊开，越来越稀（10 拍）"""
    out = []
    for i in range(10):
        b = Buf()
        r = 10 + 2.6 * i
        for q in range(48):
            a = q * math.tau / 48
            if hf(q, 0, 11) < 0.25 + 0.07 * i:
                continue
            rr = r + (hf(q, 1, 12) - 0.5) * 6
            sz = 2 if hf(q, 2, 13) < 0.5 else 1
            for dx in range(sz):
                for dy in range(sz):
                    b.put(rr * math.cos(a) + dx, rr * math.sin(a) * SQ + dy, WOLF[3] if i < 3 else WOLF[2])
            if i < 3 and q % 6 == 0:
                b.put(rr * math.cos(a), rr * math.sin(a) * SQ - 1, WOLF[4])
        out.append(b)
    return out


def s2_aura():
    """狼魂持续：脚边几缕黑烟往上飘（8 拍循环，淡）"""
    out = []
    for i in range(8):
        b = Buf()
        for k in range(4):
            x0 = [-9, -3, 4, 10][k]
            ph = (i + k * 2) % 8
            for s in range(3):
                y = -ph * 2 - s
                if ph > 5 and s == 0:
                    continue
                b.put(x0 + round(math.sin((ph + s) * 0.9 + k) * 1.2), y, WOLF[2] if ph < 4 else WOLF[1])
        out.append(b)
    return out


# 狼首（朝右的局部坐标，x 往前、y 往下）：张口、两耳、白眼；低多边形
_K = 1.0
_HEAD = [(10, -2), (4, -4), (1, -6), (-2, -7), (-6, -6), (-9, -3), (-13, -2), (-10, 0), (-13, 3), (-8, 4), (-3, 5), (1, 4), (4, 2), (9, 3), (10, 2)]
_JAW_GAP = [(12, -1.2), (2, 0.9), (12, 2.8)]
_JAW_SHUT = [(11, 0.4), (4, 0.9), (11, 1.3)]
_EARS = [[(-3, -6), (-1, -11), (1, -5.5)], [(-7, -5), (-8, -10), (-4, -6.5)]]


def _in_poly(x, y, poly):
    n = len(poly)
    c = False
    for i in range(n):
        x1, y1 = poly[i]
        x2, y2 = poly[(i + 1) % n]
        if (y1 > y) != (y2 > y) and x < (x2 - x1) * (y - y1) / (y2 - y1) + x1:
            c = not c
    return c


def wolf_frames(d_deg, tier):
    """狼首弹：两拍循环（嘴开 / 合），朝 d_deg（画面角，−90 上 … 90 下）；精二眼睛白热、耳尖亮"""
    a = math.radians(d_deg)
    ca, sa = math.cos(a), math.sin(a)
    out = []
    for i in range(2):
        b = Buf()
        gap = _JAW_GAP if i == 0 else _JAW_SHUT
        for y in range(-16, 17):
            for x in range(-16, 17):
                lx = x * ca + y * sa          # 转回局部坐标（纵向 ÷1.3：头更高）
                ly = (-x * sa + y * ca) / 1.3
                inside = _in_poly(lx, ly, _HEAD) or any(_in_poly(lx, ly, e) for e in _EARS)
                if not inside or _in_poly(lx, ly, gap):
                    continue
                ins = lambda px_, py_: _in_poly(px_, py_, _HEAD) or any(_in_poly(px_, py_, e) for e in _EARS)
                edge = not (ins(lx + 0.9, ly) and ins(lx - 0.9, ly) and ins(lx, ly + 0.9) and ins(lx, ly - 0.9))
                if edge:
                    c = WOLF[6] if (ly < -1 or (tier >= 2 and ly < -6 * _K)) else WOLF[4]
                elif ly < -3.5 * _K:   # 耳内
                    c = WOLF[2]
                elif ly < 0:
                    c = WOLF[5] if lx > 2 * _K else WOLF[4]
                else:
                    c = WOLF[3] if lx > 0 else WOLF[2]
                b.put(x, y - 8, c)   # 弹体在腰高（剑气 off −16 世界像素 = 8 美术像素）
        ex, ey = 1, -3   # 眼
        for (qx, qy) in ((0, 0), (1, 0)):
            ey2 = ey * 1.3
            b.put(ex * ca - ey2 * sa + qx * ca, ex * sa + ey2 * ca - 8 + qx * sa, LP[6] if tier >= 2 else LP[5])
        out.append(b)
    return out


# ================================================================ S3 噤声：起手 X 刃一闪 + 脚下刻痕环；叠满十字斩

def s3_up():
    out = []
    for i in range(6):
        b = Buf()
        L = [10, 16, 18, 16, 12, 8][i]
        for sgn in (-1, 1):
            for s in range(-L, L + 1):
                if i >= 3 and hf(s, sgn, i) < (i - 2) * 0.25:
                    continue
                c = LP[6] if i < 2 or abs(s) < 3 else (LP[5] if i < 4 else LP[3])
                b.put(s, -20 + sgn * s * 0.8, c)
                if i < 3 and abs(s) < L - 2:
                    b.put(s, -20 + sgn * s * 0.8 + 1, LP[4])
        out.append(b)
    return out


def s3_gd():
    """起手：一圈短刻痕从脚下推到 S3_R（观察范围边），断续、越推越稀（10 拍）"""
    out = []
    for i in range(10):
        b = Buf()
        r = S3_R * (1.0 - (1.0 - min(1.0, (i + 1) / 6.0)) ** 2)
        n = int(r * 1.2)
        for q in range(max(8, n)):
            a = q / max(8, n) * math.tau
            if q % 3 == 2 or (i >= 6 and hf(q, i) < (i - 5) * 0.22):
                continue
            for s in range(3):   # 一道径向短刻
                rr = r - s
                b.put(rr * math.cos(a), rr * math.sin(a) * SQ, LP[5] if (s == 0 and i < 5) else LP[3])
        out.append(b)
    return out


def xcut_frames():
    """十字斩（叠满观察）：两道长白斩交叉 + 第 0 拍白热定格 + 碎符片落下（7 拍），原点 = 敌人脚底，斩心在腰高"""
    out = []
    cy = -9
    for i in range(7):
        b = Buf()
        L = [6, 15, 15, 13, 10, 6, 0][i]
        for sgn in (-1, 1):
            for s in range(-L, L + 1):
                if i >= 4 and hf(s, sgn, i) < (i - 3) * 0.3:
                    continue
                c = LP[6] if i < 3 or abs(s) < 2 else (LP[5] if i < 5 else LP[3])
                b.put(s, cy + sgn * s * 0.85, c)
                if i < 3 and 1 < abs(s) < L - 1:
                    b.put(s, cy + sgn * s * 0.85 - 1, LP[4])
                    b.put(s, cy + sgn * s * 0.85 + 1, LP[4])
        if i == 0:
            for (x, y) in _SIG:
                b.put(x, cy + y, LP[6])
        if i >= 2:   # 符片：8 片菱形碎片往外崩、落下
            u = (i - 1) / 5.0
            for k in range(8):
                a = k * math.tau / 8 + 0.4
                x = math.cos(a) * (4 + 14 * u)
                y = cy + math.sin(a) * (3 + 8 * u) + 18 * u * u
                if y > 0:
                    continue
                c = LP[5] if i < 4 else LP[3]
                b.put(x, y, c)
                b.put(x + 1, y, LP[3])
        out.append(b)
    return out


# ================================================================ 断喝：狼嚎声波（锯齿断续环，往外推；地面）

def bark_gd(R):
    out = []
    for i in range(8):
        b = Buf()
        for ring in range(2):
            u = min(1.0, (i + 1 - ring * 1.5) / 4.0)
            if u <= 0:
                continue
            r = R * (1.0 - (1.0 - u) ** 2)
            n = int(r * 3.5)
            for q in range(n):
                a = q / n * math.tau
                if (q // 5) % 4 == 3 or (i >= 5 and hf(q, ring, i) < (i - 4) * 0.25):
                    continue
                zig = 2.0 if (q % 6) < 3 else -1.0   # 锯齿
                rr = r + zig * (q % 3) / 2.0
                c = (LP[6] if ring == 0 else LP[5]) if i < 3 else (LP[4] if i < 5 else LP[2])
                b.put(rr * math.cos(a), rr * math.sin(a) * SQ, c)
        out.append(b)
    return out


def spread_up():
    """断喝·传染：死亡处一枚封印符炸开成碎片（6 拍，原点 = 脚底）"""
    out = []
    for i in range(6):
        b = Buf()
        u = i / 5.0
        for k, (x, y) in enumerate(_SIG):
            a = math.atan2(y, x)
            r = 3 + 12 * u
            px = x * 1.5 + math.cos(a) * r * 0.6
            py = -10 + y * 1.5 + math.sin(a) * r * 0.5 + 10 * u * u
            if i >= 3 and hf(k, i) < (i - 2) * 0.3:
                continue
            b.put(px, py, LP[6] if i < 2 else (LP[4] if i < 4 else LP[3]))
        out.append(b)
    return out


def arm_gd():
    """日晷·反斩待命：脚下一枚小刻度盘一闪（6 拍）"""
    out = []
    for i in range(6):
        b = Buf()
        R = 10 + i
        for m in range(12):
            a = m * math.tau / 12
            if i >= 4 and m % 2:
                continue
            for s in range(2):
                b.put((R - s) * math.cos(a), (R - s) * math.sin(a) * SQ, LP[6] if i < 2 else LP[4])
        out.append(b)
    return out


# ================================================================ 连携「月牙剑气」：大月牙（凸面朝前，横跨约 150 世界像素 = 判定宽 140）

def qi_frame(d_deg, R, span, thick, lift=3):
    """剑气月牙（凸面朝前，贴地低飞：抬 lift 美术像素）；R = 月牙所在圆半径，原点 = 月牙中点。两拍：亮 / 刃线略收"""
    d = math.radians(d_deg)
    out = []
    for i in range(2):
        b = Buf()
        tmp = Buf()
        crescent(tmp, R, d, span, thick * (1.0 if i == 0 else 0.85), 1.0, 0.0, QV, lift=0, ccw=True, seed=97 + i)
        cx, cy = -R * math.cos(d) * 0.94, -R * math.sin(d) * 0.94 * SQ
        for (x, y), c in tmp.p.items():
            b.put(x + cx, y + cy - lift, c)
        out.append(b)
    return out


def qi_shadow(d_deg, R, span, thick):
    """剑气贴地影子（地面层）"""
    d = math.radians(d_deg)
    b = Buf()
    tmp = Buf()
    crescent(tmp, R, d, span * 0.9, max(1.5, thick * 0.6), 1.0, 0.0, [SHADOW] * 4, lift=0, ccw=True, seed=5, edge=False)
    cx, cy = -R * math.cos(d) * 0.94, -R * math.sin(d) * 0.94 * SQ
    for (x, y), c in tmp.p.items():
        b.put(x + cx, y + cy, c)
    return [b]


# 剑气尺寸档：键 → (圆半径, 半张角, 最厚)；far = 领主远掷 / 追猎 / 狼魂期间远掷，twin = 双生刃，big = 日晷·反斩大剑气，qi = 后期额外剑气
QI_SIZES = {"far": (16, 0.9, 3.5), "twin": (13, 0.85, 3.0), "big": (26, 0.9, 5.5), "qi": (12, 0.85, 2.6)}


def link_frame(d_deg):
    d = math.radians(d_deg)
    b = Buf()
    # 凸面朝前：圆心在后方 R 处，画朝 d 的一段弧
    R = 60
    cx, cy = -R * math.cos(d) * 0.9, -R * math.sin(d) * 0.9 * SQ
    tmp = Buf()
    crescent(tmp, R, d, 0.68, 7.0, 1.0, 0.0, [LP[6], LP[5], LP[4], LP[3]], lift=0, ccw=True, seed=91)
    for (x, y), c in tmp.p.items():
        b.put(x + cx, y + cy - 8, c)
    return [b]
