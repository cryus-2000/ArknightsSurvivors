#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""单人局胜率批跑（docs/247）：20 名干员各当一次队长 × 种子 × 潮位，机器人 normal，两组对照：
  squad = 普通策略（入队邀请接受、照常招募）；solo = --bot_solo=1（邀请一律婉拒、不选招募卡、不进强制招募画面）。
可再加一组 A/B（--groups solo,solo_buff --buff "--bal=段/键=值"）测补偿开关。

用法（仓库根目录）：
    python tools/solo_carry_batch.py run --seeds 11,23 --tides 0,10 --groups squad,solo --jobs 4 --out build/solo_carry/raw.jsonl
    python tools/solo_carry_batch.py sum --inp build/solo_carry/raw.jsonl [--md docs/assets/solo_carry/summary.md]
run 每局一行 {op, seed, tide, group, rec}；已有的 (op, seed, tide, group) 跳过（断点续跑）。
"""
import argparse, json, os, sys, threading, statistics
from concurrent.futures import ThreadPoolExecutor

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import godot_runner as GR
from balance_run import OPS

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GAME = os.path.join(ROOT, "game")
GROUP_ARGS = {"squad": ["--offerlog"], "solo": ["--bot_solo=1"]}   # --offerlog 只往 BALANCE 多写邀请记录，不影响玩法
BUFF = []   # run --buff：solo_buff 组额外参数


def group_args(g):
    if g == "solo_buff":
        return ["--bot_solo=1"] + BUFF
    if g == "squad_buff":
        return list(BUFF)
    return GROUP_ARGS[g]


def run_one(godot, op, seed, tide, group, bot):
    args = [godot, "--headless", "--path", GAME, "--", "--balance", "--seed=%d" % seed, "--tide=%d" % tide,
            "--op=" + op, "--bot=" + bot] + group_args(group)
    out, err, _ = GR.run_godot(args, 2400)
    errs = GR.script_errors(out, err)
    rec = None
    for ln in out.splitlines():
        if ln.startswith("BALANCE "):
            rec = json.loads(ln[8:])
    if rec:
        # 只留汇总要用的字段（原始 BALANCE 每局 100+ KB）
        b = rec.get("bot", {}) or {}
        rec = {k: rec.get(k) for k in ["t", "win", "lv", "lv_times", "squad", "ops", "bosses", "boss_hp", "elite_stage", "elites", "kills", "ending", "maxhp", "offers", "recruit_offers"]} | {
            "elite_t": b.get("elite_t", {}), "boss_seen": [{"type": x.get("type"), "t0": x.get("t0"), "t1": x.get("t1")} for x in b.get("bosses", [])],
            "curve": [{"t": c.get("t"), "elites": c.get("elites"), "hp": c.get("hp"), "mhp": c.get("mhp"), "rg": c.get("rg"), "squad": c.get("squad")} for c in b.get("curve", [])]}
    return {"op": op, "seed": seed, "tide": tide, "group": group, "errs": errs[:5], "rec": rec}


def cmd_run(a):
    global BUFF
    BUFF = a.buff.split() if a.buff else []
    godot = GR.find_godot()
    GR.ensure_imported(GAME)
    ops = a.ops.split(",") if a.ops else OPS
    jobs = [(o, s, t, g) for g in a.groups for t in a.tides for s in a.seeds for o in ops]
    done = set()
    if os.path.exists(a.out):
        for ln in open(a.out, encoding="utf-8"):
            r = json.loads(ln)
            if r.get("rec"):
                done.add((r["op"], r["seed"], r["tide"], r["group"]))
    jobs = [j for j in jobs if j not in done]
    os.makedirs(os.path.dirname(a.out) or ".", exist_ok=True)
    lock = threading.Lock()
    n = [0]

    def work(j):
        r = run_one(godot, *j, a.bot)
        with lock:
            with open(a.out, "a", encoding="utf-8") as f:
                f.write(json.dumps(r, ensure_ascii=False) + "\n")
            n[0] += 1
            rec = r["rec"] or {}
            print("[%d/%d] %s s%d t%d %s → t=%s win=%s lv=%s squad=%s%s" % (n[0], len(jobs), j[0], j[1], j[2], j[3], rec.get("t"), rec.get("win"), rec.get("lv"),
                  len(rec.get("squad") or []), (" ERR " + r["errs"][0][:80]) if r["errs"] else ""), flush=True)

    with ThreadPoolExecutor(a.jobs) as ex:
        list(ex.map(work, jobs))


FINAL_T = 590   # 最终 Boss 10:00 登场（bot.bosses 的 t0 = 600）


def final_info(rec):
    fin = [b for b in rec.get("boss_seen", []) if (b.get("t0") or 0) >= FINAL_T]
    reached = bool(fin) or (rec.get("t") or 0) >= 600
    killed = bool(rec.get("win")) or any((b.get("t1") or -1) >= 0 for b in fin)
    return reached, killed


def stats(rows):
    if not rows:
        return {}
    recs = [r["rec"] for r in rows]
    wins = [1 if x.get("win") else 0 for x in recs]
    deaths = [x["t"] for x in recs if not x.get("win")]
    fi = [final_info(x) for x in recs]
    e1 = [x["elite_t"].get("%s:1" % r["op"]) for r, x in zip(rows, recs)]
    e2 = [x["elite_t"].get("%s:2" % r["op"]) for r, x in zip(rows, recs)]
    el = [c["elites"] for x in recs for c in x.get("curve", []) if c.get("elites") is not None]
    solo_pure = sum(1 for x in recs if len(x.get("squad") or []) == 1)
    return {
        "n": len(recs), "win": 100.0 * sum(wins) / len(recs),
        "death_med": statistics.median(deaths) if deaths else None, "death_mean": statistics.mean(deaths) if deaths else None,
        "reach_final": 100.0 * sum(1 for f in fi if f[0]) / len(recs), "kill_final": 100.0 * sum(1 for f in fi if f[1]) / len(recs),
        "lv": statistics.mean([x.get("lv") or 0 for x in recs]),
        "e1": statistics.median([v for v in e1 if v is not None]) if any(v is not None for v in e1) else None,
        "e1_n": sum(1 for v in e1 if v is not None), "e2": statistics.median([v for v in e2 if v is not None]) if any(v is not None for v in e2) else None,
        "e2_n": sum(1 for v in e2 if v is not None),
        "elites_alive": statistics.mean(el) if el else None,
        "squad_size": statistics.mean([len(x.get("squad") or []) for x in recs]), "pure_solo": solo_pure,
        "declines": sum(sum(1 for o in (x.get("offers") or []) if o[3] == "decline") for x in recs),
    }


def mmss(v):
    return "—" if v is None else "%d:%02d" % (int(v) // 60, int(v) % 60)


def cmd_sum(a):
    rows = [json.loads(l) for l in open(a.inp, encoding="utf-8")]
    rows = [r for r in rows if r.get("rec")]
    errs = sum(1 for r in rows if r.get("errs"))
    groups = sorted({r["group"] for r in rows}, key=lambda g: ["squad", "solo", "solo_buff", "squad_buff"].index(g) if g in ["squad", "solo", "solo_buff", "squad_buff"] else 9)
    tides = sorted({r["tide"] for r in rows})
    L = ["局数 %d（脚本错误局 %d）" % (len(rows), errs), ""]
    L.append("| 组 | 潮位 | 局数 | 胜率 | 死亡时刻 中位 / 均值 | 打到最终 Boss | 打掉最终 Boss | 平均等级 | 队长精一 / 精二 中位（达成局） | 场上精英怪均值 | 平均编队人数 | 纯单人局 | 婉拒次数 |")
    L.append("|---|---|---|---|---|---|---|---|---|---|---|---|---|")
    for g in groups:
        for t in tides + ["all"]:
            sub = [r for r in rows if r["group"] == g and (t == "all" or r["tide"] == t)]
            s = stats(sub)
            if not s:
                continue
            L.append("| %s | %s | %d | %.1f%% | %s / %s | %.1f%% | %.1f%% | %.1f | %s（%d）/ %s（%d） | %s | %.2f | %d | %d |" % (
                g, t, s["n"], s["win"], mmss(s["death_med"]), mmss(s["death_mean"]), s["reach_final"], s["kill_final"], s["lv"],
                mmss(s["e1"]), s["e1_n"], mmss(s["e2"]), s["e2_n"], "%.2f" % s["elites_alive"] if s["elites_alive"] is not None else "—",
                s["squad_size"], s["pure_solo"], s["declines"]))
    L += ["", "按队长（%s 局 / 格，胜局数 / 局数，括号内为平均存活秒数）" % ("、".join("潮位 %s" % t for t in tides)), ""]
    L.append("| 队长 | " + " | ".join(groups) + " | 差（%s − %s，胜率点） |" % (groups[1] if len(groups) > 1 else "", groups[0]))
    L.append("|---|" + "---|" * len(groups) + "---|")
    ops = sorted({r["op"] for r in rows}, key=lambda o: OPS.index(o) if o in OPS else 99)
    for o in ops:
        cells = []
        wr = []
        for g in groups:
            sub = [r for r in rows if r["group"] == g and r["op"] == o]
            w = sum(1 for r in sub if r["rec"].get("win"))
            cells.append("%d/%d（%d）" % (w, len(sub), statistics.mean([r["rec"]["t"] for r in sub])) if sub else "—")
            wr.append(100.0 * w / len(sub) if sub else 0.0)
        L.append("| %s | %s | %+.0f |" % (o, " | ".join(cells), (wr[1] - wr[0]) if len(wr) > 1 else 0))
    txt = "\n".join(L)
    print(txt)
    if a.md:
        os.makedirs(os.path.dirname(a.md) or ".", exist_ok=True)
        open(a.md, "w", encoding="utf-8").write(txt + "\n")


def main():
    ap = argparse.ArgumentParser()
    sp = ap.add_subparsers(dest="cmd", required=True)
    r = sp.add_parser("run")
    r.add_argument("--seeds", type=lambda s: [int(x) for x in s.split(",")], default=[11, 23])
    r.add_argument("--tides", type=lambda s: [int(x) for x in s.split(",")], default=[0, 10])
    r.add_argument("--groups", type=lambda s: s.split(","), default=["squad", "solo"])
    r.add_argument("--ops", default="")
    r.add_argument("--bot", default="normal")
    r.add_argument("--buff", default="", help="solo_buff / squad_buff 组的额外游戏参数，例如 \"--bal=squad/solo_buff=1\"")
    r.add_argument("--jobs", type=int, default=GR.MAX_PROCS)
    r.add_argument("--out", default=os.path.join(ROOT, "build", "solo_carry", "raw.jsonl"))
    s = sp.add_parser("sum")
    s.add_argument("--inp", default=os.path.join(ROOT, "build", "solo_carry", "raw.jsonl"))
    s.add_argument("--md", default="")
    a = ap.parse_args()
    cmd_run(a) if a.cmd == "run" else cmd_sum(a)


if __name__ == "__main__":
    main()
