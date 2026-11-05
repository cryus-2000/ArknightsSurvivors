# -*- coding: utf-8 -*-
"""Boss 美术盘点取证（docs/289，11-07）：每只 Boss 在主控旁刷出（--flashspawn），录一段整屏（1280 宽）帧，每 10 帧留一张。
GCP 上用：python tools/gcp_render.py --branch <分支> --job custom --cmd 'python3 tools/boss_shots_1107.py --out $MEDIA [--only path,carmen]'
"""
import argparse, os, shutil, sys
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import godot_runner as gr

SQUAD = "--squad=skadi,saria,texas,exusiai,eyjafjalla"
BOSSES = ["path", "iberia", "carmen", "bishop", "archon", "immortal", "paranoia", "paranoia2", "knight_boss", "izumik", "ishar"]
ap = argparse.ArgumentParser()
ap.add_argument("--out", required=True)
ap.add_argument("--only", default=",".join(BOSSES))
a = ap.parse_args()
for name in a.only.split(","):
    d = os.path.join(ROOT, "build", "boss_shots", name)
    shutil.rmtree(d, ignore_errors=True)
    os.makedirs(d)
    args = [gr.find_godot(), "--path", os.path.join(ROOT, "game"), "--audio-driver", "Dummy", "--fixed-fps", "30", "--",
            "--balance", "--realtime", "--nodeath", "--seed=5", "--op=mizuki", SQUAD, "--prog=6", "--bot=master",
            "--shotdir=" + d.replace(os.sep, "/"), "--rtfrom=0", "--flashspawn=" + name, "--flashrec=3,300,1280", "--maxt=16"]
    o, e, to = gr.run_godot(args, 900)
    open(os.path.join(d, "run.log"), "w", encoding="utf-8").write(o + "\n----\n" + e)
    fr = sorted(f for f in os.listdir(d) if f.startswith("fr_"))
    print(name, "frames", len(fr), "errors", gr.script_errors(o, e)[:3], "timeout" if to else "")
    dst = os.path.join(a.out, name)
    os.makedirs(dst, exist_ok=True)
    for f in fr[::10]:
        shutil.copy(os.path.join(d, f), os.path.join(dst, f))
    if os.path.exists(os.path.join(d, "flashrec.csv")):
        shutil.copy(os.path.join(d, "flashrec.csv"), os.path.join(dst, "flashrec.csv"))
