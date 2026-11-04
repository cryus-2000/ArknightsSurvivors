#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""fx/recipe 开 / 关对照（docs/245）：同种子同一局，配方开关各跑一遍（云端 xvfb + opengl3，非实时 --fixed-fps 60），
在 3:00 / 8:00 / 9:30 截图（full + nofriend 分层，供 late_game_diag_shots.py measure 同口径量测），同时收 TRACE 逐行比。

用法（仓库根目录，Linux 云端）：
    python tools/fx_recipe_compare.py run   --op logos --squad siege --seed 11 --jobs 4
    python tools/fx_recipe_compare.py trace --op siege --squad logos --seed 11 --maxt 300 --extra "--elite2 --sptest"
    python tools/fx_recipe_compare.py diff  （比较已有日志里的 TRACE）
截图目录沿用 late_game_diag_shots 的命名：build/late_diag/shots/<op>_rcp<0|1>_s<seed>_<layer>/
"""
import argparse, os, subprocess, sys
from concurrent.futures import ThreadPoolExecutor

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import godot_runner as GR
import late_game_diag_shots as LS

LOGS = os.path.join(ROOT, "build", "fx_recipe", "logs")


def job(args):
    tag, d, extra, res, maxt, shots = args
    os.makedirs(LOGS, exist_ok=True)
    if d:
        os.makedirs(d, exist_ok=True)
        for f in os.listdir(d):
            os.remove(os.path.join(d, f))
    a = ["xvfb-run", "-a", "-s", "-screen 0 %sx24" % res, GR.find_godot(), "--rendering-driver", "opengl3", "--path", os.path.join(ROOT, "game"),
         "--resolution", res, "--audio-driver", "Dummy", "--fixed-fps", "60", "--", "--balance", "--nodeath", "--trace=1", "--maxt=%d" % maxt] + extra
    if shots:
        a += ["--shots=" + ",".join(str(f) for f in shots), "--clutterlog", "--shotdir=" + d]
    p = subprocess.run(a, capture_output=True, text=True, timeout=14400)
    out = p.stdout + p.stderr
    open(os.path.join(LOGS, tag + ".log"), "w").write(out)
    errs = [l for l in out.splitlines() if "SCRIPT ERROR" in l or "Parse Error" in l]
    return tag, len([l for l in out.splitlines() if l.startswith("TRACE")]), errs[:3]


def traces(tag):
    p = os.path.join(LOGS, tag + ".log")
    return [l for l in open(p).read().splitlines() if l.startswith("TRACE") or l.startswith("BALANCE")] if os.path.exists(p) else []


def diff(a, b):
    ta, tb = traces(a), traces(b)
    n = 0
    for i, (x, y) in enumerate(zip(ta, tb)):
        if x != y:
            n += 1
            if n <= 3:
                print("  第 %d 行不同：\n   %s\n   %s" % (i + 1, x[:160], y[:160]))
    same = n == 0 and len(ta) == len(tb) and len(ta) > 0
    print("%s vs %s：%d / %d 行，%s" % (a, b, len(ta), len(tb), "逐行一致" if same else "有差异 %d 行" % n))
    return same


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd")
    ap.add_argument("--op", default="logos")
    ap.add_argument("--squad", default="siege")
    ap.add_argument("--seed", type=int, default=11)
    ap.add_argument("--jobs", type=int, default=4)
    ap.add_argument("--maxt", type=int, default=575)
    ap.add_argument("--layers", default="full,nofriend")
    ap.add_argument("--extra", default="")
    a = ap.parse_args()
    base = ["--seed=%d" % a.seed, "--op=" + a.op] + (["--squad=" + a.squad] if a.squad else []) + a.extra.split()
    jobs = []
    if a.cmd == "run":
        LS.TARGETS[:] = [180, 480, 570]
        for on in (0, 1):
            for ly in a.layers.split(","):
                tag = "%s_rcp%d_s%d_%s" % (a.op, on, a.seed, ly)
                ex = base + ["--bal=fx/recipe=%d" % on] + ([] if ly == "full" else ["--clutterdbg=" + ly])
                jobs.append((tag, os.path.join(LS.SHOT, tag), ex, "1280x720", a.maxt, LS.frames()))
    elif a.cmd == "trace":
        for on in (0, 1):
            tag = "%s_trace%d_s%d" % (a.op, on, a.seed)
            jobs.append((tag, "", base + ["--bal=fx/recipe=%d" % on], "640x360", a.maxt, []))
    if jobs:
        with ThreadPoolExecutor(a.jobs) as ex:
            for r in ex.map(job, jobs):
                print(r, flush=True)
    ok = True
    for f in sorted(os.listdir(LOGS)) if os.path.isdir(LOGS) else []:
        if "_rcp0_" in f and f.endswith("_full.log"):
            ok &= diff(f[:-4], f[:-4].replace("_rcp0_", "_rcp1_"))
        if "_trace0_" in f:
            ok &= diff(f[:-4], f[:-4].replace("_trace0_", "_trace1_"))
    sys.exit(0 if ok else 1)


main()
