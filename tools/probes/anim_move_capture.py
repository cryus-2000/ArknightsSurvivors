"""10-24 动作审计（docs/140）实机录像：经 godot_runner 跑 game/tests/anim_move_capture.tscn（屏幕外、静音），
队长放技能 / 普攻时按「走 – 停」来回移动，逐帧截图后裁出队长周围合成 1/3 速 gif（60 帧截图按 20 fps 播）。
用法：python -X utf8 tools/probes/anim_move_capture.py <输出子目录> <干员> <技能下标|attack> [--total 300] [--skill-at 20] [--walk 45,30] [--speed 150] [--game <game 目录>]
输出：build/<子目录>/<干员>_<what>/f_*.png、log.json、<干员>_<what>.gif
"""
import argparse, os, sys
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools'))
import godot_runner as gr

ap = argparse.ArgumentParser()
ap.add_argument('out'); ap.add_argument('op'); ap.add_argument('what')
ap.add_argument('--total', type=int, default=300)
ap.add_argument('--skill-at', type=int, default=20)
ap.add_argument('--walk', default='45,30')
ap.add_argument('--speed', type=float, default=150.0)
ap.add_argument('--game', default=str(ROOT / 'game'))
ap.add_argument('--zoom', type=int, default=2)
ap.add_argument('--lead', default='', help='另一名队长（录这名干员当队员时的样子）')
ap.add_argument('--atk', action='store_true', help='技能期间照常普攻')
ap.add_argument('--mobs', type=int, default=0, help='起手前在周围刷几只近战杂兵')
a = ap.parse_args()
game = Path(a.game).resolve()
args = [gr.find_godot(), '--audio-driver', 'Dummy', '--path', str(game), '--fixed-fps', '60', '--resolution', '960x540',
        'res://tests/anim_move_capture.tscn', '--', '--regression', '--balance', '--seed=1', '--op=' + (a.lead or a.op)] + (['--squad=' + a.op] if a.lead else []) + ['--capture-atk'] * a.atk + ['--capture-mobs=%d' % a.mobs, 
        '--capture-op=' + a.op, '--capture-what=' + a.what, '--capture-total=%d' % a.total, '--capture-skill-at=%d' % a.skill_at,
        '--capture-walk=' + a.walk, '--capture-speed=%g' % a.speed, '--capture-out=' + a.out]
o, e, timeout = gr.run_godot(args, 600)
assert not timeout and not gr.script_errors(o, e) and 'failures=0' in o, (o[-800:], e[-800:])
d = game.parent / 'build' / a.out / ('%s_%s' % (a.op, a.what))
fs = sorted(d.glob('f_*.png'))
w, h = Image.open(fs[0]).size
import json
log = json.load(open(d / 'log.json'))
def box_of(i):   # 镜头跟随队长：队长在画面中心；队员按记录的相对位置裁（世界 1 px = 屏幕 1 px）
    ox, oy = log[i].get('off', [0, 0]) if a.lead else (0, 0)
    cx, cy = int(w // 2 + ox), int(h // 2 + oy)
    return (cx - 120, cy - 110, cx + 120, cy + 50)
box = box_of(0)
frames = [Image.open(f).convert("RGB").crop(box_of(i)).resize(((box[2] - box[0]) * a.zoom, (box[3] - box[1]) * a.zoom), Image.NEAREST) for i, f in enumerate(fs)]
gif = d.parent / ('%s_%s.gif' % (a.op, a.what))
frames[0].save(gif, save_all=True, append_images=frames[1:], duration=50, loop=0)
print(gif)
