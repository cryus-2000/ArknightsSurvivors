# -*- coding: utf-8 -*-
"""维什戴尔爆炸特效 vs 判定圈对比图（用户 10-26）：python tools/probes/wisadel_fx_radius.py
跑 tests/wisadel_fx_radius_test.tscn --capture（窗口放屏幕外、静音），三张图：旧 78（改半径前）/ 旧取整 66（判定变了画面没变）/ 新 66（画面跟着判定走），
各叠一圈红色判定圈（半径 = 判定半径）并标注，拼成 build/wisadel_fx_radius_compare.png。"""
import sys, json, pathlib
ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools'))
import godot_runner as gr
from PIL import Image, ImageDraw, ImageFont

args = [gr.find_godot(), '--audio-driver', 'Dummy', '--path', str(ROOT / 'game'), '--fixed-fps', '60', '--resolution', '960x540',
        '--position', '-3000,0', 'res://tests/wisadel_fx_radius_test.tscn', '--', '--balance', '--seed=1', '--op=wisadel', '--capture']
o, e, timeout = gr.run_godot(args, 600)
print('TIMEOUT' if timeout else 'ok', (o or '')[-120:].strip())
d = ROOT / 'build' / 'wisadel_fx_radius'
lg = json.loads((d / 'log.json').read_text(encoding='utf-8'))
sx = Image.open(d / 'old78.png').width / float(lg['size'][0])
font = ImageFont.truetype('C:/Windows/Fonts/msyh.ttc', 22)
LAB = {'old78': '改前 78', 'old66': '只改判定 66', 'new66': '改后 66'}
W = 460
panels = []
for c in lg['cfgs']:
    im = Image.open(d / ('%s.png' % c['name'])).convert('RGB')
    cx, cy, rs = c['centre'][0] * sx, c['centre'][1] * sx, c['r_screen'] * sx
    # 帧条的锚点不在画面像素中心：用爆炸红色像素的质心当圆心（画面圆心和换算出来的世界坐标差一个固定偏移）
    px = im.load()
    xs = ys = n = 0
    for yy in range(int(cy - 1.5 * rs), int(cy + 1.5 * rs)):
        for xx in range(int(cx - 1.5 * rs), int(cx + 1.5 * rs)):
            r_, g_, b_ = px[xx, yy]
            if r_ > 200 and g_ < 90 and b_ < 120:
                xs += xx; ys += yy; n += 1
    if n > 30:
        cx, cy = xs / n, ys / n
    dr = ImageDraw.Draw(im)
    dr.ellipse([cx - rs, cy - rs, cx + rs, cy + rs], outline=(255, 40, 40), width=3)
    im = im.crop((int(cx - W / 2), int(cy - W / 2), int(cx + W / 2), int(cy + W / 2)))
    dr = ImageDraw.Draw(im)
    dr.rectangle([0, W - 34, W, W], fill=(0, 0, 0))
    dr.text((8, W - 31), '%s 判定 %d / 实心边 %d' % (LAB[c['name']], c['r'], round(c['solid'])), font=font, fill=(255, 220, 120))
    panels.append(im)
out = Image.new('RGB', (W * len(panels), W))
for i, p in enumerate(panels):
    out.paste(p, (i * W, 0))
out.save(ROOT / 'build' / 'wisadel_fx_radius_compare.png')
print(out.size)
