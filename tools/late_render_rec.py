# -*- coding: utf-8 -*-
"""后期渲染层三件（docs/226）改前 / 改后对照录像：seed 13 A 组（德克萨斯 + 能天使 + 拉普兰德），原速 30 帧。
改前 = --bal render/foe_top=0 render/lead_sil=0 fx/team_pfx_cap=0（同一构建关掉三件），改后 = 缺省。
电脑 1920×1080 与手机横屏 --touch 1170×540 各录一组，每组左改前右改后拼一屏，电脑段在前、手机段在后接成一个 mp4。
用法：python tools/late_render_rec.py [--from 596 --secs 16] [--crf 30] [--out 路径]"""
import argparse, os, shutil, subprocess, sys
from concurrent.futures import ThreadPoolExecutor
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import godot_runner as GR
import imageio_ffmpeg
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
FF = imageio_ffmpeg.get_ffmpeg_exe()
ap = argparse.ArgumentParser()
ap.add_argument("--from", dest="t0", type=float, default=596.0); ap.add_argument("--secs", type=float, default=16.0)
ap.add_argument("--seed", type=int, default=13); ap.add_argument("--crf", type=int, default=30)
ap.add_argument("--out", default=os.path.join(ROOT, "build", "late_render", "late_render.mp4"))
a = ap.parse_args()
out = os.path.join(ROOT, "build", "late_render", "rec"); os.makedirs(out, exist_ok=True)
OFF = ["--bal=render/foe_top=0", "--bal=render/lead_sil=0", "--bal=fx/team_pfx_cap=0"]
JOBS = [(dev, on) for dev in ("pc", "touch") for on in (0, 1)]


def one(job):
    dev, on = job
    W, H = (1920, 1080) if dev == "pc" else (1170, 540)
    d = os.path.join(out, "%s_%d" % (dev, on)); shutil.rmtree(d, ignore_errors=True); os.makedirs(d)
    args = [GR.find_godot(), "--path", os.path.join(ROOT, "game"), "--audio-driver", "Dummy", "--fixed-fps", "30", "--resolution", "%dx%d" % (W, H), "--",
            "--balance", "--nodeath", "--seed=%d" % a.seed, "--bot=expert", "--op=texas", "--squad=exusiai,lappland", "--relics=1",
            "--realtime", "--rtfrom=%g" % (a.t0 - 3), "--recframes=%g,%d" % (a.t0, int(a.secs * 30)), "--recchoice",
            "--shotdir=" + d.replace(os.sep, "/"), "--maxt=%d" % (a.t0 + a.secs + 3)] + ([] if on else OFF) + (["--touch"] if dev == "touch" else [])
    o, e, to = GR.run_godot(args, 3000)
    return job, GR.script_errors(o, e)[:3], to


with ThreadPoolExecutor(4) as ex:
    for job, errs, to in ex.map(one, JOBS):
        if errs or to:
            print("WARN", job, errs, "timeout" if to else "")
parts = []
for dev in ("pc", "touch"):
    p = os.path.join(out, dev + ".mp4")
    # 每边 960 宽：电脑 960×540，手机 1170×540 → 960×443 再补黑边到 540 高
    fl = "[0:v]scale=960:-2,pad=960:540:(ow-iw)/2:(oh-ih)/2[l];[1:v]scale=960:-2,pad=960:540:(ow-iw)/2:(oh-ih)/2[r];[l][r]hstack=inputs=2[v]"
    subprocess.run([FF, "-y", "-loglevel", "error", "-framerate", "30", "-i", os.path.join(out, dev + "_0", "rec_%05d.png"),
                    "-framerate", "30", "-i", os.path.join(out, dev + "_1", "rec_%05d.png"), "-filter_complex", fl, "-map", "[v]",
                    "-c:v", "libx264", "-crf", str(a.crf), "-preset", "slow", "-pix_fmt", "yuv420p", p], check=True)
    parts.append(p)
lst = os.path.join(out, "list.txt")
open(lst, "w").write("".join("file '%s'\n" % p.replace(os.sep, "/") for p in parts))
os.makedirs(os.path.dirname(a.out), exist_ok=True)
subprocess.run([FF, "-y", "-loglevel", "error", "-f", "concat", "-safe", "0", "-i", lst, "-c", "copy", a.out], check=True)
print("OUT", a.out, "%.1f MiB" % (os.path.getsize(a.out) / 1048576.0))
