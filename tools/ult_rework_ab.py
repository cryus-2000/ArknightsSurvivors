#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""终结技重新定位 A/B 汇总（docs/250）：开关 ult/rework 与各旋钮、加上 growth/late_shape 的多组对比，全部对同一组基线配对。

用法（仓库根目录）：
    python tools/ult_rework_ab.py --diag off=build/ab/diag_off.jsonl,all=build/ab/diag_all.jsonl,... \
        --win off=build/ab/win/win_m{m}_off_*.json,all=build/ab/win/win_m{m}_all_*.json,... \
        --out docs/assets/ult_rework_ab
--diag：late_game_diag.py run（--nodeath --diagbins，20 队长 × 种子 × 潮位）的输出，第一项是基线，按 (队长, 种子, 潮位) 配对；
--win：balance_run.py（expert，starts × 4 seed × 安慰剂 3 份）的输出，路径里的 {m} 换成 0 / 18，第一项是基线，按 (编队, 种子, 安慰剂) 配对。
指标：终结技次数 / 间隔 / 首次充满、终结技占普通怪伤害与击杀（5–9 分钟）、非终结技清怪比、精英存活秒数与单次被终结技打掉的比例、
      中期 Boss 战时长与单次占比、最终 Boss 击破率；胜率、死亡时刻、翻转局（符号检验）。输出 ab.md + ab.json。
"""
import argparse, glob, json, os, statistics as st, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from late_game_diag import load
from late_power_ab import run_metrics, load_win, summarize_win, pair_win, wkey, med, LATE

FINAL = {"paranoia", "izumik", "knight"}   # 最终 Boss（10:00 登场）


def q(xs, p):
    xs = sorted(x for x in xs if x is not None)
    if not xs:
        return float("nan")
    return xs[min(len(xs) - 1, int(p * len(xs)))]


def diag_side(path):
    out = {}
    for r in load(path):
        rows, agg = run_metrics(r["rec"])
        out[(r["op"], r["seed"], r["tide"])] = {"rows": rows, "agg": agg, "rec": r["rec"]}
    return out


def summarize(side, keys):
    recs = [side[k]["rec"] for k in keys]
    ult_n, iv, first, idle = [], [], [], []
    for r in recs:
        u = r.get("ult") or {}
        t = u.get("ult_times", [])
        ult_n.append(len(t))
        iv += [b - a for a, b in zip(t, t[1:])]
        if u.get("first_full", -1) >= 0:
            first.append(u["first_full"])
        idle.append(u.get("idle_full_s", 0.0))
    nb = sum(side[k]["agg"]["nb"] for k in keys)
    nbu = sum(side[k]["agg"]["nb_ult"] for k in keys)
    kk = sum(side[k]["agg"]["k"] for k in keys)
    ku = sum(side[k]["agg"]["k_ult"] for k in keys)
    crs = [row["clear_r"] for k in keys for row in side[k]["rows"] if row["m"] in LATE and row["clear_r"] is not None]
    ttc = [row["ttc"] for k in keys for row in side[k]["rows"] if row["m"] in LATE and row["ttc"] is not None]
    el = [e for r in recs for e in (r.get("diag_x") or {}).get("elites", [])]
    el_life = [e["t1"] - e["t0"] for e in el]
    el_hit = [e.get("ultm", 0.0) for e in el if e.get("ultm", 0.0) > 0]
    el_ultk = sum(1 for e in el if e.get("cat") == "ult")
    mb_t, mb_kill, mb_n, mb_m, mb_f, mb_un = [], 0, 0, [], [], []
    fb_kill, fb_n = 0, 0
    for r in recs:
        for b in (r.get("bot") or {}).get("bosses", []):
            if b["type"] in FINAL:
                fb_n += 1
                fb_kill += 1 if b.get("t1", -1) > 0 else 0
                continue
            mb_n += 1
            if b.get("t1", -1) > 0:
                mb_kill += 1
                mb_t.append(b["t1"] - b["t0"])
        for b in (r.get("diag_x") or {}).get("bosses", []):
            if b["type"] in FINAL:
                continue
            mb_m.append(b.get("ultm", 0.0))
            mb_f.append(b.get("ultf", 0.0))
            mb_un.append(b.get("ultn", 0))
    return {"runs": len(keys), "ult_n": st.mean(ult_n) if ult_n else float("nan"), "ult_iv": med(iv), "ult_first": med(first), "idle": med(idle),
            "ult_dmg": nbu / nb if nb else float("nan"), "ult_kill": ku / kk if kk else float("nan"),
            "clear_med": med(crs), "clear_lt1": sum(1 for x in crs if x < 1) / max(1, len(crs)), "ttc_med": med(ttc),
            "el_n": len(el), "el_life": med(el_life), "el_life_p75": q(el_life, 0.75), "el_hit": len(el_hit) / max(1, len(el)),
            "el_ultm_med": med(el_hit), "el_ultm_max": max(el_hit) if el_hit else 0.0, "el_ultk": el_ultk,
            "mb_n": mb_n, "mb_kill": mb_kill / max(1, mb_n), "mb_t": med(mb_t), "mb_ultm_med": med([x for x in mb_m if x > 0]),
            "mb_ultm_max": max(mb_m) if mb_m else 0.0, "mb_ultf": st.mean(mb_f) if mb_f else float("nan"),
            "mb_ultn": st.mean(mb_un) if mb_un else float("nan"), "fb_kill": fb_kill / max(1, fb_n),
            "final_win": sum(1 for r in recs if r.get("win")) / max(1, len(recs))}


def paired_clear(s0, s1, keys):
    """同一局（队长, 种子, 潮位）5–9 分钟清怪比中位数之差，返回中位差与「变好」的局数"""
    ds = []
    for k in keys:
        a = med([row["clear_r"] for row in s0[k]["rows"] if row["m"] in LATE and row["clear_r"] is not None])
        b = med([row["clear_r"] for row in s1[k]["rows"] if row["m"] in LATE and row["clear_r"] is not None])
        if a == a and b == b:
            ds.append(b - a)
    return med(ds), sum(1 for d in ds if d > 0), len(ds)


def pct(x, d=0):
    return "—" if x != x else ("%." + str(d) + "f%%") % (100 * x)


def f1(x, d=1):
    return "—" if x != x else ("%." + str(d) + "f") % x


def parse_arms(s):
    out = []
    for it in s.split(","):
        if it.strip():
            k, v = it.split("=", 1)
            out.append((k.strip(), v.strip()))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--diag", default="")
    ap.add_argument("--win", default="")
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    res = {"diag": {}, "win": {}}
    md = ["# 终结技重新定位 A/B（tools/ult_rework_ab.py 生成）", ""]
    if a.diag:
        arms = [(n, diag_side(p)) for n, p in parse_arms(a.diag) if os.path.exists(p)]
        base = arms[0][1]
        keys_all = set(base)
        for _, s in arms[1:]:
            keys_all &= set(s)
        keys_all = sorted(keys_all)
        tides = sorted({k[2] for k in keys_all})
        md += ["## 诊断批跑（normal、--nodeath 打到终局；每组 %d 局配对）" % len(keys_all), ""]
        for tide in tides + ["all"]:
            ks = [k for k in keys_all if tide == "all" or k[2] == tide]
            md += ["### 潮位 %s（%d 局）" % (tide, len(ks)), "",
                   "| 组 | 终结技 次 / 局 | 间隔中位 秒 | 首次充满 | 终结技占普通怪 伤害 / 击杀（5–9 分） | 非终结技清怪比中位（< 1 占比） | 配对清怪比差（变好局） | 同屏清空 秒 | 精英存活 中位 / P75 秒 | 精英吃终结技 / 单次中位 / 最大 | 中期 Boss 战 秒（击破率） | 中期 Boss 单次 中位 / 最大，吃几次 | 最终 Boss 击破 |",
                   "|---|---|---|---|---|---|---|---|---|---|---|---|---|"]
            for n, s in arms:
                d = summarize(s, ks)
                pc = paired_clear(base, s, ks) if s is not base else (float("nan"), 0, 0)
                res["diag"].setdefault(str(tide), {})[n] = dict(d, clear_pair=pc)
                md.append("| %s | %.2f | %s | %s | %s / %s | %.2f（%s） | %s | %s | %s / %s | %s / %s / %s | %s（%s） | %s / %s，%.1f | %s |" % (
                    n, d["ult_n"], f1(d["ult_iv"], 0), f1(d["ult_first"], 0), pct(d["ult_dmg"], 1), pct(d["ult_kill"], 1),
                    d["clear_med"], pct(d["clear_lt1"]), ("%+.3f（%d / %d）" % pc) if pc[2] else "—", f1(d["ttc_med"]),
                    f1(d["el_life"], 0), f1(d["el_life_p75"], 0), pct(d["el_hit"]), pct(d["el_ultm_med"]), pct(d["el_ultm_max"]),
                    f1(d["mb_t"], 0), pct(d["mb_kill"]), pct(d["mb_ultm_med"]), pct(d["mb_ultm_max"]), d["mb_ultn"], pct(d["final_win"])))
            md.append("")
    if a.win:
        arms = parse_arms(a.win)
        md += ["## 胜率（expert，starts 7 编队 × 4 seed × 安慰剂 3 份）", "",
               "| 档 | 组 | 局数 | 胜率 | 各实现 | 死亡 0–4 / 4–7 / 7–10 / 终局 | 超时 | 胜局时长中位 | 终结技 次 / 局 | 对基线 输→赢 / 赢→输（p） | 窗口 |",
               "|---|---|---|---|---|---|---|---|---|---|---|"]
        for tier, win in (("0", "45–55"), ("18", "65–75")):
            recs = [(n, load_win(p.replace("{m}", tier))) for n, p in arms]
            recs = [(n, r) for n, r in recs if r]
            if not recs:
                continue
            r0 = recs[0][1]
            for n, r in recs:
                w = summarize_win(r)
                un = [len((x["data"].get("ult") or {}).get("ult_times", [])) for x in r if "data" in x and isinstance(x["data"].get("ult"), dict)]
                w["ult_n"] = st.mean(un) if un else float("nan")
                pw = pair_win(r0, r) if r is not r0 else None
                res["win"].setdefault("m" + tier, {})[n] = {"sum": w, "pair": pw}
                md.append("| m%s | %s | %d | %s | %s | %s | %d | %s | %s | %s | %s |" % (
                    tier, n, w["n"], pct(w["win"], 1), " / ".join("%.0f" % (100 * v) for v in w["pl"].values()),
                    " / ".join(str(x) for x in w["death_bins"]), w["timeout_n"], f1(w["t_win_med"], 0), f1(w["ult_n"], 2),
                    ("%d / %d（%.3f）" % (pw["l2w"], pw["w2l"], pw["p"])) if pw else "—", win))
        md.append("")
    open(os.path.join(a.out, "ab.md"), "w", encoding="utf-8").write("\n".join(md) + "\n")
    json.dump(res, open(os.path.join(a.out, "ab.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1, default=str)
    print("\n".join(md))


if __name__ == "__main__":
    main()
