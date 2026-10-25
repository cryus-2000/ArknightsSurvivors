"""标题页左侧入口分主次（10-25 用户：「几个都凑在一起，分一下主次，再出几个设计稿，出发不用动」）。
以游戏实机截图为底（build/title_jelly/desk/shot_title.png），左侧入口区换成干净场景（同 title_deep_view 的压暗），再按三种方案重画入口。
主次口径：寻访 / 认知塑造 = 局外成长主线（主）；图鉴 / 蚀刻章 = 记录（次）；试炼（测试版）= 最轻。
运行：D:/Anaconda/python.exe -B art/incoming/title_jelly_1024/render_hierarchy.py → art/incoming/title_jelly_1024/hierarchy/
"""
from pathlib import Path
import importlib.util
import math
import sys
import numpy as np
from PIL import Image, ImageDraw

P = Path(__file__).resolve().parent
ROOT = P.parents[2]
OUT = P / 'hierarchy'
sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location('prim', P / 'src/primitives_41.py')
u = importlib.util.module_from_spec(spec); spec.loader.exec_module(u)

T = '#e9f0f3'; M = '#a2b9c8'; L = '#466171'; C = '#9de5ef'; INK = '#132734'
RING = '#5c7e8f'; GLYPH = '#cad9e1'; DIM = '#6d8391'
STRIP = (24, 52, 68, 214)
REGION = (96, 168, 470, 462)   # 换底的入口区（集结出发从 466 起，不动）


def txt(im, x, y, s, size, col=T, face='bold', sp=0): u.text(im, x, y, s, size, col, face, sp)
def line(im, pts, col=L, w=1.0): u.line(im, pts, col, w)
def chevron(im, x, y, col=C, w=1.8, k=1.0): line(im, [(x - 5 * k, y - 9 * k), (x + 4 * k, y), (x - 5 * k, y + 9 * k)], col, w)


def tw(s, size, face='bold', sp=0):
    f = u.font(size, face); d = ImageDraw.Draw(Image.new('L', (1, 1)))
    return sum(d.textlength(ch, font=f) for ch in s) / u.S + sp * max(0, len(s) - 1)


def icon(im, x, y, kind, col, k=1.0):
    if kind == 'medals':
        s = 0.8 * k
        line(im, [(x - 7 * s, y - 13 * s), (x - 3 * s, y - 4 * s)], col, 1.25 * s)
        line(im, [(x + 7 * s, y - 13 * s), (x + 3 * s, y - 4 * s)], col, 1.25 * s)
        u.circle(im, x, y + 4 * s, 8 * s, None, col, 1.25 * s)
        u.circle(im, x, y + 4 * s, 3.5 * s, None, col, 1.25 * s)
        return
    s = {'headhunt': .82, 'gallery': .74, 'cognition': .78, 'trial': .78}[kind] * k
    u.icon(im, x, y + (1 if kind == 'gallery' else 0), kind, col, s)


def ring(im, x, y, r, kind, active, dim=False, k=1.0):
    if active:
        u.circle(im, x, y, r, (14, 40, 52, 255), C, 1.2)
    else:
        u.circle(im, x, y, r, None, DIM if dim else RING, 1.2)
    icon(im, x, y, kind, C if active else (DIM if dim else GLYPH), k)


def strip(im, x, y, w, h):
    u.poly(im, [(x, y), (x + w, y), (x + w - 16, y + h), (x, y + h)], STRIP)
    u.rect(im, (x, y, x + 3, y + h), C)


def clean_base():
    shot = Image.open(ROOT / 'build/title_jelly/desk/shot_title.png').convert('RGB')
    scene = Image.open(ROOT / 'build/title_jelly/frames2/g_000.png').convert('RGB').resize((1284, 720), Image.Resampling.NEAREST).crop((2, 0, 1282, 720))
    a = np.asarray(scene).astype(np.float32) / 255.0
    ys, xs = np.mgrid[0:720, 0:1280]
    sx, sy = (xs + 0.5) / 1280.0, (ys + 0.5) / 720.0
    d = np.hypot((sx - 0.5) * 1.0, (sy - 0.5) * 1.15)
    vig = 0.27 * np.clip((d - 0.32) / 0.46, 0, 1) ** 2 * (3 - 2 * np.clip((d - 0.32) / 0.46, 0, 1))
    scrim = 0.59 * np.clip((0.53 - sx) / 0.53, 0, 1)
    dark = np.maximum(vig, scrim)[..., None]
    a = a * (1 - dark) + np.array([0.024, 0.055, 0.082]) * dark
    clean = Image.fromarray((a * 255).astype(np.uint8))
    shot.paste(clean.crop(REGION), REGION[:2])
    return shot.convert('RGBA')


# ---------------- 方案 A：主次两档 ----------------
def plan_a(im):
    # 主：寻访 / 认知塑造（大一号、带圆环、有选中底条）
    for i, (cn, en, kind) in enumerate([('寻访', 'HEADHUNT', 'headhunt'), ('认知塑造', 'COGNITION', 'cognition')]):
        y = 182 + i * 66
        act = i == 0
        if act:
            strip(im, 104, y, 316, 58)
        ring(im, 132, y + 29, 22, kind, act, k=1.08)
        txt(im, 168, y + 8, cn, 28, '#ffffff' if act else '#dbe5ea')
        txt(im, 169, y + 43, en, 8, C if act else M, 'latin', 2.4)
        if act:
            line(im, [(168, y + 55), (360, y + 55)], C, 1.4)
            chevron(im, 398, y + 29)
    # 次：图鉴 / 蚀刻章 / 试炼（无圆环小图标 + 小字，一行一个）
    line(im, [(108, 324), (140, 324)], C, 1.2)
    line(im, [(146, 324), (330, 324)], '#26394a', 0.8)
    for i, (cn, kind, tag, dim) in enumerate([('图鉴', 'gallery', '', False), ('蚀刻章', 'medals', '未开放', True), ('试炼', 'trial', '测试版', False)]):
        y = 338 + i * 38
        icon(im, 122, y + 12, kind, DIM if dim else '#9fb4c1', 0.72)
        col = '#77909e' if dim else ('#c6d4dc' if kind != 'trial' else '#9fb1bc')
        txt(im, 144, y + 1, cn, 18, col, 'regular')
        if tag:
            txt(im, 144 + tw(cn, 18, 'regular') + 8, y + 6, tag, 10, M, 'regular')


# ---------------- 方案 B：分组小标题 ----------------
def group_label(im, y, cn, en):
    u.rect(im, (106, y + 2, 109, y + 13), C)
    txt(im, 116, y, cn, 12, C, 'bold')
    txt(im, 116 + tw(cn, 12) + 8, y + 3, en, 8, M, 'latin', 2.2)


def plan_b(im):
    group_label(im, 176, '成长', 'GROWTH')
    for i, (cn, en, kind) in enumerate([('寻访', 'HEADHUNT', 'headhunt'), ('认知塑造', 'COGNITION', 'cognition')]):
        y = 198 + i * 58
        act = i == 0
        if act:
            strip(im, 104, y, 300, 52)
        ring(im, 130, y + 26, 19, kind, act)
        txt(im, 164, y + 7, cn, 25, '#ffffff' if act else '#dbe5ea')
        txt(im, 165, y + 38, en, 8, C if act else M, 'latin', 2.4)
        if act:
            line(im, [(164, y + 50), (340, y + 50)], C, 1.4)
            chevron(im, 384, y + 26)
    group_label(im, 326, '档案', 'RECORDS')
    for i, (cn, en, kind, tag, dim) in enumerate([('图鉴', 'ARCHIVE', 'gallery', '', False), ('蚀刻章', 'MEDALS', 'medals', '未开放', True)]):
        y = 348 + i * 44
        ring(im, 128, y + 20, 15, kind, False, dim, 0.8)
        col = '#77909e' if dim else '#c9d6dd'
        txt(im, 154, y + 6, cn, 20, col)
        txt(im, 154 + tw(cn, 20) + 10, y + 12, en, 7, M, 'latin', 2.2)
        if tag:
            txt(im, 154 + tw(cn, 20) + 12 + tw(en, 7, 'latin', 2.2) + 8, y + 10, tag, 10, M, 'regular')
    # 试炼：最轻，一行小字靠在档案组下面
    icon(im, 128, 444, 'trial', '#7f95a2', 0.55)
    txt(im, 142, 436, '试炼', 13, '#93a6b2', 'regular')
    txt(im, 142 + tw('试炼', 13, 'regular') + 6, 439, '测试版', 9, '#6d8391', 'regular')


# ---------------- 方案 C：双卡 + 图标排 ----------------
def plan_c(im):
    for i, (cn, en, kind) in enumerate([('寻访', 'HEADHUNT', 'headhunt'), ('认知塑造', 'COGNITION', 'cognition')]):
        x = 104 + i * 168
        y = 182
        act = i == 0
        u.poly(im, [(x, y), (x + 158, y), (x + 158, y + 98), (x + 12, y + 110), (x, y + 110)], (36, 66, 84, 225) if act else (12, 27, 38, 205))
        line(im, [(x, y), (x + 158, y)], C if act else L, 2 if act else 1)
        ring(im, x + 30, y + 32, 20, kind, act)
        txt(im, x + 16, y + 62, cn, 23, '#ffffff' if act else '#dbe5ea')
        txt(im, x + 17, y + 92, en, 7, C if act else M, 'latin', 2.2)
        if act:
            chevron(im, x + 140, y + 32, C, 1.6, 0.9)
    # 次级：三个圆环小图标排成一排，字在下面
    for i, (cn, kind, tag, dim) in enumerate([('图鉴', 'gallery', '', False), ('蚀刻章', 'medals', '未开放', True), ('试炼', 'trial', '测试版', False)]):
        cx = 132 + i * 92
        y = 330
        ring(im, cx, y, 18, kind, False, dim, 0.85)
        col = '#77909e' if dim else '#c6d4dc'
        txt(im, cx - tw(cn, 15, 'regular') / 2, y + 26, cn, 15, col, 'regular')
        if tag:
            txt(im, cx - tw(tag, 9, 'regular') / 2, y + 47, tag, 9, M, 'regular')
    line(im, [(104, 404), (430, 404)], '#26394a', 0.8)


PLANS = [
    ('A', '主次两档', plan_a, ['寻访、认知塑造放大一号，带圆环与选中底条', '图鉴、蚀刻章、试炼降为无圈小图标 + 小字', '两档之间一条短青线分隔']),
    ('B', '分组小标题', plan_b, ['「成长 GROWTH」：寻访、认知塑造（现有大小）', '「档案 RECORDS」：图鉴、蚀刻章（小一号圆环）', '试炼降成档案组下的一行小字']),
    ('C', '双卡 + 图标排', plan_c, ['寻访、认知塑造做成并排两张卡（主操作）', '图鉴、蚀刻章、试炼排成一行圆环图标，字在下', '方向键：卡片左右走、图标排左右走、上下换排']),
]


def main():
    OUT.mkdir(exist_ok=True)
    base = clean_base()
    shot = Image.open(ROOT / 'build/title_jelly/desk/shot_title.png').convert('RGB')
    full = {'now': shot}
    for key, name, fn, _ in PLANS:
        u.CURRENT = key
        lay = u.layer()
        fn(lay)
        im = Image.alpha_composite(base, lay.resize((1280, 720), Image.Resampling.LANCZOS)).convert('RGB')
        im.save(OUT / f'{key}.png')
        full[key] = im
    # 对照板：现版 + 三案；上排整屏缩略，下排左侧放大
    names = [('now', '现版（5 个入口同级）', [])] + [(k, f'方案 {k} · {n}', notes) for k, n, _, notes in PLANS]
    cw, ch = 640, 360
    zw, zh = 640, 560
    b = Image.new('RGB', (cw * 4 + 30, 50 + ch + 10 + zh + 150), '#0b151d'); d = ImageDraw.Draw(b)
    f = u.font(7.5, 'bold'); fn_ = u.font(5.3, 'regular')
    for i, (k, title, notes) in enumerate(names):
        x = i * (cw + 10)
        d.text((x + 8, 12), title, font=f, fill='#e9f0f3')
        b.paste(full[k].resize((cw, ch), Image.Resampling.LANCZOS), (x, 50))
        b.paste(full[k].crop((80, 150, 480, 500)).resize((zw, zh), Image.Resampling.LANCZOS), (x, 50 + ch + 10))
        ny = 50 + ch + 10 + zh + 12
        for n in notes:
            d.text((x + 8, ny), '· ' + n, font=fn_, fill='#b9ccd6'); ny += 26
    b.save(OUT / 'comparison.png')
    print(b.size)


if __name__ == '__main__':
    main()
