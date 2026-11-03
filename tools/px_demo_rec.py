# -*- coding: utf-8 -*-
"""pixelfx 放开版图鉴演示录像（协调人 11-03：用户要看实际画面，按图鉴详情页的技能演示录）：game/tests/px_demo_rec.tscn 跑图鉴演示（demo_op），
每招按 E0 → E1 → E2 各一段（图鉴的阶段 + 模式：普攻 = 3、技能 = 0–2、终结技 = 4「演示终结技」），原速 30 帧（--fixed-fps 30，每帧存图），
--sfxtrace 离线混音效 / 语音 / 配乐（混音同 tools/ult_rec.py），每段左上角标招式名和档位，拼成一个 mp4。经 godot_runner 启动：屏幕外、不抢焦点、不开音频设备。
镜头与图鉴一致：视口 = 图鉴舞台框 444×388 × K，gallery/demo_zoom × K（同一取景、K 倍分辨率）。
用法：python tools/px_demo_rec.py <干员> [--segs basic:0,1,2/s1:0,1,2:8/s2:1,2/s3:2/ult:2] [--k 2] [--start 1] [--jobs 2] [--out 文件] [--extra "--bal=…"]
  每段 = 招式（basic / s1 / s2 / s3 / ult）:精英档列表[:秒数]。公共工具（样板分支维护，11-04 由星熊 fc07a9449 与德克萨斯 551a1c208 两份合并：
  取星熊版的图鉴取景 / 招式名 / 配乐低通，加德克萨斯版的 --start 与每段秒数；混音用 tools/rec_audio.py）。
"""
import argparse, glob, json, os, shutil, subprocess, sys
from concurrent.futures import ThreadPoolExecutor
from PIL import Image, ImageDraw, ImageFont
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import godot_runner as GR
import rec_audio as RA
import imageio_ffmpeg
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
FF = imageio_ffmpeg.get_ffmpeg_exe()
ap = argparse.ArgumentParser()
ap.add_argument("op")
ap.add_argument("--segs", default="basic:0,1,2/s1:0,1,2/s2:1,2/s3:2/ult:2")
ap.add_argument("--k", type=int, default=2)
ap.add_argument("--jobs", type=int, default=2)
ap.add_argument("--out", default="")
ap.add_argument("--tmp", default=os.path.join(ROOT, "build", "px_demo_rec"))
ap.add_argument("--extra", default="")
ap.add_argument("--start", type=float, default=1.0, help="演示开始后第几秒起录（德克萨斯版）")
ap.add_argument("--sha", default="", help="门禁核对的提交前缀（录哪一版）")
ap.add_argument("--no-gate", action="store_true", help="跳过开录门禁（只给样板自测用，交付录像不许用）")
a = ap.parse_args()
a.tmp = os.path.abspath(a.tmp)   # Godot 按 game/ 解析相对路径
MODE = {"basic": 3, "s1": 0, "s2": 1, "s3": 2, "ult": 4}
SECS = {"basic": 4.0, "s1": 6.5, "s2": 7.0, "s3": 7.5, "ult": 10.0}
DZ = 0.68   # balance.json gallery/demo_zoom 缺省
def names():
    ch = json.load(open(os.path.join(ROOT, "game", "data", "characters", a.op + ".json"), encoding="utf-8"))
    nm = {"basic": "普攻「%s」" % ch.get("attack", {}).get("name", "")}
    for i, s in enumerate(ch.get("skills", [])[:3]):
        nm["s%d" % (i + 1)] = "%s技能「%s」" % ("一二三"[i], s.get("name", ""))
    ut = json.load(open(os.path.join(ROOT, "game", "data", "ult_text.json"), encoding="utf-8")) if os.path.exists(os.path.join(ROOT, "game", "data", "ult_text.json")) else {}
    un = ut.get("ops", {}).get(a.op, {}).get("ult", {}).get("name", "")
    nm["ult"] = "终结技「%s」" % un if un else "终结技"
    return nm


def font(sz):
    for p in ("C:/Windows/Fonts/msyh.ttc", os.path.join(ROOT, "game", "fonts", "ui.ttf"), os.path.join(ROOT, "game", "fonts", "ui_fallback.otf")):   # 雅黑优先（游戏 ui 字体缺「殁」「阈」等字，组长 11-04）
        if os.path.exists(p):
            return ImageFont.truetype(p, sz)
    return ImageFont.load_default()


def one(seg):
    mv, el, secs = seg
    tag = "%s_%s_e%d" % (a.op, mv, el)
    fdir = os.path.join(a.tmp, tag)
    shutil.rmtree(fdir, ignore_errors=True)
    os.makedirs(fdir)
    n = int(secs * 30)
    args = [GR.find_godot(), "--path", os.path.join(ROOT, "game"), "--fixed-fps", "30", "res://tests/px_demo_rec.tscn", "--",
            "--rec_op=" + a.op, "--rec_stage=%d" % el, "--rec_mode=%d" % MODE[mv], "--rec_dir=" + fdir.replace(os.sep, "/"), "--rec_start=%g" % a.start, "--rec_n=%d" % n,
            "--rec_w=%d" % (444 * a.k), "--rec_h=%d" % (388 * a.k), "--bal=gallery/demo_zoom=%g" % (DZ * a.k), "--bal=fx/px_unleashed=1", "--sfxtrace"] + a.extra.split()
    o, e, to = GR.run_godot([x for x in args if x], 900)
    got = len(glob.glob(os.path.join(fdir, "rec_*.png")))
    tr, mus = RA.parse(o)
    print(tag, "帧", got, "/", n, "声音", "有" if tr else "无", "错误", GR.script_errors(o, e)[:3], "超时" if to else "", flush=True)
    return seg, fdir, got, tr, mus


if not a.no_gate:   # 开录前门禁（tools/px_prerecord.py，协调人 11-04）：FAIL 就不录
    gr = subprocess.run([sys.executable, os.path.join(ROOT, "tools", "px_prerecord.py"), a.op] + (["--sha", a.sha] if a.sha else []), cwd=ROOT)
    if gr.returncode:
        sys.exit("录像门禁 PRERECORD FAIL，拒绝录（看上面的 ✗ 项）")
segs = []   # 每段 = 招式:精英档列表[:秒数]（秒数缺省按 SECS；德克萨斯版的每段自定时长）
for part in filter(None, a.segs.split("/")):
    q = part.split(":")
    for e in q[1].split(","):
        segs.append((q[0], int(e), float(q[2]) if len(q) > 2 else SECS[q[0]]))
os.makedirs(a.tmp, exist_ok=True)
with ThreadPoolExecutor(a.jobs) as ex:
    res = list(ex.map(one, segs))
NM = names()
ft = font(15 * a.k)
parts = []
for (mv, el, secs), fdir, got, tr, mus in res:
    if not got:
        continue
    label = "%s · 精%s" % (NM.get(mv, mv), "零一二"[el]) if mv != "ult" else NM["ult"] + "（不分档）"
    for p in sorted(glob.glob(os.path.join(fdir, "rec_*.png"))):   # 左上角标签（半透明底条）
        im = Image.open(p).convert("RGBA")
        ov = Image.new("RGBA", im.size, (0, 0, 0, 0))
        d = ImageDraw.Draw(ov)
        bb = d.textbbox((0, 0), label, font=ft)
        d.rectangle((0, 0, bb[2] + 16 * a.k, bb[3] + 10 * a.k), fill=(4, 14, 30, 170))
        d.text((8 * a.k, 4 * a.k), label, font=ft, fill=(228, 238, 246, 255))
        Image.alpha_composite(im, ov).convert("RGB").save(p)
    seg = os.path.join(a.tmp, "%s_%s_e%d.mp4" % (a.op, mv, el))
    wav = os.path.join(fdir, "mix.wav")
    y, _ = RA.mix_audio(tr or {"frame0": 0, "trace": []}, mus or {}, got)
    RA.write_wav(wav, y)
    subprocess.run([FF, "-y", "-loglevel", "error", "-framerate", "30", "-i", os.path.join(fdir, "rec_%05d.png"), "-i", wav,
                    "-c:v", "libx264", "-preset", "veryfast", "-crf", "14", "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "160k", "-ar", "44100", "-shortest", seg], check=True)
    parts.append(seg)
lst = os.path.join(a.tmp, "%s_list.txt" % a.op)
open(lst, "w").write("".join("file '%s'\n" % p.replace("\\", "/") for p in parts))
total = sum(sg[2] for sg, f, g_, t_, m_ in res if g_)
kbps = min(12000, int(24.0 * 8 * 1024 / max(total, 1.0)) - 160)   # 整条 ≤ 24 MiB
out = a.out or os.path.join(ROOT, "build", "px_demo_rec", "%s_demo.mp4" % a.op)
subprocess.run([FF, "-y", "-loglevel", "error", "-f", "concat", "-safe", "0", "-i", lst, "-c:v", "libx264", "-preset", "slow", "-b:v", "%dk" % kbps,
                "-maxrate", "%dk" % int(kbps * 1.3), "-bufsize", "%dk" % (kbps * 2), "-pix_fmt", "yuv420p", "-r", "30", "-c:a", "aac", "-b:a", "160k", out], check=True)
print("demo", out, "%.1f MiB" % (os.path.getsize(out) / 1048576), "段数", len(parts))
