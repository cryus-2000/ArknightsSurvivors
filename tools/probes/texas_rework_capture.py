# -*- coding: utf-8 -*-
"""10-23 德克萨斯普攻重设计演示录像：经 godot_runner 跑 game/tests/texas_rework_capture.tscn（窗口放屏幕外、静音），
队长视角（--op=texas）或队友视角（--op=skadi --squad=texas）各录 8 秒，帧存 build/<out>/texas_<mode>/f_####.png（每 2 帧一张 = 30 fps）。
    python tools/probes/texas_rework_capture.py <out> leader|mate [秒]
再用 tools/promo_gif.py <帧目录> <gif> 30 拼 GIF。
"""
import os, sys, pathlib
ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools'))
import godot_runner as gr

out, mode = sys.argv[1], sys.argv[2]
secs = sys.argv[3] if len(sys.argv) > 3 else '8'
who = ['--op=texas'] if mode == 'leader' else ['--op=skadi', '--squad=texas']
args = [gr.find_godot(), '--audio-driver', 'Dummy', '--path', str(ROOT / 'game'), '--fixed-fps', '60', '--resolution', '960x540',
        '--position', '-3000,0', 'res://tests/texas_rework_capture.tscn', '--', '--regression', '--balance', '--seed=1'] + who + [
        '--capture-out=' + out, '--capture-mode=' + mode, '--capture-secs=' + secs] + (['--capture-s3'] if 's3' in sys.argv[4:] else [])
o, e, timeout = gr.run_godot(args, 600)
print((o or '')[-300:])
print('TIMEOUT' if timeout else 'ok')
