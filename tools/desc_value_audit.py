"""说明数字 ↔ 数据参数一致性核对（docs/335 §2）。

逐件读 relic_effects.json（藏品）与 characters/*.json（成长节点 / 技能 / 精英化），把说明文字里的每个数字
和该条目数据里的数值叶子比对：
  - desc 里出现、但数据里找不到对应值（按原值 / ×100 / 秒↔帧 / 倒数等常见换算）的数字 → 「说明多出的数」
  - 数据里的数值叶子在说明里一个对应都没有 → 只记数（很多参数是内部的，如半径、帧数，不写进卡面是正常的）

只报「说明多出的数」为疑点；已人工核过、确属合理的写进 ALLOW（id → 数字集合），这样以后改数据忘了改说明会被抓到。
用法：python tools/desc_value_audit.py [--all] [--json out.json]
退出码：疑点数 > 0 时为 1（check.py 项 desc_values）。
"""
import json
import math
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GAME = ROOT / "game"
NUM = re.compile(r"(?<![A-Za-z0-9_.])(\d+(?:\.\d+)?)")

# 人工核过的「说明里的数不直接来自本条数据」：来源写在注释里
ALLOW: dict[str, set] = {}
ALLOW_FILE = ROOT / "tools" / "desc_value_allow.json"
if ALLOW_FILE.exists():
    for k, v in json.loads(ALLOW_FILE.read_text(encoding="utf-8")).items():
        if not k.startswith("_"):
            ALLOW[k] = {float(x) for x in v.get("nums", [])}


def leaves(v, out):
    if isinstance(v, bool):
        return
    if isinstance(v, (int, float)):
        out.append(float(v))
    elif isinstance(v, dict):
        for k, x in v.items():
            if k in ("rarity", "price_class", "new", "pool", "trim", "lane", "set"):
                continue
            leaves(x, out)
    elif isinstance(v, list):
        for x in v:
            leaves(x, out)


def forms(x: float) -> set:
    """一个数据值在说明里可能写成的样子。"""
    s = {x, x * 100, abs(x), abs(x) * 100, (1 - x) * 100, (x - 1) * 100, abs(1 - x) * 100, x / 60, x * 60, x * 2, x / 2}
    if x != 0:
        s |= {1 / x, 100 / x}
    return {round(v, 4) for v in s if math.isfinite(v)}


def match(n: float, cand: set) -> bool:
    for c in cand:
        if abs(c - n) < 1e-6 or (n != 0 and abs(c - n) / abs(n) < 0.006):
            return True
        # 说明四舍五入到整数 / 一位小数
        if abs(round(c) - n) < 1e-6 and abs(c - n) < 0.5 and n >= 10:
            return True
        if abs(round(c, 1) - n) < 1e-6:
            return True
    return False


def strip_text(t: str) -> str:
    # 数量词里自带的数字不算参数：「第 1 层」等仍算；去掉罗马数字以外的编号类如「#129」「S3」
    t = re.sub(r"\{[^}]*\}", "", t)   # 运行时代入的占位（每分钟成长、10:00 估值）由 relic_fx 算，不在这里核
    t = re.sub(r"\d+:\d\d", "", t)    # 时刻「10:00」
    t = re.sub(r"docs/\d+", "", t)
    t = re.sub(r"#\d+", "", t)
    t = re.sub(r"[SE]\d", "", t)
    t = re.sub(r"精[英]?[一二零]", "", t)
    return t


def audit_relics(rows):
    data = json.loads((GAME / "data" / "relic_effects.json").read_text(encoding="utf-8"))["relics"]
    for rid, r in data.items():
        texts = [r.get("desc", "")]
        ds = r.get("desc_squad", {})
        for part in ("head", "tail", "none"):
            if isinstance(ds.get(part), str):
                texts.append(ds[part])
        for part in ("ops", "dmg_ops"):
            for x in (ds.get(part) or {}).values():
                texts.append(str(x))
        vals = []
        leaves(r.get("effects", []), vals)
        leaves(r.get("args", {}), vals)
        rows.append(("relic", rid, " / ".join(t for t in texts if t), vals))


def audit_chars(rows):
    for p in sorted((GAME / "data" / "characters").glob("*.json")):
        d = json.loads(p.read_text(encoding="utf-8"))
        cid = p.stem

        def walk(v, path):
            if isinstance(v, dict):
                if isinstance(v.get("desc"), str) and v["desc"]:
                    vals = []
                    leaves({k: x for k, x in v.items() if k not in ("desc", "brief", "name")}, vals)
                    rows.append(("char", "%s:%s" % (cid, path + "/" + str(v.get("id", v.get("name", "")))), v["desc"], vals))
                for k, x in v.items():
                    if isinstance(x, (dict, list)):
                        walk(x, path + "/" + k)
            elif isinstance(v, list):
                for i, x in enumerate(v):
                    walk(x, path + "/%d" % i)

        walk(d, "")


def main():
    rows = []
    audit_relics(rows)
    if "--all" in sys.argv:
        audit_chars(rows)
    sus = []
    for kind, rid, text, vals in rows:
        cand = set()
        for v in vals:
            cand |= forms(v)
        # 数据值的和 / 差（「+3%，满血 +30%」「每层 2%，最多 5 层 = 10%」）
        for a in vals:
            for b in vals:
                cand |= {round(a * b * 100, 4), round(a * b, 4), round(a + b, 4), round(abs(a + b) * 100, 4)}
        nums = [float(m) for m in NUM.findall(strip_text(text))]
        allow = ALLOW.get(rid, set())
        extra = [n for n in nums if not match(n, cand) and n not in allow and n not in (0.0, 1.0)]
        if extra:
            sus.append({"kind": kind, "id": rid, "extra": extra, "desc": text, "vals": vals})
    for s in sus:
        print("%s %s  说明多出 %s\n    说明：%s\n    数据：%s" % (s["kind"], s["id"], s["extra"], s["desc"], s["vals"]))
    print("DESC VALUES rows=%d suspects=%d" % (len(rows), len(sus)))
    if "--json" in sys.argv:
        Path(sys.argv[sys.argv.index("--json") + 1]).write_text(json.dumps(sus, ensure_ascii=False, indent=1), encoding="utf-8")
    return 1 if sus else 0


if __name__ == "__main__":
    sys.exit(main())
