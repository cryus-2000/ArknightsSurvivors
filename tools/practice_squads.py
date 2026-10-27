#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Boss 演练 · 成品分队数据（用户 10-28）：从 Boss 单场测试台的到场快照（docs/170）挑出随包发布的 game/data/practice_squads.json。

    python tools/practice_squads.py <快照目录>          # 目录里是 tools/boss_bench.py record 写的 <开局>_m<认知>_s<seed>_slot<k>.json

每个（开局 × 认知档 × 登场位）取中位强度的一份（先按等级、再按 最大生命 × 伤害倍率 排序取中间），只留重放成长需要的字段
（事件日志、等级 / 经验、藏品与选卡运行期变量、队长、核对指纹），丢掉场上杂兵 / 溟痕 / 随机数状态；
avg.<登场位> = 该登场位全部无认知快照的中位数值，给自选队长补到「打到这只 Boss 时的平均水平」。
"""
import json, os, re, statistics, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "game", "data", "practice_squads.json")
BUILD_VARS = ["level", "xp", "xp_need", "lamp_cap", "meta_once_heal"]
META_LABEL = {0: "无认知", 18: "18 细胞"}
AVG_KEYS = ["max_hp", "dmg_mult", "sp_mult", "armor", "regen", "dmg_taken_mult"]


def op_name(op):
    try:
        return json.load(open(os.path.join(ROOT, "game", "data", "characters", op + ".json"), encoding="utf-8")).get("name", op)
    except OSError:
        return op


def power(s):
    st = s.get("fp", {}).get("stats", {})
    return (int(s.get("fp", {}).get("level", 0)), float(st.get("max_hp", 0)) * float(st.get("dmg_mult", 1)))


def slim(s):
    return {"name": s.get("name"), "slot": s.get("slot"), "seed": s.get("seed"), "args": s.get("args", []),
            "events": s.get("events", []), "vars": {k: v for k, v in s.get("vars", {}).items() if k in BUILD_VARS},
            "objs": {k: v for k, v in s.get("objs", {}).items() if k in ("rfx", "progression")},
            "leader": s.get("leader", ""), "fp": s.get("fp", {})}


def main():
    src = sys.argv[1]
    groups, by_slot = {}, {}
    for f in sorted(os.listdir(src)):
        m = re.match(r"(.+)_m(\d+)_s(\d+)_slot(\d)\.json$", f)
        if not m:
            continue
        s = json.load(open(os.path.join(src, f), encoding="utf-8"))
        op, meta, slot = m.group(1), int(m.group(2)), int(m.group(4))
        groups.setdefault((op, meta), {}).setdefault(slot, []).append(s)
        if meta == 0:
            by_slot.setdefault(slot, []).append(s)
    order, squads = [], {}
    for (op, meta) in sorted(groups, key=lambda k: (k[0] != "wisadel", k[0] != "skadi", k[0], k[1])):
        sid = "%s_m%d" % (op, meta)
        slots = {}
        for slot, ss in sorted(groups[(op, meta)].items()):
            ss = sorted(ss, key=power)
            slots[str(slot)] = slim(ss[len(ss) // 2])
        squads[sid] = {"op": op, "meta": meta, "label": "%s开局分队 · %s" % (op_name(op), META_LABEL.get(meta, "%d 细胞" % meta)), "slots": slots}
        order.append(sid)
    avg = {}
    for slot, ss in sorted(by_slot.items()):
        a = {"level": int(statistics.median(int(s.get("fp", {}).get("level", 1)) for s in ss))}
        for k in AVG_KEYS:
            vals = [float(s.get("fp", {}).get("stats", {}).get(k)) for s in ss if s.get("fp", {}).get("stats", {}).get(k) is not None]
            if vals:
                a[k] = round(statistics.median(vals), 4)
        avg[str(slot)] = a
    data = {"_doc": "Boss 演练 · 成品分队（run/practice_squads.gd，tools/practice_squads.py 生成；来源：docs/170 测试台到场快照 %s）" % os.path.basename(os.path.normpath(src)),
            "order": order, "squads": squads, "avg": avg}
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        json.dump(data, f, ensure_ascii=False, separators=(",", ":"))
    print("%s：%d 支分队，%d KB；avg %s" % (OUT, len(order), os.path.getsize(OUT) // 1024, json.dumps(avg, ensure_ascii=False)))


if __name__ == "__main__":
    main()
