# -*- coding: utf-8 -*-
"""全员干员特效自查录像（10-29）：每人一段（队长释放普攻 + 技能），原速 30 帧（--realtime），出 mp4 + 联系表。
用法：python tools/op_fx_audit_rec.py [--ops a,b] [--at 40] [--secs 24] [--skill N] [--tag 名] [--jobs 3]   输出 build/opfx/<tag>/<干员>.mp4 + <干员>_sheet.png"""
import argparse, glob, os, shutil, subprocess, sys
from concurrent.futures import ThreadPoolExecutor
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import godot_runner as GR
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
ALL = "angelina exusiai eyjafjalla gladiia hoshiguma irene kaltsit lappland logos lumen mizuki saria siege skadi skalter specter_unchained suzuran texas ulpianus wisadel".split()
ap = argparse.ArgumentParser()
ap.add_argument("--ops", default=",".join(ALL)); ap.add_argument("--at", type=float, default=40.0); ap.add_argument("--secs", type=float, default=24.0)
ap.add_argument("--skill", type=int, default=-1); ap.add_argument("--tag", default="now"); ap.add_argument("--jobs", type=int, default=3)
a = ap.parse_args()
out = os.path.join(ROOT, "build", "opfx", a.tag); os.makedirs(out, exist_ok=True)
import imageio_ffmpeg
FF = imageio_ffmpeg.get_ffmpeg_exe()
def one(op):
    fdir = os.path.join(out, "fr_" + op); shutil.rmtree(fdir, ignore_errors=True); os.makedirs(fdir)
    ex = ["--onlyskill=%d" % a.skill] if a.skill >= 0 else []
    args = [GR.find_godot(), "--path", os.path.join(ROOT, "game"), "--audio-driver", "Dummy", "--fixed-fps", "30", "--",
            "--balance", "--realtime", "--rtfrom=%g" % max(0.0, a.at - 3), "--nodeath", "--seed=3", "--op=" + op, "--bot=expert", "--maxprog", "--sptest"] + ex + [
            "--recframes=%g,%d" % (a.at, int(a.secs * 30)), "--shotdir=" + fdir.replace(os.sep, "/"), "--maxt=%d" % (a.at + a.secs + 8)]
    o, e, to = GR.run_godot(args, 1800)
    n = len(glob.glob(os.path.join(fdir, "rec_*.png")))
    mp4 = os.path.join(out, op + ".mp4")
    subprocess.run([FF, "-y", "-loglevel", "error", "-framerate", "30", "-i", os.path.join(fdir, "rec_%05d.png"), "-vf", "scale=960:-2", "-c:v", "libx264", "-crf", "26", "-pix_fmt", "yuv420p", mp4])
    subprocess.run([FF, "-y", "-loglevel", "error", "-i", mp4, "-vf", "fps=1/2,crop=iw*0.5:ih*0.55:iw*0.25:ih*0.2,scale=320:-2,tile=6x2", "-frames:v", "1", os.path.join(out, op + "_sheet.png")])
    shutil.rmtree(fdir, ignore_errors=True)
    print(op, "frames", n, "errors", GR.script_errors(o, e)[:2], "timeout" if to else "", flush=True)
with ThreadPoolExecutor(a.jobs) as ex:
    list(ex.map(one, a.ops.split(",")))
