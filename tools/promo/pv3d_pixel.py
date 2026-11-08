# -*- coding: utf-8 -*-
"""PV 3D 段 · HD-2D 像素版（11-08 用户：与其虚的意象，不如多来点我们的像素特色）。
场景里的东西全是游戏里的像素贴图（最近邻采样、不平滑），立在有纵深的 3D 空间里，用 3D 的雾、体积光、景深、边光：
  远景  标题页的像素海底（ui/title_deep/bg.png）当大幕
  中景  像素灯塔（灯是全片唯一的暖橙点缀）、残骸、石柱；像素水母（标题页 jelly + jglow）和海嗣在雾里
  前景  水月像素帧落地（脚下接触光），方块像素颗粒
按 docs/327：深海底 + 雾（暗而不死黑）、一束顶光、清晰区小、遮幅在剪辑时加。

  blender -b --python tools/promo/pv3d_pixel.py -- <输出目录> [帧,帧,…]
"""
import math, os, random, sys, time
import bpy
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
OUT = argv[0]
STILLS = [int(x) for x in argv[1].split(",")] if len(argv) > 1 else [60]
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
ART = os.path.join(ROOT, "game", "art")
FPS = 60
CYAN = (0.35, 0.85, 1.0, 1)
WARM = (1.0, 0.38, 0.08, 1)

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
             ("volumetric_end", 60.0), ("use_shadows", True)):
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


world = bpy.data.worlds.new("deep")
sc.world = world
world.use_nodes = True
wn, wl = world.node_tree.nodes, world.node_tree.links
wn.clear()
wout = wn.new("ShaderNodeOutputWorld")
wbg = wn.new("ShaderNodeBackground")
wbg.inputs["Color"].default_value = (0.0022, 0.0055, 0.012, 1)
wl.new(wbg.outputs[0], wout.inputs["Surface"])
vol = wn.new("ShaderNodeVolumePrincipled")
vol.inputs["Color"].default_value = (0.3, 0.7, 0.9, 1)
vol.inputs["Density"].default_value = 0.05
vol.inputs["Anisotropy"].default_value = 0.6
vol.inputs["Emission Color"].default_value = (0.03, 0.09, 0.14, 1)
vol.inputs["Emission Strength"].default_value = 0.012
wl.new(vol.outputs[0], wout.inputs["Volume"])


def frame_img(path, fw=None, fi=0, crop=None):
    """读像素帧条的第 fi 帧（fw = 帧宽，None = 整张）；crop = (x0, y0, x1, y1) 像素"""
    src = bpy.data.images.load(path, check_existing=True)
    W_, H_ = src.size
    if fw is None and crop is None:
        return src, W_, H_
    x0, y0, x1, y1 = crop if crop else (fi * fw, 0, (fi + 1) * fw, H_)
    w, h = x1 - x0, y1 - y0
    px = list(src.pixels)
    buf = []
    for y in range(h):   # Blender 像素自下而上
        yy = H_ - y1 + y
        r0 = (yy * W_ + x0) * 4
        buf.extend(px[r0:r0 + w * 4])
    im = bpy.data.images.new(os.path.basename(path) + "_%d" % fi, w, h, alpha=True)
    im.pixels = buf
    im.pack()
    return im, w, h


def billboard(img, w, h, px, loc, emit=0.6, lit=True, face_cam=True, name="bb"):
    """像素纸片：px = 每个像素多少米；底边中点落在 loc；最近邻；自发光 emit + 受光（lit）；alpha 抖动裁切"""
    bpy.ops.mesh.primitive_plane_add(size=1)
    ob = bpy.context.object
    ob.name = name
    ob.scale = (w * px, h * px, 1)
    ob.rotation_euler = (math.radians(90), 0, 0)
    ob.location = (loc[0], loc[1], loc[2] + h * px / 2)
    m, n, l, o = mat(name)
    t = n.new("ShaderNodeTexImage"); t.image = img; t.interpolation = "Closest"
    b = n.new("ShaderNodeBsdfPrincipled")
    l.new(t.outputs["Color"], b.inputs["Base Color"])
    l.new(t.outputs["Color"], b.inputs["Emission Color"])
    b.inputs["Emission Strength"].default_value = emit
    b.inputs["Roughness"].default_value = 0.9
    l.new(t.outputs["Alpha"], b.inputs["Alpha"])
    l.new(b.outputs[0], o.inputs["Surface"])
    try:
        m.surface_render_method = "DITHERED"
    except Exception:
        pass
    ob.data.materials.append(m)
    return ob


def enemy(eid, idle_frames):
    p = os.path.join(ART, "enemies", eid, "e_%s@2x.png" % eid)
    s = bpy.data.images.load(p, check_existing=True)
    fw = s.size[0] // idle_frames
    return frame_img(p, fw, 0)


# ---------------------------------------------------------------- 地面：暗沙（雾里只看得见近处）
bpy.ops.mesh.primitive_plane_add(size=120, location=(0, 30, 0))
fl = bpy.context.object
fm, fn, fl_, fo = mat("floor")
fb = fn.new("ShaderNodeBsdfPrincipled"); fb.inputs["Base Color"].default_value = (0.03, 0.045, 0.05, 1); fb.inputs["Roughness"].default_value = 0.95
fl_.new(fb.outputs[0], fo.inputs["Surface"])
fl.data.materials.append(fm)

rng = random.Random(5)
LAYERS = os.environ.get("PV3D_LAYERS", "")   # 11-08 用户嫌背景杂：改用 pixgen 出的三层海底像素背景（远 / 中 / 前），主体只留水月
if LAYERS:
    def layer(name, px, loc, emit):
        im, w, h = frame_img(os.path.join(LAYERS, name + ".png"))
        return billboard(im, w, h, px, loc, emit=emit, name="L_" + name)
    layer("far", 0.16, (0, 34, -0.6), 0.06)       # 远景：融在雾里的大块礁石剪影
    layer("mid", 0.045, (1.0, 13, -0.4), 0.05)    # 中景：带残柱的礁石台地，灯塔立在上面
    lh, lw, lhh = frame_img(os.path.join(ART, "world", "props", "prop_lighthouse@2x.png"), 128, 0)
    billboard(lh, lw, lhh, 0.028, (2.6, 12.4, -0.2), emit=0.22, name="lighthouse")
    bpy.ops.object.light_add(type="POINT", location=(2.6, 12.3, -0.2 + 128 * 0.028 * 0.82))
    lamp = bpy.context.object
    lamp.data.color = WARM[:3]; lamp.data.energy = 160; lamp.data.shadow_soft_size = 0.3
    try:
        lamp.data.volume_factor = 2.0
    except Exception:
        pass
    im, w, h = enemy("mother", 6)   # 远处唯一一只海嗣剪影
    billboard(im, w, h, 0.05, (-5.5, 24, 0.2), emit=0.08, name="e_mother")
    layer("near", 0.0095, (-0.6, 0.6, -0.12), 0.03)  # 前景：画面边缘的暗礁 + 海草当框（景深虚掉）
else:
    # ---------------------------------------------------------------- 远景：标题页像素海底当大幕

    bg, bw, bh = frame_img(os.path.join(ART, "ui", "title_deep", "bg.png"))
    billboard(bg, bw, bh, 0.16, (0, 40, -4), emit=0.5, name="bgplate")

    # ---------------------------------------------------------------- 中景：灯塔（暖灯）、残骸、石柱
    lh, lw, lhh = frame_img(os.path.join(ART, "world", "props", "prop_lighthouse@2x.png"), 128, 0)
    billboard(lh, lw, lhh, 0.034, (1.6, 16, 0), emit=0.25, name="lighthouse")
    bpy.ops.object.light_add(type="POINT", location=(1.6, 15.9, 128 * 0.034 * 0.82))
    lamp = bpy.context.object
    lamp.data.color = WARM[:3]; lamp.data.energy = 160; lamp.data.shadow_soft_size = 0.3
    try:
        lamp.data.volume_factor = 2.0
    except Exception:
        pass
    wk, ww, wh = frame_img(os.path.join(ART, "world", "props", "prop_wreck.png"))
    billboard(wk, ww, wh, 0.06, (4.2, 10, 0), emit=0.15, name="wreck")
    pl, pw, ph = frame_img(os.path.join(ART, "world", "props", "prop_pillar.png"))
    for x, y in ((-6.5, 9), (6.8, 16), (1.8, 22)):
        billboard(pl, pw, ph, 0.07, (x, y, 0), emit=0.12, name="pillar")

    # ---------------------------------------------------------------- 海嗣（雾里的剪影）与像素水母
    rng = random.Random(5)
    for eid, nf, x, y, z, pxs in (("floater", 4, 3.0, 12, 2.6, 0.03), ("skimmer", 6, -5.0, 18, 3.6, 0.03), ("runner", 4, 2.2, 7, 0, 0.022),
                                  ("reaper", 4, -4.2, 11, 0, 0.026), ("mother", 6, 6.5, 24, 0, 0.05), ("brood", 4, -1.0, 9, 0, 0.022)):
        im, w, h = enemy(eid, nf)
        billboard(im, w, h, pxs, (x, y, z), emit=0.18, name="e_" + eid)
    for k in range(5):
        j = k % 3
        im, w, h = frame_img(os.path.join(ART, "ui", "title_deep", "jelly_%d.png" % j))
        gi, gw, gh = frame_img(os.path.join(ART, "ui", "title_deep", "jglow_%d.png" % j))
        x, y, z = rng.uniform(-5, 5), rng.uniform(6, 20), rng.uniform(2.5, 6.0)
        s = rng.uniform(0.006, 0.012)
        billboard(gi, gw, gh, s, (x, y + 0.02, z - (gh - h) * s / 2), emit=1.6, name="jglow")
        billboard(im, w, h, s, (x, y, z), emit=0.9, name="jelly")

# ---------------------------------------------------------------- 前景：水月落地（入场最后一帧）+ 接触光
import json
ent = json.load(open(os.path.join(ROOT, "game", "data", "characters", "mizuki.json"), encoding="utf-8"))["sprites"]["entry"]
ps = os.path.join(ART, "operators", "mizuki", ent["tex"] + "@2x.png")
s_ = bpy.data.images.load(ps)
fw = s_.size[0] // int(ent["frames"])
mz, mw, mh = frame_img(ps, fw, int(ent["frames"]) - 1)
foot_y = ent["foot"][1] * 2 / mh
MZ_PX = 0.019
billboard(mz, mw, mh, MZ_PX, (-1.15, 2.0, -(1 - foot_y) * mh * MZ_PX), emit=0.9, name="mizuki")
bpy.ops.mesh.primitive_circle_add(vertices=48, radius=0.75, fill_type="NGON", location=(-1.15, 2.0, 0.01))
cg = bpy.context.object
cg.scale = (1.0, 0.45, 1)
cm, cn, cl, co = mat("contact")
gtc = cn.new("ShaderNodeTexCoord"); grd = cn.new("ShaderNodeTexGradient"); grd.gradient_type = "SPHERICAL"
mp = cn.new("ShaderNodeMapping"); mp.inputs["Scale"].default_value = (1.35, 1.35, 1.35)
cl.new(gtc.outputs["Object"], mp.inputs["Vector"]); cl.new(mp.outputs[0], grd.inputs["Vector"])
pw_ = cn.new("ShaderNodeMath"); pw_.operation = "POWER"; pw_.inputs[1].default_value = 2.0; cl.new(grd.outputs["Fac"], pw_.inputs[0])
mu = cn.new("ShaderNodeMath"); mu.operation = "MULTIPLY"; mu.inputs[1].default_value = 1.8; cl.new(pw_.outputs[0], mu.inputs[0])
em = cn.new("ShaderNodeEmission"); em.inputs["Color"].default_value = CYAN; cl.new(mu.outputs[0], em.inputs["Strength"])
tr = cn.new("ShaderNodeBsdfTransparent"); ad = cn.new("ShaderNodeAddShader")
cl.new(tr.outputs[0], ad.inputs[0]); cl.new(em.outputs[0], ad.inputs[1]); cl.new(ad.outputs[0], co.inputs["Surface"])
try:
    cm.surface_render_method = "BLENDED"
except Exception:
    pass
cg.data.materials.append(cm)
cg.visible_shadow = False

# ---------------------------------------------------------------- 方块像素颗粒（三档：近大远小）
pm, pn, pl_, po = mat("pix")
pe = pn.new("ShaderNodeEmission"); pe.inputs["Color"].default_value = (0.75, 0.95, 1.0, 1); pe.inputs["Strength"].default_value = 0.8
pl_.new(pe.outputs[0], po.inputs["Surface"])
for k in range(140):
    d = rng.random()
    y = 1.2 + d * 22
    sz = 0.012 + (1 - d) * 0.02
    bpy.ops.mesh.primitive_plane_add(size=sz, location=(rng.uniform(-7, 7) * (0.3 + d), y, rng.uniform(0.1, 6.5)))
    q = bpy.context.object
    q.rotation_euler = (math.radians(90), 0, 0)
    q.data.materials.append(pm)
    q.visible_shadow = False

# ---------------------------------------------------------------- 光：一束顶光 + 水月身后青色逆光
bpy.ops.object.light_add(type="SPOT", location=(-1.0, 8.0, 12.0))
sp = bpy.context.object
sp.data.energy = 4000; sp.data.spot_size = math.radians(22); sp.data.spot_blend = 0.7; sp.data.color = (0.6, 0.9, 1.0)
try:
    sp.data.volume_factor = 3.0
except Exception:
    pass
sp.rotation_euler = (Vector((-0.5, 9.0, 0)) - Vector(sp.location)).to_track_quat("-Z", "Y").to_euler()
bpy.ops.object.light_add(type="AREA", location=(-1.15, 3.6, 2.2))
rim = bpy.context.object
rim.data.energy = 180; rim.data.size = 1.2; rim.data.color = (0.45, 0.85, 1.0)
try:
    rim.data.volume_factor = 0.05
except Exception:
    pass
rim.rotation_euler = (Vector((-1.15, 2.0, 1.0)) - Vector(rim.location)).to_track_quat("-Z", "Y").to_euler()

# ---------------------------------------------------------------- 镜头：低机位，焦点在水月
cam_d = bpy.data.cameras.new("cam")
cam_d.sensor_fit = "VERTICAL"
cam_d.angle_y = math.radians(30)
cam_d.dof.use_dof = True
cam_d.dof.aperture_fstop = 1.8
cam_d.dof.focus_distance = 5.2
cam = bpy.data.objects.new("cam", cam_d)
sc.collection.objects.link(cam)
sc.camera = cam
cam.location = (-0.6, -3.0, 1.1)
cam.rotation_euler = (math.radians(88), 0, math.radians(-6))

if os.environ.get("PV3D_SPOT") == "1":
    # 塔露拉前瞻 PV 20 秒那种构图（11-08 用户：PV 里没有大块面板）：人物居中、小，一束顶光圈出一块亮区，四周大片暗留白
    cam.location = (-1.15, -6.2, 1.6)
    cam.rotation_euler = (math.radians(84), 0, 0)
    cam_d.dof.focus_distance = 8.2
    sp.location = (-1.15, 2.4, 9.0)
    sp.data.energy = 9000; sp.data.spot_size = math.radians(14); sp.data.spot_blend = 0.85
    sp.rotation_euler = (Vector((-1.15, 2.0, 0)) - Vector(sp.location)).to_track_quat("-Z", "Y").to_euler()
    nl = bpy.data.objects.get("L_near")
    if nl:   # 前景框跟着镜头后移，保持在画面角上
        nl.location.x, nl.location.y = -1.15, -2.6
sc.use_nodes = True
cn_, cl2 = sc.node_tree.nodes, sc.node_tree.links
cn_.clear()
rl = cn_.new("CompositorNodeRLayers")
g = cn_.new("CompositorNodeGlare")
try:
    g.glare_type = "BLOOM"
except Exception:
    g.glare_type = "FOG_GLOW"
for nm, v in (("Threshold", 0.7), ("Strength", 0.6), ("Size", 0.6)):
    try:
        g.inputs[nm].default_value = v
    except Exception:
        pass
co2 = cn_.new("CompositorNodeComposite")
cl2.new(rl.outputs["Image"], g.inputs["Image"]); cl2.new(g.outputs["Image"], co2.inputs["Image"])

os.makedirs(OUT, exist_ok=True)
for f in STILLS:
    t0 = time.time()
    sc.frame_set(f)
    sc.render.filepath = OUT.replace("\\", "/") + "/px_s%04d.png" % f
    bpy.ops.render.render(write_still=True)
    print("PV3D still", f, "%.1f s" % (time.time() - t0), flush=True)
