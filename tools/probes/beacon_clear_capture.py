# -*- coding: utf-8 -*-
"""灯标驱散溟痕对照录像：python tools/probes/beacon_clear_capture.py <out> [标签]
跑 game/tests/beacon_clear_capture.tscn（屏幕外、静音、--fixed-fps 60）→ build/<out>/f_####.png + log.json，烧字幕（圈内溟痕数）后编码 build/<out>.mp4。"""
import sys, json, pathlib, subprocess
ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools'))
import godot_runner as gr
from PIL import Image, ImageDraw, ImageFont

out = sys.argv[1]
label = sys.argv[2] if len(sys.argv) > 2 else out
d = ROOT / 'build' / out
if d.exists():
    for fp in d.glob('*.png'):
        fp.unlink()
args = [gr.find_godot(), '--audio-driver', 'Dummy', '--path', str(ROOT / 'game'), '--fixed-fps', '60', '--resolution', '1280x720',
        '--position', '-3000,0', 'res://tests/beacon_clear_capture.tscn', '--', '--capture-out=' + out]
o, e, timeout = gr.run_godot(args, 600)
print((o or '')[-200:], 'TIMEOUT' if timeout else 'ok')
for l in (e or '').splitlines():
    if 'SCRIPT ERROR' in l:
        print(l)
log = {r['f']: r for r in json.loads((d / 'log.json').read_text(encoding='utf-8'))}
font = ImageFont.truetype('C:/Windows/Fonts/msyh.ttc', 24)
cap = d / 'cap'
cap.mkdir(exist_ok=True)
for fp in cap.glob('*.png'):
    fp.unlink()
frames = sorted(d.glob('f_*.png'))
for i, fp in enumerate(frames):
    f = int(fp.stem[2:])
    r = log[f]
    im = Image.open(fp).convert('RGB')
    dr = ImageDraw.Draw(im)
    dr.rectangle([0, im.height - 44, im.width, im.height], fill=(0, 0, 0))
    phase = '点燃前' if r['t'] < 0.5 else ('点燃' if r['t'] < 1.4 else '生效中：圈内补一片怪物溟痕 + 灯火 10（圈外溟痕逼近）')
    dr.text((16, im.height - 38), '%s · %s · 圈内非 Boss 溟痕 %d 片' % (label, phase, r['inside']), font=font, fill=(255, 220, 120))
    im.save(cap / ('c_%04d.png' % i))
import imageio_ffmpeg
ff = imageio_ffmpeg.get_ffmpeg_exe()
mp4 = ROOT / 'build' / (out + '.mp4')
subprocess.run([ff, '-y', '-loglevel', 'error', '-framerate', '30', '-i', str(cap / 'c_%04d.png'), '-vf', 'format=yuv420p', '-c:v', 'libx264', '-crf', '22', '-preset', 'medium', '-movflags', '+faststart', str(mp4)], check=True)
print(mp4, len(frames), 'frames', 'inside_end=%d' % log[max(log)]['inside'])
