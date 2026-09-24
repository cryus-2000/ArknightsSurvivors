extends RefCounted
## 属性表：所有可被修正的数值都在这里登记（Data Driven）。
## old = game.gd v0.8 里对应的旧变量，接入时逐个替换（见 docs/09_p0_architecture.md）。
## 公共属性给所有干员用；角色专属属性（如 mizuki_*）由 characters/<id>.gd 的 stat_defs() 提供，用自己的前缀。

const PLAYER := {
	# ---- 公共：生存与移动
	&"max_hp": {"base": 100.0, "min": 1.0, "old": "max_hp", "name": "最大生命"},
	&"regen": {"base": 0.0, "old": "regen", "name": "每秒回复"},
	&"armor": {"base": 0.0, "min": 0.0, "old": "armor", "name": "受到伤害 -N（固定）"},
	&"dmg_taken": {"base": 1.0, "min": 0.1, "name": "受到伤害倍率"},
	&"dodge": {"base": 0.25, "min": 0.0, "max": 0.75, "old": "dodge", "name": "闪避率"},
	&"dodge_phys": {"base": 0.0, "min": 0.0, "old": "dodge_phys", "name": "物理闪避（额外）"},
	&"dodge_arts": {"base": 0.0, "min": 0.0, "old": "dodge_arts", "name": "法术闪避（额外）"},
	&"regen_pct": {"base": 0.0, "min": 0.0, "old": "regen_pct", "name": "每秒回复最大生命百分比"},
	&"arts_res": {"base": 0.0, "min": 0.0, "max": 0.7, "old": "arts_res", "name": "法术抗性"},
	&"move_speed": {"base": 150.0, "min": 40.0, "old": "speed", "name": "移动速度"},
	&"pickup": {"base": 70.0, "old": "pickup", "name": "拾取范围"},
	&"heal_mult": {"base": 1.0, "min": 0.0, "name": "回复效果倍率"},
	&"shield_max": {"base": 0.0, "min": 0.0, "old": "shield_max", "name": "护盾层数上限"},
	&"shield_interval": {"base": 12.0, "min": 2.0, "old": "shield_every", "name": "护盾生成间隔"},
	# ---- 公共：输出
	&"dmg": {"base": 1.0, "min": 0.0, "old": "dmg_mult", "name": "全伤害倍率"},
	&"physical_dmg": {"base": 1.0, "min": 0.0, "name": "物理伤害倍率"},
	&"arts_dmg": {"base": 1.0, "min": 0.0, "name": "法术伤害倍率"},
	&"boss_dmg": {"base": 1.0, "min": 0.0, "name": "对 Boss 伤害倍率"},
	&"melee_dmg": {"base": 1.0, "min": 0.0, "old": "melee_mult", "name": "近战伤害倍率"},
	&"ranged_dmg": {"base": 1.0, "min": 0.0, "old": "ranged_mult", "name": "远程伤害倍率"},
	&"weak_bonus": {"base": 0.0, "min": 0.0, "old": "weak_bonus", "name": "弱点伤害额外加成"},
	&"sp_gain": {"base": 1.0, "min": 0.0, "old": "sp_mult", "name": "技力回复倍率"},
	&"control_dur": {"base": 1.0, "min": 0.0, "name": "控制持续时间倍率"},
	# ---- 公共：资源
	&"light_decay": {"base": 1.0, "min": 0.0, "old": "lamp_decay", "name": "受击灯火损失倍率"},
	&"light_loss": {"base": 1.0, "min": 0.0, "name": "受击 / 黑潮灯火流失倍率"},
	&"oil_gain": {"base": 1.0, "old": "oil_mult", "name": "灯油效果倍率"},
	&"xp_gain": {"base": 1.0, "old": "xp_mult", "name": "经验倍率"},
	&"shop_price": {"base": 1.0, "min": 0.1, "name": "商店价格倍率"},
	# ---- 干员层（docs/23 §5）：每个干员按 value_for(stat, ["class:<职业>", "op:<id>"]) 读取；全局修正对全队生效
	&"op_atk": {"base": 1.0, "min": 0.0, "name": "干员攻击倍率"},
	&"op_aspd": {"base": 1.0, "min": 0.2, "name": "干员攻速倍率"},
	&"op_range": {"base": 1.0, "min": 0.3, "name": "干员射程 / 范围倍率"},
	&"op_skill_sp": {"base": 1.0, "min": 0.1, "name": "干员技能充能倍率"},
	&"op_skill_power": {"base": 1.0, "min": 0.0, "name": "干员技能强度倍率"},
	# ---- 兼容：旧援护系统的键（藏品数据仍引用；现在等价于全队干员修正）
	&"ally_cap": {"base": 3.0, "min": 0.0, "max": 5.0, "name": "编队上限（旧键）"},
	&"ally_dmg": {"base": 1.0, "min": 0.0, "name": "干员伤害倍率（旧键，全队）"},
	&"ally_rate": {"base": 1.0, "min": 0.1, "name": "干员攻速倍率（旧键，全队）"},
}

## 水月专属（由 characters/mizuki.gd 的 stat_defs() 返回；新干员写自己的一份，不放这里）
const MIZUKI := {
	&"mizuki_umbrella_dmg": {"base": 1.0, "old": "u_dmg_mult", "name": "伞击伤害倍率"},
	&"mizuki_umbrella_area": {"base": 1.0, "old": "u_area_mult", "name": "伞击范围倍率"},
	&"mizuki_umbrella_interval": {"base": 1.0, "min": 0.2, "old": "u_spd_mult", "name": "挥伞间隔倍率（越小越快）"},
	&"mizuki_umbrella_arc": {"base": 0.0, "old": "rib_bonus", "name": "挥砍角度加成（度）"},
	&"mizuki_tentacle_mult": {"base": 0.6, "old": "t_mult", "name": "触手追击伤害系数"},
	&"mizuki_tentacle_targets": {"base": 1.0, "min": 1.0, "old": "extra_targets(+1)", "name": "触手追击目标数"},
	&"mizuki_s1_swings": {"base": 7.0, "min": 5.0, "old": "s1_need", "name": "唤醒所需挥伞次数"},
}

## 敌人全局修正（难度、遭诅古物、削弱类藏品）
const ENEMY := {
	&"enemy_hp": {"base": 1.0, "min": 0.1, "name": "敌人生命倍率"},
	&"enemy_dmg": {"base": 1.0, "min": 0.0, "name": "敌人伤害倍率"},
	&"enemy_speed": {"base": 1.0, "min": 0.1, "name": "敌人移速倍率"},
	&"enemy_atk_speed": {"base": 1.0, "min": 0.1, "name": "敌人攻速倍率"},
	&"enemy_dmg_taken": {"base": 1.0, "min": 0.0, "name": "敌人受到伤害倍率"},
	&"enemy_low_hp_dmg_taken": {"base": 1.0, "min": 0.0, "name": "低血（<50%）敌人受到伤害倍率"},
}
