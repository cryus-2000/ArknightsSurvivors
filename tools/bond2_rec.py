# -*- coding: utf-8 -*-
"""羁绊技 v2（docs/294）送审录像：每对两段——前段（约 22 秒解锁演出卡 + 第一次释放）、后段（约 8 分钟后怪多时再放一次，看清不清楚）。
原速 30 帧（--realtime --fixed-fps 30）、原色、1920×1080；一次只开 1 个 Godot（本机限 1 个），逐段串行。
前段用 --bal=bond2/unlock_at 把解锁推到有怪的时候（只影响录像，缺省 -1 = 关）；全员 --prog=8（精二）。
用法：python tools/bond2_rec.py [--pairs rival,penguin,inq] [--out 目录] [--crf 24]
"""
import argparse, os, shutil, subprocess, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import godot_runner as GR
import imageio_ffmpeg

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
MAIN = os.path.dirname(os.path.dirname(os.path.dirname(ROOT))) if ".claude" in ROOT else ROOT
FF = imageio_ffmpeg.get_ffmpeg_exe()
PAIRS = {"rival": ("texas", "lappland"), "penguin": ("exusiai", "texas"), "inq": ("irene", "lumen")}
NAMES = {"rival": "宿敌_十字旧怨", "penguin": "企鹅物流_急件航线", "inq": "灯下审决_提灯宣判"}
ap = argparse.ArgumentParser()
ap.add_argument("--pairs", default="rival,penguin,inq")
ap.add_argument("--out", default=os.path.join(MAIN, "Claude outputs", "bond_v2_1106"))
ap.add_argument("--crf", type=int, default=24)
ap.add_argument("--seed", type=int, default=3)
ap.add_argument("--late", type=float, default=480.0)
ap.add_argument("--late_secs", type=float, default=26.0)
a = ap.parse_args()
tmp = os.path.join(ROOT, "build", "bond2_rec")
os.makedirs(a.out, exist_ok=True)


def seg(key, t0, secs, rtfrom, extra):
    op, mate = PAIRS[key]
    d = os.path.join(tmp, "%s_%d" % (key, int(t0)))
    shutil.rmtree(d, ignore_errors=True)
    os.makedirs(d)
    args = [GR.find_godot(), "--path", os.path.join(ROOT, "game"), "--audio-driver", "Dummy", "--fixed-fps", "30", "--resolution", "1920x1080", "--",
            "--balance", "--nodeath", "--seed=%d" % a.seed, "--bot=expert", "--op=" + op, "--squad=" + mate, "--prog=8",
            "--bal=link/bond_v2=1", "--bal=bond2/log=1", "--realtime", "--rtfrom=%g" % rtfrom, "--recframes=%g,%d" % (t0, int(secs * 30)), "--recchoice",
            "--shotdir=" + d.replace(os.sep, "/"), "--maxt=%d" % (t0 + secs + 2)] + extra
    o, e, to = GR.run_godot(args, 2400)
    errs = GR.script_errors(o, e)[:3]
    casts = [ln for ln in (o or "").splitlines() if ln.startswith("BOND2")]
    print(key, t0, "errors:", errs, "timeout" if to else "", casts)
    mp4 = d + ".mp4"
    subprocess.run([FF, "-y", "-loglevel", "error", "-framerate", "30", "-i", os.path.join(d, "rec_%05d.png"), "-c:v", "libx264", "-crf", str(a.crf),
                    "-preset", "slow", "-pix_fmt", "yuv420p", mp4], check=True)
    shutil.rmtree(d, ignore_errors=True)
    return mp4


for key in a.pairs.split(","):
    p1 = seg(key, 21.6, 12.0, 20.0, ["--bal=bond2/unlock_at=22"])
    p2 = seg(key, a.late, a.late_secs, a.late - 3.0, [])
    lst = os.path.join(tmp, key + "_list.txt")
    open(lst, "w").write("file '%s'\nfile '%s'\n" % (p1.replace(os.sep, "/"), p2.replace(os.sep, "/")))
    out = os.path.join(a.out, "bond2_%s.mp4" % NAMES[key])
    subprocess.run([FF, "-y", "-loglevel", "error", "-f", "concat", "-safe", "0", "-i", lst, "-c", "copy", out], check=True)
    print("OUT", out, "%.1f MiB" % (os.path.getsize(out) / 1048576.0))
