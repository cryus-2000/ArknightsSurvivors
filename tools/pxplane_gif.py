#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""斯卡蒂转平面帧条直接拼 GIF（docs/246，本机不开 Godot）：读 game/art/fx/pxp/ 的帧条 + data/pxp_skadi.json 的原点，
贴地层在下、立起层在上，脚底放一张斯卡蒂待机帧做比例参照，15 fps；每行一招、每列一档（E0 / E1 / E2）。

用法：python tools/pxplane_gif.py --moves basic,s1 --dir 0 --out "<目录>/tiers_atk_s1.gif"
"""
import argparse, json, os

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ART = os.path.join(ROOT, "game", "art", "fx", "pxp")
META = json.load(open(os.path.join(ROOT, "game", "data", "pxp_skadi.json"), encoding="utf-8"))
OP = os.path.join(ROOT, "game", "art", "operators", "skadi", "op_skadi_idle@2x.png")
NAME = {"basic": "普攻", "s1": "S1 迅捷打击·γ型", "spin": "旋斩（异乡之舞第三下）"}
TIER = ["E0", "E1（+ 深海裂痕）", "E2（+ 暗影触须、海绿副刃）"]
BG = (34, 46, 52)
PX = 2          # 1 帧条像素 = 2 世界像素（游戏里同样整数放大）
SHOW = 2        # GIF 再放大 2 倍看得清
FONT = "C:/Windows/Fonts/msyh.ttc"


def strip(k):
    m = META.get(k)
    if not m:
        return None, None
    return Image.open(os.path.join(ART, "pxp_%s.png" % k)).convert("RGBA"), m


def frame(img, m, i):
    if img is None or i >= m["n"]:
        return None
    w, h = m["w"], m["h"]
    return img.crop((i * w, 0, i * w + w, h))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--moves", default="basic,s1")
    ap.add_argument("--dir", type=int, default=0)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    moves = a.moves.split(",")
    cw, ch = 210, 170                   # 每格（美术像素）
    ox, oy = 70, 110                    # 格内脚底位置
    op = Image.open(OP).convert("RGBA")
    ow = op.width // 8
    op0 = op.crop((0, 0, ow, op.height)).resize((ow // 2, op.height // 2), Image.NEAREST)   # @2x → 1 美术像素
    foot = (32, 60)
    nfr = 0
    cells = {}
    for mv in moves:
        for el in range(3):
            key = "spin_e%d" % el if mv == "spin" else "%s_e%d" % (mv, el)
            up, mu = strip(key + ("_up" if mv == "spin" else "_up_d%d" % a.dir))
            gd, mg = strip(key + ("_gd" if mv == "spin" else "_gd_d%d" % a.dir))
            cells[(mv, el)] = (up, mu, gd, mg)
            nfr = max(nfr, (mu or {}).get("n", 0), (mg or {}).get("n", 0))
    nfr += 4   # 停一下再循环
    fnt = ImageFont.truetype(FONT, 22) if os.path.exists(FONT) else ImageFont.load_default()
    head = 34
    W, H = cw * 3 * SHOW, (ch * SHOW + head) * len(moves) + head
    out = []
    for i in range(nfr):
        im = Image.new("RGB", (W, H), (14, 16, 20))
        d = ImageDraw.Draw(im)
        for c in range(3):
            d.text((c * cw * SHOW + 10, 6), TIER[c], fill=(235, 235, 235), font=fnt)
        for r, mv in enumerate(moves):
            y0 = head + r * (ch * SHOW + head)
            d.text((10, y0 + 4), NAME.get(mv, mv) + "（朝右出手；15 fps，2 倍）", fill=(200, 210, 220), font=fnt)
            for el in range(3):
                up, mu, gd, mg = cells[(mv, el)]
                cell = Image.new("RGBA", (cw, ch), BG + (255,))
                f = frame(gd, mg, i)
                if f is not None:
                    cell.alpha_composite(f, (ox - mg["ox"], oy - mg["oy"]))
                cell.alpha_composite(op0, (ox - foot[0], oy - foot[1]))
                f = frame(up, mu, i)
                if f is not None:
                    cell.alpha_composite(f, (ox - mu["ox"], oy - mu["oy"]))
                big = cell.resize((cw * SHOW, ch * SHOW), Image.NEAREST).convert("RGB")
                im.paste(big, (el * cw * SHOW, y0 + head))
        out.append(im)
    os.makedirs(os.path.dirname(a.out), exist_ok=True)
    out[0].save(a.out, save_all=True, append_images=out[1:], duration=int(1000 / 15), loop=0, optimize=True)
    print("GIF", a.out, nfr, "帧", "%.1f MB" % (os.path.getsize(a.out) / 1048576.0))


if __name__ == "__main__":
    main()
