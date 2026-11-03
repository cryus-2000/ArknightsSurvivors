# -*- coding: utf-8 -*-
"""pixelfx 放开版展示段录像（docs/242 §5）：一名干员的普攻、S1、S2、S3、终结技、队友版按顺序各录一小段再拼成一条，只录新版。

原速 30 帧（--realtime --playclock --fixed-fps 30），1920×1080，原色，带声音（--sfxtrace 离线混音效 / 语音 / 配乐，tools/rec_audio.py；测试局本身静音）；开关 fx/px_unleashed = 1（--lo 再加 fx/px_ul_lo = 1 录网页低档）。
技能用 ult/test_skill_*（每 2.5 秒把队长第 N 个技能充满），终结技用 ult/test_fill_at + 刷怪（同 tools/ult_rec.py），队友版让别人当队长、本人进编队。
用法：python tools/px_showcase_rec.py <干员> [--mate 队长] [--seed 13] [--at 40] [--secs 7] [--lo] [--deco0] [--out 目录] [--tmp 目录]
"""
import argparse, glob, os, shutil, subprocess, sys, tempfile
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import godot_runner as GR
import rec_audio as RA
import imageio_ffmpeg

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
FF = imageio_ffmpeg.get_ffmpeg_exe()
ap = argparse.ArgumentParser()
ap.add_argument("op")
ap.add_argument("--mate", default="")
ap.add_argument("--seed", type=int, default=13)
ap.add_argument("--at", type=float, default=40.0)
ap.add_argument("--secs", type=float, default=7.0)
ap.add_argument("--lo", action="store_true")
ap.add_argument("--deco0", action="store_true", help="装饰层关掉（fx/px_deco_k = 0），验收「只剩核心也看得清」，docs/242 §8")
ap.add_argument("--elites", default="", help="逗号分隔的精英档（例 0,1,2）：每招按这几档依次各录一段（balance fx/px_ul_elite，只换画面），队友版只录一次；docs/242 §10")
ap.add_argument("--tmp", default=tempfile.gettempdir())
ap.add_argument("--out", default="")
ap.add_argument("--mute", action="store_true", help="不配声音")
a = ap.parse_args()
out = a.out or os.path.join(ROOT, "build", "px_showcase")
os.makedirs(out, exist_ok=True)
mate = a.mate or ("hoshiguma" if a.op != "hoshiguma" else "skadi")
at = a.at
SK = lambda i: ["--maxprog", "--bal=ult/test_skill_at=%g" % (at + 0.2), "--bal=ult/test_skill_idx=%d" % i, "--bal=ult/test_skill_every=2.5"]
SEGS = [   # (标签, 队长, 编队, 额外参数)
    ("basic", a.op, "", []),
    ("s1", a.op, "", SK(0)),
    ("s2", a.op, "", SK(1)),
    ("s3", a.op, "", SK(2)),
    ("ult", a.op, "", ["--maxprog", "--bal=ult/bot_n=1", "--bal=ult/test_fill_at=%g" % (at + 1.5), "--bal=ult/test_swarm_at=%g" % (at + 0.3), "--bal=ult/test_swarm_every=6"]),
    ("teammate", mate, a.op, ["--maxprog", "--sptest"]),
]


if a.elites:   # 每招 E0 → E1 → E2 依次一段（队友版只录一次，按真实精英档）
    els = [int(x) for x in a.elites.split(",") if x != ""]
    SEGS = [(t + "_e%d" % e, l, s, x + ["--bal=fx/px_ul_elite=%d" % e]) for t, l, s, x in SEGS if t != "teammate" for e in els] + [g for g in SEGS if g[0] == "teammate"]


def rec(tag, leader, squad, extra):
    fdir = os.path.join(a.tmp, "pxsc_%s_%s" % (a.op, tag))
    shutil.rmtree(fdir, ignore_errors=True)
    os.makedirs(fdir)
    args = [GR.find_godot(), "--path", os.path.join(ROOT, "game"), "--resolution", "1920x1080", "--audio-driver", "Dummy", "--fixed-fps", "30", "--",
            "--balance", "--realtime", "--playclock", "--rtfrom=%g" % max(0.0, at - 3), "--nodeath", "--seed=%d" % a.seed, "--op=" + leader, "--bot=expert",
            "--recframes=%g,%d" % (at, int(a.secs * 30)), "--shotdir=" + fdir.replace(os.sep, "/"), "--maxt=%d" % (at + a.secs + 10),
            "--bal=fx/px_unleashed=1"] + (["--bal=fx/px_ul_lo=1"] if a.lo else []) + (["--bal=fx/px_deco_k=0"] if a.deco0 else []) + (["--squad=" + squad] if squad else []) + extra + ([] if a.mute else ["--sfxtrace"])
    o, e, to = GR.run_godot(args, 1800)
    n = len(glob.glob(os.path.join(fdir, "rec_*.png")))
    snd = ""
    if not a.mute and n:
        tr, mus = RA.parse(o)
        if tr is None:
            snd = "声音：没拿到 SFXTRACE"
        else:
            y, has_mus = RA.mix_audio(tr, mus or {}, n + 6)   # + 6 帧 = 段尾黑场
            RA.write_wav(os.path.join(fdir, "mix.wav"), y[: int((n + 6) / 30.0 * RA.SR)])
            snd = "声音：" + RA.summary(tr, has_mus)
    print(tag, "frames", n, "errors", GR.script_errors(o, e)[:3], "timeout" if to else "", snd, flush=True)
    return fdir if n else None


dirs = [(t, rec(t, l, s, x)) for t, l, s, x in SEGS]
# 拼接：每段加一行小标签（drawtext 需要字体，这里用 ffmpeg 自带的 lavfi 不写字，段间插 6 帧黑场分隔）
lst = os.path.join(a.tmp, "pxsc_%s_list.txt" % a.op)
parts = []
for t, d in dirs:
    if not d:
        continue
    seg = os.path.join(a.tmp, "pxsc_%s_%s.mp4" % (a.op, t))
    wav = os.path.join(d, "mix.wav")
    au = ["-i", wav] if os.path.exists(wav) else ["-f", "lavfi", "-i", "anullsrc=r=%d:cl=mono" % RA.SR]   # 没声音的段垫静音，拼接时每段都有音轨
    subprocess.run([FF, "-y", "-loglevel", "error", "-framerate", "30", "-i", os.path.join(d, "rec_%05d.png")] + ([] if a.mute else au) + ["-vf", "tpad=stop=6:stop_mode=add:color=black",
                    "-c:v", "libx264", "-preset", "veryfast", "-crf", "12", "-pix_fmt", "yuv420p"] + ([] if a.mute else ["-c:a", "aac", "-b:a", "192k", "-shortest"]) + [seg], check=True)
    parts.append(seg)
    shutil.rmtree(d, ignore_errors=True)
open(lst, "w").write("".join("file '%s'\n" % p.replace("\\", "/") for p in parts))
total = len(parts) * (a.secs + 0.2)
kbps = int(25.0 * 0.92 * 8 * 1024 / max(total, 1.0)) - (0 if a.mute else 160)   # 音轨 160k 从码率里扣
mp4 = os.path.join(out, "%s_showcase%s%s%s.mp4" % (a.op, "_elite" if a.elites else "", "_lo" if a.lo else "", "_deco0" if a.deco0 else ""))
subprocess.run([FF, "-y", "-loglevel", "error", "-f", "concat", "-safe", "0", "-i", lst, "-c:v", "libx264", "-preset", "slow", "-b:v", "%dk" % kbps,
                "-maxrate", "%dk" % int(kbps * 1.3), "-bufsize", "%dk" % (kbps * 2), "-pix_fmt", "yuv420p", "-r", "30"] + ([] if a.mute else ["-c:a", "aac", "-b:a", "160k"]) + [mp4], check=True)
for p in parts:
    os.remove(p)
print("showcase", mp4, "%.1f MiB" % (os.path.getsize(mp4) / 1048576), "段：" + " / ".join(t for t, d in dirs if d))
