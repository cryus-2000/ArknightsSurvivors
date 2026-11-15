"""日语版（ja）：以已提交的 game/l10n/<模块>.csv 为准，补 ja 列（docs/276 §13）。

  python tools/l10n/translate_ja.py glossary            # 日服官方名表 → build/l10n_work/glossary_ja.json（读 build/l10n_ref/ 的 cn_ / ja_ 原表）
  python tools/l10n/translate_ja.py run [--limit N]      # Vertex Gemini 翻译（缓存 build/l10n_work/cache_ja.json，断了重跑只补缺）
  python tools/l10n/translate_ja.py qa                   # 查占位符 / 简体残留 / 空译，坏的从缓存删掉（再 run 重翻）
  python tools/l10n/translate_ja.py csv                  # 写回各 CSV 的 ja 列与 _ja_note 列

口径：
- 原文（中文）是源语言；英文列只作意思参照。官方日文（ja_JP 原表能整串查到的名字、藏品、事件标题、招聘合同）不送模型。
- 查不到官方名的名字（本作自拟的普攻 / 成长节点 / 招式 / 自创词）由模型意译，_ja_note 记「自译」。
- 键与英文列不动；translate_vertex.py csv 重写 CSV 时按键保留 ja / _ja_note 两列。
鉴权同 translate_vertex.py（gcloud 令牌）。只用标准库。
"""
import argparse, concurrent.futures as cf, csv, json, os, re, sys, threading
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import translate_vertex as TV  # noqa: E402

ROOT = TV.ROOT
WORK = TV.WORK
REF = ROOT / "build/l10n_ref"
MODULES = ["ops", "enemies", "ui", "relics", "events", "meta", "run", "extra"]
CACHE_P = WORK / "cache_ja.json"
PH = re.compile(r"\{\$[^}]*\}|%[-+0-9.]*[dsf]|%%|\{[a-z_0-9]+\}")
HAN = re.compile(r"[一-鿿]")

# 本作自创词 / 系统词的日文（官方表能查到的写在注释里；查不到的为自译）。整串命中直接用
PROVISIONAL_JA = {
    "队长": "リーダー", "终结技": "必殺技", "连携": "連携", "噤声": "沈黙",
    "灯火": "灯火", "灯油": "灯油", "照亮范围": "照明範囲", "照亮": "照明",          # 灯火 / 灯油：rogue_2 官方
    "引航灯标": "導きの灯標", "灯标": "灯標", "黑潮": "黒潮", "安全区": "安全圏",
    "通明": "明明", "摇曳": "揺曳", "暗淡": "幽幽", "寂灭": "寂滅",                  # 灯火四档：rogue_2 官方
    "光域": "狐火領域", "灯塔光圈": "灯台の光輪", "灯柱": "灯柱", "光圈": "光輪",
    "随行": "追従", "突击": "突撃", "集火": "集中攻撃",
    "指挥": "指揮", "坚守": "堅守", "鼓舞": "鼓舞", "祈愿": "祈願",
    "海嗣祭坛": "シーボーンの祭壇", "抉择": "選択", "生机细胞": "有機細胞",
    "精英一": "昇進1", "精英二": "昇進2", "精一": "昇進1", "精二": "昇進2", "精英化": "昇進",
    "技力": "SP", "技力回复": "SP回復", "探索": "探索", "一次探索": "1回の探索",
    "中期 Boss": "中ボス", "最终 Boss": "最終ボス", "精英": "エリート",
}
# 只进提示词的固定写法（多数是日服官方用语）
STYLE_JA = {
    "物理": "物理", "法术": "術", "法术伤害": "術ダメージ", "物理伤害": "物理ダメージ", "真实伤害": "確定ダメージ",
    "最大生命": "最大HP", "当前生命": "現在HP", "生命": "HP", "攻击力": "攻撃力", "防御力": "防御力", "法术抗性": "術耐性",
    "攻击速度": "攻撃速度", "攻速": "攻撃速度", "移动速度": "移動速度", "所需技力": "必要SP", "Boss 除外": "ボスを除く",
    "博士": "ドクター", "干员": "オペレーター", "编队": "編成", "罗德岛": "ロドス", "海嗣": "シーボーン", "恐鱼": "恐魚",
    "深海猎人": "アビサルハンター", "伊比利亚": "イベリア", "阿戈尔": "エーギル", "审判庭": "裁判所", "审判官": "審問官",
    "源石技艺": "アーツ", "源石": "源石", "源石锭": "源石錐", "藏品": "秘宝", "收藏品": "秘宝", "招募": "招集",
    "侵蚀": "侵蝕", "停顿": "足止め", "失重": "反重力", "悬浮": "浮遊", "眩晕": "スタン", "晕眩": "スタン", "束缚": "拘束",
    "冻结": "凍結", "减速": "減速", "神经损伤": "神経損傷", "侵蚀损伤": "侵蝕損傷", "击退": "突き飛ばし", "拉拽": "引き寄せ",
    "护盾": "バリア", "召唤物": "召喚ユニット", "大群": "大群", "溟痕": "溟痕", "大静谧": "大いなる静謐",
    "集成战略": "統合戦略", "水月与深蓝之树": "ミヅキと紺碧の樹", "深蓝之树": "紺碧の樹", "认知塑造": "認知形成",
    "诡意行商": "怪しい旅商人", "不期而遇": "思わぬ遭遇", "安全屋": "セーフハウス", "鸭爵": "ダック卿", "猎潮的骑士": "猟潮の騎士",
    "先锋": "先鋒", "近卫": "前衛", "重装": "重装", "狙击": "狙撃", "术师": "術師", "医疗": "医療", "辅助": "補助", "特种": "特殊",
    "希望": "希望", "精英减半": "エリートには半減",
}

STYLE = """You are translating a Chinese fan game (an Arknights squad survivor roguelike set in the Integrated Strategies #2 'Mizuki & Caerula Arbor' setting) into Japanese.
Translate from the Chinese ('zh'). The English ('en') is an existing translation given only to help you understand the meaning; do not translate from it and do not copy its wording.
Write like the official Japanese Arknights client (アークナイツ, Yostar): restrained, short, information-dense. UI reads like a Rhodes Island combat terminal, operator files like personnel records, effect text like the official skill descriptions.
Rules:
- Effect / skill / talent text: official skill-description syntax, e.g. 「攻撃力+50%、攻撃速度+20」「3秒間スタンさせる」「最大HPの10%回復」「（ボスを除く）」. No です/ます in effect text. Numbers and units half-width; seconds as 「3秒」.
- UI labels and buttons: as short as the Chinese or shorter. A short Chinese label must stay a short Japanese label (noun phrase), never a sentence. Messages / hints: plain polite only where the Chinese addresses the player (〜してください is fine for instructions).
- Lore / operator files: である調 or plain past, factual. Enemy files: present tense observation, short sentences.
- Punctuation: Japanese 、。「」『』・！？ ー. Chinese quotes 「」 or “” become 「」. Middle dot between names → ・ . No Chinese-only punctuation （；). Keep "×1.5", "+25%", "10:00", "ATK", "DPS", "Lv." as is.
- Never output Simplified Chinese characters (们 这 说 发 设 时 击 战 门 etc.); use Japanese forms (撃 戦 時 発 設). Every output must be natural Japanese.
- Pronouns: avoid 彼/彼女 unless needed; prefer the name or omit the subject.
- Placeholders MUST be copied exactly, same count and same spelling: {$...} (code fills numbers in; never translate or edit inside the braces), %d, %s, %.1f, %%, {name}-style names, and line breaks (\\n). Put the unit right after a placeholder like the Chinese does ("{$dur} 秒" -> "{$dur}秒"). Keep the line count when the Chinese has line breaks in a short label.
- Names already translated (MUST reuse exactly when the Chinese name appears, e.g. inside 「」): {known}
- Fixed terms (MUST use exactly): {terms}
- Official Japanese Arknights names / texts that appear in this batch (MUST use exactly): {official}
Output: a JSON object mapping each input id to the Japanese string. For ids marked field "intro" output instead an object {"ja": Japanese, "note": "Chinese note explaining any pun/meme and how the Japanese keeps it, or empty"}. No extra text."""

INTRO_NOTE = ("Items with field 'intro' are recruit-card blurbs written by the game's author with jokes and memes. Keep the original meaning and the joke; "
              "do not tone it down. If a line quotes or riffs on official Arknights text, reuse the official Japanese given in 'ref'.")

SHORT_NOTE = ("Items with field 'short' are fixed-width chips / HUD labels: the Japanese must be at most as many characters as the Chinese "
              "(katakana long words may be abbreviated the way the official client does, e.g. 攻撃速度 → 攻速 is NOT official; prefer 攻撃速度 if it fits, else a natural abbreviation).")


def L(name):
    return json.load(open(REF / name, encoding="utf-8"))


def glossary():
    """zh → (ja, 来源)：干员 / 技能 / 天赋 / 敌人 / 藏品 / 术语 / 分支 / 事件 / 结局 / 招聘合同。全部来自 ja_JP 原表"""
    g = {}
    def put(zh, ja, src):
        if zh and ja and zh.strip() not in g:
            g[zh.strip()] = (ja.strip(), src)
    cc, jc = L("cn_character_table.json"), L("ja_character_table.json")
    cs, js = L("cn_skill_table.json"), L("ja_skill_table.json")
    ce, je = L("cn_enemy_handbook_table.json")["enemyData"], L("ja_enemy_handbook_table.json")["enemyData"]
    cr, jr = L("cn_roguelike_topic_table.json")["details"], L("ja_roguelike_topic_table.json")["details"]
    ck, jk = L("cn_gamedata_const.json")["termDescriptionDict"], L("ja_gamedata_const.json")["termDescriptionDict"]
    cu, ju = L("cn_uniequip_table.json").get("subProfDict", {}), L("ja_uniequip_table.json").get("subProfDict", {})
    ours = {json.load(open(p, encoding="utf-8")).get("name") for p in (ROOT / "game/data/characters").glob("*.json")}
    usage = {}
    for cid, c in cc.items():
        if not cid.startswith("char_") or cid not in jc:
            continue
        e = jc[cid]
        if c["name"] in ours:
            put(c["name"], e["name"], "character_table." + cid)
            for f in ("itemUsage", "itemDesc"):
                if c.get(f) and e.get(f):
                    put(c[f], e[f], "character_table.%s.%s" % (cid, f))
            usage[c["name"]] = {"usage_zh": c.get("itemUsage"), "usage_ja": e.get("itemUsage"), "desc_zh": c.get("itemDesc"), "desc_ja": e.get("itemDesc")}
            for s in c.get("skills") or []:
                sid = s.get("skillId")
                if sid in cs and sid in js:
                    put(cs[sid]["levels"][0]["name"], js[sid]["levels"][0]["name"], "skill_table." + sid)
            for ti, t in enumerate(c.get("talents") or []):
                try:
                    put(t["candidates"][-1]["name"], e["talents"][ti]["candidates"][-1]["name"], "character_table.%s.talents[%d]" % (cid, ti))
                except (KeyError, IndexError, TypeError):
                    pass
    for sid in ("skchr_texas2_3", "skcom_charge_cost[3]"):
        if sid in cs and sid in js:
            put(cs[sid]["levels"][0]["name"], js[sid]["levels"][0]["name"], "skill_table." + sid)
    for eid, v in ce.items():
        if eid in je:
            put(v.get("name"), je[eid].get("name"), "enemy_handbook_table." + eid)
            put((v.get("name") or "").strip("“”\""), (je[eid].get("name") or "").strip("「」"), "enemy_handbook_table." + eid)
    r2c, r2j = cr["rogue_2"], jr["rogue_2"]
    for iid, it in r2c["items"].items():
        e = r2j["items"].get(iid, {})
        for f in ("name", "usage", "description"):
            if it.get(f) and e.get(f):
                put(it[f], e[f], "roguelike_topic_table.rogue_2.items.%s.%s" % (iid, f))
    for sec in ("choiceScenes", "choices"):
        for k, v in r2c.get(sec, {}).items():
            e = r2j.get(sec, {}).get(k, {})
            for f in ("title", "description"):
                if v.get(f) and e.get(f):
                    put(v[f], e[f], "roguelike_topic_table.rogue_2.%s.%s.%s" % (sec, k, f))
    for k, v in r2c.get("nodeTypeData", {}).items():
        e = r2j.get("nodeTypeData", {}).get(k, {})
        if v.get("name") and e.get("name"):
            put(v["name"], e["name"], "roguelike_topic_table.rogue_2.nodeTypeData.%s" % k)
    for k, v in ck.items():
        if k in jk:
            put(v.get("termName"), jk[k].get("termName"), "gamedata_const.termDescriptionDict." + k)
    for k, v in cu.items():
        if k in ju:
            put(v.get("subProfessionName"), ju[k].get("subProfessionName"), "uniequip_table.subProfDict." + k)
    E = "roguelike_topic_table.rogue_2.archiveComp.endbook"
    for zh, ja in [("平凡即是喜乐", "平凡こそ幸せ"), ("静谧时代", "静謐なる時代"), ("息潮的代价", "凪の代償"), ("如星空般深蓝", "星空を湛えた群青")]:
        g[zh] = (ja, E)
    g["猎潮的骑士"] = ("猟潮の騎士", "roguelike_topic_table.rogue_2（【猟潮の騎士】）")
    g["水月与深蓝之树"] = ("ミヅキと紺碧の樹", "roguelike_topic_table.topics.rogue_2.name")
    for zh, ja in {"先锋": "先鋒", "近卫": "前衛", "重装": "重装", "狙击": "狙撃", "术师": "術師",
                   "医疗": "医療", "辅助": "補助", "特种": "特殊"}.items():
        g[zh] = (ja, "character_table profession（日服職業名）")
    return g, usage


def load_glossary():
    p = WORK / "glossary_ja.json"
    if not p.exists():
        sys.exit("先跑 glossary")
    d = json.load(open(p, encoding="utf-8"))
    return d["terms"], d["usage"]


def cmd_glossary(a):
    g, usage = glossary()
    WORK.mkdir(parents=True, exist_ok=True)
    json.dump({"terms": {k: {"ja": v[0], "src": v[1]} for k, v in g.items()}, "usage": usage},
              open(WORK / "glossary_ja.json", "w", encoding="utf-8"), ensure_ascii=False, indent=0)
    print("日服官方表", len(g), "条 →", WORK / "glossary_ja.json")


def read_rows():
    """[(模块, 行 dict)]，行按原顺序"""
    out = []
    for m in MODULES:
        p = ROOT / "game/l10n" / (m + ".csv")
        for r in csv.DictReader(open(p, encoding="utf-8")):
            out.append((m, r))
    return out


def unit_of(r):
    """行 → (待翻原文, 是否短版)；原文键行的原文就是键"""
    k = r["keys"]
    if k.startswith("short:"):
        return k[6:], True
    if r["_source"] == "原文键":
        return k, False
    return r["_zh"], False


def field_of(key):
    if key.startswith("short:"):
        return "short"
    parts = key.split(".")
    if ".intro" in key and key.startswith("op."):
        return "intro"
    if ".gd." in key:
        return "gd"
    for p in reversed(parts):
        if not p.isdigit():
            return p
    return ""


def units():
    """去重后的待翻单元：uid（短版加 short: 前缀）→ {zh, en, fields, ctx}"""
    u = {}
    for m, r in read_rows():
        zh, short = unit_of(r)
        if not zh or not HAN.search(zh):
            continue
        uid = ("short:" + zh) if short else zh
        e = u.setdefault(uid, {"zh": zh, "en": "", "fields": set(), "ctx": ""})
        if r["en"] and not e["en"]:
            e["en"] = r["en"]
        if r["_source"] != "原文键":
            e["fields"].add(field_of(r["keys"]))
            if not e["ctx"] or e["ctx"].startswith("short:"):
                e["ctx"] = r["keys"]
    return u


def official_hit(zh, g):
    s = zh.strip()
    if s in PROVISIONAL_JA:
        return PROVISIONAL_JA[s], "暂定（docs/276 §13）"
    if s in g:
        return g[s]["ja"], g[s]["src"]
    core = s.strip("“”\"「」")
    if core != s and core in g:
        return "「%s」" % g[core]["ja"].strip("「」"), g[core]["src"]
    return None


def opname_ja(g):
    d = {}
    for p in (ROOT / "game/data/characters").glob("*.json"):
        j = json.load(open(p, encoding="utf-8"))
        nm = j.get("name")
        d[j.get("id") or p.stem] = (nm, g.get(nm, {}).get("ja", nm))
    return d


_lock = threading.Lock()


def build_prompt(batch, g, cache):
    text = " ".join(m["zh"] for _, m in batch)
    known = {}
    for z, v in cache.items():
        if z.startswith("short:"):
            continue
        ja = v.get("ja") if isinstance(v, dict) else v
        if 1 < len(z) <= 12 and z in text and isinstance(ja, str) and all(z != m["zh"] for _, m in batch):
            known[z] = ja
    terms = {k: v for k, v in PROVISIONAL_JA.items() if k in text}
    terms.update({k: v for k, v in STYLE_JA.items() if k in text})
    off = {k: v["ja"] for k, v in g.items() if len(k) >= 2 and k in text}
    payload = []
    for tid, m in batch:
        it = {"id": tid, "zh": m["zh"], "en": m["en"], "field": m["field"], "ctx": m["ctx"]}
        for k2 in ("op", "ref"):
            if m.get(k2):
                it[k2] = m[k2]
        payload.append(it)
    p = STYLE.replace("{terms}", json.dumps(terms, ensure_ascii=False)).replace("{official}", json.dumps(off, ensure_ascii=False)).replace("{known}", json.dumps(known, ensure_ascii=False))
    if any(m["field"] == "intro" for _, m in batch):
        p += "\n" + INTRO_NOTE
    if any(m["field"] == "short" for _, m in batch):
        p += "\n" + SHORT_NOTE
    return p + "\n\nInput (JSON list; translate 'zh'; 'field' tells what UI slot it is; 'ctx' is where it is used; 'op' is the operator whose text it is):\n" + json.dumps(payload, ensure_ascii=False)


def ph(s):
    return sorted(PH.findall(s.replace("\\n", "\n")))


def bad_reason(zh, ja):
    """译文质检：返回问题说明，没问题返回空串"""
    if not isinstance(ja, str) or not ja.strip():
        return "空译"
    if ph(ja) != ph(zh):
        return "占位符不一致"
    for ch in ja:
        if HAN.match(ch):
            try:
                ch.encode("cp932")
            except UnicodeEncodeError:
                return "简体残留：" + ch
    if zh.count("\n") and not ja.count("\n") and len(zh) <= 24:
        return "短标签少了换行"
    return ""


def cmd_run(a):
    terms, usage = load_glossary()
    u = units()
    cache = json.load(open(CACHE_P, encoding="utf-8")) if CACHE_P.exists() else {}
    opn = opname_ja(terms)
    todo = [uid for uid in u if uid not in cache and not (not uid.startswith("short:") and official_hit(u[uid]["zh"], terms))]
    todo.sort(key=lambda z: len(u[z]["zh"]))
    if a.limit:
        todo = todo[:a.limit]
    print("ja：待翻 %d / 共 %d（已缓存 %d），模型 %s" % (len(todo), len(u), len(cache), TV.MODEL), flush=True)
    usage_p = WORK / "usage_ja.json"
    use = json.load(open(usage_p, encoding="utf-8")) if usage_p.exists() else {"in": 0, "out": 0, "think": 0, "calls": 0}

    def meta(uid):
        e = u[uid]
        fs = e["fields"]
        f = "short" if uid.startswith("short:") else ("intro" if "intro" in fs else (sorted(fs)[0] if fs else "label"))
        m = {"zh": e["zh"], "en": e["en"], "field": f, "ctx": e["ctx"]}
        ctx = e["ctx"]
        if ctx.startswith(("op.", "ult.ops.")):
            oid = ctx.split(".")[2] if ctx.startswith("ult.") else ctx.split(".")[1]
            if oid in opn:
                m["op"] = opn[oid][1]
                if f == "intro":
                    m["ref"] = usage.get(opn[oid][0]) or {}
        return m

    # 两轮：先短（≤ 12 字，名字 / 标签），再长（引用前一轮的译名）
    for phase, sel in (("短", lambda z: len(u[z]["zh"]) <= 12), ("长", lambda z: len(u[z]["zh"]) > 12)):
        ph_todo = [z for z in todo if sel(z)]
        batches, cur, n = [], [], 0
        intro = [z for z in ph_todo if meta(z)["field"] == "intro"]
        for i in range(0, len(intro), 8):
            batches.append(intro[i:i + 8])
        for z in ph_todo:
            if z in intro:
                continue
            cur.append(z); n += len(u[z]["zh"])
            if len(cur) >= 40 or n > 2200:
                batches.append(cur); cur, n = [], 0
        if cur:
            batches.append(cur)
        print("%s：%d 条 %d 批" % (phase, len(ph_todo), len(batches)), flush=True)
        done = [0]

        def work(b):
            batch = [("t%d" % i, meta(z)) for i, z in enumerate(b)]
            with _lock:
                prompt = build_prompt(batch, terms, cache)
            out, um = TV.call(prompt)
            if isinstance(out, list):
                norm = {}
                for x in out:
                    if isinstance(x, dict) and "id" in x:
                        norm[x["id"]] = x if "note" in x else x.get("ja", x.get("translation"))
                    elif isinstance(x, dict):
                        norm.update(x)
                out = norm
            bad = 0
            with _lock:
                for (tid, m), z in zip(batch, b):
                    v = out.get(tid) if isinstance(out, dict) else None
                    ja = v.get("ja") if isinstance(v, dict) else v
                    if not isinstance(ja, str):
                        bad += 1; continue
                    ja = ja.replace("\\n", "\n") if "\\n" not in m["zh"] else ja
                    why = bad_reason(m["zh"], ja)
                    if why and why != "短标签少了换行":
                        bad += 1; continue   # 不进缓存，下次 run 重翻
                    cache[z] = {"ja": ja, "note": v.get("note", "")} if isinstance(v, dict) and v.get("note") else ja
                use["in"] += um.get("promptTokenCount", 0); use["out"] += um.get("candidatesTokenCount", 0)
                use["think"] += um.get("thoughtsTokenCount", 0); use["calls"] += 1
                done[0] += 1
                json.dump(cache, open(CACHE_P, "w", encoding="utf-8"), ensure_ascii=False, indent=0)
                json.dump(use, open(usage_p, "w", encoding="utf-8"), indent=0)
                print("  批 %d/%d：%d 条，弃 %d" % (done[0], len(batches), len(b), bad), flush=True)

        with cf.ThreadPoolExecutor(a.jobs) as ex:
            for f in [ex.submit(work, b) for b in batches]:
                try:
                    f.result()
                except BaseException as e:   # 一批失败不拖垮其余批（SystemExit 也接住），下次 run 补
                    print("  批失败：", type(e).__name__, str(e)[:200], flush=True)
    cost = use["in"] / 1e6 * TV.PRICE_IN + (use["out"] + use["think"]) / 1e6 * TV.PRICE_OUT
    print("累计调用 %d 次，估价 $%.2f" % (use["calls"], cost))


def cmd_qa(a):
    u = units()
    cache = json.load(open(CACHE_P, encoding="utf-8")) if CACHE_P.exists() else {}
    bad = {}
    for uid, v in list(cache.items()):
        ja = v.get("ja") if isinstance(v, dict) else v
        zh = u[uid]["zh"] if uid in u else uid[6:] if uid.startswith("short:") else uid
        why = bad_reason(zh, ja)
        if uid.startswith("short:") and isinstance(ja, str) and len(ja) > max(len(zh) + 1, int(len(zh) * 1.3)):
            why = why or "短版偏长"
        if why:
            bad[uid] = why
    for uid, why in list(bad.items())[:60]:
        print(why, "|", uid[:40].replace("\n", "/"), "|", str(cache[uid])[:60].replace("\n", "/"))
    print("问题 %d 条" % len(bad))
    if a.drop:
        for uid, why in bad.items():
            if why != "短标签少了换行":
                cache.pop(uid, None)
        json.dump(cache, open(CACHE_P, "w", encoding="utf-8"), ensure_ascii=False, indent=0)
        print("已从缓存删除，重跑 run 重翻")


def ja_review():
    p = ROOT / "tools/l10n/review/ja.json"   # 人工改稿：原文（短版带 short: 前缀）→ 日文
    return {k: v for k, v in json.load(open(p, encoding="utf-8")).items() if not k.startswith("_")} if p.exists() else {}


def ja_fix(ja):
    """成批写法修正（只改模型稿常见误用）：「结算」界面义 = リザルト（「決算」是会计用语）；技能里结算伤害 = 清算"""
    if not ja:
        return ja
    for a, b in (("イシャマーラ", "イシャームラ"), ("イシャマラ", "イシャームラ"), ("イーシャムラ", "イシャームラ")):   # 伊莎玛拉：日服官方 イシャームラ
        ja = ja.replace(a, b)
    return ja.replace("決算", "清算" if "{$" in ja else "リザルト")


def cmd_csv(a):
    terms, _ = load_glossary()
    cache = json.load(open(CACHE_P, encoding="utf-8")) if CACHE_P.exists() else {}
    human = ja_review()
    stats = {"官方": 0, "暂定": 0, "人改": 0, "自译": 0, "缺": 0, "非中文": 0}
    for m in MODULES:
        p = ROOT / "game/l10n" / (m + ".csv")
        rows = list(csv.DictReader(open(p, encoding="utf-8")))
        cols = ["keys", "en", "ja", "ko", "_zh", "_source", "_note", "_ja_note", "_ko_note"]   # ko 两列（translate_ko.py 写）原样保留
        for r in rows:
            zh, short = unit_of(r)
            uid = ("short:" + zh) if short else zh
            ja, note = "", ""
            if not zh or not HAN.search(zh):
                ja = r["en"] if r["en"] and not HAN.search(r["en"]) else ""   # 不含汉字的原文（符号 / 英文）：同英文
                note = "无中文"; stats["非中文"] += 1
            elif uid in human:
                ja, note = human[uid], "人改"; stats["人改"] += 1
            elif not short and official_hit(zh, terms):
                ja, src = official_hit(zh, terms)
                tag = "暂定" if src.startswith("暂定") else "官方"
                note = tag + "：" + src; stats[tag] += 1
            elif uid in cache:
                v = cache[uid]
                ja = v.get("ja") if isinstance(v, dict) else v
                note = "自译" + ("；" + v["note"] if isinstance(v, dict) and v.get("note") else "")
                why = bad_reason(zh, ja)
                if why:
                    note += "；" + why
                stats["自译"] += 1
            elif short and uid[6:] in cache:   # 没有短版就用整译
                v = cache[uid[6:]]
                ja = v.get("ja") if isinstance(v, dict) else v
                note = "自译（同整译）"; stats["自译"] += 1
            else:
                stats["缺"] += 1; note = "缺"
            ja = ja_fix(ja)
            r["ja"], r["_ja_note"] = ja, note
        with open(p, "w", encoding="utf-8", newline="") as f:
            w = csv.DictWriter(f, fieldnames=cols, lineterminator="\n")
            w.writeheader()
            for r in rows:
                w.writerow({c: r.get(c, "") for c in cols})
    print(stats)


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    ap = argparse.ArgumentParser()
    sp = ap.add_subparsers(dest="cmd", required=True)
    sp.add_parser("glossary").set_defaults(f=cmd_glossary)
    r = sp.add_parser("run"); r.add_argument("--limit", type=int, default=0); r.add_argument("--jobs", type=int, default=6); r.set_defaults(f=cmd_run)
    q = sp.add_parser("qa"); q.add_argument("--drop", action="store_true"); q.set_defaults(f=cmd_qa)
    sp.add_parser("csv").set_defaults(f=cmd_csv)
    a = ap.parse_args(); a.f(a)


if __name__ == "__main__":
    main()
