# -*- coding: utf-8 -*-
"""中期 Boss 在场照常刷怪录像（docs/177 §8 第 4 轮）：开窗口局（走 godot_runner：屏外、静音、全机并发上限），录 3:30 中期 Boss 战一段原速 mp4。
用法：python tools/midboss_spawn_rec.py [起始秒] [秒数] [名] [附加游戏参数…]    缺省 218 30 midboss_spawn
30 fps（--fixed-fps 30 + --realtime）；输出 build/midboss_spawn_rec/<名>.mp4 与帧目录。
"""
import os, shutil, subprocess, sys
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import godot_runner as gr

t0 = float(sys.argv[1]) if len(sys.argv) > 1 else 218.0
secs = float(sys.argv[2]) if len(sys.argv) > 2 else 30.0
name = sys.argv[3] if len(sys.argv) > 3 else "midboss_spawn"
extra = sys.argv[4:]
fps = 30
n = int(secs * fps)
base = os.path.join(ROOT, "build", "midboss_spawn_rec")
out = os.path.join(base, name)
shutil.rmtree(out, ignore_errors=True)
os.makedirs(out)
args = [gr.find_godot(), "--path", os.path.join(ROOT, "game"), "--audio-driver", "Dummy", "--fixed-fps", str(fps), "--",
        "--balance", "--realtime", "--rtfrom=%d" % max(0, t0 - 8), "--nodeath", "--seed=1", "--op=mizuki", "--bot=master",
        "--recframes=%s,%d" % (t0, n), "--shotdir=" + out.replace(os.sep, "/"), "--maxt=%d" % (t0 + secs + 30)] + extra
o, e, to = gr.run_godot(args, 1800)
open(os.path.join(out, "run.log"), "w", encoding="utf-8").write(o + "\n----\n" + e)
fr = [f for f in os.listdir(out) if f.startswith("rec_") and f.endswith(".png")]
print("frames:", len(fr), "errors:", gr.script_errors(o, e)[:5], "timeout" if to else "")
if fr:
    import imageio_ffmpeg
    mp4 = os.path.join(base, name + ".mp4")
    subprocess.run([imageio_ffmpeg.get_ffmpeg_exe(), "-y", "-loglevel", "error", "-framerate", str(fps), "-i", os.path.join(out, "rec_%05d.png"),
                    "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "23", mp4], check=True)
    print("mp4:", mp4)
