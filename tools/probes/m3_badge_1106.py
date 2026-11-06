# -*- coding: utf-8 -*-
"""docs/298 指挥台 Mon3tr 小牌（11-06）：实机截图，在 GCP（tools/gcp_render.py --job custom）上跑。
凯尔希当队长（环左下）/ 当队友（头像格右上角），桌面 1920×1080 与触屏手机横屏 1170×540。
93 秒让 Mon3tr 倒下（--m3downat），复活读秒缩到 6 秒（只在截图局，--bal），99 秒起身闪一下；90–101 秒每 0.5 秒存一张。
用法：python3 tools/probes/m3_badge_1106.py --out <目录> [--only pc_lead,...]
"""
import argparse, os, shutil, sys
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import godot_runner as gr

BASE = ["--balance", "--realtime", "--nodeath", "--seed=3", "--elite2", "--bot=master", "--bal=ui/console_idle=1",
        "--bal=kaltsit/m3_revive_secs=6", "--rtfrom=86", "--maxt=101", "--m3downat=93"]
PC = (["--resolution", "1920x1080"], ["--flashrec=90,330,1920"])
PH = (["--resolution", "1170x540"], ["--touch", "--flashrec=90,330,1170"])
LEAD = ["--op=kaltsit", "--squad=texas,exusiai"]
MATE = ["--op=mizuki", "--squad=kaltsit,texas"]
SCENES = {"pc_lead": (PC, LEAD), "pc_mate": (PC, MATE), "ph_lead": (PH, LEAD), "ph_mate": (PH, MATE)}

ap = argparse.ArgumentParser()
ap.add_argument("--out", required=True)
ap.add_argument("--only", default=",".join(SCENES))
a = ap.parse_args()
for name in a.only.split(","):
    (pre, post), extra = SCENES[name]
    d = os.path.join(ROOT, "build", "m3_badge", name)
    shutil.rmtree(d, ignore_errors=True)
    os.makedirs(d)
    args = [gr.find_godot(), "--path", os.path.join(ROOT, "game"), "--rendering-driver", "opengl3", "--audio-driver", "Dummy",
            "--fixed-fps", "30"] + pre + ["--"] + BASE + post + extra + ["--shotdir=" + d.replace(os.sep, "/")]
    o, e, to = gr.run_godot(args, 1500)
    open(os.path.join(d, "run.log"), "w", encoding="utf-8").write(o + "\n----\n" + e)
    fr = sorted(f for f in os.listdir(d) if f.startswith("fr_"))
    print(name, "frames", len(fr), "errors", gr.script_errors(o, e)[:3], "timeout" if to else "")
    dst = os.path.join(a.out, name)
    os.makedirs(dst, exist_ok=True)
    for f in fr[::15]:
        shutil.copy(os.path.join(d, f), os.path.join(dst, f))
    shutil.copy(os.path.join(d, "run.log"), os.path.join(dst, "run.log"))
