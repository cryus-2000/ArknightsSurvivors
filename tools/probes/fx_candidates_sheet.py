"""Boss 激光 / 枪击特效候选对照图（docs/142b §8.4 的专属色）：从 art/third_party（不入库的已购 / 开放许可素材库）
抽现成的光束、射线、枪口火光、弹体、命中、烟尘帧条，按游戏里大概的显示尺寸放大，原色一列 + 按 Boss 专属色换色几列；
激光另把「起点 + 中段平铺 + 命中端」拼成一整条看效果。只读素材库，输出到 build/fx_candidates/（不进包、不入库）。

    python tools/probes/fx_candidates_sheet.py
"""
import glob, os, re
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
TP = next(p for p in (os.path.join(ROOT, "art", "third_party"),
                      os.path.join(ROOT, "..", "..", "..", "art", "third_party"))   # 工作树里没有素材库时用主仓库那份
          if os.path.isdir(os.path.join(p, "ansimuz_explosions_magic")))
A = os.path.join(TP, "ansimuz_explosions_magic")
CK = os.path.join(TP, "creativekind")
OUT = os.path.join(ROOT, "build", "fx_candidates")
FONT = os.path.join(ROOT, "game", "fonts", "ui.ttf")
BG = (16, 20, 30)

# docs/142b §8.4 专属色（近似 RGB 0–1）
BOSS = {
    "泡影": (0.78, 0.62, 1.0), "伊莎玛拉": (0.25, 1.0, 0.6), "伊祖米克": (0.3, 0.5, 1.0), "骑士": (0.85, 0.95, 1.0),
    "塑路者": (0.75, 0.8, 0.88), "伊比利亚": (1.0, 0.5, 0.2), "卡门": (1.0, 0.94, 0.82), "主教": (0.3, 0.35, 0.9),
    "蔑死体": (0.35, 0.9, 0.45), "斥亡体": (0.65, 0.7, 1.0),
}
RESERVED = [("小怪子弹 青蓝", (0.3, 0.85, 1.0)), ("预警 危险洋红", (1.0, 0.15, 0.4)), ("主轴目标 金", (1.0, 0.82, 0.3))]


def font(n):
    return ImageFont.truetype(FONT, n)


def seq(d, pat="*.png"):
    fs = glob.glob(os.path.join(d, "**", pat), recursive=True)
    key = lambda p: [int(t) if t.isdigit() else t for t in re.split(r"(\d+)", os.path.basename(p))]
    return [Image.open(p).convert("RGBA") for p in sorted(fs, key=key)]


def sheet_frames(path, fw, fh, n=None, vertical=False):
    im = Image.open(path).convert("RGBA")
    out = []
    cols = im.width // fw
    rows = im.height // fh
    for r in range(rows):
        for c in range(cols):
            out.append(im.crop((c * fw, r * fh, c * fw + fw, r * fh + fh)))
    out = [f for f in out if f.getbbox()]
    return out[:n] if n else out


def recolor(im, col):
    """按亮度映射到专属色的四阶色板（暗 → 本色 → 亮 → 近白），保留透明度"""
    stops = [(0.0, tuple(c * 0.18 for c in col)), (0.45, tuple(c * 0.75 for c in col)),
             (0.75, col), (1.0, tuple(min(1.0, c * 0.4 + 0.65) for c in col))]
    px = im.load()
    out = im.copy()
    po = out.load()
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            L = (0.299 * r + 0.587 * g + 0.114 * b) / 255.0
            L = max(L, max(r, g, b) / 255.0 * 0.85)   # 饱和色的亮部别被压暗
            for i in range(len(stops) - 1):
                if L <= stops[i + 1][0]:
                    t = (L - stops[i][0]) / max(1e-6, stops[i + 1][0] - stops[i][0])
                    c = tuple(stops[i][1][k] + (stops[i + 1][1][k] - stops[i][1][k]) * t for k in range(3))
                    break
            else:
                c = stops[-1][1]
            po[x, y] = (int(c[0] * 255), int(c[1] * 255), int(c[2] * 255), a)
    return out


def game_scale(f):
    """游戏里大概的显示大小：≤64 的按 2 倍，65–160 按 1 倍，更大的缩到 160 以内"""
    m = max(f.width, f.height)
    if m <= 64:
        k = 2.0
    elif m <= 160:
        k = 1.0
    else:
        k = 160.0 / m
    return f.resize((max(1, int(f.width * k)), max(1, int(f.height * k))), Image.NEAREST)


def pick(frames, n=5):
    if len(frames) <= n:
        return frames
    return [frames[round(i * (len(frames) - 1) / (n - 1))] for i in range(n)]


def strip(frames, col=None, gap=6):
    fr = [game_scale(recolor(f, col) if col else f) for f in frames]
    w = sum(f.width for f in fr) + gap * (len(fr) - 1)
    h = max(f.height for f in fr)
    im = Image.new("RGBA", (w, h), BG + (255,))
    x = 0
    for f in fr:
        im.alpha_composite(f, (x, (h - f.height) // 2))
        x += f.width + gap
    return im


def assemble(start, mid, end, n_mid, col=None, rot=0):
    """激光拼装：起点 + 中段平铺 n_mid 次 + 命中端（横向）；rot 把竖向素材转成横向"""
    bb = mid.getbbox()
    if bb:
        mid = mid.crop((bb[0], 0, bb[2], mid.height))   # 循环段左右带透明边，裁掉才拼得上
    parts = [start] + [mid] * n_mid + [end]
    parts = [p.rotate(rot, expand=True) if rot else p for p in parts]
    parts = [game_scale(recolor(p, col) if col else p) for p in parts]
    w = sum(p.width for p in parts)
    h = max(p.height for p in parts)
    im = Image.new("RGBA", (w, h), BG + (255,))
    x = 0
    for p in parts:
        im.alpha_composite(p, (x, (h - p.height) // 2))
        x += p.width
    return im


def tracer_demo(col, length=300):
    """程序画的曳光：一条短命亮线（白芯 + 本色 + 本色柔光，不加深色外圈——用户 10-25），从枪口往外 4 个时刻"""
    W, H = length + 20, 4 * 22
    im = Image.new("RGBA", (W, H), BG + (255,))
    d = ImageDraw.Draw(im)
    c = tuple(int(v * 255) for v in col)
    for i, (a, b) in enumerate(((0, 0.35), (0.2, 0.7), (0.55, 1.0), (0.85, 1.0))):
        y = 11 + i * 22
        x0, x1 = 10 + a * length, 10 + b * length
        d.line((x0, y, x1, y), fill=tuple(int(v * 0.45) for v in c), width=8)
        d.line((x0, y, x1, y), fill=c, width=4)
        d.line((x0 + (x1 - x0) * 0.4, y, x1, y), fill=(255, 255, 255), width=2)
    return im


def render(title, rows, path):
    """rows: [(名字, 来源与许可, [(列标题, 图), ...]), ...]"""
    pad, lab_w = 14, 380
    blocks = []
    for name, src, cells in rows:
        cw = sum(c[1].width for c in cells) + pad * (len(cells) - 1)
        ch = max(c[1].height for c in cells) + 22
        blocks.append((name, src, cells, cw, max(ch, 30 + 20 * (len(name) // 22 + 1) + 16 * (len(src) // 26 + 1))))
    W = lab_w + max(b[3] for b in blocks) + pad * 2
    H = 70 + 44 + sum(b[4] + pad for b in blocks) + pad
    im = Image.new("RGBA", (W, H), (8, 10, 16, 255))
    d = ImageDraw.Draw(im)
    d.text((pad, 12), title, font=font(24), fill=(240, 240, 240))
    x = pad
    for nm, c in RESERVED:
        d.rectangle((x, 52, x + 26, 66), fill=tuple(int(v * 255) for v in c))
        d.text((x + 32, 50), nm + "（Boss 不用）", font=font(13), fill=(200, 205, 215))
        x += 230
    y = 70 + 44
    for name, src, cells, cw, ch in blocks:
        d.rectangle((pad - 4, y - 4, W - pad + 4, y + ch + 2), outline=(40, 46, 60))
        yy = y + 2
        for ln in [name[i:i + 22] for i in range(0, len(name), 22)]:
            d.text((pad, yy), ln, font=font(16), fill=(255, 255, 255))
            yy += 20
        yy += 2
        for ln in [src[i:i + 26] for i in range(0, len(src), 26)]:
            d.text((pad, yy), ln, font=font(12), fill=(160, 168, 182))
            yy += 16
        cx = lab_w
        for lab, img in cells:
            d.text((cx, y), lab, font=font(12), fill=(200, 205, 215))
            im.alpha_composite(img, (cx, y + 18))
            cx += img.width + pad
        y += ch + pad
    os.makedirs(OUT, exist_ok=True)
    im.convert("RGB").save(path, optimize=True)
    print(path, im.size)


def lasers():
    rows = []
    pim = os.path.join(TP, "holy_light", "pimen_holy_vfx_01_02", "Holy VFX 01", "Separated Frames")
    ini = seq(pim, "Holy VFX 01 Initial*.png")
    rep = seq(pim, "Holy VFX 01 Repeatable*.png")
    imp = seq(pim, "Holy VFX 01 Impact*.png")
    rows.append(("Pimen 圣光光束（起手 2 + 循环 8 + 命中 7，32px，拼装：起点 + 中段 ×10 + 命中）", "已购 · 个人 / 商用可，不得再分发（现用于铃兰 / 塞雷娅）", [
        ("原色", assemble(ini[-1], rep[2], imp[2], 10)),
        ("伊比利亚 橙", assemble(ini[-1], rep[2], imp[2], 10, BOSS["伊比利亚"])),
        ("泡影 淡紫", assemble(ini[-1], rep[2], imp[2], 10, BOSS["泡影"])),
    ]))
    rows.append(("Pimen 圣光光束 · 循环段逐帧", "同上", [("原色", strip(pick(rep, 6))), ("骑士 冰白", strip(pick(rep, 6), BOSS["骑士"]))]))
    ray = seq(os.path.join(A, "14_gothicvania_magic_pack_10", "sprites", "Ray"))
    rows.append(("ansimuz 电射线 Ray（15 帧，48×128，竖向）", "已购 · 可商用可改，不得再分发", [
        ("原色", strip(pick(ray, 5))), ("伊祖米克 群青", strip(pick(ray, 5), BOSS["伊祖米克"])), ("卡门 象牙白", strip(pick(ray, 5), BOSS["卡门"]))]))
    rb = seq(os.path.join(A, "14_gothicvania_magic_pack_10", "sprites", "Raybolt"))
    rows.append(("ansimuz 射线弹 Raybolt（10 帧，48×64）", "已购 · 同上", [
        ("原色", strip(pick(rb, 5))), ("主教 靛蓝", strip(pick(rb, 5), BOSS["主教"])), ("伊莎玛拉 青绿", strip(pick(rb, 5), BOSS["伊莎玛拉"]))]))
    tr = seq(os.path.join(A, "03_gothicvania_magic_pack_n3", "sprites", "thunderrays"))
    rows.append(("ansimuz 雷柱 thunderrays（12 帧，48×111）", "已购 · 同上", [
        ("原色", strip(pick(tr, 5))), ("骑士 冰白", strip(pick(tr, 5), BOSS["骑士"]))]))
    ck = lambda sub, fn, fw, fh: sheet_frames(os.path.join(CK, sub, fn), fw, fh)
    eb = ck("11_Magic_Spell_Effects_6", os.path.join("Sprite_Sheet", "Energy_beam-Sheet.png"), 96, 672)
    rows.append(("CreativeKind 能量光束 Energy_beam（10 帧，96×672，竖向）", "已购 · 用户 09-26 确认可进包", [
        ("原色", strip(pick(eb, 5))), ("伊祖米克 群青", strip(pick(eb, 5), BOSS["伊祖米克"])), ("泡影 淡紫", strip(pick(eb, 5), BOSS["泡影"]))]))
    pb = ck("11_Magic_Spell_Effects_6", os.path.join("Sprite_Sheet", "PowerBeam-Sheet.png"), 96, 352)
    rows.append(("CreativeKind 强光束 PowerBeam（14 帧，96×352）", "已购 · 同上", [
        ("原色", strip(pick(pb, 5))), ("伊比利亚 橙", strip(pick(pb, 5), BOSS["伊比利亚"]))]))
    sl = ck("04_Magic_spell_effects_2", "SKY LASER_single-Sheet.png", 100, 144)
    rows.append(("CreativeKind 天降激光 SKY LASER（50 帧，100×144）", "已购 · 同上（落点打击：轰击 / 掷枪）", [
        ("原色", strip(pick(sl, 6))), ("骑士 冰白", strip(pick(sl, 6), BOSS["骑士"])), ("伊比利亚 橙", strip(pick(sl, 6), BOSS["伊比利亚"]))]))
    db = ck("14_Magic_Spell_Effects_7", "Spell1_DarkBeam_black-Sheet.png", 128, 192)
    rows.append(("CreativeKind 暗光束 DarkBeam（19 帧，128×192）", "已购 · 同上", [
        ("原色", strip(pick(db, 5))), ("泡影 淡紫", strip(pick(db, 5), BOSS["泡影"]))]))
    og = os.path.join(TP, "generic_fx", "oga_pixel_art_spells", "pixelart_spells_1", "Pixelart Spells", "PNG Files")
    for fn, nm in (("Magic Ray.png", "Magic Ray"), ("Black And White Ray.png", "Black And White Ray")):
        im = Image.open(os.path.join(og, fn)).convert("RGBA")
        h = im.height
        fr = [im.crop((i * h, 0, i * h + h, h)) for i in range(im.width // h)] if im.width >= h * 2 else [im]
        fr = [f for f in fr if f.getbbox()]
        seg = fr[len(fr) // 2]
        rows.append((f"OpenGameArt {nm}（{len(fr)} 帧，{h}px，光束中段）", "CC0 · 免费", [
            ("逐帧 原色", strip(pick(fr, 6))), ("平铺成一条 原色", assemble(seg, seg, seg, 14)),
            ("平铺 斥亡体 淡紫蓝", assemble(seg, seg, seg, 14, BOSS["斥亡体"]))]))
    render("Boss 激光 / 光束候选（现有素材库，按游戏里大概的显示大小；右侧几列按 docs/142b §8.4 专属色换色）", rows, os.path.join(OUT, "lasers.png"))


def guns():
    rows = []
    fl = seq(os.path.join(A, "05_gothicvania_magic_pack_5", "sprites", "flash", "sprites"))
    rows.append(("ansimuz 闪光 flash（14 帧，64）→ 枪口火光", "已购 · 可商用可改，不得再分发", [
        ("原色", strip(pick(fl, 6))), ("伊比利亚 橙", strip(pick(fl, 6), BOSS["伊比利亚"])), ("卡门 象牙白", strip(pick(fl, 6), BOSS["卡门"]))]))
    for nm, sub, lab in (("Hit-H", "Hit-H", "定向刺光（狙击命中）"), ("Hit-d", "Hit-d", "星芒命中"), ("Hit-k", "Hit-k", "弧光命中")):
        fr = seq(os.path.join(A, "12_warped_vfx_pack_1", "Sprites", sub))
        rows.append((f"ansimuz {nm}（{len(fr)} 帧）→ {lab}", "已购 · 同上", [
            ("原色", strip(pick(fr, 5))), ("伊比利亚 橙", strip(pick(fr, 5), BOSS["伊比利亚"])), ("卡门 象牙白", strip(pick(fr, 5), BOSS["卡门"]))]))
    fm = seq(os.path.join(A, "05_gothicvania_magic_pack_5", "sprites", "fire-missile", "sprites"))
    rows.append(("ansimuz 火球弹 fire-missile（5 帧，57×33）→ 炮弹", "已购 · 同上", [
        ("原色", strip(fm)), ("伊比利亚 橙", strip(fm, BOSS["伊比利亚"])), ("卡门 象牙白", strip(fm, BOSS["卡门"]))]))
    og = os.path.join(TP, "generic_fx", "oga_pixel_art_spells", "pixelart_spells_1", "Pixelart Spells", "PNG Files")
    for fn in ("Light Bolt.png", "Fireball.png"):
        im = Image.open(os.path.join(og, fn)).convert("RGBA")
        h = im.height
        fr = [f for f in (im.crop((i * h, 0, i * h + h, h)) for i in range(max(1, im.width // h))) if f.getbbox()]
        rows.append((f"OpenGameArt {fn[:-4]}（{len(fr)} 帧，{h}px）→ 小弹体", "CC0 · 免费", [
            ("原色", strip(pick(fr, 6))), ("伊比利亚 橙", strip(pick(fr, 6), BOSS["伊比利亚"])), ("主教 靛蓝", strip(pick(fr, 6), BOSS["主教"]))]))
    for pack, sub in (("07_warped_explosion_pack_3", "explosion-b"), ("07_warped_explosion_pack_3", "explosion-d"), ("08_warped_explosion_pack_4", "explosion-c")):
        fr = seq(os.path.join(A, pack, "Sprites" if pack.startswith("07") else "sprites", sub))
        if not fr:
            fr = seq(os.path.join(A, pack), f"{sub}*.png")
        if fr:
            rows.append((f"ansimuz 小爆炸 {pack[3:].replace('_', ' ')} / {sub}（{len(fr)} 帧）→ 炮击落点", "已购 · 同上", [
                ("原色", strip(pick(fr, 6))), ("伊比利亚 橙", strip(pick(fr, 6), BOSS["伊比利亚"]))]))
    du = seq(os.path.join(A, "05_gothicvania_magic_pack_5", "sprites", "impact-dust", "sprites"))
    pf = seq(os.path.join(A, "05_gothicvania_magic_pack_5", "sprites", "puff", "sprites"))
    rows.append(("ansimuz 落地尘 impact-dust（10 帧）+ 烟团 puff（6 帧）→ 余韵", "已购 · 同上", [
        ("落地尘 原色", strip(pick(du, 5))), ("烟团 原色", strip(pf)), ("烟团 卡门 象牙白", strip(pf, BOSS["卡门"]))]))
    sp = seq(os.path.join(A, "14_gothicvania_magic_pack_10", "sprites", "Sparks"))
    rows.append(("ansimuz 电火花 Sparks（16 帧，48）→ 命中火星", "已购 · 同上", [
        ("原色", strip(pick(sp, 6))), ("伊比利亚 橙", strip(pick(sp, 6), BOSS["伊比利亚"]))]))
    wh = sheet_frames(os.path.join(TP, "fire_lava", "codemanu_pixel_effects", "Free Pixel Effects Pack", "10_weaponhit_spritesheet.png"), 100, 100)
    rows.append((f"CodeManu weaponhit（{len(wh)} 帧，100px）→ 重击命中", "CC-BY 4.0 · 要署名（致谢页已有）", [
        ("原色", strip(pick(wh, 6))), ("伊比利亚 橙", strip(pick(wh, 6), BOSS["伊比利亚"]))]))
    rows.append(("程序画的曳光（对照：白芯 + 本色 + 柔光，4 个时刻）", "自己画，不用素材", [
        ("伊比利亚 橙", tracer_demo(BOSS["伊比利亚"])), ("卡门 象牙白", tracer_demo(BOSS["卡门"]))]))
    render("Boss 枪击候选：枪口火光 / 弹体 / 命中 / 余韵（现有素材库；右侧按专属色换色）", rows, os.path.join(OUT, "guns.png"))


KP_DIRS = [os.path.join(r, "lasers", "kanpelle_ultimate_laser_pack", "Ultimate Laser Pack")
           for r in (os.path.join(ROOT, "art", "third_party"), TP)]


def kp_sheet(color):
    """Kanpelle Ultimate Laser Pack：192×288，4 列 × 6 行、每格 48；行 = 起点持续 / 起点开启 / 中段持续 / 中段开启 / 命中持续 / 命中开启，
    每段只占格子里 x 16–31 这一条（16 宽）"""
    d = next(x for x in KP_DIRS if os.path.isdir(x))
    im = Image.open(os.path.join(d, f"Laser_Beam_Spritesheet_{color}.png")).convert("RGBA")
    cell = lambda r, c: im.crop((c * 48 + 16, r * 48, c * 48 + 32, r * 48 + 48))
    return {k: [cell(r, c) for c in range(4)] for k, r in (("src", 0), ("src_on", 1), ("mid", 2), ("mid_on", 3), ("hit", 4), ("hit_on", 5))}


def kp_beam(parts, f, n_mid, col=None, k=2):
    """拼一条：起点 + 中段 × n_mid + 命中端，第 f 帧；k = 放大倍数（游戏里按 2 倍显示）"""
    src, mid, hit = parts[0][f], parts[1][f], parts[2][f]
    seg = [src] + [mid] * n_mid + [hit]
    seg = [recolor(x, col) if col else x for x in seg]
    w = sum(x.width for x in seg)
    im = Image.new("RGBA", (w, 48), BG + (255,))
    x = 0
    for t in seg:
        im.alpha_composite(t, (x, 0))
        x += t.width
    bb = im.getbbox()
    im = im.crop((0, 8, w, 40))
    return im.resize((im.width * k, im.height * k), Image.NEAREST)


def kanpelle():
    rows = []
    W = kp_sheet("WHITE")
    flow = (W["src"], W["mid"], W["hit"])
    on = (W["src_on"], W["mid_on"], W["hit_on"])
    for nm in ("伊比利亚", "卡门", "泡影", "伊祖米克", "伊莎玛拉", "骑士", "主教", "蔑死体", "斥亡体", "塑路者"):
        c = BOSS[nm]
        rows.append((f"{nm}（白色版换专属色）", "持续帧 × 2 倍；右边 3 倍粗（重炮）", [
            ("持续", kp_beam(flow, 0, 12, c)), ("持续 3 倍粗", kp_beam(flow, 1, 8, c, 3))]))
    anim = [kp_beam(on, f, 8, BOSS["伊比利亚"]) for f in range(4)] + [kp_beam(flow, f, 8, BOSS["伊比利亚"]) for f in range(2)]
    col = Image.new("RGBA", (max(a.width for a in anim), sum(a.height + 4 for a in anim)), BG + (255,))
    y = 0
    for a in anim:
        col.alpha_composite(a, (0, y))
        y += a.height + 4
    rows.insert(0, ("开启 4 帧 → 持续（伊比利亚 橙）", "关闭 = 开启倒放", [("从上到下逐帧", col)]))
    native = []
    for c in ("ORANGE", "WHITE", "PURPLE", "BLUE", "GREEN", "CYAN"):
        S = kp_sheet(c)
        native.append((f"包内原色 {c}", kp_beam((S["src"], S["mid"], S["hit"]), 0, 6)))
    rows.insert(1, ("包内原色（对照）", "10 种颜色里挑 6 种", native[:3]))
    rows.insert(2, ("包内原色（续）", "", native[3:]))
    render("Kanpelle · Ultimate Laser Pack（起点 + 中段平铺 + 命中端；按 docs/142b §8.4 专属色换色）", rows, os.path.join(OUT, "kanpelle.png"))


if __name__ == "__main__":
    import sys
    if "--kanpelle" in sys.argv:
        kanpelle()
    else:
        lasers()
        guns()
        kanpelle()
