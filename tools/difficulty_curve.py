#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""难度曲线审计（docs/146）：读 balance_run 的整局记录（bot.curve 每 30 秒一格），按时间切片出压力曲线、标平台段 / 断层，出图 + markdown。

用法（仓库根目录；云端结果按 tag 自动 fetch cloud-results/<tag>）：
    D:/Anaconda/python.exe tools/difficulty_curve.py 常规=curve-t0 高压=curve-t5 深潮=curve-t10 --out build/curve146
    D:/Anaconda/python.exe tools/difficulty_curve.py 常规=build/balance/xxx.json --out build/curve146

每格（窗口 (t−30, t]，只统计这一格开始时还活着的局）：
  压力 = 承伤 ÷ 最大生命 × 2（每分钟承伤占最大生命的百分比）；生命中位 / 窗口最低生命 P10；在场敌人、精英、敌弹；击杀 / 分；灯火；
  溟痕片数、站溟痕秒数；Boss 在场比例；这一格死了几局、头号死因；存活率。
平台段：压力连续 ≥ 4 格（2 分钟）每格变化 < 全程压力跨度的 8%，且不在开局第一分钟；断层：相邻两格（1 分钟平均）压力涨幅 > 全程跨度的 22%。死亡集中格另列（本格死亡率 ≥ 8%）。
只读结果，不跑游戏。
"""
import argparse, glob, json, os, statistics, subprocess, sys
from collections import Counter, defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STEP = 30
TMAX = 690


def load_source(src):
    """tag（cloud-results/<tag> 分支里 build/cloud/**.json）或本地 json / 目录 → 记录列表"""
    if os.path.exists(src):
        files = [src] if src.endswith(".json") else glob.glob(os.path.join(src, "**", "*.json"), recursive=True)
        out = []
        for f in files:
            d = json.load(open(f, encoding="utf-8"))
            out += d.get("records", []) if isinstance(d, dict) else []
        return out
    ref = "origin/cloud-results/" + src
    subprocess.run(["git", "-C", ROOT, "fetch", "-q", "origin", "cloud-results/" + src], check=False)
    names = subprocess.run(["git", "-C", ROOT, "ls-tree", "-r", "--name-only", ref], capture_output=True, text=True, encoding="utf-8").stdout.split()
    out = []
    for n in names:
        if n.startswith("build/cloud/") and n.endswith(".json"):
            txt = subprocess.run(["git", "-C", ROOT, "show", ref + ":" + n], capture_output=True, encoding="utf-8").stdout
            try:
                d = json.loads(txt)
            except ValueError:
                continue
            out += d.get("records", []) if isinstance(d, dict) else []
    return out


def q(vals, p):
    vals = sorted(v for v in vals if v is not None)
    if not vals:
        return None
    k = (len(vals) - 1) * p
    lo = int(k)
    hi = min(lo + 1, len(vals) - 1)
    return vals[lo] + (vals[hi] - vals[lo]) * (k - lo)


def slices(recs):
    """→ {t: 指标字典}"""
    out = {}
    for t in range(STEP, TMAX + 1, STEP):
        rows = []
        for r in recs:
            d = r["data"]
            cv = {c["t"]: c for c in d["bot"].get("curve", [])}
            if t in cv:
                rows.append((r, cv[t], cv.get(t - STEP)))
        start_alive = sum(1 for r in recs if r["data"]["t"] > t - STEP)
        lost = sum(1 for r in recs if not r["data"]["win"] and r["data"]["t"] <= t)
        deaths = [r for r in recs if not r["data"]["win"] and t - STEP < r["data"]["t"] <= t]
        causes = Counter(r["data"]["bot"].get("death_src", "?") for r in deaths)
        if not rows and not deaths:
            continue
        g = lambda f: [f(c, p) for _, c, p in rows]
        pres = g(lambda c, p: 200.0 * c.get("taken", 0) / max(1, c.get("mhp", 100)))
        out[t] = {
            "n": len(rows), "alive0": start_alive,
            "pres_med": q(pres, .5), "pres_p25": q(pres, .25), "pres_p75": q(pres, .75), "pres_p90": q(pres, .9),
            "hp_med": q(g(lambda c, p: c.get("hp")), .5), "hpmin_p10": q(g(lambda c, p: c.get("hpmin")), .1),
            "hpmin_med": q(g(lambda c, p: c.get("hpmin")), .5),
            "enemies": q(g(lambda c, p: c.get("enemies")), .5), "elites": q(g(lambda c, p: c.get("elites")), .5),
            "ebul": q(g(lambda c, p: c.get("ebul")), .5),
            "kpm": q([2 * (c.get("kills", 0) - (p or {}).get("kills", 0)) for _, c, p in rows if p], .5),
            "lamp": q(g(lambda c, p: c.get("lamp")), .5),
            "mires": q(g(lambda c, p: c.get("mires")), .5), "mire_s": (statistics.mean([v for v in g(lambda c, p: c.get("mire_s")) if v is not None]) if any(c.get("mire_s") is not None for _, c, _p in rows) else None),
            "boss": statistics.mean(g(lambda c, p: c.get("boss", 0))) if rows else 0,
            "lv": q(g(lambda c, p: c.get("lv")), .5), "squad": q(g(lambda c, p: c.get("squad")), .5),
            "deaths": len(deaths), "surv": 1.0 - lost / max(1, len(recs)), "haz": len(deaths) / max(1, start_alive), "cause": causes.most_common(2),
            "dsrc": _top_src(rows),
        }
    return out


def _top_src(rows):
    acc = Counter()
    for _, c, _p in rows:
        for k, v in (c.get("dsrc") or {}).items():
            acc[_src_group(k)] += v
    tot = sum(acc.values())
    return [(k, round(100.0 * v / tot)) for k, v in acc.most_common(3)] if tot else []


def _src_group(k):
    for pre, name in (("boss_", "Boss"), ("contact_", "近身"), ("atk_", "怪物招式"), ("bullet", "敌弹"), ("corrode", "溟痕腐蚀"), ("mire", "溟痕"),
                      ("nerve", "神经损伤"), ("dark", "熄灯"), ("wound", "创伤")):
        if k.startswith(pre):
            return name
    return k


def marks(sl):
    ts = sorted(sl)
    raw = [sl[t]["pres_med"] or 0.0 for t in ts]
    p = [(raw[i] + raw[max(0, i - 1)]) / 2.0 for i in range(len(raw))]   # 1 分钟滑动平均再判（30 秒一格中位数抖动大）
    for i, t in enumerate(ts):
        sl[t]["pres_sm"] = p[i]
    span = (max(p) - min(p)) or 1.0
    plats, cliffs = [], []
    run = [ts[0]]
    for i in range(1, len(ts)):
        if abs(p[i] - p[i - 1]) < 0.08 * span and sl[ts[i]]["n"] >= 5:
            run.append(ts[i])
        else:
            if len(run) >= 4 and run[0] >= 60:
                plats.append((run[0] - STEP, run[-1]))
            run = [ts[i]]
        if p[i] - p[i - 1] > 0.22 * span:
            cliffs.append(ts[i])
    if len(run) >= 4 and run[0] >= 60:
        plats.append((run[0] - STEP, run[-1]))
    return plats, cliffs


def boss_stats(recs):
    out = defaultdict(list)
    for r in recs:
        d = r["data"]
        cv = d["bot"].get("curve", [])
        for b in d["bot"].get("bosses", []):
            t0, t1 = b.get("t0"), b.get("t1")
            if t0 is None:
                continue
            slot = "3:30" if t0 < 400 else ("7:00" if t0 < 590 else "10:00")
            end = t1 if t1 is not None and t1 > t0 else d["t"]
            tk = sum(c.get("taken", 0) for c in cv if t0 < c["t"] <= end + STEP)
            mhp = max([c.get("mhp", 100) for c in cv] or [100])
            out[slot].append((end - t0, 100.0 * tk / max(1, mhp) / max(0.5, (end - t0 + STEP) / 60.0), b.get("type"), t1 is not None and t1 > t0))
    return out


LAMP_BANDS = ["通明 ≥70", "摇曳 30–69", "暗淡 <30", "寂灭 0"]


def lamp_section(rs):
    """灯火统计（docs/146 §6）：需要 52ac39f8b 起的 bot.lamp_s / lamp_gain / lamp_loss / lamp_taken / lamp_end；旧数据只出 curve 的 lamp 中位"""
    md = []
    ts = sorted({c["t"] for r in rs for c in r["data"]["bot"].get("curve", []) if c["t"] > 0})
    med = []
    for t in ts:
        v = [c.get("lamp") for r in rs for c in r["data"]["bot"].get("curve", []) if c["t"] == t]
        lm = [c.get("lampmin") for r in rs for c in r["data"]["bot"].get("curve", []) if c["t"] == t and c.get("lampmin") is not None]
        if len(v) >= 5 and t % 60 == 0:
            med.append("%d:00 %.0f（P10 %.0f%s）" % (t // 60, q(v, .5), q(v, .1), "，窗口最低 P10 %.0f" % q(lm, .1) if lm else ""))
    md.append("灯火中位（每分钟采样，P10）：" + "；".join(med))
    have = [r for r in rs if "lamp_s" in r["data"]["bot"]]
    if not have:
        md.append("（这批数据没有灯火分档统计）")
        return md
    tot = [0.0] * 4
    for r in have:
        for i, v in enumerate(r["data"]["bot"]["lamp_s"]):
            tot[i] += v
    T = sum(tot) or 1.0
    md.append("各档停留时间：" + "；".join("%s %.1f%%" % (LAMP_BANDS[i], 100 * tot[i] / T) for i in range(4)))
    dark_runs = sum(1 for r in have if r["data"]["bot"].get("dark_s", 0) > 0)
    md.append("出现过熄灯（=0）的局：%d / %d；熄灯总秒数中位 %s" % (dark_runs, len(have), "%.0f" % q([r["data"]["bot"].get("dark_s", 0) for r in have if r["data"]["bot"].get("dark_s", 0) > 0], .5) if dark_runs else "-"))
    mins = sum(r["data"]["t"] for r in have) / 60.0
    for key, title in (("lamp_gain", "回补"), ("lamp_loss", "损失")):
        acc = Counter()
        for r in have:
            for k, v in (r["data"]["bot"].get(key) or {}).items():
                acc[k] += v
        s = sum(acc.values()) or 1
        md.append("%s（每分钟平均 / 占比）：%s" % (title, "；".join("%s %.1f / %.0f%%" % (k, v / mins, 100.0 * v / s) for k, v in acc.most_common())))
    # 各档承伤：每分钟承伤占最大生命 %
    tk = [0.0] * 4
    for r in have:
        mhp = max([c.get("mhp", 100) for c in r["data"]["bot"].get("curve", [])] or [100])
        for i, v in enumerate(r["data"]["bot"].get("lamp_taken", [0, 0, 0, 0])):
            tk[i] += 100.0 * v / mhp
    md.append("各档压力（每分钟承伤 % 最大生命）：" + "；".join("%s %s" % (LAMP_BANDS[i], "%.0f" % (tk[i] / (tot[i] / 60.0)) if tot[i] > 30 else "-") for i in range(4)))
    deaths = [r for r in have if not r["data"]["win"] and r["data"]["t"] < 690]
    band = Counter()
    for r in deaths:
        le = r["data"]["bot"].get("lamp_end", 100)
        band[0 if le >= 70 else 1 if le >= 30 else 2 if le > 0 else 3] += 1
    md.append("阵亡时灯火所在档（%d 局）：%s；对比停留时间占比可看「暗时死得多不多」" % (len(deaths), "；".join("%s %d（%.0f%%）" % (LAMP_BANDS[i], band[i], 100.0 * band[i] / max(1, len(deaths))) for i in range(4))))
    return md


def plot(name, groups, path):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    plt.rcParams["font.sans-serif"] = ["Microsoft YaHei", "SimHei", "DejaVu Sans"]
    fig, ax = plt.subplots(4, 1, figsize=(11, 10), sharex=True)
    cols = {"expert": "#2f7fd0", "normal": "#d0453a"}
    for bot, (sl, plats, cliffs) in groups.items():
        ts = sorted(sl)
        x = [t / 60 for t in ts]
        c = cols.get(bot, "#555")
        lab = {"expert": "高手", "normal": "普通"}.get(bot, bot)
        ax[0].plot(x, [sl[t]["pres_med"] for t in ts], color=c, lw=0.8, alpha=0.6, label=lab + " 中位")
        ax[0].plot(x, [sl[t].get("pres_sm") for t in ts], color=c, lw=2.0, label=lab + " 1 分钟平均")
        ax[0].fill_between(x, [sl[t]["pres_p25"] or 0 for t in ts], [sl[t]["pres_p75"] or 0 for t in ts], color=c, alpha=0.15)
        for a, b in plats:
            ax[0].axvspan(a / 60, b / 60, color=c, alpha=0.08, hatch="//" if bot == "normal" else None)
        for t in cliffs:
            ax[0].axvline(t / 60, color=c, ls=":", lw=1)
        ax[1].plot(x, [sl[t]["hpmin_med"] for t in ts], color=c, lw=1.4, label=lab + " 窗口最低生命 中位")
        ax[1].plot(x, [sl[t]["hpmin_p10"] for t in ts], color=c, lw=1, ls="--", label=lab + " 窗口最低 P10")
        ax[2].plot(x, [sl[t]["enemies"] for t in ts], color=c, lw=1.4, label=lab + " 在场敌人")
        if any(sl[t]["mires"] is not None for t in ts):
            ax[2].plot(x, [(sl[t]["mires"] or 0) * 5 for t in ts], color=c, lw=1, ls="--", label=lab + " 溟痕片数×5")
        if any(sl[t]["elites"] is not None for t in ts):
            ax[2].plot(x, [(sl[t]["elites"] or 0) * 10 for t in ts], color=c, lw=1, ls=":", label=lab + " 精英×10")
        ax[3].plot(x, [sl[t]["surv"] * 100 for t in ts], color=c, lw=1.4, label=lab + " 未阵亡 %")
        ax[3].bar([v + (0.06 if bot == "normal" else -0.06) for v in x], [sl[t]["haz"] * 100 for t in ts], width=0.12, color=c, alpha=0.5, label=lab + " 本格死亡率 %")
    for a in ax:
        for bt in (210, 420, 600):
            a.axvline(bt / 60, color="#888", lw=0.8)
        a.legend(fontsize=7, loc="upper left", ncol=3)
        a.grid(alpha=0.2)
    ax[0].set_ylabel("压力：每分钟承伤 % 最大生命")
    ax[1].set_ylabel("生命 %（每 30 秒窗口内最低）")
    ax[2].set_ylabel("数量")
    ax[3].set_ylabel("%")
    ax[3].set_xlabel("分钟（灰线 = 3:30 / 7:00 / 10:00 Boss；阴影 = 平台段，虚线 = 断层）")
    fig.suptitle("%s：难度曲线（30 秒一格）" % name)
    fig.tight_layout()
    fig.savefig(path, dpi=80)
    plt.close(fig)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("groups", nargs="+")
    ap.add_argument("--out", default="build/curve146")
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    md = []
    summary = {}
    for spec in a.groups:
        name, src = spec.split("=", 1) if "=" in spec else (spec, spec)
        recs = []
        for s in src.split("+"):
            recs += load_source(s)
        bybot = defaultdict(list)
        for r in recs:
            if isinstance(r.get("data"), dict) and r["data"].get("bot"):
                bybot[r.get("bot", "?")].append(r)
        groups = {}
        md.append("## %s（%d 局）\n" % (name, len(recs)))
        for bot, rs in sorted(bybot.items()):
            sl = slices(rs)
            plats, cliffs = marks(sl)
            groups[bot] = (sl, plats, cliffs)
            wins = sum(1 for r in rs if r["data"]["win"])
            md.append("### %s 机器人：胜率 %d/%d = %.1f%%\n" % (bot, wins, len(rs), 100.0 * wins / max(1, len(rs))))
            hot = [t for t in sorted(sl) if sl[t]["haz"] >= 0.08]
            md.append("死亡集中格（本格死亡率 ≥ 8%%）：%s\n" % ("、".join("%d:%02d（%.0f%%）" % (t // 60, t % 60, 100 * sl[t]["haz"]) for t in hot) or "无"))
            md.append("平台段：%s；断层：%s\n" % ("、".join("%d:%02d–%d:%02d" % (p // 60, p % 60, q2 // 60, q2 % 60) for p, q2 in plats) or "无",
                                              "、".join("%d:%02d" % (t // 60, t % 60) for t in cliffs) or "无"))
            md.append("| 时刻 | 在局 | 压力中位 / P75 | 生命中位 | 最低生命 P10 | 敌人 | 精英 | 敌弹 | 击杀/分 | 灯火 | 溟痕片 / 站溟痕秒 | Boss 在场 | 死亡 | 头号死因 | 承伤来源 |")
            md.append("|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|")
            f = lambda v, fmt="%.0f": "-" if v is None else fmt % v
            for t in sorted(sl):
                s = sl[t]
                md.append("| %d:%02d | %d | %s / %s | %s | %s | %s | %s | %s | %s | %s | %s / %s | %s | %d | %s | %s |" % (
                    t // 60, t % 60, s["n"], f(s["pres_med"]), f(s["pres_p75"]), f(s["hp_med"]), f(s["hpmin_p10"]), f(s["enemies"]), f(s["elites"]),
                    f(s["ebul"]), f(s["kpm"]), f(s["lamp"]), f(s["mires"]), f(s["mire_s"], "%.1f"), f(100 * s["boss"]) + "%", s["deaths"],
                    "、".join("%s×%d" % kv for kv in s["cause"]) or "-", "、".join("%s %d%%" % kv for kv in s["dsrc"]) or "-"))
            md.append("\n灯火：\n")
            md += ["- " + x for x in lamp_section(rs)]
            bs = boss_stats(rs)
            md.append("\nBoss 段：" + "；".join("%s 出场 %d、击破 %d、用时中位 %s 秒、段内压力中位 %s" % (
                k, len(v), sum(1 for x in v if x[3]), f(q([x[0] for x in v if x[3]], .5)), f(q([x[1] for x in v], .5))) for k, v in sorted(bs.items())) + "\n")
            summary["%s/%s" % (name, bot)] = {"win": wins, "n": len(rs), "plats": plats, "cliffs": cliffs,
                                             "pres": {t: sl[t]["pres_med"] for t in sorted(sl)}, "haz": {t: sl[t]["haz"] for t in sorted(sl)}}
        png = os.path.join(a.out, "curve_%s.png" % name)
        plot(name, groups, png)
        md.append("![](%s)\n" % os.path.basename(png))
    open(os.path.join(a.out, "curve.md"), "w", encoding="utf-8").write("\n".join(md))
    json.dump(summary, open(os.path.join(a.out, "summary.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print("写出", a.out)


if __name__ == "__main__":
    main()
