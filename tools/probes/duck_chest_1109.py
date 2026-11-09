# -*- coding: utf-8 -*-
"""鸭爵屏外 + 精英宝箱截图（11-09）：桌面 1280×720 / 手机横屏 844×390@2 / 956×440@2（含灵动岛 + 胶囊安全区）。
界面大小按网页缺省 110%（--uisize=110）。在 GCP（tools/gcp_render.py --job custom）上跑。
用法：python3 tools/probes/duck_chest_1109.py --out <目录> [--tag before|after]
"""
import argparse, os, shutil, sys
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import godot_runner as gr

DEV = {
    "pc": (["--resolution", "1280x720"], []),
    "ph844": (["--resolution", "1688x780"], ["--touch"]),
    "ph956": (["--resolution", "1912x880"], ["--touch", "--ins=76,56,76,27"]),
}
ap = argparse.ArgumentParser()
ap.add_argument("--out", required=True)
ap.add_argument("--tag", default="")
a = ap.parse_args()
os.makedirs(a.out, exist_ok=True)
for dn, (pre, post) in DEV.items():
    od = "duck_chest/" + dn
    d = os.path.join(ROOT, "build", "duck_chest", dn)
    shutil.rmtree(d, ignore_errors=True)
    args = [gr.find_godot(), "--path", os.path.join(ROOT, "game"), "--rendering-driver", "opengl3", "--audio-driver", "Dummy"] + pre + \
        ["res://tests/duck_chest_shots.tscn", "--", "--uisize=110", "--shots-out=" + od, "--squad=texas,exusiai"] + post
    o, e, to = gr.run_godot(args, 240)
    print(dn, [l for l in o.splitlines() if l.startswith("DUCK CHEST SHOT")], gr.script_errors(o, e)[:3], "timeout" if to else "")
    if os.path.isdir(d):
        for f in sorted(os.listdir(d)):
            shutil.copy(os.path.join(d, f), os.path.join(a.out, "%s%s_%s" % (a.tag + "_" if a.tag else "", dn, f)))
    open(os.path.join(a.out, "%s%s.log" % (a.tag + "_" if a.tag else "", dn)), "w", encoding="utf-8").write(o[-4000:] + "\n----\n" + e[-4000:])
