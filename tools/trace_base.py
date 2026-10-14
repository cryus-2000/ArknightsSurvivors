# -*- coding: utf-8 -*-
"""同种子对照的基线 TRACE 缓存（docs/36 §1.1、§3.2）：同一个 main 提交、同一组参数的基线只跑一次，所有会话共用。

用法：
    python tools/trace_base.py <seed> <队长> <时长秒>                  # 打印基线文件路径（没有就先跑一次再存）
    python tools/trace_base.py 1 mizuki 240 --extra "--tier=2 --sptest"   # 附加游戏参数（进缓存名）
    python tools/trace_base.py 1 mizuki 240 --ref <提交>              # 基线换成别的提交（缺省 main）
    python tools/trace_base.py 1 mizuki 240 --here                    # 另在当前工作树跑同一局，逐行比 TRACE

缓存：<主仓库>/build/trace_cache/<提交前 8 位>_<seed>_<队长>_<时长>[_<附加参数哈希 6 位>].txt，所有工作树共用。
内容：# 开头的说明行（提交、参数）+ 每秒一行 TRACE + 结束时的 BALANCE 一行。
没有缓存时：在 <主仓库>/.claude/worktrees/trace-<提交>-<pid> 建临时工作树（拷主仓库的导入缓存），
跑 `--headless --balance --seed=S --op=队长 --bot=expert --maxt=时长 --trace=1 [附加参数]`，存好后删掉工作树。
TRACE 只在 --balance 模式下打印（autotest.gd），所以基线用 --balance 跑；--bot / --tier 等可在 --extra 里覆盖。
退出码：0 = 给出了路径（--here 时还要求逐行相同）；1 = 跑失败或 --here 有差异。
"""
import argparse, hashlib, os, shutil, subprocess, sys

TOOLS = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(TOOLS)
sys.path.insert(0, TOOLS)
import godot_runner as GR

CROOT = GR.common_root()
CACHE = os.path.join(CROOT, "build", "trace_cache")


def game_args(seed, op, dur, extra):
    a = ["--balance", "--seed=%d" % seed, "--op=" + op, "--maxt=%d" % dur, "--trace=1"]
    if not any(x.startswith("--bot=") for x in extra):
        a.append("--bot=expert")
    return a + extra


def run_trace(game_dir, seed, op, dur, extra):
    """跑一局，返回 (TRACE + BALANCE 行列表, 错误说明或 None)"""
    out, err, to = GR.run_godot([GR.find_godot(), "--headless", "--path", game_dir, "--"] + game_args(seed, op, dur, extra), 600 + dur * 3)
    if to:
        return None, "超时"
    errs = GR.script_errors(out, err)
    lines = [l for l in out.splitlines() if l.startswith("TRACE ") or l.startswith("BALANCE ")]
    if errs:
        return None, "脚本报错：" + "；".join(errs[:3])
    if sum(1 for l in lines if l.startswith("TRACE ")) < 3:
        return None, "TRACE 行太少（%d），参数不对？" % len(lines)
    return lines, None


def cache_path(sha, seed, op, dur, extra):
    name = "%s_%d_%s_%d" % (sha[:8], seed, op, dur)
    if extra:
        name += "_" + hashlib.sha1(" ".join(extra).encode("utf-8")).hexdigest()[:6]
    return os.path.join(CACHE, name + ".txt")


def build_base(sha, seed, op, dur, extra, path):
    wt = os.path.join(CROOT, ".claude", "worktrees", "trace-%s-%d" % (sha[:8], os.getpid()))
    subprocess.run(["git", "worktree", "add", "--detach", wt, sha], cwd=CROOT, check=True, capture_output=True)
    try:
        src = os.path.join(CROOT, "game", ".godot")   # 主仓库的导入缓存，免得临时工作树从头导入
        dst = os.path.join(wt, "game", ".godot")
        if os.path.isdir(src) and not os.path.isdir(dst):
            shutil.copytree(src, dst)
        GR.ensure_imported(os.path.join(wt, "game"))
        print("基线：在 %s（%s）上跑 seed %d %s %d 秒……" % (sha[:8], wt, seed, op, dur), flush=True)
        lines, why = run_trace(os.path.join(wt, "game"), seed, op, dur, extra)
    finally:
        subprocess.run(["git", "worktree", "remove", "--force", wt], cwd=CROOT, capture_output=True)
    if lines is None:
        return why
    os.makedirs(CACHE, exist_ok=True)
    tmp = path + ".%d.tmp" % os.getpid()
    with open(tmp, "w", encoding="utf-8", newline="\n") as f:
        f.write("# trace_base 提交 %s\n# 参数 %s\n" % (sha, " ".join(game_args(seed, op, dur, extra))))
        f.write("\n".join(lines) + "\n")
    os.replace(tmp, path)   # 原子替换：两个会话同时建同一份也不会读到半截文件
    return None


def read_lines(path):
    return [l.rstrip("\n") for l in open(path, encoding="utf-8") if not l.startswith("#")]


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("seed", type=int)
    ap.add_argument("op", help="队长（开局干员）id")
    ap.add_argument("dur", type=int, help="游戏时长（秒，--maxt）")
    ap.add_argument("--ref", default="main", help="基线提交（缺省 main）")
    ap.add_argument("--extra", default="", help="附加游戏参数，空格分隔，例如 \"--tier=2 --sptest\"")
    ap.add_argument("--refresh", action="store_true", help="忽略已有缓存重跑")
    ap.add_argument("--here", action="store_true", help="另在当前工作树跑同一局，逐行比 TRACE（BALANCE 行只提示不判定）")
    a = ap.parse_args()
    extra = a.extra.split()
    sha = subprocess.run(["git", "rev-parse", a.ref], cwd=ROOT, capture_output=True, text=True).stdout.strip()
    if not sha:
        print("找不到提交：" + a.ref)
        return 1
    path = cache_path(sha, a.seed, a.op, a.dur, extra)
    if a.refresh or not os.path.exists(path):
        why = build_base(sha, a.seed, a.op, a.dur, extra, path)
        if why:
            print("基线没跑成：" + why)
            return 1
    else:
        print("基线缓存命中", flush=True)
    print(path)
    if not a.here:
        return 0
    GR.ensure_imported(os.path.join(ROOT, "game"))   # 新工作树没有导入缓存时 Godot 会卡住直到超时
    lines, why = run_trace(os.path.join(ROOT, "game"), a.seed, a.op, a.dur, extra)
    if lines is None:
        print("当前工作树没跑成：" + why)
        return 1
    base = read_lines(path)
    tb = [l for l in base if l.startswith("TRACE ")]
    th = [l for l in lines if l.startswith("TRACE ")]
    for i, (x, y) in enumerate(zip(tb, th)):
        if x != y:
            print("TRACE 第 %d 行起不同：\n  基线 %s\n  当前 %s" % (i + 1, x, y))
            return 1
    if len(tb) != len(th):
        print("TRACE 行数不同：基线 %d、当前 %d（前 %d 行相同）" % (len(tb), len(th), min(len(tb), len(th))))
        return 1
    bb = [l for l in base if l.startswith("BALANCE ")]
    bh = [l for l in lines if l.startswith("BALANCE ")]
    print("TRACE %d 行逐行相同%s" % (len(tb), "" if bb == bh else "（BALANCE 行有差异，多半是画面峰值 / prof 字段，需要时自己比）"))
    return 0


if __name__ == "__main__":
    for _s in (sys.stdout, sys.stderr):
        try:
            _s.reconfigure(encoding="utf-8", errors="replace")
        except (AttributeError, ValueError):
            pass
    sys.exit(main())
