extends RefCounted
## 游戏数据表：水月的成长项、技能、模组、武器、援护、难度。
## 敌人与刷怪导演表已迁到 JSON（data/enemies.json、data/waves.json），这里只做加载，调用方仍用 D.ENEMIES / D.THREAT 等。

const Loader = preload("res://scripts/enemies/enemy_db.gd")
static var ENEMIES: Dictionary = Loader.load_enemies()
static var THREAT: Array = Loader.load_waves().threat
static var BOSS_TIMES: Array = Loader.load_waves().boss_times
static var MID_POOL: Array = Loader.load_waves().mid_pool
static var ENDINGS: Dictionary = Loader.load_waves().endings

## 敌人：名称与机制按「水月与深蓝之树」，数值按本作换算
## ai: melee 近战追击 / ranged 进入射程后停下射击 / static 不移动
## 特殊字段：corrode 侵蚀比例、nerve 每次命中的神经损伤、role elite/boss
## 威胁等级：随时间上升，决定刷怪池、精英间隔（秒）与大群构成；升级时刷出一小波新种类
## Boss 结构：3:30 与 7:00 从第三层 Boss 池各抽一个（不重复），10:00 按结局出现最终 Boss
## 技能：致敬原作的三个技能，全部自动释放；按等级自动解锁，不占用升级三选一
## 设计：S1 改变单次攻击（爆发）/ S2 改变攻击节奏（攻速+束缚）/ S3 改变攻击空间（多方向+形态）
const SKILLS = {
	"s1": {"name": "唤醒", "en": "AWAKENING", "glyph": "唤", "col": Color(1.0, 0.77, 0.42), "mode": "auto", "trigger": "count",
		"desc": "每挥伞数次，下一次攻击自动强化为「唤醒」：伤害大幅提升、范围扩大，触手追击同样强化"},
	"s2": {"name": "囚徒困境", "en": "PRISONER'S DILEMMA", "glyph": "囚", "col": Color(0.45, 0.8, 1.0), "mode": "auto", "trigger": "sp",
		"desc": "周期性进入高速状态：挥伞频率翻倍，触手追击目标 +1 并附带束缚"},
	"s3": {"name": "镜花水月", "en": "MIRAGE", "glyph": "镜", "col": Color(0.8, 0.55, 1.0), "mode": "auto", "trigger": "sp",
		"desc": "周期性进入特殊形态：攻击范围扩大，斩击同时覆盖三个方向并附带短暂晕眩"},
}
## 技能解锁等级（精英化一 / 二分别对应 S2 / S3）
const SKILL_UNLOCK := {"s1": 3, "s2": 10, "s3": 19}
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
		{"name": "镜像", "desc": "镜花水月期间，身后浮现水月的镜像分身，朝它身边的敌人同步挥伞（60% 伤害）", "min_lv": 21},
		{"name": "镜花水月·深海", "desc": "斩击覆盖全方向、触手追击 +2，并在周身展开深海幻境：范围内敌人减速", "min_lv": 24},
	],
}
## 技能参数（均可调；平衡优先削减覆盖率、触发频率与额外攻击系数）
const SKILL_P := {
	"s1_mult": 3.0, "s1_radius": 1.3, "s1_burst_r": 80.0, "s1_burst_mult": 0.6, "s1_burst_max": 3,
	"s1_deep_n": 4, "s1_deep_range": 260.0, "s1_deep_mult": 0.8,
	"s2_charge": 22.0, "s2_dur": 12.0, "s2_interval": 0.5, "s2_bind": 1.0, "s2_twin_mult": 0.7,
	"s2_combo_every": 4, "s2_combo_n": 3, "s2_spread_r": 90.0, "s2_spread_bind": 0.6,
	"s3_charge": 45.0, "s3_dur": 14.0, "s3_radius": 1.45, "s3_mult": 1.8, "s3_stun": 0.6,
	"s3_echo_delay": 0.12, "s3_echo_mult": 0.6, "s3_zone_r": 200.0,
}
## 难度（参照水月肉鸽的难度分级：逐级叠加负面效果；通关当前最高难度后解锁下一级）
const DIFFICULTY := [
	{"name": "标准", "desc": "深海原本的样子"},
	{"name": "暗潮", "desc": "敌人生命 +15%"},
	{"name": "浊流", "desc": "敌人攻击 +15%"},
	{"name": "昏灯", "desc": "受击时灯火损失 +25%，灯油掉落减半"},
	{"name": "猎群", "desc": "精英出现间隔 -25%"},
	{"name": "拮据", "desc": "源石锭掉落 -30%"},
	{"name": "疾影", "desc": "Boss 招式预警时间 -25%"},
	{"name": "潮涌", "desc": "大群规模 +40%，Boss 在场时大群照常来袭"},
	{"name": "永痕", "desc": "溟痕不再消散"},
	{"name": "负伤", "desc": "初始最大生命 -20%"},
	{"name": "深蓝之树", "desc": "敌人生命与攻击再 +20%，Boss 攻击 +25%"},
]

## 武器：只保留支援无人机（与两条进化路线正交的远程补充），最高 Lv.5
## 原「海嗣触须阵」「潮汐弹」已并入进化路线（群触·阵 / 潮刃·回响）
## tags 供 Build Profile 使用：无人机 → 援护副系统
const WEAPONS := {
	"drone": {"tags": ["support", "summon", "ranged"], "name": "支援无人机", "en": "DRONE", "glyph": "机", "col": Color(0.55, 0.95, 1.0), "lv": [
		"无人机跟随水月，向最近的敌人发射子弹",
		"改装激光：周期性发射穿透激光，贯穿一条直线上的所有敌人",
		"加装导弹：在激光之外发射追踪导弹，命中后爆炸",
		"增派第二架无人机",
		"导弹数量 +1，所有攻击频率 +25%",
	]},
}
const MAX_WEAPONS := 1

## 技能进阶卡出现概率（每次升级至多一张）
const SKILL_ADV_CHANCE := 0.45


## 升级时的成长项（水月专属：伞击 / 触手 / 进化路线），max 为可选次数上限
const GROWTH = {
	"u_dmg": {"name": "伞击·锋", "desc": "伞击伤害 +15%", "max": 5},
	"u_area": {"name": "伞击·展", "desc": "伞击半径 +10%，挥砍角度 +15°", "max": 5},
	"u_spd": {"name": "伞击·迅", "desc": "挥伞间隔 -8%", "max": 4},
	"t_dmg": {"name": "触手·蚀", "desc": "触手追击伤害倍率 +20%", "max": 5},
	# 博士 / 全队被动（坚韧 / 自愈 / 硬化 / 水影 / 轻盈 / 感知 / 护灯 / 协同·×）见 characters/doctor.gd PASSIVES
	# ---- 进化路线专属（选定路线后才会出现）
	"b_count": {"name": "潮刃·分", "desc": "每次挥伞多斩出 1 道水刃（扇形展开）", "max": 2, "path": "blade"},
	"b_size": {"name": "潮刃·阔", "desc": "水刃宽度与判定范围 +25%", "max": 3, "path": "blade"},
	"b_dmg": {"name": "潮刃·利", "desc": "水刃伤害 +30%", "max": 3, "path": "blade"},
	"b_range": {"name": "潮刃·远", "desc": "水刃飞行距离 +30%", "max": 2, "path": "blade"},
	"b_pierce": {"name": "潮刃·贯", "desc": "水刃穿透数 2 → 4 名（Lv.2：无限穿透）", "max": 2, "path": "blade"},
	"b_echo": {"name": "潮刃·回响", "desc": "每 2.2 秒射出一枚潮汐弹，在敌人之间反弹（Lv.2：两枚、伤害 +50% 并击退）", "max": 2, "path": "blade", "tags": ["arts", "on_hit", "basic_attack"]},
	"t_count": {"name": "群触·增", "desc": "每次挥伞多召唤 1 根触手", "max": 3, "path": "tendril"},
	"t_stake": {"name": "群触·桩", "desc": "触手桩持续时间 +1 秒", "max": 2, "path": "tendril"},
	"t_power": {"name": "群触·力", "desc": "触手与触手桩伤害 +30%", "max": 3, "path": "tendril"},
	"t_reach": {"name": "群触·长", "desc": "触手桩鞭打范围 +25%", "max": 2, "path": "tendril"},
	"t_field": {"name": "群触·阵", "desc": "每 3.5 秒在敌人最密集处升起触须阵，持续造成伤害（Lv.2：两处并束缚）", "max": 2, "path": "tendril", "tags": ["mizuki_tentacle", "arts", "control"]},
}

## 进化：精英化一选路线，精英化二在路线内再选一次质变（共 4 种最终形态）
const EVO := {
	"blade": {"name": "潮刃", "en": "TIDE BLADE", "glyph": "刃", "col": Color(0.5, 0.9, 1.0),
		"desc": "远斩流：每次挥伞同时斩出一道与伞击同伤害的月牙水刃，穿透 2 名敌人后碎裂溅射并减速（成长可增加穿透）"},
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
	"sniper": {"name": "狙击干员", "en": "SNIPER", "desc": "远程单体射击，优先打精英和生命最高的敌人；命中使其流血", "up": "伤害 +35%，射速 +15%"},
	"caster": {"name": "术师干员", "en": "CASTER", "desc": "发射法术团，命中后爆炸造成范围伤害", "up": "伤害 +35%，爆炸范围扩大"},
	"medic": {"name": "医疗干员", "en": "MEDIC", "desc": "每 3.5 秒为水月回复 3.5% 最大生命", "up": "治疗量与频率提升"},
	"support": {"name": "辅助干员", "en": "SUPPORTER", "desc": "减速光环：身边敌人移速 -35%；并向 2 名敌人发射追踪法术", "up": "光环范围扩大，法术伤害与频率提升；Lv.3 时同时攻击 3 个目标"},
}
const RECRUIT_LEVELS := [5, 15, 25]

