# -*- coding: utf-8 -*-
"""10-25 自动技能门槛对比录像：python tools/probes/skill_gate_capture.py <out> [干员=siege] [秒=36]
跑 game/tests/skill_gate_capture.tscn（窗口放屏幕外、静音）→ build/<out>/f_####.png + log.json，再烧字幕、编码 H.264 yuv420p mp4（build/<out>.mp4，≤ 20 MB）。"""
import sys, json, pathlib, subprocess
ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools'))
import godot_runner as gr
from PIL import Image, ImageDraw, ImageFont

out = sys.argv[1]
who = sys.argv[2] if len(sys.argv) > 2 else 'siege'
secs = sys.argv[3] if len(sys.argv) > 3 else '36'
args = [gr.find_godot(), '--audio-driver', 'Dummy', '--path', str(ROOT / 'game'), '--fixed-fps', '60', '--resolution', '960x540',
        '--position', '-3000,0', 'res://tests/skill_gate_capture.tscn', '--', '--regression', '--balance', '--seed=1', '--op=' + who,
        '--probe-op=' + who, '--capture-out=' + out, '--capture-secs=' + secs]
o, e, timeout = gr.run_godot(args, 900)
print((o or '')[-200:], 'TIMEOUT' if timeout else 'ok')
d = ROOT / 'build' / out
log = json.loads((d / 'log.json').read_text(encoding='utf-8'))
font = None
for fp in ('C:/Windows/Fonts/msyh.ttc', 'C:/Windows/Fonts/simhei.ttf'):
    try:
        font = ImageFont.truetype(fp, 26); break
    except Exception:
        pass
CAP = {0: '周围没有敌人：技力满格也不放', 1: '敌人在作用范围外：不放', 2: '敌人进入作用范围：放出技能'}
last_cast = -999
casts = {r['f']: r['cast'] for r in log if r['cast']}
fr_dir = d / 'cap'
fr_dir.mkdir(exist_ok=True)
frames = sorted(d.glob('f_*.png'))
for i, fp in enumerate(frames):
    f = int(fp.stem[2:])
    row = log[f]
    for ff in range(f - 1, f + 2):
        if ff in casts: last_cast = f
    im = Image.open(fp).convert('RGB')
    dr = ImageDraw.Draw(im)
    txt = CAP[row['phase']]
    if f - last_cast < 40: txt = '▶ 放出技能 S%d' % max(casts.get(k, 0) for k in range(max(0, f - 40), f + 1) if k in casts)
    dr.rectangle([0, im.height - 70, im.width, im.height], fill=(0, 0, 0))
    dr.text((20, im.height - 56), txt, font=font, fill=(255, 220, 120))
    dr.text((im.width - 330, im.height - 56), '最近敌人 %s · 技力 %s' % ('—' if row['near'] < 0 else int(row['near']), '/'.join('%.0f' % x for x in row['sp'])), font=font, fill=(200, 230, 255))
    im.save(fr_dir / ('c_%04d.png' % i))
import imageio_ffmpeg
ff = imageio_ffmpeg.get_ffmpeg_exe()
mp4 = ROOT / 'build' / (out + '.mp4')
subprocess.run([ff, '-y', '-framerate', '30', '-i', str(fr_dir / 'c_%04d.png'), '-vf', 'scale=960:540,format=yuv420p', '-c:v', 'libx264', '-crf', '24', '-preset', 'medium', '-movflags', '+faststart', str(mp4)], check=True)
print(mp4, round(mp4.stat().st_size / 1048576, 2), 'MB')
