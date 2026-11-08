# -*- coding: utf-8 -*-
"""视频自己像素化（用户 11-08：AI 感太强、要我们自己像素化）。
做法：所有镜头先抽样合成一张拼图 → 中位切分出一套统一调色板（不同镜头同一套色，切镜不跳色、不闪色）；
每帧 BOX 缩到 1/PX（缺省 6 → 320×180，像素格 = 6×6 屏幕像素）→ 按调色板量化（不抖动）→ 最近邻放大；
时间上按 STEP（缺省 5 → 60 帧里每 5 帧换一张 = 12 帧/秒）保持，去掉 AI 插值的丝滑感，像逐帧像素动画。
  用法（模块）：pal = build_palette(图列表, colors)；out = pixelize(img, pal, px)
"""
from PIL import Image

W, H = 1920, 1080


def build_palette(images, colors=32, px=6):
    tiles = [im.convert("RGB").resize((W // px, H // px), Image.BOX) for im in images]
    cols = 4
    rows = (len(tiles) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * (W // px), rows * (H // px)))
    for i, t in enumerate(tiles):
        sheet.paste(t, ((i % cols) * (W // px), (i // cols) * (H // px)))
    return sheet.quantize(colors=colors, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)


def pixelize(im, pal, px=6):
    small = im.convert("RGB").resize((W // px, H // px), Image.BOX)
    q = small.quantize(palette=pal, dither=Image.Dither.NONE).convert("RGB")
    return q.resize((W, H), Image.NEAREST)
