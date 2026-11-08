# -*- coding: utf-8 -*-
"""PV 3D 开头 · Blender 版（11-08）：海水中（不要海床），学官方水月 PV 的渲染感——深海军蓝压底、头顶水面光 + 光束、
边缘发光的半透明水母、悬浮颗粒 + 浅景深光斑、bloom + 轻色散、逆光剪影。卡 = 游戏招募卡 / 升级卡做成的银边实体卡。EEVEE 渲染。

  D:/blender/blender-4.5.15-windows-x64/blender.exe -b --python tools/promo/pv3d_blender.py -- <卡面目录> <输出帧目录> [起帧 止帧 | 帧,帧,…]

时长 = battle2 第 70–77 小节（7 小节 = 11.507 秒，60 帧 = 691 帧）：
  0–2 小节   卡片在水中翻转下沉，镜头微仰（背后水面光与光束），缓缓下潜
  2–4 小节   一排卡悬在水里，卡背朝镜头，依次翻面露出正面（八分音符一张），镜头横移
  4 小节     重拍：斯卡蒂的招募卡转到镜头前、冷光一闪；镜头推进卡面，末 0.35 秒提亮到白切实机
坐标：Z 向上，镜头大致朝 +Y。
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
CW, CH, CT = 1.0, 1.405, 0.03
S1, S2 = int(2 * BAR * FPS), int(4 * BAR * FPS)


def ease(x):
    x = min(1.0, max(0.0, x))
    return 1 - (1 - x) ** 3


def ease_io(x):
    x = min(1.0, max(0.0, x))
    return x * x * (3 - 2 * x)


bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
sc.render.fps = FPS
sc.frame_start, sc.frame_end = 0, NF - 1
sc.render.resolution_x, sc.render.resolution_y = 1920, 1080
for eng in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE"):
    try:
        sc.render.engine = eng
        break
    except TypeError:
        pass
ee = sc.eevee
ee.taa_render_samples = 32
for k, v in (("use_raytracing", True), ("volumetric_tile_size", "2"), ("volumetric_samples", 64), ("use_volumetric_shadows", True),
             ("volumetric_end", 80.0), ("volumetric_start", 0.1), ("use_shadows", True), ("shadow_ray_count", 2)):
    try:
        setattr(ee, k, v)
    except Exception as e:
        print("eevee skip", k, e)
sc.render.use_motion_blur = True
sc.render.motion_blur_shutter = 0.45
sc.view_settings.view_transform = "AgX"
try:
    sc.view_settings.look = "AgX - Punchy"
except Exception:
    pass
sc.render.image_settings.file_format = "PNG"


def mat(name):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    n, l = m.node_tree.nodes, m.node_tree.links
    if "Principled BSDF" not in n:
        n.clear()
        o = n.new("ShaderNodeOutputMaterial")
        o.name = "out"
        b = n.new("ShaderNodeBsdfPrincipled")
        b.name = "Principled BSDF"
        l.new(b.outputs[0], o.inputs["Surface"])
    return m, n, l


def img(path):
    return bpy.data.images.load(path, check_existing=True)


# ---------------------------------------------------------------- 水体：上亮下暗的渐变 + 体积散射
world = bpy.data.worlds.new("sea")
sc.world = world
world.use_nodes = True
wn, wl = world.node_tree.nodes, world.node_tree.links
wn.clear()
wout = wn.new("ShaderNodeOutputWorld")
wbg = wn.new("ShaderNodeBackground")
wl.new(wbg.outputs[0], wout.inputs["Surface"])
tco = wn.new("ShaderNodeTexCoord")
sep = wn.new("ShaderNodeSeparateXYZ")
wl.new(tco.outputs["Generated"], sep.inputs[0])
ramp = wn.new("ShaderNodeValToRGB")
cr = ramp.color_ramp
cr.elements[0].position, cr.elements[0].color = 0.30, (0.002, 0.008, 0.018, 1)   # 深处近黑的海军蓝
cr.elements[1].position, cr.elements[1].color = 0.62, (0.025, 0.12, 0.19, 1)      # 水面方向的青蓝
e = cr.elements.new(0.80)
e.color = (0.2, 0.45, 0.58, 1)
wl.new(sep.outputs["Z"], ramp.inputs[0])
wl.new(ramp.outputs[0], wbg.inputs["Color"])
wbg.inputs["Strength"].default_value = 1.0
vol = wn.new("ShaderNodeVolumePrincipled")
vol.inputs["Color"].default_value = (0.3, 0.65, 0.8, 1)
vol.inputs["Density"].default_value = 0.04
vol.inputs["Anisotropy"].default_value = 0.72
vol.inputs["Absorption Color"].default_value = (0.02, 0.15, 0.25, 1)
wl.new(vol.outputs[0], wout.inputs["Volume"])

# ---------------------------------------------------------------- 水面（头顶发亮的波纹）+ 光束遮罩
bpy.ops.mesh.primitive_plane_add(size=400, location=(0, 10, 30))
surf = bpy.context.object
sm, sn, sl = mat("surface")
sb = sn["Principled BSDF"]
sv = sn.new("ShaderNodeTexVoronoi"); sv.voronoi_dimensions = "4D"; sv.feature = "DISTANCE_TO_EDGE"; sv.inputs["Scale"].default_value = 0.6
stc = sn.new("ShaderNodeTexCoord"); snz = sn.new("ShaderNodeTexNoise"); snz.inputs["Scale"].default_value = 0.08
smx = sn.new("ShaderNodeMix"); smx.data_type = "VECTOR"; smx.inputs["Factor"].default_value = 0.6
sl.new(stc.outputs["Object"], smx.inputs[4]); sl.new(snz.outputs["Color"], smx.inputs[5]); sl.new(stc.outputs["Object"], snz.inputs["Vector"])
sl.new(smx.outputs[1], sv.inputs["Vector"])
sv.inputs["W"].default_value = 0; sv.inputs["W"].keyframe_insert("default_value", frame=0)
sv.inputs["W"].default_value = 1.3; sv.inputs["W"].keyframe_insert("default_value", frame=NF)
srg = sn.new("ShaderNodeMapRange"); srg.inputs["From Max"].default_value = 0.14; srg.inputs["To Min"].default_value = 2.2; srg.inputs["To Max"].default_value = 0.35
sl.new(sv.outputs["Distance"], srg.inputs["Value"])
sl.new(srg.outputs[0], sb.inputs["Emission Strength"])
sb.inputs["Emission Color"].default_value = (0.65, 0.9, 1.0, 1)
sb.inputs["Base Color"].default_value = (0.0, 0.0, 0.0, 1)
surf.data.materials.append(sm)
surf.visible_shadow = False
surf.hide_render = True   # 11-08 用户：水面网纹太明显 → 不画水面，头顶亮光只靠水体渐变 + 光束
bpy.ops.mesh.primitive_plane_add(size=220, location=(0, 10, 13))
gobo = bpy.context.object
gm, gn, gl = mat("gobo")
gbs = gn["Principled BSDF"]
gnz = gn.new("ShaderNodeTexNoise"); gnz.inputs["Scale"].default_value = 0.9; gnz.inputs["Detail"].default_value = 4; gnz.inputs["Distortion"].default_value = 0.6
gcr = gn.new("ShaderNodeMapRange"); gcr.inputs["From Min"].default_value = 0.52; gcr.inputs["From Max"].default_value = 0.6
gl.new(gnz.outputs["Fac"], gcr.inputs["Value"])
gl.new(gcr.outputs[0], gbs.inputs["Alpha"])
try:
    gm.surface_render_method = "DITHERED"
except Exception:
    pass
gobo.data.materials.append(gm)
gobo.visible_camera = False
for f in (0, NF):   # 遮罩缓慢漂移 → 光束晃动
    gobo.location.x = 0.0 if f == 0 else 1.6
    gobo.keyframe_insert("location", frame=f)

# ---------------------------------------------------------------- 灯
bpy.ops.object.light_add(type="SUN", rotation=(math.radians(10), math.radians(-6), 0))
sun = bpy.context.object
sun.data.energy = 7.0
sun.data.color = (0.75, 0.95, 1.0)
sun.data.angle = math.radians(0.8)
try:
    sun.data.volume_factor = 6.0
except Exception:
    pass
bpy.ops.object.light_add(type="AREA", location=(0, 6, 3))       # 逆光：卡和水母的亮边
rim = bpy.context.object
rim.data.energy = 2500
rim.data.size = 6
rim.data.color = (0.5, 0.85, 1.0)
rim.rotation_euler = (math.radians(-100), 0, 0)
bpy.ops.object.light_add(type="AREA", location=(-3.5, -5, 1.5))  # 卡面柔光
fill = bpy.context.object
fill.data.energy = 700
fill.data.size = 5
fill.data.color = (0.8, 0.92, 1.0)
fill.rotation_euler = (math.radians(75), 0, math.radians(-35))
bpy.ops.object.light_add(type="POINT", location=(0, -0.4, 0.8))  # 重拍闪光
flash = bpy.context.object
flash.data.color = (0.7, 0.92, 1.0)
flash.data.shadow_soft_size = 0.5

# ---------------------------------------------------------------- 卡
faces_img = []
i = 0
while os.path.exists(os.path.join(CARDS, "c%d.png" % i)):
    faces_img.append(img(os.path.join(CARDS, "c%d.png" % i)))
    i += 1
back_img = img(os.path.join(CARDS, "_back.png"))
silver, sn2, sl2 = mat("silver")
sb2 = sn2["Principled BSDF"]
sb2.inputs["Base Color"].default_value = (0.82, 0.88, 0.92, 1)
sb2.inputs["Metallic"].default_value = 1.0
sb2.inputs["Roughness"].default_value = 0.18


def face_mat(im, k):
    m, n, l = mat("face")
    b = n["Principled BSDF"]
    t = n.new("ShaderNodeTexImage")
    t.image = im
    l.new(t.outputs[0], b.inputs["Base Color"])
    l.new(t.outputs[0], b.inputs["Emission Color"])
    b.inputs["Emission Strength"].default_value = k
    b.inputs["Roughness"].default_value = 0.3
    b.inputs["Coat Weight"].default_value = 0.7
    b.inputs["Coat Roughness"].default_value = 0.06
    return m


face_mats = [face_mat(im, 1.4) for im in faces_img]
back_mat = face_mat(back_img, 0.5)


def make_card(idx):
    """原点在卡中心，正面朝 -Y"""
    bpy.ops.mesh.primitive_cube_add(size=1)
    body = bpy.context.object
    body.scale = (CW, CT, CH)
    bpy.ops.object.transform_apply(scale=True)
    bv = body.modifiers.new("bevel", "BEVEL")
    bv.width = 0.012
    bv.segments = 3
    body.data.materials.append(silver)
    root = bpy.data.objects.new("card", None)
    sc.collection.objects.link(root)
    body.parent = root
    for side, mt in ((-1, face_mats[idx % len(face_mats)]), (1, back_mat)):
        bpy.ops.mesh.primitive_plane_add(size=1)
        q = bpy.context.object
        q.scale = (CW * 0.955, CH * 0.97, 1)
        q.rotation_euler = (math.radians(90) * -side, 0, math.pi if side == 1 else 0)
        q.location = (0, side * (CT / 2 + 0.0015), 0)
        q.data.materials.append(mt)
        q.parent = root
    return root


def vis(root, on_fn):
    last = None
    for f in range(NF):
        on = on_fn(f)
        if on != last:
            for o in [root] + list(root.children):
                o.hide_render = not on
                o.keyframe_insert("hide_render", frame=f)
            last = on


def key(o, f):
    o.keyframe_insert("location", frame=f)
    o.keyframe_insert("rotation_euler", frame=f)


r2 = random.Random(11)
for k in range(24):   # 镜头一：翻转下沉
    c = make_card(k)
    p0 = Vector((r2.uniform(-5.0, 5.0), r2.uniform(-1.0, 9.0), r2.uniform(0.5, 7.5)))
    r0 = Vector([math.radians(r2.uniform(-180, 180)) for _ in range(3)])
    w = Vector([math.radians(r2.uniform(-55, 55)) for _ in range(3)])
    v = r2.uniform(0.3, 0.65)
    for f in range(0, S1 + 2, 2):
        t = f / FPS
        c.location = p0 + Vector((0.08 * math.sin(t + k), 0, -v * t))
        c.rotation_euler = r0 + w * t
        key(c, f)
    vis(c, lambda f: f < S1)
for k in range(9):    # 镜头二：悬在水里一排，依次翻面（绕竖轴转 180°，卡背 → 正面）
    c = make_card(k)
    x = (k - 4) * 1.3
    zb = 0.25 * math.sin(k * 1.7)
    t_up = BAR * 2 + 0.2 + k * (BAR / 8)
    for f in range(S1 - 2, NF, 2):
        t = f / FPS
        kk = ease((t - t_up) / 0.32)
        c.location = (x, 1.0 + 0.3 * math.cos(k * 2.1), zb + 0.05 * math.sin(t * 1.3 + k))
        c.rotation_euler = (0, math.radians(4 * math.sin(k)), math.radians(180) * (1 - kk))
        key(c, f)
    vis(c, lambda f: f >= S1)
hero = make_card(5)   # 斯卡蒂：从右侧翻转着转到镜头前
for f in range(S2 - 2, NF):
    lt = f / FPS - 4 * BAR
    dk = ease(lt / 0.22)
    hero.location = (1.6 * (1 - dk), -1.0, 0.05 + 0.6 * (1 - dk) + 0.03 * math.sin(lt * 1.4))
    hero.rotation_euler = (math.radians(-10) * (1 - dk), math.radians(25) * (1 - dk), math.radians(-150) * (1 - dk))
    key(hero, f)
vis(hero, lambda f: f >= S2)

# ---------------------------------------------------------------- 水母：半透明伞，边缘按视角发青白光（菲涅尔），触须细而弯
jm, jn, jl = mat("jelly")
jout = jn["out"]
jn.remove(jn["Principled BSDF"])
lw = jn.new("ShaderNodeLayerWeight"); lw.inputs["Blend"].default_value = 0.35
em = jn.new("ShaderNodeEmission"); em.inputs["Color"].default_value = (0.45, 0.85, 1.0, 1)
pw = jn.new("ShaderNodeMath"); pw.operation = "MULTIPLY"; pw.inputs[1].default_value = 7.0
jl.new(lw.outputs["Facing"], pw.inputs[0]); jl.new(pw.outputs[0], em.inputs["Strength"])
tr = jn.new("ShaderNodeBsdfTransparent")
add = jn.new("ShaderNodeAddShader")
jl.new(tr.outputs[0], add.inputs[0]); jl.new(em.outputs[0], add.inputs[1])
jl.new(add.outputs[0], jout.inputs["Surface"])
try:
    jm.surface_render_method = "BLENDED"
except Exception:
    pass
r3 = random.Random(5)
for k in range(10):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.3, segments=32, ring_count=16)
    bell = bpy.context.object
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="DESELECT")
    bpy.ops.object.mode_set(mode="OBJECT")
    for v in bell.data.vertices:   # 去掉下半球 → 伞
        v.select = v.co.z < -0.02
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.delete(type="VERT")
    bpy.ops.object.mode_set(mode="OBJECT")
    bell.data.materials.append(jm)
    bpy.ops.object.shade_smooth()
    for tk in range(9):   # 触须：带粗细的曲线
        cu = bpy.data.curves.new("tent", "CURVE")
        cu.dimensions = "3D"
        cu.bevel_depth = 0.004 if tk % 3 else 0.008
        spl = cu.splines.new("BEZIER")
        L = r3.uniform(0.6, 1.4)
        spl.bezier_points.add(3)
        a = tk / 9 * 6.28
        for j, bp in enumerate(spl.bezier_points):
            tt = j / 3
            bp.co = (math.cos(a) * 0.2 * (1 - 0.4 * tt) + 0.08 * math.sin(j * 1.7 + tk), math.sin(a) * 0.2 * (1 - 0.4 * tt), -L * tt)
            bp.handle_left_type = bp.handle_right_type = "AUTO"
        to = bpy.data.objects.new("tent", cu)
        sc.collection.objects.link(to)
        cu.materials.append(jm)
        to.parent = bell
    p = Vector((r3.uniform(-7, 7), r3.uniform(2, 14), r3.uniform(-2.5, 5.5)))
    if k < 2:
        p = Vector(((-2.2, 2.4)[k], 2.2, (1.4, 0.2)[k]))   # 两只近景
    sp_, ph = r3.uniform(0.06, 0.16), r3.uniform(0, 6.28)
    for f in range(0, NF + 4, 4):
        t = f / FPS
        bell.location = p + Vector((0.12 * math.sin(t * 0.6 + ph), 0, sp_ * t + 0.06 * math.sin(t * 2.2 + ph)))
        s = 1 + 0.1 * math.sin(t * 2.2 + ph)
        bell.scale = (s, s, 0.7 / s)
        bell.rotation_euler = (math.radians(8 * math.sin(t * 0.8 + ph)), math.radians(6 * math.cos(t * 0.7 + ph)), 0)
        bell.keyframe_insert("location", frame=f)
        bell.keyframe_insert("scale", frame=f)
        bell.keyframe_insert("rotation_euler", frame=f)

# ---------------------------------------------------------------- 悬浮颗粒（浅景深下成光斑）
pm_, pn, pl = mat("mote")
pb = pn["Principled BSDF"]
pb.inputs["Emission Color"].default_value = (0.75, 0.95, 1.0, 1)
pb.inputs["Emission Strength"].default_value = 2.0
pb.inputs["Base Color"].default_value = (0.8, 0.95, 1.0, 1)
bpy.ops.mesh.primitive_ico_sphere_add(radius=0.01, subdivisions=1, location=(0, 0, -80))
mote = bpy.context.object
mote.data.materials.append(pm_)
bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 5, 2))
emi = bpy.context.object
emi.scale = (22, 22, 14)
ps = emi.modifiers.new("motes", "PARTICLE_SYSTEM").particle_system.settings
ps.count = 3500
ps.frame_start = -900
ps.frame_end = NF
ps.lifetime = 1800
ps.emit_from = "VOLUME"
ps.normal_factor = 0
ps.factor_random = 0.05
ps.effector_weights.gravity = -0.008
ps.render_type = "OBJECT"
ps.instance_object = mote
ps.particle_size = 1.0
ps.size_random = 0.8
emi.show_instancer_for_render = False
emi.visible_camera = False
emi.visible_shadow = False   # 发射体立方体投影会在体积光里切出直边明暗块

# ---------------------------------------------------------------- 镜头
cam_d = bpy.data.cameras.new("cam")
cam_d.sensor_fit = "VERTICAL"
cam_d.angle_y = math.radians(36)
cam_d.dof.use_dof = True
cam_d.dof.aperture_fstop = 1.4
cam = bpy.data.objects.new("cam", cam_d)
sc.collection.objects.link(cam)
sc.camera = cam
tgt = bpy.data.objects.new("tgt", None)
sc.collection.objects.link(tgt)
tc_ = cam.constraints.new("TRACK_TO")
tc_.target = tgt
tc_.track_axis = "TRACK_NEGATIVE_Z"
tc_.up_axis = "UP_Y"
for f in range(NF):
    t = f / FPS
    fl = 0.0
    if f < S1:   # 微仰，缓缓下潜前推
        u = ease_io(t / (2 * BAR))
        cl, tl, fd = (0.3 - 0.4 * u, -6.0 + 1.6 * u, 0.6 - 0.9 * u), (0, 4.0, 2.6 - 1.4 * u), 6.0 - 1.0 * u
    elif f < S2:   # 横移看一排卡
        u = ease_io((t - 2 * BAR) / (2 * BAR))
        cl, tl, fd = (-4.6 + 7.0 * u, -3.2, 0.25), (-2.6 + 7.0 * u, 1.0, 0.05), 4.4
    else:
        lt = t - 4 * BAR
        pk = ease(max(0.0, lt - 0.3) / (3 * BAR - 0.3))
        cl = (0.0, -(4.4 - 1.9 * pk), 0.15)
        tl = (0.0, -1.0, 0.08)
        fd = math.dist(cl, (0, -1.0, 0.08))
        fl = max(0.0, 1 - lt / 0.4)
    cam.location, tgt.location = cl, tl
    cam_d.dof.focus_distance = fd
    flash.data.energy = 30 + 1400 * fl
    cam.keyframe_insert("location", frame=f)
    tgt.keyframe_insert("location", frame=f)
    cam_d.dof.keyframe_insert("focus_distance", frame=f)
    flash.data.keyframe_insert("energy", frame=f)
    sc.view_settings.exposure = 2.4 * ease((t - (DUR - 0.35)) / 0.35) if f >= S2 else 0.0
    sc.view_settings.keyframe_insert("exposure", frame=f)
for a in bpy.data.actions:
    for fc in a.fcurves:
        for kp in fc.keyframe_points:
            kp.interpolation = "LINEAR"

# ---------------------------------------------------------------- 合成：bloom + 轻色散
sc.use_nodes = True
cn, cl_ = sc.node_tree.nodes, sc.node_tree.links
cn.clear()
rl = cn.new("CompositorNodeRLayers")
gl_ = cn.new("CompositorNodeGlare")
try:
    gl_.glare_type = "BLOOM"
except Exception:
    gl_.glare_type = "FOG_GLOW"
for k, v in (("quality", "HIGH"), ("threshold", 0.8), ("size", 8), ("mix", -0.55)):
    try:
        setattr(gl_, k, v)
    except Exception:
        pass
for nm, v in (("Threshold", 0.8), ("Strength", 0.5), ("Size", 0.6)):
    try:
        gl_.inputs[nm].default_value = v
    except Exception:
        pass
ld = cn.new("CompositorNodeLensdist")
try:
    ld.inputs["Dispersion"].default_value = 0.012
    ld.inputs["Distortion"].default_value = 0.0
except Exception:
    pass
co = cn.new("CompositorNodeComposite")
cl_.new(rl.outputs["Image"], gl_.inputs["Image"])
cl_.new(gl_.outputs["Image"], ld.inputs["Image"])
cl_.new(ld.outputs["Image"], co.inputs["Image"])

os.makedirs(OUT, exist_ok=True)
sc.frame_start = F0
sc.frame_end = F1 if F1 is not None else NF - 1
print("PV3D-BLENDER", sc.render.engine, sc.frame_start, sc.frame_end, flush=True)
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
