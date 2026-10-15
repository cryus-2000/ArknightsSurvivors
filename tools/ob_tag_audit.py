# -*- coding: utf-8 -*-
"""干员积木瞬时执行器的 tag 核对（docs/101 §7.3.2、§7.3.7；快检项 ob_tag，不开 Godot，约 1 秒）。

data_operator._exec_list 的缺省分支按 EXEC_SEG（tag → 执行器下标）单播给一个执行器（B6 ③）。单播与原来的「依次广播给全部执行器」等价的前提：
  1. 每个执行器的函数体只有一条 `match str(b.get("_tag", ""))`（match 前后没有别的语句，没命中的 tag 什么都不做）；
  2. 各执行器的分支 tag 两两不重叠；
  3. EXEC_SEG 与各执行器的分支一一对应（不多、不少、下标对）。
hw_exec 的 `_:` 分支转 h3_exec / h4_exec，三者按一个整体（广播时同属「hw 段」）核对，表里分别记 6 / 7 / 8。

    python tools/ob_tag_audit.py            # 核对，打印各执行器 tag 数
    python tools/ob_tag_audit.py --table    # 按当前各执行器的分支打印应有的 EXEC_SEG（加新执行器 / 新 tag 后照抄进 data_operator.gd）
"""
import os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CH = os.path.join(ROOT, "game", "scripts", "characters")
# 下标 → (文件, 函数)：顺序 = 原广播顺序
EXECUTORS = [
    ("data_operator.gd", "_ext_exec"),
    ("blocks/seg_texas.gd", "tx_exec"),
    ("blocks/seg_exusiai.gd", "exu_exec"),
    ("blocks/ob_summon.gd", "sm_exec"),
    ("blocks/ob_summon.gd", "mf_exec"),
    ("blocks/ob_elite.gd", "el_exec"),
    ("blocks/ob_hw.gd", "hw_exec"),
    ("blocks/ob_hw.gd", "h3_exec"),
    ("blocks/ob_hw.gd", "h4_exec"),
]
# 原广播里 hw_exec 的 `_:` 只允许是这样转 h3 / h4
HW_DEFAULT = ["h3_exec(o, b, at)", "if h4_on(o):", "h4_exec(o, b, at)"]
MATCH_RE = re.compile(r'^\tmatch str\(b\.get\("_tag", ""\)\):\s*$')
ARM_RE = re.compile(r'^\t\t(\S.*):\s*(#.*)?$')


def _body(path, fn):
    lines = open(path, encoding="utf-8").read().split("\n")
    head = re.compile(r"^(static )?func %s\(" % re.escape(fn))
    for i, l in enumerate(lines):
        if head.match(l):
            out = []
            for l2 in lines[i + 1:]:
                if l2.strip() == "" or l2.startswith("\t"):
                    out.append(l2)
                else:
                    break
            return out
    return None


def parse(path, fn):
    """返回 (tags, default_body, errs)"""
    errs = []
    body = _body(path, fn)
    if body is None:
        return [], [], ["%s 里找不到 %s" % (os.path.basename(path), fn)]
    stmts = [l for l in body if l.strip() and not l.strip().startswith("#")]
    if not stmts or not MATCH_RE.match(stmts[0]):
        return [], [], ["%s：函数体第一句不是 match str(b.get(\"_tag\", \"\"))" % fn]
    if any(l.startswith("\t") and not l.startswith("\t\t") for l in stmts[1:]):
        errs.append("%s：match 之外还有语句（单播会漏掉它）" % fn)
    tags, default, cur = [], [], None
    for l in stmts[1:]:
        if l.startswith("\t\t") and not l.startswith("\t\t\t"):
            m = ARM_RE.match(l)
            if not m:
                errs.append("%s：认不出的分支行 %r" % (fn, l.strip()))
                continue
            pat = m.group(1).strip()
            if pat == "_":
                cur = "_"
                continue
            cur = None
            lits = re.findall(r'"([^"]*)"', pat)
            if not lits or re.sub(r'"[^"]*"|,|\s', "", pat):
                errs.append("%s：分支不是纯字符串字面量 %r" % (fn, pat))
            tags += lits
        elif cur == "_":
            default.append(l.split("#")[0].strip())
    return tags, default, errs


def table_from_code():
    """各执行器实际的分支 → (tag → 下标, errs, 每个执行器的 tag 数)"""
    errs, seg, counts = [], {}, []
    for i, (f, fn) in enumerate(EXECUTORS):
        tags, default, e = parse(os.path.join(CH, f), fn)
        errs += e
        counts.append(len(tags))
        if fn == "hw_exec":
            if default != HW_DEFAULT:
                errs.append("hw_exec 的 _: 分支变了（应是转 h3_exec、h4_on 时转 h4_exec）：%r" % default)
        elif default:
            errs.append("%s 有 _: 分支（单播不会走到它）：%r" % (fn, default))
        for t in tags:
            if t in seg:
                errs.append("tag「%s」同时在 %s 和 %s" % (t, EXECUTORS[seg[t]][1], fn))
            else:
                seg[t] = i
    return seg, errs, counts


def table_in_data_operator():
    s = open(os.path.join(CH, "data_operator.gd"), encoding="utf-8").read()
    m = re.search(r"^const EXEC_SEG := \{(.*?)^\}", s, re.M | re.S)
    if not m:
        return None
    return {k: int(v) for k, v in re.findall(r'"([^"]+)":\s*(\d+)', m.group(1))}


def check():
    seg, errs, counts = table_from_code()
    have = table_in_data_operator()
    if have is None:
        errs.append("data_operator.gd 里找不到 const EXEC_SEG")
    else:
        for t, i in sorted(seg.items()):
            if t not in have:
                errs.append("EXEC_SEG 缺「%s」（应为 %d %s）" % (t, i, EXECUTORS[i][1]))
            elif have[t] != i:
                errs.append("EXEC_SEG「%s」= %d，应为 %d（%s）" % (t, have[t], i, EXECUTORS[i][1]))
        for t in sorted(set(have) - set(seg)):
            errs.append("EXEC_SEG 多了「%s」（没有执行器认它）" % t)
    detail = "%d 个执行器、%d 个 tag 无重叠，EXEC_SEG 一致（%s）" % (len(EXECUTORS), len(seg), " / ".join(str(c) for c in counts))
    return errs, detail


def main():
    if "--table" in sys.argv:
        seg, errs, _ = table_from_code()
        print("const EXEC_SEG := {")
        for t, i in sorted(seg.items(), key=lambda x: (x[1], x[0])):
            print('\t"%s": %d,   # %s' % (t, i, EXECUTORS[i][1]))
        print("}")
        for e in errs:
            print("!! " + e)
        return 1 if errs else 0
    errs, detail = check()
    for e in errs:
        print("!! " + e)
    print(detail if not errs else "不通过：%d 处" % len(errs))
    return 1 if errs else 0


if __name__ == "__main__":
    sys.exit(main())
