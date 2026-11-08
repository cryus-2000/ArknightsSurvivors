# -*- coding: utf-8 -*-
"""PV 3D 开头 · 暗调微距版（11-08，对齐官方水月 PV 的水下镜头）：七成画面接近黑的深海军蓝，只有光束、水母、发光丝线亮；
单一主体微距、慢漂移、浅景深；只出现一张卡。EEVEE 渲染 + bloom + 色散（颗粒在 pv.py 里叠）。

  D:/blender/blender-4.5.15-windows-x64/blender.exe -b --python tools/promo/pv3d_deep.py -- <卡面目录> <输出帧目录> [起帧 止帧 | 帧,帧,…]

时长 = battle2 第 70–77 小节（7 小节 = 11.507 秒，60 帧 = 691 帧）：
  A 0–2 小节   水母微距：伞下仰拍、逆光，伞缘发光点、放射辐管、口腕薄带、极细触须；远处水母成光斑
  B 2–4 小节   黑暗里漂着的发光丝线（水月的触须意象），丝上有光点流动；镜头贴着横移
  C 4 小节起   重拍：斯卡蒂的招募卡从黑暗里转出，一道青色逆光勾边，冷光一闪；镜头推进，末 0.35 秒提亮到白切实机
三段放在不同位置（A 在原点、B 在 y=40、C 在 y=80），镜头按段跳切。
"""
import math, os, random, sys, time
import bpy
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
CARDS, OUT = argv[0], argv[1]
STILLS = [int(x) for x in argv[2].split(",")] if len(argv) > 2 and "," in argv[2] else None
F0 = int(argv[2]) if len(argv) > 2 and not STILLS else 0
F1 = int(argv[3]) if len(argv) > 3 else None

FPS = 60
BAR = 4 * 60 / 145.99
DUR = 7 * BAR
NF = int(round(DUR * FPS)) + 1
S1, S2 = int(2 * BAR * FPS), int(4 * BAR * FPS)
CYAN = (0.35, 0.85, 1.0, 1)


def ease(x):
    x = min(1.0, max(0.0, x))
    return 1 - (1 - x) ** 3


def ease_io(x):
    x = min(1.0, max(0.0, x))
    return x * x * (3 - 2 * x)


bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
sc.render.fps = FPS
sc.render.resolution_x, sc.render.resolution_y = 1920, 1080
for eng in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE"):
    try:
        sc.render.engine = eng
        break
    except TypeError:
        pass
ee = sc.eevee
ee.taa_render_samples = 40
for k, v in (("use_raytracing", True), ("volumetric_tile_size", "2"), ("volumetric_samples", 64), ("use_volumetric_shadows", True),
             ("volumetric_end", 40.0), ("volumetric_start", 0.1), ("use_shadows", True)):
    try:
        setattr(ee, k, v)
    except Exception as e:
        print("eevee skip", k, e)
sc.render.use_motion_blur = True
sc.render.motion_blur_shutter = 0.35
sc.view_settings.view_transform = "AgX"
try:
    sc.view_settings.look = "AgX - High Contrast"
except Exception:
    pass
sc.render.image_settings.file_format = "PNG"


def mat(name):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    n, l = m.node_tree.nodes, m.node_tree.links
    n.clear()
    o = n.new("ShaderNodeOutputMaterial")
    o.name = "out"
    return m, n, l, o


def emissive(name, col, k, blend=False):
    m, n, l, o = mat(name)
    em = n.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = col
    em.inputs["Strength"].default_value = k
    if blend:
        tr = n.new("ShaderNodeBsdfTransparent")
        ad = n.new("ShaderNodeAddShader")
        l.new(tr.outputs[0], ad.inputs[0]); l.new(em.outputs[0], ad.inputs[1]); l.new(ad.outputs[0], o.inputs["Surface"])
        try:
            m.surface_render_method = "BLENDED"
        except Exception:
            pass
    else:
        l.new(em.outputs[0], o.inputs["Surface"])
    return m


# ---------------------------------------------------------------- 深海：近黑的海军蓝 + 稀薄体积（只在光束里亮）
world = bpy.data.worlds.new("deep")
sc.world = world
world.use_nodes = True
wn, wl = world.node_tree.nodes, world.node_tree.links
wn.clear()
wout = wn.new("ShaderNodeOutputWorld")
wbg = wn.new("ShaderNodeBackground")
wbg.inputs["Color"].default_value = (0.0015, 0.005, 0.011, 1)
wl.new(wbg.outputs[0], wout.inputs["Surface"])
vol = wn.new("ShaderNodeVolumePrincipled")
vol.inputs["Color"].default_value = (0.3, 0.7, 0.9, 1)
vol.inputs["Density"].default_value = 0.06
vol.inputs["Anisotropy"].default_value = 0.6
wl.new(vol.outputs[0], wout.inputs["Volume"])


def shaft(loc, aim, energy, size_deg, col=(0.55, 0.9, 1.0)):
    """从上方斜打下来的一道光（聚光灯在体积里成光柱）"""
    bpy.ops.object.light_add(type="SPOT", location=loc)
    s = bpy.context.object
    s.data.energy = energy
    s.data.spot_size = math.radians(size_deg)
    s.data.spot_blend = 0.6
    s.data.color = col
    s.data.shadow_soft_size = 0.3
    try:
        s.data.volume_factor = 4.0
    except Exception:
        pass
    d = Vector(aim) - Vector(loc)
    s.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    return s


# ================================================================= A 水母微距（原点）
def jelly(loc, r, seed, detail=True):
    rr = random.Random(seed)
    root = bpy.data.objects.new("jelly", None)
    sc.collection.objects.link(root)
    root.location = loc
    # 伞：上半球，边缘按视角发光（菲涅尔）+ 放射辐管 + 半透明
    bpy.ops.mesh.primitive_uv_sphere_add(radius=r, segments=64, ring_count=32)
    bell = bpy.context.object
    bpy.ops.object.mode_set(mode="EDIT"); bpy.ops.mesh.select_all(action="DESELECT"); bpy.ops.object.mode_set(mode="OBJECT")
    for v in bell.data.vertices:
        v.select = v.co.z < -0.05 * r
    bpy.ops.object.mode_set(mode="EDIT"); bpy.ops.mesh.delete(type="VERT"); bpy.ops.object.mode_set(mode="OBJECT")
    bpy.ops.object.shade_smooth()
    bell.scale = (1, 1, 0.62)
    m, n, l, o = mat("bell")
    lw = n.new("ShaderNodeLayerWeight"); lw.inputs["Blend"].default_value = 0.3
    tc = n.new("ShaderNodeTexCoord"); sp = n.new("ShaderNodeSeparateXYZ"); l.new(tc.outputs["Object"], sp.inputs[0])
    at = n.new("ShaderNodeMath"); at.operation = "ARCTAN2"; l.new(sp.outputs["Y"], at.inputs[0]); l.new(sp.outputs["X"], at.inputs[1])
    mu = n.new("ShaderNodeMath"); mu.operation = "MULTIPLY"; mu.inputs[1].default_value = 8.0; l.new(at.outputs[0], mu.inputs[0])
    si = n.new("ShaderNodeMath"); si.operation = "SINE"; l.new(mu.outputs[0], si.inputs[0])
    pw = n.new("ShaderNodeMath"); pw.operation = "POWER"; pw.inputs[1].default_value = 24.0
    ab = n.new("ShaderNodeMath"); ab.operation = "ABSOLUTE"; l.new(si.outputs[0], ab.inputs[0]); l.new(ab.outputs[0], pw.inputs[0])   # 8 条细辐管
    k1 = n.new("ShaderNodeMath"); k1.operation = "MULTIPLY"; k1.inputs[1].default_value = 2.6; l.new(lw.outputs["Facing"], k1.inputs[0])
    k2 = n.new("ShaderNodeMath"); k2.operation = "MULTIPLY"; k2.inputs[1].default_value = 1.2; l.new(pw.outputs[0], k2.inputs[0])
    ks = n.new("ShaderNodeMath"); ks.operation = "ADD"; l.new(k1.outputs[0], ks.inputs[0]); l.new(k2.outputs[0], ks.inputs[1])
    em = n.new("ShaderNodeEmission"); em.inputs["Color"].default_value = CYAN; l.new(ks.outputs[0], em.inputs["Strength"])
    tr = n.new("ShaderNodeBsdfTransparent"); tr.inputs["Color"].default_value = (0.85, 0.95, 1.0, 1)
    ad = n.new("ShaderNodeAddShader"); l.new(tr.outputs[0], ad.inputs[0]); l.new(em.outputs[0], ad.inputs[1]); l.new(ad.outputs[0], o.inputs["Surface"])
    try:
        m.surface_render_method = "BLENDED"
    except Exception:
        pass
    bell.data.materials.append(m)
    bell.parent = root
    dot_m = emissive("dot", (0.6, 0.95, 1.0, 1), 14.0)
    tent_m = emissive("tent", (0.4, 0.85, 1.0, 1), 0.9, blend=True)
    arm_m = emissive("arm", (0.45, 0.8, 1.0, 1), 0.7, blend=True)
    if detail:   # 伞缘一圈发光点
        for i in range(40):
            a = i / 40 * 6.283
            bpy.ops.mesh.primitive_ico_sphere_add(radius=r * 0.012, subdivisions=1, location=(math.cos(a) * r * 0.99, math.sin(a) * r * 0.99, -0.03 * r))
            d = bpy.context.object
            d.data.materials.append(dot_m)
            d.parent = root
    # 触须：极细、很长、微卷
    for i in range(28 if detail else 10):
        cu = bpy.data.curves.new("t", "CURVE"); cu.dimensions = "3D"
        cu.bevel_depth = r * rr.uniform(0.0012, 0.003)
        cu.bevel_resolution = 1
        spl = cu.splines.new("BEZIER"); spl.bezier_points.add(5)
        a = rr.uniform(0, 6.283); L = r * rr.uniform(3.0, 7.0)
        for j, bp in enumerate(spl.bezier_points):
            t = j / 5
            bp.co = (math.cos(a) * r * 0.95 * (1 - 0.3 * t) + r * 0.25 * math.sin(j * 1.3 + i), math.sin(a) * r * 0.95 * (1 - 0.3 * t) + r * 0.2 * math.cos(j * 1.1 + i), -0.04 * r - L * t)
            bp.handle_left_type = bp.handle_right_type = "AUTO"
        ob = bpy.data.objects.new("t", cu); sc.collection.objects.link(ob); cu.materials.append(tent_m); ob.parent = root
    # 口腕：4 条扭转的薄带
    for i in range(4 if detail else 0):
        cu = bpy.data.curves.new("arm", "CURVE"); cu.dimensions = "3D"
        cu.extrude = r * 0.09
        spl = cu.splines.new("BEZIER"); spl.bezier_points.add(6)
        a = i / 4 * 6.283 + 0.4
        for j, bp in enumerate(spl.bezier_points):
            t = j / 6
            bp.co = (math.cos(a) * r * 0.15 + r * 0.18 * math.sin(t * 5 + i), math.sin(a) * r * 0.15 + r * 0.18 * math.cos(t * 4 + i), -0.1 * r - r * 2.4 * t)
            bp.tilt = t * 9 + i
            bp.handle_left_type = bp.handle_right_type = "AUTO"
        ob = bpy.data.objects.new("arm", cu); sc.collection.objects.link(ob); cu.materials.append(arm_m); ob.parent = root
    return root, bell


hero_j, hero_bell = jelly((0, 0, 0), 0.55, 1)
bg_j = []
rj = random.Random(9)
for k in range(9):   # 远处的水母（光斑）
    j, b = jelly((rj.uniform(-6, 6), rj.uniform(3, 12), rj.uniform(-3, 4)), rj.uniform(0.18, 0.35), 20 + k, detail=False)
    bg_j.append((j, b, rj.uniform(0, 6.28)))
shaft((-1.5, -1.0, 7.0), (0.3, 0.6, 0.0), 1400, 14)   # A 段：伞后上方斜下的一道光
for f in range(0, S1 + 4, 4):   # 伞一张一缩、缓缓上漂
    t = f / FPS
    s = 1 + 0.09 * math.sin(t * 2.6)
    hero_bell.scale = (s, s, 0.62 / s ** 1.3)
    hero_bell.keyframe_insert("scale", frame=f)
    hero_j.location = (0, 0, 0.12 * t)
    hero_j.rotation_euler = (math.radians(4 * math.sin(t * 0.9)), 0, math.radians(6 * t))
    hero_j.keyframe_insert("location", frame=f)
    hero_j.keyframe_insert("rotation_euler", frame=f)
for j, b, ph in bg_j:
    p0 = Vector(j.location)
    for f in range(0, NF + 6, 6):
        t = f / FPS
        j.location = p0 + Vector((0, 0, 0.1 * t))
        s = 1 + 0.08 * math.sin(t * 2.3 + ph)
        b.scale = (s, s, 0.62 / s)
        j.keyframe_insert("location", frame=f)
        b.keyframe_insert("scale", frame=f)

# ================================================================= B 发光丝线（y=40）
BY = 40.0
fil_m = emissive("fil", (0.4, 0.88, 1.0, 1), 2.2)
spark_m = emissive("spark", (0.8, 1.0, 1.0, 1), 60.0)
rf = random.Random(4)
fils = []
for i in range(30):
    cu = bpy.data.curves.new("fil", "CURVE"); cu.dimensions = "3D"
    cu.bevel_depth = rf.uniform(0.002, 0.007); cu.bevel_resolution = 1
    spl = cu.splines.new("BEZIER"); spl.bezier_points.add(7)
    z0, y0 = rf.uniform(-2.2, 2.2), BY + rf.uniform(-2.5, 4.0)
    x0 = rf.uniform(-9, 3)
    ph = rf.uniform(0, 6.28)
    for j, bp in enumerate(spl.bezier_points):
        t = j / 7
        bp.co = (x0 + t * rf.uniform(6, 10), y0 + 0.6 * math.sin(t * 4 + ph), z0 + 0.5 * math.sin(t * 3 + ph * 1.7))
        bp.handle_left_type = bp.handle_right_type = "AUTO"
    ob = bpy.data.objects.new("fil", cu); sc.collection.objects.link(ob); cu.materials.append(fil_m)
    fils.append(ob)
    for f in (S1 - 2, NF):   # 慢漂
        ob.location = (0, 0, 0) if f == S1 - 2 else (rf.uniform(-0.5, 0.5), 0, rf.uniform(-0.3, 0.3))
        ob.keyframe_insert("location", frame=f)
    if i % 3 == 0:   # 光点沿丝流动
        bpy.ops.mesh.primitive_ico_sphere_add(radius=0.018, subdivisions=2)
        sp = bpy.context.object
        sp.data.materials.append(spark_m)
        c = sp.constraints.new("FOLLOW_PATH"); c.target = ob; c.use_fixed_location = True
        c.offset_factor = 0.0; c.keyframe_insert("offset_factor", frame=S1 - 2)
        c.offset_factor = 1.0; c.keyframe_insert("offset_factor", frame=S2 + rf.randint(-60, 60))
shaft((-2.0, BY - 1.0, 7.0), (1.0, BY + 1.0, -1.0), 1800, 20)

# ================================================================= C 一张卡（y=80）
CY = 80.0
CW, CH, CT = 1.0, 1.405, 0.03
face = bpy.data.images.load(os.path.join(CARDS, "c5.png"))   # 斯卡蒂
back = bpy.data.images.load(os.path.join(CARDS, "_back.png"))
m_s, n_s, l_s, o_s = mat("silver")
bs = n_s.new("ShaderNodeBsdfPrincipled"); bs.inputs["Base Color"].default_value = (0.85, 0.9, 0.95, 1); bs.inputs["Metallic"].default_value = 1; bs.inputs["Roughness"].default_value = 0.15
l_s.new(bs.outputs[0], o_s.inputs["Surface"])


def face_mat(im, k):
    m, n, l, o = mat("face")
    b = n.new("ShaderNodeBsdfPrincipled")
    t = n.new("ShaderNodeTexImage"); t.image = im
    l.new(t.outputs[0], b.inputs["Base Color"]); l.new(t.outputs[0], b.inputs["Emission Color"])
    b.inputs["Emission Strength"].default_value = k
    b.inputs["Roughness"].default_value = 0.3
    b.inputs["Coat Weight"].default_value = 0.8; b.inputs["Coat Roughness"].default_value = 0.05
    l.new(b.outputs[0], o.inputs["Surface"])
    return m


bpy.ops.mesh.primitive_cube_add(size=1)
body = bpy.context.object
body.scale = (CW, CT, CH); bpy.ops.object.transform_apply(scale=True)
bv = body.modifiers.new("bv", "BEVEL"); bv.width = 0.012; bv.segments = 3
body.data.materials.append(m_s)
card = bpy.data.objects.new("card", None); sc.collection.objects.link(card)
body.parent = card
for side, mt in ((-1, face_mat(face, 0.9)), (1, face_mat(back, 0.15))):
    bpy.ops.mesh.primitive_plane_add(size=1)
    q = bpy.context.object
    q.scale = (CW * 0.955, CH * 0.97, 1)
    q.rotation_euler = (math.radians(90) * -side, 0, math.pi if side == 1 else 0)
    q.location = (0, side * (CT / 2 + 0.0015), 0)
    q.data.materials.append(mt); q.parent = card
for f in range(S2 - 2, NF):
    lt = f / FPS - 4 * BAR
    k = ease(lt / 0.5)
    card.location = (0.0, CY, 0.0 + 0.03 * math.sin(lt * 1.2))
    card.rotation_euler = (math.radians(6) * (1 - k), math.radians(-12) * (1 - k), math.radians(200) * (1 - k))   # 从背面转过来
    card.keyframe_insert("location", frame=f)
    card.keyframe_insert("rotation_euler", frame=f)
bpy.ops.object.light_add(type="AREA", location=(0, CY + 2.2, 1.6))   # 卡后上方的青色逆光：勾银边
rim = bpy.context.object
rim.data.energy = 260; rim.data.size = 1.2
try:
    rim.data.volume_factor = 0.05   # 逆光只勾卡边，不把背景水体打亮
except Exception:
    pass; rim.data.color = (0.45, 0.85, 1.0)
rim.rotation_euler = (Vector((0, CY, 0)) - Vector(rim.location)).to_track_quat("-Z", "Y").to_euler()
bpy.ops.object.light_add(type="POINT", location=(0.6, CY - 1.0, 0.5))
flash = bpy.context.object
flash.data.color = (0.7, 0.92, 1.0)
for k in range(10):   # 卡后面虚掉的丝线
    cu = bpy.data.curves.new("fc", "CURVE"); cu.dimensions = "3D"; cu.bevel_depth = 0.004
    spl = cu.splines.new("BEZIER"); spl.bezier_points.add(5)
    z0 = rf.uniform(-1.5, 1.5); y0 = CY + rf.uniform(2.5, 6)
    for j, bp in enumerate(spl.bezier_points):
        t = j / 5
        bp.co = (-5 + 10 * t, y0 + 0.4 * math.sin(t * 5 + k), z0 + 0.4 * math.sin(t * 4 + k))
        bp.handle_left_type = bp.handle_right_type = "AUTO"
    ob = bpy.data.objects.new("fc", cu); sc.collection.objects.link(ob); cu.materials.append(fil_m)

# ---------------------------------------------------------------- 悬浮颗粒（三段各一团）
mote_m = emissive("mote", (0.75, 0.95, 1.0, 1), 3.0)
bpy.ops.mesh.primitive_ico_sphere_add(radius=0.006, subdivisions=1, location=(0, 0, -90))
mote = bpy.context.object
mote.data.materials.append(mote_m)
for cy in (0.0, BY, CY):
    bpy.ops.mesh.primitive_cube_add(size=1, location=(0, cy + 2, 0))
    e = bpy.context.object
    e.scale = (14, 14, 9)
    ps = e.modifiers.new("m", "PARTICLE_SYSTEM").particle_system.settings
    ps.count = 2200; ps.frame_start = -900; ps.frame_end = NF; ps.lifetime = 2000
    ps.emit_from = "VOLUME"; ps.normal_factor = 0; ps.factor_random = 0.04
    ps.effector_weights.gravity = -0.006
    ps.render_type = "OBJECT"; ps.instance_object = mote; ps.size_random = 0.8
    e.show_instancer_for_render = False; e.visible_camera = False; e.visible_shadow = False

# ---------------------------------------------------------------- 镜头
cam_d = bpy.data.cameras.new("cam")
cam_d.sensor_fit = "VERTICAL"
cam_d.angle_y = math.radians(30)
cam_d.dof.use_dof = True
cam_d.dof.aperture_fstop = 1.2
cam = bpy.data.objects.new("cam", cam_d)
sc.collection.objects.link(cam)
sc.camera = cam
tgt = bpy.data.objects.new("tgt", None)
sc.collection.objects.link(tgt)
tc_ = cam.constraints.new("TRACK_TO"); tc_.target = tgt; tc_.track_axis = "TRACK_NEGATIVE_Z"; tc_.up_axis = "UP_Y"
for f in range(NF):
    t = f / FPS
    fl = 0.0
    if f < S1:   # 伞下仰拍，缓缓绕
        u = ease_io(t / (2 * BAR))
        a = math.radians(-100 + 35 * u)
        rad = 3.1 - 0.4 * u
        jz = 0.12 * t
        cl = (math.cos(a) * rad, math.sin(a) * rad, jz - 1.15 + 0.2 * u)
        tl = (0, 0, jz - 0.15)
        fd = math.dist(cl, tl) - 0.1
    elif f < S2:   # 贴着丝线横移
        u = ease_io((t - 2 * BAR) / (2 * BAR))
        cl = (-5.5 + 6.0 * u, BY - 3.2, 0.3 - 0.2 * u)
        tl = (-4.0 + 6.0 * u, BY + 0.5, 0.0)
        fd = 3.4
    else:
        lt = t - 4 * BAR
        pk = ease(max(0.0, lt - 0.4) / (3 * BAR - 0.4))
        cl = (0.15 - 0.15 * pk, CY - (3.6 - 1.55 * pk), 0.1)
        tl = (0, CY, 0.0)
        fd = math.dist(cl, tl)
        fl = max(0.0, 1 - lt / 0.45)
    if os.environ.get("PV3D_ENDCAM") == "1":   # 结尾卡机位：拉远，卡在左三分线，右侧留给标题（docs/327 T1 右三分线）
        cl, tl = (2.2, CY - 7.5, 0.6), (2.0, CY, 0.2)
        fd = math.dist(cl, (0, CY, 0))
        fl = 0.0
    cam.location, tgt.location = cl, tl
    cam_d.dof.focus_distance = fd
    flash.data.energy = 5 + 600 * fl
    for ob, dp in ((cam, "location"), (tgt, "location")):
        ob.keyframe_insert(dp, frame=f)
    cam_d.dof.keyframe_insert("focus_distance", frame=f)
    flash.data.keyframe_insert("energy", frame=f)
    sc.view_settings.exposure = 2.6 * ease((t - (DUR - 0.35)) / 0.35) if f >= S2 and os.environ.get("PV3D_ENDCAM") != "1" else 0.0
    sc.view_settings.keyframe_insert("exposure", frame=f)
for a in bpy.data.actions:
    for fc in a.fcurves:
        for kp in fc.keyframe_points:
            kp.interpolation = "LINEAR"

# ---------------------------------------------------------------- 合成：bloom + 色散
sc.use_nodes = True
cn, cl_ = sc.node_tree.nodes, sc.node_tree.links
cn.clear()
rl = cn.new("CompositorNodeRLayers")
gl_ = cn.new("CompositorNodeGlare")
try:
    gl_.glare_type = "BLOOM"
except Exception:
    gl_.glare_type = "FOG_GLOW"
for k, v in (("quality", "HIGH"), ("threshold", 0.6), ("size", 8), ("mix", -0.35)):
    try:
        setattr(gl_, k, v)
    except Exception:
        pass
for nm, v in (("Threshold", 0.6), ("Strength", 0.8), ("Size", 0.7)):
    try:
        gl_.inputs[nm].default_value = v
    except Exception:
        pass
ld = cn.new("CompositorNodeLensdist")
try:
    ld.inputs["Dispersion"].default_value = 0.02
except Exception:
    pass
co = cn.new("CompositorNodeComposite")
cl_.new(rl.outputs["Image"], gl_.inputs["Image"]); cl_.new(gl_.outputs["Image"], ld.inputs["Image"]); cl_.new(ld.outputs["Image"], co.inputs["Image"])

os.makedirs(OUT, exist_ok=True)
sc.frame_start = F0
sc.frame_end = F1 if F1 is not None else NF - 1
print("PV3D-DEEP", sc.render.engine, sc.frame_start, sc.frame_end, flush=True)
if STILLS:
    for f in STILLS:
        t0 = time.time()
        sc.frame_set(f)
        sc.render.filepath = OUT.replace("\\", "/") + "/s%04d.png" % f
        bpy.ops.render.render(write_still=True)
        print("PV3D still", f, "%.1f s" % (time.time() - t0), flush=True)
else:
    sc.render.filepath = OUT.replace("\\", "/") + "/f"
    bpy.ops.render.render(animation=True)
