"""10-21 动画 bug 实机截图：经 godot_runner 跑 game/tests/anim_bugs_capture.tscn（窗口放屏幕外、静音）。
用法：python -X utf8 tools/probes/anim_bugs_capture.py <输出子目录> <干员> <技能下标|idle> [advance 次数]"""
from pathlib import Path
import sys
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools'))
import godot_runner as gr
out, op, what = sys.argv[1], sys.argv[2], sys.argv[3]
adv = sys.argv[4] if len(sys.argv) > 4 else '6'
args = [gr.find_godot(), '--audio-driver', 'Dummy', '--path', str(ROOT / 'game'), '--fixed-fps', '60', '--resolution', '960x540',
        '--position', '-3000,0', 'res://tests/anim_bugs_capture.tscn', '--', '--regression', '--balance', '--seed=1', '--op=' + op,
        '--capture-op=' + op, '--capture-what=' + what, '--capture-adv=' + adv, '--capture-out=' + out]
o, e, timeout = gr.run_godot(args, 300)
print(o[-1500:] + '\n' + e[-1500:])
assert not timeout and not gr.script_errors(o, e) and 'failures=0' in o
