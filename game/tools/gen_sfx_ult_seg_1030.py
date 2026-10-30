"""终结技专属音效·按招式分段（docs/205 §3.5，10-30 用户「音效按照每个人的终结技特色来做」）。
取代 gen_sfx_ult_1030.py 的 A / B / C 三套通用风格：每人一套，跟着他那一招的段落走——
sf（按 Q 超必杀暂停那一下）/ charge（按 Q 瞄准）/ cast（放出）/ impact（第一下掉血）+ 各段专属声（data/ult_audio.json 的 seg.<段名>.on / hit，
段名就是招式里伤害的 src，如德克萨斯「斩开」「剑雨」、星熊「格挡」「反震」）。时间按 d61028742 实录（docs/205 §3.5 表）。
全部程序合成或加工本仓库现有音效（工具函数同 gen_sfx_ult_1030.py），不含原作音频。

运行：python game/tools/gen_sfx_ult_seg_1030.py            → <主仓库>/build/ult_sfx/S/ult_<干员>_<槽>.wav
      python game/tools/gen_sfx_ult_seg_1030.py --apply    → 写进 game/audio/sfx/（并删掉不再用的旧槽文件）
      逐人精调（docs/205 §4）：--apply --only texas --reseed（只重写这一人，别人的文件不动）
响度：峰值 -1 dBFS；最响 100 ms RMS：impact -9、段开头（on）-11、蓄力 / 出手 -13、长持续声 -15、连击（*_hit）-16 dBFS。
"""
import argparse, glob, os, zlib
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
_src = open(os.path.join(HERE, "gen_sfx_ult_1030.py"), encoding="utf-8").read()
exec(_src[:_src.index("# ---------------------------------------------------------------- 20 人")])   # 工具函数 + write
exec(_src[_src.index("def rip("):_src.index("OPS = [")])   # rip / horn / heavy_chain
OUT = os.path.join(ROOT, "build", "ult_sfx", "S")


# ---------------------------------------------------------------- 录音素材（Sonniss GDC 2026 Game Audio Bundle，免版税可商用、不需署名；
## 原文件只放主仓库 build/sfx_lib/sonniss_gdc2026/extracted/（不进 git、不进包），这里写死文件名 + 截取段，重跑结果一样；登记见 docs/113 §9）
SONNISS = os.path.join(ROOT, "build", "sfx_lib", "sonniss_gdc2026", "extracted")
_LIB = {}


def lib(name, t0, dur, rate=1.0, gain=1.0, fin=0.004, fout=0.04):
    """截一段录音（转单声道 44.1 kHz）：name = 包目录/文件名，t0 / dur 秒；rate > 1 升调变短（重采样）"""
    from fractions import Fraction
    from scipy.signal import resample_poly
    import soundfile as sf
    if name not in _LIB:
        x, sr = sf.read(os.path.join(SONNISS, name), dtype="float64", always_2d=True)
        _LIB[name] = (x.mean(axis=1), sr)
    x, sr = _LIB[name]
    seg = x[int(t0 * sr):int((t0 + dur) * sr)]
    fr = Fraction(SR / (sr * rate)).limit_denominator(2000)
    y = resample_poly(seg, fr.numerator, fr.denominator)
    return fadeio(y / (np.abs(y).max() + 1e-9) * gain, fin, fout)


## Freesound CC0 录音（原文件为页面公开的 HQ 试听 mp3，放主仓库 build/sfx_src/freesound_sword/<编号>.mp3，不进 git；登记见 docs/113 §20）
FREESOUND = os.path.join(ROOT, "build", "sfx_src", "freesound_sword")


def fsd(sid, t0, dur, fout=0.08):
    """截一段 Freesound 录音（<编号>.mp3 解码成单声道 44.1 kHz），300 Hz 高通"""
    import soundfile as sf
    import subprocess as sp
    import imageio_ffmpeg
    wav = os.path.join(FREESOUND, "%d.wav" % sid)
    if not os.path.exists(wav):
        sp.run([imageio_ffmpeg.get_ffmpeg_exe(), "-v", "error", "-y", "-i", os.path.join(FREESOUND, "%d.mp3" % sid), "-ac", "1", "-ar", str(SR), wav], check=True)
    x, sr = sf.read(wav)
    y = x[max(0, int((t0 - 0.01) * sr)):int((t0 + dur) * sr)]
    return fadeio(hp(y, 300) / (np.abs(y).max() + 1e-9), 0.002, fout)


## 原作音效（用户 10-31 同意放进游戏）：明日方舟 CN 客户端热更新 26-10-22-14-02-11-51447808 的 audio/sound_beta_2/player/*.ab，
## ArknightsStudioCLI 导出到主仓库 build/ak_src/flat/、build/ak_exu_candidates/（不进 git；docs/113 §19 / §20）
def akd(name, t0=0.0, dur=None, rate=1.0, fout=0.05):
    from fractions import Fraction
    from scipy.signal import resample_poly
    import soundfile as sf
    p = os.path.join(ROOT, "build", "ak_src", "flat", name)
    if not os.path.exists(p):
        p = os.path.join(ROOT, "build", "ak_exu_candidates", name)
    x, sr = sf.read(p, always_2d=True)
    x = x.mean(axis=1)[int(t0 * sr):int((t0 + dur) * sr) if dur else None]
    fr = Fraction(SR / (sr * rate)).limit_denominator(2000)
    y = resample_poly(x, fr.numerator, fr.denominator)
    return fadeio(y / (np.abs(y).max() + 1e-9), 0.001, fout)


LV = {"mark": -13.0, "sword": -18.0, "shatter": -17.0, "cut": -11.0, "shot": -16.0, "pop": -17.0, "crack": -14.0, "pull": -16.0, "boom": -9.0, "sizzle": -17.0}   # 画面单元槽（docs/205 §4.2），按槽名前缀


def level(slot, x):
    if slot.split("_")[0] in LV:
        return LV[slot.split("_")[0]]
    if slot.endswith("_hit"):
        return -16.0
    if slot == "impact":
        return -9.0
    if slot == "sf":
        return -10.0
    if slot in ("charge", "cast"):
        return -15.0 if len(x) > 1.6 * SR else -13.0
    return -15.0 if len(x) > 1.6 * SR else -11.0


def tink(f=3200, dec=30.0):
    """细碎金属落点（剑雨一把剑）"""
    return pad(metal(0.16, f, dec, bright=0.55) * 0.6, hp(N(0.012), 3500) * env(0.012, 0.0002, 220) * 0.7)


def gun():
    return pad(ld("op_exusiai_atk") * 0.9, burst(0.08, 3000, 40) * 0.3)


def pop(cut=3000, f0=150):
    """小爆点"""
    return pad(burst(0.28, cut, 13), thud(0.22, f0, 50, 16) * 0.7)


def loopify(x, sec, fin=0.05, fout=0.3):
    y = fit(x, sec)
    return fadeio(y, fin, fout)


# ---------------------------------------------------------------- 20 人（段名 = 招式伤害 src）
TX_SLICE = "Epic Stock Media - Tower Defense Game/DSGNStngr_Action Deploy Units Sword Slice Special Move Layered Swish 04_ESM_TDG.wav"
TX_SCRAPE = "David Dumais Audio - Melee Weapons Sound Effects Pack 2/METLFric_SWING SCRAPE Swift Melee Weapon Swing With A Long Blade 14_DDUMAIS_MWP2.wav"
TX_HIT = "Cinematic Sound Design - Colossal Impacts/Impact Cut Sweep.wav"
TX_BOOM = "Federico Soler - Effective Trailer Booms Vol. 2/EffectiveTrailer_Booms_Vol2_214.wav"
TX_DRAW = [0.42, 8.17, 12.84, 16.96, 0.42, 8.17]   # Freesound 611310（IENBA「Dagger」）里 4 次拔匕首「shwing」的起点，6 道剑痕轮着用


def texas():
    """docs/205 §4.3：隐去（cast，长刃挥刮）→ 0.5 秒画 N 道发丝线，每道一声出鞘「shwing」mark_1..6（用户 10-31 在四版网上录音里选 ④：
    Freesound IENBA「Dagger」CC0，4 次拔匕首轮着用）→ 斩线齐出一声多层斩击 cut + 高潮爆开 impact（斩击冲击 + 预告片低频轰）。
    斩线碎裂、剑雨插地都不配声（用户 10-31：玻璃晶片难听、剑雨那串不要）"""
    marks = {"mark_%d" % (i + 1): fsd(611310, t0, 0.4) for i, t0 in enumerate(TX_DRAW)}
    d = {
        "charge": pad(sweep_noise(0.7, 1500, 6500, 0.3) * swell(0.7, 0.95) * 0.5, metal(0.7, 1760, 2.5, bright=0.4) * swell(0.7, 0.9) * 0.4),
        "cast": lib(TX_SCRAPE, 0.0, 0.6, rate=1.15, fout=0.15) * 0.8,
        "cut": lib(TX_SLICE, 0.29, 0.8, fout=0.3),   # 起点对到斩击最响处前一点（录音 0.42 s 峰值）
        "impact": pad(lib(TX_HIT, 0.93, 1.5, fout=0.5), lp(lib(TX_BOOM, 0.25, 1.6, fout=0.7), 900) * 0.8),
    }
    d.update(marks)
    return d


SN = {   # Sonniss 素材短名（docs/113 §20）
    "debris": "Cinematic Sound Design - Colossal Impacts/Woosh Debris.wav",
    "thud": "David Dumais Audio - Melee Weapons Sound Effects Pack 2/SWSH_SWING IMPACTS Quick Heavy Weapon Swing To Thud Impact Var 01_DDUMAIS_MWP2.wav",
    "ice": "Alexander Kopeikin - 100 kHz Designed Ice/ice, crack, ice block snapping-001.wav",
    "fissure": "Alexander Kopeikin - 100 kHz Designed Ice/ice, surface cracking, fissure, fast, hard-003.wav",
    "drag": "344 Audio - Extreme Winds Vol. 1/METLFric_Large Metal Box, Drag, Geofon_344 Audio_Extreme Winds Vol 1.wav",
    "cut": "Cinematic Sound Design - Colossal Impacts/Impact Cut Sweep.wav",
    "b214": "Federico Soler - Effective Trailer Booms Vol. 2/EffectiveTrailer_Booms_Vol2_214.wav",
    "b075": "Federico Soler - Effective Trailer Booms Vol. 2/EffectiveTrailer_Booms_Vol2_075.wav",
    "fire": "Ivo Vicic - Campfire - Bonfire FX/24 Campfire, Dropping Fresh Pine Branches in Fire, Crackling, Sizzling Strong, Close 02.wav",
    "bang": "344 Audio - Haunting Ambiences Vol. 3/METLImpt_Metal Bangs, Metal Hits, Banging On Doors_344 Audio_Haunting Ambiences Vol 3.wav",
    "elec": "Epic Stock Media - Elemental Mutation Whooshes and Impacts/ELECMisc_Impact Electric Tonal Deep Movement Motion Hiss Glitch 01_ESM_EMWI.wav",
    "flow": "Alexander Kopeikin - Emotion and Magic/magic, energy flow, astonishment-001.wav",
}


def sn(k, *a, **kw):
    return lib(SN[k], *a, **kw)


EX_BLAST = "Epic Stock Media - Anime Game/EXPLDsgn_Explosion Small Blast Enemy Death Crunchy Boom Cartoon Noisy Crash Impact Delay 03_ESM_AG.wav"


def exusiai():
    """docs/205 §4.3（用户 10-31 定）：按 Q 瞄准 = 原作手枪换弹上膛（charge，取代原先 9 声滴答）→ 放出 = 原作手枪拉栓一下（cast）
    → 每颗曳光弹出膛一枪 shot_1..4（fx circle r5）→ 每个爆点一声录音小爆炸 pop_1..3（fx strip burst，Sonniss「Explosion Small Blast」）
    → 第一下掉血 impact = 同一爆炸降调 + 低频轰"""
    shots = {"shot_%d" % (k + 1): pad(pitch(gun(), (1.0, 1.06, 0.95, 1.11)[k]) * 0.9, burst(0.05, 6000 + 900 * k, 60) * 0.25) for k in range(4)}
    pops = {"pop_%d" % (k + 1): lib(EX_BLAST, 0.02, 0.45, (0.97, 1.0, 1.04)[k], fout=0.15) for k in range(3)}
    d = {
        "charge": akd("p_atk_pistolup_sreload.wav", 0.0, 0.9, fout=0.06),
        "cast": akd("p_atk_pistolup_dreload.wav", 0.0, 0.3, fout=0.05),
        "impact": pad(lib(EX_BLAST, 0.02, 1.0, 0.85, fout=0.4), lp(lib(TX_BOOM, 0.25, 1.3, fout=0.6), 900) * 0.8),
    }
    d.update(shots)
    d.update(pops)
    return d


def skalter():
    """海嗣从身边升起、张口聚光（0.35 秒）→ 粗激光慢扫一整圈（约 3.4 秒，轻震）→ 扫过的地面连爆（深红，少而大）"""
    sw = 3.9
    t = T(sw)
    beam = (lp(N(sw), 900, 4) * 1.4 + drone(sw, 73, 0.6) * 0.45 + bp(tone(sw, 220, 196, "saw"), 150, 2500) * 0.18
            + bp(N(sw), 2200, 5500) * 0.1 * (0.7 + 0.3 * np.sin(2 * np.pi * 6 * t)))
    beam *= np.clip((t - 0.3) / 0.12, 0, 1) * np.clip((sw - t) / 0.4, 0, 1)
    ignite = at(pad(rev(burst(0.3, 3000, 8)) * 0.5, whisper(0.35, 500, 1500) * 0.3), 0.0)
    return {
        "charge": pad(drone(0.9, 49, 0.4) * swell(0.9, 0.9) * 0.8, whisper(0.9, 400, 1300) * swell(0.9, 0.8) * 0.45, lp(N(0.9), 300) * swell(0.9, 0.9) * 0.6),
        "cast": pad(ignite, beam),
        "impact": pad(burst(0.6, 2200, 7), sub(0.7, 75, 30, 4), splash(0.5, 2500, 7) * 0.4),
        "burst_hit": pad(burst(0.7, 1800, 6), sub(0.6, 70, 30, 5) * 0.9, splash(0.4, 2200, 8) * 0.35),
    }


def kaltsit():
    """docs/205 §4.3（用户 10-31 选「原作 Mon3tr 爆发音」）：按 Q = 电光定格 + 能量流（Sonniss）→ Mon3tr 跃出 = 碎石呼啸 cast
    → 落地 land（原作砸盾落地降调，fx strip melt）→ 蓄力收光每道一声能量聚集 gather_1..3（fx ring r24）
    → 第一圈熔毁 impact = 原作 p_skill_Mon3trburst 前段 + 预告片低频 → 第二 / 三圈 ring_hit = Mon3trburst 后段"""
    return {
        "sf": sn("elec", 0.0, 0.6), "charge": sn("flow", 0.0, 1.0, fout=0.2),
        "cast": sn("debris", 0.1, 0.9, fout=0.3), "land": akd("p_skill_shieldhitground.wav", 0.2, 0.9, 0.85, fout=0.3),
        **{"gather_%d" % (i + 1): sn("flow", 1.0 + 0.4 * i, 0.3, 1.0 + 0.08 * i, fout=0.1) for i in range(3)},
        "impact": pad(akd("p_skill_Mon3trburst.wav", 0.0, 1.25, fout=0.4), lp(sn("b075", 0.25, 1.4, fout=0.6), 900) * 0.6),
        "ring_hit": akd("p_skill_Mon3trburst.wav", 1.27, 0.9, fout=0.3),
    }


def ulpianus():
    """掷出巨锚（锁链放出）→ 沿锁链冲过去（路径上的敌人各吃一下）→ 落地，四圈裂地一圈圈炸起"""
    return {
        "charge": pad(heavy_chain(0.8, 8) * 0.6, drone(0.9, 41, 0.3) * swell(0.9, 0.9) * 0.7, rumble(0.9, 140, 1.0) * swell(0.9, 0.9) * 0.4),
        "cast": pad(sweep_noise(0.45, 300, 1600, 0.45) * swell(0.45, 0.6), heavy_chain(0.45, 14) * 0.9),
        "dash": pad(sweep_noise(0.25, 1800, 400, 0.5) * env(0.25, 0.003, 9), heavy_chain(0.25, 8) * 0.6),
        "impact": pad(thud(0.9, 75, 28, 4) * 1.2, crack(0.9, 4.0), metal(0.9, 170, 3.5, bright=0.5) * 0.35),
        "crack_hit": crack(0.45, 8),
    }


def skadi():
    """举巨剑向前下劈（冲击）→ 劈开处立起一道大浪，0.8 秒推过屏幕"""
    wave = lp(N(1.4), 2800, 3) * swell(1.4, 0.3) * 1.1 + splash(1.4, 4500, 2.2) * 0.45 + lp(N(1.4), 250, 3) * swell(1.4, 0.35) * 0.8
    return {
        "charge": pad(metal(0.8, 210, 2, bright=0.5) * swell(0.8, 0.9) * 0.4, sweep_noise(0.8, 250, 1000, 0.5) * swell(0.8, 0.9) * 0.5, lp(N(0.8), 350) * swell(0.8, 0.9) * 0.7),
        "cast": sweep_noise(0.16, 2500, 500, 0.5) * swell(0.16, 0.7),
        "impact": pad(thud(0.5, 110, 40, 9), burst(0.35, 2500, 11) * 0.7, metal(0.6, 260, 5, bright=0.5) * 0.35, sub(0.5, 85, 32, 6) * 0.7),
        "wave": wave,
        "wave_hit": splash(0.22, 4000, 15) * 0.8,
    }


def gladiia():
    """槊一指，漩涡越转越快把敌人拖向中心（约 0.6 秒）→ 收拢（冲击）→ 潮水从中心爆开"""
    vx = 0.75
    t = T(vx)
    swirl = bp(N(vx), 300, 2600) * (0.55 + 0.45 * np.sin(2 * np.pi * (3 + 12 * t / vx) * t)) * swell(vx, 0.95) + lp(N(vx), 260, 3) * swell(vx, 0.95) * 1.1
    return {
        "charge": pad(lp(N(0.8), 600) * swell(0.8, 0.9) * 0.7, whoosh(0.8, 200, 900) * 0.4, whisper(0.8, 600, 1800) * swell(0.8, 0.8) * 0.25),
        "cast": pad(sweep_noise(0.2, 2500, 600, 0.4) * env(0.2, 0.002, 10), metal(0.3, 520, 9, bright=0.45) * 0.3),
        "vortex": swirl,
        "impact": pad(thud(0.4, 120, 45, 9), splash(0.4, 3000, 9) * 0.7, sweep_noise(0.2, 400, 2400, 0.4) * env(0.2, 0.002, 10) * 0.5),
        "surge": pad(splash(1.0, 4500, 3.5) * 1.0, burst(0.6, 2200, 7) * 0.6, sub(0.8, 80, 30, 4)),
    }


def angelina():
    """落点出现黑紫奇点，0.8 秒把敌人吸起悬空（逐渐升高）→ 停顿 → 全部砸向地面（冲击）"""
    sing = 0.85
    t = T(sing)
    lift = pad(tone(sing, 90, 520, "tri") * swell(sing, 0.92) * 0.45, np.sin(2 * np.pi * 60 * t + 4 * np.sin(2 * np.pi * 2.5 * t)) * swell(sing, 0.9) * 0.5,
               suck(sing, 200, 3000) * 0.4, bell(sing, 1047, 1.5, 1.0, 0.4) * swell(sing, 0.9) * 0.18)
    return {
        "charge": pad(drone(0.9, 49, 0.4) * swell(0.9, 0.9) * 0.6, bell(0.9, 784, 2, 1.0, 0.3) * swell(0.9, 0.9) * 0.25),
        "cast": pad(bell(0.4, 1319, 8, 1.0, 0.3) * 0.4, rev(burst(0.3, 3000, 8)) * 0.4),
        "singularity": lift,
        "impact": pad(thud(0.9, 85, 28, 4.5) * 1.3, crack(0.9, 4.5) * 0.9, burst(0.4, 2000, 9) * 0.5),
        "slam_hit": thud(0.25, 140, 55, 16) * 0.8,
    }


def eyjafjalla():
    """落点龟裂 0.4 秒 → 巨大火柱喷出（冲击）→ 熔岩块落满一圈（每块一声）→ 中间留熔岩地面"""
    return {
        "charge": pad(rumble(0.9, 160, 0.6) * swell(0.9, 0.9), crackle(0.9, 120, 900, 4000, 1.0) * swell(0.9, 0.9) * 0.5),
        "cast": pad(crack(0.45, 7) * 0.8, lp(N(0.45), 1300) * swell(0.45, 0.95) * 0.6),
        "impact": pad(sweep_noise(1.2, 400, 2400, 0.7) * env(1.2, 0.003, 2.8) * 1.0, burst(0.8, 2200, 5), sub(0.9, 70, 28, 3.5), crackle(1.2, 320, 1300, 6000, 3) * 0.55),
        "lava_hit": pad(thud(0.28, 120, 45, 14) * 0.8, crackle(0.25, 220, 1500, 5000, 13) * 0.5, splash(0.2, 1800, 16) * 0.3),
        "ground": pad(crackle(1.2, 160, 1200, 5000, 2.0) * 0.6, lp(N(1.2), 600) * env(1.2, 0.05, 2.0) * 0.7),
    }


def wisadel():
    """架炮后仰（装填两声）→ 向前一排排地毯式炮击，由近到远推进（每排一声）→ 余震"""
    def clk(f):
        return pad(metal(0.12, f, 35, bright=0.5) * 0.6, hp(N(0.02), 2000) * env(0.02, 0.0003, 120))
    return {
        "charge": pad(clk(700), at(clk(980), 0.2), at(clk(1250), 0.4), at(metal(0.4, 160, 6, bright=0.5) * 0.5, 0.5), tone(0.9, 45, 72) * swell(0.9, 0.8) * 0.5),
        "cast": pad(thud(0.3, 150, 45, 12), burst(0.3, 2600, 14) * 0.8, hp(N(0.04), 2000) * env(0.04, 0.0005, 70) * 0.6),
        "impact": pad(burst(0.8, 2500, 5.5), sub(0.8, 85, 28, 4), rumble(0.8, 160, 3.5) * 0.7),
        "shell_hit": pad(burst(0.45, 2800, 8) * 0.9, thud(0.35, 115, 40, 10) * 0.8, at(rumble(0.5, 140, 5) * 0.5, 0.3)),
    }


def specter_unchained():
    """举起巨锯，锯刃放大绕着她转 3 秒（cast 带整段锯声）→ 第一下切进去（冲击）→ 之后每圈切到一声"""
    dur = 3.4
    t = T(dur)
    saw = lp(tone(dur, 118, 132, "saw"), 1700) * (0.65 + 0.35 * np.sin(2 * np.pi * 4 * t)) * 0.55 + bp(N(dur), 1500, 5000) * (0.4 + 0.6 * np.sin(2 * np.pi * 4 * t) ** 2) * 0.3
    return {
        "charge": pad(tone(0.8, 40, 120, "saw") * swell(0.8, 0.9) * 0.35, metal(0.5, 300, 6, bright=0.5) * 0.35, lp(N(0.8), 800) * swell(0.8, 0.9) * 0.5),
        "cast": saw * np.clip(t / 0.1, 0, 1) * np.clip((dur - t) / 0.3, 0, 1),
        "impact": pad(rip(0.35, 5200, 900), metal(0.7, 230, 4, bright=0.55) * 0.5, sub(0.5, 95, 35, 6) * 0.7),
        "saw_hit": pad(rip(0.13, 4800, 1500) * 0.7, metal(0.15, 880, 25, bright=0.5) * 0.25),
    }


def mizuki():
    """地下蠕动 → 巨型触手破土横扫半圆（冲击）→ 小触手从地下钻出抓住漏网"""
    return {
        "charge": pad(lp(N(0.9), 300, 3) * swell(0.9, 0.9) * 1.1, whisper(0.9, 400, 1200) * swell(0.9, 0.8) * 0.35, splash(0.9, 1500, 1.5) * swell(0.9, 0.9) * 0.35),
        "cast": pad(crack(0.35, 8) * 0.8, sweep_noise(0.35, 200, 900, 0.5) * swell(0.35, 0.6) * 0.7),
        "impact": pad(sweep_noise(0.55, 2600, 280, 0.5) * env(0.55, 0.002, 5.5), sub(0.6, 80, 30, 5), splash(0.5, 2400, 7) * 0.7),
        "tendril": pad(seq([(i * 0.06, pad(splash(0.18, 2000, 18) * 0.7, thud(0.14, 170, 70, 25) * 0.5)) for i in range(3)]), crack(0.3, 10) * 0.4),
    }


def saria():
    """举拳蓄力 0.2 秒 → 一拳砸地、拳风冲击环扩开（冲击）→ 十道琥珀裂纹一节节长出、爆点依次炸开"""
    cracks = seq([(i * 0.055, pad(bell(0.18, 1319 + 90 * (i % 4), 18, 3.5, 1.8) * 0.3, crackle(0.15, 300, 2000, 7000, 18) * 0.5, thud(0.12, 160, 70, 25) * 0.4)) for i in range(10)])
    return {
        "charge": pad(lp(N(0.7), 500) * swell(0.7, 0.95) * 0.8, bell(0.7, 988, 2, 3.5, 1.5) * swell(0.7, 0.9) * 0.2),
        "cast": pad(whoosh(0.2, 600, 2000), thud(0.15, 120, 60, 18) * 0.4),
        "impact": pad(thud(0.9, 75, 28, 4) * 1.3, crack(0.9, 4.5), burst(0.35, 2200, 11) * 0.6, bell(0.8, 659, 4, 3.5, 2.0) * 0.18),
        "amber": cracks,
    }


def suzuran():
    """忍冬出现在铃兰身边 → 化作白光瞬身飞出、留下一道斩痕（定住）→ 停半拍 → 斩痕炸开（冲击）"""
    return {
        "charge": pad(bell(0.8, 1760, 2.5, 1.0, 0.3) * swell(0.8, 0.9) * 0.35, whisper(0.8, 1500, 4500) * swell(0.8, 0.9) * 0.35, suck(0.7, 1500, 7000) * 0.3),
        "cast": pad(metal(0.4, 2200, 7, bright=0.45) * 0.35, sweep_noise(0.12, 3000, 6000, 0.3) * env(0.12, 0.002, 18) * 0.5),
        "flash": pad(sweep_noise(0.3, 8000, 1800, 0.3) * env(0.3, 0.002, 9), bell(0.4, 2349, 8, 2.0, 1.0) * 0.25, at(metal(0.35, 1900, 6, bright=0.4) * 0.15, 0.25)),
        "impact": pad(seq([(0, slash(0.3, 6500, 900)), (0.03, slash(0.3, 5000, 800) * 0.7)]), burst(0.6, 3500, 7) * 0.8, sub(0.6, 105, 40, 6) * 0.8),
    }


def logos():
    """铺开长方形咒域、敌人头上浮现咒文（0.5 秒，咒文一个个亮起）→ 念出一词，标记同时爆裂（冲击）"""
    return {
        "charge": pad(whisper(0.9, 450, 1500) * swell(0.9, 0.85) * 0.8, drone(0.9, 62, 0.3) * swell(0.9, 0.9) * 0.5),
        "cast": pad(seq([(i * 0.055, bell(0.25, 392 * (1.0595 ** (i * 2)), 10, 2.0, 1.5) * 0.25) for i in range(9)]), lp(N(0.55), 900) * swell(0.55, 0.95) * 0.45),
        "impact": pad(burst(0.7, 2500, 6), sub(0.7, 70, 28, 4), chord(0.9, [73, 78, 110], "saw") * env(0.9, 0.002, 3.5) * 0.4, rev(burst(0.12, 3000, 20)) * 0.3),
    }


def hoshiguma():
    """docs/205 §4.3（用户 10-31 选录音版 ② 再「低频一点」：整体降调 ×0.8、5 kHz 以上压掉、低频轰加厚）：
    按 Q = 金属重击 sf + 金属箱拖拽 charge → 盾砸地 cast（重击 + 低频轰）+ 吸怪碎石呼啸 pull（fx line+v）
    → 挡的期间金属吃力 block（seg 格挡 on）+ 每圈新裂纹一声冰裂 crack_1..5（fx line w3，逐圈略升）
    → 盾甲炸开 boom（fx blade+v，高潮：斩击冲击 + 预告片低频轰 + 地裂）→ 热砂 sizzle（篝火噼啪，fx dots）"""
    R = 0.8
    return {
        "sf": lp(sn("bang", 0.0, 0.7, R), 5000), "charge": lp(sn("drag", 0.5, 1.0, R, fout=0.2), 5000),
        "cast": pad(lp(sn("thud", 0.2, 1.0, R, fout=0.3), 5000), lp(sn("b214", 0.25, 1.1, fout=0.4), 700) * 0.9),
        "pull": lp(sn("debris", 0.1, 0.9, R, fout=0.3), 5000),
        "block": lp(sn("drag", 1.5, 1.6, R, fout=0.3), 4000),
        **{"crack_%d" % (i + 1): pad(lp(sn("ice", 0.0, 0.45, R * (1.0 + 0.04 * i)), 5000), lp(sn("thud", 0.38, 0.35, R, fout=0.2), 1500) * 0.4) for i in range(5)},
        "boom": pad(lp(sn("cut", 0.93, 1.4, R, fout=0.5), 5000), lp(sn("b214", 0.25, 1.6, fout=0.6), 900) * 1.1,
                    lp(sn("fissure", 0.0, 0.9, 0.7, fout=0.3), 4000) * 0.5),
        "sizzle": lp(sn("fire", 2.0, 0.6, fout=0.2), 7000),
    }


def siege():
    """高高跃起（风声上扬 0.6 秒）→ 巨锤砸地、冲击波横扫（冲击）→ 敌人被震上半空，落地一片"""
    return {
        "charge": pad(lp(N(0.8), 600) * swell(0.8, 0.9) * 0.6, metal(0.4, 300, 6, bright=0.5) * 0.3, horn(0.2, 220) * 0.15),
        "cast": sweep_noise(0.62, 350, 2600, 0.5) * swell(0.62, 0.9),
        "impact": pad(thud(0.9, 70, 26, 4) * 1.3, metal(1.0, 210, 3, bright=0.6) * 0.45, crack(1.0, 4) * 0.8, burst(0.4, 2000, 10) * 0.5),
        "land": seq([(i * 0.07, thud(0.2, 130 - 10 * i, 50, 18) * 0.6) for i in range(5)] + [(0, crackle(0.5, 200, 1200, 5000, 6) * 0.6)]),
    }


def irene():
    """前方卷起狂风（敌人浮空）→ 冲进风里连斩 5–6 刀（每刀一声）→ 瞬身回原地 → 手炮一枪在风眼炸开"""
    return {
        "charge": pad(whoosh(0.9, 300, 1500) * 0.7, bell(0.9, 1175, 2, 1.0, 0.3) * swell(0.9, 0.9) * 0.2, lp(N(0.9), 500) * swell(0.9, 0.9) * 0.5),
        "cast": sweep_noise(0.15, 1500, 4000, 0.5) * swell(0.15, 0.6) * 0.6,
        "gale": pad(sweep_noise(0.9, 400, 2400, 0.6) * env(0.9, 0.01, 3.0), lp(N(0.9), 500) * env(0.9, 0.01, 3) * 0.8),
        "impact": pad(slash(0.2, 6500, 1800), metal(0.4, 1500, 9, bright=0.45) * 0.3),
        "slash_hit": slash(0.14, 6200, 1900) * 0.8,
        "cannon": pad(thud(0.18, 170, 60, 20) * 0.6, at(pad(burst(0.8, 2800, 6), sub(0.8, 85, 30, 4)), 0.03)),
    }


def lappland():
    """原地狂舞连斩，四圈双刃剑气向四面飞出（0.25 秒一圈，每圈一声交叉的风切）"""
    def x(i):
        return pad(sweep_noise(0.28, 5200, 900, 0.4) * env(0.28, 0.003, 9), at(sweep_noise(0.26, 4800, 800, 0.4) * env(0.26, 0.003, 9) * 0.7, 0.04), metal(0.3, 1700 + 140 * i, 10, bright=0.45) * 0.25)
    return {
        "charge": pad(seq([(i * 0.14, slash(0.14, 4200, 1500) * 0.35) for i in range(6)]), whisper(0.8, 800, 2400) * swell(0.8, 0.9) * 0.25),
        "cast": slash(0.16, 5000, 1500) * 0.6,
        "impact": pad(x(0), sub(0.35, 110, 45, 9) * 0.5),
        "wave_hit": x(2),
    }


def lumen():
    """队长脚下升起灯塔光柱（光圈扩散灼烧，冲击）→ 光柱持续 2 秒（嗡鸣）→ 光雨落下 → 熄灭"""
    col = 1.8
    t = T(col)
    hum = (chord(col, [262, 392, 523], "tri") * 0.4 + drone(col, 131, 1.2) * 0.3 + bp(N(col), 1500, 5000) * 0.08) * np.clip(t / 0.15, 0, 1) * np.clip((col - t) / 0.5, 0, 1)
    return {
        "charge": pad(bell(0.9, 523, 2, 1.0, 0.3) * swell(0.9, 0.9) * 0.4, riser(0.9, 130, 520, "tri", 2500) * 0.45),
        "cast": pad(sweep_noise(0.3, 500, 3500, 0.5) * swell(0.3, 0.9) * 0.6, bell(0.5, 1047, 4, 1.0, 0.4) * 0.3),
        "impact": pad(sweep_noise(0.7, 600, 4200, 0.6) * env(0.7, 0.002, 5), sub(0.6, 95, 35, 6) * 0.7, bell(1.0, 392, 3, 1.0, 0.5) * 0.4),
        "column": hum,
        "rain_hit": pad(bell(0.18, 2093, 22, 1.0, 0.3) * 0.35, bp(N(0.12), 2500, 7000) * env(0.12, 0.002, 25) * 0.4),
    }


# ---------------------------------------------------------------- 超必杀暂停起手音 sf（claude/ult-superflash ae79de511 的 sf_sound 挂点）
## 按 Q 世界冻结 0.35 秒那一下：共用一个「定格」的瞬态（短促高频爆裂 + 低沉一顿），上面叠各人身份的一声，0.6 秒内收掉，
## 后面紧接 charge（瞄准蓄力），所以不做上扬。
def _sf_core(f0=170, bright=1.0):
    return pad(hp(burst(0.06, 11000, 70), 2500) * 0.45 * bright, thud(0.3, f0, 55, 13) * 0.7, sub(0.35, 80, 40, 9) * 0.45)


FLASH = {
    "texas": lambda: pad(_sf_core(), slash(0.2, 8000, 2200) * 0.6, metal(0.55, 2350, 7, bright=0.5) * 0.4),          # 拔剑一声「锵」
    "exusiai": lambda: pad(_sf_core(), metal(0.08, 1100, 40, bright=0.5) * 0.7, at(metal(0.08, 1500, 40, bright=0.5) * 0.6, 0.06), at(bell(0.4, 3520, 10, 1.0, 0.2) * 0.3, 0.1)),   # 上膛 + 光环叮
    "skalter": lambda: pad(_sf_core(120, 0.6), bell(0.6, 523, 5, 1.41, 1.2) * 0.35, lp(drone(0.6, 65, 0.8), 400) * fadeio(np.ones(int(0.6 * SR)), 0.01, 0.3) * 0.4),   # 海潮深处的低鸣
    "kaltsit": lambda: pad(_sf_core(150), zap(0.3, 1800, 600) * 0.3, bell(0.5, 880, 8, 2.0, 0.8) * 0.3),              # 冷光电鸣（Mon3tr）
    "ulpianus": lambda: pad(_sf_core(110), heavy_chain(0.35, 5, 420, 900, 30) * 0.5, sub(0.5, 55, 30, 5) * 0.4),       # 锁链一绷
    "skadi": lambda: pad(_sf_core(140), metal(0.5, 980, 6, bright=0.45) * 0.45, lp(splash(0.4, 3000, 9), 3000) * 0.35),   # 巨剑出鞘 + 浪声
    "gladiia": lambda: pad(_sf_core(130), whoosh(0.35, 400, 1600, 0.6) * 0.35, metal(0.45, 1320, 7, bright=0.4) * 0.35),   # 长枪破空
    "angelina": lambda: pad(_sf_core(160, 0.7), bell(0.55, 1568, 6, 1.5, 1.0) * 0.35, rev(fit(bell(0.3, 784, 8, 1.5, 0.8), 0.3)) * 0.2),   # 重力反转的颤鸣
    "eyjafjalla": lambda: pad(_sf_core(150), lp(crackle(0.45, 120, 1200, 6000, 7), 7000) * 0.5, rumble(0.45, 260, 6) * 0.4),   # 火山噼啪
    "wisadel": lambda: pad(_sf_core(130), metal(0.1, 700, 30, bright=0.5) * 0.7, at(thud(0.15, 260, 90, 24) * 0.5, 0.05), bell(0.4, 1046, 9, 3.0, 1.5) * 0.25),   # 炮膛合上
    "specter_unchained": lambda: pad(_sf_core(140), fit(rip(0.4, 160, 260), 0.4) * 0.3, metal(0.45, 760, 6, bright=0.5) * 0.4),   # 链锯一拉
    "mizuki": lambda: pad(_sf_core(150, 0.7), rev(fit(splash(0.3, 4000, 8), 0.3)) * 0.3, bell(0.5, 659, 6, 1.41, 1.5) * 0.3),   # 水泡倒吸 + 幽鸣
    "saria": lambda: pad(_sf_core(130), crack(0.3, 14) * 0.4, ring(0.5, 740, 6, 0.4) * 0.35),                          # 琥珀结晶
    "suzuran": lambda: pad(_sf_core(170, 0.8), bell(0.5, 1760, 7, 1.0, 0.3) * 0.35, at(bell(0.4, 2349, 9, 1.0, 0.3) * 0.25, 0.07)),   # 铃音
    "logos": lambda: pad(_sf_core(140), bell(0.6, 440, 5, 1.0, 0.4) * 0.3, bell(0.6, 659, 5, 1.0, 0.4) * 0.25, hp(sweep_noise(0.3, 5000, 1500, 0.4), 1200) * env(0.3, 0.002, 12) * 0.25),   # 咒文低吟的和音
    "hoshiguma": lambda: pad(_sf_core(110), metal(0.5, 520, 7, bright=0.35) * 0.55, thud(0.25, 140, 50, 12) * 0.5),    # 大盾一顿
    "siege": lambda: pad(_sf_core(110), thud(0.3, 120, 45, 10) * 0.7, metal(0.4, 640, 9, bright=0.4) * 0.35),          # 战锤上肩
    "irene": lambda: pad(_sf_core(160), slash(0.18, 7000, 2500) * 0.55, metal(0.5, 1975, 8, bright=0.5) * 0.35, whoosh(0.3, 700, 2200, 0.5) * 0.2),   # 细剑出鞘 + 风
    "lappland": lambda: pad(_sf_core(150), slash(0.2, 6000, 1800) * 0.5, at(slash(0.2, 7000, 2000) * 0.4, 0.08), metal(0.45, 1480, 8, bright=0.5) * 0.3),   # 双剑交错
    "lumen": lambda: pad(_sf_core(170, 0.7), bell(0.55, 1318, 6, 1.0, 0.25) * 0.35, bell(0.55, 1975, 7, 1.0, 0.25) * 0.25),   # 灯火一亮
}


OPS = [texas, exusiai, skalter, kaltsit, ulpianus, skadi, gladiia, angelina, eyjafjalla, wisadel, specter_unchained, mizuki,
       saria, suzuran, logos, hoshiguma, siege, irene, lappland, lumen]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true")
    ap.add_argument("--only", default="")
    ap.add_argument("--reseed", action="store_true", help="每人用自己的随机序列（逐人精调时配 --only 用）")
    a = ap.parse_args()
    only = set(a.only.split(",")) if a.only else None
    dst_dir = SFX if a.apply else OUT
    os.makedirs(dst_dir, exist_ok=True)
    for f in OPS:
        op = f.__name__
        if only and op not in only:
            continue
        if a.reseed:   # 每人独立随机序列（docs/205 §4 起逐人精调用；改一人不牵动别人）。没加 --reseed 时沿用旧的全程一条序列
            rng.bit_generator.state = np.random.default_rng(zlib.crc32(op.encode())).bit_generator.state
        d = f()
        st = rng.bit_generator.state   # sf 不占随机序列：其余槽与加 sf 之前逐字节相同
        if "sf" not in d:   # 干员函数自己给了录音版 sf 就不用合成的
            d["sf"] = FLASH[op]()
        rng.bit_generator.state = st
        if a.apply:   # 旧的通用槽（A/B/C 时代的 hit 等）不再用的删掉
            for old in glob.glob(os.path.join(SFX, "ult_%s_*.wav" % op)):
                if os.path.basename(old)[len("ult_%s_" % op):-4] not in d:
                    os.remove(old)
                    if os.path.exists(old + ".import"):
                        os.remove(old + ".import")
        info = []
        for slot, x in d.items():
            RMS[slot] = level(slot, np.asarray(x))
            info.append("%s %.2f" % (slot, write(os.path.join(dst_dir, "ult_%s_%s.wav" % (op, slot)), np.asarray(x, dtype=np.float64), slot)))
        print(op, " / ".join(info))


if __name__ == "__main__":
    main()
