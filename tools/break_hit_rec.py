# -*- coding: utf-8 -*-
"""破绽命中音对照录像（10-28）：Boss 战实拍（骑士 Boss 刷在主控旁，--breakloop 每 4 秒给 Boss 开 3 秒破绽窗口，队伍自动打），录一遍（--sfxgap=break_hit:0.12
= 旧节流，trace 里是旧版会放出的全部命中音），按同一份 trace 离线混四条音轨：旧（旧音 + 0.12 秒节流）→ 选中版 C（新音 + 0.25 秒节流）→ 候选 A → 候选 B（同样 0.25 秒节流）。
音轨 = 真正放出的音效（测试局静音，--sfxtrace 记录，同 tools/exu_sync_rec.py），没有配乐。
用法：python tools/break_hit_rec.py   输出：主仓库 build/break_hit_1028/破绽命中音对照.mp4（前置：python game/tools/gen_sfx_break_hit_1028.py 生成候选）
"""
import glob, json, os, shutil, subprocess, sys
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import godot_runner as GR
import exu_sync_rec as R

ROOT = R.ROOT
FPS = R.FPS
OUT = os.path.join(GR.common_root(), "build", "break_hit_1028")
OLD_WAV = os.path.join(OUT, "break_hit_old.wav")
_load = R.load_wav


def load_wav(name, cache={}):
    if name.startswith("break_hit_"):
        path = os.path.join(OUT, name + ".wav")
        if name not in cache:
            import wave
            w = wave.open(path)
            x = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(np.float64) / 32768.0
            cache[name] = (x, w.getframerate())
        return cache[name]
    return _load(name)


R.load_wav = load_wav


def variant(trace, new_name, gap):
    """break_hit 换成 new_name，并按 gap 秒的最短间隔重新节流（旧 = 0.12 不改）"""
    out, last = [], -9.0
    for fr, name, vol, pitch in trace:
        if name == "break_hit":
            t = fr / FPS
            if t - last < gap - 1e-6:
                continue
            last = t
            name = new_name
        out.append([fr, name, vol, pitch])
    return out


def main():
    import imageio_ffmpeg
    ff = imageio_ffmpeg.get_ffmpeg_exe()
    os.makedirs(OUT, exist_ok=True)
    # 旧音从 sfx.gd 改动前的提交读（候选脚本同一个基线）
    import io, soundfile as sf
    b = subprocess.run(["git", "show", "d88b56b56:game/audio/sfx/break_hit.wav"], cwd=ROOT, capture_output=True).stdout
    x, sr = sf.read(io.BytesIO(b), dtype="float32")
    sf.write(OLD_WAV, x if x.ndim == 1 else x.mean(1), sr, subtype="PCM_16")
    fdir = os.path.join(OUT, "frames")
    shutil.rmtree(fdir, ignore_errors=True)
    os.makedirs(fdir)
    GR.ensure_imported(os.path.join(ROOT, "game"))
    args = [GR.find_godot(), "--path", os.path.join(ROOT, "game"), "--audio-driver", "Dummy", "--fixed-fps", str(FPS), "--",
            "--balance", "--realtime", "--nodeath", "--seed=1", "--op=mizuki", "--squad=skadi,saria,texas,exusiai,eyjafjalla", "--prog=6", "--bot=master",
            "--flashspawn=knight_boss", "--breakloop=4:3", "--rtfrom=0", "--recframes=3,%d" % (12 * FPS), "--shotdir=" + fdir.replace(os.sep, "/"),
            "--sfxtrace", "--sfxstat", "--sfxgap=break_hit:0.12"]
    out, err, to = GR.run_godot(args, 1800)
    errs = GR.script_errors(out, err)
    tr = None
    for ln in out.splitlines():
        if ln.startswith("SFXTRACE "):
            tr = json.loads(ln[9:])
    n = len(glob.glob(os.path.join(fdir, "rec_*.png")))
    if errs or to or tr is None or n == 0:
        print("失败：", "超时" if to else ("；".join(errs[:3]) or "没有帧 / 没有 SFXTRACE"))
        return 1
    f0 = tr["frame0"]
    ev = [[e[0] - f0, e[1], e[2], e[3]] for e in tr["trace"]]
    bh = [e[0] / FPS for e in ev if e[1] == "break_hit"]
    print("帧数", n, "；break_hit 旧节流 %d 声，间隔中位 %.2f 秒；0.25 秒节流后 %d 声" % (len(bh), float(np.median(np.diff(bh))) if len(bh) > 1 else 0, len(variant(ev, "x", 0.25)) - len([e for e in ev if e[1] != "break_hit"])), flush=True)
    VARS = [("旧：破绽命中音（带 1650 Hz 钟声，0.12 秒节流）", "break_hit_old", 0.12), ("选中版 C 厚实（去音高，0.25 秒节流）", "break_hit_C", 0.25),
            ("候选 A 闷击（0.25 秒节流）", "break_hit_A", 0.25), ("候选 B 脆裂（0.25 秒节流）", "break_hit_B", 0.25)]
    frames = sorted(glob.glob(os.path.join(fdir, "rec_*.png")))
    parts = []
    for i, (label, nm, gap) in enumerate(VARS):
        wav = os.path.join(OUT, "mix_%d.wav" % i)
        R.write_wav(wav, R.mix(variant(ev, nm, gap), 0, n))
        lf = os.path.join(OUT, "lab_%d" % i)
        shutil.rmtree(lf, ignore_errors=True)
        os.makedirs(lf)
        for p in frames:
            shutil.copy(p, os.path.join(lf, os.path.basename(p)))
        R.label_frames(lf, label)
        mp4 = os.path.join(OUT, "seg_%d.mp4" % i)
        subprocess.run([ff, "-y", "-loglevel", "error", "-framerate", str(FPS), "-i", os.path.join(lf, "rec_%05d.png"), "-i", wav, "-vf", "scale=1280:-2",
                        "-c:v", "libx264", "-crf", "22", "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "160k", "-shortest", mp4], check=True)
        parts.append(mp4)
        shutil.rmtree(lf, ignore_errors=True)
    shutil.rmtree(fdir, ignore_errors=True)
    lst = os.path.join(OUT, "list.txt")
    open(lst, "w", encoding="utf-8").write("".join("file '%s'\n" % p.replace("\\", "/") for p in parts))
    final = os.path.join(OUT, "破绽命中音对照.mp4")
    subprocess.run([ff, "-y", "-loglevel", "error", "-f", "concat", "-safe", "0", "-i", lst, "-c", "copy", final], check=True)
    for f in glob.glob(os.path.join(OUT, "mix_*.wav")) + glob.glob(os.path.join(OUT, "seg_*.mp4")) + [lst]:
        os.remove(f)
    print("视频", final, os.path.getsize(final))
    return 0


if __name__ == "__main__":
    sys.exit(main())
