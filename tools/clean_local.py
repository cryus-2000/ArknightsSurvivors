#!/usr/bin/env python3
"""本地存储清理（docs/36 §10、docs/41 §3 工作树规则；用户 2026-10-15 要求，之前工作树 72 GB + release 28 GB）。

    python tools/clean_local.py                 # 只报告：哪些会删、省多少
    python tools/clean_local.py --apply         # 真删（工作树 + 旧包）
    python tools/clean_local.py --release --apply   # 只清旧包（ship.py 出包后自动调用）
    python tools/clean_local.py --worktrees --apply # 只清工作树

删什么：
- 工作树：.claude/worktrees/ 下 (a) 未在 `git worktree list` 登记的孤儿文件夹；(b) 子代理一次性工作树（agent-*）且分支已合入 main、
  无未提交改动、未跟踪文件只有 .uid。命名工作树（角色会话）默认不动，加 --named 后同样按「已合入 + 干净」清。
- 旧包：build/release/final_<sha>/ 只留最近 KEEP_NEWEST 个（按修改时间）+ KEEP_SHAS（itch 线上、EA 冻结）。zip / rehearsal / verify 不动。
分支一律保留，删错了 `git worktree add` 能再检出。
"""
import argparse, os, shutil, stat, subprocess, sys, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WT = os.path.join(ROOT, ".claude", "worktrees")
REL = os.path.join(ROOT, "build", "release")
KEEP_NEWEST = 3
KEEP_SHAS = {"42c7e74c", "e97b4a2"}  # itch 线上首推（docs/33）、EA 冻结（docs/41）；换线上版时改这里


def git(*a, cwd=ROOT):
    return subprocess.run(["git", *a], cwd=cwd, capture_output=True, text=True, encoding="utf-8", errors="replace").stdout


def rmtree(p):
    def onerr(f, path, _e):
        os.chmod(path, stat.S_IWRITE)
        f(path)
    shutil.rmtree(p, onerror=onerr)


def du(p):
    n = 0
    for d, _, fs in os.walk(p):
        for f in fs:
            try:
                n += os.path.getsize(os.path.join(d, f))
            except OSError:
                pass
    return n


def plan_worktrees(named):
    reg, cur = {}, None
    for line in git("worktree", "list", "--porcelain").splitlines():
        if line.startswith("worktree "):
            cur = os.path.normcase(os.path.normpath(line[9:]))
            reg[cur] = None
        elif line.startswith("branch ") and cur:
            reg[cur] = line[7:].replace("refs/heads/", "")
    out = []
    if not os.path.isdir(WT):
        return out
    for d in sorted(os.listdir(WT)):
        p = os.path.join(WT, d)
        if not os.path.isdir(p):
            continue
        key = os.path.normcase(os.path.normpath(p))
        if key not in reg:
            out.append((p, "孤儿（未登记）", None))
            continue
        b = reg[key]
        if b is None or (not d.startswith("agent-") and not named):
            continue
        merged = subprocess.run(["git", "merge-base", "--is-ancestor", b, "main"], cwd=ROOT).returncode == 0
        st = git("status", "--porcelain", cwd=p).splitlines()
        dirty = [l for l in st if not l.startswith("??")]
        untracked = [l for l in st if l.startswith("??") and not l.rstrip().endswith(".uid")]
        if merged and not dirty and not untracked:
            out.append((p, "已合入、干净", b))
    return out


def plan_release():
    if not os.path.isdir(REL):
        return []
    finals = [d for d in os.listdir(REL) if d.startswith("final_") and os.path.isdir(os.path.join(REL, d))]
    finals.sort(key=lambda d: os.path.getmtime(os.path.join(REL, d)), reverse=True)
    keep = set(finals[:KEEP_NEWEST]) | {d for d in finals if d[6:] in KEEP_SHAS or any(d[6:].startswith(s) for s in KEEP_SHAS)}
    return [(os.path.join(REL, d), "旧包", None) for d in finals if d not in keep]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true")
    ap.add_argument("--worktrees", action="store_true")
    ap.add_argument("--release", action="store_true")
    ap.add_argument("--named", action="store_true", help="命名工作树也按「已合入 + 干净」清")
    a = ap.parse_args()
    if not a.worktrees and not a.release:
        a.worktrees = a.release = True
    items = []
    if a.worktrees:
        items += plan_worktrees(a.named)
    if a.release:
        items += plan_release()
    total = 0
    for p, why, b in items:
        sz = du(p)
        total += sz
        print("%s  %-14s %6d MB  %s" % ("删" if a.apply else "拟删", why, sz // 2**20, os.path.relpath(p, ROOT) + (("  [" + b + "]") if b else "")))
        if a.apply:
            if why != "旧包" and why != "孤儿（未登记）":
                subprocess.run(["git", "worktree", "remove", "--force", p], cwd=ROOT, capture_output=True)
            if os.path.isdir(p):
                rmtree(p)
    if a.apply and a.worktrees:
        subprocess.run(["git", "worktree", "prune"], cwd=ROOT)
    print("%s %d 项，共 %.1f GB%s" % ("已删" if a.apply else "拟删", len(items), total / 2**30, "" if a.apply else "（加 --apply 执行）"))


if __name__ == "__main__":
    main()
