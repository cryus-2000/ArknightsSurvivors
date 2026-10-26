# -*- coding: utf-8 -*-
"""干员连携技演示录像（docs/160）：python tools/probes/synergy_capture.py <对名> <标题> <场景1> [<场景2> …]
场景 = 队长:队友,…:放技能的干员:技能号，例如 texas:exusiai,lappland:texas:0。每个场景各跑一次 game/tests/synergy_capture.tscn（窗口放屏幕外、静音），
拼成一条 H.264 yuv420p mp4（build/syn_<对名>.mp4），每段带字幕（谁放技能 → 谁合击）。"""
import sys, json, pathlib, subprocess
ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools'))
import godot_runner as gr
from PIL import Image, ImageDraw, ImageFont

name, title = sys.argv[1], sys.argv[2]
scenes = sys.argv[3:]
NAMES = {'texas': '德克萨斯', 'exusiai': '能天使', 'lappland': '拉普兰德', 'skadi': '斯卡蒂', 'ulpianus': '乌尔比安', 'gladiia': '歌蕾蒂娅', 'specter_unchained': '归溟幽灵鲨', 'skalter': '浊心斯卡蒂'}
font = None
for fp in ('C:/Windows/Fonts/msyh.ttc', 'C:/Windows/Fonts/simhei.ttf'):
    try:
        font = ImageFont.truetype(fp, 26); break
    except Exception:
        pass
cap = ROOT / 'build' / ('syn_' + name + '_cap')
cap.mkdir(parents=True, exist_ok=True)
idx = 0
for si, sc in enumerate(scenes):
    parts = sc.split(':')
    lead, mates, caster, skill = parts[:4]
    ready = parts[4] if len(parts) > 4 else ''
    tag = 'syn_%s_%d' % (name, si)
    args = [gr.find_godot(), '--audio-driver', 'Dummy', '--path', str(ROOT / 'game'), '--fixed-fps', '60', '--resolution', '960x540',
            '--position', '-3000,0', 'res://tests/synergy_capture.tscn', '--', '--regression', '--balance', '--seed=1', '--op=' + lead, '--squad=' + mates,
            '--cast=' + caster, '--skill=' + skill, '--ready=' + ready, '--capture-secs=5.5', '--capture-out=' + tag]
    o, e, timeout = gr.run_godot(args, 900)
    print(tag, 'TIMEOUT' if timeout else 'ok', (o or '')[-80:].strip())
    d = ROOT / 'build' / tag
    for fp in sorted(d.glob('f_*.png')):
        im = Image.open(fp).convert('RGB')
        dr = ImageDraw.Draw(im)
        dr.rectangle([0, im.height - 56, im.width, im.height], fill=(0, 0, 0))
        dr.text((20, im.height - 46), '%s：%s 放技能 → 搭档合击' % (title, NAMES.get(caster, caster)), font=font, fill=(255, 220, 120))
        im.save(cap / ('c_%05d.png' % idx))
        idx += 1
import imageio_ffmpeg
mp4 = ROOT / 'build' / ('syn_' + name + '.mp4')
subprocess.run([imageio_ffmpeg.get_ffmpeg_exe(), '-y', '-framerate', '30', '-i', str(cap / 'c_%05d.png'), '-vf', 'format=yuv420p', '-c:v', 'libx264', '-crf', '24', '-movflags', '+faststart', str(mp4)], check=True)
print(mp4, round(mp4.stat().st_size / 1048576, 2), 'MB')
