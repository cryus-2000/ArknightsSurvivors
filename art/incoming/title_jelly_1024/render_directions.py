"""标题页·深海水母精修：同一构图（Codex 47-C 探索徽记）下三套细节方向的对照图。
场景底图、Logo 与绘图原语复制自 codex/ui-shell（43 / 41 / 47 版），本脚本不改原素材。
运行：D:/Anaconda/python.exe -B art/incoming/title_jelly_1024/render_directions.py
"""
from pathlib import Path
import importlib.util
import math
import sys
from PIL import Image, ImageDraw, ImageFilter, ImageChops

P = Path(__file__).resolve().parent
SRC = P / 'src'
OUT = P / 'directions'
sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location('prim', SRC / 'primitives_41.py')
u = importlib.util.module_from_spec(spec); spec.loader.exec_module(u)
u.P = SRC

W, H = 1280, 720
T = '#e9f0f3'; M = '#a2b9c8'; L = '#466171'; C = '#9de5ef'; INK = '#132734'
NEAR_WHITE = '#e6edf0'   # S4 近白选中
LABELS = {'headhunt': '寻访', 'gallery': '图鉴', 'cognition': '认知塑造', 'trial': '试炼'}
EN = {'headhunt': 'HEADHUNT', 'gallery': 'ARCHIVE', 'cognition': 'COGNITION', 'trial': 'TRIAL'}
ITEMS = list(LABELS)
ROW_Y = [224, 286, 348, 410]


def txt(im, x, y, s, size=22, col=T, face='regular', sp=0): u.text(im, x, y, s, size, col, face, sp)
def line(im, pts, col=L, w=1): u.line(im, pts, col, w)
def chevron(im, x, y, col=C, w=2): line(im, [(x - 7, y - 10), (x + 3, y), (x - 7, y + 10)], col, w)


def arc(im, x, y, r, a0, a1, col=L, w=1):
    line(im, [(x + r * math.cos(math.radians(a)), y + r * math.sin(math.radians(a))) for a in range(a0, a1 + 1)], col, w)


def text_w(s, size, face, sp=0):
    f = u.font(size, face); d = ImageDraw.Draw(Image.new('L', (1, 1)))
    return sum(d.textlength(ch, font=f) for ch in s) / u.S + sp * max(0, len(s) - 1)


# ---------- 场景处理 ----------
def scene(kind):
    bg = Image.open(SRC / 'background_native.png').convert('RGB').resize((1920, 1080), Image.Resampling.NEAREST)
    if kind == 'orig':
        return bg.convert('RGBA')
    lum = bg.convert('L')
    out = bg
    if kind in ('glow', 'deep'):
        # 水母发光：只取高亮像素（水母、光柱亮核）做柔光，叠回去 → 发光体与暗部分层
        mask = lum.point(lambda v: 255 if v > (150 if kind == 'glow' else 160) else 0)
        halo = mask.filter(ImageFilter.GaussianBlur(28))
        tint = Image.new('RGB', bg.size, (120, 200, 230))
        strength = 0.55 if kind == 'glow' else 0.38
        out = ImageChops.add(out, ImageChops.multiply(tint, Image.merge('RGB', [halo.point(lambda v: int(v * strength))] * 3)))
    if kind == 'deep':
        # 暗部再压一档（中低调 gamma），高光不动 → 层次拉开
        out = out.point(lambda v: int(255 * (v / 255) ** 1.18))
    # 四周压暗 + 左侧阅读衬底（菜单区可读性）
    vig = Image.new('L', (1920, 1080), 0); dv = ImageDraw.Draw(vig)
    for i in range(60):
        k = i / 60
        dv.ellipse((-260 + i * 14, -300 + i * 9, 2180 - i * 14, 1380 - i * 9), fill=int(70 * (1 - k)))
    vig = vig.filter(ImageFilter.GaussianBlur(60))
    scrim = Image.linear_gradient('L').rotate(90, expand=True).resize((1920, 1080))  # 左白右黑
    scrim = scrim.point(lambda v: int(max(0, (v - 120)) * (150 / 135)))
    dark = ImageChops.lighter(vig, scrim)
    base = Image.new('RGB', bg.size, (6, 14, 21))
    out = Image.composite(base, out, dark)
    return out.convert('RGBA')


# ---------- Logo ----------
def logo(im, kind, x=68, y=46, width=262):
    src = Image.open(SRC / 'logo.png').convert('RGBA')
    sc = width / src.width
    def paste(box, dx, dy):
        part = src.crop(box)
        size = (round(part.width * sc * u.S), round(part.height * sc * u.S))
        im.alpha_composite(part.resize(size, Image.Resampling.NEAREST), (round((x + dx * sc) * u.S), round((y + dy * sc) * u.S)))
    if kind == 'orig':
        paste((0, 0, src.width, src.height), 0, 0); return
    # 像素徽记（塔 + 三角，去掉底下的 RHODES ISLAND 小字）与像素中文保留，拉丁字改矢量
    paste((0, 0, 124, 86), 0, 0)
    paste((124, 18, src.width, 86), 124, 18)
    cx = x + 132 * sc
    txt(im, cx + 1, y + 3, 'ARKNIGHTS', 8.5, '#c3d3dc', 'latin', 3.2)
    rule_y = y + 92 * sc
    line(im, [(x, rule_y), (x + width, rule_y)], '#3b5566', 0.8)
    line(im, [(x, rule_y), (x + 22, rule_y)], C, 1.4)
    txt(im, x + 30, rule_y + 6, 'RHODES ISLAND', 8, M, 'latin', 2.6)
    txt(im, x + 30 + text_w('RHODES ISLAND', 8, 'latin', 2.6) + 10, rule_y + 6, '·', 8, L, 'latin')
    txt(im, x + 30 + text_w('RHODES ISLAND', 8, 'latin', 2.6) + 22, rule_y + 6, 'SURVIVORS', 8, '#d5e2e8', 'latin', 2.6)


# ---------- 菜单 ----------
RING_R = 19


def ring_icon(im, cx, cy, k, ring, glyph, fill=None):
    u.circle(im, cx, cy, RING_R, fill, ring, 1.2)
    # 统一视觉尺寸：四个图标按各自轮廓的实测宽度缩放到同一光学大小
    scale = {'headhunt': .82, 'gallery': .74, 'cognition': .78, 'trial': .78}[k]
    u.icon(im, cx, cy + (1 if k == 'gallery' else 0), k, glyph, scale)


def menu_orig(im, s):
    for k, y in zip(ITEMS, ROW_Y):
        a = s == k; r, bot = 352, y + 55
        if a: u.poly(im, [(68, y + 3), (r - 1, y + 3), (r - 17, bot - 3), (68, bot - 3)], (32, 60, 77, 178))
        u.circle(im, 88, y + 26, 20, None, C if a else '#5c7e8f', 1)
        u.icon(im, 88, y + 26, k, C if a else '#cad9e1', .85)
        txt(im, 124, y + 7, LABELS[k], 26, T, 'serif'); txt(im, 125, y + 42, EN[k], 8, M, 'latin', 2)
        if k == 'trial': txt(im, 191, y + 20, '测试版', 10, M)
        if a: chevron(im, 325, y + 25, C, 1.5)


def menu_white(im, s):
    """方向一：S4 近白选中。选中 = 近白斜切底条 + 深墨字 + 右箭头。"""
    for k, y in zip(ITEMS, ROW_Y):
        a = s == k; r, bot = 356, y + 54
        if a:
            u.poly(im, [(64, y + 2), (r, y + 2), (r - 16, bot - 2), (64, bot - 2)], NEAR_WHITE)
            u.poly(im, [(64, y + 2), (68, y + 2), (68, bot - 2), (64, bot - 2)], C)
        ring_icon(im, 90, y + 27, k, INK if a else '#6f8f9f', INK if a else '#d3e0e7', None)
        col = INK if a else T
        txt(im, 124, y + 8, LABELS[k], 25, col, 'bold')
        txt(im, 125, y + 41, EN[k], 8, '#3e5a6a' if a else M, 'latin', 2.4)
        if k == 'trial': txt(im, 124 + text_w('试炼', 25, 'bold') + 10, y + 19, '测试版', 10, '#3e5a6a' if a else M)
        if a: chevron(im, 330, y + 27, INK, 1.8)


def menu_cyan(im, s):
    """方向二：青光航标。选中 = 半透明深底 + 左青边 + 青下划线扫过 + 青图标。"""
    for k, y in zip(ITEMS, ROW_Y):
        a = s == k; r, bot = 356, y + 54
        if a:
            u.poly(im, [(64, y + 2), (r, y + 2), (r - 16, bot - 2), (64, bot - 2)], (24, 52, 68, 215))
            u.rect(im, (64, y + 2, 67, bot - 2), C)
            line(im, [(124, bot - 6), (300, bot - 6)], C, 1.4)
        ring_icon(im, 90, y + 27, k, C if a else '#5c7e8f', C if a else '#cad9e1', (14, 40, 52, 255) if a else None)
        txt(im, 124, y + 8, LABELS[k], 25, '#ffffff' if a else '#dbe5ea', 'bold')
        txt(im, 125, y + 41, EN[k], 8, C if a else M, 'latin', 2.4)
        if k == 'trial': txt(im, 124 + text_w('试炼', 25, 'bold') + 10, y + 19, '测试版', 10, M)
        if a: chevron(im, 330, y + 27, C, 1.8)


def menu_index(im, s):
    """方向三：深潮档案。序号 + 圆环；选中 = 近白细框斜切 + 近白实心圆环 + 箭头，字保持宋体。"""
    for i, (k, y) in enumerate(zip(ITEMS, ROW_Y)):
        a = s == k; r, bot = 356, y + 54
        txt(im, 46, y + 21, f'{i + 1:02}', 8, C if a else '#56707f', 'latin', 1)
        if a:
            u.poly(im, [(64, y + 2), (r, y + 2), (r - 16, bot - 2), (64, bot - 2)], (230, 237, 240, 34))
            line(im, [(64, y + 2), (r, y + 2), (r - 16, bot - 2), (64, bot - 2), (64, y + 2)], NEAR_WHITE, 1)
        ring_icon(im, 90, y + 27, k, NEAR_WHITE if a else '#5c7e8f', INK if a else '#cad9e1', NEAR_WHITE if a else None)
        txt(im, 124, y + 6, LABELS[k], 26, T, 'serif')
        txt(im, 125, y + 41, EN[k], 8, NEAR_WHITE if a else M, 'latin', 2.4)
        if k == 'trial': txt(im, 124 + text_w('试炼', 26, 'serif') + 10, y + 19, '测试版', 10, M)
        if a: chevron(im, 330, y + 27, NEAR_WHITE, 1.6)


# ---------- 集结出发 ----------
def deploy_orig(im, s):
    a = s == 'deploy'; cx, cy = 284, 556
    for rad, s0, e0 in [(76, 197, 342), (86, 12, 123), (67, 16, 126), (82, 133, 174)]: arc(im, cx, cy, rad, s0, e0, '#598c9e', .8)
    for i in range(22):
        g = math.radians(-70 + i * 6.3)
        line(im, [(cx + math.cos(g) * 73, cy + math.sin(g) * 73), (cx + math.cos(g) * 82, cy + math.sin(g) * 82)], '#81becb' if a else L, 1)
    line(im, [(259, 604), (310, 553), (310, 526), (276, 526)], C if a else M, 2)
    line(im, [(280, 577), (328, 529), (328, 560)], C if a else M, 2)
    u.circle(im, 255, 608, 3, C if a else M, None)
    txt(im, 74, 492, '集结', 48, T, 'serif', 3); txt(im, 99, 548, '出发', 48, T, 'serif', 3)
    txt(im, 78, 617, 'DEPLOY', 10, C if a else M, 'latin', 4)
    line(im, [(75, 643), (236, 643)], C if a else L, 1.3)


def dial(im, cx, cy, a, tick_col, arc_col, hot=None, phase=0):
    for rad, s0, e0 in [(76, 197, 342), (86, 12, 123), (67, 16, 126), (82, 133, 174)]:
        arc(im, cx, cy, rad, s0 + phase, e0 + phase, arc_col, .8)
    for i in range(28):
        g = math.radians(-78 + i * 5.4)
        long = i % 7 == 0
        line(im, [(cx + math.cos(g) * (70 if long else 73), cy + math.sin(g) * (70 if long else 73)),
                  (cx + math.cos(g) * 82, cy + math.sin(g) * 82)], tick_col, 1.2 if long else .9)
    if hot: arc(im, cx, cy, 76, -78, -20, hot, 2.4)


def deploy_white(im, s):
    a = s == 'deploy'; cx, cy = 288, 560
    dial(im, cx, cy, a, '#7fb1c0' if a else '#4f6e7e', '#5d8ea0')
    # 方向标：单一实心箭头（去掉双折线，识别度更高）
    line(im, [(258, 606), (322, 542)], NEAR_WHITE if a else '#c9d8df', 2.4)
    u.poly(im, [(330, 534), (304, 540), (324, 560)], NEAR_WHITE if a else '#c9d8df')
    u.circle(im, 254, 610, 3.2, C, None)
    txt(im, 72, 496, '集结', 50, T, 'bold', 4); txt(im, 98, 556, '出发', 50, T, 'bold', 4)
    txt(im, 76, 624, 'DEPLOY', 10, C, 'latin', 5)
    line(im, [(75, 646), (210, 646)], C if a else L, 1.4)
    if a:
        u.poly(im, [(214, 638), (262, 638), (256, 654), (214, 654)], NEAR_WHITE)
        txt(im, 220, 640, 'ENTER', 8, INK, 'latin', 1.4)


def deploy_cyan(im, s):
    a = s == 'deploy'; cx, cy = 288, 560
    # 光晕底：圆盘中心一团极淡的青光，作为主按钮的落点
    glow = Image.new('RGBA', im.size, (0, 0, 0, 0)); dg = ImageDraw.Draw(glow)
    rr = 64 * u.S; dg.ellipse((cx * u.S - rr, cy * u.S - rr, cx * u.S + rr, cy * u.S + rr), fill=(110, 210, 230, 60 if a else 36))
    im.alpha_composite(glow.filter(ImageFilter.GaussianBlur(26 * u.S)))
    dial(im, cx, cy, a, '#8fd3df' if a else '#55788a', '#5d97aa', hot=C)
    line(im, [(258, 606), (322, 542)], C, 2.4)
    u.poly(im, [(330, 534), (304, 540), (324, 560)], C)
    u.circle(im, 254, 610, 4, C, None)
    txt(im, 72, 496, '集结', 50, '#ffffff', 'bold', 4); txt(im, 98, 556, '出发', 50, '#ffffff', 'bold', 4)
    u.poly(im, [(76, 622), (148, 622), (142, 638), (76, 638)], C)
    txt(im, 82, 625, 'DEPLOY', 9, INK, 'latin', 3)
    line(im, [(75, 648), (236, 648)], C if a else L, 1.3)


def deploy_index(im, s):
    a = s == 'deploy'; cx, cy = 288, 560
    dial(im, cx, cy, a, '#89b8c6' if a else '#4f6e7e', '#6d9aab')
    arc(im, cx, cy, 92, 200, 330, '#30495a', .7)
    line(im, [(258, 606), (322, 542)], NEAR_WHITE, 2.2)
    u.poly(im, [(330, 534), (304, 540), (324, 560)], NEAR_WHITE)
    u.circle(im, 254, 610, 3, NEAR_WHITE, None)
    txt(im, 70, 490, '集结', 52, T, 'serif', 4); txt(im, 98, 552, '出发', 52, T, 'serif', 4)
    txt(im, 76, 624, 'DEPLOY', 10, NEAR_WHITE, 'latin', 5)
    txt(im, 152, 624, '/ 00', 10, '#56707f', 'latin', 2)
    line(im, [(75, 646), (236, 646)], NEAR_WHITE if a else L, 1.2)


# ---------- 页脚 ----------
FOOT = [('设置', 68), ('操作说明', 143), ('退出', 258)]


def footer(im, s, accent):
    line(im, [(68, 662), (318, 662)], '#26394a', .8)
    x = 75
    for i, (name, _) in enumerate(FOOT):
        if i: txt(im, x + 12, 676, '/', 12, '#3b5566', 'latin'); x += 30
        txt(im, x, 674, name, 15, '#c6d4dc'); x += text_w(name, 15, 'regular')


DIRS = {
    'orig': dict(name='原版 · Codex 47-C', scene='orig', logo='orig', menu=menu_orig, deploy=deploy_orig, accent=C,
                 notes=['Codex 原稿，作对照']),
    'A': dict(name='方向一 · 近白选中', scene='glow', logo='fixed', menu=menu_white, deploy=deploy_white, accent=NEAR_WHITE,
              notes=['选中态：近白斜切底条 + 深墨字 + 青色左边标（同 S4 近白选中）',
                     '菜单与主按钮改黑体粗字，图标统一光学大小、同一线宽',
                     '集结出发：双折线改单一实心箭头 + 选中时 ENTER 键帽',
                     'Logo：SURVIVORS 错字修正，拉丁字矢量化、加 RHODES ISLAND 横线层级',
                     '场景：水母柔光 + 左侧阅读衬底 + 四周压暗']),
    'B': dict(name='方向二 · 青光航标', scene='glow', logo='fixed', menu=menu_cyan, deploy=deploy_cyan, accent=C,
              notes=['选中态：深色半透明条 + 青边标 + 青下划线 + 实心圆环图标',
                     '集结出发：圆盘中心淡青光晕 + 青色进度弧 + DEPLOY 青色标签',
                     '主按钮在画面里最亮，菜单其次（青色只给“可操作”）',
                     'Logo、字体、衬底同方向一']),
    'C': dict(name='方向三 · 深潮档案', scene='deep', logo='fixed', menu=menu_index, deploy=deploy_index, accent=NEAR_WHITE,
              notes=['保留宋体标题气质（最接近 Codex 原稿）',
                     '选中态：近白细框斜切 + 近白实心圆环 + 序号点亮',
                     '集结出发：外加一圈细轨道，DEPLOY / 00 档案编号',
                     '场景：暗部再压一档、水母柔光收敛，明暗层次最大']),
}


def render(key, selected):
    d = DIRS[key]
    u.CURRENT = f'{key}_{selected}'
    ui = u.layer()
    logo(ui, d['logo'])
    d['menu'](ui, selected)
    d['deploy'](ui, selected)
    if key == 'orig':
        for name, x in FOOT: txt(ui, x + 7, 668, name, 15, M)
    else:
        footer(ui, selected, d['accent'])
    ui = ui.resize((1920, 1080), Image.Resampling.LANCZOS)
    return Image.alpha_composite(scene(d['scene']), ui).convert('RGB')


def main():
    OUT.mkdir(exist_ok=True)
    full = {}
    for key in DIRS:
        for sel in ('headhunt', 'deploy'):
            im = render(key, sel); im.save(OUT / f'{key}_{sel}.png')
            full[(key, sel)] = im
    # 对照板：每行一个方向：整屏（寻访选中）| 左栏放大（寻访选中）| 左栏放大（集结出发选中）+ 说明
    rows = list(DIRS)
    RW, RH = 1920, 560
    board = Image.new('RGB', (RW, 60 + RH * len(rows)), '#0b151d'); db = ImageDraw.Draw(board)
    db.text((24, 14), '标题页 · 深海水母精修  同一构图三个方向（左：整屏 寻访选中；中：左栏放大 寻访选中；右：左栏放大 集结出发选中）',
            font=u.font(7, 'bold'), fill='#d4e4ec')
    for i, key in enumerate(rows):
        y0 = 60 + i * RH
        db.text((24, y0 + 8), DIRS[key]['name'], font=u.font(8.5, 'bold'), fill='#e9f0f3')
        board.paste(full[(key, 'headhunt')].resize((768, 432), Image.Resampling.LANCZOS), (24, y0 + 52))
        crop = (40, 40, 740, 1080)
        for j, sel in enumerate(('headhunt', 'deploy')):
            c = full[(key, sel)].crop(crop).resize((330, 490), Image.Resampling.LANCZOS)
            board.paste(c, (812 + j * 344, y0 + 52))
        ny = y0 + 56
        for n in DIRS[key]['notes']:
            for chunk in [n[k:k + 17] for k in range(0, len(n), 17)]:
                db.text((1524, ny), chunk, font=u.font(5.6, 'regular'), fill='#b9ccd6'); ny += 25
            ny += 8
    board.save(OUT / 'comparison.png')
    print('ok', OUT)


if __name__ == '__main__':
    main()
