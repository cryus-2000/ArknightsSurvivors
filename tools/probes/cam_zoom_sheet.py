# -*- coding: utf-8 -*-
"""docs/112 对照图：把 build/camzoom/<标签>/shot_t*.png 拼成「整屏缩小 2×2」和「主控周围 1:1 裁窗放大 3 倍」两张。
用法：python tools/probes/cam_zoom_sheet.py <前缀 d|p> <t> <标签1,标签2,…>"""
import os, sys
from PIL import Image, ImageDraw
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
pre, t, tags = sys.argv[1], int(sys.argv[2]), sys.argv[3].split(",")
base = os.path.join(ROOT, "build", "camzoom")
ims = [(tg, Image.open(os.path.join(base, tg, "shot_t%04d.png" % t)).convert("RGB")) for tg in tags]
W, H = ims[0][1].size
# 整屏：每张缩到 1/2，2 列
cols = 2
sw, sh = W // 2, H // 2
sheet = Image.new("RGB", (sw * cols, sh * ((len(ims) + 1) // cols)), (0, 0, 0))
for i, (tg, im) in enumerate(ims):
    x, y = (i % cols) * sw, (i // cols) * sh
    sheet.paste(im.resize((sw, sh), Image.LANCZOS), (x, y))
    ImageDraw.Draw(sheet).text((x + 10, y + 8), tg, fill=(255, 255, 0))
sheet.save(os.path.join(base, "sheet_%s_full_t%04d.png" % (pre, t)))
# 裁窗：屏幕中心 320×200 屏幕像素（主控），最近邻 ×3
cw, ch = 320, 200
crop = Image.new("RGB", (cw * 3 * len(ims), ch * 3 + 24), (0, 0, 0))
for i, (tg, im) in enumerate(ims):
    c = im.crop(((W - cw) // 2, (H - ch) // 2 - 30, (W + cw) // 2, (H + ch) // 2 - 30)).resize((cw * 3, ch * 3), Image.NEAREST)
    crop.paste(c, (i * cw * 3, 24))
    ImageDraw.Draw(crop).text((i * cw * 3 + 8, 6), tg, fill=(255, 255, 0))
crop.save(os.path.join(base, "sheet_%s_crop3x_t%04d.png" % (pre, t)))
print("ok")
