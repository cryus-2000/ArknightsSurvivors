# -*- coding: utf-8 -*-
"""PV 片头第一镜「海嗣爬上礁石」· Blender HD-2D（用户 11-08 构想 + 参考图第一张构图，docs/327 §18）：
  右半中景：一块黑礁（pixgen 像素礁石），滑动者（游戏像素帧）沿礁石爬上顶；礁脚白浪
  左远：雾里的海岬（pixgen）上立着游戏像素灯塔，光束扫过海面，72 重拍停在海嗣身上
  前景：近黑暗礁（pixgen）横在画面下缘，景深虚掉；夜空、月、雾
  70–72 小节 = 0–197 帧
  blender -b --python tools/promo/pv3d_reef.py -- <素材目录> <输出目录> <帧,帧,… | 起-止>
"""
import math, os, random, sys, time
import bpy
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
AS, OUT = argv[0], argv[1]
RANGE = tuple(int(x) for x in argv[2].split("-")) if "-" in argv[2] else None
STILLS = [int(x) for x in argv[2].split(",")] if not RANGE else []
FPS = 60
BAR = 4 * 60 / 145.99
B = lambda k: int(round(k * BAR * FPS))
NF = B(3)
WARM = (1.0, 0.66, 0.32)

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
ee.taa_render_samples = 32
for k, v in (("use_raytracing", True), ("volumetric_tile_size", "2"), ("volumetric_samples", 64), ("use_volumetric_shadows", True),
             ("volumetric_end", 150.0), ("use_shadows", True)):
    try:
        setattr(ee, k, v)
    except Exception:
        pass
sc.view_settings.view_transform = "AgX"
try:
    sc.view_settings.look = "AgX - Medium High Contrast"
except Exception:
    pass


def mat(name):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    n, l = m.node_tree.nodes, m.node_tree.links
    n.clear()
    return m, n, l, n.new("ShaderNodeOutputMaterial")


def emis(name, col, k):
    m, n, l, o = mat(name)
    e = n.new("ShaderNodeEmission"); e.inputs["Color"].default_value = col + (1,); e.inputs["Strength"].default_value = k
    l.new(e.outputs[0], o.inputs["Surface"])
    return m


def img(name):
    return bpy.data.images.load(os.path.join(AS, name), check_existing=True)


# 夜空：上深下略亮的海军蓝；全局薄雾（光束靠它）
w = bpy.data.worlds.new("night"); sc.world = w; w.use_nodes = True
wn, wl = w.node_tree.nodes, w.node_tree.links; wn.clear()
wo = wn.new("ShaderNodeOutputWorld"); bg = wn.new("ShaderNodeBackground")
tc = wn.new("ShaderNodeTexCoord"); sx = wn.new("ShaderNodeSeparateXYZ"); wl.new(tc.outputs["Generated"], sx.inputs[0])
rp = wn.new("ShaderNodeValToRGB")
rp.color_ramp.elements[0].position, rp.color_ramp.elements[0].color = 0.5, (0.03, 0.05, 0.08, 1)
rp.color_ramp.elements[1].position, rp.color_ramp.elements[1].color = 0.75, (0.006, 0.012, 0.025, 1)
wl.new(sx.outputs["Z"], rp.inputs[0]); wl.new(rp.outputs[0], bg.inputs["Color"]); wl.new(bg.outputs[0], wo.inputs["Surface"])
vol = wn.new("ShaderNodeVolumePrincipled")
vol.inputs["Color"].default_value = (0.55, 0.65, 0.75, 1); vol.inputs["Density"].default_value = 0.012; vol.inputs["Anisotropy"].default_value = 0.55
vol.inputs["Emission Color"].default_value = (0.03, 0.05, 0.08, 1); vol.inputs["Emission Strength"].default_value = 0.02
wl.new(vol.outputs[0], wo.inputs["Volume"])

rng = random.Random(4)
star = emis("star", (0.85, 0.9, 1.0), 2.5)
for _ in range(140):
    bpy.ops.mesh.primitive_plane_add(size=rng.choice((0.3, 0.3, 0.6)), location=(rng.uniform(-110, 110), 160, rng.uniform(18, 80)))
    s = bpy.context.object; s.rotation_euler = (math.radians(90), 0, 0); s.data.materials.append(star)
# 月：像素月牙（两个方块圆相减的近似：亮圆 + 前面一个暗圆）
bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=3.2, depth=0.1, location=(42, 150, 58), rotation=(math.radians(90), 0, 0))
bpy.context.object.data.materials.append(emis("moon", (0.95, 0.92, 0.8), 6.0))
bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=3.0, depth=0.1, location=(43.6, 149, 59.2), rotation=(math.radians(90), 0, 0))
m, n, l, o = mat("moon_cut"); bb = n.new("ShaderNodeBackground"); bb.inputs["Color"].default_value = (0.006, 0.012, 0.025, 1)
e = n.new("ShaderNodeEmission"); e.inputs["Color"].default_value = (0.006, 0.012, 0.025, 1); e.inputs["Strength"].default_value = 1.0
l.new(e.outputs[0], o.inputs["Surface"]); bpy.context.object.data.materials.append(m)

# 海面：深色 + 阶梯浪纹
bpy.ops.mesh.primitive_plane_add(size=1, location=(0, 90, 0))
sea = bpy.context.object; sea.scale = (400, 200, 1)
m, n, l, o = mat("sea")
b = n.new("ShaderNodeBsdfPrincipled"); b.inputs["Base Color"].default_value = (0.012, 0.025, 0.04, 1); b.inputs["Roughness"].default_value = 0.18
wv = n.new("ShaderNodeTexWave"); wv.bands_direction = "Y"; wv.inputs["Scale"].default_value = 2.2; wv.inputs["Distortion"].default_value = 8
tcs = n.new("ShaderNodeTexCoord"); l.new(tcs.outputs["Object"], wv.inputs["Vector"])
cr = n.new("ShaderNodeValToRGB"); cr.color_ramp.interpolation = "CONSTANT"
cr.color_ramp.elements[0].color = (0, 0, 0, 1); cr.color_ramp.elements[1].position = 0.94; cr.color_ramp.elements[1].color = (0.12, 0.18, 0.22, 1)
l.new(wv.outputs["Fac"], cr.inputs[0]); l.new(cr.outputs[0], b.inputs["Emission Color"]); b.inputs["Emission Strength"].default_value = 0.12
l.new(b.outputs[0], o.inputs["Surface"])
wv.inputs["Phase Offset"].default_value = 0; wv.inputs["Phase Offset"].keyframe_insert("default_value", frame=0)
wv.inputs["Phase Offset"].default_value = 6; wv.inputs["Phase Offset"].keyframe_insert("default_value", frame=NF)
sea.data.materials.append(m)


def sprite(image, pxm, loc, name, emit=0.0, body=1.0, alpha_soft=False):
    w_, h_ = image.size
    bpy.ops.mesh.primitive_plane_add(size=1)
    ob = bpy.context.object; ob.name = name
    ob.scale = (w_ * pxm, h_ * pxm, 1); ob.rotation_euler = (math.radians(90), 0, 0)
    ob.location = (loc[0], loc[1], loc[2] + h_ * pxm / 2)
    m, n, l, o = mat(name)
    t = n.new("ShaderNodeTexImage"); t.image = image; t.interpolation = "Closest"
    bs = n.new("ShaderNodeBsdfPrincipled")
    hs = n.new("ShaderNodeHueSaturation"); hs.inputs["Value"].default_value = body
    l.new(t.outputs["Color"], hs.inputs["Color"]); l.new(hs.outputs[0], bs.inputs["Base Color"])
    l.new(t.outputs["Alpha"], bs.inputs["Alpha"]); bs.inputs["Roughness"].default_value = 0.7
    l.new(t.outputs["Color"], bs.inputs["Emission Color"]); bs.inputs["Emission Strength"].default_value = emit
    l.new(bs.outputs[0], o.inputs["Surface"])
    try:
        m.surface_render_method = "BLENDED" if alpha_soft else "DITHERED"
    except Exception:
        pass
    ob.data.materials.append(m)
    ob["t"] = t.name; ob["b"] = bs.name
    return ob


# 左远：海岬 + 灯塔
CL = Vector((-14.0, 70.0, -0.5))
sprite(img("cliff.png"), 0.07, (CL.x, CL.y, CL.z), "cliff", emit=0.12, alpha_soft=True)
LH = Vector((-18.2, 69.5, CL.z + 100 * 0.07 * 0.7))
lh = sprite(img("lighthouse.png"), 0.03, (LH.x, LH.y, LH.z), "lighthouse", emit=0.5)
lh.visible_shadow = False
LAMP = Vector((LH.x, LH.y - 0.3, LH.z + 108 * 0.03 * 0.86))
bpy.ops.mesh.primitive_uv_sphere_add(radius=0.25, location=LAMP)
lb = bpy.context.object; lb.data.materials.append(emis("lamp", WARM, 40.0)); lb.visible_shadow = False

# 右中：黑礁 + 礁脚白浪；滑动者沿礁石爬
RK = Vector((4.2, 16.0, -0.6))
RK_PX = 0.034
rock = sprite(img("rock.png"), RK_PX, (RK.x, RK.y, RK.z), "rock", emit=0.0, body=1.0)
sl_imgs = [img("slider_%d.png" % i) for i in range(5)]
SL_PX = 0.05
slider = sprite(sl_imgs[0], SL_PX, (0, RK.y - 0.4, 0), "slider", emit=0.0, body=0.8)
slider.visible_shadow = False
# 爬行路径：礁石左下 → 右上（礁顶在礁石贴图宽 78%、高 100% 处）
top = Vector((RK.x - 220 * RK_PX / 2 + 220 * RK_PX * 0.74, RK.y - 0.4, RK.z + 182 * RK_PX * 0.78))
bot = Vector((RK.x - 220 * RK_PX * 0.22, RK.y - 0.4, RK.z + 0.6))
for f, u in ((0, 0.0), (B(2), 0.92), (NF, 1.0)):
    p = bot.lerp(top, u)
    slider.location = (p.x, p.y, p.z + 46 * SL_PX / 2)
    slider.keyframe_insert("location", frame=f)
sl_t = slider.active_material.node_tree.nodes[slider["t"]]
sl_b = slider.active_material.node_tree.nodes[slider["b"]]
for f, k in ((0, 0.0), (B(2) - 2, 0.0), (B(2) + 4, 0.9), (NF, 0.5)):   # 照住：本体透出暖光
    sl_b.inputs["Emission Strength"].default_value = k
    sl_b.inputs["Emission Strength"].keyframe_insert("default_value", frame=f)
# 白浪：礁脚一串像素水花（发光小方块，随时间起伏）
foam = emis("foam", (0.75, 0.88, 0.95), 0.8)
fo_objs = []
for i in range(60):
    x = RK.x - 3.2 + rng.uniform(0, 6.8)
    bpy.ops.mesh.primitive_plane_add(size=rng.choice((0.05, 0.05, 0.1)), location=(x, RK.y - 0.6 - rng.uniform(0, 1.2), rng.uniform(0.0, 0.3)))
    q = bpy.context.object; q.rotation_euler = (math.radians(90), 0, 0); q.data.materials.append(foam)
    ph = rng.uniform(0, 6.28)
    for f in range(0, NF + 1, 10):
        q.location.z = max(0.0, 0.12 + 0.18 * math.sin(f / FPS * 3 + ph))
        q.keyframe_insert("location", frame=f)

# 前景暗礁：画面下缘，靠近镜头，景深虚
fr = sprite(img("fore.png"), 0.016, (0.0, 1.2, -0.25), "fore", emit=0.0, body=0.5)

# 灯塔光束：扫过海面，72 重拍停在海嗣身上
bpy.ops.object.light_add(type="SPOT", location=LAMP)
beam = bpy.context.object
beam.data.color = WARM; beam.data.spot_size = math.radians(4.5); beam.data.spot_blend = 0.25; beam.data.shadow_soft_size = 0.05
try:
    beam.data.volume_factor = 10.0
except Exception:
    pass
aim = bpy.data.objects.new("aim", None); sc.collection.objects.link(aim)
c = beam.constraints.new("TRACK_TO"); c.target = aim; c.track_axis = "TRACK_NEGATIVE_Z"; c.up_axis = "UP_Y"
for f, p in ((0, (-40, 20, 0)), (B(1), (-10, 8, 0)), (B(2) - 25, (20, 20, 2)), (B(2), tuple(top)), (NF, tuple(top))):
    aim.location = p; aim.keyframe_insert("location", frame=f)
for f, e in ((0, 30000), (NF, 30000)):
    beam.data.energy = e; beam.data.keyframe_insert("energy", frame=f)
bpy.ops.object.light_add(type="SUN", rotation=(math.radians(55), 0, math.radians(150)))   # 月光：冷、弱
moon = bpy.context.object; moon.data.energy = 0.8; moon.data.color = (0.55, 0.7, 0.95)
bpy.ops.object.light_add(type="POINT", location=(top.x - 1.5, top.y - 2.2, top.z + 1.0))   # 照住时的暖色补光（光束从它侧后方来）
hit = bpy.context.object; hit.data.color = WARM
for f, e in ((0, 0), (B(2) - 2, 0), (B(2) + 4, 260), (NF, 160)):
    hit.data.energy = e; hit.data.keyframe_insert("energy", frame=f)

# 镜头：低机位，略仰；慢推（参考图第一张构图：礁石右半、灯塔左远、前景暗礁下缘）
cam_d = bpy.data.cameras.new("cam"); cam_d.sensor_fit = "VERTICAL"; cam_d.angle_y = math.radians(30)
cam_d.dof.use_dof = True; cam_d.dof.aperture_fstop = 2.8; cam_d.dof.focus_distance = 15.0
cam = bpy.data.objects.new("cam", cam_d); sc.collection.objects.link(cam); sc.camera = cam
for f, x, y in ((0, -0.6, -4.0), (NF, -0.2, -2.8)):
    cam.location = (x, y, 2.0)
    cam.rotation_euler = (math.radians(91), 0, math.radians(-4))
    cam.keyframe_insert("location", frame=f)
    cam.keyframe_insert("rotation_euler", frame=f)


def _swap(scene, *_):
    sl_t.image = sl_imgs[(scene.frame_current // 8) % 5]


bpy.app.handlers.frame_change_pre.append(_swap)

sc.use_nodes = True
cn, cl = sc.node_tree.nodes, sc.node_tree.links; cn.clear()
rl = cn.new("CompositorNodeRLayers"); g = cn.new("CompositorNodeGlare")
try:
    g.glare_type = "BLOOM"
except Exception:
    g.glare_type = "FOG_GLOW"
for nm, v in (("Threshold", 0.7), ("Strength", 0.6), ("Size", 0.6)):
    try:
        g.inputs[nm].default_value = v
    except Exception:
        pass
co = cn.new("CompositorNodeComposite"); cl.new(rl.outputs["Image"], g.inputs["Image"]); cl.new(g.outputs["Image"], co.inputs["Image"])

os.makedirs(OUT, exist_ok=True)
if RANGE:
    sc.frame_start, sc.frame_end = RANGE
    sc.render.filepath = OUT.replace("\\", "/") + "/r"
    bpy.ops.render.render(animation=True)
for f in STILLS:
    t0 = time.time()
    sc.frame_set(f)
    sc.render.filepath = OUT.replace("\\", "/") + "/r%04d.png" % f
    bpy.ops.render.render(write_still=True)
    print("PV3D still", f, "%.1f s" % (time.time() - t0), flush=True)
