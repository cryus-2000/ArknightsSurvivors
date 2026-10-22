extends Node
const Ch=preload("res://scripts/characters/character.gd")
const Op=preload("res://scripts/characters/data_operator.gd")
const NM=preload("res://scripts/characters/native_motion.gd")
class AuditOp extends "res://scripts/characters/data_operator.gd":
	var active := [0.0,0.0,0.0]
	func _release(): pass
	func _release_skill(): pass
	func skill_active_left(i: int) -> float: return active[i]
var checks:=0
var failures:=0
func ok(value: bool,label: String):
	checks+=1
	if not value:
		failures+=1
		printerr("FAIL: "+label)
func _ready():
	var g=load("res://game.tscn").instantiate()
	add_child(g)
	await get_tree().process_frame
	g.set_process(false)
	var rows: Array=[]
	var ids: Array=JSON.parse_string(FileAccess.get_file_as_string("res://tests/data_ops/approved_attack_rhythm.json")).keys()
	for id in ids:
		for skill in 3:
			var o=AuditOp.new(g,Ch.load_def(id).duplicate(true))
			o.pos=g.ppos
			o.elite=2
			o.refresh_stats()
			o.start_skill(Vector2.INF,skill)
			var slot: String=o.act_anim
			var spec: Dictionary=o.sprite_spec(slot)
			var elapsed: float=o.fire_t+0.000001
			o.attack_t=maxf(0.0,o.attack_dur-elapsed)
			o.anim_t=elapsed
			NM.tick(o,elapsed)
			var st: Dictionary=o.anim_state()
			var row={"id":id,"skill":skill+1,"slot":slot,"logical_fire":elapsed-0.000001,"duration":o.attack_dur,"expected":spec.get("fire",-1),"actual":st.get("frame",-1),"kind":st.get("kind","")}
			rows.append(row)
			if row.kind==slot and int(row.expected)>=0: ok(row.expected==row.actual,"cast release "+JSON.stringify(row))
			var seq: Dictionary=o.skill_seq(skill)
			if seq.has("run") and not seq.has("hold"):
				o.sq=seq
				o.sq_i=skill
				o.sq_ph=2
				o.sq_own=false
				o.active[skill]=8.0
				o.attack_t=0.0
				o.fire_t=-1.0
				o.sq_atk=""
				o.anim_kind=o.seq_anim(seq.run)
				o.mv=150.0
				o.run_ph=5.2
				o.sq_t=0.0
				st=o.anim_state()
				if st.kind=="run": ok(st.frame==5,"continuous run clock "+id+" s"+str(skill+1))
				if seq.has("attack"):
					o.cd=0.8
					o.start_attack(Vector2.INF)
					o.attack_t=o.attack_dur-o.attack_fire_at-0.001
					o._tick_sq_atk(0.0)
					o.anim_kind=o.sq_atk if o.sq_atk!="" else o._sq_kind()
					st=o.anim_state()
					ok(st.kind==o.seq_anim(seq.run),"moving recovery "+id+" s"+str(skill+1))
					var variant: String=o.seq_anim(seq.attack)
					ok(o.sq_atk==variant,"moving keeps variant clock "+id)
					o.follow(0.0,o.pos)
					ok(o.anim_state().kind==o.seq_anim(seq.run),"follow yields to skill movement "+id)
					o.mv=0.0
					o.follow(0.0,o.pos)
					st=o.anim_state()
					ok(st.kind==variant,"stopping resumes current variant "+id)
					ok(st.frame==o._sq_atk_frame(int(o.sprite_spec(variant).frames)),"stopping preserves recovery frame "+id)
					o.attack_t=0.0
					o._tick_sq_atk(o.attack_dur)
					o.follow(0.0,o.pos)
					ok(o.sq_atk=="" and o.anim_state().kind==o._sq_kind(),"finished variant returns to loop "+id)
					o.mv=150.0
					o.follow(0.0,o.pos)
					o.mv=0.0
					o.follow(0.0,o.pos)
					ok(o.sq_atk=="","finished variant cannot revive "+id)
					var clock: Array=[o.attack_t,o.fire_t,o.cd]
					for j in 4: o.anim_state()
					ok(clock==[o.attack_t,o.fire_t,o.cd],"drawing preserves attack clocks "+id)
			if not seq.is_empty():
				o.active[skill]=0.0
				o.attack_t=0.0
				o.fire_t=-1.0
				o._tick_sq(5.0)
				o._tick_sq(5.0)
				ok(o.sq_ph==0,"skill sequence exits "+id+" s"+str(skill+1))
	var heavy=AuditOp.new(g,Ch.load_def("siege").duplicate(true))
	heavy.pos=g.ppos
	heavy._start_action("skill",Vector2.INF,0.6,0.3,"heavy_attack")
	var fire: float=heavy.fire_t
	heavy.attack_t=heavy.attack_dur-fire-0.000001
	NM.tick(heavy,fire+0.000001)
	ok(heavy.anim_state().frame==int(heavy.sprite_spec("heavy_attack").fire),"Siege heavy hit pose matches actual hit")
	NM.tick(heavy,heavy.attack_t+0.000001)
	heavy.attack_t=0.0
	ok(NM.state(heavy,{"kind":"idle","frame":0}).kind=="idle","Siege heavy recovery ends with action")
	print("OPERATOR TRANSITIONS %d casts, %d checks, %d failed" % [rows.size(),checks,failures])
	get_tree().quit(0 if failures==0 else 1)
