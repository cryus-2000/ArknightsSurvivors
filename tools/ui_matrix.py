"""界面分辨率矩阵（10-26 用户「UI 在各个分辨率下面都能正常」）：逐屏 × 逐尺寸截图，拼一张缩略总表。
经 godot_runner 跑：屏幕外、静音、不抢焦点；尺寸用 --winsize（无边框窗口，可以比本机屏幕大）。
触屏设备（手机 / 安卓 / iPad）加 --touch；手机尺寸按 iPhone Safari 横屏扣掉地址栏后的可视区（约 2.17:1）。

  python tools/ui_matrix.py <输出目录> [--screens a,b] [--sizes a,b] [-j 2]
  → <输出目录>/<尺寸>/<界面>.png，<输出目录>/matrix.jpg（行 = 界面，列 = 尺寸）、matrix_<界面>.jpg（每屏一张大图）

界面：title 标题 / oppick 选人 / diff 难度 / hunt 寻访 / gallery 图鉴 / meta 认知塑造 / medals 蚀刻章 / settings 设置 /
      hud 局内 / levelup 升级 / shop 商人 / cross 翻卡 / event 不期而遇 / pause 暂停 / result 结算
"""
import argparse
import glob
import os
import shutil
import sys
from concurrent.futures import ThreadPoolExecutor

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import godot_runner as gr  # noqa: E402

GAME = os.path.join(ROOT, "game")

# 尺寸：名字 → (宽, 高, 触屏)
SIZES = {
    "720p": (1280, 720, False), "900p": (1600, 900, False), "1080p": (1920, 1080, False), "1440p": (2560, 1440, False),
    "uw2560": (2560, 1080, False), "4x3": (1024, 768, False), "16x10": (1680, 1050, False),
    "iphone": (2178, 1002, True), "android": (2400, 1080, True), "ipad": (2048, 1536, True),
}
RUN = ["--autotest", "--seed=7", "--op=texas", "--squad=exusiai"]
# 界面：名字 → (参数, 截图文件通配, 超时秒)
SCREENS = {
    "title": (["--titleshot"], "shot_title.png", 90),
    "oppick": (["--opshot"], "shot_oppick.png", 90),
    "diff": (["--diffshot=1,3"], "shot_diff_*.png", 90),
    "hunt": (["--titlehunt", "--roster=start5", "--rostertickets=10"], "shot_titlehunt.png", 90),
    "gallery": (["--galleryshot=0"], "shot_gallery*.png", 90),
    "meta": (["--metashot", "--metacells=600", "--metabuy=200"], "shot_meta.png", 90),
    "medals": (["--medalshot"], "shot_medals.png", 90),
    "settings": (["--settingsshot"], "shot_settings.png", 90),
    "hud": (RUN + ["--grant=1,2,3,4,5,6,7,8,9", "--shots=420"], "shot_420.png", 60),
    "levelup": (RUN + ["--motionshot=levelup,1.6"], "shot_motion_levelup_full_*.png", 120),
    "shop": (RUN + ["--motionshot=shop,1.4"], "shot_motion_shop_full_*.png", 120),
    "cross": (RUN + ["--eventtest=cross1", "--shots=90"], "shot_90.png", 50),
    "event": (RUN + ["--eventtest=madness", "--shots=60"], "shot_60.png", 50),
    "pause": (RUN + ["--motionshot=pause,0.9"], "shot_motion_pause_full_*.png", 120),
    "result": (RUN + ["--statsshot=12"], "shot_stats_result.png", 150),
}


def shoot(out, size, screen):
    w, h, touch = SIZES[size]
    args, pat, tmo = SCREENS[screen]
    d = os.path.join(out, size, "_" + screen)
    shutil.rmtree(d, ignore_errors=True)
    os.makedirs(d)
    cmd = [gr.find_godot(), "--path", GAME, "--resolution", "%dx%d" % (min(w, 1600), min(h, 900)), "--audio-driver", "Dummy", "--",
           "--shotdir=" + d.replace("\\", "/"), "--winsize=%dx%d" % (w, h)] + (["--touch"] if touch else []) + args
    o, e, to = gr.run_godot(cmd, tmo)
    hits = sorted(glob.glob(os.path.join(d, pat)))
    errs = [ln for ln in (o + e).splitlines() if "SCRIPT ERROR" in ln][:3]
    if hits:
        shutil.copy(hits[-1], os.path.join(out, size, screen + ".png"))
    return size, screen, bool(hits), errs


def sheet(out, sizes, screens):
    from PIL import Image, ImageDraw, ImageFont
    cw, chh = 320, 180
    f = ImageFont.truetype("C:/Windows/Fonts/msyhbd.ttc", 18)
    W = 120 + cw * len(sizes)
    H = 40 + chh * len(screens)
    im = Image.new("RGB", (W, H), (18, 20, 24))
    d = ImageDraw.Draw(im)
    for j, s in enumerate(sizes):
        w, h, t = SIZES[s]
        d.text((120 + j * cw + 8, 10), "%s %dx%d%s" % (s, w, h, " 触屏" if t else ""), font=f, fill=(230, 230, 230))
    for i, sc in enumerate(screens):
        d.text((8, 40 + i * chh + chh // 2 - 10), sc, font=f, fill=(255, 206, 0))
        for j, s in enumerate(sizes):
            p = os.path.join(out, s, sc + ".png")
            if not os.path.exists(p):
                d.text((120 + j * cw + 100, 40 + i * chh + 80), "缺", font=f, fill=(255, 90, 90))
                continue
            t = Image.open(p).convert("RGB")
            t.thumbnail((cw - 8, chh - 8))
            im.paste(t, (120 + j * cw + (cw - t.width) // 2, 40 + i * chh + (chh - t.height) // 2))
    im.save(os.path.join(out, "matrix.jpg"), quality=88)
    # 每屏一张大图（各尺寸 640 宽，两列）：细看字和出框
    for sc in screens:
        tiles = []
        for s in sizes:
            p = os.path.join(out, s, sc + ".png")
            if os.path.exists(p):
                t = Image.open(p).convert("RGB")
                t.thumbnail((800, 600))
                tiles.append((s, t))
        if not tiles:
            continue
        cols = 2
        rows = (len(tiles) + 1) // 2
        th = max(t.height for _, t in tiles) + 30
        big = Image.new("RGB", (cols * 810, rows * th), (18, 20, 24))
        bd = ImageDraw.Draw(big)
        for k, (s, t) in enumerate(tiles):
            x, y = (k % cols) * 810, (k // cols) * th
            bd.text((x + 6, y + 4), "%s %dx%d" % (s, SIZES[s][0], SIZES[s][1]), font=f, fill=(230, 230, 230))
            big.paste(t, (x + 5, y + 28))
        big.save(os.path.join(out, "matrix_%s.jpg" % sc), quality=85)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out")
    ap.add_argument("--screens", default=",".join(SCREENS))
    ap.add_argument("--sizes", default=",".join(SIZES))
    ap.add_argument("-j", type=int, default=2)
    ap.add_argument("--sheet-only", action="store_true")
    a = ap.parse_args()
    out = os.path.abspath(a.out)
    screens = a.screens.split(",")
    sizes = a.sizes.split(",")
    if not a.sheet_only:
        gr.ensure_imported(GAME)
        jobs = [(s, sc) for sc in screens for s in sizes]
        with ThreadPoolExecutor(max_workers=a.j) as ex:
            for size, screen, ok, errs in ex.map(lambda j: shoot(out, *j), jobs):
                print(size, screen, "ok" if ok else "MISSING", *errs, flush=True)
    sheet(out, sizes, screens)
    print("matrix", os.path.join(out, "matrix.jpg"))


if __name__ == "__main__":
    main()
