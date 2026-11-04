"""指挥台三版式 · PRTS 终端版（用户 11-05「能不能再有点 prts 的设计感」）。
版式与 hud_console_1105.py 相同，只换造型语言（沿用 docs/222 §8 第五轮 PRTS 终端）：
斜切发丝框 + 直角刻度、分段读数条、等宽字距小字（OP-00 // LEADER）、白底黑字键牌、终端日志状态行、
队友窗编号 01–03 + 10 格生命、倒地洋红斜纹警示、徽记刻度环。颜色只用现有令牌。
用法：python hud_console_1105p.py <worktree> <底图目录> <输出目录>"""
import math, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import hud_console_1105 as H
from hud_console_1105 import A, CYAN, VIOLET, RED, GOLD, GREEN, TEXT, SUB, PAPER, INK, font
from PIL import Image, ImageDraw

HAIR = (255, 255, 255, 70)
FILL = (7, 9, 11)


def poly(m, pts, fill=None, outline=None, w=0.7):
    P = [(m.P(a), m.P(b)) for a, b in pts]
    if fill:
        m.d.polygon(P, fill=fill)
    if outline:
        m.d.line(P + [P[0]], fill=outline, width=max(1, round(m.P(w))))


def cham(x, y, w, h, c=6, tl=0, tr=1, br=0, bl=1):
    """斜切矩形顶点（默认右上 + 左下切角）"""
    return [(x + (c if tl else 0), y), (x + w - (c if tr else 0), y), (x + w, y + (c if tr else 0)),
            (x + w, y + h - (c if br else 0)), (x + w - (c if br else 0), y + h), (x + (c if bl else 0), y + h),
            (x, y + h - (c if bl else 0)), (x, y + (c if tl else 0))]


def corner_tick(m, x, y, col=CYAN, L=9, w=1.3, dx=1, dy=1):
    m.line([(x, y + L * dy), (x, y), (x + L * dx, y)], col, w)


def hatch(m, x, y, w, h, col, step=4.0, wid=1.4):
    """45° 斜纹（警示）"""
    g = Image.new('RGBA', (int(m.P(w)), int(m.P(h))), (0, 0, 0, 0))
    d = ImageDraw.Draw(g)
    s = m.P(step)
    k = -g.size[1]
    while k < g.size[0]:
        d.line([(k, g.size[1]), (k + g.size[1], 0)], fill=col, width=max(1, round(m.P(wid))))
        k += s
    m.ov.alpha_composite(g, (int(m.P(x)), int(m.P(y))))


# ---------------------------------------------------------------- 覆盖：通用件
def cap(self, x, y, s, size=5.6, col=SUB, anchor='ls'):
    """等宽字距小字：每个字符固定步距（PRTS 终端读数感）"""
    f = font('semi', self.P(size))
    pitch = self.P(size * 0.86)
    w = pitch * len(s)
    x0 = self.P(x) - (w / 2 if anchor[0] == 'm' else (w if anchor[0] == 'r' else 0))
    for i, ch in enumerate(s):
        self.d.text((x0 + i * pitch + pitch / 2, self.P(y)), ch, font=f, fill=col, anchor='m' + anchor[1])
    return w / self.s


def panel(self, x, y, w, h, a=150, accent=CYAN, fade=0, tag='R.I. TAC-LINK // 04'):
    poly(self, cham(x, y, w, h, 8), fill=(FILL[0], FILL[1], FILL[2], min(255, a + 20)))
    poly(self, cham(x, y, w, h, 8), outline=HAIR, w=0.6)
    corner_tick(self, x - 2.5, y - 2.5, accent or CYAN)
    corner_tick(self, x + w + 2.5, y + h + 2.5, (255, 255, 255, 110), 7, 1.0, -1, -1)
    # 底边刻度尺（右下一段）
    for i in range(10):
        tx = x + w - 14 - i * 5
        self.line([(tx, y + h - 1), (tx, y + h - (4 if i % 5 == 0 else 2.2))], (255, 255, 255, 70), 0.5)
    if tag and w >= 400:
        cap(self, x + w - 10, y + 7.5, tag, 3.9, A(SUB, 120), 'rs')


def seg_bar(m, x, y, w, frac, col, h=2.0, marks=(), back=(255, 255, 255, 36), trail=None, rtl=False):
    n = max(6, int(w / 4.2))
    sw = w / n
    on = round(n * max(0.0, min(1.0, frac)))
    tr = round(n * trail) if trail is not None else on
    hh = max(h, 2.6)
    for i in range(n):
        j = (n - 1 - i) if rtl else i
        sx = x + j * sw
        c = col if i < on else (A(RED, 200) if i < tr else back)
        m.rect(sx, y, sw - 1.0, hh, fill=c)
    for t in marks:
        mx = x + w * (1 - t) if rtl else x + w * t
        m.line([(mx, y - 2.5), (mx, y + hh + 2.5)], (255, 255, 255, 140), 0.6)
    for k in range(0, n + 1, 10):   # 每 10 格一根短刻度
        kx = x + w - k * sw if rtl else x + k * sw
        m.line([(kx - 0.5, y + hh + 1.2), (kx - 0.5, y + hh + 3)], (255, 255, 255, 60), 0.5)


def keycap(m, x, y, s, size=7.0, col=TEXT, bg=None, anchor='l'):
    """白底黑字键牌，右上斜切"""
    f = font('semi', m.P(size))
    w = f.getlength(s) / m.s + size * 1.1
    h = size * 1.5
    if anchor == 'r':
        x -= w
    elif anchor == 'm':
        x -= w / 2
    poly(m, cham(x, y, w, h, 2.6, tr=1, bl=0), fill=PAPER if col != CYAN else CYAN)
    m.text(x + w / 2 - 0.6, y + h / 2 + size * 0.05, s, size, INK, 'semi', 'mm')
    return w


def badge(m, cx, cy, r, assets, state, key='Q', touch=False):
    ult = 1.0 if state == 'ult' else H.LEADER['ult']
    full = ult >= 1
    m.circle(cx, cy, r + 7, fill=(6, 8, 10, 215))
    m.paste_circle(assets['badge'], cx, cy, r)
    m.circle(cx, cy, r, outline=(255, 255, 255, 80), w=0.6)
    # 刻度环：40 格，充能部分亮
    n = 40
    for i in range(n):
        a = math.radians(-90 + i * 360 / n)
        lit = i < round(n * ult)
        L = 4.0 if i % 10 == 0 else 2.6
        r0 = r + 2.2
        c = (PAPER if full else CYAN) if lit else (255, 255, 255, 50)
        m.line([(cx + math.cos(a) * r0, cy + math.sin(a) * r0), (cx + math.cos(a) * (r0 + L), cy + math.sin(a) * (r0 + L))], c, 1.0 if lit else 0.6)
    # 外侧四个直角刻度（取景框）
    R = r + 9
    for dx, dy in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
        corner_tick(m, cx + dx * R, cy + dy * R, A(VIOLET, 230), 5, 1.0, -dx, -dy)
    if full:
        m.glow(cx - r - 8, cy - r - 8, 2 * r + 16, 2 * r + 16, A(PAPER, 210), 10)
        w = 40
        poly(m, cham(cx - w / 2, cy + r + 2, w, 9, 2.5), fill=PAPER)
        cap(m, cx, cy + r + 9, 'ULT READY', 4.6, INK, 'ms')
    elif cy + r + 11 > m.H - 1:
        cap(m, cx - r - 11, cy + r + 4, 'ULT %03d%%' % int(ult * 100), 4.6, CYAN, 'rs')
    else:
        cap(m, cx, cy + r + 10, 'ULT %03d%%' % int(ult * 100), 4.8, CYAN, 'ms')
    if key and not touch:
        keycap(m, cx + R - 3, cy - R - 3, key, 7.0)


def hp_block(m, x, y, w, state, big=17.0, rtl=False, show_lamp=True):
    hit = state == 'hit'
    hp = H.LEADER['hp'] - (38 if hit else 0)
    al = 'rs' if rtl else 'ls'
    xx = x + w if rtl else x
    cap(m, xx, y - big - 2.5, 'OP-00 // TEXAS // LEADER', 4.6, A(SUB, 200), al)
    lab = 'HP'
    # 读数：小字 HP 压在大数字左侧
    if rtl:
        sw = m.text(xx, y, ' / %d' % H.LEADER['hpmax'], big * 0.42, SUB, 'num', 'rs')
        nw = m.text(xx - sw, y, '%03d' % hp, big, RED if hit else TEXT, 'num', 'rs')
        cap(m, xx - sw - nw - 3, y - 1, lab, 5.2, A(CYAN, 230), 'rs')
    else:
        lw = cap(m, xx, y - 1, lab, 5.2, A(CYAN, 230), 'ls')
        nw = m.text(xx + lw + 3, y, '%03d' % hp, big, RED if hit else TEXT, 'num', 'ls')
        m.text(xx + lw + 3 + nw, y, ' / %d' % H.LEADER['hpmax'], big * 0.42, SUB, 'num', 'ls')
    if hit:
        m.glow(x - 2, y + 3, w + 4, 6, A(RED, 220), 6)
    seg_bar(m, x, y + 4.5, w, hp / H.LEADER['hpmax'], RED if hit else CYAN, 2.4,
            trail=(H.LEADER['hp'] / H.LEADER['hpmax']) if hit else None, rtl=rtl)
    if show_lamp:
        ly = y + 17.5
        if rtl:
            nw = m.text(xx, ly, '%03d' % H.LEADER['lamp'], 7.0, GOLD, 'num', 'rs')
            cap(m, xx - nw - 3, ly - 0.5, 'LMP', 4.8, A(GOLD, 220), 'rs')
            seg_bar(m, x, ly - 4, w - 46, H.LEADER['lamp'] / 100, GOLD, 1.6, marks=(0.3, 0.7), rtl=True)
        else:
            cw = cap(m, xx, ly - 0.5, 'LMP', 4.8, A(GOLD, 220), 'ls')
            m.text(xx + cw + 3, ly, '%03d' % H.LEADER['lamp'], 7.0, GOLD, 'num', 'ls')
            seg_bar(m, x + 46, ly - 4, w - 46, H.LEADER['lamp'] / 100, GOLD, 1.6, marks=(0.3, 0.7))


def dash_pips(m, cx, y, state, key='SPACE', touch=False, label=True):
    n = H.LEADER['dash']
    for k in range(2):
        px = cx + (k - 0.5) * 10
        on = k < n
        pts = [(px - 4, y - 4.5), (px + 1, y - 4.5), (px + 4, y), (px + 1, y + 4.5), (px - 4, y + 4.5), (px - 1, y)]
        if on:
            poly(m, pts, fill=CYAN)
        else:
            poly(m, pts, fill=(255, 255, 255, 30), outline=(255, 255, 255, 110), w=0.5)
    if label:
        cap(m, cx, y + 13, 'DASH %02d' % n, 4.6, SUB, 'ms')
    if key and not touch:
        keycap(m, cx, y - 19, key, 6.2, anchor='m')


def mate_card(m, x, y, w, h, mt, assets, state, tag=None):
    down = mt.get('down')
    idx = H.MATES.index(next(q for q in H.MATES if q['id'] == mt['id'])) + 1
    poly(m, cham(x, y, w, h, 6, tr=1, bl=0), fill=(6, 8, 10, 190))
    m.paste(assets[mt['id']], x + 1, y + 1, w - 2, h - 2, gray=bool(down))
    # 右上切角处补底色，立绘不出斜边
    poly(m, [(x + w - 6, y), (x + w + 0.5, y), (x + w + 0.5, y + 6)], fill=(0, 0, 0, 0))
    m.d.polygon([(m.P(x + w - 6.5), m.P(y - 0.5)), (m.P(x + w + 1), m.P(y - 0.5)), (m.P(x + w + 1), m.P(y + 6.5))], fill=(0, 0, 0, 0))
    m.rect(x, y + 10, 1.8, h - 20, fill=mt['col'])   # 职业色竖条
    low = mt['hp'] < 0.35 and not down
    poly(m, cham(x, y, w, h, 6, tr=1, bl=0), outline=A(RED, 230) if (down or low) else HAIR, w=1.0 if (down or low) else 0.6)
    # 编号块
    m.rect(x, y, 13, 8, fill=(0, 0, 0, 210))
    cap(m, x + 6.5, y + 6.3, '%02d' % idx, 4.6, PAPER, 'ms')
    # 10 格生命
    m.rect(x + 1, y + h - 7, w - 2, 6, fill=(0, 0, 0, 170))
    seg_bar(m, x + 3, y + h - 5.5, w - 6, mt['hp'], RED if low else TEXT, 2.2, back=(255, 255, 255, 30))
    if down:
        m.glow(x, y, w, h, A(RED, 255), 8)
        hatch(m, x + 1, y + h / 2 - 9, w - 2, 17, A(RED, 110), 4.5, 1.3)
        m.rect(x + 4, y + h / 2 - 6, w - 8, 11, fill=(0, 0, 0, 200))
        m.text(x + w / 2, y + h / 2 + 2.6, '倒地 %02d' % down, 7.5, RED, 'cn', 'ms')


def mate_dot(m, cx, cy, r, mt, assets, state):
    """圆头像改成斜切小窗 + 编号 + 分段生命（PRTS 版不用圆）"""
    w, h = r * 2 + 2, r * 2 + 6
    mate_card(m, cx - w / 2, cy - h / 2, w, h, mt, assets, state)


def cmd_grid(m, x, y, w, h, key='F', touch=False, cols=4):
    rows = 4 // cols
    cw, ch = w / cols, h / rows
    for i, s in enumerate(H.MODES):
        cx, cy = x + (i % cols) * cw, y + (i // cols) * ch
        on = i == H.MODE_I
        pts = cham(cx + 0.8, cy + 0.8, cw - 1.6, ch - 1.6, 4, tr=1, bl=0)
        poly(m, pts, fill=A(CYAN, 235) if on else (0, 0, 0, 120), outline=None if on else (255, 255, 255, 40), w=0.5)
        cap(m, cx + 4, cy + 7, '%02d' % (i + 1), 3.8, INK if on else A(SUB, 150), 'ls')
        m.text(cx + cw / 2 + 2, cy + ch / 2 + 3.4, s, 8.5, INK if on else SUB, 'cn', 'ms')
    m.rect(x, y - 9.5, 1.6, 7, fill=CYAN)
    cap(m, x + 4, y - 4, 'CMD // %s' % H.MODES_EN[H.MODE_I], 4.6, SUB)
    if key and not touch:
        keycap(m, x + w, y - 12, key, 6.2, anchor='r')


def status_line(m, x, y, anchor='ls'):
    parts = ['灯火通明', '护盾 ×1']
    f = font('cn', m.P(7.0))
    tw = sum(f.getlength(p) for p in parts) / m.s + 10 * len(parts) + 6
    x0 = x - (tw / 2 if anchor[0] == 'm' else (tw if anchor[0] == 'r' else 0))
    cap(m, x0, y, '>', 6.0, CYAN, 'ls')
    xx = x0 + 7
    for i, p in enumerate(parts):
        m.rect(xx, y - 6.5, 1.5, 7, fill=GOLD if i == 0 else CYAN)
        xx += 3.5
        xx += m.text(xx, y, p, 7.0, A(TEXT, 210), 'cn', 'ls') + 6.5


def corners(m, touch=False, sonar=True):
    W, Hh = m.W, m.H
    m.rect(0, 0, W * 0.62, 3.2, fill=A(H.rgb('8cffc7'), 210))
    m.rect(W * 0.62, 0, W * 0.38, 3.2, fill=(255, 255, 255, 25))
    cx = W / 2
    cap(m, cx - 8, 15, 'KILL', 4.4, A(SUB, 150), 'rs')
    m.text(cx - 8, 29, '1906', 12.5, A(TEXT, 180), 'num', 'rs')
    m.line([(cx, 10), (cx + 0.01, 32)], (255, 255, 255, 60), 0.6)
    m.line([(cx - 3, 10), (cx + 3, 10)], (255, 255, 255, 60), 0.6)
    cap(m, cx + 8, 15, 'T+', 4.4, A(SUB, 150), 'ls')
    m.text(cx + 8, 29, '09:56', 12.5, A(TEXT, 180), 'num', 'ls')
    m.text(cx, 40, '深蓝之树', 6.5, A(SUB, 140), 'cn', 'ms')
    cap(m, cx, 47, 'SECTOR // THREAT VI', 3.8, A(SUB, 110), 'ms')
    rx = W - 12 - (8 if touch else 0)
    for lab, kk in (('×1.0', 'V'), ('II', 'ESC')):
        w = 21
        poly(m, cham(rx - w, 10, w, 12, 3), fill=(0, 0, 0, 100), outline=(255, 255, 255, 80), w=0.5)
        m.text(rx - w / 2, 16.3, lab, 6.0, A(TEXT, 190), 'num', 'mm')
        if not touch:
            cap(m, rx - w / 2, 29, kk, 3.8, A(SUB, 120), 'ms')
        rx -= w + 5
    rx -= 6
    cap(m, rx, 13, 'RELIC', 4.2, A(SUB, 150), 'rs')
    m.text(rx, 25, '18', 11, A(TEXT, 180), 'num', 'rs')
    rx -= 30
    cap(m, rx, 13, 'INGOT', 4.2, A(GREEN, 170), 'rs')
    m.text(rx, 25, '24', 11, A(TEXT, 180), 'num', 'rs')
    if sonar:
        sx, sy, r = (46, 64, 30) if touch else (46, Hh - 46, 34)
        m.circle(sx, sy, r, fill=(0, 0, 0, 60), outline=(255, 255, 255, 45), w=0.6)
        for i in range(36):
            a = math.radians(i * 10)
            L = 3 if i % 9 == 0 else 1.5
            m.line([(sx + math.cos(a) * r, sy + math.sin(a) * r), (sx + math.cos(a) * (r - L), sy + math.sin(a) * (r - L))], (255, 255, 255, 70), 0.5)
        m.line([(sx - r, sy), (sx + r, sy)], (255, 255, 255, 25), 0.4)
        m.line([(sx, sy - r), (sx, sy + r)], (255, 255, 255, 25), 0.4)
        for dx, dy, c in ((10, -6, RED), (-14, 9, RED), (5, 16, CYAN), (-6, -15, RED), (18, 4, GOLD)):
            m.rect(sx + dx * r / 34 - 1.2, sy + dy * r / 34 - 1.2, 2.4, 2.4, fill=A(c, 180))
        m.circle(sx, sy, 1.6, fill=TEXT)
        cap(m, sx - r, sy - r - 3, 'SONAR // 360', 3.8, A(SUB, 110))


def touch_buttons(m, which=('ult', 'dash', 'aim', 'cmd', 'info'), state='normal', at=None):
    """手机键：八角斜切 + 刻度 + 等宽英文"""
    W, Hh = m.W, m.H
    pos = {'dash': (W - 70, Hh - 82, 33), 'ult': (W - 162, Hh - 120, 38), 'aim': (W - 74, Hh - 182, 26),
           'cmd': (W - 236, Hh - 56, 25), 'info': (W - 40, 150, 20)}
    if at:
        pos.update(at)

    def octo(cx, cy, r):
        c = r * 0.38
        return cham(cx - r, cy - r, 2 * r, 2 * r, c, 1, 1, 1, 1)

    for k in which:
        cx, cy, r = pos[k]
        if k == 'ult':
            ult = 1.0 if state == 'ult' else H.LEADER['ult']
            full = ult >= 1
            poly(m, octo(cx, cy, r), fill=PAPER if full else (8, 10, 12, 185), outline=None if full else (255, 255, 255, 100), w=0.7)
            n = 32
            for i in range(n):
                a = math.radians(-90 + i * 360 / n)
                lit = i < round(n * ult)
                m.line([(cx + math.cos(a) * (r + 3), cy + math.sin(a) * (r + 3)), (cx + math.cos(a) * (r + 6.5), cy + math.sin(a) * (r + 6.5))],
                       (PAPER if full else CYAN) if lit else (255, 255, 255, 45), 1.1 if lit else 0.6)
            m.text(cx, cy + 3, '终结技', 11, INK if full else TEXT, 'cn', 'ms')
            cap(m, cx, cy + 13, 'ULT READY' if full else 'ULT %03d%%' % int(ult * 100), 4.4, INK if full else SUB, 'ms')
            if full:
                m.glow(cx - r - 4, cy - r - 4, 2 * r + 8, 2 * r + 8, A(PAPER, 200), 8)
            continue
        poly(m, octo(cx, cy, r), fill=(8, 10, 12, 180), outline=(255, 255, 255, 100), w=0.7)
        corner_tick(m, cx - r - 2.5, cy - r - 2.5, A(CYAN, 200) if k == 'cmd' else (255, 255, 255, 90), 5, 0.9)
        lab = {'dash': ('冲刺', 'DASH'), 'aim': ('瞄准', 'AIM'), 'cmd': (H.MODES[H.MODE_I], 'CMD'), 'info': ('属性', 'INFO')}[k]
        m.text(cx, cy + 3, lab[0], 10 if r > 24 else 8.5, CYAN if k == 'cmd' else TEXT, 'cn', 'ms')
        cap(m, cx, cy + 12, lab[1], 4.2, SUB, 'ms')
        if k == 'dash':
            for j in range(2):
                px = cx + (j - 0.5) * 8
                py = cy + r - 7
                poly(m, [(px - 3, py - 2.5), (px + 1, py - 2.5), (px + 3, py), (px + 1, py + 2.5), (px - 3, py + 2.5), (px - 1, py)],
                     fill=CYAN if j < H.LEADER['dash'] else (255, 255, 255, 45))


def joystick(m):
    cx, cy = 150, m.H - 120
    m.circle(cx, cy, 58, outline=(255, 255, 255, 40), w=0.8)
    for i in range(24):
        a = math.radians(i * 15)
        m.line([(cx + math.cos(a) * 58, cy + math.sin(a) * 58), (cx + math.cos(a) * 54, cy + math.sin(a) * 54)], (255, 255, 255, 50), 0.5)
    m.circle(cx + 14, cy - 8, 20, fill=(255, 255, 255, 30), outline=(255, 255, 255, 70), w=0.8)
    m.text(cx, cy + 74, '左摇杆区', 6.5, A(SUB, 110), 'cn', 'ms')


def arc_panel(m, cx, ytop, halfw, depth, h, a=160):
    """B：中间抬高的梯形台（PRTS 版不用弧）"""
    Hh = m.H
    y1 = ytop + depth
    pts = [(cx - halfw, Hh), (cx - halfw + 16, y1), (cx - 74, y1), (cx - 60, ytop), (cx + 60, ytop),
           (cx + 74, y1), (cx + halfw - 16, y1), (cx + halfw, Hh)]
    poly(m, pts, fill=(FILL[0], FILL[1], FILL[2], a + 10))
    poly(m, pts[:-1] + [pts[-1]], outline=None)
    m.line(pts, HAIR, 0.6)
    corner_tick(m, cx - 60 - 3, ytop - 3, CYAN, 7)
    corner_tick(m, cx + 60 + 3, ytop - 3, CYAN, 7, dx=-1)
    cap(m, cx - halfw + 22, Hh - 4, 'R.I. TAC-LINK // 04', 3.9, A(SUB, 110), 'ls')


H.MODES_EN = ['FOLLOW', 'ASSAULT', 'DEPLOY', 'FOCUS']
H.M.cap = cap
H.M.panel = panel
for name, fn in dict(bar=seg_bar, keycap=keycap, badge=badge, hp_block=hp_block, dash_pips=dash_pips, mate_card=mate_card,
                     mate_dot=mate_dot, cmd_grid=cmd_grid, status_line=status_line, corners=corners,
                     touch_buttons=touch_buttons, joystick=joystick, arc_panel=arc_panel).items():
    setattr(H, name, fn)

H.NOTES['B'] = ('中轴梯形台 · 极简', [
    '放了：中间队长徽记（终结技刻度环 + Q），左翼生命 / 灯火分段条从徽记往外长，右翼三格编号小窗（10 格生命）+ 当前指令（F），冲刺两格挂在徽记正下方。',
    '台面中间抬高一段，像终端的取景台；最窄，约屏宽 40%。',
    '优点：视线集中在角色正下方一小块，挡得最少。',
    '缺点：看不到队友名字；指挥只显示当前模式，按 F 才弹圆盘；手机上徽记环和终结技键重复显示充能。',
])

if __name__ == '__main__':
    H.main()
