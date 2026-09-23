extends RefCounted
## 游戏数据表：敌人、水月的成长项、技能、模组、藏品、组合

const ENEMIES = {
	"drifter": {"name": "游荡海嗣", "hp": 7.0, "spd": 62.0, "dmg": 6.0, "r": 10.0, "xp": 1.0, "tex": "drifter"},
	"dart": {"name": "疾游海嗣", "hp": 8.0, "spd": 115.0, "dmg": 6.0, "r": 9.0, "xp": 1.0, "tex": "dart"},
	"crawler": {"name": "爬行海嗣", "hp": 20.0, "spd": 50.0, "dmg": 10.0, "r": 13.0, "xp": 2.0, "tex": "crawler"},
	"shell": {"name": "甲壳海嗣", "hp": 55.0, "spd": 38.0, "dmg": 14.0, "r": 17.0, "xp": 4.0, "tex": "shell"},
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
