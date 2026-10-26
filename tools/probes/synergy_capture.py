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
font_s = ImageFont.truetype('C:/Windows/Fonts/msyh.ttc', 20)
cap = ROOT / 'build' / ('syn_' + name + '_cap')
cap.mkdir(parents=True, exist_ok=True)
for _old in cap.glob('c_*.png'):
    _old.unlink()
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
    partner = ''
    for f in lg['frames']:
        if f['marks']:
            partner = f['marks'][0]['who']
            break
    lead_id = lg['frames'][0].get('lead', lead) if lg['frames'] else lead
    trail = []   # 搭档最近几帧的屏幕位置，画拖影
    shown_dash = shown_hit = False
    hit_n = 0
    after_n = 0
    for fp in sorted(d.glob('f_*.png')):
        fr = int(fp.stem.split('_')[1])
        info = stages.get(fr, {'stage': 'pre', 'marks': [], 'ops': {}})
        st = info['stage']
        if st == 'after':
            after_n += 1
            if after_n > 36:   # 收势只留约 1.2 秒，后面是怪群和队伍糊成一团的空镜头
                continue
        im = Image.open(fp).convert('RGBA')
        ov = Image.new('RGBA', im.size, (0, 0, 0, 0))
        dr = ImageDraw.Draw(ov)
        ops = info.get('ops', {})
        # 搭档拖影：最近 12 帧的位置连成一条渐隐的粗线（冲刺途中和命中后短暂保留）
        if partner in ops:
            trail.append((ops[partner][0] * sx, ops[partner][1] * sx))
            trail = trail[-12:]
        if st in ('dash', 'hit') and len(trail) > 1:
            for i in range(1, len(trail)):
                al = int(220 * i / len(trail))
                dr.line([trail[i - 1], trail[i]], fill=(90, 220, 255, al), width=3 + int(7 * i / len(trail)))
        elif st not in ('dash', 'hit'):
            trail = trail[-1:]
        for m in info['marks']:
            px, py = m['p'][0] * sx, m['p'][1] * sx - 26
            dr.ellipse([px - 30, py - 30, px + 30, py + 30], outline=(255, 230, 80, 255), width=3)
            if m['t']:
                tx, ty = m['t'][0] * sx, m['t'][1] * sx
                dr.line([tx - 18, ty - 18, tx + 18, ty + 18], fill=(255, 60, 60, 255), width=5)
                dr.line([tx - 18, ty + 18, tx + 18, ty - 18], fill=(255, 60, 60, 255), width=5)
        # 头顶名字：放技能的人（橙）/ 搭档（青）——只在录像里加
        for oid, col, role in ((lead_id, (255, 170, 60, 255), '放技能'), (partner, (80, 230, 255, 255), '合击')):
            if oid and oid in ops:
                x, y = ops[oid][0] * sx, ops[oid][1] * sx
                text = '%s ' % role + NAMES.get(oid, oid)
                w = dr.textlength(text, font=font_s)
                dr.rounded_rectangle([x - w / 2 - 8, y - 112, x + w / 2 + 8, y - 82], radius=8, fill=(0, 0, 0, 190))
                dr.text((x - w / 2, y - 109), text, font=font_s, fill=col)
        im = Image.alpha_composite(im, ov).convert('RGB')
        dr = ImageDraw.Draw(im)
        dr.rectangle([0, im.height - 56, im.width, im.height], fill=(0, 0, 0))
        lab = LABEL.get(st, st)
        if st == 'hit' and info['marks']:
            w = info['marks'][0]['who']
            casted = int(info.get('casts', {}).get(w, 0)) > int(base.get(w, 0))
            lab = lab + ('（%s 放出了自己的技能）' % NAMES.get(w, w) if casted else '（技能没就绪：普通一击 / 弹幕）')
        dr.text((20, im.height - 46), '%s｜%s' % (title, lab), font=font, fill=(255, 220, 120))
        # 慢放：放技能 / 冲刺 3 倍；命中前几帧 4 倍；冲刺出发、命中各停顿
        reps = 1
        if st in ('cast', 'dash'):
            reps = 3
        elif st == 'hit':
            hit_n += 1
            reps = 4 if hit_n <= 6 else 2
        if st == 'dash' and not shown_dash:
            shown_dash = True
            reps += 8
        if st == 'hit' and not shown_hit:
            shown_hit = True
            reps += 22
        for _ in range(reps):
            im.save(cap / ('c_%05d.png' % idx))
            idx += 1
import imageio_ffmpeg
mp4 = ROOT / 'build' / ('syn_' + name + '.mp4')
subprocess.run([imageio_ffmpeg.get_ffmpeg_exe(), '-y', '-framerate', '30', '-i', str(cap / 'c_%05d.png'), '-vf', 'format=yuv420p', '-c:v', 'libx264', '-crf', '24', '-movflags', '+faststart', str(mp4)], check=True)
print(mp4, round(mp4.stat().st_size / 1048576, 2), 'MB')
