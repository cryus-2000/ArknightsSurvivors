import json, sys, statistics as st
F = ["fight_t", "dmg_warns_per_min", "bul_per_s", "bul_spd", "hits_per_s", "wind", "brk", "stun", "seal", "hold", "inv", "shake", "flash", "blocked"]
for path in sys.argv[1:]:
    rows = [json.loads(l) for l in open(path, encoding="utf-8")]
    print("==", path.split("/")[-1].split("\\")[-1], "jobs", len(rows), "errors", sum(1 for r in rows if r["errors"]), "timeouts", sum(1 for r in rows if r["timeout"]))
    by = {}
    why = {}
    for r in rows:
        b = r["key"][1]
        for rec in r["recs"]:
            if rec["boss"] == b:
                by.setdefault(b, []).append(rec)
                why.setdefault(b, []).append(rec["why"])
    print("boss         " + " ".join("%8s" % f[:8] for f in F) + "  results")
    for b, recs in by.items():
        print("%-12s " % b + " ".join("%8.2f" % st.median([float(x[f]) for x in recs]) for f in F), {w: why[b].count(w) for w in set(why[b])})
    sq = [s for r in rows for s in r["squad"]][:3]
    for s in sq:
        print("  ", s[:200])
