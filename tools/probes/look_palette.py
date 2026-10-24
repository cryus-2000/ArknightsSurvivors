# -*- coding: utf-8 -*-
"""水月肉鸽配色对照（docs/137 §6）：截本作现状四景（满灯 / 弱灯 / 溟痕 / Boss），对原作参照与本作截图做同一套取色统计，出三列对照图。

用法：
    python tools/probes/look_palette.py shots [--var base,palette]     # 截图到 build/look_nausea/palette/<变体>/<景>/
    python tools/probes/look_palette.py stats                          # 原作 / 本作取色板 + 指标 → palette/stats.json、swatches.png
    python tools/probes/look_palette.py cmp                            # 原作 / 现状 / 方案 三列对照图 three_col.png
原作参照（PRTS 可查证，用户 10-15 授权下载作内部参照，不进 git）：build/prts_is3/map/ro3_*.png（关卡预览，torappu.prts.wiki/assets/map_preview），
build/prts_is3/media/（海嗣头像、主题图、认知塑造界面、深入调查插图，media.prts.wiki）。
"""
import argparse, glob, json, os, shutil, sys

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS = os.path.dirname(HERE)
ROOT = os.path.dirname(TOOLS)
sys.path.insert(0, TOOLS)
import godot_runner as GR  # noqa: E402

CR = GR.common_root(ROOT)
OUT = os.path.join(CR, "build", "look_nausea", "palette")
REF = os.path.join(CR, "build", "prts_is3")
SQUAD = ["mizuki", "siege", "wisadel", "kaltsit"]
# 景：名字 → (起始秒, 额外参数)；Boss 景走 --autotest --bosstest
SCENES = {
    "full": (300.0, ["--lampat=296:100"]),
    "weak": (300.0, ["--lampat=296:18"]),
    "mire": (420.0, ["--lampat=416:100"]),
}
VARS = {
    "base": [],
    "palette": ["--bal=render/palette_trial=1"],
    # 只改溟痕 / 圈外（用户 10-24「保留海洋感的同时调整溟痕的颜色」）：其余画面不动
    "mireonly": ["--bal=render/mire_tint_r=0.5", "--bal=render/mire_tint_g=0.95", "--bal=render/mire_tint_b=0.8", "--bal=render/mire_anim=0",
                 "--bal=render/mire_alpha=0.8", "--bal=render/zone_dark_r=0.03", "--bal=render/zone_dark_g=0.08", "--bal=render/zone_dark_b=0.12"],
}


def shot_scene(var, scene):
    t0, extra = SCENES[scene]
    d = os.path.join(OUT, var, scene)
    shutil.rmtree(d, ignore_errors=True)
    os.makedirs(d, exist_ok=True)
    args = [GR.find_godot(), "--path", os.path.join(ROOT, "game"), "--audio-driver", "Dummy", "--fixed-fps", "60", "--resolution", "1280x720", "--",
            "--balance", "--seed=3", "--op=" + SQUAD[0], "--squad=" + ",".join(SQUAD[1:]), "--bot=expert", "--realtime", "--playclock",
            "--rtfrom=%g" % (t0 - 6.0), "--nohud", "--recframes=%g,%d" % (t0, 3), "--shotdir=" + d.replace(os.sep, "/")] + extra + VARS[var]
    out, err, to = GR.run_godot(args, 1800)
    print(var, scene, len(glob.glob(os.path.join(d, "rec_*.png"))), "超时" if to else "", "；".join(GR.script_errors(out, err)[:2]))


def shot_boss(var):
    d = os.path.join(OUT, var, "boss")
    shutil.rmtree(d, ignore_errors=True)
    os.makedirs(d, exist_ok=True)
    args = [GR.find_godot(), "--path", os.path.join(ROOT, "game"), "--audio-driver", "Dummy", "--resolution", "1280x720", "--",
            "--autotest", "--seed=3", "--bosstest=ishar", "--nohud", "--shotdir=" + d.replace(os.sep, "/")] + VARS[var]
    out, err, to = GR.run_godot(args, 900)
    print(var, "boss", len(glob.glob(os.path.join(d, "*.png"))), "超时" if to else "", "；".join(GR.script_errors(out, err)[:2]))


def scene_img(var, scene):
    fs = sorted(glob.glob(os.path.join(OUT, var, scene, "rec_*.png"))) or sorted(glob.glob(os.path.join(OUT, var, scene, "shot_boss_*_150.png"))) \
        or sorted(glob.glob(os.path.join(OUT, var, scene, "*.png")))
    return fs[len(fs) // 2] if fs else None


def ref_sets():
    m = sorted(glob.glob(os.path.join(REF, "map", "ro3_*.png")))
    return {
        "原作·关卡（ro3 %d 张）" % len(m): m,
        "原作·海嗣头像（8）": sorted(glob.glob(os.path.join(REF, "media", "enemy_*.png"))),
        "原作·界面 / 插图（4）": [os.path.join(REF, "media", n) for n in ("ui_node_tree.png", "investigate_1.png", "investigate_2.png", "investigate_3.png")],
        "原作·主题图": [os.path.join(REF, "media", "theme_banner.png")],
    }


def stats_of(paths):
    """同一套取色：明度分位、饱和（全体 / 暗部）、色相分组占比（以「有色」像素计：饱和 >0.15 且明度 >0.06）、6 色主色板（k-means）"""
    import numpy as np
    from PIL import Image
    px = []
    for p in paths:
        im = Image.open(p).convert("RGBA")
        im.thumbnail((640, 640))
        a = np.asarray(im, dtype=np.float32)
        px.append(a[..., :3][a[..., 3] > 200])
    rgb = np.concatenate(px) / 255.0
    mx, mn = rgb.max(1), rgb.min(1)
    v = mx
    s = np.where(mx > 1e-4, (mx - mn) / np.maximum(mx, 1e-4), 0)
    r, g, b = rgb[:, 0], rgb[:, 1], rgb[:, 2]
    d = np.maximum(mx - mn, 1e-6)
    h = np.where(mx == r, ((g - b) / d) % 6, np.where(mx == g, (b - r) / d + 2, (r - g) / d + 4)) * 60.0
    col = (s > 0.15) & (v > 0.06)
    n = max(1, col.sum())

    def frac(lo, hi):
        return float(((h >= lo) & (h < hi) & col).sum()) / n
    res = {
        "n_px": int(len(rgb)),
        "v_p10": round(float(np.percentile(v, 10)), 3), "v_p50": round(float(np.percentile(v, 50)), 3), "v_p90": round(float(np.percentile(v, 90)), 3),
        "s_mean": round(float(s.mean()), 3), "s_p90": round(float(np.percentile(s, 90)), 3),
        "s_dark": round(float(s[v < 0.3].mean()) if (v < 0.3).any() else 0.0, 3),
        "colored": round(float(col.mean()), 3),
        "hue_warm": round(frac(0, 60) + frac(330, 360), 3), "hue_green": round(frac(60, 160), 3),
        "hue_cyan": round(frac(160, 200), 3), "hue_blue": round(frac(200, 240), 3),
        "hue_violet": round(frac(240, 290), 3), "hue_magenta": round(frac(290, 330), 3),
    }
    rs = np.random.default_rng(0)
    sm = rgb[rs.choice(len(rgb), min(40000, len(rgb)), replace=False)]
    cen = sm[rs.choice(len(sm), 6, replace=False)]
    for _ in range(10):
        lab = ((sm[:, None, :] - cen[None]) ** 2).sum(2).argmin(1)
        cen = np.array([sm[lab == k].mean(0) if (lab == k).any() else cen[k] for k in range(6)])
    cnt = np.bincount(lab, minlength=6) / len(sm)
    res["palette"] = [[[int(c * 255) for c in cen[k]], round(float(cnt[k]), 3)] for k in np.argsort(-cnt)]
    return res


def _font(sz):
    from PIL import ImageFont
    try:
        return ImageFont.truetype("C:/Windows/Fonts/msyh.ttc", sz)
    except OSError:
        return None


def cmd_stats():
    from PIL import Image, ImageDraw
    sets = ref_sets()
    for var in VARS:
        for sc in ["full", "weak", "mire", "boss"]:
            p = scene_img(var, sc)
            if p:
                sets["本作·%s·%s" % (var, sc)] = [p]
    res = {k: stats_of(v) for k, v in sets.items() if v}
    json.dump(res, open(os.path.join(OUT, "stats.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    for k, r in res.items():
        print(k, json.dumps({x: r[x] for x in r if x != "palette"}, ensure_ascii=False))
    font = _font(15)
    rh = 46
    img = Image.new("RGB", (1400, rh * len(res) + 10), (30, 30, 34))
    dr = ImageDraw.Draw(img)
    for i, (k, r) in enumerate(res.items()):
        y = 5 + i * rh
        dr.text((8, y + 12), k, fill=(230, 230, 230), font=font)
        x = 260
        for c, w in r["palette"]:
            ww = max(4, int(w * 520))
            dr.rectangle([x, y + 4, x + ww, y + rh - 6], fill=tuple(c))
            x += ww
        x = 800
        dr.text((x, y + 4), "明度中位 %.2f  饱和均值 %.2f  暗部饱和 %.2f" % (r["v_p50"], r["s_mean"], r["s_dark"]), fill=(200, 200, 200), font=font)
        dr.text((x, y + 22), "青 %.0f%%  蓝 %.0f%%  紫 %.0f%%  洋红 %.0f%%  暖 %.0f%%  绿 %.0f%%" % (100 * r["hue_cyan"], 100 * r["hue_blue"], 100 * r["hue_violet"],
                100 * r["hue_magenta"], 100 * r["hue_warm"], 100 * r["hue_green"]), fill=(200, 200, 200), font=font)
    img.save(os.path.join(OUT, "swatches.png"))


def cmd_cmp():
    """三列：原作关卡（按景挑一张）/ 现状 / 方案；每行一景"""
    from PIL import Image, ImageDraw
    font = _font(18)
    refs = {"full": "ro3_n_1_3.png", "weak": "ro3_n_3_4.png", "mire": "ro3_n_5_2.png", "boss": "ro3_e_5_8.png"}
    w, h = 480, 270
    rows = []
    for sc in ["full", "weak", "mire", "boss"]:
        cells = [os.path.join(REF, "map", refs[sc]), scene_img("base", sc), scene_img("palette", sc)]
        row = Image.new("RGB", (w * 3, h), (0, 0, 0))
        for i, (p, lab) in enumerate(zip(cells, ["原作 " + refs[sc], "现状 · " + sc, "方案 · " + sc])):
            if p and os.path.exists(p):
                im = Image.open(p).convert("RGB")
                if i:
                    im = im.crop((int(im.width * 0.1), int(im.height * 0.1), int(im.width * 0.9), int(im.height * 0.9)))
                row.paste(im.resize((w, h)), (i * w, 0))
            ImageDraw.Draw(row).text((i * w + 8, 6), lab, fill=(255, 255, 0), font=font)
        rows.append(row)
    c = Image.new("RGB", (w * 3, h * len(rows)))
    for i, r in enumerate(rows):
        c.paste(r, (0, i * h))
    c.save(os.path.join(OUT, "three_col.png"))
    print(os.path.join(OUT, "three_col.png"))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["shots", "stats", "cmp"])
    ap.add_argument("--var", default="base")
    ap.add_argument("--scenes", default="full,weak,mire,boss")
    a = ap.parse_args()
    os.makedirs(OUT, exist_ok=True)
    if a.cmd == "shots":
        GR.ensure_imported(os.path.join(ROOT, "game"))
        import concurrent.futures as cf
        with cf.ThreadPoolExecutor(4) as ex:
            jobs = [ex.submit(shot_boss, var) if sc == "boss" else ex.submit(shot_scene, var, sc)
                    for var in a.var.split(",") for sc in a.scenes.split(",")]
            [j.result() for j in jobs]
    elif a.cmd == "stats":
        cmd_stats()
    else:
        cmd_cmp()


if __name__ == "__main__":
    main()
