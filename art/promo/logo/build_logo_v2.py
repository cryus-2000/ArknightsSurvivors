"""Logo 重设计草稿（11-08 用户「去设计logo吧」）。三个方向，每个出 横版（标题页 / 封面用）+ 方版（图标用），全部在 1 像素格上画，整数倍放大：
A 灯塔航标：沿用灯塔徽记，塔顶点一盏暖橙灯、两道青光扫过字标；字 = ArkUI Heavy（游戏自带粗体），上白下青两段；
B 水母灯：「方」字顶上那一点换成一只发光小水母（伞里一点暖橙灯火）；字 = 优设标题黑（斜体，速度感）；徽记 = 同一只水母放大；
C 徽章：方版本身就是徽章——八角像素框里「方舟 / 幸存者」两行，顶上水母灯，底部 ARKNIGHTS SURVIVORS 小字条；横版 = 徽章 + 字标。
用法：python art/promo/logo/build_logo_v2.py   出到 build/logo_v2/
"""
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / "build/logo_v2"
TD = ROOT / "game/art/ui/title_deep"
F_HEAVY = str(ROOT / "game/fonts/ui_heavy.ttf")
F_YOUSHE = "C:/Windows/Fonts/YouSheBiaoTiHei-2 1.ttf"
F_LATIN = str(ROOT / "game/fonts/montserrat_bold.ttf")

WHITE = (232, 238, 236)
CYAN = (110, 228, 240)
CYAN_D = (52, 150, 178)
NAVY = (8, 16, 28)
ORANGE = (255, 170, 70)
ORANGE_L = (255, 226, 150)


# ---------- 像素工具 ----------
def text_mask(t, font, size, thr=110, track=0):
    f = ImageFont.truetype(font, size)
    ims = []
    for ch in t:
        b = f.getbbox(ch)
        im = Image.new("L", (b[2] + 4, size + 8), 0)
        ImageDraw.Draw(im).text((2, 2), ch, font=f, fill=255)
        a = np.asarray(im) > thr
        ims.append(a)
    h = max(a.shape[0] for a in ims)
    # 每字按实际列裁，字距 track
    cols = []
    for a in ims:
        xs = np.where(a.any(0))[0]
        cols.append(a[:, xs.min():xs.max() + 1] if len(xs) else np.zeros((a.shape[0], max(2, size // 3)), bool))
    w = sum(c.shape[1] for c in cols) + track * (len(cols) - 1)
    out = np.zeros((h, w), bool)
    x = 0
    for c in cols:
        out[:c.shape[0], x:x + c.shape[1]] = c
        x += c.shape[1] + track
    ys = np.where(out.any(1))[0]
    return out[ys.min():ys.max() + 1]


def latin_mask(t, size, track=1):
    return text_mask(t, F_LATIN, size, 120, track)


def dil(m, r=1, diag=True):
    o = m.copy()
    for _ in range(r):
        n = o.copy()
        n[1:] |= o[:-1]; n[:-1] |= o[1:]; n[:, 1:] |= o[:, :-1]; n[:, :-1] |= o[:, 1:]
        if diag:
            n[1:, 1:] |= o[:-1, :-1]; n[:-1, :-1] |= o[1:, 1:]; n[1:, :-1] |= o[:-1, 1:]; n[:-1, 1:] |= o[1:, :-1]
        o = n
    return o


class Canvas:
    def __init__(self, w, h):
        self.c = np.zeros((h, w, 4), np.uint8)

    def fill(self, m, x, y, col, a=255):
        h, w = m.shape
        H, W = self.c.shape[:2]
        x0, y0, x1, y1 = max(x, 0), max(y, 0), min(x + w, W), min(y + h, H)
        mm = m[y0 - y:y1 - y, x0 - x:x1 - x]
        self.c[y0:y1, x0:x1][mm] = (*col, a)

    def word(self, m, x, y, top=WHITE, bot=CYAN, split=0.58, outline=True, shadow=True):
        """字标：深色描边 + 1 格下投影 + 上白下青两段。"""
        if shadow:
            self.fill(dil(m, 1), x + 1, y + 2, NAVY)
        if outline:
            self.fill(dil(m, 1), x, y, NAVY)
        sp = int(m.shape[0] * split)
        t = m.copy(); t[sp:] = False
        b = m.copy(); b[:sp] = False
        self.fill(t, x, y, top)
        self.fill(b, x, y, bot)

    def img(self):
        return Image.fromarray(self.c, "RGBA")


def P(rows, cmap):
    """手画像素：字符画 → (掩码, 颜色) 列表。"""
    h, w = len(rows), max(len(r) for r in rows)
    out = []
    for ch, col in cmap.items():
        m = np.zeros((h, w), bool)
        for y, r in enumerate(rows):
            for x, c in enumerate(r):
                if c == ch:
                    m[y, x] = True
        out.append((m, col))
    return out


def draw_px(cv, spec, x, y):
    for m, col in spec:
        cv.fill(m, x, y, col)


# 小水母（9×11）：伞盖青、伞心暖橙灯、触须青暗
JELLY = [
    "...ooo...",
    ".occccco.",
    "occcWccco",
    "occLWLcco",
    "occcLccco",
    "ocddddd.o",
    ".d.d.d.d.",
    ".d.d..d..",
    "..d.d.d..",
    ".d..d..d.",
    "....d....",
]
JELLY_C = {"o": NAVY, "c": CYAN, "d": CYAN_D, "L": ORANGE, "W": ORANGE_L}

# 大水母徽记（19×22）
JELLY_BIG = [
    ".......ooooo.......",
    ".....oocccccoo.....",
    "....occcccccccco...",
    "...occcccWccccccc o",
    "..occccLLWLLcccccco",
    "..occcLLWWWLLccccco",
    ".occcccLLWLLcccccco",
    ".occcccccLccccccco.",
    ".oddddddddddddddo..",
    "..d..d..d..d..d....",
    "..d..d..d..d..d....",
    ".d..d..d...d...d...",
    ".d..d...d..d...d...",
    "..d..d..d...d.d....",
    "..d..d...d..d..d...",
    "...d..d..d...d.d...",
    "...d..d...d..d..d..",
    "....d..d..d...d....",
    "....d...d..d..d....",
    ".....d..d...d......",
    "........d..........",
    "........d..........",
]


def tower():
    """原灯塔徽记（logo_mark 左段，2 像素格 → 1 格）。"""
    lg = Image.open(TD / "logo_mark.png").convert("RGBA")
    a = np.asarray(lg)[..., 3] > 127
    a = a[::2, ::2]
    xs = np.where(a.any(0))[0]
    # 左段到第一个空列段
    gaps = np.where(~a.any(0))[0]
    end = next(g for g in gaps if g > xs.min() + 10)
    m = a[:, xs.min():end]
    ys = np.where(m.any(1))[0]
    return m[ys.min():ys.max() + 1]


def glow(img, k=0.6, blur=4, col=CYAN):
    a = np.asarray(img).astype(np.float32)
    m = Image.fromarray((a[..., 3] > 0).astype(np.uint8) * 255)
    g = np.asarray(m.filter(ImageFilter.GaussianBlur(blur))).astype(np.float32)[..., None] / 255 * k
    base = np.zeros_like(a)
    base[..., :3] = np.array(col, np.float32)
    base[..., 3:] = g * 255
    gi = Image.fromarray(base.astype(np.uint8), "RGBA")
    gi.alpha_composite(img)
    return gi


# ---------- 方向 A：灯塔航标 ----------
def a_horizontal():
    tw = tower()
    wd = text_mask("方舟幸存者", F_HEAVY, 30, track=2)
    lat = latin_mask("ARKNIGHTS  SURVIVORS", 9, 2)
    W, H = tw.shape[1] + 8 + wd.shape[1] + 12, max(tw.shape[0], wd.shape[0] + 14) + 10
    cv = Canvas(W, H)
    ty = 4
    # 两道青光从塔顶灯往右扫（像素斜线）
    lx, ly = tw.shape[1] // 2 + 2, ty + 5
    for dy0, a in ((0, 200), (5, 140)):
        for x in range(lx, W - 2):
            y = ly + dy0 + (x - lx) // 6
            if 0 <= y < H:
                cv.c[y, x] = (*CYAN_D, a)
    cv.fill(dil(tw, 1), 2, ty, NAVY)
    cv.fill(tw, 2, ty, WHITE)
    # 塔顶灯
    cv.fill(np.ones((3, 3), bool), 2 + tw.shape[1] // 2 - 1, ty + 8, ORANGE)
    cv.fill(np.ones((1, 1), bool), 2 + tw.shape[1] // 2, ty + 9, ORANGE_L)
    wx = tw.shape[1] + 10
    cv.word(wd, wx, ty + 2)
    cv.fill(lat, wx + 2, ty + wd.shape[0] + 6, (200, 170, 100))
    return cv.img()


def a_square():
    tw = tower()
    r1 = text_mask("方舟", F_HEAVY, 22, track=2)
    r2 = text_mask("幸存者", F_HEAVY, 22, track=2)
    W = 96
    cv = Canvas(W, W)
    tot = tw.shape[0] + 3 + r1.shape[0] + 3 + r2.shape[0]
    t0 = (W - tot) // 2
    tx = (W - tw.shape[1]) // 2
    cv.fill(dil(tw, 1), tx, t0, NAVY)
    cv.fill(tw, tx, t0, WHITE)
    cv.fill(np.ones((3, 3), bool), tx + tw.shape[1] // 2 - 1, t0 + 8, ORANGE)
    y = t0 + tw.shape[0] + 3
    cv.word(r1, (W - r1.shape[1]) // 2, y)
    cv.word(r2, (W - r2.shape[1]) // 2, y + r1.shape[0] + 3)
    return cv.img()


# ---------- 方向 B：水母灯 ----------
def b_word(size=32):
    wd = text_mask("方舟幸存者", F_YOUSHE, size, track=1)
    # 「方」顶上那一点：第一字最上面的连通小块 → 擦掉，换小水母
    first = wd[:, :size]
    ys, xs = np.where(first)
    top = ys.min()
    dot = np.zeros_like(wd)
    band = wd[top:top + max(3, size // 6), :size]
    dot[top:top + band.shape[0], :size] = band
    return wd & ~dot, (int(np.where(band.any(0))[0].mean()), top)


def b_horizontal():
    wd, (dx, dy) = b_word(32)
    lat = latin_mask("ARKNIGHTS  SURVIVORS", 9, 2)
    jb = P(JELLY_BIG, JELLY_C)
    jh, jw = len(JELLY_BIG), len(JELLY_BIG[0])
    W, H = jw + 10 + wd.shape[1] + 10, max(jh, wd.shape[0] + 20) + 8
    cv = Canvas(W, H)
    draw_px(cv, jb, 2, 3)
    wx, wy = jw + 8, 10
    cv.word(wd, wx, wy)
    draw_px(cv, P(JELLY, JELLY_C), wx + dx - 4, wy + dy - 8)
    cv.fill(lat, wx + 3, wy + wd.shape[0] + 5, (200, 170, 100))
    return cv.img()


def b_square():
    jb = P(JELLY_BIG, JELLY_C)
    r1 = text_mask("方舟", F_YOUSHE, 28, track=1)
    r2 = text_mask("幸存者", F_YOUSHE, 28, track=1)
    W = 96
    cv = Canvas(W, W)
    draw_px(cv, jb, (W - len(JELLY_BIG[0])) // 2, 2)
    y = 26
    cv.word(r1, (W - r1.shape[1]) // 2, y)
    cv.word(r2, (W - r2.shape[1]) // 2, y + r1.shape[0] + 4)
    return cv.img()


# ---------- 方向 C：徽章 ----------
def octagon(w, h, cut):
    m = np.zeros((h, w), bool)
    for y in range(h):
        d = max(0, cut - y, y - (h - 1 - cut))
        m[y, d:w - d] = True
    return m


def badge(W=96):
    cv = Canvas(W, W)
    outer = octagon(W - 4, W - 4, 14)
    inner = octagon(W - 10, W - 10, 11)
    cv.fill(dil(outer, 1), 1, 1, NAVY)
    cv.fill(outer, 2, 2, CYAN_D)
    cv.fill(inner, 5, 5, (14, 34, 48))
    # 内框细线
    ring = octagon(W - 16, W - 16, 9)
    ring2 = octagon(W - 18, W - 18, 8)
    rr = np.zeros_like(ring); rr[1:-1, 1:-1] = ring2
    cv.fill(ring & ~rr, 8, 8, (40, 90, 108))
    r1 = text_mask("方舟", F_HEAVY, 22, track=2)
    r2 = text_mask("幸存者", F_HEAVY, 22, track=2)
    draw_px(cv, P(JELLY, JELLY_C), (W - 9) // 2, 9)
    y = 22
    cv.word(r1, (W - r1.shape[1]) // 2, y)
    cv.word(r2, (W - r2.shape[1]) // 2, y + r1.shape[0] + 3)
    # 底部小字条
    lat = latin_mask("SURVIVORS", 6, 1)
    by = W - 20
    bar = np.ones((lat.shape[0] + 4, lat.shape[1] + 10), bool)
    bx = (W - bar.shape[1]) // 2
    cv.fill(bar, bx, by, CYAN)
    cv.fill(lat, bx + 5, by + 2, NAVY)
    return cv.img()


def c_horizontal():
    b = badge(96)
    wd = text_mask("方舟幸存者", F_HEAVY, 34, track=2)
    lat = latin_mask("ARKNIGHTS  SURVIVORS", 9, 2)
    W, H = b.width + 10 + wd.shape[1] + 8, b.height + 4
    cv = Canvas(W, H)
    img = cv.img()
    img.alpha_composite(b, (2, 2))
    cv.c = np.asarray(img).copy()
    wx = b.width + 10
    wy = (H - wd.shape[0] - 14) // 2
    cv.word(wd, wx, wy)
    cv.fill(lat, wx + 2, wy + wd.shape[0] + 5, (200, 170, 100))
    return cv.img()


# ---------- 预览 ----------
def on_bg(img, k, size, bgcrop=None):
    bg = Image.open(TD / "bg.png").convert("RGBA")
    if bgcrop:
        bg = bg.crop(bgcrop)
    bg = bg.resize(size, Image.NEAREST)
    a = np.asarray(bg).astype(np.float32); a[..., :3] *= .75
    bg = Image.fromarray(a.astype(np.uint8), "RGBA")
    lg = glow(img, .16, 2).resize((img.width * k, img.height * k), Image.NEAREST)
    return bg, lg


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    dirs = {"A 灯塔航标": (a_horizontal(), a_square()),
            "B 水母灯": (b_horizontal(), b_square()),
            "C 徽章": (c_horizontal(), badge())}
    f = ImageFont.truetype("C:/Windows/Fonts/msyh.ttc", 26)
    rowH = 380
    sheet = Image.new("RGB", (40 + 960 + 30 + 360 + 30 + 140, 30 + len(dirs) * rowH), (22, 24, 30))
    d = ImageDraw.Draw(sheet)
    for i, (name, (hz, sq)) in enumerate(dirs.items()):
        tag = name.split()[0]
        hz.save(OUT / f"logo_{tag}_h_1x.png"); sq.save(OUT / f"logo_{tag}_sq_1x.png")
        y = 30 + i * rowH
        d.text((40, y), name, fill=(255, 255, 255), font=f)
        # 横版：放在标题页背景上（像标题页左上 / 封面标题）
        bg, lg = on_bg(hz, 3, (960, 330), (0, 0, 428, 147))
        bg.alpha_composite(lg, (30, (330 - lg.height) // 2))
        sheet.paste(bg.convert("RGB"), (40, y + 40))
        # 方版：当 Toy 图标（512 → 预览 360）
        k = 512 // sq.width
        bg2, lg2 = on_bg(sq, k, (512, 512), (240, 0, 411, 171))
        bg2.alpha_composite(lg2, ((512 - lg2.width) // 2, (512 - lg2.height) // 2))
        ic = bg2.convert("RGB")
        ic.save(OUT / f"icon_{tag}.png")
        sheet.paste(ic.resize((330, 330), Image.NEAREST), (1030, y + 40))
        sheet.paste(ic.resize((64, 64), Image.LANCZOS), (1390, y + 40))
        sheet.paste(ic.resize((128, 128), Image.LANCZOS), (1390, y + 120))
    sheet.save(OUT / "logo_v2_sheet.png")
    print(OUT)


if __name__ == "__main__":
    main()
