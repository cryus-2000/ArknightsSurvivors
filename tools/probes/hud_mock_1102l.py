"""docs/222 §16：等级重新设计（用户 11-02「等级那里能不能重新设计一下，现在那个框有点丑，可以用生图工具来做一下」）。
pixgen 出 4 块无字等级底牌（build/imagegen/lvplate，像素化 48），游戏里用 Montserrat 叠「LV」+ 数字；外加 1 个纯排版方案对照。
B′ 徽记本体（头像环 + Q）不改，只换掉顶上的 LV 框。效果稿里旧 LV 框用同帧无界面底图补回、补画环顶。
用法：python hud_mock_1102l.py <worktree> <输出目录>"""
import glob, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import hud_mock_1102 as H
import hud_mock_1102h as E
import hud_mock_1102j as J
from hud_mock_1102 import M, C, TEXT, SUB, CYAN
from PIL import Image, ImageDraw

WT, OUT = sys.argv[1], sys.argv[2]
PLATES = [Image.open(p).convert('RGBA') for p in sorted(glob.glob(os.path.join(WT, 'build', 'imagegen', 'lvplate', 'pix_*_?.png')))]


def clean_badge():
    """B′ 徽记去掉 LV 框：框所在区域换成无界面底图，补一段外环"""
    full = H.DESK_FULL.copy()
    bg = H.DESK_BG
    box = (8, 4, 112, 45)
    full.paste(bg.crop(box), box[:2])
    d = ImageDraw.Draw(full)
    d.arc((19, 23, 103, 107), 200, 340, fill=(52, 62, 72, 255), width=1)
    return full.crop((14, 6, 108, 118))


BADGE_CLEAN = clean_badge()


def lv_number(m, cx, cy, n='28', big=13, lab=6, ink=TEXT, lab_col=SUB):
    f = E.LF(E.LATB, big * m.s)
    m.d.text((m.P(cx), m.P(cy + 4)), n, font=f, fill=ink, anchor='mm')
    E.cap(m, cx, cy - big * 0.5, 'LV', lab, (200, 230, 235, 255), 1.0, anchor='m')


def make_leader(variant):
    def leader(m, x, y, phone=False):
        E.R.soft_shade(m, x - 6, y - 6, 260 if not phone else 220, 86, 0.32) if hasattr(E, 'R') else None
        m.img(BADGE_CLEAN, x, y + 2, 60, 62)
        if variant == 'type':
            # 纯排版：环左上一块纸白小名牌「LV」+ 粗体数字，无框
            E.plate(m, x - 2, y - 2, 20, 10, E.PAPER, 0.95)
            E.cap(m, x + 2, y + 6, 'LV', 6, (14, 16, 18, 255), 1.0)
            f = E.LF(E.LATB, 15 * m.s)
            for dx, dy in ((1, 1), (0, 2)):
                m.d.text((m.P(x + 21) + dx, m.P(y + 9) + dy), '28', font=f, fill=(0, 6, 12, 140), anchor='ls')
            m.d.text((m.P(x + 21), m.P(y + 9)), '28', font=f, fill=TEXT, anchor='ls')
        else:
            pl = PLATES[variant]
            k = max(1, round(m.P(32) / pl.size[1]))
            t = pl.resize((pl.size[0] * k, pl.size[1] * k), Image.NEAREST)
            px, py = m.P(x - 12), m.P(y - 10)
            m.ov.alpha_composite(t, (px, py))
            cx = (px + t.size[0] / 2) / m.s
            cy = (py + t.size[1] / 2) / m.s
            lv_number(m, cx, cy)
        # 右侧读数沿用编辑式
        tx = x + 72
        E.cap(m, tx, y + 10, 'HP', 7)
        w = E.big(m, tx, y + 38, '195', 26)
        E.cap(m, tx + w + 6, y + 37, '/ 195', 8, SUB)
        E.line_bar(m, tx, y + 46, 150 if not phone else 120, 1.0, (70, 225, 240, 255))
        E.cap(m, tx, y + 62, 'LAMP', 7, H.GOLD)
        m.text(tx + 34, y + 63, '100', 10, H.GOLD, bold=True)
        E.line_bar(m, tx + 58, y + 59, (150 if not phone else 120) - 58, 1.0, H.GOLD, marks=(0.3, 0.7))
    return leader


if __name__ == '__main__':
    os.makedirs(OUT, exist_ok=True)
    variants = list(range(len(PLATES))) + ['type']
    crops = []
    for v in variants:
        E.leader = make_leader(v)
        im = J.frame(False, 0, False, 'R14_lv_%s.png' % v)
        crops.append(im.convert('RGB').crop((0, 48, 420, 48 + 170)).resize((840, 340), Image.NEAREST))
    # 现行对照
    cur = H.DESK_FULL.convert('RGB').crop((0, 0, 420, 170)).resize((840, 340), Image.NEAREST)
    allc = [('现行', cur)] + [('生图 %d' % (i + 1), c) for i, c in enumerate(crops[:-1])] + [('纯排版（不用生图）', crops[-1])]
    cols = 3
    rows = (len(allc) + cols - 1) // cols
    sheet = Image.new('RGB', (cols * 856, rows * 390), (12, 14, 18))
    d = ImageDraw.Draw(sheet)
    for i, (lab, c) in enumerate(allc):
        x, y = (i % cols) * 856, (i // cols) * 390
        sheet.paste(c, (x, y + 44))
        d.text((x + 12, y + 22), lab, font=H.FBF(24), fill=(255, 236, 170), anchor='lm')
    sheet.save(os.path.join(OUT, 'R14_lv_options.png'))
    print('ok', len(PLATES))
