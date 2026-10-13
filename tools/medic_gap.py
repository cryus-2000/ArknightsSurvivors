"""医疗差距诊断（docs/88）：只读 BALANCE 记录，不跑游戏。

    python tools/medic_gap.py <组> [<组> ...] [--split squad] [--th 90]

每个位置参数是一组，写法同 tools/cloud_compare.py（cloud-results 的 tag、本地目录或 json，可写 名字=来源，多个来源用 + 连接）。
--split squad：一组里按开局编队再拆开（一个 tag 里跑了多个编队时）。

每组输出（单位：% 最大生命，存活局平均）：
  1. 胜率、输局死亡时间；
  2. 按 0–3 / 3–6 / 6–9 / 9+ 分钟：生命均值、承伤 / 秒（按来源归类）、治疗 / 秒（自身 / 医疗 / 浊心斯卡蒂 / 拾取 / 其他）、灯火均值与 < 30 占比；
  3. 压力窗（30 秒承伤 ≥ --th% 最大生命）：每局个数、窗内承伤 / 治疗分项、窗后生命中位、致死率，并按进窗灯火 < 30 / ≥ 30 分开；
  4. 寂灭秒与寂灭掉血（不进 dsrc）；
  5. 有 data.sus（docs/88 遥测，本分支起）时：治疗子项（实际 / 给出）、干员减伤、净化侵蚀池。
"""
import argparse, collections, os, statistics as st, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import cloud_compare as cc  # noqa: E402

BOSS = {"knight_boss", "paranoia", "carmen", "ishar", "archon", "path", "immortal", "iberia", "izumik", "bishop"}
DCATS = ["引痕/收割", "滑动者", "奠基者", "其他近身", "子弹", "冲击环", "溟痕", "侵蚀", "创口", "Boss", "其他"]
HCATS = ["自身", "医疗", "浊心", "拾取", "其他"]
HMAP = {"自身回复": "自身", "流明": "医疗", "凯尔希": "医疗", "浊心斯卡蒂": "浊心", "拾取": "拾取"}
SEGS = [(0, 180, "0–3"), (180, 360, "3–6"), (360, 540, "6–9"), (540, 10 ** 6, "9+")]
SUS_SEGS = [("m0", 0, 180), ("m3", 180, 360), ("m6", 360, 540), ("m9", 540, 10 ** 6)]


def dcat(k):
    if k.startswith("boss_"):
        return "Boss"
    p = k.split("_", 1)
    t = p[1] if len(p) == 2 else ""
    if t in BOSS:
        return "Boss"
    if p[0] in ("contact", "atk"):
        if t in ("tracer", "reaper"):
            return "引痕/收割"
        if t == "slider":
            return "滑动者"
        if t == "founder":
            return "奠基者"
        return "其他近身"
    if p[0] == "shock":
        return "冲击环"
    return {"bullet": "子弹", "mire": "溟痕", "corrode": "侵蚀", "wound": "创口"}.get(k, "其他")


def seg_name(t0):
    for a, b, n in SEGS:
        if a <= t0 < b:
            return n
    return SEGS[-1][2]


def windows(r):
    bot = r["data"].get("bot", {})
    out, prev = [], 0
    for c in bot.get("curve", []):
        out.append((prev, c["t"], c))
        prev = c["t"]
    ct = bot.get("curve_tail")
    if ct and ct.get("t", 0) > ct.get("t0", 0):
        out.append((ct["t0"], ct["t"], ct))
    return out


def dedupe(recs):
    seen = {}
    for r in recs:
        seen.setdefault(cc.rec_key(r), r)
    return list(seen.values())


def med(x):
    return st.median(x) if x else float("nan")


def report(name, rs, th):
    n = len(rs)
    w = sum(1 for r in rs if r["data"].get("win"))
    _p, lo, hi = cc.wilson(w, n)
    dts = sorted(int(r["data"]["t"]) for r in rs if not r["data"].get("win"))
    print("\n== %s：%d/%d = %.1f%%%s  输局死亡（秒）%s" % (name, w, n, 100.0 * w / max(1, n),
          "（Wilson [%.0f, %.0f]）" % (100 * lo, 100 * hi), dts))
    # 2. 分段
    S = {sn: {"sec": 0, "d": collections.Counter(), "h": collections.Counter(), "hp": [], "lamp": []} for _, _, sn in SEGS}
    for r in rs:
        for t0, t1, c in windows(r):
            s = S[seg_name(t0)]
            mh = max(1, c.get("mhp", 100))
            s["sec"] += t1 - t0
            for k, v in c.get("dsrc", {}).items():
                s["d"][dcat(k)] += 100.0 * v / mh
            for k, v in c.get("hsrc", {}).items():
                s["h"][HMAP.get(k, "其他")] += 100.0 * v / mh
            if "hp" in c:
                s["hp"].append(c["hp"])
            if "lamp" in c:
                s["lamp"].append(c["lamp"])
    print("  段    生命  灯火(<30)  承伤/s 治疗/s | " + " ".join(DCATS) + " | " + " ".join(HCATS))
    for _, _, sn in SEGS:
        s = S[sn]
        if not s["sec"]:
            continue
        sec = s["sec"]
        dk = sum(s["lamp"]) / len(s["lamp"]) if s["lamp"] else 0
        dark = 100.0 * sum(1 for x in s["lamp"] if x < 30) / max(1, len(s["lamp"]))
        print("  %-5s %5.1f %4.0f(%3.0f%%) %6.2f %6.2f | %s | %s" % (
            sn, med(s["hp"]), dk, dark, sum(s["d"].values()) / sec, sum(s["h"].values()) / sec,
            " ".join("%.2f" % (s["d"][c] / sec) for c in DCATS), " ".join("%.2f" % (s["h"][c] / sec) for c in HCATS)))
    # 3. 压力窗
    P = {"n": 0, "dead": 0, "d": 0.0, "h": collections.Counter(), "after": [], "lamp": {True: [0, 0], False: [0, 0]}}
    for r in rs:
        ws = windows(r)
        prev_lamp = 100
        for i, (t0, t1, c) in enumerate(ws):
            mh = max(1, c.get("mhp", 100))
            sc = 30.0 / max(1, t1 - t0)
            tk = 100.0 * sum(c.get("dsrc", {}).values()) / mh * sc
            if tk >= th:
                died = i == len(ws) - 1 and not r["data"].get("win")
                P["n"] += 1
                P["d"] += tk
                P["dead"] += died
                for k, v in c.get("hsrc", {}).items():
                    P["h"][HMAP.get(k, "其他")] += 100.0 * v / mh * sc
                if not died and "hp" in c:
                    P["after"].append(c["hp"])
                dk = prev_lamp < 30
                P["lamp"][dk][0] += died
                P["lamp"][dk][1] += 1
            prev_lamp = c.get("lamp", prev_lamp)
    if P["n"]:
        k = P["n"]
        print("  压力窗（≥%d%%/30 秒）%d 个（每局 %.1f），致死 %d（%.0f%%），窗内承伤 %.0f，治疗 %.0f：%s；窗后生命中位 %.0f；进窗灯火 <30 致死 %d/%d，≥30 致死 %d/%d" % (
            th, k, k / max(1, n), P["dead"], 100.0 * P["dead"] / k, P["d"] / k, sum(P["h"].values()) / k,
            " ".join("%s %.0f" % (c, v / k) for c, v in P["h"].most_common()), med(P["after"]),
            P["lamp"][True][0], P["lamp"][True][1], P["lamp"][False][0], P["lamp"][False][1]))
    # 4. 寂灭
    ds = [r["data"].get("bot", {}).get("dark_s", 0) for r in rs]
    dd = [100.0 * r["data"].get("bot", {}).get("dark_dmg", 0) / max(1.0, float(r["data"].get("maxhp", 100))) for r in rs]
    print("  寂灭：每局均 %.0f 秒（有寂灭的局 %d/%d），掉血均 %.0f%% 最大生命（不进 dsrc）" % (
        sum(ds) / max(1, n), sum(1 for x in ds if x > 0), n, sum(dd) / max(1, n)))
    # 5. sus 遥测
    if any("sus" in r["data"] for r in rs):
        for sk, a, b in SUS_SEGS:
            sec = 0
            H = collections.defaultdict(lambda: [0.0, 0.0])
            DR = collections.Counter()
            CL = 0.0
            for r in rs:
                t = r["data"]["t"]
                s = max(0, min(t, b) - a)
                if s <= 0:
                    continue
                sec += s
                mh = 100
                for c in r["data"].get("bot", {}).get("curve", []):
                    if c["t"] <= (a + min(t, b)) / 2 + 30:
                        mh = c.get("mhp", mh)
                mh = max(1, mh)
                ss = r["data"].get("sus", {}).get(sk, {})
                for key, v in ss.get("heal", {}).items():
                    H[key][0] += 100.0 * v[0] / mh
                    H[key][1] += 100.0 * v[1] / mh
                for key, v in ss.get("dr", {}).items():
                    DR[key] += 100.0 * v / mh
                CL += 100.0 * ss.get("clean", {}).get("corrode", 0.0) / mh
            if not sec:
                continue
            hs = sorted(H.items(), key=lambda kv: -kv[1][0])
            print("  遥测 %s：治疗 实际/给出 %s%s%s" % (
                sk, "  ".join("%s %.2f/%.2f" % (key, v[0] / sec, v[1] / sec) for key, v in hs if v[1] / sec >= 0.01),
                ("  | 干员减伤 " + " ".join("%s %.2f" % (key, v / sec) for key, v in DR.items())) if DR else "",
                ("  | 净化侵蚀池 %.2f" % (CL / sec)) if CL else ""))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("groups", nargs="+")
    ap.add_argument("--split", choices=["squad"], default=None)
    ap.add_argument("--th", type=float, default=90.0, help="压力窗阈值：30 秒承伤占最大生命的百分比（缺省 90）")
    a = ap.parse_args()
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    for spec in a.groups:
        name, recs, _metas, _envs = cc.load_source(spec)
        recs = dedupe(recs)
        if a.split:
            by = collections.defaultdict(list)
            for r in recs:
                by[",".join(r.get("squad", []))].append(r)
            for k in sorted(by):
                report("%s / %s" % (name, k), by[k], a.th)
        else:
            report(name, recs, a.th)


if __name__ == "__main__":
    main()
