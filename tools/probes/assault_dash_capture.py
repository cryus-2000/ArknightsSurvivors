# -*- coding: utf-8 -*-
"""10-26 突击模式德克萨斯自冲刺录像：python tools/probes/assault_dash_capture.py <out> [秒=14]
跑 game/tests/assault_dash_capture.tscn（窗口放屏幕外、静音）→ 烧字幕（随行 / 突击、每次冲刺亮「冲刺」）→ H.264 yuv420p mp4（build/<out>.mp4）。"""
import sys, os, json, pathlib, subprocess
ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools'))
import godot_runner as gr
from PIL import Image, ImageDraw, ImageFont

out = sys.argv[1]
secs = sys.argv[2] if len(sys.argv) > 2 else '14'
args = [gr.find_godot(), '--audio-driver', 'Dummy', '--path', str(ROOT / 'game'), '--fixed-fps', '60', '--resolution', '960x540',
        '--position', '-3000,0', 'res://tests/assault_dash_capture.tscn', '--', '--regression', '--balance', '--seed=1', '--op=skadi', '--squad=texas',
        '--capture-secs=' + secs, '--capture-out=' + out]
if not os.environ.get('REUSE'):   # REUSE=1：只重新烧字幕拼视频
    o, e, timeout = gr.run_godot(args, 900)
    print('TIMEOUT' if timeout else 'ok', (o or '')[-160:].strip())
d = ROOT / 'build' / out
lg = json.loads((d / 'log.json').read_text(encoding='utf-8'))
font = None
for fp in ('C:/Windows/Fonts/msyh.ttc', 'C:/Windows/Fonts/simhei.ttf'):
    try:
        font = ImageFont.truetype(fp, 26); break
    except Exception:
        pass
cap = ROOT / 'build' / (out + '_cap')
cap.mkdir(exist_ok=True)
for i, fp in enumerate(sorted(d.glob('f_*.png'))):
    t = int(fp.stem[2:]) / 60.0
    im = Image.open(fp).convert('RGB')
    dr = ImageDraw.Draw(im)
    dr.rectangle([0, im.height - 56, im.width, im.height], fill=(0, 0, 0))
    mode = '突击' if t >= lg['roam_at'] else '随行'
    dash = any(0 <= t - x <= 0.6 for x in lg['dashes'])
    dr.text((20, im.height - 46), '指挥：%s' % mode + ('    德克萨斯自冲刺 >>' if dash else ''), font=font, fill=(255, 220, 120) if dash else (200, 230, 255))
    im.save(cap / ('c_%04d.png' % i))
import imageio_ffmpeg
mp4 = ROOT / 'build' / (out + '.mp4')
subprocess.run([imageio_ffmpeg.get_ffmpeg_exe(), '-y', '-framerate', '30', '-i', str(cap / 'c_%04d.png'), '-vf', 'format=yuv420p', '-c:v', 'libx264', '-crf', '24', '-movflags', '+faststart', str(mp4)], check=True)
print(mp4, round(mp4.stat().st_size / 1048576, 2), 'MB', 'dashes', lg['dashes'])
