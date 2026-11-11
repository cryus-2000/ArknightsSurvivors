"""英文初稿：Vertex AI（Gemini）批量翻译 + 官方名强制替换 + 写 CSV（docs/276）。

  python tools/l10n/extract.py                                  # 先抽取
  python tools/l10n/translate_vertex.py run ops --limit 10      # 试跑 10 条，打印用量与估价
  python tools/l10n/translate_vertex.py run ops                 # 全量（缓存在 build/l10n_work/cache_<模块>.json，断了重跑只补缺）
  python tools/l10n/translate_vertex.py csv ops                 # 合成 game/l10n/<模块>.csv（key,zh,en,source,note）

鉴权同 tools/imagegen/pixgen.py：gcloud 当前项目 + `gcloud auth print-access-token`，不用 API key。只用标准库。
官方英文（en_US 原表能查到的名字、招聘合同原文）不送模型；模型输出里官方名的写法再按术语表核一遍。
"""
import argparse, json, os, re, sys, time, urllib.request, urllib.error
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import extract as X  # noqa: E402

ROOT, WORK = X.ROOT, X.WORK
MODEL = os.environ.get("L10N_MODEL", "gemini-3.1-pro-preview")
VERTEX = "https://aiplatform.googleapis.com/v1/projects/{p}/locations/global/publishers/google/models/{m}:generateContent"
# 估价（美元 / 百万 token）。Vertex 上 Gemini 3 Pro 预览档 ≤200k 上下文：输入 2、输出（含思考）12。以 Vertex 定价页为准，可用环境变量改
PRICE_IN = float(os.environ.get("L10N_PRICE_IN", "2.0"))
PRICE_OUT = float(os.environ.get("L10N_PRICE_OUT", "12.0"))
BATCH = 30
PH = re.compile(r"\{\$[^}]*\}|%[-+0-9.]*[dsf]|\{[a-z_]+\}|\\n|\n")

STYLE = """You are translating a Chinese fan game (an Arknights squad survivor roguelike set in the Integrated Strategies #2 'Mizuki & Caerula Arbor' setting) into English.
Write like the official Arknights Global (en_US) client: short, restrained, information-dense. UI reads like a Rhodes Island combat terminal, operator files like HR records, effect text like a technical manual.
Rules:
- Effect / skill / talent text: official skill-description syntax. Present tense, subject may be omitted, numbers first then conditions, exceptions as "(Bosses excepted)". Capitalize status keywords like the official client: Stun, Bind, Freeze, Fragile, Weightless, Nervous Impairment, Corrosion Damage, Arts damage, Physical damage, True damage.
- Abbreviations as in the official client: ATK, DEF, RES, HP, Max HP, SP, ASPD. Seconds as "3s" in effect text. Keep "×1.5", "+25%", "10:00" as is.
- Never use: epic, unleash, ultimate power, journey, adventure, embark, massive, powerful, greatly. No exclamation marks except inside quoted dialogue. No slogans, no closing moral sentences, no rhetorical "not X but Y". Em dashes only inside the fixed banner format "Event — instruction".
- "you" = the Doctor/player. Generic operator (relics, generic rules) = "the Operator"/"they". But inside one operator's own text (item has "op"), 她/他/自身 refers to THAT operator: use "she"/"he"/"herself"/"himself" (male operators: Mizuki, Logos, Lumen, Ulpianus; all others female; Mon3tr is "it").
- Game statuses (Title Case, never paraphrase): 停顿 = Halt (stops movement briefly; NOT Slow), 减速 = Slow, 悬浮 = Levitate, 失重 = Weightless, 眩晕 = Stun, 束缚 = Bind, 冻结 = Freeze, 照亮 = Illuminated. Ordinary words like "move", "attack", "movement speed" stay lowercase.
- Operator lore/profile text: third person, past tense for history, factual. Enemy/Boss files (lore of enemies, intro.line, intro.sub, gallery, desc): PRESENT tense like the official enemy handbook, field observation, short sentences, end on a concrete image.
- 大群 = "We Many" (no article: "the will of We Many"). 蓄力 as an action = "charges up" (the status keyword Charged only when it is a named status). 一次探索 / 每次探索 = "a run" / "per run".
- Boss subtitle format "最终 · X" -> "Final · X" (keep the middle dot).
- Names already translated (MUST reuse exactly when the Chinese name appears, e.g. inside 「」): {known}
- American spelling (Armor, Defense, Color).
- Chinese 「」 or “” quotes become single quotes 'like this' (as the official client does for names).
- Placeholders MUST be copied exactly and kept the same count: {$...} (code fills numbers in, e.g. "{$s1_mult}" or "{$talent_mult*100-100}"), %d, %s, %.1f, {name}, and line breaks \\n. Never translate or reformat text inside {$...}. Put the unit right after a placeholder like the Chinese does ("{$dur} 秒" -> "{$dur}s").
- Short labels (field = name, tags, kind, range, trigger, status, banner, class, sub, weak, src, cleanse, profile, profile_key, faction, atk, gd short strings): keep them short, at most about 2x the Chinese character count in Latin letters; Title Case for names, sentence case for descriptions.
- Fixed terms (MUST use exactly): {terms}
- Official Arknights names that appear in this batch (MUST use exactly): {official}
Output: a JSON object mapping each input id to the English string. For ids marked "intro" output instead an object {"en": best version, "alt": a second, different version, "hard": true/false, "note": "Chinese note explaining any pun/meme/wordplay and how each version keeps it, or empty"}. No extra text."""

INTRO_NOTE = ("These recruit-card blurbs were written by the game's author and contain jokes and memes. Keep the original meaning and the joke. "
              "If a line quotes or riffs on official Arknights text, reuse the official English given in 'ref'.")


def _gcloud(*a):
    import shutil, subprocess
    g = shutil.which("gcloud") or shutil.which("gcloud.cmd")
    if not g:
        sys.exit("找不到 gcloud")
    r = subprocess.run([g, *a], capture_output=True, text=True)
    if r.returncode != 0 or not r.stdout.strip():
        sys.exit("gcloud %s 失败：%s" % (a[0], r.stderr.strip()[:300]))
    return r.stdout.strip()


_tok = {"t": None, "at": 0}


def _token():
    if not _tok["t"] or time.time() - _tok["at"] > 1800:
        _tok["t"], _tok["at"] = _gcloud("auth", "print-access-token"), time.time()
    return _tok["t"]


def call(prompt, model=MODEL, tries=6):
    url = VERTEX.format(p=_gcloud("config", "get-value", "project"), m=model)
    body = {"contents": [{"role": "user", "parts": [{"text": prompt}]}],
            "generationConfig": {"responseMimeType": "application/json", "temperature": 0.3}}
    delay = 4.0
    for k in range(tries):
        req = urllib.request.Request(url, data=json.dumps(body).encode(), headers={"Content-Type": "application/json", "Authorization": "Bearer " + _token()})
        try:
            with urllib.request.urlopen(req, timeout=300) as r:
                res = json.load(r)
            txt = "".join(p.get("text", "") for c in res.get("candidates", []) for p in c.get("content", {}).get("parts", []) if not p.get("thought"))
            return json.loads(txt), res.get("usageMetadata", {})
        except urllib.error.HTTPError as e:
            msg = e.read().decode(errors="replace")[:300]
            if e.code in (401, 429, 500, 502, 503, 504):
                print("  HTTP %d，%.0f 秒后重试（%d/%d）" % (e.code, delay, k + 1, tries))
                if e.code == 401:   # 令牌过期 / 偶发无效：重取
                    _tok["t"] = None
                time.sleep(delay); delay *= 2
                continue
            raise SystemExit("HTTP %d: %s" % (e.code, msg))
        except (json.JSONDecodeError, urllib.error.URLError, TimeoutError) as e:
            print("  返回不可解析 / 网络错误（%s），重试" % type(e).__name__)
            time.sleep(delay); delay *= 2
    raise SystemExit("重试用尽")


def load(module):
    items = json.load(open(WORK / (module + ".items.json"), encoding="utf-8"))
    gl = json.load(open(WORK / "glossary.json", encoding="utf-8"))
    return items, gl


def ph(s):
    return sorted(PH.findall(s))


def units(module):
    """去重后的待翻单元：zh → {field（取最「短标签」的那个）, keys}"""
    items, gl = load(module)
    u = {}
    for it in items:
        if "official" in it:
            continue
        e = u.setdefault(it["zh"], {"fields": set(), "keys": []})
        e["fields"].add(it["field"]); e["keys"].append(it["key"])
    return u, gl, items


def official_refs(module):
    """招募卡简介用：每名干员的官方 itemUsage / itemDesc 英文，给模型作 ref"""
    cc, ec = X.L("cn_character_table.json"), X.L("en_character_table.json")
    by_name = {c["name"]: cid for cid, c in cc.items() if cid.startswith("char_")}
    refs = {}
    for p in (ROOT / "game/data/characters").glob("*.json"):
        d = json.load(open(p, encoding="utf-8"))
        cid = by_name.get(d.get("name"))
        if cid and cid in ec:
            refs[d.get("id") or p.stem] = {"usage": ec[cid].get("itemUsage"), "desc": ec[cid].get("itemDesc"),
                                          "usage_zh": cc[cid].get("itemUsage"), "desc_zh": cc[cid].get("itemDesc")}
    return refs


def build_prompt(batch, gl, cache=None):
    text = " ".join(z for z, _ in batch)
    known = {}
    for z, v in (cache or {}).items():
        en = v.get("en") if isinstance(v, dict) else v
        if len(z) <= 10 and z in text and isinstance(en, str) and all(z != b for b, _ in batch):
            known[z] = en
    terms = {k: v for k, v in X.PROVISIONAL.items() if k in text}
    terms.update({k: v for k, v in X.STYLE_TERMS.items() if k in text})
    off = {k: v["en"] for k, v in gl.items() if len(k) >= 2 and k in text}
    payload = []
    for zh, meta in batch:
        payload.append({k: v for k, v in meta.items() if v})
        payload[-1]["zh"] = zh
    p = STYLE.replace("{terms}", json.dumps(terms, ensure_ascii=False)).replace("{official}", json.dumps(off, ensure_ascii=False)).replace("{known}", json.dumps(known, ensure_ascii=False))
    if any(m.get("field") == "intro" for _, m in batch):
        p += "\n" + INTRO_NOTE
    return p + "\n\nInput (JSON list; translate 'zh'; 'field' tells what UI slot it is; 'ctx' is where it is used):\n" + json.dumps(payload, ensure_ascii=False)


def _opnames():
    d = {}
    for p in (ROOT / "game/data/characters").glob("*.json"):
        j = json.load(open(p, encoding="utf-8"))
        d[j.get("id") or p.stem] = (j.get("en") or p.stem).title()
    return d


OPN = {}


def cmd_run(a):
    OPN.update(_opnames())
    u, gl, items = units(a.module)
    cache_p = WORK / ("cache_%s.json" % a.module)
    cache = json.load(open(cache_p, encoding="utf-8")) if cache_p.exists() else {}
    refs = official_refs(a.module)
    todo = sorted((z for z in u if z not in cache), key=len)   # 短名先翻，长文本引用时有现成译名
    if a.limit:
        todo = todo[:a.limit]
    print("%s：待翻 %d / 共 %d（已缓存 %d），模型 %s" % (a.module, len(todo), len(u), len(cache), MODEL))
    usage_p = WORK / ("usage_%s.json" % a.module)
    usage = json.load(open(usage_p, encoding="utf-8")) if usage_p.exists() else {"in": 0, "out": 0, "think": 0, "calls": 0, "zh_chars": 0}
    # 简介单独成批（要两个候选），长文本（档案）小批
    intro = [z for z in todo if "intro" in u[z]["fields"]]
    rest = [z for z in todo if z not in intro]
    batches = [intro[i:i + 10] for i in range(0, len(intro), 10)]
    cur, n = [], 0
    for z in rest:
        cur.append(z); n += len(z)
        if len(cur) >= BATCH or n > 1800:
            batches.append(cur); cur, n = [], 0
    if cur:
        batches.append(cur)
    for bi, b in enumerate(batches):
        ids = {}
        batch = []
        for i, z in enumerate(b):
            meta = u[z]
            fid = "intro" if "intro" in meta["fields"] else sorted(meta["fields"])[0]
            ctx = meta["keys"][0]
            m = {"id": "t%d" % i, "field": fid, "ctx": ctx}
            if ctx.startswith(("op.", "ult.ops.")):
                oid = ctx.split(".")[2] if ctx.startswith("ult.") else ctx.split(".")[1]
                m["op"] = OPN.get(oid, oid)
            if fid == "intro":
                oid = ctx.split(".")[1]
                r = refs.get(oid) or {}
                m["ref"] = {"official_usage_zh": r.get("usage_zh"), "official_usage_en": r.get("usage"), "official_desc_zh": r.get("desc_zh"), "official_desc_en": r.get("desc")}
            ids["t%d" % i] = z
            batch.append((z, m))
        out, um = call(build_prompt(batch, gl, cache))
        usage["in"] += um.get("promptTokenCount", 0); usage["out"] += um.get("candidatesTokenCount", 0)
        usage["think"] += um.get("thoughtsTokenCount", 0); usage["calls"] += 1
        usage["zh_chars"] += sum(len(X.CJK.findall(z)) for z in b)
        if isinstance(out, list):   # 偶尔回成 [{"id": .., "en": ..}] 或 [{"t0": ..}, ..]
            norm = {}
            for x in out:
                if isinstance(x, dict) and "id" in x:
                    norm[x["id"]] = x if "alt" in x else x.get("en", x.get("translation"))
                elif isinstance(x, dict):
                    norm.update(x)
            out = norm
        bad = 0
        for tid, z in ids.items():
            v = out.get(tid)
            if v is None:
                bad += 1; continue
            en = v.get("en") if isinstance(v, dict) else v
            if not isinstance(en, str):
                bad += 1; continue
            if ph(en.replace("\\n", "\n")) != ph(z) and ph(en) != ph(z):
                v = {"en": en, "note": "占位符不一致"} if not isinstance(v, dict) else dict(v, note=(v.get("note") or "") + "；占位符不一致")
            cache[z] = v
        json.dump(cache, open(cache_p, "w", encoding="utf-8"), ensure_ascii=False, indent=0)
        json.dump(usage, open(usage_p, "w", encoding="utf-8"), indent=0)
        print("  批 %d/%d：%d 条，缺 %d；累计 in %d out %d think %d" % (bi + 1, len(batches), len(b), bad, usage["in"], usage["out"], usage["think"]))
    cost = usage["in"] / 1e6 * PRICE_IN + (usage["out"] + usage["think"]) / 1e6 * PRICE_OUT
    print("累计调用 %d 次，中文 %d 字，估价 $%.3f（输入 $%.1f / 输出含思考 $%.1f 每百万 token）" % (usage["calls"], usage["zh_chars"], cost, PRICE_IN, PRICE_OUT))
    if usage["zh_chars"]:
        tot = sum(len(X.CJK.findall(z)) for z in u)
        print("按字数外推本模块全量：约 $%.2f（共 %d 字）" % (cost / usage["zh_chars"] * tot, tot))


SHORT = {"name", "tags", "kind", "range", "trigger", "status", "banner", "class", "sub", "weak", "src", "cleanse", "profile", "profile_key", "faction", "atk", "s", "label", "branch", "line"}
CHIP = {"tags", "kind", "range", "status", "class", "weak", "atk", "cleanse", "profile_key"}   # 定宽小格子；名字、横幅走 fit() 缩字号


# 复核时发现的成批写法问题，合成 CSV 时统一改（只改模型稿）
FIXES = [(r"Ishar[-‐]mla", "Ishar'mla"), (r"\b[Tt]he We Many\b", "We Many"), (r"\bper a run\b", "per run"),
         (r"\bTide-?[Hh]unting Knight\b", "Tide-Hunt Knight"), (r"\bTidehunt Knight\b", "Tide-Hunt Knight"),
         (r"\bBasic attack", "Normal attack"), (r"\bbasic attack", "normal attack"), (r"Movement Speed", "movement speed"),
         (r"; Unlocks", "; unlocks"),
         # 恐鱼：官方英文统一叫 Seaborn（箱形恐鱼 = Chest Seaborn）
         (r"\bterrorfish\b", "Seaborn"), (r"\b[Tt]errors?\b(?! of)", "Seaborn"),
         (r"\bnot Move\b", "not move"), (r"\b(sturdy|swift|robust|fast) Melee\b", r"\1 melee"), (r"\bRanged entity\b", "ranged entity"),
         (r"Defier of Death or (a )?Repeller of Death", "Archon or Immortal"), (r"\ba Archon\b", "an Archon"),
         # docs/276 §4 禁用词
         (r"\bunleashes\b", "releases"), (r"\bunleashing\b", "releasing"), (r"\bpowerful rounds\b", "enhanced rounds"),
         (r"\btheir Bite\b", "their bite")]


def fix(en):
    for a, b in FIXES:
        en = re.sub(a, b, en)
    return en


def check_term(en, zh, gl):
    """官方名在中文里出现、英文里却没用官方写法 → 备注"""
    miss = []
    for k, v in gl.items():
        if len(k) >= 3 and k in zh and v["en"].lower() not in en.lower():
            miss.append(v["en"])
    return miss


def cmd_csv(a):
    import csv
    u, gl, items = units(a.module)
    cache = json.load(open(WORK / ("cache_%s.json" % a.module), encoding="utf-8"))
    pp = WORK / ("proof_%s.json" % a.module)
    proof = json.load(open(pp, encoding="utf-8")) if pp.exists() else {}   # 第二遍校对（cmd_proof）：zh → {en, why}
    human = {}
    hp = ROOT / "tools/l10n/review" / ("%s.json" % a.module)
    if hp.exists():
        human = json.load(open(hp, encoding="utf-8"))   # zh → {"en":..., "note":...} 人工复核改过的
    out = ROOT / "game/l10n" / ("%s.csv" % a.module)
    out.parent.mkdir(parents=True, exist_ok=True)
    stats = {"官方": 0, "暂定": 0, "模型": 0, "校对": 0, "人改": 0, "缺": 0}
    names = {}   # 本模块短名的最终译法（官方 > 人改 > 模型），查说明里「」引用是否一致
    for it in items:
        z = it["zh"]
        if len(z) > 12 or z in names:
            continue
        if "official" in it:
            names[z] = it["official"]
        elif z in human:
            names[z] = human[z]["en"]
        elif z in cache:
            v = cache[z]; names[z] = v.get("en") if isinstance(v, dict) else v
    for k, v in gl.items():
        names.setdefault(k, v["en"])
    renames = {}
    for z, h in human.items():
        if z.startswith("_") or not 2 < len(z) <= 12 or z not in cache:   # 两字标签常是更长名字的一部分（连射 ⊂ 穿甲连射），不同步
            continue
        v = cache[z]; old = v.get("en") if isinstance(v, dict) else v
        if isinstance(old, str) and old and old != h["en"] and len(old) >= 4:
            renames[z] = (old, h["en"])
    with open(out, "w", encoding="utf-8", newline="") as f:
        w = csv.writer(f)
        # Godot CSV 翻译表格式（docs/276 §10）：首列 keys，en 是唯一的语言列；_ 开头的列 Godot 导入时跳过（中文原文 / 来源 / 备注只给人看）
        w.writerow(["keys", "en", "_zh", "_source", "_note"])
        srcmap = {}   # 中文原文 → 英文：显示时按原文查表（名字、标签、招式名、已填数的说明）用
        rank = {"官方": 0, "暂定": 1, "人改": 2, "校对": 3, "模型": 4}
        for it in items:
            zh, note, src = it["zh"], [], ""
            if "official" in it:
                en = it["official"]
                src = "暂定" if it["official_src"].startswith("暂定") else "官方"
                note.append(it["official_src"])
            elif zh in human:
                h = human[zh]; en = h["en"]; src = "人改"
                if h.get("note"): note.append(h["note"])
            elif zh in cache:
                v = cache[zh]
                en = fix(v.get("en") if isinstance(v, dict) else v)
                for oz, (old, new) in renames.items():   # 人改过的短名，同步到引用它的说明
                    if oz in zh and old in en:
                        en = en.replace(old, new)
                src = "模型"
                if zh in proof and proof[zh].get("en"):
                    en = fix(proof[zh]["en"]); src = "校对"
                    note.append("校对：" + str(proof[zh].get("why", ""))[:80])
                if isinstance(v, dict):
                    if v.get("alt"): note.append("候选2：" + v["alt"])
                    if v.get("hard"): note.append("难翻，待用户定")
                    if v.get("note"): note.append(v["note"])
            else:
                en, src = "", "缺"
            if en and "quote_en" in it and src != "人改":
                note.append("首句招聘合同已换官方原文 " + it["quote_src"])
                body = en.split("\n", 1)[1] if "\n" in en else en   # 中文首行就是「招聘合同」，英文首行整行换掉
                en = "'%s'\n%s" % (it["quote_en"], body.lstrip())
            if en and src in ("模型", "校对", "人改"):
                if ph(en) != ph(zh):
                    note.append("占位符不一致")
                m = check_term(en, zh, gl)
                if m:
                    note.append("官方名未用上：" + " / ".join(sorted(set(m))[:3]))
                # 拉丁字母约半个汉字宽：短标签英文超过中文宽度 1.8 倍记「可能偏长」，界面适配时按实测再定
                if (it["field"] in CHIP or ".chips." in it["key"]) and len(zh) <= 12 and len(en) * 0.55 > 1.8 * len(zh) and len(en) > 10:
                    note.append("可能偏长：%d 字母 / 中文 %d 字" % (len(en), len(zh)))
                for q in re.findall(r"[「“](.{1,12}?)[」”]", zh):
                    qe = names.get(q)
                    if qe and qe.lower() not in en.lower():
                        note.append("「%s」本表译 %s，这里没对上" % (q, qe))
            stats[src] += 1
            w.writerow([it["key"], en, zh, src, "；".join(dict.fromkeys(n for n in note if n))])
            if en and (zh not in srcmap or rank.get(src, 9) < rank.get(srcmap[zh][1], 9)):
                srcmap[zh] = (en, src)
        # 原文键行：键 = 中文原文本身（Godot tr() 查不到时原样返回中文，不会出现空 key）
        taken = set()   # 已复核的 ops / enemies 原文键优先：其余模块不再重复写同一原文（TranslationServer 同键多份时取哪份不确定）
        if a.module not in ("ops", "enemies"):
            for om in ("ops", "enemies"):
                op = ROOT / "game/l10n" / (om + ".csv")
                if op.exists():
                    taken |= {r["keys"] for r in csv.DictReader(open(op, encoding="utf-8")) if r["_source"] == "原文键"}
        for zh, h in human.items():   # 补条：拆段后的片段等没有对应抽取条目的人改稿，也写成原文键
            if not zh.startswith("_") and zh not in srcmap and isinstance(h, dict) and h.get("en"):
                srcmap[zh] = (h["en"], "人改")
        for zh, (en, src) in srcmap.items():
            if zh != en and zh not in taken:
                w.writerow([zh, en, "", "原文键", src])
        # 短版：定宽格子（HUD 状态名、标签、按钮）用，键 short:<中文原文>（docs/276 §9 第 4 条）
        nshort = 0
        sp = ROOT / "tools/l10n/review/short.json"
        if a.module == "ops" and sp.exists():   # 短版是全局的（TranslationServer 不分模块），只写进 ops.csv 一份
            for zh, v in json.load(open(sp, encoding="utf-8")).items():
                if not zh.startswith("_"):
                    w.writerow(["short:" + zh, v, zh, "短版", "docs/276 §9 第 4 条"]); nshort += 1
        stats["原文键"] = len(srcmap); stats["短版"] = nshort
    print(out.relative_to(ROOT), stats)


PROOF = """You are proofreading an English localization of a Chinese fan game (Arknights squad survivor roguelike, Integrated Strategies #2 'Mizuki & Caerula Arbor' setting).
Each item has the Chinese source (zh), the current English (en), and where it is used (ctx; a key containing '.gd.' is a UI string from a script).
Fix ONLY real problems: mistranslation or missing meaning; leftover Chinese; terminology that differs from the fixed terms below; placeholders ({$...}, %d, %s, line breaks) changed, added or dropped; wording that breaks the style rules (no hype words like epic / unleash / powerful / journey / adventure, no exclamation marks unless the Chinese has one, official Arknights Global capitalization for statuses); a UI label (short Chinese) that became a long sentence.
Do not rewrite for taste. Keep official Arknights names exactly.
Fixed terms: {terms}
Return a JSON object mapping the id of every item that needs a change to {"en": corrected English, "why": short reason in Chinese}. Items that are fine must be omitted. Return {} if all are fine."""


def cmd_proof(a):
    import csv
    rows = [r for r in csv.DictReader(open(ROOT / "game/l10n" / (a.module + ".csv"), encoding="utf-8")) if r["_source"] == "模型"]
    pp = WORK / ("proof_%s.json" % a.module)
    sp_ = WORK / ("proofseen_%s.json" % a.module)
    proof = json.load(open(pp, encoding="utf-8")) if pp.exists() else {}
    seen = json.load(open(sp_, encoding="utf-8")) if sp_.exists() else {}
    todo, dup = [], set()
    for r in rows:
        if r["_zh"] in dup or r["_zh"] in seen:
            continue
        dup.add(r["_zh"]); todo.append(r)
    if a.limit:
        todo = todo[:a.limit]
    terms = dict(X.PROVISIONAL); terms.update(X.STYLE_TERMS)
    usage_p = WORK / ("usage_proof_%s.json" % a.module)
    usage = json.load(open(usage_p, encoding="utf-8")) if usage_p.exists() else {"in": 0, "out": 0, "think": 0, "calls": 0}
    print("%s：校对 %d 条" % (a.module, len(todo)), flush=True)
    for i in range(0, len(todo), 40):
        b = todo[i:i + 40]
        payload = [{"id": "p%d" % j, "zh": r["_zh"], "en": r["en"], "ctx": r["keys"]} for j, r in enumerate(b)]
        out, um = call(PROOF.replace("{terms}", json.dumps(terms, ensure_ascii=False)) + "\n\nItems:\n" + json.dumps(payload, ensure_ascii=False))
        if isinstance(out, list):
            out = {x.get("id"): x for x in out if isinstance(x, dict)}
        for j, r in enumerate(b):
            v = out.get("p%d" % j) if isinstance(out, dict) else None
            if isinstance(v, dict) and isinstance(v.get("en"), str) and v["en"] != r["en"] and ph(v["en"]) == ph(r["_zh"]):
                proof[r["_zh"]] = {"en": v["en"], "why": v.get("why", "")}
            seen[r["_zh"]] = 1
        for k2, k3 in (("in", "promptTokenCount"), ("out", "candidatesTokenCount"), ("think", "thoughtsTokenCount")):
            usage[k2] += um.get(k3, 0)
        usage["calls"] += 1
        json.dump(proof, open(pp, "w", encoding="utf-8"), ensure_ascii=False, indent=0)
        json.dump(seen, open(sp_, "w", encoding="utf-8"), ensure_ascii=False)
        json.dump(usage, open(usage_p, "w", encoding="utf-8"), indent=0)
        print("  批 %d：本批改 %d 条（累计 %d）" % (i // 40 + 1, sum(1 for r in b if r["_zh"] in proof), len(proof)), flush=True)
    cost = usage["in"] / 1e6 * PRICE_IN + (usage["out"] + usage["think"]) / 1e6 * PRICE_OUT
    print("校对累计 %d 次调用，估价 $%.2f" % (usage["calls"], cost))


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    ap = argparse.ArgumentParser()
    sp = ap.add_subparsers(dest="cmd", required=True)
    r = sp.add_parser("run"); r.add_argument("module"); r.add_argument("--limit", type=int, default=0); r.set_defaults(f=cmd_run)
    c = sp.add_parser("csv"); c.add_argument("module"); c.set_defaults(f=cmd_csv)
    pr = sp.add_parser("proof"); pr.add_argument("module"); pr.add_argument("--limit", type=int, default=0); pr.set_defaults(f=cmd_proof)
    a = ap.parse_args(); a.f(a)


if __name__ == "__main__":
    main()
