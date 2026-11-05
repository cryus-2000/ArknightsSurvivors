#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""星熊终结技「般若反震」转平面版的新音效候选（docs/254 §8，11-05 终结技画面升级任务单）。
用户口径：只用仓库已登记、有授权的录音（Sonniss GDC 2026 包，docs/113 §20），**不用原作客户端解出的音源**；
最大那一下（反震）要配合慢动作：拉长的低频余音；高频收着；响度照 docs/113 的口径（rms100 + 软限幅，boom 槽 -9）。

只重做 boom（原来那一声叠了两层原作素材 p_skill_fireboomexplo / p_skill_robotexplo，按新口径不能用）；
另加一声收尾 settle（碎石落地 + 低频回落）。其余槽（sf / charge / cast / pull / block / crack_1..5 / sizzle）原来就全是授权录音，照用。

用法（游戏目录 game/）：python tools/gen_sfx_ult_hoshiguma_1105.py [--apply]
    缺省写候选到 <主仓库>/build/ult_sfx/hoshiguma_1105/；--apply 写进 audio/sfx/（用户点头后）。
"""
import argparse, os, sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_sfx_ult_seg_1030 as G


def delay(x, sec):
    return np.concatenate([np.zeros(int(sec * G.SR)), x])


def boom():
    """反震（冲击帧同帧，全招最响）：
    ① 斩击冲击瞬态：CSD「Impact Cut Sweep」0.93 s 起 1.4 s，降调 ×0.8，4 kHz 低通（收高频）；
    ② 低频主体：Federico Soler「EffectiveTrailer_Booms_Vol2_214」0.25 s 起 1.6 s，**放慢 ×0.68**（变成约 2.35 s 的长低频余音，配慢动作），700 Hz 低通；
    ③ 盾甲崩开的碎裂：Kopeikin「ice, surface cracking, fissure, fast, hard-003」0.9 s，×0.7，3.5 kHz 低通，0.5 倍；
    ④ 实心炸开：ESM「EXPLDsgn_Explosion Small Blast…03」1.0 s，×0.8，3 kHz 低通，0.45 倍；
    ⑤ 碎石回落的尾巴：CSD「Woosh Debris」0.3 s 起 2.0 s，×0.75，1.2 kHz 低通，0.35 倍，晚 0.18 s。"""
    R = 0.8
    a = G.lp(G.sn("cut", 0.93, 1.4, R, fout=0.5), 4000)
    b = G.lp(G.sn("b214", 0.25, 1.6, 0.68, fout=1.0), 700) * 1.25
    c = G.lp(G.sn("fissure", 0.0, 0.9, 0.7, fout=0.3), 3500) * 0.5
    d = G.lp(G.sn("blast", 0.0, 1.0, R, fout=0.4), 3000) * 0.45
    e = delay(G.lp(G.sn("debris", 0.3, 2.0, 0.75, fout=1.0), 1200) * 0.35, 0.18)
    return G.pad(a, b, c, d, e)


def settle():
    """收尾（反震后约 1 秒，碎石落地、灰尘散开）：CSD「Woosh Debris」1.2 s 起 1.0 s，×0.7，900 Hz 低通 + 一点低频回落（Booms_214 尾段 ×0.6）"""
    a = G.lp(G.sn("debris", 1.2, 1.0, 0.7, fout=0.5), 900)
    b = G.lp(G.sn("b214", 1.2, 1.0, 0.6, fout=0.6), 400) * 0.6
    return G.pad(a, b)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true")
    a = ap.parse_args()
    out = G.SFX if a.apply else os.path.join(G.ROOT, "build", "ult_sfx", "hoshiguma_1105")
    os.makedirs(out, exist_ok=True)
    G.RMS["boom"] = -9.0                                        # docs/113：高潮槽 -9
    G.RMS["settle"] = -17.0                                     # 收尾压在底下，不抢反震
    for slot, x in (("boom", boom()), ("settle", settle())):
        pk = G.write(os.path.join(out, "ult_hoshiguma_%s.wav" % slot), np.asarray(x, dtype=np.float64), slot)
        print(slot, "%.2f" % pk, os.path.join(out, "ult_hoshiguma_%s.wav" % slot))


if __name__ == "__main__":
    main()
