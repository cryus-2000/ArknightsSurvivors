"""指挥台第三稿 · 终末地 × NieR 减法版（用户 11-05「更高级、更有设计感」→「试试看」）。只出示意图。
规则：不画底板，只垫一道底部渐变；一个主角（队长头像 + 终结技环）；装饰只留直角刻度 + 等宽小字各一两处；
常态黑白灰，青只在「可以按」时出现，洋红只在危险时，金只给灯火；闲时整台约 45% 不透明，出事时提亮；8 像素网格、同一条底线。
版式沿用 A：左生命 / 灯火，中头像，右队友 + 指挥。
用法：python hud_console_1105r3.py <worktree> <底图目录> <输出目录>"""
import math, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import hud_console_1105 as H
from hud_console_1105 import A, M, CYAN, RED, GOLD, TEXT, SUB, INK, font
from PIL import Image, ImageDraw, ImageFont

OUT = sys.argv[3]
WHITE = (236, 238, 240, 255)
GREY = (150, 156, 164, 255)
DIM = (255, 255, 255, 46)


def mono(m, x, y, s, size, col, anchor='ls', pitch=0.9):
    f = font('semi', m.P(size))
    p = m.P(size * pitch)
    w = p * len(s)
    x0 = m.P(x) - (w / 2 if anchor[0] == 'm' else (w if anchor[0] == 'r' else 0))
    for i, ch in enumerate(s):
        m.d.text((x0 + i * p + p / 2, m.P(y)), ch, font=f, fill=col, anchor='m' + anchor[1])
    return w / m.s


def gradient(m, h, a=150):
    g = Image.new('RGBA', (int(m.P(m.W)), int(m.P(h))), (0, 0, 0, 0))
    px = g.load()
    for j in range(g.size[1]):
        t = j / max(1, g.size[1] - 1)
        al = int(a * (t ** 1.6))
        for i in range(g.size[0]):
            px[i, j] = (4, 6, 8, al)
    m.ov.alpha_composite(g, (0, int(m.P(m.H - h))))


def tick(m, x, y, dx, dy, col=(255, 255, 255, 120), L=6):
    m.line([(x, y + L * dy), (x, y), (x + L * dx, y)], col, 0.8)


def hairbar(m, x, y, w, frac, col, trail=None, rtl=True, back=DIM, h=1.0):
    """1 像素细线；rtl = 从右端（头像侧）往左长"""
    m.rect(x, y, w, h, fill=back)
    def seg(f0, f1, c):
        if f1 <= f0:
            return
        a0, a1 = (x + w * (1 - f1), x + w * (1 - f0)) if rtl else (x + w * f0, x + w * f1)
        m.rect(a0, y - (h * 0.5 if c != back else 0), a1 - a0, h * 2, fill=c)
    if trail is not None:
        seg(frac, trail, A(RED, 150))
    seg(0, frac, col)


def _bez(p0, c, p1, n=10):
    return [((1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * c[0] + t * t * p1[0], (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * c[1] + t * t * p1[1])
            for t in (i / n for i in range(1, n + 1))]


def _drop(cx, yb, w, h, sway):
    rw = w / 2
    yc = yb - rw
    pts = [(cx + math.cos(math.pi * i / 12) * rw, yc + math.sin(math.pi * i / 12) * rw) for i in range(13)]
    tip = (cx + sway, yb - h)
    pts += _bez((cx - rw, yc), (cx - rw * 1.05, yc - (h - rw) * 0.55), tip)
    pts += _bez(tip, (cx + rw * 1.1, yc - (h - rw) * 0.5), (cx + rw, yc))
    return pts


def flame(m, cx, yb, lamp, k=1.0):
    """灯火火焰：四档。通明 ≥70 高、亮金、白芯 + 微光 + 火星；摇曳 30–70 中、金、尖端偏；
    暗淡 <30 矮、暗橙、半透明；寂灭 0 只剩一粒洋红余烬 + 一缕灰烟"""
    P = lambda pts: [(m.P(a), m.P(b)) for a, b in pts]
    if lamp <= 0:
        m.circle(cx, yb - 2.2 * k, 1.8 * k, fill=A(RED, 230))
        m.glow(cx - 3 * k, yb - 5 * k, 6 * k, 6 * k, A(RED, 160), 4)
        m.line([(cx, yb - 5 * k), (cx - 2 * k, yb - 10 * k), (cx + 1.5 * k, yb - 15 * k), (cx - 1 * k, yb - 20 * k)], (180, 186, 194, 90), 0.6)
        return
    f = min(lamp, 100) / 100.0
    h = k * (9 + 15 * f)
    w = h * 0.52
    if lamp >= 70:
        outer, mid, core, sway = (244, 192, 78, 255), (255, 228, 160, 255), (255, 255, 246, 255), 1.0 * k
        m.glow(cx - w, yb - h * 0.9, w * 2, h, A(GOLD, 120), 9)
    elif lamp >= 30:
        outer, mid, core, sway = (232, 170, 70, 235), (252, 214, 140, 235), (255, 248, 230, 220), 2.2 * k
    else:
        outer, mid, core, sway = (196, 104, 58, 170), (226, 150, 92, 160), None, -1.6 * k
    m.d.polygon(P(_drop(cx, yb, w, h, sway)), fill=outer)
    m.d.polygon(P(_drop(cx + sway * 0.15, yb - h * 0.04, w * 0.62, h * 0.66, sway * 0.6)), fill=mid)
    if core:
        m.d.polygon(P(_drop(cx + sway * 0.1, yb - h * 0.06, w * 0.3, h * 0.34, sway * 0.3)), fill=core)
    if lamp >= 70:
        for dx, dy, rr in ((-0.55, 1.2, 0.9), (0.6, 1.4, 0.7), (0.1, 1.65, 0.6)):
            m.circle(cx + dx * w, yb - dy * h, rr * k, fill=(255, 220, 140, 220))


def console(m, assets, state, touch=False):
    W, Hh = m.W, m.H
    k = 0.92 if touch else 1.0
    cx = W / 2 - (44 if touch else 0)
    base = Hh - (14 if touch else 16)          # 统一底线
    r = 22 * k
    by = base - r - 6 * k                      # 头像中心
    hit, ultf, down = state == 'hit', state == 'ult', state == 'down'
    L = H.LEADER

    # ---- 主角：头像 + 终结技环
    ult = 1.0 if ultf else L['ult']
    m.circle(cx, by, r + 1, fill=(0, 0, 0, 150))
    m.paste_circle(assets['badge'], cx, by, r)
    m.arc(cx, by, r + 4, 0, 360, DIM, 1.0)
    if ultf:
        m.glow(cx - r - 6, by - r - 6, 2 * r + 12, 2 * r + 12, A(CYAN, 170), 9)
        m.arc(cx, by, r + 4, 0, 360, CYAN, 1.6)
    else:
        m.arc(cx, by, r + 4, -90, -90 + 360 * ult, WHITE, 1.4)
        a = math.radians(-90 + 360 * ult)
        m.circle(cx + math.cos(a) * (r + 4), by + math.sin(a) * (r + 4), 1.6, fill=WHITE)
    # Q：头像正上方，满了才变青
    if not touch:
        mono(m, cx, by - r - 9, 'Q', 6.0, CYAN if ultf else GREY, 'ms')
    mono(m, cx, base + 9 * k, 'READY' if ultf else '%d%%' % int(ult * 100), 4.6, CYAN if ultf else GREY, 'ms', 1.0)

    # ---- 左：生命 / 灯火，从头像往外长
    gx = cx - r - 14 * k                        # 左组右缘
    lw = 196 * k
    hp = L['hp'] - (38 if hit else 0)
    numc = RED if hit else WHITE
    sw = m.text(gx, base - 16 * k, ' / %d' % L['hpmax'], 6.5 * k, GREY, 'num', 'rs')
    m.text(gx - sw, base - 16 * k, str(hp), 18 * k, numc, 'num', 'rs')
    mono(m, gx - lw, base - 30 * k, 'TEXAS  ·  LV 27', 4.4, GREY)
    hairbar(m, gx - lw, base - 10 * k, lw, hp / L['hpmax'], RED if hit else WHITE,
            trail=(L['hp'] / L['hpmax']) if hit else None)
    if hit:
        m.glow(gx - lw * (L['hp'] / L['hpmax']), base - 12 * k, lw * 38 / L['hpmax'], 4, A(RED, 180), 5)
    # 灯火：生命数字左侧一簇火焰 + 小号数字（替掉灯火细线）
    nw = font('num', m.P(18 * k)).getlength(str(hp)) / m.s
    fx = gx - sw - nw - 14 * k
    flame(m, fx, base - 16 * k, L['lamp'], 1.15 * k)
    mono(m, fx - 7 * k, base - 16.5 * k, '%d' % L['lamp'], 4.8, A(GOLD, 220) if L['lamp'] >= 30 else A(RED, 220), 'rs', 0.95)
    # 冲刺：底线上两短划，可用 = 青
    for j in range(2):
        on = j < L['dash']
        x0 = gx - 22 * k + j * 12 * k
        m.rect(x0, base + 2.5 * k, 9 * k, 1.6, fill=CYAN if on else DIM)
    if not touch:
        mono(m, gx - 26 * k, base + 4.6 * k, 'SPACE', 4.0, GREY, 'rs')
    # 状态：左组左端一行灰字
    m.text(gx - lw, base - 40 * k, H.STATUS, 6.6 * k, A(GREY, 230), 'cn', 'ls')

    # ---- 右：队友三格 + 指挥
    qx = cx + r + 14 * k
    s = 30 * k
    ms = H.st_mates(state)
    for i, mt in enumerate(ms):
        x = qx + i * (s + 8 * k)
        y = base - s - 6 * k
        dn = mt.get('down')
        sub = assets[mt['id']]
        sw_, sh_ = sub.size
        face = sub.crop((int(sw_ * 0.12), int(sh_ * 0.02), int(sw_ * 0.88), int(sh_ * 0.02) + int(sw_ * 0.76)))
        m.rect(x, y, s, s, fill=(0, 0, 0, 120))
        m.paste(face, x, y, s, s, gray=bool(dn), alpha=150 if dn else 255)
        low = mt['hp'] < 0.35 and not dn
        hairbar(m, x, base - 1.5 * k, s, mt['hp'], RED if (low or dn) else WHITE, rtl=False)
        if dn:
            m.glow(x, y, s, s, A(RED, 200), 6)
            m.line([(x, y), (x + s, y)], RED, 1.0)
            mono(m, x + s / 2, y + s / 2 + 3, '%02d' % dn, 8.0, RED, 'ms', 0.75)
    # 指挥：当前一个词 + 四个点（当前那颗实心）
    mx = qx + 3 * (s + 8 * k) + 6 * k
    m.text(mx, base - 14 * k, H.MODES[H.MODE_I], 11 * k, WHITE, 'cn', 'ls')
    for i in range(4):
        px = mx + 2 + i * 7 * k
        if i == H.MODE_I:
            m.circle(px, base - 4 * k, 1.8, fill=WHITE)
        else:
            m.circle(px, base - 4 * k, 1.6, outline=(255, 255, 255, 110), w=0.5)
    if not touch:
        mono(m, mx, base - 28 * k, 'F  CMD', 4.2, GREY)
    # ---- 唯一装饰：整组的一对直角刻度 + 头像下方断开的底线
    gl, gr = gx - lw - 8, mx + 40 * k
    tick(m, gl, base - 46 * k, 1, 1)
    tick(m, gr, base + 6 * k, -1, -1)
    m.line([(gl + 8, base + 6 * k), (cx - r - 6, base + 6 * k)], (255, 255, 255, 34), 0.5)
    m.line([(cx + r + 6, base + 6 * k), (gr - 8, base + 6 * k)], (255, 255, 255, 34), 0.5)
    return Hh - (base - 46 * k)


def touch_buttons(m, state):
    W, Hh = m.W, m.H
    ultf = state == 'ult'
    for key, (cx, cy, r) in {'aim': (W - 74, Hh - 182, 24), 'ult': (W - 162, Hh - 118, 34), 'dash': (W - 70, Hh - 80, 30),
                             'info': (W - 40, 150, 18)}.items():
        m.circle(cx, cy, r, fill=(0, 0, 0, 70), outline=(255, 255, 255, 80), w=0.6)
        lab = {'aim': '瞄准', 'ult': '终结技', 'dash': '冲刺', 'info': '属性'}[key]
        col = WHITE
        if key == 'ult':
            if ultf:
                m.circle(cx, cy, r, outline=CYAN, w=1.4)
                m.glow(cx - r - 3, cy - r - 3, 2 * r + 6, 2 * r + 6, A(CYAN, 150), 7)
                col = CYAN
            else:
                m.arc(cx, cy, r, -90, -90 + 360 * H.LEADER['ult'], WHITE, 1.4)
        m.text(cx, cy + 3.5, lab, 10 if r > 22 else 8.5, col, 'cn', 'ms')
        if key == 'dash':
            for j in range(2):
                m.rect(cx - 9 + j * 10, cy + 11, 8, 1.5, fill=CYAN if j < H.LEADER['dash'] else DIM)
    cx, cy = 150, Hh - 120
    m.circle(cx, cy, 56, outline=(255, 255, 255, 34), w=0.6)
    m.circle(cx + 14, cy - 8, 18, fill=(255, 255, 255, 24), outline=(255, 255, 255, 60), w=0.6)


def corners(m, touch):
    """角上：再小、再淡（约 55%），不加任何框"""
    W, Hh = m.W, m.H
    m.rect(0, 0, W * 0.62, 2.4, fill=A(H.rgb('8cffc7'), 190))
    a = 150
    cx = W / 2
    m.text(cx - 8, 24, '1906', 11, (255, 255, 255, a), 'num', 'rs')
    m.text(cx + 8, 24, '09:56', 11, (255, 255, 255, a), 'num', 'ls')
    m.line([(cx, 14), (cx, 26)], (255, 255, 255, 50), 0.5)
    mono(m, cx, 35, 'BLUE TREE  ·  VI', 3.8, (255, 255, 255, 90), 'ms')
    rx = W - 16
    m.text(rx, 22, 'II   1×', 8, (255, 255, 255, a), 'num', 'rs')
    m.text(rx - 46, 22, '18', 9, (255, 255, 255, a), 'num', 'rs')
    mono(m, rx - 46, 30, 'RELIC', 3.6, (255, 255, 255, 80), 'rs')
    m.text(rx - 80, 22, '24', 9, (255, 255, 255, a), 'num', 'rs')
    mono(m, rx - 80, 30, 'INGOT', 3.6, (255, 255, 255, 80), 'rs')
    sx, sy, r = (40, 58, 26) if touch else (40, Hh - 40, 28)
    m.circle(sx, sy, r, outline=(255, 255, 255, 40), w=0.5)
    for dx, dy, c in ((10, -6, RED), (-14, 9, RED), (5, 16, WHITE), (-6, -15, RED), (18, 4, GOLD)):
        m.circle(sx + dx * r / 34, sy + dy * r / 34, 1.1, fill=A(c, 150))
    m.circle(sx, sy, 1.3, fill=WHITE)


def render(base, s, state, touch, assets, alpha=1.0):
    m = M(base, s)
    gradient(m, 120 if not touch else 96, 160)
    corners(m, touch)
    c = M(base, s)
    used = console(c, assets, state, touch)
    if touch:
        touch_buttons(c, state)
    if alpha < 1:
        ch = c.ov.getchannel('A').point(lambda v: int(v * alpha))
        c.ov.putalpha(ch)
    m.ov.alpha_composite(c.ov)
    return m.done(), used / m.H * 100


def main():
    import json
    BASE = sys.argv[2]
    os.makedirs(OUT, exist_ok=True)
    cfg = json.load(open(os.path.join(BASE, 'crops.json'), encoding='utf-8'))
    H.CARD_BOXES.update({k: tuple(v) for k, v in cfg['cards'].items()})
    H.BADGE_BOX = tuple(cfg['badge'])
    H.EXTRA.update(cfg.get('extra', {}))
    H.BASE = BASE
    assets = H.load_assets()
    pc = Image.open(os.path.join(BASE, 'pc.png'))
    ph = Image.open(os.path.join(BASE, 'phone.png'))
    im, p1 = render(pc, 1.5, 'normal', False, assets)
    im.save(os.path.join(OUT, 'R3_pc.png'))
    im, p2 = render(ph, 2.0, 'normal', True, assets)
    im.save(os.path.join(OUT, 'R3_phone.png'))
    tiles, labs = [], []
    for stt, al, lab in (('normal', 0.45, '闲时：整台约 45% 不透明'), ('normal', 1.0, '有变化时提亮（常态全亮）'),
                         ('hit', 1.0, '掉血：数字与细线转洋红 + 残影'), ('ult', 1.0, '终结技充满：环与 Q 转青 + 微光'),
                         ('down', 1.0, '队友倒地：头像灰 + 洋红线 + 读秒')):
        im, _ = render(pc, 1.5, stt, False, assets, al)
        tiles.append(im.crop((420, 900, 1500, 1080)).resize((1620, 270), Image.LANCZOS))
        labs.append(lab)
    tw, th = tiles[0].size
    sheet = Image.new('RGB', (tw, (th + 8) * len(tiles)), (16, 18, 22))
    d = ImageDraw.Draw(sheet)
    f = ImageFont.truetype(os.path.join(H.FONTS, 'ui.ttf'), 26)
    for i, (t, lab) in enumerate(zip(tiles, labs)):
        sheet.paste(t, (0, i * (th + 8)))
        d.text((18, i * (th + 8) + 14), lab, font=f, fill=(255, 220, 120))
    sheet.save(os.path.join(OUT, 'R3_states.png'))
    # 灯火四档放大
    from hud_console_1105 import rgb
    bg = pc.crop((560, 760, 1360, 1000)).convert('RGBA')
    m = M(bg, 1.5)
    gradient(m, m.H, 120)
    for i, (lv, lab) in enumerate(((90, '通明 ≥ 70'), (52, '摇曳 30–70'), (18, '暗淡 < 30'), (0, '寂灭 0'))):
        x = 70 + i * 130
        flame(m, x, 112, lv, 2.6)
        mono(m, x, 132, '%d' % lv, 9, A(GOLD, 230) if lv >= 30 else A(RED, 230), 'ms', 0.9)
        m.text(x, 150, lab, 10, (230, 232, 236, 230), 'cn', 'ms')
    m.done().save(os.path.join(OUT, 'R3_lamp.png'))
    print(p1, p2)


if __name__ == '__main__':
    main()
