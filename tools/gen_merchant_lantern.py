# -*- coding: utf-8 -*-
"""商人灯笼发光帧（docs/54 §6 最后一条的程序生成版）：从 art/incoming/merchant.png 里找出暖色提灯的位置，
生成一条叠在商人帧上的发光覆盖帧条 fx_merchant_lantern.png（48×48 × 4 帧，二值 alpha，@2x 严格 2 倍最近邻）。

帧序 = 商人帧 × 2 + 亮度：0 / 1 = 商人第 0 帧的暗 / 亮，2 / 3 = 商人第 1 帧的暗 / 亮。
  暗帧：灯芯按原色、提灯周围 3 像素内的衣料往暖色轻压一点；
  亮帧：灯芯白热、玻璃罩亮黄、周围 5 像素内的衣料明显被照亮，灯外一圈棋盘点暖光。
游戏里（render/world.gd 商人绘制）以同一锚点、同一镜像叠画，按 g.t 的不规则节律在暗 / 亮之间切换，灯光节点能量同步抖一下；
贴图不在或 fx/strips = 0 时回到改动前（PointLight2D + 暖尘）。

调色与 gen_fx_strips 的灯火暖色一致（#FFF6E0 / #FFE8B0 / #FFC46B / #FF8A3D），衣料压色取商人原像素与暖色的混合，只用固定种子。

用法：python tools/gen_merchant_lantern.py [--preview [目录]]
  --preview 另写 build/fxstrips/merchant_lantern.png：商人帧 + 覆盖后的四种状态，1x 与 4x。
"""
import os, sys, math, random
from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
INC = os.path.join(ROOT, "art", "incoming")
PREV = os.path.join(ROOT, "build", "fxstrips")
SRC = os.path.join(INC, "merchant.png")
NAME = "fx_merchant_lantern"
FW, FH, NF = 48, 48, 4

CLEAR = (0, 0, 0, 0)
W_CORE = (0xFF, 0xF6, 0xE0, 255)
W_PALE = (0xFF, 0xE8, 0xB0, 255)
W_GOLD = (0xFF, 0xC4, 0x6B, 255)
W_ORNG = (0xFF, 0x8A, 0x3D, 255)


def lantern_pixels(im, f):
    """商人第 f 帧里的提灯像素：暖色（红明显高于蓝）且在右下象限（左上还有一粒帽檐 / 眼睛的反光，排除）。"""
    out = {}
    for y in range(FH // 2, FH):
        for x in range(FW // 2, FW):
            r, g, b, a = im.getpixel((x + f * FW, y))
            if a and r > 140 and r > b + 40:
                out[(x, y)] = (r, g, b)
    assert out, "第 %d 帧找不到提灯" % f
    return out


def mix(c, w, k):
    return tuple(int(round(c[i] * (1 - k) + w[i] * k)) for i in range(3)) + (255,)


def frame(im, f, bright, rng):
    lp = lantern_pixels(im, f)
    cx = sum(x for x, _ in lp) / len(lp)
    cy = sum(y for _, y in lp) / len(lp)
    px = {}
    rad = 5.5 if bright else 3.2
    for y in range(FH):
        for x in range(FW):
            r, g, b, a = im.getpixel((x + f * FW, y))
            d = math.hypot(x - cx, (y - cy) * 1.15)
            if (x, y) in lp:
                src = lp[(x, y)]
                lum = (src[0] + src[1]) / 2
                if bright:
                    px[(x, y)] = W_CORE if lum >= 215 else (W_PALE if lum >= 180 else W_GOLD)
                else:
                    px[(x, y)] = src + (255,)
                continue
            if d > rad:
                continue
            k = max(0.0, 1.0 - d / rad)
            if a:
                # 衣料被照亮：离灯越近越暖；暗帧只轻压，亮帧明显
                amt = (0.55 if bright else 0.28) * k
                if amt < 0.08:
                    continue
                px[(x, y)] = mix((r, g, b), W_GOLD, amt)
            elif bright and d <= 3.6 and (x + y) % 2 == 0:
                # 灯外的棋盘点暖光（只在亮帧）
                px[(x, y)] = W_ORNG if d > 2.4 else W_GOLD
    return px


def build():
    im = Image.open(SRC).convert("RGBA")
    assert im.size == (FW * 2, FH), im.size
    rng = random.Random(54)
    out = Image.new("RGBA", (FW * NF, FH), CLEAR)
    for f in range(2):
        for b in range(2):
            px = frame(im, f, b == 1, rng)
            for (x, y), c in px.items():
                out.putpixel((x + (f * 2 + b) * FW, y), c)
    return im, out


def check(im):
    assert im.size == (FW * NF, FH)
    assert set(im.getchannel("A").getdata()) <= {0, 255}


def preview(src, strip, out_dir):
    os.makedirs(out_dir, exist_ok=True)
    bg = (28, 30, 44, 255)
    cells = []
    for f in range(2):
        base = src.crop((f * FW, 0, f * FW + FW, FH))
        cells.append(base)
        for b in range(2):
            ov = strip.crop(((f * 2 + b) * FW, 0, (f * 2 + b + 1) * FW, FH))
            c = base.copy()
            c.alpha_composite(ov)
            cells.append(c)
    W = (FW + 6) * len(cells) + 6
    sheet = Image.new("RGBA", (W * 4 + 12, FH + 12 + FH * 4 + 12), bg)
    x = 6
    for c in cells:
        sheet.paste(c, (x, 6), c)
        sheet.paste(c.resize((FW * 4, FH * 4), Image.NEAREST), (x * 4, FH + 18), c.resize((FW * 4, FH * 4), Image.NEAREST))
        x += FW + 6
    p = os.path.join(out_dir, "merchant_lantern.png")
    sheet.save(p)
    return p


def main():
    src, strip = build()
    check(strip)
    strip.save(os.path.join(INC, NAME + ".png"))
    strip.resize((strip.width * 2, strip.height * 2), Image.NEAREST).save(os.path.join(INC, NAME + "@2x.png"))
    print("wrote", NAME, strip.size)
    if "--preview" in sys.argv:
        i = sys.argv.index("--preview")
        d = sys.argv[i + 1] if i + 1 < len(sys.argv) and not sys.argv[i + 1].startswith("--") else PREV
        print("preview:", preview(src, strip, d))


if __name__ == "__main__":
    main()
