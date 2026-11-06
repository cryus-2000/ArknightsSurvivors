"""终结技伤害现状（docs/302）：读 cloud-results/<分支> 里 balance_run 的原始 json（批跑带 --ultcasts），
按 组 × 机器人 × 难度 出总表，再按队长出每人表。
用法：python tools/ult_dmg_audit.py [--fetch] --arms A0=cloud-results/ud1107-A0,A1=cloud-results/ud1107-A1b [--by-op A0] [--json out.json]
口径：
  次数 = 每局终结技（不含连携终结技）次数；活到 8:00 的局另列（早死局拉低均值）
  每次：d 实际掉血合计 / mk 小怪击杀 / mv 出招时屏内小怪 / 清屏 = mk / mv（上限 100%）
  精英：这次罩到的精英合计被打掉最大生命的比例；Boss：中期 Boss / 最终 Boss 这次打掉最大生命的比例（只算打到的那几次）
  占比 = 终结技来源（终结技· / 连携终结技·）伤害 / 全队造成伤害
  时段：前期 < 4:00、中期 4:00–8:00、后期 ≥ 8:00
"""
import argparse
import json
import os
import statistics as st
import subprocess
import sys
from collections import defaultdict

sys.stdout.reconfigure(encoding="utf-8")
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def git(*a):
    return subprocess.run(["git", "-C", ROOT] + list(a), capture_output=True, text=True, encoding="utf-8").stdout


def load(branch):
    ref = "origin/" + branch
    out = []
    for f in git("ls-tree", "-r", "--name-only", ref).splitlines():
        base = os.path.basename(f)
        if not (f.endswith(".json") and base.startswith("ud-")):
            continue
        try:
            d = json.loads(git("show", ref + ":" + f))
        except json.JSONDecodeError:
            continue
        if not isinstance(d, dict) or "records" not in d:
            continue
        band = "m18" if "-m18" in base else "m0"
        for r in d["records"]:
            if "data" in r:
                r["_band"] = band
                out.append(r)
    return out


def mean(v):
    return st.mean(v) if v else float("nan")


def med(v):
    return st.median(v) if v else float("nan")


def phase(t):
    return "early" if t < 240 else ("mid" if t < 480 else "late")


def ult_casts(r):
    return [c for c in r["data"].get("ult", {}).get("casts", []) if c.get("k") == "ult"]


def cell_stats(rs):
    """一组局的终结技指标"""
    n = len(rs)
    wins = sum(1 for r in rs if r["data"].get("win"))
    casts_pr, casts_pr8, share = [], [], []
    per, mk, clear, el, mid_b, fin_b, fin_sum = [], [], [], [], [], [], []
    ph = defaultdict(int)
    php = defaultdict(list)   # 时段 → 每次掉血
    for r in rs:
        d = r["data"]
        cs = ult_casts(r)
        casts_pr.append(len(cs))
        if d["t"] >= 480:
            casts_pr8.append(len(cs))
        out = d.get("out", {})
        tot = sum(out.values()) or 1.0
        share.append(sum(v for k, v in out.items() if k.startswith("终结技·") or k.startswith("连携终结技·")) / tot)
        fs, hit_fin = 0.0, False
        for c in cs:
            p = phase(c["t"])
            ph[p] += 1
            per.append(c["d"])
            mk.append(c["mk"])
            if c.get("mv", -1) > 0:
                clear.append(min(1.0, c["mk"] / c["mv"]))
                php[p].append(min(1.0, c["mk"] / c["mv"]))
            if c.get("en", 0) > 0 and c.get("emh", 0) > 0:
                el.append(c["ed"] / c["emh"])
            for bk, f in c.get("b", {}).items():
                if bk.startswith("f:"):
                    fin_b.append(f)
                    fs += f
                    hit_fin = True
                else:
                    mid_b.append(f)
        if hit_fin:
            fin_sum.append(fs)
    tc = sum(ph.values()) or 1
    return {
        "n": n, "win": wins / max(1, n), "surv": mean([r["data"]["t"] for r in rs]),
        "casts": mean(casts_pr), "casts8": mean(casts_pr8), "n8": len(casts_pr8),
        "share": mean(share), "dmg_per": med(per), "mk": mean(mk), "clear": mean(clear),
        "clear_ph": {k: mean(v) for k, v in php.items()},
        "elite": mean(el), "mid_boss": mean(mid_b), "mid_n": len(mid_b), "fin_boss": mean(fin_b), "fin_n": len(fin_b),
        "fin_sum": mean(fin_sum),
        "ph": {k: ph[k] / tc for k in ("early", "mid", "late")},
    }


def boss_fight(rs):
    by = defaultdict(list)
    for r in rs:
        for b in r["data"].get("bot", {}).get("bosses", []):
            if b.get("t1", -1) > 0:
                by[b["type"]].append(b["t1"] - b["t0"])
    return {k: (len(v), med(v)) for k, v in sorted(by.items())}


def fmt_cell(s):
    p, cp = s["ph"], s["clear_ph"]
    return ("%3d 局 胜 %5.1f%% 存活 %4.0f 秒 | 次数 %.2f（活到 8 分的 %d 局 %.2f）| 占比 %4.1f%% | 每次掉血中位 %6.0f 小怪击杀 %5.1f"
            " 清屏 %4.1f%%（前 %2.0f / 中 %2.0f / 后 %2.0f）| 精英 %4.1f%% | 中期 Boss %4.1f%%（%d 次）| 最终 Boss %4.1f%%（%d 次，一局合计 %4.1f%%）"
            "| 时段 前 / 中 / 后 %2.0f / %2.0f / %2.0f%%") % (
        s["n"], s["win"] * 100, s["surv"], s["casts"], s["n8"], s["casts8"], s["share"] * 100, s["dmg_per"], s["mk"],
        s["clear"] * 100, cp.get("early", float("nan")) * 100, cp.get("mid", float("nan")) * 100, cp.get("late", float("nan")) * 100,
        s["elite"] * 100, s["mid_boss"] * 100, s["mid_n"], s["fin_boss"] * 100, s["fin_n"], s["fin_sum"] * 100,
        p["early"] * 100, p["mid"] * 100, p["late"] * 100)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--fetch", action="store_true")
    ap.add_argument("--arms", required=True)
    ap.add_argument("--by-op", default="")
    ap.add_argument("--json", default="")
    a = ap.parse_args()
    arms = [x.split("=", 1) for x in a.arms.split(",")]
    if a.fetch:
        for _, b in arms:
            git("fetch", "-q", "origin", "+%s:refs/remotes/origin/%s" % (b, b))
    data = {name: load(br) for name, br in arms}
    dump = {}
    for name, rs in data.items():
        print("\n## %s（%d 局，脚本错误 %d）" % (name, len(rs), sum(1 for r in rs if r.get("script_errors"))))
        for bot in ("expert", "normal"):
            for band in ("m0", "m18"):
                sub = [r for r in rs if r.get("bot") == bot and r["_band"] == band]
                if not sub:
                    continue
                s = cell_stats(sub)
                s["boss_fight"] = boss_fight(sub)
                dump["%s/%s/%s" % (name, bot, band)] = s
                print("- %s %s：%s" % (bot, band, fmt_cell(s)))
                print("    Boss 用时中位（秒，打掉的局数）：" + "，".join("%s %.0f（%d）" % (k, v[1], v[0]) for k, v in s["boss_fight"].items()))
    for name in [x for x in a.by_op.split(",") if x]:
        rs = data[name]
        for bot in ("expert", "normal", None):
            sub0 = [r for r in rs if bot is None or r.get("bot") == bot]
            print("\n## %s 按队长（%s，m0 + m18 合并，按终结技伤害占比排序）" % (name, bot or "两档机器人合并"))
            print("| 队长 | 局 | 胜 | 次数 | 活到 8 分次数 | 每次掉血中位 | 小怪击杀 | 清屏 | 占比 | 精英 | 中期 Boss | 最终 Boss |")
            print("|---|---|---|---|---|---|---|---|---|---|---|---|")
            rows = []
            for op in sorted({r["squad"][0] for r in sub0}):
                s = cell_stats([r for r in sub0 if r["squad"][0] == op])
                rows.append((op, s))
                dump["%s/op/%s/%s" % (name, bot or "all", op)] = s
            for op, s in sorted(rows, key=lambda x: x[1]["share"]):
                print("| %s | %d | %.0f%% | %.2f | %.2f | %.0f | %.1f | %.0f%% | %.1f%% | %.0f%% | %.1f%% | %.1f%% |" % (
                    op, s["n"], s["win"] * 100, s["casts"], s["casts8"], s["dmg_per"], s["mk"], s["clear"] * 100, s["share"] * 100,
                    s["elite"] * 100, s["mid_boss"] * 100, s["fin_boss"] * 100))
    if a.json:
        with open(a.json, "w", encoding="utf-8") as f:
            json.dump(dump, f, ensure_ascii=False, indent=1)


if __name__ == "__main__":
    main()
