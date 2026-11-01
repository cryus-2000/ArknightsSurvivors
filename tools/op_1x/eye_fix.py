# -*- coding: utf-8 -*-
"""1 倍帧条瞳色保护（docs/87 §4.3「瞳色单独保留」，docs/214 A1）。

1 倍帧条（make_op_1x：Spine 1 倍像素化 / @2x 2×2 合并）在 48 像素级会把眼睛并进脸和头发：铃兰绿瞳、德克萨斯橙瞳看不见，
拉普兰德 / 艾丽妮 / 推进之王只剩暗点。这里只改眼睛像素，头脸轮廓和其他颜色一律不动：
  1. 眼位：avatar_eyes.json 的双眼中点与眼距（@2x 待机首帧坐标）折半到 1 倍；两只眼的瞳孔格 = 眼中心 ±1 像素里最暗的那格。
  2. 逐帧跟踪：取 1 倍待机首帧眼部一小块（11×7）作模板，在每条帧条的每一帧里找最像的位置；分数好的帧定出这条帧条里脸的位置，
     其余帧位置对得上、差得不太多才改，转头 / 闭眼 / 遮住的帧不改。
  3. 改色：匹配上的帧，瞳孔格换成 IRIS 里本人的虹膜色（只改不透明、且比虹膜色更暗或同色系的格子，避免把皮肤 / 头发涂上颜色）。
虹膜色：@2x 里看得清的直接取 @2x，@2x 也发灰的取 PRTS 战斗小人待机帧（build/prts_ref/<id>/idle_f00.png）里眼部同色系像素中位数。
没登记在 IRIS 里的干员不处理（1 倍上眼睛本来就清楚，或侧脸只露一只眼）。

    python -X utf8 tools/op_1x/eye_fix.py [--only suzuran,texas] [--dry] [--report build/op_1x/eyes]
make_op_1x.py 出完每名干员后也调 fix_op（重出 1 倍时不丢）。重复跑结果不变。
"""
import argparse
import json
import os
import sys

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import asset_paths

CHARS = os.path.join(ROOT, "game", "data", "characters")
EYES = os.path.join(ROOT, "game", "art", "operators", "avatar_eyes.json")

# 虹膜色（RGB）。出处见上：suzuran / texas / irene / lappland / siege / kaltsit 取 PRTS 战斗小人眼部
IRIS = {
    "suzuran": (92, 107, 43),     # 绿（PRTS 小人眼部绿 #5c6b2b）
    "texas": (239, 148, 98),      # 橙（#ef9462）
    "irene": (164, 113, 134),     # 浅灰紫（#a47186）
    "lappland": (92, 92, 81),     # 灰（PRTS #90907f 压到 0.64 明度：原色在她的白脸 / 白发上比黑瞳孔还难看出）
    "siege": (163, 119, 71),      # 琥珀（#a37747）
    "kaltsit": (110, 116, 37),    # 黄绿（#6e7425）
}
# 两个瞳孔格相对模板左上角的偏移（11-01 用未改过的 1 倍待机首帧按「眼中心 ±1 格里最暗那格」量出后写死：
# 改过色之后再量会挪到别的格子，重复跑就不幂等了；待机帧条重出、脸挪了位置时用 --measure 重量）
PUPIL = {
    "irene": [(4, 2), (8, 2)], "kaltsit": [(3, 2), (7, 2)], "lappland": [(3, 2), (8, 2)],
    "siege": [(1, 2), (6, 2)], "suzuran": [(4, 2), (8, 2)], "texas": [(3, 2), (8, 3)],
}
TW, TH = 11, 7        # 模板大小（1 倍像素）
THR = 30.0            # 模板平均色差（0–255）：一条帧条里至少有一帧在这以内才处理这条，并用这些帧定脸的位置
THR2 = 50.0           # 其余帧：位置在上面定出的 ±3 格内、色差在这以内就改；再差就当转头 / 闭眼 / 遮住，不改


def _sprites(op):
    d = json.load(open(os.path.join(CHARS, op + ".json"), encoding="utf-8"))
    return d.get("sprites", {})


def _strips(op):
    """[(tex, 帧数)]：本人所有带 @1x 的帧条，去重"""
    out, seen = [], set()
    for v in _sprites(op).values():
        if isinstance(v, dict) and isinstance(v.get("tex"), str) and v["tex"] not in seen and v.get("frames"):
            if asset_paths.runtime_png(v["tex"] + "@1x"):
                seen.add(v["tex"])
                out.append((v["tex"], int(v["frames"])))
    return out


def _eye_setup(op, idle):
    """(模板, 模板左上角, 两个瞳孔格相对模板左上角的偏移)"""
    e = json.load(open(EYES, encoding="utf-8"))["ops"][op]
    k = idle.shape[0] / float(e["fh"])
    mx, my = e["eye"][0] * k, e["eye"][1] * k
    half = e["d"] * k / 2.0
    pts = []
    for cx in (mx - half, mx + half):
        best = None
        for y in range(int(round(my)) - 1, int(round(my)) + 2):
            for x in range(int(round(cx)) - 1, int(round(cx)) + 2):
                p = idle[y, x]
                if p[3] == 0:
                    continue
                lum = 0.3 * p[0] + 0.59 * p[1] + 0.11 * p[2]
                if best is None or lum < best[0]:
                    best = (lum, x, y)
        if best is not None:
            pts.append((best[1], best[2]))
    x0, y0 = int(round(mx)) - TW // 2, int(round(my)) - TH // 2
    tpl = idle[y0:y0 + TH, x0:x0 + TW].astype(float)
    return tpl, (x0, y0), [(x - x0, y - y0) for x, y in pts]


def _match(fr, tpl, skip=(), iris=None):
    """模板在帧里最像的位置 (x, y, 平均色差)；skip = 不参与比较的模板格（瞳孔格），帧里已经是虹膜色的格子也不比
    （改过色后再跑，匹配位置和第一遍一样，结果不变）"""
    m = tpl[..., 3] > 0
    for dx, dy in skip:
        m[dy, dx] = False
    if not m.any():
        return None
    best = None
    h, w = fr.shape[:2]
    f = fr.astype(float)
    for y in range(0, h - TH + 1):
        for x in range(0, w - TW + 1):
            c = f[y:y + TH, x:x + TW]
            d = np.abs(c[..., :3] - tpl[..., :3]).mean(axis=2)
            d = np.where(c[..., 3] > 0, d, 255.0)
            mm = m & ~np.all(c[..., :3] == iris, axis=2) if iris is not None else m
            if not mm.any():
                continue
            s = float(d[mm].mean())
            if best is None or s < best[2]:
                best = (x, y, s)
    return best


def _paint_ok(p, iris):
    """只改不透明、亮度不高于虹膜色太多的格子（瞳孔 / 睫毛 / 已经是虹膜色），不碰皮肤和高光"""
    if p[3] == 0:
        return False
    lum = 0.3 * p[0] + 0.59 * p[1] + 0.11 * p[2]
    il = 0.3 * iris[0] + 0.59 * iris[1] + 0.11 * iris[2]
    return lum <= max(il + 12, 135.0)   # 135：比所有人的皮肤 / 高光都暗，瞳孔灰格（拉普兰德 117）也能改


def fix_op(op, dry=False):
    """跑到不再变化为止（最多 4 遍：改过色的格子不参与匹配，个别帧第二遍会落到相邻一格，第三遍收敛）。
    返回第一遍的 [(tex, 改了的帧数, 改了的像素数)]"""
    first = _pass(op, dry)
    if not dry:
        for _ in range(3):
            if not any(x[2] for x in _pass(op, False)):
                break
    return first


def _pass(op, dry):
    if op not in IRIS:
        return []
    iris = IRIS[op]
    sp = _sprites(op)
    idle_tex = sp["idle"]["tex"]
    idle_n = int(sp["idle"]["frames"])
    idle_img = np.asarray(Image.open(asset_paths.runtime_png(idle_tex + "@1x")).convert("RGBA"))
    fw0 = idle_img.shape[1] // idle_n
    tpl, _, pts = _eye_setup(op, idle_img[:, :fw0].copy())
    pts = PUPIL.get(op, pts)
    res = []
    for tex, n in _strips(op):
        path = asset_paths.runtime_png(tex + "@1x")
        img = np.asarray(Image.open(path).convert("RGBA")).copy()
        if img.shape[0] != idle_img.shape[0] or img.shape[1] % n:
            continue
        fw = img.shape[1] // n
        nf = npx = 0
        mts = [_match(img[:, i * fw:(i + 1) * fw], tpl, pts, iris) for i in range(n)]
        good = [m for m in mts if m is not None and m[2] <= THR]
        if not good:   # 没有一帧很像（拉普兰德跑步整条阴影都不同）：过半帧在 THR2 内且位置互相差不超过 1 格，也认这张脸
            ok = [m for m in mts if m is not None and m[2] <= THR2]
            if len(ok) * 2 >= n:
                mx0, my0 = np.median([m[0] for m in ok]), np.median([m[1] for m in ok])
                if all(abs(m[0] - mx0) <= 1 and abs(m[1] - my0) <= 1 for m in ok):
                    good = ok
        if not good:
            res.append((tex, 0, 0))
            continue
        ax = float(np.median([m[0] for m in good]))
        ay = float(np.median([m[1] for m in good]))
        for i in range(n):
            fr = img[:, i * fw:(i + 1) * fw]
            mt = mts[i]
            # 同一条帧条里脸的位置只随起伏挪一两格：分数好的帧定出位置，其余帧落在 ±3 格内、分数 ≤ THR2 就算同一张脸（跑步帧阴影变化大，分数偏高）
            if mt is None or mt[2] > THR2 or abs(mt[0] - ax) > 3 or abs(mt[1] - ay) > 3:
                continue
            hit = 0
            for dx, dy in pts:
                x, y = mt[0] + dx, mt[1] + dy
                if 0 <= x < fw and 0 <= y < fr.shape[0] and _paint_ok(fr[y, x], iris):
                    if tuple(fr[y, x, :3]) != iris:
                        fr[y, x, :3] = iris
                        npx += 1
                    hit += 1
            nf += 1 if hit else 0
        if npx and not dry:
            Image.fromarray(img).save(path)
        res.append((tex, nf, npx))
    return res


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    ap.add_argument("--dry", action="store_true")
    ap.add_argument("--measure", action="store_true", help="只打印按当前待机首帧量出的瞳孔格偏移（填 PUPIL 用），不改图")
    a = ap.parse_args()
    ops = sorted(IRIS) if not a.only else [o for o in a.only.split(",") if o in IRIS]
    if a.measure:
        for op in ops:
            sp = _sprites(op)
            idle = np.asarray(Image.open(asset_paths.runtime_png(sp["idle"]["tex"] + "@1x")).convert("RGBA"))
            print(op, _eye_setup(op, idle[:, :idle.shape[1] // int(sp["idle"]["frames"])].copy())[2])
        return
    for op in ops:
        r = fix_op(op, a.dry)
        print(op, "；".join("%s 帧 %d 像素 %d" % x for x in r if x[2] or x[1]))


if __name__ == "__main__":
    main()
