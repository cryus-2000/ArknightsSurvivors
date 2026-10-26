# -*- coding: utf-8 -*-
"""招募 / 换人出现频率统计（10-26 用户「后期换干员的频率高吗」）：读 balance_run 的原始 JSON（build/balance/<tag>_*.json），
按 0–3:30 / 3:30–7:00 / 7:00–10:00 统计每局：升级面板次数、招募卡 / 换人卡 / 保底招募出现次数、实际换人次数，以及后期每多少秒弹一次换人选择。
用法：python tools/probes/recruit_freq.py build/balance/rf_before_*.json [--md 输出.md]"""
import glob, json, sys, statistics

SEGS = [(0, 210, "0–3:30"), (210, 420, "3:30–7:00"), (420, 600, "7:00–10:00")]


def load(paths):
    runs = []
    for p in paths:
        d = json.load(open(p, encoding="utf-8"))
        for r in d.get("records", []):
            rec = r.get("data") or {}
            if "recruit_offers" in rec:
                runs.append((r.get("bot", "?"), rec))
    return runs


def seg_of(t):
    for a, b, name in SEGS:
        if a <= t < b:
            return name
    return None


def summarize(runs):
    rows = []
    for bot in sorted({b for b, _ in runs}) + ["全部"]:
        sel = [rec for b, rec in runs if bot == "全部" or b == bot]
        if not sel:
            continue
        for a, b, name in SEGS:
            lv = [sum(1 for t in rec.get("levelup_t", []) if a <= t < b) for rec in sel]
            rc = [sum(1 for o in rec["recruit_offers"] if a <= o[0] < b and o[1] == "recruit") for rec in sel]
            sw = [sum(1 for o in rec["recruit_offers"] if a <= o[0] < b and o[1] == "swap") for rec in sel]
            fo = [sum(1 for o in rec["recruit_offers"] if a <= o[0] < b and o[1] == "forced") for rec in sel]
            ac = [sum(1 for s in rec.get("swaps", []) if a <= s[0] < b) for rec in sel]
            m = lambda xs: statistics.mean(xs) if xs else 0.0
            sw_m = m(sw)
            rows.append([bot, name, len(sel), m(lv), m(rc), sw_m, m(fo), m(ac), (b - a) / sw_m if sw_m > 0 else float("inf"),
                         (m(sw) + m(rc) + m(fo)) / m(lv) if m(lv) > 0 else 0.0])
    return rows


def table(rows):
    out = ["| 机器人 | 时段 | 局数 | 升级面板 | 招募卡 | 换人卡 | 保底招募 | 实际换人 | 换人卡间隔（秒） | 含招募 / 换人的面板占比 |", "|---|---|---|---|---|---|---|---|---|---|"]
    for r in rows:
        out.append("| %s | %s | %d | %.1f | %.1f | %.1f | %.1f | %.2f | %s | %.0f%% |" % (r[0], r[1], r[2], r[3], r[4], r[5], r[6], r[7], "—" if r[8] == float("inf") else "%.0f" % r[8], r[9] * 100))
    return "\n".join(out)


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    paths = sorted(set(sum((glob.glob(a) for a in args), [])))
    runs = load(paths)
    print("局数", len(runs))
    t = table(summarize(runs))
    print(t)
