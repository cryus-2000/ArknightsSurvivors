"""docs/222 §7 第四轮：② 水月深海 · 减法版（用户 11-02「感觉有点丑和拥挤，特别是手机上」）。
原则：少框多留白——数值直接浮在战场上（只加柔和投影），玻璃只留给真正要成块的两处（右上一条、指挥牌），
编队改成四颗圆形「水泡头像」（@2x 待机帧头部 + 泡内水位 = 生命），手机再砍一半信息。
用法：python hud_mock_1102d.py <worktree> <输出目录>"""
import math, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import hud_mock_1102 as H
import hud_mock_1102c as G
from hud_mock_1102 import M, C, TEXT, SUB, CYAN, GOLD, VIOLET, OPS, RELIC, BADGE
from PIL import Image, ImageDraw, ImageFilter

OUT = sys.argv[2]
AQUA = G.AQUA
PURPLE = G.PURPLE


def shadow_text(m, x, y, s, sz, col=TEXT, anchor='ls', bold=False):
    """浮在战场上的字：只加一圈柔和暗影，不垫底板"""
    for dx, dy in ((1, 1), (-1, 1), (1, -1), (-1, -1), (0, 1.5)):
        m.text(x + dx / m.s * 1.2, y + dy / m.s * 1.2, s, sz, (0, 8, 14, 150), anchor=anchor, bold=bold)
    return m.text(x, y, s, sz, col, anchor=anchor, bold=bold)


def soft_shade(m, x, y, w, h, a=0.45, r=24):
    """一块很淡的暗晕（不是面板）：只为让浮字在亮特效上也读得清"""
    lay = Image.new('RGBA', m.ov.size, (0, 0, 0, 0))
    ImageDraw.Draw(lay).rounded_rectangle(m.R(x, y, w, h), radius=m.P(r), fill=(2, 10, 18, int(255 * a)))
    m.ov.alpha_composite(lay.filter(ImageFilter.GaussianBlur(m.P(10))))


def head_of(src, frac=0.5):
    """@2x 待机帧的头部（上 frac，横向居中取方块）"""
    w, h = src.size
    hh = int(h * frac)
    cx = w // 2
    s = min(w, hh)
    return src.crop((max(0, cx - s // 2), 0, max(0, cx - s // 2) + s, s))


HEADS = [head_of(s) for s in G.HI]


def orb(m, cx, cy, r, i, hp, leader=False, phone=False):
    """水泡头像：深色泡 + @2x 头部（整数倍放大，裁在泡里）+ 一圈细边（队长紫）+ 外圈水环 = 生命"""
    box = m.R(cx - r, cy - r, 2 * r, 2 * r)
    mk = Image.new('L', m.ov.size, 0)
    ImageDraw.Draw(mk).ellipse(box, fill=255)
    lay = Image.new('RGBA', m.ov.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(lay)
    d.ellipse(box, fill=(4, 18, 30, 235))
    src = HEADS[i]
    k = max(1, round(m.P(2 * r * 1.05) / src.size[1]))
    t = src.resize((src.size[0] * k, src.size[1] * k), Image.NEAREST)
    lay.alpha_composite(t, (m.P(cx) - t.size[0] // 2, m.P(cy - r * 0.92)))
    m.ov.alpha_composite(Image.composite(lay, Image.new('RGBA', m.ov.size, (0, 0, 0, 0)), mk))
    ec = PURPLE if leader else (150, 220, 255, 200)
    if leader:
        for q in range(3, 0, -1):
            m.d.ellipse([box[0] - q, box[1] - q, box[2] + q, box[3] + q], outline=(PURPLE[0], PURPLE[1], PURPLE[2], 40 * (4 - q)))
    m.d.ellipse(box, outline=ec, width=max(1, m.P(1.3 if leader else 1)))
    m.d.arc(m.R(cx - r + 2, cy - r + 2, 2 * r - 4, 2 * r - 4), 205, 255, fill=(255, 255, 255, 150), width=max(1, m.P(1)))
    # 生命 = 外圈一道水环：从正下方顺时针灌，满了是整圈；残血变金；空的部分是暗槽
    rr = r + 4
    ring = m.R(cx - rr, cy - rr, 2 * rr, 2 * rr)
    m.d.arc(ring, 0, 360, fill=(2, 12, 20, 200), width=max(2, m.P(3)))
    col = (70, 225, 240, 255) if hp > 0.5 else (255, 190, 80, 255)
    if hp > 0.0:
        m.d.arc(ring, 90, 90 + 360 * hp, fill=col, width=max(2, m.P(3)))


# ================================================================ 件
def leader(m, x, y, phone=False):
    """左上：徽记 + 两根细管，数值浮字；不垫面板"""
    soft_shade(m, x - 6, y - 4, 250 if not phone else 200, 76, a=0.35)
    m.img(BADGE, x, y, 62, 64)
    tw = 168 if not phone else 132
    tx = x + 70
    shadow_text(m, tx, y + 22, '195', 18, TEXT, bold=True)
    shadow_text(m, tx + m.tw('195', 18) + 4, y + 22, '/ 195', 9, SUB)
    G.tank(m, tx, y + 28, tw, 8, 1.0, (70, 225, 240), ph=0.6)
    shadow_text(m, tx, y + 52, '灯火 100', 10, GOLD)
    G.tank(m, tx + 52, y + 45, tw - 52, 6, 1.0, (255, 190, 80), ph=1.8, ticks=(0.3, 0.7), deep=(150, 70, 10))


def status(m, x, y, phone=False):
    """状态：一行小字，彩色圆点打头；手机最多两枚 + 「+N」"""
    items = [('灯火通明', GOLD), ('护盾 ×1', CYAN), ('攻速 +70%', GOLD), ('认知负担', PURPLE)]
    if phone:
        items = items[:2] + [('+2', SUB)]
    xx = x
    for s, col in items:
        m.d.ellipse(m.R(xx, y - 7, 6, 6), fill=col)
        xx += 9
        xx += shadow_text(m, xx, y, s, 10, TEXT) + 12


def info(m, phone=False):
    """右上：一条细玻璃胶囊（藏品数 + 最近几件）+ 暂停 / 倍速两颗泡；手机只留数字"""
    W = m.W
    n = 3 if not phone else 0
    w = 62 + n * 26
    x = W - 16 - 84 - w
    G.glass(m, x, 14, w, 30, r=15, seed=1.1, cau=False)
    shadow_text(m, x + 12, 34, '藏品', 9, AQUA)
    m.text(x + 38, 35, '15', 13, TEXT, bold=True)
    for k in range(n):
        m.img(RELIC[k], x + 62 + k * 26, 19, 20, 20)
    for i, val in enumerate(['Ⅱ', '1×']):
        cx = W - 16 - 60 + i * 40
        G.bubble(m, cx, 29, 15, glow=False)
        m.text(cx, 34, val, 12, TEXT, anchor='ms', bold=True)


def squad(m, x, y, phone=False):
    """右下：指挥牌（唯一一块实玻璃）+ 四颗水泡头像；名字只在桌面写一行小字，手机不写"""
    r = 30 if not phone else 22
    gap = 12 if not phone else 9
    n = 4
    w = n * 2 * r + (n - 1) * gap
    # 指挥牌
    cpw = 132 if not phone else 112
    cx0 = x + w - cpw
    G.tank(m, cx0, y, cpw, 24, 1.0, (40, 170, 180), ph=0.4)
    m.d.rounded_rectangle(m.R(cx0, y, cpw, 24), radius=m.P(12), outline=CYAN, width=max(1, m.P(1.2)))
    m.text(cx0 + 14, y + 17, '指挥 · 随行', 12, TEXT, bold=True)
    if not phone:
        m.keycap(cx0 + cpw - 22, y + 4, 'F', 9, TEXT)
        shadow_text(m, cx0 - 10, y + 16, '羁绊 2', 10, GOLD, anchor='rs')
    G.tank(m, cx0 + 8, y + 27, cpw - 16, 3, 0.35, (70, 225, 240))
    oy = y + 44 + r
    for i, (nm, cls, hp) in enumerate(OPS):
        cx = x + r + i * (2 * r + gap)
        orb(m, cx, oy, r, i, hp if i else 1.0, leader=(i == 0), phone=phone)
        # 职业小点 + 技能三点（只在桌面）
        cc = H.CLS[cls]
        m.d.ellipse(m.R(cx - r * 0.78 - 4, oy - r * 0.78 - 4, 9, 9), fill=(4, 18, 30, 255), outline=cc, width=1)
        if not phone:
            shadow_text(m, cx, oy + r + 15, nm, 10, TEXT, anchor='ms')
            for q in range(3):
                m.d.ellipse(m.R(cx - 10 + q * 8, oy + r + 20, 5, 5), fill=[GOLD, CYAN, (110, 130, 150, 255)][q])
        if i in (1, 2):
            H.M.diamond(m, cx + r * 0.75, oy - r * 0.75, 3.2, GOLD)
    return w


def top_bar(m, y0=10, compact=False):
    """顶栏：去掉底板，数字浮字；Boss 条是一根细紫液管"""
    W = m.W
    cx = W / 2
    soft_shade(m, cx - 160, y0 - 4, 320, 46 if compact else 92, a=0.3)
    m.d.ellipse(m.R(cx - 122, y0 + 12, 14, 14), outline=(255, 140, 50, 255), width=max(1, m.P(1.8)))
    m.d.ellipse(m.R(cx - 117.5, y0 + 16.5, 5, 5), fill=(255, 140, 50, 255))
    shadow_text(m, cx - 100, y0 + 29, '1910', 22, TEXT, bold=True)
    shadow_text(m, cx - 46, y0 + 29, '击杀', 10, SUB)
    m.d.ellipse(m.R(cx + 14, y0 + 13, 13, 13), outline=TEXT, width=max(1, m.P(1.4)))
    shadow_text(m, cx + 34, y0 + 29, '10:35', 22, TEXT, bold=True)
    if not compact:
        shadow_text(m, cx, y0 + 52, '深蓝之树 · 威胁 VI', 11, SUB, anchor='ms')
    by = y0 + (78 if not compact else 46)
    bw = 520 if not compact else 300
    shadow_text(m, cx - bw / 2, by - 4, '偏执泡影', 12, TEXT)
    G.tank(m, cx - bw / 2, by, bw, 7, 0.55, (190, 150, 255), ph=2.0, deep=(70, 40, 140))


def desktop():
    m = M(H.DESK_BG, 1.5)
    W, Hh = m.W, m.H
    leader(m, 16, 12)
    status(m, 18, 98)
    top_bar(m)
    info(m)
    w = squad(m, 0, 0) if False else None
    r, gap = 30, 12
    w = 4 * 2 * r + 3 * gap
    squad(m, W - 20 - w, Hh - 20 - (44 + 2 * r + 30))
    H.minimap(m, 16, Hh - 16 - 130, 130)
    H.key_hints(m)
    return m.done(os.path.join(OUT, 'R4_D_desktop.png'), '② 水月深海 · 减法版（电脑 1920×1080）')


def phone():
    m = M(H.PH_BG, 1.25, 1.0)
    W, Hh = m.W, m.H
    leader(m, 12, 8, phone=True)
    status(m, 14, 88, phone=True)
    top_bar(m, 6, compact=True)
    info(m, phone=True)
    H.phone_buttons(m, '随行', speed=False, pause=False)
    r, gap = 22, 9
    w = 4 * 2 * r + 3 * gap
    squad(m, W - 14 - w, Hh - 14 - (44 + 2 * r + 6), phone=True)
    H.minimap(m, 10, Hh - 10 - 84, 84)
    return m.done(os.path.join(OUT, 'R4_D_phone.png'), '② 水月深海 · 减法版（手机横屏）')


if __name__ == '__main__':
    os.makedirs(OUT, exist_ok=True)
    d, p = desktop(), phone()
    # 和上一版并排：上 = 上一版，下 = 减法版（电脑 / 手机）
    prev_d = Image.open(os.path.join(OUT, 'R3_D_desktop.png')).convert('RGB')
    prev_p = Image.open(os.path.join(OUT, 'R3_D_phone.png')).convert('RGB')
    dw = 960
    dh = int(prev_d.size[1] * dw / prev_d.size[0])
    pw = int(prev_p.size[0] * dh / prev_p.size[1])
    sheet = Image.new('RGB', (dw + 12 + pw, dh * 2 + 12), (12, 14, 18))
    sheet.paste(prev_d.resize((dw, dh)), (0, 0))
    sheet.paste(prev_p.resize((pw, dh)), (dw + 12, 0))
    sheet.paste(d.convert('RGB').resize((dw, dh)), (0, dh + 12))
    sheet.paste(p.convert('RGB').resize((pw, dh)), (dw + 12, dh + 12))
    sheet.save(os.path.join(OUT, 'R4_vs_R3.png'))
    print('ok')
