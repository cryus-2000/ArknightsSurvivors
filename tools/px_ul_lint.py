# -*- coding: utf-8 -*-
"""pixelfx 放开版注册表检查（docs/242 §14.22）：注册表 data/px_ul.json 里有条目的干员，干员 JSON 里的圆形 / 锥形判定段
没在注册表 shapes 登记（按 px_key，没有再按 src）、也没写 "px_ul": false 的，打印警告——放开版下这些段不画通用刀光弧（vfx.melee_arc），会没有画面。
另查注册表 shapes 里登记了、干员 JSON 里却找不到的 src（多半是拼错）。

用法：python tools/px_ul_lint.py [干员,...]      退出码：0 = 没警告；1 = 有警告
"""
import json, os, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REG = os.path.join(ROOT, "game", "data", "px_ul.json")
CH = os.path.join(ROOT, "game", "data", "characters")
for _s in (sys.stdout, sys.stderr):   # GBK 控制台打印中文 / ✗ 会 UnicodeEncodeError（拉普兰德 11-04）
    if hasattr(_s, "reconfigure"):
        _s.reconfigure(encoding="utf-8", errors="replace")


def shapes(node, out, path=()):
    """圆形 / 锥形判定段；召唤物的攻击（…summons.<kind>.attack）走注册表 summons 接管，不算（组长 11-04：凯尔希 Mon3tr 误报）"""
    if isinstance(node, dict):
        if node.get("shape") in ("circle", "cone") and node.get("src") and not (len(path) >= 3 and path[-1] == "attack" and path[-3] == "summons"):
            out.append(node)
        for k, v in node.items():
            shapes(v, out, path + (k,))
    elif isinstance(node, list):
        for v in node:
            shapes(v, out, path)
    return out


def seg_src():
    """game/scripts/characters/blocks/seg_*.gd 里写死的 src 字面量：\"src\": \"…\" / src = \"…\" / _src(…, \"…\")"""
    out = set()
    import glob, re
    for f in glob.glob(os.path.join(ROOT, "game", "scripts", "characters", "blocks", "seg_*.gd")):
        t = open(f, encoding="utf-8").read()
        out.update(re.findall(r'"src"\s*:\s*"([^"]+)"', t))
        out.update(re.findall(r'\bsrc\b[^=\n]*=\s*"([^"]+)"', t))
        out.update(re.findall(r'(?:melee_hit|area_hit|log_hit|make_hit)\(\s*"([^"]+)"', t))
    return out


SEG_SRC = set()


def main():
    global SEG_SRC
    SEG_SRC = seg_src()
    reg = json.load(open(REG, encoding="utf-8"))
    only = set(filter(None, (sys.argv[1] if len(sys.argv) > 1 else "").split(",")))
    warn = 0
    for op, r in sorted(reg.items()):
        if op.startswith("_") or not isinstance(r, dict) or (only and op not in only):
            continue
        p = os.path.join(CH, op + ".json")
        if not os.path.exists(p):
            continue
        sh = r.get("shapes", {})
        seen, miss = set(), {}
        for b in shapes(json.load(open(p, encoding="utf-8")), []):
            key = str(b.get("px_key", b["src"]))
            seen.add(key)
            if b.get("px_ul", True) is False or key in sh:
                continue
            miss[key] = miss.get(key, 0) + 1
        for k, n in sorted(miss.items()):
            print("警告 %s：判定段「%s」（%d 处）没在注册表 shapes 登记，放开版下没有刀光画面（登记它，或形状块写 \"px_ul\": false，或注册表写 \"arc\": true 恢复通用弧）" % (op, k, n))
            warn += 1
        seen |= SEG_SRC   # seg_*.gd 里写死的 src 字面量（例 seg_hoshiguma 的「热砂沸腾」）也算有（组长 11-04）
        for k in sorted(set(sh) - seen):
            print("警告 %s：注册表 shapes 登记了「%s」，干员 JSON 里没有这个 src / px_key" % (op, k))
            warn += 1
    print("px_ul_lint：%d 条警告" % warn)
    sys.exit(1 if warn else 0)


if __name__ == "__main__":
    main()
