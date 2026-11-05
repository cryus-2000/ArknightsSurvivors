#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""推进之王 S1「冲锋号令」狮吼的狮头帧条（docs/264 §8，用户 11-05「狮吼用生图工具然后再转吧」）。

源图：pixgen（Gemini）出的怒吼狮头侧面（洋红底），候选原图只放本机 Claude outputs/pxplane_siege_1105/lion_gen/，不进 git。
转法：洋红抠图 → 去掉小星点 → 裁外框 → 按目标高度逐帧重采样（不是把像素图再缩放）→ 按亮度分位压成 4 阶金色 + 深色外描边 → 对齐美术像素格；
帧条 15 fps 7 帧（0.47 秒）：张口（0.7 倍、提亮一阶）→ 吼出（0.88 → 1 倍，描边热白一拍）→ 停 → 从鬃毛尾端往前散掉（按哈希逐像素去掉）。
最亮一阶进发光层（emit 点表，前 4 帧）。原点 = 干员脚底，狮头中心在身前 30、离地 34 美术像素（朝 +x；朝左游戏里翻转）。
输出：game/art/fx/pxp/pxp_sg_lion_e{0,1,2}_up.png + 写进 game/data/pxp_siege.json（E2 描边白金，E0 / E1 金）。

用法：python tools/pxplane_lion.py --src "<候选原图>" [--sheet 对照图输出路径 --cands 候选目录]
"""
import argparse, glob, json, os

import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy import ndimage

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
H = 38                     # 目标高度（美术像素）= 76 世界像素
CX, CZ = 30, 34            # 狮头中心相对脚底（美术像素）
TONES = [(0xa8, 0x5e, 0x1a), (0xe0, 0x8e, 0x26), (0xff, 0xbf, 0x3c), (0xff, 0xe9, 0xa0)]   # 4 阶金（同 ak-siege-pp.js 熔金）
OUTLINE = (0x2c, 0x16, 0x0a)
DEEP = (0x55, 0x2a, 0x10)  # 口里 / 源图深线
WHITE = (255, 255, 255)
ACC = (0xff, 0xf1, 0xb8)


def load(src):
    im = np.asarray(Image.open(src).convert("RGB")).astype(np.float32) / 255.0
    r, g, b = im[..., 0], im[..., 1], im[..., 2]
    mag = (r > 0.6) & (b > 0.6) & (g < 0.55) & (np.abs(r - b) < 0.35)
    fg = ~mag
    lab, n = ndimage.label(fg)
    sizes = ndimage.sum(fg, lab, range(1, n + 1))
    keep = np.isin(lab, 1 + np.flatnonzero(sizes >= sizes.max() * 0.02))   # 去掉小星点
    keep = ndimage.binary_fill_holes(keep) & fg | keep
    ys, xs = np.nonzero(keep)
    y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
    luma = 0.2126 * r + 0.7152 * g + 0.0722 * b
    return keep[y0:y1, x0:x1], luma[y0:y1, x0:x1]


def pixelize(mask, luma, h):
    w = max(4, int(round(mask.shape[1] * h / mask.shape[0])))
    m = np.asarray(Image.fromarray((mask * 255).astype(np.uint8)).resize((w, h), Image.BOX)) / 255.0
    l = np.asarray(Image.fromarray((luma * mask * 255).astype(np.uint8)).resize((w, h), Image.BOX)) / 255.0
    inside = m > 0.5
    lv = np.where(inside, l / np.maximum(m, 1e-3), 0)
    vals = lv[inside]
    qs = np.quantile(vals, [0.12, 0.35, 0.65, 0.88]) if vals.size else [0, 0, 0, 0]
    idx = np.full(lv.shape, -1, int)
    idx[inside] = np.digitize(lv[inside], qs)          # 0 = 最暗（深线 / 口里），1..4 = 4 阶金
    return inside, idx


def render(inside, idx, el, frame):
    """单帧 RGBA（美术像素），含 1 格外描边"""
    h, w = inside.shape
    out = np.zeros((h + 2, w + 2, 4), np.uint8)
    ins = np.zeros((h + 2, w + 2), bool)
    ins[1:-1, 1:-1] = inside
    ix = np.full((h + 2, w + 2), -1, int)
    ix[1:-1, 1:-1] = idx
    shift = 1 if frame == 0 else 0                     # 张口那一拍提亮一阶
    for yy in range(h + 2):
        for xx in range(w + 2):
            if ins[yy, xx]:
                k = ix[yy, xx]
                c = DEEP if k <= 0 else TONES[min(3, k - 1 + shift)]
                out[yy, xx] = (*c, 255)
    edge = ndimage.binary_dilation(ins) & ~ins
    oc = WHITE if frame <= 1 else (ACC if el >= 2 else OUTLINE)
    if frame >= 2 and el < 2:
        oc = OUTLINE
    out[edge] = (*oc, 255)
    if el >= 2 and frame >= 2:                         # 精二：外描边内侧再一圈白金（亮边）
        rim = ins & ndimage.binary_dilation(edge) & (ix >= 2)
        out[rim] = (*ACC, 255)
    return out


def dissolve(rgba, amt, seed):
    """从鬃毛尾端（左）往前散掉：越靠左越先去，按哈希逐像素"""
    h, w = rgba.shape[:2]
    yy, xx = np.mgrid[0:h, 0:w]
    hsh = ((xx * 73856093) ^ (yy * 19349663) ^ seed) % 1000 / 1000.0
    score = hsh * 0.5 + (xx / max(1, w - 1)) * 0.5   # 左（鬃毛尾端）分数低、先去
    out = rgba.copy()
    out[score < amt, 3] = 0
    return out


def build(src, el):
    mask, luma = load(src)
    scales = [0.7, 0.88, 1.0, 1.0, 1.0, 1.0, 1.0]
    dis = [0, 0, 0, 0, 0.35, 0.62, 0.86]
    frames = []
    for f, (sc, dv) in enumerate(zip(scales, dis)):
        inside, idx = pixelize(mask, luma, max(6, int(round(H * sc))))
        fr = render(inside, idx, el, f)
        if dv > 0:
            fr = dissolve(fr, dv, 7 + f)
        frames.append(fr)
    W = max(fr.shape[1] for fr in frames) + 2
    HH = max(fr.shape[0] for fr in frames) + 2
    strip = np.zeros((HH, W * len(frames), 4), np.uint8)
    emit = []
    for i, fr in enumerate(frames):
        fh, fw = fr.shape[:2]
        ox, oy = (W - fw) // 2, (HH - fh) // 2   # 每帧居中（中心固定）
        strip[oy:oy + fh, i * W + ox:i * W + ox + fw] = fr
        pts = []
        if i < 4:
            sub = fr
            m = (sub[..., 3] > 0) & ((sub[..., :3] == TONES[3]).all(-1) | (sub[..., :3] == WHITE).all(-1) | (sub[..., :3] == ACC).all(-1))
            py, px = np.nonzero(m)
            sel = np.linspace(0, len(px) - 1, min(48, len(px))).astype(int) if len(px) else []
            for j in sel:
                r, g, b = sub[py[j], px[j], :3]
                pts.append([int(px[j] + ox), int(py[j] + oy), "%02x%02x%02x" % (r, g, b)])
        emit.append(pts)
    # 原点 = 脚底：狮头中心（W/2, HH/2）在脚底右 CX、上 CZ
    meta = {"n": len(frames), "fps": 15, "w": W, "h": HH, "ox": int(W // 2 - CX), "oy": int(HH // 2 + CZ), "loop": False, "emit": emit}
    return strip, meta, frames


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", required=True)
    ap.add_argument("--sheet", default="")
    ap.add_argument("--cands", default="")
    a = ap.parse_args()
    mp = os.path.join(ROOT, "game", "data", "pxp_siege.json")
    reg = json.load(open(mp, encoding="utf-8"))
    big = None
    for el in (0, 1, 2):
        strip, meta, frames = build(a.src, el)
        Image.fromarray(strip, "RGBA").save(os.path.join(ROOT, "game", "art", "fx", "pxp", "pxp_sg_lion_e%d_up.png" % el), optimize=True)
        reg["sg_lion_e%d_up" % el] = meta
        if el == 2:
            big = frames
        print("sg_lion_e%d_up" % el, meta["n"], "帧", meta["w"], "x", meta["h"])
    doc = reg.pop("_doc", "")
    reg = {k: reg[k] for k in sorted(reg)}
    reg["_doc"] = doc
    json.dump(reg, open(mp, "w", encoding="utf-8"), ensure_ascii=False, separators=(",", ":"))
    if a.sheet:   # 候选原图 → 像素化后 对照图
        cands = sorted(glob.glob(os.path.join(a.cands, "raw_*.png"))) if a.cands else [a.src]
        cw = 220
        sheet = Image.new("RGB", (max(cw * len(cands), 400 + 7 * 150), cw + 40 + 260), (24, 26, 28))
        d = ImageDraw.Draw(sheet)
        try:
            fnt = ImageFont.truetype("C:/Windows/Fonts/msyh.ttc", 14)
        except OSError:
            fnt = ImageFont.load_default()
        for i, c in enumerate(cands):
            im = Image.open(c).convert("RGB").resize((cw - 10, cw - 10))
            sheet.paste(im, (i * cw + 5, 30))
            sel = os.path.abspath(c) == os.path.abspath(a.src)
            if sel:
                d.rectangle([i * cw + 2, 27, i * cw + cw - 3, cw + 22], outline=(255, 200, 60), width=3)
            d.text((i * cw + 8, 8), ("采用 " if sel else "") + "候选 %d" % (i + 1), fill=(230, 220, 200), font=fnt)
        y = cw + 50
        full = big[2]
        f1 = Image.fromarray(full, "RGBA")
        bg = Image.new("RGBA", f1.size, (36, 46, 48, 255))
        bg.alpha_composite(f1)
        for k, sc in enumerate((1, 2, 4)):
            sheet.paste(bg.resize((f1.width * sc, f1.height * sc), Image.NEAREST).convert("RGB"), (10 + [0, 60, 160][k], y))
        d.text((10, y - 18), "像素化（精二）：1 倍 / 2 倍 / 4 倍（美术像素；实机再 ×2）", fill=(200, 200, 200), font=fnt)
        xs = 400
        for i, fr in enumerate(big):
            im = Image.fromarray(fr, "RGBA")
            b2 = Image.new("RGBA", (fr.shape[1], fr.shape[0]), (36, 46, 48, 255))
            b2.alpha_composite(im)
            sheet.paste(b2.resize((fr.shape[1] * 3, fr.shape[0] * 3), Image.NEAREST).convert("RGB"), (xs + i * 150, y + 20))
        d.text((xs, y - 18), "帧条 7 帧（15 fps）：张口 → 吼出 → 停 → 散掉（×3）", fill=(200, 200, 200), font=fnt)
        sheet.save(a.sheet)
        print(a.sheet)


if __name__ == "__main__":
    main()
