# -*- coding: utf-8 -*-
"""圣聆初雪积雪撞色对照（docs/403 §6.0）：同种子开一局，按局内时刻截图（开窗口、放副屏 / 屏幕外、静音）。
用法：python tools/sbell2_snow_shots.py --tag deep [--game <game 目录>] [--t 25,40,60] [--extra "--theme=sami"]
输出 build/sbell2_snow/<tag>/shot_<帧>.png；本机同时最多 2 个 Godot（godot_runner 排队）"""
import argparse, os, shutil, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import godot_runner as GR
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
SPF = 0.0659   # 非实时平衡模式每渲染帧约 0.0659 局内秒（desk_cam_shots.py 同口径）

ap = argparse.ArgumentParser()
ap.add_argument("--tag", required=True)
ap.add_argument("--game", default=os.path.join(ROOT, "game"))
ap.add_argument("--t", default="25,40,60")
ap.add_argument("--seed", type=int, default=3)
ap.add_argument("--squad", default="")
ap.add_argument("--extra", default="")
a = ap.parse_args()
TS = [float(x) for x in a.t.split(",")]
FR = [int(round(t / SPF)) for t in TS]
d = os.path.join(ROOT, "build", "sbell2_snow", a.tag)
shutil.rmtree(d, ignore_errors=True)
os.makedirs(d)
GR.ensure_imported(a.game)
args = [GR.find_godot(), "--path", a.game, "--audio-driver", "Dummy", "--fixed-fps", "60", "--resolution", "1280x720", "--", "--winsize=1920x1080",
        "--quality=high", "--balance", "--nodeath", "--seed=%d" % a.seed, "--op=sbell2",
        "--shots=" + ",".join(str(f) for f in FR), "--shotdir=" + d.replace(os.sep, "/"), "--maxt=%d" % (TS[-1] + 3)]
if a.squad:
    args.append("--squad=" + a.squad)
args += a.extra.split()
o, e, to = GR.run_godot(args, 1800)
open(os.path.join(d, "run.log"), "w", encoding="utf-8").write(o + "\n" + e)
print(sorted(os.listdir(d)), GR.script_errors(o, e)[:5], "TIMEOUT" if to else "")
