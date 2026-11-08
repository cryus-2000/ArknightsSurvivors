# -*- coding: utf-8 -*-
"""PV 1108 文字卡 / 登场卡 / 字幕条 / 标题卡（1920×1080 RGBA，输入卡内秒数 t）。
风格：纯色斜切条 + 大字随鼓点逐字砸出（同游戏指挥台 / 面板的编辑式风格；fx.py 的元素沿用 11-02 小样）。
立绘只用本作像素待机帧（整数倍最近邻放大），不用原作官方立绘原图。"""
import json, math, os
from PIL import Image, ImageDraw, ImageFilter
from fx import *

SUB = (150, 164, 180)
FPS = 60
BEAT = P
ART = WT + "/game/art"
MAIN = os.path.dirname(os.path.dirname(os.path.dirname(WT))) if ".claude" in WT else WT
POSTER = MAIN + "/Claude outputs/cover_1107/final/toy_poster_notext_1200x900.png"

OPS = {
    # id: (名字, 英文, 职业（game/data/characters 的 class）, 职业图标, 主色)
    "mizuki": ("水月", "MIZUKI", "特种", "special", (120, 104, 236)),
    "skadi": ("斯卡蒂", "SKADI", "近卫", "warrior", (200, 46, 64)),
    "texas": ("德克萨斯", "TEXAS", "先锋", "pioneer", (236, 140, 52)),
}
_FR = {}


def idle_frames(cid):
    if cid not in _FR:
        d = json.load(open(WT + "/game/data/characters/%s.json" % cid, encoding="utf-8"))
        sp = d["sprites"]["idle"]
        tex = sp.get("tex", "op_%s_idle" % cid)
        p = ART + "/operators/%s/%s@2x.png" % (cid, tex)
        if not os.path.exists(p):
            p = ART + "/operators/%s/op_%s_idle@2x.png" % (cid, cid)
        s = Image.open(p).convert("RGBA")
        n = int(sp["frames"])
        fw = s.width // n
        frs = [s.crop((i * fw, 0, (i + 1) * fw, s.height)) for i in range(n)]
        bb = None
        for f in frs:
            b = f.getbbox()
            if b:
                bb = b if bb is None else (min(bb[0], b[0]), min(bb[1], b[1]), max(bb[2], b[2]), max(bb[3], b[3]))
        frs = [f.crop(bb) for f in frs]
        k = max(1, int(820 / frs[0].height))
        fps = float(sp.get("fps", 8.0))
        _FR[cid] = ([f.resize((f.width * k, f.height * k), Image.NEAREST) for f in frs], fps)
    return _FR[cid]


def _shade(c, k):
    return tuple(int(v * k) for v in c)


def card_operator(t, cid, dur):
    """登场卡：主色斜切大色块从左切入 + 像素待机帧放大 + 名字逐字砸出 + 空心英文 + 职业标签；末 6 帧斜切条扫走"""
    name, en, cls, icon, col = OPS[cid]
    frs, fps = idle_frames(cid)
    im = Image.new("RGBA", (W, H), INK + (255,))
    d = ImageDraw.Draw(im)
    u = ease_out(t / 0.16)
    xr = -200 + 1180 * u
    d.polygon([(-10, 0), (xr + 220, 0), (xr - 160, H), (-10, H)], fill=_shade(col, 0.32) + (255,))
    d.polygon([(xr + 220, 0), (xr + 252, 0), (xr - 128, H), (xr - 160, H)], fill=col + (255,))
    grid(im, col, 96, 22)
    fr = frs[int(t * fps) % len(frs)]
    sx = 540 - (1 - u) * 320
    im.alpha_composite(fr, (int(sx - fr.width / 2), int(H / 2 - fr.height / 2 + 30)))
    nx = 1360
    slam_text(im, name, t - 0.08, nx, 420, 172 if len(name) < 4 else 150, WHITE, step=BEAT / 4, ghost=col)
    if t > 0.32:
        a = ease_out((t - 0.32) / 0.16)
        g = glyph(en, 112, CYAN, hollow=True)
        paste_scaled(im, g, nx + (1 - a) * 80, 600, 1.0, a)
    if t > 0.45:
        lw = text_w(cls, 46) + 44 + 12
        label(im, cls, nx - lw / 2 + 50, 700, 46, slide=(t - 0.45) / 0.14)
        if t > 0.52:
            pi = Image.open(ART + "/ui/professions/%s.png" % icon).convert("RGBA").resize((84, 84), Image.NEAREST)
            im.alpha_composite(pi, (int(nx - lw / 2 - 50), 700))
    so = 12 / FPS   # 斜切条扫走：三条依次（间隔 0.05 秒）盖满，最上面是墨色，切到下一镜不留整帧纯色
    if dur - t < so:
        slash_bars(im, so - (dur - t), so, [col + (255,), WHITE + (255,), INK + (255,)])
    return im


def caption(base, t, text, sub, y=780, col=CYAN, dur=99.0):
    """实机上的字幕条：左下斜切色带扫入 + 大字逐字砸出（八分音符一字）+ 小英文标签；末 0.2 秒整条向左扫出"""
    out_u = ease_out((t - (dur - 0.22)) / 0.22) if t > dur - 0.22 else 0.0
    sz = 92
    tw = text_w(text, sz, 0.04)
    lay = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(lay)
    u = ease_out(t / 0.14)
    x1 = (140 + tw + 150) * u
    sh = int(-out_u * (tw + 600))
    d.polygon([(sh - 40, y - 78), (sh + x1 + 40, y - 78), (sh + x1, y + 78), (sh - 40, y + 78)], fill=INK + (225,))
    d.polygon([(sh + x1 + 40, y - 78), (sh + x1 + 58, y - 78), (sh + x1 + 18, y + 78), (sh + x1, y + 78)], fill=col + (255,))
    d.rectangle((sh - 40, y + 78, sh + x1 * 0.6, y + 86), fill=col + (255,))
    if sub:
        label(lay, sub, sh + 120, y - 140, 30, slide=(t - 0.05) / 0.14)
    slam_text(lay, text, t - 0.06, sh + 140 + tw / 2, y, sz, WHITE, step=BEAT / 2, ghost=col, gap=0.04)
    base.alpha_composite(lay)


_POSTER = None


def poster_bg():
    global _POSTER
    if _POSTER is None:
        p = Image.open(POSTER).convert("RGBA")
        k = W / p.width
        p = p.resize((W, int(p.height * k)), Image.NEAREST)
        y0 = int((p.height - H) * 0.62)
        _POSTER = p.crop((0, y0, W, y0 + H))
    return _POSTER


_TITLE = None


def card_title(t, short=False, vw=W, vh=H):
    """标题卡：封面图（压暗）上像素标题砸出 + 英文 + 「B站 Toy 点开即玩」+ 同人声明；short = 竖版缩短版"""
    global _TITLE
    import promo_cover as C
    if _TITLE is None:
        _TITLE = (C.pixel_text(C.TITLE, 17, 8, (232, 226, 208), (138, 154, 168), outline=(3, 6, 12)),
                  C.pixel_text(C.TITLE_EN, 9, 4, CYAN, (30, 120, 130), outline=(3, 6, 12)))
    t1, t2 = _TITLE
    bg = poster_bg()
    if (vw, vh) != (W, H):
        k = vh / bg.height
        b2 = bg.resize((int(bg.width * k), vh), Image.NEAREST)
        x0 = (b2.width - vw) // 2
        bg = b2.crop((x0, 0, x0 + vw, vh))
    im = bg.copy()
    # 轻推近 + 压暗（标题下沉区更暗）
    zoom = 1.0 + 0.03 * min(1.0, t / 6.0)
    if zoom > 1.001:
        w2, h2 = int(vw * zoom), int(vh * zoom)
        im = im.resize((w2, h2), Image.BILINEAR).crop(((w2 - vw) // 2, (h2 - vh) // 2, (w2 - vw) // 2 + vw, (h2 - vh) // 2 + vh))
    dark = Image.new("RGBA", (vw, vh), (3, 6, 12, 150))
    im.alpha_composite(dark)
    d = ImageDraw.Draw(im)
    cy = int(vh * 0.30)
    d.polygon([(0, cy - 150), (vw, cy - 230), (vw, cy - 214), (0, cy - 134)], fill=CYAN + (255,))
    dy = 50 * vw / 1920
    d.polygon([(0, cy + 300 + dy), (vw, cy + 300 - dy), (vw, cy + 308 - dy), (0, cy + 308 + dy)], fill=PURPLE + (200,))
    tk = min(1.0, (vw - 120) / t1.width)
    s = tk * (1.0 + 0.9 * (1 - ease_out(t / 0.12)))
    paste_scaled(im, t1, vw / 2, cy, s, min(1, t / 0.06 + 0.2))
    if 0.12 < t < 0.6:
        u = (t - 0.12) / 0.48
        gh = t1.copy()
        gh.putalpha(gh.getchannel("A").point(lambda v: int(v * 0.5 * (1 - u))))
        paste_scaled(im, gh, vw / 2 + 20 * u, cy + 10 * u, tk * (1.0 + 0.25 * u))
    if t > 0.35:
        a = ease_out((t - 0.35) / 0.3)
        paste_scaled(im, t2, vw / 2, cy + 150 * tk + (1 - a) * 30, tk, a)
    t_cta = 2 * BEAT if short else 4 * BEAT
    yc = int(vh * (0.70 if short else 0.76))
    if t > t_cta:
        txt = "B站 Toy 免费玩" if short else "B站 Toy 点开即玩"
        sz = 76 if vw >= 1600 else 70
        tw = text_w(txt, sz)
        lay = Image.new("RGBA", (vw, vh), (0, 0, 0, 0))
        dd = ImageDraw.Draw(lay)
        u = ease_out((t - t_cta) / 0.14)
        bx0, bx1 = vw / 2 - tw / 2 - 60, vw / 2 - tw / 2 - 60 + (tw + 120) * u
        dd.polygon([(bx0, yc - 62), (bx1 + 24, yc - 62), (bx1, yc + 62), (bx0 - 24, yc + 62)], fill=INK + (230,))
        dd.rectangle((bx0 - 24, yc + 62, bx1, yc + 68), fill=CYAN + (255,))
        im.alpha_composite(lay)
        slam_text(im, txt, t - t_cta - 0.05, vw / 2, yc, sz, WHITE, step=BEAT / 4, ghost=CYAN)
    # 同人声明：标题落下就在（全程可见）
    a = ease_out((t - 0.5) / 0.4)
    if a > 0:
        f = font(34 if vw >= 1600 else 36)
        txt = "明日方舟同人 · Arknights fan work"
        lay = Image.new("RGBA", (vw, vh), (0, 0, 0, 0))
        ImageDraw.Draw(lay).text((vw / 2 - f.getlength(txt) / 2, vh - (120 if vw >= 1600 else 300)), txt, font=f,
                                 fill=(206, 214, 222, int(255 * a)), stroke_width=3, stroke_fill=(3, 6, 12, int(230 * a)))
        im.alpha_composite(lay)
    return im


_NOISE = None


def _paper(vw, vh):
    """大字卡底：近黑墨色 + 纸纹噪点 + 细网格（参考官方水月 PV 的灰纸 / 水墨底，压暗成本作 UI 的墨色）"""
    global _NOISE
    if _NOISE is None or _NOISE.size != (vw, vh):
        import numpy as np
        rng = np.random.default_rng(7)
        n = rng.normal(0, 1, (vh // 4 + 1, vw // 4 + 1))
        n = np.kron(n, np.ones((4, 4)))[:vh, :vw]
        base = np.array(INK, np.float32)[None, None, :] + n[..., None] * 3.2
        yy = np.linspace(-1, 1, vh)[:, None]
        xx = np.linspace(-1, 1, vw)[None, :]
        vig = 1.0 + 0.9 * np.exp(-(xx ** 2 * 1.4 + yy ** 2 * 2.2))
        base = base * vig[..., None]
        _NOISE = Image.fromarray(np.clip(base, 0, 255).astype("uint8")).convert("RGBA")
        grid(_NOISE, (40, 60, 72), step=96, a=26)
    return _NOISE.copy()


def card_word(t, text, sub="", dur=1.6, col=CYAN, vw=W, vh=H, step=None):
    """全屏大字卡（术曲 PV 排版）：墨色纸纹底，大字逐字砸在八分音符上；「，」处分两行；下方空心英文 + 一道主色条从左扫入"""
    im = _paper(vw, vh)
    lines = [s for s in text.replace("，", "，\n").split("\n") if s]
    sz = int((300 if len(text) <= 3 else 240 if len(lines) == 1 and len(text) <= 6 else 190) * min(1.0, vw / W))
    n = len(text.replace("，", ""))
    step = step or min(BEAT / 2, 0.45 * dur / max(1, n))
    gap = 0.06
    lh = sz * 1.25
    y0 = vh / 2 - (len(lines) - 1) * lh / 2 - (40 if sub else 0)
    k0 = 0
    for i, ln in enumerate(lines):
        slam_text(im, ln, t - k0 * step, vw / 2, y0 + i * lh, sz, WHITE, step=step, ghost=col, gap=gap)
        k0 += len(ln)
    d = ImageDraw.Draw(im)
    u = ease_out(t / 0.22)
    yb = int(y0 + (len(lines) - 1) * lh + sz * 0.75)
    bw = int(min(vw * 0.62, max(text_w(ln, sz, gap) for ln in lines) + 120) * u)
    d.rectangle((vw // 2 - bw // 2, yb, vw // 2 + bw // 2, yb + 8), fill=col + (255,))
    if sub and t > 0.12:
        f = font(int(52 * min(1.0, vw / W)))
        tw = f.getlength(sub)
        a = int(255 * ease_out((t - 0.12) / 0.2))
        d.text((vw / 2 - tw / 2, yb + 30), sub, font=f, fill=SUB + (a,))
    return im
