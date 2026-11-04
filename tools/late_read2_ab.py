#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""后期可读性第二批（docs/247）同 seed TRACE 对照：light_share / ground_ring_edge / crowd_env_dim 全关、全开、各单开，同一局逐行比 TRACE，
（由 docs/244 的 late_read_ab.py 改来）
可选再和基准提交（另一份检出，--base 指目录）的「关」逐行比。画面代码只在有窗口时跑，所以缺省用 xvfb + opengl3、
--fixed-fps 60 非实时（同 late_game_diag_shots.py）；--headless 另跑一遍无头。

用法（仓库根目录，Linux 云端，先 source tools/cloud/env.sh）：
    python tools/late_read2_ab.py                      # 3 个用例 × 关 / 全开 / 三个单开，带窗口
"""
import argparse, os, subprocess, sys
from concurrent.futures import ThreadPoolExecutor

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import godot_runner as GR

CASES = [
    ("复现局 维什戴尔+铃兰+逻各斯 s7", ["--seed=7", "--op=wisadel", "--squad=suzuran,logos", "--bot=expert", "--maxt=240"]),
    ("召唤专项 凯尔希+水月+塞雷娅 地雷组+轰隆隆 s11", ["--seed=11", "--op=kaltsit", "--squad=mizuki,saria", "--relics=210,211", "--nodeath", "--maxt=300"]),
    ("能天使 s11 不死 到后期", ["--seed=11", "--op=exusiai", "--nodeath", "--maxt=600"]),
]
V4, V9, V10 = "--bal=render/light_share=1", "--bal=render/ground_ring_edge=1", "--bal=render/crowd_env_dim=1"
CONFIGS = [("关", []), ("全开", [V4, V9, V10]), ("V4", [V4]), ("V9", [V9]), ("V10", [V10])]


def run(job):
    root, name, cfg, args, headless = job
    if headless:
        cmd = [GR.find_godot(), "--headless", "--path", os.path.join(root, "game"), "--"]
    else:
        cmd = ["xvfb-run", "-a", "-s", "-screen 0 1280x720x24", GR.find_godot(), "--rendering-driver", "opengl3", "--path", os.path.join(root, "game"),
               "--resolution", "1280x720", "--audio-driver", "Dummy", "--fixed-fps", "60", "--"]
    cmd += ["--balance", "--trace=1"] + args + cfg
    p = subprocess.run(cmd, capture_output=True, text=True, timeout=7200)
    out = p.stdout + p.stderr
    tr = [l for l in out.splitlines() if l.startswith("TRACE ")]
    errs = [l for l in out.splitlines() if "SCRIPT ERROR" in l or "Parse Error" in l]
    return job, tr, errs


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--headless", action="store_true")
    ap.add_argument("--base", default="", help="基准提交的检出目录（只跑「关」）")
    ap.add_argument("--jobs", type=int, default=3)
    ap.add_argument("--cases", default="")
    a = ap.parse_args()
    cases = [c for i, c in enumerate(CASES) if not a.cases or str(i) in a.cases.split(",")]
    jobs = [(ROOT, n, c, args, a.headless) for n, args in cases for _, c in CONFIGS]
    if a.base:
        jobs += [(a.base, n, [], args, a.headless) for n, args in cases]
    res = {}
    with ThreadPoolExecutor(a.jobs) as ex:
        for job, tr, errs in ex.map(run, jobs):
            root, n, cfg, _, _ = job
            key = (n, "基准" if root != ROOT else next(k for k, c in CONFIGS if c == cfg))
            res[key] = (tr, errs)
            print("%s / %s：TRACE %d 行，脚本错误 %d" % (key[0], key[1], len(tr), len(errs)), flush=True)
            for e in errs[:3]:
                print("   ", e)
    ok = True
    for n, _ in cases:
        ref = res[(n, "关")][0]
        for k in [k for k, _ in CONFIGS[1:]] + (["基准"] if a.base else []):
            tr = res[(n, k)][0]
            same = tr == ref and len(ref) > 0
            first = next((i for i, (x, y) in enumerate(zip(ref, tr)) if x != y), None)
            if not same:
                ok = False
            print("%s：%s vs 关 → %s" % (n, k, "逐行相同（%d 行）" % len(ref) if same else "不同：行数 %d / %d，首个不同行 %s" % (len(ref), len(tr), first)))
        if any(res[(n, k)][1] for k in [c for c, _ in CONFIGS] + (["基准"] if a.base else [])):
            ok = False
    print("结论：", "全部逐行相同、无脚本错误" if ok else "有不同或报错")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
