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
	"paranoia": {"name": "\"偏执泡影\"", "hp": 6200.0, "spd": 34.0, "dmg": 15.0, "r": 40.0, "xp": 0.0, "tex": "e_paranoia", "ai": "ranged", "range": 320.0, "cd": 1.5, "role": "boss", "corrode": 0.5, "hover": true},
	"ishar": {"name": "伊莎玛拉，腐化之心", "hp": 9000.0, "spd": 34.0, "dmg": 18.0, "r": 46.0, "xp": 0.0, "tex": "e_ishar", "ai": "ranged", "range": 340.0, "cd": 1.5, "role": "boss"},
}
## Boss 结构：3:30 与 7:00 从第三层 Boss 池各抽一个（不重复），10:00 按结局出现最终 Boss
const BOSS_TIMES := [210.0, 420.0, 600.0]
const MID_POOL := [["path"], ["iberia"], ["carmen"], ["bishop", "archon"], ["bishop", "immortal"]]
const ENDINGS := {
	"standard": {"name": "结局一", "en": "PRECIOUS DAYS", "boss": "paranoia"},
}

## 技能：致敬原作的三个技能，全部自动释放；按等级自动解锁，不占用升级三选一
## 设计：S1 改变单次攻击（爆发）/ S2 改变攻击节奏（攻速+束缚）/ S3 改变攻击空间（多方向+形态）
const SKILLS = {
	"s1": {"name": "唤醒", "en": "AWAKENING", "glyph": "唤", "col": Color(1.0, 0.77, 0.42),
		"desc": "每挥伞数次，下一次攻击自动强化为「唤醒」：伤害大幅提升、范围扩大，触手追击同样强化"},
	"s2": {"name": "囚徒困境", "en": "PRISONER'S DILEMMA", "glyph": "囚", "col": Color(0.45, 0.8, 1.0),
		"desc": "周期性进入高速状态：挥伞频率翻倍，触手追击目标 +1 并附带束缚"},
	"s3": {"name": "镜花水月", "en": "MIRAGE", "glyph": "镜", "col": Color(0.8, 0.55, 1.0),
		"desc": "周期性进入特殊形态：攻击范围扩大，斩击同时覆盖三个方向并附带短暂晕眩"},
}
## 技能解锁等级（精英化一 / 二分别对应 S2 / S3）
const SKILL_UNLOCK := {"s1": 3, "s2": 10, "s3": 20}
## 技能进阶：「基础解锁 + 进阶 I + 进阶 II」，以进阶卡形式少量混入升级选项
const SKILL_ADV := {
	"s1": [
		{"name": "创伤扩散", "desc": "唤醒命中后，在目标处引发一次范围冲击，波及周围敌人", "min_lv": 5},
		{"name": "深层唤醒", "desc": "唤醒命中后，海床下唤出 4 条触手追击附近的敌人（不会连锁）", "min_lv": 9},
	],
	"s2": [
		{"name": "双重困境", "desc": "囚徒困境期间，每次挥伞额外斩向另一方向最近的敌人", "min_lv": 12},
		{"name": "无解困境", "desc": "囚徒困境期间，每第 4 次挥伞插入一轮触手连击；束缚会传播给身边 1 名敌人", "min_lv": 16},
	],
	"s3": [
		{"name": "倒影", "desc": "镜花水月期间，每次挥伞后倒影会在反方向延迟复刻一次攻击", "min_lv": 22},
		{"name": "镜花水月·深海", "desc": "斩击覆盖全方向、触手追击 +2，并在周身展开深海幻境：范围内敌人减速", "min_lv": 26},
	],
}
## 技能参数（均可调；平衡优先削减覆盖率、触发频率与额外攻击系数）
const SKILL_P := {
	"s1_mult": 3.0, "s1_radius": 1.3, "s1_burst_r": 80.0, "s1_burst_mult": 0.6, "s1_burst_max": 3,
	"s1_deep_n": 4, "s1_deep_range": 260.0, "s1_deep_mult": 0.8,
	"s2_charge": 22.0, "s2_dur": 12.0, "s2_interval": 0.5, "s2_bind": 1.0, "s2_twin_mult": 0.7,
	"s2_combo_every": 4, "s2_combo_n": 3, "s2_spread_r": 90.0, "s2_spread_bind": 0.6,
	"s3_charge": 45.0, "s3_dur": 14.0, "s3_radius": 1.45, "s3_mult": 1.8, "s3_stun": 0.6,
	"s3_echo_delay": 0.35, "s3_echo_mult": 0.7, "s3_zone_r": 200.0,
}
## 难度（参照水月肉鸽的难度分级：逐级叠加负面效果；通关当前最高难度后解锁下一级）
const DIFFICULTY := [
	{"name": "标准", "desc": "深海原本的样子"},
	{"name": "暗潮", "desc": "敌人生命 +15%"},
	{"name": "浊流", "desc": "敌人攻击 +15%"},
	{"name": "昏灯", "desc": "灯火消耗速度 +25%"},
	{"name": "猎群", "desc": "精英出现间隔 -25%"},
	{"name": "拮据", "desc": "源石锭掉落 -30%"},
	{"name": "躁动", "desc": "敌人移动速度 +10%"},
	{"name": "潮涌", "desc": "大群规模 +40%"},
	{"name": "巨影", "desc": "Boss 生命 +30%"},
	{"name": "负伤", "desc": "初始最大生命 -20%"},
	{"name": "深蓝之树", "desc": "敌人生命与攻击再 +20%，Boss 攻击 +25%"},
]

## 武器：升级时以卡片形式出现，最多同时持有 3 种，每种最高 Lv.5
## tags 供 Build Profile 使用：无人机 → 援护副系统，触须阵 → 触手 / 控制流，潮汐弹 → 伞击 / 连锁清怪流
const WEAPONS := {
	"drone": {"tags": ["support", "summon", "ranged"], "name": "支援无人机", "en": "DRONE", "glyph": "机", "col": Color(0.55, 0.95, 1.0), "lv": [
		"无人机跟随水月，向最近的敌人发射子弹",
		"改装激光：周期性发射穿透激光，贯穿一条直线上的所有敌人",
		"加装导弹：在激光之外发射追踪导弹，命中后爆炸",
		"增派第二架无人机",
		"导弹数量 +1，所有攻击频率 +25%",
	]},
	"field": {"tags": ["mizuki_tentacle", "arts", "control"], "name": "海嗣触须阵", "en": "TENTACLE FIELD", "glyph": "阵", "col": Color(0.75, 0.5, 1.0), "lv": [
		"每 3.5 秒在敌人最密集处升起触须阵，持续造成伤害",
		"触须阵范围 +30%",
		"触须阵会束缚其中的敌人",
		"同时升起 2 处触须阵",
		"触须阵伤害 +60%，持续时间延长",
	]},
	"tide": {"tags": ["arts", "on_hit", "basic_attack"], "name": "潮汐弹", "en": "TIDE SHOT", "glyph": "潮", "col": Color(0.4, 0.75, 1.0), "lv": [
		"每 2.2 秒射出一枚水弹，命中后在敌人之间反弹 3 次",
		"反弹次数 +2",
		"同时射出 2 枚",
		"水弹伤害 +50%，击退敌人",
		"反弹次数 +3，发射间隔 -30%",
	]},
}
const MAX_WEAPONS := 3

## 技能进阶卡出现概率（每次升级至多一张）
const SKILL_ADV_CHANCE := 0.45

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
	# ---- 进化路线专属（选定路线后才会出现）
	"b_count": {"name": "潮刃·分", "desc": "每次挥伞多斩出 1 道水刃（扇形展开）", "max": 2, "path": "blade"},
	"b_size": {"name": "潮刃·阔", "desc": "水刃宽度与判定范围 +25%", "max": 3, "path": "blade"},
	"b_dmg": {"name": "潮刃·利", "desc": "水刃伤害 +30%", "max": 3, "path": "blade"},
	"b_range": {"name": "潮刃·远", "desc": "水刃飞行距离 +30%", "max": 2, "path": "blade"},
	"t_count": {"name": "群触·增", "desc": "每次挥伞多召唤 1 根触手", "max": 3, "path": "tendril"},
	"t_stake": {"name": "群触·桩", "desc": "触手桩持续时间 +1 秒", "max": 2, "path": "tendril"},
	"t_power": {"name": "群触·力", "desc": "触手与触手桩伤害 +30%", "max": 3, "path": "tendril"},
	"t_reach": {"name": "群触·长", "desc": "触手桩鞭打范围 +25%", "max": 2, "path": "tendril"},
}

## 进化：精英化一选路线，精英化二在路线内再选一次质变（共 4 种最终形态）
const EVO := {
	"blade": {"name": "潮刃", "en": "TIDE BLADE", "glyph": "刃", "col": Color(0.5, 0.9, 1.0),
		"desc": "远斩流：每次挥伞同时斩出一道穿透的月牙水刃，贯穿直线上的所有敌人并使其减速"},
	"tendril": {"name": "群触", "en": "TENDRIL SWARM", "glyph": "触", "col": Color(0.78, 0.5, 1.0),
		"desc": "召唤流：每次挥伞额外召唤触手，触手化为「触手桩」留在原地，持续鞭打周围敌人"},
	"blade_moon": {"name": "月轮", "en": "CRESCENT MOON", "glyph": "月", "col": Color(0.6, 0.95, 1.0), "path": "blade",
		"desc": "水刃化为月轮：飞出后折返，去程与回程各命中一次；水刃数 +1"},
	"blade_abyss": {"name": "深渊巨斩", "en": "ABYSSAL CLEAVE", "glyph": "渊", "col": Color(0.55, 0.7, 1.0), "path": "blade",
		"desc": "每第 4 次挥伞斩出 3 倍大小、3 倍伤害的巨型月牙并晕眩敌人；普通水刃范围 +30%"},
	"tendril_mother": {"name": "深海之母", "en": "ABYSSAL MOTHER", "glyph": "母", "col": Color(0.85, 0.45, 1.0), "path": "tendril",
		"desc": "每次挥伞再多召唤 2 根触手；被触手击杀的敌人会在附近唤出新的触手"},
	"tendril_giant": {"name": "巨触吞噬", "en": "DEVOURING KRAKEN", "glyph": "吞", "col": Color(0.7, 0.35, 0.95), "path": "tendril",
		"desc": "每 5 秒在敌群中心升起巨型触手：范围重击、把敌人拖向中心并晕眩；普通触手 +1"},
}

## 援护干员：原创的通用职业干员（远程支援），最多 3 名，每名最高 Lv.3
const ALLIES = {
	"sniper": {"name": "狙击干员", "en": "SNIPER", "desc": "远程单体射击，优先攻击精英和生命最高的敌人；命中使敌人流血", "up": "伤害 +50%，射速 +15%"},
	"caster": {"name": "术师干员", "en": "CASTER", "desc": "发射火球，命中后爆炸造成范围伤害", "up": "伤害 +50%，爆炸范围扩大"},
	"medic": {"name": "医疗干员", "en": "MEDIC", "desc": "每 2.4 秒为水月回复 5% 最大生命", "up": "治疗量与频率提升"},
	"support": {"name": "辅助干员", "en": "SUPPORTER", "desc": "减速光环：水月身边的敌人移动速度 -35%；并向 2 名敌人发射追踪的紫色法术", "up": "光环范围扩大，法术伤害与频率提升；Lv.3 时同时攻击 3 个目标"},
}
const RECRUIT_LEVELS := [5, 15, 25]

const RELICS = {
	# 护盾类（名称取自水月肉鸽藏品；除「药枚」外需先拥有药枚）
	"sh_base": {"name": "药枚", "cat": "生存", "desc": "每 12 秒生成一层淡蓝护盾，抵挡一次伤害"},
	"sh_count": {"name": "御2", "cat": "生存", "desc": "护盾层数上限 +1", "need": "sh_base"},
	"sh_fast": {"name": "《杜林地上环游记》", "cat": "生存", "desc": "护盾生成间隔 -30%", "need": "sh_base"},
	"sh_burst": {"name": "皇族金胸针", "cat": "生存", "desc": "护盾破裂时释放冲击，伤害并击退周围敌人", "need": "sh_base"},
	"sh_plate": {"name": "嵌体甲片", "cat": "生存", "desc": "最大生命 -10，护盾层数上限 +2", "need": "sh_base"},
	"sh_ring": {"name": "“国王的护戒”", "cat": "生存", "desc": "护盾抵挡伤害时回复 3% 最大生命", "need": "sh_base"},
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
