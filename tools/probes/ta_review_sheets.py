"""TA 审阅取证（docs/127）：从 art/incoming 帧条直接拼对照图 + 量化指标（只读资源）。
  ① ops_lineup_<bg>.png / enemies_lineup_<bg>.png：真实缩放（@2x 帧条 1 像素 = 屏幕 1 像素 × draw_scale，镜头 100%）下 待机 f0 / 攻击中帧 / 受击白闪，三种底色
  ② equal_height_ops.png / equal_height_enemies.png：帧条等高对照（同一高度看头身比、像素密度、描边粗细）
  ③ metrics.json + metric_bars.png：像素密度（2×2 块同色率）、半透明像素率、调色板色数、明度直方图、外轮廓暗边率、受光方向
  ④ fx_sheet.png：特效帧条首帧 + 色相 / 明度统计
用法：python -X utf8 tools/probes/ta_review_sheets.py
输出：主仓库 build/ta_review/
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
os.makedirs(OUT, exist_ok=True)
FONT = ImageFont.truetype("C:/Windows/Fonts/msyh.ttc", 13)
FONT_S = ImageFont.truetype("C:/Windows/Fonts/msyh.ttc", 11)
BGS = {"shallow": (40, 74, 88), "deep": (13, 21, 34), "boss": (26, 12, 36)}
BG_CN = {"shallow": "浅滩（取样底色）", "deep": "深海（游戏内地面均色）", "boss": "Boss 场（暗紫）"}


def load(tex):
    for n in (tex + "@2x.png", tex + ".png"):
        p = os.path.join(INC, n)
        if os.path.exists(p):
            return Image.open(p).convert("RGBA"), (2 if "@2x" in n else 1)
    return None, 0


def frame(im, n, i):
    fw = im.width // max(1, n)
    return im.crop((fw * i, 0, fw * i + fw, im.height))


def white(fr):
    a = fr.split()[3]
    w = Image.new("RGBA", fr.size, (255, 255, 255, 0))
    w.putalpha(a)
    return w


def lum(c):
    return (0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]) / 255.0


def metrics(fr):
    px = fr.load()
    W, H = fr.size
    op = [[px[x, y][3] > 200 for x in range(W)] for y in range(H)]
    cols = set()
    semi = 0
    tot = 0
    hist = [0] * 10
    L = R = T = B = 0.0
    nl = nr = nt = nb = 0
    ys = []
    xs = []
    for y in range(H):
        for x in range(W):
            a = px[x, y][3]
            if 10 < a <= 200:
                semi += 1
            if a > 200:
                tot += 1
                c = px[x, y][:3]
                cols.add(c)
                v = lum(c)
                hist[min(9, int(v * 10))] += 1
                xs.append(x)
                ys.append(y)
    if tot == 0:
        return None
    x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys)
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            if op[y][x]:
                v = lum(px[x, y][:3])
                if x < cx:
                    L += v; nl += 1
                else:
                    R += v; nr += 1
                if y < cy:
                    T += v; nt += 1
                else:
                    B += v; nb += 1
    # 2×2 块同色率（≈1 = 1x 美术放大；低 = 真 2x 细节）
    same = blk = 0
    for y in range(0, H - 1, 2):
        for x in range(0, W - 1, 2):
            q = [px[x, y], px[x + 1, y], px[x, y + 1], px[x + 1, y + 1]]
            if all(p[3] > 200 for p in q):
                blk += 1
                if q.count(q[0]) == 4:
                    same += 1
    # 外轮廓暗边：不透明且四邻有透明的像素里，明度 < 0.22 的比例；再往里一圈也暗 = 2 px 描边
    edge = dark = dark2 = 0
    for y in range(1, H - 1):
        for x in range(1, W - 1):
            if not op[y][x]:
                continue
            nb4 = [op[y - 1][x], op[y + 1][x], op[y][x - 1], op[y][x + 1]]
            if all(nb4):
                continue
            edge += 1
            if lum(px[x, y][:3]) < 0.22:
                dark += 1
                # 朝内一格
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    if not op[y - dy][x - dx] and op[y + dy][x + dx]:
                        if lum(px[x + dx, y + dy][:3]) < 0.22:
                            dark2 += 1
                        break
    vals = sorted(lum(px[x, y][:3]) for y in range(H) for x in range(W) if px[x, y][3] > 200)
    return {"h": y1 - y0 + 1, "w": x1 - x0 + 1, "colors": len(cols), "semi": round(semi / max(1, tot + semi), 3),
            "block2": round(same / max(1, blk), 3), "hist": [round(h / tot, 3) for h in hist],
            "l_mean": round(sum(vals) / len(vals), 3), "l_p5": round(vals[len(vals) // 20], 3), "l_p95": round(vals[len(vals) * 19 // 20], 3),
            "edge_dark": round(dark / max(1, edge), 3), "edge_dark2": round(dark2 / max(1, dark), 3),
            "light_lr": round(L / max(1, nl) - R / max(1, nr), 3), "light_tb": round(T / max(1, nt) - B / max(1, nb), 3)}


def strip_frames(im, h_frame):
    return max(1, round(im.width / h_frame)) if h_frame else 1


# ---------------- 收集 ----------------
ops = []
for f in sorted(glob.glob(os.path.join(ROOT, "game", "data", "characters", "*.json"))):
    c = json.load(open(f, encoding="utf8"))
    s = c.get("sprites", {})
    oid = os.path.basename(f)[:-5]

    def slot(k):
        v = s.get(k)
        if v is None:
            return None
        t = v if isinstance(v, str) else v.get("tex")
        im, d = load(t)
        if im is None:
            return None
        n = v.get("frames") if isinstance(v, dict) and v.get("frames") else strip_frames(im, im.height)
        return {"tex": t, "im": im, "n": int(n), "d": d}
    ops.append({"id": oid, "name": c.get("name", oid), "ds": float(s.get("draw_scale", 1.0)), "size": s.get("size", 64),
                "idle": slot("idle"), "attack": slot("attack"), "fps": (s.get("idle") or {}).get("fps") if isinstance(s.get("idle"), dict) else None})
E = json.load(open(os.path.join(ROOT, "game", "data", "enemies.json"), encoding="utf8"))["enemies"]
ens = []
for k, v in E.items():
    im, d = load(v["tex"])
    at, d2 = load(v["tex"] + "_attack")
    if im is None:
        continue
    ens.append({"id": k, "name": v.get("name", k), "role": v.get("role", "normal"), "ds": float(v.get("draw_scale", 1.0)),
                "idle": {"im": im, "n": strip_frames(im, im.height), "d": d}, "attack": {"im": at, "n": strip_frames(at, at.height), "d": d2} if at else None})


def three(ent):
    """待机 f0 / 攻击中帧 / 白闪 —— 帧条原始像素（@2x）"""
    i = ent["idle"]
    f0 = frame(i["im"], i["n"], 0)
    a = ent.get("attack")
    fa = frame(a["im"], a["n"], a["n"] // 2) if a else None
    return f0, fa, white(f0), i["d"]


def real_scale(img, d, ds):
    k = (2.0 / d) * ds   # 屏幕像素 / 帧条像素：@2x → 1 × draw_scale；1x → 2 × draw_scale
    w, h = max(1, round(img.width * k)), max(1, round(img.height * k))
    return img.resize((w, h), Image.NEAREST), k


def lineup(items, bg, name, cols_per_row=10, title=""):
    cells = []
    for ent in items:
        f0, fa, fw, d = three(ent)
        ims = []
        for fr in (f0, fa, fw):
            if fr is None:
                ims.append(None)
                continue
            r, k = real_scale(fr, d, ent["ds"])
            ims.append(r)
        cells.append((ent, ims, k))
    rows = [cells[i:i + cols_per_row] for i in range(0, len(cells), cols_per_row)]
    pad = 10
    blocks = []
    for row in rows:
        cw = [max(max((im.width for im in c[1] if im is not None), default=40), 90) for c in row]
        ch = max(max((im.height for im in c[1] if im is not None), default=40) for c in row)
        blocks.append((row, cw, ch))
    W = max(sum(cw) + pad * (len(cw) + 1) for _, cw, _ in blocks)
    H = sum(ch * 3 + 60 + pad * 4 for _, _, ch in blocks) + 30
    out = Image.new("RGB", (W, H), BGS[bg])
    dr = ImageDraw.Draw(out)
    dr.text((8, 6), "%s · %s · 镜头 100%%（1280×720 屏幕像素，未缩放本图）· 每列：待机 f0 / 攻击中帧 / 受击白闪" % (title, BG_CN[bg]), font=FONT, fill=(230, 230, 230))
    y = 30
    for row, cw, ch in blocks:
        x = pad
        for (ent, ims, k), w in zip(row, cw):
            for r, im in enumerate(ims):
                if im is None:
                    dr.text((x + 4, y + r * (ch + pad) + ch // 2), "（无攻击帧）", font=FONT_S, fill=(160, 160, 160))
                    continue
                out.paste(im, (x + (w - im.width) // 2, y + r * (ch + pad) + ch - im.height), im)
            dr.text((x, y + 3 * (ch + pad)), "%s" % ent["name"][:7], font=FONT_S, fill=(240, 240, 240))
            dr.text((x, y + 3 * (ch + pad) + 14), "×%.2f %s" % (k, "" if abs(k - round(k)) < 1e-6 else "非整数"), font=FONT_S, fill=(255, 200, 120) if abs(k - round(k)) > 1e-6 else (150, 200, 150))
            x += w + pad
        y += ch * 3 + 60 + pad * 4
    out.save(os.path.join(OUT, name))
    return name


def equal_height(items, name, H=200, title=""):
    cells = []
    for ent in items:
        f0 = frame(ent["idle"]["im"], ent["idle"]["n"], 0)
        bb = f0.getbbox()
        if bb is None:
            continue
        c = f0.crop(bb)
        k = H / c.height
        cells.append((ent, c.resize((max(1, round(c.width * k)), H), Image.NEAREST), k))
    cols = 10
    cw = max(c[1].width for c in cells) + 16
    rows = (len(cells) + cols - 1) // cols
    out = Image.new("RGB", (cw * cols + 16, rows * (H + 70) + 40), (128, 128, 128))
    dr = ImageDraw.Draw(out)
    dr.text((8, 8), "%s · 待机 f0 裁到身体包围盒后统一缩到 %d 高（最近邻）：看头身比、像素格大小、描边粗细、受光方向" % (title, H), font=FONT, fill=(20, 20, 20))
    for i, (ent, im, k) in enumerate(cells):
        x, y = 8 + (i % cols) * cw, 34 + (i // cols) * (H + 70)
        out.paste(im, (x + (cw - im.width) // 2, y), im)
        m = ent.get("m", {})
        dr.text((x, y + H + 4), ent["name"][:8], font=FONT_S, fill=(10, 10, 10))
        dr.text((x, y + H + 18), "体高 %dpx · 放大 ×%.1f" % (m.get("h", 0), k), font=FONT_S, fill=(30, 30, 30))
        dr.text((x, y + H + 32), "块同色 %.2f · 色 %d" % (m.get("block2", 0), m.get("colors", 0)), font=FONT_S, fill=(30, 30, 30))
    out.save(os.path.join(OUT, name))


# ---------------- 指标 ----------------
allm = {}
for ent in ops + ens:
    f0 = frame(ent["idle"]["im"], ent["idle"]["n"], 0)
    m = metrics(f0)
    ent["m"] = m or {}
    allm[ent["id"]] = dict(m or {}, name=ent["name"], role=ent.get("role", "op"), ds=ent["ds"], density=ent["idle"]["d"],
                           frames_idle=ent["idle"]["n"], frames_attack=(ent["attack"] or {}).get("n") if ent.get("attack") else None,
                           strip_h=ent["idle"]["im"].height)
json.dump(allm, open(os.path.join(OUT, "metrics.json"), "w", encoding="utf8"), ensure_ascii=False, indent=1)

for bg in BGS:
    lineup(ops, bg, "ops_lineup_%s.png" % bg, 10, "干员 20 名")
    lineup([e for e in ens if e["role"] != "boss"], bg, "enemies_lineup_%s.png" % bg, 10, "普通怪 + 精英")
    lineup([e for e in ens if e["role"] == "boss"], bg, "bosses_lineup_%s.png" % bg, 5, "Boss")
equal_height(ops, "equal_height_ops.png", 200, "干员")
equal_height([e for e in ens if e["role"] != "boss"], "equal_height_enemies.png", 160, "普通怪 + 精英")
equal_height([e for e in ens if e["role"] == "boss"], "equal_height_bosses.png", 220, "Boss")

# 指标条形图：每个实体一行
keys = [("block2", "2×2块同色率", 1.0), ("semi", "半透明率", 0.3), ("colors", "色数", 160), ("edge_dark", "外沿暗边率", 1.0),
        ("l_mean", "明度均值", 1.0), ("light_lr", "受光 左-右", 0.3), ("light_tb", "受光 上-下", 0.3)]
rows = [(k, v) for k, v in allm.items()]
rh = 18
img = Image.new("RGB", (220 + len(keys) * 150 + 220, 40 + rh * len(rows)), (24, 26, 30))
dr = ImageDraw.Draw(img)
for j, (k, t, mx) in enumerate(keys):
    dr.text((220 + j * 150, 10), t, font=FONT_S, fill=(220, 220, 220))
dr.text((220 + len(keys) * 150, 10), "明度直方图（0→1）", font=FONT_S, fill=(220, 220, 220))
for i, (k, m) in enumerate(rows):
    y = 30 + i * rh
    dr.text((8, y), "%s [%s]" % (m["name"][:8], {"op": "干员", "boss": "Boss", "elite": "精英"}.get(m["role"], "普通")), font=FONT_S, fill=(230, 230, 230))
    for j, (kk, t, mx) in enumerate(keys):
        v = float(m.get(kk, 0))
        x0 = 220 + j * 150
        if kk.startswith("light"):
            c = x0 + 60
            dr.line([(c, y), (c, y + rh - 4)], fill=(90, 90, 90))
            dr.rectangle([min(c, c + v / mx * 60), y + 3, max(c, c + v / mx * 60), y + rh - 6], fill=(240, 190, 90))
        else:
            dr.rectangle([x0, y + 3, x0 + min(1.0, v / mx) * 120, y + rh - 6], fill=(90, 190, 240))
        dr.text((x0 + 124 if not kk.startswith("light") else x0 + 124, y), ("%.2f" % v) if kk != "colors" else str(int(v)), font=FONT_S, fill=(200, 200, 200))
    hx = 220 + len(keys) * 150
    for b, h in enumerate(m.get("hist", [])):
        g = int(25 + b * 23)
        dr.rectangle([hx + b * 20, y + rh - 4 - h * 40, hx + b * 20 + 16, y + rh - 4], fill=(g, g, g))
img.save(os.path.join(OUT, "metric_bars.png"))

# 特效首帧总览
fxs = sorted(set(re.sub(r"(@2x)?\.png$", "", os.path.basename(p)) for p in glob.glob(os.path.join(INC, "fx_*.png"))))
cells = []
for n in fxs:
    im, d = load(n)
    if im is None:
        continue
    f0 = frame(im, strip_frames(im, im.height), 0)
    bb = f0.getbbox()
    if not bb:
        continue
    f0 = f0.crop(bb)
    f0.thumbnail((96, 96), Image.NEAREST)
    px = [p for p in im.getdata() if p[3] > 40]
    if not px:
        continue
    hs = [colorsys.rgb_to_hsv(p[0] / 255, p[1] / 255, p[2] / 255) for p in px[::max(1, len(px) // 2000)]]
    hue = sum(h[0] for h in hs) / len(hs)
    val = sum(h[2] for h in hs) / len(hs)
    sat = sum(h[1] for h in hs) / len(hs)
    cells.append((n, f0, hue, sat, val))
cells.sort(key=lambda c: c[2])
cols = 12
out = Image.new("RGB", (cols * 112 + 10, ((len(cells) + cols - 1) // cols) * 140 + 30), (14, 18, 26))
dr = ImageDraw.Draw(out)
dr.text((8, 6), "特效帧条首帧（按平均色相排序）：%d 张 · 每格下方 色相 / 饱和 / 明度" % len(cells), font=FONT, fill=(220, 220, 220))
for i, (n, im, h, s, v) in enumerate(cells):
    x, y = 6 + (i % cols) * 112, 28 + (i // cols) * 140
    out.paste(im, (x + (104 - im.width) // 2, y + (96 - im.height) // 2), im)
    dr.text((x, y + 98), n[3:17], font=FONT_S, fill=(210, 210, 210))
    dr.text((x, y + 112), "H%.2f S%.2f V%.2f" % (h, s, v), font=FONT_S, fill=(150, 200, 230))
out.save(os.path.join(OUT, "fx_sheet.png"))
json.dump([{"name": c[0], "hue": round(c[2], 3), "sat": round(c[3], 3), "val": round(c[4], 3)} for c in cells], open(os.path.join(OUT, "fx_stats.json"), "w"), indent=1)
print("ops", len(ops), "enemies", len(ens), "fx", len(cells), "->", OUT)
