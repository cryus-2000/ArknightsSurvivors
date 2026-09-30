# -*- coding: utf-8 -*-
"""把 promo_shots.gd 录下的帧（build/promo/shots_<tag>/rec_<名>/f####.png）拼成 GIF：缩到 640 宽、每帧八叉树 255 色，超过 8 MB 先降到 128 色、再隔帧抽掉。
用法：python tools/promo_gif.py <帧目录> <输出.gif> [fps=12] [裁切 x0,y0,x1,y1（原图像素，可省）]
"""
import os, sys, glob
from PIL import Image

src, dst = sys.argv[1], sys.argv[2]
fps = float(sys.argv[3]) if len(sys.argv) > 3 else 12.0
crop = tuple(int(v) for v in sys.argv[4].split(",")) if len(sys.argv) > 4 else None
fs = sorted(glob.glob(os.path.join(src, "f*.png")))
LIMIT = 8_000_000   # 按 8 MB 十进制算，两种口径都满足


def build(files, colors):
    frames = []
    for f in files:
        im = Image.open(f).convert("RGB")
        if crop:
            im = im.crop(crop)
        frames.append(im.resize((640, int(im.height * 640 / im.width)), Image.LANCZOS))
    # 每帧各自用八叉树取色（共用调色板会被多数帧的颜色主导，金色 / 洋红这类少数色会串色；中位切分在暗画面上偏色）
    ims = [fr.quantize(colors, method=Image.Quantize.FASTOCTREE, dither=Image.Dither.NONE) for fr in frames]
    ims[0].save(dst, save_all=True, append_images=ims[1:], duration=int(1000 / fps), loop=0, optimize=True, disposal=1)
    return os.path.getsize(dst)


files, colors = fs, 255
size = build(files, colors)
while size > LIMIT:
    if colors > 128:
        colors = 128
    else:
        files = files[::2]
        fps /= 2.0
    size = build(files, colors)
print(dst, len(files), "frames", colors, "colors", round(size / 1048576, 2), "MB")
