import json, sys, statistics as st
for path in sys.argv[1:]:
    rows = [json.loads(l) for l in open(path, encoding="utf-8")]
    print("==", path.replace("\\", "/").split("/")[-1], "jobs", len(rows), "err", sum(1 for r in rows if r["errors"]))
    by = {}
    for r in rows:
        for rec in r["recs"]:
            if rec["boss"] == r["key"][1]:
                by.setdefault(rec["boss"], []).append(rec)
    for b, recs in by.items():
        tpm = [x.get("taken_pct_per_min", 0) for x in recs]
        mh = [x.get("max_hp", 0) for x in recs]
        print("%-12s fight %5.1f  taken/min %5.1f (%.0f%% maxhp/min)  TTK %5.1fs  maxhp %3.0f  hits/min %.1f  wins %d/%d" % (
            b, st.median([x["fight_t"] for x in recs]), st.median([x.get("taken_per_min", 0) for x in recs]), 100 * st.median(tpm),
            60.0 / max(1e-3, st.median(tpm)), st.median(mh), st.median([x.get("p_hits", 0) * 60 / x["fight_t"] for x in recs]),
            sum(x["why"] == "win" for x in recs), len(recs)))
        src = {}
        for x in recs:
            for s, v in x.get("p_src", {}).items():
                src.setdefault(s, []).extend(v)
        for s, v in sorted(src.items(), key=lambda kv: -len(kv[1]))[:14]:
            pc = sorted(x[0] if isinstance(x, list) else x for x in v)
            rw = sorted(x[1] for x in v if isinstance(x, list))
            print("     %-34s n%4d  med %4.1f%%  max %4.1f%%  raw med %5.1f max %5.1f" % (s[:34], len(v), 100 * pc[len(pc) // 2], 100 * pc[-1], rw[len(rw) // 2] if rw else -1, rw[-1] if rw else -1))
