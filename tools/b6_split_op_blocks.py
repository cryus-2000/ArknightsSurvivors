# -*- coding: utf-8 -*-
# 用法见 docs/101 §7.3.5：python tools/b6_split_op_blocks.py game --write，再 python tools/b6_fix_infer.py game（拆分可复现：main 的 op_blocks.gd 有新提交时在新 main 上重跑）
"""B6 ①：把 op_blocks.gd 按段拆到 scripts/characters/blocks/，用继承链串起来，op_blocks.gd 留作门面（extends 最后一个文件）。
用法：python split_ob.py <game_dir> [--write]
- 顶层条目：static func / const / static var；条目前面的注释、空行跟着下一个条目走
- 按行号区间分到文件；链的顺序 = ORDER；早文件引用晚文件的函数 → 改写成 _F().名(…)（_F() = 运行时 load 门面）；
  被早文件引用的常量 / 静态变量上提到 ob_core（连同它们依赖的）
"""
import sys, os, re, collections

G = sys.argv[1]
WRITE = "--write" in sys.argv
SRC = os.path.join(G, "scripts", "characters", "op_blocks.gd")
OUTD = os.path.join(G, "scripts", "characters", "blocks")
lines = open(SRC, encoding="utf-8", newline="").read().split("\n")
assert lines[-1] == ""
lines = lines[:-1]
N = len(lines)

RANGES = [(1, "ob_core"), (511, "ob_check"), (896, "ob_fx"), (1441, "ob_vortex"), (1925, "seg_hoshiguma"), (2105, "seg_angelina"),
          (2372, "ob_core"), (2509, "seg_texas"), (3242, "seg_exusiai"), (3800, "ob_summon"), (5826, "ob_elite"), (5958, "seg_exusiai"),
          (6003, "ob_elite"), (6468, "ob_hw"), (6785, "seg_skadi"), (7153, "seg_eyjafjalla"), (7902, "seg_logos"), (8617, "seg_ulpianus"),
          (9535, "ob_hw"), (9593, "seg_logos"), (9760, "seg_eyjafjalla"), (9858, "seg_ulpianus"), (10022, "ob_hw"), (10157, "seg_irene"),
          (10602, "ob_hw"), (11049, "seg_specter"), (11523, "seg_lumen"), (12173, "seg_mizuki"), (12767, "ob_hw"), (12805, "seg_specter"),
          (12908, "seg_irene"), (12981, "seg_lumen"), (13079, "seg_mizuki"), (13256, "ob_hw"), (13514, "seg_siege"), (14040, "seg_suzuran"),
          (14663, "seg_wisadel"), (15510, "seg_saria"), (16235, "ob_hw"), (16516, "seg_skalter")]
ORDER = ["ob_core", "ob_check", "ob_fx", "ob_vortex", "ob_summon", "ob_elite", "ob_hw", "seg_hoshiguma", "seg_angelina", "seg_texas", "seg_exusiai",
         "seg_skadi", "seg_eyjafjalla", "seg_logos", "seg_ulpianus", "seg_irene", "seg_specter", "seg_lumen", "seg_mizuki", "seg_siege",
         "seg_suzuran", "seg_wisadel", "seg_saria", "seg_skalter"]


def file_of(ln):
    f = None
    for s, n in RANGES:
        if ln >= s:
            f = n
    return f


head_re = re.compile(r"^(static func ([A-Za-z_0-9]+)|const ([A-Za-z_0-9]+)|static var ([A-Za-z_0-9]+))")
starts = []
for i, l in enumerate(lines):
    m = head_re.match(l)
    if m:
        kind = "func" if m.group(2) else ("const" if m.group(3) else "svar")
        starts.append((i, kind, m.group(2) or m.group(3) or m.group(4)))
ext_i = next(i for i, l in enumerate(lines) if l.startswith("extends "))
items = []
for k, (i, kind, name) in enumerate(starts):
    end = starts[k + 1][0] if k + 1 < len(starts) else N
    items.append({"name": name, "kind": kind, "s": i, "e": end})
for k, it in enumerate(items):
    if k + 1 >= len(items):
        continue
    j = it["e"]
    while j - 1 > it["s"] and (lines[j - 1].startswith("#") or lines[j - 1].strip() == ""):
        j -= 1
    it["e2"] = j
    items[k + 1]["lead"] = j
for it in items:
    it.setdefault("e2", it["e"])
    it.setdefault("lead", it["s"])
items[0]["lead"] = ext_i + 1
for it in items:
    it["file"] = file_of(it["s"] + 1)
names = {it["name"]: it for it in items}
assert len(names) == len(items), "重名"

IDENT = re.compile(r"(?<![\w.$])([A-Za-z_][A-Za-z_0-9]*)\b")
STRLIT = re.compile(r'"(?:[^"\\]|\\.)*"|\'(?:[^\'\\]|\\.)*\'')
NUL = chr(0)


def masked(l):
    m0 = STRLIT.sub(lambda m: NUL * len(m.group(0)), l)
    ci = m0.find("#")
    if ci >= 0:
        m0 = m0[:ci] + NUL * (len(m0) - ci)
    return m0


def refs(it):
    out = set()
    for li in range(it["s"], it["e2"]):
        for m in IDENT.finditer(masked(lines[li])):
            if m.group(1) in names:
                out.add(m.group(1))
    return out


pos = {f: i for i, f in enumerate(ORDER)}
hoisted = set()
changed = True
while changed:
    changed = False
    for it in items:
        for n in refs(it):
            t = names[n]
            if t["kind"] != "func" and pos[t["file"]] > pos[it["file"]]:
                t["file"] = "ob_core"
                hoisted.add(n)
                changed = True
print("上提到 ob_core：", sorted(hoisted))

back = collections.Counter()
bad = []
rewrites = {}
for it in items:
    fi = pos[it["file"]]
    for li in range(it["s"], it["e2"]):
        mk = masked(lines[li])
        repl = []
        for m in IDENT.finditer(mk):
            n = m.group(1)
            if n not in names:
                continue
            tgt = names[n]
            if pos[tgt["file"]] <= fi:
                continue
            if tgt["kind"] == "func":
                if mk[m.end():m.end() + 1] != "(":
                    bad.append((it["file"], li + 1, n, "函数当值用"))
                    continue
                if li == it["s"] and n == it["name"]:
                    continue
                repl.append(m.start())
                back[(it["file"], tgt["file"])] += 1
            else:
                bad.append((it["file"], li + 1, n, tgt["kind"]))
        if repl:
            s = lines[li]
            for p0 in sorted(repl, reverse=True):
                s = s[:p0] + "_F()." + s[p0:]
            rewrites[li] = s

cnt = collections.Counter(i["file"] for i in items)
for f in ORDER:
    print("  %-16s %4d 条目 %6d 行" % (f, cnt[f], sum(i["e2"] - i["lead"] for i in items if i["file"] == f)))
print("反向函数调用（改写成 _F()）：", sum(back.values()))
for (a, b), c in back.most_common(12):
    print("   %s -> %s : %d" % (a, b, c))
print("剩余问题：", len(bad))
for x in bad[:40]:
    print("   ", x)
if not WRITE:
    sys.exit(0)
assert not bad

os.makedirs(OUTD, exist_ok=True)
header = lines[:ext_i]
prev = None
for f in ORDER:
    body = []
    for it in sorted([i for i in items if i["file"] == f], key=lambda x: x["s"]):
        for li in range(it["lead"], it["e2"]):
            body.append(rewrites.get(li, lines[li]))
        body.append("")
    out = ["## 干员积木 · %s（docs/101 §7.3 B6 ①，10-15：由 op_blocks.gd 按段拆出，内容与注释照搬；继承链与门面见 op_blocks.gd）" % f]
    if prev is None:
        out += header
        out += ["extends RefCounted", "",
                "## 门面（op_blocks.gd = 链尾）：链上早的文件调用晚的文件里的函数时经 _F() 运行时转发（B6 ② 直连 / ③ 单播后去掉）",
                "static var _facade = null", "",
                "static func _F():", "\tif _facade == null:", '\t\t_facade = load("res://scripts/characters/op_blocks.gd")', "\treturn _facade", ""]
    else:
        out += ['extends "res://scripts/characters/blocks/%s.gd"' % prev, ""]
    txt = "\n".join(out + body)
    txt = re.sub(r"\n{4,}", "\n\n\n", txt).rstrip("\n") + "\n"
    open(os.path.join(OUTD, f + ".gd"), "w", encoding="utf-8", newline="").write(txt)
    prev = f
facade = "\n".join(header) + "\n" + \
    "## B6 ①（docs/101 §7.3，10-15）：本文件只剩门面。内容按段拆到 scripts/characters/blocks/，继承链 " + " → ".join(ORDER) + "；\n" + \
    "## 外部照旧 preload 本文件、调 OB.<函数> / 读 OB.<常量>（沿继承链解析）。改积木请改 blocks/ 下对应的段文件。\n" + \
    'extends "res://scripts/characters/blocks/%s.gd"\n' % ORDER[-1]
open(SRC, "w", encoding="utf-8", newline="").write(facade)
print("写好", len(ORDER), "个文件")
