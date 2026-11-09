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


_ENTRY = {}


def entry_frames(cid, k=10):
    """原作「入场」动作帧（data/characters/<id>.json sprites.entry，64 画布 @2x），整数倍最近邻放大；返回 (帧, 每帧秒数, 脚底点)"""
    if cid not in _ENTRY:
        d = json.load(open(WT + "/game/data/characters/%s.json" % cid, encoding="utf-8"))
        sp = d["sprites"]["entry"]
        s = Image.open(ART + "/operators/%s/%s@2x.png" % (cid, sp["tex"])).convert("RGBA")
        n = int(sp["frames"])
        fw = s.width // n
        frs = [s.crop((i * fw, 0, (i + 1) * fw, s.height)).resize((fw * k, s.height * k), Image.NEAREST) for i in range(n)]
        durs = sp.get("frame_durations") or [1.0 / float(sp.get("fps", 10))] * n
        foot = (sp["foot"][0] * 2 * k, sp["foot"][1] * 2 * k)
        _ENTRY[cid] = (frs, durs, foot)
    return _ENTRY[cid]


def _tint(fr, col, a):
    r = Image.new("RGBA", fr.size, col + (0,))
    r.putalpha(fr.getchannel("A").point(lambda v: int(v * a)))
    return r


def card_operator2(t, cid, dur, tag=""):
    """登场卡 v2（11-08 用户嫌旧卡简陋）：原作入场动作放大 10 倍 + 职业色残影 + 落地闪白 / 冲击环 / 震屏；
    背后职业色斜条滚动、速度线、空心大英文跑马；右侧中文名砸出 + 英文 + 职业标签；末 12 帧斜切条扫走"""
    import numpy as np
    name, en, cls, icon, col = OPS[cid]
    frs, durs, foot = entry_frames(cid)
    t_in = 0.06
    ends = np.cumsum(durs)
    land = t_in + ends[-1]
    lt = t - t_in
    fi = int(np.searchsorted(ends, lt, side="right")) if lt >= 0 else 0
    fi = min(fi, len(frs) - 1)
    # 震屏
    sh = 0
    if 0 <= t - land < 4 / FPS:
        sh = (8, -6, 5, -3)[int((t - land) * FPS)]
    im = Image.new("RGBA", (W, H), INK + (255,))
    d = ImageDraw.Draw(im)
    # 斜条滚动（职业色暗调）
    off = (t * 420) % 180
    dk = _shade(col, 0.22)
    for i in range(-2, 16):
        x0 = i * 180 - off
        d.polygon([(x0, 0), (x0 + 70, 0), (x0 + 70 - 420, H), (x0 - 420, H)], fill=dk + (255,))
    # 角色背后的主色斜块从左切入
    u = ease_out(t / 0.18)
    xr = -300 + 1300 * u
    d.polygon([(-10, 0), (xr + 260, 0), (xr - 160, H), (-10, H)], fill=_shade(col, 0.42) + (235,))
    d.polygon([(xr + 260, 0), (xr + 300, 0), (xr - 120, H), (xr - 160, H)], fill=col + (255,))
    # 空心大英文跑马（两行反向）
    g = glyph(en, 300, col, hollow=True)
    ga = _tint(g, col, 0.22)
    for row, (yy, sp) in enumerate(((150, -260), (930, 200))):
        x = (t * sp) % (g.width + 120)
        for k in range(-1, 3):
            im.alpha_composite(ga, (int(k * (g.width + 120) + (x if sp > 0 else -x)), int(yy - g.height / 2)))
    # 速度线（入场前半）
    if t < land + 0.1:
        rng = np.random.default_rng(int(t * FPS))
        for _ in range(26):
            y = int(rng.integers(120, H - 120))
            x = int(rng.integers(-200, W))
            ln = int(rng.integers(160, 620))
            d.rectangle((x, y, x + ln, y + int(rng.integers(2, 6))), fill=WHITE + (int(rng.integers(40, 150)),))
    grid(im, col, 96, 18)
    # 角色：入场动作 + 两层残影
    fx_, fy = 640 + sh, 1010
    for back, a in ((2, 0.18), (1, 0.38)):
        j = fi - back
        if j >= 0 and t < land + 0.15:
            gh = _tint(frs[j], col, a)
            im.alpha_composite(gh, (int(fx_ - foot[0] - 26 * back), int(fy - foot[1])))
    fr = frs[fi]
    bob = int(3 * math.sin((t - land) * 5.5)) if t > land else 0
    im.alpha_composite(fr, (int(fx_ - foot[0]), int(fy - foot[1] + bob)))
    # 落地：冲击环 + 闪白
    if t >= land:
        q = (t - land) / 0.35
        if q < 1:
            rx, ry = 120 + 520 * ease_out(q), 26 + 90 * ease_out(q)
            lay = Image.new("RGBA", (W, H), (0, 0, 0, 0))
            dl = ImageDraw.Draw(lay)
            wv = max(2, int(14 * (1 - q)))
            dl.ellipse((fx_ - rx, fy - ry, fx_ + rx, fy + ry), outline=WHITE + (int(255 * (1 - q)),), width=wv)
            dl.ellipse((fx_ - rx * 0.7, fy - ry * 0.7, fx_ + rx * 0.7, fy + ry * 0.7), outline=col + (int(200 * (1 - q)),), width=max(2, wv // 2))
            im.alpha_composite(lay)
        if t - land < 3 / FPS:
            im = Image.blend(im, Image.new("RGBA", (W, H), WHITE + (255,)), 0.55 * (1 - (t - land) * FPS / 3))
    # 右侧文字（落地前 0.15 秒开始）
    tt = t - (land - 0.15)
    nx = 1380
    if tt > 0:
        slam_text(im, name, tt, nx + sh, 430, 190 if len(name) < 4 else 160, WHITE, step=BEAT / 4, ghost=col)
    if tt > 0.25:
        a = ease_out((tt - 0.25) / 0.16)
        gE = glyph(en, 112, CYAN, hollow=True)
        paste_scaled(im, gE, nx + (1 - a) * 80, 610, 1.0, a)
    if tt > 0.36:
        lw = text_w(cls, 46) + 44 + 12
        label(im, cls, nx - lw / 2 + 50, 710, 46, slide=(tt - 0.36) / 0.14)
        if tt > 0.42:
            pi = Image.open(ART + "/ui/professions/%s.png" % icon).convert("RGBA").resize((84, 84), Image.NEAREST)
            im.alpha_composite(pi, (int(nx - lw / 2 - 50), 710))
        if tag and tt > 0.46:
            label(im, tag, nx - lw / 2 + 80 + lw, 710, 46, bg=col, fg=WHITE, slide=(tt - 0.46) / 0.14)
    so = 12 / FPS
    if dur - t < so:
        slash_bars(im, so - (dur - t), so, [col + (255,), WHITE + (255,), INK + (255,)])
    return im


_DEEP = {}


def _deep_bg(vw, vh, t):
    """深海底（对齐 3D 开头）：近黑海军蓝，上方一道斜光、少量悬浮颗粒，暗角"""
    import numpy as np
    if (vw, vh) not in _DEEP:
        yy = np.linspace(0, 1, vh)[:, None]
        xx = np.linspace(0, 1, vw)[None, :]
        base = np.array([2, 6, 13], np.float32)[None, None, :] * np.ones((vh, vw, 1), np.float32)
        d = np.abs((xx - 0.38) - (yy * 0.22))   # 斜光柱
        shaft = np.exp(-(d / 0.09) ** 2) * np.clip(1.2 - yy * 1.3, 0, 1)
        base = base + shaft[..., None] * np.array([18, 52, 70], np.float32)
        r = np.sqrt(((xx - 0.5) * 1.4) ** 2 + (yy - 0.5) ** 2)
        base = base * np.clip(1.15 - r * 0.9, 0.2, 1)[..., None]
        _DEEP[(vw, vh)] = base
    import numpy as np
    a = _DEEP[(vw, vh)].copy()
    rng = np.random.default_rng(3)
    pts = rng.random((70, 3))
    for x, y, s in pts:   # 颗粒缓慢上浮
        px, py = int(x * vw), int(((y - t * 0.03 * (0.5 + s)) % 1.0) * vh)
        rr = 1 + int(s * 2)
        a[max(0, py - rr):py + rr, max(0, px - rr):px + rr] += 60 * (0.4 + s)
    rng2 = np.random.default_rng(int(t * 30))
    a += rng2.normal(0, 4.0, (vh // 2 + 1, vw // 2 + 1)).repeat(2, 0).repeat(2, 1)[:vh, :vw, None]
    return Image.fromarray(np.clip(a, 0, 255).astype("uint8")).convert("RGBA")


def card_word_deep(t, text, sub="", dur=1.6, vw=W, vh=H):
    """大字卡 · 深海版：近黑底 + 斜光柱，白字带青色辉光逐字浮现（不砸、不放大），下方细青线 + 英文；同 3D 开头的调子"""
    im = _deep_bg(vw, vh, t)
    sz = int((300 if len(text) <= 3 else 220) * min(1.0, vw / W))
    f = font(sz)
    n = len(text)
    step = min(BEAT / 2, 0.4 * dur / max(1, n))
    gap = sz * 0.12
    ws = [f.getlength(c) for c in text]
    tw = sum(ws) + gap * (n - 1)
    x = vw / 2 - tw / 2
    cy = vh / 2 - sz * 0.15
    lay = Image.new("RGBA", (vw, vh), (0, 0, 0, 0))
    d = ImageDraw.Draw(lay)
    for k, c in enumerate(text):
        a = max(0.0, min(1.0, (t - k * step) / 0.18))
        if a > 0:
            dy = (1 - ease_out(a)) * 26
            d.text((x, cy - sz * 0.6 + dy), c, font=f, fill=(236, 246, 250, int(255 * a)))
        x += ws[k] + gap
    glow = lay.filter(ImageFilter.GaussianBlur(18))
    gl = Image.new("RGBA", (vw, vh), (90, 210, 255, 0))
    gl.putalpha(glow.getchannel("A").point(lambda v: int(v * 0.9)))
    im.alpha_composite(gl)
    im.alpha_composite(lay)
    u = ease_out((t - 0.1) / 0.4)
    yb = int(cy + sz * 0.82)
    bw = int(tw * 0.9 * u)
    d2 = ImageDraw.Draw(im)
    d2.rectangle((vw // 2 - bw // 2, yb, vw // 2 + bw // 2, yb + 3), fill=(110, 220, 255, 255))
    if sub and t > 0.2:
        fe = font(int(34 * min(1.0, vw / W)))
        a = int(220 * ease_out((t - 0.2) / 0.3))
        sw = fe.getlength(sub) + len(sub) * 10
        xx = vw / 2 - sw / 2
        for c in sub:
            d2.text((xx, yb + 26), c, font=fe, fill=(120, 200, 230, a))
            xx += fe.getlength(c) + 10
    return im
