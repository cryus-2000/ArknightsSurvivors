# -*- coding: utf-8 -*-
"""pixelfx 不加限制试验（斯卡蒂）实战录像：同种子旧版 / 新版各录一段，再左右拼一段。

原速 30 帧（--realtime --fixed-fps 30），--playclock 让命中定格照玩家局生效（批跑 / TRACE 不受影响），1920×1080，原色。
帧先存到 --tmp（缺省系统临时目录，1080p 每帧约 2–3 MB），编码完删掉。
用法：python tools/px_unleashed_rec.py [--seed 13] [--at 420] [--secs 120] [--extra "--maxprog --sptest"] [--only old|new] [--out 目录]
"""
import argparse, glob, os, shutil, subprocess, sys, tempfile
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import godot_runner as GR
import imageio_ffmpeg

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
FF = imageio_ffmpeg.get_ffmpeg_exe()
ap = argparse.ArgumentParser()
ap.add_argument("--seed", type=int, default=13)
ap.add_argument("--at", type=float, default=420.0)
ap.add_argument("--secs", type=float, default=120.0)
ap.add_argument("--extra", default="")
ap.add_argument("--only", default="")
ap.add_argument("--tmp", default=tempfile.gettempdir())
ap.add_argument("--out", default=os.path.join(ROOT, "build", "px_unleashed"))
a = ap.parse_args()
os.makedirs(a.out, exist_ok=True)


def enc(src_glob_dir, mp4, max_mib=25.0):
    """按时长定码率，保证不超过 max_mib（留 8% 余量）"""
    kbps = int(max_mib * 0.92 * 8 * 1024 / a.secs)
    subprocess.run([FF, "-y", "-loglevel", "error", "-framerate", "30", "-i", os.path.join(src_glob_dir, "rec_%05d.png"), "-c:v", "libx264", "-preset", "slow",
                    "-b:v", "%dk" % kbps, "-maxrate", "%dk" % int(kbps * 1.3), "-bufsize", "%dk" % (kbps * 2), "-pix_fmt", "yuv420p", mp4], check=True)


def rec(tag, on):
    fdir = os.path.join(a.tmp, "pxul_" + tag)
    shutil.rmtree(fdir, ignore_errors=True)
    os.makedirs(fdir)
    args = [GR.find_godot(), "--path", os.path.join(ROOT, "game"), "--resolution", "1920x1080", "--audio-driver", "Dummy", "--fixed-fps", "30", "--",
            "--balance", "--realtime", "--playclock", "--rtfrom=%g" % max(0.0, a.at - 3), "--nodeath", "--seed=%d" % a.seed, "--op=skadi", "--bot=expert",
            "--recframes=%g,%d" % (a.at, int(a.secs * 30)), "--shotdir=" + fdir.replace(os.sep, "/"), "--maxt=%d" % (a.at + a.secs + 10),
            "--bal=fx/px_unleashed=%d" % (1 if on else 0)] + a.extra.split()
    o, e, to = GR.run_godot(args, 3600)
    n = len(glob.glob(os.path.join(fdir, "rec_*.png")))
    mp4 = os.path.join(a.out, tag + ".mp4")
    enc(fdir, mp4)
    shutil.rmtree(fdir, ignore_errors=True)
    print(tag, "frames", n, "errors", GR.script_errors(o, e)[:3], "timeout" if to else "", "%.1f MiB" % (os.path.getsize(mp4) / 1048576), flush=True)
    return mp4


tags = {"old": False, "new": True}
for t, on in tags.items():
    if not a.only or a.only == t:
        rec(t, on)
old, new = os.path.join(a.out, "old.mp4"), os.path.join(a.out, "new.mp4")
if os.path.exists(old) and os.path.exists(new) and not a.only:
    kbps = int(25.0 * 0.92 * 8 * 1024 / a.secs)
    subprocess.run([FF, "-y", "-loglevel", "error", "-i", old, "-i", new, "-filter_complex", "[0:v]scale=960:-2[l];[1:v]scale=960:-2[r];[l][r]hstack",
                    "-c:v", "libx264", "-preset", "slow", "-b:v", "%dk" % kbps, "-maxrate", "%dk" % int(kbps * 1.3), "-bufsize", "%dk" % (kbps * 2),
                    "-pix_fmt", "yuv420p", "-r", "30", os.path.join(a.out, "side_by_side.mp4")], check=True)
    print("side_by_side %.1f MiB" % (os.path.getsize(os.path.join(a.out, "side_by_side.mp4")) / 1048576))
