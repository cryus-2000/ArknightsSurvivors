# -*- coding: utf-8 -*-
"""逻各斯 S3「延异视阈」录像（10-28）：逻各斯当队长，--onlyskill=2 反复放 S3，原速 30 帧（--realtime），从 --at 秒录 --secs 秒。
用法：python tools/logos_s3_rec.py [--at 60] [--secs 45] [--out 名字]   输出：build/logos_s3_rec/<名字>.mp4（帧目录录完即删）"""
import argparse, glob, os, shutil, subprocess, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import godot_runner as GR
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
ap = argparse.ArgumentParser()
ap.add_argument("--at", type=float, default=60.0)
ap.add_argument("--secs", type=float, default=45.0)
ap.add_argument("--seed", type=int, default=3)
ap.add_argument("--out", default="logos_s3_now")
a = ap.parse_args()
out = os.path.join(ROOT, "build", "logos_s3_rec")
fdir = os.path.join(out, "frames_" + a.out)
shutil.rmtree(fdir, ignore_errors=True)
os.makedirs(fdir)
args = [GR.find_godot(), "--path", os.path.join(ROOT, "game"), "--audio-driver", "Dummy", "--fixed-fps", "30", "--",
        "--balance", "--realtime", "--rtfrom=%g" % max(0.0, a.at - 3), "--nodeath", "--seed=%d" % a.seed, "--op=logos", "--bot=expert", "--maxprog",
        "--onlyskill=2", "--recframes=%g,%d" % (a.at, int(a.secs * 30)), "--shotdir=" + fdir.replace(os.sep, "/"), "--maxt=%d" % (a.at + a.secs + 10)]
o, e, to = GR.run_godot(args, 1800)
n = len(glob.glob(os.path.join(fdir, "rec_*.png")))
print("frames", n, "errors", GR.script_errors(o, e)[:5], "timeout" if to else "")
import imageio_ffmpeg
mp4 = os.path.join(out, a.out + ".mp4")
subprocess.run([imageio_ffmpeg.get_ffmpeg_exe(), "-y", "-loglevel", "error", "-framerate", "30", "-i", os.path.join(fdir, "rec_%05d.png"),
                "-vf", "scale=1280:-2", "-c:v", "libx264", "-crf", "24", "-pix_fmt", "yuv420p", mp4], check=True)
print(mp4, os.path.getsize(mp4), "secs", n / 30)
shutil.rmtree(fdir, ignore_errors=True)
