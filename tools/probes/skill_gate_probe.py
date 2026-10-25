# -*- coding: utf-8 -*-
"""10-25 自动技能门槛探针：python tools/probes/skill_gate_probe.py <队长> <被测干员> [秒]；输出被测干员每次放技能时的最近敌人距离。"""
import sys, pathlib
ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools'))
import godot_runner as gr

lead, who = sys.argv[1], sys.argv[2]
secs = sys.argv[3] if len(sys.argv) > 3 else '120'
squad = [] if lead == who else ['--squad=' + who]
args = [gr.find_godot(), '--headless', '--path', str(ROOT / 'game'), 'res://tests/skill_gate_probe.tscn', '--',
        '--regression', '--balance', '--seed=1', '--op=' + lead] + squad + ['--probe-op=' + who, '--probe-secs=' + secs]
o, e, timeout = gr.run_godot(args, 900)
for ln in (o or '').splitlines():
    if ln.startswith(('PROBE', 'CAST')):
        print(ln)
print('TIMEOUT' if timeout else 'ok')
