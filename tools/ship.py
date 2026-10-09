# -*- coding: utf-8 -*-
"""一键发版（用户 2026-10-10 授权方案 A：合入 main 后自动推 origin、重出三包、butler 推 itch，不再逐次问）。

    python tools/ship.py                 # 全流程：快检 → 发布检查 → 推 origin/main → release_all 三包 → deploy_itch --apply
    python tools/ship.py --skip-check    # 快检刚跑过时跳过（发布检查仍跑）
    python tools/ship.py --no-itch       # 只推 origin + 出包，不上 itch
    python tools/ship.py --dry-run       # 只打印要做什么

规则：
- 工作区必须干净且在 main，HEAD 就是要发的提交；任一步失败立即停，后面的步骤不做。
- 只推 audience=public 的 Windows 包与网页 zip 到 itch（deploy_itch 自己把关），对内包只出本地。
- 每步输出进 build/ship/<提交>/ 下的日志，退出码从文件读，不靠管道。
"""
import argparse, os, subprocess, sys, time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TOOLS = ROOT / "tools"
ENV = dict(os.environ, PYTHONIOENCODING="utf-8", PYTHONUTF8="1")


def sh(args, log, cwd=ROOT, timeout=3600):
    with open(log, "ab") as fh:
        fh.write(("\n$ " + " ".join(str(a) for a in args) + "\n").encode("utf-8"))
        fh.flush()
        p = subprocess.run([str(a) for a in args], cwd=str(cwd), env=ENV, stdout=fh, stderr=subprocess.STDOUT, timeout=timeout)
    return p.returncode


def git(*a):
    return subprocess.run(["git"] + list(a), cwd=str(ROOT), capture_output=True, text=True, encoding="utf-8", errors="replace").stdout.strip()


def main():
    for st in (sys.stdout, sys.stderr):
        try:
            st.reconfigure(encoding="utf-8")
        except Exception:
            pass
    ap = argparse.ArgumentParser()
    ap.add_argument("--skip-check", action="store_true")
    ap.add_argument("--no-itch", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()

    if git("branch", "--show-current") != "main":
        sys.exit("不在 main，停止")
    dirty = [l for l in git("status", "--short").splitlines() if l and not l.startswith("??")]
    if dirty:
        sys.exit("工作区有未提交改动，停止：\n" + "\n".join(dirty))
    commit = git("rev-parse", "HEAD")
    short = git("rev-parse", "--short=8", "HEAD")
    logdir = ROOT / "build" / "ship" / short
    logdir.mkdir(parents=True, exist_ok=True)
    print("发版 %s（%s）" % (short, git("log", "-1", "--format=%s")[:60]))

    steps = []
    if not a.skip_check:
        steps.append(("快检", [sys.executable, TOOLS / "check.py", "--jobs", "4"]))
    steps.append(("发布检查", [sys.executable, TOOLS / "check_release.py"]))
    steps.append(("推 origin/main", ["git", "push", "origin", "main"]))
    for kind in ("public", "web", "internal"):
        steps.append(("出包 " + kind, [sys.executable, TOOLS / "release_all.py", "--ref", short, "--only", kind]))
    if not a.no_itch:
        steps.append(("itch dry-run", [sys.executable, TOOLS / "deploy_itch.py", "--ref", short]))
        steps.append(("itch 真推", [sys.executable, TOOLS / "deploy_itch.py", "--ref", short, "--apply", "--confirm", short]))

    for name, cmd in steps:
        print("  - " + name, end="", flush=True)
        if a.dry_run:
            print("（dry-run）")
            continue
        t0 = time.time()
        log = logdir / (name.replace(" ", "_").replace("/", "_") + ".log")
        rc = sh(cmd, log)
        print("  rc=%d  %.0fs  %s" % (rc, time.time() - t0, log.relative_to(ROOT)))
        if rc != 0:
            sys.exit("「%s」失败，后续步骤未做；看日志 %s" % (name, log))
    print("完成：origin/main = %s；包在 build/release/final_%s/；itch %s" % (short, short, "已更新" if not a.no_itch else "未推"))


if __name__ == "__main__":
    main()
