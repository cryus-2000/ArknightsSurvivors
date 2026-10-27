"""docs/172 事件改版示意图（手机竖屏）：程序画的线框，不是游戏截图。

用法：D:/Anaconda/python.exe tools/probes/event_redesign_sheet.py [输出路径]
缺省输出 docs/reference/172_event_redesign.png。卡背、图标、配色沿用 node_cards_sheet.py。
"""
import os
import sys

from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from node_cards_sheet import (  # noqa: E402
    BG, DIM, END_COL, GOLD, INK, LINE, PANEL, H, W, card_back, font, icon, text,
)

RED = (230, 90, 110)
TEAL = (90, 210, 190)


def cost_tag(d, x, y):
    """卡背右上角的「代价」角标。"""
    d.polygon([(x - 92, y), (x, y), (x, y + 92)], fill=RED)
    text(d, (x - 30, y + 14), "代价", 20, BG, True, "ma")


def main(out):
    img = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(img)
    text(d, (40, 40), "事件改版 · 有代价的取舍", 52, INK, True)
    text(d, (40, 112), "docs/172 · 程序画的线框，不是游戏截图", 26, DIM)

    # ---------- 时间线 ----------
    y0 = 180
    text(d, (40, y0), "一次探索里的四次翻卡（首通前也有，只是没有结局入口）", 30, GOLD, True)
    rows = [
        ("1:20", "途中一 · 2 张", TEAL, True),
        ("2:00", "第一位商人", GOLD, False),
        ("3:30", "中 Boss → 路口一 · 3 张（结局入口）", (208, 90, 138), True),
        ("5:00", "第二位商人", GOLD, False),
        ("6:00", "途中二 · 2 张", TEAL, True),
        ("7:00", "中 Boss → 路口二 · 3 张（按信物）", (208, 90, 138), True),
        ("8:00", "第三位商人，之后不再停", GOLD, False),
        ("10:00", "最终 Boss", (255, 90, 122), False),
    ]
    ty = y0 + 64
    d.line([(150, ty + 10), (150, ty + 10 + 56 * (len(rows) - 1))], fill=LINE, width=4)
    for t, s, col, hot in rows:
        d.ellipse([140, ty, 160, ty + 20], fill=col if not hot else BG, outline=col, width=4)
        text(d, (40, ty - 6), t, 28, col)
        text(d, (190, ty - 8), s, 30 if hot else 28, INK if hot else DIM, hot)
        ty += 56
    text(d, (40, ty + 8), "每次停顿 ≤ 5 秒（不含阅读）；途中路口等精英清场再弹", 24, DIM)

    # ---------- 途中路口：2 张 ----------
    py = ty + 70
    d.rounded_rectangle([24, py, W - 24, py + 630], radius=18, fill=PANEL, outline=LINE, width=3)
    text(d, (W // 2, py + 26), "深入海洋 · 途中", 40, INK, True, "ma")
    text(d, (W // 2, py + 82), "桌上至少一张交易卡，最多一张无代价卡", 26, DIM, False, "ma")
    cw, ch = 330, 400
    gap = (W - 48 - 2 * cw) // 3
    cx = [24 + gap + i * (cw + gap) for i in range(2)]
    cy = py + 172
    top0 = card_back(img, d, cx[0], cy, cw, ch, "incident", lifted=True)
    cost_tag(d, cx[0] + cw, top0)
    card_back(img, d, cx[1], cy, cw, ch, "rest")
    text(d, (cx[0] + cw // 2, py + 586), "交易：翻开前就知道要付东西", 22, RED, False, "ma")
    text(d, (cx[1] + cw // 2, py + 586), "稳妥卡", 22, DIM, False, "ma")

    # ---------- 翻开：事件面板 ----------
    fy = py + 670
    text(d, (40, fy), "翻开 ↓ 每件事件都留一个稳妥选项", 30, GOLD, True)
    ey = fy + 56
    eh = 860
    d.rounded_rectangle([24, ey, W - 24, ey + eh], radius=18, fill=(20, 24, 30), outline=(120, 190, 255), width=3)
    # 顶部小图（手机版：CG 缩略 + 压暗铺底，见 docs/156 §4）
    d.rectangle([48, ey + 24, 248, ey + 204], fill=(30, 40, 52), outline=LINE, width=2)
    text(d, (148, ey + 100), "CG 47", 24, DIM, False, "ma")
    text(d, (272, ey + 30), "不期而遇 · 郁金香的委托", 36, INK, True)
    text(d, (272, ey + 84), "终端上有三条新委托，", 24, DIM)
    text(d, (272, ey + 118), "发件人是郁金香。", 24, DIM)
    d.rounded_rectangle([272, ey + 160, 520, ey + 200], radius=8, fill=(30, 56, 60))
    text(d, (290, ey + 166), "主流派：E 远程·火力", 22, TEAL)
    opts = [
        ("点开最棘手的委托", "接下来 90 秒敌人生命与伤害 +30%，来一支精英小队", "完成：主流派藏品三选一，源石锭 +15", RED),
        ("点开稍有挑战性的委托", "接下来 90 秒敌人生命与伤害 +20%", "存活：整局经验 +15%", RED),
        ("点开看似轻松的委托", "60 秒内击败 150 名敌人", "完成：源石锭 +10", DIM),
        ("关闭终端", "离开", "", DIM),
    ]
    oy = ey + 236
    for name, cost, gain, col in opts:
        hgt = 140 if gain else 92
        d.rounded_rectangle([48, oy, W - 48, oy + hgt], radius=10, fill=(28, 36, 46), outline=col, width=2)
        text(d, (72, oy + 10), name, 30, INK, True)
        if col == RED:
            d.rounded_rectangle([W - 160, oy + 14, W - 68, oy + 46], radius=6, fill=RED)
            text(d, (W - 114, oy + 16), "代价", 22, BG, True, "ma")
        text(d, (72, oy + 54), cost, 22, RED if col == RED else DIM)
        if gain:
            text(d, (72, oy + 94), gain, 22, GOLD)
        oy += hgt + 12
    text(d, (48, ey + eh - 46), "付不起的选项灰掉并写原因；生命 < 30% 时不能再付生命", 22, DIM)

    # ---------- 代价 / 收益 ----------
    ry = ey + eh + 40
    d.rounded_rectangle([24, ry, W - 24, ry + 420], radius=18, fill=PANEL, outline=LINE, width=3)
    text(d, (52, ry + 24), "代价", 30, RED, True)
    text(d, (560, ry + 24), "收益（按主流派出）", 30, GOLD, True)
    costs = ["当前生命 −20%", "最大生命 −10%", "源石锭 −15", "遭诅藏品一件", "交出一件藏品", "队友暂离 120 秒", "90 秒限时强敌"]
    gains = ["主流派藏品 / 三选一", "一名干员精英化一级", "招募（对口职业加权）", "整局经验 +15%", "最大生命 / 护盾", "源石锭", "同档换对口藏品"]
    for i, (c, g) in enumerate(zip(costs, gains)):
        text(d, (52, ry + 80 + i * 46), "· " + c, 24, INK)
        text(d, (560, ry + 80 + i * 46), "· " + g, 24, INK)
    end_y = ry + 450
    text(d, (40, end_y), "结局线规则不变：路口一必出狂徒妄念与开端，结局只看信物", 24, END_COL["四"])
    img = img.crop((0, 0, W, end_y + 60))
    os.makedirs(os.path.dirname(out), exist_ok=True)
    img.save(out, optimize=True)
    print(out, img.size)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else os.path.join("docs", "reference", "172_event_redesign.png"))
