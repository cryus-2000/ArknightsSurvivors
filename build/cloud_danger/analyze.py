"""docs/178 云端结果汇总：python3 build/cloud_danger/analyze.py [side ...]，读 build/cloud_danger/raw/*.json.gz"""
import json, glob, gzip, os, sys, math
from collections import defaultdict
RAW = os.path.join(os.path.dirname(os.path.abspath(__file__)), "raw")
recs = defaultdict(dict)   # (side, cell) -> {(squad, seed): rec}
for f in sorted(glob.glob(os.path.join(RAW, "*.json.gz"))):
    tag = os.path.basename(f)[:-8].rsplit("_s", 1)[0]          # e.g. new_n0
    side, cell = tag.rsplit("_", 1)
    for r in json.load(gzip.open(f, "rt", encoding="utf-8"))["records"]:
        recs[(side, cell)][("+".join(r["squad"]), r["seed"])] = r

def win(r): return bool(r.get("data", {}).get("win"))
def wilson(k, n, z=1.96):
    if n == 0: return (0, 0)
    p = k / n; d = 1 + z * z / n; c = (p + z * z / (2 * n)) / d; h = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / d
    return (c - h, c + h)
def mcnemar(b, c):
    n = b + c
    if n == 0: return 1.0
    k = min(b, c); p = sum(math.comb(n, i) for i in range(k + 1)) / 2 ** n
    return min(1.0, 2 * p)
def stats(rs):
    n = len(rs); k = sum(win(r) for r in rs); lo, hi = wilson(k, n)
    ok = [r for r in rs if "data" in r]
    t = [r["data"]["t"] for r in ok]
    bot = [r["data"].get("bot", {}) for r in ok]
    def avg(key):
        v = [b[key] for b in bot if key in b]
        return (sum(v) / len(v)) if v else None
    deaths = [r["data"]["t"] for r in ok if not r["data"].get("win")]
    bins = [(0, 300), (300, 480), (480, 600), (600, 720), (720, 99999)]
    dist = [sum(1 for x in deaths if a <= x < b) for a, b in bins]
    kl = [b["king_low_s"] for b in bot if "king_low_s" in b]
    return dict(n=n, k=k, lo=lo, hi=hi, surv=sum(t) / len(t) if t else 0, low35=avg("low_hp_s"), low20=avg("low20_s"),
                king=avg("king_low_s"), king_runs=sum(1 for x in kl if x > 0), king_n=len(kl), dist=dist,
                timeouts=sum(1 for r in rs if "data" not in r), errs=sum(1 for r in rs if r.get("script_errors")),
                err_list=["%s s%d: %s" % ("+".join(r["squad"]), r["seed"], r.get("first_error", r.get("error", ""))[:90]) for r in rs if r.get("script_errors") or "data" not in r])
def f(x, fmt="%.1f"): return "—" if x is None else fmt % x
CELLS = [("n0", "常规 · 无成长"), ("n18", "常规 · 18 细胞"), ("h0", "高压 · 无成长"), ("h18", "高压 · 18 细胞")]
sides = sys.argv[1:] or ["new"]
print("| 档 | 组 | 胜率（95% 区间） | McNemar 新胜旧负 / 旧胜新负 · p | 均存活 | 死亡分布 <5 / 5–8 / 8–10 / 10–12 / ≥12 分 | 生命<35% 秒 | <20% 秒 | 国王套低血秒 / 局（有触发局 / 局） | 超时 | script_errors |")
print("|---|---|---|---|---|---|---|---|---|---|---|")
errs = []
for cell, name in CELLS:
    old = recs.get(("old", cell), {})
    for side in ["old"] + sides:
        cur = recs.get((side, cell), {})
        if not cur: continue
        keys = sorted(set(cur) & set(old)) if side != "old" and old else sorted(cur)
        s = stats([cur[k] for k in keys])
        mc = "—"
        if side != "old" and old:
            b = sum(1 for k in keys if win(cur[k]) and not win(old[k])); c = sum(1 for k in keys if win(old[k]) and not win(cur[k]))
            mc = "%d / %d · p=%.3f" % (b, c, mcnemar(b, c))
        print("| %s | %s | %d/%d = %.1f%%（%.1f–%.1f） | %s | %d 秒 | %s | %s | %s | %s（%d/%d） | %d | %d |" % (
            name, side, s["k"], s["n"], 100 * s["k"] / max(1, s["n"]), 100 * s["lo"], 100 * s["hi"], mc, s["surv"],
            " / ".join(map(str, s["dist"])), f(s["low35"]), f(s["low20"]), f(s["king"], "%.2f"), s["king_runs"], s["king_n"], s["timeouts"], s["errs"]))
        errs += ["%s %s %s" % (side, cell, e) for e in s["err_list"]]
for e in errs: print("- " + e)
