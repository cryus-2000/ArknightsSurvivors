"""跑步试做审阅图：帧条 @2x、GIF（常速 / 慢放）、8 倍逐帧、与现有 run 条对照。

用法：python sheet.py <frames 目录> <输出前缀> [--old <现有 run 条> --old-size N] [--ms 75]
"""
import argparse
from pathlib import Path
from PIL import Image, ImageDraw

BG = (48, 61, 77, 255)
ap = argparse.ArgumentParser()
ap.add_argument('frames'); ap.add_argument('prefix')
ap.add_argument('--old'); ap.add_argument('--old-size', type=int, default=128)
ap.add_argument('--old-origin', type=int, nargs=2, default=None, help='现有条每帧原点；与新帧 (64,120) 对齐')
ap.add_argument('--ms', type=int, default=75)
ap.add_argument('--ms-list', type=int, nargs=8, help='逐帧时长（动作用）')
ap.add_argument('--size', type=int, default=128, help='帧画布边长（动作可大于 128，原点居中平移）')
a = ap.parse_args()
F = Path(a.frames); pre = Path(a.prefix); pre.parent.mkdir(parents=True, exist_ok=True)
frames = [Image.open(F / f'f{i:02d}.png').convert('RGBA') for i in range(8)]
S = a.size; PAD = (S - 128) // 2; GROUND = 120 + PAD
MS = a.ms_list or [a.ms] * 8

strip = Image.new('RGBA', (S * 8, S))
for i, im in enumerate(frames): strip.paste(im, (S * i, 0))
strip.save(f'{pre}_strip@2x.png')

# 统一裁剪框：8 帧并集外扩 4
box = None
for im in frames:
    b = im.getchannel('A').getbbox()
    box = b if box is None else (min(box[0], b[0]), min(box[1], b[1]), max(box[2], b[2]), max(box[3], b[3]))
box = (max(0, box[0] - 4), max(0, box[1] - 4), min(S, box[2] + 4), min(S, box[3] + 4))


def on_bg(im, scale, crop=box, ground=True):
    c = im.crop(crop); bg = Image.new('RGBA', c.size, BG)
    if ground:
        d = ImageDraw.Draw(bg); y = GROUND - crop[1]
        d.line([(0, y), (c.width, y)], fill=(88, 104, 122, 255))
    bg.alpha_composite(c)
    return bg.resize((c.width * scale, c.height * scale), Image.Resampling.NEAREST)


for name, k in (('run', 1), ('run_slow', 4)):
    seq = [on_bg(im, 4).convert('RGB') for im in frames]
    seq[0].save(f'{pre}_{name}.gif', save_all=True, append_images=seq[1:], duration=[m * k for m in MS], loop=0, disposal=2)

# 8 倍逐帧：两行四列，每帧标号 + 地面线 + 像素网格
tiles = [on_bg(im, 8) for im in frames]
tw, th = tiles[0].size
sheet = Image.new('RGBA', (tw * 4 + 5 * 8, th * 2 + 3 * 8 + 32), (30, 36, 44, 255))
d = ImageDraw.Draw(sheet)
for i, t in enumerate(tiles):
    x = 8 + (i % 4) * (tw + 8); y = 24 + (i // 4) * (th + 8 + 12)
    g = ImageDraw.Draw(t)
    for gx in range(0, tw, 8): g.line([(gx, 0), (gx, th)], fill=(0, 0, 0, 28))
    for gy in range(0, th, 8): g.line([(0, gy), (tw, gy)], fill=(0, 0, 0, 28))
    sheet.alpha_composite(t, (x, y))
    d.text((x, y - 14), f'f{i}', fill=(220, 220, 220, 255))
sheet.convert('RGB').save(f'{pre}_x8.png')

# 对照：上行现有 run 条，下行新试做，同 4 倍
if a.old:
    old = Image.open(a.old).convert('RGBA'); n = a.old_size; k = old.width // n
    ox, oy = a.old_origin or (n // 2, n - 8)
    olds = []
    for i in range(k):
        cell = old.crop((i * n, 0, i * n + n, n)); c = Image.new('RGBA', (128, 128))
        c.alpha_composite(cell, (64 - ox, 120 - oy)) if (64 - ox) >= 0 else c.alpha_composite(cell.crop((ox - 64, oy - 120, ox - 64 + 128, oy - 120 + 128)))
        olds.append(c)
    ob = None
    for im in olds + frames:
        b = im.getchannel('A').getbbox()
        if b: ob = b if ob is None else (min(ob[0], b[0]), min(ob[1], b[1]), max(ob[2], b[2]), max(ob[3], b[3]))
    ob = (max(0, ob[0] - 3), max(0, ob[1] - 3), min(128, ob[2] + 3), min(128, ob[3] + 3))
    cols = max(len(olds), 8); s = 4
    tw, th = (ob[2] - ob[0]) * s, (ob[3] - ob[1]) * s
    cmp = Image.new('RGBA', (cols * (tw + 4) + 4, 2 * (th + 18) + 8), (30, 36, 44, 255)); d = ImageDraw.Draw(cmp)
    for row, (label, seq) in enumerate((('现有 run', olds), ('Spine 试做', frames))):
        y = 18 + row * (th + 18); d.text((4, y - 14), label.encode('ascii', 'ignore').decode() or ('old' if row == 0 else 'new'), fill=(220, 220, 220, 255))
        for i, im in enumerate(seq): cmp.alpha_composite(on_bg(im, s, ob), (4 + i * (tw + 4), y))
    cmp.convert('RGB').save(f'{pre}_vs_old.png')
    seq = []
    for i in range(8):
        o = on_bg(olds[i % len(olds)], 4, ob); nn = on_bg(frames[i], 4, ob)
        both = Image.new('RGBA', (o.width * 2 + 8, o.height), (30, 36, 44, 255)); both.alpha_composite(o, (0, 0)); both.alpha_composite(nn, (o.width + 8, 0))
        seq.append(both.convert('RGB'))
    seq[0].save(f'{pre}_vs_old.gif', save_all=True, append_images=seq[1:], duration=a.ms * 2, loop=0, disposal=2)
print('ok', pre)
