extends RefCounted
## 战斗事件名（框架第 28 节）。藏品、技能、统计都通过监听这些事件工作。
## 每个事件附带一个 Dictionary 负载，字段约定写在各常量后面；监听者可以修改负载里标明「可改」的字段。

## 水月 / 干员开始一次攻击 { src: 伤害来源, tags: Array }
const ATTACK_STARTED := &"AttackStarted"
## 攻击命中一个敌人（结算伤害前）{ src, target, amount(可改), tags, crit }
const HIT := &"Hit"
## 敌人实际受到伤害后 { src, target, amount, tags, overkill }
const DAMAGE_DEALT := &"DamageDealt"
## 水月即将受到伤害 { amount(可改), source_enemy, tags, blocked(可改) }
const DAMAGE_TAKEN := &"DamageTaken"
## 敌人被击杀 { src, target, tags, elite, boss }
const ENEMY_KILLED := &"EnemyKilled"
## 技能开始 / 结束 { skill: "s1"/"s2"/"s3", branch }
const SKILL_STARTED := &"SkillStarted"
const SKILL_ENDED := &"SkillEnded"
## 状态施加到敌人或水月 { status: "stun"/"bind"/"slow"/"corrode"/"nerve", target, duration(可改), src }
const STATUS_APPLIED := &"StatusApplied"
## 水月闪避了一次攻击 { source_enemy }
const DODGE := &"Dodge"
## 灯火变化 { before, after, reason }
const LIGHT_CHANGED := &"LightChanged"
## 援护干员出手 { kind, lv, target }
const SUPPORT_ATTACKED := &"SupportAttacked"
## Boss 被击败 { target, index }
const BOSS_KILLED := &"BossKilled"
## 额外的通用事件
const LEVEL_UP := &"LevelUp"            # { level }
const RELIC_GAINED := &"RelicGained"    # { id }
const HEALED := &"Healed"               # { amount, src }
const SHIELD_BROKEN := &"ShieldBroken"  # { layers_left }
const TICK := &"Tick"                   # { dt } 每帧一次，给计时类效果用

const ALL := [ATTACK_STARTED, HIT, DAMAGE_DEALT, DAMAGE_TAKEN, ENEMY_KILLED, SKILL_STARTED, SKILL_ENDED,
	STATUS_APPLIED, DODGE, LIGHT_CHANGED, SUPPORT_ATTACKED, BOSS_KILLED, LEVEL_UP, RELIC_GAINED, HEALED, SHIELD_BROKEN, TICK]
