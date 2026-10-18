extends Node
const AP = preload("res://scripts/characters/blocks/attack_phases.gd")
const OB = preload("res://scripts/characters/blocks/seg_skalter.gd")
const Fixture = preload("res://tests/data_ops/attack_phases_fixture.gd")
var checks := 0
var failures := 0
var g
func ok(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + label)
func step(o, dt: float) -> void:
	o.follow(dt, o.pos)
	o.update(dt)
func start(o) -> void:
	AP.cancel(o)
	o._sq_clear()
	o.attack_t = 0.0
	o.fire_t = -1.0
	o.events.clear()
	o.ends = 0
	o.sp = [-10000.0,-10000.0,-10000.0]
	o.start_skill(Vector2.INF,0)
	for k in 24:
		step(o,1.0/60)
func _ready() -> void:
	g = load("res://game.tscn").instantiate()
	add_child(g)
	await get_tree().process_frame
	g.set_process(false)
	var definition: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/data_ops/attack_phases_fixture.json"))
	var o = Fixture.new(g,definition)
	o.pos = g.ppos
	o.is_leader = true
	o.elite = 2
	for e in g.enemies:
		e.dead = true
	g.enemies = []
	var enemy: Dictionary = g.spawner.spawn_enemy("runner",o.pos+Vector2(100,0))
	enemy.hp = 1000000.0
	enemy.max_hp = enemy.hp
	g.enemies_sys.build_grid()
	start(o)
	ok(not o.phases.is_empty() and o.phases.skill == 0,"S1 fixture activates shared phases")
	ok(not o.hw.has("wd"),"ordinary circle has no cannon state")
	ok(o.skills_occupied() and o.charge_skills(0.0) == -1,"shared automatic occupancy")
	o.sp[2] = o.sp_need(2)
	ok(not o.manual_ready(2),"manual occupancy")
	var old_skill: int = o.cur_skill
	o.start_skill(Vector2.INF,2)
	ok(o.cur_skill == old_skill,"direct or buffered cast cannot interrupt")
	o.sp[2] = 0.0
	o.tick_sp(.1)
	ok(o.sp[2] > 0.0,"other skills charge during stage")
	var saved: Dictionary = o.phases
	AP.start(o,0)
	ok(is_same(saved,o.phases),"duplicate activation retains running state")
	for rate in [1.0,2.0,4.0]:
		start(o)
		g.stats.remove_source("phase_test")
		g.stats.add(&"op_aspd","override",rate,"phase_test","op:phase_fixture")
		o.refresh_stats()
		o.attack_t = 0.0
		o.fire_t = -1.0
		o.s_t[0] = 1.5
		AP.tick(o,0.0)
		o.cd = 1.4/rate
		o.start_attack(enemy.pos, .5,.25,"",o.cd)
		ok(o.phases.index == 0 and o.phases.round.burst == 1,"round snapshot before non-half boundary")
		ok(absf(o.cd-1.4*.8/rate)<.00001,"phase interval respects attack speed")
		o.s_t[0] = 1.0
		AP.tick(o,0.0)
		ok(o.phases.index == 0,"boundary waits for attack recovery")
		o.attack_t = 0.0
		o.fire_t = -1.0
		AP.tick(o,0.0)
		ok(o.phases.index == 1,"stage switches at configured .3 after recovery")
		o.phases.transition = 0.0
		o.vis_anim = ""
		o.cd = 1.4/rate
		o.start_attack(enemy.pos,.5,.25,"",o.cd)
		o.attack_t = o.attack_dur-o.attack_fire_at
		var hp: float = enemy.hp
		var n: int = o.atk_n
		o._release()
		ok(o.phases.queue.size()==2 and o.atk_n==n+1,"three-shot round counts once")
		ok(enemy.hp < hp,"generic phase shot executes ordinary shape damage")
		o.s_t[0] = 0.0
		ok(o.skill_active_left(0)>0.0 and o.ends==0,"expiry preserves final round and defers end")
		o.attack_t = 0.0
		o.fire_t = -1.0
		var emitted: int = o.events.size()
		AP.tick(o,2.0)
		ok(o.events.size()==emitted+2,"large dt drains all pending events once")
		ok(o.atk_n==n+1 and o.ends==1,"burst does not multiply round counter or end callback")
		AP.tick(o,0.0)
		ok(o.events.size()==emitted+2 and o.ends==1,"no repeated queue or callback")
		ok(o.events[-1].damage == .75,"last shot keeps phase multiplier after duration expiry")
	start(o)
	o.s_t[0]=1.0
	o.attack_t=0.0
	o.fire_t=-1.0
	AP.tick(o,0.0)
	o.phases.transition=0.0
	o.cd=1.0
	o.start_attack(enemy.pos)
	o._release()
	AP.cancel(o)
	var count: int=o.events.size()
	AP.tick(o,2.0)
	ok(o.phases.is_empty() and o.events.size()==count and o.fire_t<0,"cancel clears pending rounds")
	# Replacement owns the whole round: it must not leave delayed phase shots.
	start(o)
	o.attack_t=0.0
	o.fire_t=-1.0
	o.s_t[0]=1.0
	AP.tick(o,0.0)
	o.phases.transition=0.0
	o.cd=1.0
	o.start_attack(enemy.pos,.5,.25,"s2_over_attack")
	ok(o.act_anim=="attack" and o.sq_atk==o.phases.round.anim,"phase slots own explicit attack animation")
	o.B.trait=[{"_tag":"trig.every_n","n":1,"replace":true,"do":[]}]
	o.B.erase("_el_rep")
	o._tg_key=-1
	count=o.events.size()
	o._release()
	ok(o.events.size()==count and o.phases.queue.is_empty(),"every_n replacement suppresses entire phase round")
	o.B.trait=[]
	o.B.erase("_el_rep")
	o._tg_key=-1
	# Generic cone uses the sampled target direction rather than the default nearest aim.
	start(o)
	var cone: Dictionary={"shape":"cone","r":220,"half_deg":10,"src":"fixture","ring":false}
	var round_: Dictionary={"attack":cone,"target":"random","damage_mult":1.5,"anim":"attack"}
	var hp_before: float=enemy.hp
	var aim_before: Vector2=o.atk_aim
	o.phase_shot(round_,0)
	ok(enemy.hp<hp_before and o.atk_aim==aim_before,"generic random cone damages and restores input aim")
	# Inherited manual targeting must preserve the aimed ground point.
	enemy.pos=o.pos+Vector2(-20,0)
	g.enemies_sys.build_grid()
	o.atk_aim=Vector2.RIGHT
	var circle: Dictionary={"shape":"circle","center":"target","r":20,"range":220,"src":"fixture","ring":false}
	hp_before=enemy.hp
	o.phase_shot({"attack":circle,"target":"inherit","damage_mult":1.0,"anim":"attack"},0)
	ok(enemy.hp==hp_before,"inherit manual ground aim does not retarget enemy behind")
	o.atk_aim=Vector2.ZERO
	enemy.pos=o.pos+Vector2(100,0)
	g.enemies_sys.build_grid()
	# Dead targets consume queued rounds without RNG retries or retained events.
	o.attack_t=0.0
	o.fire_t=-1.0
	o.s_t[0]=1.0
	AP.tick(o,0.0)
	o.phases.transition=0.0
	o.cd=1.0
	o.start_attack(enemy.pos)
	o._release()
	enemy.dead=true
	g.enemies_sys.build_grid()
	var rng_before: int=g.rng.state
	o.attack_t=0.0
	o.fire_t=-1.0
	AP.tick(o,2.0)
	ok(o.phases.queue.is_empty() and g.rng.state==rng_before,"empty target queue drains without retry sampling")
	enemy.dead=false
	g.enemies_sys.build_grid()
	start(o)
	o.on_leave()
	ok(o.phases.is_empty(),"retreat cancels phase ownership")
	start(o)
	o.pos=Vector2.INF
	AP.tick(o,.1)
	ok(o.phases.is_empty(),"off-field cancels queued work")
	o.pos=g.ppos
	enemy.dead=true
	g.enemies_sys.build_grid()
	start(o)
	for k in 240:
		step(o,1.0/60)
	ok(o.phases.is_empty() and o.ends==1,"no-target duration exits and ends once")
	var compiled: Dictionary=OB.compile(definition)
	var ctx: Dictionary={"base":definition.base,"sprites":definition.sprites,"errs":[]}
	AP.validate(definition.blocks.skills[0],"fixture",ctx,definition.blocks.attack,0,OB.eval_expr)
	ok(ctx.errs.is_empty(),"ordinary stage config validates without muzzles")
	for mutation in ["duration","ratio","burst","offsets","shape","flow","slot","random_center","armed","fps","sequence","strip","attack","sequences"]:
		var d: Dictionary=definition.duplicate(true)
		match mutation:
			"duration":d.blocks.skills[0].dur=INF
			"ratio":d.blocks.skills[0].attack_phases[1].at=0
			"burst":d.blocks.skills[0].attack_phases[1].burst=2.5
			"offsets":d.blocks.skills[0].attack_phases[1].shot_offsets=[0,.5,.5]
			"shape":d.blocks.attack.shape="projectile"
			"flow":d.blocks.attack.flow="free"
			"slot":d.sprites.skills.s1.phases[1].attack="missing"
			"random_center":d.blocks.attack.center="self"
			"armed":d.blocks.attack.armed={}
			"fps":d.sprites.s2_attack.fps=INF
			"sequence":d.sprites.skills.s1=3
			"strip":d.sprites.s2_attack=3
			"attack":d.blocks.attack=null
			"sequences":d.sprites.skills=[]
		ctx={"base":d.base,"sprites":d.sprites,"errs":[]}
		AP.validate(d.blocks.skills[0],"fixture",ctx,d.blocks.attack,0,OB.eval_expr)
		ok(not ctx.errs.is_empty(),"reject invalid "+mutation)
	ok(AP.has_swap({"trait":[{"do":[{"verb":"swap_attack"}]}]}),"nested attack swap detected")
	ok(compiled.skills[0].attack_phases[1].burst==3,"fixture has configurable three-shot phase")
	print("ATTACK PHASES checks=%d failures=%d" % [checks,failures])
	get_tree().quit(1 if failures else 0)
