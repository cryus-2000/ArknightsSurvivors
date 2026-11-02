"""docs/222 §10 第七轮：莱茵生命「编辑式」界面（用户 11-02 给的参考：github.com/tmc5csxr9m-cpu/laiyin-video 的成片截帧）。
借它的语言而不是它的装饰：几何粗体大字 + 极小的字距拉开的大写标签、实心名牌（深底白字 / 纸白底黑字）、细长结构线、
橙色细线 + 圆点的步骤指示（这里拿来当「指挥模式」选择器）、大量留白、元素极少。
拉丁大字在效果稿里用 Segoe UI Bold 代替（实现时换 Montserrat，OFL，只子集数字和大写字母）。
用法：python hud_mock_1102g.py <worktree> <输出目录>"""
import math, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import hud_mock_1102 as H
import hud_mock_1102c as G
from hud_mock_1102 import M, C, TEXT, SUB, CYAN, GOLD, OPS, RELIC, BADGE
from PIL import Image, ImageDraw, ImageFont, ImageFilter

OUT = sys.argv[2]
LATB = os.path.join(sys.argv[1], 'game', 'fonts', 'montserrat_bold.ttf')       # Montserrat Bold 子集（11-02 起游戏内同一份）
LATS = os.path.join(sys.argv[1], 'game', 'fonts', 'montserrat_semibold.ttf')   # Montserrat SemiBold 子集（小标签）
_lf = {}
PAPER = (233, 231, 225, 255)              # 纸白（名牌反白）
INK = (16, 17, 19, 255)
ORANGE = (240, 128, 48, 255)              # 步骤指示的橙
LINE = (255, 255, 255, 70)
LINE2 = (255, 255, 255, 36)
PURPLE = C(0.66, 0.52, 1.0)


def LF(path, px):
    k = (path, int(round(px)))
    if k not in _lf:
        _lf[k] = ImageFont.truetype(path, int(round(px)))
    return _lf[k]


def big(m, x, y, s, sz, col=TEXT, anchor='ls'):
    """几何粗体大字（数字 / 大写拉丁）"""
    f = LF(LATB, sz * m.s * m.fk)
    for dx, dy in ((1, 1), (0, 2)):
        m.d.text((m.P(x) + dx, m.P(y) + dy), s, font=f, fill=(0, 6, 12, 120), anchor=anchor)
    m.d.text((m.P(x), m.P(y)), s, font=f, fill=col, anchor=anchor)
    return m.d.textlength(s, font=f) / m.s


def cap(m, x, y, s, sz=7, col=SUB, sp=1.6, anchor='l'):
    """极小的字距拉开的大写标签"""
    f = LF(LATS, sz * m.s * m.fk)
    w = sum(m.d.textlength(ch, font=f) for ch in s) + sp * m.s * (len(s) - 1)
    cx = m.P(x) - (w if anchor == 'r' else (w / 2 if anchor == 'm' else 0))
    for ch in s:
        m.d.text((cx + 1, m.P(y) + 1), ch, font=f, fill=(0, 6, 12, 110), anchor='ls')
        m.d.text((cx, m.P(y)), ch, font=f, fill=col, anchor='ls')
        cx += m.d.textlength(ch, font=f) + sp * m.s
    return w / m.s


def hair(m, a, b, col=LINE, w=1):
    m.d.line([(m.P(a[0]), m.P(a[1])), (m.P(b[0]), m.P(b[1]))], fill=col, width=w)


def plate(m, x, y, w, h, fill=INK, a=0.92):
    m.rect(x, y, w, h, fill[:3] + (int(255 * a),))


def shade(m, x, y, w, h, a=0.38):
    lay = Image.new('RGBA', m.ov.size, (0, 0, 0, 0))
    ImageDraw.Draw(lay).rectangle(m.R(x, y, w, h), fill=(2, 8, 14, int(255 * a)))
    m.ov.alpha_composite(lay.filter(ImageFilter.GaussianBlur(m.P(14))))


def line_bar(m, x, y, w, frac, col, slot=(255, 255, 255, 40), h=2, marks=()):
    """一根细线做条：暗细线打底，亮线填到 frac，头上一颗小点"""
    m.rect(x, y, w, h, slot)
    m.rect(x, y, w * frac, h, col)
    m.d.ellipse(m.R(x + w * frac - 2, y + h / 2 - 2, 4, 4), fill=col)
    for t in marks:
        m.rect(x + w * t, y - 3, 1, h + 6, col)


def stepper(m, x, y, w, n, cur, labels=None, col=ORANGE):
    """步骤指示：一根橙色细线，n 颗小点，当前那颗外面一圈"""
    hair(m, (x, y), (x + w, y), col, max(1, m.P(1)))
    for k in range(n):
        cx = x + w * k / (n - 1)
        r = 2.4
        m.d.ellipse(m.R(cx - r, y - r, 2 * r, 2 * r), fill=col)
        if k == cur:
            m.d.ellipse(m.R(cx - 5, y - 5, 10, 10), outline=col, width=max(1, m.P(1.2)))
        if labels:
            cap(m, cx, y + 13, labels[k], 6, (TEXT if k == cur else SUB), 1.2, anchor='m')


# ================================================================ 件
def leader(m, x, y, phone=False):
    shade(m, x - 6, y - 6, 260 if not phone else 220, 86, 0.32)
    m.img(BADGE, x, y + 2, 60, 62)
    tx = x + 72
    cap(m, tx, y + 10, 'HP', 7)
    w = big(m, tx, y + 42, '195', 30)
    cap(m, tx + w + 6, y + 41, '/ 195', 8, SUB)
    line_bar(m, tx, y + 50, 150 if not phone else 120, 1.0, (70, 225, 240, 255))
    cap(m, tx, y + 66, 'LAMP', 7, GOLD)
    m.text(tx + 34, y + 67, '100', 10, GOLD, bold=True)
    line_bar(m, tx + 58, y + 63, (150 if not phone else 120) - 58, 1.0, GOLD, marks=(0.3, 0.7))
    # 结构线：从徽记下沿竖下去，到状态行
    hair(m, (x + 30, y + 66), (x + 30, y + 92), LINE2)


def status(m, x, y, phone=False):
    items = ['灯火通明', '护盾 ×1', '攻速 +70%', '认知负担']
    if phone:
        items = items[:2] + ['+2']
    hair(m, (x, y - 4), (x + 22, y - 4), LINE)
    xx = x + 28
    for k, s in enumerate(items):
        xx += m.text(xx, y, s, 10, (230, 232, 230, 235)) + 8
        if k < len(items) - 1:
            m.text(xx - 4, y, '/', 10, SUB)
            xx += 6


def top_bar(m, y0=10, compact=False):
    W = m.W
    cx = W / 2
    shade(m, cx - 170, y0 - 4, 340, 48 if compact else 96, 0.26)
    cap(m, cx - 20, y0 + 10, 'KILLS', 7, anchor='r')
    big(m, cx - 20, y0 + 38, '1910', 26, anchor='rs')
    hair(m, (cx, y0 + 6), (cx, y0 + 38), LINE)
    cap(m, cx + 20, y0 + 10, 'TIME', 7)
    big(m, cx + 20, y0 + 38, '10:35', 26)
    if not compact:
        m.text(cx, y0 + 60, '深蓝之树', 11, SUB, anchor='ms')
        cap(m, cx, y0 + 72, 'BLUE TREE  ·  THREAT VI', 6, (150, 160, 170, 255), anchor='m')
    by = y0 + (90 if not compact else 52)
    bw = 520 if not compact else 300
    # Boss：小黑签 TARGET + 名字 + 一根紫细线
    plate(m, cx - bw / 2, by - 13, 44, 12)
    cap(m, cx - bw / 2 + 5, by - 4, 'TARGET', 6, TEXT, 1.0)
    m.text(cx - bw / 2 + 50, by - 3, '偏执泡影', 11, TEXT, bold=True)
    cap(m, cx + bw / 2, by - 4, '55%', 7, PURPLE, anchor='r')
    line_bar(m, cx - bw / 2, by + 2, bw, 0.55, PURPLE, h=3)


def info(m, phone=False):
    W = m.W
    # 藏品：大数字 + 小标签，最近几件在右边一排，没有框
    x = W - 16 - 96 - (44 if phone else 132)
    cap(m, x, 22, 'RELICS', 7)
    big(m, x, 46, '15', 22)
    if not phone:
        for k in range(3):
            m.img(RELIC[k], x + 36 + k * 30, 26, 24, 24)
        hair(m, (x, 54), (x + 124, 54), LINE2)
    # 暂停 / 倍速：两块纸白小名牌（反白），倍速 ≠ 1 时变橙
    for i, s in enumerate(['II', '×1.0']):
        px = W - 16 - 84 + i * 44
        plate(m, px, 16, 40, 30, PAPER, 0.92)
        f = LF(LATB, (14 if i == 0 else 12) * m.s * m.fk)
        m.d.text((m.P(px + 20), m.P(31)), s, font=f, fill=INK, anchor='mm')
    if not phone:
        cap(m, W - 16, 60, 'SPEED', 6, SUB, anchor='r')


def squad(m, x, y, phone=False):
    """右下：指挥 = 大字模式名 + 橙色步骤指示（四个模式，当前那颗带圈）；
    下面四个立绘窗（@2x 半身），窗下实心黑名牌（白字），队长名牌上压一个小签 LEADER；生命是名牌下的一根细线"""
    cw = 72 if not phone else 50
    ch = 66 if not phone else 46
    gap = 8 if not phone else 6
    W = 4 * cw + 3 * gap
    shade(m, x - 10, y - 8, W + 20, ch + (98 if not phone else 66), 0.34)
    # 指挥
    cap(m, x, y + 8, 'COMMAND' + ('  ·  F' if not phone else ''), 7)
    big(m, x, y + 34, '', 1)
    m.text(x, y + 33, '随行', 18, TEXT, bold=True)
    if not phone:
        stepper(m, x + 70, y + 22, W - 160, 4, 0, ['FOLLOW', 'ASSAULT', 'DEPLOY', 'FOCUS'])
        cap(m, x + W, y + 8, 'SQUAD 4/4', 7, anchor='r')
        cap(m, x + W, y + 22, 'BOND 2', 7, GOLD, anchor='r')
        line_bar(m, x + W - 60, y + 30, 60, 0.35, (70, 225, 240, 255), h=1)
    else:
        stepper(m, x + 50, y + 26, W - 60, 4, 0)
    oy = y + (52 if not phone else 50)
    for i, (nm, cls, hp) in enumerate(OPS):
        cx0 = x + i * (cw + gap)
        m.rect(cx0, oy, cw, ch, (10, 12, 14, 200))
        G_portrait(m, cx0, oy, cw, ch, i)
        # 名牌
        nh = 14 if not phone else 0
        if not phone:
            plate(m, cx0, oy + ch, cw, nh, INK if i else PAPER, 0.95)
            m.text(cx0 + 5, oy + ch + 11, nm[:4], 9, TEXT if i else INK, bold=True)
            m.rect(cx0 + cw - 6, oy + ch + 4, 3, 6, H.CLS[cls])
        if i == 0:
            plate(m, cx0, oy - 11, 40, 11, PAPER if phone else INK)
            cap(m, cx0 + 4, oy - 2.5, 'LEADER', 5.5, INK if phone else TEXT, 0.9)
        # 生命细线（队长不画，生命在左上）
        if i:
            line_bar(m, cx0, oy + ch + nh + 4, cw, hp, (70, 225, 240, 255) if hp > 0.5 else GOLD, h=2)
        if i in (1, 2):
            H.M.diamond(m, cx0 + cw - 5, oy + 5, 2.6, GOLD)
    return W


def G_portrait(m, x, y, w, h, i):
    """@2x 待机帧上半身，整数倍放大，裁进窗口"""
    src = G.HI[i]
    s = src.crop((0, 0, src.size[0], int(src.size[1] * 0.56)))
    k = max(1, round(m.P(h) / s.size[1]))
    t = s.resize((s.size[0] * k, s.size[1] * k), Image.NEAREST)
    lay = Image.new('RGBA', m.ov.size, (0, 0, 0, 0))
    lay.alpha_composite(t, (m.P(x + w / 2) - t.size[0] // 2, m.P(y + 1)))
    mk = Image.new('L', m.ov.size, 0)
    ImageDraw.Draw(mk).rectangle(m.R(x, y, w, h), fill=255)
    m.ov.alpha_composite(Image.composite(lay, Image.new('RGBA', m.ov.size, (0, 0, 0, 0)), mk))


def guide(m, x, y, w):
    """指南卡：纸白底（反白，像片子里的纸面）+ 黑字；左边一个黑色大块写步骤号，右边标题 + 一句话 + 做完条件；上沿橙色步骤指示"""
    h = 112
    plate(m, x, y, w, h, PAPER, 0.96)
    plate(m, x, y, 92, h, INK, 1.0)
    f = LF(LATB, 40 * m.s)
    m.d.text((m.P(x + 46), m.P(y + 56)), '02', font=f, fill=(240, 240, 236, 255), anchor='mm')
    f2 = LF(LATS, 7 * m.s)
    m.d.text((m.P(x + 46), m.P(y + 84)), 'STEP / 06', font=f2, fill=(170, 170, 170, 255), anchor='mm')
    cap(m, x + 106, y + 18, 'TUTORIAL', 7, (90, 90, 90, 255))
    stepper(m, x + w - 120, y + 15, 104, 6, 1)
    m.text(x + 106, y + 44, '经验与升级', 17, INK, bold=True)
    hair(m, (x + 106, y + 52), (x + 230, y + 52), (20, 20, 20, 255), max(1, m.P(1)))
    m.text(x + 106, y + 72, '拾取经验结晶，经验条满了就升级，三张卡里选一张。', 10, (40, 42, 44, 255))
    m.rect(x + 106, y + 86, 6, 6, ORANGE)
    m.text(x + 118, y + 93, '捡起附近的经验结晶', 10, INK, bold=True)
    cap(m, x + w - 10, y + 104, 'POWERED BY RHODES ISLAND', 5.5, (120, 120, 120, 255), anchor='r')


# ================================================================ 组装
def desktop():
    m = M(H.DESK_BG, 1.5)
    W, Hh = m.W, m.H
    leader(m, 20, 14)
    status(m, 20, 116)
    top_bar(m)
    info(m)
    W4 = 4 * 72 + 3 * 8
    squad(m, W - 24 - W4, Hh - 24 - (52 + 66 + 20))
    H.minimap(m, 16, Hh - 16 - 130, 130)
    H.key_hints(m)
    return m.done(os.path.join(OUT, 'R7_RL_desktop.png'), '莱茵生命 · 编辑式（电脑 1920×1080）')


def phone():
    m = M(H.PH_BG, 1.25, 1.0)
    W, Hh = m.W, m.H
    leader(m, 14, 10, phone=True)
    status(m, 14, 110, phone=True)
    top_bar(m, 6, compact=True)
    info(m, phone=True)
    H.phone_buttons(m, '随行', speed=False, pause=False)
    W4 = 4 * 50 + 3 * 6
    squad(m, W - 16 - W4, Hh - 14 - (50 + 46 + 6), phone=True)
    H.minimap(m, 10, Hh - 10 - 84, 84)
    return m.done(os.path.join(OUT, 'R7_RL_phone.png'), '莱茵生命 · 编辑式（手机横屏）')


NOTES = [
    'TYPE   几何粗体大字（数字 / 模式名）+ 极小的字距拉开的大写标签；层级只靠字号与粗细对比，不靠框',
    'PLATE  实心名牌：队友深底白字、队长纸白底黑字；暂停 / 倍速是两块纸白小名牌',
    'LINE   细长结构线：生命 / 灯火 / Boss / 队友生命都是一根细线 + 头上一颗点；徽记下一条竖向结构线',
    'STEP   橙色细线 + 圆点的步骤指示：指挥模式四档（随行 / 突击 / 部署 / 集火），当前那颗带圈；指南卡六步同款',
    'SPACE  没有面板，只有一片很淡的暗晕托住文字；手机去掉名牌、标签和最近藏品',
    'MOTION 数字变化时上下滚一格；切模式时圆圈沿橙线滑到新位置；指南卡从纸白里划出',
]


def detail():
    bg = H.DESK_BG.crop((560, 480, 1520, 1020)).resize((1920, 1080))
    m = M(bg, 2.0)
    m.rect(0, 0, m.W, m.H, C(0.01, 0.02, 0.03, 0.45))
    leader(m, 26, 24)
    status(m, 26, 128)
    m.W = 940
    info(m)
    m.W = 960
    squad(m, 26, 170)
    guide(m, 420, 170, 500)
    y = 368
    for k, s in enumerate(NOTES):
        tag_, rest = s.split(' ', 1)
        cap(m, 26, y + k * 24, tag_, 8, (240, 128, 48, 255))
        m.text(96, y + k * 24, rest.strip(), 10, C(0.95, 0.93, 0.85))
    return m.done(os.path.join(OUT, 'R7_RL_detail.png'), '莱茵生命 · 编辑式 · 件的放大（2 倍）')


if __name__ == '__main__':
    os.makedirs(OUT, exist_ok=True)
    d, p, dt = desktop(), phone(), detail()
    dw = 960
    dh = int(d.size[1] * dw / d.size[0])
    sheet = Image.new('RGB', (dw * 2 + 12, dh * 2 + 12), (12, 14, 18))
    sheet.paste(Image.open(os.path.join(OUT, 'R6_PR_desktop.png')).convert('RGB').resize((dw, dh)), (0, 0))
    sheet.paste(d.convert('RGB').resize((dw, dh)), (dw + 12, 0))
    sheet.paste(dt.convert('RGB').resize((dw, dh)), (0, dh + 12))
    sheet.paste(p.convert('RGB').resize((dw, int(p.size[1] * dw / p.size[0]))), (dw + 12, dh + 12))
    sheet.save(os.path.join(OUT, 'R7_overview.png'))
    print('ok')
