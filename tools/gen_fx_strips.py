# -*- coding: utf-8 -*-
"""docs/54 §6 的五条事件特效帧条（程序生成版，固定种子、可重复；二值 alpha，同现有 fx_*；@2x 为严格 2 倍最近邻）。

写到 art/incoming/：
  fx_beacon_ignite   64×64 × 8 帧 16 fps：灯标点燃——暖白核心先聚后炸，外扩棋盘点光晕 + 8 道放射，末两帧散成火星。加色层。
  fx_ember           8×8 × 4 帧：余烬（亮 → 暖 → 橙 → 暗红一粒）；游戏里按 mote 的颜色调制，一张通用。
  fx_mire_dissolve   64×64 × 6 帧 8 fps：溟痕退散——和 terrain_mire 同尺寸的深紫污斑，边缘先碎、中心最后，退散前沿一圈洋红。
  fx_levelup_pillar  32×160 × 6 帧 12 fps：升级光柱——底部亮、顶部散（棋盘点消散），先涨后收成几缕。加色层。
  fx_elite_spawn     96×48 × 6 帧 ≈ 6.7 fps：精英登场地纹——地面椭圆裂纹（洋红）→ 光涌（白芯环 + 竖光）→ 散。

调色：灯标 / 升级用灯火暖色（#FFC46B / #FF8A3D / BEACON_COL #FFC76B），溟痕用海嗣紫（#8A5CD6 / #C9A6FF），
精英用 UI.RED 洋红（#FF3D8B）。全部只有 0 / 255 两种 alpha，柔光靠棋盘点（和 fx_logos_glyph 的晕光一样）。

用法：python tools/gen_fx_strips.py [--preview [目录]]
  --preview 另写 build/fxstrips/contact.png：五条帧条各一行，1x 与 4x。
"""
import os, sys, math, random
from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
OUT = os.path.join(ROOT, "art", "incoming")
PREV = os.path.join(ROOT, "build", "fxstrips")

CLEAR = (0, 0, 0, 0)
# 灯火暖色（docs/11 / world.BEACON_COL）
W_CORE = (0xFF, 0xF6, 0xE0, 255)
W_PALE = (0xFF, 0xE8, 0xB0, 255)
W_GOLD = (0xFF, 0xC4, 0x6B, 255)
W_ORNG = (0xFF, 0x8A, 0x3D, 255)
W_DEEP = (0xB8, 0x50, 0x1E, 255)
W_DARK = (0x7A, 0x20, 0x30, 255)
# 海嗣紫（溟痕）
M_BASE = (0x15, 0x08, 0x20, 255)
M_MID = (0x3A, 0x1C, 0x5A, 255)
M_VIO = (0x8A, 0x5C, 0xD6, 255)
M_LITE = (0xC9, 0xA6, 0xFF, 255)
M_HI = (0xEE, 0xE0, 0xFF, 255)
# 升级金
G_HI = (0xFF, 0xF1, 0xC0, 255)
G_GOLD = (0xFF, 0xC4, 0x6B, 255)
G_MID = (0xF4, 0xC0, 0x4E, 255)
G_DEEP = (0xB8, 0x80, 0x1E, 255)
# 精英洋红（UI.RED #FF3D8B）
E_HI = (0xFF, 0xE0, 0xF0, 255)
E_LITE = (0xFF, 0x9A, 0xD0, 255)
E_MAG = (0xFF, 0x3D, 0x8B, 255)
E_DEEP = (0x8A, 0x1C, 0x50, 255)

SPECS = {   # 名字: (帧宽, 帧高, 帧数, fps)——和 game.gd V6_FRAMES 登记的一致
    "fx_beacon_ignite": (64, 64, 8, 16.0),
    "fx_ember": (8, 8, 4, 8.0),
    "fx_mire_dissolve": (64, 64, 6, 8.0),
    "fx_levelup_pillar": (32, 160, 6, 12.0),
    "fx_elite_spawn": (96, 48, 6, 6.7),
}


# ---------------------------------------------------------------- 像素助手（px: dict (x,y)->RGBA）
def put(px, x, y, c):
    px[(int(x), int(y))] = c


def disc(px, cx, cy, r, c, sy=1.0, dither=False, rmin=0.0):
    """实心圆（sy < 1 压成椭圆）；dither 时只填棋盘格；rmin 为内径（环带）。"""
    R = int(math.ceil(r)) + 1
    for y in range(int(cy - R * sy) - 1, int(cy + R * sy) + 2):
        for x in range(int(cx - R) - 1, int(cx + R) + 2):
            d = math.hypot(x + 0.5 - cx, (y + 0.5 - cy) / max(sy, 1e-3))
            if rmin <= d <= r and (not dither or (x + y) % 2 == 0):
                put(px, x, y, c)


def line(px, x0, y0, x1, y1, c, w=1):
    n = int(max(abs(x1 - x0), abs(y1 - y0))) + 1
    for i in range(n):
        t = i / max(1, n - 1)
        x, y = x0 + (x1 - x0) * t, y0 + (y1 - y0) * t
        put(px, round(x), round(y), c)
        if w >= 2:
            put(px, round(x) + (1 if abs(y1 - y0) > abs(x1 - x0) else 0), round(y) + (0 if abs(y1 - y0) > abs(x1 - x0) else 1), c)


def blit(im, px, dx, dy, w, h):
    for (x, y), c in px.items():
        x += dx
        if 0 <= x - dx < w and 0 <= y < h:
            im.putpixel((x, y), c)


def strip(name, draw_frame):
    fw, fh, n, _ = SPECS[name]
    im = Image.new("RGBA", (fw * n, fh), CLEAR)
    for f in range(n):
        px = {}
        draw_frame(px, f)
        blit(im, px, f * fw, 0, fw, fh)
    return im


# ---------------------------------------------------------------- ① 灯标点燃 64×64 × 8
def beacon_frame(px, f):
    cx = cy = 32.0
    rnd = random.Random(540 + f)
    if f == 0:            # 聚光：小核心 + 四粒向心火星
        disc(px, cx, cy, 2.5, W_CORE)
        disc(px, cx, cy, 4.5, W_GOLD, rmin=2.5, dither=True)
        for q in range(4):
            a = q * math.pi / 2 + 0.4
            put(px, cx + math.cos(a) * 9, cy + math.sin(a) * 9, W_PALE)
    elif f == 1:          # 核心涨大 + 细环
        disc(px, cx, cy, 5.0, W_CORE)
        disc(px, cx, cy, 7.5, W_PALE, rmin=5.0)
        disc(px, cx, cy, 11.0, W_GOLD, rmin=9.5)
    elif f == 2:          # 炸开：实心暖核 + 8 道短放射
        disc(px, cx, cy, 11.0, W_GOLD)
        disc(px, cx, cy, 8.0, W_PALE)
        disc(px, cx, cy, 5.0, W_CORE)
        for q in range(8):
            a = q * math.pi / 4
            line(px, cx + math.cos(a) * 13, cy + math.sin(a) * 13, cx + math.cos(a) * 20, cy + math.sin(a) * 20, W_PALE, 2)
    elif f in (3, 4):     # 最大：棋盘光晕到 27 / 30，放射拉长，核心仍白
        R = 27 if f == 3 else 30
        disc(px, cx, cy, R, W_ORNG, dither=True, rmin=R - 6)
        disc(px, cx, cy, R - 6, W_GOLD, dither=True, rmin=16)
        disc(px, cx, cy, 16, W_GOLD)
        disc(px, cx, cy, 11, W_PALE)
        disc(px, cx, cy, 6 if f == 3 else 5, W_CORE)
        for q in range(8):
            a = q * math.pi / 4 + (0.0 if f == 3 else 0.2)
            L = 29 if f == 3 else 31
            line(px, cx + math.cos(a) * 17, cy + math.sin(a) * 17, cx + math.cos(a) * L, cy + math.sin(a) * L, W_CORE if q % 2 == 0 else W_PALE, 2 if f == 3 else 1)
    elif f == 5:          # 收：外晕变薄环，核心转暖
        disc(px, cx, cy, 30, W_ORNG, dither=True, rmin=26)
        disc(px, cx, cy, 20, W_GOLD, dither=True, rmin=12)
        disc(px, cx, cy, 12, W_GOLD)
        disc(px, cx, cy, 7, W_PALE)
        disc(px, cx, cy, 3, W_CORE)
        for q in range(8):
            a = q * math.pi / 4 + 0.4
            line(px, cx + math.cos(a) * 22, cy + math.sin(a) * 22, cx + math.cos(a) * 28, cy + math.sin(a) * 28, W_ORNG)
    elif f == 6:          # 散：稀疏环 + 火星
        disc(px, cx, cy, 31, W_DEEP, dither=True, rmin=29)
        disc(px, cx, cy, 8, W_GOLD, dither=True, rmin=4)
        disc(px, cx, cy, 4, W_PALE)
        for q in range(14):
            a = rnd.random() * math.tau
            d = rnd.uniform(14, 27)
            put(px, cx + math.cos(a) * d, cy + math.sin(a) * d * 0.9 - 2, W_ORNG if q % 3 else W_PALE)
    else:                 # 余烬几粒上浮
        disc(px, cx, cy, 2.5, W_GOLD, dither=True)
        for q in range(9):
            a = rnd.random() * math.tau
            d = rnd.uniform(10, 26)
            put(px, cx + math.cos(a) * d, cy + math.sin(a) * d * 0.8 - 6, W_DEEP if q % 2 else W_ORNG)


# ---------------------------------------------------------------- ② 余烬 8×8 × 4
def ember_frame(px, f):
    if f == 0:
        for (x, y) in [(3, 3), (4, 3), (3, 4), (4, 4)]:
            put(px, x, y, W_CORE)
        for (x, y) in [(2, 3), (5, 4), (3, 2), (4, 5)]:
            put(px, x, y, W_PALE)
        for (x, y) in [(2, 4), (5, 3), (4, 2), (3, 5)]:
            put(px, x, y, W_GOLD)
    elif f == 1:
        for (x, y) in [(3, 3), (4, 3), (3, 4), (4, 4)]:
            put(px, x, y, W_PALE)
        for (x, y) in [(2, 3), (5, 4), (3, 2), (4, 5)]:
            put(px, x, y, W_ORNG)
    elif f == 2:
        for (x, y) in [(3, 3), (4, 3), (3, 4), (4, 4)]:
            put(px, x, y, W_ORNG)
        put(px, 5, 3, W_DEEP)
        put(px, 3, 5, W_DEEP)
    else:
        put(px, 3, 4, W_DEEP)
        put(px, 4, 3, W_DARK)


# ---------------------------------------------------------------- ③ 溟痕退散 64×64 × 6
def _mire_blob():
    """固定的污斑形状：半径 ~28 的圆加 5 个瓣（种子固定）；返回 (x,y)->归一化「深度」（0 边缘 … 1 中心）。"""
    rnd = random.Random(5403)
    lobes = [(rnd.uniform(0, math.tau), rnd.uniform(0.12, 0.3), rnd.choice([2, 3, 3, 4])) for _ in range(5)]
    out = {}
    cx = cy = 32.0
    for y in range(64):
        for x in range(64):
            dx, dy = x + 0.5 - cx, y + 0.5 - cy
            d = math.hypot(dx, dy)
            a = math.atan2(dy, dx)
            r = 25.0
            for (pa, amp, k) in lobes:
                r += 28.0 * amp * max(0.0, math.cos((a - pa) * k)) ** 2
            r = min(r, 31.0)
            if d < r:
                out[(x, y)] = 1.0 - d / r
    return out


MIRE_BLOB = _mire_blob()


def _value_noise(w, h, cell, seed):
    """平滑值噪声（cell 像素一格、双线性插值），边缘碎裂用它而不是逐像素随机（否则像雪花点）。"""
    rnd = random.Random(seed)
    gw, gh = w // cell + 2, h // cell + 2
    grid = [[rnd.random() for _ in range(gw)] for _ in range(gh)]
    out = {}
    for y in range(h):
        for x in range(w):
            fx, fy = x / cell, y / cell
            ix, iy = int(fx), int(fy)
            tx, ty = fx - ix, fy - iy
            tx, ty = tx * tx * (3 - 2 * tx), ty * ty * (3 - 2 * ty)
            a = grid[iy][ix] * (1 - tx) + grid[iy][ix + 1] * tx
            b = grid[iy + 1][ix] * (1 - tx) + grid[iy + 1][ix + 1] * tx
            out[(x, y)] = a * (1 - ty) + b * ty
    return out


MIRE_NOISE = _value_noise(64, 64, 6, 5404)


def mire_frame(px, f):
    rnd = random.Random(5410 + f)
    k = f / 5.0                     # 0 完整 … 1 几乎没了
    noise = {p: MIRE_NOISE[p] for p in MIRE_BLOB}
    thr = k * 1.15                  # 深度 < thr 的被退散掉（边缘先碎，中心最后）
    front = set()
    for p, depth in MIRE_BLOB.items():
        dd = depth + (noise[p] - 0.5) * 0.5
        if dd >= thr:
            # 底色：中心略亮的两层
            c = M_MID if depth > 0.45 and noise[p] > 0.55 else M_BASE
            put(px, p[0], p[1], c)
            if dd - thr < 0.12:
                front.add(p)
    # 退散前沿：洋红一圈（前沿像素里取棋盘 + 全亮两档），f=0 时只是暗紫边
    for p in front:
        if f == 0:
            if (p[0] + p[1]) % 2 == 0:
                put(px, p[0], p[1], M_MID)
        else:
            put(px, p[0], p[1], M_VIO if (p[0] + p[1]) % 2 == 0 else M_LITE)
    # 紫色筋络（固定几条）与亮点，随退散减少
    veins = [((20, 22), (30, 34)), ((44, 20), (34, 30)), ((24, 44), (33, 33)), ((46, 42), (36, 36)), ((32, 14), (32, 26))]
    for i, (a, b) in enumerate(veins):
        if i < 5 - f:
            for t in range(0, 11):
                x = a[0] + (b[0] - a[0]) * t / 10.0
                y = a[1] + (b[1] - a[1]) * t / 10.0
                if (round(x), round(y)) in px and t % 2 == 0:
                    put(px, round(x), round(y), M_VIO)
    # 上浮紫尘：随帧上升、变多后变少
    n = [3, 6, 9, 9, 6, 4][f]
    for q in range(n):
        a = rnd.random() * math.tau
        d = rnd.uniform(6, 26) * (1.0 - 0.5 * k)
        x, y = 32 + math.cos(a) * d, 32 + math.sin(a) * d * 0.8 - 8 * k - rnd.uniform(0, 6)
        if 0 <= x < 64 and 0 <= y < 64:
            put(px, x, y, M_LITE if q % 2 else M_HI)
    if f == 5:   # 最后一帧只剩中心一撮
        for p in list(px):
            if MIRE_BLOB.get(p, 1.0) < 0.75 and px[p] in (M_BASE, M_MID):
                del px[p]


# ---------------------------------------------------------------- ④ 升级光柱 32×160 × 6
def pillar_frame(px, f):
    cx = 16.0
    H = 160
    rnd = random.Random(5420 + f)
    # (柱高, 外半宽, 内半宽, 底部光斑半径, 顶端消散起点比例)
    h, wo, wi, rb, top = [(70, 4, 2, 7, 0.55), (130, 6, 3, 10, 0.5), (158, 7, 4, 12, 0.45),
                          (158, 6, 3, 10, 0.3), (150, 4, 2, 7, 0.2), (140, 2, 1, 4, 0.0)][f]
    y0 = H - 6                # 脚底
    for y in range(y0 - h, y0):
        u = (y0 - y) / float(h)          # 0 底 … 1 顶
        fade = u > top                     # 顶部消散段
        wo_y = wo * (1.0 - 0.35 * u)
        wi_y = wi * (1.0 - 0.5 * u)
        for x in range(int(cx - wo_y - 1), int(cx + wo_y + 2)):
            d = abs(x + 0.5 - cx)
            if d > wo_y:
                continue
            if fade:
                # 消散：越靠上保留越少（棋盘 + 随机抽稀）
                keep = (1.0 - (u - top) / max(1e-3, 1.0 - top))
                if (x + y) % 2 != 0 or rnd.random() > keep + 0.25:
                    continue
            if d <= wi_y:
                c = G_HI if (f in (1, 2, 3) and u < 0.6) else G_GOLD
            elif d <= wi_y + 1.5:
                c = G_GOLD if not fade else G_MID
            else:
                if (x + y) % 2 != 0 and f != 2:
                    continue
                c = G_MID if u < 0.5 else G_DEEP
            put(px, x, y, c)
    # 底部光斑（椭圆、棋盘外圈）
    if rb > 0:
        disc(px, cx, y0 - 1, rb, G_MID, sy=0.4, dither=True)
        disc(px, cx, y0 - 1, rb * 0.6, G_GOLD, sy=0.4)
        disc(px, cx, y0 - 1, rb * 0.3, G_HI, sy=0.4)
    # 柱身旁上升的金尘
    n = [2, 5, 8, 8, 6, 5][f]
    for q in range(n):
        x = cx + rnd.choice([-1, 1]) * rnd.uniform(wo + 1, wo + 6)
        y = y0 - rnd.uniform(10, h * 0.9) - f * 6
        if 0 <= x < 32 and 0 <= y < H:
            put(px, x, y, G_HI if q % 3 == 0 else G_GOLD)


# ---------------------------------------------------------------- ⑤ 精英登场地纹 96×48 × 6
def elite_frame(px, f):
    cx, cy = 48.0, 24.0
    SY = 0.5
    rnd = random.Random(5430 + f)
    cracks = []
    rr = random.Random(5431)
    for q in range(9):
        a = q * math.tau / 9 + rr.uniform(-0.2, 0.2)
        L = rr.uniform(14, 26)
        cracks.append((a, L, rr.uniform(-0.5, 0.5)))

    def crack(a, L, bend, c, frac):
        x, y = cx, cy
        steps = int(L * frac)
        for i in range(steps):
            a2 = a + bend * (i / max(1, L)) + (0.6 if i % 5 == 2 else -0.4 if i % 7 == 4 else 0.0)
            x += math.cos(a2)
            y += math.sin(a2) * SY
            put(px, round(x), round(y), c)

    if f == 0:            # 裂开：地面暗斑 + 暗洋红裂纹
        disc(px, cx, cy, 16, E_DEEP, sy=SY, dither=True)
        for (a, L, b) in cracks:
            crack(a, L, b, E_DEEP, 0.7)
        disc(px, cx, cy, 2, E_MAG, sy=SY)
    elif f == 1:          # 裂纹发亮，内圈冒光
        disc(px, cx, cy, 20, E_DEEP, sy=SY, dither=True)
        for (a, L, b) in cracks:
            crack(a, L, b, E_MAG, 1.0)
        disc(px, cx, cy, 6, E_LITE, sy=SY, rmin=4)
        disc(px, cx, cy, 3, E_HI, sy=SY)
    elif f == 2:          # 光涌：环 28 + 白芯 + 竖光
        for (a, L, b) in cracks:
            crack(a, L, b, E_LITE, 1.0)
        disc(px, cx, cy, 28, E_MAG, sy=SY, rmin=26)
        disc(px, cx, cy, 14, E_LITE, sy=SY, rmin=12)
        disc(px, cx, cy, 5, E_HI, sy=SY)
        for q in range(8):
            a = q * math.tau / 8 + 0.4
            x, y = cx + math.cos(a) * 27, cy + math.sin(a) * 27 * SY
            line(px, x, y, x, y - 10, E_LITE if q % 2 else E_HI)
    elif f == 3:          # 最大：环 40，竖光拉长，外圈棋盘
        disc(px, cx, cy, 44, E_DEEP, sy=SY, rmin=41, dither=True)
        disc(px, cx, cy, 40, E_MAG, sy=SY, rmin=38)
        disc(px, cx, cy, 39, E_HI, sy=SY, rmin=38)
        disc(px, cx, cy, 24, E_LITE, sy=SY, rmin=23, dither=True)
        for (a, L, b) in cracks:
            crack(a, L, b, E_MAG, 0.8)
        disc(px, cx, cy, 4, E_HI, sy=SY, dither=True)
        for q in range(8):
            a = q * math.tau / 8 + 0.4
            x, y = cx + math.cos(a) * 38, cy + math.sin(a) * 38 * SY
            line(px, x, y, x, y - 18, E_HI if q % 2 else E_LITE)
            put(px, x, y - 19, E_MAG)
    elif f == 4:          # 散：环 46 变薄、棋盘；竖光短
        disc(px, cx, cy, 45, E_MAG, sy=SY, rmin=43, dither=True)
        disc(px, cx, cy, 30, E_DEEP, sy=SY, rmin=29, dither=True)
        for q in range(8):
            a = q * math.tau / 8 + 0.6
            x, y = cx + math.cos(a) * 44, cy + math.sin(a) * 44 * SY
            line(px, x, y - 2, x, y - 8, E_LITE if q % 2 else E_MAG)
        for q in range(10):
            a = rnd.random() * math.tau
            d = rnd.uniform(10, 40)
            put(px, cx + math.cos(a) * d, cy + math.sin(a) * d * SY - rnd.uniform(0, 6), E_LITE)
    else:                 # 余光几粒
        disc(px, cx, cy, 46, E_DEEP, sy=SY, rmin=45, dither=True)
        for q in range(8):
            a = rnd.random() * math.tau
            d = rnd.uniform(20, 44)
            put(px, cx + math.cos(a) * d, cy + math.sin(a) * d * SY - rnd.uniform(2, 10), E_MAG if q % 2 else E_LITE)


# ----------------------------------------------------------------
GEN = {
    "fx_beacon_ignite": beacon_frame,
    "fx_ember": ember_frame,
    "fx_mire_dissolve": mire_frame,
    "fx_levelup_pillar": pillar_frame,
    "fx_elite_spawn": elite_frame,
}


def _x2(im):
    return im.resize((im.width * 2, im.height * 2), Image.NEAREST)


def check(im, name):
    fw, fh, n, _ = SPECS[name]
    assert im.size == (fw * n, fh), (name, im.size)
    vals = set(im.getchannel("A").getdata())
    assert vals <= {0, 255}, (name, vals)


def preview(ims, out_dir):
    os.makedirs(out_dir, exist_ok=True)
    bg = (28, 30, 44, 255)
    rows = []
    for name, im in ims.items():
        rows.append(im)
        rows.append(im.resize((im.width * 4, im.height * 4), Image.NEAREST))
    W = max(r.width for r in rows) + 16
    H = sum(r.height + 8 for r in rows) + 8
    sheet = Image.new("RGBA", (W, H), bg)
    y = 8
    for r in rows:
        sheet.paste(r, (8, y), r)
        y += r.height + 8
    p = os.path.join(out_dir, "contact.png")
    sheet.save(p)
    return p


def main():
    ims = {}
    for name, fn in GEN.items():
        im = strip(name, fn)
        check(im, name)
        im.save(os.path.join(OUT, name + ".png"))
        _x2(im).save(os.path.join(OUT, name + "@2x.png"))
        ims[name] = im
        print("wrote", name, im.size)
    if "--preview" in sys.argv:
        i = sys.argv.index("--preview")
        d = sys.argv[i + 1] if i + 1 < len(sys.argv) and not sys.argv[i + 1].startswith("--") else PREV
        print("preview:", preview(ims, d))


if __name__ == "__main__":
    main()
