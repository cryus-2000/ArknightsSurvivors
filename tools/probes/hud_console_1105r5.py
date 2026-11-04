"""指挥台第五稿（用户 11-05：提灯像蜡烛 → 用生图工具做煤油马灯；灯火条要回来、放在生命下面；队友头像大小不一；终结技再明显一点）。
- 马灯：pixgen 出底图 + hud_lantern_1105.py 罩内着色 / 火焰 / 柔光的四档 30 帧帧条，按 1 倍屏幕像素贴。
- 灯火条：生命细线下面一根金色细线，30 / 70 两根刻度，左端写「灯火 82」。
- 队友头像：按卡片里角色的实际外框找头部，统一裁成同样大小的方块。
- 终结技：头像加大，环加粗到 3 像素 + 外圈刻度；头像下写「Q 终结技 64%」；充满时整环青色、外圈一道呼吸光环、字改「终结技 就绪」。
用法：python hud_console_1105r5.py <worktree> <底图目录> <输出目录> <马灯帧条目录>"""
import json, math, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import hud_console_1105 as H
import hud_console_1105r3 as R3
from hud_console_1105 import A, M, CYAN, RED, GOLD, font
from hud_console_1105r3 import WHITE, GREY, DIM, mono, gradient, tick, hairbar
from PIL import Image, ImageDraw, ImageFont

OUT, LANT = sys.argv[3], sys.argv[4]
_strip = {}


def tier_of(lv):
    return 'lit' if lv >= 70 else ('sway' if lv >= 30 else ('dim' if lv > 0 else 'out'))


def paste_lantern(m, x, y, level, px=1, i=7):
    t = tier_of(level)
    if t not in _strip:
        _strip[t] = (Image.open(os.path.join(LANT, 'lantern_%s.png' % t)).convert('RGBA'),
                     json.load(open(os.path.join(LANT, 'lantern_%s.json' % t))))
    im, meta = _strip[t]
    fw, fh = meta['frameSize']
    fr = im.crop((i * fw, 0, (i + 1) * fw, fh))
    if px != 1:
        fr = fr.resize((round(fw * px), round(fh * px)), Image.NEAREST)
    pv = meta['pivot']
    m.ov.alpha_composite(fr, (int(m.P(x) - pv[0] * px), int(m.P(y) - pv[1] * px)))


HEAD = {'exusiai': (33, 24, 34), 'lappland': (19, 24, 34), 'saria': (23, 8, 40)}   # 卡片立绘里头部方块（x, y, 边长）：按各自比例统一成同样大小


def head_crop(sub, oid=None):
    if oid in HEAD:
        x, y, sd = HEAD[oid]
        return sub.crop((x, y, x + sd, y + sd))
    return _auto_head(sub)


def _auto_head(sub):
    """卡片立绘里找角色外框（比卡底亮的像素），取头部方块：统一大小"""
    g = sub.convert('L')
    w, h = g.size
    px = g.load()
    pts = [(x, y) for y in range(h) for x in range(w) if px[x, y] > 70]
    if not pts:
        return sub
    xs, ys = [p[0] for p in pts], [p[1] for p in pts]
    top, bot = min(ys), max(ys)
    side = int((bot - top) * 0.46)
    band = [p[0] for p in pts if p[1] < top + side]
    hx = sorted(band)[len(band) // 2]
    x0 = max(0, min(w - side, hx - side // 2))
    y0 = max(0, top - 1)
    return sub.crop((x0, y0, x0 + side, y0 + side))


MODE_EN = ['ESCORT', 'ASSAULT', 'DEPLOY', 'FOCUS']
STAMINA = 0.72          # 出击作战时限剩余（25 秒满）
RUSH = '攻速 +25% · 技力回复 ×1.5'   # 出击加成：突击 / 部署 / 集火共用（squad.rush_text，balance command/rush_aspd、rush_sp）
FOCUS_TGT = ('偏执泡影', 0.62)


def mode_icon(m, cx, cy, i, r, col, w=1.0):
    """四种指令的线性小图标：随行 = 队长点 + 三名队友围成弧；突击 = 双箭头；部署 = 落点菱形 + 地面线；集火 = 准星"""
    if i == 0:
        m.circle(cx, cy + r * 0.25, r * 0.22, fill=col)
        for a in (-150, -90, -30):
            t = math.radians(a)
            m.circle(cx + math.cos(t) * r * 0.75, cy + r * 0.25 + math.sin(t) * r * 0.75, r * 0.16, fill=col)
    elif i == 1:
        for dx in (-0.35, 0.2):
            m.line([(cx + (dx - 0.25) * r, cy - 0.55 * r), (cx + (dx + 0.25) * r, cy), (cx + (dx - 0.25) * r, cy + 0.55 * r)], col, w * 1.3)
    elif i == 2:
        m.line([(cx, cy - 0.75 * r), (cx + 0.45 * r, cy - 0.2 * r), (cx, cy + 0.35 * r), (cx - 0.45 * r, cy - 0.2 * r), (cx, cy - 0.75 * r)], col, w)
        m.line([(cx - 0.7 * r, cy + 0.7 * r), (cx + 0.7 * r, cy + 0.7 * r)], col, w)
    else:
        m.circle(cx, cy, r * 0.55, outline=col, w=w)
        for a in range(4):
            t = math.radians(a * 90)
            m.line([(cx + math.cos(t) * r * 0.35, cy + math.sin(t) * r * 0.35), (cx + math.cos(t) * r * 0.9, cy + math.sin(t) * r * 0.9)], col, w)
        m.circle(cx, cy, r * 0.1, fill=col)


def cmd_block(m, x, base, k, tile, eff, touch):
    """小队指令牌：左边方形图标牌（突击时外框是作战时限），右边三行：指令名 + 英文 / 当前加成 / 四种指令小图标（当前那个亮）+ F"""
    i = H.MODE_I
    ty = base - tile - 2 * k
    m.rect(x, ty, tile, tile, fill=(0, 0, 0, 120), outline=(255, 255, 255, 60), width=0.6)
    if i:   # 出击（突击 / 部署 / 集火）：作战时限 = 沿方框顺时针走的一道亮边，用掉的那段压暗
        per = 4 * tile
        left = per * STAMINA
        pts = [(x, ty), (x + tile, ty), (x + tile, ty + tile), (x, ty + tile), (x, ty)]
        m.rect(x, ty, tile, tile, outline=(255, 255, 255, 28), width=1.6)
        acc = 0
        for a, b in zip(pts, pts[1:]):
            seg = math.dist(a, b)
            if left <= acc:
                break
            t = min(1.0, (left - acc) / seg)
            m.line([a, (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)], WHITE, 1.6)
            acc += seg
        mono(m, x + tile - 1, ty + tile + 7.5 * k, '%ds' % round(25 * STAMINA), 4.6 * k, GREY, 'rs', 0.95)
    mode_icon(m, x + tile / 2, ty + tile / 2, i, tile * 0.36, WHITE, 1.2)
    tx = x + tile + 8 * k
    nw = m.text(tx, ty + 10 * k, H.MODES[i], 12 * k, WHITE, 'cn', 'ls')
    mono(m, tx + nw + 5 * k, ty + 9.5 * k, MODE_EN[i], 4.6 * k, GREY)
    if eff:
        m.text(tx, ty + 20 * k, eff, 7.2 * k, A(GREY, 235), 'cn', 'ls')
    if i == 3:   # 集火：牌子上方一行目标 + 血量细线
        nm, hp = FOCUS_TGT
        yy = ty - 6 * k
        w0 = m.text(x, yy, '目标 · ' + nm, 7.6 * k, WHITE, 'cn', 'ls')
        m.text(x + w0 + 4 * k, yy, '%d%%' % round(hp * 100), 7.6 * k, A(RED, 235), 'num', 'ls')
        bw = w0 + 26 * k
        m.rect(x, yy + 2.2 * k, bw, 1.2, fill=DIM)
        m.rect(x, yy + 2.2 * k, bw * hp, 1.2, fill=A(RED, 230))
    for j in range(4):
        ix = tx + 4 * k + j * 13 * k
        mode_icon(m, ix, base + 1 * k, j, 4.2 * k, WHITE if j == i else (255, 255, 255, 80), 0.8)
    if not touch:
        mono(m, tx + 4 * k + 4 * 13 * k + 2 * k, base + 3 * k, 'F', 5.0 * k, GREY, 'ls')


def dash_row(m, xr, ly, k, n, cd, touch, flash=False):
    """xr = 右端，ly = 文字基线。箭头：可用 = 青；充能中 = 暗底 + 从下往上回填的青色"""
    lab = '冲刺'
    tw = m.text(xr, ly, lab, 8.5 * k, A(WHITE, 220) if n else GREY, 'cn', 'rs')
    x = xr - tw - 6 * k
    ch_w, ch_h = 7 * k, 9 * k
    for j in (1, 0):   # 从右往左画：右边那格先用掉
        x0 = x - ch_w
        cy = ly - 4 * k
        pts = [(x0, cy - ch_h / 2), (x0 + ch_w * 0.45, cy - ch_h / 2), (x0 + ch_w, cy), (x0 + ch_w * 0.45, cy + ch_h / 2), (x0, cy + ch_h / 2), (x0 + ch_w * 0.55, cy)]
        P = [(m.P(a), m.P(b)) for a, b in pts]
        if j < n:
            m.d.polygon(P, fill=CYAN)
        else:
            m.d.polygon(P, fill=(255, 255, 255, 38))
            if j == n:   # 正在充能的那格：从下往上回填
                yb = cy + ch_h / 2
                yt = yb - ch_h * cd
                img = Image.new('L', m.ov.size, 0)
                ImageDraw.Draw(img).polygon(P, fill=255)
                clip = Image.new('L', m.ov.size, 0)
                ImageDraw.Draw(clip).rectangle([m.P(x0 - 1), m.P(yt), m.P(x0 + ch_w + 1), m.P(yb + 1)], fill=255)
                from PIL import ImageChops
                mask = ImageChops.multiply(img, clip)
                fill = Image.new('RGBA', m.ov.size, (CYAN[0], CYAN[1], CYAN[2], 150))
                m.ov.paste(fill, (0, 0), mask)
        x = x0 - 2.5 * k
    if flash:
        m.glow(x - 2 * k, ly - 10 * k, xr - x + 4 * k, 12 * k, A(CYAN, 170), 6)
    if not touch:
        f = font('semi', m.P(5.6 * k))
        kw = f.getlength('SPACE') / m.s + 6 * k
        kx = x - 3 * k - kw
        m.rect(kx, ly - 8.6 * k, kw, 9.4 * k, fill=(0, 0, 0, 120), outline=(255, 255, 255, 150), width=0.7)
        m.text(kx + kw / 2, ly - 3.9 * k, 'SPACE', 5.6 * k, WHITE, 'semi', 'mm')


def console(m, assets, state, touch=False):
    W, Hh = m.W, m.H
    k = 1.0 if touch else 1.25
    cx = W / 2                                   # 整台以屏幕中线对称：头像在正中，左右两翼等宽
    base = Hh - 14 * k
    r = 25 * k
    by = base - r - 7 * k
    hit, ultf = state == 'hit', state == 'ult'
    L = H.LEADER
    lamp = L['lamp']

    # ---- 主角：头像 + 终结技
    ult = 1.0 if ultf else L['ult']
    RR = r + 5 * k
    if ultf:
        m.glow(cx - RR - 8, by - RR - 8, 2 * RR + 16, 2 * RR + 16, A(CYAN, 210), 12)
        m.circle(cx, by, RR + 5 * k, outline=A(CYAN, 120), w=1.0)          # 呼吸光环（这一帧）
    m.circle(cx, by, r + 1, fill=(0, 0, 0, 160))
    m.paste_circle(assets['badge'], cx, by, r)
    # 外圈 40 格刻度：充能部分亮
    n = 40
    for j in range(n):
        a = math.radians(-90 + j * 360 / n)
        on = j < round(n * ult)
        r0, r1 = RR + 2.6 * k, RR + (5.2 if j % 10 == 0 else 3.8) * k
        m.line([(cx + math.cos(a) * r0, by + math.sin(a) * r0), (cx + math.cos(a) * r1, by + math.sin(a) * r1)],
               (CYAN if ultf else WHITE) if on else (255, 255, 255, 40), 1.0)
    m.arc(cx, by, RR, 0, 360, (255, 255, 255, 50), 3.0)
    m.arc(cx, by, RR, -90, -90 + 360 * ult, CYAN if ultf else WHITE, 3.0)
    if not ultf:
        a = math.radians(-90 + 360 * ult)
        m.circle(cx + math.cos(a) * RR, by + math.sin(a) * RR, 2.6, fill=WHITE)
    # 头像下：Q 键 + 终结技 + 百分比
    ly = base + 9 * k
    lab = '终结技 就绪' if ultf else '终结技 %d%%' % int(ult * 100)
    f = font('cn', m.P(8.5 * k))
    tw = f.getlength(lab) / m.s
    kw = 0 if touch else 11 * k
    x0 = cx - (tw + kw) / 2
    if not touch:
        m.rect(x0, ly - 8.2 * k, 8.5 * k, 9 * k, fill=CYAN if ultf else (0, 0, 0, 120), outline=CYAN if ultf else (255, 255, 255, 140), width=0.7)
        m.text(x0 + 4.25 * k, ly - 3.6 * k, 'Q', 6.2 * k, (10, 14, 16, 255) if ultf else WHITE, 'num', 'mm')
    m.text(x0 + kw, ly, lab, 8.5 * k, CYAN if ultf else A(WHITE, 220), 'cn', 'ls')

    # ---- 左：马灯 + 生命 + 灯火
    gx = cx - RR - 16 * k
    s = 34 * k
    gap = 12 * k
    eff = RUSH if H.MODE_I else '队友不受伤'
    tile = 26 * k
    blockw = tile + 8 * k + font('cn', m.P(7.2 * k)).getlength(RUSH) / m.s   # 按最长那行定宽，切指令时台子不跳
    right_ext = RR + 16 * k + 3 * (s + gap) + 2 * k + blockw
    lw = max(128 * k, right_ext - (RR + 16 * k + 56 * k))
    hp = L['hp'] - (38 if hit else 0)
    sw = m.text(gx, base - 19 * k, ' / %d' % L['hpmax'], 7.5 * k, GREY, 'num', 'rs')
    m.text(gx - sw, base - 19 * k, str(hp), 20 * k, RED if hit else WHITE, 'num', 'rs')
    m.text(gx - lw, base - 19 * k, '生命', 7.5 * k, GREY, 'cn', 'ls')
    m.text(gx - lw, base - 38 * k, H.STATUS, 8.0 * k, A(GREY, 235), 'cn', 'ls')
    hairbar(m, gx - lw, base - 12 * k, lw, hp / L['hpmax'], RED if hit else WHITE,
            trail=(L['hp'] / L['hpmax']) if hit else None, h=1.6)
    if hit:
        m.glow(gx - lw * (L['hp'] / L['hpmax']), base - 14 * k, lw * 38 / L['hpmax'], 5, A(RED, 180), 6)
    # 灯火条：生命下面
    lcol = A(GOLD, 240) if lamp >= 30 else A(RED, 230)
    hairbar(m, gx - lw, base - 4 * k, lw, lamp / 100, lcol, h=1.6, back=(255, 200, 120, 40))
    for tt in (0.3, 0.7):
        tx = gx - lw * tt
        m.line([(tx, base - 6.5 * k), (tx, base - 1.5 * k)], (255, 255, 255, 120), 0.6)
    m.text(gx - lw, base + 6.5 * k, '灯火 %d' % lamp, 7.5 * k, lcol, 'cn', 'ls')
    # 冲刺（11-05 用户「不够明显」）：和头像下「Q 终结技」同一条底线——[SPACE] 键牌 + 两格箭头 + 「冲刺」，右对齐到左翼末端
    dash_row(m, gx, base + 9 * k, k, L['dash'], L.get('dash_cd', 0.55), touch, state == 'dash')
    # 马灯：左组最外侧
    lx = gx - lw - 30 * k
    paste_lantern(m, lx, base + 4 * k, lamp, 1.5)

    # ---- 右：队友 + 指挥
    qx = cx + RR + 16 * k
    for i, mt in enumerate(H.st_mates(state)):
        x = qx + i * (s + gap)
        y = base - s - 5 * k
        dn = mt.get('down')
        face = head_crop(assets[mt['id']], mt['id'])
        m.rect(x, y, s, s, fill=(0, 0, 0, 130))
        m.paste(face, x, y, s, s, gray=bool(dn), alpha=150 if dn else 255)
        m.rect(x, y, s, s, outline=(255, 255, 255, 50), width=0.6)
        low = mt['hp'] < 0.35 and not dn
        hairbar(m, x, base - 1.5 * k, s, mt['hp'], RED if (low or dn) else WHITE, rtl=False, h=1.6)
        if dn:
            m.glow(x, y, s, s, A(RED, 200), 7)
            m.line([(x, y), (x + s, y)], RED, 1.2)
            mono(m, x + s / 2, y + s / 2 + 4, '%02d' % dn, 10 * k, RED, 'ms', 0.75)
    mx = qx + 3 * (s + gap) + 2 * k
    cmd_block(m, mx, base, k, tile, eff, touch)
    ext = max(cx - (lx - 26 * k), (mx + blockw + 4 * k) - cx)   # 两翼取宽的那边，刻度对称放
    gl, gr = cx - ext, cx + ext
    tick(m, gl, base - 50 * k, 1, 1, L=7 * k)
    tick(m, gr, base + 8 * k, -1, -1, L=7 * k)
    return Hh - (base - 50 * k)


import hud_console_1105r4 as R4
R4.console = console
R4.LANT = LANT


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
    im, p1 = R4.render(pc, 1.5, 'normal', False, assets)
    im.save(os.path.join(OUT, 'R5_pc.png'))
    im, p2 = R4.render(ph, 2.0, 'normal', True, assets)
    im.save(os.path.join(OUT, 'R5_phone.png'))
    rows = (('normal', 1.0, '常态'), ('hit', 1.0, '掉血：数字与细线转洋红 + 残影'),
            ('ult', 1.0, '终结技充满：整环 + 刻度转青、外圈光环、Q 键反色、「终结技 就绪」'),
            ('down', 1.0, '队友倒地：头像灰 + 洋红线 + 读秒'), ('normal', 0.45, '闲时：整台约 45% 不透明'))
    tiles = []
    for stt, al, lab in rows:
        im, _ = R4.render(pc, 1.5, stt, False, assets, al)
        tiles.append((im.crop((300, 860, 1620, 1080)), lab))
    tw, th = tiles[0][0].size
    sheet = Image.new('RGB', (tw, (th + 8) * len(tiles)), (16, 18, 22))
    d = ImageDraw.Draw(sheet)
    f = ImageFont.truetype(os.path.join(H.FONTS, 'ui.ttf'), 24)
    for i, (t, lab) in enumerate(tiles):
        sheet.paste(t, (0, i * (th + 8)))
        d.text((16, i * (th + 8) + 10), lab, font=f, fill=(255, 220, 120))
    sheet.save(os.path.join(OUT, 'R5_states.png'))
    # 马灯四档（4 倍）+ 动画帧
    bg = pc.crop((560, 640, 1360, 1000)).convert('RGBA')
    fdir = os.path.join(OUT, '_lamp_frames')
    os.makedirs(fdir, exist_ok=True)
    for fi in range(30):
        mm = M(bg, 1.5)
        gradient(mm, mm.H, 140)
        for j, (lv, lab) in enumerate(((90, '通明 ≥ 70'), (50, '摇曳 30–70'), (18, '暗淡 < 30'), (0, '寂灭 0'))):
            x = 70 + j * 130
            paste_lantern(mm, x, 175, lv, 3, fi)
            mm.text(x, 200, '灯火 %d' % lv, 10, A(GOLD, 230) if lv >= 30 else A(RED, 230), 'cn', 'ms')
            mm.text(x, 218, lab, 10, (230, 232, 236, 230), 'cn', 'ms')
        out = mm.done()
        out.save(os.path.join(fdir, 'f%03d.png' % fi))
        if fi == 7:
            out.save(os.path.join(OUT, 'R5_lamp.png'))
    print(p1, p2)


if __name__ == '__main__':
    main()
