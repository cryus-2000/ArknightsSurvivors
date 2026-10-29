# -*- coding: utf-8 -*-
"""Run boss diag scenarios in parallel. usage: run_diag.py <out.jsonl> <mode> ; mode = trial | normal | idle"""
import json, os, sys
from concurrent.futures import ThreadPoolExecutor
WT = r"E:\ArknightsSurvivors\.claude\worktrees\boss-bench-d562fa"
sys.path.insert(0, os.path.join(WT, "tools"))
import godot_runner as gr

out, mode = sys.argv[1], sys.argv[2]
GAME = os.path.join(WT, "game")
gr.ensure_imported(GAME)
BOSS = {"paranoia": "standard", "ishar": "deep", "knight_boss": "knight", "izumik": "resolve"}
jobs = []
if mode in ("trial", "idle"):
    for b in BOSS:
        for sq in ["wisadel_m0", "skadi_m0", "kaltsit_m0", "wisadel_m18", "skadi_m18", "kaltsit_m18"]:
            extra = ["--balance", "--bot=expert", "--diagbot", "--realtime"] if mode == "trial" else []
            jobs.append(((mode, b, sq), [gr.find_godot(), "--headless", "--path", GAME, "--fixed-fps", "30", "--"] + extra +
                         ["--bossdiag", "--diagtrial=%s:%s" % (b, sq), "--diagmax=150", "--maxt=900", "--seed=1"]))
else:
    for b, en in BOSS.items():
        for op in ["wisadel", "skadi", "kaltsit"]:
            for seed in [11, 12]:
                jobs.append((("normal", b, "%s_s%d" % (op, seed)), [gr.find_godot(), "--headless", "--path", GAME, "--", "--balance", "--bot=expert",
                             "--seed=%d" % seed, "--op=" + op, "--meta=0", "--forceending=" + en, "--bossdiag", "--diagmax=150", "--maxt=800"]))


def one(j):
    key, args = j
    o, e, to = gr.run_godot(args, 1500)
    recs = [json.loads(l[9:]) for l in o.splitlines() if l.startswith("BOSSDIAG {")]
    sq = [l for l in o.splitlines() if l.startswith("BOSSDIAG_SQUAD")]
    return {"key": key, "recs": recs, "squad": sq, "errors": gr.script_errors(o, e)[:3], "timeout": to}


with ThreadPoolExecutor(max_workers=6) as ex, open(out, "w", encoding="utf-8") as f:
    for r in ex.map(one, jobs):
        f.write(json.dumps(r, ensure_ascii=False) + "\n")
        f.flush()
        print(r["key"], len(r["recs"]), r["errors"][:1], "TIMEOUT" if r["timeout"] else "", flush=True)
