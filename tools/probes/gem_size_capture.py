"""10-21 结晶缩小截图：经 godot_runner 跑 game/tests/gem_size_capture.tscn（窗口放屏幕外、静音）。用法：python -X utf8 tools/probes/gem_size_capture.py <输出子目录>"""
from pathlib import Path
import sys
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools'))
import godot_runner as gr
args = [gr.find_godot(), '--audio-driver', 'Dummy', '--path', str(ROOT / 'game'), '--fixed-fps', '60', '--resolution', '960x540',
        '--position', '-3000,0', 'res://tests/gem_size_capture.tscn', '--', '--regression', '--balance', '--seed=1', '--capture-out=' + sys.argv[1]]
o, e, timeout = gr.run_godot(args, 300)
print(o[-800:] + '\n' + e[-800:])
assert not timeout and not gr.script_errors(o, e) and 'failures=0' in o
