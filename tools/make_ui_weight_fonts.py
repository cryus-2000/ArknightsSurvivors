"""界面字重对照用字体（11-06 用户「这个字体有点丑，查一下明日方舟用的什么字体」→「做对照」）：
明日方舟正文是思源黑体，干员名用 Heavy、说明用 Normal（UI 分析文章，见 docs/291）。我们 ui.ttf 是思源黑体 Bold 一档到底。
这里从 Noto Sans SC 可变字重版（= 思源黑体）切出 Heavy（900）与 Regular（400）两份，码位与 ui.ttf 完全相同（同一批 4096 个），
纵向度量（hhea / OS/2 ascent、descent、lineGap）抄 ui.ttf，换字体后行高、基线不变。
用法：python tools/make_ui_weight_fonts.py [NotoSansSC-VF.ttf 路径]  → game/fonts/ui_heavy.ttf、game/fonts/ui_regular.ttf"""
import os, sys
from fontTools.ttLib import TTFont
from fontTools import subset
from fontTools.varLib import instancer

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
SRC = sys.argv[1] if len(sys.argv) > 1 else "C:/Windows/Fonts/NotoSansSC-VF.ttf"
UI = os.path.join(ROOT, "game", "fonts", "ui.ttf")


def build(wght: int, out: str, fam: str):
    ref = TTFont(UI)
    cps = set(ref.getBestCmap().keys())
    vf = TTFont(SRC)
    f = instancer.instantiateVariableFont(vf, {"wght": wght})
    opts = subset.Options()
    opts.layout_features = ["*"]
    opts.name_IDs = ["*"]
    opts.notdef_outline = True
    opts.hinting = False
    sub = subset.Subsetter(opts)
    sub.populate(unicodes=cps)
    sub.subset(f)
    # 纵向度量对齐 ui.ttf（两者都是 1000 units/em）
    for k in ("ascent", "descent", "lineGap"):
        setattr(f["hhea"], k, getattr(ref["hhea"], k))
    for k in ("sTypoAscender", "sTypoDescender", "sTypoLineGap", "usWinAscent", "usWinDescent"):
        setattr(f["OS/2"], k, getattr(ref["OS/2"], k))
    f["OS/2"].usWeightClass = wght
    n = f["name"]
    for rec in list(n.names):
        if rec.nameID in (1, 4, 6, 16, 17):
            n.removeNames(nameID=rec.nameID)
    n.setName(fam, 1, 3, 1, 0x409)
    n.setName(fam, 4, 3, 1, 0x409)
    n.setName(fam.replace(" ", ""), 6, 3, 1, 0x409)
    f.save(out)
    print(out, os.path.getsize(out) // 1024, "KB", len(TTFont(out).getBestCmap()), "codepoints")


build(900, os.path.join(ROOT, "game", "fonts", "ui_heavy.ttf"), "ArkUI Heavy")
build(400, os.path.join(ROOT, "game", "fonts", "ui_regular.ttf"), "ArkUI Regular")
