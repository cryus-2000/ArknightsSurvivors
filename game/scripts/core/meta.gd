extends RefCounted
## 认知塑造（局外成长 P2，docs/109 §4 / §14 v5）：节点数据在 data/meta_tree.json，玩家已点的在 Cfg.meta_shape（{节点 id: true}）。
## 质变 / 非数值节点走 effects 里的 rule（开局写进 rfx.rules），各自的钩子：combat.gd（护盾反震 / 低血回复 / 处决 / 静守）、game.gd（濒死免死）、pickups.gd（升级再升）、progression.gd（开局四选一）、shop.gd（免费刷新）。
## 一局开局时 apply_run(g) 把已点节点写进属性块（来源 "meta"）与开局资源。
## 测试局缺省不带任何局外成长（与改动前逐局相同）；--meta=<生机细胞数> 按推荐点法点到这个数，--meta=full 点满（机器人校准用，docs/109 §5.4）。
## --metanodes=<id,id,…> 只点指定节点（按线单测）。--meta / --metanodes 只在测试局读；正式游玩用存档里的 Cfg.meta_shape。

const PATH := "res://data/meta_tree.json"
static var _data := {}


## 「队长攻击」（护盾反震等质变节点的基数）：队长 JSON base.atk；没有这一项的干员（水月伞击 / 凯尔希 / 流明）用 balance meta/leader_atk_fallback
static func leader_atk(g) -> float:
	var Bal = load("res://scripts/core/balance.gd")
	if g.ch == null:
		return Bal.v("meta/leader_atk_fallback", 15.0)
	var a: float = g.ch.base("atk", g.ch.base("umbrella_dmg", 0.0))
	if a <= 0.0:
		a = Bal.v("meta/leader_atk_fallback", 15.0)
	return a * g.ch._dmg_bonus()


static func data() -> Dictionary:
	if _data.is_empty():
		var j = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		_data = j if j is Dictionary else {"nodes": {}, "order": []}
	return _data


static func nodes() -> Dictionary:
	return data().get("nodes", {})


static func total_cost() -> int:
	var n := 0
	for k in nodes():
		n += int(nodes()[k].cost)
	return n


static func spent(shape: Dictionary) -> int:
	var n := 0
	for k in shape:
		if shape[k] and nodes().has(k):
			n += int(nodes()[k].cost)
	return n


## 能不能点：未点、前置已点、大节点的总量门槛已到、余额够
static func can_buy(shape: Dictionary, id: String, budget: int) -> bool:
	if not nodes().has(id) or shape.get(id, false):
		return false
	var nd: Dictionary = nodes()[id]
	if nd.has("req") and not shape.get(str(nd.req), false):
		return false
	var sp := spent(shape)
	if sp < int(nd.get("need", 0)):
		return false
	return sp + int(nd.cost) <= budget


## 推荐点法：按 order 依次点，点不了（前置 / 门槛 / 余额）先跳过，反复到不再变化
static func shape_for(budget: int) -> Dictionary:
	var shape := {}
	var changed := true
	while changed:
		changed = false
		for id in data().get("order", []):
			if can_buy(shape, str(id), budget):
				shape[str(id)] = true
				changed = true
	return shape


## 本局用哪一份局外成长：测试局只认 --meta=；正式游玩用存档
static func run_shape() -> Dictionary:
	var test := false
	for a in Cfg.dev_args():
		if a.begins_with("--meta="):
			var v := a.substr(7)
			return shape_for(total_cost() if v == "full" else int(v))
		if a.begins_with("--metanodes="):
			# 只点指定节点（逗号分隔 id，不看前置与余额；按线单测用，docs/109 §5.4 S1b）
			var sh := {}
			for id in a.substr(12).split(",", false):
				if nodes().has(id):
					sh[id] = true
			return sh
		if a.begins_with("--"):
			test = true
	return {} if test else Cfg.meta_shape


# ---------------------------------------------------------------- 生机细胞（docs/109 §3.1 v3）
## 探索评分：存活每分钟 10（10:00 封顶 100）+ 中期 Boss 每个 20 + 通关 60，× 潮位系数（每级 +0.05，10 级起封顶 ×1.5）；
## 结局首达 +40（不乘系数）。生机细胞 = 评分 ÷ 6（10-24 起，原 ÷ 8，用户要成长更快）；首通某一潮位另给 5 + 潮位。

## 本局潮位（g.tier，0–15）
static func tide_of(g) -> int:
	return clampi(int(g.tier), 0, 15)


static func tide_factor(tide: int) -> float:
	return minf(1.5, 1.0 + 0.05 * tide)


## 结算用：{score, factor, cells, bounty, ending}
static func run_reward(g, won: bool) -> Dictionary:
	var tide := tide_of(g)
	var mid := 0
	for b in g.bosses:
		if b.dead and not is_same(b, g.final_boss):
			mid += 1
	var base := mini(100, int(g.t / 60.0 * 10.0)) + 20 * mini(mid, 2) + (60 if won else 0)
	var f := tide_factor(tide)
	var score := int(round(base * f)) + (40 if won and g.ending_new else 0)
	var bounty := (5 + tide) if won and not Cfg.meta_bounty.has(tide) else 0
	return {"base": base, "factor": f, "score": score, "cells": score / 6 + bounty, "bounty": bounty, "tide": tide}


static func earned_total() -> int:
	var n := 0
	for k in Cfg.meta_earned:
		n += int(Cfg.meta_earned[k])
	return n


## 兑换寻访凭证花掉的细胞总数（各设备之和，云存档逐设备取大）
static func bought_total() -> int:
	var n := 0
	for k in Cfg.meta_bought:
		n += int(Cfg.meta_bought[k])
	return n


## 认知塑造可用的预算 = 累计获得 − 兑换凭证花掉的
static func budget() -> int:
	return earned_total() - bought_total()


static func available() -> int:
	return budget() - spent(Cfg.meta_shape)


static func dev_id() -> String:
	if Cfg.meta_dev == "":
		var rr := RandomNumberGenerator.new()
		rr.randomize()
		Cfg.meta_dev = "d%08x" % rr.randi()
	return Cfg.meta_dev


## 花 n 个细胞（兑换用）：余额不够返回 false，记在本机设备号下
static func pay(n: int) -> bool:
	if n <= 0 or available() < n:
		return false
	var dev := dev_id()
	Cfg.meta_bought[dev] = int(Cfg.meta_bought.get(dev, 0)) + n
	return true


## 一次探索结束（game.gd _process 进入 WIN / DEAD 时，与寻访同一处）：记生机细胞。条件同 Roster.on_run_end
static func on_run_end(g, won: bool) -> void:
	var Roster = load("res://scripts/core/roster.gd")
	if not Roster.active() or g.mode != g.Mode.PLAY or g.trial.active or g.demo_op != "" or Cfg.practice_active:
		return
	var r := run_reward(g, won)
	if Cfg.meta_dev == "":
		var rr := RandomNumberGenerator.new()
		rr.randomize()
		Cfg.meta_dev = "d%08x" % rr.randi()
	Cfg.meta_earned[Cfg.meta_dev] = int(Cfg.meta_earned.get(Cfg.meta_dev, 0)) + int(r.cells)
	if int(r.bounty) > 0:
		Cfg.meta_bounty.append(int(r.tide))
	g.meta_result = r
	Cfg.save()


## 点 / 重置（认知塑造页）
static func buy(id: String) -> bool:
	if not can_buy(Cfg.meta_shape, id, budget()):
		return false
	Cfg.meta_shape[id] = true
	Cfg.meta_shape_t = int(Time.get_unix_time_from_system())
	Cfg.save()
	return true


static func reset() -> void:
	Cfg.meta_shape = {}
	Cfg.meta_shape_t = int(Time.get_unix_time_from_system())
	Cfg.save()


## 推荐：从当前已点出发，按推荐顺序把余额点完
static func buy_recommended() -> void:
	var changed := true
	while changed:
		changed = false
		for id in data().get("order", []):
			if can_buy(Cfg.meta_shape, str(id), budget()):
				Cfg.meta_shape[str(id)] = true
				changed = true
	Cfg.meta_shape_t = int(Time.get_unix_time_from_system())
	Cfg.save()


## 开局：属性写进 stats（来源 meta），开局资源与一次性规则写进 g / rfx。返回本局点了多少生机细胞（记进作战记录 / BALANCE）
static func apply_run(g) -> int:
	var shape := run_shape()
	g.meta_cells = spent(shape)
	var scale: float = load("res://scripts/core/balance.gd").v("meta/stat_scale", 1.0)   # 局外成长数值总旋钮（云端校准用，缺省 1）
	if shape.is_empty() or g.demo_op != "":
		return 0
	for id in shape:
		if not shape[id] or not nodes().has(id):
			continue
		for ef in nodes()[id].get("effects", []):
			if ef.has("stat"):
				g.stats.add(StringName(ef.stat), str(ef.get("op", "add")), float(ef.value) * scale, "meta")
			elif ef.has("rule"):
				g.rfx.rules[ef.rule] = int(g.rfx.rules.get(ef.rule, 0)) + int(ef.get("value", 1))
			elif ef.has("start_ingots"):
				g.ingots += int(ef.start_ingots)
			elif ef.has("once_heal"):
				g.meta_once_heal = [float(ef.at), float(ef.once_heal)]
			elif ef.has("start_relic"):
				g.meta_start_relic = int(ef.start_relic)
	g.sync_stats()
	return g.meta_cells
