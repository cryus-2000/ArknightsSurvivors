"""指挥台第四稿：第三稿（终末地 × NieR 减法版）+ 灯火改提灯 + 整体放大（用户 11-05「火焰用 pixelfx」「提灯那种感觉」「UI 有点太小」）。
提灯是 pixelfx 新做的 fire/hud-lantern（level 0–100 四档），这里读它导出的帧条（--sheet），按整数倍最近邻贴进示意图。
放大：电脑整台 ×1.3（字号、头像、细线一起放），手机 ×1.15；占高仍 ≤ 12%。
用法：python hud_console_1105r4.py <worktree> <底图目录> <输出目录> <提灯帧条目录（sheet_<lv>.png/json）>"""
import json, math, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import hud_console_1105 as H
import hud_console_1105r3 as R
from hud_console_1105 import A, M, CYAN, RED, GOLD, font
from hud_console_1105r3 import WHITE, GREY, DIM, mono, gradient, tick, hairbar
from PIL import Image, ImageDraw, ImageFont

OUT, LANT = sys.argv[3], sys.argv[4]
FRAME = 12
_sheet = {}


def lantern_frame(level, i=FRAME):
    lv = 90 if level >= 70 else (50 if level >= 30 else (18 if level > 0 else 0))
    if lv not in _sheet:
        _sheet[lv] = (Image.open(os.path.join(LANT, 'sheet_%d.png' % lv)).convert('RGBA'),
                      json.load(open(os.path.join(LANT, 'sheet_%d.json' % lv)))['meta']['pixelfx'])
    im, meta = _sheet[lv]
    fw, fh = meta['frameSize']
    c = meta['columns']
    return im.crop(((i % c) * fw, (i // c) * fh, (i % c + 1) * fw, (i // c + 1) * fh)), meta['pivot']


def paste_lantern(m, x, y, level, px=2, i=FRAME):
    """(x, y) 逻辑坐标 = 提灯底座中心；px = 每个像素画成几个屏幕像素（整数，最近邻）"""
    fr, pv = lantern_frame(level, i)
    big = fr.resize((fr.size[0] * px, fr.size[1] * px), Image.NEAREST)
    m.ov.alpha_composite(big, (int(m.P(x) - pv[0] * px), int(m.P(y) - pv[1] * px)))


def console(m, assets, state, touch=False):
    W, Hh = m.W, m.H
    k = 1.05 if touch else 1.3
    cx = W / 2 - (40 if touch else 0)
    base = Hh - 13 * k
    r = 22 * k
    by = base - r - 6 * k
    hit, ultf = state == 'hit', state == 'ult'
    L = H.LEADER
    lamp = L['lamp'] if state not in H.LAMP_OVERRIDE else H.LAMP_OVERRIDE[state]

    # ---- 主角：头像 + 终结技环
    ult = 1.0 if ultf else L['ult']
    m.circle(cx, by, r + 1, fill=(0, 0, 0, 150))
    m.paste_circle(assets['badge'], cx, by, r)
    m.arc(cx, by, r + 4 * k, 0, 360, DIM, 1.2)
    if ultf:
        m.glow(cx - r - 7, by - r - 7, 2 * r + 14, 2 * r + 14, A(CYAN, 170), 10)
        m.arc(cx, by, r + 4 * k, 0, 360, CYAN, 2.0)
    else:
        m.arc(cx, by, r + 4 * k, -90, -90 + 360 * ult, WHITE, 1.8)
        a = math.radians(-90 + 360 * ult)
        m.circle(cx + math.cos(a) * (r + 4 * k), by + math.sin(a) * (r + 4 * k), 2.0, fill=WHITE)
    if not touch:
        mono(m, cx, by - r - 10 * k, 'Q', 6.5 * k, CYAN if ultf else GREY, 'ms')
    mono(m, cx, base + 9 * k, 'READY' if ultf else '%d%%' % int(ult * 100), 5.4 * k, CYAN if ultf else GREY, 'ms', 1.0)

    # ---- 左：提灯 + 生命
    gx = cx - r - 14 * k
    lw = 168 * k
    hp = L['hp'] - (38 if hit else 0)
    sw = m.text(gx, base - 14 * k, ' / %d' % L['hpmax'], 7.5 * k, GREY, 'num', 'rs')
    m.text(gx - sw, base - 14 * k, str(hp), 20 * k, RED if hit else WHITE, 'num', 'rs')
    hairbar(m, gx - lw, base - 7 * k, lw, hp / L['hpmax'], RED if hit else WHITE,
            trail=(L['hp'] / L['hpmax']) if hit else None, h=1.4)
    if hit:
        m.glow(gx - lw * (L['hp'] / L['hpmax']), base - 9 * k, lw * 38 / L['hpmax'], 5, A(RED, 180), 6)
    mono(m, gx - lw, base - 14 * k, 'TEXAS  LV 27', 5.0 * k, GREY)
    m.text(gx - lw, base - 26 * k, H.STATUS, 8.0 * k, A(GREY, 235), 'cn', 'ls')
    # 冲刺：底线下两短划
    for j in range(2):
        m.rect(gx - 28 * k + j * 15 * k, base + 1.5 * k, 11 * k, 2.0, fill=CYAN if j < L['dash'] else DIM)
    if not touch:
        mono(m, gx - 32 * k, base + 4.6 * k, 'SPACE', 4.6 * k, GREY, 'rs')
    # 提灯：左组最外侧，底座落在底线上；读数在灯下
    lx = gx - lw - 22 * k
    paste_lantern(m, lx, base + 1, lamp, 2)
    lcol = A(GOLD, 230) if lamp >= 30 else A(RED, 230)
    mono(m, lx, base + 9 * k, 'LAMP %d' % lamp, 4.8 * k, lcol, 'ms', 0.95)

    # ---- 右：队友 + 指挥
    qx = cx + r + 14 * k
    s = 30 * k
    for i, mt in enumerate(H.st_mates(state)):
        x = qx + i * (s + 8 * k)
        y = base - s - 5 * k
        dn = mt.get('down')
        sub = assets[mt['id']]
        sw_, sh_ = sub.size
        face = sub.crop((int(sw_ * 0.12), int(sh_ * 0.02), int(sw_ * 0.88), int(sh_ * 0.02) + int(sw_ * 0.76)))
        m.rect(x, y, s, s, fill=(0, 0, 0, 120))
        m.paste(face, x, y, s, s, gray=bool(dn), alpha=150 if dn else 255)
        low = mt['hp'] < 0.35 and not dn
        hairbar(m, x, base - 1.5 * k, s, mt['hp'], RED if (low or dn) else WHITE, rtl=False, h=1.4)
        if dn:
            m.glow(x, y, s, s, A(RED, 200), 7)
            m.line([(x, y), (x + s, y)], RED, 1.2)
            mono(m, x + s / 2, y + s / 2 + 4, '%02d' % dn, 10 * k, RED, 'ms', 0.75)
    mx = qx + 3 * (s + 8 * k) + 6 * k
    m.text(mx, base - 13 * k, H.MODES[H.MODE_I], 13 * k, WHITE, 'cn', 'ls')
    for i in range(4):
        px = mx + 3 + i * 8.5 * k
        if i == H.MODE_I:
            m.circle(px, base - 3 * k, 2.2, fill=WHITE)
        else:
            m.circle(px, base - 3 * k, 2.0, outline=(255, 255, 255, 120), w=0.6)
    if not touch:
        mono(m, mx, base - 27 * k, 'F  CMD', 4.8 * k, GREY)
    # ---- 装饰：一对直角刻度 + 断开的底线
    gl, gr = lx - 16 * k, mx + 40 * k
    tick(m, gl, base - 50 * k, 1, 1, L=7 * k)
    tick(m, gr, base + 6 * k, -1, -1, L=7 * k)
    m.line([(gl + 9, base + 6 * k), (cx - r - 6, base + 6 * k)], (255, 255, 255, 34), 0.5)
    m.line([(cx + r + 6, base + 6 * k), (gr - 9, base + 6 * k)], (255, 255, 255, 34), 0.5)
    return Hh - (base - 50 * k)


def sonar(m, sx, sy, r):
    """声呐（11-05 用户：再大一点）：暗底圆 + 两道距离圈 + 十字刻度 + 扫描扇 + 视野框；敌人洋红、精英金、拾取白，点按距离淡出"""
    m.circle(sx, sy, r, fill=(0, 0, 0, 70), outline=(255, 255, 255, 70), w=0.7)
    for f in (0.66, 0.33):
        m.circle(sx, sy, r * f, outline=(255, 255, 255, 26), w=0.5)
    for a in range(0, 360, 15):
        t = math.radians(a)
        L = 4 if a % 90 == 0 else 2
        m.line([(sx + math.cos(t) * r, sy + math.sin(t) * r), (sx + math.cos(t) * (r - L), sy + math.sin(t) * (r - L))], (255, 255, 255, 80 if a % 90 == 0 else 45), 0.5)
    # 扫描扇：最近 40° 一道渐隐
    for j in range(16):
        a0 = -50 + j * 2.5
        m.arc(sx, sy, r * 0.5, a0, a0 + 2.6, (140, 255, 199, int(6 + j * 3.2)), r)
    t = math.radians(-10)
    m.line([(sx, sy), (sx + math.cos(t) * r, sy + math.sin(t) * r)], (140, 255, 199, 110), 0.6)
    # 视野框（屏幕范围）
    m.rect(sx - r * 0.42, sy - r * 0.24, r * 0.84, r * 0.48, outline=(255, 255, 255, 50), width=0.5)
    pts = ((10, -6, RED, 1), (-14, 9, RED, 1), (5, 16, WHITE, 0), (-6, -15, RED, 1), (18, 4, GOLD, 2), (-22, -10, RED, 1),
           (24, -14, RED, 1), (-8, 24, RED, 1), (14, 22, RED, 1), (-26, 12, WHITE, 0), (28, 18, RED, 1), (2, -26, GOLD, 2))
    for dx, dy, c, kind in pts:
        x, y = sx + dx * r / 34, sy + dy * r / 34
        d = math.hypot(dx, dy) / 34
        a = int(230 - 110 * d)
        if kind == 2:
            m.d.polygon([(m.P(x), m.P(y - 2.4)), (m.P(x + 2.4), m.P(y)), (m.P(x), m.P(y + 2.4)), (m.P(x - 2.4), m.P(y))], fill=A(c, a))
        else:
            m.circle(x, y, 1.6 if kind else 1.3, fill=A(c, a))
    m.d.polygon([(m.P(sx), m.P(sy - 3.2)), (m.P(sx + 2.2), m.P(sy + 2.4)), (m.P(sx), m.P(sy + 1.2)), (m.P(sx - 2.2), m.P(sy + 2.4))], fill=WHITE)
    m.text(sx - r, sy - r - 4, '声呐', 6.5, (255, 255, 255, 110), 'cn', 'ls')


def corners(m, touch):
    """角上仍小而淡，但比第三稿大一号"""
    W, Hh = m.W, m.H
    m.rect(0, 0, W * 0.62, 2.6, fill=A(H.rgb('8cffc7'), 190))
    a = 165
    cx = W / 2
    m.text(cx - 9, 27, '1906', 13, (255, 255, 255, a), 'num', 'rs')
    m.text(cx + 9, 27, '09:56', 13, (255, 255, 255, a), 'num', 'ls')
    m.line([(cx, 15), (cx, 29)], (255, 255, 255, 55), 0.6)
    m.text(cx, 41, '深蓝之树 · 威胁 VI', 7.5, (255, 255, 255, 105), 'cn', 'ms')
    rx = W - 16
    m.text(rx, 25, 'II   1×', 10, (255, 255, 255, a), 'num', 'rs')
    for v, lab, off in (('18', '藏品', 58), ('24', '源石锭', 100)):
        m.text(rx - off, 25, v, 11, (255, 255, 255, a), 'num', 'rs')
        m.text(rx - off, 37, lab, 6.5, (255, 255, 255, 100), 'cn', 'rs')
    sonar(m, *((60, 76, 44) if touch else (64, Hh - 64, 50)))


def touch_buttons(m, state):
    W, Hh = m.W, m.H
    ultf = state == 'ult'
    for key, (cx, cy, r) in {'aim': (W - 76, Hh - 196, 27), 'ult': (W - 172, Hh - 128, 38), 'dash': (W - 72, Hh - 84, 33),
                             'info': (W - 40, 150, 20)}.items():
        m.circle(cx, cy, r, fill=(0, 0, 0, 80), outline=(255, 255, 255, 90), w=0.7)
        lab = {'aim': '瞄准', 'ult': '终结技', 'dash': '冲刺', 'info': '属性'}[key]
        col = WHITE
        if key == 'ult':
            if ultf:
                m.circle(cx, cy, r, outline=CYAN, w=1.6)
                m.glow(cx - r - 3, cy - r - 3, 2 * r + 6, 2 * r + 6, A(CYAN, 150), 8)
                col = CYAN
            else:
                m.arc(cx, cy, r, -90, -90 + 360 * H.LEADER['ult'], WHITE, 1.6)
        m.text(cx, cy + 4, lab, 11.5 if r > 24 else 9.5, col, 'cn', 'ms')
        if key == 'dash':
            for j in range(2):
                m.rect(cx - 10 + j * 11, cy + 13, 9, 1.8, fill=CYAN if j < H.LEADER['dash'] else DIM)
    cx, cy = 150, Hh - 120
    m.circle(cx, cy, 56, outline=(255, 255, 255, 34), w=0.6)
    m.circle(cx + 14, cy - 8, 18, fill=(255, 255, 255, 24), outline=(255, 255, 255, 60), w=0.6)


def render(base, s, state, touch, assets, alpha=1.0):
    m = M(base, s)
    gradient(m, 140 if not touch else 100, 170)
    corners(m, touch)
    c = M(base, s)
    used = console(c, assets, state, touch)
    if touch:
        touch_buttons(c, state)
    if alpha < 1:
        c.ov.putalpha(c.ov.getchannel('A').point(lambda v: int(v * alpha)))
    m.ov.alpha_composite(c.ov)
    return m.done(), used / m.H * 100


H.LAMP_OVERRIDE = {}


def main():
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
    H.LEADER['lamp'] = 82
    im, p1 = render(pc, 1.5, 'normal', False, assets)
    im.save(os.path.join(OUT, 'R4_pc.png'))
    im, p2 = render(ph, 2.0, 'normal', True, assets)
    im.save(os.path.join(OUT, 'R4_phone.png'))
    H.STATUS = '灯火通明 / 护盾 ×1'
    rows = (('normal', 0.45, '闲时：整台约 45% 不透明'), ('normal', 1.0, '有变化时提亮'),
            ('hit', 1.0, '掉血：数字与细线转洋红 + 残影'), ('ult', 1.0, '终结技充满：环与 Q 转青 + 微光'),
            ('down', 1.0, '队友倒地：头像灰 + 洋红线 + 读秒'))
    tiles = []
    for stt, al, lab in rows:
        im, _ = render(pc, 1.5, stt, False, assets, al)
        tiles.append((im.crop((300, 880, 1620, 1080)), lab))
    tw, th = tiles[0][0].size
    sheet = Image.new('RGB', (tw, (th + 8) * len(tiles)), (16, 18, 22))
    d = ImageDraw.Draw(sheet)
    f = ImageFont.truetype(os.path.join(H.FONTS, 'ui.ttf'), 24)
    for i, (t, lab) in enumerate(tiles):
        sheet.paste(t, (0, i * (th + 8)))
        d.text((16, i * (th + 8) + 10), lab, font=f, fill=(255, 220, 120))
    sheet.save(os.path.join(OUT, 'R4_states.png'))
    # 提灯四档：同一底图，按游戏里的 2 倍像素，再并排一张 4 倍放大
    bg = pc.crop((560, 700, 1360, 1000)).convert('RGBA')
    m = M(bg, 1.5)
    gradient(m, m.H, 130)
    for i, (lv, lab) in enumerate(((90, '通明 ≥ 70'), (50, '摇曳 30–70'), (18, '暗淡 < 30'), (0, '寂灭 0'))):
        x = 70 + i * 130
        paste_lantern(m, x, 140, lv, 4)
        mono(m, x, 160, 'LAMP %d' % lv, 7, A(GOLD, 230) if lv >= 30 else A(RED, 230), 'ms', 0.95)
        m.text(x, 182, lab, 11, (230, 232, 236, 230), 'cn', 'ms')
    m.done().save(os.path.join(OUT, 'R4_lamp.png'))
    # 提灯四档动画帧（给 mp4 用）：90 帧
    fdir = os.path.join(OUT, '_lamp_frames')
    os.makedirs(fdir, exist_ok=True)
    for fi in range(90):
        mm = M(bg, 1.5)
        gradient(mm, mm.H, 130)
        for i, (lv, lab) in enumerate(((90, '通明 ≥ 70'), (50, '摇曳 30–70'), (18, '暗淡 < 30'), (0, '寂灭 0'))):
            x = 70 + i * 130
            paste_lantern(mm, x, 140, lv, 4, fi)
            mono(mm, x, 160, 'LAMP %d' % lv, 7, A(GOLD, 230) if lv >= 30 else A(RED, 230), 'ms', 0.95)
            mm.text(x, 182, lab, 11, (230, 232, 236, 230), 'cn', 'ms')
        mm.done().save(os.path.join(fdir, 'f%03d.png' % fi))
    print(p1, p2)


if __name__ == '__main__':
    main()
