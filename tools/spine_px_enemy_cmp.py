# -*- coding: utf-8 -*-
"""萨米敌人三列对照图（docs/399 §5）：原作参照 / 像素 @1x（×4）/ 像素 @2x（×2），每动作一行取关键帧（出手帧 / 中间帧）；--overview 再拼总览。

    python tools/spine_px_enemy_cmp.py              # 全部，出 build/spine_px/_sami_cmp/<id>_cmp.png + sami_overview.png
    python tools/spine_px_enemy_cmp.py husk will
"""
import json, os, sys
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import prts_spine as PS
import spine_px_enemy as SE

OUT = os.path.join(SE.COMMON, "build", "spine_px", "_sami_cmp")
os.makedirs(OUT, exist_ok=True)
spec = json.load(open(SE.SPEC_OUT, encoding="utf-8"))
try:
    FONT = ImageFont.truetype(r"C:\Windows\Fonts\msyh.ttc", 18)
    FONT_S = ImageFont.truetype(r"C:\Windows\Fonts\msyh.ttc", 14)
except Exception:
    FONT = FONT_S = ImageFont.load_default()
BG = (40, 46, 58, 255)
TIER = {"normal": "普通", "high": "高阶", "elite": "精英", "rare": "稀有", "boss": "Boss"}


def key_frame(name, n, ev):
    if n == 1 or name in ("idle", "disguised"):
        return 0
    if ev:
        return ev[0]
    return n // 2


def ref_frames(eid, e, picks):
    raw = os.path.join(SE.RAW, e["src"])
    meta = json.load(open(os.path.join(raw, "meta.json"), encoding="utf-8"))
    base = os.path.join(raw, os.path.basename(meta["file"]))
    od = os.path.join(OUT, "_ref_" + eid)
    job = {"skel": base + ".skel", "atlas": base + ".atlas", "out_dir": od, "size": 1000, "flip": False,
           "frames": [{"name": nm, "anim": an, "t": t} for nm, an, t in picks]}
    res = PS.run_render(job)
    return {f["name"]: Image.open(f["file"]).convert("RGBA") for f in res["frames"]}


def one(eid):
    e = SE.ENEMIES[eid]
    k = "sami_" + eid
    sd = os.path.join(SE.COMMON, "build", "spine_px", k, "strips")
    size = e["canvas"]
    ox, oy = 64 + (size - 128) // 2, 120 + (size - 128) // 2
    info = spec["enemies"][eid]
    w, h = info["frame_size_2x"]
    rows, picks = [], []
    for name, a in e["acts"].items():
        key = "e_" + k if name == "idle" else "e_%s_%s" % (k, name)
        sp = spec["sprites"][key]
        n = sp["pixels"]["frames"]
        fi = key_frame(name, n, sp["redraw"]["event_frames"])
        t = sp["redraw"]["sample_times"][fi]
        s2 = Image.open(os.path.join(SE.DST, key + "@2x.png")).convert("RGBA")
        f2 = s2.crop((w * fi, 0, w * (fi + 1), h))
        p1 = os.path.join(SE.DST, key + ".png")
        p1 = p1 if os.path.exists(p1) else os.path.join(SE.CMP1X, key + ".png")
        if os.path.exists(p1):   # Boss：进包的 1 倍
            f1 = Image.open(p1).convert("RGBA").crop((w // 2 * fi, 0, w // 2 * (fi + 1), h // 2))
        else:                    # 其余：大画布 1 倍帧条按同一框裁（不进包，只对照）
            big = Image.open(os.path.join(sd, "e_%s_%s@1x.png" % (k, name))).convert("RGBA")
            ax, ay = sp["pixels"]["anchor"]
            X0, Y0 = ox - round(ax * w), oy - round(ay * h)
            s1 = size // 2
            f1 = big.crop((s1 * fi + X0 // 2, Y0 // 2, s1 * fi + X0 // 2 + w // 2, Y0 // 2 + h // 2))
        rows.append((name, a["anim"], fi, n, t, f1, f2))
        picks.append((name, a["anim"], t))
    refs = ref_frames(eid, e, picks)
    bb = [r.getbbox() for r in refs.values() if r.getbbox()]
    u = (min(b[0] for b in bb), min(b[1] for b in bb), max(b[2] for b in bb), max(b[3] for b in bb))
    cw, ch = w * 2, h * 2
    sc = min(cw / (u[2] - u[0]), ch / (u[3] - u[1]))
    colw, head, rh = max(cw + 24, 150), 84, ch + 30
    img = Image.new("RGBA", (130 + colw * 3, head + rh * len(rows) + 10), BG)
    dr = ImageDraw.Draw(img)
    dr.text((12, 8), "%s  %s（%s）  %s" % (e["name"], eid, e["src"], TIER[e["tier"]]), font=FONT, fill=(255, 235, 150, 255))
    dr.text((12, 34), "帧框 @2x %d×%d · 待机 %d×%d（顶到脚 %d）" % (w, h, *info["idle_body_2x"], info["top_to_foot_2x"]), font=FONT_S, fill=(200, 210, 225, 255))
    for c, lab in enumerate(["原作参照", "像素 @1x（×4）", "像素 @2x（×2）"]):
        dr.text((130 + colw * c + 6, head - 20), lab, font=FONT_S, fill=(170, 220, 255, 255))
    for r, (name, anim, fi, n, t, f1, f2) in enumerate(rows):
        y = head + rh * r
        dr.text((10, y + 8), name, font=FONT_S, fill=(255, 255, 255, 255))
        dr.text((10, y + 28), "%s f%d/%d" % (anim, fi, n), font=FONT_S, fill=(160, 170, 190, 255))
        dr.text((10, y + 46), "t=%.2fs" % t, font=FONT_S, fill=(160, 170, 190, 255))
        ref = refs[name].crop(u)
        ref = ref.resize((max(1, round(ref.width * sc)), max(1, round(ref.height * sc))), Image.LANCZOS)
        img.alpha_composite(ref, (130 + 6 + (cw - ref.width) // 2, y + 8 + (ch - ref.height)))
        img.alpha_composite(f1.resize((f1.width * 4, f1.height * 4), Image.NEAREST), (130 + colw + 6, y + 8))
        img.alpha_composite(f2.resize((f2.width * 2, f2.height * 2), Image.NEAREST), (130 + colw * 2 + 6, y + 8))
    p = os.path.join(OUT, "%s_cmp.png" % eid)
    img.save(p)
    print(p, img.size, flush=True)
    return img


def overview(sheets):
    """总览：上排全部待机 @2x 原尺寸 ×2 与水月同档 / 干员并排比大小，下面各对照图缩到同宽拼两列"""
    game_art = os.path.join(ROOT, "game", "art")
    pix = json.load(open(os.path.join(ROOT, "game", "themes", "deep_sea", "data", "enemy_pixels.json"), encoding="utf-8"))
    line = []
    for key, own in (("op_ling_idle", "operators/ling"), ("e_slider", "enemies/slider"), ("e_founder", "enemies/founder"),
                     ("e_skimmer", "enemies/skimmer"), ("e_saint", "enemies/saint"), ("e_path", "enemies/path")):
        p = os.path.join(game_art, own, key + "@2x.png")
        if not os.path.exists(p):
            continue
        im = Image.open(p).convert("RGBA")
        if key.startswith("op_"):
            fw, fh, fy = 192, 192, 152
        else:
            fw, fh = pix[key]["frame_size"]
            fy = round(pix[key]["anchor"][1] * fh)
        line.append(("水月 " + key[2:] if key.startswith("e_") else "干员 令", im.crop((0, 0, fw, fh)), fy))
    for eid in SE.ENEMIES:
        info = spec["enemies"].get(eid)
        if not info:
            continue
        sp = spec["sprites"]["e_sami_" + eid]["pixels"]
        w, h = sp["frame_size"]
        im = Image.open(os.path.join(SE.DST, "e_sami_%s@2x.png" % eid)).convert("RGBA").crop((0, 0, w, h))
        line.append((SE.ENEMIES[eid]["name"], im, round(sp["anchor"][1] * h)))
    trimmed = []
    for lab, im, fy in line:
        b = im.getbbox()
        trimmed.append((lab, im.crop((b[0], 0, b[2], fy + 2)), fy))
    top = max(fy for _, _, fy in trimmed) + 2
    W = sum(max(im.width, len(lab) * 14) + 14 for lab, im, _ in trimmed) + 20
    lane = Image.new("RGBA", (W, top + 24), BG)
    d = ImageDraw.Draw(lane)
    x = 10
    for lab, im, fy in trimmed:
        lane.alpha_composite(im, (x, top - im.height))
        d.text((x, top + 2), lab, font=FONT_S, fill=(220, 225, 235, 255))
        x += max(im.width, len(lab) * 14) + 14
    lane = lane.crop((0, 0, x + 10, lane.height)).resize(((x + 10) * 2, lane.height * 2), Image.NEAREST)
    colw, NC = 1060, 3
    thumbs = [s.resize((colw, round(s.height * colw / s.width)), Image.LANCZOS) if s.width > colw else s for s in sheets]
    cols = [[] for _ in range(NC)]
    hs = [0] * NC
    for t in thumbs:
        c = hs.index(min(hs))
        cols[c].append(t)
        hs[c] += t.height + 12
    W = max(lane.width, (colw + 12) * NC + 24)
    img = Image.new("RGBA", (W, 50 + lane.height + 20 + max(hs)), (28, 32, 42, 255))
    d = ImageDraw.Draw(img)
    d.text((12, 12), "萨米敌人 / Boss 像素帧条总览（上排：待机 @2x ×2，与干员令和水月同档敌人脚底对齐比大小）", font=FONT, fill=(255, 235, 150, 255))
    img.alpha_composite(lane, (0, 50))
    for c in range(NC):
        y = 50 + lane.height + 20
        for t in cols[c]:
            img.alpha_composite(t, (12 + c * (colw + 12), y))
            y += t.height + 12
    p = os.path.join(OUT, "sami_overview.png")
    img.save(p)
    print(p, img.size)


def variants(out_dir, eids=("husk", "will"), acts={"husk": ("idle", "attack", "death"), "will": ("idle", "sigh")}):
    """处理方式候选对照（11-20）：每只敌人一张，行 = 候选 × 动作，列 = 原作 / @1x ×4 / @2x ×2；再并成 sami_variants_overview.png
    候选帧条由 spine_px_enemy.py --variant <名> --out <out_dir> 出"""
    sheets = []
    for eid in eids:
        e = SE.ENEMIES[eid]
        rows = []
        for v in SE.VARIANTS:
            vd = os.path.join(out_dir, v)
            sj = json.load(open(os.path.join(vd, eid + "_spec.json"), encoding="utf-8"))
            k = "sami_%s_v%s" % (eid, v)
            for name in acts[eid]:
                key = "e_" + k if name == "idle" else "e_%s_%s" % (k, name)
                sp = sj["spec"][key]
                w, h = sp["pixels"]["frame_size"]
                fi = key_frame(name, sp["pixels"]["frames"], sp["redraw"]["event_frames"])
                f2 = Image.open(os.path.join(vd, key + "@2x.png")).convert("RGBA").crop((w * fi, 0, w * (fi + 1), h))
                f1 = Image.open(os.path.join(vd, key + ".png")).convert("RGBA").crop((w // 2 * fi, 0, w // 2 * (fi + 1), h // 2))
                rows.append((v, name, e["acts"][name]["anim"], sp["redraw"]["sample_times"][fi], f1, f2, (w, h)))
        uniq = {}
        for v, name, anim, t, *_ in rows:
            uniq[name] = (anim, t)
        refs = ref_frames(eid, e, [(n, a, t) for n, (a, t) in uniq.items()])
        bb = [r.getbbox() for r in refs.values() if r.getbbox()]
        u = (min(b[0] for b in bb), min(b[1] for b in bb), max(b[2] for b in bb), max(b[3] for b in bb))
        w, h = rows[0][6]
        cw, ch = w * 2, h * 2
        sc = min(cw / (u[2] - u[0]), ch / (u[3] - u[1]))
        colw, head, rh = max(cw + 24, 230), 120, ch + 30
        img = Image.new("RGBA", (max(190 + colw * 3, 760), head + rh * len(rows) + 10), BG)
        dr = ImageDraw.Draw(img)
        dr.text((12, 8), "%s  %s  处理方式候选" % (e["name"], eid), font=FONT, fill=(255, 235, 150, 255))
        for n, v in enumerate(SE.VARIANTS):
            dr.text((12, 34 + 18 * n), "%s：%s" % (v, SE.VARIANTS[v]["_doc"]), font=FONT_S, fill=(200, 210, 225, 255))
        for c, lab in enumerate(["原作参照", "像素 @1x（×4）", "像素 @2x（×2）"]):
            dr.text((190 + colw * c + 6, head - 20), lab, font=FONT_S, fill=(170, 220, 255, 255))
        last = None
        for r, (v, name, anim, t, f1, f2, _) in enumerate(rows):
            y = head + rh * r
            if v != last:
                dr.line((0, y, img.width, y), fill=(255, 235, 150, 255), width=2)
                last = v
            dr.text((10, y + 8), "候选 %s" % v, font=FONT, fill=(255, 235, 150, 255))
            dr.text((10, y + 36), "%s · %s t=%.2fs" % (name, anim, t), font=FONT_S, fill=(200, 205, 215, 255))
            ref = refs[name].crop(u)
            ref = ref.resize((max(1, round(ref.width * sc)), max(1, round(ref.height * sc))), Image.LANCZOS)
            img.alpha_composite(ref, (190 + 6 + (cw - ref.width) // 2, y + 8 + (ch - ref.height)))
            img.alpha_composite(f1.resize((f1.width * 4, f1.height * 4), Image.NEAREST), (190 + colw + 6, y + 8))
            img.alpha_composite(f2.resize((f2.width * 2, f2.height * 2), Image.NEAREST), (190 + colw * 2 + 6, y + 8))
        p = os.path.join(out_dir, "%s_variants.png" % eid)
        img.save(p)
        print(p, img.size, flush=True)
        sheets.append(img)
    W = sum(s.width for s in sheets) + 12 * (len(sheets) + 1)
    H = max(s.height for s in sheets) + 24
    ov = Image.new("RGBA", (W, H), (28, 32, 42, 255))
    x = 12
    for s in sheets:
        ov.alpha_composite(s, (x, 12))
        x += s.width + 12
    p = os.path.join(out_dir, "sami_variants_overview.png")
    ov.save(p)
    print(p, ov.size)


def ground(out_dir, pair=("A", "D"), picks=(("husk", "idle"), ("husk", "attack"), ("will", "idle"), ("will", "sigh"))):
    """深色地面底对照（11-20 看轮廓）：每行一个动作，左 = pair[0]、右 = pair[1]；各给 @2x 原大（游戏里的屏幕尺寸）与 ×2 放大"""
    import random
    rnd = random.Random(7)

    def floor(w, h):
        g = Image.new("RGBA", (w, h), (24, 30, 36, 255))
        px = g.load()
        for y in range(0, h, 2):
            for x in range(0, w, 2):
                d = rnd.choice((-4, -2, 0, 0, 0, 2, 3))
                c = (24 + d, 30 + d, 36 + d, 255)
                for yy in (y, y + 1):
                    for xx in (x, x + 1):
                        if xx < w and yy < h:
                            px[xx, yy] = c
        return g
    rows = []
    for eid, name in picks:
        fr = {}
        for v in pair:
            vd = os.path.join(out_dir, v)
            sj = json.load(open(os.path.join(vd, eid + "_spec.json"), encoding="utf-8"))
            k = "sami_%s_v%s" % (eid, v)
            key = "e_" + k if name == "idle" else "e_%s_%s" % (k, name)
            sp = sj["spec"][key]
            w, h = sp["pixels"]["frame_size"]
            fi = key_frame(name, sp["pixels"]["frames"], sp["redraw"]["event_frames"])
            fr[v] = Image.open(os.path.join(vd, key + "@2x.png")).convert("RGBA").crop((w * fi, 0, w * (fi + 1), h))
        rows.append((eid, name, fr))
    cells = [(max(f.width for f in fr.values()), max(f.height for f in fr.values())) for _, _, fr in rows]
    zm = [4 if c[1] < 100 else 2 for c in cells]   # 小怪放大 ×4，Boss ×2
    colw = max(c[0] * (z + 1) + 40 for c, z in zip(cells, zm))
    W = 150 + colw * len(pair)
    H = 50 + sum(c[1] * z + 30 for c, z in zip(cells, zm))
    img = floor(W, H)
    dr = ImageDraw.Draw(img)
    dr.text((12, 10), "深色地面对照：左 = 候选 %s，右 = 候选 %s（每格：@2x 原大 + 放大：躯壳 ×4、意志 ×2）" % pair, font=FONT, fill=(255, 235, 150, 255))
    y = 50
    for (eid, name, fr), (cw, ch), z in zip(rows, cells, zm):
        dr.text((10, y + 8), "%s · %s" % (SE.ENEMIES[eid]["name"], name), font=FONT_S, fill=(200, 210, 225, 255))
        for c, v in enumerate(pair):
            f = fr[v]
            x = 150 + colw * c
            dr.text((x, y), v, font=FONT, fill=(255, 235, 150, 255))
            img.alpha_composite(f, (x + 24, y + ch * z - f.height + 20))
            img.alpha_composite(f.resize((f.width * z, f.height * z), Image.NEAREST), (x + 24 + cw + 12, y + 20 + ch * z - f.height * z))
        y += ch * z + 30
    p = os.path.join(out_dir, "sami_ground_%s_vs_%s.png" % pair)
    img.save(p)
    print(p, img.size)


if __name__ == "__main__" and len(sys.argv) > 2 and sys.argv[1] == "--variants":
    variants(sys.argv[2])
    ground(sys.argv[2])
elif __name__ == "__main__":
    ids = sys.argv[1:] or list(SE.ENEMIES)
    sheets = [one(i) for i in ids]
    if not sys.argv[1:]:
        overview(sheets)
