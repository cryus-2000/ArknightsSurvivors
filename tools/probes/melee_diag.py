# -*- coding: utf-8 -*-
"""10-24 近战队长诊断：同一套驱动（高手机器人、队长单开、tier 0）逐 seed 跑 --t 秒，汇总 MELEEDIAG（见 game/tests/melee_diag.gd）。
    python tools/probes/melee_diag.py --game <game 目录> --ops texas,lappland --seeds 8 --t 300 --label main [--out build/melee_diag/x.json]
每个 op 输出各指标的均值（胜 / 死 / 时长另算）。
"""
import argparse, json, os, sys
from concurrent.futures import ThreadPoolExecutor

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, 'tools'))
import godot_runner as gr

ap = argparse.ArgumentParser()
ap.add_argument('--game', default=os.path.join(ROOT, 'game'))
ap.add_argument('--ops', default='texas')
ap.add_argument('--seeds', type=int, default=8)
ap.add_argument('--t', type=float, default=300.0)
ap.add_argument('--jobs', type=int, default=4)
ap.add_argument('--label', default='')
ap.add_argument('--out', default='')
a = ap.parse_args()
game = os.path.abspath(a.game)
gr.ensure_imported(game)
ops = [x for x in a.ops.split(',') if x]


def one(job):
    op, seed = job
    args = [gr.find_godot(), '--headless', '--audio-driver', 'Dummy', '--path', game, 'res://tests/melee_diag.tscn', '--',
            '--regression', '--balance', '--bot=expert', '--seed=%d' % seed, '--op=' + op, '--tier=0', '--maxt=%d' % int(a.t + 30), '--diag-t=%g' % a.t]
    o, e, to = gr.run_godot(args, 900)
    for l in (o or '').splitlines():
        if l.startswith('MELEEDIAG '):
            return op, seed, json.loads(l[len('MELEEDIAG '):])
    return op, seed, None


jobs = [(op, s) for op in ops for s in range(1, a.seeds + 1)]
res = {}
with ThreadPoolExecutor(max_workers=a.jobs) as ex:
    for op, seed, r in ex.map(one, jobs):
        res.setdefault(op, []).append(r)
KEYS = ['act_frac', 'atk_per_min', 'move_frac', 'still_frac', 'near_at_atk', 'zero_target_frac', 'sur3_frac', 'sur3_dmg_frac', 'contact_avg', 'dmg_taken_pm', 'kills_pm', 't', 'lv']
summary = {}
for op, rs in res.items():
    ok = [r for r in rs if r]
    m = {k: round(sum(float(r[k]) for r in ok) / max(1, len(ok)), 3) for k in KEYS}
    m['n'] = len(ok)
    m['dead'] = sum(1 for r in ok if r['dead'])
    m['win'] = sum(1 for r in ok if r['win'])
    summary[op] = m
    print('%s [%s] %s' % (op, a.label, json.dumps(m, ensure_ascii=False)))
if a.out:
    os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
    json.dump({'label': a.label, 'summary': summary, 'runs': res}, open(a.out, 'w', encoding='utf-8'), ensure_ascii=False)
