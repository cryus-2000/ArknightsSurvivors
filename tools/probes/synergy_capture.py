# -*- coding: utf-8 -*-
"""干员连携技演示录像（docs/160）：python tools/probes/synergy_capture.py <对名> <标题> <场景1> [<场景2> …]
场景 = 队长:队友,…:放技能的干员:技能号，例如 texas:exusiai,lappland:texas:0。每个场景各跑一次 game/tests/synergy_capture.tscn（窗口放屏幕外、静音），
拼成一条 H.264 yuv420p mp4（build/syn_<对名>.mp4），每段带字幕（谁放技能 → 谁合击）。"""
import sys, os, json, pathlib, subprocess
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
            '--cast=' + caster, '--skill=' + skill, '--ready=' + ready, '--capture-secs=6.0', '--capture-out=' + tag]
    if not os.environ.get('SYN_ASSEMBLE'):   # SYN_ASSEMBLE=1：不重录，只用已有帧重新拼字幕 / mp4
        o, e, timeout = gr.run_godot(args, 900)
        print(tag, 'TIMEOUT' if timeout else 'ok', (o or '')[-80:].strip())
    d = ROOT / 'build' / tag
    lg = json.loads((d / 'log.json').read_text(encoding='utf-8')) if (d / 'log.json').exists() else {'frames': []}
    print('  casts=%s syn_n=%s' % (lg.get('casts'), lg.get('acts')))
    sz = lg.get('size', [960, 540])
    sx = Image.open(sorted(d.glob('f_*.png'))[0]).width / float(sz[0])
    stages = {f['f']: f for f in lg['frames']}
    LABEL = {'pre': '队伍待命，怪群逼近', 'cast': '① %s 放技能（控场）' % NAMES.get(caster, caster), 'dash': '② 搭档冲向目标（收割）', 'hit': '② 搭档命中', 'after': '收势'}
    prev_stage = ''
    base = {}   # 放技能那一刻各人的施放计数：之后搭档的计数涨了 = 搭档真的放了自己的技能
    for f in lg['frames']:
        if f['stage'] == 'cast':
            base = dict(f['casts'])
            break
    for fp in sorted(d.glob('f_*.png')):
        fr = int(fp.stem.split('_')[1])
        info = stages.get(fr, {'stage': 'pre', 'marks': []})
        st = info['stage']
        im = Image.open(fp).convert('RGB')
        dr = ImageDraw.Draw(im)
        for m in info['marks']:
            px, py = m['p'][0] * sx, m['p'][1] * sx
            dr.ellipse([px - 26, py - 26, px + 26, py + 26], outline=(255, 230, 80), width=3)
            if m['t']:
                tx, ty = m['t'][0] * sx, m['t'][1] * sx
                dr.line([tx - 16, ty - 16, tx + 16, ty + 16], fill=(255, 60, 60), width=4)
                dr.line([tx - 16, ty + 16, tx + 16, ty - 16], fill=(255, 60, 60), width=4)
        dr.rectangle([0, im.height - 56, im.width, im.height], fill=(0, 0, 0))
        lab = LABEL.get(st, st)
        if st == 'hit' and info['marks']:
            w = info['marks'][0]['who']
            casted = int(info.get('casts', {}).get(w, 0)) > int(base.get(w, 0))
            lab = lab + ('（%s 放出了自己的技能）' % NAMES.get(w, w) if casted else '（技能没就绪：普通一击）')
        dr.text((20, im.height - 46), '%s｜%s' % (title, lab), font=font, fill=(255, 220, 120))
        # 慢放：放技能到合击收势这段每帧写 2 次；合击命中那一刻停顿
        reps = 2 if st in ('cast', 'dash', 'hit') else 1
        if st == 'hit' and prev_stage != 'hit':
            reps = 12
        prev_stage = st
        for _ in range(reps):
            im.save(cap / ('c_%05d.png' % idx))
            idx += 1
import imageio_ffmpeg
mp4 = ROOT / 'build' / ('syn_' + name + '.mp4')
subprocess.run([imageio_ffmpeg.get_ffmpeg_exe(), '-y', '-framerate', '30', '-i', str(cap / 'c_%05d.png'), '-vf', 'format=yuv420p', '-c:v', 'libx264', '-crf', '24', '-movflags', '+faststart', str(mp4)], check=True)
print(mp4, round(mp4.stat().st_size / 1048576, 2), 'MB')
