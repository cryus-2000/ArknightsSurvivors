# -*- coding: utf-8 -*-
"""录屏配声音（离线混音）：测试局照旧静音，录屏时开 --sfxtrace，autotest 结束时打印 SFXTRACE（音效 / 语音事件）和 MUSTRACE（逐帧配乐采样），
这里按记录混成单声道 44.1k WAV，再由各录像脚本合进 mp4（AAC）。原在 tools/ult_rec.py，px_showcase_rec / px_unleashed_rec 共用。
用法：tr, mus = parse(godot 输出)；y, has_mus = mix_audio(tr, mus or {}, 帧数)；write_wav(路径, y)
"""
import json, os, subprocess, wave
import numpy as np
import imageio_ffmpeg

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
FF = imageio_ffmpeg.get_ffmpeg_exe()


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


def parse(out):
    """godot 标准输出 → (SFXTRACE dict 或 None, MUSTRACE dict 或 None)"""
    tr = mus = None
    for ln in out.splitlines():
        if ln.startswith("SFXTRACE "):
            tr = json.loads(ln[9:])
        elif ln.startswith("MUSTRACE "):
            mus = json.loads(ln[9:])
    return tr, mus


def summary(tr, has_mus):
    return "音效 %d 次、语音 %d 句、配乐%s" % (sum(1 for e in tr["trace"] if not e[1].startswith(("voice:", "vduck:"))),
                                     sum(1 for e in tr["trace"] if e[1].startswith("voice:")), "有" if has_mus else "无")
