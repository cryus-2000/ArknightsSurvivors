# -*- coding: utf-8 -*-
"""敌人控制状态直写检查（docs/101 §7.3.10；快检项 cc_lint，不开 Godot，约 1 秒）。

  1. 全部 game/scripts：禁止对击退累加 `.kb +=` / `.kb -=` / `["kb"] +=`——击退一律走 apply_kb（失重倍率在那里乘，B7 修过直接累加漏乘的 bug）。
     唯一例外是 run/enemies.gd 的 apply_kb 本身。清零（`e.kb = Vector2.ZERO`）不禁。
  2. 干员代码（scripts/characters/ 下全部 .gd）：禁止直写敌人的 stun / slow / air，分别走 add_cc / set_air（op_api 转发 enemies_sys）。
     「敌人」按变量名认：e / e2 / en / best / target / tgt / victim，以及 `<x>.e`（浮空表、链等跨帧持有的敌人）。
     干员自己的同名状态（如艾丽妮的 ir.air 浮空表）不算。
  不禁：e.pos 直写（拖拽 / 推开，用 hold_at / nudge 是好习惯但不强制）。

    python tools/op_cc_lint.py
"""
import os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCRIPTS = os.path.join(ROOT, "game", "scripts")
KB_RE = re.compile(r'(\.kb|\["kb"\])\s*[-+]=')
KB_OK = {("run/enemies.gd", "apply_kb")}
EN = r'(?:\b(?:e|e2|en|best|target|tgt|victim)|\b\w+\.e)'
CC_RE = re.compile(EN + r'(?:\.(stun|slow|air)|\["(stun|slow|air)"\])\s*(?:=(?!=)|[-+*/]=)')
FN_RE = re.compile(r'^(?:static\s+)?func\s+(\w+)\(')
FIX = {"stun": "add_cc(e, stun)", "slow": "add_cc(e, -INF, slow)", "air": "set_air(e, h, hold_kb)"}


def _scan(path, rel, cc):
    errs = []
    fn = ""
    for i, l in enumerate(open(path, encoding="utf-8").read().split("\n")):
        m = FN_RE.match(l)
        if m:
            fn = m.group(1)
        code = l.split("#")[0]
        if KB_RE.search(code) and (rel, fn) not in KB_OK:
            errs.append("%s:%d（%s）击退累加要走 apply_kb：%s" % (rel, i + 1, fn, code.strip()[:80]))
        if cc:
            m = CC_RE.search(code)
            if m:
                f = m.group(1) or m.group(2)
                errs.append("%s:%d（%s）直写敌人 %s，改走 %s：%s" % (rel, i + 1, fn, f, FIX[f], code.strip()[:80]))
    return errs


def check():
    errs, n = [], 0
    for d, _, fs in os.walk(SCRIPTS):
        for f in fs:
            if not f.endswith(".gd"):
                continue
            p = os.path.join(d, f)
            rel = os.path.relpath(p, SCRIPTS).replace("\\", "/")
            n += 1
            errs += _scan(p, rel, rel.startswith("characters/"))
    return errs, "%d 个脚本：击退累加只在 apply_kb；干员代码不直写敌人 stun / slow / air" % n


def main():
    errs, detail = check()
    for e in errs:
        print("!! " + e)
    print(detail if not errs else "不通过：%d 处" % len(errs))
    return 1 if errs else 0


if __name__ == "__main__":
    sys.exit(main())
