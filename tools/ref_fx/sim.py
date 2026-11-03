# -*- coding: utf-8 -*-
"""原作 prefab 回放（内部参照）：读 arkab.dump_prefabs 的节点树，按层级 TRS 变换叠粒子 / 网格 / 拖尾 / 连线，画到 numpy 画布上。
原型：逻各斯会话 Claude outputs/logos_ref/scripts（recon.py / engine.py），这里把场景常量改成可配（cfg）。
已知近似：形状模块除球形外都按锥近似；速度限制只按 0.6 衰减；MeshRenderer 没读动画曲线（0.12 s 淡入、mesh_life 后淡出）；
TrailRenderer 要给 path、LineRenderer 要给 line 才画；子发射器、噪声、力场、碰撞不模拟。
投影：billboard 类 prefab 屏幕 = (X, -Y)；地面类（树里有 rotation_z 节点，或 ground=True）屏幕 = (X, -Y·GROUND_SY)。
"""
import math, os, random
import numpy as np
from PIL import Image


class Cfg:
    S = 200.0             # 像素 / Unity 单位
    W, H = 960, 640
    BG = (52, 58, 68)
    FPS = 30
    END = 6.0             # 循环发射到此为止
    GROUND_SY = 0.55
    TEX_DIRS = []         # 找贴图的目录（按顺序）：<名>.png 或 lib_*_<名>.png（build/ark_ref/<人>/ 的命名）
    MESH = ""


cfg = Cfg()


# ---------- 贴图
_tex = {}


def tex(name):
    if name in _tex:
        return _tex[name]
    for d in cfg.TEX_DIRS:
        if not os.path.isdir(d):
            continue
        for f in os.listdir(d):
            b = f[:-4]
            if f.endswith(".png") and (b == name or (b.startswith("lib_") and b.endswith("_" + name))):
                im = np.asarray(Image.open(os.path.join(d, f)).convert("RGBA"), dtype=np.float32) / 255.0
                if im[..., 3].min() > 0.95:   # 无 alpha 的流动 / 遮罩图：亮度当 alpha（Torappu 粒子着色器按 R / 亮度取透明）
                    im = im.copy()
                    im[..., 3] = im[..., :3].max(2)
                _tex[name] = im
                return im
    _tex[name] = None
    return None


# ---------- 曲线 / 渐变
def keys_eval(keys, t):
    if not keys:
        return 1.0
    if t <= keys[0]["time"]:
        return keys[0]["value"]
    for a, b in zip(keys, keys[1:]):
        if t <= b["time"]:
            u = (t - a["time"]) / max(1e-6, b["time"] - a["time"])
            return a["value"] + (b["value"] - a["value"]) * u
    return keys[-1]["value"]


def curve(c, t, r):
    s = c.get("minMaxState", 0)
    sc = c.get("scalar", 1.0)
    if s == 0:
        return sc
    if s == 3:
        return c.get("minScalar", 0) + (sc - c.get("minScalar", 0)) * r
    if s == 1:
        return sc * keys_eval(c["maxCurve"]["m_Curve"], t)
    a = keys_eval(c["minCurve"]["m_Curve"], t)
    b = keys_eval(c["maxCurve"]["m_Curve"], t)
    return sc * (a + (b - a) * r)


def grad_eval(g, t):
    nc, na = g.get("m_NumColorKeys", 2), g.get("m_NumAlphaKeys", 2)
    cs = [(g["ctime%d" % i] / 65535, np.array([g["key%d" % i][k] for k in "rgb"])) for i in range(nc)]
    al = [(g["atime%d" % i] / 65535, g["key%d" % i]["a"]) for i in range(na)]

    def ev(lst, t):
        if t <= lst[0][0]:
            return lst[0][1]
        for (ta, va), (tb, vb) in zip(lst, lst[1:]):
            if t <= tb:
                u = (t - ta) / max(1e-6, tb - ta)
                return va + (vb - va) * u
        return lst[-1][1]
    return np.append(ev(cs, t), ev(al, t))


def col(c):
    return np.array([c["r"], c["g"], c["b"], c["a"]])


def mmg(m, t, r):
    s = m.get("minMaxState", 0)
    if s == 0:
        return col(m["maxColor"])
    if s == 1:
        return grad_eval(m["maxGradient"], t)
    if s == 2:
        return col(m["minColor"]) * (1 - r) + col(m["maxColor"]) * r
    if s == 3:
        return grad_eval(m["minGradient"], t) * (1 - r) + grad_eval(m["maxGradient"], t) * r
    return col(m["maxColor"])


# ---------- 画布与混合
class Canvas:
    def __init__(self, base=None):
        if base is None:
            self.c = np.zeros((cfg.H, cfg.W, 3), np.float32)
            self.c[:] = np.array(cfg.BG) / 255.0
        else:
            self.c = np.asarray(base.convert("RGB"), np.float32) / 255.0

    def quad(self, img, center, ex, ey, rgba, add):
        """把贴图 img 贴到以 center 为中心、轴向量 ex / ey（半宽，像素）的平行四边形上"""
        W, H = cfg.W, cfg.H
        ex, ey = np.asarray(ex, float), np.asarray(ey, float)
        r = abs(ex[0]) + abs(ey[0])
        s = abs(ex[1]) + abs(ey[1])
        x0, x1 = int(max(0, center[0] - r)), int(min(W, center[0] + r + 1))
        y0, y1 = int(max(0, center[1] - s)), int(min(H, center[1] + s + 1))
        if x1 <= x0 or y1 <= y0:
            return
        M = np.array([[ex[0], ey[0]], [ex[1], ey[1]]])
        if abs(np.linalg.det(M)) < 1e-6:
            return
        Mi = np.linalg.inv(M)
        yy, xx = np.mgrid[y0:y1, x0:x1].astype(np.float32)
        dx, dy = xx - center[0], yy - center[1]
        u = Mi[0, 0] * dx + Mi[0, 1] * dy
        v = Mi[1, 0] * dx + Mi[1, 1] * dy
        m = (np.abs(u) <= 1) & (np.abs(v) <= 1)
        if not m.any():
            return
        th, tw = img.shape[:2]
        tx = np.clip(((u + 1) * 0.5 * (tw - 1)).astype(int), 0, tw - 1)
        ty = np.clip(((1 - (v + 1) * 0.5) * (th - 1)).astype(int), 0, th - 1)
        self.blend(img[ty, tx], m, rgba, add, y0, y1, x0, x1)

    def blend(self, smp, m, rgba, add, y0, y1, x0, x1):
        a = smp[..., 3] * rgba[3] * m
        rgb = smp[..., :3] * rgba[:3]
        reg = self.c[y0:y1, x0:x1]
        if add:
            reg += rgb * a[..., None]
        else:
            reg[:] = reg * (1 - a[..., None]) + rgb * a[..., None]
        np.clip(reg, 0, 4, out=reg)

    def mesh(self, verts, uvs, faces, img, xf, rgba, add, soft=0.0):
        """xf: 局部顶点 → 屏幕像素"""
        W, H = cfg.W, cfg.H
        P = np.array([xf(v) for v in verts])
        th, tw = img.shape[:2]
        for a, b, c in faces:
            pa, pb, pc = P[a], P[b], P[c]
            x0, x1 = int(max(0, min(pa[0], pb[0], pc[0]))), int(min(W, max(pa[0], pb[0], pc[0]) + 1))
            y0, y1 = int(max(0, min(pa[1], pb[1], pc[1]))), int(min(H, max(pa[1], pb[1], pc[1]) + 1))
            if x1 <= x0 or y1 <= y0:
                continue
            d = (pb[1] - pc[1]) * (pa[0] - pc[0]) + (pc[0] - pb[0]) * (pa[1] - pc[1])
            if abs(d) < 1e-6:
                continue
            yy, xx = np.mgrid[y0:y1, x0:x1].astype(np.float32) + 0.5
            l1 = ((pb[1] - pc[1]) * (xx - pc[0]) + (pc[0] - pb[0]) * (yy - pc[1])) / d
            l2 = ((pc[1] - pa[1]) * (xx - pc[0]) + (pa[0] - pc[0]) * (yy - pc[1])) / d
            l3 = 1 - l1 - l2
            m = (l1 >= 0) & (l2 >= 0) & (l3 >= 0)
            if not m.any():
                continue
            uu = l1 * uvs[a][0] + l2 * uvs[b][0] + l3 * uvs[c][0]
            vv = l1 * uvs[a][1] + l2 * uvs[b][1] + l3 * uvs[c][1]
            tx = np.clip((np.mod(uu, 1.0) * (tw - 1)).astype(int), 0, tw - 1)
            ty = np.clip(((1 - np.mod(vv, 1.0)) * (th - 1)).astype(int), 0, th - 1)
            smp = img[ty, tx]
            if soft > 0:   # 扰动 / 溶解着色器的遮罩会吃掉面片边缘：按 UV 到边距离软化
                fu, fv = np.mod(uu, 1.0), np.mod(vv, 1.0)
                k = np.clip(np.minimum(np.minimum(fu, 1 - fu), np.minimum(fv, 1 - fv)) / soft, 0, 1)
                smp = smp.copy()
                smp[..., 3] *= k * k
            self.blend(smp, m, rgba, add, y0, y1, x0, x1)

    def image(self):
        return Image.fromarray((np.clip(self.c, 0, 1) * 255).astype(np.uint8))


def load_obj(path):
    vs, ts, fs = [], [], []
    for ln in open(path):
        p = ln.split()
        if not p:
            continue
        if p[0] == "v":
            vs.append([float(x) for x in p[1:4]])
        elif p[0] == "vt":
            ts.append([float(x) for x in p[1:3]])
        elif p[0] == "f":
            fs.append([int(q.split("/")[0]) - 1 for q in p[1:4]])
    return vs, ts, fs


def find(node, name):
    if node["name"] == name:
        return node
    for k in node["kids"]:
        r = find(k, name)
        if r:
            return r
    return None


# ---------- 变换
def qrot(q, v):
    x, y, z, w = q["x"], q["y"], q["z"], q["w"]
    u = np.array([x, y, z])
    v = np.asarray(v, float)
    return 2 * np.dot(u, v) * u + (w * w - np.dot(u, u)) * v + 2 * w * np.cross(u, v)


class Xf:
    """世界变换：p_world = R·(s ∘ p) + t，按父子链组合"""
    def __init__(self, chain=()):
        self.chain = list(chain)

    def child(self, n):
        return Xf(self.chain + [(np.array([n["pos"]["x"], n["pos"]["y"], n["pos"]["z"]]), n["rot"], np.array([n["scale"]["x"], n["scale"]["y"], n["scale"]["z"]]))])

    def point(self, p):
        p = np.asarray(p, float)
        for t, r, s in reversed(self.chain):
            p = qrot(r, p * s) + t
        return p

    def vec(self, v):
        v = np.asarray(v, float)
        for t, r, s in reversed(self.chain):
            v = qrot(r, v)
        return v

    def scale(self):
        k = np.ones(3)
        for t, r, s in self.chain:
            k = k * np.abs(s)
        return k


def mat(node, kind):
    """材质 → (贴图名, 是否加色, 着色 rgba)"""
    ms = node["comps"].get(kind, {}).get("mats", [])
    m = ms[0] if ms and isinstance(ms[0], dict) else {}
    tn = m.get("tex", {}).get("_MainTex")
    sh = m.get("shader", "") or ""
    add = "Additive" in sh or "Add " in sh or sh.endswith("Add")
    cols = m.get("cols", {})
    fl = m.get("floats") or {}
    if "_DstBlend" in fl and ("Disturb" in sh or "Dissolve" in sh):
        add = fl["_DstBlend"] == 1.0   # Blend One One = 加色；One OneMinusSrcAlpha = 透明混合
    if ("Disturb" in sh or "Dissolve(CustomData)" in sh) and "_MainColor" in cols:
        tint = np.array(cols["_MainColor"], float) * (2.0 if add else 1.6)   # Torappu 扰动 / 溶解着色器用 _MainColor
    elif "_TintColor" in cols:
        tint = np.array(cols["_TintColor"]) * 2.0
    elif "_MainColor" in cols:
        tint = np.array(cols["_MainColor"], float)
    elif "_Color" in cols:
        tint = np.array(cols["_Color"], float)
    else:
        tint = np.ones(4)
    tint = tint.copy()
    tint[3] = min(tint[3], 1.0)
    return tn, add, tint


class Inst:
    """一个 prefab 实例：t0 开始，stop 之后循环发射停止、网格淡出；anchor = 根节点屏幕像素位置；flip = -1 朝左；
    path = (t_a, t_b, fn(t)→像素)：拖尾和按距离发射跟它走；line = (a, b) 或 fn(t)→(a, b)：连线两端"""
    def __init__(self, root, prefab, t0, anchor, stop=None, flip=1, ground=None, path=None, line=None, seed=1, mesh_life=0.6, rot_deg=0.0, scale=1.0, only=None, skip=()):
        self.prefab, self.t0, self.anchor, self.flip = prefab, t0, np.asarray(anchor, float), flip
        self.stop = stop if stop is not None else t0 + 1e9
        self.ground = ground if ground is not None else (find(root, "rotation_z") is not None)
        self.path, self.line, self.mesh_life, self.rot, self.k = path, line, mesh_life, math.radians(rot_deg), scale
        self.rnd = random.Random(seed)
        self.items = []
        self.only, self.skip = only, skip
        self.missing = set()
        self._walk(root, Xf(), "", 0)

    def proj(self, p):
        x, y = p[0], p[1] * (cfg.GROUND_SY if self.ground else 1.0)
        if self.rot:
            c, s = math.cos(self.rot), math.sin(self.rot)
            x, y = x * c - y * s, x * s + y * c
        return self.anchor + np.array([x * self.flip, -y]) * cfg.S * self.k

    def _walk(self, n, xf, path, depth):
        path = (path + "/" + n["name"]) if path else n["name"]
        xf = xf.child(n) if depth > 0 else Xf()
        if not n["active"] or n["name"] in self.skip:
            return
        c = n["comps"]
        use = self.only is None or n["name"] in self.only
        if use and "ParticleSystem" in c and "ParticleSystemRenderer" in c:
            self.items.append(PSim(self, n, xf, path))
        if use and "MeshRenderer" in c:
            ob = os.path.join(cfg.MESH, "%s__%s.obj" % (self.prefab, path.replace("/", "_")))
            if os.path.exists(ob):
                self.items.append(MeshR(self, n, xf, ob))
        if use and "TrailRenderer" in c and self.path is not None:
            self.items.append(TrailR(self, n, xf))
        if use and "LineRenderer" in c and self.line is not None:
            self.items.append(LineR(self, n))
        for k in n["kids"]:
            self._walk(k, xf, path, depth + 1)

    def draw(self, cv, t):
        for it in self.items:
            it.draw(cv, t)

    def tex(self, name):
        im = tex(name) if name else None
        if name and im is None:
            self.missing.add(name)
        return im


class PSim:
    def __init__(self, I, n, xf, path):
        self.I, self.n, self.xf = I, n, xf
        self.ps = P = n["comps"]["ParticleSystem"]
        self.tn, self.add, self.tint = mat(n, "ParticleSystemRenderer")
        rd = n["comps"]["ParticleSystemRenderer"]
        self.mode = rd.get("m_RenderMode", 0)
        self.ls = rd.get("m_LengthScale", 2.0)
        self.mesh = None
        if self.mode == 4:
            ob = os.path.join(cfg.MESH, "%s__%s.obj" % (I.prefab, path.replace("/", "_")))
            self.mesh = load_obj(ob) if os.path.exists(ob) else None
        dl = P.get("startDelay")
        self.delay = curve(dl, 0, 0.5) if isinstance(dl, dict) else float(dl or 0)
        self.parts = []
        E = P.get("EmissionModule", {})
        t0 = I.t0 + self.delay
        dur = P.get("lengthInSec", 1.0)
        loop = P.get("looping", False)
        end = min(I.stop if loop else t0 + dur, cfg.END)
        if not E.get("enabled"):
            return
        for b in E.get("m_Bursts", []):
            cc = b.get("countCurve", {"scalar": b.get("minCount", 1)})
            reps = int(b.get("cycleCount", 1) or 1)
            cyc = t0
            while cyc < end:
                for _ in range(reps):
                    for _ in range(int(round(curve(cc, 0, I.rnd.random())))):
                        self.spawn(cyc + b["time"], None)
                if not loop or dur <= 0:
                    break
                cyc += dur
        rate = E.get("rateOverTime", {})
        tt, acc = t0, 0.0
        while tt < end and rate:
            acc += curve(rate, ((tt - t0) % dur) / dur if dur else 0, I.rnd.random()) / 30.0
            while acc >= 1:
                acc -= 1
                self.spawn(tt + I.rnd.random() / 30.0, None)
            tt += 1 / 30.0
        rdist = E.get("rateOverDistance", {}).get("scalar", 0)
        if rdist and I.path is not None:
            a, b, fn = I.path
            last, acc = None, 0.0
            for tt in np.linspace(a, b, 240):
                p = fn(tt)
                if last is not None:
                    acc += np.linalg.norm(p - last) / cfg.S * rdist
                    while acc >= 1:
                        acc -= 1
                        self.spawn(tt, p)
                last = p

    def spawn(self, t, at_px):
        I, P, rr = self.I, self.ps, self.I.rnd.random
        IM, Sh = P["InitialModule"], P.get("ShapeModule", {})
        life = curve(IM["startLifetime"], 0, rr())
        spd = curve(IM["startSpeed"], 0, rr())
        sz = curve(IM["startSize"], 0, rr())
        szy = curve(IM["startSizeY"], 0, rr()) if IM.get("size3D") else sz
        rot = curve(IM["startRotation"], 0, rr())
        d = np.array([0.0, 0.0, 1.0])
        off = np.zeros(3)
        if Sh.get("enabled"):
            typ = Sh.get("type", 4)
            a = rr() * 2 * math.pi
            rad = Sh["radius"]["value"] if isinstance(Sh.get("radius"), dict) else Sh.get("radius", 0)
            sc = Sh.get("m_Scale", {"x": 1, "y": 1, "z": 1})
            if typ in (0, 1):   # 球
                v = np.array([rr() * 2 - 1, rr() * 2 - 1, rr() * 2 - 1])
                v /= (np.linalg.norm(v) or 1)
                d, off = v, v * rad * rr()
            else:               # 锥 / 圆 / 边 等都按锥近似
                ang = math.radians(Sh.get("angle", 25))
                c = math.cos(ang * rr())
                sn = math.sqrt(max(0, 1 - c * c))
                d = np.array([math.cos(a) * sn, math.sin(a) * sn, c])
                off = np.array([math.cos(a), math.sin(a), 0]) * rad * rr()
            d = d * np.array([sc.get("x", 1), sc.get("y", 1), sc.get("z", 1)])
            off = off * np.array([sc.get("x", 1), sc.get("y", 1), 1])
            sr = Sh.get("m_Rotation", {"x": 0, "y": 0, "z": 0})
            if any(sr.get(k, 0) for k in "xyz"):
                rx, ry = math.radians(sr.get("x", 0)), math.radians(sr.get("y", 0))
                d = np.array([d[0], d[1] * math.cos(rx) - d[2] * math.sin(rx), d[1] * math.sin(rx) + d[2] * math.cos(rx)])
                d = np.array([d[0] * math.cos(ry) + d[2] * math.sin(ry), d[1], -d[0] * math.sin(ry) + d[2] * math.cos(ry)])
        k = self.xf.scale()[0]
        p0 = self.I.proj(self.xf.point(off)) if at_px is None else np.asarray(at_px, float) + np.array([off[0], -off[1]]) * cfg.S
        dw = self.xf.vec(d)
        v = np.array([dw[0] * self.I.flip, -dw[1] * (cfg.GROUND_SY if self.I.ground else 1)]) * spd * cfg.S * self.I.k
        self.parts.append(dict(t=t, p=p0, v=v, life=max(life, 0.02), sz=sz * k, szy=szy * k, rot=rot, r=rr(), r2=rr(), fr=rr()))

    def draw(self, cv, t):
        img = self.I.tex(self.tn)
        if img is None:
            return
        P = self.ps
        IM = P["InitialModule"]
        C, Z, RO, UV = P.get("ColorModule", {}), P.get("SizeModule", {}), P.get("RotationModule", {}), P.get("UVModule", {})
        damp = 0.6 if (P.get("ClampVelocityModule", {}).get("enabled") or P.get("LimitVelocityModule", {}).get("enabled")) else 1.0
        S, k = cfg.S, self.I.k
        for q in self.parts:
            age = t - q["t"]
            if age < 0 or age > q["life"]:
                continue
            u = age / q["life"]
            c = mmg(IM["startColor"], u, q["r"]) * self.tint
            if C.get("enabled"):
                c = c * mmg(C["gradient"], u, q["r2"])
            if c[3] <= 0.003:
                continue
            kk = curve(Z["curve"], u, q["r2"]) if Z.get("enabled") else 1.0
            pos = q["p"] + q["v"] * age * damp
            rot = q["rot"] + (curve(RO["curve"], u, q["r"]) * age if RO.get("enabled") else 0)
            sub = img
            if UV.get("enabled"):
                tx, ty = max(1, UV.get("tilesX", 1)), max(1, UV.get("tilesY", 1))
                fr = int(curve(UV["frameOverTime"], u, q["fr"]) * tx * ty) % (tx * ty)
                hh, ww = img.shape[0] // ty, img.shape[1] // tx
                sub = img[(fr // tx) * hh:(fr // tx + 1) * hh, (fr % tx) * ww:(fr % tx + 1) * ww]
            hx, hy = q["sz"] * kk * S * 0.5 * k, q["szy"] * kk * S * 0.5 * k
            if self.mode == 4 and self.mesh is not None:
                vs, ts, fs = self.mesh
                sx, sy = hx * 2, hy * 2 * (cfg.GROUND_SY if self.I.ground else 1)
                cv.mesh(vs, ts, fs, sub, lambda v: pos + np.array([v[0] * sx * self.I.flip, -v[1] * sy]), c, self.add)
            elif self.mode == 1:   # 拉伸 billboard
                vv = q["v"]
                n = np.linalg.norm(vv)
                if n < 1e-6:
                    continue
                dv = vv / n
                L = hx * abs(self.ls)
                cv.quad(sub[:, ::-1] if self.ls < 0 else sub, pos - dv * L, dv * L, np.array([-dv[1], dv[0]]) * hx, c, self.add)
            else:
                cr, sr = math.cos(rot), math.sin(rot)
                cv.quad(sub, pos, (cr * hx, -sr * hx), (sr * hy, cr * hy), c, self.add)


class MeshR:
    """MeshRenderer 节点（动画曲线读不到）：0.12 s 淡入，循环 prefab 持续到 stop，一次性 prefab 显示 mesh_life 后淡出"""
    def __init__(self, I, n, xf, ob):
        self.I, self.xf = I, xf
        self.tn, self.add, self.tint = mat(n, "MeshRenderer")
        sh = ((n["comps"]["MeshRenderer"].get("mats") or [{}])[0] or {}).get("shader", "") or ""
        self.soft = 0.25 if ("Disturb" in sh or "Dissolve" in sh) else 0.0
        vs, self.ts, self.fs = load_obj(ob)
        self.P = [I.proj(xf.point(v)) for v in vs]

    def draw(self, cv, t):
        I = self.I
        img = I.tex(self.tn)
        if img is None or t < I.t0:
            return
        end = min(I.stop, I.t0 + I.mesh_life) if I.stop < 1e8 else I.t0 + I.mesh_life
        if t > end + 0.25:
            return
        a = min(1, (t - I.t0) / 0.12) * (1 - max(0, min(1, (t - end) / 0.25)))
        P = self.P
        cv.mesh(list(range(len(P))), self.ts, self.fs, img, lambda i: P[i], self.tint * np.array([1, 1, 1, a]), self.add, soft=self.soft)


class TrailR:
    def __init__(self, I, n, xf):
        tr = n["comps"]["TrailRenderer"]
        P = tr["m_Parameters"]
        self.I, self.time, self.wm, self.wk, self.g = I, tr["m_Time"], P["widthMultiplier"], P["widthCurve"]["m_Curve"], P["colorGradient"]
        self.tn, self.add, self.tint = mat(n, "TrailRenderer")

    def draw(self, cv, t):
        a, b, fn = self.I.path
        img = self.I.tex(self.tn)
        if t < a or t > b + self.time or img is None:
            return
        tw = img.shape[1]
        head, tail = min(t, b), max(a, t - self.time)
        if head - tail < 1e-3:
            return
        n = 36
        for i in range(n):
            ta, tb = head - (head - tail) * i / n, head - (head - tail) * (i + 1) / n
            u = i / n
            pa, pb = fn(ta), fn(tb)
            w = keys_eval(self.wk, u) * self.wm * cfg.S * 0.5 * self.I.k
            c = grad_eval(self.g, u) * self.tint
            dv = pb - pa
            L = np.linalg.norm(dv) or 1
            dv = dv / L
            x0 = int(u * (tw - 1))
            cv.quad(img[:, x0:min(tw, x0 + max(2, tw // n + 1))], (pa + pb) / 2, dv * (L / 2 + 1), np.array([-dv[1], dv[0]]) * w, c, self.add)


class LineR:
    """LineRenderer：两点之间，贴图沿长度平铺（按宽度比例重复）并流动"""
    def __init__(self, I, n):
        lr = n["comps"]["LineRenderer"]
        P = lr["m_Parameters"]
        self.I, self.wm, self.wk, self.g = I, P["widthMultiplier"], P["widthCurve"]["m_Curve"], P["colorGradient"]
        self.mode = P.get("textureMode", 0)
        self.tn, self.add, self.tint = mat(n, "LineRenderer")

    def draw(self, cv, t):
        I = self.I
        img = I.tex(self.tn)
        if img is None or t < I.t0 or t > I.stop + 0.2:
            return
        a, b = I.line(t) if callable(I.line) else I.line
        a, b = np.asarray(a, float), np.asarray(b, float)
        th, tw = img.shape[:2]
        L = np.linalg.norm(b - a) or 1
        dv = (b - a) / L
        w = self.wm * cfg.S * 0.5 * I.k
        fade = min(1, (t - I.t0) / 0.1) * (1 - max(0, min(1, (t - I.stop) / 0.2)))
        reps = max(1, int(round(L / max(4, w * 2 * tw / th)))) if self.mode in (1, 2) else 1
        n = max(12, reps * 2)
        for i in range(n):
            u0, u1 = i / n, (i + 1) / n
            pa, pb = a + (b - a) * u0, a + (b - a) * u1
            ww = keys_eval(self.wk, (u0 + u1) / 2) * w
            c = grad_eval(self.g, (u0 + u1) / 2) * self.tint * np.array([1, 1, 1, fade])
            uu = ((u0 + u1) / 2 * reps + t * 0.6) % 1.0
            x0 = int(uu * (tw - 1))
            cv.quad(img[:, x0:min(tw, x0 + max(2, tw // max(1, n // reps) + 1))], (pa + pb) / 2, dv * (L / n / 2 + 1), np.array([-dv[1], dv[0]]) * ww, c, self.add)
