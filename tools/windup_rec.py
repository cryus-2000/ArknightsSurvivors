# -*- coding: utf-8 -*-
"""普通怪蓄力改前 / 改后录像（docs/182）：开窗口局（走 godot_runner：屏外、静音、全机并发上限），同 seed 同时段各录一段原速 mp4。
用法：python tools/windup_rec.py <起始秒> <秒数> [名]    例：python tools/windup_rec.py 330 14 windup
改前 = --bal=enemy/windup_mult=1；改后 = 缺省。20 fps 原速；输出 build/windup_rec/<名>_before.mp4 / <名>_after.mp4。
"""
import os, shutil, subprocess, sys
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import godot_runner as gr

t0, secs = float(sys.argv[1]), float(sys.argv[2])
name = sys.argv[3] if len(sys.argv) > 3 else "windup"
fps = 20
n = int(secs * fps)
base = os.path.join(ROOT, "build", "windup_rec")
os.makedirs(base, exist_ok=True)
for tag, extra in (("before", ["--bal=enemy/windup_mult=1"]), ("after", [])):
    out = os.path.join(base, name + "_" + tag)
    shutil.rmtree(out, ignore_errors=True)
    os.makedirs(out)
    args = [gr.find_godot(), "--path", os.path.join(ROOT, "game"), "--audio-driver", "Dummy", "--fixed-fps", str(fps), "--",
            "--balance", "--realtime", "--rtfrom=%d" % max(0, t0 - 8), "--nodeath", "--seed=1", "--op=mizuki", "--bot=master",
            "--recframes=%s,%d" % (t0, n), "--shotdir=" + out.replace(os.sep, "/"), "--maxt=%d" % (t0 + secs + 30)] + extra
    o, e, to = gr.run_godot(args, 1500)
    open(os.path.join(out, "run.log"), "w", encoding="utf-8").write(o + "\n----\n" + e)
    fr = [f for f in os.listdir(out) if f.startswith("rec_") and f.endswith(".png")]
    print(tag, "frames:", len(fr), "errors:", gr.script_errors(o, e)[:5], "timeout" if to else "")
    if fr:
        import imageio_ffmpeg
        mp4 = os.path.join(base, name + "_" + tag + ".mp4")
        subprocess.run([imageio_ffmpeg.get_ffmpeg_exe(), "-y", "-loglevel", "error", "-framerate", str(fps), "-i", os.path.join(out, "rec_%05d.png"),
                        "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "23", mp4], check=True)
        print("mp4:", mp4)
