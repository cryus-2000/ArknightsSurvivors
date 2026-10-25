# -*- coding: utf-8 -*-
"""docs/156 事件 CG 像素化草稿：D:/Anaconda/python.exe tools/probes/event_cg_pixel_draft.py [编号 ...]
读主仓库 build/event_cg/Avg_pic_rogue_2_<n>.png（PRTS 原图，只作内部参照，不进 git / 包），
按事件面板插画框比例 560:500 裁出主体 → 缩到 140×125 美术像素 → 64 色量化（中位切分 + 不抖动）→ ×4 最近邻放大，
输出 build/event_cg/draft_<n>.png 与对比图 build/event_cg/compare_<n>.png（左原图裁切 | 右 64 色草稿）、总表 compare_all.png。
草稿只看「能不能读出主体」，正式重构交 Codex。"""
import sys
import pathlib
from PIL import Image, ImageDraw, ImageFont

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools'))
import godot_runner as gr
D = pathlib.Path(gr.common_root()) / 'build' / 'event_cg'   # 主仓库 build/（各工作树共用，不进 git）
# 编号: (事件名, 裁切中心 x 比例, 中心 y 比例, 裁切宽占原图比例)；中心按主体位置手调
CROPS = {
    25: ('开端', 0.50, 0.50, 0.66),
    23: ('狂徒妄念', 0.56, 0.48, 0.62),
    57: ('升华', 0.50, 0.52, 0.66),
    24: ('骑士仍在', 0.55, 0.50, 0.62),
    56: ('深蓝仪式', 0.50, 0.50, 0.70),
    6: ('点滴星火', 0.52, 0.52, 0.56),
}
AW, AH = 140, 125   # 美术像素：事件面板插画框 560×500 的 1/4（1 美术像素 = 4 屏幕像素，接近局内粗像素观感）
K = 4
COLORS = 64


def crop(im, cx, cy, wk):
    w, h = im.size
    cw = int(w * wk)
    ch = int(cw * AH / AW)
    if ch > h:
        ch = h
        cw = int(ch * AW / AH)
    x0 = min(max(0, int(w * cx - cw / 2)), w - cw)
    y0 = min(max(0, int(h * cy - ch / 2)), h - ch)
    return im.crop((x0, y0, x0 + cw, y0 + ch))


def draft(n):
    name, cx, cy, wk = CROPS[n]
    src = Image.open(D / ('Avg_pic_rogue_2_%d.png' % n)).convert('RGB')
    c = crop(src, cx, cy, wk)
    small = c.resize((AW, AH), Image.LANCZOS)
    q = small.quantize(colors=COLORS, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).convert('RGB')
    big = q.resize((AW * K, AH * K), Image.NEAREST)
    big.save(D / ('draft_%d.png' % n))
    ref = c.resize((AW * K, AH * K), Image.LANCZOS)
    f = ImageFont.truetype('C:/Windows/Fonts/msyh.ttc', 22)
    out = Image.new('RGB', (AW * K * 2 + 24, AH * K + 44), (12, 14, 18))
    out.paste(ref, (8, 36))
    out.paste(big, (AW * K + 16, 36))
    dr = ImageDraw.Draw(out)
    dr.text((10, 6), '%s · 原图 Avg_pic_rogue_2_%d（裁到面板比例）' % (name, n), font=f, fill=(230, 226, 214))
    dr.text((AW * K + 18, 6), '草稿：140×125 美术像素 · 64 色 · ×4 显示', font=f, fill=(242, 196, 109))
    out.save(D / ('compare_%d.png' % n))
    return out


if __name__ == '__main__':
    ns = [int(x) for x in sys.argv[1:]] or [25, 23, 57]
    rows = [draft(n) for n in ns]
    sheet = Image.new('RGB', (rows[0].width, sum(r.height for r in rows)), (12, 14, 18))
    y = 0
    for r in rows:
        sheet.paste(r, (0, y))
        y += r.height
    sheet.save(D / 'compare_all.png')
    print(D / 'compare_all.png', sheet.size)
