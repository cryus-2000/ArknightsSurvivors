#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""后期混战刺眼度（docs/274 §2.4，GCP 上跑，本机不开 Godot）：同种子同一局 8:00 起 secs 秒，跑两遍
A 正常（fx/px_plane=1）/ C 关 emit（fx/px_plane_emit=0），逐帧 A−C 亮度差 > 8 的像素数 = 发光核心辉光面积（同 docs/270 §1 的量法），
给每帧面积的中位 / p90 / 最大，另存辉光最大那帧和第 5 秒的 1 倍截图。

用法：python3 tools/pxplane_lateglow.py --op wisadel --out $MEDIA [--seed 11 --from 480 --secs 10]
"""
import argparse, glob, json, os, shutil, sys
from concurrent.futures import ThreadPoolExecutor

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import godot_runner as GR

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GAME = os.path.join(ROOT, "game")
BUILD = os.path.join(ROOT, "build", "lateglow")


def run(tag, op, seed, t0, secs, extra):
    fdir = os.path.join(BUILD, tag)
    shutil.rmtree(fdir, ignore_errors=True)
    os.makedirs(fdir)
    args = [GR.find_godot(), "--path", GAME, "--audio-driver", "Dummy", "--resolution", "1280x720", "--fixed-fps", "30", "--",
            "--balance", "--nodeath", "--seed=%d" % seed, "--op=" + op, "--bal=fx/px_plane=1", "--bal=growth/late_shape=1", "--realtime", "--rtfrom=%d" % t0,
            "--recframes=%d,%d" % (t0, secs * 30), "--maxt=%d" % (t0 + secs + 1), "--shotdir=" + fdir.replace(os.sep, "/")] + extra
    out, err, to = GR.run_godot(args, 5400)
    open(os.path.join(BUILD, tag + ".log"), "w", encoding="utf-8").write((out or "") + "\n" + (err or ""))
    return tag, len(glob.glob(os.path.join(fdir, "rec_*.png"))), GR.script_errors(out or "", err or "")[:3]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--op", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--seed", type=int, default=11)
    ap.add_argument("--from", dest="t0", type=int, default=480)
    ap.add_argument("--secs", type=int, default=10)
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    os.makedirs(BUILD, exist_ok=True)
    jobs = [("A", []), ("C", ["--bal=fx/px_plane_emit=0"])]
    with ThreadPoolExecutor(2) as ex:
        for r in ex.map(lambda j: run("%s_%s" % (a.op, j[0]), a.op, a.seed, a.t0, a.secs, j[1]), jobs):
            print("局", r, flush=True)
    fa = sorted(glob.glob(os.path.join(BUILD, a.op + "_A", "rec_*.png")))
    fc = sorted(glob.glob(os.path.join(BUILD, a.op + "_C", "rec_*.png")))
    n = min(len(fa), len(fc))
    areas = []
    for i in range(n):
        A = np.asarray(Image.open(fa[i]).convert("L"), dtype=np.int16)
        C = np.asarray(Image.open(fc[i]).convert("L"), dtype=np.int16)
        areas.append(int(((A - C) > 8).sum()))
    if not areas:
        print("没有帧")
        sys.exit(1)
    s = sorted(areas)
    res = {"op": a.op, "frames": n, "glow_median": s[len(s) // 2], "glow_p90": s[int(len(s) * 0.9)], "glow_max": s[-1],
           "glow_mean": round(sum(s) / len(s), 1)}
    k = int(np.argmax(areas))
    shutil.copy(fa[k], os.path.join(a.out, "%s_late8_glowmax.png" % a.op))
    shutil.copy(fa[min(n - 1, 150)], os.path.join(a.out, "%s_late8_t5.png" % a.op))
    res["glowmax_frame"] = k
    json.dump(res, open(os.path.join(a.out, "%s_lateglow.json" % a.op), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print("LATEGLOW", json.dumps(res, ensure_ascii=False), flush=True)


if __name__ == "__main__":
    main()
