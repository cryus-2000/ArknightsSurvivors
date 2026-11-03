"""docs/222 §9 第六轮：PRTS 终端 × 莱茵生命（用户 11-02「能不能在 PRTS 的风格上进一步优化？配点莱茵生命的设计风格」）。
莱茵生命的视觉线索取自 PRTS 塞雷娅页立绘（ref/prts_saria_rhinelab.jpg）：白底、黑色束带、细橙红色条、盾面「+」字菱形格、黑白斜向分割。
叠到第五轮 PRTS 终端上：白色实心标签块（黑字等宽编号，像实验样本标签）、黑白斜切分割的徽记底、细橙红结构线、面板里极淡的「+」字点阵、
编队窗背后的菱形格。颜色语义不动（青 = 可选 / 当前模式，金 = 灯火，UI.PURPLE / VIOLET = 队长）；橙红只做结构线，不表意。
用法：python hud_mock_1102f.py <worktree> <输出目录>"""
import math, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import hud_mock_1102 as H
import hud_mock_1102c as G
import hud_mock_1102d as R
import hud_mock_1102e as P
from hud_mock_1102 import M, C, TEXT, SUB, CYAN, GOLD, VIOLET, OPS, RELIC, BADGE
from hud_mock_1102b import chamfer, poly, line, mono, dotted
from PIL import Image, ImageDraw

OUT = sys.argv[2]
WHITE = (238, 240, 236, 255)
INKC = (14, 16, 18, 255)
RHINE = (232, 92, 46, 255)      # 莱茵橙红：只做结构细线 / 小色条
HAIR = P.HAIR
HAIR2 = P.HAIR2
PURPLE = P.PURPLE
sh = R.shadow_text
segbar = P.segbar


def tag(m, x, y, s, sz=7, fill=WHITE, ink=INKC, pad=4):
    """白色实心标签块 + 黑字等宽（实验样本标签）"""
    w = (sz * 0.62 + 1.2) * len(s) + pad * 2
    m.rect(x, y - sz - 3, w, sz + 5, fill)
    mono(m, x + pad, y, s, sz, ink)
    return w


def plus_grid(m, x, y, w, h, gap=14, a=0.10, clip=None):
    """面板里极淡的「+」字点阵"""
    col = (255, 255, 255, int(255 * a))
    yy = y + gap / 2
    while yy < y + h:
        xx = x + gap / 2
        while xx < x + w:
            line(m, (xx - 2, yy), (xx + 2, yy), col, 1)
            line(m, (xx, yy - 2), (xx, yy + 2), col, 1)
            xx += gap
        yy += gap


def lattice(m, x, y, w, h, gap=10, col=(255, 255, 255, 22)):
    """菱形格（塞雷娅盾面）：两组 45° 细线，裁进矩形"""
    W_, H_ = m.P(w), m.P(h)
    lay = Image.new('RGBA', (W_, H_), (0, 0, 0, 0))
    d = ImageDraw.Draw(lay)
    g = m.P(gap)
    for k in range(-H_, W_ + H_, g):
        d.line([(k, 0), (k + H_, H_)], fill=col, width=1)
        d.line([(k, H_), (k + H_, 0)], fill=col, width=1)
    m.ov.alpha_composite(lay, (m.P(x), m.P(y)))


def split_plate(m, x, y, w, h):
    """黑白斜向分割底板：左上白三角、右下黑，中间一道橙红细线"""
    poly(m, [(x, y), (x + w * 0.62, y), (x, y + h * 0.9)], fill=(236, 238, 234, 235))
    poly(m, [(x + w * 0.62, y), (x + w, y), (x + w, y + h), (x, y + h), (x, y + h * 0.9)], fill=(10, 12, 14, 220))
    line(m, (x + w * 0.62, y), (x, y + h * 0.9), RHINE, 1.4)


def strap(m, x, y, w, col=INKC, h=4):
    """黑色束带：一段实心横条 + 两端各一颗白色铆点"""
    m.rect(x, y, w, h, col)
    for xx in (x + 3, x + w - 5):
        m.rect(xx, y + h / 2 - 1, 2, 2, WHITE)


# ================================================================ 件
def leader(m, x, y, phone=False):
    w = 236 if not phone else 196
    R.soft_shade(m, x - 6, y - 6, w + 12, 80, a=0.34)
    split_plate(m, x - 2, y + 2, 70, 70)
    m.img(BADGE, x + 2, y + 6, 62, 64)
    tx = x + 76
    tw = tag(m, tx, y + 4, 'OP-00')
    mono(m, tx + tw + 6, y + 4, 'LEADER', 7, SUB)
    line(m, (x + 66, y + 30), (tx - 2, y + 30), RHINE, 1)
    mono(m, tx, y + 21, 'HP', 8, SUB)
    P.readout(m, tx + 16, y + 23, '195', '/195', 16)
    segbar(m, tx, y + 27, w - 80, 1.0, CYAN, n=30, h=5, ticks=10)
    mono(m, tx, y + 52, 'LMP', 8, SUB)
    P.readout(m, tx + 22, y + 54, '100', '', 12, GOLD)
    segbar(m, tx + 48, y + 48, w - 128, 1.0, GOLD, n=20, h=3, marks=(0.3, 0.7))
    strap(m, tx, y + 64, w - 80, h=3)


def status(m, x, y, phone=False):
    items = [('灯火通明', GOLD), ('护盾 ×1', CYAN), ('攻速 +70%', GOLD), ('认知负担', PURPLE)]
    if phone:
        items = items[:2] + [('+2', SUB)]
    tag(m, x, y, 'LOG', 7)
    xx = x + 26
    for k, (s, col) in enumerate(items):
        m.rect(xx, y - 7, 2, 8, col)
        xx += 5
        xx += sh(m, xx, y, s, 10, TEXT) + 6
        if k < len(items) - 1:
            line(m, (xx, y - 3), (xx + 6, y - 3), HAIR, 1)
            xx += 10


def top_bar(m, y0=10, compact=False):
    W = m.W
    cx = W / 2
    R.soft_shade(m, cx - 170, y0 - 4, 340, 44 if compact else 92, a=0.28)
    tag(m, cx - 118, y0 + 8, 'KILL', 6)
    sh(m, cx - 118, y0 + 31, '1910', 22, TEXT, bold=True)
    line(m, (cx, y0 + 6), (cx, y0 + 30), RHINE, 1)
    tag(m, cx + 14, y0 + 8, 'T+', 6)
    sh(m, cx + 14, y0 + 31, '10:35', 22, TEXT, bold=True)
    if not compact:
        sh(m, cx, y0 + 53, '深蓝之树 · 威胁 VI', 11, SUB, anchor='ms')
    by = y0 + (78 if not compact else 47)
    bw = 520 if not compact else 300
    tw = tag(m, cx - bw / 2, by - 3, 'TARGET', 6, fill=(188, 160, 255, 255))
    sh(m, cx - bw / 2 + tw + 6, by - 3, '偏执泡影', 11, TEXT)
    mono(m, cx + bw / 2, by - 4, '055%', 8, PURPLE, anchor='r')
    segbar(m, cx - bw / 2, by, bw, 0.55, PURPLE, n=60, h=4)


def info(m, phone=False):
    W = m.W
    n = 3 if not phone else 0
    w = 70 + n * 28
    x = W - 16 - 82 - w
    p = chamfer(x, 14, w, 30, 7, 'tr,bl')
    poly(m, p, fill=C(0.02, 0.035, 0.045, 0.78))
    plus_grid(m, x + 2, 16, w - 4, 26, gap=10, a=0.08)
    poly(m, p, outline=HAIR)
    m.rect(x, 14, 3, 30, RHINE)
    tag(m, x + 8, 25, 'RELIC', 6)
    sh(m, x + 9, 41, '15', 13, TEXT, bold=True)
    for k in range(n):
        m.rect(x + 44 + k * 28, 17, 24, 24, C(0, 0, 0, 0.4), outline=HAIR2)
        m.img(RELIC[k], x + 45 + k * 28, 18, 22, 22)
    for i, (val, on) in enumerate([('Ⅱ', False), ('×1.0', False)]):
        px = W - 16 - 76 + i * 40
        p = chamfer(px, 14, 36, 30, 6, 'tr,bl')
        poly(m, p, fill=C(0.02, 0.035, 0.045, 0.78))
        poly(m, p, outline=(CYAN if on else HAIR))
        m.text(px + 18, 35, val, 11 if i else 12, TEXT, anchor='ms', bold=True)


def portrait(m, x, y, w, h, i):
    P.portrait(m, x, y, w, h, i)


def squad(m, x, y, phone=False):
    cw = 64 if not phone else 46
    ch = 64 if not phone else 46
    gap = 8 if not phone else 6
    n = 4
    W = n * cw + (n - 1) * gap
    R.soft_shade(m, x - 8, y - 8, W + 16, ch + (66 if not phone else 46), a=0.32)
    # 指令行：白色标签「CMD」+ 青色大字；橙红竖条；时限是束带式刻度
    m.rect(x, y + 2, 2.5, 18, RHINE)
    tag(m, x + 7, y + 9, 'CMD', 6)
    sh(m, x + 7, y + 22, '随行', 13, CYAN, bold=True)
    if not phone:
        m.keycap(x + 44, y + 9, 'F', 9, SUB)
        mono(m, x + 66, y + 8, 'OPS-T', 7, SUB)
        segbar(m, x + 66, y + 12, 90, 0.35, CYAN, n=18, h=3)
        tag(m, x + W - 62, y + 9, 'SQUAD 4/4', 6)
        mono(m, x + W, y + 21, 'BOND 02', 7, GOLD, anchor='r')
    else:
        segbar(m, x + 40, y + 14, 70, 0.35, CYAN, n=14, h=3)
    oy = y + 28
    for i, (nm, cls, hp) in enumerate(OPS):
        cx0 = x + i * (cw + gap)
        p = chamfer(cx0, oy, cw, ch, 7, 'tr')
        poly(m, p, fill=C(0.02, 0.035, 0.045, 0.88))
        lattice(m, cx0 + 1, oy + 1, cw - 2, ch - 2, gap=8 if not phone else 6)
        portrait(m, cx0, oy + 2, cw, ch - 2, i)
        poly(m, p, outline=(PURPLE if i == 0 else HAIR))
        # 窗底一条黑色束带，名字白字压在上面（手机只留束带）
        strap(m, cx0, oy + ch - (12 if not phone else 4), cw, h=(12 if not phone else 4))
        if not phone:
            m.text(cx0 + cw / 2, oy + ch - 2.5, nm[:4], 8, TEXT, anchor='ms', bold=True)
        # 左上白色编号签（职业色一竖）
        tw = tag(m, cx0 + 2, oy + 10, '%02d' % (i + 1), 6)
        m.rect(cx0 + 2 + tw, oy + 3, 2, 8, H.CLS[cls])
        if i in (1, 2):
            H.M.diamond(m, cx0 + cw - 6, oy + 7, 2.6, GOLD)
        if i:
            segbar(m, cx0, oy + ch + 3, cw, hp, (70, 225, 240, 255) if hp > 0.5 else GOLD, n=10, h=3)
        else:
            segbar(m, cx0, oy + ch + 3, cw, 1.0, PURPLE, n=10, h=3)
            line(m, (cx0 - 3, oy - 3), (cx0 + 9, oy - 3), PURPLE, 1.5)
            line(m, (cx0 - 3, oy - 3), (cx0 - 3, oy + 9), PURPLE, 1.5)
        if not phone:
            for q in range(3):
                m.rect(cx0 + 6 + q * 7, oy + ch + 9, 5, 3, [GOLD, CYAN, C(1, 1, 1, 0.25)][q])
    return W


def guide(m, x, y, w):
    h = 108
    p = chamfer(x, y, w, h, 12, 'tr,bl')
    poly(m, p, fill=C(0.02, 0.035, 0.045, 0.84))
    plus_grid(m, x + w * 0.62, y + 6, w * 0.36, 26, gap=12, a=0.07)   # 只在右上角一小片，不压正文
    poly(m, p, outline=HAIR)
    m.rect(x, y, 3, h, RHINE)
    tag(m, x + 10, y - 2, 'TUTORIAL 02/06', 7)
    mono(m, x + w - 6, y - 5, 'RHODES ISLAND // LOG', 7, SUB, anchor='r')
    split_plate(m, x + 10, y + 12, 104, 84)
    m.rect(x + 14, y + 16, 96, 76, C(0, 0.01, 0.02, 0.72))
    lattice(m, x + 14, y + 16, 96, 76, gap=9)
    G.pix(m, G.HI[0], x + 44, y + 30, 50)
    for dx, dy in [(16, 18), (88, 16), (92, 66), (20, 64)]:
        H.M.diamond(m, x + 10 + dx, y + 12 + dy, 3, C(0.55, 1.0, 0.78))
    sh(m, x + 126, y + 32, '经验与升级', 14, TEXT, bold=True)
    m.text(x + 126, y + 54, '拾取经验结晶，经验条满了就升级，三张卡里选一张。', 10, TEXT)
    sh(m, x + 126, y + 84, '> 捡起附近的经验结晶', 10, CYAN)
    dotted(m, x + 262, x + w - 40, y + 80, HAIR, 3)
    mono(m, x + w - 10, y + 84, '0/1', 8, CYAN, anchor='r')
    for k in range(6):
        c = CYAN if k < 1 else (C(0.212, 0.886, 0.863, 0.5) if k == 1 else C(1, 1, 1, 0.12))
        m.rect(x + w - 10 - (6 - k) * 13, y + 12, 10, 3, c)


# ================================================================ 组装
def desktop():
    m = M(H.DESK_BG, 1.5)
    W, Hh = m.W, m.H
    leader(m, 18, 14)
    status(m, 20, 104)
    top_bar(m)
    info(m)
    cw, gap = 64, 8
    w = 4 * cw + 3 * gap
    squad(m, W - 22 - w, Hh - 22 - (28 + 64 + 14))
    H.minimap(m, 16, Hh - 16 - 130, 130)
    H.key_hints(m)
    return m.done(os.path.join(OUT, 'R6_PR_desktop.png'), 'PRTS 终端 × 莱茵生命（电脑 1920×1080）')


def phone():
    m = M(H.PH_BG, 1.25, 1.0)
    W, Hh = m.W, m.H
    leader(m, 14, 10, phone=True)
    status(m, 16, 96, phone=True)
    top_bar(m, 6, compact=True)
    info(m, phone=True)
    H.phone_buttons(m, '随行', speed=False, pause=False)
    cw, gap = 46, 6
    w = 4 * cw + 3 * gap
    squad(m, W - 16 - w, Hh - 14 - (28 + 46 + 8), phone=True)
    H.minimap(m, 10, Hh - 10 - 84, 84)
    return m.done(os.path.join(OUT, 'R6_PR_phone.png'), 'PRTS 终端 × 莱茵生命（手机横屏）')


NOTES = [
    ('标签', '白色实心块 + 黑字等宽编号（OP-00、CMD、RELIC、TUTORIAL 02/06）：实验样本标签的感觉，代替上一版的青色小字'),
    ('分割', '徽记底板和指南卡演示窗用黑白斜向分割，中间一道橙红细线（塞雷娅立绘背景的黑白斜切）'),
    ('束带', '队长读数下、编队窗底是黑色束带 + 两颗白铆点，名字白字压在束带上'),
    ('纹理', '面板里极淡的「+」字点阵；编队窗、演示窗背后是菱形格（塞雷娅盾面）'),
    ('橙红', '只做结构线：引线、竖条、分割线、信息条左边一竖；不表示危险（危险仍是 UI.RED 洋红）'),
    ('不变', 'PRTS 终端的发丝线、斜切、分段读数条、@2x 半身窗、少框留白、手机减半都保留'),
]


def detail():
    bg = H.DESK_BG.crop((560, 480, 1520, 1020)).resize((1920, 1080))
    m = M(bg, 2.0)
    m.rect(0, 0, m.W, m.H, C(0.01, 0.02, 0.03, 0.45))
    leader(m, 24, 26)
    status(m, 26, 118)
    m.W = 940
    info(m)
    m.W = 960
    squad(m, 26, 160)
    guide(m, 420, 154, 500)
    y = 350
    for k, (a, b) in enumerate(NOTES):
        tag(m, 26, y + k * 26, a, 8)
        m.text(80, y + k * 26, b, 10, C(0.95, 0.93, 0.85))
    return m.done(os.path.join(OUT, 'R6_PR_detail.png'), 'PRTS 终端 × 莱茵生命 · 件的放大（2 倍）')


if __name__ == '__main__':
    os.makedirs(OUT, exist_ok=True)
    d, p, dt = desktop(), phone(), detail()
    prev = Image.open(os.path.join(OUT, 'R5_P_desktop.png')).convert('RGB')
    dw = 960
    dh = int(d.size[1] * dw / d.size[0])
    pw = int(p.size[0] * dh / p.size[1])
    sheet = Image.new('RGB', (dw * 2 + 12, dh * 2 + 12), (12, 14, 18))
    sheet.paste(prev.resize((dw, dh)), (0, 0))
    sheet.paste(d.convert('RGB').resize((dw, dh)), (dw + 12, 0))
    sheet.paste(dt.convert('RGB').resize((dw, dh)), (0, dh + 12))
    sheet.paste(p.convert('RGB').resize((dw, int(p.size[1] * dw / p.size[0]))), (dw + 12, dh + 12))
    sheet.save(os.path.join(OUT, 'R6_vs_R5.png'))
    print('ok')
