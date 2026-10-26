# -*- coding: utf-8 -*-
"""Suno 分轨 → 整首分层循环配乐（docs/164，10-27 用户把 Suno 新配乐接进游戏）。

输入：art/incoming/music_suno/*.zip（Suno 分轨，每条 3–3.5 分钟、48 kHz、同步对齐；原始 WAV / zip 不进 git）。
流程（和 tools/suno_track.py 同口径）：分轨按下表预混成层 → 重采样 32 kHz → 去尾部静音 → 尾首等功率交叉淡化成无缝循环
（交叉淡化长度取整数个小节，这样回环点前后的拍位不变）→ 响度按整曲（全部层开）对齐 → 每层写一个 ogg（所有层同长度，同一个增益，保持混音比例）。
另写 game/audio/music/suno_layers.json：每首的 bpm、首拍偏移（秒）、层清单、时长（给 sfx.gd 按小节线切层用）。

分轨取舍（见 build/suno_stats.json：每条分轨的整曲 RMS / 有声占比）：
  - Woodwinds：全部 ≤ -52 dBFS、有声占比 ≤ 9%（battle1 -62 dB / 2%）= 底噪，丢掉。
  - Lead / Backing Vocals：battle1 / battle3 / boss 里 ≤ -44 dBFS、有声占比 ≤ 15% = 零星哼唱杂音，丢掉；battle2 的 Lead -34 dB / Backing -31 dB（有声 29% / 18%）是真的哼唱和声，并进 drive 层；
    最终 Boss 的 Lead -28 dB（有声 61%）/ Backing -31 dB 是歌的主唱，放进 p1（一阶段就有歌，p2 再叠鼓 / 吉他 / 铜管 / 打击乐）。
层：battle1–3 = base（Keyboard + Strings + Synth + Bass + Other，平静）/ pulse（Drums + Percussion，交战）/ drive（Guitar + Brass + Lead / Backing 哼唱，激战）；
    中期 Boss = full（全部）；最终 Boss = p1（Keyboard + Strings + Synth + Bass + Other + 人声）/ p2（Drums + Percussion + Guitar + Brass）；图鉴 = 全部相加成整曲。

用法：python tools/suno_layers.py [曲名 …]   （缺省全部：battle1 battle2 battle3 boss final archive）
需要 numpy / scipy / soundfile，响度函数借 game/tools/gen_music_battle.py 的 lufs。
"""
import glob, io, json, os, subprocess, sys, zipfile
import numpy as np
import soundfile as sf
from scipy.signal import resample_poly

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(ROOT, "game", "tools"))
import gen_music_battle as gb   # noqa: E402

common = subprocess.run(["git", "rev-parse", "--git-common-dir"], cwd=HERE, capture_output=True, text=True).stdout.strip()
MAIN = os.path.dirname(os.path.abspath(os.path.join(HERE, common)))
ZIPS = os.path.join(MAIN, "art", "incoming", "music_suno")
CACHE = os.path.join(MAIN, "build", "suno_src")
OUT = os.path.join(ROOT, "game", "audio", "music")
SR = 32000
LEVEL = 0.75        # ogg 编码档位（soundfile compression_level，0.75 ≈ 70 kbps 立体声；每层单独编）
PEAK_MAX = 1.6     # 全部层开的峰值上限（线性）：Music 总线挂了限幅器（default_bus_layout.tres），瞬态峰值可以超过 1，响度才不被峰值拖低
XF_SEC = 4.0        # 回环交叉淡化约 4 秒（取整数个小节）

ZIPNAME = {"battle1": "战斗第一段", "battle2": "战斗第二段", "battle3": "战斗第三段", "boss": "中期boss", "final": "最终bossfinal", "archive": "图鉴archive"}
# 分轨名（去掉编号）→ 层；None = 丢掉
BATTLE = {"Keyboard": "base", "Strings": "base", "Synth": "base", "Bass": "base", "Other": "base", "Drums": "pulse", "Percussion": "pulse",
          "Guitar": "drive", "Brass": "drive", "Woodwinds": None, "Lead Vocals": None, "Backing Vocals": None}
SPEC = {
    "battle1": {"layers": ["base", "pulse", "drive"], "map": BATTLE, "lufs": -15.0, "bpm_guess": 140.0},
    "battle2": {"layers": ["base", "pulse", "drive"], "map": dict(BATTLE, **{"Lead Vocals": "drive", "Backing Vocals": "drive"}), "lufs": -15.0, "bpm_guess": 146.0},
    "battle3": {"layers": ["base", "pulse", "drive"], "map": BATTLE, "lufs": -15.0, "bpm_guess": 152.0},
    "boss": {"layers": ["full"], "map": {k: ("full" if k != "Woodwinds" and k not in ("Lead Vocals", "Backing Vocals") else None) for k in BATTLE}, "lufs": -15.0, "bpm_guess": 150.0},
    "final": {"layers": ["p1", "p2"], "map": {"Keyboard": "p1", "Strings": "p1", "Synth": "p1", "Bass": "p1", "Other": "p1", "Lead Vocals": "p1", "Backing Vocals": "p1",
                                             "Drums": "p2", "Percussion": "p2", "Guitar": "p2", "Brass": "p2", "Woodwinds": None}, "lufs": -15.0, "lufs_full": -13.5, "bpm_guess": 152.0},
    "archive": {"layers": ["full"], "map": {k: "full" for k in ("Drums", "Bass", "Keyboard", "Percussion", "Synth", "Other")}, "lufs": -17.8, "bpm_guess": 100.0},
}


def stem_name(path):
    n = os.path.splitext(os.path.basename(path))[0]
    return n.split(" ", 1)[1] if n.split(" ", 1)[0].isdigit() else n


def extract(track):
    d = os.path.join(CACHE, track)
    if not glob.glob(os.path.join(d, "*.wav")):
        os.makedirs(d, exist_ok=True)
        zf = zipfile.ZipFile(os.path.join(ZIPS, ZIPNAME[track] + ".zip"))
        for i in zf.infolist():
            if not i.is_dir() and i.filename.lower().endswith(".wav"):
                with zf.open(i) as s, open(os.path.join(d, os.path.basename(i.filename)), "wb") as o:
                    o.write(s.read())
    return sorted(glob.glob(os.path.join(d, "*.wav")))


def to32(x, sr):
    if sr == SR:
        return x
    from math import gcd
    g = gcd(SR, sr)
    return resample_poly(x, SR // g, sr // g, axis=0).astype(np.float32)


def beat_grid(drums, guess):
    """鼓轨 → 精确 bpm 与首拍偏移（秒）：在 guess ±4% 内扫拍频，取起音包络在该频率上的傅里叶幅值最大者"""
    m = drums.mean(1)
    hop = 256
    n = len(m) // hop
    e = np.sqrt((m[:n * hop].reshape(n, hop) ** 2).mean(1))
    d = np.maximum(np.diff(e), 0)
    t = (np.arange(len(d)) + 1) * hop / SR
    best = (0.0, guess, 0.0)
    for bpm in np.arange(guess * 0.96, guess * 1.04, 0.005):
        f = bpm / 60.0
        z = (d * np.exp(-2j * np.pi * f * t)).sum()
        if abs(z) > best[0]:
            best = (abs(z), bpm, float(np.angle(z)))
    bpm = best[1]
    beat = 60.0 / bpm
    off = (-best[2] / (2 * np.pi)) * beat % beat   # 第一拍落在 off 秒（相位 → 时间）
    # 鼓的起音比包络峰值略早，不再细调；偏移只用来在小节线上切层，±半拍以内都听不出
    return bpm, off


def build(track):
    spec = SPEC[track]
    files = extract(track)
    acc = {l: None for l in spec["layers"]}
    drums = None
    for f in files:
        nm = stem_name(f)
        lay = spec["map"].get(nm)
        x, sr = sf.read(f, dtype="float32", always_2d=True)
        x = to32(x, sr)
        if nm == "Drums":
            drums = x.copy()
        if lay is None:
            continue
        acc[lay] = x if acc[lay] is None else _add(acc[lay], x)
        del x
    n = max(len(v) for v in acc.values() if v is not None)
    for l in acc:
        if acc[l] is None:
            raise SystemExit("%s：层 %s 没有任何分轨" % (track, l))
        if len(acc[l]) < n:
            acc[l] = np.pad(acc[l], ((0, n - len(acc[l])), (0, 0)))
    # 去尾部静音（按全部层之和）
    tot = sum(acc.values())
    end = int(np.nonzero(np.abs(tot).max(1) > 10 ** (-50 / 20))[0][-1]) + 1
    bpm, off = beat_grid(drums if drums is not None else tot, spec["bpm_guess"])
    bar = 4 * 60.0 / bpm
    L = int(round(round(XF_SEC / bar) * bar * SR))
    t = np.linspace(0, np.pi / 2, L)[:, None]
    out = {}
    for l, x in acc.items():
        x = x[:end]
        y = x[L:].copy()
        y[-L:] = x[-L:] * np.cos(t) + x[:L] * np.sin(t)
        out[l] = y
    gb.SR = SR
    full = sum(out.values())
    if track == "final":
        g = 10 ** ((spec["lufs"] - gb.lufs(out["p1"])) / 20)           # 一阶段（p1 单放）= -15
        out["p1"] = out["p1"] * g
        p2 = out["p2"] * g
        # p2 层再乘一个系数，让全部层开 = -13.5
        lo, hi = 0.2, 4.0
        for _ in range(30):
            k = (lo + hi) / 2
            if gb.lufs(out["p1"] + p2 * k) < spec["lufs_full"]:
                lo = k
            else:
                hi = k
        out["p2"] = p2 * k
    else:
        g = 10 ** ((spec["lufs"] - gb.lufs(full)) / 20)
        for l in out:
            out[l] = out[l] * g
    peak = max(float(np.abs(v).max()) for v in out.values())
    full = sum(out.values())
    fpk = float(np.abs(full).max())
    print("  全部层开峰值（对齐响度后、保护前）%.3f" % fpk)
    if fpk > PEAK_MAX:   # 全部层开时的峰值保护：整体等比例压（保持层间比例）
        s = PEAK_MAX / fpk
        for l in out:
            out[l] = out[l] * s
    res = {"bpm": round(float(bpm), 3), "offset": round(float(off), 3), "len": round(len(out[spec["layers"][0]]) / SR, 3), "layers": spec["layers"], "files": [], "xf": round(L / SR, 3)}
    for l, y in out.items():
        name = "suno_%s_%s.ogg" % (track, l)
        with sf.SoundFile(os.path.join(OUT, name), "w", SR, 2, format="OGG", subtype="VORBIS", compression_level=LEVEL) as f:
            for i in range(0, len(y), 65536):
                f.write(y[i:i + 65536].astype(np.float32))
        z, _ = sf.read(os.path.join(OUT, name), always_2d=True)
        res["files"].append(name[:-4])
        print("  %-24s dur %.1f lufs %.2f peak %.3f seam %.4f size %.2f MiB" % (name, len(z) / SR, gb.lufs(z), float(np.abs(z).max()), float(np.abs(z[0] - z[-1]).max()), os.path.getsize(os.path.join(OUT, name)) / 1048576))
    zs = [sf.read(os.path.join(OUT, f + ".ogg"), always_2d=True)[0] for f in res["files"]]
    print("  全部层开 lufs %.2f；%s  bpm %.3f 首拍 %.3f s 交叉淡化 %.2f s（%d 小节）" % (gb.lufs(sum(zs)), ("p1 单放 %.2f" % gb.lufs(zs[0])) if track == "final" else "", bpm, off, L / SR, round(L / SR / bar)))
    return res


def _add(a, b):
    n = max(len(a), len(b))
    if len(a) < n:
        a = np.pad(a, ((0, n - len(a)), (0, 0)))
    if len(b) < n:
        b = np.pad(b, ((0, n - len(b)), (0, 0)))
    return a + b


if __name__ == "__main__":
    tracks = sys.argv[1:] or list(SPEC)
    jp = os.path.join(OUT, "suno_layers.json")
    meta = json.load(open(jp, encoding="utf-8")) if os.path.exists(jp) else {}
    for t in tracks:
        print(t)
        meta[t] = build(t)
        json.dump(meta, open(jp, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
