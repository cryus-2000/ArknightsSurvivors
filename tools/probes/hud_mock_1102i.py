"""docs/222 §12 第九轮（在第八轮上改）：用户 11-02「指挥模式用线条是不是有点奇怪」「队友的立绘应该放全，否则大小不一致」「队友的生命值放哪里了」。
- 指挥模式：橙色步骤线 → 四格分段按钮（随行 / 突击 / 部署 / 集火），当前格实心青底黑字；
- 立绘：@2x 待机帧全身，四人用同一个裁切窗口（帧内 34–126 行、按身体中心取 80 宽）和同一个缩放，脚底对齐、比例一致；
- 队友生命：立绘窗底部一根 3.5 高的生命条 + 名牌右侧的数字（残血变金 / 红）。
用法：python hud_mock_1102i.py <worktree> <输出目录>"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import hud_mock_1102 as H
import hud_mock_1102h as E
from hud_mock_1102 import M, C, TEXT, SUB, CYAN, GOLD, OPS
from PIL import Image, ImageDraw

WT, OUT = sys.argv[1], sys.argv[2]
ART = os.path.join(WT, 'game', 'art', 'operators')
IDS = ['texas', 'exusiai', 'lappland', 'lumen']
HPN = [195, 172, 118, 160]   # 效果稿里的生命数字（与 OPS 的比例一致）


def full_body(oid, top=34, bot=126, w=80):
    im = Image.open(os.path.join(ART, oid, 'op_%s_idle@2x.png' % oid)).convert('RGBA')
    h = im.size[1]
    f = im.crop((0, 0, h, h))
    bb = f.getbbox()
    cx = (bb[0] + bb[2]) // 2
    x0 = max(0, min(h - w, cx - w // 2))
    return f.crop((x0, top, x0 + w, bot))


BODY = [full_body(o) for o in IDS]


def body(m, x, y, w, h, i, k):
    """全身窗：同一裁切、同一缩放（整数 / 半倍最近邻），底边对齐窗底"""
    src = BODY[i]
    t = src.resize((max(1, int(src.size[0] * k)), max(1, int(src.size[1] * k))), Image.NEAREST)
    lay = Image.new('RGBA', m.ov.size, (0, 0, 0, 0))
    lay.alpha_composite(t, (m.P(x + w / 2) - t.size[0] // 2, m.P(y + h) - t.size[1]))
    mk = Image.new('L', m.ov.size, 0)
    ImageDraw.Draw(mk).rectangle(m.R(x, y, w, h), fill=255)
    m.ov.alpha_composite(Image.composite(lay, Image.new('RGBA', m.ov.size, (0, 0, 0, 0)), mk))


def segmented(m, x, y, w, cur, labels, phone=False):
    """四格分段按钮：当前格实心青底黑字，其余暗底灰字，格间 1 像素分隔"""
    n = len(labels)
    cw = w / n
    hh = 20 if not phone else 18
    m.rect(x, y, w, hh, (10, 12, 14, 220))
    m.rect(x, y, w, hh, None, outline=(255, 255, 255, 60))
    for k, s in enumerate(labels):
        cx = x + k * cw
        if k == cur:
            m.rect(cx, y, cw, hh, CYAN)
        elif k:
            m.rect(cx, y + 4, 1 / m.s, hh - 8, (255, 255, 255, 50))
        m.text(cx + cw / 2, y + hh - 6, s, 10 if not phone else 9, (14, 16, 18, 255) if k == cur else SUB, anchor='ms', bold=(k == cur))


def squad(m, x, y, phone=False):
    k = 1.0 if not phone else 0.5          # @2x 帧：电脑 1:1 像素；手机按 @1x 大小（真机是高密度屏，同样清楚）
    cw = 80 * k / m.s + (14 if not phone else 4)
    ch = 92 * k / m.s
    gap = 6
    W = 4 * cw + 3 * gap
    nh = 15 if not phone else 12
    E.shade(m, x - 10, y - 10, W + 20, ch + nh + (48 if not phone else 40), 0.36)
    # 指挥：小标签 + 四格分段按钮；右边编队 / 羁绊
    E.cap(m, x, y + 6, 'COMMAND' + ('  ·  F' if not phone else ''), 6.5)
    if not phone:
        E.cap(m, x + W, y + 6, 'SQUAD 4/4', 6.5, anchor='r')
        E.cap(m, x + W - E.cap(m, -999, -999, 'SQUAD 4/4', 6.5) - 12, y + 6, 'BOND 2', 6.5, GOLD, anchor='r')
    segmented(m, x, y + 10, W, 0, ['随行', '突击', '部署', '集火'], phone)
    oy = y + (40 if not phone else 36)
    for i, (nm, cls, hp) in enumerate(OPS):
        cx0 = x + i * (cw + gap)
        m.rect(cx0, oy, cw, ch, (10, 12, 14, 205))
        body(m, cx0, oy, cw, ch, i, k)
        m.rect(cx0, oy, cw, 1.5, H.CLS[cls])                       # 职业色顶线
        if i in (1, 2):
            H.M.diamond(m, cx0 + cw - 5, oy + 6, 2.6, GOLD)            # 羁绊
        # 生命：窗底一根条（满 = 青，<50% 金，<25% 红）
        col = (70, 225, 240, 255) if hp > 0.5 else (GOLD if hp > 0.25 else (255, 61, 139, 255))
        m.rect(cx0, oy + ch - 3.5, cw, 3.5, (0, 0, 0, 200))
        m.rect(cx0, oy + ch - 3.5, cw * hp, 3.5, col)
        # 名牌：名字 + 生命数字（队长纸白底）
        lead = i == 0
        E.plate(m, cx0, oy + ch, cw, nh, E.PAPER if lead else E.INK, 0.95)
        ink = (14, 16, 18, 255) if lead else TEXT
        if not phone:
            m.text(cx0 + 4, oy + ch + 11, nm[:4], 9, ink, bold=True)
            m.text(cx0 + cw - 3, oy + ch + 11, str(HPN[i]), 9, ink if lead else col, anchor='rs', bold=True)
        else:
            m.text(cx0 + cw / 2, oy + ch + 9.5, str(HPN[i]), 8, ink if lead else col, anchor='ms', bold=True)
        if lead:
            E.plate(m, cx0, oy - 10, 34, 10, E.INK)
            E.cap(m, cx0 + 3, oy - 2.5, 'LEADER', 5, TEXT, 0.8)
    return W, ch + nh + 40


E.squad = squad


def desktop():
    m = M(H.DESK_BG, 1.5)
    W, Hh = m.W, m.H
    E.leader(m, 20, 14)
    E.status(m, 20, 116)
    E.top_bar(m)
    E.info(m)
    cw = 80 / 1.5 + 14
    w = 4 * cw + 18
    squad(m, W - 24 - w, Hh - 24 - (40 + 92 / 1.5 + 15))
    H.minimap(m, 16, Hh - 16 - 130, 130)
    H.key_hints(m)
    return m.done(os.path.join(OUT, 'R9_RL_desktop.png'), '编辑式 · 第九轮（电脑 1920×1080）')


def phone():
    m = M(H.PH_BG, 1.25, 1.0)
    W, Hh = m.W, m.H
    E.leader(m, 14, 10, phone=True)
    E.status(m, 14, 110, phone=True)
    E.top_bar(m, 6, compact=True)
    E.info(m, phone=True)
    H.phone_buttons(m, '随行', speed=False, pause=False)
    cw = 40 / 1.25 + 4
    w = 4 * cw + 18
    squad(m, W - 16 - w, Hh - 12 - (36 + 46 / 1.25 + 12), phone=True)
    H.minimap(m, 10, Hh - 10 - 84, 84)
    return m.done(os.path.join(OUT, 'R9_RL_phone.png'), '编辑式 · 第九轮（手机横屏）')


def detail(d):
    """编队区放大：直接从电脑稿裁右下角，最近邻放大 2 倍（真实比例）"""
    im = d.convert('RGB')
    w, h = im.size
    crop = im.crop((w - 560, h - 300, w, h)).resize((1120, 600), Image.NEAREST)
    out = Image.new('RGB', (1120, 600 + 150), (12, 14, 18))
    out.paste(crop, (0, 0))
    dr = ImageDraw.Draw(out)
    notes = ['指挥模式：四格分段按钮，当前格实心青底；鼠标 / 触屏可直接点格切换（F 仍开圆盘）',
             '立绘：四人同一个裁切窗口、同一个缩放，脚底对齐；高矮按原作比例，不再各自放大',
             '队友生命：立绘窗底一根条（青 → 金 → 红）+ 名牌右侧数字；队长名牌纸白',
             '职业：窗顶一根职业色细线；羁绊：右上金菱形']
    for k, t in enumerate(notes):
        dr.text((16, 612 + k * 34), t, font=H.FBF(20), fill=(242, 237, 216))
    out.save(os.path.join(OUT, 'R9_RL_detail.png'))
    return out


if __name__ == '__main__':
    os.makedirs(OUT, exist_ok=True)
    d, p = desktop(), phone()
    detail(d)
    print('ok')
