#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""攻速—实际出手频率对照表（docs/335）：20 名干员 × 攻速倍率 1 / 2 / 4，各打木桩 30 秒（技能关），
统计出手次数与动作起手次数，和 1 倍次数 × 倍率的理论值比较，偏差超过 5% 的标出。
  python tools/atk_rate_table.py [--ops a,b] [--mults 1,2,4] [--secs 30] [--jobs 4] [--out build/atk_rate]
批跑放 GCP：tools/gcp/batch.py run <tag> --cmd 'python3 tools/atk_rate_table.py --jobs $GODOT_MAX_PROCS --out $OUT'
"""
import argparse, glob, json, os, re, sys
from concurrent.futures import ThreadPoolExecutor
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import godot_runner as GR

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GAME = os.path.join(ROOT, "game")


def one(godot, op, mult, secs, skills=False, fps=240, timeout=1500):
    args = [godot, "--headless", "--fixed-fps", str(fps), "--path", GAME, "res://tests/atk_rate_test.tscn", "--", "--balance", "--bot=afk", "--nodeath",
            "--seed=1", "--op=" + op, "--rate_op=" + op, "--rate_mult=%g" % mult, "--rate_secs=%g" % secs] + (["--rate_skills"] if skills else [])
    out, err, to = GR.run_godot(args, timeout)
    m = re.search(r"^ATKRATE (\{.*\})\s*$", out, re.M)
    errs = GR.script_errors(out, err)
    return {"op": op, "mult": mult, "rec": json.loads(m.group(1)) if m else None, "errors": errs[:2] + (["超时"] if to else [])}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ops", default="")
    ap.add_argument("--mults", default="1,2,4")
    ap.add_argument("--secs", type=float, default=30)
    ap.add_argument("--skills", action="store_true", help="技能开着：额外按动作条列出窗口 > 出手间隔的次数")
    ap.add_argument("--fps", type=int, default=240, help="固定帧率（--fixed-fps）：越高越没有帧取整误差，60 = 实机")
    ap.add_argument("--jobs", type=int, default=2)
    ap.add_argument("--out", default=os.path.join(ROOT, "build", "atk_rate"))
    a = ap.parse_args()
    ops = a.ops.split(",") if a.ops else sorted(os.path.basename(p)[:-5] for p in glob.glob(os.path.join(GAME, "data", "characters", "*.json")))
    mults = [float(x) for x in a.mults.split(",")]
    os.makedirs(a.out, exist_ok=True)
    godot = GR.find_godot()
    jobs = [(o, m) for o in ops for m in mults]
    with ThreadPoolExecutor(a.jobs) as ex:
        res = list(ex.map(lambda j: one(godot, j[0], j[1], a.secs, a.skills, a.fps), jobs))
    json.dump(res, open(os.path.join(a.out, "atk_rate_skills.json" if a.skills else "atk_rate.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    by = {(r["op"], r["mult"]): r for r in res}
    lines = ["| 干员 | 倍率 | 面板间隔 s | 实测均间隔 s | 理论出手 | 实测出手 | 偏差 | 起手 | 动作窗口 s | 最大间隔 s | 动作窗口÷间隔 |", "|---|---|---|---|---|---|---|---|---|---|---|"]
    bad = []
    for o in ops:
        base = by.get((o, 1.0))
        b = base["rec"]["fires"] if base and base["rec"] else None
        for m in mults:
            r = by[(o, m)]
            rec = r["rec"]
            if not rec:
                lines.append("| %s | %g | — | — | — | 失败 | — | — | — | — | %s |" % (o, m, ";".join(r["errors"])))
                bad.append((o, m, "失败"))
                continue
            theory = b * m if b else None
            dev = (rec["fires"] - theory) / theory if theory else None
            flag = "" if dev is None or abs(dev) <= 0.05 else " ⚠"
            if flag:
                bad.append((o, m, "%+.1f%%" % (dev * 100)))
            ratio = rec["act_dur"] / rec["cd_avg"] if rec["cd_avg"] > 0 else 0
            lines.append("| %s | %g | %s | %.3f | %s | %d | %s%s | %d | %.3f | %.2f | %.2f |" % (
                o, m, ("%.3f" % rec["nominal"]) if rec["nominal"] > 0 else "—", a.secs / max(1, rec["fires"]),
                ("%.1f" % theory) if theory else "—", rec["fires"], ("%+.1f%%" % (dev * 100)) if dev is not None else "—", flag,
                rec["starts"], rec["act_dur"], rec["gap_max"], ratio))
    if a.skills:
        lines += ["", "## 动作条窗口 vs 出手间隔（技能开）", "", "| 干员 | 倍率 | 动作条 | 次数 | 平均窗口 s | 平均间隔 s | 窗口>间隔次数 |", "|---|---|---|---|---|---|---|"]
        for r in res:
            if not r["rec"]:
                continue
            for k, v in sorted(r["rec"].get("by_anim", {}).items()):
                lines.append("| %s | %g | %s | %d | %.3f | %.3f | %d%s |" % (r["op"], r["mult"], k, v["n"], v["dur"] / v["n"], v["cd"] / v["n"], v["over"], " ⚠" if v["over"] > 0 else ""))
    lines += ["", "偏差超过 5%：" + ("无" if not bad else "；".join("%s×%g %s" % x for x in bad))]
    open(os.path.join(a.out, "atk_rate_skills.md" if a.skills else "atk_rate.md"), "w", encoding="utf-8").write("\n".join(lines) + "\n")
    print("\n".join(lines))


if __name__ == "__main__":
    main()
