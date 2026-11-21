#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""特效预算汇总（docs/368 §2 的表）：合并静态账（build/fx_budget/static.json）、帧时（perf_<tag>.json）、画面占比（cover*.json），
出 20 人 × 各项表 + 最小 / 25 / 中位 / 75 / 90 / 最大分位，打印 Markdown。不开 Godot。

  python tools/fx_budget_report.py [--perf desk_high] [--cover build/fx_budget/cover_*.json] > build/fx_budget/report.md
"""
import argparse, glob, json, os, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fx_budget as FB
import fx_budget_runtime as FR

OUT = os.path.join(FB.ROOT, "build", "fx_budget")
MOVES = ["atk", "s1", "s2", "s3", "ult"]
ACT_PCT = 0.1   # 生效门槛：覆盖 > 0.1% 屏幕
MOVE_ZH = {"atk": "普攻", "s1": "S1", "s2": "S2", "s3": "S3", "ult": "终结技"}


def stats(xs):
    xs = [x for x in xs if x is not None]
    if not xs:
        return None
    return [min(xs), FB.pct(xs, .25), FB.pct(xs, .5), FB.pct(xs, .75), FB.pct(xs, .9), max(xs)]


def table(rows, cols, fmt="%.1f"):
    out = ["| 干员 | " + " | ".join(c[1] for c in cols) + " |", "|---|" + "---|" * len(cols)]
    for o, r in rows:
        out.append("| %s | " % o + " | ".join("—" if r.get(c[0]) is None else (fmt % r[c[0]]) for c in cols) + " |")
    for i, lab in enumerate(["最小", "25%", "中位", "75%", "90%", "最大"]):
        s = [stats([r.get(c[0]) for _, r in rows]) for c in cols]
        out.append("| **%s** | " % lab + " | ".join("—" if x is None else fmt % x[i] for x in s) + " |")
    return "\n".join(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--perf", default="desk_high")
    ap.add_argument("--cover", nargs="*", default=None)
    a = ap.parse_args()
    perf = json.load(open(os.path.join(OUT, "perf_%s.json" % a.perf), encoding="utf-8"))
    cov = {}
    for p in (a.cover or sorted(glob.glob(os.path.join(OUT, "cover*.json")))):
        cov.update(json.load(open(p, encoding="utf-8")))
    # 普攻 / 技能在图鉴演示里只占屏 0.1–2%，cover 里「生效」门槛 0.5% 太高：按覆盖曲线（每 3 帧一点）用 0.1% 重算生效时长与生效时平均覆盖
    # （无特效时的底噪约 0.05%：本人身上的照地光）
    for o in cov:
        for m, r in cov[o].items():
            cur = r.get("cov_curve") or []
            act = [x for x in cur if x > ACT_PCT]
            r["active_s"] = round(len(act) * 3 / 30.0, 1)
            r["cov_mean_active"] = round(sum(act) / len(act), 2) if act else 0.0
    ops = sorted(o for o in perf)
    # 帧时
    prow = []
    for o in ops:
        r = perf[o]
        d, share = FR.draw_delta(r)
        prow.append((o, {"d": d, "share": share, "dc": r["dc_med"]["d"], "rcpu": r["rcpu_med"]["d"], "gpu": r["gpu_med"]["d"],
                         "ft": r["ft_mean"]["d"], "en": r["en_med"]["on"]}))
    print("## 帧时（本机桌面高画质，后期 8:00 起 90 秒，同局每 30 帧开 / 关该干员特效）\n")
    print(table(prow, [("d", "世界绘制增量 ms"), ("share", "占世界绘制 %"), ("dc", "绘制调用 +"), ("rcpu", "渲染 CPU ms"), ("gpu", "GPU ms"), ("ft", "帧间隔 ms（噪声大）"), ("en", "同屏敌人中位")]))
    # 画面占比，按招
    for key, zh in (("cov_peak_ex", "覆盖峰值 %（去整屏帧）"), ("cov_mean_active", "生效时平均覆盖 %"), ("solid_peak_ex", "实心覆盖峰值 %"),
                    ("solid_mean_active", "生效时实心覆盖 %"), ("dlum_mean_active", "生效时平均亮度增量（0–255）"), ("active_s", "生效时长 秒（6 秒窗口内）"),
                    ("enemy_covered_mean", "敌人被实心盖住 %（均）"), ("flash_frames", "整屏帧数")):
        rows = [(o, {m: cov.get(o, {}).get(m, {}).get(key) for m in MOVES}) for o in ops]
        print("\n## %s\n" % zh)
        print(table(rows, [(m, MOVE_ZH[m]) for m in MOVES], "%.1f" if key != "flash_frames" else "%d"))
    print("\n## 运行时超硬上限（tools/fx_budget.json runtime）\n")
    for o in ops:
        bad = FR.check_runtime(o, perf.get(o), cov.get(o, {}))
        if bad:
            print("- **%s**：%s" % (o, "；".join(bad)))


if __name__ == "__main__":
    main()
