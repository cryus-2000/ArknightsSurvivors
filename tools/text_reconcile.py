# -*- coding: utf-8 -*-
"""说明文字 <-> 数值对账（docs/204 §3，第 3 期）：纯静态、只读 json、不开 Godot、约 0.1 秒。

做法（A 档）：每条玩家可见说明，取出文字里的字面数字，到它自己的参数池里找「能解释它」的值：
  参数池 = 该条目结构化字段里的全部数值（递归）+ value_bal 指向的 balance.json 现值（缺省回落到写在 json 里的默认）；
  解释口径沿用 op_text_check：原值、x100、(v-1)x100、(1-v)x100、1/v（取整到卡面精度）。
找不到解释的数字 = 说明可能没跟上数值（或参数藏在代码里，需要登记/补参数）。
判定：基线 tools/text_reconcile_baseline.json 里的「类别|条目|数字」是已知待核（警告）；基线以外的新增未解释数字 = 失败。
  所以任何人把一张卡 / 藏品 / 节点的数值改了而没改文字（或反之）都会被报出；老账靠清单逐步销（--update-baseline 重写基线）。
用法：python -I tools/text_reconcile.py [--list] [--update-baseline] [--json]
"""
import argparse, glob, json, os, re, sys, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import text_reconcile_scan as SC

DATA = os.path.join(ROOT, "game", "data")
BASELINE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "text_reconcile_baseline.json")
SKIP_NUM_KEYS = {"id", "tex", "icon", "key", "rarity", "new", "version", "order"}
COUNT_UNITS = "名个次层张件枚发段轮人只条种套"


def load(name):
    return json.load(open(os.path.join(DATA, name), encoding="utf-8"))


class Bal:
    def __init__(self):
        self.d = load("balance.json")

    def get(self, path, default=None):
        n = self.d
        for k in path.split("/"):
            if not isinstance(n, dict) or k not in n:
                return default
            n = n[k]
        return n if isinstance(n, (int, float)) and not isinstance(n, bool) else default


def leaves(o, bal, out=None, key=""):
    """递归取数值；[路径, 缺省] 形式的 value_bal 取 balance 现值"""
    out = [] if out is None else out
    if isinstance(o, bool):
        return out
    if isinstance(o, (int, float)):
        if key not in SKIP_NUM_KEYS:
            out.append(float(o))
    elif isinstance(o, dict):
        for k, v in o.items():
            if k in SC.TEXT_KEYS or k.startswith("_") or k in ("src", "source"):
                continue
            if k.endswith("_bal") and isinstance(v, list) and len(v) == 2 and isinstance(v[0], str):
                x = bal.get(v[0], v[1])
                if isinstance(x, (int, float)):
                    out.append(float(x))
                continue
            leaves(v, bal, out, k)
    elif isinstance(o, list):
        for v in o:
            leaves(v, bal, out, key)
    return out


def _cands(x):
    """(换算值, 是否「取整显示」类)：直接换算要求几乎相等（参数改 10% 必须对不上）；倒数 / 除法类按卡面精度四舍五入比"""
    c = [(v, False) for v in (x, x * 100, (x - 1) * 100, (1 - x) * 100, abs(x), abs(x) * 100, x * 60, 1 + x, abs(1 + x) * 100)]
    if abs(x) < 10:
        c.append((x * 1000, False))
    c.append((x / 60, True))
    if x:
        c += [(1 / x, True), (100 / x, True)]
    return c


def explained(n, pool, scale=1.0, near=None, raw=None):
    """n 能被池里某个值（或两个值的和 / 积，如「每层 8%、最多 4 层 = 32%」）经常见换算解释？near 传入列表时，把「差一点」的候选记进去（疑似不符）"""
    exact = 1e-3 + 1e-4 * abs(n)
    rnd = 0.5 * 10 ** -(len(raw.split(".")[1]) if raw and "." in raw else 0) + 1e-6   # 卡面精度的一半
    vals = [v * scale for v in pool] if scale != 1.0 else list(pool)
    vals += list(pool) if scale != 1.0 else []
    for x in vals:
        for c, is_round in _cands(x):
            d = abs(abs(c) - n)
            if d <= (rnd if is_round else exact):
                return True
            if near is not None and n and 0 < d <= 0.2 * n and abs(c) >= 1:
                near.append(c)
    if len(vals) <= 24:
        for i, x in enumerate(vals):
            for y in vals[i:]:
                for c in (x + y, x * y, abs(x) + abs(y)):
                    for d in (c, c * 100):
                        if abs(abs(d) - n) <= exact:
                            return True
    return False


def numbers(text):
    """字面数字（沿用扫描器的误报排除），并去掉「1 名 / 2 次」这类小计数"""
    out = []
    s = SC.strip_false_pos(SC.PH_ANY.sub("<>", text))
    for m in SC.NUM.finditer(s):
        n = float(m.group(0))
        tail = s[m.end():m.end() + 2].lstrip()
        if n <= 3 and n == int(n) and tail[:1] and tail[0] in COUNT_UNITS:
            continue
        out.append((m.group(0), n))
    return out


def adapters(bal):
    """逐类产出 (类别, 条目标识, 文件:键路径, 文本, 参数池, 缩放)"""
    fx = load("relic_effects.json")["relics"]
    for rid, r in fx.items():
        pool = leaves(r.get("effects", []), bal) + leaves({k: v for k, v in r.items() if k in ("max_lv", "cd", "chance")}, bal)
        yield "藏品卡面", "relic#" + rid, "relic_effects.json:relics.%s.desc" % rid, r.get("desc", ""), pool, 1.0
    cards = load("cards.json")
    for pid, c in cards["passives"].items():
        yield "升级卡", "passive#" + pid, "cards.json:passives.%s.desc" % pid, c.get("desc", ""), leaves({k: v for k, v in c.items() if k != "max"}, bal), 1.0
    for c in cards["fillers"]:
        yield "升级卡", "filler#" + c["id"], "cards.json:fillers.%s.desc" % c["id"], c.get("desc", ""), leaves(c, bal), 1.0
    mt = load("meta_tree.json")
    sc = bal.get("meta/stat_scale", 1.0)
    for nid, n in mt["nodes"].items():
        yield "局外认知塑造", "meta#" + nid, "meta_tree.json:nodes.%s.desc" % nid, n.get("desc", ""), leaves(n.get("effects", []), bal) + leaves({"cost": n.get("cost", 0), "need": n.get("need", 0)}, bal), sc
    evd = load("events_v2.json")
    ev_cfg = leaves({k: v for k, v in evd.items() if k != "events"}, bal)   # 顶层的全局参数（away_t 等）
    for e in evd["events"]:
        for i, o in enumerate(e.get("options", [])):
            yield "事件选项", "event#%s.%d" % (e["id"], i), "events_v2.json:%s.options[%d].desc" % (e["id"], i), o.get("desc", ""), leaves(o.get("ops", []), bal) + leaves(e.get("req", {}), bal) + ev_cfg, 1.0
    md = load("medals.json")["medals"]
    for m in md:
        yield "蚀刻章", "medal#%s" % m["key"], "medals.json:%s.desc" % m["key"], m.get("desc", ""), leaves(m, bal) + [float(len(md) - 1)], 1.0
    for eid, e in load("enemies.json")["enemies"].items():
        yield "敌人说明", "enemy#" + eid, "enemies.json:%s.desc" % eid, e.get("desc", ""), leaves(e, bal), 1.0
    pool_bal = leaves(bal.d, bal)
    for pi, pg in enumerate(load("guide.json").get("pages", [])):
        for key in ("lines", "more"):
            for li, t in enumerate(pg.get(key, [])):
                if isinstance(t, str):
                    yield "开局指南", "guide#%d.%s%d" % (pi, key, li), "guide.json:pages[%d].%s[%d]" % (pi, key, li), t, pool_bal, 1.0
    for f in sorted(glob.glob(os.path.join(DATA, "characters", "*.json"))):
        d = json.load(open(f, encoding="utf-8"))
        pool = leaves({k: v for k, v in d.items() if k != "gallery"}, bal)
        oid = os.path.basename(f)[:-5]
        for sect in ("response", "leader"):
            if isinstance(d.get(sect), dict) and isinstance(d[sect].get("desc"), str):
                yield "干员响应/队长说明", "op#%s.%s" % (oid, sect), "characters/%s.json:%s.desc" % (oid, sect), d[sect]["desc"], pool, 1.0


def run():
    bal = Bal()
    res, per = [], {}
    for cat, ident, where, text, pool, scale in adapters(bal):
        c = per.setdefault(cat, {"texts": 0, "with_num": 0, "nums": 0, "ok": 0})
        c["texts"] += 1
        nums = numbers(text)
        if nums:
            c["with_num"] += 1
        for raw, n in nums:
            c["nums"] += 1
            near = []
            if explained(n, pool, scale, near, raw):
                c["ok"] += 1
            else:
                res.append({"cat": cat, "id": ident, "where": where, "num": raw, "text": text[:60], "near": sorted(set(round(x, 2) for x in near))[:3]})
    return res, per


def inject_rate(trials=None):
    """回归注入自测：对每条「文字数字全能解释」的条目，把参数池里每个值改 10%，看这条文字会不会被报出。
    返回 (被报出的条目数, 参与测试的条目数)——比例就是这套对账对「改了数值没改文字」的检出率"""
    bal = Bal()
    hit = tot = 0
    by = {}
    for cat, ident, where, text, pool, scale in adapters(bal):
        nums = numbers(text)
        if not nums or not pool or len(pool) > 24 or not all(explained(n, pool, scale, raw=r) for r, n in nums):
            continue
        for v in sorted(set(abs(x) for x in pool)):
            if v == 0:
                continue
            p2 = [x * 1.1 if abs(x) == abs(v) else x for x in pool]   # 同值的参数一起改（两个效果都写 4% 时只改一个，另一个仍能解释文字，不算漏报）
            used = any(explained(n, [v], scale, raw=r) for r, n in nums)   # 这个值确实解释了某个数字才算
            if not used:
                continue
            tot += 1
            by.setdefault(cat, [0, 0])[1] += 1
            if not all(explained(n, p2, scale, raw=r) for r, n in nums):
                hit += 1
                by[cat][0] += 1
    inject_rate.by = by
    return hit, tot


def keyof(r):
    return "%s|%s|%s" % (r["cat"], r["id"], r["num"])


def check():
    """给 check.py 用：返回 (errors, detail, 未解释列表, 分类统计)"""
    res, per = run()
    try:
        base = set(json.load(open(BASELINE, encoding="utf-8")).get("known", []))
    except OSError:
        base = set()
    new = [r for r in res if keyof(r) not in base]
    gone = base - {keyof(r) for r in res}
    tot = sum(c["nums"] for c in per.values())
    ok = sum(c["ok"] for c in per.values())
    errs = ["%s：%s 的说明里「%s」解释不了（%s…）——文字没跟上数值，或参数藏在代码里；确认后改文字，或 --update-baseline 登记" % (r["cat"], r["where"], r["num"], r["text"][:24]) for r in new]
    detail = "%d 类、%d 个数字，已解释 %d（%.0f%%）；待核基线 %d 条%s" % (len(per), tot, ok, 100.0 * ok / max(1, tot), len(res) - len(new), "；基线里 %d 条已解释可删" % len(gone) if gone else "")
    return errs, detail, res, per


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--list", action="store_true", help="列出全部未解释数字")
    ap.add_argument("--update-baseline", action="store_true")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--inject", action="store_true", help="回归注入自测：参数改 10% 的检出率")
    a = ap.parse_args()
    if a.inject:
        h, t = inject_rate()
        print("回归注入：参数改 10%% 后文字被报出 %d / %d（%.0f%%）" % (h, t, 100.0 * h / max(1, t)))
        for k, (x, y) in inject_rate.by.items():
            print("    %-10s %d / %d（%.0f%%）" % (k, x, y, 100.0 * x / max(1, y)))
        print("    漏报多为「同一数字被池里另一个值碰巧解释」（如护甲 +1 与最大层数 1），不是真漏")
        # 点名用例：改一张卡 / 一件藏品 / 一个局外节点的 value 10%，对应文字必须被报出
        bal = Bal()
        want = {"passive#hp", "passive#dodge", "passive#squad_atk", "relic#2", "relic#3", "meta#atk1", "filler#atk"}
        got = set()
        for cat, ident, where, text, pool, scale in adapters(bal):
            if ident in want:
                nums = numbers(text)
                if all(explained(n, pool, scale, raw=r) for r, n in nums) and not all(explained(n, [x * 1.1 for x in pool], scale, raw=r) for r, n in nums):
                    got.add(ident)
        print("    点名用例检出 %d / %d%s" % (len(got), len(want), "" if got == want else "，漏：" + "、".join(sorted(want - got))))
        focus = [inject_rate.by.get(k, [0, 0]) for k in ("藏品卡面", "升级卡", "局外认知塑造")]
        rate = sum(x for x, _ in focus) / max(1, sum(y for _, y in focus))
        print("    三大类（藏品 / 升级卡 / 局外）合计检出率 %.0f%%（门槛 70%%）" % (100 * rate))
        return 0 if got == want and rate >= 0.7 else 1
    t0 = time.time()
    errs, detail, res, per = check()
    if a.update_baseline:
        json.dump({"_doc": "tools/text_reconcile.py 的已知待核清单（类别|条目|数字）：文字里的数字当前解释不了。逐条核实后改文字 / 补参数，再 --update-baseline 删掉。", "known": sorted(keyof(r) for r in res)},
                  open(BASELINE, "w", encoding="utf-8", newline="\n"), ensure_ascii=False, indent=0)
        print("基线已重写：%d 条" % len(res))
        return 0
    if a.json:
        print(json.dumps({"per": per, "unexplained": res}, ensure_ascii=False, indent=1))
        return 0
    print("%-14s %6s %8s %6s %6s" % ("类别", "条数", "含数字条", "数字", "已解释"))
    for k, c in per.items():
        print("%-14s %6d %8d %6d %6d" % (k, c["texts"], c["with_num"], c["nums"], c["ok"]))
    print(detail)
    if a.list:
        for r in res:
            print("  %s  %s  「%s」 %s%s" % (r["cat"], r["where"], r["num"], r["text"], "   <-- 疑似不符，参数里有接近的值 %s" % r["near"] if r["near"] else ""))
    for e in errs:
        print("FAIL " + e)
    print("耗时 %.2f 秒；新增未解释 %d 条" % (time.time() - t0, len(errs)))
    return 1 if errs else 0


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    sys.exit(main())
