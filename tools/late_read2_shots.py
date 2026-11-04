#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""后期可读性第二批（docs/247：V4 light_share / V9 ground_ring_edge / V10 crowd_env_dim）开 / 关对照截图、录像。
截图口径同 late_game_diag_shots.py（云端 xvfb + opengl3，1280×720，--fixed-fps 60 非实时，同种子）。

    python tools/late_read2_shots.py shoot            # 5 组配置 × 各自需要的分层，3:00 / 8:00 / 9:30
    python tools/late_read2_shots.py video --t0 480   # 8:00 起 20 秒，关 / 开各一局（--dt 1/30 = 每帧 1/30 局内秒，30 帧原速）
"""
import argparse, os, shutil, subprocess, sys
from concurrent.futures import ThreadPoolExecutor

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import godot_runner as GR
import late_game_diag_shots as S

ALL = ["--bal=render/light_share=1", "--bal=render/ground_ring_edge=1", "--bal=render/crowd_env_dim=1"]
CONFIGS = {   # tag → (额外参数, 分层, 时刻)
    "_OFF": ([], ["full", "nofriend", "noring"], [180, 480, 570]),
    "_ON": (ALL, ["full", "nofriend", "noring"], [180, 480, 570]),
    "_V4": ([ALL[0]], ["full", "nofriend"], [480]),
    "_V9": ([ALL[1]], ["full"], [480]),       # V9 只改光环层：它的 noring 与全关的 noring 是同一张图，量测时借用全关的
    "_V10": ([ALL[2]], ["full", "nofriend"], [480]),
}
OP, SQUAD, SEED = "logos", "texas,suzuran", 11


def _cmd(d, extra, maxt):
    return ["xvfb-run", "-a", "-s", "-screen 0 1280x720x24", GR.find_godot(), "--rendering-driver", "opengl3", "--path", os.path.join(ROOT, "game"),
            "--resolution", "1280x720", "--audio-driver", "Dummy", "--fixed-fps", "60", "--",
            "--balance", "--nodeath", "--seed=%d" % SEED, "--op=" + OP, "--squad=" + SQUAD, "--maxt=%d" % maxt, "--clutterlog", "--shotdir=" + d] + extra


def shoot_one(job):
    tag, layer = job
    extra, _, targets = CONFIGS[tag]
    d = os.path.join(S.SHOT, "%s%s_s%d_%s" % (OP, tag, SEED, layer))
    shutil.rmtree(d, ignore_errors=True)
    os.makedirs(d)
    fr = []
    for t in targets:
        f = int(round(t / S.SPF))
        fr += [f, f + 4]
    # full 层顺带 --trace=1：同一局的 TRACE 存成 trace.txt，各配置之间逐行比（docs/36 §3.2；截图、--clutterlog 各配置相同）
    args = _cmd(d, list(extra) + ["--shots=" + ",".join(str(f) for f in fr)] + (["--trace=1"] if layer == "full" else ["--clutterdbg=" + layer]), targets[-1] + 5)
    p = subprocess.run(args, capture_output=True, text=True, timeout=14400)
    out = (p.stdout + p.stderr).splitlines()
    if layer == "full":
        open(os.path.join(d, "trace.txt"), "w").write("\n".join(l for l in out if l.startswith("TRACE ")) + "\n")
    errs = [l for l in out if "SCRIPT ERROR" in l or "Parse Error" in l]
    return job, len(os.listdir(d)), errs[:3]


def cmd_shoot(a):
    tags = a.tags.split(",") if a.tags else list(CONFIGS)
    jobs = [(t, ly) for t in tags for ly in CONFIGS[t][1]]
    with ThreadPoolExecutor(a.jobs) as ex:
        for job, n, errs in ex.map(shoot_one, jobs):
            print(job, "files", n, errs, flush=True)


def video_one(job):
    tag, t0, dur = job
    d = os.path.join(S.SHOT, "video%s" % tag)
    shutil.rmtree(d, ignore_errors=True)
    os.makedirs(d)
    dt = 1.0 / 30.0
    f0 = int(round(t0 / dt))
    extra = (ALL if tag == "_ON" else []) + ["--dt=%.6f" % dt, "--shots=" + ",".join(str(f) for f in range(f0, f0 + int(dur * 30)))]
    args = _cmd(d, extra, int(t0 + dur + 3))
    args.remove("--clutterlog")
    p = subprocess.run(args, capture_output=True, text=True, timeout=14400)
    errs = [l for l in (p.stdout + p.stderr).splitlines() if "SCRIPT ERROR" in l or "Parse Error" in l]
    return job, len(os.listdir(d)), errs[:3]


def cmd_video(a):
    jobs = [("_OFF", a.t0, a.dur), ("_ON", a.t0, a.dur)]
    with ThreadPoolExecutor(2) as ex:
        for job, n, errs in ex.map(video_one, jobs):
            print(job, "files", n, errs, flush=True)


def main():
    ap = argparse.ArgumentParser()
    sp = ap.add_subparsers(dest="cmd", required=True)
    s = sp.add_parser("shoot")
    s.add_argument("--tags", default="")
    s.add_argument("--jobs", type=int, default=3)
    v = sp.add_parser("video")
    v.add_argument("--t0", type=float, default=480.0)
    v.add_argument("--dur", type=float, default=20.0)
    a = ap.parse_args()
    {"shoot": cmd_shoot, "video": cmd_video}[a.cmd](a)


if __name__ == "__main__":
    main()
