# -*- coding: utf-8 -*-
"""藏品图标模板生成器（docs/11 规格：32×32、透明底、1 px 外轮廓 #080E18、二值 alpha、主体 ≤ 28×28 居中、左上来光）。

思路：按藏品名字里的关键词（没有命中再按流派）从一张「物件词汇表」里选一个母题（瓶 / 刀 / 盾 / 灯 / 书 / 币 / 宝石 /
羽毛 / 锚 / 贝 / 烧瓶 / 钥匙 / 戒指 / 弩 / 号角 / 徽章 / 果实 / 花 / 丝带 / 镜筒），用矩形 / 椭圆 / 多边形拼出轮廓遮罩，
再统一上色：按流派取一组 2 色主体（亮面 / 暗面，沿左上—右下的对角分界）+ 1 px 深色描边 + 1–3 粒冰蓝高光 + 母题自己的 1 个点缀色。
现有手绘图标（art/incoming/relic_*.png）不画底板，底板 / 稀有度边框由程序按稀有度画（docs/11 §2）——缺省照此不画底板；
--plate 时加一块流派色的圆角底板（试看用）。

用法：python tools/gen_relic_icons.py --trial [N]       给还没有图标的藏品生成 N（缺省 20）张到 art/incoming/_trial_icons/（按流派分散取）
      python tools/gen_relic_icons.py --ids 6,7,8       指定 id 生成到 _trial_icons/
      --contact 目录                                    另写联系表（10 张手绘 vs 生成的，1x / 3x）
      --plate                                           带流派色底板
确定性：同名同流派总是同一张；不用随机数。
"""
import os, sys, json, math, re
from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
INC = os.path.join(ROOT, "art", "incoming")
TRIAL = os.path.join(INC, "_trial_icons")
DATA = os.path.join(ROOT, "game", "data", "relics.json")

OUTLINE = (0x08, 0x0E, 0x18, 255)
HILITE = (0xE6, 0xFA, 0xFF, 255)
HILITE2 = (0x9F, 0xE3, 0xF0, 255)
CLEAR = (0, 0, 0, 0)

# 流派 → (亮面, 暗面, 底板色)；参照 docs/11 深海基础色与 UI.CAT_COL 的气质
LANE_TONES = {
    "A": ((0xE0, 0x50, 0x6A), (0xB3, 0x26, 0x3E), (0x3A, 0x18, 0x24)),   # 前锋·近战：血红
    "B": ((0x3F, 0x7A, 0x94), (0x2E, 0x4C, 0x6E), (0x16, 0x23, 0x3A)),   # 追击·召唤：冷蓝
    "C": ((0xC9, 0xA6, 0xFF), (0x8A, 0x5C, 0xD6), (0x2A, 0x1C, 0x48)),   # 控制·技能：海嗣紫
    "D": ((0xC7, 0xCF, 0xD9), (0x7F, 0x8A, 0x99), (0x24, 0x2A, 0x36)),   # 收割·弱点：钢
    "E": ((0x53, 0xEB, 0xE0), (0x1F, 0x8E, 0x8A), (0x12, 0x30, 0x34)),   # 远程·火力：青
    "F": ((0x7C, 0x6B, 0xFF), (0x3C, 0x30, 0x90), (0x18, 0x14, 0x3A)),   # 深蓝·低灯火：靛紫
    "G": ((0xFF, 0xC4, 0x6B), (0xB8, 0x80, 0x1E), (0x3A, 0x2A, 0x12)),   # 编队·协同：金
    "H": ((0x7F, 0xD9, 0x9A), (0x2F, 0x8A, 0x60), (0x14, 0x30, 0x24)),   # 守护·续航：绿
    "": ((0xC7, 0xCF, 0xD9), (0x7F, 0x8A, 0x99), (0x24, 0x2A, 0x36)),    # 无流派：灰蓝旧物
}
# 点缀色（母题自带）
ACC = {"gold": (0xFF, 0xC4, 0x6B), "orange": (0xFF, 0x8A, 0x3D), "red": (0xE0, 0x50, 0x6A), "ice": (0x9F, 0xE3, 0xF0),
       "violet": (0xC9, 0xA6, 0xFF), "steel": (0xC7, 0xCF, 0xD9), "green": (0x7F, 0xD9, 0x9A), "ink": (0x16, 0x23, 0x3A)}

# 关键词 → 母题（先命中的优先；名字里有书名号一律 book）
KEYWORDS = [
    (("《",), "book"), (("手稿", "法", "契约", "文件", "报告", "信", "创想", "量尺"), "scroll"),
    (("支票", "币", "银行", "钱", "报酬", "赤金"), "coin"),
    (("香精", "药", "之水", "剂", "瓶"), "flask"), (("酒", "佳酿", "汽水", "咖啡", "茶", "饮", "壶"), "bottle"),
    (("糖", "豆", "樱桃", "水果", "什锦", "果", "饼", "食"), "fruit"), (("花", "鸢尾", "玫瑰", "菊"), "flower"),
    (("刀", "剑", "刃", "斧", "矛"), "blade"), (("盾", "甲", "衣", "护"), "shield"),
    (("灯", "烛", "火", "光"), "lamp"), (("弩", "弓", "箭", "枪"), "bow"),
    (("狙击镜", "镜", "望远"), "scope"), (("钥", "锁"), "key"), (("戒", "指环", "环"), "ring"),
    (("锚", "海程", "船", "航"), "anchor"), (("贝", "珊瑚", "海草", "螺", "海"), "shell"),
    (("羽", "鸟", "鸢", "翼"), "feather"), (("笛", "八音盒", "音", "琴", "鼓"), "horn"),
    (("丝巾", "蝴蝶结", "带", "巾"), "ribbon"), (("徽", "勋", "小队", "队", "章"), "badge"),
    (("石", "宝石", "水晶", "玻璃", "源石", "珠", "金"), "gem"),
]
LANE_DEFAULT = {"A": "blade", "B": "anchor", "C": "scroll", "D": "blade", "E": "bow", "F": "lamp", "G": "badge", "H": "shield", "": "gem"}


def pick_motif(name, lanes):
    for keys, m in KEYWORDS:
        if any(k in name for k in keys):
            return m
    return LANE_DEFAULT.get(lanes[0] if lanes else "", "gem")


# ---------------------------------------------------------------- 形状原语（遮罩 = set((x,y))）
def rect(m, x0, y0, x1, y1):
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            m.add((x, y))


def ell(m, cx, cy, rx, ry):
    for y in range(int(cy - ry) - 1, int(cy + ry) + 2):
        for x in range(int(cx - rx) - 1, int(cx + rx) + 2):
            if ((x + 0.5 - cx) / rx) ** 2 + ((y + 0.5 - cy) / ry) ** 2 <= 1.0:
                m.add((x, y))


def poly(m, pts):
    ys = [p[1] for p in pts]
    for y in range(int(min(ys)), int(max(ys)) + 1):
        xs = []
        n = len(pts)
        for i in range(n):
            (x0, y0), (x1, y1) = pts[i], pts[(i + 1) % n]
            if (y0 <= y + 0.5 < y1) or (y1 <= y + 0.5 < y0):
                xs.append(x0 + (y + 0.5 - y0) * (x1 - x0) / (y1 - y0))
        xs.sort()
        for i in range(0, len(xs) - 1, 2):
            for x in range(int(math.floor(xs[i])), int(math.ceil(xs[i + 1]))):
                m.add((x, y))


def seg(m, x0, y0, x1, y1, w=1):
    n = int(max(abs(x1 - x0), abs(y1 - y0))) + 1
    for i in range(n):
        t = i / max(1, n - 1)
        x, y = round(x0 + (x1 - x0) * t), round(y0 + (y1 - y0) * t)
        for k in range(w):
            m.add((x + (k if abs(y1 - y0) > abs(x1 - x0) else 0), y + (0 if abs(y1 - y0) > abs(x1 - x0) else k)))


# ---------------------------------------------------------------- 母题：返回 (主体遮罩, 点缀像素 dict, 点缀色名, 高光点列表)
def m_bottle():
    m = set(); rect(m, 13, 4, 18, 8); rect(m, 11, 9, 20, 26); ell(m, 16, 26, 5, 2)
    d = {}; rect_d = set(); rect(rect_d, 12, 14, 19, 19)
    for p in rect_d: d[p] = "gold"
    for x in range(13, 19): d[(x, 4)] = "ink"
    return m, d, [(13, 10), (13, 11), (14, 5)]


def m_flask():
    m = set(); rect(m, 14, 4, 17, 11); poly(m, [(14, 11), (18, 11), (24, 24), (23, 27), (9, 27), (8, 24)])
    d = {}; liq = set(); poly(liq, [(11, 20), (21, 20), (23, 25), (10, 25)])
    for p in liq: d[p] = "violet"
    d[(13, 22)] = "ice"; d[(18, 23)] = "ice"
    return m, d, [(15, 5), (15, 6), (12, 17)]


def m_blade():
    m = set(); poly(m, [(22, 3), (26, 7), (13, 20), (9, 16)]); rect(m, 7, 17, 13, 19); seg(m, 10, 19, 5, 24, 2); seg(m, 11, 18, 6, 23, 2)
    rect(m, 8, 16, 12, 20)
    d = {}
    for i in range(0, 12): d[(22 - i + 2, 7 + i - 2)] = "steel"
    rect_d = set(); rect(rect_d, 6, 22, 8, 24)
    for p in rect_d: d[p] = "gold"
    return m, d, [(23, 5), (22, 6), (21, 7)]


def m_shield():
    m = set(); poly(m, [(6, 5), (26, 5), (26, 17), (16, 28), (6, 17)])
    d = {}; seg(d_s := set(), 16, 9, 16, 22, 2); seg(d_s, 11, 13, 21, 13, 2)
    for p in d_s: d[p] = "steel"
    return m, d, [(8, 7), (9, 7), (8, 8)]


def m_lamp():
    m = set(); rect(m, 14, 3, 17, 4); rect(m, 10, 5, 21, 7); rect(m, 9, 8, 22, 22); rect(m, 11, 23, 20, 25); rect(m, 8, 26, 23, 27)
    d = {}; fl = set(); ell(fl, 15.5, 15, 3.5, 5)
    for p in fl: d[p] = "gold"
    d[(15, 14)] = "ice"; d[(16, 14)] = "ice"
    for y in range(8, 23): d[(9, y)] = "ink"; d[(22, y)] = "ink"
    return m, d, [(11, 9), (11, 10)]


def m_book():
    m = set(); rect(m, 6, 5, 25, 26); rect(m, 8, 27, 25, 27)
    d = {}
    for y in range(5, 27): d[(9, y)] = "ink"
    for x in range(12, 22): d[(x, 10)] = "gold"; d[(x, 11)] = "gold"
    for y in range(5, 27): d[(25, y)] = "steel"
    return m, d, [(7, 6), (8, 6), (7, 7)]


def m_scroll():
    m = set(); rect(m, 7, 6, 24, 25); ell(m, 8, 7, 3, 3); ell(m, 23, 7, 3, 3); ell(m, 8, 24, 3, 3); ell(m, 23, 24, 3, 3)
    d = {}
    for y in (11, 14, 17, 20):
        for x in range(10, 22 if y != 20 else 17): d[(x, y)] = "ink"
    d[(20, 20)] = "red"; d[(21, 20)] = "red"; d[(20, 21)] = "red"; d[(21, 21)] = "red"
    return m, d, [(9, 8), (10, 8)]


def m_coin():
    m = set(); ell(m, 16, 16, 11, 11)
    d = {}; inner = set(); ell(inner, 16, 16, 8, 8)
    for p in inner: d[p] = "gold"
    core = set(); poly(core, [(16, 10), (20, 16), (16, 22), (12, 16)])
    for p in core: d[p] = "orange"
    return m, d, [(9, 11), (10, 10), (11, 9)]


def m_gem():
    m = set(); poly(m, [(10, 7), (22, 7), (27, 13), (16, 27), (5, 13)])
    d = {}
    for x in range(6, 27):
        d[(x, 13)] = "ice"
    for i in range(6): d[(13 + i, 7 + i)] = "ice"
    return m, d, [(11, 9), (12, 9), (11, 10)]


def m_feather():
    m = set(); poly(m, [(24, 4), (26, 8), (20, 20), (12, 27), (7, 28), (10, 22), (14, 14)])
    d = {}; seg(sp := set(), 24, 6, 9, 26)
    for p in sp: d[p] = "ink"
    return m, d, [(22, 7), (21, 9)]


def m_anchor():
    m = set(); ell(m, 16, 6, 3, 3); rect(m, 15, 9, 16, 24); rect(m, 9, 13, 22, 14)
    seg(m, 6, 17, 6, 22, 2); seg(m, 25, 17, 25, 22, 2); poly(m, [(6, 22), (16, 28), (26, 22), (26, 25), (16, 30), (6, 25)])
    d = {(16, 6): "ink", (15, 6): "ink"}
    return m, d, [(14, 5), (15, 10)]


def m_shell():
    m = set(); poly(m, [(16, 27), (5, 14), (8, 7), (16, 4), (24, 7), (27, 14)])
    d = {}
    for i in range(4):
        x0 = 8 + i * 5
        seg(s := set(), x0, 8 + (i % 2) * 2, 16, 26)
        for p in s: d[p] = "ink"
    return m, d, [(9, 9), (10, 8), (11, 8)]


def m_key():
    m = set(); ell(m, 10, 10, 6, 6); rect(m, 13, 12, 26, 14); rect(m, 22, 15, 23, 18); rect(m, 25, 15, 26, 17)
    d = {}; hole = set(); ell(hole, 10, 10, 2.5, 2.5)
    for p in hole: d[p] = "ink"
    return m, d, [(6, 7), (7, 6)]


def m_ring():
    m = set(); ell(m, 16, 18, 9, 9); poly(m, [(16, 3), (21, 8), (16, 12), (11, 8)])
    d = {}; hole = set(); ell(hole, 16, 18, 5.5, 5.5)
    for p in hole: d[p] = "hole"
    stone = set(); poly(stone, [(16, 5), (19, 8), (16, 11), (13, 8)])
    for p in stone: d[p] = "red"
    d[(15, 6)] = "ice"
    return m, d, [(9, 14), (10, 13)]


def m_bow():
    m = set(); poly(m, [(8, 4), (12, 4), (26, 16), (12, 28), (8, 28), (20, 16)])
    seg(m, 9, 5, 9, 27, 2)
    d = {}; seg(s := set(), 9, 5, 9, 27)
    for p in s: d[p] = "steel"
    seg(a := set(), 5, 16, 24, 16)
    for p in a: d[p] = "ink"
    d[(25, 16)] = "ice"; d[(24, 15)] = "ice"; d[(24, 17)] = "ice"
    return m, d, [(10, 6), (11, 7)]


def m_scope():
    m = set(); rect(m, 4, 12, 27, 19); ell(m, 6, 15.5, 4, 5); ell(m, 25, 15.5, 4, 5); rect(m, 13, 9, 18, 11)
    d = {}; lens = set(); ell(lens, 25, 15.5, 2.5, 3.5)
    for p in lens: d[p] = "ice"
    d[(24, 14)] = "hilite"
    return m, d, [(6, 12), (7, 12)]


def m_horn():
    m = set(); poly(m, [(6, 10), (12, 8), (24, 20), (26, 26), (20, 27), (8, 15)]); ell(m, 25, 24, 4, 4); ell(m, 6, 11, 3, 3)
    d = {}; bell = set(); ell(bell, 25, 24, 2, 2)
    for p in bell: d[p] = "ink"
    seg(s := set(), 10, 11, 21, 22)
    for p in s: d[p] = "gold"
    return m, d, [(8, 9), (9, 9)]


def m_badge():
    m = set(); ell(m, 16, 13, 9, 9); poly(m, [(11, 20), (21, 20), (22, 29), (16, 25), (10, 29)])
    d = {}; inner = set(); ell(inner, 16, 13, 6, 6)
    for p in inner: d[p] = "gold"
    star = set(); poly(star, [(16, 9), (18, 12), (21, 12), (18, 14), (19, 18), (16, 16), (13, 18), (14, 14), (11, 12), (14, 12)])
    for p in star: d[p] = "orange"
    return m, d, [(9, 9), (10, 8)]


def m_flower():
    m = set()
    for a in range(5):
        t = a * math.tau / 5 - math.pi / 2
        ell(m, 16 + math.cos(t) * 6, 12 + math.sin(t) * 6, 4.2, 4.2)
    rect(m, 15, 18, 16, 28); poly(m, [(16, 22), (22, 20), (20, 25)])
    d = {}; c = set(); ell(c, 16, 12, 2.5, 2.5)
    for p in c: d[p] = "gold"
    for y in range(18, 29): d[(15, y)] = "green"; d[(16, y)] = "green"
    for p in [(18, 22), (19, 22), (20, 22), (19, 23)]: d[p] = "green"
    return m, d, [(11, 7), (12, 7)]


def m_ribbon():
    m = set(); poly(m, [(16, 14), (5, 6), (4, 22), (16, 18)]); poly(m, [(16, 14), (27, 6), (28, 22), (16, 18)])
    ell(m, 16, 16, 3, 3); poly(m, [(13, 18), (19, 18), (23, 28), (9, 28)])
    d = {}; k = set(); ell(k, 16, 16, 1.5, 1.5)
    for p in k: d[p] = "ink"
    return m, d, [(7, 8), (8, 8)]


def m_fruit():
    m = set(); ell(m, 15, 18, 9, 9); ell(m, 15, 10, 4, 3); rect(m, 18, 4, 19, 11)
    d = {}; leaf = set(); ell(leaf, 22, 8, 3.5, 2)
    for p in leaf: d[p] = "green"
    for y in range(4, 11): d[(18, y)] = "ink"; d[(19, y)] = "ink"
    return m, d, [(10, 13), (11, 12), (10, 14)]


MOTIFS = {"bottle": m_bottle, "flask": m_flask, "blade": m_blade, "shield": m_shield, "lamp": m_lamp, "book": m_book,
          "scroll": m_scroll, "coin": m_coin, "gem": m_gem, "feather": m_feather, "anchor": m_anchor, "shell": m_shell,
          "key": m_key, "ring": m_ring, "bow": m_bow, "scope": m_scope, "horn": m_horn, "badge": m_badge,
          "flower": m_flower, "ribbon": m_ribbon, "fruit": m_fruit}


# ---------------------------------------------------------------- 上色
def _fit(mask):
    """主体收进 2..29（28×28 居中）：超出就整体平移，仍超就裁掉"""
    xs = [p[0] for p in mask]; ys = [p[1] for p in mask]
    dx = dy = 0
    if min(xs) < 2: dx = 2 - min(xs)
    if max(xs) > 29: dx = min(dx, 29 - max(xs))
    if min(ys) < 2: dy = 2 - min(ys)
    if max(ys) > 29: dy = min(dy, 29 - max(ys))
    return dx, dy


def render(motif, lane, plate=False):
    mask, deco, hl = MOTIFS[motif]()
    dx, dy = _fit(mask)
    mask = {(x + dx, y + dy) for (x, y) in mask if 2 <= x + dx <= 29 and 2 <= y + dy <= 29}
    deco = {(x + dx, y + dy): c for (x, y), c in deco.items()}
    hl = [(x + dx, y + dy) for (x, y) in hl]
    light, dark, plate_c = LANE_TONES.get(lane, LANE_TONES[""])
    im = Image.new("RGBA", (32, 32), CLEAR)
    if plate:
        pl = set(); rect(pl, 2, 2, 29, 29)
        for p in [(2, 2), (29, 2), (2, 29), (29, 29)]: pl.discard(p)
        for p in pl: im.putpixel(p, plate_c + (255,))
        for x in range(3, 29): im.putpixel((x, 2), OUTLINE); im.putpixel((x, 29), OUTLINE)
        for y in range(3, 29): im.putpixel((2, y), OUTLINE); im.putpixel((29, y), OUTLINE)
    # 主体：左上亮、右下暗，分界过形心、沿 x+y
    cx = sum(p[0] for p in mask) / len(mask); cy = sum(p[1] for p in mask) / len(mask)
    for (x, y) in mask:
        c = light if (x - cx) + (y - cy) < 1.0 else dark
        im.putpixel((x, y), c + (255,))
    # 暗面再压一层：贴近右下轮廓的一圈更暗（像手绘的内描边）
    darker = tuple(int(v * 0.72) for v in dark)
    for (x, y) in mask:
        if (x - cx) + (y - cy) >= 1.0 and ((x + 1, y) not in mask or (x, y + 1) not in mask):
            im.putpixel((x, y), darker + (255,))
    # 点缀
    for (x, y), c in deco.items():
        if (x, y) not in mask:
            continue
        if c == "hole":
            im.putpixel((x, y), CLEAR if not plate else plate_c + (255,))
        elif c == "hilite":
            im.putpixel((x, y), HILITE)
        else:
            im.putpixel((x, y), ACC[c] + (255,))
    body = {(x, y) for y in range(32) for x in range(32) if im.getpixel((x, y))[3] == 255 and (not plate or (x, y) in mask or deco.get((x, y)) == "hole")}
    if plate:
        body = {p for p in mask if deco.get(p) != "hole"}
    # 1 px 外轮廓（4 邻接）
    for (x, y) in list(body):
        for (ox, oy) in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            q = (x + ox, y + oy)
            if 0 <= q[0] < 32 and 0 <= q[1] < 32 and q not in body:
                im.putpixel(q, OUTLINE)
    # 高光
    for i, p in enumerate(hl):
        if p in mask and deco.get(p) is None:
            im.putpixel(p, HILITE if i == 0 else HILITE2)
    return im


# ---------------------------------------------------------------- 选藏品 / 联系表
def load_relics():
    return json.load(open(DATA, encoding="utf-8"))["items"]


def existing_ids():
    """已有的手绘图标：relic_<数字>.png 且是 32×32（incoming 里还有 relic_ 开头的联系表，不算）"""
    out = set()
    for f in os.listdir(INC):
        m = re.match(r"relic_(\d+)\.png$", f)
        if m and Image.open(os.path.join(INC, f)).size == (32, 32):
            out.add(m.group(1))
    return out


def pick_trial(items, n):
    """没有图标的藏品里按流派轮流取（各流派 + 无流派），母题尽量不重复"""
    have = existing_ids()
    by_lane = {}
    for it in items:
        if str(it["id"]) in have:
            continue
        by_lane.setdefault(it["lanes"][0] if it["lanes"] else "", []).append(it)
    order = ["A", "B", "C", "D", "E", "F", "G", "H", ""]
    out, used = [], set()
    while len(out) < n and any(by_lane.values()):
        for ln in order:
            lst = by_lane.get(ln, [])
            pick = None
            for it in lst:
                mt = pick_motif(it["name"], it["lanes"])
                if mt not in used:
                    pick = it; break
            if pick is None and lst:
                pick = lst[0]
            if pick is not None:
                lst.remove(pick); out.append(pick); used.add(pick_motif(pick["name"], pick["lanes"]))
            if len(out) >= n:
                break
        if all(not v for v in by_lane.values()):
            break
    return out


def contact(gen, out_dir):
    os.makedirs(out_dir, exist_ok=True)
    hand = sorted(existing_ids(), key=lambda s: int(s) if s.isdigit() else 0)[:10]
    hand_ims = [Image.open(os.path.join(INC, "relic_%s.png" % i)).convert("RGBA") for i in hand]
    bg = (28, 30, 44, 255)
    rows = [hand_ims, gen[:10], gen[10:20]]
    cell1, cell3 = 36, 100
    W = 10 * cell3 + 16
    H = (cell1 + cell3 + 12) * 3 + 16
    sheet = Image.new("RGBA", (W, H), bg)
    y = 8
    for r in rows:
        for i, im in enumerate(r):
            sheet.paste(im, (8 + i * cell3, y), im)
            big = im.resize((96, 96), Image.NEAREST)
            sheet.paste(big, (8 + i * cell3, y + cell1), big)
        y += cell1 + cell3 + 12
    p = os.path.join(out_dir, "contact.png")
    sheet.save(p)
    return p


def main():
    args = sys.argv[1:]
    plate = "--plate" in args
    items = load_relics()
    chosen = []
    if "--ids" in args:
        ids = {int(v) for v in args[args.index("--ids") + 1].split(",")}
        chosen = [it for it in items if it["id"] in ids]
    else:
        n = 20
        if "--trial" in args:
            i = args.index("--trial")
            if i + 1 < len(args) and args[i + 1].isdigit():
                n = int(args[i + 1])
        chosen = pick_trial(items, n)
    os.makedirs(TRIAL, exist_ok=True)
    gen = []
    for it in chosen:
        mt = pick_motif(it["name"], it["lanes"])
        ln = it["lanes"][0] if it["lanes"] else ""
        im = render(mt, ln, plate)
        assert set(im.getchannel("A").getdata()) <= {0, 255}
        im.save(os.path.join(TRIAL, "relic_%d.png" % it["id"]))
        gen.append(im)
        print("relic_%d  %-14s lane=%s motif=%s" % (it["id"], it["name"], ln or "-", mt))
    if "--contact" in args:
        d = args[args.index("--contact") + 1]
        print("contact:", contact(gen, d))


if __name__ == "__main__":
    main()
