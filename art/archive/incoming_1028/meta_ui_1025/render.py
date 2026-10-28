"""认知塑造界面重设计（10-25 用户：「认知那个界面现在有点杂乱，重新设计一下」）——三个方案的样图与 10 秒演示视频。
同一份存档：累计生机细胞 600，按 meta_tree.json 的推荐顺序花到 ≤ 330（同游戏 --metacells=600 --metabuy=330）。节点名、消耗、效果都读真实数据。
  A 档案列表：照图鉴——顶部分类页签、左边 10 条链各一行（等级格 + 当前总加成 + 下一节消耗）、右边浅色详情面板逐节列出。
  B 整齐图谱：保留「树」——10 列按 战斗 / 成长 / 资源 分组等距排齐、不斜不扇、去掉背景碎片与每节名字，右边暗色详情面板。
  C 单链聚焦：照选人——底部一排链卡（像名册），中间放大当前链的 3–5 节横排卡片，右下大按钮塑造。
运行：D:/Anaconda/python.exe -B art/archive/incoming_1028/meta_ui_1025/render.py [--video]
产物：build/meta_ui/plans/<A|B|C>.png、build/meta_ui/plans/<A|B|C>.mp4（H.264 yuv420p，24 fps，10 秒）、build/meta_ui/plans/compare.png
"""
from pathlib import Path
import importlib.util
import json
import math
import re
import subprocess
import shutil
import sys
from PIL import Image, ImageDraw

P = Path(__file__).resolve().parent
ROOT = P.parents[3]
OUT = ROOT / 'build/meta_ui/plans'
FFMPEG = r'C:\Users\colafax\AppData\Local\Packages\PythonSoftwareFoundation.Python.3.13_qbz5n2kfra8p0\LocalCache\local-packages\Python313\site-packages\imageio_ffmpeg\binaries\ffmpeg-win-x86_64-v7.1.exe'
sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location('prim', ROOT / 'art/archive/incoming_1028/title_jelly_1024/src/primitives_41.py')
u = importlib.util.module_from_spec(spec); spec.loader.exec_module(u)
u.S = 2                                       # 1280×720 设计坐标 ×2 绘制，再缩到 1600×900
u.text.__globals__['TEXT_BOXES'] = []
# ui.ttf 缺的字（癖 等）：样图整段换字体
from fontTools.ttLib import TTFont
u.FONT_PATHS['fb'] = Path('C:/Windows/Fonts/msyhbd.ttc')   # 样图用：ui.ttf 缺字时整段换微软雅黑粗体（游戏内是逐字回退 ui_fallback.otf）
_CMAP = TTFont(str(u.FONT_PATHS['bold'])).getBestCmap()

# ---------------------------------------------------------------- 数据
D = json.loads((ROOT / 'game/data/meta_tree.json').read_text(encoding='utf-8'))
NODES = D['nodes']
GROUPS = [('战斗', 'COMBAT', ['atk', 'hp', 'def', 'reg', 'sh']), ('成长', 'GROWTH', ['xp', 'pick', 'disp']), ('资源', 'SUPPLY', ['gold', 'shop'])]
CHAIN_EN = {'atk': 'ATTACK', 'hp': 'VITALITY', 'def': 'GUARD', 'reg': 'RECOVERY', 'sh': 'SHIELD', 'xp': 'EXPERIENCE', 'pick': 'PICKUP',
            'disp': 'DISPATCH', 'gold': 'ORIGINIUM', 'shop': 'NEGOTIATION'}
RULE_TAG = {"atk5": "处决", "hp5": "濒死免死", "def4": "久守减伤", "reg3": "低血回复", "sh1": "碎盾反震", "xp4": "升级再升",
            "disp1": "四选一", "disp2": "免费刷新", "disp3": "开局藏品", "disp4": "绝处逢生"}


def chain_ids(p):
    out = [k for k in NODES if re.fullmatch(p + r'\d+', k)]
    return sorted(out, key=lambda k: int(k[len(p):]))


CHAINS = [c for _, _, cs in GROUPS for c in cs]
ROMAN = 'ⅠⅡⅢⅣⅤ'


def chain_title(p):
    n = NODES[chain_ids(p)[0]]['name']
    return '调度' if p == 'disp' else n.rstrip(ROMAN)


def spent(shape):
    return sum(NODES[k]['cost'] for k in shape)


def can_buy(shape, k, budget):
    n = NODES[k]
    if k in shape or ('req' in n and n['req'] not in shape):
        return False
    return spent(shape) + n['cost'] <= budget


def shape_for(budget):
    shape, changed = set(), True
    while changed:
        changed = False
        for k in D['order']:
            if can_buy(shape, k, budget):
                shape.add(k); changed = True
    return shape


SHAPE0 = shape_for(330)
EARNED = 600


def level(p, shape):
    return sum(1 for k in chain_ids(p) if k in shape)


def next_id(p, shape):
    for k in chain_ids(p):
        if k not in shape:
            return k
    return None


def summary(p, shape):
    """当前链已塑造部分的总加成：同前缀数值相加（「全体伤害 +4%」×3 → 「全体伤害 +12%」）；调度链列规则名"""
    if p == 'disp':
        got = [RULE_TAG[k] for k in chain_ids(p) if k in shape]
        return '、'.join(got) if got else '—'
    acc = {}
    order = []
    for k in chain_ids(p):
        if k not in shape:
            continue
        head = NODES[k]['desc'].split('。')[0].split('（')[0]
        m = re.match(r'(.*?)([+-])([\d.]+)(%?)(.*)$', head)
        if not m:
            continue
        key = (m.group(1), m.group(2), m.group(4), m.group(5))
        if key not in acc:
            acc[key] = 0.0; order.append(key)
        acc[key] += float(m.group(3))
    if not order:
        return '—'
    parts = []
    for key in order:
        v = acc[key]
        vs = ('%.2f' % v).rstrip('0').rstrip('.')
        parts.append('%s%s%s%s%s' % (key[0], key[1], vs, key[2], key[3]))
    return '，'.join(parts)


# ---------------------------------------------------------------- 画法工具
BG0 = (14, 20, 36); BG1 = (8, 11, 22)
CY = (60, 200, 228); CY_HI = (140, 236, 248)
TXT = (232, 238, 244); SUB = (150, 166, 186); DIM = (88, 100, 118)
WARM = (255, 240, 214)
LINE = (52, 70, 98)
PANEL = (14, 22, 40, 236); PANEL_SEL = (30, 58, 90, 245)
GLASS = (226, 228, 231, 232); INK = (22, 24, 28); INK2 = (92, 96, 104)
YEL = (255, 206, 0)


def hexc(c):
    return '#%02x%02x%02x' % c[:3]


def T(im, x, y, s, size, col=TXT, face='bold', sp=0):
    if face == 'bold' and any(ord(ch) not in _CMAP for ch in s if not ch.isspace()):
        face = 'fb'
    u.text(im, x, y, s, size, hexc(col), face, sp)


def tw(s, size, face='bold', sp=0):
    if face == 'bold' and any(ord(ch) not in _CMAP for ch in s if not ch.isspace()):
        face = 'fb'
    f = u.font(size, face); d = ImageDraw.Draw(Image.new('L', (1, 1)))
    return sum(d.textlength(ch, font=f) for ch in s) / u.S + sp * max(0, len(s) - 1)


def wrap(s, size, width, face='regular'):
    lines, cur = [], ''
    for ch in s:
        if tw(cur + ch, size, face) > width and cur:
            lines.append(cur); cur = '' if ch in '，。' else ''
            if ch in '，。':
                lines[-1] += ch; continue
        cur += ch
    if cur:
        lines.append(cur)
    return lines


def rect(im, box, fill=None, outline=None, w=1):
    d = ImageDraw.Draw(im, 'RGBA')
    d.rectangle(tuple(round(v * u.S) for v in box), fill=fill, outline=outline, width=round(w * u.S) if outline else 0)


def poly(im, pts, fill):
    ImageDraw.Draw(im, 'RGBA').polygon([(round(x * u.S), round(y * u.S)) for x, y in pts], fill=fill)


def line(im, pts, col, w=1):
    ImageDraw.Draw(im, 'RGBA').line([(round(x * u.S), round(y * u.S)) for x, y in pts], fill=col, width=max(1, round(w * u.S)))


def circle(im, x, y, r, fill=None, outline=None, w=1):
    ImageDraw.Draw(im, 'RGBA').ellipse(((x - r) * u.S, (y - r) * u.S, (x + r) * u.S, (y + r) * u.S), fill=fill, outline=outline, width=round(w * u.S) if outline else 0)


def fa(c, a):
    return (c[0], c[1], c[2], int((c[3] if len(c) > 3 else 255) * max(0.0, min(1.0, a))))


def icon(im, x, y, p, col, s=1.0):
    """每条链一个线框小图标（设计坐标中心 x, y）"""
    L = lambda pts: line(im, [(x + a * s, y + b * s) for a, b in pts], col, 1.4)
    if p == 'atk':
        L([(-7, -7), (7, 7)]); L([(-7, 7), (7, -7)])
    elif p == 'hp':
        L([(-8, 0), (-3, 0), (-1, -6), (2, 6), (4, 0), (8, 0)])
    elif p == 'def':
        L([(-7, -7), (7, -7), (7, 1), (0, 8), (-7, 1), (-7, -7)])
    elif p == 'reg':
        L([(0, -7), (0, 7)]); L([(-7, 0), (7, 0)])
    elif p == 'sh':
        L([(-4, -8), (4, -8), (8, 0), (4, 8), (-4, 8), (-8, 0), (-4, -8)])
    elif p == 'xp':
        L([(-7, 1), (0, -6), (7, 1)]); L([(-7, 7), (0, 0), (7, 7)])
    elif p == 'pick':
        for a, b in [(-4, -4), (4, -4), (-4, 4), (4, 4)]:
            L([(a - 3, b - 3), (a + 3, b - 3), (a + 3, b + 3), (a - 3, b + 3), (a - 3, b - 3)])
    elif p == 'disp':
        L([(0, -8), (8, 0), (0, 8), (-8, 0), (0, -8)]); L([(0, -3), (3, 0), (0, 3), (-3, 0), (0, -3)])
    elif p == 'gold':
        circle(im, x, y, 7 * s, None, col, 1.4); circle(im, x, y, 2 * s, col)
    elif p == 'shop':
        L([(-8, -2), (-2, -8), (8, -8), (8, 2), (2, 8), (-8, -2)]); circle(im, x + 4 * s, y - 4 * s, 1.5 * s, col)


def background():
    im = Image.new('RGBA', (1280 * u.S, 720 * u.S), BG1 + (255,))
    d = ImageDraw.Draw(im)
    for yy in range(720 * u.S):
        t = yy / (720 * u.S)
        c = tuple(int(BG0[i] * (1 - t) + BG1[i] * t) for i in range(3))
        d.line([(0, yy), (1280 * u.S, yy)], fill=c)
    # 选人 / 图鉴同款：一道斜向浅光带
    poly(im, [(560, 0), (760, 0), (520, 720), (320, 720)], (40, 60, 110, 22))
    return im


def topbar(im, st, title_en='COGNITION', show_tabs=False, tab=0):
    a = st['appear']
    rect(im, (0, 0, 1280, 56), fa((6, 10, 20, 235), a))
    line(im, [(0, 56), (1280, 56)], fa(LINE, a), 1)
    rect(im, (0, 0, 150, 56), fa((226, 228, 231, 240), a))
    T(im, 18, 9, title_en, 8, fa(INK2, a), 'latin', 3)
    T(im, 18, 22, '认知塑造', 20, fa(INK, a))
    for i in range(6):
        poly(im, [(150 + i * 8, 0), (154 + i * 8, 0), (150 + i * 8 + 4 - 20, 56), (150 + i * 8 - 20, 56)], fa((40, 60, 90, 255), a))
    if show_tabs:
        for i, (cn, en) in enumerate([('全部', 'ALL')] + [(g[0], g[1]) for g in GROUPS]):
            x = 200 + i * 118
            on = i == tab
            poly(im, [(x + 12, 10), (x + 108, 10), (x + 96, 48), (x, 48)], fa(CY + (255,) if on else (18, 28, 48, 230), a))
            if not on:
                line(im, [(x + 12, 10), (x + 108, 10), (x + 96, 48), (x, 48), (x + 12, 10)], fa(LINE, a), 1)
            T(im, x + 22, 14, cn, 16, fa(INK if on else TXT, a))
            T(im, x + 22, 36, en, 6, fa(INK if on else SUB, a), 'latin', 2)
    # 生机细胞 + 进度 + 返回
    cells = st['cells']
    T(im, 870, 10, '生机细胞', 11, fa(SUB, a), 'regular')
    T(im, 870, 24, '%d' % cells, 24, fa(CY_HI, a))
    T(im, 870 + tw('%d' % cells, 24) + 10, 33, '累计 %d' % EARNED, 11, fa(SUB, a), 'regular')
    n = len(st['shape'])
    T(im, 1024, 10, '已塑造', 11, fa(SUB, a), 'regular')
    T(im, 1024, 26, '%d / %d' % (n, len(NODES)), 18, fa(TXT, a))
    poly(im, [(1140, 12), (1262, 12), (1256, 44), (1134, 44)], fa((8, 12, 22, 255), a))
    line(im, [(1140, 12), (1262, 12), (1256, 44), (1134, 44), (1140, 12)], fa(TXT, a), 1.2)
    T(im, 1162, 18, '返回 Esc', 14, fa(TXT, a))


def pips(im, x, y, p, shape, a, size=12, gap=4, lit=None, litp=0.0):
    for i, k in enumerate(chain_ids(p)):
        xx = x + i * (size + gap)
        if k in shape:
            rect(im, (xx, y, xx + size, y + size), fa(WARM + (255,), a))
        elif k == lit:
            rect(im, (xx, y, xx + size, y + size), fa(WARM + (255,), a * litp), fa(CY + (255,), a), 1.4)
        elif k == next_id(p, shape):
            rect(im, (xx, y, xx + size, y + size), None, fa(CY + (255,), a), 1.4)
        else:
            rect(im, (xx, y, xx + size, y + size), None, fa(DIM + (255,), a), 1)


def button(im, box, label, sub, a, enabled=True, press=0.0):
    x0, y0, x1, y1 = box
    dy = 2 * press
    fill = CY + (255,) if enabled else (40, 52, 70, 255)
    poly(im, [(x0 + 8, y0 + dy), (x1, y0 + dy), (x1 - 8, y1 + dy), (x0, y1 + dy)], fa(fill, a))
    if press > 0:
        poly(im, [(x0 + 8, y0 + dy), (x1, y0 + dy), (x1 - 8, y1 + dy), (x0, y1 + dy)], fa((255, 255, 255, 255), a * press * 0.5))
    T(im, x0 + 22, y0 + 10 + dy, label, 20, fa(INK if enabled else SUB, a))
    if sub:
        T(im, x0 + 22, y1 - 20 + dy, sub, 10, fa(INK if enabled else SUB, a), 'regular')


def hint(im, a, s):
    T(im, 28, 694, s, 11, fa(SUB, a), 'regular')


def small_btn(im, x, y, label, key, a, col=TXT, sub=SUB):
    w = tw(label, 13) + 46
    line(im, [(x + 6, y), (x + w, y), (x + w - 6, y + 26), (x, y + 26), (x + 6, y)], fa(col + (255,), a), 1)
    T(im, x + 14, y + 5, label, 13, fa(col, a))
    T(im, x + w - 20, y + 8, key, 9, fa(sub, a), 'latin')
    return w


# ---------------------------------------------------------------- 方案 A：档案列表
def plan_a(st):
    im = background()
    a = st['appear']
    sel = st['sel']
    shape = st['shape']
    topbar(im, st, show_tabs=True, tab=st.get('tab', 0))
    shown = CHAINS if st.get('tab', 0) == 0 else GROUPS[st['tab'] - 1][2]
    y = 72
    off = (1 - a) * 30
    for gname, gen, cs in GROUPS:
        cs = [c for c in cs if c in shown]
        if not cs:
            continue
        T(im, 30 - off, y + 2, gname, 12, fa(CY, a))
        T(im, 30 + tw(gname, 12) + 8 - off, y + 5, gen, 7, fa(SUB, a), 'latin', 2)
        line(im, [(110 - off, y + 10), (820 - off, y + 10)], fa(LINE, a * 0.8), 1)
        y += 22
        for p in cs:
            on = p == CHAINS[sel]
            hp = st['sel_ease'] if on else 0.0
            x0 = 28 - off
            rect(im, (x0, y, 820 - off, y + 46), fa(PANEL_SEL if on else PANEL, a))
            if on:
                rect(im, (x0, y, x0 + 3, y + 46), fa(CY + (255,), a))
                line(im, [(x0, y), (x0 + 792 * hp, y)], fa(CY + (255,), a), 1.2)
            rect(im, (x0 + 14, y + 7, x0 + 46, y + 39), None, fa((CY if on else LINE) + (255,), a), 1)
            icon(im, x0 + 30, y + 23, p, fa((CY_HI if on else SUB) + (255,), a))
            T(im, x0 + 60, y + 6, chain_title(p), 17, fa(TXT, a))
            T(im, x0 + 61, y + 29, CHAIN_EN[p], 6, fa(SUB, a), 'latin', 2)
            pips(im, x0 + 220, y + 17, p, shape, a, lit=st.get('lit_id'), litp=st.get('lit', 0))
            sm = summary(p, shape)
            T(im, x0 + 330, y + 14, sm if tw(sm, 14, 'regular') < 300 else wrap(sm, 14, 290)[0] + '…', 14, fa(TXT if sm != '—' else DIM, a), 'regular')
            nk = next_id(p, shape)
            if nk:
                T(im, x0 + 690, y + 8, '下一节', 10, fa(SUB, a), 'regular')
                T(im, x0 + 690, y + 22, '%d' % NODES[nk]['cost'], 16, fa(CY_HI if NODES[nk]['cost'] <= st['cells'] else SUB, a))
                T(im, x0 + 690 + tw('%d' % NODES[nk]['cost'], 16) + 4, y + 27, '生机细胞', 9, fa(SUB, a), 'regular')
            else:
                T(im, x0 + 690, y + 15, '已满', 15, fa(WARM, a))
            y += 50
        y += 4
    # 右：浅色详情面板（同图鉴右栏）
    p = CHAINS[sel]
    px0 = 844 + (1 - a) * 40
    rect(im, (px0, 72, 1256, 680), fa(GLASS, a))
    T(im, px0 + 20, 86, 'CHAIN  //  %s' % CHAIN_EN[p], 7, fa(INK2, a), 'latin', 2.5)
    T(im, px0 + 20, 102, chain_title(p), 28, fa(INK, a))
    lv = '%d / %d' % (level(p, shape), len(chain_ids(p)))
    T(im, 1236 - tw(lv, 18), 112, lv, 18, fa(INK, a))
    line(im, [(px0 + 20, 146), (1236, 146)], fa((180, 184, 190, 255), a), 1)
    yy = 158
    for i, k in enumerate(chain_ids(p)):
        n = NODES[k]
        done = k in shape
        nxt = k == next_id(p, shape)
        lit = k == st.get('lit_id') and st.get('lit', 0) > 0
        if nxt or lit:
            rect(im, (px0 + 12, yy - 6, 1248, yy + 64), fa((255, 255, 255, 255), a))
            rect(im, (px0 + 12, yy - 6, px0 + 15, yy + 64), fa(CY + (255,), a))
        T(im, px0 + 24, yy, ROMAN[i] if i < 5 else str(i + 1), 18, fa(INK if (done or nxt or lit) else (160, 164, 170), a))
        T(im, px0 + 56, yy, n['name'], 15, fa(INK if (done or nxt or lit) else (150, 154, 160), a))
        chip = '已塑造' if done or (lit and st['lit'] >= 1) else ('下一节 · %d' % n['cost'] if nxt or lit else '%d' % n['cost'])
        T(im, 1236 - tw(chip, 11, 'regular'), yy + 3, chip, 11, fa(INK2 if not (nxt or lit) else (24, 130, 160), a), 'regular')
        for j, ln in enumerate(wrap(n['desc'], 12, 340)[:2]):
            T(im, px0 + 56, yy + 22 + j * 17, ln, 12, fa(INK2 if (done or nxt or lit) else (160, 164, 170), a), 'regular')
        yy += 72 if len(wrap(n['desc'], 12, 340)) > 1 else 56
    nk = next_id(p, shape)
    small_btn(im, px0 + 20, 600, '推荐', 'R', a, INK, INK2)
    small_btn(im, px0 + 104, 600, '全部重置', 'X', a, INK, INK2)
    if nk:
        button(im, (px0 + 214, 590, 1248, 668), '塑造  %s' % NODES[nk]['name'], 'ENTER  ·  消耗 %d 生机细胞' % NODES[nk]['cost'], a, NODES[nk]['cost'] <= st['cells'], st.get('press', 0))
    else:
        button(im, (px0 + 214, 590, 1248, 668), '本链已满', '', a, False)
    hint(im, a, '↑↓ 选择链  ·  Q / E 分类  ·  Enter 塑造  ·  R 推荐  ·  X 两次全部重置  ·  Esc 返回')
    return im


# ---------------------------------------------------------------- 方案 B：整齐图谱
def colx(i):
    """第 i 列中心 x：组间多空 26"""
    gi = 0 if i < 5 else (1 if i < 8 else 2)
    return 80 + i * 72 + gi * 26


ROWY = [588, 504, 420, 336, 252]


def plan_b(st):
    im = background()
    a = st['appear']
    shape = st['shape']
    sel = st['sel']
    sn = st.get('node', None)
    topbar(im, st)
    rect(im, (28, 72, 820, 680), fa((10, 16, 30, 170), a))
    for gi, (gname, gen, cs) in enumerate(GROUPS):
        i0 = CHAINS.index(cs[0]); i1 = CHAINS.index(cs[-1])
        x0, x1 = colx(i0) - 30, colx(i1) + 30
        T(im, x0, 84, gname, 13, fa(CY, a))
        T(im, x0 + tw(gname, 13) + 8, 88, gen, 7, fa(SUB, a), 'latin', 2)
        line(im, [(x0, 104), (x1, 104)], fa(LINE, a), 1)
        line(im, [(x0, 630), (x1, 630)], fa(LINE, a), 1)
    for i, p in enumerate(CHAINS):
        x = colx(i)
        on = i == sel
        ids = chain_ids(p)
        if on:
            rect(im, (x - 32, 112, x + 32, 640), fa((40, 80, 120, 40), a * st['sel_ease']))
            line(im, [(x - 32, 112), (x + 32, 112)], fa(CY + (255,), a * st['sel_ease']), 1.4)
        icon(im, x, 128, p, fa((CY_HI if on else SUB) + (255,), a), 0.9)
        T(im, x - tw(chain_title(p), 12) / 2, 144, chain_title(p), 12, fa(TXT if on else SUB, a))
        top = ROWY[len(ids) - 1]
        last = ids[-1]
        if last in RULE_TAG:
            tg = RULE_TAG[last]
            w = tw(tg, 10) + 10
            rect(im, (x - w / 2, top - 44, x + w / 2, top - 28), fa((14, 40, 60, 255), a), fa(CY + (255,), a), 1)
            T(im, x - w / 2 + 5, top - 43, tg, 10, fa(CY_HI, a))
        line(im, [(x, 630), (x, ROWY[0] + 16)], fa(((210, 220, 230) if ids[0] in shape else LINE) + (255,), a), 2)
        for j, k in enumerate(ids):
            y = ROWY[j]
            if j > 0:
                lit_line = k in shape or (k == st.get('lit_id') and st.get('lit', 0) > 0)
                yy0 = ROWY[j - 1] - 16
                yy1 = y + 16
                if k == st.get('lit_id') and st.get('lit', 0) < 1:
                    line(im, [(x, yy0), (x, yy1)], fa(LINE + (255,), a), 2)
                    line(im, [(x, yy0), (x, yy0 + (yy1 - yy0) * min(1, st['lit'] / 0.55))], fa(WARM + (255,), a), 2.4)
                else:
                    line(im, [(x, yy0), (x, yy1)], fa(((210, 220, 230) if lit_line else LINE) + (255,), a), 2)
            done = k in shape
            lit = k == st.get('lit_id')
            lp = st.get('lit', 0) if lit else 0
            nxt = k == next_id(p, shape)
            if done or (lit and lp >= 0.55):
                rect(im, (x - 15, y - 15, x + 15, y + 15), fa(WARM + (255,), a))
                T(im, x - tw(ROMAN[j], 14) / 2, y - 9, ROMAN[j], 14, fa(INK, a))
                if lit and lp < 1:
                    r = 15 + 22 * (lp - 0.55) / 0.45
                    rect(im, (x - r, y - r, x + r, y + r), None, fa(WARM + (255,), a * (1 - (lp - 0.55) / 0.45)), 1.5)
            else:
                rect(im, (x - 15, y - 15, x + 15, y + 15), fa((10, 16, 30, 255), a), fa((CY if nxt else DIM) + (255,), a), 1.6 if nxt else 1)
                T(im, x - tw(ROMAN[j], 14) / 2, y - 9, ROMAN[j], 14, fa(CY_HI if nxt else DIM, a))
            if on and sn == j:
                for sx, sy in [(-1, -1), (1, -1), (-1, 1), (1, 1)]:
                    line(im, [(x + sx * 22, y + sy * 14), (x + sx * 22, y + sy * 22), (x + sx * 14, y + sy * 22)], fa(TXT + (255,), a), 1.6)
    # 右：暗色详情（同选人右栏）
    p = CHAINS[sel]
    ids = chain_ids(p)
    j = sn if sn is not None else min(level(p, shape), len(ids) - 1)
    k = ids[j]
    n = NODES[k]
    px0 = 844 + (1 - a) * 40
    rect(im, (px0, 72, 1256, 680), fa((12, 18, 34, 235), a))
    line(im, [(px0, 72), (1256, 72)], fa(CY + (255,), a), 1)
    T(im, px0 + 20, 86, 'NODE  //  %s %s' % (CHAIN_EN[p], j + 1), 7, fa(SUB, a), 'latin', 2.5)
    T(im, px0 + 20, 102, n['name'], 28, fa(TXT, a))
    pips(im, px0 + 22, 148, p, shape, a, 14, 5, st.get('lit_id'), st.get('lit', 0))
    state = '已塑造' if k in shape else ('可塑造' if k == next_id(p, shape) else '先塑造「%s」' % NODES[n['req']]['name'] if 'req' in n and n['req'] not in shape else '')
    T(im, px0 + 130, 147, state, 13, fa(CY_HI if state == '可塑造' else SUB, a), 'regular')
    line(im, [(px0 + 20, 178), (1236, 178)], fa(LINE, a), 1)
    T(im, px0 + 20, 192, '效果', 11, fa(SUB, a), 'regular')
    first = n['desc'].split('。')[0]
    rest = '。'.join(n['desc'].split('。')[1:]).strip('。')
    T(im, px0 + 20, 210, first, 20, fa(TXT, a))
    yy = 244
    if rest:
        rect(im, (px0 + 20, yy, 1236, yy + 22 + 18 * len(wrap(rest, 13, 360))), fa((20, 44, 64, 255), a))
        rect(im, (px0 + 20, yy, px0 + 23, yy + 22 + 18 * len(wrap(rest, 13, 360))), fa(CY + (255,), a))
        T(im, px0 + 32, yy + 6, RULE_TAG.get(k, '规则'), 11, fa(CY_HI, a))
        for i2, ln in enumerate(wrap(rest, 13, 360)):
            T(im, px0 + 32, yy + 24 + i2 * 18, ln, 13, fa(TXT, a), 'regular')
        yy += 40 + 18 * len(wrap(rest, 13, 360))
    T(im, px0 + 20, yy + 10, '本链合计', 11, fa(SUB, a), 'regular')
    for i2, ln in enumerate(wrap(summary(p, shape), 15, 380)):
        T(im, px0 + 20, yy + 28 + i2 * 20, ln, 15, fa(TXT, a), 'regular')
    if ids[-1] in RULE_TAG and k != ids[-1]:
        T(im, px0 + 20, 540, '末节  %s · %s' % (NODES[ids[-1]]['name'], RULE_TAG[ids[-1]]), 12, fa(SUB, a), 'regular')
    small_btn(im, px0 + 20, 600, '推荐', 'R', a)
    small_btn(im, px0 + 104, 600, '全部重置', 'X', a)
    nk = next_id(p, shape)
    can = k == nk and n['cost'] <= st['cells']
    button(im, (px0 + 214, 590, 1248, 668), '确认塑造' if k == nk else ('已塑造' if k in shape else '未解锁'), 'ENTER  ·  消耗 %d 生机细胞' % n['cost'] if k == nk else '', a, can, st.get('press', 0))
    hint(im, a, '←→ 换链  ·  ↑↓ 沿链  ·  Enter 塑造  ·  R 推荐  ·  X 两次全部重置  ·  Esc 返回')
    return im


# ---------------------------------------------------------------- 方案 C：单链聚焦
def plan_c(st):
    im = background()
    a = st['appear']
    shape = st['shape']
    sel = st['sel']
    p = CHAINS[sel]
    ids = chain_ids(p)
    topbar(im, st)
    # 左：分组筛选竖栏（同选人职业栏）
    grp = st.get('tab', 0)
    rect(im, (24, 80, 76, 330), fa((10, 16, 30, 200), a), fa(LINE + (255,), a), 1)
    for i, cn in enumerate(['全部', '战斗', '成长', '资源']):
        y = 106 + i * 58
        on = i == grp
        circle(im, 50, y, 18, fa((CY if on else (18, 28, 48)) + (255,), a), fa(LINE + (255,), a) if not on else None, 1)
        T(im, 50 - tw(cn[0], 15) / 2, y - 10, cn[0], 15, fa(INK if on else TXT, a))
        T(im, 50 - tw(cn, 9, 'regular') / 2, y + 21, cn, 9, fa(SUB, a), 'regular')
    # 中：当前链
    ox = 110 + (1 - st['sel_ease']) * 20
    ca = a * (0.4 + 0.6 * st['sel_ease'])
    g = next(gg for gg in GROUPS if p in gg[2])
    T(im, ox, 82, 'CHAIN %02d  //  %s  //  %s' % (sel + 1, g[1], CHAIN_EN[p]), 8, fa(SUB, ca), 'latin', 2.5)
    T(im, ox, 98, chain_title(p), 40, fa(TXT, ca))
    T(im, ox + tw(chain_title(p), 40) + 16, 120, '%d / %d' % (level(p, shape), len(ids)), 20, fa(CY_HI, ca))
    T(im, ox, 152, '本链合计  ' + summary(p, shape), 14, fa(SUB, ca), 'regular')
    cw = 210 if len(ids) >= 4 else 260
    gap = 14
    for j, k in enumerate(ids):
        x = ox + j * (cw + gap)
        y = 196
        n = NODES[k]
        done = k in shape
        lit = k == st.get('lit_id')
        lp = st.get('lit', 0) if lit else 0
        nxt = k == next_id(p, shape)
        on_card = done or (lit and lp >= 0.5)
        fill = (230, 233, 236, 240) if on_card else ((24, 48, 76, 235) if nxt else (12, 18, 32, 220))
        rect(im, (x, y, x + cw, y + 236), fa(fill, ca))
        if nxt or lit:
            rect(im, (x, y, x + cw, y + 236), None, fa(CY + (255,), ca), 1.6)
        if lit and 0.5 <= lp < 1:
            gr = (lp - 0.5) / 0.5
            rect(im, (x - 10 * gr, y - 10 * gr, x + cw + 10 * gr, y + 236 + 10 * gr), None, fa(WARM + (255,), ca * (1 - gr)), 2)
        ink = INK if on_card else (TXT if nxt else DIM)
        T(im, x + 16, y + 12, ROMAN[j], 30, fa(ink, ca))
        chip = '已塑造' if on_card else ('下一节' if nxt else '未解锁')
        T(im, x + cw - 16 - tw(chip, 11, 'regular'), y + 22, chip, 11, fa((24, 130, 160) if on_card else (CY_HI if nxt else DIM), ca), 'regular')
        T(im, x + 16, y + 60, n['name'], 16, fa(ink, ca))
        first = n['desc'].split('。')[0]
        rest = '。'.join(n['desc'].split('。')[1:]).strip('。')
        yy = y + 92
        for ln in wrap(first, 14, cw - 32)[:2]:
            T(im, x + 16, yy, ln, 14, fa(INK2 if on_card else (TXT if nxt else DIM), ca), 'regular'); yy += 20
        if rest:
            yy += 8
            tg = RULE_TAG.get(k, '规则')
            rect(im, (x + 16, yy, x + 16 + tw(tg, 10) + 10, yy + 16), fa(((22, 24, 28) if on_card else CY) + (255,), ca))
            T(im, x + 21, yy + 1, tg, 10, fa((255, 255, 255) if on_card else INK, ca))
            yy += 24
            for ln in wrap(rest, 12, cw - 32)[:5]:
                T(im, x + 16, yy, ln, 12, fa(INK2 if on_card else (SUB if nxt else DIM), ca), 'regular'); yy += 17
        T(im, x + 16, y + 208, '消耗 %d' % n['cost'], 12, fa(INK2 if on_card else (CY_HI if nxt else DIM), ca), 'regular')
        if j < len(ids) - 1:
            line(im, [(x + cw, y + 118), (x + cw + gap, y + 118)], fa(((210, 220, 230) if ids[j + 1] in shape else LINE) + (255,), ca), 2)
    # 下：链卡（同选人名册条）
    shown = CHAINS if grp == 0 else GROUPS[grp - 1][2]
    x = 110
    for gname, gen, cs in GROUPS:
        cs = [c for c in cs if c in shown]
        if not cs:
            continue
        T(im, x, 548, gname, 11, fa(CY, a))
        line(im, [(x + tw(gname, 11) + 6, 556), (x + len(cs) * 92 - 6, 556)], fa(LINE, a), 1)
        for c in cs:
            on = c == p
            dy = -8 * st['sel_ease'] if on else 0
            rect(im, (x, 566 + dy, x + 86, 680 + dy), fa(PANEL_SEL if on else PANEL, a), fa((CY if on else LINE) + (255,), a), 1.4 if on else 1)
            icon(im, x + 43, 594 + dy, c, fa((CY_HI if on else SUB) + (255,), a))
            T(im, x + 43 - tw(chain_title(c), 12) / 2, 614 + dy, chain_title(c), 12, fa(TXT, a))
            nn = len(chain_ids(c))
            pips(im, x + 43 - (nn * 12 - 4) / 2, 640 + dy, c, shape, a, 8, 4, st.get('lit_id'), st.get('lit', 0))
            x += 92
        x += 10
    nk = next_id(p, shape)
    bx = max(x + 8, 1080)
    if nk:
        button(im, (bx, 566, 1256, 680), '塑造 %s' % ROMAN[ids.index(nk)], 'ENTER · 消耗 %d' % NODES[nk]['cost'], a, NODES[nk]['cost'] <= st['cells'], st.get('press', 0))
    else:
        button(im, (bx, 566, 1256, 680), '本链已满', '', a, False)
    hint(im, a, '←→ 换链  ·  Q / E 分组  ·  Enter 塑造  ·  R 推荐  ·  X 两次全部重置  ·  Esc 返回')
    return im


PLANS = {'A': (plan_a, '档案列表', '照图鉴：10 条链各一行（等级格 + 当前总加成 + 下一节消耗），右侧浅色面板逐节列出，一屏读完全部进度'),
         'B': (plan_b, '整齐图谱', '保留树：10 列按 战斗 / 成长 / 资源 等距排齐、不斜不扇，去背景碎片和每节名字，节点只标罗马数字'),
         'C': (plan_c, '单链聚焦', '照选人：底部一排链卡像名册，中间放大当前链的各节卡片（效果、质变规则一眼看全），右下大按钮塑造')}


def state_at(key, t):
    """10 秒演示脚本：0–0.8 进入 → 依次选 攻击 / 生命 / 减伤 → 回到攻击看详情 → 5.4 塑造下一节（细胞扣减、节点点亮）→ 7.4 起切到成长组"""
    ease = lambda x: 1 - (1 - max(0.0, min(1.0, x))) ** 3
    st = {'appear': ease(t / 0.8), 'shape': set(SHAPE0), 'cells': EARNED - spent(SHAPE0), 'tab': 0, 'node': None}
    keys = [(0.0, 'atk'), (1.4, 'hp'), (2.2, 'def'), (3.0, 'atk'), (7.4, 'xp'), (8.6, 'pick')]
    cur, t0 = 'atk', 0.0
    for kt, c in keys:
        if t >= kt:
            cur, t0 = c, kt
    st['sel'] = CHAINS.index(cur)
    st['sel_ease'] = ease((t - t0) / 0.25) if t0 > 0 else st['appear']
    nk = next_id('atk', SHAPE0)
    if key == 'B' and cur == 'atk' and 3.6 <= t < 5.0:
        st['node'] = min(4, level('atk', SHAPE0) - 1 + (1 if t >= 4.3 else 0))   # 沿链看一节已塑造的、再落到下一节
    if key in ('A', 'C') and t >= 7.4:
        st['tab'] = 2 if key == 'A' else 2
    if t >= 5.4:
        st['press'] = max(0.0, 1 - abs(t - 5.5) / 0.15)
        lp = min(1.0, (t - 5.5) / 1.0)
        if lp > 0:
            st['lit_id'] = nk
            st['lit'] = lp
            cost = NODES[nk]['cost']
            st['cells'] = int(round(EARNED - spent(SHAPE0) - cost * min(1.0, lp / 0.5)))
            if lp >= 1:
                st['shape'].add(nk)
                st['lit_id'] = None
    if key == 'B' and t >= 5.0 and cur == 'atk':
        st['node'] = SHAPE0 and chain_ids('atk').index(nk)
    return st


def finish(im):
    return im.resize((1600, 900), Image.Resampling.LANCZOS).convert('RGB')


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    video = '--video' in sys.argv
    stills = {}
    for key, (fn, name, _) in PLANS.items():
        st = state_at(key, 4.0)
        im = finish(fn(st))
        im.save(OUT / f'{key}.png')
        stills[key] = im
        if video:
            fdir = OUT / f'frames_{key}'
            shutil.rmtree(fdir, ignore_errors=True)
            fdir.mkdir()
            for f in range(240):
                finish(fn(state_at(key, f / 24.0))).save(fdir / f'f_{f:03d}.png')
            subprocess.run([FFMPEG, '-y', '-loglevel', 'error', '-framerate', '24', '-i', str(fdir / 'f_%03d.png'), '-c:v', 'libx264', '-pix_fmt', 'yuv420p',
                            '-crf', '22', '-movflags', '+faststart', str(OUT / f'{key}.mp4')], check=True)
            shutil.rmtree(fdir, ignore_errors=True)
            print(key, (OUT / f'{key}.mp4').stat().st_size)
    # 并排对比：现状（桌面）+ 三方案
    now = Image.open(ROOT / 'build/meta_ui/now/desk/shot_meta.png').convert('RGB').resize((800, 450), Image.Resampling.LANCZOS)
    tiles = [('现状', '10 条链扇形散开、39 个节点全标名、背景碎片线条、左浅右暗两块，信息挤在一起', now)] + \
            [(f'方案 {k} · {v[1]}', v[2], stills[k].resize((800, 450), Image.Resampling.LANCZOS)) for k, v in PLANS.items()]
    b = Image.new('RGB', (1620, 1080), '#0b151d')
    d = ImageDraw.Draw(b)
    from PIL import ImageFont
    f1 = ImageFont.truetype(str(ROOT / 'game/fonts/ui.ttf'), 22)
    f2 = ImageFont.truetype(str(ROOT / 'game/fonts/ui.ttf'), 15)
    for i, (t1, t2, im) in enumerate(tiles):
        x = (i % 2) * 815 + 5
        y = (i // 2) * 540 + 5
        d.text((x + 4, y + 2), t1, font=f1, fill='#e9f0f3')
        d.text((x + 4, y + 32), t2, font=f2, fill='#9fb4c1')
        b.paste(im, (x, y + 60))
    b.save(OUT / 'compare.png')
    print('ok')


if __name__ == '__main__':
    main()
