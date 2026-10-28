# -*- coding: utf-8 -*-
"""第三批干员（docs/59）技能图标：浊心斯卡蒂 / 德克萨斯 / 星熊 / 能天使 / 安洁莉娜 各 S1–S3，共 15 个。

写到运行时 game/art/ui/skills/skill_<id>_s<n>.png（32×32，与 make_skill_icons.py 同尺寸同构图）。
构图沿用 make_skill_icons.py 的「原作风格方形技能图标」：暗色渐变方形底 + 彩色楔形 / 五边形 / 圆 + 扁平白色主体，
S3 加白框；方形底的几何与上色引擎直接 import make_skill_icons（Icon / tile / frame / wedge …），
白色主体（音符、剑、盾、鬼面、枪、子弹、重力箭头……）全部是本文件里的手摆字符图（bitmap），不用原作图片。

身份色（docs/59 各节「美术」行）：
  浊心斯卡蒂  浊心红 #D94059 + 海蓝点缀（歌、音符、波纹）
  德克萨斯    红 + 橙 #FF8C33（剑雨、冲刺剑光）
  星熊        鬼金 #F2BF4D（盾、热砂、鬼面）——防御类沿用原作图标的金色
  能天使      天使红 + 白色弹道（子弹、枪、光环）
  安洁莉娜    重力紫 #B380F2（重力球、环带、悬浮）

只写清单里的 id：art/incoming/skill_icons_batch3_manifest.json 记着本脚本接入的文件；
目标文件已存在而不在清单里（别人手绘的）一律不覆盖，除非 --force。

用法：
  python tools/skill_icons_batch3.py                 # 生成并写入
  python tools/skill_icons_batch3.py --preview x.png # 另存放大预览（6 倍 + HUD 20px 格子 ×4）
  python tools/skill_icons_batch3.py --no-write --preview x.png
"""
import argparse
import json
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_skill_icons as M  # noqa: E402
from make_skill_icons import (Icon, tile, frame, wedge, xrays, house, ngon, ering, star_pts,  # noqa: E402
                              WHT, REDM, GOLDM, DARK, BLACK, ramp, H)

OUT_DIR = M.OUT_DIR
MANIFEST = os.path.join(OUT_DIR, "skill_icons_batch3_manifest.json")
OPS = ["skalter", "texas", "hoshiguma", "exusiai", "angelina"]

# ---------------------------------------------------------------- 身份色（两档：0.0 暗面 / 1.0 亮面，同 REDM 的用法）
SKR = ramp("#8e1f3a", "#d94059")       # 浊心红
SEA = ramp("#1a5e98", "#36a4dc")       # 海蓝
ORG = ramp("#b8501e", "#ff8c33")       # 德克萨斯橙
VIO = ramp("#5b3a9e", "#a77ef0")       # 重力紫
SAND = ramp("#b8601e", "#e08a3a")      # 热砂

# 字符图图例：值为 (色阶, 亮度)
LEG = {
    "W": (WHT, 1.0), "g": (WHT, 0.0),
    "R": (REDM, 1.0), "r": (REDM, 0.0),
    "K": (DARK, 0.5), "X": (BLACK, 0.5),
    "Y": (GOLDM, 1.0), "y": (GOLDM, 0.0),
    "S": (SKR, 1.0), "s": (SKR, 0.0),
    "B": (SEA, 1.0), "b": (SEA, 0.0),
    "O": (ORG, 1.0), "o": (ORG, 0.0),
    "V": (VIO, 1.0), "v": (VIO, 0.0),
    "A": (SAND, 1.0), "a": (SAND, 0.0),
}

ICONS = {}


def icon(op, n):
    def deco(fn):
        ICONS[(op, n)] = fn
        return fn
    return deco


def stamp(ic, rows, x0, y0, sub=None):
    """贴一张字符图；sub 把字符整体换成另一个字符（同一张图画成残影 / 换色）"""
    if sub:
        rows = ["".join(sub.get(c, c) if c != "." else "." for c in r) for r in rows]
    ic.bitmap(rows, x0, y0, LEG)


def mirror(half, odd=False):
    """左半边 → 左右对称的整行（odd：中间一列不重复）"""
    return [h + (h[-2::-1] if odd else h[::-1]) for h in half]


def rot90(rows):
    """字符图顺时针转 90°"""
    h, w = len(rows), len(rows[0])
    return ["".join(rows[h - 1 - y][x] for y in range(h)) for x in range(w)]


# ================================================================ 字符图
NOTE_PAIR = [            # 两个连在一起的八分音符（16×17）
    ".....WWWWWWWWWWW",
    ".....WWWWWWWWWWW",
    ".....WWWWWWWWWWW",
    ".....WW.......WW",
    ".....WW.......WW",
    ".....WW.......WW",
    ".....WW.......WW",
    ".....WW.......WW",
    ".....WW.......WW",
    ".....WW.......WW",
    ".....WW.......WW",
    "..WWWWW....WWWWW",
    ".WWWWWW...WWWWWW",
    "WWWWWWW..WWWWWWW",
    "WWWWWW...WWWWWW.",
    ".WWWW.....WWWW..",
]

NOTE_ONE = [             # 单个八分音符，带旗（14×20）
    "......WW......",
    "......WWW.....",
    "......WWWW....",
    "......WW.WW...",
    "......WW..WW..",
    "......WW...WW.",
    "......WW....WW",
    "......WW....WW",
    "......WW...WW.",
    "......WW..WW..",
    "......WW......",
    "......WW......",
    "......WW......",
    "......WW......",
    "..WWWWWW......",
    ".WWWWWWW......",
    "WWWWWWWW......",
    "WWWWWWW.......",
    ".WWWWW........",
]

NOTE_SMALL = [           # 小音符（6×9）
    "..WW..",
    "..WWW.",
    "..W.WW",
    "..W...",
    "..W...",
    "WWW...",
    "WWW...",
    ".W....",
]

SWORD_DOWN = [           # 剑尖朝下的短剑（5×10），上面两格是橙色拖影
    "..o..",
    "..O..",
    ".WWW.",
    "WWWWW",
    ".WWW.",
    ".WWW.",
    ".WWW.",
    ".WWW.",
    ".WWW.",
    "..W..",
]

SWORD_DIAG = [           # 右上指向的长剑（18×18）
    "...............WWW",
    "..............WWWW",
    ".............WWWW.",
    "............WWWW..",
    "...........WWWW...",
    "..........WWWW....",
    ".........WWWW.....",
    "........WWWW......",
    ".......WWWW.......",
    "..W...WWWW........",
    "..WW.WWWW.........",
    "...WWWWW..........",
    "....WWW...........",
    "...WWWWW..........",
    "..WWW..WW.........",
    ".WWW..............",
    "WWW...............",
    "WW................",
]

SWORD_RIGHT = [          # 剑尖朝右的长剑（20×7）
    "....W...............",
    "....WW..............",
    "WW..WWWWWWWWWWWWWW..",
    "WWWWWWWWWWWWWWWWWWWW",
    "WW..WWWWWWWWWWWWWW..",
    "....WW..............",
    "....W...............",
]

CHEVRON_R = [            # 向右的箭头折角（5×7）
    "WW...",
    ".WW..",
    "..WW.",
    "...WW",
    "..WW.",
    ".WW..",
    "WW...",
]

SHIELD = mirror([        # 星熊的大盾（18×20），中间金色竖脊 + 横带
    "..WWWWWWW",
    ".WWWWWWWW",
    "WWWWWWWWy",
    "WWWWWWWWy",
    "WWWWWWWWy",
    "WWWWWWWWy",
    "WWWWWWWWy",
    "yyyyyyyyy",
    "WWWWWWWWy",
    "WWWWWWWWy",
    "WWWWWWWWy",
    "WWWWWWWWy",
    "WWWWWWWWy",
    ".WWWWWWWy",
    ".WWWWWWWy",
    "..WWWWWWy",
    "...WWWWWy",
    ".....WWWy",
    ".......WW",
])

ONI = mirror([           # 鬼面（20×19）：额上独角 + 两侧短角、红眼、獠牙
    ".........W",
    "........WW",
    "........WW",
    ".W......WW",
    ".WW....WWW",
    "..WWWWWWWW",
    "...WWWWWWW",
    "..WWWWWWWW",
    "..WRRRWWWW",
    "..WWRRRWWW",
    "..WWWWWWWW",
    "..WWWWWWWK",
    "...WWWWWWW",
    "...WKKWKKK",
    "...WKKKKKK",
    "....WWKKKW",
    ".....WWWWW",
    "......WWWW",
    "........WW",
])

HEAT = [                 # 热浪（4×10）
    ".WW.",
    "WW..",
    "WW..",
    ".WW.",
    "..WW",
    "..WW",
    ".WW.",
    "WW..",
    "WW..",
    ".WW.",
]

DUNE = [                 # 沙丘（28×7），橙色是砂粒
    "...........WWWWW............",
    ".......WWWWWWWWWWWWW........",
    "....WWWWWWaWWWWWWWWWWWWW....",
    "..WWWWWWWWWWWWWWWWaWWWWWWWW.",
    "WWWWaWWWWWWWWWWWWWWWWWWWWWWW",
    "WWWWWWWWWWWWWaWWWWWWWWWWaWWW",
    "WWWWWWWWWWWWWWWWWWWWWWWWWWWW",
]

BULLET_UP = mirror([     # 竖直大子弹（8×20）：弹头、弹壳、底缘
    "...W",
    "..WW",
    "..WW",
    ".WWW",
    ".WWW",
    "WWWW",
    "WWWW",
    "gggg",
    "WWWW",
    "WWWW",
    "WWWW",
    "WWWW",
    "WWWW",
    "WWWW",
    "WWWW",
    "WWWW",
    "WWWW",
    "gggg",
    "WWWW",
])

BULLET_S = [             # 小子弹（3×7）
    ".W.",
    "WWW",
    "WWW",
    "WWW",
    "ggg",
    "WWW",
    "WWW",
]

PISTOL = [               # 枪口朝右的手枪（22×11）
    "..WWWWWWWWWWWWWWWWWWW.",
    ".WWWWWWWWWWWWWWWWWWWWW",
    ".WWWWWWWWWWWWWWWWWWWWW",
    ".WWWWWWWWWWWWWWW......",
    ".WWWWWW..WWWWWWW......",
    "..WWWW....W..WW.......",
    "..WWWW.....WW.........",
    ".WWWWW................",
    ".WWWW.................",
    "WWWWW.................",
    "WWWW..................",
]

ARROW_DOWN = [           # 向下的粗箭头（7×6）
    "..WWW..",
    "..WWW..",
    "WWWWWWW",
    ".WWWWW.",
    "..WWW..",
    "...W...",
]

BLOB = [                 # 被托起的小海嗣（6×5）
    ".WWWW.",
    "WWWWWW",
    "WWVVWW",
    "WWWWWW",
    ".W..W.",
]

CHEVRON_UP = [           # 向上的折角（7×4）
    "...W...",
    "..WWW..",
    ".WW.WW.",
    "WW...WW",
]


# ================================================================ 浊心斯卡蒂
@icon("skalter", 1)
def skalter_wandering(ic):
    """吟游：浊心红楔形从左下张开 + 一对连音符 + 底部海蓝波纹"""
    tile(ic)
    wedge(ic, 2, 29, 50, 24, SKR, 1.0)
    for y, x0 in ((26, 2), (28, 2)):
        for x in range(x0, 30):
            k = (x + (0 if y == 26 else 3)) % 6
            if k in (0, 1, 2):
                ic.rect(x, y - (1 if k == 1 else 0), x, y - (1 if k == 1 else 0), SEA, 1.0 if y == 26 else 0.0)
    stamp(ic, NOTE_PAIR, 8, 6)
    ic.spark(26, 5, WHT[1])
    ic.spark(5, 9, WHT[1])


@icon("skalter", 2)
def skalter_call(ic):
    """深海的呼唤（永久）：浊心红五边形 + 自下而上扩散的三道声波 + 中心海蓝音符"""
    tile(ic)
    house(ic, SKR)
    for r0, r1, rp, v in ((15.0, 16.6, WHT, 1.0), (10.6, 12.2, WHT, 1.0), (6.2, 7.8, SEA, 1.0)):
        ic.ring(15.5, 27.5, r0, r1, rp, v, a0=28, a1=152)
    stamp(ic, NOTE_SMALL, 12, 18, {"W": "W"})
    stamp(ic, ["B"], 14, 25)


@icon("skalter", 3)
def skalter_deadland(ic):
    """死地之歌：白框 + 浊心红 X + 大音符，右下一枚暗灰残音与落下的红滴"""
    tile(ic)
    xrays(ic, SKR, half=13)
    stamp(ic, NOTE_ONE, 6, 5)
    stamp(ic, NOTE_SMALL, 20, 17, {"W": "g"})
    for x, y in ((23, 8), (25, 11), (22, 13)):
        ic.rect(x, y, x, y + 1, SKR, 0.0)
    frame(ic)


# ================================================================ 德克萨斯
@icon("texas", 1)
def texas_rain(ic):
    """剑雨：红色楔形自上压下 + 五柄错落落下的短剑 + 地面白线"""
    tile(ic)
    wedge(ic, 15.5, 0, -90, 28, REDM, 1.0)
    for x, y in ((3, 9), (9, 4), (14, 11), (20, 5), (25, 10)):
        stamp(ic, SWORD_DOWN, x, y)
    ic.rect(2, 25, 29, 25, WHT, 0.0)
    for x in (5, 11, 16, 22, 27):
        ic.rect(x - 1, 24, x + 1, 24, ORG, 1.0)


@icon("texas", 2)
def texas_partner(ic):
    """可靠伙伴（永久）：橙色楔形从左下冲出 + 斜指右上的长剑 + 左上两道前冲折角"""
    tile(ic)
    wedge(ic, 1, 30, 45, 20, ORG, 1.0)
    stamp(ic, SWORD_DIAG, 7, 6)
    stamp(ic, CHEVRON_R, 4, 4, {"W": "g"})
    stamp(ic, CHEVRON_R, 9, 4)


@icon("texas", 3)
def texas_express(ic):
    """连冲（暂名速递）：白框 + 右侧红色楔形 + 一柄长剑与上下两道残影（灰 / 橙）"""
    tile(ic)
    wedge(ic, 30, 15.5, 180, 26, REDM, 1.0)
    stamp(ic, SWORD_RIGHT, 3, 5, {"W": "g"})
    stamp(ic, SWORD_RIGHT, 3, 20, {"W": "O"})
    stamp(ic, SWORD_RIGHT, 8, 12)
    frame(ic)


# ================================================================ 星熊
@icon("hoshiguma", 1)
def hoshiguma_shield(ic):
    """举盾：金色五边形 + 白色大盾（金脊）+ 右上一点格挡闪光"""
    tile(ic)
    house(ic, GOLDM)
    stamp(ic, SHIELD, 7, 7)
    ic.spark(26, 6, WHT[1], big=True)


@icon("hoshiguma", 2)
def hoshiguma_sands(ic):
    """热砂：热砂橙的落日 + 三道上升的热浪 + 底部白色沙丘（橙色砂粒）"""
    tile(ic)
    ic.rect(1, 19, 30, 22, SAND, 0.0)
    ic.circle(20.5, 13.0, 8.0, SAND, 1.0)
    for x, y in ((6, 4), (13, 8), (23, 3)):
        stamp(ic, HEAT, x, y)
    stamp(ic, DUNE, 2, 23)


@icon("hoshiguma", 3)
def hoshiguma_demon(ic):
    """魔王：白框 + 红 X + 白色鬼面（红眼、獠牙）"""
    tile(ic)
    xrays(ic, half=14)
    stamp(ic, ONI, 6, 6)
    frame(ic)


# ================================================================ 能天使
@icon("exusiai", 1)
def exusiai_power(ic):
    """强力击：红色放射自下而上 + 竖立的大子弹 + 两侧速度线"""
    tile(ic)
    wedge(ic, 15.5, 31, 90, 22, REDM, 1.0)
    stamp(ic, BULLET_UP, 12, 5)
    for x, y0, y1 in ((6, 14, 22), (8, 20, 27), (24, 14, 22), (22, 20, 27)):
        ic.rect(x, y0, x, y1, WHT, 0.0)
    ic.spark(16, 3, H("#ffd86a"))


@icon("exusiai", 2)
def exusiai_overdrive(ic):
    """过载模式：红色五边形 + 白色手枪 + 枪口外三道弹道"""
    tile(ic)
    house(ic)
    stamp(ic, PISTOL, 2, 11)
    for y, x0 in ((9, 25), (12, 26), (15, 25)):
        ic.rect(x0, y, 29, y, WHT, 1.0 if y == 12 else 0.0)


@icon("exusiai", 3)
def exusiai_execution(ic):
    """处决模式：白框 + 红 X + 头顶光环 + 四发错落的子弹"""
    tile(ic)
    xrays(ic, half=13)
    ering(ic, 15.5, 7.5, 9.0, 3.2, 1.5, 0.0)
    for x, y in ((7, 16), (12, 13), (17, 13), (22, 16)):
        stamp(ic, BULLET_S, x, y)
    for x in (8, 13, 18, 23):
        ic.rect(x, 24 if x in (13, 18) else 25, x, 27, WHT, 0.0)
    frame(ic)


# ================================================================ 安洁莉娜
@icon("angelina", 1)
def angelina_adjust(ic):
    """重力调节：重力紫大圆 + 中心白色重力球 + 四个指向中心的箭头"""
    tile(ic)
    ic.circle(15.5, 15.5, 12.5, VIO, 1.0)
    ic.circle(15.5, 15.5, 7.5, VIO, 0.0)
    ic.circle(15.5, 15.5, 4.0, WHT, 1.0)
    ic.rect(14, 13, 14, 13, WHT, 0.0)
    a = ARROW_DOWN
    stamp(ic, a, 12, 2)                         # 上
    stamp(ic, rot90(rot90(a)), 12, 24)          # 下（朝上）
    stamp(ic, rot90(rot90(rot90(a))), 2, 12)    # 左（朝右）
    stamp(ic, rot90(a), 24, 12)                 # 右（朝左）


@icon("angelina", 2)
def angelina_control(ic):
    """重力控制（永久）：重力紫八边形 + 白色分段环带（束成一圈的敌人）+ 中心重力球"""
    tile(ic)
    ic.poly(ngon(15.5, 15.5, 14.6, 8, -90 + 22.5), VIO, 1.0)
    ic.poly(ngon(15.5, 15.5, 12.0, 8, -90 + 22.5), DARK, 0.5)
    for k in range(8):
        a0 = k * 45 + 6
        ic.ring(15.5, 15.5, 8.0, 10.2, WHT, 1.0, a0=a0, a1=a0 + 26)
    for k in range(8):
        a = math.radians(k * 45 + 41)
        x, y = 15.5 + 9.1 * math.cos(a), 15.5 - 9.1 * math.sin(a)
        ic.rect(int(x), int(y), int(x), int(y), VIO, 1.0)
    ic.circle(15.5, 15.5, 3.4, WHT, 1.0)
    ic.circle(15.5, 15.5, 1.4, VIO, 1.0)


@icon("angelina", 3)
def angelina_levitation(ic):
    """悬浮：白框 + 重力紫楔形自下张开 + 底部白色环带 + 三只被托起的海嗣与上升折角"""
    tile(ic)
    wedge(ic, 15.5, 31, 58, 14, VIO, 1.0)
    wedge(ic, 15.5, 31, 122, 14, VIO, 1.0)
    ering(ic, 15.5, 24.5, 11.5, 3.6, 1.5, 0.0)
    for x, y in ((5, 13), (13, 7), (21, 12)):
        stamp(ic, BLOB, x, y)
        for dx in (1, 4):
            ic.rect(x + dx, y + 7, x + dx, y + 9, WHT, 0.0)
    for x, y in ((10, 3), (20, 4)):
        stamp(ic, CHEVRON_UP, x, y, {"W": "g"})
    frame(ic)


# ================================================================ 出图
def render_all(only=None):
    out = {}
    for (op, n), fn in ICONS.items():
        if only and op not in only:
            continue
        ic = Icon()
        fn(ic)
        out[(op, n)] = ic.render()
    return out


def out_name(op, n):
    return "skill_%s_s%d" % (op, n)


def check(im, name):
    assert im.size == (32, 32), (name, im.size)
    vals = set(im.getchannel("A").tobytes())
    assert vals <= {0, 255}, (name, vals)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    ap.add_argument("--preview", default="")
    ap.add_argument("--no-write", action="store_true")
    ap.add_argument("--force", action="store_true", help="清单外的已有文件也覆盖")
    a = ap.parse_args()
    only = [s for s in a.only.split(",") if s]
    imgs = render_all(only)
    for (op, n), im in imgs.items():
        check(im, out_name(op, n))
    if not a.no_write:
        owned = set()
        if os.path.exists(MANIFEST):
            owned = set(json.load(open(MANIFEST, encoding="utf-8")).get("ids", []))
        wrote = 0
        for (op, n), im in sorted(imgs.items()):
            name = out_name(op, n)
            if os.path.exists(M.asset_paths.runtime_png(name)) and name not in owned and not a.force:
                print("跳过（清单外已有文件）：", name)
                continue
            im.save(M.asset_paths.out_png(name))
            owned.add(name)
            wrote += 1
        json.dump({"tool": "tools/skill_icons_batch3.py", "doc": "docs/59", "ids": sorted(owned)},
                  open(MANIFEST, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
        M.write_index()
        print("写入 %d 个图标 → game/art/ui/skills" % wrote)
    if a.preview:
        M.preview(imgs, a.preview)
        print("预览：", a.preview)


if __name__ == "__main__":
    main()
