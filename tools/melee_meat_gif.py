#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""卡肉节奏示意 GIF（11-05 用户「我用德克萨斯打，没有卡肉感」；render/melee_impact.meat）：只用 Python，不开 Godot。
左：现在（德克萨斯没接打击感包——刀痕一路扫过、怪只闪 0.06 秒）；右：卡肉（命中那一刻本体、被砍的怪停 70 ms，怪白闪；
刀痕在命中那一拍多停一拍再扫出去；停完怪被往后推 8 世界像素再弹回）。60 fps 时间轴，GIF 按 30 fps、慢放 2 倍放，3 倍放大。
用法：python tools/melee_meat_gif.py [--out 目录] [--hold_ms 70] [--slow 2]
"""
import argparse, json, math, os

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAIN = os.path.dirname(os.path.dirname(os.path.dirname(ROOT))) if ".claude" in ROOT else ROOT
FONT = "C:/Windows/Fonts/msyh.ttc"
M = json.load(open(os.path.join(ROOT, "game", "data", "pxp_texas.json"), encoding="utf-8"))


def strip(k, f):
    m = M[k]
    if f < 0 or f >= m["n"]:
        return None, m
    im = Image.open(os.path.join(ROOT, "game", "art", "fx", "pxp", "pxp_%s.png" % k)).convert("RGBA")
    return im.crop((f * m["w"], 0, (f + 1) * m["w"], m["h"])).resize((m["w"] * 2, m["h"] * 2), Image.NEAREST), m


def sprite(path, n, fi):
    im = Image.open(path).convert("RGBA")
    fw = im.width // n
    return im.crop((fi * fw, 0, (fi + 1) * fw, im.height))


def scene(t, meat, hold, tx_frames, en):
    """t：命中后秒数（< 0 = 命中前）。返回 1 倍画面（世界像素）"""
    W, H = 300, 170
    img = Image.new("RGBA", (W, H), (34, 44, 50, 255))
    d = ImageDraw.Draw(img)
    me = (88, 120)
    ep = (178, 118)
    # 时间：卡肉时命中后 hold 秒内世界里的这一招停住（本体、怪、刀痕第 1 帧）
    held = meat and 0 <= t < hold
    te = t if not meat or t < 0 else (0.0 if t < hold else t - hold)   # 这一招自己的时间
    # 刀痕帧：命中在第 1 拍；卡肉时第 1 拍多停一拍
    beat = math.floor((te + 1 / 15) * 15) if te >= -1 / 15 else -1
    if meat and t >= 0 and beat >= 2:
        beat = math.floor((te + 1 / 15) * 15 - 1) if te >= 1 / 15 else 1
        beat = max(1, beat)
    # 怪：推开（停完以后）
    off = 0.0
    if t >= 0:
        age = t - (hold if meat else 0.0)
        ti, tb, px = (0.027, 0.08, 8.0) if meat else (0.0, 0.0, 0.0)
        if meat and 0 <= age < ti + tb:
            off = px * (age / ti if age < ti else 1 - (age - ti) / tb)
    flash = (0 <= t < (hold + 0.04 if meat else 0.06))
    e = en.copy()
    if flash:
        a = np.asarray(e).copy()
        a[..., :3] = np.where(a[..., 3:4] > 0, 255 if meat else np.array([255, 190, 110]), a[..., :3])
        e = Image.fromarray(a)
    ex = int(ep[0] + round(off / 2) * 2)
    d.ellipse([ex - 12, ep[1] - 3, ex + 12, ep[1] + 4], fill=(16, 20, 22, 255))
    img.alpha_composite(e, (ex - e.width // 2, ep[1] - e.height + 6))
    # 本体：出手帧（命中 = 第 3 帧）；卡肉时停住
    fi = 3 if held else min(7, max(0, 3 + int(math.floor(te * 22.4))))
    tx = tx_frames[fi]
    img.alpha_composite(tx, (me[0] - tx.width // 2, me[1] - tx.height + 16))
    if beat >= 0:
        for k in ("tx_slash_r56_e2_gd_d0", "tx_slash_r56_e2_up_d0"):
            s, m = strip(k, beat)
            if s is not None:
                img.alpha_composite(s, (me[0] - m["ox"] * 2, me[1] - m["oy"] * 2))
    return img


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join(MAIN, "Claude outputs", "texas_meat_1105"))
    ap.add_argument("--hold_ms", type=float, default=70.0)
    ap.add_argument("--slow", type=float, default=2.0)
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    hold = a.hold_ms / 1000.0
    od = os.path.join(ROOT, "game", "art", "operators", "texas", "op_texas_attack@2x.png")
    txf = [sprite(od, 8, i) for i in range(8)]
    en = sprite(os.path.join(ROOT, "game", "art", "enemies", "offspring", "e_offspring@2x.png"), 4, 0)
    font = ImageFont.truetype(FONT, 16)
    frames = []
    t = -0.1
    while t < 0.5:
        L = scene(t, False, hold, txf, en).resize((900, 510), Image.NEAREST)
        Rr = scene(t, True, hold, txf, en).resize((900, 510), Image.NEAREST)
        sh = Image.new("RGB", (1808, 600), (12, 12, 16))
        sh.paste(L, (0, 60))
        sh.paste(Rr, (908, 60))
        dd = ImageDraw.Draw(sh)
        dd.text((10, 6), "现在：德克萨斯没接打击感包（刀痕一路扫过、怪只闪 0.06 秒）", fill=(230, 230, 230), font=font)
        dd.text((918, 6), "卡肉：命中停 %d ms（本体 / 被砍的怪 / 刀痕命中那一拍），怪先白闪、停完再推开 8 px" % a.hold_ms, fill=(255, 220, 160), font=font)
        dd.text((10, 32), "命中后 %+4.0f ms（60 fps 时间轴，GIF 慢放 %.0f 倍、3 倍放大）" % (t * 1000, a.slow), fill=(170, 170, 170), font=font)
        if 0 <= t < hold:
            dd.rectangle([918, 32, 1100, 54], fill=(120, 60, 20))
            dd.text((924, 32), "停住（卡在肉里）", fill=(255, 255, 255), font=font)
        frames.append(sh)
        t += 1 / 60
    pal = frames[len(frames) // 3].quantize(colors=200, method=Image.MEDIANCUT)
    q = [f.quantize(palette=pal, dither=Image.NONE) for f in frames]
    dur = int(1000 / 60 * a.slow)
    path = os.path.join(a.out, "texas_meat_rhythm.gif")
    q[0].save(path, save_all=True, append_images=q[1:], duration=dur, loop=0, disposal=1)
    print(path, len(q), "帧", "%.0f KB" % (os.path.getsize(path) / 1024))


if __name__ == "__main__":
    main()
