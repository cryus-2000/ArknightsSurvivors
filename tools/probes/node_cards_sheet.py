"""docs/154 翻节点卡示意图（手机竖屏）：程序画的示意，不是游戏截图。

用法：D:/Anaconda/python.exe tools/probes/node_cards_sheet.py [输出路径]
缺省输出 docs/reference/154_node_cards.png。只用 PIL，节点图标在 16×16 格上画再最近邻放大。
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFont

W, H = 1080, 3000
BG = (11, 22, 32)
INK = (232, 226, 214)
DIM = (143, 163, 173)
GOLD = (242, 196, 109)
PANEL = (18, 40, 56)
LINE = (59, 100, 117)
# 结局色（waves.json endings.col）
END_COL = {
    "一": (204, 140, 255),
    "二": (153, 217, 255),
    "三": (89, 153, 255),
    "四": (255, 204, 102),
}
FONT = "C:/Windows/Fonts/msyh.ttc"
FONT_B = "C:/Windows/Fonts/msyhbd.ttc"


def font(size, bold=False):
    return ImageFont.truetype(FONT_B if bold else FONT, size)


def icon(kind, col, scale=6):
    """16×16 像素图标，最近邻放大。"""
    im = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    c = col + (255,)
    if kind == "incident":   # 不期而遇：菱形里一个问号
        d.polygon([(8, 0), (15, 8), (8, 15), (1, 8)], outline=c)
        d.line([(6, 5), (7, 4), (9, 4), (10, 5), (10, 7), (8, 8), (8, 10)], fill=c)
        d.point((8, 12), fill=c)
    elif kind == "wish":     # 得偿所愿：四角星
        d.polygon([(8, 1), (10, 6), (15, 8), (10, 10), (8, 15), (6, 10), (1, 8), (6, 6)], fill=c)
    elif kind == "shop":     # 诡意行商：提灯
        d.line([(6, 1), (10, 1)], fill=c)
        d.line([(8, 1), (8, 3)], fill=c)
        d.rectangle([4, 4, 12, 13], outline=c)
        d.rectangle([6, 6, 10, 11], fill=c)
        d.line([(5, 14), (11, 14)], fill=c)
    elif kind == "rest":     # 安全的角落：篝火
        d.polygon([(8, 2), (11, 8), (10, 11), (6, 11), (5, 8)], fill=c)
        d.line([(3, 14), (13, 12)], fill=c)
        d.line([(3, 12), (13, 14)], fill=c)
    elif kind == "elite":    # 紧急作战：交叉的刃 + 感叹号
        d.line([(2, 2), (13, 13)], fill=c)
        d.line([(13, 2), (2, 13)], fill=c)
        d.line([(1, 4), (4, 1)], fill=c)
        d.line([(11, 1), (14, 4)], fill=c)
    elif kind == "fog":      # 迷雾重重：三道波
        for y in (4, 8, 12):
            d.line([(1, y), (4, y - 2), (7, y), (10, y - 2), (14, y)], fill=c)
    return im.resize((16 * scale, 16 * scale), Image.NEAREST)


NAMES = {"incident": "不期而遇", "wish": "得偿所愿", "shop": "诡意行商", "rest": "安全的角落", "elite": "紧急作战", "fog": "迷雾重重"}
ICOL = {"incident": (120, 190, 255), "wish": GOLD, "shop": (242, 160, 90), "rest": (90, 210, 160), "elite": (230, 90, 130), "fog": (170, 180, 200)}


def text(d, xy, s, size=30, col=INK, bold=False, anchor="la"):
    d.text(xy, s, font=font(size, bold), fill=col, anchor=anchor)


def card_back(img, d, x, y, w, h, kind, edges=(), lifted=False):
    if lifted:
        y -= 26
    d.rounded_rectangle([x, y, x + w, y + h], radius=14, fill=(16, 34, 48), outline=LINE, width=3)
    # 结局色边：一色描整圈，两色左右各半
    if len(edges) == 1:
        d.rounded_rectangle([x - 6, y - 6, x + w + 6, y + h + 6], radius=18, outline=edges[0], width=7)
    elif len(edges) == 2:
        left = Image.new("RGBA", img.size, (0, 0, 0, 0))
        ld = ImageDraw.Draw(left)
        ld.rounded_rectangle([x - 6, y - 6, x + w + 6, y + h + 6], radius=18, outline=edges[0] + (255,), width=7)
        right = Image.new("RGBA", img.size, (0, 0, 0, 0))
        rd = ImageDraw.Draw(right)
        rd.rounded_rectangle([x - 6, y - 6, x + w + 6, y + h + 6], radius=18, outline=edges[1] + (255,), width=7)
        mask_l = Image.new("L", img.size, 0)
        ImageDraw.Draw(mask_l).rectangle([0, 0, x + w // 2, H], fill=255)
        img.paste(left, (0, 0), Image.composite(left.split()[3], Image.new("L", img.size, 0), mask_l))
        mask_r = Image.new("L", img.size, 0)
        ImageDraw.Draw(mask_r).rectangle([x + w // 2, 0, W, H], fill=255)
        img.paste(right, (0, 0), Image.composite(right.split()[3], Image.new("L", img.size, 0), mask_r))
    # 卡背纹样：细格 + 中央图标 + 名字
    for gy in range(y + 24, y + h - 20, 22):
        d.line([(x + 18, gy), (x + w - 18, gy)], fill=(22, 46, 62), width=1)
    ic = icon(kind, ICOL[kind], 8)
    img.paste(ic, (x + (w - ic.width) // 2, y + 70), ic)
    text(d, (x + w // 2, y + h - 64), NAMES[kind], 34, INK, True, "ma")
    return y


def main(out):
    img = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(img)
    text(d, (40, 40), "翻节点卡 · 多结局选路", 52, INK, True)
    text(d, (40, 112), "docs/154 · 程序画的示意，不是游戏截图", 26, DIM)

    # ---------- 时间线 ----------
    y0 = 180
    text(d, (40, y0), "一局 10 分钟里的两个路口", 34, GOLD, True)
    rows = [
        ("0:00", "开局", DIM, False),
        ("2:00", "第一位商人", (242, 196, 109), False),
        ("3:30", "中 Boss → 打完翻卡：路口一", (208, 90, 138), True),
        ("5:00", "第二位商人", (242, 196, 109), False),
        ("7:00", "中 Boss → 打完翻卡：路口二", (208, 90, 138), True),
        ("8:00", "第三位商人", (242, 196, 109), False),
        ("9:00", "终局预告，走向冻结", (143, 211, 255), False),
        ("10:00", "最终 Boss（按结局）", (255, 90, 122), False),
    ]
    ty = y0 + 64
    d.line([(150, ty + 10), (150, ty + 10 + 56 * (len(rows) - 1))], fill=LINE, width=4)
    for t, s, col, hot in rows:
        d.ellipse([140, ty, 160, ty + 20], fill=col if not hot else BG, outline=col, width=4)
        text(d, (40, ty - 6), t, 28, col)
        text(d, (190, ty - 8), s, 32 if hot else 28, INK if hot else DIM, hot)
        if hot:
            ic = icon("incident", GOLD, 3)
            img.paste(ic, (190 + int(d.textlength(s, font=font(32, True))) + 16, ty - 8), ic)
        ty += 56
    text(d, (40, ty + 8), "中 Boss 拖太久也会弹：路口一最晚 6:30，路口二最晚 8:40", 24, DIM)

    # ---------- 路口一摊牌 ----------
    py = ty + 70
    d.rounded_rectangle([24, py, W - 24, py + 640], radius=18, fill=PANEL, outline=LINE, width=3)
    text(d, (W // 2, py + 26), "深入海洋 · 路口一", 40, INK, True, "ma")
    text(d, (W // 2, py + 82), "选一张翻开（灯火暗淡时只有 2 张）", 26, DIM, False, "ma")
    cw, ch = 290, 400
    gap = (W - 48 - 3 * cw) // 4
    cx = [24 + gap + i * (cw + gap) for i in range(3)]
    cy = py + 150
    top0 = card_back(img, d, cx[0], cy, cw, ch, "incident", (END_COL["三"], END_COL["四"]), lifted=True)
    card_back(img, d, cx[1], cy, cw, ch, "incident", (END_COL["二"],))
    card_back(img, d, cx[2], cy, cw, ch, "wish")
    text(d, (cx[0] + cw // 2, py + 588), "色边：结局三 + 四", 24, GOLD, False, "ma")
    text(d, (cx[1] + cw // 2, py + 588), "色边：结局二", 24, END_COL["二"], False, "ma")
    text(d, (cx[2] + cw // 2, py + 588), "随机填充", 24, DIM, False, "ma")
    d.polygon([(cx[0] + cw // 2 - 14, top0 - 40), (cx[0] + cw // 2 + 14, top0 - 40), (cx[0] + cw // 2, top0 - 18)], fill=GOLD)

    # ---------- 翻开 ----------
    fy = py + 680
    text(d, (40, fy), "翻开 ↓ 结局入口每局必有，但翻开前不知道是哪件事", 30, GOLD, True)
    ey = fy + 56
    d.rounded_rectangle([24, ey, W - 24, ey + 540], radius=18, fill=(20, 24, 30), outline=(120, 190, 255), width=3)
    ic = icon("incident", (120, 190, 255), 5)
    img.paste(ic, (48, ey + 24), ic)
    text(d, (140, ey + 24), "不期而遇 · 开端", 40, INK, True)
    text(d, (140, ey + 80), "坏消息接踵而至。水月找到的文件里，记着一个地点。", 24, DIM)
    opts = [
        ("决定潜入深海", "得到「主教的研究」→ 深蓝之心线（结局三）", END_COL["三"]),
        ("“深蓝”？！", "得到「深蓝回忆」，灯火降到 10 → 升华线（结局四）", END_COL["四"]),
        ("噩梦……", "源石锭 +15", DIM),
        ("离开", "什么都不做", DIM),
    ]
    oy = ey + 136
    for name, desc, col in opts:
        d.rounded_rectangle([48, oy, W - 48, oy + 88], radius=10, fill=(28, 36, 46), outline=col, width=2)
        text(d, (72, oy + 8), name, 30, INK, True)
        text(d, (72, oy + 50), desc, 22, col if col != DIM else DIM)
        oy += 98

    # ---------- 六种卡 ----------
    ly = ey + 580
    text(d, (40, ly), "六种节点卡（原作节点语义）", 34, GOLD, True)
    legend = [
        ("incident", "弹事件：结局线或普通事件"),
        ("wish", "亮出 3 件藏品选 1"),
        ("shop", "下一位商人多一格，首件 7 折"),
        ("rest", "回血 / 灯火 +15 / 招募 三选一"),
        ("elite", "刷 2 只精英，全灭多一个宝箱"),
        ("fog", "翻开才知道变成哪一种"),
    ]
    gy = ly + 60
    for i, (k, desc) in enumerate(legend):
        col_x = 40 + (i % 2) * 510
        row_y = gy + (i // 2) * 120
        ic = icon(k, ICOL[k], 5)
        img.paste(ic, (col_x, row_y), ic)
        text(d, (col_x + 100, row_y + 4), NAMES[k], 30, INK, True)
        text(d, (col_x + 100, row_y + 46), desc, 22, DIM)

    # ---------- 规则 ----------
    ry = gy + 3 * 120 + 10
    d.rounded_rectangle([24, ry, W - 24, ry + 300], radius=18, fill=PANEL, outline=LINE, width=3)
    lines = [
        ("路口一", "已解锁结局线：狂徒妄念、开端各一张必出（三条线只能走一条）"),
        ("路口二", "持某条线的信物：骑士仍在 / 深蓝之心 / 深蓝仪式·升华 必出一张"),
        ("升华", "灯火 ≥ 90 才能选「决心」，≥ 50 才能选「观望」"),
        ("结局", "抉择信物 → 四；深蓝之心 → 三；骑士在 → 二；都没有 → 一"),
    ]
    yy = ry + 26
    for k, v in lines:
        text(d, (52, yy), k, 28, GOLD, True)
        text(d, (190, yy + 2), v, 24, INK)
        yy += 66
    img = img.crop((0, 0, W, ry + 330))
    os.makedirs(os.path.dirname(out), exist_ok=True)
    img.save(out, optimize=True)
    print(out, img.size)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else os.path.join("docs", "reference", "154_node_cards.png"))
