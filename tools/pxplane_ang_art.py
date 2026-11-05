"""安洁莉娜转平面（docs/267）的像素图形：重力弹 / 落点内爆 / 失重井 / 悬浮 / 微粒绸带 / 反重力场 / 连携碎片的帧条（Python 版，唯一来源）。
tools/pxplane_bake_angelina.py 用它烤帧条（game/art/fx/pxp/pxp_an_*.png + game/data/pxp_angelina.json），
tools/pxplane_gif_angelina.py 用它拼送审 GIF；运行时小件（弹尾、弹药珠、连携碎片尾迹、透镜线）在 fx_pxplane_ang.gd 逐格画，
算法与本文件 trail_px() / pips_px() / link_trail() 一一对应，改一边要改另一边。
单位：美术像素（游戏里 1 美术像素 = g.PX = 2 世界像素）。全部确定性（不用随机数，抖动用坐标哈希）。
配色：pixelfx house.js OP.angelina 紫 7 阶 + 最暗压底一阶（用户 11-04 认可）；精二专属点缀 = 发箍红压暗（组长 C 11-04 配色甲），只用在奇点描边段。"""
import math

V = ["#140c24", "#312f5c", "#5c4a8e", "#8765c0", "#b280f2", "#cdacf7", "#e8d9fb", "#ffffff"]
ACC = ["#3a1416", "#8a3330", "#b4504a"]
SHADOW = "#0b0812"
SQ = 0.72          # 贴地压扁（combat.GROUND_Y）
Z = [1.0, 1.15, 1.3]   # 尺寸档（op_range / 范围加成变大时挑不超过判定 ×1.1 的最大一档）


def hx(s):
    s = s.lstrip("#")
    return (int(s[0:2], 16), int(s[2:4], 16), int(s[4:6], 16), 255)


def hsh(x, y, k=0):
    return ((x * 73856093) ^ (y * 19349663) ^ (k * 83492791)) & 0xFFFF


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

    def line(self, x0, y0, x1, y1, c, keep=False):
        n = max(1, int(math.ceil(max(abs(x1 - x0), abs(y1 - y0)))))
        for i in range(n + 1):
            u = i / n
            (self.put_if_empty if keep else self.put)(x0 + (x1 - x0) * u, y0 + (y1 - y0) * u, c)


def ease_in(u):
    return u * u


def ease_out(u):
    return 1 - (1 - u) * (1 - u)


# ---------------------------------------------------------------- 重力弹
def orb(tier, big=False):
    """重力弹弹体（立起层，原点 = 弹心），4 帧循环：黑紫实心核 + 一圈亮紫边（亮点绕边走）+ 白高光。
    精一：两颗小卫星绕弹转（引力）；精二质变：核更大、下沿一段发箍红描边（奇点意象）。big = 速充模式强化弹（大一号、芯更亮）"""
    R = (3 if not big else 4) + (1 if tier >= 2 else 0)
    fr = []
    for k in range(4):
        b = Buf()
        for y in range(-R - 1, R + 2):
            for x in range(-R - 1, R + 2):
                d = math.hypot(x, y)
                if d <= R - 1.0:
                    b.put(x, y, V[0] if d < R - 2.0 or tier >= 2 else V[1])
                elif d <= R + 0.4:
                    a = (math.atan2(y, x) / math.tau * 8 - k * 2) % 8
                    b.put(x, y, V[7] if a < 0.8 else (V[6] if a < 2.4 else (V[5] if a < 4 or big else V[4])))
        b.put(-R + 1, -R + 1, V[7])
        if big:
            b.put(-R + 2, -R + 1, V[7])
            b.put(0, 0, V[2])
        if tier >= 2:
            for x in range(-1, 2):
                b.put(x, R, ACC[2] if x == 0 else ACC[1])
        if tier >= 1:
            for j in range(2):
                a = k * math.pi / 2 + j * math.pi
                b.put(math.cos(a) * (R + 3), math.sin(a) * (R + 3) * 0.6, V[5] if j == 0 else V[4])
        fr.append(b)
    return fr


def orb_shadow():
    b = Buf()
    for x in range(-2, 3):
        b.put(x, 0, SHADOW)
    b.put(-1, 1, SHADOW)
    b.put(0, 1, SHADOW)
    b.put(1, 1, SHADOW)
    return [b]


def trail_px(k_list):
    """弹尾（运行时）：弹身后沿弧线 3 点，越远越暗。返回 [(序号, 色阶)]"""
    return [(1, 4), (2, 3), (3, 2)]


def pips_px(n, beat):
    """速充模式剩余弹数（运行时，头顶上方，原点 = 头顶）：n 颗 3×3 十字小珠绕一圈扁椭圆转。返回 [(x, y, 色)]"""
    out = []
    for j in range(n):
        a = beat * 0.42 + j * math.tau / 3.0
        x, y = round(math.cos(a) * 7), round(math.sin(a) * 2)
        front = math.sin(a) > 0
        out.append((x, y, V[7] if front else V[6]))
        for (dx, dy) in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            out.append((x + dx, y + dy, V[5] if front else V[4]))
    return out


# ---------------------------------------------------------------- 落点内爆
def _star(b, L, cols, n=4, sd=0, th=1.6, cy=0.0, cx=0.0):
    """不规整星芒（中心 (cx, cy)）：n 道芒，长短不一，根部粗、尖端 1 像素；斜叉（n = 8 的奇数道）短一截"""
    a0 = 0.35 + 0.3 * hf(sd, 1)
    for i in range(n):
        a = a0 + i * math.tau / n + 0.18 * (hf(i, sd, 3) - 0.5)
        LL = L * (0.7 + 0.45 * hf(i, sd, 5)) * (0.6 if (n > 4 and i % 2) else 1.0)
        d = 0.0
        while d <= LL:
            w = max(0.0, th * (1 - d / LL))
            s = -w
            while s <= w + 0.01:
                ci = min(len(cols) - 1, int(d / LL * len(cols) + abs(s) * 0.6))
                b.put_if_empty(cx + math.cos(a) * d - math.sin(a) * s, cy + (math.sin(a) * d + math.cos(a) * s) * 0.8, cols[ci])
                s += 0.5
            d += 0.5


def _tri(b, cx, cy, sz, rot, body, rim):
    """小三角碎片（黑紫身 + 亮紫边一角）"""
    pts = [(cx + math.cos(rot + i * math.tau / 3) * sz * (1.25 if i == 0 else 1.0), cy + math.sin(rot + i * math.tau / 3) * sz * 0.8) for i in range(3)]
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    for y in range(int(math.floor(min(ys))), int(math.ceil(max(ys))) + 1):
        for x in range(int(math.floor(min(xs))), int(math.ceil(max(xs))) + 1):
            # 重心坐标判断
            (x1, y1), (x2, y2), (x3, y3) = pts
            den = (y2 - y3) * (x1 - x3) + (x3 - x2) * (y1 - y3)
            if abs(den) < 1e-6:
                continue
            l1 = ((y2 - y3) * (x - x3) + (x3 - x2) * (y - y3)) / den
            l2 = ((y3 - y1) * (x - x3) + (x1 - x3) * (y - y3)) / den
            l3 = 1 - l1 - l2
            if min(l1, l2, l3) >= -0.12:
                b.put(x, y, rim if l1 > 0.62 else body)
    b.put(pts[0][0], pts[0][1], rim)


def land(tier, mode, z):
    """重力弹落点（原点 = 落点地面）。返回 (立起层帧, 贴地层帧)。
    立起层：不规整星芒爆点（白 → 亮紫，2 拍收）；mode s1（秘杖·速充模式）= 先三根细长光刺从上往下钉进落点（原作 S3 三叉意象，立起），钉到地那一拍再爆星芒。
    贴地层：拉拢半径边缘的三角碎片先慢后快吸向落点（带 1 像素细引线）→ 落点压出不规整暗凹（上沿一道亮唇）；
    精一新元素「重力停顿」：三段断开的弧从落点半径往里收紧；精二另有失重井（单独件）。精二星芒八芒。全程只往里收，不画外扩环"""
    s1 = mode == "s1"
    zk = Z[z]
    pull = 50.0 * zk * 0.92            # 拉拢半径 100 世界 = 50 美术像素（碎片起点 ≤ 判定）
    aoe = (37.5 if not s1 else 52.5) * zk
    L = [16, 18, 20][tier] + (3 if s1 else 0)
    n_arm = 8 if tier >= 2 else 4
    sd = 3 + tier + (7 if s1 else 0)
    up = []
    if s1:   # 光刺下钉：第 0 拍刺在空中往下落，第 1 拍钉到地 + 星芒
        spikes = [(-9, 2, 30), (1, -2, 38), (9, 3, 26)]
        f = Buf()
        for (sx, sy, sl) in spikes:
            f.line(sx, sy * SQ - 30 - sl * 0.6, sx, sy * SQ - 30, V[5])
            f.put(sx, sy * SQ - 30, V[7])
            f.put(sx, sy * SQ - 31, V[6])
        up.append(f)
    for k in range(6):   # docs/270 补齐：星芒收掉后落点中心留一颗白热「压缩点」再亮 3 拍（发光核心）
        f = Buf()
        if s1 and k <= 3:
            for (sx, sy, sl) in spikes:
                top = sy * SQ - sl * (1.0 - 0.25 * k)
                for y in range(int(top), int(sy * SQ) + 1):
                    u = (y - top) / max(1, sy * SQ - top)
                    f.put(sx, y, V[7] if k <= 1 or u > 0.55 else (V[6] if k == 2 else V[5]))
                    if k == 0:
                        f.put(sx + 1, y, V[6] if u > 0.3 else V[5])
                if k == 0:
                    f.put(sx - 1, sy * SQ - 1, V[5])
                    f.put(sx + 1, sy * SQ - 1, V[5])
        if k == 0:
            _star(f, L, [V[7], V[7], V[7], V[6], V[6], V[5]], n_arm, sd, 2.8, -12)
            for x in range(-3, 4):
                for y in range(-3, 4):
                    if abs(x) + abs(y) <= 3:
                        f.put(x, -12 + y, V[7])
        elif k == 1:
            _star(f, L * 0.65, [V[7], V[6], V[6], V[5], V[4]], n_arm, sd, 1.8, -12)
            for x in range(-1, 2):
                for y in range(-1, 2):
                    f.put(x, -12 + y, V[7])
        elif k == 2:
            _star(f, L * 0.35, [V[6], V[5], V[4]], 4, sd, 1.0, -12)
            for x in range(-2, 3):
                for y in range(-2, 3):
                    if abs(x) + abs(y) <= 2:
                        f.put(x, -12 + y, V[7])
        elif k <= 4:
            r0 = 2 if k == 3 else 1
            for x in range(-r0, r0 + 1):
                for y in range(-r0, r0 + 1):
                    if abs(x) + abs(y) <= r0:
                        f.put(x, -12 + y, V[7] if abs(x) + abs(y) < r0 or k == 4 else V[6])
            f.put(2, -15, V[5])
            f.put(-3, -14, V[4])
        else:
            f.put(0, -12, V[6])
            f.put(1, -14, V[4])
            f.put(-2, -15, V[3])
        up.append(f)
    # 贴地层
    gd = []
    nsh = (5 if not s1 else 7) + (1 if tier >= 2 else 0)
    shards = []
    gaps = [0.35 + 1.5 * hf(i, sd, 11) for i in range(nsh)]   # 角度按不等间隔累加（组长 C 11-04：不等距）
    gs = sum(gaps)
    a = hf(sd, 9) * math.tau
    for i in range(nsh):
        a += gaps[i] / gs * math.tau
        r0 = pull * (0.72 + 0.28 * hf(i, sd, 13))
        dl = int(hf(i, sd, 17) * 2)   # 出发先后
        shards.append((a, r0, dl, (3.4 if not s1 else 4.0) + hf(i, sd, 19) * 1.2, hf(i, sd, 23) * math.tau))
    dent_r = 7 + 2 * tier + (3 if s1 else 0)
    NF = 9
    for k in range(NF):
        f = Buf()
        # 暗凹（第 1 拍起）
        if k >= 1:
            fade = 0 if k < 6 else (k - 5)
            rr = dent_r * (0.7 if k == 1 else 1.0) * (1.0 - 0.12 * fade)
            for y in range(-int(rr) - 2, int(rr) + 3):
                for x in range(-int(rr) - 2, int(rr) + 3):
                    nz = 0.8 * (hf(x // 2, y // 2, 31) - 0.5)
                    d = math.hypot(x, y / SQ) + nz * 2
                    if d <= rr:
                        if fade >= 2 and hsh(x, y, k) % 3 == 0:
                            continue
                        f.put(x, y, V[0] if d < rr - 2 else V[1])
            if k < 7:   # 上沿亮唇
                for i in range(-int(rr * 0.8), int(rr * 0.8) + 1):
                    yy = -math.sqrt(max(0.0, rr * rr - i * i)) * SQ
                    if hsh(i, k, 37) % 4:
                        f.put(i, yy, V[4] if k < 4 else V[3])
        # 碎片吸入（第 0–4 拍）
        for (sa, r0, dl, sz, rot) in shards:
            kk = k - dl
            if kk < 0 or kk > 4:
                continue
            u = ease_in(kk / 4.0)
            rr = r0 * (1 - u)
            cx, cy = math.cos(sa) * rr, math.sin(sa) * rr * SQ
            if kk >= 1:   # 细引线：身后一段（越快越长）
                tl = 3 + 7 * u
                for s in range(1, int(tl) + 1):
                    q = rr + s
                    f.put_if_empty(math.cos(sa) * q, math.sin(sa) * q * SQ, V[3] if s < tl * 0.5 else V[2])
            if kk < 4:
                _tri(f, cx, cy, sz * (1.0 - 0.3 * u), rot + kk * 0.9, V[1], V[5] if kk < 3 else V[4])
        # 重力停顿：三段断弧往里收紧（精一起）
        if tier >= 1 and k <= 5:
            rr = aoe * 0.95 * (1 - ease_out(min(1.0, k / 5.0))) + 5
            for j in range(3):
                a0 = j * math.tau / 3 + 0.4 + 0.3 * hf(j, tier, 41)
                span = 0.9 + 0.3 * hf(j, 5, 43)
                n = max(6, int(rr * span))
                for i in range(n + 1):
                    t = a0 + span * i / n
                    col = V[6] if k == 0 else (V[5] if k < 3 else V[4])
                    f.put(math.cos(t) * rr, math.sin(t) * rr * SQ, col)
                    if k < 2:
                        f.put_if_empty(math.cos(t) * (rr - 1), math.sin(t) * (rr - 1) * SQ, V[3])
        gd.append(f)
    return up, gd


# ---------------------------------------------------------------- 失重井（精二）
def well(z):
    """失重井（贴地，原点 = 井心），18 帧 = 1.2 秒播完整口井：张开（3 拍）→ 三条长短不一的细旋臂往井心卷、碎末顺臂吸进去 →
    最后 3 拍整口井往中心塌没。井心黑紫不规整暗块、上沿亮唇、下沿一段发箍红描边（精二专属）。全程只往里，不画外扩环"""
    R = 30.0 * Z[z] * 0.95
    fr = []
    for k in range(18):
        b = Buf()
        if k < 3:
            cr = 3 + k * 2.2
        elif k < 15:
            cr = 8 + (1 if (k % 4) < 2 else 0)
        else:
            cr = 8 * (1 - (k - 14) / 4.0) + 1
        # 旋臂（第 2–14 拍）
        if 2 <= k <= 14:
            for j in range(3):
                L = (0.85, 1.0, 0.7)[j]
                base = j * math.tau / 3 + k * 0.42 + 0.3 * j
                for i in range(40):
                    u = i / 39.0
                    r = R * L * (1 - u) + cr * u
                    t = base + u * 2.0
                    col = V[2] if u < 0.35 else (V[3] if u < 0.75 else V[4])
                    b.put_if_empty(math.cos(t) * r, math.sin(t) * r * SQ, col)
                # 碎末：沿臂往里走
                for q in range(2):
                    u = ((k * 0.11 + q * 0.5 + j * 0.23) % 1.0) ** 1.6
                    r = R * L * (1 - u) + cr * u
                    t = base + u * 2.0
                    b.put(math.cos(t) * r, math.sin(t) * r * SQ - 1, V[5] if u > 0.4 else V[4])
        # 井心暗块
        for y in range(-int(cr) - 2, int(cr) + 3):
            for x in range(-int(cr) - 2, int(cr) + 3):
                nz = hf(x // 2 + k // 3, y // 2, 51) - 0.5
                d = math.hypot(x, y / SQ) + nz * 1.6
                if d <= cr:
                    b.put(x, y, V[0] if d < cr - 1.2 else V[1])
        if k < 17:
            for i in range(-int(cr * 0.75), int(cr * 0.75) + 1):   # 上沿亮唇
                b.put(i, -math.sqrt(max(0.0, cr * cr - i * i)) * SQ - 0.6, V[5] if k < 15 else V[4])
            for i in range(-int(cr * 0.4), int(cr * 0.4) + 1):     # 下沿发箍红一段
                b.put(i + 1, math.sqrt(max(0.0, cr * cr - i * i)) * SQ + 0.4, ACC[1] if abs(i) > 0 else ACC[2])
        if k == 17:
            b.p = {}
            b.put(0, 0, V[5])
            b.put(1, 0, V[4])
        fr.append(b)
    return fr


# ---------------------------------------------------------------- 悬浮（贴地，挂在悬浮敌人脚下）
def float_lines(sz):
    """悬浮附件（贴地，原点 = 敌人脚底），6 帧循环：脚下 2–3 道向上的短竖线（长短不一、轮流往上提、顶端亮）。
    影子随高度缩小与轻微上下浮动在 world.gd 画（只改画面）"""
    xs = [-sz, sz]   # 两道（S3 一场几十只同时悬浮，三道显碎）
    fr = []
    for k in range(6):
        b = Buf()
        for j, x in enumerate(xs):
            ph = (k + j * 2) % 6
            L = 2 + (1 if ph < 3 else 0)
            y0 = -1 - ph
            for s in range(L):
                b.put(x, y0 - s, V[4] if s == L - 1 else V[3])
        fr.append(b)
    return fr


# ---------------------------------------------------------------- 小件：双重引力回响 / 扩散 / 致密 / 沉落锁
def ring_in(r, nf=4, star=0, cols=(5, 4, 3, 2), dash=4):
    """往里收的断续环（贴地，压扁）：r → 6；star > 0 时最后一拍中心一颗小星芒（贴地不立起，压扁）"""
    fr = []
    for k in range(nf):
        b = Buf()
        rr = r * (1 - ease_out(k / nf)) + 4
        n = max(16, int(rr * 5))
        for i in range(n):
            if (i // 2) % dash == dash - 1:
                continue
            t = i / n * math.tau + k * 0.2
            b.put(math.cos(t) * rr, math.sin(t) * rr * SQ, V[cols[min(k, len(cols) - 1)]])
        if star and k >= nf - 2:
            _star(b, star * (1.0 if k == nf - 2 else 0.5), [V[7], V[6], V[5]] if k == nf - 2 else [V[5], V[4]], 4, 61, 1.0, 0)
        fr.append(b)
    return fr


def dense_pop(r):
    """致密坍缩爆开（立起层，原点 = 落点地面）：八芒星芒 + 一圈亮环外闪（坍缩爆开是这里唯一往外的一下，半径 ≤ 判定）"""
    fr = []
    for k in range(4):
        b = Buf()
        if k == 0:
            _star(b, 14, [V[7], V[7], V[6], V[5], V[4]], 8, 71, 1.8, -6)
        elif k == 1:
            _star(b, 9, [V[6], V[5], V[4]], 8, 71, 1.2, -6)
        rr = r * (0.55 + 0.15 * k)
        if k < 3:
            n = int(rr * 5)
            for i in range(n):
                if hsh(i, k, 73) % 3 == 0:
                    continue
                t = i / n * math.tau
                b.put(math.cos(t) * rr, math.sin(t) * rr * SQ, V[[6, 5, 3][k]])
        fr.append(b)
    return fr


def lock_mark(r):
    """潮汐锁·沉落锁定（贴地，原点 = 敌人脚底）：四角括号收紧 4 拍"""
    fr = []
    for k in range(4):
        b = Buf()
        rr = r + 3 - k
        for q in range(4):
            a0 = q * math.pi / 2 + math.pi / 4
            for j in range(-3, 4):
                t = a0 + j * 0.14
                b.put(math.cos(t) * rr, math.sin(t) * rr * SQ, V[6] if k < 1 else (V[5] if k < 3 else V[4]))
        fr.append(b)
    return fr


def cast_star():
    """速充模式起手（立起层，原点 = 杖头）：杖头一记四芒星 3 拍"""
    fr = []
    for k in range(3):
        b = Buf()
        _star(b, [9, 6, 3][k], [V[7], V[6], V[5]] if k == 0 else [V[5], V[4]], 4, 81, [1.4, 1.0, 0.6][k], 0)
        fr.append(b)
    return fr


# ---------------------------------------------------------------- S2 秘杖·微粒模式
def band(z):
    """环带（贴地循环 8 帧，原点 = 场心）：环带半径上的稀疏短划，慢慢转；常驻所以很暗（只画边）"""
    R = 55.0 * Z[z]
    fr = []
    for k in range(8):
        b = Buf()
        n = int(R * 4.5)
        for i in range(n):
            seg = (i + k) % 12
            if seg >= 3:
                continue
            t = i / n * math.tau
            b.put(math.cos(t) * R, math.sin(t) * R * SQ, V[3] if (i // 12) % 4 == 0 and seg == 1 else V[2])
        fr.append(b)
    return fr


def band_open(z):
    """微粒模式展开（贴地 6 帧）：场外一圈短划往里收到环带半径、亮一下"""
    R = 55.0 * Z[z]
    Ro = 75.0 * Z[z] * 0.97
    fr = []
    for k in range(6):
        b = Buf()
        rr = Ro + (R - Ro) * ease_out(min(1.0, k / 3.0))
        n = int(rr * 4.5)
        for i in range(n):
            if (i % 9) >= 4:
                continue
            t = i / n * math.tau - k * 0.08
            b.put(math.cos(t) * rr, math.sin(t) * rr * SQ, V[[6, 5, 5, 4, 3, 2][k]])
        fr.append(b)
    return fr


def ribbon(tier, z, rot):
    """微粒绸带（贴地 7 帧，原点 = 场心）：精一 2 条 / 精二 3 条连续细绸带从场外不同方位起手，绕着她旋进、收到环带上的同一处，
    那里一记小星芒；绸带只占半圈多、不闭合。精二质变：绸带加厚到 2 格、汇点变成一颗黑紫奇点（亮月牙 + 发箍红一段）。rot = 汇点方位（度）"""
    R = 55.0 * Z[z]
    Ro = 75.0 * Z[z] * 0.97
    ac = math.radians(rot)
    ns = 2 if tier < 2 else 3
    wide = tier >= 2
    paths = []
    for j in range(ns):
        span = (2.0, 1.55, 1.8)[j]   # 同一个旋向，起手方位错开；每条只占约 90–115°，合起来也不闭合
        a_in = (0.0, 0.75, -0.6)[j]
        pts = []
        N = 220
        for i in range(N + 1):
            u = i / N
            t = ac - (span + a_in) * (1 - u) ** 0.8 + a_in * 0.0
            r = (Ro + 6) * (1 - u) ** 1.3 + R * (1 - (1 - u) ** 1.3) + 3 * math.sin(u * 6 + j * 2) * (1 - u)
            pts.append((math.cos(t) * r, math.sin(t) * r * SQ))
        paths.append(pts)
    px, py = math.cos(ac) * R, math.sin(ac) * R * SQ
    fr = []
    for k in range(7):
        b = Buf()
        head = [0.35, 0.7, 1.0, 1.0, 1.0, 1.0, 1.0][k]
        tail = [0.0, 0.0, 0.1, 0.45, 0.8, 1.01, 1.01][k]
        for pts in paths:
            N = len(pts) - 1
            for i in range(N + 1):
                u = i / N
                if u > head or u < tail:
                    continue
                rel = (u - tail) / max(0.01, head - tail)
                col = V[5] if (head - u) < 0.08 and k < 3 else (V[4] if rel > 0.55 else (V[3] if rel > 0.2 else V[2]))
                x, y = pts[i]
                b.put(x, y, col)
                if wide:
                    b.put_if_empty(x, y + 1, V[2] if col != V[5] else V[4])
        if k >= 2:   # 汇点
            if not wide:
                if k <= 4:
                    _star(b, [6, 4, 2][k - 2], [V[7], V[6], V[5]] if k == 2 else [V[5], V[4]], 4, 91, 1.0, py, px)
            elif k <= 5:
                for y in range(-2, 3):
                    for x in range(-2, 3):
                        if abs(x) + abs(y) <= 3:
                            b.put(px + x, py + y, V[0] if abs(x) + abs(y) <= 2 else V[1])
                for x in range(-2, 2):
                    b.put(px + x, py - 3, V[6] if k == 2 else V[5])
                b.put(px, py + 3, ACC[2])
                b.put(px + 1, py + 3, ACC[1])
        fr.append(b)
    return fr


# ---------------------------------------------------------------- S3 秘杖·反重力模式
def lift_edge(z, opening=False):
    """反重力场边（贴地，原点 = 场心）：常驻 = 很暗的稀疏点线慢慢转（8 帧循环）；opening = 起手 6 帧从 1.06 倍往里收到场边、亮一下，内侧一圈淡环"""
    R = 110.0 * Z[z] * 0.97
    fr = []
    for k in range(8 if not opening else 6):
        b = Buf()
        rr = R if not opening else R * (1.06 - 0.06 * ease_out(min(1.0, k / 3.0)))
        n = int(rr * 4)
        for i in range(n):
            if not opening:
                if (i + k) % 10 >= 2:
                    continue
                col = V[2] if (i // 10) % 3 else V[3]
            else:
                if (i + k) % 6 >= 3:
                    continue
                col = V[[6, 5, 5, 4, 3, 2][k]]
            t = i / n * math.tau
            b.put(math.cos(t) * rr, math.sin(t) * rr * SQ, col)
        if opening and 1 <= k <= 4:
            r2 = R * 0.55
            n2 = int(r2 * 3)
            for i in range(n2):
                if i % 4:
                    continue
                t = i / n2 * math.tau + 0.3
                b.put(math.cos(t) * r2, math.sin(t) * r2 * SQ, V[3])
        fr.append(b)
    return fr


BLADES = [(-132, 30), (-97, 38), (-60, 26)]   # 身后三叉光刃：角度（度，-90 = 正上）、长度（美术像素）


def blades(cast=False):
    """身后三叉光刃（立起层，原点 = 她脚底，画在本体后面）：三道从腰后斜伸的细长光刃（长短不一），沿刃身亮斑往外跑、刃尖一闪一闪，随呼吸微微张合（8 帧循环）。
    cast = 起手 4 帧：光刃从 0 弹到全长、刃尖白热"""
    root = (0, -34)
    fr = []
    for k in range(8 if not cast else 4):
        b = Buf()
        for j, (deg, L) in enumerate(BLADES):
            a = math.radians(deg + (1.5 * math.sin(k * math.pi / 4 + j) if not cast else 0))
            LL = L * ([0.3, 0.75, 1.08, 1.0][k] if cast else (1.0 + 0.06 * math.sin(k * math.pi / 4 + j * 2)))
            d = (math.cos(a), math.sin(a))
            nv = (-d[1], d[0])
            spot = ((k * 5 + j * 11) % int(L)) if not cast else -1
            for s in range(int(LL) + 1):
                x, y = root[0] + d[0] * (s + 4), root[1] + d[1] * (s + 4)
                tip = s >= LL - 2
                col = V[6] if (tip and (k + j) % 2 == 0) or abs(s - spot) < 1 or (cast and k <= 1) else (V[5] if s < LL * 0.5 else V[4])
                if tip and cast and k == 2:
                    col = V[7]
                b.put(x, y, col)
                if s < LL * 0.35:   # 根部 2 宽
                    b.put_if_empty(x + nv[0], y + nv[1], V[3])
        if cast and k <= 1:
            _star(b, [8, 5][k], [V[7], V[6], V[5]], 4, 97, 1.2, root[1] - 2)
        fr.append(b)
    return fr


def rock(var):
    """反重力碎石（立起层，原点 = 落脚地面）：12 帧 = 0.8 秒：被托离地面（脚下影子随高度缩小）→ 悬停一下 → 落回、小弹一下 → 变暗没入地面。
    碎石：黑紫身、顶面一阶亮、底面一格紫光反射"""
    shapes = [[(-4, -1), (-2, -4), (2, -4), (4, -1), (3, 2), (-2, 2)],
              [(-5, 0), (-2, -3), (3, -4), (5, -1), (2, 2), (-3, 2)],
              [(-2, -4), (2, -4), (4, 0), (2, 3), (-3, 2)]][var % 3]
    H = [0, 5, 10, 13, 14, 13, 14, 13, 8, 0, 2, 0]
    fr = []
    for k in range(12):
        b = Buf()
        h = H[k]
        sw = max(2, 5 - h // 4)
        if k < 11:
            for x in range(-sw, sw + 1):
                b.put(x, 1, SHADOW)
        if k == 11:
            for x in range(-2, 3):
                b.put(x, 0, V[1])
            fr.append(b)
            continue
        xs = [p[0] for p in shapes]
        ys = [p[1] for p in shapes]
        for y in range(min(ys), max(ys) + 1):
            for x in range(min(xs), max(xs) + 1):
                if _inside(x, y, shapes):
                    col = V[1]
                    if y == min(ys) or not _inside(x, y - 1, shapes):
                        col = V[2]
                    b.put(x, y - h - 2, col)
        if h > 0:
            b.put(0, max(ys) - h - 1, V[4] if k < 8 else V[3])
        fr.append(b)
    return fr


def _inside(x, y, poly):
    c = False
    n = len(poly)
    for i in range(n):
        (x1, y1), (x2, y2) = poly[i], poly[(i + 1) % n]
        if (y1 > y) != (y2 > y):
            xi = x1 + (y - y1) * (x2 - x1) / (y2 - y1)
            if x < xi + 0.01:
                c = not c
    return c


# ---------------------------------------------------------------- 连携「引力环」
def link_shard():
    """连携碎片（立起层，原点 = 碎片中心），4 帧自转循环：较大的黑紫三角 + 亮紫边 + 白尖"""
    fr = []
    for k in range(4):
        b = Buf()
        _tri(b, 0, 0, 6.5, k * math.tau / 4 + 0.3, V[1], V[5])
        b.put(math.cos(k * math.tau / 4 + 0.3) * 8, math.sin(k * math.tau / 4 + 0.3) * 5.2, V[7])
        b.put(math.cos(k * math.tau / 4 + 0.3) * 7, math.sin(k * math.tau / 4 + 0.3) * 4.4, V[6])
        fr.append(b)
    return fr


def link_trail():
    """连携碎片尾迹（运行时）：沿轨道往回每 0.01 秒一个采样点，相邻两点连成 1 像素线（第 i 段 = 第 i−1 到第 i 个点），色阶 5 → 2。返回 [(段序号, 色阶)]"""
    return [(1, 5), (2, 5), (3, 4), (4, 4), (5, 3), (6, 2)]


def link_land():
    """连携落定（原点 = 区域中心）：同普攻落点的形状语言，大一号（星芒 22、暗凹 14），立起 + 贴地"""
    up = []
    for k in range(4):
        b = Buf()
        if k == 0:
            _star(b, 22, [V[7], V[7], V[7], V[6], V[6], V[5]], 4, 101, 2.8, -7)
            for x in range(-3, 4):
                for y in range(-3, 4):
                    if abs(x) + abs(y) <= 3:
                        b.put(x, -7 + y, V[7])
        elif k == 1:
            _star(b, 14, [V[6], V[5], V[4], V[3]], 4, 101, 1.4, -7)
        elif k == 2:
            _star(b, 6, [V[5], V[4]], 4, 101, 0.8, -7)
        up.append(b)
    gd = []
    rr0 = 14
    for k in range(9):
        b = Buf()
        if k >= 1:
            fade = 0 if k < 6 else k - 5
            rr = rr0 * (0.7 if k == 1 else 1.0) * (1 - 0.12 * fade)
            for y in range(-int(rr) - 2, int(rr) + 3):
                for x in range(-int(rr) - 2, int(rr) + 3):
                    nz = 0.8 * (hf(x // 2, y // 2, 103) - 0.5)
                    d = math.hypot(x, y / SQ) + nz * 2
                    if d <= rr:
                        if fade >= 2 and hsh(x, y, k) % 3 == 0:
                            continue
                        b.put(x, y, V[0] if d < rr - 2 else V[1])
            if k < 7:
                for i in range(-int(rr * 0.8), int(rr * 0.8) + 1):
                    if hsh(i, k, 107) % 4:
                        b.put(i, -math.sqrt(max(0.0, rr * rr - i * i)) * SQ, V[4] if k < 4 else V[3])
        gd.append(b)
    return up, gd


# ---------------------------------------------------------------- 第二轮（11-05 用户「S3 的光刃很奇怪，S2 和 S3 的问题修改一下，可以稍微华丽一点」）
def band2(z):
    """环带 v2（贴地循环 8 帧，原点 = 场心）：比 v1 亮一档的稀疏短划 + 6 颗沿环带流动的光点（亮头 + 4 格尾，相邻两颗反向），1 倍下读得出范围"""
    R = 55.0 * Z[z]
    fr = []
    n = int(R * 4.5)
    for k in range(8):
        b = Buf()
        for i in range(n):
            seg = (i + k) % 12
            if seg >= 4:
                continue
            t = i / n * math.tau
            b.put(math.cos(t) * R, math.sin(t) * R * SQ, V[4] if (i // 12) % 3 == 0 and seg in (1, 2) else V[3])
        for j in range(6):
            sgn = 1 if j % 2 == 0 else -1
            t0 = j * math.tau / 6 + sgn * (k / 8.0) * (math.tau / 6)
            for s in range(5):
                t = t0 - sgn * s * 0.035
                col = V[7] if s == 0 else (V[6] if s == 1 else (V[5] if s < 4 else V[4]))
                b.put(math.cos(t) * R, math.sin(t) * R * SQ, col)
            b.put(math.cos(t0) * R, math.sin(t0) * R * SQ - 1, V[5])
        fr.append(b)
    return fr


def gcore(cast=False):
    """反重力「重力核心」（立起层，原点 = 核心中心，游戏里放在她头顶上方 112 世界像素，跟她走）：
    黑紫实心核（亮紫边、白高光、下沿发箍红一小段）+ 两道斜着的光环（前半亮、后半暗被核挡住）绕核转，各有一颗白亮珠沿环走；
    外圈一圈暗紫点线一呼一吸。8 帧循环。cast = 起手 5 帧：外圈一圈亮点往里收成核、一记星芒"""
    fr = []
    RC = 6
    rings = [(16.0, 5.0, math.radians(18)), (15.0, 4.5, math.radians(-24))]
    for k in range(8 if not cast else 5):
        b = Buf()
        if cast and k < 3:   # 往里收
            rr = 26 - k * 8
            n = int(rr * 6)
            for i in range(n):
                if i % 3 == 0:
                    continue
                t = i / n * math.tau + k * 0.4
                b.put(math.cos(t) * rr, math.sin(t) * rr * 0.8, V[6] if k < 2 else V[5])
            if k == 2:
                _star(b, 12, [V[7], V[7], V[6], V[5]], 4, 111, 1.6, 0, 0)
            fr.append(b)
            continue
        back, front = Buf(), Buf()
        for ri, (rx, ry, tilt) in enumerate(rings):
            ct, st = math.cos(tilt), math.sin(tilt)
            n = 64
            bead = (k / 8.0 + ri * 0.5) % 1.0
            for i in range(n):
                u = i / n
                t = u * math.tau
                x, y = math.cos(t) * rx, math.sin(t) * ry
                X, Y = x * ct - y * st, x * st + y * ct
                is_front = math.sin(t) > 0
                d = abs(((u - bead + 0.5) % 1.0) - 0.5)
                if d < 0.02:
                    col = V[7]
                elif d < 0.06:
                    col = V[6]
                else:
                    col = V[5] if is_front else V[3]
                (front if is_front else back).put(X, Y, col)
        ro = 20 + (1 if k % 4 < 2 else 0)   # 外圈呼吸点线
        for i in range(36):
            if (i + k) % 3:
                continue
            t = i / 36 * math.tau
            back.put(math.cos(t) * ro, math.sin(t) * ro * 0.8, V[2])
        b.p.update(back.p)
        for y in range(-RC - 1, RC + 2):
            for x in range(-RC - 1, RC + 2):
                d = math.hypot(x, y)
                if d <= RC - 0.8:
                    b.put(x, y, V[0] if d < RC - 2 else V[1])
                elif d <= RC + 0.4:
                    a = (math.atan2(y, x) / math.tau * 8 - k) % 8
                    b.put(x, y, V[6] if a < 1.5 else V[5])
        b.put(-2, -3, V[7])
        b.put(-3, -2, V[7])
        b.put(0, RC, ACC[2])
        b.put(-1, RC, ACC[1])
        b.put(1, RC, ACC[1])
        b.p.update(front.p)
        if cast and k == 3:
            _star(b, 8, [V[7], V[6], V[5]], 4, 113, 1.2, 0, 0)
        fr.append(b)
    return fr


def ripple(z):
    """反重力场的空间扭曲（贴地循环 12 帧 = 0.8 秒，原点 = 场心）：两道细波纹从场边往场心收（半径按角度起伏，像空间被拧了一下），
    越往里越亮；场边一圈很暗的稀疏点线标出范围"""
    R = 110.0 * Z[z] * 0.97
    fr = []
    for k in range(12):
        b = Buf()
        n = int(R * 4)
        for i in range(n):
            if i % 7:
                continue
            t = i / n * math.tau
            b.put(math.cos(t) * R, math.sin(t) * R * SQ, V[3])
        for w in range(2):
            u = ((k / 12.0) + w * 0.5) % 1.0
            rr = R * (0.95 - 0.75 * u)
            m = max(24, int(rr * 4.5))
            for i in range(m):
                t = i / m * math.tau
                wob = 1.0 + 0.06 * math.sin(t * 3 + k * 0.5 + w)
                if (i // 3 + w) % 4 == 3:
                    continue
                col = V[2] if u < 0.35 else (V[3] if u < 0.7 else V[4])
                b.put(math.cos(t) * rr * wob, math.sin(t) * rr * wob * SQ, col)
        fr.append(b)
    return fr


def rock_big(var):
    """反重力大碎石（立起层，原点 = 碎石中心）：4 帧缓慢翻转循环（顶面亮阶换边）；黑紫身、顶面一阶亮、底面一排紫光反射"""
    shapes = [[(-7, -1), (-4, -5), (2, -6), (7, -2), (6, 3), (0, 5), (-5, 4)],
              [(-6, -3), (-1, -6), (5, -5), (8, 0), (4, 5), (-3, 5), (-7, 2)]][var % 2]
    fr = []
    xs = [p[0] for p in shapes]
    ys = [p[1] for p in shapes]
    for k in range(4):
        b = Buf()
        for y in range(min(ys), max(ys) + 1):
            for x in range(min(xs), max(xs) + 1):
                if not _inside(x, y, shapes):
                    continue
                top = not _inside(x, y - 1, shapes)
                bot = not _inside(x, y + 1, shapes)
                edge = not _inside(x - 1, y, shapes) or not _inside(x + 1, y, shapes)
                col = V[1]
                if top:
                    col = V[3] if ((x + k) % 4) < 2 else V[2]
                elif bot:
                    col = V[4]
                elif edge:
                    col = V[0]
                elif hsh(x, y, var) % 7 == 0:
                    col = V[2]
                b.put(x, y, col)
        fr.append(b)
    return fr


def rock_shadow(w):
    b = Buf()
    for x in range(-w, w + 1):
        b.put(x, 0, SHADOW)
    for x in range(-w + 1, w):
        b.put(x, 1, SHADOW)
    return [b]


def rock_state(t, R, c=(0.0, 0.0)):
    """反重力大碎石的时间表（游戏 fx_pxplane_ang._rock_list 同算法）：场开着第 t 秒时在场的碎石，每 0.6 秒生一块、每块活 2 秒（同屏 ≤ 4）。
    返回 [(变体, 地面点 x, y, 高度, 影子半宽)]；位置绕场心缓慢转、托起 → 悬停微浮 → 落回"""
    out = []
    n_now = int(math.floor(t / 0.6))
    for n in range(max(0, n_now - 3), n_now + 1):
        age = t - n * 0.6
        if age < 0 or age >= 2.0:
            continue
        a0 = hf(n, 1, 7) * math.tau
        rr = R * (0.35 + 0.45 * hf(n, 2, 13))
        a = a0 + 0.55 * age
        if age < 0.4:
            h = 24 * ease_out(age / 0.4)
        elif age < 1.6:
            h = 24 + (2 if (int(age * 15) // 3) % 2 else 0)
        else:
            h = 24 * (1 - (age - 1.6) / 0.4) ** 2
        gx, gy = c[0] + math.cos(a) * rr, c[1] + math.sin(a) * rr * SQ
        sw = 6 if h < 8 else (4 if h < 18 else 3)
        out.append((n % 2, gx, gy, h, sw))
    return out
