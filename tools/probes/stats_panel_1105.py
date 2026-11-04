"""属性栏（Tab）按指挥台统一风格的示意（用户 11-05「属性图开始做了吗」，docs/222 §18.3 待办）。只出图，不改游戏代码。
做法同指挥台：不画框、不用彩色标签片；常态黑白灰，青 = 能操作 / 当前，洋红 = 危险，金 = 灯火 / 羁绊；
三栏顺序同指挥台（左 队长生存 / 中 攻击与技能 / 右 编队、指令、藏品）；共用部件：头像刻度环、马灯、细线条、方头像、指令牌。
用法：python stats_panel_1105.py <worktree> <底图（实机带指挥台截图）> <现属性栏截图（取藏品图标）> <马灯帧条目录> <输出目录>"""
import json, math, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import hud_console_1105 as H
from hud_console_1105 import A, M, CYAN, RED, GOLD, font
from hud_console_1105r3 import WHITE, GREY, DIM, mono
from PIL import Image, ImageDraw, ImageEnhance

WT, BASE, OLD, LANT, OUT = sys.argv[1:6]
from PIL import ImageFont, ImageFilter
from fontTools.ttLib import TTFont
_CM = TTFont(os.path.join(WT, 'game', 'fonts', 'ui.ttf')).getBestCmap()
_FB = {}
_orig_text = M.text


def _text_fb(self, x, y, s, size, col, kind='cn', anchor='ls', sp=0.0):
    """ui.ttf 是子集：缺的字按游戏里的回退链（ui_fallback → 系统黑体）画"""
    if kind != 'cn' or all(ord(ch) in _CM for ch in s):
        return _orig_text(self, x, y, s, size, col, kind, anchor, sp)
    f0 = font('cn', self.P(size))
    key = int(self.P(size))
    if key not in _FB:
        _FB[key] = ImageFont.truetype('C:/Windows/Fonts/msyhbd.ttc', key)
    fb = _FB[key]
    w = sum((f0 if ord(ch) in _CM else fb).getlength(ch) for ch in s)
    x0 = self.P(x) - (w / 2 if anchor[0] == 'm' else (w if anchor[0] == 'r' else 0))
    for ch in s:
        f = f0 if ord(ch) in _CM else fb
        self.d.text((x0, self.P(y)), ch, font=f, fill=col, anchor='l' + anchor[1])
        x0 += f.getlength(ch)
    return w / self.s


M.text = _text_fb
ART = os.path.join(WT, 'game', 'art')
os.makedirs(OUT, exist_ok=True)


def lantern(m, x, y, lv, px):
    t = 90 if lv >= 70 else (50 if lv >= 30 else (18 if lv > 0 else 0))
    im = Image.open(os.path.join(LANT, 'sheet_%d.png' % t)).convert('RGBA')
    meta = json.load(open(os.path.join(LANT, 'sheet_%d.json' % t)))['meta']['pixelfx']
    fw, fh = meta['frameSize']
    fr = im.crop((5 * fw, 0, 6 * fw, fh)).resize((fw * px, fh * px), Image.NEAREST)
    pv = meta['pivot']
    m.ov.alpha_composite(fr, (int(m.P(x) - pv[0] * px), int(m.P(y) - pv[1] * px)))


def hair(m, x, y, w, frac, col, ticks=(), h=1.6):
    m.rect(x, y, w, h, fill=DIM)
    m.rect(x, y - h * 0.5, w * frac, h * 2, fill=col)
    for t in ticks:
        m.rect(x + w * t - 0.4, y - 3, 0.8, h + 6, fill=(255, 255, 255, 120))


def row(m, x, y, w, lab, val, vcol=WHITE, size=9.5):
    m.text(x, y, lab, size, GREY, 'cn', 'ls')
    m.text(x + w, y, val, size, vcol, 'cn', 'rs')
    m.rect(x, y + 5, w, 0.6, fill=(255, 255, 255, 22))


def head(m, label, en, x, y, w):
    m.text(x, y, label, 12, WHITE, 'cn', 'ls')
    lw = font('cn', m.P(12)).getlength(label) / m.s
    mono(m, x + lw + 6, y - 1, en, 4.6, GREY)
    m.rect(x, y + 6, w, 0.7, fill=(255, 255, 255, 50))
    m.rect(x, y + 5.6, 14, 1.6, fill=WHITE)


def wrap(m, x, y, w, s, size, col, lh):
    f = font('cn', m.P(size))
    line = ''
    for ch in s:
        if f.getlength(line + ch) / m.s > w:
            m.text(x, y, line, size, col, 'cn', 'ls')
            y += lh
            line = ch
        else:
            line += ch
    if line:
        m.text(x, y, line, size, col, 'cn', 'ls')
        y += lh
    return y


def badge(m, c, r, img, ek=0.5):
    RR = r + 4
    m.circle(c[0], c[1], r + 1, fill=(0, 0, 0, 160))
    m.paste_circle(img, c[0], c[1], r)
    for j in range(40):
        a = math.radians(-90 + j * 9)
        on = j < round(40 * ek)
        r0, r1 = RR + 2.2, RR + (4.6 if j % 10 == 0 else 3.4)
        m.line([(c[0] + math.cos(a) * r0, c[1] + math.sin(a) * r0), (c[0] + math.cos(a) * r1, c[1] + math.sin(a) * r1)],
               WHITE if on else (255, 255, 255, 40), 0.8)
    m.arc(c[0], c[1], RR, 0, 360, (255, 255, 255, 50), 2.4)
    m.arc(c[0], c[1], RR, -90, -90 + 360 * ek, WHITE, 2.4)


def mode_icon(m, cx, cy, i, r, col, w=1.0):
    import hud_console_1105r5 as R5
    R5.mode_icon(m, cx, cy, i, r, col, w)


def draw_pc(base_im, old_im, assets):
    bg = ImageEnhance.Brightness(base_im.convert('RGB').filter(ImageFilter.GaussianBlur(8))).enhance(0.14).convert('RGBA')
    m = M(bg, 1.875)   # 逻辑 1024×576：整张比指挥台的 1280 基准大 1.25 倍（用户嫌界面小）
    W, Hh = m.W, m.H
    # 整张一对直角刻度 + 页眉
    L, T, R_, B = 40, 34, W - 40, Hh - 34
    m.line([(L, T + 10), (L, T), (L + 10, T)], (255, 255, 255, 120), 1.0)
    m.line([(R_, B - 10), (R_, B), (R_ - 10, B)], (255, 255, 255, 120), 1.0)
    # 页眉左：头像刻度环 + 名字
    badge(m, (L + 34, T + 40), 24, assets['badge'], 0.5)
    m.rect(L + 34 - 15, T + 40 - 34, 30, 10, fill=(4, 6, 9, 230), outline=(255, 255, 255, 90), width=0.6)
    m.text(L + 34, T + 40 - 26.5, 'LV 3', 6.5, WHITE, 'num', 'ms')
    nx = L + 78
    m.text(nx, T + 36, '德克萨斯', 22, WHITE, 'cn', 'ls')
    mono(m, nx + 98, T + 34, 'TEXAS  ·  LEADER  ·  VANGUARD', 4.8, GREY)
    m.text(nx, T + 56, '编队 3/4  /  常规  /  结局一 · 平凡即是喜乐', 8.5, GREY, 'cn', 'ls')
    m.text(nx, T + 70, '特性  近战 · 位移 · 穿透 · 技力', 8.5, A(GREY, 200), 'cn', 'ls')
    # 页眉右：本局读数
    rx = R_ - 4
    for lab, v in (('源石锭', '18'), ('藏品', '9'), ('击杀', '29'), ('时间', '00:40')):
        vw = font('num', m.P(16)).getlength(v) / m.s
        m.text(rx, T + 40, v, 16, A(WHITE, 220), 'num', 'rs')
        m.text(rx, T + 54, lab, 7.5, GREY, 'cn', 'rs')
        rx -= max(vw, 28) + 26
    # 三栏
    top = T + 100
    cw = (R_ - L - 2 * 28) / 3
    xs = [L, L + cw + 28, L + 2 * (cw + 28)]
    for x in xs[1:]:
        m.rect(x - 14, top - 6, 0.6, B - top - 20, fill=(255, 255, 255, 26))
    # ---- 左：生存
    x = xs[0]
    head(m, '生存', 'SURVIVAL', x, top + 8, cw)
    y = top + 34
    lantern(m, x + 10, y + 36, 91, 2)
    gx = x + 32
    m.text(gx, y + 4, '生命', 8.5, GREY, 'cn', 'ls')
    m.text(x + cw, y + 6, '/ 158', 7.5, GREY, 'num', 'rs')
    m.text(x + cw - 26, y + 6, '158', 18, WHITE, 'num', 'rs')
    UI_d = [(gx + 26 + q * 9, y + 0.5) for q in range(1)]
    for (dx, dy) in UI_d:
        m.d.polygon([(m.P(dx), m.P(dy - 3)), (m.P(dx + 3), m.P(dy)), (m.P(dx), m.P(dy + 3)), (m.P(dx - 3), m.P(dy))], fill=(128, 216, 255, 255))
    hair(m, gx, y + 12, x + cw - gx, 1.0, WHITE)
    m.text(gx, y + 30, '灯火', 8.5, GREY, 'cn', 'ls')
    m.text(gx + 24, y + 30, '通明', 8.5, A(GOLD, 230), 'cn', 'ls')
    m.text(x + cw, y + 31, '91', 13, GOLD, 'num', 'rs')
    hair(m, gx, y + 37, x + cw - gx, 0.91, GOLD, ticks=(0.3, 0.7))
    y += 62
    for lab, val in (('生命回复', '2.2 / 秒（入队 +0.3）'), ('物理减伤 / 法抗', '4.0 / 0%'), ('闪避 物 / 法', '0% / 0%'),
                     ('移动速度', '165'), ('拾取范围', '71'), ('受击灯火损失', '×1.00'), ('照亮范围', '338'), ('护盾', '1 / 1 · 每 13.5 秒')):
        row(m, x, y, cw, lab, val)
        y += 19
    # ---- 中：攻击与技能
    x = xs[1]
    head(m, '攻击', 'OFFENSE', x, top + 8, cw)
    y = top + 34
    row(m, x, y, cw, '近战 / 远程', '×1.00 / ×1.00'); y += 19
    row(m, x, y, cw, '物理 / 法术', '×1.00 / ×1.00'); y += 19
    m.text(x, y, '本局伤害构成', 9.5, GREY, 'cn', 'ls')
    y += 9
    segs = (('远掷', 0.36, WHITE), ('冲锋模式', 0.21, (190, 196, 204, 255)), ('双刃', 0.18, (130, 138, 148, 255)), ('其他', 0.25, (70, 76, 84, 255)))
    xx = x
    for nm, f, c in segs:
        m.rect(xx, y, cw * f - 1, 3, fill=c)
        xx += cw * f
    y += 13
    xx = x
    for nm, f, c in segs[:3]:
        m.rect(xx, y - 5, 5, 5, fill=c)
        w = m.text(xx + 8, y, '%s %d%%' % (nm, round(f * 100)), 8, A(WHITE, 210), 'cn', 'ls')
        xx += w + 22
    y += 18
    head(m, '技能', 'SKILLS', x, y, cw)
    y += 18
    skills = [('skill_texas_s1', '剑雨', '所需技力 6 · 88%', '以自身为中心半径 130 落下剑雨，×1.6 并眩晕 0.5 秒（精英减半，Boss 除外），全队（不含自身）技力 +10%', True),
              ('skill_texas_s2', '冲锋号令 · γ型', '精英一解锁', '充能一次后永久生效：冲刺距离 +40%、伤害 ×1.3', False),
              ('skill_texas_s3', '剑雨滂沱', '精英二解锁', '8 秒内普攻换成「次元斩」：出手时她从原地隐去，追着附近的敌人连续闪现 5 次……', False)]
    for ic, nm, sub, desc, active in skills:
        p = os.path.join(ART, 'ui', 'skills', ic + '.png')
        if os.path.exists(p):
            im = Image.open(p).convert('RGBA')
            m.paste(im, x, y - 9, 24, 24, gray=not active, alpha=255 if active else 150)
        if active:
            m.rect(x - 4, y - 9, 1.6, 24, fill=CYAN)
        tx = x + 32
        nw = m.text(tx, y, nm, 10, WHITE if active else A(WHITE, 170), 'cn', 'ls')
        m.text(tx + nw + 8, y, sub, 7.5, CYAN if active else GREY, 'cn', 'ls')
        if active:
            hair(m, tx, y + 5, cw - 32, 0.88, CYAN, h=1.2)
        y = wrap(m, tx, y + 16, cw - 32, desc, 8, A(WHITE, 200) if active else GREY, 12) + 8
    # ---- 右：编队 / 指令 / 羁绊 / 藏品
    x = xs[2]
    head(m, '编队', 'SQUAD  3/4', x, top + 8, cw)
    y = top + 30
    pop = None
    for key, nm, cls, nxt, lead in (('badge', '德克萨斯', '先锋', '精英一', True), ('exusiai', '能天使', '狙击', '对空优先', False),
                                    ('lappland', '拉普兰德', '近卫', '双刃连斩', False)):
        im = assets[key]
        if key != 'badge':
            from hud_console_1105r5 import head_crop
            im = head_crop(im, key)
        m.paste(im, x, y, 22, 22)
        m.rect(x, y, 22, 22, outline=(255, 255, 255, 50), width=0.6)
        m.text(x + 30, y + 10, nm, 9.5, WHITE, 'cn', 'ls')
        if lead:
            mono(m, x + 30 + font('cn', m.P(9.5)).getlength(nm) / m.s + 6, y + 9, 'LEADER', 4.2, A(CYAN, 220))
        m.text(x + 30, y + 21, cls + ' · 精零', 7.5, GREY, 'cn', 'ls')
        for d in range(6):   # 成长进度：普通节点 = 圆点，精英化 = 菱形（第 3、6 个）；选过的白，未选的暗；点它弹出已选节点
            px_ = x + cw - 74 + d * 9
            on = d < 2 and lead
            c_ = WHITE if on else (255, 255, 255, 60)
            if d in (2, 5):
                m.d.polygon([(m.P(px_), m.P(y + 3.6)), (m.P(px_ + 3.4), m.P(y + 7)), (m.P(px_), m.P(y + 10.4)), (m.P(px_ - 3.4), m.P(y + 7))], outline=c_)
            else:
                m.circle(px_, y + 7, 2.0, fill=c_)
        if lead:   # 当前选中的这一行：点阵外一圈细框 = 可点
            m.rect(x + cw - 79, y + 1.5, 55, 11, outline=(255, 255, 255, 120), width=0.6)
        m.text(x + cw, y + 21, '下一步 ' + nxt, 7.5, A(WHITE, 180), 'cn', 'rs')
        if lead:
            pop = (x + cw - 210, y + 16)
        y += 30
    y += 4
    m.rect(x, y, cw, 0.6, fill=(255, 255, 255, 26))
    y += 12
    # 指令牌（同指挥台）
    tile = 22
    m.rect(x, y, tile, tile, fill=(0, 0, 0, 120), outline=(255, 255, 255, 60), width=0.6)
    mode_icon(m, x + tile / 2, y + tile / 2, 0, tile * 0.36, WHITE, 1.2)
    m.text(x + tile + 8, y + 9, '随行', 10, WHITE, 'cn', 'ls')
    mono(m, x + tile + 34, y + 8, 'ESCORT', 4.4, GREY)
    m.text(x + tile + 8, y + 20, '队友不受伤  ·  出击时：攻速 +25% · 技力回复 ×1.5', 7.5, GREY, 'cn', 'ls')
    y += tile + 14
    m.text(x, y, '羁绊', 9.5, GREY, 'cn', 'ls')
    for i, ln in enumerate(('企鹅物流 · 全队攻速 +8% · 合击「急件专送」', '宿敌 · 对精英伤害 +10% · 合击「旧怨交锋」')):
        yy = y + i * 15
        m.d.polygon([(m.P(x + 36), m.P(yy - 6)), (m.P(x + 39), m.P(yy - 3)), (m.P(x + 36), m.P(yy)), (m.P(x + 33), m.P(yy - 3))], fill=GOLD)
        m.text(x + 44, yy, ln, 8.5, A(WHITE, 210), 'cn', 'ls')
    y += 40
    m.text(x, y, '藏品', 9.5, GREY, 'cn', 'ls')
    m.text(x + 26, y, '9', 9.5, WHITE, 'num', 'ls')
    m.text(x + cw, y, '悬停看效果', 7.5, GREY, 'cn', 'rs')
    y += 6
    icons = old_im.crop((1180, 748, 1724, 878))
    cell = 26
    for i in range(9):
        cx_ = 1180 + (i % 8) * 69
        cy_ = 748 + (i // 8) * 69
        ic = old_im.crop((cx_ + 2, cy_ + 2, cx_ + 58, cy_ + 58))
        gx_ = x + (i % 8) * (cell + 4)
        gy_ = y + (i // 8) * (cell + 4)
        m.rect(gx_, gy_, cell, cell, fill=(0, 0, 0, 90), outline=(255, 255, 255, 40), width=0.5)
        m.paste(ic, gx_ + 1, gy_ + 1, cell - 2, cell - 2)
    # 点成长进度点弹出的已选节点（以德克萨斯为例，节点名取自 data/characters/texas.json progression）
    px0, py0 = pop
    pw, ph = 186, 126
    m.rect(px0, py0, pw, ph, fill=(8, 10, 13, 245), outline=(255, 255, 255, 90), width=0.7)
    m.line([(px0 + pw - 30, py0), (px0 + pw - 24, py0 - 6), (px0 + pw - 18, py0)], (255, 255, 255, 90), 0.7)
    m.text(px0 + 10, py0 + 15, '德克萨斯 · 成长', 9, WHITE, 'cn', 'ls')
    mono(m, px0 + pw - 10, py0 + 14, '2 / 6', 4.6, GREY, 'rs')
    nodes = (('居合', '已选', True, False), ('破绽', '已选', True, False), ('精英一', '下一步', False, True),
             ('回马剑', '', False, False), ('剑雨·连', '', False, False), ('精英二', '', False, True))
    yy = py0 + 32
    for nm, st, on, elite in nodes:
        cx_ = px0 + 14
        c_ = WHITE if on else (255, 255, 255, 80)
        if elite:
            m.d.polygon([(m.P(cx_), m.P(yy - 6.4)), (m.P(cx_ + 3.4), m.P(yy - 3)), (m.P(cx_), m.P(yy + 0.4)), (m.P(cx_ - 3.4), m.P(yy - 3))], outline=c_)
        else:
            m.circle(cx_, yy - 3, 2.0, fill=c_)
        m.text(px0 + 24, yy, nm, 8.5, WHITE if on else A(WHITE, 150), 'cn', 'ls')
        if st:
            m.text(px0 + pw - 10, yy, st, 7.5, A(CYAN, 230) if st == '下一步' else GREY, 'cn', 'rs')
        yy += 16
    # 页脚：按键
    mono(m, R_ - 4, B - 6, 'TAB / C / ESC  返回', 5.0, GREY, 'rs') if False else m.text(R_ - 4, B - 6, 'TAB / C / ESC 返回', 8, GREY, 'cn', 'rs')
    return m.done()


def draw_phone(base_im, assets):
    bg = ImageEnhance.Brightness(base_im.convert('RGB').filter(ImageFilter.GaussianBlur(8))).enhance(0.14).convert('RGBA')
    m = M(bg, 2.0)   # 1170×540
    W, Hh = m.W, m.H
    L, T, R_ = 40, 26, W - 40
    badge(m, (L + 26, T + 30), 19, assets['badge'], 0.5)
    m.text(L + 62, T + 30, '德克萨斯', 20, WHITE, 'cn', 'ls')
    m.text(L + 62, T + 50, '编队 3/4 / 常规 / 结局一 · 平凡即是喜乐', 11, GREY, 'cn', 'ls')
    rx = R_
    for lab, v in (('源石锭', '18'), ('击杀', '29'), ('时间', '00:40')):
        vw = font('num', m.P(16)).getlength(v) / m.s
        m.text(rx, T + 32, v, 16, A(WHITE, 220), 'num', 'rs')
        m.text(rx, T + 48, lab, 10, GREY, 'cn', 'rs')
        rx -= max(vw, 34) + 22
    # 页签：文字页签，当前那页白字 + 下方一道白线（青只给可操作的东西，页签当前态用白）
    ty = T + 92
    tabs = ['属性', '攻击', '技能', '编队', '藏品']
    tw = (R_ - L) / 5
    for i, t in enumerate(tabs):
        cx = L + tw * i + tw / 2
        m.text(cx, ty, t, 15, WHITE if i == 0 else GREY, 'cn', 'ms')
        if i == 0:
            m.rect(cx - 22, ty + 9, 44, 2, fill=WHITE)
    m.rect(L, ty + 11, R_ - L, 0.6, fill=(255, 255, 255, 40))
    # 属性页：左 生命 / 灯火（马灯），右 两栏数值
    y = ty + 40
    lantern(m, L + 14, y + 50, 91, 3)
    gx = L + 44
    cw = (R_ - L) / 2 - 30
    m.text(gx, y + 4, '生命', 13, GREY, 'cn', 'ls')
    m.text(gx + cw - 44, y + 8, '/ 158', 11, GREY, 'num', 'rs')
    m.text(gx + cw - 80, y + 8, '158', 22, WHITE, 'num', 'rs')
    hair(m, gx, y + 16, cw - 44, 1.0, WHITE, h=2.0)
    m.text(gx, y + 42, '灯火  通明', 13, A(GOLD, 230), 'cn', 'ls')
    m.text(gx + cw - 44, y + 44, '91', 18, GOLD, 'num', 'rs')
    hair(m, gx, y + 52, cw - 44, 0.91, GOLD, ticks=(0.3, 0.7), h=2.0)
    rows = (('生命回复', '2.2 / 秒（入队 +0.3）'), ('物理减伤 / 法抗', '4.0 / 0%'), ('闪避 物 / 法', '0% / 0%'), ('移动速度', '165'),
            ('拾取范围', '71'), ('受击灯火损失', '×1.00'), ('照亮范围', '338'), ('护盾', '1 / 1 · 每 13.5 秒'))
    x2 = L + (R_ - L) / 2 + 10
    w2 = R_ - x2
    yy = y + 4
    for lab, val in rows:
        row(m, x2, yy, w2, lab, val, size=13)
        yy += 30
    m.text(R_, Hh - 14, '点空白处返回', 11, GREY, 'cn', 'rs')
    return m.done()


def main():
    cfg = json.load(open(os.path.join(os.path.dirname(BASE), 'crops.json'), encoding='utf-8')) if False else None
    t1 = r"C:/Users/colafax/AppData/Local/Temp/claude/17117de69bbd8478/035779e7-7958-47d4-9a6f-8ada7d8d5733/scratchpad/t1"
    cfg = json.load(open(os.path.join(t1, 'crops.json'), encoding='utf-8'))
    H.CARD_BOXES.update({k: tuple(v) for k, v in cfg['cards'].items()})
    H.BADGE_BOX = tuple(cfg['badge'])
    H.EXTRA.update(cfg.get('extra', {}))
    H.BASE = t1
    assets = H.load_assets()
    out = draw_pc(Image.open(BASE), Image.open(OLD).convert('RGBA'), assets)
    out.save(os.path.join(OUT, 'stats_pc.png'))
    draw_phone(Image.open(BASE.replace('ingame_pc', 'ingame_phone')), assets).save(os.path.join(OUT, 'stats_phone.png'))
    print('ok')


if __name__ == '__main__':
    main()
