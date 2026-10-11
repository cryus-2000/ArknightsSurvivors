# -*- coding: utf-8 -*-
"""水月肉鸽式「潮位」难度阶梯概念图（docs/71，2026-10-12 用户：「修改成水月肉鸽的风格」，奖励只给荣誉）。
只是概念图，不改游戏代码。画法沿用 T5s（docs/67 §12 / docs/37 §8）与 docs/68 的概念工具（tools/concept_contracts.py 的小件直接复用）。

另外做三件事（不开 Godot）：
1. 把 docs/71 §2 的阶梯表（下面 LADDER）逐级累加成修正表，和 game/data/balance.json difficulty/standard | hard | extreme
   （经 data.gd dmod_for_level 拼底）逐键核对：潮位 0 = 标准、潮位 4 = 现行 IV 逐键相等；潮位 8 = 现行 VIII + IV 的「寒流」两键
   （ctrl_start 300、frost_max 2，docs/71 §2.3 的修正，需云端确认）——工具把差异逐键打印出来。
2. 检查阶梯是「严格累加」的：每一级只加键或把已有键往更难的方向推（补偿键除外，单列）。
3. 打印每一级在现有代码上复现用的 `--bal` 参数（docs/71 §5 的扫描直接用；领潮者用全局 enemy/elite_*_mult 代替新键），
   写进 build/is3_levels/sweep_extra.txt。

用法：
    python tools/concept_is3_levels.py
输出（不入库）：主仓库 build/is3_levels/
    is3_levels_desktop.png         桌面 · 选择潮位（选中 8，已解锁到 9）
    is3_levels_desktop_locked.png  桌面 · 选中未解锁的 11
    is3_levels_phone.png           手机 · 选择潮位（1480×720 屏幕像素，UI 逻辑约 1044×481）
    is3_levels_settlement.png      胜利结算 · 潮位与本级新规则、纪录、解锁下一级
    is3_levels_badges.png          选人 / 图鉴 · 潮位徽记与分段
    is3_levels_table.png           阶梯总表（级 / 名 / 新规则 / 旋钮）
    contact_sheet.png              总览
    sweep_extra.txt                每一级的 --bal 参数
"""
import json, math, os, sys

import numpy as np
from PIL import Image, ImageDraw

TOOLS = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, TOOLS)
import concept_contracts as cc  # noqa: E402
from concept_contracts import c1, panel, sel_block, chip, ticon, wrap, GOLD, DIM, STEEL, N_ACT  # noqa: E402
from concept_title_ui_v4 import snap, stair, edge_of, dith, paint, solid, glow, ripple, ptxt, WATER, EDGE, N_TONES, FOAM  # noqa: E402
from concept_title_ui_v2 import CY, CY_DIM, TXT, TXT2, text  # noqa: E402
from concept_title_ui_v5 import NEAR_WHITE, NAVY_INK, SEL_EDGE, SEL_SUB, SEL_IDX, TIDE_GLOW, FOAM_GLOW  # noqa: E402

ROOT = cc.ROOT
MAIN = cc.MAIN
OUT = os.path.join(MAIN, "build", "is3_levels")
W, H = 1280, 720
PHW, PHH = 1480, 720
RELIEF = (140, 220, 200)
LOCK_T = (84, 98, 116)

# ---------------------------------------------------------------- docs/71 §2 阶梯表（与文档一致）
# set：这一级写入的 dmod 键（逐级覆盖，后一级把同一键推得更难 = 「加重」）；relief：其中属于补偿（放宽）的键，规则行不写、修正列表绿色列出
# grp：规则颜色（同 docs/68 组色）；preset：现行推荐档；new：要新旋钮
LADDER = [
    {"lv": 0, "cn": "海面", "en": "SURFACE", "grp": None, "set": {},
     "rule": "没有额外规则：深海原本的样子。", "short": "无额外规则", "lore": "海洋的真容，才刚刚显露。"},
    {"lv": 1, "cn": "巨影", "en": "LOOMING", "grp": "boss", "set": {"boss_hp": 1.15, "boss_warn": 0.85},
     "rule": "Boss 生命 +15%，Boss 招式预警缩短 15%。", "short": "Boss 生命 +15% · 预警 -15%", "lore": "水下有什么庞大的东西翻了个身。"},
    {"lv": 2, "cn": "昏灯", "en": "DIM LAMP", "grp": "lamp", "set": {"lamp_hit": 1.3, "oil_drop": 0.7, "ingot": 0.9},
     "rule": "受击时灯火损失 +30%；灯油掉落 -30%，源石锭掉落 -10%。", "short": "灯火损失 +30% · 灯油 -30% · 锭 -10%", "lore": "灯油见底，火苗缩成一粒豆。"},
    {"lv": 3, "cn": "暗涌", "en": "UNDERTOW", "grp": "horde",
     "set": {"enemy_hp": 1.2, "enemy_dmg": 1.2, "hunt_dur": 0.85, "hunt_ring_hp": 0.85, "beacon_every": 0.8},
     "relief": ["hunt_dur", "hunt_ring_hp", "beacon_every"],
     "rule": "敌人生命与造成的伤害 +20%。", "short": "敌人生命 / 伤害 +20%", "lore": "水面平静，脚下的水却在拽人。"},
    {"lv": 4, "cn": "寒流", "en": "COLD CURRENT", "grp": "env", "set": {"horde": 1.2, "ctrl_start": 300, "frost_max": 2}, "preset": "IV",
     "rule": "大群规模 +20%；小怪控制提前到 5:00，寒霜 2 层即冻结。", "short": "大群 +20% · 控制 5:00 · 2 层冻结", "lore": "暗礁更多，灯火更难守住。"},
    {"lv": 5, "cn": "搁浅", "en": "STRANDED", "grp": "lamp", "set": {"max_hp": 0.9, "oil_drop": 0.6, "ingot": 0.75},
     "rule": "主控初始最大生命 -10%；灯油掉落加重到 -40%，源石锭加重到 -25%。", "short": "最大生命 -10% · 灯油 -40% · 锭 -25%", "lore": "补给船没有回来。"},
    {"lv": 6, "cn": "渊影", "en": "ABYSSAL SHADOW", "grp": "boss", "set": {"boss_hp": 1.35, "boss_warn": 0.8, "boss_dmg": 1.15},
     "rule": "Boss 生命加重到 +35%，预警缩短加重到 20%；Boss 造成的伤害再 +15%。", "short": "Boss 生命 +35% · 预警 -20% · 伤害 +15%", "lore": "巨影浮近，出手不再迟疑。"},
    {"lv": 7, "cn": "甲潮", "en": "HARD SHELL", "grp": "horde",
     "set": {"enemy_hp": 1.7, "enemy_dmg": 1.25, "hunt_dur": 0.7, "hunt_ring_hp": 0.7, "boss_fight_enemy_hp": 1.0},
     "relief": ["hunt_dur", "hunt_ring_hp", "boss_fight_enemy_hp"],
     "rule": "敌人生命加重到 +70%，造成的伤害加重到 +25%。", "short": "敌人生命 +70% · 伤害 +25%", "lore": "海嗣披上了更厚的壳。"},
    {"lv": 8, "cn": "漫灌", "en": "FLOOD", "grp": "env", "set": {"mire_permanent": 1, "beacon_every": 0.6, "horde": 1.6, "horde_in_boss": 1},
     "relief": ["beacon_every"], "preset": "VIII",
     "rule": "自然溟痕常驻，只有引航灯标能驱散；大群加重到 +60%，Boss 在场时照常来袭。", "short": "溟痕常驻 · 大群 +60% · Boss 战照常来袭",
     "lore": "大海不再留情。"},
    {"lv": 9, "cn": "夜潮", "en": "NIGHT TIDE", "grp": "time", "set": {"dmg_late_cap": 0.5},
     "rule": "后期敌人伤害的成长上限从 +25% 提高到 +50%。", "short": "后期伤害上限 +50%", "lore": "入夜之后，潮水只会更凶。"},
    {"lv": 10, "cn": "残烛", "en": "GUTTERING", "grp": "lamp", "set": {"lamp_hit": 1.6, "oil_drop": 0.4},
     "rule": "受击时灯火损失加重到 +60%，灯油掉落加重到 -60%。", "short": "灯火损失 +60% · 灯油 -60%", "lore": "每受一次伤，灯就暗一分。"},
    {"lv": 11, "cn": "领潮者", "en": "TIDE LORDS", "grp": "boss", "set": {"elite_hp": 1.25, "elite_dmg": 1.25}, "new": True,
     "rule": "精英生命与造成的伤害 +25%。", "short": "精英生命 / 伤害 +25%", "lore": "群潮之中，有了领头的。"},
    {"lv": 12, "cn": "异变", "en": "MUTATION", "grp": "horde", "set": {"affix_start": 300, "affix_max": 0.5},
     "rule": "带词条的海嗣提前到 5:00 出现，词条概率上限从 35% 提高到 50%。", "short": "词条 5:00 起 · 上限 50%", "lore": "它们变得太快了。"},
    {"lv": 13, "cn": "深压", "en": "DEEP PRESSURE", "grp": "lamp", "set": {"max_hp": 0.8},
     "rule": "主控初始最大生命加重到 -20%。", "short": "最大生命 -20%", "lore": "越往下，水越沉。"},
    {"lv": 14, "cn": "渊主", "en": "ABYSS LORD", "grp": "boss", "set": {"final_boss_hp": 1.3},
     "rule": "最终 Boss 生命再 +30%。", "short": "最终 Boss 生命 +30%", "lore": "深处的主人不会轻易倒下。"},
    {"lv": 15, "cn": "潮不止息", "en": "ENDLESS TIDE", "grp": "time", "set": {"final_stop_mobs": 0},
     "rule": "最终 Boss 在场时，海嗣照常涌来。", "short": "最终 Boss 战照常刷怪", "lore": "潮水没有尽头。"},
]
N = len(LADDER) - 1
GCOL = dict(cc.GRP_COL)
NEW_KEYS = {"elite_hp": 1.0, "elite_dmg": 1.0}          # docs/71 §2.4 新旋钮（DMOD_DEFAULT 里还没有）
# 「更难」的方向：大于缺省更难的键（其余是越小越难）；绝对值键（-1 = 用全局）单独比较
HARDER_UP = {"enemy_hp", "enemy_dmg", "boss_hp", "boss_dmg", "lamp_hit", "horde", "horde_in_boss", "mire_permanent", "mire_dmg",
             "nerve_rate", "final_boss_hp", "elite_hp", "elite_dmg", "affix_max", "dmg_late_cap"}
ABS_GLOBAL = {"ctrl_start": 400.0, "frost_max": 3.0, "affix_start": 420.0, "affix_max": 0.35, "dmg_late_cap": 0.25,
              "final_stop_mobs": 1.0}                    # balance.json enemy / final 段的全局值（-1 时用它）


def compose(n):
    """潮位 n 的修正表：DMOD_DEFAULT 起，逐级写入 1..n 的键（同一键后写覆盖）"""
    m = cc.dmod_default()
    m.update(NEW_KEYS)
    for L in LADDER[1:n + 1]:
        for k, v in L["set"].items():
            m[k] = float(v)
    return m


def eff(k, v):
    return ABS_GLOBAL[k] if (k in ABS_GLOBAL and v < 0) else v


def verify():
    base = cc.dmod_default()
    bal = json.load(open(os.path.join(ROOT, "game", "data", "balance.json"), encoding="utf-8"))["difficulty"]
    report = []
    for key, lvl in (("standard", 0), ("hard", 4), ("extreme", 8)):
        tier = cc.dmod_for_level(lvl, base)
        for k, v in bal.get(key, {}).items():
            if k in tier:
                tier[k] = float(v)
        lad = compose(lvl)
        bad = [k for k in tier if abs(float(tier[k]) - float(lad[k])) > 1e-6]
        msg = "逐键一致" if not bad else "差异：" + "、".join("%s 现表 %g → 阶梯 %g" % (k, tier[k], lad[k]) for k in bad)
        print("潮位 %d 对 现行 %-8s %s" % (lvl, key, msg))
        report.append((lvl, key, bad))
    # 严格累加：每一级写的键要么新加、要么往更难推（补偿键除外）
    ok = True
    for i, L in enumerate(LADDER[1:], 1):
        prev = compose(i - 1)
        for k, v in L["set"].items():
            if k in L.get("relief", []):
                continue
            a, b = eff(k, prev[k]), eff(k, float(v))
            if k == "final_stop_mobs":
                harder = b < a
            elif k in ("ctrl_start", "affix_start", "frost_max"):
                harder = b < a
            elif k in HARDER_UP:
                harder = b > a
            else:
                harder = b < a
            if not harder:
                print("  !! 潮位 %d 的 %s %g → %g 不是更难" % (i, k, a, b))
                ok = False
    print("严格累加检查：" + ("通过（每级只加规则或加重已有规则；补偿键单列）" if ok else "未通过"))
    return report, ok


def bal_args(n):
    """在现有代码上复现潮位 n：--tier=0 + difficulty/standard 覆盖；领潮者用全局 enemy/elite_*_mult 代替新键"""
    base = cc.dmod_default()
    m = compose(n)
    out = ["--tier=0"]
    for k in sorted(m):
        if k in NEW_KEYS:
            continue
        if abs(float(m[k]) - float(base.get(k, m[k]))) > 1e-9:
            out.append("--bal=difficulty/standard/%s=%g" % (k, m[k]))
    if m["elite_hp"] != 1.0:
        out.append("--bal=enemy/elite_hp_mult=%g" % (7.0 * m["elite_hp"]))
        out.append("--bal=enemy/elite_dmg_mult=%g" % (1.3 * m["elite_dmg"]))
    return " ".join(out)


def rule_lines(sel):
    """潮位 sel 的累计规则：[(级, 是否新增, 状态, 加重到的级)]；状态 full = 已被后级完全加重，part = 部分加重"""
    out = []
    for L in LADDER[1:sel + 1]:
        keys = [k for k in L["set"] if k not in L.get("relief", [])]
        later = {}
        for L2 in LADDER[L["lv"] + 1:sel + 1]:
            for k in keys:
                if k in L2["set"] and k not in later:
                    later[k] = L2["lv"]
        st = "full" if keys and len(later) == len(keys) else ("part" if later else "")
        out.append((L, L["lv"] == sel, st, min(later.values()) if later else None))
    return out


def relief_text(m):
    r = []
    if m["hunt_dur"] < 0.9999:
        r.append("围猎时长与圈上海嗣生命 -%d%%" % round((1 - m["hunt_dur"]) * 100))
    if m["beacon_every"] < 0.9999:
        r.append("引航灯标刷新间隔 -%d%%" % round((1 - m["beacon_every"]) * 100))
    if m["boss_fight_enemy_hp"] >= 0:
        r.append("终局新刷杂兵生命不加成")
    return "补偿：" + "，".join(r) if r else ""


# ---------------------------------------------------------------- 小件
def lock_icon(img, cx, cy, k, col):
    pat = [".####.", "#....#", "#....#", "######", "######", "##..##", "######"]
    d = ImageDraw.Draw(img)
    x0, y0 = int(cx - 3 * k), int(cy - 3.5 * k)
    for r, row in enumerate(pat):
        for c, ch in enumerate(row):
            if ch == "#":
                d.rectangle([x0 + c * k, y0 + r * k, x0 + c * k + k - 1, y0 + r * k + k - 1], fill=col)


def lv2(i):
    return "%02d" % i


def badge(img, cx, cy, r, k=2):
    """潮位徽记：像素六边盾 + 数字。分段：未通关 / 0–3 钢蓝 / 4–7 潮水 / 8–11 S4 反白 / 12–14 反白 + 潮线 / 15 反白 + 泡沫光"""
    pat = ["....######....", "..##########..", ".############.", "##############", "##############", "##############",
           "##############", "##############", ".############.", "..##########..", "....######....", ".....####....."]
    hgt, wid = len(pat), len(pat[0])
    m = np.array([[ch == "#" for ch in row] for row in pat])
    e = m & ~(np.roll(m, 1, 0) & np.roll(m, -1, 0) & np.roll(m, 1, 1) & np.roll(m, -1, 1))
    if r is None:
        fill, edge, num = (14, 26, 44), (60, 74, 92), (90, 104, 120)
    elif r < 4:
        fill, edge, num = (14, 30, 52), STEEL, (180, 196, 214)
    elif r < 8:
        fill, edge, num = (24, 92, 118), CY, (220, 255, 255)
    else:
        fill, edge, num = NEAR_WHITE, SEL_EDGE, NAVY_INK
    arr = np.zeros((hgt, wid, 4), np.uint8)
    arr[m] = fill + (255,)
    arr[e] = edge + (255,)
    if r is not None and r >= 12:
        band = np.zeros_like(m)
        band[8:10, :] = True
        arr[band & m & ~e] = (90, 200, 230, 255)
    im = Image.fromarray(arr, "RGBA").resize((wid * k, hgt * k), Image.NEAREST)
    x0, y0 = int(cx - wid * k / 2), int(cy - hgt * k / 2)
    if r is not None and r >= N:
        gm = Image.new("L", img.size, 0)
        gm.paste(im.getchannel("A"), (x0, y0))
        glow(img, gm, FOAM_GLOW, 3 * k, (0.08, 0.3), (50, 110), cell=k)
    img.alpha_composite(im, (x0, y0))
    ptxt(img, (cx, cy - k), "-" if r is None else str(r), max(1, k // 2), num, 1, "mm")


def gauge(img, box, ys, sel, best=None, P=2, labels=(0, 4, 8, 12, 15)):
    """竖潮位尺：刻度对齐每一级的行中心，水位停在选中级；best = 当前主控最佳（金色虚线）"""
    (bx0, by0, bx1, by1), gm = panel(img, box, P, 3)
    lvl = snap(ys[sel], P)
    h, w = gm.shape
    yy, xx = np.mgrid[0:h, 0:w]
    gxx = (xx + bx0) // P
    wave = (np.round(np.sin(gxx * 0.7) * 0.8) * P).astype(int)
    wm = gm & (yy >= (lvl - by0) + wave) & ~edge_of(gm, P)
    wl = dith(bx0, by0, w, h, P, lambda cx, cy: np.clip((cy - (lvl - by0)) / 300 * 2.2, 0, 2))
    paint(img, bx0, by0, wm, wl, WATER, 240)
    top = wm & ~np.roll(wm, P, axis=0)
    solid(img, bx0, by0, top, FOAM + (230,))
    d = ImageDraw.Draw(img)
    for i, y in ys.items():
        y = snap(y, P)
        major = i in labels
        L = (5 if major else 3) * P
        d.rectangle([bx1 - 3 * P - L, y, bx1 - 3 * P - 1, y + P - 1], fill=CY if i == sel else CY_DIM)
        if major:
            ptxt(img, (bx0 + 4 * P, y), str(i), 1, TXT if i <= sel else TXT2, 1, "lm")
    if best is not None:
        y = snap(ys[best], P) + 2 * P
        for x in range(bx0 + 3 * P, bx1 - 3 * P, 3 * P):
            d.rectangle([x, y, x + P * 2 - 1, y + P - 1], fill=GOLD)
    ripple(img, (bx0 + bx1) / 2, lvl, P, 0.6, gm, (bx0, by0))
    # 指针：尺 → 选中行
    d.polygon([(bx1 + 2, lvl), (bx1 + 10, lvl - 5), (bx1 + 10, lvl + 5)], fill=SEL_EDGE)
    return (bx0, by0, bx1, by1)


def level_row(img, box, L, state, s=1.0, P=2, compact=False):
    """一行：编号 + 名 + 本级新规则（短）+ 状态。state：sel / open / clear / best / locked / next_locked"""
    x0, y0, x1, y1 = [snap(v, P) for v in box]
    hgt = y1 - y0
    cy = (y0 + y1) / 2
    gc = GCOL.get(L["grp"], STEEL)
    locked = state in ("locked", "next_locked")
    if state == "sel":
        sel_block(img, (x0, y0, x1, y1), P, 2, water=0.18, glow_on=True)
        tc, sc, nc = NAVY_INK, SEL_SUB, SEL_IDX
    else:
        (x0, y0, x1, y1), _ = panel(img, (x0, y0, x1, y1), P, 2, N_TONES, 150 if locked else 214,
                                    (EDGE + (110,)) if locked else (EDGE + (180,)))
        tc, sc, nc = (TXT, TXT2, CY) if not locked else ((104, 118, 136), LOCK_T, (70, 92, 112))
    d = ImageDraw.Draw(img)
    if not locked and L["grp"]:
        d.rectangle([x0 + 2 * P, y0 + 3 * P, x0 + 3 * P - 1, y1 - 3 * P], fill=gc if state != "sel" else (30, 150, 180))
    ps = 2 if (hgt >= 30 or s > 1) else 1
    ptxt(img, (x0 + int(12 * s), cy), lv2(L["lv"]), ps, nc, 1, "lm")
    tx = x0 + int(48 * s)
    wn = text(img, (tx, cy), L["cn"], int(15 * s), tc, "lm", bold=True)
    rx = tx + max(wn, int(64 * s)) + int(10 * s)
    tag_w = 0
    if L.get("preset"):
        tw = len(L["preset"]) * int(7 * (1 if s < 1.3 else 2)) + 10
        tag_w = tw + 8
        bx = x1 - int(12 * s) - tw - (int(46 * s) if state in ("clear", "best") else 0)
        col = (120, 140, 160) if state != "sel" else (80, 104, 124)
        d.rectangle([bx, cy - 8 * (1 if s < 1.3 else 1.5), bx + tw, cy + 7 * (1 if s < 1.3 else 1.5)], outline=col)
        ptxt(img, (bx + tw / 2, cy), L["preset"], 1 if s < 1.3 else 2, col, 1, "mm")
    if locked:
        lock_icon(img, x1 - int(18 * s), cy, 2 if s < 1.3 else 3, (84, 100, 120))
        if not compact:
            text(img, (rx, cy), "通关上一级解锁" if state == "next_locked" else L["short"], int(12.5 * s),
                 (124, 140, 160) if state == "next_locked" else (74, 88, 106), "lm")
    else:
        if not compact:
            lim = x1 - rx - int(70 * s) - tag_w
            st = L["short"]
            while c1.F(int(12.5 * s), st).getlength(st) > lim and len(st) > 4:
                st = st[:-2] + "…"
            text(img, (rx, cy), st, int(12.5 * s), sc, "lm")
        if state == "clear":
            ptxt(img, (x1 - int(12 * s), cy), "CLEAR", 1, CY_DIM, 1, "rm")
        elif state == "best":
            ptxt(img, (x1 - int(12 * s), cy), "BEST", 1, GOLD, 1, "rm")
        elif L.get("new") and state != "sel":
            pass
    return (x0, y0, x1, y1)


def row_state(i, sel, unlocked, best, cleared):
    if i == sel:
        return "sel"
    if i > unlocked:
        return "next_locked" if i == unlocked + 1 else "locked"
    if best is not None and i == best:
        return "best"
    if i <= cleared:
        return "clear"
    return "open"


def header(img, cn, en, x=28, s=1.0, sub="OPERATION // TIDE LEVEL"):
    ptxt(img, (x, int(30 * s)), sub, 1, CY, 1, "lm")
    w = text(img, (x, int(60 * s)), cn, int(26 * s), TXT, "lm", bold=True)
    ptxt(img, (x + w + 14, int(62 * s)), en, 2, TXT2, 2, "lm")
    return w


def level_file(img, box, sel, unlocked, op_name, op_best, all_best, all_name, P=2, s=1.0, two_col=False):
    """右侧「潮位档案」：大号编号 + 名 + 一句话；累计规则（新增那条反白）；补偿；纪录与解锁"""
    x0, y0, x1, y1 = box
    panel(img, box, P, 3, a=236)
    L = LADDER[sel]
    locked = sel > unlocked
    ptxt(img, (x0 + 22 * s, y0 + 22 * s), "LEVEL FILE // TIDE %s" % lv2(sel), 1, CY, 1, "lm")
    if L.get("preset"):
        ptxt(img, (x1 - 22 * s, y0 + 22 * s), "= RISING TIDE %s" % L["preset"], 1, TXT2, 1, "rm")
    ptxt(img, (x0 + 22 * s, y0 + 66 * s), lv2(sel), 5 if s < 1.3 else 6, TXT if not locked else TXT2, 1, "lm")
    nx = x0 + int(118 * s) if s < 1.3 else x0 + int(140 * s)
    wn = text(img, (nx, y0 + 54 * s), L["cn"], int(28 * s), TXT if not locked else TXT2, "lm", bold=True)
    ptxt(img, (nx + wn + 12, y0 + 56 * s), L["en"], 2 if s < 1.3 else 3, TXT2, 2, "lm")
    text(img, (nx, y0 + 86 * s), L["lore"], int(14 * s), TXT2, "lm")
    d = ImageDraw.Draw(img)
    yl = y0 + int(112 * s)
    d.rectangle([x0 + 22 * s, yl, x1 - 22 * s, yl + 1], fill=(40, 80, 104))
    lines = rule_lines(sel)
    ptxt(img, (x0 + 22 * s, yl + 18 * s), "RULES", 1, TXT2, 1, "lm")
    text(img, (x0 + 80 * s, yl + 18 * s), "累计规则 %d 条 · 本级新增 1 条（反白）· 灰字 = 已被后一级加重" % len(lines) if sel else "潮位 0：没有额外规则",
         int(12 * s), TXT2, "lm")
    m = compose(sel)
    rel = relief_text(m)
    foot = int(64 * s)
    avail = (y1 - foot) - (yl + 34 * s) - (22 * s if rel else 0)
    cols = 2 if two_col else 1
    per = math.ceil(len(lines) / cols) if lines else 1
    lh = min(int(30 * s), int(avail / max(1, per)))
    cw = (x1 - x0 - 44 * s) / cols
    for i, (R, is_new, st, to) in enumerate(lines):
        cx = x0 + 22 * s + (i // per) * cw
        y = yl + 34 * s + (i % per) * lh
        hh = lh - 4
        if is_new:
            sel_block(img, (cx - 4, y, cx + cw - 8, y + hh), P, 2, water=0.0, glow_on=False)
            tc, nc = NAVY_INK, SEL_IDX
        else:
            tc = TXT if not st else ((150, 164, 180) if st == "part" else (84, 100, 120))
            nc = CY if not st else (70, 100, 120)
        cyy = y + hh / 2
        ptxt(img, (cx + 4, cyy), lv2(R["lv"]), 1, nc, 1, "lm")
        if R["grp"]:
            d.rectangle([cx + 24, cyy - 6, cx + 26, cyy + 5], fill=GCOL[R["grp"]] if not st or is_new else (60, 76, 92))
        tw = text(img, (cx + 34, cyy), R["cn"], int(13.5 * s), tc, "lm", bold=True)
        body = R["short"] if two_col else R["rule"]
        lim = cw - (34 + tw + 12) - (64 if (st and not is_new) else 14)
        while c1.F(int(13 * s), body).getlength(body) > lim and len(body) > 4:
            body = body[:-2] + "…"
        text(img, (cx + 34 + tw + 10, cyy), body, int(13 * s), tc, "lm")
        if is_new:
            ptxt(img, (cx + cw - 16, cyy), "NEW", 1, SEL_IDX, 1, "rm")
        elif st:
            ptxt(img, (cx + cw - 16, cyy), "→ %s" % lv2(to), 1, nc, 1, "rm")
        if R.get("new") and not two_col:
            ptxt(img, (cx + cw - 52, cyy), "KNOB", 1, (255, 150, 180) if not is_new else (200, 60, 110), 1, "rm")
    if rel:
        ry = yl + 34 * s + per * lh + 8
        d.rectangle([x0 + 22 * s, ry - 3, x0 + 22 * s + 3, ry + 2], fill=(60, 200, 150))
        text(img, (x0 + 32 * s, ry), rel, int(12 * s), RELIEF, "lm")
    # 纪录 / 解锁
    fy = y1 - foot / 2 - 4
    d.rectangle([x0 + 22 * s, y1 - foot, x1 - 22 * s, y1 - foot + 1], fill=(40, 80, 104))
    badge(img, x0 + 40 * s, fy, op_best, k=2 if s < 1.3 else 3)
    w1 = text(img, (x0 + 62 * s, fy - 10 * s), "%s 最佳潮位 %s" % (op_name, "-" if op_best is None else op_best), int(14 * s), GOLD, "lm")
    text(img, (x0 + 62 * s, fy + 11 * s), "全干员最佳 %d（%s）" % (all_best, all_name), int(12.5 * s), TXT2, "lm")
    if locked:
        lock_icon(img, x1 - 250 * s, fy, 2 if s < 1.3 else 3, (255, 150, 180))
        text(img, (x1 - 236 * s, fy - 9 * s), "通关潮位 %d 后解锁" % (sel - 1), int(14 * s), (255, 170, 190), "lm")
        text(img, (x1 - 236 * s, fy + 11 * s), "现已解锁到潮位 %d · 可先查看规则" % unlocked, int(12 * s), TXT2, "lm")
    elif sel == unlocked and sel < N:
        text(img, (x1 - 22 * s, fy - 9 * s), "通关本级 → 解锁潮位 %d「%s」" % (sel + 1, LADDER[sel + 1]["cn"]), int(13 * s), CY, "rm")
        text(img, (x1 - 22 * s, fy + 11 * s), "任一结局都算 · Boss 演练与练习不算", int(12 * s), TXT2, "rm")
    else:
        text(img, (x1 - 22 * s, fy - 9 * s), "已解锁到潮位 %d" % unlocked, int(13 * s), TXT2, "rm")
        text(img, (x1 - 22 * s, fy + 11 * s), "任一结局都算 · Boss 演练与练习不算", int(12 * s), TXT2, "rm")


def depart(img, box, locked, label="出发", s=1.0, P=2):
    (ox0, oy0, ox1, oy1), om = panel(img, box, P, 3, a=240)
    d = ImageDraw.Draw(img)
    if locked:
        solid(img, ox0, oy0, edge_of(om, P), (70, 84, 100))
        lock_icon(img, ox0 + 30 * s, (oy0 + oy1) / 2, 2 if s < 1.3 else 3, (110, 124, 140))
        text(img, (ox0 + 56 * s, (oy0 + oy1) / 2), "未解锁", int(22 * s), (120, 134, 150), "lm", bold=True)
        return
    solid(img, ox0, oy0, edge_of(om, P), CY)
    text(img, (ox0 + 64 * s, (oy0 + oy1) / 2), label, int(24 * s), TXT, "lm", bold=True)
    for i in range(3):
        xx = ox0 + 22 * s + i * 9 * s
        d.line([(xx, oy0 + 20 * s), (xx + 7 * s, (oy0 + oy1) / 2), (xx, oy1 - 20 * s)], fill=CY, width=2 if s < 1.3 else 3)
    if s < 1.3:
        ptxt(img, (ox1 - 16, (oy0 + oy1) / 2), "ENTER", 1, TXT2, 1, "rm")


# ---------------------------------------------------------------- 1. 桌面 · 选择潮位
def page_desktop(sel=8, unlocked=9, op_best=6, cleared=8):
    img = cc.bg(k=150)
    header(img, "选择潮位", "TIDE LEVEL")
    text(img, (1256, 50), "波涛迭起 · 逐级叠加：每升一级加一条新规则，前面的规则全部保留", 13, TXT2, "rm")
    text(img, (1256, 72), "通关一级解锁下一级 · 奖励只有荣誉", 13, TXT2, "rm")
    y0, rh, g = 100, 33, 2
    ys = {i: y0 + (N - i) * (rh + g) + rh / 2 for i in range(N + 1)}
    gauge(img, (24, 96, 92, 664), ys, sel, best=op_best)
    for i in range(N + 1):
        st = row_state(i, sel, unlocked, op_best, cleared)
        x1 = 562 if st == "sel" else 548
        level_row(img, (112, ys[i] - rh / 2, x1, ys[i] + rh / 2), LADDER[i], st)
    level_file(img, (588, 96, 1256, 604), sel, unlocked, "维什戴尔", op_best, 8, "斯卡蒂")
    depart(img, (588, 620, 888, 680), sel > unlocked)
    for i, (lab, key, a, b) in enumerate((("返回", "ESC", 904, 1024),)):
        (b0, b1, b2, b3), _ = panel(img, (a, 628, b, 672), 2, 2)
        text(img, (b0 + 14, (b1 + b3) / 2), lab, 15, TXT, "lm")
        ptxt(img, (b2 - 12, (b1 + b3) / 2), key, 1, TXT2, 1, "rm")
    ptxt(img, (1256, 700), "↑↓ LEVEL   PGUP/PGDN 4 LV   HOME TOP UNLOCKED   ENTER DEPART   ESC BACK", 1, TXT2, 1, "rm")
    ptxt(img, (24, 700), "GOLD = OPERATOR BEST", 1, GOLD, 1, "lm")
    return img


# ---------------------------------------------------------------- 2. 手机 · 选择潮位
def page_phone(sel=9, unlocked=9, op_best=6, cleared=8):
    img = cc.bg(phone=True, k=165)
    s = 1.42
    P = 2
    ptxt(img, (36, 30), "OPERATION // TIDE LEVEL", 1, CY, 1, "lm")
    w = text(img, (36, 66), "选择潮位", 34, TXT, "lm", bold=True)
    ptxt(img, (36 + w + 16, 68), "TIDE LEVEL", 2, TXT2, 2, "lm")
    # 左：只显示选中附近 7 行（每行 64 屏幕像素 ≈ 45 逻辑像素，触屏可点），上下箭头提示还有几级
    hi = min(N, max(6, sel + 3))
    win = list(range(hi, max(-1, hi - 7), -1))
    rh, g = 64, 4
    top = 132
    ys_all = {}
    for j, i in enumerate(win):
        ys_all[i] = top + j * (rh + g) + rh / 2
    # 潮位尺：全 16 格压缩画在最左（只看水位，不点）
    gy = {i: 132 + (N - i) * (7 * (rh + g) - 4) / N for i in range(N + 1)}
    gauge(img, (20, 120, 64, 640), gy, sel, best=op_best, labels=(0, 8, 15))
    if win[0] < N:
        ptxt(img, (300, 116), "↑ %d-%d" % (win[0] + 1, N), 2, TXT2, 1, "mm")
    if win[-1] > 0:
        ptxt(img, (300, top + 7 * (rh + g) + 8), "↓ 0-%d" % (win[-1] - 1), 2, TXT2, 1, "mm")
    for i in win:
        st = row_state(i, sel, unlocked, op_best, cleared)
        level_row(img, (86, ys_all[i] - rh / 2, 560 if st == "sel" else 544, ys_all[i] + rh / 2), LADDER[i], st, s=1.25, compact=False)
    level_file(img, (580, 104, PHW - 24, 604), sel, unlocked, "维什戴尔", op_best, 8, "斯卡蒂", s=1.25, two_col=True)
    depart(img, (PHW - 360, 620, PHW - 24, 704), sel > unlocked, s=1.4)
    text(img, (580, 648), "上下滑动列表或点按一行换级；点「出发」开始", 18, TXT2, "lm")
    text(img, (580, 678), "系统返回键 = 返回；行高 ≥ 44 逻辑像素", 18, TXT2, "lm")
    return img


# ---------------------------------------------------------------- 3. 胜利结算
def settlement():
    p = os.path.join(MAIN, "build", "motion", "shots", "win", "shot_win.png")
    img = Image.open(p).convert("RGBA").resize((W, H)) if os.path.exists(p) else Image.new("RGBA", (W, H), (10, 14, 22, 255))
    c1.over(img, lambda d: d.rectangle([0, 0, W, H], fill=(4, 8, 14, 120)))
    x0, y0, x1, y1 = 150, 70, 830, 652
    col = (232, 160, 210)

    def pnl(d):
        d.rectangle([x0, y0, x1, y1], fill=(24, 26, 32, 255))
        d.rectangle([x0, y0, x1, y0 + 1], fill=col + (255,))
        d.rectangle([x0, y0, x1, y1], outline=(70, 76, 88, 255))
    c1.over(img, pnl)
    ptxt(img, ((x0 + x1) / 2, y0 + 40), "PRECIOUS DAYS", 1, col, 3, "mm")
    text(img, ((x0 + x1) / 2, y0 + 78), "结局一 · 平凡即是喜乐 · 探索完成", 30, (240, 242, 246), "mm")
    d = ImageDraw.Draw(img)
    chip(img, x0 + 24, y0 + 14, "新纪录", GOLD, 12)
    rows = [("探索时间", "11:42"), ("等级", "Lv.26  精英二"), ("击杀", "5 233"), ("潮位", "8 · 漫灌（原 波涛迭起·VIII）")]
    for i, (a, b) in enumerate(rows):
        y = y0 + 128 + i * 32
        d.polygon([(x0 + 44, y), (x0 + 48, y - 4), (x0 + 52, y), (x0 + 48, y + 4)], fill=col)
        text(img, (x0 + 62, y), a, 16, (150, 160, 176), "lm")
        text(img, (x0 + 160, y), b, 18, (240, 242, 246), "lm")
    bx, by = x1 - 120, y0 + 178
    c1.over(img, lambda dd: dd.rectangle([bx - 92, by - 72, bx + 92, by + 84], fill=(12, 22, 38, 230)))
    ptxt(img, (bx, by - 56), "TIDE", 1, CY, 2, "mm")
    badge(img, bx, by + 2, 8, k=7)
    text(img, (bx, by + 66), "斯卡蒂 7 → 8", 15, GOLD, "mm")
    # 本级新规则（反白条）
    ny = y0 + 268
    ptxt(img, (x0 + 44, ny), "NEW RULE", 1, (150, 160, 176), 2, "lm")
    text(img, (x0 + 150, ny), "本级新增规则 · 累计 8 条", 14, (150, 160, 176), "lm")
    sel_block(img, (x0 + 40, ny + 16, x1 - 40, ny + 78), 2, 2, water=0.12, glow_on=False)
    ptxt(img, (x0 + 56, ny + 34), "08", 2, SEL_IDX, 1, "lm")
    text(img, (x0 + 90, ny + 34), "漫灌", 17, NAVY_INK, "lm", bold=True)
    r1, r2 = LADDER[8]["rule"].split("；")
    text(img, (x0 + 140, ny + 33), r1 + "；", 14, NAVY_INK, "lm")
    text(img, (x0 + 140, ny + 53), r2, 14, NAVY_INK, "lm")
    # 累计规则小片（前 7 级，灰底）
    cx, cy = x0 + 44, ny + 90
    for R in LADDER[1:8]:
        lab = "%d %s" % (R["lv"], R["cn"])
        cx += chip(img, cx, cy, lab, GCOL[R["grp"]], 12) + 6
    # 纪录三行
    yb = cy + 52
    d.line([(x0 + 40, yb - 14), (x1 - 40, yb - 14)], fill=(60, 66, 78), width=1)
    rec = [("斯卡蒂 · 干员最佳", "7 → 8", "新纪录", GOLD), ("全干员最佳", "8（斯卡蒂）", "新纪录", GOLD),
           ("解锁", "潮位 9「夜潮」", "已解锁", CY)]
    for i, (a, b, tg, tc) in enumerate(rec):
        y = yb + 8 + i * 30
        text(img, (x0 + 62, y), a, 16, (150, 160, 176), "lm")
        w = text(img, (x0 + 230, y), b, 18, (240, 242, 246), "lm")
        if tg:
            chip(img, x0 + 242 + w, y - 12, tg, tc, 12)
    for i, (lab, key) in enumerate((("再次探索", "R"), ("挑战潮位 9", "N"), ("回到标题", "T"))):
        bw = (x1 - x0 - 80 - 24) / 3
        bx0 = x0 + 40 + i * (bw + 12)
        c1.over(img, lambda dd, bx0=bx0, bw=bw, i=i: dd.rectangle([bx0, y1 - 62, bx0 + bw, y1 - 22],
                                                                 fill=(54, 226, 220, 255) if i == 1 else (126, 152, 184, 102)))
        ink = (10, 18, 22) if i == 1 else (240, 242, 246)
        text(img, (bx0 + 14, y1 - 42), lab, 15, ink, "lm")
        d.rectangle([bx0 + bw - 28, y1 - 52, bx0 + bw - 10, y1 - 33], outline=ink)
        text(img, (bx0 + bw - 19, y1 - 42), key, 12, ink, "mm")
    c1.over(img, lambda dd: dd.rectangle([150, 662, 1130, 710], fill=(10, 12, 18, 220)))
    text(img, (166, 674), "失败 / 超时：潮位与本级新规则照常列出，纪录行换成「本局未通关 · 不计入纪录」，没有「挑战下一级」。", 14, (170, 180, 196), "lm")
    text(img, (166, 696), "Boss 演练与练习不显示潮位区。已通关过的级再通关：只在破干员纪录时挂「新纪录」。", 14, (170, 180, 196), "lm")
    return img


# ---------------------------------------------------------------- 4. 徽记
def badges():
    img = Image.new("RGBA", (W, H), (14, 16, 22, 255))
    text(img, (24, 28), "潮位徽记：每名干员「通关过的最高潮位」——选人名册卡、图鉴名册卡、干员档案。只是荣誉，不解锁任何东西", 17, (230, 234, 240), "lm")
    cap = (170, 180, 196)
    op = os.path.join(c1.SHOTS, "oppick", "shot_oppick.png")
    vals = [9, 4, None, 8, 2, 0, 12, None, 15, 6]
    if os.path.exists(op):
        src = Image.open(op).convert("RGBA").resize((W, H))
        ox, oy = 20 - 60, 60 - 556
        img.alpha_composite(src.crop((60, 556, 980, 700)), (20, 60))
        for i, v in enumerate(vals):
            badge(img, 72 + i * 90 + 80 - 16 + ox, 685 - 42 + oy, v, k=2)
        top = src.crop((940, 12, 1150, 44))
        img.alpha_composite(top, (980, 92))
        c1.over(img, lambda d: d.rectangle([980 + 10, 92 + 3, 980 + 112, 92 + 29], fill=(14, 22, 40, 255)))
        c1.over(img, lambda d: d.rectangle([980 + 10, 92 + 3, 980 + 112, 92 + 29], outline=(124, 120, 255, 255)))
        text(img, (980 + 18, 92 + 16), "潮位 8 · 漫灌", 13, (230, 236, 244), "lm")
        text(img, (980, 140), "顶栏小标：难度 → 本局潮位", 13, cap, "lm")
    text(img, (24, 218), "选人（B+）：名册卡右下角 = 该干员通关过的最高潮位；没通关过写「-」", 14, cap, "lm")
    if os.path.exists(op):
        img.alpha_composite(src.crop((80, 280, 520, 412)), (20, 246))
        c1.over(img, lambda d: d.rectangle([28, 382, 452, 416], fill=(14, 20, 40, 240)))
        badge(img, 48, 399, 8, k=2)
        text(img, (70, 399), "潮位纪录  最高 8 · 漫灌 · 结局三 · 10-12", 14, (230, 236, 244), "lm")
    cx_ = os.path.join(MAIN, "build", "codex_impl", "glass", "after_op.png")
    if os.path.exists(cx_):
        csrc = Image.open(cx_).convert("RGBA").resize((W, H))
        img.alpha_composite(csrc.crop((444, 470, 830, 560)), (20, 440))
        c1.over(img, lambda d: d.rectangle([26, 532, 406, 566], fill=(30, 30, 34, 240)))
        badge(img, 46, 549, 12, k=2)
        text(img, (68, 549), "潮位纪录  最高 12 · 异变 · 结局二", 14, (236, 238, 240), "lm")
    text(img, (24, 594), "档案：名字区下一行「潮位纪录」；点开看那一局的", 14, cap, "lm")
    text(img, (24, 616), "结局、用时、日期、版本（阶梯表版本不同时注明）", 14, cap, "lm")
    if os.path.exists(cx_):
        k = 0.78
        crop = csrc.crop((70, 80, 426, 560))
        crop = crop.resize((int(crop.width * k), int(crop.height * k)), Image.LANCZOS)
        gx, gy = 480, 236
        img.alpha_composite(crop, (gx, gy))
        cvals = [9, 4, None, 8, 2, 0, 12, None, 15, 6, None, 1, None, None, None]
        for i, v in enumerate(cvals):
            r_, c_ = i // 4, i % 4
            x1c = 76 + c_ * 88 + 80
            y1c = 86 + r_ * 120 + 110
            badge(img, gx + (x1c - 14 - 70) * k, gy + (y1c - 36 - 80) * k, v, k=2)
    text(img, (480, 626), "图鉴（C4'）：同一枚徽记，冷色，不用警示黄", 14, cap, "lm")
    sx = 820
    text(img, (sx, 246), "分段（固定按级，不随校准移动）", 15, (230, 234, 240), "lm")
    spec = [(None, "未通关：暗灰空盾，写「-」"), (2, "潮位 0–3：钢蓝边"), (6, "潮位 4–7（≥ 原 IV）：潮水底 + 青边"),
            (9, "潮位 8–11（≥ 原 VIII）：S4 反白 + 细青边"), (13, "潮位 12–14：反白 + 一道潮线"), (15, "潮位 15（顶级）：反白 + 潮线 + 泡沫光")]
    for i, (v, s_) in enumerate(spec):
        y = 296 + i * 64
        badge(img, sx + 32, y, v, k=4)
        text(img, (sx + 74, y), s_, 14, (200, 208, 220), "lm")
    return img


# ---------------------------------------------------------------- 5. 阶梯总表
def table():
    rh = 38
    img = Image.new("RGBA", (W, 128 + (N + 1) * rh + 60), (12, 18, 30, 255))
    text(img, (24, 34), "潮位阶梯 0–15（逐级叠加；每级一条新规则，「加重」= 把前面某条推得更难）", 20, TXT, "lm", bold=True)
    text(img, (24, 66), "潮位 0 / 4 / 8 = 现行 标准 / IV / VIII（8 另加 IV 的寒流两键，见 docs/71 §2.3）；KNOB = 要新旋钮；绿字 = 同级附带的补偿", 14, TXT2, "lm")
    cols = [24, 74, 186, 776, 1170]
    for x, h_ in zip(cols, ["级", "名", "新规则（玩家看到的）", "旋钮（dmod 键）", "备注"]):
        text(img, (x, 104), h_, 14, CY, "lm")
    for i, L in enumerate(LADDER):
        y = 128 + i * rh + rh / 2
        if L.get("preset"):
            c1.over(img, lambda d, y=y: d.rectangle([16, y - rh / 2 + 2, W - 16, y + rh / 2 - 2], fill=(30, 60, 84, 255)))
        ptxt(img, (cols[0], y), lv2(i), 2, CY if L.get("preset") else TXT2, 1, "lm")
        if L["grp"]:
            ImageDraw.Draw(img).rectangle([cols[1] - 8, y - 9, cols[1] - 6, y + 8], fill=GCOL[L["grp"]])
        text(img, (cols[1], y), L["cn"], 15, TXT, "lm", bold=True)
        r = L["rule"]
        while c1.F(13, r).getlength(r) > cols[3] - cols[2] - 14:
            r = r[:-2] + "…"
        text(img, (cols[2], y), r, 13, TXT, "lm")
        knobs = ", ".join("%s %g" % (k, v) for k, v in L["set"].items() if k not in L.get("relief", []))
        rel = [k for k in L["set"] if k in L.get("relief", [])]
        text(img, (cols[3], y - (7 if rel else 0)), knobs, 12, TXT2, "lm")
        if rel:
            text(img, (cols[3], y + 9), "补偿 " + ", ".join("%s %g" % (k, L["set"][k]) for k in rel), 11, RELIEF, "lm")
        note = []
        if L.get("preset"):
            note.append("= " + L["preset"])
        if L.get("new"):
            note.append("KNOB")
        if any(k in compose(i - 1) and compose(i - 1)[k] != cc.dmod_default().get(k, NEW_KEYS.get(k)) for k in L["set"]) and i > 0:
            note.append("加重")
        text(img, (cols[4], y), " ".join(note), 13, GOLD if L.get("preset") else TXT2, "lm")
    return img


# ---------------------------------------------------------------- 总览
def main():
    os.makedirs(OUT, exist_ok=True)
    report, ok = verify()
    with open(os.path.join(OUT, "sweep_extra.txt"), "w", encoding="utf-8") as f:
        for i in range(N + 1):
            line = "L%02d %s" % (i, bal_args(i))
            f.write(line + "\n")
    print("写出", os.path.join(OUT, "sweep_extra.txt"))
    outs = {"is3_levels_desktop": page_desktop(), "is3_levels_desktop_locked": page_desktop(sel=11, unlocked=9),
            "is3_levels_phone": page_phone(), "is3_levels_settlement": settlement(), "is3_levels_badges": badges(),
            "is3_levels_table": table()}
    for k, im in outs.items():
        p = os.path.join(OUT, k + ".png")
        im.convert("RGB").save(p)
        print("写出", p)
    c1.contact_sheet([
        ("选择潮位", [("桌面 · 选中 8（已解锁到 9）", outs["is3_levels_desktop"]), ("桌面 · 选中未解锁的 11", outs["is3_levels_desktop_locked"])]),
        ("手机 / 结算", [("手机 · 选中 9（1480×720）", outs["is3_levels_phone"]), ("胜利结算 · 潮位 8 首通", outs["is3_levels_settlement"])]),
        ("徽记 / 总表", [("选人 / 图鉴 · 潮位徽记", outs["is3_levels_badges"]), ("阶梯总表", outs["is3_levels_table"])]),
    ], "潮位阶梯（水月肉鸽式逐级难度）概念图  docs/71", os.path.join(OUT, "contact_sheet.png"))
    if not ok:
        sys.exit(1)


if __name__ == "__main__":
    main()
