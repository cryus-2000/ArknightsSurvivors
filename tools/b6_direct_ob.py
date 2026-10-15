# -*- coding: utf-8 -*-
"""B6 ②：生产代码里经门面的 OB.<名> / OpBlocks.<名> 改成直连定义所在的 blocks 文件。用法：python direct_ob.py <game_dir> [--write]"""
import sys, os, re, glob, collections
G = sys.argv[1]
WRITE = "--write" in sys.argv
BD = os.path.join(G, "scripts", "characters", "blocks")
defs = {}
for p in glob.glob(os.path.join(BD, "*.gd")):
    f = os.path.basename(p)[:-3]
    for m in re.finditer(r"^(?:static func|const|static var) ([A-Za-z_0-9]+)", open(p, encoding="utf-8").read(), re.M):
        defs[m.group(1)] = f


def alias(f):
    return "".join(x.capitalize() for x in f.split("_"))   # ob_core → ObCore, seg_logos → SegLogos


TARGETS = [("scripts/characters/data_operator.gd", "OB"), ("scripts/characters/character.gd", "OpBlocks")]
for rel, ali in TARGETS:
    p = os.path.join(G, rel)
    s = open(p, encoding="utf-8", newline="").read()
    nl = "\r\n" if "\r\n" in s else "\n"
    used = collections.Counter()
    miss = []

    def rep(m):
        n = m.group(1)
        if n not in defs:
            miss.append(n)
            return m.group(0)
        used[defs[n]] += 1
        return alias(defs[n]) + "." + n
    t = re.sub(r"(?<![\w.])%s\.([A-Za-z_][A-Za-z_0-9]*)" % ali, rep, s)
    print(rel, "改写", sum(used.values()), "处，涉及", len(used), "个文件；找不到", miss)
    if not WRITE:
        continue
    assert not miss
    # 原 const 门面行换成按文件的 preload（同位置，按名字排序）
    line_re = re.compile(r"^const %s = preload\(\"res://scripts/characters/op_blocks.gd\"\)[^\n]*$" % ali, re.M)
    m = line_re.search(t)
    assert m, "没找到门面 const"
    consts = nl.join('const %s = preload("res://scripts/characters/blocks/%s.gd")' % (alias(f), f) for f in sorted(used))
    note = "## B6 ②（docs/101 §7.3.6）：积木按定义所在的 blocks 文件直连（原 const %s = preload(op_blocks.gd) 门面）" % ali
    t = t[:m.start()] + note + nl + consts + t[m.end():]
    open(p, "w", encoding="utf-8", newline="").write(t)
