# -*- coding: utf-8 -*-
"""pixelfx 放开版自动图案检查（docs/242 §9.3）：规整放射 / 同心圈 / 等距并排 / 持续白，任一项超标报警。

只是过滤，最终仍由人眼判断；误报写明理由后放行（targets 条目加 "check_skip": ["radial", ...] 和 "check_note"）。
用法：
  python tools/pixelfx_check.py game/art/fx/fx_skadi_ul_slash.png [--frames N] [--origin x,y] [--sy 0.55]   单张帧条
  python tools/pixelfx_check.py --selftest                                                            用人工违规样例自检
导出脚本 tools/pixelfx_export.py 每张帧条导出前调用 check_frames()。
"""
import argparse, math, os, sys
import numpy as np
from PIL import Image, ImageDraw

# 阈值：用斯卡蒂放开版 13 张校准（都不报），人工违规样例都要报（--selftest）
WHITE_FRAC = 0.35      # 一帧可见像素里近白（RGB 最小通道 > 225）的占比
WHITE_MIN_PX = 300     # 可见像素少于这个的帧不算（只是小火花）
WHITE_RUN = 3          # 连续这么多帧算「持续白」
RING_COVER = 0.6       # 一个半径上有像素的角度格占比（360 格，要连续成线，稀疏散点到不了）≥ 这个算一道环
RING_GAP = 5           # 两道环至少隔这么多像素才算两道
RADIAL_RATIO = 7.0     # 角度直方图 6–24 次谐波里的尖峰 ÷ 左右邻居中位数（且尖峰 ≥ 总量 12%）
RADIAL_MIN_PX = 120


def _vis(f):
    a = np.asarray(f.convert("RGBA"), dtype=np.int32)
    return a, a[..., 3] > 40


def white_run(frames):
    run, worst = 0, 0
    for f in frames:
        a, v = _vis(f)
        n = int(v.sum())
        if n >= WHITE_MIN_PX and (a[..., :3].min(axis=2)[v] > 225).mean() > WHITE_FRAC:
            run += 1
            worst = max(worst, run)
        else:
            run = 0
    return worst >= WHITE_RUN, "连续近白 %d 帧" % worst


def _polar(v, ox, oy, sy):
    ys, xs = np.nonzero(v)
    dx, dy = xs - ox, (ys - oy) / sy
    return np.hypot(dx, dy), np.arctan2(dy, dx)


def rings(frames, ox, oy, sy):
    worst = 0
    for f in frames:
        _, v = _vis(f)
        if v.sum() < 60:
            continue
        r, ang = _polar(v, ox, oy, sy)
        rmax = int(r.max()) + 1
        bins = ((ang + math.pi) / (2 * math.pi) * 360).astype(int) % 360
        cover = np.zeros(rmax + 2)
        for rr in range(4, rmax):
            m = np.abs(r - rr) <= 1.0
            if m.any():
                cover[rr] = len(np.unique(bins[m])) / 360.0
        found, last = 0, -99
        for rr in range(4, rmax):
            lo = min(cover[max(0, rr - 4)], cover[min(rmax + 1, rr + 4)])
            if cover[rr] >= RING_COVER and cover[rr] >= cover[rr - 1] and cover[rr] >= cover[rr + 1] and cover[rr] - lo >= 0.3:   # 细线才算环；实心光团没有突出度
                if rr - last >= RING_GAP:
                    found += 1
                last = rr
        worst = max(worst, found)
    return worst > 1, "同一帧最多 %d 道整环" % worst


def radial(frames, ox, oy, sy):
    """角度直方图（144 格）的 6–24 次谐波里，有没有一个明显高出左右邻居的尖峰（等距放射才会出尖峰；一条弧 / 散点的频谱是平滑下降的）"""
    worst = 0.0
    for f in frames:
        _, v = _vis(f)
        r, ang = _polar(v, ox, oy, sy)
        if len(r) < RADIAL_MIN_PX:
            continue
        sel = r > 0.3 * r.max()
        if sel.sum() < RADIAL_MIN_PX:
            continue
        h, _ = np.histogram(ang[sel], bins=144, range=(-math.pi, math.pi))
        F = np.abs(np.fft.rfft(h - h.mean()))
        for k in range(6, 25):
            nb = np.concatenate([F[k - 3:k - 1], F[k + 2:k + 4]])
            base = float(np.median(nb)) + 1e-6
            if F[k] > 0.12 * float(h.sum()):   # 尖峰本身也要够大
                worst = max(worst, float(F[k] / base))
    return worst > RADIAL_RATIO, "放射尖峰比 %.1f" % worst


def repeats(frames):
    """同一帧里 ≥ 4 个形状逐像素相似（同尺寸、掩码 IoU ≥ 0.8）的连通块，排成一线且间距几乎相等（相对差 < 6%），算等距并排。
    小颗粒（< 40 px）和颗粒云（> 25 块）不算子图"""
    from scipy import ndimage
    worst = 0
    for f in frames:
        _, v = _vis(f)
        lab, n = ndimage.label(v)
        if n < 4:
            continue
        objs = []
        for i, sl in enumerate(ndimage.find_objects(lab)):
            m = lab[sl] == i + 1
            if int(m.sum()) < 40:
                continue
            objs.append(((sl[1].start + sl[1].stop) / 2, (sl[0].start + sl[0].stop) / 2, m))
        if len(objs) > 25 or len(objs) < 4:
            continue
        def same(a, b):
            if a[2].shape != b[2].shape:
                return False
            inter = float((a[2] & b[2]).sum())
            return inter / float((a[2] | b[2]).sum()) >= 0.8
        for a in objs:
            grp = [b for b in objs if same(a, b)]
            if len(grp) < 4:
                continue
            for axis in (0, 1):
                pts = sorted(grp, key=lambda b: b[axis])
                for j in range(len(pts) - 3):
                    q = pts[j:j + 4]
                    ds = [math.dist(q[k][:2], q[k + 1][:2]) for k in range(3)]
                    off = abs(q[3][1 - axis] - q[0][1 - axis])
                    if min(ds) > 4 and (max(ds) - min(ds)) / max(ds) < 0.06 and off < 0.1 * sum(ds):
                        worst = 4
    return worst >= 4, "等距并排 %s" % ("有" if worst else "无")


def check_frames(frames, origin, sy=1.0, skip=()):
    """返回 [(项, 超标, 说明)]"""
    ox, oy = origin
    out = []
    for key, fn in (("white", lambda: white_run(frames)), ("ring", lambda: rings(frames, ox, oy, sy)),
                    ("radial", lambda: radial(frames, ox, oy, sy)), ("repeat", lambda: repeats(frames))):
        bad, note = fn()
        out.append((key, bad and key not in skip, note + ("（已放行）" if bad and key in skip else "")))
    return out


def load_strip(path, n):
    im = Image.open(path).convert("RGBA")
    w = im.width // n
    return [im.crop((i * w, 0, (i + 1) * w, im.height)) for i in range(n)]


def _selftest():
    W = 160
    def blank():
        return Image.new("RGBA", (W, W), (0, 0, 0, 0))
    cases = {}
    fr = []
    for k in range(4):   # 等距放射线
        im = blank(); d = ImageDraw.Draw(im)
        for i in range(12):
            a = i * math.tau / 12
            d.line((80 + 20 * math.cos(a), 80 + 20 * math.sin(a), 80 + 70 * math.cos(a), 80 + 70 * math.sin(a)), fill=(255, 180, 60, 255), width=3)
        fr.append(im)
    cases["radial"] = fr
    fr = []
    for k in range(4):   # 三道同心圈
        im = blank(); d = ImageDraw.Draw(im)
        for r in (25, 45, 65):
            d.ellipse((80 - r, 80 - r, 80 + r, 80 + r), outline=(80, 200, 255, 255), width=2)
        fr.append(im)
    cases["ring"] = fr
    fr = []
    for k in range(4):   # 同一子图等距并排
        im = blank(); d = ImageDraw.Draw(im)
        for i in range(5):
            x = 10 + i * 30
            d.polygon([(x, 120), (x + 12, 60), (x + 24, 120)], fill=(120, 220, 255, 255))
        fr.append(im)
    cases["repeat"] = fr
    fr = []
    for k in range(4):   # 持续白
        im = blank(); d = ImageDraw.Draw(im)
        d.ellipse((30, 30, 130, 130), fill=(255, 255, 255, 255))
        fr.append(im)
    cases["white"] = fr
    ok = True
    for want, frames in cases.items():
        res = {k: b for k, b, _ in check_frames(frames, (80, 80))}
        print("%-7s 应报 → %s %s" % (want, "报了" if res[want] else "**漏报**", {k: v for k, v in res.items() if v}))
        ok &= res[want]
    return ok


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("strip", nargs="?")
    ap.add_argument("--frames", type=int, default=0)
    ap.add_argument("--origin", default="")
    ap.add_argument("--sy", type=float, default=1.0)
    ap.add_argument("--selftest", action="store_true")
    a = ap.parse_args()
    if a.selftest:
        sys.exit(0 if _selftest() else 1)
    n = a.frames
    if not n:   # 从 art.gd 的 V6_FRAMES 读帧数
        import re
        base = os.path.basename(a.strip).replace("@2x", "")[:-4]
        art = open(os.path.join(os.path.dirname(__file__), "..", "game", "scripts", "art.gd"), encoding="utf-8").read()
        n = int(re.search(r'"%s": \[(\d+)' % re.escape(base), art).group(1))
    frames = load_strip(a.strip, n)
    origin = tuple(int(v) for v in a.origin.split(",")) if a.origin else (frames[0].width // 2, frames[0].height // 2)
    res = check_frames(frames, origin, a.sy)
    for k, bad, note in res:
        print("%-7s %s  %s" % (k, "超标" if bad else "ok", note))
    sys.exit(1 if any(b for _, b, _ in res) else 0)


if __name__ == "__main__":
    main()
