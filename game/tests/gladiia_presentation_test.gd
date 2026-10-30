extends Node
const Ch = preload("res://scripts/characters/character.gd")
const Op = preload("res://scripts/characters/data_operator.gd")
const Ob = preload("res://scripts/characters/op_blocks.gd")
const Fx = preload("res://scripts/characters/blocks/ob_fx.gd")
class CanvasProbe extends RefCounted:
 var alpha := -1.0
 func draw_set_transform(_pos, _ang, _scale): pass
 func draw_texture_rect_region(_tx, _rect, _region, col): alpha=col.a
var checks:=0
var failures:=0
func ok(value: bool,label: String):
 checks+=1
 if not value:
  failures+=1
  printerr("FAIL: "+label)
func entries(value, key: String, expected: String, out: Array):
 if value is Dictionary:
  if str(value.get(key,""))==expected: out.append(value)
  for v in value.values(): entries(v,key,expected,out)
 elif value is Array:
  for v in value: entries(v,key,expected,out)
func _ready():
 var g=load("res://game.tscn").instantiate()
 add_child(g)
 await get_tree().process_frame
 g.set_process(false)
 var definition=Ch.load_def("gladiia")
 var ctx={"base":definition.base,"srcs":definition.hit_sources,"errs":[],"custom":0,"summons":{},"sprites":definition.sprites,"stat_defs":{}}
 for flag in ["no_fade","inward"]:
  ctx.errs.clear()
  var invalid={"strip":"fx_gladiia_pull"}
  invalid[flag]="wrong"
  Ob._fx([invalid],"fx",ctx,"verb.field")
  ok(ctx.errs.any(func(e):return flag in str(e)),flag+" rejects wrong type")
 ctx.errs.clear()
 var invalid_hook: Dictionary=definition.blocks.skills[0].do[0].duplicate(true)
 invalid_hook.thin_chain="wrong"
 Ob._block(invalid_hook,"hook","skill",ctx)
 ok(ctx.errs.any(func(e):return "thin_chain" in str(e)),"thin_chain rejects wrong type")
 for invalid_end in [true,{"skill":"wrong","fx":[]},{"skill":0.5,"fx":[]},{"skill":2,"fx":"wrong"}]:
  ctx.errs.clear()
  var invalid_field: Dictionary=definition.blocks.skills[2].do[0].duplicate(true)
  invalid_field.visual_end=invalid_end
  Ob._block(invalid_field,"field","skill",ctx)
  ok(ctx.errs.any(func(e):return "visual_end" in str(e)),"visual_end rejects invalid shape/index/fx")
 var o=Op.new(g,Ch.load_def("gladiia").duplicate(true))
 ok(Ob.validate("gladiia",Ch.load_def("gladiia")),"updated visual schema validates")
 o.pos=g.ppos
 var hooks: Array=[]
 entries(o.B,"shape","hookshot",hooks)
 ok(hooks.size()==2,"both hook paths covered (%d)" % hooks.size())   # docs/202 怒海改机制后路线不再切三份钩索参数：普攻 + S1 重钩
 for h in hooks:
  ok(h.get("thin_chain",false),"hook uses slim tether")
 for name in ["fx_gladiia_tornado_open","fx_gladiia_tornado_loop","fx_gladiia_tornado_close","fx_gladiia_ram"]:
  var fx: Array=[]
  entries(o.B,"strip",name,fx)
  ok(not fx.is_empty(),name+" remains wired")
  for f in fx:
   var anchor: Array=f.get("anchor",[])
   ok(anchor.size()==2 and is_equal_approx(float(anchor[0]),32.0) and is_equal_approx(float(anchor[1]),50.0 if name=="fx_gladiia_ram" else 58.0),name+" uses delivered ground origin")
 var b: Dictionary=o.B.skills[2].do[0]
 var ticks: Array=[]
 entries(b.do,"strip","fx_gladiia_pull",ticks)
 ok(not ticks.is_empty(),"actual field tick emits inward water")
 var center=o.pos+Vector2(100,40)
 o.last_hit_pos=center
 ok(str(b.get("pix",""))=="gl_s3","S3 field uses pixfx vortex (10-31)")
 b.erase("pix")   # 下面核原帧条后备路径（缺图 / g.ult 关时照播）
 o.s_t[2]=8.0
 o._ext_exec(b,Vector2.INF)
 ok(o.fields.size()==1,"field created once")
 var loops: Array=[]
 for f in o.pfx:
  if f.get("name","")=="fx_gladiia_tornado_loop": loops.append(f)
 ok(loops.size()==1,"one loop bound to one field")
 if not loops.is_empty():
  var probe=CanvasProbe.new()
  loops[0].life=1.0
  Fx.fx_draw(probe,g,loops[0],1.0)
  ok(is_equal_approx(probe.alpha,1.0),"loop stays solid until actual end")
 var unrelated: Dictionary=loops[0].duplicate()
 o.pfx.push_front(unrelated)
 # 后续命中点改变，收尾仍使用场中心快照；只终止画面。
 o.last_hit_pos=center+Vector2(180,0)
 o.s_t[2]=0.0
 o._ext_sustain([],0.0)
 var closes: Array=[]
 for f in o.pfx:
  if f.get("name","")=="fx_gladiia_tornado_close": closes.append(f)
 ok(closes.size()==1,"skill end emits exactly one visual close")
 if closes.size()==1:
  ok(closes[0].pos==center+Vector2(0,4),"close stays at field snapshot")
 if not loops.is_empty(): ok(loops[0].life<=0.0,"skill end stops loop immediately")
 ok(o.pfx.has(unrelated) and unrelated.life>0.0,"closing a field preserves unrelated same-texture particle")
 ok(o.fields.size()==1 and o.fields[0].done==0,"visual close leaves gameplay field and tick count intact")
 o._ext_sustain([],0.0)
 var count:=0
 for f in o.pfx:
  if f.get("name","")=="fx_gladiia_tornado_close": count+=1
 ok(count==1,"visual end is idempotent")
 # 保持原有 0.75 秒间隔和 11 次判定，区域移除只触发一次画面收尾。
 o.fields.clear()
 o.pfx.clear()
 o.s_t[2]=8.0
 o.last_hit_pos=center
 o._ext_exec(b,Vector2.INF)
 var field: Dictionary=o.fields[0]
 o._ext_sustain([],8.25)
 ok(o.fields.is_empty() and field.done==11,"natural expiry retains all original gameplay ticks")
 count=0
 for f in o.pfx:
  if f.get("name","")=="fx_gladiia_tornado_close": count+=1
 ok(count==1,"natural expiry emits one close")
 o.pfx.clear()
 o._ext_exec(b,Vector2.INF)
 o.last_hit_pos=center+Vector2(50,0)
 o._ext_exec(b,Vector2.INF)
 count=0
 for f in o.pfx:
  if f.get("name","")=="fx_gladiia_tornado_close": count+=1
 ok(o.fields.size()==1 and o.fields[0].pos==o.last_hit_pos,"field cap retains newest gameplay field")
 ok(count==1,"field replacement closes old visual only once")
 # 每条水带按自身散布位置朝向中心。
 o.pfx.clear()
 Fx.fx_play(o,[{"strip":"fx_gladiia_pull","n":6,"spread":0.8,"inward":true}],center,100.0)
 for f in o.pfx:
  ok(Vector2.from_angle(f.ang).dot((center-f.pos).normalized())>0.999,"water ribbon points into field center")
 # 走真实 update 顺序：技能结束的原有结算先执行，画面独立收尾。
 var live=Op.new(g,Ch.load_def("gladiia").duplicate(true))
 live.pos=g.ppos
 live.no_attack=true
 live.last_hit_pos=center
 live.s_t[2]=0.01
 live.B.skills[2].do[0].erase("pix")   # 同上：核原帧条后备路径
 live._ext_exec(live.B.skills[2].do[0],Vector2.INF)
 live.last_hit_pos=center+Vector2(170,0)
 live.update(0.02)
 count=0
 for f in live.pfx:
  if f.get("name","")=="fx_gladiia_tornado_close":
   count+=1
   ok(f.pos==center+Vector2(0,4),"real update closes at saved field center")
 ok(count==1,"real skill-end update emits close once")
 ok(live.fields.size()==1 and live.fields[0].done==0,"real update does not expire gameplay field early")
 print("GLADIIA PRESENTATION %d checks, %d failed" % [checks,failures])
 get_tree().quit(0 if failures==0 else 1)
