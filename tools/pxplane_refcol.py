#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""转平面出图的「原作」一栏（docs/256 §4、docs/257）：原作参照图只在本机（Claude outputs/<干员>_ref/，不进 git、不上 GCP），
GCP 出的三栏对比（cmp_*.png：① 当前游戏 / ② 旧做法 / ③ 转平面）下载后，在本机用 PIL 把原作一格贴在最左边，存成 cmp4_*.png。不开 Godot。

  python tools/pxplane_refcol.py --op texas --src "<下载目录>" --out "<交付目录>"

原作参照取 tools/ref_fx 回放出的 *_ref_keyframes.png（4 × 2 格，每格 480 × 320，标题里有时刻）；REF 表写每招取哪几格（竖着叠）。
原作没有对应特效的招（德克萨斯 S2 原作是立即获得部署费用、S3 原作是剑雨滂沱持续落剑、连携是本作原创）只写一行说明，不编图。
"""
import argparse, glob, os

from PIL import Image, ImageDraw, ImageFont

FONT = "C:/Windows/Fonts/msyh.ttc"
CELL = (480, 320)
# 招 → [(keyframes 文件, 格号 0–7)]
REF = {
    "texas": {
        "atk": [("texas_attack_01_start+texas_attack_01_hit_ref_keyframes.png", 1), ("texas_attack_01_start+texas_attack_01_hit_ref_keyframes.png", 2)],
        "s1": [("texas_skill_01_start_ref_keyframes.png", 1), ("texas_skill_01_hit_ref_keyframes.png", 2), ("texas_skill_01_range_ref_keyframes.png", 3)],
    },
}
NOTE = {
    "texas": {
        "s2": "原作 S2「冲锋号令」为立即获得部署费用，\n没有攻击特效；本作改写为冲刺强化，\n这一招无原作参照。",
        "s3": "原作 S3「剑雨滂沱」的参照未回放\n（本地只有普攻与 S1 的原作特效）；\n本作改写为次元斩，无原作参照。",
        "link": "连携技是本作原创，无原作参照。",
        "s3burst": "",
    },
}


def font(sz):
    return ImageFont.truetype(FONT, sz)


def ref_column(op, key, refdir, H):
    W = 640
    col = Image.new("RGB", (W, H), (12, 12, 16))
    d = ImageDraw.Draw(col)
    d.rectangle((8, 8, 8 + 300, 50), fill=(0, 0, 0))
    d.text((16, 10), "⓪ 原作参照（本机回放，近似）", fill=(255, 255, 255), font=font(24))
    cells = REF.get(op, {}).get(key)
    if not cells:
        d.multiline_text((24, 90), NOTE.get(op, {}).get(key, "无原作参照"), fill=(200, 200, 200), font=font(24), spacing=10)
        return col
    y = 60
    h = (H - 70) // len(cells)
    for f, i in cells:
        im = Image.open(os.path.join(refdir, f)).convert("RGB")
        cx, cy = (i % 4) * CELL[0], (i // 4) * CELL[1]
        c = im.crop((cx, cy, cx + CELL[0], cy + CELL[1]))
        s = min(W / CELL[0], h / CELL[1])
        c = c.resize((int(CELL[0] * s), int(CELL[1] * s)), Image.LANCZOS)
        col.paste(c, ((W - c.width) // 2, y))
        y += h
    return col


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--op", default="texas")
    ap.add_argument("--src", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--refdir", default="")
    a = ap.parse_args()
    refdir = a.refdir or os.path.join("E:/ArknightsSurvivors/Claude outputs", a.op + "_ref")
    os.makedirs(a.out, exist_ok=True)
    for f in sorted(glob.glob(os.path.join(a.src, "cmp_*.png"))):
        base = os.path.basename(f)
        if base.endswith("_x2.png"):
            continue
        key = base[4:-4].rsplit("_e", 1)[0] if "_e" in base else base[4:-4]
        im = Image.open(f).convert("RGB")
        col = ref_column(a.op, key, refdir, im.height)
        out = Image.new("RGB", (col.width + 4 + im.width, im.height), (12, 12, 16))
        out.paste(col, (0, 0))
        out.paste(im, (col.width + 4, 0))
        out.save(os.path.join(a.out, "cmp4_" + base[4:]))
        print("cmp4_" + base[4:])


if __name__ == "__main__":
    main()
