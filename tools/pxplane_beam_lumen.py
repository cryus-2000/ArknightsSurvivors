#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""流明「灯塔守望」光束重做（docs/255 §6，11-05 用户「流明那个光束得重新做一下」）的出图：只拍这一招。

图鉴演示（tests/elite_demo_shot.tscn），路线 --route=lumen:watch：
  E1：成长节点 4 个（发光单元 ×2 → 精一 → 灯塔守望；同用户那局），S1 沐雨后光束转 3 秒；
  E2：节点全开（含回光），S1 后光束 + S3 灯火不灭期间从灯塔射出的光束。
每组三种画法（0 当前游戏 / 2 旧放开版原样贴 / 1 转平面）同一演示同一帧号，拼三栏 + 2 倍局部；另拼两档并排（只转平面版）。
Godot 只经 godot_runner.run_godot 启动（本机 / GCP 都一样），一次只开 1 个。

用法：python tools/pxplane_beam_lumen.py --out <目录>
"""
import argparse, os, sys

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pxplane_shots_lumen as S

SETS = [  # (标签, 档, 演示模式, 节点数, 起手后取帧偏移（引擎帧，含约 9 帧启动差）)
    ("e1", 1, 0, 4, 9 + 30),
    ("e2", 2, 0, -1, 9 + 30),
    ("e2s3", 2, 2, -1, 9 + 60),
]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--every", type=int, default=2)
    ap.add_argument("--n", type=int, default=90)
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    S.OP = "lumen"
    S.MODE_NAME.clear()
    S.MODE_NAME.update(S.OPS["lumen"][1])
    S.BALS[:] = ["growth/late_shape=1"]
    rows = []
    for tag, tier, mode, nodes, off in SETS:
        start = 1.2 if mode == 2 else 2.0
        ex = ["--route=lumen:watch"] + (["--shot_nodes=%d" % nodes] if nodes >= 0 else [])
        fr, ev = {}, []
        for px, _ in S.COLS:
            t_, frames, errs, e = S.shoot(px, tier, mode, start, a.every, a.n, extra=ex, suffix="_beam_" + tag)
            print(t_, len(frames), "帧", errs[:2], flush=True)
            fr[px] = frames
            if px == 1:
                ev = e
        n = min(len(v) for v in fr.values())
        if n == 0:
            continue
        key = "skill%d" % mode
        evs = [int(x[3]) for x in ev if len(x) > 3 and x[2] == key and x[3].isdigit()]
        cand = [(fe + off - int(start * 30)) // a.every for fe in evs]
        cand = [k for k in cand if 0 <= k < n]
        k = cand[0] if cand else n // 2
        title = "流明 灯塔守望光束（重做）· %s · 同一帧（演示第 %d 张）" % ({"e1": "精英 1（S1 后 3 秒）", "e2": "精英 2（S1 后 3 秒）", "e2s3": "精英 2（S3 灯塔在场）"}[tag], k)
        ims, x0, y0, cw, ch, W, H = S.sheet3(fr, k, "cmp_beam_" + tag, title, a.out)
        idx = [max(0, min(n - 1, k + d)) for d in (-6, -3, 0, 3, 6)]
        box = (max(0, x0 - 200), max(0, y0 - 120), min(W, x0 + cw + 200), min(H, y0 + ch + 120))
        rows.append((tag, [Image.open(fr[1][j]).convert("RGB").crop(box) for j in idx]))
        print("三栏", tag, "帧", k, flush=True)
    if rows:
        rw, rh = rows[0][1][0].size
        sheet = Image.new("RGB", (130 + rw * 5 + 16, 56 + (rh + 8) * len(rows)), (12, 12, 16))
        dd = ImageDraw.Draw(sheet)
        dd.text((12, 8), "转平面版 · 流明 灯塔守望光束（重做）· 每行一档，光束转动中隔 0.2 秒一张", fill=(230, 230, 230), font=S.font(30))
        for r, (tag, row) in enumerate(rows):
            y = 56 + r * (rh + 8)
            dd.text((12, y + rh // 2 - 18), {"e1": "E1", "e2": "E2", "e2s3": "E2·S3"}[tag], fill=(255, 255, 255), font=S.font(30))
            for j, im in enumerate(row):
                sheet.paste(im.resize((rw, rh)), (130 + j * (rw + 4), y))
        sheet.save(os.path.join(a.out, "tiers_beam.png"))


if __name__ == "__main__":
    main()
