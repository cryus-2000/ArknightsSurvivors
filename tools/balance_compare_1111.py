# -*- coding: utf-8 -*-
"""docs/331 §8 改后对照（11-11）：改前 / 改后 balance_run 结果按实现（placebo）分组，比胜率、死亡分布、各时刻压力，出前后对比图。
用法：python tools/balance_compare_1111.py --arm 改前m0=<dir>[,<dir>] --arm 改后m0=<dir> ... --out "Claude outputs/balance_audit_1110"
只读结果，不跑游戏。"""
import argparse, glob, json, os, statistics, sys
from collections import defaultdict
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

sys.stdout.reconfigure(encoding="utf-8")
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
plt.rcParams["font.sans-serif"] = ["Microsoft YaHei", "SimHei", "Noto Sans CJK SC", "DejaVu Sans"]
plt.rcParams["axes.unicode_minus"] = False
SEGS = [("0–3:30", 0, 210), ("3:30–7", 210, 420), ("7–10", 420, 600), ("10+", 600, 9999)]


def load(spec):
    recs = []
    for d in spec.split(","):
        fs = [d] if d.endswith(".json") else glob.glob(os.path.join(d, "**", "*.json"), recursive=True)
        for f in fs:
            j = json.load(open(f, encoding="utf-8"))
            if not isinstance(j, dict):
                continue
            for w in j.get("records", []):
                r = w.get("data") or {}
                if r:
                    r = dict(r)
                    r["_pl"] = w.get("placebo", 0)
                    r["_start"] = (w.get("squad") or ["?"])[0]
                    recs.append(r)
    return recs


def summary(recs):
    by = defaultdict(list)
    for r in recs:
        by[r["_pl"]].append(r)
    wins = {p: sum(1 for r in v if r.get("win")) / len(v) for p, v in sorted(by.items())}
    seg = defaultdict(int)
    for r in recs:
        if r.get("win"):
            continue
        t = r.get("t", 0)
        for n, a, b in SEGS:
            if a <= t < b:
                seg[n] += 1
    press = defaultdict(list)
    for r in recs:
        for c in (r.get("bot") or {}).get("curve") or []:
            press[c["t"]].append(c["taken"] * 2.0 / max(1, c["mhp"]) * 100)
    pc = {}
    for t, v in sorted(press.items()):
        v = sorted(v)
        pc[t] = (statistics.mean(v), v[int(0.9 * (len(v) - 1))], len(v))
    starts = defaultdict(list)
    for r in recs:
        starts[r["_start"]].append(1 if r.get("win") else 0)
    bt = defaultdict(list)
    for r in recs:
        for b in (r.get("bot") or {}).get("bosses", []):
            if b.get("t1", -1) >= 0:
                bt[b["type"]].append(b["t1"] - b["t0"])
    seen = defaultdict(lambda: [0, 0])
    for r in recs:
        for b in (r.get("bot") or {}).get("bosses", []):
            seen[b["type"]][0] += 1
            if b.get("t1", -1) >= 0:
                seen[b["type"]][1] += 1
    src = defaultdict(int)
    for r in recs:
        if not r.get("win"):
            src[(r.get("bot") or {}).get("death_src", "?")] += 1
    return {"n": len(recs), "win": statistics.mean(wins.values()) if wins else 0, "win_pl": wins,
            "sd": statistics.pstdev(wins.values()) if len(wins) > 1 else 0, "seg": {n: seg.get(n, 0) for n, _, _ in SEGS},
            "press": pc, "starts": {k: sum(v) / len(v) for k, v in sorted(starts.items())},
            "boss_t": {k: statistics.median(v) for k, v in bt.items()}, "boss_kill": {k: v for k, v in seen.items()},
            "death_src": dict(sorted(src.items(), key=lambda x: -x[1])[:8])}


def win_window(pc, a, b):
    m = [v[0] for t, v in pc.items() if a <= t <= b]
    p = [v[1] for t, v in pc.items() if a <= t <= b]
    return (statistics.mean(m) if m else 0, statistics.mean(p) if p else 0)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--arm", action="append", default=[])
    ap.add_argument("--out", default="Claude outputs/balance_audit_1110")
    a = ap.parse_args()
    S = {}
    for s in a.arm:
        k, v = s.split("=", 1)
        S[k] = summary(load(v))
    res = {}
    for k, s in S.items():
        w45 = win_window(s["press"], 240, 330)
        res[k] = {kk: s[kk] for kk in ("n", "win", "win_pl", "sd", "seg", "starts", "boss_t", "boss_kill", "death_src")}
        res[k]["press_4_5:30"] = w45
        res[k]["press_at"] = {t: s["press"].get(t) for t in (60, 180, 270, 300, 330, 420, 540, 600, 660)}
        print(k, "n=%d 胜率 %.1f%%（%s，sd %.1f）死亡 %s 4:00–5:30 压力 均 %.0f / P90 %.0f" % (
            s["n"], 100 * s["win"], " / ".join("%.0f" % (100 * x) for x in s["win_pl"].values()), 100 * s["sd"], s["seg"], w45[0], w45[1]))
    json.dump(res, open(os.path.join(a.out, "compare_1111.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1, default=str)
    fig, ax = plt.subplots(1, 2, figsize=(12, 4.2))
    sty = {"改前": "-", "改后": "--", "仅调数": ":"}
    for k, s in S.items():
        ls = next((v for p, v in sty.items() if k.startswith(p)), "-")
        col = "C3" if "m0" in k else "C4"
        tt = [t for t in sorted(s["press"]) if t <= 720 and s["press"][t][2] >= 20]
        ax[0].plot([t / 60 for t in tt], [s["press"][t][0] for t in tt], ls=ls, color=col, label=k)
        ax[1].plot([t / 60 for t in tt], [s["press"][t][1] for t in tt], ls=ls, color=col, label=k)
    for x, tit in ((ax[0], "压力均值（每分钟承伤 % 最大生命）"), (ax[1], "压力 P90")):
        x.axvspan(4, 5.5, color="orange", alpha=.1)
        x.set_xlabel("分钟"); x.set_title(tit); x.grid(alpha=.3); x.legend(fontsize=8)
    fig.tight_layout(); fig.savefig(os.path.join(a.out, "06_press_before_after.png"), dpi=110); plt.close(fig)
    # 静态：池平均一下伤害前后
    import balance_audit_1110 as A
    ts = list(range(0, 631, 5))
    new = [A.pool_avg(A.mob_hit, t) for t in ts]
    newhp = [A.pool_avg(A.normal_hp, t) for t in ts]
    A.SL["comp_from"], A.SL["comp_to"] = 150, 360
    A.TH[3]["tier_hp"] = 0.6
    A.TH[5]["tier_hp"], A.TH[5]["tier_dmg"] = 0.35, 0.45
    A.TH[4]["tier_hp"], A.TH[4]["tier_dmg"] = 0.45, 0.54
    A.B["dmg_curve"]["knots"] = [list(k) for k in A.B["dmg_curve"]["knots"]]
    A.B["dmg_curve"]["knots"][-1] = [600, 30.0]
    old = [A.pool_avg(A.mob_hit, t) for t in ts]
    oldhp = [A.pool_avg(A.normal_hp, t) for t in ts]
    fig, ax = plt.subplots(1, 2, figsize=(12, 4.2))
    ax[0].plot([t / 60 for t in ts], old, "k-", label="改前"); ax[0].plot([t / 60 for t in ts], new, "C2--", label="改后")
    ax[0].set_title("普通怪池平均一下伤害（受伤 0.9、护甲 1.9 后）"); ax[0].set_xlabel("分钟"); ax[0].grid(alpha=.3); ax[0].legend()
    ax[1].plot([t / 60 for t in ts], oldhp, "k-", label="改前"); ax[1].plot([t / 60 for t in ts], newhp, "C2--", label="改后")
    ax[1].set_yscale("log"); ax[1].set_title("刷怪池平均单只生命"); ax[1].set_xlabel("分钟"); ax[1].grid(alpha=.3); ax[1].legend()
    fig.tight_layout(); fig.savefig(os.path.join(a.out, "07_curve_before_after.png"), dpi=110); plt.close(fig)


if __name__ == "__main__":
    main()
