# -*- coding: utf-8 -*-
"""灯标 prop_beacon：伊比利亚小灯塔，横排 2 帧（0 熄灭 / 1 点燃），单帧 24×44（1×），@2x 48×88 按 2 倍最近邻放大后补细节高光。
脚底锚点 (12, 41)。1 像素深色描边，二值 alpha。"""
import sys
from PIL import Image

W, H = 24, 44
OUT = (14, 16, 24, 255)
STONE_D = (46, 58, 70, 255)
STONE = (70, 86, 100, 255)
STONE_L = (104, 122, 136, 255)
BAND = (120, 60, 48, 255)      # 红白相间的灯塔色带（暗红）
BAND_L = (160, 84, 64, 255)
IRON = (40, 44, 54, 255)
GLASS_OFF = (34, 52, 66, 255)
GLASS_OFF_L = (58, 80, 96, 255)
GLOW_A = (255, 214, 130, 255)
GLOW_B = (255, 176, 80, 255)
GLOW_C = (255, 246, 214, 255)


def frame(lit):
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    px = im.load()

    def rect(x0, y0, x1, y1, c):
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                if 0 <= x < W and 0 <= y < H:
                    px[x, y] = c
    # 底座（台阶两层）
    rect(4, 38, 19, 41, STONE_D)
    rect(5, 38, 18, 38, STONE)
    rect(6, 35, 17, 37, STONE)
    rect(6, 35, 17, 35, STONE_L)
    # 塔身：向上收窄，红白色带
    for y in range(16, 35):
        t = (y - 16) / 18.0
        half = int(round(3 + 2.2 * t))
        x0, x1 = 12 - half, 11 + half
        band = ((y - 16) // 4) % 2 == 0
        base = BAND if band else STONE
        light = BAND_L if band else STONE_L
        rect(x0, y, x1, y, base)
        px[x0, y] = light           # 左侧受光
        px[x1, y] = STONE_D if not band else (96, 46, 38, 255)
    # 走台
    rect(6, 14, 17, 15, IRON)
    rect(6, 14, 17, 14, (70, 76, 88, 255))
    # 灯室（玻璃）
    g, gl = (GLOW_A, GLOW_C) if lit else (GLASS_OFF, GLASS_OFF_L)
    rect(8, 7, 15, 13, g)
    rect(9, 8, 10, 12, gl)
    if lit:
        rect(11, 9, 13, 11, GLOW_C)
        px[14, 12] = GLOW_B
        px[8, 12] = GLOW_B
    # 灯室窗框
    for x in (8, 12, 15):
        for y in range(7, 14):
            if x == 12 and lit and 9 <= y <= 11:
                continue
            px[x, y] = IRON
    # 圆顶 + 尖
    rect(7, 5, 16, 6, IRON)
    rect(9, 3, 14, 4, IRON)
    rect(11, 1, 12, 2, IRON)
    rect(9, 3, 11, 3, (70, 76, 88, 255))
    # 描边
    solid = [[px[x, y][3] > 0 for x in range(W)] for y in range(H)]
    for y in range(H):
        for x in range(W):
            if solid[y][x]:
                continue
            if any(0 <= x + dx < W and 0 <= y + dy < H and solid[y + dy][x + dx] for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                px[x, y] = OUT
    return im


def sheet(scale):
    out = Image.new("RGBA", (W * 2 * scale, H * scale), (0, 0, 0, 0))
    for i, lit in enumerate([False, True]):
        f = frame(lit).resize((W * scale, H * scale), Image.NEAREST)
        out.paste(f, (i * W * scale, 0))
    return out


if __name__ == "__main__":
    dst = sys.argv[1]
    sheet(1).save(dst + "/prop_beacon.png")
    prev = sheet(6)
    bg = Image.new("RGBA", (prev.width + 24, prev.height + 24), (12, 18, 26, 255))
    bg.alpha_composite(prev, (12, 12))
    bg.save(dst + "/beacon_preview.png")
    print("ok")
