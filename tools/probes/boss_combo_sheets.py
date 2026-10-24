"""Boss 合并版示意图（docs/142b §8）：B 的主轴 + A 的新弹幕，每只一张、每栏一幕。
画法复用 boss_phase_sheets.py（弹幕形状、地面、颗粒）与 boss_axis_sheets.py（桩、路线、连线、冲刺标记、血条等）；
程序画的形状 + 现有帧条第 0 帧，不是游戏截图。

    python tools/probes/boss_combo_sheets.py            # 输出 build/boss_combo_sheets/<boss>.png
"""
import math, os, random, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import boss_phase_sheets as B
import boss_axis_sheets as X
from PIL import Image, ImageDraw

OUT = os.path.join(B.ROOT, "build", "boss_combo_sheets")
PW, PH = B.PW, B.PH
CX, CY = PW // 2, 150
put, gold, cring, dash, arrow, bar, pips, path = X.put, X.gold_mark, X.cyan_ring, X.dash_mark, X.arrow, X.bar, X.pips, X.path_line
fire, node = X.fire_line, X.node
W = (1, 1, 1)


def txt(d, xy, s, n=15):
    if xy[1] == 96:   # 说明文字统一放到栏顶标题下面，别压在本体上
        xy = (xy[0], 36)
        w = d.textlength(s, font=B.font(n))
        d.rectangle((xy[0] - 4, xy[1] - 2, xy[0] + w + 4, xy[1] + n + 6), fill=(0, 0, 0, 170))
    d.text(xy, s, font=B.font(n), fill=(255, 255, 255))


def tag(d, xy, s):
    """弹幕用处小标签：拦路 / 惩罚 / 定拍"""
    col = {"拦路": (255, 210, 90), "惩罚": (255, 120, 120), "定拍": (140, 220, 255)}[s]
    x, y = xy
    y = min(y, PH - 50)
    d.rectangle((x, y, x + 34, y + 18), fill=(0, 0, 0, 200), outline=col)
    d.text((x + 3, y), s, font=B.font(13), fill=col)


def sheet(key, title, acts):
    rng = random.Random(5)
    for act in acts:
        if "P" in act:
            act["P"] = [(x, min(y, PH - 22)) for x, y in act["P"]]
    Wd = PW * len(acts) + 10 * (len(acts) + 1)
    H = 56 + PH + B.TXT_H + 10
    im = Image.new("RGBA", (Wd, H), (8, 10, 16, 255))
    d = ImageDraw.Draw(im)
    d.text((12, 12), title, font=B.font(24), fill=(240, 240, 240))
    for i, act in enumerate(acts):
        x = 10 + i * (PW + 10)
        im.alpha_composite(X.panel(act, rng), (x, 56))
        d.rectangle((x, 56, x + PW - 1, 56 + 30), fill=(0, 0, 0, 200))
        d.text((x + 10, 60), act["name"], font=B.font(18), fill=B.rgb(act["col"], 1.3))
        y = 56 + PH + 8
        for ln in act["lines"]:
            for w in B.wrap(ln, 34):
                d.text((x + 6, y), w, font=B.font(14), fill=(215, 220, 230))
                y += 19
    os.makedirs(OUT, exist_ok=True)
    p = os.path.join(OUT, key + ".png")
    im.convert("RGB").save(p, optimize=True)
    print(p)


PURPLE, MAGENTA, VOID = (0.8, 0.4, 1.0), (1.0, 0.35, 0.8), (0.55, 0.25, 0.8)
PARANOIA = ("“偏执泡影” · 合并版（主轴：冲刺穿身）", [
    {"name": "一 · 凝望：打落", "col": PURPLE, "draw": [
        lambda im, d: B.gap_ring(d, CX, CY + 40, 200, math.pi / 2 + 0.25, 0.6, PURPLE, 30),
        lambda im, d: B.beam(d, 40, CY + 95, PW - 40, CY + 80, 16, PURPLE),
        lambda im, d: B.circle(d, CX + 10, CY + 150, 30, PURPLE),
        lambda im, d: put(im, "e_paranoia", 0.55, CX, CY + 40),
        lambda im, d: dash(d, CX, CY + 60, 44),
        lambda im, d: d.line((CX - 40, CY + 200, CX + 10, CY + 70), fill=(255, 255, 255), width=3),
        lambda im, d: tag(d, (CX + 40, CY + 225), "拦路"),
        lambda im, d: txt(d, (20, 96), "泡影环缺口总朝着她 = 冲进去的路"),
    ], "P": [(CX - 40, CY + 205), (CX - 140, CY + 190), (CX + 120, CY + 195)],
     "lines": ["主轴：冲刺穿身 → 坠地 4 秒。", "弹幕：凝视两道平行光束截断冲刺路线；叠影实心圈；泡影环缺口总朝着她——缺口就是冲进去的路（拦路）。"]},
    {"name": "二 · 狂望：认真身", "col": MAGENTA, "ground": "mist_ring", "draw": [
        lambda im, d: B.beam(d, 80, CY + 60, PW - 60, CY + 230, 16, MAGENTA, "eye"),
        lambda im, d: B.beam(d, PW - 80, CY + 60, 60, CY + 230, 16, MAGENTA, "eye"),
        lambda im, d: d.ellipse((CX - 30, CY + 70, CX + 30, CY + 84), fill=(0, 0, 0, 220)),
        lambda im, d: put(im, "e_paranoia", 0.45, CX - 150, CY + 30, alpha=0.7),
        lambda im, d: put(im, "e_paranoia", 0.45, CX, CY + 30),
        lambda im, d: put(im, "e_paranoia", 0.45, CX + 150, CY + 30, alpha=0.7),
        lambda im, d: [B.gap_ring(d, x, CY + 20, 60, 1.2, 0.8, MAGENTA, 10, "tear") for x in (CX,)],
        lambda im, d: [d.ellipse((x + math.cos(a) * 55 - 4, CY + 20 + math.sin(a) * 27 - 4, x + math.cos(a) * 55 + 4, CY + 20 + math.sin(a) * 27 + 4), outline=(255, 255, 255, 90)) for x in (CX - 150, CX + 150) for a in [i * 0.63 for i in range(10)]],
        lambda im, d: tag(d, (40, CY + 200), "拦路"),
        lambda im, d: txt(d, (20, 96), "影子 + 只有真身的弹有伤害"),
    ], "lines": ["主轴：站离真身最近（自动攻击打最近的）、冲刺冲真身；认法：地上影子 + 只有真身放的泪滴弹是实的，幻影的是半透明空弹。", "弹幕：凝视改 X 交叉（斜着冲）；叠影分落三人双环。"]},
    {"name": "三 · 失声：打散光环", "col": VOID, "ground": "cracks", "draw": [
        lambda im, d: [d.ellipse((CX - r, CY + 40 - r * 0.5, CX + r, CY + 40 + r * 0.5), fill=B.rgb(VOID, 0.35, 55 + i * 15)) for i, r in enumerate((240, 170))],
        lambda im, d: B.gap_ring(d, CX, CY + 40, 140, 2.2, 0.55, VOID, 22),
        lambda im, d: B.gap_ring(d, CX, CY + 40, 205, 2.75, 0.55, VOID, 30),
        lambda im, d: put(im, "e_paranoia_phase2", 0.5, CX, CY + 60),
        lambda im, d: dash(d, CX, CY + 60, 44),
        lambda im, d: d.line((CX - 210, CY + 175, CX - 10, CY + 75), fill=(255, 255, 255), width=3),
        lambda im, d: tag(d, (CX - 250, CY + 130), "拦路"),
        lambda im, d: txt(d, (20, 96), "冲进去连穿两道缺口；光环散掉 5 秒不放呼号"),
    ], "P": [(CX - 215, CY + 178), (CX - 255, CY + 155), (CX - 175, CY + 198)],
     "lines": ["主轴：光环 −35%，冲刺穿身 = 光环散掉 5 秒（窗口期停火）。", "弹幕：泡影环 2 波错位（冲进去要连穿两道缺口，拦路）；呼号声波扇（光环在时每 6 秒一次，惩罚）。"]},
])

TEAL, BT2, WT = (0.25, 1.0, 0.6), (0.35, 0.75, 0.4), (0.8, 1.0, 0.85)   # 伊莎玛拉青绿系（用户 10-25）；二幕的红只放在预警外缘和地面血斑
BLOOD = (1.0, 0.3, 0.38)
RING = [(CX + math.cos(a) * 250, CY + 50 + math.sin(a) * 120) for a in (0.3, 1.2, 2.0, 2.9, 3.8, 5.4)]
ISHAR = ("伊莎玛拉 · 合并版（主轴：破网）", [
    {"name": "一 · 大群：绕一圈拆网", "col": TEAL, "draw": [
        lambda im, d: [d.line((CX, CY + 20, x, y - 20), fill=B.rgb(TEAL, 0.7, 180), width=2) for x, y in RING],
        lambda im, d: B.gap_ring(d, CX, CY + 40, 230, 0.75, 0.6, TEAL, 30),
        lambda im, d: B.beam(d, CX, CY + 40, CX - 230, CY + 220, 12, TEAL),
        lambda im, d: [put(im, "e_bone", 0.5, x, y) for x, y in RING],
        lambda im, d: [gold(d, x, y - 4, 18) for x, y in RING],
        lambda im, d: put(im, "e_ishar_t", 0.36, CX, CY + 50),
        lambda im, d: tag(d, (CX + 150, CY + 120), "拦路"),
        lambda im, d: txt(d, (20, 96), "歌环从她往外扩，正好扫过连线海嗣那一圈"),
    ], "P": [(CX + 200, CY + 135), (CX + 160, CY + 160), (CX + 240, CY + 160)],
     "lines": ["主轴：连线海嗣在 220–320 一圈，绕着走过去让自动攻击拆。", "弹幕：大群之歌缺口环正好扫过那一圈（拆网时要穿缺口，拦路）；三线扫射；撕咬（贴她太近才出，惩罚）。"]},
    {"name": "二 · 濒死强化：先打碎泪", "col": BT2, "draw": [
        lambda im, d: B.ground(d, "blood", BLOOD, CX, CY + 40, random.Random(3)),
        lambda im, d: B.beam(d, CX, CY + 40, CX - 170, CY + 80, 10, BT2),
        lambda im, d: B.beam(d, CX, CY + 40, CX + 170, CY + 80, 10, BT2),
        lambda im, d: [B.circle(d, CX - 170 + i * 45, CY + 140 + abs(i - 2) * 18 - 30, 18, BT2) for i in range(5)],
        lambda im, d: [d.ellipse((CX - 170 + i * 45 - 21, CY + 140 + abs(i - 2) * 18 - 30 - 11, CX - 170 + i * 45 + 21, CY + 140 + abs(i - 2) * 18 - 30 + 11), outline=B.rgb(BLOOD, 1.1), width=2) for i in range(5)],
        lambda im, d: [put(im, "e_tear", 0.7, x, CY + 100) for x in (CX - 170, CX + 170)],
        lambda im, d: [gold(d, x, CY + 96, 24) for x in (CX - 170, CX + 170)],
        lambda im, d: put(im, "e_ishar_t", 0.36, CX, CY + 40, tint=(0.95, 1.05, 0.95)),
        lambda im, d: tag(d, (CX - 60, CY + 205), "拦路"),
        lambda im, d: txt(d, (20, 96), "共鸣直线：从侧面接近泪，别走连线"),
    ], "P": [(CX - 120, CY + 200), (CX - 160, CY + 215), (CX - 80, CY + 220)],
     "lines": ["主轴：泪在场时断线会自动接回，先打碎泪。暗绿主色，「濒死强化」的红只在预警外缘和地面血斑。", "弹幕：泪落——5 个小落点沿弧线落在去泪的路上；泪与她之间的共鸣直线每 6 秒结算（拦路）；撕咬改 X 交叉剪。"]},
    {"name": "三 · 回声：拆网 + 音圈", "col": WT, "ground": "sound", "draw": [
        lambda im, d: B.gap_ring(d, CX, CY + 40, 150, 1.2, 0.6, WT, 22, "scale"),
        lambda im, d: B.gap_ring(d, CX, CY + 40, 230, 2.25, 0.6, WT, 30, "scale", 0.1),
        lambda im, d: [B.beam(d, CX, CY + 40, px, py, 8, WT) for px, py in ((CX + 10, CY + 190), (CX - 110, CY + 170), (CX + 140, CY + 175))],
        lambda im, d: [d.ellipse((x - 26, y - 13, x + 26, y + 13), outline=B.rgb(WT, 1.2), width=2) for x, y in RING[:3]],
        lambda im, d: put(im, "e_ishar_t", 0.36, CX, CY + 50, tint=(1.1, 1.15, 1.15)),
        lambda im, d: tag(d, (20, CY + 200), "定拍"),
        lambda im, d: txt(d, (20, 96), "三线分锁三人之后 2 秒不出招 = 拆网空档"),
    ], "P": [(CX + 10, CY + 190), (CX - 110, CY + 170), (CX + 140, CY + 175)],
     "lines": ["主轴：拆网；被杀的连线海嗣留音圈，1 秒后爆。", "弹幕：三线分锁三人（之后 2 秒空档，定拍）；大群之歌 2 圈鳞片弹（拦路）。"]},
])

G1, G2, G3 = (0.3, 0.5, 1.0), (0.5, 0.75, 1.0), (0.82, 0.9, 1.0)   # 伊祖米克群青系（用户 10-25），比小怪青蓝深、偏紫
IZUMIK = ("伊祖米克 · 合并版（主轴：拦截子代）", [
    {"name": "一 · 阐释：场边截杀", "col": G1, "ground": "roots", "draw": [
        lambda im, d: [B.circle(d, 210 - i * 30, CY + 60 + i * 30, 24, G1) for i in range(4)],
        lambda im, d: put(im, "e_izumik", 0.42, CX + 60, CY + 70),
        lambda im, d: [put(im, "e_offspring", 0.5, x, y) for x, y in ((60, CY + 120), (90, CY + 160), (50, CY + 190))],
        lambda im, d: [gold(d, x, y - 4, 16) for x, y in ((60, CY + 120), (90, CY + 160), (50, CY + 190))],
        lambda im, d: arrow(d, 16, CY + 150, 0.0, X.GOLD, 18),
        lambda im, d: tag(d, (220, CY + 150), "拦路"),
        lambda im, d: txt(d, (20, 96), "潮汐坠落落在你和这一批子代之间"),
    ], "P": [(170, CY + 190), (140, CY + 215), (210, CY + 210)],
     "lines": ["主轴：子代从场边走向她，迎上去让自动攻击在半路打掉。", "弹幕：潮汐坠落弧排落点落在你和子代之间（拦路）；回中间贴她时分享扇形（惩罚）。"]},
    {"name": "二 · 学习：两路 + 脚下的茧", "col": G2, "ground": "roots", "draw": [
        lambda im, d: B.spiral(d, CX, CY + 40, G2, 2),
        lambda im, d: put(im, "e_izumik", 0.42, CX, CY + 70, tint=(0.9, 1.0, 1.15)),
        lambda im, d: [d.ellipse((x - 14, y - 10, x + 14, y + 10), fill=B.rgb(G2, 0.6, 220), outline=(255, 255, 255)) for x, y in ((CX - 55, CY + 85), (CX + 50, CY + 90))],
        lambda im, d: [cring(d, x, y, 24, 0.45) for x, y in ((CX - 55, CY + 85), (CX + 50, CY + 90))],
        lambda im, d: arrow(d, 16, CY + 130, 0.0, X.GOLD, 18),
        lambda im, d: arrow(d, PW - 16, CY + 60, math.pi, X.GOLD, 18),
        lambda im, d: tag(d, (CX + 120, CY + 200), "拦路"),
        lambda im, d: txt(d, (20, 96), "回来打茧要从螺旋臂之间走进去"),
    ], "lines": ["主轴：两路子代；走到她身边先结茧 4 秒（主轴目标，自动攻击先打茧）。", "弹幕：解读旋涡改 2 条慢转螺旋弹臂，回来打茧要从臂间走进去（拦路）。"]},
    {"name": "三 · 分享：灯柱一根根熄灭", "col": G3, "ground": "fog", "draw": [
        lambda im, d: B.circle(d, 110, CY + 170, 52, (1.0, 0.9, 0.5), "ring"),
        lambda im, d: B.circle(d, PW - 110, CY + 170, 52, (0.4, 0.4, 0.4), "ring"),
        lambda im, d: [B.fan(d, CX, CY + 40, 190, math.pi / 2 + k, 0.3, G3) for k in (-0.9, 0.0, 0.9)],
        lambda im, d: put(im, "e_izumik", 0.42, CX, CY + 70),
        lambda im, d: tag(d, (CX - 17, CY + 150), "拦路"),
        lambda im, d: txt(d, (130, 96), "全场分享：预告 2–4.5 秒 + 蓄力 1.6 秒"),
    ], "P": [(110, CY + 170), (85, CY + 160), (135, CY + 160)],
     "lines": ["主轴：全场分享时躲进灯柱（灯柱内不受伤、留缓冲），每次分享后用过的灯柱熄灭。", "弹幕：分享扇形改三叶扇，挡在去下一根灯柱的路上（拦路）。"]},
])

I1, I2, I3, I4 = (0.55, 0.85, 1.0), (0.8, 0.95, 1.0), (0.3, 0.5, 0.95), (0.6, 0.8, 1.0)
KNIGHT = ("最后的骑士 · 合并版（主轴：斗牛）", [
    {"name": "一 · 骑士：引它撞桩", "col": I1, "P": [(CX + 150, CY + 170), (CX + 60, CY + 190), (CX + 210, CY + 150)], "draw": [
        lambda im, d: d.ellipse((CX - 150 - 140, CY + 60 - 70, CX - 150 + 140, CY + 60 + 70), outline=B.rgb(I1, 0.5, 120), width=2),
        lambda im, d: B.beam(d, CX - 150, CY + 20, CX + 150, CY + 170, 30, I1),
        lambda im, d: put(im, "prop_ice_stake", 0.7, CX + 40, CY + 125),
        lambda im, d: gold(d, CX + 40, CY + 120),
        lambda im, d: put(im, "e_knight", 0.8, CX - 150, CY + 60),
        lambda im, d: bar(d, 20, PH - 24, 150, 0.35, I1, "寒冷条（进寒气圈就涨）"),
    ], "lines": ["主轴：冲锋锁定后侧身，让它撞上桩 → 破绽 5 秒、受伤 ×2.0；打它的干员平时攻速 −30%。", "弹幕：冲锋（主轴本身）；长枪连刺扇形（贴近又不在破绽期才出，惩罚）。"]},
    {"name": "二 · 冰原：桩会碎，掷枪补桩", "col": I2, "ground": "frost", "draw": [
        lambda im, d: B.beam(d, CX - 160, CY + 30, CX + 170, CY + 190, 30, I2, "zig"),
        lambda im, d: B.circle(d, CX + 150, CY + 70, 40, I2, "dark", "hex"),
        lambda im, d: put(im, "prop_ice_stake", 0.6, CX + 150, CY + 85, alpha=0.5),
        lambda im, d: put(im, "e_knight", 0.8, CX - 160, CY + 70, tint=(1.05, 1.1, 1.2)),
        lambda im, d: tag(d, (CX - 30, CY + 150), "拦路"),
        lambda im, d: txt(d, (CX + 90, CY + 10), "掷枪落点 = 新桩", 14),
    ], "P": [(CX + 60, CY + 210), (CX + 10, CY + 220), (CX + 110, CY + 225)],
     "lines": ["主轴：桩撞一次就碎，新桩只能靠它掷枪补。", "弹幕：冲锋路径留锯齿冰棱带、冰面涨寒冷（去下一根桩要绕开，拦路）；掷枪落点用六角雪花纹预警，落地立桩。"]},
    {"name": "三 · 掷枪：折线冲锋", "col": I3, "ground": "abyss", "draw": [
        lambda im, d: B.beam(d, CX - 40, CY + 40, CX - 170, CY + 170, 28, I3),
        lambda im, d: B.beam(d, CX - 170, CY + 170, CX + 140, CY + 200, 28, I3),
        lambda im, d: put(im, "prop_ice_stake", 0.6, CX - 10, CY + 200),
        lambda im, d: gold(d, CX - 10, CY + 196),
        lambda im, d: put(im, "e_knight", 0.8, CX - 40, CY + 60, tint=(0.85, 0.95, 1.2)),
        lambda im, d: tag(d, (CX + 40, CY + 140), "拦路"),
        lambda im, d: txt(d, (20, 96), "第二冲转向你：桩要挡在第二段上"),
    ], "P": [(CX + 150, CY + 205), (CX + 110, CY + 225), (CX + 200, CY + 220)],
     "lines": ["主轴：掷枪 2 连补桩。", "弹幕：冲锋改 2 连折线，第二冲转向你——桩要挡在第二段上（拦路）。"]},
    {"name": "重生 · 冲锋形态：趁喘气打", "col": I4, "draw": [
        lambda im, d: B.beam(d, 40, CY + 110, PW - 40, CY + 110, 26, I4),
        lambda im, d: B.beam(d, PW - 40, CY + 150, 40, CY + 165, 26, I4),
        lambda im, d: B.beam(d, 40, CY + 205, PW - 40, CY + 200, 26, I4),
        lambda im, d: B.gap_ring(d, CX + 150, CY + 50, 90, math.pi, 0.7, I4),
        lambda im, d: put(im, "e_knight_walk_charge", 0.75, CX + 150, CY + 70),
        lambda im, d: cring(d, CX + 150, CY + 50, 70, 0.4),
        lambda im, d: tag(d, (CX + 100, CY - 30), "惩罚"),
    ], "lines": ["主轴：桩不管用了；躲过三连冲，喘气 2.5 秒里打（受伤 ×2.0）。", "弹幕：冲锋三连三条平行横扫（主轴本身）；喘气结束时还贴着它就吃长枪回旋（惩罚）。"]},
])

S1, S2 = (0.7, 0.8, 0.95), (0.55, 0.65, 1.0)
PATH = ("塑路者 · 合并版（主轴：截路）", [
    {"name": "一 · 探路：跑过路标，冲撞沿路线冲", "col": S1, "P": [(CX + 120, CY + 160), (CX + 40, CY + 185), (CX + 200, CY + 180)], "draw": [
        lambda im, d: path(d, [(CX, CY + 60), (CX + 80, CY + 110), (CX + 120, CY + 160), (CX + 230, CY + 190)], S1, cut=(CX + 120, CY + 160)),
        lambda im, d: [node(d, x, y) for x, y in ((CX + 40, CY + 85), (CX + 175, CY + 175))],
        lambda im, d: B.beam(d, CX, CY + 60, CX + 120, CY + 160, 26, S1),
        lambda im, d: put(im, "e_path", 0.5, CX, CY + 70),
        lambda im, d: put(im, "e_fractal", 0.45, CX + 185, CY + 192, tint=(0.8, 0.9, 1.2)),
        lambda im, d: gold(d, CX + 185, CY + 190),
        lambda im, d: tag(d, (CX + 140, CY + 110), "拦路"),
        lambda im, d: txt(d, (20, 96), "去碰路标 = 跑进冲撞道：锁定时先让开再回去"),
    ], "lines": ["主轴：跑过路线上的金色路标就截断（不用停），断口外分形变金色目标；全断 = 迷路 3 秒。", "弹幕：冲撞沿着它自己铺的路线冲（去碰路标就是跑进冲撞道，拦路）；震地（贴脸，惩罚）。"]},
    {"name": "二 · 订正：断口放刃环", "col": S2, "ground": "fractal", "draw": [
        lambda im, d: path(d, [(CX - 230, CY + 60), (CX - 150, CY + 130), (CX - 30, CY + 120), (CX, CY + 70)], S2, cut=(CX - 150, CY + 130)),
        lambda im, d: B.gap_ring(d, CX - 150, CY + 130, 60, 0.4, 0.8, S2, 12, "blade"),
        lambda im, d: B.beam(d, CX, CY + 70, CX + 180, CY + 130, 24, S2),
        lambda im, d: B.beam(d, CX + 180, CY + 130, CX + 60, CY + 210, 24, S2),
        lambda im, d: [B.circle(d, CX + 180 - k * 40, CY + 130 + k * 27, 26, S2, "solid", "tri") for k in range(3)],
        lambda im, d: put(im, "e_path", 0.5, CX, CY + 70, tint=(0.9, 0.95, 1.25)),
        lambda im, d: tag(d, (CX - 200, CY + 175), "惩罚"),
        lambda im, d: txt(d, (20, 96), "你每截断一条路，它就在断口放一圈订正刃环"),
    ], "P": [(CX - 185, CY + 150), (CX - 215, CY + 175), (CX - 150, CY + 180)],
     "lines": ["主轴：分形往回走、走回去回血；截断的路会改道。", "弹幕：订正刃环落在断口（截完马上走，惩罚）；冲撞 2 连直角折线；震地沿冲撞线 3 连。"]},
])

O1, O2 = (1.0, 0.45, 0.2), (0.95, 0.7, 0.3)
IBERIA = ("圣徒伊比利亚 · 合并版（主轴：打断装填）", [
    {"name": "一 · 圣徒：躲一炮再冲", "col": O1, "draw": [
        lambda im, d: B.beam(d, CX, CY + 40, CX + 30, PH - 10, 18, O1),
        lambda im, d: B.circle(d, CX - 80, CY + 130, 40, O1),
        lambda im, d: put(im, "e_saint_dark", 0.8, CX, CY + 60),
        lambda im, d: pips(d, CX - 7, CY - 50, 1, 0, O1),
        lambda im, d: bar(d, CX - 40, CY - 30, 80, 0.55, O1),
        lambda im, d: dash(d, CX, CY + 55, 40),
        lambda im, d: d.line((CX - 170, CY + 200, CX - 10, CY + 70), fill=(255, 255, 255), width=3),
        lambda im, d: tag(d, (CX - 160, CY + 100), "拦路"),
        lambda im, d: txt(d, (20, 96), "轰击落在你和他之间"),
    ], "P": [(CX - 170, CY + 200), (CX - 210, CY + 185), (CX - 130, CY + 215)],
     "lines": ["主轴：手炮之后装填 2.2 秒，冲刺穿身（或站在射程里打掉 5%）= 晕眩 5 秒。", "弹幕：手炮（主轴本身）；轰击落在你冲进去的路上（拦路）。"]},
    {"name": "二 · 延生：三角落点 + 清膛", "col": O2, "ground": "scorch", "draw": [
        lambda im, d: [B.circle(d, CX + math.cos(a) * 95, CY + 60 + math.sin(a) * 50, 30, O2, "solid", "tri") for a in (-math.pi / 2, math.pi / 6, 5 * math.pi / 6)],
        lambda im, d: put(im, "e_saint_dark", 0.8, CX, CY + 60, tint=(1.1, 0.95, 0.75)),
        lambda im, d: bar(d, CX - 40, CY - 30, 80, 0.3, O2),
        lambda im, d: dash(d, CX, CY + 55, 40),
        lambda im, d: d.line((CX - 200, CY + 205, CX - 10, CY + 75), fill=(255, 255, 255), width=3),
        lambda im, d: tag(d, (CX + 110, CY + 140), "拦路"),
        lambda im, d: txt(d, (20, 96), "装填前打出三角落点；没打断 = 清膛环 + 三连"),
    ], "P": [(CX - 200, CY + 205), (CX - 240, CY + 190), (CX - 160, CY + 220)],
     "lines": ["主轴：装填 1.4 秒，只认冲刺穿身；靠近时它先抡一下。", "弹幕：轰击三连曲射、落点排成三角围住它，从缝里穿进去（拦路）；没打断时放清膛缺口环接手炮三连（惩罚）。"]},
])

C1, C2 = (1.0, 0.94, 0.82), (1.0, 0.9, 0.65)
CARMEN = ("圣徒卡门 · 合并版（主轴：封锁线）", [
    {"name": "一 · 圣徒：三条平行火线", "col": C1, "P": [(CX - 40, CY + 205), (CX - 80, CY + 195), (CX, CY + 215)], "draw": [
        lambda im, d: [fire(d, 20, CY + 60 + k * 70, PW - 20, CY + 20 + k * 70, C1, gap=g) for k, g in ((0, 0.78), (1, 0.3), (2, 0.62))],
        lambda im, d: B.gap_ring(d, CX + 40, CY + 150, 90, 0.5, 0.7, C1, 16),
        lambda im, d: put(im, "e_saint", 0.8, PW - 70, CY + 20),
        lambda im, d: pips(d, PW - 91, CY - 90, 3, 0, C1),
        lambda im, d: tag(d, (CX + 120, CY + 185), "拦路"),
        lambda im, d: txt(d, (20, 96), "跑道里也要穿环射的缺口"),
    ], "lines": ["主轴：三枪留三条火线，每条留一处缺口、缺口错开，S 形穿过去绕到她身边；装填 3 秒压上去。", "弹幕：狙击（主轴本身，打完变火线）；环射缺口环的缺口落在某条跑道上（拦路）。"]},
    {"name": "二 · 守誓：交叉成格", "col": C2, "ground": "cross_cracks", "P": [(CX + 40, CY + 160), (CX, CY + 175), (CX + 80, CY + 180)], "draw": [
        lambda im, d: fire(d, 20, CY + 40, PW - 20, CY + 90, C2, gap=0.75),
        lambda im, d: fire(d, 20, CY + 150, PW - 20, CY + 200, C2, gap=0.2),
        lambda im, d: fire(d, CX - 120, 40, CX - 60, PH - 10, C2, gap=0.55),
        lambda im, d: B.beam(d, PW - 20, CY + 130, 20, CY + 160, 10, C2),
        lambda im, d: put(im, "e_saint", 0.8, 70, CY + 110),
        lambda im, d: B.circle(d, 110, CY + 170, 32, C2),
        lambda im, d: tag(d, (CX + 120, CY + 100), "定拍"),
        lambda im, d: txt(d, (20, 96), "第三枪锁你所在的跑道：1 秒里换格"),
    ], "lines": ["主轴：火线交叉成格，最后一枪锁你那条跑道；装填时她退避跳。", "弹幕：狙击分两个方向（第三枪锁你，定拍）；环射 2 波；追上去时炮身砸击（惩罚）。"]},
])

T1, T2, T3 = (0.25, 0.85, 0.9), (0.5, 0.95, 0.6), (0.65, 0.75, 1.0)
PAIR = ("接潮组 · 合并版（主轴：同步）", [
    {"name": "一：站位拉平血量", "col": T1, "draw": [
        lambda im, d: B.beam(d, 160, CY + 40, PW - 160, CY + 40, 8, T1),
        lambda im, d: [B.circle(d, PW - 170 + dx, CY + 130 + dy, 24, T1) for dx, dy in ((-60, 0), (0, 15), (60, 30))],
        lambda im, d: put(im, "e_bishop", 0.75, 130, CY + 70),
        lambda im, d: put(im, "e_archon", 0.7, PW - 130, CY + 70),
        lambda im, d: bar(d, 60, 100, 150, 0.35, T1, "主教 35%"),
        lambda im, d: bar(d, PW - 210, 100, 150, 0.7, T2, "蔑死体 70%"),
        lambda im, d: d.ellipse((90, CY + 30, 170, CY + 70), outline=B.rgb(T1, 1.3), width=4),
        lambda im, d: tag(d, (CX - 17, CY + 50), "拦路"),
    ], "P": [(PW - 170, CY + 190), (PW - 220, CY + 205), (PW - 120, CY + 210)],
     "lines": ["主轴：血量差 > 25% 时血少那具受伤 ×0.4，站到血多那具身边（两具隔 ≥360）。", "弹幕：两体之间的统一连线（不让你从中间穿过去换边，拦路）；潮汐柱；贴着打的那具出近身招（惩罚）。"]},
    {"name": "二 · 统一：换位 + 三角", "col": T1, "ground": "tide", "draw": [
        lambda im, d: B.beam(d, 160, CY + 40, PW - 160, CY + 40, 14, T1),
        lambda im, d: B.beam(d, 130, CY + 40, PW - 170, CY + 190, 12, T2),
        lambda im, d: B.beam(d, PW - 130, CY + 40, PW - 170, CY + 190, 12, T3),
        lambda im, d: put(im, "e_bishop", 0.75, 130, CY + 70, tint=(0.95, 1.1, 1.15)),
        lambda im, d: put(im, "e_archon", 0.7, PW - 130, CY + 70, tint=(1.0, 1.15, 0.95)),
        lambda im, d: arrow(d, PW - 175, CY + 40, 0.0, W),
        lambda im, d: arrow(d, 175, CY + 40, math.pi, W),
        lambda im, d: tag(d, (CX - 17, CY + 10), "定拍"),
        lambda im, d: txt(d, (CX - 80, CY - 15), "换位预警线 = 统一连线", 14),
    ], "P": [(PW - 170, CY + 190), (PW - 220, CY + 205), (PW - 120, CY + 210)],
     "lines": ["主轴：每 10 秒换位，换完重新选边。", "弹幕：换位的预警线就是统一连线、换位瞬间结算（定拍）；统一改三角——两体连线 + 各自连向队长，往三角外斜走（拦路）。"]},
])


if __name__ == "__main__":
    for k, (t, acts) in {"paranoia": PARANOIA, "ishar": ISHAR, "izumik": IZUMIK, "knight_boss": KNIGHT,
                          "path": PATH, "iberia": IBERIA, "carmen": CARMEN, "tide_pair": PAIR}.items():
        sheet(k, t, acts)
