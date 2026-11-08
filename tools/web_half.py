#!/usr/bin/env python3
"""网页包的半分辨率贴图（11-09 docs/319 §16）：只改导出副本，仓库与桌面包不动。

WASM / 显存里最大的几类贴图都是 @2x（2 倍像素密度）：
1. 整 2 倍放大的 @2x（每 2×2 一样的像素，特效 226 张、怪物 398 张）：减半是无损的 → 副本里直接换成 1 倍的基础名文件
   （删掉 @2x 与它的 .import，索引改指 1 倍文件）。所有平台的网页包都用它，画面完全一样，包更小，读图时也不用再解 2 倍的再缩
   （原来怪物在手机上是读 2 倍 → 读回像素 → 缩半，art.gd _halve）。
2. 有真 2 倍细节的特效 @2x（260 张）：另写一份 <名>@h.png（按预乘 alpha 的 2×2 平均缩半），索引记 <名>@h；
   只有手机网页读它（art.gd，--bal=web/mobile_fx_half=0 退回 @2x），电脑网页仍读 @2x。
3. 浊心斯卡蒂终结技的方向图集（ult_sd/*.png，每张解码 23–28 MB）：缩半写到 ult_sd_half/，手机网页读这份（run/ult_px_sd.gd）。
新 PNG 的 .import 照抄原图的 [params]（不写 uid / 路径，导入时 Godot 自己生成）。
用法：make(副本 game 目录) → 统计字典；report(字典) → 一行说明
"""
import json
import os

import numpy as np
from PIL import Image


def _rgba(p):
    return np.asarray(Image.open(p).convert("RGBA")).astype(np.float32)


def _exact2x(a):
    h, w = a.shape[:2]
    if w % 2 or h % 2:
        return False
    al = a[..., 3:4] / 255.0
    pm = a[..., :3] * al
    q, qa = pm[::2, ::2], al[::2, ::2]
    up = np.repeat(np.repeat(q, 2, 0), 2, 1)
    upa = np.repeat(np.repeat(qa, 2, 0), 2, 1)
    return np.abs(up - pm).max() < 1.0 and np.abs(upa - al).max() < 0.01


def _box_half(a):
    """预乘 alpha 的 2×2 平均（奇数边先补一行 / 列透明）：细线不会像取点那样整条消失，半透明边不发黑"""
    h, w = a.shape[:2]
    if w % 2 or h % 2:
        a = np.pad(a, ((0, h % 2), (0, w % 2), (0, 0)))
    al = a[..., 3:4] / 255.0
    pm = a[..., :3] * al
    s = lambda x: (x[0::2, 0::2] + x[1::2, 0::2] + x[0::2, 1::2] + x[1::2, 1::2]) / 4.0
    pa, aa = s(pm), s(al)
    rgb = np.where(aa > 1e-6, pa / np.maximum(aa, 1e-6), 0.0)
    out = np.concatenate([np.clip(rgb, 0, 255), np.clip(aa * 255.0, 0, 255)], axis=2)
    return out.round().astype(np.uint8)


def _write(arr, dst, src_import):
    Image.fromarray(arr.astype(np.uint8), "RGBA").save(dst, optimize=False, compress_level=6)
    params = ""
    if os.path.exists(src_import):
        txt = open(src_import, encoding="utf-8").read()
        i = txt.find("[params]")
        if i >= 0:
            params = txt[i:]
    with open(dst + ".import", "w", encoding="utf-8", newline="\n") as fh:
        fh.write('[remap]\n\nimporter="texture"\ntype="CompressedTexture2D"\n\n' + params)


def _rm(p):
    for q in (p, p + ".import"):
        if os.path.exists(q):
            os.remove(q)


def make(gamedir):
    ip = os.path.join(gamedir, "art", "index.json")
    idx = json.load(open(ip, encoding="utf-8"))
    r = {"exact": 0, "exact_mb": 0.0, "half": 0, "half_mb": 0.0, "sd": 0}
    for k in [k for k in idx if k.endswith("@2x")]:
        v = idx[k]
        cat = "fx" if v.startswith("res://art/fx/") else ("e" if v.startswith("res://art/enemies/") else "")
        p = os.path.join(gamedir, v[len("res://"):])
        if not cat or not os.path.exists(p) or not p.endswith("@2x.png"):
            continue
        base = k[:-3]
        a = _rgba(p)
        mb = a.shape[0] * a.shape[1] * 4 / 1048576
        if _exact2x(a):
            dst = p[:-len("@2x.png")] + ".png"
            if base in idx or os.path.exists(dst):
                continue   # 已有 1 倍文件（10 张旧怪物）：不动
            _write(a[::2, ::2].round().astype(np.uint8), dst, p + ".import")
            _rm(p)
            del idx[k]
            idx[base] = "res://" + os.path.relpath(dst, gamedir).replace(os.sep, "/")
            r["exact"] += 1
            r["exact_mb"] += mb
        elif cat == "fx":
            dst = p[:-len("@2x.png")] + "@h.png"
            _write(_box_half(a), dst, p + ".import")
            idx[base + "@h"] = "res://" + os.path.relpath(dst, gamedir).replace(os.sep, "/")
            r["half"] += 1
            r["half_mb"] += mb
    sd = os.path.join(gamedir, "art", "fx", "pxp", "ult_sd")
    if os.path.isdir(sd):
        out = sd + "_half"
        os.makedirs(out, exist_ok=True)
        for f in sorted(os.listdir(sd)):
            if f.endswith(".png"):
                _write(_box_half(_rgba(os.path.join(sd, f))), os.path.join(out, f), os.path.join(sd, f + ".import"))
                r["sd"] += 1
    with open(ip, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(idx, fh, ensure_ascii=False, separators=(",", ":"))
    return r


def report(r):
    return ("网页半分辨率贴图：整 2 倍放大的 %d 张换成 1 倍（解码后共 %.0f MB → %.0f MB）；有细节的特效 %d 张另出 @h 给手机（%.0f → %.0f MB）；"
            "斯卡蒂终结技图集 %d 张出半分辨率（docs/319 §16）" % (r["exact"], r["exact_mb"], r["exact_mb"] / 4, r["half"], r["half_mb"], r["half_mb"] / 4, r["sd"]))


if __name__ == "__main__":
    import sys
    print(report(make(sys.argv[1])))
