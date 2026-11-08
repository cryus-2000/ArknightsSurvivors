"""Q 版半身像素小人（11-08 用户：照用户给的参考小人的格子标准，约 16 × 18 格，不用黑描边，最深发色当轮廓，一只眼 + 腮红）。
用法：python tools/chibi/chibi_grids.py <输出目录> [--install]
  → 每人 op_<id>_chibi.png（1 格 = 1 像素）+ 总览 preview.png；--install 直接拷到 game/art/operators/<id>/。
做法：共用一套头 / 脸 / 身子模板，每人只换发长、露眼的一侧、头饰（耳 / 角 / 帽 / 光环 / 发箍 / 鳍 / 面罩）和配色；
配色取 PRTS 立绘（build/prts_ref/<id>/standing_1 / idle，有取色表的按 build/prts_ref/_colors）。德克萨斯、能天使是先手绘定稿的，原样保留。
分享卡相框左下角的小队成员用（share_card.chibi，外加一格相框描边色轮廓）。"""
import sys, os, shutil
from PIL import Image

W = 16

# ---------------------------------------------------------------- 模板
HEAD = [
    "....DDDDDDDD....",
    "..DDHHHHHHHHDD..",
    ".DHHHLLLHHHHHHD.",
    "DHHHLLHHHHHHHHHD",
    "DHHHHHHHHHHDHHHD",
]
FACE_R = [  # 露右眼（看的人的右边）
    "DHHHHHHHHHDSSHHD",
    "DHHHHHHHHDSSESHD",
    "DHHHHHHHDSSSISHD",
    "DHHDHHHSSBSSSBHD",
    "DHHDHDSSSSSSSSHD",
]
BODY = [
    "...JCCCCCCCCJ...",
    "..JJWWCCCCWWJJ..",
    "..JWWWAWWWWWWJ..",
    ".JJWGWWAWWWWGJJ.",
    ".JJWGWWWAWWWGJJ.",
    "..KKKKKKKKKKKK..",
]
LONG = ["DHH", "HHD"]   # 长发：身子两侧各垂 3 格

ACC = {   # 头饰：键 = 相对头顶行的偏移（-4..-1 在头上方，0.. 覆盖头 / 脸行），'.' 不改
    "wolf": {-3: ".D............D.", -2: ".DD..........DD.", -1: ".DXD........DXD.", 0: ".DXHDDDDDDDDHXD."},
    "fox": {-4: "D..............D", -3: "DD............DD", -2: "DXD..........DXD", -1: "DXXD........DXXD", 0: "DXXHDDDDDDDDHXXD"},
    "cat": {-3: ".Q............Q.", -2: ".QD..........DQ.", -1: ".DXD........DXD.", 0: ".DXHDDDDDDDDHXD."},
    "lion": {-1: "..DD........DD..", 0: ".DXHDDDDDDDDHXD."},
    "ram": {1: "OO............OO", 2: "OPO..........OPO", 3: ".OO..........OO.", 4: "..O..........O.."},
    "vouivre": {-3: "..O..........O..", -2: "..OO........OO..", -1: "...OY......YO..."},
    "oni": {-2: ".....O..........", -1: ".....OO........."},
    "spikes": {-4: "..T..........T..", -3: ".TT..T....T..TT.", -2: "..TTTT....TTTT..", -1: "...TT......TT..."},
    "redhalo": {-4: "....rRRRRRRr....", -3: "...R........R...", -2: "..T.RRRRRRRR.T..", -1: "..TT........TT.."},
    "hat": {-3: "....TTTTTTTT....", -2: "...TTTTTTTTTT...", -1: "...TTTTTTTTTT...", 0: "BBBBBBBBBBBBBBBB"},
    "beret": {-2: "...TTTTTTTTT....", -1: "..TTTTEETTTTTT..", 0: "..TTTTTTTTTTTT.."},
    "band": {1: "..DDRRRRRRRRDD.."},
    "fins": {2: "F..............F", 3: "FF............FF", 4: "F..............F"},
    "crown": {-4: ".....Y.Y.Y......", -3: "....TTTTTTTT....", -2: "...TTTTTTTTTT...", -1: "..BBBBBBBBBBBB.."},
}

BASE = {"S": "fbe9dc", "B": "f2bdb2", "E": "1e1418", "K": "2a2a30"}

# 每人：pal（D/H/L 发、I 瞳、C 领、W 上衣、G 上衣暗部、A 点缀、J 外套两侧、K 腰带，头饰色 X/O/P/T/B/R/r/Y/E/F/Q/M）
OPS = {
    "angelina": {"long": True, "eye": "L", "acc": ["fox", "band"], "pal": {"D": "6f463d", "H": "a17b6f", "L": "c6a59b", "X": "f0d0c4", "R": "c0302a", "I": "b8433a",
                 "C": "3d2f2b", "W": "dececa", "G": "b9aea8", "A": "c0302a", "J": "80221a"}},
    "eyjafjalla": {"long": False, "eye": "R", "acc": ["ram"], "pal": {"D": "6b4436", "H": "a06d5c", "L": "c99886", "O": "d9cbb6", "P": "8f7f6e", "I": "d4687a",
                   "C": "2b2422", "W": "f2e4e0", "G": "d5b7ad", "A": "c43a3a", "J": "8f6455"}},
    "gladiia": {"long": True, "eye": "L", "acc": ["hat"], "pal": {"D": "9797a8", "H": "ddddee", "L": "ffffff", "T": "181824", "B": "2b2a38", "I": "c4202a",
                "C": "ebebf4", "W": "2b2a38", "G": "181824", "A": "a01828", "J": "10101f"}},
    "hoshiguma": {"long": True, "eye": "R", "acc": ["oni"], "pal": {"D": "1f3c38", "H": "35665c", "L": "6f9a8c", "O": "f0dfd4", "I": "d8a73c",
                  "C": "0f1719", "W": "3f3f40", "G": "212c2d", "A": "86aa9a", "J": "1b1c1e"}},
    "irene": {"long": True, "eye": "L", "acc": ["spikes"], "pal": {"D": "7d7a74", "H": "b8b5ad", "L": "e1dfd6", "T": "272625", "I": "8a7fa0",
              "C": "272625", "W": "eae5db", "G": "c2bfb7", "A": "c0303a", "J": "615f5b"}},
    "kaltsit": {"long": False, "eye": "R", "acc": ["cat"], "pal": {"D": "9fa27e", "H": "d9dcc0", "L": "f6f7e8", "X": "f0f2dc", "Q": "403a28", "I": "6a9a3a",
                "C": "060605", "W": "b9c196", "G": "8a9070", "A": "060605", "J": "f9fae1"}},
    "lappland": {"long": True, "eye": "L", "acc": ["wolf"], "pal": {"D": "979594", "H": "e7e5e5", "L": "ffffff", "X": "5d5c5c", "I": "6e6c6c",
                 "C": "292828", "W": "3a3939", "G": "292828", "A": "b9b7b5", "J": "1e1d1d"}},
    "logos": {"long": False, "eye": "R", "acc": ["spikes"], "pal": {"D": "6f7180", "H": "a9aab7", "L": "d6d7e0", "T": "131315", "I": "c42a2a",
              "C": "131315", "W": "303032", "G": "131315", "A": "2a7fc0", "J": "040404"}},
    "lumen": {"long": False, "eye": "L", "acc": ["fins"], "pal": {"D": "171c24", "H": "2b303a", "L": "4a5566", "F": "4f86b8", "I": "88a9bb",
              "C": "34628a", "W": "f1f1ef", "G": "d8cac2", "A": "34628a", "J": "3b4452"}},
    "mizuki": {"long": False, "eye": "R", "acc": ["beret"], "pal": {"D": "6f86a0", "H": "a8c8dc", "L": "e7f3f6", "T": "18193c", "E": "4a7fe0", "I": "e09ab0",
               "C": "2a3ab0", "W": "f4f6f8", "G": "c1c9d0", "A": "e0c040", "J": "373d5e"}},
    "saria": {"long": True, "eye": "L", "acc": ["vouivre"], "pal": {"D": "77706f", "H": "c2b9b1", "L": "ebe1d4", "O": "4e4848", "Y": "e06a2a", "I": "d07a3a",
              "C": "171418", "W": "ebe1d4", "G": "c2b9b1", "A": "e06a2a", "J": "443735"}},
    "siege": {"long": True, "eye": "R", "acc": ["lion"], "pal": {"D": "8a6a40", "H": "c9a66a", "L": "e6d2a8", "X": "e6d2a8", "I": "c88a30",
              "C": "e6d7c7", "W": "f2efec", "G": "c8c0b8", "A": "a02020", "J": "1b1a1a"}},
    "skadi": {"long": True, "eye": "L", "acc": ["hat"], "pal": {"D": "5a5858", "H": "979595", "L": "c8c4c4", "T": "0c0d0f", "B": "1b6287", "I": "c01818",
              "C": "213a49", "W": "383538", "G": "262628", "A": "53373c", "J": "1a2b36"}},
    "skalter": {"long": True, "eye": "R", "acc": ["crown"], "pal": {"D": "6e6f71", "H": "a1a4a5", "L": "e5dfdd", "T": "2a8a7a", "B": "1f5a52", "Y": "d8b050", "I": "c0202a",
                "C": "180606", "W": "ae282f", "G": "871a20", "A": "e5dfdd", "J": "551316"}},
    "specter_unchained": {"long": True, "eye": "L", "acc": ["hat"], "pal": {"D": "586677", "H": "acb0b3", "L": "e5ded8", "T": "e5ded8", "B": "14151b", "I": "c0303a",
                          "C": "e5ded8", "W": "252a37", "G": "14151b", "A": "586677", "J": "09080c"}},
    "suzuran": {"long": False, "eye": "R", "acc": ["fox", "band"], "pal": {"D": "b39a5a", "H": "e8d29a", "L": "fbf3d0", "X": "f2c4c4", "R": "4a9ad8", "I": "8ab83a",
                "C": "ccc9b8", "W": "fbf7e4", "G": "dfccaf", "A": "4a9ad8", "J": "8e9186"}},
    "ulpianus": {"long": False, "eye": "L", "acc": ["hat"], "mask": True, "pal": {"D": "65696d", "H": "978e86", "L": "c8beb5", "T": "2b2c34", "B": "194262", "M": "15181d", "I": "c01020",
                 "C": "15181d", "W": "2b2c34", "G": "15181d", "A": "820d2e", "J": "3f4147"}},
    "wisadel": {"long": True, "eye": "R", "acc": ["redhalo"], "pal": {"D": "5e5e60", "H": "a09fa0", "L": "d4d3d3", "R": "b02a2a", "r": "e05050", "T": "191718", "I": "d02a2a",
                "C": "191718", "W": "2a2628", "G": "191718", "A": "b02a2a", "J": "5e3838"}},
}

# 先手绘定稿的两人（原样）
HAND = {
    "texas": {
        "pal": {"D": "23252d", "H": "41485e", "L": "6b7184", "X": "b9a99a", "S": "fbe9dc", "B": "f2bdb2", "E": "1a1418", "I": "e08a3c",
                "C": "1c1c22", "W": "f1efec", "G": "c9c6c3", "R": "b5303a", "K": "2a2a30"},
        "rows": [
            ".D............D.", ".DD..........DD.", ".DXD........DXD.", ".DXHDDDDDDDDHXD.", "DHHHHHHLLHHHHHHD", "DHHHLLLHHHHHHHHD",
            "DHHHHHHHHHHDHHHD", "DHHHHHHHHHDSSHHD", "DHHHHHHHHDSSESHD", "DHHHHHHHDSSSISHD", "DHHDHHHSSBSSSBHD", "DHHDHDSSSSSSSSHD",
            "DHHDDCCCCCCCCDHD", "DHHDWWCCCCCCWWHD", "DHHWWWRWCCWWWWHD", ".DHWGWWRWWWWWGHD", ".DHWGWWWRWWWWGD.", "..DKKKKKKRKKKKD.",
        ],
    },
    "exusiai": {
        "pal": {"D": "4a1a2a", "H": "8a3350", "L": "b85a78", "Y": "f0d27a", "y": "fff3c8", "S": "fbe9dc", "B": "f2bdb2", "E": "2a1418", "I": "cd885e",
                "J": "2a2630", "W": "ece8e4", "G": "bdb6b0", "M": "d92768", "F": "f6e3c0", "K": "1e1c22"},
        "rows": [
            "....yYYYYYYy....", "...YY......YY...", "....YYYYYYYY....", "....DDDDDDDD....", "..DDHHHHHHHHDD..", ".DHHHLLLHHHHHHD.",
            "DHHHLLHHHHHHHHHD", "DHHHHHHHHHHDHHHD", "HDDSSSDHHHHHHHDH", "DHDSESSDHHHHHHHD", "DHDSISSSDHHHHHHD", "DHHBSSSSSBHHDHHD",
            "D.DHSSSSSSHD.HD.", "F.JJJWWWWWWJJJ.F", "FFJJWWMWWWWWJJFF", ".FJJWGWWWWWGJJF.", "..JJWGWWWWWGJJ..", "..JKKKKKKKKKKJ..",
        ],
    },
}


def build(op):
    if op in HAND:
        return HAND[op]["rows"], HAND[op]["pal"]
    o = OPS[op]
    face = FACE_R if o["eye"] == "R" else [r[::-1] for r in FACE_R]
    head = HEAD if o["eye"] == "R" else [r[::-1] for r in HEAD]
    rows = [list(r) for r in head + face]
    body = [list(r) for r in BODY]
    if o.get("long"):
        for r in body[:5]:
            r[0:3] = list(LONG[0])
            r[13:16] = list(LONG[1])
    if o.get("mask"):   # 面罩：脸下两行的皮肤 / 腮红换成面罩色
        for r in rows[8:10]:
            for i, ch in enumerate(r):
                if ch in "SB":
                    r[i] = "M"
    top = [list("." * W) for _ in range(4)]
    grid = top + rows + body   # 头顶行在第 4 行
    for name in o["acc"]:
        for off, pat in ACC[name].items():
            y = 4 + off
            for x, ch in enumerate(pat):
                if ch != ".":
                    grid[y][x] = ch
    rows = ["".join(r) for r in grid]
    while rows and set(rows[0]) == {"."}:
        rows.pop(0)
    pal = dict(BASE)
    pal.update(o["pal"])
    return rows, pal


def render(op):
    rows, pal = build(op)
    im = Image.new("RGBA", (W, len(rows)), (0, 0, 0, 0))
    for y, r in enumerate(rows):
        assert len(r) == W, (op, y, r)
        for x, ch in enumerate(r):
            if ch in pal:
                h = pal[ch]
                im.putpixel((x, y), (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), 255))
            elif ch != ".":
                raise SystemExit("%s：第 %d 行字符 %s 没有配色" % (op, y, ch))
    return im


if __name__ == "__main__":
    out = sys.argv[1]
    install = "--install" in sys.argv
    os.makedirs(out, exist_ok=True)
    allops = sorted(list(OPS) + list(HAND))
    tiles = []
    for op in allops:
        im = render(op)
        p = os.path.join(out, "op_%s_chibi.png" % op)
        im.save(p)
        if install:
            dst = os.path.join(os.path.dirname(__file__), "..", "..", "game", "art", "operators", op)
            if os.path.isdir(dst):
                shutil.copy(p, os.path.join(dst, "op_%s_chibi.png" % op))
        big = im.resize((im.size[0] * 10, im.size[1] * 10), Image.NEAREST)
        bg = Image.new("RGBA", (200, 240), (205, 225, 245, 255))
        bg.alpha_composite(big, ((200 - big.size[0]) // 2, 240 - big.size[1] - 6))
        tiles.append((op, bg))
    cols = 5
    o = Image.new("RGB", (cols * 210 + 10, ((len(tiles) + cols - 1) // cols) * 270 + 10), (60, 62, 68))
    from PIL import ImageDraw
    dr = ImageDraw.Draw(o)
    for i, (op, t) in enumerate(tiles):
        x, y = 10 + (i % cols) * 210, 10 + (i // cols) * 270
        o.paste(t, (x, y + 20))
        dr.text((x + 2, y + 4), op, fill=(230, 230, 230))
    o.save(os.path.join(out, "preview.png"))
    print("ok", len(tiles))
