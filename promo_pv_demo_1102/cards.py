# -*- coding: utf-8 -*-
"""文字卡 / 登场卡 / 标题卡：输入卡内秒数 t，返回 1920x1080 RGBA"""
import math, json
from PIL import Image, ImageDraw
from fx import *

SUB = (150, 164, 180)


def card_squad(t):
    """「带上你的小队」：黑底 + 青色斜带 + 逐字砸出（八分音符一个字）"""
    im = Image.new("RGBA", (W, H), INK + (255,))
    grid(im, CYAN, 120, 22, off=int(t * 60))
    d = ImageDraw.Draw(im)
    sk = 260
    d.polygon([(0, 640), (W, 420), (W, 640), (0, 860)], fill=(20, 60, 66, 255))
    d.polygon([(0, 700), (W, 480), (W, 500), (0, 720)], fill=CYAN + (255,))
    label(im, "SQUAD", 150, 250, 40, slide=min(1, t / 0.15))
    slam_text(im, "带上你的小队", t - 0.02, W / 2, H / 2 - 20, 190, WHITE, step=P / 2, ghost=CYAN, stroke=0)
    if t < 0.2:
        slash_bars(im, t, 0.2, [CYAN + (255,), WHITE + (255,), PURPLE + (255,)], out=True)
    return im


_TX = None


def card_operator(t):
    """登场卡：德克萨斯（像素待机帧放大）+ 名字 + 英文空心字 + 职业标签；先锋 · 尖兵按 game/data/characters/texas.json"""
    global _TX
    if _TX is None:
        s = Image.open(WT + "/game/art/operators/texas/op_texas_idle@2x.png").convert("RGBA")
        n = 7
        fw = s.width // n
        _TX = [s.crop((i * fw, 0, (i + 1) * fw, s.height)).resize((fw * 7, s.height * 7), Image.NEAREST) for i in range(n)]
    im = Image.new("RGBA", (W, H), INK + (255,))
    d = ImageDraw.Draw(im)
    u = ease_out(t / 0.18)
    # 紫色斜切大色块从左切入
    xr = -200 + 1180 * u
    d.polygon([(-10, 0), (xr + 220, 0), (xr - 160, H), (-10, H)], fill=(58, 40, 110, 255))
    d.polygon([(xr + 220, 0), (xr + 250, 0), (xr - 130, H), (xr - 160, H)], fill=PURPLE + (255,))
    grid(im, PURPLE, 96, 26)
    fr = _TX[int(t * 3.5 * 1.6) % len(_TX)]
    sx = 520 - (1 - u) * 300
    im.alpha_composite(fr, (int(sx - fr.width / 2), int(H / 2 - fr.height / 2 + 20)))
    # 名字 + 英文
    slam_text(im, "德克萨斯", t - 0.2, 1340, 430, 170, WHITE, step=P / 2, ghost=PURPLE)
    if t > 1.0:
        a = ease_out((t - 1.0) / 0.2)
        g = glyph("TEXAS", 120, CYAN, hollow=True)
        paste_scaled(im, g, 1340 + (1 - a) * 80, 600, 1.0, a)
    if t > 1.2:
        label(im, "先锋 · 尖兵", 1110, 700, 44, slide=(t - 1.2) / 0.16)
        pi = Image.open(WT + "/game/art/ui/professions/pioneer.png").convert("RGBA").resize((84, 84), Image.NEAREST)
        if t > 1.35:
            im.alpha_composite(pi, (1010, 700))
    return im


def card_lamp(t):
    """「灯火之外，皆是敌人」：莱茵白底黑字（反色段），青色菱形线框转动；前半句十六分音符逐字、后半句从第三拍起"""
    im = Image.new("RGBA", (W, H), RHINE + (255,))
    d = ImageDraw.Draw(im)
    cx, cy = W / 2, H / 2
    for k, r in enumerate([620, 470]):
        a = t * (0.6 if k == 0 else -0.9) + math.pi / 4
        pts = [(cx + r * math.cos(a + i * math.pi / 2), cy + r * math.sin(a + i * math.pi / 2)) for i in range(4)]
        d.line(pts + [pts[0]], fill=CYAN + (255,), width=10 if k == 0 else 4)
    label(im, "LAMPLIGHT", 150, 170, 40, bg=INK, fg=RHINE, slide=min(1, t / 0.15))
    slam_text(im, "灯火之外，", t, cx - 90, cy - 110, 170, INK, step=P / 4, ghost=PURPLE)
    slam_text(im, "皆是敌人", t - 2 * P, cx + 130, cy + 110, 170, INK, step=P / 4, ghost=CYAN)
    return im


_TITLE = None


def card_title(t):
    """片名：静默一拍后砸出像素标题；第二小节「免费试玩 · itch / B站」，第三小节同人声明"""
    global _TITLE
    import promo_cover as C
    if _TITLE is None:
        _TITLE = (C.pixel_text(C.TITLE, 17, 8, (232, 226, 208), (138, 154, 168), outline=(3, 6, 12)),
                  C.pixel_text(C.TITLE_EN, 9, 4, CYAN, (30, 120, 130), outline=(3, 6, 12)))
    t1, t2 = _TITLE
    im = Image.new("RGBA", (W, H), NAVY + (255,))
    d = ImageDraw.Draw(im)
    B = 4 * P
    # 冷色斜条底纹
    d.polygon([(0, 300), (W, 160), (W, 200), (0, 340)], fill=(16, 44, 54, 255))
    d.polygon([(0, 760), (W, 620), (W, 640), (0, 780)], fill=(36, 28, 70, 255))
    s = 1.0 + 0.9 * (1 - ease_out(t / 0.12))
    paste_scaled(im, t1, W / 2, 390, s, min(1, t / 0.06 + 0.2))
    if t > 0.12 and t < 0.6:
        u = (t - 0.12) / 0.48
        gh = t1.copy()
        gh.putalpha(gh.getchannel("A").point(lambda v: int(v * 0.5 * (1 - u))))
        paste_scaled(im, gh, W / 2 + 20 * u, 390 + 10 * u, 1.0 + 0.25 * u)
    if t > 0.35:
        a = ease_out((t - 0.35) / 0.3)
        paste_scaled(im, t2, W / 2, 540 + (1 - a) * 30, 1.0, a)
    if t > B:
        slam_text(im, "免费试玩", t - B, W / 2 - 250, 700, 76, WHITE, step=P / 4, ghost=CYAN)
        slam_text(im, "·", t - B - P, W / 2 - 25, 700, 76, SUB, step=P, ghost=None)
        slam_text(im, "itch / B站", t - B - P, W / 2 + 230, 700, 76, CYAN, step=P / 8, ghost=PURPLE)
    if t > 2 * B:
        a = ease_out((t - 2 * B) / 0.4)
        f = font(30)
        txt = "非官方同人作品，与鹰角网络无关"
        lay = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        ImageDraw.Draw(lay).text((W / 2 - f.getlength(txt) / 2, 900), txt, font=f, fill=SUB + (int(255 * a),))
        im.alpha_composite(lay)
    return im
