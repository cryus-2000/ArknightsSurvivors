#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""统一测试入口（docs/36）。所有运行都是无界面、静音的。

    python tools/check.py              快检（提交前必跑，约 1 分钟）：核心契约测试 + 每名干员冒烟 + 同 seed 复现
    python tools/check.py --bots       快检 + 机器人标准矩阵（starts × 高手 / 普通 × 4 seed，结果缓存）
    python tools/check.py --ab REF     A/B：临时工作树跑 REF，与当前工作区同 seed 对比机器人标准矩阵
    python tools/check.py --only smoke 只跑某一项（core / smoke / repro）

退出码 0 = 全部通过；1 = 有失败。任何 SCRIPT ERROR / Parse Error 都算失败。

冒烟：每名干员各当一次主控，带两名队友（按名单轮换，每人也都当过队友），开局拿全部藏品、直接推到成长线末端、
技力常满，Boss 提前到 0:30 / 1:00 / 1:30（中期 Boss 按局轮换），跑 2 分钟游戏时间；另有两局不作弊的自然流程
（高手 / 普通机器人，跑过第一个商人）。看的是「有没有报错、能不能跑完」，不看数值。
复现：同一组参数跑两次，BALANCE 结果必须逐字段相同（docs/36 §3）。
"""
import argparse, datetime, glob, json, os, re, shutil, statistics, subprocess, sys, tempfile, time
from concurrent.futures import ThreadPoolExecutor

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import godot_runner as GR

ROOT = GR.ROOT
GAME = os.path.join(ROOT, "game")
OUT_DIR = os.path.join(ROOT, "build", "check")


def op_ids(game=GAME):
    return sorted(os.path.basename(p)[:-5] for p in glob.glob(os.path.join(game, "data", "characters", "*.json")))


def godot_args(godot, extra, game=GAME):
    return [godot, "--headless", "--path", game, "--"] + extra


def parse_balance(out):
    m = re.search(r"^BALANCE (\{.*\})\s*$", out, re.M)
    if not m:
        return None
    try:
        return json.loads(m.group(1))
    except json.JSONDecodeError:
        return None


# ---------------------------------------------------------------- 各项检查

def check_core(godot):
    out, err, to = GR.run_godot([godot, "--headless", "--path", GAME, "-s", "res://tests/test_core.gd"], 300)
    errs = GR.script_errors(out, err)
    m = re.search(r"(\d+) checks, (\d+) failed", out)
    ok = "CORE TESTS PASSED" in out and not errs and not to
    detail = (m.group(0) if m else "没有输出结果")
    fails = re.findall(r"^FAIL: .*$", out + "\n" + err, re.M)
    return {"name": "核心契约测试", "ok": ok, "detail": detail, "errors": (errs + fails)[:5]}


def smoke_cases():
    ids = op_ids()
    n = len(ids)
    cases = []
    for k, op in enumerate(ids):
        mates = [ids[(k + 1) % n], ids[(k + 5) % n]]
        cases.append(("冒烟 · " + op, ["--balance", "--seed=1", "--op=" + op, "--squad=" + ",".join(mates), "--bot=expert",
                                      "--maxt=120", "--relics=all", "--maxprog", "--sptest", "--bosstimes=30,60,90", "--forceboss=%d" % (k % 5)]))
    cases.append(("自然流程 · 高手", ["--balance", "--seed=2", "--op=" + ids[0], "--bot=expert", "--maxt=150"]))
    cases.append(("自然流程 · 普通", ["--balance", "--seed=3", "--op=" + ids[-1], "--bot=normal", "--maxt=150"]))
    return cases


def run_case(godot, name, extra, timeout=300):
    t0 = time.time()
    out, err, to = GR.run_godot(godot_args(godot, extra), timeout)
    errs = GR.script_errors(out, err)
    d = parse_balance(out)
    ok = d is not None and not errs and not to
    detail = ("超时" if to else ("没有 BALANCE 行" if d is None else "t=%d %s" % (d["t"], "胜" if d.get("win") else "")))
    return {"name": name, "ok": ok, "detail": "%s · %.0fs" % (detail, time.time() - t0), "errors": errs[:3], "data": d}


def check_repro(godot):
    extra = ["--balance", "--seed=7", "--op=wisadel", "--squad=suzuran", "--bot=expert", "--maxt=240"]
    with ThreadPoolExecutor(2) as ex:
        a, b = list(ex.map(lambda _: run_case(godot, "复现", extra), [0, 1]))
    if not (a["ok"] and b["ok"]):
        return {"name": "同 seed 复现", "ok": False, "detail": "有一局没跑完", "errors": a["errors"] + b["errors"]}
    da, db = dict(a["data"]), dict(b["data"])
    da.pop("prof", None)
    db.pop("prof", None)
    diff = [k for k in sorted(set(da) | set(db)) if da.get(k) != db.get(k)]
    return {"name": "同 seed 复现", "ok": not diff, "detail": "4:00 游戏时间逐字段相同" if not diff else "不同的字段：" + "、".join(diff[:8]), "errors": []}


# ---------------------------------------------------------------- 机器人矩阵 / A/B

def run_matrix(game, tag, outdir, seeds=4, bots="expert,normal", preset="starts", extra=None):
    os.makedirs(outdir, exist_ok=True)
    cmd = [sys.executable, os.path.join(ROOT, "tools", "balance_run.py"), "--preset", preset, "--bots", bots, "--seeds", str(seeds),
           "--tag", tag, "--game", game, "--out", outdir]
    if extra:
        cmd += ["--extra=" + extra]
    subprocess.run(cmd, cwd=ROOT)
    files = sorted(glob.glob(os.path.join(outdir, tag + "_*.json")), key=os.path.getmtime)
    return json.load(open(files[-1], encoding="utf-8"))["records"] if files else []


def _fmt(t):
    return "%d:%02d" % (int(t) // 60, int(t) % 60)


def compare(base, head):
    """按 机器人 × 开局 对比胜率 / 存活 / 终局等级；配对 seed 算出变化的局数"""
    def group(recs):
        g = {}
        for r in recs:
            if "data" in r:
                g.setdefault((r["bot"], r["squad"][0]), {})[r["seed"]] = r["data"]
        return g
    a, b = group(base), group(head)
    lines = ["| 机器人 | 开局 | 胜率 前 | 胜率 后 | 存活 前 | 存活 后 | 等级 前 | 等级 后 | 结果完全相同的局 |", "|---|---|---|---|---|---|---|---|---|"]
    tot = {}
    for key in sorted(set(a) & set(b)):
        x, y = a[key], b[key]
        seeds = sorted(set(x) & set(y))
        if not seeds:
            continue
        same = sum(1 for s in seeds if {k: v for k, v in x[s].items() if k != "prof"} == {k: v for k, v in y[s].items() if k != "prof"})
        row = []
        for d in (x, y):
            ds = [d[s] for s in seeds]
            row.append((sum(1 for q in ds if q.get("win")) / len(ds), statistics.mean(q["t"] for q in ds), statistics.mean(q["lv"] for q in ds)))
        lines.append("| %s | %s | %d%% | %d%% | %s | %s | %.1f | %.1f | %d / %d |" % (key[0], key[1], row[0][0] * 100, row[1][0] * 100,
                     _fmt(row[0][1]), _fmt(row[1][1]), row[0][2], row[1][2], same, len(seeds)))
        t = tot.setdefault(key[0], [[], [], 0, 0])
        t[0] += [x[s] for s in seeds]
        t[1] += [y[s] for s in seeds]
        t[2] += same
        t[3] += len(seeds)
    for bot, (x, y, same, n) in tot.items():
        wa = sum(1 for q in x if q.get("win")) / len(x)
        wb = sum(1 for q in y if q.get("win")) / len(y)
        lines.append("| **%s 合计** | | %d%% | %d%% | %s | %s | %.1f | %.1f | %d / %d |" % (bot, wa * 100, wb * 100,
                     _fmt(statistics.mean(q["t"] for q in x)), _fmt(statistics.mean(q["t"] for q in y)),
                     statistics.mean(q["lv"] for q in x), statistics.mean(q["lv"] for q in y), same, n))
    return "\n".join(lines)


def ab(ref, seeds, keep):
    croot = GR.common_root()
    sha = subprocess.run(["git", "rev-parse", "--short", ref], cwd=ROOT, capture_output=True, text=True).stdout.strip()
    if not sha:
        sys.exit("找不到提交：" + ref)
    wt = os.path.join(croot, ".claude", "worktrees", "ab-" + sha)
    made = False
    if not os.path.isdir(wt):
        subprocess.run(["git", "worktree", "add", "--detach", wt, sha], cwd=ROOT, check=True)
        made = True
        # 拷导入缓存，免得临时工作树第一次启动重新导入全部资源
        src = os.path.join(GAME, ".godot")
        if os.path.isdir(src) and not os.path.isdir(os.path.join(wt, "game", ".godot")):
            shutil.copytree(src, os.path.join(wt, "game", ".godot"))
    outdir = os.path.join(OUT_DIR, "ab_" + datetime.datetime.now().strftime("%m%d_%H%M"))
    print("A/B：基准 %s（%s） vs 当前工作区；机器人标准矩阵 × %d seed" % (ref, sha, seeds), flush=True)
    base = run_matrix(os.path.join(wt, "game"), "base_" + sha, outdir, seeds)
    head = run_matrix(GAME, "head", outdir, seeds)
    table = compare(base, head)
    print("\n" + table)
    open(os.path.join(outdir, "compare.md"), "w", encoding="utf-8").write("# A/B %s vs 工作区\n\n%s\n" % (sha, table))
    print("\n写入", os.path.join(outdir, "compare.md"))
    if made and not keep:
        subprocess.run(["git", "worktree", "remove", "--force", wt], cwd=ROOT)


# ---------------------------------------------------------------- 主流程

def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--bots", action="store_true", help="快检之后再跑机器人标准矩阵")
    ap.add_argument("--ab", metavar="REF", help="与某个提交做 A/B 对比（机器人标准矩阵）")
    ap.add_argument("--seeds", type=int, default=4)
    ap.add_argument("--keep", action="store_true", help="A/B 结束后保留临时工作树")
    ap.add_argument("--only", choices=["core", "smoke", "repro"], help="只跑快检里的某一项")
    a = ap.parse_args()
    godot = GR.find_godot()
    if a.ab:
        ab(a.ab, a.seeds, a.keep)
        return 0
    t0 = time.time()
    print("快检：全机并发上限 %d 个 Godot" % GR.MAX_PROCS, flush=True)
    jobs = []
    if a.only in (None, "core"):
        jobs.append(lambda: check_core(godot))
    if a.only in (None, "smoke"):
        jobs += [(lambda c=c: run_case(godot, c[0], c[1])) for c in smoke_cases()]
    if a.only in (None, "repro"):
        jobs.append(lambda: check_repro(godot))
    with ThreadPoolExecutor(max(1, GR.MAX_PROCS)) as ex:
        results = list(ex.map(lambda f: f(), jobs))
    bad = [r for r in results if not r["ok"]]
    lines = []
    for r in results:
        lines.append("%s %s  %s" % ("通过" if r["ok"] else "失败", r["name"], r["detail"]))
        for e in r.get("errors", []):
            lines.append("      " + e[:220])
    summary = "\n".join(lines) + "\n\n%s：%d 项，失败 %d 项，耗时 %.0f 秒" % ("快检通过" if not bad else "快检失败", len(results), len(bad), time.time() - t0)
    print(summary)
    os.makedirs(OUT_DIR, exist_ok=True)
    open(os.path.join(OUT_DIR, "last_quick.txt"), "w", encoding="utf-8").write(summary + "\n")
    if a.bots and not bad:
        outdir = os.path.join(OUT_DIR, "bots_" + datetime.datetime.now().strftime("%m%d_%H%M"))
        run_matrix(GAME, "bots", outdir, a.seeds)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
