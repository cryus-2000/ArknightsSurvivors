"""手机界面字体（用户 11-05「手机的字体是不是也可以换一下」→ 中文 + 数字都换）：
中文用 Noto Sans SC Medium（比 ui.ttf 的 Bold 细一档），字表与 ui.ttf 完全相同（同一批 4096 个码位）；
数字 / 拉丁字母 / 常用符号换成 Montserrat SemiBold（指挥台、属性栏读数用的那套几何字体）。
两者都是 1000 units/em；纵向度量沿用 Noto（ascent 1160 / descent −288，同 ui.ttf），手机上换字体后行高、基线不变，排版不跑位。
做法：Noto Medium（CFF）先按 ui.ttf 的码位子集，再转成 TrueType 轮廓（cu2qu），把 Montserrat 的字形画进去替换 ASCII 区。
用法：python tools/make_ui_phone_font.py [Noto Sans SC Medium 路径]  → game/fonts/ui_phone.ttf"""
import os, sys
from fontTools.ttLib import TTFont, newTable
from fontTools import subset
from fontTools.pens.cu2quPen import Cu2QuPen
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.pens.recordingPen import DecomposingRecordingPen

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
SRC = sys.argv[1] if len(sys.argv) > 1 else "C:/Windows/Fonts/Noto Sans SC Medium (TrueType).otf"
UI = os.path.join(ROOT, "game", "fonts", "ui.ttf")
MONT = os.path.join(ROOT, "game", "fonts", "montserrat_semibold.ttf")
OUT = os.path.join(ROOT, "game", "fonts", "ui_phone.ttf")


def main():
    cps = set(TTFont(UI).getBestCmap().keys())
    # 1) 子集到 ui.ttf 的码位
    opts = subset.Options()
    opts.layout_features = ["*"]
    opts.name_IDs = ["*"]
    opts.notdef_outline = True
    opts.hinting = False
    f = TTFont(SRC)
    sub = subset.Subsetter(opts)
    sub.populate(unicodes=cps)
    sub.subset(f)
    # 2) CFF → glyf（二次曲线）
    gs = f.getGlyphSet()
    order = f.getGlyphOrder()
    glyf = {}
    for gn in order:
        pen = TTGlyphPen(None)
        gs[gn].draw(Cu2QuPen(pen, max_err=1.0, reverse_direction=True))
        glyf[gn] = pen.glyph()
    # 3) Montserrat 的拉丁 / 数字 / 符号替换进来（字形分解后画，宽度沿用 Montserrat）
    m = TTFont(MONT)
    mgs = m.getGlyphSet()
    mcm = m.getBestCmap()
    hmtx = {gn: f["hmtx"][gn] for gn in order}
    cmap = dict(f.getBestCmap())
    swapped = 0
    for cp, mgn in mcm.items():
        if cp < 0x21 or cp > 0x2212:
            continue
        name = "mont_%04X" % cp
        rec = DecomposingRecordingPen(mgs)   # 复合字形（引号、带符号字母）先分解成轮廓，不留对 Montserrat 字形名的引用
        mgs[mgn].draw(rec)
        pen = TTGlyphPen(None)
        rec.replay(pen)
        glyf[name] = pen.glyph()
        hmtx[name] = (m["hmtx"][mgn][0], 0)
        if name not in order:
            order.append(name)
        cmap[cp] = name
        swapped += 1
    # 4) 组装 TrueType
    out = TTFont()
    out.setGlyphOrder(order)
    for tag in ("head", "hhea", "OS/2", "name", "post"):
        out[tag] = f[tag]
    out["post"].formatType = 3.0
    out["post"].extraNames = []
    out["post"].mapping = {}
    out["glyf"] = newTable("glyf")
    out["glyf"].glyphOrder = order
    out["glyf"].glyphs = glyf
    out["loca"] = newTable("loca")
    out["maxp"] = newTable("maxp")
    out["maxp"].tableVersion = 0x00010000
    for k in ("numGlyphs", "maxPoints", "maxContours", "maxCompositePoints", "maxCompositeContours", "maxZones", "maxTwilightPoints",
              "maxStorage", "maxFunctionDefs", "maxInstructionDefs", "maxStackElements", "maxSizeOfInstructions", "maxComponentElements",
              "maxComponentDepth"):
        setattr(out["maxp"], k, 0)
    out["maxp"].maxZones = 1
    out["hmtx"] = newTable("hmtx")
    out["hmtx"].metrics = hmtx
    from fontTools.ttLib.tables._c_m_a_p import cmap_format_4, cmap_format_12
    out["cmap"] = newTable("cmap")
    out["cmap"].tableVersion = 0
    t4 = cmap_format_4(4)
    t4.platformID, t4.platEncID, t4.language = 3, 1, 0
    t4.cmap = {k: v for k, v in cmap.items() if k <= 0xFFFF}
    t12 = cmap_format_12(12)
    t12.platformID, t12.platEncID, t12.language = 3, 10, 0
    t12.cmap = dict(cmap)
    out["cmap"].tables = [t4, t12]
    out["head"].glyphDataFormat = 0
    out["head"].indexToLocFormat = 1
    name = out["name"]
    for rec in name.names:
        if rec.nameID in (1, 4, 6):
            rec.string = "ArkUIPhone" if rec.nameID != 6 else "ArkUIPhone-Medium"
    out.save(OUT)
    print("ui_phone.ttf: %d 字形（替换拉丁 / 数字 %d 个），%.2f MB" % (len(order), swapped, os.path.getsize(OUT) / 1048576.0))


if __name__ == "__main__":
    main()
