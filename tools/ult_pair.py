"""终结技原型配对报告（docs/198 / docs/199）：读 cloud-results/ult-T0（ult/on=0）与 ult-T1（ult/on=1）的 build/cloud_ult/raw/*.json，
按（编队, seed, 档）配对，出每档：胜率与差、新胜旧负 / 旧胜新负、均存活秒、输局死亡时段分布、T1 每局终结技 / 连携 / 连携终结技次数与时刻。
用法：python tools/ult_pair.py [--fetch] [--t0 cloud-results/ult-T0] [--t1 cloud-results/ult-T1]"""
import argparse
import json
import os
import statistics
import subprocess
import sys

sys.stdout.reconfigure(encoding="utf-8")
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def git(*a):
    return subprocess.run(["git", "-C", ROOT] + list(a), capture_output=True, text=True, encoding="utf-8").stdout


def load(branch):
    ref = "origin/" + branch
    recs = {}
    for f in git("ls-tree", "-r", "--name-only", ref).splitlines():
        if not (f.startswith("build/cloud_ult/raw/") and f.endswith(".json")):
            continue
        tag = os.path.basename(f)
        band = "m18" if "_m18_" in tag else "m0"
        d = json.loads(git("show", ref + ":" + f))
        for r in d.get("records", []):
            key = (band, ",".join(r.get("squad", [])), int(r.get("seed", 0)))
            recs[key] = r
    return recs


def win(r):
    return bool(r.get("data", {}).get("win"))


def tsurv(r):
    return float(r.get("data", {}).get("t", 0))


def minute_bucket(t):
    return "%d–%d" % (int(t // 60), int(t // 60) + 1) if t < 600 else "10+"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--fetch", action="store_true")
    ap.add_argument("--t0", default="cloud-results/ult-T0")
    ap.add_argument("--t1", default="cloud-results/ult-T1")
    a = ap.parse_args()
    if a.fetch:
        git("fetch", "origin", a.t0 + ":refs/remotes/origin/" + a.t0, a.t1 + ":refs/remotes/origin/" + a.t1)
    A, B = load(a.t0), load(a.t1)
    for band in ["m0", "m18"]:
        keys = sorted(k for k in A if k[0] == band and k in B)
        if not keys:
            print("## %s：没有配对" % band)
            continue
        wa = sum(win(A[k]) for k in keys)
        wb = sum(win(B[k]) for k in keys)
        only_b = sum(1 for k in keys if win(B[k]) and not win(A[k]))
        only_a = sum(1 for k in keys if win(A[k]) and not win(B[k]))
        n = len(keys)
        print("## %s（%d 对）" % (band, n))
        print("- 胜率：ult/on=0 %d/%d = %.1f%% → ult/on=1 %d/%d = %.1f%%，差 %+.1f 点；新胜旧负 %d / 旧胜新负 %d" % (wa, n, 100.0 * wa / n, wb, n, 100.0 * wb / n, 100.0 * (wb - wa) / n, only_b, only_a))
        print("- 均存活秒：%.0f → %.0f" % (statistics.mean(tsurv(A[k]) for k in keys), statistics.mean(tsurv(B[k]) for k in keys)))
        for nm, S in (("ult/on=0", A), ("ult/on=1", B)):
            dist = {}
            for k in keys:
                if not win(S[k]):
                    b = minute_bucket(tsurv(S[k]))
                    dist[b] = dist.get(b, 0) + 1
            order = sorted(dist, key=lambda s: (s == "10+", int(s.split("–")[0]) if s != "10+" else 99))
            print("- 输局死亡时段 %s：%s" % (nm, "，".join("%s 分 %d" % (b, dist[b]) for b in order) or "无"))
        us = [B[k]["data"].get("ult") or {} for k in keys]
        def avg(f):
            return statistics.mean(float(u.get(f, 0)) for u in us)
        print("- 每局（ult/on=1）：终结技 %.2f、连携终结技 %.2f、连携 %.1f（其中组合自动接 %.1f）、亮起 %.1f、漏按 %.1f" % (avg("ult"), avg("cult"), avg("combo"), avg("combo_up"), avg("lit"), avg("miss")))
        ff = [float(u.get("first_full", -1)) for u in us if float(u.get("first_full", -1)) > 0]
        if ff:
            print("- 首次充满：中位 %.0f 秒（%d 局有）" % (statistics.median(ff), len(ff)))
        ut = sorted(t for u in us for t in u.get("ult_times", []))
        ct = sorted(t for u in us for t in u.get("cult_times", []))
        def hist(ts):
            h = {}
            for t in ts:
                b = minute_bucket(t)
                h[b] = h.get(b, 0) + 1
            return "，".join("%s 分 %d" % (b, h[b]) for b in sorted(h, key=lambda s: int(s.split("–")[0]) if s != "10+" else 99))
        print("- 终结技时刻分布：%s" % (hist(ut) or "无"))
        print("- 连携终结技时刻分布：%s" % (hist(ct) or "无"))
        es = {s: avg("e_" + s) for s in ["out", "kill", "hurt", "combo"]}
        tot = sum(es.values()) or 1.0
        print("- 能量来源占比：输出 %.0f%% / 击杀 %.0f%% / 受伤 %.0f%% / 连携 %.0f%%" % tuple(100.0 * es[s] / tot for s in ["out", "kill", "hurt", "combo"]))
        print()


if __name__ == "__main__":
    main()
