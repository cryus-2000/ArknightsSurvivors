# -*- coding: utf-8 -*-
"""商店封面 11-07 重做（itch 630×500 / B站 Toy 1200×900 4:3）：只用游戏内像素资产 + 实机截图。
  A 深海水母·水月主视觉：标题页沉船背景 + 发光水母 + 青光航标，水月大立像
  B 小队迎海嗣潮：水月 + 深海猎人四人，对面海嗣大群与 Boss
  C 实机割草：GCP 实机满屏截图（tools/gcp/render_jobs/cover_shots.sh）+ 标题字
每个元素按整数倍最近邻放大，不先画大图再缩。
用法：python tools/promo_cover_1107.py <输出目录> [--shot <实机截图 png>] [--only A,B,C] [--sheet]
"""
import os, sys, random, argparse
from PIL import Image, ImageDraw, ImageFilter, ImageChops, ImageEnhance
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import promo_cover as PC

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
ART = os.path.join(ROOT, "game", "art")
NOTICE = "明日方舟同人 · 非官方"
CYAN = (110, 225, 240)
SIZES = {"itch": (630, 500), "toy": (1200, 900)}


def load(rel):
    return Image.open(os.path.join(ART, rel)).convert("RGBA")


def frame(rel, i=0, trim=True):
    im = load(rel)
    h = im.height
    n = max(1, im.width // h)
    fr = im.crop(((i % n) * h, 0, (i % n + 1) * h, h)) if n > 1 else im
    return fr.crop(fr.getbbox()) if trim else fr


def up(im, k):
    return im.resize((im.width * k, im.height * k), Image.NEAREST) if k != 1 else im


def glow_of(im, col, radius, strength=1.0):
    """返回比原图四周各大 3×radius 的光晕（不补边会在画布边被截成矩形）"""
    p = int(radius * 3)
    a = Image.new("L", (im.width + 2 * p, im.height + 2 * p), 0)
    a.paste(im.split()[3], (p, p))
    a = a.filter(ImageFilter.GaussianBlur(radius))
    if strength != 1.0:
        a = a.point(lambda v: min(255, int(v * strength)))
    g = Image.new("RGBA", a.size, col + (0,))
    g.putalpha(a)
    return g


def shine(base, im, col, radius, strength, xy):
    p = int(radius * 3)
    add_light(base, glow_of(im, col, radius, strength), (xy[0] - p, xy[1] - p))


def add_light(base, light_rgba, xy):
    """加色叠光（像水下发光）：只取 RGB×alpha 加到底图上"""
    l = Image.new("RGBA", base.size, (0, 0, 0, 0))
    l.paste(light_rgba, (int(xy[0]), int(xy[1])))
    r, g, b, a = l.split()
    rgb = Image.merge("RGB", (ImageChops.multiply(r, a), ImageChops.multiply(g, a), ImageChops.multiply(b, a)))
    out = ImageChops.add(base.convert("RGB"), rgb)
    out = out.convert("RGBA")
    base.paste(out)


def radial(size, r, col, strength=1.0):
    w, h = size
    m = Image.new("L", size, 0)
    d = ImageDraw.Draw(m)
    steps = 40
    for i in range(steps):
        t = i / steps
        rr = r * (1 - t)
        v = int(255 * strength * (t ** 1.6))
        d.ellipse((w / 2 - rr, h / 2 - rr, w / 2 + rr, h / 2 + rr), fill=v)
    m = m.filter(ImageFilter.GaussianBlur(r * 0.08))
    g = Image.new("RGBA", size, col + (0,))
    g.putalpha(m)
    return g


def put(base, im, cx, foot):
    """以底边中点定位贴精灵"""
    x, y = int(cx - im.width / 2), int(foot - im.height)
    tmp = Image.new("RGBA", base.size, (0, 0, 0, 0))
    tmp.paste(im, (x, y), im)
    base.alpha_composite(tmp)
    return x, y


def bg_title(W, H, k, x_off=0.5, dark=0.85):
    """标题页沉船背景（428×240）整数倍放大，宽高不够时上下补边色"""
    bg = load("ui/title_deep/bg.png")
    bg = up(bg, k)
    out = Image.new("RGBA", (W, H))
    # 先用顶 / 底一行颜色铺满，再贴图，底部对齐
    top = bg.crop((0, 0, bg.width, 1)).resize((W, H)) if False else None
    x = -int((bg.width - W) * x_off)
    y = H - bg.height
    if y > 0:
        out.paste(bg.crop((0, 0, bg.width, 1)).resize((bg.width, y)), (x, 0))
    out.paste(bg, (x, y))
    return ImageEnhance.Brightness(out).enhance(dark)


def jelly(base, which, k, cx, cy, strength=1.0, flip=False):
    j = load("ui/title_deep/jelly_%d.png" % which)
    gl = load("ui/title_deep/jglow_%d.png" % which)
    if flip:
        j, gl = j.transpose(Image.FLIP_LEFT_RIGHT), gl.transpose(Image.FLIP_LEFT_RIGHT)
    j, gl = up(j, k), up(gl, k)
    # 发光图是黑底灰度：当作亮度，染青色加到底图
    lum = gl.convert("L").point(lambda v: min(255, int(v * strength)))
    g = Image.new("RGBA", gl.size, CYAN + (0,))
    g.putalpha(lum)
    add_light(base, g, (cx - gl.width // 2, cy - gl.height // 2))
    tmp = Image.new("RGBA", base.size, (0, 0, 0, 0))
    tmp.paste(j, (cx - j.width // 2, cy - j.height // 2), j)
    base.alpha_composite(tmp)


def logo(k):
    """标题页像素 Logo（logo_mark.png 是 2 像素格，先还原成 1 像素格再按 k 放大）"""
    lg = load("ui/title_deep/logo_mark.png")
    lg = lg.resize((lg.width // 2, lg.height // 2), Image.NEAREST)
    lg = up(lg, k)
    # 描边 + 下投影，压在任何背景上都读得出
    a = lg.split()[3]
    ol = a.filter(ImageFilter.MaxFilter(2 * k + 1 if k > 1 else 3))
    out = Image.new("RGBA", (lg.width + 4 * k, lg.height + 6 * k), (0, 0, 0, 0))
    sh = Image.new("RGBA", lg.size, (4, 10, 20, 255))
    out.paste(sh, (2 * k, 4 * k), ol)
    out.paste(sh, (2 * k, 2 * k), ol)
    out.paste(lg, (2 * k, 2 * k), lg)
    return out


def notice(k):
    return PC.pixel_text(NOTICE, 12, k, (200, 225, 232), (150, 180, 192))


def title_block(base, k, x, y, anchor="center", glow=True):
    lg = logo(k)
    if anchor == "center":
        x = x - lg.width // 2
    if glow:
        shine(base, lg, (40, 120, 150), 8 * k, 0.9, (x, y))
    base.alpha_composite(lg, (x, y))
    nt = notice(max(1, k - 1) if k > 2 else k)
    nx = x + lg.width - nt.width - 2 * k
    base.alpha_composite(nt, (nx, y + lg.height + 1 * k))


def vignette(base, strength=0.55):
    W, H = base.size
    m = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(m)
    for i in range(30):
        t = i / 30
        d.rectangle((W * t * 0.12, H * t * 0.12, W * (1 - t * 0.12), H * (1 - t * 0.12)), fill=int(255 * t))
    m = m.filter(ImageFilter.GaussianBlur(W * 0.04))
    dark = Image.new("RGBA", (W, H), (2, 5, 12, 255))
    inv = m.point(lambda v: int((255 - v) * strength))
    base.paste(dark, (0, 0), inv)


def top_shade(base, frac, strength=0.75):
    W, H = base.size
    m = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(m)
    hh = int(H * frac)
    for y in range(hh):
        d.line([(0, y), (W, y)], fill=int(255 * strength * (1 - y / hh) ** 1.3))
    base.paste(Image.new("RGBA", (W, H), (2, 6, 14, 255)), (0, 0), m)


def sprite_with_rim(base, spr, cx, foot, rim=CYAN, rim_r=3, rim_s=1.6, halo=None):
    if halo:
        hr, hs = halo
        h = radial((int(hr * 2), int(hr * 2)), hr, rim, hs)
        add_light(base, h, (cx - hr, foot - spr.height * 0.55 - hr))
    shine(base, spr, rim, rim_r, rim_s, (cx - spr.width // 2, foot - spr.height))
    put(base, spr, cx, foot)


# ---------------- 方向 A：水月主视觉 ----------------
def dir_A(kind):
    W, H = SIZES[kind]
    k = 2 if kind == "itch" else 4
    img = bg_title(W, H, k, x_off=0.55, dark=0.9)
    s = k / 2   # 相对 itch 的倍数
    jelly(img, 0, k, int(W * 0.78), int(H * 0.50), 1.3)
    jelly(img, 1, k, int(W * 0.60), int(H * 0.36), 1.2, flip=True)
    jelly(img, 2, k, int(W * 0.92), int(H * 0.26), 1.1)
    jelly(img, 2, k, int(W * 0.10), int(H * 0.46), 0.9, flip=True)
    vignette(img, 0.5)
    miz = frame("operators/mizuki/mizuki_runtime_idle@2x.png", 0)
    ms = 4 if kind == "itch" else 7
    spr = up(miz, ms)
    cx, foot = int(W * 0.36), H - int(10 * s)
    sprite_with_rim(img, spr, cx, foot, rim_r=int(2 * s), rim_s=1.2, halo=(int(170 * s), 0.55))
    top_shade(img, 0.30, 0.7)
    title_block(img, k, W // 2, int(14 * s))
    return img.convert("RGB")


# ---------------- 方向 B：小队守灯标，海嗣从暗处围上来 ----------------
def silhouette(im, col=(6, 8, 16), keep=0.18):
    """压成深色剪影（保留一点原色）"""
    d = Image.new("RGBA", im.size, col + (255,))
    d.putalpha(im.split()[3])
    return Image.blend(d, im, keep)


def dir_B(kind):
    W, H = SIZES[kind]
    k = 2 if kind == "itch" else 4
    s = k / 2
    img = bg_title(W, H, k, x_off=0.15, dark=0.6)
    rnd = random.Random(7)
    # 远处 Boss 剪影（泡影二阶段）压在右上暗处
    boss = up(frame("enemies/paranoia/e_paranoia_phase2@2x.png", 0).transpose(Image.FLIP_LEFT_RIGHT), int(2 * s))
    shine(img, boss, (150, 50, 130), int(4 * s), 0.6, (int(W * 0.80) - boss.width // 2, int(H * 0.70) - boss.height))
    put(img, silhouette(boss, keep=0.22), int(W * 0.80), int(H * 0.70))
    jelly(img, 2, k, int(W * 0.10), int(H * 0.36), 0.9, flip=True)
    # 海嗣：左右两侧暗处围上来，只露剪影和一点紫色边光
    mobs = ["enemies/runner/e_runner@2x.png", "enemies/slider/e_slider@2x.png", "enemies/spitter/e_spitter@2x.png",
            "enemies/mimic/e_mimic@2x.png", "enemies/stone/e_stone@2x.png", "enemies/tracer/e_tracer@2x.png",
            "enemies/offspring/e_offspring@2x.png", "enemies/path/e_path@2x.png"]
    pts = []
    for i in range(16):
        side = 1
        x = W * rnd.uniform(0.70, 1.06)
        y = H * rnd.uniform(0.56, 0.72)
        pts.append((y, x, rnd.choice(mobs), rnd.randint(0, 5), side))
    pts.sort()
    for y, x, m, fi, side in pts:
        e = frame(m, fi)
        if side > 0:
            e = e.transpose(Image.FLIP_LEFT_RIGHT)
        e = up(e, int(2 * s))
        shine(img, e, (190, 70, 160), int(3 * s), 0.6, (int(x) - e.width // 2, int(y) - e.height))
        put(img, silhouette(e, keep=0.4), int(x), int(y))
    # 小队：博士居中伸手指向海嗣，水月冲在最前，深海猎人四人分列
    squad = [("operators/ulpianus/op_ulpianus_idle@2x.png", 0.13, 0.78, False), ("operators/skadi/op_skadi_idle@2x.png", 0.58, 0.74, False),
             ("operators/gladiia/op_gladiia_idle@2x.png", 0.90, 0.80, False),
             ("operators/specter_unchained/op_specter_unchained_idle@2x.png", 0.06, 1.0, False)]
    for rel, fx, fy, fl in squad:
        spr = up(frame(rel, 0), int(2 * s))
        if fl:
            spr = spr.transpose(Image.FLIP_LEFT_RIGHT)
        sprite_with_rim(img, ImageEnhance.Brightness(spr).enhance(0.85), int(W * fx), int(H * fy), rim_r=int(2 * s), rim_s=0.8)
    import promo_doctor_point as DP
    doc = ImageEnhance.Brightness(up(DP.doctor_point(), int(3 * s))).enhance(1.3)
    sprite_with_rim(img, doc, int(W * 0.30), int(H * 1.0), rim_r=int(3 * s), rim_s=2.2, halo=(int(170 * s), 0.8))
    miz = up(frame("operators/mizuki/mizuki_runtime_attack@2x.png", 3), int(3 * s))
    sprite_with_rim(img, miz, int(W * 0.72), int(H * 1.0), rim_r=int(2 * s), rim_s=1.2)
    vignette(img, 0.45)
    top_shade(img, 0.32, 0.8)
    title_block(img, k, W // 2, int(14 * s))
    return img.convert("RGB")


# ---------------- 方向 C：实机割草 ----------------
def dir_C(kind, shot, crop=None):
    W, H = SIZES[kind]
    src = Image.open(shot).convert("RGBA")
    k = 2 if kind == "itch" else 4
    s = k / 2
    # crop=(cx, cy, scale)：以 (cx, cy) 为中心，从截图里取 W/scale × H/scale 再按 scale 缩放
    cx, cy, sc = crop or (src.width / 2, src.height / 2, 0.5 if kind == "itch" else 0.8)
    cw, ch = W / sc, H / sc
    box = (int(cx - cw / 2), int(cy - ch / 2), int(cx + cw / 2), int(cy + ch / 2))
    img = src.crop(box).resize((W, H), Image.BOX if sc < 1 else Image.NEAREST)
    vignette(img, 0.35)
    top_shade(img, 0.34, 0.85)
    title_block(img, k, W // 2, int(14 * s))
    return img.convert("RGB")


def thumbs(img, kind):
    """平台列表里的小图：itch 网格 315×250 / 小 158×125；Toy 卡片约 320×240 / 小 160×120"""
    sz = [(315, 250), (158, 125)] if kind == "itch" else [(320, 240), (160, 120)]
    return [img.resize(z, Image.LANCZOS) for z in sz]


PITCH = {"A": "A 水月主视觉：深海水母 + 青光，水月大立像，缩到最小也认得出人和标题",
         "B": "B 小队守灯标：水月 + 深海猎人四人，海嗣从暗处围上来（小队代入感）",
         "C": "C 实机割草：GCP 实机满屏截图，画面就是游戏里的样子（割草爽感）"}


def sheet(res, path):
    from PIL import ImageFont
    f = ImageFont.truetype(PC.K.FONT_UI, 26)
    fs = ImageFont.truetype(PC.K.FONT_UI, 16)
    ds = sorted({d for d, _ in res})
    RH = 44 + 540 + 30
    W = 1357 + 500
    out = Image.new("RGB", (W, 20 + RH * len(ds)), (18, 22, 30))
    dr = ImageDraw.Draw(out)
    for r, d in enumerate(ds):
        y = 20 + r * RH
        dr.text((20, y), PITCH[d], font=f, fill=(230, 236, 240))
        y += 44
        it, ty = res[(d, "itch")], res[(d, "toy")]
        out.paste(it, (20, y))
        out.paste(ty.resize((667, 500), Image.LANCZOS), (670, y))
        x = 1357
        t1, t2 = thumbs(it, "itch")
        u1, u2 = thumbs(ty, "toy")
        dr.text((x, y - 4), "缩略图 itch 315×250 / 158×125", font=fs, fill=(160, 170, 180))
        out.paste(t1, (x, y + 16)); out.paste(t2, (x + 325, y + 16 + 125))
        dr.text((x, y + 272), "缩略图 Toy 320×240 / 160×120", font=fs, fill=(160, 170, 180))
        out.paste(u1, (x, y + 292)); out.paste(u2, (x + 330, y + 292 + 120))
    out.save(path)
    print(path)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out")
    ap.add_argument("--shot")
    ap.add_argument("--crop_itch")
    ap.add_argument("--crop_toy")
    ap.add_argument("--only", default="A,B,C")
    ap.add_argument("--sheet")
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    res = {}
    for d in a.only.split(","):
        for kind in ("itch", "toy"):
            if d == "A":
                im = dir_A(kind)
            elif d == "B":
                im = dir_B(kind)
            else:
                if not a.shot:
                    continue
                cr = getattr(a, "crop_" + kind)
                im = dir_C(kind, a.shot, tuple(float(v) for v in cr.split(",")) if cr else None)
            p = os.path.join(a.out, "%s_%s_%dx%d.png" % (d, kind, im.width, im.height))
            im.save(p)
            res[(d, kind)] = im
            print(p)
    if a.sheet:
        sheet(res, a.sheet)
    return res


if __name__ == "__main__":
    main()
