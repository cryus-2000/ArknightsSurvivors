# -*- coding: utf-8 -*-
"""标题页 / 局外菜单 C4' 改版概念图（docs/67，2026-10-11 用户：「主界面之类的是不是可以根据图鉴的风格重新设计一下」）。

只是给人看的概念图，不改游戏代码。底图全部是当前版本的真实截图（Godot 经 tools/godot_runner 开窗口截，窗口不抢焦点），
概念元素用 PIL 按 docs/58 §8 / §11 的 C4' 规则画上去：浅色终端面板（半透明 C_L_GLASS 0.82）、警示黄 #FFCE00、
平行四边形页签、巨型描边英文、微型代码、职业色斜带。只用仓库资产与 game/fonts，不用原作任何图片。

用法：
    python tools/concept_title_ui.py --capture   先截一轮当前界面（标题 / 开场无菜单帧 / 难度 / 设置 / 致谢 / 操作说明 / 图鉴 / 选人；桌面 + 手机），再出图
    python tools/concept_title_ui.py             用已有截图出图

输出（不入库）：主仓库 build/title_redesign/
    contact_sheet.png         总览（先看这张）：现状一行 + 标题三案 + 难度 / 设置 / 致谢 + 手机
    current_*.png             现状截图（1280×720；手机 740×360）
    title_T1_split.png        标题 T1「档案终端」：左舞台 keyart，右侧浅色终端菜单
    title_T2_strip.png        标题 T2「全幅 + 终端条」：keyart 全幅，底部一条浅色终端菜单条
    title_T3_minimal.png      标题 T3「极简」：keyart 全幅，左下只有巨型描边英文 + 一列平行四边形菜单
    title_T1_phone.png        T1 手机 740×360（另有 T2 / T3 手机）
    diff_C4.png / settings_C4.png / credits_C4.png   难度 / 设置 / 致谢与声明 按选定语言（T1）的样子
    motion_T1.png             T1 动效分镜（开场下摇 + Logo 扫光 / 光束换行 / 声呐环进内页）
"""
import argparse, math, os, sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

TOOLS = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(TOOLS)
sys.path.insert(0, TOOLS)
import godot_runner as gr  # noqa: E402

W, H = 1280, 720
PW, PH = 740, 360
OUT = os.path.join(gr.common_root(ROOT), "build", "title_redesign")
SHOTS = os.path.join(OUT, "shots")
FONT_UI = os.path.join(ROOT, "game", "fonts", "ui.ttf")
FONT_FB = os.path.join(ROOT, "game", "fonts", "ui_fallback.otf")
ART = os.path.join(ROOT, "art", "incoming")

# ---------------------------------------------------------------- 截图
# 名字: (分辨率, Godot 参数, 产物文件)
CAPTURE = {
    "title": ("1280x720", ["--titleshot"], "shot_title.png"),
    "intro": ("1280x720", ["--introshot"], "shot_intro_22.png"),        # 开场 2.2 秒：镜头下摇完、Logo / 菜单还没出 = 干净 keyart
    "diff": ("1280x720", ["--diffshot=1,2"], "shot_diff_1_2.png"),
    "settings": ("1280x720", ["--settingsshot"], "shot_settings.png"),
    "credits": ("1280x720", ["--creditsshot"], "shot_credits.png"),
    "guide": ("1280x720", ["--guideshot"], "shot_guide.png"),
    "codex": ("1280x720", ["--galleryshot=0,0,0,1.5", "--galleryid=skadi"], "shot_gallery_ui.png"),
    "oppick": ("1280x720", ["--opshot", "--opid=skadi"], "shot_oppick.png"),
    "title_phone": ("1480x720", ["--titleshot", "--touch"], "shot_title.png"),
    "intro_phone": ("1480x720", ["--introshot", "--touch"], "shot_intro_22.png"),
}


def capture(names):
    import concurrent.futures as cf
    game = os.path.join(ROOT, "game")
    gr.ensure_imported(game)
    godot = gr.find_godot()

    def run(k):
        res, args, fn = CAPTURE[k]
        d = os.path.join(SHOTS, k)
        os.makedirs(d, exist_ok=True)
        gr.run_godot([godot, "--path", game, "--resolution", res, "--", "--shotdir=" + d] + args, 90)
        return k, os.path.exists(os.path.join(d, fn))

    with cf.ThreadPoolExecutor(4) as ex:
        for k, ok in ex.map(run, names):
            print("截图 %-12s %s" % (k, "好" if ok else "缺"), flush=True)


def shot(name, size=None):
    res, _, fn = CAPTURE[name]
    im = Image.open(os.path.join(SHOTS, name, fn)).convert("RGBA")
    if size and im.size != size:
        im = im.resize(size, Image.LANCZOS)
    return im


# ---------------------------------------------------------------- C4' 令牌（与 ui.gd UI.C_* 一致）
YEL = (255, 206, 0)                 # C_ACC 警示黄
HZ = (22, 24, 28)                   # C_HZ
INK = (22, 24, 28)                  # C_L_INK
SUB = (92, 96, 104)                 # C_L_SUB
GLASS = (226, 228, 231, 209)        # C_L_GLASS（透明度 0.82，10-11 图鉴右侧面板）
LPANEL = (250, 250, 250, 240)       # C_L_PANEL
LSEL = (255, 247, 206, 250)         # C_L_SEL
DINK = (236, 238, 240)              # C_D_INK
DSUB = (146, 151, 160)              # C_D_SUB
LINK = (36, 92, 150)                # 浅底上的链接色（概念）
CYAN = (54, 226, 220)
RED = (255, 61, 139)
CLS_SPECIAL = (191, 153, 255)       # 封面干员水月 = 特种（Character.CLASS_COL）
SHIFT = 300                         # T1：keyart 整体左移，让巨树和封面干员落在暗舞台里（title_bg 加 x 偏移）
SHIFT_P = 230                       # 手机同理（740 宽设计坐标）

MENU = [("集结出发", "DEPLOY"), ("图鉴", "GALLERY"), ("Boss 演练", "BOSS TRIAL"), ("操作说明", "GUIDE"), ("设置", "SETTINGS"), ("退出", "EXIT")]
MENU_SUB = ["选择干员与难度，走进深海", "干员、敌人、藏品与结局档案", "直接选择 Boss，检查招式与阶段", "键盘、手柄与触屏操作", "画面、声音与操作设置", "离开游戏"]

_UI_CMAP = None
try:
    from fontTools.ttLib import TTFont
    _UI_CMAP = TTFont(FONT_UI).getBestCmap()
except Exception:
    pass


def F(size, s="汉"):
    if _UI_CMAP is not None and os.path.exists(FONT_FB) and any(ord(ch) not in _UI_CMAP for ch in s if not ch.isspace()):
        return ImageFont.truetype(FONT_FB, size)
    return ImageFont.truetype(FONT_UI, size)


def layer(img):
    return Image.new("RGBA", img.size, (0, 0, 0, 0))


def over(img, fn):
    """在透明层上画（半透明填充才会正确混合），再叠回去"""
    ov = layer(img)
    fn(ImageDraw.Draw(ov))
    img.alpha_composite(ov)


def text(img, xy, s, size, col=INK, anchor="la", bold=False):
    d = ImageDraw.Draw(img)
    f = F(size, s)
    d.text(xy, s, font=f, fill=col, anchor=anchor, stroke_width=1 if bold else 0, stroke_fill=col)
    return d.textlength(s, font=f)


def code(img, xy, s, size=9, col=SUB, spacing=2, anchor="la"):
    """微型代码：宽字距小号英文（UI.code）"""
    f = F(size, s)
    d = ImageDraw.Draw(img)
    w = sum(d.textlength(ch, font=f) for ch in s) + spacing * (len(s) - 1)
    x, y = xy
    if anchor[0] == "r":
        x -= w
    elif anchor[0] == "m":
        x -= w / 2
    for ch in s:
        d.text((x, y), ch, font=f, fill=col, anchor="l" + anchor[1])
        x += d.textlength(ch, font=f) + spacing
    return w


def ghost(img, xy, s, size, col, stroke=2):
    """巨型描边英文（UI.ghost_name）"""
    over(img, lambda d: d.text(xy, s, font=F(size, s), fill=(0, 0, 0, 0), stroke_width=stroke, stroke_fill=col))


def para(d, box, skew, fill=None, outline=None, width=1):
    """平行四边形（右倾）：页签 / 按钮 / 菜单行"""
    x0, y0, x1, y1 = box
    d.polygon([(x0 + skew, y0), (x1, y0), (x1 - skew, y1), (x0, y1)], fill=fill, outline=outline, width=width)


def hazard(img, box, step=8):
    """黄黑警示条"""
    x0, y0, x1, y1 = [int(v) for v in box]
    w, h = x1 - x0, y1 - y0
    tile = Image.new("RGBA", (w, h), YEL + (255,))
    d = ImageDraw.Draw(tile)
    for x in range(-h - step * 2, w + h, step * 2):
        d.polygon([(x, h), (x + step, h), (x + step + h, 0), (x + h, 0)], fill=HZ + (255,))
    img.alpha_composite(tile, (x0, y0))


def emblem(img, c, r, col):
    """本作徽记：菱形 + 一道浪（title.gd _draw_emblem 的简化）"""
    x, y = c
    d = ImageDraw.Draw(img)
    d.polygon([(x, y - r), (x + r, y), (x, y + r), (x - r, y)], outline=col, width=2)
    pts = [(x - r * 0.55 + i * r * 0.11, y + 1.5 * math.sin(i * 0.9)) for i in range(11)]
    d.line(pts, fill=col, width=2)


def logo(scale=1.0, sweep=1.0):
    """像素 Logo（art/incoming/logo.png，最近邻缩放）；sweep < 1 = 扫光进行中，只露出左边一截 + 青色扫光边"""
    im = Image.open(os.path.join(ART, "logo.png")).convert("RGBA")
    if scale != 1.0:
        im = im.resize((int(im.width * scale), int(im.height * scale)), Image.NEAREST)
    if sweep < 1.0:
        cut = int(im.width * max(0.0, sweep))
        out = Image.new("RGBA", im.size, (0, 0, 0, 0))
        out.paste(im.crop((0, 0, cut, im.height)), (0, 0))
        ImageDraw.Draw(out).rectangle([cut - 3, 0, cut, im.height], fill=CYAN + (200,))
        return out
    return im


def vignette(img, w, a=0.42):
    """左侧柔和暗角（同 title.gd：14 条渐隐竖带）"""
    def f(d):
        n = 14
        for i in range(n):
            d.rectangle([i * w / n, 0, (i + 1) * w / n, img.height], fill=(0, 3, 8, int(255 * a * (1 - i / n) ** 1.6)))
    over(img, f)


def dim(im, k):
    """压暗（k = 保留的亮度）"""
    out = im.copy()
    out.alpha_composite(Image.new("RGBA", im.size, (0, 0, 0, int(255 * (1 - k)))))
    return out


def keyart(phone=False, shift=0):
    """干净的 keyart：开场 2.2 秒那一帧（镜头下摇完、Logo / 菜单还没出）；shift = 整体左移"""
    im = shot("intro_phone", (PW, PH)) if phone else shot("intro", (W, H))
    if shift:
        base = Image.new("RGBA", im.size, (6, 8, 14, 255))
        base.alpha_composite(im.crop((shift, 0, im.width, im.height)), (0, 0))
        im = base
    return im


def glass_split(img, x_top, x_bot, y0=0, y1=None, edge=3):
    """C4' 明暗分区：右侧半透明浅色终端面板 + 3 px 黄色斜边"""
    y1 = img.height if y1 is None else y1
    over(img, lambda d: d.polygon([(x_top, y0), (img.width, y0), (img.width, y1), (x_bot, y1)], fill=GLASS))
    ImageDraw.Draw(img).line([(x_top, y0), (x_bot, y1)], fill=YEL, width=edge)


def band(img, x_bot, w, h, col, a=80, shear=210):
    """职业色斜带（倾角约 66°，与选人 / 图鉴同一条几何）+ 黑细带"""
    def f(d):
        d.polygon([(x_bot, h), (x_bot + w, h), (x_bot + w + shear, 0), (x_bot + shear, 0)], fill=col + (a,))
        d.polygon([(x_bot + w + 12, h), (x_bot + w + 24, h), (x_bot + w + 24 + shear, 0), (x_bot + w + 12 + shear, 0)], fill=HZ + (120,))
    over(img, f)


def head_block(img, x0, x1, h, en_s, cn_s, hz=22, cn=22):
    """浅色标题块 + 右端警示条（图鉴左上 ARCHIVE 块的同款）"""
    ImageDraw.Draw(img).rectangle([x0, 0, x1, h], fill=LPANEL[:3])
    hazard(img, (x1, 0, x1 + hz, h))
    code(img, (x0 + 18, h * 0.3), en_s, 9 if h > 50 else 7, SUB, 2, "lm")
    text(img, (x0 + 18, h * 0.68), cn_s, cn, INK, "lm", bold=True)


def keycap(img, xy, s, col=INK, size=10):
    d = ImageDraw.Draw(img)
    f = F(size, s)
    w = d.textlength(s, font=f) + 12
    x, y = xy
    d.rectangle([x, y, x + w, y + size + 8], outline=col, width=1)
    d.text((x + 6, y + 4), s, font=f, fill=col)
    return w


def ctabs(img, x, y, names, sel, w=150, h=34, skew=10, ink=INK):
    """平行四边形大页签（图鉴同款）：01 / 02 小代码 + 中文 + 英文"""
    d = ImageDraw.Draw(img)
    for i, (cn, e) in enumerate(names):
        bx = x + i * (w + 8)
        if i == sel:
            para(d, (bx, y, bx + w, y + h), skew, fill=YEL)
            col, sc = INK, INK
        else:
            para(d, (bx, y, bx + w, y + h), skew, fill=None, outline=ink, width=1)
            col, sc = ink, SUB
        code(img, (bx + skew + 8, y + 9), "%02d" % (i + 1), 7, sc, 1, "lm")
        text(img, (bx + skew + 26, y + h / 2 + 1), cn, 16, col, "lm", bold=(i == sel))
        code(img, (bx + w - skew - 10, y + h / 2 + 1), e, 7, sc, 2, "rm")
    d.line([(x, y + h + 6), (x + len(names) * (w + 8) - 8, y + h + 6)], fill=ink, width=2)


def callout(img, xy, n):
    x, y = xy
    d = ImageDraw.Draw(img)
    d.ellipse([x - 11, y - 11, x + 11, y + 11], fill=RED, outline=(255, 255, 255), width=2)
    d.text((x, y), str(n), font=F(13, "1"), fill=(255, 255, 255), anchor="mm")


def cover_tag(img, box, small=False):
    """封面干员小牌：暗底 + 职业色左条 + 名字 + 「更换 V」平行四边形"""
    x0, y0, x1, y1 = box
    over(img, lambda d: d.rectangle(box, fill=(10, 12, 16, 205)))
    d = ImageDraw.Draw(img)
    d.rectangle([x0, y0, x0 + 4, y1], fill=CLS_SPECIAL)
    if not small:
        code(img, (x0 + 16, y0 + 12), "COVER OPERATOR  //  No.01  //  SPECIALIST", 7, (170, 176, 182), 2, "lm")
    text(img, (x0 + 16, y1 - (16 if not small else (y1 - y0) / 2)), "水月", 16 if not small else 14, DINK, "lm", bold=True)
    if not small:
        code(img, (x0 + 58, y1 - 16), "MIZUKI", 9, (170, 176, 182), 3, "lm")
    bw = 78 if not small else 60
    para(d, (x1 - bw - 8, y1 - 30 if not small else y0 + 6, x1 - 8, y1 - 6), 6, outline=DINK)
    text(img, (x1 - bw / 2 - 8, (y1 - 18) if not small else (y0 + y1) / 2), "更换  V" if not small else "更换", 12 if not small else 11, DINK, "mm")


# ---------------------------------------------------------------- 菜单行
def menu_rows(img, x0, y0, w, step, sel, fs=22, en=10, skew=12, sub=True, n=6):
    """竖排菜单（浅色面板上）：选中 = 黄色平行四边形 + 左端黑块编号 + 黑投影；其余 = 编号 + 墨色字 + 1 px 细线"""
    d = ImageDraw.Draw(img)
    rows = []
    for i, (cn, e) in enumerate(MENU[:n]):
        y = y0 + i * step + (24 if (sub and i > sel) else 0)   # 选中行下方让出一行说明
        h = step - 10
        rows.append((x0, y, x0 + w, y + h))
        if i == sel:
            over(img, lambda dd: para(dd, (x0 + 5, y + 4, x0 + w + 5, y + h + 4), skew, fill=(0, 0, 0, 80)))
            para(d, (x0, y, x0 + w, y + h), skew, fill=YEL)
            para(d, (x0, y, x0 + 48, y + h), skew, fill=HZ)
            code(img, (x0 + 26, y + h / 2), "%02d" % (i + 1), 11, YEL, 1, "mm")
            text(img, (x0 + 62, y + h / 2), cn, fs, INK, "lm", bold=True)
            code(img, (x0 + w - 24, y + h / 2), e, en, INK, 2, "rm")
        else:
            code(img, (x0 + 26, y + h / 2), "%02d" % (i + 1), 10, SUB, 1, "mm")
            text(img, (x0 + 62, y + h / 2), cn, fs - 2, INK, "lm")
            code(img, (x0 + w - 24, y + h / 2), e, en - 1, SUB, 2, "rm")
            d.line([(x0 + 54, y + h + 4), (x0 + w - 14, y + h + 4)], fill=(22, 24, 28, 60), width=1)
    if sub:
        y = y0 + sel * step + step - 8
        text(img, (x0 + 62, y + 3), MENU_SUB[sel], max(12, fs - 9), SUB)
    return rows


# ---------------------------------------------------------------- 标题 T1「档案终端」（推荐）
T1_XT, T1_XB = 880, 830


def title_T1(sel=0, panel_t=1.0, logo_t=1.0, marks=False, beam_from=None):
    img = keyart(shift=SHIFT)
    vignette(img, 640)
    ghost(img, (30, 478), "SURVIVORS", 150, (255, 255, 255, 30))
    emblem(img, (56, 46), 8, (196, 202, 206))
    code(img, (74, 46), "ARKNIGHTS FAN GAME  //  ROGUELIKE SURVIVORS", 10, (150, 156, 162), 2, "lm")
    if logo_t > 0:
        img.alpha_composite(logo(0.86, logo_t), (44, 82))
    if logo_t >= 1.0:
        code(img, (50, 212), "ARKNIGHTS  SURVIVORS", 13, (220, 226, 230), 5, "lm")
        text(img, (50, 240), "水月与深蓝之树", 15, (230, 234, 238), "lm")
        code(img, (172, 240), "MIZUKI & CAERULA ARBOR", 9, (150, 156, 162), 2, "lm")
    if panel_t <= 0.0:
        return img
    cover_tag(img, (44, 636, 336, 690))
    k = 1 - (1 - min(1.0, panel_t)) ** 3
    dx = int(320 * (1 - k))
    pan = layer(img)
    glass_split(pan, T1_XT, T1_XB)
    head_block(pan, T1_XT + 30, W - 26, 64, "TERMINAL  //  MAIN MENU", "主界面", 26)
    rows = menu_rows(pan, T1_XT - 8, 100, 376, 66, sel)
    pd = ImageDraw.Draw(pan)
    code(pan, (T1_XB + 66, 592), "STATUS  //  LAMP 03  //  SAVE OK", 8, SUB, 2, "lm")
    pd.line([(T1_XB + 58, 608), (W - 24, 608)], fill=INK, width=1)
    code(pan, (T1_XB + 66, 628), "W / S  ·  ↑ ↓  SELECT      ENTER  CONFIRM", 9, SUB, 2, "lm")
    text(pan, (T1_XB + 66, 662), "明日方舟同人作品 · 非商业 · 致谢与声明 C", 12, SUB, "lm")
    code(pan, (W - 26, 694), "v2.0", 10, SUB, 2, "rm")
    if beam_from is not None:
        # 灯标光束（docs/62 §3.1）：从巨树根部的灯标打到选中行左端，加色 25 %
        r = rows[sel]
        tgt = (r[0] + 4, (r[1] + r[3]) / 2)
        sx, sy = beam_from
        ang = math.atan2(tgt[1] - sy, tgt[0] - sx)
        L = math.hypot(tgt[0] - sx, tgt[1] - sy)
        sp = math.radians(3)
        beam = layer(img)
        bd = ImageDraw.Draw(beam)
        bd.polygon([(sx, sy), (sx + L * math.cos(ang - sp), sy + L * math.sin(ang - sp)), (sx + L * math.cos(ang + sp), sy + L * math.sin(ang + sp))], fill=(200, 250, 250, 70))
        img.alpha_composite(beam.filter(ImageFilter.GaussianBlur(3)))
    img.alpha_composite(pan, (dx, 0))
    if marks:
        for n_, xy in enumerate([(40, 86), (T1_XT + 40, 14), (T1_XT + 4, 128), (W - 14, 32), (40, 640), (30, 520), (T1_XT - 18, 360)], 1):
            callout(img, xy, n_)
    return img


# ---------------------------------------------------------------- 标题 T2「全幅 + 终端条」
def title_T2(sel=0):
    img = keyart()
    d = ImageDraw.Draw(img)
    vignette(img, 640, 0.3)
    emblem(img, (56, 46), 8, (196, 202, 206))
    code(img, (74, 46), "ARKNIGHTS FAN GAME  //  ROGUELIKE SURVIVORS", 10, (150, 156, 162), 2, "lm")
    img.alpha_composite(logo(0.8), (44, 80))
    code(img, (50, 200), "ARKNIGHTS  SURVIVORS", 12, (220, 226, 230), 5, "lm")
    text(img, (50, 226), "水月与深蓝之树", 14, (230, 234, 238), "lm")
    cover_tag(img, (976, 24, 1256, 76))
    y0, y1 = 590, 676
    over(img, lambda dd: dd.rectangle([0, y0, W, y1], fill=GLASS))
    d.line([(0, y0), (W, y0)], fill=YEL, width=3)
    d.rectangle([0, y0 + 2, 150, y1], fill=HZ)
    hazard(img, (150, y0 + 2, 166, y1))
    code(img, (24, y0 + 26), "MAIN  MENU", 9, (170, 176, 182), 2, "lm")
    text(img, (24, y0 + 56), "主界面", 20, DINK, "lm", bold=True)
    x = 188
    widths = [200, 130, 160, 160, 130, 120]
    for i, (cn, e) in enumerate(MENU):
        w = widths[i]
        if i == sel:
            over(img, lambda dd: para(dd, (x + 5, y0 + 18, x + w + 5, y1 - 10), 14, fill=(0, 0, 0, 80)))
            para(d, (x, y0 + 14, x + w, y1 - 14), 14, fill=YEL)
            text(img, (x + w / 2, y0 + 39), cn, 22, INK, "mm", bold=True)
            code(img, (x + w / 2, y1 - 28), e, 9, INK, 2, "mm")
        else:
            para(d, (x, y0 + 14, x + w, y1 - 14), 14, outline=INK)
            text(img, (x + w / 2, y0 + 39), cn, 19, INK, "mm")
            code(img, (x + w / 2, y1 - 28), e, 8, SUB, 2, "mm")
        x += w + 8
    over(img, lambda dd: dd.rectangle([188, y0 - 36, 188 + 330, y0 - 8], fill=(10, 12, 16, 200)))
    code(img, (200, y0 - 22), "01", 9, YEL, 1, "lm")
    text(img, (224, y0 - 22), MENU_SUB[sel], 14, DINK, "lm")
    code(img, (24, 699), "← →  /  A D  SELECT      ENTER  CONFIRM", 9, (150, 156, 162), 2, "lm")
    text(img, (W - 26, 699), "明日方舟同人作品 · 非商业 · 致谢与声明 C    v2.0", 12, (150, 156, 162), "rm")
    return img


# ---------------------------------------------------------------- 标题 T3「极简」
def title_T3(sel=0):
    img = keyart()
    d = ImageDraw.Draw(img)
    over(img, lambda dd: dd.polygon([(0, 0), (560, 0), (380, H), (0, H)], fill=(0, 4, 10, 120)))
    ghost(img, (16, 286), "ARKNIGHTS", 128, (255, 255, 255, 34))
    ghost(img, (16, 410), "SURVIVORS", 128, (255, 255, 255, 34))
    head_block(img, 0, 210, 54, "TITLE  //  ARKNIGHTS SURVIVORS", "方舟幸存者", 18)
    img.alpha_composite(logo(0.7), (40, 92))
    text(img, (46, 210), "水月与深蓝之树", 14, (230, 234, 238), "lm")
    code(img, (168, 210), "MIZUKI & CAERULA ARBOR", 9, (150, 156, 162), 2, "lm")
    y = 300
    for i, (cn, e) in enumerate(MENU):
        h = 40
        w = 250 if i == sel else 210
        if i == sel:
            para(d, (40, y, 40 + w, y + h), 12, fill=YEL)
            text(img, (62, y + h / 2), cn, 21, INK, "lm", bold=True)
            code(img, (40 + w - 20, y + h / 2), e, 9, INK, 2, "rm")
            text(img, (40 + w + 16, y + h / 2), MENU_SUB[sel], 13, (220, 226, 230), "lm")
        else:
            over(img, lambda dd: para(dd, (40, y, 40 + w, y + h), 12, fill=(15, 16, 19, 200)))
            text(img, (62, y + h / 2), cn, 18, DINK, "lm")
            code(img, (40 + w - 20, y + h / 2), e, 8, DSUB, 2, "rm")
        y += h + 8
    code(img, (40, 692), "明日方舟同人作品  ·  非商业  ·  致谢与声明 C", 9, (150, 156, 162), 2, "lm")
    code(img, (W - 26, 692), "COVER  //  MIZUKI   V        v2.0", 9, (150, 156, 162), 2, "rm")
    return img


# ---------------------------------------------------------------- 手机 740×360（设计坐标，实机再整体缩放，同选人 / 图鉴）
def title_T1_phone(sel=0):
    img = keyart(phone=True, shift=SHIFT_P)
    vignette(img, 360)
    ghost(img, (10, 252), "SURVIVORS", 74, (255, 255, 255, 30), 1)
    img.alpha_composite(logo(0.5), (18, 22))
    text(img, (22, 104), "水月与深蓝之树", 13, (230, 234, 238), "lm")
    cover_tag(img, (16, 310, 200, 346), small=True)
    pan = layer(img)
    xt, xb = 456, 428
    glass_split(pan, xt, xb)
    head_block(pan, xt + 18, PW - 16, 40, "TERMINAL  //  MENU", "主界面", 15, cn=15)
    menu_rows(pan, xt - 8, 50, 272, 50, sel, fs=19, en=8, skew=9, sub=False)
    code(pan, (PW - 12, 50), "CREDITS  C", 7, SUB, 2, "rm")
    img.alpha_composite(pan)
    return img


def title_T2_phone(sel=0):
    img = keyart(phone=True)
    d = ImageDraw.Draw(img)
    img.alpha_composite(logo(0.5), (18, 22))
    text(img, (22, 104), "水月与深蓝之树", 12, (230, 234, 238), "lm")
    cover_tag(img, (540, 14, 724, 50), small=True)
    y0, y1 = 282, 352
    over(img, lambda dd: dd.rectangle([0, y0, PW, y1], fill=GLASS))
    d.line([(0, y0), (PW, y0)], fill=YEL, width=3)
    hazard(img, (0, y0 + 2, 12, y1))
    x = 22
    widths = [140, 92, 116, 116, 86]
    for i, (cn, e) in enumerate(MENU[:5]):
        w = widths[i]
        if i == sel:
            para(d, (x, y0 + 12, x + w, y1 - 10), 10, fill=YEL)
            text(img, (x + w / 2, y0 + 31), cn, 18, INK, "mm", bold=True)
            code(img, (x + w / 2, y1 - 20), e, 7, INK, 1, "mm")
        else:
            para(d, (x, y0 + 12, x + w, y1 - 10), 10, outline=INK)
            text(img, (x + w / 2, y0 + 31), cn, 16, INK, "mm")
            code(img, (x + w / 2, y1 - 20), e, 7, SUB, 1, "mm")
        x += w + 8
    return img


def title_T3_phone(sel=0):
    img = keyart(phone=True)
    d = ImageDraw.Draw(img)
    over(img, lambda dd: dd.polygon([(0, 0), (330, 0), (230, PH), (0, PH)], fill=(0, 4, 10, 120)))
    ghost(img, (8, 196), "SURVIVORS", 70, (255, 255, 255, 34), 1)
    img.alpha_composite(logo(0.42), (18, 18))
    y = 104
    for i, (cn, e) in enumerate(MENU[:5]):
        h, w = 38, (196 if i == sel else 164)
        if i == sel:
            para(d, (20, y, 20 + w, y + h), 9, fill=YEL)
            text(img, (40, y + h / 2), cn, 18, INK, "lm", bold=True)
        else:
            over(img, lambda dd: para(dd, (20, y, 20 + w, y + h), 9, fill=(15, 16, 19, 200)))
            text(img, (40, y + h / 2), cn, 16, DINK, "lm")
        y += h + 6
    return img


# ---------------------------------------------------------------- 内页（T1 语言）
def inner_stage(ghost_s, k=0.42):
    """内页舞台：T1 同一张 keyart（同样左移）压暗 + 巨型描边英文"""
    img = dim(keyart(shift=SHIFT), k)
    ghost(img, (24, 520), ghost_s, 140, (255, 255, 255, 26))
    emblem(img, (40, 92), 7, (170, 176, 182))
    code(img, (56, 92), "ARKNIGHTS SURVIVORS  //  TITLE", 8, (130, 136, 142), 2, "lm")
    return img


def diff_C4():
    img = inner_stage("RISING TIDE")
    d = ImageDraw.Draw(img)
    head_block(img, 0, 330, 64, "OPERATION  //  DIFFICULTY", "选择难度", 24)
    # 舞台：大号档位 + 潮位（docs/62 §3.3 潮位上涨：水位升到所选档刻度）
    lvl_y = 360
    def water(dd):
        pts = [(0, H)] + [(x, lvl_y + 6 * math.sin(x / 38.0) + 3 * math.sin(x / 13.0 + 1)) for x in range(0, 560, 8)] + [(552, H)]
        dd.polygon(pts, fill=(40, 120, 150, 70))
        dd.line(pts[1:-1], fill=(150, 240, 240, 150), width=2)
    over(img, water)
    text(img, (60, 230), "Ⅳ", 120, YEL, "ls", bold=True)
    code(img, (66, 256), "TIER  02 / 03  //  LEVEL 4", 9, (200, 204, 208), 2, "lm")
    text(img, (60, 300), "波涛迭起 · Ⅳ", 30, DINK, "lm", bold=True)
    code(img, (62, 330), "RISING TIDE  IV", 11, (190, 196, 202), 4, "lm")
    # 潮位刻度（舞台右缘）
    for i, (lab, yy) in enumerate([("≈", 470), ("Ⅳ", lvl_y), ("Ⅷ", 250)]):
        d.line([(470, yy), (500, yy)], fill=(220, 224, 228), width=2 if i == 1 else 1)
        text(img, (462, yy), lab, 14, YEL if i == 1 else (200, 204, 208), "rm")
    d.line([(500, 230), (500, 500)], fill=(200, 204, 208), width=1)
    d.polygon([(506, lvl_y), (514, lvl_y - 7), (522, lvl_y), (514, lvl_y + 7)], fill=YEL)
    # 右侧终端面板
    xt, xb = 600, 556
    glass_split(img, xt, xb)
    ctabs(img, xt + 20, 34, [("标准", "STANDARD"), ("Ⅳ", "TIER IV"), ("Ⅷ", "TIER VIII")], 1, w=196)
    x0 = xb + 66
    code(img, (x0, 112), "TIER FILE  //  MODIFIERS", 9, SUB, 2, "lm")
    text(img, (x0, 140), "暗礁更多，灯火更难守住。", 18, INK, "lm")
    effs = [("敌人生命", "+20%"), ("敌人造成的伤害", "+20%"), ("Boss 生命", "+15%"), ("受击时灯火损失", "+30%"), ("灯油掉落", "−30%"),
            ("源石锭掉落", "−10%"), ("Boss 预警最多缩短", "15%"), ("大群规模", "+20%"), ("小怪控制提前到", "5:00"), ("寒霜 2 层即冻结", "")]
    for i, (a, b) in enumerate(effs):
        col, row = i // 5, i % 5
        bx = x0 + col * 316
        by = 170 + row * 58
        over(img, lambda dd: dd.rectangle([bx, by, bx + 300, by + 48], fill=LPANEL))
        d.rectangle([bx, by, bx + 300, by + 48], outline=INK, width=1)
        d.rectangle([bx, by, bx + 3, by + 48], fill=INK)
        code(img, (bx + 14, by + 12), "MOD %02d" % (i + 1), 7, SUB, 2, "lm")
        text(img, (bx + 14, by + 32), a, 15, INK, "lm")
        if b:
            text(img, (bx + 288, by + 26), b, 22, INK, "rm", bold=True)
    # 主操作：出发（左段警示条）+ 返回
    by = 612
    para(d, (x0, by, x0 + 300, by + 56), 16, fill=YEL)
    hazard(img, (x0 + 18, by + 2, x0 + 64, by + 54))
    para(d, (x0, by, x0 + 300, by + 56), 16, outline=INK, width=2)
    text(img, (x0 + 84, by + 30), "出发", 26, INK, "lm", bold=True)
    code(img, (x0 + 280, by + 30), "ENTER  //  PAD A", 9, INK, 2, "rm")
    para(d, (x0 + 320, by + 8, x0 + 470, by + 48), 12, outline=INK, width=1)
    text(img, (x0 + 395, by + 28), "返回  Esc", 15, INK, "mm")
    code(img, (W - 26, 700), "← →  CHANGE TIER", 8, SUB, 2, "rm")
    return img


def settings_C4():
    img = inner_stage("SETTINGS")
    d = ImageDraw.Draw(img)
    head_block(img, 0, 300, 64, "SYSTEM  //  SETTINGS", "设置", 24)
    code(img, (40, 640), "CFG  //  3 PAGES  //  AUTOSAVE ON CLOSE", 9, (170, 176, 182), 2, "lm")
    xt, xb = 420, 376
    glass_split(img, xt, xb)
    ctabs(img, xt + 24, 34, [("声音", "SOUND"), ("画面", "DISPLAY"), ("游戏", "GAMEPLAY")], 0, w=176)
    keycap(img, (W - 92, 40), "Q")
    keycap(img, (W - 62, 40), "E")
    x0 = xb + 70
    rows = [("主音量", "MASTER", 8), ("音乐", "MUSIC", 6), ("音效", "SFX", 9), ("语音", "VOICE", 7)]
    for i, (cn, e, v) in enumerate(rows):
        y = 116 + i * 70
        sel = i == 0
        over(img, lambda dd: dd.rectangle([x0, y, W - 40, y + 58], fill=LSEL if sel else LPANEL))
        d.rectangle([x0, y, W - 40, y + 58], outline=INK, width=2 if sel else 1)
        if sel:
            d.rectangle([x0, y, x0 + 5, y + 58], fill=YEL)
        text(img, (x0 + 24, y + 29), cn, 19, INK, "lm", bold=sel)
        code(img, (x0 + 120, y + 29), e, 8, SUB, 2, "lm")
        sx = x0 + 300
        text(img, (sx - 18, y + 29), "◀", 14, INK, "mm")
        for k in range(10):
            para(d, (sx + k * 30, y + 18, sx + k * 30 + 24, y + 40), 5, fill=(YEL if sel else INK) if k < v else None, outline=INK)
        text(img, (sx + 312, y + 29), "▶", 14, INK, "mm")
        text(img, (W - 60, y + 30), str(v * 10), 24, INK, "rm", bold=True)
    # 返回钉在底部
    d.line([(x0, 600), (W - 40, 600)], fill=INK, width=1)
    para(d, (x0, 618, x0 + 170, 662), 12, outline=INK, width=2)
    text(img, (x0 + 85, 640), "返回  Esc", 16, INK, "mm")
    code(img, (x0 + 200, 640), "Q / E  PAGE    ↑ ↓  SELECT    ← →  ADJUST", 9, SUB, 2, "lm")
    return img


def credits_C4():
    img = inner_stage("CREDITS")
    d = ImageDraw.Draw(img)
    head_block(img, 0, 360, 64, "ARCHIVE  //  CREDITS & DISCLAIMER", "致谢与声明", 24)
    xt, xb = 330, 290
    glass_split(img, xt, xb)
    x0 = xb + 70
    rows = [("同人声明", "《方舟幸存者》是《明日方舟》的非官方同人作品，免费、非商业。角色、世界观、名称与「水月与深蓝之树」的设定均属于鹰角网络（Hypergryph），本作与鹰角网络无关。", ""),
            ("明日方舟游戏数据", "藏品名称、编号与敌人设定的核对参考自社区整理的游戏数据仓库。", "https://github.com/Kengxxiao/ArknightsGameData"),
            ("PRTS Wiki", "机制与文案参考。", "https://prts.wiki"),
            ("像素美术", "角色、敌人、场景与特效为根据《明日方舟》游戏美术二次创作的像素画，由 Claude（Anthropic）与 ChatGPT / Codex（OpenAI）程序化绘制。", ""),
            ("引擎", "Godot Engine 4.7（MIT 许可）。", "https://godotengine.org")]
    y = 40
    tw = W - 60 - (x0 + 190)
    for i, (lab, body, link) in enumerate(rows):
        para(d, (x0, y, x0 + 170, y + 28), 8, fill=INK)
        code(img, (x0 + 14, y + 14), "%02d" % (i + 1), 7, YEL, 1, "lm")
        text(img, (x0 + 36, y + 14), lab, 14, DINK, "lm", bold=True)
        lines = wrap(body, 17, tw)
        for k, ln in enumerate(lines):
            text(img, (x0 + 190, y + 2 + k * 27), ln, 17, INK)
        yy = y + 2 + len(lines) * 27
        if link:
            text(img, (x0 + 190, yy + 2), link, 14, LINK)
            yy += 24
        y = yy + 18
    # 滚动条：墨色细轨 + 黄色滑块
    d.rectangle([W - 40, 40, W - 34, 590], fill=(22, 24, 28, 40))
    d.rectangle([W - 40, 40, W - 34, 230], fill=YEL, outline=INK)
    d.line([(x0, 600), (W - 40, 600)], fill=INK, width=1)
    text(img, (x0, 630), "如有侵权请通过小红书 菜月colafax（373145407）联系作者，将立即处理。", 14, SUB, "lm")
    code(img, (x0, 656), "WHEEL / ↑ ↓ / PGUP PGDN  SCROLL", 8, SUB, 2, "lm")
    para(d, (W - 210, 618, W - 40, 662), 12, outline=INK, width=2)
    text(img, (W - 125, 640), "返回  Esc", 16, INK, "mm")
    return img


def wrap(s, size, width):
    f = F(size, s)
    d = ImageDraw.Draw(Image.new("RGBA", (1, 1)))
    out, cur = [], ""
    for ch in s:
        if d.textlength(cur + ch, font=f) > width and cur:
            if ch in "，。、；：」）》":   # 标点不放行首
                cur += ch
                continue
            out.append(cur)
            cur = ch
        else:
            cur += ch
    if cur:
        out.append(cur)
    return out


# ---------------------------------------------------------------- 动效分镜（T1）
def ring_mix(outside, inside, c, r):
    """声呐环揭开（docs/62 §3.2）：环内新页、环外旧页，环 + 两道回波"""
    mask = Image.new("L", outside.size, 0)
    ImageDraw.Draw(mask).ellipse([c[0] - r, c[1] - r, c[0] + r, c[1] + r], fill=255)
    out = outside.copy()
    out.paste(inside, (0, 0), mask)
    d = ImageDraw.Draw(out)
    for k, (dr, a) in enumerate([(0, 230), (-26, 110), (-52, 50)]):
        rr = r + dr
        if rr > 0:
            over(out, lambda dd: dd.ellipse([c[0] - rr, c[1] - rr, c[0] + rr, c[1] + rr], outline=CYAN + (a,), width=3 if k == 0 else 2))
    return out


def motion_T1():
    a = shot("intro", (W, H))   # 现有开场：镜头下摇（背景层，不动）
    f1 = keyart(shift=SHIFT)
    f1 = dim(f1, 0.7)
    f2 = title_T1(sel=0, panel_t=0.35, logo_t=0.55)
    f3 = title_T1(sel=1, beam_from=(560, 300))
    rows_y = 100 + 4 * 66 + 24 + 28
    f4 = ring_mix(title_T1(sel=4), settings_C4(), (T1_XT + 40, rows_y), 520)
    caps = ["① 0.4–2.2 s  镜头下摇（不变；keyart 左移 300，右侧黑边是截图平移的空白，实机由 title_bg 补画）",
            "② 2.6–3.2 s  Logo 扫光（不变）+ 3.0 s 起终端面板从右滑入 300 ms",
            "③ 换选项：黄条 200 ms 滑到新行 + 灯标光束从巨树打到该行（docs/62 §3.1）",
            "④ 进内页：声呐环从选中行扩散 600 ms，环内是 C4' 内页（docs/62 §3.2）"]
    tw, th = 640, 360
    sheet = Image.new("RGBA", (tw * 2 + 30, (th + 40) * 2 + 70), (18, 20, 24, 255))
    text(sheet, (14, 30), "T1 动效分镜（开场与换页沿用 docs/62，只改落点）", 22, DINK, "lm", bold=True)
    for i, f in enumerate([f1, f2, f3, f4]):
        x = 10 + (i % 2) * (tw + 10)
        y = 60 + (i // 2) * (th + 40)
        sheet.alpha_composite(f.resize((tw, th), Image.LANCZOS), (x, y))
        text(sheet, (x, y + th + 20), caps[i], 14, DINK, "lm")
    return sheet


# ---------------------------------------------------------------- 总览
def tile(im, w=512):
    h = int(im.height * w / im.width)
    return im.resize((w, h), Image.LANCZOS)


def contact_sheet(rows, title, path):
    tw, gap = 512, 14
    th = 288
    cols = max(len(r[1]) for r in rows)
    width = 170 + cols * (tw + gap) + gap
    height = 74 + len(rows) * (th + 44 + gap)
    sheet = Image.new("RGBA", (width, height), (18, 20, 24, 255))
    text(sheet, (gap, 36), title, 24, DINK, "lm", bold=True)
    y = 74
    for name, items in rows:
        text(sheet, (gap, y + th / 2), name, 18, YEL, "lm", bold=True)
        for j, (cap, im) in enumerate(items):
            x = 170 + j * (tw + gap)
            t = tile(im, tw)
            if t.height < th:
                bg = Image.new("RGBA", (tw, th), (10, 11, 14, 255))
                bg.alpha_composite(t, (0, (th - t.height) // 2))
                t = bg
            sheet.alpha_composite(t.crop((0, 0, tw, th)), (x, y))
            text(sheet, (x, y + th + 20), cap, 14, DINK, "lm")
        y += th + 44 + gap
    sheet.convert("RGB").save(path)
    print("写出", path)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--capture", action="store_true")
    a = ap.parse_args()
    if a.capture:
        capture(list(CAPTURE))
    os.makedirs(OUT, exist_ok=True)
    cur = {k: shot(k, (W, H)) for k in ("title", "diff", "settings", "credits", "guide", "codex", "oppick")}
    cur_phone = shot("title_phone", (PW, PH))
    for k, im in cur.items():
        im.convert("RGB").save(os.path.join(OUT, "current_%s.png" % k))
    cur_phone.convert("RGB").save(os.path.join(OUT, "current_title_phone.png"))
    outs = {
        "title_T1_split": title_T1(),
        "title_T1_split_marked": title_T1(marks=True),
        "title_T2_strip": title_T2(),
        "title_T3_minimal": title_T3(),
        "title_T1_phone": title_T1_phone(),
        "title_T2_phone": title_T2_phone(),
        "title_T3_phone": title_T3_phone(),
        "diff_C4": diff_C4(),
        "settings_C4": settings_C4(),
        "credits_C4": credits_C4(),
        "motion_T1": motion_T1(),
    }
    for k, im in outs.items():
        im.convert("RGB").save(os.path.join(OUT, k + ".png"))
    contact_sheet([
        ("现状", [("标题（方案 A 时间轴菜单）", cur["title"]), ("难度", cur["diff"]), ("设置", cur["settings"]), ("致谢与声明（10-11 滚动版）", cur["credits"])]),
        ("标题三案", [("T1 档案终端：左舞台 + 右浅色终端菜单（推荐）", outs["title_T1_split"]), ("T2 全幅 keyart + 底部终端条", outs["title_T2_strip"]),
                     ("T3 极简：描边英文 + 一列平行四边形", outs["title_T3_minimal"]), ("参照：图鉴 C4'（现版）", cur["codex"])]),
        ("内页（T1 语言）", [("难度：潮位 + 平行四边形档位 + 警示条出发", outs["diff_C4"]), ("设置：页签 / 行卡 / 平行四边形音量格", outs["settings_C4"]),
                          ("致谢与声明：黑底条目签 + 黄滑块", outs["credits_C4"]), ("参照：选人 B+（不改）", cur["oppick"])]),
        ("手机 740×360", [("现状（手机）", cur_phone), ("T1 手机", outs["title_T1_phone"]), ("T2 手机", outs["title_T2_phone"]), ("T3 手机", outs["title_T3_phone"])]),
    ], "标题 / 局外菜单 C4' 改版概念（docs/67）", os.path.join(OUT, "contact_sheet.png"))


if __name__ == "__main__":
    main()
