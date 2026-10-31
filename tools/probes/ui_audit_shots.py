"""全界面巡检截图（11-01 UI 巡检，docs/211）：标题 → 难度 / 选人 → 载入 → 局内 HUD → 三选一 / 藏品 / 招募 / 商店 / 暂停 / 横幅 / Tab
→ 结算 / 作战记录 → 图鉴 / 寻访 / 局外成长 / 勋章 / 设置 / 致谢，桌面 1280×720 + 手机横屏 1170×540（--touch），各存一套 PNG。

用法：python -X utf8 tools/probes/ui_audit_shots.py <输出目录> [项,项,…]
窗口在屏幕外、静音（godot_runner：临时用户目录 + 固定设置）。每项输出到 <输出目录>/<项>_<desktop|phone>/。
"""
import os
import shutil
import sys
from concurrent.futures import ThreadPoolExecutor
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
import godot_runner as gr  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
out = os.path.abspath(sys.argv[1])
game = os.path.join(ROOT, 'game')
gr.ensure_imported(game)
godot = gr.find_godot()
AT = ['--autotest']
JOBS = {
    'boot': ['--bootshot=ready', '--bal=ui/boot_v=3'],
    'title': ['--titleshot'],
    'diff': ['--diffshot=1,3'],
    'guide': ['--guideshot'],
    'meta': ['--metashot'],
    'medal': ['--medalshot'],
    'credits': ['--creditsshot'],
    'set0': ['--settingsshot', '--settingstab=0'],
    'set1': ['--settingsshot', '--settingstab=1'],
    'set2': ['--settingsshot', '--settingstab=2'],
    'oppick': ['--unlockall', '--opshot', '--opid=mizuki'],
    'codex': ['--unlockall', '--galleryshot=0,0,0,1.5', '--galleryid=mizuki'],
    'codex_enemy': ['--unlockall', '--galleryshot=1,0,0,1.5'],
    'loading': ['--loadingshot'],
    'hunt': AT + ['--huntshot', '--roster=start5', '--rostertickets=1,1,1'],
    'hud': ['--balance', '--seed=1', '--op=mizuki', '--realtime', '--nodeath', '--maxt=22', '--shots=1260'],
    'levelup': AT + ['--motionshot=levelup,1.2'],
    'relic': AT + ['--motionshot=relic,1.2'],
    'recruit': AT + ['--motionshot=recruit,1.2'],
    'swap': AT + ['--motionshot=swap,1.2'],
    'shop': AT + ['--motionshot=shop,1.2'],
    'pause': AT + ['--motionshot=pause,1.2'],
    'banner': AT + ['--motionshot=banner,1.0'],
    'tab': AT + ['--tabshot=600'],
    'win': AT + ['--statsshot=20'],
    'fail': AT + ['--statsshot=20,dead'],
    'choices': AT + ['--choiceshots', '--maxt=320'],
}
ONLY = sys.argv[2].split(',') if len(sys.argv) > 2 else None
if ONLY:
    JOBS = {k: v for k, v in JOBS.items() if k in ONLY}
DEVS = [('desktop', '1280x720', []), ('phone', '1170x540', ['--touch'])]


def run(item):
    (name, args), (dev, res, extra) = item
    d = os.path.join(out, name + '_' + dev)
    shutil.rmtree(d, ignore_errors=True)
    os.makedirs(d, exist_ok=True)
    so, se, to = gr.run_godot([godot, '--path', game, '--resolution', res, '--position', '-4000,0', '--fixed-fps', '60', '--',
                               '--shotdir=' + d] + extra + args, 420)
    errs = [ln for ln in ((so or '') + (se or '')).splitlines() if 'SCRIPT ERROR' in ln or 'Parse Error' in ln]
    with open(os.path.join(d, 'log.txt'), 'w', encoding='utf-8') as f:
        f.write((so or '') + '\n----\n' + (se or ''))
    return name, dev, sorted(x for x in os.listdir(d) if x.endswith('.png')), errs[:3], to


os.makedirs(out, exist_ok=True)
items = [(j, v) for j in JOBS.items() for v in DEVS]
with ThreadPoolExecutor(3) as ex:
    for name, dev, got, errs, to in ex.map(run, items):
        print(name, dev, len(got), got[:4], 'TIMEOUT' if to else '', errs, flush=True)
