# -*- coding: utf-8 -*-
"""发行包瘦身（docs/33 §包体瘦身，用户 2026-10-14 批准；不改画面和声音）。

三件事，导出脚本（export_build.py / export_web.py）共用这里的规则：
1. 审阅用图片不进包：art/incoming 里 Codex 交付审阅用的拼图（contact / compare / art_review / elite_art / *_qa / 返修对照条 …）。
   规则在 REVIEW_ART_GLOBS；Windows 包按它挑要打进 pck 的 PNG，网页包复制美术时按它跳过，两个导出预设的 exclude_filter 也写着同一组规则。
2. 字体按实际用字子集化：只在打包副本里把 fonts/ui.ttf、fonts/serif.ttf 换成子集（仓库里的原字体不动）。
   用字 = game/scripts 的字符串与注释 + game/data 的 JSON + 场景 / project.godot 的全部字符 + ASCII + 原字体里所有非汉字字符（标点、数字、符号、全角）。
   ui_fallback.otf 不动，回退链（settings.gd 挂到 ui.ttf 上）照旧。
3. 测试与工具脚本不进包：两个预设的 exclude_filter 都有 tests/*、tools/*（发布版不读命令行，测试入口不可达，check_release 第 1 项）。

    python tools/release_slim.py            # 快检项：审阅图规则不误伤运行时引用的贴图、预设与规则一致、扫描到的字全在子集字体里
    python tools/release_slim.py --report   # 另列出：被排除的审阅图、未被引用但保留的 PNG、字体子集前后大小
"""
import argparse, fnmatch, glob, io, json, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GAME = os.path.join(ROOT, "game")
INCOMING = os.path.join(ROOT, "art", "incoming")

# 审阅用图片（按文件名，小写，fnmatch）。前五条是原来的 SKIP_WORDS / Web exclude_filter。
# 只用 * 和 ?：同一组规则原样写进导出预设的 exclude_filter，Godot 的 matchn 不认 [0-9] 之类的字符组。
# 新加规则后跑一次本脚本：被排除的图若在运行时文本里能找到名字（含「前缀 + 后缀」「格式串」拼法）就算失败
REVIEW_ART_GLOBS = (
    "*preview*", "*overview*", "*_frames.png", "*reference*", "*_ref.*",
    "*contact*", "*compare*", "*comparison*", "*composite*", "*_qa.*", "*_qa_*",
    "art_review_*", "elite_art_*", "run_rework_*", "idle_pose_*", "facing_*", "*lineup*",
)
# 只在开发 / 测试时用的目录（相对 game/）
DEV_EXCLUDES = ("tests/*", "tools/*")
SUBSET_FONTS = ("ui.ttf", "serif.ttf")
# FreeType 自动微调（serif.ttf 是没有微调指令的 TrueType，Godot 用 FreeType 自动微调）按「标准字」量全字体的笔画宽度：
# 汉字用「田」（缺了退「囗」）。子集里少了它，所有字的微调结果都会变（实测 serif 子集全体像素有差），所以一律保留
AUTOHINT_CHARS = "田囗"
FALLBACK_FONT = "ui_fallback.otf"


def is_review_art(name):
    n = os.path.basename(name).lower()
    return any(fnmatch.fnmatchcase(n, g) for g in REVIEW_ART_GLOBS)


def is_fallback_2x(name, siblings):
    """干员 @2x 回退条（docs/128）：同名 @1x 存在时，render/op_1x 缺省开、游戏读 1x，@2x 只在 op_1x=0 时回退用。
    对外包与网页包不带（Toy 50 MB 上限），对内包保留以便对照。siblings = 同目录文件名集合。
    10-23 用户「选人和图鉴放之前的精细版（@2x）」：界面立绘位（选人 / 图鉴 / 招募卡 / 属性面板，art.gd tex_hi）只用待机条，
    所以名字含 idle 的 @2x 照样进包；其余动作的 @2x 只是 op_1x=0 的回退"""
    n = os.path.basename(name)
    return n.lower().endswith("@2x.png") and (n[:-7] + "@1x.png") in siblings and "idle" not in n.lower()


def preset_excludes():
    """两个导出预设 exclude_filter 里应有的项（art/incoming 前缀 + 开发目录）"""
    return ["art/incoming/" + g for g in REVIEW_ART_GLOBS] + list(DEV_EXCLUDES)


# ---------- 运行时文本 ----------

def gd_split(txt):
    """GDScript 源码拆成（字符串字面量, 注释）两段文本。处理 \"\"\" / ''' 长串与转义"""
    lits, comments = [], []
    i, n = 0, len(txt)
    while i < n:
        c = txt[i]
        if c == "#":
            j = txt.find("\n", i)
            j = n if j < 0 else j
            comments.append(txt[i + 1:j])
            i = j
            continue
        if c in "\"'":
            q = txt[i:i + 3] if txt[i:i + 3] in ('"""', "'''") else c
            j = i + len(q)
            buf = []
            while j < n and txt[j:j + len(q)] != q:
                if txt[j] == "\\" and j + 1 < n:
                    m = re.match(r"u([0-9a-fA-F]{4})|U([0-9a-fA-F]{6})", txt[j + 1:j + 8])
                    if m:
                        buf.append(chr(int(m.group(1) or m.group(2), 16)))
                        j += 1 + len(m.group(0))
                        continue
                    buf.append(txt[j:j + 2])
                    j += 2
                    continue
                buf.append(txt[j])
                j += 1
            lits.append("".join(buf))
            i = j + len(q)
            continue
        i += 1
    return lits, comments


def _json_strings(v, out, docs):
    if isinstance(v, dict):
        for k, x in v.items():
            out.append(k)
            if isinstance(k, str) and k.startswith("_"):   # "_doc" / "_note" 之类设计说明：只算字（余量），不算贴图引用
                _json_strings(x, docs, docs)
            else:
                _json_strings(x, out, docs)
    elif isinstance(v, list):
        for x in v:
            _json_strings(x, out, docs)
    elif isinstance(v, str):
        out.append(v)


def _runtime_files(game):
    skip = ("tests", "tools", "addons", ".godot")   # 不进包 / 不是游戏内容的目录（相对 game/ 的第一级）
    keep = lambda p: os.path.relpath(p, game).replace("\\", "/").split("/")[0] not in skip
    gds = [p for p in glob.glob(os.path.join(game, "scripts", "**", "*.gd"), recursive=True) if keep(p)]
    jsons = [p for p in glob.glob(os.path.join(game, "data", "**", "*.json"), recursive=True) if keep(p)]
    scenes = [p for p in glob.glob(os.path.join(game, "**", "*.tscn"), recursive=True) + glob.glob(os.path.join(game, "**", "*.tres"), recursive=True) if keep(p)]
    return gds, jsons, scenes + [os.path.join(game, "project.godot")]


def runtime_text(game=GAME):
    """返回 (literals, margin)：literals = 运行时可能用到的字符串（.gd 字符串字面量、JSON 的键与值、场景与工程文件全文）；
    margin = 只当字体余量的文本（.gd 注释、JSON 里 _doc 之类说明字段）"""
    gds, jsons, others = _runtime_files(game)
    lits, margin = [], []
    for p in gds:
        a, b = gd_split(open(p, encoding="utf-8").read())
        lits += a
        margin += b
    for p in jsons:
        _json_strings(json.load(open(p, encoding="utf-8")), lits, margin)
    for p in others:
        if os.path.isfile(p):
            lits.append(open(p, encoding="utf-8").read())
    return lits, margin


# ---------- 1. 审阅图 ----------

def art_files(incoming=INCOMING):
    """随包候选：运行时贴图 [(文件名, 路径)]——game/art 索引里的加 art/incoming 根目录里索引没有的（docs/189 §6.1，过渡期两处都看）；
    带前缀的 portraits/ / optical_fx/ 不在内（不受审阅图规则影响）"""
    import asset_paths
    return sorted((n + ".png", p) for n, p in asset_paths.runtime_files(incoming=incoming).items() if "/" not in n)


def prune_game_art(gpath, drop_fallback):
    """导出副本 gpath（= 打包用的 game/）：drop_fallback 时删掉 game/art 里的干员 @2x 回退条（is_fallback_2x，对外包 / 网页包），
    再按剩下的文件重写副本里的 art/index.json。返回 (剩余 PNG 列表 [(名字, 路径)], 删掉的字节数)"""
    import asset_index
    art = os.path.join(gpath, "art")
    freed = 0
    if drop_fallback:
        idx, _ = asset_index.build(art)
        for name, rp in idx.items():
            p = os.path.join(art, rp[len("res://art/"):].replace("/", os.sep))
            if os.path.exists(p) and is_fallback_2x(os.path.basename(p), set(os.listdir(os.path.dirname(p)))):
                freed += os.path.getsize(p)
                os.remove(p)
                if os.path.exists(p + ".import"):
                    os.remove(p + ".import")
    idx, _ = asset_index.build(art)
    with open(os.path.join(art, "index.json"), "w", encoding="utf-8", newline="\n") as fh:
        fh.write(asset_index.dump(idx))
    return sorted((n, os.path.join(art, rp[len("res://art/"):].replace("/", os.sep))) for n, rp in idx.items()), freed


def art_report(game=GAME, incoming=INCOMING):
    """把 art/incoming 根目录 PNG 分成：referenced（运行时文本里能找到名字或「前缀 + 后缀」拼法）、review（审阅图规则排除）、
    unreferenced（找不到引用、但不是审阅图，照旧随包）。violations = 被审阅图规则排除、却能在运行时文本里找到的（不许有）"""
    lits, _ = runtime_text(game)
    blob = "\n".join(lits)
    litset = set(lits)
    fmts = []
    for s in litset:
        if "%s" in s and len(s) < 80 and len(s.replace("%s", "")) >= 3 and re.fullmatch(r"[A-Za-z0-9_%@/]+", s):
            fmts.append(re.compile("".join("[A-Za-z0-9_]+" if t == "%s" else re.escape(t) for t in re.split(r"(%s)", s))))
    out = {"referenced": [], "review": [], "unreferenced": [], "violations": []}
    for f, fp in art_files(incoming):
        base = f[:-4].replace("@2x", "")
        size = os.path.getsize(fp)
        ref = base in blob
        if not ref:   # 拼出来的名字（"growth_" + id、tex + "_move" 之类）：在某个 _ 处切开，前后两段各自是完整的字符串字面量，下划线归其中一段
            parts = base.split("_")
            for k in range(len(parts) - 1, 0, -1):
                pre, suf = "_".join(parts[:k]), "_".join(parts[k:])
                if (pre + "_" in litset and suf in litset) or (pre in litset and "_" + suf in litset):
                    ref = True
                    break
        if not ref:   # 格式串（"op_%s_%s" % [...] 之类）
            ref = any(rx.fullmatch(base) for rx in fmts)
        if is_review_art(f):
            out["review"].append((f, size))
            if ref:
                out["violations"].append(f)
        else:
            out["referenced" if ref else "unreferenced"].append((f, size))
    return out


def check_presets(game=GAME):
    """两个导出预设的 exclude_filter 都要含 preset_excludes() 的每一项"""
    errs = []
    text = open(os.path.join(game, "export_presets.cfg"), encoding="utf-8").read()
    for block in re.split(r"(?=^\[preset\.\d+\]$)", text, flags=re.M):
        m = re.search(r'^name="(.*)"$', block, re.M)
        ex = re.search(r'^exclude_filter="(.*)"$', block, re.M)
        if not m or not ex:
            continue
        have = {s.strip() for s in ex.group(1).split(",")}
        miss = [p for p in preset_excludes() if p not in have]
        if miss:
            errs.append("导出预设「%s」exclude_filter 缺：%s" % (m.group(1), ", ".join(miss)))
    return errs


# ---------- 2. 字体子集 ----------

def font_chars(game=GAME, src_font=None):
    """子集要保留的字：运行时文本 + 余量文本 + ASCII + 原字体里所有非汉字字符"""
    lits, margin = runtime_text(game)
    chars = set("".join(lits)) | set("".join(margin)) | {chr(c) for c in range(0x20, 0x7F)} | set(AUTOHINT_CHARS)
    if src_font:
        from fontTools.ttLib import TTFont
        chars |= {chr(c) for c in TTFont(src_font).getBestCmap() if not _is_han(c)}
    return {c for c in chars if c not in "\r\n\t"}


def _is_han(cp):
    return 0x3400 <= cp <= 0x9FFF or 0xF900 <= cp <= 0xFAFF or 0x20000 <= cp <= 0x3FFFF


def subset_bytes(src_font, chars):
    """fontTools 子集：保留全部 OpenType 特性 / 名称 / 未识别的表（字形、度量、排版行为不变），只去掉用不到的字"""
    from fontTools.ttLib import TTFont
    from fontTools import subset
    opt = subset.Options()
    opt.layout_features = ["*"]
    opt.name_IDs = ["*"]
    opt.name_languages = ["*"]
    opt.name_legacy = True
    opt.notdef_outline = True
    opt.notdef_glyph = True
    opt.glyph_names = True
    opt.drop_tables = []
    opt.passthrough_tables = True
    opt.prune_unicode_ranges = False
    opt.prune_codepage_ranges = False
    font = TTFont(src_font)
    have = font.getBestCmap()
    s = subset.Subsetter(opt)
    s.populate(unicodes=sorted(ord(c) for c in chars if ord(c) in have))
    s.subset(font)
    buf = io.BytesIO()
    font.save(buf)
    return buf.getvalue()


def subset_fonts(game_dir, scan_game=None):
    """打包副本用：把 game_dir/fonts 下的 SUBSET_FONTS 就地换成子集。拒绝改仓库里的 game/fonts。
    返回 [(文件名, 原字节, 子集字节, 原字形数, 子集字形数)]"""
    from fontTools.ttLib import TTFont
    if os.path.normcase(os.path.abspath(game_dir)) == os.path.normcase(os.path.abspath(GAME)):
        raise ValueError("只能对打包副本做字体子集，不改仓库里的 game/fonts")
    rows = []
    for fn in SUBSET_FONTS:
        p = os.path.join(game_dir, "fonts", fn)
        if not os.path.isfile(p):
            continue
        before = os.path.getsize(p)
        g0 = TTFont(p)["maxp"].numGlyphs
        data = subset_bytes(p, font_chars(scan_game or game_dir, p))
        with open(p, "wb") as fh:
            fh.write(data)
        rows.append((fn, before, len(data), g0, TTFont(p)["maxp"].numGlyphs))
    return rows


def print_font_rows(rows):
    tb = sum(r[1] for r in rows)
    ta = sum(r[2] for r in rows)
    for fn, b, a, g0, g1 in rows:
        print("[瘦身] 字体子集 %s：%.2f MB → %.2f MB（字形 %d → %d）" % (fn, b / 1e6, a / 1e6, g0, g1), flush=True)
    if rows:
        print("[瘦身] 字体合计：%.2f MB → %.2f MB" % (tb / 1e6, ta / 1e6), flush=True)


def check_fonts(game=GAME, report=False):
    """扫描到的字：原字体有的，子集里必须都有；ui.ttf 与 ui_fallback.otf 都没有的字只提示（与子集无关，原来就缺）"""
    from fontTools.ttLib import TTFont
    errs, info = [], []
    lits, _ = runtime_text(game)
    used = {c for c in "".join(lits) if ord(c) > 0x7F}
    fb = TTFont(os.path.join(game, "fonts", FALLBACK_FONT)).getBestCmap()
    for fn in SUBSET_FONTS:
        p = os.path.join(game, "fonts", fn)
        orig = TTFont(p).getBestCmap()
        data = subset_bytes(p, font_chars(game, p))
        sub = TTFont(io.BytesIO(data)).getBestCmap()
        lost = sorted(c for c in used if ord(c) in orig and ord(c) not in sub)
        if lost:
            errs.append("%s 子集缺字 %d 个：%s" % (fn, len(lost), "".join(lost[:40])))
        lost_nonhan = [c for c in orig if not _is_han(c) and c not in sub]
        if lost_nonhan:
            errs.append("%s 子集丢了非汉字字符 %d 个（标点 / 数字 / 符号要全留）" % (fn, len(lost_nonhan)))
        info.append("%s %.2f → %.2f MB" % (fn, os.path.getsize(p) / 1e6, len(data) / 1e6))
        if fn == "ui.ttf":
            nowhere = sorted(c for c in used if ord(c) not in orig and ord(c) not in fb and not c.isspace())
            if nowhere and report:
                print("提示：ui.ttf 与 ui_fallback.otf 都没有的字 %d 个（与子集无关，桌面版靠系统字体）：%s" % (len(nowhere), "".join(nowhere)))
    return errs, info


def check(report=False):
    errs = []
    rep = art_report()
    for f in rep["violations"]:
        errs.append("审阅图规则排除了运行时文本里引用到的贴图：%s" % f)
    errs += check_presets()
    ferrs, finfo = check_fonts(report=report)
    errs += ferrs
    rb = sum(s for _, s in rep["review"])
    detail = "审阅图 %d 张（%.2f MB）不进包，未误伤运行时引用；字体子集 %s" % (len(rep["review"]), rb / 1e6, "，".join(finfo))
    if report:
        print("== 审阅图（排除）%d 张，%.2f MB" % (len(rep["review"]), rb / 1e6))
        for f, s in rep["review"]:
            print("   %8d %s" % (s, f))
        ub = sum(s for _, s in rep["unreferenced"])
        print("== 运行时文本里找不到引用、但不是审阅图（照旧随包，多为待接入的素材）%d 张，%.2f MB" % (len(rep["unreferenced"]), ub / 1e6))
        for f, s in rep["unreferenced"]:
            print("   %8d %s" % (s, f))
        print("== 引用到的 %d 张" % len(rep["referenced"]))
    return errs, detail


def main():
    for st in (sys.stdout, sys.stderr):
        try:
            st.reconfigure(encoding="utf-8", errors="replace")
        except Exception:
            pass
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--report", action="store_true")
    a = ap.parse_args()
    errs, detail = check(a.report)
    print(detail)
    for e in errs:
        print("失败：" + e)
    return 1 if errs else 0


if __name__ == "__main__":
    sys.exit(main())
