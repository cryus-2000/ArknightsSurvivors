# -*- coding: utf-8 -*-
"""10-23 手动普攻探针：每名干员无头起一局（PLAY 模式、无机器人），打开手动普攻、模拟按住攻击键指向右，
队长左侧放一只木桩，probe 秒后打印 MANUALPROBE：普攻出手次数 / 子弹数 / 木桩掉血（应为 0：不吸附背后的敌人）。
    python tools/probes/manual_aim_probe.py [--game <game 目录>] [--ops a,b] [--t 6] [--jobs 4]
"""
import argparse, os, sys
from concurrent.futures import ThreadPoolExecutor

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, 'tools'))
import godot_runner as gr

ap = argparse.ArgumentParser()
ap.add_argument('--game', default=os.path.join(ROOT, 'game'))
ap.add_argument('--ops', default='')
ap.add_argument('--t', type=float, default=6.0)
ap.add_argument('--jobs', type=int, default=4)
ap.add_argument('--dx', type=float, default=-220.0, help='木桩相对队长的 x，负 = 背后')
ap.add_argument('--line', type=int, default=1, help='沿 +x 每 60 px 放几只木桩（穿透验收）')
ap.add_argument('--dy', type=float, default=0.0, help='木桩线每只的 y 递增（排在弹道上：能天使约 17、流明约 22）')
ap.add_argument('--mode', default='hold', help='hold = 一直按住攻击键；tap = 每 1.5 秒轻点一次')
ap.add_argument('--move', default='0,0', help='移动输入 x,y（手动攻击方向取它）')
ap.add_argument('--input', default='sim', help='sim = 直接写 doctor；kb = 真实键盘事件；mouse = 真实鼠标；touch = 触屏攻击键')
ap.add_argument('--card', type=int, default=0, help='先选几次「贯穿」卡')
ap.add_argument('--relic', default='', help='先给的藏品编号（穿甲弹 265）')
a = ap.parse_args()
game = os.path.abspath(a.game)
ops = [x for x in a.ops.split(',') if x] or sorted(f[:-5] for f in os.listdir(os.path.join(game, 'data', 'characters')) if f.endswith('.json'))
gr.ensure_imported(game)


def one(op):
    args = [gr.find_godot(), '--headless', '--audio-driver', 'Dummy', '--path', game, 'res://tests/manual_aim_probe.tscn', '--',
            '--regression', '--seed=1', '--op=' + op, '--probe-op=' + op, '--probe-t=%g' % a.t, '--probe-dx=%g' % a.dx, '--probe-line=%d' % a.line, '--probe-dy=%g' % a.dy, '--probe-card=%d' % a.card, '--probe-mode=' + a.mode, '--probe-input=' + a.input, '--probe-move=' + a.move, '--probe-relic=' + a.relic]
    o, e, to = gr.run_godot(args, 300)
    line = [l for l in (o or '').splitlines() if l.startswith('MANUALPROBE')]
    errs = [l for l in (o or '').splitlines() + (e or '').splitlines() if 'SCRIPT ERROR' in l]
    return op, (line[-1] if line else 'MANUALPROBE op=%s FAILED timeout=%s' % (op, to)), errs[:2]


with ThreadPoolExecutor(max_workers=a.jobs) as ex:
    for op, line, errs in ex.map(one, ops):
        print(line)
        for e in errs:
            print('   ', e[:200])
