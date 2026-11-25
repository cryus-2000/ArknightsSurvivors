"""萨米 HUD：灯火位改为坍缩显示的样张（docs/413 §6，11-25）。

原作查证（build/collapse_ref/，不进 git）：
- 坍缩值详情面板（小米游戏中心攻略配图 xiaomi_1.png）：左上坍缩图标（白色圆盘被黑烟吞蚀、中心黑洞、外圈紫光）+ 大字「12/15」（当前值 / 下一级阈值）
  +「当前坍缩值」；下一行紫条：眼睛图标 +「坍缩到达下一层级将触发：情绪实体」（预告）。
- 战斗内原作没有坍缩数值 UI（未查到）；地图顶部圆盘的大号数字是抗干扰指数，不是坍缩值；坍缩等级是圆盘下的黑色烟环。
本作：底部指挥台原灯火位 = 坍缩图标（照原作圆盘吞蚀样式，程序画近似，进包换客户端原图）+「坍缩 · 等级 n」+ 坍缩值条（到下一级阈值）+ 右侧「当前 / 阈值」紫字；
距下一级 ≤ 2 点时，状态行上方出原作式预告条：眼睛图标 +「将触发：<范式>」（加深时「将加深：<范式>」），轻微呼吸。
用法：python tools/probes/sami_collapse_hud_mock.py <出图目录> <游戏截图（萨米局内、指挥台 HUD）>
"""
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

S = 2
CJK_B = "C:/Windows/Fonts/Noto Sans SC Bold (TrueType).otf"
CJK = "C:/Windows/Fonts/Noto Sans SC (TrueType).otf"
PURPLE = (111, 69, 195)        # #6f45c3 坍缩紫（docs/397 §7.1）
PURPLE_HI = (178, 150, 236)
INK = (230, 233, 235)
SUB = (150, 156, 160)


def F(p, px):
    return ImageFont.truetype(p, int(px * S))


def P(v):
    return int(round(v * S))


def collapse_icon(r):
    """原作坍缩图标的程序近似：白色圆盘、黑烟楔块吞蚀、中心黑洞、外圈紫光（xiaomi_1.png 左上）"""
    n = P(r * 2 + 20)
    im = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    c = n / 2
    glow = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.ellipse([c - P(r + 7), c - P(r + 7), c + P(r + 7), c + P(r + 7)], fill=PURPLE + (150,))
    glow = glow.filter(ImageFilter.GaussianBlur(P(4)))
    im.alpha_composite(glow)
    d = ImageDraw.Draw(im)
    d.ellipse([c - P(r), c - P(r), c + P(r), c + P(r)], fill=(232, 232, 238, 255))
    rng = np.random.default_rng(4)
    for k in range(4):   # 黑烟团：从边缘往中心卷入（原作是不规则烟块，不是规整扇叶）
        a0 = k * math.tau / 4 + rng.uniform(-0.5, 0.5)
        pts = []
        for j in range(9):
            t = j / 8
            ang = a0 + t * 0.9 + 0.25 * math.sin(t * 5 + k)
            rr = P(r) * (1.02 - 0.72 * t)
            pts.append((c + rr * math.cos(ang), c + rr * math.sin(ang)))
        for j in range(8, -1, -1):
            t = j / 8
            ang = a0 + t * 0.9 + 0.55 - 0.3 * t
            rr = P(r) * (1.02 - 0.6 * t)
            pts.append((c + rr * math.cos(ang), c + rr * math.sin(ang)))
        d.polygon(pts, fill=(18, 16, 24, 235))
    d.ellipse([c - P(r * 0.28), c - P(r * 0.28), c + P(r * 0.28), c + P(r * 0.28)], fill=(6, 5, 9, 255))
    return im


def eye_icon(w):
    """预告条的眼睛（原作预告行用眼睛图标）：线描杏仁眼 + 实心瞳"""
    h = w * 0.55
    im = Image.new("RGBA", (P(w), P(h)), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    pts_t, pts_b = [], []
    for i in range(25):
        x = i / 24
        y = math.sin(x * math.pi)
        pts_t.append((P(x * w), P(h / 2 - y * h * 0.46)))
        pts_b.append((P(x * w), P(h / 2 + y * h * 0.46)))
    d.line(pts_t, fill=INK + (255,), width=P(1.6))
    d.line(pts_b, fill=INK + (255,), width=P(1.6))
    d.ellipse([P(w / 2 - h * 0.3), P(h / 2 - h * 0.3), P(w / 2 + h * 0.3), P(h / 2 + h * 0.3)], outline=INK + (255,), width=P(1.6))
    d.ellipse([P(w / 2 - h * 0.13), P(h / 2 - h * 0.13), P(w / 2 + h * 0.13), P(h / 2 + h * 0.13)], fill=INK + (255,))
    return im


def tw(d, s, f):
    return d.textlength(s, font=f) / S


def draw_variant(base, val, thr_prev, thr_next, level, warn):
    img = base.resize((base.width * S, base.height * S), Image.LANCZOS).convert("RGBA")
    d = ImageDraw.Draw(img, "RGBA")
    # 左侧整块压一块托底板（docs/397 §7.4：亮雪原上 HUD 一律压 PLATE），重画生命行
    plate = Image.new("RGBA", (P(314), P(68)), (0, 0, 0, 0))
    pd = ImageDraw.Draw(plate)
    for i in range(P(314)):
        a = 252
        pd.line([(i, 0), (i, P(68))], fill=(8, 11, 14, a))
    img.alpha_composite(plate, (P(292), P(632)))
    d.rectangle([P(292), P(700), P(372), P(718)], fill=(8, 11, 14, 252))   # 灯笼底座
    d.line([(P(292), P(632)), (P(606), P(632))], fill=(255, 255, 255, 60), width=P(1))
    d.text((P(373), P(660)), "生命", font=F(CJK, 11), fill=SUB + (255,))
    hp = "152"
    rx0 = 604 - tw(d, "/ 152", F(CJK, 10))
    d.text((P(rx0), P(664)), "/ 152", font=F(CJK, 10), fill=SUB + (255,))
    d.text((P(rx0 - 4 - tw(d, hp, F(CJK_B, 24))), P(646)), hp, font=F(CJK_B, 24), fill=INK + (255,))
    d.rectangle([P(373), P(677), P(604), P(679)], fill=(235, 238, 240, 255))
    # 坍缩图标（原灯笼位）
    ic = collapse_icon(19)
    img.alpha_composite(ic, (P(334) - ic.width // 2, P(676) - ic.height // 2))
    # 状态行：坍缩 · 等级 n
    d.text((P(373), P(640)), "坍缩", font=F(CJK_B, 12), fill=PURPLE_HI + (255,))
    d.text((P(373 + 30), P(640)), "· 等级 %d" % level, font=F(CJK, 12), fill=SUB + (255,))
    # 坍缩值条（原灯火条位）：到下一级阈值的进度，等级刻度
    x0, x1, y = 373, 548, 690
    d.text((P(373 - 1), P(683)), "坍缩", font=F(CJK_B, 11), fill=PURPLE_HI + (255,))
    bx0 = 404
    d.rectangle([P(bx0), P(y), P(x1), P(y + 5)], fill=(40, 32, 60, 220))
    k = (val - thr_prev) / max(1, thr_next - thr_prev)
    d.rectangle([P(bx0), P(y), P(bx0 + (x1 - bx0) * k), P(y + 5)], fill=PURPLE + (255,))
    for i in range(1, thr_next - thr_prev):
        tx = bx0 + (x1 - bx0) * i / (thr_next - thr_prev)
        d.line([(P(tx), P(y - 1)), (P(tx), P(y + 6))], fill=(10, 10, 14, 200), width=P(1))
    vs = "%d" % val
    ts = "/ %d" % thr_next
    rx = 604 - tw(d, ts, F(CJK, 11))
    d.text((P(rx), P(686)), ts, font=F(CJK, 11), fill=SUB + (255,))
    d.text((P(rx - 3 - tw(d, vs, F(CJK_B, 17))), P(679)), vs, font=F(CJK_B, 17), fill=(PURPLE_HI if warn else INK) + (255,))
    # 临近升级：原作式预告条（眼睛 + 将触发）
    if warn:
        pw = 236
        py = 612
        bar = Image.new("RGBA", (P(pw), P(22)), (0, 0, 0, 0))
        bd = ImageDraw.Draw(bar)
        for i in range(P(pw)):
            a = int(200 * (1 - i / P(pw) * 0.7))
            bd.line([(i, 0), (i, P(22))], fill=PURPLE + (a,))
        img.alpha_composite(bar, (P(300), P(py)))
        e = eye_icon(20)
        img.alpha_composite(e, (P(308), P(py + 11) - e.height // 2))
        d.text((P(334), P(py + 2)), "将触发：情绪实体", font=F(CJK_B, 12), fill=INK + (255,))
        d.text((P(300 + pw - 6 - tw(d, "还差 1", F(CJK, 10))), P(py + 5)), "还差 1", font=F(CJK, 10), fill=(220, 210, 240, 255))
    return img.resize(base.size, Image.LANCZOS).convert("RGB")


def main():
    od, shot = sys.argv[1], sys.argv[2]
    os.makedirs(od, exist_ok=True)
    base = Image.open(shot).convert("RGB")
    a = draw_variant(base, 9, 8, 12, 2, False)
    b = draw_variant(base, 14, 12, 15, 3, True)
    a.save(os.path.join(od, "sami_hud_collapse_a.png"))
    b.save(os.path.join(od, "sami_hud_collapse_b.png"))
    # 对照条：原（灯火）/ A 平时 / B 临近升级，各裁底部一段放大
    crops = [base, a, b]
    labels = ["现在（水月灯火）", "萨米 · 平时（坍缩值 9 / 12，等级 2）", "萨米 · 临近升级（14 / 15，出预告条）"]
    rows = []
    for im, lb in zip(crops, labels):
        c = im.crop((240, 596, 1040, 720)).resize((1600, 248), Image.LANCZOS)
        r = Image.new("RGB", (1600, 248 + 30), (12, 14, 16))
        r.paste(c, (0, 30))
        ImageDraw.Draw(r).text((8, 4), lb, font=ImageFont.truetype(CJK, 18), fill=(220, 224, 226))
        rows.append(r)
    sheet = Image.new("RGB", (1600, sum(r.height for r in rows)), (12, 14, 16))
    y = 0
    for r in rows:
        sheet.paste(r, (0, y))
        y += r.height
    sheet.save(os.path.join(od, "sami_hud_collapse_compare.png"))
    print("ok")


if __name__ == "__main__":
    main()
