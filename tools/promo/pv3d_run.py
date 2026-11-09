# -*- coding: utf-8 -*-
"""跑 pv3d.gd 出 3D 开头（本机 1 个 Godot，Forward+），帧编成 mp4 后删帧。
  python tools/promo/pv3d_run.py <卡面目录> <输出.mp4>"""
import glob, os, shutil, subprocess, sys
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import godot_runner as GR
import imageio_ffmpeg

cards, out = sys.argv[1], sys.argv[2]
fd = out[:-4] + "_frames"
shutil.rmtree(fd, ignore_errors=True)
os.makedirs(fd)
args = [GR.find_godot(), "--path", os.path.join(ROOT, "game"), "--audio-driver", "Dummy", "--fixed-fps", "60", "--resolution", "1920x1080",
        "-s", os.path.join(HERE, "pv3d.gd").replace(os.sep, "/"), "--",
        "--pv3d_cards=" + cards.replace(os.sep, "/"), "--pv3d_out=" + fd.replace(os.sep, "/")]
o, e, to = GR.run_godot(args, 900)
print("\n".join(l for l in (o + e).splitlines() if "PV3D" in l or "ERROR" in l or "SCRIPT" in l)[:3000])
n = len(glob.glob(fd + "/f*.png"))
print("frames", n)
if n:
    subprocess.run([imageio_ffmpeg.get_ffmpeg_exe(), "-v", "error", "-y", "-framerate", "60", "-start_number", "0", "-i", fd + "/f%08d.png", "-c:v", "libx264", "-crf", "14",
                    "-preset", "slow", "-pix_fmt", "yuv420p", out], check=True)
    shutil.rmtree(fd)
    print(out)
