"""新手开局全流程录屏（10-26）：game/tests/first_tenpull_rec.tscn（标题引导 → 十连 → 揭示 → 十人总览）每 2 帧存一张，转 mp4（H.264 yuv420p，手机可直接播）。

用法：python -X utf8 tools/probes/first_tenpull_rec.py [desktop|phone]（缺省 desktop）
输出：主仓库 build/first_tenpull/<dev>/rec_*.jpg 与 first_tenpull_<dev>.mp4（30 fps）
窗口在屏幕外、静音；只走 tools/godot_runner.py。
"""
import glob
import os
import shutil
import subprocess
import sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
import godot_runner as gr  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
game = os.path.join(ROOT, 'game')
OUT = os.path.join(gr.common_root(ROOT), 'build', 'first_tenpull')
dev = sys.argv[1] if len(sys.argv) > 1 else 'desktop'
res, extra = ('1280x720', []) if dev == 'desktop' else ('1480x720', ['--touch'])
d = os.path.join(OUT, dev)
shutil.rmtree(d, ignore_errors=True)
os.makedirs(d, exist_ok=True)
gr.ensure_imported(game)
so, se, to = gr.run_godot([gr.find_godot(), '--path', game, '--resolution', res, '--position', '-4000,0', '--fixed-fps', '60',
                           '--audio-driver', 'Dummy', 'res://tests/first_tenpull_rec.tscn', '--', '--shotdir=' + d, '--roster=new'] + extra, 600)
for ln in (so + se).splitlines():
    if 'SCRIPT' in ln or 'FIRSTREC' in ln or 'Parse' in ln:
        print(ln[:300])
import imageio_ffmpeg  # noqa: E402
ff = imageio_ffmpeg.get_ffmpeg_exe()
mp4 = os.path.join(OUT, 'first_tenpull_%s.mp4' % dev)
subprocess.run([ff, '-y', '-loglevel', 'error', '-framerate', '30', '-i', os.path.join(d, 'rec_%04d.jpg'), '-vf', 'scale=1280:-2',
                '-c:v', 'libx264', '-crf', '20', '-pix_fmt', 'yuv420p', '-movflags', '+faststart', mp4], check=True)
print('frames', len(glob.glob(os.path.join(d, 'rec_*.jpg'))), mp4, 'timeout' if to else 'ok')
