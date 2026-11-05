#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""终结技 × 新美术差异盘点（docs/278）的对照总图：每人一行 = 原版终结技 8 帧（ult_inventory.py ult 的联系表拆格）+ 新美术 S3 / 普攻招牌帧（中心 640×360）。
只用 PIL，本机可跑。  python tools/ult_inventory_sheet.py --ult <dir> --art <dir> [<dir> …] --order a,b,… --out <png> [--chunk 5]"""
import argparse, glob, os
from PIL import Image, ImageDraw, ImageFont

NAMES = {"angelina": "安洁莉娜", "exusiai": "能天使", "eyjafjalla": "艾雅法拉", "gladiia": "歌蕾蒂娅", "hoshiguma": "星熊", "irene": "艾丽妮", "kaltsit": "凯尔希",
         "lappland": "拉普兰德", "logos": "逻各斯", "lumen": "流明", "mizuki": "水月", "saria": "塞雷娅", "siege": "推进之王", "skadi": "斯卡蒂", "skalter": "浊心斯卡蒂",
         "specter_unchained": "归溟幽灵鲨", "suzuran": "铃兰", "texas": "德克萨斯", "ulpianus": "乌尔比安", "wisadel": "维什戴尔"}


def font(sz):
    return ImageFont.truetype("C:/Windows/Fonts/msyh.ttc", sz)


def cells(p):
    """拆 ult_inventory 联系表：4 列、每格 480×270、表头 44、每行 298（24 字条 + 270 图 + 4）"""
    im = Image.open(p).convert("RGB")
    out = []
    rows = (im.height - 44) // 298
    for r in range(rows):
        for c in range(4):
            x, y = c * 484, 44 + r * 298 + 24
            out.append(im.crop((x, y, x + 480, y + 270)))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ult", required=True)
    ap.add_argument("--art", nargs="+", required=True)
    ap.add_argument("--order", required=True)
    ap.add_argument("--tags", default="", help="op:标签;… 写在名字下（如差异度）")
    ap.add_argument("--out", required=True)
    ap.add_argument("--chunk", type=int, default=0)
    a = ap.parse_args()
    ops = a.order.split(",")
    tags = dict(x.split(":", 1) for x in a.tags.split(";") if ":" in x)
    tw, th = 320, 180
    lw = 170
    W = lw + 8 * (tw + 4) + 16 + 2 * (tw + 4)
    groups = [ops[i:i + a.chunk] for i in range(0, len(ops), a.chunk)] if a.chunk else [ops]
    for gi, grp in enumerate(groups):
        sh = Image.new("RGB", (W, 60 + len(grp) * (th + 10)), (12, 12, 16))
        d = ImageDraw.Draw(sh)
        d.text((10, 14), "原版终结技（integ-1105 现行，8 帧：起手前 → 收尾）", fill=(235, 235, 235), font=font(24))
        d.text((lw + 8 * (tw + 4) + 16, 14), "新美术：S3 ｜ 普攻（精二）", fill=(255, 210, 120), font=font(24))
        for r, op in enumerate(grp):
            y = 60 + r * (th + 10)
            d.text((10, y + 50), NAMES.get(op, op), fill=(255, 255, 255), font=font(26))
            if op in tags:
                d.text((10, y + 92), tags[op], fill=(255, 150, 120), font=font(20))
            p = os.path.join(a.ult, "%s_ult_sheet.png" % op)
            if os.path.exists(p):
                for k, c in enumerate(cells(p)[:8]):
                    sh.paste(c.resize((tw, th), Image.LANCZOS), (lw + k * (tw + 4), y))
            for k, mode in enumerate(("s3", "atk")):
                q = [x for dd in a.art for x in glob.glob(os.path.join(dd, "%s_%s.png" % (op, mode)))]
                if q:
                    im = Image.open(q[0]).convert("RGB").crop((320, 180, 960, 540)).resize((tw, th), Image.LANCZOS)
                    sh.paste(im, (lw + 8 * (tw + 4) + 16 + k * (tw + 4), y))
        out = a.out if not a.chunk else a.out.replace(".png", "_%d.png" % gi)
        sh.save(out)
        print(out)


if __name__ == "__main__":
    main()
