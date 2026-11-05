#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""离线混音：把 tools/sfx_event_log.py 记下的同一局音效事件表，按「改前 / 改后」两套规则混成音频（docs/255 §7，流明攻击音效对照）。
本机不开 Godot。只复刻 sfx.gd 里和这次改动有关的规则，其余照事件表原样：
  - 流明 op_lumen_atk / op_lumen_hit 从 SFXOP（op() 入口、节流前）重新生成：改前 = 旧文件、无命中间隔、命中音高随机 ±5%；改后 = 新文件、命中最短间隔 0.09 秒、±4%；
    音量 = OP_VOL[类别] + 调用处偏移（OP_DB 两版都没有流明条目）；
  - 其他音效照 SFXLOG（play() 请求）；
  - play() 同名最短间隔 = max(MERGE_T 0.05, LIMIT / OP_LIMIT)，按游戏时间算（游戏里按墙钟，实时局两者一样）；
  - 不模拟同时发声上限、总线效果和音乐；两版用同一个总增益（按改前那版的峰值定），所以改后变轻在文件里直接听得出。
用法：python tools/sfx_offline_mix.py --log <sfx_events_11.log> --t0 480 --secs 10 --out <目录>
"""
import argparse, hashlib, os, re, subprocess

import numpy as np
import soundfile as sf

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAIN = os.path.dirname(os.path.dirname(os.path.dirname(ROOT))) if ".claude" in ROOT else ROOT
SFX = os.path.join(ROOT, "game", "audio", "sfx")
OLD = os.path.join(MAIN, "build", "sfx_lumen_1105")
SR = 44100
OP_VOL = {"atk": -11.0, "hit": -10.0, "s1": -4.0, "s2": -4.0, "s3": -2.0, "big": -6.0, "heal": -9.0, "quake": -13.0}
OP_LIMIT = {"atk": 0.06, "hit": 0.06, "quake": 0.08, "big": 0.1, "heal": 0.3}
MERGE_T = 0.05


def read_limit():
    s = open(os.path.join(ROOT, "game", "scripts", "sfx.gd"), encoding="utf-8").read()
    m = re.search(r"^const LIMIT := (\{.*?\})$", s, re.M)
    return {k: float(v) for k, v in re.findall(r'"([^"]+)": ([0-9.]+)', m.group(1))} if m else {}


LIMIT = read_limit()
_cache = {}


NEWDIR = ""


def wav(name, old):
    key = (name, old)
    if key not in _cache:
        p = os.path.join(OLD, name + "_old.wav") if old else (os.path.join(NEWDIR, name + ".wav") if NEWDIR and name.startswith("op_lumen_") else None)
        if not p or not os.path.exists(p):
            p = None
            for ext in (".wav", ".ogg"):
                q = os.path.join(SFX, name + ext)
                if os.path.exists(q):
                    p = q
                    break
        if p is None:
            _cache[key] = None
        else:
            x, sr = sf.read(p, always_2d=True)
            x = x.mean(axis=1)
            if sr != SR:
                x = np.interp(np.arange(0, len(x), sr / SR), np.arange(len(x)), x)
            _cache[key] = x.astype(np.float32)
    return _cache[key]


def rnd(*k):
    h = hashlib.md5(("|".join(map(str, k))).encode()).digest()
    return int.from_bytes(h[:4], "little") / 2 ** 32


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--log", required=True)
    ap.add_argument("--t0", type=float, default=480.0)
    ap.add_argument("--secs", type=float, default=10.0)
    ap.add_argument("--out", required=True)
    ap.add_argument("--name", default="lumen_atk_sfx")
    ap.add_argument("--newdir", default="", help="改后那版流明攻击音从这个目录取 op_lumen_atk.wav / op_lumen_hit.wav（候选对比用；缺省用 game/audio/sfx）")
    ap.add_argument("--unit_db", type=float, default=0.0, help="改后那版：发光单元 / 非本体的命中（调用处偏移 ≤ −3 dB 的 op_lumen_hit）再加这么多 dB；≤ −60 = 不出声")
    ap.add_argument("--only", default="", help="只混这个前缀的音（如 op_lumen_ 只听流明自己的声音）")
    a = ap.parse_args()
    global NEWDIR
    NEWDIR = a.newdir
    fr2t, plays, ops = [], [], []
    for l in open(a.log, encoding="utf-8"):
        p = l.split()
        if l.startswith("FXRLOG") and len(p) >= 5:
            fr2t.append((int(p[3]), float(p[4])))
        elif l.startswith("SFXLOG") and len(p) >= 6:
            plays.append((float(p[1]), p[2], float(p[3]), float(p[4]), float(p[5])))
        elif l.startswith("SFXOP") and len(p) >= 6:
            ops.append((float(p[1]), p[2], float(p[3]), float(p[4]), float(p[5])))
    tm = lambda f: f   # 事件行第 2 列就是游戏时间（sfx.gd _log_t）
    LM = ("op_lumen_atk", "op_lumen_hit")
    outs = {}
    for ver in ("before", "after"):
        ev = [(tm(f), n, v, pi, pv, False) for f, n, v, pi, pv in plays if n not in LM and n.startswith(a.only)]
        gap_last = {}
        for f, sn, v, pi, pv in ops:
            if sn not in LM:
                continue
            t = tm(f)
            kind = sn.split("_")[-1]
            if ver == "after" and sn == "op_lumen_hit" and v <= -3.0 and a.unit_db != 0.0:
                if a.unit_db <= -60.0:
                    continue
                v += a.unit_db
            if ver == "after" and sn == "op_lumen_hit":
                if t - gap_last.get(sn, -99.0) < 0.09:
                    continue
                gap_last[sn] = t
            pvar = max(pv, {"op_lumen_atk": 0.07, "op_lumen_hit": 0.0 if ver == "before" else 0.04}[sn])
            ev.append((t, sn, OP_VOL.get(kind, -8.0) + v, pi, pvar, ver == "before"))
        ev.sort(key=lambda e: e[0])
        last = {}
        L = int((a.secs + 1.0) * SR)
        mix = np.zeros(L, np.float32)
        n_lm = 0
        for i, (t, n, v, pi, pv, old) in enumerate(ev):
            lim = max(MERGE_T, LIMIT.get(n, OP_LIMIT.get(n.split("_")[-1], 0.0) if n.startswith("op_") else 0.0))
            if t - last.get(n, -99.0) < lim:
                continue
            last[n] = t
            if not (a.t0 <= t < a.t0 + a.secs):
                continue
            x = wav(n, old)
            if x is None:
                continue
            pitch = pi * (1.0 + (rnd(n, round(t, 4)) * 2 - 1) * pv)
            idx = np.arange(0, len(x) - 1, pitch)
            y = np.interp(idx, np.arange(len(x)), x) * 10 ** (v / 20.0)
            s0 = int((t - a.t0) * SR)
            e0 = min(L, s0 + len(y))
            mix[s0:e0] += y[:e0 - s0]
            if n in LM:
                n_lm += 1
        outs[ver] = (mix[:int(a.secs * SR)], n_lm)
    g = 0.89 / max(1e-6, np.abs(outs["before"][0]).max())
    import imageio_ffmpeg
    ff = imageio_ffmpeg.get_ffmpeg_exe()
    os.makedirs(a.out, exist_ok=True)
    for ver, (m, n_lm) in outs.items():
        y = np.clip(m * g, -1, 1)
        w = os.path.join(a.out, "%s_%s.wav" % (a.name, ver))
        sf.write(w, y, SR, subtype="PCM_16")
        mp3 = w[:-4] + ".mp3"
        subprocess.run([ff, "-y", "-loglevel", "error", "-i", w, "-c:a", "libmp3lame", "-b:a", "192k", mp3], check=True)
        os.remove(w)
        X = np.abs(np.fft.rfft(y))
        f = np.fft.rfftfreq(len(y), 1 / SR)
        print("%s：流明攻击音 %d 声，整段峰值 %.1f dB、RMS %.1f dB、6 kHz 以上能量 %.0f%% → %s" % (ver, n_lm, 20 * np.log10(np.abs(y).max() + 1e-9), 20 * np.log10(np.sqrt((y ** 2).mean()) + 1e-9), X[f > 6000].sum() / X.sum() * 100, mp3))


if __name__ == "__main__":
    main()
