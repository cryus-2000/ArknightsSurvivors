"""局内 HUD「指挥台」三版式示意（用户 11-05：「视觉基本上只注意到正下的区域」「把队友、指挥、生命整合到一起」）。
只出图，不改游戏代码。A 部署栏（横条）/ B 中轴弧台（极简）/ C 两翼（中间留空）；各出电脑 16:9 + 手机横屏 + 状态放大。
底图：--nohud 的同一帧（电脑 1920×1080 = 1280×720 × 1.5；手机 2340×1080 = 1170×540 × 2）。头像从同一帧带界面截图里裁。
用法：python hud_console_1105.py <worktree> <底图目录> <输出目录>"""
import math, os, sys
from PIL import Image, ImageDraw, ImageFont, ImageFilter

WT, BASE, OUT = sys.argv[1], sys.argv[2], sys.argv[3]
FONTS = os.path.join(WT, "game", "fonts")


def rgb(h, a=255):
    h = h.lstrip('#')
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), a)


CYAN, VIOLET, RED, GOLD, GREEN = rgb('36e2dc'), rgb('7c6bff'), rgb('ff3d8b'), rgb('f4c04e'), rgb('2fd3a0')
TEXT, SUB, PAPER, INK = rgb('f2f4f5'), rgb('9aa3ad'), rgb('e9e7e1'), rgb('15171a')
PANEL = (12, 15, 18)


def A(c, a):
    return (c[0], c[1], c[2], int(a))


_fc = {}


def font(kind, px):
    key = (kind, int(px))
    if key not in _fc:
        f = {'cn': 'ui.ttf', 'num': 'montserrat_bold.ttf', 'semi': 'montserrat_semibold.ttf'}[kind]
        _fc[key] = ImageFont.truetype(os.path.join(FONTS, f), max(6, int(px)))
    return _fc[key]


class M:
    """在 s 倍的 RGBA 叠层上用逻辑坐标画"""

    def __init__(self, base, s):
        self.base = base.convert('RGBA')
        self.s = s
        self.W, self.H = base.size[0] / s, base.size[1] / s
        self.ov = Image.new('RGBA', base.size, (0, 0, 0, 0))
        self.d = ImageDraw.Draw(self.ov)

    def P(self, v):
        return v * self.s

    def R(self, x, y, w, h):
        return [self.P(x), self.P(y), self.P(x + w), self.P(y + h)]

    def rect(self, x, y, w, h, fill=None, outline=None, width=1.0):
        self.d.rectangle(self.R(x, y, w, h), fill=fill, outline=outline, width=max(1, round(self.P(width))) if outline else 0)

    def line(self, pts, col, w=1.0):
        self.d.line([(self.P(a), self.P(b)) for a, b in pts], fill=col, width=max(1, round(self.P(w))))

    def circle(self, cx, cy, r, fill=None, outline=None, w=1.0):
        self.d.ellipse(self.R(cx - r, cy - r, 2 * r, 2 * r), fill=fill, outline=outline, width=max(1, round(self.P(w))) if outline else 0)

    def arc(self, cx, cy, r, a0, a1, col, w=2.0):
        self.d.arc(self.R(cx - r, cy - r, 2 * r, 2 * r), a0, a1, fill=col, width=max(1, round(self.P(w))))

    def text(self, x, y, s, size, col, kind='cn', anchor='ls', sp=0.0):
        f = font(kind, self.P(size))
        if sp <= 0:
            self.d.text((self.P(x), self.P(y)), s, font=f, fill=col, anchor=anchor)
            return f.getlength(s) / self.s
        w = sum(f.getlength(ch) for ch in s) + self.P(sp) * (len(s) - 1)
        x0 = self.P(x) - (w / 2 if anchor[0] == 'm' else (w if anchor[0] == 'r' else 0))
        for ch in s:
            self.d.text((x0, self.P(y)), ch, font=f, fill=col, anchor='l' + anchor[1])
            x0 += f.getlength(ch) + self.P(sp)
        return w / self.s

    def cap(self, x, y, s, size=5.6, col=SUB, anchor='ls'):
        """字距拉开的英文小标签"""
        return self.text(x, y, s, size, col, 'semi', anchor, sp=size * 0.32)

    def panel(self, x, y, w, h, a=150, accent=CYAN, fade=0):
        """docs/37 面板：炭灰上亮下暗 + 顶部一线高光 + 左上一小段强调色；fade>0 时左右两端渐隐"""
        g = Image.new('RGBA', (max(1, int(self.P(w))), max(1, int(self.P(h)))), (0, 0, 0, 0))
        px = g.load()
        gw, gh = g.size
        for j in range(gh):
            t = j / max(1, gh - 1)
            c = (int(PANEL[0] + 14 * (1 - t)), int(PANEL[1] + 16 * (1 - t)), int(PANEL[2] + 18 * (1 - t)))
            for i in range(gw):
                al = a
                if fade:
                    e = min(i, gw - 1 - i) / max(1, self.P(fade))
                    al = a * min(1.0, e)
                px[i, j] = (c[0], c[1], c[2], int(al))
        self.ov.alpha_composite(g, (int(self.P(x)), int(self.P(y))))
        self.line([(x + fade * 0.6, y), (x + w - fade * 0.6, y)], (255, 255, 255, 46), 0.7)
        if accent and not fade:
            self.line([(x, y), (x + 18, y)], accent, 1.4)

    def paste(self, im, x, y, w, h, gray=False, alpha=255):
        t = im.resize((int(self.P(w)), int(self.P(h))), Image.LANCZOS).convert('RGBA')
        if gray:
            g = t.convert('LA').convert('RGBA')
            g = Image.blend(g, Image.new('RGBA', g.size, (20, 20, 24, 255)), 0.45)
            g.putalpha(t.getchannel('A'))
            t = g
        if alpha < 255:
            t.putalpha(t.getchannel('A').point(lambda v: v * alpha // 255))
        self.ov.alpha_composite(t, (int(self.P(x)), int(self.P(y))))

    def paste_circle(self, im, cx, cy, r):
        sz = int(self.P(2 * r))
        t = im.resize((sz, sz), Image.LANCZOS).convert('RGBA')
        mk = Image.new('L', (sz, sz), 0)
        ImageDraw.Draw(mk).ellipse([0, 0, sz - 1, sz - 1], fill=255)
        t.putalpha(mk)
        self.ov.alpha_composite(t, (int(self.P(cx - r)), int(self.P(cy - r))))

    def glow(self, x, y, w, h, col, rad=8):
        g = Image.new('RGBA', self.ov.size, (0, 0, 0, 0))
        ImageDraw.Draw(g).rectangle(self.R(x, y, w, h), outline=col, width=int(self.P(3)))
        g = g.filter(ImageFilter.GaussianBlur(self.P(rad) / 2))
        self.ov.alpha_composite(g)

    def done(self):
        out = self.base.copy()
        out.alpha_composite(self.ov)
        return out.convert('RGB')


# ---------------------------------------------------------------- 素材
def load_assets():
    hud = Image.open(os.path.join(BASE, 'pchud.png')).convert('RGBA')
    a = {}
    # 编队卡头像（1920 坐标，按带界面截图量）
    for k, box in CARD_BOXES.items():
        a[k] = hud.crop(box)
    a['badge'] = hud.crop(BADGE_BOX)
    for k, f in EXTRA.items():
        a[k] = Image.open(os.path.join(BASE, f)).convert('RGBA')
    return a


CARD_BOXES = {}
BADGE_BOX = None
EXTRA = {}

# 演示数据（后期局）
LEADER = {'name': '德克萨斯', 'lv': 27, 'hp': 142, 'hpmax': 196, 'lamp': 72, 'ult': 0.64, 'dash': 1, 'dash_cd': 0.55}
MATES = [
    {'id': 'exusiai', 'name': '能天使', 'hp': 0.86, 'col': rgb('f0c040')},
    {'id': 'lappland', 'name': '拉普兰德', 'hp': 0.31, 'col': rgb('c9ced6')},
    {'id': 'saria', 'name': '塞雷娅', 'hp': 1.0, 'col': rgb('d9b45a')},
]
MODES = ['随行', '突击', '部署', '集火']
MODE_I = 1
STATUS = '灯火通明 / 护盾 ×1'


def st_mates(state):
    ms = [dict(m) for m in MATES]
    if state == 'down':
        ms[2]['hp'] = 0.0
        ms[2]['down'] = 7
    return ms


def keycap(m, x, y, s, size=7.0, col=TEXT, bg=(0, 0, 0, 170), anchor='l'):
    """小按键牌，(x, y) 为左上（anchor 'l'）或右上（'r'）"""
    f = font('semi', m.P(size))
    w = f.getlength(s) / m.s + size * 0.9
    h = size * 1.55
    if anchor == 'r':
        x -= w
    elif anchor == 'm':
        x -= w / 2
    m.rect(x, y, w, h, fill=bg, outline=A(col, 150), width=0.6)
    m.text(x + w / 2, y + h / 2 + size * 0.05, s, size, col, 'semi', 'mm')
    return w


def bar(m, x, y, w, frac, col, h=2.0, marks=(), back=(255, 255, 255, 40), trail=None, rtl=False):
    m.rect(x, y, w, h, fill=back)
    if trail is not None and trail > frac:
        tx0 = x + w * (1 - trail) if rtl else x + w * frac
        m.rect(tx0, y, w * (trail - frac), h, fill=A(RED, 230))
    fw = w * max(0.0, min(1.0, frac))
    m.rect(x + w - fw if rtl else x, y, fw, h, fill=col)
    hx = x + w - fw if rtl else x + fw
    m.circle(hx, y + h / 2, h * 1.25, fill=col)
    for t in marks:
        mx = x + w * (1 - t) if rtl else x + w * t
        m.line([(mx, y - 2.5), (mx, y + h + 2.5)], (255, 255, 255, 120), 0.6)


def badge(m, cx, cy, r, assets, state, key='Q', touch=False):
    """队长徽记：头像圆 + 终结技充能环；充满时反白纸牌 + READY"""
    ult = 1.0 if state == 'ult' else LEADER['ult']
    m.circle(cx, cy, r + 4.5, fill=(8, 10, 12, 200))
    m.paste_circle(assets['badge'], cx, cy, r)
    m.arc(cx, cy, r + 3, 0, 360, (255, 255, 255, 40), 2.2)
    m.arc(cx, cy, r + 3, -90, -90 + 360 * ult, PAPER if ult >= 1 else CYAN, 2.2)
    if ult >= 1:
        m.glow(cx - r - 6, cy - r - 6, 2 * r + 12, 2 * r + 12, A(PAPER, 200), 10)
        m.circle(cx, cy, r + 5.5, outline=PAPER, w=1.0)
        w = 34
        m.rect(cx - w / 2, cy + r - 4, w, 10, fill=PAPER)
        m.text(cx, cy + r + 1.2, 'READY', 6.0, INK, 'num', 'mm')
    else:
        m.text(cx, cy + r + 7.5, '%d%%' % int(ult * 100), 6.5, CYAN, 'num', 'mm')
    if key and not touch:
        keycap(m, cx + r * 0.62, cy - r - 4, key, 7.5, PAPER if ult >= 1 else TEXT)


def hp_block(m, x, y, w, state, big=17.0, rtl=False, show_lamp=True):
    """生命大数字 + 细条 + 灯火细条。y 为数字基线"""
    hit = state == 'hit'
    hp = LEADER['hp'] - (38 if hit else 0)
    col = RED if hit else TEXT
    al = 'rs' if rtl else 'ls'
    xx = x + w if rtl else x
    m.cap(xx - (0 if not rtl else 0), y - big - 2.5, 'HP', 5.6, A(CYAN, 220), 'rs' if rtl else 'ls')
    n = m.text(xx, y, str(hp), big, col, 'num', al)
    small = ' / %d' % LEADER['hpmax']
    if rtl:
        m.text(xx - n - 2, y, small, big * 0.42, SUB, 'num', 'rs')
    else:
        m.text(xx + n + 2, y, small, big * 0.42, SUB, 'num', 'ls')
    f = hp / LEADER['hpmax']
    if hit:
        m.glow(x - 2, y + 3, w + 4, 6, A(RED, 220), 6)
    bar(m, x, y + 4.5, w, f, RED if hit else CYAN, 2.2, trail=(LEADER['hp'] / LEADER['hpmax']) if hit else None, rtl=rtl)
    if show_lamp:
        if rtl:
            nw = m.text(xx, y + 16.5, str(LEADER['lamp']), 7.5, GOLD, 'num', 'rs')
            m.cap(xx - nw - 3, y + 16, 'LAMP', 5.0, A(GOLD, 220), 'rs')
            bar(m, x, y + 13.5, w - 44, LEADER['lamp'] / 100, GOLD, 1.4, marks=(0.3, 0.7), rtl=True)
        else:
            cw = m.cap(xx, y + 16, 'LAMP', 5.0, A(GOLD, 220), 'ls')
            m.text(xx + cw + 3, y + 16.5, str(LEADER['lamp']), 7.5, GOLD, 'num', 'ls')
            bar(m, x + 44, y + 13.5, w - 44, LEADER['lamp'] / 100, GOLD, 1.4, marks=(0.3, 0.7))


def dash_pips(m, cx, y, state, key='SPACE', touch=False, label=True):
    n = LEADER['dash']
    for k in range(2):
        px = cx + (k - 0.5) * 11
        on = k < n
        pts = [(px, y - 4), (px + 4, y), (px, y + 4), (px - 4, y)]
        m.d.polygon([(m.P(a), m.P(b)) for a, b in pts], fill=CYAN if on else (255, 255, 255, 40))
        if not on:
            m.arc(px, y, 6.2, -90, -90 + 360 * LEADER['dash_cd'], (255, 255, 255, 140), 1.0)
    if label:
        m.text(cx, y + 14, '冲刺', 7.5, SUB, 'cn', 'ms')
    if key and not touch:
        keycap(m, cx, y - 19, key, 6.5, TEXT, anchor='m')


def mate_card(m, x, y, w, h, mt, assets, state, tag=None):
    """部署卡式队友：立绘窗 + 左上职业色角 + 底部血条；倒地灰掉 + 洋红框 + 读秒"""
    down = mt.get('down')
    m.rect(x, y, w, h, fill=(10, 12, 14, 170))
    m.paste(assets[mt['id']], x + 1, y + 1, w - 2, h - 2, gray=bool(down))
    m.d.polygon([(m.P(x), m.P(y)), (m.P(x + 7), m.P(y)), (m.P(x), m.P(y + 7))], fill=mt['col'])
    low = mt['hp'] < 0.35 and not down
    m.rect(x, y, w, h, outline=A(RED, 230) if (down or low) else (255, 255, 255, 60), width=1.0 if (down or low) else 0.6)
    bar(m, x + 3, y + h - 5, w - 6, mt['hp'], RED if low else TEXT, 1.6, back=(0, 0, 0, 150))
    if down:
        m.glow(x, y, w, h, A(RED, 255), 8)
        m.rect(x + 1, y + h / 2 - 8, w - 2, 15, fill=(0, 0, 0, 170))
        m.text(x + w / 2, y + h / 2 + 3.5, '倒地 %d' % down, 8.0, RED, 'cn', 'ms')
    if tag:
        m.text(x + w / 2, y + h + 9, tag, 6.5, SUB, 'cn', 'ms')


def mate_dot(m, cx, cy, r, mt, assets, state):
    """圆形小头像 + 环形血量"""
    down = mt.get('down')
    m.circle(cx, cy, r + 3, fill=(8, 10, 12, 190))
    sub = assets[mt['id']]
    sw, sh = sub.size
    face = sub.crop((int(sw * 0.15), 0, int(sw * 0.85), int(sw * 0.7)))
    if down:
        face = face.convert('LA').convert('RGBA')
    m.paste_circle(face, cx, cy, r)
    m.arc(cx, cy, r + 2, 0, 360, (255, 255, 255, 40), 1.6)
    low = mt['hp'] < 0.35
    m.arc(cx, cy, r + 2, -90, -90 + 360 * mt['hp'], RED if low else TEXT, 1.6)
    if down:
        m.glow(cx - r - 3, cy - r - 3, 2 * r + 6, 2 * r + 6, A(RED, 255), 6)
        m.circle(cx, cy, r + 2.5, outline=RED, w=1.2)
        m.circle(cx, cy, r * 0.62, fill=(0, 0, 0, 200))
        m.text(cx, cy + 0.5, str(down), 9.0, RED, 'num', 'mm')
    m.circle(cx - r * 0.75, cy - r * 0.75, 2.2, fill=mt['col'])


def cmd_grid(m, x, y, w, h, key='F', touch=False, cols=4):
    rows = 4 // cols
    cw, ch = w / cols, h / rows
    for i, s in enumerate(MODES):
        cx, cy = x + (i % cols) * cw, y + (i // cols) * ch
        on = i == MODE_I
        m.rect(cx + 0.5, cy + 0.5, cw - 1, ch - 1, fill=A(CYAN, 235) if on else (0, 0, 0, 110), outline=None)
        m.text(cx + cw / 2, cy + ch / 2 + 3.2, s, 8.5, INK if on else SUB, 'cn', 'ms')
    m.cap(x, y - 4, 'COMMAND', 5.0, SUB)
    if key and not touch:
        keycap(m, x + w, y - 12, key, 6.5, TEXT, anchor='r')


# ---------------------------------------------------------------- 角落（小、淡）
def corners(m, touch=False, sonar=True):
    W, H = m.W, m.H
    m.rect(0, 0, W * 0.62, 3.2, fill=A(rgb('8cffc7'), 210))   # 经验通栏（保留）
    m.rect(W * 0.62, 0, W * 0.38, 3.2, fill=(255, 255, 255, 25))
    al = 150
    cx = W / 2
    m.cap(cx - 6, 16, 'KILLS', 4.6, A(SUB, al), 'rs')
    m.text(cx - 6, 30, '1906', 13, A(TEXT, 175), 'num', 'rs')
    m.line([(cx, 12), (cx, 32)], (255, 255, 255, 50), 0.6)
    m.cap(cx + 6, 16, 'TIME', 4.6, A(SUB, al), 'ls')
    m.text(cx + 6, 30, '09:56', 13, A(TEXT, 175), 'num', 'ls')
    m.text(cx, 41, '深蓝之树 · 威胁 VI', 6.5, A(SUB, 130), 'cn', 'ms')
    # 右上：源石锭 / 藏品 / 暂停 / 倍速
    rx = W - 12 - (8 if touch else 0)
    for lab, kk in (('1×', 'V'), ('II', 'ESC')):
        w = 18
        m.rect(rx - w, 10, w, 13, fill=(0, 0, 0, 90), outline=(255, 255, 255, 70), width=0.6)
        m.text(rx - w / 2, 16.8, lab, 6.5, A(TEXT, 190), 'num', 'mm')
        if not touch:
            m.cap(rx - w / 2, 30, kk, 4.0, A(SUB, 120), 'ms')
        rx -= w + 5
    rx -= 6
    m.cap(rx, 13, 'RELICS', 4.4, A(SUB, al), 'rs')
    m.text(rx, 25, '18', 11, A(TEXT, 175), 'num', 'rs')
    rx -= 28
    m.cap(rx, 13, 'INGOT', 4.4, A(GREEN, 170), 'rs')
    m.text(rx, 25, '24', 11, A(TEXT, 175), 'num', 'rs')
    if sonar:
        if touch:
            sx, sy, r = 46, 64, 30
        else:
            sx, sy, r = 46, H - 46, 34
        m.circle(sx, sy, r, fill=(0, 0, 0, 60), outline=(255, 255, 255, 45), w=0.6)
        m.circle(sx, sy, r * 0.5, outline=(255, 255, 255, 25), w=0.5)
        for dx, dy, c in ((10, -6, RED), (-14, 9, RED), (5, 16, CYAN), (-6, -15, RED), (18, 4, GOLD)):
            m.circle(sx + dx * r / 34, sy + dy * r / 34, 1.3, fill=A(c, 170))
        m.circle(sx, sy, 1.6, fill=TEXT)
        m.cap(sx - r, sy - r - 3, 'SONAR', 4.2, A(SUB, 110))


def status_line(m, x, y, anchor='ls'):
    m.text(x, y, STATUS, 7.0, A(GOLD, 200), 'cn', anchor)


def touch_buttons(m, which=('ult', 'dash', 'aim', 'cmd', 'info'), state='normal', at=None):
    """手机右手按键（位置可由 at 覆盖）。终结技键 = 头像环 + 充能"""
    W, H = m.W, m.H
    pos = {'dash': (W - 70, H - 82, 33), 'ult': (W - 162, H - 120, 38), 'aim': (W - 74, H - 182, 26),
           'cmd': (W - 236, H - 56, 25), 'info': (W - 40, 150, 20)}
    if at:
        pos.update(at)
    for k in which:
        cx, cy, r = pos[k]
        if k == 'ult':
            ult = 1.0 if state == 'ult' else LEADER['ult']
            if ult >= 1:
                m.circle(cx, cy, r, fill=PAPER)
                m.glow(cx - r - 4, cy - r - 4, 2 * r + 8, 2 * r + 8, A(PAPER, 200), 8)
                m.text(cx, cy + 3, '终结技', 11, INK, 'cn', 'ms')
                m.cap(cx, cy + 13, 'READY', 4.6, INK, 'ms')
            else:
                m.circle(cx, cy, r, fill=(10, 12, 14, 175), outline=(255, 255, 255, 105), w=0.8)
                m.arc(cx, cy, r + 4, 0, 360, (255, 255, 255, 30), 2.4)
                m.arc(cx, cy, r + 4, -90, -90 + 360 * ult, CYAN, 2.4)
                m.text(cx, cy + 3, '终结技', 11, TEXT, 'cn', 'ms')
                m.cap(cx, cy + 13, 'ULT %d%%' % int(ult * 100), 4.6, SUB, 'ms')
            continue
        m.circle(cx, cy, r, fill=(10, 12, 14, 175), outline=(255, 255, 255, 105), w=0.8)
        lab = {'dash': ('冲刺', 'DASH'), 'aim': ('瞄准', 'AIM'), 'cmd': (MODES[MODE_I], 'CMD'), 'info': ('属性', 'INFO')}[k]
        m.text(cx, cy + 3, lab[0], 10 if r > 24 else 8.5, CYAN if k == 'cmd' else TEXT, 'cn', 'ms')
        m.cap(cx, cy + 12, lab[1], 4.4, SUB, 'ms')
        if k == 'dash':
            for j in range(2):
                a = math.radians(90 + (j - 0.5) * 22)
                p = (cx + math.cos(a) * (r - 5), cy + math.sin(a) * (r - 5))
                m.circle(p[0], p[1], 2.0, fill=CYAN if j < LEADER['dash'] else (255, 255, 255, 45))


def joystick(m):
    cx, cy = 150, m.H - 120
    m.circle(cx, cy, 58, outline=(255, 255, 255, 40), w=0.8)
    m.circle(cx + 14, cy - 8, 20, fill=(255, 255, 255, 30), outline=(255, 255, 255, 70), w=0.8)
    m.text(cx, cy + 74, '左摇杆区', 6.5, A(SUB, 110), 'cn', 'ms')


def safe_line(m, top, label):
    """标出指挥台占高（≤ 12%）"""
    y = m.H - top
    for x in range(0, int(m.W), 10):
        m.line([(x, y), (x + 5, y)], (255, 255, 255, 34), 0.5)
    m.text(8, y - 3, label, 6.5, A(SUB, 150), 'cn', 'ls')


# ---------------------------------------------------------------- A 部署栏
def layout_A(m, assets, state, touch):
    W, H = m.W, m.H
    if not touch:
        w, h = 640, 78
        x0, y0 = (W - w) / 2, H - h - 8
        m.panel(x0, y0, w, h, 165)
        status_line(m, x0 + 2, y0 - 6)
        m.text(x0 + w - 2, y0 - 6, 'LV 27', 7.5, A(TEXT, 200), 'num', 'rs')
        badge(m, x0 + 38, y0 + 36, 25, assets, state, 'Q')
        hp_block(m, x0 + 78, y0 + 31, 150, state)
        m.line([(x0 + 244, y0 + 12), (x0 + 244, y0 + h - 12)], (255, 255, 255, 40), 0.6)
        dash_pips(m, x0 + 274, y0 + 42, state, 'SPACE')
        m.line([(x0 + 304, y0 + 12), (x0 + 304, y0 + h - 12)], (255, 255, 255, 40), 0.6)
        ms = st_mates(state)
        for i, mt in enumerate(ms):
            mate_card(m, x0 + 314 + i * 56, y0 + 7, 50, 64, mt, assets, state)
        m.line([(x0 + 486, y0 + 12), (x0 + 486, y0 + h - 12)], (255, 255, 255, 40), 0.6)
        cmd_grid(m, x0 + 496, y0 + 22, 134, 46, 'F', cols=2)
        return h + 8
    # 手机：台子居中，按键留在右手
    joystick(m)
    w, h = 470, 62
    x0, y0 = W / 2 - w / 2 - 50, H - h - 6
    m.panel(x0, y0, w, h, 165)
    status_line(m, x0 + 2, y0 - 5)
    badge(m, x0 + 31, y0 + 30, 21, assets, state, None, True)
    hp_block(m, x0 + 64, y0 + 27, 128, state, big=15)
    ms = st_mates(state)
    for i, mt in enumerate(ms):
        mate_card(m, x0 + 206 + i * 46, y0 + 5, 42, 52, mt, assets, state)
    cmd_grid(m, x0 + 350, y0 + 18, 112, 38, None, True, cols=2)
    touch_buttons(m, ('ult', 'dash', 'aim', 'info'), state)
    return h + 6


# ---------------------------------------------------------------- B 中轴弧台
def arc_panel(m, cx, ytop, halfw, depth, h, a=160):
    """顶边是一道缓弧（中间高、两端低），两端渐隐"""
    g = Image.new('RGBA', m.ov.size, (0, 0, 0, 0))
    gd = ImageDraw.Draw(g)
    pts = []
    for i in range(0, 41):
        t = i / 40 * 2 - 1
        pts.append((m.P(cx + t * halfw), m.P(ytop + depth * t * t)))
    pts += [(m.P(cx + halfw), m.P(m.H)), (m.P(cx - halfw), m.P(m.H))]
    gd.polygon(pts, fill=(PANEL[0], PANEL[1], PANEL[2], a))
    mask = Image.new('L', g.size, 0)
    md = mask.load()
    x0, x1 = int(m.P(cx - halfw)), int(m.P(cx + halfw))
    for xx in range(max(0, x0), min(g.size[0], x1)):
        e = min(xx - x0, x1 - xx) / m.P(halfw * 0.16)
        v = int(255 * min(1.0, e))
        for yy in range(int(m.P(ytop - 2)), g.size[1]):
            md[xx, yy] = v
    g.putalpha(Image.composite(g.getchannel('A'), Image.new('L', g.size, 0), mask))
    m.ov.alpha_composite(g)
    for i in range(0, 40):
        t0, t1 = i / 40 * 2 - 1, (i + 1) / 40 * 2 - 1
        al = int(80 * min(1.0, (1 - abs(t0)) / 0.16))
        m.line([(cx + t0 * halfw, ytop + depth * t0 * t0), (cx + t1 * halfw, ytop + depth * t1 * t1)], (255, 255, 255, al), 0.7)


def layout_B(m, assets, state, touch):
    W, H = m.W, m.H
    cx = W / 2 if not touch else W / 2 - 40
    k = 1.0 if not touch else 0.86
    h = 60 * k
    ytop = H - h
    arc_panel(m, cx, ytop, 270 * k, 14 * k, h, 190)
    r = 26 * k
    bcy = ytop + 6 * k
    badge(m, cx, bcy, r, assets, state, None if touch else 'Q', touch)
    # 左翼：生命（朝外长）+ 灯火
    hp_block(m, cx - r - 14 - 150 * k, ytop + 27 * k, 150 * k, state, big=15 * k, rtl=True)
    # 冲刺在徽记正下方
    dash_pips(m, cx, H - 9 * k, state, None, touch, label=False)
    if not touch:
        keycap(m, cx + 16, H - 14.5, 'SPACE', 5.6, TEXT)
    # 右翼：三名队友圆头像 + 当前指令
    ms = st_mates(state)
    for i, mt in enumerate(ms):
        mate_dot(m, cx + r + 30 * k + i * 36 * k, ytop + 26 * k, 13 * k, mt, assets, state)
    mx = cx + r + 30 * k + 3 * 36 * k - 4
    m.cap(mx, ytop + 17 * k, 'CMD', 4.6, SUB)
    m.text(mx, ytop + 32 * k, MODES[MODE_I], 11 * k, CYAN, 'cn', 'ls')
    if not touch:
        keycap(m, mx + 26, ytop + 21, 'F', 6.5, TEXT)
        m.text(mx, ytop + 45, '随行 / 部署 / 集火', 6.0, A(SUB, 130), 'cn', 'ls')
    status_line(m, cx, ytop - r - 10 * k, 'ms')
    m.text(cx - r - 10, bcy - r + 2, 'LV 27', 6.5, A(TEXT, 170), 'num', 'rs')
    if touch:
        joystick(m)
        touch_buttons(m, ('ult', 'dash', 'aim', 'cmd', 'info'), state)
    return h + r * 0.8


# ---------------------------------------------------------------- C 两翼
def layout_C(m, assets, state, touch):
    W, H = m.W, m.H
    if not touch:
        gap, h = 170, 70
        y0 = H - h - 8
        lw = 300
        lx = W / 2 - gap / 2 - lw
        rx = W / 2 + gap / 2
        m.panel(lx, y0, lw, h, 165, fade=60)
        m.panel(rx, y0, lw, h, 165, fade=60)
        # 中缝：一根细线把两翼连起来
        m.line([(W / 2 - gap / 2 + 6, H - 6), (W / 2 + gap / 2 - 6, H - 6)], (255, 255, 255, 50), 0.6)
        m.cap(W / 2, H - 10, 'TEXAS · LEADER', 4.2, A(SUB, 110), 'ms')
        # 左翼：队长（右端朝向中心：徽记靠中缝）
        badge(m, lx + lw - 34, y0 + 33, 24, assets, state, 'Q')
        hp_block(m, lx + 60, y0 + 28, 160, state, big=16, rtl=True)
        dash_pips(m, lx + 34, y0 + 40, state, 'SPACE')
        status_line(m, lx + lw, y0 - 6, 'rs')
        m.text(lx + lw - 34, y0 - 6, '', 6, SUB)
        # 右翼：编队 + 指挥（左端靠中缝）
        ms = st_mates(state)
        for i, mt in enumerate(ms):
            mate_card(m, rx + 10 + i * 50, y0 + 7, 44, 56, mt, assets, state)
        cmd_grid(m, rx + 166, y0 + 22, 120, 40, 'F', cols=2)
        m.text(rx + 2, y0 - 6, 'LV 27  ·  SQUAD 4/4  ·  BOND 2', 6.0, A(SUB, 170), 'num', 'ls')
        return h + 8
    # 手机：左翼贴在摇杆区上沿内侧，右翼并进按键簇（按键 + 队友围成一组）
    joystick(m)
    lw, h = 250, 58
    y0 = H - h - 6
    lx = W / 2 - 60 - lw
    m.panel(lx, y0, lw, h, 160, fade=40)
    badge(m, lx + lw - 30, y0 + 28, 21, assets, state, None, True)
    hp_block(m, lx + 42, y0 + 25, 150, state, big=14, rtl=True)
    status_line(m, lx + lw, y0 - 5, 'rs')
    # 右翼：按键簇外圈一道弧，三名队友头像沿弧排开；指挥键就是弧的起点
    ccx, ccy = W - 170, H - 108
    R = 92
    m.arc(ccx, ccy, R, 150, 285, (255, 255, 255, 45), 0.8)
    ms = st_mates(state)
    for i, mt in enumerate(ms):
        a = math.radians(205 + i * 33)
        mate_dot(m, ccx + math.cos(a) * R, ccy + math.sin(a) * R, 15, mt, assets, state)
    a = math.radians(163)
    touch_buttons(m, ('ult', 'dash', 'aim', 'cmd', 'info'), state,
                  at={'cmd': (ccx + math.cos(a) * R, ccy + math.sin(a) * R, 24),
                      'ult': (ccx, ccy, 38), 'dash': (W - 66, H - 70, 33), 'aim': (W - 62, H - 176, 26)})
    return h + 6


LAYOUTS = {'A': layout_A, 'B': layout_B, 'C': layout_C}


def render(base, s, key, state, touch, assets):
    m = M(base, s)
    corners(m, touch)
    used = LAYOUTS[key](m, assets, state, touch)
    pct = used / m.H * 100
    safe_line(m, used, '指挥台占高 %.1f%%' % pct)
    return m.done(), pct


def main():
    global BADGE_BOX
    os.makedirs(OUT, exist_ok=True)
    import json
    cfg = json.load(open(os.path.join(BASE, 'crops.json'), encoding='utf-8'))
    CARD_BOXES.update({k: tuple(v) for k, v in cfg['cards'].items()})
    BADGE_BOX = tuple(cfg['badge'])
    EXTRA.update(cfg.get('extra', {}))
    assets = load_assets()
    pc = Image.open(os.path.join(BASE, 'pc.png'))
    ph = Image.open(os.path.join(BASE, 'phone.png'))
    info = {}
    for k in 'ABC':
        im, p1 = render(pc, 1.5, k, 'normal', False, assets)
        im.save(os.path.join(OUT, '%s_pc.png' % k))
        im, p2 = render(ph, 2.0, k, 'normal', True, assets)
        im.save(os.path.join(OUT, '%s_phone.png' % k))
        info[k] = (p1, p2)
        # 状态放大：电脑底部 1/4 裁出，四态并排成 2×2
        tiles = []
        for stt in ('normal', 'hit', 'ult', 'down'):
            im, _ = render(pc, 1.5, k, stt, False, assets)
            tiles.append(im.crop((330, 900, 1590, 1080)))
        tw, th = tiles[0].size
        sheet = Image.new('RGB', (tw, th * 4 + 3 * 6), (20, 22, 26))
        lab = {'normal': '常态', 'hit': '掉血：生命数字与细条转洋红 + 掉落残影', 'ult': '终结技充满：头像环反白 + READY',
               'down': '队友倒地：头像灰 + 洋红框闪 + 读秒'}
        d = ImageDraw.Draw(sheet)
        f = ImageFont.truetype(os.path.join(FONTS, 'ui.ttf'), 22)
        for i, (t, stt) in enumerate(zip(tiles, ('normal', 'hit', 'ult', 'down'))):
            sheet.paste(t, (0, i * (th + 6)))
            d.text((14, i * (th + 6) + 10), lab[stt], font=f, fill=(255, 220, 120))
        sheet.save(os.path.join(OUT, '%s_states.png' % k))
    print(json.dumps(info))
    build_page(info)



NOTES = {
    'A': ('部署栏 · 横条', [
        '放了：队长徽记（头像 + 终结技充能环，角上 Q）、生命 / 灯火、冲刺两格（SPACE）、三张部署卡式队友（血条 + 倒地读秒）、指挥四格（F）。',
        '一条横台，约屏宽 50%；最像原作底部的干员部署栏。',
        '优点：所有信息一眼看全，指挥四格常显；手机上按键留在右手，台子不碰拇指，改动最小。',
        '缺点：横向长，看队友要往右扫；三张立绘卡在后期弹幕下偏「重」。',
    ]),
    'B': ('中轴弧台 · 极简', [
        '放了：中间队长徽记（终结技环 + Q），左翼生命 / 灯火从徽记往外长，右翼三颗圆头像（环形血量）+ 当前指令一个词（F），冲刺两格挂在徽记正下方。',
        '顶边是一道缓弧，两端渐隐；最窄，约屏宽 40%。',
        '优点：视线集中在角色正下方一小块，挡得最少。',
        '缺点：看不到队友名字和精确血量；指挥只显示当前模式，按 F 才弹出圆盘；手机上徽记环和终结技键重复显示充能。',
    ]),
    'C': ('两翼 · 中间留空', [
        '放了：左翼「队长」＝冲刺、生命 / 灯火、头像徽记（徽记靠中缝）；右翼「编队」＝三张队友卡 + 指挥四格。两翼之间留 170 像素空位给战斗与掉落物。',
        '手机：右翼并进按键簇，三颗队友头像沿终结技键外圈排开，指挥键是这道弧的起点。',
        '优点：自己和队伍分两边，正下方不挡；手机上队友就在拇指旁边。',
        '缺点：总宽最大（约屏宽 60%），两翼要左右扫；手机按键簇变密，误触风险比 A 高。',
    ]),
}


def build_page(info):
    cols = []
    for k in 'ABC':
        title, lines = NOTES[k]
        p1, p2 = info[k]
        li = ''.join('<li>%s</li>' % t for t in lines)
        cols.append(f"""<section class="col"><h2><b>{k}</b> {title}</h2>
<p class="meta">占高：电脑 {p1:.1f}% · 手机 {p2:.1f}%（含底边距）</p>
<ul>{li}</ul>
<figure><img src="{k}_pc.png"><figcaption>电脑 16:9（1920×1080）</figcaption></figure>
<figure><img src="{k}_phone.png"><figcaption>手机横屏（2340×1080）</figcaption></figure>
<figure><img src="{k}_states.png"><figcaption>闪一下：常态 / 掉血 / 终结技充满 / 队友倒地（电脑底部放大）</figcaption></figure>
</section>""")
    html = f"""<!DOCTYPE html><html lang="zh-CN"><head><meta charset="utf-8"><title>局内指挥台 · 三版式（11-05）</title>
<style>
body{{margin:0;background:#0d1013;color:#e9e7e1;font-family:"Noto Sans SC","Microsoft YaHei",sans-serif;font-size:14px;line-height:1.6}}
header{{padding:20px 28px 8px}} h1{{font-size:22px;margin:0 0 6px}} header p{{margin:2px 0;color:#9aa3ad;max-width:1400px}}
.wrap{{display:grid;grid-template-columns:repeat(3,1fr);gap:18px;padding:12px 28px 28px}}
.col{{background:#14181c;border-top:2px solid #36e2dc;padding:12px 14px}} h2{{font-size:17px;margin:0}} h2 b{{color:#36e2dc;font-family:Montserrat,sans-serif}}
.meta{{color:#9aa3ad;margin:2px 0 6px;font-size:12px}} ul{{padding-left:18px;margin:0 0 10px}} li{{margin:2px 0}}
figure{{margin:0 0 12px}} img{{width:100%;display:block;cursor:zoom-in}} figcaption{{color:#9aa3ad;font-size:12px}}
.now{{padding:0 28px 28px;display:grid;grid-template-columns:1fr 1fr;gap:18px}}
img.big{{position:fixed;inset:0;margin:auto;width:auto;max-width:98vw;max-height:98vh;z-index:9;box-shadow:0 0 0 100vmax rgba(0,0,0,.85);cursor:zoom-out}}
</style></head><body>
<header><h1>局内指挥台 · 三版式</h1>
<p>把队长生命、终结技充能、冲刺、灯火、队友（头像 + 血量 + 倒地）、指挥四格收进正下方一台。按键提示标在图标角上（Q / SPACE / F），单独的提示条删掉；「左键 瞄准」只留在开局指南里。</p>
<p>角上只留偶尔看的：顶部中央击杀 / 时间，右上源石锭 / 藏品数 / 暂停 / 倍速，左下（手机左上）声呐，都缩小、压到约 60% 不透明。</p>
<p>镜头建议：台子占底部 11–13%，建议镜头中心上移屏高 4%（电脑 1280×720 逻辑下 28，手机 1170×540 下 22），队长脚下到台子上沿仍有约 35% 屏高。</p>
<p>闪一下的规则：掉血时生命数字和细条转洋红并留残影 0.4 秒；终结技充满时徽记环反白 + READY；队友倒地时那张卡灰掉、洋红框闪 + 读秒。不弹文字提示。</p>
<p>底图：同一帧实机画面（--nohud，为了不占本机只用了现成的前期帧，敌人偏少），头像从带界面的同帧截图裁出；示意图用游戏字体与 ui.gd 颜色。脚本 tools/probes/hud_console_1105.py。</p></header>
<div class="wrap">{''.join(cols)}</div>
<header><h1 style="font-size:17px">对照：现在的 HUD v2</h1></header>
<div class="now"><figure><img src="now_pc.png"><figcaption>电脑</figcaption></figure><figure><img src="now_phone.png"><figcaption>手机</figcaption></figure></div>
<script>document.querySelectorAll('img').forEach(i=>i.onclick=()=>i.classList.toggle('big'))</script>
</body></html>"""
    open(os.path.join(OUT, 'index.html'), 'w', encoding='utf-8').write(html)
    # 总览 PNG：3 行（A/B/C）× 2 列（电脑 / 手机）
    cw = 1100
    rows = []
    f = ImageFont.truetype(os.path.join(FONTS, 'ui.ttf'), 30)
    for k in 'ABC':
        a = Image.open(os.path.join(OUT, '%s_pc.png' % k))
        b = Image.open(os.path.join(OUT, '%s_phone.png' % k))
        a = a.resize((cw, int(a.size[1] * cw / a.size[0])), Image.LANCZOS)
        bw = int(b.size[0] * a.size[1] / b.size[1])
        b = b.resize((bw, a.size[1]), Image.LANCZOS)
        rows.append((k, a, b))
    W = 20 + cw + 20 + rows[0][2].size[0] + 20
    Hh = sum(r[1].size[1] + 56 for r in rows) + 20
    ov = Image.new('RGB', (W, Hh), (13, 16, 19))
    d = ImageDraw.Draw(ov)
    y = 10
    for k, a, b in rows:
        d.text((20, y + 8), '%s  %s' % (k, NOTES[k][0]), font=f, fill=(54, 226, 220))
        y += 50
        ov.paste(a, (20, y))
        ov.paste(b, (40 + cw, y))
        y += a.size[1] + 6
    ov.save(os.path.join(OUT, 'overview.png'))


if __name__ == '__main__':
    main()
