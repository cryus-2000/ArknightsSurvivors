import json, sys, statistics as st
for p in sys.argv[1:]:
    rs = [rec for l in open(p, encoding="utf-8") for r in [json.loads(l)] for rec in r["recs"] if rec["boss"] == r["key"][1]]
    def m(k):
        v = [x.get(k, -1) for x in rs if x.get(k, -1) >= 0]
        return round(st.median(v), 2) if v else -1
    print(p.split("/")[-1], "runs", len(rs), "peak_bul", m("bul_peak"), "ft>=130 n", m("ft_hi_n"), "p50", m("ft_hi_p50"), "p95", m("ft_hi_p95"), "| all p50", m("ft_all_p50"), "p95", m("ft_all_p95"))
