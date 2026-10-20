"""图鉴格子 / 选人名册卡截图（10-21 小人居中、统一缩放的改前改后对照）。

用法：python -X utf8 tools/probes/roster_card_shots.py <游戏工作树根> <输出目录>
窗口放到屏幕外（不打扰用户），带 -- 参数即静音。
"""
import os
import sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
import godot_runner as gr  # noqa: E402

root, out = os.path.abspath(sys.argv[1]), os.path.abspath(sys.argv[2])
game = os.path.join(root, 'game')
gr.ensure_imported(game)
godot = gr.find_godot()
SHOTS = {
    'codex_desktop': ('1280x720', ['--unlockall', '--galleryshot=0,0,0,1.5', '--galleryid=irene'], 'shot_gallery_ui.png'),
    'codex_phone': ('720x1480', ['--unlockall', '--touch', '--galleryshot=0,0,0,1.5', '--galleryid=irene'], 'shot_gallery_ui.png'),
    'oppick_desktop': ('1280x720', ['--unlockall', '--opshot', '--opid=irene'], 'shot_oppick.png'),
    'oppick_phone': ('1480x720', ['--unlockall', '--touch', '--opshot', '--opid=irene'], 'shot_oppick.png'),
    'codex_hoshiguma': ('1280x720', ['--unlockall', '--galleryshot=0,0,0,1.5', '--galleryid=hoshiguma'], 'shot_gallery_ui.png'),
    'oppick_wisadel': ('1280x720', ['--unlockall', '--opshot', '--opid=wisadel'], 'shot_oppick.png'),
    'oppick_specter': ('1280x720', ['--unlockall', '--opshot', '--opid=specter_unchained'], 'shot_oppick.png'),   # 名册在后半段（选人 / 封面干员共用 roster_card）
}
only = sys.argv[3].split(',') if len(sys.argv) > 3 else None
SHOTS = {k: v for k, v in SHOTS.items() if not only or k in only}
for k, (res, args, fn) in SHOTS.items():
    d = os.path.join(out, k)
    os.makedirs(d, exist_ok=True)
    gr.run_godot([godot, '--path', game, '--resolution', res, '--position', '-4000,0', '--', '--shotdir=' + d] + args, 120)
    print(k, '好' if os.path.exists(os.path.join(d, fn)) else '缺', flush=True)
