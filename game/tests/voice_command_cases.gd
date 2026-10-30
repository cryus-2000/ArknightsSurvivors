extends RefCounted

const Squad = preload("res://scripts/characters/squad.gd")
const Character = preload("res://scripts/characters/character.gd")

class VoiceSpy extends Node:
	var calls: Array = []
	var urgents: Array = []
	func voice(cid: String, key: String, queued := false, urgent := false) -> void:
		calls.append([cid, key, queued])
		urgents.append(urgent)   # 指挥回应一律 urgent（10-23）
	var delays: Array = []
	func voice_chorus(cid: String, key: String, delay := 0.0, _duck := -3.0) -> void:
		calls.append([cid, key, false])   # 指挥合唱（10-28）：同 urgent 指挥回应，另记错开秒数
		urgents.append(true)
		delays.append(delay)
	func has_voice(_cid: String, _key: String) -> bool:
		return true

class VoiceGame extends RefCounted:
	var sfx: Node
	var panel_ui = null
	var t := 100.0
	var demo_op := ""
	var trace_every := 0.0
	var ppos := Vector2.ZERO
	var in_tree := true
	var entry_voice_hold := false
	var rng := RandomNumberGenerator.new()
	var vrng := RandomNumberGenerator.new()
	var stats = preload("res://scripts/core/stat_block.gd").new()
	var hit_src := {}
	func get_node_or_null(_path: String):
		return sfx
	func is_inside_tree() -> bool:
		return in_tree

func run(check: Callable) -> void:
	var game := VoiceGame.new()
	var spy := VoiceSpy.new()
	game.sfx = spy
	game.rng.seed = 123
	var before := game.rng.state
	var squad := Squad.new(game)
	var leader := Character.new(game, {"id": "skadi"})
	leader.is_leader = true
	var medic := Character.new(game, {"id": "lumen", "command": {"roam": false}})
	var fighter := Character.new(game, {"id": "texas"})
	var down := Character.new(game, {"id": "hoshiguma"})
	down.cmd_down = 5.0
	squad.ops = [medic, fighter, leader, down]
	squad.set_stance(Squad.ROAM)
	check.call(spy.calls == [["texas", "command", false]], "assault requests the sortieing teammate's own command voice, not the leader's")
	var called := spy.calls.size()
	squad.set_stance(Squad.ROAM)
	check.call(spy.calls.size() == called, "same stance does not request another voice")
	game.t += 7.0
	squad.set_stance(Squad.RECALL)
	check.call(spy.calls.size() == 1, "recall is silent (user 10-29)")
	squad.set_stance(Squad.ROAM)
	check.call(spy.calls.size() == 2 and spy.calls[-1] == ["texas", "command", false], "assault after a silent recall still speaks; non-roaming and downed followers do not")
	game.t += 1.0
	squad.set_stance(Squad.RECALL)
	squad.set_stance(Squad.ROAM)
	check.call(spy.calls.size() == 2, "rapid command change is throttled")
	game.t += 7.0
	squad._stance_voice(Squad.ROAM)
	check.call(spy.calls[-1] == ["texas", "command", false], "assault rotation stays on the sortieing teammates")
	squad.set_stance(Squad.GUARD)
	squad.stamina = 0.0
	squad.exhausted = true
	called = spy.calls.size()
	game.t += 20.0
	check.call(not squad.cycle_stance() and spy.calls.size() == called, "rejected assault has no voice")
	game.demo_op = "skadi"
	squad._stance_voice(Squad.ROAM)
	check.call(spy.calls.size() == called, "gallery demo suppresses command voices")
	game.demo_op = ""
	medic.is_leader = true
	leader.is_leader = false
	squad.ops = [medic]
	squad._vo_i = 0
	squad._stance_voice(Squad.ROAM)
	check.call(spy.calls[-1] == ["lumen", "command", false], "non-roaming operator may speak when leading")
	check.call(game.rng.state == before, "voice selection consumes no gameplay RNG")

	_chorus_rotation(check, game, spy)

	spy.calls.clear()
	var entrant := Character.new(game, {"id": "gladiia"})
	check.call(entrant.has_method("entry_started"), "character exposes entry-start hook")
	if entrant.has_method("entry_started"):
		entrant.entry_started()
		entrant.entry_started()
		check.call(spy.calls == [["gladiia", "entry", true]], "entry-start requests queued entry only once")
	var demo := Character.new(game, {"id": "lappland"})
	if demo.has_method("entry_started"):
		spy.calls.clear()
		game.demo_op = "lappland"
		demo.entry_started()
		check.call(spy.calls.is_empty(), "gallery demo suppresses entry hook")
		game.demo_op = ""
		game.in_tree = false
		demo.entry_started()
		check.call(spy.calls.is_empty(), "detached character does not request entry")
		game.in_tree = true
		demo.entry_started()
		check.call(spy.calls == [["lappland", "entry", true]], "suppressed entry does not consume the once-only hook")
	spy.calls.clear()
	var joined = Squad.new(game).add("gladiia", false)
	check.call(joined != null and spy.calls == [["gladiia", "entry", true]], "Squad.add immediate entry fallback is wired")
	if joined != null and joined.has_method("entry_started"):
		joined.entry_started()
		check.call(spy.calls.size() == 1, "later entry-start notification does not repeat join voice")
	# 开局编队：建局时（画面还没出来）不播登场语音，game.release_entry_voices 放开后才播（用户 10-25）
	spy.calls.clear()
	game.entry_voice_hold = true
	var held = Squad.new(game).add("texas", false)
	check.call(held != null and spy.calls.is_empty(), "opening squad entry voice waits while held")
	game.entry_voice_hold = false
	if held != null:
		held.entry_started()
		check.call(spy.calls == [["texas", "entry", true]], "held entry voice plays once released")
	spy.free()
	_asset_coverage(check)
	_channel_rules(check)
	_ult_mute(check)
	_pool_rules(check)

## 指挥合唱（10-28 用户「突击时两名队友的台词可以交替或一起喊」）：两名出击队友都开口，轮换谁先、其余晚 voice_stagger 秒
func _chorus_rotation(check: Callable, game, spy) -> void:
	var sq := Squad.new(game)
	var a := Character.new(game, {"id": "texas"})
	var b := Character.new(game, {"id": "skadi"})
	var ld := Character.new(game, {"id": "lumen"})
	ld.is_leader = true
	sq.ops = [ld, a, b]
	spy.calls.clear()
	spy.delays.clear()
	game.t += 30.0
	sq._stance_voice(Squad.ROAM)
	check.call(spy.calls == [["texas", "command", false], ["skadi", "command", false]], "assault chorus: both sortieing teammates speak")
	check.call(spy.delays.size() == 2 and is_zero_approx(spy.delays[0]) and is_equal_approx(spy.delays[1], 0.4), "chorus alternates: second line 0.4 s after the first")
	game.t += 7.0
	sq._stance_voice(Squad.RECALL)
	check.call(spy.calls.size() == 2, "recall chorus is silent (user 10-29)")
	sq._stance_voice(Squad.ROAM)
	check.call(spy.calls.slice(2) == [["skadi", "command", false], ["texas", "command", false]], "next assault chorus rotates who speaks first")


func _asset_coverage(check: Callable) -> void:
	var manifest = JSON.parse_string(FileAccess.get_file_as_string("res://audio/voice/voice_manifest.json"))
	check.call(manifest is Dictionary and manifest.get("clips", []).size() == 233, "runtime manifest: 121 clips + 2 synergy lines (docs/160) + 110 pooled lines (docs/190)")
	if not manifest is Dictionary:
		return
	var have := {}
	for clip in manifest.clips:
		have[clip.operator + ":" + clip.event] = true
	check.call(have.size() == 233, "runtime event pairs are unique")
	var ids := Character.list_ids()
	check.call(manifest.operators.size() == 20 and ids.size() == 20, "runtime voice map covers20 operators")
	for cid in ids:
		check.call(have.has(cid + ":command"), "approved command registered: " + cid)
		var stream = load("res://audio/voice/%s_command.ogg" % cid) if have.has(cid + ":command") else null
		check.call(stream is AudioStreamOggVorbis and stream.get_length() <= 8.0, "command OGG loads within voice limit: " + cid)
	for cid in ["lappland", "gladiia"]:
		for event in ["entry", "skill_1", "skill_2", "skill_3", "battle"]:
			check.call(have.has(cid + ":" + event), "new operator event registered: " + cid + ":" + event)

## 终结技期间只让队长开口（用户 10-30）：mute_mates 后队友的单通道 / 合唱 / 排队一律不播，队长照播；解除后恢复
func _ult_mute(check: Callable) -> void:
	var sfx = load("res://scripts/sfx.gd").new()
	sfx.voice_pools = {"_": {}}
	sfx.voice_player = AudioStreamPlayer.new()
	sfx.voice_fader = AudioStreamPlayer.new()
	if sfx._voice_stream("texas", "battle") != null and sfx._voice_stream("skadi", "skill_3") != null:
		sfx.voice_now = 3000.0
		sfx.mute_mates("skadi")
		sfx.voice("texas", "battle", true)
		check.call(sfx.voice_cid != "texas" and sfx.voice_queue.is_empty(), "ult: teammate chatter is dropped, not queued")
		sfx.voice("texas", "command", false, true)
		check.call(sfx.voice_cid != "texas" and sfx.voice_urgent.is_empty(), "ult: teammate command response is dropped")
		sfx.voice_chorus("texas", "command", 0.0)
		check.call(sfx.chorus_pending.is_empty() and not sfx.chorus.has("texas"), "ult: teammate chorus is dropped")
		sfx.voice("skadi", "skill_3", false, true)
		check.call(sfx.voice_cid == "skadi", "ult: leader's own ultimate line still plays")
		sfx.mute_mates("")
		sfx.voice_now = 3030.0
		sfx.voice("texas", "battle")
		check.call(sfx.voice_cid == "texas", "after the ultimate teammates may speak again")
	for cp in sfx.chorus.values():
		cp.free()
	sfx.voice_player.free()
	sfx.voice_fader.free()
	sfx.free()


func _channel_rules(check: Callable) -> void:
	var sfx = load("res://scripts/sfx.gd").new()
	sfx.voice_pools = {"_": {}}   # 这里只验通道规则：不走语音池，固定读 <干员>_<事件>.ogg（池见 _pool_rules）
	sfx.voice_player = AudioStreamPlayer.new()
	sfx.voice_fader = AudioStreamPlayer.new()
	var clip = sfx._voice_stream("skadi", "command")
	check.call(clip != null, "real channel can load command voice")
	if clip != null:
		sfx.voice_now = 1000.0
		sfx.voice("skadi", "command")
		check.call(sfx.voice_cid == "skadi" and sfx.voice_key == "command", "real channel starts command")
		sfx.voice_now = 1000.1
		sfx.voice("texas", "command")
		check.call(sfx.voice_cid == "skadi" and sfx.voice_queue.is_empty(), "busy command is dropped without queueing")
		sfx.voice("texas", "skill_1")
		check.call(sfx.voice_cid == "skadi", "skill does not add a new interruption exception for command")
		sfx.voice_now = 1000.0 + clip.get_length() + 2.0
		sfx.voice("texas", "command")
		check.call(sfx.voice_cid == "skadi", "command observes existing team gap")
		sfx.voice_now = 1000.0 + clip.get_length() + 3.01
		sfx.voice("texas", "command")
		check.call(sfx.voice_cid == "texas", "different operator may respond after team gap")
		sfx.voice_now = 1014.0
		sfx.voice("skadi", "command")
		check.call(sfx.voice_cid == "texas", "command observes existing15-second operator gap")
		sfx.voice_now = 1015.01
		sfx.voice("skadi", "command")
		check.call(sfx.voice_cid == "skadi", "command may resume when operator gap expires")
	# 合唱通道：错开的那句到点才开播；播出后记同人 / 全队间隔，单通道照旧（其它语音规则不变）
	var c2 = sfx._voice_stream("texas", "command")
	if clip != null and c2 != null:
		sfx.voice_now = 2000.0
		sfx.voice_chorus("skadi", "command", 0.0)
		sfx.voice_chorus("texas", "command", 0.4)
		check.call(float(sfx.voice_last.get("skadi:command", 0.0)) == 2000.0 and float(sfx.voice_last.get("texas:command", 0.0)) < 2000.0, "chorus: first line starts now, staggered line waits")
		sfx.voice_now = 2000.41
		sfx._chorus_tick()
		check.call(is_equal_approx(float(sfx.voice_last.get("texas:command", 0.0)), 2000.41) and sfx.chorus_pending.is_empty(), "chorus: staggered line starts after 0.4 s")
		check.call(sfx.voice_end >= 2000.41 + c2.get_length() + sfx.VOICE_GAP - 0.001, "chorus keeps the team gap after the last line")
		sfx.voice_now = 2001.0
		sfx.voice("kaltsit", "battle")
		check.call(sfx.voice_cid != "kaltsit", "battle chatter still waits for the team gap after a chorus")
		check.call(sfx.chorus.size() == 2, "one chorus player per operator")
	for cp in sfx.chorus.values():
		cp.free()
	sfx.voice_player.free()
	sfx.voice_fader.free()
	sfx.free()


## 语音池（10-29 用户「语音多一点」，docs/190）：每人每类条数够、文件能读；同一干员同一池洗牌不重复（一轮放完再洗、
## 新一轮不接上一句）；同一句 60 秒内不重复（普通语音放弃，指挥回应播最久没播的）；冷却 / 间隔仍按事件名
func _pool_rules(check: Callable) -> void:
	var sfx = load("res://scripts/sfx.gd").new()
	sfx.voice_player = AudioStreamPlayer.new()
	sfx.voice_fader = AudioStreamPlayer.new()
	var want := {"entry": 3, "command": 4, "skill": 4, "battle": 3}
	for cid in Character.list_ids():
		for pool in want:
			var stems: Array = sfx._voice_pool(cid, {"skill": "skill_1"}.get(pool, pool))
			var n := 0
			for s in stems:
				if sfx._voice_file(s) != null:
					n += 1
			check.call(n >= int(want[pool]) and n == stems.size(), "voice pool %s:%s has %d loadable lines (>= %d)" % [cid, pool, n, want[pool]])
	# 洗牌不重复：歌蕾蒂娅一技能隔 100 秒放 4 次 = 技能池 4 句各一次；第 5 次不接第 4 句
	var got: Array = []
	for i in 5:
		sfx.voice_now = 3000.0 + 100.0 * i
		sfx.voice_player.stream = null
		sfx.voice_end = 0.0
		sfx.voice("gladiia", "skill_1")
		got.append(str(sfx.voice_player.stream.get_instance_id()) if sfx.voice_player.stream != null else "")
	var first4 := {}
	for p in got.slice(0, 4):
		first4[p] = true
	check.call(first4.size() == 4 and not first4.has(""), "skill pool: one shuffled round plays all 4 lines once: %s" % [got])
	check.call(got[4] != got[3] and got[4] != "", "skill pool: next round does not repeat the previous line")
	# 同句 60 秒：池里都在 60 秒内时普通语音放弃，玩家指挥回应播最久没播的那句
	var bat: Array = sfx._voice_pool("gladiia", "battle")
	sfx.voice_now = 5000.0
	for j in bat.size():
		sfx.voice_line_last[bat[j]] = 4950.0 + j
	check.call(sfx._voice_pick("gladiia", "battle", false) == "", "same line not repeated within 60 s (chatter gives up)")
	check.call(sfx._voice_pick("gladiia", "battle", true) == bat[0], "urgent picks the least recently played line")
	# 突击连按：4 句轮完前不重复（urgent 不受同人间隔）
	var cmd := {}
	for k in 4:
		sfx.voice_now = 6000.0 + 7.0 * k
		sfx.voice_player.stream = null
		sfx.voice_end = 0.0
		sfx.voice("gladiia", "command", false, true)
		cmd[sfx.voice_player.stream.get_instance_id()] = true
	check.call(cmd.size() == 4, "command pool: 4 presses give 4 different lines")
	sfx.voice_player.free()
	sfx.voice_fader.free()
	sfx.free()
