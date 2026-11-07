#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""羁绊技（docs/294）转平面帧条烘焙：只烤羁绊技自己要的新件，其余直接借各干员已有的技能帧条（fx_bond2.gd 里按键名推）。
现在只有企鹅物流的炸弹：pixelfx 爆炸（tools/pixelfx_fx/explosions/ak-bond-bomb.js，库自带 small-explosion 去掉冲击环细线）。
输出 game/art/fx/pxp/pxp_bd_<键>.png + game/data/pxp_bond2.json（fx_pxplane.METAS 前缀 bd_）。.import 交给 Godot 生成（别手写 uid）。
用法（仓库根目录）：python tools/pxplane_bake_bond2.py"""
import json, os, shutil, subprocess, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pxplane_bake as pb

ROOT = pb.ROOT
META = os.path.join(ROOT, "game", "data", "pxp_bond2.json")
FX = [("explosions", "ak-bond-bomb")]


def variants():
    v = []
    for i, sd in enumerate((7, 13, 21)):   # 三个变体（每颗炸弹挑一个，免得一模一样）
        v.append(("bomb_v%d" % i, "explosions/ak-bond-bomb", {"size": 1.8, "seed": sd, "rings": 0}, 1.3))
    return v


def render(key, fx_id, opts, dur):
    d = os.path.join(pb.TMP, "bond2", key)
    os.makedirs(d, exist_ok=True)
    p = subprocess.run(["node", "tools/ak_layers.mjs", fx_id, "--out", d, "--fps", str(pb.FPS), "--opts", json.dumps(opts)], cwd=pb.PFX, capture_output=True, text=True)
    if p.returncode != 0:
        raise RuntimeError(key + ": " + p.stderr[-400:])
    return d


def main():
    for sub, fn in FX:
        shutil.copy(os.path.join(ROOT, "tools", "pixelfx_fx", sub, fn + ".js"), os.path.join(pb.PFX, "src", "fx", sub, fn + ".js"))
    pb.PREFIX = "bd_"
    pb.ACC_RG = []
    os.makedirs(pb.OUT_ART, exist_ok=True)
    reg = {}
    for key, fx_id, opts, dur in variants():
        d = render(key, fx_id, opts, dur)
        k, m = pb.bake(key, d, dur)
        if m is None:
            print("空", k)
            continue
        reg[k] = m
        print("%-12s %2d 帧 %3d×%3d emit %d" % (k, m["n"], m["w"], m["h"], max((len(e) for e in m["emit"]), default=0)))
    reg["_doc"] = "docs/294 羁绊技转平面帧条（tools/pxplane_bake_bond2.py 生成，勿手改）：键加前缀 bd_ 对应 art/fx/pxp/pxp_bd_<键>.png；n 帧数、fps、w×h、ox / oy 原点（地面点）、loop、emit"
    with open(META, "w", encoding="utf-8", newline="\n") as f:
        json.dump(reg, f, ensure_ascii=False, separators=(",", ":"))


if __name__ == "__main__":
    main()
