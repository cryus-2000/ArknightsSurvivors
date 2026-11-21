# -*- coding: utf-8 -*-
"""把 sbell2_snow_shots.py 的两张截图拼成撞色对照（docs/403 §6.0）：每张地图一行，左 = 1 倍裁切（队长周围 760 × 520），右 = 同区域中心 2 倍放大。
用法：python tools/sbell2_snow_compare.py <深海截图> <萨米截图> <输出.png> [--cx 960 --cy 560]"""
import argparse
from PIL import Image, ImageDraw, ImageFont

ap = argparse.ArgumentParser()
ap.add_argument("deep"); ap.add_argument("sami"); ap.add_argument("out")
ap.add_argument("--cx", type=int, default=1060); ap.add_argument("--cy", type=int, default=560)
ap.add_argument("--w", type=int, default=860); ap.add_argument("--h", type=int, default=560)
a = ap.parse_args()
try:
    font = ImageFont.truetype("C:/Windows/Fonts/msyh.ttc", 22)
except OSError:
    font = ImageFont.load_default()
rows = []
for label, p in (("深海地面", a.deep), ("萨米雪地（昧明冻土）", a.sami)):
    im = Image.open(p).convert("RGB")
    box = (a.cx - a.w // 2, a.cy - a.h // 2, a.cx + a.w // 2, a.cy + a.h // 2)
    one = im.crop(box)
    z = one.crop((a.w // 4, a.h // 4, a.w * 3 // 4, a.h * 3 // 4)).resize((a.w, a.h), Image.NEAREST)
    row = Image.new("RGB", (a.w * 2 + 30, a.h + 40), (16, 20, 28))
    row.paste(one, (10, 34)); row.paste(z, (a.w + 20, 34))
    d = ImageDraw.Draw(row)
    d.text((12, 4), label + " · 1 倍", fill=(230, 235, 240), font=font)
    d.text((a.w + 22, 4), label + " · 2 倍（中心放大）", fill=(230, 235, 240), font=font)
    rows.append(row)
out = Image.new("RGB", (rows[0].width, sum(r.height for r in rows)), (16, 20, 28))
y = 0
for r in rows:
    out.paste(r, (0, y)); y += r.height
out.save(a.out)
print(a.out, out.size)
