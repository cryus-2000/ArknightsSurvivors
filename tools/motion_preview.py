# -*- coding: utf-8 -*-
"""界面动效预览（docs/62）：用当前版本的真实截图做底，PIL 逐帧模拟各界面的「招牌动效」，拼成一段 MP4。

只是给人看的预览，不改游戏代码；画面里的元素是从截图里裁出来再按动效曲线摆放的，个别界面（事件页）截不到时用合成示意。

用法：
    python tools/motion_preview.py --capture          # 先用 Godot 截一轮当前界面（开窗口但不抢焦点、静音，docs/36 §5），再出片
    python tools/motion_preview.py                    # 用已有截图出片
    python tools/motion_preview.py --stills           # 另存每段几张关键帧 PNG（核对用）
    python tools/motion_preview.py --only levelup,shop

输出：主仓库 build/motion/motion_preview.mp4（1280×720、30 fps、H.264 yuv420p、+faststart），截图在 build/motion/shots/。
每段在屏幕下方标中文界面名，连放两遍。
"""
import argparse, math, os, random, subprocess, sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

TOOLS = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(TOOLS)
sys.path.insert(0, TOOLS)
import godot_runner as gr  # noqa: E402

W, H, FPS = 1280, 720, 30
OUT_DIR = os.path.join(gr.common_root(ROOT), "build", "motion")
SHOT_DIR = os.path.join(OUT_DIR, "shots")

# docs/37 色板
CYAN = (54, 226, 220)
GOLD = (244, 192, 78)
RED = (255, 61, 139)
TEXT = (242, 244, 245)
SUB = (154, 163, 173)
PANEL = (22, 25, 31)

# ---------------------------------------------------------------- 截图

CAPTURE = {
    # 目录名: (Godot 参数, 要用的文件)。自动测试局里截到哪个面板受帧率与 seed 影响（--max-fps 20 让面板入场动画来得及播完），
    # 个别缺图或截到的不是想要的面板（例如商店被升级面板顶掉）就换 seed 重跑这一项：--capture 之后看终端里的「缺」
    "title": (["--titleshot"], "shot_title.png"),
    "settings": (["--settingsshot"], "shot_settings.png"),
    "diff": (["--diffshot=1,2"], "shot_diff_1_2.png"),
    "loading": (["--loadingshot"], "shot_loading.png"),
    "levelup": (["--autotest", "--eventtest=whisper", "--seed=3"], "shot_choice.png"),
    "recruit": (["--autotest", "--fastlevel", "--seed=3", "--shots=200"], "shot_choice.png"),
    "play": (["--autotest", "--fastlevel", "--seed=3", "--shots=200"], "shot_200.png"),
    "relic": (["--autotest", "--relicshot", "--seed=3"], "shot_choice.png"),
    "shop": (["--autotest", "--fastlevel", "--seed=3", "--shots=200"], "shot_shop.png"),
    "win": (["--autotest", "--winshot=standard", "--seed=3"], "shot_win.png"),
}


def capture(names):
    import concurrent.futures as cf
    game = os.path.join(ROOT, "game")
    gr.ensure_imported(game)
    godot = gr.find_godot()

    def run(k):
        d = os.path.join(SHOT_DIR, k)
        os.makedirs(d, exist_ok=True)
        args = [godot, "--path", game, "--resolution", "%dx%d" % (W, H), "--max-fps", "20", "--", "--shotdir=" + d] + CAPTURE[k][0]
        gr.run_godot(args, 90)   # 自动测试局截完图不一定自己退出，超时由 runner 按 PID 结束
        return k, os.path.exists(os.path.join(d, CAPTURE[k][1]))

    with cf.ThreadPoolExecutor(4) as ex:
        for k, ok in ex.map(run, names):
            print("截图 %-9s %s" % (k, "好" if ok else "缺（%s）" % CAPTURE[k][1]), flush=True)


def shot(name):
    p = os.path.join(SHOT_DIR, name, CAPTURE[name][1])
    im = Image.open(p).convert("RGBA")
    if im.size != (W, H):
        raise SystemExit("截图尺寸不对（%s %s），重跑 --capture" % (p, im.size))
    return im

# ---------------------------------------------------------------- 曲线与小工具（与 docs/62 §2 的缓动集合一一对应）


def clamp(x, a=0.0, b=1.0):
    return max(a, min(b, x))


def seg(t, t0, dur):
    return clamp((t - t0) / dur)


def out_cubic(x):
    return 1 - (1 - x) ** 3


def in_out_cubic(x):
    return 4 * x ** 3 if x < 0.5 else 1 - (-2 * x + 2) ** 3 / 2


def out_back(x, s=1.4):
    x -= 1
    return 1 + (s + 1) * x ** 3 + s * x ** 2


def in_quad(x):
    return x * x


def steps(x, n):
    return math.floor(clamp(x) * n) / n


def lerp(a, b, k):
    return a + (b - a) * k


def lerp_col(a, b, k):
    return tuple(int(lerp(a[i], b[i], k)) for i in range(3))


def rgba(c, a):
    return (int(c[0]), int(c[1]), int(c[2]), int(clamp(a) * 255))


_fonts = {}


def font(size, serif=False):
    key = (size, serif)
    if key not in _fonts:
        p = os.path.join(ROOT, "game", "fonts", "serif.ttf" if serif else "ui.ttf")
        _fonts[key] = ImageFont.truetype(p, size)
    return _fonts[key]


def layer():
    return Image.new("RGBA", (W, H), (0, 0, 0, 0))


def with_alpha(im, a):
    if a >= 1.0:
        return im
    im = im.copy()
    im.putalpha(im.getchannel("A").point(lambda v: int(v * clamp(a))))
    return im


def scaled(im, sx, sy):
    w, h = max(1, int(im.width * sx)), max(1, int(im.height * sy))
    return im.resize((w, h), Image.NEAREST)


def shake(im, amp, t):
    if amp <= 0.3:
        return im
    dx = int(round(math.sin(t * 91.0) * amp))
    dy = int(round(math.cos(t * 73.0) * amp))
    out = Image.new("RGBA", (W, H), (0, 0, 0, 255))
    out.paste(im, (dx, dy))
    return out


def darken(im, k, tint=(0, 0, 0)):
    over = Image.new("RGBA", im.size, tint + (int(255 * clamp(k)),))
    out = im.copy()
    out.alpha_composite(over)
    return out


def erase_rects(base, rects, blur=26):
    """把卡片从截图里抹掉：卡片区填卡片之间缝隙的平均色（面板后面压暗的世界），再整体模糊，只取回这些区域"""
    gaps = [(rects[i][0] + rects[i][2] + 4, rects[i][1] + 10, rects[i + 1][0] - 4, rects[i][1] + rects[i][3] - 10) for i in range(len(rects) - 1)]
    cols = [base.crop(g).convert("RGB").resize((1, 1), Image.BOX).getpixel((0, 0)) for g in gaps]
    fill = tuple(sum(c[k] for c in cols) // len(cols) for k in range(3))
    flat = base.copy()
    d = ImageDraw.Draw(flat)
    for (x, y, w, h) in rects:
        d.rectangle((x - 4, y - 4, x + w + 4, y + h + 4), fill=fill + (255,))
    bl = flat.filter(ImageFilter.GaussianBlur(blur))
    out = base.copy()
    for (x, y, w, h) in rects:
        out.paste(bl.crop((x - 4, y - 4, x + w + 4, y + h + 4)), (x - 4, y - 4))
    return out


def solid_like(base, box):
    return base.crop(box).convert("RGB").resize((1, 1), Image.BOX).getpixel((0, 0))


def text_c(d, cx, y, s, size, col, serif=False, a=1.0):
    f = font(size, serif)
    w = d.textlength(s, font=f)
    d.text((cx - w / 2, y), s, font=f, fill=rgba(col, a))


CARD_RECTS = [(196 + 308 * i, 190, 273, 383) for i in range(3)]   # choice_panel 三张卡（1280×720）

# ---------------------------------------------------------------- 各界面招牌动效


class Seg:
    def __init__(self, key, label, dur, setup, frame):
        self.key, self.label, self.dur = key, label, dur
        self.setup, self.frame = setup, frame
        self.ctx = None


def title_setup():
    title, sett = shot("title"), shot("settings")
    P = (320, 53, 961, 668)
    # 设置截图里面板外是压暗的标题页：按面板外一块的亮度比把标题页压到同样暗，作为「没有面板」的底
    a = solid_like(sett, (20, 100, 300, 600))
    b = solid_like(title, (20, 100, 300, 600))
    k = sum(a) / max(1, sum(b))
    dim = darken(title, 1 - k)
    bg = sett.copy()
    bg.paste(dim.crop((P[0] - 16, P[1] - 16, P[2] + 16, P[3] + 16)), (P[0] - 16, P[1] - 16))
    panel = sett.crop(P)
    return dict(title=title, bg=bg, panel=panel, P=P, O=(112, 541))


def title_frame(c, t):
    title, bg, P, O = c["title"], c["bg"], c["P"], c["O"]
    u = seg(t, 0.18, 0.62)
    r = in_out_cubic(u) * 1500
    img = title.copy()
    L = layer()
    d = ImageDraw.Draw(L)
    # ① 按下「设置」：选中行亮一下
    fl = clamp(1 - abs(t - 0.12) / 0.12)
    if fl > 0:
        d.rectangle((O[0] - 70, O[1] - 14, O[0] + 200, O[1] + 14), fill=rgba(CYAN, 0.22 * fl))
    # ② 声呐环从按下的那一行扩散，环内是新页面
    if r > 0:
        m = Image.new("L", (W, H), 0)
        ImageDraw.Draw(m).ellipse((O[0] - r, O[1] - r, O[0] + r, O[1] + r), fill=255)
        img.paste(bg, (0, 0), m)
        for k, (off, a) in enumerate([(0, 0.9), (26, 0.45), (64, 0.2)]):
            rr = r - off
            if rr > 4 and u < 1:
                d.ellipse((O[0] - rr, O[1] - rr, O[0] + rr, O[1] + rr), outline=rgba(CYAN, a * (1 - u * 0.6)), width=3 if k == 0 else 1)
    if u >= 1:
        img = bg.copy()
    img.alpha_composite(L)
    # ③ 面板：先一道中线向两边拉开，再沿中线上下展开（档案夹打开）
    cx, cy = (P[0] + P[2]) / 2, (P[1] + P[3]) / 2
    pw, ph = P[2] - P[0], P[3] - P[1]
    lw = out_cubic(seg(t, 0.72, 0.14)) * pw
    s = out_cubic(seg(t, 0.84, 0.30))
    L2 = layer()
    d2 = ImageDraw.Draw(L2)
    if lw > 0 and s < 1:
        d2.rectangle((cx - lw / 2, cy - 1, cx + lw / 2, cy + 1), fill=rgba(CYAN, 0.9))
    img.alpha_composite(L2)
    if s > 0:
        hh = max(2, int(ph * s))
        pv = c["panel"].resize((pw, hh), Image.NEAREST)
        img.alpha_composite(pv, (P[0], int(cy - hh / 2)))
    return img


def diff_setup():
    base = shot("diff")
    pc = solid_like(base, (270, 600, 330, 630))
    clean = base.copy()
    d = ImageDraw.Draw(clean)
    d.rectangle((272, 236, 1008, 290), fill=pc + (255,))   # 档名 + 英文
    d.rectangle((272, 296, 1008, 500), fill=pc + (255,))   # 说明 + 效果列表
    return dict(base=base, clean=clean, pc=pc)


def diff_frame(c, t):
    base, clean = c["base"], c["clean"]
    R = (260, 60, 1020, 660)
    y0, y1 = 520.0, 236.0                 # 档 0 / 档 1 的潮位
    u = seg(t, 0.32, 0.62)
    lv = lerp(y0, y1, out_back(u, 1.2))
    col = lerp_col(CYAN, lerp_col(CYAN, RED, 0.5), out_cubic(u))
    # 内容：潮水漫过的那一行才「浮现」（水面以下 = 截图原样，以上 = 盖住）
    img = clean.copy()
    reveal = Image.new("L", (W, H), 0)
    ImageDraw.Draw(reveal).rectangle((R[0], int(lv) - 6, R[2], R[3]), fill=255)
    if u > 0:
        img.paste(base, (0, 0), reveal)
    else:
        img = clean.copy()
    # 菱形里的级数：▶ 按下后旧的「≈」上滑出去、新的「Ⅳ」从下面顶上来
    L = layer()
    d = ImageDraw.Draw(L)
    k = in_out_cubic(seg(t, 0.30, 0.22))
    dia = base.crop((600, 160, 680, 240))
    hole = Image.new("RGBA", (80, 80), solid_like(base, (626, 186, 634, 190)) + (255,))
    old = Image.new("RGBA", (80, 80), (0, 0, 0, 0))
    text_c(ImageDraw.Draw(old), 40, 22, "≈", 28, TEXT)
    newm = dia.copy()
    clipm = Image.new("L", (80, 80), 0)
    ImageDraw.Draw(clipm).polygon([(40, 10), (70, 40), (40, 70), (10, 40)], fill=255)
    comp = Image.new("RGBA", (80, 80), (0, 0, 0, 0))
    comp.paste(hole, (0, 0))
    comp.alpha_composite(old, (0, int(-40 * k)))
    nm = Image.new("RGBA", (80, 80), (0, 0, 0, 0))
    nm.paste(newm, (0, 0))
    if k > 0:
        comp.alpha_composite(nm, (0, int(40 * (1 - k))))
    img.paste(dia, (600, 160))
    img.paste(comp, (600, 160), clipm)
    # 潮水本体：半透明水体 + 两层正弦水面
    pts = [(x, lv + 4 * math.sin(x / 38 + t * 6) + 2 * math.sin(x / 17 - t * 4)) for x in range(R[0] + 2, R[2] - 1, 6)]
    poly = pts + [(R[2] - 2, R[3] - 2), (R[0] + 2, R[3] - 2)]
    d.polygon(poly, fill=rgba(col, 0.10))
    d.line(pts, fill=rgba(col, 0.85), width=2)
    pts2 = [(x, y + 7 + 2 * math.sin(x / 23 + t * 3)) for x, y in pts]
    d.line(pts2, fill=rgba(col, 0.3), width=1)
    # 右侧潮位刻度：三档三条刻度，当前水位一颗菱形游标
    gx = R[2] - 34
    for i, (yy, s) in enumerate([(y0, "≈"), (y1, "Ⅳ"), (y1 - 140, "VIII")]):
        d.line((gx, yy, gx + 14, yy), fill=rgba(TEXT, 0.5), width=1)
        d.text((gx - 34, yy - 9), s, font=font(13), fill=rgba(SUB, 0.9))
    d.line((gx + 7, y1 - 150, gx + 7, y0 + 10), fill=rgba(TEXT, 0.2), width=1)
    d.polygon([(gx + 7, lv - 6), (gx + 13, lv), (gx + 7, lv + 6), (gx + 1, lv)], fill=rgba(col, 1))
    # ▶ 按下闪一下
    fl = clamp(1 - abs(t - 0.28) / 0.1)
    if fl > 0:
        d.rectangle((790, 170, 840, 230), fill=rgba(TEXT, 0.25 * fl))
    img.alpha_composite(L)
    return img


def card_back(w, h, col, label):
    im = Image.new("RGBA", (w, h), PANEL + (255,))
    d = ImageDraw.Draw(im)
    d.rectangle((0, 0, w - 1, h - 1), outline=rgba(TEXT, 0.25))
    d.rectangle((8, 8, w - 9, h - 9), outline=rgba(col, 0.35))
    for k in range(-h, w, 14):
        d.line((k, 0, k + h, h), fill=rgba(col, 0.06))
    cx, cy = w / 2, h / 2
    for r, a in [(58, 0.9), (44, 0.4)]:
        d.polygon([(cx, cy - r), (cx + r, cy), (cx, cy + r), (cx - r, cy)], outline=rgba(col, a))
    text_c(d, cx, cy - 8, "≈", 22, col)
    text_c(d, cx, h - 40, label, 11, col, a=0.8)
    return im


def deal_setup(name, back_col, label):
    def setup():
        base = shot(name)
        clean = erase_rects(base, CARD_RECTS)
        cards = [base.crop((x, y, x + w, y + h)) for (x, y, w, h) in CARD_RECTS]
        return dict(clean=clean, cards=cards, back=card_back(273, 383, back_col, label))
    return setup


def levelup_frame(c, t):
    img = c["clean"].copy()
    deck = (640 - 136, 760)
    for i, (x, y, w, h) in enumerate(CARD_RECTS):
        # ① 发牌：从屏幕下方的牌堆依次飞到位，带一点旋转
        u = out_cubic(seg(t, 0.05 + 0.09 * i, 0.32))
        if u <= 0:
            continue
        px, py = lerp(deck[0], x, u), lerp(deck[1], y, u)
        rot = lerp(-14 + 14 * i, 0, u)
        # ② 翻面：横向压扁到 0 再展开，展开后是正面
        f = seg(t, 0.55 + 0.11 * i, 0.24)
        if f < 0.5:
            face, sx = c["back"], 1 - in_out_cubic(f * 2) if f > 0 else 1.0
        else:
            face, sx = c["cards"][i], in_out_cubic((f - 0.5) * 2)
        sc = lerp(0.62, 1.0, u)
        im = scaled(face, max(0.01, sx) * sc, sc)
        if abs(rot) > 0.3:
            im = im.rotate(rot, resample=Image.NEAREST, expand=True)
        cx, cy = px + w / 2, py + h / 2
        img.alpha_composite(im, (int(cx - im.width / 2), int(cy - im.height / 2)))
        # ③ 翻完：青色描边闪一下
        fl = clamp(1 - abs(t - (0.55 + 0.11 * i + 0.30)) / 0.14)
        if fl > 0 and f >= 1:
            L = layer()
            ImageDraw.Draw(L).rectangle((x - 2, y - 2, x + w + 1, y + h + 1), outline=rgba(CYAN, fl), width=2)
            img.alpha_composite(L)
    return img


def relic_frame(c, t):
    img = c["clean"].copy()
    rnd = random.Random(7)
    for i, (x, y, w, h) in enumerate(CARD_RECTS):
        rare = i == 1
        col = GOLD if rare else (170, 240, 236)
        c0 = 0.10 + 0.13 * i
        # ① 光柱：从卡位底边冲上去，再慢慢退
        up = out_cubic(seg(t, c0, 0.18))
        fade = 1 - seg(t, c0 + 0.30, 0.45)
        if rare:
            fade = max(fade, 0.55 * clamp(1 - abs(t - (c0 + 0.85)) / 0.25))   # 稀有：第二次脉冲
        if up > 0 and fade > 0:
            L = layer()
            d = ImageDraw.Draw(L)
            top = lerp(y + h, 40, up)
            cx = x + w / 2
            for k in range(12):
                ww = w * (0.18 + 0.82 * k / 11)
                d.rectangle((cx - ww / 2, top, cx + ww / 2, y + h), fill=rgba(col, 0.05 * fade))
            d.rectangle((cx - 3, top, cx + 3, y + h), fill=rgba((255, 255, 255), 0.6 * fade))
            for p in range(14 if rare else 7):   # 上升的光点（预览用固定种子，游戏里用 g.vrng 或固定表）
                px = cx + rnd.uniform(-w / 2.2, w / 2.2)
                sp = rnd.uniform(160, 320)
                py = y + h - ((t - c0) * sp + rnd.uniform(0, 200)) % (h + 80)
                s = 2 if p % 3 else 3
                d.rectangle((px, py, px + s, py + s), fill=rgba(col, 0.8 * fade))
            img.alpha_composite(L)
        # ② 卡片从光里升起：自下而上显出，同时上移 40 px 到位
        r = out_cubic(seg(t, c0 + 0.08, 0.34))
        if r > 0:
            card = c["cards"][i]
            vis = int(h * r)
            part = card.crop((0, 0, w, vis))
            img.alpha_composite(part, (x, int(y + 40 * (1 - r) + (h - vis) * 0.0)))
    return img


def recruit_setup():
    base = shot("recruit")
    clean = erase_rects(base, CARD_RECTS)
    pc = solid_like(base, (210, 520, 240, 530))
    cards, sprites, empties = [], [], []
    for (x, y, w, h) in CARD_RECTS:
        card = base.crop((x, y, x + w, y + h))
        cx, cy = w // 2 + 2, 124
        spr = card.crop((cx - 36, cy - 44, cx + 36, cy + 40))
        e = card.copy()
        d = ImageDraw.Draw(e)
        d.ellipse((cx - 40, cy - 46, cx + 40, cy + 42), fill=pc + (255,))
        d.rectangle((8, 160, w - 9, h - 60), fill=pc + (255,))
        cards.append(card)
        sprites.append((spr, (cx - 36, cy - 44)))
        empties.append(e)
    return dict(clean=clean, cards=cards, sprites=sprites, empties=empties)


def recruit_frame(c, t):
    img = c["clean"].copy()
    for i, (x, y, w, h) in enumerate(CARD_RECTS):
        t0 = 0.05 + 0.20 * i
        a = seg(t, t0, 0.12)
        if a <= 0:
            continue
        land = t0 + 0.32
        sh = 2.0 * clamp(1 - (t - land) / 0.1) if t >= land else 0.0
        ox = int(round(math.sin(t * 120) * sh))
        textk = seg(t, land + 0.05, 0.2)
        card = c["empties"][i].copy()
        if textk > 0:
            full = c["cards"][i].crop((0, 160, w, h - 60))
            card.alpha_composite(with_alpha(full, textk), (0, 160))
        spr, (sx0, sy0) = c["sprites"][i]
        cx, cy = sx0 + 36, sy0 + 84
        L = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        d = ImageDraw.Draw(L)
        # ① 部署格：菱形落点先画出来
        dk = out_back(seg(t, t0 + 0.08, 0.12))
        if dk > 0:
            rr = 30 * dk
            d.polygon([(cx - rr, cy), (cx, cy - rr * 0.45), (cx + rr, cy), (cx, cy + rr * 0.45)], outline=rgba(CYAN, 0.9), width=1)
        # ② 干员从上方落下（加速），落地压扁一下
        fu = seg(t, t0 + 0.14, 0.18)
        if fu > 0:
            yy = lerp(-70, 0, in_quad(fu))
            squash = 1.0
            if t > land:
                squash = lerp(0.84, 1.0, out_cubic(seg(t, land, 0.1)))
            s2 = scaled(spr, 2 - squash, squash)
            card.alpha_composite(L)
            L = Image.new("RGBA", (w, h), (0, 0, 0, 0))
            d = ImageDraw.Draw(L)
            card.alpha_composite(s2, (int(sx0 + 36 - s2.width / 2), int(sy0 + yy + (spr.height - s2.height))))
        # ③ 落地环
        rk = seg(t, land, 0.28)
        if 0 < rk < 1:
            rr = lerp(10, 54, out_cubic(rk))
            d.ellipse((cx - rr, cy - rr * 0.45, cx + rr, cy + rr * 0.45), outline=rgba(CYAN, 1 - rk), width=2)
        card.alpha_composite(L)
        img.alpha_composite(with_alpha(card, a), (x + ox, int(y + 10 * (1 - a))))
    return img


def event_setup():
    base = darken(shot("play"), 0.72, (2, 8, 14))
    page = layer()
    d = ImageDraw.Draw(page)
    rnd = random.Random(11)
    # 左：墨块插画区（choice_panel.event_art 的意思：毛边纸面 + 墨团 + 斜笔触 + 圆相）
    edge = [(60 + k * 27 + rnd.uniform(-4, 4), 120 + rnd.uniform(-8, 8)) for k in range(21)]
    edge += [(600 + rnd.uniform(-8, 8), 120 + k * 25) for k in range(21)]
    edge += [(600 - k * 27 + rnd.uniform(-4, 4), 620 + rnd.uniform(-8, 8)) for k in range(21)]
    edge += [(60 + rnd.uniform(-8, 8), 620 - k * 25) for k in range(21)]
    d.polygon(edge, fill=(170, 186, 204, 60))
    for k in range(9):
        cx, cy, r = rnd.uniform(120, 560), rnd.choice([rnd.uniform(100, 180), rnd.uniform(520, 640)]), rnd.uniform(40, 100)
        d.ellipse((cx - r, cy - r * 0.8, cx + r, cy + r * 0.8), fill=(6, 10, 14, 230))
    for k in range(5):
        x0, y0 = rnd.uniform(60, 260), rnd.uniform(200, 520)
        L = rnd.uniform(240, 420)
        d.line((x0, y0, x0 + L, y0 - L * 0.42), fill=(220, 230, 235, 70), width=int(rnd.uniform(6, 16)))
    d.ellipse((230, 260, 430, 460), outline=(180, 200, 255, 160), width=5)
    d.ellipse((300, 330, 360, 390), fill=(70, 110, 255, 220))
    # 右：标题
    d.text((640, 150), "E V E N T  ·  C H O O S E   O N E", font=font(18), fill=rgba(TEXT, 0.75))
    d.text((640, 182), "做出你的选择", font=font(44, True), fill=rgba(TEXT, 1))
    d.text((644, 246), "海嗣祭坛 · 深蓝的低语", font=font(16), fill=rgba(SUB, 1))
    bars = []
    opts = [("倾听", "得到藏品  灯火 -50（最低 10）", (110, 130, 255)), ("抗拒", "灯火 +30，祭坛沉入海底", CYAN), ("离开", "不领取藏品，保持当前路线", SUB)]
    for i, (n, s, col) in enumerate(opts):
        y = 300 + i * 104
        bar = Image.new("RGBA", (600, 88), (0, 0, 0, 0))
        bd = ImageDraw.Draw(bar)
        pts = [(14, 6), (590, 0), (598, 82), (0, 88)]
        bd.polygon(pts, fill=(14, 18, 24, 235))
        bd.line([(14, 6), (0, 88)], fill=rgba(col, 1), width=4)
        bd.ellipse((26, 18, 78, 70), outline=rgba(col, 0.9), width=3)
        bd.text((100, 14), n, font=font(28, True), fill=rgba(TEXT, 1))
        bd.text((100, 54), s, font=font(15), fill=rgba(SUB, 1))
        bars.append((bar, (640, y)))
    return dict(base=base, page=page, bars=bars)


def event_frame(c, t):
    img = c["base"].copy()
    # ① 页面从深处浮上来：上移 + 由糊到清 + 透明度
    u = out_cubic(seg(t, 0.0, 0.62))
    blur = (1 - u) * 6
    pg = c["page"].filter(ImageFilter.GaussianBlur(blur)) if blur > 0.4 else c["page"]
    if u > 0:
        tmp = layer()
        tmp.paste(pg, (0, int(80 * (1 - u))))
        img.alpha_composite(with_alpha(tmp, u))
    # 焦散光纹：浮起过程中几道斜向亮纹掠过页面，随后消失
    L = layer()
    d = ImageDraw.Draw(L)
    ca = (1 - u) * 0.5
    if ca > 0.02:
        for k in range(5):
            yy = 120 + k * 120 + math.sin(t * 5 + k) * 30
            d.line([(x, yy + 18 * math.sin(x / 70 + t * 4 + k)) for x in range(0, W, 16)], fill=rgba((150, 220, 255), ca * 0.5), width=3)
    # 气泡（固定种子）
    rnd = random.Random(3)
    for k in range(22):
        bx = rnd.uniform(80, 1200)
        sp = rnd.uniform(220, 420)
        by = H + 20 - (t * sp + rnd.uniform(0, 300))
        if -10 < by < H + 20 and t < 1.2:
            r = rnd.choice([2, 3, 4])
            d.ellipse((bx - r, by - r, bx + r, by + r), outline=rgba((190, 230, 255), 0.6 * (1 - seg(t, 0.8, 0.4))), width=1)
    img.alpha_composite(L)
    # ② 选项条：一笔刷出来（遮罩右缘是毛边），刷过以后字再显
    for i, (bar, (bx, by)) in enumerate(c["bars"]):
        k = in_out_cubic(seg(t, 0.55 + 0.14 * i, 0.32))
        if k <= 0:
            continue
        m = Image.new("L", bar.size, 0)
        md = ImageDraw.Draw(m)
        edge = k * (bar.width + 30)
        poly = [(0, 0), (edge, 0)]
        for yy in range(0, bar.height + 1, 6):
            poly.append((edge - 18 + 14 * math.sin(yy * 1.7 + i), yy))
        poly += [(edge - 10, bar.height), (0, bar.height)]
        md.polygon(poly, fill=255)
        part = Image.new("RGBA", bar.size, (0, 0, 0, 0))
        part.paste(bar, (0, 0), m)
        img.alpha_composite(part, (bx, by))
    return img


def shop_setup():
    base = shot("shop")
    rel = [shot("relic")]
    icons = []
    for r in rel:
        for (x, y, w, h) in CARD_RECTS:
            icons.append(r.crop((x + 20, y + 30, x + w - 20, y + 250)))
    goods = []
    names = [("藏品", 18), ("藏品", 22), ("藏品", 16), ("回复药剂", 6), ("灯油", 4)]
    for k in range(5):
        g = Image.new("RGBA", (162, 300), PANEL + (245,))
        d = ImageDraw.Draw(g)
        d.rectangle((0, 0, 161, 299), outline=rgba(TEXT, 0.22))
        ic = icons[k % len(icons)].resize((150, int(150 * icons[0].height / icons[0].width)), Image.LANCZOS)
        g.alpha_composite(ic, (6, 14))
        d.rectangle((10, 252, 151, 288), fill=(32, 37, 46, 255))
        d.text((20, 258), "源石锭", font=font(14), fill=rgba(SUB, 1))
        d.text((110, 254), str(names[k][1]), font=font(20), fill=rgba(GREEN, 1))
        goods.append(g)
    return dict(base=base, goods=goods)


GREEN = (47, 211, 160)


def shop_frame(c, t):
    img = c["base"].copy()
    lamp = (272, 452)
    pulses = [0.18, 0.46, 0.74, 1.02, 1.30]
    # 灯笼：先暗，每次「一明」点亮一格货架，「一暗」回落
    inten = 0.25
    for p in pulses:
        inten = max(inten, 1.0 * clamp(1 - abs(t - p) / 0.12))
    if t > 1.42:
        inten = max(inten, 0.78 + 0.08 * math.sin((t - 1.42) * 9))
    L = layer()
    d = ImageDraw.Draw(L)
    for r in range(150, 10, -14):
        d.ellipse((lamp[0] - r, lamp[1] - r, lamp[0] + r, lamp[1] + r), fill=rgba((255, 170, 70), 0.035 * inten))
    img.alpha_composite(L)
    for k, g in enumerate(c["goods"]):
        x, y = 362 + k * 172, 224
        lit = seg(t, pulses[k], 0.01)
        pop = clamp(1 - (t - pulses[k]) / 0.3) if t >= pulses[k] else 0
        if lit <= 0:
            gi = darken(g, 0.8, (4, 6, 8))
        else:
            gi = g.copy()
            if pop > 0:
                gi = Image.blend(gi, Image.new("RGBA", gi.size, (255, 214, 150, 255)), 0.25 * pop)
        img.alpha_composite(gi, (x, y))
        if lit > 0:
            L2 = layer()
            d2 = ImageDraw.Draw(L2)
            d2.rectangle((x, y, x + 161, y + 2), fill=rgba(GOLD, 0.9))
            if pop > 0:   # 一缕暖光从灯笼扫到这一格
                d2.line((lamp[0], lamp[1], x + 80, y + 150), fill=rgba((255, 190, 110), 0.35 * pop), width=6)
            img.alpha_composite(L2)
    return img


def pause_setup():
    return dict(base=shot("play"))


def pause_frame(c, t):
    k = out_cubic(seg(t, 0.0, 0.22))
    img = darken(c["base"], 0.62 * k, (4, 10, 16))
    L = layer()
    d = ImageDraw.Draw(L)
    C, R = (430, 360), 150
    # ① 表盘：圆环描出来 + 12 道刻度依次出现
    ak = out_cubic(seg(t, 0.08, 0.26))
    if ak > 0:
        d.arc((C[0] - R, C[1] - R, C[0] + R, C[1] + R), -90, -90 + 360 * ak, fill=rgba(CYAN, 0.8), width=2)
        for i in range(12):
            if i / 12 <= ak:
                a = math.radians(i * 30 - 90)
                r0 = R - (16 if i % 3 == 0 else 9)
                d.line((C[0] + math.cos(a) * r0, C[1] + math.sin(a) * r0, C[0] + math.cos(a) * (R - 3), C[1] + math.sin(a) * (R - 3)), fill=rgba(TEXT, 0.7), width=2 if i % 3 == 0 else 1)
    # ② 秒针：一进来飞转，减速，越过 12 点一点再弹回停住
    hk = seg(t, 0.12, 0.85)
    if hk > 0:
        ang = -720 * (1 - out_back(hk, 1.6))
        a = math.radians(ang - 90)
        d.line((C[0], C[1], C[0] + math.cos(a) * (R - 22), C[1] + math.sin(a) * (R - 22)), fill=rgba(RED, 1), width=3)
        d.line((C[0], C[1], C[0] - math.cos(a) * 22, C[1] - math.sin(a) * 22), fill=rgba(RED, 1), width=3)
        d.ellipse((C[0] - 6, C[1] - 6, C[0] + 6, C[1] + 6), fill=rgba(TEXT, 1))
    # 停住那一下：一圈细环外扩
    st = seg(t, 0.97, 0.3)
    if 0 < st < 1:
        rr = R + 30 * out_cubic(st)
        d.ellipse((C[0] - rr, C[1] - rr, C[0] + rr, C[1] + rr), outline=rgba(CYAN, 0.6 * (1 - st)), width=2)
    # ③ 菜单：按「嘀嗒」节奏分三格跳进来（steps 缓动），不是平滑滑入
    if t > 0.95:
        d.text((650, 196), "PAUSED", font=font(15), fill=rgba(CYAN, clamp((t - 0.95) / 0.12)))
        d.text((650, 216), "暂停", font=font(40, True), fill=rgba(TEXT, clamp((t - 0.95) / 0.12)))
    items = [("继续", "Esc"), ("指南", "G"), ("设置", "O"), ("重新开始", "R"), ("回到标题", "T")]
    for i, (n, kk) in enumerate(items):
        s = steps(seg(t, 1.0 + 0.08 * i, 0.24), 3)
        if s <= 0:
            continue
        x = 650 + 40 * (1 - s)
        y = 290 + i * 52
        d.rectangle((x, y, x + 300, y + 42), fill=rgba((40, 48, 60), 0.92 * s), outline=rgba(CYAN if i == 0 else TEXT, (0.9 if i == 0 else 0.15) * s))
        d.text((x + 16, y + 9), n, font=font(19), fill=rgba(TEXT, s))
        d.text((x + 262, y + 11), kk, font=font(14), fill=rgba(SUB, s))
    img.alpha_composite(L)
    return img


def key_out(im, bg, soft=10):
    """把截图裁片里接近底色的像素变透明（盖章放大时不带出一块底色方框）"""
    out = im.copy()
    px = out.load()
    for y in range(out.height):
        for x in range(out.width):
            r, g, b_, _ = px[x, y]
            dist = abs(r - bg[0]) + abs(g - bg[1]) + abs(b_ - bg[2])
            px[x, y] = (r, g, b_, int(clamp((dist - soft) / 40.0) * 255))
    return out


def win_setup():
    base = shot("win")
    pc = solid_like(base, (222, 440, 236, 448))
    clean = base.copy()
    d = ImageDraw.Draw(clean)
    d.rectangle((216, 236, 804, 438), fill=pc + (255,))
    rows = [(216, 236, 804, 286), (240, 286, 800, 310)] + [(240, 314 + 32 * i, 560, 344 + 32 * i) for i in range(4)]
    crops = [key_out(base.crop(r), pc) for r in rows]
    # 右侧结局徽：用柔边圆遮罩盖暗 / 显出，不留方框
    m = Image.new("L", (W, H), 0)
    ImageDraw.Draw(m).ellipse((930 - 175, 345 - 175, 930 + 175, 345 + 175), fill=255)
    m = m.filter(ImageFilter.GaussianBlur(24))
    bgc = solid_like(base, (1230, 300, 1250, 320))
    clean.paste(Image.new("RGBA", (W, H), bgc + (255,)), (0, 0), m)
    return dict(base=base, clean=clean, rows=rows, crops=crops, emb_mask=m)


def win_frame(c, t):
    img = c["clean"].copy()
    times = [0.18, 0.42, 0.62, 0.78, 0.94, 1.10]
    amp = 0.0
    L = layer()
    d = ImageDraw.Draw(L)
    for i, (r, cr) in enumerate(zip(c["rows"], c["crops"])):
        t0 = times[i]
        if i == 1:   # 副标题不盖章，淡入
            a = seg(t, t0, 0.2)
            if a > 0:
                img.alpha_composite(with_alpha(cr, a), (r[0], r[1]))
            continue
        u = seg(t, t0, 0.15)
        if u <= 0:
            continue
        s = lerp(1.5 if i == 0 else 1.32, 1.0, out_cubic(u))
        im = scaled(cr, s, s)
        cx, cy = r[0] + cr.width / 2, (r[1] + r[3]) / 2
        img.alpha_composite(with_alpha(im, out_cubic(u)), (int(cx - im.width / 2), int(cy - im.height / 2)))
        hit = t - (t0 + 0.15)
        if 0 <= hit < 0.14:
            amp = max(amp, (3.0 if i == 0 else 2.0) * (1 - hit / 0.14))
            # 盖章溅出的墨点（洋红）
            for k in range(8):
                ang = k * 0.785 + i
                rr = 20 + 140 * hit
                px, py = (r[0] + 20 if i > 1 else cx) + math.cos(ang) * rr, cy + math.sin(ang) * rr * 0.4
                d.rectangle((px, py, px + 2, py + 2), fill=rgba(RED, 0.8 * (1 - hit / 0.14)))
    # 右侧结局徽：带光芒淡入
    ea = out_cubic(seg(t, 0.3, 0.6))
    if ea > 0:
        cx, cy = 930, 330
        for k in range(16):
            a = math.radians(k * 22.5 + t * 20)
            d.line((cx + math.cos(a) * 80, cy + math.sin(a) * 80, cx + math.cos(a) * (80 + 90 * ea), cy + math.sin(a) * (80 + 90 * ea)), fill=rgba((255, 170, 210), 0.12 * ea), width=3)
        img.paste(c["base"], (0, 0), c["emb_mask"].point(lambda v: int(v * ea)))
    # 收尾：右上角「达成」印章斜着砸下
    su = seg(t, 1.32, 0.14)
    if su > 0:
        seal = Image.new("RGBA", (96, 96), (0, 0, 0, 0))
        sd = ImageDraw.Draw(seal)
        sd.rectangle((4, 4, 91, 91), outline=rgba(RED, 0.95), width=4)
        text_c(sd, 48, 26, "达成", 30, RED, serif=True)
        sc = lerp(2.0, 1.0, out_cubic(su))
        sim = scaled(seal, sc, sc).rotate(-8, resample=Image.NEAREST, expand=True)
        img.alpha_composite(with_alpha(sim, out_cubic(su) * 0.9), (int(770 - sim.width / 2), int(206 - sim.height / 2)))
        hit = t - 1.46
        if 0 <= hit < 0.14:
            amp = max(amp, 3.0 * (1 - hit / 0.14))
    img.alpha_composite(L)
    return shake(img, amp, t)


SEGS = [
    Seg("title", "标题 → 设置 · 声呐环揭开 + 档案夹展开", 1.9, title_setup, title_frame),
    Seg("diff", "难度选择 · 潮位上涨到所选档", 1.9, diff_setup, diff_frame),
    Seg("levelup", "升级选卡 · 发牌 + 依次翻面", 1.9, deal_setup("levelup", CYAN, "LEVEL UP"), levelup_frame),
    Seg("relic", "藏品选择 · 光柱托起（稀有二次脉冲）", 1.9, deal_setup("relic", GOLD, "RELIC"), relic_frame),
    Seg("recruit", "招募干员 · 部署落地", 1.9, recruit_setup, recruit_frame),
    Seg("event", "海嗣祭坛事件 · 深海浮起 + 笔刷选项（合成示意）", 1.9, event_setup, event_frame),
    Seg("shop", "流浪商人 · 灯笼一明一暗，货架逐格亮起", 1.9, shop_setup, shop_frame),
    Seg("pause", "暂停 · 秒针停摆 + 菜单嘀嗒入场", 1.9, pause_setup, pause_frame),
    Seg("win", "结局结算 · 战绩逐行盖章", 1.9, win_setup, win_frame),
]
HOLD = 0.3


def label(img, idx, total, text, rep):
    L = layer()
    d = ImageDraw.Draw(L)
    s = "%d / %d   %s" % (idx, total, text)
    f = font(20)
    tw = d.textlength(s, font=f) + 150
    x0 = (W - tw) / 2
    d.rectangle((x0, H - 52, x0 + tw, H - 14), fill=(6, 8, 12, 215), outline=rgba(CYAN, 0.6))
    d.text((x0 + 18, H - 46), s, font=f, fill=rgba(TEXT, 1))
    d.text((x0 + tw - 112, H - 43), "第 %d 遍 / 2" % rep, font=font(16), fill=rgba(SUB, 1))
    img.alpha_composite(L)
    return img


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--capture", action="store_true", help="先用 Godot 重截一轮界面")
    ap.add_argument("--only", default="", help="只出这些段（逗号分隔键名）")
    ap.add_argument("--stills", action="store_true", help="每段另存 4 张关键帧 PNG")
    ap.add_argument("--out", default=os.path.join(OUT_DIR, "motion_preview.mp4"))
    a = ap.parse_args()
    os.makedirs(OUT_DIR, exist_ok=True)
    if a.capture:
        capture(list(CAPTURE))
    segs = [s for s in SEGS if not a.only or s.key in a.only.split(",")]
    import imageio_ffmpeg
    ff = imageio_ffmpeg.get_ffmpeg_exe()
    cmd = [ff, "-y", "-loglevel", "error", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", "%dx%d" % (W, H), "-r", str(FPS), "-i", "-",
           "-c:v", "libx264", "-preset", "medium", "-crf", "18", "-pix_fmt", "yuv420p", "-movflags", "+faststart", a.out]
    p = subprocess.Popen(cmd, stdin=subprocess.PIPE)
    n = 0
    for i, s in enumerate(segs):
        s.ctx = s.setup()
        frames = int(round((s.dur + HOLD) * FPS))
        for rep in (1, 2):
            for f in range(frames):
                t = min(f / FPS, s.dur)
                img = s.frame(s.ctx, t).convert("RGBA")
                if a.stills and rep == 1 and f in (int(0.2 * FPS), int(0.6 * FPS), int(1.0 * FPS), frames - 1):
                    img.convert("RGB").save(os.path.join(OUT_DIR, "still_%s_%02d.png" % (s.key, f)))
                img = label(img, i + 1, len(segs), s.label, rep)
                p.stdin.write(img.convert("RGB").tobytes())
                n += 1
        print("段 %-8s %d 帧 ×2" % (s.key, frames), flush=True)
    p.stdin.close()
    p.wait()
    print("出片：%s（%d 帧，%.1f 秒）" % (a.out, n, n / FPS))


if __name__ == "__main__":
    main()
