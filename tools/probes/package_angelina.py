"""安洁莉娜 64 画布接入：原作动作条（cb_18）+ Codex dl 跑步 + 浮空移动草稿 → op_angelina_<slot>@2x.png。

不缩放像素：原作条是 192 @2x 舞台、原点 (96,152)；跑步 / 浮空移动由 tools/spine_run_trial 逐附件像素化，
128 @2x、原点 (64,120)，贴进 192 舞台 (32,32) 后与原作条同一原点（Idle 对拍 IoU 0.97，偏移 (32,32) 最优）。
全部帧落在中间 128 内 → 64 画布 foot (32,60)；否则 96 画布 foot (48,76)（docs/108 §5）。
浮空四槽把整帧上移 LIFT（@2x 像素，偶数 = 1x 整像素），json foot 仍是地面，影子画在地面。
时序：普攻 / 浮空普攻 / 技能的总时长与出手时刻沿用旧条（5/12、2.5/12；7/12、3.5/12），只按原生节奏分配各帧时长。

用法：
  python -X utf8 tools/probes/package_angelina.py --preview <目录>   # 候选：GIF 常速 / 慢放、8 倍逐帧、与旧版对照
  python -X utf8 tools/probes/package_angelina.py --apply            # 写 art/incoming 帧条与 angelina.json，删旧 48 / 1x
跑步、浮空移动帧先用 run_trial 生成（--run / --float-move 指定目录）：
  NODE_PATH=E:/ArknightsSurvivors/build/prts_ref/_node/node_modules node tools/spine_run_trial/run_trial.js tools/spine_run_trial/cfg/angelina_dl.json --out <run>
  NODE_PATH=... node tools/spine_run_trial/run_trial.js tools/spine_run_trial/cfg/angelina_float_move.json --out <fm>
"""
from pathlib import Path
import argparse
import hashlib
import json
import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
CODEX = Path('E:/ArknightsSurvivors/.worktrees/codex-art/art/incoming')
CB = CODEX / 'cb_18_prts_native_actions_1017/angelina'
OUT = ROOT / 'art/incoming'
LIFT = 18                                   # 浮空离地 9 个 1x 像素（48 口径 7 × 64/48 ≈ 9，docs/108 §9 估 50–52 行）

ap = argparse.ArgumentParser()
ap.add_argument('--preview'); ap.add_argument('--apply', action='store_true')
ap.add_argument('--run', default=str(ROOT / 'build/spine_run_trial/angelina/dl_swap_hand/frames'))
ap.add_argument('--float-move', default=str(ROOT / 'build/spine_run_trial/angelina/float_move/frames'))
args = ap.parse_args()

provenance = {}


def cb(action, i):
    f = CB / action / f'{action}_{i:02d}.png'
    provenance[f.relative_to(CODEX).as_posix()] = hashlib.sha256(f.read_bytes()).hexdigest()
    im = Image.open(f).convert('RGBA'); assert im.size == (192, 192)
    return im


def trial(folder, i):
    f = Path(folder) / f'f{i:02d}.png'
    im = Image.open(f).convert('RGBA'); assert im.size == (128, 128)
    stage = Image.new('RGBA', (192, 192)); stage.paste(im, (32, 32))
    return stage


def native_durs(action):
    m = json.loads((CB / 'manifest.json').read_text(encoding='utf-8'))
    return next(a for a in m['actions'] if a['action'] == action)['frame_durations']


def lift(im, dy):
    if not dy: return im
    out = Image.new('RGBA', im.size); out.paste(im.crop((0, dy, 192, 192)), (0, 0))
    assert np.asarray(im)[:dy, :, 3].sum() == 0, '上移会裁掉顶部像素'
    return out


def split(durs, fire, total, fire_time):
    """按原生各帧比例把出手前 / 后两段分别压到 fire_time / total - fire_time（出手时刻 = fire 帧起点）。"""
    a, b = durs[:fire], durs[fire:]
    pre = [d * fire_time / sum(a) for d in a]
    post = [d * (total - fire_time) / sum(b) for d in b]
    pre[-1] = fire_time - sum(pre[:-1]) - 1e-9          # 防浮点累加越过出手时刻（V7）
    post[-1] = total - fire_time - sum(post[:-1]) + 1e-9
    return pre + post


def scaled(durs, total):
    return [d * total / sum(durs) for d in durs]


slots = {}
def add(name, frames, durs, **kw):
    assert len(frames) == len(durs) == 8
    slots[name] = dict(frames=frames, durs=durs, **kw)

add('idle', [cb('Idle', i) for i in range(8)], native_durs('Idle'), src='cb Idle')
def ground(im, row=151):
    """跑步贴地：乌尔比安步态带腾空相，像素尺度下支撑脚在 117–119 行间跳、读成一跳一跳；整帧竖移让最低像素落在地面行。"""
    bot = np.where(np.asarray(im)[:, :, 3].any(1))[0][-1]
    out = Image.new('RGBA', im.size); out.paste(im, (0, row - bot)); return out


add('run', [ground(trial(args.run, i)) for i in range(8)], [0.075] * 8, src='Codex dl_angelina_swap_hand_1020（run_trial 逐附件像素化）')
add('attack', [cb('Attack', i) for i in range(8)], split(native_durs('Attack'), 3, 5 / 12, 2.5 / 12), fire=3, fire_time=2.5 / 12,
    src='cb Attack（OnAttack 0.633 s = f3 起点）')
sk = [cb('Skill1_Begin', i) for i in (1, 3, 5, 7)] + [cb('Skill1_Loop', 4)] + [cb('Skill1_End', i) for i in (3, 5, 7)]
add('skill', sk, split([1] * 8, 4, 7 / 12, 3.5 / 12), fire=4, fire_time=3.5 / 12,
    src='cb Skill1_Begin f1/3/5/7 + Skill1_Loop f4（OnAttack）+ Skill1_End f3/5/7')
die = [cb('Die', i) for i in range(8)]
slots['hurt'] = dict(frames=die[:2], durs=[0.1, 0.1], src='cb Die f0–f1（原作无受击轨，同能天使 / 逻各斯口径）')
add('death', die, native_durs('Die'), src='cb Die')
ramp = [0, 2, 4, 8, 12, 14, 16, 18]
add('float_in', [lift(cb('Skill2_Begin', i), ramp[i]) for i in range(8)], [1 / 24] * 8,
    src=f'cb Skill2_Begin，离地 0→{LIFT // 2} 像素')
bob = [0, 0, 2, 2, 2, 2, 0, 0]
add('float', [lift(cb('Skill2_Loop', i), LIFT + bob[i]) for i in range(8)], scaled(native_durs('Skill2_Loop'), 0.75),
    src='cb Skill2_Loop 放慢到 0.75 s，离地 9 像素 + 1 像素浮动')
add('float_move', [lift(trial(args.float_move, i), LIFT) for i in range(8)], [0.075] * 8,
    src='run_trial 浮空草稿（原生 Skill2_Loop t0 为底稿）')
add('float_attack', [lift(cb('Skill2_Loop', i), LIFT) for i in range(8)], split(native_durs('Skill2_Loop'), 4, 5 / 12, 2.5 / 12),
    fire=4, fire_time=2.5 / 12, src='cb Skill2_Loop（OnAttack 0.233 s = f4 起点），离地 9 像素')

for name, s in slots.items():
    s['compact'] = all(np.asarray(f)[:, :, 3].sum() == np.asarray(f.crop((32, 32, 160, 160)))[:, :, 3].sum() for f in s['frames'])
    assert all(set(np.unique(np.asarray(f)[:, :, 3])) <= {0, 255} for f in s['frames']), name


def strip(s):
    fr = [f.crop((32, 32, 160, 160)) for f in s['frames']] if s['compact'] else s['frames']
    w = fr[0].width; out = Image.new('RGBA', (w * len(fr), w))
    for i, f in enumerate(fr): out.paste(f, (w * i, 0))
    return out


OLD = {'idle': 'idle', 'run': 'run', 'attack': 'attack', 'skill': 'skill', 'float_in': 'float_in',
       'float': 'float', 'float_move': 'float_move', 'float_attack': 'float_attack'}


def old_frames(name):
    p = ROOT / f'art/incoming/op_angelina_{OLD[name]}@2x.png' if name in OLD else None
    if not p or not p.exists(): return [], []
    spec = json.loads((ROOT / 'game/data/characters/angelina.json').read_text(encoding='utf-8'))['sprites'][OLD[name]]
    im = Image.open(p).convert('RGBA'); n = spec['frames']; w = im.width // n; fr = []
    for i in range(n):
        st = Image.new('RGBA', (192, 192)); st.paste(im.crop((w * i, 0, w * i + w, w)), (96 - 48, 152 - 92)); fr.append(st)
    return fr, [1 / spec['fps']] * n


def preview(out):
    out = Path(out); out.mkdir(parents=True, exist_ok=True)
    F1, F2 = ImageFont.truetype('C:/Windows/Fonts/msyh.ttc', 11), ImageFont.truetype('C:/Windows/Fonts/msyh.ttc', 24)
    BG, GROUND = (58, 64, 60, 255), (120, 130, 110, 255)
    order = list(slots)
    def frame_at(fr, durs, t):
        t %= sum(durs); acc = 0
        for i, d in enumerate(durs):
            acc += d
            if t < acc: return fr[i]
        return fr[-1]
    def board(t, speed):
        cols, cw = 4, 192
        rows = (len(order) + 1) // 2
        im = Image.new('RGBA', (cols * cw, rows * (cw + 14)), BG); d = ImageDraw.Draw(im)
        for k, name in enumerate(order):
            r, c = k // 2, (k % 2) * 2; y = r * (cw + 14)
            d.text((c * cw + 4, y + 2), f'{name}  旧 | 新', fill=(230, 230, 230, 255), font=F1)
            of, od = old_frames(name); s = slots[name]
            for j, (fr, du) in enumerate([(of, od), (s['frames'], s['durs'])]):
                x = (c + j) * cw
                d.line([(x, y + 14 + 152), (x + cw - 1, y + 14 + 152)], fill=GROUND)
                if fr: im.alpha_composite(frame_at(fr, du, t * speed), (x, y + 14))
        return im.resize((im.width * 2, im.height * 2), Image.NEAREST)
    for tag, speed, total, tick in [('normal', 1.0, 2.1, 0.03), ('slow', 0.25, 2.1 * 4, 0.06)]:
        ims = [board(i * tick, speed).convert('P', palette=Image.ADAPTIVE) for i in range(int(total / tick))]
        ims[0].save(out / f'angelina_{tag}.gif', save_all=True, append_images=ims[1:], duration=int(tick * 1000), loop=0, disposal=2)
    # 8 倍逐帧（1x 的 8 倍 = @2x 的 4 倍），每张两槽
    for k in range(0, len(order), 2):
        group = order[k:k + 2]; Z = 4; cw = 192 * Z
        im = Image.new('RGBA', (cw * 8, (cw + 40) * len(group)), BG); d = ImageDraw.Draw(im)
        for r, name in enumerate(group):
            s = slots[name]; y = r * (cw + 40)
            d.text((8, y + 8), f"{name}  {'64' if s['compact'] else '96'} 画布  {s['src']}", fill=(240, 240, 240, 255), font=F2)
            for i, f in enumerate(s['frames']):
                x = i * cw
                d.rectangle([x + 32 * Z, y + 40 + 32 * Z, x + 160 * Z - 1, y + 40 + 160 * Z - 1], outline=(90, 100, 95, 255))
                d.line([(x, y + 40 + 152 * Z), (x + cw - 1, y + 40 + 152 * Z)], fill=GROUND)
                im.alpha_composite(f.resize((cw, cw), Image.NEAREST), (x, y + 40))
                tag = ' 出手' if s.get('fire') == i else ''
                d.text((x + 8, y + 44), f"f{i}  {s['durs'][i] * 1000:.0f} ms{tag}", fill=(255, 220, 120, 255), font=F2)
        im.convert('RGB').save(out / f'angelina_x8_{"_".join(group)}.png', optimize=True)
    print('preview ->', out)


def apply():
    path = ROOT / 'game/data/characters/angelina.json'
    data = json.loads(path.read_text(encoding='utf-8')); sp = data['sprites']
    for name, s in slots.items():
        tex = f'op_angelina_{name}'
        strip(s).save(OUT / f'{tex}@2x.png')
        (OUT / f'{tex}.png').unlink(missing_ok=True)
        n = len(s['frames']); spec = {'tex': tex, 'frames': n, 'fps': round(n / sum(s['durs']), 6),
                                      'foot': [32, 60] if s['compact'] else [48, 76], 'frame_durations': s['durs']}
        if 'fire' in s: spec.update(fire=s['fire'], fire_time=s['fire_time'])
        sp[name] = spec
    sp['size'] = 64; sp['foot'] = [32, 60]
    path.write_text(json.dumps(data, ensure_ascii=False, indent=1) + '\n', encoding='utf-8')
    (OUT / 'angelina_native_sources.json').write_text(json.dumps(
        {'sources': provenance, 'slots': {k: v['src'] for k, v in slots.items()}}, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print('applied', {k: ('64' if v['compact'] else '96') for k, v in slots.items()})


if args.preview: preview(args.preview)
if args.apply: apply()
