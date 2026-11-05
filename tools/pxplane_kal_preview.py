#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""凯尔希转平面实机预览（docs/265；协调人 11-05：上 GCP 出一组图鉴演示截图，只出各招 E2，不出录像、不跑 TRACE，看实机光感）。

图鉴演示（tests/elite_demo_shot.tscn）精二、fx/px_plane = 1、growth/late_shape = 1，每招连拍一段，拼成：
  kal_e2_<招>.png      12 格联系表（等间隔取帧，1280×720 缩到一半）
  kal_e2_<招>_best.png  最「亮」的一帧原尺寸（暖色 / 荧光绿像素最多的那张，看照地光和发光）
招：atk（普攻：爪击 + 治疗）、s1（结构加固，缺省路线）、s1_rebuild（S1 分支「不毁重构」，--route=kaltsit:melt）、s2、s3（含结束熔毁爆）。
用法（GCP）：python tools/gcp_render.py --branch <分支> --job custom --cmd 'python3 tools/pxplane_kal_preview.py --out $MEDIA'
"""
import argparse, glob, os, shutil, sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import godot_runner as GR

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GAME = os.path.join(ROOT, "game")
BUILD = os.path.join(ROOT, "build", "pxplane_kal")
# 招 → (演示模式, 起拍秒, 隔几帧, 张数, 另加参数, 标题)
MOVES = {
    "atk": (3, 1.5, 3, 60, [], "普攻（Mon3tr 爪击 + 治疗）"),
    "s1": (0, 1.0, 2, 45, [], "S1 结构加固"),
    "s1_rebuild": (0, 1.0, 2, 45, ["--route=kaltsit:melt"], "S1 分支「不毁重构」"),
    "s2": (1, 1.0, 2, 45, [], "S2 战术协同"),
    "s3": (2, 1.0, 3, 110, [], "S3 熔毁（含结束熔毁爆）"),
    "s3end": (2, 8.5, 1, 75, [], "S3 收尾熔毁爆（逐帧连拍，镜头拉近）"),
}
FONTS = ["C:/Windows/Fonts/msyh.ttc", "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc", "/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc"]


def font(sz):
    for f in FONTS:
        if os.path.exists(f):
            return ImageFont.truetype(f, sz)
    return ImageFont.load_default()


def shoot(key, mode, start, every, n, extra):
    fdir = os.path.join(BUILD, key)
    shutil.rmtree(fdir, ignore_errors=True)
    os.makedirs(fdir)
    args = [GR.find_godot(), "--audio-driver", "Dummy", "--fixed-fps", "30", "--path", GAME, "res://tests/elite_demo_shot.tscn", "--",
            "--shot_op=kaltsit", "--shot_stage=2", "--shot_mode=%d" % mode, "--shot_dir=" + fdir.replace("\\", "/"),
            "--shot_start=%g" % start, "--shot_every=%d" % every, "--shot_n=%d" % n, "--shot_w=1280", "--shot_h=720",
            "--bal=fx/px_plane=1", "--bal=growth/late_shape=1"] + extra
    out, err, to = GR.run_godot(args, 900)
    os.makedirs(BUILD, exist_ok=True)
    open(os.path.join(BUILD, key + ".log"), "w", encoding="utf-8").write((out or "") + "\n" + (err or ""))
    return sorted(glob.glob(os.path.join(fdir, "f_*.png"))), GR.script_errors(out, err)


def heat(path):
    a = np.asarray(Image.open(path).convert("RGB")).astype(int)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    warm = (r > 170) & (r > g + 50) & (r > b + 60)
    green = (g > 170) & (g > r + 20) & (g > b + 60)
    mint = (g > 190) & (b > 150) & (r > 140)
    return int(warm.sum() + green.sum() + mint.sum())


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join(BUILD, "out"))
    ap.add_argument("--only", default="")
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    only = set(x for x in a.only.split(",") if x)
    report = []
    for key, (mode, start, every, n, extra, title) in MOVES.items():
        if only and key not in only:
            continue
        frames, errs = shoot(key, mode, start, every, n, extra)
        report.append("%s: %d 张, SCRIPT ERROR %d" % (key, len(frames), len(errs)))
        for e in errs[:5]:
            report.append("  " + e)
        if not frames:
            continue
        if key == "s3end":   # 收尾连拍：以暖色像素最多的那帧为中心取 12 张连续帧，裁到干员附近放大 2 倍
            hs = [heat(f) for f in frames]
            k0 = max(0, min(len(frames) - 12, hs.index(max(hs)) - 3))
            sheet = Image.new("RGB", (640 * 4, 360 * 3 + 40), (14, 16, 18))
            d = ImageDraw.Draw(sheet)
            d.text((12, 8), "凯尔希 · 转平面 · 精二 · %s（第 %d–%d 帧，30 fps 连续，局部 2 倍）" % (title, k0, k0 + 11), fill=(230, 230, 230), font=font(24))
            for i, f in enumerate(frames[k0:k0 + 12]):
                im = Image.open(f).convert("RGB")
                cx, cy = 640, 340
                im = im.crop((cx - 320, cy - 180, cx + 320, cy + 180)).resize((640, 360), Image.NEAREST)
                sheet.paste(im, ((i % 4) * 640, 40 + (i // 4) * 360))
            sheet.save(os.path.join(a.out, "kal_e2_%s.png" % key))
            shutil.copy(frames[hs.index(max(hs))], os.path.join(a.out, "kal_e2_%s_best.png" % key))
            continue
        pick = [frames[int(i * (len(frames) - 1) / 11)] for i in range(12)]
        tw, th = 640, 360
        sheet = Image.new("RGB", (tw * 4, th * 3 + 40), (14, 16, 18))
        d = ImageDraw.Draw(sheet)
        d.text((12, 8), "凯尔希 · 转平面 · 精二 · %s（图鉴演示实机，等间隔 12 帧）" % title, fill=(230, 230, 230), font=font(24))
        for i, f in enumerate(pick):
            im = Image.open(f).convert("RGB").resize((tw, th), Image.LANCZOS)
            sheet.paste(im, ((i % 4) * tw, 40 + (i // 4) * th))
        sheet.save(os.path.join(a.out, "kal_e2_%s.png" % key))
        best = max(frames, key=heat)
        shutil.copy(best, os.path.join(a.out, "kal_e2_%s_best.png" % key))
    open(os.path.join(a.out, "kal_preview_report.txt"), "w", encoding="utf-8").write("\n".join(report) + "\n")
    print("\n".join(report))


if __name__ == "__main__":
    main()
