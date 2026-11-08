# -*- coding: utf-8 -*-
"""PV 3D 开头 · Blender 版（11-08，用户嫌 Godot 版粗糙）：海底场景 + 游戏招募卡做成的银边实体卡，EEVEE 渲染。

  D:/blender/blender-4.5.15-windows-x64/blender.exe -b --python tools/promo/pv3d_blender.py -- <卡面目录> <素材目录> <输出帧目录> [起帧 止帧]

卡面目录：c0.png … c8.png（从实机录像按原尺寸抠的招募卡 / 升级卡）+ _back.png；素材目录：Poly Haven CC0（礁石 / 岩壁 / 沙地）。
时长 = battle2 第 70–77 小节（7 小节 = 11.507 秒，60 帧 = 691 帧），运镜同 pv3d.gd：
  0–2 小节   卡片在海底上方翻转下落，镜头缓降前推
  2–4 小节   低机位贴着海床横移，一排卡从卡背朝下平躺依次立起（八分音符一张）
  4 小节     重拍：斯卡蒂的招募卡砸到镜头前，冷光一闪；之后镜头推进卡面，末 0.35 秒提亮到白切实机
坐标：Blender Z 向上，镜头朝 +Y 看（Godot 的 (x, y, z) = 这里的 (x, -z, y)）。
"""
import math, os, random, sys
import bpy
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
CARDS, ASSETS, OUT = argv[0], argv[1], argv[2]
STILLS = [int(x) for x in argv[3].split(",")] if len(argv) > 3 and "," in argv[3] else None   # 试渲：只出这几帧
F0 = int(argv[3]) if len(argv) > 3 and not STILLS else 0
F1 = int(argv[4]) if len(argv) > 4 else None

FPS = 60
BAR = 4 * 60 / 145.99
DUR = 7 * BAR
NF = int(round(DUR * FPS)) + 1
CW, CH, CT = 1.0, 1.405, 0.03
FLOOR = -1.0


def ease(x):
    x = min(1.0, max(0.0, x))
    return 1 - (1 - x) ** 3


# ---------------------------------------------------------------- 场景
bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
sc.render.fps = FPS
sc.frame_start, sc.frame_end = 0, NF - 1
sc.render.resolution_x, sc.render.resolution_y = 1920, 1080
sc.render.resolution_percentage = 100
for eng in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE"):
    try:
        sc.render.engine = eng
        break
    except TypeError:
        pass
ee = sc.eevee
ee.taa_render_samples = 48
for k, v in (("use_raytracing", True), ("volumetric_tile_size", "4"), ("volumetric_samples", 64), ("use_volumetric_shadows", True),
             ("volumetric_end", 160.0), ("use_shadows", True), ("shadow_ray_count", 2), ("volumetric_ray_depth", 8)):
    try:
        setattr(ee, k, v)
    except Exception as e:
        print("eevee skip", k, e)
sc.render.use_motion_blur = True
try:
    sc.render.motion_blur_shutter = 0.45
except Exception:
    pass
sc.view_settings.view_transform = "AgX"
try:
    sc.view_settings.look = "AgX - Medium High Contrast"
except Exception:
    pass
sc.render.image_settings.file_format = "PNG"
sc.render.film_transparent = False


def mat(name):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    n, l = m.node_tree.nodes, m.node_tree.links
    if "Principled BSDF" not in n:
        n.clear()
        o = n.new("ShaderNodeOutputMaterial")
        b = n.new("ShaderNodeBsdfPrincipled")
        b.name = "Principled BSDF"
        l.new(b.outputs[0], o.inputs["Surface"])
    return m, n, l


# 世界：灰蓝水体 + 体积散射（光束靠它）
world = bpy.data.worlds.new("sea")
sc.world = world
world.use_nodes = True
wn, wl = world.node_tree.nodes, world.node_tree.links
wn.clear()
wout = wn.new("ShaderNodeOutputWorld")
wbg = wn.new("ShaderNodeBackground")
wl.new(wbg.outputs[0], wout.inputs["Surface"])
wbg.inputs["Color"].default_value = (0.16, 0.22, 0.26, 1)
wbg.inputs["Strength"].default_value = 2.5
vol = wn.new("ShaderNodeVolumePrincipled")
vol.inputs["Color"].default_value = (0.55, 0.72, 0.82, 1)
vol.inputs["Density"].default_value = 0.04
vol.inputs["Anisotropy"].default_value = 0.55
wl.new(vol.outputs[0], wout.inputs["Volume"])


def img(path):
    return bpy.data.images.load(path, check_existing=True)


# ---------------------------------------------------------------- 海床
bpy.ops.mesh.primitive_plane_add(size=90, location=(0, 10, FLOOR))
floor = bpy.context.object
floor.name = "seabed"
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.subdivide(number_cuts=180)
bpy.ops.object.mode_set(mode="OBJECT")
tex = bpy.data.textures.new("dunes", "CLOUDS")
tex.noise_scale = 6.0
tex.noise_depth = 3
dm = floor.modifiers.new("dunes", "DISPLACE")
dm.texture = tex
dm.strength = 1.6
dm.mid_level = 0.55
# 镜头附近压平：用顶点组按到镜头的距离加权
vg = floor.vertex_groups.new(name="far")
for v in floor.data.vertices:
    w = floor.matrix_world @ v.co
    d = math.hypot(w.x, w.y - 1.0)
    vg.add([v.index], min(1.0, max(0.0, (d - 4.0) / 10.0)), "REPLACE")
dm.vertex_group = "far"
sd = os.path.join(ASSETS, "coast_sand_01")
m, n, l = mat("sand")
bsdf = n["Principled BSDF"]
tc = n.new("ShaderNodeTexCoord")
mp = n.new("ShaderNodeMapping")
mp.inputs["Scale"].default_value = (14, 14, 14)
l.new(tc.outputs["UV"], mp.inputs["Vector"])
dif = n.new("ShaderNodeTexImage"); dif.image = img(os.path.join(sd, "coast_sand_01_diff_2k.png"))
nor = n.new("ShaderNodeTexImage"); nor.image = img(os.path.join(sd, "coast_sand_01_nor_gl_2k.png")); nor.image.colorspace_settings.name = "Non-Color"
rou = n.new("ShaderNodeTexImage"); rou.image = img(os.path.join(sd, "coast_sand_01_rough_2k.png")); rou.image.colorspace_settings.name = "Non-Color"
for t in (dif, nor, rou):
    l.new(mp.outputs[0], t.inputs["Vector"])
hsv = n.new("ShaderNodeHueSaturation")
hsv.inputs["Saturation"].default_value = 0.35
hsv.inputs["Value"].default_value = 0.75
l.new(dif.outputs[0], hsv.inputs["Color"])
l.new(hsv.outputs[0], bsdf.inputs["Base Color"])
l.new(rou.outputs[0], bsdf.inputs["Roughness"])
nm = n.new("ShaderNodeNormalMap")
l.new(nor.outputs[0], nm.inputs["Color"])
l.new(nm.outputs[0], bsdf.inputs["Normal"])
# 焦散：4D Voronoi（W 随帧走）的边距 → 细亮网纹，当自发光叠在沙上
vor = n.new("ShaderNodeTexVoronoi")
vor.voronoi_dimensions = "4D"
vor.feature = "DISTANCE_TO_EDGE"
vor.inputs["Scale"].default_value = 0.9
dn = n.new("ShaderNodeTexNoise"); dn.inputs["Scale"].default_value = 0.35; dn.inputs["Detail"].default_value = 2
dmx = n.new("ShaderNodeMix"); dmx.data_type = "VECTOR"; dmx.inputs["Factor"].default_value = 0.55
l.new(tc.outputs["Object"], dmx.inputs[4]); l.new(dn.outputs["Color"], dmx.inputs[5])
l.new(tc.outputs["Object"], dn.inputs["Vector"])
l.new(dmx.outputs[1], vor.inputs["Vector"])
vor.inputs["W"].default_value = 0.0
vor.inputs["W"].keyframe_insert("default_value", frame=0)
vor.inputs["W"].default_value = 2.2
vor.inputs["W"].keyframe_insert("default_value", frame=NF)
cr = n.new("ShaderNodeMapRange")
cr.inputs["From Min"].default_value = 0.0
cr.inputs["From Max"].default_value = 0.035
cr.inputs["To Min"].default_value = 0.22
cr.inputs["To Max"].default_value = 0.0
l.new(vor.outputs["Distance"], cr.inputs["Value"])
l.new(cr.outputs[0], bsdf.inputs["Emission Strength"])
bsdf.inputs["Emission Color"].default_value = (0.55, 0.75, 0.85, 1)
floor.data.materials.append(m)
bpy.ops.object.shade_smooth()

# ---------------------------------------------------------------- Poly Haven 礁石 / 岩壁
rock_src = {}
for a in ("boulder_01", "coast_rocks_01", "coast_rocks_05", "rock_face_01", "sand_rocks_small_01"):
    d = os.path.join(ASSETS, a)
    bl = [f for f in os.listdir(d) if f.endswith(".blend")][0]
    with bpy.data.libraries.load(os.path.join(d, bl), link=False) as (src, dst):
        dst.objects = [o for o in src.objects]
    objs = [o for o in dst.objects if o is not None and o.type == "MESH" and ("LOD" not in o.name or "LOD0" in o.name)]   # 只要最精细一档
    rock_src[a] = objs
    for o in objs:
        for slot in o.material_slots:
            if slot.material and slot.material.use_nodes:
                for nd in slot.material.node_tree.nodes:
                    if nd.type == "TEX_IMAGE" and nd.image and nd.image.filepath.startswith("//"):
                        nd.image.filepath = os.path.join(d, nd.image.filepath[2:])
for imgb in bpy.data.images:
    imgb.reload()


def place(a, loc, rot_z, size):
    """把一套礁石按包围盒归一：最长边 = size 米，底面中点落在 loc"""
    objs = rock_src[a]
    pts = [o.matrix_world @ Vector(c) for o in objs for c in o.bound_box]
    lo = Vector([min(p[i] for p in pts) for i in range(3)])
    hi = Vector([max(p[i] for p in pts) for i in range(3)])
    k = size / max(hi - lo)
    base = Vector(((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, lo.z))
    root = bpy.data.objects.new("rock_" + a, None)
    sc.collection.objects.link(root)
    for o in objs:
        c = o.copy()
        c.data = o.data
        sc.collection.objects.link(c)
        c.parent = root
        c.matrix_parent_inverse.identity()
        c.matrix_basis = o.matrix_world.copy()
        c.location = c.location - base
    root.location = Vector(loc)
    root.rotation_euler = (0, 0, rot_z)
    root.scale = (k, k, k)


rng = random.Random(21)
for i in range(14):   # 两侧散落的礁石（最长边 1–3.5 米）
    side = -1 if i % 2 == 0 else 1
    a = rng.choice(["boulder_01", "coast_rocks_01", "coast_rocks_05", "sand_rocks_small_01"])
    place(a, (side * rng.uniform(3.4, 13), rng.uniform(3, 20), FLOOR - 0.2), rng.uniform(0, 6.28), rng.uniform(1.0, 3.5))
for x, y, sz in ((-15, 30, 11), (13, 34, 13), (2, 44, 15), (-6, 52, 14)):   # 远处大礁石剪影
    place(rng.choice(["boulder_01", "coast_rocks_05"]), (x, y, FLOOR - 0.8), rng.uniform(0, 6.28), sz)

# ---------------------------------------------------------------- 海草
km, kn, kl = mat("kelp")
kb = kn["Principled BSDF"]
kb.inputs["Base Color"].default_value = (0.05, 0.1, 0.09, 1)
kb.inputs["Roughness"].default_value = 0.6
kb.inputs["Transmission Weight"].default_value = 0.3
km.use_backface_culling = False
for i in range(54):
    hgt = rng.uniform(1.8, 5.2)
    w = rng.uniform(0.06, 0.14)
    seg = 18
    verts, faces = [], []
    for j in range(seg + 1):
        t = j / seg
        ww = w * (1 - 0.8 * t)
        verts += [(t * hgt, -ww / 2, 0), (t * hgt, ww / 2, 0)]
        if j:
            b = 2 * (j - 1)
            faces.append((b, b + 1, b + 3, b + 2))
    me = bpy.data.meshes.new("kelp")
    me.from_pydata(verts, [], faces)
    ob = bpy.data.objects.new("kelp", me)
    sc.collection.objects.link(ob)
    me.materials.append(km)
    side = -1 if i % 2 == 0 else 1
    ob.location = (side * rng.uniform(2.4, 12) + rng.uniform(-0.5, 0.5), rng.uniform(1.5, 18), FLOOR - 0.05)
    ob.rotation_euler = (rng.uniform(-0.1, 0.1), -math.pi / 2 + rng.uniform(-0.12, 0.12), rng.uniform(0, 6.28))
    bd = ob.modifiers.new("sway", "SIMPLE_DEFORM")
    bd.deform_method = "BEND"
    bd.deform_axis = "Z"
    ph = rng.uniform(0, 6.28)
    for fr in range(0, NF + 12, 12):
        bd.angle = math.radians(26) * math.sin(fr / FPS * 1.1 + ph)
        bd.keyframe_insert("angle", frame=fr)

# ---------------------------------------------------------------- 水面 + 光束遮罩
bpy.ops.mesh.primitive_plane_add(size=140, location=(0, 12, 9.5))
surf = bpy.context.object
sm, sn, sl = mat("surface")
sb = sn["Principled BSDF"]
sv = sn.new("ShaderNodeTexVoronoi"); sv.voronoi_dimensions = "4D"; sv.feature = "DISTANCE_TO_EDGE"; sv.inputs["Scale"].default_value = 0.35
sv.inputs["W"].default_value = 0; sv.inputs["W"].keyframe_insert("default_value", frame=0)
sv.inputs["W"].default_value = 1.5; sv.inputs["W"].keyframe_insert("default_value", frame=NF)
sr = sn.new("ShaderNodeMapRange"); sr.inputs["From Max"].default_value = 0.08; sr.inputs["To Min"].default_value = 4.0; sr.inputs["To Max"].default_value = 0.6
sl.new(sv.outputs["Distance"], sr.inputs["Value"])
sl.new(sr.outputs[0], sb.inputs["Emission Strength"])
sb.inputs["Emission Color"].default_value = (0.7, 0.85, 0.95, 1)
sb.inputs["Base Color"].default_value = (0.1, 0.15, 0.18, 1)
surf.data.materials.append(sm)
surf.visible_shadow = False
# 光束遮罩：水面下一层带孔的板，太阳从孔里漏下来在雾里成光束
bpy.ops.mesh.primitive_plane_add(size=140, location=(0, 12, 8.5))
gobo = bpy.context.object
gm, gn, gl = mat("gobo")
gbs = gn["Principled BSDF"]
gnz = gn.new("ShaderNodeTexNoise"); gnz.inputs["Scale"].default_value = 0.45; gnz.inputs["Detail"].default_value = 3
gcr = gn.new("ShaderNodeMapRange"); gcr.inputs["From Min"].default_value = 0.5; gcr.inputs["From Max"].default_value = 0.56
gl.new(gnz.outputs["Fac"], gcr.inputs["Value"])
gl.new(gcr.outputs[0], gbs.inputs["Alpha"])
gbs.inputs["Base Color"].default_value = (0, 0, 0, 1)
try:
    gm.surface_render_method = "DITHERED"
except Exception:
    gm.blend_method = "CLIP"
gobo.data.materials.append(gm)
gobo.visible_camera = False

# ---------------------------------------------------------------- 灯
bpy.ops.object.light_add(type="SUN", rotation=(math.radians(14), math.radians(-8), 0))
sun = bpy.context.object
sun.data.energy = 9.0
sun.data.color = (0.9, 0.96, 1.0)
sun.data.angle = math.radians(1.5)
try:
    sun.data.volume_factor = 3.0
except Exception:
    pass
bpy.ops.object.light_add(type="POINT", location=(0, -0.2, 0.6))
flash = bpy.context.object
flash.data.color = (0.75, 0.9, 1.0)
flash.data.shadow_soft_size = 0.4
bpy.ops.object.light_add(type="AREA", location=(-3, -4, 2.5))   # 卡面补光
fill = bpy.context.object
fill.data.energy = 1500
fill.data.size = 4
fill.data.color = (0.8, 0.9, 1.0)
fill.rotation_euler = (math.radians(70), 0, math.radians(-35))

# ---------------------------------------------------------------- 卡
faces_img = []
i = 0
while os.path.exists(os.path.join(CARDS, "c%d.png" % i)):
    faces_img.append(img(os.path.join(CARDS, "c%d.png" % i)))
    i += 1
back_img = img(os.path.join(CARDS, "_back.png"))
silver, sn2, sl2 = mat("silver")
sb2 = sn2["Principled BSDF"]
sb2.inputs["Base Color"].default_value = (0.8, 0.84, 0.88, 1)
sb2.inputs["Metallic"].default_value = 1.0
sb2.inputs["Roughness"].default_value = 0.22


def face_mat(im, k):
    m, n, l = mat("face")
    b = n["Principled BSDF"]
    t = n.new("ShaderNodeTexImage")
    t.image = im
    l.new(t.outputs[0], b.inputs["Base Color"])
    l.new(t.outputs[0], b.inputs["Emission Color"])
    b.inputs["Emission Strength"].default_value = k
    b.inputs["Roughness"].default_value = 0.35
    b.inputs["Coat Weight"].default_value = 0.6   # 卡面覆膜的一层高光
    b.inputs["Coat Roughness"].default_value = 0.08
    return m


face_mats = [face_mat(im, 1.1) for im in faces_img]
back_mat = face_mat(back_img, 0.15)


def make_card(idx):
    """原点在卡底边中点，正面朝 -Y"""
    bpy.ops.mesh.primitive_cube_add(size=1)
    body = bpy.context.object
    body.scale = (CW, CT, CH)
    bpy.ops.object.transform_apply(scale=True)
    body.location = (0, 0, CH / 2)
    bv = body.modifiers.new("bevel", "BEVEL")
    bv.width = 0.01
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
        q.location = (0, side * (CT / 2 + 0.0015), CH / 2)
        q.data.materials.append(mt)
        q.parent = root
    return root


def vis(root, frames_on):
    """frames_on(f) → 是否可见；按每帧插 hide_render 关键帧（只在切换处插）"""
    last = None
    for f in range(NF):
        on = frames_on(f)
        if on != last:
            for o in [root] + list(root.children):
                o.hide_render = not on
                o.keyframe_insert("hide_render", frame=f)
            last = on


S1, S2 = int(2 * BAR * FPS), int(4 * BAR * FPS)
fall = []
r2 = random.Random(11)
for k in range(22):
    c = make_card(k)
    p0 = Vector((r2.uniform(-4.5, 4.5), -r2.uniform(-7.0, 1.5), r2.uniform(-0.5, 5.5)))
    r0 = Vector([math.radians(r2.uniform(-180, 180)) for _ in range(3)])
    w = Vector([math.radians(r2.uniform(-60, 60)) for _ in range(3)])
    v = r2.uniform(0.35, 0.7)
    fall.append(c)
    for f in range(0, S1 + 2, 2):
        t = f / FPS
        c.location = p0 + Vector((0, 0, -v * t))
        c.rotation_euler = r0 + w * t
        c.keyframe_insert("location", frame=f)
        c.keyframe_insert("rotation_euler", frame=f)
    vis(c, lambda f: f < S1)
row = []
for k in range(9):
    c = make_card(k)
    x = (k - 4) * 1.22
    t_up = BAR * 2 + 0.25 + k * (BAR / 8)
    for f in range(S1 - 2, NF, 2):
        kk = ease((f / FPS - t_up) / 0.28)
        c.location = (x, 1.0, FLOOR + 0.01)
        c.rotation_euler = (math.radians(90) * (1 - kk), 0, 0)   # 卡背朝上平躺 → 立起翻出正面
        c.keyframe_insert("location", frame=f)
        c.keyframe_insert("rotation_euler", frame=f)
    vis(c, lambda f: f >= S1)
hero = make_card(5)   # 斯卡蒂
for f in range(S2 - 2, NF):
    lt = f / FPS - 4 * BAR
    dk = ease(lt / 0.16)
    hero.location = (0, -0.9, FLOOR + 2.6 * (1 - dk))
    hero.rotation_euler = (0, math.radians(8) * (1 - dk), 0)
    hero.keyframe_insert("location", frame=f)
    hero.keyframe_insert("rotation_euler", frame=f)
vis(hero, lambda f: f >= S2)

# ---------------------------------------------------------------- 水母（发光半透明伞 + 触须）
jm, jn, jl = mat("jelly")
jb = jn["Principled BSDF"]
jb.inputs["Base Color"].default_value = (0.5, 0.75, 1.0, 1)
jb.inputs["Emission Color"].default_value = (0.35, 0.7, 1.0, 1)
jb.inputs["Emission Strength"].default_value = 0.8
jb.inputs["Alpha"].default_value = 0.3
jb.inputs["Transmission Weight"].default_value = 0.6
try:
    jm.surface_render_method = "BLENDED"
except Exception:
    jm.blend_method = "BLEND"
r3 = random.Random(5)
for k in range(8):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.22, segments=24, ring_count=12)
    bell = bpy.context.object
    bell.scale = (1, 1, 0.62)
    bell.data.materials.append(jm)
    bpy.ops.object.shade_smooth()
    p = Vector((r3.uniform(-6, 6), r3.uniform(3, 12), r3.uniform(-0.5, 4.0)))
    for tk in range(7):
        bpy.ops.mesh.primitive_cylinder_add(radius=0.0025, depth=0.8, vertices=5)
        tn = bpy.context.object
        a = tk / 7 * 6.28
        tn.location = (math.cos(a) * 0.12, math.sin(a) * 0.12, -0.42)
        tn.data.materials.append(jm)
        tn.parent = bell
    sp, ph = r3.uniform(0.08, 0.2), r3.uniform(0, 6.28)
    for f in range(0, NF + 6, 6):
        t = f / FPS
        bell.location = p + Vector((0.15 * math.sin(t * 0.7 + ph), 0, sp * t + 0.05 * math.sin(t * 2.4 + ph)))
        s = 1 + 0.08 * math.sin(t * 2.4 + ph)
        bell.scale = (s, s, 0.62 / s)
        bell.keyframe_insert("location", frame=f)
        bell.keyframe_insert("scale", frame=f)

# ---------------------------------------------------------------- 气泡
bm2, bn2, bl2 = mat("bubble")
bb = bn2["Principled BSDF"]
bb.inputs["Emission Color"].default_value = (0.9, 0.97, 1.0, 1)
bb.inputs["Emission Strength"].default_value = 1.2
bb.inputs["Base Color"].default_value = (0.9, 0.95, 1.0, 1)
bpy.ops.mesh.primitive_ico_sphere_add(radius=0.012, subdivisions=1, location=(0, 0, -50))
bub = bpy.context.object
bub.data.materials.append(bm2)
bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 4, 2.5))
em = bpy.context.object
em.scale = (18, 18, 7)
em.visible_camera = False
em.visible_shadow = False
ps = em.modifiers.new("bubbles", "PARTICLE_SYSTEM").particle_system.settings
ps.count = 2200
ps.frame_start = -900
ps.frame_end = NF
ps.lifetime = 1600
ps.emit_from = "VOLUME"
ps.normal_factor = 0
ps.factor_random = 0.08
ps.effector_weights.gravity = -0.015
ps.render_type = "OBJECT"
ps.instance_object = bub
ps.particle_size = 1.0
ps.size_random = 0.7
em.show_instancer_for_render = False

# ---------------------------------------------------------------- 镜头
cam_d = bpy.data.cameras.new("cam")
cam_d.sensor_fit = "VERTICAL"
cam_d.angle_y = math.radians(38)
cam_d.dof.use_dof = True
cam_d.dof.aperture_fstop = 1.6
cam = bpy.data.objects.new("cam", cam_d)
sc.collection.objects.link(cam)
sc.camera = cam
tgt = bpy.data.objects.new("tgt", None)
sc.collection.objects.link(tgt)
tr = cam.constraints.new("TRACK_TO")
tr.target = tgt
tr.track_axis = "TRACK_NEGATIVE_Z"
tr.up_axis = "UP_Y"
for f in range(NF):
    t = f / FPS
    if f < S1:
        u = t / (2 * BAR)
        cl, tl, fd = (0.2, -(6.0 - 1.4 * u), 2.6 - 0.8 * u), (0, 2.0, 1.6 - 0.8 * u), 6.2 - 1.2 * u
        fl = 0.0
    elif f < S2:
        u = (t - 2 * BAR) / (2 * BAR)
        cl, tl, fd = (-4.2 + 6.0 * u, -2.6, -0.72), (-2.4 + 6.0 * u, 1.0, -0.45), 3.7
        fl = 0.0
    else:
        lt = t - 4 * BAR
        pk = ease(max(0.0, lt - 0.3) / (3 * BAR - 0.3))
        cl = (0, -(4.6 - 2.05 * pk), -0.3)
        tl = (0, -0.9, FLOOR + CH / 2 + 0.08)
        fd = math.dist(cl, tl)
        fl = max(0.0, 1 - lt / 0.35)
    cam.location = cl
    tgt.location = tl
    cam_d.dof.focus_distance = fd
    flash.data.energy = 40 + 900 * fl
    cam.keyframe_insert("location", frame=f)
    tgt.keyframe_insert("location", frame=f)
    cam_d.dof.keyframe_insert("focus_distance", frame=f)
    flash.data.keyframe_insert("energy", frame=f)
    ex = 0.0
    if f >= S2:
        ex = 2.2 * ease((t - (DUR - 0.35)) / 0.35)
    sc.view_settings.exposure = ex
    sc.view_settings.keyframe_insert("exposure", frame=f)

# 切镜处的关键帧不插值：全部改成常量 → 用线性（跨镜头的那一帧由 hide_render 切）
for a in bpy.data.actions:
    for fc in a.fcurves:
        for kp in fc.keyframe_points:
            kp.interpolation = "LINEAR"

os.makedirs(OUT, exist_ok=True)
sc.render.filepath = OUT.replace("\\", "/") + "/f"
sc.frame_start = F0
sc.frame_end = (F1 if F1 is not None else NF - 1)
print("PV3D-BLENDER frames", sc.frame_start, sc.frame_end, "engine", sc.render.engine, flush=True)
if os.environ.get("PV3D_DBG"):
    for f in (30, 230, 420):
        sc.frame_set(f)
        cl = cam.matrix_world.translation
        hits = []
        for o in sc.objects:
            if o.type != "MESH" or o.hide_render:
                continue
            bb = [o.matrix_world @ Vector(c) for c in o.bound_box]
            lo = Vector([min(v[i] for v in bb) for i in range(3)])
            hi = Vector([max(v[i] for v in bb) for i in range(3)])
            if all(lo[i] <= cl[i] <= hi[i] for i in range(3)):
                hits.append(o.name)
        print("PV3D dbg", f, tuple(round(x, 2) for x in cl), hits, flush=True)
    sys.exit(0)
if STILLS:
    import time
    for f in STILLS:
        t0 = time.time()
        sc.frame_set(f)
        sc.render.filepath = OUT.replace("\\", "/") + "/s%04d.png" % f
        bpy.ops.render.render(write_still=True)
        print("PV3D still", f, "%.1f s" % (time.time() - t0), flush=True)
else:
    bpy.ops.render.render(animation=True)
