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
MZ_L = {"n": [14, 16, 18], "s1": [16, 18, 20], "s2": [12, 14, 16], "s3": [16, 18, 20], "g": [14, 16, 18]}   # 11-05 第三轮按实机 1 倍放大约一倍
HIT_N = {"n": [8, 10, 12], "s1": [10, 12, 14], "s2": [8, 10, 11], "s3": [10, 12, 14], "g": [10, 12, 14], "x": [5, 5, 5], "full": [12, 12, 12]}
HIT_L = {"n": [9, 10, 12], "s1": [10, 12, 14], "s2": [8, 9, 10], "s3": [10, 12, 14], "g": [10, 12, 14], "x": [6, 6, 6], "full": [12, 12, 12]}
# 金属火花（橙白，所有模式共用；模式色只在命中芯上）与碎屑
SPARK = ["#5a2a0c", "#9a4a14", "#d87a28", "#ffb050", "#ffe0a0", "#fff6e0", "#ffffff"]
CHIP = ["#2a2628", "#4a4448", "#6e666c"]


def _rot(d, a):
    c, s = math.cos(a), math.sin(a)
    return (d[0] * c - d[1] * s, d[0] * s + d[1] * c)


def _spike(b, o, d, L, cols, keep=False):
    """一道 1 像素硬芒：从 o 沿 d 走 L 格，颜色按 cols 依次（最后一个延续到底）"""
    for s in range(L):
        c = cols[min(s, len(cols) - 1)]
        (b.put_if_empty if keep else b.put)(o[0] + d[0] * s, o[1] + d[1] * s, c)


def muzzle(mode, tier, deg, var=0):
    """枪口火（立起层，原点 = 枪口）：2 拍硬星形短闪。第 0 拍：3×3 白芯 + 前向长芒（根部 3 像素宽、收成 1 像素尖）+ 侧芒 + 后向短芒；
    第 1 拍：芯暗一阶、前芒剩一半、侧芒剩 1 格。var 0 = 侧芒垂直（十字），var 1 = 侧芒斜前 45°（星形、前芒短 1）——连射时交替，有节奏变化。
    倾泻 g = 前向五道扇形硬芒；S3 = 垂直 + 斜向都有（八芒）。精一：前芒 +2；精二：芯两侧各一颗金星"""
    C = RAMP[mode]
    a = math.radians(deg)
    d = (math.cos(a), math.sin(a))
    nv = (-d[1], d[0])
    L = MZ_L[mode][tier] + (2 if tier >= 1 else 0) - (1 if var == 1 else 0)
    P = 6 + 2 * tier
    f0, f1 = Buf(), Buf()
    fronts = [0.0] if mode != "g" else [-0.42, -0.21, 0.0, 0.21, 0.42]
    for ra in fronts:
        dd = _rot(d, ra)
        nn = (-dd[1], dd[0])
        LL = L if ra == 0.0 else L - 3
        _spike(f0, (dd[0] * 2, dd[1] * 2), dd, LL, [C[6], C[6], C[5], C[5], C[4], C[4], C[3]])
        if ra == 0.0:
            for q in (-2, -1, 1, 2):   # 根部 5 像素宽，收尖
                _spike(f0, (dd[0] * 2 + nn[0] * q, dd[1] * 2 + nn[1] * q), dd, max(2, LL // (3 if abs(q) == 1 else 5)), [C[5], C[4]] if abs(q) == 1 else [C[4], C[3]], keep=True)
        _spike(f1, (dd[0] * 2, dd[1] * 2), dd, max(2, LL // 2), [C[5], C[4], C[3]])
    sides = []
    if var == 0 or mode == "s3":
        sides += [nv, (-nv[0], -nv[1])]
    if var == 1 or mode == "s3":
        sides += [_rot(d, 0.785), _rot(d, -0.785)]
    for sd in sides:
        _spike(f0, (sd[0] * 2, sd[1] * 2), sd, P, [C[5], C[4], C[3]])
        f1.put(sd[0] * 2, sd[1] * 2, C[3])
    _spike(f0, (-d[0] * 2, -d[1] * 2), (-d[0], -d[1]), 4, [C[5], C[4], C[3]])
    for x in range(-2, 3):
        for y in range(-2, 3):
            if abs(x) + abs(y) <= 3:
                f0.put(x, y, C[6] if abs(x) + abs(y) <= 2 else C[5])
            if abs(x) + abs(y) <= 2:
                f1.put(x, y, C[5] if abs(x) + abs(y) <= 1 else C[4])
    if tier >= 2:
        for sd in (-1, 1):
            f0.put(nv[0] * 2 * sd - d[0], nv[1] * 2 * sd - d[1], GOLD[6])
            f1.put(nv[0] * 3 * sd - d[0], nv[1] * 3 * sd - d[1], GOLD[4])
    return [f0, f1]


def smoke():
    """偶发枪口烟（每 3 轮一缕，原点 = 枪口）：5 拍，一缕灰烟弯着往上飘、变淡"""
    fr = []
    for k in range(5):
        b = Buf()
        for j in range(3 + k // 2):
            y = -1 - k * 2 - j
            x = round(math.sin((j + k) * 0.9) * (1 + k * 0.4)) + k // 2
            col = SMOKE[max(0, 3 - (k + j) // 2)]
            b.put(x, y, col)
            if k >= 2 and j % 2 == 0:
                b.put(x + 1, y, SMOKE[max(0, 2 - (k + j) // 2)])
        fr.append(b)
    return fr


def hit(mode, tier, deg):
    """命中（立起层，原点 = 命中点，deg = 弹道方向）：4 拍硬质金属火花溅射 + 碎屑，不是一团光。
    第 0 拍：模式色 3×3 芯 + n 道 1 像素火花（多数往回溅：弹道反向 ±75°，两道往前穿），橙白；
    第 1 拍：火花外移变橙、剩外半段，2–3 块深色碎屑飞起；第 2 拍：火花尖端几点下坠、碎屑下落；第 3 拍：余烬 + 碎屑落地。
    精二质变：一道沿弹道往前的穿甲亮线（白金，2 拍）。full = 精一叠满金色 X；x = 额外弹 / 连锁的小火花（3 道、无碎屑）"""
    C = RAMP["g" if mode == "full" else ("n" if mode == "x" else mode)]
    S = SPARK if mode != "full" else GOLD
    a = math.radians(deg)
    d = (math.cos(a), math.sin(a))
    n = HIT_N[mode][tier]
    Lm = HIT_L[mode][tier]
    fr = [Buf() for _ in range(4)]
    for i in range(n):
        if i < 2 and mode != "x":   # 两道往前穿
            ang = a + (0.35 if i == 0 else -0.4)
        else:
            ang = a + math.pi + (-1.3 + 2.6 * ((i * 0.618 + hsh(i, tier, 3) % 7 * 0.02) % 1.0))
        sd = (math.cos(ang), math.sin(ang))
        L = Lm - (hsh(i, n, 5) % 3)
        _spike(fr[0], (sd[0] * 2, sd[1] * 2), sd, max(3, int(L * 0.65)), [S[6], S[5], S[5], S[4], S[4], S[3]])
        for s in range(int(L * 0.5), L + 1):   # 第 1 拍：外半段，带一点下坠
            u = s / max(1, L)
            fr[1].put(sd[0] * (s + 1), sd[1] * (s + 1) + u * 1.5, S[4] if u < 0.75 else S[3])
        fr[2].put(sd[0] * (L + 2), sd[1] * (L + 2) + 3, S[3])
        if i % 2 == 0:
            fr[2].put(sd[0] * (L + 1), sd[1] * (L + 1) + 2, S[2])
        if i % 3 == 0:
            fr[3].put(sd[0] * (L + 2), sd[1] * (L + 2) + 6, S[2])
    for x in range(-2, 3):
        for y in range(-2, 3):
            if abs(x) + abs(y) <= 3:
                fr[0].put(x, y, C[6] if abs(x) + abs(y) <= 2 else C[5])
            if abs(x) + abs(y) <= 1:
                fr[1].put(x, y, C[5] if (x, y) == (0, 0) else C[4])
    if mode != "x":   # 碎屑：深色小块往回上方飞、落下
        for j in range(2 + (1 if tier >= 1 else 0)):
            ang = a + math.pi + (-0.7 + 0.7 * j)
            sd = (math.cos(ang), math.sin(ang))
            fr[1].put(sd[0] * 3, sd[1] * 3 - 2, CHIP[2])
            fr[2].put(sd[0] * 5, sd[1] * 5 - 1, CHIP[1])
            if j == 0:
                fr[2].put(sd[0] * 5 + 1, sd[1] * 5 - 1, CHIP[1])
            fr[3].put(sd[0] * 6, sd[1] * 6 + 4, CHIP[0])
    if mode == "s3":
        for i in range(24):
            t = i / 24 * math.tau
            fr[1].put_if_empty(math.cos(t) * (Lm - 1), math.sin(t) * (Lm - 1), C[3])
    if mode == "full":
        for s in range(-Lm, Lm + 1):
            for w in (0, 1):
                fr[0].put(s, s + w, GOLD[6] if abs(s) < 3 else GOLD[5])
                fr[0].put(s, -s + w, GOLD[6] if abs(s) < 3 else GOLD[5])
            if abs(s) > 2:
                fr[1].put(s, s, GOLD[4])
                fr[1].put(s, -s, GOLD[4])
    if tier >= 2 and mode in ("n", "s1", "s2", "s3", "g"):   # 精二：穿甲亮线
        _spike(fr[0], (d[0] * 3, d[1] * 3), d, 11, [GOLD[5], GOLD[6], GOLD[6], GOLD[5], GOLD[5], GOLD[4]], keep=True)
        for s in range(6, 12):
            fr[1].put_if_empty(d[0] * s, d[1] * s, GOLD[4] if s < 10 else GOLD[3])
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
# 11-05 第四轮（用户「还是以肉鸽的可视化为优先级最高」）：高可读光弹——弹身 B 格（4 宽 + 一圈光晕描边，第五轮加大约 30%）+ 亮尾 T 格
B_BODY = {"n": [8, 9, 9], "s1": [10, 10, 10], "s2": [7, 8, 8], "s3": [9, 9, 9], "g": [9, 10, 10], "t1": [8, 9, 9], "t2": [8, 9, 9], "t3": [8, 9, 9], "tr": [10, 10, 10], "x": [5, 5, 5]}
B_TAIL = {"n": [10, 12, 13], "s1": [13, 14, 14], "s2": [8, 9, 10], "s3": [11, 12, 12], "g": [10, 12, 12], "t1": [11, 12, 13], "t2": [11, 12, 13], "t3": [11, 12, 13], "tr": [18, 18, 18], "x": [6, 6, 6]}


def bullet_kind(tex):
    """弹体帧条名 → 画法（与 fx_pxplane_exu.gd _bkind 一致）"""
    return {"proj_exusiai_bullet": "n", "proj_exusiai_bullet_s1": "s1", "proj_exusiai_bullet_s2": "s2", "proj_exusiai_bullet_s3": "s3",
            "proj_exusiai_bullet_power": "g", "proj_exusiai_bullet_t1": "t1", "proj_exusiai_bullet_t2": "t2", "proj_exusiai_bullet_t3": "t3"}.get(tex, "n")


def bullet_px(kind, tier, d, small=False, tracer=False):
    """光弹的像素表：[(x, y, 色阶序号 或 "rim", 是否进发光层)]，原点 = 弹头。按弹道坐标扫像素格分类（任意方向都不漏洞）：
    a = 沿弹道往后的距离、c = 横向偏移；弹身 a∈[-0.5, B-0.5]、c∈[-1.5, 1.5 + (wide-1)]（两头各收窄 1）；外扩 1 格是光晕描边；
    亮尾 a∈(B-0.5, B+T-0.5]，|c|<0.5（前 3 格 |c|<1.5）。游戏里 fx_pxplane_exu._bul_px 同一算法（按 32 个方向缓存）"""
    key = "tr" if tracer else ("x" if small else kind)
    B = B_BODY[key][tier]
    T = B_TAIL[key][tier]
    wide = 2 if not small else 1   # 11-05 第五轮：精零 / 精一也 4 宽（档差靠金描边、金星、穿甲亮线、光环，不靠尺寸）
    c0, c1 = -1.5, 1.5 + (wide - 1)
    R = B + T + 4
    out = []
    for y in range(-R, R + 1):
        for x in range(-R, R + 1):
            av = -(x * d[0] + y * d[1])
            cv = x * -d[1] + y * d[0]
            end = av < 0.5 or av > B - 1.5
            lo, hi = (c0 + 1, c1 - 1) if end else (c0, c1)
            if -0.5 <= av <= B - 0.5 and lo <= cv <= hi:
                white = abs(cv - (wide - 1) * 0.5) < 0.5 + (wide - 1) * 0.5 and not (end and av > B - 1.5)
                out.append((x, y, 6 if white else 5, white))
            elif not small and -1.5 <= av <= B - 0.5 + 0.5 and lo - 1 <= cv <= hi + 1 and not (av > B - 0.5 and abs(cv) < 0.5):
                out.append((x, y, "rim", False))
            elif B - 0.5 < av <= B + T - 0.5:
                j = av - B
                u = j / max(1, T)
                if abs(cv) < 0.5:
                    out.append((x, y, 5 if u < 0.3 else (4 if u < 0.65 else 3), False))
                elif j < 2.5 and abs(cv) < 1.5 and not small:
                    out.append((x, y, 4 if j < 1.5 else 3, False))
    return out


def bullet(kind, tier, d, beat, small=False, tracer=False, back=0):
    """一颗光弹（原点 = 弹头，d = 单位方向），肉鸽式高可读弹，不追求像真子弹：弹身中线白芯、两侧亮色（4 宽），
    外面一圈光晕描边（本色；精一起金色）、两头圆钝，芯进发光层；亮尾前 3 格 3 宽、之后 1 宽渐暗；精二弹头两侧按拍闪金点；
    额外弹 / 跳弹（small）小一号无描边。back = 只画面的后移（美术像素，倾泻扇形错开用）"""
    C = RAMP["g" if kind in ("tr",) else ("n" if kind == "x" else kind)]
    if tracer:
        C = GOLD
    rim = GOLD[4] if (tier >= 1 and not small and not tracer) else C[3]
    ox, oy = round(-d[0] * back), round(-d[1] * back)
    b = Buf()
    for (x, y, k, _) in bullet_px(kind, tier, d, small, tracer):
        b.put(ox + x, oy + y, rim if k == "rim" else C[k])
    if tier >= 2 and not small and beat % 2 == 0:
        nv = (-d[1], d[0])
        b.put(ox - d[0] + nv[0] * -4, oy - d[1] + nv[1] * -4, GOLD[6])
        b.put(ox - d[0] * 2 + nv[0] * 5, oy - d[1] * 2 + nv[1] * 5, GOLD[5])
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
