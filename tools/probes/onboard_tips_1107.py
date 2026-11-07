# -*- coding: utf-8 -*-
"""新手引导 11-07 改版（Toy 预览实测）实机截图：演示局结束框 + 正式局小字提示。在 GCP（tools/gcp_render.py --job custom）上跑。
结束框：--onboarddemo=drill_end（模态，不自动关）；小字提示：--onboarddemo=toast:<id>（常驻）。
桌面 1920×1080 / 触屏手机横屏 1170×540。
用法：python3 tools/probes/onboard_tips_1107.py --out <目录> [--only pc_end,ph_toast_merchant,...]
"""
import argparse, os, shutil, sys
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import godot_runner as gr

BASE = ["--balance", "--realtime", "--seed=1", "--op=mizuki", "--nodeath"]
PC = ["--resolution", "1920x1080"], [], 1920
PH = ["--resolution", "1170x540"], ["--touch"], 1170
CARDS = {"end": (["--onboarddemo=drill_end"], True), "toast_merchant": (["--onboarddemo=toast:merchant"], False),
         "toast_boss": (["--onboarddemo=toast:boss"], False), "toast_duck": (["--onboarddemo=toast:duck"], False)}
SCENES = {}
for dn, dev in (("pc", PC), ("ph", PH)):
    for cn, (ca, modal) in CARDS.items():
        SCENES[dn + "_" + cn] = (dev, ca, modal)

ap = argparse.ArgumentParser()
ap.add_argument("--out", required=True)
ap.add_argument("--only", default=",".join(SCENES))
a = ap.parse_args()
for name in a.only.split(","):
    (pre, post, w), ca, modal = SCENES[name]
    d = os.path.join(ROOT, "build", "onboard_tips", name)
    shutil.rmtree(d, ignore_errors=True)
    os.makedirs(d)
    rec = ["--flashrec=0,24,%d" % w] if modal else ["--flashrec=3,1,%d" % w, "--maxt=4"]
    args = [gr.find_godot(), "--path", os.path.join(ROOT, "game"), "--rendering-driver", "opengl3", "--audio-driver", "Dummy",
            "--fixed-fps", "30"] + pre + ["--"] + BASE + post + ca + rec + ["--shotdir=" + d.replace(os.sep, "/")]
    o, e, to = gr.run_godot(args, 90)
    fr = sorted(f for f in os.listdir(d) if f.startswith("fr_"))
    print(name, "frames", len(fr), "errors", gr.script_errors(o, e)[:3], "timeout" if to else "")
    os.makedirs(a.out, exist_ok=True)
    if fr:
        shutil.copy(os.path.join(d, fr[-1]), os.path.join(a.out, "%s.png" % name))
    open(os.path.join(a.out, "%s.log" % name), "w", encoding="utf-8").write(o[-4000:] + "\n----\n" + e[-4000:])
