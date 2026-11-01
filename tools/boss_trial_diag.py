# -*- coding: utf-8 -*-
"""Boss 体检（11-01，claude/boss-diag-1101 专用，不合入）：每组 Boss × 成品分队 × 种子起一局演练，机器人 expert 打，
读 boss_trial.gd 打印的 TRIALREC（run.trial 同格式），一局一行写 <out>/trial_diag.txt（云端只收 md / json / txt / log）。
用法：python tools/boss_trial_diag.py --out <目录> [--seeds 1,2,3] [--cap 300] [--jobs N]
"""
import argparse, json, os, sys
from concurrent.futures import ThreadPoolExecutor
ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import godot_runner as gr

GROUPS = ["path", "iberia", "carmen", "bishop+archon", "bishop+immortal", "paranoia", "ishar", "knight_boss", "izumik"]
SQUADS = ["wisadel_m0", "skadi_m0", "kaltsit_m0", "wisadel_m18", "skadi_m18", "kaltsit_m18"]

ap = argparse.ArgumentParser()
ap.add_argument("--out", required=True)
ap.add_argument("--seeds", default="1,2,3")
ap.add_argument("--cap", type=int, default=300)
ap.add_argument("--jobs", type=int, default=0)
a = ap.parse_args()
os.makedirs(a.out, exist_ok=True)
GAME = os.path.join(ROOT, "game")
gr.ensure_imported(GAME)
jobs = []
for grp in GROUPS:
    for sq in SQUADS:
        for s in a.seeds.split(","):
            jobs.append(((grp, sq, int(s)), [gr.find_godot(), "--headless", "--path", GAME, "--fixed-fps", "30", "--", "--balance", "--bot=expert",
                         "--diagbot", "--realtime", "--diagtrial=%s:%s" % (grp, sq), "--diagmax=%d" % a.cap, "--maxt=1500", "--seed=" + s]))


def one(j):
    key, args = j
    o, e, to = gr.run_godot(args, 1800)
    recs = [json.loads(l[9:]) for l in o.splitlines() if l.startswith("TRIALREC {")]
    return {"key": list(key), "rec": recs[0] if recs else None, "errors": gr.script_errors(o, e)[:3], "timeout": to}


n = a.jobs or gr._max_procs()
with ThreadPoolExecutor(max_workers=max(1, n)) as ex, open(os.path.join(a.out, "trial_diag.txt"), "w", encoding="utf-8") as f:
    for r in ex.map(one, jobs):
        f.write(json.dumps(r, ensure_ascii=False) + "\n")
        f.flush()
        rec = r["rec"] or {}
        print(r["key"], rec.get("result"), rec.get("t"), r["errors"][:1], "TIMEOUT" if r["timeout"] else "", flush=True)
