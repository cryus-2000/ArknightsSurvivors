#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Boss 单场测试台（docs/170）：不跑满整局，用「正常编队打到该 Boss 时」的队伍快照直接开打 Boss。

三步：
    # 1. 录快照（在基线提交上跑一次就行）：高手机器人正常跑局（--nodeath 保证每个 seed 都能走到 10:00），
    #    每只 Boss 登场那一刻写一份快照 <开局>_m<认知>_s<seed>_slot<1|2|3>.json；BENCHREAL（真实局这场的结果）存 record.json
    python tools/boss_bench.py record --ops wisadel,skadi,kaltsit --metas 0,18 --seeds 1-16 --out build/boss_bench/snaps
    # 2. 开打：每只 Boss × 对应登场位的全部快照，各跑一局（--game 指向别的工作树的 game/ 做对照）
    python tools/boss_bench.py run --snaps build/boss_bench/snaps --bosses all --tag base --out build/boss_bench/res
    # 3. 出表（一份 = 单表；两份 = 对照 vs 改版）
    python tools/boss_bench.py table build/boss_bench/res/base.json build/boss_bench/res/new.json

登场位：塑路者 / 圣徒卡门 = 3:30（slot1，第一只中期 Boss 只从这两只里抽）；圣徒伊比利亚 / 接潮组 = 7:00（slot2）；
最终 Boss（偏执泡影 / 骑士 / 伊莎玛拉 / 伊祖米克）= 10:00（slot3）。--slot 可强制改。
同 seed 可复现：快照里存了 g.rng 状态，测试台局的随机数从登场那一刻接着走。
"""
import argparse, json, os, re, statistics, sys, time
from concurrent.futures import ThreadPoolExecutor

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import godot_runner as GR

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GAME = os.path.join(ROOT, "game")

# Boss 键 → (刷出的种类, 缺省登场位, 中文名)
BOSSES = {
    "path": (["path"], 1, "塑路者"),
    "carmen": (["carmen"], 1, "圣徒卡门"),
    "iberia": (["iberia"], 2, "圣徒伊比利亚"),
    "bishop+archon": (["bishop", "archon"], 2, "接潮组（主教+执政官）"),
    "bishop+immortal": (["bishop", "immortal"], 2, "接潮组（主教+斥亡者）"),
    "paranoia": (["paranoia"], 3, "偏执泡影"),
    "knight_boss": (["knight_boss"], 3, "最后的骑士"),
    "ishar": (["ishar"], 3, "伊莎玛拉"),
    "izumik": (["izumik"], 3, "伊祖米克"),
}


def seeds_of(spec):
    out = []
    for part in str(spec).split(","):
        if "-" in part:
            a, b = part.split("-")
            out += list(range(int(a), int(b) + 1))
        elif part:
            out.append(int(part))
    return out


def run(args, timeout):
    out, err, to = GR.run_godot(args, timeout)
    return out, err, to


def cmd_record(a):
    game = os.path.abspath(a.game)
    GR.ensure_imported(game)
    os.makedirs(a.out, exist_ok=True)
    jobs = []
    for op in a.ops.split(","):
        for m in [int(x) for x in a.metas.split(",")]:
            for s in seeds_of(a.seeds):
                jobs.append((op, m, s))

    def one(j):
        op, m, s = j
        prefix = os.path.abspath(os.path.join(a.out, "%s_m%d_s%d" % (op, m, s)))
        args = [GR.find_godot(), "--headless", "--path", game, "--", "--balance", "--seed=%d" % s, "--op=" + op, "--bot=" + a.bot,
                "--tide=%d" % a.tide, "--meta=%d" % m, "--nodeath", "--benchsnap=" + prefix, "--maxt=%d" % a.maxt] + a.extra
        t0 = time.time()
        out, err, to = run(args, a.timeout)
        real = [json.loads(l[10:]) for l in out.splitlines() if l.startswith("BENCHREAL ")]
        bal = re.search(r"^BALANCE (\{.*\})\s*$", out, re.M)
        errs = GR.script_errors(out, err)
        rec = {"op": op, "meta": m, "seed": s, "wall": round(time.time() - t0, 1), "real": real, "timeout": to,
               "snaps": [l for l in out.splitlines() if l.startswith("BENCHSNAP ")], "script_errors": len(errs), "first_error": errs[0][:300] if errs else ""}
        if bal:
            d = json.loads(bal.group(1))
            rec["run_t"] = d.get("t")
            rec["floor_hits"] = d.get("floor_hits")
        print("%-10s m%-2d s%-3d %5.0fs  snaps=%d real=%s%s" % (op, m, s, rec["wall"], len(rec["snaps"]),
              ",".join("%s:%s/%.0fs" % (r["boss"], r["result"], r["fight_t"]) for r in real), "  错误 %d" % len(errs) if errs else ""), flush=True)
        return rec

    with ThreadPoolExecutor(max_workers=a.jobs) as ex:
        recs = list(ex.map(one, jobs))
    with open(os.path.join(a.out, "record.json"), "w", encoding="utf-8") as f:
        json.dump(recs, f, ensure_ascii=False, indent=1)
    print("快照目录：%s（%d 局）" % (a.out, len(recs)))


def cmd_run(a):
    game = os.path.abspath(a.game)
    GR.ensure_imported(game)
    keys = list(BOSSES) if a.bosses == "all" else a.bosses.split(",")
    snaps = sorted(f for f in os.listdir(a.snaps) if f.endswith(".json") and "_slot" in f)
    metas = set(int(x) for x in a.metas.split(",")) if a.metas else None
    ops = set(a.ops.split(",")) if a.ops else None
    jobs = []
    for k in keys:
        grp, slot, _ = BOSSES[k]
        slot = a.slot or slot
        for f in snaps:
            m = re.match(r"(.+)_m(\d+)_s(\d+)_slot(\d)\.json$", f)
            if not m or int(m.group(4)) != slot:
                continue
            if metas is not None and int(m.group(2)) not in metas:
                continue
            if ops is not None and m.group(1) not in ops:
                continue
            if a.max_seed and int(m.group(3)) > a.max_seed:
                continue
            jobs.append((k, grp, os.path.abspath(os.path.join(a.snaps, f)), m.group(1), int(m.group(2)), int(m.group(3))))

    def one(j):
        k, grp, path, op, meta, seed = j
        snap = json.load(open(path, encoding="utf-8"))
        args = [GR.find_godot(), "--headless", "--path", game, "--", "--balance"] + snap["args"] + [
            "--bossbench=" + path, "--benchboss=" + "+".join(grp), "--benchmaxt=%d" % a.maxt] + a.extra
        t0 = time.time()
        out, err, to = run(args, a.timeout)
        mm = re.search(r"^BENCH (\{.*\})\s*$", out, re.M)
        errs = GR.script_errors(out, err)
        rec = {"boss": k, "op": op, "meta": meta, "seed": seed, "wall": round(time.time() - t0, 1), "script_errors": len(errs),
               "first_error": errs[0][:300] if errs else ""}
        if mm:
            rec.update(json.loads(mm.group(1)))
        else:
            rec["error"] = "timeout" if to else "no BENCH line"
            rec["tail"] = out[-800:]
        print("%-16s %-10s m%-2d s%-3d %4.0fs  %s" % (k, op, meta, seed, rec["wall"],
              ("%s %.0fs 承伤%.0f%% 破绽输出%.0f%%" % (rec["result"], rec["fight_t"], rec["taken_pct"] * 100, rec["brk_dmg_share"] * 100)) if mm else rec["error"]), flush=True)
        return rec

    print("%d 局（%s）" % (len(jobs), ", ".join(keys)), flush=True)
    with ThreadPoolExecutor(max_workers=a.jobs) as ex:
        recs = list(ex.map(one, jobs))
    os.makedirs(a.out, exist_ok=True)
    path = os.path.join(a.out, a.tag + ".json")
    with open(path, "w", encoding="utf-8") as f:
        json.dump({"tag": a.tag, "game": game, "records": recs}, f, ensure_ascii=False, indent=1)
    md = table([path])
    with open(os.path.join(a.out, a.tag + ".md"), "w", encoding="utf-8") as f:
        f.write(md)
    print(md)


def _agg(rs):
    ok = [r for r in rs if "result" in r]
    if not ok:
        return None
    n = len(ok)
    med = lambda xs: statistics.median(xs) if xs else 0.0
    wins = [r for r in ok if r["win"]]
    return {"n": n, "err": len(rs) - n, "win": len(wins) / n,
            "dead": sum(r["result"] == "dead" for r in ok) / n, "timeout": sum(r["result"] == "timeout" for r in ok) / n,
            "t_win": med([r["fight_t"] for r in wins]), "t_all": med([r["fight_t"] for r in ok]),
            "taken": statistics.mean(r["taken_pct"] for r in ok), "boss_left": statistics.mean(r["boss_hp_left"] for r in ok),
            "brk_dmg": statistics.mean(r["brk_dmg_share"] for r in ok), "brk_t": statistics.mean(r["brk_time_share"] for r in ok),
            "fp": sum(1 for r in ok if r.get("fp_diff")), "se": sum(1 for r in rs if r.get("script_errors"))}


def table(paths):
    data = [json.load(open(p, encoding="utf-8")) for p in paths]
    tags = [d["tag"] for d in data]
    L = ["# Boss 单场测试台结果（%s）" % " vs ".join(tags), "",
         "胜率 = 打死该 Boss（最终 Boss = 进入胜利）；超时 = 登场后 %s 秒没打死；承伤 = 队长掉血 / 最大生命；破绽输出 = 打在破绽（break_t 或 Boss 受伤倍率 > 1）上的伤害占比；"
         "破绽时间 = 有破绽的时间占比；用时取中位（胜局 / 全部）。fp = 还原后与快照不一致的局数，se = 有脚本错误的局数。" % "N", ""]
    hdr = "| Boss | 认知 | 版本 | 局数 | 胜率 | 阵亡 | 超时 | 胜局用时 | 全部用时 | 承伤 | Boss 余血 | 破绽输出 | 破绽时间 | fp/se |"
    L += [hdr, "|" + "---|" * 14]
    keys = []
    for d in data:
        for r in d["records"]:
            if r["boss"] not in keys:
                keys.append(r["boss"])
    metas = sorted({r["meta"] for d in data for r in d["records"]})
    for k in keys:
        for m in metas + ["全部"]:
            for d in data:
                rs = [r for r in d["records"] if r["boss"] == k and (m == "全部" or r["meta"] == m)]
                s = _agg(rs)
                if s is None:
                    continue
                L.append("| %s | %s | %s | %d | **%.0f%%** | %.0f%% | %.0f%% | %.0f | %.0f | %.0f%% | %.0f%% | %.0f%% | %.0f%% | %d/%d |" % (
                    BOSSES.get(k, (0, 0, k))[2], m, d["tag"], s["n"], s["win"] * 100, s["dead"] * 100, s["timeout"] * 100, s["t_win"], s["t_all"],
                    s["taken"] * 100, s["boss_left"] * 100, s["brk_dmg"] * 100, s["brk_t"] * 100, s["fp"], s["se"]))
    if len(data) == 2:
        L += ["", "## 改版 − 对照（同快照配对）", "", "| Boss | 认知 | 配对 | 胜率差 | 两边都胜的用时差（中位） | 承伤差 | 破绽输出差 |", "|---|---|---|---|---|---|---|"]
        for k in keys:
            for m in metas + ["全部"]:
                A = {(r["op"], r["meta"], r["seed"]): r for r in data[0]["records"] if r["boss"] == k and "result" in r and (m == "全部" or r["meta"] == m)}
                B = {(r["op"], r["meta"], r["seed"]): r for r in data[1]["records"] if r["boss"] == k and "result" in r and (m == "全部" or r["meta"] == m)}
                ks = sorted(set(A) & set(B))
                if not ks:
                    continue
                dw = (sum(B[x]["win"] for x in ks) - sum(A[x]["win"] for x in ks)) / len(ks)
                both = [B[x]["fight_t"] - A[x]["fight_t"] for x in ks if A[x]["win"] and B[x]["win"]]
                dt = statistics.mean(B[x]["taken_pct"] - A[x]["taken_pct"] for x in ks)
                db = statistics.mean(B[x]["brk_dmg_share"] - A[x]["brk_dmg_share"] for x in ks)
                L.append("| %s | %s | %d | %+.0f 点 | %s | %+.0f 点 | %+.0f 点 |" % (BOSSES.get(k, (0, 0, k))[2], m, len(ks), dw * 100,
                         ("%+.0f 秒" % statistics.median(both)) if both else "-", dt * 100, db * 100))
    return "\n".join(L) + "\n"


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    r = sub.add_parser("record")
    r.add_argument("--ops", default="wisadel,skadi,kaltsit")
    r.add_argument("--metas", default="0,18")
    r.add_argument("--seeds", default="1-16")
    r.add_argument("--bot", default="expert")
    r.add_argument("--tide", type=int, default=0)
    r.add_argument("--maxt", type=int, default=790)
    r.add_argument("--out", default=os.path.join(ROOT, "build", "boss_bench", "snaps"))
    r.add_argument("--game", default=GAME)
    r.add_argument("--jobs", type=int, default=max(1, (os.cpu_count() or 2) - 1))
    r.add_argument("--timeout", type=int, default=1800)
    r.add_argument("--extra", nargs="*", action="extend", default=[])
    b = sub.add_parser("run")
    b.add_argument("--snaps", default=os.path.join(ROOT, "build", "boss_bench", "snaps"))
    b.add_argument("--bosses", default="all")
    b.add_argument("--slot", type=int, default=0)
    b.add_argument("--metas", default="")
    b.add_argument("--ops", default="")
    b.add_argument("--max-seed", type=int, default=0)
    b.add_argument("--maxt", type=int, default=180)
    b.add_argument("--tag", required=True)
    b.add_argument("--out", default=os.path.join(ROOT, "build", "boss_bench", "res"))
    b.add_argument("--game", default=GAME)
    b.add_argument("--jobs", type=int, default=max(1, (os.cpu_count() or 2) - 1))
    b.add_argument("--timeout", type=int, default=900)
    b.add_argument("--extra", nargs="*", action="extend", default=[])
    t = sub.add_parser("table")
    t.add_argument("paths", nargs="+")
    a = ap.parse_args()
    if a.cmd == "record":
        cmd_record(a)
    elif a.cmd == "run":
        cmd_run(a)
    else:
        print(table(a.paths))


if __name__ == "__main__":
    main()
