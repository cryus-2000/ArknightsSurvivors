#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""平衡批跑器（docs/27 §6）：并行跑多组 `--balance` 模拟，汇总 BALANCE JSON 成表。

用法（在仓库根目录）：
    python tools/balance_run.py                       # 默认矩阵：8 名干员单人开局 × 3 seed
    python tools/balance_run.py --preset squads       # 预设编队矩阵
    python tools/balance_run.py --op wisadel --seeds 5
    python tools/balance_run.py --squad wisadel,suzuran,saria --seeds 3 --diff 0
    python tools/balance_run.py --preset solo --jobs 8 --tag after_nerf

    python tools/balance_run.py --preset starts --bots afk,bad,normal,expert --seeds 4 --tag bots   # 四档机器人（docs/29）

输出：build/balance/<tag>_<时间>.json（原始）与同名 .md（汇总表）；终端打印汇总表。
机器人（docs/29）：--bot 选一档，--bots 逗号分隔跑多档矩阵；afk 挂机 / bad 手残 / normal 普通（缺省）/ expert 高手。
多档时额外输出「按机器人汇总」表，并对照 BOT_TARGETS 给出 达标 / 偏难 / 偏易。
指标：胜率、存活时间、等级里程碑（2:00 / 5:00 / 8:00）、最终 Boss 剩余、伤害占比（按干员 / 来源）、
      精英化时间、灯火、死因（承伤最大的来源）。
"""
import argparse, json, os, re, subprocess, sys, time, datetime, statistics, itertools
from concurrent.futures import ThreadPoolExecutor

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GAME = os.path.join(ROOT, "game")
OPS = ["mizuki", "wisadel", "eyjafjalla", "kaltsit", "saria", "siege", "skadi", "suzuran",
       "ulpianus", "irene", "specter_unchained", "logos", "lumen"]
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
    "batch2": [
        ["ulpianus", "wisadel", "saria"], ["irene", "wisadel", "saria"], ["specter_unchained", "wisadel", "saria"],
        ["logos", "wisadel", "saria"], ["lumen", "wisadel", "saria"],
        ["ulpianus", "suzuran", "kaltsit"], ["irene", "suzuran", "kaltsit"], ["specter_unchained", "suzuran", "kaltsit"],
        ["logos", "suzuran", "kaltsit"], ["lumen", "suzuran", "kaltsit"],
    ],
    "batch2solo": [["ulpianus"], ["irene"], ["specter_unchained"], ["logos"], ["lumen"], ["skadi"], ["eyjafjalla"], ["kaltsit"]],
    "b2fix": [["ulpianus"], ["specter_unchained"], ["logos"], ["lumen"]],
    "b2fix3": [["logos", "wisadel", "saria"], ["logos", "suzuran", "kaltsit"]],
    "b2fix2": [["logos", "wisadel", "saria"], ["logos", "suzuran", "kaltsit"], ["irene", "wisadel", "saria"], ["irene", "suzuran", "kaltsit"]],
    "pairs": [list(p) for p in itertools.combinations(OPS, 2)],
    # 单人开局、自然招募（真实流程）：每个职业一名代表
    "starts": [["wisadel"], ["eyjafjalla"], ["skadi"], ["mizuki"], ["saria"], ["kaltsit"], ["suzuran"]],
}

BOTS = ["afk", "bad", "normal", "expert"]
## 各档机器人的难度目标（docs/29 §3）：win 胜率区间、t 平均存活秒数区间、s330 3:30 存活率下限
BOT_TARGETS = {
    "afk":    {"win": (0.0, 0.0),   "t": (90, 300),  "s330": None, "desc": "挂机：3:30 前死；活过 5:00 说明太简单"},
    "bad":    {"win": (0.0, 0.10),  "t": (180, 480), "s330": None, "desc": "手残：第一个 Boss 前后死，偶尔撑到中后期"},
    "normal": {"win": (0.30, 0.55), "t": (420, 780), "s330": 0.9, "desc": "普通：几乎都能过 3:30，三到五成通关"},
    "expert": {"win": (0.70, 0.95), "t": (540, 780), "s330": 1.0, "desc": "高手：大多通关，但不是必胜"},
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


def run_one(godot, squad, seed, diff, extra, timeout, bot=None):
    args = [godot, "--headless", "--path", GAME, "--", "--balance", "--seed=%d" % seed, "--diff=%d" % diff, "--op=" + squad[0]]
    if bot:
        args.append("--bot=" + bot)
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
    rec = {"squad": squad, "seed": seed, "diff": diff, "bot": bot or "normal", "wall": round(time.time() - t0, 1)}
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
    """按编队（多档机器人时按 机器人 × 编队）分组汇总"""
    multi_bot = len({r.get("bot", "normal") for r in records}) > 1
    groups = {}
    for r in records:
        key = "+".join(r["squad"])
        if r.get("bot", "normal") != "normal" or multi_bot:
            key = "[%s] %s" % (r.get("bot", "normal"), key)
        groups.setdefault(key, []).append(r)
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
        # 治疗占比（BALANCE 的 heal 段：来源 → 有效治疗量），用来看医疗无人机 / 医疗干员是不是保底
        heal_tot = {}
        heal_abs = 0.0
        for d in ok:
            h = d.get("heal", {})
            tot = sum(h.values()) or 1.0
            heal_abs += sum(h.values()) / len(ok)
            for k, v in h.items():
                heal_tot[k] = heal_tot.get(k, 0.0) + v / tot / len(ok)
        heal_top = sorted(heal_tot.items(), key=lambda kv: -kv[1])[:3]
        drone_lv = statistics.mean([d.get("drone", 0) for d in ok])
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
        floor = [d.get("floor_hits", 0) for d in ok]
        rows.append({
            "squad": key, "n": len(ok), "win": wins / len(ok), "floor": statistics.mean(floor),
            "floor_first": statistics.mean([d["floor_times"][0] for d in ok if d.get("floor_times")]) if any(d.get("floor_times") for d in ok) else None,
            "t_mean": statistics.mean(ts), "t_min": min(ts),
            "lv2": mark("120"), "lv5": mark("300"), "lv8": mark("480"), "lv_end": statistics.mean(lv),
            "boss_hp": statistics.mean(boss_hp) if boss_hp else None,
            "lamp": statistics.mean([d.get("lamp", 0) for d in ok]),
            "kills": statistics.mean([d.get("kills", 0) for d in ok]),
            "e2_share": e2 / max(1, len(elites)),
            "top": top, "killer": killer,
            "heal_top": heal_top, "heal_abs": heal_abs, "drone_lv": drone_lv,
            **bot_cols(ok),
        })
    return rows


def _mean(v, default=None):
    v = [x for x in v if x is not None]
    return statistics.mean(v) if v else default


def bot_cols(ok):
    """docs/29 的机器人指标：受击频率、承伤、低血时间、死因、精英化 / 招募 / Boss 击杀节奏"""
    bs = [d.get("bot", {}) for d in ok]
    deaths = [b.get("death_src", "") for d, b in zip(ok, bs) if not d.get("win") and b.get("death_src")]
    death_mode = max(set(deaths), key=deaths.count) if deaths else "-"
    def first_elite(b, lvl):
        ts = [t for k, t in b.get("elite_t", {}).items() if k.endswith(":%d" % lvl)]
        return min(ts) if ts else None
    ttk = []
    for b in bs:
        for bo in b.get("bosses", []):
            if bo.get("t1", -1) >= 0:
                ttk.append(bo["t1"] - bo["t0"])
    bosses_killed = [sum(1 for bo in b.get("bosses", []) if bo.get("t1", -1) >= 0) for b in bs]
    rec1 = [b.get("recruit_t", [None])[0] if b.get("recruit_t") else None for b in bs]
    return {
        "s330": sum(1 for d in ok if d.get("win") or d["t"] >= 210) / len(ok),
        "s500": sum(1 for d in ok if d.get("win") or d["t"] >= 300) / len(ok),
        "hits_pm": _mean([b.get("hits_pm") for b in bs], 0), "taken_pm": _mean([b.get("taken_pm") for b in bs], 0),
        "low_hp_s": _mean([b.get("low_hp_s") for b in bs], 0), "dark_s": _mean([b.get("dark_s") for b in bs], 0),
        "death_mode": death_mode, "e1": _mean([first_elite(b, 1) for b in bs]), "e2": _mean([first_elite(b, 2) for b in bs]),
        "rec1": _mean(rec1), "boss_ttk": _mean(ttk), "bosses_killed": _mean(bosses_killed, 0),
        "still": _mean([b.get("still_pct") for b in bs], 0), "moved_pm": _mean([b.get("moved_pm") for b in bs], 0),
    }


def _ft(v):
    return fmt_t(v) if v is not None else "-"


def bot_table(rows):
    """机器人指标表（每个 机器人 × 编队 一行）"""
    lines = ["| 机器人 · 开局 | n | 胜率 | 存活 均/最短 | 3:30 存活 | 5:00 存活 | 首次招募 | 首次精一 / 精二 | 中期 Boss 击杀数 / 平均用时 | 受击/分 | 承伤/分 | 低血(<35%)秒 | 熄灯秒 | 静止% | 主要死因 |",
             "|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|"]
    for r in rows:
        if "error" in r:
            continue
        lines.append("| %s | %d | %d%% | %s / %s | %d%% | %d%% | %s | %s / %s | %.1f / %s | %.1f | %.0f | %.0f | %.0f | %.0f | %s |" % (
            r["squad"], r["n"], r["win"] * 100, fmt_t(r["t_mean"]), fmt_t(r["t_min"]), r["s330"] * 100, r["s500"] * 100,
            _ft(r["rec1"]), _ft(r["e1"]), _ft(r["e2"]), r["bosses_killed"],
            ("%ds" % r["boss_ttk"]) if r["boss_ttk"] is not None else "-",
            r["hits_pm"], r["taken_pm"], r["low_hp_s"], r["dark_s"], r["still"], r["death_mode"]))
    return "\n".join(lines)


def bot_summary(records):
    """按机器人汇总（跨所有开局），对照 BOT_TARGETS 判定"""
    by = {}
    for r in records:
        if "data" in r:
            by.setdefault(r.get("bot", "normal"), []).append(r["data"])
    lines = ["| 机器人 | 局数 | 胜率 | 平均存活 | 3:30 存活 | 平均终局等级 | 平均击杀 | 目标（胜率 / 存活） | 判定 |",
             "|---|---|---|---|---|---|---|---|---|"]
    verdicts = {}
    for bot in BOTS + sorted(set(by) - set(BOTS)):
        ds = by.get(bot)
        if not ds:
            continue
        win = sum(1 for d in ds if d.get("win")) / len(ds)
        tm = statistics.mean([d["t"] for d in ds])
        s330 = sum(1 for d in ds if d.get("win") or d["t"] >= 210) / len(ds)
        tg = BOT_TARGETS.get(bot)
        v = "-"
        if tg:
            w0, w1 = tg["win"]
            t0, t1 = tg["t"]
            if win > w1 + 1e-9 or tm > t1 + 1e-9:
                v = "偏易"
            elif win < w0 - 1e-9 or tm < t0 - 1e-9 or (tg["s330"] is not None and s330 < tg["s330"] - 1e-9):
                v = "偏难"
            else:
                v = "达标"
        verdicts[bot] = v
        tgt = ("%d–%d%% / %s–%s" % (tg["win"][0] * 100, tg["win"][1] * 100, fmt_t(tg["t"][0]), fmt_t(tg["t"][1]))) if tg else "-"
        lines.append("| %s | %d | %d%% | %s | %d%% | %.1f | %.0f | %s | **%s** |" % (
            bot, len(ds), win * 100, fmt_t(tm), s330 * 100, statistics.mean([d["lv"] for d in ds]),
            statistics.mean([d.get("kills", 0) for d in ds]), tgt, v))
    return "\n".join(lines), verdicts


def table(rows):
    lines = ["| 编队 | n | 胜率 | 存活(均/最短) | 托底(次/首次) | Lv 2:00/5:00/8:00/末 | 终Boss剩余 | 精二占比 | 灯火 | 击杀 | 主要伤害来源 | 治疗来源(总量/无人机Lv) | 主要死因 |",
             "|---|---|---|---|---|---|---|---|---|---|---|---|---|"]
    for r in rows:
        if "error" in r:
            lines.append("| %s | %d | 失败: %s | | | | | | | | | | |" % (r["squad"], r["n"], r["error"]))
            continue
        top = " ".join("%s %d%%" % (k, v * 100) for k, v in r["top"][:4])
        heal = " ".join("%s %d%%" % (k, v * 100) for k, v in r["heal_top"]) or "-"
        lines.append("| %s | %d | %d%% | %s / %s | %.1f / %s | %.0f / %.0f / %.0f / %.0f | %s | %d%% | %.0f | %.0f | %s | %s (%.0f / %.1f) | %s |" % (
            r["squad"], r["n"], r["win"] * 100, fmt_t(r["t_mean"]), fmt_t(r["t_min"]),
            r["floor"], fmt_t(r["floor_first"]) if r["floor_first"] is not None else "-",
            r["lv2"], r["lv5"], r["lv8"], r["lv_end"],
            ("%d%%" % (r["boss_hp"] * 100)) if r["boss_hp"] is not None else "-",
            r["e2_share"] * 100, r["lamp"], r["kills"], top, heal, r["heal_abs"], r["drone_lv"], r["killer"]))
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
    ap.add_argument("--bot", choices=BOTS, default=None, help="机器人档位（docs/29），缺省 normal")
    ap.add_argument("--bots", default=None, help="逗号分隔的多档机器人矩阵，例如 afk,bad,normal,expert")
    a = ap.parse_args()
    if a.squad:
        squads = [a.squad.split(",")]
    elif a.op:
        squads = [[a.op]]
    else:
        squads = PRESETS[a.preset or "solo"]
    extra = a.extra.split() if a.extra else []
    godot = find_godot()
    bots = a.bots.split(",") if a.bots else [a.bot]
    jobs = [(s, a.seed0 + i, b) for b in bots for s in squads for i in range(a.seeds)]
    print("跑 %d 局（%d 机器人 × %d 编队 × %d seed），并行 %d" % (len(jobs), len(bots), len(squads), a.seeds, a.jobs), flush=True)
    t0 = time.time()
    with ThreadPoolExecutor(a.jobs) as ex:
        records = list(ex.map(lambda j: run_one(godot, j[0], j[1], a.diff, extra, a.timeout, j[2]), jobs))
    rows = summarize(records)
    md = table(rows) + "\n\n### 机器人指标（docs/29）\n\n" + bot_table(rows)
    if len(bots) > 1:
        bs, _ = bot_summary(records)
        md = "### 按机器人汇总\n\n" + bs + "\n\n### 明细\n\n" + md
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
