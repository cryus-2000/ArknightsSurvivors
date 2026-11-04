#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""后期打得动 A/B 汇总（docs/244）：开关 growth/late_shape 0 / 1 的配对对比。

用法（仓库根目录）：
    python tools/late_power_ab.py --diag0 build/ab/diag_base.jsonl --diag1 build/ab/diag_on.jsonl \
        --win "build/ab/win/win_m0_off_*.json,build/ab/win/win_m0_on_*.json,build/ab/win/win_m18_off_*.json,build/ab/win/win_m18_on_*.json" \
        --out docs/assets/late_power_ab
诊断（late_game_diag.py run，--nodeath --diagbins）按 (队长, 种子, 潮位) 配对：清怪比、终结技占比、同屏清空秒数；
胜率（balance_run.py，expert，starts × 4 seed × 安慰剂 3 份）按 (编队, 种子, 安慰剂) 配对：胜率、局长、死亡时刻。
输出 ab.md（表）+ ab.json + 图 PNG。
"""
import argparse, glob, json, math, os, statistics as st, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from late_game_diag import load, per_min

LATE = range(5, 10)   # 5–9 分钟


def run_metrics(rec):
    """一局：逐分钟清怪比 / 同屏清空秒数，5–9 分钟终结技占普通怪伤害 / 击杀"""
    rows = []
    agg = {"nb": 0.0, "nb_ult": 0.0, "k": 0.0, "k_ult": 0.0, "nb_all": 0.0, "nb_all_ult": 0.0}
    for m in per_min(rec):
        nb = sum(m["dmg_nb"].values())
        u = m["dmg_nb"].get("ult", 0.0)
        n = max(1, m["ns"])
        hp_screen = m["hps_sum"] / n
        dps = (nb - u) / 60.0
        cr = (nb - u) / m["sp_hp"] if m["sp_hp"] > 0 else None
        ttc = hp_screen / dps if dps > 0 else None
        rows.append({"m": m["m"], "clear_r": cr, "ttc": ttc, "lv": m["lv"]})
        if m["m"] in LATE:
            agg["nb"] += nb
            agg["nb_ult"] += u
            agg["k"] += sum(m["kill"].values())
            agg["k_ult"] += m["kill"].get("ult", 0)
    return rows, agg


def diag_side(path):
    out = {}
    for r in load(path):
        rows, agg = run_metrics(r["rec"])
        out[(r["op"], r["seed"], r["tide"])] = {"rows": rows, "agg": agg, "rec": r["rec"]}
    return out


def med(xs):
    xs = [x for x in xs if x is not None]
    return st.median(xs) if xs else float("nan")


def summarize_diag(side, keys, tide):
    ks = [k for k in keys if k[2] == tide]
    crs = [row["clear_r"] for k in ks for row in side[k]["rows"] if row["m"] in LATE and row["clear_r"] is not None]
    tts = [row["ttc"] for k in ks for row in side[k]["rows"] if row["m"] in LATE and row["ttc"] is not None]
    nb = sum(side[k]["agg"]["nb"] for k in ks)
    nbu = sum(side[k]["agg"]["nb_ult"] for k in ks)
    kk = sum(side[k]["agg"]["k"] for k in ks)
    ku = sum(side[k]["agg"]["k_ult"] for k in ks)
    return {"n_runs": len(ks), "n_min": len(crs), "clear_med": med(crs), "clear_lt1": sum(1 for x in crs if x < 1) / max(1, len(crs)),
            "ult_dmg": nbu / nb if nb else float("nan"), "ult_kill": ku / kk if kk else float("nan"), "ttc_med": med(tts),
            "win": sum(1 for k in ks if side[k]["rec"].get("win")) / max(1, len(ks)), "t_med": med([side[k]["rec"].get("t") for k in ks])}


def by_minute(side, keys, tide):
    out = {}
    for k in keys:
        if k[2] != tide:
            continue
        for row in side[k]["rows"]:
            out.setdefault(row["m"], {"cr": [], "ttc": []})
            if row["clear_r"] is not None:
                out[row["m"]]["cr"].append(row["clear_r"])
            if row["ttc"] is not None:
                out[row["m"]]["ttc"].append(row["ttc"])
    return out


def per_op(side0, side1, keys, tide):
    ops = sorted({k[0] for k in keys})
    res = []
    for op in ops:
        ks = [k for k in keys if k[0] == op and k[2] == tide]
        def f(side):
            crs = [row["clear_r"] for k in ks for row in side[k]["rows"] if row["m"] in LATE and row["clear_r"] is not None]
            k_ = sum(side[k]["agg"]["k"] for k in ks)
            ku = sum(side[k]["agg"]["k_ult"] for k in ks)
            return med(crs), (ku / k_ if k_ else float("nan"))
        a, b = f(side0), f(side1)
        res.append({"op": op, "cr0": a[0], "cr1": b[0], "uk0": a[1], "uk1": b[1]})
    return res


# ---------------------------------------------------------------- 胜率

def load_win(pattern):
    recs = []
    for f in sorted(glob.glob(pattern)):
        recs += json.load(open(f, encoding="utf-8"))["records"]
    return recs


def wkey(r):
    return (",".join(r["squad"]) if isinstance(r["squad"], list) else str(r["squad"]), r["seed"], r.get("placebo", 0))


def is_timeout(d):
    return (not d.get("win")) and d.get("t", 0) >= 779


def summarize_win(recs):
    ds = [r["data"] for r in recs if "data" in r]
    pl = {}
    for r in recs:
        if "data" in r:
            pl.setdefault(r.get("placebo", 0), []).append(1 if r["data"].get("win") else 0)
    deaths = [d["t"] for d in ds if not d.get("win") and not is_timeout(d)]
    return {"n": len(ds), "win": sum(1 for d in ds if d.get("win")) / max(1, len(ds)),
            "pl": {p: sum(v) / len(v) for p, v in sorted(pl.items())},
            "pl_sd": st.pstdev([sum(v) / len(v) for v in pl.values()]) if len(pl) > 1 else 0.0,
            "t_med": med([d["t"] for d in ds]), "t_win_med": med([d["t"] for d in ds if d.get("win")]),
            "death_n": len(deaths), "timeout_n": sum(1 for d in ds if is_timeout(d)), "death_med": med(deaths),
            "death_bins": [sum(1 for t in deaths if lo <= t < hi) for lo, hi in ((0, 240), (240, 420), (420, 600), (600, 9999))],
            "errs": sum(1 for r in recs if r.get("script_errors"))}


def pair_win(r0, r1):
    a = {wkey(r): r["data"] for r in r0 if "data" in r}
    b = {wkey(r): r["data"] for r in r1 if "data" in r}
    ks = sorted(set(a) & set(b))
    l2w = sum(1 for k in ks if not a[k].get("win") and b[k].get("win"))
    w2l = sum(1 for k in ks if a[k].get("win") and not b[k].get("win"))
    n = l2w + w2l
    # 符号检验（双侧，二项 0.5）
    p = 1.0
    if n:
        kk = min(l2w, w2l)
        p = min(1.0, 2 * sum(math.comb(n, i) for i in range(kk + 1)) / 2 ** n)
    return {"pairs": len(ks), "l2w": l2w, "w2l": w2l, "p": p}


def pct(x):
    return "—" if x != x else "%.0f%%" % (100 * x)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--diag0", required=True)
    ap.add_argument("--diag1", required=True)
    ap.add_argument("--win", default="", help="逗号分隔 4 个 glob：m0 关, m0 开, m18 关, m18 开")
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    s0, s1 = diag_side(a.diag0), diag_side(a.diag1)
    keys = sorted(set(s0) & set(s1))
    tides = sorted({k[2] for k in keys})
    res = {"pairs": len(keys), "diag": {}, "minute": {}, "per_op": {}, "win": {}}
    md = ["## 诊断批跑（%d 对：20 名队长 × 种子 × 潮位，机器人 normal，--nodeath）" % len(keys), "",
          "| 潮位 | 开关 | 5–9 分钟清怪比 中位 | 清怪比 < 1 的局·分钟 | 终结技占普通怪伤害 | 终结技占普通怪击杀 | 同屏清空秒数 中位 | 打掉最终 Boss | 局长 中位 |",
          "|---|---|---|---|---|---|---|---|---|"]
    for t in tides:
        for nm, sd in (("0（关）", s0), ("1（开）", s1)):
            d = summarize_diag(sd, keys, t)
            res["diag"]["%d_%s" % (t, nm[0])] = d
            md.append("| %d | %s | %.2f | %s | %s | %s | %.1f | %s | %s |" % (t, nm, d["clear_med"], pct(d["clear_lt1"]), pct(d["ult_dmg"]), pct(d["ult_kill"]), d["ttc_med"], pct(d["win"]), d["t_med"]))
    md += ["", "### 逐分钟清怪比中位（关 → 开）", "", "| 分钟 | " + " | ".join("潮位 %d" % t for t in tides) + " |", "|---|" + "---|" * len(tides)]
    bm = {t: (by_minute(s0, keys, t), by_minute(s1, keys, t)) for t in tides}
    res["minute"] = {t: {m: [med(bm[t][0].get(m, {"cr": []})["cr"]), med(bm[t][1].get(m, {"cr": []})["cr"]),
                             med(bm[t][0].get(m, {"ttc": []})["ttc"]), med(bm[t][1].get(m, {"ttc": []})["ttc"])] for m in range(0, 13)} for t in tides}
    for m in range(1, 11):
        md.append("| %d | " % m + " | ".join("%.2f → %.2f" % (res["minute"][t][m][0], res["minute"][t][m][1]) for t in tides) + " |")
    for t in tides:
        po = per_op(s0, s1, keys, t)
        res["per_op"][t] = po
    md += ["", "### 按队长（5–9 分钟清怪比中位 / 终结技击杀占比，关 → 开）", "", "| 队长 | " + " | ".join("潮位 %d 清怪比 | 潮位 %d 终结技击杀" % (t, t) for t in tides) + " |",
           "|---|" + "---|---|" * len(tides)]
    for i, r in enumerate(res["per_op"][tides[0]]):
        cells = []
        for t in tides:
            q = res["per_op"][t][i]
            cells.append("%.2f → %.2f | %s → %s" % (q["cr0"], q["cr1"], pct(q["uk0"]), pct(q["uk1"])))
        md.append("| %s | %s |" % (r["op"], " | ".join(cells)))
    if a.win:
        gl = a.win.split(",")
        md += ["", "## 胜率（expert，starts 7 编队 × 4 seed × 安慰剂 3 份，每组 84 局）", "",
               "| 档 | 开关 | 胜率 | 安慰剂 0 / 1 / 2 | 局长 中位 | 胜局用时 中位 | 死亡 / 超时 | 死亡时刻 中位 | 死亡 0–4 / 4–7 / 7–10 / 10+ 分钟 | 配对 负转胜 / 胜转负（p） | 窗口 |",
               "|---|---|---|---|---|---|---|---|---|---|---|"]
        for i, (tier, win) in enumerate((("m0", "45–55"), ("m18", "65–75"))):
            if 2 * i + 1 >= len(gl):
                break
            r0, r1 = load_win(gl[2 * i]), load_win(gl[2 * i + 1])
            if not r0 or not r1:
                continue
            w0, w1 = summarize_win(r0), summarize_win(r1)
            pw = pair_win(r0, r1)
            res["win"][tier] = {"off": w0, "on": w1, "pair": pw}
            for nm, w in (("关", w0), ("开", w1)):
                md.append("| %s | %s | **%s** | %s | %s | %s | %d / %d | %s | %s | %s | %s |" % (
                    tier, nm, pct(w["win"]), " / ".join("%.1f" % (100 * v) for v in w["pl"].values()), w["t_med"], w["t_win_med"],
                    w["death_n"], w["timeout_n"], w["death_med"], " / ".join(str(x) for x in w["death_bins"]),
                    ("%d / %d（%.3f）" % (pw["l2w"], pw["w2l"], pw["p"])) if nm == "开" else "", win))
    open(os.path.join(a.out, "ab.md"), "w", encoding="utf-8").write("\n".join(md) + "\n")
    json.dump(res, open(os.path.join(a.out, "ab.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1, default=str)
    plots(res, tides, a.out)
    print("\n".join(md))


def plots(res, tides, out):
    try:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
        from matplotlib import font_manager
    except ImportError:
        print("没有 matplotlib，跳过画图")
        return
    for f in ("Noto Sans CJK SC", "Noto Sans CJK JP", "WenQuanYi Zen Hei", "SimHei", "Microsoft YaHei"):
        if any(f in x.name for x in font_manager.fontManager.ttflist):
            plt.rcParams["font.sans-serif"] = [f]
            break
    plt.rcParams["axes.unicode_minus"] = False
    ms = list(range(1, 11))
    fig, axs = plt.subplots(1, 2, figsize=(12, 4.2))
    for ax, idx, title in ((axs[0], 0, "清怪比中位（非终结技伤害 ÷ 新刷怪生命）"), (axs[1], 2, "同屏清空秒数中位（不靠终结技）")):
        for t, c in zip(tides, ("#3b7dd8", "#d8543b")):
            mm = res["minute"][t]
            ax.plot(ms, [mm[m][idx] for m in ms], "--", color=c, label="潮位 %d 关" % t)
            ax.plot(ms, [mm[m][idx + 1] for m in ms], "-", color=c, lw=2, label="潮位 %d 开" % t)
        if idx == 0:
            ax.axhline(1.0, color="#888", lw=0.8)
        ax.axvspan(5, 9, color="#999", alpha=0.08)
        ax.set_xlabel("分钟")
        ax.set_title(title)
        ax.legend(fontsize=8)
    fig.tight_layout()
    fig.savefig(os.path.join(out, "clear_ratio_ab.png"), dpi=110)
    plt.close(fig)
    # 按队长终结技击杀占比
    fig, ax = plt.subplots(figsize=(13, 4.2))
    t = tides[-1]
    po = sorted(res["per_op"][t], key=lambda r: -(r["uk0"] if r["uk0"] == r["uk0"] else 0))
    x = range(len(po))
    ax.bar([i - 0.2 for i in x], [100 * r["uk0"] for r in po], width=0.4, label="关", color="#9aa7b8")
    ax.bar([i + 0.2 for i in x], [100 * r["uk1"] for r in po], width=0.4, label="开", color="#d8543b")
    ax.axhline(10, color="#555", lw=0.8, ls=":")
    ax.set_xticks(list(x))
    ax.set_xticklabels([r["op"] for r in po], rotation=40, ha="right", fontsize=8)
    ax.set_ylabel("%")
    ax.set_title("潮位 %d：5–9 分钟普通怪击杀里终结技的占比（按开局队长）" % t)
    ax.legend()
    fig.tight_layout()
    fig.savefig(os.path.join(out, "ult_kill_ab.png"), dpi=110)
    plt.close(fig)


if __name__ == "__main__":
    main()
