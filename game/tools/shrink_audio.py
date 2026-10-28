"""网页包压音频（10-21，B站 Toy 上限 50 MB、实测 43.1 MiB、音频占七成多）：BGM 与语音降一档，音效不动，不改播放代码。

- BGM（audio/music/*.ogg）：没有母带（gen_music*.py 直接写 OGG），解码后按 BGM_LEVEL 重新编码；只在变小时替换，
  帧数必须与原文件相同（乐句式曲目按帧接缝）。生成脚本的编码档位同步改成 BGM_LEVEL，以后重跑也是这一档。
- 语音（audio/voice/*.ogg）：从 art/source/voice/ 的 WAV 母带重编码（不叠加有损），走 voice_ogg.encode：24 kHz 单声道、清单 ogg_quality 统一 0.7（约 57 kbps）。
- 对比样本：BGM / 语音各取几条，压前压后各一段写到 <主仓库>/build/audio_shrink/。

用法：python game/tools/shrink_audio.py --bgm --voice            先写 <主仓库>/build/audio_shrink/stage/ 并打印省多少
      python game/tools/shrink_audio.py --bgm --voice --apply    写进 game/audio/（覆盖的都是 git 跟踪文件）
10-21 已各做过一次：BGM 别再跑 --bgm（会在 0.70 上再压一遍）；语音以后改档位直接用 voice_ogg.py --all（从母带编码，可重复）。
需要 numpy + soundfile。
"""
import io, json, os, subprocess, sys
import numpy as np
import soundfile as sf

BGM_LEVEL = 0.70     # soundfile compression_level（0 最好、1 最小）；原 gen_music 0.45、战斗曲 0.62 / 0.66

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.normpath(os.path.join(HERE, ".."))
MUSIC = os.path.join(GAME, "audio", "music")
VOICE = os.path.join(GAME, "audio", "voice")
common = subprocess.run(["git", "rev-parse", "--git-common-dir"], cwd=HERE, capture_output=True, text=True).stdout.strip()
ROOT = os.path.dirname(os.path.abspath(os.path.join(HERE, common)))
OUT = os.path.join(ROOT, "build", "audio_shrink")
APPLY = "--apply" in sys.argv
STAGE = os.path.join(OUT, "stage")


def enc(x, sr, level):
    b = io.BytesIO()
    ch = 1 if x.ndim == 1 else x.shape[1]
    with sf.SoundFile(b, "w", sr, ch, format="OGG", subtype="VORBIS", compression_level=level) as f:
        for i in range(0, len(x), 8192):
            f.write(x[i:i + 8192])
    return b.getvalue()


def frames(data):
    return sf.info(io.BytesIO(data)).frames


def put(rel, data):
    path = os.path.join(GAME if APPLY else STAGE, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(data)


tot = {"BGM": [0, 0], "语音": [0, 0]}

# ---------------------------------------------------------------- BGM
if "--bgm" in sys.argv:
    for f in sorted(os.listdir(MUSIC)):
        if not f.endswith(".ogg"):
            continue
        src = os.path.join(MUSIC, f)
        old = os.path.getsize(src)
        x, sr = sf.read(src, dtype="float32")
        new = enc(x, sr, BGM_LEVEL)
        assert frames(new) == len(x), f"{f}: 帧数变了"
        use = new if len(new) < old else open(src, "rb").read()
        tot["BGM"][0] += old
        tot["BGM"][1] += len(use)
        if use is new:
            put(os.path.join("audio", "music", f), new)

# ---------------------------------------------------------------- 语音
if "--voice" in sys.argv:
    # 编码统一走 voice_ogg.encode（24 kHz、清单里的 ogg_quality 0.7），保证以后 voice_ogg.py 重跑结果一致
    sys.path.insert(0, HERE)
    import voice_ogg
    man = json.load(open(os.path.join(VOICE, "voice_manifest.json"), encoding="utf-8"))
    for clip in man["clips"]:
        dst = os.path.join(VOICE, clip["file"])
        old = os.path.getsize(dst) if os.path.exists(dst) else 0
        out = os.path.join(GAME if APPLY else STAGE, "audio", "voice", clip["file"])
        os.makedirs(os.path.dirname(out), exist_ok=True)
        tmp = out + ".tmp.ogg"
        voice_ogg.encode(os.path.join(GAME, "..", clip["master"]), tmp, float(clip["ogg_quality"]))   # master 相对仓库根（art/source/voice/…）
        tot["语音"][0] += old
        tot["语音"][1] += os.path.getsize(tmp)
        os.replace(tmp, out)

for k, (a, b) in tot.items():
    print("%s  %.2f → %.2f MiB（省 %.2f MiB，%.0f%%）" % (k, a / 2**20, b / 2**20, (a - b) / 2**20, 100 * (a - b) / max(1, a)))
a = sum(v[0] for v in tot.values()); b = sum(v[1] for v in tot.values())
print("合计  %.2f → %.2f MiB（省 %.2f MiB）" % (a / 2**20, b / 2**20, (a - b) / 2**20))
print("->", GAME if APPLY else STAGE)
