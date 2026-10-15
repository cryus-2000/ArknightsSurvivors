# -*- coding: utf-8 -*-
"""Boss 逐秒追踪探针（docs/95 §17.6 斥亡体组 28 局对照用；只读、不碰随机数，同 seed 结果不变）。

用法：在要测的检出目录里跑 `python3 tools/probes/btrace_patch.py [仓库根]`，给 game/scripts/run/autotest.gd 的 TRACE 打印后面插一段：
环境变量 KBTRACE=1 且 --balance --trace=1 时，游戏时间 ≥400 秒起每秒打印一行
  BTRACE t=<秒> hp=<队长生命>/<上限> boss=<type:hp/maxhp:状态:复苏:距离:wind:ai:标记>;... warns=<act>:<数量>,...
状态 A 活 / C 假死 / D 死；标记 R 狂暴、P 慌乱。配 balance_run --keep BTRACE 存进每局记录的 lines（每局最多 400 行，别同时 keep TRACE，会把名额占满）。
不入库到游戏代码：云端两侧检出后各打一次补丁，测完 git checkout -- game 还原。锚点是 TRACE 那行 print（fb38ad44 与 10-15 main 相同）。
"""
import os, sys

root = sys.argv[1] if len(sys.argv) > 1 else '.'
p = os.path.join(root, 'game', 'scripts', 'run', 'autotest.gd')
s = open(p, encoding='utf-8').read()
T = '\t'
anchor = (T * 3 + 'print("TRACE t=%.2f lv=%d k=%d hp=%.2f n=%d rng=%d pos=%.2f,%.2f h=%.3f" % '
          '[g.t, g.level, g.kills, g.hp, g.enemies.size(), g.rng.state, g.ppos.x, g.ppos.y, hsum])\n')
if 'BTRACE' in s:
    print('already patched')
    sys.exit(0)
assert s.count(anchor) == 1, 'TRACE anchor not found'
probe = '\n'.join([
    T * 3 + 'if OS.has_environment("KBTRACE") and g.t >= 400.0:',
    T * 4 + 'var bl := PackedStringArray()',
    T * 4 + 'for be in g.bosses:',
    T * 5 + 'var st: String = "D" if be.dead else ("C" if be.get("coma", false) else "A")',
    T * 5 + 'var fl: String = ("R" if be.get("rage", false) else "") + ("P" if be.get("panic", false) else "")',
    T * 5 + 'bl.append("%s:%.0f/%.0f:%s:%d:%.0f:%.2f:%s:%s" % [be.type, be.hp, be.maxhp, st, int(be.get("revives", 0)), be.pos.distance_to(g.ppos), float(be.get("wind", 0.0)), str(be.get("ai", "")), fl])',
    T * 4 + 'var wc: Dictionary = {}',
    T * 4 + 'for bw in g.warns:',
    T * 5 + 'if bw.owner.get("boss", false) and not bw.done:',
    T * 6 + 'wc[str(bw.act)] = int(wc.get(str(bw.act), 0)) + 1',
    T * 4 + 'var ws := PackedStringArray()',
    T * 4 + 'for k in wc:',
    T * 5 + 'ws.append("%s:%d" % [k, wc[k]])',
    T * 4 + 'print("BTRACE t=%.1f hp=%.0f/%.0f boss=%s warns=%s" % [g.t, g.hp, g.max_hp, ";".join(bl), ",".join(ws)])',
    ''])
s = s.replace(anchor, anchor + probe)
open(p, 'w', encoding='utf-8', newline='').write(s)
print('patched', p)
