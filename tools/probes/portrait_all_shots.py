"""选人 / 图鉴舞台立绘全员截图 + 拼图（10-21 水月立绘大小 / 脚底线核对）。

用法：python -X utf8 tools/probes/portrait_all_shots.py <游戏工作树根> <输出目录>
每人一张选人页、一张图鉴页（屏幕外窗口、静音），再把舞台区裁出来按同一脚底线拼成两张总图（红线 = 舞台脚底线）。
"""
import json
import os
import sys
from concurrent.futures import ThreadPoolExecutor
from PIL import Image, ImageDraw
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
import godot_runner as gr  # noqa: E402

root, out = os.path.abspath(sys.argv[1]), os.path.abspath(sys.argv[2])
game = os.path.join(root, 'game')
gr.ensure_imported(game)
godot = gr.find_godot()
ids = sorted(f[:-5] for f in os.listdir(os.path.join(game, 'data', 'characters')) if f.endswith('.json'))
ids = [i for i in ids if json.load(open(os.path.join(game, 'data', 'characters', i + '.json'), encoding='utf-8')).get('recruitable', True)]
JOBS = []
for i in ids:
    JOBS.append(('oppick', i, ['--unlockall', '--opshot', '--opid=' + i], 'shot_oppick.png'))
    JOBS.append(('codex', i, ['--unlockall', '--galleryshot=0,0,0,1.5', '--galleryid=' + i], 'shot_gallery_ui.png'))


def run(job):
    kind, i, args, fn = job
    d = os.path.join(out, kind, i)
    os.makedirs(d, exist_ok=True)
    if not os.path.exists(os.path.join(d, fn)):
        gr.run_godot([godot, '--path', game, '--resolution', '1280x720', '--position', '-4000,0', '--', '--shotdir=' + d] + args, 150)
    return kind, i, os.path.exists(os.path.join(d, fn))


with ThreadPoolExecutor(4) as ex:
    for kind, i, ok in ex.map(run, JOBS):
        print(kind, i, '好' if ok else '缺', flush=True)
# 舞台区（1280 × 720 设计坐标）：选人 / 图鉴的立绘框
BOX = {'oppick': ((600, 230, 962, 548), 'shot_oppick.png', 536), 'codex': ((436, 120, 880, 452), 'shot_gallery_ui.png', 436)}
for kind, (box, fn, foot_y) in BOX.items():
    tiles = []
    for i in ids:
        p = os.path.join(out, kind, i, fn)
        if os.path.exists(p):
            t = Image.open(p).convert('RGB').crop(box)
            d = ImageDraw.Draw(t)
            d.line([(0, foot_y - box[1]), (t.width, foot_y - box[1])], fill=(255, 60, 60))
            d.text((4, 4), i, fill=(255, 255, 0))
            tiles.append(t)
    cols = 6
    w, h = tiles[0].size
    sheet = Image.new('RGB', (w * cols, h * ((len(tiles) + cols - 1) // cols)), (0, 0, 0))
    for n, t in enumerate(tiles):
        sheet.paste(t, ((n % cols) * w, (n // cols) * h))
    sheet.save(os.path.join(out, kind + '_all.png'))
    print(kind, 'sheet', sheet.size)
