# -*- coding: utf-8 -*-
"""鸭爵实战录像（docs/216 §11）：自然对局，--duckat 指定出现时刻，机器人追打；从出现前 1 秒录到被打倒后 2 秒。
1920×1080、--realtime 30 帧、原色原速；音轨 = 真正放出的音效（测试局静音，--sfxtrace 记录后离线混，同 tools/exu_sync_rec.py），没有配乐。
用法：python tools/duck_rec.py [--seed 1] [--at 200] [--bot expert] [--crf 20]
输出：主仓库 Claude outputs/duck_lord_1104/鸭爵实战.mp4（超过 25 MiB 自动提高 crf 重编）
"""
import argparse, glob, json, os, re, shutil, subprocess, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import godot_runner as GR
import exu_sync_rec as R

ROOT = R.ROOT
FPS = R.FPS
ap = argparse.ArgumentParser()
ap.add_argument("--seed", type=int, default=1)
ap.add_argument("--at", type=float, default=200.0)
ap.add_argument("--bot", default="expert")
ap.add_argument("--crf", type=int, default=20)
ap.add_argument("--secs", type=float, default=32.0)
ap.add_argument("--res", default="1920x1080", help="游戏窗口分辨率；近镜头用 960x540 再整数倍放大到 1920×1080（像素不糊）")
ap.add_argument("--viewh", type=int, default=0, help="近镜头：render/view_h_desk 覆盖（缺省 1080 = 正常镜头；560 ≈ 拉近 1.9 倍）")
ap.add_argument("--extra", default="", help="透传给游戏的额外参数（空格分隔），如 --bal=duck/hp_mult=3 拉长演示")
ap.add_argument("--zoom", type=int, default=0, help="战斗画面缩放 %%（--camzoom，近镜头用；0 = 缺省）")
a = ap.parse_args()

OUT = os.path.join(GR.common_root(), "Claude outputs", "duck_lord_1104")
WORK = os.path.join(GR.common_root(), "build", "duck_rec")
fdir = os.path.join(WORK, "frames")
shutil.rmtree(fdir, ignore_errors=True)
os.makedirs(fdir)
os.makedirs(OUT, exist_ok=True)
GR.ensure_imported(os.path.join(ROOT, "game"))
t0 = a.at - 1.0
args = [GR.find_godot(), "--path", os.path.join(ROOT, "game"), "--audio-driver", "Dummy", "--fixed-fps", str(FPS), "--resolution", a.res, "--",
        "--balance", "--realtime", "--nodeath", "--seed=%d" % a.seed, "--bot=" + a.bot, "--duckat=%g" % a.at,
        "--rtfrom=%g" % (t0 - 3), "--recframes=%g,%d" % (t0, int(a.secs * FPS)), "--shotdir=" + fdir.replace(os.sep, "/"),
        "--sfxtrace", "--maxt=%d" % (t0 + a.secs + 3)] + (["--camzoom=%d" % a.zoom] if a.zoom else []) + (["--bal=render/view_h_desk=%d" % a.viewh] if a.viewh else []) + a.extra.split()
out, err, to = GR.run_godot(args, 3000)
open(os.path.join(WORK, "run.log"), "w", encoding="utf-8").write(out + "\n----\n" + err)
errs = GR.script_errors(out, err)
tr = None
kill = None
for ln in out.splitlines():
    if ln.startswith("SFXTRACE "):
        tr = json.loads(ln[9:])
    m = re.match(r"DUCK (kill|fled) t=([\d.]+)", ln)
    if m:
        kill = (m.group(1), float(m.group(2)))
    if ln.startswith("DUCK"):
        print(ln)
frames = sorted(glob.glob(os.path.join(fdir, "rec_*.png")))
if errs or to or not frames or tr is None or kill is None:
    print("失败：", "超时" if to else ("；".join(errs[:3]) or "没有帧 / SFXTRACE / DUCK 行"), len(frames))
    sys.exit(1)
n = min(len(frames), int((kill[1] + 2.0 - t0) * FPS))
for p in frames[n:]:
    os.remove(p)
f0 = tr["frame0"]
ev = [[e[0] - f0, e[1], e[2], e[3]] for e in tr["trace"] if 0 <= e[0] - f0 < n]   # 剪掉的尾巴上的音效不混
wav = os.path.join(WORK, "mix.wav")
R.write_wav(wav, R.mix(ev, 0, n))
import imageio_ffmpeg
ff = imageio_ffmpeg.get_ffmpeg_exe()
final = os.path.join(OUT, "鸭爵实战.mp4")
crf = a.crf
while True:
    subprocess.run([ff, "-y", "-loglevel", "error", "-framerate", str(FPS), "-i", os.path.join(fdir, "rec_%05d.png"), "-i", wav, "-frames:v", str(n),
                    "-vf", "scale=1920:1080:flags=neighbor", "-c:v", "libx264", "-crf", str(crf), "-preset", "slow", "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "160k", "-shortest", final], check=True)
    mb = os.path.getsize(final) / 1048576.0
    if mb <= 25.0 or crf >= 32:
        break
    crf += 2
print("结果", kill[0], "出现后 %.1f 秒" % (kill[1] - a.at), "；帧", n, "；crf", crf, "；%.1f MiB" % mb, final)
