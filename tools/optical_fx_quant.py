"""光学观感 · 特效帧条压阶（10-23 用户定特效处理第 1 步 ①，docs/50 §25）：导入时离线处理，游戏里光学观感开着时换用。
干员技能 / 通用命中 / 我方弹体的 fx_* / proj_* 帧条：半透明与软边渐变压成 3 阶 alpha（0 / 中 / 255），
每个色相组的明度压成 3 阶（1D k-means，整条帧条共用一组色阶，逐帧不跳）；按原 RGB 比例缩放，色相与饱和度不变，形状（不透明覆盖）不变。
敌方特效（统一走危险色语言，另做）与寻访界面（hh_）不处理。

    python -X utf8 tools/optical_fx_quant.py            # 生成 art/incoming/optical_fx/*.png + index.json
    python -X utf8 tools/optical_fx_quant.py --check    # 只统计不写

运行时：render/optical.gd 按 index.json 把 g.tex 里同名贴图换成 optical_fx/<名>（关掉时换回）；@2x 与原图同名同密度。
"""
import glob
import json
import os
import sys

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
INC = os.path.join(ROOT, "art", "incoming")
OUT = os.path.join(INC, "optical_fx")
A_LOW, A_HIGH, A_MID = 0.12, 0.6, 140      # alpha 阈值（0–1）与中间阶的值（0–255）
LEVELS = 3
# 掏空成描边的帧（10-23 特效处理 ④：我方原作红保留，但不出现与敌方预警同形的「地面整块红色填充」）：帧条名 → 帧号
# 维什戴尔炮击：第 0 帧落点红盘标记、第 3 帧地面红色旋涡盘
HOLLOW = {"fx_wisadel_cannon": [0, 3]}
EDGE_PX = 2   # 描边宽（按 1x 美术像素；@2x 帧条 ×2）
ENEMY_WORDS = ["acid", "brood", "mother", "spitter", "nest", "skimmer", "pocket", "mire", "corrode", "knight", "tide", "tear", "mimic",
               "slider", "reaper", "founder", "tracer", "fractal", "paranoia", "ishar", "izumik", "path", "saint", "bishop", "archon",
               "immortal", "kraken", "floater", "boss", "seaborn", "rock", "lava", "nova", "drone", "fireball", "missile", "lavaball"]


def wanted(base: str) -> bool:
    b = base.split("_", 1)[1] if "_" in base else base
    if b.startswith("hh"):
        return False   # 寻访界面
    return not any(b.startswith(w) for w in ENEMY_WORDS)


def kmeans1d(v: np.ndarray, k: int) -> np.ndarray:
    c = np.quantile(v, np.linspace(0.15, 0.9, k))
    for _ in range(10):
        lab = np.argmin(np.abs(v[:, None] - c[None, :]), axis=1)
        for i in range(k):
            m = lab == i
            if m.any():
                c[i] = v[m].mean()
    return c


def quant(img: Image.Image) -> Image.Image:
    a = np.asarray(img.convert("RGBA")).astype(np.float32)
    rgb, al = a[..., :3], a[..., 3] / 255.0
    out_a = np.where(al < A_LOW, 0.0, np.where(al < A_HIGH, A_MID, 255.0))
    vis = out_a > 0
    mx = rgb.max(axis=2)
    mn = rgb.min(axis=2)
    d = mx - mn
    s = np.where(mx > 0, d / np.maximum(mx, 1e-6), 0.0)
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    h = np.zeros_like(mx)
    m = d > 1e-6
    hr = np.where(mx == r, ((g - b) / np.maximum(d, 1e-6)) % 6, 0)
    hg = np.where(mx == g, (b - r) / np.maximum(d, 1e-6) + 2, 0)
    hb = np.where(mx == b, (r - g) / np.maximum(d, 1e-6) + 4, 0)
    h = np.where(mx == r, hr, np.where(mx == g, hg, hb)) / 6.0
    h = np.where(m, h % 1.0, 0.0)
    grp = np.where(s > 0.15, (h * 12).astype(int) % 12, 12)   # 12 个色相组 + 灰组
    newv = mx.copy()
    for gi in range(13):
        sel = vis & (grp == gi) & (mx > 0)
        n = int(sel.sum())
        if n < 12:
            continue
        v = mx[sel]
        c = kmeans1d(v, LEVELS if n >= 40 else 2)
        newv[sel] = c[np.argmin(np.abs(v[:, None] - c[None, :]), axis=1)]
    k = np.where(mx > 0, newv / np.maximum(mx, 1e-6), 1.0)
    o = np.clip(rgb * k[..., None], 0, 255)
    res = np.dstack([o, out_a]).astype(np.uint8)
    res[~vis] = 0
    return Image.fromarray(res, "RGBA")


def hollow(img: Image.Image, frames: int, which: list, edge: int) -> Image.Image:
    a = np.asarray(img).copy()
    fw = a.shape[1] // frames
    for fi in which:
        sl = a[:, fi * fw:(fi + 1) * fw]
        op = sl[..., 3] > 0
        inner = op.copy()
        for dy in range(-edge, edge + 1):
            for dx in range(-edge, edge + 1):
                inner &= np.roll(np.roll(op, dy, axis=0), dx, axis=1)
        sl[inner] = 0
    return Image.fromarray(a, "RGBA")


def frames_of(base: str) -> int:
    src = open(os.path.join(ROOT, "game", "scripts", "art.gd"), encoding="utf-8").read()
    import re
    m = re.search(r'"%s": \[(\d+),' % re.escape(base), src)
    return int(m.group(1)) if m else 1


def main():
    check = "--check" in sys.argv
    files = []
    for p in sorted(glob.glob(os.path.join(INC, "fx_*.png")) + glob.glob(os.path.join(INC, "proj_*.png"))):
        fn = os.path.basename(p)
        base = fn[:-4].replace("@2x", "")
        if not wanted(base):
            continue
        files.append((base, fn, p))
    names = sorted({b for b, _, _ in files})
    if check:
        print(len(names), "条，", len(files), "个文件")
        return
    os.makedirs(OUT, exist_ok=True)
    tot_in = tot_out = 0
    for base, fn, p in files:
        q = quant(Image.open(p))
        if base in HOLLOW:
            q = hollow(q, frames_of(base), HOLLOW[base], EDGE_PX * (2 if "@2x" in fn else 1))
        dst = os.path.join(OUT, fn)
        q.save(dst, optimize=True)
        tot_in += os.path.getsize(p)
        tot_out += os.path.getsize(dst)
    with open(os.path.join(OUT, "index.json"), "w", encoding="utf-8") as f:
        json.dump({"doc": "tools/optical_fx_quant.py 生成，勿手改", "names": names}, f, ensure_ascii=False, indent=0)
    print("%d 条 / %d 文件；原 %.2f MB → 压阶 %.2f MB" % (len(names), len(files), tot_in / 1e6, tot_out / 1e6))


if __name__ == "__main__":
    main()
