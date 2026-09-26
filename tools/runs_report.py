"""玩家局内数据汇总（docs/40）：读 game/scripts/run/telemetry.gd 写下的本地记录，套用 balance_run 的汇总表。

记录在哪：Godot 的用户目录下 runs/runs.jsonl，每局一行 {"schema", "meta": {版本, 提交, 平台, 时间, 种子, 难度, 地图, 开局干员, 结果}, "run": 整局记录}。
  Windows：%APPDATA%\\Godot\\app_userdata\\水月 · 深海幸存者\\runs\\runs.jsonl
「run」和平衡测试打印的 BALANCE 同一格式，所以胜率 / 存活 / 伤害构成 / 死因 / 藏品拿取这些表可以直接复用。

用法：
  python tools/runs_report.py                       # 本机全部记录
  python tools/runs_report.py --since 2026-09-26    # 某天以后
  python tools/runs_report.py --commit abc1234      # 只看某个版本（改平衡前后对比）
  python tools/runs_report.py --file 某个.jsonl --out build/runs_report.md
"""
import argparse, collections, json, os, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import balance_run as BR   # noqa: E402  复用汇总表

PROJECT = "水月 · 深海幸存者"   # game/project.godot config/name


def default_file():
    base = os.environ.get("APPDATA") or os.path.expanduser("~/.local/share")
    return os.path.join(base, "Godot", "app_userdata", PROJECT, "runs", "runs.jsonl")


def load(path, a):
    out = []
    for n, line in enumerate(open(path, encoding="utf-8"), 1):
        line = line.strip()
        if not line:
            continue
        try:
            rec = json.loads(line)
        except ValueError:
            print("跳过第 %d 行：不是合法 JSON" % n, file=sys.stderr)
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
        out.append(rec)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--file", default=None, help="记录文件（缺省：本机 Godot 用户目录下的 runs/runs.jsonl）")
    ap.add_argument("--since", default=None, help="只看这个时间以后（ISO 前缀，如 2026-09-26）")
    ap.add_argument("--commit", default=None)
    ap.add_argument("--version", default=None)
    ap.add_argument("--diff", type=int, default=None, help="只看某个难度")
    ap.add_argument("--result", choices=["win", "dead", "quit"], default=None)
    ap.add_argument("--out", default=None, help="另存为 Markdown")
    a = ap.parse_args()
    path = a.file or default_file()
    if not os.path.exists(path):
        sys.exit("没有找到记录：%s（正常游玩一局、局内超过 20 秒后才会写入）" % path)
    recs = load(path, a)
    if not recs:
        sys.exit("筛选后没有记录")
    meta = [r["meta"] for r in recs]
    res = collections.Counter(m.get("result") for m in meta)
    head = ["# 玩家局内数据 %s" % os.path.basename(path), "",
            "局数 %d（胜 %d / 负 %d / 中途退出 %d）；版本 %s；时间 %s ~ %s" % (
                len(recs), res["win"], res["dead"], res["quit"],
                ", ".join(sorted({"%s@%s" % (m.get("version"), m.get("commit")) for m in meta})),
                min(m.get("time", "") for m in meta), max(m.get("time", "") for m in meta)), ""]
    # 转成 balance_run 的记录形状：按开局干员分组，机器人档位记为 player
    rows_in = [{"squad": [r["meta"].get("start_op", "?")], "seed": r["meta"].get("seed"), "diff": r["meta"].get("diff", 0),
                "bot": "player", "data": r["run"]} for r in recs]
    rows = BR.summarize(rows_in)
    md = "\n".join(head) + "### 总览\n\n" + BR.bot_summary(rows_in)[0] + "\n\n### 按开局干员\n\n" + BR.table(rows) + \
        "\n\n### 行为指标\n\n" + BR.bot_table(rows)
    rt = BR.relic_table(rows_in)
    if rt:
        md += "\n\n### 藏品\n\n" + rt
    print(md)
    if a.out:
        os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
        open(a.out, "w", encoding="utf-8").write(md + "\n")
        print("写入", a.out)


if __name__ == "__main__":
    main()
