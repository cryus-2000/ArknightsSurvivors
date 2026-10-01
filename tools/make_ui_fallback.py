# -*- coding: utf-8 -*-
"""生成 game/fonts/ui_fallback.otf（界面与美术 2026-10-01）：ui.ttf（Noto Sans CJK SC 子集）缺的字的回退字体。
扫 game/scripts 与 game/data 里所有 ui.ttf 没有的字，从 Noto Sans SC Bold（OFL，与 ui.ttf 同族同字重）只取这些字形；
另补全套 A–Z 圈字（手柄提示 Ⓐ Ⓑ Ⓧ Ⓨ）。settings.gd 启动时挂到 ui.ttf 的 fallbacks 上——网页版没有系统字体可回退。
新文案用到生僻字后重跑一次：python tools/make_ui_fallback.py [Noto Sans SC Bold 路径]
"""
import glob, os, sys
from fontTools.ttLib import TTFont
from fontTools import subset

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = sys.argv[1] if len(sys.argv) > 1 else "C:/Windows/Fonts/Noto Sans SC Bold (TrueType).otf"
OUT = os.path.join(ROOT, "game", "fonts", "ui_fallback.otf")

have = TTFont(os.path.join(ROOT, "game", "fonts", "ui.ttf")).getBestCmap()
src_cmap = TTFont(SRC).getBestCmap()
chars = set()
for f in glob.glob(os.path.join(ROOT, "game", "scripts", "**", "*.gd"), recursive=True) + glob.glob(os.path.join(ROOT, "game", "data", "**", "*.json"), recursive=True):
    chars |= {c for c in open(f, encoding="utf-8").read() if ord(c) > 0x7F and ord(c) not in have and ord(c) in src_cmap}
chars |= {chr(c) for c in range(0x24B6, 0x24D0) if c in src_cmap}
text = "".join(sorted(chars))
opt = subset.Options()
opt.layout_features = ["*"]
opt.name_IDs = ["*"]
opt.name_languages = ["*"]
opt.notdef_outline = True
font = TTFont(SRC)
s = subset.Subsetter(opt)
s.populate(text=text)
s.subset(font)
font.save(OUT)
sys.stdout.reconfigure(encoding="utf-8")
print(len(text), "字：", text)
print(OUT, os.path.getsize(OUT), "bytes")
