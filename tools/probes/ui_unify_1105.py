"""局内其余界面按指挥台统一（用户 11-05「指挥圆盘也可以改成 prts 风格…剩下的你也都一起做一下」；卡片 / 商店不改、结算不改）。只出图。
五样：Boss 血条与名片、横幅 / 提示（含屏外指针让开指挥台）、暂停、开局指南卡、指挥圆盘。全部画在同一张带新指挥台的实机底图上。
用法：python ui_unify_1105.py <worktree> <底图 ingame_pc.png> <输出目录>"""
import math, os, sys
sys.argv = [sys.argv[0], sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[3]]   # hud_console_1105 / r3 / r5 在导入时读 argv
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import hud_console_1105 as H
from hud_console_1105 import A, M, CYAN, RED, GOLD, font
from hud_console_1105r3 import WHITE, GREY, DIM, mono
import hud_console_1105r5 as R5
from PIL import Image, ImageEnhance, ImageFilter, ImageDraw

WT, BASE, OUT = sys.argv[1], sys.argv[2], sys.argv[3]
os.makedirs(OUT, exist_ok=True)
base = Image.open(BASE).convert('RGBA')
INK = (10, 14, 16, 255)


def tick(m, x, y, dx, dy, L=10, col=(255, 255, 255, 130)):
    m.line([(x, y + L * dy), (x, y), (x + L * dx, y)], col, 1.0)


def keycap(m, x, y, s, size=7.0, col=WHITE, fill=(0, 0, 0, 140), anchor='l'):
    f = font('semi', m.P(size))
    w = f.getlength(s) / m.s + size * 1.1
    h = size * 1.6
    if anchor == 'r':
        x -= w
    m.rect(x, y - h + 2, w, h, fill=fill, outline=A(col, 160), width=0.7)
    m.text(x + w / 2, y - h / 2 + 2.2, s, size, col, 'semi', 'mm')
    return w


def dim(im, k=0.35, blur=0):
    im = im.convert('RGB')
    if blur:
        im = im.filter(ImageFilter.GaussianBlur(blur))
    return ImageEnhance.Brightness(im).enhance(k).convert('RGBA')


# ---------------------------------------------------------------- 1 Boss 血条 + 名片
def boss():
    m = M(base, 1.5)
    W = m.W
    cx, y = W / 2, 66
    bw = 420
    # 名字行：中文名 + 称号 + 等宽小签；右端状态（破绽 = 可趁机 → 青）
    m.text(cx - bw / 2, y, '最后的骑士', 14, WHITE, 'cn', 'ls')
    nw = font('cn', m.P(14)).getlength('最后的骑士') / m.s
    m.text(cx - bw / 2 + nw + 8, y, '· 堕落的旗手', 9, GREY, 'cn', 'ls')
    mono(m, cx - bw / 2, y - 16, 'TARGET  //  BOSS  ·  PHASE 2', 4.6, A(RED, 220))
    m.text(cx + bw / 2, y, '破绽 2.4 秒 · 受伤 +40%', 9, CYAN, 'cn', 'rs')
    # 血条：洋红 3 像素细线 + 刚掉的白色残影 + 阶段刻度（菱形）+ 右端百分比
    by = y + 9
    frac, trail = 0.62, 0.68
    m.rect(cx - bw / 2, by, bw, 3, fill=(255, 255, 255, 30))
    m.rect(cx - bw / 2, by, bw * trail, 3, fill=(255, 255, 255, 170))
    m.rect(cx - bw / 2, by, bw * frac, 3, fill=RED)
    for t in (0.33, 0.66):
        px = cx - bw / 2 + bw * t
        m.d.polygon([(m.P(px), m.P(by - 3)), (m.P(px + 3), m.P(by + 1.5)), (m.P(px), m.P(by + 6)), (m.P(px - 3), m.P(by + 1.5))],
                    fill=(14, 18, 22, 255), outline=WHITE)
    m.text(cx + bw / 2 + 8, by + 5, '62%', 10, A(WHITE, 220), 'num', 'ls')
    tick(m, cx - bw / 2 - 8, y - 24, 1, 1, 7)
    tick(m, cx + bw / 2 + 36, by + 10, -1, -1, 7)
    # 登场名片（第一次出现时 2 秒，之后收成上面这条）：示意放在下方
    yy = 300
    m.rect(0, yy - 46, W, 92, fill=(0, 0, 0, 120))
    m.line([(cx - 260, yy - 30), (cx + 260, yy - 30)], (255, 255, 255, 60), 0.6)
    mono(m, cx, yy - 36, 'WARNING  //  HOSTILE  BOSS  CONFIRMED', 5.0, A(RED, 230), 'ms')
    m.text(cx, yy + 6, '最后的骑士', 28, WHITE, 'cn', 'ms')
    m.text(cx, yy + 28, '堕落的旗手 · 黑潮的守门人', 10, GREY, 'cn', 'ms')
    m.line([(cx - 260, yy + 38), (cx + 260, yy + 38)], (255, 255, 255, 60), 0.6)
    m.text(cx, yy + 60, '（登场名片：第一次出现时 2 秒，之后收成顶部血条）', 8, A(GREY, 180), 'cn', 'ms')
    return m.done()


# ---------------------------------------------------------------- 2 横幅 / 提示 + 屏外指针让开指挥台
def banners():
    m = M(base, 1.5)
    W, Hh = m.W, m.H
    cx = W / 2
    # 指挥台上方一条「消息带」：最新一条大、旧的往上淡出；不再横跨整屏
    y0 = Hh - 112
    items = [('羁绊成立', '企鹅物流 · 全队攻速 +8%', GOLD, 'SQUAD // BOND', 1.0),
             ('编队上限 +1', '可再招募一名干员', WHITE, 'SQUAD // SLOT', 0.55),
             ('商人', '「洁白的舞鞋」14 锭 · 持有 18 · 可买', GREEN_(), 'MERCHANT', 0.32)]
    for i, (t, sub, col, tag, a) in enumerate(items):
        y = y0 - i * 30
        big = i == 0
        tw = m.text(cx, y, t + '  ', 13 if big else 10, A(col, int(255 * a)), 'cn', 'rs')
        m.text(cx, y, sub, 13 if big else 10, A(WHITE, int(235 * a)), 'cn', 'ls')
        mono(m, cx, y - (19 if big else 15), tag, 4.4, A(GREY, int(220 * a)), 'ms')
        if big:
            for s_ in (-1, 1):
                m.line([(cx + s_ * 20, y + 8), (cx + s_ * 230, y + 8)], (255, 255, 255, 70), 0.6)
    # 屏外指针：贴屏幕边缘，但底边让出指挥台（落在台子上沿之上）
    top_console = Hh - 64
    for (x, y, lab, col) in ((470, top_console - 18, '最后的骑士  16m', RED), (1040, top_console - 18, '商人  9m', (47, 211, 160, 255))):
        m.d.polygon([(m.P(x), m.P(y + 9)), (m.P(x - 6), m.P(y)), (m.P(x + 6), m.P(y))], fill=col)
        m.text(x, y - 5, lab, 9, col, 'cn', 'ms')
    m.line([(0, top_console), (W, top_console)], (255, 255, 255, 30), 0.5)
    m.text(8, top_console - 4, '屏外指针的下边界 = 指挥台上沿', 7, A(GREY, 170), 'cn', 'ls')
    return m.done()


def GREEN_():
    return (47, 211, 160, 255)


# ---------------------------------------------------------------- 3 暂停
def pause():
    m = M(dim(base, 0.3, 4), 1.5)
    W, Hh = m.W, m.H
    L, T = 120, 140
    tick(m, L - 24, T - 40, 1, 1, 12)
    mono(m, L, T - 18, 'PRTS  //  OPERATION  PAUSED', 5.2, GREY)
    m.text(L, T + 16, '暂停', 34, WHITE, 'cn', 'ls')
    rows = (('探索时间', '00:01'), ('等级', 'LV 1 · 精零'), ('击杀', '0'), ('难度', '常规'))
    y = T + 60
    for lab, v in rows:
        m.text(L, y, lab, 11, GREY, 'cn', 'ls')
        m.text(L + 200, y, v, 11, WHITE, 'cn', 'rs')
        m.rect(L, y + 6, 200, 0.6, fill=(255, 255, 255, 25))
        y += 26
    # 右：竖排按钮（字 + 按键），悬停 / 手柄选中的那项左边一道青条、字变白
    bx = 560
    y = T + 2
    btns = (('继续', 'ESC'), ('指南', 'G'), ('演示', 'H'), ('设置', 'O'), ('重新开始', 'R'), ('回到标题', 'T'))
    for i, (t, k) in enumerate(btns):
        on = i == 0
        if on:
            m.rect(bx - 14, y - 18, 2, 24, fill=CYAN)
            m.rect(bx - 12, y - 18, 300, 24, fill=(255, 255, 255, 14))
        m.text(bx, y, t, 16, WHITE if on else A(WHITE, 170), 'cn', 'ls')
        keycap(m, bx + 280, y, k, 6.5, WHITE if on else GREY, anchor='r')
        y += 40
    m.line([(bx - 14, T + 236), (bx + 286, T + 236)], (255, 255, 255, 40), 0.6)
    m.text(bx, T + 258, '重新开始 / 回到标题 会结束本次探索', 9, A(GREY, 200), 'cn', 'ls')
    tick(m, bx + 310, T + 270, -1, -1, 12)
    return m.done()


# ---------------------------------------------------------------- 4 开局指南卡
def guide():
    m = M(base, 1.5)
    x, y, w, h = 24, 120, 360, 128
    m.rect(x, y, w, h, fill=(6, 9, 12, 225))
    m.rect(x, y, 2, h, fill=WHITE)
    tick(m, x + w, y + h, -1, -1, 8)
    # 演示窗
    dx, dy, dw = x + 12, y + 12, 118
    m.rect(dx, dy, dw, h - 24, fill=(0, 0, 0, 150), outline=(255, 255, 255, 50), width=0.6)
    for k in range(1, 4):
        m.line([(dx + dw * k / 4, dy), (dx + dw * k / 4, dy + h - 24)], (255, 255, 255, 14), 0.5)
    R5.mode_icon(m, dx + dw / 2, dy + (h - 24) / 2, 1, 22, WHITE, 1.6)
    m.text(dx + 6, dy + h - 30, '② 突击：队友冲出去', 7.5, A(WHITE, 200), 'cn', 'ls')
    keycap(m, dx + dw - 4, dy + h - 28, 'F', 6.5, anchor='r')
    tx = dx + dw + 14
    mono(m, tx, y + 22, 'TUTORIAL  //  02 · COMMAND', 4.6, GREY)
    for i in range(6):   # 步骤点
        m.circle(x + w - 60 + i * 9, y + 18, 2.0, fill=WHITE if i <= 1 else (255, 255, 255, 50))
    m.text(tx, y + 44, '指挥圆盘', 15, WHITE, 'cn', 'ls')
    m.text(tx, y + 66, '按 F 打开指挥圆盘，给队友下令：', 9.5, A(WHITE, 210), 'cn', 'ls')
    m.text(tx, y + 82, '随行、突击、部署、集火。', 9.5, A(WHITE, 210), 'cn', 'ls')
    m.circle(tx + 3, y + 103, 2.6, outline=CYAN, w=1.0)
    m.text(tx + 12, y + 107, '下达一次指挥', 9.5, CYAN, 'cn', 'ls')
    keycap(m, x + w - 10, y + h - 10, '跳过  ESC', 6.0, GREY, anchor='r')
    return m.done()


# ---------------------------------------------------------------- 5 指挥圆盘（PRTS）
def wheel():
    m = M(dim(base, 0.42, 2), 1.5)
    W, Hh = m.W, m.H
    cx, cy = W / 2, Hh / 2 - 14
    R0, R1 = 70, 196
    names = ('随行', '突击', '部署', '集火')
    ens = ('ESCORT', 'ASSAULT', 'DEPLOY', 'FOCUS')
    desc = ('队长身边护卫 · 队友不受伤', '按职业分工出击 · 限时', '指定地点落位驻扎 · 限时', '点精英或 Boss · 全队集火 · 限时')
    sel, cur = 1, 0
    # 外圈刻度 + 取景框
    m.arc(cx, cy, R1 + 10, 0, 360, (255, 255, 255, 40), 0.8)
    for a in range(0, 360, 5):
        t = math.radians(a)
        L_ = 6 if a % 45 == 0 else 3
        m.line([(cx + math.cos(t) * (R1 + 14), cy + math.sin(t) * (R1 + 14)), (cx + math.cos(t) * (R1 + 14 + L_), cy + math.sin(t) * (R1 + 14 + L_))],
               (255, 255, 255, 90 if a % 45 == 0 else 40), 0.6)
    for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
        tick(m, cx + sx * (R1 + 44), cy + sy * (R1 + 30), -sx, -sy, 14)
    # 四扇：只描边、极淡底；选中那扇白边 + 外沿一道青弧 + 微亮底
    gap = 3.0
    for i in range(4):
        a0 = -90 + i * 90 + gap
        a1 = a0 + 90 - 2 * gap
        pts = []
        for k in range(31):
            t = math.radians(a0 + (a1 - a0) * k / 30)
            pts.append((cx + math.cos(t) * R1, cy + math.sin(t) * R1))
        for k in range(30, -1, -1):
            t = math.radians(a0 + (a1 - a0) * k / 30)
            pts.append((cx + math.cos(t) * R0, cy + math.sin(t) * R0))
        P = [(m.P(a), m.P(b)) for a, b in pts]
        on = i == sel
        m.d.polygon(P, fill=(255, 255, 255, 26) if on else (8, 10, 12, 150))
        m.d.line(P + [P[0]], fill=(236, 238, 240, 230) if on else (255, 255, 255, 60), width=max(1, round(m.P(1.2 if on else 0.6))))
        if on:
            m.arc(cx, cy, R1 + 4, a0, a1, CYAN, 2.4)
        mid = math.radians((a0 + a1) / 2)
        rr = (R0 + R1) / 2 + 6
        px, py = cx + math.cos(mid) * rr, cy + math.sin(mid) * rr
        R5.mode_icon(m, px, py - 30, i, 12, WHITE if on else A(WHITE, 170), 1.4)
        m.text(px, py + 2, names[i], 17, WHITE if on else A(WHITE, 190), 'cn', 'ms')
        mono(m, px, py + 16, '%02d // %s' % (i + 1, ens[i]), 4.8, CYAN if on else GREY, 'ms')
        if i == cur:
            m.rect(px - 15, py + 22, 30, 12, fill=WHITE)
            m.text(px, py + 31.5, '当前', 7.5, INK, 'cn', 'ms')
    # 中心：当前指令 + 作战时限环
    m.circle(cx, cy, R0 - 8, fill=(6, 8, 10, 230), outline=(255, 255, 255, 70), w=0.6)
    stam = 0.72
    m.arc(cx, cy, R0 - 14, 0, 360, (255, 255, 255, 35), 2.4)
    m.arc(cx, cy, R0 - 14, -90, -90 + 360 * stam, WHITE, 2.4)
    mono(m, cx, cy - 20, 'COMMAND', 4.4, GREY, 'ms')
    m.text(cx, cy + 6, names[sel], 18, WHITE, 'cn', 'ms')
    m.text(cx, cy + 24, '作战时限 18s', 8, GREY, 'cn', 'ms')
    # 底部说明：一行描述 + 共用出击加成 + 按键
    by = cy + R1 + 46
    m.text(cx, by, desc[sel], 12, WHITE, 'cn', 'ms')
    m.text(cx, by + 20, '出击加成：攻速 +25% · 技力回复 ×1.5', 9.5, GREY, 'cn', 'ms')
    mono(m, cx, by + 38, 'PRTS  //  COMMAND  TERMINAL', 4.6, A(GREY, 180), 'ms')
    k1 = keycap(m, cx - 120, by + 58, '点选 / ENTER', 6.0)
    m.text(cx - 120 + k1 + 6, by + 56, '确认', 9, GREY, 'cn', 'ls')
    k2 = keycap(m, cx + 30, by + 58, 'ESC / F', 6.0)
    m.text(cx + 30 + k2 + 6, by + 56, '取消', 9, GREY, 'cn', 'ls')
    return m.done()


def main():
    for nm, fn in (('boss', boss), ('banners', banners), ('pause', pause), ('guide', guide), ('wheel', wheel)):
        fn().save(os.path.join(OUT, 'new_%s.png' % nm))
    print('ok')


if __name__ == '__main__':
    main()
