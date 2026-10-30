# -*- coding: utf-8 -*-
"""check.py --changed 的选项引擎（docs/204 §2）：改动路径 → tools/check_map.json 的规则 → 要跑的检查组。
纯函数，不开 Godot、不跑 git（git 由 check.py 传进来）。规则先匹配先生效；全局公共文件走 escalate（升级为分支全量）；
没有规则命中的路径走 unknown（core + 抽样冒烟）并在输出里点名，防止漏映射悄悄漏测。
"""
import json
import os
import re

MAP_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "check_map.json")
BUILTIN = {"core", "prot", "repro", "smoke-sample", "op-tier", "test-file"}


def load_map(path=MAP_PATH):
    return json.load(open(path, encoding="utf-8"))


def glob_re(g):
    """** 跨目录、* 与 ? 不跨目录、{a,b} 可选"""
    out, i = "", 0
    while i < len(g):
        c = g[i]
        if g[i:i + 3] == "**/":
            out += "(?:.*/)?"
            i += 3
            continue
        if g[i:i + 2] == "**":
            out += ".*"
            i += 2
            continue
        if c == "*":
            out += "[^/]*"
        elif c == "?":
            out += "[^/]"
        elif c == "{":
            j = g.index("}", i)
            out += "(?:" + "|".join(re.escape(x) for x in g[i + 1:j].split(",")) + ")"
            i = j
        else:
            out += re.escape(c)
        i += 1
    return re.compile("^" + out + "$")


def scene_ops(extra, ids):
    """场景回归参数里出现的干员（--op= / --squad=）：这些场景在对应干员改动时要跑"""
    found = set()
    for a in extra:
        m = re.match(r"--(?:op|squad)=(.*)", a)
        if m:
            found |= set(x for x in m.group(1).split(",") if x in ids)
    return found


def _ops_of(path, mode, ids, alias):
    name = os.path.basename(path)
    stem = name.split(".")[0]
    if mode == "stem":
        return {stem} if stem in ids else set()
    if mode == "seg":
        x = alias.get(stem[4:], stem[4:])
        return {x} if x in ids else set()
    if mode == "art":
        m = re.match(r"game/art/operators/([^/]+)/", path)
        if m and m.group(1) in ids:
            return {m.group(1)}
        hit = max((o for o in ids if name.startswith("op_" + o + "_") or name.startswith("op_" + o + "@")), key=len, default=None)
        return {hit} if hit else set()
    return set()


def decide(files, ids, scene_regs, text_only=lambda p: False, m=None):
    """返回 {full, groups, ops, scenes, rows, unmapped}。rows = [(文件, 规则 glob 或原因, 组列表)] 供 --explain 打印"""
    m = m or load_map()
    ids = set(ids)
    rules = [(glob_re(r["glob"]), r) for r in m["rules"]]
    esc = [glob_re(g) for g in m.get("escalate", [])]
    alias = m.get("op_alias", {})
    groups, ops, rows, unmapped, scenes, full = set(), set(), [], [], set(), False
    for p in files:
        if any(e.match(p) for e in esc):
            full = True
            rows.append((p, "escalate（全局公共文件）", ["full"]))
            continue
        if p.startswith("game/data/") and p.endswith(".json") and text_only(p):
            groups.add("core")
            rows.append((p, "只改说明字段", ["core"]))
            continue
        hit = next((r for rx, r in rules if rx.match(p)), None)
        if hit is None:
            groups |= set(m.get("unknown", []))
            unmapped.append(p)
            rows.append((p, "未映射 → unknown", list(m.get("unknown", []))))
            continue
        g = list(hit["groups"])
        if hit.get("ops"):
            o = _ops_of(p, hit["ops"], ids, alias)
            if o:
                ops |= o
            else:
                g = [x for x in g if x != "op-tier"] + ["core"]   # 召唤物等附属帧条 / 非干员文件：核心契约即可
        if "test-file" in g:
            name = os.path.basename(p).split(".")[0]
            g.remove("test-file")
            ks = {k for k, v in scene_regs.items() if v[1].split(".")[0] == name}
            scenes |= ks
            if name == "prot_test":
                g.append("prot")
            if name == "test_core":
                g.append("core")
        groups |= set(g)
        rows.append((p, hit["glob"], g + (["ops:" + ",".join(sorted(ops & _ops_of(p, hit.get("ops"), ids, alias)))] if hit.get("ops") and _ops_of(p, hit.get("ops"), ids, alias) else [])))
    if ops:
        groups.add("core")
    for g in groups:
        if g in BUILTIN:
            continue
        scenes |= set(m["groups"].get(g, {}).get("scenes", []))
    for o in ops:
        scenes |= set(m.get("op_scenes", {}).get(o, []))
        scenes |= {k for k, v in scene_regs.items() if o in scene_ops(v[3], ids)}
    scenes &= set(scene_regs)
    return {"full": full, "groups": groups, "ops": ops, "scenes": scenes, "rows": rows, "unmapped": unmapped}


def selftest(scene_regs, m=None):
    """映射自检：每个场景回归键至少属于一个组 / 干员场景表（或 full_only）；组里不能有不存在的键；规则里的组名要有定义"""
    m = m or load_map()
    errs = []
    known = set(scene_regs)
    covered = set(m.get("full_only", []))
    for g, v in m["groups"].items():
        for k in v["scenes"]:
            if k not in known:
                errs.append("check_map.json：组 %s 里的场景「%s」不在 SCENE_REGRESSIONS" % (g, k))
        covered |= set(v["scenes"])
    for o, ks in m.get("op_scenes", {}).items():
        for k in ks:
            if k not in known:
                errs.append("check_map.json：干员 %s 的场景「%s」不在 SCENE_REGRESSIONS" % (o, k))
        covered |= set(ks)
    for k in sorted(known - covered):
        errs.append("check_map.json：场景回归「%s」没有归任何组（只有全量会跑；归组或写进 full_only）" % k)
    for r in m["rules"]:
        for g in r["groups"]:
            if g not in BUILTIN and g not in m["groups"]:
                errs.append("check_map.json：规则 %s 用了没定义的组「%s」" % (r["glob"], g))
        try:
            glob_re(r["glob"])
        except (ValueError, re.error) as e:
            errs.append("check_map.json：glob %s 非法：%s" % (r["glob"], e))
    return errs
