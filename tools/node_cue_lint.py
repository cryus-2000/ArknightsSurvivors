#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""成长节点画面出口检查（docs/310 §2）：转平面接管干员后 o.fx / o.sparks / spawn_fx_sprite 不画，
写在这些调用里的节点提示实机看不到。本检查扫 game/scripts/characters/blocks/seg_*.gd：
某个函数里调了 o.fx( / o.sparks( 却没有同时发 _FXR.ev( / ncue(（或各段自己的转平面钩子常量），就算一个「只走旧画面」的函数。

做法是棘轮：tools/node_cue_lint_baseline.json 记着每个文件现有的此类函数名，**新增**的才报错
（新写的节点提示必须走 ncue / _FXR.ev）；改好一个就从基线里删掉它（--update 重写基线，只许变少）。

用法：
    python tools/node_cue_lint.py            检查（退出码 1 = 有新增）
    python tools/node_cue_lint.py --update   按当前代码重写基线（只在函数变少时用）
"""
import glob, json, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BLOCKS = os.path.join(ROOT, "game", "scripts", "characters", "blocks")
BASE = os.path.join(ROOT, "tools", "node_cue_lint_baseline.json")
OLD = re.compile(r"\bo\.(fx|sparks)\(")
NEW = re.compile(r"(_FXR|_MZFX)\.ev\(|\bncue\(")
FUNC = re.compile(r"^(static\s+)?func\s+(\w+)")


def scan():
    out = {}
    for p in sorted(glob.glob(os.path.join(BLOCKS, "seg_*.gd"))):
        name, body, bare = None, [], []
        lines = open(p, encoding="utf-8").read().splitlines() + ["func __end__():"]
        for ln in lines:
            m = FUNC.match(ln)
            if m:
                if name and any(OLD.search(x) for x in body) and not any(NEW.search(x) for x in body):
                    bare.append(name)
                name, body = m.group(2), []
            elif name:
                body.append(ln.split("#", 1)[0])
        out[os.path.basename(p)] = sorted(set(bare))
    return out


def check():
    cur = scan()
    base = json.load(open(BASE, encoding="utf-8")) if os.path.exists(BASE) else {}
    errs = []
    for f, fns in cur.items():
        known = set(base.get(f, []))
        for fn in fns:
            if fn not in known:
                errs.append("%s %s：调了 o.fx / o.sparks 却没发 _FXR.ev / ncue（转平面下不画，docs/310 §2）" % (f, fn))
    n = sum(len(v) for v in cur.values())
    return errs, "%d 个旧画面函数（基线 %d），新增 %d" % (n, sum(len(v) for v in base.values()), len(errs))


def main():
    if "--update" in sys.argv:
        cur = scan()
        json.dump(cur, open(BASE, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
        print("基线已写：%d 个函数" % sum(len(v) for v in cur.values()))
        return 0
    errs, detail = check()
    print(detail)
    for e in errs:
        print("  " + e)
    return 1 if errs else 0


if __name__ == "__main__":
    sys.exit(main())
