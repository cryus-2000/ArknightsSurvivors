# -*- coding: utf-8 -*-
"""能天使枪声对拍录像（10-28）：普攻 / 移动攻击、带攻速加成、冲锋模式 S1、扫射 S2、过载 S3 各录一段原速（30 帧 / 秒，游戏钟与录像钟 1:1），
配上「真正放出的」音效：测试局一律静音（Master 总线静音，不改），录屏时 --sfxtrace 让 Sfx 记下每次真正放出的音效（渲染帧号、名字、音量、音高），
这里按记录从 game/audio/sfx/*.wav 离线混音成 wav 再合进 mp4（H.264 + AAC），没有任何声音从扬声器放出来。只有音效，没有配乐。
左上角标出场景名；打印每段的枪声间隔统计（每个出弹轮次一声：中位间隔应等于实际射击间隔）。

用法：python tools/exu_sync_rec.py [--out <目录>] [--only 普攻,攻速,s1,s2,s3]
输出：主仓库 build/exu_sync_1028/能天使枪声对拍.mp4（各段依次拼接）+ 各段 mp4
窗口经 godot_runner 放副屏 / 屏幕外，静音；ffmpeg 用 imageio_ffmpeg 自带的。
"""
import argparse, glob, json, os, shutil, subprocess, sys, wave
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import godot_runner as GR

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SFX = os.path.join(ROOT, "game", "audio", "sfx")
SR = 44100
FPS = 30

# 名字, 队长 / 编队, 额外参数, 开录秒, 录多少秒
SCENES = [
    ("普攻 + 移动攻击（机器人一直在跑）", "exusiai", "", 24.0, 12.0),
    ("带攻速加成（狙击攻速 +40%）", "exusiai", "--grant=150", 24.0, 12.0),
    ("冲锋模式 S1（强力弹 6 发）", "mizuki+exusiai", "--maxprog --sptest --onlyskill=0", 26.0, 12.0),
    ("扫射模式 S2（8 秒间隔 0.2）", "mizuki+exusiai", "--maxprog --sptest --onlyskill=1", 26.0, 12.0),
    ("过载模式 S3（每轮 4 连射）", "mizuki+exusiai", "--maxprog --sptest --onlyskill=2", 26.0, 12.0),
]
KEYS = ["普攻", "攻速", "s1", "s2", "s3"]


def load_wav(name, cache={}):
    if name not in cache:
        try:
            w = wave.open(os.path.join(SFX, name + ".wav"))
        except FileNotFoundError:
            cache[name] = None
            return None
        sr, ch = w.getframerate(), w.getnchannels()
        x = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(np.float64) / 32768.0
        if ch > 1:
            x = x.reshape(-1, ch).mean(1)
        cache[name] = (x, sr)
    return cache[name]


def mix(trace, frame0, n_frames):
    out = np.zeros(int((n_frames / FPS + 2.0) * SR))
    for fr, name, vol, pitch in trace:
        w = load_wav(name)
        if w is None:
            continue
        x, sr = w
        idx = np.arange(0, len(x) - 1, sr / SR * pitch)
        y = np.interp(idx, np.arange(len(x)), x) * 10 ** (vol / 20.0)
        at = int((fr - frame0) / FPS * SR)
        if at < 0:
            continue
        j = min(len(out), at + len(y))
        out[at:j] += y[: j - at]
    pk = np.abs(out).max()
    if pk > 0.89:
        out *= 0.89 / pk
    return out


def write_wav(path, y):
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((np.clip(y, -1, 1) * 32767).astype(np.int16).tobytes())


def label_frames(fdir, text):
    from PIL import Image, ImageDraw, ImageFont
    font = ImageFont.truetype(r"C:\Windows\Fonts\msyh.ttc", 26)
    for p in sorted(glob.glob(os.path.join(fdir, "rec_*.png"))):
        im = Image.open(p).convert("RGB")
        d = ImageDraw.Draw(im)
        d.rectangle([0, 0, 12 + 26 * len(text), 44], fill=(10, 16, 24))
        d.text((10, 4), text, font=font, fill=(235, 240, 245))
        im.save(p)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join(GR.common_root(), "build", "exu_sync_1028"))
    ap.add_argument("--only", default="")
    ap.add_argument("--seed", type=int, default=3)
    a = ap.parse_args()
    only = [k for k in a.only.split(",") if k]
    import imageio_ffmpeg
    ff = imageio_ffmpeg.get_ffmpeg_exe()
    os.makedirs(a.out, exist_ok=True)
    GR.ensure_imported(os.path.join(ROOT, "game"))
    parts = []
    for key, (label, squad, extra, start, secs) in zip(KEYS, SCENES):
        if only and key not in only:
            continue
        fdir = os.path.join(a.out, "frames_" + key)
        shutil.rmtree(fdir, ignore_errors=True)
        os.makedirs(fdir, exist_ok=True)
        sq = squad.split("+")
        args = [GR.find_godot(), "--path", os.path.join(ROOT, "game"), "--audio-driver", "Dummy", "--fixed-fps", str(FPS), "--",
                "--balance", "--seed=%d" % a.seed, "--op=" + sq[0], "--bot=expert", "--realtime", "--rtfrom=%g" % max(0.0, start - 2.0),
                "--recframes=%g,%d" % (start, int(secs * FPS)), "--shotdir=" + fdir, "--sfxtrace", "--sfxstat"]
        if len(sq) > 1:
            args.append("--squad=" + ",".join(sq[1:]))
        args += extra.split()
        out, err, to = GR.run_godot(args, 1800)
        errs = GR.script_errors(out, err)
        tr, req = None, {}
        for ln in out.splitlines():
            if ln.startswith("SFXTRACE "):
                tr = json.loads(ln[9:])
            elif ln.startswith("SFXREQ "):
                req = json.loads(ln[7:])
        n = len(glob.glob(os.path.join(fdir, "rec_*.png")))
        if errs or to or tr is None or n == 0:
            print(key, "失败：", "超时" if to else ("；".join(errs[:3]) or "没有帧 / 没有 SFXTRACE"))
            continue
        ev = [e for e in tr["trace"] if e[1].startswith("op_exusiai_atk")]
        t = [(e[0] - tr["frame0"]) / FPS for e in ev]
        gaps = np.diff(t) if len(t) > 1 else np.array([])
        cues = [e[1] for e in tr["trace"] if e[1] in ("op_exusiai_s1", "op_exusiai_s2", "op_exusiai_s3", "op_exusiai_big")]
        print("%-4s 枪声 %d 声，间隔中位 %.3f 秒（<0.1 秒的 %d 个）；发动提示 / big：%s" % (
            key, len(ev), float(np.median(gaps)) if len(gaps) else 0.0, int((gaps < 0.1).sum()) if len(gaps) else 0, ",".join(cues) or "无"), flush=True)
        r = [sum(v[i] for k, v in req.items() if k.startswith("op_exusiai_atk")) for i in range(5)]
        print("     枪声请求 %d、实播 %d、同名合并 %d、满槽 / 同时发声上限丢弃 %d；命中 请求 %d 实播 %d（每颗子弹命中一声，同名 0.14 秒合并）" % (
            r[0], r[1], r[2], r[3], req.get("op_exusiai_hit", [0, 0])[0], req.get("op_exusiai_hit", [0, 0])[1]), flush=True)
        label_frames(fdir, label)
        wav = os.path.join(fdir, "mix.wav")
        write_wav(wav, mix(tr["trace"], tr["frame0"], n))
        mp4 = os.path.join(a.out, "seg_%s.mp4" % key)
        subprocess.run([ff, "-y", "-loglevel", "error", "-framerate", str(FPS), "-i", os.path.join(fdir, "rec_%05d.png"), "-i", wav,
                        "-vf", "scale=1280:-2", "-c:v", "libx264", "-crf", "20", "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "160k", "-shortest", mp4], check=True)
        parts.append(mp4)
        shutil.rmtree(fdir, ignore_errors=True)
    if parts:
        lst = os.path.join(a.out, "list.txt")
        open(lst, "w", encoding="utf-8").write("".join("file '%s'\n" % p.replace("\\", "/") for p in parts))
        final = os.path.join(a.out, "能天使枪声对拍.mp4")
        subprocess.run([ff, "-y", "-loglevel", "error", "-f", "concat", "-safe", "0", "-i", lst, "-c", "copy", final], check=True)
        os.remove(lst)
        print("视频", final, os.path.getsize(final))
    return 0


if __name__ == "__main__":
    sys.exit(main())
