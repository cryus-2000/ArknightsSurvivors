"""深渊巨斩专用贴图 proj_tide_blade_abyss.png（96×72 × 4 帧 @12fps，锚点 (48,36) 中心，朝右）。

之前巨斩只是把 32×24 的普通水刃放大 3 倍再染紫，边缘发糊、层次单薄。这里按 3 倍尺寸重画：
厚月牙 + 四层色带（外缘深渊黑紫 → 紫 → 亮紫 → 金白刃口）、沿刃口流动的金色能量、
内侧的暗色水流纹、尾部拖曳的水珠与碎光。二值 alpha，最近邻放大 ×2 显示。
"""
from PIL import Image
import math, os, random

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "..", "art", "incoming", "proj_tide_blade_abyss.png")
W, H, FRAMES = 96, 72, 4
rnd = random.Random(11)

# 色带（从刃口到外缘）
GOLD_W = (255, 246, 205)
GOLD = (255, 214, 110)
VIOLET_L = (214, 160, 255)
VIOLET = (150, 88, 230)
PURPLE = (92, 40, 170)
ABYSS = (40, 16, 78)
RIM = (14, 8, 30)
WATER = (120, 200, 255)
WHITE = (255, 255, 255)


def crescent_field(x, y):
    """返回 (在月牙内?, 距刃口 0..1, 沿刃口角度 -1..1)。外圆 (44,36) r30，内圆 (30,36) r27。"""
    ox, oy, orad = 44.0, 36.0, 30.0
    ix, iy, irad = 30.0, 36.0, 27.0
    dxo, dyo = x + 0.5 - ox, y + 0.5 - oy
    do = math.hypot(dxo, dyo)
    di = math.hypot(x + 0.5 - ix, y + 0.5 - iy)
    if do > orad or di < irad:
        return False, 0.0, 0.0
    # 厚度方向：从外缘(刃口) 0 到内缘 1
    outer_gap = orad - do
    inner_gap = di - irad
    t = outer_gap / max(0.5, outer_gap + inner_gap)
    ang = math.atan2(dyo, dxo) / (math.pi / 2)   # 右侧 0，上 -1，下 +1
    return True, t, ang


def frame(fi):
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    p = im.load()
    phase = fi / FRAMES
    for y in range(H):
        for x in range(W):
            inside, t, ang = crescent_field(x, y)
            if not inside:
                continue
            # 沿刃口流动的一段白光（每帧推进），以及缓慢的明暗呼吸
            spark = abs(((ang + 1.0) / 2.0 - phase) % 1.0 - 0.5) < 0.09
            breath = 0.5 + 0.5 * math.sin((ang * 1.5 + phase) * math.pi)
            # 内侧的暗色水流纹：顺着月牙弧向的细纹
            ripple = math.sin((ang * 7.0 - t * 2.5 + phase * 2.0) * math.pi) > 0.85
            if t < 0.17:
                c = GOLD_W if spark else GOLD
            elif t < 0.34:
                c = GOLD if (spark and t < 0.24) else VIOLET_L
            elif t < 0.60:
                c = VIOLET if breath < 0.7 or t > 0.5 else VIOLET_L
            elif t < 0.84:
                c = PURPLE if not ripple else ABYSS
            elif t < 0.94:
                c = ABYSS
            else:
                c = RIM
            # 月牙两端尖处收成金色
            if abs(ang) > 0.9 and t < 0.6:
                c = GOLD if abs(ang) > 0.95 else VIOLET_L
            p[x, y] = (*c, 255)
    # 刃口高光点（随帧沿刃口移动）
    for k in range(3):
        a = ((k / 3.0 + phase * 0.5) % 1.0) * 1.7 - 0.85
        ex = int(44 + 29.0 * math.cos(a * math.pi / 2))
        ey = int(36 + 29.0 * math.sin(a * math.pi / 2))
        for dx, dy in ((0, 0), (-1, 0), (1, 0), (0, -1), (0, 1)):
            if 0 <= ex + dx < W and 0 <= ey + dy < H and p[ex + dx, ey + dy][3]:
                p[ex + dx, ey + dy] = (*WHITE, 255)
    # 尾部拖曳：水平拉长的水痕 + 水珠 + 碎光（月牙左侧，越远越稀越小）
    rs = random.Random(100 + fi)
    for k in range(22):
        dist = rs.uniform(2, 40)
        spread = 30.0 * (1.0 - dist / 55.0)
        yy = int(36 + rs.uniform(-spread, spread))
        xx = int(30 - dist + rs.uniform(-2, 2))
        if not (0 <= xx < W and 0 <= yy < H):
            continue
        r = rs.random()
        col = WATER if r < 0.5 else (VIOLET_L if r < 0.8 else GOLD)
        if dist < 22 and rs.random() < 0.55:
            ln = rs.randint(3, 7)          # 水痕：向左拖长的短线
            pts = [(xx - i, yy) for i in range(ln)]
            if rs.random() < 0.5:
                pts += [(xx - i, yy + 1) for i in range(ln // 2)]
        elif rs.random() < 0.4:
            pts = [(xx, yy), (xx + 1, yy), (xx, yy + 1), (xx + 1, yy + 1)]
        else:
            pts = [(xx, yy)]
        for (qx, qy) in pts:
            if 0 <= qx < W and 0 <= qy < H and p[qx, qy][3] == 0:
                p[qx, qy] = (*col, 255)
    # 月牙内侧贴着内缘的一圈青色水光（被撕开的水面），断续
    for i in range(80):
        a = (-0.7 + 1.4 * i / 79.0) * math.pi / 2
        ex = int(30 + 25.3 * math.cos(a)); ey = int(36 + 25.3 * math.sin(a))
        if 0 <= ex < W and 0 <= ey < H and p[ex, ey][3] == 0 and (i + fi * 2) % 7 < 4:
            p[ex, ey] = (*WATER, 255)
    return im


strip = Image.new("RGBA", (W * FRAMES, H), (0, 0, 0, 0))
for i in range(FRAMES):
    strip.paste(frame(i), (i * W, 0))
strip.save(OUT)
print("saved", OUT, strip.size)
