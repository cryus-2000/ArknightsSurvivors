"""Codex 界面重置单的现状截图（10-22）：主界面 / 寻访 / 结算 / 局内面板，桌面 1280×720 + 手机 1480×720（--touch）。

用法：python -X utf8 tools/probes/ui_ref_shots.py <输出目录>
窗口在屏幕外、静音；参考图转 JPG（质量 88）入库，控制体积。
"""
import os
import shutil
import sys
from concurrent.futures import ThreadPoolExecutor
from PIL import Image
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
import godot_runner as gr  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
out = os.path.abspath(sys.argv[1])
game = os.path.join(ROOT, 'game')
gr.ensure_imported(game)
godot = gr.find_godot()
tmp = os.path.join(ROOT, 'build', 'ui_ref_tmp')
# 名字: (Godot 参数, 要拷的产物 {源文件: 目标名})
JOBS = {
    'title': (['--titleshot'], {'shot_title.png': '1_main_title'}),
    'hunt': (['--autotest', '--huntshot', '--roster=start5', '--rostertickets=1,1,1'],
             {'shot_hunt_0.png': '2_hunt_reveal', 'shot_hunt_1.png': '2_hunt_pick_class', 'shot_hunt_3.png': '2_hunt_pick_letter', 'shot_hunt_5.png': '2_hunt_wish'}),
    'win': (['--autotest', '--statsshot=20'], {'shot_stats_result.png': '3_result_win', 'shot_stats_overview.png': '3_result_stats'}),
    'fail': (['--autotest', '--statsshot=20,dead'], {'shot_stats_result.png': '3_result_fail'}),
    'hud': (['--balance', '--seed=1', '--op=mizuki', '--realtime', '--nodeath', '--maxt=22', '--shots=1260'], {'shot_1260.png': '4_hud'}),
    'levelup': (['--autotest', '--motionshot=levelup,0.9'], {'*levelup*': '4_levelup'}),
    'shop': (['--autotest', '--motionshot=shop,1.2'], {'*shop*': '4_shop'}),
    'pause': (['--autotest', '--motionshot=pause,0.9'], {'*pause*': '4_pause'}),
    'codex': (['--unlockall', '--galleryshot=0,0,0,1.5', '--galleryid=mizuki'], {'shot_gallery_ui.png': '0_anchor_codex'}),
    'oppick': (['--unlockall', '--opshot', '--opid=mizuki'], {'shot_oppick.png': '0_anchor_oppick'}),
}
ONLY = sys.argv[2].split(',') if len(sys.argv) > 2 else None
if ONLY:
    JOBS = {k: v for k, v in JOBS.items() if k in ONLY}


def run(item):
    (name, (args, files)), (dev, res, extra) = item
    d = os.path.join(tmp, name + '_' + dev)
    shutil.rmtree(d, ignore_errors=True)
    os.makedirs(d, exist_ok=True)
    gr.run_godot([godot, '--path', game, '--resolution', res, '--position', '-4000,0', '--fixed-fps', '60', '--', '--shotdir=' + d] + extra + args, 240)
    got = []
    for src, dst in files.items():
        cands = [f for f in sorted(os.listdir(d)) if (src.strip('*') in f if '*' in src else f == src)]
        if cands:
            Image.open(os.path.join(d, cands[-1])).convert('RGB').save(os.path.join(out, '%s_%s.jpg' % (dst, dev)), quality=88)
            got.append(dst)
    return name, dev, got


os.makedirs(out, exist_ok=True)
items = [(j, v) for j in JOBS.items() for v in (('desktop', '1280x720', []), ('phone', '1480x720', ['--touch']))]
with ThreadPoolExecutor(3) as ex:
    for name, dev, got in ex.map(run, items):
        print(name, dev, got, flush=True)
