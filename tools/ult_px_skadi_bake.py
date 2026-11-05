#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""斯卡蒂终结技转平面（docs/246 §16，开关 ult/px_plane）：pixelfx 效果 water/ak-skadi-ult-pp 按出手方向烤成帧图集。
  · 方向：平面角 -90…90 每 22.5° 一张（9 张），另一半水平翻转；
  · 每个方向一张图集 game/art/fx/pxp/ult_sd/sd_d<角>.png：招式 up / gd 两层逐帧（每帧按自身外框裁）+ 冲击帧剪影（爆点那一拍 up 层的白色剪影）；
  · 起手蓄力（与方向无关，朝左时翻转）：sd_charge.png；
  · 帧表 game/data/ult_px_skadi.json：{fps, ihf, charge: {up: [...], gd: [...]}, dirs: {"<角>": {up, gd, hf}}}，每帧 [x, y, w, h, ox, oy]（ox / oy = 脚底原点在帧内的位置）。
用法：python tools/ult_px_skadi_bake.py [--dirs -90,-67.5,…]
"""
import argparse, json, math, os, shutil, subprocess, sys, tempfile

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PFX = "E:/ArknightsSurvivors/build/pixelfx" if os.path.isdir("E:/ArknightsSurvivors/build/pixelfx") else os.path.join(os.path.dirname(ROOT), "pixelfx")
FX = "water/ak-skadi-ult-pp"
OUT_ART = os.path.join(ROOT, "game", "art", "fx", "pxp", "ult_sd")
OUT_META = os.path.join(ROOT, "game", "data", "ult_px_skadi.json")
FPS = 15
DIRS = [-90 + 22.5 * k for k in range(9)]
CHG_N = 8


def render(part, layer, d, tmp):
    for f in ("ak-skadi-ult-pp.js", "ak-skadi-pp.js"):
        shutil.copy(os.path.join(ROOT, "tools", "pixelfx_fx", "water", f), os.path.join(PFX, "src", "fx", "water", f))
    out = os.path.join(tmp, "%s_%s_%s" % (part, layer, d))
    o = {"part": part, "layer": layer, "dir": d}
    p = subprocess.run(["node", "tools/ak_layers.mjs", FX, "--out", out, "--fps", str(FPS), "--opts", json.dumps(o)], cwd=PFX, capture_output=True, text=True)
    if p.returncode != 0:
        sys.exit(p.stderr[-800:])
    m = json.load(open(os.path.join(out, "meta.json")))
    col = np.asarray(Image.open(os.path.join(out, "color.png")).convert("RGBA"))
    fw, fh = m["frameSize"]
    return [col[:, i * fw:(i + 1) * fw] for i in range(m["frames"])], m["pivot"]


def crash_index():
    tc = 0.15
    while True:
        k = min(1.0, (tc - 0.15) / 0.8)
        if -100 + 850 * k * (1.35 - 0.35 * k) >= 260:
            return int(math.ceil(tc * FPS))
        tc += 0.002


def trim(f, piv):
    a = f[..., 3]
    ys, xs = np.nonzero(a)
    if len(xs) == 0:
        return None, [0, 0, 0, 0, 0, 0]
    x0, x1, y0, y1 = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1
    return f[y0:y1, x0:x1], [0, 0, int(x1 - x0), int(y1 - y0), int(piv[0] - x0), int(piv[1] - y0)]


def pack(items, width=4096):
    """items: [(key, i, img)] → 图集 + 位置（按高度排的货架装箱）"""
    order = sorted(range(len(items)), key=lambda j: -items[j][2].shape[0])
    x = y = rowh = 0
    pos = {}
    for j in order:
        h, w = items[j][2].shape[:2]
        if x + w > width:
            x, y, rowh = 0, y + rowh + 1, 0
        pos[j] = (x, y)
        x += w + 1
        rowh = max(rowh, h)
    H = y + rowh
    atlas = np.zeros((H, width, 4), np.uint8)
    for j, (x, y) in pos.items():
        img = items[j][2]
        atlas[y:y + img.shape[0], x:x + img.shape[1]] = img
    used = max(x + items[j][2].shape[1] for j, (x, y) in pos.items())
    return atlas[:, :used], pos


def bake_set(name, layers, tmp):
    """layers: {"up": (frames, piv), "gd": ..., "hf": ...} → 写图集，返回帧表"""
    items, rects = [], {}
    for ly, (frames, piv) in layers.items():
        rects[ly] = []
        for i, f in enumerate(frames):
            img, r = trim(f, piv)
            rects[ly].append(r)
            if img is not None:
                items.append((ly, i, img))
    atlas, pos = pack(items)
    for j, (ly, i, img) in enumerate(items):
        rects[ly][i][0], rects[ly][i][1] = pos[j]
    Image.fromarray(atlas, "RGBA").save(os.path.join(OUT_ART, name + ".png"), optimize=True)
    return rects, atlas.shape


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dirs", default=",".join("%g" % d for d in DIRS))
    a = ap.parse_args()
    os.makedirs(OUT_ART, exist_ok=True)
    tmp = tempfile.mkdtemp(prefix="ultsd_")
    ihf = crash_index()
    meta = json.load(open(OUT_META, encoding="utf-8")) if os.path.exists(OUT_META) else {}
    meta.update({"fps": FPS, "ihf": ihf, "dirs": meta.get("dirs", {})})
    cu, piv = render("charge", "up", 0, tmp)
    cg, _ = render("charge", "gd", 0, tmp)
    meta["charge"], shp = bake_set("sd_charge", {"up": (cu[:CHG_N], piv), "gd": (cg[:CHG_N], piv)}, tmp)
    print("charge", shp)
    tot = 0
    for d in [float(x) for x in a.dirs.split(",")]:
        uu, piv = render("ult", "up", d, tmp)
        ug, _ = render("ult", "gd", d, tmp)
        n = len(uu)
        while n > 1 and uu[n - 1][..., 3].max() == 0 and ug[n - 1][..., 3].max() == 0:
            n -= 1
        hf = uu[ihf].copy()
        m = hf[..., 3] > 128
        hf[...] = 0
        hf[m] = [255, 255, 255, 255]
        key = "%g" % d
        rects, shp = bake_set("sd_d%s" % key.replace("-", "m").replace(".", "_"), {"up": (uu[:n], piv), "gd": (ug[:n], piv), "hf": ([hf], piv)}, tmp)
        meta["dirs"][key] = rects
        sz = os.path.getsize(os.path.join(OUT_ART, "sd_d%s.png" % key.replace("-", "m").replace(".", "_")))
        tot += sz
        print("dir %6s  %d 帧  图集 %dx%d  %.0f KB" % (key, n, shp[1], shp[0], sz / 1024), flush=True)
    json.dump(meta, open(OUT_META, "w", encoding="utf-8"), separators=(",", ":"))
    print("ihf", ihf, "合计 %.1f MB" % (tot / 1048576))


if __name__ == "__main__":
    main()
