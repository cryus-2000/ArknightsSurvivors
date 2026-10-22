"""特效 TA 审阅取证（docs/127 §6）：art/incoming/fx_*.png 全量量化（只读资源）。
指标：帧数 / 单帧尺寸 / 有无 @2x、像素格（k×k 对齐块同色率，k = 1–4 取最大成立的 k）、半透明率（软光 vs 硬边）、色数、
平均色相 / 饱和 / 明度、近白像素占比（加法叠加过曝风险）、代码与数据里的引用次数（0 = 没用到）、归属（文件名前缀 → 干员 / 敌人 / 通用）。
用法：python -X utf8 tools/probes/ta_fx_review.py
输出：主仓库 build/ta_review/fx_metrics.json、fx_grid_alpha.png（像素格 × 半透明散点）、fx_by_owner.png（按归属分组的首帧总览）
"""
import colorsys
import glob
import json
import os
import re
import subprocess
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
_gc = subprocess.run(["git", "rev-parse", "--git-common-dir"], cwd=ROOT, capture_output=True, text=True).stdout.strip()
COMMON = os.path.dirname(_gc if os.path.isabs(_gc) else os.path.join(ROOT, _gc))
OUT = os.path.join(COMMON, "build", "ta_review")
INC = os.path.join(ROOT, "art", "incoming")
FONT = ImageFont.truetype("C:/Windows/Fonts/msyh.ttc", 13)
FS = ImageFont.truetype("C:/Windows/Fonts/msyh.ttc", 10)
os.makedirs(OUT, exist_ok=True)

OPS = sorted(os.path.basename(p)[:-5] for p in glob.glob(os.path.join(ROOT, "game", "data", "characters", "*.json")))
ALIAS = {"specter": "specter_unchained", "eyja": "eyjafjalla", "mon3tr": "kaltsit", "holy": "suzuran", "umbrella": "mizuki", "tendril": "mizuki",
         "seaborn": "", "skalter": "skalter", "doll": "specter_unchained", "lighthouse": "lumen", "hh": "UI 寻访"}
ENEMY_WORDS = ["acid", "brood", "mother", "spitter", "nest", "skimmer", "pocket", "mire", "corrode", "knight", "tide", "tear", "mimic",
               "slider", "reaper", "founder", "tracer", "fractal", "paranoia", "ishar", "izumik", "path", "saint", "bishop", "archon", "immortal", "kraken"]

# 代码与数据全文（数引用）
src = []
for p in glob.glob(os.path.join(ROOT, "game", "scripts", "**", "*.gd"), recursive=True) + glob.glob(os.path.join(ROOT, "game", "data", "**", "*.json"), recursive=True):
    src.append(open(p, encoding="utf8", errors="ignore").read())
SRC = "\n".join(src)


def owner(name):
    b = name[3:]
    head = b.split("_")[0]
    for o in OPS:
        if b.startswith(o):
            return o
    if head in ALIAS:
        return ALIAS[head] or "敌人"
    if any(b.startswith(w) for w in ENEMY_WORDS):
        return "敌人"
    return "通用"


def grid_of(fr):
    px = fr.load()
    W, H = fr.size
    best = 1
    rates = {}
    for k in (2, 3, 4):
        same = blk = 0
        for y in range(0, H - k + 1, k):
            for x in range(0, W - k + 1, k):
                q = [px[x + i, y + j] for j in range(k) for i in range(k)]
                if all(p[3] > 200 for p in q):
                    blk += 1
                    if q.count(q[0]) == len(q):
                        same += 1
        r = same / blk if blk else 0.0
        rates[k] = round(r, 2)
        if blk >= 8 and r >= 0.85:
            best = k
    return best, rates


names = sorted(set(re.sub(r"(@2x)?\.png$", "", os.path.basename(p)) for p in glob.glob(os.path.join(INC, "fx_*.png"))))
rows = []
for n in names:
    p2 = os.path.join(INC, n + "@2x.png")
    p1 = os.path.join(INC, n + ".png")
    p = p2 if os.path.exists(p2) else p1
    im = Image.open(p).convert("RGBA")
    nfr = max(1, round(im.width / im.height))
    fw = im.width // nfr
    fr0 = im.crop((0, 0, fw, im.height))
    mid = im.crop((fw * (nfr // 2), 0, fw * (nfr // 2) + fw, im.height))
    pix = [q for q in im.getdata() if q[3] > 10]
    if not pix:
        continue
    semi = sum(1 for q in pix if q[3] < 245) / len(pix)
    sample = pix[::max(1, len(pix) // 4000)]
    hsv = [colorsys.rgb_to_hsv(q[0] / 255, q[1] / 255, q[2] / 255) for q in sample]
    hue = sum(h[0] for h in hsv) / len(hsv)
    sat = sum(h[1] for h in hsv) / len(hsv)
    val = sum(h[2] for h in hsv) / len(hsv)
    near_white = sum(1 for h in hsv if h[2] > 0.92 and h[1] < 0.2) / len(hsv)
    g, rates = grid_of(mid if mid.getbbox() else fr0)
    refs = len(re.findall(r"\b%s\b" % re.escape(n), SRC))
    rows.append({"name": n, "owner": owner(n), "frames": nfr, "w": fw, "h": im.height, "hi2x": os.path.exists(p2), "lo1x": os.path.exists(p1),
                 "grid": g, "grid_rates": rates, "semi": round(semi, 3), "colors": len(set(q[:3] for q in sample)),
                 "hue": round(hue, 3), "sat": round(sat, 3), "val": round(val, 3), "near_white": round(near_white, 3), "refs": refs})
json.dump(rows, open(os.path.join(OUT, "fx_metrics.json"), "w", encoding="utf8"), ensure_ascii=False, indent=1)

# 散点：x = 像素格（屏幕像素：@2x 的 grid 即屏幕像素，1x 乘 2），y = 半透明率
img = Image.new("RGB", (900, 560), (20, 22, 28))
dr = ImageDraw.Draw(img)
dr.text((10, 8), "特效像素格（屏幕像素）× 半透明率：右下 = 粗格硬边，左上 = 细格软光；点色 = 平均色相，空心 = 代码 / 数据未引用", font=FONT, fill=(230, 230, 230))
import random
random.seed(3)
for gx in range(1, 9):
    x = 60 + gx * 95
    dr.line([(x, 40), (x, 520)], fill=(45, 48, 56))
    dr.text((x - 6, 525), "%d px" % gx, font=FS, fill=(180, 180, 180))
for gy in range(0, 11, 2):
    y = 520 - gy * 46
    dr.line([(60, y), (880, y)], fill=(45, 48, 56))
    dr.text((20, y - 6), "%.1f" % (gy / 10), font=FS, fill=(180, 180, 180))
for r in rows:
    scr = r["grid"] * (1 if r["hi2x"] else 2)
    x = 60 + scr * 95 + random.uniform(-30, 30)
    y = 520 - min(1.0, r["semi"]) * 460 + random.uniform(-4, 4)
    c = tuple(int(v * 255) for v in colorsys.hsv_to_rgb(r["hue"], max(0.5, r["sat"]), 0.95))
    if r["refs"] == 0:
        dr.ellipse([x - 5, y - 5, x + 5, y + 5], outline=c, width=1)
    else:
        dr.ellipse([x - 4, y - 4, x + 4, y + 4], fill=c)
img.save(os.path.join(OUT, "fx_grid_alpha.png"))

# 按归属分组总览
groups = {}
for r in rows:
    groups.setdefault(r["owner"], []).append(r)
order = sorted(groups, key=lambda k: (k in ("通用", "敌人", "UI 寻访"), k))
cell = 84
cols = 14
H = 30
for k in order:
    H += 22 + ((len(groups[k]) + cols - 1) // cols) * (cell + 26)
out = Image.new("RGB", (cols * cell + 20, H), (14, 18, 26))
dr = ImageDraw.Draw(out)
y = 8
dr.text((8, y), "特效按归属分组（首帧中帧，缩到 76 px 内，最近邻）· 每格：名字 / 帧数×尺寸 / 像素格·半透明 · 红框 = 未引用", font=FONT, fill=(230, 230, 230))
y += 24
for k in order:
    dr.text((8, y), "%s（%d）" % (k, len(groups[k])), font=FONT, fill=(255, 210, 120))
    y += 20
    for i, r in enumerate(groups[k]):
        x = 8 + (i % cols) * cell
        yy = y + (i // cols) * (cell + 26)
        p = os.path.join(INC, r["name"] + ("@2x" if r["hi2x"] else "") + ".png")
        im = Image.open(p).convert("RGBA")
        f = im.crop((r["w"] * (r["frames"] // 2), 0, r["w"] * (r["frames"] // 2) + r["w"], r["h"]))
        bb = f.getbbox()
        if bb:
            f = f.crop(bb)
            f.thumbnail((76, 76), Image.NEAREST)
            out.paste(f, (x + (cell - f.width) // 2, yy + (76 - f.height) // 2), f)
        if r["refs"] == 0:
            dr.rectangle([x + 1, yy, x + cell - 3, yy + 78], outline=(230, 70, 70))
        dr.text((x, yy + 78), r["name"][3:15], font=FS, fill=(210, 210, 210))
        dr.text((x, yy + 90), "%d×%d g%d a%.2f" % (r["frames"], r["w"], r["grid"] * (1 if r["hi2x"] else 2), r["semi"]), font=FS, fill=(140, 190, 230))
    y += ((len(groups[k]) + cols - 1) // cols) * (cell + 26)
out.save(os.path.join(OUT, "fx_by_owner.png"))
print(len(rows), "fx")
