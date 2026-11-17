# -*- coding: utf-8 -*-
"""新干员 B 方案帧条审阅（docs/365 §5）：同屏站位对照（1 倍 + 放大）与逐动作循环录像（原速 30 帧 mp4）。

    python tools/spine_px_review.py ling --vs suzuran angelina mizuki texas
    python tools/spine_px_review.py ling --video-only --with ling_soul1 ling_soul2 ling_soul3 --dens 2 1   # 连同召唤物、@2x 与 @1x 各一段

站位：各人待机首帧按游戏原点（128 画布 (64,120) / 192 画布 (96,152)）对齐到同一地线，原色原尺寸；放大图 ×4 最近邻。
录像：每个动作一格，按 build/spine_px/<id>/summary.json 的逐帧时长原速循环；30 帧、×3 最近邻、底色与审阅图同。
产物在 build/spine_px/<id>/review/。
"""
import argparse, glob, json, os, subprocess, sys
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import godot_runner as _GR
COMMON = _GR.common_root()
BG = (48, 61, 77, 255)
NAMES = {"ling": "令", "suzuran": "铃兰", "angelina": "安洁莉娜", "mizuki": "水月", "texas": "德克萨斯", "phantom": "傀影", "dusk": "夕", "shu": "黍", "surtr": "史尔特尔", "fiammetta": "菲亚梅塔"}


def font(sz):
    for f in ("C:/Windows/Fonts/msyh.ttc", "C:/Windows/Fonts/simhei.ttf"):
        if os.path.exists(f):
            return ImageFont.truetype(f, sz)
    return ImageFont.load_default()


def origin(size):
    return (size // 2, {128: 120, 192: 152, 256: 184}[size])


def lineup(oid, vs, out, extra=()):
    extra = list(extra)
    cells = []
    for o in [oid] + extra + vs:
        d = os.path.join(ROOT, "game", "art", "operators", o)
        cand = [os.path.join(d, "op_%s_idle@2x.png" % o)] + sorted(glob.glob(os.path.join(d, "*idle*@2x.png")))
        pxs = os.path.join(ROOT, "tools", "spine_run_trial", "cfg", "%s_px.json" % o)
        if o in extra and os.path.exists(pxs):        # 召唤物：帧条在主人目录，名字按 tex_prefix
            sp = json.load(open(pxs, encoding="utf-8"))
            cand = [os.path.join(ROOT, "game", "art", "operators", sp.get("owner", o), sp["tex_prefix"] + "_idle@2x.png")]
            NAMES.setdefault(o, json.load(open(os.path.join(ROOT, "tools", "spine_run_trial", "cfg", sp["rig"]), encoding="utf-8")).get("name", o))
        p = next(c for c in cand if os.path.exists(c))
        im = Image.open(p).convert("RGBA")
        s = im.height
        cells.append((o, im.crop((0, 0, s, s)), origin(s)))
    W, UP, DN = 120, 100, 16          # 每人格宽、原点以上 / 以下高度（@2x 像素）
    img = Image.new("RGBA", (W * len(cells), UP + DN), BG)
    for i, (o, im, (ox, oy)) in enumerate(cells):
        img.alpha_composite(im.crop((ox - W // 2, oy - UP, ox + W // 2, oy + DN)), (i * W, 0))
    d = ImageDraw.Draw(img)
    d.line((0, UP, img.width, UP), fill=(90, 105, 125, 255))
    img.save(os.path.join(out, "lineup_x1.png"))
    big = img.resize((img.width * 4, img.height * 4), Image.NEAREST)
    lab = Image.new("RGBA", (big.width, big.height + 44), (24, 28, 36, 255))
    lab.paste(big, (0, 44))
    dd = ImageDraw.Draw(lab)
    f = font(26)
    for i, (o, _, _) in enumerate(cells):
        dd.text((i * W * 4 + 12, 8), NAMES.get(o, o) + ("（B 方案）" if o == oid else ""), font=f, fill=(235, 235, 235, 255))
    lab.save(os.path.join(out, "lineup_x4.png"))
    return os.path.join(out, "lineup_x1.png"), os.path.join(out, "lineup_x4.png")


def _entries(ids, dens):
    """[(标签, 帧列表, 逐帧时长)]：各 id 的 summary.json 里该密度的动作，帧条名按 cfg/<id>_px.json 的 tex_prefix"""
    out = []
    for oid in ids:
        base = os.path.join(COMMON, "build", "spine_px", oid)
        summ = json.load(open(os.path.join(base, "summary.json"), encoding="utf-8"))
        pxs = os.path.join(ROOT, "tools", "spine_run_trial", "cfg", "%s_px.json" % oid)
        spec = json.load(open(pxs, encoding="utf-8")) if os.path.exists(pxs) else {}
        prefix = spec.get("tex_prefix", "op_%s" % oid)
        label = NAMES.get(oid) or json.load(open(os.path.join(ROOT, "tools", "spine_run_trial", "cfg", spec.get("rig", oid + ".json")), encoding="utf-8")).get("name", oid)
        for key, v in summ.items():
            act = key[:-3] if key.endswith("@1x") else key
            if (dens == 1) != key.endswith("@1x"):
                continue
            pth = os.path.join(base, "strips", "%s_%s@%dx.png" % (prefix, act, dens))
            if not os.path.exists(pth):
                continue
            im = Image.open(pth).convert("RGBA")
            sz = im.height
            out.append(("%s %s" % (label, act), [im.crop((sz * k, 0, sz * (k + 1), sz)) for k in range(im.width // sz)], v["durations"]))
    return out


def video(ids, out, name, dens=2, fps=30, secs=None, scale=3):
    """ids 的全部动作一格一个、原速循环；dens 1 时 1 倍条按 ×(2·scale) 放大，与 @2x 同显示尺寸"""
    ents = _entries(ids, dens)
    size = ents[0][1][0].width
    k2 = 2 // dens
    crop = (size // 2 - 64 // k2, 8 // k2, size // 2 + 64 // k2, size - 8 // k2)    # 192 画布裁 128×176（1 倍按半）
    sc = scale * k2
    cw, ch = (crop[2] - crop[0]) * sc, (crop[3] - crop[1]) * sc
    cols = 5
    rows = (len(ents) + cols - 1) // cols
    W, H = cols * cw, rows * (ch + 34)
    W += W % 2
    H += H % 2
    total = secs or max(4.0, max(sum(e[2]) for e in ents) * 2)
    fr = os.path.join(out, "_vid")
    os.makedirs(fr, exist_ok=True)
    for f in glob.glob(os.path.join(fr, "*.png")):
        os.remove(f)
    f = font(22)
    n = int(total * fps)
    for k in range(n):
        t = k / fps
        img = Image.new("RGB", (W, H), (24, 28, 36))
        d = ImageDraw.Draw(img)
        for i, (lab, frames, durs) in enumerate(ents):
            L = sum(durs)
            tt = t % L
            j = 0
            while j < len(durs) - 1 and tt >= durs[j]:
                tt -= durs[j]
                j += 1
            cell = Image.new("RGBA", (crop[2] - crop[0], crop[3] - crop[1]), BG)
            cell.alpha_composite(frames[j].crop(crop))
            x, y = (i % cols) * cw, (i // cols) * (ch + 34)
            img.paste(cell.resize((cw, ch), Image.NEAREST).convert("RGB"), (x, y + 34))
            d.text((x + 8, y + 4), "%s  %d 帧 %.2fs" % (lab, len(durs), L), font=f, fill=(230, 230, 230))
        img.save(os.path.join(fr, "%05d.png" % k))
    import imageio_ffmpeg
    mp4 = os.path.join(out, "%s.mp4" % name)
    subprocess.run([imageio_ffmpeg.get_ffmpeg_exe(), "-y", "-loglevel", "error", "-framerate", str(fps), "-i", os.path.join(fr, "%05d.png"),
                    "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "16", "-r", str(fps), mp4], check=True)
    for f2 in glob.glob(os.path.join(fr, "*.png")):
        os.remove(f2)
    os.rmdir(fr)
    return mp4


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("id")
    ap.add_argument("--vs", nargs="*", default=["suzuran", "angelina", "mizuki", "texas"])
    ap.add_argument("--video-only", action="store_true")
    ap.add_argument("--secs", type=float)
    ap.add_argument("--with", dest="extra", nargs="*", default=[], help="同录像里追加的 id（召唤物：ling_soul1 …）")
    ap.add_argument("--dens", type=int, nargs="*", default=[2], help="录哪几种密度（2 / 1）")
    a = ap.parse_args()
    out = os.path.join(COMMON, "build", "spine_px", a.id, "review")
    os.makedirs(out, exist_ok=True)
    if not a.video_only:
        print(*lineup(a.id, a.vs, out, a.extra))
    for dn in a.dens:
        print(video([a.id] + a.extra, out, "%s_anims%s" % (a.id, "" if dn == 2 else "_1x"), dens=dn, secs=a.secs))


if __name__ == "__main__":
    main()
