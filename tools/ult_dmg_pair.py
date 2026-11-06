"""终结技伤害配对（docs/302）：按（编队, seed, 安慰剂）配对两组 cloud-results，出每档胜率、各份实现胜率、负转胜 / 胜转负与符号检验 p。
用法：python tools/ult_dmg_pair.py <基线分支[,分支…]> <对照分支[,分支…]>"""
import math, statistics as st, sys
sys.path.insert(0, __import__("os").path.dirname(__file__))
import ult_dmg_audit as U

def recs(branches):
    out = {}
    for b in branches.split(","):
        for r in U.load(b):
            out[(r["_band"], ",".join(r["squad"]), r["seed"], r.get("placebo", 0))] = r
    return out

def sign_p(a, b):
    n = a + b
    if n == 0:
        return 1.0
    k = min(a, b)
    return min(1.0, 2 * sum(math.comb(n, i) for i in range(k + 1)) / 2 ** n)

A, B = recs(sys.argv[1]), recs(sys.argv[2])
for band in ("m0", "m18"):
    keys = [k for k in A if k[0] == band and k in B]
    w = lambda R, ks: sum(1 for k in ks if R[k]["data"].get("win")) / max(1, len(ks)) * 100
    pl = sorted({k[3] for k in keys})
    per = [(w(A, [k for k in keys if k[3] == p]), w(B, [k for k in keys if k[3] == p])) for p in pl]
    up = sum(1 for k in keys if B[k]["data"].get("win") and not A[k]["data"].get("win"))
    dn = sum(1 for k in keys if A[k]["data"].get("win") and not B[k]["data"].get("win"))
    sa = st.mean(A[k]["data"]["t"] for k in keys); sb = st.mean(B[k]["data"]["t"] for k in keys)
    print("%s %d 对：胜率 %.1f → %.1f（%+.1f）| 各份 %s | 负转胜 %d / 胜转负 %d p=%.3f | 均存活 %.0f → %.0f 秒" % (
        band, len(keys), w(A, keys), w(B, keys), w(B, keys) - w(A, keys),
        " ".join("%.0f→%.0f" % x for x in per), up, dn, sign_p(up, dn), sa, sb))
