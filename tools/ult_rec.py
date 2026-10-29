# -*- coding: utf-8 -*-
"""终结技原型审阅录像（docs/198，10-29）：每段一名队长，局内自动放终结技 / 连携 / 连携终结技，原速 30 帧（--realtime），出 mp4。
用法：python tools/ult_rec.py [--clips texas,exusiai,skalter,kaltsit,ulpianus,cult] [--at 30] [--secs 14] [--tag 名] [--jobs 3]
  每个队长一段：编队带两名有连携的队友，能量倍率调高让终结技在录制窗口里放出；cult = 协同满 + 连携终结技那一段。
  输出 build/ult_rec/<tag>/<段>.mp4，再拼一条 all.mp4。"""
import argparse, glob, os, shutil, subprocess, sys
from concurrent.futures import ThreadPoolExecutor
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import godot_runner as GR
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
CLIPS = {
    "texas": ("texas", "exusiai,lappland", []),
    "exusiai": ("exusiai", "texas,saria", []),
    "skalter": ("skalter", "skadi,gladiia", []),
    "kaltsit": ("kaltsit", "hoshiguma,lumen", []),
    "ulpianus": ("ulpianus", "gladiia,specter_unchained", []),
    "cult": ("texas", "exusiai,lappland", ["--bal=ult/test_cells=7"]),
    "combo": ("texas", "exusiai,siege", ["--bot=master", "--bal=ult/test_fill_at=-1"], 90.0),   # 连携：两人都跟队长冲刺（master 机器人会冲刺）；这段不放终结技
}
ap = argparse.ArgumentParser()
ap.add_argument("--clips", default=",".join(CLIPS)); ap.add_argument("--at", type=float, default=30.0); ap.add_argument("--secs", type=float, default=14.0)
ap.add_argument("--tag", default="now"); ap.add_argument("--jobs", type=int, default=3); ap.add_argument("--extra", default="")
a = ap.parse_args()
out = os.path.join(ROOT, "build", "ult_rec", a.tag); os.makedirs(out, exist_ok=True)
import imageio_ffmpeg
FF = imageio_ffmpeg.get_ffmpeg_exe()


def one(name):
    op, squad, ex = CLIPS[name][:3]
    at = CLIPS[name][3] if len(CLIPS[name]) > 3 else a.at   # 连携段要 1:30 以后（敌人够密）
    fdir = os.path.join(out, "fr_" + name); shutil.rmtree(fdir, ignore_errors=True); os.makedirs(fdir)
    args = [GR.find_godot(), "--path", os.path.join(ROOT, "game"), "--audio-driver", "Dummy", "--fixed-fps", "30", "--",
            "--balance", "--realtime", "--rtfrom=%g" % max(0.0, at - 3), "--nodeath", "--seed=3", "--op=" + op, "--squad=" + squad] + ([] if any(x.startswith("--bot=") for x in ex) else ["--bot=expert"]) + [
            "--maxprog", "--bal=ult/bot_n=1"] + ([] if any(x.startswith("--bal=ult/test_fill_at") for x in ex) else ["--bal=ult/test_fill_at=%g" % (at + 1.5)]) + ex + a.extra.split() + [
            "--recframes=%g,%d" % (at, int(a.secs * 30)), "--shotdir=" + fdir.replace(os.sep, "/"), "--maxt=%d" % (at + a.secs + 8)]
    o, e, to = GR.run_godot([x for x in args if x], 1800)
    n = len(glob.glob(os.path.join(fdir, "rec_*.png")))
    mp4 = os.path.join(out, name + ".mp4")
    subprocess.run([FF, "-y", "-loglevel", "error", "-framerate", "30", "-i", os.path.join(fdir, "rec_%05d.png"), "-vf", "scale=1280:-2", "-c:v", "libx264", "-crf", "24", "-pix_fmt", "yuv420p", mp4])
    shutil.rmtree(fdir, ignore_errors=True)
    ult = [ln for ln in o.splitlines() if ln.startswith("BALANCE ")]
    print(name, "frames", n, "(%.1f 秒)" % (n / 30.0), "errors", GR.script_errors(o, e)[:2], "timeout" if to else "", flush=True)
    return mp4


with ThreadPoolExecutor(a.jobs) as ex:
    mp4s = list(ex.map(one, a.clips.split(",")))
lst = os.path.join(out, "list.txt")
with open(lst, "w", encoding="utf-8") as f:
    for m in mp4s:
        if os.path.exists(m):
            f.write("file '%s'\n" % m.replace("\\", "/"))
subprocess.run([FF, "-y", "-loglevel", "error", "-f", "concat", "-safe", "0", "-i", lst, "-c", "copy", os.path.join(out, "all.mp4")])
print("输出", out)
