# -*- coding: utf-8 -*-
"""干员语音日 / 英 / 韩三语版（11-15 用户：中文 237 条对应的原作外语配音也放进来，按「语音语言」设置切换）。

来源同中文版：Ark-Voice（isHarryh/Ark-Voice，固定在 REV）长音轨 + voice_data.json 每语言各自的切片起点。
  日语 voice/、英语 voice_en/、韩语 voice_kr/（中文 voice_cn/）；同一干员同一编号（CN_0xx）即同一句台词。
每条中文语音按 manifest 的 source_operator + source_clip 找到外语同编号整段，再按静音检测重新截取：
  10 ms 帧 RMS，阈值 = max(-50 dBFS, 段内峰值 -38 dB)；首个 / 末个过阈帧前留 PAD_HEAD、后留 PAD_TAIL（不出原段），
  头 FADE_IN、尾 FADE_OUT 线性淡入淡出。整段原句不截半句（只削首尾静音）。
  外语没有这一编号（如水月、铃兰无英语配音）或截后超过 sfx.gd VOICE_MAX_LEN → 不出文件，manifest 记 missing，游戏回退中文。
输出：game/audio/voice/<ja|en|ko>/<主名>.ogg（24 kHz 单声道，compression_level 与对应中文条目的 ogg_quality 一致）。
  外语母带不进仓库（约 150 MB），需要时用本脚本从 build/ 的原始长音轨重切；manifest 记源区间、截取区间和 OGG SHA-256。
  manifest 每条中文条目加 "langs": {"ja": {...}, "en": {...}, "ko": {...}}。

用法：先下载长音轨到 --src（主仓库 build/arkvoice_ml/{voice,voice_en,voice_kr}/<char>.ogg + voice_data.json；
      台词表 charword/{ja_JP,en_US,ko_KR}.json 取自 Kengxxiao/ArknightsGameData_YoStar main；PRTS 单条自动下载缓存到 prts/），
      python tools/voice_lang_1115.py --src E:/ArknightsSurvivors/build/arkvoice_ml [--dry] [--table build/voice_lang_table.csv]
"""
import argparse, csv, hashlib, json, os, sys

import numpy as np
import soundfile as sf

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
sys.path.insert(0, os.path.join(ROOT, "game", "tools"))
import voice_ogg as VO

REV = "79584841f7a28f9d029ec2dc1b72444bce87eb1e"
VOICE = os.path.join(ROOT, "game", "audio", "voice")
# 游戏语言码 -> (Ark-Voice voice_data 变体名, 仓库目录)
LANGS = {"ja": ("JP", "voice"), "en": ("EN", "voice_en"), "ko": ("KR", "voice_kr")}
MAX_LEN = 10.0         # 同 sfx.gd VOICE_MAX_LEN（11-15 由 8 提到 10：韩语 W 突击、日语歌蕾蒂娅入队整句 8.1–9.5 秒）
FRAME = 0.01
PAD_HEAD, PAD_TAIL = 0.06, 0.15
FADE_IN, FADE_OUT = 0.005, 0.04
FLOOR_DB, REL_DB = -60.0, 40.0


def sha(p):
    with open(p, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()


def trim(x, sr):
    """返回 (s0, s1, 头贴边, 尾贴边)：x 内语音的起止样本（含留白）。
    阈值随录音底噪走（英 / 韩录音底噪 -50~-60 dB，固定阈值会把底噪当语音）：max(峰值 -REL_DB, 底噪(10% 分位) +12 dB, FLOOR_DB)。
    贴边 = 首 / 末 20 ms 内就有离峰值 20 dB 以内的响声（可能是原段起点偏晚 / 终点偏早，要人听）"""
    n = int(FRAME * sr)
    k = len(x) // n
    if k == 0:
        return 0, len(x), False, False
    fr = x[:k * n].reshape(k, n)
    db = 10 * np.log10(np.mean(fr * fr, axis=1) + 1e-12)
    pk = db.max()
    th = max(FLOOR_DB, pk - REL_DB, float(np.percentile(db, 10)) + 12.0)
    on = np.nonzero(db > th)[0]
    if len(on) == 0:
        return 0, len(x), False, False
    a, b = int(on[0]), int(on[-1]) + 1
    s0 = max(0, a * n - int(PAD_HEAD * sr))
    s1 = min(len(x), b * n + int(PAD_TAIL * sr))
    return s0, s1, bool((db[:2] > pk - 20).any()), bool((db[-2:] > pk - 20).any())


def fade(y, sr):
    y = y.copy()
    fi, fo = min(len(y), int(FADE_IN * sr)), min(len(y), int(FADE_OUT * sr))
    if fi:
        y[:fi] *= np.linspace(0, 1, fi, dtype=np.float32)
    if fo:
        y[-fo:] *= np.linspace(1, 0, fo, dtype=np.float32)
    return y


def active_rms(x, sr):
    """有声帧（离峰值 30 dB 以内的 10 ms 帧）的 RMS"""
    if x.ndim > 1:
        x = x.mean(axis=1)
    n = int(FRAME * sr)
    k = len(x) // n
    if k == 0:
        return float(np.sqrt(np.mean(x * x) + 1e-12))
    e = np.mean(x[:k * n].reshape(k, n) ** 2, axis=1)
    m = e > e.max() * 1e-3
    return float(np.sqrt(e[m].mean()))


PRTS = "https://torappu.prts.wiki/assets/audio/%s/%s/%s.mp3"


def prts_clip(src, sub, cid, n):
    """PRTS 单条 mp3（缓存到 src/prts/）→ (44.1 kHz 单声道, URL, sha256)；没有返回 None"""
    import urllib.request
    url = PRTS % (sub, cid, n.lower())
    p = os.path.join(src, "prts", sub, cid, n.lower() + ".mp3")
    if not os.path.exists(p):
        os.makedirs(os.path.dirname(p), exist_ok=True)
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
            data = urllib.request.urlopen(req, timeout=60).read()
        except Exception:
            return None
        with open(p, "wb") as f:
            f.write(data)
    x, sr = sf.read(p, dtype="float32")
    if x.ndim > 1:
        x = x.mean(axis=1)
    if sr != VO.SR:
        from scipy.signal import resample_poly
        g = np.gcd(sr, VO.SR)
        x = resample_poly(x, VO.SR // g, sr // g).astype(np.float32)
    return x, url, sha(p)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", required=True)
    ap.add_argument("--dry", action="store_true")
    ap.add_argument("--table", default="")
    a = ap.parse_args()
    vd = json.load(open(os.path.join(a.src, "voice_data.json"), encoding="utf-8"))["data"]
    man_p = os.path.join(VOICE, "voice_manifest.json")
    man = json.load(open(man_p, encoding="utf-8"))
    tracks = {}
    # 各语言台词文本（ArknightsGameData_YoStar <区服>/gamedata/excel/charword_table.json，放 --src/charword/<区服>.json）：写进 manifest 作对位凭据
    words = {}
    for lang, reg in (("ja", "ja_JP"), ("en", "en_US"), ("ko", "ko_KR")):
        wp = os.path.join(a.src, "charword", reg + ".json")
        words[lang] = json.load(open(wp, encoding="utf-8")).get("charWords", {}) if os.path.exists(wp) else {}
    rows, flags, total = [], [], {k: 0 for k in LANGS}
    cnt = {k: [0, 0] for k in LANGS}   # [有, 缺]
    prts_n = {k: 0 for k in LANGS}
    for lang in LANGS:
        os.makedirs(os.path.join(VOICE, lang), exist_ok=True)
    for c in man["clips"]:
        stem = os.path.splitext(c["file"])[0]
        cid, n = c["source_operator"], c["source_clip"]
        row = {"file": stem, "operator": c["operator"], "clip": n, "zh": c["duration_seconds"]}
        langs = {}
        cn_rms = active_rms(*sf.read(os.path.join(ROOT, c["master"]), dtype="float32")) if c.get("master") else None
        for lang, (var_name, sub) in LANGS.items():
            var = vd.get(cid, {}).get("variations", {}).get(var_name)
            names = [x["name"] for x in var["clips"]] if var else []
            path = os.path.join(a.src, sub, cid + ".ogg")
            seg, ent = None, None
            if n in names and os.path.exists(path):
                i = names.index(n)
                t0 = var["clips"][i]["start"]
                t1 = var["clips"][i + 1]["start"] if i + 1 < len(names) else var["duration"]
                key = (lang, cid)
                if key not in tracks:
                    x, sr = sf.read(path, dtype="float32")
                    if x.ndim > 1:
                        x = x.mean(axis=1)
                    assert sr == VO.SR, (path, sr)
                    tracks[key] = (x, sha(path), abs(len(x) / sr - var["duration"]) < 0.05)
                x, src_sha, aligned = tracks[key]
                if aligned:   # 长音轨与 voice_data 总长一致才按起点切（韩语斯卡蒂 / 浊心 / 塞雷娅 / 歌蕾蒂娅对不上，改取 PRTS 单条）
                    g0, g1 = int(round(t0 * VO.SR)), min(len(x), int(round(t1 * VO.SR)))
                    seg = x[g0:g1]
                    ent = {"source_url": "https://raw.githubusercontent.com/isHarryh/Ark-Voice/%s/%s/%s.ogg" % (REV, sub, cid),
                           "source_language": var_name, "source_audio_sha256": src_sha,
                           "source_start_seconds": round(t0, 6), "source_end_seconds": round(t1, 6)}
            if seg is None:   # PRTS 单条（torappu 资源站 voice/voice_en/voice_kr/<角色>/cn_0xx.mp3）：长音轨缺（水月、铃兰英语）或对不上
                got = prts_clip(a.src, sub, cid, n)
                if got is not None:
                    seg, url, src_sha = got
                    g0 = 0
                    ent = {"source_url": url, "source_language": var_name, "source_audio_sha256": src_sha}
                    prts_n[lang] += 1
            if seg is None:
                langs[lang] = {"missing": True, "reason": "no_source"}
                row[lang] = ""
                cnt[lang][1] += 1
                continue
            sr = VO.SR
            s0, s1, edge_a, edge_b = trim(seg, sr)
            dur = (s1 - s0) / sr
            ent.update({"cut_start_sample": g0 + s0, "cut_end_sample": g0 + s1, "duration_seconds": round(dur, 3)})
            w = words[lang].get(cid + "_" + n)
            if w:
                ent["text"] = w.get("voiceText", "")
                ent["text_source_key"] = cid + "_" + n
            else:
                flags.append("%s %s %s 台词表里没有这一条" % (lang, stem, n))
            y = seg[s0:s1]
            if cn_rms is not None:   # 响度对齐中文母带（有声帧 RMS），sfx.gd VOICE_TRIM 按干员的修正照旧适用；±9 dB 内，峰值不过 -1 dBFS
                g = float(np.clip(cn_rms / max(active_rms(y, sr), 1e-6), 10 ** (-9 / 20), 10 ** (9 / 20)))
                g = min(g, 0.891 / max(float(np.abs(y).max()), 1e-6))
                y = y * g
                ent["gain_db"] = round(20 * np.log10(g), 2)
            if edge_a or edge_b:
                ent["edge"] = ("head" if edge_a else "") + ("tail" if edge_b else "")
                flags.append("%s %s %s 语音贴%s边" % (lang, stem, n, ent["edge"]))
            if dur > MAX_LEN:
                ent.update({"missing": True, "reason": "too_long"})
                langs[lang] = ent
                row[lang] = ""
                cnt[lang][1] += 1
                flags.append("%s %s %.2f s 超 %.0f 秒，回退中文" % (lang, stem, dur, MAX_LEN))
                continue
            q = float(c.get("ogg_quality", VO.DEFAULT_Q))
            ogg = os.path.join(VOICE, lang, stem + ".ogg")
            if not a.dry:
                tmp = os.path.join(VOICE, lang, "_tmp.wav")
                sf.write(tmp, np.clip(fade(y.astype(np.float32), sr), -1, 1), sr, subtype="PCM_16")
                VO.encode(tmp, ogg, q)
                os.remove(tmp)
                ent["ogg_sha256"] = sha(ogg)
                total[lang] += os.path.getsize(ogg)
            ent["file"] = "%s/%s.ogg" % (lang, stem)
            ent["ogg_quality"] = q
            langs[lang] = ent
            row[lang] = round(dur, 2)
            cnt[lang][0] += 1
        c["langs"] = langs
        rows.append(row)
    for f in flags:
        sys.stdout.buffer.write((f + "\n").encode("utf-8"))
    for lang in LANGS:
        print("%s: %d 条（其中 PRTS 单条 %d）/ 缺 %d 条，OGG %.2f MiB" % (lang, cnt[lang][0], prts_n[lang], cnt[lang][1], total[lang] / 1048576))
    if a.table:
        with open(a.table, "w", encoding="utf-8-sig", newline="") as f:
            w = csv.DictWriter(f, ["file", "operator", "clip", "zh", "ja", "en", "ko"])
            w.writeheader()
            for r in rows:
                w.writerow({k: ("缺" if r[k] == "" else r[k]) for k in w.fieldnames})
    if a.dry:
        return
    man["voice_lang_1115"] = {
        "date": "2026-11-15", "source_revision": REV, "tool": "tools/voice_lang_1115.py",
        "dirs": {k: "audio/voice/%s/" % k for k in LANGS},
        "trim": "silence trim within the language's own voice_data span: 10 ms RMS, threshold max(%g dBFS, peak-%g dB, noise p10+12 dB), pad %g/%g s, fade %g/%g s" % (FLOOR_DB, REL_DB, PAD_HEAD, PAD_TAIL, FADE_IN, FADE_OUT),
        "note": "原作日 / 英 / 韩配音，同干员同编号即同一句；missing = 该语言无此条或超 8 秒，游戏回退中文。外语母带不进仓库，可从源长音轨按 cut_*_sample 重切",
        "counts": {k: {"have": cnt[k][0], "missing": cnt[k][1]} for k in LANGS}}
    with open(man_p, "w", encoding="utf-8", newline="\n") as f:
        f.write(json.dumps(man, ensure_ascii=False, indent=2) + "\n")


if __name__ == "__main__":
    main()
