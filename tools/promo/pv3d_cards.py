# -*- coding: utf-8 -*-
"""PV 3D 开头的卡面贴图（11-08）：20 名干员各一张（像素待机帧 + 职业色 + 金边 + 名字），一张卡背。
  python tools/promo/pv3d_cards.py <输出目录>
只用本作像素帧，不用原作立绘。"""
import json, os, sys
from PIL import Image, ImageDraw
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from fx import WT, font, glyph, INK, CYAN, WHITE

CW, CH = 630, 880
GOLD = (214, 176, 98)
CLS = {"近卫": ("warrior", (200, 46, 64)), "先锋": ("pioneer", (236, 140, 52)), "特种": ("special", (120, 104, 236)),
       "狙击": ("sniper", (226, 196, 70)), "术师": ("caster", (176, 92, 226)), "医疗": ("medic", (90, 200, 120)),
       "重装": ("tank", (70, 140, 220)), "辅助": ("support", (60, 190, 200))}


_CMAP = None


def nfont(text, sz):
    """ui.ttf 缺字（娅、鲨……）时整名换 ui_fallback.otf"""
    global _CMAP
    from PIL import ImageFont
    if _CMAP is None:
        from fontTools.ttLib import TTFont
        _CMAP = TTFont(WT + "/game/fonts/ui.ttf").getBestCmap()
    if all(ord(c) in _CMAP for c in text):
        return font(sz)
    return ImageFont.truetype(WT + "/game/fonts/ui_fallback.otf", sz)


def idle0(cid, d):
    sp = d["sprites"]
    idle = sp.get("idle")
    tex = idle.get("tex") if isinstance(idle, dict) else None
    tex = tex or sp.get("base") or "op_%s_idle" % cid
    n = int(idle.get("frames", 8)) if isinstance(idle, dict) else 8
    p = WT + "/game/art/operators/%s/%s@2x.png" % (cid, tex)
    if not os.path.exists(p):
        p = WT + "/game/art/operators/%s/op_%s_idle@2x.png" % (cid, cid)
    s = Image.open(p).convert("RGBA")
    fw = s.width // n
    f = s.crop((0, 0, fw, s.height))
    return f.crop(f.getbbox())


def face(cid, out):
    d = json.load(open(WT + "/game/data/characters/%s.json" % cid, encoding="utf-8"))
    icon, col = CLS.get(d.get("class", ""), ("special", (120, 120, 160)))
    im = Image.new("RGBA", (CW, CH), INK + (255,))
    dr = ImageDraw.Draw(im)
    for y in range(CH):   # 职业色由下往上渐隐
        a = max(0.0, (y / CH - 0.25)) ** 1.6
        c = tuple(int(INK[i] + (col[i] * 0.55 - INK[i]) * a) for i in range(3))
        dr.line((0, y, CW, y), fill=c + (255,))
    for x in range(-CH, CW, 46):   # 细斜纹
        dr.line((x, CH, x + CH, 0), fill=col + (22,), width=2)
    f = idle0(cid, d)
    k = max(1, min(560 // f.height, 520 // f.width))
    f = f.resize((f.width * k, f.height * k), Image.NEAREST)
    im.alpha_composite(f, ((CW - f.width) // 2, 640 - f.height))
    dr.rectangle((14, 14, CW - 15, CH - 15), outline=GOLD + (255,), width=5)
    dr.rectangle((30, 30, CW - 31, CH - 31), outline=GOLD + (120,), width=2)
    dr.polygon([(30, 680), (CW - 30, 680), (CW - 30, CH - 30), (30, CH - 30)], fill=INK + (225,))
    dr.rectangle((30, 680, CW - 30, 686), fill=col + (255,))
    nm = d.get("name", cid)
    fz = nfont(nm, 78 if len(nm) <= 4 else 60)
    dr.text((CW / 2 - fz.getlength(nm) / 2, 712), nm, font=fz, fill=WHITE + (255,))
    fe = font(30)
    en = d.get("en", cid.upper())
    dr.text((CW / 2 - fe.getlength(en) / 2, 812), en, font=fe, fill=GOLD + (255,))
    pi = Image.open(WT + "/game/art/ui/professions/%s.png" % icon).convert("RGBA").resize((72, 72), Image.NEAREST)
    im.alpha_composite(pi, (48, 48))
    im.save(out)


def back(out):
    im = Image.new("RGBA", (CW, CH), (10, 16, 24, 255))
    dr = ImageDraw.Draw(im)
    for x in range(-CH, CW, 30):
        dr.line((x, CH, x + CH, 0), fill=(28, 44, 56, 255), width=2)
        dr.line((x, 0, x + CH, CH), fill=(28, 44, 56, 255), width=2)
    dr.rectangle((14, 14, CW - 15, CH - 15), outline=GOLD + (255,), width=5)
    dr.rectangle((30, 30, CW - 31, CH - 31), outline=GOLD + (120,), width=2)
    cx, cy, r = CW // 2, CH // 2, 120
    dr.polygon([(cx, cy - r), (cx + r, cy), (cx, cy + r), (cx - r, cy)], outline=GOLD + (255,), width=6)
    dr.polygon([(cx, cy - 46), (cx + 46, cy), (cx, cy + 46), (cx - 46, cy)], fill=GOLD + (255,))
    im.save(out)


if __name__ == "__main__":
    od = sys.argv[1]
    os.makedirs(od, exist_ok=True)
    ids = sorted(f[:-5] for f in os.listdir(WT + "/game/data/characters") if f.endswith(".json"))
    for c in ids:
        try:
            face(c, os.path.join(od, c + ".png"))
        except Exception as e:
            print("skip", c, e)
    back(os.path.join(od, "_back.png"))
    print(len(ids), "张")
