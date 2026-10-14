#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""干员木桩表（docs/79，制作人 10-12）：自动生成的理论数值对照表。

对每名干员（game/data/characters/*.json）× 精英阶段 0 / 1 / 2 × 场景（单体木桩 / 怪群）× 身份（主控 / 队友），
无头跑 tests/op_dummy_test.tscn 一次（热身 20 秒 + 统计 60 秒），汇总成
    build/op_dummy/table.md   按职业分组的表格：各列中位数、每人相对中位数的百分比，偏离 ±30% 的格子标出
    build/op_dummy/table.json 每局原始记录

用法（仓库根目录）：
    python tools/op_dummy_table.py                    # 全部 18 人 × 3 阶段 × 2 场景 × 2 身份 = 216 局
    python tools/op_dummy_table.py --ops wisadel,saria --stages 2
    python tools/op_dummy_table.py --secs 60 --warm 20 --jobs 4
    python tools/op_dummy_table.py --report-only     # 不跑，只用上次的 table.json 重出 table.md

并行数最多 4（另受全机上限 GODOT_MAX_PROCS 约束，经 tools/godot_runner.py 启动）；全部 --headless、静音、临时用户目录。
"""
import argparse, datetime, glob, json, os, re, statistics, subprocess, sys, time
from concurrent.futures import ThreadPoolExecutor

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import godot_runner as GR

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GAME = os.path.join(ROOT, "game")
OUT = os.path.join(ROOT, "build", "op_dummy")
BASELINE = "hoshiguma"       # 队友身份时的固定主控（技力压 0、不放技能）
BASELINE_ALT = "saria"       # 测星熊自己当队友时换成塞雷娅
CLASS_ORDER = ["先锋", "近卫", "重装", "狙击", "术师", "医疗", "辅助", "特种"]
FLAG = 0.30
SCENES = ["single", "horde"]
ROLES = ["leader", "mate"]
SCENE_NAME = {"single": "木桩", "horde": "怪群"}
ROLE_NAME = {"leader": "主控", "mate": "队友"}


def op_defs():
    out = {}
    for p in sorted(glob.glob(os.path.join(GAME, "data", "characters", "*.json"))):
        d = json.load(open(p, encoding="utf-8"))
        out[d.get("id", os.path.splitext(os.path.basename(p))[0])] = {"name": d.get("name", ""), "cls": d.get("class", "")}
    return out


BAL = []   # --bal 段/键=值：透传给游戏（同 check.py / balance_run --extra 的 --bal=），对照旋钮用


def run_one(godot, op, stage, scene, role, secs, warm, timeout):
    leader = op if role == "leader" else (BASELINE_ALT if op == BASELINE else BASELINE)
    args = [godot, "--headless", "--path", GAME, "res://tests/op_dummy_test.tscn", "--",
            "--balance", "--bot=afk", "--nodeath", "--seed=1", "--op=" + leader]
    if role == "mate":
        args.append("--squad=" + op)
    args += ["--dummy_op=" + op, "--dummy_role=" + role, "--dummy_scene=" + scene, "--dummy_stage=%d" % stage,
             "--dummy_secs=%g" % secs, "--dummy_warm=%g" % warm] + ["--bal=" + b for b in BAL]
    t0 = time.time()
    out, err, to = GR.run_godot(args, timeout)
    errs = GR.script_errors(out, err)
    m = re.search(r"^DUMMY (\{.*\})\s*$", out, re.M)
    rec = json.loads(m.group(1)) if m else None
    key = "%s_e%d_%s_%s" % (op, stage, scene, role)
    log = os.path.join(OUT, "logs", key + ".log")
    with open(log, "w", encoding="utf-8") as fh:
        fh.write("# %s\n# %s\n# %.0f 秒%s\n\n## stdout\n%s\n\n## stderr\n%s\n" % (key, " ".join(args[1:]), time.time() - t0, "（超时）" if to else "", out, err))
    return {"key": key, "op": op, "stage": stage, "scene": scene, "role": role, "ok": rec is not None and not errs and not to,
            "errors": errs[:3] + (["超时"] if to else []) + ([] if rec else ["没有 DUMMY 行"]), "data": rec, "log": log}


# ---------------------------------------------------------------- 汇总

def _median(vals):
    vals = [v for v in vals if v is not None]
    return statistics.median(vals) if vals else None


def _cell(v, med, fmt="%.0f", nonzero=False):
    """数值 + 相对中位数百分比；偏离 ±30% 加粗并标 ▲ / ▼。nonzero：0 显示为 —（治疗 / 护盾这类多数人没有的列）"""
    if v is None:
        return "—"
    if nonzero and v <= 0:
        return "—"
    s = fmt % v
    if med is None or med <= 0:
        return s
    r = v / med - 1.0
    tag = "%+.0f%%" % (r * 100)
    if r > FLAG:
        return "**%s (%s ▲)**" % (s, tag)
    if r < -FLAG:
        return "**%s (%s ▼)**" % (s, tag)
    return "%s (%s)" % (s, tag)


def _order(ids, defs):
    def k(o):
        c = defs[o]["cls"]
        return (CLASS_ORDER.index(c) if c in CLASS_ORDER else 99, o)
    return sorted(ids, key=k)


def build_report(results, defs, meta):
    by = {}
    for r in results:
        if r.get("data"):
            by[(r["op"], r["stage"], r["scene"], r["role"])] = r["data"]
    ids = _order(sorted({r["op"] for r in results}), defs)
    stages = sorted({r["stage"] for r in results})
    g = lambda op, st, sc, ro, k: (by.get((op, st, sc, ro)) or {}).get(k)
    L = []
    L.append("# 干员木桩表（理论预算）")
    L.append("")
    L.append("生成：%s · 提交 %s · 统计 %g 秒（热身 %g 秒）· 种子 1 · 口径见 docs/79_op_dummy_table.md" % (meta["time"], meta["commit"], meta["secs"], meta["warm"]))
    L.append("")
    L.append("- 手动技能按**就绪即放**（机器人缺省是保命型时机，这里取上限）；主控生命恒压 60%、灯火 100，无藏品、不升级。")
    L.append("- 队友身份：主控固定为星熊（测星熊时换塞雷娅），主控技力压 0 不放技能，只统计被测干员。")
    L.append("- 百分比 = 相对该列 18 人中位数；**加粗 ▲ / ▼** = 偏离超过 ±30%。治疗 / 护盾列只在有该能力的干员之间取中位数，没有的记 —。")
    L.append("- 怪群：主控周围持续补满 30 只普通近战怪（每只 400 生命）；「怪群在场均值」接近 30 = 没被打空，明显偏低 = 补怪速度成了上限、怪群秒伤被低估。")
    L.append("- 精英阶段：E0 = 0 个成长节点，E1 = 推进到精一（3 个节点），E2 = 整条成长线（6 个节点）；精英化节点有选项时取第一个。")
    fails = [r for r in results if not r["ok"]]
    if fails:
        L.append("")
        L.append("**有 %d 局没跑成**：%s" % (len(fails), "、".join("%s（%s）" % (r["key"], (r["errors"] or ["?"])[0][:60]) for r in fails[:12])))
    # ---------------- 摘要
    L.append("")
    L.append("## 摘要（E2）")
    L.append("")
    st_sum = max(stages)
    L.append("| 职业 | 木桩秒伤（主控）最高 | 最低 | 怪群秒伤（主控）最高 | 最低 | 治疗 / 秒 最高 |")
    L.append("|---|---|---|---|---|---|")
    for c in CLASS_ORDER:
        mem = [o for o in ids if defs[o]["cls"] == c]
        if not mem:
            continue
        def ext(sc, k="dps"):
            vals = [(g(o, st_sum, sc, "leader", k), o) for o in mem if g(o, st_sum, sc, "leader", k) is not None]
            if not vals:
                return ("—", "—")
            hi, lo = max(vals), min(vals)
            f = lambda t: "%s %.0f" % (defs[t[1]]["name"], t[0])
            return (f(hi), f(lo) if len(vals) > 1 else "—")
        hv = [(g(o, st_sum, "single", "leader", "hps") or 0, o) for o in mem]
        hv = [x for x in hv if x[0] > 0]
        hs = "%s %.1f" % (defs[max(hv)[1]]["name"], max(hv)[0]) if hv else "—"
        a, b = ext("single")
        c2, d2 = ext("horde")
        L.append("| %s | %s | %s | %s | %s | %s |" % (c, a, b, c2, d2, hs))
    # ---------------- 每阶段主表
    cols = [("木桩·主控 秒伤", "single", "leader", "dps", "%.0f", False),
            ("木桩·队友 秒伤", "single", "mate", "dps", "%.0f", False),
            ("怪群·主控 秒伤", "horde", "leader", "dps", "%.0f", False),
            ("怪群·队友 秒伤", "horde", "mate", "dps", "%.0f", False),
            ("怪群·主控 击杀", "horde", "leader", "op_kills", "%.0f", False),
            ("怪群·队友 击杀", "horde", "mate", "op_kills", "%.0f", False),
            ("治疗/秒（木桩·主控）", "single", "leader", "hps", "%.1f", True),
            ("治疗/秒（木桩·队友）", "single", "mate", "hps", "%.1f", True),
            ("护盾/秒（木桩·主控）", "single", "leader", "shield_ps", "%.1f", True),
            ("怪群在场均值（主控）", "horde", "leader", "horde_alive", "%.1f", False)]
    flagged = []
    for st in stages:
        L.append("")
        L.append("## E%d · 输出 / 治疗" % st)
        L.append("")
        L.append("| 职业 | 干员 | " + " | ".join(c[0] for c in cols) + " |")
        L.append("|---|---|" + "---|" * len(cols))
        meds = []
        for name, sc, ro, k, fmt, nz in cols:
            vals = [g(o, st, sc, ro, k) for o in ids]
            if nz:
                vals = [v for v in vals if v is not None and v > 0]
            meds.append(_median(vals))
        for o in ids:
            cells = []
            for (name, sc, ro, k, fmt, nz), med in zip(cols, meds):
                v = g(o, st, sc, ro, k)
                cells.append(_cell(v, med, fmt, nz))
                if v is not None and med and med > 0 and not (nz and v <= 0) and abs(v / med - 1.0) > FLAG:
                    flagged.append((st, defs[o]["cls"], defs[o]["name"], name, v, med, v / med - 1.0))
            L.append("| %s | %s | %s |" % (defs[o]["cls"], defs[o]["name"], " | ".join(cells)))
        L.append("| | **中位数** | %s |" % " | ".join(("—" if m is None else (c[4] % m)) for c, m in zip(cols, meds)))
        # 拆分：木桩主控的 普攻 / 技能 / 召唤 / 其他（天赋、分支）占比
        L.append("")
        L.append("E%d 木桩秒伤拆分（主控 / 队友，普攻 · 技能 · 召唤 · 天赋与分支；括号内为技能发动次数）：" % st)
        L.append("")
        L.append("| 职业 | 干员 | 主控 普攻 | 技能 | 召唤 | 其他 | 队友 普攻 | 技能 | 召唤 | 其他 |")
        L.append("|---|---|---|---|---|---|---|---|---|---|")
        for o in ids:
            row = []
            for ro in ROLES:
                d = by.get((o, st, "single", ro))
                if not d:
                    row += ["—"] * 4
                    continue
                row += ["%.0f" % d["dps_basic"], "%.0f (%d)" % (d["dps_skill"], d["casts"]), "%.0f" % d["dps_summon"], "%.0f" % d["dps_other"]]
            L.append("| %s | %s | %s |" % (defs[o]["cls"], defs[o]["name"], " | ".join(row)))
    # ---------------- 基础属性
    L.append("")
    L.append("## 基础属性（运行时读取）")
    L.append("")
    L.append("主控层（生命 / 物理减伤 / 法抗 / 回复 / 移速 / 闪避）取该干员当主控、单人编队时的博士属性；攻击力系数等取被测干员作用域。"
             "普攻命中间隔 = 统计期 ÷ 普攻在木桩上造成伤害的帧数（实测，一帧 0.066 秒；持续型普攻会贴近 0.066）。")
    L.append("")
    st_b = min(stages)
    hdr = ["生命", "物理减伤", "法抗", "回复/秒", "移速", "闪避", "普攻间隔 E%d（秒）" % st_b, "普攻间隔 E%d" % max(stages),
           "攻击系数 E%d" % max(stages), "攻速系数 E%d" % max(stages), "范围系数 E%d" % max(stages), "技力 S1/S2/S3"]
    L.append("| 职业 | 干员 | " + " | ".join(hdr) + " |")
    L.append("|---|---|" + "---|" * len(hdr))
    bcols = ["max_hp", "armor", "arts_res", "regen", "speed", "dodge"]
    bmed = {k: _median([g(o, st_b, "single", "leader", k) for o in ids]) for k in bcols}
    imed0 = _median([v for v in (g(o, st_b, "single", "leader", "basic_interval") for o in ids) if v and v > 0])
    imed2 = _median([v for v in (g(o, max(stages), "single", "leader", "basic_interval") for o in ids) if v and v > 0])
    for o in ids:
        d0 = by.get((o, st_b, "single", "leader")) or {}
        d2 = by.get((o, max(stages), "single", "leader")) or {}
        cells = [_cell(d0.get("max_hp"), bmed["max_hp"], "%.0f"), _cell(d0.get("armor"), bmed["armor"], "%.2f"),
                 _cell(d0.get("arts_res"), bmed["arts_res"], "%.2f"), "%.2f" % d0["regen"] if d0 else "—",
                 _cell(d0.get("speed"), bmed["speed"], "%.0f"), "%.2f" % d0["dodge"] if d0 else "—"]
        iv0, iv2 = d0.get("basic_interval", -1), d2.get("basic_interval", -1)
        cells.append(_cell(iv0, imed0, "%.2f") if iv0 and iv0 > 0 else "—")
        cells.append(_cell(iv2, imed2, "%.2f") if iv2 and iv2 > 0 else "—")
        cells += ["%.2f" % d2.get("op_atk", 0) if d2 else "—", "%.2f" % d2.get("op_aspd", 0) if d2 else "—",
                  "%.2f" % d2.get("op_range", 0) if d2 else "—",
                  "/".join("%g" % x for x in d2.get("sp_need", [])) if d2 else "—"]
        L.append("| %s | %s | %s |" % (defs[o]["cls"], defs[o]["name"], " | ".join(cells)))
    # ---------------- 偏离清单
    L.append("")
    L.append("## 偏离 ±30% 的格子（输出 / 治疗表）")
    L.append("")
    if not flagged:
        L.append("没有。")
    else:
        L.append("| 阶段 | 职业 | 干员 | 列 | 值 | 中位数 | 偏离 |")
        L.append("|---|---|---|---|---|---|---|")
        for st, c, n, col, v, med, r in sorted(flagged, key=lambda x: (x[0], x[3], -abs(x[6]))):
            L.append("| E%d | %s | %s | %s | %.1f | %.1f | %+.0f%% |" % (st, c, n, col, v, med, r * 100))
    L.append("")
    L.append("## 局限")
    L.append("")
    L.append("木桩不反映生存（主控生命被压住、不会倒下）、走位（主控站桩，冲刺 / 位移型干员的真实落点不同）、机器人的技能时机与选卡，"
             "也没有藏品与博士被动。它只回答「同样条件下谁的理论输出 / 治疗预算偏高偏低」，调数值前看它，定数值仍以机器人批跑胜率为准（docs/79 §4）。")
    return "\n".join(L) + "\n", flagged


def main():
    global OUT
    ap = argparse.ArgumentParser(description="干员木桩表（docs/79）")
    ap.add_argument("--ops", default="", help="逗号分隔干员 id（缺省全部）")
    ap.add_argument("--stages", default="0,1,2")
    ap.add_argument("--scenes", default="single,horde")
    ap.add_argument("--roles", default="leader,mate")
    ap.add_argument("--secs", type=float, default=60.0)
    ap.add_argument("--warm", type=float, default=20.0)
    ap.add_argument("--jobs", type=int, default=4, help="并行数（最多 4）")
    ap.add_argument("--timeout", type=int, default=600)
    ap.add_argument("--out", default=OUT)
    ap.add_argument("--report-only", action="store_true")
    ap.add_argument("--bal", action="append", default=[], metavar="段/键=值", help="透传 --bal=（可多次），例如 --bal enemy/density=1")
    a = ap.parse_args()
    OUT = a.out
    BAL[:] = a.bal
    os.makedirs(os.path.join(OUT, "logs"), exist_ok=True)
    defs = op_defs()
    jpath = os.path.join(OUT, "table.json")
    try:
        commit = subprocess.run(["git", "-C", ROOT, "rev-parse", "--short", "HEAD"], capture_output=True, text=True).stdout.strip()
    except OSError:
        commit = "?"
    if a.report_only:
        prev = json.load(open(jpath, encoding="utf-8"))
        results, meta = prev["results"], prev["meta"]
    else:
        ids = [x for x in a.ops.split(",") if x] or list(defs)
        bad = [x for x in ids if x not in defs]
        if bad:
            sys.exit("没有这些干员：" + ",".join(bad))
        godot = GR.find_godot()
        GR.ensure_imported(GAME)
        jobs = [(o, int(s), sc, ro) for o in ids for s in a.stages.split(",") for sc in a.scenes.split(",") for ro in a.roles.split(",")]
        n = max(1, min(4, a.jobs))
        print("木桩表：%d 局，并行 %d（全机上限 %d）；输出 %s" % (len(jobs), n, GR.MAX_PROCS, OUT), flush=True)
        t0 = time.time()
        done = [0]

        def one(j):
            r = run_one(godot, j[0], j[1], j[2], j[3], a.secs, a.warm, a.timeout)
            done[0] += 1
            d = r.get("data") or {}
            print("[%3d/%d] %-34s %s dps=%s kills=%s hps=%s" % (done[0], len(jobs), r["key"], "通过" if r["ok"] else "失败 " + "; ".join(r["errors"])[:120],
                                                                d.get("dps", "—"), d.get("op_kills", "—"), d.get("hps", "—")), flush=True)
            return r

        with ThreadPoolExecutor(n) as ex:
            results = list(ex.map(one, jobs))
        meta = {"time": datetime.datetime.now().strftime("%Y-%m-%d %H:%M"), "commit": commit, "secs": a.secs, "warm": a.warm,
                "baseline": BASELINE, "baseline_alt": BASELINE_ALT, "bal": list(BAL), "elapsed_s": round(time.time() - t0)}
        json.dump({"meta": meta, "results": results}, open(jpath, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    md, flagged = build_report(results, defs, meta)
    open(os.path.join(OUT, "table.md"), "w", encoding="utf-8").write(md)
    nfail = sum(1 for r in results if not r["ok"])
    print("完成：%d 局，失败 %d；偏离 ±30%% 的格子 %d 个；%s" % (len(results), nfail, len(flagged), os.path.join(OUT, "table.md")))
    return 1 if nfail else 0


if __name__ == "__main__":
    sys.exit(main())
