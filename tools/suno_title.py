# Suno 主题曲接入：去尾部静音 → 尾首交叉淡化成无缝循环 → 响度对齐 -17.8 LUFS → 写 ogg
import sys, numpy as np, soundfile as sf
sys.path.insert(0, r"E:\ArknightsSurvivors\game\tools")
import gen_music_battle as gb

src, dst = sys.argv[1], sys.argv[2]
x, sr = sf.read(src, always_2d=True)
gb.SR = sr
m = np.abs(x).max(1)
thr = 10 ** (-50 / 20)
end = int(np.nonzero(m > thr)[0][-1]) + 1          # 去掉尾部静音
x = x[:end]
L = int(sr * 4.0)                                     # 4 秒交叉淡化：尾巴淡出叠进开头淡入
t = np.linspace(0, np.pi / 2, L)[:, None]
fi, fo = np.sin(t), np.cos(t)                         # 等功率
y = x[L:].copy()
y[-L:] = x[-L:] * fo + x[:L] * fi
target = -17.8                                        # 与旧标题曲同档（docs/21）
g = 10 ** ((target - gb.lufs(y)) / 20)
y = y * g
pk = float(np.abs(y).max())
if pk > 0.9:
    y = np.tanh(y / 0.9) * 0.9                       # 软限，与 gen_music 一致的思路
with sf.SoundFile(dst, "w", sr, y.shape[1], format="OGG", subtype="VORBIS", compression_level=0.35) as f:
    pass
    for i in range(0, len(y), 65536):
        f.write(y[i:i + 65536].astype(np.float32))
z, _ = sf.read(dst, always_2d=True)
seam = float(np.abs(z[0] - z[-1]).max())
print("dur", round(len(y) / sr, 2), "gain_db", round(20 * np.log10(g), 2), "peak_before", round(pk, 3),
      "lufs_out", round(gb.lufs(z), 2), "seam_jump", round(seam, 4))
