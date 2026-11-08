# -*- coding: utf-8 -*-
"""网页配乐出包（11-08 docs/319 §12）：长配乐不进 index.pck，改成单独的 AAC 文件，由浏览器解码（tools/web/web_music.js）。

为什么：引擎把每首配乐注册成网页样本时，先在 WASM 堆里整段解成双声道 float（一首 200 秒约 +100 MB 堆高水位，只涨不缩），
iPhone B站 App 实测 WASM 一开局就 513 MB。浏览器 decodeAudioData 在 JS 侧解码（异步、不占主线程、不进 WASM 堆），
解出来的 AudioBuffer 与引擎样本同样大小（按音频上下文采样率），但 WASM 不再被配乐撑高，主包也少了这些 OGG。
为什么是 AAC：iOS Safari / WKWebView 的 decodeAudioData 不保证认 Ogg Vorbis，AAC（.m4a）各家浏览器都认。
码率按原 OGG 的平均码率给（再 +4 kbps），包体基本不变（Toy 包上限 50 MB）。

- 只处理长曲（≥ LONG_MIN 秒，开场引子 / Boss 登场与击破乐句等短句仍在主包里走引擎样本）；
- 每首写 <out>/music_<名>.m4a，并在副本的 audio/music/web_music.json 记 {名: {len 秒, url}}，删掉副本里的 .ogg / .ogg.import；
- sfx.gd 在网页上看到 web_music.json 就给这些曲目建静音占位播放器，由 web_music.js 照着占位器的播放 / 停止 / 音量出声。
只改导出副本，仓库与桌面包不动。用法：externalize(副本 game 目录, 网页输出目录)
"""
import json, os, subprocess, tempfile

import soundfile as sf

LONG_MIN = 30.0
SKIP = {"opening", "boss_in", "boss_down"}


def _ffmpeg():
    import imageio_ffmpeg
    return imageio_ffmpeg.get_ffmpeg_exe()


def externalize(gamedir, outdir):
    """返回 (曲数, 原 OGG 字节, 新 AAC 字节)"""
    mdir = os.path.join(gamedir, "audio", "music")
    odir = outdir   # 平铺在网页输出根目录（Toy zip 只收根目录文件）
    os.makedirs(odir, exist_ok=True)
    meta = {}
    n = before = after = 0
    ff = _ffmpeg()
    for f in sorted(os.listdir(mdir)):
        if not f.endswith(".ogg"):
            continue
        name = f[:-4]
        p = os.path.join(mdir, f)
        info = sf.info(p)
        dur = info.frames / float(info.samplerate)
        if name in SKIP or dur < LONG_MIN:
            continue
        size = os.path.getsize(p)
        kbps = max(40, min(160, int(size * 8 / dur / 1000) + 4))
        x, sr = sf.read(p, dtype="float32")
        o = os.path.join(odir, "music_%s.m4a" % name)
        with tempfile.TemporaryDirectory() as td:
            w = os.path.join(td, "a.wav")
            sf.write(w, x, sr, subtype="FLOAT")
            subprocess.run([ff, "-v", "error", "-y", "-i", w, "-c:a", "aac", "-b:a", "%dk" % kbps, "-movflags", "+faststart", o], check=True)
        meta[name] = {"len": round(dur, 6), "url": "music_%s.m4a" % name}
        n += 1
        before += size
        after += os.path.getsize(o)
        for g in (f, f + ".import"):
            gp = os.path.join(mdir, g)
            if os.path.exists(gp):
                os.remove(gp)
    with open(os.path.join(mdir, "web_music.json"), "w", encoding="utf-8") as fh:
        json.dump(meta, fh, ensure_ascii=False, indent=1)
    return n, before, after


def report(r):
    return "配乐出包 %d 首：OGG %.2f MiB → AAC %.2f MiB（docs/319 §12）" % (r[0], r[1] / 1048576, r[2] / 1048576)
