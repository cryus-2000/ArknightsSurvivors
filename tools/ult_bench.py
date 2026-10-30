"""终结技对齐表（docs/198 §3.4）：每人跑一次 --ultbench（无头），汇总成表。
用法：python tools/ult_bench.py [--ops texas,exusiai,skalter,kaltsit,ulpianus] [--cluster | --area] [--jobs 3] [--extra "--bal=…"] [--json 文件]
--area：判定面积（打不死的密格假人，各段并集，单位千平方像素）、质心离队长距离、最远一格、伤害合计；--json 把每人均值另存一份
输出：每人 4 个瞄准方向的平均（屏内小怪倒下% / 其中普通 / 重型、精英平均掉血%、中期 Boss 掉血%、按下到最后一次伤害秒数、占位图形峰值）
与对齐标准（小怪 45–55%、20 人极差 ≤ 12、精英 40±5、Boss 8±2、瞬发 ≤ 1.2 秒 / 短持续 ≤ 3.5 秒）的比较。"""
import argparse
import json
import os
import shlex
import sys
from concurrent.futures import ThreadPoolExecutor

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import godot_runner as GR  # noqa: E402

sys.stdout.reconfigure(encoding="utf-8")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GAME = os.path.join(ROOT, "game")


def one(op, cluster, extra, area=False):
    args = [GR.find_godot(), "--headless", "--path", GAME, "--fixed-fps", "60", "--audio-driver", "Dummy", "--",
            "--balance", "--seed=1", "--bot=expert", "--op=" + op, "--maxt=900", "--ultbench" + ("=area" if area else ("=cluster" if cluster else ""))] + extra
    out, err, to = GR.run_godot(args, 600)
    rows, avg = [], None
    for ln in out.splitlines():
        if ln.startswith("ULTBENCH_AVG "):
            avg = json.loads(ln[13:])
        elif ln.startswith("ULTBENCH "):
            rows.append(json.loads(ln[9:]))
    return op, rows, avg, GR.script_errors(out, err)[:3], to


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ops", default="texas,exusiai,skalter,kaltsit,ulpianus")
    ap.add_argument("--cluster", action="store_true")
    ap.add_argument("--jobs", type=int, default=3)
    ap.add_argument("--extra", default="")
    ap.add_argument("--rows", action="store_true", help="另打印每个瞄准方向的明细")
    ap.add_argument("--area", action="store_true")
    ap.add_argument("--t", type=float, default=-1.0)
    ap.add_argument("--json", default="")
    a = ap.parse_args()
    extra = shlex.split(a.extra) + (["--ub_t=%g" % a.t] if a.t >= 0 else [])
    with ThreadPoolExecutor(a.jobs) as ex:
        res = list(ex.map(lambda op: one(op, a.cluster, extra, a.area), a.ops.split(",")))
    if a.json:
        with open(a.json, "w", encoding="utf-8") as f:
            json.dump({op: {"avg": avg, "rows": rows} for op, rows, avg, errs, to in res}, f, ensure_ascii=False, indent=1)
    if a.area:
        print("| 干员 | 面积 千平方像素 | 其中屏内 | 命中格 | 质心离队长 | 最远 | 伤害合计 ×基准生命 | 时长 秒 |")
        print("|---|---|---|---|---|---|---|---|")
        for op, rows, avg, errs, to in res:
            if avg is None:
                print("| %s | 失败 %s %s |" % (op, "超时" if to else "", errs))
                continue
            print("| %s | %.0f | %.0f | %.0f | %.0f | %.0f | %.1f | %.2f |" % (op, avg["area_k"], avg.get("view_k", 0), avg["hit_n"], avg["cen_d"], avg["far"], avg["dmg"], avg["dur"]))
            if a.rows:
                for r in rows:
                    print("|  · %s | %.0f | %.0f | %d | %.0f | %.0f | %.1f | %.2f |" % (r["aim"], r["area_k"], r.get("view_k", 0), r["hit_n"], r["cen_d"], r["far"], r["dmg"], r["dur"]))
            for e in errs:
                print("ERR", op, e)
        return
    print("| 干员 | 屏内小怪倒下 | 普通 | 重型 | 精英掉血 | 中期 Boss | 时长 秒 | 图形峰值 | 命中小怪 | 伤害合计 | 范围内清光 |")
    print("|---|---|---|---|---|---|---|---|---|---|---|")
    mins = []
    for op, rows, avg, errs, to in res:
        if avg is None:
            print("| %s | 失败 %s %s |" % (op, "超时" if to else "", errs))
            continue
        mins.append(avg["minion"])
        print("| %s | %.1f%% | %.1f%% | %.1f%% | %.1f%% | %.1f%% | %.2f | %d | %.1f | %.1f | %.1f%% |" % (op, avg["minion"], avg["normal"], avg["heavy"], avg["elite"], avg["boss"], avg["dur"], avg["shapes_peak"], avg.get("hit_n", 0), avg.get("dmg", 0), avg.get("clear", 0)))
        if avg.get("by"):
            print("|  · 各种类 倒下/被打到 | " + "，".join("%s %d/%d" % (k, v[0], v[1]) for k, v in sorted(avg["by"].items())) + " |")
        if a.rows:
            for r in rows:
                print("|  · %s | %.1f%% | %.1f%% | %.1f%% | %.1f%% | %.1f%% | %.2f | %d |" % (r["aim"], r["minion"], r["normal"], r["heavy"], r["elite"], r["boss"], r["dur"], r["shapes_peak"]))
        for e in errs:
            print("ERR", op, e)
    if mins:
        print("小怪倒下极差 %.1f 点（目标 ≤ 12；%s 档目标 %s）" % (max(mins) - min(mins), "聚怪" if a.cluster else "均匀", "≤ 75%" if a.cluster else "45–55%"))


if __name__ == "__main__":
    main()
