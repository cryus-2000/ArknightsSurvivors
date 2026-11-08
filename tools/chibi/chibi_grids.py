"""手绘 Q 版半身像素小人（11-08 用户：照参考图小人的格子标准，约 16 × 18 格，不用黑描边，最深发色当轮廓）。
用法：python tools/chibi/chibi_grids.py <输出目录>  → 每人 op_<id>_chibi.png（1 格 = 1 像素）+ 预览 preview.png；成品拷到 game/art/operators/<id>/。
配色取 PRTS 取色表（build/prts_ref/_colors），分享卡相框里队友探头用（share_card.chibi，一格 12、外加一格相框描边色轮廓）。"""
import sys, os
from PIL import Image

OPS = {
    "texas": {
        "pal": {"D": "23252d", "H": "41485e", "L": "6b7184", "X": "b9a99a", "S": "fbe9dc", "B": "f2bdb2", "E": "1a1418", "I": "e08a3c",
                "C": "1c1c22", "W": "f1efec", "G": "c9c6c3", "R": "b5303a", "K": "2a2a30"},
        "rows": [
            ".D............D.",
            ".DD..........DD.",
            ".DXD........DXD.",
            ".DXHDDDDDDDDHXD.",
            "DHHHHHHLLHHHHHHD",
            "DHHHLLLHHHHHHHHD",
            "DHHHHHHHHHHDHHHD",
            "DHHHHHHHHHDSSHHD",
            "DHHHHHHHHDSSESHD",
            "DHHHHHHHDSSSISHD",
            "DHHDHHHSSBSSSBHD",
            "DHHDHDSSSSSSSSHD",
            "DHHDDCCCCCCCCDHD",
            "DHHDWWCCCCCCWWHD",
            "DHHWWWRWCCWWWWHD",
            ".DHWGWWRWWWWWGHD",
            ".DHWGWWWRWWWWGD.",
            "..DKKKKKKRKKKKD.",
        ],
    },
    "exusiai": {
        "pal": {"D": "4a1a2a", "H": "8a3350", "L": "b85a78", "Y": "f0d27a", "y": "fff3c8", "S": "fbe9dc", "B": "f2bdb2", "E": "2a1418", "I": "cd885e",
                "J": "2a2630", "W": "ece8e4", "G": "bdb6b0", "M": "d92768", "F": "f6e3c0", "K": "1e1c22"},
        "rows": [
            "....yYYYYYYy....",
            "...YY......YY...",
            "....YYYYYYYY....",
            "....DDDDDDDD....",
            "..DDHHHHHHHHDD..",
            ".DHHHLLLHHHHHHD.",
            "DHHHLLHHHHHHHHHD",
            "DHHHHHHHHHHDHHHD",
            "HDDSSSDHHHHHHHDH",
            "DHDSESSDHHHHHHHD",
            "DHDSISSSDHHHHHHD",
            "DHHBSSSSSBHHDHHD",
            "D.DHSSSSSSHD.HD.",
            "F.JJJWWWWWWJJJ.F",
            "FFJJWWMWWWWWJJFF",
            ".FJJWGWWWWWGJJF.",
            "..JJWGWWWWWGJJ..",
            "..JKKKKKKKKKKJ..",
        ],
    },
}


def render(op):
    d = OPS[op]
    rows = d["rows"]
    w = max(len(r) for r in rows)
    for r in rows:
        assert len(r) == w, (op, r, len(r))
    im = Image.new("RGBA", (w, len(rows)), (0, 0, 0, 0))
    for y, r in enumerate(rows):
        for x, ch in enumerate(r):
            if ch in d["pal"]:
                h = d["pal"][ch]
                im.putpixel((x, y), (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), 255))
    return im


if __name__ == "__main__":
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    tiles = []
    for op in OPS:
        im = render(op)
        im.save(os.path.join(out, "op_%s_chibi.png" % op))
        big = im.resize((im.size[0] * 14, im.size[1] * 14), Image.NEAREST)
        bg = Image.new("RGBA", (big.size[0] + 40, 300), (205, 225, 245, 255))
        bg.alpha_composite(big, (20, 300 - big.size[1] - 10))
        tiles.append(bg)
    W = sum(t.size[0] for t in tiles) + 20 * (len(tiles) + 1)
    o = Image.new("RGB", (W, 340), (60, 62, 68))
    x = 20
    for t in tiles:
        o.paste(t, (x, 20))
        x += t.size[0] + 20
    o.save(os.path.join(out, "preview.png"))
    print("ok")
