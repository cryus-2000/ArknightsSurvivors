# Suno 曲目接入：解码 → 降采样到 32 kHz → 去尾静音 → 尾首 4 秒等功率交叉淡化成无缝循环 → 响度对齐 → 写 ogg
# 用法：python suno_track.py <输入 wav/mp3> <输出 ogg> <目标 LUFS> [交叉淡化秒数]
import sys, io, subprocess, numpy as np, soundfile as sf
sys.path.insert(0, r"E:\ArknightsSurvivors\game\tools")
import gen_music_battle as gb
FF = r"C:\Users\colafax\AppData\Local\Packages\PythonSoftwareFoundation.Python.3.13_qbz5n2kfra8p0\LocalCache\local-packages\Python313\site-packages\imageio_ffmpeg\binaries\ffmpeg-win-x86_64-v7.1.exe"
SR = 32000
src, dst, target = sys.argv[1], sys.argv[2], float(sys.argv[3])
xf = float(sys.argv[4]) if len(sys.argv) > 4 else 4.0
raw = subprocess.run([FF, "-v", "error", "-i", src, "-ac", "2", "-ar", str(SR), "-f", "wav", "-"], capture_output=True).stdout
x, sr = sf.read(io.BytesIO(raw), always_2d=True)
gb.SR = sr
m = np.abs(x).max(1)
end = int(np.nonzero(m > 10 ** (-50 / 20))[0][-1]) + 1
x = x[:end]
L = int(sr * xf)
t = np.linspace(0, np.pi / 2, L)[:, None]
y = x[L:].copy()
y[-L:] = x[-L:] * np.cos(t) + x[:L] * np.sin(t)
g = 10 ** ((target - gb.lufs(y)) / 20)
y = y * g
if np.abs(y).max() > 0.9:
    y = np.tanh(y / 0.9) * 0.9
with sf.SoundFile(dst, "w", sr, 2, format="OGG", subtype="VORBIS", compression_level=0.45) as f:
    for i in range(0, len(y), 65536):
        f.write(y[i:i + 65536].astype(np.float32))
z, _ = sf.read(dst, always_2d=True)
print(dst.split("\\")[-1].split("/")[-1], "sr", sr, "dur", round(len(z) / sr, 1), "lufs", round(gb.lufs(z), 2),
      "peak", round(float(np.abs(z).max()), 3), "seam", round(float(np.abs(z[0] - z[-1]).max()), 4))
