# -*- coding: utf-8 -*-
"""说明文字 <-> 数值对账：只读扫描原型。python -I text_reconcile_scan.py [--json] [--examples N] [--root DIR]

按「文本类别」统计玩家可见文字：总条数 / 含数字 / 含占位 / 字面数字未占位 + 样例。纯标准库，只读 game/data/**.json。
占位：{$键} / {$a*$b:0}（干员、藏品、升级卡、局外树，求值见 character.gd fill_text / relic_db.fill_desc）与 {键}（guide.json，intro.fill_numbers）。
「字面数字」= 去掉占位后仍剩的数字，再排除以下误报：
  E1 字母+数字标识 S3 / E2 / Mon3tr / Lv2 / T1 / W2（前后紧邻 ASCII 字母的数字）
  E2 年份 / 日期 / 时刻  2026年、10-28、10:00、8:00（时钟写法）
  E3 编号引用  docs/184、#56、第 N（序数：第3次 / 第2阶段 / 第N个）、N号 / N阶段 / N档 / N星
  E4 「」『』《》 内的专名（敌人名 / 技能名里的数字）整段剔除
  E5 文字里的罗马序号不含阿拉伯数字，天然不计；「精二」「三选一」等汉字数不计（汉字数字不扫，见 NOTE）
NOTE 汉字数字（三选一、两倍、一半）没有扫：它们同样可能与数值脱节，原型不覆盖。
"""
import argparse, glob, json, os, re, sys, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TEXT_KEYS = {"desc", "text", "label", "info", "tip", "banner", "branch_desc", "lore", "lines", "more", "hint",
             "more_hint", "adapt", "original", "title", "intro", "line"}
# 这些键不是玩家可见文字（机器字段 / 出处注释）
SKIP_KEYS = {"_doc", "src", "source", "rule", "type", "stat", "id", "key", "tex", "en", "icon", "voice", "script"}
PH_ANY = re.compile(r"\{[^{}]*\}")
PH_DOLLAR = re.compile(r"\{[^{}]*\$[^{}]*\}")
NUM = re.compile(r"(?<![A-Za-z0-9.])\d+(?:\.\d+)?(?![A-Za-z0-9])|(?<=[+\-−×x/])\d+(?:\.\d+)?")
HAS_DIGIT = re.compile(r"\d")


def strip_false_pos(s):
    s = re.sub(r"[「『《][^」』》]*[」』》]", "", s)                        # E4
    s = re.sub(r"\d{4}\s*年|\d{1,2}\s*[-/月]\s*\d{1,2}\s*[日号]?", "", s)   # E2 日期
    s = re.sub(r"\d{1,2}\s*[:：]\s*\d{2}", "", s)                          # E2 时刻 10:00
    s = re.sub(r"docs/\d+\w*|#\d+|第\s*\d+\s*(?:次|阶段|个|层|章|关|批|名|只|轮|段|节|人|件|张|条)?", "", s)  # E3
    s = re.sub(r"\d+\s*(?:号|阶段|档|星|期|章)", "", s)                    # E3
    s = re.sub(r"[A-Za-z]+\d+[A-Za-z]*|\d+[A-Za-z]+", "", s)               # E1
    return s


def literal_numbers(text):
    s = PH_ANY.sub("⟨⟩", text)
    s = strip_false_pos(s)
    return [m.group(0) for m in NUM.finditer(s)]


def walk(n, path, fname, out, in_text=False):
    """收集 (文件, 键路径, 末键, 文本)"""
    if isinstance(n, dict):
        for k, v in n.items():
            if k in SKIP_KEYS or k.startswith("_"):
                continue
            walk(v, path + "." + k, fname, out, k in TEXT_KEYS)
    elif isinstance(n, list):
        for i, v in enumerate(n):
            walk(v, "%s[%d]" % (path, i), fname, out, in_text)
    elif isinstance(n, str) and in_text and re.search(r"[\u4e00-\u9fff]", n):
        out.append((fname, path.lstrip("."), path.rsplit(".", 1)[-1].split("[")[0], n))


def category(fname, key, path):
    f = fname.replace("\\", "/")
    if f.startswith("characters"):
        if key == "banner": return "干员·积木 banner"
        if ".progression[" in "." + path: return "干员·成长/精英化节点"
        if path.startswith("skills"): return "干员·技能"
        if path.startswith("attack"): return "干员·普攻"
        if path.startswith("talent"): return "干员·天赋"
        if path.startswith("gallery"): return "干员·图鉴简介"
        return "干员·其它(" + key + ")"
    if f == "relics.json": return "藏品·relics.json " + key + ("（不直接显示）" if key == "original" else "（无 effects 条目时的缺省说明）")
    if f == "relic_effects.json": return "藏品·relic_effects desc（实际卡面）"
    if f == "cards.json": return "升级卡·cards.json " + ("fillers" if path.startswith("fillers") else "passives") + " desc"
    if f == "meta_tree.json": return "局外·认知塑造节点 desc"
    if f == "events_v2.json" or (f == "waves.json" and "events[" in path):
        return "事件·" + ("选项 desc" if key == "desc" else "选项 label" if key == "label" else "正文 text")
    if f == "medals.json": return "蚀刻章·desc"
    if f == "guide.json": return "开局指南·pages/lines/more"
    if f == "enemies.json": return "敌人·enemies.json desc"
    if f == "lore.json": return "图鉴·lore.json 档案文字"
    if f == "waves.json" and ".gallery." in "." + path: return "结局·waves.json endings gallery/omen"
    if f == "waves.json": return "刷怪表·waves.json 其它文字(" + key + ")"
    if f == "practice_squads.json": return "练习编队·文字"
    return "其它·" + f + "(" + key + ")"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--examples", type=int, default=3)
    ap.add_argument("--root", default=ROOT)
    a = ap.parse_args()
    t0 = time.time()
    data = os.path.join(a.root, "game", "data")
    items = []
    files = sorted(glob.glob(os.path.join(data, "**", "*.json"), recursive=True))
    for p in files:
        rel = os.path.relpath(p, data)
        if os.path.basename(p) in ("enemy_pixels.json", "enemy_redraw.json", "balance.json", "maps", "medals_layout.json", "boot_order.json"):
            continue
        d = json.load(open(p, encoding="utf-8"))
        walk(d, "", rel, items)
    cats = {}
    for fname, path, key, text in items:
        c = cats.setdefault(category(fname, key, path), {"total": 0, "with_digit": 0, "with_ph": 0, "ph_dollar": 0, "literal": 0, "literal_numbers": 0, "ex": []})
        c["total"] += 1
        if HAS_DIGIT.search(text): c["with_digit"] += 1
        if PH_ANY.search(text): c["with_ph"] += 1
        if PH_DOLLAR.search(text): c["ph_dollar"] += 1
        lits = literal_numbers(text)
        if lits:
            c["literal"] += 1
            c["literal_numbers"] += len(lits)
            if len(c["ex"]) < a.examples:
                i = text.find(lits[0])
                c["ex"].append({"file": fname, "path": path, "frag": text[max(0, i - 12):i + len(lits[0]) + 10], "nums": lits[:5]})
    res = {"seconds": round(time.time() - t0, 2), "total_texts": sum(c["total"] for c in cats.values()),
           "total_literal": sum(c["literal"] for c in cats.values()), "categories": cats}
    if a.json:
        print(json.dumps(res, ensure_ascii=False, indent=1)); return
    print("%-44s %6s %6s %6s %6s %6s" % ("类别", "总条", "含数字", "含占位", "字面", "(数)"))
    for k in sorted(cats):
        c = cats[k]
        print("%-44s %6d %6d %6d %6d %6d" % (k[:44], c["total"], c["with_digit"], c["with_ph"], c["literal"], c["literal_numbers"]))
    print("合计 %d 条文字，字面数字未占位 %d 条；耗时 %.2f 秒" % (res["total_texts"], res["total_literal"], res["seconds"]))
    if a.examples:
        print("\n样例（每类前 %d 条字面数字）" % a.examples)
        for k in sorted(cats):
            for e in cats[k]["ex"]:
                print("[%s] %s :: %s :: ...%s... %s" % (k, e["file"], e["path"], e["frag"].replace("\n", " "), e["nums"]))


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    main()
