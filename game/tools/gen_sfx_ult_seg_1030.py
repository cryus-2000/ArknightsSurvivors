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


LV = {"mark": -13.0, "sword": -18.0, "shatter": -17.0, "cut": -11.0, "shot": -16.0, "pop": -17.0, "crack": -14.0, "pull": -16.0, "boom": -9.0, "slam": -9.0, "surge": -9.0, "final": -9.0, "burst": -9.0, "slam_1": -9.0, "smash": -8.0, "sizzle": -17.0, "bomb": -18.0, "steam": -17.0, "crash": -9.0, "final": -9.0, "rupt": -10.0, "glyph": -19.0, "slash": -16.0, "seal": -12.0, "air": -13.0, "wave": -13.0, "smash2": -12.0, "rock": -16.0, "zip": -15.0, "warn": -13.0}   # 画面单元槽（docs/205 §4.2），按槽名前缀


LV_SLOT = {"boom_1": -15.0, "boom_hit": -15.0}
LV_OP = {("logos", "cast"): -12.0, ("logos", "charge"): -9.0}   # 逻各斯时停（docs/205 §4.10）；起手秒针要压过同时开口的台词（11-01 第六轮）   # 艾丽妮连环爆（11-01 夜定稿时的响度）；星熊 boom 是高潮，走 LV 的 -9


def level(slot, x):
    if slot in LV_SLOT:
        return LV_SLOT[slot]
    if slot in LV:
        return LV[slot]
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
    "rattle": "344 Audio - Elemental Palette Designed Vol. 1/METLMisc_Metal, Slow Whoosh, Rattle, Pass By x4 01_344 Audio_Elemental Palette Designed Vol 1.wav",
    "ring": "David Dumais Audio - Melee Weapons Sound Effects Pack 2/METLImpt_METAL SWING HIT Weapon Swing To Metallic Body Impact And Resonant Tail 01_DDUMAIS_MWP2.wav",
    "sub": "Epic Stock Media - Elemental Mutation Whooshes and Impacts/WATRImpt_Impact Water Deep Submerge Bubble Drown Ship Hit 05_ESM_EMWI.wav",
    "liq": "344 Audio - Elemental Palette Designed Vol. 1/WATRMisc_Water, Liquid Impact, Bubble, Sci Fi, Hit 04_344 Audio_Elemental Palette Designed Vol 1.wav",
    "astral": "Alexander Kopeikin - Emotion and Magic/magic, energy flow, astral travel-015.wav",
    "jump": "344 Audio - Bass Drops & Downers Vol. 3/DSGNBass_Jump Start Drop 3_344 Audio_Bass Drops and Downers Vol 3.wav",
    "drop": "344 Audio - Bass Drops & Downers Vol. 1/DSGNBass_Bass Drop & Downer Fast 16_344 Audio_Bass Drops & Downers.wav",
    "sweep": "Cinematic Sound Design - Ultra Transitions & Impacts/Woosh Sweep Slide Infographics Basic.wav",
    "b011": "Federico Soler - Effective Trailer Booms Vol. 2/EffectiveTrailer_Booms_Vol2_011.wav",
    "scrape": "David Dumais Audio - Melee Weapons Sound Effects Pack 2/METLFric_SWING SCRAPE Swift Melee Weapon Swing With A Long Blade 14_DDUMAIS_MWP2.wav",
    "slice": "Epic Stock Media - Tower Defense Game/DSGNStngr_Action Deploy Units Sword Slice Special Move Layered Swish 04_ESM_TDG.wav",
    "blast": "Epic Stock Media - Anime Game/EXPLDsgn_Explosion Small Blast Enemy Death Crunchy Boom Cartoon Noisy Crash Impact Delay 03_ESM_AG.wav",
    "fwhsh": "Epic Stock Media - Elemental Mutation Whooshes and Impacts/FIREWhsh_Whoosh Fire Deep Growl Monster Saturated Crisp 03_ESM_EMWI.wav",
    "thunder": "Epic Stock Media - Public Spaces - Storms Lakes Parks and Rural Nature Exteriors/STORM_Texas Rain Thunder Initial Crash Boom Storm 01 Clap Lightning_ESM_CPS.wav",
    "rumbleT": "Jake Fielding - Interior Wind Rain and Storms/THUN_Interior Thunder Rumble_JF_INT Storm_01.wav",
    "steam": "Ivo Vicic - Campfire - Bonfire FX/42 Campfire, Putting Out Fire, Water from Bottle, Variation, Close.wav",
    "cauldron": "344 Audio - Haunting Ambiences Vol. 5/FIRECrkl_Fire Crackling, Popping, Witch's Cauldron_344 Audio_Haunting Ambiences Vol 5.wav",
    "fworks": "Ivo Vicic - Fireworks FX/13 Fireworks_powerful explosions_multiples in a row_near.wav",
    "waves": "Just Sound Effects - Rocky Coast of Norway/WATRWave_Medium Waves at Pebble Beach_JSE_RCoN_Stereo.wav",
    "whip": "David Dumais Audio - Melee Weapons Sound Effects Pack 2/WEAPWhip_WHIP Snap Crack 05_DDUMAIS_MWP2.wav",
    "drone": "Alexander Kopeikin - Emotion and Magic/magic, drone, tension, spellbound, evanescence-002.wav",
    "onslaught": "Alexander Kopeikin - Emotion and Magic/magic, action gesture, evil presence, onslaught-004.wav",
    "braam": "Jake Fielding - Cinematic Horn Braams/DSGNBram____Cinematic Horn Braam, Epic, Cinematic, Dark, Instrument, Huge-32.wav",
    "tbraam": "Cinematic Sound Design - Ultra Transitions & Impacts/Transition Braam Slow Dark Creepy.wav",
    "clock": "344 Audio - Antique Clocks/CLOCKTick_Crooked Antique Clock_344 Audio_Antique Clocks.wav",
    "indamb": "Cinematic Sound Design - Sci-Fi Drones/Dark Industrial Ambience.wav",
    "wind": "344 Audio - Elemental Palette Designed Vol. 1/WINDDsgn_Wind, Rush, Whoosh, Long x5 01_344 Audio_Elemental Palette Designed Vol 1.wav",
    "smash": "Epic Stock Media - Halloween Game - Haunted House and Horror Audio Scare Kit/GORESplt_Gore Designed Transient Heavy Impact Smash 01_ESM_HALG.wav",
}


def gm(n, t0=0.0, dur=None, fout=0.05):
    """游戏里已有的录音音效（audio/sfx/<n>.wav，如乌尔比安技能的 CC0 锁链）"""
    import soundfile as sf
    x, sr = sf.read(os.path.join(SFX, n + ".wav"))
    x = x if x.ndim == 1 else x.mean(axis=1)
    return fadeio(x[int(t0 * sr):int((t0 + dur) * sr) if dur else None] / (np.abs(x).max() + 1e-9), 0.002, fout)


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
    """docs/205 §4.4（用户 10-31 选 ① 原作）：提示 = 原作召潮降调 → 海嗣升起（strip seaborn_front）= 原作召潮
    → 激光扫一圈 cast（3.9 秒）= 原作电场低鸣降调低通 → 沿途爆裂（strip fx_sk_blast）= 原作灵魂爆裂 3 个音高
    → 收尾大爆（strip fx_sk_flash，min_sc 1.5，高潮）= 原作陨石 + 黑洞 + 低频；第一下掉血不另响（没有 impact）"""
    return {
        "sf": akd("p_skill_seasummon.wav", 0.0, 0.5, 0.8, fout=0.25), "cast": lp(akd("p_field_elefield_loop.wav", 5.0, 3.9, 0.7, fout=0.8), 3000),
        "rise": akd("p_skill_seasummon.wav", 0.0, 1.3, 0.85, fout=0.5),
        **{"blast_%d" % (i + 1): akd("p_skill_spiritexplo.wav", 0.02, 0.9, r, fout=0.35) for i, r in enumerate([0.8, 0.85, 0.9])},
        "final": pad(akd("p_skill_aeroliteexplo.wav", 0.0, 1.5, 0.8, fout=0.6), akd("p_skill_darkholeboost.wav", 0.0, 1.2, fout=0.5) * 0.6, lp(sn("b214", 0.25, 1.6, fout=0.6), 900)),
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
    """docs/205 §4.3（用户 10-31 选录音版 ②）：按 Q = 金属重击定格 + 锁链掠过（轻）→ 掷锚 cast = 游戏里乌尔比安技能的 CC0 锁链
    → 锚扎地 anchor（金属刃撞击降调，fx ring r90 w5）→ 沿链冲过去 dash（锁链掠过，seg 锁链 on）
    → 第一圈裂地 impact = 深水冲击 + 预告片低频 → 后三圈 crack_hit（地裂降调）+ 每圈水柱一声液体冲击 splash_1..3（fx strip burst）"""
    return {
        "sf": lp(sn("ring", 0.38, 0.6, 0.6, fout=0.25), 4000), "charge": sn("rattle", 0.0, 1.0, 0.85, fout=0.3),
        "cast": gm("op_ulpianus_s1", fout=0.2), "anchor": lp(sn("ring", 0.38, 0.8, 0.7, fout=0.3), 5000),
        "dash": sn("rattle", 0.0, 0.9, fout=0.3),
        "impact": pad(sn("sub", 0.0, 1.4, fout=0.5), lp(sn("b214", 0.25, 1.4, fout=0.6), 900) * 0.8),
        "crack_hit": lp(sn("fissure", 0.0, 0.6, 0.8, fout=0.2), 5000),
        **{"splash_%d" % (i + 1): sn("liq", 0.0, 0.6, r, fout=0.2) for i, r in enumerate([0.9, 1.0, 1.1])},
    }


def skadi():
    """docs/205 §4.7（用户 11-01「斯卡蒂的也是」——音效和画面再做一轮；11-01 夜的 ①〔海浪拍岸 / 深水冲击〕作废）：
    11-01 选定 ① 原作：提示 = 原作沉默之剑连斩起头 → 下劈 cast / impact（次级）= 原作沉默之剑重斩 + 液体冲击 → 立浪往前滚 wave = 原作潮涌（浪涌最满那段）
    → 劈浪 crash（hf_slot，全招最响）= 原作大水炮 + 原作盾斧砸地爆裂 + 深水冲击（70 Hz 以下切）"""
    return {
        "sf": akd("p_skill_reticentsword_s.wav", 0.1, 0.45, fout=0.2), "cast": akd("p_skill_reticentsword_h.wav", 0.1, 0.5, fout=0.2),
        "impact": pad(akd("p_skill_reticentsword_h.wav", 0.1, 0.8, fout=0.3), sn("liq", 0.0, 0.5, fout=0.2) * 0.5),
        "wave": lp(akd("p_skill_tidesurging_2.wav", 0.3, 1.6, fout=0.6), 7000),
        "crash": hp(pad(akd("p_skill_bigwatercannon.wav", 0.0, 1.5, 0.9, fout=0.6), akd("p_skill_MHshieldaxe_ground2.wav", 0.0, 1.2, fout=0.5) * 0.7,
                        sn("sub", 0.0, 1.2, 0.9, fout=0.5) * 0.5), 70, 4),
    }


def gladiia():
    """docs/205 §4.4（用户 10-31 选 ① 原作海水）：提示 = 原作水炮起头降调 → 放出 / 卷起水龙卷 = 原作召潮（fx strip tornado_open）
    → 龙卷持续 = 原作潮涌铺底（strip tornado_loop）→ 水环往里收每道一声水泡（ring r40 w4）→ 收拢 = 原作水炮（seg 收拢 on）
    → 潮涌炸开（高潮，strip fx_skadi_surge）= 原作水炮 + 潮涌 + 低频 → 水花（strip fx_water_splash，Sonniss 液体冲击）"""
    return {
        "sf": akd("p_skill_bigwatercannon.wav", 0.03, 0.5, 0.7, fout=0.25), "cast": akd("p_skill_seasummon.wav", 0.0, 0.6, fout=0.3),
        "open": akd("p_skill_seasummon.wav", 0.0, 1.2, fout=0.5), "loop": akd("p_skill_tidesurging_1.wav", 0.2, 1.8, fout=0.6),
        **{"swirl_%d" % (i + 1): akd("p_skill_waterbubble.wav", 0.15, 0.75, r, fout=0.25) for i, r in enumerate([0.9, 1.0, 1.1])},
        "crush": akd("p_skill_bigwatercannon.wav", 0.03, 0.9, 0.85, fout=0.3),
        "surge": pad(akd("p_skill_bigwatercannon.wav", 0.0, 1.8, fout=0.6), akd("p_skill_tidesurging.wav", 0.45, 1.4, fout=0.5) * 0.6, lp(sn("b214", 0.25, 1.4, fout=0.6), 900) * 0.8),
        **{"splash_%d" % (i + 1): sn("liq", 0.0, 0.5, r, fout=0.2) for i, r in enumerate([1.0, 1.1, 1.2])},
    }


def angelina():
    """docs/205 §4.4（用户 10-31 选 ② 录音）：提示 = 电光定格 → 重力井张开 = 能量流（strip well_back）→ 吸起 = 低音起跳（seg 奇点 on）
    → 脉冲环 = 电光（ring r60 w3）、光线往里收 = 短掠过（line+v w2）→ 每次砸地 = 斩击冲击 + 低音下坠（strip well_close，第一下叠预告片低频最重）"""
    return {
        "sf": sn("elec", 0.0, 0.6, 0.8, fout=0.25), "cast": sn("astral", 0.0, 0.5, fout=0.2),
        "open": sn("astral", 0.0, 1.6, fout=0.6), "lift": sn("jump", 0.0, 1.0, fout=0.4),
        **{"pulse_%d" % (i + 1): sn("elec", 0.0, 0.5, r, fout=0.25) for i, r in enumerate([0.7, 0.8])},
        **{"streak_%d" % (i + 1): sn("sweep", 0.0, 0.35, r, fout=0.15) for i, r in enumerate([1.2, 1.3, 1.4])},
        "slam_1": pad(sn("cut", 0.93, 1.4, fout=0.5), lp(sn("drop", 0.0, 1.2, fout=0.5), 1500) * 0.8, lp(sn("b214", 0.25, 1.4, fout=0.6), 900) * 0.8),
        **{"slam_%d" % (i + 2): pad(sn("cut", 0.93, 1.0, r, fout=0.4), lp(sn("drop", 0.0, 0.8, r, fout=0.4), 1500) * 0.6) for i, r in enumerate([0.92, 1.08])},
    }


def eyjafjalla():
    """docs/205 §4.4（用户 11-01 选 ② 录音；画面按喷发冲击帧 v3）：提示 = 火焰低吼 → 瞄准 = 雷声低滚 + 噼啪
    → 放出（裂纹渗开、气泡上冒 0.4 秒）= 冰面龟裂降调 + 低滚 → 喷发 impact（与冲击帧同一帧）= 雷暴炸裂 + 火焰低吼 + 预告片低频 + 碎屑
    → 每颗火山弹落地（fx strip fx_ey_pumice）= 近距烟花爆破降调 bomb_1..3 → 黑蒸汽翻起（strip fx_ey_steam）= 浇水灭火的蒸汽
    → 熔岩池铺开 1 秒后（strip fx_ey_pool at 1.0）= 篝火噼啪；熔岩天降路线的预热弹（seg 熔岩弹）沿用 bomb_1"""
    d = {
        "sf": sn("fwhsh", 0.35, 0.55, 1.0, fout=0.25),
        "charge": pad(lp(sn("rumbleT", 6.0, 0.9, fout=0.3), 1500), hp(sn("cauldron", 60.0, 0.9, fout=0.3), 1500) * 0.4),
        "cast": pad(lp(sn("fissure", 0.0, 0.45, 0.8, fout=0.15), 4000), lp(sn("rumbleT", 6.2, 0.45, fout=0.1), 900) * 0.7),
        "impact": pad(sn("thunder", 3.27, 1.5, 0.85, fout=0.6), sn("fwhsh", 0.45, 1.3, 0.85, fout=0.5) * 0.6, lp(sn("b214", 0.25, 1.4, fout=0.6), 900) * 0.8, sn("debris", 0.35, 1.0, fout=0.4) * 0.4),
        **{"bomb_%d" % (i + 1): lp(sn("fworks", t, 0.6, r, fout=0.25), 5000) for i, (t, r) in enumerate(zip([4.32, 6.57, 9.07], [0.72, 0.66, 0.78]))},
        "steam": sn("steam", 0.08, 1.5, fout=0.6),
        "ground": sn("fire", 0.5, 1.2, fout=0.5),
    }
    d["lava_hit"] = d["bomb_1"]
    return d


def wisadel():
    """docs/205 §4.4（用户 10-31 选 ① 原作炮击）：提示 = 原作重炮蓄能 → 放出 = 原作发射架 → 开炮（strip fx_cannon_burst）= 原作重炮
    → 每发落弹（strip fx_wisadel_cannon）= 原作火爆弹 3 个音高 → 余震（strip fx_missile_explode）= 原作火爆弹发射声
    → 第一发掉血 impact = 原作陨石爆炸 + 低频（全招最重）"""
    return {
        "sf": akd("p_skill_blackcannonfull_cast.wav", 0.15, 0.45, fout=0.2), "cast": akd("p_skill_launcher_cast.wav", 0.0, 0.8, fout=0.3),
        "fire": akd("p_skill_blackcannonfull.wav", 0.0, 1.0, fout=0.4),
        **{"shell_%d" % (i + 1): akd("p_skill_fireboomexplo.wav", 0.0, 0.9, r, fout=0.35) for i, r in enumerate([1.0, 0.92, 1.08])},
        **{"after_%d" % (i + 1): akd("p_skill_fireboomshot.wav", 0.0, 0.6, r, fout=0.25) for i, r in enumerate([1.0, 1.1, 0.9])},
        "impact": pad(akd("p_skill_aeroliteexplo.wav", 0.0, 1.3, fout=0.5), lp(sn("b214", 0.25, 1.4, fout=0.6), 900) * 0.9),
    }


def specter_unchained():
    """docs/205 §4.7（用户 11-01「归溟幽灵鲨的终结技音效也要修改」→ 11-01 选定 ① 原作链锯；画面弹射撕裂 + 巨锯不动）：
    提示 = 原作链锯起转 → 放出 = 原作链锯展开起头 → 每次弹射一声链锯咬合 zip_1..3（原作链锯不同段）
    → 巨锯压下 warn = 原作链锯持续研磨降调 → 落地锯开 impact（高潮）= 原作链锯收尾 + 原作盾斧砸地爆裂（80 Hz 以下切，不留「咚」）"""
    return {
        "sf": akd("p_skill_chainsawextension.wav", 0.0, 0.45, fout=0.2), "cast": akd("p_skill_chainsawulmextension_1_intro.wav", 0.0, 0.8, fout=0.3),
        **{"zip_%d" % (i + 1): akd("p_skill_chainsawextension.wav", t, 0.3, r, fout=0.12) for i, (t, r) in enumerate([(0.3, 1.1), (0.75, 1.2), (1.2, 1.0)])},
        "warn": akd("p_skill_chainsawulmextension_2.wav", 0.1, 1.2, 0.85, fout=0.4),
        "impact": hp(pad(akd("p_skill_chainsawulmextension_3.wav", 0.0, 1.4, fout=0.5), akd("p_skill_MHshieldaxe_ground2.wav", 0.0, 1.2, fout=0.5) * 0.7), 80, 4),
    }


def mizuki():
    """docs/205 §4.4（用户 10-31 选 ① 原作；画面按 claude/ult-fx-c2 水母群第三轮）：提示 = 原作水泡降调 → 放出 = 原作召潮升调
    → 每只水母冒出一声水泡 rise_1..3（fx circle r26 地面暗斑）→ 一起压缩 compress（原作黑洞吸入，fx ring r90 w4 出现）
    → 一起炸开 burst（高潮，fx ring w10 r1 60 群心冲击波）= 原作水炮 + 潮涌 + 低频 → 每只爆闪一声小水泡 pop_1..3（fx circle r34）"""
    return {
        "sf": akd("p_skill_waterbubble.wav", 0.15, 0.5, 0.8, fout=0.25), "cast": akd("p_skill_seasummon.wav", 0.0, 0.6, 1.1, fout=0.3),
        **{"rise_%d" % (i + 1): akd("p_skill_waterbubble.wav", 0.15, 0.5, r, fout=0.2) for i, r in enumerate([1.3, 1.42, 1.55])},
        "compress": akd("p_skill_darkholespell.wav", 0.0, 0.55, 1.1, fout=0.1),
        "burst": pad(akd("p_skill_bigwatercannon.wav", 0.0, 1.6, 0.9, fout=0.6), akd("p_skill_tidesurging.wav", 0.45, 1.2, 1.1, fout=0.5) * 0.6, lp(sn("b075", 0.25, 1.0, fout=0.4), 900) * 0.7),
        **{"pop_%d" % (i + 1): akd("p_skill_waterbubble.wav", 0.15, 0.4, r, fout=0.15) for i, r in enumerate([1.7, 1.85, 2.0])},
    }


def saria():
    """docs/205 §4.3（用户 10-31 选原作版 ①）：按 Q = 原作碎岩一下定格 sf → 举拳聚光 gather（原作 rockboost 起段，fx line+v w3）
    → 一拳砸地 slam（fx circle r110，高潮挂画面：原作 jumphammer_2 + 预告片低频；第一下掉血不另响，没有 impact）
    → 沿裂纹一波波岩柱爆开 rock_1..4（原作 rocksleep 起头那一下 + 自然衰减，4 个音高；fx strip pillar_break 节流 0.15 秒）。
    10-31 用户「奇怪的卡顿声」：原作 rocksleep / rockboost 是 2 秒连续碎石声，先前切成 0.5 秒碎段、0.07 秒连发听着像卡顿 → 改成每声完整一下；
    没有蓄力 charge（碎石磨擦声连续抖动）"""
    return {
        "sf": akd("p_skill_rocksleep.wav", 0.0, 0.45, 0.8, fout=0.25),
        "gather": akd("p_skill_rockboost.wav", 0.0, 0.5, fout=0.15),
        "air": sn("debris", 0.1, 0.8, 0.9, fout=0.3),   # 10-31 朝前打 v2：拳风往前推出（fx strip fx_sa_air）；岩柱改成崩起碎石（fx_ul_rock / rock2 带速度）
        "slam": pad(akd("p_skill_jumphammer_2.wav", 0.0, 1.0, fout=0.4), lp(sn("b214", 0.25, 1.4, fout=0.6), 900) * 0.9),
        **{"rock_%d" % (i + 1): akd("p_skill_rocksleep.wav", 0.0, 0.45, r, fout=0.28) for i, r in enumerate([1.0, 1.08, 0.94, 1.15])},
    }


def suzuran():
    """docs/205 §4.6（11-01 定稿 ① 原作刀声 + 录音）：提示 = 原作忍刀命中 → 忍冬现身 cast = 能量流升调 → 瞬身 flash（seg 瞬身 on）= 原作忍刀一挥
    → 斩痕爆亮 impact（冲击帧同帧，全招最响）= 原作暗刃 + 斩击冲击 + 低频 → 0.32 秒后刀痕绷开 rupt（fx band w8 冷白细芯，次级）= 鞭响脆裂 + 原作忍刀命中。
    11-01 第二轮（用户「忍冬最后的爆裂要做出来」，画面刀痕连环爆裂 ult/sz_rupt_chain）rupt 改成 原作灵魂爆裂升调 + 原作忍刀命中（用户选 ①）"""
    rupt = pad(akd("p_skill_spiritexplo.wav", 0.02, 0.9, 1.15, fout=0.35), akd("p_skill_ninjasword_imp.wav", 0.05, 0.5, 0.85, fout=0.2) * 0.6)
    return {
        "sf": akd("p_skill_ninjasword_imp.wav", 0.05, 0.5, fout=0.2), "cast": sn("astral", 0.0, 0.5, 1.3, fout=0.2),
        "flash": akd("p_skill_ninjasword.wav", 0.05, 0.5, fout=0.2),
        "impact": pad(akd("p_skill_darkatana.wav", 0.0, 1.0, fout=0.4), sn("cut", 0.93, 0.9, fout=0.4) * 0.6, lp(sn("b075", 0.25, 1.0, fout=0.4), 900) * 0.7),
        "rupt": rupt,
    }

ZW_BELL = "Ivo Vicic - Church Bells/04 Church Bells, Near Distance, In Church Tower-3 Different Bell 02.wav"   # 2.80 秒处一记大钟（锣的金属体）
ZW_DROP = "344 Audio - Bass Drops & Downers Vol. 1/DSGNBass_Bass Drop & Downer Fast 16_344 Audio_Bass Drops & Downers.wav"   # 0.13 秒瞬态 + 音高快速下坠
ZW_TONE = "344 Audio - Bass Drops & Downers Vol. 3/DSGNBass_Tone Downer (Reverb)_344 Audio_Bass Drops and Downers Vol 3.wav"   # 长音下坠 + 混响尾
ZW_SHIM = "Epic Stock Media - Anime Game/DSGNStngr_Power Up Bright Positive Successful Light Saturation Crash Shimmer 05_ESM_AG.wav"   # 碎钹般的亮尾
ZW_SWEEP = "Cinematic Sound Design - Ultra Transitions & Impacts/Woosh Sweep Slide Infographics Basic.wav"
ZW_CLK = "344 Audio - Antique Clocks/CLOCKTick_You're Running Late _344 Audio_Antique Clocks.wav"   # 座钟（11-01 第四轮 LC2）：0.755 起每 0.75 秒一下
ZW_LATCH = "Epic Stock Media - HD Lock And Mechanism Sound Design Kit/MECHLtch_Click Deep Mechanism Latch Button Nearfield Thunk 02_ESM_HDLM.wav"
ZW_CLANK = "Epic Stock Media - HD Game Materials/METLImpt_Metal Old File Impact Tap Against Tire Iron Metallic Hit 01_ESM_HDGM.wav"
ZW_HUM = "Jake Fielding - Fridge Hums Vol.2/MACHAppl_Deep Fridge Hum, Buzz, Electric Tone, Deep_Jake Fielding_Fridge Hums Pt2.wav"
ZW_CAST_T = 1.8   # 放出（cast）到爆开那一声（impact，收尾加强吸气之后）实测 54 帧 = 1.8 秒（cue_lg 录像 SFXTRACE 218 → 272）


def _zw_tick(t0, gain=1.0, rate=1.0, dur=0.16):
    return hp(lib(ZW_CLK, t0 - 0.006, dur, rate, fout=0.06), 250) * gain


def _zw_verb(x, sec, wet, cut, seed):
    """长混响尾巴（空间被压扁后的回响）：衰减噪声冲激卷积，种子固定"""
    from scipy.signal import fftconvolve
    n = int(sec * SR)
    ir = lp(np.random.default_rng(seed).standard_normal(n), cut) * np.exp(-np.linspace(0.0, 6.9, n))
    ir /= np.sqrt(np.sum(ir ** 2)) + 1e-9
    return pad(x, fftconvolve(x, ir) * wet)


ZW_CLK_A = "344 Audio - Antique Clocks/CLOCKTick_Crooked Antique Clock_344 Audio_Antique Clocks.wav"   # 歪钟（偏重那版垫一层，滴答更厚）
ZW_A_ON = {0.755: 2.06, 1.5: 3.055, 2.255: 7.035, 3.005: 8.06, 3.755: 9.055}   # 座钟第 n 下 → 歪钟里对应用哪一下（起点实测）


def _zw_after(blast, tk):
    """爆开 + 时钟接着走两下：爆开尾巴 0.35 秒起压低 15 dB，0.45 / 0.8 秒各一下滴答"""
    duck = np.ones(len(blast))
    i0, i1 = int(0.35 * SR), int(0.5 * SR)
    duck[i0:i1] = np.linspace(1.0, 0.18, i1 - i0)
    duck[i1:] = 0.18
    return pad(blast * duck, at(tk(1.5, 2.2), 0.45), at(tk(2.255, 2.0), 0.8))


def logos(v=1):
    """docs/205 §4.10（11-01 第五轮，用户「要 JoJo『世界』时停那种声音」；只按特征用录音重做，不扒原片）：
    开始（charge，确认释放后的 0.5 秒起手里响）= 倒放的大钟 + 碎钹亮尾往里吸，越来越响 →
    放出 cast（时停那一刻）= 沉重闷「嗡——咚」：低音瞬态音高往下坠 + 预告片低频 + 大钟降调 + 长音下坠，长混响尾巴；同时配乐低通压到很小、别的音效压低（ult.gd world_hush）
    → 停住：完全没有滴答（静止感），只留极低的电器嗡鸣 → 结束（cast 末尾，对准爆开）= 反向扫频「呼——」往上提（低音下坠倒放 = 音高回正）
    → 爆开 impact：世界的声音从低通里弹回来（ult.gd _fin_release），真空压缩爆炸。
    时钟是主角（11-01 第六轮，用户「logos 的是不是还没有时钟的声音」）：起手 0.5 秒里秒针「滴、答、滴」三下越走越紧、在前景（吸气垫在下面）；
    时停那一刻同帧一记清楚的机械卡死「咔」（高通，和嗡——咚叠着也能单独听出来）；停住期间无滴答；爆开前 0.3 秒一记「咔哒」，
    时钟重新走：爆开前一下、爆开后两下（爆开尾巴压低让出来）。
    每只敌人头上咒文 glyph_1..3 照旧（很轻）。提示音 sf 不放（sf_off）。
    v=1 偏重：大钟降到 0.7、预告片低频压底、混响 1.8 秒；v=2 偏清脆：大钟原调、碎钹亮尾多、混响 1.4 秒、滴答原调更亮"""
    heavy = v != 2
    r = 0.85 if heavy else 1.0
    n05 = int(0.5 * SR)
    bell = lib(ZW_BELL, 2.80, 1.0, 0.7 if heavy else 1.0, fin=0.002, fout=0.05)
    shim = hp(lib(ZW_SHIM, 0.13, 0.9, 0.8 if heavy else 1.0, fout=0.1), 1500)
    charge = pad(lp(rev(bell), 5000 if heavy else 9000)[-n05:], rev(shim)[-n05:] * (0.45 if heavy else 0.9))
    charge = charge * np.linspace(0.15, 1.0, len(charge)) ** 1.5 * 0.35   # 越吸越响，到时停那一刻最满；垫在秒针下面
    tr = 0.85 if heavy else 1.0
    tk = lambda t0, g, d=0.14: _zw_tick(t0, g, tr, d) if not heavy else pad(_zw_tick(t0, g, tr, d), lp(lib(ZW_CLK_A, ZW_A_ON[t0] - 0.006, d, 0.9, fout=0.05), 6000) * g * 0.5)
    # 秒针「滴、答、滴」越走越紧：0.03 / 0.21 / 0.36（间隔 0.18 → 0.15），前景
    charge = pad(charge, at(tk(0.755, 1.0), 0.03), at(tk(1.5, 0.9), 0.21), at(tk(2.255, 1.0), 0.36))
    drop = lib(ZW_DROP, 0.11, 1.6, r, fout=0.6)
    tone = lib(ZW_TONE, 0.6, 2.0, r, fout=0.8)
    low = lp(sn("b214", 0.25, 1.4, fout=0.6), 600)
    ring = lp(lib(ZW_BELL, 2.80, 1.4, 0.5 if heavy else 0.75, fout=0.6), 1800 if heavy else 4500)
    boom = pad(drop, low, ring * 0.45, tone * 0.4) if heavy else pad(drop * 0.7, ring * 0.7, tone * 0.5, low * 0.45)
    boom = _zw_verb(boom, 1.8 if heavy else 1.4, 0.45 if heavy else 0.35, 2500 if heavy else 5000, 11 if heavy else 12)
    tb = np.arange(len(boom)) / SR
    boom = boom * np.where(tb < 0.08, 1.0, np.exp(-(tb - 0.08) / (0.32 if heavy else 0.26)))   # 「咚」之后指数衰减：混响尾巴拖着，约 1 秒收到近乎无声
    boom = fadeio(boom[:int(1.1 * SR)], 0.002, 0.3)
    # 时停那一刻的机械卡死「咔」：深闩扣 + 钟锤一记 + 铁件敲击，1 kHz 以下切掉（嗡——咚在低频，咔在中高频，叠着能单独听出来）
    stop = hp(pad(lib(ZW_LATCH, 0.0, 0.38, 0.8 if heavy else 1.0, fout=0.15), _zw_tick(3.005, 0.9, 0.75 if heavy else 0.9, 0.3), lib(ZW_CLANK, 0.12, 0.34, 0.85 if heavy else 1.0, fout=0.2) * 0.6), 1000)
    hum = lp(lib(ZW_HUM, 20.0, 1.3, fout=0.3), 160) * (0.14 if heavy else 0.1)
    if heavy:
        riser = pad(rev(lib(ZW_DROP, 0.11, 0.8, 0.85, fout=0.05))[-int(0.45 * SR):], rev(sn("debris", 0.1, 0.6, fout=0.05))[-int(0.45 * SR):] * 0.5)
    else:
        riser = pad(rev(lib(ZW_DROP, 0.11, 0.6, 1.1, fout=0.05))[-int(0.4 * SR):], rev(shim)[-int(0.4 * SR):] * 0.6, rev(lib(ZW_SWEEP, 0.03, 0.4, fout=0.05)) * 0.5)
    riser = riser * np.linspace(0.2, 1.0, len(riser)) ** 2
    # 爆开前 0.3 秒「咔哒」（钟重新卡上）+ 0.15 秒后第一下滴答
    restart = hp(pad(lib(ZW_LATCH, 0.0, 0.38, 0.9 if heavy else 1.1, fout=0.15), _zw_tick(3.755, 0.7, tr, 0.2)), 800)
    cast = pad(boom, at(stop * 2.4, 0.0), at(hum, 0.45), at(riser * 0.6, ZW_CAST_T - len(riser) / SR), at(restart * 2.2, ZW_CAST_T - 0.3), at(tk(0.755, 1.8), ZW_CAST_T - 0.15))
    release = sn("wind", 0.05, 0.8, 1.1, fout=0.35) if heavy else sn("debris", 0.1, 0.9, 1.1, fout=0.4)
    blast = pad(sn("elec", 0.0, 0.9, 0.6, fout=0.4), akd("p_skill_darkholespell.wav", 0.0, 1.2, 0.85, fout=0.5) * 0.6, lp(sn("b214", 0.25, 1.4, fout=0.6), 900) * 0.9, release * 0.5)
    return {
        "sf": None,
        "charge": fadeio(charge, 0.01, 0.01),
        "cast": cast,
        **{"glyph_%d" % (i + 1): hp(sn("astral", 0.3, 0.3, rr, fout=0.15), 800) for i, rr in enumerate([1.5, 1.62, 1.75])},
        "impact": _zw_after(blast, tk),
    }


def hoshiguma():
    """docs/205 §4.3（用户 10-31 选录音版 ② 再「低频一点」：整体降调 ×0.8、5 kHz 以上压掉、低频轰加厚）：
    按 Q = 金属重击 sf + 金属箱拖拽 charge → 盾砸地 cast（重击 + 低频轰）+ 吸怪碎石呼啸 pull（fx line+v）
    → 挡的期间金属吃力 block（seg 格挡 on）+ 每圈新裂纹一声冰裂 crack_1..5（fx line w3，逐圈略升）
    → 盾甲炸开 boom（fx blade+v，高潮：斩击冲击 + 预告片低频轰 + 地裂）→ 热砂 sizzle（篝火噼啪，fx dots）"""
    R = 0.8
    boom = pad(lp(sn("cut", 0.93, 1.4, R, fout=0.5), 5000), lp(sn("b214", 0.25, 1.6, fout=0.6), 900) * 1.1, lp(sn("fissure", 0.0, 0.9, 0.7, fout=0.3), 4000) * 0.5)
    # 11-01 用户「最后缺个爆裂的声音」→ 选 ②：盾甲炸开叠一层原作火爆弹炸裂 + 机械爆炸
    boom = pad(boom * 0.8, akd("p_skill_fireboomexplo.wav", 0.0, 1.3, 0.85, fout=0.5) * 0.9, akd("p_skill_robotexplo.wav", 0.55, 1.0, 0.9, fout=0.4) * 0.5)
    return {
        "sf": lp(sn("bang", 0.0, 0.7, R), 5000), "charge": lp(sn("drag", 0.5, 1.0, R, fout=0.2), 5000),
        "cast": pad(lp(sn("thud", 0.2, 1.0, R, fout=0.3), 5000), lp(sn("b214", 0.25, 1.1, fout=0.4), 700) * 0.9),
        "pull": lp(sn("debris", 0.1, 0.9, R, fout=0.3), 5000),
        "block": lp(sn("drag", 1.5, 1.6, R, fout=0.3), 4000),
        **{"crack_%d" % (i + 1): pad(lp(sn("ice", 0.0, 0.45, R * (1.0 + 0.04 * i)), 5000), lp(sn("thud", 0.38, 0.35, R, fout=0.2), 1500) * 0.4) for i in range(5)},
        "boom": boom,
        "sizzle": lp(sn("fire", 2.0, 0.6, fout=0.2), 7000),
    }


def siege():
    """docs/205 §4.7（用户 11-01「推进之王的终结技音效需要修改」；10-31 要「拿着锤子爆裂的感觉」、不要「咚」——那一声已查实是队友技能音效，放出期间静音）：
    11-01 选定 ① 原作盾斧爆裂：提示 = 原作磁锤 → 起跳 = 原作跳劈起手 → 落地砸地 smash（fx circle r100，高潮）= 原作盾斧砸地榴弹爆裂 + 原作磁锤砸实瞬态 + 碎石
    → 再跃小砸地 smash2 = 原作盾斧重击 → 碎岩 rock_1..3 = 原作碎盾 3 个音高 → 敌人落地 land = 原作盾斧收势。90 Hz 以下切，保留锤身的重量"""
    return {
        "sf": akd("p_skill_magnetichammer.wav", 0.0, 0.45, 1.0, fout=0.2), "cast": akd("p_skill_jumphammer_1.wav", 0.0, 0.7, fout=0.25),
        "smash": hp(pad(akd("p_skill_MHshieldaxe_ground2.wav", 0.0, 1.35, fout=0.5), akd("p_skill_magnetichammer.wav", 0.0, 0.5, fout=0.2) * 0.6,
                        sn("debris", 0.1, 1.0, fout=0.4) * 0.4), 90, 4),
        "smash2": hp(akd("p_skill_MHshieldaxe_h2.wav", 0.0, 0.7, fout=0.25), 200),
        **{"rock_%d" % (i + 1): hp(akd("p_skill_shieldbreak.wav", 0.0, 0.45, r, fout=0.2), 400) for i, r in enumerate([0.85, 0.95, 0.78])},
        "land": hp(akd("p_skill_MHshieldaxe_end.wav", 0.0, 0.5, fout=0.2), 300),
    }


def irene(v=1):
    """docs/205 §4.6（11-01 定稿 ① 录音 + 原作；画面「宣判」）：提示 = 原作光剑 → 盖下审判纹章 seal（fx strip fx_irv_seal）= 金属重击共鸣降调 + 原作铜印
    → 纹章内来回穿梭 6 刀 cut_1..3（fx blade w6，每刀一声）= 长刃刮擦升调轮换 → 连环爆 boom_1 / boom_hit（seg 宣判）= 小爆炸降调
    → 最后一刀劈开纹章 impact（冲击帧同帧，全招最响）= 斩击冲击 + 多层剑斩 + 预告片低频。
    v=2 原作：每刀 = 原作弧切，最后一刀 = 原作沉默之剑重斩 + 低频"""
    d = {
        "sf": akd("p_skill_lightsword.wav", 0.0, 0.5, 1.05, fout=0.2), "cast": sn("slice", 0.29, 0.45, 1.1, fout=0.2),
        "seal": pad(sn("ring", 0.0, 1.0, 0.75, fout=0.4), akd("p_skill_copperseal.wav", 0.0, 1.0, fout=0.4) * 0.5),
        **{"cut_%d" % (i + 1): sn("scrape", 0.0, 0.3, r, fout=0.12) for i, r in enumerate([1.15, 1.28, 1.05])},
        "boom_1": sn("blast", 0.02, 0.5, 0.85, fout=0.2), "boom_hit": sn("blast", 0.02, 0.4, 0.95, fout=0.15),
        "impact": pad(sn("cut", 0.93, 1.4, fout=0.5), sn("slice", 0.29, 0.7, fout=0.3) * 0.7, lp(sn("b214", 0.25, 1.4, fout=0.6), 900) * 0.9),
    }
    if v == 2:
        d.update({**{"cut_%d" % (i + 1): akd("p_skill_arccutting.wav", 0.0, 0.4, r, fout=0.15) for i, r in enumerate([1.1, 1.2, 1.0])},
                  "impact": pad(akd("p_skill_reticentsword_h.wav", 0.1, 1.2, fout=0.5), lp(sn("b214", 0.25, 1.4, fout=0.6), 900) * 0.9)})
    return d

def lappland():
    """docs/205 §4.7（用户 11-01「拉普兰德的音效和终结技还得做一下」；11-01 夜的 ① 作废）：起手语音 = 她的笑声（voice）
    11-01 选定 ① 原作：放出 = 原作双刀展开 → 每道剑气 slash_1..4 = 原作弧切（亮金属掠过，4 个音高）；第一下掉血 impact 很轻
    → 收尾横斩 final（hf_slot，全招最响）= 原作沉默之剑重斩 + 原作双刀 + 预告片低频 → 空气爆破 air = 原作盾斧砸地爆裂升调 + 碎屑呼啸。
    画面原来硬写的通用 boom 已去掉（ult/la_r2），空气爆破只响 air 这一声"""
    return {
        "sf": akd("p_skill_arccutting.wav", 0.0, 0.4, 0.95, fout=0.15), "cast": akd("p_skill_MHdualswords_on.wav", 0.0, 0.6, fout=0.2),
        **{"slash_%d" % (i + 1): akd("p_skill_arccutting.wav", 0.0, 0.3, r, fout=0.1) for i, r in enumerate([1.0, 1.1, 1.2, 0.92])},
        "impact": akd("p_skill_arccutting.wav", 0.0, 0.3, 0.9, fout=0.1),
        "final": pad(akd("p_skill_reticentsword_h.wav", 0.1, 1.2, fout=0.5), akd("p_skill_MHdualswords_on.wav", 0.0, 0.8, fout=0.3) * 0.6, lp(sn("b075", 0.25, 1.0, fout=0.4), 900) * 0.6),
        "air": hp(pad(akd("p_skill_MHshieldaxe_ground.wav", 0.0, 1.0, 1.15, fout=0.4) * 0.8, sn("debris", 0.3, 1.0, fout=0.4) * 0.4), 120),
    }


def lumen():
    """docs/205 §4.4（用户 10-31 选 ① 原作）：提示 = 原作星光 → 放出 = 原作提灯 → 点亮灯塔（strip fx_beacon_ignite）= 原作提灯
    → 光圈炸开 impact（高潮）= 原作灯火进化 + 低频 → 光柱每跳一声铃（dots，原作召回铃 3 个音高）→ 光雨（line+v w2，原作星光升调）"""
    return {
        "sf": akd("p_skill_shinestar.wav", 0.0, 0.6, 0.9, fout=0.3), "cast": akd("p_skill_lantern_cast.wav", 0.0, 0.6, fout=0.3),
        "ignite": akd("p_skill_lantern.wav", 0.0, 1.2, fout=0.5),
        "impact": pad(akd("p_skill_lanternevolution.wav", 0.1, 1.5, fout=0.6), lp(sn("b075", 0.25, 1.2, fout=0.5), 900) * 0.6),
        **{"pulse_%d" % (i + 1): akd("p_skill_recallbell.wav", 0.0, 0.6, r, fout=0.25) for i, r in enumerate([1.0, 1.12, 1.26])},
        **{"rain_%d" % (i + 1): akd("p_skill_shinestar.wav", 0.0, 0.5, r, fout=0.25) for i, r in enumerate([1.3, 1.45, 1.6])},
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
    ap.add_argument("--variant", type=int, default=1, help="备选版（docs/205 §4.6，干员函数带 v 参数的才认；配 --only、不带 --apply 出候选）")
    ap.add_argument("--out", default="", help="候选输出目录（缺省 build/ult_sfx/S）")
    a = ap.parse_args()
    only = set(a.only.split(",")) if a.only else None
    dst_dir = SFX if a.apply else (a.out or OUT)
    os.makedirs(dst_dir, exist_ok=True)
    for f in OPS:
        op = f.__name__
        if only and op not in only:
            continue
        if a.reseed:   # 每人独立随机序列（docs/205 §4 起逐人精调用；改一人不牵动别人）。没加 --reseed 时沿用旧的全程一条序列
            rng.bit_generator.state = np.random.default_rng(zlib.crc32(op.encode())).bit_generator.state
        d = f(a.variant) if a.variant != 1 else f()
        st = rng.bit_generator.state   # sf 不占随机序列：其余槽与加 sf 之前逐字节相同
        if "sf" not in d:   # 干员函数自己给了录音版 sf 就不用合成的
            d["sf"] = FLASH[op]()
        d = {k: x for k, x in d.items() if x is not None}   # 给 None = 这一槽不要（逻各斯 sf）：不写，--apply 时旧文件按下面一并删
        rng.bit_generator.state = st
        if a.apply:   # 旧的通用槽（A/B/C 时代的 hit 等）不再用的删掉；只剩 .import 的也删（否则 Godot 照样从导入缓存放旧声）
            for imp in glob.glob(os.path.join(SFX, "ult_%s_*.wav.import" % op)):
                if not os.path.exists(imp[:-7]) and os.path.basename(imp)[len("ult_%s_" % op):-11] not in d:
                    os.remove(imp)
            for old in glob.glob(os.path.join(SFX, "ult_%s_*.wav" % op)):
                if os.path.basename(old)[len("ult_%s_" % op):-4] not in d:
                    os.remove(old)
                    if os.path.exists(old + ".import"):
                        os.remove(old + ".import")
        info = []
        for slot, x in d.items():
            RMS[slot] = LV_OP.get((op, slot), level(slot, np.asarray(x)))
            info.append("%s %.2f" % (slot, write(os.path.join(dst_dir, "ult_%s_%s.wav" % (op, slot)), np.asarray(x, dtype=np.float64), slot)))
        print(op, " / ".join(info))


if __name__ == "__main__":
    main()
