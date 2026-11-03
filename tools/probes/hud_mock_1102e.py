"""docs/222 §8 第五轮：PRTS 终端风格 · 定稿方向（用户 11-02「还是 PRTS 风格吧」）。
吸收前几轮的结论：少框多留白（第四轮）、编队用 @2x 高精度待机帧（第三轮）、手机再砍一半；造型语言用第二轮 ① 的终端：
发丝线、斜切角、直角刻度、等宽小号英文编号、读数式数字、分段刻度条、点线引导。
用法：python hud_mock_1102e.py <worktree> <输出目录>"""
import math, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import hud_mock_1102 as H
import hud_mock_1102b as T
import hud_mock_1102c as G
import hud_mock_1102d as R
from hud_mock_1102 import M, C, TEXT, SUB, CYAN, GOLD, VIOLET, OPS, RELIC, BADGE
from hud_mock_1102b import chamfer, poly, line, mono, dotted
from PIL import Image, ImageDraw

OUT = sys.argv[2]
HAIR = C(1, 1, 1, 0.30)
HAIR2 = C(1, 1, 1, 0.16)
LINE = C(0.62, 0.95, 0.95, 0.6)
PURPLE = C(0.66, 0.52, 1.0)
sh = R.shadow_text


def corner(m, x, y, w, h, col=CYAN, L=10, wd=1.5):
    """四角直角刻度（不画整框）"""
    for (cx, cy, dx, dy) in [(x, y, 1, 1), (x + w, y, -1, 1), (x, y + h, 1, -1), (x + w, y + h, -1, -1)]:
        line(m, (cx, cy), (cx + dx * L, cy), col, wd)
        line(m, (cx, cy), (cx, cy + dy * L), col, wd)


def segbar(m, x, y, w, frac, col, n=30, h=5, ticks=0, marks=()):
    """分段读数条：暗槽 + n 段亮格 + 下沿刻度"""
    m.rect(x, y, w, h, C(0, 0.02, 0.03, 0.65))
    sw = w / n
    for k in range(n):
        if (k + 0.5) / n <= frac:
            m.rect(x + k * sw + 0.4, y + 0.6, sw - 1.1, h - 1.2, col)
    if ticks:
        for t in range(ticks + 1):
            line(m, (x + w * t / ticks, y + h + 1.5), (x + w * t / ticks, y + h + (4 if t % 5 == 0 else 2.5)), HAIR, 1)
    for t in marks:
        line(m, (x + w * t, y - 2), (x + w * t, y + h + 2), col, 1.2)


def readout(m, x, y, val, unit, sz=18, col=TEXT, ucol=SUB):
    w = sh(m, x, y, val, sz, col, bold=True)
    mono(m, x + w + 3, y, unit, 8, ucol)


# ================================================================ 件
def leader(m, x, y, phone=False):
    """左上：徽记 + 两行读数；只有左上 / 右下两个直角刻度和一根引线，不画整框"""
    w = 230 if not phone else 190
    R.soft_shade(m, x - 6, y - 6, w + 12, 78, a=0.32)
    mono(m, x + 70, y + 2, 'OP-00 // LEADER', 7, CYAN)
    m.img(BADGE, x, y + 4, 62, 64)
    tx = x + 70
    line(m, (x + 62, y + 30), (tx - 2, y + 30), LINE, 1)
    mono(m, tx, y + 18, 'HP', 8, SUB)
    readout(m, tx + 16, y + 20, '195', '/195', 16)
    segbar(m, tx, y + 25, w - 74, 1.0, CYAN, n=30, h=5, ticks=10)
    mono(m, tx, y + 50, 'LMP', 8, SUB)
    readout(m, tx + 22, y + 52, '100', '', 12, GOLD)
    segbar(m, tx + 48, y + 46, w - 122, 1.0, GOLD, n=20, h=3, marks=(0.3, 0.7))
    corner(m, x - 4, y - 4, w + 8, 74, CYAN, L=8, wd=1.2) if False else None
    line(m, (x - 4, y - 4), (x + 8, y - 4), CYAN, 1.5)
    line(m, (x - 4, y - 4), (x - 4, y + 8), CYAN, 1.5)


def status(m, x, y, phone=False):
    """状态：终端日志一行——「> 」起头、色点、点线分隔"""
    items = [('灯火通明', GOLD), ('护盾 ×1', CYAN), ('攻速 +70%', GOLD), ('认知负担', PURPLE)]
    if phone:
        items = items[:2] + [('+2', SUB)]
    mono(m, x, y, '>', 9, CYAN)
    xx = x + 10
    for k, (s, col) in enumerate(items):
        m.rect(xx, y - 7, 2, 8, col)
        xx += 5
        xx += sh(m, xx, y, s, 10, TEXT) + 6
        if k < len(items) - 1:
            dotted(m, xx, xx + 10, y - 3, HAIR, 3)
            xx += 14


def top_bar(m, y0=10, compact=False):
    W = m.W
    cx = W / 2
    R.soft_shade(m, cx - 170, y0 - 4, 340, 44 if compact else 92, a=0.28)
    mono(m, cx - 118, y0 + 8, 'KILL', 7, SUB)
    sh(m, cx - 118, y0 + 30, '1910', 22, TEXT, bold=True)
    line(m, (cx, y0 + 8), (cx, y0 + 30), HAIR, 1)
    mono(m, cx + 14, y0 + 8, 'T+', 7, SUB)
    sh(m, cx + 14, y0 + 30, '10:35', 22, TEXT, bold=True)
    if not compact:
        mono(m, cx, y0 + 50, 'ZONE // BLUE TREE · THR VI', 7, SUB, anchor='l') if False else None
        sh(m, cx, y0 + 52, '深蓝之树 · 威胁 VI', 11, SUB, anchor='ms')
    by = y0 + (78 if not compact else 46)
    bw = 520 if not compact else 300
    mono(m, cx - bw / 2, by - 5, 'TARGET //', 7, PURPLE)
    sh(m, cx - bw / 2 + 52, by - 3, '偏执泡影', 11, TEXT)
    mono(m, cx + bw / 2, by - 5, '055%', 8, PURPLE, anchor='r')
    segbar(m, cx - bw / 2, by, bw, 0.55, PURPLE, n=60, h=4)


def info(m, phone=False):
    """右上：斜切发丝条「RELIC 15」+ 最近几件（手机只留数字）；暂停 / 倍速两块小读数牌"""
    W = m.W
    n = 3 if not phone else 0
    w = 66 + n * 28
    x = W - 16 - 82 - w
    p = chamfer(x, 14, w, 30, 7, 'tr,bl')
    poly(m, p, fill=C(0.02, 0.035, 0.045, 0.72))
    poly(m, p, outline=HAIR)
    mono(m, x + 8, 26, 'RELIC', 7, CYAN)
    sh(m, x + 8, 40, '15', 13, TEXT, bold=True)
    for k in range(n):
        m.rect(x + 40 + k * 28, 17, 24, 24, None, outline=HAIR2)
        m.img(RELIC[k], x + 41 + k * 28, 18, 22, 22)
    for i, (lab, val, on) in enumerate([('PAUSE', 'Ⅱ', False), ('SPD', '×1.0', False)]):
        px = W - 16 - 76 + i * 40
        p = chamfer(px, 14, 36, 30, 6, 'tr,bl')
        poly(m, p, fill=C(0.02, 0.035, 0.045, 0.72))
        poly(m, p, outline=(CYAN if on else HAIR))
        mono(m, px + 18, 23, lab, 6, SUB, anchor='l') if False else None
        m.text(px + 18, 35, val, 11 if i else 12, TEXT, anchor='ms', bold=True)
    line(m, (W - 16 - 76 + 36, 50), (W - 16, 50), HAIR2, 1)
    mono(m, W - 16, 58, 'SPD x1.0', 6, SUB, anchor='r') if not phone else None


def portrait(m, x, y, w, h, i, frac=0.55):
    """@2x 待机帧上半身，整数倍放大裁进窗口（不出框）"""
    src = G.HI[i]
    s = src.crop((0, 0, src.size[0], int(src.size[1] * frac)))
    k = max(1, round(m.P(h) / s.size[1]))
    t = s.resize((s.size[0] * k, s.size[1] * k), Image.NEAREST)
    lay = Image.new('RGBA', m.ov.size, (0, 0, 0, 0))
    lay.alpha_composite(t, (m.P(x + w / 2) - t.size[0] // 2, m.P(y)))
    mk = Image.new('L', m.ov.size, 0)
    ImageDraw.Draw(mk).polygon([(m.P(a), m.P(b)) for a, b in chamfer(x, y, w, h, 7, 'tr')], fill=255)
    m.ov.alpha_composite(Image.composite(lay, Image.new('RGBA', m.ov.size, (0, 0, 0, 0)), mk))


def squad(m, x, y, phone=False):
    """右下：上面一行指令读数（CMD ▸ 随行 · 作战时限刻度），下面四个斜切发丝窗（@2x 半身）+ 分段生命条"""
    cw = 64 if not phone else 46
    ch = 64 if not phone else 46
    gap = 8 if not phone else 6
    n = 4
    W = n * cw + (n - 1) * gap
    R.soft_shade(m, x - 8, y - 8, W + 16, ch + (66 if not phone else 46), a=0.32)
    # 指令行
    line(m, (x, y + 2), (x, y + 18), CYAN, 2)
    mono(m, x + 6, y + 8, 'CMD', 7, SUB)
    sh(m, x + 6, y + 20, '随行', 13, CYAN, bold=True)
    if not phone:
        m.keycap(x + 42, y + 7, 'F', 9, SUB)
        mono(m, x + 66, y + 8, 'OPS-T', 7, SUB)
        segbar(m, x + 66, y + 12, 90, 0.35, CYAN, n=18, h=3)
        mono(m, x + W, y + 8, 'SQUAD 04/04', 7, SUB, anchor='r')
        mono(m, x + W, y + 20, 'BOND 02', 7, GOLD, anchor='r')
    else:
        segbar(m, x + 38, y + 14, 70, 0.35, CYAN, n=14, h=3)
    oy = y + 28
    for i, (nm, cls, hp) in enumerate(OPS):
        cx0 = x + i * (cw + gap)
        p = chamfer(cx0, oy, cw, ch, 7, 'tr')
        poly(m, p, fill=C(0.02, 0.035, 0.045, 0.85))
        portrait(m, cx0, oy + 2, cw, ch - 2, i)
        poly(m, p, outline=(PURPLE if i == 0 else HAIR))
        if i == 0:
            line(m, (cx0 - 3, oy - 3), (cx0 + 9, oy - 3), PURPLE, 1.5)
            line(m, (cx0 - 3, oy - 3), (cx0 - 3, oy + 9), PURPLE, 1.5)
        # 角标：职业色小方块 + 编号
        m.rect(cx0 + 2, oy + 2, 10, 10, C(0, 0, 0, 0.7))
        m.rect(cx0 + 2, oy + 2, 2, 10, H.CLS[cls])
        mono(m, cx0 + 5, oy + 10, str(i + 1), 7, TEXT) if False else None
        if i in (1, 2):
            H.M.diamond(m, cx0 + cw - 5, oy + ch - 5, 2.6, GOLD)
        # 生命：窗下一根分段条（队长窗下写 LEADER）
        if i:
            segbar(m, cx0, oy + ch + 3, cw, hp, (70, 225, 240, 255) if hp > 0.5 else GOLD, n=10, h=3)
        else:
            segbar(m, cx0, oy + ch + 3, cw, 1.0, PURPLE, n=10, h=3)   # 队长生命在左上；这里只标紫
        if not phone:
            sh(m, cx0, oy + ch + 19, nm[:4], 9, TEXT)
            for q in range(3):
                m.rect(cx0 + cw - 6 - (2 - q) * 7, oy + 3, 5, 5, [GOLD, CYAN, C(1, 1, 1, 0.25)][q])
    return W


def guide(m, x, y, w):
    """指南卡：斜切发丝框 + 上沿编号 + 演示窗（@2x）+ 读数式做完条件"""
    h = 108
    p = chamfer(x, y, w, h, 12, 'tr,bl')
    poly(m, p, fill=C(0.02, 0.035, 0.045, 0.8))
    poly(m, p, outline=HAIR)
    line(m, (x - 4, y), (x + 12, y), CYAN, 1.5)
    line(m, (x, y - 4), (x, y + 12), CYAN, 1.5)
    mono(m, x + 10, y - 5, 'TUTORIAL // 02-06', 7, CYAN)
    mono(m, x + w - 6, y - 5, 'LOG', 7, SUB, anchor='r')
    m.rect(x + 10, y + 12, 104, 84, C(0, 0.01, 0.02, 0.7), outline=HAIR2)
    corner(m, x + 10, y + 12, 104, 84, CYAN, L=6, wd=1)
    G.pix(m, G.HI[0], x + 44, y + 30, 50)
    for dx, dy in [(16, 18), (88, 16), (92, 66), (20, 64)]:
        H.M.diamond(m, x + 10 + dx, y + 12 + dy, 3, C(0.55, 1.0, 0.78))
    sh(m, x + 126, y + 30, '经验与升级', 14, TEXT, bold=True)
    m.text(x + 126, y + 52, '拾取经验结晶，经验条满了就升级，三张卡里选一张。', 10, TEXT)
    mono(m, x + 126, y + 80, '> 捡起附近的经验结晶', 8, CYAN) if False else sh(m, x + 126, y + 82, '> 捡起附近的经验结晶', 10, CYAN)
    dotted(m, x + 260, x + w - 40, y + 78, HAIR, 3)
    mono(m, x + w - 10, y + 82, '0/1', 8, CYAN, anchor='r')
    # 步骤：六格分段（做完的亮、当前的半亮）
    for k in range(6):
        c = CYAN if k < 1 else (C(0.212, 0.886, 0.863, 0.5) if k == 1 else C(1, 1, 1, 0.12))
        m.rect(x + w - 10 - (6 - k) * 13, y + 10, 10, 3, c)


# ================================================================ 组装
def desktop():
    m = M(H.DESK_BG, 1.5)
    W, Hh = m.W, m.H
    leader(m, 18, 14)
    status(m, 20, 100)
    top_bar(m)
    info(m)
    cw, gap = 64, 8
    w = 4 * cw + 3 * gap
    squad(m, W - 22 - w, Hh - 22 - (28 + 64 + 22))
    H.minimap(m, 16, Hh - 16 - 130, 130)
    H.key_hints(m)
    return m.done(os.path.join(OUT, 'R5_P_desktop.png'), 'PRTS 终端 · 定稿方向（电脑 1920×1080）')


def phone():
    m = M(H.PH_BG, 1.25, 1.0)
    W, Hh = m.W, m.H
    leader(m, 14, 10, phone=True)
    status(m, 16, 92, phone=True)
    top_bar(m, 6, compact=True)
    info(m, phone=True)
    H.phone_buttons(m, '随行', speed=False, pause=False)
    cw, gap = 46, 6
    w = 4 * cw + 3 * gap
    squad(m, W - 16 - w, Hh - 14 - (28 + 46 + 8), phone=True)
    H.minimap(m, 10, Hh - 10 - 84, 84)
    return m.done(os.path.join(OUT, 'R5_P_phone.png'), 'PRTS 终端 · 定稿方向（手机横屏）')


NOTES = [
    ('角', '只在面板的右上 / 左下斜切；整块信息不画整框，只在左上放一个青色直角刻度（队长、指南卡）'),
    ('线', '1px 白色发丝（30% / 16% 两档）；徽记到读数一根青色引线；状态之间点线分隔'),
    ('字', '等宽小号英文标签（OP-00、HP、LMP、CMD、RELIC、TARGET）+ 中文正文；数字是读数，单位用小号等宽字'),
    ('条', '分段读数条：生命 30 格 + 10 格刻度、灯火 20 格 + 30 / 70 档位线、Boss 60 格紫、队友 10 格'),
    ('编队', '四个右上斜切的发丝窗，@2x 待机帧上半身裁进窗里（不出框）；队长窗紫框 + 紫色直角刻度'),
    ('动效', '读数变化逐位滚动；受击时生命条掉格从右往左逐格熄；指令切换时 CMD 竖线闪一下；刷新时一道扫描线过窗'),
]


def detail():
    bg = H.DESK_BG.crop((560, 480, 1520, 1020)).resize((1920, 1080))
    m = M(bg, 2.0)
    m.rect(0, 0, m.W, m.H, C(0.01, 0.02, 0.03, 0.45))
    leader(m, 24, 26)
    status(m, 26, 112)
    m.W = 940
    info(m)
    m.W = 960
    squad(m, 26, 160)
    guide(m, 420, 150, 500)
    y = 340
    for k, (a, b) in enumerate(NOTES):
        mono(m, 26, y + k * 26, a, 9, CYAN)
        m.text(80, y + k * 26, b, 10, C(0.95, 0.93, 0.85))
    return m.done(os.path.join(OUT, 'R5_P_detail.png'), 'PRTS 终端 · 件的放大（2 倍）')


if __name__ == '__main__':
    os.makedirs(OUT, exist_ok=True)
    d, p, dt = desktop(), phone(), detail()
    dw = 960
    dh = int(d.size[1] * dw / d.size[0])
    pw = int(p.size[0] * dh / p.size[1])
    sheet = Image.new('RGB', (dw + 12 + pw, dh * 2 + 12), (12, 14, 18))
    sheet.paste(d.convert('RGB').resize((dw, dh)), (0, 0))
    sheet.paste(p.convert('RGB').resize((pw, dh)), (dw + 12, 0))
    sheet.paste(dt.convert('RGB').resize((dw, dh)), (0, dh + 12))
    sheet.save(os.path.join(OUT, 'R5_overview.png'))
    print('ok')
