# -*- coding: utf-8 -*-
"""乌尔比安 pixelfx 放开版：把导出脚本打印的帧数写进 art.gd V6_FRAMES 的乌尔比安块（# pixelfx 放开版 · 乌尔比安 起止标记之间，每次整块重写）。
用法：python tools/pixelfx_export.py --only … | python tools/pixelfx_ulpianus_reg.py   （读 stdin 里 "fx_ulpianus_ul_…": [n, fps] 行，和已登记的合并）"""
import os, re, sys
ART = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "game", "scripts", "art.gd")
B, E = "\t# pixelfx 放开版 · 乌尔比安（claude/pixelfx-ul-ulpianus，开关 fx/px_unleashed；tools/pixelfx_ulpianus_reg.py 生成，别手改）\n", "\t# pixelfx 放开版 · 乌尔比安 end\n"
src = open(ART, encoding="utf-8").read()
cur = {}
if B in src:
    blk = src[src.index(B) + len(B):src.index(E)]
    cur = {m.group(1): m.group(2) for m in re.finditer(r'"((?:fx|proj)_ulpianus_ul_[a-z0-9_]+)": (\[[^\]]+\])', blk)}
for line in sys.stdin.read().splitlines():
    m = re.match(r'"((?:fx|proj)_ulpianus_ul_[a-z0-9_]+)": (\[[^\]]+\])', line.strip())
    if m:
        cur[m.group(1)] = m.group(2)
names = sorted(cur)
rows, row = [], []
for n in names:
    row.append('"%s": %s' % (n, cur[n]))
    if len(row) == 6:
        rows.append(row); row = []
if row:
    rows.append(row)
body = "".join("\t" + ", ".join(r) + ",\n" for r in rows)
if B in src:
    src = src[:src.index(B)] + B + body + src[src.index(E):]
else:
    anchor = "\t# pixelfx 不加限制试验（claude/pixelfx-unleashed-skadi"
    i = src.index(anchor)
    src = src[:i] + B + body + E + src[i:]
open(ART, "w", encoding="utf-8", newline="").write(src)
print("V6_FRAMES 乌尔比安 %d 条" % len(names))
