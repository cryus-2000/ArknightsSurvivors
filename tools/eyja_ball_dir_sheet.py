#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""艾雅法拉直线弹朝向核对（11-06 用户「感觉是不是还是斜着飞过去的」）：不开 Godot，按游戏里同一套算法
（fx_pxplane.pick_dir 挑最近 45° 帧条 + 翻转，再绕锚点 = 弹头转掉剩余偏差）把帧条贴到 8 个方向 + 2 个中间角，
叠一根青线 = 真实飞行方向。上排 = 6c82c4138（按标称角转），下排 = 修正后（按帧条火体实测主轴转）。
用法：python tools/eyja_ball_dir_sheet.py <输出.png> [fire|lava|pow|ign]"""
import json, math, os, sys
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DIRS = [-90, -45, 0, 45, 90]
VIS = {-90: -85.6, -45: -40.7, 0: 4.4, 45: 49.3, 90: 94.4}   # 同 fx_pxplane.EY_BALL_VIS（火体主轴）
ANGS = [0, 45, 90, 135, 180, 225, 270, 315, 20, 160]
S = 4   # 放大倍数


def pick_dir(a):
    a = (a + 180) % 360 - 180
    flip = False
    if abs(a) > 90:
        a = (180 - a + 180) % 360 - 180
        flip = True
    best = 0
    for d in DIRS:
        if abs(a - d) < abs(a - best):
            best = d
    return best, flip


def main():
    out = sys.argv[1]
    st = sys.argv[2] if len(sys.argv) > 2 else "fire"
    meta = json.load(open(os.path.join(ROOT, "game", "data", "pxp_eyjafjalla.json"), encoding="utf-8"))
    meta = meta.get("strips", meta)
    cell = 70 * S
    f = ImageFont.truetype("C:/Windows/Fonts/msyh.ttc", 22)
    sheet = Image.new("RGB", (cell * len(ANGS), cell * 2 + 40), (24, 28, 34))
    d0 = ImageDraw.Draw(sheet)
    d0.text((8, 6), "艾雅法拉火球（%s）朝向核对：青线 = 真实飞行方向（穿过弹头）；上排 = 6c82c4138 按标称角转，下排 = 修正后按火体实测主轴转" % st, fill=(235, 235, 235), font=f)
    for row, corr in enumerate((False, True)):
        for i, ang in enumerate(ANGS):
            b, flip = pick_dir(ang)
            k = "ball_%s_d%d" % (st, b)
            m = meta[k]
            im = Image.open(os.path.join(ROOT, "game", "art", "fx", "pxp", "pxp_ey_%s.png" % k.replace("_d-", "_dm"))).convert("RGBA")
            fr = im.crop((6 * m["w"], 0, 7 * m["w"], m["h"])).resize((m["w"] * S, m["h"] * S), Image.NEAREST)
            ox, oy = m["ox"] * S, m["oy"] * S
            if flip:
                fr = fr.transpose(Image.FLIP_LEFT_RIGHT)
                ox = (m["w"] - m["ox"]) * S
            vis = VIS[b] if corr else b
            shown = 180 - vis if flip else vis
            res = ((ang - shown) + 180) % 360 - 180
            # 绕锚点转 res（屏幕 y 向下：正角 = 顺时针；PIL rotate 正角 = 逆时针）
            big = Image.new("RGBA", (cell * 2, cell * 2), (0, 0, 0, 0))
            big.alpha_composite(fr, (cell - ox, cell - oy))
            big = big.rotate(-res, resample=Image.NEAREST, center=(cell, cell))
            c = Image.new("RGBA", (cell, cell), (24, 28, 34, 255))
            c.alpha_composite(big.crop((cell // 2, cell // 2, cell // 2 + cell, cell // 2 + cell)))
            d = ImageDraw.Draw(c)
            hx, hy = cell // 2, cell // 2
            dx, dy = math.cos(math.radians(ang)), math.sin(math.radians(ang))
            d.line((hx - dx * cell * 0.48, hy - dy * cell * 0.48, hx + dx * cell * 0.3, hy + dy * cell * 0.3), fill=(60, 240, 255), width=2)
            d.text((6, cell - 30), "%d°  帧条 %s%d°  转 %+.1f°" % (ang, "翻 " if flip else "", b, res), fill=(220, 220, 220), font=ImageFont.truetype("C:/Windows/Fonts/msyh.ttc", 16))
            sheet.paste(c.convert("RGB"), (i * cell, 40 + row * cell))
    sheet.save(out)
    print(out)


if __name__ == "__main__":
    main()
