# -*- coding: utf-8 -*-
"""已入库特效帧条的重调色变体（docs/25 §3 的延伸，第二批干员用）。

用法：python tools/fx_recolor.py
输入 / 输出都在 art/incoming/：按 VARIANTS 表把源帧条按亮度映射到目标色板，写出新帧条；帧数 / fps 与源相同，
所以 game.gd V6_FRAMES 里照抄源的登记即可（脚本最后打印登记行）。
源帧条本身已是重调色过的第三方素材（tools/fx_import.py），亮度信息仍在，可以再映射一次。
"""
import os
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ART = os.path.join(ROOT, 'art', 'incoming')

# 第二批干员色板（暗 → 中 → 亮 → 高光）
RAMPS = {
    'steel': ['#0A1A2C', '#2F5F8A', '#8FC4EE', '#EAF6FF'],    # 乌尔比安：锚与锁链
    'rose':  ['#3A0F24', '#B2336F', '#FF8FC4', '#FFF0F7'],    # 艾丽妮：剑光
    'ghost': ['#141A2A', '#5C6C8A', '#C3D2E6', '#FFFFFF'],    # 归溟幽灵鲨：常态
    'blood': ['#2A0608', '#8E1E2A', '#FF6070', '#FFE0E0'],    # 归溟幽灵鲨：求生之压
    'ink':   ['#0E1040', '#3A48B8', '#8FA2FF', '#EEF0FF'],    # Logos：言
    'lantern': ['#2A1A06', '#A86E1E', '#FFD27A', '#FFF8E0'],  # 流明：小提灯
}

# (源, 目标, 色板)
VARIANTS = [
    ('fx_slash_arc_deep', 'fx_slash_arc_rose', 'rose'),
    ('fx_slash_heavy_deep', 'fx_slash_heavy_rose', 'rose'),
    ('fx_slash_circle_deep', 'fx_slash_circle_rose', 'rose'),
    ('fx_slash_heavy_deep', 'fx_slash_heavy_steel', 'steel'),
    ('fx_circle_gold', 'fx_circle_steel', 'steel'),
    ('fx_slash_circle_deep', 'fx_slash_circle_ghost', 'ghost'),
    ('fx_slash_circle_deep', 'fx_slash_circle_blood', 'blood'),
    ('fx_circle_gold', 'fx_circle_ghost', 'ghost'),
    ('fx_flam_hit', 'fx_ink_hit', 'ink'),
    ('fx_holy_pillar', 'fx_holy_pillar_ink', 'ink'),
    ('fx_circle_gold', 'fx_circle_ink', 'ink'),
    ('proj_foxfire', 'proj_lumen_bolt', 'lantern'),
    ('fx_holy_impact', 'fx_holy_impact_lantern', 'lantern'),
]


def hex2rgb(h):
    h = h.lstrip('#')
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def recolor(im, ramp):
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


def main():
    made = []
    for src, dst, ramp in VARIANTS:
        sp = os.path.join(ART, src + '.png')
        if not os.path.exists(sp):
            print('缺源帧条：', src)
            continue
        im = Image.open(sp)
        recolor(im, ramp).save(os.path.join(ART, dst + '.png'))
        made.append((src, dst))
        print('%-24s → %-26s (%s)  %dx%d' % (src, dst, ramp, im.width, im.height))
    print('\nV6_FRAMES 登记（帧数 / fps 与源相同）：')
    for src, dst in made:
        print('  "%s": 同 "%s"' % (dst, src))


if __name__ == '__main__':
    main()
