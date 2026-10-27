extends RefCounted
## Solid material silhouettes underneath short-lived granular detail. Read-only presentation.
const DEEP := Color(0.025, 0.09, 0.14)
const SEA := Color(0.08, 0.36, 0.42)
const LIT := Color(0.28, 0.65, 0.68)
const FOAM := Color(0.78, 0.95, 0.89)

static func draw(g, w: Dictionary, alpha: float) -> bool:
	var age: float = float(w.get("age", float(w.get("max", 0.0)) - float(w.get("life", 0.0))))
	var skin: String = str(w.get("skin", ""))
	var r = g.world
	match skin:
		"ice": _ice(r, w, age, alpha)
		"ice_field": _ice_field(r,w,age,alpha)
		"crescent": _blade(r, w, age, alpha)
		"spear", "step": _spear(r, w, age, alpha)
		"choir":
			if w.shape == "circle": _pearl(r, w, age, alpha)
			else: _choir(r, w, age, alpha)
		"tentacle":
			if w.shape == "cone":
				_cone_water(r, w, age, alpha)
				for k in 3:
					_arm(r, w.pos, w.ang + (k - 1) * w.half * 0.66, w.r, 30.0, age, alpha, k)
			else: _arm(r, w.pos, w.ang, w.len, w.wid, age, alpha, 1)
		"tide": _wave(r, w, age, alpha)
		"abyss": _surge(r, w, g.combat.GROUND_Y, age, alpha)
		_: return false
	return true

static func _c(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, a)

static func _n(i: int, salt := 0) -> float:
	var x: int = (i * 73471 + salt * 19391 + 137) & 65535
	x = ((x ^ (x >> 7)) * 127) & 65535
	return float(x) / 65535.0

static func _poly(r, points: Array, c: Color) -> void:
	var p := PackedVector2Array()
	for v in points: p.append(v.snapped(Vector2(2, 2)))
	r.tb_poly(p, c)

static func _band(r, a: Vector2, b: Vector2, wa: float, wb: float, c: Color) -> void:
	var n := (b - a).normalized().orthogonal()
	_poly(r, [a-n*wa, b-n*wb, b+n*wb, a+n*wa], c)

static func _grain(r, p: Vector2, c: Color) -> void:
	var q := p.snapped(Vector2(2, 2))
	r.tb_quad(q, q+Vector2(2,0), q+Vector2(2,2), q+Vector2(0,2), c)

static func _oval(r, p: Vector2, rx: float, ry: float, c: Color, angle := 0.0) -> void:
	var pts: Array = []
	for i in 16:
		var a: float = TAU * i / 16.0
		pts.append(p + Vector2(cos(a)*rx, sin(a)*ry).rotated(angle))
	_poly(r, pts, c)

static func _ice(r, w: Dictionary, age: float, alpha: float) -> void:
	var d := Vector2.from_angle(w.ang)
	var n := d.orthogonal()
	var count: int = maxi(4, ceili(w.len / 28.0))
	for i in count:
		var t: float = (i + 0.5) / count
		var p: Vector2 = w.pos + d * w.len * t
		var lean: float = (_n(i,2)-0.5)*18
		var height: float = 17 + _n(i,5)*24
		var half: float = 6 + _n(i,3)*7
		# Frost roots cover the attack width; the crystal rises off that ground plane.
		_oval(r, p, 19, w.wid, _c(Color(.1,.27,.34),alpha*.65),w.ang)
		var tip: Vector2 = p + Vector2(lean,-height)
		_poly(r,[p-d*half+n*4,p+n*9,p+d*half,tip],_c(Color(.09,.28,.39),alpha))
		_poly(r,[p-d*half+n*4,tip,p+Vector2(lean*.4,-height*.22)],_c(Color(.28,.58,.72),alpha))
		_poly(r,[p+Vector2(lean*.4,-height*.22),tip,p+d*half],_c(Color(.59,.83,.9),alpha))
		_band(r,p+Vector2(lean*.4,-height*.22),tip,1,1,_c(Color(.87,1.04,1.08),alpha))
		var crack: Vector2 = p + n * (w.wid * (.4 + _n(i,8)*.4))
		_band(r,p-d*13,crack,1,1,_c(Color(.4,.66,.76),alpha*.8))
		for j in 3:
			var q := p + Vector2((_n(i*3+j,4)-.5)*34,-(8+_n(i*3+j,6)*22)-age*18)
			_grain(r,q,_c(Color(.55,.83,.9),alpha*.7))

static func _ice_field(r, w: Dictionary, age: float, alpha: float) -> void:
	var d := Vector2.from_angle(w.ang)
	var n := d.orthogonal()
	var end: Vector2 = w.pos+d*w.len
	_poly(r,[w.pos-n*w.wid,end-n*w.wid,end+n*w.wid,w.pos+n*w.wid],_c(Color(.14,.30,.40),alpha*.38))
	for row in 3:
		for col in 20:
			var k: int = row*20+col
			var along: float = (col+.3+_n(k,5)*.4)*w.len/20
			var p: Vector2 = w.pos+d*along+n*((row-1)*46+(_n(k,4)-.5)*12)
			var height: float = 24+_n(k,9)*33
			var half: float = 9+_n(k,3)*7
			var tip: Vector2 = p+Vector2((_n(k,7)-.5)*15,-height)
			_oval(r,p,22,12,_c(Color(.11,.27,.35),alpha*.75),w.ang)
			_poly(r,[p-Vector2(half,0),p+Vector2(0,7),p+Vector2(half,0),tip],_c(Color(.08,.22,.33),alpha))
			var seam: Vector2 = p+Vector2(2,-height*.25)
			_poly(r,[p-Vector2(half,0),tip,seam],_c(Color(.31,.55,.70),alpha))
			_poly(r,[seam,tip,p+Vector2(half,0)],_c(Color(.66,.85,.93),alpha))
			_band(r,seam,tip,1,1,_c(Color(.89,.97,1),alpha))
			_poly(r,[p+Vector2(half*.4,2),p+Vector2(half+8,-height*.55),p+Vector2(half+10,3)],_c(Color(.39,.66,.8),alpha))
			_band(r,p-d*20,p+n*16,1,1,_c(Color(.51,.73,.85),alpha*.75))
			_grain(r,tip+Vector2(4,-age*25),_c(FOAM,alpha*.7))

static func _blade(r, w: Dictionary, age: float, alpha: float) -> void:
	var formation: float = float(w.get("formation", 1.0))
	var extent: float = float(w.half) * formation
	var forward := Vector2.from_angle(w.ang)
	var center: Vector2 = w.pos - forward*float(w.get("arc_back",0.0))
	for i in 64:
		var u: float = float(i)/64
		var v: float = float(i+1)/64
		var va := Vector2.from_angle(w.ang + lerpf(-extent,extent,u))
		var vb := Vector2.from_angle(w.ang + lerpf(-extent,extent,v))
		var a: Vector2 = center + va*w.r
		var b: Vector2 = center + vb*w.r
		var wa: float = w.wid*(.12+.88*sin(u*PI))
		var wb: float = w.wid*(.12+.88*sin(v*PI))
		# Translucent ice facets, fractured seam and irregular frost teeth share the curved cutting edge.
		_poly(r,[a-va*w.wid,b-vb*w.wid,b+vb*w.wid,a+va*w.wid],_c(Color(.18,.38,.51),alpha*.32))
		_poly(r,[a-va*wa,b-vb*wb,b+vb*wb,a+va*wa],_c(Color(.06,.17,.27),alpha))
		var seam_a: Vector2 = a + va*wa*(_n(i,3)-.4)*.8
		var seam_b: Vector2 = b + vb*wb*(_n(i+1,3)-.4)*.8
		_poly(r,[a-va*wa,seam_a,seam_b,b-vb*wb],_c(Color(.25,.46,.60),alpha*.9))
		_poly(r,[seam_a,a+va*wa,b+vb*wb],_c(Color(.54,.76,.85) if i%3 else Color(.73,.88,.93),alpha))
		_poly(r,[seam_a,b+vb*wb,seam_b],_c(Color(.35,.60,.74),alpha))
		if i%3 != 0:
			_band(r,a+va*wa,b+vb*wb,1.5,1.5,_c(Color(.88,.98,1.0),alpha))
		if i%4 == 1:
			var tooth: Vector2 = a.lerp(b,.5)+va*(wa+3+_n(i,11)*5)
			_poly(r,[seam_a,tooth,b+vb*wb*.8],_c(Color(.69,.87,.94),alpha))
		if i%5 == 2:
			_band(r,a-va*wa*.8,seam_b,1,1,_c(Color(.025,.13,.23),alpha*.85))
			_band(r,seam_b,b+vb*wb*.65,1,1,_c(Color(.025,.13,.23),alpha*.85))
		if _n(i,8)>.55:
			var drift: float = (1.0-formation)*45.0 if formation<.99 else fmod(age*100+i*3.7,48)
			var shard: Vector2 = a-forward*(wa+drift)
			_poly(r,[shard-forward*6,shard+va*3,shard+forward*4,shard-va*2],_c(Color(.64,.83,.93),alpha*.75))

static func _spear(r, w: Dictionary, age: float, alpha: float) -> void:
	var d := Vector2.from_angle(w.ang)
	var n := d.orthogonal()
	var p: Vector2 = w.pos
	var end: Vector2 = p+d*w.len
	for j in 5:
		var side: float = (j-2)*.44
		var a: Vector2 = p+d*(20+j*9)+n*w.wid*side
		var b: Vector2 = end-d*(18+absf(side)*36)+n*w.wid*side
		_band(r,a,b,2,1,_c(Color(.25,.5,.62),alpha*.28))
	_band(r,p,end-d*38,4,5,_c(Color(.05,.13,.19),alpha))
	_band(r,p-n*2,end-d*34-n*2,1.2,1.2,_c(Color(.55,.72,.76),alpha))
	_poly(r,[end-d*72-n*16,end-d*20-n*7,end,end-d*18+n*8,end-d*72+n*16,end-d*53],_c(Color(.14,.3,.4),alpha))
	_poly(r,[end-d*72-n*16,end,end-d*49+n*2],_c(Color(.52,.74,.82),alpha))
	_band(r,end-d*64-n*12,end,1.2,.7,_c(Color(.91,1.05,1.08),alpha))
	for j in 8:
		var t: float = _n(j,7)
		_grain(r,p+d*w.len*t+n*w.wid*(_n(j,9)*2-1)-d*age*30,_c(LIT,alpha*.65))

static func _arm_center(p: Vector2, d: Vector2, n: Vector2, length: float, width: float, u: float, age: float, salt: int) -> Vector2:
	var bend: float = sin(u*PI*1.7+salt*.7+age*4)*sin(u*PI)*width*.58
	var lift: float = sin(u*PI)*5 + 2
	return p+d*length*u+n*bend+Vector2(0,-lift)

static func _arm(r, p: Vector2, angle: float, length: float, width: float, age: float, alpha: float, salt: int) -> void:
	var d := Vector2.from_angle(angle)
	var n := d.orthogonal()
	var count: int = ceili(length/12)
	# Broad wet shadow anchors an emerging organic limb; no rectangular overlay.
	for i in count:
		var u: float = float(i)/count
		var v: float = float(i+1)/count
		var a := _arm_center(p,d,n,length,width,u,age,salt)
		var b := _arm_center(p,d,n,length,width,v,age,salt)
		var ta: float = width*(.62-.5*pow(u,.85))*(1+.12*sin(u*PI*9))
		var tb: float = width*(.62-.5*pow(v,.85))*(1+.12*sin(v*PI*9))
		_band(r,p+d*length*u,p+d*length*v,width,width,_c(Color(.06,.22,.27),alpha*.14))
		_band(r,a+Vector2(0,4),b+Vector2(0,4),ta+2,tb+2,_c(DEEP,alpha))
		_band(r,a,b,ta,tb,_c(Color(.06,.3,.37),alpha))
		_band(r,a-n*ta*.22,b-n*tb*.22,ta*.64,tb*.64,_c(Color(.13,.48,.51),alpha))
		_band(r,a-n*ta*.53,b-n*tb*.53,ta*.12,tb*.12,_c(Color(.35,.68,.66),alpha))
		if i%2==1:
			var at := a+n*ta*.5
			_oval(r,at,5.0,3.5,_c(Color(.025,.15,.21),alpha),angle)
			_oval(r,at-n,3,2,_c(Color(.65,.79,.66),alpha),angle)
		if _n(i,salt)>.7 and u<.85:
			_poly(r,[a-n*ta*.55,a-d*5-n*(ta+6),b-n*tb*.55],_c(Color(.2,.5,.51),alpha))
		if i%4==0: _grain(r,a+n*(ta+3)+Vector2(0,age*13),_c(LIT,alpha*.5))
	_oval(r,p+Vector2(0,-4),width*.7,width*.46,_c(Color(.1,.38,.42),alpha),angle)

static func _pearl(r, w: Dictionary, age: float, alpha: float) -> void:
	var d := Vector2.from_angle(w.ang)
	var n := d.orthogonal()
	var radius: float = w.r
	var p: Vector2 = w.pos+Vector2(0,-10-sin(age*5)*2)
	_oval(r,w.pos,radius,radius*.62,_c(DEEP,alpha*.34))
	_oval(r,p,radius*.77,radius*.72,_c(Color(.04,.22,.29),alpha))
	_oval(r,p-Vector2(3,3),radius*.64,radius*.58,_c(Color(.17,.51,.54),alpha))
	_oval(r,p-Vector2(6,6),radius*.37,radius*.31,_c(Color(.51,.8,.73),alpha))
	# Soft paired mantle lobes trail behind the sphere, never form an arrowhead.
	for side in [-1.0,1.0]:
		var lobe: Vector2 = p-d*radius*.55+n*side*radius*.4
		_oval(r,lobe,radius*.38,radius*.2,_c(Color(.25,.56,.54),alpha*.8),w.ang+side*.3)
		_band(r,lobe-d*radius*.25,lobe,1,2,_c(Color(.58,.77,.65),alpha))
	_oval(r,p+d*radius*.25-Vector2(3,5),4,3,_c(FOAM,alpha))
	for i in 6:
		var drag: float = fmod(age*40+i*8,35)
		_grain(r,p-d*(radius*.6+drag)+n*(_n(i)*2-1)*radius*.35,_c(LIT,alpha*(1-drag/40)))

static func _choir(r, w: Dictionary, age: float, alpha: float) -> void:
	var d := Vector2.from_angle(w.ang)
	var n := d.orthogonal()
	var count: int = ceili(w.len/10)
	for i in count:
		var u: float = float(i)/count
		var v: float = float(i+1)/count
		var a: Vector2 = w.pos+d*w.len*u
		var b: Vector2 = w.pos+d*w.len*v
		var wave_a: float = sin(u*26-age*30)*w.wid*.22
		var wave_b: float = sin(v*26-age*30)*w.wid*.22
		_band(r,a,b,w.wid,w.wid,_c(DEEP,alpha*.7))
		_band(r,a+n*wave_a,b+n*wave_b,w.wid*.72,w.wid*.72,_c(SEA,alpha))
		_band(r,a+n*wave_a-n*3,b+n*wave_b-n*3,w.wid*.36,w.wid*.36,_c(Color(.38,.72,.66),alpha))
		if _n(i,4)>.23:
			_band(r,a+n*wave_a-n*4,b+n*wave_b-n*4,1.3,1.3,_c(Color(1.05,1.07,.85),alpha))
		if i%4==0:
			var side: float = -1.0 if _n(i)> .5 else 1.0
			_poly(r,[a+n*w.wid*.5*side,a-d*10+n*w.wid*.95*side,b+n*w.wid*.5*side],_c(LIT,alpha*.8))
	# Source flower opens around a small bright pearl; all waves visibly originate here.
	for i in 5:
		var a: float = TAU*i/5
		var v := Vector2.from_angle(a)
		_oval(r,w.pos+v*12,10,5,_c(Color(.48,.7,.61),alpha),a)
	_oval(r,w.pos,6,6,_c(FOAM,alpha))

static func _wave(r, w: Dictionary, age: float, alpha: float) -> void:
	var d := Vector2.from_angle(w.ang)
	var f: Vector2 = w.get("velocity",d.orthogonal()).normalized()
	var count: int = maxi(2,ceili(w.len/9))
	# One continuous rolling face with irregular broken foam; no repeated bead cells.
	for i in count:
		var u: float = float(i)/count
		var v: float = float(i+1)/count
		var a: Vector2 = w.pos+d*w.len*u
		var b: Vector2 = w.pos+d*w.len*v
		var ca: float = sin(u*w.len*.035+age*6)*3+sin(u*w.len*.11-age*4)*2
		var cb: float = sin(v*w.len*.035+age*6)*3+sin(v*w.len*.11-age*4)*2
		_poly(r,[a-f*w.wid,b-f*w.wid,b+f*w.wid,a+f*w.wid],_c(DEEP,alpha*.65))
		_poly(r,[a-f*w.wid*.8,b-f*w.wid*.8,b+f*(w.wid*.65+cb),a+f*(w.wid*.65+ca)],_c(Color(.06,.32,.39),alpha))
		_poly(r,[a-f*2,b-f*2,b+f*(w.wid*.65+cb),a+f*(w.wid*.65+ca)],_c(Color(.14,.52,.57),alpha))
		_poly(r,[a+f*(w.wid*.3+ca),b+f*(w.wid*.3+cb),b+f*(w.wid*.65+cb),a+f*(w.wid*.65+ca)],_c(Color(.28,.65,.65),alpha))
		if _n(i/3,3)>.28:
			_band(r,a+f*(w.wid*.65+ca),b+f*(w.wid*.65+cb),1.5,2.5,_c(FOAM,alpha*.85))
		if _n(i,4)>.55:
			_grain(r,a+f*(w.wid*.7+ca),_c(FOAM,alpha))
			_grain(r,a-f*(w.wid*.5),_c(LIT,alpha*.6))

static func _cone_water(r, w: Dictionary, age: float, alpha: float) -> void:
	for i in 24:
		var a: float = w.ang-w.half+2*w.half*i/24
		var b: float = w.ang-w.half+2*w.half*(i+1)/24
		var va := Vector2.from_angle(a)
		var vb := Vector2.from_angle(b)
		_poly(r,[w.pos,w.pos+va*w.r,w.pos+vb*w.r],_c(SEA,alpha*.13))
		var inset: float = 7+_n(i,5)*9
		_band(r,w.pos+va*(w.r-inset),w.pos+vb*(w.r-inset),2,2,_c(LIT,alpha*.7))

static func _surge(r, w: Dictionary, gy: float, age: float, alpha: float) -> void:
	var inner: float = float(w.get("inner_r",0))
	var outer: float = w.r
	var count: int = ceili(outer*TAU/19)
	for i in count:
		var a: float = TAU*i/count
		var b: float = TAU*(i+1)/count
		var va := Vector2(cos(a),sin(a)*gy)
		var vb := Vector2(cos(b),sin(b)*gy)
		_poly(r,[w.pos+va*inner,w.pos+va*outer,w.pos+vb*outer,w.pos+vb*inner],_c(SEA,alpha*.23))
		# Short turbulent ridges have independent radial phases: they cannot join into rings.
		for ridge in 3:
			var cell: int = i / 4
			if _n(cell,ridge+8)<.3: continue
			var phase: float = _n(cell,ridge+31)
			var travel: float = fmod(age*42+phase*200+ridge*37,maxf(10,outer-inner-46))
			var radius: float = inner+21+travel
			var width: float = 3+_n(i,ridge)*10
			var local: float = float(i%4)/4
			var ra: float = radius+sin(local*PI)*7+(_n(i,ridge+48)-.5)*7
			var rb: float = radius+sin((local+.25)*PI)*7+(_n(i+1,ridge+48)-.5)*7
			var ca: Vector2 = w.pos+va*ra
			var cb: Vector2 = w.pos+vb*rb
			_band(r,ca,cb,width,width*.7,_c(Color(.04,.24,.32),alpha*.9))
			_band(r,ca-va*3,cb-vb*3,width*.6,width*.35,_c(Color(.12,.47,.53),alpha*.85))
			if _n(i,ridge+21)>.42:
				_band(r,ca-va*5,cb-vb*5,1.5,1.5,_c(LIT,alpha*.85))
			if _n(i,ridge+12)>.4:
				_grain(r,ca-va*5,_c(FOAM,alpha))
				_grain(r,ca-va*8+Vector2(3,2),_c(FOAM,alpha*.8))
