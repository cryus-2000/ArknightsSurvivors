"""HUD 灯火图标：煤油马灯四档动画帧（用户 11-05「更像蜡烛，没有煤油灯的感觉，可以用生图工具」）。
底图：pixgen（Gemini gemini-3.1-flash-image）出的未点燃马灯，像素化到 64（build/imagegen/lamp_hurricane/pix_1793797469_1.png）。
本脚本只改玻璃罩里的像素：罩内亮色玻璃按档位重新着色（离火越近越亮），铁丝护网保持深色压在光上；
灯芯上画一簇煤油火（宽、矮、圆头，蓝色火根）；外圈加一层柔光。寂灭档：玻璃转冷灰，灯芯一粒洋红余烬，顶上冒一缕烟。
出：<out>/lantern_<档>.png（30 帧横排帧条，每帧 96×88，支点 = 底座中心 (48, 84)）+ lantern_<档>.json。
用法：python hud_lantern_1105.py <底图 png> <输出目录>"""
import colorsys, json, math, os, sys
from PIL import Image, ImageFilter

SRC, OUT = sys.argv[1], sys.argv[2]
FW, FH, N = 96, 88, 30
OX, OY = 16, 20                       # 64 底图在帧里的偏移
GX, GY, GRX, GRY = 30, 34, 11.5, 8.0  # 玻璃罩椭圆（底图坐标）
WX, WY = 30, 39                       # 灯芯
TIERS = {'lit': 90, 'sway': 50, 'dim': 18, 'out': 0}


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(len(a)))


def loopn(i, seed, *freqs):
    """无缝循环的噪声：整数频率正弦之和，-1..1"""
    t = i / N
    v = sum(math.sin(2 * math.pi * (f * t) + seed * (k + 1) * 1.7) / (k + 1) for k, f in enumerate(freqs))
    return v / sum(1 / (k + 1) for k in range(len(freqs)))


def is_glass(px, x, y):
    r, g, b, a = px
    if a < 128:
        return False
    if ((x - GX) / GRX) ** 2 + ((y - GY) / GRY) ** 2 > 1.0:
        return False
    h, l, s = colorsys.rgb_to_hls(r / 255, g / 255, b / 255)
    return l > 0.42 and s < 0.35


def frame(base, glass, tier, i):
    lv = TIERS[tier]
    fl = 1.0 + 0.10 * loopn(i, 1, 3, 7) + (0.22 * loopn(i, 5, 5, 11) if tier == 'dim' else 0)
    sway = loopn(i, 2, 2, 5) * (0.6 if tier == 'lit' else 1.0)
    im = Image.new('RGBA', (FW, FH), (0, 0, 0, 0))
    # 柔光（先画在底下）
    glow = Image.new('RGBA', (FW, FH), (0, 0, 0, 0))
    if tier != 'out':
        k = {'lit': 1.0, 'sway': 0.62, 'dim': 0.32}[tier] * fl
        col = {'lit': (255, 190, 90), 'sway': (250, 170, 80), 'dim': (230, 110, 60)}[tier]
        R = {'lit': 40, 'sway': 30, 'dim': 20}[tier]
        g = glow.load()
        for y in range(FH):
            for x in range(FW):
                d = math.hypot(x - (OX + GX), (y - (OY + GY + 1)) * 1.1) / R
                if d < 1:
                    a = int(200 * k * (1 - d) ** 2.0)
                    g[x, y] = (*col, min(255, a))
        im.alpha_composite(glow)
    lay = Image.new('RGBA', (FW, FH), (0, 0, 0, 0))
    lay.paste(base, (OX, OY))
    p = lay.load()
    # 玻璃重新着色
    fcx, fcy = WX + sway * 0.4, WY - 3
    for (x, y) in glass:
        d = min(1.0, math.hypot(x - fcx, (y - fcy) * 1.25) / 12.0)
        if tier == 'out':
            c = lerp((112, 124, 134), (64, 72, 82), d)
        elif tier == 'dim':
            c = lerp((206, 112, 66), (88, 46, 40), min(1, d * 1.15 / max(0.4, fl)))
        else:
            near, far = ((255, 252, 228), (244, 176, 72)) if tier == 'lit' else ((252, 220, 150), (176, 104, 48))
            c = lerp(near, far, min(1, d / (fl * (1.0 if tier == 'lit' else 0.85))))
        # 左上一道玻璃高光
        if tier != 'dim' and -5.5 < (x - GX) < -3.5 and -5 < (y - GY) < 1:
            c = lerp(c, (255, 255, 255), 0.45 if tier != 'out' else 0.25)
        p[OX + x, OY + y] = (*c, 255)
    # 铁框受光：玻璃罩外 3 像素内的不透明像素朝暖色偏
    if tier != 'out':
        kk = {'lit': 0.42, 'sway': 0.28, 'dim': 0.16}[tier] * fl
        warm = (255, 190, 100) if tier != 'dim' else (220, 100, 60)
        gs = set(glass)
        for y in range(base.size[1]):
            for x in range(base.size[0]):
                if (x, y) in gs:
                    continue
                e = math.hypot((x - GX) / GRX, (y - GY) / GRY)
                q = p[OX + x, OY + y]
                if q[3] > 200 and 0.95 < e < 1.0 + 3.0 / GRX:
                    t = kk * (1 - (e - 0.95) / (3.0 / GRX + 0.05))
                    p[OX + x, OY + y] = (*lerp(q[:3], warm, max(0, t)), q[3])
    # 火焰 / 余烬
    wx, wy = OX + WX, OY + WY
    if tier == 'out':
        for (dx, c) in ((-1, (200, 40, 110)), (0, (255, 61, 139)), (1, (200, 40, 110))):
            p[wx + dx, wy] = (*c, 255)
        p[wx, wy - 1] = (255, 176, 208, 255)
        # 一缕烟：从灯顶往上飘，循环
        for j in range(3):
            ph = (i / N + j / 3) % 1.0
            sy = OY + 2 - ph * 18
            sx = wx + math.sin(ph * 6.0 + j) * 2.0
            a = int(120 * math.sin(ph * math.pi))
            if 0 <= int(sy) < FH:
                for dx in (0, 1):
                    q = p[int(sx) + dx, int(sy)]
                    p[int(sx) + dx, int(sy)] = (150, 156, 164, max(q[3], a)) if q[3] < 200 else q
        return _merge(im, lay)
    h = {'lit': 7.5, 'sway': 5.5, 'dim': 3.2}[tier] * fl
    w = {'lit': 2.6, 'sway': 2.2, 'dim': 1.7}[tier]
    for yy in range(int(h) + 2):
        u = yy / max(1.0, h)
        if u > 1:
            break
        half = w * (1 - u ** 1.6) ** 0.7 + 0.35
        cx = wx + sway * u * 1.2
        for xx in range(int(cx - half - 1), int(cx + half + 2)):
            dd = abs(xx + 0.5 - cx - 0.5) / max(0.6, half)
            if dd > 1:
                continue
            core = (1 - dd) * (1 - u)
            if tier == 'dim':
                c = (255, 150, 70) if core > 0.45 else (220, 80, 40)
            else:
                c = (255, 255, 236) if core > 0.55 else ((255, 222, 110) if core > 0.25 else (246, 140, 40))
            p[xx, wy - yy] = (*c, 255)
    if tier != 'dim':
        p[wx, wy + 1] = (90, 140, 255, 255)        # 蓝色火根
        p[wx - 1, wy + 1] = (60, 90, 200, 200)
        p[wx + 1, wy + 1] = (60, 90, 200, 200)
    if tier == 'lit':
        # 两粒火星从顶上飘出
        for j in range(2):
            ph = (i / N + j * 0.5) % 1.0
            sy, sx = OY + 4 - ph * 14, wx + (j - 0.5) * 6 + math.sin(ph * 7 + j) * 1.5
            if ph < 0.85 and 0 <= int(sy) < FH:
                p[int(sx), int(sy)] = (255, 220, 140, int(255 * (1 - ph)))
    return _merge(im, lay)


def _merge(im, lay):
    im.alpha_composite(lay)
    return im


def main():
    os.makedirs(OUT, exist_ok=True)
    base = Image.open(SRC).convert('RGBA')
    bp = base.load()
    glass = [(x, y) for y in range(base.size[1]) for x in range(base.size[0]) if is_glass(bp[x, y], x, y)]
    bb = base.getbbox()
    for tier in TIERS:
        strip = Image.new('RGBA', (FW * N, FH), (0, 0, 0, 0))
        for i in range(N):
            strip.paste(frame(base, glass, tier, i), (i * FW, 0))
        strip.save(os.path.join(OUT, 'lantern_%s.png' % tier))
        json.dump({'frames': N, 'fps': 15, 'frameSize': [FW, FH], 'pivot': [OX + (bb[0] + bb[2]) // 2, OY + bb[3]],
                   'level': TIERS[tier]}, open(os.path.join(OUT, 'lantern_%s.json' % tier), 'w'))
    print(len(glass), 'glass px; pivot', OX + (bb[0] + bb[2]) // 2, OY + bb[3])


if __name__ == '__main__':
    main()
