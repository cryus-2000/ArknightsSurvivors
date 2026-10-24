"""Boss 改版方案 B 示意图（docs/142b）：每只 Boss 一张，每栏一条规则——主轴怎么做、下一幕规则怎么换。
画法沿用 boss_phase_sheets.py（程序画的形状 + 现有帧条第 0 帧，不是游戏截图），另加路线、连线、掩体、血条、弹药格等主轴元素。

    python tools/probes/boss_axis_sheets.py            # 输出 build/boss_axis_sheets/<boss>.png
"""
import math, os, random, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import boss_phase_sheets as B
from PIL import Image, ImageDraw

OUT = os.path.join(B.ROOT, "build", "boss_axis_sheets")
PW, PH = B.PW, B.PH
CX, CY = PW // 2, 150
GOLD = (1.0, 0.82, 0.3)
CYAN = (0.35, 0.95, 1.0)
FRAMES = {"prop_ice_stake": 2, "prop_lamp_post": 3, "e_bone": 4, "e_offspring": 4, "e_tear": 4, "e_fractal": 4}


def spr(key, scale, tint=None, alpha=1.0):
    p = os.path.join(B.INC, key + "@2x.png")
    if not os.path.exists(p):
        p = os.path.join(B.INC, key + ".png")
        scale *= 2
    im = Image.open(p).convert("RGBA")
    spec = B.PIX.get(key, {})
    if key in FRAMES:
        im = im.crop((0, 0, im.width // FRAMES[key], im.height))
    elif spec.get("frame_size"):
        fs = spec["frame_size"]
        im = im.crop((0, 0, fs[0], fs[1]))
    im = im.resize((max(1, int(im.width * scale)), max(1, int(im.height * scale))), Image.NEAREST)
    if tint:
        im = B.tinted(im, tint)
    if alpha < 1.0:
        im.putalpha(im.split()[3].point(lambda v: int(v * alpha)))
    return im


def put(im, key, scale, x, y, tint=None, alpha=1.0):
    s = spr(key, scale, tint, alpha)
    im.alpha_composite(s, (int(x - s.width / 2), int(y - s.height)))
    return s


def gold_mark(d, x, y, r=16):
    d.ellipse((x - r, y - r * 0.5, x + r, y + r * 0.5), outline=B.rgb(GOLD, 1.2), width=3)
    d.polygon([(x, y - r - 14), (x - 5, y - r - 20), (x - 3, y - r - 25), (x, y - r - 22), (x + 3, y - r - 25), (x + 5, y - r - 20)], fill=B.rgb(GOLD, 1.2))


def cyan_ring(d, x, y, r, frac=0.65):
    d.arc((x - r, y - r * 0.5, x + r, y + r * 0.5), -90, -90 + 360 * frac, fill=B.rgb(CYAN, 1.2), width=4)
    d.arc((x - r, y - r * 0.5, x + r, y + r * 0.5), -90 + 360 * frac, 270, fill=B.rgb(CYAN, 0.4), width=2)


def dash_mark(d, x, y, r=40):
    d.ellipse((x - r, y - r * 0.5, x + r, y + r * 0.5), outline=(255, 255, 255), width=2)
    d.ellipse((x - r - 4, y - r * 0.5 - 3, x + r + 4, y + r * 0.5 + 3), outline=(255, 255, 255), width=2)
    d.polygon([(x + r + 10, y - 6), (x + r + 22, y), (x + r + 10, y + 6)], fill=(255, 255, 255))
    d.line((x + r + 2, y, x + r + 12, y), fill=(255, 255, 255), width=3)


def path_line(d, pts, col, cut=None):
    for i in range(len(pts) - 1):
        d.line((pts[i], pts[i + 1]), fill=B.rgb(col, 0.5, 140), width=10)
        d.line((pts[i], pts[i + 1]), fill=B.rgb(col, 1.1, 230), width=3)
    if cut:
        x, y = cut
        d.rectangle((x - 9, y - 9, x + 9, y + 9), fill=B.BG + (255,))
        d.line((x - 9, y - 9, x + 9, y + 9), fill=B.rgb(GOLD, 1.2), width=3)
        d.line((x - 9, y + 9, x + 9, y - 9), fill=B.rgb(GOLD, 1.2), width=3)


def arrow(d, x, y, ang, col, s=16):
    dx, dy = math.cos(ang), math.sin(ang)
    d.polygon([(x + dx * s, y + dy * s), (x - dy * s * 0.6, y + dx * s * 0.6), (x + dy * s * 0.6, y - dx * s * 0.6)], fill=B.rgb(col, 1.2))


def bar(d, x, y, w, frac, col, label=None):
    d.rectangle((x, y, x + w, y + 8), fill=(30, 34, 46), outline=(200, 200, 210))
    d.rectangle((x + 1, y + 1, x + 1 + (w - 2) * frac, y + 7), fill=B.rgb(col, 1.0))
    if label:
        d.text((x, y - 18), label, font=B.font(13), fill=(230, 230, 230))


def pips(d, x, y, n, full, col):
    for i in range(n):
        f = B.rgb(col, 1.2) if i < full else (50, 50, 60)
        d.rectangle((x + i * 14, y, x + i * 14 + 10, y + 10), fill=f, outline=(230, 230, 230))


def fire_line(d, x0, y0, x1, y1, col, w=16, fading=False, gap=None, gap_len=70):
    """卡门的封锁线：打完留下的火线（低亮度填充 + 危险色细描边，不闪）；gap = 缺口在线上的位置（0–1），白圈标出"""
    def seg(ax, ay, bx, by):
        ang = math.atan2(by - ay, bx - ax); nx, ny = -math.sin(ang) * w / 2, math.cos(ang) * w / 2
        a = 70 if fading else 140
        d.polygon([(ax + nx, ay + ny), (bx + nx, by + ny), (bx - nx, by - ny), (ax - nx, ay - ny)], fill=B.rgb(col, 0.6, a), outline=(255, 60, 110, 200 if not fading else 90))
    if gap is None:
        seg(x0, y0, x1, y1)
        return
    L = math.hypot(x1 - x0, y1 - y0); h = gap_len / 2 / L
    ga, gb = gap - h, gap + h
    seg(x0, y0, x0 + (x1 - x0) * ga, y0 + (y1 - y0) * ga)
    seg(x0 + (x1 - x0) * gb, y0 + (y1 - y0) * gb, x1, y1)
    gx, gy = x0 + (x1 - x0) * gap, y0 + (y1 - y0) * gap
    d.ellipse((gx - 10, gy - 6, gx + 10, gy + 6), outline=(255, 255, 255), width=2)


def node(d, x, y):
    """塑路者路线上的路标（金色小菱形）"""
    d.polygon([(x, y - 9), (x + 7, y), (x, y + 9), (x - 7, y)], fill=B.rgb(GOLD, 1.2), outline=(255, 255, 255))


def panel(act, rng):
    im = Image.new("RGBA", (PW, PH), B.BG + (255,))
    d = ImageDraw.Draw(im, "RGBA")
    B.ground(d, act.get("ground", "none"), act["col"], CX, CY + 40, rng)
    for step in act["draw"]:
        step(im, d)
    if act.get("players", True):
        B.players(d, act.get("P", [(CX + 10, CY + 150), (CX - 110, CY + 120), (CX + 140, CY + 125)]))
    return im


def sheet(key, title, acts):
    rng = random.Random(11)
    W = PW * len(acts) + 10 * (len(acts) + 1)
    H = 56 + PH + B.TXT_H + 10
    im = Image.new("RGBA", (W, H), (8, 10, 16, 255))
    d = ImageDraw.Draw(im)
    d.text((12, 12), title, font=B.font(24), fill=(240, 240, 240))
    for i, act in enumerate(acts):
        x = 10 + i * (PW + 10)
        im.alpha_composite(panel(act, rng), (x, 56))
        d.rectangle((x, 56, x + PW - 1, 56 + 30), fill=(0, 0, 0, 200))
        d.text((x + 10, 60), act["name"], font=B.font(18), fill=B.rgb(act["col"], 1.3))
        y = 56 + PH + 8
        for ln in act["lines"]:
            for w in B.wrap(ln, 34):
                d.text((x + 6, y), w, font=B.font(14), fill=(215, 220, 230))
                y += 19
    os.makedirs(OUT, exist_ok=True)
    p = os.path.join(OUT, key + ".png")
    im.convert("RGB").save(p, optimize=True)
    print(p)


L = lambda f: f   # 可读性：每个 draw 步骤都是 (im, d) -> None
ICE = (0.55, 0.85, 1.0)
PL = (CX + 10, CY + 150)

KNIGHT = ("最后的骑士 · 斗牛（方案 B）", [
    {"name": "主轴：引它撞桩", "col": ICE, "P": [(CX + 150, CY + 170), (CX + 60, CY + 190), (CX + 210, CY + 150)], "draw": [
        L(lambda im, d: B.beam(d, CX - 150, CY + 20, CX + 150, CY + 170, 30, ICE)),
        L(lambda im, d: put(im, "prop_ice_stake", 0.7, CX + 40, CY + 125)),
        L(lambda im, d: gold_mark(d, CX + 40, CY + 120)),
        L(lambda im, d: put(im, "e_knight", 0.8, CX - 150, CY + 60)),
        L(lambda im, d: bar(d, 20, PH - 24, 150, 0.35, ICE, "寒冷条（进寒气圈就涨）")),
        L(lambda im, d: d.ellipse((CX - 150 - 140, CY + 60 - 70, CX - 150 + 140, CY + 60 + 70), outline=B.rgb(ICE, 0.5, 120), width=2)),
        L(lambda im, d: d.text((CX + 60, CY + 60), "正面受伤 ×0.4", font=B.font(15), fill=(255, 255, 255))),
    ], "lines": ["站到「冰枪桩在你和它之间」的位置，冲锋锁定后侧身，让它撞上去。", "原作反冻，按自动攻击改：打它的干员攻速 −30%（平时输出打折）；队长进它脚下的寒气圈就涨寒冷条，满了冻 1 秒、下一击 ×1.75。"]},
    {"name": "撞上 = 破绽 5 秒", "col": ICE, "draw": [
        L(lambda im, d: put(im, "prop_ice_stake", 0.7, CX + 20, CY + 95)),
        L(lambda im, d: put(im, "e_knight", 0.8, CX - 30, CY + 80)),
        L(lambda im, d: cyan_ring(d, CX - 30, CY + 60, 90, 0.7)),
        L(lambda im, d: d.text((CX + 70, CY + 30), "受伤 ×2.0\n攻速减益解除\n贴上去不涨寒冷", font=B.font(15), fill=(255, 255, 255))),
        L(lambda im, d: bar(d, 20, PH - 24, 150, 0.1, ICE, "寒冷条")),
    ], "lines": ["长枪脱手，青色倒计时环 5 秒；这段时间打满。", "二幕：桩撞一次就碎，新桩只能靠它「掷枪」补——掷枪既是威胁也是资源。"]},
    {"name": "重生 · 冲锋形态：桩不管用了", "col": (0.6, 0.8, 1.0), "draw": [
        L(lambda im, d: B.beam(d, 40, CY + 110, PW - 40, CY + 110, 26, (0.6, 0.8, 1.0))),
        L(lambda im, d: B.beam(d, PW - 40, CY + 150, 40, CY + 165, 26, (0.6, 0.8, 1.0))),
        L(lambda im, d: B.beam(d, 40, CY + 205, PW - 40, CY + 200, 26, (0.6, 0.8, 1.0))),
        L(lambda im, d: put(im, "prop_ice_stake", 0.6, CX - 60, CY + 120, alpha=0.4)),
        L(lambda im, d: put(im, "e_knight_walk_charge", 0.75, CX + 150, CY + 70)),
        L(lambda im, d: cyan_ring(d, CX + 150, CY + 50, 80, 0.4)),
        L(lambda im, d: d.text((30, CY - 20), "三连冲后喘气 2.5 秒：受伤 ×2.0", font=B.font(15), fill=(255, 255, 255))),
    ], "lines": ["原作不可阻挡：撞碎桩继续冲。规则从「引它撞桩」换成「躲过三连冲，趁喘气打」。", "原作「释放当前波次」：重生时刷一波 16 只普通海嗣。"]},
])

STEEL, FRACT = (0.7, 0.8, 0.95), (0.55, 0.65, 1.0)
PATH = ("塑路者 · 截路（方案 B）", [
    {"name": "主轴：跑过路标截断", "col": STEEL, "P": [(CX + 120, CY + 160), (CX + 40, CY + 180), (CX + 200, CY + 175)], "draw": [
        L(lambda im, d: path_line(d, [(CX, CY + 60), (CX + 80, CY + 110), (CX + 120, CY + 160), (CX + 230, CY + 190)], STEEL, cut=(CX + 120, CY + 160))),
        L(lambda im, d: [node(d, x, y) for x, y in ((CX + 40, CY + 85), (CX - 45, CY + 80), (CX - 120, CY + 135), (CX - 195, CY + 185), (CX + 175, CY + 175))]),
        L(lambda im, d: path_line(d, [(CX, CY + 60), (CX - 90, CY + 100), (CX - 150, CY + 170), (CX - 240, CY + 200)], STEEL)),
        L(lambda im, d: put(im, "e_path", 0.5, CX, CY + 70)),
        L(lambda im, d: [put(im, "e_fractal", 0.45, x, y, tint=(0.8, 0.9, 1.2)) for x, y in ((CX + 175, CY + 190), (CX - 120, CY + 150), (CX - 200, CY + 200))]),
        L(lambda im, d: gold_mark(d, CX + 175, CY + 188)),
        L(lambda im, d: d.text((20, 96), "分形沿路走到尽头 = 塑路者 +1 层强化", font=B.font(15), fill=(255, 255, 255))),
    ], "lines": ["每 10 秒铺一条「生路」，分形沿路往外走。路线上每段有个金色路标，跑过去碰到就截断（不用停）：断口以外的分形停住、变成金色目标。", "全部截断那一刻它「迷路」：硬直 3 秒、受伤 ×1.5。"]},
    {"name": "二幕 · 订正：分形往回走", "col": FRACT, "ground": "fractal", "draw": [
        L(lambda im, d: path_line(d, [(CX - 230, CY + 60), (CX - 150, CY + 130), (CX - 30, CY + 120), (CX, CY + 70)], FRACT)),
        L(lambda im, d: path_line(d, [(CX + 240, CY + 200), (CX + 160, CY + 130), (CX + 60, CY + 140), (CX, CY + 70)], FRACT)),
        L(lambda im, d: [arrow(d, x, y, a, FRACT) for x, y, a in ((CX - 150, CY + 130, -0.1), (CX + 160, CY + 130, 3.0))]),
        L(lambda im, d: put(im, "e_path", 0.5, CX, CY + 70, tint=(0.9, 0.95, 1.25))),
        L(lambda im, d: [put(im, "e_fractal", 0.45, x, y, tint=(0.8, 0.9, 1.2)) for x, y in ((CX - 190, CY + 100), (CX + 200, CY + 170))]),
        L(lambda im, d: d.text((20, 96), "走回它身上 = 回 3% 生命", font=B.font(15), fill=(255, 255, 255))),
    ], "lines": ["方向反过来：分形沿路线往回走，走回去给它回血（「订正」）。一次两条路。", "被截断的路 2 秒后绕开你改道重铺一段，要跟着去截。"]},
])

ORANGE = (1.0, 0.45, 0.2)
IBERIA = ("圣徒伊比利亚 · 打断（方案 B）", [
    {"name": "① 躲一炮", "col": ORANGE, "draw": [
        L(lambda im, d: B.beam(d, CX, CY + 40, CX + 30, PH - 10, 18, ORANGE)),
        L(lambda im, d: put(im, "e_saint_dark", 0.8, CX, CY + 60)),
        L(lambda im, d: pips(d, CX - 7, CY - 50, 1, 1, ORANGE)),
        L(lambda im, d: arrow(d, CX - 40, CY + 165, math.pi, (1, 1, 1))),
    ], "lines": ["手炮是全场最重的一发，锁定后贯穿直线；侧移躲开。头顶 1 格弹药。"]},
    {"name": "② 趁装填冲刺穿身", "col": ORANGE, "draw": [
        L(lambda im, d: put(im, "e_saint_dark", 0.8, CX, CY + 60)),
        L(lambda im, d: pips(d, CX - 7, CY - 50, 1, 0, ORANGE)),
        L(lambda im, d: bar(d, CX - 40, CY - 30, 80, 0.55, ORANGE)),
        L(lambda im, d: dash_mark(d, CX, CY + 55, 44)),
        L(lambda im, d: d.line((CX - 160, CY + 160, CX + 90, CY + 20), fill=(255, 255, 255), width=3)),
        L(lambda im, d: arrow(d, CX + 90, CY + 20, -0.5, (1, 1, 1))),
    ], "lines": ["装填 2.2 秒（读条），身上出白色双描边 + 冲刺图标：冲刺穿过去就打断。", "二幕：装填缩到 1.4 秒，只有冲刺穿身算打断；你靠近时它先抡一下（原作近战模式）。"]},
    {"name": "③ 晕眩 5 秒，打满", "col": ORANGE, "draw": [
        L(lambda im, d: put(im, "e_saint_dark", 0.8, CX, CY + 60, tint=(0.8, 0.8, 0.9))),
        L(lambda im, d: cyan_ring(d, CX, CY + 45, 70, 0.6)),
        L(lambda im, d: d.text((CX + 70, CY + 20), "受伤 ×1.5", font=B.font(15), fill=(255, 255, 255))),
    ], "P": [(CX + 50, CY + 100), (CX - 70, CY + 110), (CX + 100, CY + 140)],
     "lines": ["没打断：装填完是手炮三连。节奏就是「躲 → 冲 → 打」一圈一圈转。"]},
])

GOLDC = (1.0, 0.76, 0.3)
CARMEN = ("圣徒卡门 · 封锁线（方案 B）", [
    {"name": "主轴：三条火线切出跑道", "col": GOLDC, "P": [(CX - 40, CY + 205), (CX - 80, CY + 195), (CX, CY + 215)], "draw": [
        L(lambda im, d: [fire_line(d, 20, CY + 60 + k * 70, PW - 20, CY + 20 + k * 70, GOLDC, gap=g) for k, g in ((0, 0.78), (1, 0.3), (2, 0.62))]),
        L(lambda im, d: put(im, "e_saint", 0.8, PW - 70, CY + 20)),
        L(lambda im, d: pips(d, PW - 91, CY - 90, 3, 0, GOLDC)),
        L(lambda im, d: d.line((CX - 40, CY + 205, 20 + (PW - 40) * 0.62, CY + 160 - 0.62 * 40, 20 + (PW - 40) * 0.3, CY + 130 - 0.3 * 40 - 12, 20 + (PW - 40) * 0.78, CY + 60 - 0.78 * 40, PW - 80, CY + 5), fill=(255, 255, 255), width=3, joint="curve")),
        L(lambda im, d: arrow(d, PW - 80, CY + 5, -0.6, (1, 1, 1))),
        L(lambda im, d: d.text((20, 96), "每条火线留一处缺口，缺口错开：S 形穿过去", font=B.font(15), fill=(255, 255, 255))),
    ], "lines": ["她连开 3 枪，每枪打完留一条火线 6 秒（碰到掉血 + 减速），每条线上留一处缺口（白圈），三条的缺口错开——边跑边 S 形穿过缺口绕到她身边。", "3 枪后装填 3 秒：火线消退、她站定、受伤 ×1.5，压上去打。"]},
    {"name": "二幕 · 守誓：交叉成格", "col": (1.0, 0.9, 0.65), "ground": "cross_cracks", "P": [(CX + 40, CY + 160), (CX, CY + 175), (CX + 80, CY + 180)], "draw": [
        L(lambda im, d: fire_line(d, 20, CY + 40, PW - 20, CY + 90, (1.0, 0.9, 0.65), gap=0.75)),
        L(lambda im, d: fire_line(d, 20, CY + 150, PW - 20, CY + 200, (1.0, 0.9, 0.65), gap=0.2)),
        L(lambda im, d: fire_line(d, CX - 120, 40, CX - 60, PH - 10, (1.0, 0.9, 0.65), gap=0.55)),
        L(lambda im, d: B.beam(d, PW - 20, CY + 130, 20, CY + 160, 10, (1.0, 0.9, 0.65))),
        L(lambda im, d: put(im, "e_saint", 0.8, 70, CY + 110)),
        L(lambda im, d: arrow(d, CX + 40, CY + 135, -math.pi / 2, (1, 1, 1))),
        L(lambda im, d: d.text((20, 96), "第三枪锁你所在的跑道：1 秒里换格", font=B.font(15), fill=(255, 255, 255))),
    ], "lines": ["三枪分两个方向，火线交叉把场地切成格子；最后一枪锁定的是你所在的那条跑道，要在锁定的 1 秒里换到隔壁格子。", "装填时她退避跳到场地另一边——窗口还在，但要多跑一段。"]},
])

PURPLE = (0.8, 0.4, 1.0)
PARANOIA = ("“偏执泡影” · 打落（方案 B）", [
    {"name": "主轴：冲刺穿身，把她打落", "col": PURPLE, "ground": "mist_ring", "draw": [
        L(lambda im, d: put(im, "e_paranoia", 0.55, CX, CY + 40)),
        L(lambda im, d: dash_mark(d, CX, CY + 60, 46)),
        L(lambda im, d: d.line((CX - 170, CY + 170, CX + 70, CY + 20), fill=(255, 255, 255), width=3)),
        L(lambda im, d: arrow(d, CX + 70, CY + 20, -0.55, (1, 1, 1))),
        L(lambda im, d: d.text((20, 96), "悬浮：受伤 ×0.5", font=B.font(15), fill=(255, 255, 255))),
    ], "lines": ["悬浮时打不太动。冲刺穿过她（本作把冲刺穿身算作原作的「异常效果」）→ 坠地 4 秒、受伤 ×1.8。", "难点在靠近：光环压攻速、凝视逼你横移、冲刺有冷却。"]},
    {"name": "二幕 · 狂望：只有真身有影子", "col": (1.0, 0.35, 0.8), "draw": [
        L(lambda im, d: [d.ellipse((x - 34, CY + 112, x + 34, CY + 128), fill=(0, 0, 0, 200)) for x in (CX,)]),
        L(lambda im, d: put(im, "e_paranoia", 0.5, CX - 150, CY + 40, alpha=0.75)),
        L(lambda im, d: put(im, "e_paranoia", 0.5, CX, CY + 40)),
        L(lambda im, d: put(im, "e_paranoia", 0.5, CX + 150, CY + 40, alpha=0.75)),
        L(lambda im, d: d.text((CX - 34, CY + 132), "影子", font=B.font(14), fill=(255, 255, 255))),
        L(lambda im, d: d.text((20, PH - 30), "冲错 = 幻影炸开 + 丢一次冲刺", font=B.font(15), fill=(255, 255, 255))),
    ], "lines": ["分出 2 个幻影一起漂；地上只有真身投下影子（同类游戏 HoloCure 的影子语言）。自动攻击打最近的那只，所以要站得离真身最近；幻影挨 3 下就散。冲刺认错 = 丢一次冲刺。"]},
    {"name": "三幕 · 失声：冲刺打散光环", "col": (0.55, 0.25, 0.8), "ground": "cracks", "draw": [
        L(lambda im, d: [d.ellipse((CX - r, CY + 40 - r * 0.5, CX + r, CY + 40 + r * 0.5), fill=B.rgb((0.55, 0.25, 0.8), 0.35, 60 + i * 20)) for i, r in enumerate((240, 180, 120))]),
        L(lambda im, d: d.ellipse((CX - 240, CY + 40 - 120, CX + 240, CY + 40 + 120), outline=B.rgb((0.55, 0.25, 0.8), 1.2), width=3)),
        L(lambda im, d: put(im, "e_paranoia_phase2", 0.5, CX, CY + 60)),
        L(lambda im, d: dash_mark(d, CX, CY + 60, 46)),
        L(lambda im, d: d.line((CX - 230, CY + 175, CX + 60, CY + 30), fill=(255, 255, 255), width=3)),
        L(lambda im, d: arrow(d, CX + 60, CY + 30, -0.47, (1, 1, 1))),
        L(lambda im, d: d.text((CX - 20, PH - 30), "光环内攻速 −35%；穿身 = 光环散掉 5 秒", font=B.font(15), fill=(255, 255, 255))),
    ], "P": [(CX - 230, CY + 175), (CX - 270, CY + 150), (CX - 190, CY + 195)],
     "lines": ["原作第二形态落地，不再悬浮。冲刺的用处换成打散光环：光环加重（攻速 −35%，近战必须进去、远程站外够不着），冲刺穿身 = 光环散掉 5 秒，这 5 秒正常输出。", "最终战清场单挑：登场时杂兵消散，之后不刷。"]},
])

TEAL = (0.2, 1.0, 0.85)
ISHAR = ("伊莎玛拉 · 破网（方案 B）", [
    {"name": "主轴：杀连线海嗣，拆护盾", "col": TEAL, "draw": [
        L(lambda im, d: [d.line((CX, CY + 20, x, y - 20), fill=B.rgb(TEAL, 0.7, 200), width=2) for x, y in ((CX - 170, CY + 80), (CX - 110, CY + 190), (CX + 120, CY + 200), (CX + 190, CY + 90))]),
        L(lambda im, d: [put(im, "e_bone", 0.6, x, y) for x, y in ((CX - 170, CY + 80), (CX - 110, CY + 190), (CX + 120, CY + 200), (CX + 190, CY + 90))]),
        L(lambda im, d: [gold_mark(d, x, y - 4, 22) for x, y in ((CX - 170, CY + 80), (CX - 110, CY + 190), (CX + 120, CY + 200), (CX + 190, CY + 90))]),
        L(lambda im, d: put(im, "e_ishar_t", 0.4, CX, CY + 50)),
        L(lambda im, d: [d.arc((CX - 75, CY - 40, CX + 75, CY + 60), -90 + i * 60 + 4, -90 + i * 60 + 56, fill=B.rgb(TEAL, 1.2 if i < 4 else 0.3), width=5) for i in range(6)]),
        L(lambda im, d: d.text((20, 96), "护盾环 4/6：受伤 −40%", font=B.font(15), fill=(255, 255, 255))),
    ], "P": [(CX + 10, CY + 140), (CX - 60, CY + 150), (CX + 70, CY + 150)],
     "lines": ["她的歌把海嗣连成网：每只连着的给她 −10% 受伤（最多 6 只）。连线海嗣站在离她一段距离的一圈上，自动攻击会先打它们——队长要绕着她走过去，让它们进射程。", "她每 6 秒从场边叫来 3 只补进圈里。"]},
    {"name": "二幕 · 濒死强化：先打碎泪", "col": (1.0, 0.3, 0.38), "ground": "blood", "draw": [
        L(lambda im, d: [d.line((x0, y0, x, y - 20), fill=B.rgb(TEAL, 0.7, 200), width=2) for (x0, y0) in ((CX - 150, CY + 40), (CX + 150, CY + 40)) for x, y in ((CX - 200, CY + 160), (CX + 200, CY + 170))]),
        L(lambda im, d: [put(im, "e_bone", 0.6, x, y) for x, y in ((CX - 200, CY + 160), (CX + 200, CY + 170))]),
        L(lambda im, d: [put(im, "e_tear", 0.8, x, y) for x, y in ((CX - 150, CY + 60), (CX + 150, CY + 60))]),
        L(lambda im, d: [gold_mark(d, x, y, 26) for x, y in ((CX - 150, CY + 55), (CX + 150, CY + 55))]),
        L(lambda im, d: put(im, "e_ishar_t", 0.4, CX, CY + 40, tint=(1.2, 0.8, 0.85))),
        L(lambda im, d: d.text((20, 96), "泪在：网上限 10，断线 3 秒自动接上", font=B.font(15), fill=(255, 255, 255))),
    ], "lines": ["原作召 2 个泪。泪是歌眼：泪在场时断掉的线会自动接回去——规则从「清怪」变成「先拆核心」。", "三幕「回声」：被杀的连线海嗣死后留音圈，1 秒后爆开，近身清场开始有代价。"]},
])

GREEN = (0.55, 1.0, 0.65)
IZUMIK = ("伊祖米克 · 拦截（方案 B）", [
    {"name": "主轴：半路截杀子代", "col": GREEN, "ground": "roots", "draw": [
        L(lambda im, d: put(im, "e_izumik", 0.45, CX, CY + 70)),
        L(lambda im, d: [put(im, "e_offspring", 0.55, x, y) for x, y in ((70, CY + 110), (120, CY + 140), (60, CY + 170), (150, CY + 95))]),
        L(lambda im, d: [gold_mark(d, x, y - 4, 18) for x, y in ((70, CY + 110), (120, CY + 140), (60, CY + 170), (150, CY + 95))]),
        L(lambda im, d: [d.line((x, y - 30, CX - 20, CY + 30), fill=B.rgb(GREEN, 0.6, 160), width=1) for x, y in ((70, CY + 110), (120, CY + 140))]),
        L(lambda im, d: arrow(d, 16, CY + 130, 0.0, GOLD, 18)),
        L(lambda im, d: d.text((CX + 60, CY - 10), "强化 ●●○○", font=B.font(15), fill=(255, 255, 255))),
    ], "P": [(170, CY + 150), (140, CY + 190), (210, CY + 180)],
     "lines": ["子代分批从场边走向她（约 10 秒），HUD 边缘箭头标出来向。走到就被吸收：计数 5 = 强化 1 层 + 回 5%（原作学习）。", "子代是主轴目标，自动攻击会先打；玩家只管迎上去让它们进射程。去场边追截、和时间赛跑——和伊莎玛拉「绕着她拆一圈」不是一回事。"]},
    {"name": "二幕 · 学习：两路 + 脚下结茧", "col": (0.9, 1.0, 0.4), "ground": "roots", "draw": [
        L(lambda im, d: put(im, "e_izumik", 0.45, CX, CY + 70, tint=(1.1, 1.1, 0.8))),
        L(lambda im, d: [d.ellipse((x - 16, y - 12, x + 16, y + 12), fill=B.rgb((0.9, 1.0, 0.4), 0.6, 220), outline=(255, 255, 255)) for x, y in ((CX - 60, CY + 85), (CX + 55, CY + 90))]),
        L(lambda im, d: [cyan_ring(d, x, y, 26, 0.45) for x, y in ((CX - 60, CY + 85), (CX + 55, CY + 90))]),
        L(lambda im, d: arrow(d, 16, CY + 130, 0.0, GOLD, 18)),
        L(lambda im, d: arrow(d, PW - 16, CY + 60, math.pi, GOLD, 18)),
        L(lambda im, d: d.text((20, 96), "到了先结茧 4 秒：最后的机会", font=B.font(15), fill=(255, 255, 255))),
    ], "lines": ["一次两个方向。走到她身边的子代先在她脚下结茧 4 秒（同类游戏深岩银河：幸存者的茧），要贴近她打碎。"]},
    {"name": "三幕 · 分享：灯柱一根根熄灭", "col": (0.85, 1.0, 0.85), "ground": "fog", "draw": [
        L(lambda im, d: put(im, "e_izumik", 0.45, CX, CY + 70)),
        L(lambda im, d: B.circle(d, 110, CY + 170, 52, (1.0, 0.9, 0.5), "ring")),
        L(lambda im, d: B.circle(d, PW - 110, CY + 170, 52, (0.4, 0.4, 0.4), "ring")),
        L(lambda im, d: d.text((PW - 140, CY + 140), "已熄灭", font=B.font(13), fill=(180, 180, 180))),
        L(lambda im, d: d.text((130, 96), "全场分享：预告 2–4.5 秒 + 蓄力 1.6 秒", font=B.font(15), fill=(255, 255, 255))),
    ], "P": [(110, CY + 170), (85, CY + 160), (135, CY + 160)],
     "lines": ["不再来子代。每 12 秒全场分享，站在灯柱光圈里不受伤（用户 10-24 定，留缓冲）；每次分享后你躲过的那根灯柱熄灭——灯越来越少，要在最后一根熄灭前打完。"]},
])

BT, AG, IB = (0.25, 0.85, 0.9), (0.5, 0.95, 0.6), (0.65, 0.75, 1.0)
PAIR = ("接潮组 · 同步（方案 B）", [
    {"name": "主轴：血量拉平，一起打进假死", "col": BT, "draw": [
        L(lambda im, d: put(im, "e_bishop", 0.75, 130, CY + 70)),
        L(lambda im, d: put(im, "e_archon", 0.7, PW - 130, CY + 70)),
        L(lambda im, d: bar(d, 60, 100, 150, 0.35, BT, "主教 35%")),
        L(lambda im, d: bar(d, PW - 210, 100, 150, 0.7, AG, "蔑死体 70%")),
        L(lambda im, d: d.ellipse((130 - 40, CY + 30, 130 + 40, CY + 70), outline=B.rgb(BT, 1.3), width=4)),
        L(lambda im, d: d.text((70, CY + 80), "差 > 25%：受伤 ×0.4", font=B.font(14), fill=(255, 255, 255))),
        L(lambda im, d: arrow(d, PW - 190, CY + 150, 0.0, (1, 1, 1))),
    ], "P": [(PW - 170, CY + 150), (PW - 220, CY + 170), (PW - 120, CY + 175)],
     "lines": ["两具血量差超过 25%，血少那具出护盾（受伤 ×0.4）。自动攻击先打射程内最近的 Boss，所以站到血多那具身边、让另一具在射程外（两具保持 ≥360 的距离）。", "一具打进假死后 8 秒内把另一具也打进去才算死（原作）。护盾规则取材同类游戏深岩银河：幸存者的双子，原作没有。"]},
    {"name": "二幕 · 统一：换位", "col": BT, "ground": "tide", "draw": [
        L(lambda im, d: put(im, "e_bishop", 0.75, 130, CY + 70, tint=(0.95, 1.1, 1.15))),
        L(lambda im, d: put(im, "e_archon", 0.7, PW - 130, CY + 70, tint=(1.0, 1.15, 0.95))),
        L(lambda im, d: B.beam(d, 160, CY + 40, PW - 160, CY + 40, 8, BT)),
        L(lambda im, d: arrow(d, PW - 175, CY + 40, 0.0, (1, 1, 1))),
        L(lambda im, d: arrow(d, 175, CY + 40, math.pi, (1, 1, 1))),
        L(lambda im, d: bar(d, 60, 100, 150, 0.5, BT, "主教 50%")),
        L(lambda im, d: bar(d, PW - 210, 100, 150, 0.6, AG, "蔑死体 60%")),
        L(lambda im, d: d.text((CX - 70, CY + 10), "1 秒后互换位置", font=B.font(15), fill=(255, 255, 255))),
    ], "P": [(PW - 170, CY + 150), (PW - 220, CY + 170), (PW - 120, CY + 175)],
     "lines": ["每 10 秒两具之间亮起连线，1 秒后瞬间互换位置——你身边那具换成另一具，要重新判断站哪边；血量差门槛收到 15%，假死窗口 8 → 6 秒。"]},
])


if __name__ == "__main__":
    for k, (t, acts) in {"knight_boss": KNIGHT, "path": PATH, "iberia": IBERIA, "carmen": CARMEN, "paranoia": PARANOIA,
                          "ishar": ISHAR, "izumik": IZUMIK, "tide_pair": PAIR}.items():
        sheet(k, t, acts)
