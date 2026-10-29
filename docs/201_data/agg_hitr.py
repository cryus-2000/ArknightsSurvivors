"""Visible vs hit radius table per boss / bullet kind. usage: agg_hitr.py <idle jsonl>  (pad 3: visible outer = r + 3)"""
import json, sys, statistics as st
by = {}
for l in open(sys.argv[1], encoding="utf-8"):
    r = json.loads(l)
    for rec in r["recs"]:
        if rec["boss"] != r["key"][1]:
            continue
        for k, v in rec.get("kinds", {}).items():
            d = by.setdefault(rec["boss"], {}).setdefault(k, {"n": 0, "r": []})
            d["n"] += v["n"]; d["r"] += v.get("r", [])
print("boss | kind | n | r | visible outer r+3 | core 0.6r | 70% | 85% | 100%")
for b, ks in by.items():
    for k, d in sorted(ks.items(), key=lambda kv: -kv[1]["n"]):
        if not d["r"]:
            continue
        r = st.median(d["r"]); vis = r + 3.0
        print("%s | %s | %d | %.1f | %.1f | %.1f | %.1f | %.1f | %.1f" % (b, k, d["n"], r, vis, 0.6 * r, 0.7 * vis, 0.85 * vis, vis))
