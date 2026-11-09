# -*- coding: utf-8 -*-
"""PV 配乐（11-08）：游戏内 battle2（Suno 分层，145.99 BPM，第 0 拍 0.111 秒，一小节 1.6438 秒）三层相加成整曲，按小节线拼成 60 秒。

  python tools/promo/music.py [输出.wav]      缺省 Claude outputs/pv_1108/work/music.wav

段落（原曲小节号，按 tools/promo 里的能量表挑）：
  片中 0.000  原曲 0      1 小节  只有底层铺底（黑暗中一盏灯）
  片中 1.644  原曲 108    1 小节  第二次 drop 的重拍 → 对水月终结技冲击帧
  片中 3.288  原曲 4–12   9 小节  平稳 → 第 6 小节鼓和律动层进来（6.58 秒，登场卡）
  片中 18.08  原曲 22–28  7 小节  律动段（升级 / 指挥 / 灯标）；指挥圆盘那 3 秒加低通（LP 段）
  片中 29.59  原曲 54–57  4 小节  大段（满屏怪潮 + 终结技 ① ②）
  片中 36.17  原曲 74–77  4 小节  drop 前的断点，74 小节一记重拍（终结技 ③），之后收（中期 Boss 登场）
  片中 42.75  原曲 78–81  4 小节  第一次 drop（Boss 弹幕、弹幕缝里穿行）
  片中 49.32  原曲 82–83  2 小节  82 小节重拍（击杀）→ 余音淡出（俯瞰 + 最终 Boss 剪影）
  片中 52.60  静默 2 拍（0.82 秒，全片唯一一次）
  片中 53.42  原曲 108–111 4 小节 标题砸出（同一记 drop2 重拍首尾呼应），末 1.8 秒淡出
"""
import json, os, subprocess, sys
import numpy as np
import soundfile as sf
from scipy.signal import butter, sosfilt

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
MAIN = os.path.dirname(os.path.dirname(os.path.dirname(ROOT))) if ".claude" in ROOT else ROOT
SR = 48000
LAY = json.load(open(os.path.join(ROOT, "game", "audio", "music", "suno_layers.json"), encoding="utf-8"))["battle2"]
BPM, OFF = LAY["bpm"], LAY["offset"]
BEAT = 60.0 / BPM
BAR = 4 * BEAT
# (原曲起始小节, 小节数) 或 ("rest", 拍数)
SEGS = [(0, 1), (108, 1), (4, 9), (22, 7), (54, 4), (74, 4), (78, 4), (82, 2), ("rest", 2), (108, 4)]
TAIL_FADE = 1.8
# 15 秒竖版：77 小节（drop 前一小节）→ 78–83 drop 6 小节 → 108 重拍标题 2.125 小节（共 15.0 秒）
SEGS_VERT = [(77, 1), (78, 6), (108, 2.125)]
FADE82 = (0.9, 2 * BAR)   # 82–83 小节：重拍后从 0.9 秒起淡到 0（余音）


def ffmpeg():
    import imageio_ffmpeg
    return imageio_ffmpeg.get_ffmpeg_exe()


def load(name):
    p = os.path.join(ROOT, "game", "audio", "music", name + ".ogg")
    raw = subprocess.run([ffmpeg(), "-v", "error", "-i", p, "-ac", "2", "-ar", str(SR), "-f", "f32le", "-"], capture_output=True).stdout
    return np.frombuffer(raw, np.float32).reshape(-1, 2).astype(np.float64)


def song():
    st = [load(f) for f in LAY["files"]]
    n = min(len(s) for s in st)
    return sum(s[:n] for s in st)


def marks():
    """各段在片中的起始秒：[(段, 片中秒)]"""
    t, out = 0.0, []
    for a, n in SEGS:
        out.append(((a, n), t))
        t += (n * BEAT) if a == "rest" else n * BAR
    return out, t


def build(out, lp=None, segs=None, tail_fade=TAIL_FADE):
    """lp = [(片中起, 片中止)]：这些时段过低通（指挥圆盘时间变慢），边缘 0.15 秒交叉淡化"""
    s = song()
    parts = []
    for a, n in (segs or SEGS):
        if a == "rest":
            parts.append(np.zeros((int(round(n * BEAT * SR)), 2)))
            continue
        s0 = int(round((OFF + a * BAR) * SR))
        L = int(round(n * BAR * SR))
        x = s[s0:s0 + L].copy()
        f = int(0.006 * SR)
        x[:f] *= np.linspace(0, 1, f)[:, None]
        x[-f:] *= np.linspace(1, 0, f)[:, None]
        if a == 82 and n == 2:
            env = np.ones(L)
            i0, i1 = int(FADE82[0] * SR), min(L, int(FADE82[1] * SR))
            env[i0:i1] = np.linspace(1, 0, i1 - i0) ** 2
            env[i1:] = 0
            x *= env[:, None]
        parts.append(x)
    m = np.concatenate(parts)
    for t0, t1 in (lp or []):
        sos = butter(4, 520, "low", fs=SR, output="sos")
        y = sosfilt(sos, m, axis=0) * 1.5
        w = np.zeros(len(m))
        a0, a1 = int(t0 * SR), int(t1 * SR)
        r = int(0.15 * SR)
        w[a0:a1] = 1
        w[max(0, a0 - r):a0] = np.linspace(0, 1, a0 - max(0, a0 - r))
        w[a1:a1 + r] = np.linspace(1, 0, len(w[a1:a1 + r]))
        m = m * (1 - w[:, None]) + y * w[:, None]
    tail = int(tail_fade * SR)
    m[-tail:] *= (np.linspace(1, 0, tail) ** 1.5)[:, None]
    m *= 0.89 / np.abs(m).max()
    os.makedirs(os.path.dirname(out), exist_ok=True)
    sf.write(out, m.astype(np.float32), SR)
    return m


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(MAIN, "Claude outputs", "pv_1108", "work", "music.wav")
    build(out)
    mk, tot = marks()
    print(out, "%.3f 秒" % tot)
    for (a, n), t in mk:
        print("  %6.3f  %s × %s" % (t, a, n))
