# -*- coding: utf-8 -*-
"""balance 旋钮对账（docs/199）：扫描所有 Bal.v / Bal.vi 的「字面键 + 字面缺省值」读点，和 data/balance.json 对账。
Bal.v 在键存在时一律取 json 值，所以把代码缺省值改成 json 值运行结果不变。
用法：python tools/bal_audit.py            只读，打印统计（明细写 build/bal_audit.json）
      python tools/bal_audit.py --apply    把缺省值改成 json 值（跳过 game.gd / character.gd / pad.gd / hud_squad.gd / combat.kill()：
                                           别的会话正在改，对应读点留给他们合入后再跑）"""
import json, re, sys, os, collections
sys.stdout.reconfigure(encoding="utf-8")
repo = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
apply = "--apply" in sys.argv
data = json.load(open(os.path.join(repo, "game/data/balance.json"), encoding="utf-8"))
ALIASES = r"(?:Bal|BalS|BalW|B|BranchBal|CmdBal|MfBal|VBal)"
# 只认已知是 balance.gd 的别名：先收每个文件里 preload balance 的名字
bal_re = re.compile(r'(?:const|var)\s+(\w+)\s*(?::=|=)\s*preload\("res://scripts/core/balance\.gd"\)')
call_re = None
NUM = r'(-?\d+(?:\.\d+)?(?:e-?\d+)?|-?\.\d+)'
def lookup(path):
    cur = data
    for k in path.split("/"):
        if isinstance(cur, dict) and k in cur:
            cur = cur[k]
        else:
            return None, False
    return cur, True
rows = []   # (file, line, fn, key, default_literal, json_value, found)
uses = collections.defaultdict(list)
for root, _, files in os.walk(os.path.join(repo, "game/scripts")):
    for fn in files:
        if not fn.endswith(".gd"):
            continue
        p = os.path.join(root, fn)
        src = open(p, encoding="utf-8", newline="").read()
        names = set(bal_re.findall(src)) | {"Bal"}
        pat = re.compile(r'\b(' + "|".join(names) + r')\.(v|vi)\(\s*"([A-Za-z0-9_/]+)"\s*,\s*' + NUM + r'\s*\)')
        for m in pat.finditer(src):
            line = src.count("\n", 0, m.start()) + 1
            key = m.group(3)
            lit = m.group(4)
            jv, found = lookup(key)
            uses[key].append((os.path.relpath(p, repo), line, m.group(2), lit, m.start(4), m.end(4)))
            rows.append((os.path.relpath(p, repo), line, m.group(2), key, lit, jv, found))
# 判定
diff = []; missing = []
for f, ln, fnc, key, lit, jv, found in rows:
    if not found:
        missing.append((key, f, ln, lit)); continue
    if isinstance(jv, bool) or not isinstance(jv, (int, float)):
        continue
    litv = float(lit)
    if fnc == "vi":
        same = int(litv) == int(jv)
    else:
        same = abs(litv - float(jv)) < 1e-9
    if not same:
        diff.append((key, f, ln, fnc, lit, jv))
dk = sorted(set(k for k, *_ in diff)); mk = sorted(set(k for k, *_ in missing))
print("读点（字面键 + 字面缺省）", len(rows), "键", len(uses))
print("缺省与 json 不同：键", len(dk), "读点", len(diff))
print("json 里没有：键", len(mk), "读点", len(missing))
# 键内多读点缺省互不一致
inc = [k for k, v in uses.items() if len(set(float(x[3]) for x in v)) > 1]
print("同一键读点缺省互不一致：", len(inc), inc[:10])
out = {"diff": diff, "missing": missing, "uses": {k: [list(x) for x in v] for k, v in uses.items()}}
os.makedirs(os.path.join(repo, "build"), exist_ok=True)
json.dump(out, open(os.path.join(repo, "build", "bal_audit.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
if apply:
    # 把代码缺省值改成 json 值（保留原字面风格：整数键写整数，浮点写浮点）
    byfile = collections.defaultdict(list)
    SKIP_FILES = ("scripts/game.gd", "scripts/characters/character.gd", "scripts/pad.gd", "screens/hud_squad.gd")
    def skipped(f, ln):
        f2 = f.replace("\\", "/")
        if any(f2.endswith(x) for x in SKIP_FILES):
            return True
        return f2.endswith("run/combat.gd") and 1280 <= ln < 1461
    for key, f, ln, fnc, lit, jv in diff:
        if skipped(f, ln):
            continue
        for (uf, uln, ufn, ulit, s, e) in uses[key]:
            if uf == f and uln == ln and ulit == lit:
                byfile[f].append((s, e, fnc, jv))
    n = 0
    for f, items in byfile.items():
        p = os.path.join(repo, f)
        src = open(p, encoding="utf-8", newline="").read()
        for s, e, fnc, jv in sorted(set(items), reverse=True):
            if fnc == "vi":
                rep = str(int(jv))
            else:
                x = float(jv)
                rep = repr(int(x)) + ".0" if x == int(x) and abs(x) < 1e15 else repr(x)
            src = src[:s] + rep + src[e:]
            n += 1
        open(p, "w", encoding="utf-8", newline="").write(src)
    print("改了", n, "处")
