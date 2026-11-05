"""英文超框预检（docs/276 §9）：用游戏字体量中 / 英文的像素宽度，按界面框宽折行算行数，列出放不下的条目。

  python tools/l10n/overflow_check.py          # → build/l10n_work/overflow.csv + 屏幕摘要；--md 另出 docs/278 对照页

字体：中文 = game/fonts/ui.ttf（Noto Sans CJK SC Bold 子集，现用）；英文 = Noto Sans Bold（docs/276 §2.7 方案 A，
OFL，本地副本 build/l10n_ref/fonts/，不进 git；没有就退回 ui.ttf 的拉丁字形）。都按桌面设计尺寸 1280×720。
框宽 / 字号取自界面代码（各 CTX 的 src 写了出处）；取不准的（ratio = True）只比「英文 ÷ 中文」，超过 1.3 记超框。
这是预检，不替代第三步截图验收：Godot 的 TextParagraph 断行、字距与 PIL 有出入，误差约 ±5%。
"""
import csv, re, sys
from pathlib import Path

from PIL import ImageFont

ROOT = Path(__file__).resolve().parents[2]
ZH_FONT = ROOT / "game/fonts/ui.ttf"
EN_FONT = ROOT / "build/l10n_ref/fonts/NotoSans-Bold.ttf"
if not EN_FONT.exists():
    EN_FONT = ZH_FONT
FLOOR = 0.85   # fit 自动缩字号的下限：原字号的 85%（协调人 11-05）

# 界面上下文：w = 框宽，h = 框高（None = 单行），sizes = 现有 fit 字号表（大→小），ratio = 框量不准、只比比例
CTX = {
    "card":     dict(name="升级卡一句话 / 招募卡简介", w=232, h=116, sizes=[14, 13], src="choice_panel.gd CARD_W 272 - 40，紧凑布局 DESC_H_DESK_C 116，DESC_SIZES_DESK"),
    "skillrow": dict(name="图鉴技能行说明", w=288, h=None, sizes=[12, 11, 10], src="gallery.gd _panel_x 932–1244（宽 312）- 24；_row_heights 按中文行数分高度", lines_from_zh=True),
    "galdesc":  dict(name="图鉴说明栏（定位 / 机制）", w=312, h=150, sizes=[13, 12, 11, 10], src="gallery.gd _draw_data desc：宽 312，高约 688 - y（标签行以下约 150）"),
    "lore":     dict(name="图鉴档案", w=312, h=400, sizes=[13, 12, 11], src="gallery.gd 档案页：宽 312，高按 680 - y 估约 400"),
    "bossline": dict(name="Boss 出场台词", w=921, h=None, sizes=[14, 13, 12, 11], src="boss_intro.gd fit_line(card.line, 14, vs.x × 0.72, 11)", single=True),
    "bosssub":  dict(name="Boss 出场副标题", w=921, h=None, sizes=[14], src="boss_intro.gd sub（同台词宽）", single=True),
    "banner":   dict(name="横幅", w=1152, h=None, sizes=[21], src="hud_banners.gd 21 号居中，最宽屏宽 90%", single=True),
    "name":     dict(name="名字（技能 / 节点 / 招式）", w=200, h=None, sizes=[13], src="gallery.gd 技能行 / 成长树 fit_line(name, 13, 约 200, 9)；choice_panel 卡名 nmax ≈ 272 - 48", single=True),
    "chip":     dict(name="标签 / 档案栏位 / 状态名（定宽）", w=None, h=None, sizes=[11], src="gallery.gd ctag 11 号（格子随字宽、满行换行）、HUD 状态名；取不准，按比例", ratio=True, single=True),
    "trigger":  dict(name="连携触发条件", w=None, h=None, sizes=[12], src="gallery.gd 技能行副标题", ratio=True, single=True),
}


def ctx_of(key, field):
    if key.endswith("gallery.intro") or ".progression." in key and field in ("desc", "brief"):
        return "card"
    if key.startswith("lore.") and field == "lore":
        return "lore"
    if field in ("gallery",) or key.endswith("gallery.desc") or (key.startswith("enemy.") and field == "desc"):
        return "galdesc"
    if field in ("desc", "branch_desc"):
        return "skillrow"
    if key.endswith("intro.line"):
        return "bossline"
    if key.endswith("intro.sub"):
        return "bosssub"
    if field in ("banner",) or (key.startswith("enemy.gd.") and ("——" in key or False)):
        return "banner"
    if field == "trigger":
        return "trigger"
    if field in ("tags", "kind", "range", "status", "class", "weak", "atk", "cleanse", "profile", "profile_key", "faction", "chips", "sub", "s"):
        return "chip"
    if field in ("name", "src", "label", "branch", "line", "gd"):
        return "name"
    return None


_fc = {}


def font(p, size):
    k = (str(p), size)
    if k not in _fc:
        _fc[k] = ImageFont.truetype(str(p), size)
    return _fc[k]


PH = re.compile(r"\{\$[^}]*\}")


def sample(s):
    """占位符换成典型数字（2 位数 + 小数），%d 换成 3"""
    return PH.sub("12.5", s).replace("%d", "3").replace("%%", "%").replace("\\n", "\n")


def width(s, p, size):
    return font(p, size).getlength(s)


def lh(p, size):
    a, d = font(p, size).getmetrics()
    return a + d


def wrap(s, p, size, w, cjk):
    """贪心折行：中文按字（行首不放结尾标点），英文按词（超长词硬切）"""
    lines = []
    for para in s.split("\n"):
        if cjk:
            cur = ""
            for ch in para:
                if cur and width(cur + ch, p, size) > w and ch not in "，。、；：！？」）》”’…":
                    lines.append(cur); cur = ch
                else:
                    cur += ch
            lines.append(cur)
        else:
            cur = ""
            for wd in para.split(" "):
                t = (cur + " " + wd) if cur else wd
                if cur and width(t, p, size) > w:
                    lines.append(cur); cur = wd
                else:
                    cur = t
            lines.append(cur)
    return lines


def brief(s, cjk):
    """choice_panel.brief() 的同款：第一行、去括号、截到第一个「；」「。」（英文 '; ' '. '）"""
    s = s.strip().split("\n")[0]
    s = re.sub(r"（[^）]*）|\([^)]*\)", "", s)
    for sep in (["；", "。"] if cjk else ["; ", ". "]):
        k = s.find(sep)
        if k > 0:
            s = s[:k]
    return s.strip()


def measure(zh, en, c, card_brief=False):
    zh, en = sample(zh), sample(en)
    if card_brief:
        zh, en = brief(zh, True), brief(en, False)
    base = c["sizes"][0]
    if c.get("ratio") or c.get("single"):
        zw = max(width(x, ZH_FONT, base) for x in zh.split("\n"))
        ew = max(width(x, EN_FONT, base) for x in en.split("\n"))
        if c.get("ratio"):
            r = ew / max(zw, 1.0)
            # 格子宽取不准：按中文宽 × 1.6、至少 56 px 估（标签是随字宽的胶囊，满行才换行）
            box = max(zw * 1.6, 56.0)
            over = ew - box
            min_ok = next((sz for sz in range(base, int(base * FLOOR) - 1, -1) if width(en, EN_FONT, sz) <= box), None)
            return dict(kind="比例", zh=zw, en=ew, ratio=r, over=over, base=base, fit_size=min_ok, box=box)
        box = c["w"]
        sizes = list(range(base, int(base * FLOOR) - 1, -1))
        min_ok = next((sz for sz in sizes if width(en, EN_FONT, sz) <= box), None)
        return dict(kind="单行", zh=zw, en=ew, ratio=ew / max(zw, 1.0), over=ew - box, base=base, fit_size=min_ok, box=box)
    # 多行：按框宽折行，比较行数 / 高度
    w = c["w"]
    smallest = c["sizes"][-1]
    # 技能行：_row_heights 先试 12 号，整页放得下就用 12（中文现状基本如此），所以中文按最大号量、英文可退到最小号
    zsz = c["sizes"][0] if c.get("lines_from_zh") else smallest
    zl = wrap(zh, ZH_FONT, zsz, w, True)
    zh_h = len(zl) * lh(ZH_FONT, zsz)
    # 允许高度 = max(框高, 中文实际占用)：中文本来就超框的段落另有机制（详情键、悬停全文、可点开的行），只算英文比中文多出的部分。
    # 技能行几行共用一块区域、按各行中文行数分高度，所以允许 = 中文占用
    room = max(c["h"], zh_h) if c.get("h") else zh_h
    best = None
    for sz in list(c["sizes"]) + [s for s in range(c["sizes"][-1] - 1, int(c["sizes"][0] * FLOOR) - 1, -1)]:
        el = wrap(en, EN_FONT, sz, w, False)
        eh = len(el) * lh(EN_FONT, sz)
        if eh <= room:
            best = (sz, len(el), eh)
            break
    el0 = wrap(en, EN_FONT, smallest, w, False)
    eh0 = len(el0) * lh(EN_FONT, smallest)
    return dict(kind="多行", zh_lines=len(zl), en_lines=len(el0), zh_h=zh_h, en_h=eh0, room=room, over=eh0 - room,
                ratio=eh0 / max(zh_h, 1.0), base=c["sizes"][0], fit_size=best[0] if best else None,
                line_h=lh(EN_FONT, smallest))


def verdict(m, c):
    """处理办法（协调人 11-05 优先级）：改短 → 多折一行 → 缩字号（≥85%）→ 短版 _short"""
    if m["over"] <= 0:
        return "放得下", 0
    if m["fit_size"] is not None:
        if m["fit_size"] >= min(c["sizes"]):
            return "放得下（现有 fit 字号表内）", 0
        return "缩字号到 %d（≥85%%）" % m["fit_size"], 1
    if m["kind"] == "多行":
        extra = m["over"] / m["line_h"]
        if extra <= 1.0:
            return "改短，或多折一行（超 %.1f 行）" % extra, 2
        return "改短（超 %.1f 行）" % extra, 3
    if c.get("ratio") and m["ratio"] <= 1.8:
        return "改短，或缩字号", 2
    return "改短；仍超就加 _short", 3


def run(md=False):
    rows = []
    for mod in ("ops", "enemies"):
        for r in csv.DictReader(open(ROOT / "game/l10n" / (mod + ".csv"), encoding="utf-8")):
            if not r["en"]:
                continue
            k = r["key"]
            parts = k.split(".")
            field = parts[-1] if not parts[-1].isdigit() else parts[-2]
            if k.startswith("enemy.gd."):
                field = "gd"
                if "——" in r["zh"] or "！" in r["zh"] or len(r["zh"]) > 9:
                    field = "banner"
            cx = ctx_of(k, field)
            if not cx:
                continue
            c = CTX[cx]
            m = measure(r["zh"], r["en"], c, card_brief=(cx == "card" and not k.endswith("gallery.intro")))
            v, sev = verdict(m, c)
            rows.append(dict(mod=mod, key=k, zh=r["zh"], en=r["en"], ctx=cx, ctxname=c["name"], m=m, verdict=v, sev=sev))
    bad = [x for x in rows if x["sev"] > 0]
    bad.sort(key=lambda x: (-x["sev"], -(x["m"]["over"] / (x["m"].get("line_h") or x["m"].get("box") or 1.0))))
    out = ROOT / "build/l10n_work/overflow.csv"
    with open(out, "w", encoding="utf-8", newline="") as f:
        w = csv.writer(f)
        w.writerow(["严重度", "界面", "key", "zh", "en", "量法", "中文", "英文", "超出", "比例", "处理"])
        for x in bad:
            m = x["m"]
            if m["kind"] == "多行":
                zs, es, ov = "%d 行" % m["zh_lines"], "%d 行" % m["en_lines"], "%.0f px（%.1f 行）" % (m["over"], m["over"] / m["line_h"])
            else:
                zs, es, ov = "%.0f px" % m["zh"], "%.0f px" % m["en"], "%.0f px" % m["over"]
            w.writerow([x["sev"], x["ctxname"], x["key"], x["zh"], x["en"], m["kind"], zs, es, ov, "%.2f" % m["ratio"], x["verdict"]])
    # 摘要
    from collections import Counter, defaultdict
    by = defaultdict(Counter)
    for x in rows:
        by[x["ctxname"]][x["sev"]] += 1
    print("界面                               条数   放得下  缩字号  改短/多折  改短/短版")
    for name, cn in by.items():
        print("%-28s %5d %8d %7d %9d %9d" % (name, sum(cn.values()), cn[0], cn[1], cn[2], cn[3]))
    print("超框 %d / %d 条 → %s" % (len(bad), len(rows), out.relative_to(ROOT)))
    if md:
        write_md(bad[:30], by, len(rows), len(bad))
    return rows, bad


def write_md(top, by, n, nb):
    def cell(s):
        return str(s).replace("|", "\\|").replace("\n", "<br>")
    L = ["# 278 英文超框预检：前 30 条（干员 + 怪物）", "",
         "2026-11-05。tools/l10n/overflow_check.py 用游戏字体量像素宽度（中文 ui.ttf、英文 Noto Sans Bold，桌面 1280×720 设计尺寸），按界面框宽折行。全表在 build/l10n_work/overflow.csv，规则与处理办法见 docs/276 §9。这是预检，最终以第三步截图为准（误差约 ±5%）。", "",
         "共量 %d 条，超框 %d 条。严重度：1 = 缩字号能放下（不低于原字号 85%%）；2 = 要改短或多折一行；3 = 必须改短，HUD / 按钮类另写 _short。" % (n, nb), "",
         "| 界面 | 条数 | 放得下 | 1 缩字号 | 2 改短 / 多折 | 3 改短 / 短版 |", "|---|---|---|---|---|---|"]
    for name, cn in by.items():
        L.append("| %s | %d | %d | %d | %d | %d |" % (name, sum(cn.values()), cn[0], cn[1], cn[2], cn[3]))
    L += ["", "| # | 严重度 | 界面 | 中文 | English | 中 → 英 | 处理 |", "|---|---|---|---|---|---|---|"]
    for i, x in enumerate(top, 1):
        m = x["m"]
        if m["kind"] == "多行":
            d = "%d 行 → %d 行（超 %.1f 行）" % (m["zh_lines"], m["en_lines"], m["over"] / m["line_h"])
        else:
            d = "%.0f → %.0f px（×%.2f）" % (m["zh"], m["en"], m["ratio"])
        L.append("| %d | %d | %s | %s | %s | %s | %s |" % (i, x["sev"], x["ctxname"], cell(x["zh"]), cell(x["en"]), d, x["verdict"]))
    (ROOT / "docs/278_english_overflow.md").write_text("\n".join(L) + "\n", encoding="utf-8")
    print("docs/278_english_overflow.md")


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    run(md="--md" in sys.argv)
