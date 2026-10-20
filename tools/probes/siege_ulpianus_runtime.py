"""Run silent focused checks and actual viewport captures through godot_runner."""
from pathlib import Path
import sys
import tempfile
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools'))
import godot_runner as gr
OUT = ROOT / 'build/siege_ulpianus_runtime'
(OUT / 'tmp').mkdir(parents=True, exist_ok=True)
tempfile.tempdir = str(OUT / 'tmp')
mode = sys.argv[1] if len(sys.argv) > 1 else 'test'
op = sys.argv[2] if len(sys.argv) > 2 else 'siege'
scene = 'siege_ulpianus_art_test' if mode == 'test' else 'siege_ulpianus_art_capture'
args = [gr.find_godot(), '--audio-driver', 'Dummy', '--path', str(ROOT / 'game')]
args += ['--headless'] if mode == 'test' else ['--fixed-fps', '60', '--resolution', '960x540']
args += ['res://tests/' + scene + '.tscn', '--', '--regression', '--balance', '--seed=1', '--op=' + op]
args += ['--squad=ulpianus'] if mode == 'test' else ['--capture-op=' + op]
out, err, timeout = gr.run_godot(args, 180)
(OUT / (op + '_' + mode + '.log')).write_text(out + '\n' + err, encoding='utf-8')
print(out[-2000:] + '\n' + err[-2000:])
assert not timeout and not gr.script_errors(out, err) and 'failures=0' in out
