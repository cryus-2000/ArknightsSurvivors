# -*- coding: utf-8 -*-
"""终结技专属音效候选对比（docs/205 §3）：同一段录像（tools/ult_rec.py --sfx 录下的画面 + SFXTRACE），
把 ult_<干员>_* 换成 build/ult_sfx/<A|B|C>/ 的候选重混声音，A / B / C 依次拼成一条，左上角标套名。不重跑游戏。
用法：python tools/ult_sfx_review.py --tag <ult_rec 的 tag> [--clips u_texas,u_exusiai] [--from 0.8] [--len 7.5] [--group 5]
输出 build/ult_rec/<tag>/abc_<n>.mp4（每条 group 名干员，≤30 MB）。"""
import argparse, json, os, subprocess, sys
import numpy as np

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
src = open(os.path.join(ROOT, "tools", "ult_rec.py"), encoding="utf-8").read()
import imageio_ffmpeg, wave
FF = imageio_ffmpeg.get_ffmpeg_exe()
exec(src[src.index("SR = 44100"):src.index("def one(")])   # _decode / _res / mix_audio / write_wav
try:
    common = subprocess.run(["git", "rev-parse", "--git-common-dir"], cwd=ROOT, capture_output=True, text=True).stdout.strip()
    MAIN = os.path.dirname(os.path.abspath(os.path.join(ROOT, common)))
except OSError:
    MAIN = ROOT
CAND = os.path.join(MAIN, "build", "ult_sfx")
SETS = [("A", "A 厚重写实"), ("B", "B 能量感"), ("C", "C 现有音色加工")]
NAMES = {"texas": "德克萨斯", "exusiai": "能天使", "skalter": "浊心斯卡蒂", "kaltsit": "凯尔希", "ulpianus": "乌尔比安", "skadi": "斯卡蒂",
         "gladiia": "歌蕾蒂娅", "angelina": "安洁莉娜", "eyjafjalla": "艾雅法拉", "wisadel": "维什戴尔", "specter_unchained": "归溟幽灵鲨",
         "mizuki": "水月", "saria": "塞雷娅", "suzuran": "铃兰", "logos": "逻各斯", "hoshiguma": "星熊", "siege": "推进之王", "irene": "艾丽妮",
         "lappland": "拉普兰德", "lumen": "流明"}
FONT = "C\\:/Windows/Fonts/msyh.ttc"

ap = argparse.ArgumentParser()
ap.add_argument("--tag", required=True)
ap.add_argument("--clips", default="")
ap.add_argument("--from", dest="t0", type=float, default=0.8)
ap.add_argument("--len", dest="dur", type=float, default=7.5)
ap.add_argument("--group", type=int, default=5)
a = ap.parse_args()
out = os.path.join(ROOT, "build", "ult_rec", a.tag)
clips = a.clips.split(",") if a.clips else sorted(f[:-11] for f in os.listdir(out) if f.endswith(".sound.json"))
_orig = _decode


def seg(clip, v, label, dst):
    d = json.load(open(os.path.join(out, clip + ".sound.json"), encoding="utf-8"))
    sfx_dir = os.path.join(ROOT, "game", "audio", "sfx")

    def dec(path):
        b = os.path.basename(path)
        if b.startswith("ult_") and os.path.dirname(os.path.abspath(path)) == os.path.abspath(sfx_dir):
            return _orig(os.path.join(CAND, v, b))
        return _orig(path)
    globals()["_decode"] = dec
    n = int((a.t0 + a.dur + 1.0) * 30)
    y, _ = mix_audio(d["sfx"], d.get("music") or {}, n)
    globals()["_decode"] = _orig
    wav = dst + ".wav"
    write_wav(wav, y)
    oid = clip[2:] if clip.startswith("u_") else clip
    name = NAMES.get(oid, oid)
    txt = "%s  %s" % (name, label)
    subprocess.run([FF, "-y", "-loglevel", "error", "-ss", str(a.t0), "-t", str(a.dur), "-i", os.path.join(out, clip + ".mp4"),
                    "-ss", str(a.t0), "-t", str(a.dur), "-i", wav, "-map", "0:v", "-map", "1:a",
                    "-vf", "scale=960:-2,drawtext=fontfile='%s':text='%s':x=16:y=12:fontsize=30:fontcolor=white:box=1:boxcolor=black@0.55:boxborderw=8" % (FONT, txt),
                    "-r", "30", "-c:v", "libx264", "-crf", "30", "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "160k", "-ar", "44100", dst], check=True)
    os.remove(wav)


parts = []
for c in clips:
    for v, label in SETS:
        if not os.path.isdir(os.path.join(CAND, v)):
            continue
        dst = os.path.join(out, "_abc_%s_%s.mp4" % (c, v))
        seg(c, v, label, dst)
        parts.append((c, dst))
groups = [clips[i:i + a.group] for i in range(0, len(clips), a.group)]
for gi, gc in enumerate(groups):
    lst = os.path.join(out, "_abc_%d.txt" % gi)
    with open(lst, "w", encoding="utf-8") as f:
        for c, p in parts:
            if c in gc:
                f.write("file '%s'\n" % p.replace("\\", "/"))
    mp4 = os.path.join(out, "abc_%d.mp4" % (gi + 1))
    subprocess.run([FF, "-y", "-loglevel", "error", "-f", "concat", "-safe", "0", "-i", lst, "-c", "copy", mp4], check=True)
    os.remove(lst)
    print(mp4, "%.1f MB" % (os.path.getsize(mp4) / 1048576), ",".join(gc))
for _, p in parts:
    os.remove(p)
