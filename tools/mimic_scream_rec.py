# -*- coding: utf-8 -*-
"""箱形恐鱼尖叫圈录像（10-28）：开局局内快进到 --at 秒，主控身边刷一只现形尖叫的箱形恐鱼，录 --secs 秒原速 30 帧。
用法：python tools/mimic_scream_rec.py [--at 40] [--secs 7]   输出：build/mimic_rec/mimic_scream.mp4（帧目录录完即删）"""
import argparse, glob, os, shutil, subprocess, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import godot_runner as GR
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
ap = argparse.ArgumentParser()
ap.add_argument("--at", type=float, default=40.0)
ap.add_argument("--secs", type=float, default=7.0)
ap.add_argument("--seed", type=int, default=3)
a = ap.parse_args()
out = os.path.join(ROOT, "build", "mimic_rec")
fdir = os.path.join(out, "frames")
shutil.rmtree(fdir, ignore_errors=True)
os.makedirs(fdir)
rec0 = a.at - 0.5
args = [GR.find_godot(), "--path", os.path.join(ROOT, "game"), "--audio-driver", "Dummy", "--fixed-fps", "30", "--",
        "--balance", "--realtime", "--rtfrom=%g" % max(0.0, a.at - 3), "--nodeath", "--seed=%d" % a.seed, "--op=mizuki", "--bot=expert",
        "--mimicscream=%g" % a.at, "--recframes=%g,%d" % (rec0, int(a.secs * 30)), "--shotdir=" + fdir.replace(os.sep, "/"), "--maxt=%d" % (a.at + a.secs + 10)]
o, e, to = GR.run_godot(args, 1200)
n = len(glob.glob(os.path.join(fdir, "rec_*.png")))
print("frames", n, "errors", GR.script_errors(o, e)[:5], "timeout" if to else "")
import imageio_ffmpeg
mp4 = os.path.join(out, "mimic_scream.mp4")
subprocess.run([imageio_ffmpeg.get_ffmpeg_exe(), "-y", "-loglevel", "error", "-framerate", "30", "-i", os.path.join(fdir, "rec_%05d.png"),
                "-vf", "scale=1280:-2", "-c:v", "libx264", "-crf", "24", "-pix_fmt", "yuv420p", mp4], check=True)
print(mp4, os.path.getsize(mp4), "secs", n / 30)
