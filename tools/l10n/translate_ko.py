"""韩语版（ko）：以已提交的 game/l10n/<模块>.csv 为准，补 ko 列（docs/276 §14；做法同日文 translate_ja.py）。

  python tools/l10n/translate_ko.py glossary            # 韩服官方名表 → build/l10n_work/glossary_ko.json（读 build/l10n_ref/ 的 cn_ / ko_ 原表）
  python tools/l10n/translate_ko.py run [--limit N]      # Vertex Gemini 翻译（缓存 build/l10n_work/cache_ko.json，断了重跑只补缺）
  python tools/l10n/translate_ko.py qa [--drop]          # 查占位符 / 汉字假名残留 / 没有韩文 / 空译，--drop 从缓存删掉（再 run 重翻）
  python tools/l10n/translate_ko.py csv                  # 写回各 CSV 的 ko 列与 _ko_note 列

口径：
- 原文（中文）是源语言；英文列只作意思参照。官方韩文（ArknightsGameData_YoStar ko_KR 原表能整串查到的名字、藏品、事件标题、招聘合同）不送模型。
- 查不到官方名的名字（本作自拟的普攻 / 成长节点 / 招式 / 自创词）由模型意译，_ko_note 记「自译」。
- 键、英文列、日文列不动；translate_vertex.py csv / translate_ja.py csv 重写 CSV 时按键保留 ko / _ko_note 两列。
鉴权同 translate_vertex.py（gcloud 令牌）。只用标准库。
"""
import argparse, concurrent.futures as cf, csv, json, re, sys, threading
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import translate_vertex as TV  # noqa: E402

ROOT = TV.ROOT
WORK = TV.WORK
REF = ROOT / "build/l10n_ref"
MODULES = ["ops", "enemies", "ui", "relics", "events", "meta", "run", "extra"]
CACHE_P = WORK / "cache_ko.json"
PH = re.compile(r"\{\$[^}]*\}|%[-+0-9.]*[dsf]|%%|\{[a-z_0-9]+\}")
HAN = re.compile(r"[一-鿿]")
KANA = re.compile(r"[ぁ-ヿ]")
HANGUL = re.compile(r"[가-힣]")
COLS = ["keys", "en", "ja", "ko", "_zh", "_source", "_note", "_ja_note", "_ko_note"]

# 本作自创词 / 系统词的韩文（官方表能查到的写在注释里；查不到的为自译）。整串命中直接用
PROVISIONAL_KO = {
    "队长": "리더", "终结技": "필살기", "连携": "연계", "噤声": "침묵",
    "灯火": "등불", "灯油": "등유", "照亮范围": "조명 범위", "照亮": "조명",            # 등불：rogue_2 官方
    "引航灯标": "길잡이 등표", "灯标": "등표", "黑潮": "흑조", "安全区": "안전 구역",
    "通明": "밝음", "摇曳": "흔들림", "暗淡": "희미함", "寂灭": "꺼짐",                # 灯火四档：rogue_2 官方（sanCheck.sanRanges）
    "光域": "여우불 영역", "灯塔光圈": "등대의 빛무리", "灯柱": "빛기둥", "光圈": "빛무리",
    "随行": "동행", "突击": "돌격", "集火": "집중 공격",
    "指挥": "지휘", "坚守": "사수", "鼓舞": "격려", "祈愿": "기원",
    "海嗣祭坛": "시본 제단", "抉择": "선택", "生机细胞": "생체 세포",                 # 생체 세포：rogue_2 官方
    "精英一": "정예화 1", "精英二": "정예화 2", "精一": "정예화 1", "精二": "정예화 2", "精英化": "정예화",
    "技力": "SP", "技力回复": "SP 회복", "探索": "탐험", "一次探索": "1회 탐험",
    "中期 Boss": "중간 보스", "最终 Boss": "최종 보스", "精英": "엘리트",
    "认知塑造": "인지 형성", "藏品": "소장품", "收藏品": "소장품", "源石锭": "오리지늄각뿔",   # 后三条官方
}
# 只进提示词的固定写法（多数是韩服官方用语）
STYLE_KO = {
    "物理": "물리", "法术": "마법", "法术伤害": "마법 대미지", "物理伤害": "물리 대미지", "真实伤害": "트루 대미지",
    "最大生命": "최대 HP", "当前生命": "현재 HP", "生命": "HP", "攻击力": "공격력", "防御力": "방어력", "法术抗性": "마법 저항력",
    "攻击速度": "공격 속도", "攻速": "공격 속도", "移动速度": "이동 속도", "所需技力": "필요 SP", "Boss 除外": "보스 제외",
    "博士": "박사", "干员": "오퍼레이터", "编队": "편성", "罗德岛": "로도스 아일랜드", "海嗣": "시본", "恐鱼": "시테러",
    "深海猎人": "어비설 헌터", "伊比利亚": "이베리아", "阿戈尔": "에기르", "审判庭": "재판소", "审判官": "재판관",
    "源石技艺": "오리지늄 아츠", "源石": "오리지늄", "招募": "모집", "召唤物": "소환물",
    "侵蚀": "침식", "停顿": "정지", "失重": "무중력", "悬浮": "공중 부양", "眩晕": "기절", "晕眩": "기절", "束缚": "속박",
    "冻结": "빙결", "寒冷": "냉기", "减速": "감속", "神经损伤": "신경 손상", "侵蚀损伤": "침식 손상", "击退": "밀어내기", "拉拽": "끌어당기기",
    "护盾": "실드", "屏障": "보호막", "脆弱": "취약", "大群": "위매니", "溟痕": "명흔", "大静谧": "고요함",
    "集成战略": "통합 전략", "水月与深蓝之树": "미즈키 & 카이룰라 아버", "深蓝之树": "카이룰라 아버",
    "诡意行商": "교활한 상인", "不期而遇": "우연한 만남", "安全屋": "안전가옥", "猎潮的骑士": "파도 사냥의 기사",
    "先锋": "뱅가드", "近卫": "가드", "重装": "디펜더", "狙击": "스나이퍼", "术师": "캐스터", "医疗": "메딕", "辅助": "서포터", "特种": "스페셜리스트",
    "希望": "희망", "精英减半": "엘리트는 절반",
}

STYLE = """You are translating a Chinese fan game (an Arknights squad survivor roguelike set in the Integrated Strategies #2 'Mizuki & Caerula Arbor' setting) into Korean.
Translate from the Chinese ('zh'). The English ('en') is an existing translation given only to help you understand the meaning; do not translate from it and do not copy its wording.
Write like the official Korean Arknights client (명일방주, Yostar KR): restrained, short, information-dense. UI reads like a Rhodes Island combat terminal, operator files like personnel records, effect text like the official skill descriptions.
Rules:
- Effect / skill / talent text: official KR skill-description syntax, terse noun-ending style, e.g. 「공격력 +50%, 공격 속도 +20」「3초 동안 기절」「최대 HP의 10% 회복」「(보스 제외)」. No 합니다/해요 in effect text. Numbers and units half-width; seconds as 「3초」.
- UI labels and buttons: short noun phrases, never a sentence. Messages / hints: polite 하세요/합니다 only where the Chinese addresses the player.
- Lore / operator files: 한다체 (plain written style), factual. Enemy files: present-tense observation, short sentences.
- Word spacing (띄어쓰기) MUST follow standard Korean orthography: the game breaks lines only at spaces, so never glue several words together and never put a space inside a word.
- Punctuation: half-width , . : ! ? ( ) ; Chinese quotes 「」 or “” around names become single quotes '이름'; 【】 become [ ]. Middle dot · between names stays ·. No full-width punctuation （，。：）. Keep "×1.5", "+25%", "10:00", "ATK", "DPS", "Lv." as is.
- Never output Chinese characters (Hanja) or Japanese kana. Every output must be natural Korean in Hangul (Latin letters only for names like Mon3tr, PRTS, Boss abbreviations already Latin).
- Pronouns: avoid 그녀/그 unless needed; prefer the name or omit the subject.
- Placeholders MUST be copied exactly, same count and same spelling: {$...} (code fills numbers in; never translate or edit inside the braces), %d, %s, %.1f, %%, {name}-style names, and line breaks (\\n). Put the unit right after a placeholder like the Chinese does ("{$dur} 秒" -> "{$dur}초"). Keep the line count when the Chinese has line breaks in a short label.
- If the Chinese uses the separator "｜" (label｜text), keep "｜" in the same place.
- Names already translated (MUST reuse exactly when the Chinese name appears, e.g. inside 「」): {known}
- Fixed terms (MUST use exactly): {terms}
- Official Korean Arknights names / texts that appear in this batch (MUST use exactly): {official}
Output: a JSON object mapping each input id to the Korean string. For ids marked field "intro" output instead an object {"ko": Korean, "note": "Chinese note explaining any pun/meme and how the Korean keeps it, or empty"}. No extra text."""

INTRO_NOTE = ("Items with field 'intro' are recruit-card blurbs written by the game's author with jokes and memes. Keep the original meaning and the joke; "
              "do not tone it down. If a line quotes or riffs on official Arknights text, reuse the official Korean given in 'ref'.")

SHORT_NOTE = ("Items with field 'short' are fixed-width chips / HUD labels: the Korean must be at most as many syllables as the Chinese has characters, "
              "plus one (use the official client's short forms, e.g. 공격 속도 → 공속 only if it does not fit).")


def L(name):
    return json.load(open(REF / name, encoding="utf-8"))


def glossary():
    """zh → (ko, 来源)：干员 / 技能 / 天赋 / 敌人 / 藏品 / 术语 / 分支 / 事件 / 结局 / 招聘合同。全部来自 ko_KR 原表"""
    g = {}
    def put(zh, ko, src):
        if zh and ko and zh.strip() not in g:
            g[zh.strip()] = (ko.strip(), src)
    cc, kc = L("cn_character_table.json"), L("ko_character_table.json")
    cs, ks = L("cn_skill_table.json"), L("ko_skill_table.json")
    ce, ke = L("cn_enemy_handbook_table.json")["enemyData"], L("ko_enemy_handbook_table.json")["enemyData"]
    cr, kr = L("cn_roguelike_topic_table.json"), L("ko_roguelike_topic_table.json")
    ck, kk = L("cn_gamedata_const.json")["termDescriptionDict"], L("ko_gamedata_const.json")["termDescriptionDict"]
    cu, ku = L("cn_uniequip_table.json").get("subProfDict", {}), L("ko_uniequip_table.json").get("subProfDict", {})
    ours = {json.load(open(p, encoding="utf-8")).get("name") for p in (ROOT / "game/data/characters").glob("*.json")}
    usage = {}
    for cid, c in cc.items():
        if not cid.startswith("char_") or cid not in kc:
            continue
        e = kc[cid]
        if c["name"] in ours:
            put(c["name"], e["name"], "character_table." + cid)
            for f in ("itemUsage", "itemDesc"):
                if c.get(f) and e.get(f):
                    put(c[f], e[f], "character_table.%s.%s" % (cid, f))
            usage[c["name"]] = {"usage_zh": c.get("itemUsage"), "usage_ko": e.get("itemUsage"), "desc_zh": c.get("itemDesc"), "desc_ko": e.get("itemDesc")}
            for s in c.get("skills") or []:
                sid = s.get("skillId")
                if sid in cs and sid in ks:
                    put(cs[sid]["levels"][0]["name"], ks[sid]["levels"][0]["name"], "skill_table." + sid)
            for ti, t in enumerate(c.get("talents") or []):
                try:
                    put(t["candidates"][-1]["name"], e["talents"][ti]["candidates"][-1]["name"], "character_table.%s.talents[%d]" % (cid, ti))
                except (KeyError, IndexError, TypeError):
                    pass
    for sid in ("skchr_texas2_3", "skcom_charge_cost[3]"):
        if sid in cs and sid in ks:
            put(cs[sid]["levels"][0]["name"], ks[sid]["levels"][0]["name"], "skill_table." + sid)
    for eid, v in ce.items():
        if eid in ke:
            put(v.get("name"), ke[eid].get("name"), "enemy_handbook_table." + eid)
            put((v.get("name") or "").strip("“”\""), (ke[eid].get("name") or "").strip("'\"“”"), "enemy_handbook_table." + eid)
    r2c, r2k = cr["details"]["rogue_2"], kr["details"]["rogue_2"]
    for iid, it in r2c["items"].items():
        e = r2k["items"].get(iid, {})
        for f in ("name", "usage", "description"):
            if it.get(f) and e.get(f):
                put(it[f], e[f], "roguelike_topic_table.rogue_2.items.%s.%s" % (iid, f))
    for sec in ("choiceScenes", "choices"):
        for k, v in r2c.get(sec, {}).items():
            e = r2k.get(sec, {}).get(k, {})
            for f in ("title", "description"):
                if v.get(f) and e.get(f):
                    put(v[f], e[f], "roguelike_topic_table.rogue_2.%s.%s.%s" % (sec, k, f))
    for k, v in r2c.get("nodeTypeData", {}).items():
        e = r2k.get("nodeTypeData", {}).get(k, {})
        if v.get("name") and e.get("name"):
            put(v["name"], e["name"], "roguelike_topic_table.rogue_2.nodeTypeData.%s" % k)
    for k, v in ck.items():
        if k in kk:
            put(v.get("termName"), kk[k].get("termName"), "gamedata_const.termDescriptionDict." + k)
    for k, v in cu.items():
        if k in ku:
            put(v.get("subProfessionName"), ku[k].get("subProfessionName"), "uniequip_table.subProfDict." + k)
    E = "roguelike_topic_table.rogue_2.archiveComp.endbook"
    for zh, ko in [("平凡即是喜乐", "소중한 일상"), ("静谧时代", "침묵의 시대"), ("息潮的代价", "평화의 대가"), ("如星空般深蓝", "스텔라 카이룰라")]:
        g[zh] = (ko, E)
    g["猎潮的骑士"] = ("파도 사냥의 기사", "roguelike_topic_table.rogue_2.items.rogue_2_relic_grace_83.usage（[파도 사냥의 기사]）")
    g["水月与深蓝之树"] = ("미즈키 & 카이룰라 아버", "roguelike_topic_table.topics.rogue_2.name")
    for zh, ko in {"先锋": "뱅가드", "近卫": "가드", "重装": "디펜더", "狙击": "스나이퍼", "术师": "캐스터",
                   "医疗": "메딕", "辅助": "서포터", "特种": "스페셜리스트"}.items():
        g[zh] = (ko, "character_table profession（韩服职业名）")
    return g, usage


def load_glossary():
    p = WORK / "glossary_ko.json"
    if not p.exists():
        sys.exit("先跑 glossary")
    d = json.load(open(p, encoding="utf-8"))
    return d["terms"], d["usage"]


def cmd_glossary(a):
    g, usage = glossary()
    WORK.mkdir(parents=True, exist_ok=True)
    json.dump({"terms": {k: {"ko": v[0], "src": v[1]} for k, v in g.items()}, "usage": usage},
              open(WORK / "glossary_ko.json", "w", encoding="utf-8"), ensure_ascii=False, indent=0)
    print("韩服官方表", len(g), "条 →", WORK / "glossary_ko.json")


def read_rows():
    out = []
    for m in MODULES:
        p = ROOT / "game/l10n" / (m + ".csv")
        for r in csv.DictReader(open(p, encoding="utf-8")):
            out.append((m, r))
    return out


def unit_of(r):
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
    if s in PROVISIONAL_KO:
        return PROVISIONAL_KO[s], "暂定（docs/276 §14）"
    if s in g:
        return g[s]["ko"], g[s]["src"]
    core = s.strip("“”\"「」")
    if core != s and core in g:
        return "'%s'" % g[core]["ko"].strip("'\""), g[core]["src"]
    return None


def opname_ko(g):
    d = {}
    for p in (ROOT / "game/data/characters").glob("*.json"):
        j = json.load(open(p, encoding="utf-8"))
        nm = j.get("name")
        d[j.get("id") or p.stem] = (nm, g.get(nm, {}).get("ko", nm))
    return d


_lock = threading.Lock()


def build_prompt(batch, g, cache):
    text = " ".join(m["zh"] for _, m in batch)
    known = {}
    for z, v in cache.items():
        if z.startswith("short:"):
            continue
        ko = v.get("ko") if isinstance(v, dict) else v
        if 1 < len(z) <= 12 and z in text and isinstance(ko, str) and all(z != m["zh"] for _, m in batch):
            known[z] = ko
    terms = {k: v for k, v in PROVISIONAL_KO.items() if k in text}
    terms.update({k: v for k, v in STYLE_KO.items() if k in text})
    off = {k: v["ko"] for k, v in g.items() if len(k) >= 2 and k in text}
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


def bad_reason(zh, ko):
    """译文质检：返回问题说明，没问题返回空串"""
    if not isinstance(ko, str) or not ko.strip():
        return "空译"
    if ph(ko) != ph(zh):
        return "占位符不一致"
    m = HAN.search(ko) or KANA.search(ko)
    if m:
        return "汉字 / 假名残留：" + m.group(0)
    if not HANGUL.search(ko) and len(HAN.findall(zh)) >= 3:
        return "没有韩文"
    for ch in "，。：；（）！？":
        if ch in ko:
            return "全角标点：" + ch
    if zh.count("\n") and not ko.count("\n") and len(zh) <= 24:
        return "短标签少了换行"
    if "｜" in zh and "｜" not in ko:
        return "少了｜"
    return ""


def cmd_run(a):
    terms, usage = load_glossary()
    u = units()
    cache = json.load(open(CACHE_P, encoding="utf-8")) if CACHE_P.exists() else {}
    opn = opname_ko(terms)
    todo = [uid for uid in u if uid not in cache and not (not uid.startswith("short:") and official_hit(u[uid]["zh"], terms))]
    todo.sort(key=lambda z: len(u[z]["zh"]))
    if a.limit:
        todo = todo[:a.limit]
    print("ko：待翻 %d / 共 %d（已缓存 %d），模型 %s" % (len(todo), len(u), len(cache), TV.MODEL), flush=True)
    usage_p = WORK / "usage_ko.json"
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
                        norm[x["id"]] = x if "note" in x else x.get("ko", x.get("translation"))
                    elif isinstance(x, dict):
                        norm.update(x)
                out = norm
            bad = 0
            with _lock:
                for (tid, m), z in zip(batch, b):
                    v = out.get(tid) if isinstance(out, dict) else None
                    ko = v.get("ko") if isinstance(v, dict) else v
                    if not isinstance(ko, str):
                        bad += 1; continue
                    ko = ko.replace("\\n", "\n") if "\\n" not in m["zh"] else ko
                    why = bad_reason(m["zh"], ko)
                    if why and why != "短标签少了换行":
                        bad += 1; continue   # 不进缓存，下次 run 重翻
                    cache[z] = {"ko": ko, "note": v.get("note", "")} if isinstance(v, dict) and v.get("note") else ko
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
                except BaseException as e:   # 一批失败不拖垮其余批，下次 run 补
                    print("  批失败：", type(e).__name__, str(e)[:200], flush=True)
    cost = use["in"] / 1e6 * TV.PRICE_IN + (use["out"] + use["think"]) / 1e6 * TV.PRICE_OUT
    print("累计调用 %d 次，估价 $%.2f" % (use["calls"], cost))


def cmd_qa(a):
    u = units()
    cache = json.load(open(CACHE_P, encoding="utf-8")) if CACHE_P.exists() else {}
    bad = {}
    for uid, v in list(cache.items()):
        ko = v.get("ko") if isinstance(v, dict) else v
        zh = u[uid]["zh"] if uid in u else uid[6:] if uid.startswith("short:") else uid
        why = bad_reason(zh, ko)
        if uid.startswith("short:") and isinstance(ko, str) and len(ko.replace(" ", "")) > max(len(zh) + 1, int(len(zh) * 1.4)):
            why = why or "短版偏长"
        if why:
            bad[uid] = why
    for uid, why in list(bad.items())[:60]:
        print(why, "|", uid[:40].replace("\n", "/"), "|", str(cache[uid])[:60].replace("\n", "/"))
    print("问题 %d 条" % len(bad))
    if a.drop:
        for uid, why in bad.items():
            if why not in ("短标签少了换行", "短版偏长"):
                cache.pop(uid, None)
        json.dump(cache, open(CACHE_P, "w", encoding="utf-8"), ensure_ascii=False, indent=0)
        print("已从缓存删除，重跑 run 重翻")


def ko_review():
    p = ROOT / "tools/l10n/review/ko.json"   # 人工改稿：原文（短版带 short: 前缀）→ 韩文
    return {k: v for k, v in json.load(open(p, encoding="utf-8")).items() if not k.startswith("_")} if p.exists() else {}


def ko_fix(ko):
    """成批写法修正：全角标点换半角（模型偶尔漏）"""
    if not ko:
        return ko
    for a, b in (("，", ", "), ("：", ": "), ("；", "; "), ("（", " ("), ("）", ")"), ("！", "!"), ("？", "?")):
        ko = ko.replace(a, b)
    return ko.replace("  (", " (").replace("( ", "(")


def write_csv_cols(p, rows):
    with open(p, "w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=COLS, lineterminator="\n")
        w.writeheader()
        for r in rows:
            w.writerow({c: r.get(c, "") for c in COLS})


def cmd_csv(a):
    terms, _ = load_glossary()
    cache = json.load(open(CACHE_P, encoding="utf-8")) if CACHE_P.exists() else {}
    human = ko_review()
    stats = {"官方": 0, "暂定": 0, "人改": 0, "自译": 0, "缺": 0, "非中文": 0}
    for m in MODULES:
        p = ROOT / "game/l10n" / (m + ".csv")
        rows = list(csv.DictReader(open(p, encoding="utf-8")))
        for r in rows:
            zh, short = unit_of(r)
            uid = ("short:" + zh) if short else zh
            ko, note = "", ""
            if not zh or not HAN.search(zh):
                ko = r["en"] if r["en"] and not HAN.search(r["en"]) else ""
                note = "无中文"; stats["非中文"] += 1
            elif uid in human:
                ko, note = human[uid], "人改"; stats["人改"] += 1
            elif not short and official_hit(zh, terms):
                ko, src = official_hit(zh, terms)
                tag = "暂定" if src.startswith("暂定") else "官方"
                note = tag + "：" + src; stats[tag] += 1
            elif uid in cache:
                v = cache[uid]
                ko = v.get("ko") if isinstance(v, dict) else v
                note = "自译" + ("；" + v["note"] if isinstance(v, dict) and v.get("note") else "")
                why = bad_reason(zh, ko)
                if why:
                    note += "；" + why
                stats["自译"] += 1
            elif short and uid[6:] in cache:
                v = cache[uid[6:]]
                ko = v.get("ko") if isinstance(v, dict) else v
                note = "自译（同整译）"; stats["自译"] += 1
            else:
                stats["缺"] += 1; note = "缺"
            if short and not ko and official_hit(zh, terms):   # 短版没有缓存：用官方整名
                ko = official_hit(zh, terms)[0]; note = "官方（同整名）"
            r["ko"], r["_ko_note"] = ko_fix(ko), note
        write_csv_cols(p, rows)
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
