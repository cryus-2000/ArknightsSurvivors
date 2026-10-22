# -*- coding: utf-8 -*-
"""10-22 攻击后滑步 / 卡末帧探针：对每名干员无头跑 --probe-t 秒（--balance --bot=expert），
逐帧统计「画面还是出手帧条、出手帧已过、却在移动」的帧数（slide）与「停在末帧 ≥ 8 帧」的次数（stuck）。
    python tools/probes/anim_slide_probe.py [--game <game 目录>] [--ops a,b] [--t 40] [--seed 1] [--jobs 4]
输出每人一行 ANIMPROBE，末尾合计。只读探针（game/tests/anim_slide_probe.gd），不改模拟。
"""
import argparse, json, os, sys
from concurrent.futures import ThreadPoolExecutor

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, 'tools'))
import godot_runner as gr

ap = argparse.ArgumentParser()
ap.add_argument('--game', default=os.path.join(ROOT, 'game'))
ap.add_argument('--ops', default='')
ap.add_argument('--t', type=float, default=40.0)
ap.add_argument('--seed', type=int, default=1)
ap.add_argument('--jobs', type=int, default=4)
a = ap.parse_args()
game = os.path.abspath(a.game)
ops = [x for x in a.ops.split(',') if x] or sorted(f[:-5] for f in os.listdir(os.path.join(game, 'data', 'characters')) if f.endswith('.json'))
gr.ensure_imported(game)


def one(op):
    args = [gr.find_godot(), '--headless', '--audio-driver', 'Dummy', '--path', game, 'res://tests/anim_slide_probe.tscn', '--',
            '--regression', '--balance', '--seed=%d' % a.seed, '--op=' + op, '--bot=expert', '--maxt=%d' % int(a.t + 30), '--probe-t=%g' % a.t]
    o, e, to = gr.run_godot(args, 600)
    line = [l for l in (o or '').splitlines() if l.startswith('ANIMPROBE')]
    errs = [l for l in (o or '').splitlines() + (e or '').splitlines() if 'SCRIPT ERROR' in l]
    return op, (line[-1] if line else 'ANIMPROBE op=%s FAILED timeout=%s' % (op, to)), errs[:2]


tot = {'atk': 0, 'slide': 0, 'stuck': 0}
with ThreadPoolExecutor(max_workers=a.jobs) as ex:
    for op, line, errs in ex.map(one, ops):
        print(line)
        for e in errs:
            print('   ', e[:160])
        for k in tot:
            for tok in line.split():
                if tok.startswith(k + '='):
                    tot[k] += int(tok.split('=')[1])
print('TOTAL atk=%d slide=%d stuck=%d' % (tot['atk'], tot['slide'], tot['stuck']))
