# -*- coding: utf-8 -*-
"""docs/290 指挥台技能细格示意（11-06）：实机截图，在 GCP（tools/gcp_render.py --job custom）上跑。
同一局（seed 3、水月队长 + 德克萨斯 / 能天使 / 塞雷娅，队友直接精二、队长不推进 → 队长 S2 / S3 没解锁），
90 秒起每 0.5 秒存一张，挑技能状态混着的那帧。场景：
  pc_l1 / pc_l2      桌面 1920×1080，ui/console_skills = 1（环下）/ 2（等级旁）
  pc_peek            桌面，布局一 + ui/console_peek = 1，编队卡强制展开（--consolepeek）
  ph_l1 / ph_l2 / ph_peek   同上，触屏手机横屏 1170×540（--touch）
整台闲时变淡（ui/console_idle）拍图时关掉，方便看清；冲刺格充能沿轮廓走（ui/console_dash_trace = 1）一起开。
用法：python3 tools/probes/hud_skill_cd_1106.py --out <目录> [--only pc_l1,...]
"""
import argparse, os, shutil, sys
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import godot_runner as gr

BASE = ["--balance", "--realtime", "--nodeath", "--seed=3", "--op=mizuki", "--slot4", "--squad=texas,exusiai,saria", "--elite2",
        "--bot=master", "--bal=ui/console_idle=1", "--bal=ui/console_dash_trace=1", "--rtfrom=86", "--maxt=101"]
PC = (["--resolution", "1920x1080"], ["--flashrec=90,330,1920"])
PH = (["--resolution", "1170x540"], ["--touch", "--flashrec=90,330,1170"])
SCENES = {
    "pc_l1": (PC, ["--bal=ui/console_skills=1"]),
    "pc_l2": (PC, ["--bal=ui/console_skills=2"]),
    "pc_peek": (PC, ["--bal=ui/console_skills=1", "--bal=ui/console_peek=1", "--consolepeek"]),
    "ph_l1": (PH, ["--bal=ui/console_skills=1"]),
    "ph_l2": (PH, ["--bal=ui/console_skills=2"]),
    "ph_peek": (PH, ["--bal=ui/console_skills=1", "--bal=ui/console_peek=1", "--consolepeek"]),
}

ap = argparse.ArgumentParser()
ap.add_argument("--out", required=True)
ap.add_argument("--only", default=",".join(SCENES))
a = ap.parse_args()
for name in a.only.split(","):
    (pre, post), extra = SCENES[name]
    d = os.path.join(ROOT, "build", "hud_skill_cd", name)
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
