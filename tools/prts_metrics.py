# -*- coding: utf-8 -*-
"""PRTS 小人（Spine 待机 f0）比例实测（界面与美术 10-15，docs/103 §6 的数据来源）。

样本：主仓库 build/prts_ref/<id>/idle_f00.png（1000×1000 透明底、朝右，不入库）。
纯剪影自动量会被头发 / 帽子 / 武器 / 披风干扰，所以全部是人工读数：在 10 像素网格放大图上读，写在 ANNOT 里
（原图像素，±5 左右）。脚本只做汇总和出标线拼图。

ANNOT 字段（原图像素坐标）：
    top    头部最高点（含帽 / 耳 / 角；不含武器、光环、呆毛）
    hair   发顶 / 额头（不含帽 / 耳 / 角）；None = 帽子盖住，按其余样本的眼高中位推
    el/er  左 / 右眼中心 x；None = 被遮或侧脸
    ey     眼中心 y
    chin   下巴
    hl/hr  眼高那一行的头宽左右端（含两侧头发，不含双马尾 / 耳 / 角）
    sl/sr/sy  肩宽左右端与所在行（含肩上的外套 / 披风，不含手臂与武器）
    waist  腰（躯干最窄处 / 腰带）
    crotch 两腿分开处（裙 / 长外套盖住时取下摆，偏低，见备注）
    feet   脚底

定义（和 docs/103 §1 对齐）：
    头高 = chin − hair；站立高 = feet − top；头身比 = 头高 / 站立高（同 docs/103）
    头身数 = (feet − hair) / 头高（几头身，原作口径，不含头饰）
    眼高 = (ey − hair) / 头高；眼到下巴 / 头高；眼距 / 头宽；头宽 / 头高；肩宽 / 头宽
    腰位 = (waist − hair) / (feet − hair)；腿长占比 = (feet − crotch) / (feet − hair)

用法：python tools/prts_metrics.py [--ref build/prts_ref] [--out art/reference/prts_body_ratios.png]
"""
import argparse, os, statistics
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

#         top  hair  el   er   ey   chin  hl   hr   sl   sr   sy   waist crotch feet
ANNOT = {
    "mizuki":     (329, None, 476, 580, 490, 530, 405, 605, 415, 540, 565, 640, 700, 798, "帽遮发顶"),
    "suzuran":    (265, 305, 470, 557, 465, 528, 400, 610, 420, 580, 590, 680, 800, 932, "裙盖腿"),
    "siege":      (410, 475, 488, 552, 585, 625, 415, 600, 440, 570, 650, 720, 760, 928, ""),
    "skadi":      (398, None, 512, 570, 535, 565, 450, 600, 470, 580, 590, 650, 700, 819, "帽遮发顶"),
    "saria":      (380, 412, 487, 572, 535, 585, 445, 615, 440, 600, 600, 680, 800, 917, "长外套盖腿"),
    "eyjafjalla": (255, 270, 468, 550, 425, 468, 370, 585, 430, 620, 500, 600, 660, 825, ""),
    "kaltsit":    (70, 175, 448, 572, 405, 470, 300, 615, 390, 560, 520, 640, 740, 937, "长发宽"),
    "skalter":    (147, None, 497, 575, 395, 435, 435, 620, 420, 560, 470, 560, 620, 815, "帽遮发顶"),
    "texas":      (66, 135, 482, 567, 262, 300, 395, 605, 430, 600, 340, 400, 470, 615, ""),
    "hoshiguma":  (446, 466, 500, None, 572, 610, 430, 600, 470, 590, 640, 720, 790, 856, "侧脸，只见一只眼"),
    "exusiai":    (150, 160, None, 612, 425, 470, 395, 660, 390, 550, 500, 620, 690, 940, "侧脸，光环不计"),
    "angelina":   (300, 365, 472, 548, 515, 560, 345, 565, 400, 560, 600, 680, 740, 910, "双马尾不计"),
    "irene":      (410, 478, 485, 565, 600, 645, 410, 600, 440, 590, 680, 760, 820, 922, ""),
    "specter_unchained": (371, None, 508, 572, 568, 608, 445, 610, 450, 600, 630, 700, 760, 826, "帽遮发顶"),
    "lumen":      (268, 268, 497, 577, 425, 482, 375, 610, 380, 560, 510, 650, 740, 898, "呆毛不计"),
    "wisadel":    (295, 330, 495, 578, 485, 525, 450, 605, 430, 560, 600, 690, 760, 927, "光环 / 背后武器不计"),
    "ulpianus":   (430, None, 500, 567, 588, 630, 445, 605, 440, 620, 660, 740, 800, 917, "帽遮发顶、面罩遮下巴（按面罩下沿）；长外套盖腿"),
    "logos":      (190, 305, 455, 550, 452, 503, 395, 610, 420, 590, 545, 680, 760, 916, "角饰算头部最高点；长外套盖腿"),
}
NAME = {"mizuki": "水月", "suzuran": "铃兰", "siege": "推进之王", "skadi": "斯卡蒂", "saria": "塞雷娅", "eyjafjalla": "艾雅法拉",
        "kaltsit": "凯尔希", "skalter": "浊心斯卡蒂", "texas": "德克萨斯", "hoshiguma": "星熊", "exusiai": "能天使",
        "angelina": "安洁莉娜", "irene": "艾丽妮", "specter_unchained": "归溟幽灵鲨", "lumen": "流明", "wisadel": "维什戴尔", "ulpianus": "乌尔比安", "logos": "逻各斯"}
# docs/103 §3 的分卡（10-15 协调人定）
CARD = {"成女": ["saria", "skalter", "hoshiguma", "texas", "siege", "specter_unchained", "wisadel"],
        "少": ["exusiai", "eyjafjalla", "irene", "angelina", "kaltsit", "skadi", "mizuki"],
        "幼": ["suzuran"], "成男": ["lumen", "logos", "ulpianus"]}


# 现版像素小人（docs/103 §2，1x）：站立高、头高、头饰高、眼距、眼高、眼到下巴；卡同 docs/103 §3
OURS = {
    "成女": [(37.5, 11, 1.5, 4, 0.84, 1.75), (34.5, 11.25, 4.25, 3.25, 0.78, 2.5), (36.5, 12, 5.5, 4, 0.77, 2.75), (32.5, 9.5, 2.5, None, 0.68, 3),
             (34, 11.5, 4, 5.5, 0.8, 2.25), (39, 11.5, 2, 5, 0.76, 2.75), (33, 13, 5, 3.5, 0.81, 2.5)],
    "少": [(35.5, 13, 3.5, None, 0.73, 3.5), (33.5, 13.5, 1.5, 4.5, 0.7, 4), (32, 11.5, 3, 5, 0.7, 3.5), (36.5, 12, 5.5, 5.5, 0.69, 3.75),
           (35.5, 12.5, 4.5, 5.5, 0.74, 3.25), (33, 11, 1, 4, 0.8, 2.25), (33.5, 12, 1, 4, 0.73, 3.25)],
    "幼": [(34, 11, 4, 4.25, 0.61, 4.25)],
    "成男": [(34.5, 12, 4.5, 3, 0.62, 4.5), (33.5, 11.5, 4.5, 3.5, 0.65, 4)],
}
# 现版四张代表帧（art/templates/body_*.png，@2x ×6 显示像素）人工读：发顶、下巴、腰、两腿分开处、脚底
OURS_BODY = {"成女": (265, 402, 490, 525, 600), "少": (234, 378, 470, 520, 612), "幼": (265, 396, 470, 540, 598), "成男": (265, 408, 500, 560, 610)}


def ours_summary():
    rows = []
    for card, rs in OURS.items():
        hs = [(h - hw) / hh for h, hh, hw, *_ in rs]
        hb = [hh / h for h, hh, *_ in rs]
        eh = [r[4] for r in rs]
        ec = [r[5] / r[1] for r in rs]
        ed = [r[3] / r[1] for r in rs if r[3]]
        top, chin, waist, crotch, feet = OURS_BODY[card]
        body = feet - top
        def rng(v):
            return fmt(v[0]) if len(v) == 1 else f"{statistics.mean(v):.2f}（{min(v):.2f}–{max(v):.2f}）"
        rows.append([card, rng(hs), rng(hb), rng(eh), rng(ec), rng(ed), fmt((waist - top) / body), fmt((feet - crotch) / body)])
    return rows


def metrics():
    # 帽遮的按其余样本「眼高」中位推发顶
    eh = [(a[4] - a[1]) / (a[5] - a[1]) for a in ANNOT.values() if a[1] is not None]
    e_med = statistics.median(eh)
    out = {}
    for k, a in ANNOT.items():
        top, hair, el, er, ey, chin, hl, hr, sl, sr, sy, waist, crotch, feet, note = a
        est = hair is None
        if est:
            hair = ey - e_med / (1 - e_med) * (chin - ey)
        hh = chin - hair
        body = feet - hair
        hw = hr - hl
        m = {"hair": hair, "est": est, "头高": hh, "站立高": feet - top, "头身比": hh / (feet - top), "头身数": body / hh,
             "头宽/头高": hw / hh, "眼高": (ey - hair) / hh, "眼到下巴/头高": (chin - ey) / hh,
             "眼距/头宽": (er - el) / hw if el and er else None, "眼距/头高": (er - el) / hh if el and er else None, "肩宽/头宽": (sr - sl) / hw,
             "腰位": (waist - hair) / body, "腿长占比": (feet - crotch) / body, "note": note}
        out[k] = m
    return out, e_med


def fmt(v, n=2):
    return "—" if v is None else f"{v:.{n}f}"


def summary(ms):
    keys = ["头身数", "头身比", "头宽/头高", "眼高", "眼到下巴/头高", "眼距/头宽", "眼距/头高", "肩宽/头宽", "腰位", "腿长占比"]
    rows = []
    for card, ids in CARD.items():
        r = [card, "、".join(NAME[i] for i in ids)]
        for key in keys:
            vs = [ms[i][key] for i in ids if ms[i][key] is not None]
            if not vs:
                r.append("—")
            elif len(vs) == 1:
                r.append(fmt(vs[0]))
            else:
                r.append(f"{statistics.mean(vs):.2f}（{min(vs):.2f}–{max(vs):.2f}）")
        rows.append(r)
    return keys, rows


def mosaic(ref, out, ms):
    ids = [i for ids in CARD.values() for i in ids]
    cw, chh, cols = 300, 400, 5
    rows = (len(ids) + cols - 1) // cols
    can = Image.new("RGB", (cw * cols, (chh + 30) * rows), (24, 26, 32))
    d = ImageDraw.Draw(can)
    try:
        f = ImageFont.truetype(r"C:\Windows\Fonts\msyh.ttc", 15)
        fs = ImageFont.truetype(r"C:\Windows\Fonts\msyh.ttc", 11)
    except OSError:
        f = fs = ImageFont.load_default()
    for n, k in enumerate(ids):
        a = ANNOT[k]
        m = ms[k]
        top, feet = a[0], a[13]
        im = Image.open(os.path.join(ref, k, "idle_f00.png")).convert("RGBA")
        # 以 top–feet 为高缩放，水平以头宽中心居中
        sc = (chh - 40) / (feet - top + 40)
        cx = (a[6] + a[7]) / 2
        x0 = cx - cw / 2 / sc
        y0 = top - 20
        crop = im.crop((int(x0), int(y0), int(x0 + cw / sc), int(y0 + (chh - 20) / sc)))
        crop = crop.resize((cw, chh - 20), Image.LANCZOS)
        cell = Image.new("RGBA", (cw, chh - 20), (40, 43, 52, 255))
        cell.alpha_composite(crop)
        gx, gy = (n % cols) * cw, (n // cols) * (chh + 30)
        can.paste(cell.convert("RGB"), (gx, gy + 30))
        def Y(v):
            return gy + 30 + (v - y0) * sc
        def X(v):
            return gx + (v - x0) * sc
        hair = m["hair"]
        lines = [(top, (150, 150, 150), "顶"), (hair, (80, 200, 255), "发顶" + ("*" if m["est"] else "")), (a[4], (255, 220, 80), "眼"),
                 (a[5], (255, 120, 120), "颏"), (a[10], (160, 255, 160), "肩"), (a[11], (255, 160, 255), "腰"),
                 (a[12], (255, 180, 90), "裆"), (feet, (200, 200, 200), "脚")]
        for v, col, lab in lines:
            d.line([(gx + 4, Y(v)), (gx + cw - 4, Y(v))], fill=col, width=1)
            d.text((gx + cw - 30, Y(v) - 13), lab, fill=col, font=fs)
        d.line([(X(a[6]), Y(a[4]) - 6), (X(a[6]), Y(a[4]) + 6)], fill=(80, 200, 255), width=2)
        d.line([(X(a[7]), Y(a[4]) - 6), (X(a[7]), Y(a[4]) + 6)], fill=(80, 200, 255), width=2)
        d.line([(X(a[8]), Y(a[10]) - 5), (X(a[9]), Y(a[10]) - 5)], fill=(160, 255, 160), width=2)
        for ex in (a[2], a[3]):
            if ex:
                d.ellipse([X(ex) - 3, Y(a[4]) - 3, X(ex) + 3, Y(a[4]) + 3], outline=(255, 220, 80), width=2)
        card = next(c for c, v in CARD.items() if k in v)
        d.text((gx + 6, gy + 6), f"{NAME[k]}（{card}）  {m['头身数']:.2f} 头身  眼高 {m['眼高']:.2f}", fill=(235, 235, 235), font=f)
    can.save(out)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ref", default=os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(ROOT))), "build", "prts_ref")
                    if ".claude" in ROOT else os.path.join(ROOT, "build", "prts_ref"))
    ap.add_argument("--out", default=os.path.join(ROOT, "art", "reference", "prts_body_ratios.png"))
    args = ap.parse_args()
    ms, e_med = metrics()
    cols = ["头身数", "头身比", "头宽/头高", "眼高", "眼到下巴/头高", "眼距/头宽", "眼距/头高", "肩宽/头宽", "腰位", "腿长占比"]
    print(f"眼高中位（推帽遮发顶用）{e_med:.3f}")
    print("| 干员 | 卡 | " + " | ".join(cols) + " | 备注 |")
    print("|---|---|" + "---|" * len(cols) + "---|")
    for card, ids in CARD.items():
        for k in ids:
            m = ms[k]
            print(f"| {NAME[k]} | {card} | " + " | ".join(fmt(m[c]) for c in cols) + f" | {m['note']}{'；发顶按眼高推' if m['est'] else ''} |")
    keys, rows = summary(ms)
    print()
    print("| 卡 | 成员 | " + " | ".join(keys) + " |")
    print("|---|---|" + "---|" * len(keys))
    for r in rows:
        print("| " + " | ".join(r) + " |")
    print()
    print("现版（docs/103 §2；腰位 / 腿长只量了四张代表帧）")
    print("| 卡 | 头身数 | 头身比 | 眼高 | 眼到下巴/头高 | 眼距/头高 | 腰位 | 腿长占比 |")
    print("|---|---|---|---|---|---|---|---|")
    for r in ours_summary():
        print("| " + " | ".join(r) + " |")
    if os.path.isdir(args.ref):
        print(mosaic(args.ref, args.out, ms))


if __name__ == "__main__":
    main()
