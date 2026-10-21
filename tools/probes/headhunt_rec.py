"""寻访演出实机截图 / 录屏（docs/124）：--huntshot 静帧 + --huntrec 录屏转 gif，桌面 1280×720 与手机横屏 1480×720（--touch）。

用法：python -X utf8 tools/probes/headhunt_rec.py [shot|rec|all]（缺省 all）
输出：主仓库 build/headhunt_rec/<desktop|phone>/shot_hunt_<n>.png、headhunt_<desktop|phone>.gif（15 fps，宽 640）
窗口在屏幕外、静音；演出按帧计时（--fixed-fps 60），录屏与真实节奏一致。
"""
import glob
import os
import shutil
import sys
from concurrent.futures import ThreadPoolExecutor
from PIL import Image
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
import godot_runner as gr  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
game = os.path.join(ROOT, 'game')
OUT = os.path.join(gr.common_root(ROOT), 'build', 'headhunt_rec')
what = sys.argv[1] if len(sys.argv) > 1 else 'all'
gr.ensure_imported(game)
godot = gr.find_godot()
DEVS = [('desktop', '1280x720', []), ('phone', '1480x720', ['--touch'])]
BASE = ['--autotest', '--huntshot', '--roster=start5', '--rostertickets=3,0,1']   # 3 张寻访凭证 + 1 张人事调度函（roster.gd 还是旧三券时，定向寻访走人事调度函）


def run(item):
    kind, (dev, res, extra) = item
    d = os.path.join(OUT, dev + ('_rec' if kind == 'rec' else ''))
    shutil.rmtree(d, ignore_errors=True)
    os.makedirs(d, exist_ok=True)
    args = BASE + (['--huntrec'] if kind == 'rec' else [])
    so, se, _to = gr.run_godot([godot, '--path', game, '--resolution', res, '--position', '-4000,0', '--fixed-fps', '60', '--audio-driver', 'Dummy', '--', '--shotdir=' + d] + extra + args, 600)
    for ln in (so + se).splitlines():
        if 'ERROR' in ln or 'SCRIPT' in ln or 'HUNT' in ln:
            print(dev, kind, ln[:300], flush=True)
    if kind == 'rec':
        fs = sorted(glob.glob(os.path.join(d, 'rec_*.png')))
        frames = []

        for f in fs[::2]:   # 30 fps 录的 → 15 fps
            im = Image.open(f).convert('RGB')
            frames.append(im.resize((640, round(im.height * 640 / im.width)), Image.LANCZOS).convert('P', palette=Image.ADAPTIVE, colors=128))
        out = os.path.join(OUT, 'headhunt_%s.gif' % dev)
        if frames:
            frames[0].save(out, save_all=True, append_images=frames[1:], duration=67, loop=0, optimize=True)
        return dev, kind, len(fs), out
    return dev, kind, sorted(os.listdir(d)), d


items = [(k, v) for k in (['shot', 'rec'] if what == 'all' else [what]) for v in DEVS]
with ThreadPoolExecutor(2) as ex:
    for r in ex.map(run, items):
        print(*r, flush=True)
