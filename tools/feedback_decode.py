# -*- coding: utf-8 -*-
"""反馈码解码（docs/311）：玩家从结算 / 标题页设置「反馈」复制的短码 → 版本、提交号、本局摘要。
位表与 game/scripts/core/feedback.gd 同一份（OPS / CAUSES 只许往后追加）。
用法：python tools/feedback_decode.py AS-XXXX-XXXX-...   [更多码]   （大小写、横线、O/I/L 误写都能认）
      python tools/feedback_decode.py --json AS-...         输出 JSON
校验字不对返回 1（多半是抄错了）。
"""
import json, sys

ALPHA = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
OPS = ["", "angelina", "exusiai", "eyjafjalla", "gladiia", "hoshiguma", "irene", "kaltsit", "lappland", "logos", "lumen",
       "mizuki", "saria", "siege", "skadi", "skalter", "specter_unchained", "suzuran", "texas", "ulpianus", "wisadel"]


def _op_names():
    """干员中文名：读仓库里的 game/data/characters/*.json（读不到就显示 id）"""
    import glob, os
    root = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
    out = {}
    for f in glob.glob(os.path.join(root, "game", "data", "characters", "*.json")):
        try:
            out[os.path.basename(f)[:-5]] = json.load(open(f, encoding="utf-8")).get("name", "")
        except Exception:
            pass
    return out


OP_CN = _op_names()
CAUSES = ["", "enemy", "elite", "boss", "rare", "env:zone", "env:mire", "env:dark", "env:relic", "env:bullet",
          "env:corrode", "env:wound", "env:nerve", "other"]
CAUSE_CN = {"": "—", "enemy": "普通敌人", "elite": "精英敌人", "boss": "Boss", "rare": "稀有敌人", "env:zone": "黑潮（安全区外）",
            "env:mire": "溟痕", "env:dark": "寂灭", "env:relic": "藏品代价", "env:bullet": "敌方弹幕", "env:corrode": "侵蚀",
            "env:wound": "侵蚀创口", "env:nerve": "神经损伤", "other": "其他"}
RESULT_CN = ["倒下", "胜利", "中途退出", "其他"]
TIER_CN = {0: "常规", 5: "高压", 10: "深潮"}


def _check(vals):
    c = 7
    for i, v in enumerate(vals):
        c = (c * 33 + v * (i + 3)) % 1021
    return c % 32


def _norm(code):
    s = code.strip().upper().replace("-", "").replace(" ", "")
    if s.startswith("AS"):
        s = s[2:]
    return s.replace("O", "0").replace("I", "1").replace("L", "1").replace("U", "V")


def decode(code):
    s = _norm(code)
    vals = []
    for ch in s:
        if ch not in ALPHA:
            raise ValueError("含非法字符：%s" % ch)
        vals.append(ALPHA.index(ch))
    if len(vals) < 2:
        raise ValueError("太短")
    body, chk = vals[:-1], vals[-1]
    if _check(body) != chk:
        raise ValueError("校验不对（多半抄错了一位）")
    bits = []
    for v in body:
        bits.extend((v >> i) & 1 for i in range(4, -1, -1))
    pos = [0]

    def take(n):
        if pos[0] + n > len(bits):
            raise ValueError("码不完整")
        v = 0
        for b in bits[pos[0]:pos[0] + n]:
            v = v * 2 + b
        pos[0] += n
        return v

    fmt = take(3)
    if fmt != 1:
        raise ValueError("不认识的格式版本 %d（解码脚本要更新）" % fmt)
    kind = take(1)
    out = {"version": "%d.%d" % (take(4), take(7))}
    patch = take(6)
    if patch:
        out["version"] += ".%d" % patch
    out["commit"] = ("%07x" % take(28)) if take(1) else "dev"
    if kind == 0:
        out["run"] = None
        return out
    lead = take(6)
    n = take(3)
    mates = [take(6) for _ in range(n)]

    def op(i):
        return OPS[i] if 0 < i < len(OPS) else ("表外干员" if i else "")
    run = {"leader": op(lead), "squad": [op(i) for i in mates], "tier": take(5)}
    run["result"] = RESULT_CN[take(2)]
    run["trial"] = bool(take(1))
    run["death_t"] = take(12)
    run["wall_s"] = take(13)
    ci = take(4)
    run["cause"] = CAUSES[ci] if ci < len(CAUSES) else "unknown"
    out["run"] = run
    return out


def mmss(s):
    return "%d:%02d" % (s // 60, s % 60)


def pretty(code, d):
    lines = ["反馈码 %s" % code, "  版本 %s · 提交 %s" % (d["version"], d["commit"])]
    r = d["run"]
    if r is None:
        lines.append("  （标题页入口：只有版本）")
        return "\n".join(lines)
    nm = lambda x: OP_CN.get(x, x)
    lines.append("  队长 %s · 小队 %s" % (nm(r["leader"]), "、".join(nm(x) for x in r["squad"]) or "—"))
    lines.append("  难度 %s（潮位 %d）· 结果 %s%s" % (TIER_CN.get(r["tier"], "潮位 %d" % r["tier"]), r["tier"], r["result"], " · Boss 演练" if r["trial"] else ""))
    if r["death_t"]:
        lines.append("  倒下 %s · 原因 %s" % (mmss(r["death_t"]), CAUSE_CN.get(r["cause"], r["cause"])))
    lines.append("  局时 %s（真实时间，含暂停与选卡）" % mmss(r["wall_s"]))
    return "\n".join(lines)


def main(argv):
    as_json = "--json" in argv
    codes = [a for a in argv if not a.startswith("--")]
    if not codes:
        print(__doc__)
        return 2
    rc = 0
    res = []
    for c in codes:
        try:
            d = decode(c)
            res.append({"code": c, **d})
            if not as_json:
                print(pretty(c, d))
        except ValueError as e:
            rc = 1
            res.append({"code": c, "error": str(e)})
            if not as_json:
                print("反馈码 %s：%s" % (c, e))
    if as_json:
        print(json.dumps(res, ensure_ascii=False, indent=1))
    return rc


if __name__ == "__main__":
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    sys.exit(main(sys.argv[1:]))
