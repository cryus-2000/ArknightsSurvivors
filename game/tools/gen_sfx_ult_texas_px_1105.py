#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""德克萨斯终结技转平面版音效候选（docs/257 §8，11-05 用户「接下来的终结技都带音效来」）。
只用仓库已登记、有授权的录音（docs/113 §20：Sonniss GDC 2026 免版税可商用；Freesound 611310 CC0），不用原作客户端解包音源。
复用 gen_sfx_ult_seg_1030.py 的截取 / 响度工具（同一套 rms100 对齐 + 软限幅），输出到主仓库 build/ult_sfx_texas_px/（不进游戏，用户点头后 --apply 才写 game/audio/sfx/）。

槽（ult_audio.json texas）：
  charge   起手蓄力：原合成噪声扫频（4 kHz 以上占 76%）→ 长刃挥刮录音 3.5 kHz 低通、慢起
  mark_1..6 刀网每道一声出鞘：原 4 段轮用、6 道里有 2 对完全相同、重心 9–10 kHz 偏刺 → 同录音 5 kHz 低通、6 道各变一次调（×0.9–1.1），不再有重复的两声
  cut      斩线齐出（冲击帧第一拍）：原多层斩击 → 同录音 6 kHz 低通
  finale   最大那一下（新槽；亮核起爆那一拍）：斩击冲击头 + 预告片轰降调 ×0.78（拖长、低频余音盖住 0.53 秒慢动作 + 缓回）+ 低频垫底 300 Hz 低通，2.6 秒
  sheathe  收刀冲回原位（新槽）：长刃挥刮尾段降调 ×0.85、4 kHz 低通，0.4 秒
  sf / cast / impact 不动（impact 改由 finale 接管时音量下调 6 dB，避免两声同时打满）
用法：python game/tools/gen_sfx_ult_texas_px_1105.py [--apply]
"""
import argparse, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
_src = open(os.path.join(HERE, "gen_sfx_ult_seg_1030.py"), encoding="utf-8").read()
exec(_src[:_src.index("def texas():")])   # 工具函数 + lib / fsd / level / write

OUT2 = os.path.join(ROOT, "build", "ult_sfx_texas_px")


def tx_px():
    d = {}
    d["charge"] = fadeio(lp(lib(TX_SCRAPE, 0.0, 0.75, rate=0.9, fout=0.2), 3500) * swell(len(lib(TX_SCRAPE, 0.0, 0.75, rate=0.9)) / SR, 0.9), 0.15, 0.2)
    for i, t0 in enumerate(TX_DRAW):
        k = [0.92, 1.0, 1.08, 0.96, 1.04, 1.1][i]
        x = fsd(611310, t0, 0.4)
        x = pitch(x, k) if k != 1.0 else x
        d["mark_%d" % (i + 1)] = lp(x, 5000)
    d["cut"] = lp(lib(TX_SLICE, 0.29, 0.8, fout=0.3), 6000)
    head = lib(TX_HIT, 0.93, 1.2, fout=0.6)
    tail = lp(lib(TX_BOOM, 0.25, 2.0, rate=0.78, fout=1.2), 700)
    sub_ = lp(lib("Federico Soler - Effective Trailer Booms Vol. 2/EffectiveTrailer_Booms_Vol2_075.wav", 0.0, 2.2, rate=0.8, fout=1.4), 300)
    d["finale"] = fadeio(pad(head * 0.8, tail * 0.9, sub_ * 0.7), 0.002, 0.9)
    d["sheathe"] = lp(lib(TX_SCRAPE, 0.18, 0.42, rate=0.85, fout=0.2), 4000)
    return d


LV_NEW = {"finale": -8.0, "sheathe": -15.0}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true")
    a = ap.parse_args()
    out = os.path.join(ROOT, "game", "audio", "sfx") if a.apply else OUT2
    os.makedirs(out, exist_ok=True)
    for slot, x in tx_px().items():
        path = os.path.join(out, "ult_texas_%s.wav" % slot)
        if slot in LV_NEW:
            LV_SLOT[slot] = LV_NEW[slot]
        write(path, x, slot)
        print(path, "%.2f s" % (len(x) / SR))


if __name__ == "__main__":
    main()
