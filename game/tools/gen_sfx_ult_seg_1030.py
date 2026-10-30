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


LV = {"mark": -13.0, "sword": -18.0, "shatter": -17.0, "cut": -11.0, "shot": -16.0, "pop": -17.0, "crack": -14.0, "pull": -16.0, "boom": -9.0, "slam": -9.0, "surge": -9.0, "final": -9.0, "slam_1": -9.0, "sizzle": -17.0}   # 画面单元槽（docs/205 §4.2），按槽名前缀


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
    "rattle": "344 Audio - Elemental Palette Designed Vol. 1/METLMisc_Metal, Slow Whoosh, Rattle, Pass By x4 01_344 Audio_Elemental Palette Designed Vol 1.wav",
    "ring": "David Dumais Audio - Melee Weapons Sound Effects Pack 2/METLImpt_METAL SWING HIT Weapon Swing To Metallic Body Impact And Resonant Tail 01_DDUMAIS_MWP2.wav",
    "sub": "Epic Stock Media - Elemental Mutation Whooshes and Impacts/WATRImpt_Impact Water Deep Submerge Bubble Drown Ship Hit 05_ESM_EMWI.wav",
    "liq": "344 Audio - Elemental Palette Designed Vol. 1/WATRMisc_Water, Liquid Impact, Bubble, Sci Fi, Hit 04_344 Audio_Elemental Palette Designed Vol 1.wav",
    "astral": "Alexander Kopeikin - Emotion and Magic/magic, energy flow, astral travel-015.wav",
    "jump": "344 Audio - Bass Drops & Downers Vol. 3/DSGNBass_Jump Start Drop 3_344 Audio_Bass Drops and Downers Vol 3.wav",
    "drop": "344 Audio - Bass Drops & Downers Vol. 1/DSGNBass_Bass Drop & Downer Fast 16_344 Audio_Bass Drops & Downers.wav",
    "sweep": "Cinematic Sound Design - Ultra Transitions & Impacts/Woosh Sweep Slide Infographics Basic.wav",
    "b011": "Federico Soler - Effective Trailer Booms Vol. 2/EffectiveTrailer_Booms_Vol2_011.wav",
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
    """落点龟裂 0.4 秒 → 巨大火柱喷出（冲击）→ 熔岩块落满一圈（每块一声）→ 中间留熔岩地面"""
    return {
        "charge": pad(rumble(0.9, 160, 0.6) * swell(0.9, 0.9), crackle(0.9, 120, 900, 4000, 1.0) * swell(0.9, 0.9) * 0.5),
        "cast": pad(crack(0.45, 7) * 0.8, lp(N(0.45), 1300) * swell(0.45, 0.95) * 0.6),
        "impact": pad(sweep_noise(1.2, 400, 2400, 0.7) * env(1.2, 0.003, 2.8) * 1.0, burst(0.8, 2200, 5), sub(0.9, 70, 28, 3.5), crackle(1.2, 320, 1300, 6000, 3) * 0.55),
        "lava_hit": pad(thud(0.28, 120, 45, 14) * 0.8, crackle(0.25, 220, 1500, 5000, 13) * 0.5, splash(0.2, 1800, 16) * 0.3),
        "ground": pad(crackle(1.2, 160, 1200, 5000, 2.0) * 0.6, lp(N(1.2), 600) * env(1.2, 0.05, 2.0) * 0.7),
    }


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
    """docs/205 §4.3（用户 10-31 选原作版 ①）：按 Q = 原作碎岩一下定格 sf → 举拳聚光 gather（原作 rockboost 起段，fx line+v w3）
    → 一拳砸地 slam（fx circle r110，高潮挂画面：原作 jumphammer_2 + 预告片低频；第一下掉血不另响，没有 impact）
    → 沿裂纹一波波岩柱爆开 rock_1..4（原作 rocksleep 起头那一下 + 自然衰减，4 个音高；fx strip pillar_break 节流 0.15 秒）。
    10-31 用户「奇怪的卡顿声」：原作 rocksleep / rockboost 是 2 秒连续碎石声，先前切成 0.5 秒碎段、0.07 秒连发听着像卡顿 → 改成每声完整一下；
    没有蓄力 charge（碎石磨擦声连续抖动）"""
    return {
        "sf": akd("p_skill_rocksleep.wav", 0.0, 0.45, 0.8, fout=0.25),
        "gather": akd("p_skill_rockboost.wav", 0.0, 0.5, fout=0.15),
        "slam": pad(akd("p_skill_jumphammer_2.wav", 0.0, 1.0, fout=0.4), lp(sn("b214", 0.25, 1.4, fout=0.6), 900) * 0.9),
        **{"rock_%d" % (i + 1): akd("p_skill_rocksleep.wav", 0.0, 0.45, r, fout=0.28) for i, r in enumerate([1.0, 1.08, 0.94, 1.15])},
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
