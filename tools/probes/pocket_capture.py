# -*- coding: utf-8 -*-
"""10-25 囊海爬行者 1/3 血无敌自爆演示录像：经 godot_runner 跑 game/tests/pocket_capture.tscn（窗口放屏幕外、静音）。
    python tools/probes/pocket_capture.py <out> [秒] [干员]
帧存 build/<out>/f_####.png，再用 tools/promo_gif.py build/<out> <gif> 30 拼 GIF。
"""
import sys, pathlib
ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools'))
import godot_runner as gr

out = sys.argv[1]
secs = sys.argv[2] if len(sys.argv) > 2 else '14'
op = sys.argv[3] if len(sys.argv) > 3 else 'exusiai'
args = [gr.find_godot(), '--audio-driver', 'Dummy', '--path', str(ROOT / 'game'), '--fixed-fps', '60', '--resolution', '960x540',
        '--position', '-3000,0', 'res://tests/pocket_capture.tscn', '--', '--regression', '--balance', '--seed=1', '--op=' + op,
        '--capture-out=' + out, '--capture-secs=' + secs]
o, e, timeout = gr.run_godot(args, 600)
print((o or '')[-300:])
print('TIMEOUT' if timeout else 'ok')
