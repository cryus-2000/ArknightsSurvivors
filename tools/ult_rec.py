# -*- coding: utf-8 -*-
"""终结技原型审阅录像（docs/198，10-29）：每段一名队长，局内自动放终结技 / 连携 / 连携终结技，原速 30 帧（--realtime），出 mp4。
用法：python tools/ult_rec.py [--clips texas,exusiai,skalter,kaltsit,ulpianus,cult] [--at 30] [--secs 14] [--tag 名] [--jobs 3]
  每个队长一段：编队带两名有连携的队友，能量倍率调高让终结技在录制窗口里放出；cult = 协同满 + 连携终结技那一段。
  输出 build/ult_rec/<tag>/<段>.mp4，再拼一条 all.mp4。"""
import argparse, glob, json, os, shutil, subprocess, sys, wave
import numpy as np
from concurrent.futures import ThreadPoolExecutor
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import godot_runner as GR
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
CLIPS = {
    "texas": ("texas", "exusiai,lappland", []),
    "exusiai": ("exusiai", "texas,saria", []),
    "skalter": ("skalter", "skadi,gladiia", []),
    "kaltsit": ("kaltsit", "hoshiguma,lumen", []),
    "ulpianus": ("ulpianus", "gladiia,specter_unchained", []),
    "cult": ("texas", "exusiai,lappland", ["--bal=ult/test_cells=7"]),
    "combo": ("texas", "exusiai,siege", ["--bot=master", "--bal=ult/test_fill_at=-1"], 90.0),
    "link1": ("texas", "exusiai,lappland", ["--bal=combo/skill_link=1", "--bal=ult/test_fill_at=-1", "--bal=ult/test_skill_at=62", "--bal=ult/test_skill_idx=0"], 60.0),   # 技能连携样片①：德克萨斯剑雨 + 能天使 → 爆炸剑雨
    "link2": ("lappland", "texas,saria", ["--bal=combo/skill_link=1", "--bal=ult/test_fill_at=-1", "--bal=ult/test_skill_at=62", "--bal=ult/test_skill_idx=1"], 60.0),   # 样片②：拉普兰德狼魂剑气 + 德克萨斯 → 十字斩
    "lf": ("texas", "exusiai,lappland", ["--bal=combo/skill_link=1", "--bal=ult/test_fill_at=-1", "--bal=ult/test_skill_at=61.5", "--bal=ult/test_skill_idx=0", "--bal=ult/test_skill_every=4", "--bal=ult/link_gap=3.5", "--bal=link/calm=0"], 60.0),   # 连携轻量演出（link/flash）：约 4 秒一次、关掉防疲劳（link/calm=0，只为录像），每次完整演出
    "lf_calm": ("texas", "exusiai,lappland", ["--bal=combo/skill_link=1", "--bal=ult/test_fill_at=-1", "--bal=ult/test_skill_at=61.5", "--bal=ult/test_skill_idx=0", "--bal=ult/test_skill_every=3", "--bal=ult/link_gap=1"], 60.0),   # 同上隔 3 秒：防疲劳（第一次完整，之后只打聚光）
    "s_pursue": ("skadi", "texas", ["--bal=combo/skill_link=1", "--bal=ult/test_fill_at=-1", "--bal=ult/test_skill_at=61.2", "--bal=ult/test_skill_idx=0", "--bal=ult/test_skill_every=3"], 60.0),   # 技能连携四类样片：追击·德克萨斯
    "s_lava": ("skadi", "eyjafjalla", ["--bal=combo/skill_link=1", "--bal=ult/test_fill_at=-1", "--bal=ult/test_skill_at=61.2", "--bal=ult/test_skill_idx=0", "--bal=ult/test_skill_every=3"], 60.0),   # 技能连携四类样片：附加·艾雅法拉
    "s_gather": ("skadi", "gladiia", ["--bal=combo/skill_link=1", "--bal=ult/test_fill_at=-1", "--bal=ult/test_skill_at=61.2", "--bal=ult/test_skill_idx=0", "--bal=ult/test_skill_every=3"], 60.0),   # 技能连携四类样片：聚拢·歌蕾蒂娅
    "s_cover": ("skadi", "hoshiguma", ["--bal=combo/skill_link=1", "--bal=ult/test_fill_at=-1", "--bal=ult/test_skill_at=61.2", "--bal=ult/test_skill_idx=0", "--bal=ult/test_skill_every=3"], 60.0),   # 技能连携四类样片：掩护·星熊
    "combo2": ("skadi", "gladiia,ulpianus", ["--bot=master", "--bal=ult/test_fill_at=-1"], 90.0),   # 深海猎人：组合升级自动接（两人同框条带）   # 连携：两人都跟队长冲刺（master 机器人会冲刺）；这段不放终结技
}
# 20 人终结技各一段（u_<干员>）：队长 + 两名不同的队友，0:31.5 充满放出（录像口径同上）
_ALL20 = "angelina exusiai eyjafjalla gladiia hoshiguma irene kaltsit lappland logos lumen mizuki saria siege skadi skalter specter_unchained suzuran texas ulpianus wisadel".split()
for _op in _ALL20:
    _mates = [m for m in ["saria", "exusiai", "lappland"] if m != _op][:2]
    CLIPS["u_" + _op] = (_op, ",".join(_mates), [])
# 20 人技能连携各一段（l_<干员>）：队长斯卡蒂（接的是斯卡蒂本人时队长换塞雷娅）+ 这一名队友，61.2 秒起队长每 3 秒放一次技能
_LINK = ["--bal=combo/skill_link=1", "--bal=ult/test_fill_at=-1", "--bal=ult/test_skill_at=61.2", "--bal=ult/test_skill_idx=0", "--bal=ult/test_skill_every=3"]
for _op in _ALL20:
    CLIPS["l_" + _op] = ("saria" if _op == "skadi" else "skadi", _op, _LINK, 60.6)
ap = argparse.ArgumentParser()
ap.add_argument("--clips", default=",".join(CLIPS)); ap.add_argument("--at", type=float, default=30.0); ap.add_argument("--secs", type=float, default=14.0)
ap.add_argument("--tag", default="now"); ap.add_argument("--jobs", type=int, default=3); ap.add_argument("--extra", default="")
ap.add_argument("--sfx", action="store_true", help="配声音：录屏时开 --sfxtrace，按记录离线混音效 + 语音 + 配乐（含终结技压低配乐的低通），合进 mp4（AAC）。测试局照旧静音")
a = ap.parse_args()
out = os.path.join(ROOT, "build", "ult_rec", a.tag); os.makedirs(out, exist_ok=True)
import imageio_ffmpeg
FF = imageio_ffmpeg.get_ffmpeg_exe()


SR = 44100
_dec = {}


def _decode(path):
    """任意音频文件 → 44.1k 单声道 float（ffmpeg 解码，缓存）；缺文件返回 None"""
    if path not in _dec:
        if not os.path.exists(path):
            _dec[path] = None
        else:
            r = subprocess.run([FF, "-loglevel", "error", "-i", path, "-f", "f32le", "-ac", "1", "-ar", str(SR), "-"], capture_output=True)
            _dec[path] = np.frombuffer(r.stdout, dtype=np.float32).astype(np.float64) if r.returncode == 0 else None
    return _dec[path]


def _res(p):
    return os.path.join(ROOT, "game", p[len("res://"):].replace("/", os.sep)) if p.startswith("res://") else p


def mix_audio(tr, mus, n_frames):
    """SFXTRACE（音效 / 语音事件）+ MUSTRACE（逐帧配乐采样）→ 单声道 44.1k。增益 = 播放器音量 + 所在总线音量。
    测试局把各总线压到 -80（静音），记录里的总线音量不能用：按玩家缺省设置算（settings.gd：配乐 0.8 / 音效 0.9 / 语音 0.8）"""
    buses = {"Music": 20 * np.log10(0.8), "SFX": 20 * np.log10(0.9), "Voice": 20 * np.log10(0.8)}
    n = int((n_frames / 30.0 + 0.5) * SR)
    fx = np.zeros(n)
    f0 = tr["frame0"]
    for fr, name, vol, pitch in tr["trace"]:
        if name.startswith("vduck:"):
            continue
        if name.startswith("voice:"):
            x, bus = _decode(os.path.join(ROOT, "game", "audio", "voice", name[6:] + ".ogg")), "Voice"
        else:
            x, bus = _decode(os.path.join(ROOT, "game", "audio", "sfx", name + ".wav")), "SFX"
        if x is None or len(x) < 2:
            continue
        idx = np.arange(0, len(x) - 1, float(pitch))
        y = np.interp(idx, np.arange(len(x)), x) * 10 ** ((float(vol) + float(buses.get(bus, 0.0))) / 20.0)
        at = int((fr - f0) / 30.0 * SR)
        if at < 0 or at >= n:
            continue
        j = min(n, at + len(y))
        fx[at:j] += y[: j - at]
    mu = np.zeros(n)
    cut = np.full(n, 20000.0)
    pos = {}
    step = SR // 30
    mg = 10 ** (float(buses.get("Music", 0.0)) / 20.0)
    for fr, hz, ents in mus.get("frames", []):
        at = int((fr - f0) / 30.0 * SR)
        if at < 0 or at >= n:
            continue
        cut[at:at + step] = float(hz)
        live = set()
        for path, vol, ppos in ents:
            x = _decode(_res(path))
            if x is None or len(x) < step:
                continue
            live.add(path)
            p0 = pos.get(path, int(float(ppos) * SR) % len(x))   # 第一次出现按播放位置起，之后每帧推进 1/30 秒（与录像钟 1:1）
            seg = np.take(x, np.arange(p0, p0 + step) % len(x))
            j = min(n, at + step)
            mu[at:j] += seg[: j - at] * 10 ** (float(vol) / 20.0) * mg
            pos[path] = (p0 + step) % len(x)
        for k in list(pos):
            if k not in live:
                del pos[k]
    # 配乐低通（Sfx.music_lp，终结技冲击帧压低）：一阶低通，截止频率逐帧取采样值
    a = 1.0 - np.exp(-2.0 * np.pi * np.minimum(cut, SR * 0.45) / SR)
    y = np.empty(n)
    z = 0.0
    mul, al = mu.tolist(), a.tolist()
    for i in range(n):
        z += al[i] * (mul[i] - z)
        y[i] = z
    out = fx + y
    pk = np.abs(out).max() if n else 0.0
    if pk > 0.89:
        out *= 0.89 / pk
    return out, len(mus.get("frames", [])) > 0 and np.abs(y).max() > 1e-4


def write_wav(path, y):
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((np.clip(y, -1, 1) * 32767).astype(np.int16).tobytes())


def one(name):
    op, squad, ex = CLIPS[name][:3]
    at = CLIPS[name][3] if len(CLIPS[name]) > 3 else a.at   # 连携段要 1:30 以后（敌人够密）
    fdir = os.path.join(out, "fr_" + name); shutil.rmtree(fdir, ignore_errors=True); os.makedirs(fdir)
    # 录像口径（10-29）：放终结技前 1.2 秒刷一团怪、之后每 6 秒一团（ult/test_swarm_*）
    args = [GR.find_godot(), "--path", os.path.join(ROOT, "game"), "--audio-driver", "Dummy", "--fixed-fps", "30", "--",
            "--balance", "--realtime", "--rtfrom=%g" % max(0.0, at - 3), "--nodeath", "--seed=3", "--op=" + op, "--squad=" + squad] + ([] if any(x.startswith("--bot=") for x in ex) else ["--bot=expert"]) + [
            "--maxprog", "--bal=ult/bot_n=1", "--bal=ult/test_swarm_at=%g" % (at + 0.3), "--bal=ult/test_swarm_every=6"] + ([] if any(x.startswith("--bal=ult/test_fill_at") for x in ex) else ["--bal=ult/test_fill_at=%g" % (at + 1.5)]) + ex + a.extra.split() + [
            "--recframes=%g,%d" % (at, int(a.secs * 30)), "--shotdir=" + fdir.replace(os.sep, "/"), "--maxt=%d" % (at + a.secs + 8)] + (["--sfxtrace"] if a.sfx else [])
    o, e, to = GR.run_godot([x for x in args if x], 1800)
    n = len(glob.glob(os.path.join(fdir, "rec_*.png")))
    mp4 = os.path.join(out, name + ".mp4")
    tr = mus = None
    for ln in o.splitlines():
        if ln.startswith("SFXTRACE "):
            tr = json.loads(ln[9:])
        elif ln.startswith("MUSTRACE "):
            mus = json.loads(ln[9:])
    snd = ""
    if a.sfx and tr is not None and n > 0:
        json.dump({"sfx": tr, "music": mus}, open(os.path.join(out, name + ".sound.json"), "w", encoding="utf-8"))   # 原始记录（排查声音对不上用）
        wav = os.path.join(fdir, "mix.wav")
        y, has_mus = mix_audio(tr, mus or {}, n)
        write_wav(wav, y)
        snd = "声音：音效 %d 次、语音 %d 句、配乐%s" % (sum(1 for e in tr["trace"] if not e[1].startswith(("voice:", "vduck:"))),
                                              sum(1 for e in tr["trace"] if e[1].startswith("voice:")), "有" if has_mus else "无")
        subprocess.run([FF, "-y", "-loglevel", "error", "-framerate", "30", "-i", os.path.join(fdir, "rec_%05d.png"), "-i", wav, "-vf", "scale=1280:-2",
                        "-c:v", "libx264", "-crf", "24", "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "160k", "-shortest", mp4])
    else:
        if a.sfx:
            snd = "声音：没拿到 SFXTRACE"
        subprocess.run([FF, "-y", "-loglevel", "error", "-framerate", "30", "-i", os.path.join(fdir, "rec_%05d.png"), "-vf", "scale=1280:-2", "-c:v", "libx264", "-crf", "24", "-pix_fmt", "yuv420p", mp4])
    shutil.rmtree(fdir, ignore_errors=True)
    ult = [ln for ln in o.splitlines() if ln.startswith("BALANCE ")]
    print(name, "frames", n, "(%.1f 秒)" % (n / 30.0), "errors", GR.script_errors(o, e)[:2], "timeout" if to else "", snd, flush=True)
    return mp4


with ThreadPoolExecutor(a.jobs) as ex:
    mp4s = list(ex.map(one, a.clips.split(",")))
lst = os.path.join(out, "list.txt")
with open(lst, "w", encoding="utf-8") as f:
    for m in mp4s:
        if os.path.exists(m):
            f.write("file '%s'\n" % m.replace("\\", "/"))
subprocess.run([FF, "-y", "-loglevel", "error", "-f", "concat", "-safe", "0", "-i", lst, "-c", "copy", os.path.join(out, "all.mp4")])
print("输出", out)
