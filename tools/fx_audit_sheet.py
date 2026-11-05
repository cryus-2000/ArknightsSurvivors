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
# S1 按哪类验收（docs/270 §3）；不在表里的干员缺省「爆发」
CLS = {"skadi": "爆发", "hoshiguma": "爆发", "lumen": "治疗", "eyjafjalla": "爆发", "siege": "爆发", "exusiai": "普攻", "mizuki": "爆发", "angelina": "爆发",
       "saria": "治疗", "logos": "持续", "gladiia": "爆发", "texas": "爆发", "skalter": "持续", "kaltsit": "治疗"}
# n 颗粒/次（下, 上）、nmax 单簇上限、lpb 灯/次下限、lr / li 灯半径 / 强度（普攻 = 每次命中的中位数；其余 = 技能后 1 秒内最亮一盏）、
# glp 照地亮度峰值、gla 命中帧照地面积、ema 命中帧核心辉光面积、ep emit p90（下, 上）、sz 平均边长下限、life 寿命（下, 上）
STD = {
    "普攻": dict(n=(3, 10), nmax=16, lpb=0.9, lr=(80, 160), li=(0.35, 0.8), glp=50, gla=1000, ema=30, ep=(40, 300), sz=3.0, life=(0.7, 1.0)),
    "爆发": dict(n=(6, 16), nmax=25, lpb=1.0, lr=(140, 240), li=(0.6, 0.9), glp=65, gla=1500, ema=60, ep=(60, 300), sz=3.0, life=(0.7, 1.0)),
    "持续": dict(n=(1, 4), nmax=12, lpb=0.5, lr=(80, 200), li=(0.35, 0.7), glp=40, gla=800, ema=20, ep=(20, 300), sz=3.0, life=(0.5, 1.0)),
    "治疗": dict(n=(2, 6), nmax=10, lpb=0.9, lr=(80, 160), li=(0.35, 0.7), glp=40, gla=800, ema=20, ep=(20, 300), sz=2.0, life=(0.5, 1.0)),
}
CORE = ("颗粒数", "颗粒边长", "照地灯/次", "核心辉光", "emit 量")


def judge(op, mode, r):
    """按 docs/270 §3 逐项对照：返回 (类, [(项, 过否, 实测)])。灯：普攻取每次命中的中位数，技能取技能后 1 秒内最亮一盏"""
    cl = "普攻" if mode == "atk" else CLS.get(op, "爆发")
    s = STD[cl]
    skill = mode == "s1" and r.get("skill_frame") is not None
    if cl == "爆发":
        n = r.get("skill_burst_max") if skill else r.get("burst_max")
    elif cl == "持续":
        n = round(r["parts_per_s"] / max(1.0, r.get("bursts", 1) / r["secs"]), 1)
    else:
        n = r.get("burst_med")
    lr, li = (r.get("skill_light_r"), r.get("skill_light_i")) if (skill and cl != "普攻") else (r["light_r"], r["light_i"])
    lr, li = lr or 0, li or 0
    chk = [
        # 普攻 / 治疗：每次中位数在 n 区间、单簇不超 nmax；爆发：技能后 1 秒最大簇在 [n 下限, nmax]；持续：每跳在 [n 下限, nmax]
        ("颗粒数", n is not None and ((s["n"][0] <= n <= s["n"][1] and (r.get("burst_max") or 0) <= s["nmax"]) if cl in ("普攻", "治疗") else s["n"][0] <= n <= s["nmax"]),
         "%s（单簇最多 %s）" % (n, r.get("burst_max")) if cl in ("普攻", "治疗") else n),
        ("颗粒边长", r["sz"] >= s["sz"], r["sz"]),
        ("颗粒寿命", s["life"][0] <= r["life"] <= s["life"][1], r["life"]),
        ("照地灯/次", r.get("lights_per_burst", 0) >= s["lpb"], r.get("lights_per_burst")),
        ("灯半径", s["lr"][0] <= lr <= s["lr"][1], lr),
        ("灯强度", s["li"][0] <= li <= s["li"][1], li),
        ("照地亮度", r["gl_peak"] >= s["glp"], r["gl_peak"]),
        ("照地面积", r["gl_area_hit"] >= s["gla"], r["gl_area_hit"]),
        ("核心辉光", r["em_area_hit"] >= s["ema"], r["em_area_hit"]),
        ("emit 量", s["ep"][0] <= r.get("emit_p90", 0) <= s["ep"][1], r.get("emit_p90")),
    ]
    if r["mats"].get("grains", 0) > 50:
        chk.append(("模板颗粒", False, "%.0f/秒 2px" % (r["mats"]["grains"] / r["secs"])))
    if mode == "s1" and not skill:
        chk.append(("技能入镜", False, "拍摄段里没有技能事件"))
    return cl, chk


def font(sz):
    for f in ["C:/Windows/Fonts/msyh.ttc", "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc"]:
        if os.path.exists(f):
            return ImageFont.truetype(f, sz)
    return ImageFont.load_default()


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
        "颗粒 每次 %s 颗（最多 %s%s），寿命 %.2f 秒，边长 %.1f px；材质 %s" % (r.get("burst_med"), r.get("burst_max"),
            "，技能后 1 秒最大簇 %s" % r["skill_burst_max"] if r.get("skill_burst_max") is not None else "", r["life"], r["sz"], mats),
        "照地光 %s 盏/次，每次命中 半径 %s、强度 %s%s；实测亮度 峰值 +%s、命中帧面积 %d px" % (
            r.get("lights_per_burst"), int(r["light_r"]), r["light_i"],
            "；技能最亮一盏 %s / %s" % (r["skill_light_r"], r["skill_light_i"]) if r.get("skill_light_r") is not None else "", r["gl_peak"], r["gl_area_hit"]),
        "发光核心 emit p90 %s 点/帧；实测辉光 峰值 +%s、命中帧面积 %d px" % (r.get("emit_p90"), r["em_peak"], r["em_area_hit"]),
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
    md = ["| 干员 | 招 | 颗粒/次（中位 / 最多） | 技能后 1 秒最大簇 | 寿命 s | 边长 px | 材质 | 灯/次 | 每次命中灯 半径 / 强度（中位） | 技能后 1 秒最亮灯 | 照地亮度峰值 | 照地面积 | emit p90 | 辉光面积 |",
          "|---|---|---|---|---|---|---|---|---|---|---|---|---|---|"]
    for op in ops:
        for mode in ("atk", "s1"):
            r = res.get((op, mode))
            if not r or r.get("err"):
                md.append("| %s | %s | — 无数据 %s |" % (NAMES[op], mode, (r or {}).get("err", "")))
                continue
            mats = "、".join("%s %d" % (k, v) for k, v in sorted(r["mats"].items(), key=lambda x: -x[1])) or "无"
            skl = "%s / %s" % (r.get("skill_light_r"), r.get("skill_light_i")) if r.get("skill_light_r") is not None else "—"
            md.append("| %s | %s | %s / %s | %s | %.2f | %.1f | %s | %s | %d / %s | %s | +%.0f | %d | %s | %d |" % (
                NAMES[op], "普攻" if mode == "atk" else "S1", r.get("burst_med"), r.get("burst_max"), r.get("skill_burst_max") if r.get("skill_burst_max") is not None else "—",
                r["life"], r["sz"], mats, r.get("lights_per_burst"), int(r["light_r"]), r["light_i"], skl, r["gl_peak"], r["gl_area_hit"], r.get("emit_p90"), r["em_area_hit"]))
    open(os.path.join(a.out, "fx_audit_table.md"), "w", encoding="utf-8").write("\n".join(md) + "\n")
    print("\n".join(md))
    jd = ["| 干员 | 招 | 按哪类 | 过几项 | 不达标项（实测值；★ = 核心项） |", "|---|---|---|---|---|"]
    for op in ops:
        for mode in ("atk", "s1"):
            r = res.get((op, mode))
            if not r or r.get("err"):
                continue
            cl, chk = judge(op, mode, r)
            bad = [x for x in chk if not x[1]]
            jd.append("| %s | %s | %s | %d / %d | %s |" % (NAMES[op], "普攻" if mode == "atk" else "S1", cl, len(chk) - len(bad), len(chk),
                      "；".join(("★" if x[0] in CORE else "") + "%s %s" % (x[0], x[2]) for x in bad) or "全过"))
    open(os.path.join(a.out, "fx_audit_judge.md"), "w", encoding="utf-8").write("\n".join(jd) + "\n")
    print("\n".join(jd))


if __name__ == "__main__":
    main()
