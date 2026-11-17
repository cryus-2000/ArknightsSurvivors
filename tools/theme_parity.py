# -*- coding: utf-8 -*-
"""主题重构同种子对照基准（docs/359 §1）：固定一组局，两次提交逐帧逐字段比，有一处不同就失败。

用法：
    python tools/theme_parity.py                       # 基线 = main（缓存），当前工作树各跑全套，逐字段比
    python tools/theme_parity.py --ref <提交>          # 基线换成别的提交
    python tools/theme_parity.py --self                # 当前工作树自己跑两遍（查噪声 / 不确定性）
    python tools/theme_parity.py --cases short,boss    # 只跑部分局（名字见 CASES）
    python tools/theme_parity.py record <目录>         # 只在当前工作树录一套（云端 / GCP 用），每局一个 <名字>.txt
    python tools/theme_parity.py compare <目录A> <目录B>   # 比两套录好的结果

每局跑 `--headless --balance --seed=S --op=… --bot=expert --trace=1 --parity=N [附加]`，收三种行：
  PARITY（autotest.parity_line，每 N 帧一行，按帧不按 g.t：约 40 个字段——时间、状态、等级、经验、击杀、生命、灯火、
  五条 rng、队长位置、敌人逐个类型 / 位置 / 生命哈希、Boss 血、藏品 / 成长 / 支援哈希、队友哈希、神经损伤、缩圈、溟痕、灯标、
  结局与翻卡状态、选项、护盾……）、TRACE（每秒一行，docs/36 §3.2）、BALANCE（结算数据，去掉画面峰值 peak / peak_min 与 prof）。
比较：PARITY 逐行逐字段；报第一处分歧的局、帧、游戏时间、字段名与两边的值。TRACE 逐行；BALANCE 逐键。
基线缓存：<主仓库>/build/parity_cache/<提交前 8 位>/<局名>_<参数哈希>.txt（同提交同参数只跑一次，所有工作树共用）。
本机 Godot 经 tools/godot_runner（全机上限）；--jobs 缺省 2（每会话 ≤ 2 个）。
退出码：0 = 全部一致；1 = 有差异或没跑成。
"""
import argparse, hashlib, json, os, shutil, subprocess, sys
from concurrent.futures import ThreadPoolExecutor

TOOLS = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(TOOLS)
sys.path.insert(0, TOOLS)
import godot_runner as GR

CROOT = GR.common_root()
CACHE = os.path.join(CROOT, "build", "parity_cache")
PARITY_EVERY = 15   # 帧；--balance 步长约 1/15 秒，约每游戏秒一行

# 四个结局（standard / knight / deep / resolve）× 三档难度（--preset 0/1/2）+ 1 局 Boss 测试台（伊莎玛拉二阶段）+ 1 局 3 分钟短局
CASES = {
    # 局名 = 实际走到的结局_难度档。--god（队长倒下回满）让机器人打满一局、走到结局线；结局靠 seed 选出来（docs/359 §1.2：
    # 机器人按 --route 选卡，但能不能翻到入口卡看发牌，heart 线 seed 25–40 里 Linux 只有 33、Windows 只有 37 走到 deep）
    "standard_p0": ["--seed=11", "--op=mizuki", "--preset=0", "--route=none"],
    "knight_p2": ["--seed=13", "--op=skadi", "--preset=2", "--route=knight", "--god", "--meta=full"],
    "deep_p0": ["--seed=33", "--op=mizuki", "--preset=0", "--route=heart", "--god"],
    "deep_p0w": ["--seed=37", "--op=mizuki", "--preset=0", "--route=heart", "--god"],   # 跨平台不逐局一致（docs/36 §7.4）：seed 33 在 Linux 走到 deep、Windows 是 standard；seed 37 反过来
    "resolve_p1": ["--seed=22", "--op=mizuki", "--preset=1", "--route=memory", "--god"],
    "boss": ["--seed=15", "--op=mizuki", "--bosstest=ishar2", "--parity=5"],
    "short": ["--seed=3", "--op=logos", "--maxt=180", "--squad=lappland"],
}
DROP_BAL = ("prof",)
DROP_BOT = ("peak", "peak_min")


def case_args(name):
    a = list(CASES[name])
    out = ["--balance", "--bot=expert", "--trace=1"]
    if not any(x.startswith("--parity=") for x in a):
        out.append("--parity=%d" % PARITY_EVERY)
    return out + a


def args_hash(name):
    return hashlib.sha1(" ".join(case_args(name)).encode("utf-8")).hexdigest()[:8]


def run_case(game_dir, name):
    """跑一局，返回 (行列表, 错误或 None)。只留 PARITY / TRACE / BALANCE 行。"""
    out, err, to = GR.run_godot([GR.find_godot(), "--headless", "--path", game_dir, "--"] + case_args(name), 2400)
    if to:
        return None, "超时"
    errs = GR.script_errors(out, err)
    if errs:
        return None, "脚本报错：" + "；".join(errs[:3])
    lines = [l for l in out.splitlines() if l.startswith(("PARITY ", "TRACE ", "BALANCE "))]
    if sum(1 for l in lines if l.startswith("PARITY ")) < 3:
        return None, "PARITY 行太少（%d）：被测提交没有 --parity？" % len(lines)
    return lines, None


def write_lines(path, header, lines):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".%d.tmp" % os.getpid()
    with open(tmp, "w", encoding="utf-8", newline="\n") as f:
        f.write(header + "\n" + "\n".join(lines) + "\n")
    os.replace(tmp, path)


def read_lines(path):
    return [l.rstrip("\n") for l in open(path, encoding="utf-8") if not l.startswith("#")]


def record(game_dir, outdir, names, jobs, tag):
    GR.ensure_imported(game_dir)

    def one(n):
        lines, why = run_case(game_dir, n)
        if lines is None:
            return n, why
        write_lines(os.path.join(outdir, "%s_%s.txt" % (n, args_hash(n))), "# theme_parity %s %s %s" % (tag, n, " ".join(case_args(n))), lines)
        return n, None

    with ThreadPoolExecutor(max(1, jobs)) as ex:
        res = list(ex.map(one, names))
    bad = [(n, w) for n, w in res if w]
    for n, w in bad:
        print("  %s 没跑成：%s" % (n, w), flush=True)
    return not bad


def parse_kv(line):
    d = {}
    for tok in line.split(" ")[1:]:
        k, _, v = tok.partition("=")
        d[k] = v
    return d


def bal_core(line):
    d = json.loads(line[len("BALANCE "):])
    for k in DROP_BAL:
        d.pop(k, None)
    if isinstance(d.get("bot"), dict):
        d["bot"] = {k: v for k, v in d["bot"].items() if k not in DROP_BOT}
    return d


def compare_case(name, la, lb):
    """返回 (ok, 说明, 统计)。"""
    pa = [l for l in la if l.startswith("PARITY ")]
    pb = [l for l in lb if l.startswith("PARITY ")]
    nf = 0
    for x, y in zip(pa, pb):
        if x == y:
            nf = max(nf, len(parse_kv(x)))
            continue
        dx, dy = parse_kv(x), parse_kv(y)
        keys = list(dx) + [k for k in dy if k not in dx]
        diffs = [k for k in keys if dx.get(k) != dy.get(k)]
        k0 = diffs[0]
        return False, "PARITY 第一处分歧：帧 %s、t=%s，字段 %s：A=%s / B=%s（同行另有 %d 个字段不同：%s）" % (
            dx.get("f"), dx.get("t"), k0, dx.get(k0), dy.get(k0), len(diffs) - 1, "、".join(diffs[1:8])), None
    if len(pa) != len(pb):
        return False, "PARITY 行数不同：A %d / B %d（前 %d 行相同）" % (len(pa), len(pb), min(len(pa), len(pb))), None
    ta = [l for l in la if l.startswith("TRACE ")]
    tb = [l for l in lb if l.startswith("TRACE ")]
    if ta != tb:
        for i, (x, y) in enumerate(zip(ta, tb)):
            if x != y:
                return False, "TRACE 第 %d 行不同：A %s / B %s" % (i + 1, x[:160], y[:160]), None
        return False, "TRACE 行数不同：A %d / B %d" % (len(ta), len(tb)), None
    ba = [bal_core(l) for l in la if l.startswith("BALANCE ")]
    bb = [bal_core(l) for l in lb if l.startswith("BALANCE ")]
    nb = 0
    if ba or bb:
        if len(ba) != len(bb):
            return False, "BALANCE 行数不同：A %d / B %d" % (len(ba), len(bb)), None
        for x, y in zip(ba, bb):
            dk = [k for k in sorted(set(x) | set(y)) if x.get(k) != y.get(k)]
            if dk:
                return False, "BALANCE 字段不同：" + "、".join(dk[:10]), None
            nb = max(nb, len(x))
    end = ""
    if ba:
        end = "，结局 %s、%s、%d 秒" % (ba[-1].get("ending"), "胜" if ba[-1].get("win") else "负", ba[-1].get("t", 0))
    st = {"parity_lines": len(pa), "parity_fields": nf, "trace_lines": len(ta), "balance_keys": nb}
    return True, "PARITY %d 行 × %d 字段、TRACE %d 行、BALANCE %d 键全部一致%s" % (len(pa), nf, len(ta), nb, end), st


def compare_dirs(da, db, names):
    ok_all = True
    tot = {"parity_lines": 0, "fields": 0, "cases": 0}
    for n in names:
        fa = os.path.join(da, "%s_%s.txt" % (n, args_hash(n)))
        fb = os.path.join(db, "%s_%s.txt" % (n, args_hash(n)))
        if not (os.path.exists(fa) and os.path.exists(fb)):
            print("失败 %-10s 缺结果文件（%s / %s）" % (n, os.path.exists(fa), os.path.exists(fb)))
            ok_all = False
            continue
        ok, why, st = compare_case(n, read_lines(fa), read_lines(fb))
        print("%s %-10s %s" % ("一致" if ok else "失败", n, why), flush=True)
        ok_all &= ok
        if st:
            tot["parity_lines"] += st["parity_lines"]
            tot["fields"] = max(tot["fields"], st["parity_fields"])
            tot["cases"] += 1
    print("\n%s：%d 局一致 / %d 局，PARITY 共 %d 行 × %d 字段" % ("theme_parity 通过" if ok_all else "theme_parity 失败", tot["cases"], len(names), tot["parity_lines"], tot["fields"]))
    return ok_all


def base_dir(sha, names, jobs):
    d = os.path.join(CACHE, sha[:8])
    miss = [n for n in names if not os.path.exists(os.path.join(d, "%s_%s.txt" % (n, args_hash(n))))]
    if not miss:
        print("基线缓存命中：" + d, flush=True)
        return d
    wt = os.path.join(CROOT, ".claude", "worktrees", "parity-%s-%d" % (sha[:8], os.getpid()))
    subprocess.run(["git", "worktree", "add", "--detach", wt, sha], cwd=CROOT, check=True, capture_output=True)
    try:
        src = os.path.join(CROOT, "game", ".godot")
        dst = os.path.join(wt, "game", ".godot")
        if os.path.isdir(src) and not os.path.isdir(dst):
            shutil.copytree(src, dst)
        print("基线：在 %s 上跑 %s……" % (sha[:8], "、".join(miss)), flush=True)
        ok = record(os.path.join(wt, "game"), d, miss, jobs, sha)
    finally:
        subprocess.run(["git", "worktree", "remove", "--force", wt], cwd=CROOT, capture_output=True)
    return d if ok else None


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("cmd", nargs="?", choices=["record", "compare"])
    ap.add_argument("dirs", nargs="*")
    ap.add_argument("--ref", default="main")
    ap.add_argument("--self", action="store_true", help="当前工作树自己跑两遍")
    ap.add_argument("--cases", default="", help="逗号分隔，缺省全部：" + ",".join(CASES))
    ap.add_argument("--jobs", type=int, default=2)
    a = ap.parse_args()
    names = [n for n in a.cases.split(",") if n] or list(CASES)
    for n in names:
        if n not in CASES:
            print("没有这一局：" + n)
            return 1
    game = os.path.join(ROOT, "game")
    head = subprocess.run(["git", "rev-parse", "HEAD"], cwd=ROOT, capture_output=True, text=True).stdout.strip()
    if a.cmd == "record":
        return 0 if record(game, a.dirs[0], names, a.jobs, head) else 1
    if a.cmd == "compare":
        return 0 if compare_dirs(a.dirs[0], a.dirs[1], names) else 1
    here = os.path.join(ROOT, "build", "parity_here")
    shutil.rmtree(here, ignore_errors=True)
    if a.self:
        other = os.path.join(ROOT, "build", "parity_here2")
        shutil.rmtree(other, ignore_errors=True)
        if not (record(game, here, names, a.jobs, head + "+wt") and record(game, other, names, a.jobs, head + "+wt")):
            return 1
        return 0 if compare_dirs(here, other, names) else 1
    sha = subprocess.run(["git", "rev-parse", a.ref], cwd=ROOT, capture_output=True, text=True).stdout.strip()
    if not sha:
        print("找不到提交：" + a.ref)
        return 1
    bd = base_dir(sha, names, a.jobs)
    if bd is None:
        print("基线没跑成")
        return 1
    if not record(game, here, names, a.jobs, head + "+wt"):
        return 1
    print("A = %s（基线），B = 当前工作树" % sha[:8])
    return 0 if compare_dirs(bd, here, names) else 1


if __name__ == "__main__":
    for _s in (sys.stdout, sys.stderr):
        try:
            _s.reconfigure(encoding="utf-8", errors="replace")
        except (AttributeError, ValueError):
            pass
    sys.exit(main())
