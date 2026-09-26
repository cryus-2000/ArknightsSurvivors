# -*- coding: utf-8 -*-
"""干员技能图标（32×32 像素）：art/incoming/skill_<干员 id>_s<1-3>.png；水月沿用旧文件名 skill_s1/s2/s3。

用法：
  python tools/make_skill_icons.py                    # 生成全部，写进 art/incoming/
  python tools/make_skill_icons.py --only skadi,logos # 只生成这几名干员
  python tools/make_skill_icons.py --preview out.png  # 另存一张放大预览（6 倍 + HUD 实际大小）

风格：按原作技能图标的构图重画（方形底 + 红色放射 / X / 五边形 + 白框 + 扁平白色主体，治疗蓝、防御金、充能绿），
不使用原作图片。像素规范同 docs/05：每个图标由几何图形拼成，每个像素记「色阶 + 亮度」按色阶上色，
方形底外加 1px 深色描边 #080E18；不做抗锯齿、没有半透明像素。
"""
import argparse
import math
import os
import sys

from PIL import Image, ImageDraw

W = 32
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "art", "incoming")
OUTLINE = (8, 14, 24, 255)   # #080E18


def H(s):
    s = s.lstrip("#")
    return (int(s[0:2], 16), int(s[2:4], 16), int(s[4:6], 16), 255)


def ramp(*cols):
    return [H(c) for c in cols]


# ---------------------------------------------------------------- 色阶（暗 → 亮）
FIRE = ramp("#7a1c0c", "#c8391a", "#f26b1d", "#ffab3a", "#ffe07a")
FIRE_CORE = ramp("#ffb040", "#ffe07a", "#fff6d0")
ROCK = ramp("#1c1318", "#34252c", "#4f3a42", "#6c525a")
STEEL = ramp("#2e3848", "#56657a", "#8d9db2", "#c8d4e2", "#f2f7ff")
GOLD = ramp("#6a3e0c", "#a8661a", "#e0a032", "#ffd86a", "#fff4c0")
PINK = ramp("#5e2442", "#a44a7a", "#e28ab8", "#ffcfe6")
WIND = ramp("#b87aa4", "#f0bede", "#fff2fa")
WOOD = ramp("#3a200c", "#65401e", "#946034", "#b8844e")
GREEN = ramp("#0b3a20", "#1b7040", "#3dbb62", "#9af0a6", "#e8ffe8")
BADGE = ramp("#6e7c8c", "#aab6c4", "#dfe6ee", "#fafcff")
BONE_G = ramp("#3d5a46", "#7fa88a", "#c4e8cc", "#f2fff4")
VIOLET = ramp("#1c1846", "#3a3494", "#6264d8", "#a8b0ff", "#e4e8ff")
VOID = ramp("#06050e", "#141029", "#241c46")
EYE = ramp("#8a8ec8", "#c8ccf0", "#f4f6ff")
LBLUE = ramp("#0f3558", "#2572aa", "#52b6ea", "#b4ecff", "#f0fcff")
GLASS = ramp("#1c3a4a", "#3d7890", "#8cc8dc", "#e0f6ff")
IRON = ramp("#161e2a", "#2e3e54", "#50698a", "#8eaccb", "#d2e4f6")
TOWER = ramp("#7c8898", "#bcc6d2", "#e8eef6", "#ffffff")
AMBER = ramp("#5a2e06", "#9e5a12", "#e09a2c", "#ffd07a", "#fff0c8")
BLUE = ramp("#0c1f46", "#1b4696", "#3b80de", "#9cc8ff", "#e6f2ff")
WATER = ramp("#0b2a48", "#1a5e98", "#36a4dc", "#9ae6ff", "#eaffff")
CRIMSON = ramp("#360812", "#7e1422", "#cf2c36", "#ff7a72", "#ffd0c8")
PALE = ramp("#36404c", "#7c8c9c", "#bccad8", "#eef4fb")
FOX = ramp("#7a3a06", "#c27414", "#f5b640", "#ffe79a", "#fffbe0")
TEAL = ramp("#0a3a3c", "#167a78", "#2ec4bc", "#9af4ec")
RED = ramp("#380606", "#841210", "#d92a24", "#ff7a5e", "#ffd2c0")
ASH = ramp("#222228", "#46464e", "#72727c", "#a8a8b2")
MIST = ramp("#24163a", "#4c3272", "#8a64b8", "#cfb0f0")

LAVA = H("#ff7a22")
LAVA_HI = H("#ffd35a")
WHITE = H("#ffffff")


# ---------------------------------------------------------------- 图形工具
def _inside(pts, px, py):
    c = False
    n = len(pts)
    for i in range(n):
        x1, y1 = pts[i]
        x2, y2 = pts[(i + 1) % n]
        if (y1 > py) != (y2 > py):
            xi = x1 + (py - y1) * (x2 - x1) / (y2 - y1)
            if px < xi:
                c = not c
    return c


def rot(pts, cx, cy, deg):
    """点绕 (cx, cy) 旋转（角度按屏幕顺时针为正）"""
    a = math.radians(deg)
    ca, sa = math.cos(a), math.sin(a)
    return [(cx + (x - cx) * ca - (y - cy) * sa, cy + (x - cx) * sa + (y - cy) * ca) for x, y in pts]


def rect_pts(cx, cy, w, h, deg=0.0):
    p = [(cx - w / 2, cy - h / 2), (cx + w / 2, cy - h / 2), (cx + w / 2, cy + h / 2), (cx - w / 2, cy + h / 2)]
    return rot(p, cx, cy, deg) if deg else p


def star_pts(cx, cy, r_out, r_in, n, deg=-90.0):
    out = []
    for i in range(n * 2):
        r = r_out if i % 2 == 0 else r_in
        a = math.radians(deg + i * 180.0 / n)
        out.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return out


def arc_pts(cx, cy, r0, r1, a0, a1, steps=24):
    """扇环多边形；角度：0 = 右，90 = 上（逆时针）"""
    outer = []
    inner = []
    for i in range(steps + 1):
        a = math.radians(a0 + (a1 - a0) * i / steps)
        outer.append((cx + r1 * math.cos(a), cy - r1 * math.sin(a)))
        inner.append((cx + r0 * math.cos(a), cy - r0 * math.sin(a)))
    return outer + inner[::-1]


def bezier(p0, p1, p2, t):
    u = 1 - t
    return (u * u * p0[0] + 2 * u * t * p1[0] + t * t * p2[0], u * u * p0[1] + 2 * u * t * p1[1] + t * t * p2[1])


class Icon:
    def __init__(self):
        self.m = [[None] * W for _ in range(W)]     # 色阶（None = 空）
        self.v = [[0.5] * W for _ in range(W)]      # 亮度 0..1
        self.bev = [[0.0] * W for _ in range(W)]    # 边缘提亮 / 压暗的幅度
        self.fix = {}                               # 上色后、描边前的定色像素（裂纹、眼睛）
        self.post = {}                              # 描边后的点缀（火星、闪光）
        self.clip = None                            # (x0, y0, x1, y1)：方形底画好后，之后的图形都裁在里面

    # ---- 基本写入
    def _put(self, pts, rp, shade, bevel):
        c = self.clip or (0, 0, W - 1, W - 1)
        pts = [(x, y) for x, y in pts if c[0] <= x <= c[2] and c[1] <= y <= c[3]]
        if not pts:
            return
        xs = [p[0] for p in pts]
        ys = [p[1] for p in pts]
        box = (min(xs), min(ys), max(xs), max(ys))
        for x, y in pts:
            self.fix.pop((x, y), None)
            if rp is None:
                self.m[y][x] = None
                continue
            self.m[y][x] = rp
            self.v[y][x] = _shade(shade, x, y, box)
            self.bev[y][x] = bevel

    # ---- 图形
    def poly(self, pts, rp, shade=0.5, bevel=0.0):
        self._put([(x, y) for y in range(W) for x in range(W) if _inside(pts, x + 0.5, y + 0.5)], rp, shade, bevel)

    def circle(self, cx, cy, r, rp, shade=0.5, bevel=0.0):
        self._put([(x, y) for y in range(W) for x in range(W) if (x + 0.5 - cx) ** 2 + (y + 0.5 - cy) ** 2 <= r * r], rp, shade, bevel)

    def ellipse(self, cx, cy, rx, ry, rp, shade=0.5, bevel=0.0):
        self._put([(x, y) for y in range(W) for x in range(W) if ((x + 0.5 - cx) / rx) ** 2 + ((y + 0.5 - cy) / ry) ** 2 <= 1.0], rp, shade, bevel)

    def ring(self, cx, cy, r0, r1, rp, shade=0.5, bevel=0.0, a0=None, a1=None):
        pts = []
        for y in range(W):
            for x in range(W):
                dx, dy = x + 0.5 - cx, y + 0.5 - cy
                d2 = dx * dx + dy * dy
                if not (r0 * r0 <= d2 <= r1 * r1):
                    continue
                if a0 is not None:
                    a = math.degrees(math.atan2(-dy, dx)) % 360
                    lo, hi = a0 % 360, a1 % 360
                    ok = (lo <= a <= hi) if lo <= hi else (a >= lo or a <= hi)
                    if not ok:
                        continue
                pts.append((x, y))
        self._put(pts, rp, shade, bevel)

    def crescent(self, cx, cy, r, ox, oy, r2, rp, shade=0.5, bevel=0.0):
        """圆 (cx, cy, r) 减去圆 (cx+ox, cy+oy, r2)"""
        pts = []
        for y in range(W):
            for x in range(W):
                if (x + 0.5 - cx) ** 2 + (y + 0.5 - cy) ** 2 <= r * r and (x + 0.5 - cx - ox) ** 2 + (y + 0.5 - cy - oy) ** 2 > r2 * r2:
                    pts.append((x, y))
        self._put(pts, rp, shade, bevel)

    def line(self, x0, y0, x1, y1, rp, w=1.0, shade=0.5, bevel=0.0):
        if w <= 1.0:
            self._put(_bres(round(x0), round(y0), round(x1), round(y1)), rp, shade, bevel)
            return
        pts = []
        for y in range(W):
            for x in range(W):
                if _seg_dist(x + 0.5, y + 0.5, x0 + 0.5, y0 + 0.5, x1 + 0.5, y1 + 0.5) <= w / 2.0:
                    pts.append((x, y))
        self._put(pts, rp, shade, bevel)

    def sweep(self, p0, p1, p2, r0, r1, rp, shade=0.5, bevel=0.0, steps=40):
        """沿二次贝塞尔扫过的圆（粗细从 r0 渐变到 r1）：号角、狐尾这类弯的粗条"""
        pts = set()
        for i in range(steps + 1):
            t = i / steps
            cx, cy = bezier(p0, p1, p2, t)
            r = r0 + (r1 - r0) * t
            for y in range(int(cy - r - 1), int(cy + r + 2)):
                for x in range(int(cx - r - 1), int(cx + r + 2)):
                    if (x + 0.5 - cx) ** 2 + (y + 0.5 - cy) ** 2 <= r * r:
                        pts.add((x, y))
        self._put(sorted(pts), rp, shade, bevel)

    def rect(self, x0, y0, x1, y1, rp, shade=0.5, bevel=0.0):
        self._put([(x, y) for y in range(y0, y1 + 1) for x in range(x0, x1 + 1)], rp, shade, bevel)

    def bitmap(self, rows, x0, y0, legend):
        """legend：字符 → (色阶, 亮度) 或定色 RGBA；'.' 为空（不改）"""
        for j, row in enumerate(rows):
            for i, ch in enumerate(row):
                if ch == "." or ch not in legend:
                    continue
                x, y = x0 + i, y0 + j
                if not (0 <= x < W and 0 <= y < W):
                    continue
                val = legend[ch]
                if isinstance(val, tuple) and len(val) == 2 and isinstance(val[0], list):
                    self.m[y][x] = val[0]
                    self.v[y][x] = val[1]
                    self.bev[y][x] = 0.0
                    self.fix.pop((x, y), None)
                else:
                    if self.m[y][x] is None:
                        self.m[y][x] = [val]
                        self.v[y][x] = 0.5
                    self.fix[(x, y)] = val

    # ---- 定色细节 / 点缀
    def dot(self, x, y, col):
        if 0 <= x < W and 0 <= y < W and self.m[y][x] is not None:
            self.fix[(x, y)] = col

    def fline(self, pts, col):
        """定色折线（只画在已有图形上）：裂纹、高光线"""
        for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
            for x, y in _bres(x0, y0, x1, y1):
                self.dot(x, y, col)

    def spark(self, x, y, col, big=False):
        """描边之后画的闪光：单点，big 时画成十字"""
        self.post[(x, y)] = col
        if big:
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                self.post[(x + dx, y + dy)] = col

    # ---- 出图
    def render(self):
        img = Image.new("RGBA", (W, W), (0, 0, 0, 0))
        px = img.load()
        for y in range(W):
            for x in range(W):
                rp = self.m[y][x]
                if rp is None:
                    continue
                v = self.v[y][x]
                b = self.bev[y][x]
                if b:
                    def same(xx, yy):
                        return 0 <= xx < W and 0 <= yy < W and self.m[yy][xx] is rp
                    if not same(x, y - 1) or not same(x - 1, y):
                        v += b
                    if not same(x, y + 1) or not same(x + 1, y):
                        v -= b
                i = int(max(0, min(len(rp) - 1, math.floor(v * len(rp)))))
                px[x, y] = rp[i]
        for (x, y), c in self.fix.items():
            px[x, y] = c
        solid = [[px[x, y][3] > 0 for x in range(W)] for y in range(W)]
        for y in range(W):
            for x in range(W):
                if solid[y][x]:
                    continue
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    xx, yy = x + dx, y + dy
                    if 0 <= xx < W and 0 <= yy < W and solid[yy][xx]:
                        px[x, y] = OUTLINE
                        break
        for (x, y), c in self.post.items():
            if 0 <= x < W and 0 <= y < W:
                px[x, y] = c
        return img


def _bres(x0, y0, x1, y1):
    pts = []
    dx, dy = abs(x1 - x0), -abs(y1 - y0)
    sx, sy = (1 if x0 < x1 else -1), (1 if y0 < y1 else -1)
    err = dx + dy
    while True:
        pts.append((x0, y0))
        if x0 == x1 and y0 == y1:
            return pts
        e2 = 2 * err
        if e2 >= dy:
            err += dy
            x0 += sx
        if e2 <= dx:
            err += dx
            y0 += sy


def _seg_dist(px, py, ax, ay, bx, by):
    vx, vy = bx - ax, by - ay
    L = vx * vx + vy * vy
    t = 0.0 if L == 0 else max(0.0, min(1.0, ((px - ax) * vx + (py - ay) * vy) / L))
    qx, qy = ax + vx * t, ay + vy * t
    return math.hypot(px - qx, py - qy)


_LIGHT = (-0.45, -0.6, 0.66)
_LN = math.sqrt(sum(c * c for c in _LIGHT))
_LIGHT = tuple(c / _LN for c in _LIGHT)


def _shade(spec, x, y, box):
    x0, y0, x1, y1 = box
    if callable(spec):
        return spec(x, y)
    if isinstance(spec, (int, float)):
        return float(spec)
    kind = spec if isinstance(spec, str) else spec[0]
    args = () if isinstance(spec, str) else spec[1:]
    fw, fh = max(1, x1 - x0), max(1, y1 - y0)
    if kind in ("tl", "t", "l", "b", "r"):
        lo, hi = (args[0], args[1]) if len(args) >= 2 else (0.15, 0.95)
        fx, fy = (x - x0) / fw, (y - y0) / fh
        k = {"tl": 1 - (fx + fy) / 2, "t": 1 - fy, "l": 1 - fx, "b": fy, "r": fx}[kind]
        return lo + (hi - lo) * k
    if kind == "sph":
        if args:
            cx, cy, R = args
        else:
            cx, cy, R = (x0 + x1 + 1) / 2, (y0 + y1 + 1) / 2, max(x1 - x0 + 1, y1 - y0 + 1) / 2
        nx, ny = (x + 0.5 - cx) / R, (y + 0.5 - cy) / R
        nz = math.sqrt(max(0.0, 1 - nx * nx - ny * ny))
        return max(0.0, min(1.0, 0.08 + 0.97 * (nx * _LIGHT[0] + ny * _LIGHT[1] + nz * _LIGHT[2])))
    if kind == "rad":
        cx, cy, r = args[:3]
        lo = args[3] if len(args) > 3 else 0.0
        return max(0.0, min(1.0, lo + (1 - lo) * (1 - math.hypot(x + 0.5 - cx, y + 0.5 - cy) / r)))
    raise ValueError(kind)


# ================================================================ 原作风格的方形技能图标
# 2026-09-26 用户要求「参考干员在原作里的技能图标」：原作图标是方形底（深灰渐变或彩色）+ 红色放射楔形 / X / 五边形 +
# 常见的白色粗框 + 一个扁平的白色主体。这里按同样的构图重画成 32×32 像素（不用原作图片）：
# 输出图标、治疗 / 辅助用蓝，防御用金，充能用绿。每个图标写明参考了原作哪个技能。
ICONS = {}


def icon(op, n):
    def deco(fn):
        ICONS[(op, n)] = fn
        return fn
    return deco


T0, T1 = 1, 30   # 方形底的范围（外面一圈留给描边）

BG = ramp("#101014", "#1b1b21", "#29292f", "#39393f", "#4b4b52")
LIGHTBG = ramp("#7d838d", "#a3a9b3", "#c7ccd4", "#e4e7ec")
REDBG = ramp("#7a2016", "#9c2a1d", "#bf3625", "#e04632")
BLUEBG = ramp("#153c70", "#1d4f8e", "#2766b0", "#3380d0")
REDM = ramp("#a52d1f", "#e04632")          # 原作的朱红（亮）与暗红
BLUEM = ramp("#1f5aa6", "#3d93e6")
GOLDM = ramp("#a8701a", "#f0b43a")
GREENM = ramp("#5c8e20", "#8cc63a")
GREYM = ramp("#4a4d55", "#6c707a")
WHT = ramp("#b4bac6", "#ffffff")            # 1.0 = 白，0.0 = 浅灰（白色主体的暗面）
DARK = ramp("#17181d")
BLACK = ramp("#08080a")
RAIN = H("#8cc8ff")


def tile(ic, bg=None):
    """方形底：左下亮、右上暗的渐变（原作技能图标的底色）；之后所有图形都裁在方形里"""
    ic.clip = (T0, T0, T1, T1)
    ic.rect(T0, T0, T1, T1, bg or BG, lambda x, y: 0.04 + 0.92 * (0.7 * (y - T0) / 29 + 0.3 * (T1 - x) / 29))


def frame(ic, w=2):
    """白框（原作多数技能图标都有），最后画"""
    for x0, y0, x1, y1 in ((T0, T0, T1, T0 + w - 1), (T0, T1 - w + 1, T1, T1), (T0, T0, T0 + w - 1, T1), (T1 - w + 1, T0, T1, T1)):
        ic.rect(x0, y0, x1, y1, WHT, 1.0)


def wedge(ic, cx, cy, a_deg, half_deg, rp=REDM, v=1.0, r=64):
    """从 (cx, cy) 朝 a_deg 张开 ±half_deg 的楔形（原作的红色放射）；0 = 右，90 = 上"""
    a0, a1 = math.radians(a_deg - half_deg), math.radians(a_deg + half_deg)
    ic.poly([(cx, cy), (cx + r * math.cos(a0), cy - r * math.sin(a0)), (cx + r * math.cos(a1), cy - r * math.sin(a1))], rp, v)


def xrays(ic, rp=REDM, v=1.0, half=15, cx=15.5, cy=15.5):
    """红色 X：四道朝四角的楔形"""
    for a in (45, 135, 225, 315):
        wedge(ic, cx, cy, a, half, rp, v)


def house(ic, rp=REDM, v=1.0, x0=4, x1=27, top=4, shoulder=11, bottom=28):
    """原作的五边形底（平底尖顶）"""
    ic.poly([(x0, shoulder), ((x0 + x1 + 1) / 2, top), (x1 + 1, shoulder), (x1 + 1, bottom + 1), (x0, bottom + 1)], rp, v)


def ngon(cx, cy, r, n, deg=-90.0):
    return [(cx + r * math.cos(math.radians(deg + 360.0 * i / n)), cy + r * math.sin(math.radians(deg + 360.0 * i / n))) for i in range(n)]


def badge(ic, n, rp, r_out=15.2, r_in=11.6, deg=-90.0, inner=None):
    """多边形徽章：外圈彩色粗边 + 暗色内芯（塞雷娅的蓝六边形、推进之王的绿六边形、流明的蓝八边形）"""
    ic.poly(ngon(15.5, 15.5, r_out, n, deg), rp, 1.0)
    ic.poly(ngon(15.5, 15.5, r_in, n, deg), inner or DARK, 0.5)


def rain(ic, col=RAIN, step=6):
    """斜雨丝（流明）：只画在已有底色上"""
    for k in range(-6, 8):
        x0 = k * step
        for j in range(0, 36, 9):
            ic.fline([(x0 + j // 2 + 4, j), (x0 + j // 2 + 2, j + 4)], col)


def brackets(ic, col=1.0, L=5, w=2, inset=3):
    """四角的直角括号（流明一技能）"""
    a, b = T0 + inset, T1 - inset
    for (x, y, sx, sy) in ((a, a, 1, 1), (b, a, -1, 1), (a, b, 1, -1), (b, b, -1, -1)):
        ic.rect(min(x, x + sx * (L - 1)), min(y, y + sy * (w - 1)), max(x, x + sx * (L - 1)), max(y, y + sy * (w - 1)), WHT, col)
        ic.rect(min(x, x + sx * (w - 1)), min(y, y + sy * (L - 1)), max(x, x + sx * (w - 1)), max(y, y + sy * (L - 1)), WHT, col)


def flame_pts(cx, cy, s=1.0):
    """火焰轮廓：尖头朝上、底圆，左侧一道火舌"""
    P = [(0, -9), (2.4, -4.8), (4.8, -1.6), (5.6, 2.6), (3.8, 6.8), (0, 8.4), (-3.8, 6.8), (-5.6, 2.6), (-5.2, -1.2), (-3.4, -2.6), (-2.6, -6.2), (-1.2, -4.2)]
    return [(cx + x * s, cy + y * s) for x, y in P]


def star4(ic, cx, cy, r, rp=WHT, v=1.0, thin=1.6, deg=-90.0):
    ic.poly(star_pts(cx, cy, r, thin, 4, deg=deg), rp, v)


def ering(ic, cx, cy, rx, ry, th, deg, rp=WHT, v=1.0):
    """旋转的椭圆环（逻各斯的轨道、维什戴尔的环）"""
    a = math.radians(deg)
    ca, sa = math.cos(a), math.sin(a)
    pts = []
    for y in range(W):
        for x in range(W):
            dx, dy = x + 0.5 - cx, y + 0.5 - cy
            u, w_ = dx * ca + dy * sa, -dx * sa + dy * ca
            if (u / rx) ** 2 + (w_ / ry) ** 2 <= 1.0 and (u / (rx - th)) ** 2 + (w_ / (ry - th)) ** 2 >= 1.0:
                pts.append((x, y))
    ic._put(pts, rp, v, 0.0)


def anchor(ic, cx, cy, deg=0.0, s=1.0, rp=WHT, v=1.0):
    """直立的锚（环在上、锚爪在下），(cx, cy) 为锚杆中点；可旋转、缩放"""
    R = lambda pts: rot([(cx + x * s, cy + y * s) for x, y in pts], cx, cy, deg)
    ic.poly(R([(-1.4, -9), (1.4, -9), (1.4, 10), (-1.4, 10)]), rp, v)
    ic.poly(R([(-6.5, -6.6), (6.5, -6.6), (6.5, -4.4), (-6.5, -4.4)]), rp, v)
    ic.poly(R(arc_pts(0, 3.5, 7.4, 10.2, 190, 350, 18)), rp, v)
    ic.poly(R([(-11, 2.6), (-6.4, 4.6), (-9.8, 8)]), rp, v)
    ic.poly(R([(11, 2.6), (6.4, 4.6), (9.8, 8)]), rp, v)
    c = R([(0, -11.6)])[0]
    ic.ring(c[0], c[1], 1.3 * s, 3.1 * s, rp, v)


def tentacle(ic, p0, p1, p2, r0=2.4, r1=0.7, curl=None, rp=WHT, v=1.0):
    """白色触手：沿贝塞尔渐细，末端可卷一个小钩（curl = (cx, cy, r, a0, a1)）"""
    ic.sweep(p0, p1, p2, r0, r1, rp, v)
    if curl:
        cx, cy, r, a0, a1 = curl
        ic.ring(cx, cy, r - 1.1, r + 0.1, rp, v, a0=a0, a1=a1)


# ---------------------------------------------------------------- 艾雅法拉
@icon("eyjafjalla", 1)
def eyja_heat(ic):
    """炽热（参考原作一技能「二重咏唱」的构图：白框 + 红五边形 + 交叉法杖）：法杖顶上燃着火"""
    tile(ic)
    house(ic, top=6, shoulder=13)
    ic.line(8, 27, 23, 12, WHT, w=1.8, shade=1.0)
    ic.line(23, 27, 8, 12, WHT, w=1.8, shade=1.0)
    ic.poly(flame_pts(7.5, 9, 0.5), WHT, 1.0)
    ic.poly(flame_pts(23.5, 9, 0.5), WHT, 1.0)
    ic.poly(ngon(15.5, 19.5, 2.2, 4), REDM, 1.0)
    frame(ic)


@icon("eyjafjalla", 2)
def eyja_ignite(ic):
    """点燃（参考原作二技能「点燃」）：红色放射底 + 大团白焰，焰心镂空"""
    tile(ic)
    for a, h in ((40, 11), (72, 9), (108, 9), (140, 11), (8, 7), (172, 7)):
        wedge(ic, 15.5, 30, a, h)
    ic.poly(flame_pts(15.5, 17, 1.38), WHT, 1.0)
    ic.poly(flame_pts(15.5, 21.5, 0.5), REDM, 1.0)


@icon("eyjafjalla", 3)
def eyja_volcano(ic):
    """火山（参考原作三技能「火山」）：放射的红光里喷发的白色火山"""
    tile(ic)
    for a, h in ((25, 7), (55, 9), (90, 10), (125, 9), (155, 7)):
        wedge(ic, 15.5, 15, a, h)
    ic.poly([(2, 31), (11, 17), (20, 17), (29, 31)], WHT, 1.0)
    ic.poly([(12, 17), (19, 17), (17.5, 19.5), (13.5, 19.5)], REDM, 0.0)
    ic.fline([(15, 20), (14, 23), (16, 26), (15, 30)], REDM[1])
    ic.fline([(19, 22), (21, 26)], REDM[1])
    for cx, cy, r in ((15.5, 9, 2.8), (10, 12, 2.1), (21, 11.5, 2.1), (6, 7, 1.3), (25, 6, 1.3), (15.5, 3.5, 1.3), (9, 3.5, 0.9), (22, 2.8, 0.9)):
        ic.circle(cx, cy, r, WHT, 1.0)


# ---------------------------------------------------------------- 艾丽妮
@icon("irene", 1)
def irene_gust(ic):
    """疾风（参考原作一技能「疾风」）：斜向红色锋面 + 白色细剑 + 两道新月风刃"""
    tile(ic)
    for a, h in ((20, 8), (45, 10), (70, 8)):
        wedge(ic, 2, 29, a, h)
    ic.line(4, 28, 21, 9, WHT, w=1.8, shade=1.0)
    ic.line(4, 23, 10, 29, WHT, w=1.6, shade=1.0)
    ic.circle(3, 29.5, 1.6, WHT, 1.0)
    ic.crescent(14, 20, 14, -2.4, 1.4, 13.6, WHT, 1.0)
    ic.crescent(16, 22, 10, -2.0, 1.2, 9.6, WHT, 1.0)
    ic.poly([(20, 6), (25, 2), (22, 8)], WHT, 1.0)


@icon("irene", 2)
def irene_shattertide(ic):
    """碎潮（参考原作二技能「碎潮」）：白框 + 上下红楔 + 碎开的潮环 + 竖剑"""
    tile(ic)
    wedge(ic, 15.5, 15.5, 90, 24)
    wedge(ic, 15.5, 15.5, 270, 24)
    for a0, a1 in ((15, 70), (105, 165), (195, 250), (290, 345)):
        ic.ring(15.5, 16, 8.4, 10.8, WHT, 1.0, a0=a0, a1=a1)
    for pts in ([(4, 9), (7, 11), (4, 12)], [(27, 20), (24, 21), (27, 23)], [(24, 7), (26, 9), (23, 10)], [(6, 22), (8, 24), (5, 25)]):
        ic.poly(pts, WHT, 1.0)
    ic.line(15.5, 3, 15.5, 28, WHT, w=1.6, shade=1.0)
    ic.line(12, 8, 19, 8, WHT, w=1.6, shade=1.0)
    frame(ic)


@icon("irene", 3)
def irene_judgment(ic):
    """审判（参考原作三技能「审判」）：白框 + V 形红光 + 竖直长剑与灯环，两侧卷起白焰"""
    tile(ic)
    wedge(ic, 15.5, 20, 58, 14)
    wedge(ic, 15.5, 20, 122, 14)
    ic.poly(rot(flame_pts(8, 23, 0.62), 8, 23, -18), WHT, 1.0)
    ic.poly(rot(flame_pts(23, 23, 0.62), 23, 23, 18), WHT, 1.0)
    ic.line(15.5, 4, 15.5, 28, WHT, w=1.6, shade=1.0)
    ic.ring(15.5, 10.5, 2.4, 4.0, WHT, 1.0)
    ic.line(11, 16, 20, 16, WHT, w=1.4, shade=1.0)
    frame(ic)


# ---------------------------------------------------------------- 凯尔希
@icon("kaltsit", 1)
def kaltsit_unit(ic):
    """医疗单元（参考原作一技能「指令：结构加固」）：白框 + 金色阶梯十字 + 白十字"""
    tile(ic)
    for x0, y0, x1, y1 in ((10, 4, 21, 27), (4, 10, 27, 21), (7, 7, 24, 24)):
        ic.rect(x0, y0, x1, y1, GOLDM, 1.0 if x0 != 7 else 0.0)
    for x0, y0, x1, y1 in ((7, 7, 9, 9), (22, 7, 24, 9), (7, 22, 9, 24), (22, 22, 24, 24)):
        ic.rect(x0, y0, x1, y1, BG, 0.2)
    ic.rect(13, 6, 18, 25, WHT, 1.0)
    ic.rect(6, 13, 25, 18, WHT, 1.0)
    ic.rect(14, 14, 17, 17, GOLDM, 1.0)
    frame(ic)


@icon("kaltsit", 2)
def kaltsit_coord(ic):
    """战术协同（参考原作二技能「指令：战术协同」）：浅色底 + 叠起的菱形 + 中间一道黑线"""
    tile(ic, LIGHTBG)
    for dy, v in ((6, 0.0), (2, 0.0), (-2, 1.0)):
        pts_o = ngon(15.5, 15.5 + dy, 11.5, 4)
        pts_i = ngon(15.5, 15.5 + dy, 7.0, 4)
        ic.poly(pts_o, WHT, v)
        ic.poly(pts_i, LIGHTBG, 0.55)
    ic.rect(15, T0, 16, T1, BLACK, 0.5)
    frame(ic)


@icon("kaltsit", 3)
def kaltsit_meltdown(ic):
    """熔毁（参考原作三技能「指令：熔毁」）：白框 + 灰色 X + 迸碎的红三角"""
    tile(ic)
    xrays(ic, GREYM, 1.0, half=11)
    ic.poly([(15.5, 5), (28, 27), (3, 27)], REDM, 1.0)
    ic.poly([(15.5, 25), (11, 17), (20, 17)], BLACK, 0.5)
    ic.poly([(9.5, 22), (7, 26), (12, 26)], BLACK, 0.5)
    ic.poly([(21.5, 22), (19, 26), (24, 26)], BLACK, 0.5)
    for pts in ([(23, 6), (26, 4), (25, 8)], [(6, 8), (9, 7), (7, 11)], [(26, 14), (28, 13), (27, 16)]):
        ic.poly(pts, REDM, 1.0)
    frame(ic)


# ---------------------------------------------------------------- 逻各斯
@icon("logos", 1)
def logos_synecdoche(ic):
    """提喻（参考原作「提喻」）：白框 + 红 X + 两道交叉的轨道环 + 中间的咒文"""
    tile(ic)
    xrays(ic, half=10)
    ering(ic, 15.5, 15.5, 13.2, 5.4, 1.6, 34)
    ering(ic, 15.5, 15.5, 13.2, 5.4, 1.6, -34)
    ic.circle(15.5, 15.5, 5.6, DARK, 0.5)
    rune = ["..####..",
            ".##..##.",
            ".##.....",
            "..####..",
            ".....##.",
            ".##..##.",
            "..####..",
            "...##...",
            "...#...."]
    ic.bitmap(rune, 12, 11, {"#": (WHT, 1.0)})
    frame(ic)


@icon("logos", 2)
def logos_perish(ic):
    """湮灭（参考原作「湮灭」）：散落的红方块 + 白色十字星与环"""
    tile(ic)
    for x, y, s in ((4, 4, 3), (9, 3, 2), (14, 5, 3), (21, 4, 2), (25, 8, 3), (3, 10, 2), (6, 15, 3), (4, 21, 2), (8, 25, 3),
                    (13, 26, 2), (19, 24, 3), (24, 20, 2), (26, 25, 2), (11, 9, 2), (20, 10, 2), (22, 15, 2)):
        ic.rect(x, y, x + s - 1, y + s - 1, REDM, 1.0 if s == 3 else 0.0)
    ic.ring(15.5, 15.5, 8.2, 9.8, WHT, 1.0)
    star4(ic, 15.5, 15.5, 14, WHT, 1.0, 2.2)
    star4(ic, 15.5, 15.5, 6.5, WHT, 1.0, 1.4, deg=-45)
    ic.poly(ngon(15.5, 15.5, 1.8, 4), DARK, 0.5)


@icon("logos", 3)
def logos_acuity(ic):
    """延展敏锐（参考原作「延展敏锐」）：白框 + 红放射 + 环中交叉的菱格 + 底部两道羽翼"""
    tile(ic)
    for a in (55, 125):
        wedge(ic, 15.5, 14, a, 16)
    ic.ring(15.5, 14, 9.6, 11.2, WHT, 1.0)
    ic.line(10, 8, 21, 20, WHT, w=1.6, shade=1.0)
    ic.line(21, 8, 10, 20, WHT, w=1.6, shade=1.0)
    ic.poly(ngon(15.5, 14, 5.4, 4), WHT, 1.0)
    ic.poly(ngon(15.5, 14, 3.0, 4), REDM, 1.0)
    ic.crescent(7, 27, 7, 2.6, -2.4, 6.4, WHT, 1.0)
    ic.crescent(24, 27, 7, -2.6, -2.4, 6.4, WHT, 1.0)
    frame(ic)


# ---------------------------------------------------------------- 流明
@icon("lumen", 1)
def lumen_purify(ic):
    """净化之光（参考原作一技能「微雨，匮乏」）：蓝底斜雨 + 白色六臂星 + 四角括号"""
    tile(ic, BLUEBG)
    for a, h in ((200, 16), (330, 12), (100, 10)):
        wedge(ic, 15.5, 15.5, a, h, BLUEM, 0.0)
    rain(ic)
    for a in (90, 30, 150):
        ca, sa = math.cos(math.radians(a)), -math.sin(math.radians(a))
        ic.line(15.5 - 10 * ca, 15.5 - 10 * sa, 15.5 + 10 * ca, 15.5 + 10 * sa, WHT, w=4.2, shade=1.0)
    brackets(ic)


@icon("lumen", 2)
def lumen_lantern(ic):
    """领航灯（参考原作三技能「此灯不灭」）：蓝色八边形徽章里的白色提灯"""
    tile(ic)
    ic.poly(ngon(15.5, 15.5, 15.6, 8, -67.5), WHT, 1.0)
    ic.poly(ngon(15.5, 15.5, 13.6, 8, -67.5), BLUEM, 1.0)
    rain(ic, H("#6cb2f2"))
    ic.ring(15.5, 5.5, 1.4, 2.8, WHT, 1.0)
    ic.rect(11, 8, 20, 9, WHT, 1.0)
    ic.rect(10, 10, 21, 24, WHT, 1.0)
    ic.rect(12, 12, 19, 22, BLUEM, 0.0)
    ic.poly(flame_pts(15.5, 17.5, 0.46), WHT, 1.0)
    ic.rect(9, 25, 22, 26, WHT, 1.0)


@icon("lumen", 3)
def lumen_lighthouse(ic):
    """指引灯塔（参考原作流明图标的蓝底斜雨与括号）：灯塔向两侧打出光束"""
    tile(ic, BLUEBG)
    rain(ic)
    wedge(ic, 15.5, 8, 168, 9, ramp("#8cc8ff"), 0.5)
    wedge(ic, 15.5, 8, 12, 9, ramp("#8cc8ff"), 0.5)
    ic.poly([(12, 12), (19, 12), (21, 28), (10, 28)], WHT, 1.0)
    ic.poly([(11.6, 16), (19.4, 16), (19.7, 18), (11.3, 18)], BLUEM, 0.0)
    ic.poly([(10.9, 22), (20.1, 22), (20.4, 24), (10.6, 24)], BLUEM, 0.0)
    ic.rect(12, 6, 19, 11, WHT, 1.0)
    ic.rect(14, 7, 17, 10, ramp("#8cc8ff"), 0.5)
    ic.poly([(11, 6), (15.5, 2.5), (20, 6)], WHT, 1.0)
    ic.rect(6, 28, 25, 29, WHT, 1.0)


# ---------------------------------------------------------------- 水月（覆盖 skill_s1/2/3）
@icon("mizuki", 1)
def mizuki_awaken(ic):
    """唤醒（参考原作一技能「唤醒」）：红色放射 + 从下方翻涌而起的白色触手"""
    tile(ic)
    for a, h in ((45, 12), (90, 12), (135, 12)):
        wedge(ic, 15.5, 30, a, h)
    tentacle(ic, (5, 31), (2, 17), (9, 10), 2.8, 1.0, (10.5, 12.5, 2.6, 20, 200))
    tentacle(ic, (15, 31), (20, 16), (13, 5), 3.0, 1.0, (11, 6.5, 2.4, 300, 120))
    tentacle(ic, (25, 31), (30, 19), (23, 13), 2.6, 0.9, (25, 13.5, 2.3, 100, 260))


@icon("mizuki", 2)
def mizuki_dilemma(ic):
    """囚徒困境（参考原作二技能「囚徒困境」）：白框 + 红五边形 + 触手围成的心形，中间一枚菱形"""
    tile(ic)
    house(ic)
    tentacle(ic, (15.5, 27), (4, 21), (7, 11), 2.2, 1.0, (10, 11, 3.0, 0, 180))
    tentacle(ic, (15.5, 27), (27, 21), (24, 11), 2.2, 1.0, (21, 11, 3.0, 0, 180))
    ic.poly(ngon(15.5, 15, 4.4, 4), WHT, 1.0)
    ic.poly(ngon(15.5, 15, 2.4, 4), REDM, 1.0)
    ic.poly(ngon(15.5, 15, 1.0, 4), WHT, 1.0)
    frame(ic)


@icon("mizuki", 3)
def mizuki_mirage(ic):
    """镜花水月（参考原作三技能「镜中月」）：白框 + 红底 + 触手缠成的环 + 中间的四瓣花"""
    tile(ic, REDBG)
    xrays(ic, ramp("#1b1b21"), 0.5, half=10)
    ic.ring(15.5, 15.5, 9, 11.2, WHT, 1.0)
    for k in range(12):
        a = math.radians(k * 30 + 15)
        ic.poly(star_pts(15.5 + 12 * math.cos(a), 15.5 + 12 * math.sin(a), 2.4, 0.8, 2, deg=k * 30 + 15), WHT, 1.0)
    for dx, dy in ((0, -4), (4, 0), (0, 4), (-4, 0)):
        ic.circle(15.5 + dx, 15.5 + dy, 3.2, WHT, 1.0)
    ic.poly(ngon(15.5, 15.5, 3.2, 4), REDM, 1.0)
    ic.poly(ngon(15.5, 15.5, 1.4, 4), WHT, 1.0)
    frame(ic)


# ---------------------------------------------------------------- 塞雷娅
@icon("saria", 1)
def saria_first_aid(ic):
    """急救（参考原作一技能「急救」）：蓝色六边形徽章 + 白色三叉 + 括号"""
    tile(ic)
    badge(ic, 6, BLUEM)
    for a in (90, 210, 330):
        ca, sa = math.cos(math.radians(a)), -math.sin(math.radians(a))
        ic.line(15.5, 15.5, 15.5 + 8.8 * ca, 15.5 + 8.8 * sa, WHT, w=3.8, shade=1.0)
    ic.circle(15.5, 15.5, 3.0, WHT, 1.0)


@icon("saria", 2)
def saria_dispense(ic):
    """药剂散布（参考原作二技能「药剂散布」）：蓝色六边形徽章 + 白色胶囊，四周散开的短线"""
    tile(ic)
    badge(ic, 6, BLUEM)
    for a in (30, 150, 210, 330):
        ca, sa = math.cos(math.radians(a)), -math.sin(math.radians(a))
        ic.line(15.5 + 7.2 * ca, 15.5 + 7.2 * sa, 15.5 + 9.6 * ca, 15.5 + 9.6 * sa, WHT, w=2.0, shade=1.0)
    ic.circle(15.5, 10.5, 3.0, WHT, 1.0)
    ic.rect(13, 10, 18, 15, WHT, 1.0)
    ic.circle(15.5, 20.5, 3.0, WHT, 1.0)
    ic.rect(13, 16, 18, 21, WHT, 1.0)
    ic.circle(15.5, 20.5, 1.6, DARK, 0.5)
    ic.rect(14, 16, 17, 20, DARK, 0.5)


@icon("saria", 3)
def saria_calcify(ic):
    """钙质化（参考原作三技能「钙质化」）：白框 + 上方蓝色晶块、下方白色晶珠排成的晶格"""
    tile(ic)
    for x, y, s in ((4, 4, 3), (9, 5, 2), (13, 4, 3), (18, 5, 2), (22, 4, 3), (26, 6, 2), (5, 9, 2), (10, 9, 3), (16, 9, 3), (21, 10, 2), (25, 10, 3), (7, 13, 2), (14, 13, 2), (19, 14, 2), (24, 14, 2)):
        ic.rect(x, y, x + s - 1, y + s - 1, BLUEM, 1.0 if s == 3 else 0.0)
    for row, y in enumerate((18.5, 22.5, 26.5)):
        for k in range(6):
            x = 5 + k * 4.4 + (2.2 if row % 2 else 0)
            if x < 28:
                ic.circle(x, y, 1.7, WHT, 1.0)
    frame(ic)


# ---------------------------------------------------------------- 推进之王
@icon("siege", 1)
def siege_charge(ic):
    """冲锋号令（参考原作一技能「冲锋号令·γ」的充能图标）：绿色六边形 + C 与两个加号"""
    tile(ic)
    badge(ic, 6, GREENM, 15.2, 12.8, inner=DARK)
    ic.poly(ngon(15.5, 15.5, 11.8, 6), GREENM, 1.0)
    ic.ring(11.5, 15.5, 3.2, 6.2, WHT, 1.0, a0=45, a1=315)
    for x0, y0 in ((19, 8), (19, 18)):
        ic.rect(x0 + 2, y0, x0 + 3, y0 + 5, WHT, 1.0)
        ic.rect(x0, y0 + 2, x0 + 5, y0 + 3, WHT, 1.0)


@icon("siege", 2)
def siege_aerial(ic):
    """跃空锤（参考原作二技能「跃空锤」）：红色斜向碎片 + 从空中抡下的白色战锤"""
    tile(ic)
    wedge(ic, 10, 21, 30, 22)
    wedge(ic, 10, 21, 215, 30)
    ic.line(26, 3, 16, 15, WHT, w=2.6, shade=1.0)
    ic.poly(rect_pts(12, 19, 14, 8, -40), WHT, 1.0)
    for pts in ([(22, 16), (26, 15), (24, 19)], [(20, 22), (24, 23), (20, 25)], [(4, 9), (8, 10), (5, 12)], [(24, 26), (28, 25), (26, 29)]):
        ic.poly(pts, WHT, 1.0)


@icon("siege", 3)
def siege_skull(ic):
    """碎颅（参考原作三技能「碎颅」）：白框 + 红色半圆 + 斜挥的白色战锤，锤头前炸开冲击"""
    tile(ic)
    ic.circle(24, 6, 17, REDM, 1.0)
    ic.line(26, 28, 18, 15, WHT, w=2.6, shade=1.0)
    ic.poly(rect_pts(15, 10, 14, 7, 32), WHT, 1.0)
    ic.poly(star_pts(6, 13, 6.2, 2.2, 7, deg=-90), WHT, 1.0)
    frame(ic)


# ---------------------------------------------------------------- 斯卡蒂
@icon("skadi", 1)
def skadi_wave_strike(ic):
    """潮涌斩（参考原作「跃浪击」）：红色方块 + 斜斩的白色大剑 + 环绕的浪弧"""
    tile(ic)
    ic.rect(8, 3, 26, 22, REDM, 1.0)
    ic.crescent(15, 17, 13.5, 2.2, -1.6, 12.8, WHT, 1.0)
    blade = [(-11, -2.6), (7, -2.6), (7, 2.6), (-11, 2.6), (-14, 0)]
    ic.poly(rot([(15 + x, 15 + y) for x, y in blade], 15, 15, 45), WHT, 1.0)
    ic.line(19, 26, 26, 19, WHT, w=2.2, shade=1.0)
    ic.line(22, 22, 28, 28, WHT, w=2.4, shade=1.0)


@icon("skadi", 2)
def skadi_heavy(ic):
    """重斩（按原作近卫一技能「迅捷打击」的构图：白框 + 红五边形 + 汇聚的白线）：下劈的大剑"""
    tile(ic)
    house(ic, top=5, shoulder=12)
    for pts in ([(6, 5), (8, 5), (14, 25)], [(25, 5), (27, 5), (17, 25)], [(10, 3), (12, 3), (15, 20)], [(21, 3), (23, 3), (16, 20)]):
        ic.poly(pts, WHT, 0.0)
    ic.poly([(13, 7), (18, 7), (18, 22), (15.5, 28), (13, 22)], WHT, 1.0)
    ic.rect(10, 5, 21, 6, WHT, 1.0)
    frame(ic)


@icon("skadi", 3)
def skadi_tidal(ic):
    """潮汐（参考原作三技能「涌潮悲歌」）：红 X + 卷起的白色巨浪"""
    tile(ic)
    xrays(ic, half=15)
    wave = [(1, 31), (3, 23), (8, 16), (14, 11), (20, 8), (26, 7), (30, 9), (27, 10), (24, 12), (28, 14), (25, 17), (21, 15),
            (18, 18), (16, 23), (17, 31)]
    ic.poly(wave, WHT, 1.0)
    ic.poly([(21, 15), (19, 12), (23, 11)], REDM, 1.0)
    for cx, cy, r in ((26, 21, 1.4), (22, 24, 1.1), (28, 26, 1.2), (24, 28.5, 0.9)):
        ic.circle(cx, cy, r, WHT, 1.0)


# ---------------------------------------------------------------- 归溟幽灵鲨
@icon("specter_unchained", 1)
def specter_skill(ic):
    """求生之技（参考原作一技能）：红 X + 白色漩涡与交错的水带"""
    tile(ic)
    xrays(ic, half=14)
    ic.sweep((1, 13), (5, 3), (18, 1), 1.3, 0.6, WHT, 1.0)
    ic.sweep((30, 18), (26, 28), (13, 30), 1.3, 0.6, WHT, 1.0)
    for k in range(34):
        t = k / 33
        a = math.radians(90 + t * 560)
        r = 1.5 + 9.5 * t
        ic.circle(15.5 + r * math.cos(a), 15.5 - r * math.sin(a), 0.9 + 0.9 * t, WHT, 1.0)


@icon("specter_unchained", 2)
def specter_thirst(ic):
    """求生之渴（参考原作二技能）：红色放射 + 白色水滴（内卷一道红）+ 横过的水带"""
    tile(ic)
    for a in (60, 120, 240, 300, 0, 180):
        wedge(ic, 15.5, 16, a, 10)
    ic.sweep((1, 22), (13, 15), (31, 25), 1.2, 1.2, WHT, 1.0)
    ic.poly([(15.5, 3), (19.5, 10), (22.5, 16), (21.5, 22), (15.5, 26), (9.5, 22), (8.5, 16), (11.5, 10)], WHT, 1.0)
    ic.crescent(15.5, 18.5, 4.2, 1.4, -1.4, 3.4, REDM, 1.0)


@icon("specter_unchained", 3)
def specter_pressure(ic):
    """求生之压（参考原作三技能）：红色放射 + 向外刺出的白色轮 + 底部卷浪"""
    tile(ic)
    for k in range(8):
        wedge(ic, 15.5, 13, k * 45 + 22.5, 11)
    ic.ring(15.5, 13, 4.6, 6.6, WHT, 1.0)
    for k in range(8):
        a = math.radians(k * 45)
        cx, cy = 15.5 + 9 * math.cos(a), 13 + 9 * math.sin(a)
        ic.poly(rot([(cx - 1.6, cy - 1.4), (cx + 2.2, cy), (cx - 1.6, cy + 1.4)], cx, cy, k * 45), WHT, 1.0)
    for cx in (6, 15.5, 25):
        ic.ring(cx, 29, 2.4, 4.4, WHT, 1.0, a0=0, a1=200)


# ---------------------------------------------------------------- 铃兰
def _fox_flame(ic, cx, cy, s=0.45, deg=0.0, rp=WHT, v=1.0):
    pts = flame_pts(cx, cy, s)
    ic.poly(rot(pts, cx, cy, deg) if deg else pts, rp, v)


@icon("suzuran", 1)
def suzuran_volley(ic):
    """狐火连珠（参考原作一技能的构图：红五边形 + 白色三角纹）：五团狐火扇形排开"""
    tile(ic)
    house(ic)
    for a in (158, 124, 90, 56, 22):
        cx = 15.5 + 11 * math.cos(math.radians(a))
        cy = 25.5 - 11 * math.sin(math.radians(a))
        _fox_flame(ic, cx, cy, 0.4, 90 - a)
    ic.poly([(12.5, 23), (18.5, 23), (15.5, 27)], WHT, 1.0)


@icon("suzuran", 2)
def suzuran_warm(ic):
    """暖光（参考原作二技能「童心」：红色斜带 + 圆 + 白色法杖）：法杖前一团暖光"""
    tile(ic)
    ic.poly([(1, 21), (30, 7), (30, 15), (1, 29)], REDM, 0.0)
    ic.circle(19, 12, 7.5, REDM, 1.0)
    for k in range(8):
        a = math.radians(k * 45)
        ic.line(19 + 9 * math.cos(a), 12 + 9 * math.sin(a), 19 + 11 * math.cos(a), 12 + 11 * math.sin(a), WHT, w=1, shade=1.0)
    ic.line(6, 28, 19, 8, WHT, w=1.6, shade=1.0)
    ic.ring(20, 6.5, 1.4, 2.8, WHT, 1.0)
    ic.sweep((18, 9), (13, 9), (11, 14), 1.0, 0.5, WHT, 1.0)
    ic.sweep((21, 9), (25, 12), (24, 17), 1.0, 0.5, WHT, 1.0)


@icon("suzuran", 3)
def suzuran_haze(ic):
    """狐火迷雾（参考原作三技能「狐火渺然」）：白框 + 蓝色方格 + 蜷成一圈的白狐"""
    tile(ic)
    for x in range(3, 29, 4):
        for y in range(3, 29, 4):
            if ((x // 4) + (y // 4)) % 2 == 0:
                ic.rect(x, y, x + 2, y + 2, BLUEM, 1.0)
    ic.ring(15.5, 16.5, 6.4, 10.4, WHT, 1.0, a0=95, a1=395)
    ic.poly([(18, 8), (20, 3), (22, 7), (25, 4), (25.5, 9), (27, 12), (22, 14), (18.5, 11)], WHT, 1.0)
    ic.dot(23, 9, BLACK[0])
    ic.circle(9.8, 23, 2.6, BLUEM, 1.0)
    frame(ic)


# ---------------------------------------------------------------- 乌尔比安
@icon("ulpianus", 1)
def ulpianus_contact(ic):
    """必须接触（参考原作一技能）：左上射来的红 / 灰楔形 + 甩向右下的白色铁锚与速度线"""
    tile(ic)
    wedge(ic, 1, 1, -45, 14)
    wedge(ic, 1, 1, -18, 7, GREYM, 1.0)
    wedge(ic, 1, 1, -72, 7, GREYM, 1.0)
    for x0, y0, L in ((3, 9, 7), (8, 4, 6), (5, 15, 5)):
        ic.line(x0, y0, x0 + L, y0 + L, WHT, w=1, shade=1.0)
    anchor(ic, 18.5, 18.5, deg=-45, s=0.95)


@icon("ulpianus", 2)
def ulpianus_keep(ic):
    """必须坚守（参考原作二技能）：金色五边形 + 带刺的白环 + 竖立的锚"""
    tile(ic)
    house(ic, GOLDM)
    ic.poly(star_pts(15.5, 16.5, 12.5, 8.8, 8, deg=-90), WHT, 1.0)
    ic.circle(15.5, 16.5, 6.6, GOLDM, 1.0)
    ic.line(15.5, 3, 15.5, 29, WHT, w=2.2, shade=1.0)
    ic.line(11, 9, 20, 9, WHT, w=1.8, shade=1.0)
    ic.ring(15.5, 21, 5.0, 6.6, WHT, 1.0, a0=190, a1=350)


@icon("ulpianus", 3)
def ulpianus_open(ic):
    """必须开辟（参考原作三技能）：白框 + 红色放射 + 两侧垂下的锁链与底部的锚"""
    tile(ic)
    wedge(ic, 15.5, 22, 62, 14)
    wedge(ic, 15.5, 22, 118, 14)
    for x in (7, 24):
        for k, y in enumerate(range(3, 21, 4)):
            if k % 2 == 0:
                ic.ring(x + 0.5, y + 1.5, 0.8, 2.2, WHT, 1.0)
            else:
                ic.rect(x, y, x, y + 2, WHT, 1.0)
    anchor(ic, 15.5, 17.5, deg=0, s=0.9)
    frame(ic)


# ---------------------------------------------------------------- 维什戴尔
@icon("wisadel", 1)
def wisadel_barrage(ic):
    """灰烬弹幕（参考原作一技能「局部清算」）：红色放射 + 缺口白环 + 向内的四个三角 + 中心旋涡"""
    tile(ic)
    xrays(ic, half=14)
    for a0 in (0, 90, 180, 270):
        ic.ring(15.5, 15.5, 9.4, 11, WHT, 1.0, a0=a0 + 14, a1=a0 + 76)
    for pts in ([(15.5, 8), (13.2, 3.5), (17.8, 3.5)], [(15.5, 23), (13.2, 27.5), (17.8, 27.5)], [(8, 15.5), (3.5, 13.2), (3.5, 17.8)], [(23, 15.5), (27.5, 13.2), (27.5, 17.8)]):
        ic.poly(pts, WHT, 1.0)
    ic.ring(15.5, 15.5, 3.8, 5.6, WHT, 1.0, a0=0, a1=280)
    ic.ring(15.5, 15.5, 1.0, 2.4, WHT, 1.0, a0=180, a1=460)


@icon("wisadel", 2)
def wisadel_execution(ic):
    """凋零处刑（参考原作三技能「爆裂黎明」）：红 X + 竖起的白色重炮与环，右下一发炮弹"""
    tile(ic)
    xrays(ic, half=14)
    ering(ic, 15.5, 18, 12.5, 5, 1.4, -18)
    ic.rect(14, 3, 17, 22, WHT, 1.0)
    ic.rect(13, 2, 18, 4, WHT, 1.0)
    ic.rect(18, 8, 20, 13, WHT, 1.0)
    ic.rect(11, 12, 13, 15, WHT, 1.0)
    ic.poly([(13, 22), (18, 22), (19, 28), (12, 28)], WHT, 1.0)
    ic.poly([(25, 21), (27, 23), (27, 28), (23, 28), (23, 23)], WHT, 1.0)


@icon("wisadel", 3)
def wisadel_saturation(ic):
    """饱和炮击（参考原作二技能「饱和复仇」）：白框 + 红色大圆 + 斜架的白色重炮与弧"""
    tile(ic)
    ic.poly(star_pts(21, 10, 13, 6.5, 9, deg=-75), REDM, 1.0)
    ic.poly(star_pts(21, 10, 7, 3.5, 9, deg=-55), REDM, 0.0)
    # 重炮：粗炮身 + 细炮管 + 炮口 + 瞄具 + 枪托（斜放，右上指向）
    ic.line(8, 23, 18, 13, WHT, w=5.0, shade=1.0)
    ic.line(17, 14, 26, 5, WHT, w=2.6, shade=1.0)
    ic.line(24, 4, 28, 8, WHT, w=2.2, shade=1.0)
    ic.poly(rot([(13, 12), (18, 12), (18, 15), (13, 15)], 15.5, 13.5, -45), WHT, 1.0)
    ic.line(5, 21, 10, 26, WHT, w=3.0, shade=1.0)
    ic.line(12, 22, 14, 26, WHT, w=1.8, shade=1.0)
    ic.line(11, 19, 15, 23, REDM, w=1, shade=0.0)
    frame(ic)


# ================================================================ 出图
def render_all(only=None):
    out = {}
    for (op, n), fn in ICONS.items():
        if only and op not in only:
            continue
        ic = Icon()
        fn(ic)
        out[(op, n)] = ic.render()
    return out


def preview(imgs, path, scale=6):
    """放大预览：每名干员一行（三个图标 ×scale），右边再各画一个 HUD 实际大小（24px 格子里 20px）×4 的样子"""
    ops = []
    for op, _n in imgs:
        if op not in ops:
            ops.append(op)
    cell = W * scale
    hud = 24 * 4
    pad = 12
    row_h = cell + pad + 16
    sheet = Image.new("RGB", (pad + 3 * (cell + pad) + 3 * (hud + pad) + 120, pad + len(ops) * row_h), (28, 32, 40))
    d = ImageDraw.Draw(sheet)
    for r, op in enumerate(ops):
        y = pad + r * row_h
        d.text((pad, y), op, fill=(255, 230, 120))
        for n in (1, 2, 3):
            im = imgs.get((op, n))
            if im is None:
                continue
            x = pad + (n - 1) * (cell + pad)
            bg = Image.new("RGBA", (cell, cell), (18, 22, 28, 255))
            bg.alpha_composite(im.resize((cell, cell), Image.NEAREST))
            sheet.paste(bg.convert("RGB"), (x, y + 14))
            # HUD：暗格 24×24，图标画成 20×20（最近邻），再整体放大 4 倍
            hx = pad + 3 * (cell + pad) + (n - 1) * (hud + pad)
            cellimg = Image.new("RGBA", (24, 24), (10, 12, 15, 255))
            cellimg.alpha_composite(im.resize((20, 20), Image.NEAREST), (2, 2))
            sheet.paste(cellimg.resize((hud, hud), Image.NEAREST).convert("RGB"), (hx, y + 14))
    sheet.save(path)


def out_name(op, n):
    """贴图名（不含 .png）：水月是最早的干员，沿用 skill_s1/2/3（JSON 与成长节点都引用这个名字）"""
    return "skill_s%d" % n if op == "mizuki" else "skill_%s_s%d" % (op, n)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    ap.add_argument("--preview", default="")
    ap.add_argument("--no-write", action="store_true")
    a = ap.parse_args()
    only = [s for s in a.only.split(",") if s]
    imgs = render_all(only)
    if not a.no_write:
        for (op, n), im in imgs.items():
            im.save(os.path.join(OUT_DIR, out_name(op, n) + ".png"))
    if a.preview:
        preview(imgs, a.preview)
    print("%d 个图标%s" % (len(imgs), "" if a.no_write else " → " + OUT_DIR))


if __name__ == "__main__":
    main()
