# -*- coding: utf-8 -*-
"""封面用：博士待机第 0 帧加一条向前（右）伸出、食指指向前方的手臂（游戏里没有这个动作，只给封面用）。
输出裁好的 RGBA（@2x 精灵像素），promo_cover_1107.dir_B 调用 doctor_point()。"""
import os
from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
OL, HI, MID, DK, CUFF, GLV, GHI = (21, 24, 33), (83, 89, 112), (48, 51, 70), (35, 37, 51), (36, 101, 116), (36, 31, 37), (81, 64, 72)


def doctor_point():
    im = Image.open(os.path.join(ROOT, "game/art/operators/doctor/doctor_idle@2x.png")).convert("RGBA").crop((0, 0, 128, 128))
    fr = im.crop(im.getbbox())
    W = fr.width + 20
    out = Image.new("RGBA", (W, fr.height), (0, 0, 0, 0))
    out.paste(fr, (0, 0))
    px = out.load()

    def put(x, y, c):
        if 0 <= x < W and 0 <= y < fr.height:
            px[x, y] = c + (255,)
    # 屈肘指向（不能是直臂上扬：用户 11-07 指出那像纳粹礼）：上臂从肩斜向下到肘，前臂近水平前伸，握拳只伸食指
    def seg(ax, ay, bx, by, inner, w):
        n = max(abs(bx - ax), abs(by - ay))
        pts = [(round(ax + (bx - ax) * t / n), round(ay + (by - ay) * t / n)) for t in range(n + 1)]
        for x, y in pts:   # 先描边
            for dx in range(-w - 1, w + 2):
                for dy in range(-w - 1, w + 2):
                    if abs(dx) + abs(dy) <= w + 1:
                        put(x + dx, y + dy, OL)
        for x, y in pts:
            for dx in range(-w, w + 1):
                for dy in range(-w, w + 1):
                    if abs(dx) + abs(dy) <= w:
                        put(x + dx, y + dy, inner(dy))
    sleeve = lambda dy: HI if dy < 0 else (MID if dy == 0 else DK)
    seg(26, 35, 31, 43, sleeve, 2)          # 上臂（大衣袖，粗）
    seg(31, 43, 41, 41, sleeve, 1)          # 前臂
    for y in range(40, 43):                 # 袖口青色
        put(40, y, CUFF); put(41, y, CUFF)
    # 拳头 4×4
    for x in range(42, 46):
        put(x, 38, OL); put(x, 43, OL)
        for y in range(39, 43):
            put(x, y, GHI if y == 39 else GLV)
    put(46, 39, OL); put(46, 41, GLV); put(46, 42, OL)
    for y in range(39, 43):
        put(42, y, GLV)
    # 食指：从拳头上沿平伸出去
    for x in range(46, 51):
        put(x, 39, OL); put(x, 40, GHI); put(x, 41, OL)
    put(51, 40, OL)
    return out.crop(out.getbbox())


if __name__ == "__main__":
    import sys
    d = doctor_point()
    k = 8
    b = Image.new("RGBA", (d.width * k, d.height * k), (70, 95, 120, 255))
    b.alpha_composite(d.resize((d.width * k, d.height * k), Image.NEAREST))
    b.save(sys.argv[1])
