"""铃兰转平面（docs/271）的像素图形：狐火 / 光域 / 金印 / 祝福帧条，以及运行时件（狐火弹、光域边、传火线）的同一套画法（Python 版）。
tools/pxplane_bake_suzuran.py 用它烤帧条（game/art/fx/pxp/pxp_sz_*.png + game/data/pxp_suzuran.json），
tools/pxplane_gif_suzuran.py 用它拼送审 GIF；运行时件在游戏里由 fx_pxplane_sz.gd 逐格画，算法与本文件 fox_bolt() / aura_ring() / pass_line() 一一对应，改一边要改另一边。
单位：美术像素（游戏里 1 美术像素 = g.PX = 2 世界像素）。全部确定性（不用随机数，抖动用坐标哈希）。

配色：
- 狐火 F：暖金 7 阶（深棕 → 橙金 → 浅金 → 白），她的招牌；
- 浅色 P：浅紫白（狐火尖、九尾尾尖、狐火渺然的薄雾），任务单「暖金狐火配浅色」；
- 金印 G：亮金（全力以赴的符印、画地为牢、狐火灼印），比狐火更黄、线状；
- 祝福 M：浅薄荷（队长回复：铃兰小铃铛），和治疗绿分开、也和狐火分开。不用红。

每招不同招牌：普攻 = 追踪火团（命中小火苗炸开）；三火归一 = 狐形大狐火；S1 = 金色符印（脚下符阵 + 命中盖印）；
S2 = 落地火环（光域推开一圈火）；S3 = 尾焰扫过（一条大火尾绕身扫一圈）+ 薄雾 + 狐火落点；连携 = 四团狐火绕身后拖光追迹。"""
import math

F = ["#2a1405", "#5c2a0c", "#a04e14", "#e08424", "#ffb84a", "#ffe6a6", "#ffffff"]
P = ["#2e2a3e", "#5a5478", "#9690b8", "#cfcae8", "#f2f0ff"]
G = ["#3a2606", "#7a5410", "#c89420", "#ffd24a", "#fff0b0"]
M = ["#0c3020", "#22744a", "#5cc88a", "#b4f0cc", "#f0fff6"]
SQ = 0.72    # 贴地压扁（combat.GROUND_Y）
SQ_H = 0.55  # 围炉狐火的玩法位置（seg_suzuran._h4_hearth_tick 用 0.55 椭圆），画在玩法位置上

# 尺寸档（美术像素 = 判定半径 ÷ 2；游戏挑不超过判定 × 1.1 的最近一档）
S2_R = [68, 80, 92, 104]      # 儿时的舞乐起手火环（光域 (85 + 15 × 精英) × 1.6 × op_range）
S3_R = [94, 110, 126, 142]    # 狐火渺然尾焰（光域 × 2.2）
PRAY_R = [40, 48, 56, 64]     # 响应「祈愿」：队长处光域闪一下（r = aura 85 × op_range）
HB_R = [52, 60, 68]           # 围炉·添薪爆发（aura × 1.3）
SPLASH_R = 28                 # 扩散（splash_r 60）
ATT_R = 28                    # 狐火点点灼烧圈（att_r 60）


def hx(s):
    s = s.lstrip("#")
    return (int(s[0:2], 16), int(s[2:4], 16), int(s[4:6], 16), 255)


def hsh(x, y, k=0):
    return ((int(x) * 73856093) ^ (int(y) * 19349663) ^ (int(k) * 83492791)) & 0xFFFF


def hf(x, y, k=0):
    return hsh(x, y, k) / 65535.0


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

    def merge(self, o, keep=False):
        for k, c in o.p.items():
            if keep:
                self.p.setdefault(k, c)
            else:
                self.p[k] = c
        return self

    def shift(self, dx, dy):
        b = Buf()
        for (x, y), c in self.p.items():
            b.p[(x + dx, y + dy)] = c
        return b

    def keep(self, fn):
        b = Buf()
        for (x, y), c in self.p.items():
            if fn(x, y):
                b.p[(x, y)] = c
        return b


# ================================================================ 火苗（立起）：所有狐火的基本笔画

def flame(b, x0, y0, h, w, ph, seed=0, pale=False, cool=0):
    """一根往上的火舌：底在 (x0, y0)，高 h、底宽 w；ph = 拍（摇曳），cool = 往暗挪几阶（熄火）。
    外缘橙、里面浅金、底部中心白芯；pale = 尖上一点浅紫白（狐火的「浅色」）"""
    if h < 1:
        return
    hw0 = w / 2.0
    for yy in range(int(h) + 1):
        u = yy / max(1.0, h)
        half = hw0 * (1.0 - u ** 1.35)
        sway = round(math.sin(ph * 1.7 + yy * 0.55 + seed * 1.3) * u * 1.2)
        cx = x0 + sway
        y = y0 - yy
        r = int(round(half))
        for dx in range(-r, r + 1):
            edge = abs(dx) >= r and r > 0
            if u > 0.82:
                c = (P[3] if pale else F[4]) if u > 0.92 else F[4]
            elif edge:
                c = F[3] if u < 0.6 else F[2]
            elif u < 0.35 and abs(dx) <= max(0, r - 2):
                c = F[6] if (u < 0.18 and dx == 0) else F[5]
            else:
                c = F[4]
            if cool:
                c = _cool(c, cool)
            b.put(cx + dx, y, c)


def _cool(c, k):
    for pal in (F, P, G, M):
        if c in pal:
            i = pal.index(c)
            return pal[max(0, i - k)]
    return c


def flame_frames(h, w, n=6, pale=False, seed=0):
    """循环小火苗（狐火绕身 / 光域边 / 附着火 / 拖尾）：n 拍一循环，高度轻微起伏"""
    out = []
    for f in range(n):
        b = Buf()
        hh = h + (1 if f % 3 == 1 else 0) - (1 if f % 3 == 2 and h > 4 else 0)
        flame(b, 0, -1, hh, w, f * 2.1, seed, pale)
        b.put(0, 0, F[2])   # 底下一点暗色（贴地 / 接触）
        out.append(b)
    return out


# ================================================================ 运行时件（游戏里 fx_pxplane_sz.gd 逐格画，同算法）

def fox_bolt(d, bt, big=False):
    """狐火弹：头在 (0, 0)，往 d 方向飞。返回 [(沿向 s（往后为正）, 法向 w, 颜色)]。
    big = 全力以赴的强化狐火（头大一圈 + 分叉双尾，像狐尾）"""
    out = [(0, 0, F[6]), (-1, 0, F[5]), (0, 1, F[5]), (0, -1, F[5]), (1, 0, F[5]), (1, 1, F[4]), (1, -1, F[4]), (2, 0, F[4])]
    if big:
        out += [(-1, 1, F[4]), (-1, -1, F[4]), (0, 2, F[3]), (0, -2, F[3]), (-2, 0, F[5]), (1, 2, F[3]), (1, -2, F[3])]
        for s in range(2, 8):
            w = 1 if s < 6 else 2
            if (s + bt) % 4 == 3 and s > 3:
                continue
            col = F[4] if s < 4 else (F[3] if s < 6 else F[2])
            out.append((s, w, col))
            out.append((s, -w, col))
        out.append((8, 2 if bt % 2 == 0 else 1, P[3]))
        out.append((8, -2 if bt % 2 == 1 else -1, P[3]))
    else:
        for s in range(3, 6):
            if (s + bt) % 3 == 0 and s > 3:
                continue
            out.append((s, 0, F[3] if s < 5 else F[2]))
        out.append((4, 1 if bt % 2 == 0 else -1, F[3]))
        out.append((6, -1 if bt % 2 == 0 else 1, P[2]))
    return out


def aura_ring(R, bt, mode):
    """光域边（贴地、压扁 SQ）：返回 [(x, y, 颜色)]。mode：0 平时（暗、稀）/ 1 暖光（儿时的舞乐：亮一阶 + 内侧一圈浅色点）/ 2 狐火渺然（浅紫白与金交替 + 内侧两道薄雾细线）。
    虚线每 2 拍转一格；只画边不平涂"""
    out = []
    n = max(24, int(R * 6.4))
    rot = ((bt // 2) % 64) / 64.0 * math.tau / 12.0
    duty = [0.42, 0.62, 0.66][mode]
    seen = set()
    for q in range(n):
        t = q / n * math.tau
        seg = ((t - rot) % (math.tau / 12.0)) / (math.tau / 12.0)
        if seg > duty:
            continue
        x, y = round(R * math.cos(t)), round(R * math.sin(t) * SQ)
        if (x, y) in seen:
            continue
        seen.add((x, y))
        if mode == 0:
            c = F[2] if seg < duty * 0.7 else F[1]
        elif mode == 1:
            c = F[4] if seg < duty * 0.25 else (F[3] if seg < duty * 0.75 else F[2])
        else:
            c = P[3] if (q // 6) % 2 == 0 else F[3]
            if seg > duty * 0.8:
                c = P[1]
        out.append((x, y, c))
        if mode >= 1 and seg < duty * 0.75:   # 2 格暗内边（颜色阶代替透明度渐变）
            xi, yi = round((R - 1) * math.cos(t)), round((R - 1) * math.sin(t) * SQ)
            if (xi, yi) not in seen:
                seen.add((xi, yi))
                out.append((xi, yi, F[1] if mode == 1 else P[0]))
    if mode == 1:   # 暖光：内侧一圈浅色点，反向慢转
        r2 = R * 0.86
        m = max(12, int(r2 * 1.6))
        for q in range(m):
            t = q / m * math.tau - rot * 0.5
            if (q + bt // 3) % 3:
                continue
            out.append((round(r2 * math.cos(t)), round(r2 * math.sin(t) * SQ), P[2]))
    if mode == 2:   # 薄雾：两道起伏的细线（断续），缓慢漂
        for k, (rr, a) in enumerate(((0.74, 5), (0.5, 4))):
            r2 = R * rr
            m = max(16, int(r2 * 3.2))
            for q in range(m):
                t = q / m * math.tau
                if hf(q, k, 5) < 0.45 or (q + bt // 2 + k * 7) % 9 < 3:
                    continue
                wob = math.sin(t * a + bt * 0.12 + k) * 3.0
                out.append((round((r2 + wob) * math.cos(t)), round((r2 + wob) * math.sin(t) * SQ), P[2] if q % 4 else P[1]))
    return out


def pass_line(dx, dy, f):
    """传火（狐火点点）：两只敌人之间一道往上拱的金线（dx, dy = b − a，美术像素），3 拍：第 0 拍全亮、第 1 拍后半、第 2 拍只剩落点几格。返回 [(x, y, 颜色)]（相对 a）"""
    L = max(1.0, math.hypot(dx, dy))
    m = int(L)
    out = []
    for i in range(m + 1):
        u = i / max(1, m)
        if f == 1 and u < 0.45:
            continue
        if f >= 2 and u < 0.82:
            continue
        lift = 4.0 * L * 0.12 * u * (1.0 - u)
        out.append((round(dx * u), round(dy * u - lift), F[5] if (f == 0 and 0.3 < u < 0.9) else F[4]))
    return out


# ================================================================ 帧条

def hit_up():
    """狐火命中：一团小火苗炸开往上窜（立起，原点 = 命中点脚底往上 0；画面中心抬到 −6）"""
    out = []
    tongues = [(-4, 5, 3), (-2, 8, 3), (0, 10, 4), (2, 7, 3), (4, 5, 3)]
    for f in range(5):
        b = Buf()
        if f == 0:
            for (x, y) in [(0, -6), (-1, -6), (1, -6), (0, -5), (0, -7)]:
                b.put(x, y, F[6])
            for k in range(4):
                a = k * math.tau / 4 + 0.6
                for s in range(2, 5):
                    b.put(round(math.cos(a) * s), -6 + round(math.sin(a) * s), F[5] if s < 4 else F[4])
        elif f <= 3:
            kk = f
            for j, (x, h, w) in enumerate(tongues):
                hh = h * (0.7 if kk == 1 else (1.0 if kk == 2 else 0.6))
                flame(b, x * (1 + 0.2 * kk), -2, hh, w, f * 1.9 + j, j, cool=0 if kk < 3 else 1)
        else:
            for j in range(5):
                b.put(-4 + 2 * j + (j % 2), -6 - (j * 3) % 5, F[3] if j % 2 else F[2])
        out.append(b)
    return out


def ring_gd(R, n=4, col=None, start=0.5, tongue=False):
    """贴地小火环（往外推一点、变暗、断开）：狐火命中 / 扩散 / 灼烧圈"""
    out = []
    for f in range(n):
        b = Buf()
        r = R * (start + (1.0 - start) * min(1.0, (f + 1) / (n - 1)))
        m = max(16, int(r * 6.4))
        for q in range(m):
            t = q / m * math.tau
            if hf(q, f, int(R)) < 0.18 + 0.2 * f:
                continue
            c = [F[5], F[4], F[3], F[2], F[1]][min(4, f)] if col is None else col[min(len(col) - 1, f)]
            b.put(r * math.cos(t), r * math.sin(t) * SQ, c)
            if f <= 1:
                b.put((r - 1) * math.cos(t), (r - 1) * math.sin(t) * SQ, F[2])
        out.append(b)
    return out


def ring_tongues(R, n_t, frames, h0, seed, half=None, travel=None):
    """一圈火舌（立起）：在半径 R（压扁）上 n_t 根火苗，frames 拍：窜起 → 变矮熄掉。
    half = 'b' 只要后半圈（y ≤ 0，排在人后）/ 'f' 只要前半圈；travel = (r0, r1)：火环从 r0 推到 r1"""
    out = []
    for f in range(frames):
        b = Buf()
        u = f / max(1, frames - 1)
        rr = R if travel is None else travel[0] + (travel[1] - travel[0]) * min(1.0, u * 1.4)
        hk = min(1.0, (f + 1) / 2.0) * (1.0 - max(0.0, u - 0.45) / 0.55)
        for k in range(n_t):
            a = k * math.tau / n_t + hf(k, 3, seed) * 0.4
            x, y = rr * math.cos(a), rr * math.sin(a) * SQ
            if half == "b" and y > 0.5:
                continue
            if half == "f" and y <= 0.5:
                continue
            h = h0 * (0.6 + 0.6 * hf(k, 9, seed)) * hk
            flame(b, x, y, h, 3 if h > 4 else 2, f * 1.7 + k, k + seed, pale=(k % 3 == 0), cool=0 if u < 0.6 else 1)
        out.append(b)
    return out


def big_ring_gd(R, frames, travel=None, col=None, seed=0):
    """大火环的贴地部分：断续的亮边 + 2 格暗内边，推开后变暗散掉"""
    out = []
    for f in range(frames):
        b = Buf()
        u = f / max(1, frames - 1)
        rr = R if travel is None else travel[0] + (travel[1] - travel[0]) * min(1.0, u * 1.4)
        m = max(24, int(rr * 6.4))
        for q in range(m):
            t = q / m * math.tau
            if hf(q, f // 2, seed) < 0.1 + 0.55 * max(0.0, u - 0.35):
                continue
            cs = col or [F[5], F[4], F[4], F[3], F[3], F[2], F[2], F[1]]
            c = cs[min(len(cs) - 1, int(u * len(cs)))]
            b.put(rr * math.cos(t), rr * math.sin(t) * SQ, c)
            if u < 0.7:
                b.put_if_empty((rr - 1) * math.cos(t), (rr - 1) * math.sin(t) * SQ, F[2])
                b.put_if_empty((rr - 2) * math.cos(t), (rr - 2) * math.sin(t) * SQ, F[1])
        out.append(b)
    return out


def bigfox(d_deg, f):
    """三火归一的狐形大狐火（朝 d_deg 方向跑，逆映射采样，任意角都不漏格）：头在 (0, 0)、两只耳朵往后外撇、身子收成一条摇曳的长火尾"""
    a = math.radians(d_deg)
    ca, sa = math.cos(a), math.sin(a)
    b = Buf()
    for y in range(-18, 19):
        for x in range(-18, 19):
            s = x * ca + y * sa      # 沿向（往前为正）
            w = -x * sa + y * ca     # 法向
            c = _fox_px(s, w, f)
            if c:
                b.put(x, y, c)
    return b


def _fox_px(s, w, f):
    # 头：椭圆（前钝后宽）
    hd = (s / 3.4) ** 2 + (w / 2.8) ** 2
    if hd <= 1.0:
        if hd < 0.22:
            return F[6]
        return F[5] if hd < 0.65 else F[4]
    # 耳：两只往后外撇的三角
    for sg in (1, -1):
        es, ew = s + 1.2, w * sg - 1.6
        if -5.0 < es < 0.6 and 0 <= ew <= 2.6 * (es + 5.0) / 5.6 + 0.3 and ew < 3.2:
            return P[3] if es < -3.4 else (F[5] if ew < 0.8 else F[4])
    # 身子 → 火尾
    if -15.5 < s < -1.0:
        u = (-s - 1.0) / 14.5
        cw = math.sin(-s * 0.55 + f * 1.6) * u * 1.6
        half = 2.4 * (1.0 - u ** 0.9) + 0.6
        dw = abs(w - cw)
        if dw <= half:
            if u > 0.88:
                return P[3] if (int(-s) + f) % 2 == 0 else None
            if dw < half * 0.4 and u < 0.45:
                return F[5]
            return F[4] if dw < half * 0.75 else (F[3] if u < 0.6 else F[2])
    return None


def tails(f, flare=False):
    """九尾虚影（精二，立起，排在她身后）：九条蓬松的狐尾从腰后扇开（170°），每条中段最粗、尾尖一截浅紫白，
    每条外面 1 格暗描边，前后叠着也分得清是九条；慢慢摆。原点 = 她脚底；尾根在 (−1, −17)。
    flare = 全力以赴精二起手：尾巴张得更开、更长、整条提亮一阶（6 拍）"""
    b = Buf()
    root = (-1, -17)
    order = [0, 8, 1, 7, 2, 6, 3, 5, 4]   # 先画两边（靠后），最后画中间
    for k in order:
        t = (k - 4) / 4.0
        a0 = -math.pi / 2 + t * (1.62 if not flare else 1.78)
        sway = math.sin(f * 0.78 + k * 0.9) * 0.09
        L = (24 - abs(t) * 4) + (4 if flare else 0)
        body = {}
        steps = int(L * 2)
        for i in range(steps + 1):
            u = i / steps
            an = a0 + sway * u * 2.0 + u * u * 0.35 * (1 if t >= 0 else -1)
            cx = root[0] + math.cos(an) * L * u
            cy = root[1] + math.sin(an) * L * u * 0.92
            hw = 0.5 + 2.4 * math.sin(math.pi * min(1.0, u ** 0.85 * 0.98 + 0.02))
            if u > 0.86:
                hw *= max(0.25, (1.0 - u) / 0.14)
            r = int(math.ceil(hw))
            for dy in range(-r, r + 1):
                for dx in range(-r, r + 1):
                    if dx * dx + dy * dy > hw * hw + 0.3:
                        continue
                    key = (int(round(cx + dx)), int(round(cy + dy)))
                    dd = math.hypot(dx, dy) / max(0.6, hw)
                    if u > 0.72:
                        c = P[4] if (flare or dd < 0.5) else P[3]
                    elif dd < 0.45:
                        c = F[5] if flare else F[4]
                    else:
                        c = F[4] if flare else F[3]
                    if key not in body or body[key][1] < -dd:
                        body[key] = (c, -dd)
        for (x, y) in body:   # 描边：这条尾巴的外沿 1 格暗色（盖住后面那条，分出层次）
            for ex, ey in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                q = (x + ex, y + ey)
                if q not in body:
                    b.put(q[0], q[1], F[1])
        for (x, y), (c, _) in body.items():
            b.put(x, y, c)
    return b


def tails_frames(flare=False):
    return [tails(f, flare) for f in range(8 if not flare else 6)]


def sigil_gd(R, f, n_f, gold=True, mark=5):
    """金色符印（贴地压扁）：外圈 + 内圈 + 五个角点连线（五芒），第 0–2 拍描出来，之后亮着慢转，最后两拍暗掉"""
    b = Buf()
    draw_u = min(1.0, (f + 1) / 3.0)
    fade = max(0, f - (n_f - 3))
    col_hi = [G[4], G[3], G[2], G[1]][min(3, fade)]
    col_lo = [G[2], G[2], G[1], G[0]][min(3, fade)]
    rot = f * 0.06
    m = max(24, int(R * 6.4))
    for q in range(int(m * draw_u)):
        t = q / m * math.tau + rot
        b.put(R * math.cos(t), R * math.sin(t) * SQ, col_hi if q % 5 else G[4] if fade == 0 else col_hi)
    r2 = R * 0.72
    m2 = max(16, int(r2 * 6.4))
    for q in range(int(m2 * draw_u)):
        if q % 3 == 2:
            continue
        t = -q / m2 * math.tau - rot
        b.put(r2 * math.cos(t), r2 * math.sin(t) * SQ, col_lo)
    if f >= 2:
        pts = [(r2 * math.cos(rot + k * math.tau / mark - math.pi / 2), r2 * math.sin(rot + k * math.tau / mark - math.pi / 2) * SQ) for k in range(mark)]
        for k in range(mark):
            a, c2 = pts[k], pts[(k + 2) % mark]
            nn = int(max(abs(c2[0] - a[0]), abs(c2[1] - a[1]))) + 1
            for i in range(nn + 1):
                u = i / nn
                if i % 2 == 0:
                    b.put_if_empty(a[0] + (c2[0] - a[0]) * u, a[1] + (c2[1] - a[1]) * u, col_lo)
        for (x, y) in pts:
            b.put(x, y, col_hi)
            b.put(x, y - 1, G[4] if fade == 0 else col_hi)
    return b


def stamp_gd(f):
    """全力以赴命中的金印（贴地）：菱形符框盖下去（第 0 拍大而亮 → 收到 r 7 → 停 → 暗掉）"""
    b = Buf()
    r = [10, 8, 7, 7, 7, 7][f]
    hi = [G[4], G[4], G[3], G[3], G[2], G[1]][f]
    for i in range(-r, r + 1):
        k = r - abs(i)
        for (x, y) in ((i, k * SQ), (i, -k * SQ)):
            b.put(x, y, hi)
    if f >= 1:
        for (x, y) in ((0, 0), (-2, 0), (2, 0), (0, -1), (0, 1)):
            b.put(x, y, G[3] if f < 4 else G[1])
    return b


def seal_gd(f):
    """画地为牢（被定身的敌人脚下，循环 8 拍，跟着那只）：外圈 r 11 + 内方框慢转 + 四角点"""
    b = Buf()
    R = 11
    m = 70
    for q in range(m):
        t = q / m * math.tau
        if (q + f) % 7 == 6:
            continue
        b.put(R * math.cos(t), R * math.sin(t) * SQ, G[3] if q % 2 else G[2])
    rot = f / 8.0 * (math.pi / 2)
    sq = [(math.cos(rot + k * math.pi / 2 + math.pi / 4) * 8, math.sin(rot + k * math.pi / 2 + math.pi / 4) * 8 * SQ) for k in range(4)]
    for k in range(4):
        a, c = sq[k], sq[(k + 1) % 4]
        nn = int(max(abs(c[0] - a[0]), abs(c[1] - a[1]))) + 1
        for i in range(nn + 1):
            u = i / nn
            b.put_if_empty(a[0] + (c[0] - a[0]) * u, a[1] + (c[1] - a[1]) * u, G[2])
        b.put(a[0], a[1], G[4])
    return b


def brand_gd(f):
    """狐火灼印（精一，被狐火打中的敌人脚下小金印，循环 6 拍）：小环 r 6 + 三点绕转"""
    b = Buf()
    R = 6
    m = 40
    for q in range(m):
        t = q / m * math.tau
        if q % 4 == 3:
            continue
        b.put(R * math.cos(t), R * math.sin(t) * SQ, G[2])
    for k in range(3):
        t = f / 6.0 * math.tau / 3 + k * math.tau / 3
        b.put(R * math.cos(t), R * math.sin(t) * SQ, G[4])
        b.put((R - 1) * math.cos(t), (R - 1) * math.sin(t) * SQ, G[3])
    return b


def column_up():
    """全力以赴精一：杖头一束往上窜的火柱（细、高，6 拍），原点 = 杖头"""
    out = []
    for f in range(6):
        b = Buf()
        hk = [0.5, 1.0, 1.0, 0.8, 0.5, 0.25][f]
        for j, (x, h) in enumerate([(-2, 12), (0, 20), (2, 14), (-1, 9), (1, 10)]):
            flame(b, x, 0, h * hk, 3 if j < 3 else 2, f * 1.9 + j, j, pale=(j == 1), cool=0 if f < 4 else 1)
        if f == 0:
            for (x, y) in [(0, 0), (-1, 0), (1, 0), (0, -1), (0, 1)]:
                b.put(x, y, F[6])
        out.append(b)
    return out


def gather():
    """三火归一：杖头一团狐火在长大（循环 4 拍，汇聚期间画）"""
    out = []
    for f in range(4):
        b = Buf()
        r = 3 + (f % 2)
        for y in range(-r, r + 1):
            for x in range(-r, r + 1):
                d = math.hypot(x, y * 1.1)
                if d <= r:
                    b.put(x, y, F[6] if d < 1.2 else (F[5] if d < r - 1 else F[4]))
        flame(b, 0, -r, 4 + f % 2, 3, f * 2.0, 2, pale=True)
        out.append(b)
    return out


def drop_frames():
    """狐火渺然期间的狐火落点：一团狐火从上面落下（3 拍）→ 落地炸开一圈小火舌（5 拍）；原点 = 落点脚底"""
    out = []
    for f in range(8):
        b = Buf()
        if f < 3:
            y = -26 + f * 9
            for (s, w, c) in fox_bolt((0, 1), f):
                b.put(w * -1, y - s, c)   # 朝下飞（d = (0, 1)：沿向 = y，法向 = −x）
        else:
            k = f - 3
            b.merge(ring_tongues(7, 6, 5, 6, 31)[k])
            if k == 0:
                for (x, y) in [(0, -2), (-1, -2), (1, -2), (0, -3)]:
                    b.put(x, y, F[6])
        out.append(b)
    return out


def drop_gd():
    out = [Buf() for _ in range(3)]
    out += ring_gd(9, 5)
    return out


def heal_up():
    """祝福（队长回复）：头顶三朵铃兰小铃铛慢慢落下、闪一下薄荷光（10 拍）；原点 = 队长脚底"""
    bell = [(0, -1), (-1, 0), (0, 0), (1, 0), (-1, 1), (1, 1)]
    out = []
    spots = [(-7, -44), (0, -50), (7, -42)]
    for f in range(10):
        b = Buf()
        for j, (bx, by) in enumerate(spots):
            ff = f - j
            if ff < 0 or ff > 7:
                continue
            y = by + ff * 2
            x = bx + round(math.sin(ff * 0.9 + j) * 1.0)
            hi = M[4] if ff < 3 else (M[3] if ff < 6 else M[2])
            for (dx, dy) in bell:
                b.put(x + dx, y + dy, hi if dy <= 0 else M[3])
            b.put(x, y - 2, M[2])   # 花梗
            if ff in (2, 5):
                for (dx, dy) in ((-2, 0), (2, 0), (0, -3), (0, 3)):
                    b.put(x + dx, y + dy, M[3])
        out.append(b)
    return out


def heal_gd():
    return ring_gd(9, 5, col=[M[4], M[3], M[2], M[2], M[1]], start=0.4)


def sweep(R, f, n_f, half=None):
    """狐火渺然起手「尾焰扫过」（立起）：一条大火尾贴着地面绕她扫一圈（≈ 300°，头亮尾暗、尾巴越往后越矮越稀），
    扫到哪里那里留一排矮火舌很快熄掉。half = 'b' / 'f' 前后半圈分开排序。原点 = 脚底"""
    b = Buf()
    head = -math.pi * 0.6 + f / (n_f - 3) * math.tau * 0.84
    span = 1.9
    n_t = int(R * 0.9)
    for k in range(n_t):
        a = -math.pi * 0.6 + k / n_t * math.tau * 0.84
        lag = head - a
        if lag < 0 or a > head:
            continue
        rr = R * (0.92 + 0.08 * math.sin(a * 3 + 1.0))
        x, y = rr * math.cos(a), rr * math.sin(a) * SQ
        if half == "b" and y > 0.5:
            continue
        if half == "f" and y <= 0.5:
            continue
        if lag < span:   # 尾焰本体：头最高最亮最密（像一条蓬起的狐尾），往后变矮变稀
            u = lag / span
            h = (18 if u < 0.12 else 15 * (1 - u) + 3) * (0.5 + 0.7 * hf(k, 1, 7))   # 高低错落，不成一排齐的火墙
            if (k % 2 and u > 0.45) or (k % 3 == 1 and u > 0.25):
                continue
            flame(b, x, y, h, 5 if u < 0.25 else 3, f * 1.7 + k, k, pale=(u < 0.2 or k % 5 == 0))
            if u < 0.3:   # 头部两侧再各补一根（蓬松）
                for sd in (-1, 1):
                    flame(b, x + sd * 2, y - sd, h * 0.7, 3, f * 1.7 + k + sd, k + 11 * sd)
        elif lag < span + 1.4 and k % 3 == 0:   # 余火：一排矮火舌，很快熄
            u2 = (lag - span) / 1.4
            flame(b, x, y, 4 * (1 - u2) + 1, 2, f * 1.3 + k, k, cool=1 + int(u2 * 2))
    return b


def sweep_gd(R, f, n_f):
    """尾焰扫过的贴地部分：扫过处一道焦亮的弧（亮 → 暗 → 断开），跟着火尾头走"""
    b = Buf()
    head = -math.pi * 0.6 + f / (n_f - 3) * math.tau * 0.84
    m = int(R * 6.4)
    for q in range(m):
        a = -math.pi * 0.6 + q / m * math.tau * 0.84
        lag = head - a
        if lag < 0:
            continue
        if lag > 2.6 or hf(q, f // 2, 3) < lag / 3.2:
            continue
        rr = R * (0.92 + 0.08 * math.sin(a * 3 + 1.0))
        c = F[4] if lag < 0.5 else (F[3] if lag < 1.3 else F[2])
        b.put(rr * math.cos(a), rr * math.sin(a) * SQ, c)
        b.put_if_empty((rr - 1) * math.cos(a), (rr - 1) * math.sin(a) * SQ, F[1])
    return b


def att_tick_gd():
    return ring_gd(ATT_R, 4, col=[F[3], F[3], F[2], F[1]], start=0.8)


def splash_frames():
    return ring_gd(SPLASH_R, 4, start=0.35)


def tuft_frames():
    """精二狐火拖尾：大狐火飞过的路上留下的一簇矮火苗（循环 6 拍，按剩余寿命变矮变暗，游戏里按寿命挑帧组）"""
    out = []
    for lv in range(3):   # 0 新 / 1 中 / 2 将熄
        for f in range(4):
            b = Buf()
            h = [6, 4, 2][lv]
            flame(b, -1, 0, h + (f % 2), 3, f * 2.0, lv, cool=lv)
            flame(b, 2, 0, max(1, h - 2 + ((f + 1) % 2)), 2, f * 2.0 + 1, lv + 3, cool=lv)
            out.append(b)
    return out
