# -*- coding: utf-8 -*-
"""鸭爵跑步帧（docs/216 §11.2）：pixgen 出的 3×2 跑步精灵表 → 本作像素帧条 e_duck_run@2x.png。
各帧同一缩放（按静态图 e_duck@2x 的身高）、脚底同一基线、按前景质心水平对齐；每格取众数色（同 pixgen.pixelize），
颜色吸附到静态图的色板（与已过审的静态图同色），去小碎块，外轮廓统一深色。
用法：python tools/imagegen/duck_run_cut.py <raw 精灵表> [--grid 3x2] [--order 0,1,2,3,4,5] [--out game/art/enemies/duck/e_duck_run@2x.png]
"""
import argparse, os, sys
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import pixgen as P

ROOT = os.path.dirname(os.path.dirname(HERE))
STATIC = os.path.join(ROOT, "game", "art", "enemies", "duck", "e_duck@2x.png")
FW, FH = 64, 56   # 帧宽高缺省（跑步步幅比站立宽，宽 64）；--fw 改宽


def comps_keep(m, frac=0.04):
    """只留大连通块（主体 + 面积 ≥ 主体 frac 的部件，如公文包）"""
    from collections import deque
    h, w = m.shape
    lab = np.zeros((h, w), int)
    sizes = [0]
    for y in range(h):
        for x in range(w):
            if m[y, x] and not lab[y, x]:
                n = len(sizes)
                q = deque([(y, x)])
                lab[y, x] = n
                c = 0
                while q:
                    a, b = q.popleft()
                    c += 1
                    for da in (-1, 0, 1):
                        for db in (-1, 0, 1):
                            u, v = a + da, b + db
                            if 0 <= u < h and 0 <= v < w and m[u, v] and not lab[u, v]:
                                lab[u, v] = n
                                q.append((u, v))
                sizes.append(c)
    if len(sizes) == 1:
        return m
    big = max(sizes)
    keep = [i for i, s in enumerate(sizes) if i and s >= frac * big]
    return np.isin(lab, keep)


def main():
    global FW
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("--grid", default="3x2")
    ap.add_argument("--order", default="")
    ap.add_argument("--fw", type=int, default=FW)
    ap.add_argument("--preview", default="run_strip_6x.png")
    ap.add_argument("--out", default=os.path.join(ROOT, "game", "art", "enemies", "duck", "e_duck_run@2x.png"))
    a = ap.parse_args()
    FW = a.fw
    gx, gy = [int(v) for v in a.grid.split("x")]
    im, fg = P._cutout(a.src)
    H, W = fg.shape
    cells = []
    for j in range(gy):
        for i in range(gx):
            sl = (slice(j * H // gy, (j + 1) * H // gy), slice(i * W // gx, (i + 1) * W // gx))
            m = fg[sl].copy()
            # 下采样后再求连通块太慢：先在 1/4 分辨率上找要留的块，再放大回去
            small = m[::4, ::4]
            keep = comps_keep(small)
            km = np.kron(keep, np.ones((4, 4), bool))[: m.shape[0], : m.shape[1]]
            m &= np.pad(km, ((0, m.shape[0] - km.shape[0]), (0, m.shape[1] - km.shape[1])))
            cells.append((im[sl], m))
    if a.order:
        cells = [cells[int(k)] for k in a.order.split(",")]
    st = np.array(Image.open(STATIC).convert("RGBA"))
    sm = st[..., 3] > 0
    ys = np.nonzero(sm)[0]
    target_h = ys.max() - ys.min() + 1
    pal = np.unique(st[sm][:, :3], axis=0).astype(int)
    hs = []
    for c, m in cells:
        yy = np.nonzero(m)[0]
        hs.append(yy.max() - yy.min() + 1)
    blk = float(np.median(hs)) / target_h   # 源像素 / 目标像素
    frames = []
    for c, m in cells:
        yy, xx = np.nonzero(m)
        foot = yy.max() + 1
        cx = xx.mean()
        out = np.zeros((FH, FW, 4), np.uint8)
        key = (c[..., 0] >> 3) << 10 | (c[..., 1] >> 3) << 5 | (c[..., 2] >> 3)
        for ty in range(FH):
            for tx in range(FW):
                y0 = int(round(foot - (FH - ty) * blk))
                y1 = int(round(foot - (FH - ty - 1) * blk))
                x0 = int(round(cx + (tx - FW / 2) * blk))
                x1 = int(round(cx + (tx + 1 - FW / 2) * blk))
                if y1 <= 0 or x1 <= 0 or y0 >= m.shape[0] or x0 >= m.shape[1]:
                    continue
                y0, x0 = max(y0, 0), max(x0, 0)
                cm = m[y0:y1, x0:x1]
                if cm.size == 0 or cm.mean() < 0.5:
                    continue
                ks = key[y0:y1, x0:x1][cm]
                vals, cnt = np.unique(ks, return_counts=True)
                col = c[y0:y1, x0:x1][cm][ks == vals[cnt.argmax()]].mean(0)
                col = pal[((pal - col) ** 2).sum(1).argmin()]
                out[ty, tx, :3] = col
                out[ty, tx, 3] = 255
        # 去孤立像素
        A = out[..., 3] > 0
        pad = np.pad(A, 1)
        nb = sum(np.roll(np.roll(pad, dy, 0), dx, 1)[1:-1, 1:-1] for dy in (-1, 0, 1) for dx in (-1, 0, 1)) - A
        out[A & (nb <= 1)] = 0
        # 外轮廓统一深色（同 pixgen.pixelize）
        A = out[..., 3] > 0
        pad = np.pad(A, 1)
        edge = A & ~(pad[:-2, 1:-1] & pad[2:, 1:-1] & pad[1:-1, :-2] & pad[1:-1, 2:])
        luma = out[..., :3].astype(int) @ np.array([299, 587, 114]) // 1000
        out[edge & (luma < 190), :3] = P.OUTLINE
        frames.append(out)
    strip = np.concatenate(frames, 1)
    Image.fromarray(strip).save(a.out)
    prev = Image.new("RGBA", (FW * len(frames) * 6 + 6 * FW * 2, FH * 6), (40, 44, 52, 255))
    prev.alpha_composite(Image.fromarray(strip).resize((FW * len(frames) * 6, FH * 6), Image.NEAREST))
    prev.alpha_composite(Image.open(STATIC).convert("RGBA").resize((56 * 6, 56 * 6), Image.NEAREST), (FW * len(frames) * 6 + 30, 0))
    prev.save(os.path.join(ROOT, "build", "duck_ref", a.preview))
    gif = [Image.alpha_composite(Image.new("RGBA", (FW, FH), (40, 44, 52, 255)), Image.fromarray(f)).resize((FW * 6, FH * 6), Image.NEAREST) for f in frames]
    gif[0].save(os.path.join(ROOT, "build", "duck_ref", "run_cycle.gif"), save_all=True, append_images=gif[1:], duration=90, loop=0)
    print("帧", len(frames), "块", round(blk, 2), "身高", target_h, "→", a.out)


if __name__ == "__main__":
    main()
