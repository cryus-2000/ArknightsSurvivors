# -*- coding: utf-8 -*-
"""灯火三档对照录像（docs/222）：同一局里依次把灯火钉在 通明 100 → 暗淡 20 → 寂灭 0，各录 --secs 秒原速 30 帧。
游戏静音录不到声，按 world.gd 的心跳节拍（暗淡 1.25 秒、寂灭 0.95 秒，-6 / -3 dB）把 lamp_heart.wav 铺进音轨，听节拍与音色用。
用法：python tools/lamp_tiers_rec.py [--at 70] [--secs 6]   输出：build/lamp_rec/lamp_tiers_1102.mp4（帧目录录完即删）"""
import argparse, glob, os, shutil, subprocess, sys, wave
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import godot_runner as GR
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
ap = argparse.ArgumentParser()
ap.add_argument("--at", type=float, default=70.0)
ap.add_argument("--secs", type=float, default=6.0)
ap.add_argument("--seed", type=int, default=3)
ap.add_argument("--op", default="mizuki")
a = ap.parse_args()
out = os.path.join(ROOT, "build", "lamp_rec")
fdir = os.path.join(out, "frames")
shutil.rmtree(fdir, ignore_errors=True)
os.makedirs(fdir)
t1, t2, t3 = a.at, a.at + a.secs, a.at + 2 * a.secs
hold = "--lamphold=%g:100,%g:20,%g:0" % (t1 - 2, t2, t3)
args = [GR.find_godot(), "--path", os.path.join(ROOT, "game"), "--audio-driver", "Dummy", "--fixed-fps", "30", "--",
        "--balance", "--realtime", "--rtfrom=%g" % max(0.0, t1 - 4), "--nodeath", "--seed=%d" % a.seed, "--op=" + a.op, "--bot=expert",
        hold, "--recframes=%g,%d" % (t1, int(3 * a.secs * 30)), "--shotdir=" + fdir.replace(os.sep, "/"), "--maxt=%d" % (t3 + a.secs + 10)]
o, e, to = GR.run_godot(args, 1800)
n = len(glob.glob(os.path.join(fdir, "rec_*.png")))
print("frames", n, "errors", GR.script_errors(o, e)[:5], "timeout" if to else "")

# 心跳音轨（同 world.gd 节拍；暗淡档要等 vfx.dark_k 过 0.5，约 0.3 秒后第一下）
import numpy as np
SR = 44100
with wave.open(os.path.join(ROOT, "game", "audio", "sfx", "lamp_heart.wav")) as w:
    hb = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(np.float64) / 32767.0
dur = n / 30.0
trk = np.zeros(int((dur + 2) * SR))
t = a.secs + 0.3
while t < dur:
    out_seg = t >= 2 * a.secs
    i = int(t * SR)
    trk[i:i + len(hb)] += hb[:len(trk) - i] * (10 ** ((-3.0 if out_seg else -6.0) / 20.0))
    t += 0.95 if out_seg else 1.25
trk = trk[:int(dur * SR)]
wav = os.path.join(out, "heart_track.wav")
with wave.open(wav, "wb") as w:
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
    w.writeframes((np.clip(trk, -1, 1) * 32767).astype(np.int16).tobytes())

import imageio_ffmpeg
mp4 = os.path.join(out, "lamp_tiers_1102.mp4")
subprocess.run([imageio_ffmpeg.get_ffmpeg_exe(), "-y", "-loglevel", "error", "-framerate", "30", "-i", os.path.join(fdir, "rec_%05d.png"), "-i", wav,
                "-vf", "scale=1280:-2", "-c:v", "libx264", "-crf", "24", "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "96k", "-shortest", mp4], check=True)
shutil.rmtree(fdir, ignore_errors=True)
print(mp4, os.path.getsize(mp4), "secs", dur)
