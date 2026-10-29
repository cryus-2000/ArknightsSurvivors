"""Bullet speed inventory per boss / kind from run_diag.py jsonl (probe with kinds). usage: agg_spd.py <jsonl>..."""
import json, sys, statistics as st
for path in sys.argv[1:]:
    rows = [json.loads(l) for l in open(path, encoding="utf-8")]
    by = {}
    for r in rows:
        for rec in r["recs"]:
            if rec["boss"] != r["key"][1]:
                continue
            for k, v in rec.get("kinds", {}).items():
                d = by.setdefault(rec["boss"], {}).setdefault(k, {"n": 0, "v0": [], "v1": [], "vmax": 0.0, "home": 0})
                d["n"] += v["n"]; d["v0"] += v["v0"]; d["v1"] += v["v1"]; d["vmax"] = max(d["vmax"], v["vmax"]); d["home"] += v["home"]
    las = {}
    for r in rows:
        for rec in r["recs"]:
            if rec["boss"] == r["key"][1]:
                for k, v in rec.get("lasers", {}).items():
                    las.setdefault(rec["boss"], {}).setdefault(k, []).extend(v)
    print("==", path.replace("\\", "/").split("/")[-1])
    for b, ks in las.items():
        for k, v in ks.items():
            print("LASER %-12s %-26s n%3d  dur %s  track %s" % (b, k[:26], len(v), sorted(set(x[0] for x in v)), sorted(set(x[1] for x in v))))
    for b, ks in by.items():
        print(b)
        for k, d in sorted(ks.items(), key=lambda kv: -kv[1]["n"]):
            med0 = st.median(d["v0"]) if d["v0"] else -1
            med1 = st.median(d["v1"]) if d["v1"] else -1
            print("   %-28s n%5d  v0 %4.0f  v1s %4.0f  max %4.0f  home %d" % (k[:28], d["n"], med0, med1, d["vmax"], d["home"]))
