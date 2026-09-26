#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""统一测试入口（docs/36）。所有运行都是无界面、静音的。

    python tools/check.py              快检（提交前必跑，约 1 分钟）：核心契约测试 + 每名干员冒烟 + 同 seed 复现
    python tools/check.py --bots       快检 + 机器人标准矩阵（starts × 高手 / 普通 × 4 seed，结果缓存）
    python tools/check.py --ab REF     A/B：临时工作树跑 REF，与当前工作区同 seed 对比机器人标准矩阵
    python tools/check.py --only smoke 只跑某一项（core / smoke / nodes / prot / repro）
    python tools/check.py --jobs 4     本次最多同时开 4 个 Godot（全机总数另受 GODOT_MAX_PROCS 限制）
    python tools/check.py --auto       按相对 main 的改动只跑相关项目：只改文档 → 不开 Godot；只改说明字段 → +核心契约；
                                       只改某几名干员 → +这些干员的冒烟 / 成长节点 + 复现；其余 → 全量。合入 main 前仍跑全量

每次快检把每局的完整输出写到 build/check/quick_<时间>/，失败时报告末尾列出失败项、原因和日志路径。
新工作树没有导入缓存时会先自动导入（docs/36 §2.1）。

退出码 0 = 全部通过；1 = 有失败。任何 SCRIPT ERROR / Parse Error 都算失败。

冒烟：每名干员各当一次主控，带两名队友（按名单轮换，每人也都当过队友），开局拿全部藏品、直接推到成长线末端、
技力常满，Boss 提前到 0:30 / 1:00 / 1:30（中期 Boss 按局轮换），跑 2 分钟游戏时间；另有两局不作弊的自然流程
（高手 / 普通机器人，跑过第一个商人）。看的是「有没有报错、能不能跑完」，不看数值。
主控保护：Boss 来源的扣血截断（单发 / 2 秒合计 / 满血保护 / 持续伤害上限，docs/38 §1.11）的脚本测试。
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


# ---------------------------------------------------------------- --auto：按改动文件选项目（docs/44 ②）

# 只改这些字段的 JSON 算「纯文字改动」：说明 / 名字 / 台词，不影响玩法
TEXT_KEYS = {"desc", "name", "en", "cn", "story", "lore", "flavor", "hint", "title", "note", "quote", "text", "tip", "subtitle"}
# 干员范围之外、但改了就要跑全量的角色脚本（基类 / 编队 / 主控）
SHARED_CHAR = {"character", "op_api", "squad", "doctor"}
LEVELS = ["none", "text", "ops", "full"]


def _git(*args):
    r = subprocess.run(["git"] + list(args), cwd=ROOT, capture_output=True, text=True, encoding="utf-8", errors="replace")
    return r.stdout if r.returncode == 0 else ""


def changed_files():
    """相对 main 的改动：merge-base 到 HEAD 的提交 + 工作区未提交的改动 + 未跟踪的新文件。返回 (文件列表, merge-base)"""
    base = _git("merge-base", "HEAD", "main").strip()
    files = set()
    if base and base != _git("rev-parse", "HEAD").strip():
        files |= set(_git("diff", "--name-only", base, "HEAD").split())
    files |= set(_git("diff", "--name-only", "HEAD").split())
    files |= set(_git("ls-files", "--others", "--exclude-standard").split())
    return sorted(f.replace("\\", "/") for f in files if f), base


def _strip_text(o):
    if isinstance(o, dict):
        return {k: _strip_text(v) for k, v in o.items() if k not in TEXT_KEYS}
    if isinstance(o, list):
        return [_strip_text(v) for v in o]
    return o


def _json_text_only(path, base):
    """这个 JSON 相对 base 是否只改了说明类字段"""
    try:
        old = json.loads(_git("show", "%s:%s" % (base or "HEAD", path)) or "null")
        new = json.load(open(os.path.join(ROOT, path), encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return False
    return old is not None and _strip_text(old) == _strip_text(new)


def plan_auto():
    """按改动文件定档：none（不开 Godot）< text（+核心契约）< ops（+相关干员冒烟 / 成长节点 / 复现）< full（全量）。
    返回 (档位, 相关干员集合, 理由列表)"""
    files, base = changed_files()
    if not files:
        return "full", set(), ["相对 main 没有改动可比，跑全量"]
    ids = set(op_ids())
    level, ops, why = "none", set(), []

    def bump(lv, reason):
        nonlocal level
        if LEVELS.index(lv) > LEVELS.index(level):
            level = lv
        why.append("%s → %s" % (reason, lv))

    for p in files:
        name = os.path.basename(p)
        stem = name.split(".")[0]
        if p.startswith("docs/") or p.endswith(".md") or p.endswith((".uid", ".import")):
            bump("none", p)
        elif p.startswith("art/incoming/") and ("preview" in name or name.endswith((".json", ".html", ".txt"))):
            bump("none", p)
        elif p.startswith("art/incoming/op_") and name.endswith(".png"):
            hit = max((o for o in ids if name.startswith("op_" + o + "_") or name.startswith("op_" + o + "@")), key=len, default=None)
            if hit:
                ops.add(hit)
                bump("ops", p)
            else:
                bump("text", p)   # 召唤物等附属帧条（如 op_mon3tr_*）：只影响画面，核心契约即可
        elif p.startswith("game/data/") and name.endswith(".json"):
            if os.path.exists(os.path.join(ROOT, p)) and _json_text_only(p, base):
                bump("text", p + "（只改说明字段）")
            elif p.startswith("game/data/characters/") and stem in ids:
                ops.add(stem)
                bump("ops", p)
            else:
                bump("full", p)
        elif p.startswith("game/scripts/characters/") and name.endswith(".gd"):
            if stem in ids and stem not in SHARED_CHAR:
                ops.add(stem)
                bump("ops", p)
            else:
                bump("full", p)
        else:
            bump("full", p)
    return level, ops, why


def check_static():
    """不开 Godot 的检查：game/data 下所有 JSON 能解析"""
    bad = []
    for p in glob.glob(os.path.join(GAME, "data", "**", "*.json"), recursive=True):
        try:
            json.load(open(p, encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as e:
            bad.append("%s：%s" % (os.path.relpath(p, ROOT), str(e)[:120]))
    return {"name": "数据 JSON 解析", "ok": not bad, "detail": "game/data 全部可解析" if not bad else "%d 个文件解析失败" % len(bad), "errors": bad[:5]}


JOBS = GR.MAX_PROCS   # 本次快检的并行数（main 里按 --jobs 设置）
LOG_DIR = None   # 本次快检的日志目录（main 里设置）；每次启动 Godot 的完整输出都写进去，失败时报告里给路径


def _run(args, timeout, tag):
    """启动一次 Godot（经 godot_runner 的全机并发上限），把 stdout / stderr 写进 LOG_DIR/<tag>.log，返回 (out, err, 超时, 日志路径)"""
    t0 = time.time()
    out, err, to = GR.run_godot(args, timeout)
    path = None
    if LOG_DIR:
        safe = re.sub(r"[^\w.-]+", "_", tag).strip("_") or "run"
        path = os.path.join(LOG_DIR, safe + ".log")
        n = 2
        while os.path.exists(path):
            path = os.path.join(LOG_DIR, "%s_%d.log" % (safe, n))
            n += 1
        with open(path, "w", encoding="utf-8") as fh:
            fh.write("# %s\n# 参数：%s\n# 用时 %.0f 秒%s；结束时全机 Godot %d 个\n\n## stdout\n%s\n\n## stderr\n%s\n" % (
                tag, " ".join(args[1:]), time.time() - t0, "（超时）" if to else "", GR.count_godot(), out, err))
    return out, err, to, path


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
    out, err, to, log = _run([godot, "--headless", "--path", GAME, "-s", "res://tests/test_core.gd"], 300, "core")
    errs = GR.script_errors(out, err)
    m = re.search(r"(\d+) checks, (\d+) failed", out)
    ok = "CORE TESTS PASSED" in out and not errs and not to
    detail = (m.group(0) if m else "没有输出结果")
    fails = re.findall(r"^FAIL: .*$", out + "\n" + err, re.M)
    return {"name": "核心契约测试", "ok": ok, "detail": ("超时 · " if to else "") + detail, "errors": (errs + fails)[:5], "log": log}


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


def ctrl_errors(d):
    """主控保护的自动检查（docs/38 §1.11，BALANCE 的 ctrl，run/combat.gd）：Boss 存活期间主控僵直、atk_slow 恒为 0，
    移速倍率不低于下限 floor"""
    c = (d or {}).get("ctrl") or {}
    errs = []
    if c.get("stun_t", 0) > 0:
        errs.append("主控保护：Boss 存活期间主控僵直 %.2f 秒（应为 0）" % c["stun_t"])
    if c.get("aslow_t", 0) > 0:
        errs.append("主控保护：Boss 存活期间 atk_slow %.2f 秒（应为 0）" % c["aslow_t"])
    if c.get("move_min", 1) < c.get("floor", 0) - 1e-6:
        errs.append("主控保护：Boss 存活期间移速倍率最低 %.2f（应 ≥%.2f）" % (c["move_min"], c["floor"]))
    return errs


def run_case(godot, name, extra, timeout=300):
    t0 = time.time()
    out, err, to, log = _run(godot_args(godot, extra), timeout, name)
    errs = GR.script_errors(out, err)
    d = parse_balance(out)
    errs += ctrl_errors(d)
    ok = d is not None and not errs and not to
    detail = ("超时" if to else ("没有 BALANCE 行" if d is None else "t=%d %s" % (d["t"], "胜" if d.get("win") else "")))
    return {"name": name, "ok": ok, "detail": "%s · %.0fs" % (detail, time.time() - t0), "errors": errs[:3], "data": d, "log": log}


def check_nodes(godot, only=None):
    """成长节点当场生效（tests/node_test.tscn）：每名干员逐个应用 6 个节点，每个节点选下的那一刻必须有东西变化。
    only：只测这些干员（--auto 按改动选）"""
    ids = [o for o in op_ids() if only is None or o in only]

    def one(op):
        out, err, to, log = _run([godot, "--headless", "--path", GAME, "res://tests/node_test.tscn", "--", "--balance", "--seed=1", "--op=" + op], 300, "nodes_" + op)
        lines = re.findall(r"^NODE (\S+) (\d+) (\S+) (\S+) \| imm: (.*?) \| sync: (.*)$", out, re.M)
        empty = [l[3] for l in lines if not l[4].strip() and not l[5].strip()]
        return op, lines, empty, GR.script_errors(out, err), to

    with ThreadPoolExecutor(max(1, min(len(ids), JOBS))) as ex:
        res = list(ex.map(one, ids))
    bad = []
    for op, lines, empty, errs, to in res:
        if to or errs or len(lines) != 6 or empty:
            bad.append("%s：%s" % (op, "超时" if to else (errs[0][:120] if errs else ("节点行数 %d" % len(lines) if len(lines) != 6 else "选下当场没变化的节点 " + "、".join(empty)))))
    bad_logs = [LOG_DIR and os.path.join(LOG_DIR, "nodes_" + op + ".log") for op, lines, empty, errs, to in res if to or errs or len(lines) != 6 or empty]
    return {"log": "、".join(p for p in bad_logs if p), "name": "成长节点当场生效", "ok": not bad, "detail": "%d 名干员 × 6 节点" % len(ids) if not bad else "%d 名干员有问题" % len(bad), "errors": bad[:6]}


def check_prot(godot):
    """主控保护（tests/prot_test.tscn，docs/38 §1.11）：Boss 来源单发 ≤40%、2 秒合计 ≤50%、满血保护、Boss 持续伤害每秒 ≤4%"""
    ids = op_ids()
    out, err, to, log = _run([godot, "--headless", "--path", GAME, "res://tests/prot_test.tscn", "--", "--balance", "--seed=1",
                              "--op=" + ("wisadel" if "wisadel" in ids else ids[0])], 300, "prot")
    errs = GR.script_errors(out, err)
    m = re.search(r"(\d+) checks, (\d+) failed", out)
    fails = re.findall(r"^FAIL: .*$", out + "\n" + err, re.M)
    ok = "PROT TESTS PASSED" in out and not errs and not to
    return {"name": "主控保护", "ok": ok, "detail": "超时" if to else (m.group(0) if m else "没有输出结果"), "errors": (errs + fails)[:5], "log": log}


def check_repro(godot):
    extra = ["--balance", "--seed=7", "--op=wisadel", "--squad=suzuran", "--bot=expert", "--maxt=240"]
    with ThreadPoolExecutor(2) as ex:
        a, b = list(ex.map(lambda k: run_case(godot, "复现_%d" % k, extra), [1, 2]))
    logs = "、".join(x["log"] for x in (a, b) if x.get("log"))
    if not (a["ok"] and b["ok"]):
        why = "；".join("第 %d 局 %s" % (k + 1, x["detail"]) for k, x in enumerate((a, b)) if not x["ok"])
        return {"name": "同 seed 复现", "ok": False, "detail": "有一局没跑完（%s）" % why, "errors": a["errors"] + b["errors"], "log": logs}
    da, db = dict(a["data"]), dict(b["data"])
    da.pop("prof", None)
    db.pop("prof", None)
    # 同屏数量峰值（telemetry peak / peak_min）只观察画面：特效里有绘制时追加的项，两局可能差一两个，不算复现失败
    for d in (da, db):
        if isinstance(d.get("bot"), dict):
            d["bot"] = {k: v for k, v in d["bot"].items() if k not in ("peak", "peak_min")}
    diff = [k for k in sorted(set(da) | set(db)) if da.get(k) != db.get(k)]
    return {"name": "同 seed 复现", "ok": not diff, "detail": "4:00 游戏时间逐字段相同" if not diff else "不同的字段：" + "、".join(diff[:8]), "errors": [], "log": logs}


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


def _same(p, q):
    """两局结果相同：只比两边都有的字段（不含 prof），基准提交之后新加的统计字段（如 ctrl）不算差异"""
    return all(p[k] == q[k] for k in (set(p) & set(q)) - {"prof"})


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
        same = sum(1 for s in seeds if _same(x[s], y[s]))
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
    ap.add_argument("--only", choices=["core", "smoke", "nodes", "prot", "repro"], help="只跑快检里的某一项")
    ap.add_argument("--jobs", type=int, default=GR.MAX_PROCS,
                    help="本次快检最多同时开几个 Godot（缺省 = 全机上限）；全机总数另受 GODOT_MAX_PROCS 限制")
    ap.add_argument("--auto", action="store_true",
                    help="按相对 main 改了哪些文件只跑相关项目（改的过程中用；合入 main 前仍跑全量）")
    a = ap.parse_args()
    global JOBS, LOG_DIR
    JOBS = max(1, a.jobs)
    godot = GR.find_godot()
    GR.ensure_imported(GAME)
    if a.ab:
        ab(a.ab, a.seeds, a.keep)
        return 0
    t0 = time.time()
    LOG_DIR = os.path.join(OUT_DIR, "quick_" + datetime.datetime.now().strftime("%m%d_%H%M%S"))
    os.makedirs(LOG_DIR, exist_ok=True)
    load0 = GR.count_godot()
    print("快检：本次最多 %d 个 Godot 并行（全机上限 %d，开始时全机已有 %d 个）；日志 %s" % (JOBS, GR.MAX_PROCS, load0, LOG_DIR), flush=True)
    jobs = [check_static]
    if a.auto and not a.only:
        level, ops, why = plan_auto()
        print("按改动分级（--auto）：%s%s" % (level, "（干员：%s）" % "、".join(sorted(ops)) if ops else ""), flush=True)
        for w in why[:12]:
            print("    " + w, flush=True)
        if len(why) > 12:
            print("    …… 另 %d 个文件" % (len(why) - 12), flush=True)
        if level != "full":
            print("    注意：分级只用于改的过程中；快进合入 main 前仍要跑全量（不带 --auto）", flush=True)
        if level in ("text", "ops"):
            jobs.append(lambda: check_core(godot))
        if level == "ops":
            jobs += [(lambda c=c: run_case(godot, c[0], c[1])) for c in smoke_cases() if c[0].split(" · ")[-1] in ops]
            jobs.append(lambda: check_nodes(godot, ops))
            jobs.append(lambda: check_repro(godot))
        if level == "full":
            a.auto = False
    if not a.auto:
        if a.only in (None, "core"):
            jobs.append(lambda: check_core(godot))
        if a.only in (None, "smoke"):
            jobs += [(lambda c=c: run_case(godot, c[0], c[1])) for c in smoke_cases()]
        if a.only in (None, "nodes"):
            jobs.append(lambda: check_nodes(godot))
        if a.only in (None, "prot"):
            jobs.append(lambda: check_prot(godot))
        if a.only in (None, "repro"):
            jobs.append(lambda: check_repro(godot))
    with ThreadPoolExecutor(JOBS) as ex:
        results = list(ex.map(lambda f: f(), jobs))
    bad = [r for r in results if not r["ok"]]
    lines = []
    for r in results:
        lines.append("%s %s  %s" % ("通过" if r["ok"] else "失败", r["name"], r["detail"]))
        for e in r.get("errors", []):
            lines.append("      " + e[:220])
    summary = "\n".join(lines) + "\n\n%s：%d 项，失败 %d 项，耗时 %.0f 秒（开始时全机 %d 个 Godot，结束时 %d 个）" % (
        "快检通过" if not bad else "快检失败", len(results), len(bad), time.time() - t0, load0, GR.count_godot())
    if bad:
        # 失败项单独再列一遍：名字、原因、完整日志路径（负载高时偶发失败，事后要能查到是哪项、为什么）
        summary += "\n\n失败项：\n" + "\n".join("  · %s — %s\n    日志：%s" % (r["name"], r["detail"], r.get("log") or "（无）") for r in bad)
    print(summary)
    os.makedirs(OUT_DIR, exist_ok=True)
    open(os.path.join(OUT_DIR, "last_quick.txt"), "w", encoding="utf-8").write(summary + "\n")
    if a.bots and not bad:
        outdir = os.path.join(OUT_DIR, "bots_" + datetime.datetime.now().strftime("%m%d_%H%M"))
        run_matrix(GAME, "bots", outdir, a.seeds)
    return 1 if bad else 0


if __name__ == "__main__":
    # 统一 UTF-8 输出：Windows 下缺省是 GBK，别的会话读到的是乱码，看不出哪项失败
    for _s in (sys.stdout, sys.stderr):
        try:
            _s.reconfigure(encoding="utf-8", errors="replace")
        except (AttributeError, ValueError):
            pass
    sys.exit(main())
