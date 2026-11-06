# -*- coding: utf-8 -*-
"""卡牌文字排版对照（11-06 用户「卡牌上的文字也重新排版一下大小」）：实机截选卡 / 招募 / 商店 / 事件面板，在 GCP 上跑。
--choiceshots：每个选择面板等卡片全翻面后存一张 shot_choice_<n>.png。
用法：python3 tools/probes/card_text_1106.py --out <目录> [--only pc,ph] [--tag 名]
"""
import argparse, os, shutil, sys
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import godot_runner as gr

BASE = ["--balance", "--nodeath", "--seed=3", "--op=mizuki", "--bot=master", "--choiceshots", "--maxt=240"]
SCENES = {
    "pc": (["--resolution", "1920x1080"], []),
    "ph": (["--resolution", "1170x540"], ["--touch"]),
}
ap = argparse.ArgumentParser()
ap.add_argument("--out", required=True)
ap.add_argument("--only", default=",".join(SCENES))
ap.add_argument("--tag", default="")
a = ap.parse_args()
for name in a.only.split(","):
    pre, post = SCENES[name]
    d = os.path.join(ROOT, "build", "card_text", name)
    shutil.rmtree(d, ignore_errors=True)
    os.makedirs(d)
    args = [gr.find_godot(), "--path", os.path.join(ROOT, "game"), "--rendering-driver", "opengl3", "--audio-driver", "Dummy",
            "--fixed-fps", "30"] + pre + ["--"] + BASE + post + ["--shotdir=" + d.replace(os.sep, "/")]
    o, e, to = gr.run_godot(args, 1500)
    open(os.path.join(d, "run.log"), "w", encoding="utf-8").write(o + "\n----\n" + e)
    shots = sorted(f for f in os.listdir(d) if f.startswith("shot_choice_"))
    print(name, "shots", len(shots), "errors", gr.script_errors(o, e)[:3], "timeout" if to else "")
    dst = os.path.join(a.out, name + a.tag)
    os.makedirs(dst, exist_ok=True)
    for f in shots + ["run.log"]:
        shutil.copy(os.path.join(d, f), os.path.join(dst, f))
