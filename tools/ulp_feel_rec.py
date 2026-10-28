# -*- coding: utf-8 -*-
"""乌尔比安手感对照录像（10-28 用户「乌尔比安的手感不太好，钝感很强」）：乌尔比安当队长、高手机器人自动走位，原速 30 帧（--realtime --fixed-fps 30），
音轨 = 真正放出的音效（测试局静音，--sfxtrace 记录后离线混，同 tools/exu_sync_rec.py）。
用法：python tools/ulp_feel_rec.py <段名> <标签> [--game <game 目录>] [--op 干员] [--t0 秒] [--sec 秒] [附加游戏参数…]
  每次录一段，存 build/ulp_feel/seg_<段名>.mp4；--concat a,b 把已录的段按顺序拼成 build/ulp_feel/乌尔比安手感对照.mp4
"""
import glob, json, os, shutil, subprocess, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import godot_runner as GR
import exu_sync_rec as R

FPS = R.FPS
OUT = os.path.join(GR.common_root(), "build", "ulp_feel")


def ffmpeg():
    import imageio_ffmpeg
    return imageio_ffmpeg.get_ffmpeg_exe()


def record(name, label, game, t0, sec, extra, op="ulpianus"):
    fdir = os.path.join(OUT, "frames_" + name)
    shutil.rmtree(fdir, ignore_errors=True)
    os.makedirs(fdir)
    GR.ensure_imported(game)
    args = [GR.find_godot(), "--path", game, "--audio-driver", "Dummy", "--fixed-fps", str(FPS), "--",
            "--balance", "--realtime", "--rtfrom=%d" % max(0, t0 - 5), "--nodeath", "--seed=3", "--op=" + op, "--bot=master",
            "--recframes=%s,%d" % (t0, int(sec * FPS)), "--shotdir=" + fdir.replace(os.sep, "/"), "--maxt=%d" % (t0 + sec + 10),
            "--sfxtrace"] + extra
    out, err, to = GR.run_godot(args, 1800)
    errs = GR.script_errors(out, err)
    tr = None
    for ln in out.splitlines():
        if ln.startswith("SFXTRACE "):
            tr = json.loads(ln[9:])
    frames = sorted(glob.glob(os.path.join(fdir, "rec_*.png")))
    if errs or to or not frames:
        print("失败：", "超时" if to else ("；".join(errs[:3]) or "没有帧"))
        return 1
    print("帧数 %d ÷ %.1f 秒 = %.1f 帧/秒" % (len(frames), sec, len(frames) / sec))
    wav = os.path.join(OUT, "mix_%s.wav" % name)
    ev = [] if tr is None else [[e[0] - tr["frame0"], e[1], e[2], e[3]] for e in tr["trace"]]
    R.write_wav(wav, R.mix(ev, 0, len(frames)))
    R.label_frames(fdir, label)
    mp4 = os.path.join(OUT, "seg_%s.mp4" % name)
    subprocess.run([ffmpeg(), "-y", "-loglevel", "error", "-framerate", str(FPS), "-i", os.path.join(fdir, "rec_%05d.png"), "-i", wav,
                    "-vf", "scale=1280:-2", "-c:v", "libx264", "-crf", "27", "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "128k", "-shortest", mp4], check=True)
    os.remove(wav)
    print("段", mp4, os.path.getsize(mp4))
    return 0


def concat(names):
    lst = os.path.join(OUT, "list.txt")
    open(lst, "w", encoding="utf-8").write("".join("file '%s'\n" % os.path.join(OUT, "seg_%s.mp4" % n).replace("\\", "/") for n in names))
    final = os.path.join(OUT, "乌尔比安手感对照.mp4")
    subprocess.run([ffmpeg(), "-y", "-loglevel", "error", "-f", "concat", "-safe", "0", "-i", lst, "-c", "copy", final], check=True)
    os.remove(lst)
    print("视频", final, os.path.getsize(final))


def main():
    a = sys.argv[1:]
    if a and a[0] == "--concat":
        concat(a[1].split(","))
        return 0
    name, label = a[0], a[1]
    rest = a[2:]
    game, t0, sec, extra, op = os.path.join(R.ROOT, "game"), 40.0, 15.0, [], "ulpianus"
    i = 0
    while i < len(rest):
        if rest[i] == "--game":
            game = os.path.abspath(rest[i + 1]); i += 2
        elif rest[i] == "--t0":
            t0 = float(rest[i + 1]); i += 2
        elif rest[i] == "--op":
            op = rest[i + 1]; i += 2
        elif rest[i] == "--sec":
            sec = float(rest[i + 1]); i += 2
        else:
            extra.append(rest[i]); i += 1
    os.makedirs(OUT, exist_ok=True)
    return record(name, label, game, t0, sec, extra, op)


if __name__ == "__main__":
    sys.exit(main())
