# -*- coding: utf-8 -*-
"""鸭爵统计（docs/331 §9，11-11）：读 balance_run 结果里的 duck 遥测，比出场次数、打倒率、用时、受击次数、出场时刻、和 Boss 重叠、藏品数。
用法：python tools/duck_stats_1111.py 改前m0=<dir> 改后m0=<dir> ...   只读结果。"""
import glob, json, os, statistics as S, sys
from collections import defaultdict

sys.stdout.reconfigure(encoding="utf-8")


def q(v, p):
    v = sorted(v)
    return v[int(p * (len(v) - 1))] if v else float("nan")


def load(d):
    out = []
    for f in glob.glob(os.path.join(d, "**", "*.json"), recursive=True):
        j = json.load(open(f, encoding="utf-8"))
        if isinstance(j, dict):
            for w in j.get("records", []):
                r = w.get("data") or {}
                if r:
                    r["_pl"] = w.get("placebo", 0)
                    out.append(r)
    return out


def main():
    res = {}
    for arg in sys.argv[1:]:
        lab, d = arg.split("=", 1)
        R = load(d)
        sp = ki = fl = ov = 0
        kt, kh, st, fh = [], [], [], []
        per = defaultdict(int)
        seg = defaultdict(lambda: [0, 0, []])   # 出场时段 → [出场, 打倒, 用时]
        relics, wins = [], []
        for r in R:
            dk = r.get("duck", {})
            sp += dk.get("spawned", 0); ki += dk.get("killed", 0); fl += dk.get("fled", 0); ov += dk.get("boss_overlap", 0)
            kt += dk.get("kill_t", []); kh += dk.get("kill_hits", []); st += dk.get("spawn_t", []); fh += dk.get("fled_hp", [])
            per[dk.get("spawned", 0)] += 1
            relics.append(r.get("relics", 0)); wins.append(1 if r.get("win") else 0)
        # 出场时段：按出场时刻分 3:30 前 / 3:30–7 / 7–10 / 10 后（只有新遥测有 spawn_t）
        res[lab] = {"局": len(R), "胜率": round(100 * S.mean(wins), 1), "每局出场": round(sp / max(1, len(R)), 2), "出场分布": dict(sorted(per.items())),
                    "打倒率": round(100 * ki / max(1, sp), 1), "溜走": fl, "溜走时剩血中位": q(fh, .5) if fh else None,
                    "用时 P10/中位/P90": (q(kt, .1), q(kt, .5), q(kt, .9)), "≤1 秒": round(100 * sum(1 for x in kt if x <= 1) / max(1, len(kt)), 1),
                    "≤3 秒": round(100 * sum(1 for x in kt if x <= 3) / max(1, len(kt)), 1),
                    "受击 P10/中位/P90": (q(kh, .1), q(kh, .5), q(kh, .9)) if kh else None, "1–2 下死": round(100 * sum(1 for x in kh if x <= 2) / max(1, len(kh)), 1) if kh else None,
                    "出场时刻 P10/中位/P90": (q(st, .1), q(st, .5), q(st, .9)) if st else None,
                    "与 Boss 重叠": ov, "藏品数中位 / 均": (S.median(relics), round(S.mean(relics), 1))}
        print(lab, json.dumps(res[lab], ensure_ascii=False))
    out = os.path.join("Claude outputs", "balance_audit_1110", "duck_1111.json")
    json.dump(res, open(out, "w", encoding="utf-8"), ensure_ascii=False, indent=1)


if __name__ == "__main__":
    main()
