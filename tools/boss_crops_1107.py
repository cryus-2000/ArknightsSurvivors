# -*- coding: utf-8 -*-
"""Boss 美术取证 v2（docs/289，11-07）：只带队长（水月，afk 机器人不出手）在主控旁刷出 Boss，录 18 秒整屏，
按 flashrec.csv 里 Boss 的屏幕位置裁 512×384 的块（不放大），每 4 帧留一张；Boss 预警（warns > 0）首次出现前后 45 帧全留。
GCP：python tools/gcp_render.py --branch <分支> --job custom --cmd 'python3 tools/boss_crops_1107.py --out $MEDIA [--only path]'
"""
import argparse, csv, os, shutil, sys
from PIL import Image
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import godot_runner as gr

BOSSES = ["path", "iberia", "carmen", "bishop", "archon", "immortal", "paranoia", "paranoia2", "knight_boss", "izumik", "ishar"]
ap = argparse.ArgumentParser()
ap.add_argument("--out", required=True)
ap.add_argument("--only", default=",".join(BOSSES))
a = ap.parse_args()
for name in a.only.split(","):
    d = os.path.join(ROOT, "build", "boss_crops", name)
    shutil.rmtree(d, ignore_errors=True)
    os.makedirs(d)
    args = [gr.find_godot(), "--path", os.path.join(ROOT, "game"), "--audio-driver", "Dummy", "--fixed-fps", "30", "--",
            "--balance", "--realtime", "--nodeath", "--seed=5", "--op=mizuki", "--prog=3", "--bot=afk",
            "--shotdir=" + d.replace(os.sep, "/"), "--rtfrom=0", "--flashspawn=" + name, "--flashrec=3,540,1280", "--maxt=24"]
    o, e, to = gr.run_godot(args, 1200)
    open(os.path.join(d, "run.log"), "w", encoding="utf-8").write(o + "\n----\n" + e)
    rows = list(csv.DictReader(open(os.path.join(d, "flashrec.csv"), encoding="utf-8"))) if os.path.exists(os.path.join(d, "flashrec.csv")) else []
    first_warn = next((int(r["i"]) for r in rows if int(r["warns"]) > 0), -999)
    dst = os.path.join(a.out, name)
    os.makedirs(dst, exist_ok=True)
    n = 0
    for r in rows:
        i = int(r["i"])
        if not (i % 4 == 0 or abs(i - first_warn) <= 45):
            continue
        f = os.path.join(d, "fr_%05d.png" % i)
        if not os.path.exists(f):
            continue
        im = Image.open(f).convert("RGB")
        cx, cy = float(r["bx"]) * im.width, float(r["by"]) * im.height
        x0 = int(min(max(cx - 256, 0), im.width - 512)); y0 = int(min(max(cy - 192, 0), im.height - 384))
        im.crop((x0, y0, x0 + 512, y0 + 384)).save(os.path.join(dst, "c_%05d.png" % i))
        n += 1
    shutil.copy(os.path.join(d, "flashrec.csv"), dst) if rows else None
    print(name, "frames", len(rows), "crops", n, "first_warn", first_warn, "errors", gr.script_errors(o, e)[:3], "timeout" if to else "")
