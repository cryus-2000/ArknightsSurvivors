# -*- coding: utf-8 -*-
"""宣传主视觉合成（界面与美术，2026-09-30 协调人派）：只用本项目自己的像素资产（art/incoming 帧条 + logo + game/fonts）。
版式参照「深色底、高对比、像素角色放大居中、技能光效点睛、字少而大」的气质，不用任何外部素材。

用法：python tools/promo_keyart.py [输出目录，缺省 build/promo] [--size 1920x1080] [--name keyart] [--boss paranoia|knight|saints] [--squad a,b,c,d,e]（干员 id，mizuki = 水月）
像素一律整数倍最近邻放大，保持颗粒清楚。
"""
import os, sys, random
from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageChops

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
ART = os.path.join(ROOT, "art", "incoming")
FONT_UI = os.path.join(ROOT, "game", "fonts", "ui.ttf")

SLOGAN_CN = "点亮灯火，穿过深海"
SLOGAN_EN = "LIGHT THE LAMP. OUTLAST THE DEEP."
NOTICE = "《明日方舟》同人作品 · 非官方 · 非商业  |  Arknights fan work · unofficial · non-commercial"

# 编队：[贴图名, 帧数]；中间是主控（放大一档）
SQUAD = [("op_saria_idle@2x", 4), ("op_skadi_idle@2x", 4), ("player_idle@2x", 4), ("op_suzuran_idle@2x", 4), ("op_wisadel_idle@2x", 4)]
SQUAD_OVERRIDE = None   # --squad a,b,c,d,e（干员 id，mizuki = 水月；中间那位放大一档）
BOSS_DX, BOSS_DY = 0.10, 0.06   # 泡影相对画面中心右移 / 顶部下沉（协调人：别压标题「幸存者」）
BOSSES = {"saints": None, "paranoia": ("e_paranoia_phase2@2x", 2), "knight": ("e_knight", 2)}


def load(name):
    im = Image.open(os.path.join(ART, name + ".png")).convert("RGBA")
    # 帧条四周有 alpha 1–30 的近透明噪点：放大 + 染色 / 发光后会显出一个方框，先清掉
    r, g, b, a = im.split()
    a = a.point(lambda v: 0 if v < 40 else v)
    im.putalpha(a)
    return im


def frame(name, n, i=0, trim=False):
    im = load(name)
    fw = im.width // n
    f = im.crop((fw * i, 0, fw * (i + 1), im.height))
    if trim:
        bb = f.getbbox()
        if bb:
            f = f.crop(bb)
    return f


def up(im, k):
    return im.resize((im.width * k, im.height * k), Image.NEAREST)


def tint(im, col, keep=0.0):
    """保留 alpha，颜色换成 col（keep = 原色保留比例）"""
    a = im.split()[3]
    solid = Image.new("RGBA", im.size, col + (255,))
    solid.putalpha(a)
    return Image.blend(solid, im, keep) if keep > 0 else solid


def glow(im, col, radius, strength=1.0):
    """外发光：先四周留出 3 倍半径的空白再模糊（不留白会在贴图边界被截成一个方框）；返回 (图, 偏移)"""
    pad = int(radius * 3) + 2
    big = Image.new("RGBA", (im.width + pad * 2, im.height + pad * 2), (0, 0, 0, 0))
    big.alpha_composite(tint(im, col), (pad, pad))
    a = big.split()[3].filter(ImageFilter.GaussianBlur(radius)).point(lambda v: min(255, int(v * strength)))
    big.putalpha(a)
    return big, pad


def put_glow(img, im, col, radius, strength, xy):
    g, pad = glow(im, col, radius, strength)
    img.alpha_composite(g, (int(xy[0]) - pad, int(xy[1]) - pad))


def add(base, over, xy):
    """加色叠加（光效）"""
    layer = Image.new("RGBA", base.size, (0, 0, 0, 0))
    layer.alpha_composite(over, (int(xy[0]), int(xy[1])))
    rgb = Image.new("RGB", base.size, (0, 0, 0))
    rgb.paste(layer.convert("RGB"), (0, 0), layer.split()[3])
    return ImageChops.add(base.convert("RGB"), rgb).convert("RGBA")


def radial(size, center, r, col, alpha):
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).ellipse((center[0] - r, center[1] - r, center[0] + r, center[1] + r), fill=alpha)
    m = m.filter(ImageFilter.GaussianBlur(r * 0.45))
    layer = Image.new("RGBA", size, col + (0,))
    layer.putalpha(m)
    return layer


def boss_layer(img, kind, W, H, s, dx=None):
    if kind == "saints":
        # 圣徒双子：卡门（左，红边光）与伊比利亚（右，橙金边光）并立的剪影，各保留一点原色（帧条按亮度提亮的高光加色叠加）
        for i, (name, rim, hi) in enumerate([("e_carmen_slash@2x", (230, 60, 55), (255, 120, 90)), ("e_iberia_attack@2x", (235, 150, 60), (255, 200, 120))]):
            bf = frame(name, 4, 0, trim=True)   # @2x 出招帧条第 0 帧（蓄势），比 1× 待机帧细节多一倍
            kb = max(1, int(round(4 * s)))
            boss = up(bf, kb)
            if i == 0:
                boss = boss.transpose(Image.FLIP_LEFT_RIGHT)   # 两人相对而立
            bx = int(W * (0.40 if i == 0 else 0.62)) - boss.width // 2 + int((dx or 0.0) * W)
            by = int(H * 0.60) - boss.height
            put_glow(img, boss, rim, 9 * s, 7.0, (bx, by))
            img.alpha_composite(tint(boss, (20, 12, 16), keep=0.85), (bx, by))   # 人形剪影压太暗会糊成一团：保留八成五原色
            lum = boss.convert("L").point(lambda v: 0 if v < 140 else int((v - 140) * 2.2))
            lum = ImageChops.multiply(lum, boss.split()[3])
            hl = Image.new("RGBA", boss.size, hi + (0,))
            hl.putalpha(lum.point(lambda v: int(v * 0.6)))
            img = add(img, hl, (bx, by))
        return img
    if kind == "knight":
        # 骑士：骑马持枪的剪影一眼可读；放大后压成深蓝黑剪影 + 冷青边光，枪尖一点寒光
        bf = frame("e_knight", 2, 0, trim=True)
        kb = max(1, int(round(7 * s)))
        boss = up(bf, kb)
        bx, by = (W - boss.width) // 2 + int(40 * s), int(H * 0.60) - boss.height
        put_glow(img, boss, (80, 170, 230), 18 * s, 4.5, (bx, by))
        img.alpha_composite(tint(boss, (6, 10, 20), keep=0.14), (bx, by))
        return img
    # 泡影二阶段：深紫剪影，但保留壳的裂纹 / 洋红核心（原色按亮度提出来加色叠加），读得出「一只巨物」
    bf = frame("e_paranoia_phase2@2x", 2, 0)
    kb = max(1, int(round(5 * s)))
    boss = up(bf, kb)
    bx, by = (W - boss.width) // 2 + int((BOSS_DX if dx is None else dx) * W), int(BOSS_DY * H)
    put_glow(img, boss, (210, 40, 180), 20 * s, 4.5, (bx, by))
    img.alpha_composite(tint(boss, (12, 6, 22), keep=0.16), (bx, by))
    # 亮部（裂纹、核心）按亮度提取，洋红调加色叠加
    lum = boss.convert("L").point(lambda v: 0 if v < 120 else int((v - 120) * 1.9))
    lum = ImageChops.multiply(lum, boss.split()[3])
    hi = Image.new("RGBA", boss.size, (255, 90, 190, 0))
    hi.putalpha(lum.point(lambda v: int(v * 0.8)))
    img = add(img, hi, (bx, by))
    core = Image.new("RGBA", boss.size, (255, 130, 210, 0))
    cm = Image.new("L", boss.size, 0)
    ImageDraw.Draw(cm).ellipse((boss.width * 0.36, boss.height * 0.24, boss.width * 0.64, boss.height * 0.5), fill=150)
    core.putalpha(ImageChops.multiply(cm.filter(ImageFilter.GaussianBlur(22 * s)), boss.split()[3]))
    return add(img, core, (bx, by))


def compose(W=1920, H=1080, boss_kind="paranoia", capsule=False):
    """capsule：商店胶囊版式——logo 放大占左半、编队三人（斯卡蒂 / 水月 / 铃兰）靠右、不写 slogan 与声明（小图上读不出）"""
    s = H / 1080.0
    full = SQUAD_OVERRIDE or SQUAD
    squad = [full[1], full[2], full[3]] if capsule else full
    img = Image.new("RGBA", (W, H))
    top, bot = (4, 7, 14), (10, 24, 40)
    d0 = ImageDraw.Draw(img)
    for y in range(H):
        t = y / (H - 1)
        d0.line([(0, y), (W, y)], fill=tuple(int(top[i] + (bot[i] - top[i]) * t) for i in range(3)) + (255,))
    sea_y = int(H * 0.86)
    foot = int(H * 0.93)
    # 灯塔（点亮）：画面右侧，暖光打向编队——和洋红 / 冷青的 Boss 冷暖对比。暖光先铺，Boss 剪影压在上面（不被洗成褐色）
    lh = frame("prop_lighthouse@2x", 2, 1, trim=True)
    kl = max(1, int(round(4 * s)))
    lh = up(lh, kl)
    lhx, lhy = int(W * 0.86) - lh.width // 2, sea_y + int(30 * s) - lh.height
    lamp = (lhx + lh.width // 2, lhy + int(lh.height * 0.2))
    if not capsule:
        img.alpha_composite(radial((W, H), lamp, int(460 * s), (255, 190, 110), 110))
    img.alpha_composite(radial((W, H), (W // 2, int(H * 0.86)), int(520 * s), (255, 190, 120), 80))
    img = boss_layer(img, boss_kind, W, H, s, 0.22 if capsule else None)
    if not capsule:
        img.alpha_composite(lh, (lhx, lhy))
    if not capsule:
        img = add(img, radial((W, H), lamp, int(70 * s), (255, 230, 160), 230), (0, 0))
    # 光束：从灯室斜向编队的一道淡光
    beam = Image.new("L", (W, H), 0)
    if not capsule:
        ImageDraw.Draw(beam).polygon([lamp, (int(W * 0.30), int(H * 0.62)), (int(W * 0.34), int(H * 0.98))], fill=105)
    beam = beam.filter(ImageFilter.GaussianBlur(40 * s))
    bl = Image.new("RGBA", (W, H), (255, 214, 150, 0))
    bl.putalpha(beam)
    img = add(img, bl, (0, 0))
    # 溟痕海面
    img.alpha_composite(Image.new("RGBA", (W, H - sea_y), (6, 20, 32, 255)), (0, sea_y))
    wave = load("fx_skadi_wave@2x")
    fw = wave.width // 6
    kw = max(1, int(round(2 * s)))
    x, i = -40, 0
    while x < W:
        f = tint(up(wave.crop((fw * (i % 3 + 1), 0, fw * (i % 3 + 2), wave.height)), kw), (20, 58, 78), keep=0.22)
        img.alpha_composite(f, (x, sea_y - f.height + int(18 * s)))
        x += f.width - int(30 * s)
        i += 1
    bub = load("fx_mire_bubble")
    rnd = random.Random(7)
    for _ in range(8):
        b = tint(up(bub.crop((0, 0, bub.height, bub.height)), max(1, int(round(2 * s)))), (150, 70, 190), keep=0.4)
        img.alpha_composite(b, (rnd.randrange(0, W - b.width), rnd.randrange(sea_y + int(30 * s), H - b.height)))
    # 编队：裁到像素包围盒再放大（原帧四周空白多），中间主控大一档，脚线压住海面
    k_side, k_mid = (7, 8) if capsule else (max(1, int(round(5 * s))), max(1, int(round(6 * s))))
    mid = len(squad) // 2
    frames = [(frame(n, c, 0, trim=True), k_mid if j == mid else k_side) for j, (n, c) in enumerate(squad)]
    gap = int(10 * s)
    ims = [up(f, k) for f, k in frames]
    total = sum(im.width for im in ims) + gap * (len(ims) - 1)
    x = (W - total) // 2 - int(60 * s) if not capsule else int(W * 0.97) - total
    placed = []
    for j, im in enumerate(ims):
        y = foot - im.height
        sh = Image.new("RGBA", (int(im.width * 0.8), int(30 * s)), (0, 0, 0, 0))
        ImageDraw.Draw(sh).ellipse((0, 0, sh.width - 1, sh.height - 1), fill=(0, 0, 0, 170))
        img.alpha_composite(sh.filter(ImageFilter.GaussianBlur(5 * s)), (x + (im.width - sh.width) // 2, foot - int(18 * s)))
        put_glow(img, im, (255, 206, 140), 12 * s, 0.9, (x, y))
        if x + im.width // 2 > W * 0.5:
            # 灯塔一侧的暖边光：向灯塔方向错开几像素的亮橙外光，越靠近灯塔越强（冷暖对比）
            kk = min(1.0, (x + im.width / 2 - W * 0.5) / (W * 0.3))
            put_glow(img, im, (255, 170, 80), 7 * s, 0.9 + 1.2 * kk, (x + int(6 * s), y - int(2 * s)))
        img.alpha_composite(im, (x, y))
        placed.append((x, y, im))
        x += im.width + gap

    def fx_at(base, name, n, i, k, cx, cy, col=None):
        f = up(frame(name, n, i), k)
        if col:
            f = tint(f, col, keep=0.6)
        return add(base, f, (cx - f.width // 2, cy - f.height // 2))
    iS, iM, iZ = (0, 1, 2) if capsule else (1, 2, 3)
    sx, sy, sim = placed[iS]
    img = fx_at(img, "fx_skadi_surge@2x", 6, 2, max(1, int(round(3 * s))), sx + sim.width // 2, sy + sim.height - int(30 * s))
    zx, zy, zim = placed[iZ]
    img = fx_at(img, "fx_suzuran_wisp@2x", 4, 1, max(1, int(round(4 * s))), zx + zim.width + int(10 * s), zy + int(40 * s))
    img = fx_at(img, "fx_suzuran_wisp@2x", 4, 3, max(1, int(round(3 * s))), zx - int(10 * s), zy + int(10 * s))
    mx, my, mim = placed[iM]
    img = fx_at(img, "fx_mizuki_jelly@2x", 4, 0, max(1, int(round(4 * s))), mx - int(30 * s), my + int(60 * s))
    img = fx_at(img, "fx_mizuki_jelly@2x", 4, 2, max(1, int(round(4 * s))), mx + mim.width + int(20 * s), my + int(100 * s))
    # 暗角
    vig = Image.new("L", (W, H), 0)
    ImageDraw.Draw(vig).ellipse((-W * 0.15, -H * 0.25, W * 1.15, H * 1.25), fill=255)
    vig = vig.filter(ImageFilter.GaussianBlur(160 * s))
    dark = Image.new("RGBA", (W, H), (0, 0, 0, 255))
    dark.putalpha(vig.point(lambda v: int((255 - v) * 0.7)))
    img.alpha_composite(dark)
    # 标题：logo 左上；slogan 紧跟其下
    wide = W / H > 2.0
    lg = load("logo")
    if capsule:
        kl2 = 3 if wide else 2
        lg = up(lg, kl2)
        lx, ly = int(50 * s), (int(H * 0.36) if wide else int(H * 0.08))
    else:
        lg = up(lg, max(1, int(round(2 * s))))
        lx, ly = int(80 * s), int(56 * s)
    put_glow(img, lg, (90, 220, 230), 16 * s, 0.8, (lx, ly))
    img.alpha_composite(lg, (lx, ly))
    if capsule:
        return img.convert("RGB")
    d = ImageDraw.Draw(img)
    f1 = ImageFont.truetype(FONT_UI, int(56 * s))
    f2 = ImageFont.truetype(FONT_UI, int(30 * s))
    f3 = ImageFont.truetype(FONT_UI, int(14 * s))
    ty = ly + lg.height + int(12 * s)
    d.text((lx + int(8 * s), ty), SLOGAN_CN, font=f1, fill=(236, 240, 244, 255), stroke_width=max(1, int(3 * s)), stroke_fill=(4, 8, 14, 255))
    d.text((lx + int(10 * s), ty + int(72 * s)), SLOGAN_EN, font=f2, fill=(255, 206, 130, 255), stroke_width=max(1, int(2 * s)), stroke_fill=(4, 8, 14, 255))
    bb = d.textbbox((0, 0), NOTICE, font=f3)
    d.text((W - (bb[2] - bb[0]) - int(20 * s), H - int(26 * s)), NOTICE, font=f3, fill=(150, 160, 170, 200))
    return img.convert("RGB")


if __name__ == "__main__":
    args = sys.argv[1:]
    out = args[0] if args and not args[0].startswith("--") else os.path.join(ROOT, "build", "promo")
    opt = {"--size": "1920x1080", "--name": "keyart", "--boss": "paranoia", "--squad": ""}
    for i, a in enumerate(args):
        if a in opt and i + 1 < len(args):
            opt[a] = args[i + 1]
    W, H = (int(v) for v in opt["--size"].split("x"))
    if opt["--squad"]:
        SQUAD_OVERRIDE = [("player_idle@2x" if sid == "mizuki" else "op_%s_idle@2x" % sid, 4) for sid in opt["--squad"].split(",")]
    os.makedirs(out, exist_ok=True)
    if W < 1000:
        # 胶囊：按 1080 高的比例在 1080 高画布上排版（像素整数倍清楚），再整体缩到目标尺寸
        k = 1080.0 / H
        im = compose(int(round(W * k)), 1080, opt["--boss"], capsule=True).resize((W, H), Image.LANCZOS)
    else:
        im = compose(W, H, opt["--boss"])
    p = os.path.join(out, "%s_%s_%dx%d.png" % (opt["--name"], opt["--boss"], W, H))
    im.save(p, optimize=True)
    print(p, os.path.getsize(p) // 1024, "KB")
