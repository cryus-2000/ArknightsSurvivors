#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""后期特效控制诊断（docs/289）的本机量测：读 GCP late_fx_diag.sh 的截图（<阵容>_<层>/shot_<帧>.png + .json），
逐像素差出各层掩码，量战场区里我方特效 / 队长 / 队友 / 每名干员 / 敌人 / 敌弹预警的占屏，以及我方特效盖住敌弹预警、敌人的比例；
挑我方特效占屏最大的 3 帧，出掩码描边图。不开 Godot。

用法：python tools/late_fx_measure.py <截图根目录> <输出目录>
输出：metrics.json、worst_<阵容>_<帧>.png（左原图 / 右掩码：青 = 队长、黄 = 队友、橙 = 敌弹预警、品红 = 敌人）、summary.md
"""
import glob, json, os, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFont

BOX = (180, 150, 1100, 560)   # 中央战场区（避开顶栏 / 小地图 / 编队卡，同 docs/243）
THR = 0.06 * 255 * 3          # 三通道差之和 > 0.06（docs/243 §1.3 口径）
SPF = 0.0659


def load(p):
    return np.asarray(Image.open(p).convert("RGB"), dtype=np.int16)


def mask(a, b):
    m = np.abs(a - b).sum(axis=2) > THR
    x0, y0, x1, y1 = BOX
    out = np.zeros_like(m)
    out[y0:y1, x0:x1] = m[y0:y1, x0:x1]
    return out


def main():
    root, out = sys.argv[1], sys.argv[2]
    os.makedirs(out, exist_ok=True)
    area = (BOX[2] - BOX[0]) * (BOX[3] - BOX[1])
    res = {}
    lineups = sorted({os.path.basename(d).split("_")[0] for d in glob.glob(os.path.join(root, "*_full"))})
    for lu in lineups:
        full_dir = os.path.join(root, lu + "_full")
        layers = [os.path.basename(d)[len(lu) + 1:] for d in glob.glob(os.path.join(root, lu + "_*")) if os.path.isdir(d)]
        for fp in sorted(glob.glob(os.path.join(full_dir, "shot_*.png"))):
            fr = os.path.basename(fp)[5:-4]
            full = load(fp)
            ms = {}
            for ly in layers:
                if ly == "full":
                    continue
                q = os.path.join(root, "%s_%s" % (lu, ly), "shot_%s.png" % fr)
                if os.path.exists(q):
                    ms[ly] = mask(full, load(q))
            js = {}
            jp = os.path.join(full_dir, "shot_%s.json" % fr)
            if os.path.exists(jp):
                js = json.load(open(jp, encoding="utf-8"))
            row = {"t": js.get("t", int(fr) * SPF), "enemies_on": js.get("enemies_on"), "ebullets_on": js.get("ebullets_on"),
                   "warns_full": js.get("warns_full"), "fx_dim": js.get("fx_dim"), "ops": js.get("ops"), "fx_by_op": js.get("fx_by_op")}
            for k, m in ms.items():
                row["area_" + k] = round(100.0 * m.sum() / area, 2)
            fr_m = ms.get("nofriend")
            for foe_k in ("nofoe", "noenemy"):
                if fr_m is not None and foe_k in ms and ms[foe_k].sum() > 0:
                    row["cover_" + foe_k] = round(100.0 * (fr_m & ms[foe_k]).sum() / ms[foe_k].sum(), 1)   # 敌方像素里有多少同时也被我方特效改了色（≈ 被盖）
            res["%s_%s" % (lu, fr)] = row
    json.dump(res, open(os.path.join(out, "metrics.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    # 最糊的 3 帧：我方特效占屏最大
    worst = sorted(res.items(), key=lambda kv: -kv[1].get("area_nofriend", 0))[:3]
    f = ImageFont.truetype("C:/Windows/Fonts/msyh.ttc", 18) if os.path.exists("C:/Windows/Fonts/msyh.ttc") else ImageFont.load_default()
    for key, row in worst:
        lu, fr = key.split("_")
        full = Image.open(os.path.join(root, lu + "_full", "shot_%s.png" % fr)).convert("RGB")
        ov = full.copy()
        px = np.asarray(ov).copy()
        cols = {"noenemy": (255, 60, 220), "nofoe": (255, 150, 30), "nomates": (255, 230, 60), "nolead": (60, 240, 255)}
        for ly, c in cols.items():
            q = os.path.join(root, "%s_%s" % (lu, ly), "shot_%s.png" % fr)
            if os.path.exists(q):
                m = mask(load(os.path.join(root, lu + "_full", "shot_%s.png" % fr)), load(q))
                px[m] = (0.35 * px[m] + 0.65 * np.array(c)).astype(np.uint8)
        ov = Image.fromarray(px)
        c = Image.new("RGB", (full.width * 2 + 8, full.height), (12, 12, 16))
        c.paste(full, (0, 0)); c.paste(ov, (full.width + 8, 0))
        d = ImageDraw.Draw(c)
        lab = "阵容 %s  %d:%02d  我方特效 %.1f%%（队长 %.1f / 队友 %.1f）  敌弹预警被盖 %s%%" % (
            lu, int(row["t"]) // 60, int(row["t"]) % 60, row.get("area_nofriend", 0), row.get("area_nolead", 0), row.get("area_nomates", 0), row.get("cover_nofoe", "-"))
        d.rectangle((0, 0, d.textlength(lab, font=f) + 16, 28), fill=(0, 0, 0))
        d.text((8, 3), lab, fill=(255, 220, 140), font=f)
        c.save(os.path.join(out, "worst_%s_%s.png" % (lu, fr)))
    # 汇总表
    lines = ["| 帧 | 时刻 | 敌人 | 敌弹 | 我方特效 % | 队长 % | 队友 % | 各干员 % | 敌弹预警 % | 敌人 % | 敌弹预警被盖 % | 敌人被盖 % |", "|" + "---|" * 12]
    for key, row in sorted(res.items()):
        per = " ".join("%s %.1f" % (k[8:], v) for k, v in row.items() if k.startswith("area_noop_"))
        lines.append("| %s | %d:%02d | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s |" % (key, int(row["t"]) // 60, int(row["t"]) % 60, row.get("enemies_on"), row.get("ebullets_on"),
                     row.get("area_nofriend"), row.get("area_nolead"), row.get("area_nomates"), per, row.get("area_nofoe"), row.get("area_noenemy"), row.get("cover_nofoe"), row.get("cover_noenemy")))
    open(os.path.join(out, "summary.md"), "w", encoding="utf-8").write("\n".join(lines) + "\n")
    print("\n".join(lines))
    print("最糊 3 帧：", [k for k, _ in worst])


if __name__ == "__main__":
    main()
