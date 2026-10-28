"""寻访十连录屏（10-28）：game/tests/headhunt_ten_rec.tscn（单抽一次 → 十连一次），每 2 帧存一张，转 mp4（30 fps，H.264 + AAC）。
声音同 first_tenpull_rec.py：测试局静音，按 Sfx 记录离线混音（只有音效）。
用法：python -X utf8 tools/probes/headhunt_ten_rec.py [desktop|phone]
输出：主仓库 build/headhunt_ten/<dev>/rec_*.jpg 与 headhunt_ten_<dev>.mp4
"""
import glob
import json
import os
import shutil
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
import godot_runner as gr  # noqa: E402
from first_tenpull_rec import mix, write_wav  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
game = os.path.join(ROOT, 'game')
OUT = os.path.join(gr.common_root(ROOT), 'build', 'headhunt_ten')

if __name__ == '__main__':
    dev = sys.argv[1] if len(sys.argv) > 1 else 'desktop'
    res, extra = ('1280x720', []) if dev == 'desktop' else ('1480x720', ['--touch'])
    d = os.path.join(OUT, dev)
    shutil.rmtree(d, ignore_errors=True)
    os.makedirs(d, exist_ok=True)
    gr.ensure_imported(game)
    so, se, to = gr.run_godot([gr.find_godot(), '--path', game, '--resolution', res, '--position', '-4000,0', '--fixed-fps', '60',
                               '--audio-driver', 'Dummy', 'res://tests/headhunt_ten_rec.tscn', '--', '--shotdir=' + d, '--roster=start5'] + extra, 900)
    tr = None
    for ln in (so + se).splitlines():
        if ln.startswith('SFXTRACE '):
            tr = json.loads(ln[9:])
        elif 'SCRIPT' in ln or 'TENREC' in ln or 'Parse' in ln:
            print(ln[:300])
    n = len(glob.glob(os.path.join(d, 'rec_*.jpg')))
    import imageio_ffmpeg  # noqa: E402
    ff = imageio_ffmpeg.get_ffmpeg_exe()
    mp4 = os.path.join(OUT, 'headhunt_ten_%s.mp4' % dev)
    args = [ff, '-y', '-loglevel', 'error', '-framerate', '30', '-i', os.path.join(d, 'rec_%04d.jpg')]
    if tr:
        wav = os.path.join(d, 'mix.wav')
        write_wav(wav, mix(tr['trace'], tr['frame0'], n))
        args += ['-i', wav, '-c:a', 'aac', '-b:a', '160k', '-shortest']
    args += ['-vf', 'scale=1280:-2', '-c:v', 'libx264', '-crf', '22', '-pix_fmt', 'yuv420p', '-movflags', '+faststart', mp4]
    subprocess.run(args, check=True)
    print('frames', n, '%.1fs' % (n / 30.0), mp4, 'timeout' if to else 'ok')
