#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""近战打击感包（docs/246 §12，fx/melee_impact）开 / 关对照：GCP 虚拟机上跑（Linux，xvfb + opengl3），本机不开 Godot。

  rec    斯卡蒂、星熊各一局（队长），同种子开 / 关两遍，--realtime --playclock（顿帧在玩家时钟下才看得见）30 帧原速连存 N 秒，
         拼成 2×2（上斯卡蒂、下星熊；左关右开）1920 宽 mp4，压到 30 MB 以内
  trace  同种子开 / 关 TRACE 逐行比（--fixed-fps 60 批跑模式，不消耗顿帧——顿帧在玩家时钟里本来就会停模拟，开关两局必然分岔）

用法（虚拟机仓库根目录）：python3 tools/melee_impact_rec.py all --out $OUT
"""
import argparse, glob, json, os, shutil, subprocess, sys, wave

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import godot_runner as GR

OPS = [("skadi", ["--bal=fx/px_plane=1"]), ("hoshiguma", [])]
NAMES = {"skadi": "斯卡蒂", "hoshiguma": "星熊", "texas": "德克萨斯"}
NAME = "melee_impact_onoff"
PLAYCLOCK_TRACE = False
KNOB = "fx/melee_impact"   # --knob：开 / 关对照的旋钮（缺省打击感包）；逗号分隔 = 几项一起开 / 关


def kb(on):
    return ["--bal=%s=%d" % (k, on) for k in KNOB.split(",") if k]
EXTRA = []                 # --extra：两局都带的启动参数（如 --elite2 --sptest）
KLABEL = "打击感包"   # --playclock_trace：TRACE 也走玩家时钟（局部卡肉不停世界，开关两局应逐行一致；全局顿帧会在这里分岔）


def godot(args, timeout=5400):
    if os.environ.get("DISPLAY") and os.environ.get("GODOT"):   # GCP 出图虚拟机（tools/gcp/render_prep.sh）：GODOT 已包成 opengl3、画在 Xvfb :99 上
        base = [os.environ["GODOT"], "--path", os.path.join(ROOT, "game"), "--audio-driver", "Dummy"]
    else:
        base = [GR.find_godot(), "--path", os.path.join(ROOT, "game"), "--audio-driver", "Dummy"]
        if os.name != "nt":
            base = ["xvfb-run", "-a", "-s", "-screen 0 1280x720x24", base[0], "--rendering-driver", "opengl3"] + base[1:]
    p = subprocess.run(base + args, capture_output=True, text=True, timeout=timeout)
    return (p.stdout or "") + "\n" + (p.stderr or "")


# ---------------------------------------------------------------- 离线混音（抄 tools/ult_rec.py：--sfxtrace 记下音效 / 语音 / 配乐，按帧号混进 mp4）
try:
    import imageio_ffmpeg as _iff
    FF = _iff.get_ffmpeg_exe()
except Exception:
    FF = "ffmpeg"
SR = 44100
_dec = {}


def _decode(path):
    """任意音频文件 → 44.1k 单声道 float（ffmpeg 解码，缓存）；缺文件返回 None"""
    if path not in _dec:
        if not os.path.exists(path):
            _dec[path] = None
        else:
            r = subprocess.run([FF, "-loglevel", "error", "-i", path, "-f", "f32le", "-ac", "1", "-ar", str(SR), "-"], capture_output=True)
            _dec[path] = np.frombuffer(r.stdout, dtype=np.float32).astype(np.float64) if r.returncode == 0 else None
    return _dec[path]


def _res(p):
    return os.path.join(ROOT, "game", p[len("res://"):].replace("/", os.sep)) if p.startswith("res://") else p


def mix_audio(tr, mus, n_frames):
    """SFXTRACE（音效 / 语音事件）+ MUSTRACE（逐帧配乐采样）→ 单声道 44.1k。增益 = 播放器音量 + 所在总线音量。
    测试局把各总线压到 -80（静音），记录里的总线音量不能用：按玩家缺省设置算（settings.gd：配乐 0.8 / 音效 0.9 / 语音 0.8）"""
    buses = {"Music": 20 * np.log10(0.8), "SFX": 20 * np.log10(0.9), "Voice": 20 * np.log10(0.8)}
    n = int((n_frames / 30.0 + 0.5) * SR)
    fx = np.zeros(n)
    f0 = tr["frame0"]
    for fr, name, vol, pitch in tr["trace"]:
        if name.startswith("vduck:"):
            continue
        if name.startswith("voice:"):
            x, bus = _decode(os.path.join(ROOT, "game", "audio", "voice", name[6:] + ".ogg")), "Voice"
        else:
            x, bus = _decode(os.path.join(ROOT, "game", "audio", "sfx", name + ".wav")), "SFX"
        if x is None or len(x) < 2:
            continue
        idx = np.arange(0, len(x) - 1, float(pitch))
        y = np.interp(idx, np.arange(len(x)), x) * 10 ** ((float(vol) + float(buses.get(bus, 0.0))) / 20.0)
        at = int((fr - f0) / 30.0 * SR)
        if at < 0 or at >= n:
            continue
        j = min(n, at + len(y))
        fx[at:j] += y[: j - at]
    mu = np.zeros(n)
    cut = np.full(n, 20000.0)
    pos = {}
    step = SR // 30
    mg = 10 ** (float(buses.get("Music", 0.0)) / 20.0)
    for fr, hz, ents in mus.get("frames", []):
        at = int((fr - f0) / 30.0 * SR)
        if at < 0 or at >= n:
            continue
        cut[at:at + step] = float(hz)
        live = set()
        for path, vol, ppos in ents:
            x = _decode(_res(path))
            if x is None or len(x) < step:
                continue
            live.add(path)
            p0 = pos.get(path, int(float(ppos) * SR) % len(x))   # 第一次出现按播放位置起，之后每帧推进 1/30 秒（与录像钟 1:1）
            seg = np.take(x, np.arange(p0, p0 + step) % len(x))
            j = min(n, at + step)
            mu[at:j] += seg[: j - at] * 10 ** (float(vol) / 20.0) * mg
            pos[path] = (p0 + step) % len(x)
        for k in list(pos):
            if k not in live:
                del pos[k]
    # 配乐低通（Sfx.music_lp，终结技冲击帧压低）：一阶低通，截止频率逐帧取采样值
    a = 1.0 - np.exp(-2.0 * np.pi * np.minimum(cut, SR * 0.45) / SR)
    y = np.empty(n)
    z = 0.0
    mul, al = mu.tolist(), a.tolist()
    for i in range(n):
        z += al[i] * (mul[i] - z)
        y[i] = z
    out = fx + y
    pk = np.abs(out).max() if n else 0.0
    if pk > 0.89:
        out *= 0.89 / pk
    return out, len(mus.get("frames", [])) > 0 and np.abs(y).max() > 1e-4


def write_wav(path, y):
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((np.clip(y, -1, 1) * 32767).astype(np.int16).tobytes())



def rec(out, t0, secs, seed):
    tiles = []
    for op, ex in OPS:
        for on in (0, 1):
            fdir = os.path.join(out, "fr_%s_%d" % (op, on))
            shutil.rmtree(fdir, ignore_errors=True)
            os.makedirs(fdir)
            log = godot(["--resolution", "1280x720", "--fixed-fps", "30", "--", "--balance", "--nodeath", "--realtime", "--playclock",
                         "--rtfrom=%d" % (t0 - 3), "--seed=%d" % seed, "--op=" + op, "--bot=expert", "--maxprog",
                         ] + kb(on) + ["--recframes=%d,%d" % (t0, secs * 30), "--shotdir=" + fdir, "--maxt=%d" % (t0 + secs + 2), "--sfxtrace"] + ex + EXTRA)
            open(os.path.join(out, "rec_%s_%d.log" % (op, on)), "w").write(log)
            errs = [l for l in log.splitlines() if "SCRIPT ERROR" in l or "Parse Error" in l]
            print(op, on, len(glob.glob(os.path.join(fdir, "rec_*.png"))), "帧", errs[:3], flush=True)
            tiles.append(fdir)
            tr = mus = None
            for ln in log.splitlines():
                if ln.startswith("SFXTRACE "):
                    tr = json.loads(ln[9:])
                elif ln.startswith("MUSTRACE "):
                    mus = json.loads(ln[9:])
            nfr = len(glob.glob(os.path.join(fdir, "rec_*.png")))
            if tr is not None and nfr > 0:
                y, _ = mix_audio(tr, mus or {}, nfr)
                write_wav(os.path.join(fdir, "mix.wav"), y)
                print(op, on, "声音：音效 %d 次（斩肉 %d 次）" % (sum(1 for e in tr["trace"] if not e[1].startswith(("voice:", "vduck:"))), sum(1 for e in tr["trace"] if "flesh" in e[1])), flush=True)
    import imageio_ffmpeg
    ff = imageio_ffmpeg.get_ffmpeg_exe()
    n = min(len(glob.glob(os.path.join(d, "rec_*.png"))) for d in tiles)
    mp4 = os.path.join(out, NAME + ".mp4")
    fnt = os.environ.get("CJK_FONT", "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf")
    labs = [lb for op, _ in OPS for lb in (NAMES.get(op, op) + " " + KLABEL + " 关", NAMES.get(op, op) + " " + KLABEL + " 开（%s=1）" % KNOB)]
    args = [ff, "-y", "-loglevel", "error"]
    for d in tiles:
        args += ["-framerate", "30", "-i", os.path.join(d, "rec_%05d.png")]
    wav = os.path.join(tiles[-1], "mix.wav")   # 声音取「开」那一局（最后一格）
    aud = os.path.exists(wav)
    if aud:
        args += ["-i", wav]
    fl = []
    for i, lb in enumerate(labs):
        dt = ",drawtext=fontfile=%s:text='%s':x=16:y=16:fontsize=30:fontcolor=white:box=1:boxcolor=black@0.6" % (fnt, lb) if os.path.exists(fnt) else ""
        fl.append("[%d:v]scale=960:540%s[v%d]" % (i, dt, i))
    fl.append("[v0][v1]hstack=inputs=2[t];[v2][v3]hstack=inputs=2[b];[t][b]vstack=inputs=2[v]" if len(tiles) == 4 else "[v0][v1]hstack=inputs=2[v]")
    for crf in (23, 27, 31):
        am = ["-map", "%d:a" % len(tiles), "-c:a", "aac", "-b:a", "128k"] if aud else []
        subprocess.run(args + ["-filter_complex", ";".join(fl), "-map", "[v]"] + am + ["-frames:v", str(n), "-c:v", "libx264", "-crf", str(crf),
                               "-preset", "slow", "-pix_fmt", "yuv420p", mp4], check=True)
        if os.path.getsize(mp4) <= 29 * 1024 * 1024:
            break
    print("录像", mp4, "%.1f MB" % (os.path.getsize(mp4) / 1048576.0), n, "帧", flush=True)
    for d in tiles:
        shutil.rmtree(d, ignore_errors=True)


def traces(log):
    return [l for l in log.splitlines() if l.startswith("TRACE")]


def trace(out, seed, maxt):
    ok = True
    for op, ex in OPS:
        tr = []
        for on in (0, 1):
            pc = ["--realtime", "--playclock"] if PLAYCLOCK_TRACE else []
            log = godot(["--resolution", "1280x720", "--fixed-fps", "60", "--", "--balance", "--nodeath", "--trace=1",
                         "--seed=%d" % seed, "--op=" + op, "--elite2", "--sptest", "--maxt=%d" % maxt] + kb(on) + pc + ex + EXTRA)
            open(os.path.join(out, "trace_%s_%d.log" % (op, on)), "w").write(log)
            errs = [l for l in log.splitlines() if "SCRIPT ERROR" in l or "Parse Error" in l]
            if errs:
                print("脚本错误", op, on, errs[:3], flush=True)
            tr.append(traces(log))
        diff = sum(1 for a, b in zip(tr[0], tr[1]) if a != b) + abs(len(tr[0]) - len(tr[1]))
        same = diff == 0 and len(tr[0]) > 0
        ok &= same
        print("TRACE %s 打击感包 关 vs 开：%d / %d 行，%s" % (op, len(tr[0]), len(tr[1]), "逐行一致" if same else "有差异 %d 行" % diff), flush=True)
    if not any(op == "skadi" for op, _ in OPS):
        return ok
    # 框架修复（docs/246 §11）：斯卡蒂 fx/px_plane 0 vs 1（打击感包开着）
    tr = []
    for px in (0, 1):
        log = godot(["--resolution", "1280x720", "--fixed-fps", "60", "--", "--balance", "--nodeath", "--trace=1", "--seed=%d" % seed, "--op=skadi",
                     "--elite2", "--sptest", "--maxt=%d" % maxt, "--bal=fx/melee_impact=1", "--bal=fx/px_plane=%d" % px, "--bal=growth/late_shape=1"])
        open(os.path.join(out, "trace_pxp_%d.log" % px), "w").write(log)
        errs = [l for l in log.splitlines() if "SCRIPT ERROR" in l or "Parse Error" in l]
        if errs:
            print("脚本错误", px, errs[:3], flush=True)
        tr.append(traces(log))
    diff = sum(1 for a, b in zip(tr[0], tr[1]) if a != b) + abs(len(tr[0]) - len(tr[1]))
    same = diff == 0 and len(tr[0]) > 0
    ok &= same
    print("TRACE 斯卡蒂 转平面 0 vs 1（打击感包开、late_shape 开）：%d / %d 行，%s" % (len(tr[0]), len(tr[1]), "逐行一致" if same else "有差异 %d 行" % diff), flush=True)
    return ok


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["rec", "trace", "all"])
    ap.add_argument("--out", default=os.environ.get("MEDIA", os.path.join(ROOT, "build", "melee_impact")))
    ap.add_argument("--from", dest="t0", type=int, default=90)
    ap.add_argument("--secs", type=int, default=12)
    ap.add_argument("--seed", type=int, default=7)
    ap.add_argument("--maxt", type=int, default=300)
    ap.add_argument("--ops", default="", help="逗号分隔的干员（缺省斯卡蒂、星熊）；如 texas")
    ap.add_argument("--name", default="melee_impact_onoff", help="录像文件名")
    ap.add_argument("--playclock_trace", action="store_true")
    ap.add_argument("--knob", default="fx/melee_impact")
    ap.add_argument("--klabel", default="打击感包")
    ap.add_argument("--extra", default="")
    a = ap.parse_args()
    global OPS, NAME, PLAYCLOCK_TRACE, KNOB, EXTRA, KLABEL
    if a.ops:
        OPS = [(x, ["--bal=fx/px_plane=1"]) for x in a.ops.split(",") if x]
    NAME = a.name
    PLAYCLOCK_TRACE = a.playclock_trace
    KNOB = a.knob
    KLABEL = a.klabel
    EXTRA = a.extra.split()
    a.out = os.path.abspath(a.out)   # Godot 带 --path game 启动：相对路径会落到 game/ 下存不进去
    os.makedirs(a.out, exist_ok=True)
    ok = True
    if a.cmd in ("trace", "all"):
        ok = trace(a.out, a.seed, a.maxt)
    if a.cmd in ("rec", "all"):
        rec(a.out, a.t0, a.secs, a.seed)
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
