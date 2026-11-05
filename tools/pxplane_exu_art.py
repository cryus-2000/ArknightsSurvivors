"""能天使转平面（docs/262）的像素图形：枪口焰 / 命中火花 / 贴地环 / 光环帧条，以及运行时弹体、曳光线的同一套画法（Python 版）。
tools/pxplane_bake_exusiai.py 用它烤帧条（game/art/fx/pxp/pxp_ex_*.png + game/data/pxp_exusiai.json），
tools/pxplane_gif_exusiai.py 用它拼审阅 GIF；弹体 / 曳光线在游戏里由 fx_pxplane_exu.gd 逐格画，算法与本文件 bullet() / tracer_line() 一一对应，改一边要改另一边。
单位：美术像素（游戏里 1 美术像素 = g.PX = 2 世界像素）。全部确定性（不用随机数，抖动用坐标哈希）。"""
import math

# 色阶（暗 → 亮，7 阶，最后一阶白）。模式色沿用 docs/25 §6.1：速射朱橙（原作白色尖梭曳光 + 她的暖色；纯红留给危险提示）、S1 冰青、S2 琥珀橙、S3 过热白（橙红边）、倾泻金
RAMP = {
    "n": ["#2a100c", "#5c2418", "#a8402a", "#f07048", "#ffa880", "#ffe0cc", "#ffffff"],
    "s1": ["#08202a", "#0f4458", "#1b7f9e", "#38c0e0", "#8fe6f5", "#d6f8ff", "#ffffff"],
    "s2": ["#2a1406", "#5c2c0a", "#a8520f", "#f08a1e", "#ffbd5a", "#ffe6b0", "#ffffff"],
    "s3": ["#3a140a", "#7a2814", "#d05030", "#ff8050", "#ffb890", "#fff0e0", "#ffffff"],
    "g": ["#2a1c06", "#5c3e0a", "#a8741a", "#e8b030", "#ffd86a", "#fff2c0", "#ffffff"],
    # 精一穿甲连射层数（白 → 浅金 → 金），只给弹体
    "t1": ["#2a1c10", "#5c3a20", "#a86a40", "#e8a070", "#ffd0a8", "#fff0e0", "#ffffff"],
    "t2": ["#2a1c06", "#5c3e0a", "#a8741a", "#f0c050", "#ffe08a", "#fff6d8", "#ffffff"],
    "t3": ["#2a1c06", "#5c3e0a", "#a8741a", "#e8b030", "#ffd86a", "#fff2c0", "#ffffff"],
}
GOLD = RAMP["g"]
SMOKE = ["#2c2830", "#4a4450", "#6e6874", "#958e9a"]
SQ = 0.72   # 贴地压扁（combat.GROUND_Y）


def hx(s):
    s = s.lstrip("#")
    return (int(s[0:2], 16), int(s[2:4], 16), int(s[4:6], 16), 255)


def hsh(x, y, k=0):
    return ((x * 73856093) ^ (y * 19349663) ^ (k * 83492791)) & 0xFFFF


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


# ---------------------------------------------------------------- 尺寸表（模式 → 三档）
MZ_L = {"n": [7, 8, 9], "s1": [9, 10, 11], "s2": [7, 8, 9], "s3": [9, 10, 11], "g": [8, 9, 10]}
HIT_R = {"n": [6, 7, 8], "s1": [8, 9, 10], "s2": [6, 7, 7], "s3": [8, 9, 10], "g": [8, 9, 10], "x": [4, 4, 4], "full": [10, 10, 10]}


def _rot(d, a):
    c, s = math.cos(a), math.sin(a)
    return (d[0] * c - d[1] * s, d[0] * s + d[1] * c)


def muzzle(mode, tier, deg):
    """枪口焰（立起层，原点 = 枪口）：3 帧。第 0 拍白芯 + 火舌 + 两侧短喷口；第 1 拍火舌缩短变暗 + 两点烟；第 2 拍烟上飘。
    精一：火舌前多一道细芒；精二：火舌根部两侧各一颗金星。倾泻 g = 五道扇形火舌；S3 = 十字星芒"""
    C = RAMP[mode]
    a = math.radians(deg)
    d = (math.cos(a), math.sin(a))
    nv = (-d[1], d[0])
    L = MZ_L[mode][tier]
    fr = [Buf(), Buf(), Buf()]
    b = fr[0]
    # 火舌
    rays = [0.0] if mode != "g" else [-0.44, -0.22, 0.0, 0.22, 0.44]
    for ra in rays:
        dd = _rot(d, ra)
        nn = (-dd[1], dd[0])
        LL = L if ra == 0.0 else L - 1
        s = 0.0
        while s <= LL:
            u = s / LL
            w = (1.0 - u) * (1.6 if mode != "g" else 0.6) + (0.4 if s < 2 else 0.0)
            col = C[5] if u < 0.35 else (C[4] if u < 0.7 else C[3])
            m = int(round(w))
            for q in range(-m, m + 1):
                if abs(q) == m and m > 0 and hsh(int(s * 2), q, 7) % 3 == 0:
                    continue   # 边缘参差
                b.put(dd[0] * s + nn[0] * q, dd[1] * s + nn[1] * q, col)
            s += 0.5
    if tier >= 1 and mode != "g":   # 精一：前方细芒
        for s in range(L + 1, L + 3):
            b.put(d[0] * s, d[1] * s, C[5] if s == L + 1 else C[4])
    js = 2 if tier == 0 else 3
    for sd in (-1, 1):   # 两侧短喷口（±60°）
        jd = _rot(d, sd * 1.05)
        for s in range(1, js + 1):
            b.put(jd[0] * (s + 0.5), jd[1] * (s + 0.5), C[4] if s == 1 else C[3])
    if mode == "s3":   # 过载：垂直方向十字星芒
        for sd in (-1, 1):
            for s in range(2, 6):
                b.put(nv[0] * s * sd + d[0], nv[1] * s * sd + d[1], C[5] if s < 4 else C[4])
    for x in (-1, 0, 1):   # 白芯
        for y in (-1, 0, 1):
            if abs(x) + abs(y) <= 1:
                b.put(d[0] * 1 + x, d[1] * 1 + y, C[6])
    # 第 1 拍：缩短、暗一阶、无白芯
    b1 = fr[1]
    for ra in rays:
        dd = _rot(d, ra)
        for s in range(1, int(L * 0.6) + 1):
            b1.put(dd[0] * s, dd[1] * s, C[4] if s < L * 0.3 else C[3])
    b1.put(d[0] * (L * 0.6 + 1), d[1] * (L * 0.6 + 1) - 1, SMOKE[2])
    b1.put(d[0] * (L * 0.4), d[1] * (L * 0.4) - 2, SMOKE[1])
    # 第 2 拍：烟上飘 + 一点余烬
    b2 = fr[2]
    b2.put(d[0] * (L * 0.6 + 1), d[1] * (L * 0.6 + 1) - 3, SMOKE[1])
    b2.put(d[0] * (L * 0.4) + 1, d[1] * (L * 0.4) - 4, SMOKE[0])
    b2.put(d[0] * 2, d[1] * 2, C[2])
    if tier >= 2:   # 精二：火舌根部两颗金星（天使的金色）
        for sd in (-1, 1):
            fr[0].put(nv[0] * 3 * sd + d[0] * 2, nv[1] * 3 * sd + d[1] * 2, GOLD[6])
            fr[0].put(nv[0] * 4 * sd + d[0] * 2, nv[1] * 4 * sd + d[1] * 2, GOLD[5])
            fr[1].put(nv[0] * 4 * sd + d[0] * 3, nv[1] * 4 * sd + d[1] * 3, GOLD[4])
    return fr


def hit(mode, tier):
    """命中火花（立起层，原点 = 命中点，不分方向）：4 帧。第 0 拍白芯 + 放射短芒（E0 4 道 / E1 6 / E2 8）；第 1 拍芒外移断开；
    第 2 拍尖端几点下坠；第 3 拍两点余烬。精二速射质变：金色细十字星（天使的星芒）；S3 加一圈过载环；full = 精一叠满金色 X"""
    C = RAMP["g" if mode == "full" else ("n" if mode == "x" else mode)]
    R = HIT_R[mode][tier]
    nr = 4 if mode == "x" else [4, 6, 8][tier]
    fr = [Buf() for _ in range(4)]
    off = math.pi / 4 if nr == 4 else 0.0
    for i in range(nr):
        a = off + i / nr * math.tau + (0.12 if i % 2 else 0.0)
        d = (math.cos(a), math.sin(a))
        rl = R * (1.0 if i % 2 == 0 else 0.75)
        for s in range(2, int(rl * 0.8) + 1):
            fr[0].put(d[0] * s, d[1] * s, C[5] if s < 4 else C[4])
        for s in range(int(rl * 0.55), int(rl) + 1):
            fr[1].put(d[0] * s, d[1] * s, C[4] if s < rl * 0.8 else C[3])
        fr[2].put(d[0] * (rl + 1), d[1] * (rl + 1) + 1, C[3])
        if i % 3 == 0:
            fr[3].put(d[0] * (rl + 1), d[1] * (rl + 1) + 3, C[2])
    for x in range(-2, 3):
        for y in range(-2, 3):
            if abs(x) + abs(y) <= 2:
                fr[0].put(x, y, C[6] if abs(x) + abs(y) <= 1 else C[5])
    for (x, y) in ((0, 0), (1, 0), (0, 1), (-1, 0), (0, -1)):
        fr[1].put(x, y, C[4] if (x, y) == (0, 0) else C[3])
    if mode == "s3":
        for i in range(24):
            t = i / 24 * math.tau
            fr[1].put_if_empty(math.cos(t) * (R - 1), math.sin(t) * (R - 1), C[3])
    if mode == "full":
        for s in range(-R, R + 1):
            for w in (0, 1):
                fr[0].put(s, s + w, GOLD[6] if abs(s) < 3 else GOLD[5])
                fr[0].put(s, -s + w, GOLD[6] if abs(s) < 3 else GOLD[5])
                if abs(s) > 2:
                    fr[1].put(s, s, GOLD[4])
                    fr[1].put(s, -s, GOLD[4])
    if tier >= 2 and mode in ("n", "s1", "s2", "s3", "g"):   # 精二：金色细十字星
        for s in range(1, R + 3):
            col = GOLD[6] if s < 3 else GOLD[5]
            for (dx, dy) in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                fr[0].put_if_empty(dx * s, dy * s, col)
                if s >= 2 and s <= R:
                    fr[1].put_if_empty(dx * (s + 1), dy * (s + 1), GOLD[4])
    return fr


def ring_gd(ramp, r, kind="ring"):
    """贴地环（压扁 SQ）：只画边。ring = 3 拍外扩的断续边；mark = 曳光锁定四角括号（4 拍收紧）；frag = 弹片环 + 外向短划"""
    C = RAMP[ramp]
    fr = []
    if kind == "mark":
        for k in range(4):
            b = Buf()
            rr = r + 3 - k
            for q in range(4):
                a0 = q * math.pi / 2 + math.pi / 4
                for j in range(-3, 4):
                    t = a0 + j * 0.13
                    b.put(math.cos(t) * rr, math.sin(t) * rr * SQ, C[5] if k < 2 else C[4])
            fr.append(b)
        return fr
    for k in range(3):
        b = Buf()
        rr = r * (0.75, 1.0, 1.08)[k]
        n = max(24, int(rr * 7))
        for i in range(n):
            t = i / n * math.tau
            if hsh(i, k, 11) % (7 if k < 2 else 3) == 0:
                continue
            col = (C[5], C[4], C[2])[k]
            b.put(math.cos(t) * rr, math.sin(t) * rr * SQ, col)
            if k < 2:   # 内侧一圈深色内边（颜色阶代替透明度渐变）
                b.put_if_empty(math.cos(t) * (rr - 1.2), math.sin(t) * (rr - 1.2) * SQ, C[1])
        if kind == "frag" and k < 2:
            for i in range(10):
                t = i / 10 * math.tau + 0.2
                for s in range(2):
                    b.put(math.cos(t) * (rr + 2 + s + k * 2), math.sin(t) * (rr + 2 + s + k * 2) * SQ, C[4] if s == 0 else C[3])
        fr.append(b)
    return fr


def halo(kind):
    """光环（立起层，原点 = 头顶光环中心）。halo = 队友头顶常驻（8 帧循环，一点亮光绕环走）；fire = 她开火时一亮（3 帧，环 + 四向短刺）；
    s3 = 过载期间她头顶的大光环 + 光刺（原作 angel_02，8 帧循环）；bless = 被祝福的队友出手时手边一颗金色小星芒（3 帧）"""
    G = GOLD
    fr = []
    if kind == "bless":
        for k in range(3):
            b = Buf()
            L = (3, 2, 1)[k]
            for s in range(0, L + 1):
                for (dx, dy) in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    b.put(dx * s, dy * s, G[6] if s == 0 else (G[5] if k == 0 else G[4]))
            fr.append(b)
        return fr
    ra, rb = (6.0, 2.0) if kind != "s3" else (9.0, 3.0)
    nfr = 3 if kind == "fire" else 8
    for k in range(nfr):
        b = Buf()
        n = 40 if kind != "s3" else 56
        for i in range(n):
            t = i / n * math.tau
            x, y = math.cos(t) * ra, math.sin(t) * rb
            if kind == "fire":
                col = (G[6], G[5], G[4])[k]
            elif kind == "s3":
                col = G[6] if (i + k * 7) % n < 10 else G[5]
            else:
                col = G[6] if abs(((i - k * n / 8) % n)) < 3 else (G[5] if math.sin(t) > 0 else G[4])
            b.put(x, y, col)
        if kind == "fire" and k < 2:
            for (dx, dy, L) in ((0, -1, 3), (0, 1, 2), (-1, 0, 3), (1, 0, 3)):
                for s in range(1, L + 1 - k):
                    b.put(dx * (ra + s) if dx else 0, dy * (rb + s) if dy else 0, G[5])
        if kind == "s3":   # 光刺：12 道，按帧闪烁、长短不一
            for i in range(12):
                if hsh(i, k, 5) % 3 == 0:
                    continue
                t = i / 12 * math.tau + 0.13
                L = 2 + hsh(i, k, 9) % 3
                for s in range(1, L + 1):
                    b.put(math.cos(t) * (ra + s), math.sin(t) * (rb + s * 0.8), G[5] if s < L else G[4])
        fr.append(b)
    return fr


def steam():
    """S2 结束枪管过热：枪口冒两缕烟往上飘（6 帧，原点 = 枪口）"""
    fr = []
    for k in range(6):
        b = Buf()
        for j in range(2):
            x = j * 3 - 1 + (1 if (k + j) % 3 == 0 else 0)
            y = -2 - k * 2 - j
            r = 1 if k < 3 else 2
            col = SMOKE[3 - min(3, k // 2 + j)]
            for dx in range(-r + 1, r):
                for dy in range(-r + 1, r):
                    if hsh(dx + k, dy + j, 3) % 4:
                        b.put(x + dx, y + dy, col)
        fr.append(b)
    return fr


# ---------------------------------------------------------------- 运行时件（游戏里 fx_pxplane_exu.gd 逐格画，这里是同一算法的 Python 版）
B_LEN = {"n": [9, 11, 13], "s1": [13, 15, 17], "s2": [7, 8, 9], "s3": [10, 11, 12], "g": [12, 13, 14], "t1": [11, 11, 13], "t2": [11, 11, 13], "t3": [11, 11, 13],
         "tr": [18, 18, 18], "x": [6, 6, 6]}


def bullet_kind(tex):
    """弹体帧条名 → 画法（与 fx_pxplane_exu.gd _bkind 一致）"""
    return {"proj_exusiai_bullet": "n", "proj_exusiai_bullet_s1": "s1", "proj_exusiai_bullet_s2": "s2", "proj_exusiai_bullet_s3": "s3",
            "proj_exusiai_bullet_power": "g", "proj_exusiai_bullet_t1": "t1", "proj_exusiai_bullet_t2": "t2", "proj_exusiai_bullet_t3": "t3"}.get(tex, "n")


def bullet(kind, tier, d, beat, small=False, tracer=False):
    """一颗弹（原点 = 弹头，d = 单位方向）：白弹头 + 渐暗的细长尾（原作 trail_32 的细长尖梭）。S1 / 倾泻：弹头前 3 格 3 像素宽（菱形）；
    S3：弹头 2 像素宽、尾带一格红边；精二：弹头两侧按拍闪一颗金点（天使的金星）。曳光弹（tr）：金色长尾。small = 额外弹 / 跳弹"""
    C = RAMP["g" if kind in ("tr",) else ("n" if kind == "x" else kind)]
    L = B_LEN["tr" if tracer else ("x" if small else kind)][tier]
    if tracer:
        C = GOLD
    nv = (-d[1], d[0])
    b = Buf()
    for i in range(L):
        u = i / L
        col = C[6] if i == 0 else (C[5] if i < 2 else (C[4] if u < 0.5 else (C[3] if u < 0.8 else C[2])))
        x, y = -d[0] * i, -d[1] * i
        b.put(x, y, col)
        if i < L * 0.6 and not small:   # 身段 2 像素厚（一侧暗一阶），后期满屏也读得出
            b.put_if_empty(x + nv[0], y + nv[1], C[4] if i < 2 else (C[3] if u < 0.5 else C[2]))
        wide = (kind in ("s1", "g") and i < 3 and not small) or (kind == "s3" and i < 2 and not small)
        if wide:
            w = 1 if not (kind in ("s1", "g") and i == 0) else 0
            if kind in ("s1", "g") and i == 1:
                w = 1
            for sd in (-1, 1):
                if w:
                    b.put(x + nv[0] * sd, y + nv[1] * sd, C[5] if i < 2 else C[4])
        if kind == "s3" and 2 <= i < L - 2 and i % 2 == 0:
            b.put(x + nv[0], y + nv[1], C[3])
    b.put(d[0], d[1], C[5])   # 弹头前一格
    if tier >= 2 and not small and beat % 2 == 0:
        b.put(nv[0] * 2 - d[0], nv[1] * 2 - d[1], GOLD[5])
        b.put(-nv[0] * 2 - d[0] * 2, -nv[1] * 2 - d[1] * 2, GOLD[4])
    return b


def tracer_line(L, f, i):
    """连携技「穿透扫射」一发曳光（原点 = 起点，沿 +x，长 L）：第 f 拍（0–2）画一段长 18 的亮段在 L·(f+1)/3 处，红金交替（i 奇偶）；身后留一条 1 像素暗线"""
    C = RAMP["n"] if i % 2 == 0 else GOLD
    b = Buf()
    head = L * (f + 1) / 3.0
    for s in range(int(head)):
        if s > head - 18:
            u = (head - s) / 18.0
            b.put(s, 0, C[6] if u < 0.12 else (C[5] if u < 0.4 else C[4]))
            if u < 0.4:
                b.put(s, -1, C[4])
        elif f < 2 and hsh(s, i, 1) % 3:
            b.put(s, 0, C[2])
    return b
