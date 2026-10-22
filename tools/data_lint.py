# -*- coding: utf-8 -*-
"""数据契约检查（docs/126 R2，快检不开 Godot 的一项）：game/data 下那些只有「加载容错」、没有 schema 的数据，查最容易静默出错的几类。

失败（退出码 1）：
  1. 任何 game/data/**/*.json 里同一个对象出现重复的键（JSON.parse 只留最后一个，前面的改了等于白改）。
  2. waves.json 引用了 enemies.json 里没有的敌人 id（threat 的 pool / horde / horde_mix 主体与特种、mid_pool、endings 的 boss）；
     Boss 位（mid_pool、endings.boss）的 id 没在 boss_ai.gd 的 SCRIPTS 登记（没登记的 Boss 不出招）；events 选项给的藏品不在 relics.json。
  3. balance.json 疑似拼错的键：代码里 Bal.v / Bal.vi / BalS.v / MfBal.v("段/键", 缺省) 读的路径 json 里没有，
     而同一段里有一个名字很像、却没有任何代码读到的键（读不到时静默取缺省值，改了 json 等于没改）。
提示（不算失败）：balance.json 里没有在代码里以字面路径出现的叶子键（可能是动态拼的路径，也可能是死键），只报个数，--verbose 列出。

用法：python tools/data_lint.py [--verbose]
"""
import difflib
import glob
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "game", "data")
SCRIPTS = os.path.join(ROOT, "game", "scripts")


def _rel(p):
    try:
        return os.path.relpath(p, ROOT).replace("\\", "/")
    except ValueError:   # 不在同一个盘
        return p


def _load(path, errs):
    """读 json；对象里出现重复键时记错误（object_pairs_hook 能看到全部键值对）"""
    def hook(pairs):
        seen = {}
        for k, v in pairs:
            if k in seen:
                errs.append("%s：重复的键「%s」（只有最后一个生效）" % (_rel(path), k))
            seen[k] = v
        return seen
    with open(path, encoding="utf-8") as f:
        return json.load(f, object_pairs_hook=hook)


def check_dupes(errs):
    n = 0
    for p in sorted(glob.glob(os.path.join(DATA, "**", "*.json"), recursive=True)):
        _load(p, errs)
        n += 1
    return n


def _boss_scripts():
    src = open(os.path.join(SCRIPTS, "boss_ai.gd"), encoding="utf-8").read()
    m = re.search(r"const SCRIPTS := \{(.*?)\n\}", src, re.S)
    return set(re.findall(r'"([a-z_0-9]+)"\s*:', m.group(1))) if m else set()


def check_waves(errs):
    enemies = set(_load(os.path.join(DATA, "enemies.json"), [])["enemies"].keys())
    relics = {str(it.get("id")) for it in _load(os.path.join(DATA, "relics.json"), []).get("items", []) if isinstance(it, dict)}
    w = _load(os.path.join(DATA, "waves.json"), [])
    bosses = _boss_scripts()

    def need(eid, where):
        if eid not in enemies:
            errs.append("waves.json %s：敌人「%s」不在 enemies.json" % (where, eid))

    for i, t in enumerate(w.get("threat", [])):
        for k in ("pool", "horde"):
            for eid in t.get(k, []):
                need(eid, "threat[%d].%s" % (i, k))
        for j, mx in enumerate(t.get("horde_mix", [])):
            for eid in mx.get("body", []):
                need(eid, "threat[%d].horde_mix[%d].body" % (i, j))
            for x in mx.get("extra", []):
                need(x.get("id", ""), "threat[%d].horde_mix[%d].extra" % (i, j))
    boss_ids = [(eid, "mid_pool[%d]" % i) for i, grp in enumerate(w.get("mid_pool", [])) for eid in grp]
    boss_ids += [(e.get("boss", ""), "endings.%s.boss" % k) for k, e in w.get("endings", {}).items() if e.get("boss")]
    for eid, where in boss_ids:
        need(eid, where)
        if bosses and eid not in bosses:
            errs.append("waves.json %s：Boss「%s」没在 boss_ai.gd SCRIPTS 登记（不会出招）" % (where, eid))
    for ev in w.get("events", []):
        for oi, op in enumerate(ev.get("options", [])):
            for x in op.get("ops", []):
                if isinstance(x, dict) and "relic" in x and relics and str(x["relic"]) not in relics:
                    errs.append("waves.json events.%s.options[%d]：藏品「%s」不在 relics.json" % (ev.get("id", "?"), oi, x["relic"]))


BAL_CALL = re.compile(r'\b(?:Bal|BalS|MfBal)\.(?:v|vi)\(\s*"([A-Za-z0-9_]+(?:/[A-Za-z0-9_]+)+)"')
PATH_LIT = re.compile(r'"([A-Za-z0-9_]+(?:/[A-Za-z0-9_]+)+)"')


def _leaves(d, p=""):
    for k, v in d.items():
        if k.startswith("_"):
            continue
        q = p + "/" + k if p else k
        if isinstance(v, dict):
            yield from _leaves(v, q)
        else:
            yield q


def check_balance(errs, verbose):
    bal = _load(os.path.join(DATA, "balance.json"), [])
    leaves = set(_leaves(bal))
    reads, lits = set(), set()
    for p in glob.glob(os.path.join(SCRIPTS, "**", "*.gd"), recursive=True):
        s = open(p, encoding="utf-8").read()
        reads.update(BAL_CALL.findall(s))
        lits.update(PATH_LIT.findall(s))
    for p in glob.glob(os.path.join(ROOT, "tools", "*.py")):
        lits.update(PATH_LIT.findall(open(p, encoding="utf-8").read()))
    unread = sorted(x for x in leaves if x not in lits and x not in reads)
    for r in sorted(reads):
        if r in leaves or "/" not in r:
            continue
        parent, last = r.rsplit("/", 1)
        sib = [x for x in unread if x.rsplit("/", 1)[0] == parent]
        close = difflib.get_close_matches(last, [x.rsplit("/", 1)[1] for x in sib], n=1, cutoff=0.8)
        if close:
            errs.append("balance.json 疑似拼错：代码读「%s」（json 里没有，走缺省值），json 里有「%s/%s」却没有代码读" % (r, parent, close[0]))
    return unread


def main():
    verbose = "--verbose" in sys.argv
    errs = []
    n = check_dupes(errs)
    check_waves(errs)
    unread = check_balance(errs, verbose)
    for e in errs:
        print("FAIL " + e)
    print("DATA LINT: %d 个 json，失败 %d；balance.json 里没有字面读点的叶子键 %d 个（动态拼路径或死键，--verbose 列出）" % (n, len(errs), len(unread)))
    if verbose:
        for x in unread:
            print("  unread " + x)
    return 1 if errs else 0


if __name__ == "__main__":
    sys.exit(main())
