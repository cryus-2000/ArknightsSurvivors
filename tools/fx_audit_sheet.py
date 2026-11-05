#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""光感 + 粒子感体检（docs/270）的对比总表：读 tools/fx_audit.py 在 GCP 上出的 <op>_<招>.json / *_x2.png，
拼一张总表 PNG（每人一行：普攻 2 倍局部、S1 2 倍局部，旁边写量化数）并输出 Markdown 表。只用 PIL，本机可跑。

    python tools/fx_audit_sheet.py --dirs "<Claude outputs>/render-fxaudit-integ" "<…>/render-fxaudit-logos" … --out <目录>
"""
import argparse, glob, json, os

from PIL import Image, ImageDraw, ImageFont

NAMES = {"skadi": "斯卡蒂", "hoshiguma": "星熊", "lumen": "流明", "eyjafjalla": "艾雅法拉", "siege": "推进之王", "exusiai": "能天使",
         "mizuki": "水月", "angelina": "安洁莉娜", "saria": "塞雷娅", "logos": "逻各斯", "gladiia": "歌蕾蒂娅", "texas": "德克萨斯",
         "skalter": "浊心斯卡蒂", "kaltsit": "凯尔希"}
ORDER = list(NAMES)


def font(sz):
    return ImageFont.truetype("C:/Windows/Fonts/msyh.ttc", sz)


def load(dirs):
    res = {}
    for d in dirs:
        for f in glob.glob(os.path.join(d, "**", "*_atk.json"), recursive=True) + glob.glob(os.path.join(d, "**", "*_s1.json"), recursive=True):
            r = json.load(open(f, encoding="utf-8"))
            r["_dir"] = os.path.dirname(f)
            res[(r["op"], r["mode"])] = r
    return res


def line(r):
    if not r or r.get("err"):
        return ["（无数据：%s）" % (r or {}).get("err", "没跑")]
    mats = "、".join("%s %d" % (k, v) for k, v in sorted(r["mats"].items(), key=lambda x: -x[1])) or "无"
    return [
        "颗粒 %s/次命中（%s/秒），寿命 %.2f 秒，边长 %.1f px；材质 %s" % (r["parts_per_hit"], r["parts_per_s"], r["life"], r["sz"], mats),
        "照地光 %s 盏/次，半径 %s、强度 %s、寿命 %s 秒；实测亮度 峰值 +%s / 命中帧均值 +%s、面积 %d px" % (
            r["lights_per_hit"], int(r["light_r"]), r["light_i"], r["light_life"], r["gl_peak"], r["gl_mean_hit"], r["gl_area_hit"]),
        "发光核心 emit 每帧最多 %d 点（有 emit 帧均值 %s）；实测辉光 峰值 +%s、命中帧面积 %d px" % (r["emit_max"], r["emit_mean"], r["em_peak"], r["em_area_hit"]),
    ]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dirs", nargs="+", required=True)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    res = load(a.dirs)
    ops = [o for o in ORDER if (o, "atk") in res or (o, "s1") in res]
    cw, ch = 640, 360
    tw = 760
    rowh = ch + 16
    W = 200 + (cw + tw + 16) * 2
    sheet = Image.new("RGB", (W, 70 + rowh * len(ops)), (12, 12, 16))
    d = ImageDraw.Draw(sheet)
    d.text((16, 14), "光感 + 粒子感体检 · 精二 · 图鉴演示 · fx/px_plane=1 · 命中那一刻 2 倍局部（docs/270）", fill=(235, 235, 235), font=font(30))
    f20, f30 = font(19), font(30)
    for i, op in enumerate(ops):
        y = 70 + i * rowh
        d.text((16, y + ch // 2 - 20), NAMES[op], fill=(255, 255, 255), font=f30)
        for j, mode in enumerate(("atk", "s1")):
            x = 200 + j * (cw + tw + 16)
            r = res.get((op, mode))
            if r and not r.get("err"):
                p = os.path.join(r["_dir"], "%s_%s_x2.png" % (op, mode))
                if os.path.exists(p):
                    im = Image.open(p).convert("RGB")
                    sheet.paste(im.crop((0, 40, cw, 40 + ch)), (x, y))
            d.text((x + tw * 0 + cw + 12, y + 4), "普攻" if mode == "atk" else "S1", fill=(255, 210, 120), font=f30)
            for k, t in enumerate(line(r)):
                # 手动换行
                rows, cur = [], ""
                for chh in t:
                    if d.textlength(cur + chh, font=f20) > tw - 20:
                        rows.append(cur)
                        cur = ""
                    cur += chh
                rows.append(cur)
                yy = y + 50 + k * 96
                for q, rr in enumerate(rows):
                    d.text((x + cw + 12, yy + q * 24), rr, fill=(220, 220, 220), font=f20)
    os.makedirs(a.out, exist_ok=True)
    sheet.save(os.path.join(a.out, "fx_audit_sheet.png"))
    # Markdown 表
    md = ["| 干员 | 招 | 颗粒/次 | 颗粒/秒 | 寿命 s | 边长 px | 材质 | 灯/次 | 灯半径 | 灯强度 | 灯寿命 | 照地亮度峰值 | 照地面积 | emit 点/帧 | 辉光峰值 | 辉光面积 |",
          "|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|"]
    for op in ops:
        for mode in ("atk", "s1"):
            r = res.get((op, mode))
            if not r or r.get("err"):
                md.append("| %s | %s | — 无数据 %s |" % (NAMES[op], mode, (r or {}).get("err", "")))
                continue
            mats = "、".join("%s %d" % (k, v) for k, v in sorted(r["mats"].items(), key=lambda x: -x[1])) or "无"
            md.append("| %s | %s | %s | %s | %.2f | %.1f | %s | %s | %d | %s | %s | %s | %d | %d | %s | %d |" % (
                NAMES[op], "普攻" if mode == "atk" else "S1", r["parts_per_hit"], r["parts_per_s"], r["life"], r["sz"], mats,
                r["lights_per_hit"], int(r["light_r"]), r["light_i"], r["light_life"], r["gl_peak"], r["gl_area_hit"], r["emit_max"], r["em_peak"], r["em_area_hit"]))
    open(os.path.join(a.out, "fx_audit_table.md"), "w", encoding="utf-8").write("\n".join(md) + "\n")
    print("\n".join(md))


if __name__ == "__main__":
    main()
