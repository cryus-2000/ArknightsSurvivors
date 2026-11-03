# -*- coding: utf-8 -*-
"""pixelfx 放开版开关前后同种子 TRACE 配对（docs/242 §14.21）：同一份代码，fx/px_unleashed 0 / 1 各跑两局，逐行比 TRACE。

两局：后期局 seed 13、560 秒；终结技局 seed 7、240 秒（--maxprog --sptest，第 20 秒充满终结技）。都带 --nodeath。
开跑前（组长 11-04：索引没跟上时新帧条一张都加载不到，「一致」是假的）：核对 game/art/index.json 与磁盘，不一致就重建（tools/asset_index.py），
再确认导入缓存（godot_runner.ensure_imported），然后数这名干员在索引里的放开版帧条（名字含 _ul_ 且含干员 id），打印「放开版帧条已加载 N 张」，N = 0 直接判 FAIL。
比对：TRACE 行必须逐行相同；BALANCE 汇总行去掉纯画面统计（同屏特效 / 飘字峰值 peak / peak_min、性能计数 prof / fx_peak / draw）后也要相同。
原型：星熊会话 build/trace_ab_hs.py（11-04 收成公共工具）。本机机器紧时请放云端例行任务跑（docs/36 §7、docs/41）。

用法：python tools/px_trace_ab.py <干员> [--squad a,b] [--cases late,ult] [--jobs 4] [--out 结果.json]
退出码：0 = 全部一致（打印 PX_TRACE_AB PASS）；1 = 有差异或跑失败（PX_TRACE_AB FAIL）
"""
import argparse, json, os, sys
from concurrent.futures import ThreadPoolExecutor

TOOLS = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, TOOLS)
import trace_base as TB
import asset_index as AI
import godot_runner as GR

GAME = os.path.join(os.path.dirname(TOOLS), "game")
CASES = {
    "late": (13, 560, ["--nodeath"]),
    "ult": (7, 240, ["--nodeath", "--maxprog", "--sptest", "--bal=ult/test_fill_at=20"]),
}
VIS_KEYS = ("peak", "peak_min", "prof", "fx_peak", "draw")   # BALANCE 里只跟画面有关的字段


def _strip_vis(d):
    if isinstance(d, dict):
        return {k: _strip_vis(v) for k, v in d.items() if k not in VIS_KEYS}
    if isinstance(d, list):
        return [_strip_vis(x) for x in d]
    return d


def _bal(lines):
    for ln in reversed(lines):
        if ln.startswith("BALANCE "):
            try:
                return _strip_vis(json.loads(ln[8:]))
            except ValueError:
                return ln
    return None


def _diff_keys(a, b, p=""):
    if isinstance(a, dict) and isinstance(b, dict):
        out = []
        for k in sorted(set(a) | set(b)):
            out += _diff_keys(a.get(k), b.get(k), p + "/" + k)
        return out
    return [p] if a != b else []


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("op")
    ap.add_argument("--squad", default="")
    ap.add_argument("--cases", default="late,ult")
    ap.add_argument("--jobs", type=int, default=4)
    ap.add_argument("--out", default="")
    a = ap.parse_args()
    sq = ["--squad=" + a.squad] if a.squad else []
    errs = AI.check()
    if errs:
        print("贴图索引和磁盘不一致，先重建：" + "；".join(errs[:2]))
        idx, _ = AI.build()
        with open(AI.INDEX, "w", encoding="utf-8", newline="\n") as fh:
            fh.write(AI.dump(idx))
    GR.ensure_imported(GAME)
    idx = json.load(open(AI.INDEX, encoding="utf-8"))
    n_ul = len([k for k in idx if "_ul_" in k and a.op in k and "@2x" not in k])
    print("放开版帧条已加载 %d 张（索引里名字含 _ul_ 与 %s）" % (n_ul, a.op))
    if n_ul == 0:
        print("PX_TRACE_AB FAIL（这名干员没有放开版帧条进索引，开关 1 的画面分支走不到，比对没有意义）")
        sys.exit(1)
    jobs = [(c, sw) for c in a.cases.split(",") if c in CASES for sw in (0, 1)]

    def run(j):
        c, sw = j
        seed, dur, ex = CASES[c]
        lines, err = TB.run_trace(GAME, seed, a.op, dur, ex + sq + ["--bal=fx/px_unleashed=%d" % sw])
        return j, lines or [], err

    with ThreadPoolExecutor(max(1, a.jobs)) as ex:
        res = {j: (lines, err) for j, lines, err in ex.map(run, jobs)}
    ok = True
    report = {"op": a.op, "squad": a.squad, "ul_strips": n_ul, "cases": {}}
    for c in a.cases.split(","):
        if c not in CASES:
            continue
        seed, dur, _ = CASES[c]
        (l0, e0), (l1, e1) = res[(c, 0)], res[(c, 1)]
        if e0 or e1:
            print("%s seed %d %ds：跑失败 %s / %s" % (c, seed, dur, e0, e1))
            report["cases"][c] = {"error": [e0, e1]}
            ok = False
            continue
        t0 = [x for x in l0 if x.startswith("TRACE")]
        t1 = [x for x in l1 if x.startswith("TRACE")]
        first = next((i for i, (x, y) in enumerate(zip(t0, t1)) if x != y), None)
        same = t0 == t1 and len(t0) > 0
        bd = _diff_keys(_bal(l0), _bal(l1))
        print("%s seed %d %ds：TRACE %d / %d 行 %s；BALANCE（去掉画面统计）%s" % (c, seed, dur, len(t0), len(t1),
              "逐行一致" if same else "不一致，首差第 %s 行" % first, "一致" if not bd else "差在 " + "、".join(bd[:6])))
        if first is not None:
            print("  关：" + t0[first][:200])
            print("  开：" + t1[first][:200])
        report["cases"][c] = {"seed": seed, "secs": dur, "trace_lines": [len(t0), len(t1)], "trace_same": same, "first_diff": first, "balance_diff": bd}
        ok &= same and not bd
    report["pass"] = ok
    if a.out:
        json.dump(report, open(a.out, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print("PX_TRACE_AB", "PASS" if ok else "FAIL")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
