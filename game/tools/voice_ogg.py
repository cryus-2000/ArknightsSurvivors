"""干员语音：WAV 母带 → 游戏里用的 OGG Vorbis（单声道 44.1 kHz）。

母带在 audio/voice/masters/（目录里有 .gdignore，Godot 不导入也不导出）；游戏读 audio/voice/<干员>_<事件>.ogg（sfx.gd）。
每条的编码档位记在 voice_manifest.json 的 ogg_quality（soundfile 的 compression_level，0 最好、1 最小）。
2026-09-26 从 QOA（WAV 导入时的默认压缩）改成 OGG 时逐条选的档位：在 0.7 / 0.6 / 0.5 / 0.4 / 0.3 里取最小的一档，
要求它和原始 WAV 的差异（简化 PEAQ 式噪声掩蔽比，长帧 2048 和短帧 512 两种分析）不比当时游戏里的 QOA 版本大
（容差 0.5 dB / 3 个百分点）。清单里没有档位的新语音用 DEFAULT_Q：当时所有条目在这一档都不比 QOA 差。

新交付的语音照 README 放进 audio/voice/（<干员>_<事件>.wav，并在清单里登记）后运行本脚本：
WAV 会被挪进 masters/，清单里的 file 改成 .ogg，并补上 master / ogg_quality。

用法：cd game/tools && python voice_ogg.py      # 只转换还没有 OGG 的条目（新交付）
      python voice_ogg.py 名字 ...               # 重新转换指定条目（比如改了清单里的 ogg_quality）
      python voice_ogg.py --all                  # 全部重新转换
依赖 numpy / soundfile。libvorbis 的输出是确定的：同一母带、同一档位，解码结果逐采样相同；但 Ogg 流序列号每次随机，
所以重新转换过的文件在 git 里总会显示为改动——没必要就别用 --all。
"""
import hashlib
import json
import os
import shutil
import sys

import numpy as np
import soundfile as sf

HERE = os.path.dirname(os.path.abspath(__file__))
VOICE = os.path.normpath(os.path.join(HERE, "..", "audio", "voice"))
MASTERS = os.path.join(VOICE, "masters")
MANIFEST = os.path.join(VOICE, "voice_manifest.json")
DEFAULT_Q = 0.3
SR = 44100


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        h.update(f.read())
    return h.hexdigest()


def encode(src, dst, q):
    x, sr = sf.read(src, dtype="float32")
    assert sr == SR and x.ndim == 1, f"{src}: 需要单声道 {SR} Hz，实际 {sr} Hz / {x.ndim} 维"
    with sf.SoundFile(dst, "w", SR, 1, format="OGG", subtype="VORBIS", compression_level=q) as f:
        for i in range(0, len(x), 8192):   # libsndfile 一次写整段 Vorbis 会崩，分块写
            f.write(x[i:i + 8192])
    return len(x) / SR


def main(args):
    redo_all = "--all" in args
    only = {a for a in args if not a.startswith("--")}
    with open(MANIFEST, encoding="utf-8") as f:
        man = json.load(f)
    os.makedirs(MASTERS, exist_ok=True)
    total_in = total_out = done = 0
    for clip in man["clips"]:
        stem = os.path.splitext(clip["file"])[0]
        master = os.path.join(MASTERS, stem + ".wav")
        delivered = os.path.join(VOICE, stem + ".wav")
        if os.path.exists(delivered):          # 新交付：挪进母带目录
            shutil.move(delivered, master)
            imp = delivered + ".import"
            if os.path.exists(imp):
                os.remove(imp)
        dst = os.path.join(VOICE, stem + ".ogg")
        if not (redo_all or stem in only or not os.path.exists(dst)):
            continue
        assert os.path.exists(master), f"缺母带 {master}"
        assert sha256(master) == clip["sha256"], f"{stem}.wav 的 SHA-256 与清单不符"
        q = float(clip.get("ogg_quality", DEFAULT_Q))
        dur = encode(master, dst, q)
        done += 1
        clip["file"] = stem + ".ogg"
        clip["master"] = "masters/" + stem + ".wav"
        clip["ogg_quality"] = q
        total_in += os.path.getsize(master)
        total_out += os.path.getsize(dst)
        print(f"{stem:28s} {dur:5.2f} s  档位 {q:.1f}  {os.path.getsize(dst) * 8 / dur / 1000:4.0f} kbps")
    stray = [f for f in os.listdir(VOICE) if f.lower().endswith(".wav")]
    if stray:
        print("警告：audio/voice/ 里还有没登记到清单的 WAV（游戏只读 OGG，这些不会播）：", stray)
    with open(MANIFEST, "w", encoding="utf-8", newline="\n") as f:
        f.write(json.dumps(man, ensure_ascii=False, indent=2) + "\n")
    print(f"转换 {done} 条：母带 {total_in / 1048576:.2f} MB → OGG {total_out / 1048576:.2f} MB")


if __name__ == "__main__":
    main(sys.argv[1:])
