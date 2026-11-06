#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""艾丽妮 11-07 两项改动的新旧对照（图鉴演示 tests/elite_demo_shot.tscn，30 帧原速连存，GCP 虚拟机上跑，本机不开 Godot）：
  ① 普攻星光画法 fx/ir_atk_star（用户「更喜欢旧版带星光的，现在太象是激光了」）
  ② 全部特效白 + 粉、去蓝（用户「主色调应该是白+粉为主，一技能的蓝色去掉」）
旧画面取 --old 提交（改动之前）：脚本把 game/ 切到那个提交、重新导入 + 生成 index.json 再拍，拍完切回 HEAD。
每招一段 mp4，精零 → 精二接在一起（左上标档位和栏名）；另出每招每档一张定格（三栏 / 两栏 + 下方 2 倍局部）。

用法（仓库根目录）：python3 tools/irene_star_rec.py --out $MEDIA --old 873eda0d2 [--moves atk,s1,s2,s3,ult]
"""
import argparse, glob, os, shutil, subprocess, sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import godot_runner as GR

try:
    import imageio_ffmpeg as _iff
    FF = _iff.get_ffmpeg_exe()   # 虚拟机镜像上没有系统 ffmpeg（render_prep 装的是 imageio-ffmpeg）
except Exception:
    FF = "ffmpeg"

GAME = os.path.join(ROOT, "game")
BUILD = os.path.join(ROOT, "build", "irene_star")
TIER = {0: "精零", 1: "精一", 2: "精二"}
# 招 → (演示模式, 档位, 秒数)
MOVES = {"atk": (3, [0, 1, 2], 4.0, "普攻"), "s1": (0, [0, 1, 2], 6.0, "S1 起风"), "s2": (1, [1, 2], 6.0, "S2 裂潮"),
         "s3": (2, [2], 8.0, "S3 判决"), "ult": (4, [2], 8.0, "终结技 宣判")}
W, H = 640, 360


def cols_for(mv):
    """[(栏名, 提交 None = HEAD, 额外参数)]"""
    if mv == "atk":
        return [("旧版（转平面前）", None, ["--bal=fx/px_plane=0"]),
                ("现在（光锥 + 紫）", "OLD", []),
                ("新版（星光 + 白粉）", None, ["--bal=fx/ir_atk_star=1"])]
    return [("现在（紫 / 蓝）", "OLD", []), ("新版（白 + 粉）", None, [])]


def font(sz):
    for p in ("C:/Windows/Fonts/msyh.ttc", "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",
              "/usr/share/fonts/noto-cjk/NotoSansCJK-Regular.ttc", "/usr/share/fonts/truetype/wqy/wqy-microhei.ttc"):
        try:
            return ImageFont.truetype(p, sz)
        except OSError:
            pass
    return ImageFont.load_default()


def switch(ref):
    """把 game/ 切到 ref（HEAD = 切回），重新导入、生成 index.json"""
    if subprocess.run(["git", "checkout", ref, "--", "game"], cwd=ROOT).returncode != 0:   # 虚拟机是浅克隆：旧提交要先按完整号取下来
        full = subprocess.run(["git", "rev-parse", ref], cwd=ROOT, capture_output=True, text=True).stdout.strip()
        subprocess.run(["git", "fetch", "-q", "--depth", "1", "origin", full if len(full) == 40 else ref], cwd=ROOT)
        subprocess.run(["git", "checkout", "FETCH_HEAD" if ref != "HEAD" else ref, "--", "game"], cwd=ROOT, check=True)
    if ref == "HEAD":
        subprocess.run(["git", "clean", "-fdq", "--", "game/art/fx/pxp", "game/data"], cwd=ROOT)
    subprocess.run([GR.find_godot(), "--headless", "--path", GAME, "--import"], cwd=ROOT, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if os.path.exists(os.path.join(ROOT, "tools", "asset_index.py")):
        subprocess.run([sys.executable, os.path.join(ROOT, "tools", "asset_index.py")], cwd=ROOT, stdout=subprocess.DEVNULL)
    print("== game/ →", ref, flush=True)


def shoot(tag, mode, tier, start, n, extra):
    fdir = os.path.join(BUILD, tag)
    shutil.rmtree(fdir, ignore_errors=True)
    os.makedirs(fdir)
    args = [GR.find_godot(), "--audio-driver", "Dummy", "--fixed-fps", "30", "--path", GAME, "res://tests/elite_demo_shot.tscn", "--",
            "--shot_op=irene", "--shot_stage=%d" % tier, "--shot_mode=%d" % mode, "--shot_dir=" + fdir.replace("\\", "/"),
            "--shot_start=%g" % start, "--shot_every=1", "--shot_n=%d" % n, "--shot_w=%d" % W, "--shot_h=%d" % H] + extra
    out, err, _ = GR.run_godot(args, 900)
    errs = GR.script_errors(out, err)
    fs = sorted(glob.glob(os.path.join(fdir, "f_*.png")))
    print(tag, len(fs), "帧", errs[:3], flush=True)
    return fs


def trace_cmp(a):
    """同种子 TRACE：旧提交 vs HEAD（星光开），批跑（--fixed-fps 60）与玩家时钟（--realtime --playclock）各一局"""
    res = {}
    for ref in ("HEAD", a.old):
        if ref != "HEAD":
            switch(ref)
        for pc in (False, True):
            args = [GR.find_godot(), "--audio-driver", "Dummy", "--resolution", "1280x720", "--fixed-fps", "60", "--path", GAME, "--",
                    "--balance", "--nodeath", "--trace=1", "--seed=23", "--op=irene", "--elite2", "--sptest", "--maxt=%d" % (120 if pc else 300),
                    "--bal=growth/late_shape=1"] + (["--bal=fx/ir_atk_star=1"] if ref == "HEAD" else []) + (["--realtime", "--playclock"] if pc else [])
            out, err, _ = GR.run_godot(args, 1200)
            tag = "%s_%s" % ("new" if ref == "HEAD" else "old", "pc" if pc else "batch")
            open(os.path.join(a.out, "trace_%s.log" % tag), "w").write((out or "") + "\n" + (err or ""))
            res[(ref == "HEAD", pc)] = [l for l in (out or "").splitlines() if l.startswith("TRACE")]
            print(tag, len(res[(ref == "HEAD", pc)]), "行", GR.script_errors(out, err)[:3], flush=True)
    switch("HEAD")
    for pc in (False, True):
        x, y = res[(False, pc)], res[(True, pc)]
        diff = sum(1 for p, q in zip(x, y) if p != q) + abs(len(x) - len(y))
        print("TRACE 艾丽妮 %s 旧提交 vs 新（白粉 + 星光开）：%d / %d 行，%s" % ("玩家时钟" if pc else "批跑", len(x), len(y),
              "逐行一致" if diff == 0 and x else "有差异 %d 行" % diff), flush=True)


def label(im, text, f):
    d = ImageDraw.Draw(im)
    d.rectangle((6, 6, 18 + int(d.textlength(text, font=f)), 38), fill=(0, 0, 0))
    d.text((12, 8), text, fill=(255, 255, 255), font=f)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.environ.get("MEDIA", os.path.join(ROOT, "build", "irene_star_out")))
    ap.add_argument("--old", required=True)
    ap.add_argument("--moves", default="atk,s1,s2,s3,ult")
    ap.add_argument("--start", type=float, default=2.0)
    ap.add_argument("--trace", action="store_true", help="只比 TRACE，不录像")
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    if a.trace:
        trace_cmp(a)
        return
    mvs = [m for m in a.moves.split(",") if m]
    shots = {}
    for ref in ("HEAD", "OLD"):   # 先拍 HEAD 的栏，再切到旧提交拍，最后切回
        if ref == "OLD":
            switch(a.old)
        for mv in mvs:
            mode, tiers, secs, _ = MOVES[mv]
            for ci, (_, cref, extra) in enumerate(cols_for(mv)):
                if (cref or "HEAD") != ref:
                    continue
                for t in tiers:
                    shots[(mv, t, ci)] = shoot("%s_e%d_c%d" % (mv, t, ci), mode, t, a.start, int(secs * 30), extra)
    switch("HEAD")
    f = font(20)
    for mv in mvs:
        mode, tiers, secs, name = MOVES[mv]
        cols = cols_for(mv)
        nc = len(cols)
        fdir = os.path.join(BUILD, "sheet_" + mv)
        shutil.rmtree(fdir, ignore_errors=True)
        os.makedirs(fdir)
        k = 0
        for t in tiers:
            cs = [shots.get((mv, t, ci), []) for ci in range(nc)]
            m = min(len(c) for c in cs)
            best, bk = -1, 0
            for i in range(m):
                sheet = Image.new("RGB", (W * nc + 4 * (nc - 1), H), (12, 12, 16))
                ims = [Image.open(c[i]).convert("RGB") for c in cs]
                e = int((np.abs(np.asarray(ims[-1], np.int16) - np.asarray(ims[-2], np.int16)).sum(axis=2) > 60).sum())
                if e > best:
                    best, bk = e, i
                for ci, im in enumerate(ims):
                    label(im, "%s %s · %s" % (name, TIER[t], cols[ci][0]), f)
                    sheet.paste(im, (ci * (W + 4), 0))
                sheet.save(os.path.join(fdir, "f_%04d.png" % k))
                k += 1
            if m:   # 定格 + 下方 2 倍局部（以她为中心）
                st = Image.open(os.path.join(fdir, "f_%04d.png" % (k - m + bk)))
                big = Image.new("RGB", (st.width, H + 248), (12, 12, 16))
                big.paste(st, (0, 0))
                for ci in range(nc):
                    im = Image.open(cs[ci][bk]).convert("RGB").crop((W // 2 - 160, H // 2 - 90, W // 2 + 160, H // 2 + 30)).resize((640, 240), Image.NEAREST)
                    big.paste(im, (ci * (W + 4), H + 8))
                big.save(os.path.join(a.out, "irene_%s_e%d_still.png" % (mv, t)))
        if k:
            mp4 = os.path.join(a.out, "irene_%s.mp4" % mv)
            subprocess.run([FF, "-y", "-loglevel", "error", "-framerate", "30", "-i", os.path.join(fdir, "f_%04d.png"),
                            "-vf", "scale=trunc(iw/2)*2:trunc(ih/2)*2", "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "20", mp4], check=True)
            print("mp4", mp4, os.path.getsize(mp4) // 1024, "KB", flush=True)


if __name__ == "__main__":
    main()
