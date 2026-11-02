"""docs/222 §6 第三轮：精进处理 ②「水月深海」（用户 11-02「在 2 的基础上进一步精进，队伍立绘选用高精度的，只有真正实机的采用低精度的」）。
磨砂玻璃（真的模糊底图）+ 内发光 + 焦散纹理；液面槽有深度渐变、液面弯月高光、气泡；编队卡用 @2x 待机帧（图鉴 / 选人同款），
技能用高精度技能图标。出 电脑 1920×1080、手机 1170×540、件的放大图（带造型说明）。
用法：python hud_mock_1102c.py <worktree> <输出目录>"""
import math, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import hud_mock_1102 as H
from hud_mock_1102 import M, C, TEXT, SUB, CYAN, GOLD, VIOLET, GREEN, OPS, RELIC, BADGE
from PIL import Image, ImageDraw, ImageFilter, ImageChops

WT, OUT = sys.argv[1], sys.argv[2]
ART = os.path.join(WT, 'game', 'art')
PURPLE = C(0.66, 0.52, 1.0)
AQUA = C(0.45, 0.92, 1.0)
DEEP = (6, 22, 36)
IDS = ['texas', 'exusiai', 'lappland', 'lumen']


def idle_frame(oid):
    """@2x 待机帧第 0 帧，按不透明像素裁边（图鉴 / 选人页用的高精度版）"""
    im = Image.open(os.path.join(ART, 'operators', oid, 'op_%s_idle@2x.png' % oid)).convert('RGBA')
    h = im.size[1]
    f = im.crop((0, 0, h, h))
    bb = f.getbbox()
    return f.crop(bb) if bb else f


HI = [idle_frame(o) for o in IDS]
SKI = [[Image.open(os.path.join(ART, 'ui', 'skills', 'skill_%s_s%d.png' % (o, k + 1))).convert('RGBA') for k in range(3)] for o in IDS]


def pix(m, src, x, y, h, crop_top=None):
    """像素图按整数倍放大贴上（最近邻，不糊）；h = 目标高度（设计单位）；crop_top = 只取上面这一比例（半身）"""
    s = src if crop_top is None else src.crop((0, 0, src.size[0], int(src.size[1] * crop_top)))
    k = max(1, round(m.P(h) / s.size[1]))
    t = s.resize((s.size[0] * k, s.size[1] * k), Image.NEAREST)
    m.ov.alpha_composite(t, (m.P(x), m.P(y)))
    return t.size[0] / m.s


def rmask(m, x, y, w, h, r):
    mk = Image.new('L', m.im.size, 0)
    ImageDraw.Draw(mk).rounded_rectangle(m.R(x, y, w, h), radius=m.P(r), fill=255)
    return mk


def frost(m, x, y, w, h, r, tint=(8, 30, 46), k=0.58, blur=7):
    """磨砂玻璃：把面板下面的画面模糊 + 压暗染深海蓝，再贴回去"""
    box = m.R(x, y, w, h)
    reg = m.im.crop(box).filter(ImageFilter.GaussianBlur(m.P(blur)))
    tint_im = Image.new('RGBA', reg.size, tint + (255,))
    reg = Image.blend(reg.convert('RGBA'), tint_im, k)
    mk = Image.new('L', reg.size, 0)
    ImageDraw.Draw(mk).rounded_rectangle([0, 0, reg.size[0] - 1, reg.size[1] - 1], radius=m.P(r), fill=255)
    m.im.paste(reg, (box[0], box[1]), mk)


def caustic(m, x, y, w, h, r, a=0.07, seed=0.0):
    """焦散：两组正弦干涉出的亮纹，裁进圆角面板"""
    W, Hh = m.P(w), m.P(h)
    lay = Image.new('RGBA', (W, Hh), (0, 0, 0, 0))
    d = ImageDraw.Draw(lay)
    for k in range(7):
        pts = []
        for t in range(0, W + 1, max(3, m.P(4))):
            yy = Hh * (k + 0.5) / 7 + m.P(3) * math.sin(t / max(1, m.P(18)) + k * 1.7 + seed) + m.P(2) * math.sin(t / max(1, m.P(7)) + k)
            pts.append((t, yy))
        d.line(pts, fill=(160, 235, 255, int(255 * a)), width=max(1, m.P(1)))
    mk = Image.new('L', (W, Hh), 0)
    ImageDraw.Draw(mk).rounded_rectangle([0, 0, W - 1, Hh - 1], radius=m.P(r), fill=255)
    out = Image.new('RGBA', (W, Hh), (0, 0, 0, 0))
    out.paste(lay, (0, 0), mk)
    m.ov.alpha_composite(out, (m.P(x), m.P(y)))


def rim(m, x, y, w, h, r, c0=AQUA, c1=PURPLE, glow=4):
    """边：上半青、下半紫的渐变细边 + 一圈外发光 + 顶沿一线高光"""
    for k in range(glow, 0, -1):
        a = int(70 * (1 - k / (glow + 1)))
        m.d.rounded_rectangle([m.P(x) - k, m.P(y) - k, m.P(x + w) + k, m.P(y + h) + k], radius=m.P(r) + k, outline=(c0[0], c0[1], c0[2], a // 2), width=1)
    W, Hh = m.P(w) + 1, m.P(h) + 1
    grad = Image.new('RGBA', (W, Hh))
    gd = ImageDraw.Draw(grad)
    for yy in range(Hh):
        t = yy / max(1, Hh - 1)
        gd.line([(0, yy), (W, yy)], fill=tuple(int(c0[i] + (c1[i] - c0[i]) * t) for i in range(3)) + (210,))
    mk = Image.new('L', (W, Hh), 0)
    ImageDraw.Draw(mk).rounded_rectangle([0, 0, W - 1, Hh - 1], radius=m.P(r), outline=255, width=max(1, m.P(1)))
    edge = Image.new('RGBA', (W, Hh), (0, 0, 0, 0))
    edge.paste(grad, (0, 0), mk)
    m.ov.alpha_composite(edge, (m.P(x), m.P(y)))
    # 顶沿高光（只在上沿中段）
    m.d.line([(m.P(x + r), m.P(y) + 1), (m.P(x + w * 0.55), m.P(y) + 1)], fill=(255, 255, 255, 90), width=1)


def glass(m, x, y, w, h, r=12, c0=AQUA, c1=PURPLE, cau=True, seed=0.0):
    frost(m, x, y, w, h, r)
    # 上亮下暗的一层（水面透光）
    lay = Image.new('RGBA', (m.P(w), m.P(h)), (0, 0, 0, 0))
    ld = ImageDraw.Draw(lay)
    for yy in range(m.P(h)):
        t = yy / max(1, m.P(h) - 1)
        ld.line([(0, yy), (m.P(w), yy)], fill=(120, 220, 255, int(26 * (1 - t))))
    mk = Image.new('L', lay.size, 0)
    ImageDraw.Draw(mk).rounded_rectangle([0, 0, lay.size[0] - 1, lay.size[1] - 1], radius=m.P(r), fill=255)
    o = Image.new('RGBA', lay.size, (0, 0, 0, 0))
    o.paste(lay, (0, 0), mk)
    m.ov.alpha_composite(o, (m.P(x), m.P(y)))
    if cau:
        caustic(m, x, y, w, h, r, seed=seed)
    rim(m, x, y, w, h, r, c0, c1)


def tank(m, x, y, w, h, frac, col, ph=0.0, ticks=(), deep=None):
    """液面槽：玻璃管（暗底 + 管壁高光）里装液体；液体上浅下深，液面一道正弦弯月 + 亮线，管里有气泡"""
    r = h / 2
    m.d.rounded_rectangle(m.R(x, y, w, h), radius=m.P(r), fill=(2, 12, 20, 200))
    fw = max(0.0, w * frac)
    W, Hh = m.P(w), m.P(h)
    liq = Image.new('RGBA', (W, Hh), (0, 0, 0, 0))
    dl = ImageDraw.Draw(liq)
    dc = deep or tuple(int(c * 0.45) for c in col[:3])
    for yy in range(Hh):
        t = yy / max(1, Hh - 1)
        dl.line([(0, yy), (m.P(fw), yy)], fill=tuple(int(col[i] + (dc[i] - col[i]) * t) for i in range(3)) + (235,))
    # 液面：顶部一条波（液体只在波线以下）
    cut = Image.new('L', (W, Hh), 0)
    cd = ImageDraw.Draw(cut)
    pts = [(0, Hh)]
    for k in range(0, m.P(fw) + 1, 2):
        pts.append((k, Hh * 0.2 + m.P(0.9) * math.sin(k / max(1, m.P(5)) + ph)))
    pts.append((m.P(fw), Hh))
    cd.polygon(pts, fill=255)
    liq.putalpha(ImageChops.multiply(liq.getchannel('A'), cut))
    dl2 = ImageDraw.Draw(liq)
    dl2.line(pts[1:-1], fill=(255, 255, 255, 170), width=1)
    # 液头竖向一道亮边（液体前沿）
    if 0 < fw < w:
        dl2.line([(m.P(fw) - 1, Hh * 0.25), (m.P(fw) - 1, Hh - 2)], fill=(255, 255, 255, 120), width=1)
    for k in range(6):
        bx = (0.08 + 0.15 * k) * fw
        by = Hh * (0.55 + 0.2 * math.sin(k * 1.9 + ph))
        dl2.ellipse([m.P(bx), by, m.P(bx) + max(2, m.P(1.6)), by + max(2, m.P(1.6))], outline=(255, 255, 255, 140))
    mk = Image.new('L', (W, Hh), 0)
    ImageDraw.Draw(mk).rounded_rectangle([0, 0, W - 1, Hh - 1], radius=m.P(r), fill=255)
    out = Image.new('RGBA', (W, Hh), (0, 0, 0, 0))
    out.paste(liq, (0, 0), mk)
    m.ov.alpha_composite(out, (m.P(x), m.P(y)))
    # 管壁高光 + 细边
    m.d.line([(m.P(x + r), m.P(y) + 1), (m.P(x + w - r), m.P(y) + 1)], fill=(255, 255, 255, 60), width=1)
    m.d.rounded_rectangle(m.R(x, y, w, h), radius=m.P(r), outline=(170, 230, 255, 90), width=1)
    for t in ticks:
        m.d.line([(m.P(x + w * t), m.P(y) - 2), (m.P(x + w * t), m.P(y + h) + 2)], fill=(255, 230, 160, 200), width=max(1, m.P(1)))


def bubble(m, cx, cy, r, fill=(6, 26, 40, 210), edge=AQUA, glow=True):
    if glow:
        for k in range(4, 0, -1):
            m.d.ellipse([m.P(cx - r) - k, m.P(cy - r) - k, m.P(cx + r) + k, m.P(cy + r) + k], outline=(edge[0], edge[1], edge[2], 18 * (5 - k)))
    m.d.ellipse(m.R(cx - r, cy - r, 2 * r, 2 * r), fill=fill, outline=edge, width=max(1, m.P(1)))
    m.d.arc(m.R(cx - r + 2, cy - r + 2, 2 * r - 4, 2 * r - 4), 200, 260, fill=(255, 255, 255, 140), width=max(1, m.P(1)))


# ================================================================ 件
def leader(m, x, y, phone=False):
    w = 300 if not phone else 260
    glass(m, x + 38, y + 8, w - 38, 64, r=16, seed=0.3)
    # B′ 徽记坐在一口「水井」里：深色圆 + 青色外发光（呼应徽记的环）
    bubble(m, x + 36, y + 40, 34, fill=(4, 18, 30, 235))
    m.img(BADGE, x + 5, y + 8, 62, 64)
    m.text(x + 82, y + 26, '生命', 10, AQUA)
    m.text(x + w - 12, y + 27, '195', 17, TEXT, anchor='rs', bold=True)
    m.text(x + w - 12 - m.tw('195', 17) - 3, y + 27, '/195', 9, SUB, anchor='rs')
    tank(m, x + 82, y + 31, w - 96, 12, 1.0, (70, 225, 240), ph=0.6)
    # 灯火：小灯笼符号 + 金色液槽 + 30 / 70 档位刻度
    m.d.ellipse(m.R(x + 82, y + 52, 9, 11), outline=GOLD, width=max(1, m.P(1.2)))
    m.d.rectangle(m.R(x + 85, y + 50, 3, 2), fill=GOLD)
    tank(m, x + 96, y + 52, w - 146, 9, 1.0, (255, 190, 80), ph=1.8, ticks=(0.3, 0.7), deep=(150, 70, 10))
    m.text(x + w - 12, y + 62, '100', 13, GOLD, anchor='rs', bold=True)
    return w


def status(m, x, y):
    for k, (s, col) in enumerate([('灯火通明 · 技力 +30%', GOLD), ('护盾 ×1', CYAN), ('攻速 +70%', GOLD), ('认知负担 −10%', PURPLE)]):
        yy = y + (k // 2) * 23
        xx = x + (0 if k % 2 == 0 else 176)
        w = m.tw(s, 10) + 26
        frost(m, xx, yy, w, 19, 9.5, k=0.62, blur=4)
        m.d.rounded_rectangle(m.R(xx, yy, w, 19), radius=m.P(9.5), outline=(col[0], col[1], col[2], 150), width=1)
        bubble(m, xx + 10, yy + 9.5, 3.2, fill=col, edge=col)
        m.text(xx + 18, yy + 13.5, s, 10, TEXT)


def info(m, phone=False):
    W = m.W
    n = 4 if not phone else 3
    w = 82 + n * 34
    x = W - 16 - 88 - w
    glass(m, x, 12, w, 36, r=18, seed=1.1)
    m.text(x + 14, 34, '藏品', 10, AQUA)
    m.text(x + 42, 36, '15', 16, TEXT, bold=True)
    for k in range(n):
        bubble(m, x + 82 + k * 34, 30, 14, glow=False, edge=(150, 220, 255, 140))
        m.img(RELIC[k], x + 71 + k * 34, 19, 22, 22)
    # 暂停 / 倍速：两颗玻璃泡；倍速 ≠ 1× 时泡里注满青色液体（这里画 1×：空泡）
    for i, val in enumerate(['Ⅱ', '1×']):
        cx = W - 16 - 62 + i * 42
        bubble(m, cx, 30, 18)
        m.text(cx, 35, val, 13, TEXT, anchor='ms', bold=True)
    m.text(W - 16 - 20, 62, '倍速 V', 8, SUB, anchor='ms')


def squad(m, x, y, cw, ch, phone=False):
    n = 4
    pw = n * (cw + 8) + 14
    ph = ch + 52
    glass(m, x, y, pw, ph, r=16, seed=2.2)
    # 指挥牌：注满青色液体的玻璃胶囊（液面在胶囊里缓缓晃），作战时限 = 同一胶囊下沿的细液槽
    cpw = 150 if not phone else 130
    m.d.rounded_rectangle(m.R(x + 10, y + 9, cpw, 26), radius=m.P(13), fill=(10, 60, 72, 200))
    tank(m, x + 10, y + 9, cpw, 26, 1.0, (40, 170, 180), ph=0.4)
    m.d.rounded_rectangle(m.R(x + 10, y + 9, cpw, 26), radius=m.P(13), outline=CYAN, width=max(1, m.P(1.2)))
    m.text(x + 24, y + 27, '指挥 · 随行', 13, TEXT, bold=True)
    if not phone:
        m.keycap(x + cpw - 14, y + 13, 'F', 9, TEXT)
    tank(m, x + 14, y + 38, cpw - 8, 4, 0.35, (70, 225, 240))
    m.text(x + pw - 12, y + 26, '编队 4/4', 10, AQUA, anchor='rs')
    m.text(x + pw - 12 - m.tw('编队 4/4', 10) - 8, y + 26, '羁绊 2', 10, GOLD, anchor='rs')
    for i, (nm, cls, hp) in enumerate(OPS):
        cx0, cy0 = x + 10 + i * (cw + 8), y + 46
        # 卡：深色玻璃底 + 高精度待机帧（半身，按卡宽整数倍放大）+ 底部水位 = 生命
        m.d.rounded_rectangle(m.R(cx0, cy0, cw, ch), radius=m.P(10), fill=(4, 16, 26, 225))
        caustic(m, cx0, cy0, cw, ch, 10, a=0.06, seed=i)
        src = HI[i]
        sh = ch * (1.25 if not phone else 1.1)
        ww = src.size[0] * max(1, round(m.P(sh) / src.size[1])) / m.s
        lay_x = cx0 + (cw - ww) / 2
        # 裁进卡里（立绘不出框）
        tmp = Image.new('RGBA', m.ov.size, (0, 0, 0, 0))
        k = max(1, round(m.P(sh) / src.size[1]))
        t = src.resize((src.size[0] * k, src.size[1] * k), Image.NEAREST)
        tmp.alpha_composite(t, (m.P(lay_x), m.P(cy0 + 2)))
        mk = rmask(m, cx0 + 1, cy0 + 1, cw - 2, ch - 2, 9)
        m.ov.alpha_composite(Image.composite(tmp, Image.new('RGBA', m.ov.size, (0, 0, 0, 0)), mk))
        # 底部水位（队友 = 生命；队长卡 = 满水，生命在左上）
        lvl = hp if i else 1.0
        wl = ch * 0.26
        tmp2 = Image.new('RGBA', m.ov.size, (0, 0, 0, 0))
        d2 = ImageDraw.Draw(tmp2)
        top = cy0 + ch - wl
        pts = [(m.P(cx0), m.P(cy0 + ch))]
        for q in range(0, m.P(cw * lvl) + 1, 2):
            pts.append((m.P(cx0) + q, m.P(top) + m.P(1.2) * math.sin(q / max(1, m.P(5)) + i)))
        pts.append((m.P(cx0 + cw * lvl), m.P(cy0 + ch)))
        col = (60, 215, 235) if lvl > 0.5 else (255, 190, 80)
        d2.polygon(pts, fill=col + (110,))
        d2.line(pts[1:-1], fill=(255, 255, 255, 170), width=1)
        m.ov.alpha_composite(Image.composite(tmp2, Image.new('RGBA', m.ov.size, (0, 0, 0, 0)), mk))
        m.text(cx0 + cw / 2, cy0 + ch - 6, nm, 10 if not phone else 9, TEXT, anchor='ms', bold=True)
        rim(m, cx0, cy0, cw, ch, 10, c0=(PURPLE if i == 0 else (150, 220, 255, 255)), c1=(PURPLE if i == 0 else (60, 120, 160, 255)), glow=3 if i == 0 else 1)
        # 职业泡（左上）+ 技能泡（右上，高精度技能图标）
        bubble(m, cx0 + 10, cy0 + 10, 7, glow=False, edge=H.CLS[cls])
        m.text(cx0 + 10, cy0 + 13.5, cls, 8, TEXT, anchor='ms')
        if not phone:
            for q in range(3):
                bx = cx0 + cw - 9 - (2 - q) * 15
                m.d.ellipse(m.R(bx - 7, cy0 + 3, 14, 14), fill=(4, 16, 26, 230))
                m.img(SKI[i][q], bx - 6, cy0 + 4, 12, 12)
                m.d.ellipse(m.R(bx - 7, cy0 + 3, 14, 14), outline=([GOLD, CYAN, (120, 140, 160, 255)][q]), width=1)
        if i == 0:
            m.d.rounded_rectangle(m.R(cx0 + cw / 2 - 18, cy0 - 7, 36, 13), radius=m.P(6.5), fill=VIOLET)
            m.text(cx0 + cw / 2, cy0 + 3, '队长', 8, TEXT, anchor='ms', bold=True)
        if i in (1, 2):
            H.M.diamond(m, cx0 + cw - 8, cy0 + ch - 10, 3, GOLD)
    return pw, ph


def guide(m, x, y, w):
    glass(m, x, y, w, 120, r=16, c0=CYAN, c1=AQUA, seed=3.1)
    # 演示窗：深海小水箱
    m.d.rounded_rectangle(m.R(x + 12, y + 12, 116, 96), radius=m.P(10), fill=(2, 12, 22, 230))
    caustic(m, x + 12, y + 12, 116, 96, 10, a=0.12, seed=0.7)
    pix(m, HI[0], x + 48, y + 34, 50)
    for dx, dy in [(18, 22), (96, 18), (100, 74), (22, 70)]:
        H.M.diamond(m, x + 12 + dx, y + 12 + dy, 3.2, (140, 255, 200, 255))
    rim(m, x + 12, y + 12, 116, 96, 10, glow=1)
    # 步骤泡：6 颗，已做的灌满青色，当前的半满在晃
    for k in range(6):
        cx = x + w - 20 - (5 - k) * 16
        bubble(m, cx, y + 22, 5.5, glow=(k == 1))
        if k < 1:
            m.d.ellipse(m.R(cx - 4.5, y + 17.5, 9, 9), fill=CYAN)
        elif k == 1:
            m.d.chord(m.R(cx - 4.5, y + 17.5, 9, 9), 0, 180, fill=CYAN)
    m.text(x + 142, y + 28, '新手引导', 10, AQUA)
    m.text(x + 142, y + 52, '经验与升级', 16, TEXT, bold=True)
    m.text(x + 142, y + 74, '拾取经验结晶，经验条满了就升级，三张卡里选一张。', 11, TEXT)
    bubble(m, x + 147, y + 95, 4, fill=CYAN, edge=CYAN)
    m.text(x + 158, y + 99, '捡起附近的经验结晶', 11, CYAN)


def top_bar(m, y0=10, compact=False):
    """顶部中央战斗顶栏也换成玻璃（信息不变）"""
    W = m.W
    cx = W / 2
    glass(m, cx - 150, y0, 300, 40, r=20, seed=4.0)
    H.top_center(m, y0, compact=compact) if False else None
    m.d.ellipse(m.R(cx - 132, y0 + 12, 16, 16), outline=(255, 140, 50, 255), width=max(1, m.P(2)))
    m.d.ellipse(m.R(cx - 127, y0 + 17, 6, 6), fill=(255, 140, 50, 255))
    m.text(cx - 104, y0 + 31, '1910', 24, TEXT, bold=True)
    m.text(cx - 46, y0 + 31, '击杀', 11, SUB)
    m.d.line([(m.P(cx + 6), m.P(y0 + 10)), (m.P(cx + 6), m.P(y0 + 30))], fill=(150, 220, 255, 90), width=1)
    m.d.ellipse(m.R(cx + 18, y0 + 13, 15, 15), outline=TEXT, width=max(1, m.P(1.6)))
    m.text(cx + 40, y0 + 31, '10:35', 24, TEXT, bold=True)
    if not compact:
        m.text(cx - 62, y0 + 64, '◆ 深蓝之树', 14, TEXT)
        m.en(cx + 18, y0 + 63, 'BLUE TREE', 9, SUB, 3)
        m.text(cx, y0 + 82, '威胁 VI', 10, SUB, anchor='ms')
    by = y0 + (100 if not compact else 52)
    m.text(cx, by - 4, '偏执泡影', 14, TEXT, anchor='ms')
    bw = 540 if not compact else 360
    tank(m, cx - bw / 2, by + 1, bw, 10, 0.55, (190, 150, 255), ph=2.0, deep=(70, 40, 140))
    m.text(cx + bw / 2, by - 4, '阶段护盾 · 时限到后破碎', 10, GOLD, anchor='rs')


# ================================================================ 组装
def desktop():
    m = M(H.DESK_BG, 1.5)
    W, Hh = m.W, m.H
    leader(m, 14, 10)
    status(m, 16, 96)
    top_bar(m)
    info(m)
    cw, ch = 86, 104
    pw = 4 * (cw + 8) + 14
    squad(m, W - 16 - pw, Hh - 16 - (ch + 52), cw, ch)
    H.minimap(m, 16, Hh - 16 - 150, 150)
    H.key_hints(m)
    return m.done(os.path.join(OUT, 'R3_D_desktop.png'), '处理 ② 水月深海 · 精进（电脑 1920×1080）')


def phone():
    m = M(H.PH_BG, 1.25, 1.0)
    W, Hh = m.W, m.H
    leader(m, 10, 8, phone=True)
    status(m, 12, 92)
    top_bar(m, 6, compact=True)
    info(m, phone=True)
    H.phone_buttons(m, '随行', speed=False, pause=False)   # 暂停 / 倍速都在右上信息条
    cw, ch = 64, 62
    pw = 4 * (cw + 8) + 14
    squad(m, W - 12 - pw, Hh - 10 - (ch + 52), cw, ch, phone=True)
    H.minimap(m, 10, Hh - 10 - 96, 96)
    return m.done(os.path.join(OUT, 'R3_D_phone.png'), '处理 ② 水月深海 · 精进（手机横屏）')


NOTES = [
    ('队长块', '角：圆角 16 · 线：上青下紫渐变细边 + 外发光 · 纹理：磨砂（模糊底图）+ 焦散 · 动效：受击时生命液面晃一下再回平，回血时液头冒泡'),
    ('灯火槽', '暖金液体、上浅下深；30 / 70 两根档位刻度穿过槽；灯火低于 30 时液面变暗、气泡停'),
    ('右上信息条', '藏品在玻璃泡里；暂停 / 倍速是两颗泡，倍速 ≠ 1× 时泡里注满青色液体'),
    ('指挥牌', '注满青色液体的胶囊，换模式时液体整体左右荡一下；下沿细液槽 = 作战时限'),
    ('编队卡', '@2x 待机帧（图鉴同款）裁进卡里，不出框；卡底水位 = 队友生命，掉血时水位下降、残血变金色'),
    ('指南卡', '演示窗是一个小水箱；步骤是 6 颗泡，做完的灌满，当前的半满在晃'),
]


def detail():
    bg = H.DESK_BG.crop((560, 480, 1520, 1020)).resize((1920, 1080))
    m = M(bg, 2.0)
    m.rect(0, 0, m.W, m.H, C(0.01, 0.03, 0.05, 0.35))
    leader(m, 20, 20)
    status(m, 22, 106)
    m.W = 940
    info(m)
    m.W = 960
    squad(m, 20, 166, 86, 104)
    guide(m, 440, 150, 500)
    y = 360
    for k, (a, b) in enumerate(NOTES):
        m.text(20, y + k * 26, a, 11, AQUA, bold=True)
        m.text(100, y + k * 26, b, 10, C(0.95, 0.93, 0.85))
    return m.done(os.path.join(OUT, 'R3_D_detail.png'), '处理 ② 水月深海 · 精进 · 件的放大（2 倍）')


if __name__ == '__main__':
    os.makedirs(OUT, exist_ok=True)
    a, b, c = desktop(), phone(), detail()
    dw, dh = 960, 570
    pw = int(1170 * 540 / 540 * dh / 576)
    sheet = Image.new('RGB', (dw * 2 + 12, dh * 2 + 12), (12, 14, 18))
    sheet.paste(a.convert('RGB').resize((dw, dh)), (0, 0))
    sheet.paste(c.convert('RGB').resize((dw, dh)), (dw + 12, 0))
    ph = b.convert('RGB')
    sheet.paste(ph.resize((dw, int(ph.size[1] * dw / ph.size[0]))), (0, dh + 12))
    sheet.save(os.path.join(OUT, 'R3_overview.png'))
    print('ok')
