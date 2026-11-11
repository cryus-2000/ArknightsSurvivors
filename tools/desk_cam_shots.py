# -*- coding: utf-8 -*-
"""桌面战斗镜头对照（docs/335）：同种子同时刻，桌面缺省 126 与放大档、几种分辨率、手机横屏各截一张。
用法：python tools/desk_cam_shots.py [--t 150,480] [--only d126,d140]
输出 build/desk_cam/<tag>/shot_<帧>.png；本机开窗口（godot_runner 放屏幕外、静音），同时最多 2 个
注意：刷怪圈按可见范围算（spawner.gd 读 battle_zoom），不同缩放档同一时刻的怪群位置不完全相同"""
import argparse, os, shutil, sys
from concurrent.futures import ThreadPoolExecutor
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import godot_runner as GR
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
SPF = 0.0659   # 非实时平衡模式每渲染帧约 0.0659 局内秒（late_game_diag_shots.py 同口径）
CONFIGS = {    # tag → (分辨率, 额外参数)
    "d126": ("1920x1080", ["--camzoom=126"]),
    "d140": ("1920x1080", ["--camzoom=140"]),
    "d150": ("1920x1080", ["--camzoom=150"]),
    "d126_1440": ("2560x1440", ["--camzoom=126"]),
    "d126_768": ("1366x768", ["--camzoom=126"]),
    "d126_1610": ("1920x1200", ["--camzoom=126"]),
    "phone": ("1266x585", ["--touch"]),
}
ap = argparse.ArgumentParser()
ap.add_argument("--t", default="150,480"); ap.add_argument("--only", default="")
ap.add_argument("--seed", type=int, default=11)
a = ap.parse_args()
TS = [float(x) for x in a.t.split(",")]
FR = [int(round(t / SPF)) for t in TS]


def run(tag):
    res, extra = CONFIGS[tag]
    d = os.path.join(ROOT, "build", "desk_cam", tag); shutil.rmtree(d, ignore_errors=True); os.makedirs(d)
    args = [GR.find_godot(), "--path", os.path.join(ROOT, "game"), "--audio-driver", "Dummy", "--fixed-fps", "60", "--resolution", "1280x720", "--", "--winsize=" + res,
            "--quality=high", "--balance", "--nodeath", "--seed=%d" % a.seed, "--op=logos", "--squad=texas,suzuran",
            "--shots=" + ",".join(str(f) for f in FR), "--shotdir=" + d.replace(os.sep, "/"), "--maxt=%d" % (TS[-1] + 5)] + extra
    o, e, to = GR.run_godot(args, 5400)
    return tag, sorted(os.listdir(d)), GR.script_errors(o, e)[:3], to


tags = a.only.split(",") if a.only else list(CONFIGS)
with ThreadPoolExecutor(2) as ex:
    for tag, files, errs, to in ex.map(run, tags):
        print(tag, files, errs, "TIMEOUT" if to else "", flush=True)
