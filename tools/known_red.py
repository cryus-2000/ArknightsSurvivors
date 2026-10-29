# -*- coding: utf-8 -*-
"""已知红登记（docs/204 §5.4）：tools/known_red.json 里每条 = 一个有人认领、有到期日的失败。

字段：scope（检查项名里含这段文字即命中）、pattern（可选：只放行含该文字的单条错误，用 | 分隔多个；用于 graph_lint 这类一项里多条错误）、
      since、owner、reason、due（YYYY-MM-DD）。owner / reason / due 缺一不可，due 距 since 不得超过 14 天。
行为：未过期 → 放行并单列「已知红」；过期仍红 → 硬失败；登记项实际已绿 → 提示可删除。
"""
import datetime
import json
import os

PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "known_red.json")
MAX_DAYS = 14


def _d(s):
    return datetime.date.fromisoformat(str(s))


def load(today=None):
    """返回 (条目列表, 加载错误列表)"""
    today = today or datetime.date.today()
    errs, items = [], []
    try:
        raw = json.load(open(PATH, encoding="utf-8")).get("items", [])
    except OSError:
        return [], []
    except json.JSONDecodeError as e:
        return [], ["known_red.json 解析失败：%s" % e]
    for i, it in enumerate(raw):
        miss = [k for k in ("scope", "owner", "reason", "since", "due") if not it.get(k)]
        if miss:
            errs.append("known_red.json 第 %d 条缺字段 %s（不允许无人认领 / 无到期日）" % (i + 1, "/".join(miss)))
            continue
        try:
            since, due = _d(it["since"]), _d(it["due"])
        except ValueError:
            errs.append("known_red.json 第 %d 条日期格式要 YYYY-MM-DD" % (i + 1))
            continue
        if (due - since).days > MAX_DAYS:
            errs.append("known_red.json 第 %d 条（%s）期限超过 %d 天：续期要重新登记" % (i + 1, it["scope"], MAX_DAYS))
        it = dict(it)
        it["expired_days"] = (today - due).days if today > due else 0
        items.append(it)
    return items, errs


def waive_errors(scope, errors, items):
    """单项内按 pattern 放行。返回 (剩余错误, 已放行[(错误, 条目)], 过期条目命中的错误)"""
    left, waived, expired = [], [], []
    for e in errors:
        hit = next((it for it in items if it.get("pattern") and it["scope"] in scope and any(q in e for q in it["pattern"].split("|"))), None)
        if hit is None:
            left.append(e)
        elif hit["expired_days"] > 0:
            expired.append((e, hit))
            left.append(e)
        else:
            waived.append((e, hit))
    return left, waived, expired


def classify(results, items):
    """整项放行：失败项名含 scope 且条目无 pattern。返回 (硬失败, 已知红[(r, it)], 过期红[(r, it)], 可删条目)"""
    hard, known, expired, used = [], [], [], set()
    for r in results:
        if r["ok"]:
            continue
        it = next((x for x in items if not x.get("pattern") and x["scope"] in r["name"]), None)
        if it is None:
            hard.append(r)
            continue
        used.add(id(it))
        (expired if it["expired_days"] > 0 else known).append((r, it))
    names_ok = [r["name"] for r in results if r["ok"]]
    stale = [x for x in items if not x.get("pattern") and id(x) not in used and any(x["scope"] in n for n in names_ok)]
    return hard, known, expired, stale
