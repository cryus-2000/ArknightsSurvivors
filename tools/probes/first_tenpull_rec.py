"""新手开局全流程录屏（10-26）：game/tests/first_tenpull_rec.tscn（标题引导 → 十连 → 拖动开包（拉开一半 → 拉回 → 再拉开）→ 揭示 → 十人总览）
每 2 帧存一张，转 mp4（H.264 yuv420p + AAC，手机可直接播）。

声音：测试局一律静音（Master 总线静音，不改），录屏脚本让 Sfx 记下每次真正放出的音效（渲染帧号、名字、音量、音高，开包光的循环音每帧一条），
这里按记录从 game/audio/sfx/*.wav 离线混音成 wav 再合进视频——没有任何声音从扬声器放出来。只有音效，没有背景音乐。

用法：python -X utf8 tools/probes/first_tenpull_rec.py [desktop|phone]（缺省 desktop）
输出：主仓库 build/first_tenpull/<dev>/rec_*.jpg、mix.wav 与 first_tenpull_<dev>.mp4（30 fps）
窗口在屏幕外、静音；只走 tools/godot_runner.py。
"""
import glob
import json
import os
import shutil
import subprocess
import sys
import wave

import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
import godot_runner as gr  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
game = os.path.join(ROOT, 'game')
SFX = os.path.join(game, 'audio', 'sfx')
OUT = os.path.join(gr.common_root(ROOT), 'build', 'first_tenpull')
SR = 44100
FPS = 60.0


def load_wav(name, cache={}):
    if name not in cache:
        w = wave.open(os.path.join(SFX, name + '.wav'))
        sr, ch = w.getframerate(), w.getnchannels()
        x = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(np.float64) / 32768.0
        if ch > 1:
            x = x.reshape(-1, ch).mean(1)
        cache[name] = (x, sr)
    return cache[name]


def mix(trace, frame0, n_video_frames):
    dur = n_video_frames / 30.0 + 3.0
    out = np.zeros(int(dur * SR))
    hum = [e for e in trace if e[1] == 'hh_hum~']
    for fr, name, vol, pitch in trace:
        if name == 'hh_hum~':
            continue
        try:
            x, sr = load_wav(name)
        except FileNotFoundError:
            continue
        step = sr / SR * pitch   # 音高 = 播放速度
        idx = np.arange(0, len(x) - 1, step)
        y = np.interp(idx, np.arange(len(x)), x) * 10 ** (vol / 20.0)
        at = int((fr - frame0) / FPS * SR)
        if at < 0:
            continue
        j = min(len(out), at + len(y))
        out[at:j] += y[: j - at]
    if hum:
        x, sr = load_wav('hh_hum')
        phase = 0.0
        hum.sort(key=lambda e: e[0])
        for k, (fr, _, vol, pitch) in enumerate(hum):
            at = int((fr - frame0) / FPS * SR)
            nxt = hum[k + 1][0] if k + 1 < len(hum) and hum[k + 1][0] - fr <= 2 else fr + 1
            n = int((nxt - fr) / FPS * SR)
            if at < 0 or n <= 0:
                continue
            ph = phase + np.arange(n) * (sr / SR * pitch)
            y = np.interp(ph % len(x), np.arange(len(x)), x) * 10 ** (vol / 20.0)
            phase = (phase + n * sr / SR * pitch) % len(x)
            j = min(len(out), at + n)
            out[at:j] += y[: j - at]
    pk = np.abs(out).max()
    if pk > 0.89:
        out *= 0.89 / pk   # 防削波（只整体压，不改各音相对音量）
    return out


def write_wav(path, y):
    with wave.open(path, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((np.clip(y, -1, 1) * 32767).astype(np.int16).tobytes())


if __name__ == '__main__':
    dev = sys.argv[1] if len(sys.argv) > 1 else 'desktop'
    res, extra = ('1280x720', []) if dev == 'desktop' else ('1480x720', ['--touch'])
    d = os.path.join(OUT, dev)
    shutil.rmtree(d, ignore_errors=True)
    os.makedirs(d, exist_ok=True)
    gr.ensure_imported(game)
    so, se, to = gr.run_godot([gr.find_godot(), '--path', game, '--resolution', res, '--position', '-4000,0', '--fixed-fps', '60',
                               '--audio-driver', 'Dummy', 'res://tests/first_tenpull_rec.tscn', '--', '--shotdir=' + d, '--roster=new'] + extra, 900)
    tr = None
    for ln in (so + se).splitlines():
        if ln.startswith('SFXTRACE '):
            tr = json.loads(ln[9:])
        elif 'SCRIPT' in ln or 'FIRSTREC' in ln or 'Parse' in ln:
            print(ln[:300])
    n = len(glob.glob(os.path.join(d, 'rec_*.jpg')))
    import imageio_ffmpeg  # noqa: E402
    ff = imageio_ffmpeg.get_ffmpeg_exe()
    mp4 = os.path.join(OUT, 'first_tenpull_%s.mp4' % dev)
    args = [ff, '-y', '-loglevel', 'error', '-framerate', '30', '-i', os.path.join(d, 'rec_%04d.jpg')]
    if tr:
        wav = os.path.join(d, 'mix.wav')
        write_wav(wav, mix(tr['trace'], tr['frame0'], n))
        args += ['-i', wav, '-c:a', 'aac', '-b:a', '160k', '-shortest']
        print('sfx events', len(tr['trace']))
    args += ['-vf', 'scale=1280:-2', '-c:v', 'libx264', '-crf', '20', '-pix_fmt', 'yuv420p', '-movflags', '+faststart', mp4]
    subprocess.run(args, check=True)
    print('frames', n, mp4, 'timeout' if to else 'ok')
