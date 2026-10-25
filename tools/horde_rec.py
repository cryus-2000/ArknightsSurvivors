# -*- coding: utf-8 -*-
"""大群收拢录像（docs/150）：开一个窗口局（走 godot_runner：屏外、静音、全机并发上限），快进到大群前几秒，逐帧存图，拼 1/3 速 gif。
用法：python tools/horde_rec.py <起始秒> <帧数> <输出名> [附加游戏参数…]
  例：python tools/horde_rec.py 296 260 hunt500        # 5:00 围猎型那波
      python tools/horde_rec.py 221 260 horde345       # 3:45 普通分股那波
录像 20 fps（--fixed-fps 20），gif 按 1/3 速（每帧 150 毫秒）、缩到 640 宽；输出 build/horde_rec/<输出名>.gif 与帧目录。
"""
import os, shutil, sys
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import godot_runner as gr

t0, n, name = float(sys.argv[1]), int(sys.argv[2]), sys.argv[3]
extra = sys.argv[4:]
out = os.path.join(ROOT, "build", "horde_rec", name)
shutil.rmtree(out, ignore_errors=True)
os.makedirs(out)
args = [gr.find_godot(), "--path", os.path.join(ROOT, "game"), "--audio-driver", "Dummy", "--fixed-fps", "20", "--",
        "--balance", "--realtime", "--rtfrom=%d" % max(0, t0 - 8), "--nodeath", "--seed=1", "--op=mizuki", "--bot=master",
        "--recframes=%s,%d" % (t0, n), "--shotdir=" + out.replace(os.sep, "/"), "--maxt=%d" % (t0 + n / 20 + 30)] + extra
o, e, to = gr.run_godot(args, 1200)
open(os.path.join(out, "run.log"), "w", encoding="utf-8").write(o + "\n----\n" + e)
fr = sorted(f for f in os.listdir(out) if f.startswith("rec_") and f.endswith(".png"))
print("frames:", len(fr), "errors:", gr.script_errors(o, e)[:5], "timeout" if to else "")
if fr:
    from PIL import Image
    ims = []
    for f in fr:
        im = Image.open(os.path.join(out, f)).convert("RGB")
        ims.append(im.resize((640, int(640 * im.height / im.width))).quantize(96))
    ims[0].save(os.path.join(ROOT, "build", "horde_rec", name + ".gif"), save_all=True, append_images=ims[1:], duration=150, loop=0)
    print("gif:", os.path.join(ROOT, "build", "horde_rec", name + ".gif"))
