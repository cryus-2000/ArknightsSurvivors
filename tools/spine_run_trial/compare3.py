"""三列对照：原作 Spine 直出（--hires，不像素化）｜本流程像素帧｜Codex 版同动作帧（按原点对齐）。

用法：python compare3.py <frames 目录> <输出 png> --size 192 --codex <条@2x.png>:<帧号,...> [--codex ...] [--crop x0 y0 x1 y1] [--k 3]
--codex 可给多次，帧号按顺序拼成与本流程逐帧对应的列表；Codex 条按 128 画布 (64,120) 原点对齐到本画布原点。
"""
import argparse
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ap = argparse.ArgumentParser()
ap.add_argument('frames'); ap.add_argument('out')
ap.add_argument('--size', type=int, default=128)
ap.add_argument('--codex', action='append', default=[])
ap.add_argument('--codex-size', type=int, default=128)
ap.add_argument('--codex-at', action='append', default=[], help='行号=单帧 png：Codex 只交关键帧时按行放（画布按图高自动定，原点同居中平移）')
ap.add_argument('--crop', type=int, nargs=4)
ap.add_argument('--k', type=int, default=3)
ap.add_argument('--labels', nargs='*')
a = ap.parse_args()
F = Path(a.frames); S = a.size; PAD = (S - 128) // 2; K = a.k
BG = (48, 61, 77, 255)
ours = [Image.open(p).convert('RGBA') for p in sorted(F.glob('f[0-9][0-9].png'))]
hires = [Image.open(p).convert('RGBA') for p in sorted(F.glob('hires_f[0-9][0-9].png'))]
cdx = []
for spec in a.codex:
    path, idx = spec.rsplit(':', 1); st = Image.open(path).convert('RGBA'); cs = a.codex_size; cp = (cs - 128) // 2
    for i in map(int, idx.split(',')):
        im = Image.new('RGBA', (S, S)); im.alpha_composite(st.crop((i * cs, 0, (i + 1) * cs, cs)), (PAD - cp, PAD - cp)); cdx.append((im, f'{Path(path).stem.split("@")[0]} f{i}'))
for spec in a.codex_at:
    row, path = spec.split('=', 1); im0 = Image.open(path).convert('RGBA'); cs = im0.height; cp = (cs - 128) // 2
    im = Image.new('RGBA', (S, S)); im.alpha_composite(im0.crop((0, 0, cs, cs)), (PAD - cp, PAD - cp))
    while len(cdx) <= int(row): cdx.append(None)
    cdx[int(row)] = (im, Path(path).stem.split('@')[0])
crop = tuple(a.crop) if a.crop else (0, 0, S, S)
cw, ch = (crop[2] - crop[0]) * K, (crop[3] - crop[1]) * K
font = ImageFont.load_default()
try: font = ImageFont.truetype('C:/Windows/Fonts/msyh.ttc', 16)
except OSError: pass
HEAD = 30
sheet = Image.new('RGBA', (cw * 3 + 32, HEAD + len(ours) * (ch + 22) + 8), (30, 36, 44, 255))
d = ImageDraw.Draw(sheet)
for j, t in enumerate(['原作 Spine 直出（不像素化）', '本流程帧条（@2x）', 'Codex 版（同动作最近帧 / 关键帧）']):
    d.text((8 + j * (cw + 8), 6), t, fill=(230, 230, 230, 255), font=font)


def cell(im, smooth):
    bg = Image.new('RGBA', im.size, BG); bg.alpha_composite(im)
    g = ImageDraw.Draw(bg); y = 120 + PAD; g.line([(0, y), (S, y)], fill=(88, 104, 122, 255))
    return bg.crop(crop).resize((cw, ch), Image.Resampling.NEAREST)


for i, im in enumerate(ours):
    y = HEAD + i * (ch + 22) + 18
    lab = a.labels[i] if a.labels and i < len(a.labels) else f'f{i}'
    d.text((8, y - 18), lab, fill=(200, 200, 200, 255), font=font)
    if i < len(hires):
        h = hires[i]; bg = Image.new('RGBA', h.size, BG); bg.alpha_composite(h)
        hc = bg.crop(tuple(v * 4 for v in crop)).resize((cw, ch), Image.Resampling.LANCZOS); sheet.alpha_composite(hc, (8, y))
    sheet.alpha_composite(cell(im, False), (16 + cw, y))
    if i < len(cdx) and cdx[i]:
        sheet.alpha_composite(cell(cdx[i][0], False), (24 + 2 * cw, y)); d.text((24 + 2 * cw + 4, y + 2), cdx[i][1], fill=(200, 200, 200, 255), font=font)
sheet.convert('RGB').save(a.out)
print('ok', a.out, sheet.size)
