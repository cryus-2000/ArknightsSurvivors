# 蚀刻章改版示意：方案 A（套组蜂巢）/ 方案 B（蚀刻进度格），电脑 1280×720、手机横屏 1300×600（×2 出图）
import os
from PIL import Image, ImageDraw, ImageFont, ImageFilter
from medal_px import medal, up

HERE = os.path.dirname(os.path.abspath(__file__))
G = r'E:/ArknightsSurvivors/.claude/worktrees/hud-skill-cd-e5a2f6/game/'
OUT = r'E:/ArknightsSurvivors/Claude outputs/'
F_UI = G + 'fonts/ui.ttf'
F_HV = G + 'fonts/ui_heavy.ttf'
F_SERIF = G + 'fonts/serif.ttf'
F_EN = G + 'fonts/montserrat_semibold.ttf'

T = (232, 240, 248)
SUB = (150, 170, 196)
DIM = (86, 104, 130)
CY = (110, 220, 255)
GOLD = (236, 200, 110)
TIERC = {1: (138, 150, 168), 2: (110, 210, 230), 3: (236, 200, 110)}

# 12 枚：key, 名, 星, 章面图, 状态, 镀层, 进度
MEDALS = [
    ('set', '深蓝之下', 3, 3, 'locked', False, (7, 11)),
    ('e_std', '泡影散尽', 1, 1, 'got', False, None),
    ('e_kn', '骑士归潮', 2, 2, 'got', False, None),
    ('e_deep', '潮声止息', 2, 4, 'locked', False, None),
    ('e_res', '深蓝之树', 2, 5, 'got', True, None),
    ('elite', '协同晋升', 2, 7, 'got', False, None),
    ('relic', '海中拾遗', 1, 8, 'line', False, (37, 50)),
    ('cog1', '初识深蓝', 1, 11, 'got', False, None),
    ('cogall', '认知深化', 2, 10, 'locked', False, (21, 34)),
    ('new1', '招募记录（新）', 1, 11, 'locked', False, (26, 40)),
    ('new2', '水月同行（新）', 2, 1, 'locked', False, (4, 10)),
    ('new3', '深潮之下（新）', 2, 2, 'locked', False, None),
]


def font(p, n):
    return ImageFont.truetype(p, int(n))


class Cv:
    def __init__(self, w, h, s, bg):
        self.s = s
        self.im = bg.resize((int(w * s), int(h * s)), Image.NEAREST).convert('RGBA')
        self.d = ImageDraw.Draw(self.im)
        self.w, self.h = w, h

    def S(self, *v):
        return [int(round(x * self.s)) for x in v]

    def text(self, xy, t, size, col=T, f=F_UI, anchor='la', spacing=0):
        fo = font(f, size * self.s)
        if spacing:
            x, y = xy
            for ch in t:
                self.d.text(self.S(x, y), ch, fill=col, font=fo, anchor=anchor)
                x += fo.getlength(ch) / self.s + spacing
            return x
        self.d.text(self.S(*xy), t, fill=col, font=fo, anchor=anchor)
        return xy[0] + fo.getlength(t) / self.s

    def tw(self, t, size, f=F_UI):
        return font(f, size * self.s).getlength(t) / self.s

    def rect(self, r, fill=None, outline=None, w=1):
        x, y, ww, hh = r
        self.d.rectangle(self.S(x, y, x + ww, y + hh), fill=fill, outline=outline, width=max(1, int(w * self.s)))

    def line(self, a, b, col, w=1):
        self.d.line(self.S(*a, *b), fill=col, width=max(1, int(w * self.s)))

    def para(self, r, fill, sk=8):
        x, y, w, h = r
        self.d.polygon([tuple(self.S(x + sk, y)), tuple(self.S(x + w, y)), tuple(self.S(x + w - sk, y + h)), tuple(self.S(x, y + h))], fill=fill)

    def medal(self, img, cx, cy, k):
        """k = 每个美术像素占几个界面单位"""
        m = up(img, max(1, int(round(k * self.s))))
        self.im.alpha_composite(m, (int(cx * self.s - m.width / 2), int(cy * self.s - m.height / 2)))
        return m.width / self.s

    def wrap(self, xy, t, size, w, col=SUB, lh=1.55, f=F_UI):
        fo = font(f, size * self.s)
        x, y = xy
        line = ''
        for ch in t:
            if fo.getlength(line + ch) / self.s > w and ch not in '」。，、）':
                self.d.text(self.S(x, y), line, fill=col, font=fo)
                y += size * lh
                line = ch
            else:
                line += ch
        if line:
            self.d.text(self.S(x, y), line, fill=col, font=fo)
            y += size * lh
        return y

    def dim(self, a):
        ov = Image.new('RGBA', self.im.size, (4, 8, 16, int(255 * a)))
        self.im.alpha_composite(ov)


def bg_page():
    return Image.open(G + 'art/ui/medals/bg_src.png').convert('RGBA')


def stars(c, x, y, n, size, col):
    for i in range(3):
        c.text((x + i * size * 1.05, y), '★', size, col if i < n else (60, 74, 96), f=F_UI)


def back_btn(c, phone):
    w = 110 if phone else 120
    x = c.w - w - 24
    c.para((x, 18, w, 34), (20, 34, 56, 230), 10)
    c.line((x + 10, 18), (x + w, 18), (180, 200, 220), 1)
    if not phone:
        c.rect((x + 18, 26, 28, 17), outline=(150, 170, 196), w=1)
        c.text((x + 32, 34.5), 'ESC', 9, SUB, anchor='mm')
    c.text((x + (w / 2 + 14 if not phone else w / 2), 35), '返回', 15 if phone else 13, T, f=F_HV, anchor='mm')


def mstate(m):
    return m[4]


def detail_A(c, x, y, w, m, phone):
    key, name, tier, face, st, plated, prog = m
    col = TIERC[tier]
    hh = 34 if phone else 30
    c.rect((x, y, w, hh), fill=tuple(int(v * 0.42) for v in col) + (255,))
    c.rect((x, y, 4, hh), fill=col)
    c.text((x + 14, y + hh / 2), '“%s”' % name, 18 if phone else 16, T, f=F_HV, anchor='lm')
    stars(c, x + w - (66 if phone else 58), y + hh / 2 - (9 if phone else 8), tier, 17 if phone else 15, col)
    y += hh
    c.rect((x, y, w, (250 if phone else 250)), fill=(12, 22, 40, 225))
    img = medal(face, 48, 'A', tier, 'got' if st == 'got' else 'locked', plated)
    mw = c.medal(img, x + (62 if phone else 70), y + (66 if phone else 72), 2)
    tx = x + (128 if phone else 140)
    fs = 13 if phone else 12
    yy = c.wrap((tx, y + 16), '为在探索中见证「静谧时代」的您颁发的蚀刻章。', fs, w - (tx - x) - 14, T)
    yy = c.wrap((tx, yy + 2), '潮水退去以后，岸上的人终于能睡个安稳觉。', fs, w - (tx - x) - 14, SUB)
    yy = max(yy, y + 138 if not phone else y + 128) + 6
    for tag, txt, tc in [('获得方式', '达成结局「静谧时代」。', (70, 84, 104)), ('镀层方式', '在「深潮」难度下达成结局「静谧时代」。', (54, 96, 120))]:
        tw = c.tw(tag, fs) + 12
        c.rect((x + 14, yy, tw, fs + 8), fill=tc)
        c.text((x + 20, yy + 3), tag, fs, T, f=F_HV)
        yy = c.wrap((x + 20 + tw, yy + 3), txt, fs, w - tw - 40, T) + 6
    c.line((x + 14, yy + 4), (x + w - 14, yy + 4), (40, 60, 86), 1)
    c.text((x + 14, yy + 14), '获得于 2026-11-08 · 已镀层 0 / 1', fs - 1, DIM)
    return y


# ---------------------------------------------------------------- 方案 A：套组蜂巢
HEX_A = [  # 蜂巢格（列, 行），★★★ 占大格
    (0, 0), (1.55, -0.6), (2.5, -0.06), (3.45, -0.6), (1.55, 0.6), (2.5, 1.14), (3.45, 0.6), (4.4, 0.06), (4.4, 1.2), (5.35, 0.6), (5.35, -0.6), (4.4, -1.08)
]


def page_A(phone):
    W, H = (1300, 600) if phone else (1280, 720)
    c = Cv(W, H, 2 if phone else 1, bg_page())
    c.dim(0.18)
    c.text((40 if not phone else 36, 34), '蚀刻章', 15 if phone else 13, T, f=F_HV, spacing=4)
    back_btn(c, phone)
    # 左栏
    lx = 70 if not phone else 52
    ty = 250 if not phone else 150
    c.text((lx, ty), '深蓝之下', 58 if not phone else 48, T, f=F_SERIF)
    c.text((lx + 4, ty + (78 if not phone else 64)), 'BENEATH  THE  BLUE', 12 if not phone else 12, SUB, f=F_EN, spacing=3)
    y2 = ty + (112 if not phone else 96)
    c.text((lx + 4, y2), '蚀刻章套组  ·  07 / 12', 15 if phone else 14, T, f=F_HV)
    for i, (n, col, got, tot) in enumerate([(3, TIERC[3], 0, 1), (2, TIERC[2], 3, 7), (1, TIERC[1], 3, 4)]):
        yy = y2 + 30 + i * (24 if phone else 22)
        stars(c, lx + 4, yy, n, 13, col)
        c.text((lx + 58, yy), '%d / %d' % (got, tot), 13, SUB, f=F_EN)
    # 蜂巢：★★★ 大格在左，其余 11 枚按正六边形密铺（尖顶，横距 = 格宽，行距 = 0.75 格高，奇数行错半格）
    k = 2
    P = 46 * k
    ox, oy = (420, 360) if not phone else (390, 300)
    big = MEDALS[0]
    c.medal(medal(big[3], 64, 'A', 3, 'got' if big[4] == 'got' else 'locked'), ox, oy, k)
    cells = [(0, 0), (1, 0), (2, 0), (3, 0), (0, 1), (1, 1), (2, 1), (3, 1), (0, 2), (1, 2), (2, 2)]
    x0 = ox + 64 * k / 2 + P * 0.62
    y0 = oy - P * 0.75
    for i, m in enumerate(MEDALS[1:]):
        key, name, tier, face, st, plated, prog = m
        col, row = cells[i]
        cx = x0 + col * P + (P / 2 if row % 2 else 0)
        cy = y0 + row * P * 0.75 * 1.02
        S = {1: 32, 2: 44, 3: 64}[tier]
        c.medal(medal(face, S, 'A', tier, 'got' if st == 'got' else 'locked', plated), cx, cy, k)
        if i + 1 == 2:
            r = 44 * k / 2 + 8
            c.d.regular_polygon((cx * c.s, cy * c.s, r * c.s), 6, rotation=30, outline=CY, width=int(2 * c.s))
    # 详情
    dw = 340 if not phone else 330
    detail_A(c, W - dw - 30, 92 if not phone else 74, dw, MEDALS[2], phone)
    # 底栏
    by = H - 34
    if not phone:
        c.text((40, by), 'Q / E 切换套组  ·  ← → ↑ ↓ 选择  ·  ESC 返回', 11, DIM)
    c.text((W / 2 + (60 if not phone else 40), by), '‹   深蓝之下   1 / 1   ›', 13 if phone else 12, SUB, anchor='mm')
    c.text((W - 30, by), '未获得：剪影 + 获得方式可见', 12 if phone else 11, DIM, anchor='ra')
    return c.im


# ---------------------------------------------------------------- 方案 B：蚀刻进度格
CATS = [('全部', 12), ('结局', 4), ('探索', 3), ('编队', 2), ('认知', 2), ('套组', 1)]


def page_B(phone):
    W, H = (1300, 600) if phone else (1280, 720)
    c = Cv(W, H, 2 if phone else 1, bg_page())
    c.dim(0.35)
    c.text((40 if not phone else 36, 34), '蚀刻章', 15 if phone else 13, T, f=F_HV, spacing=4)
    back_btn(c, phone)
    # 套组页签
    tx = 150 if not phone else 140
    for i, (n, sub, on) in enumerate([('深蓝之下', '07 / 12', True), ('？？？', '后续套组', False)]):
        w = 170
        c.para((tx, 22, w, 32), (CY + (255,)) if on else (24, 36, 56, 220), 10)
        c.text((tx + 20, 38), n, 14, (8, 20, 36) if on else DIM, f=F_HV, anchor='lm')
        c.text((tx + w - 18, 38), sub, 11, (8, 20, 36) if on else DIM, f=F_HV, anchor='rm')
        tx += w + 8
    # 分类栏（电脑）/ 分类条（手机）
    gx = 40 if not phone else 36
    gy = 84 if not phone else 74
    if not phone:
        for i, (n, cnt) in enumerate(CATS):
            y = gy + 10 + i * 40
            on = i == 0
            c.rect((gx, y, 120, 32), fill=(30, 50, 78, 230) if on else (14, 24, 40, 200))
            if on:
                c.rect((gx, y, 3, 32), fill=CY)
            c.text((gx + 14, y + 16), n, 13, T if on else SUB, f=F_HV, anchor='lm')
            c.text((gx + 108, y + 16), str(cnt), 11, SUB, f=F_EN, anchor='rm')
        gx2 = 180
    else:
        gx2 = gx
    # 格子
    cols = 4 if not phone else 6
    tw_, th_ = (128, 150) if not phone else (118, 150)
    gy2 = gy + (10 if not phone else 4)
    for i, m in enumerate(MEDALS):
        key, name, tier, face, st, plated, prog = m
        x = gx2 + (i % cols) * (tw_ + 8)
        y = gy2 + (i // cols) * (th_ + 8)
        sel = i == 6
        c.rect((x, y, tw_, th_), fill=(18, 30, 50, 230) if st == 'got' else (10, 18, 32, 220), outline=CY if sel else (36, 54, 80), w=2 if sel else 1)
        fill = 1.0
        stt = st
        if st == 'line' and prog:
            fill = prog[0] / prog[1]
            stt = 'got'
        img = medal(face, 44 if tier < 3 else 52, 'B', tier, 'got' if stt == 'got' else 'locked', False, fill)
        c.medal(img, x + tw_ / 2, y + 56, 2)
        nm = name.replace('（新）', '')
        c.text((x + tw_ / 2, y + 112), nm, 13 if not phone else 14, T if st == 'got' else SUB, f=F_HV, anchor='mm')
        if prog and st != 'got':
            pw = tw_ - 36
            c.rect((x + 18, y + 128, pw, 4), fill=(30, 44, 64))
            c.rect((x + 18, y + 128, pw * prog[0] / prog[1], 4), fill=TIERC[tier])
            c.text((x + tw_ / 2, y + 141), '%d / %d' % prog, 10, SUB, f=F_EN, anchor='mm')
        else:
            stars(c, x + tw_ / 2 - 24, y + 125, tier, 13, TIERC[tier] if st == 'got' else (60, 74, 96))
        if '（新）' in name:
            c.text((x + 8, y + 6), '新增', 10, GOLD, f=F_HV)
    # 详情
    dw = 330 if not phone else 330
    dx = W - dw - 30
    dy = 74 if phone else 84
    m = MEDALS[6]
    col = TIERC[1]
    c.rect((dx, dy, dw, 32), fill=tuple(int(v * 0.42) for v in col) + (255,))
    c.rect((dx, dy, 4, 32), fill=col)
    c.text((dx + 14, dy + 16), '“海中拾遗”', 16 if not phone else 17, T, f=F_HV, anchor='lm')
    stars(c, dx + dw - 58, dy + 8, 1, 15, col)
    y = dy + 32
    c.rect((dx, y, dw, 300 if not phone else 290), fill=(12, 22, 40, 225))
    img = medal(8, 44, 'B', 1, 'got', False, 37 / 50)
    c.medal(img, dx + 70, y + 74, 3)
    fs = 12 if not phone else 13
    tx = dx + 140
    yy = c.wrap((tx, y + 18), '为在海中拾起许多旧物的您颁发的蚀刻章。', fs, dw - 154, T)
    yy = c.wrap((tx, yy + 2), '它们各有来处，如今都收在同一只箱子里。', fs, dw - 154, SUB)
    yy = max(yy, y + 150) + 4
    c.text((dx + 14, yy), '蚀刻进度', fs, SUB, f=F_HV)
    c.text((dx + dw - 14, yy), '37 / 50', fs, T, f=F_EN, anchor='ra')
    yy += fs + 8
    segs = 10
    for i in range(segs):
        c.rect((dx + 14 + i * (dw - 28) / segs, yy, (dw - 28) / segs - 3, 8), fill=TIERC[1] if i < 7 else (30, 44, 64))
    yy += 20
    for tag, txt, tcol in [('获得方式', '累计获得 50 种不同的藏品。', (70, 84, 104)), ('镀层方式', '累计获得 100 种不同的藏品。', (54, 96, 120))]:
        tw = c.tw(tag, fs) + 12
        c.rect((dx + 14, yy, tw, fs + 8), fill=tcol)
        c.text((dx + 20, yy + 3), tag, fs, T, f=F_HV)
        yy = c.wrap((dx + 20 + tw, yy + 3), txt, fs, dw - tw - 40, T) + 6
    c.text((dx + 14, yy + 8), '章面随进度从线稿蚀刻成铜面（未获得）', fs - 1, DIM)
    by = H - 30
    if not phone:
        c.text((40, by), 'Q / E 切换套组  ·  Tab 分类  ·  ← → ↑ ↓ 选择  ·  ESC 返回', 11, DIM)
    else:
        c.text((36, by), '分类：全部 · 结局 · 探索 · 编队 · 认知 · 套组（横向滑动）', 13, DIM)
    return c.im


# ---------------------------------------------------------------- 获得提示
def hud_bg(phone):
    p = HERE + ('/hud/hud_phone/shot_1260.png' if phone else '/hud/hud_desktop/shot_1260.png')
    return Image.open(p).convert('RGBA')


def toast_A(phone):
    W, H = (1300, 600) if phone else (1280, 720)
    bg = hud_bg(phone)
    c = Cv(W, H, 2 if phone else 1, bg.resize((W, H)))
    m = MEDALS[2]
    col = TIERC[2]
    bw, bh = (420, 86) if not phone else (430, 84)
    x, y = (W - bw) / 2, 64 if not phone else 70
    c.para((x, y, bw, bh), (8, 16, 30, 236), 14)
    c.line((x + 14, y), (x + bw, y), col, 2)
    c.line((x, y + bh), (x + bw - 14, y + bh), (40, 60, 86), 1)
    img = medal(m[3], 44, 'A', 2, 'got')
    c.medal(img, x + 62, y + bh / 2, 1.6)
    # 嵌入一瞬的亮环
    c.d.regular_polygon(((x + 62) * c.s, (y + bh / 2) * c.s, 46 * c.s), 6, rotation=30, outline=col + (160,), width=int(2 * c.s))
    c.text((x + 120, y + 22), '获得蚀刻章', 12 if not phone else 13, SUB, f=F_HV, spacing=2)
    c.text((x + 120, y + 52), '“骑士归潮”', 22 if not phone else 22, T, f=F_HV, anchor='lm')
    stars(c, x + bw - 80, y + 44, 2, 16, col)
    c.text((x + 120, y + 70), '达成结局「静谧时代」', 11 if not phone else 12, DIM)
    return c.im


def toast_B(phone):
    W, H = (1300, 600) if phone else (1280, 720)
    bg = hud_bg(phone)
    c = Cv(W, H, 2 if phone else 1, bg.resize((W, H)))
    c.dim(0.55)
    cx, cy = W / 2, H / 2 - 70
    img = medal(3, 64, 'B', 3, 'got', False, 0.55)
    w = c.medal(img, cx, cy, 3)
    for r, a in [(118, 120), (140, 60)]:
        c.d.regular_polygon((cx * c.s, cy * c.s, r * c.s), 6, rotation=30, outline=CY + (a,), width=int(2 * c.s))
    c.text((cx, cy + 158), '获得蚀刻章', 14, SUB, f=F_HV, anchor='mm', spacing=0)
    c.text((cx, cy + 190), '“深蓝之下”', 28, T, f=F_HV, anchor='mm')
    stars(c, cx - 30, cy + 212, 3, 18, TIERC[3])
    c.text((cx, cy + 250), '套组「深蓝之下」已集齐 · 点击任意处继续（局终结算 / 标题页）', 12, DIM, anchor='mm')
    return c.im


def main():
    os.makedirs(OUT, exist_ok=True)
    # 章面样张
    for sch in 'AB':
        row = []
        if sch == 'A':
            row = [(medal(11, 32, 'A', 1), '★ 铁框 32'), (medal(2, 44, 'A', 2), '★★ 银框 44'), (medal(3, 64, 'A', 3), '★★★ 双框 64'),
                   (medal(5, 44, 'A', 2, plated=True), '★★ 镀层'), (medal(4, 44, 'A', 2, 'locked'), '未获得 剪影')]
        else:
            row = [(medal(11, 44, 'B', 1), '★ 铜'), (medal(2, 44, 'B', 2), '★★ 银'), (medal(3, 52, 'B', 3), '★★★ 白金'),
                   (medal(8, 44, 'B', 1, 'got', False, 0.74), '蚀刻中 37/50'), (medal(4, 44, 'B', 2, 'locked'), '未获得 线稿')]
        k = 5
        cw = 74 * k
        sh = Image.new('RGBA', (cw * len(row), 92 * k), (8, 16, 30, 255))
        d = ImageDraw.Draw(sh)
        fo = font(F_HV, 22)
        for i, (im, lab) in enumerate(row):
            u = up(im, k)
            sh.alpha_composite(u, (i * cw + (cw - u.width) // 2, (72 * k - u.height) // 2))
            d.text((i * cw + cw / 2, 80 * k), lab, fill=T, font=fo, anchor='mm')
        sh.save(HERE + '/faces_%s.png' % sch)
    for sch, pg, ts in [('A', page_A, toast_A), ('B', page_B, toast_B)]:
        pg(False).convert('RGB').save(HERE + '/page_%s_pc.png' % sch)
        pg(True).convert('RGB').save(HERE + '/page_%s_ph.png' % sch)
        ts(False).convert('RGB').save(HERE + '/toast_%s_pc.png' % sch)
        ts(True).convert('RGB').save(HERE + '/toast_%s_ph.png' % sch)


if __name__ == '__main__':
    main()
