# -*- coding: utf-8 -*-
"""PV 干员出场 · 3D 水下版（11-08 用户：干员出场要和 3D 开头同一种渲染——近黑深海蓝 + 局部发光）。
本作像素入场帧（原作 Start 动作重绘，data/characters/<id>.json sprites.entry）贴在一块最近邻采样的发光面片上，
悬在深海里：身后一道青色逆光、虚掉的发光丝线和水母；名字是 3D 发光字（中文 + 空心英文 + 职业）。一镜 1 小节。

  blender -b --python tools/promo/pv3d_ops.py -- <干员 id> <中文名> <英文名> <职业> <输出帧目录> [帧,帧,… | 起帧 止帧]
"""
import json, math, os, random, sys, time
import bpy
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
OP, NAME, EN, CLS, OUT = argv[:5]
STILLS = [int(x) for x in argv[5].split(",")] if len(argv) > 5 and "," in argv[5] else None
F0 = int(argv[5]) if len(argv) > 5 and not STILLS else 0
F1 = int(argv[6]) if len(argv) > 6 else None
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
ART = os.path.join(ROOT, "game", "art", "operators", OP)
FONT = os.path.join(ROOT, "game", "fonts", "ui.ttf")   # ui_heavy.ttf 的「月」在 Blender 里破面，ui_fallback.otf 读不出
FONT_EN = os.path.join(ROOT, "game", "fonts", "montserrat_bold.ttf")

FPS = 60
BAR = 4 * 60 / 145.99
NF = int(round(BAR * FPS))
CYAN = (0.35, 0.85, 1.0, 1)


def ease(x):
    x = min(1.0, max(0.0, x))
    return 1 - (1 - x) ** 3


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
             ("volumetric_end", 40.0), ("use_shadows", True)):
    try:
        setattr(ee, k, v)
    except Exception:
        pass
sc.render.use_motion_blur = True
sc.render.motion_blur_shutter = 0.35
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
    o = n.new("ShaderNodeOutputMaterial")
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
vol.inputs["Density"].default_value = 0.04
vol.inputs["Anisotropy"].default_value = 0.6
wl.new(vol.outputs[0], wout.inputs["Volume"])

# ---------------------------------------------------------------- 像素入场帧：拆成单帧图，按时间换贴图
d = json.load(open(os.path.join(ROOT, "game", "data", "characters", OP + ".json"), encoding="utf-8"))["sprites"]["entry"]
strip = bpy.data.images.load(os.path.join(ART, d["tex"] + "@2x.png"))
nfr = int(d["frames"])
durs = d.get("frame_durations") or [1.0 / float(d.get("fps", 10))] * nfr
fw, fh = strip.size[0] // nfr, strip.size[1]
px = list(strip.pixels)
frame_imgs = []
for i in range(nfr):
    im = bpy.data.images.new("f%d" % i, fw, fh, alpha=True)
    buf = []
    for y in range(fh):
        row0 = (y * strip.size[0] + i * fw) * 4
        buf.extend(px[row0: row0 + fw * 4])
    im.pixels = buf
    im.pack()
    frame_imgs.append(im)
SP_H = 3.0   # 面片高（米）
SP_W = SP_H * fw / fh
bpy.ops.mesh.primitive_plane_add(size=1)
sp = bpy.context.object
sp.scale = (SP_W, SP_H, 1)
sp.rotation_euler = (math.radians(90), 0, 0)
foot = (d["foot"][0] * 2 / fw, d["foot"][1] * 2 / fh)   # 脚底在帧内的比例
sp.location = ((0.5 - foot[0]) * SP_W, 0, (foot[1] - 0.5) * SP_H)   # 脚底落在原点（贴图上方 = +Z）
spm, n, l, o = mat("sprite")
tx = n.new("ShaderNodeTexImage")
tx.interpolation = "Closest"
tx.image = frame_imgs[0]
em = n.new("ShaderNodeEmission"); em.inputs["Strength"].default_value = 1.15
tr = n.new("ShaderNodeBsdfTransparent")
mx = n.new("ShaderNodeMixShader")
l.new(tx.outputs["Color"], em.inputs["Color"])
l.new(tx.outputs["Alpha"], mx.inputs["Fac"]); l.new(tr.outputs[0], mx.inputs[1]); l.new(em.outputs[0], mx.inputs[2])
l.new(mx.outputs[0], o.inputs["Surface"])
try:
    spm.surface_render_method = "DITHERED"
except Exception:
    pass
sp.data.materials.append(spm)
sp.visible_shadow = False
# 身后的发光轮廓（同一帧放大一点、只取 alpha 发青光）→ 像水下逆光勾边
bpy.ops.mesh.primitive_plane_add(size=1)
gl = bpy.context.object
gl.scale = (SP_W * 1.04, SP_H * 1.02, 1)
gl.rotation_euler = sp.rotation_euler
gl.location = sp.location + Vector((0, 0.03, 0.01))
glm, n2, l2, o2 = mat("glow")
tx2 = n2.new("ShaderNodeTexImage"); tx2.interpolation = "Closest"; tx2.image = frame_imgs[0]
em2 = n2.new("ShaderNodeEmission"); em2.inputs["Color"].default_value = CYAN; em2.inputs["Strength"].default_value = 6.0
tr2 = n2.new("ShaderNodeBsdfTransparent"); mx2 = n2.new("ShaderNodeMixShader")
l2.new(tx2.outputs["Alpha"], mx2.inputs["Fac"]); l2.new(tr2.outputs[0], mx2.inputs[1]); l2.new(em2.outputs[0], mx2.inputs[2])
l2.new(mx2.outputs[0], o2.inputs["Surface"])
try:
    glm.surface_render_method = "BLENDED"
except Exception:
    pass
gl.data.materials.append(glm)
gl.visible_shadow = False
t_in = 0.05
ends = []
acc = 0.0
for dd in durs:
    acc += dd
    ends.append(acc)
LAND = t_in + ends[-1]


def frame_at(t):
    lt = t - t_in
    for i, e in enumerate(ends):
        if lt < e:
            return i
    return nfr - 1


# 换贴图靠驱动不方便 → 每帧渲染前由 frame_change_pre 换（渲染时也会调用）
def _swap(scene, *_):
    t = scene.frame_current / FPS
    i = frame_at(t)
    tx.image = frame_imgs[i]
    tx2.image = frame_imgs[i]


bpy.app.handlers.frame_change_pre.append(_swap)

# ---------------------------------------------------------------- 落地：脚下一圈青色冲击环 + 亮一下
ring_m = emissive("ring", CYAN, 12.0, blend=True)
bpy.ops.mesh.primitive_torus_add(major_radius=0.5, minor_radius=0.012, major_segments=96, minor_segments=8)
ring = bpy.context.object
ring.data.materials.append(ring_m)
ring_em = [nd for nd in ring_m.node_tree.nodes if nd.type == "EMISSION"][0]
for f in range(NF + 1):
    t = f / FPS
    q = (t - LAND) / 0.4
    if q < 0:
        ring.scale = (0.001, 0.001, 0.001)
    else:
        s = 0.3 + 2.6 * ease(q)
        ring.scale = (s, s * 0.32, s)   # 透视里压扁成椭圆
    ring.keyframe_insert("scale", frame=f)
    ring_em.inputs["Strength"].default_value = 12.0 * max(0.0, 1 - max(q, 0))
    ring_em.inputs["Strength"].keyframe_insert("default_value", frame=f)

# ---------------------------------------------------------------- 名字：3D 发光字
txt_m = emissive("txt", (0.92, 0.97, 1.0, 1), 3.2)
en_m = emissive("en", CYAN, 4.0)
line_m = emissive("line", CYAN, 8.0)


def text(body, font, size, loc, m, extrude=0.0):
    cu = bpy.data.curves.new("t", "FONT")
    cu.body = body
    cu.font = bpy.data.fonts.load(font)
    cu.size = size
    cu.align_x = "LEFT"
    cu.extrude = extrude
    ob = bpy.data.objects.new("t", cu)
    sc.collection.objects.link(ob)
    ob.location = loc
    ob.rotation_euler = (math.radians(90), 0, 0)
    cu.materials.append(m)
    return ob


TX = 1.25
name = text(NAME, FONT, 0.62, (TX, -0.3, 1.55), txt_m)
en = text(EN, FONT_EN, 0.26, (TX, -0.3, 1.12), en_m)
cls = text(CLS, FONT, 0.2, (TX + 0.05, -0.3, 0.72), txt_m)
bpy.ops.mesh.primitive_cube_add(size=1, location=(TX, -0.3, 1.0))
line = bpy.context.object
line.data.materials.append(line_m)
for f in range(NF + 1):
    t = f / FPS
    k = ease((t - (LAND - 0.1)) / 0.25)
    for ob, dy in ((name, 0.0), (en, 0.06), (cls, 0.1)):
        kk = ease((t - (LAND - 0.1) - dy) / 0.25)
        ob.location.x = TX + 0.6 * (1 - kk)
        ob.scale = (1, 1, 1) if kk > 0.001 else (0.001, 0.001, 0.001)
        ob.keyframe_insert("location", frame=f)
        ob.keyframe_insert("scale", frame=f)
    line.scale = (max(0.001, 1.8 * k), 0.005, 0.01)
    line.location.x = TX + 0.9 * k
    line.keyframe_insert("scale", frame=f)
    line.keyframe_insert("location", frame=f)

# ---------------------------------------------------------------- 光：背后青色逆光 + 顶光光束
bpy.ops.object.light_add(type="AREA", location=(-0.2, 2.0, 2.4))
rim = bpy.context.object
rim.data.energy = 300; rim.data.size = 1.5; rim.data.color = (0.45, 0.85, 1.0)
try:
    rim.data.volume_factor = 0.05
except Exception:
    pass
rim.rotation_euler = (Vector((0, 0, 1.2)) - Vector(rim.location)).to_track_quat("-Z", "Y").to_euler()
bpy.ops.object.light_add(type="SPOT", location=(-1.0, 1.5, 7.0))
shaft = bpy.context.object
shaft.data.energy = 300; shaft.data.spot_size = math.radians(16); shaft.data.spot_blend = 0.6; shaft.data.color = (0.55, 0.9, 1.0)
try:
    shaft.data.volume_factor = 4.0
except Exception:
    pass
shaft.rotation_euler = (Vector((0, 2.0, -1.0)) - Vector(shaft.location)).to_track_quat("-Z", "Y").to_euler()

# ---------------------------------------------------------------- 背景：虚掉的发光丝线 + 远处水母光斑 + 颗粒
fil_m = emissive("fil", (0.4, 0.88, 1.0, 1), 1.4)
rf = random.Random(hash(OP) & 0xffff)
for k in range(9):
    cu = bpy.data.curves.new("fil", "CURVE"); cu.dimensions = "3D"; cu.bevel_depth = rf.uniform(0.003, 0.007)
    spl = cu.splines.new("BEZIER"); spl.bezier_points.add(5)
    z0, y0, ph = rf.uniform(-1.5, 3.5), rf.uniform(3.0, 8.0), rf.uniform(0, 6.28)
    for j, bp in enumerate(spl.bezier_points):
        t = j / 5
        bp.co = (-6 + 12 * t, y0 + 0.5 * math.sin(t * 4 + ph), z0 + 0.5 * math.sin(t * 3 + ph))
        bp.handle_left_type = bp.handle_right_type = "AUTO"
    ob = bpy.data.objects.new("fil", cu); sc.collection.objects.link(ob); cu.materials.append(fil_m)
    for f in (0, NF):
        ob.location.x = 0 if f == 0 else rf.uniform(-0.4, 0.4)
        ob.keyframe_insert("location", frame=f)
jm = emissive("jb", CYAN, 0.8, blend=True)
for k in range(6):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=rf.uniform(0.15, 0.3), segments=24, ring_count=12, location=(rf.uniform(-4, 4), rf.uniform(4, 9), rf.uniform(0, 3.5)))
    b = bpy.context.object
    b.scale = (1, 1, 0.6)
    b.data.materials.append(jm)
mote_m = emissive("mote", (0.75, 0.95, 1.0, 1), 3.0)
bpy.ops.mesh.primitive_ico_sphere_add(radius=0.006, subdivisions=1, location=(0, 0, -90))
mote = bpy.context.object
mote.data.materials.append(mote_m)
bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 3, 1))
e = bpy.context.object
e.scale = (10, 10, 6)
ps = e.modifiers.new("m", "PARTICLE_SYSTEM").particle_system.settings
ps.count = 1500; ps.frame_start = -900; ps.frame_end = NF; ps.lifetime = 2000
ps.emit_from = "VOLUME"; ps.normal_factor = 0; ps.factor_random = 0.04; ps.effector_weights.gravity = -0.006
ps.render_type = "OBJECT"; ps.instance_object = mote; ps.size_random = 0.8
e.show_instancer_for_render = False; e.visible_camera = False; e.visible_shadow = False

# ---------------------------------------------------------------- 镜头：略仰、缓推，焦点在人身上
cam_d = bpy.data.cameras.new("cam")
cam_d.sensor_fit = "VERTICAL"
cam_d.angle_y = math.radians(32)
cam_d.dof.use_dof = True
cam_d.dof.aperture_fstop = 1.8
cam = bpy.data.objects.new("cam", cam_d)
sc.collection.objects.link(cam)
sc.camera = cam
for f in range(NF + 1):
    t = f / FPS
    u = ease(t / BAR)
    sh = 0.0
    if 0 <= t - LAND < 4 / FPS:
        sh = (0.03, -0.02, 0.015, -0.008)[int((t - LAND) * FPS)]
    cam.location = (1.0 + sh, -6.4 + 0.5 * u, 0.85)
    cam.rotation_euler = (math.radians(91), 0, math.radians(0))
    cam.keyframe_insert("location", frame=f)
    cam.keyframe_insert("rotation_euler", frame=f)
    cam_d.dof.focus_distance = 6.4 - 0.5 * u
    cam_d.dof.keyframe_insert("focus_distance", frame=f)

# 合成：bloom + 色散（同 pv3d_deep）
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
ld = cn.new("CompositorNodeLensdist")
try:
    ld.inputs["Dispersion"].default_value = 0.02
except Exception:
    pass
co = cn.new("CompositorNodeComposite")
cl.new(rl.outputs["Image"], g.inputs["Image"]); cl.new(g.outputs["Image"], ld.inputs["Image"]); cl.new(ld.outputs["Image"], co.inputs["Image"])

os.makedirs(OUT, exist_ok=True)
sc.frame_start = F0
sc.frame_end = F1 if F1 is not None else NF - 1
print("PV3D-OPS", OP, "frames", NF, "land", round(LAND, 3), flush=True)
if STILLS:
    for f in STILLS:
        t0 = time.time()
        sc.frame_set(f)
        sc.render.filepath = OUT.replace("\\", "/") + "/%s_s%04d.png" % (OP, f)
        bpy.ops.render.render(write_still=True)
        print("PV3D still", f, "%.1f s" % (time.time() - t0), flush=True)
else:
    sc.render.filepath = OUT.replace("\\", "/") + "/%s_f" % OP
    bpy.ops.render.render(animation=True)
