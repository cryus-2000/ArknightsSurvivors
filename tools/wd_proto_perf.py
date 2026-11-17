# -*- coding: utf-8 -*-
"""维什戴尔终结技原型帧时对照（docs/353）：同种子同局，ult/wd_proto 各档 × 画质档各跑一局（桌面窗口放屏幕外、静音），
--perfdump 逐帧记录；取每次终结技充满后 2 秒窗口里的 渲染 CPU / GPU / 帧时 均值与 p95 / 最大，和 wd_proto=0 比。
用法：python tools/wd_proto_perf.py [--modes 0,1,2,3] [--q high,low] [--jobs 2]"""
import argparse, csv, os, sys
from concurrent.futures import ThreadPoolExecutor
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import godot_runner as GR
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
ap = argparse.ArgumentParser()
ap.add_argument("--modes", default="0,1,2,3"); ap.add_argument("--q", default="high,low"); ap.add_argument("--jobs", type=int, default=2)
ap.add_argument("--at", type=float, default=300.0)
a = ap.parse_args()
OUT = os.path.join(ROOT, "build", "wd_proto_perf"); os.makedirs(OUT, exist_ok=True)
FILLS = [a.at + 1.5 + 5.5 * i for i in range(3)]


def one(job):
    m, q = job
    f = os.path.join(OUT, "m%s_%s.csv" % (m, q))
    args = [GR.find_godot(), "--path", os.path.join(ROOT, "game"), "--audio-driver", "Dummy", "--",
            "--balance", "--realtime", "--rtfrom=%g" % (a.at - 3), "--nodeath", "--seed=3", "--op=wisadel", "--squad=saria,exusiai", "--bot=expert",
            "--maxprog", "--bal=ult/bot_n=1", "--bal=ult/test_swarm_at=%g" % (a.at + 0.3), "--bal=ult/test_swarm_every=6",
            "--bal=ult/test_fill_at=%g" % FILLS[0], "--bal=ult/test_fill_every=5.5", "--bal=ult/wd_proto=" + m, "--quality=" + q,
            "--perf", "--perfdump=" + f.replace(os.sep, "/"), "--maxt=%d" % (FILLS[-1] + 3)]
    o, e, to = GR.run_godot(args, 1800)
    return job, f, GR.script_errors(o, e)[:2]


def stats(f):
    rows = list(csv.DictReader(open(f, encoding="utf-8")))
    out = {}
    for k in ("ft", "rcpu", "gpu"):
        w = np.array([float(r[k]) for r in rows if any(t0 <= float(r["t"]) < t0 + 2.0 for t0 in FILLS)])
        out[k] = (w.mean(), np.percentile(w, 95), w.max()) if len(w) else (0, 0, 0)
    out["fx"] = max((float(r["fx"]) for r in rows if any(t0 <= float(r["t"]) < t0 + 2.0 for t0 in FILLS)), default=0)
    return out


jobs = [(m, q) for q in a.q.split(",") for m in a.modes.split(",")]
with ThreadPoolExecutor(a.jobs) as ex:
    res = list(ex.map(one, jobs))
lines = ["| 画质 | wd_proto | 帧时 均 / p95 / 最大 ms | 渲染 CPU 均 / p95 / 最大 | GPU 均 / p95 / 最大 | fx 峰值 |", "|---|---|---|---|---|---|"]
for (m, q), f, err in res:
    if not os.path.exists(f):
        lines.append("| %s | %s | 无数据 %s | | | |" % (q, m, err)); continue
    s = stats(f)
    fm = lambda t: "%.2f / %.2f / %.2f" % t
    lines.append("| %s | %s | %s | %s | %s | %d |" % (q, m, fm(s["ft"]), fm(s["rcpu"]), fm(s["gpu"]), s["fx"]))
txt = "\n".join(lines)
open(os.path.join(OUT, "table.md"), "w", encoding="utf-8").write(txt + "\n")
print(txt)
