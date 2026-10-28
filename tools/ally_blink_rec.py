# -*- coding: utf-8 -*-
"""队友闪现修复 + 指挥合唱录像（10-28）。原速 30 帧 / 秒，带 --realtime；测试局静音，--sfxtrace 记下真正放出的音效 / 语音，离线混音合进 mp4。

  blink：同 seed 同时段录两遍——修前（--bal=command/follow_vmax=999 = 原来不限速的随行 lerp）/ 修后，拼成一条；同时打 --blinklog 统计录到的闪现帧
  voice：两次突击（--cmdat 突击 → 归队 → 突击），听两名队友交替开口

用法：python tools/ally_blink_rec.py blink [--seed 2 --squad wisadel,siege,skadi --start 60 --secs 15]
      python tools/ally_blink_rec.py voice [--seed 3 --squad wisadel,siege,skadi --start 60 --secs 22]
输出：主仓库 build/ally_blink_1028/
"""
import argparse, glob, json, os, re, shutil, subprocess, sys, wave
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import godot_runner as GR
import exu_sync_rec as R

ROOT = R.ROOT
FPS = R.FPS
SR = R.SR
VOICE = os.path.join(ROOT, "game", "audio", "voice")


def load_ogg(name, cache={}):
    """语音 ogg 用 ffmpeg 解成单声道 44.1k"""
    if name not in cache:
        p = os.path.join(VOICE, name + ".ogg")
        if not os.path.exists(p):
            cache[name] = None
        else:
            import imageio_ffmpeg
            raw = subprocess.run([imageio_ffmpeg.get_ffmpeg_exe(), "-loglevel", "error", "-i", p, "-f", "s16le", "-ac", "1", "-ar", str(SR), "-"],
                                 capture_output=True, check=True).stdout
            cache[name] = np.frombuffer(raw, dtype=np.int16).astype(np.float64) / 32768.0
    return cache[name]


def mix(trace, frame0, n_frames):
    """音效照 exu_sync_rec.mix；voice:<名> 按语音 ogg 混，vduck:<名> 把这条之后的部分压 vol dB（合唱重叠时先开口的那条）"""
    out = R.mix([t for t in trace if not (t[1].startswith("voice:") or t[1].startswith("vduck:"))], frame0, n_frames) if trace else np.zeros(int((n_frames / FPS + 2.0) * SR))
    out = np.concatenate([out, np.zeros(max(0, int((n_frames / FPS + 2.0) * SR) - len(out)))])
    voices = []   # [名, 开始样本, 音量 dB, [(压低起点, dB)]]
    for fr, name, vol, _p in trace:
        at = int((fr - frame0) / FPS * SR)
        if name.startswith("voice:"):
            voices.append([name[6:], at, vol, []])
        elif name.startswith("vduck:"):
            for v in reversed(voices):
                if v[0] == name[6:]:
                    v[3].append((at, vol))
                    break
    for name, at, vol, ducks in voices:
        x = load_ogg(name)
        if x is None or at < 0:
            continue
        g = np.full(len(x), 10 ** (vol / 20.0))
        for d_at, db in ducks:
            k = max(0, d_at - at)
            g[k:] *= 10 ** (db / 20.0)
        j = min(len(out), at + len(x))
        out[at:j] += (x * g)[: j - at]
    pk = np.abs(out).max()
    if pk > 0.89:
        out *= 0.89 / pk
    return out


def record(tag, a, extra, out_dir, ff, label=""):
    fdir = os.path.join(out_dir, "frames_" + tag)
    shutil.rmtree(fdir, ignore_errors=True)
    os.makedirs(fdir, exist_ok=True)
    sq = a.squad.split(",")
    args = [GR.find_godot(), "--path", os.path.join(ROOT, "game"), "--audio-driver", "Dummy", "--fixed-fps", str(FPS), "--",
            "--balance", "--seed=%d" % a.seed, "--op=" + sq[0], "--squad=" + ",".join(sq[1:]), "--bot=expert", "--realtime",
            "--rtfrom=%g" % max(0.0, a.start - 2.0), "--recframes=%g,%d" % (a.start, int(a.secs * FPS)), "--shotdir=" + fdir,
            "--sfxtrace", "--blinklog", "--trace=5"] + extra
    out, err, to = GR.run_godot(args, 1800)
    errs = GR.script_errors(out, err)
    open(os.path.join(out_dir, "log_%s.txt" % tag), "w", encoding="utf-8").write("\n".join(l for l in out.splitlines() if not l.startswith("SFXTRACE ")))
    tr = None
    blinks = []
    for ln in out.splitlines():
        if ln.startswith("SFXTRACE "):
            tr = json.loads(ln[9:])
        elif ln.startswith("BLINK "):
            m = re.search(r"t=([\d.]+)", ln)
            if m and a.start <= float(m.group(1)) <= a.start + a.secs:
                blinks.append(ln)
        elif ln.startswith("CMD ") or "VOICEPLAY" in ln:
            print(tag, ln)
    n = len(glob.glob(os.path.join(fdir, "rec_*.png")))
    print(tag, "帧数", n, "脚本错误", errs[:3] if errs else 0, "超时" if to else "")
    wav = os.path.join(fdir, "mix.wav")
    R.write_wav(wav, mix(tr["trace"] if tr else [], tr["frame0"] if tr else 0, n))
    mp4 = os.path.join(out_dir, "seg_%s.mp4" % tag)
    vf = "scale=trunc(iw/2)*2:trunc(ih/2)*2"
    if label:   # 左上角标注（修前 / 修后）
        vf += r",drawtext=fontfile='C\:/Windows/Fonts/msyh.ttc':text='%s':x=24:y=24:fontsize=40:fontcolor=white:box=1:boxcolor=black@0.55:boxborderw=10" % label
    subprocess.run([ff, "-y", "-loglevel", "error", "-framerate", str(FPS), "-i", os.path.join(fdir, "rec_%05d.png"), "-i", wav,
                    "-vf", vf, "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "26", "-c:a", "aac", "-b:a", "128k", "-shortest", mp4], check=True)
    return mp4, blinks, n


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("what", choices=["blink", "voice"])
    ap.add_argument("--out", default=os.path.join(GR.common_root(), "build", "ally_blink_1028"))
    ap.add_argument("--seed", type=int, default=2)
    ap.add_argument("--squad", default="wisadel,siege,skadi")
    ap.add_argument("--start", type=float, default=60.0)
    ap.add_argument("--secs", type=float, default=15.0)
    ap.add_argument("--cmdat", default="")
    ap.add_argument("--extra", default="")
    ap.add_argument("--name", default="", help="成片文件名（不含 .mp4）")
    a = ap.parse_args()
    import imageio_ffmpeg
    ff = imageio_ffmpeg.get_ffmpeg_exe()
    os.makedirs(a.out, exist_ok=True)
    GR.ensure_imported(os.path.join(ROOT, "game"))
    ex = a.extra.split()
    if a.what == "blink":
        segs = [("before", ex + ["--bal=command/follow_vmax=999", "--bal=command/bot_roam=1"], "修前（随行不限速）"), ("after", ex + ["--bal=command/bot_roam=1"], "修后")]
        final = os.path.join(a.out, "队友闪现_修前修后.mp4")
    else:
        cm = a.cmdat or "%g,%g,%g" % (a.start + 2, a.start + 10, a.start + 14)
        segs = [("voice", ex + ["--cmdat=" + cm, "--voicelog"], "")]
        final = os.path.join(a.out, (a.name or "突击合唱_两次突击") + ".mp4")
    parts = []
    for tag, extra, label in segs:
        mp4, blinks, n = record(tag, a, extra, a.out, ff, label)
        print(tag, "录到的闪现帧", len(blinks))
        for l in blinks[:30]:
            print("  ", l)
        parts.append(mp4)
    if len(parts) == 1:
        shutil.copyfile(parts[0], final)
    else:
        lst = os.path.join(a.out, "list.txt")
        open(lst, "w", encoding="utf-8").write("".join("file '%s'\n" % p.replace("\\", "/") for p in parts))
        subprocess.run([ff, "-y", "-loglevel", "error", "-f", "concat", "-safe", "0", "-i", lst, "-c", "copy", final], check=True)
    pr = subprocess.run([ff, "-i", final], capture_output=True, text=True, encoding="utf-8", errors="replace").stderr
    print("视频", final, os.path.getsize(final), re.findall(r"Duration: [\d:.]+|\d+(?:\.\d+)? fps", pr))
    return 0


if __name__ == "__main__":
    sys.exit(main())
