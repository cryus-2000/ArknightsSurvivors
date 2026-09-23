extends RefCounted
## 游戏数据表：敌人、水月的成长项、技能、模组、藏品、组合

## 敌人：名称与机制按「水月与深蓝之树」，数值按本作换算
## ai: melee 近战追击 / ranged 进入射程后停下射击 / static 不移动
## 特殊字段：corrode 侵蚀比例、nerve 每次命中的神经损伤、role elite/boss
const ENEMIES = {
	# ---- 普通
	"bone": {"name": "骨海漂流体", "hp": 7.0, "spd": 64.0, "dmg": 5.0, "r": 10.0, "xp": 1.0, "tex": "e_bone", "ai": "melee", "corrode": 0.2},
	"slider": {"name": "底海滑动者", "hp": 12.0, "spd": 72.0, "dmg": 6.0, "r": 10.0, "xp": 1.0, "tex": "e_slider", "ai": "melee", "nerve": 15.0},
	"stone": {"name": "固海凿石者", "hp": 22.0, "spd": 46.0, "dmg": 7.0, "r": 12.0, "xp": 2.0, "tex": "e_stone", "ai": "ranged", "range": 230.0, "cd": 2.4, "entrench": true},
	"offspring": {"name": "伊祖米克的子代", "hp": 70.0, "spd": 28.0, "dmg": 10.0, "r": 15.0, "xp": 4.0, "tex": "e_offspring", "ai": "melee", "morph": true},
	"brood": {"name": "注亡拟嗣", "hp": 16.0, "spd": 0.0, "dmg": 6.0, "r": 9.0, "xp": 0.5, "tex": "e_brood", "ai": "static", "corrode": 0.3, "decay": 0.08},
	"fractal": {"name": "塑路者碎片", "hp": 18.0, "spd": 95.0, "dmg": 6.0, "r": 8.0, "xp": 1.0, "tex": "e_fractal", "ai": "melee"},
	"tear": {"name": "伊莎玛拉之泪", "hp": 60.0, "spd": 0.0, "dmg": 0.0, "r": 14.0, "xp": 2.0, "tex": "e_tear", "ai": "static", "tear": true},
	# ---- 精英
	"pocket": {"name": "囊海爬行者", "hp": 32.0, "spd": 48.0, "dmg": 12.0, "r": 18.0, "xp": 2.0, "tex": "e_pocket", "ai": "melee", "role": "elite", "burst": true},
	"skimmer": {"name": "掠海漂移体", "hp": 26.0, "spd": 62.0, "dmg": 9.0, "r": 16.0, "xp": 2.0, "tex": "e_skimmer", "ai": "ranged", "range": 200.0, "cd": 1.8, "role": "elite", "corrode": 0.5, "hover": true},
	"mother": {"name": "投嗣育母", "hp": 30.0, "spd": 40.0, "dmg": 8.0, "r": 18.0, "xp": 2.0, "tex": "e_mother", "ai": "ranged", "range": 260.0, "cd": 2.2, "role": "elite", "brood": true},
	"mimic": {"name": "箱形恐鱼", "hp": 45.0, "spd": 88.0, "dmg": 14.0, "r": 16.0, "xp": 3.0, "tex": "e_mimic", "ai": "melee", "role": "elite", "ingots": 10},
	# ---- Boss
	"path": {"name": "塑路者", "hp": 2600.0, "spd": 58.0, "dmg": 20.0, "r": 34.0, "xp": 60.0, "tex": "e_path", "ai": "melee", "role": "boss"},
	"izumik": {"name": "伊祖米克，生态泉源", "hp": 5200.0, "spd": 30.0, "dmg": 16.0, "r": 40.0, "xp": 90.0, "tex": "e_izumik", "ai": "ranged", "range": 320.0, "cd": 1.6, "role": "boss"},
	"iberia": {"name": "圣徒伊比利亚", "hp": 2800.0, "spd": 58.0, "dmg": 18.0, "r": 22.0, "xp": 60.0, "tex": "e_iberia", "ai": "ranged", "range": 280.0, "cd": 1.5, "role": "boss", "ammo": 3},
	"carmen": {"name": "圣徒卡门", "hp": 2400.0, "spd": 50.0, "dmg": 16.0, "r": 22.0, "xp": 60.0, "tex": "e_carmen", "ai": "ranged", "range": 380.0, "cd": 1.2, "role": "boss", "ammo": 3},
	"bishop": {"name": "接潮主教", "hp": 2000.0, "spd": 36.0, "dmg": 14.0, "r": 22.0, "xp": 50.0, "tex": "e_bishop", "ai": "ranged", "range": 300.0, "cd": 1.8, "role": "boss", "pair": true},
	"archon": {"name": "接潮蔑死体", "hp": 2200.0, "spd": 56.0, "dmg": 18.0, "r": 24.0, "xp": 50.0, "tex": "e_archon", "ai": "melee", "role": "boss", "corrode": 0.5, "pair": true},
	"immortal": {"name": "接潮斥亡体", "hp": 1500.0, "spd": 82.0, "dmg": 13.0, "r": 20.0, "xp": 50.0, "tex": "e_immortal", "ai": "melee", "role": "boss", "corrode": 0.5, "pair": true},
	"paranoia": {"name": "\"偏执泡影\"", "hp": 7000.0, "spd": 34.0, "dmg": 15.0, "r": 40.0, "xp": 0.0, "tex": "e_paranoia", "ai": "ranged", "range": 320.0, "cd": 1.5, "role": "boss", "corrode": 0.5, "hover": true},
	"ishar": {"name": "伊莎玛拉，腐化之心", "hp": 9000.0, "spd": 34.0, "dmg": 18.0, "r": 46.0, "xp": 0.0, "tex": "e_ishar", "ai": "ranged", "range": 340.0, "cd": 1.5, "role": "boss"},
}
## Boss 结构：3:30 与 7:00 从第三层 Boss 池各抽一个（不重复），10:00 按结局出现最终 Boss
const BOSS_TIMES := [210.0, 420.0, 600.0]
const MID_POOL := [["path"], ["iberia"], ["carmen"], ["bishop", "archon"], ["bishop", "immortal"]]
const ENDINGS := {
	"standard": {"name": "结局一", "en": "PRECIOUS DAYS", "boss": "paranoia"},
}

## 技能：致敬原作的三个技能，全部自动释放
const SKILLS = {
	"s1": {"name": "唤醒", "desc": "每挥伞 7 次充能 1 层（最多 3 层），下一次挥砍造成 300% 伤害，触手追击伤害 ×3"},
	"s2": {"name": "囚徒困境", "desc": "技力充满后自动开启 21 秒：挥伞频率翻倍、伤害 +30%，触手目标 +1 并束缚 1.3 秒"},
	"s3": {"name": "镜花水月", "desc": "技力充满后自动开启 30 秒：挥砍范围扩大、伤害 +150%，触手目标 +2 并晕眩；命中少于 3 个敌人时损失生命"},
}

## 精英化二时三选一的模组
const MODULES = {
	"x": {"name": "X 模组「分裂创伤」", "desc": "天赋「创伤性癔症」的触手追击目标 +1"},
	"y": {"name": "Y 模组「嗜血回响」", "desc": "「反移情」伤害加成提升至 +35%，击杀回复翻倍"},
	"a": {"name": "α 模组「深渊拖拽」", "desc": "触手会把目标拖向水月；技能生效期间追击目标再 +2"},
}

## 升级时的成长项（水月自身），max 为可选次数上限
const GROWTH = {
	"u_dmg": {"name": "伞击·锋", "desc": "伞击伤害 +15%", "max": 5},
	"u_area": {"name": "伞击·展", "desc": "伞击半径 +10%，挥砍角度 +15°", "max": 5},
	"u_spd": {"name": "伞击·迅", "desc": "挥伞间隔 -8%", "max": 5},
	"t_dmg": {"name": "触手·蚀", "desc": "触手追击伤害倍率 +20%", "max": 5},
	"sp": {"name": "技力", "desc": "技力回复速度 +15%，唤醒所需挥伞次数 -1", "max": 3},
	"dodge": {"name": "水影", "desc": "闪避率 +5%", "max": 4},
	"hp": {"name": "坚韧", "desc": "最大生命 +20", "max": 99},
	"speed": {"name": "轻盈", "desc": "移动速度 +10%", "max": 5},
	"pickup": {"name": "感知", "desc": "拾取范围 +30%", "max": 5},
	"regen": {"name": "自愈", "desc": "每秒回复生命 +0.6", "max": 5},
	"armor": {"name": "硬化", "desc": "受到伤害 -1", "max": 5},
	"wick": {"name": "护灯", "desc": "灯火消耗速度 -15%", "max": 4},
}

## 援护干员：原创的通用职业干员（远程支援），最多 3 名，每名最高 Lv.3
const ALLIES = {
	"sniper": {"name": "狙击干员", "en": "SNIPER", "desc": "远程单体射击，优先攻击精英和生命最高的敌人", "up": "伤害 +50%，射速 +15%"},
	"caster": {"name": "术师干员", "en": "CASTER", "desc": "发射法术弹，命中后小范围爆炸", "up": "伤害 +50%，爆炸范围扩大"},
	"medic": {"name": "医疗干员", "en": "MEDIC", "desc": "每 3 秒为水月回复 3% 最大生命", "up": "治疗量与频率提升"},
	"support": {"name": "辅助干员", "en": "SUPPORTER", "desc": "水月周围的敌人移动速度 -35%，并持续受到少量伤害", "up": "范围扩大，伤害提升"},
}
const RECRUIT_LEVELS := [5, 15, 25]

const RELICS = {
	# 灯火类
	"wick_shield": {"name": "灯芯护罩", "cat": "灯火", "desc": "灯火消耗速度 -25%"},
	"oil_jar": {"name": "灯油壶", "cat": "灯火", "desc": "立即点满灯火，灯油效果 +50%"},
	"backlight": {"name": "逆光之瞳", "cat": "灯火", "desc": "灯火低于 30 时，伤害 +30%"},
	"ember": {"name": "余烬", "cat": "灯火", "desc": "击败精英时灯火 +20"},
	# 战斗类
	"umbrella_rib": {"name": "破碎的伞骨", "cat": "战斗", "desc": "伞击挥砍角度 +40°"},
	"deep_limb": {"name": "深渊残肢", "cat": "战斗", "desc": "触手追击目标 +1"},
	"watch": {"name": "潮汐怀表", "cat": "战斗", "desc": "技力回复速度 +25%"},
	"scale": {"name": "锋利鳞片", "cat": "战斗", "desc": "所有伤害 +15%"},
	"jelly_spec": {"name": "发光水母标本", "cat": "战斗", "desc": "两只发光水母环绕水月，触碰敌人造成伤害"},
	"conch": {"name": "涨潮螺壳", "cat": "战斗", "desc": "每 3 秒向四周释放一次潮涌冲击，击退敌人"},
	# 生存类
	"coral": {"name": "深海珊瑚", "cat": "生存", "desc": "最大生命 +30，每秒回复 +0.5"},
	"scarf": {"name": "咸湿的围巾", "cat": "生存", "desc": "受到伤害 -2"},
	"bottle": {"name": "漂流瓶", "cat": "生存", "desc": "拾取范围 +50%，经验 +15%"},
	"cloak": {"name": "水影披风", "cat": "生存", "desc": "闪避率 +10%"},
	# 海嗣类（高风险高收益）
	"symbiote": {"name": "共生囊", "cat": "海嗣", "desc": "海嗣进化得更快，但进化体掉落的经验 ×3"},
	"whisper": {"name": "大群的低语", "cat": "海嗣", "desc": "「大群来袭」规模 +50%，每次大群出现时额外掉落一个藏品箱"},
	"seed": {"name": "吞噬之种", "cat": "海嗣", "desc": "海嗣吞噬同类时，水月回复 5% 最大生命"},
}

const COMBOS = {
	"deep_light": {"name": "深海之光", "req": ["wick_shield", "jelly_spec"], "desc": "水母每次命中恢复少量灯火"},
	"high_tide": {"name": "涨潮", "req": ["conch", "watch"], "desc": "潮涌每 2 秒释放一次，范围与伤害 +30%"},
	"drifter": {"name": "漂流者", "req": ["bottle", "scarf"], "desc": "移动速度 +15%，拾取范围 +30%"},
	"abyss_grip": {"name": "深渊之握", "req": ["umbrella_rib", "deep_limb"], "desc": "伞击命中的每个敌人都有 20% 几率被额外触手追击"},
	"tide_of_flesh": {"name": "血肉之潮", "req": ["symbiote", "seed"], "desc": "击败进化体时回复 3% 最大生命"},
}
