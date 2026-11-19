# -*- coding: utf-8 -*-
"""网页配乐出包（11-08 docs/319 §12）：长配乐不进 index.pck，改成单独的 AAC 文件，由浏览器解码（tools/web/web_music.js）。

为什么：引擎把每首配乐注册成网页样本时，先在 WASM 堆里整段解成双声道 float（一首 200 秒约 +100 MB 堆高水位，只涨不缩），
iPhone B站 App 实测 WASM 一开局就 513 MB。浏览器 decodeAudioData 在 JS 侧解码（异步、不占主线程、不进 WASM 堆），
解出来的 AudioBuffer 与引擎样本同样大小（按音频上下文采样率），但 WASM 不再被配乐撑高，主包也少了这些 OGG。
为什么是 AAC：iOS Safari / WKWebView 的 decodeAudioData 不保证认 Ogg Vorbis，AAC（.m4a）各家浏览器都认。
码率按原 OGG 平均码率 × 1.15 + 2 kbps（Toy 包上限 50 MB）。

- 只处理长曲（≥ LONG_MIN 秒，开场引子 / Boss 登场与击破乐句等短句仍在主包里走引擎样本）；
- 每首写 <out>/music_<名>.m4a，并在副本的 audio/music/web_music.json 记 {名: {len 秒, url}}，删掉副本里的 .ogg / .ogg.import；
- sfx.gd 在网页上看到 web_music.json 就给这些曲目建静音占位播放器，由 web_music.js 照着占位器的播放 / 停止 / 音量出声。
只改导出副本，仓库与桌面包不动。用法：externalize(副本 game 目录, 网页输出目录)
"""
import json, os, shutil, subprocess, tempfile

import soundfile as sf

import re
LONG_MIN = 30.0
OVERLAY_LAYER = re.compile(r"^suno_battle\d_(pulse|drive)$")
SKIP = {"opening", "boss_in", "boss_down"}
# 二阶段预混：p2 层名 -> 底层 p1 名 / 输出名（url 与 tools/web/web_music.js 的 PAIRS 一致）。只做结局一偏执泡影：其余三首结局 Boss 各 +1.6 MB，Toy 包 50 MB 线放不下——那三首在 web_music.js 里运行时混（PAIRS mix: null，11-12 docs/319 §24）
PREMIX_P2 = {"suno_final_p2": "suno_final_p1"}
PREMIX_P2_OUT = {"suno_final_p2": "suno_final_p12_mono"}
# Toy 包专用配乐档（11-19，Toy 50 MB 线要给新干员腾地方）：全部单声道（手机本来就在 web_music.js 里混成单声道再播，听感只差在电脑 Toy 的立体声），
# 码率 = 现行码率 × k（下限 floor kbps），sr 非空时再降采样。全单声道后偏执泡影 p1 不再另存 _mono 副本（web_music.js 看 __SY_MUS_MONO 直接解 p1）。
# itch 网页包不传 toy_tier，行为不变。档位由用户试听后定（export_web.py --toy-music）
TOY_TIERS = {
    "A": {"k": 0.75, "floor": 20, "sr": None},
    "B": {"k": 0.55, "floor": 16, "sr": 16000},
}


def _ffmpeg():
    import imageio_ffmpeg
    return imageio_ffmpeg.get_ffmpeg_exe()


def externalize(gamedir, outdir, toy_tier=None, toy_outdir=None):
    """返回 (曲数, 原 OGG 字节, 新 AAC 字节)。toy_tier：TOY_TIERS 的键，None = 现行（itch 网页包）。
    单独出 Toy 包（export_web --toy）：toy_tier 给档位、toy_outdir 不给，outdir 里就是 Toy 档。
    共用导入（export_web --toy-out）：outdir 出 itch 现行档，toy_outdir 另出一份 Toy 档（toy_tier 档位），
    Toy 档的 web_music.json 内容写到 toy_outdir/web_music.toy.json，Toy 那次导出前由调用方换进副本（use_toy_meta）"""
    mdir = os.path.join(gamedir, "audio", "music")
    if toy_outdir:
        meta, n, before, after, done = _encode_all(mdir, outdir, None)
        tmeta, _, _, tafter, _ = _encode_all(mdir, toy_outdir, TOY_TIERS[toy_tier])
        with open(os.path.join(toy_outdir, "web_music.toy.json"), "w", encoding="utf-8") as fh:
            json.dump(tmeta, fh, ensure_ascii=False, indent=1)
    else:
        meta, n, before, after, done = _encode_all(mdir, outdir, TOY_TIERS[toy_tier] if toy_tier else None)
    for f in done:   # 全部处理完再删：预混要读 p2 之前的 p1 原文件
        for g in (f, f + ".import"):
            gp = os.path.join(mdir, g)
            if os.path.exists(gp):
                os.remove(gp)
    with open(os.path.join(mdir, "web_music.json"), "w", encoding="utf-8") as fh:
        json.dump(meta, fh, ensure_ascii=False, indent=1)
    return n, before, after


def use_toy_meta(gamedir, toy_outdir):
    """共用导入出 Toy 包：把 Toy 档的 web_music.json 换进副本（之后再导出一次），toy_outdir 里的 .m4a 就是 Toy 包的配乐；返回 Toy 档 AAC 字节"""
    src = os.path.join(toy_outdir, "web_music.toy.json")
    shutil.move(src, os.path.join(gamedir, "audio", "music", "web_music.json"))
    return sum(os.path.getsize(os.path.join(toy_outdir, f)) for f in os.listdir(toy_outdir) if f.endswith(".m4a"))


def _encode_all(mdir, odir, tt):
    """mdir 里的长曲编成 odir/music_*.m4a；返回 (meta, 曲数, 原 OGG 字节, AAC 字节, 处理过的文件名)。不删原文件"""
    os.makedirs(odir, exist_ok=True)   # 平铺在网页输出根目录（Toy zip 只收根目录文件）
    meta = {}
    n = before = after = 0
    done = []
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
        kbps = max(24, min(160, int(round(size * 8 / dur / 1000 * 1.15)) + 2))   # AAC-LC 低码率比 Vorbis 吃亏约一成半；Toy 包 50 MB 上限（11-09 实测 40 kbps 下限超到 52 MB）
        x, sr = sf.read(p, dtype="float32")
        if OVERLAY_LAYER.match(name) and x.ndim == 2:
            x = x.mean(1)   # 战斗加层（打击乐 / 驱动）：手机只放底层，加层只在桌面网页叠在立体声底层上；单声道 × 0.65 码率，省约 2.4 MiB（Toy 包 49.9 → 约 47.5 MB）
            kbps = max(24, int(round(kbps * 0.65)))
        mix_kbps = max(24, int(round(kbps * 0.65)))   # 二阶段预混（单声道）码率：按 Toy 档缩放之前的口径
        out_sr = sr
        if tt:
            if x.ndim == 2:
                x = x.mean(1)
            kbps = max(tt["floor"], int(round(kbps * tt["k"])))
            mix_kbps = max(tt["floor"], int(round(mix_kbps * tt["k"])))
            if tt["sr"] and tt["sr"] < sr:
                out_sr = tt["sr"]
        ar = ["-ar", str(out_sr)] if out_sr != sr else []
        o = os.path.join(odir, "music_%s.m4a" % name)
        with tempfile.TemporaryDirectory() as td:
            w = os.path.join(td, "a.wav")
            sf.write(w, x, sr, subtype="FLOAT")
            subprocess.run([ff, "-v", "error", "-y", "-i", w, "-c:a", "aac", "-b:a", "%dk" % kbps] + ar + ["-movflags", "+faststart", o], check=True)
            # 偏执泡影 P1：手机原本就在播放前取 (L + R) / 2。另存同码率副本，
            # 避免登场时同时持有整首立体声解码缓冲和单声道渲染目标。
            if name == "suno_final_p1" and x.ndim == 2 and x.shape[1] == 2:
                mobile = os.path.join(odir, "music_suno_final_p1_mono.m4a")
                subprocess.run([ff, "-v", "error", "-y", "-i", w, "-af", "pan=mono|c0=0.5*c0+0.5*c1",
                                "-c:a", "aac", "-b:a", "%dk" % kbps, "-movflags", "+faststart", mobile], check=True)
                after += os.path.getsize(mobile)
        # 偏执泡影二阶段（11-11 docs/332 §2）：手机二阶段原来 p1 + p2 两份单声道缓冲同驻（配乐 19 → 37 MB）。另存 p1 + p2 的单声道预混，
        # web_music.js 在二阶段放它、把 p1 交叉淡出后释放。同采样率同编码器，AAC 起始延迟与 p1 一致，样本级对齐；单声道码率 × 0.65（同战斗加层）
        if name in PREMIX_P2:
            bp = os.path.join(mdir, PREMIX_P2[name] + ".ogg")
            xb, srb = sf.read(bp, dtype="float32")
            xa = x.mean(1) if x.ndim == 2 else x
            xb = xb.mean(1) if xb.ndim == 2 else xb
            assert srb == sr and abs(len(xb) - len(xa)) <= 1, "预混两层长度 / 采样率不一致：%s" % name
            n2 = min(len(xa), len(xb))
            mix = xa[:n2] + xb[:n2]
            pk = float(abs(mix).max())
            if pk > 0.999:
                mix *= 0.999 / pk   # 防削波（偏执泡影实测峰值 0.986，不会触发）
            mo = os.path.join(odir, "music_%s.m4a" % PREMIX_P2_OUT[name])
            with tempfile.TemporaryDirectory() as td:
                w = os.path.join(td, "m.wav")
                sf.write(w, mix, sr, subtype="FLOAT")
                subprocess.run([ff, "-v", "error", "-y", "-i", w, "-c:a", "aac", "-b:a", "%dk" % mix_kbps] + ar +
                               ["-movflags", "+faststart", mo], check=True)
            after += os.path.getsize(mo)
        # pre：AAC 编码器前置预滚（1024 样本）秒数。web_music.js 解码后据此判断浏览器有没有去掉预滚，没去掉就平移循环点（11-12 配乐循环验收）
        meta[name] = {"len": round(dur, 6), "url": "music_%s.m4a" % name, "pre": round(1024.0 / out_sr, 6)}
        n += 1
        before += size
        after += os.path.getsize(o)
        done.append(f)
    return meta, n, before, after, done


def report(r):
    return "配乐出包 %d 首：OGG %.2f MiB → AAC %.2f MiB（docs/319 §12）" % (r[0], r[1] / 1048576, r[2] / 1048576)
