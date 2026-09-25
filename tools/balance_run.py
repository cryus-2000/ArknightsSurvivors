#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""平衡批跑器（docs/27 §6）：并行跑多组 `--balance` 模拟，汇总 BALANCE JSON 成表。

用法（在仓库根目录）：
    python tools/balance_run.py                       # 默认矩阵：8 名干员单人开局 × 3 seed
    python tools/balance_run.py --preset squads       # 预设编队矩阵
    python tools/balance_run.py --op wisadel --seeds 5
    python tools/balance_run.py --squad wisadel,suzuran,saria --seeds 3 --diff 0
    python tools/balance_run.py --preset solo --jobs 8 --tag after_nerf

输出：build/balance/<tag>_<时间>.json（原始）与同名 .md（汇总表）；终端打印汇总表。
指标：胜率、存活时间、等级里程碑（2:00 / 5:00 / 8:00）、最终 Boss 剩余、伤害占比（按干员 / 来源）、
      精英化时间、灯火、死因（承伤最大的来源）。
"""
import argparse, json, os, re, subprocess, sys, time, datetime, statistics, itertools
from concurrent.futures import ThreadPoolExecutor

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GAME = os.path.join(ROOT, "game")
OPS = ["mizuki", "wisadel", "eyjafjalla", "kaltsit", "saria", "siege", "skadi", "suzuran"]
PRESETS = {
    "solo": [[o] for o in OPS],
    "squads": [
        ["wisadel", "suzuran", "saria"],     # 远程输出 + 辅助 + 护盾
        ["mizuki", "kaltsit", "siege"],      # 近战 + 医疗 + 节奏
        ["eyjafjalla", "skadi", "saria"],    # 法术 AoE + 近卫 + 重装
        ["skadi", "siege", "kaltsit"],       # 纯近战
        ["wisadel", "eyjafjalla", "suzuran"],# 纯远程
        ["mizuki", "saria", "suzuran"],      # 水月 + 双辅助
    ],
    "pairs": [list(p) for p in itertools.combinations(OPS, 2)],
}


def find_godot():
    import shutil
    for c in [os.environ.get("GODOT"), "godot", "godot4",
              r"E:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe"]:
        if not c:
            continue
        if os.path.exists(c):
            return c
        if os.sep not in c and shutil.which(c):
            return shutil.which(c)
    sys.exit("找不到 Godot，请设置环境变量 GODOT")


def run_one(godot, squad, seed, diff, extra, timeout):
    args = [godot, "--headless", "--path", GAME, "--", "--balance", "--seed=%d" % seed, "--diff=%d" % diff, "--op=" + squad[0]]
    if len(squad) > 1:
        args.append("--squad=" + ",".join(squad[1:]))
    args += extra
    t0 = time.time()
    try:
        p = subprocess.run(args, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=timeout)
        out = p.stdout
    except subprocess.TimeoutExpired as e:
        out = (e.stdout or b"").decode("utf-8", "replace") if isinstance(e.stdout, bytes) else (e.stdout or "")
    m = re.search(r"^BALANCE (\{.*\})\s*$", out, re.M)
    rec = {"squad": squad, "seed": seed, "diff": diff, "wall": round(time.time() - t0, 1)}
    if m:
        try:
            rec["data"] = json.loads(m.group(1))
        except json.JSONDecodeError:
            rec["error"] = "bad json"
    else:
        rec["error"] = "no BALANCE line"
        rec["tail"] = out[-600:]
    return rec


def fmt_t(sec):
    return "%d:%02d" % (int(sec) // 60, int(sec) % 60)


def summarize(records):
    """按编队分组汇总"""
    groups = {}
    for r in records:
        groups.setdefault("+".join(r["squad"]), []).append(r)
    rows = []
    for key, rs in groups.items():
        ok = [r["data"] for r in rs if "data" in r]
        if not ok:
            rows.append({"squad": key, "n": len(rs), "error": rs[0].get("error", "?")})
            continue
        wins = sum(1 for d in ok if d.get("win"))
        ts = [d["t"] for d in ok]
        lv = [d["lv"] for d in ok]
        marks = [d.get("marks", {}) for d in ok]
        def mark(k):
            v = [m.get(k) for m in marks if m.get(k) is not None]
            return statistics.mean(v) if v else 0
        boss_hp = [d.get("boss_hp", -1) for d in ok if d.get("boss_hp", -1) >= 0]
        # 伤害占比：按干员（out 的 key 是伤害来源名；hit_sources 里 op 字段无法从 JSON 反推，这里按来源名聚合）
        out_tot = {}
        for d in ok:
            tot = sum(d.get("out", {}).values()) or 1.0
            for k, v in d.get("out", {}).items():
                out_tot[k] = out_tot.get(k, 0.0) + v / tot / len(ok)
        top = sorted(out_tot.items(), key=lambda kv: -kv[1])[:6]
        dmg_in = {}
        for d in ok:
            for k, v in d.get("dmg", {}).items():
                dmg_in[k] = dmg_in.get(k, 0.0) + v
        killer = max(dmg_in.items(), key=lambda kv: kv[1])[0] if dmg_in else "-"
        elites = []
        for d in ok:
            for o in d.get("ops", []):
                elites.append((o["id"], o.get("elite", 0)))
        e2 = sum(1 for _, e in elites if e >= 2)
        rows.append({
            "squad": key, "n": len(ok), "win": wins / len(ok),
            "t_mean": statistics.mean(ts), "t_min": min(ts),
            "lv2": mark("120"), "lv5": mark("300"), "lv8": mark("480"), "lv_end": statistics.mean(lv),
            "boss_hp": statistics.mean(boss_hp) if boss_hp else None,
            "lamp": statistics.mean([d.get("lamp", 0) for d in ok]),
            "kills": statistics.mean([d.get("kills", 0) for d in ok]),
            "e2_share": e2 / max(1, len(elites)),
            "top": top, "killer": killer,
        })
    return rows


def table(rows):
    lines = ["| 编队 | n | 胜率 | 存活(均/最短) | Lv 2:00/5:00/8:00/末 | 终Boss剩余 | 精二占比 | 灯火 | 击杀 | 主要伤害来源 | 主要死因 |",
             "|---|---|---|---|---|---|---|---|---|---|---|"]
    for r in rows:
        if "error" in r:
            lines.append("| %s | %d | 失败: %s | | | | | | | | |" % (r["squad"], r["n"], r["error"]))
            continue
        top = " ".join("%s %d%%" % (k, v * 100) for k, v in r["top"][:4])
        lines.append("| %s | %d | %d%% | %s / %s | %.0f / %.0f / %.0f / %.0f | %s | %d%% | %.0f | %.0f | %s | %s |" % (
            r["squad"], r["n"], r["win"] * 100, fmt_t(r["t_mean"]), fmt_t(r["t_min"]),
            r["lv2"], r["lv5"], r["lv8"], r["lv_end"],
            ("%d%%" % (r["boss_hp"] * 100)) if r["boss_hp"] is not None else "-",
            r["e2_share"] * 100, r["lamp"], r["kills"], top, r["killer"]))
    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--preset", choices=list(PRESETS), default=None)
    ap.add_argument("--op", help="单人开局干员")
    ap.add_argument("--squad", help="逗号分隔的编队（第一个是开局干员）")
    ap.add_argument("--seeds", type=int, default=3)
    ap.add_argument("--seed0", type=int, default=1)
    ap.add_argument("--diff", type=int, default=0)
    ap.add_argument("--jobs", type=int, default=max(1, (os.cpu_count() or 4) - 1))
    ap.add_argument("--timeout", type=int, default=900)
    ap.add_argument("--tag", default="run")
    ap.add_argument("--extra", default="", help="透传给游戏的额外参数，空格分隔，例如 \"--nodeath --botrandom\"")
    a = ap.parse_args()
    if a.squad:
        squads = [a.squad.split(",")]
    elif a.op:
        squads = [[a.op]]
    else:
        squads = PRESETS[a.preset or "solo"]
    extra = a.extra.split() if a.extra else []
    godot = find_godot()
    jobs = [(s, a.seed0 + i) for s in squads for i in range(a.seeds)]
    print("跑 %d 局（%d 编队 × %d seed），并行 %d" % (len(jobs), len(squads), a.seeds, a.jobs), flush=True)
    t0 = time.time()
    with ThreadPoolExecutor(a.jobs) as ex:
        records = list(ex.map(lambda j: run_one(godot, j[0], j[1], a.diff, extra, a.timeout), jobs))
    rows = summarize(records)
    md = table(rows)
    print(md)
    print("耗时 %.0fs" % (time.time() - t0))
    outdir = os.path.join(ROOT, "build", "balance")
    os.makedirs(outdir, exist_ok=True)
    stamp = datetime.datetime.now().strftime("%m%d_%H%M")
    base = os.path.join(outdir, "%s_%s" % (a.tag, stamp))
    json.dump({"args": vars(a), "records": records}, open(base + ".json", "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    open(base + ".md", "w", encoding="utf-8").write("# balance %s %s\n\nargs: `%s`\n\n%s\n" % (a.tag, stamp, " ".join(sys.argv[1:]), md))
    print("写入", base + ".{json,md}")


if __name__ == "__main__":
    main()
