# -*- coding: utf-8 -*-
"""PV 片头「海嗣上岸」· Blender HD-2D（用户 11-08 构想，docs/327 §18）：battle2 第 70–77 小节 + 77 后两拍，一个连续摇臂镜头。
  70–71  夜海滩：一只滑动者（slider）从浪里爬上岸，前景、要大；远处小灯塔的光束扫过海面
  72     重拍：光束停在它身上，暖光，眼睛反光
  73     镜头下沉穿过水面（上半岸上、下半水下）
  74     水下近处几只海嗣，大、暗、虚
  75–76  拉远：几百双眼睛分三层亮起
  77–    drop 青白一闪（标题组在剪辑时 2D 叠）
游戏像素贴图（最近邻、整数像素）立在 3D 里；海面、海滩、夜空、礁石在 Blender 里搭。

  blender -b --python tools/promo/pv3d_shore.py -- <素材目录> <输出目录> [帧,帧,… | 起帧-止帧]
素材目录：<怪>_<帧>.png / _emit.png（从游戏帧条按帧切出）、lighthouse.png、mound.png
"""
import math, os, random, sys, time
import bpy
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
AS, OUT = argv[0], argv[1]
RANGE = tuple(int(x) for x in argv[2].split("-")) if len(argv) > 2 and "-" in argv[2] else None
STILLS = [int(x) for x in argv[2].split(",")] if len(argv) > 2 and not RANGE else [60]
FPS = 60
BAR = 4 * 60 / 145.99
B = lambda k: int(round(k * BAR * FPS))   # 第 70+k 小节起点的帧号
NF = B(7) + int(round(2 * BAR / 4 * FPS))  # 70–77 + 两拍
WARM = (1.0, 0.62, 0.28)
CY = (0.37, 0.9, 0.9)

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
             ("volumetric_end", 120.0), ("use_shadows", True)):
    try:
        setattr(ee, k, v)
    except Exception:
        pass
sc.view_settings.view_transform = "AgX"
try:
    sc.view_settings.look = "AgX - High Contrast"
except Exception:
    pass


def mat(name):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    n, l = m.node_tree.nodes, m.node_tree.links
    n.clear()
    return m, n, l, n.new("ShaderNodeOutputMaterial")


def img(name):
    return bpy.data.images.load(os.path.join(AS, name), check_existing=True)


# ---------------------------------------------------------------- 夜空（世界）+ 岸上薄雾
w = bpy.data.worlds.new("night")
sc.world = w
w.use_nodes = True
wn, wl = w.node_tree.nodes, w.node_tree.links
wn.clear()
wo = wn.new("ShaderNodeOutputWorld")
bgn = wn.new("ShaderNodeBackground")
tc = wn.new("ShaderNodeTexCoord"); sp_ = wn.new("ShaderNodeSeparateXYZ"); wl.new(tc.outputs["Generated"], sp_.inputs[0])
rp = wn.new("ShaderNodeValToRGB")
rp.color_ramp.elements[0].position, rp.color_ramp.elements[0].color = 0.45, (0.004, 0.008, 0.016, 1)
rp.color_ramp.elements[1].position, rp.color_ramp.elements[1].color = 0.8, (0.012, 0.025, 0.05, 1)
wl.new(sp_.outputs["Z"], rp.inputs[0]); wl.new(rp.outputs[0], bgn.inputs["Color"])
wl.new(bgn.outputs[0], wo.inputs["Surface"])
vol = wn.new("ShaderNodeVolumePrincipled")
vol.inputs["Color"].default_value = (0.5, 0.6, 0.7, 1)
vol.inputs["Density"].default_value = 0.006
vol.inputs["Anisotropy"].default_value = 0.6
wl.new(vol.outputs[0], wo.inputs["Volume"])


def emis_mat(name, col, k):
    m, n, l, o = mat(name)
    e = n.new("ShaderNodeEmission"); e.inputs["Color"].default_value = col + (1,); e.inputs["Strength"].default_value = k
    l.new(e.outputs[0], o.inputs["Surface"])
    return m


rng = random.Random(3)
star_m = emis_mat("star", (0.8, 0.9, 1.0), 3.0)
for _ in range(160):   # 像素星：远处小方片
    bpy.ops.mesh.primitive_plane_add(size=rng.choice((0.25, 0.25, 0.5)), location=(rng.uniform(-90, 90), 150, rng.uniform(8, 70)))
    s = bpy.context.object
    s.rotation_euler = (math.radians(90), 0, 0)
    s.data.materials.append(star_m)

# ---------------------------------------------------------------- 海面（z = 0，y > 1.5）：深蓝 + 阶梯状浪纹（像素感）；水下体积
bpy.ops.mesh.primitive_plane_add(size=1, location=(0, 81.5, 0))
sea = bpy.context.object
sea.scale = (300, 160, 1)
m, n, l, o = mat("sea")
b = n.new("ShaderNodeBsdfPrincipled")
b.inputs["Base Color"].default_value = (0.01, 0.025, 0.045, 1)
b.inputs["Roughness"].default_value = 0.25
wv = n.new("ShaderNodeTexWave"); wv.wave_type = "BANDS"; wv.bands_direction = "Y"; wv.inputs["Scale"].default_value = 3.0
wv.inputs["Distortion"].default_value = 6.0; wv.inputs["Detail"].default_value = 1.0
tcs = n.new("ShaderNodeTexCoord"); l.new(tcs.outputs["Object"], wv.inputs["Vector"])
cr = n.new("ShaderNodeValToRGB"); cr.color_ramp.interpolation = "CONSTANT"
cr.color_ramp.elements[0].position, cr.color_ramp.elements[0].color = 0.0, (0, 0, 0, 1)
cr.color_ramp.elements[1].position, cr.color_ramp.elements[1].color = 0.93, (0.25, 0.6, 0.7, 1)
l.new(wv.outputs["Fac"], cr.inputs[0]); l.new(cr.outputs[0], b.inputs["Emission Color"])
b.inputs["Emission Strength"].default_value = 0.35
l.new(b.outputs[0], o.inputs["Surface"])
wv.inputs["Phase Offset"].default_value = 0.0
wv.inputs["Phase Offset"].keyframe_insert("default_value", frame=0)
wv.inputs["Phase Offset"].default_value = 18.0
wv.inputs["Phase Offset"].keyframe_insert("default_value", frame=NF)
sea.data.materials.append(m)
# 浪线：近岸一条亮的阶梯白浪（拍岸）
bpy.ops.mesh.primitive_plane_add(size=1, location=(0, 1.55, 0.015))
foam = bpy.context.object
foam.scale = (300, 0.12, 1)
foam.data.materials.append(emis_mat("foam", (0.6, 0.85, 0.9), 1.2))
# 水下体积：海面以下一个大盒子，浓青蓝雾
bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 80, -40))
uw = bpy.context.object
uw.scale = (400, 200, 80)
m, n, l, o = mat("underwater")
uv_ = n.new("ShaderNodeVolumePrincipled")
uv_.inputs["Color"].default_value = (0.25, 0.6, 0.75, 1)
uv_.inputs["Density"].default_value = 0.05
uv_.inputs["Anisotropy"].default_value = 0.7
uv_.inputs["Emission Color"].default_value = (0.02, 0.07, 0.11, 1)
uv_.inputs["Emission Strength"].default_value = 0.02
l.new(uv_.outputs[0], o.inputs["Volume"])
uw.data.materials.append(m)
uw.visible_shadow = False

# ---------------------------------------------------------------- 海滩（y < 1.6，略高于海面）+ 水下海床
bpy.ops.mesh.primitive_plane_add(size=1, location=(0, -48.4, 0.01))
beach = bpy.context.object
beach.scale = (300, 100, 1)
m, n, l, o = mat("sand")
b = n.new("ShaderNodeBsdfPrincipled"); b.inputs["Base Color"].default_value = (0.05, 0.06, 0.07, 1); b.inputs["Roughness"].default_value = 0.95
l.new(b.outputs[0], o.inputs["Surface"])
beach.data.materials.append(m)
bpy.ops.mesh.primitive_plane_add(size=1, location=(0, 80, -26))
bed = bpy.context.object
bed.scale = (400, 200, 1)
bed.data.materials.append(m)


# ---------------------------------------------------------------- 像素纸片
def sprite(image, pxm, loc, name, emit_img=None, emit_k=0.0, emit_col=(1, 1, 1), body=1.0, self_emit=0.05, rot=(90, 0, 0)):
    w_, h_ = image.size
    bpy.ops.mesh.primitive_plane_add(size=1)
    ob = bpy.context.object
    ob.name = name
    ob.scale = (w_ * pxm, h_ * pxm, 1)
    ob.rotation_euler = tuple(math.radians(a) for a in rot)
    ob.location = (loc[0], loc[1], loc[2] + h_ * pxm / 2)
    m, n, l, o = mat(name)
    t = n.new("ShaderNodeTexImage"); t.image = image; t.interpolation = "Closest"
    bs = n.new("ShaderNodeBsdfPrincipled")
    hs = n.new("ShaderNodeHueSaturation"); hs.inputs["Value"].default_value = body
    l.new(t.outputs["Color"], hs.inputs["Color"]); l.new(hs.outputs[0], bs.inputs["Base Color"])
    l.new(t.outputs["Alpha"], bs.inputs["Alpha"])
    bs.inputs["Roughness"].default_value = 0.9
    if emit_img is not None:
        te = n.new("ShaderNodeTexImage"); te.image = emit_img; te.interpolation = "Closest"
        mx = n.new("ShaderNodeMix"); mx.data_type = "RGBA"; mx.inputs[6].default_value = (0, 0, 0, 1)   # 只有发光层（眼睛）发光
        l.new(te.outputs["Color"], mx.inputs[7])
        l.new(te.outputs["Alpha"], mx.inputs["Factor"])
        l.new(mx.outputs[2], bs.inputs["Emission Color"])
        bs.inputs["Emission Strength"].default_value = emit_k
    else:
        l.new(t.outputs["Color"], bs.inputs["Emission Color"])
        bs.inputs["Emission Strength"].default_value = self_emit
    l.new(bs.outputs[0], o.inputs["Surface"])
    try:
        m.surface_render_method = "DITHERED"
    except Exception:
        pass
    ob.data.materials.append(m)
    ob["texnode"] = t.name
    ob["bsdf"] = bs.name
    return ob


# 灯塔：远处礁石上
LH = Vector((14.0, 46.0, 0.0))
sprite(img("mound.png"), 0.008, (LH.x, LH.y + 0.3, -2.4), "lh_rock", self_emit=0.0)
lh = sprite(img("lighthouse.png"), 0.045, (LH.x, LH.y - 0.2, 0.4), "lighthouse", self_emit=0.6)
lh.visible_shadow = False
LAMP = Vector((LH.x, LH.y - 0.2, 0.4 + 108 * 0.045 * 0.85))
bpy.ops.mesh.primitive_uv_sphere_add(radius=0.35, location=LAMP)
lampball = bpy.context.object
lampball.data.materials.append(emis_mat("lampglow", WARM, 30.0))
lampball.visible_shadow = False
bpy.ops.object.light_add(type="SUN", rotation=(math.radians(60), 0, math.radians(200)))   # 月光：冷、弱，勾出岸和海嗣
moon = bpy.context.object
moon.data.energy = 0.6; moon.data.color = (0.55, 0.7, 0.95)

# 滑动者：前景爬上岸（5 帧循环，约 8 fps），72 重拍被光照住
sl_imgs = [img("slider_%d.png" % i) for i in range(5)]
sl_em = [img("slider_%d_emit.png" % i) for i in range(5)]
SL_PX = 0.04
slider = sprite(sl_imgs[0], SL_PX, (0.6, 3.2, 0.0), "slider", emit_img=sl_em[0], emit_k=0.0, body=0.9)
slider.visible_shadow = False
for f, y in ((0, 4.2), (B(2), 2.2), (B(3), 1.9)):
    slider.location.y = y
    slider.keyframe_insert("location", frame=f)
sl_mat = slider.active_material
sl_tex = sl_mat.node_tree.nodes[slider["texnode"]]
sl_bsdf = sl_mat.node_tree.nodes[slider["bsdf"]]
for f, k in ((0, 0.0), (B(2) - 2, 0.0), (B(2) + 4, 60.0), (B(3), 30.0)):   # 眼睛反光：照住那一刻亮起
    sl_bsdf.inputs["Emission Strength"].default_value = k
    sl_bsdf.inputs["Emission Strength"].keyframe_insert("default_value", frame=f)
emit_tex = [nd for nd in sl_mat.node_tree.nodes if nd.type == "TEX_IMAGE" and nd != sl_tex][0]

# 灯塔光束：聚光灯扫海面，72 重拍停在滑动者身上
bpy.ops.object.light_add(type="SPOT", location=LAMP)
beam = bpy.context.object
beam.data.energy = 60000
beam.data.spot_size = math.radians(5)
beam.data.spot_blend = 0.3
beam.data.color = WARM
try:
    beam.data.volume_factor = 8.0
except Exception:
    pass
beam.data.shadow_soft_size = 0.1
aim = bpy.data.objects.new("aim", None)
sc.collection.objects.link(aim)
tr = beam.constraints.new("TRACK_TO"); tr.target = aim; tr.track_axis = "TRACK_NEGATIVE_Z"; tr.up_axis = "UP_Y"
bpy.ops.object.light_add(type="POINT", location=(0.3, 0.9, 1.4))   # 光束照住的那一刻：暖光打到它正面（灯塔光在它身后，单靠逆光看不清）
hit = bpy.context.object
hit.data.color = WARM; hit.data.shadow_soft_size = 0.8
try:
    hit.data.volume_factor = 0.0
except Exception:
    pass
for f, e in ((0, 0), (B(2) - 2, 0), (B(2) + 3, 320), (B(3), 180)):
    hit.data.energy = e
    hit.data.keyframe_insert("energy", frame=f)
for f, e in ((0, 60000), (B(2) - 4, 60000), (B(2), 9000), (NF, 9000)):   # 照住之后压低，免得直射镜头打白
    beam.data.energy = e
    beam.data.keyframe_insert("energy", frame=f)
for f, p in ((0, (-30, 30, 0)), (B(1), (-8, 12, 0)), (B(2) - 20, (6, 6, 0)), (B(2), (0.6, 2.4, 1.0)), (NF, (0.6, 2.0, 1.0))):
    aim.location = p
    aim.keyframe_insert("location", frame=f)

# ---------------------------------------------------------------- 水下海嗣：近处几只（74）+ 三层潮（75–76 眼睛依次亮）
kinds = [("runner", 6), ("skimmer", 7), ("offspring", 4), ("floater", 5)]
swarm = []
near = [(-3.2, 8.0, -3.6, "skimmer", 0.05), (3.0, 9.5, -5.0, "floater", 0.05), (0.8, 12.0, -2.8, "runner", 0.06)]
for (x, y, z, k, pxm) in near:
    o = sprite(img("%s_0.png" % k), pxm, (x, y, z), "near_" + k, emit_img=img("%s_0_emit.png" % k), emit_k=0.0, body=0.35)
    swarm.append((o, B(4) + 10))
for layer, (ymin, ymax, cnt, on) in enumerate(((14, 26, 60, B(5)), (26, 45, 140, B(5) + 45), (45, 75, 260, B(6)))):
    for i in range(cnt):
        k, nfr = rng.choice(kinds)
        fi = rng.randrange(nfr)
        x = rng.uniform(-28, 28) * (ymax / 40)
        z = rng.uniform(-24, -2)
        y = rng.uniform(ymin, ymax)
        o = sprite(img("%s_%d.png" % (k, fi)), rng.uniform(0.04, 0.07), (x, y, z), "sw", emit_img=img("%s_%d_emit.png" % (k, fi)), emit_k=0.0, body=0.25)
        swarm.append((o, on + rng.randint(0, 30)))
for o, on in swarm:   # 眼睛从暗到亮（0.25 秒）
    bs = o.active_material.node_tree.nodes[o["bsdf"]]
    for f, kk in ((0, 0.0), (on, 0.0), (on + 15, 80.0)):
        bs.inputs["Emission Strength"].default_value = kk
        bs.inputs["Emission Strength"].keyframe_insert("default_value", frame=f)

# 水下的光柱：从海面斜照下来（青）
for x in (-6, 2, 9):
    bpy.ops.object.light_add(type="SPOT", location=(x, 20, 2))
    s = bpy.context.object
    s.data.energy = 6000; s.data.spot_size = math.radians(10); s.data.spot_blend = 0.6; s.data.color = (0.6, 0.9, 1.0)
    try:
        s.data.volume_factor = 3.0
    except Exception:
        pass
    s.rotation_euler = (Vector((x + 3, 30, -20)) - Vector(s.location)).to_track_quat("-Z", "Y").to_euler()

# ---------------------------------------------------------------- 摇臂镜头
cam_d = bpy.data.cameras.new("cam")
cam_d.sensor_fit = "VERTICAL"
cam_d.dof.use_dof = True
cam_d.dof.aperture_fstop = 2.2
cam = bpy.data.objects.new("cam", cam_d)
sc.collection.objects.link(cam)
sc.camera = cam
tgt = bpy.data.objects.new("tgt", None)
sc.collection.objects.link(tgt)
tc_ = cam.constraints.new("TRACK_TO"); tc_.target = tgt; tc_.track_axis = "TRACK_NEGATIVE_Z"; tc_.up_axis = "UP_Y"
KEYS = [  # 帧, 镜头位置, 看向, 竖直视角, 对焦距离
    (0,          (-1.2, -2.6, 0.9),  (1.0, 30, 2.5),   34, 6.0),
    (B(2),       (-1.6, -2.4, 1.0),  (1.6, 4.0, 1.3),  36, 4.8),
    (B(3) - 30,  (0.0, 2.6, 0.35),   (0.4, 12, -0.6),  36, 7.0),
    (B(3) + 20,  (0.0, 4.0, -0.6),   (0.4, 14, -2.2),  38, 7.0),
    (B(4),       (0.0, 4.6, -1.8),   (0.6, 14, -3.4),  40, 6.0),
    (B(5),       (0.0, 3.6, -3.0),   (0.0, 30, -8.0),  50, 14.0),
    (B(7),       (0.0, -2.0, -6.5),  (0.0, 40, -11.0), 72, 30.0),
    (NF,         (0.0, -2.6, -6.8),  (0.0, 40, -11.0), 74, 30.0),
]


def lerp(a, b, u):
    return tuple(x + (y - x) * u for x, y in zip(a, b)) if isinstance(a, tuple) else a + (b - a) * u


def ease(x):
    x = min(1.0, max(0.0, x))
    return x * x * (3 - 2 * x)


for f in range(0, NF + 1, 2):
    for (f0, p0, t0, a0, d0), (f1, p1, t1, a1, d1) in zip(KEYS, KEYS[1:]):
        if f0 <= f <= f1:
            u = ease((f - f0) / (f1 - f0))
            cam.location = lerp(p0, p1, u); tgt.location = lerp(t0, t1, u)
            cam_d.angle_y = math.radians(lerp(a0, a1, u)); cam_d.dof.focus_distance = lerp(d0, d1, u)
            break
    cam.keyframe_insert("location", frame=f); tgt.keyframe_insert("location", frame=f)
    cam_d.keyframe_insert("lens", frame=f); cam_d.dof.keyframe_insert("focus_distance", frame=f)


def _swap(scene, *_):   # 滑动者爬行帧（8 fps）
    i = (scene.frame_current // 8) % 5
    sl_tex.image = sl_imgs[i]
    emit_tex.image = sl_em[i]


bpy.app.handlers.frame_change_pre.append(_swap)

sc.use_nodes = True
cn, cl = sc.node_tree.nodes, sc.node_tree.links
cn.clear()
rl = cn.new("CompositorNodeRLayers")
g = cn.new("CompositorNodeGlare")
try:
    g.glare_type = "BLOOM"
except Exception:
    g.glare_type = "FOG_GLOW"
for nm, v in (("Threshold", 0.6), ("Strength", 0.8), ("Size", 0.7)):
    try:
        g.inputs[nm].default_value = v
    except Exception:
        pass
co = cn.new("CompositorNodeComposite")
cl.new(rl.outputs["Image"], g.inputs["Image"]); cl.new(g.outputs["Image"], co.inputs["Image"])

os.makedirs(OUT, exist_ok=True)
print("PV3D-SHORE NF", NF, "bars", [B(k) for k in range(8)], flush=True)
if RANGE:
    sc.frame_start, sc.frame_end = RANGE
    sc.render.filepath = OUT.replace("\\", "/") + "/s"
    bpy.ops.render.render(animation=True)
else:
    for f in STILLS:
        t0 = time.time()
        sc.frame_set(f)
        sc.render.filepath = OUT.replace("\\", "/") + "/k%04d.png" % f
        bpy.ops.render.render(write_still=True)
        print("PV3D still", f, "%.1f s" % (time.time() - t0), flush=True)
