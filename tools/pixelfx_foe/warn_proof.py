# -*- coding: utf-8 -*-
"""预警 = 判定的录像证明图（docs/229 §9 组 E 验收，docs/236 §3.4）：读 rec_moves.py 录的逐帧截图（改前 / 改后同 seed），
新旧画面开始分叉的那一帧 = 结算帧（落点特效第 0 帧）。每次结算取三张：结算前一帧（预警圈画满，判定半径就是它）、
结算后 +6 帧（0.2 秒，尘墙推满）、两张 50% 叠合，以结算帧差异中心（落点）为心裁 460×300、放大 2 倍（最近邻），横排存 PNG。

    python tools/pixelfx_foe/warn_proof.py <输出目录> carmen2 immortal
"""
import os, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
REC = os.path.join(ROOT, "build", "foe_fx")
LAG = 6
HW, HH = 230, 150   # 裁框半宽 / 半高（屏幕像素，够装 r120 的尘墙）


def shots(d):
    return sorted(f for f in os.listdir(d) if f.startswith("shot_bmframe_") and f.endswith(".png"))


def load(d, f):
    return np.asarray(Image.open(os.path.join(d, f)).convert("RGB")).astype(np.int16)


def cam_shift(a, b, avoid=None):
    """求 b 相对 a 的整像素平移（镜头跟随造成），返回 (dy, dx)：np.roll(a, (dy, dx)) ≈ b。
    暴力搜索：降采样 2 倍、±50×±60 屏幕像素内找平均绝对差最小的平移，再在原分辨率 ±2 细化；avoid（布尔掩码）区域不参与（落点特效 / 预警）。
    相位相关会被地面噪点和 HUD 带偏（11-03 实测把 50 像素的平移测成 0），不用"""
    ga, gb = a.mean(axis=2), b.mean(axis=2)
    h, w = ga.shape
    keep = np.ones((h, w), bool)
    keep[:40] = keep[-60:] = False   # 顶部提示条、底部 HUD
    if avoid is not None:
        keep &= ~avoid
    def cost(dy, dx, st):
        y0, y1, x0, x1 = max(0, dy), h + min(0, dy), max(0, dx), w + min(0, dx)
        A = ga[y0 - dy:y1 - dy:st, x0 - dx:x1 - dx:st]
        B = gb[y0:y1:st, x0:x1:st]
        K = keep[y0:y1:st, x0:x1:st]
        return float(np.abs(A - B)[K].mean())
    best = min(((cost(dy, dx, 2), dy, dx) for dy in range(-50, 51, 2) for dx in range(-60, 61, 2)))
    best = min(((cost(dy, dx, 1), dy, dx) for dy in range(best[1] - 2, best[1] + 3) for dx in range(best[2] - 2, best[2] + 3)))
    return best[1], best[2]


def ext(mask):
    """掩码的中心与半宽 / 半高（1–99 分位，抗零星噪点）"""
    ys, xs = np.nonzero(mask)
    if xs.size < 50:
        return None
    x0, x1, y0, y1 = np.percentile(xs, 1), np.percentile(xs, 99), np.percentile(ys, 1), np.percentile(ys, 99)
    return ((x0 + x1) / 2, (y0 + y1) / 2, (x1 - x0) / 2, (y1 - y0) / 2)


def main():
    out, tags = sys.argv[1], sys.argv[2:]
    os.makedirs(out, exist_ok=True)
    try:
        font = ImageFont.truetype("C:/Windows/Fonts/msyh.ttc", 18)
    except OSError:
        font = None
    stats = []
    for tag in tags:
        da, db = os.path.join(REC, "before", tag), os.path.join(REC, "after", tag)
        fa, fb = shots(da), shots(db)
        n = min(len(fa), len(fb))
        diff = [int((np.abs(load(da, fa[i]) - load(db, fb[i])).max(axis=2) > 60).sum()) for i in range(n)]
        starts, i = [], 0
        while i < n:
            if diff[i] > 300 and (i == 0 or diff[i - 1] <= 300):
                starts.append(i)
                i += 20
            i += 1
        rows = []
        for k, s in enumerate([x for x in starts if x >= 20]):   # 开头 20 帧是刷怪，不算
            if s < 1 or s + LAG >= n:
                continue
            warn, hit = load(db, fb[s - 1]), load(db, fb[s + LAG])
            m = np.abs(load(da, fa[s]) - load(db, fb[s])).max(axis=2) > 60   # 结算帧（爆亮 + 热裂）的差异：中心 = 落点
            ys, xs = np.nonzero(m)
            if xs.size < 200 or np.percentile(xs, 95) - np.percentile(xs, 5) > 260:   # 不是落点：零星差异，或铺得很开（激光等别的招式的随机画面）
                continue
            cx, cy = int(np.median(xs)), int(np.median(ys))
            av = np.zeros(m.shape, bool)
            av[max(0, cy - HH):cy + HH, max(0, cx - HW):cx + HW] = True
            dy, dx = cam_shift(load(da, fa[s - 1]), load(da, fa[s + LAG]), av)   # 改前那局同一对帧求镜头平移（两局镜头一致），避开落点一带
            warn = np.roll(warn, (dy, dx), axis=(0, 1))   # 预警帧挪到结算 +LAG 帧的镜头下
            x0, x1, y0, y1 = max(0, cx - HW), min(m.shape[1], cx + HW), max(0, cy - HH), min(m.shape[0], cy + HH)
            win = np.zeros(m.shape, bool)
            win[y0:y1, x0:x1] = True
            red = (warn[:, :, 0] > warn[:, :, 1] + 40) & (warn[:, :, 0] > warn[:, :, 2] + 25) & win   # 预警填充（危险色系）
            dust = (np.abs(load(da, fa[s + LAG]) - hit).max(axis=2) > 40) & win   # 新特效相对旧画面的像素
            ew, ed = ext(red), ext(dust)
            if ew and ed:
                stat = "预警 中心 (%.0f, %.0f) 半宽 %.0f 半高 %.0f ｜ 尘墙 中心 (%.0f, %.0f) 半宽 %.0f 半高 %.0f ｜ 镜头平移 (%d, %d)" % (ew + ed + (dx, dy))
                print(tag, "结算帧", s, stat)
                stats.append((tag, s) + ew + ed + (dx, dy))
            crop = lambda a: Image.fromarray(a[y0:y1, x0:x1].astype(np.uint8)).resize(((x1 - x0) * 2, (y1 - y0) * 2), Image.NEAREST)
            a, b = crop(warn), crop(hit)
            c = Image.blend(a, b, 0.5)
            w, h = a.size
            row = Image.new("RGB", (w * 3 + 16, h + 28), (10, 12, 18))
            d = ImageDraw.Draw(row)
            for j, (im, lab) in enumerate(((a, "结算前 1 帧（已按镜头平移对齐）：预警圈 = 判定"), (b, "结算 +%d 帧：尘墙推满" % LAG), (c, "两帧 50% 叠合"))):
                row.paste(im, (j * (w + 8), 28))
                d.text((j * (w + 8) + 4, 4), lab, fill=(255, 230, 150), font=font)
            rows.append(row)
        if rows:
            W, H = max(r.width for r in rows), sum(r.height + 8 for r in rows)
            sheet = Image.new("RGB", (W, H), (10, 12, 18))
            y = 0
            for r in rows:
                sheet.paste(r, (0, y))
                y += r.height + 8
            p = os.path.join(out, "warn_proof_%s.png" % tag)
            lines = ["%s 结算帧 %d 预警 (%.0f,%.0f) 半宽 %.0f 半高 %.0f / 尘墙 (%.0f,%.0f) 半宽 %.0f 半高 %.0f / 镜头 (%d,%d)" % t for t in stats if t[0] == tag]
            open(os.path.join(out, "warn_proof.txt"), "a", encoding="utf-8").write("".join(ln + "\n" for ln in lines))
            sheet.save(p, optimize=True)
            print(p)


if __name__ == "__main__":
    main()
