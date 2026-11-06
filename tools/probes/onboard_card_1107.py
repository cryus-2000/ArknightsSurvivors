# -*- coding: utf-8 -*-
"""docs/300 开局指南卡按属性面板画（11-07）：实机截图，在 GCP（tools/gcp_render.py --job custom）上跑。
卡片：--onboarddemo=<id>（进局即出、常驻）；问题框：--onboard=ask（2.4 秒后自动选，截第 20 帧，此前已滑入）。
桌面 1920×1080 / 触屏手机横屏 1170×540。新旧对照：同一提交跑一遍，再把 onboard.gd 换成 --old-ref 的版本跑一遍。
用法：python3 tools/probes/onboard_card_1107.py --out <目录> [--only ...] [--tag new]
"""
import argparse, os, shutil, sys
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import godot_runner as gr

BASE = ["--balance", "--realtime", "--seed=1", "--op=mizuki", "--nodeath"]
PC = ["--resolution", "1920x1080"], [], 1920
PH = ["--resolution", "1170x540"], ["--touch"], 1170
CARDS = {"move": ["--onboarddemo=move"], "lamp": ["--onboarddemo=lamp"], "command": ["--onboarddemo=command"], "ask": ["--onboard=ask"]}
SCENES = {}
for dn, dev in (("pc", PC), ("ph", PH)):
    for cn, ca in CARDS.items():
        SCENES[dn + "_" + cn] = (dev, ca, cn == "ask")

ap = argparse.ArgumentParser()
ap.add_argument("--out", required=True)
ap.add_argument("--only", default=",".join(SCENES))
ap.add_argument("--tag", default="new")
a = ap.parse_args()
for name in a.only.split(","):
    (pre, post, w), ca, ask = SCENES[name]
    d = os.path.join(ROOT, "build", "onboard_card", a.tag, name)
    shutil.rmtree(d, ignore_errors=True)
    os.makedirs(d)
    rec = ["--flashrec=0,24,%d" % w] if ask else ["--flashrec=3,1,%d" % w, "--maxt=4"]
    args = [gr.find_godot(), "--path", os.path.join(ROOT, "game"), "--rendering-driver", "opengl3", "--audio-driver", "Dummy",
            "--fixed-fps", "30"] + pre + ["--"] + BASE + post + ca + rec + ["--shotdir=" + d.replace(os.sep, "/")]
    o, e, to = gr.run_godot(args, 90)
    fr = sorted(f for f in os.listdir(d) if f.startswith("fr_"))
    print(a.tag, name, "frames", len(fr), "errors", gr.script_errors(o, e)[:3], "timeout" if to else "")
    os.makedirs(a.out, exist_ok=True)
    if fr:
        shutil.copy(os.path.join(d, fr[-1]), os.path.join(a.out, "%s_%s.png" % (name, a.tag)))
    open(os.path.join(a.out, "%s_%s.log" % (name, a.tag)), "w", encoding="utf-8").write(o[-4000:] + "\n----\n" + e[-4000:])
