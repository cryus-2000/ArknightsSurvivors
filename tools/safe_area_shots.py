# -*- coding: utf-8 -*-
"""手机安全区截图（11-13，iPhone 17 B站 App 横屏灵动岛挡字 / 经验条悬空，docs/22「Toy 接入」）：
各种屏幕比例 × 安全区（--safe 窗口像素，按 2 倍 CSS px 给）进局截一张，看局内 HUD 是否让开刘海 / 灵动岛 / 圆角 / 胶囊。
用法：python tools/safe_area_shots.py [--only ip17,ip17_l] [--out safe_area_shots]
输出 build/<out>/<tag>.png；godot_runner 放屏幕外、静音，同时最多 2 个；--desk 另截一张桌面 1920×1080 无 --touch 作对照"""
import argparse, os, sys
from concurrent.futures import ThreadPoolExecutor
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import godot_runner as GR
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
CAP = "--capsule=216,92"   # B站 App 沉浸横屏右上胶囊禁区 108×46 CSS px（container.js guessCapsule）×2
CONFIGS = {   # tag → (窗口, 安全区 l,t,r,b 窗口像素, 额外参数)；iOS 横屏左右边距对称（系统给的就是对称值），单侧两条是模拟非对称的设备
    "ip17": ("1748x804", "124,0,124,42", [CAP]),            # iPhone 17 / 16 横屏 874×402（2.17），灵动岛 62
    "ip17_l": ("1748x804", "124,0,0,42", [CAP]),            # 只有左侧（岛在左）
    "ip17_r": ("1748x804", "0,0,124,42", [CAP]),            # 只有右侧（岛在右）
    "ip17_t": ("1748x804", "124,60,124,42", [CAP]),         # B站 App 横屏回了顶部边距（11-13 真机：经验条仍卡在顶栏下）：横屏应忽略
    "ip17pm": ("1912x880", "124,0,124,42", [CAP]),          # Pro Max 956×440
    "ipx": ("1624x750", "88,0,88,42", [CAP]),               # 刘海老机型 812×375，44
    "a20x9": ("2400x1080", "80,0,0,0", []),                 # 安卓 20:9 挖孔在左
    "a195x9": ("2340x1080", "0,0,0,0", []),                 # 安卓 19.5:9 无边距
    "w16x9": ("1920x1080", "0,0,0,0", []),                  # 16:9
    "pad4x3": ("2048x1536", "0,0,0,40", []),                # 平板 4:3（iPad 横条 20）
}
ap = argparse.ArgumentParser()
ap.add_argument("--only", default=""); ap.add_argument("--out", default="safe_area_shots")
ap.add_argument("--desk", action="store_true")
a = ap.parse_args()
d = os.path.join(ROOT, "build", a.out)
os.makedirs(d, exist_ok=True)


def run(tag):
    if tag == "desk":
        res, extra = "1920x1080", []
    else:
        res, safe, ex = CONFIGS[tag]
        extra = ["--touch", "--safe=" + safe] + ex
    args = [GR.find_godot(), "--path", os.path.join(ROOT, "game"), "--audio-driver", "Dummy", "--fixed-fps", "60", "--resolution", "1280x720",
            "res://tests/safe_area_shots.tscn", "--", "--winsize=" + res, "--nodeath", "--seed=7", "--op=wisadel", "--squad=texas,suzuran",
            "--shots-out=" + a.out, "--shot-name=%s.png" % tag] + extra
    o, e, to = GR.run_godot(args, 600)
    line = [l for l in o.splitlines() if "SAFE AREA SHOT" in l]
    return tag, line[:1], GR.script_errors(o, e)[:3], to


tags = a.only.split(",") if a.only else list(CONFIGS)
if a.desk:
    tags.append("desk")
with ThreadPoolExecutor(2) as ex:
    for tag, line, errs, to in ex.map(run, tags):
        print(tag, line, errs, "TIMEOUT" if to else "", flush=True)

# 叠设备示意（只为看图：圆角外涂黑、灵动岛 / 刘海、底部横条、B站胶囊虚框），另存 <tag>_dev.png
DEV = {   # tag → (圆角半径, 岛侧 "l" / "r" / "lr"(刘海)/ "", 岛 宽×高, 横条, 胶囊)，窗口像素（2 倍 CSS px）
    "ip17": (110, "l", (74, 252), True, True), "ip17_l": (110, "l", (74, 252), True, True), "ip17_r": (110, "r", (74, 252), True, True), "ip17_t": (110, "l", (74, 252), True, True),
    "ip17pm": (110, "l", (74, 252), True, True), "ipx": (78, "l", (60, 418), True, True),
    "a20x9": (60, "l", (56, 56), False, False), "a195x9": (60, "", None, False, False), "w16x9": (0, "", None, False, False), "pad4x3": (36, "", None, True, False),
}
try:
    from PIL import Image, ImageDraw
except ImportError:
    Image = None
if Image:
    for tag in tags:
        p = os.path.join(d, tag + ".png")
        if tag not in DEV or not os.path.exists(p):
            continue
        rad, side, isl, bar, capsule = DEV[tag]
        im = Image.open(p).convert("RGB"); W, H = im.size
        m = Image.new("L", (W, H), 0); md = ImageDraw.Draw(m)
        md.rounded_rectangle([0, 0, W - 1, H - 1], rad if rad else 0, fill=255)
        black = Image.new("RGB", (W, H), (0, 0, 0)); im = Image.composite(im, black, m)
        dr = ImageDraw.Draw(im, "RGBA")
        if isl:
            iw, ih = isl
            for sd in (["l"] if side == "l" else ["r"] if side == "r" else []):
                x0 = 22 if sd == "l" else W - 22 - iw
                dr.rounded_rectangle([x0, H / 2 - ih / 2, x0 + iw, H / 2 + ih / 2], iw / 2, fill=(0, 0, 0, 255))
        if bar:
            dr.rounded_rectangle([W / 2 - 134, H - 16 - 10, W / 2 + 134, H - 16], 5, fill=(235, 235, 235, 230))
        if capsule:
            safe_r = int(CONFIGS[tag][1].split(",")[2])
            dr.rounded_rectangle([W - safe_r - 24 - 164, 22, W - safe_r - 24, 22 + 62], 31, fill=(20, 20, 24, 170), outline=(255, 255, 255, 140), width=2)
        im.save(os.path.join(d, tag + "_dev.png"))
