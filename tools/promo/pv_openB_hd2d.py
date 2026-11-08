# -*- coding: utf-8 -*-
"""片头 B · 深海里的一点光（11-09 整夜任务，HD-2D：游戏像素贴图立在 Blender 三维空间里）。
一条连续镜头（battle2 第 70–77 小节，7 小节 ≈ 11.5 秒）：
  70–72  近黑深海，海床中央亮起一点航标光（声呐圈扩散）；镜头远远望着它缓推
  72–74  镜头穿过标题页沉船层往下沉：前景像素水母虚化掠过、残骸 / 石柱在雾里
  74–75  第一批海嗣（游戏贴图）从黑暗边缘游向光
  75–77  越来越多，绕着光收紧；光在闪；镜头升起、转成正俯视：海床一圈光，海嗣等在圈外
第 77 小节起的闪白 + logo、像素化、配乐与音效在 tools/promo/pv_openB_post.py。
颜色：标题页深海藏青，光和雾往淡蓝偏（用户 11-09），不用饱和青。
  blender -b --python tools/promo/pv_openB_hd2d.py -- <输出目录> [起帧-止帧 | 帧,帧,…]
渲染 960×540、30 帧（后期整幅 4×4 像素化，半分辨率足够）。
"""
import math, os, random, sys
import bpy
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
OUT = argv[0]
SEL = argv[1] if len(argv) > 1 else ""
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
ART = os.path.join(ROOT, "game", "art")
FPS = 30
BAR = 4 * 60 / 145.99
F = lambda bars: int(round(bars * BAR * FPS))
NF = F(7)
PALE = (0.62, 0.80, 1.0)          # 淡蓝光
rng = random.Random(9)

bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
sc.render.fps = FPS
sc.render.resolution_x, sc.render.resolution_y = 960, 540
for eng in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE"):
    try:
        sc.render.engine = eng
        break
    except TypeError:
        pass
ee = sc.eevee
ee.taa_render_samples = 24
for k, v in (("volumetric_tile_size", "4"), ("volumetric_samples", 48), ("use_volumetric_shadows", True), ("volumetric_end", 70.0), ("use_shadows", True)):
    try:
        setattr(ee, k, v)
    except Exception:
        pass
sc.view_settings.view_transform = "AgX"


def mat(name):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    n, l = m.node_tree.nodes, m.node_tree.links
    n.clear()
    return m, n, l, n.new("ShaderNodeOutputMaterial")


# ---- 世界：深藏青 + 淡蓝体积雾（远处融进雾，不是死黑）
world = bpy.data.worlds.new("deep"); sc.world = world; world.use_nodes = True
wn, wl = world.node_tree.nodes, world.node_tree.links; wn.clear()
wout = wn.new("ShaderNodeOutputWorld"); wbg = wn.new("ShaderNodeBackground")
wbg.inputs["Color"].default_value = (0.004, 0.008, 0.016, 1)
wl.new(wbg.outputs[0], wout.inputs["Surface"])
vol = wn.new("ShaderNodeVolumePrincipled")
vol.inputs["Color"].default_value = (0.55, 0.72, 0.95, 1)
vol.inputs["Density"].default_value = 0.035
vol.inputs["Anisotropy"].default_value = 0.55
vol.inputs["Emission Color"].default_value = (0.05, 0.08, 0.14, 1)
vol.inputs["Emission Strength"].default_value = 0.006
wl.new(vol.outputs[0], wout.inputs["Volume"])


def frame_img(path, crop=None):
    src = bpy.data.images.load(path, check_existing=True)
    W_, H_ = src.size
    if crop is None:
        return src, W_, H_
    x0, y0, x1, y1 = crop
    w, h = x1 - x0, y1 - y0
    px = list(src.pixels)
    buf = []
    for y in range(h):
        yy = H_ - y1 + y
        r0 = (yy * W_ + x0) * 4
        buf.extend(px[r0:r0 + w * 4])
    im = bpy.data.images.new("%s_%d" % (os.path.basename(path), x0), w, h, alpha=True)
    im.pixels = buf; im.pack()
    return im, w, h


def first_frame(path):
    """帧条第一帧：按透明缝切（列全透明处），再按非空行裁上下"""
    src = bpy.data.images.load(path, check_existing=True)
    W_, H_ = src.size
    px = src.pixels[:]
    col = [any(px[(y * W_ + x) * 4 + 3] > 0.01 for y in range(H_)) for x in range(W_)]
    x0 = col.index(True); x1 = x0
    while x1 < W_ and col[x1]:
        x1 += 1
    rows = [y for y in range(H_) if any(px[(y * W_ + x) * 4 + 3] > 0.01 for x in range(x0, x1))]
    yb, yt = min(rows), max(rows) + 1          # Blender 行号自下而上
    return frame_img(path, (x0, H_ - yt, x1, H_ - yb))


def card(img, w, h, px, loc, emit=0.5, face=None, name="card"):
    """像素纸片：中心落在 loc；最近邻；face=相机对象时始终朝向镜头"""
    bpy.ops.mesh.primitive_plane_add(size=1)
    ob = bpy.context.object; ob.name = name
    ob.scale = (w * px, h * px, 1)
    ob.location = loc
    if face is None:
        ob.rotation_euler = (math.radians(90), 0, 0)
    else:
        c = ob.constraints.new("TRACK_TO"); c.target = face; c.track_axis = "TRACK_Z"; c.up_axis = "UP_Y"
    m, n, l, o = mat(name)
    t = n.new("ShaderNodeTexImage"); t.image = img; t.interpolation = "Closest"
    b = n.new("ShaderNodeBsdfPrincipled")
    l.new(t.outputs["Color"], b.inputs["Base Color"]); l.new(t.outputs["Color"], b.inputs["Emission Color"])
    b.inputs["Emission Strength"].default_value = emit; b.inputs["Roughness"].default_value = 0.9
    l.new(t.outputs["Alpha"], b.inputs["Alpha"]); l.new(b.outputs[0], o.inputs["Surface"])
    try:
        m.surface_render_method = "DITHERED"
    except Exception:
        pass
    ob.data.materials.append(m)
    ob.visible_shadow = False
    return ob, b


# ---- 镜头
cam_d = bpy.data.cameras.new("cam"); cam_d.sensor_fit = "VERTICAL"; cam_d.angle_y = math.radians(34)
cam_d.dof.use_dof = True; cam_d.dof.aperture_fstop = 2.2
cam = bpy.data.objects.new("cam", cam_d); sc.collection.objects.link(cam); sc.camera = cam
tgt = bpy.data.objects.new("tgt", None); sc.collection.objects.link(tgt)
tc = cam.constraints.new("TRACK_TO"); tc.target = tgt; tc.track_axis = "TRACK_NEGATIVE_Z"; tc.up_axis = "UP_Y"
cam_d.dof.focus_object = tgt

# ---- 海床（暗沙）+ 标题页海底当远幕
bpy.ops.mesh.primitive_plane_add(size=160, location=(0, 20, 0))
fl = bpy.context.object
fm, fn, fl_, fo = mat("floor")
fb = fn.new("ShaderNodeBsdfPrincipled"); fb.inputs["Base Color"].default_value = (0.05, 0.065, 0.085, 1); fb.inputs["Roughness"].default_value = 0.95
nz = fn.new("ShaderNodeTexNoise"); nz.inputs["Scale"].default_value = 3.0
mx = fn.new("ShaderNodeMix"); mx.data_type = "RGBA"; mx.inputs["A"].default_value = (0.035, 0.045, 0.06, 1); mx.inputs["B"].default_value = (0.08, 0.1, 0.13, 1)
fl_.new(nz.outputs["Fac"], mx.inputs["Factor"]); fl_.new(mx.outputs["Result"], fb.inputs["Base Color"])
fl_.new(fb.outputs[0], fo.inputs["Surface"]); fl.data.materials.append(fm)

bg, bw, bh = frame_img(os.path.join(ART, "ui", "title_deep", "bg.png"))
bgp, bgp_b = card(bg, bw, bh, 0.11, (0, 26, 9), emit=0.5, name="bgplate")
wk, ww, wh = frame_img(os.path.join(ART, "world", "props", "prop_wreck.png"))
card(wk, ww, wh, 0.05, (-6.5, 9, wh * 0.025), emit=0.25, name="wreck")
card(wk, ww, wh, 0.035, (-4.6, -9.5, 4.0), emit=0.3, name="wreck_near")
pl, pw, ph = frame_img(os.path.join(ART, "world", "props", "prop_pillar.png"))
for x, y, z in ((5.5, 7, None), (-3.5, 14, None), (7.5, 15, None), (3.6, -10.5, 3.6), (-4.2, -6.5, 1.6)):
    card(pl, pw, ph, 0.06, (x, y, ph * 0.03 if z is None else z), emit=0.25, name="pillar")

# ---- 航标：游戏灯标点燃帧条的中间一帧 + 点光（淡蓝白）+ 一盏顶光在海床打出光圈
bi, bw_, bh_ = frame_img(os.path.join(ART, "fx", "fx_beacon_ignite@2x.png"), (128 * 5, 0, 128 * 6, 128))
beacon, beacon_b = card(bi, bw_, bh_, 0.006, (0, 0, 0.42), emit=0.0, face=cam, name="beacon")
bpy.ops.object.light_add(type="POINT", location=(0, 0, 0.5))
lamp = bpy.context.object; lamp.data.color = PALE; lamp.data.shadow_soft_size = 0.2
try:
    lamp.data.volume_factor = 1.6
except Exception:
    pass
bpy.ops.object.light_add(type="SPOT", location=(0, 0, 9))
spot = bpy.context.object; spot.data.color = PALE; spot.data.spot_size = math.radians(26); spot.data.spot_blend = 0.35
try:
    spot.data.volume_factor = 0.6
except Exception:
    pass
spot.rotation_euler = (0, 0, 0)

# 声呐圈：海床上一个扩散的发光细环
bpy.ops.mesh.primitive_torus_add(major_radius=1.0, minor_radius=0.006, location=(0, 0, 0.05))
ring = bpy.context.object
rm, rn, rl, ro = mat("ring"); re = rn.new("ShaderNodeEmission"); re.inputs["Color"].default_value = PALE + (1,)
rl.new(re.outputs[0], ro.inputs["Surface"]); ring.data.materials.append(rm); ring.visible_shadow = False

# ---- 像素水母（前景虚化掠过）
jellies = []
for k, (x, y, z) in enumerate(((-1.6, -7.2, 5.6), (2.0, -5.6, 3.8), (-2.4, -3.2, 2.6), (3.2, 2.5, 4.5), (-4.5, 5, 5.5))):
    j = k % 3
    im, w, h = frame_img(os.path.join(ART, "ui", "title_deep", "jelly_%d.png" % j))
    s = 0.011 if k < 3 else 0.016
    ob, _ = card(im, w, h, s, (x, y, z), emit=0.7, face=cam, name="jelly%d" % k)
    jellies.append((ob, Vector((x, y, z)), rng.uniform(0, 6.28)))

# ---- 海嗣：游戏贴图第一帧；从边缘游向光，最后围成一圈
SEA = {}
for e in ("floater", "slider", "runner", "skimmer", "offspring"):
    SEA[e] = first_frame(os.path.join(ART, "enemies", e, "e_%s@2x.png" % e))
kinds = ["floater", "slider", "runner", "skimmer", "offspring"]
swarm = []
N = 64
for k in range(N):
    e = kinds[k % len(kinds)]
    im, w, h = SEA[e]
    ang = (k / N) * 6.283 + rng.uniform(-0.08, 0.08)
    r_end = 2.35 + rng.uniform(0, 0.9) + (0.7 if k % 3 == 0 else 0)
    r0 = rng.uniform(9, 14)
    z = 0.45 if e in ("runner", "offspring", "slider") else rng.uniform(0.6, 1.6)
    t_in = 4.0 + (k / N) ** 1.5 * 1.5 + rng.uniform(-0.1, 0.1)        # 第几小节开始游进来（4 = 第 74 小节）
    px = 0.022 if e != "skimmer" else 0.018
    ob, _ = card(im, w, h, px, (math.cos(ang) * r0, math.sin(ang) * r0, z), emit=0.35, face=cam, name="sb_" + e)
    swarm.append((ob, ang, r0, r_end, z, t_in, rng.uniform(0, 6.28)))

# 方块颗粒（海雪）
pm, pn, pl_, po = mat("pix"); pe = pn.new("ShaderNodeEmission"); pe.inputs["Color"].default_value = (0.75, 0.88, 1.0, 1); pe.inputs["Strength"].default_value = 0.6
pl_.new(pe.outputs[0], po.inputs["Surface"])
snow = bpy.data.objects.new("snow", None); sc.collection.objects.link(snow)
for k in range(160):
    bpy.ops.mesh.primitive_plane_add(size=rng.uniform(0.015, 0.035), location=(rng.uniform(-9, 9), rng.uniform(-9, 16), rng.uniform(0.2, 9)))
    q = bpy.context.object; q.data.materials.append(pm); q.visible_shadow = False; q.parent = snow
    c = q.constraints.new("TRACK_TO"); c.target = cam; c.track_axis = "TRACK_Z"; c.up_axis = "UP_Y"


def ease(x):
    x = min(1.0, max(0.0, x))
    return x * x * (3 - 2 * x)


def lerp(a, b, u):
    return a + (b - a) * u


def keys(track, bars):
    """track = [(小节, 值)]，返回线性 + smoothstep 插值"""
    for (b0, v0), (b1, v1) in zip(track, track[1:]):
        if bars <= b1:
            u = ease((bars - b0) / max(1e-6, b1 - b0))
            if isinstance(v0, tuple):
                return tuple(lerp(a, b, u) for a, b in zip(v0, v1))
            return lerp(v0, v1, u)
    return track[-1][1]


CAM = [(0, (0, -15, 8.5)), (2, (0, -13.5, 7.6)), (4, (0.6, -6.2, 2.6)), (5, (0.3, -5.0, 2.3)), (6, (0, -2.2, 6.5)), (7, (0, -0.01, 9.0))]
TGT = [(0, (0, 0, 0.6)), (2, (0, 0, 0.6)), (4, (0, 0, 0.7)), (5, (0, 0, 0.6)), (6, (0, 0, 0.2)), (7, (0, 0, 0.0))]


def pose(f):
    bars = f / FPS / BAR
    t = f / FPS
    cam.location = keys(CAM, bars)
    tgt.location = keys(TGT, bars)
    # 航标：第 0.25 小节点亮（0.15 小节内到满），之后轻呼吸；75 后开始闪
    on = ease((bars - 0.25) / 0.15)
    flick = 1.0
    if bars > 5.0:
        flick = 0.65 + 0.35 * abs(math.sin(t * 7.3)) * (0.6 + 0.4 * math.sin(t * 2.1))
    lamp.data.energy = 120 * on * flick * (1 + 0.05 * math.sin(t * 2.2))
    beacon_b.inputs["Emission Strength"].default_value = 1.4 * on * flick
    spot.data.energy = 2600 * ease((bars - 0.4) / 1.5) * flick * (1 - 0.35 * ease((bars - 5) / 2))
    spot.data.spot_size = math.radians(lerp(26, 19, ease((bars - 5) / 2)))     # 光圈在缩
    # 声呐圈：每 2 小节一圈（0.25 / 2.25 / 4.25），扩散变淡
    ph = ((bars - 0.25) % 2.0) / 2.0 if bars >= 0.25 else 1.0
    ring.scale = (0.3 + 9 * ph,) * 3
    re.inputs["Strength"].default_value = 1.6 * (1 - ph) ** 2 * on * (1 if bars < 4.6 else 0)
    for ob, p0, phs in jellies:
        ob.location = p0 + Vector((0.15 * math.sin(t * 0.5 + phs), 0, 0.25 * t / 11 + 0.08 * math.sin(t * 1.3 + phs)))
    for ob, ang, r0, r1, z, t_in, phs in swarm:
        u = ease((bars - t_in) / 1.0)
        r = lerp(r0, r1, u)
        a = ang + 0.05 * u * math.sin((bars - t_in) * 2.0)          # 收紧时绕圈
        ob.location = (math.cos(a) * r, math.sin(a) * r, z + 0.06 * math.sin(t * 2.0 + phs))
        ob.hide_render = bars < t_in - 0.05
    bgp_b.inputs["Emission Strength"].default_value = 0.12 + 0.4 * ease((bars - 1.5) / 2.0)
    snow.location = (0, 0, 0.05 * t)


os.makedirs(OUT, exist_ok=True)
sc.render.image_settings.file_format = "PNG"
if SEL and "-" in SEL:
    a, b = (int(x) for x in SEL.split("-"))
    frames = range(a, b + 1)
elif SEL:
    frames = [int(x) for x in SEL.split(",")]
else:
    frames = range(0, NF)
for f in frames:
    sc.frame_set(f)
    pose(f)
    sc.render.filepath = OUT.replace("\\", "/") + "/b%04d.png" % f
    bpy.ops.render.render(write_still=True)
print("PVB done", len(list(frames)), "NF", NF)
