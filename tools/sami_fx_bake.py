#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""萨米敌人攻击特效主形帧条烘焙（docs/401）：pixelfx 效果 tools/pixelfx_fx/foe/ak-sami-foe.js 按件导出，
色层 + 光层合成一张直通 alpha 的单行帧条（萨米雪地 / 黑烟底上光晕当颜色读），裁掉尾部空帧和四周空边，
输出 game/themes/sami/fx/sfx_<键>.png 与 game/themes/sami/fx/sami_fx.json（帧数、fps、帧尺寸、原点）。

需要本机 pixelfx 库（主仓库 build/pixelfx，同 tools/pxplane_bake.py）。用法（仓库根目录）：python tools/sami_fx_bake.py [--only 键前缀]
"""
import argparse, json, os, shutil, subprocess

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PFX = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(ROOT))) if ".claude" in ROOT else os.path.dirname(ROOT), "build", "pixelfx")
if not os.path.isdir(PFX):
    PFX = os.path.join(ROOT, "build", "pixelfx")
SRC = os.path.join(ROOT, "tools", "pixelfx_fx", "foe", "ak-sami-foe.js")
OUT = os.path.join(ROOT, "game", "themes", "sami", "fx")
TMP = os.path.join(ROOT, "build", "sami_fx_bake")

# 键 → (part, R 纹素, ramp, seed)。1 纹素 = 2 世界像素
PIECES = {
    "husk_hit": ("slash", 12, "steel", 1),      # 染污躯壳爪击命中（原作 smsbr_attack_01_hit）
    "caster_star": ("star", 9, "ice", 2),       # 歪曲施法者出手星闪（smwiz_attack_01_start_02）
    "caster_pop": ("pop", 9, "ice", 3),         # 法术弹命中（smwiz_attack_01_hit）
    "icebug_nova": ("nova", 28, "frost", 4),    # 冰爆源石虫死亡冰爆，r55 世界像素（snslime_die_01_start）
    "blade_charge": ("charge", 13, "blood", 5), # 利刃投刃蓄能（smgrd_attack_01_start）
    "blade_star": ("star", 16, "blood", 6),     # 利刃十字星（出手 / 国度爆发）
    "blade_slash": ("slash", 30, "blood", 7),   # 利刃斩击（smgrd_attack_02_hit），扇形 r100
    "blade_pop": ("pop", 13, "blood", 8),       # 刃片 / 投刃命中（smgrd_attack_01_hit）
}


def bake(key, part, R, ramp, seed):
    d = os.path.join(TMP, key)
    os.makedirs(d, exist_ok=True)
    opts = json.dumps({"part": part, "R": R, "ramp": ramp, "seed": seed})
    subprocess.run(["node", "tools/ak_layers.mjs", "foe/ak-sami-foe", "--out", d, "--opts", opts], cwd=PFX, check=True, capture_output=True)
    meta = json.load(open(os.path.join(d, "meta.json")))
    w, h = meta["frameSize"]
    n = meta["frames"]
    col = np.asarray(Image.open(os.path.join(d, "color.png")).convert("RGBA")).astype(np.float32) / 255.0
    lit = np.asarray(Image.open(os.path.join(d, "light.png")).convert("RGB")).astype(np.float32) / 255.0
    a = col[..., 3:4]
    prem = col[..., :3] * a + lit                      # 光层加色（预乘）
    la = np.clip(lit.max(axis=2, keepdims=True), 0, 1)
    A = np.clip(a + la * (1 - a), 0, 1)
    rgb = np.where(A > 1e-4, np.clip(prem / np.maximum(A, 1e-4), 0, 1), 0)
    img = np.concatenate([rgb, A], axis=2)
    frames = [img[:, i * w:(i + 1) * w] for i in range(n)]
    while frames and frames[-1][..., 3].max() < 0.02:
        frames.pop()
    # 统一裁边（所有帧并集），原点跟着平移
    alpha = np.max([f[..., 3] for f in frames], axis=0)
    ys, xs = np.where(alpha > 0.02)
    x0, x1, y0, y1 = max(0, xs.min() - 1), min(w, xs.max() + 2), max(0, ys.min() - 1), min(h, ys.max() + 2)
    frames = [f[y0:y1, x0:x1] for f in frames]
    strip = np.concatenate(frames, axis=1)
    Image.fromarray((strip * 255 + 0.5).astype(np.uint8), "RGBA").save(os.path.join(OUT, "sfx_%s.png" % key))
    ox, oy = meta["pivot"]
    return {"frames": len(frames), "fps": meta["fps"], "size": [int(x1 - x0), int(y1 - y0)], "origin": [int(ox - x0), int(oy - y0)], "part": part}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    a = ap.parse_args()
    os.makedirs(OUT, exist_ok=True)
    shutil.copy(SRC, os.path.join(PFX, "src", "fx", "foe", "ak-sami-foe.js"))
    mp = os.path.join(OUT, "sami_fx.json")
    meta = json.load(open(mp, encoding="utf-8")) if os.path.exists(mp) else {}
    meta["_doc"] = "萨米敌人攻击特效主形帧条（docs/401）：tools/sami_fx_bake.py 生成，勿手改。size / origin 单位是 1x 纹素（游戏里 ×2 = 世界像素）。"
    for k, (part, R, ramp, seed) in PIECES.items():
        if a.only and not k.startswith(a.only):
            continue
        meta[k] = bake(k, part, R, ramp, seed)
        print(k, meta[k])
    json.dump(meta, open(mp, "w", encoding="utf-8"), ensure_ascii=False, indent=1)


if __name__ == "__main__":
    main()
