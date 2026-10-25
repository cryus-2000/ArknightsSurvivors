# -*- coding: utf-8 -*-
"""10-25 攻速对比录像：python tools/probes/atk_rate_capture.py <out> [干员=mizuki] [秒=6] [倍率,…=1,2.5,4]
每个倍率各跑一次 game/tests/atk_rate_capture.tscn（窗口放屏幕外、静音），裁出角色周围一块并排拼成 H.264 yuv420p mp4（build/<out>.mp4），字幕标倍率和实测出手频率。"""
import sys, os, json, pathlib, subprocess
ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools'))
import godot_runner as gr
from PIL import Image, ImageDraw, ImageFont

out = sys.argv[1]
who = sys.argv[2] if len(sys.argv) > 2 else 'mizuki'
secs = sys.argv[3] if len(sys.argv) > 3 else '6'
rates = [float(x) for x in (sys.argv[4] if len(sys.argv) > 4 else '1,2.5,4').split(',')]
font = None
for fp in ('C:/Windows/Fonts/msyh.ttc', 'C:/Windows/Fonts/simhei.ttf'):
    try:
        font = ImageFont.truetype(fp, 24); break
    except Exception:
        pass
dirs = []
for r in rates:
    tag = '%s_%s' % (out, str(r).replace('.', 'p'))
    args = [gr.find_godot(), '--audio-driver', 'Dummy', '--path', str(ROOT / 'game'), '--fixed-fps', '60', '--resolution', '960x540',
            '--position', '-3000,0', 'res://tests/atk_rate_capture.tscn', '--', '--regression', '--balance', '--seed=1', '--op=' + who,
            '--rate=%s' % r, '--capture-secs=' + secs, '--capture-out=' + tag]
    if not os.environ.get('REUSE'):   # REUSE=1：只重新拼视频，不重跑 Godot
        o, e, timeout = gr.run_godot(args, 900)
        print(tag, 'TIMEOUT' if timeout else 'ok', (o or '')[-120:].strip())
    dirs.append(ROOT / 'build' / tag)
logs = [json.loads((d / 'log.json').read_text(encoding='utf-8')) for d in dirs]
cap = ROOT / 'build' / (out + '_cap')
cap.mkdir(exist_ok=True)
files = [sorted(d.glob('f_*.png')) for d in dirs]
n = min(len(f) for f in files)
W, H = 360, 330
for i in range(n):
    canvas = Image.new('RGB', (W * len(dirs), H + 76), (0, 0, 0))
    for j, fl in enumerate(files):
        im = Image.open(fl[i]).convert('RGB').crop((300, 100, 660, 430))
        canvas.paste(im, (W * j, 0))
        st = [s for s in logs[j]['starts']]
        hz = (len(st) - 1) / (st[-1] - st[0]) if len(st) > 1 else 0.0
        d = ImageDraw.Draw(canvas)
        d.text((W * j + 10, H + 6), '攻速 ×%g' % logs[j]['rate'], font=font, fill=(255, 220, 120))
        d.text((W * j + 10, H + 32), '实测 %.2f 次/秒' % hz, font=font, fill=(200, 230, 255))
    canvas.save(cap / ('c_%04d.png' % i))
import imageio_ffmpeg
mp4 = ROOT / 'build' / (out + '.mp4')
subprocess.run([imageio_ffmpeg.get_ffmpeg_exe(), '-y', '-framerate', '30', '-i', str(cap / 'c_%04d.png'), '-vf', 'format=yuv420p', '-c:v', 'libx264', '-crf', '24', '-movflags', '+faststart', str(mp4)], check=True)
print(mp4, round(mp4.stat().st_size / 1048576, 2), 'MB')
for lg in logs:
    st = lg['starts']
    print('rate', lg['rate'], 'aspd', lg['aspd'], 'attacks', len(st), 'intervals', [round(st[k + 1] - st[k], 3) for k in range(min(5, len(st) - 1))])
