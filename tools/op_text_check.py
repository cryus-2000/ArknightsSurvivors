"""干员文字与数值对照检查（不开 Godot，快检 check.py 的一项）。

玩家可见的干员文字（普攻 / 技能 / 天赋 / 成长节点 / 精英化「普攻」卡 / 图鉴简介 / 积木 banner）可以写数值占位
「{表达式}」，加载时按 base 填数（game/scripts/characters/character.gd fill_text，docs/61 §1.4）。本工具：

1. 占位求值：每个占位都必须求得出值（引用的键在 base 里且是数字、表达式能解析）——求不出算失败。
2. 字面数字：文字里没写成占位的「N%」「N 秒」「×N」「半径 N」「每第 N 次」，到这名干员的 base 与 blocks 里找能对上的数
   （原值、×100、(值−1)×100、(1−值)×100）。哪个都对不上、又不在 ALLOW 里的算失败（多半是改了数值文字没跟上）；
   对得上的列进「需人工看」清单（能对上不等于说的是同一个数，--report 打印，方便以后改成占位）。

用法：
    python tools/op_text_check.py               # 检查，失败时退出码 1
    python tools/op_text_check.py --report      # 另外打印每条字面数字对上的键（需人工看清单）
    python tools/op_text_check.py --dump OP     # 打印某名干员填好占位后的全部文字
"""
import argparse
import glob
import json
import math
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CHAR_DIR = os.path.join(ROOT, "game", "data", "characters")

TEXT_FILL_KEYS = ("desc", "banner")
PH = re.compile(r"\{([^{}]*)\}")

# 字面数字里允许、base / blocks 里对不上的（引擎通用规则或写死在代码里的数）：(干员 id 或 "*", 文字片段)。
# 片段是该条文字里包含这个数字的一小段原文；改文字时一起改
ALLOW = [
    ("*", "受到的伤害 +10%"),          # 易伤 aura_weak：combat.gd 固定 ×1.1（艾雅法拉「点燃」、塞雷娅「钙质化」、铃兰天赋 / 「狐火渺然」）
    ("lumen", "受到的伤害 +25%"),      # 照亮：combat.gd 固定 ×1.25（与灯火照亮范围同一条）
    ("wisadel", "0.25 秒后爆炸"),      # 残影引爆延迟：积木执行器里写死
    ("suzuran", "移速 -35%"),          # 光域减速：enemies.gd 固定 ×0.65（e.slow）
]


# ------------------------------------------------------------------ 占位求值（与 character.gd text_eval / text_fmt 同规则）

def _tokens(expr):
    s = expr.replace(" ", "")
    out, i = [], 0
    while i < len(s):
        c = s[i]
        if c in "+-*/()":
            out.append(c)
            i += 1
        elif c == "$" or c.isdigit() or c == ".":
            j = i + 1
            while j < len(s) and s[j] not in "+-*/()":
                j += 1
            out.append(s[i:j])
            i = j
        else:
            raise ValueError("看不懂的字符「%s」" % c)
    return out


def text_eval(expr, base):
    toks = _tokens(expr)
    pos = [0]

    def peek():
        return toks[pos[0]] if pos[0] < len(toks) else None

    def atom():
        t = peek()
        if t is None:
            raise ValueError("表达式不完整")
        pos[0] += 1
        if t == "-":
            return -atom()
        if t == "(":
            v = total()
            if peek() != ")":
                raise ValueError("缺「)」")
            pos[0] += 1
            return v
        if t.startswith("$"):
            k = t[1:]
            v = base.get(k)
            if isinstance(v, bool) or not isinstance(v, (int, float)):
                raise ValueError("base 里没有数字「%s」" % k)
            return float(v)
        try:
            return float(t)
        except ValueError:
            raise ValueError("看不懂的「%s」" % t)

    def prod():
        v = atom()
        while peek() in ("*", "/"):
            op = toks[pos[0]]
            pos[0] += 1
            r = atom()
            if op == "*":
                v *= r
            elif r == 0:
                raise ValueError("除以 0")
            else:
                v /= r
        return v

    def total():
        v = prod()
        while peek() in ("+", "-"):
            op = toks[pos[0]]
            pos[0] += 1
            r = prod()
            v = v + r if op == "+" else v - r
        return v

    v = total()
    if pos[0] != len(toks):
        raise ValueError("多余的「%s」" % toks[pos[0]])
    return v


def text_fmt(v, nd=3):
    k = 10.0 ** nd
    r = math.floor(v * k + 0.5) / k   # 同 character.gd text_fmt：最多 nd 位小数（缺省 3），四舍五入（.5 进位）
    if abs(r - round(r)) < 0.0001:
        return str(int(round(r)))
    return ("%.*f" % (nd, r)).rstrip("0").rstrip(".")


def fill_line(s, base, errs=None, where=""):
    def rep(m):
        expr = m.group(1)
        if "$" not in expr:
            return m.group(0)
        nd = 3
        head, _, tail = expr.rpartition(":")
        if head and tail.lstrip("-").isdigit():   # {表达式:N}：四舍五入到 N 位小数
            nd = max(0, min(3, int(tail)))
            expr = head
        try:
            return text_fmt(text_eval(expr, base), nd)
        except ValueError as e:
            if errs is not None:
                errs.append("%s：占位「{%s}」求值失败：%s" % (where, expr, e))
            return m.group(0)
    return PH.sub(rep, s)


# ------------------------------------------------------------------ 取文字

def iter_texts(d):
    """(位置, 类别, 原文)；类别：attack / skill / talent / custom / elite / stat / elite_attack / choice / gallery / banner"""
    if isinstance(d.get("attack"), dict) and d["attack"].get("desc"):
        yield "attack.desc", "attack", d["attack"]["desc"]
    for i, sk in enumerate(d.get("skills", []) or []):
        if isinstance(sk, dict) and sk.get("desc"):
            yield "skills[%d]「%s」" % (i, sk.get("name", "")), "skill", sk["desc"]
    if isinstance(d.get("talent"), dict) and d["talent"].get("desc"):
        yield "talent「%s」" % d["talent"].get("name", ""), "talent", d["talent"]["desc"]
    for i, n in enumerate(d.get("progression", []) or []):
        if not isinstance(n, dict):
            continue
        t = n.get("type", "")
        nm = n.get("name", "")
        if n.get("desc"):
            yield "progression[%d]「%s」" % (i, nm), t, n["desc"]
        if isinstance(n.get("attack"), dict) and n["attack"].get("desc"):
            yield "progression[%d]「%s」.attack「%s」" % (i, nm, n["attack"].get("name", "")), "elite_attack", n["attack"]["desc"]
        ch = n.get("choices")
        if isinstance(ch, dict):
            for k, c in ch.items():
                if isinstance(c, dict) and c.get("desc"):
                    yield "progression[%d]「%s」.choices.%s" % (i, nm, k), "choice", c["desc"]
    gd = d.get("gallery", {}) or {}
    if gd.get("desc"):
        yield "gallery.desc", "gallery", gd["desc"]

    def walk(n, path):
        if isinstance(n, dict):
            for k, v in n.items():
                if k == "banner" and isinstance(v, str):
                    yield path + "." + k, "banner", v
                elif isinstance(v, (dict, list)):
                    yield from walk(v, path + "." + k)
        elif isinstance(n, list):
            for i, v in enumerate(n):
                yield from walk(v, "%s[%d]" % (path, i))
    yield from walk(d.get("blocks", {}), "blocks")


# ------------------------------------------------------------------ 字面数字

NUM = r"(\d+(?:\.\d+)?)"
LIT_PATTERNS = [
    ("pct", re.compile(NUM + r"\s*%")),
    ("sec", re.compile(NUM + r"\s*秒")),
    ("mult", re.compile(r"[×x]\s*" + NUM)),
    ("dist", re.compile(r"(?:半径|射程|距离|范围|长度|宽)\s*" + NUM)),
    ("nth", re.compile(r"每第\s*" + NUM + r"\s*次")),
]


def _block_numbers(n, base, out):
    if isinstance(n, dict):
        for k, v in n.items():
            if k.startswith("_"):
                continue
            _block_numbers(v, base, out)
    elif isinstance(n, list):
        for v in n:
            _block_numbers(v, base, out)
    elif isinstance(n, bool):
        return
    elif isinstance(n, (int, float)):
        out.add(float(n))
    elif isinstance(n, str) and "$" in n:
        try:
            out.add(text_eval(n, base))
        except ValueError:
            pass


def candidates(d):
    """{数值: 来源说明}：base 的数字、blocks 里的字面数与 $ 表达式结果、技能 dur / sp，各按原值、×100、(值−1)×100、(1−值)×100、1/值"""
    base = d.get("base", {}) or {}
    raw = {}
    for k, v in base.items():
        if isinstance(v, bool) or not isinstance(v, (int, float)):
            continue
        raw.setdefault(float(v), []).append("$" + k)
    bn = set()
    _block_numbers(d.get("blocks", {}), base, bn)
    for sk in d.get("skills", []) or []:
        if isinstance(sk, dict):
            for k in ("dur", "sp"):
                if isinstance(sk.get(k), (int, float)):
                    bn.add(float(sk[k]))
    for v in bn:
        raw.setdefault(v, []).append("blocks")
    out = {}
    for v, srcs in raw.items():
        src = srcs[0] if srcs[0] != "blocks" or len(srcs) == 1 else srcs[0]
        forms = [(v, src), (v * 100, src + "×100"), ((v - 1) * 100, "(" + src + "−1)×100"), ((1 - v) * 100, "(1−" + src + ")×100")]
        if v not in (0.0,):
            forms.append((1.0 / v, "1/" + src))
        for val, why in forms:
            key = round(val, 2)
            out.setdefault(key, why)
    return out


def literal_numbers(text):
    """去掉占位后的字面数字：[(类别, 数字串, 片段)]"""
    s = PH.sub(lambda m: "⟨⟩" if "$" in m.group(1) else m.group(0), text)
    found = []
    seen = set()
    for kind, pat in LIT_PATTERNS:
        for m in pat.finditer(s):
            if (m.start(1), m.group(1)) in seen:
                continue
            seen.add((m.start(1), m.group(1)))
            a = max(0, m.start() - 8)
            found.append((kind, m.group(1), s[a:m.end() + 4]))
    return found


def _allowed(cid, raw_text, num):
    """ALLOW 里有本干员（或 *）的片段出现在这条文字里，且片段里含这个数字"""
    for who, piece in ALLOW:
        if who in (cid, "*") and piece in raw_text and re.search(r"(?<![\d.])" + re.escape(num) + r"(?![\d.])", piece):
            return True
    return False


def check_op(path):
    d = json.load(open(path, encoding="utf-8"))
    cid = d.get("id", os.path.splitext(os.path.basename(path))[0])
    base = d.get("base", {}) or {}
    errs, manual = [], []
    cand = candidates(d)
    for where, kind, text in iter_texts(d):
        fill_line(text, base, errs, "%s %s" % (cid, where))
        for lk, num, frag in literal_numbers(text):
            v = round(float(num), 2)
            if _allowed(cid, text, num):
                continue
            if v in cand:
                manual.append("%s %s：「%s」对上 %s" % (cid, where, frag.strip(), cand[v]))
            elif v in (0.0, 1.0, 100.0) and lk != "sec":
                continue
            else:
                errs.append("%s %s：字面数字「%s」（%s）在 base / blocks 里找不到对应的数（改成占位，或核对后加进 op_text_check.ALLOW）"
                            % (cid, where, frag.strip(), num))
    return cid, errs, manual


def run():
    errs, manual, ids = [], [], []
    for p in sorted(glob.glob(os.path.join(CHAR_DIR, "*.json"))):
        cid, e, m = check_op(p)
        ids.append(cid)
        errs += e
        manual += m
    return ids, errs, manual


def check():
    """给 check.py：返回 (错误列表, 一行说明)"""
    ids, errs, manual = run()
    detail = "%d 名干员：占位 / 字面数字不一致 %d 条，字面数字对得上 base / blocks（需人工看）%d 条（明细 python tools/op_text_check.py --report）" % (len(ids), len(errs), len(manual))
    return errs, detail


def dump(cid):
    d = json.load(open(os.path.join(CHAR_DIR, cid + ".json"), encoding="utf-8"))
    base = d.get("base", {}) or {}
    for where, kind, text in iter_texts(d):
        print("[%s] %s\n    %s" % (kind, where, fill_line(text, base)))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--report", action="store_true", help="打印字面数字对上的键（需人工看清单）")
    ap.add_argument("--dump", metavar="OP", help="打印某名干员填好占位后的全部文字")
    a = ap.parse_args()
    if a.dump:
        dump(a.dump)
        return 0
    ids, errs, manual = run()
    for e in errs:
        print("失败  " + e)
    if a.report:
        for m in manual:
            print("人工  " + m)
    print("%d 名干员：失败 %d 条，需人工看 %d 条" % (len(ids), len(errs), len(manual)))
    return 1 if errs else 0


if __name__ == "__main__":
    for _s in (sys.stdout, sys.stderr):
        try:
            _s.reconfigure(encoding="utf-8", errors="replace")
        except (AttributeError, ValueError):
            pass
    sys.exit(main())
