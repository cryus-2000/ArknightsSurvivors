# -*- coding: utf-8 -*-
"""危机合约式自选难度「潮汐合约」概念图（docs/68，2026-10-12 用户：「难度可以改成自选条目」「奖励暂时只给荣誉」）。
只是概念图，不改游戏代码。画法沿用 T5s（docs/67 §12 / docs/37 §8）：藏青三阶 Bayer 抖动、像素阶梯切角、
选中 = S4 反白 #EEF3F6 + 细青边 + 只有选中块有潮线；像素字 5×7（罗马数字一律 I / II / III / IV / VIII）。
底图用现有截图（不重截）：开场 2.2 秒 keyart（build/title_redesign/shots）、胜利结算（build/motion/shots/win）、
选人 / 图鉴（build/title_redesign/shots/oppick、build/codex_impl/glass/after_op.png）；缺图时退回纯色底。

另外做一件事：把 docs/68 §1 的条目表（下面 TAGS / PRESETS）按合成规则拼成修正表，
和 game/data/balance.json difficulty/hard、extreme（经 data.gd dmod_for_level 拼底）逐键核对——推荐合约 = 条目之和必须逐键相等。

用法：
    python tools/concept_contracts.py
输出（不入库）：主仓库 build/contracts/
    contracts_board.png        桌面 · 自定义合约条目板
    contracts_presets.png      桌面 · 推荐合约（潮位尺上的 标准 / IV / VIII + 自定义）
    contracts_board_phone.png  手机 · 条目板（1480×720 屏幕像素，UI 逻辑约 1044×481）
    contracts_settlement.png   胜利结算 · 合约与潮位、干员最佳
    contracts_badges.png       选人 / 图鉴 · 潮位徽记
    contact_sheet.png          总览
"""
import json, math, os, re, sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

TOOLS = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, TOOLS)
import godot_runner as gr  # noqa: E402
import concept_title_ui as c1  # noqa: E402
import concept_title_ui_v3 as c3  # noqa: E402
from concept_title_ui_v4 import snap, stair, edge_of, dith, paint, solid, glow, ripple, ptxt, WATER, EDGE, N_TONES, FOAM, motes  # noqa: E402
from concept_title_ui_v2 import CY, CY_DIM, TXT, TXT2, text  # noqa: E402
from concept_title_ui_v5 import NEAR_WHITE, NAVY_INK, SEL_EDGE, SEL_SUB, SEL_IDX, TIDE_GLOW, FOAM_GLOW  # noqa: E402

ROOT = c1.ROOT
MAIN = gr.common_root(ROOT)
OUT = os.path.join(MAIN, "build", "contracts")
W, H = 1280, 720
PHW, PHH = 1480, 720
N_ACT = [(24, 58, 92), (16, 40, 70), (8, 20, 40)]    # 已选条目：比未选亮一阶
STEEL = (126, 152, 184)
DIM = (92, 108, 126)
GOLD = (244, 192, 78)
GRP_COL = {"horde": (96, 224, 232), "boss": (255, 96, 150), "lamp": (244, 192, 78), "env": (124, 120, 255), "time": (150, 230, 180)}

# ---------------------------------------------------------------- docs/68 §1 条目表（与文档一致；风险是初始猜测，P2 按云端实测替换）
# tiers：(档位说明, 累计风险, 用到的推荐合约, 旋钮)；旋钮里 beacon_x 是灯标刷新间隔的乘数（各条目相乘后写进 beacon_every）
GROUPS = [("horde", "敌群", "HORDE"), ("boss", "精英与 Boss", "ELITE & BOSS"), ("lamp", "灯火与资源", "LAMP & SUPPLY"),
          ("env", "环境与控制", "ENV & CONTROL"), ("time", "时间", "TIME")]
TAGS = [
    {"id": "shell", "grp": "horde", "cn": "厚壳", "en": "SHELL", "ic": "shell", "tiers": [
        ("敌人生命 +20%", 2, "IV", {"enemy_hp": 1.2, "hunt_ring_hp": 0.85, "hunt_dur": 0.85}),
        ("敌人生命 +45%", 3, "", {"enemy_hp": 1.45, "hunt_ring_hp": 0.78, "hunt_dur": 0.78, "boss_fight_enemy_hp": 1.0}),
        ("敌人生命 +70%", 4, "VIII", {"enemy_hp": 1.7, "hunt_ring_hp": 0.7, "hunt_dur": 0.7, "boss_fight_enemy_hp": 1.0})]},
    {"id": "fangs", "grp": "horde", "cn": "利齿", "en": "FANGS", "ic": "fangs", "tiers": [
        ("敌人造成的伤害 +20%", 2, "IV", {"enemy_dmg": 1.2}),
        ("敌人造成的伤害 +25%", 2, "VIII*", {"enemy_dmg": 1.25}),
        ("敌人造成的伤害 +40%", 4, "", {"enemy_dmg": 1.4})]},
    {"id": "surge", "grp": "horde", "cn": "大潮", "en": "SURGE", "ic": "surge", "tiers": [
        ("大群规模 +20%", 1, "IV", {"horde": 1.2}),
        ("大群 +60%，Boss 在场照常来袭", 3, "VIII", {"horde": 1.6, "horde_in_boss": 1})]},
    {"id": "mutate", "grp": "horde", "cn": "异变", "en": "MUTATION", "ic": "mutate", "tiers": [
        ("词条提前到 5:00", 1, "", {"affix_start": 300}),
        ("词条提前到 4:00，概率上限 55%", 2, "", {"affix_start": 240, "affix_max": 0.55})]},
    {"id": "colossus", "grp": "boss", "cn": "巨躯", "en": "COLOSSUS", "ic": "colossus", "tiers": [
        ("Boss 生命 +15%", 1, "IV", {"boss_hp": 1.15}),
        ("Boss 生命 +35%", 2, "VIII", {"boss_hp": 1.35}),
        ("Boss +35%，最终 Boss 再 +30%", 4, "", {"boss_hp": 1.35, "final_boss_hp": 1.3})]},
    {"id": "fury", "grp": "boss", "cn": "狂澜", "en": "FURY", "ic": "fury", "tiers": [
        ("Boss 预警缩短 15%", 1, "IV", {"boss_warn": 0.85}),
        ("预警 -20%，Boss 伤害 +15%", 2, "VIII", {"boss_warn": 0.8, "boss_dmg": 1.15}),
        ("预警 -30%，Boss 伤害 +30%", 4, "", {"boss_warn": 0.7, "boss_dmg": 1.3})]},
    {"id": "warlord", "grp": "boss", "cn": "领袖", "en": "WARLORD", "ic": "warlord", "new": True, "tiers": [
        ("精英生命与伤害 +25%", 1, "", {"elite_hp": 1.25, "elite_dmg": 1.25}),
        ("精英生命与伤害 +50%", 3, "", {"elite_hp": 1.5, "elite_dmg": 1.5})]},
    {"id": "gutter", "grp": "lamp", "cn": "残烛", "en": "GUTTERING", "ic": "gutter", "tiers": [
        ("灯火损失 +30%，灯油 -30%", 1, "IV", {"lamp_hit": 1.3, "oil_drop": 0.7, "beacon_x": 0.8}),
        ("灯火损失 +30%，灯油 -40%", 1, "VIII*", {"lamp_hit": 1.3, "oil_drop": 0.6, "beacon_x": 0.8}),
        ("灯火损失 +60%，灯油 -70%", 3, "", {"lamp_hit": 1.6, "oil_drop": 0.3, "beacon_x": 0.8})]},
    {"id": "scarcity", "grp": "lamp", "cn": "拮据", "en": "SCARCITY", "ic": "scarcity", "tiers": [
        ("源石锭掉落 -10%", 1, "IV", {"ingot": 0.9}),
        ("源石锭掉落 -25%", 2, "VIII", {"ingot": 0.75}),
        ("源石锭掉落 -50%", 3, "", {"ingot": 0.5})]},
    {"id": "wound", "grp": "lamp", "cn": "负伤", "en": "WOUNDED", "ic": "wound", "tiers": [
        ("主控初始最大生命 -10%", 1, "VIII", {"max_hp": 0.9}),
        ("主控初始最大生命 -20%", 3, "", {"max_hp": 0.8})]},
    {"id": "mire", "grp": "env", "cn": "永痕", "en": "ETERNAL MIRE", "ic": "mire", "tiers": [
        ("自然溟痕常驻，只有灯标能驱散", 3, "VIII", {"mire_permanent": 1, "beacon_x": 0.75}),
        ("常驻，溟痕伤害与神经损伤 +30%", 5, "", {"mire_permanent": 1, "beacon_x": 0.75, "mire_dmg": 1.3, "nerve_rate": 1.3})]},
    {"id": "cold", "grp": "env", "cn": "寒潮", "en": "COLD SNAP", "ic": "cold", "tiers": [
        ("控制提前到 5:00，寒霜 2 层冻结", 1, "IV", {"ctrl_start": 300, "frost_max": 2}),
        ("控制提前到 3:00，1 层即冻结", 2, "", {"ctrl_start": 180, "frost_max": 1})]},
    {"id": "lonely", "grp": "env", "cn": "孤灯", "en": "LONE LIGHT", "ic": "lonely", "tiers": [
        ("引航灯标刷新间隔 +30%", 1, "", {"beacon_x": 1.3}),
        ("引航灯标刷新间隔 +70%", 2, "", {"beacon_x": 1.7})]},
    {"id": "night", "grp": "time", "cn": "夜潮", "en": "NIGHT TIDE", "ic": "night", "tiers": [
        ("后期敌人伤害上限 +50%", 1, "", {"dmg_late_cap": 0.5}),
        ("后期敌人伤害上限 +80%", 2, "", {"dmg_late_cap": 0.8})]},
    {"id": "endless", "grp": "time", "cn": "潮不止息", "en": "ENDLESS TIDE", "ic": "endless", "tiers": [
        ("最终 Boss 在场时照常刷怪", 4, "", {"final_stop_mobs": 0})]},
    {"id": "deadline", "grp": "time", "cn": "限时", "en": "DEADLINE", "ic": "deadline", "new": True, "tiers": [
        ("最终 Boss 5:00 内未击破即失败", 1, "", {"final_limit": 300}),
        ("最终 Boss 3:00 内未击破即失败", 3, "", {"final_limit": 180})]},
]
TAG = {t["id"]: t for t in TAGS}
EXCL = [("lonely", 2, "mire", 1), ("deadline", 2, "colossus", 3)]   # (条目, 自哪一档起, 与之互斥的条目, 自哪一档起)
PRESETS = {
    "standard": {},
    "hard": {"shell": 1, "fangs": 1, "surge": 1, "colossus": 1, "fury": 1, "gutter": 1, "scarcity": 1, "cold": 1},
    "extreme": {"shell": 3, "fangs": 2, "surge": 2, "colossus": 2, "fury": 2, "gutter": 2, "scarcity": 2, "wound": 1, "mire": 1},
}
NEW_KEYS = {"elite_hp": 1.0, "elite_dmg": 1.0, "final_limit": -1.0}   # 新旋钮（docs/68 §1.4），现有 DMOD_DEFAULT 里没有


def risk(sel):
    return sum(TAG[k]["tiers"][v - 1][1] for k, v in sel.items() if v > 0)


# ---------------------------------------------------------------- 合成规则 + 与 balance.json 核对
def dmod_default():
    src = open(os.path.join(ROOT, "game", "scripts", "data.gd"), encoding="utf-8").read()
    blk = src[src.index("const DMOD_DEFAULT := {"):]
    blk = blk[:blk.index("\n}")]
    blk = "\n".join(ln.split("#")[0] for ln in blk.splitlines())
    m = {k: float(v) for k, v in re.findall(r'"(\w+)":\s*(-?[\d.]+)', blk)}
    return m


def dmod_for_level(L, base):
    m = dict(base)
    m["enemy_hp"] = 1.0 + (0.15 if L >= 1 else 0.0) + (0.2 if L >= 10 else 0.0)
    m["boss_hp"] = 1.15 if L >= 1 else 1.0
    m["enemy_dmg"] = 1.0 + (0.15 if L >= 2 else 0.0) + (0.2 if L >= 10 else 0.0)
    m["lamp_hit"] = 1.25 if L >= 3 else 1.0
    m["oil_drop"] = 0.5 if L >= 3 else 1.0
    m["elite_interval"] = 0.75 if L >= 4 else 1.0
    m["ingot"] = 0.7 if L >= 5 else 1.0
    m["boss_warn"] = 0.75 if L >= 6 else 1.0
    m["horde"] = 1.4 if L >= 7 else 1.0
    m["horde_in_boss"] = 1 if L >= 7 else 0
    m["mire_permanent"] = 1 if L >= 8 else 0
    m["max_hp"] = 0.8 if L >= 9 else 1.0
    m["boss_dmg"] = 1.25 if L >= 10 else 1.0
    return m


def compose(sel, base):
    """条目 → 修正表：每个主键只属于一个条目（直接写）；beacon_x 各条目相乘写进 beacon_every"""
    m = dict(base)
    m.update(NEW_KEYS)
    bx = 1.0
    for k, v in sel.items():
        if v <= 0:
            continue
        for key, val in TAG[k]["tiers"][v - 1][3].items():
            if key == "beacon_x":
                bx *= val
            else:
                m[key] = float(val)
    m["beacon_every"] = round(bx, 6)
    return m


def verify():
    base = dmod_default()
    bal = json.load(open(os.path.join(ROOT, "game", "data", "balance.json"), encoding="utf-8"))["difficulty"]
    ok = True
    for key, lvl in (("standard", 0), ("hard", 4), ("extreme", 8)):
        tier = dmod_for_level(lvl, base)
        for k, v in bal.get(key, {}).items():
            if k in tier:
                tier[k] = float(v)
        tags = compose(PRESETS[key], base)
        bad = [k for k in tier if abs(float(tier[k]) - float(tags[k])) > 1e-6]
        print("推荐合约核对 %-8s 风险 %2d  %s" % (key, risk(PRESETS[key]), "逐键一致" if not bad else "不一致：" + ", ".join(
            "%s 现表 %s / 条目 %s" % (k, tier[k], tags[k]) for k in bad)))
        ok = ok and not bad
    return ok


def mod_lines(m):
    """修正表 → (说明, 像素字数值, 类) 行；类 up = 收紧、relief = 补偿（放宽）。顺序同 data.gd DMOD_TEXT，新键接在后面"""
    L = []

    def up(k, s):
        if m[k] > 1.0001:
            L.append((s, "+%d%%" % round((m[k] - 1) * 100), "up"))

    def dn(k, s):
        if m[k] < 0.9999:
            L.append((s, "-%d%%" % round((1 - m[k]) * 100), "up"))
    up("enemy_hp", "敌人生命")
    up("enemy_dmg", "敌人造成的伤害")
    up("boss_hp", "Boss 生命")
    up("boss_dmg", "Boss 造成的伤害再")
    up("final_boss_hp", "最终 Boss 生命再")
    up("elite_hp", "精英生命与伤害")
    dn("max_hp", "主控初始最大生命")
    up("lamp_hit", "受击时灯火损失")
    dn("oil_drop", "灯油掉落")
    dn("ingot", "源石锭掉落")
    if m["boss_warn"] < 0.9999:
        L.append(("Boss 预警最多缩短", "%d%%" % round((1 - m["boss_warn"]) * 100), "up"))
    up("horde", "大群规模")
    if m["horde_in_boss"] > 0.5:
        L.append(("Boss 在场时大群照常来袭", "", "up"))
    if m["mire_permanent"] > 0.5:
        L.append(("自然溟痕常驻，只有灯标能驱散", "", "up"))
    up("mire_dmg", "溟痕伤害")
    up("nerve_rate", "神经损伤累积")
    if m["ctrl_start"] >= 0:
        L.append(("小怪控制提前到", "%d:%02d" % (m["ctrl_start"] // 60, m["ctrl_start"] % 60), "up"))
    if m["frost_max"] >= 0:
        L.append(("寒霜 %d 层即冻结" % m["frost_max"], "", "up"))
    if m["affix_start"] >= 0:
        L.append(("词条提前到", "%d:%02d" % (m["affix_start"] // 60, m["affix_start"] % 60), "up"))
    if m["affix_max"] >= 0:
        L.append(("词条概率上限", "%d%%" % round(m["affix_max"] * 100), "up"))
    if m["dmg_late_cap"] >= 0:
        L.append(("后期敌人伤害上限", "+%d%%" % round(m["dmg_late_cap"] * 100), "up"))
    if m["final_stop_mobs"] == 0:
        L.append(("最终 Boss 在场时照常刷怪", "", "up"))
    if m["final_limit"] > 0:
        L.append(("最终 Boss 限时", "%d:%02d" % (m["final_limit"] // 60, m["final_limit"] % 60), "up"))
    if m["beacon_every"] > 1.0001:
        L.append(("引航灯标刷新间隔", "+%d%%" % round((m["beacon_every"] - 1) * 100), "up"))
    if m["beacon_every"] < 0.9999:
        L.append(("引航灯标刷新间隔", "-%d%%" % round((1 - m["beacon_every"]) * 100), "relief"))
    if m["hunt_dur"] < 0.9999:
        L.append(("围猎时长与圈上海嗣生命", "-%d%%" % round((1 - m["hunt_dur"]) * 100), "relief"))
    if m["boss_fight_enemy_hp"] >= 0:
        L.append(("终局新刷的杂兵生命不加成", "", "relief"))
    return L


# ---------------------------------------------------------------- 16×16 条目图标
def _ticon(kind):
    im = Image.new("L", (16, 16), 0)
    d = ImageDraw.Draw(im)
    if kind == "shell":
        d.polygon([(7, 1), (8, 1), (14, 4), (14, 11), (8, 14), (7, 14), (1, 11), (1, 4)], outline=1)
        d.polygon([(7, 5), (8, 5), (10, 7), (10, 9), (8, 10), (7, 10), (5, 9), (5, 7)], fill=2)
    elif kind == "fangs":
        d.line([(1, 2), (14, 2)], fill=1)
        d.polygon([(2, 3), (7, 3), (4, 12)], outline=1)
        d.polygon([(8, 3), (13, 3), (11, 12)], outline=1)
        d.point([(4, 9), (11, 9)], fill=2)
    elif kind == "surge":
        for j, y in enumerate((4, 8, 12)):
            for x in range(1, 15):
                d.point((x, y + round(math.sin(x * 0.9 + j) * 1.4)), fill=1 if j != 1 else 2)
    elif kind == "mutate":
        d.ellipse([3, 3, 12, 12], outline=1)
        d.rectangle([7, 7, 8, 8], fill=2)
        for p in ((1, 1), (14, 1), (1, 14), (14, 14), (7, 0), (0, 7)):
            d.point(p, fill=2)
    elif kind == "colossus":
        d.ellipse([1, 3, 14, 12], outline=1)
        d.rectangle([6, 5, 9, 10], fill=2)
        d.line([(0, 2), (3, 0)], fill=1)
        d.line([(15, 2), (12, 0)], fill=1)
    elif kind == "fury":
        d.polygon([(9, 0), (3, 9), (7, 9), (5, 15), (13, 5), (9, 5), (11, 0)], fill=2, outline=1)
    elif kind == "warlord":
        d.polygon([(1, 12), (1, 4), (5, 8), (7, 2), (8, 2), (10, 8), (14, 4), (14, 12)], outline=1)
        d.line([(1, 14), (14, 14)], fill=2)
        d.point([(7, 9), (8, 9)], fill=2)
    elif kind == "gutter":
        d.rectangle([5, 7, 10, 14], outline=1)
        d.rectangle([7, 2, 8, 5], fill=2)
        d.point([(6, 3), (9, 4)], fill=2)
        d.line([(10, 9), (11, 11)], fill=1)
    elif kind == "scarcity":
        d.polygon([(3, 5), (12, 5), (14, 12), (1, 12)], outline=1)
        d.line([(5, 9), (10, 9)], fill=2)
    elif kind == "wound":
        for (x, y) in ((3, 3), (4, 2), (5, 2), (6, 3), (7, 4), (8, 4), (9, 3), (10, 2), (11, 2), (12, 3), (13, 4), (13, 6), (12, 8),
                       (11, 9), (10, 10), (9, 11), (8, 12), (7, 12), (6, 11), (5, 10), (4, 9), (3, 8), (2, 6), (2, 4)):
            d.point((x, y), fill=1)
        d.line([(8, 5), (7, 7), (9, 8), (8, 10)], fill=2)
    elif kind == "mire":
        d.ellipse([1, 9, 14, 14], outline=1)
        d.rectangle([7, 1, 8, 2], fill=2)
        d.rectangle([6, 3, 9, 5], fill=2)
        d.point([(4, 11), (10, 12)], fill=2)
    elif kind == "cold":
        for a in (0, 60, 120):
            r = math.radians(a)
            d.line([(7.5 - 6.5 * math.cos(r), 7.5 - 6.5 * math.sin(r)), (7.5 + 6.5 * math.cos(r), 7.5 + 6.5 * math.sin(r))], fill=1)
        d.rectangle([7, 7, 8, 8], fill=2)
    elif kind == "lonely":
        d.rectangle([6, 5, 9, 14], outline=1)
        d.rectangle([5, 1, 10, 3], fill=2)
        d.line([(1, 15), (14, 0)], fill=1)
    elif kind == "night":
        d.ellipse([2, 2, 13, 13], fill=1)
        d.ellipse([6, 0, 16, 10], fill=0)
        d.point([(12, 12), (14, 9)], fill=2)
    elif kind == "endless":
        d.ellipse([0, 4, 8, 11], outline=1)
        d.ellipse([7, 4, 15, 11], outline=1)
        d.point([(7, 7), (8, 8)], fill=2)
    elif kind == "custom":     # 条目板：4 格，两格已选
        for i, (x, y) in enumerate(((1, 1), (9, 1), (1, 9), (9, 9))):
            if i in (0, 3):
                d.rectangle([x, y, x + 5, y + 5], fill=2)
            d.rectangle([x, y, x + 5, y + 5], outline=1)
    elif kind == "deadline":
        d.polygon([(3, 1), (12, 1), (8, 7), (8, 8), (12, 14), (3, 14), (7, 8), (7, 7)], outline=1)
        d.polygon([(5, 13), (10, 13), (8, 10), (7, 10)], fill=2)
    return im


def ticon(img, kind, cx, cy, k, col, col2=None):
    src = np.array(_ticon(kind))
    out = np.zeros((16, 16, 4), np.uint8)
    out[src == 1] = col + (255,)
    out[src == 2] = (col2 or col) + (255,)
    ic = Image.fromarray(out, "RGBA").resize((16 * k, 16 * k), Image.NEAREST)
    img.alpha_composite(ic, (int(cx - 8 * k), int(cy - 8 * k)))


# ---------------------------------------------------------------- 通用小件
def panel(img, box, P=2, n=2, tones=None, a=228, edge=EDGE + (190,)):
    x0, y0, x1, y1 = [snap(v, P) for v in box]
    m = stair(x1 - x0, y1 - y0, P, n)
    t = tones or N_TONES
    lv = dith(x0, y0, x1 - x0, y1 - y0, P, lambda cx, cy: np.clip(cy / (y1 - y0) * (len(t) - 1) * 1.1, 0, len(t) - 1))
    paint(img, x0, y0, m, lv, t, a)
    if edge:
        solid(img, x0, y0, edge_of(m, P), edge)
    return (x0, y0, x1, y1), m


def sel_block(img, box, P=2, n=2, water=0.2, glow_on=True):
    """S4 选中：反白 + 细青边 + 发光潮线（只有选中块有水）"""
    x0, y0, x1, y1 = [snap(v, P) for v in box]
    w, h = x1 - x0, y1 - y0
    m = stair(w, h, P, n)
    if glow_on:
        gm = Image.new("L", img.size, 0)
        gm.paste(Image.fromarray((m * 255).astype(np.uint8), "L"), (x0, y0))
        glow(img, gm, (90, 200, 230), 8, (0.08, 0.3, 0.6), (18, 36, 64), cell=P * 2)
    solid(img, x0, y0, m, NEAR_WHITE)
    crest = None
    if water > 0:
        base = h - max(3 * P, snap(h * water, P))
        ys, xs = np.mgrid[0:h, 0:w]
        gx = (xs + x0) // P
        wave = (np.round(np.sin(gx * 0.45 + y0 * 0.1) * 0.8 + np.sin(gx * 0.17 + 1.3) * 0.6) * P).astype(int)
        wm = m & (ys >= base + wave)
        wl = dith(x0, y0, w, h, P, lambda cx, cy: np.clip((cy - base) / max(1.0, h - base) * 2.4, 0, 2))
        wl[~wm] = -1
        paint(img, x0, y0, wm, wl, WATER, 236)
        top = wm & ~np.roll(wm, P, axis=0)
        band = wm & (ys < base + wave + 3 * P)
        gmk = Image.new("L", img.size, 0)
        gmk.paste(Image.fromarray((band * 255).astype(np.uint8), "L"), (x0, y0))
        glow(img, gmk, TIDE_GLOW, 3, (0.15, 0.45), (60, 110), cell=P)
        solid(img, x0, y0, top, FOAM_GLOW + (255,))
        crest = y0 + base
    solid(img, x0, y0, edge_of(m, P), SEL_EDGE)
    return (x0, y0, x1, y1), m, crest


def wrap(s, size, width):
    """按像素宽折行：英文数字串（+20%、5:00、VIII）不拆开，标点不放行首"""
    f = c1.F(size, s)
    toks = re.findall(r"[A-Za-z0-9+\-%:.×/]+|\s|.", s)
    out, cur = [], ""
    for tk in toks:
        if f.getlength(cur + tk) > width and cur.strip() and tk not in "，。、；：）":
            out.append(cur.rstrip())
            cur = tk.lstrip()
        else:
            cur += tk
    if cur.strip():
        out.append(cur)
    return out


def roman(i):
    return ["", "I", "II", "III", "IV"][i]


def bg(phone=False, k=150):
    try:
        if phone:
            im = c3.stage(phone=True).resize((PHW, PHH), Image.LANCZOS)
        else:
            im = c3.stage()
    except Exception:
        im = Image.new("RGBA", (PHW, PHH) if phone else (W, H), (8, 16, 30, 255))
    c1.over(im, lambda d: d.rectangle([0, 0, im.width, im.height], fill=(2, 6, 16, k)))
    return im


# ---------------------------------------------------------------- 潮位尺（总风险 = 水位）
def tide_gauge(img, box, total, marks, best=None, P=2, rmax=48, big=True, label=True):
    """marks：[(风险, 标签)]；best：当前主控的最佳潮位（虚线）"""
    (bx0, by0, bx1, by1), gm = panel(img, box, P, 3)
    pad_t, pad_b = (70 if big else 40), 16
    ytop, ybot = by0 + pad_t, by1 - pad_b

    def ry(r):
        return snap(ybot - (ybot - ytop) * min(r, rmax) / rmax, P)
    lvl = ry(total)
    h, w = gm.shape
    yy, xx = np.mgrid[0:h, 0:w]
    gxx = (xx + bx0) // P
    wave = (np.round(np.sin(gxx * 0.7) * 0.8) * P).astype(int)
    wm = gm & (yy >= (lvl - by0) + wave) & ~edge_of(gm, P)
    wl = dith(bx0, by0, w, h, P, lambda cx, cy: np.clip((cy - (lvl - by0)) / 260 * 2.2, 0, 2))
    paint(img, bx0, by0, wm, wl, WATER, 240)
    top = wm & ~np.roll(wm, P, axis=0)
    solid(img, bx0, by0, top, FOAM + (230,))
    d = ImageDraw.Draw(img)
    for r in range(0, rmax + 1, 2):
        L = 6 * P if r % 10 == 0 else 3 * P
        d.rectangle([bx0 + 3 * P, ry(r), bx0 + 3 * P + L - 1, ry(r) + P - 1], fill=CY_DIM)
        if r % 10 == 0 and label:
            ptxt(img, (bx1 - 4 * P, ry(r)), str(r), 1, TXT2, 1, "rm")
    for r, lab in marks:
        y = ry(r)
        d.rectangle([bx0 + 3 * P, y, bx1 - 3 * P, y + P - 1], fill=CY)
        d.polygon([(bx1 + 2, y), (bx1 + 8, y - 4), (bx1 + 8, y + 4)], fill=CY)
        if lab:
            ptxt(img, (bx1 + 12, y), lab, 1, CY, 1, "lm")
    if best is not None:
        y = ry(best)
        for x in range(bx0 + 3 * P, bx1 - 3 * P, 3 * P):
            d.rectangle([x, y, x + P * 2 - 1, y + P - 1], fill=GOLD)
        if label:
            ptxt(img, (bx1 + 12, y), "BEST %d" % best, 1, GOLD, 1, "lm")
    ripple(img, (bx0 + bx1) / 2, lvl, P, 0.7, gm, (bx0, by0))
    if big:
        ptxt(img, ((bx0 + bx1) / 2, by0 + 22), "TIDE", 1, TXT2, 1, "mm")
        ptxt(img, ((bx0 + bx1) / 2, by0 + 48), str(total), 3 if total < 100 else 2, TXT, 1, "mm")
    return ry


# ---------------------------------------------------------------- 条目卡
def tag_card(img, box, tag, tier, focus=False, blocked=None, compact=False, s=1.0, P=2, show_eff=True):
    x0, y0, x1, y1 = [snap(v, P) for v in box]
    w, h = x1 - x0, y1 - y0
    gc = GRP_COL[tag["grp"]]
    if focus:
        _, m, crest = sel_block(img, (x0, y0, x1, y1), P, 2, water=0.16)
        tc, sc, ic1, ic2, pc_on, pc_off = NAVY_INK, SEL_SUB, NAVY_INK, (30, 150, 180), (20, 110, 140), (170, 186, 198)
    else:
        act = tier > 0
        (x0, y0, x1, y1), m = panel(img, (x0, y0, x1, y1), P, 2, N_ACT if act else N_TONES, 236 if act else 205,
                                    (CY + (255,)) if act else (EDGE + (170,)))
        if act:
            d = ImageDraw.Draw(img)
            d.rectangle([x0 + 2 * P, y0 + 4 * P, x0 + 3 * P - 1, y1 - 4 * P], fill=gc)
        tc = TXT if act else (150, 166, 184)
        sc = (170, 196, 212) if act else DIM
        ic1, ic2 = ((200, 226, 238), gc) if act else ((96, 116, 136), (70, 92, 112))
        pc_on, pc_off = CY, (34, 56, 82)
    if blocked:
        c1.over(img, lambda d: d.rectangle([x0 + P, y0 + P, x1 - P, y1 - P], fill=(4, 10, 20, 150)))
        tc, sc, ic1, ic2 = (110, 122, 138), (96, 108, 122), (70, 84, 100), (70, 84, 100)
    k = 2 if s >= 1 else 1
    ix = x0 + int(20 * s)
    iy = y0 + int(22 * s)
    ticon(img, tag["ic"], ix, iy, k, ic1, ic2)
    nx = ix + int(18 * s)
    text(img, (nx, iy - int(5 * s)), tag["cn"], int(17 * s), tc, "lm", bold=True)
    ptxt(img, (nx + 1, iy + int(11 * s)), tag["en"], 1, sc, 1, "lm")
    if tag.get("new"):
        ptxt(img, (x1 - 8, y0 + 10), "NEW KNOB", 1, (255, 150, 180) if not focus else (200, 60, 110), 1, "rm")
    elif tier > 0:
        ptxt(img, (x1 - 10, y0 + int(18 * s)), "+%d" % tag["tiers"][tier - 1][1], 2 if s >= 1 else 1, tc if focus else CY, 1, "rm")
    # 效果说明：当前档；没选时淡色预览第一档
    if show_eff:
        eff = tag["tiers"][max(tier, 1) - 1][0]
        fs = int(12.5 * s) if not compact else int(12 * s)
        lines = wrap(eff, fs, w - int(26 * s))[:2]
        for j, ln in enumerate(lines):
            text(img, (x0 + int(12 * s), y0 + int(48 * s) + j * int(16 * s)), ln, fs, tc if tier > 0 else sc, "lm")
    # 档位格（格里写累计风险；预设专用窄档虚线框）
    n = len(tag["tiers"])
    bw, bh, g = int(30 * s), int(18 * s), int(4 * s)
    by = y1 - bh - int(9 * s)
    d = ImageDraw.Draw(img)
    for i in range(n):
        bx = x0 + int(12 * s) + i * (bw + g)
        on = i < tier
        narrow = tag["tiers"][i][2].endswith("*")
        if on:
            d.rectangle([bx, by, bx + bw - 1, by + bh - 1], fill=pc_on)
            ptxt(img, (bx + bw / 2, by + bh / 2), str(tag["tiers"][i][1]), 1, NEAR_WHITE if focus else NAVY_INK, 1, "mm")
        else:
            if narrow:
                for xx in range(bx, bx + bw, 4):
                    d.rectangle([xx, by, xx + 1, by], fill=pc_off if not focus else (150, 170, 186))
                    d.rectangle([xx, by + bh - 1, xx + 1, by + bh - 1], fill=pc_off if not focus else (150, 170, 186))
            else:
                d.rectangle([bx, by, bx + bw - 1, by + bh - 1], outline=pc_off if not focus else (150, 170, 186))
            ptxt(img, (bx + bw / 2, by + bh / 2), str(tag["tiers"][i][1]), 1, sc, 1, "mm")
        ptxt(img, (bx + bw / 2, by - int(7 * s)), roman(i + 1), 1, sc, 1, "mm")
    if blocked:
        text(img, (x1 - 10, y0 + int(48 * s)), blocked, int(12 * s), (255, 120, 160), "rm")
    return (x0, y0, x1, y1)


# ---------------------------------------------------------------- 1. 桌面 · 自定义合约条目板
BOARD_SEL = {"shell": 2, "fangs": 1, "surge": 1, "colossus": 2, "fury": 1, "gutter": 1, "mire": 1, "cold": 1, "night": 1, "endless": 1}
FOCUS = "mire"


def header(img, cn, en, tabs_sel, x=28, phone=False, s=1.0):
    ptxt(img, (x, int(30 * s)), "OPERATION // CONTRACT", 1, CY, 1, "lm")
    w = text(img, (x, int(58 * s)), cn, int(26 * s), TXT, "lm", bold=True)
    ptxt(img, (x + w + 14, int(60 * s)), en, 2, TXT2, 2, "lm")
    # 推荐 / 自定义 两个页签（Q / E、LB / RB）
    tx = x + w + 14 + len(en) * 16 + 40
    for i, (lab, key) in enumerate((("推荐合约", "Q"), ("自定义合约", "E"))):
        bw = int(132 * s)
        box = (tx + i * (bw + 8), int(42 * s), tx + i * (bw + 8) + bw, int(74 * s))
        if i == tabs_sel:
            sel_block(img, box, 2, 2, water=0, glow_on=False)
            text(img, (box[0] + 14, (box[1] + box[3]) / 2), lab, int(15 * s), NAVY_INK, "lm", bold=False)
            ptxt(img, (box[2] - 10, (box[1] + box[3]) / 2), key, 1, SEL_IDX, 1, "rm")
        else:
            panel(img, box, 2, 2)
            text(img, (box[0] + 14, (box[1] + box[3]) / 2), lab, int(15 * s), TXT2, "lm")
            ptxt(img, (box[2] - 10, (box[1] + box[3]) / 2), key, 1, TXT2, 1, "rm")
    return tx


def summary_list(img, x0, y0, x1, lines, fs=13, lh=20, cols=1):
    n = len(lines)
    per = math.ceil(n / cols)
    cw = (x1 - x0) / cols
    for i, (a, b, kind) in enumerate(lines):
        cx = x0 + (i // per) * cw
        y = y0 + (i % per) * lh
        col = TXT if kind == "up" else CY
        mark = CY if kind == "up" else (60, 200, 150)
        d = ImageDraw.Draw(img)
        d.rectangle([cx, y - 2, cx + 3, y + 1], fill=mark)
        text(img, (cx + 10, y), a, fs, col if kind == "up" else (140, 220, 200), "lm")
        if b:
            ptxt(img, (cx + cw - 12, y), b, 1, col if kind == "up" else (140, 220, 200), 1, "rm")


def board_desktop():
    img = bg(k=170)
    header(img, "自定义合约", "CUSTOM", 1)
    base = dmod_default()
    total = risk(BOARD_SEL)
    tide_gauge(img, (24, 100, 108, 664), total, [(0, ""), (risk(PRESETS["hard"]), "IV"), (risk(PRESETS["extreme"]), "VIII")], best=18)
    # 条目板：五组五列
    bx0, bx1 = 150, 900
    g = 8
    cw = (bx1 - bx0 - g * 4) / 5
    for ci, (gid, gcn, gen) in enumerate(GROUPS):
        x = bx0 + ci * (cw + g)
        d = ImageDraw.Draw(img)
        d.rectangle([x, 118, x + cw, 119], fill=GRP_COL[gid])
        text(img, (x + 2, 104), gcn, 14, TXT, "lm", bold=False)
        ptxt(img, (x + cw - 2, 104), gen.split(" ")[0], 1, TXT2, 1, "rm")
        tags = [t for t in TAGS if t["grp"] == gid]
        for ri, t in enumerate(tags):
            y = 128 + ri * (116 + g)
            blk = None
            if t["id"] == "lonely":
                blk = "II 与永痕互斥"
            tag_card(img, (x, y, x + cw, y + 116), t, BOARD_SEL.get(t["id"], 0), focus=(t["id"] == FOCUS), blocked=None)
            if blk:
                text(img, (x + cw - 10, y + 92), blk, 11, (255, 130, 170), "rm")
    # 底部：焦点条目说明条
    (fx0, fy0, fx1, fy1), _ = panel(img, (150, 630, 900, 672), 2, 2)
    t = TAG[FOCUS]
    ticon(img, t["ic"], fx0 + 22, (fy0 + fy1) / 2, 1, CY, GRP_COL[t["grp"]])
    w0 = text(img, (fx0 + 38, (fy0 + fy1) / 2), "%s %s" % (t["cn"], roman(BOARD_SEL[FOCUS])), 15, TXT, "lm", bold=False)
    text(img, (fx0 + 50 + w0, (fy0 + fy1) / 2), "自然溟痕不再消散，只有点亮的引航灯标能驱散；灯标刷新间隔 ×0.75（补偿）", 13, TXT2, "lm")
    # 右：合约档案
    rx0, ry0, rx1, ry1 = 920, 100, 1256, 600
    panel(img, (rx0, ry0, rx1, ry1), 2, 3, a=236)
    ptxt(img, (rx0 + 18, ry0 + 20), "CONTRACT FILE // CUSTOM", 1, CY, 1, "lm")
    text(img, (rx0 + 18, ry0 + 50), "潮位", 16, TXT2, "lm")
    ptxt(img, (rx0 + 64, ry0 + 52), str(total), 4, TXT, 1, "lm")
    text(img, (rx0 + 150, ry0 + 42), "推荐合约  IV = %d · VIII = %d" % (risk(PRESETS["hard"]), risk(PRESETS["extreme"])), 12, TXT2, "lm")
    text(img, (rx0 + 150, ry0 + 62), "斯卡蒂 最佳 18 · 本合约 +%d" % (total - 18), 12, GOLD, "lm")
    d = ImageDraw.Draw(img)
    d.rectangle([rx0 + 18, ry0 + 84, rx1 - 18, ry0 + 85], fill=(40, 80, 104))
    ptxt(img, (rx0 + 18, ry0 + 100), "ACTIVE MODIFIERS", 1, TXT2, 1, "lm")
    text(img, (rx0 + 150, ry0 + 100), "生效修正（%d 条）" % len([x for x in mod_lines(compose(BOARD_SEL, base)) if x[2] == "up"]), 12, TXT2, "lm")
    lines = mod_lines(compose(BOARD_SEL, base))
    summary_list(img, rx0 + 18, ry0 + 124, rx1 - 6, lines, 13, 19)
    # 出发 / 返回 / 清空
    (ox0, oy0, ox1, oy1), om = panel(img, (920, 612, 1128, 672), 2, 3, a=240)
    solid(img, ox0, oy0, edge_of(om, 2), CY)
    text(img, (ox0 + 56, (oy0 + oy1) / 2), "出发", 22, TXT, "lm", bold=True)
    for i in range(3):
        xx = ox0 + 18 + i * 8
        d.line([(xx, oy0 + 22), (xx + 6, (oy0 + oy1) / 2), (xx, oy1 - 22)], fill=CY, width=2)
    ptxt(img, (ox1 - 12, (oy0 + oy1) / 2), "ENTER", 1, TXT2, 1, "rm")
    for i, (lab, key) in enumerate((("返回", "ESC"), ("清空", "R"))):
        (b0, b1, b2, b3), _ = panel(img, (1138, 612 + i * 32, 1256, 640 + i * 32), 2, 2)
        text(img, (b0 + 12, (b1 + b3) / 2), lab, 13, TXT, "lm")
        ptxt(img, (b2 - 8, (b1 + b3) / 2), key, 1, TXT2, 1, "rm")
    ptxt(img, (W - 24, 700), "↑↓←→ SELECT   ENTER +TIER   BACKSPACE -TIER   0-3 SET   Q/E PAGE", 1, TXT2, 1, "rm")
    return img


# ---------------------------------------------------------------- 2. 桌面 · 推荐合约
def preset_cards(img, cards, sel, ry, x0=156, x1=556, P=2):
    d = ImageDraw.Draw(img)
    for i, (cy, num, nm, en, desc, r, extra) in enumerate(cards):
        box = (x0, cy - 42, x1, cy + 42)
        if i == sel:
            (bx0, by0, bx1, by1), m, crest = sel_block(img, box, P, 3, water=0.1)
            tc, sc = NAVY_INK, SEL_SUB
        else:
            (bx0, by0, bx1, by1), m = panel(img, box, P, 3, a=230)
            tc, sc = TXT, TXT2
        # 刻度连线：卡片 → 潮位尺上的风险刻度
        ty = ry(r)
        d.line([(120, ty), (136, ty), (136, cy), (bx0 - 4, cy)], fill=CY if i == sel else CY_DIM, width=2)
        if num == "C":
            ticon(img, "custom", bx0 + 46, cy - 4, 3, tc, CY if i != sel else SEL_IDX)
        else:
            ptxt(img, (bx0 + 22, cy), num, 4 if len(num) < 4 else 3, tc, 1, "lm")
        wn = text(img, (bx0 + 132, by0 + 28), nm, 21, tc, "lm", bold=True)
        ptxt(img, (bx0 + 134, by0 + 51), en, 1, tc, 2, "lm")
        text(img, (bx0 + 132, by0 + 68), desc, 13, sc, "lm")
        ptxt(img, (bx1 - 12, by0 + 14), "TIDE %d" % r, 1, sc, 1, "rm")
        if extra:
            ptxt(img, (bx1 - 12, by1 - 14), extra, 1, GOLD if i != sel else (150, 110, 20), 1, "rm")


def presets_desktop():
    img = bg(k=140)
    header(img, "选择潮位", "TIDE LEVEL", 0)
    rH, rX = risk(PRESETS["hard"]), risk(PRESETS["extreme"])
    cust = risk(BOARD_SEL)
    ry = tide_gauge(img, (24, 100, 108, 664), rX, [(0, ""), (rH, ""), (rX, ""), (cust, "")], best=18, label=False)
    cards = [(160, "C", "自定义合约", "CUSTOM CONTRACT", "上次的 10 条合约 · 进入条目板", cust, "BEST 18"),
             (300, "VIII", "波涛迭起", "RISING TIDE VIII", "大海不再留情。", rX, ""),
             (440, "IV", "波涛迭起", "RISING TIDE IV", "暗礁更多，灯火更难守住。", rH, "CLEAR"),
             (580, "0", "波涛迭起", "RISING TIDE", "海洋的真容，才刚刚显露。", 0, "CLEAR")]
    preset_cards(img, cards, 1, ry)
    # 右：合约档案 = 条目片 + 修正项
    rx0, ry0, rx1, ry1 = 612, 100, 1256, 600
    panel(img, (rx0, ry0, rx1, ry1), 2, 3, a=236)
    ptxt(img, (rx0 + 22, ry0 + 22), "CONTRACT FILE // RISING TIDE VIII", 1, CY, 1, "lm")
    text(img, (rx0 + 22, ry0 + 52), "大海不再留情。", 18, TXT, "lm")
    ptxt(img, (rx1 - 22, ry0 + 50), "TIDE %d" % rX, 2, TXT, 1, "rm")
    ptxt(img, (rx0 + 22, ry0 + 84), "TAGS", 1, TXT2, 1, "lm")
    text(img, (rx0 + 64, ry0 + 84), "推荐合约 = 下面 %d 条合约之和（逐键与现行 VIII 表相同）" % len(PRESETS["extreme"]), 12, TXT2, "lm")
    sel = PRESETS["extreme"]
    keys = [t["id"] for t in TAGS if t["id"] in sel]
    cw, chh = 196, 44
    for i, k in enumerate(keys):
        t = TAG[k]
        cx = rx0 + 22 + (i % 3) * (cw + 8)
        cy = ry0 + 100 + (i // 3) * (chh + 6)
        (a0, a1, a2, a3), _ = panel(img, (cx, cy, cx + cw, cy + chh), 2, 2, N_ACT, 236, CY + (200,))
        d = ImageDraw.Draw(img)
        d.rectangle([a0 + 4, a1 + 8, a0 + 5, a3 - 8], fill=GRP_COL[t["grp"]])
        ticon(img, t["ic"], a0 + 22, (a1 + a3) / 2, 1, (200, 226, 238), GRP_COL[t["grp"]])
        text(img, (a0 + 38, (a1 + a3) / 2 - 1), t["cn"], 15, TXT, "lm")
        ptxt(img, (a0 + 38 + 16 * len(t["cn"]) + 10, (a1 + a3) / 2), roman(sel[k]), 1, CY, 1, "lm")
        ptxt(img, (a2 - 10, (a1 + a3) / 2), "+%d" % t["tiers"][sel[k] - 1][1], 2, CY, 1, "rm")
    yy = ry0 + 100 + 3 * (chh + 6) + 10
    d = ImageDraw.Draw(img)
    d.rectangle([rx0 + 22, yy, rx1 - 22, yy + 1], fill=(40, 80, 104))
    ptxt(img, (rx0 + 22, yy + 16), "ACTIVE MODIFIERS", 1, TXT2, 1, "lm")
    summary_list(img, rx0 + 22, yy + 38, rx1 - 10, mod_lines(compose(sel, dmod_default())), 13, 19, cols=2)
    # 出发 / 返回 / 在条目板里改
    (ox0, oy0, ox1, oy1), om = panel(img, (612, 620, 912, 680), 2, 3, a=240)
    solid(img, ox0, oy0, edge_of(om, 2), CY)
    text(img, (ox0 + 64, (oy0 + oy1) / 2), "出发", 24, TXT, "lm", bold=True)
    for i in range(3):
        xx = ox0 + 22 + i * 9
        d.line([(xx, oy0 + 20), (xx + 7, (oy0 + oy1) / 2), (xx, oy1 - 20)], fill=CY, width=2)
    ptxt(img, (ox1 - 16, (oy0 + oy1) / 2), "ENTER", 1, TXT2, 1, "rm")
    for i, (lab, key, x0_, x1_) in enumerate((("以此为底自定义", "Y", 932, 1124), ("返回", "ESC", 1136, 1256))):
        (b0, b1, b2, b3), _ = panel(img, (x0_, 628, x1_, 672), 2, 2)
        text(img, (b0 + 14, (b1 + b3) / 2), lab, 15, TXT, "lm")
        ptxt(img, (b2 - 12, (b1 + b3) / 2), key, 1, TXT2, 1, "rm")
    ptxt(img, (W - 24, 700), "↑↓ CHANGE TIDE   Q/E PAGE   Y EDIT AS CUSTOM", 1, TXT2, 1, "rm")
    return img


# ---------------------------------------------------------------- 3. 手机 · 条目板（1480×720 屏幕像素 = UI 逻辑约 1044×481 × 1.42）
def board_phone():
    img = bg(phone=True, k=175)
    s = 1.42
    P = 2
    ptxt(img, (36, 30), "OPERATION // CONTRACT", 1, CY, 1, "lm")
    w = text(img, (36, 64), "自定义合约", 34, TXT, "lm", bold=True)
    for i, lab in enumerate(("推荐合约", "自定义合约")):
        box = (36 + w + 30 + i * 196, 40, 36 + w + 30 + i * 196 + 186, 88)
        if i == 1:
            sel_block(img, box, P, 2, water=0, glow_on=False)
            text(img, (box[0] + 20, 64), lab, 21, NAVY_INK, "lm")
        else:
            panel(img, box, P, 2)
            text(img, (box[0] + 20, 64), lab, 21, TXT2, "lm")
    total = risk(BOARD_SEL)
    # 右上：潮位大字 + 干员最佳
    text(img, (PHW - 300, 64), "潮位", 22, TXT2, "lm")
    ptxt(img, (PHW - 240, 66), str(total), 5, TXT, 1, "lm")
    text(img, (PHW - 36, 50), "斯卡蒂 最佳 18", 18, GOLD, "rm")
    text(img, (PHW - 36, 78), "IV %d · VIII %d" % (risk(PRESETS["hard"]), risk(PRESETS["extreme"])), 18, TXT2, "rm")
    tide_gauge(img, (24, 110, 92, 606), total, [(risk(PRESETS["hard"]), ""), (risk(PRESETS["extreme"]), "")], best=18, big=False, label=False)
    bx0, bx1 = 112, PHW - 24
    g = 10
    cw = (bx1 - bx0 - g * 4) / 5
    for ci, (gid, gcn, gen) in enumerate(GROUPS):
        x = bx0 + ci * (cw + g)
        d = ImageDraw.Draw(img)
        d.rectangle([x, 128, x + cw, 129], fill=GRP_COL[gid])
        text(img, (x + 2, 114), gcn, 18, TXT, "lm")
        tags = [t for t in TAGS if t["grp"] == gid]
        for ri, t in enumerate(tags):
            y = 138 + ri * (110 + g)
            tag_card(img, (x, y, x + cw, y + 110), t, BOARD_SEL.get(t["id"], 0), focus=(t["id"] == "shell"), s=1.25, compact=True,
                     show_eff=False)
    # 底栏：修正抽屉按钮 + 操作提示 + 出发
    (a0, a1, a2, a3), _ = panel(img, (112, 626, 520, 700), P, 3, a=236)
    n_up = len([x for x in mod_lines(compose(BOARD_SEL, dmod_default())) if x[2] == "up"])
    text(img, (a0 + 22, (a1 + a3) / 2), "生效修正 %d 条" % n_up, 22, TXT, "lm")
    ptxt(img, (a2 - 22, (a1 + a3) / 2), "^", 2, CY, 1, "rm")
    text(img, (a2 - 40, (a1 + a3) / 2), "展开", 18, CY, "rm")
    text(img, (540, (a1 + a3) / 2 - 12), "点按卡片：升一档（满档再点归零）", 17, TXT2, "lm")
    text(img, (540, (a1 + a3) / 2 + 14), "长按卡片：说明 + 大号档位键（≥ 44）", 17, TXT2, "lm")
    (ox0, oy0, ox1, oy1), om = panel(img, (PHW - 340, 620, PHW - 24, 704), P, 3, a=240)
    solid(img, ox0, oy0, edge_of(om, P), CY)
    text(img, (ox0 + 84, (oy0 + oy1) / 2), "出发", 34, TXT, "lm", bold=True)
    d = ImageDraw.Draw(img)
    for i in range(3):
        xx = ox0 + 28 + i * 12
        d.line([(xx, oy0 + 26), (xx + 10, (oy0 + oy1) / 2), (xx, oy1 - 26)], fill=CY, width=3)
    # 长按「厚壳」：说明面板 + 大号档位键（每个 ≥ 44 逻辑像素）
    c1.over(img, lambda dd: dd.rectangle([0, 0, PHW, PHH], fill=(2, 6, 14, 110)))
    q0, q1, q2, q3 = 470, 214, 1180, 520
    panel(img, (q0, q1, q2, q3), P, 3, a=248, edge=CY + (255,))
    t = TAG["shell"]
    ticon(img, t["ic"], q0 + 40, q1 + 40, 3, (200, 226, 238), GRP_COL[t["grp"]])
    text(img, (q0 + 76, q1 + 34), "厚壳", 30, TXT, "lm", bold=True)
    ptxt(img, (q0 + 150, q1 + 38), "SHELL", 2, TXT2, 2, "lm")
    text(img, (q2 - 28, q1 + 36), "敌群", 20, GRP_COL["horde"], "rm")
    for j, ln in enumerate(wrap("所有小怪与精英生命提高（围猎圈上海嗣生命与时长同步下调作补偿）。IV 用 I 档，VIII 用 III 档。", 19, q2 - q0 - 60)):
        text(img, (q0 + 30, q1 + 84 + j * 28), ln, 19, TXT2, "lm")
    opts = [("不选", "0", 0)] + [("%s 档" % roman(i + 1), "+%d" % tr[1], i + 1) for i, tr in enumerate(t["tiers"])]
    bw = (q2 - q0 - 60 - 3 * 14) / 4
    for i, (lab, rk, lv) in enumerate(opts):
        bx = q0 + 30 + i * (bw + 14)
        box = (bx, q3 - 120, bx + bw, q3 - 30)
        if lv == BOARD_SEL["shell"]:
            sel_block(img, box, P, 2, water=0.18, glow_on=False)
            tc = NAVY_INK
        else:
            panel(img, box, P, 2)
            tc = TXT
        text(img, (bx + 18, q3 - 92), lab, 20, tc, "lm")
        ptxt(img, (bx + bw - 16, q3 - 92), rk, 2, tc, 1, "rm")
        eff = t["tiers"][lv - 1][0].replace("敌人生命 ", "") if lv else "-"
        text(img, (bx + 18, q3 - 58), eff, 17, tc if lv else TXT2, "lm")
    return img


# ---------------------------------------------------------------- 4. 胜利结算
def badge(img, cx, cy, r, k=2, best_iv=None, best_viii=None):
    """潮位徽记：像素六边盾 + 数字；档按推荐合约之和分段（随校准移动）"""
    iv = best_iv if best_iv is not None else risk(PRESETS["hard"])
    vi = best_viii if best_viii is not None else risk(PRESETS["extreme"])
    pat = ["....######....", "..##########..", ".############.", "##############", "##############", "##############",
           "##############", "##############", ".############.", "..##########..", "....######....", ".....####....."]
    hgt, wid = len(pat), len(pat[0])
    m = np.array([[ch == "#" for ch in row] for row in pat])
    e = m & ~(np.roll(m, 1, 0) & np.roll(m, -1, 0) & np.roll(m, 1, 1) & np.roll(m, -1, 1))
    if r is None:
        fill, edge, num = (14, 26, 44), (60, 74, 92), (90, 104, 120)
    elif r == 0:
        fill, edge, num = (14, 30, 52), STEEL, (180, 196, 214)
    elif r < iv:
        fill, edge, num = (12, 30, 54), CY, CY
    elif r < vi:
        fill, edge, num = (24, 92, 118), CY, (220, 255, 255)
    else:
        fill, edge, num = NEAR_WHITE, SEL_EDGE, NAVY_INK
    arr = np.zeros((hgt, wid, 4), np.uint8)
    arr[m] = fill + (255,)
    arr[e] = edge + (255,)
    if r is not None and r >= vi + 10:
        arr[8:10, 3:11][m[8:10, 3:11]] = (90, 200, 230, 255)
    im = Image.fromarray(arr, "RGBA").resize((wid * k, hgt * k), Image.NEAREST)
    x0, y0 = int(cx - wid * k / 2), int(cy - hgt * k / 2)
    if r is not None and r >= vi + 10:
        gm = Image.new("L", img.size, 0)
        gm.paste(im.getchannel("A"), (x0, y0))
        glow(img, gm, FOAM_GLOW, 3 * k, (0.08, 0.3), (40, 90), cell=k)
    img.alpha_composite(im, (x0, y0))
    lab = "-" if r is None else str(r)
    ptxt(img, (cx, cy - k), lab, max(1, k // 2), num, 1, "mm")


def chip(img, x, y, s, col, size=13, sub=None):
    """局内 A 风格标签片：暗底 + 左色条（UI.chip）"""
    f = c1.F(size, s)
    tw = f.getlength(s) + (f.getlength(sub) + 6 if sub else 0)
    w = tw + 22
    c1.over(img, lambda d: d.rectangle([x, y, x + w, y + size + 12], fill=(16, 22, 30, 230)))
    d = ImageDraw.Draw(img)
    d.rectangle([x, y, x + 3, y + size + 12], fill=col)
    text(img, (x + 12, y + (size + 12) / 2), s, size, (228, 236, 244), "lm")
    if sub:
        text(img, (x + 12 + f.getlength(s) + 6, y + (size + 12) / 2), sub, size, col, "lm")
    return w


def settlement():
    p = os.path.join(MAIN, "build", "motion", "shots", "win", "shot_win.png")
    img = Image.open(p).convert("RGBA").resize((W, H)) if os.path.exists(p) else Image.new("RGBA", (W, H), (10, 14, 22, 255))
    c1.over(img, lambda d: d.rectangle([0, 0, W, H], fill=(4, 8, 14, 120)))
    x0, y0, x1, y1 = 150, 86, 830, 648
    col = (232, 160, 210)

    def pnl(d):
        d.rectangle([x0, y0, x1, y1], fill=(24, 26, 32, 255))
        d.rectangle([x0, y0, x1, y0 + 1], fill=(232, 160, 210, 255))
        d.rectangle([x0, y0, x1, y1], outline=(70, 76, 88, 255))
    c1.over(img, pnl)
    ptxt(img, ((x0 + x1) / 2, y0 + 40), "PRECIOUS DAYS", 1, col, 3, "mm")
    text(img, ((x0 + x1) / 2, y0 + 78), "结局一 · 平凡即是喜乐 · 探索完成", 30, (240, 242, 246), "mm", bold=False)
    d = ImageDraw.Draw(img)
    d.line([(x0 + 40, y0 + 78), (x0 + 74, y0 + 78)], fill=(240, 242, 246), width=2)
    d.line([(x1 - 74, y0 + 78), (x1 - 40, y0 + 78)], fill=(240, 242, 246), width=2)
    chip(img, x0 + 24, y0 + 14, "新纪录", GOLD, 12)
    # 左：统计四行（合约取代「难度」）
    rows = [("探索时间", "11:42"), ("等级", "Lv.26  精英二"), ("击杀", "5 233"), ("合约", "自定义 · 10 条")]
    for i, (a, b) in enumerate(rows):
        y = y0 + 128 + i * 32
        d.polygon([(x0 + 44, y), (x0 + 48, y - 4), (x0 + 52, y), (x0 + 48, y + 4)], fill=col)
        text(img, (x0 + 62, y), a, 16, (150, 160, 176), "lm")
        text(img, (x0 + 200, y), b, 18, (240, 242, 246), "lm")
    # 右：潮位徽记（大）
    total = risk(BOARD_SEL)
    bx, by = x1 - 150, y0 + 178
    c1.over(img, lambda dd: dd.rectangle([bx - 110, by - 74, bx + 110, by + 86], fill=(12, 22, 38, 230)))
    ptxt(img, (bx, by - 58), "TIDE // 潮位".split(" //")[0], 1, CY, 2, "mm")
    badge(img, bx, by + 2, total, k=8)
    text(img, (bx, by + 68), "斯卡蒂 18 → %d" % total, 15, GOLD, "mm")
    # 合约条目片（两行）
    ptxt(img, (x0 + 44, y0 + 272), "CONTRACT", 1, (150, 160, 176), 2, "lm")
    text(img, (x0 + 130, y0 + 272), "本局合约（%d 条，潮位 %d）" % (len(BOARD_SEL), total), 14, (150, 160, 176), "lm")
    cx, cy = x0 + 44, y0 + 292
    for t in TAGS:
        if t["id"] not in BOARD_SEL:
            continue
        lv = BOARD_SEL[t["id"]]
        lab = "%s %s" % (t["cn"], roman(lv))
        f = c1.F(13, lab)
        w = f.getlength(lab) + f.getlength("+%d" % t["tiers"][lv - 1][1]) + 30
        if cx + w > x1 - 40:
            cx, cy = x0 + 44, cy + 34
        cx += chip(img, cx, cy, lab, GRP_COL[t["grp"]], 13, "+%d" % t["tiers"][lv - 1][1]) + 8
    # 纪录三行
    yb = cy + 52
    d.line([(x0 + 40, yb - 14), (x1 - 40, yb - 14)], fill=(60, 66, 78), width=1)
    rec = [("斯卡蒂 · 干员最佳", "18 → %d" % total, "新纪录", GOLD), ("全干员最佳", "26（维什戴尔）", "", None),
           ("通关过合约的干员", "7 / 14", "", None)]
    for i, (a, b, tag, tc) in enumerate(rec):
        y = yb + 8 + i * 30
        text(img, (x0 + 62, y), a, 16, (150, 160, 176), "lm")
        w = text(img, (x0 + 250, y), b, 18, (240, 242, 246), "lm")
        if tag:
            chip(img, x0 + 262 + w, y - 12, tag, tc, 12)
    # 按钮
    for i, (lab, key) in enumerate((("同合约再来", "R"), ("修改合约", "C"), ("回到标题", "T"))):
        bw = (x1 - x0 - 80 - 24) / 3
        bx0 = x0 + 40 + i * (bw + 12)
        c1.over(img, lambda dd, bx0=bx0, bw=bw, i=i: dd.rectangle([bx0, y1 - 66, bx0 + bw, y1 - 26],
                                                                 fill=(54, 226, 220, 255) if i == 0 else (126, 152, 184, 102)))
        text(img, (bx0 + 14, y1 - 46), lab, 15, (10, 18, 22) if i == 0 else (240, 242, 246), "lm")
        d.rectangle([bx0 + bw - 28, y1 - 56, bx0 + bw - 10, y1 - 37], outline=(10, 18, 22) if i == 0 else (240, 242, 246))
        text(img, (bx0 + bw - 19, y1 - 46), key, 12, (10, 18, 22) if i == 0 else (240, 242, 246), "mm")
    # 失败时的样子（注释条）
    c1.over(img, lambda dd: dd.rectangle([150, 660, 1130, 708], fill=(10, 12, 18, 220)))
    text(img, (166, 684), "失败 / 超时：合约片与潮位照常列出，纪录行换成「本局未通关 · 不计入纪录」，按钮同上；Boss 演练与练习不显示合约。", 14, (170, 180, 196), "lm")
    return img


# ---------------------------------------------------------------- 5. 选人 / 图鉴徽记
def badges():
    img = Image.new("RGBA", (W, H), (14, 16, 22, 255))
    text(img, (24, 28), "潮位徽记：每名干员「通关过的最高潮位」。选人名册卡、图鉴名册卡、干员档案；只是荣誉，不解锁任何东西", 17, (230, 234, 240), "lm")
    cap = (170, 180, 196)
    # ---- 选人名册（B+）：卡片 x = 72 + 90i（宽 80），y 573–685
    op = os.path.join(c1.SHOTS, "oppick", "shot_oppick.png")
    vals = [21, 12, None, 18, 8, 0, 26, None, 33, 10]
    if os.path.exists(op):
        src = Image.open(op).convert("RGBA").resize((W, H))
        ox, oy = 20 - 60, 60 - 556          # 截取 (60, 556)–(980, 700) 贴到 (20, 60)
        img.alpha_composite(src.crop((60, 556, 980, 700)), (20, 60))
        for i, v in enumerate(vals):
            badge(img, 72 + i * 90 + 80 - 16 + ox, 685 - 42 + oy, v, k=2)
        # 顶栏小标：「难度 波涛迭起」→「合约 潮位 21」
        top = src.crop((940, 12, 1150, 44))
        img.alpha_composite(top, (980, 92))
        c1.over(img, lambda d: d.rectangle([980 + 10, 92 + 3, 980 + 102, 92 + 29], fill=(14, 22, 40, 255)))
        c1.over(img, lambda d: d.rectangle([980 + 10, 92 + 3, 980 + 102, 92 + 29], outline=(124, 120, 255, 255)))
        text(img, (980 + 18, 92 + 16), "合约 潮位 21", 13, (230, 236, 244), "lm")
        text(img, (980, 140), "顶栏小标：难度 → 合约潮位", 13, cap, "lm")
    text(img, (24, 218), "选人（B+）：名册卡右下角徽记 = 该干员的最佳潮位；没通关过合约写「-」", 14, cap, "lm")
    # ---- 左列：档案行
    if os.path.exists(op):
        img.alpha_composite(src.crop((80, 280, 520, 412)), (20, 246))
        c1.over(img, lambda d: d.rectangle([28, 382, 452, 416], fill=(14, 20, 40, 240)))
        badge(img, 48, 399, 18, k=2)
        text(img, (70, 399), "合约纪录  最佳潮位 18 · 10 条 · 结局三 · 10-12", 14, (230, 236, 244), "lm")
    cx_ = os.path.join(MAIN, "build", "codex_impl", "glass", "after_op.png")
    if os.path.exists(cx_):
        csrc = Image.open(cx_).convert("RGBA").resize((W, H))
        img.alpha_composite(csrc.crop((444, 470, 830, 560)), (20, 440))
        c1.over(img, lambda d: d.rectangle([26, 532, 406, 566], fill=(30, 30, 34, 240)))
        badge(img, 46, 549, 26, k=2)
        text(img, (68, 549), "合约纪录  最佳潮位 26 · 11 条 · 结局二", 14, (236, 238, 240), "lm")
    text(img, (24, 594), "档案：名字区下一行「合约纪录」；点开列出这名干员", 14, cap, "lm")
    text(img, (24, 616), "最佳那一局的合约条目、结局、日期（按条目重算潮位）", 14, cap, "lm")
    # ---- 中列：图鉴名册（C4'）：卡片 x = 76 + 88c（宽 80），y = 86 + 120r（高 110）
    if os.path.exists(cx_):
        k = 0.78
        crop = csrc.crop((70, 80, 426, 560))
        crop = crop.resize((int(crop.width * k), int(crop.height * k)), Image.LANCZOS)
        gx, gy = 480, 236
        img.alpha_composite(crop, (gx, gy))
        cvals = [21, 12, None, 18, 8, 0, 26, None, 33, 10, None, 4, None, None, None]
        for i, v in enumerate(cvals):
            r_, c_ = i // 4, i % 4
            x1c = 76 + c_ * 88 + 80
            y1c = 86 + r_ * 120 + 110
            badge(img, gx + (x1c - 14 - 70) * k, gy + (y1c - 36 - 80) * k, v, k=2)
    text(img, (480, 626), "图鉴（C4'）：同一枚徽记，冷色，不用警示黄", 14, cap, "lm")
    # ---- 右列：分段
    sx = 820
    text(img, (sx, 246), "分段（按推荐合约之和，随校准移动）", 15, (230, 234, 240), "lm")
    iv, vi = risk(PRESETS["hard"]), risk(PRESETS["extreme"])
    spec = [(None, "未通关：暗灰空盾，写「-」"), (0, "通关「波涛迭起」（潮位 0）：钢蓝边"),
            (iv - 3, "潮位 1 – %d：藏青底 + 青边" % (iv - 1)), (iv + 2, "潮位 %d – %d（≥ IV）：潮水底 + 青边" % (iv, vi - 1)),
            (vi + 1, "潮位 %d – %d（≥ VIII）：S4 反白 + 细青边" % (vi, vi + 9)), (vi + 13, "潮位 ≥ %d：反白 + 潮线 + 泡沫光" % (vi + 10))]
    for i, (v, s_) in enumerate(spec):
        y = 296 + i * 64
        badge(img, sx + 32, y, v, k=4)
        text(img, (sx + 74, y), s_, 14, (200, 208, 220), "lm")
    return img

# ---------------------------------------------------------------- 总览
def main():
    os.makedirs(OUT, exist_ok=True)
    ok = verify()
    outs = {"contracts_board": board_desktop(), "contracts_presets": presets_desktop(), "contracts_board_phone": board_phone(),
            "contracts_settlement": settlement(), "contracts_badges": badges()}
    for k, im in outs.items():
        p = os.path.join(OUT, k + ".png")
        im.convert("RGB").save(p)
        print("写出", p)
    c1.contact_sheet([
        ("条目板", [("桌面 · 自定义合约（潮位 %d）" % risk(BOARD_SEL), outs["contracts_board"]),
                 ("手机 · 自定义合约（1480×720）", outs["contracts_board_phone"])]),
        ("推荐 / 结算", [("桌面 · 推荐合约（选中 VIII）", outs["contracts_presets"]), ("胜利结算 · 合约与纪录", outs["contracts_settlement"])]),
        ("徽记", [("选人 / 图鉴 · 潮位徽记", outs["contracts_badges"])]),
    ], "潮汐合约（危机合约式自选条目）概念图  docs/68", os.path.join(OUT, "contact_sheet.png"))
    if not ok:
        sys.exit(1)


if __name__ == "__main__":
    main()
