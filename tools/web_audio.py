# -*- coding: utf-8 -*-
"""网页包专用的音频再压缩（10-26 用户批：网页包压音频，「听感无损」优先；docs/121 §4）。

只改 export_web.py 的打包副本（git archive 出来的 src/game/audio），仓库里的原文件和桌面包一律不动。
- 配乐（audio/music/*.ogg）：解码后按档位重新编码 Ogg Vorbis（保留立体声与采样率，帧数必须和原文件一模一样——
  乐句式曲目按帧接缝，循环曲的首尾衔接靠样本数不变；只在变小时替换）。
- 语音（audio/voice/*.ogg）：从 masters/ 的 WAV 母带重新编码（不在已有损的 OGG 上再压），采样率与档位按档位表。
- 音效（audio/sfx/*.wav）：不动（导入时已是 QOA，只占约 2.4 MiB，换格式要改播放代码）。
档位（compression_level：0 最好、1 最小；libsndfile 把它映射成 Vorbis 质量 1 - level）：
  A 近无损：配乐全 0.85（约 64 kbps）；语音 24 kHz / 0.85
  B 平衡：配乐 0.85，但战斗叠层 pulse / drive / 危险层用 1.0（它们叠在底层之上，量化噪声被底层盖住）；语音同 A
  C 激进：配乐全 1.0（约 50 kbps）；语音 22.05 kHz / 0.9
样本播放是解码后放进内存的，降码率不改变解码后的大小（只减下载量 / 包体）。
用法：export_web.py --audio-tier B（缺省）；单独试：python tools/web_audio.py <game 目录副本> <A|B|C> （只改传进去的目录）
"""
import io, json, os, sys
from math import gcd

import numpy as np
import soundfile as sf

TIERS = {
    "A": {"music": {"default": 0.85}, "voice": (24000, 0.85)},
    "B": {"music": {"default": 0.85, "battle_pulse": 1.0, "battle_drive": 1.0, "danger": 1.0}, "voice": (24000, 0.85)},
    "C": {"music": {"default": 1.0}, "voice": (22050, 0.9)},
}


def music_group(name):
    if name.startswith("suno_"):   # Suno 分层配乐（docs/163）：suno_battle1_pulse 等按去掉前缀的名字分组
        name = name[5:]
    if name.startswith("battle") and name.endswith("_base"):
        return "battle_base"
    if name.startswith("battle") and name.endswith("_pulse"):
        return "battle_pulse"
    if name.startswith("battle") and name.endswith("_drive"):
        return "battle_drive"
    if name.endswith("_danger"):
        return "danger"
    return "other"


def encode(x, sr, level):
    b = io.BytesIO()
    ch = 1 if x.ndim == 1 else x.shape[1]
    with sf.SoundFile(b, "w", sr, ch, format="OGG", subtype="VORBIS", compression_level=level) as f:
        for i in range(0, len(x), 8192):   # libsndfile 一次写整段 Vorbis 会崩，分块写
            f.write(x[i:i + 8192])
    return b.getvalue()


def shrink(gamedir, tier):
    """改 gamedir/audio 下的配乐与语音；返回 {"music": [前, 后], "voice": [前, 后]}（字节）"""
    t = TIERS[tier]
    stat = {"music": [0, 0], "voice": [0, 0]}
    mdir = os.path.join(gamedir, "audio", "music")
    for f in sorted(os.listdir(mdir)):
        if not f.endswith(".ogg"):
            continue
        p = os.path.join(mdir, f)
        old = os.path.getsize(p)
        x, sr = sf.read(p, dtype="float32")
        lv = t["music"].get(music_group(f[:-4]), t["music"]["default"])
        new = encode(x, sr, lv)
        assert sf.info(io.BytesIO(new)).frames == len(x), "%s：重新编码后帧数变了" % f
        stat["music"][0] += old
        if len(new) < old:
            with open(p, "wb") as fh:
                fh.write(new)
            stat["music"][1] += len(new)
        else:
            stat["music"][1] += old
    vdir = os.path.join(gamedir, "audio", "voice")
    mast = os.path.join(vdir, "masters")
    sr_out, lv = t["voice"]
    if os.path.isdir(mast):
        from scipy.signal import resample_poly
        for f in sorted(os.listdir(vdir)):
            if not f.endswith(".ogg"):
                continue
            p = os.path.join(vdir, f)
            m = os.path.join(mast, f[:-4] + ".wav")
            if not os.path.exists(m):
                continue
            old = os.path.getsize(p)
            x, sr = sf.read(m, dtype="float32")
            g = gcd(sr_out, sr)
            y = resample_poly(x, sr_out // g, sr // g).astype(np.float32) if sr != sr_out else x
            new = encode(y, sr_out, lv)
            stat["voice"][0] += old
            if len(new) < old:
                with open(p, "wb") as fh:
                    fh.write(new)
                stat["voice"][1] += len(new)
            else:
                stat["voice"][1] += old
    return stat


def drop_unused_music(gamedir):
    """Suno 整首分层配乐接进来之后（docs/163），旧的程序合成乐句（battle*_A–E_*、危险层、boss_A–D_full、final_A–D_p1/p2）、final_suno、archive_v2
    在 suno_layers 开着时不会被载入（sfx.gd 按 suno_layers.json 判断），网页包里不带。suno_layers.json 或任一层文件缺失时什么都不删。返回删掉的字节数。
    代价：网页包里没法再用 balance.json music/suno_layers = 0 退回旧曲（桌面包 / 仓库里旧文件都还在）"""
    import re
    mdir = os.path.join(gamedir, "audio", "music")
    mp = os.path.join(mdir, "suno_layers.json")
    if not os.path.exists(mp):
        return 0
    meta = json.load(open(mp, encoding="utf-8"))
    for t, m in meta.items():
        for f in m["files"]:
            if not os.path.exists(os.path.join(mdir, f + ".ogg")):
                return 0
    if not os.path.exists(os.path.join(mdir, "suno_archive_full.ogg")):
        return 0
    pat = re.compile(r"^(battle[123]_([A-E]_(base|pulse|drive)|danger)|boss_[A-D]_full|final_[A-D]_p[12]|final_suno|archive_v2)\.ogg$")
    freed = 0
    for f in sorted(os.listdir(mdir)):
        if pat.match(f):
            freed += os.path.getsize(os.path.join(mdir, f))
            for g in (f, f + ".import"):
                gp = os.path.join(mdir, g)
                if os.path.exists(gp):
                    os.remove(gp)
    return freed


def report(stat):
    mb = 1048576.0
    return "音频再压缩：配乐 %.2f → %.2f MiB，语音 %.2f → %.2f MiB，合计省 %.2f MiB" % (
        stat["music"][0] / mb, stat["music"][1] / mb, stat["voice"][0] / mb, stat["voice"][1] / mb,
        (stat["music"][0] - stat["music"][1] + stat["voice"][0] - stat["voice"][1]) / mb)


if __name__ == "__main__":
    print(report(shrink(sys.argv[1], sys.argv[2])))
