#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""攻速探针（11-09 用户「确保攻速真的有变快」）：同一干员、同一 seed，攻速 +0% / +30% / +60% 各打一段木桩，
量实际出手频率与动作时长，确认出手频率按比例提高（不是只改了数值、动画或冷却其中一个）。

复用 tests/op_dummy_test.tscn（--dummy_aspd=x 给被测干员额外 op_aspd +x），单体木桩、主控身份、E0。
每局输出：atk_n（攻击动作开始次数）、atk_dur（平均动作时长）、basic_hit_frames（普攻命中帧数）、dps_basic。
判定：频率指标取普攻命中帧数（≥ 8 时；atk_n 在动作被压缩后会数漏），召唤物出伤的取召唤物秒伤，否则退到 atk_n、普攻秒伤；
  实测倍率 / 期望倍率（1.3、1.6）低于 TOL 就判「没跟上」。

用法（仓库根目录）：
    python tools/aspd_probe.py                     # 全员
    python tools/aspd_probe.py --ops texas,lumen --secs 30
结果：build/aspd_probe/result.json + 控制台表格。串行（本机 Godot 限流）。
"""
import argparse, glob, json, os, re, sys, time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import godot_runner as GR

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GAME = os.path.join(ROOT, "game")
OUT = os.path.join(ROOT, "build", "aspd_probe")
LEVELS = [0.0, 0.3, 0.6]
TOL = 0.85


def ops_all():
    out = []
    for p in sorted(glob.glob(os.path.join(GAME, "data", "characters", "*.json"))):
        d = json.load(open(p, encoding="utf-8"))
        if d.get("id") and d.get("id") != "doctor":
            out.append(d["id"])
    return out


def run(godot, op, add, secs, warm, timeout):
    args = [godot, "--headless", "--path", GAME, "res://tests/op_dummy_test.tscn", "--",
            "--balance", "--bot=afk", "--nodeath", "--seed=1", "--op=" + op,
            "--dummy_op=" + op, "--dummy_role=leader", "--dummy_scene=single", "--dummy_stage=0",
            "--dummy_secs=%g" % secs, "--dummy_warm=%g" % warm, "--dummy_aspd=%g" % add]
    out, err, to = GR.run_godot(args, timeout)
    m = re.search(r"^DUMMY (\{.*\})\s*$", out, re.M)
    return (json.loads(m.group(1)) if m else None), GR.script_errors(out, err), to


def metric(rec):
    if rec["dps_basic"] <= 0.0 and rec.get("dps_summon", 0.0) > 0.0:   # 召唤物出伤的（凯尔希 Mon3tr）
        return "dps_summon", float(rec["dps_summon"])
    if rec["basic_hit_frames"] >= 8:   # 命中帧数最可靠：动作压缩后攻击计时不再往上跳，atk_n 会数漏（11-09 实测）
        return "hit_frames", float(rec["basic_hit_frames"])
    if rec["atk_n"] >= 8:
        return "atk_n", float(rec["atk_n"])
    return "dps_basic", float(rec["dps_basic"])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ops", default="")
    ap.add_argument("--secs", type=float, default=30.0)
    ap.add_argument("--warm", type=float, default=5.0)
    ap.add_argument("--timeout", type=float, default=240.0)
    a = ap.parse_args()
    ops = a.ops.split(",") if a.ops else ops_all()
    godot = GR.find_godot()
    os.makedirs(OUT, exist_ok=True)
    res = {}
    for op in ops:
        res[op] = {}
        for add in LEVELS:
            rec, errs, to = run(godot, op, add, a.secs, a.warm, a.timeout)
            res[op][str(add)] = rec if rec else {"error": (errs[:2] if errs else []) + (["timeout"] if to else [])}
            print(op, add, "ok" if rec else res[op][str(add)], flush=True)
        json.dump(res, open(os.path.join(OUT, "result.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    # 汇总
    bad = []
    print("\n干员 | 指标 | +0% | +30%（倍率） | +60%（倍率） | 动作时长 0→60% | 判定")
    for op in ops:
        r = res[op]
        if any("error" in r[str(x)] for x in LEVELS):
            print(op, "| 运行失败", r)
            bad.append((op, "运行失败"))
            continue
        k, base = metric(r["0.0"])
        key = {"atk_n": "atk_n", "hit_frames": "basic_hit_frames", "dps_basic": "dps_basic", "dps_summon": "dps_summon"}[k]
        vals = [base] + [float(r[str(x)][key]) for x in LEVELS[1:]]
        rat = [v / base if base > 0 else 0.0 for v in vals]
        ok = base > 0 and rat[1] >= 1.3 * TOL and rat[2] >= 1.6 * TOL
        verdict = "过" if ok else "没跟上"
        if not ok:
            bad.append((op, "倍率 %.2f / %.2f（%s）" % (rat[1], rat[2], k)))
        print("%s | %s | %.0f | %.0f（×%.2f） | %.0f（×%.2f） | %.3f→%.3f | %s" % (
            op, k, vals[0], vals[1], rat[1], vals[2], rat[2], r["0.0"]["atk_dur"], r["0.6"]["atk_dur"], verdict))
    print("\n没跟上：", bad if bad else "无")
    json.dump({"result": res, "bad": bad}, open(os.path.join(OUT, "result.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)


if __name__ == "__main__":
    main()
