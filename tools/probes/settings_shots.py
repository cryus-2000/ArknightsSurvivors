"""设置页三页截图（10-22 设置精简 16 行 + 画质四档）：桌面 1280×720、手机横屏 1480×720（--touch），窗口在屏幕外、静音。

用法：python -X utf8 tools/probes/settings_shots.py
输出：主仓库 build/settings_shots/<声音|画面|操作>_<desktop|phone>.png 与总览 sheet.jpg
"""
import os
import shutil
import sys
from concurrent.futures import ThreadPoolExecutor
from PIL import Image
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
import godot_runner as gr  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
game = os.path.join(ROOT, 'game')
OUT = os.path.join(gr.common_root(ROOT), 'build', 'settings_shots')
gr.ensure_imported(game)
godot = gr.find_godot()
TABS = [(0, 'sound'), (1, 'display'), (2, 'controls')]
DEVS = [('desktop', '1280x720', []), ('phone', '1480x720', ['--touch'])]
os.makedirs(OUT, exist_ok=True)


def run(item):
    (tab, name), (dev, res, extra) = item
    d = os.path.join(OUT, 'tmp_%s_%s' % (name, dev))
    shutil.rmtree(d, ignore_errors=True)
    os.makedirs(d, exist_ok=True)
    so, se, _to = gr.run_godot([godot, '--path', game, '--resolution', res, '--position', '-4000,0', '--audio-driver', 'Dummy', '--',
                                '--shotdir=' + d, '--settingsshot', '--settingstab=%d' % tab] + extra, 180)
    for ln in (so + se).splitlines():
        if 'SCRIPT ERROR' in ln or 'Parse Error' in ln:
            print(name, dev, ln[:200], flush=True)
    src = os.path.join(d, 'shot_settings.png')
    if os.path.exists(src):
        shutil.copy(src, os.path.join(OUT, '%s_%s.png' % (name, dev)))
    shutil.rmtree(d, ignore_errors=True)
    return name, dev, os.path.exists(os.path.join(OUT, '%s_%s.png' % (name, dev)))


items = [(t, v) for t in TABS for v in DEVS]
with ThreadPoolExecutor(3) as ex:
    for r in ex.map(run, items):
        print(*r, flush=True)
W = 640
ims = [Image.open(os.path.join(OUT, '%s_%s.png' % (n, dv))).convert('RGB') for _t, n in TABS for dv, _r, _e in DEVS if os.path.exists(os.path.join(OUT, '%s_%s.png' % (n, dv)))]
if ims:
    hs = [round(im.height * W / im.width) for im in ims]
    rows = (len(ims) + 1) // 2
    sheet = Image.new('RGB', (W * 2, max(hs) * rows))
    for i, im in enumerate(ims):
        sheet.paste(im.resize((W, hs[i]), Image.LANCZOS), ((i % 2) * W, (i // 2) * max(hs)))
    sheet.save(os.path.join(OUT, 'sheet.jpg'), quality=88)
