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
    "touch16x9": (1920, 1080, True),
}
# 带安全区的尺寸（11-13 安全区适配，docs/22「Toy 接入」）：名字 → (--safe 窗口像素 l,t,r,b, --capsule 宽,高 或 "", 设备示意)
# iPhone 17 横屏 874×402 CSS ×2；B站 App 真机回的是岛那一侧 62、另一侧 0（env 两侧都是 62，container.js 逐边取大后两侧都让）。
# 这里左岛 / 右岛各一套，只给岛那一侧，用来分别看两侧有没有让开；圆角 / 岛 / 胶囊 / 横条在截图上叠示意（<界面>_dev.png）
SAFE = {
    "ip17L": ("124,0,0,42", "216,92", ("l", 110)), "ip17R": ("0,0,124,42", "216,92", ("r", 110)),
    "ipad": ("0,0,0,40", "", ("", 36)),
}
SIZES.update({"ip17L": (1748, 804, True), "ip17R": (1748, 804, True)})
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
    "runstats": (RUN + ["--statsshot=12"], "shot_stats_overview.png", 150),
    "tab": (RUN + ["--tabshot=200"], "shot_tab.png", 60),
    "recruit": (RUN + ["--motionshot=recruit,1.6"], "shot_motion_recruit_full_*.png", 120),
    "relic": (RUN + ["--motionshot=relic,1.6"], "shot_motion_relic_full_*.png", 120),
    "loading": (["--loadingshot"], "shot_loading.png", 90),
    "support": (["--titleshot", "--supopen"], "shot_title.png", 90),
    "supzoom": (["--titleshot", "--supopen", "--supzoom"], "shot_title.png", 90),
    "feedback": (["--titleshot", "--fbopen"], "shot_title.png", 90),
    "credits": (["--creditsshot"], "shot_credits.png", 90),
    "guide": (["--guideshot"], "shot_guide.png", 90),
    # 没有现成钩子的几屏：tests/safe_screens_shots.tscn（场景路径放 -- 前面）
    "event": (["res://tests/safe_screens_shots.tscn", "--which=event", "--op=texas", "--squad=exusiai"], "shot_event.png", 120),
    "elite": (["res://tests/safe_screens_shots.tscn", "--which=elite", "--op=texas", "--squad=exusiai"], "shot_elite.png", 120),
    "ultaim": (["res://tests/safe_screens_shots.tscn", "--which=ultaim", "--op=texas", "--squad=exusiai"], "shot_ultaim.png", 120),
    "runlog": (["res://tests/safe_screens_shots.tscn", "--which=runlog", "--op=texas", "--squad=exusiai"], "shot_runlog.png", 120),
}


def shoot(out, size, screen):
    w, h, touch = SIZES[size]
    args, pat, tmo = SCREENS[screen]
    d = os.path.join(out, size, "_" + screen)
    shutil.rmtree(d, ignore_errors=True)
    os.makedirs(d)
    scene = [args[0]] if args and args[0].startswith("res://") else []
    args = args[len(scene):]
    cmd = [gr.find_godot(), "--path", GAME, "--resolution", "%dx%d" % (min(w, 1600), min(h, 900)), "--audio-driver", "Dummy"] + scene + ["--",
           "--shotdir=" + d.replace("\\", "/"), "--winsize=%dx%d" % (w, h)] + (["--touch"] if touch else []) + args
    if size in SAFE:
        cmd += ["--safe=" + SAFE[size][0]] + (["--capsule=" + SAFE[size][1]] if SAFE[size][1] else [])
    o, e, to = gr.run_godot(cmd, tmo)
    hits = sorted(glob.glob(os.path.join(d, pat)))
    errs = [ln for ln in (o + e).splitlines() if "SCRIPT ERROR" in ln][:3]
    if hits:
        shutil.copy(hits[-1], os.path.join(out, size, screen + ".png"))
        if size in SAFE:
            dev_overlay(os.path.join(out, size, screen + ".png"), size)
    shutil.rmtree(d, ignore_errors=True)
    return size, screen, bool(hits), errs


def dev_overlay(p, size):
    """圆角外涂黑、灵动岛、底部横条、B站胶囊虚框（只为看图），覆盖原图"""
    from PIL import Image, ImageDraw
    safe, cap, (side, rad) = SAFE[size]
    l, t, r, b = [int(x) for x in safe.split(",")]
    im = Image.open(p).convert("RGB"); W, H = im.size
    m = Image.new("L", (W, H), 0); ImageDraw.Draw(m).rounded_rectangle([0, 0, W - 1, H - 1], rad, fill=255)
    im = Image.composite(im, Image.new("RGB", (W, H), (0, 0, 0)), m)
    dr = ImageDraw.Draw(im, "RGBA")
    if side:
        x0 = 22 if side == "l" else W - 22 - 74
        dr.rounded_rectangle([x0, H / 2 - 126, x0 + 74, H / 2 + 126], 37, fill=(0, 0, 0, 255))
    if b:
        dr.rounded_rectangle([W / 2 - 134, H - 26, W / 2 + 134, H - 16], 5, fill=(235, 235, 235, 230))
    if cap:
        cw, chh = [int(x) for x in cap.split(",")]
        dr.rounded_rectangle([W - r - 24 - 164, 22, W - r - 24, 84], 31, fill=(20, 20, 24, 170), outline=(255, 255, 255, 140), width=2)
    im.save(p)


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
