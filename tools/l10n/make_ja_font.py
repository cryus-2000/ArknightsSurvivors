"""日文回退字体 game/l10n/ui_ja.otf（docs/276 §13）：界面字体 ui.ttf（Noto Sans CJK SC 子集）没有假名和日文新字体（戦 / 撃 / 歩 …）。
从 Noto Sans JP Bold（SIL OFL 1.1，github.com/notofonts/noto-cjk，与 ui.ttf 同族同字重）只取「日文文本用到、发行包 ui.ttf 子集与 ui_fallback.otf 都没有」的字。
放在 game/l10n/ 下：B站 Toy 包整个不带 l10n（export_web --toy），只有 itch 包有。loc.gd 切到日文时才 load、挂到 ui.ttf / serif.ttf 的 fallbacks 末尾。

  python tools/l10n/make_ja_font.py [NotoSansJP-Bold.otf 路径]     # 生成（缺省 build/fonts_src/NotoSansJP-Bold.otf）
  python tools/l10n/make_ja_font.py --check                         # 只查：日文文本里有没有三种字体都没有的字（release_slim 快检也调 missing()）
日文文本 = 各 CSV 的 ja 列 + 脚本里日文分支的字面量（含假名或 GB2312 外汉字的字面量）。新译文用到新字后重跑一次。
"""
import csv, glob, os, sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
GAME = os.path.join(ROOT, "game")
OUT = os.path.join(GAME, "l10n", "ui_ja.otf")
SRC = os.path.join(ROOT, "build", "fonts_src", "NotoSansJP-Bold.otf")
sys.path.insert(0, os.path.join(ROOT, "tools"))


def _jaish(s):
    for c in s:
        o = ord(c)
        if 0x3041 <= o <= 0x30FF:
            return True
        if 0x4E00 <= o <= 0x9FFF:
            try:
                c.encode("gb2312")
            except UnicodeEncodeError:
                return True
    return False


def ja_text(game=GAME):
    chars = set()
    for p in glob.glob(os.path.join(game, "l10n", "*.csv")):
        for r in csv.DictReader(open(p, encoding="utf-8")):
            chars |= set(r.get("ja") or "")
    import release_slim
    lits, _ = release_slim.runtime_text(game)
    for s in lits:
        if len(s) < 200 and _jaish(s):
            chars |= set(s)
    return {c for c in chars if ord(c) > 0x7F and not c.isspace()}


def _have(game=GAME):
    """发行包里日文模式能用的字：ui.ttf 子集（按运行时文本）∪ ui_fallback.otf"""
    from fontTools.ttLib import TTFont
    import release_slim
    ui = os.path.join(game, "fonts", "ui.ttf")
    cm = TTFont(ui).getBestCmap()
    kept = {c for c in release_slim.font_chars(game, ui) if ord(c) in cm}
    fb = {chr(c) for c in TTFont(os.path.join(game, "fonts", release_slim.FALLBACK_FONT)).getBestCmap()}
    return kept | fb


def missing(game=GAME):
    """日文文本里 ui.ttf 子集、ui_fallback、ui_ja 都没有的字（空 = 不会出豆腐块）"""
    from fontTools.ttLib import TTFont
    need = ja_text(game) - _have(game)
    if not need:
        return []
    p = os.path.join(game, "l10n", "ui_ja.otf")
    ja = {chr(c) for c in TTFont(p).getBestCmap()} if os.path.isfile(p) else set()
    import release_slim
    return sorted(c for c in need if c not in ja and c not in "​‌‍﻿" and c not in release_slim.FONT_GAP_OK)


def build(src):
    import release_slim
    from fontTools.ttLib import TTFont
    need = ja_text() - _have()
    cm = TTFont(src).getBestCmap()
    gap = sorted(c for c in need if ord(c) not in cm)
    data = release_slim.subset_bytes(src, need | set("田囗"))   # 田囗：FreeType 自动微调的标准字（同 release_slim AUTOHINT_CHARS）
    open(OUT, "wb").write(data)
    print("ui_ja.otf：%d 字，%.0f KiB → %s" % (len(need), len(data) / 1024, OUT))
    if gap:
        print("Noto Sans JP 也没有的字 %d 个：%s" % (len(gap), "".join(gap)))


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    if "--check" in sys.argv:
        m = missing()
        print("日文缺字 %d 个%s" % (len(m), "：" + "".join(m) if m else ""))
        sys.exit(1 if m else 0)
    build(sys.argv[1] if len(sys.argv) > 1 else SRC)
