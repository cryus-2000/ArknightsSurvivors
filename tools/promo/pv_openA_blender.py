# -*- coding: utf-8 -*-
"""片头 A · Blender 抽象氛围版（11-09 整夜，用户：回到 Blender 那种「虚」的感觉；颜色按官方水月 PV 取色，淡蓝偏好）。
battle2 第 70–77 小节（7 小节，690 帧 @60）在 Blender 里渲染，77–78 的闪白 + logo 在 pv_openA_post.py 里合成。
  A 0–2 小节    水母伞底微距，冷淡蓝逆光
  B 2–4 小节    灰雾里几根淡蓝丝线穿过景深，光点沿线游走
  C 4–5.5 小节  仰望：一道冷光从上方落下，雾里悬着海嗣巨影（带棱球形头 + 细长触手，只露轮廓）
  D 5.5–7 小节  一点淡蓝光在中央，海嗣从雾里朝它涌来（近大虚、远小淡）
色：近黑 / 灰藏青雾，高光只用淡蓝白（#b8d4ec / #dcecf8），低饱和、远处融进雾；不加大 bloom。

  D:/blender/blender-4.5.15-windows-x64/blender.exe -b --python tools/promo/pv_openA_blender.py -- <输出帧目录> [起帧 止帧 | 帧,帧,…] [--preview]
"""
import math, os, random, sys, time
import bpy
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
PREVIEW = "--preview" in argv
argv = [a for a in argv if a != "--preview"]
OUT = argv[0]
STILLS = [int(x) for x in argv[1].split(",")] if len(argv) > 1 and "," in argv[1] else None
F0 = int(argv[1]) if len(argv) > 1 and not STILLS else 0
F1 = int(argv[2]) if len(argv) > 2 else None

FPS = 60
BAR = 4 * 60 / 145.99
NF = int(round(7 * BAR * FPS))          # 690
S1, S2, S3 = int(round(2 * BAR * FPS)), int(round(4 * BAR * FPS)), int(round(5.5 * BAR * FPS))
ICE = (0.62, 0.78, 0.95, 1)              # 淡蓝高光（线性空间，AgX 后约 #b8d4ec）
ICE_W = (0.80, 0.88, 0.97, 1)


def ease(x):
    x = min(1.0, max(0.0, x)); return 1 - (1 - x) ** 3


def ease_io(x):
    x = min(1.0, max(0.0, x)); return x * x * (3 - 2 * x)


bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
sc.render.fps = FPS
sc.render.resolution_x, sc.render.resolution_y = 1920, 1080
sc.render.resolution_percentage = 50 if PREVIEW else 100
for eng in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE"):
    try:
        sc.render.engine = eng; break
    except TypeError:
        pass
ee = sc.eevee
ee.taa_render_samples = 12 if PREVIEW else 24
for k, v in (("volumetric_tile_size", "4" if PREVIEW else "2"), ("volumetric_samples", 32 if PREVIEW else 48), ("use_volumetric_shadows", True),
             ("volumetric_end", 60.0), ("volumetric_start", 0.1), ("use_shadows", True), ("use_raytracing", False)):
    try:
        setattr(ee, k, v)
    except Exception as e:
        print("eevee skip", k, e)
sc.render.use_motion_blur = not PREVIEW
sc.render.motion_blur_shutter = 0.3
sc.view_settings.view_transform = "AgX"
try:
    sc.view_settings.look = "AgX - Base Contrast"
except Exception:
    pass
sc.render.image_settings.file_format = "PNG"


def mat(name):
    m = bpy.data.materials.new(name); m.use_nodes = True
    n, l = m.node_tree.nodes, m.node_tree.links; n.clear()
    o = n.new("ShaderNodeOutputMaterial"); return m, n, l, o


def emissive(name, col, k, blend=False):
    m, n, l, o = mat(name)
    em = n.new("ShaderNodeEmission"); em.inputs["Color"].default_value = col; em.inputs["Strength"].default_value = k
    if blend:
        tr = n.new("ShaderNodeBsdfTransparent"); ad = n.new("ShaderNodeAddShader")
        l.new(tr.outputs[0], ad.inputs[0]); l.new(em.outputs[0], ad.inputs[1]); l.new(ad.outputs[0], o.inputs["Surface"])
        try:
            m.surface_render_method = "BLENDED"
        except Exception:
            pass
    else:
        l.new(em.outputs[0], o.inputs["Surface"])
    return m


# ---------------------------------------------------------------- 深海：灰藏青雾（远处融进雾色，不是死黑）
world = bpy.data.worlds.new("deep"); sc.world = world; world.use_nodes = True
wn, wl = world.node_tree.nodes, world.node_tree.links; wn.clear()
wout = wn.new("ShaderNodeOutputWorld"); wbg = wn.new("ShaderNodeBackground")
wbg.inputs["Color"].default_value = (0.006, 0.009, 0.014, 1)
wl.new(wbg.outputs[0], wout.inputs["Surface"])
vol = wn.new("ShaderNodeVolumePrincipled")
vol.inputs["Color"].default_value = (0.7, 0.8, 0.9, 1)
vol.inputs["Density"].default_value = 0.045
vol.inputs["Anisotropy"].default_value = 0.55
vol.inputs["Emission Color"].default_value = (0.05, 0.07, 0.10, 1)
vol.inputs["Emission Strength"].default_value = 0.010
wl.new(vol.outputs[0], wout.inputs["Volume"])


def shaft(loc, aim, energy, size_deg, col=(0.72, 0.84, 1.0)):
    bpy.ops.object.light_add(type="SPOT", location=loc)
    s = bpy.context.object
    s.data.energy = energy; s.data.spot_size = math.radians(size_deg); s.data.spot_blend = 0.7
    s.data.color = col; s.data.shadow_soft_size = 0.4
    try:
        s.data.volume_factor = 3.0
    except Exception:
        pass
    s.rotation_euler = (Vector(aim) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
    return s


# ================================================================= A 水母微距（原点）
def jelly(loc, r, seed, detail=True, k_em=1.0):
    rr = random.Random(seed)
    root = bpy.data.objects.new("jelly", None); sc.collection.objects.link(root); root.location = loc
    bpy.ops.mesh.primitive_uv_sphere_add(radius=r, segments=64, ring_count=32)
    bell = bpy.context.object
    bpy.ops.object.mode_set(mode="EDIT"); bpy.ops.mesh.select_all(action="DESELECT"); bpy.ops.object.mode_set(mode="OBJECT")
    for v in bell.data.vertices:
        v.select = v.co.z < -0.05 * r
    bpy.ops.object.mode_set(mode="EDIT"); bpy.ops.mesh.delete(type="VERT"); bpy.ops.object.mode_set(mode="OBJECT")
    bpy.ops.object.shade_smooth(); bell.scale = (1, 1, 0.62)
    m, n, l, o = mat("bell")
    lw = n.new("ShaderNodeLayerWeight"); lw.inputs["Blend"].default_value = 0.35
    tc = n.new("ShaderNodeTexCoord"); sp = n.new("ShaderNodeSeparateXYZ"); l.new(tc.outputs["Object"], sp.inputs[0])
    at = n.new("ShaderNodeMath"); at.operation = "ARCTAN2"; l.new(sp.outputs["Y"], at.inputs[0]); l.new(sp.outputs["X"], at.inputs[1])
    mu = n.new("ShaderNodeMath"); mu.operation = "MULTIPLY"; mu.inputs[1].default_value = 8.0; l.new(at.outputs[0], mu.inputs[0])
    si = n.new("ShaderNodeMath"); si.operation = "SINE"; l.new(mu.outputs[0], si.inputs[0])
    ab = n.new("ShaderNodeMath"); ab.operation = "ABSOLUTE"; l.new(si.outputs[0], ab.inputs[0])
    pw = n.new("ShaderNodeMath"); pw.operation = "POWER"; pw.inputs[1].default_value = 24.0; l.new(ab.outputs[0], pw.inputs[0])
    k1 = n.new("ShaderNodeMath"); k1.operation = "MULTIPLY"; k1.inputs[1].default_value = 1.4 * k_em; l.new(lw.outputs["Facing"], k1.inputs[0])
    k2 = n.new("ShaderNodeMath"); k2.operation = "MULTIPLY"; k2.inputs[1].default_value = 0.6 * k_em; l.new(pw.outputs[0], k2.inputs[0])
    ks = n.new("ShaderNodeMath"); ks.operation = "ADD"; l.new(k1.outputs[0], ks.inputs[0]); l.new(k2.outputs[0], ks.inputs[1])
    em = n.new("ShaderNodeEmission"); em.inputs["Color"].default_value = ICE; l.new(ks.outputs[0], em.inputs["Strength"])
    tr = n.new("ShaderNodeBsdfTransparent"); tr.inputs["Color"].default_value = (0.9, 0.94, 1.0, 1)
    ad = n.new("ShaderNodeAddShader"); l.new(tr.outputs[0], ad.inputs[0]); l.new(em.outputs[0], ad.inputs[1]); l.new(ad.outputs[0], o.inputs["Surface"])
    try:
        m.surface_render_method = "BLENDED"
    except Exception:
        pass
    bell.data.materials.append(m); bell.parent = root
    dot_m = emissive("dot", ICE_W, 6.0 * k_em)
    tent_m = emissive("tent", ICE, 0.5 * k_em, blend=True)
    arm_m = emissive("arm", ICE, 0.4 * k_em, blend=True)
    if detail:
        a = 0.0
        while a < 6.2:
            a += rr.uniform(0.06, 0.38)
            bpy.ops.mesh.primitive_ico_sphere_add(radius=r * rr.uniform(0.005, 0.013), subdivisions=1, location=(math.cos(a) * r * 0.99, math.sin(a) * r * 0.99, -0.03 * r))
            d = bpy.context.object; d.data.materials.append(dot_m); d.parent = root
    for i in range(28 if detail else 10):
        cu = bpy.data.curves.new("t", "CURVE"); cu.dimensions = "3D"; cu.bevel_depth = r * rr.uniform(0.0012, 0.003); cu.bevel_resolution = 1
        spl = cu.splines.new("BEZIER"); spl.bezier_points.add(5)
        a = rr.uniform(0, 6.283); L = r * rr.uniform(3.0, 7.0)
        for j, bp in enumerate(spl.bezier_points):
            t = j / 5
            bp.co = (math.cos(a) * r * 0.95 * (1 - 0.3 * t) + r * 0.25 * math.sin(j * 1.3 + i), math.sin(a) * r * 0.95 * (1 - 0.3 * t) + r * 0.2 * math.cos(j * 1.1 + i), -0.04 * r - L * t)
            bp.handle_left_type = bp.handle_right_type = "AUTO"
        ob = bpy.data.objects.new("t", cu); sc.collection.objects.link(ob); cu.materials.append(tent_m); ob.parent = root
    for i in range(4 if detail else 0):
        cu = bpy.data.curves.new("arm", "CURVE"); cu.dimensions = "3D"; cu.extrude = r * 0.09
        spl = cu.splines.new("BEZIER"); spl.bezier_points.add(6)
        a = i / 4 * 6.283 + 0.4
        for j, bp in enumerate(spl.bezier_points):
            t = j / 6
            bp.co = (math.cos(a) * r * 0.15 + r * 0.18 * math.sin(t * 5 + i), math.sin(a) * r * 0.15 + r * 0.18 * math.cos(t * 4 + i), -0.1 * r - r * 2.4 * t)
            bp.tilt = t * 9 + i; bp.handle_left_type = bp.handle_right_type = "AUTO"
        ob = bpy.data.objects.new("arm", cu); sc.collection.objects.link(ob); cu.materials.append(arm_m); ob.parent = root
    return root, bell


hero_j, hero_bell = jelly((0, 0, 0), 0.55, 1)
bg_j = []
rj = random.Random(9)
for k in range(8):
    j, b = jelly((rj.uniform(-6, 6), rj.uniform(3, 12), rj.uniform(-3, 4)), rj.uniform(0.18, 0.35), 20 + k, detail=False, k_em=0.5)
    bg_j.append((j, b, rj.uniform(0, 6.28)))
shaft((-1.5, -1.0, 7.0), (0.3, 0.6, 0.0), 900, 16)
for f in range(0, S1 + 6, 4):
    t = f / FPS
    s = 1 + 0.09 * math.sin(t * 2.6)
    hero_bell.scale = (s, s, 0.62 / s ** 1.3); hero_bell.keyframe_insert("scale", frame=f)
    hero_j.location = (0, 0, 0.12 * t)
    hero_j.rotation_euler = (math.radians(4 * math.sin(t * 0.9)), 0, math.radians(6 * t))
    hero_j.keyframe_insert("location", frame=f); hero_j.keyframe_insert("rotation_euler", frame=f)
for j, b, ph in bg_j:
    p0 = Vector(j.location)
    for f in range(0, S1 + 12, 12):
        t = f / FPS
        j.location = p0 + Vector((0, 0, 0.1 * t)); s = 1 + 0.08 * math.sin(t * 2.3 + ph); b.scale = (s, s, 0.62 / s)
        j.keyframe_insert("location", frame=f); b.keyframe_insert("scale", frame=f)

# ================================================================= B 发光丝线（y=40）
BY = 40.0
fil_m = emissive("fil", ICE, 1.6)
fil_dim = emissive("fil_dim", (0.45, 0.58, 0.75, 1), 0.35)
spark_m = emissive("spark", ICE_W, 18.0)
rf = random.Random(4)
for i in range(22):
    main = i < 3
    cu = bpy.data.curves.new("fil", "CURVE"); cu.dimensions = "3D"
    cu.bevel_depth = rf.uniform(0.005, 0.008) if main else rf.uniform(0.0015, 0.004); cu.bevel_resolution = 1
    spl = cu.splines.new("BEZIER"); spl.bezier_points.add(7)
    z0, y0 = (rf.uniform(-0.6, 0.6), BY + 0.3 + rf.uniform(-0.15, 0.15)) if main else (rf.uniform(-2.5, 2.5), BY + rf.uniform(3.5, 12.0))
    x0 = rf.uniform(-9, 3); ph = rf.uniform(0, 6.28)
    for j, bp in enumerate(spl.bezier_points):
        t = j / 7
        bp.co = (x0 + t * rf.uniform(6, 10), y0 + 0.6 * math.sin(t * 4 + ph), z0 + 0.5 * math.sin(t * 3 + ph * 1.7))
        bp.handle_left_type = bp.handle_right_type = "AUTO"
    ob = bpy.data.objects.new("fil", cu); sc.collection.objects.link(ob); cu.materials.append(fil_m if main else fil_dim)
    for f in (S1 - 2, S2 + 2):
        ob.location = (0, 0, 0) if f == S1 - 2 else (rf.uniform(-0.5, 0.5), 0, rf.uniform(-0.3, 0.3)); ob.keyframe_insert("location", frame=f)
    if main or i % 6 == 0:
        bpy.ops.mesh.primitive_ico_sphere_add(radius=0.016, subdivisions=2)
        sp = bpy.context.object; sp.data.materials.append(spark_m)
        c = sp.constraints.new("FOLLOW_PATH"); c.target = ob; c.use_fixed_location = True
        c.offset_factor = 0.0; c.keyframe_insert("offset_factor", frame=S1 - 2)
        c.offset_factor = 1.0; c.keyframe_insert("offset_factor", frame=S2 + rf.randint(-60, 60))
shaft((-2.0, BY - 1.0, 7.0), (1.0, BY + 1.0, -1.0), 1100, 22)


# ================================================================= 海嗣（带棱球形头 + 细长触手，暗色、只靠逆光勾轮廓）
def seaborn_mats():
    m, n, l, o = mat("sb_head")
    b = n.new("ShaderNodeBsdfPrincipled")
    b.inputs["Base Color"].default_value = (0.32, 0.36, 0.42, 1); b.inputs["Roughness"].default_value = 0.45
    lw = n.new("ShaderNodeLayerWeight"); lw.inputs["Blend"].default_value = 0.2
    em = n.new("ShaderNodeEmission"); em.inputs["Color"].default_value = ICE
    mu = n.new("ShaderNodeMath"); mu.operation = "MULTIPLY"; mu.inputs[1].default_value = 0.35; l.new(lw.outputs["Fresnel"], mu.inputs[0]); l.new(mu.outputs[0], em.inputs["Strength"])
    ad = n.new("ShaderNodeAddShader"); l.new(b.outputs[0], ad.inputs[0]); l.new(em.outputs[0], ad.inputs[1]); l.new(ad.outputs[0], o.inputs["Surface"])
    m2, n2, l2, o2 = mat("sb_tent")
    b2 = n2.new("ShaderNodeBsdfPrincipled"); b2.inputs["Base Color"].default_value = (0.05, 0.06, 0.08, 1); b2.inputs["Roughness"].default_value = 0.35
    l2.new(b2.outputs[0], o2.inputs["Surface"])
    return m, m2


SB_HEAD, SB_TENT = seaborn_mats()


def seaborn(loc, r, seed):
    rr = random.Random(seed)
    root = bpy.data.objects.new("sb", None); sc.collection.objects.link(root); root.location = loc
    bpy.ops.mesh.primitive_uv_sphere_add(radius=r, segments=32, ring_count=16)
    h = bpy.context.object
    for v in h.data.vertices:   # 竖棱：按经度起伏，下半收口
        a = math.atan2(v.co.y, v.co.x)
        k = 1 + 0.16 * abs(math.sin(a * 5)) ** 0.6
        v.co.x *= k; v.co.y *= k
        if v.co.z < 0:
            v.co.z *= 0.75
    bpy.ops.object.shade_smooth(); h.scale = (1, 1, 1.12)
    h.data.materials.append(SB_HEAD); h.parent = root
    for i in range(9):
        cu = bpy.data.curves.new("st", "CURVE"); cu.dimensions = "3D"; cu.bevel_depth = r * rr.uniform(0.04, 0.07); cu.bevel_resolution = 2
        spl = cu.splines.new("BEZIER"); spl.bezier_points.add(5)
        a = i / 9 * 6.283 + rr.uniform(-0.2, 0.2); L = r * rr.uniform(3.5, 6.0)
        for j, bp in enumerate(spl.bezier_points):
            t = j / 5
            bp.co = (math.cos(a) * r * (0.5 + 0.5 * t) + r * 0.3 * math.sin(t * 4 + i), math.sin(a) * r * (0.5 + 0.5 * t) + r * 0.3 * math.cos(t * 3 + i), -0.6 * r - L * t)
            bp.radius = 1.0 - 0.85 * t
            bp.handle_left_type = bp.handle_right_type = "AUTO"
        ob = bpy.data.objects.new("st", cu); sc.collection.objects.link(ob); cu.materials.append(SB_TENT); ob.parent = root
    return root


# ================================================================= C 仰望冷光 + 巨影（y=120）
CY = 120.0
giants = []
for k, (x, y, z, r) in enumerate(((-4.5, CY + 20, 8, 2.0), (5.0, CY + 24, 11, 2.6), (-1.0, CY + 34, 15, 3.0), (-9, CY + 30, 5, 1.8), (10, CY + 36, 4, 2.2))):
    g = seaborn((x, y, z), r, 50 + k); g.rotation_euler = (math.radians(random.Random(k).uniform(-10, 10)), 0, random.Random(k + 9).uniform(0, 6.28))
    giants.append((g, Vector((x, y, z))))
shaft((1.5, CY + 16, 30), (0.8, CY + 14, -10), 30000, 3.5, (0.78, 0.88, 1.0))
bpy.context.object.data.volume_factor = 8.0
for g, p0 in giants:
    for f in range(S2 - 6, S3 + 12, 12):
        t = f / FPS
        g.location = p0 + Vector((0, 0, 0.15 * math.sin(t * 0.6 + p0.x)))
        g.keyframe_insert("location", frame=f)

# ================================================================= D 一点光 + 海嗣涌来（y=200）
DY = 200.0
bpy.ops.mesh.primitive_uv_sphere_add(radius=0.06, segments=16, ring_count=8, location=(0, DY, 0))
core = bpy.context.object; core.data.materials.append(emissive("core", ICE_W, 40.0))
bpy.ops.object.light_add(type="POINT", location=(0, DY, 0))
pl = bpy.context.object; pl.data.energy = 120; pl.data.color = (0.75, 0.86, 1.0); pl.data.shadow_soft_size = 0.2
try:
    pl.data.volume_factor = 1.5
except Exception:
    pass
rs = random.Random(77)
swarm = []
for k in range(70):
    a = rs.uniform(0, 6.283); el = rs.uniform(-0.9, 0.9); d0 = rs.uniform(7, 26)
    p0 = Vector((math.cos(a) * math.cos(el) * d0, DY + math.sin(a) * math.cos(el) * d0 * 0.6 + rs.uniform(-2, 8), math.sin(el) * d0 * 0.5))
    if p0.y < DY - 4.0 or (p0 - Vector((0, DY - 9, 0))).length < 6.0:   # 别贴到镜头前挡满画面
        continue
    s = seaborn(p0, rs.uniform(0.35, 0.8), 200 + k)
    swarm.append((s, p0, rs.uniform(0.25, 0.5)))
for s, p0, sp in swarm:
    tgt_ = Vector((0, DY, 0))
    s.rotation_euler = (tgt_ - p0).to_track_quat("Z", "Y").to_euler()
    for f in range(S3 - 6, NF + 12, 12):
        u = ease_io((f - S3) / (NF - S3))
        s.location = p0 + (tgt_ - p0) * (sp * u)
        s.keyframe_insert("location", frame=f)
for f in range(S3 - 6, NF + 6, 3):   # 光在闪
    t = f / FPS
    pl.data.energy = 120 * (0.75 + 0.25 * math.sin(t * 13) * math.sin(t * 5.3))
    pl.data.keyframe_insert("energy", frame=f)

# ---------------------------------------------------------------- 悬浮颗粒
mote_m = emissive("mote", ICE_W, 2.0)
bpy.ops.mesh.primitive_ico_sphere_add(radius=0.006, subdivisions=1, location=(0, 0, -90))
mote = bpy.context.object; mote.data.materials.append(mote_m)
for cy, sz in ((0.0, 14), (BY, 14), (CY, 30), (DY, 34)):
    bpy.ops.mesh.primitive_cube_add(size=1, location=(0, cy + 2, 0))
    e = bpy.context.object; e.scale = (sz, sz, sz * 0.7)
    ps = e.modifiers.new("m", "PARTICLE_SYSTEM").particle_system.settings
    ps.count = 1500 if not PREVIEW else 600; ps.frame_start = -900; ps.frame_end = NF; ps.lifetime = 2000
    ps.emit_from = "VOLUME"; ps.normal_factor = 0; ps.factor_random = 0.04; ps.effector_weights.gravity = -0.006
    ps.render_type = "OBJECT"; ps.instance_object = mote; ps.size_random = 0.8
    e.show_instancer_for_render = False; e.visible_camera = False; e.visible_shadow = False

# ---------------------------------------------------------------- 镜头
cam_d = bpy.data.cameras.new("cam"); cam_d.sensor_fit = "VERTICAL"; cam_d.angle_y = math.radians(30)
cam_d.dof.use_dof = True; cam_d.dof.aperture_fstop = 1.4
cam = bpy.data.objects.new("cam", cam_d); sc.collection.objects.link(cam); sc.camera = cam
tgt = bpy.data.objects.new("tgt", None); sc.collection.objects.link(tgt)
tc_ = cam.constraints.new("TRACK_TO"); tc_.target = tgt; tc_.track_axis = "TRACK_NEGATIVE_Z"; tc_.up_axis = "UP_Y"
for f in range(NF):
    t = f / FPS
    if f < S1:
        u = ease_io(t / (2 * BAR)); a = math.radians(-100 + 35 * u); rad = 3.1 - 0.4 * u; jz = 0.12 * t
        cl = (math.cos(a) * rad, math.sin(a) * rad, jz - 1.15 + 0.2 * u); tl = (0, 0, jz - 0.15); fd = math.dist(cl, tl) - 0.1
    elif f < S2:
        u = ease_io((t - 2 * BAR) / (2 * BAR))
        cl = (-5.5 + 6.0 * u, BY - 3.2, 0.3 - 0.2 * u); tl = (-4.0 + 6.0 * u, BY + 0.5, 0.0); fd = 3.4
    elif f < S3:   # 仰望：极慢上仰，焦点在巨影
        u = ease_io((t - 4 * BAR) / (1.5 * BAR))
        cl = (0.0, CY - 2.0, -2.0); tl = (0.3, CY + 18, 4 + 5 * u); fd = 22.0
    else:          # 一点光：缓推
        u = ease((t - 5.5 * BAR) / (1.5 * BAR))
        cl = (0.0, DY - 12.0 + 4.0 * u, 0.4 - 0.3 * u); tl = (0.0, DY, 0.0); fd = math.dist(cl, tl)
    sc.view_settings.exposure = 0.0 if f < S2 else 0.55
    sc.view_settings.keyframe_insert("exposure", frame=f)
    cam.location, tgt.location = cl, tl
    cam_d.dof.focus_distance = fd
    cam_d.dof.aperture_fstop = 4.0 if S2 <= f < S3 else 1.4
    cam.keyframe_insert("location", frame=f); tgt.keyframe_insert("location", frame=f)
    cam_d.dof.keyframe_insert("focus_distance", frame=f); cam_d.dof.keyframe_insert("aperture_fstop", frame=f)
for a in bpy.data.actions:
    for fc in a.fcurves:
        for kp in fc.keyframe_points:
            kp.interpolation = "LINEAR"

# ---------------------------------------------------------------- 合成：极轻 glare（不要大光晕）
sc.use_nodes = True
cn, cl_ = sc.node_tree.nodes, sc.node_tree.links; cn.clear()
rl = cn.new("CompositorNodeRLayers"); gl_ = cn.new("CompositorNodeGlare")
try:
    gl_.glare_type = "BLOOM"
except Exception:
    gl_.glare_type = "FOG_GLOW"
for k, v in (("quality", "MEDIUM"), ("threshold", 1.2), ("size", 6), ("mix", -0.7)):
    try:
        setattr(gl_, k, v)
    except Exception:
        pass
for nm, v in (("Threshold", 1.2), ("Strength", 0.35), ("Size", 0.5)):
    try:
        gl_.inputs[nm].default_value = v
    except Exception:
        pass
co = cn.new("CompositorNodeComposite")
cl_.new(rl.outputs["Image"], gl_.inputs["Image"]); cl_.new(gl_.outputs["Image"], co.inputs["Image"])

os.makedirs(OUT, exist_ok=True)
sc.frame_start = F0; sc.frame_end = F1 if F1 is not None else NF - 1
print("PVA", sc.render.engine, sc.frame_start, sc.frame_end, NF, flush=True)
if STILLS:
    for f in STILLS:
        t0 = time.time(); sc.frame_set(f)
        sc.render.filepath = OUT.replace("\\", "/") + "/s%04d.png" % f
        bpy.ops.render.render(write_still=True)
        print("PVA still", f, "%.1f s" % (time.time() - t0), flush=True)
else:
    sc.render.filepath = OUT.replace("\\", "/") + "/f"
    bpy.ops.render.render(animation=True)
