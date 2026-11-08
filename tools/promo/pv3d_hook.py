# -*- coding: utf-8 -*-
"""PV 开头钩子 · Blender HD-2D（11-08 用户：开头留不住人，Blender 能用上吗）：
游戏像素贴图（最近邻）立在 3D 空间里，体积雾 + 顶光光柱 + 景深。第一秒：黑场一束光，伊莎玛拉（最终 Boss）的巨大像素剪影
从镜头前游过（只亮发光纹 = 游戏的 _emit 层），远处是标题页像素海底和灯塔。

  blender -b --python tools/promo/pv3d_hook.py -- <输出目录> <帧,帧,…>
"""
import math, os, sys, time
import bpy
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
OUT = argv[0]
STILLS = [int(x) for x in argv[1].split(",")]
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
ART = os.path.join(ROOT, "game", "art")
FPS = 60

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
for k, v in (("use_raytracing", True), ("volumetric_tile_size", "2"), ("volumetric_samples", 96), ("use_volumetric_shadows", True),
             ("volumetric_end", 80.0), ("use_shadows", True)):
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


w = bpy.data.worlds.new("deep")
sc.world = w
w.use_nodes = True
wn, wl = w.node_tree.nodes, w.node_tree.links
wn.clear()
wo = wn.new("ShaderNodeOutputWorld")
bg = wn.new("ShaderNodeBackground"); bg.inputs["Color"].default_value = (0.002, 0.005, 0.011, 1)
wl.new(bg.outputs[0], wo.inputs["Surface"])
vol = wn.new("ShaderNodeVolumePrincipled")
vol.inputs["Color"].default_value = (0.35, 0.7, 0.85, 1)
vol.inputs["Density"].default_value = 0.03
vol.inputs["Anisotropy"].default_value = 0.65
vol.inputs["Emission Color"].default_value = (0.03, 0.09, 0.14, 1)
vol.inputs["Emission Strength"].default_value = 0.012
wl.new(vol.outputs[0], wo.inputs["Volume"])


def load_frame(path, fw=None, fi=0):
    src = bpy.data.images.load(path, check_existing=True)
    W_, H_ = src.size
    if fw is None:
        return src, W_, H_
    px = list(src.pixels)
    buf = []
    for y in range(H_):
        r0 = (y * W_ + fi * fw) * 4
        buf.extend(px[r0:r0 + fw * 4])
    im = bpy.data.images.new(os.path.basename(path) + "_%d" % fi, fw, H_, alpha=True)
    im.pixels = buf
    im.pack()
    return im, fw, H_


def sprite(img, w_, h_, pxm, loc, emit=0.5, emit_img=None, emit_k=0.0, emit_col=(0.4, 0.9, 1.0), name="s", rot_z=0.0):
    bpy.ops.mesh.primitive_plane_add(size=1)
    ob = bpy.context.object
    ob.name = name
    ob.scale = (w_ * pxm, h_ * pxm, 1)
    ob.rotation_euler = (math.radians(90), 0, rot_z)
    ob.location = loc
    m, n, l, o = mat(name)
    t = n.new("ShaderNodeTexImage"); t.image = img; t.interpolation = "Closest"
    b = n.new("ShaderNodeBsdfPrincipled")
    if name == "ishar":   # 巨物压成近剪影：原色只留 18%
        hs = n.new("ShaderNodeHueSaturation"); hs.inputs["Value"].default_value = 0.18; hs.inputs["Saturation"].default_value = 0.6
        l.new(t.outputs["Color"], hs.inputs["Color"]); l.new(hs.outputs[0], b.inputs["Base Color"])
    else:
        l.new(t.outputs["Color"], b.inputs["Base Color"])
    l.new(t.outputs["Alpha"], b.inputs["Alpha"])
    b.inputs["Roughness"].default_value = 0.9
    if emit_img is not None:   # 只让发光纹发光（游戏的 _emit 层）
        te = n.new("ShaderNodeTexImage"); te.image = emit_img; te.interpolation = "Closest"
        mu = n.new("ShaderNodeMix"); mu.data_type = "RGBA"; mu.blend_type = "MULTIPLY"; mu.inputs["Factor"].default_value = 1.0
        l.new(te.outputs["Color"], mu.inputs[6]); mu.inputs[7].default_value = emit_col + (1,)
        l.new(mu.outputs[2], b.inputs["Emission Color"])
        b.inputs["Emission Strength"].default_value = emit_k
    else:
        l.new(t.outputs["Color"], b.inputs["Emission Color"])
        b.inputs["Emission Strength"].default_value = emit
    l.new(b.outputs[0], o.inputs["Surface"])
    try:
        m.surface_render_method = "DITHERED"
    except Exception:
        pass
    ob.data.materials.append(m)
    return ob


# 远景：标题页像素海底
bimg, bw, bh = load_frame(os.path.join(ART, "ui", "title_deep", "bg.png"))
sprite(bimg, bw, bh, 0.12, (0, 30, 9), emit=1.6, name="bgplate")
# 中景：灯塔（灭灯，暗）
limg, lw, lh = load_frame(os.path.join(ART, "world", "props", "prop_lighthouse@2x.png"), 128, 0)
sprite(limg, lw, lh, 0.05, (3.0, 20, 3.0), emit=0.12, name="lighthouse")
# 近景：伊莎玛拉巨大剪影（从镜头前游过），只亮发光纹
iimg, iw, ih = load_frame(os.path.join(ART, "enemies", "ishar", "e_ishar_t_move@2x.png"), 318, 0)
boss = sprite(iimg, iw, ih, 0.04, (0.0, 7.0, 1.8), emit=0.02, name="ishar")   # 游戏的 _emit 层几乎是空的：本体压暗只留一点原色，靠身后逆光勾出轮廓
bpy.ops.object.light_add(type="AREA", location=(0.0, 9.0, 4.0))
bl = bpy.context.object
bl.data.energy = 700; bl.data.size = 6; bl.data.color = (0.45, 0.85, 1.0)
bl.rotation_euler = (Vector((0, 7.0, 2.0)) - Vector(bl.location)).to_track_quat("-Z", "Y").to_euler()
try:
    bl.data.volume_factor = 0.0
except Exception:
    pass
# 动画：剪影从右向左游过镜头（0–60 帧），微上浮
for f, x in ((0, 11.0), (60, 0.5), (120, -11.0)):
    boss.location.x = x
    boss.location.z = 1.8 + 0.15 * f / 120
    boss.keyframe_insert("location", frame=f)

# 光：一束顶光（体积光柱），剪影从光柱里穿过
bpy.ops.object.light_add(type="SPOT", location=(-0.6, 5.0, 14.0))
sp = bpy.context.object
sp.data.energy = 14000; sp.data.spot_size = math.radians(14); sp.data.spot_blend = 0.8; sp.data.color = (0.6, 0.92, 1.0)
try:
    sp.data.volume_factor = 4.0
except Exception:
    pass
sp.rotation_euler = (Vector((-0.6, 5.5, -2)) - Vector(sp.location)).to_track_quat("-Z", "Y").to_euler()

cam_d = bpy.data.cameras.new("cam")
cam_d.sensor_fit = "VERTICAL"
cam_d.angle_y = math.radians(34)
cam_d.dof.use_dof = True
cam_d.dof.aperture_fstop = 2.0
cam_d.dof.focus_distance = 7.0
cam = bpy.data.objects.new("cam", cam_d)
sc.collection.objects.link(cam)
sc.camera = cam
cam.location = (0, -3.0, 1.6)
cam.rotation_euler = (math.radians(92), 0, 0)

sc.use_nodes = True
cn, cl = sc.node_tree.nodes, sc.node_tree.links
cn.clear()
rl = cn.new("CompositorNodeRLayers")
g = cn.new("CompositorNodeGlare")
try:
    g.glare_type = "BLOOM"
except Exception:
    g.glare_type = "FOG_GLOW"
for nm, v in (("Threshold", 0.6), ("Strength", 0.9), ("Size", 0.7)):
    try:
        g.inputs[nm].default_value = v
    except Exception:
        pass
co = cn.new("CompositorNodeComposite")
cl.new(rl.outputs["Image"], g.inputs["Image"]); cl.new(g.outputs["Image"], co.inputs["Image"])

os.makedirs(OUT, exist_ok=True)
for f in STILLS:
    t0 = time.time()
    sc.frame_set(f)
    sc.render.filepath = OUT.replace("\\", "/") + "/h%04d.png" % f
    bpy.ops.render.render(write_still=True)
    print("PV3D still", f, "%.1f s" % (time.time() - t0), flush=True)
