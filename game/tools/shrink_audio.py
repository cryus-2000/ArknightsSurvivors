"""网页包压音频（10-21，B站 Toy 上限 50 MB、实测 43.1 MiB、音频占七成多）：BGM 与语音降一档，音效不动，不改播放代码。

- BGM（audio/music/*.ogg）：没有母带（gen_music*.py 直接写 OGG），解码后按 BGM_LEVEL 重新编码；只在变小时替换，
  帧数必须与原文件相同（乐句式曲目按帧接缝）。生成脚本的编码档位同步改成 BGM_LEVEL，以后重跑也是这一档。
- 语音（audio/voice/*.ogg）：从 masters/ 的 WAV 母带重编码（不叠加有损），voice_manifest.json 每条 ogg_quality 加 VOICE_STEP（封顶 VOICE_MAX）。
- 对比样本：BGM / 语音各取几条，压前压后各一段写到 <主仓库>/build/audio_shrink/。

用法：python game/tools/shrink_audio.py            先写 <主仓库>/build/audio_shrink/stage/ 并打印省多少
      python game/tools/shrink_audio.py --apply    写进 game/audio/（覆盖的都是 git 跟踪文件）并改清单
需要 numpy + soundfile。
"""
import io, json, os, subprocess, sys
import numpy as np
import soundfile as sf

BGM_LEVEL = 0.70     # soundfile compression_level（0 最好、1 最小）；原 gen_music 0.45、战斗曲 0.62 / 0.66
VOICE_STEP = 0.1
VOICE_MAX = 0.8

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
man_path = os.path.join(VOICE, "voice_manifest.json")
man = json.load(open(man_path, encoding="utf-8"))
for clip in man["clips"]:
    dst = os.path.join(VOICE, clip["file"])
    old = os.path.getsize(dst)
    q = round(min(VOICE_MAX, float(clip.get("ogg_quality", 0.3)) + VOICE_STEP), 2)
    x, sr = sf.read(os.path.join(VOICE, clip["master"]), dtype="float32")
    new = enc(x, sr, q)
    assert frames(new) == len(x), f"{clip['file']}: 帧数变了"
    tot["语音"][0] += old
    tot["语音"][1] += len(new)
    clip["ogg_quality"] = q
    put(os.path.join("audio", "voice", clip["file"]), new)
if APPLY:
    with open(man_path, "w", encoding="utf-8", newline="\n") as f:
        f.write(json.dumps(man, ensure_ascii=False, indent=2) + "\n")   # 与 voice_ogg.py 写法一致

for k, (a, b) in tot.items():
    print("%s  %.2f → %.2f MiB（省 %.2f MiB，%.0f%%）" % (k, a / 2**20, b / 2**20, (a - b) / 2**20, 100 * (a - b) / max(1, a)))
a = sum(v[0] for v in tot.values()); b = sum(v[1] for v in tot.values())
print("合计  %.2f → %.2f MiB（省 %.2f MiB）" % (a / 2**20, b / 2**20, (a - b) / 2**20))
print("->", GAME if APPLY else STAGE)
