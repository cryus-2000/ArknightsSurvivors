# -*- coding: utf-8 -*-
"""第三方开放许可特效 → 本作帧条（docs/25 §3）。

用法：python tools/fx_import.py [名字…]
输入：art/third_party/…（不入库）；输出：art/incoming/fx_<name>.png / proj_<name>.png（入库），并打印 V6_FRAMES 登记行。

处理：切帧（按透明列自动分割 / 网格 / 等分）→ 最近邻缩放到目标高度 → 亮度分档映射到干员色板（可选）→ 等宽帧条。
"""
import os, sys
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TP = os.path.join(ROOT, 'art', 'third_party')
OUT = os.path.join(ROOT, 'art', 'incoming')
NA = os.path.join(TP, 'icons', 'pixelboy_ninja_adventure', 'Ninja Adventure - Asset Pack', 'Ninja Adventure - Asset Pack', 'FX')
CM = os.path.join(TP, 'fire_lava', 'codemanu_pixel_effects', 'Free Pixel Effects Pack')
PM = os.path.join(TP, 'holy_light', 'pimen_holy_vfx_01_02')
OG = os.path.join(TP, 'generic_fx', 'oga_pixel_art_spells', 'pixelart_spells_1', 'Pixelart Spells', 'PNG Files')

# 干员色板（docs/25）：暗 → 中 → 亮 → 高光
RAMPS = {
    'green': ['#0B2A18', '#1F7A3A', '#6DFF80', '#E8FFE0'],   # 凯尔希 / Mon3tr
    'amber': ['#2A1606', '#9A5A1E', '#FFB861', '#FFF1CF'],   # 塞雷娅
    'gold':  ['#3A2A08', '#C89A3A', '#FFD173', '#FFFBE8'],   # 铃兰
    'lava':  ['#3A0E04', '#C8420E', '#FF8A2A', '#FFF0B0'],   # 艾雅法拉
    'deep':  ['#0B1E4A', '#2E5EC9', '#8FD3FF', '#F0FBFF'],   # 斯卡蒂
    'lion':  ['#2B1A0A', '#8A5A22', '#E0A54A', '#FFF0C0'],   # 推进之王
}


def hex2rgb(h):
    h = h.lstrip('#')
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def recolor(im, ramp):
    """按亮度在色板上插值；alpha 原样保留"""
    cols = [hex2rgb(c) for c in RAMPS[ramp]]
    im = im.convert('RGBA')
    px = im.load()
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            L = (0.299 * r + 0.587 * g + 0.114 * b) / 255.0
            t = L * (len(cols) - 1)
            i = min(int(t), len(cols) - 2)
            f = t - i
            c = tuple(int(cols[i][k] + (cols[i + 1][k] - cols[i][k]) * f) for k in range(3))
            px[x, y] = c + (a,)
    return im


def split_by_gaps(sheet):
    """按整列透明切帧（Ninja Adventure 的帧间有透明间隔）"""
    a = sheet.convert('RGBA').split()[3]
    W, H = sheet.size
    cols = [any(a.getpixel((x, y)) > 0 for y in range(H)) for x in range(W)]
    frames, x = [], 0
    while x < W:
        if cols[x]:
            x0 = x
            while x < W and cols[x]:
                x += 1
            frames.append(sheet.crop((x0, 0, x, H)))
        else:
            x += 1
    return frames


def split_smart(sheet):
    """先按透明列切；相邻帧贴在一起的段（宽度明显大于中位数）再按中位宽度等分"""
    segs = split_by_gaps(sheet)
    if len(segs) < 2:
        return segs
    ws = sorted(f.width for f in segs)
    med = ws[len(ws) // 2]
    out = []
    for f in segs:
        k = max(1, round(f.width / med))
        if k == 1:
            out.append(f)
        else:
            fw = f.width / k
            for i in range(k):
                out.append(f.crop((round(i * fw), 0, round((i + 1) * fw), f.height)))
    return out


def split_even(sheet, n):
    W, H = sheet.size
    fw = W // n
    return [sheet.crop((i * fw, 0, i * fw + fw, H)) for i in range(n)]


def split_grid(sheet, cell, count, step=1, start=0):
    W, H = sheet.size
    per = W // cell
    out = []
    for k in range(start, count, step):
        cx, cy = (k % per) * cell, (k // per) * cell
        out.append(sheet.crop((cx, cy, cx + cell, cy + cell)))
    return out


def trim_alpha(frames):
    """统一裁到所有帧的联合包围盒（保留对齐）"""
    boxes = [f.getbbox() for f in frames]
    boxes = [b for b in boxes if b]
    if not boxes:
        return frames
    l = min(b[0] for b in boxes); t = min(b[1] for b in boxes)
    r = max(b[2] for b in boxes); btm = max(b[3] for b in boxes)
    return [f.crop((l, t, r, btm)) for f in frames]


def build(frames, height, ramp=None, anchor='center', pad=1):
    """缩放到 height（最近邻，只缩不放）、调色、等宽居中排成一条；anchor=bottom 时底部对齐"""
    frames = [f.convert('RGBA') for f in frames]
    k = min(1.0, height / max(f.height for f in frames))
    if k < 1.0:
        frames = [f.resize((max(1, round(f.width * k)), max(1, round(f.height * k))), Image.NEAREST) for f in frames]
    if ramp:
        frames = [recolor(f, ramp) for f in frames]
    cw = max(f.width for f in frames) + pad * 2
    ch = max(f.height for f in frames) + pad * 2
    cw += cw % 2
    ch += ch % 2
    strip = Image.new('RGBA', (cw * len(frames), ch), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        ox = i * cw + (cw - f.width) // 2
        oy = (ch - f.height) // 2 if anchor == 'center' else ch - pad - f.height
        strip.alpha_composite(f, (ox, oy))
    return strip, cw, ch


def na(rel):
    return os.path.join(NA, rel)


# 名字 → (来源, 切帧方式, 参数, 目标高度, 色板, 锚点, 帧率)
JOBS = {
    # ---- 圣光（Pimen，已是金色）
    'fx_holy_pillar':       (os.path.join(PM, 'Holy VFX 02', 'Holy VFX 02.png'), 'even', 16, 48, None, 'bottom', 14),
    'fx_holy_pillar_amber': (os.path.join(PM, 'Holy VFX 02', 'Holy VFX 02.png'), 'even', 16, 48, 'amber', 'bottom', 14),
    'fx_holy_impact':       (os.path.join(PM, 'Holy VFX 01', 'Holy VFX 01 Impact.png'), 'even', 7, 32, None, 'center', 16),
    # ---- 治疗光环 / 法阵（Ninja Adventure）
    'fx_heal_aura_green':   (na('Magic/Aura/SpriteSheet.png'), 'even', 5, 32, 'green', 'bottom', 10),
    'fx_heal_aura_amber':   (na('Magic/Aura/SpriteSheet.png'), 'even', 5, 32, 'amber', 'bottom', 10),
    'fx_circle_gold':       (na('Magic/Circle/SpriteSheetOrange.png'), 'gaps', None, 32, 'gold', 'center', 8),
    'fx_circle_amber':      (na('Magic/Circle/SpriteSheetOrange.png'), 'gaps', None, 32, 'amber', 'center', 8),
    'fx_shield_amber':      (na('Magic/Shield/SpriteSheetYellow.png'), 'even', 6, 32, 'amber', 'center', 12),
    # ---- 火（艾雅法拉）
    'fx_flam_hit':          (na('Elemental/Flam/SpriteSheet.png'), 'even', 8, 32, 'lava', 'center', 14),
    'fx_sunburst':          (os.path.join(CM, '16_sunburn_spritesheet.png'), 'grid', (100, 64, 4), 64, 'lava', 'center', 16),
    'proj_lavaball':        (os.path.join(OG, 'Fireball.png'), 'even', 6, 16, 'lava', 'center', 12),
    # ---- 绿（凯尔希 / Mon3tr）
    'fx_claw_green':        (na('Attack/Claw/SpriteSheet.png'), 'gaps', None, 32, 'green', 'center', 16),
    'fx_claw_double_green': (na('Attack/ClawDouble/SpriteSheet.png'), 'gaps', None, 32, 'green', 'center', 16),
    'fx_felspell':          (os.path.join(CM, '17_felspell_spritesheet.png'), 'grid', (100, 100, 6), 64, 'green', 'center', 16),
    # ---- 深海（斯卡蒂）
    'fx_slash_arc_deep':    (na('Slash/SpriteSheetArc.png'), 'even', 6, 40, 'deep', 'center', 18),
    'fx_slash_heavy_deep':  (na('Slash/SpriteSheetSlash01.png'), 'even', 5, 40, 'deep', 'center', 16),
    'fx_slash_circle_deep': (na('Slash/SpriteSheetCircular.png'), 'even', 7, 56, 'deep', 'center', 16),
    'fx_water_splash':      (na('Elemental/Water/SpriteSheet.png'), 'even', 11, 34, None, 'bottom', 14),
    # ---- 狮王金（推进之王）
    'fx_rock_burst':        (na('Elemental/Rock/SpriteSheet.png'), 'even', 14, 32, 'lion', 'bottom', 14),
    'fx_rock_spike':        (na('Elemental/RockSpike/SpriteSheet.png'), 'even', 10, 48, 'lion', 'bottom', 14),
    # ---- 狐火弹（铃兰）
    'proj_foxfire':         (os.path.join(OG, 'Light Bolt.png'), 'even', 6, 16, 'gold', 'center', 12),
}


def run(name):
    src, mode, arg, height, ramp, anchor, fps = JOBS[name]
    sheet = Image.open(src).convert('RGBA')
    if mode == 'even':
        frames = split_even(sheet, arg)
    elif mode == 'gaps':
        frames = split_by_gaps(sheet)
    else:
        cell, count, step = arg
        frames = split_grid(sheet, cell, count, step)
    frames = trim_alpha(frames)
    strip, cw, ch = build(frames, height, ramp, anchor)
    out = os.path.join(OUT, name + '.png')
    strip.save(out)
    print(f'"{name}": [{len(frames)}, {fps}.0],  # {cw}x{ch} x{len(frames)}  <- {os.path.relpath(src, TP)}')
    return name, len(frames), fps, cw, ch


if __name__ == '__main__':
    names = sys.argv[1:] or list(JOBS)
    for n in names:
        run(n)
