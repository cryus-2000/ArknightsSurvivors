#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""星熊精一「反击架势」刀光（docs/310 §4.2，卡面「刀光转为暗红」）：把盾斧斩立起层帧条的青绿色阶换成暗红色阶，另存 *_stance 键。
只换青绿（刀光）像素，钢灰（盾 / 碎石）与透明不动；白芯换成暖白。meta 复制原键，发光点改暖红。
用法（仓库根目录）：python tools/hsg_stance_recolor.py
"""
import json, os
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ART = os.path.join(ROOT, "game", "art", "fx", "pxp")
META = os.path.join(ROOT, "game", "data", "pxp_hoshiguma.json")
RED = [(26, 4, 6), (58, 8, 12), (98, 14, 18), (150, 24, 26), (204, 46, 38), (250, 120, 96), (255, 214, 196)]


def lum(c):
    return 0.3 * c[0] + 0.59 * c[1] + 0.11 * c[2]


def recolor(p):
    r, g, b, a = p
    if a == 0:
        return p
    if r == g == b == 255:
        return RED[6] + (a,)
    if g > r * 1.35 and b > r * 1.2:   # 青绿刀光
        l = lum(p) / 255.0
        x = min(5.999, max(0.0, l * 6.6))
        i = int(x)
        f = x - i
        c0, c1 = RED[i], RED[min(6, i + 1)]
        return tuple(int(c0[k] + (c1[k] - c0[k]) * f) for k in range(3)) + (a,)
    return p


def main():
    meta = json.load(open(META, encoding="utf-8"))
    n = 0
    for rr in (47, 56, 66):
        for t in (1, 2):
            for d in (-90, -45, 0, 45, 90):
                k = "hsg_sweep_r%d_e%d_up_d%d" % (rr, t, d)
                nk = "hsg_sweep_r%d_e%d_stance_up_d%d" % (rr, t, d)
                fk = k.replace("_d-", "_dm")
                src = os.path.join(ART, "pxp_%s.png" % fk)
                if k not in meta or not os.path.exists(src):
                    continue
                im = Image.open(src).convert("RGBA")
                im.putdata([recolor(p) for p in im.getdata()])
                im.save(os.path.join(ART, "pxp_%s.png" % nk.replace("_d-", "_dm")))
                m = json.loads(json.dumps(meta[k]))
                m["emit"] = [[[q[0], q[1], "ff7a5a"] for q in fr] for fr in m.get("emit", [])]
                meta[nk] = m
                n += 1
    json.dump(meta, open(META, "w", encoding="utf-8"), ensure_ascii=False, separators=(",", ":"))
    print("写了 %d 条" % n)


if __name__ == "__main__":
    main()
