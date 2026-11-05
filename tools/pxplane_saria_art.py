"""塞雷娅转平面（docs/269）的像素图形：盾击 / 钙晶 / 治疗帧条，以及运行时弹体（注射器、碎晶片）、阻挡圈、晶柱墙脚的同一套画法（Python 版）。
tools/pxplane_bake_saria.py 用它烤帧条（game/art/fx/pxp/pxp_sa_*.png + game/data/pxp_saria.json），
tools/pxplane_gif_saria.py 用它拼送审 GIF；运行时件在游戏里由 fx_pxplane_sa.gd 逐格画，算法与本文件 syringe() / shard() / guard_ring() 一一对应，改一边要改另一边。
单位：美术像素（游戏里 1 美术像素 = g.PX = 2 世界像素）。全部确定性（不用随机数，抖动用坐标哈希）。

配色（原作 demkni_* 参照：普攻命中是暖白细芒、治疗是绿色、钙质化是暗色网点区 + 橙色裂纹）：
- 晶体 AMB：琥珀 → 白（钙化结晶，她的招牌；用户「钙化结晶用琥珀到白的配色，和治疗区分开」）；
- 冷白 CAL：钙质晶簇的冷白晶身（琥珀描边），和琥珀晶柱分开；
- 冲击 WH：暖白（盾击冲击芒，原作 attack_01_hit）；
- 治疗 HEAL：医疗绿（原作 skill_01 / skill_02）。不用红。"""
import math

AMB = ["#2a1606", "#5a300c", "#9a5a16", "#d88a2a", "#f5b860", "#ffe2b0", "#ffffff"]
CAL = ["#2c241c", "#5e5040", "#9a8a70", "#d0c4a8", "#efe6d2", "#fffaf0", "#ffffff"]
WH = ["#2e2820", "#6a5c48", "#b4a284", "#e6d8bc", "#fff3de", "#fffaf2", "#ffffff"]
HEAL = ["#06200e", "#0c4420", "#16803a", "#2cc060", "#78e89a", "#c8f8d6", "#ffffff"]
DUST = ["#24201c", "#3e3830", "#5e564a", "#857a68"]
SHADOW = "#141210"
SQ = 0.72   # 贴地压扁（combat.GROUND_Y）
WAIST = 5   # 腰高（美术像素；判定原点 脚底 + (0, −10) 世界像素）

# 尺寸档（美术像素）：判定半径 ÷ 2，范围成长放大时游戏挑最近的一档（只整数放大，不做小数缩放）
BASH_R = [40, 49, 58, 68]      # 普攻盾击（reach 98 世界像素 × op_range）
SUIT_R = [55, 66]              # 精二满格环冲（suit_r 110 × op_range）
SHAT2_R = [45, 54]             # 碎晶·崩落（orb_r × 1.3 = 91 × op_range）
FIELD_R = 90                   # 钙质化区域（s3_r 180）


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

    def line(self, x0, y0, x1, y1, c, keep=False):
        n = max(1, int(math.ceil(max(abs(x1 - x0), abs(y1 - y0)))))
        for i in range(n + 1):
            u = i / n
            (self.put_if_empty if keep else self.put)(x0 + (x1 - x0) * u, y0 + (y1 - y0) * u, c)

    def merge(self, o, keep=False):
        for k, c in o.p.items():
            if keep:
                self.p.setdefault(k, c)
            else:
                self.p[k] = c
        return self


def _gpt(r, a, lift=0.0):
    """地面极坐标 → 画面（压扁 SQ），lift = 往上抬的高度"""
    return (r * math.cos(a), r * math.sin(a) * SQ - lift)


def _spike(b, o, d, L, cols, keep=False):
    for s in range(L):
        c = cols[min(s, len(cols) - 1)]
        (b.put_if_empty if keep else b.put)(o[0] + d[0] * s, o[1] + d[1] * s, c)


def _cross(b, x, y, c, edge=None, big=False):
    """医疗「+」：小 3×3、大 5×5（大号带暗边）"""
    if big:
        for i in range(-2, 3):
            b.put(x + i, y, c)
            b.put(x, y + i, c)
        if edge:
            for (dx, dy) in ((-2, -1), (-2, 1), (2, -1), (2, 1), (-1, -2), (1, -2), (-1, 2), (1, 2)):
                b.put_if_empty(x + dx, y + dy, edge)
    else:
        for (dx, dy) in ((0, 0), (1, 0), (-1, 0), (0, 1), (0, -1)):
            b.put(x + dx, y + dy, c)


# ================================================================ 晶体造型（琥珀晶柱 / 冷白晶簇 / 环绕钙晶 / 晶刺）

def prism(b, cx, base, w, h, ramp, lean=0.0, crack=0, glint=-1, top_hot=False):
    """竖直六棱晶柱（侧视、尖顶）：左面受光、右面暗、中脊亮线、外缘暗描边；底边在 base。
    lean：每升高 1 像素横移；crack：裂纹数（碎裂前）；glint：沿左棱往上走的高光行（-1 = 无）"""
    C = ramp
    hw = w / 2.0
    tip = max(3, int(w * 0.6))
    for y in range(h):
        yy = base - y
        k = 1.0 if y < h - tip else (h - y) / tip
        half = max(0.5, hw * k)
        xc = cx + lean * y
        x0, x1 = int(round(xc - half)), int(round(xc + half))
        for x in range(x0, x1 + 1):
            u = (x - (xc - half)) / max(1.0, 2 * half)
            if x == x0 or x == x1:
                c = C[1]
            elif u < 0.38:
                c = C[4] if y > 1 else C[3]
            elif u < 0.55:
                c = C[5]
            else:
                c = C[3] if u < 0.8 else C[2]
            b.put(x, yy, c)
        if y >= h - tip and y == h - 1:
            b.put(xc, yy, C[1])
    if top_hot:
        for y in range(h - tip, h):
            b.put(cx + lean * y, base - y, C[6])
    if glint >= 0 and glint < h - 2:
        for dy in (0, 1):
            y = glint + dy
            xc = cx + lean * y
            k = 1.0 if y < h - tip else (h - y) / tip
            b.put(int(round(xc - hw * k)) + 1, base - y, C[6])
    for i in range(crack):
        y0 = int(h * (0.25 + 0.22 * i))
        xs = cx + lean * y0
        for s in range(max(2, int(w * 0.7))):
            x = xs - hw * 0.6 + s
            y = y0 + (1 if (s + i) % 3 == 0 else 0) + (s // 3)
            b.put(x + lean * y, base - y, C[6] if s % 2 == 0 else C[5])


def diamond(b, cx, cy, w, h, ramp, glint=0):
    """菱形钙晶（环绕钙晶 / 碎片）：上半亮、下半暗，中线白"""
    C = ramp
    hh = h / 2.0
    for y in range(-int(hh), int(hh) + 1):
        k = 1.0 - abs(y) / (hh + 0.5)
        half = max(0, int(round(w / 2.0 * k)))
        for x in range(-half, half + 1):
            if abs(x) == half:
                c = C[1] if y > 0 else C[2]
            elif y < 0:
                c = C[5] if x < 0 else C[4]
            else:
                c = C[3] if x < 0 else C[2]
            b.put(cx + x, cy + y, c)
    for y in range(-int(hh) + 1, int(hh)):
        b.put(cx, cy + y, C[5] if y < 0 else C[4])
    gy = -int(hh) + 1 + (glint % max(1, int(h) - 1))
    b.put(cx - 1, cy + gy, C[6])


def cluster(b, cx, base, ramp, k=1.0, v=0, crack=0, glint=-1):
    """冷白钙质晶簇：主晶 + 左右两根斜的小晶（v 换一种排法）"""
    hs = [int(20 * k), int(12 * k), int(9 * k)]
    if v == 1:
        hs = [int(17 * k), int(14 * k), int(7 * k)]
    prism(b, cx - 4, base, 5, max(2, hs[1]), ramp, lean=-0.35, crack=min(crack, 1), glint=-1)
    prism(b, cx + 4, base + 1, 4, max(2, hs[2]), ramp, lean=0.4, crack=0, glint=-1)
    prism(b, cx, base + 1, 7, max(2, hs[0]), ramp, lean=0.08, crack=crack, glint=glint)


def base_shadow(b, cx, base, rx, keep=True):
    for x in range(-rx, rx + 1):
        (b.put_if_empty if keep else b.put)(cx + x, base + 1, SHADOW)
    for x in range(-rx + 2, rx - 1):
        (b.put_if_empty if keep else b.put)(cx + x, base + 2, SHADOW)


def shards_fly(b, cx, cy, n, r, ramp, seed, down=0.0, size=2):
    """一圈往外飞的碎晶（2 像素小菱）"""
    for i in range(n):
        a = (i / n) * math.tau + (hf(i, seed, 3) - 0.5) * 1.6
        rr = r * (0.45 + 0.8 * hf(i, seed, 5))
        x = cx + math.cos(a) * rr
        y = cy + math.sin(a) * rr * 0.8 + down * (0.6 + 0.6 * hf(i, seed, 7))
        b.put(x, y, ramp[5])
        if size >= 2:
            b.put(x + 1, y, ramp[3])
            b.put(x, y + 1, ramp[2])


# ================================================================ 普攻：盾击（立起层：盾面冲击；贴地层：推地擦痕）

def bash_up(R, tier, deg):
    """持盾出拳（原点 = 脚底，判定扇形 R / 半角 1.1 rad）：腰高一道**钝头盾面冲击**（压扁的厚弧，两头方头不收尖），
    第 0 拍从 0.5R 冲出、第 1 拍到 0.85R 最亮，之后整道变薄变暗、断开；身后 3 道速度纹。精一起盾面 +1 厚、外缘一排琥珀晶点"""
    a = math.radians(deg)
    half = 1.1 * 0.82
    fr = []
    spec = [(0.5, 5, 6), (0.85, 6, 6), (0.9, 4, 5), (0.94, 2, 4), (0.96, 1, 3)]
    for k, (ru, th, hot) in enumerate(spec):
        b = Buf()
        rr = R * ru
        thk = th + (1 if tier >= 1 and k <= 2 else 0)
        n = max(10, int(rr * half * 2))
        for i in range(n + 1):
            u = i / n
            t = -half + 2 * half * u
            edge = min(u, 1 - u)
            if k >= 3 and hsh(i, k, 11) % 3 == 0:
                continue
            if k == 4 and i % 2:
                continue
            for j in range(thk):
                r2 = rr - j
                x, y = _gpt(r2, a + t, WAIST)
                if j == 0:
                    c = WH[hot] if edge > 0.06 else WH[hot - 1]
                elif j == thk - 1:
                    c = AMB[1]
                elif k <= 1:   # 盾面：白 → 奶白 → 琥珀（实心，不是细线）
                    c = WH[5] if j == 1 else WH[4] if j == 2 else AMB[4] if j == thk - 2 else AMB[5]
                else:
                    c = AMB[4] if j == 1 else AMB[3]
                b.put(x, y, c)
            if tier >= 1 and k in (1, 2) and i % 4 == 2:   # 精一：外缘琥珀晶点（钙化拳）
                x, y = _gpt(rr + 1.5, a + t, WAIST)
                b.put(x, y, AMB[5] if k == 1 else AMB[4])
        if k <= 1:   # 速度纹：身后 3 道
            for s in (-0.55, 0.0, 0.55):
                t = s * half
                r0, r1 = rr * (0.25 if k == 0 else 0.45), rr * (0.7 if k == 0 else 0.8)
                for q in range(int(r0), int(r1)):
                    if (q + int(s * 7)) % 4 == 3:
                        continue
                    x, y = _gpt(q, a + t, WAIST)
                    b.put_if_empty(x, y, WH[3] if k == 0 else WH[2])
        if k == 0:   # 出手第 0 拍：盾心一团热白
            cx, cy = _gpt(R * 0.3, a, WAIST)
            for dx in range(-2, 3):
                for dy in range(-1, 2):
                    if abs(dx) + abs(dy) <= 2:
                        b.put(cx + dx, cy + dy, WH[6])
        fr.append(b)
    return fr


def bash_gd(R, deg):
    """推地擦痕（贴地）：盾面投影的暗弧 + 两头各一小团尘"""
    a = math.radians(deg)
    half = 1.1 * 0.8
    fr = []
    for k, ru in enumerate([0.5, 0.85, 0.9, 0.93]):
        b = Buf()
        rr = R * ru
        n = max(10, int(rr * half * 2))
        for i in range(n + 1):
            u = i / n
            if k >= 2 and hsh(i, k, 13) % 2:
                continue
            x, y = _gpt(rr - 1, a - half + 2 * half * u)
            b.put(x, y, SHADOW)
            if k <= 1 and 0.15 < u < 0.85:
                b.put(x, y - 1, SHADOW)
        for s in (-1, 1):   # 两头尘
            x, y = _gpt(rr, a + s * half)
            for q in range(3 + k):
                dx = (hsh(q, k, 17 + s) % 5) - 2
                dy = -(q // 2) - k
                b.put(x + dx, y + dy, DUST[3 - min(3, k)] if q % 2 == 0 else DUST[2])
        fr.append(b)
    return fr


def hit_spikes(deg, calc=False, amber=False):
    """命中（立起层，原点 = 命中点）：原作 attack_01_hit 的暖白细芒——5 道 1 像素硬芒（多数顺着出拳方向往外 ±70°），
    第 0 拍白芯、第 1 拍外半段脱开、第 2 拍只剩尖端几点。calc（精一钙化拳）：再崩出 3 粒琥珀碎晶；amber（钙质化空手拳）：芒换琥珀"""
    a = math.radians(deg)
    C = AMB if amber else WH
    fr = [Buf() for _ in range(3)]
    for i in range(5):
        if i < 4:
            ang = a + (-1.2 + 2.4 * ((i * 0.618 + hf(i, 3, 1) * 0.15) % 1.0))
        else:
            ang = a + math.pi + 0.5
        sd = (math.cos(ang), math.sin(ang))
        L = [9, 7, 8, 6, 4][i]
        _spike(fr[0], (sd[0] * 2, sd[1] * 2), sd, L, [C[6], C[6], C[5], C[5], C[4], C[3]])
        for s in range(L // 2, L + 2):
            fr[1].put(sd[0] * (s + 2), sd[1] * (s + 2), C[4] if s < L else C[3])
        fr[2].put(sd[0] * (L + 3), sd[1] * (L + 3) + 1, C[3])
    for x in range(-1, 2):
        for y in range(-1, 2):
            fr[0].put(x, y, C[6] if abs(x) + abs(y) <= 1 else C[5])
    fr[1].put(0, 0, C[4])
    if calc:   # 琥珀碎晶往外崩、受重力
        for j in range(3):
            ang = a + (-0.8 + 0.8 * j)
            sd = (math.cos(ang), math.sin(ang))
            for k, (dist, dy) in enumerate([(3, -2), (6, -2), (8, 1)]):
                x, y = sd[0] * dist, sd[1] * dist + dy
                fr[k].put(x, y, AMB[5] if k == 0 else AMB[4])
                fr[k].put(x + 1, y, AMB[3])
                if k < 2:
                    fr[k].put(x, y + 1, AMB[2])
    return fr


# ================================================================ 钙质化期间的空手拳：碎晶喷射（盾放在地上，拳头把晶片往前打出去）

def cbash_up(R, deg):
    """钙质化期间出拳（原点 = 脚底）：拳头前一点热白 + 7 枚琥珀晶片顺扇形往前喷出（掰下晶柱打出去的意象），
    飞到 0.95R 内、下坠，最后一拍碎成点落地"""
    a = math.radians(deg)
    half = 1.1 * 0.75
    fr = [Buf() for _ in range(5)]
    cx, cy = _gpt(9, a, WAIST + 1)
    for dx in range(-3, 4):
        for dy in range(-3, 4):
            if abs(dx) + abs(dy) <= 3:
                fr[0].put(cx + dx, cy + dy, AMB[6] if abs(dx) + abs(dy) <= 1 else AMB[5] if abs(dx) + abs(dy) <= 2 else AMB[4])
            if abs(dx) + abs(dy) <= 1:
                fr[1].put(cx + dx, cy + dy, AMB[5] if (dx, dy) == (0, 0) else AMB[3])
    for i in range(9):
        t = -half + 2 * half * ((i + 0.5) / 9) + (hf(i, 9, 1) - 0.5) * 0.14
        d = (math.cos(a + t), math.sin(a + t) * SQ)
        for k, ru in enumerate([0.3, 0.6, 0.85, 0.95, 0.95]):
            r = R * ru * (0.85 + 0.15 * hf(i, 9, 2))
            drop = [0, 0.5, 1.5, 3.5, 5][k] * (0.7 + 0.6 * hf(i, 9, 3))
            x, y = d[0] * r, d[1] * r - WAIST - 1 + drop
            if k <= 2:   # 晶片：2 格宽的尖菱——亮尖 + 琥珀身（下侧暗一阶）+ 暗尾
                nx, ny = -d[1], d[0]
                fr[k].put(x, y, AMB[6])
                fr[k].put(x - d[0] * 1.2, y - d[1] * 1.2, AMB[5] if k < 2 else AMB[4])
                fr[k].put(x - d[0] * 1.2 + nx, y - d[1] * 1.2 + ny + 0.6, AMB[3])
                fr[k].put(x - d[0] * 2.4, y - d[1] * 2.4, AMB[4] if k < 2 else AMB[3])
                fr[k].put(x - d[0] * 2.4 + nx, y - d[1] * 2.4 + ny + 0.6, AMB[2])
                fr[k].put(x - d[0] * 3.6, y - d[1] * 3.6, AMB[2])
                if k == 0:
                    fr[k].put(x - d[0] * 4.8, y - d[1] * 4.8, AMB[1])
            elif k == 3:
                fr[k].put(x, y, AMB[4])
                fr[k].put(x - d[0], y - d[1], AMB[2])
            else:
                fr[k].put(x, y + 1, AMB[2])
    return fr


# ================================================================ 精二：满格环冲（贴地冲击环 + 6 道盾冲）+ 晶柱环

def suit_gd(R):
    """满格冲击（贴地，原点 = 脚底）：一圈往外推的冲击环（第 0 拍热白 → 琥珀 → 断开）+ 6 道往外的推地楔痕"""
    fr = []
    spec = [(0.4, WH[6], WH[4]), (0.75, WH[5], AMB[4]), (0.95, AMB[4], AMB[2]), (1.0, AMB[3], AMB[1]), (1.0, AMB[2], AMB[1])]
    for k, (ru, c0, c1) in enumerate(spec):
        b = Buf()
        r = R * ru
        n = int(r * 6.4)
        for i in range(n):
            t = i / n * math.tau
            if k >= 3 and hsh(i, k, 19) % (2 if k == 3 else 3) != 0:
                continue
            x, y = _gpt(r, t)
            b.put(x, y, c0)
            if k <= 2:
                x2, y2 = _gpt(r - 2, t)
                b.put_if_empty(x2, y2, c1)
        if k <= 2:
            for j in range(6):
                t = j * math.tau / 6 + 0.26
                for q in range(int(r * 0.45), int(r * 0.9)):
                    if q % 3 == 2:
                        continue
                    x, y = _gpt(q, t)
                    b.put_if_empty(x, y, WH[4] if k == 0 else AMB[3])
        fr.append(b)
    return fr


def suit_up():
    """满格冲击（立起，原点 = 脚底）：身前一团热白爆闪（两拍）+ 一圈往上蹦的琥珀碎晶"""
    fr = [Buf() for _ in range(4)]
    cy = -14
    for x in range(-4, 5):
        for y in range(-4, 5):
            d = abs(x) + abs(y)
            if d <= 5:
                fr[0].put(x, cy + y, WH[6] if d <= 3 else WH[5])
            if d <= 2:
                fr[1].put(x, cy + y, WH[5] if d <= 1 else AMB[4])
    for i in range(8):
        a = i / 8 * math.tau + 0.2
        for k, (r, dy) in enumerate([(6, -2), (11, -3), (14, 0), (16, 4)]):
            x, y = math.cos(a) * r, cy + math.sin(a) * r * 0.6 + dy
            fr[k].put_if_empty(x, y, AMB[5] if k < 2 else AMB[3])
            if k < 2:
                fr[k].put_if_empty(x + 1, y, AMB[3])
    return fr


def crystal_prism(b, cx, base, w, h, lean=0.0, crack=0, glint=-1, top_hot=False):
    """琥珀晶（晶柱用）：暗琥珀晶芯 + 左棱白亮线 + 右棱琥珀亮线 + 斜切顶面（亮一阶），不平涂——读成透光的晶体而不是一块橙色"""
    hw = w / 2.0
    tip = max(3, int(w * 0.8))
    for y in range(h):
        yy = base - y
        k = 1.0 if y < h - tip else (h - y) / tip
        xc = cx + lean * y
        half = max(0.5, hw * k)
        x0, x1 = int(round(xc - half)), int(round(xc + half))
        for x in range(x0, x1 + 1):
            u = (x - x0) / max(1, x1 - x0)
            if x == x0:
                c = AMB[5] if y > 1 else AMB[3]
            elif x == x1:
                c = AMB[1]
            elif x == x0 + 1:
                c = AMB[4]
            elif u > 0.62:
                c = AMB[3] if x == x1 - 1 else AMB[2]
            else:
                c = AMB[2] if (y + x) % 5 else AMB[3]   # 晶芯暗、偶有一点内反光
            if y >= h - tip:   # 斜切顶面：亮一阶
                c = AMB[5] if u < 0.5 else AMB[4]
            b.put(x, yy, c)
    if top_hot:
        for y in range(h - tip, h):
            b.put(cx + lean * y, base - y, AMB[6])
    if glint >= 0 and glint < h - tip:
        for dy in (0, 1):
            y = glint + dy
            b.put(int(round(cx + lean * y - hw)), base - y, AMB[6])
    for i in range(crack):
        y0 = int(h * (0.3 + 0.25 * i))
        for s2 in range(max(2, int(w * 0.8))):
            y = y0 + s2 // 2
            b.put(cx - hw + 1 + s2 + lean * y, base - y, AMB[6] if s2 % 2 == 0 else AMB[5])


def amber_cluster(b, base, big, v, crack=0, glint=-1, top_hot=False, hk=1.0):
    """晶柱 = 琥珀晶簇：主晶 + 两根斜的小晶，v 决定高矮 / 倾斜（相邻晶柱不一样）"""
    H0 = 20 if big else 16
    hs = [(H0, 0.06, 7), (int(H0 * 0.6), -0.32, 5), (int(H0 * 0.45), 0.36, 4)]
    if v == 1:
        hs = [(int(H0 * 0.9), -0.08, 7), (int(H0 * 0.7), -0.42, 5), (int(H0 * 0.4), 0.45, 4)]
    elif v == 2:
        hs = [(int(H0 * 1.05), 0.12, 6), (int(H0 * 0.5), -0.36, 5), (int(H0 * 0.55), 0.28, 4)]
    if not big:
        hs = [(h, l, max(3, w - 1)) for (h, l, w) in hs]
    xs = [0, -4, 4]
    for i in (1, 2, 0):
        h, l, w = hs[i]
        crystal_prism(b, xs[i], base + (0 if i == 0 else 1), w, max(2, int(h * hk)), lean=l, crack=crack if i == 0 else 0,
                      glint=glint if i == 0 else -1, top_hot=top_hot and i == 0)


def pillar_frames(big=True, v=0):
    """晶柱（立起，原点 = 底边中点）：琥珀晶簇。rise 4 拍（破土冲出 + 顶端热白 + 回落）、idle 6 拍循环（高光沿主晶左棱往上走）、
    break 5 拍（主晶裂开 → 崩成碎晶飞散 → 落地成碎点）。11-05 用户「金色柱子是不是有点奇怪」：原来是一根平涂橙色尖柱、每根一样，改成晶簇"""
    rx = 8 if big else 7
    rise = []
    for k, hk in enumerate([0.3, 0.8, 1.08, 1.0]):
        b = Buf()
        base_shadow(b, 0, 0, rx)
        amber_cluster(b, 0, big, v, top_hot=k <= 2, hk=hk)
        if k <= 1:
            for s in (-1, 1):
                for q in range(3 + k * 2):
                    b.put(s * (rx + 1 + q), -((q * 3 + k) % 4), DUST[3] if q % 2 == 0 else DUST[2])
        rise.append(b)
    idle = []
    for k in range(6):
        b = Buf()
        base_shadow(b, 0, 0, rx)
        amber_cluster(b, 0, big, v, glint=k * 3)
        idle.append(b)
    brk = []
    for k in range(5):
        b = Buf()
        if k == 0:
            base_shadow(b, 0, 0, rx)
            amber_cluster(b, 0, big, v, crack=2)
        else:
            shards_fly(b, 0, -9, 8, 4 + k * 4, AMB, 31 + v, down=k * k * 0.9)
            shards_fly(b, 0, -4, 4, 3 + k * 3, CAL, 33 + v, down=k * k * 0.7)
            for q in range(k + 2):
                b.put(-5 + q * 3, 1, AMB[2] if q % 2 else DUST[2])
        brk.append(b)
    return rise, idle, brk


def cluster_frames(v=0):
    """钙质晶簇（S3 晶柱槽，立起，原点 = 底边中点）：grow 6 拍（0.4 秒）、idle 6 拍循环、break 5 拍（0.3 秒）"""
    grow = []
    for k, hk in enumerate([0.2, 0.45, 0.75, 1.05, 1.0, 1.0]):
        b = Buf()
        base_shadow(b, 0, 0, 8)
        cluster(b, 0, 0, CAL, k=hk, v=v)
        if k <= 2:
            for s in (-1, 1):
                for q in range(2 + k):
                    b.put(s * (8 + q), -((q * 2 + k) % 3), DUST[3] if q % 2 == 0 else DUST[2])
        if k == 3:   # 长成那一拍：琥珀描边亮一下
            for (x, y), c in list(b.p.items()):
                if c == CAL[1]:
                    b.p[(x, y)] = AMB[4]
        grow.append(b)
    idle = []
    for k in range(6):
        b = Buf()
        base_shadow(b, 0, 0, 8)
        cluster(b, 0, 0, CAL, v=v, glint=k * 3)
        for (x, y), c in list(b.p.items()):   # 琥珀描边（冷白晶身 + 琥珀边）
            if c == CAL[1]:
                b.p[(x, y)] = AMB[2]
        idle.append(b)
    brk = []
    for k in range(5):
        b = Buf()
        if k == 0:
            base_shadow(b, 0, 0, 8)
            cluster(b, 0, 0, CAL, v=v, crack=2)
        else:
            shards_fly(b, 0, -9, 8, 4 + k * 4, CAL, 41 + v, down=k * k * 0.8)
            shards_fly(b, 0, -5, 4, 3 + k * 3, AMB, 43 + v, down=k * k * 0.7)
            for q in range(k + 2):
                b.put(-6 + q * 3, 1, DUST[2])
        brk.append(b)
    return grow, idle, brk


# ================================================================ S3 钙质化：起手裂纹 + 区域边

def s3cast_gd():
    """钙质化起手（贴地，原点 = 队长脚底）：原作 skill_03 的橙色裂纹——9 道分叉裂纹从脚下往外裂（热白芯 → 琥珀 → 冷成暗琥珀、断成一节节），
    外圈一道断续环推到区域边（R = 90）。8 拍"""
    R = FIELD_R
    cracks = []
    for i in range(9):
        a0 = i / 9 * math.tau + hf(i, 1, 1) * 0.5
        L = R * (0.38 + 0.25 * hf(i, 1, 2))
        pts = []
        x, y, a = 0.0, 0.0, a0
        s = 0
        while s < L:
            pts.append((x, y * SQ, s / L))
            a += (hf(i, s, 3) - 0.5) * 0.55
            x += math.cos(a)
            y += math.sin(a)
            s += 1
        fk = int(L * (0.45 + 0.2 * hf(i, 1, 4)))   # 一道分叉
        br = []
        if fk < len(pts):
            bx, by = pts[fk][0], pts[fk][1] / SQ
            ba = a0 + (0.6 if i % 2 else -0.6)
            for q in range(int(L * 0.35)):
                br.append((bx, by * SQ, (fk + q) / L))
                ba += (hf(i, q, 5) - 0.5) * 0.5
                bx += math.cos(ba)
                by += math.sin(ba)
        cracks.append(pts + br)
    fr = []
    for k in range(8):
        b = Buf()
        grow = [0.35, 0.75, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0][k]
        for i, pts in enumerate(cracks):
            for j, (x, y, u) in enumerate(pts):
                if u > grow:
                    continue
                if k >= 4 and hsh(j, i, k) % (6 - min(4, k - 3)) == 0:
                    continue
                if k >= 6 and j % 2:
                    continue
                if k <= 1:
                    c = AMB[6] if u > grow - 0.2 else AMB[5]
                elif k <= 3:
                    c = AMB[5] if u < 0.25 and k == 2 else AMB[4] if u < 0.6 else AMB[3]
                else:
                    c = AMB[3] if k == 4 else AMB[2] if k <= 5 else AMB[1]
                b.put(x, y, c)
                if k <= 3 and u < 0.4:
                    b.put_if_empty(x, y + 1, AMB[1])
        rr = R * [0.25, 0.55, 0.85, 1.0, 1.0, 1.0, 0, 0][k]
        if rr > 0:
            n = int(rr * 6.4)
            for q in range(n):
                t = q / n * math.tau
                if hsh(q, k, 23) % (2 if k < 4 else 3) == 0:
                    continue
                x, y = _gpt(rr, t)
                b.put(x, y, AMB[5] if k <= 2 else AMB[3] if k <= 3 else AMB[2])
        if k <= 1:
            for x in range(-5, 6):
                for y in range(-2, 3):
                    if abs(x) / 5 + abs(y) / 2.5 <= 1:
                        b.put(x, y, AMB[6] if k == 0 else AMB[4])
        fr.append(b)
    return fr


def s3cast_up():
    """钙质化起手（立起）：脚下崩起一圈琥珀晶片往上飞、落下（4 拍）"""
    fr = [Buf() for _ in range(5)]
    for i in range(8):
        a = i / 8 * math.tau + 0.4
        for k in range(5):
            r = 4 + k * 5
            h = [4, 14, 20, 18, 10][k] * (0.7 + 0.5 * hf(i, 2, 1))
            x, y = math.cos(a) * r, math.sin(a) * r * SQ - h
            fr[k].put(x, y, AMB[6] if k < 2 else AMB[4])
            fr[k].put(x, y + 1, AMB[3] if k < 3 else AMB[2])
            if k < 2:
                fr[k].put(x, y + 2, AMB[2])
    return fr


def field_gd():
    """钙质化区域（贴地，循环 8 拍，原点 = 队长脚底，R = 90）：只画边——断续琥珀边线 + 内侧 2 格暗琥珀内边（颜色阶代替透明度）
    + 内圈一层稀疏网点（原作暗色网点区），网点逐拍闪烁换位"""
    R = FIELD_R
    fr = []
    for k in range(8):
        b = Buf()
        n = int(R * 6.4)
        for q in range(n):
            t = q / n * math.tau
            seg = int((t + k * 0.06) / (math.tau / 22))
            if seg % 5 == 4:
                continue
            x, y = _gpt(R, t)
            b.put(x, y, AMB[4] if (q + k * 3) % 29 != 0 else AMB[6])
            x2, y2 = _gpt(R - 1.5, t)
            b.put_if_empty(x2, y2, AMB[1])
            x3, y3 = _gpt(R - 3, t)
            b.put_if_empty(x3, y3, AMB[0])
        for r in (R - 9, R - 17):   # 网点：两圈稀疏亮点
            m = int(r * 6.4 / 9)
            for q in range(m):
                if (q + k + (1 if r == R - 17 else 0)) % 3 != 0:
                    continue
                t = q / m * math.tau + (0.1 if r == R - 17 else 0)
                x, y = _gpt(r, t)
                b.put(x, y, AMB[2] if (q + k) % 2 else AMB[3])
        fr.append(b)
    return fr


# ================================================================ 碎晶 / 晶簇 / 崩落 / 环绕钙晶

def orb_frames():
    """环绕钙晶（立起，循环 6 拍，原点 = 晶心）：琥珀菱晶，高光沿左棱往下走"""
    fr = []
    for k in range(6):
        b = Buf()
        diamond(b, 0, 0, 7, 11, AMB, glint=k * 2)
        fr.append(b)
    return fr


def orb_break():
    """钙晶击碎（立起，原点 = 晶心）：第 0 拍热白闪 + 裂开，之后 6 粒碎晶往外飞、下坠"""
    fr = [Buf() for _ in range(4)]
    diamond(fr[0], 0, 0, 7, 11, AMB)
    for (x, y) in ((0, -4), (-1, -2), (1, 0), (0, 2), (-1, 3)):
        fr[0].put(x, y, AMB[6])
    for y in range(-2, 3):
        fr[0].put(-3, y, AMB[6])
        fr[0].put(3, y, AMB[6])
    for k in range(1, 4):
        shards_fly(fr[k], 0, 0, 6, 3 + k * 4, AMB, 51, down=k * k * 1.0)
    return fr


def chip_up():
    """碎晶 / 钙晶命中（立起，原点 = 命中点）：一点琥珀热白 + 4 粒小碎晶崩开下坠（4 拍）"""
    fr = [Buf() for _ in range(4)]
    for x in range(-1, 2):
        for y in range(-1, 2):
            if abs(x) + abs(y) <= 1:
                fr[0].put(x, y, AMB[6])
    for k in range(4):
        for i in range(4):
            a = i / 4 * math.tau + 0.6
            r = 2 + k * 2.5
            x, y = math.cos(a) * r, math.sin(a) * r * 0.8 - 1 + k * k * 0.6
            fr[k].put_if_empty(x, y, AMB[5] if k < 2 else AMB[3])
    return fr


def ring_spikes_up(R, n, h0, seed):
    """一圈晶刺破土（立起，原点 = 圆心脚底）：碎晶·崩落 / 晶簇爆开用。n 根小晶刺在 0.55R → 0.9R 处依次冒出、碎掉"""
    fr = []
    for k in range(5):
        b = Buf()
        for i in range(n):
            a = i / n * math.tau + hf(i, seed, 1) * 0.4
            r = R * (0.55 + 0.35 * min(1.0, k / 2.0)) * (0.9 + 0.15 * hf(i, seed, 2))
            x, y = _gpt(r, a)
            hk = [0.4, 1.0, 0.9, 0.5, 0.0][k]
            hh = int(h0 * hk * (0.7 + 0.5 * hf(i, seed, 3)))
            if hh >= 2:
                crystal_prism(b, x, y, 3, hh, lean=math.cos(a) * 0.25, top_hot=k == 1)
            elif k == 4:
                b.put(x, y, AMB[2])
                b.put(x + 1, y - 1, AMB[3])
            if k == 3:
                b.put(x + math.cos(a) * 3, y - 2, AMB[4])
        fr.append(b)
    return fr


def ring_dust_gd(R, seed):
    """贴地：一圈往外的碎晶尘痕（4 拍，断续、越来越稀）"""
    fr = []
    for k in range(4):
        b = Buf()
        r = R * (0.6 + 0.12 * k)
        n = int(r * 6.4)
        for q in range(n):
            if hsh(q, seed, k) % (2 + k) != 0:
                continue
            t = q / n * math.tau
            x, y = _gpt(r, t)
            b.put(x, y, AMB[3] if k == 0 else AMB[2] if k < 3 else AMB[1])
        fr.append(b)
    return fr


def qspike(tier, v):
    """后期剑气「晶刺地波」的一根晶刺（立起，原点 = 底边中点）：破土 → 立住 → 裂 → 碎成点。精一起高一档 + 根部琥珀碎屑，精二顶端热白"""
    h = [8, 11, 14][tier]
    lean = 0.18 if v == 0 else -0.18
    fr = []
    for k, hk in enumerate([0.35, 1.0, 1.0, 0.8, 0.0]):
        b = Buf()
        if hk > 0:
            base_shadow(b, 0, 0, 2)
            crystal_prism(b, 0, 0, 4 if tier < 2 else 5, max(2, int(h * hk)), lean=lean, crack=1 if k == 3 else 0, top_hot=(k <= 1 and tier >= 2) or k == 0)
        else:
            for q in range(3):
                b.put(-2 + q * 2, 0, AMB[2] if q != 1 else AMB[3])
        if tier >= 1 and k in (1, 2):
            b.put(-3, -1 - k, AMB[4])
            b.put(3, -2 + k, AMB[3])
        fr.append(b)
    return fr


def qcrack_gd(L, deg):
    """剑气地波身后的一道地裂（贴地，原点 = 出手点，长 L）：琥珀芯冷成暗色（6 拍）"""
    a = math.radians(deg)
    fr = []
    for k in range(6):
        b = Buf()
        for s in range(L):
            j = (hf(s // 3, 7, 1) - 0.5) * 2
            x = math.cos(a) * s - math.sin(a) * j
            y = (math.sin(a) * s + math.cos(a) * j) * SQ
            if k >= 3 and hsh(s, k, 29) % (k - 1) == 0:
                continue
            b.put(x, y, AMB[4] if k == 0 else AMB[3] if k < 2 else AMB[2] if k < 4 else AMB[1])
        fr.append(b)
    return fr


# ================================================================ S1 急救 / S2 药物配置（医疗绿）

def s1_gd():
    """急救（贴地，原点 = 队长脚底）：两圈细绿环往外扩（原作 skill_01 的双环），5 拍"""
    fr = []
    for k in range(5):
        b = Buf()
        for rr, sh in ((8 + k * 4, 0), (4 + k * 4.5, 1)):
            n = int(rr * 6.4)
            for q in range(n):
                t = q / n * math.tau
                if k >= 3 and q % 2:
                    continue
                x, y = _gpt(rr, t)
                b.put(x, y, HEAL[5 - sh - min(2, k // 2)] if k < 4 else HEAL[2])
        fr.append(b)
    return fr


def s1_up(tier):
    """急救（立起，原点 = 队长脚底）：
    E0 胸口一团绿星芒（原作 skill_01_hit 的绿刺芒）+ 一枚大「+」往上飘；
    E1 再加 6 粒绿光点从脚下往上升（新元素）；E2 再加一道细绿白光柱从头顶落下（新元素）。8 拍"""
    fr = [Buf() for _ in range(8)]
    cy = -22
    for i in range(8):   # 星芒
        a = i / 8 * math.tau + 0.2
        L = 7 if i % 2 == 0 else 4
        d = (math.cos(a), math.sin(a))
        _spike(fr[0], (d[0] * 2, cy + d[1] * 2), d, L, [HEAL[6], HEAL[5], HEAL[5], HEAL[4], HEAL[3]])
        for s in range(L // 2, L + 1):
            fr[1].put(d[0] * (s + 2), cy + d[1] * (s + 2), HEAL[4] if s < L else HEAL[3])
        fr[2].put(d[0] * (L + 3), cy + d[1] * (L + 3), HEAL[3])
    for x in range(-1, 2):
        for y in range(-1, 2):
            fr[0].put(x, cy + y, HEAL[6])
    for k in range(1, 8):   # 大「+」往上飘、变暗
        _cross(fr[k], 0, cy - 6 - k * 2, HEAL[6] if k < 3 else HEAL[5] if k < 6 else HEAL[3], edge=HEAL[2], big=True)
    if tier >= 1:
        for i in range(6):
            x = -10 + i * 4 + (hsh(i, 1, 1) % 3) - 1
            for k in range(8):
                y = -2 - k * (3 + i % 3) - (i % 2) * 3
                if y < -34 or k < i // 2:
                    continue
                c = HEAL[6] if k - i // 2 < 2 else HEAL[4] if k - i // 2 < 5 else HEAL[3]
                fr[k].put_if_empty(x, y, c)
                if k - i // 2 < 3:
                    fr[k].put_if_empty(x, y + 1, HEAL[3])
    if tier >= 2:
        for k, (top, w) in enumerate([(-60, 1), (-60, 1), (-56, 0), (-50, 0)]):
            for y in range(top, -3):
                fr[k].put_if_empty(0, y, HEAL[6] if k < 2 else HEAL[5])
                if w:
                    fr[k].put_if_empty(-1, y, HEAL[4])
                    fr[k].put_if_empty(1, y, HEAL[4])
    return fr


def syr_hit():
    """注射器命中（立起，原点 = 命中点）：一点绿白 + 4 滴绿药水溅开（3 拍）"""
    fr = [Buf() for _ in range(3)]
    for x in range(-1, 2):
        for y in range(-1, 2):
            if abs(x) + abs(y) <= 1:
                fr[0].put(x, y, HEAL[6])
    for k in range(3):
        for i in range(4):
            a = i / 4 * math.tau + 0.8
            r = 2 + k * 2
            fr[k].put_if_empty(math.cos(a) * r, math.sin(a) * r + k, HEAL[5] if k < 2 else HEAL[3])
    return fr


def s2_gd(tier):
    """药物配置（贴地，原点 = 队长脚底）：原作 skill_02 的网点药环——一道绿白细环往外扩到 44，
    环内侧一圈「+」字网点跟着走，后 3 拍变稀、褪成暗绿。精二环外再多一道淡绿外环（同一件里，持续回复的形状差）"""
    fr = []
    for k in range(9):
        b = Buf()
        r = [8, 18, 27, 34, 39, 42, 44, 44, 44][k]
        fade = max(0, k - 5)
        n = int(r * 6.4)
        for q in range(n):
            t = q / n * math.tau
            if fade and hsh(q, k, 31) % (fade + 1) != 0:
                continue
            x, y = _gpt(r, t)
            b.put(x, y, HEAL[6] if k < 3 else HEAL[5] if k < 6 else HEAL[3])
        m = max(6, int(r * 6.4 / 9))
        for q in range(m):
            if fade and q % (fade + 1) != 0:
                continue
            t = q / m * math.tau + k * 0.04
            x, y = _gpt(r - 5, t)
            _cross(b, x, y, HEAL[4] if k < 6 else HEAL[2])
        if tier >= 2 and k >= 2:
            r2 = r + 4
            for q in range(int(r2 * 6.4)):
                if q % 3:
                    continue
                t = q / int(r2 * 6.4) * math.tau
                x, y = _gpt(r2, t)
                b.put_if_empty(x, y, HEAL[3] if k < 7 else HEAL[2])
        fr.append(b)
    return fr


def s2_up():
    """药物配置（立起，原点 = 队长脚底）：4 枚「+」在身侧冒出、慢慢往上飘、褪掉（10 拍）"""
    fr = [Buf() for _ in range(10)]
    pos = [(-9, -18, 0), (8, -24, 1), (-4, -30, 2), (11, -14, 3)]
    for (x0, y0, d) in pos:
        for k in range(10):
            u = k - d
            if u < 0 or u > 6:
                continue
            c = HEAL[6] if u < 2 else HEAL[5] if u < 4 else HEAL[3]
            _cross(fr[k], x0, y0 - u * 2, c, edge=HEAL[1], big=d % 2 == 0)
    return fr


def hot_aura():
    """药物配置持续回复（精二，立起，循环 12 拍，原点 = 队长脚底）：3 枚小「+」绕腰一圈（前半圈亮、后半圈暗）"""
    fr = []
    for k in range(12):
        b = Buf()
        for i in range(3):
            a = (k / 12 + i / 3) * math.tau
            x, y = math.cos(a) * 14, math.sin(a) * 5 - 14
            _cross(b, x, y, HEAL[5] if math.sin(a) > 0 else HEAL[3])
        fr.append(b)
    return fr


def hot_tick():
    """持续回复每跳（立起，原点 = 队长脚底）：一枚小「+」从胸口往上冒（6 拍）"""
    fr = [Buf() for _ in range(6)]
    for k in range(6):
        _cross(fr[k], 3 - k // 3, -26 - k * 2, HEAL[6] if k < 2 else HEAL[4] if k < 4 else HEAL[2])
    return fr


# ================================================================ 连携技「钙质护盾」（skill_link l_saria）

def link_shell(front):
    """钙质护盾（立起，原点 = 队长脚底）：贴地一圈琥珀矮晶围住队长（11-05 用户「钙质护盾会挡住队长，需要改一下图层位置」：
    原来 6 片晶板浮在腰高、前半圈盖住队长本体）。现在晶全部长在地上：后半圈（front = False，排在队长身后）高 9；
    前半圈（front = True，排在队长前面）只有 4 像素高的小晶尖、离脚 ≥ 10 像素，1 倍下队长本体完整看得见。
    23 拍 ≈ 1.5 秒：0–3 破土长出，4–18 立着（高光逐根走），19–22 碎开"""
    fr = []
    rx = 20
    n = 10
    for k in range(23):
        b = Buf()
        for i in range(n):
            a = i / n * math.tau + 0.31
            sa = math.sin(a)
            if (sa > 0.05) != front:
                continue
            x, y = math.cos(a) * rx, sa * rx * SQ
            H = 4 if front else (9 if abs(math.cos(a)) < 0.8 else 7)
            if k <= 3:
                hh = max(1, int(H * (k + 1) / 4))
            elif k <= 18:
                hh = H
            else:
                hh = 0
            if hh > 0:
                hot = 4 <= k <= 18 and ((k - 4) // 2) % n == i
                base_shadow(b, x, y, 2)
                crystal_prism(b, x, y, 3 if front else 4, hh, lean=math.cos(a) * 0.25, glint=1 if hot and hh > 4 else -1, top_hot=k == 4 or hot)
            else:
                shards_fly(b, x, y - 3, 3, 2 + (k - 19) * 3, AMB, 61 + i, down=(k - 19) * 3)
        fr.append(b)
    return fr


def link_ring_gd():
    """钙质护盾贴地晶环（贴地，原点 = 队长脚底）：半径 20 的断续琥珀环 + 2 格暗内边，23 拍，最后 4 拍断开褪掉"""
    fr = []
    r = 20
    for k in range(23):
        b = Buf()
        u = min(1.0, (k + 1) / 3)
        fade = max(0, k - 18)
        m = int(r * 6.4)
        for q in range(m):
            t = q / m * math.tau
            if hsh(q, 5, 81) % 4 == 0 or (fade and hsh(q, k, 83) % (5 - min(4, fade)) == 0):
                continue
            x, y = _gpt(r * u, t)
            b.put(x, y, AMB[4] if (q + k * 2) % 23 else AMB[6])
            x2, y2 = _gpt(r * u - 1.5, t)
            b.put_if_empty(x2, y2, AMB[1])
        fr.append(b)
    return fr


def link_patch(v):
    """钙化地面斑（贴地，原点 = 斑心）：一片不规则的暗琥珀斑边（断续）+ 斑里冒出 6–8 粒 2–4 像素高的小晶尖（冷白尖、琥珀身），
    24 拍 ≈ 1.6 秒：前 3 拍晶尖冒出、中间逐粒闪一下、最后 5 拍晶尖缩回、斑边断开褪掉"""
    fr = []
    rx, ry = 15, 6
    pts = []
    for i in range(8):
        a = hf(i, v, 1) * math.tau
        r = 0.25 + 0.7 * math.sqrt(hf(i, v, 2))
        pts.append((round(math.cos(a) * r * rx), round(math.sin(a) * r * ry), 2 + hsh(i, v, 3) % 3))
    for k in range(24):
        b = Buf()
        u = min(1.0, (k + 1) / 3)
        fade = max(0, k - 18)
        n = 40
        for q in range(n):
            t = q / n * math.tau
            wob = 1.0 + (hf(q // 4, v, 9) - 0.5) * 0.35
            if hsh(q, v, 37) % 3 == 0 or (fade and hsh(q, k, 39) % (6 - min(5, fade)) == 0):
                continue
            b.put(math.cos(t) * rx * wob * u, math.sin(t) * ry * wob * u, AMB[1])
        for i, (x, y, h) in enumerate(pts):
            hh = h if k >= 2 else max(1, h * k // 2)
            if fade:
                hh = max(0, h - (fade * h) // 5)
            for j in range(hh):
                c = CAL[5] if j == hh - 1 else AMB[3] if j == 0 else AMB[4]
                if j == hh - 1 and (k + i * 3) % 12 == 0:
                    c = AMB[6]
                b.put(x, y - j, c)
            if hh > 0:
                b.put(x + 1, y, AMB[2])
        fr.append(b)
    return fr


# ================================================================ 运行时件（游戏里 fx_pxplane_sa.gd 逐格画，同算法）

def syringe(d):
    """注射器弹体（腰高飞行，原点 = 弹头）：沿方向 d，s = 0 针尖白、1–2 针（浅灰）、3–6 针筒（中线绿药亮芯、两侧白壁）、7 推杆、8 横档。
    1 倍下要看得清（用户口径：细物件用尖长形 + 亮芯）。返回 [(沿向 s, 法向 w, 颜色)]"""
    out = [(0, 0, WH[6]), (1, 0, WH[4]), (2, 0, WH[3])]
    for s in range(3, 7):
        out.append((s, 0, HEAL[6] if s in (4, 5) else HEAL[5]))
        out.append((s, 1, WH[5]))
        out.append((s, -1, WH[4]))
    out += [(7, 0, DUST[3]), (8, 0, DUST[3]), (8, 1, DUST[3]), (8, -1, DUST[3])]
    return out


def shard(d, beat):
    """碎晶片弹体（腰高飞行，原点 = 弹头）：白尖 + 2 格琥珀身 + 3 格暗尾（尾巴逐拍闪一格）"""
    out = [(0, 0, AMB[6]), (1, 0, AMB[5]), (2, 0, AMB[4]), (1, 1, AMB[3])]
    for s in range(3, 6):
        if (s + beat) % 3 == 0 and s > 3:
            continue
        out.append((s, 0, AMB[2] if s < 5 else AMB[1]))
    return out


def guard_ring(r, beat):
    """阻挡圈（贴地，原点 = 队长脚底）：8 段断续暗琥珀弧（各占 1/8 的 55%），每 2 拍转一格。返回 [(x, y, 颜色)]"""
    out = []
    n = int(r * 6.4)
    rot = (beat // 2) % 64 / 64.0 * math.tau / 8
    for q in range(n):
        t = q / n * math.tau
        seg = ((t - rot) % (math.tau / 8)) / (math.tau / 8)
        if seg > 0.55:
            continue
        x, y = _gpt(r, t)
        out.append((round(x), round(y), AMB[2] if seg < 0.45 else AMB[1]))
    return out
