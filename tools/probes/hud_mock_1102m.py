"""docs/222 §16.1：等级不要框（用户 11-02「都很丑」）——三种纯排版：
A 读数列：徽记右侧先一列「LV / 28」，竖发丝线隔开再接 HP；
B 经验条：屏幕最上沿经验细条左端「LV 28」+ 经验百分比（等级本来就跟经验走）；
C 徽记头顶：无框小字「LV」+ 粗体数字 + 下面一根短发丝线。
用法：python hud_mock_1102m.py <worktree> <输出目录>"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import hud_mock_1102 as H
import hud_mock_1102h as E
import hud_mock_1102j as J
import hud_mock_1102l as L
from hud_mock_1102 import M, TEXT, SUB, CYAN, GOLD
from PIL import Image, ImageDraw

OUT = sys.argv[2]
XP = (140, 255, 199, 255)   # 经验条同色 #8cffc7


def shadowed(m, x, y, s, sz, col, anchor='ls'):
    f = E.LF(E.LATB, sz * m.s)
    for dx, dy in ((1, 1), (0, 2)):
        m.d.text((m.P(x) + dx, m.P(y) + dy), s, font=f, fill=(0, 6, 12, 140), anchor=anchor)
    m.d.text((m.P(x), m.P(y)), s, font=f, fill=col, anchor=anchor)
    return m.d.textlength(s, font=f) / m.s


def readouts(m, x, y, tx, phone):
    E.cap(m, tx, y + 10, 'HP', 7)
    w = E.big(m, tx, y + 38, '195', 26)
    E.cap(m, tx + w + 6, y + 37, '/ 195', 8, SUB)
    E.line_bar(m, tx, y + 46, 150 if not phone else 120, 1.0, (70, 225, 240, 255))
    E.cap(m, tx, y + 62, 'LAMP', 7, GOLD)
    m.text(tx + 34, y + 63, '100', 10, GOLD, bold=True)
    E.line_bar(m, tx + 58, y + 59, (150 if not phone else 120) - 58, 1.0, GOLD, marks=(0.3, 0.7))


def make(variant):
    def leader(m, x, y, phone=False):
        m.img(L.BADGE_CLEAN, x, y + 2, 60, 62)
        if variant == 'A':
            lx = x + 70
            E.cap(m, lx, y + 10, 'LV', 7)
            shadowed(m, lx, y + 38, '28', 20, TEXT)
            E.hair(m, (lx + 30, y + 6), (lx + 30, y + 66), E.LINE)
            readouts(m, lx + 40, y, lx + 40, phone)
        elif variant == 'B':
            # 顶部经验细条：全宽 3 像素，左端「LV 28」压在条下方
            W = m.W
            m.rect(0, 0, W, 3, (255, 255, 255, 30))
            m.rect(0, 0, W * 0.62, 3, XP)
            E.cap(m, x - 4, y + 5, 'LV', 6.5, XP, 1.0)
            w_ = shadowed(m, x + 9, y + 6, '28', 10, TEXT)
            m.text(x + 12 + w_, y + 5.5, '62%', 7, SUB)
            readouts(m, x, y, x + 72, phone)
        elif variant == 'D':
            # 徽记正下方（Q 键牌下面）：一根青色短线 + 小字 LV + 粗体数字，居中
            cx = x + 30
            E.hair(m, (cx - 16, y + 70), (cx + 16, y + 70), CYAN, max(1, m.P(1)))
            E.cap(m, cx - 16, y + 82, 'LV', 6, SUB, 1.0)
            shadowed(m, cx - 3, y + 83, '28', 12, TEXT)
            readouts(m, x, y, x + 72, phone)
        elif variant == 'E':
            # 灯火那行下面：读数列最后一行「LV 28」，和 HP / LAMP 同一列
            readouts(m, x, y, x + 72, phone)
            E.cap(m, x + 72, y + 80, 'LV', 7)
            shadowed(m, x + 92, y + 81, '28', 11, TEXT)
        else:
            cx = x + 30
            E.cap(m, cx - 13, y + 2, 'LV', 6, SUB, 1.0)
            shadowed(m, cx - 1, y + 4, '28', 12, TEXT)
            E.hair(m, (cx - 14, y + 7), (cx + 18, y + 7), CYAN, max(1, m.P(1)))
            readouts(m, x, y, x + 72, phone)
    return leader


if __name__ == '__main__':
    cur = H.DESK_FULL.convert('RGB').crop((0, 0, 420, 190)).resize((840, 380), Image.NEAREST)
    cells = [('现行', cur)]
    for v, lab in [('A', 'A 读数列：LV 和 HP 并排'), ('C', 'C 徽记头顶：无框小字 + 一根线'), ('D', 'D 徽记下面（Q 键牌下）'), ('E', 'E 灯火那行下面（同一列）')]:
        E.leader = make(v)
        _st = E.status
        if v in ('D', 'E'):
            E.status = lambda m, x, y, phone=False, _f=_st: _f(m, x, y + 12, phone)   # 等级放下面时状态行再让一行
        im = J.frame(False, 0, False, 'R15_lv_%s.png' % v)
        E.status = _st
        cells.append((lab, im.convert('RGB').crop((0, 48, 420, 48 + 190)).resize((840, 380), Image.NEAREST)))
    sheet = Image.new('RGB', (2 * 856, 3 * 430), (12, 14, 18))
    d = ImageDraw.Draw(sheet)
    for i, (lab, c) in enumerate(cells):
        x, y = (i % 2) * 856, (i // 2) * 430
        sheet.paste(c, (x, y + 44))
        d.text((x + 12, y + 22), lab, font=H.FBF(24), fill=(255, 236, 170), anchor='lm')
    sheet.save(os.path.join(OUT, 'R16_lv_below.png'))
    print('ok')
