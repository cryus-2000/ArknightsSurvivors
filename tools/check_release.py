#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""发布前检查：玩家首次打开发布版必须是初始状态（图鉴未解锁、难度从头开始、结局事件未解锁）。

    python tools/check_release.py      退出码 0 = 通过；1 = 有问题（逐条列出）

检查项：
1. 存档字段的代码默认值是初始值（settings.gd：diff_unlocked = 0，seen_* / endings_cleared 为空，seen_intro = false）。
2. 解锁类开发开关（--allend / --allrelics / --unlock*）以及所有命令行开关都只经 Cfg.dev_args() 读取（发布版里返回空）。
3. 存档不会被打进包：game/ 下没有 settings.cfg / *.save，导出预设的 include_filter 不含 *.cfg。
4. tools/export_build.py 用 --export-release（非 debug 导出，OS.is_debug_build() 为 false）。
5. 全部解锁（Cfg.unlock_all）默认 false，发布版只对对内包（audience == internal）打开，对外包恒不打开。

说明：存档在 user://settings.cfg（Windows：%APPDATA%/Godot/app_userdata/<项目名>/；网页版：浏览器 IndexedDB，按网址隔离），
都不在导出包里，所以开发机的进度不会被带出去。但在开发机上直接运行导出的 exe 会读到本机的开发存档——
验收「首次打开」要在干净的用户目录或另一台机器上看。
"""
import glob, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GAME = os.path.join(ROOT, "game")
UNLOCK_FLAGS = ("--allend", "--allrelics", "--unlock")
DEFAULTS = {
    "diff_unlocked": r":=\s*0\b",
    "seen_shows": r":\s*Array\s*=\s*\[\]",
    "seen_relics": r":\s*Array\s*=\s*\[\]",
    "endings_cleared": r":\s*Array\s*=\s*\[\]",
    "seen_intro": r":=\s*false\b",
}


def read(p):
    with open(p, encoding="utf-8") as f:
        return f.read()


def main():
    errs = []
    st = read(os.path.join(GAME, "scripts", "settings.gd"))
    for name, pat in DEFAULTS.items():
        m = re.search(r"^var\s+%s\b(.*)$" % name, st, re.M)
        if not m or not re.search(pat, m.group(1)):
            errs.append("settings.gd：%s 的默认值不是初始值（%s）" % (name, m.group(0).strip() if m else "没找到"))
    if "func dev_args" not in st or "is_debug_build" not in st:
        errs.append("settings.gd：缺少 dev_args()（发布版屏蔽开发参数）")

    for p in glob.glob(os.path.join(GAME, "scripts", "**", "*.gd"), recursive=True):
        for i, line in enumerate(read(p).splitlines(), 1):
            code = line.split("#")[0]   # 注释里提到开关名不算
            if any(f in code for f in UNLOCK_FLAGS) and "dev_args()" not in code:
                errs.append("%s:%d：解锁开关没走 Cfg.dev_args()：%s" % (os.path.relpath(p, ROOT), i, line.strip()[:100]))

    # 所有命令行开关（截图 / 自测 / 解锁）一律经 Cfg.dev_args()，发布版里读不到（EA 验收 P2-14：--winshot 等可直接看结局结算页）。
    # 例外：settings.gd 里 dev_args() 本身；sfx.gd 自动加载早于 Cfg，就地用 is_debug_build() 守住
    for p in glob.glob(os.path.join(GAME, "scripts", "**", "*.gd"), recursive=True):
        for i, line in enumerate(read(p).splitlines(), 1):
            code = line.split("#")[0]
            if "get_cmdline_user_args" in code and "is_debug_build" not in code:
                errs.append("%s:%d：命令行参数没走 Cfg.dev_args()：%s" % (os.path.relpath(p, ROOT), i, line.strip()[:100]))

    for pat in ("settings.cfg", "*.save", "**/settings.cfg"):
        for p in glob.glob(os.path.join(GAME, pat), recursive=True):
            errs.append("game/ 下有存档文件会被打进包：%s" % os.path.relpath(p, ROOT))
    for line in read(os.path.join(GAME, "export_presets.cfg")).splitlines():
        if line.startswith("include_filter=") and ".cfg" in line:
            errs.append("export_presets.cfg：include_filter 带了 .cfg：%s" % line)

    eb = read(os.path.join(ROOT, "tools", "export_build.py"))
    if "--export-debug" in eb or "--export-release" not in eb:
        errs.append("tools/export_build.py：应使用 --export-release")

    # 5. 全部解锁（Cfg.unlock_all，1.1.1 用户 09-30）：默认 false；发布版只对对内包（build.json audience == internal）打开，
    #    对外包恒不打开；只有 _apply_unlock_all 能把它设成 true（打包后的实测断言在 verify_encrypted_game.py）
    if not re.search(r"^var\s+unlock_all\s*:=\s*false\b", st, re.M):
        errs.append("settings.gd：unlock_all 的默认值必须是 false")
    body = re.search(r"^func _apply_unlock_all\(\).*?(?=^\S)", st, re.M | re.S)
    if not body or "OS.is_debug_build()" not in body.group(0) or 'build_audience() != "internal"' not in body.group(0):
        errs.append('settings.gd：_apply_unlock_all 的发布版分支必须在 build_audience() != "internal" 时直接返回（对外包不得全部解锁）')
    # _apply_unlock_all 函数体在 settings.gd 里的行号范围（1 起）：只有这几行可以写 unlock_all = true
    first = st[:body.start()].count("\n") + 1 if body else 0
    last = first + body.group(0).count("\n") if body else -1
    for p in glob.glob(os.path.join(GAME, "scripts", "**", "*.gd"), recursive=True):
        for i, line in enumerate(read(p).splitlines(), 1):
            code = line.split("#")[0]
            if re.search(r"\bunlock_all\s*=\s*true", code) and not (os.path.basename(p) == "settings.gd" and first <= i <= last):
                errs.append("%s:%d：只有 settings.gd 的 _apply_unlock_all 可以打开 unlock_all：%s" % (os.path.relpath(p, ROOT), i, line.strip()[:100]))

    if errs:
        print("发布检查：%d 项问题" % len(errs))
        for e in errs:
            print("  ✗ " + e)
        return 1
    print("发布检查：通过（初始存档默认值、解锁开关、存档不入包、release 导出、对外包不全解锁）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
