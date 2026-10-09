"""玩家局内数据汇总（docs/40）：读 game/scripts/run/telemetry.gd 写下的本地记录，套用 balance_run 的汇总表。

记录在哪：Godot 的用户目录下 runs/runs.jsonl，每局一行 {"schema", "meta": {版本, 提交, 平台, 时间, 种子, 难度, 地图, 开局干员, 结果}, "run": 整局记录}。
  Windows：开发试玩 %APPDATA%\\ArknightsSurvivors\\runs\\runs.jsonl；对内测试包 %APPDATA%\\ArknightsSurvivors_Internal\\runs\\runs.jsonl
  （对外包不记录；project.godot 固定了 custom_user_dir_name，没固定时是 %APPDATA%\\Godot\\app_userdata\\<项目名>）
「run」和平衡测试打印的 BALANCE 同一格式，所以胜率 / 存活 / 伤害构成 / 死因 / 藏品拿取这些表可以直接复用。

用法：
  python tools/runs_report.py                                 # 本机全部记录（开发目录 + 对内包目录，有哪个读哪个）
  python tools/runs_report.py a.jsonl b.jsonl c.jsonl         # 几位测试者发来的文件合在一起（也可 --file 多次）
  python tools/runs_report.py --since 2026-09-26              # 某天以后
  python tools/runs_report.py --commit abc1234                # 只看某个版本（改平衡前后对比）
  python tools/runs_report.py --by-file                       # 汇总表按文件（测试者）分行
  python tools/runs_report.py 某个.jsonl --out build/runs_report.md
输出：总览、按难度 × 开局干员的胜率 / 用时 / 等级、死因、Boss 用时（中期 / 最终）、等级曲线、藏品、再加逐局一行的清单。
"""
import argparse, collections, json, os, statistics, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import balance_run as BR   # noqa: E402  复用汇总表

TIER_NAMES = {0: "标准", 4: "Ⅳ", 8: "Ⅷ"}   # meta.diff 是累计档位（D.DIFFICULTY_TIERS 的 level），其余档位按数字显示
BOSS_NAMES = dict(BR.FINAL_BOSS_NAMES, **BR.MID_BOSS_NAMES)


def user_dirs():
    """本机可能有记录的 Godot user:// 目录（按 game/project.godot 推算，和游戏里一致）：
    - 开了 application/config/use_custom_user_dir：%APPDATA%\\<custom_user_dir_name>（开发试玩），以及对内包的 <名字>_Internal
    - 没开：%APPDATA%\\Godot\\app_userdata\\<config/name>"""
    pg = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "game", "project.godot")
    kv = {}
    for line in open(pg, encoding="utf-8"):
        if "=" in line and not line.startswith(("[", ";")):
            k, v = line.split("=", 1)
            kv[k.strip()] = v.strip().strip('"')
    base = os.environ.get("APPDATA") or os.path.expanduser("~/.local/share")
    if kv.get("config/use_custom_user_dir") == "true" and kv.get("config/custom_user_dir_name"):
        name = kv["config/custom_user_dir_name"]
        return [os.path.join(base, name), os.path.join(base, name + "_Internal")]
    return [os.path.join(base, "Godot", "app_userdata", kv.get("config/name", "方舟幸存者"))]


def default_files():
    return [p for p in (os.path.join(d, "runs", "runs.jsonl") for d in user_dirs()) if os.path.exists(p)]


def load(path, a):
    out = []
    for n, line in enumerate(open(path, encoding="utf-8"), 1):
        line = line.strip()
        if not line:
            continue
        try:
            rec = json.loads(line)
        except ValueError:
            print("跳过 %s 第 %d 行：不是合法 JSON" % (os.path.basename(path), n), file=sys.stderr)
            continue
        m = rec.get("meta", {})
        if a.since and m.get("time", "") < a.since:
            continue
        if a.commit and m.get("commit") != a.commit:
            continue
        if a.version and m.get("version") != a.version:
            continue
        if a.diff is not None and m.get("diff") != a.diff:
            continue
        if a.result and m.get("result") != a.result:
            continue
        rec["_file"] = os.path.splitext(os.path.basename(path))[0] if len(a.files) <= 1 else _label(path)
        out.append(rec)
    return out


def _label(path):
    """多份文件时用「上级目录/文件名」区分（测试者通常各放一个目录，或者改名成 张三.jsonl）"""
    d = os.path.basename(os.path.dirname(os.path.abspath(path)))
    return "%s/%s" % (d, os.path.splitext(os.path.basename(path))[0])


def tier(diff):
    return TIER_NAMES.get(diff, "档位 %s" % diff)


def diff_op_table(recs):
    """按难度 × 开局干员：局数、胜率、平均用时 / 最长、平均终局等级、主要死因（只计失败的局）"""
    by = collections.OrderedDict()
    for r in sorted(recs, key=lambda r: (r["meta"].get("diff", 0), r["meta"].get("start_op", ""))):
        by.setdefault((r["meta"].get("diff", 0), r["meta"].get("start_op", "?")), []).append(r)
    lines = ["| 难度 | 开局干员 | 局数 | 胜 / 负 / 退出 | 胜率 | 用时 均 / 最长 | 终局等级 均 | 主要死因 |", "|---|---|---|---|---|---|---|---|"]
    for (df, op), rs in by.items():
        res = collections.Counter(r["meta"].get("result") for r in rs)
        ts = [r["run"]["t"] for r in rs]
        lv = [r["run"]["lv"] for r in rs]
        src = collections.Counter(_death_src(r) for r in rs if r["meta"].get("result") == "dead")
        lines.append("| %s | %s | %d | %d / %d / %d | %d%% | %s / %s | %.1f | %s |" % (
            tier(df), op, len(rs), res["win"], res["dead"], res["quit"], 100 * res["win"] / len(rs),
            BR.fmt_t(statistics.mean(ts)), BR.fmt_t(max(ts)), statistics.mean(lv),
            " ".join("%s %d" % kv for kv in src.most_common(3)) or "-"))
    return "\n".join(lines)


def _death_src(r):
    b = r["run"].get("bot", {})
    return b.get("death_src") or b.get("end", {}).get("src") or "?"


def death_table(recs):
    """死因（只计失败的局）：来源、局数、平均死亡时间、Boss 在场几局、圈外几局"""
    by = {}
    for r in recs:
        if r["meta"].get("result") != "dead":
            continue
        e = r["run"].get("bot", {}).get("end", {})
        by.setdefault(_death_src(r), []).append(e)
    if not by:
        return "（没有失败的局）"
    lines = ["| 死因 | 局数 | 平均死亡时间 | 最早 | Boss 在场 | 圈外 |", "|---|---|---|---|---|---|"]
    for src, es in sorted(by.items(), key=lambda kv: -len(kv[1])):
        ts = [e.get("t", 0) for e in es]
        lines.append("| %s | %d | %s | %s | %d | %d |" % (src, len(es), BR.fmt_t(statistics.mean(ts)), BR.fmt_t(min(ts)),
                                                         sum(1 for e in es if e.get("boss")), sum(1 for e in es if e.get("zone_out"))))
    return "\n".join(lines)


def boss_table(recs):
    """Boss 用时（按类型）：出场、击杀、用时 均 / 中 / 最长（出现起算；胜利的局最终 Boss 按出现 → 通关）、未击杀的局"""
    by = {}
    for r in recs:
        d = r["run"]
        for bo in d.get("bot", {}).get("bosses", []):
            e = by.setdefault(bo.get("type", "?"), {"n": 0, "t": [], "miss": 0})
            e["n"] += 1
            t_end = bo["t1"] if bo.get("t1", -1) >= 0 else (d["t"] if d.get("win") and BR._boss_phase(bo) == 2 else None)
            if t_end is None:
                e["miss"] += 1
            else:
                e["t"].append(t_end - bo["t0"])
    if not by:
        return "（记录里没有 Boss）"
    lines = ["| Boss | 出场 | 击杀 | 用时 均 / 中 / 最长 | 未击杀（死亡或退出） |", "|---|---|---|---|---|"]
    for ty, e in sorted(by.items(), key=lambda kv: -kv[1]["n"]):
        ts = e["t"]
        lines.append("| %s | %d | %d | %s | %d |" % (BOSS_NAMES.get(ty, ty), e["n"], len(ts),
                                                    ("%ds / %ds / %ds" % (statistics.mean(ts), statistics.median(ts), max(ts))) if ts else "-", e["miss"]))
    return "\n".join(lines)


def level_curve(recs):
    """等级曲线：每 30 秒曲线的平均等级（bot.curve），按难度分行；机器人目标见 balance_run"""
    by = {}
    for r in recs:
        for c in r["run"].get("bot", {}).get("curve", []):
            by.setdefault(r["meta"].get("diff", 0), {}).setdefault(int(c.get("t", 0)), []).append(c.get("lv", 0))
    if not by:
        return ""
    cols = [60, 120, 180, 240, 300, 360, 420, 480, 540, 600]
    lines = ["| 难度 | 局数 | " + " | ".join(BR.fmt_t(t) for t in cols) + " |", "|---|---|" + "---|" * len(cols)]
    for df, pts in sorted(by.items()):
        n = len([r for r in recs if r["meta"].get("diff", 0) == df])
        lines.append("| %s | %d | " % (tier(df), n) + " | ".join(("%.1f (%d)" % (statistics.mean(pts[t]), len(pts[t]))) if pts.get(t) else "-" for t in cols) + " |")
    return "\n".join(lines) + "\n\n（括号里是该时刻还在局内的局数）"


def run_list(recs, by_file):
    head = "| 时间 (UTC) | %s开局干员 | 难度 | 结果 | 用时 | 等级 | 击杀 | 死因 / 结局 |" % ("文件 | " if by_file else "")
    lines = [head, "|" + "---|" * (head.count("|") - 1)]
    for r in sorted(recs, key=lambda r: r["meta"].get("time", "")):
        m, d = r["meta"], r["run"]
        res = {"win": "胜", "dead": "负", "quit": "退出"}.get(m.get("result"), m.get("result"))
        tail = d.get("ending") or "" if m.get("result") == "win" else (_death_src(r) if m.get("result") == "dead" else "")
        lines.append("| %s | %s%s | %s | %s | %s | %d | %d | %s |" % (
            m.get("time", "").replace("T", " "), (r["_file"] + " | ") if by_file else "", m.get("start_op", "?"), tier(m.get("diff", 0)),
            res, BR.fmt_t(d.get("t", 0)), d.get("lv", 0), d.get("kills", 0), tail))
    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("files", nargs="*", help="记录文件，可以多个（几位测试者发来的 runs.jsonl）；缺省：本机 Godot 用户目录下的 runs/runs.jsonl")
    ap.add_argument("--file", action="append", default=[], help="同上，可多次")
    ap.add_argument("--since", default=None, help="只看这个时间以后（ISO 前缀，如 2026-09-26）")
    ap.add_argument("--commit", default=None)
    ap.add_argument("--version", default=None)
    ap.add_argument("--diff", type=int, default=None, help="只看某个难度（累计档位：标准 0 / Ⅳ 4 / Ⅷ 8）")
    ap.add_argument("--result", choices=["win", "dead", "quit"], default=None)
    ap.add_argument("--by-file", action="store_true", help="balance_run 的汇总表按文件（测试者）分行，逐局清单加文件列")
    ap.add_argument("--out", default=None, help="另存为 Markdown")
    a = ap.parse_args()
    a.files = a.files + a.file or default_files()
    if not a.files:
        sys.exit("没有找到记录：%s（正常游玩一局、局内超过 20 秒后才会写入；测试者发来的文件直接当参数传）" % " / ".join(os.path.join(d, "runs", "runs.jsonl") for d in user_dirs()))
    recs = []
    for p in a.files:
        if not os.path.exists(p):
            sys.exit("没有找到记录：%s" % p)
        recs += load(p, a)
    if not recs:
        sys.exit("筛选后没有记录")
    meta = [r["meta"] for r in recs]
    res = collections.Counter(m.get("result") for m in meta)
    head = ["# 玩家局内数据 %s" % ", ".join(os.path.basename(p) for p in a.files), "",
            "局数 %d（胜 %d / 负 %d / 中途退出 %d）；来源 %d 份文件；版本 %s；时间 %s ~ %s" % (
                len(recs), res["win"], res["dead"], res["quit"], len(a.files),
                ", ".join(sorted({"%s@%s" % (m.get("version"), m.get("commit")) for m in meta})),
                min(m.get("time", "") for m in meta), max(m.get("time", "") for m in meta)), ""]
    # 转成 balance_run 的记录形状：按开局干员分组，「机器人」列记为 player（--by-file 时记为文件名，各测试者分行）
    rows_in = [{"squad": [r["meta"].get("start_op", "?")], "seed": r["meta"].get("seed"), "diff": r["meta"].get("diff", 0),
                "bot": r["_file"] if a.by_file else "player", "data": r["run"]} for r in recs]
    rows = BR.summarize(rows_in)
    md = "\n".join(head) + "### 总览\n\n" + BR.bot_summary(rows_in)[0]
    md += "\n\n### 按难度 × 开局干员\n\n" + diff_op_table(recs)
    md += "\n\n### 按开局干员（balance_run 同款）\n\n" + BR.table(rows)
    md += "\n\n### 死因\n\n" + death_table(recs)
    md += "\n\n### Boss 用时\n\n" + boss_table(recs)
    for title, fn in (("最终 Boss（balance_run 同款）", BR.final_boss_summary), ("中期 Boss（balance_run 同款）", BR.mid_boss_summary)):
        t = fn(rows_in)
        if t:
            md += "\n\n#### %s\n\n%s" % (title, t)
    lc = level_curve(recs)
    if lc:
        md += "\n\n### 等级曲线（每 30 秒曲线取整分钟）\n\n" + lc
    md += "\n\n### 行为指标\n\n" + BR.bot_table(rows)
    rt = BR.relic_table(rows_in)
    if rt:
        md += "\n\n### 藏品\n\n" + rt
    md += "\n\n### 逐局清单\n\n" + run_list(recs, a.by_file)
    print(md)
    if a.out:
        os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
        open(a.out, "w", encoding="utf-8").write(md + "\n")
        print("写入", a.out)


if __name__ == "__main__":
    main()
