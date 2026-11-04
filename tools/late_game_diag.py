#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""后期诊断批跑（docs/243，只读遥测 --diagbins）：20 名干员各当一次队长 × 种子 × 潮位，机器人 normal、--nodeath 打到终局。

用法（仓库根目录）：
    python tools/late_game_diag.py run  --seeds 11,23 --tides 0,10 --jobs 4 --out build/late_diag/raw.jsonl
    python tools/late_game_diag.py sum  --inp build/late_diag/raw.jsonl --out docs/assets/late_game_diag
run 每局一行 {op, seed, tide, rec}（rec = BALANCE 记录，含 diag 分桶）；sum 出按分钟汇总的 CSV + 图。
"""
import argparse, json, os, sys, threading
from concurrent.futures import ThreadPoolExecutor

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import godot_runner as GR
from balance_run import OPS

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GAME = os.path.join(ROOT, "game")
CATS = ["basic", "S1", "S2", "S3", "talent", "route", "ult", "combo", "relic", "summon", "support", "other", "S?"]
CAT_ZH = {"basic": "普攻", "S1": "技能1", "S2": "技能2", "S3": "技能3", "talent": "天赋", "route": "分支", "ult": "终结技",
          "combo": "连携", "relic": "藏品", "summon": "召唤物", "support": "支援", "other": "其他", "S?": "技能?"}


EXTRA = []   # run --squad / --relics 透传（召唤物专项，docs/243 §5）


def run_one(godot, op, seed, tide):
    args = [godot, "--headless", "--path", GAME, "--", "--balance", "--seed=%d" % seed, "--tide=%d" % tide,
            "--op=" + op, "--nodeath", "--diagbins"] + EXTRA
    out, err, _ = GR.run_godot(args, 1800)
    errs = GR.script_errors(out, err)
    rec = None
    for ln in out.splitlines():
        if ln.startswith("BALANCE "):
            rec = json.loads(ln[8:])
    return {"op": op, "seed": seed, "tide": tide, "errs": errs[:5], "rec": rec}


def cmd_run(a):
    godot = GR.find_godot()
    GR.ensure_imported(GAME)
    jobs = [(o, s, t) for t in a.tides for s in a.seeds for o in (a.ops or OPS)]
    done = set()
    if os.path.exists(a.out):
        for ln in open(a.out, encoding="utf-8"):
            r = json.loads(ln)
            if r.get("rec"):
                done.add((r["op"], r["seed"], r["tide"]))
    jobs = [j for j in jobs if j not in done]
    os.makedirs(os.path.dirname(a.out) or ".", exist_ok=True)
    lock = threading.Lock()
    n = [0]

    def work(j):
        r = run_one(godot, *j)
        with lock:
            with open(a.out, "a", encoding="utf-8") as f:
                f.write(json.dumps(r, ensure_ascii=False) + "\n")
            n[0] += 1
            rec = r["rec"] or {}
            print("[%d/%d] %s s%d tide%d t=%s win=%s errs=%d" % (n[0], len(jobs), j[0], j[1], j[2], rec.get("t"), rec.get("win"), len(r["errs"])), flush=True)

    with ThreadPoolExecutor(a.jobs) as ex:
        list(ex.map(work, jobs))


def load(path):
    rs = []
    for ln in open(path, encoding="utf-8"):
        r = json.loads(ln)
        if r.get("rec") and r["rec"].get("diag"):
            rs.append(r)
    return rs


def per_min(rec):
    """30 秒桶两两合成 1 分钟：返回 [{m, dmg, dmg_nb, kill, ns, na, hps, sp_hp, sp_n, lv, squad}]"""
    out = {}
    for b in rec["diag"]:
        m = int(b["t"] // 60)
        o = out.setdefault(m, {"m": m, "dmg": {}, "dmg_nb": {}, "kill": {}, "ns_sum": 0, "ns": 0, "na_sum": 0, "hps_sum": 0, "sp_hp": 0, "sp_n": 0,
                                "ns_pk": 0, "lv": 0, "squad": 0, "secs": 0})
        for k in ("dmg", "dmg_nb", "kill"):
            for c, v in b[k].items():
                o[k][c] = o[k].get(c, 0) + v
        for k in ("ns_sum", "ns", "na_sum", "hps_sum", "sp_hp", "sp_n"):
            o[k] += b[k]
        o["ns_pk"] = max(o["ns_pk"], b["ns_pk"])
        o["lv"] = max(o["lv"], b["lv"])
        o["squad"] = max(o["squad"], b["squad"])
    return [out[k] for k in sorted(out)]


def _sh(d, keys):
    t = sum(d.values()) or 1
    return sum(d.get(k, 0) for k in keys) / t


def cmd_sum(a):
    import csv, statistics as st
    rs = load(a.inp)
    os.makedirs(a.out, exist_ok=True)
    rows = []   # 每局每分钟一行
    for r in rs:
        for m in per_min(r["rec"]):
            n = max(1, m["ns"])
            nb = sum(m["dmg_nb"].values())
            nb_nu = nb - m["dmg_nb"].get("ult", 0)
            row = {"op": r["op"], "seed": r["seed"], "tide": r["tide"], "m": m["m"], "lv": m["lv"], "squad": m["squad"],
                   "ns": m["ns_sum"] / n, "ns_pk": m["ns_pk"], "na": m["na_sum"] / n, "hp_screen": m["hps_sum"] / n,
                   "sp_hp_s": m["sp_hp"] / 60.0, "sp_n": m["sp_n"], "dps_all": sum(m["dmg"].values()) / 60.0,
                   "dps_nb": nb / 60.0, "dps_nb_noult": nb_nu / 60.0,
                   "kills": sum(m["kill"].values())}
            row["clear_r"] = nb_nu / m["sp_hp"] if m["sp_hp"] > 0 else None       # 非终结技对普通怪的伤害 / 新刷怪生命
            row["ttc_screen"] = row["hp_screen"] / row["dps_nb_noult"] if row["dps_nb_noult"] > 0 else None   # 不靠终结技清掉同屏怪群要几秒
            for c in CATS:
                row["dnb_" + c] = m["dmg_nb"].get(c, 0)
                row["d_" + c] = m["dmg"].get(c, 0)
                row["k_" + c] = m["kill"].get(c, 0)
            rows.append(row)
    keys = list(rows[0].keys())
    with open(os.path.join(a.out, "per_run_minute.csv"), "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, keys)
        w.writeheader()
        for row in rows:
            w.writerow({k: (round(v, 3) if isinstance(v, float) else v) for k, v in row.items()})
    # 按潮位 × 分钟汇总（各局求和再算占比；比值取中位）
    agg = {}
    for row in rows:
        k = (row["tide"], row["m"])
        agg.setdefault(k, []).append(row)
    lines = []
    summ = {}
    for (tide, m), L in sorted(agg.items()):
        dnb = {c: sum(x["dnb_" + c] for x in L) for c in CATS}
        da = {c: sum(x["d_" + c] for x in L) for c in CATS}
        kk = {c: sum(x["k_" + c] for x in L) for c in CATS}
        cr = [x["clear_r"] for x in L if x["clear_r"] is not None]
        tc = [x["ttc_screen"] for x in L if x["ttc_screen"] is not None]
        e = {"tide": tide, "m": m, "runs": len(L), "lv": st.mean(x["lv"] for x in L), "ns": st.mean(x["ns"] for x in L),
             "ns_pk": st.mean(x["ns_pk"] for x in L), "na": st.mean(x["na"] for x in L),
             "hp_screen": st.mean(x["hp_screen"] for x in L), "sp_hp_s": st.mean(x["sp_hp_s"] for x in L),
             "dps_nb_noult": st.mean(x["dps_nb_noult"] for x in L), "clear_r_med": st.median(cr) if cr else 0,
             "clear_r_lt1": sum(1 for v in cr if v < 1.0) / max(1, len(cr)), "ttc_med": st.median(tc) if tc else 0}
        for c in CATS:
            e["shnb_" + c] = dnb[c] / max(1, sum(dnb.values()))
            e["sha_" + c] = da[c] / max(1, sum(da.values()))
            e["shk_" + c] = kk[c] / max(1, sum(kk.values()))
        summ[(tide, m)] = e
        lines.append(e)
    with open(os.path.join(a.out, "tide_minute.csv"), "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, list(lines[0].keys()))
        w.writeheader()
        for e in lines:
            w.writerow({k: (round(v, 4) if isinstance(v, float) else v) for k, v in e.items()})
    # 每名干员：后期（6–10 分钟、不含最终 Boss）终结技占普通怪击杀 / 伤害的比例；清怪比值首次 < 1 的分钟
    ops = {}
    for row in rows:
        ops.setdefault((row["op"], row["tide"]), []).append(row)
    oprows = []
    for (op, tide), L in sorted(ops.items()):
        late = [x for x in L if 6 <= x["m"] <= 9]
        k = sum(x["kills"] for x in late) or 1
        d = sum(x["dps_nb"] for x in late) or 1
        first = None
        for seed in sorted(set(x["seed"] for x in L)):
            S = sorted([x for x in L if x["seed"] == seed], key=lambda x: x["m"])
            for i in range(len(S) - 1):
                if S[i]["m"] >= 2 and S[i]["clear_r"] is not None and S[i]["clear_r"] < 1.0 and (S[i + 1]["clear_r"] or 0) < 1.0:
                    first = S[i]["m"] if first is None else min(first, S[i]["m"])
                    break
        oprows.append({"op": op, "tide": tide, "ult_kill_6_9": sum(x["k_ult"] for x in late) / k,
                       "ult_dmg_6_9": sum(x["dnb_ult"] for x in late) / 60.0 / d,
                       "basic_skill_kill_6_9": sum(x["k_basic"] + x["k_S1"] + x["k_S2"] + x["k_S3"] for x in late) / k,
                       "clear_r_6_9": st.median([x["clear_r"] for x in late if x["clear_r"] is not None] or [0]),
                       "first_behind_m": first})
    with open(os.path.join(a.out, "per_op.csv"), "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, list(oprows[0].keys()))
        w.writeheader()
        for e in oprows:
            w.writerow({k: (round(v, 4) if isinstance(v, float) else v) for k, v in e.items()})
    json.dump({"runs": len(rs), "wins": sum(1 for r in rs if r["rec"]["win"]), "ult_n": [r["rec"].get("ult", {}).get("ult") for r in rs],
               "ult_times": {"%s_%d_%d" % (r["op"], r["seed"], r["tide"]): r["rec"].get("ult", {}).get("ult_times") for r in rs},
               "end_t": {"%s_%d_%d" % (r["op"], r["seed"], r["tide"]): r["rec"]["t"] for r in rs}},
              open(os.path.join(a.out, "runs_meta.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=0)
    plots(a.out, summ, oprows)
    print("runs", len(rs))


def plots(out, summ, oprows):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    plt.rcParams["font.sans-serif"] = ["WenQuanYi Zen Hei"]
    plt.rcParams["axes.unicode_minus"] = False
    show = ["basic", "S1", "S2", "S3", "talent", "route", "summon", "combo", "relic", "ult"]
    cols = ["#8a8f98", "#4c78a8", "#72b7b2", "#54a24b", "#b7a3d4", "#9d755d", "#eeca3b", "#ff9da6", "#bab0ac", "#e45756"]
    tides = sorted(set(k[0] for k in summ))
    fig, axs = plt.subplots(2, len(tides), figsize=(6.5 * len(tides), 7.5), squeeze=False)
    for j, tide in enumerate(tides):
        ms = sorted(m for (t, m) in summ if t == tide)
        for i, (pre, title) in enumerate([("shnb_", "对普通怪的伤害占比"), ("shk_", "击杀占比")]):
            ax = axs[i][j]
            ys = [[summ[(tide, m)][pre + c] * 100 for m in ms] for c in show]
            ax.stackplot(ms, ys, labels=[CAT_ZH[c] for c in show], colors=cols)
            ax.set_title("潮位 %d · %s（20 名队长 × 2 种子）" % (tide, title))
            ax.set_xlabel("分钟")
            ax.set_ylabel("%")
            ax.set_ylim(0, 100)
            ax.axvline(10, color="k", lw=0.8, ls="--")
    axs[0][0].legend(loc="upper left", fontsize=7, ncol=2)
    fig.tight_layout()
    fig.savefig(os.path.join(out, "share_by_minute.png"), dpi=110)
    plt.close(fig)
    fig, axs = plt.subplots(1, 2, figsize=(13, 4.2))
    for tide in tides:
        ms = sorted(m for (t, m) in summ if t == tide)
        axs[0].plot(ms, [summ[(tide, m)]["clear_r_med"] for m in ms], marker="o", label="潮位 %d 清怪比（中位）" % tide)
        axs[1].plot(ms, [summ[(tide, m)]["ns"] for m in ms], marker="o", label="潮位 %d 同屏敌人（均）" % tide)
        axs[1].plot(ms, [summ[(tide, m)]["na"] for m in ms], ls="--", label="潮位 %d 全场存活（均）" % tide)
    axs[0].axhline(1.0, color="k", lw=0.8)
    axs[0].set_title("非终结技对普通怪伤害 ÷ 新刷怪生命（< 1 = 清不过来）")
    axs[1].set_title("敌人数量")
    for ax in axs:
        ax.set_xlabel("分钟")
        ax.legend(fontsize=8)
        ax.axvline(10, color="k", lw=0.8, ls="--")
    fig.tight_layout()
    fig.savefig(os.path.join(out, "clear_ratio.png"), dpi=110)
    plt.close(fig)
    fig, ax = plt.subplots(figsize=(13, 4.2))
    o0 = sorted([r for r in oprows if r["tide"] == tides[0]], key=lambda r: -r["ult_kill_6_9"])
    names = [r["op"] for r in o0]
    x = range(len(names))
    for k, tide in enumerate(tides):
        d = {r["op"]: r for r in oprows if r["tide"] == tide}
        ax.bar([i + k * 0.4 - 0.2 for i in x], [d[n]["ult_kill_6_9"] * 100 if n in d else 0 for n in names], width=0.4, label="潮位 %d" % tide)
    ax.set_xticks(list(x))
    ax.set_xticklabels(names, rotation=40, ha="right", fontsize=8)
    ax.set_ylabel("%")
    ax.set_title("6–9 分钟普通怪击杀里终结技的占比（按开局队长）")
    ax.legend()
    fig.tight_layout()
    fig.savefig(os.path.join(out, "ult_kill_by_op.png"), dpi=110)
    plt.close(fig)


def main():
    p = argparse.ArgumentParser()
    sp = p.add_subparsers(dest="cmd")
    r = sp.add_parser("run")
    r.add_argument("--seeds", default="11,23")
    r.add_argument("--tides", default="0,10")
    r.add_argument("--ops", default="")
    r.add_argument("--jobs", type=int, default=4)
    r.add_argument("--squad", default="")
    r.add_argument("--relics", default="")
    r.add_argument("--out", default=os.path.join(ROOT, "build", "late_diag", "raw.jsonl"))
    q = sp.add_parser("sum")
    q.add_argument("--inp", default=os.path.join(ROOT, "build", "late_diag", "raw.jsonl"))
    q.add_argument("--out", default=os.path.join(ROOT, "docs", "assets", "late_game_diag"))
    a = p.parse_args()
    if a.cmd == "run":
        a.seeds = [int(x) for x in a.seeds.split(",")]
        a.tides = [int(x) for x in a.tides.split(",")]
        a.ops = [x for x in a.ops.split(",") if x]
        if a.squad:
            EXTRA.append("--squad=" + a.squad)
        if a.relics:
            EXTRA.append("--relics=" + a.relics)
        cmd_run(a)
    elif a.cmd == "sum":
        cmd_sum(a)
    else:
        p.print_help()


if __name__ == "__main__":
    main()
