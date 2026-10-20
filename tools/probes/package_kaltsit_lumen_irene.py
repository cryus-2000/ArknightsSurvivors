"""凯尔希本体 / 流明 / 艾丽妮：原作条（cb_18）+ Spine 新做条 → 64 画布 @2x（超界 96），时序不改出手时刻。

用法：python tools/probes/package_kaltsit_lumen_irene.py [--apply]
  不带 --apply：只出候选到 build/op_klc/<id>/<槽>/（逐帧 PNG + 帧条 + timing.json），供 review_kaltsit_lumen_irene.py 出审阅图。
  --apply：写 art/incoming/op_<id>_<槽>@2x.png、改 game/data/characters/<id>.json、删旧 48 / 1x 条。
新做条先跑 tools/spine_run_trial/run_trial.js（cfg 见 SPINE 表），本脚本只读其 frames/。
"""
from pathlib import Path
import json
import math
import sys
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
CB = Path('E:/ArknightsSurvivors/.worktrees/codex-art/art/incoming/cb_18_prts_native_actions_1017')
TRIAL = ROOT / 'build/spine_run_trial'
OUT = ROOT / 'build/op_klc'
INC = ROOT / 'art/incoming'

# cb_18 192 画布 → run_trial 128 画布（原点 (64,120)）的裁切起点：按 Idle t=0 两边像素配准量得（kaltsit 33 / lumen 28 / irene 32）
CROP = {'kaltsit': (32, 33), 'lumen': (32, 28), 'irene': (32, 32)}

# 旧时序（不改出手时刻）：(总时长, 出手时刻)；旧条 frames/fps，出手 (fire+0.5)/fps
OLD = {
    ('kaltsit', 'attack'): (4 / 14, 2.5 / 14), ('kaltsit', 'skill'): (6 / 12, 3.5 / 12), ('kaltsit', 'command'): (6 / 12, 2.5 / 12),
    ('lumen', 'attack'): (4 / 12, 2.5 / 12), ('lumen', 'skill'): (6 / 12, 3.5 / 12),
    ('irene', 'attack'): (5 / 12, 1.5 / 12), ('irene', 'skill'): (7 / 12, 3.5 / 12),
}

# 槽 → 来源。native: (原作轨, 出手帧)；spine: run_trial 的输出目录（相对 build/spine_run_trial/<id>/）
# time: 'loop' = 原作总时长均分；'run' = 8 帧 40/3 fps；('old', 键, 出手帧) = 前摇 / 收势分别按原作帧长比例压进旧时长
SLOTS = {
    'kaltsit': {
        'idle': ('native', 'Idle', 'loop'),
        'run': ('spine', 'frames', 'run'),
        'attack': ('native', 'Attack', ('old', 'attack', 3)),
        'skill': ('same', 'attack', ('old', 'skill', 3)),
        'command': ('spine', 'command/frames', ('old', 'command', 3)),
    },
    'lumen': {
        'idle': ('native', 'Idle', 'loop'),
        'run': ('spine', 'frames', 'run'),
        'attack': ('spine', 'attack/frames', ('old', 'attack', 5)),
        'attack_beam': ('spine', 'attack_beam/frames', ('old', 'attack', 4)),
        'skill': ('native', 'Skill_1', ('old', 'skill', 2)),
        'skill_s2': ('native', 'Skill_2', ('old', 'skill', 4)),
        'skill_s3_start': ('native', 'Skill_3_Begin', ('old', 'skill', 4)),
        'skill_s3_loop': ('native', 'Skill_3_Idle', 'loop'),
        'skill_s3_end': ('native', 'Skill_3_End', 'native'),
    },
    'irene': {
        'idle': ('native', 'Idle', 'loop'),
        'run': ('spine', 'frames', 'run'),
        'attack': ('native', 'Attack', ('old', 'attack', 3)),
        'attack_retrial': ('spine', 'attack_retrial/frames', ('thrusts', [2, 4, 6], [1.5 / 12, 1.5 / 12 + 2 / 12, 1.5 / 12 + 4 / 12], 0.62)),
        'finisher': ('spine', 'finisher/frames', ('fps', 16)),
        'skill': ('spine', 's1/frames|Skill_1', ('old', 'skill', 2)),
        'skill_s2': ('spine', 's2/frames|Skill_2', ('old', 'skill', 2)),   # 原作轨按 cb_18 同一采样时刻重出，去掉原作刀光（F_Weapon(2)）
        'skill_s3_start': ('spine', 's3_start/frames|Skill_3_Start', ('old', 'skill', 4)),
        'skill_s3_loop': ('spine', 's3_loop/frames', ('fps', 4)),
        'skill_s3_end': ('spine', 's3_end/frames', ('fps', 12)),
    },
}


def manifest(op):
    return json.loads((CB / op / 'manifest.json').read_text(encoding='utf-8'))


def native_frames(op, action):
    """cb_18 原作帧对齐到 256 舞台（原点 (128,240)，= 128 画布 (64,120) + 64 边）。"""
    m = manifest(op)
    act = next(a for a in m['actions'] if a['action'] == action)
    cx, cy = CROP[op]
    base = m['canvas_by_action']['Idle']['anchor']
    ax, ay = m['canvas_by_action'][action]['anchor']
    dx, dy = round(ax - base[0]), round(ay - base[1])   # 加边画布（如艾丽妮 S3 起手 204）相对 192 的原点差
    frames = []
    for i in range(act['frames']):
        im = Image.open(CB / op / action / f'{action}_{i:02d}.png').convert('RGBA')
        stage = Image.new('RGBA', (256, 256))
        stage.alpha_composite(im, (64 - cx - dx, 64 - cy - dy)) if 64 - cx - dx >= 0 and 64 - cy - dy >= 0 else stage.paste(im.crop((cx + dx - 64, cy + dy - 64, cx + dx + 192, cy + dy + 192)), (0, 0))
        frames.append(stage)
    d = list(act['frame_durations'])
    if len(d) > 1 and d[-1] < 0.05:   # 末帧是轨道终点采样（0.01 s），按均值给它一个可见时长
        d[-1] = sum(d[:-1]) / (len(d) - 1)
    return frames, d, act['duration']


def spine_frames(op, sub):
    d = TRIAL / op / sub
    out = []
    for p in sorted(d.glob('f[0-9][0-9].png')):
        im = Image.open(p).convert('RGBA'); s = im.width; pad = (256 - s) // 2
        stage = Image.new('RGBA', (256, 256)); stage.alpha_composite(im, (pad, pad)); out.append(stage)
    return out


def exact_split(weights, total):
    """按比例分 total，逐项相加（同 GDScript 顺序）的和与 total 逐位相等（末项按 ulp 微调）。"""
    w = [x / sum(weights) * total for x in weights]
    head = 0.0
    for x in w[:-1]: head += x
    last = total - head
    for k in range(200):
        for cand in (last, ):
            if head + cand == total and cand > 0:
                return w[:-1] + [cand]
        last = math.nextafter(last, math.inf if head + last < total else -math.inf)
    raise ValueError('cannot split exactly')


def timing(kind, n, native_d=None, native_total=None, op=None):
    if kind == 'loop':
        return {'frame_durations': exact_split([1] * n, native_total)}
    if kind == 'native':
        return {'frame_durations': exact_split(native_d, sum(native_d))}
    if kind == 'run':
        return {'fps': 40 / 3}
    if kind[0] == 'fps':
        return {'fps': kind[1]}
    if kind[0] == 'old':
        T, F = OLD[(op, kind[1])]; f = kind[2]
        w = native_d or [1] * n
        pre = exact_split(w[:f], F) if f else []
        d = pre + [x / sum(w[f:]) * (T - F) for x in w[f:]]
        d = exact_split(d, T)
        s = 0.0
        for x in d[:f]: s += x
        assert abs(s - F) < 1e-12, (op, kind, s, F)
        return {'frame_durations': d, 'fire_time': F, 'fire': f}
    if kind[0] == 'thrusts':
        idx, times, total = kind[1], kind[2], kind[3]
        marks = [0.0] + times + [total]; frs = [0] + idx + [n]; d = []
        for a in range(len(marks) - 1):
            k = frs[a + 1] - frs[a]; d += [(marks[a + 1] - marks[a]) / k] * k
        return {'frame_durations': exact_split(d, total)}
    raise ValueError(kind)


def fit_canvas(frames):
    """64 画布（128 @2x）装得下就裁 128，否则 96（192）/ 128（256）；原点保持 (64,120) 口径 + 加边。"""
    a = np.zeros((256, 256), bool)
    for f in frames: a |= np.asarray(f)[:, :, 3] > 0
    for size in (128, 192, 256):
        pad = (256 - size) // 2
        if a.sum() == a[pad:pad + size, pad:pad + size].sum():
            return size, [f.crop((pad, pad, pad + size, pad + size)) for f in frames]
    raise ValueError('超出 256')


def build(op):
    res = {}
    for slot, (src, name, kind) in SLOTS[op].items():
        if src == 'same':
            res[slot] = dict(res[name]); res[slot]['same'] = name
            frames_d = res[name]['_nd']
            res[slot].update(timing(kind, res[name]['frames'], frames_d, None, op))
            continue
        nd = ntot = None
        if src == 'native':
            frames, nd, ntot = native_frames(op, name)
        else:
            sub, _, act = name.partition('|')
            frames = spine_frames(op, sub)
            if act: _, nd, ntot = native_frames(op, act)   # 时长沿用原作采样
        size, cut = fit_canvas(frames)
        spec = {'frames': len(cut), 'size': size, '_nd': nd}
        spec.update(timing(kind, len(cut), nd, ntot, op))
        d = OUT / op / slot; d.mkdir(parents=True, exist_ok=True)
        for p in d.glob('f*.png'): p.unlink()
        for i, im in enumerate(cut): im.save(d / f'f{i:02d}.png')
        strip = Image.new('RGBA', (size * len(cut), size))
        for i, im in enumerate(cut): strip.paste(im, (i * size, 0))
        strip.save(d / 'strip@2x.png')
        spec['src'] = f'{src}:{name}'
        res[slot] = spec
    for v in res.values(): v.pop('_nd', None)
    (OUT / op / 'timing.json').write_text(json.dumps(res, ensure_ascii=False, indent=1), encoding='utf-8')
    return res


if __name__ == '__main__':
    for op in SLOTS:
        r = build(op)
        print(op, {k: (v['frames'], v.get('size'), round(sum(v['frame_durations']), 4) if 'frame_durations' in v else v.get('fps'), v.get('fire_time')) for k, v in r.items()})
