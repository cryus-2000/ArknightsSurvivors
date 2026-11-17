# -*- coding: utf-8 -*-
"""一键发版（用户 2026-10-10 授权方案 A：合入 main 后自动推 origin、重出三包、butler 推 itch，不再逐次问）。

    python tools/ship.py                 # 全流程：快检 → 发布检查 → 推 origin/main → release_all 三包 → deploy_itch --apply
    python tools/ship.py --skip-check    # 快检刚跑过时跳过（发布检查仍跑）
    python tools/ship.py --no-itch       # 只推 origin + 出包，不上 itch
    python tools/ship.py --dry-run       # 只打印要做什么
    python tools/ship.py --toy           # 顺带出 B站 Toy 包（同一次网页导入，只出包不上传；docs/33 §发版提速）

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
    ap.add_argument("--internal", action="store_true", help="同时出对内包（缺省只出 public + web；用户 10-16 定）")
    ap.add_argument("--toy", action="store_true", help="同一次网页导入顺带出 B站 Toy 包（build/toy/web + zip，只出包不上传；上传由协调人 toy update）")
    ap.add_argument("--serial", action="store_true", help="Windows 包与网页包按旧办法串行出（缺省并行，11-17 发版提速）")
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
        # 积木等价金样重录（docs/36 §1.3）：快检通过后把数据版输出录到 build/golden_cache；seed1 用例刚跑过、直接命中结果缓存。
        # 不挡发版：失败（多半是 seed3 用例与未过期金样不同）只提示，金样不更新
        steps.append(("金样重录", [sys.executable, TOOLS / "check.py", "--only", "blocks_eq", "--eq-all", "--update-golden", "--jobs", "4"]))
    steps.append(("发布检查", [sys.executable, TOOLS / "check_release.py"]))
    steps.append(("推 origin/main", ["git", "push", "origin", "main"]))
    # 出包：Windows 包（build/_export）与网页包（build/_web）用不同的干净副本，并行出（11-17 发版提速；各占 1 个 Godot）。
    # 同一组里的步骤同时跑，任一失败整组算失败；--serial 退回逐个串行
    pkgs = []
    for kind in (("public", "web", "internal") if a.internal else ("public", "web")):
        pkgs.append(("出包 " + kind, [sys.executable, TOOLS / "release_all.py", "--ref", short, "--only", kind] + (["--toy"] if a.toy and kind == "web" else [])))
    if a.serial:
        steps += pkgs
    else:
        steps.append(pkgs[:2])
        steps += pkgs[2:]
    steps.append(("清旧包", [sys.executable, TOOLS / "clean_local.py", "--release", "--apply"]))  # docs/36 §10：只留最近 3 个 + KEEP_SHAS
    if not a.no_itch:
        steps.append(("itch dry-run", [sys.executable, TOOLS / "deploy_itch.py", "--ref", short]))
        steps.append(("itch 真推", [sys.executable, TOOLS / "deploy_itch.py", "--ref", short, "--apply", "--confirm", short]))

    t_all = time.time()
    for item in steps:
        if isinstance(item, list):   # 并行组
            print("  - 并行：" + " + ".join(n for n, _ in item), flush=True)
            if a.dry_run:
                continue
            t0 = time.time()
            procs = []
            for name, cmd in item:
                log = logdir / (name.replace(" ", "_").replace("/", "_") + ".log")
                fh = open(log, "ab")
                fh.write(("\n$ " + " ".join(str(x) for x in cmd) + "\n").encode("utf-8"))
                fh.flush()
                procs.append((name, log, fh, subprocess.Popen([str(x) for x in cmd], cwd=str(ROOT), env=ENV, stdout=fh, stderr=subprocess.STDOUT)))
            failed = None
            for name, log, fh, p in procs:
                rc = p.wait(timeout=3600)
                fh.close()
                print("    %s  rc=%d  %.0fs  %s" % (name, rc, time.time() - t0, log.relative_to(ROOT)), flush=True)
                if rc != 0 and failed is None:
                    failed = (name, log)
            if failed:
                sys.exit("「%s」失败，后续步骤未做；看日志 %s" % failed)
            continue
        name, cmd = item
        print("  - " + name, end="", flush=True)
        if a.dry_run:
            print("（dry-run）")
            continue
        t0 = time.time()
        log = logdir / (name.replace(" ", "_").replace("/", "_") + ".log")
        rc = sh(cmd, log)
        print("  rc=%d  %.0fs  %s" % (rc, time.time() - t0, log.relative_to(ROOT)))
        if rc != 0 and name == "金样重录":
            print("    金样没有重录（不挡发版）：多半是 seed3 用例与金样不同，看日志 %s" % log)
            continue
        if rc != 0:
            sys.exit("「%s」失败，后续步骤未做；看日志 %s" % (name, log))
    if a.dry_run:
        return
    print("完成（%.0f 秒）：origin/main = %s；包在 build/release/final_%s/；itch %s%s" % (time.time() - t_all, short, short, "已更新" if not a.no_itch else "未推",
          "；Toy 包在 build/toy/（未上传，用 toy update）" if a.toy else ""))


if __name__ == "__main__":
    main()
