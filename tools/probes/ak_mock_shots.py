"""结算 / 寻访两屏静态样张（docs/125）：autotest --akmock=<屏>，桌面 1280×720 + 手机横屏 1480×720（--touch）。

用法：python -X utf8 tools/probes/ak_mock_shots.py [屏,屏…]（缺省全部）
输出：主仓库 build/ak_mock/<屏>_<desktop|phone>.png 和总览 sheet_<desktop|phone>.jpg；窗口在屏幕外、静音
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
OUT = os.path.join(gr.common_root(ROOT), 'build', 'ak_mock')
SCREENS = ['result', 'hunt', 'reveal', 'pick_class', 'pick_letter', 'hunt_result']
which = sys.argv[1].split(',') if len(sys.argv) > 1 else SCREENS
DEVS = [('desktop', '1280x720', []), ('phone', '1480x720', ['--touch'])]
gr.ensure_imported(game)
godot = gr.find_godot()
os.makedirs(OUT, exist_ok=True)


def run(item):
    scr, (dev, res, extra) = item
    d = os.path.join(gr.common_root(ROOT), 'build', 'ak_mock_tmp', scr + '_' + dev)
    shutil.rmtree(d, ignore_errors=True)
    os.makedirs(d, exist_ok=True)
    so, se, _to = gr.run_godot([godot, '--path', game, '--resolution', res, '--position', '-4000,0', '--audio-driver', 'Dummy', '--',
                                '--shotdir=' + d, '--autotest', '--akmock=' + scr] + extra, 240)
    for ln in (so + se).splitlines():
        if 'SCRIPT ERROR' in ln or 'Parse Error' in ln:
            print(scr, dev, ln[:240], flush=True)
    src = os.path.join(d, 'shot_akmock.png')
    if os.path.exists(src):
        shutil.copy(src, os.path.join(OUT, '%s_%s.png' % (scr, dev)))
        return scr, dev, True
    return scr, dev, False


items = [(s, v) for s in which for v in DEVS]
with ThreadPoolExecutor(3) as ex:
    for r in ex.map(run, items):
        print(*r, flush=True)
for dev in ('desktop', 'phone'):
    fs = [os.path.join(OUT, '%s_%s.png' % (s, dev)) for s in SCREENS if os.path.exists(os.path.join(OUT, '%s_%s.png' % (s, dev)))]
    if not fs:
        continue
    ims = [Image.open(f).convert('RGB') for f in fs]
    w = 640
    hs = [round(im.height * w / im.width) for im in ims]
    sheet = Image.new('RGB', (w * 2, sum(hs[::2]) + (hs[-1] if len(ims) % 2 else 0)), (0, 0, 0))
    y = 0
    for i, im in enumerate(ims):
        sheet.paste(im.resize((w, hs[i]), Image.LANCZOS), ((i % 2) * w, y))
        if i % 2:
            y += hs[i]
    sheet.save(os.path.join(OUT, 'sheet_%s.jpg' % dev), quality=88)
