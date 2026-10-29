#!/usr/bin/env python3
"""死因报告：读 balance_run.py / 云端批跑产出的 JSON（records[].data 为 BALANCE 整局记录），
对每个失败局统计死亡前 2 秒 / 5 秒窗口的挨打次数、承伤占最大生命比、来源分类、2 秒上限是否起作用。

只读 JSON、不依赖 Godot。数据来源字段：data.bot.end.last15.hits（最近 15 秒逐 tick 掉血明细：
t / src / amt / hp_after / boss / zone_out）、data.bot.end（t / boss / zone_out）、data.bot.lamp_end、
data.maxhp。字段不够的地方（精英标记、敌弹来源类型、窗口内在场敌人数、上限触发计数）
在 docs/194_telemetry_plan.md §1 说明，这里只用现有字段能算的部分，不编造。

用法：
  python tools/death_report.py build/cloud/cal1029-T1 build/cloud/cal1029-R1 ...   # 目录（下面的 *.json）或单个 json
  python tools/death_report.py DIR... --bots expert,master --out build/death_report.md
  python tools/death_report.py DIR... --swarm 60 --cap 0.70 --sudden 0.5
"""
import argparse
import glob
import json
import os
import statistics
import sys
from collections import Counter, defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
ENEMIES = os.path.join(HERE, "..", "game", "data", "enemies.json")

# 每 tick 都会记一笔的持续 / 环境来源：数「挨了几下」时不算
PER_TICK = {"corrode", "wound", "mire", "zone", "dark", "nerve"}
DOT = {"corrode", "wound", "nerve"}


def load_roles():
    try:
        with open(ENEMIES, encoding="utf-8") as f:
            d = json.load(f)
        return {k: v.get("role", "") for k, v in d.get("enemies", {}).items()}
    except Exception:
        return {}


def category(src, roles, boss_alive):
    """来源键 → 类别。src 形如 contact_tracer / atk_reaper / boss_carmen / shock_paranoia / blast_runner / bullet / mire ..."""
    if src == "dark":
        return "熄灯"
    if src == "mire":
        return "溟痕"
    if src == "zone":
        return "黑潮(圈外)"
    if src in DOT:
        return "侵蚀/创口(持续)"
    if src == "bullet":
        return "敌弹(Boss在场)" if boss_alive else "敌弹"
    if "_" in src:
        ty = src.split("_", 1)[1]
        role = roles.get(ty, "")
        if role == "boss":
            return "Boss本体/招式"
        if role == "elite":
            return "精英(按类型)"
        return "普通怪"
    if src == "nest":
        return "普通怪"
    return "其他"


def files_of(paths):
    out = []
    for p in paths:
        if os.path.isdir(p):
            out += sorted(glob.glob(os.path.join(p, "**", "*.json"), recursive=True))
        else:
            out += sorted(glob.glob(p))
    return out


def window_stats(hits, t_end, span, maxhp):
    ws = [h for h in hits if h["t"] > t_end - span]
    dmg = sum(h["amt"] for h in ws)
    n_hit = sum(1 for h in ws if h["src"] not in PER_TICK)
    return ws, dmg / maxhp, n_hit


def max_2s(hits, maxhp):
    """15 秒明细里任意 2 秒滑窗的最大合计 / 最大生命。"""
    best = 0.0
    for h in hits:
        t0 = h["t"]
        s = sum(x["amt"] for x in hits if t0 <= x["t"] < t0 + 2.0)
        best = max(best, s)
    return best / maxhp


def hp_at(hits, tau):
    """tau 时刻的生命（最后一条 t<=tau 的 hp_after；没有则取最早一条的 hp_after+amt）。"""
    prev = None
    for h in hits:
        if h["t"] <= tau:
            prev = h
        else:
            break
    if prev is not None:
        return prev["hp_after"]
    return hits[0]["hp_after"] + hits[0]["amt"]


def group_of(t, boss):
    m = t / 60.0
    if boss:
        return "最终Boss段(>=10分,Boss在场)" if m >= 10 else "中期Boss段(Boss在场)"
    if m < 4:
        return "0-4分"
    if m < 7:
        return "4-7分"
    if m < 10:
        return "7-10分"
    return "10分后(无Boss)"


GROUP_ORDER = ["0-4分", "4-7分", "7-10分", "中期Boss段(Boss在场)", "最终Boss段(>=10分,Boss在场)", "10分后(无Boss)"]


def med(v, nd=2):
    return round(statistics.median(v), nd) if v else None


def q90(v):
    if not v:
        return None
    s = sorted(v)
    return round(s[min(len(s) - 1, int(0.9 * len(s)))], 2)


def pct(a, b):
    return "-" if b == 0 else "%d%%" % round(100.0 * a / b)


TIMEOUTS = []


def analyse(args):
    roles = load_roles()
    deaths = []
    total = 0
    for f in files_of(args.paths):
        try:
            with open(f, encoding="utf-8") as fh:
                d = json.load(fh)
        except Exception:
            continue
        if not isinstance(d, dict) or "records" not in d:
            continue
        branch = os.path.basename(os.path.dirname(f))
        for r in d["records"]:
            if args.bots and r.get("bot") not in args.bots:
                continue
            total += 1
            dd = r.get("data", {})
            if dd.get("win"):
                continue
            b = dd.get("bot") or {}
            end = b.get("end") or {}
            l15 = end.get("last15") or {}
            hits = l15.get("hits") or []
            if int(end.get("hp", 1)) > 0 and dd.get("t", 0) >= args.maxt - 1:
                # 到 bal_maxt（缺省 780 秒）还活着：最终 Boss 没打完的超时失败，不是死亡
                TIMEOUTS.append({"boss": ",".join(dd.get("bosses") or [])[-40:], "ending": dd.get("ending", ""), "hp": end.get("hp"),
                                 "maxhp": dd.get("maxhp"), "boss_hp": dd.get("boss_hp")})
                continue
            maxhp = float(dd.get("maxhp") or 0) or 1.0
            if not hits:
                deaths.append({"branch": branch, "no_ring": True, "t": dd.get("t", 0), "death_src": b.get("death_src", "")})
                continue
            t_end = max(h["t"] for h in hits)
            boss = bool(end.get("boss"))
            dd_t = dd.get("t", t_end)
            rec = {"branch": branch, "no_ring": False, "t": dd_t, "t_end": t_end, "boss": boss, "maxhp": maxhp,
                   "death_src": b.get("death_src", ""), "group": group_of(dd_t, boss),
                   "lamp_end": b.get("lamp_end"), "enemies_peak": l15.get("enemies_peak"),
                   "ebul_peak": l15.get("ebullets_peak"), "mire_s": l15.get("mire_s"), "squad": r.get("squad")}
            for span in (2.0, 5.0, 15.0):
                ws, frac, n_hit = window_stats(hits, t_end, span, maxhp)
                k = int(span)
                rec["dmg%d" % k] = frac
                rec["n%d" % k] = n_hit
                cat = defaultdict(float)
                src = defaultdict(float)
                for h in ws:
                    cat[category(h["src"], roles, boss)] += h["amt"]
                    src[h["src"]] += h["amt"]
                # 熄灯的持续掉血（每秒 3 点）不进 dmg_log、不在逐笔明细里，只有 last15.dark_s；窗口内按「熄灯秒数不超过窗口」折算
                dk = 3.0 * min(span, float(l15.get("dark_s") or 0.0))
                if dk > 0:
                    cat["熄灯"] += dk
                    src["dark"] += dk
                    rec["dmg%d" % k] += dk / maxhp
                rec["cat%d" % k] = dict(cat)
                rec["src%d" % k] = dict(src)
            rec["max2s"] = max_2s(hits, maxhp)
            rec["maxhit"] = max(h["amt"] for h in hits) / maxhp
            rec["hp5_pct"] = hp_at(hits, t_end - 5.0) / maxhp
            rec["hp2_pct"] = hp_at(hits, t_end - 2.0) / maxhp
            deaths.append(rec)
    return total, deaths


def dominant(cat):
    if not cat:
        return "-"
    return max(cat.items(), key=lambda kv: kv[1])[0]


def conclusions(ok, args):
    sudden = [d for d in ok if d["hp5_pct"] >= args.sudden]
    dom = Counter(dominant(d["cat5"]) for d in ok)
    top = "；".join("%s %s" % (k, pct(v, len(ok))) for k, v in dom.most_common(4))
    atcap = sum(1 for d in ok if d["max2s"] >= args.cap)
    near = sum(1 for d in ok if args.cap * 0.9 <= d["max2s"] < args.cap)
    return [
        "1. 暴毙（死前 5 秒血量 ≥ %d%%）占失败局 %s；5 秒承伤中位 %s×最大生命，2 秒中位 %s；挨打次数中位 %s 下。" % (
            int(args.sudden * 100), pct(len(sudden), len(ok)), med([d["dmg5"] for d in ok]), med([d["dmg2"] for d in ok]), med([d["n5"] for d in ok], 1)),
        "2. 5 秒窗口主因分布：%s。" % top,
        "3. 贴着或触到 2 秒上限（最大 2 秒滑窗 ≥ %.2f）的失败局 %s，贴近（≥0.9×）另有 %s；单下 ≥ 0.25 最大生命 %s。" % (
            args.cap, pct(atcap, len(ok)), pct(near, len(ok)), pct(sum(1 for d in ok if d["maxhit"] >= 0.25), len(ok))),
    ]


def render(total, deaths, args):
    L = []
    ok = [d for d in deaths if not d["no_ring"]]
    L.append("# 死因报告")
    L.append("")
    L.append("输入 %d 局（%s），失败 %d 局：死亡 %d 局（其中有 15 秒掉血明细的 %d 局），超时未死 %d 局（到 %d 秒最终 Boss 没打完，不进下面的死亡统计）。" % (
        total, "机器人 " + ",".join(args.bots) if args.bots else "全部机器人", len(deaths) + len(TIMEOUTS), len(deaths), len(ok), len(TIMEOUTS), int(args.maxt)))
    L.append("口径：窗口以最后一笔掉血的时刻为终点；承伤占比 = 窗口内 dmg_log 增量合计 / 局终最大生命（已是各种减伤与上限之后的实际扣血）；"
             "「挨了几下」不数持续 / 环境来源（侵蚀、创口、溟痕、黑潮、熄灯、神经），这些每 tick 记一笔。")
    L.append("")
    if not ok:
        return "\n".join(L)

    sudden = [d for d in ok if d["hp5_pct"] >= args.sudden]
    L.append("## 1. 暴毙占比")
    L.append("")
    L.append("- 死亡前 5 秒血量 ≥ %d%% 最大生命的「暴毙」局：%d / %d（%s）；其余为「失血型」。" % (
        int(args.sudden * 100), len(sudden), len(ok), pct(len(sudden), len(ok))))
    n2 = sum(1 for d in ok if d["hp2_pct"] >= 0.5)
    L.append("- 死亡前 2 秒血量 ≥ 50%%：%d / %d（%s）。" % (n2, len(ok), pct(n2, len(ok))))
    L.append("- 5 秒窗口承伤占最大生命 中位 %s，P90 %s；2 秒窗口 中位 %s，P90 %s。" % (
        med([d["dmg5"] for d in ok]), q90([d["dmg5"] for d in ok]), med([d["dmg2"] for d in ok]), q90([d["dmg2"] for d in ok])))
    L.append("")

    L.append("## 2. 按死亡时段")
    L.append("")
    L.append("| 时段 | 局数 | 占比 | 暴毙(5s前≥%d%%血) | 2s承伤 中位 | 5s承伤 中位 | 5s内挨打次数 中位 | 15s内在场敌人峰值 中位 | 单下最大(占最大生命) 中位 | 最大2s滑窗≥%.2f | 最大2s滑窗≥%.2f×0.9 |" % (
        int(args.sudden * 100), args.cap, args.cap))
    L.append("|---|---|---|---|---|---|---|---|---|---|---|")
    for g in GROUP_ORDER:
        s = [d for d in ok if d["group"] == g]
        if not s:
            continue
        L.append("| %s | %d | %s | %s | %s | %s | %s | %s | %s | %s | %s |" % (
            g, len(s), pct(len(s), len(ok)), pct(sum(1 for d in s if d["hp5_pct"] >= args.sudden), len(s)),
            med([d["dmg2"] for d in s]), med([d["dmg5"] for d in s]), med([d["n5"] for d in s], 1),
            med([d["enemies_peak"] for d in s if d["enemies_peak"] is not None], 0),
            med([d["maxhit"] for d in s]), pct(sum(1 for d in s if d["max2s"] >= args.cap), len(s)),
            pct(sum(1 for d in s if d["max2s"] >= args.cap * 0.9), len(s))))
    L.append("")

    L.append("## 3. 死前 5 秒来源与主因分布")
    L.append("")
    cats = Counter()
    for d in ok:
        for k, v in d["cat5"].items():
            cats[k] += v / d["maxhp"]
    tot = sum(cats.values()) or 1.0
    L.append("全部失败局 5 秒窗口承伤额占比（按占最大生命比加权）：" + "；".join("%s %d%%" % (k, round(100 * v / tot)) for k, v in cats.most_common()))
    L.append("")
    L.append("主因 = 5 秒窗口内承伤最大的类别（持续伤害单列，它是更早受击的后果，看下面的 15 秒口径）。")
    L.append("")
    names = sorted(cats)
    L.append("| 时段 | 局数 | " + " | ".join(names) + " |")
    L.append("|---|---|" + "---|" * len(names))
    for g in GROUP_ORDER + ["合计"]:
        s = ok if g == "合计" else [d for d in ok if d["group"] == g]
        if not s:
            continue
        dom = Counter(dominant(d["cat5"]) for d in s)
        L.append("| %s | %d | " % (g, len(s)) + " | ".join(pct(dom.get(c, 0), len(s)) for c in names) + " |")
    L.append("")
    cats15 = Counter()
    for d in ok:
        for k, v in d["cat15"].items():
            cats15[k] += v / d["maxhp"]
    t15 = sum(cats15.values()) or 1.0
    L.append("15 秒口径承伤额占比：" + "；".join("%s %d%%" % (k, round(100 * v / t15)) for k, v in cats15.most_common()))
    L.append("")

    sw = [d for d in ok if d["enemies_peak"] is not None and d["enemies_peak"] >= args.swarm]
    swc = [d for d in sw if dominant(d["cat5"]) == "普通怪"]
    L.append("## 4. 大群 / 具体怪种")
    L.append("")
    L.append("- 死前 15 秒在场敌人峰值 ≥ %d 的局：%d / %d（%s）；其中 5 秒主因是普通怪的 %d 局（%s）。字段只有 15 秒峰值、没有逐下的在场数，所以「大群围死」是粗判。" % (
        args.swarm, len(sw), len(ok), pct(len(sw), len(ok)), len(swc), pct(len(swc), len(ok))))
    src5 = Counter()
    for d in ok:
        for k, v in d["src5"].items():
            src5[k] += v / d["maxhp"]
    s5 = sum(src5.values()) or 1.0
    L.append("- 5 秒窗口承伤来源前 12（占比）：" + "；".join("%s %d%%" % (k, round(100 * v / s5)) for k, v in src5.most_common(12)))
    L.append("- 局终 death_src（最后一笔）分布前 8：" + "；".join("%s %s" % (k, pct(v, len(deaths))) for k, v in Counter(d["death_src"] for d in deaths).most_common(8))
             + "。corrode / wound 是持续伤害的最后一滴，不等于真凶。")
    L.append("")

    L.append("## 5. 灯火档与持续压力")
    L.append("")
    tiers = Counter()
    for d in ok:
        v = d["lamp_end"]
        if v is None:
            continue
        tiers["通明(>=70)" if v >= 70 else "摇曳(30-69)" if v >= 30 else "暗淡(1-29)" if v > 0 else "寂灭(0)"] += 1
    L.append("- 死亡时灯火档：" + "；".join("%s %s" % (k, pct(v, len(ok))) for k, v in tiers.most_common()))
    L.append("- 15 秒内站在溟痕里 >= 3 秒的局：%s；15 秒内有熄灯掉血的局：%s。" % (
        pct(sum(1 for d in ok if (d["mire_s"] or 0) >= 3.0), len(ok)), pct(sum(1 for d in ok if d["cat15"].get("熄灯", 0) > 0), len(ok))))
    L.append("")

    L.append("## 6. 2 秒上限 / 单下上限（推断，游戏没有计数）")
    L.append("")
    L.append("游戏里 `_any_clamp` / `_boss_clamp` 触发时不记数；这里用 15 秒明细里最大的 2 秒滑窗合计推断。窗口合计 >= any_2s_cap(%.2f) x 最大生命，说明上限已在起作用（超出部分只放过 x0.6）；"
             "合计在 0.9 x 上限到上限之间，说明贴着上限。" % args.cap)
    L.append("")
    nc = sum(1 for d in ok if d["max2s"] >= args.cap)
    nn = sum(1 for d in ok if args.cap * 0.9 <= d["max2s"] < args.cap)
    L.append("- 最大 2 秒滑窗 >= %.2f：%d / %d（%s）；在 [%.2f, %.2f)：%s。" % (
        args.cap, nc, len(ok), pct(nc, len(ok)), args.cap * 0.9, args.cap, pct(nn, len(ok))))
    L.append("- 最大 2 秒滑窗 中位 %s、P90 %s；死前 2 秒窗口 >= %.2f 的局：%s。" % (
        med([d["max2s"] for d in ok]), q90([d["max2s"] for d in ok]), args.cap, pct(sum(1 for d in ok if d["dmg2"] >= args.cap), len(ok))))
    L.append("- 单下最大（占最大生命）中位 %s、P90 %s；单下 >= 0.25 的局：%s；>= 0.40（Boss leader_hit_cap）：%s。" % (
        med([d["maxhit"] for d in ok]), q90([d["maxhit"] for d in ok]),
        pct(sum(1 for d in ok if d["maxhit"] >= 0.25), len(ok)), pct(sum(1 for d in ok if d["maxhit"] >= 0.40), len(ok))))
    nb = sum(1 for d in ok if d["boss"])
    L.append("- 只看 Boss 在场的 %d 局：最大 2 秒滑窗 >= %.2f 的 %s（Boss 来源另走 leader_2s_cap 0.68，口径不同）。" % (
        nb, args.cap, pct(sum(1 for d in ok if d["boss"] and d["max2s"] >= args.cap), nb)))
    L.append("")

    L.append("## 7. 三行结论（自动生成，口径见上）")
    L.append("")
    L.extend(conclusions(ok, args))
    return "\n".join(L)


def main():
    ap = argparse.ArgumentParser(description="死因报告（读 BALANCE json，不依赖 Godot）")
    ap.add_argument("paths", nargs="+", help="目录（递归找 *.json）或 json 文件 / 通配")
    ap.add_argument("--bots", default="expert,master", help="只统计这些机器人档位，逗号分隔；空 = 全部")
    ap.add_argument("--swarm", type=int, default=60, help="「大群」门槛：死前 15 秒在场敌人峰值")
    ap.add_argument("--cap", type=float, default=0.70, help="protect/any_2s_cap（balance.json 现值 0.70）")
    ap.add_argument("--sudden", type=float, default=0.5, help="暴毙门槛：死亡前 5 秒血量占最大生命比例")
    ap.add_argument("--maxt", type=float, default=780.0, help="局时限（bal_maxt，缺省 780 秒）：到点还活着算超时失败，不进死亡统计")
    ap.add_argument("--out", default="", help="写入 markdown 文件；缺省打印到标准输出")
    args = ap.parse_args()
    args.bots = [b for b in args.bots.split(",") if b]
    total, deaths = analyse(args)
    text = render(total, deaths, args)
    if args.out:
        with open(args.out, "w", encoding="utf-8") as f:
            f.write(text + "\n")
        print("已写入", args.out)
    else:
        try:
            sys.stdout.reconfigure(encoding="utf-8")
        except Exception:
            pass
        print(text)


if __name__ == "__main__":
    main()
