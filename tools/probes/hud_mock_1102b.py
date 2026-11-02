"""docs/222 §5 第二轮：同一 A 布局上的三套视觉处理（PRTS 终端 / 水月深海 / 强图形）。
每套出 电脑 1920×1080、手机 1170×540、件的放大细节图；外加总览。复用 hud_mock_1102.py 的底图、素材与画笔。
用法：python hud_mock_1102b.py <worktree> <输出目录>"""
import math, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import hud_mock_1102 as H
from hud_mock_1102 import M, C, F, TEXT, SUB, CYAN, GOLD, RED, VIOLET, GREEN, STEEL, TAB_HP, TAB_LAMP, EDGE, EDGE_DIM, CLS, OPS, HEAD, PORTRAIT, SKILL, RELIC, BADGE, MINIMAP
from PIL import Image, ImageDraw

OUT = sys.argv[2]
PURPLE = C(0.66, 0.52, 1.0)
INK = C(0.03, 0.035, 0.045)


# ---------------------------------------------------------------- 通用小画法
def poly(m, pts, fill=None, outline=None, width=1):
    m.d.polygon([(m.P(x), m.P(y)) for x, y in pts], fill=fill, outline=outline, width=width)


def line(m, a, b, col, w=1.0):
    m.d.line([(m.P(a[0]), m.P(a[1])), (m.P(b[0]), m.P(b[1]))], fill=col, width=max(1, int(round(w * m.s))))


def chamfer(x, y, w, h, c, corners='tr,bl'):
    """斜切角矩形的顶点（c = 切角长度；corners 选哪几个角切）"""
    cs = corners.split(',')
    p = []
    p += [(x, y + c), (x + c, y)] if 'tl' in cs else [(x, y)]
    p += [(x + w - c, y), (x + w, y + c)] if 'tr' in cs else [(x + w, y)]
    p += [(x + w, y + h - c), (x + w - c, y + h)] if 'br' in cs else [(x + w, y + h)]
    p += [(x + c, y + h), (x, y + h - c)] if 'bl' in cs else [(x, y + h)]
    return p


def dotted(m, x0, x1, y, col, gap=4):
    x = x0
    while x < x1:
        m.rect(x, y, 1, 1, col)
        x += gap


def mono(m, x, y, s, sz, col, sp=1.2, anchor='l'):
    """等宽小号英文 / 数字：逐字固定步距"""
    step = sz * 0.62 + sp
    if anchor == 'r':
        x -= step * len(s)
    for i, ch in enumerate(s):
        m.text(x + i * step + step / 2, y, ch, sz, col, anchor='ms')
    return step * len(s)


def stripes(m, pts, col, gap=6, w=2):
    """多边形内的斜纹（45°）"""
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    W, Hh = m.P(max(xs) - min(xs)) + 2, m.P(max(ys) - min(ys)) + 2
    ox, oy = m.P(min(xs)), m.P(min(ys))
    mask = Image.new('L', (W, Hh), 0)
    ImageDraw.Draw(mask).polygon([(m.P(x) - ox, m.P(y) - oy) for x, y in pts], fill=255)
    lay = Image.new('RGBA', (W, Hh), (0, 0, 0, 0))
    d = ImageDraw.Draw(lay)
    g = m.P(gap)
    for k in range(-Hh, W + Hh, max(2, g)):
        d.line([(k, Hh), (k + Hh, 0)], fill=col, width=max(1, m.P(w)))
    base = Image.new('RGBA', (W, Hh), (0, 0, 0, 0))
    base.paste(lay, (0, 0), mask)
    m.ov.alpha_composite(base, (ox, oy))


def glow_rect(m, x, y, w, h, r, col, n=6):
    """圆角矩形外发光 / 内发光（一圈圈淡下去的描边）"""
    for k in range(n):
        a = col[3] * (1 - k / n) * 0.5
        rr = [m.P(x - k), m.P(y - k), m.P(x + w + k), m.P(y + h + k)]
        m.d.rounded_rectangle(rr, radius=m.P(r + k), outline=(col[0], col[1], col[2], int(a)), width=1)


def ripple(m, x, y, w, h, col, n=4, amp=2.0, ph=0.0):
    for k in range(n):
        yy = y + h * (k + 1) / (n + 1)
        pts = [(m.P(x + t), m.P(yy + amp * math.sin((t / w) * 6.28 * 2 + ph + k))) for t in range(0, int(w) + 1, 4)]
        m.d.line(pts, fill=col, width=1)


# ================================================================ ① PRTS 终端
class Terminal:
    name = 'T'
    title = '处理 ① PRTS 终端'
    LINE = C(0.62, 0.95, 0.95, 0.55)
    HAIR = C(1, 1, 1, 0.28)

    def frame(self, m, x, y, w, h, c=10, lab=None, code=None):
        p = chamfer(x, y, w, h, c)
        poly(m, p, fill=C(0.025, 0.04, 0.05, 0.78))
        poly(m, p, outline=self.HAIR)
        # 角标刻度：左上 / 右下各一个直角发丝
        line(m, (x - 4, y), (x + 10, y), CYAN, 1.5)
        line(m, (x, y - 4), (x, y + 10), CYAN, 1.5)
        line(m, (x + w - 10, y + h), (x + w + 4, y + h), CYAN, 1.5)
        if lab:
            mono(m, x + 8, y - 5, lab, 8, CYAN)
        if code:
            mono(m, x + w - 6, y - 5, code, 8, SUB, anchor='r')

    def bar(self, m, x, y, w, frac, col, ticks=10, h=5, ro=None):
        m.rect(x, y, w, h, C(0, 0, 0, 0.6))
        n = 40
        for k in range(n):
            if k / n < frac:
                m.rect(x + k * w / n + 0.5, y, w / n - 1.2, h, col)
        for t in range(ticks + 1):
            line(m, (x + w * t / ticks, y + h + 1), (x + w * t / ticks, y + h + (4 if t % 5 == 0 else 2)), self.HAIR, 1)
        if ro:
            mono(m, x + w + 6, y + h + 1, ro, 9, TEXT)

    def leader(self, m, x, y, phone=False):
        w = 290 if not phone else 250
        self.frame(m, x, y, w, 76, lab='OP-00 // LEADER', code='SYNC 100%')
        m.img(BADGE, x + 6, y + 6, 62, 64)
        # 引线：徽记 → 生命读数
        line(m, (x + 70, y + 20), (x + 82, y + 20), self.LINE, 1)
        mono(m, x + 84, y + 18, 'HP', 9, SUB)
        m.text(x + w - 10, y + 22, '195', 18, TEXT, anchor='rs', bold=True)
        mono(m, x + w - 10, y + 32, '/195', 8, SUB, anchor='r')
        self.bar(m, x + 84, y + 26, w - 130, 1.0, CYAN)
        mono(m, x + 84, y + 50, 'LMP', 9, SUB)
        m.text(x + w - 10, y + 54, '100', 14, GOLD, anchor='rs', bold=True)
        self.bar(m, x + 84, y + 56, w - 130, 1.0, GOLD, h=3)
        for t in (0.3, 0.7):
            line(m, (x + 84 + (w - 130) * t, y + 53), (x + 84 + (w - 130) * t, y + 61), GOLD, 1)
        return w

    def status(self, m, x, y):
        for k, (s, col) in enumerate([('LIGHT · 灯火通明 · 技力 +30%', GOLD), ('SHD ×1', CYAN), ('ASPD +70%', GOLD), ('认知负担 −10%', PURPLE)]):
            yy = y + (k // 2) * 20
            xx = x + (0 if k % 2 == 0 else 196)
            m.rect(xx, yy, 2, 14, col)
            m.text(xx + 6, yy + 11, s, 10, TEXT)
            dotted(m, xx + 6 + m.tw(s, 10) + 4, xx + 186, yy + 10, self.HAIR)

    def info(self, m, phone=False):
        W = m.W
        x = W - 16 - (300 if not phone else 230)
        w = (300 if not phone else 230) - 84
        self.frame(m, x, 12, w, 34, c=8, lab='RELIC', code='015')
        mono(m, x + 8, 34, 'R//15', 10, TEXT)
        for k in range(4 if not phone else 3):
            m.rect(x + 56 + k * 32, 16, 28, 26, None, outline=self.HAIR)
            m.img(RELIC[k], x + 58 + k * 32, 17, 24, 23)
        # 暂停 / 倍速 读数牌
        for i, (lab, val, on) in enumerate([('PAUSE', 'Ⅱ', False), ('SPD', '×1.0', False)]):
            px = W - 16 - 74 + i * 40
            self.frame(m, px, 12, 36, 34, c=6, lab=None)
            mono(m, px + 18, 9, lab, 7, SUB, anchor='l') if False else None
            m.text(px + 18, 34, val, 11 if i else 13, TEXT, anchor='ms', bold=True)
        mono(m, W - 16, 58, 'T+10:35 · LV28', 8, SUB, anchor='r')

    def squad(self, m, x, y, cw, ch, phone=False):
        n = 4
        pw = n * (cw + 6) + 10
        hh = 34
        self.frame(m, x, y, pw, hh + ch + 10, c=12, lab='SQUAD // 04-04', code='BOND 02')
        # 指挥牌（读数式）
        line(m, (x + 10, y + 10), (x + 10, y + 26), CYAN, 2)
        mono(m, x + 16, y + 16, 'CMD', 8, SUB)
        m.text(x + 16, y + 29, '随行 · 集火', 12, CYAN, bold=True)
        if not phone:
            m.keycap(x + 100, y + 14, 'F', 9, SUB)
        mono(m, x + 130, y + 16, 'OPS-T', 8, SUB)
        self.bar(m, x + 130, y + 21, 110, 0.35, CYAN, ticks=4, h=3)
        for i, (nm, cls, hp) in enumerate(OPS):
            cx0, cy0 = x + 8 + i * (cw + 6), y + hh + 4
            p = chamfer(cx0, cy0, cw, ch, 8, 'tr')
            poly(m, p, fill=C(0.04, 0.05, 0.06, 0.95))
            m.img(PORTRAIT[i] if not phone else HEAD[i], cx0 + 2, cy0 + 2, cw - 4, ch * 0.62)
            poly(m, p, outline=(VIOLET if i == 0 else self.HAIR))
            mono(m, cx0 + 4, cy0 + ch * 0.62 + 12, 'OP-%02d' % i, 7, SUB)
            m.text(cx0 + cw - 4, cy0 + ch * 0.62 + 12, nm[:4], 10, TEXT, anchor='rs')
            if i:
                self.bar(m, cx0 + 4, cy0 + ch - 9, cw - 8, hp, GREEN if hp > 0.5 else GOLD, ticks=4, h=3)
            else:
                mono(m, cx0 + 4, cy0 + ch - 4, 'LEADER', 7, VIOLET)
            for k in range(3):
                m.rect(cx0 + cw - 4 - (3 - k) * 9, cy0 + 4, 7, 7, [GOLD, CYAN, C(1, 1, 1, 0.25)][k])
        return pw

    def guide(self, m, x, y, w):
        self.frame(m, x, y, w, 110, c=12, lab='TUTORIAL // 02-06', code='LOG')
        m.rect(x + 10, y + 12, 108, 86, C(0, 0, 0, 0.5), outline=self.HAIR)
        m.img(HEAD[0], x + 50, y + 40, 26, 22)
        for dx, dy in [(20, 20), (90, 18), (96, 70), (24, 66)]:
            H.M.diamond(m, x + 10 + dx, y + 12 + dy, 3, C(0.55, 1.0, 0.78))
        m.text(x + 130, y + 30, '经验与升级', 14, TEXT, bold=True)
        m.text(x + 130, y + 52, '拾取经验结晶，经验条满了就升级，', 11, TEXT)
        m.text(x + 130, y + 68, '三张卡里选一张。', 11, TEXT)
        mono(m, x + 130, y + 92, '> 捡起附近的经验结晶', 9, CYAN)
        dotted(m, x + 260, x + w - 40, y + 90, self.HAIR)
        mono(m, x + w - 10, y + 92, '0/1', 9, CYAN, anchor='r')


# ================================================================ ② 水月深海
class Abyss:
    name = 'D'
    title = '处理 ② 水月深海'
    RIM = C(0.55, 0.85, 1.0, 0.5)

    def glass(self, m, x, y, w, h, r=10, rim=None, ph=0.0):
        rr = m.R(x, y, w, h)
        m.d.rounded_rectangle(rr, radius=m.P(r), fill=C(0.05, 0.12, 0.17, 0.55))
        # 顶部亮一截（玻璃反光）
        m.d.rounded_rectangle(m.R(x + 2, y + 2, w - 4, min(14, h / 3)), radius=m.P(r - 2), fill=C(1, 1, 1, 0.05))
        ripple(m, x + 6, y + 4, w - 12, h - 8, C(0.55, 0.9, 1.0, 0.07), n=3, amp=1.6, ph=ph)
        glow_rect(m, x, y, w, h, r, rim or self.RIM, n=5)
        m.d.rounded_rectangle(rr, radius=m.P(r), outline=rim or self.RIM, width=1)

    def tank(self, m, x, y, w, h, frac, col, ph=0.0):
        """有液面的槽：胶囊槽 + 液体（顶边是一道正弦液面 + 一线高光）"""
        m.d.rounded_rectangle(m.R(x, y, w, h), radius=m.P(h / 2), fill=C(0, 0.05, 0.08, 0.7), outline=C(1, 1, 1, 0.18))
        fw = w * frac
        pts = [(m.P(x), m.P(y + h))]
        steps = 24
        for k in range(steps + 1):
            t = k / steps
            yy = y + h * 0.18 + 1.2 * math.sin(t * 6.28 * 3 + ph)
            pts.append((m.P(x + fw * t), m.P(yy)))
        pts.append((m.P(x + fw), m.P(y + h)))
        mask = Image.new('L', m.ov.size, 0)
        ImageDraw.Draw(mask).rounded_rectangle(m.R(x, y, w, h), radius=m.P(h / 2), fill=255)
        lay = Image.new('RGBA', m.ov.size, (0, 0, 0, 0))
        ld = ImageDraw.Draw(lay)
        ld.polygon(pts, fill=col)
        ld.line(pts[1:-1], fill=C(1, 1, 1, 0.55), width=max(1, m.P(1)))
        # 液体里的几颗气泡
        for k in range(5):
            bx = x + fw * (0.15 + 0.17 * k)
            by = y + h * (0.45 + 0.25 * math.sin(k * 2.1 + ph))
            ld.ellipse(m.R(bx, by, 2, 2), outline=C(1, 1, 1, 0.5))
        m.ov.alpha_composite(Image.composite(lay, Image.new('RGBA', m.ov.size, (0, 0, 0, 0)), mask))

    def leader(self, m, x, y, phone=False):
        w = 290 if not phone else 250
        self.glass(m, x + 34, y + 6, w - 34, 66, r=12, rim=C(0.66, 0.52, 1.0, 0.55))
        # 徽记压在玻璃左缘外（配合 B′ 的圆）
        m.d.ellipse(m.R(x + 2, y + 4, 70, 70), fill=C(0.03, 0.08, 0.12, 0.8))
        glow_rect(m, x + 2, y + 4, 70, 70, 35, C(0.55, 0.85, 1.0, 0.6), n=4)
        m.img(BADGE, x + 6, y + 6, 62, 64)
        m.text(x + 84, y + 24, '生命', 10, C(0.7, 0.95, 1.0))
        m.text(x + w - 12, y + 25, '195', 16, TEXT, anchor='rs', bold=True)
        self.tank(m, x + 84, y + 29, w - 100, 12, 1.0, C(0.25, 0.85, 0.95, 0.9), ph=0.6)
        m.text(x + 84, y + 56, '灯火', 10, C(1.0, 0.85, 0.5))
        m.text(x + w - 12, y + 57, '100', 13, GOLD, anchor='rs', bold=True)
        self.tank(m, x + 84 + 26, y + 49, w - 160, 9, 1.0, C(1.0, 0.72, 0.28, 0.9), ph=1.8)
        return w

    def status(self, m, x, y):
        for k, (s, col) in enumerate([('灯火通明 · 技力 +30%', GOLD), ('护盾 ×1', CYAN), ('攻速 +70%', GOLD), ('认知负担 −10%', PURPLE)]):
            yy = y + (k // 2) * 22
            xx = x + (0 if k % 2 == 0 else 168)
            w = m.tw(s, 10) + 22
            m.d.rounded_rectangle(m.R(xx, yy, w, 18), radius=m.P(9), fill=C(0.05, 0.12, 0.17, 0.6), outline=(col[0], col[1], col[2], 140))
            m.d.ellipse(m.R(xx + 6, yy + 6, 6, 6), fill=col)
            m.text(xx + 15, yy + 13, s, 10, TEXT)

    def info(self, m, phone=False):
        W = m.W
        w = 220 if not phone else 170
        x = W - 16 - 84 - w
        self.glass(m, x, 12, w, 34, r=17)
        m.text(x + 14, 34, '藏品', 11, C(0.7, 0.95, 1.0))
        m.text(x + 44, 35, '15', 14, TEXT, bold=True)
        for k in range(4 if not phone else 3):
            m.d.ellipse(m.R(x + 70 + k * 34, 15, 28, 28), fill=C(0, 0.05, 0.08, 0.6), outline=C(0.55, 0.85, 1.0, 0.35))
            m.img(RELIC[k], x + 73 + k * 34, 18, 22, 22)
        for i, val in enumerate(['Ⅱ', '1×']):
            cx = W - 16 - 60 + i * 40
            m.d.ellipse(m.R(cx - 17, 12, 34, 34), fill=C(0.05, 0.12, 0.17, 0.6), outline=self.RIM)
            m.text(cx, 34, val, 12, TEXT, anchor='ms', bold=True)
        m.text(W - 16 - 20, 60, '倍速', 9, SUB, anchor='ms')

    def squad(self, m, x, y, cw, ch, phone=False):
        n = 4
        pw = n * (cw + 6) + 12
        self.glass(m, x, y, pw, ch + 46, r=14, rim=C(0.66, 0.52, 1.0, 0.45))
        # 指挥牌：玻璃胶囊 + 青色内发光
        m.d.rounded_rectangle(m.R(x + 10, y + 8, 128, 24), radius=m.P(12), fill=C(0.1, 0.35, 0.4, 0.55), outline=CYAN)
        glow_rect(m, x + 10, y + 8, 128, 24, 12, C(0.212, 0.886, 0.863, 0.9), n=4)
        m.text(x + 22, y + 25, '指挥 · 随行', 12, TEXT, bold=True)
        if not phone:
            m.keycap(x + 112, y + 11, 'F', 9, SUB)
        self.tank(m, x + 146, y + 16, 90, 6, 0.35, C(0.25, 0.85, 0.95, 0.85))
        m.text(x + pw - 12, y + 25, '编队 4/4 · 羁绊 2', 10, C(0.7, 0.95, 1.0), anchor='rs')
        for i, (nm, cls, hp) in enumerate(OPS):
            cx0, cy0 = x + 8 + i * (cw + 6), y + 38
            m.d.rounded_rectangle(m.R(cx0, cy0, cw, ch), radius=m.P(8), fill=C(0.02, 0.06, 0.09, 0.85))
            m.img(PORTRAIT[i] if not phone else HEAD[i], cx0 + 3, cy0 + 3, cw - 6, ch - 20)
            # 卡底水位 = 生命
            lvl = hp if i else 1.0
            self.tank(m, cx0 + 4, cy0 + ch - 14, cw - 8, 9, lvl, C(0.25, 0.85, 0.95, 0.85) if lvl > 0.5 else C(1.0, 0.72, 0.28, 0.85), ph=i)
            m.d.rounded_rectangle(m.R(cx0, cy0, cw, ch), radius=m.P(8), outline=(PURPLE if i == 0 else C(1, 1, 1, 0.2)), width=max(1, m.P(1.2)))
            m.text(cx0 + cw / 2, cy0 + ch - 18, nm[:4], 9, TEXT, anchor='ms')
            for k in range(3):
                m.d.ellipse(m.R(cx0 + cw - 4 - (3 - k) * 10, cy0 + 4, 7, 7), fill=[GOLD, CYAN, C(1, 1, 1, 0.25)][k])
        return pw

    def guide(self, m, x, y, w):
        self.glass(m, x, y, w, 110, r=14, rim=C(0.212, 0.886, 0.863, 0.6))
        m.d.rounded_rectangle(m.R(x + 10, y + 12, 108, 86), radius=m.P(8), fill=C(0, 0.04, 0.07, 0.7))
        ripple(m, x + 12, y + 14, 104, 82, C(0.55, 0.9, 1.0, 0.12), n=4, amp=2)
        m.img(HEAD[0], x + 50, y + 40, 26, 22)
        m.d.rounded_rectangle(m.R(x + 130, y + 12, 94, 20), radius=m.P(10), fill=C(0.1, 0.35, 0.4, 0.6), outline=CYAN)
        m.text(x + 140, y + 27, '新手引导 2 / 6', 10, TEXT)
        m.text(x + 130, y + 52, '经验与升级', 14, TEXT, bold=True)
        m.text(x + 130, y + 72, '拾取经验结晶，经验条满了就升级，三张卡里选一张。', 11, TEXT)
        m.d.ellipse(m.R(x + 130, y + 86, 8, 8), fill=CYAN)
        m.text(x + 144, y + 94, '捡起附近的经验结晶', 11, CYAN)


# ================================================================ ③ 强图形
class Bold:
    name = 'G'
    title = '处理 ③ 强图形'

    def band(self, m, x, y, w, h, col, slant=14):
        poly(m, [(x + slant, y), (x + w, y), (x + w - slant, y + h), (x, y + h)], fill=col)

    def leader(self, m, x, y, phone=False):
        w = 300 if not phone else 260
        # 斜向色带垫底 + 大号数字
        self.band(m, x + 40, y + 6, w - 40, 40, C(0.05, 0.06, 0.08, 0.86))
        self.band(m, x + 40, y + 6, 10, 40, CYAN, slant=14)
        m.img(BADGE, x + 2, y + 2, 66, 68)
        m.text(x + 84, y + 40, '195', 34, TEXT, bold=True)
        m.text(x + 84 + m.tw('195', 34) + 4, y + 40, '/195', 11, SUB)
        m.text(x + 84 + m.tw('195', 34) + 4, y + 22, '生命', 10, CYAN, bold=True)
        m.rect(x + 160 + 30, y + 30, w - 200, 8, C(0, 0, 0, 0.6))
        m.rect(x + 160 + 30, y + 30, w - 200, 8, CYAN)
        # 灯火：金色斜带上的白字
        self.band(m, x + 70, y + 50, w - 90, 20, C(0.72, 0.53, 0.04, 0.95), slant=10)
        stripes(m, [(x + 80, y + 50), (x + w - 20, y + 50), (x + w - 30, y + 70), (x + 70, y + 70)], C(1, 1, 1, 0.08), gap=5, w=2)
        m.text(x + 86, y + 65, '灯火 100 · 通明', 12, C(0.08, 0.05, 0.0), bold=True)
        return w

    def status(self, m, x, y):
        for k, (s, col) in enumerate([('灯火通明 技力+30%', GOLD), ('护盾×1', CYAN), ('攻速+70%', GOLD), ('认知负担−10%', PURPLE)]):
            yy = y + (k // 2) * 22
            xx = x + (0 if k % 2 == 0 else 150)
            w = m.tw(s, 11) + 18
            self.band(m, xx, yy, w, 18, col, slant=6)
            m.text(xx + 9, yy + 14, s, 11, C(0.05, 0.05, 0.06), bold=True)

    def info(self, m, phone=False):
        W = m.W
        w = 220 if not phone else 170
        x = W - 16 - 84 - w
        self.band(m, x, 12, w, 36, C(0.05, 0.06, 0.08, 0.88), slant=12)
        m.text(x + 18, 40, '15', 24, TEXT, bold=True)
        m.text(x + 18 + m.tw('15', 24) + 3, 30, '藏品', 9, GOLD, bold=True)
        for k in range(4 if not phone else 3):
            m.img(RELIC[k], x + 80 + k * 30, 16, 27, 27)
        for i, val in enumerate(['Ⅱ', '1×']):
            px = W - 16 - 78 + i * 40
            self.band(m, px, 12, 40, 36, CYAN if i == 1 else C(0.05, 0.06, 0.08, 0.88), slant=8)
            m.text(px + 20, 37, val, 14, C(0.03, 0.06, 0.08) if i == 1 else TEXT, anchor='ms', bold=True)

    def squad(self, m, x, y, cw, ch, phone=False):
        n = 4
        pw = n * (cw + 6) + 10
        # 指挥牌：实色青板 + 大字
        self.band(m, x, y, 170, 30, CYAN, slant=12)
        m.text(x + 16, y + 23, '随行', 18, C(0.02, 0.06, 0.08), bold=True)
        m.text(x + 16 + m.tw('随行', 18) + 6, y + 21, 'COMMAND · F', 9, C(0.02, 0.2, 0.24), bold=True)
        m.text(x + pw - 6, y + 22, '4/4', 18, TEXT, anchor='rs', bold=True)
        m.text(x + pw - 6 - m.tw('4/4', 18) - 6, y + 21, '羁绊 2  编队', 10, GOLD, anchor='rs', bold=True)
        for i, (nm, cls, hp) in enumerate(OPS):
            cx0, cy0 = x + 6 + i * (cw + 6), y + 38
            col = CLS[cls]
            m.rect(cx0, cy0 + 10, cw, ch - 10, C(0.05, 0.06, 0.08, 0.92))
            # 职业色块：左侧一整条 + 斜纹
            pts = [(cx0, cy0 + 10), (cx0 + 18, cy0 + 10), (cx0 + 18, cy0 + ch), (cx0, cy0 + ch)]
            poly(m, pts, fill=col)
            stripes(m, pts, C(0, 0, 0, 0.18), gap=4, w=1.5)
            m.text(cx0 + 9, cy0 + 28, cls, 12, C(0.05, 0.05, 0.06), anchor='ms', bold=True)
            # 头像出框：头顶越过卡上沿
            m.img(HEAD[i], cx0 + 20, cy0 - 4, cw - 22, (cw - 22) * 0.7)
            m.text(cx0 + 22, cy0 + ch - 12, nm[:4], 12, TEXT, bold=True)
            if i:
                m.rect(cx0 + 22, cy0 + ch - 8, cw - 26, 5, C(0, 0, 0, 0.6))
                m.rect(cx0 + 22, cy0 + ch - 8, (cw - 26) * hp, 5, GREEN if hp > 0.5 else GOLD)
            else:
                self.band(m, cx0 + 22, cy0 + ch - 9, 40, 7, VIOLET, slant=4)
            for k in range(3):
                m.rect(cx0 + cw - 4 - (3 - k) * 9, cy0 + 14, 7, 7, [GOLD, CYAN, C(1, 1, 1, 0.25)][k])
        return pw

    def guide(self, m, x, y, w):
        self.band(m, x, y, w, 110, C(0.05, 0.06, 0.08, 0.92), slant=18)
        self.band(m, x + 10, y, 90, 110, CYAN, slant=18)
        m.text(x + 54, y + 74, '02', 46, C(0.02, 0.06, 0.08), anchor='ms', bold=True)
        m.text(x + 54, y + 94, '/ 06', 11, C(0.02, 0.2, 0.24), anchor='ms', bold=True)
        m.text(x + 116, y + 34, '经验与升级', 20, TEXT, bold=True)
        m.text(x + 116, y + 58, '拾取经验结晶，经验条满了就升级，', 12, TEXT)
        m.text(x + 116, y + 76, '三张卡里选一张。', 12, TEXT)
        self.band(m, x + 116, y + 84, 170, 18, GOLD, slant=6)
        m.text(x + 126, y + 98, '捡起附近的经验结晶', 11, C(0.08, 0.05, 0.0), bold=True)


# ================================================================ 组装
def desktop(T):
    m = M(H.DESK_BG, 1.5)
    W, Hh = m.W, m.H
    T.leader(m, 14, 10)
    T.status(m, 16, 94)
    H.top_center(m)
    T.info(m)
    cw, ch = 84, 96
    pw = 4 * (cw + 6) + 12
    T.squad(m, W - 16 - pw, Hh - 16 - (ch + 46), cw, ch)
    H.minimap(m, 16, Hh - 16 - 150, 150)
    H.key_hints(m)
    return m.done(os.path.join(OUT, 'R2_%s_desktop.png' % T.name), T.title + '（A 布局 · 电脑 1920×1080）')


def phone(T):
    m = M(H.PH_BG, 1.25, 1.0)
    W, Hh = m.W, m.H
    T.leader(m, 10, 8, phone=True)
    T.status(m, 12, 92)
    H.top_center(m, 6, compact=True)
    T.info(m, phone=True)
    H.phone_buttons(m, '随行', speed=False)   # 倍速在右上信息条里
    cw, ch = 70, 56
    pw = 4 * (cw + 6) + 12
    T.squad(m, W - 12 - pw, Hh - 10 - (ch + 46), cw, ch, phone=True)
    H.minimap(m, 10, Hh - 10 - 96, 96)
    return m.done(os.path.join(OUT, 'R2_%s_phone.png' % T.name), T.title + '（手机横屏）')


def detail(T):
    """件的放大细节：队长块、右上信息条、编队面板（含指挥牌）、指南卡，2 倍"""
    bg = H.DESK_BG.crop((600, 520, 1560, 1060)).resize((1920, 1080))
    m = M(bg, 2.0)
    m.rect(0, 0, m.W, m.H, C(0.02, 0.03, 0.04, 0.55))
    T.leader(m, 20, 24)
    T.status(m, 22, 108)
    m.W = 960 - 20   # 右上信息条贴右沿
    T.info(m)
    m.W = 960
    T.squad(m, 20, 170, 84, 96)
    T.guide(m, 430, 170, 470)
    lab = {'T': '角：斜切 + 直角刻度 · 线：发丝框 + 引线 · 纹理：点线 / 分段刻度条 · 动效：读数逐位跳动、刷新时扫描线过一遍',
           'D': '角：圆角 · 线：内发光描边（青 / UI.PURPLE） · 纹理：水波纹 + 气泡 · 动效：受击液面晃、数值变化时涟漪',
           'G': '角：平行四边形斜切 · 线：粗色带、无细线 · 纹理：职业色斜纹 · 动效：色带硬切滑入、大数字跳动'}[T.name]
    m.text(20, 520, lab, 11, C(1.0, 0.93, 0.66))
    return m.done(os.path.join(OUT, 'R2_%s_detail.png' % T.name), T.title + ' · 件的放大（2 倍）')


if __name__ == '__main__':
    os.makedirs(OUT, exist_ok=True)
    rows = []
    for T in (Terminal(), Abyss(), Bold()):
        rows.append((T.title, desktop(T), phone(T), detail(T)))
    dw, dh = 960, 540
    pw = int(1170 * dh / 540)
    sheet = Image.new('RGB', (200 + dw + 12 + pw + 12 + dw, len(rows) * (dh + 60 + 12)), (12, 14, 18))
    d = ImageDraw.Draw(sheet)
    for r, (lab, de, ph, dt) in enumerate(rows):
        y = r * (dh + 72)
        d.text((14, y + dh / 2), lab.replace('处理 ', ''), font=H.FBF(28), fill=(255, 236, 170), anchor='lm')
        for k, (im, x, w) in enumerate([(de, 200, dw), (ph, 200 + dw + 12, pw), (dt, 200 + dw + 12 + pw + 12, dw)]):
            sheet.paste(im.convert('RGB').resize((w, dh + 30)), (x, y))
    sheet.save(os.path.join(OUT, 'R2_overview.png'))
    print('ok')
