# -*- coding: utf-8 -*-
"""docs/154 翻节点卡演示录像：python tools/probes/node_cards_capture.py [out=node_cards_rec] [route=memory] [seed=5]
跑 game/tests/node_cards_capture.tscn（窗口放屏幕外、静音、--fixed-fps 60）→ build/<out>/f_#####.png + log.json，
再烧一行字幕、编码 H.264 yuv420p mp4（build/<out>.mp4，手机可直接播）。"""
import sys, json, pathlib, subprocess
ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools'))
import godot_runner as gr
from PIL import Image, ImageDraw, ImageFont

out = sys.argv[1] if len(sys.argv) > 1 else 'node_cards_rec'
route = sys.argv[2] if len(sys.argv) > 2 else 'memory'
seed = sys.argv[3] if len(sys.argv) > 3 else '5'
d = ROOT / 'build' / out
if d.exists():
    for fp in d.glob('*.png'):
        fp.unlink()
args = [gr.find_godot(), '--audio-driver', 'Dummy', '--path', str(ROOT / 'game'), '--fixed-fps', '60', '--resolution', '960x540',
        '--position', '-3000,0', 'res://tests/node_cards_capture.tscn', '--', '--seed=' + seed, '--route=' + route, '--capture-out=' + out]
o, e, timeout = gr.run_godot(args, 1500)
print((o or '')[-300:], 'TIMEOUT' if timeout else 'ok')
log = json.loads((d / 'log.json').read_text(encoding='utf-8'))
font = ImageFont.truetype('C:/Windows/Fonts/msyh.ttc', 24)


def caption(r):
    if r['kind'] == 'cross':
        return '路口%s · 翻节点卡：只露类型，选一张翻开' % ('一' if r['cross'] == 1 else '二')
    if r['kind'] == 'event':
        return '不期而遇 · ' + r['title']
    if 535 <= r['t'] <= 546:
        return '9:00 终局预告：走向冻结，10:00 按结局出最终 Boss'
    if r['cross'] < 2:
        return '中 Boss 倒下 → 2 秒后弹路口%s' % ('一' if r['cross'] == 0 else '二')
    return ''


cap = d / 'cap'
cap.mkdir(exist_ok=True)
for fp in cap.glob('*.png'):
    fp.unlink()
for i, r in enumerate(log):
    im = Image.open(d / ('f_%05d.png' % r['n'])).convert('RGB')
    dr = ImageDraw.Draw(im)
    txt = caption(r)
    if txt:
        dr.rectangle([0, im.height - 44, im.width, im.height], fill=(0, 0, 0))
        dr.text((16, im.height - 38), txt, font=font, fill=(255, 220, 120))
        mm, ss = divmod(int(r['t']), 60)
        dr.text((im.width - 90, im.height - 38), '%d:%02d' % (mm, ss), font=font, fill=(200, 230, 255))
    im.save(cap / ('c_%05d.png' % i))
import imageio_ffmpeg
ff = imageio_ffmpeg.get_ffmpeg_exe()
mp4 = ROOT / 'build' / (out + '.mp4')
subprocess.run([ff, '-y', '-loglevel', 'error', '-framerate', '30', '-i', str(cap / 'c_%05d.png'), '-vf', 'scale=960:540,format=yuv420p',
                '-c:v', 'libx264', '-crf', '24', '-preset', 'medium', '-movflags', '+faststart', str(mp4)], check=True)
print(mp4, len(log), 'frames', round(mp4.stat().st_size / 1048576, 2), 'MB')
