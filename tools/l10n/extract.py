"""英文版文本抽取 + 官方术语表（docs/276 §2.3、§3）。

  python tools/l10n/extract.py            # 抽 ops / enemies 两块 → build/l10n_work/<模块>.items.json，官方表 → build/l10n_work/glossary.json

只读 game/ 与 build/l10n_ref/（ArknightsGameData zh_CN / en_US 原表，不进 git，见 docs/276 文首）。不改游戏文件。
条目：{key, zh, file, path, field, official?, note?}；official 有值的不送模型，直接用官方英文。
"""
import json, os, re, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
REF = ROOT / "build/l10n_ref"
WORK = ROOT / "build/l10n_work"
CJK = re.compile(r"[一-鿿]")

# 暂定词（docs/276 §3.6、§7；协调人 11-05 按建议暂定，用户可改）。整串命中时强制替换，来源记「暂定」
PROVISIONAL = {
    "队长": "Leader", "终结技": "Ultimate", "连携": "Link", "噤声": "Hush",
    "灯火": "Light", "灯油": "Lamp Oil", "照亮范围": "Light Radius", "照亮": "Illuminated",
    "引航灯标": "Guiding Beacon", "灯标": "Beacon", "黑潮": "Black Tide", "安全区": "Safe Zone",
    "通明": "Bright", "摇曳": "Flickering", "暗淡": "Dim", "寂灭": "Out",
    "光域": "Foxfire Field", "灯塔光圈": "Lighthouse Zone", "灯柱": "Lamp Pillar", "光圈": "Beacon Ring",
    "随行": "Follow", "突击": "Assault", "集火": "Focus Fire",
    "指挥": "Command", "坚守": "Steadfast", "鼓舞": "Rally", "祈愿": "Prayer",
    "海嗣祭坛": "Seaborn Altar", "抉择": "Decision", "生机细胞": "Vital Cells",
    "精英一": "Elite 1", "精英二": "Elite 2", "精一": "E1", "精二": "E2", "精英化": "Promotion",
    "技力": "SP", "技力回复": "SP Recovery", "探索": "run", "一次探索": "a run",
    "中期 Boss": "Mid-Boss", "最终 Boss": "Final Boss", "精英": "Elite",
}
# 非整串、只进提示词的固定写法
STYLE_TERMS = {
    "物理": "Physical", "法术": "Arts", "法术伤害": "Arts damage", "物理伤害": "Physical damage", "真实伤害": "True damage",
    "最大生命": "Max HP", "当前生命": "current HP", "生命": "HP", "攻击力": "ATK", "防御力": "DEF", "法术抗性": "RES",
    "攻击速度": "ATK speed", "攻速": "ASPD", "移动速度": "movement speed", "所需技力": "SP cost", "Boss 除外": "Bosses excepted",
    "精英减半": "halved on Elites", "博士": "Doctor", "干员": "Operator", "编队": "squad", "加入编队": "join the squad",
    "罗德岛": "Rhodes Island", "海嗣": "Seaborn", "深海猎人": "Abyssal Hunter", "伊比利亚": "Iberia", "阿戈尔": "Ægir",
    "审判庭": "Inquisition", "源石技艺": "Originium Arts", "源石": "Originium", "侵蚀": "Corrosion", "停顿": "Halt",
    "失重": "Weightless", "击退": "knockback", "拉拽": "pull", "护盾": "Shield", "召唤物": "summon",
}


def L(name):
    return json.load(open(REF / name, encoding="utf-8"))


def official_glossary():
    """zh → (en, 来源) ：干员、技能、天赋、敌人、藏品、职业、分支、状态词。全部来自 en_US 原表。"""
    g = {}
    def put(zh, en, src):
        if zh and en and zh not in g:
            g[zh.strip()] = (en.strip(), src)
    cc, ec = L("cn_character_table.json"), L("en_character_table.json")
    cs, es = L("cn_skill_table.json"), L("en_skill_table.json")
    ce, ee = L("cn_enemy_handbook_table.json")["enemyData"], L("en_enemy_handbook_table.json")["enemyData"]
    cr, er = L("cn_roguelike_topic_table.json"), L("en_roguelike_topic_table.json")
    ck, ek = L("cn_gamedata_const.json")["termDescriptionDict"], L("en_gamedata_const.json")["termDescriptionDict"]
    cu, eu = L("cn_uniequip_table.json").get("subProfDict", {}), L("en_uniequip_table.json").get("subProfDict", {})
    ours = {json.load(open(p, encoding="utf-8")).get("name") for p in (ROOT / "game/data/characters").glob("*.json")}
    usage = {}
    for cid, c in cc.items():
        if not cid.startswith("char_") or cid not in ec:
            continue
        e = ec[cid]
        if c["name"] in ours:
            put(c["name"], e["name"], "character_table." + cid)
            usage[cid] = (c.get("itemUsage"), e.get("itemUsage"), c["name"])
            for i, s in enumerate(c.get("skills") or []):
                sid = s.get("skillId")
                if sid in cs and sid in es:
                    put(cs[sid]["levels"][0]["name"], es[sid]["levels"][0]["name"], "skill_table." + sid)
            for ti, t in enumerate(c.get("talents") or []):
                try:
                    put(t["candidates"][-1]["name"], e["talents"][ti]["candidates"][-1]["name"], "character_table.%s.talents[%d]" % (cid, ti))
                except (KeyError, IndexError, TypeError):
                    pass
    # 德克萨斯「剑雨滂沱」= 缄默德克萨斯三技能（docs/276 §3.2）
    if "skchr_texas2_3" in cs:
        put(cs["skchr_texas2_3"]["levels"][0]["name"], es["skchr_texas2_3"]["levels"][0]["name"], "skill_table.skchr_texas2_3")
    for eid, v in ce.items():
        if eid in ee:
            put(v.get("name"), ee[eid].get("name"), "enemy_handbook_table." + eid)
            put((v.get("name") or "").strip("“”\""), (ee[eid].get("name") or ""), "enemy_handbook_table." + eid)
    for iid, it in cr["details"]["rogue_2"]["items"].items():
        en = er["details"]["rogue_2"]["items"].get(iid, {}).get("name")
        put(it.get("name"), en, "roguelike_topic_table.rogue_2.items." + iid)
    for k, v in ck.items():
        if k in ek:
            put(v.get("termName"), ek[k].get("termName"), "gamedata_const.termDescriptionDict." + k)
    for k, v in cu.items():
        if k in eu:
            put(v.get("subProfessionName"), eu[k].get("subProfessionName"), "uniequip_table.subProfDict." + k)
    # 集成战略 #2 结局、猎潮的骑士、大群等（en_US 原表逐条查过，docs/276 §8）
    E = "roguelike_topic_table.rogue_2.archiveComp.endbook"
    for zh, en, src in [("平凡即是喜乐", "Precious Days", E), ("静谧时代", "Age of the Silence", E), ("息潮的代价", "Price of Peace", E),
                        ("如星空般深蓝", "Stella Caerula", E), ("猎潮的骑士", "Tide-Hunt Knight", "character_table.trap_079_allydonq"),
                        ("大群", "We Many", "enemy_handbook_table.enemy_1529_dsdevr（The Endspeaker, Will of We Many）"),
                        ("罗辛南特", "Rocinante", "rogue_2_relic_grace_84（Regressed Rocinante）")]:
        g[zh] = (en, src)
    for zh, en in {"先锋": "Vanguard", "近卫": "Guard", "重装": "Defender", "狙击": "Sniper", "术师": "Caster",
                   "医疗": "Medic", "辅助": "Supporter", "特种": "Specialist"}.items():
        g[zh] = (en, "character_table profession（data.gd CLASS_EN）")
    return g, usage


SKIP_KEYS = {"foot_exempt", "cond", "tex", "id", "script", "icon", "sprites", "src_note"}


def walk(o, path, out, skip_path=lambda p: False):
    if isinstance(o, str):
        if CJK.search(o) and not skip_path(path):
            out.append((path, o))
    elif isinstance(o, dict):
        for k, v in o.items():
            if k.startswith("_") or k in SKIP_KEYS:
                continue
            walk(v, path + [k], out, skip_path)
    elif isinstance(o, list):
        for i, v in enumerate(o):
            walk(v, path + [str(i)], out, skip_path)


def gd_strings(path):
    """脚本里的中文字面量（去注释、去 print / push_*）。按出现顺序去重。"""
    res = []
    seen = set()
    for ln, line in enumerate(open(path, encoding="utf-8"), 1):
        code, q = "", False
        for i, c in enumerate(line):
            if c == '"' and (i == 0 or line[i - 1] != "\\"):
                q = not q
            if c == "#" and not q:
                break
            code += c
        if re.search(r"\b(print|prints|printerr|push_warning|push_error|assert)\(", code):
            continue
        for m in re.finditer(r'"((?:[^"\\\n]|\\.)*)"', code):
            s = m.group(1)
            # 还原 GDScript 字面量转义，键要和运行时的字符串一字不差（\" → "、\n → 换行）
            s = s.replace('\\"', '"').replace("\\n", "\n").replace("\\t", "\t").replace("\\\\", "\\")
            if CJK.search(s) and s not in seen:
                seen.add(s)
                res.append((ln, s))
    return res


def item(key, zh, file, path, field):
    return {"key": key, "zh": zh, "file": file, "path": path, "field": field}


def extract():
    g, usage = official_glossary()
    use_by_zhname = {v[2]: (v[0], v[1], cid) for cid, v in usage.items()}
    ops, ens = [], []
    op_ids = []
    for p in sorted((ROOT / "game/data/characters").glob("*.json")):
        d = json.load(open(p, encoding="utf-8"))
        oid = d.get("id") or p.stem
        op_ids.append(oid)
        out = []
        walk(d, [], out)
        for path, s in out:
            ops.append(item("op.%s.%s" % (oid, ".".join(path)), s, "game/data/characters/" + p.name, "/".join(path), path[-1] if not path[-1].isdigit() else path[-2]))
    ut = json.load(open(ROOT / "game/data/ult_text.json", encoding="utf-8"))
    out = []
    walk(ut, [], out)
    for path, s in out:
        ops.append(item("ult." + ".".join(path), s, "game/data/ult_text.json", "/".join(path), path[-1]))
    lore = json.load(open(ROOT / "game/data/lore.json", encoding="utf-8"))
    enemy_ids = set(json.load(open(ROOT / "game/data/enemies.json", encoding="utf-8"))["enemies"].keys())
    for k, v in lore.items():
        if k.startswith("_"):
            continue
        out = []
        walk(v, [], out)
        dst = ens if k in enemy_ids or k in ("iberia", "carmen", "bishop", "archon", "immortal", "paranoia", "izumik", "ishar", "knight", "path", "mimic", "mother", "tear", "fractal", "tracer", "nest", "founder", "runner", "floater", "reaper", "skimmer", "pocket", "spitter", "brood", "offspring", "stone", "slider", "bone") else ops
        for path, s in out:
            dst.append(item("lore.%s.%s" % (k, ".".join(path)), s, "game/data/lore.json", k + "/" + "/".join(path), "lore" if path[-1] == "lore" else "profile"))
        # 档案键名（性别 / 出身地 …）也要翻
        for pk in (v.get("profile") or {}):
            if CJK.search(pk):
                dst.append(item("lore.%s.profile_key.%s" % (k, pk), pk, "game/data/lore.json", k + "/profile(key)", "profile_key"))
    ej = json.load(open(ROOT / "game/data/enemies.json", encoding="utf-8"))
    out = []
    walk(ej["enemies"], [], out)
    for path, s in out:
        ens.append(item("enemy." + ".".join(path), s, "game/data/enemies.json", "/".join(path), path[-1]))
    # 图鉴机制行（gallery.gd ENEMY_DESC）
    gl = open(ROOT / "game/scripts/gallery.gd", encoding="utf-8").read().splitlines()
    on = False
    for ln, line in enumerate(gl, 1):
        if line.startswith("const ENEMY_DESC"):
            on = True
            continue
        if on and line.startswith("}"):
            break
        m = on and re.match(r'\s*"(\w+)":\s*"((?:[^"\\]|\\.)*)"', line)
        if m:
            ens.append(item("enemy.%s.gallery" % m.group(1), m.group(2), "game/scripts/gallery.gd", "ENEMY_DESC/%s (L%d)" % (m.group(1), ln), "gallery"))
    # 敌人 / Boss 脚本里的招式名、横幅、飘字（框架阶段再挂 tr 键）
    for p in sorted((ROOT / "game/scripts/enemies").rglob("*.gd")):
        rel = p.relative_to(ROOT).as_posix()
        for i, (ln, s) in enumerate(gd_strings(p)):
            ens.append(item("enemy.gd.%s.%03d" % (p.stem, i), s, rel, "L%d" % ln, "gd"))
    # 官方英文：整串命中官方表或暂定词
    for it in ops + ens:
        zh = it["zh"].strip()
        f = it["field"]
        core = zh.strip("“”\"")
        hit = None
        if zh in PROVISIONAL:
            hit = (PROVISIONAL[zh], "暂定（docs/276 §3.6）")
        elif zh in g:
            hit = g[zh]
        elif core in g and core != zh:
            hit = ("'%s'" % g[core][0].strip("'"), g[core][1])
        if hit and f not in ("desc", "lore", "intro", "text", "branch_desc", "gallery", "brief"):
            it["official"], it["official_src"] = hit
        # 招聘合同原文（干员简介）= 官方 itemUsage
        if f in ("intro", "lore"):
            for cnu, enu, cid in use_by_zhname.values():
                if not cnu:
                    continue
                if zh.rstrip("。") == cnu.rstrip("。"):
                    it["official"], it["official_src"] = enu, "character_table.%s.itemUsage" % cid
                elif f == "lore" and zh.startswith("「" + cnu + "」"):
                    it["quote_en"], it["quote_src"] = enu, "character_table.%s.itemUsage" % cid
    WORK.mkdir(parents=True, exist_ok=True)
    gl_out = {k: {"en": v[0], "src": v[1]} for k, v in g.items()}
    json.dump(gl_out, open(WORK / "glossary.json", "w", encoding="utf-8"), ensure_ascii=False, indent=0)
    for name, items in (("ops", ops), ("enemies", ens)):
        json.dump(items, open(WORK / (name + ".items.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
        uz = {i["zh"] for i in items if "official" not in i}
        print("%-8s 条目 %4d  官方 %4d  需翻（去重）%4d  中文字数 %6d" % (
            name, len(items), sum(1 for i in items if "official" in i), len(uz), sum(len(CJK.findall(z)) for z in uz)))
    print("官方表", len(g), "条 →", WORK / "glossary.json")
    extract_modules(g)


# ---------------------------------------------------------------- 其余模块（docs/276 §11，11-11 恢复）：按原文键接入
# 模块 → {json: [数据文件]，gd: [脚本 glob]，skip: [不抽的脚本]}。键：<模块>.<文件名>.<路径> / <模块>.gd.<相对路径>.<序号>。
# 显示时 ui.gd 助手按原文查表（Loc.s），所以这些键只作 CSV 行标识，代码不引用；json 不改结构
MODULES = {
    "ui": {"json": ["guide.json", "onboard.json", "credits.json", "balance.json", "boot_order.json", "boot_operator_order.json", "doctor.json"],
           "gd": ["scripts/*.gd", "scripts/screens/*.gd", "scripts/core/*.gd", "scripts/render/*.gd", "scripts/world/*.gd"],
           "skip": ["screens/ak_mock.gd", "core/perf_report.gd", "core/loc.gd", "screens/perf_view.gd"]},
    "relics": {"json": ["relics.json", "relic_effects.json"], "gd": [], "skip": []},
    "events": {"json": ["waves.json", "events_v2.json"], "gd": [], "skip": []},
    "meta": {"json": ["meta_tree.json", "meta_roots.json", "cards.json", "medals.json", "synergy.json", "practice_squads.json"],
             "gd": [], "skip": []},
    "run": {"json": [], "gd": ["scripts/run/*.gd", "scripts/characters/**/*.gd", "scripts/allies/*.gd"], "skip": []},
}
# 只给代码 / 工具看的字段（中文也不翻）
JSON_SKIP = {"src", "_doc", "requires", "conflicts", "id", "tex", "icon", "sfx", "script", "set", "lane", "pool"}


def official_extra():
    """集成战略 #2 的藏品原作说明（usage）、事件 / 选项标题：中文原文 → 官方英文（整串命中才用）"""
    cr, er = L("cn_roguelike_topic_table.json")["details"]["rogue_2"], L("en_roguelike_topic_table.json")["details"]["rogue_2"]
    m = {}
    for iid, it in cr["items"].items():
        e = er["items"].get(iid, {})
        for f in ("usage", "description", "name"):
            if it.get(f) and e.get(f):
                m.setdefault(it[f].strip(), (e[f].strip(), "roguelike_topic_table.rogue_2.items.%s.%s" % (iid, f)))
    for sec in ("choiceScenes", "choices"):
        for k, v in cr.get(sec, {}).items():
            e = er.get(sec, {}).get(k, {})
            for f in ("title", "description"):
                if v.get(f) and e.get(f):
                    m.setdefault(v[f].strip(), (e[f].strip(), "roguelike_topic_table.rogue_2.%s.%s.%s" % (sec, k, f)))
    for k, v in cr.get("nodeTypeData", {}).items():
        e = er.get("nodeTypeData", {}).get(k, {})
        if v.get("name") and e.get("name"):
            m.setdefault(v["name"], (e["name"], "roguelike_topic_table.rogue_2.nodeTypeData.%s" % k))
    return m


def extract_modules(g):
    import glob
    ex = official_extra()
    done_zh = set()
    for m in ("ops", "enemies"):
        for it in json.load(open(WORK / (m + ".items.json"), encoding="utf-8")):
            done_zh.add(it["zh"])
    for name, spec in MODULES.items():
        items = []
        for f in spec["json"]:
            p = ROOT / "game/data" / f
            if not p.exists():
                print("  缺文件", f); continue
            d = json.load(open(p, encoding="utf-8"))
            out = []
            walk(d, [], out)
            for path, s in out:
                if any(x in JSON_SKIP for x in path):
                    continue
                field = path[-1] if not path[-1].isdigit() else (path[-2] if len(path) > 1 else "")
                items.append(item("%s.%s.%s" % (name, p.stem, ".".join(path)), s, "game/data/" + f, "/".join(path), field))
        for gpat in spec["gd"]:
            for p in sorted(glob.glob(str(ROOT / "game" / gpat), recursive=True)):
                rel = Path(p).relative_to(ROOT / "game/scripts").as_posix()
                if rel in spec["skip"] or "/ult" in "/" + rel and Path(p).name.startswith("ult"):
                    pass
                if rel in spec["skip"]:
                    continue
                for i, (ln, s) in enumerate(gd_strings(Path(p))):
                    items.append(item("%s.gd.%s.%03d" % (name, rel[:-3].replace("/", "."), i), s, "game/scripts/" + rel, "L%d" % ln, "gd"))
        for it in items:
            zh = it["zh"].strip()
            hit = PROVISIONAL.get(zh) and (PROVISIONAL[zh], "暂定（docs/276 §3.6）") or g.get(zh) or ex.get(zh)
            if hit:
                it["official"], it["official_src"] = hit
        json.dump(items, open(WORK / (name + ".items.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
        uz = {i["zh"] for i in items if "official" not in i and i["zh"] not in done_zh}
        print("%-8s 条目 %4d  官方 %4d  需翻（去重、扣除 ops / enemies 已有）%4d  中文字数 %6d" % (
            name, len(items), sum(1 for i in items if "official" in i), len(uz), sum(len(CJK.findall(z)) for z in uz)))


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    extract()
