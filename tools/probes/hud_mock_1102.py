"""docs/222 局内 HUD 方向稿：在同一帧无 HUD 画面上画三个方向的静态效果稿（电脑 1920×1080 + 手机 1170×540）、
指南卡样式、现状盘点标注图和对比总览。素材（头像徽记、立绘卡头像、技能 / 藏品图标）从同一帧带 HUD 的截图上裁。
用法：python hud_mock.py <worktree> <输出目录>"""
import os, sys
from PIL import Image, ImageDraw, ImageFont, ImageFilter

WT, OUT = sys.argv[1], sys.argv[2]
os.makedirs(OUT, exist_ok=True)
LA = os.path.join(WT, 'build', 'late_audit')
FONT = os.path.join(WT, 'game', 'fonts', 'ui.ttf')
_fc = {}
from fontTools.ttLib import TTFont as _TT
_CM = _TT(FONT).getBestCmap()
FB = 'C:/Windows/Fonts/msyh.ttc'
_fb = {}


def FBF(sz):
    sz = int(round(sz))
    if sz not in _fb:
        _fb[sz] = ImageFont.truetype(FB, sz)
    return _fb[sz]


def _segs(s):
    out = []
    for ch in s:
        ok = ord(ch) in _CM
        if out and out[-1][1] == ok:
            out[-1][0] += ch
        else:
            out.append([ch, ok])
    return out


def F(sz):
    sz = int(round(sz))
    if sz not in _fc:
        _fc[sz] = ImageFont.truetype(FONT, sz)
    return _fc[sz]


def C(r, g, b, a=1.0):
    return (int(r * 255), int(g * 255), int(b * 255), int(a * 255))


# ui.gd 语义色
BG = C(0.063, 0.071, 0.086, 0.86)
BG2 = C(0.094, 0.106, 0.125, 0.9)
CYAN = C(0.212, 0.886, 0.863)
CYAN_DIM = C(0.36, 0.62, 0.64)
GOLD = C(0.957, 0.753, 0.306)
RED = C(1.0, 0.239, 0.545)
VIOLET = C(0.486, 0.42, 1.0)
GREEN = C(0.184, 0.827, 0.627)
TEXT = C(0.949, 0.957, 0.961)
SUB = C(0.604, 0.639, 0.678)
STEEL = C(0.494, 0.596, 0.722)
TAB_HP = C(0.09, 0.56, 0.65)
TAB_LAMP = C(0.72, 0.53, 0.04)
EDGE = C(1, 1, 1, 0.24)
EDGE_DIM = C(1, 1, 1, 0.12)
B_ACC = (0x3C, 0xC8, 0xE4, 255)
CLS = {'先': C(0.95, 0.75, 0.3), '狙': C(1.0, 0.45, 0.4), '近': C(0.55, 0.75, 1.0), '医': C(0.5, 0.95, 0.6), '特': C(0.75, 0.55, 1.0)}


class M:
    """一张效果稿：底图 + RGBA 叠层；s = 设计单位 → 像素"""

    def __init__(self, bg: Image.Image, s: float, fk: float = 1.0):
        self.im = bg.convert('RGBA')
        self.ov = Image.new('RGBA', self.im.size, (0, 0, 0, 0))
        self.d = ImageDraw.Draw(self.ov)
        self.s = s
        self.fk = fk   # 字号系数（手机）
        self.W, self.H = self.im.size[0] / s, self.im.size[1] / s

    def P(self, v):
        return int(round(v * self.s))

    def R(self, x, y, w, h):
        return [self.P(x), self.P(y), self.P(x + w), self.P(y + h)]

    def rect(self, x, y, w, h, fill, outline=None, width=1):
        self.d.rectangle(self.R(x, y, w, h), fill=fill, outline=outline, width=width)

    def panel(self, x, y, w, h, acc=CYAN, a=0.86, edge=True):
        # 上亮下暗的炭灰平面 + 顶部一线高光 + 1px 细边 + 左上一小段强调色（docs/37 §3 面板）
        top, bot = (0.094, 0.106, 0.125), (0.05, 0.057, 0.07)
        x0, y0, x1, y1 = self.R(x, y, w, h)
        for yy in range(y0, y1):
            k = (yy - y0) / max(1, y1 - y0 - 1)
            c = tuple(int((top[i] + (bot[i] - top[i]) * k) * 255) for i in range(3)) + (int(a * 255),)
            self.d.line([(x0, yy), (x1 - 1, yy)], fill=c)
        self.d.line([(x0, y0), (x1 - 1, y0)], fill=C(1, 1, 1, 0.22))
        if edge:
            self.d.rectangle([x0, y0, x1 - 1, y1 - 1], outline=EDGE_DIM, width=1)
        if acc is not None:
            self.d.rectangle([x0, y0, x0 + self.P(18), y0 + max(1, self.P(2)) - 1], fill=acc)

    def _len(self, s, px):
        return sum(self.d.textlength(t, font=(F(px) if ok else FBF(px))) for t, ok in _segs(s))

    def text(self, x, y, s, sz, col=TEXT, anchor='ls', bold=False):
        px = sz * self.s * self.fk
        L = self._len(s, px)
        x0 = self.P(x) - (L if anchor[0] == 'r' else (L / 2 if anchor[0] == 'm' else 0))
        va = 'l' + anchor[1]
        for dx in ((0, 1) if bold else (0,)):
            cx = x0 + dx
            for t, ok in _segs(s):
                f = F(px) if ok else FBF(px)
                self.d.text((cx, self.P(y)), t, font=f, fill=col, anchor=va)
                cx += self.d.textlength(t, font=f)
        return L / self.s

    def tw(self, s, sz):
        return self._len(s, sz * self.s * self.fk) / self.s

    def en(self, x, y, s, sz, col=CYAN, sp=3.0):
        f = F(sz * self.s * self.fk)
        cx = self.P(x)
        for ch in s:
            self.d.text((cx, self.P(y)), ch, font=f, fill=col, anchor='ls')
            cx += self.d.textlength(ch, font=f) + sp * self.s
        return (cx - self.P(x)) / self.s

    def bar(self, x, y, w, h, frac, col, slot=C(0, 0, 0, 0.55), ticks=0):
        self.rect(x, y, w, h, slot)
        self.rect(x, y, w * frac, h, col)
        self.rect(x, y, w * frac, max(1 / self.s, h * 0.25), C(1, 1, 1, 0.25))
        for t in range(1, ticks):
            self.rect(x + w * t / ticks, y, 1 / self.s, h, C(0, 0, 0, 0.5))

    def tab(self, x, y, s, col, sz=11):
        w = self.tw(s, sz) + 10
        self.rect(x, y, w, sz + 6, col)
        self.text(x + 5, y + sz + 2, s, sz, TEXT)
        return w

    def chip(self, x, y, s, col, sz=11):
        w = self.tw(s, sz) + 16
        self.rect(x, y, w, sz + 8, C(0.03, 0.035, 0.045, 0.8))
        self.rect(x, y, 3, sz + 8, col)
        self.text(x + 9, y + sz + 2.5, s, sz, tuple(int(col[i] * 0.7 + TEXT[i] * 0.3) for i in range(3)) + (255,))
        return w

    def keycap(self, x, y, s, sz=10, col=TEXT):
        w = self.tw(s, sz) + 10
        self.rect(x, y, w, sz + 8, C(0, 0, 0, 0.45), outline=C(1, 1, 1, 0.45), width=1)
        self.text(x + 5, y + sz + 3, s, sz, col)
        return w

    def pill(self, x, y, s, col, sz=12, fill=None, key=''):
        w = self.tw(s, sz) + 22 + (self.tw(key, 10) + 14 if key else 0)
        h = sz + 12
        x0, y0, x1, y1 = self.R(x, y, w, h)
        self.d.rounded_rectangle([x0, y0, x1, y1], radius=self.P(h / 2), fill=fill or C(0.03, 0.035, 0.045, 0.82), outline=col, width=max(1, self.P(1.2)))
        self.text(x + 11, y + sz + 4.5, s, sz, col)
        if key:
            self.keycap(x + 11 + self.tw(s, sz) + 6, y + 3, key, 10, SUB)
        return w

    def diamond(self, cx, cy, r, col, edge=None):
        p = [(self.P(cx), self.P(cy - r)), (self.P(cx + r), self.P(cy)), (self.P(cx), self.P(cy + r)), (self.P(cx - r), self.P(cy))]
        self.d.polygon(p, fill=col, outline=edge)

    def img(self, src: Image.Image, x, y, w, h):
        t = src.resize((max(1, self.P(w)), max(1, self.P(h))), Image.NEAREST).convert('RGBA')
        self.ov.alpha_composite(t, (self.P(x), self.P(y)))

    def note(self, x, y, s, col=GOLD):
        # 稿子上的注释（不是界面元素）：黄底黑字小签
        w = self.tw(s, 11) + 12
        self.rect(x, y, w, 19, col)
        self.text(x + 6, y + 14, s, 11, (12, 12, 12, 255))

    def done(self, path, title=None):
        im = Image.alpha_composite(self.im, self.ov)
        if title:
            hb = 48 if im.size[0] > 1500 else 36
            out = Image.new('RGBA', (im.size[0], im.size[1] + hb), (12, 14, 18, 255))
            out.alpha_composite(im, (0, hb))
            d = ImageDraw.Draw(out)
            d.text((14, hb / 2), title, font=FBF(26 if hb > 40 else 20), fill=(255, 236, 170, 255), anchor='lm')
            im = out
        im.convert('RGB').save(path)
        return im


# ---------------------------------------------------------------- 素材
DESK_FULL = Image.open(os.path.join(LA, 'dA_fin', 'rec_00900.png')).convert('RGBA')
DESK_BG = Image.open(os.path.join(LA, 'dA_fin_nh', 'rec_00900.png')).convert('RGBA')
PH_FULL = Image.open(os.path.join(LA, 'pA_fin', 'rec_00900.png')).convert('RGBA')
PH_BG = Image.open(os.path.join(LA, 'pA_fin_nh', 'rec_00900.png')).convert('RGBA')
BADGE = DESK_FULL.crop((14, 6, 108, 118))                     # B′ 徽记（头像 + 环 + Q）
CARD_X = [1348, 1489, 1630, 1771]
PORTRAIT = [DESK_FULL.crop((x + 8, 930, x + 118, 1022)) for x in CARD_X]   # 立绘卡头像段
HEAD = [DESK_FULL.crop((x + 30, 930, x + 96, 980)) for x in CARD_X]
SKILL = [[DESK_FULL.crop((CARD_X[i] + k * 45, 856, CARD_X[i] + k * 45 + 36, 892)) for k in range(3)] for i in range(4)]
RELIC = [DESK_FULL.crop((1340 + k * 57, 64, 1388 + k * 57, 108)) for k in range(8)]
MINIMAP = DESK_FULL.crop((30, 800, 275, 1048))
OPS = [('德克萨斯', '先', 1.0), ('能天使', '狙', 0.92), ('拉普兰德', '近', 0.64), ('流明', '医', 1.0)]


# ---------------------------------------------------------------- 共用块（顶部中央战斗顶栏 + Boss 条，各方向都不动）
def top_center(m: M, y0=10, boss=True, compact=False):
    W = m.W
    cx = W / 2
    m.rect(cx - 150, y0, 300, 40, C(0.03, 0.035, 0.045, 0.72))
    m.d.ellipse(m.R(cx - 132, y0 + 12, 16, 16), outline=C(1, 0.55, 0.2), width=max(1, m.P(2)))
    m.d.ellipse(m.R(cx - 127, y0 + 17, 6, 6), fill=C(1, 0.55, 0.2))
    m.text(cx - 104, y0 + 31, '1910', 24, TEXT, bold=True)
    m.text(cx - 46, y0 + 31, '击杀', 11, SUB)
    m.rect(cx + 6, y0 + 10, 1, 20, EDGE)
    m.d.ellipse(m.R(cx + 18, y0 + 13, 15, 15), outline=TEXT, width=max(1, m.P(1.6)))
    m.text(cx + 40, y0 + 31, '10:35', 24, TEXT, bold=True)
    if not compact:
        m.text(cx - 62, y0 + 64, '◆ 深蓝之树', 14, TEXT)
        m.en(cx + 18, y0 + 63, 'BLUE TREE', 9, SUB, 3)
        m.text(cx, y0 + 82, '威胁 VI', 10, SUB, anchor='ms')
    if boss:
        by = y0 + (100 if not compact else 56)
        m.text(cx, by - 4, '偏执泡影', 14, TEXT, anchor='ms')
        m.rect(cx - 270, by + 2, 540, 9, C(0, 0, 0, 0.6), outline=C(0.66, 0.52, 1.0, 0.7))
        m.rect(cx - 269, by + 3, 538 * 0.55, 7, C(0.72, 0.6, 1.0))
        m.text(cx + 270, by - 4, '阶段护盾 · 时限到后破碎', 10, GOLD, anchor='rs')


def key_hints(m: M, y=None):
    y = m.H - 30 if y is None else y
    cx = m.W / 2
    x = cx - 150
    x += m.keycap(x, y, '左键', 10, GOLD) + 6
    m.text(x, y + 13, '瞄准', 12, TEXT)
    x = cx + 10
    x += m.keycap(x, y, 'SPACE', 10, CYAN) + 6
    m.text(x, y + 13, '冲刺 ×2', 12, TEXT)


def minimap(m: M, x, y, sz):
    m.img(MINIMAP, x, y, sz, sz)


def phone_buttons(m: M, cmd='突击', speed=True, pause=True):
    """触屏右侧按键列（位置同现状 touch.gd 缺省布局，各方向都不动）"""
    W = m.W
    for (dx, cy, r, lab) in [b for b in [(80, 106, 18, cmd), (30, 106, 18, 'Ⅱ'), (150, 146, 28, '终结技'), (30, 152, 18, '≡'), (150, 202, 18, '◎'), (82, 202, 24, '冲刺')] if pause or b[3] != 'Ⅱ']:
        cx = W - dx
        m.d.ellipse(m.R(cx - r, cy - r, 2 * r, 2 * r), outline=CYAN, width=max(1, m.P(1.6)), fill=C(0.03, 0.035, 0.045, 0.6))
        m.text(cx, cy + 4, lab, 11 if r < 26 else 12, TEXT, anchor='ms')
    if speed:
        m.text(W - 30, 64, '1×', 14, TEXT, anchor='ms', bold=True)
        m.text(W - 30, 78, '倍速', 9, SUB, anchor='ms')


def relic_strip(m: M, x, y, n_show=4, total=15, align_right=True):
    """藏品收起：最近 n 件 + 「藏品 15 ▸」（悬停 / 点开展开整栏）"""
    w = 70 + n_show * 30
    if align_right:
        x = x - w
    m.panel(x, y, w, 34, acc=None)
    m.text(x + 10, y + 22, '藏品', 12, TEXT)
    m.text(x + 40, y + 22, str(total), 13, TEXT, bold=True)
    for k in range(n_show):
        m.img(RELIC[k], x + 66 + k * 30, y + 5, 25, 24)
    m.text(x + w - 6, y + 22, '▸', 11, SUB, anchor='rs')
    return x


def guide_card(m: M, x, y, w, style='A', step=2, total=6):
    """统一后的指南卡：炭灰面板 + 左侧 3px 青条 + 节点标签条（左段青底压缩英文、右段暗底中文标题）+ 步骤点 + 实时演示框"""
    h = 112
    m.panel(x, y, w, h, acc=None)
    m.rect(x, y, 3, h, CYAN)
    # 节点标签条
    tw = m.en(-999, -999, 'TUTORIAL', 9, CYAN)  # 量宽
    m.rect(x + 12, y + 10, 84, 18, CYAN)
    m.en(x + 18, y + 23, 'TUTORIAL', 9, C(0.03, 0.06, 0.08), 2.4)
    m.rect(x + 96, y + 10, 120, 18, C(0, 0, 0, 0.55))
    m.text(x + 104, y + 24, '经验与升级', 12, TEXT, bold=True)
    # 步骤点
    for k in range(total):
        cx = x + w - 18 - (total - 1 - k) * 12
        if k < step - 1:
            m.diamond(cx, y + 19, 3.5, CYAN)
        elif k == step - 1:
            m.diamond(cx, y + 19, 4.5, TEXT, edge=CYAN)
        else:
            m.diamond(cx, y + 19, 3.0, C(1, 1, 1, 0.18))
    # 演示框
    m.rect(x + 12, y + 36, 110, 64, C(0.02, 0.03, 0.04, 0.85), outline=EDGE_DIM)
    m.img(HEAD[0], x + 48, y + 52, 26, 22)
    for k, (dx, dy) in enumerate([(22, 18), (80, 14), (92, 44), (30, 48)]):
        m.diamond(x + 12 + dx, y + 36 + dy, 3, C(0.55, 1.0, 0.78))
    m.text(x + 132, y + 54, '拾取经验结晶，经验条满了就升级，', 12, TEXT)
    m.text(x + 132, y + 72, '三张卡里选一张。', 12, TEXT)
    m.diamond(x + 136, y + 90, 3, CYAN)
    m.text(x + 144, y + 94, '捡起附近的经验结晶', 11, CYAN)
    return h


# ================================================================ 现状盘点（标注）
def inventory():
    m = M(DESK_FULL, 1.5)
    marks = [
        (1, (14, 8, 230, 112), '队长：等级 + B′ 徽记 + 生命 / 灯火'),
        (2, (70, 74, 160, 40), '队友血条（名单）'),
        (3, (16, 128, 300, 44), '灯火档 + 状态标签'),
        (4, (500, 10, 280, 52), '击杀 | 时间 + 海域 / 威胁'),
        (5, (360, 76, 560, 46), 'Boss 名 + 血条'),
        (6, (884, 12, 316, 108), '藏品栏 16 格'),
        (7, (1222, 10, 48, 112), '暂停 / 倍速'),
        (8, (1030, 486, 240, 50), '指挥模式 + 作战时限'),
        (9, (1010, 528, 260, 30), '编队人数 + 源石锭'),
        (10, (896, 566, 370, 30), '技能格 12 枚'),
        (11, (896, 598, 370, 106), '编队卡 4 张'),
        (12, (18, 530, 170, 170), '声呐'),
        (13, (470, 672, 240, 34), '瞄准 / 冲刺按键牌'),
    ]
    for n, (x, y, w, h), lab in marks:
        m.rect(x, y, w, h, None, outline=GOLD, width=2)
        m.rect(x, y, 22, 18, GOLD)
        m.text(x + 11, y + 14, str(n), 12, (10, 10, 10, 255), anchor='ms', bold=True)
    m.done(os.path.join(OUT, '00_inventory_desktop.png'), '现状（10:35，c73d2ff86）：13 块常驻元素')


# ================================================================ 方向 A：四角收拢
def dir_a_desk():
    m = M(DESK_BG, 1.5)
    # 左上：B′ 徽记 + 生命 / 灯火上下叠（队友不在这里）
    m.img(BADGE, 14, 12, 62, 64)
    m.tab(84, 14, '生命值', TAB_HP)
    m.text(140, 30, '195', 20, TEXT, bold=True)
    m.text(177, 30, '/ 195', 11, SUB)
    m.bar(84, 36, 190, 6, 1.0, CYAN)
    m.tab(84, 48, '灯火', TAB_LAMP)
    m.text(128, 64, '100', 16, TEXT, bold=True)
    m.bar(84, 68, 190, 5, 1.0, GOLD, ticks=10)
    x = 16 + m.chip(16, 84, 'LIGHT 灯火通明 · 技力回复 +30%', GOLD) + 6
    m.chip(x, 84, '护盾 ×1', CYAN)
    x = 16 + m.chip(16, 106, '攻速 +70%', GOLD) + 6
    m.chip(x, 106, '认知负担 · 攻速 −10%', C(0.85, 0.55, 1.0))
    top_center(m)
    # 右上：一个信息区——藏品收起 + 暂停 / 倍速成对
    rx = relic_strip(m, m.W - 92, 12)
    m.panel(m.W - 84, 12, 30, 34, acc=None)
    m.text(m.W - 69, 34, 'Ⅱ', 13, TEXT, anchor='ms')
    m.panel(m.W - 50, 12, 34, 34, acc=None)
    m.text(m.W - 33, 34, '1×', 13, TEXT, anchor='ms', bold=True)
    m.text(m.W - 33, 58, '倍速 V', 9, SUB, anchor='ms')
    m.note(rx, 52, '藏品收成一条：最近 4 件 + 总数，悬停 / Tab 展开整栏')
    # 右下：编队面板（标题栏 = 指挥模式 + 编队 / 羁绊 / 源石锭；卡内 = 头像 + 生命条 + 3 枚技能点）
    W, H = m.W, m.H
    pw, px, py = 4 * 92 + 10, W - 16 - (4 * 92 + 10), H - 16 - 138
    m.panel(px, py, pw, 138, acc=CYAN)
    hx = px + 10
    hx += m.pill(hx, py + 7, '指挥 · 随行', CYAN, 12, key='F') + 8
    m.text(px + pw - 10, py + 24, '编队 4/4 · 羁绊 2', 11, SUB, anchor='rs')
    m.bar(px + 10, py + 33, 120, 3, 0.35, CYAN, slot=C(1, 1, 1, 0.1))
    m.text(px + 136, py + 37, '作战时限', 9, SUB)
    for i, (nm, cls, hp) in enumerate(OPS):
        cx0 = px + 8 + i * 92
        cy0 = py + 44
        m.rect(cx0, cy0, 86, 86, C(0.08, 0.09, 0.11, 0.95), outline=(VIOLET if i == 0 else C(1, 1, 1, 0.16)), width=1)
        m.img(PORTRAIT[i], cx0 + 4, cy0 + 4, 78, 58)
        m.rect(cx0, cy0, 16, 16, C(0, 0, 0, 0.72))
        m.text(cx0 + 8, cy0 + 12, cls, 10, TEXT, anchor='ms')
        for k in range(3):
            m.img(SKILL[i][k], cx0 + 86 - 3 - (3 - k) * 17, cy0 + 3, 15, 15)
        m.rect(cx0, cy0 + 60, 86, 26, C(0, 0, 0, 0.6))
        m.text(cx0 + 43, cy0 + 73, nm, 10, TEXT, anchor='ms')
        if i > 0:
            m.bar(cx0 + 4, cy0 + 78, 78, 4, hp, GREEN if hp > 0.5 else GOLD)
        if i in (1, 2):
            m.diamond(cx0 + 79, cy0 + 70, 3, GOLD)
        if i == 0:
            m.rect(cx0 + 20, cy0 - 7, 46, 12, VIOLET)
            m.text(cx0 + 43, cy0 + 3, '队长', 9, TEXT, anchor='ms')
    # 源石锭并到编队面板左侧
    m.panel(px - 86, H - 16 - 38, 80, 38, acc=GREEN)
    m.text(px - 76, H - 24, '0', 22, TEXT, bold=True)
    m.text(px - 50, H - 24, '源石锭', 10, SUB)
    minimap(m, 16, H - 16 - 150, 150)
    key_hints(m)
    m.note(px, py - 24, '技能格并进卡角、队友生命条进卡底；左上不再列队友')
    return m.done(os.path.join(OUT, 'A_desktop.png'), '方向 A · 四角收拢（电脑 1920×1080）')


def dir_a_phone():
    m = M(PH_BG, 1.25, 1.0)
    m.img(PH_FULL.crop((12, 12, 72, 70)), 10, 10, 54, 52)
    m.tab(70, 10, '生命值', TAB_HP, 10)
    m.text(124, 28, '169', 18, TEXT, bold=True)
    m.bar(70, 33, 150, 5, 1.0, CYAN)
    m.tab(70, 42, '灯火', TAB_LAMP, 10)
    m.bar(108, 48, 112, 4, 0.95, GOLD, ticks=10)
    m.chip(12, 70, '护盾 ×1', CYAN, 10)
    m.chip(76, 70, '+2', SUB, 10)
    top_center(m, 6, compact=True)
    relic_strip(m, m.W - 120, 8, n_show=3, total=16)
    # 右侧按键列（照旧）
    phone_buttons(m)
    # 右下编队：一行收起卡（头像 + 生命条），标题栏同电脑
    px, py, pw = m.W - 12 - 4 * 74, m.H - 12 - 92, 4 * 74
    m.panel(px, py, pw, 92, acc=CYAN)
    m.pill(px + 8, py + 6, '指挥 · 随行', CYAN, 11)
    m.text(px + pw - 8, py + 22, '编队 4/4 · 羁绊 2', 10, SUB, anchor='rs')
    for i, (nm, cls, hp) in enumerate(OPS):
        cx0, cy0 = px + 6 + i * 74, py + 34
        m.rect(cx0, cy0, 68, 52, C(0.08, 0.09, 0.11, 0.95), outline=(VIOLET if i == 0 else C(1, 1, 1, 0.16)))
        m.img(HEAD[i], cx0 + 6, cy0 + 2, 56, 36)
        for k in range(3):
            m.rect(cx0 + 4 + k * 8, cy0 + 4, 6, 6, [GOLD, CYAN, SUB][k])
        m.text(cx0 + 34, cy0 + 48, nm[:3], 9, TEXT, anchor='ms')
        if i:
            m.bar(cx0 + 4, cy0 + 40, 60, 3, hp, GREEN)
    m.panel(px - 74, m.H - 12 - 30, 68, 30, acc=GREEN)
    m.text(px - 66, m.H - 18, '0 源石锭', 11, TEXT)
    minimap(m, 10, m.H - 10 - 96, 96)
    return m.done(os.path.join(OUT, 'A_phone.png'), '方向 A · 手机横屏')


# ================================================================ 方向 B：底部指挥台
def console(m: M, cx, y, w, phone=False):
    """底部中央指挥台：中间 B′ 徽记，左边生命 / 灯火，右边三名队友小卡；台面上沿一排状态胶囊（指挥 / 倍速 / 编队羁绊）"""
    h = 78
    x = cx - w / 2
    m.panel(x, y, w, h, acc=None)
    m.rect(x, y, w, 2, C(0.212, 0.886, 0.863, 0.55))
    # 上沿胶囊
    px = x + 10
    px += m.pill(px, y - 30, '指挥 · 突击 · 集火', CYAN, 11, key='' if phone else 'F') + 6
    px += m.pill(px, y - 30, '倍速 1×', STEEL, 11, key='' if phone else 'V') + 6
    m.pill(px, y - 30, '编队 4/4 · 羁绊 2', SUB, 11)
    m.bar(x + w - 150, y - 18, 140, 3, 0.35, CYAN, slot=C(1, 1, 1, 0.12))
    m.text(x + w - 150, y - 23, '作战时限', 9, SUB)
    # 中间徽记
    bs = 62 if not phone else 52
    m.img(BADGE, cx - bs / 2, y + (h - bs) / 2 - 2, bs, bs + 2)
    # 左：生命 / 灯火
    lw = w / 2 - bs / 2 - 26
    lx = x + 12
    m.tab(lx, y + 10, '生命值', TAB_HP, 10)
    m.text(lx + 50, y + 25, '195 / 195', 14, TEXT, bold=True)
    m.bar(lx, y + 32, lw, 7, 1.0, CYAN)
    m.tab(lx, y + 45, '灯火', TAB_LAMP, 10)
    m.text(lx + 38, y + 59, '100', 12, TEXT)
    m.bar(lx, y + 64, lw, 5, 1.0, GOLD, ticks=10)
    # 右：队友小卡
    rx = cx + bs / 2 + 14
    cw = (x + w - 10 - rx) / 3
    for i, (nm, cls, hp) in enumerate(OPS[1:]):
        c0 = rx + i * cw
        m.rect(c0, y + 8, cw - 6, h - 16, C(0.08, 0.09, 0.11, 0.9), outline=C(1, 1, 1, 0.14))
        m.img(HEAD[i + 1], c0 + 3, y + 11, 34 if not phone else 28, 26 if not phone else 22)
        m.text(c0 + (40 if not phone else 34), y + 24, nm[:3], 10, TEXT)
        for k in range(3):
            m.img(SKILL[i + 1][k], c0 + (40 if not phone else 34) + k * 15, y + 28, 13, 13)
        m.bar(c0 + 4, y + h - 16, cw - 14, 4, hp, GREEN if hp > 0.5 else GOLD)
        if i in (0, 1):
            m.diamond(c0 + cw - 13, y + 18, 3, GOLD)
    return x, h


def dir_b_desk():
    m = M(DESK_BG, 1.5)
    W, H = m.W, m.H
    x0, h = console(m, W / 2, H - 16 - 78, 600)
    # 左上只留状态标签
    x = 16
    for s, c in [('LIGHT 灯火通明 · 技力回复 +30%', GOLD), ('护盾 ×1', CYAN), ('攻速 +70%', GOLD)]:
        x += m.chip(x, 16, s, c) + 6
    m.chip(16, 40, '认知负担 · 攻速 −10%', C(0.85, 0.55, 1.0))
    top_center(m)
    # 右上：时间以外的局况一列 + 藏品收起 + 暂停
    relic_strip(m, W - 56, 12)
    m.panel(W - 50, 12, 34, 34, acc=None)
    m.text(W - 33, 34, 'Ⅱ', 13, TEXT, anchor='ms')
    m.panel(W - 96, 54, 80, 30, acc=GREEN)
    m.text(W - 88, 75, '0', 18, TEXT, bold=True)
    m.text(W - 70, 75, '源石锭', 10, SUB)
    minimap(m, 16, H - 16 - 150, 150)
    # 按键牌挪到指挥台左侧
    kx = W / 2 - 300 - 150
    kx += m.keycap(kx, H - 44, '左键', 10, GOLD) + 4
    kx += m.text(kx, H - 31, '瞄准', 11) + 10
    kx += m.keycap(kx, H - 44, 'SPACE', 10, CYAN) + 4
    m.text(kx, H - 31, '冲刺 ×2', 11)
    m.note(W / 2 - 300, H - 16 - 78 - 60, '队长 / 队友 / 指挥 / 倍速收进底部一台；视线从队长往下就到')
    return m.done(os.path.join(OUT, 'B_desktop.png'), '方向 B · 底部指挥台（电脑 1920×1080）')


def dir_b_phone():
    m = M(PH_BG, 1.25, 1.0)
    W, H = m.W, m.H
    console(m, W / 2 - 60, H - 8 - 78, 520, phone=True)
    m.chip(12, 12, '护盾 ×1', CYAN, 10)
    m.chip(76, 12, '攻速 +70%', GOLD, 10)
    top_center(m, 6, compact=True)
    relic_strip(m, W - 12, 8, n_show=3, total=16)
    phone_buttons(m)
    minimap(m, 10, H - 10 - 96, 96)
    return m.done(os.path.join(OUT, 'B_phone.png'), '方向 B · 手机横屏')


# ================================================================ 方向 C：终端侧栏（左侧档案列）
def dossier(m: M, x, y, w, phone=False):
    k = 0.86 if phone else 1.0
    # 队长卡
    m.panel(x, y, w, 76 * k, acc=VIOLET)
    m.img(BADGE, x + 6, y + 6, 58 * k, 60 * k)
    m.text(x + 70 * k, y + 20 * k, '德克萨斯', 14, TEXT, bold=True)
    m.en(x + 70 * k + m.tw('德克萨斯', 14) + 8, y + 19 * k, 'LEADER', 8, VIOLET, 2)
    m.bar(x + 70 * k, y + 28 * k, w - 78 * k, 7, 1.0, CYAN)
    m.text(x + w - 8, y + 48 * k, '195 / 195', 10, SUB, anchor='rs')
    m.bar(x + 70 * k, y + 52 * k, w - 78 * k, 5, 1.0, GOLD, ticks=10)
    m.text(x + 70 * k, y + 70 * k, '灯火 100 · 通明', 10, GOLD)
    yy = y + 80 * k
    # 队友档案行
    for i, (nm, cls, hp) in enumerate(OPS[1:]):
        rh = 30 * k
        m.rect(x, yy, w, rh, C(0.05, 0.057, 0.07, 0.82))
        m.rect(x, yy, 3, rh, CLS[cls])
        m.img(HEAD[i + 1], x + 6, yy + 2, 30 * k, rh - 4)
        m.text(x + 40 * k, yy + 13 * k, nm, 10, TEXT)
        for q in range(3):
            m.img(SKILL[i + 1][q], x + w - 8 - (3 - q) * 14, yy + 3, 12, 12)
        m.bar(x + 40 * k, yy + 19 * k, w - 50 * k - 44, 4, hp, GREEN if hp > 0.5 else GOLD)
        if i in (0, 1):
            m.diamond(x + w - 52, yy + 9 * k, 3, GOLD)
        yy += rh + 3
    # 作战指令行：指挥模式 + 倍速 + 作战时限
    m.rect(x, yy, w, 30 * k, C(0.05, 0.057, 0.07, 0.82))
    px = x + 6
    px += m.pill(px, yy + 4, '突击 · 集火', CYAN, 10, key='' if phone else 'F') + 4
    m.pill(px, yy + 4, '1×', STEEL, 10, key='' if phone else 'V')
    m.bar(x + 6, yy + 26 * k, w - 12, 2, 0.35, CYAN, slot=C(1, 1, 1, 0.1))
    yy += 34 * k
    # 状态标签
    xx = x
    for s, c in [('护盾 ×1', CYAN), ('攻速 +70%', GOLD), ('认知负担 −10%', C(0.85, 0.55, 1.0))]:
        xx += m.chip(xx, yy, s, c, 10) + 4
    return yy + 22


def dir_c_desk():
    m = M(DESK_BG, 1.5)
    W, H = m.W, m.H
    dossier(m, 16, 12, 236)
    top_center(m)
    # 右上：局况卡（时间外的：海域 / 威胁 / 源石锭）+ 藏品收起 + 暂停
    m.panel(W - 16 - 200, 12, 200, 58, acc=CYAN)
    m.text(W - 206, 32, '源石锭', 10, SUB)
    m.text(W - 166, 34, '0', 16, TEXT, bold=True)
    m.text(W - 140, 32, '羁绊', 10, SUB)
    m.text(W - 112, 34, '2', 16, GOLD, bold=True)
    m.text(W - 90, 32, '藏品', 10, SUB)
    m.text(W - 62, 34, '15', 16, TEXT, bold=True)
    for k in range(5):
        m.img(RELIC[k], W - 206 + k * 30, 40, 25, 24)
    m.text(W - 24, 60, '▸', 11, SUB, anchor='rs')
    m.panel(W - 50, 76, 34, 30, acc=None)
    m.text(W - 33, 96, 'Ⅱ', 13, TEXT, anchor='ms')
    minimap(m, W - 16 - 150, H - 16 - 150, 150)
    key_hints(m)
    m.note(16, 300, '左侧一列「档案」：队长 → 队友 → 指令 → 状态；右下空出来给战场')
    return m.done(os.path.join(OUT, 'C_desktop.png'), '方向 C · 终端侧栏（电脑 1920×1080）')


def dir_c_phone():
    m = M(PH_BG, 1.25, 1.0)
    W, H = m.W, m.H
    dossier(m, 10, 10, 210, phone=True)
    top_center(m, 6, compact=True)
    relic_strip(m, W - 12, 8, n_show=3, total=16)
    phone_buttons(m)
    minimap(m, W - 10 - 96 - 150, H - 10 - 96, 96)
    return m.done(os.path.join(OUT, 'C_phone.png'), '方向 C · 手机横屏')


# ================================================================ 指南卡（统一样式，放在三个方向各自的位置）
def guides():
    out = []
    for key, (x, y, w, lab) in {'A': (16, 140, 420, '方向 A：左上状态标签下方（事件槽位置）'),
                                'B': (None, None, 460, '方向 B：指挥台正上方'),
                                'C': (16, 330, 236 * 1.6, '方向 C：左侧档案列下面')}.items():
        m = M(DESK_BG, 1.5)
        if key == 'B':
            x, y = m.W / 2 - 230, m.H - 16 - 78 - 160
        guide_card(m, x, y, w, key)
        m.done(os.path.join(OUT, 'guide_%s.png' % key), '指南卡 · ' + lab)
        out.append(os.path.join(OUT, 'guide_%s.png' % key))
    # 单独一张大图：卡片样式本身（2 倍）
    big = Image.new('RGBA', (1000, 300), (14, 18, 24, 255))
    m = M(big, 2.0)
    guide_card(m, 10, 10, 470)
    m.done(os.path.join(OUT, 'guide_card_style.png'))
    return out


if __name__ == '__main__':
    inventory()
    shots = {'现状': (os.path.join(LA, 'dA_fin', 'rec_00900.png'), os.path.join(LA, 'pA_fin', 'rec_00900.png'))}
    a = (dir_a_desk(), dir_a_phone())
    b = (dir_b_desk(), dir_b_phone())
    c = (dir_c_desk(), dir_c_phone())
    guides()
    # 对比总览：4 行（现状 / A / B / C）× 2 列（电脑 / 手机）
    rows = [('现状', Image.open(shots['现状'][0]), Image.open(shots['现状'][1])),
            ('A 四角收拢', Image.open(os.path.join(OUT, 'A_desktop.png')), Image.open(os.path.join(OUT, 'A_phone.png'))),
            ('B 底部指挥台', Image.open(os.path.join(OUT, 'B_desktop.png')), Image.open(os.path.join(OUT, 'B_phone.png'))),
            ('C 终端侧栏', Image.open(os.path.join(OUT, 'C_desktop.png')), Image.open(os.path.join(OUT, 'C_phone.png')))]
    dw, dh = 960, 540
    pw = int(1170 * dh / 540)
    sheet = Image.new('RGB', (180 + dw + 12 + pw, len(rows) * (dh + 12)), (12, 14, 18))
    d = ImageDraw.Draw(sheet)
    for r, (lab, de, ph) in enumerate(rows):
        y = r * (dh + 12)
        d.text((14, y + dh / 2), lab, font=F(30), fill=(255, 236, 170), anchor='lm')
        sheet.paste(de.convert('RGB').resize((dw, dh)), (180, y))
        sheet.paste(ph.convert('RGB').resize((pw, dh)), (180 + dw + 12, y))
    sheet.save(os.path.join(OUT, 'overview.png'))
    print('ok', sorted(os.listdir(OUT)))
