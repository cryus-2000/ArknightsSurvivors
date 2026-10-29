# -*- coding: utf-8 -*-
"""graph_lint.py — 节点 / 引用完整性静态检查（只读原型，纯标准库，不开 Godot）。

用法：python -I graph_lint.py [仓库根（含 game/）] [--verbose]
退出码：有命中 1，否则 0。

建模（和 character.gd 的运行时一致）：
  成长线 = def.progression 数组，按顺序一个个 advance()；每个节点的「生效视图」= node_view：
    1) alt 无条件覆盖顶层（levelup/branch 开关已在 4825643b0 删除，alt 现在恒生效）
    2) 带 branch 的节点 = 路线选择点；选定路线 rid 后，branch[rid] / routes[rid] 覆盖字段（含 id）
    3) elite 节点的 id 视为 elite<level>
  可达节点 id 集 = 对 branch 路线展开后所有生效 id 的并集（没有 branch 节点时路线恒为 ""，routes 不生效）。
  blocks.progression 的键 / "node:<id>" 条件 / 路线 bot 字段都必须落在可达 id 集里，否则永远不会生效。
  元成长树 meta_tree：req 是前置边，必须无环、前置存在、全部节点在 order 与星图里。
  事件选项：运行时只有 endings._blocked() 会把选项灰掉（hp_pct<0 且生命<30%，或 need.mate/tradeable/later/room 不满足），
  所以「至少一个选项在最坏状态下可选」= 存在一个选项既无 need、又无负 hp_pct 的 op。
"""
import bisect
import glob
import json
import os
import re
import sys
import time

T0 = time.time()
VERBOSE = False
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GAME = os.path.join(ROOT, "game")
DATA = os.path.join(GAME, "data")


def configure(root):
    """指定仓库根（含 game/）；被 check.py 导入时调用，命令行入口也走这里"""
    global ROOT, GAME, DATA
    ROOT = os.path.abspath(root)
    GAME = os.path.join(ROOT, "game")
    DATA = os.path.join(GAME, "data")

HITS = {}      # rule -> [(file, path, msg)]


def rel(p):
    return os.path.relpath(p, ROOT).replace("\\", "/")


# ---------------------------------------------------------------- JSON 带行号定位（只在出命中时才解析）
class _Pos:
    """极简 JSON 扫描器：只为取 路径 → 行号，不做校验"""
    def __init__(self, s):
        self.s, self.i, self.map = s, 0, {}
        self.nl = [m.start() for m in re.finditer("\n", s)]

    def ln(self, i):
        return bisect.bisect_right(self.nl, i - 1) + 1

    def ws(self):
        s = self.s
        while self.i < len(s) and s[self.i] in " \t\r\n":
            self.i += 1

    def val(self, path):
        self.ws()
        c = self.s[self.i]
        self.map.setdefault(path, self.ln(self.i))
        if c == "{":
            self.i += 1
            self.ws()
            while self.s[self.i] != "}":
                self.ws()
                k_start = self.i
                k = self.string()
                self.ws()
                self.i += 1  # :
                self.map[path + (k,)] = self.ln(k_start)
                self.val(path + (k,))
                self.ws()
                if self.s[self.i] == ",":
                    self.i += 1
                    self.ws()
            self.i += 1
        elif c == "[":
            self.i += 1
            self.ws()
            n = 0
            while self.s[self.i] != "]":
                self.val(path + (n,))
                n += 1
                self.ws()
                if self.s[self.i] == ",":
                    self.i += 1
                    self.ws()
            self.i += 1
        elif c == '"':
            self.string()
        else:
            while self.s[self.i] not in ",}] \t\r\n":
                self.i += 1

    def string(self):
        s = self.s
        j = self.i + 1
        while s[j] != '"':
            j += 2 if s[j] == "\\" else 1
        out = s[self.i + 1:j]
        self.i = j + 1
        return out


_posmaps = {}


def line_of(file, path):
    if file not in _posmaps:
        try:
            with open(file, encoding="utf-8") as f:
                p = _Pos(f.read())
            p.val(())
            _posmaps[file] = p.map
        except Exception:
            _posmaps[file] = {}
    m = _posmaps[file]
    path = tuple(path)
    while path and path not in m:
        path = path[:-1]
    return m.get(path, 0)


def hit(rule, file, path, msg):
    HITS.setdefault(rule, []).append((file, tuple(path), msg))


def pstr(path):
    out = ""
    for p in path:
        out += "[%d]" % p if isinstance(p, int) else ("." if out else "") + str(p)
    return out


def load(rel_path):
    p = os.path.join(DATA, rel_path)
    with open(p, encoding="utf-8") as f:
        return p, json.load(f)


# ---------------------------------------------------------------- 资源索引
with open(os.path.join(GAME, "art", "index.json"), encoding="utf-8") as _f:
    ART = json.load(_f)
ART_ALIAS = {}
try:
    _t = open(os.path.join(GAME, "scripts", "art.gd"), encoding="utf-8").read()
    _m = re.search(r"const ALIAS := \{(.*?)\n\}", _t, re.S)
    for a, b in re.findall(r'"([^"]+)":\s*"([^"]+)"', _m.group(1)):
        ART_ALIAS[a] = b
except Exception:
    pass
SFX = {os.path.basename(p)[:-4] for p in glob.glob(os.path.join(GAME, "audio", "sfx", "*.wav"))}
VOICE = {os.path.basename(p)[:-4] for p in glob.glob(os.path.join(GAME, "audio", "voice", "*.ogg"))}


def art_has(name):
    """art.gd has_override / tex 的口径：索引里有 name / name@2x / name@1x，或经别名，或 art/px/<name>.png"""
    for n in (name, name + "@2x", name + "@1x"):
        if n in ART:
            return True
    al = ART_ALIAS.get(name)
    if al and (al in ART or al + "@2x" in ART or al + "@1x" in ART):
        return True
    return os.path.exists(os.path.join(GAME, "art", "px", name + ".png"))


def walk(o, path=()):
    yield path, o
    if isinstance(o, dict):
        for k, v in o.items():
            yield from walk(v, path + (k,))
    elif isinstance(o, list):
        for i, v in enumerate(o):
            yield from walk(v, path + (i,))


# ================================================================ 干员成长线
def node_eid(v):
    if v.get("type") == "elite":
        return "elite%d" % int(v.get("level", 0))
    return str(v.get("id", ""))


def check_characters():
    passives = set(load("cards.json")[1].get("passives", {}))
    relic_ids = {str(i["id"]) for i in load("relics.json")[1]["items"]}
    chars = {}
    for f in sorted(glob.glob(os.path.join(DATA, "characters", "*.json"))):
        with open(f, encoding="utf-8") as fh:
            chars[f] = json.load(fh)
    char_ids = {d["id"] for d in chars.values()}
    for f, d in chars.items():
        cid = d["id"]
        pg = d.get("progression", [])
        bp = d.get("blocks", {}).get("progression", {})
        sk = d.get("skills", [])
        # ---- R1 路线 id 一致性
        branch_keys = None
        branch_idx = None
        for i, n in enumerate(pg):
            if isinstance(n.get("branch"), dict):
                if branch_keys is None:
                    branch_keys, branch_idx = list(n["branch"].keys()), i
                else:
                    hit("R1", f, ("progression", i, "branch"), "%s：出现第二个 branch 节点（路线只在第一个选）" % cid)
        for i, n in enumerate(pg):
            if isinstance(n.get("routes"), dict):
                if branch_keys is None:
                    hit("R1", f, ("progression", i, "routes"), "%s：routes 节点前没有 branch 节点，路线恒为空、routes 永不生效" % cid)
                elif i < branch_idx:
                    hit("R1", f, ("progression", i, "routes"), "%s：routes 节点在 branch 节点之前" % cid)
                elif set(n["routes"]) != set(branch_keys):
                    hit("R1", f, ("progression", i, "routes"), "%s：routes 键 %s 与 branch 路线 %s 不一致" % (cid, sorted(n["routes"]), sorted(branch_keys)))
            if "bot" in n and n["bot"] not in (n.get("branch") or {}):
                hit("R1", f, ("progression", i, "bot"), "%s：bot 路线「%s」不在该节点的 branch 里" % (cid, n["bot"]))
        # ---- R2 可达 id
        reach = {}
        declared = {}
        for i, n in enumerate(pg):
            if n.get("type") == "elite":
                reach.setdefault("elite%d" % int(n.get("level", 0)), i)
                continue
            base = dict(n)
            if isinstance(n.get("alt"), dict):
                base.update(n["alt"])
                base.pop("alt", None)
            alts = n.get("branch", n.get("routes"))
            route_chosen = branch_keys is not None and i >= branch_idx
            if isinstance(alts, dict) and route_chosen:
                for rk, rv in alts.items():
                    reach.setdefault(str(rv.get("id", "")), i)
            else:
                reach.setdefault(node_eid(base), i)
            # 声明过的 id（顶层 / alt / branch / routes）
            if n.get("type") == "custom":
                declared.setdefault(str(n.get("id", "")), ("progression", i, "id"))
                if isinstance(n.get("alt"), dict):
                    declared.setdefault(str(n["alt"].get("id", "")), ("progression", i, "alt", "id"))
                for key in ("branch", "routes"):
                    if isinstance(n.get(key), dict):
                        for rk, rv in n[key].items():
                            declared.setdefault(str(rv.get("id", "")), ("progression", i, key, rk, "id"))
        for eid, path in declared.items():
            if eid not in reach:
                hit("R2", f, path, "%s：节点「%s」在任何路线下生效视图里都不出现（被 alt / 路线覆盖）%s" % (cid, eid, "；blocks.progression.%s 积木随之失效" % eid if eid in bp else ""))
        for k in bp:
            if k not in reach and k not in declared and k not in ("elite1", "elite2"):
                hit("R2", f, ("blocks", "progression", k), "%s：blocks.progression.%s 不对应任何节点" % (cid, k))
        # ---- R3 技能解锁 / 精英节点链
        levels = [(i, int(n["level"])) for i, n in enumerate(pg) if n.get("type") == "elite"]
        for lv in range(1, max(0, len(sk) - 1) + 1):
            if lv not in {l for _, l in levels}:
                hit("R3", f, ("progression",), "%s：有 %d 个技能（解锁条件 elite>=下标），成长线却没有 elite level %d 节点" % (cid, len(sk), lv))
        for a, b in zip(levels, levels[1:]):
            if b[1] <= a[1]:
                hit("R3", f, ("progression", b[0], "level"), "%s：精英节点顺序错（level %d 排在 level %d 之后）" % (cid, b[1], a[1]))
        for i, n in enumerate(pg):
            req = n.get("requires", {})
            for rid in req.get("relic", []):
                if str(rid) not in relic_ids:
                    hit("R5", f, ("progression", i, "requires", "relic"), "%s：requires.relic 藏品 %s 不存在" % (cid, rid))
            if "doctor_passive" in req and req["doctor_passive"] not in passives:
                hit("R5", f, ("progression", i, "requires", "doctor_passive"), "%s：doctor_passive %s 不在 cards.passives" % (cid, req["doctor_passive"]))
        for path, v in walk(d.get("blocks", {}), ("blocks",)):
            if isinstance(v, str):
                for m in re.finditer(r"\bnode:([A-Za-z0-9_]+)", v):
                    if m.group(1) not in reach:
                        hit("R3", f, path, "%s：条件 node:%s 依赖的节点不可达，条件永不满足" % (cid, m.group(1)))
                for m in re.finditer(r"\bskill_active:(\d+)", v):
                    if int(m.group(1)) >= len(sk):
                        hit("R3", f, path, "%s：条件 skill_active:%s 超出技能数 %d" % (cid, m.group(1), len(sk)))
        # ---- R5 $变量 / 贴图 / 音效
        known = set(d.get("base", {})) | {"k_atk", "k_pow", "k_kill"}   # operator_defs.text_base 注入的派生键
        for path, v in walk(d):
            if not isinstance(v, str) or not path:
                continue
            if "$" in v and path[0] != "base" and not str(path[-1]).startswith("_"):
                for m in re.finditer(r"\$([A-Za-z_][A-Za-z0-9_]*)", v):
                    if m.group(1) not in known:
                        hit("R5", f, path, "%s：引用 $%s，base 里没有这个键" % (cid, m.group(1)))
            k = path[-1]
            if k == "icon" and v and not art_has(v):
                hit("R5", f, path, "%s：icon「%s」在 art 索引里找不到" % (cid, v))
            elif k == "tex" and v and not v.startswith("res://") and not art_has(v):
                hit("R5", f, path, "%s：tex「%s」在 art 索引里找不到" % (cid, v))
            elif k == "sfx" and v and "op_%s_%s" % (cid, v) not in SFX and v not in SFX:   # Sfx.op(id, kind) → op_<干员>_<kind>
                hit("R5", f, path, "%s：sfx「%s」没有 audio/sfx/op_%s_%s.wav" % (cid, v, cid, v))
            elif v.startswith("res://") and not os.path.exists(os.path.join(GAME, v[6:])):
                hit("R5", f, path, "%s：%s 文件不存在" % (cid, v))
    p, ps = load("practice_squads.json")
    for sk_id, sq in ps["squads"].items():
        if sq["op"] not in char_ids:
            hit("R5", p, ("squads", sk_id, "op"), "practice_squads：干员 %s 不存在" % sq["op"])
    p, sy = load("synergy.json")
    for i, pr in enumerate(sy.get("pairs", [])):
        for j, dr in enumerate(pr.get("dirs", [])):
            for k in ("from", "to"):
                if dr.get(k) not in char_ids:
                    hit("R5", p, ("pairs", i, "dirs", j, k), "synergy：干员 %s 不存在" % dr.get(k))
            v = dr.get("voice")
            if v and "%s_%s" % (dr.get("from"), v) not in VOICE and "%s_%s" % (dr.get("to"), v) not in VOICE:
                hit("R9", p, ("pairs", i, "dirs", j, "voice"), "synergy：语音键 %s 两个干员都没有 ogg（运行时静默）" % v)
    for i, gr in enumerate(sy.get("groups", [])):
        for j, m in enumerate(gr.get("members", [])):
            if m not in char_ids:
                hit("R5", p, ("groups", i, "members", j), "synergy：干员 %s 不存在" % m)


# ================================================================ 元成长树
def check_meta():
    p, t = load("meta_tree.json")
    nodes = t["nodes"]
    for k, n in nodes.items():
        r = n.get("req")
        if r is not None and r not in nodes:
            hit("R3", p, ("nodes", k, "req"), "meta_tree：%s 的前置 %s 不存在" % (k, r))
    for k in nodes:
        seen, cur = [], k
        while cur in nodes and nodes[cur].get("req") is not None:
            if cur in seen:
                hit("R3", p, ("nodes", k, "req"), "meta_tree：%s 的前置链成环 %s" % (k, "→".join(seen + [cur])))
                break
            seen.append(cur)
            cur = nodes[cur]["req"]
    order = t.get("order", [])
    for k in nodes:
        if k not in order:
            hit("R2", p, ("nodes", k), "meta_tree：节点 %s 不在 order 里" % k)
    for i, k in enumerate(order):
        if k not in nodes:
            hit("R2", p, ("order", i), "meta_tree：order 里的 %s 没有节点定义" % k)
    if len(order) != len(set(order)):
        hit("R2", p, ("order",), "meta_tree：order 有重复项")
    pos = {k: i for i, k in enumerate(order)}
    for k, n in nodes.items():
        r = n.get("req")
        if r in pos and k in pos and pos[r] > pos[k]:
            hit("R3", p, ("nodes", k, "req"), "meta_tree：%s 在 order 里排在前置 %s 之前" % (k, r))
    p2, roots = load("meta_roots.json")
    stars = roots["scene"]["stars"]
    for k in nodes:
        if k not in stars:
            hit("R2", p2, ("scene", "stars"), "meta_roots：星图缺节点 %s（界面画不出来）" % k)
    for k in stars:
        if k not in nodes:
            hit("R2", p2, ("scene", "stars", k), "meta_roots：星图有 %s，meta_tree 没有" % k)
    for k in roots["scene"].get("lside", {}):
        if k not in nodes:
            hit("R2", p2, ("scene", "lside", k), "meta_roots：lside 有 %s，meta_tree 没有" % k)
    try:
        sd = open(os.path.join(GAME, "scripts", "core", "stat_defs.gd"), encoding="utf-8").read()
    except Exception:
        sd = ""
    if sd:
        for k, n in nodes.items():
            for i, ef in enumerate(n.get("effects", [])):
                st = ef.get("stat")
                if st and st not in sd:
                    hit("R5", p, ("nodes", k, "effects", i, "stat"), "meta_tree：stat「%s」在 stat_defs.gd 里没出现" % st)


# ================================================================ 事件
def check_events():
    pr, relics = load("relics.json")
    relic_ids = {str(i["id"]) for i in relics["items"]}
    rarities = {i.get("rarity") for i in relics["items"]}
    lanes = set(relics.get("lane_names", {}))
    pe, ev2 = load("events_v2.json")
    pw, waves = load("waves.json")
    enemies = load("enemies.json")[1]["enemies"]
    sources = [(pe, ("events",), ev2["events"]), (pw, ("events",), waves["events"])]
    all_ids = {e["id"] for _, _, es in sources for e in es}
    cross_count = len(ev2["cross"].get("mid", []))
    for f, base, evs in sources:
        for ei, ev in enumerate(evs):
            ep = base + (ei,)
            opts = ev.get("options", [])

            def never_blocked(o):
                if o.get("need"):
                    return False
                for op in o.get("ops", []):
                    if isinstance(op, dict) and float(op.get("hp_pct", 0) or 0) < 0:
                        return False
                return True
            if not opts:
                hit("R4", f, ep + ("options",), "事件 %s：没有任何选项" % ev.get("id"))
            elif not any(never_blocked(o) for o in opts):
                hit("R4", f, ep + ("options",), "事件 %s：每个选项都带 need 或扣生命条件，存在全灰状态" % ev.get("id"))
            for oi, o in enumerate(opts):
                op_p = ep + ("options", oi)
                if o.get("next") and o["next"] not in all_ids:
                    hit("R5", f, op_p + ("next",), "事件 %s：next 指向不存在的事件 %s" % (ev.get("id"), o["next"]))
                for xi, op in enumerate(o.get("ops", [])):
                    if not isinstance(op, dict):
                        continue
                    xp = op_p + ("ops", xi)
                    if "relic" in op and str(op["relic"]) not in relic_ids:
                        hit("R5", f, xp + ("relic",), "事件 %s：藏品 %s 不存在" % (ev.get("id"), op["relic"]))
                    for sub in ("relic_lane", "relic_choice"):
                        if isinstance(op.get(sub), dict):
                            r = op[sub].get("rarity")
                            if r is not None and r not in rarities:
                                hit("R5", f, xp + (sub, "rarity"), "事件 %s：稀有度「%s」不在 relics.json 里" % (ev.get("id"), r))
                    if isinstance(op.get("chance"), (int, float)) and not (0 < op["chance"] <= 1):
                        hit("R5", f, xp + ("chance",), "事件 %s：chance %s 不在 (0,1]" % (ev.get("id"), op["chance"]))
            for li, ln in enumerate(ev.get("lanes", [])):
                if ln not in lanes:
                    hit("R5", f, ep + ("lanes", li), "事件 %s：lane「%s」不在 relics.lane_names" % (ev.get("id"), ln))
            cg = str(ev.get("cg") or ev.get("id"))
            if not os.path.exists(os.path.join(GAME, "art", "event_cg", "hi", cg + ".webp")):
                hit("R6", f, ep + ("id",), "事件 %s：插画 art/event_cg/hi/%s.webp 不存在（运行时 ResourceLoader.exists 失败 → 无插画，软缺失）" % (ev.get("id"), cg))
            q = ev.get("req", {})
            if f == pe and q.get("after_cross", 0) > cross_count:
                hit("R4", f, ep + ("req", "after_cross"), "事件 %s：after_cross %s 超过路口数 %d，永不出现" % (ev.get("id"), q["after_cross"], cross_count))
            if q.get("before") is not None and float(q["before"]) <= 0:
                hit("R4", f, ep + ("req", "before"), "事件 %s：before<=0 永不出现" % ev.get("id"))
    en = {k for k in enemies if not k.startswith("_")}

    def chk_en(path, v):
        if isinstance(v, str) and v not in en:
            hit("R5", pw, path, "waves：敌人 id「%s」不在 enemies.json" % v)
    for ti, th in enumerate(waves["threat"]):
        for key in ("pool", "horde", "horde_lead"):
            for j, v in enumerate(th.get(key, [])):
                if v != "elite":
                    chk_en(("threat", ti, key, j), v)
        for mi, mx in enumerate(th.get("horde_mix", [])):
            for j, v in enumerate(mx.get("body", [])):
                chk_en(("threat", ti, "horde_mix", mi, "body", j), v)
            for j, x in enumerate(mx.get("extra", [])):
                chk_en(("threat", ti, "horde_mix", mi, "extra", j, "id"), x.get("id"))
    for path, v in walk(waves.get("cross_deck", {}), ("cross_deck",)):
        if path and "pool" in str(path[-1]) and isinstance(v, list):
            for j, e in enumerate(v):
                for jj, ee in enumerate(e if isinstance(e, list) else [e]):
                    chk_en(path + ((j, jj) if isinstance(e, list) else (j,)), ee)
    for k, e in waves.get("endings", {}).items():
        chk_en(("endings", k, "boss"), e.get("boss"))


# ================================================================ 藏品
def check_relics():
    pr, relics = load("relics.json")
    pf, fx = load("relic_effects.json")
    ids = {str(i["id"]) for i in relics["items"]}
    fxk = set(fx.get("relics", {}))
    for k in sorted(fxk - ids, key=lambda s: (len(s), s)):
        hit("R5", pf, ("relics", k), "relic_effects：%s 在 relics.json items 里没有" % k)
    for i, it in enumerate(relics["items"]):
        rid = str(it["id"])
        if rid not in fxk:
            hit("R5", pr, ("items", i, "id"), "relics.json：藏品 %s「%s」在 relic_effects.json 里没有效果定义" % (rid, it.get("name")))
        if not art_has("relic_" + rid):
            hit("R5", pr, ("items", i, "id"), "relics.json：藏品 %s 缺图标 relic_%s" % (rid, rid))
        if it.get("lane") and it["lane"] not in relics["lane_names"] and it["lane"] != "general":
            hit("R5", pr, ("items", i, "lane"), "relics.json：藏品 %s lane「%s」不在 lane_names" % (rid, it["lane"]))
    if len(ids) != len(relics["items"]):
        hit("R5", pr, ("items",), "relics.json：id 有重复")


def check_misc():
    p, m = load("medals.json")
    ids = [x["id"] for x in m["medals"]]
    if len(ids) != len(set(ids)):
        hit("R5", p, ("medals",), "medals：id 重复")
    for f in sorted(glob.glob(os.path.join(DATA, "*.json")) + glob.glob(os.path.join(DATA, "maps", "*.json"))):
        with open(f, encoding="utf-8") as fh:
            d = json.load(fh)
        for path, v in walk(d):
            if isinstance(v, str) and v.startswith("res://") and " " not in v and not v.endswith("/"):
                if not os.path.exists(os.path.join(GAME, v[6:])):
                    hit("R5", f, path, "%s 文件不存在" % v)


def run(root=None):
    """跑全部规则，返回 {规则: [(文件, 键路径, 说明)]}（每次调用重新计算）；R6 / R9 是提示，不算硬命中"""
    if root:
        configure(root)
    HITS.clear()
    _posmaps.clear()
    check_characters()
    check_meta()
    check_events()
    check_relics()
    check_misc()
    return HITS


def format_hit(f, path, msg):
    return "%s:%s [%s] %s" % (rel(f), line_of(f, path) or "?", pstr(path), msg)


def main():
    global VERBOSE
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    VERBOSE = "--verbose" in sys.argv
    run(args[0] if args else os.getcwd())
    names = {
        "R1": "成长线 / 路线 id 对不上",
        "R2": "节点不可达 / 死积木",
        "R3": "依赖断链（前置 / 技能解锁 / node: 条件）",
        "R4": "事件选项全灰 / 事件永不出现",
        "R5": "引用的键 / 资源不存在",
        "R6": "软缺失：缺素材但运行时降级（无插画等）",
        "R9": "提示：缺素材但运行时静默",
    }
    total = 0
    for r in ["R1", "R2", "R3", "R4", "R5", "R6", "R9"]:
        hs = HITS.get(r, [])
        print("== %s %s：%d 条" % (r, names[r], len(hs)))
        if r not in ("R6", "R9"):
            total += len(hs)
        shown = hs if (VERBOSE or len(hs) <= 60) else hs[:60]
        for f, path, msg in shown:
            print("  %s:%s  [%s]  %s" % (rel(f), line_of(f, path) or "?", pstr(path), msg))
        if len(shown) < len(hs):
            print("  … 另 %d 条（--verbose 全列）" % (len(hs) - len(shown)))
    print("总命中（不含提示）：%d；耗时 %.2f 秒" % (total, time.time() - T0))
    return 1 if total else 0


if __name__ == "__main__":
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except Exception:
        pass
    sys.exit(main())
