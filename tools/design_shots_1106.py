# -*- coding: utf-8 -*-
"""docs/283 / 284 的实机取证截图（11-06，只读游戏、不改代码）：在 GCP（tools/gcp_render.py --job custom）上跑。
三个场景，镜头不放大，整屏（--flashrec 的第三个参数是输出宽度，1280 = 整屏缩到 1280 宽），每场景存若干 fr_*.png：
  mag     8 分钟后期局，--bal 把磁铁掉率调高（不改代码）：看磁铁在满屏怪里是否找得到
  carmen  7:00 前在主控旁刷出圣徒卡门（--flashspawn），同屏后期怪群
  bishop  3:30 前在主控旁刷出主教
用法：python3 tools/design_shots_1106.py --out <目录> [--only mag,carmen,bishop]
"""
import argparse, os, shutil, sys
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import godot_runner as gr

SQUAD = "--squad=skadi,saria,texas,exusiai,eyjafjalla"
SCENES = {
    "mag": ["--rtfrom=470", "--dropmagnet=472", "--flashrec=474,120,1280", "--maxt=482"],
    "carmen": ["--rtfrom=400", "--flashspawn=carmen", "--flashrec=402,300,1280", "--maxt=415"],
    "bishop": ["--rtfrom=190", "--flashspawn=bishop", "--flashrec=192,300,1280", "--maxt=205"],
}

ap = argparse.ArgumentParser()
ap.add_argument("--out", required=True)
ap.add_argument("--only", default="mag,carmen,bishop")
a = ap.parse_args()
for name in a.only.split(","):
    d = os.path.join(ROOT, "build", "design_shots", name)
    shutil.rmtree(d, ignore_errors=True)
    os.makedirs(d)
    args = [gr.find_godot(), "--path", os.path.join(ROOT, "game"), "--audio-driver", "Dummy", "--fixed-fps", "30", "--",
            "--balance", "--realtime", "--nodeath", "--seed=3", "--op=mizuki", SQUAD, "--prog=6", "--bot=master",
            "--shotdir=" + d.replace(os.sep, "/")] + SCENES[name]
    o, e, to = gr.run_godot(args, 1500)
    open(os.path.join(d, "run.log"), "w", encoding="utf-8").write(o + "\n----\n" + e)
    fr = sorted(f for f in os.listdir(d) if f.startswith("fr_"))
    print(name, "frames", len(fr), "errors", gr.script_errors(o, e)[:3], "timeout" if to else "")
    dst = os.path.join(a.out, name)
    os.makedirs(dst, exist_ok=True)
    for f in fr[::10]:   # 每 10 帧留一张（三分之一秒），够挑 2–3 张
        shutil.copy(os.path.join(d, f), os.path.join(dst, f))
    for f in ("run.log", "flashrec.csv"):
        if os.path.exists(os.path.join(d, f)):
            shutil.copy(os.path.join(d, f), os.path.join(dst, f))
