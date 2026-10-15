# -*- coding: utf-8 -*-
"""Spine 3.5 二进制 .skel → Spine 3.5 JSON（tools/prts_spine.py 用，docs/36 §9.1）。

PRTS 上较早的干员（spine/ 前缀）是 Spine 3.5.51 二进制，3.8 运行时读不了，而 spine-ts 3.5 只有 SkeletonJson、没有二进制读取器。
这里逐行移植官方 spine-csharp 3.5.51 标签的 SkeletonBinary.cs（注意：3.5 分支头上的代码已混入 3.6 的双色 / 裁剪，格式不同，别用），
读成 3.5 JSON 交给 spine-ts 3.5.51 渲染。必须恰好读到文件末尾，否则视为格式不符并报错。

    python tools/prts_spine35.py <in.skel> <out.json>
"""
import json, struct, sys

TRANSFORM = ["normal", "onlyTranslation", "noRotationOrReflection", "noScale", "noScaleOrReflection"]
BLEND = ["normal", "additive", "multiply", "screen"]
POSITION = ["fixed", "percent"]
SPACING = ["length", "fixed", "percent"]
ROTATE = ["tangent", "chain", "chainScale"]


class R:
    def __init__(self, b):
        self.b, self.p = b, 0

    def byte(self):
        if self.p >= len(self.b):
            raise EOFError("读过文件末尾（位置 %d）" % self.p)
        v = self.b[self.p]
        self.p += 1
        return v

    def sbyte(self):
        v = self.byte()
        return v - 256 if v > 127 else v

    def bool(self):
        return self.byte() != 0

    def int(self):
        v = struct.unpack_from(">i", self.b, self.p)[0]
        self.p += 4
        return v

    def float(self):
        v = struct.unpack_from(">f", self.b, self.p)[0]
        self.p += 4
        return v

    def varint(self, pos=True):
        b = self.byte()
        r = b & 0x7F
        sh = 7
        while b & 0x80 and sh <= 28:
            b = self.byte()
            r |= (b & 0x7F) << sh
            sh += 7
        r &= 0xFFFFFFFF
        if pos:
            return r - (1 << 32) if r & 0x80000000 else r
        return (r >> 1) ^ -(r & 1)

    def string(self):
        n = self.varint()
        if n == 0:
            return None
        if n == 1:
            return ""
        s = self.b[self.p:self.p + n - 1].decode("utf-8")
        self.p += n - 1
        return s

    def floats(self, n):
        return [self.float() for _ in range(n)]

    def shorts(self):
        n = self.varint()
        out = []
        for _ in range(n):
            out.append((self.byte() << 8) | self.byte())
        return out


def color(c):
    return "%08x" % (c & 0xFFFFFFFF)


def vertices(r, count):
    """未加权：2·count 个坐标；加权：每顶点 [骨数, (骨, x, y, 权重)…]（与 3.5 JSON 同格式）"""
    if not r.bool():
        return r.floats(count * 2), False
    out = []
    for _ in range(count):
        bc = r.varint()
        out.append(bc)
        for _ in range(bc):
            out += [r.varint(), r.float(), r.float(), r.float()]
    return out, True


def attachment(r, aname, nonessential):
    name = r.string()
    a = {}
    if name is not None and name != aname:
        a["name"] = name
    t = r.byte()
    if t == 0:   # region
        a.update(type="region")
        path = r.string()
        if path is not None:
            a["path"] = path
        a["rotation"], a["x"], a["y"], a["scaleX"], a["scaleY"], a["width"], a["height"] = r.floats(7)
        a["color"] = color(r.int())
    elif t == 1:   # boundingbox
        vc = r.varint()
        a.update(type="boundingbox", vertexCount=vc)
        a["vertices"], _ = vertices(r, vc)
        if nonessential:
            r.int()
    elif t == 2:   # mesh
        a["type"] = "mesh"
        path = r.string()
        if path is not None:
            a["path"] = path
        a["color"] = color(r.int())
        vc = r.varint()
        a["uvs"] = r.floats(vc * 2)
        a["triangles"] = r.shorts()
        a["vertices"], _ = vertices(r, vc)
        a["hull"] = r.varint()
        if nonessential:
            a["edges"] = r.shorts()
            a["width"], a["height"] = r.float(), r.float()
    elif t == 3:   # linkedmesh
        a["type"] = "linkedmesh"
        path = r.string()
        if path is not None:
            a["path"] = path
        a["color"] = color(r.int())
        skin = r.string()
        if skin is not None:
            a["skin"] = skin
        a["parent"] = r.string()
        a["deform"] = r.bool()
        if nonessential:
            a["width"], a["height"] = r.float(), r.float()
    elif t == 4:   # path
        a["type"] = "path"
        a["closed"], a["constantSpeed"] = r.bool(), r.bool()
        vc = r.varint()
        a["vertexCount"] = vc
        a["vertices"], _ = vertices(r, vc)
        a["lengths"] = r.floats(vc // 3)
        if nonessential:
            r.int()
    else:
        raise ValueError("未知附件类型 %d（位置 %d）" % (t, r.p))
    return a


def skin(r, nonessential, slots, out):
    n = r.varint()
    if n == 0:
        return None
    for _ in range(n):
        si = r.varint()
        sm = out.setdefault(slots[si], {})
        for _ in range(r.varint()):
            an = r.string()
            sm[an] = attachment(r, an, nonessential)
    return out


def curve(r, f):
    c = r.byte()
    if c == 1:
        f["curve"] = "stepped"
    elif c == 2:
        f["curve"] = r.floats(4)
    elif c != 0:
        raise ValueError("未知曲线 %d（位置 %d）" % (c, r.p))


def animation(r, d, skin_names, skin_atts, slots, bones, iks, tcs, pcs, events):
    an = {}
    for _ in range(r.varint()):   # 槽
        sn = slots[r.varint()]
        sm = an.setdefault("slots", {}).setdefault(sn, {})
        for _ in range(r.varint()):
            tt, fc = r.byte(), r.varint()
            if tt == 1:
                fr = []
                for k in range(fc):
                    f = {"time": r.float(), "color": color(r.int())}
                    if k < fc - 1:
                        curve(r, f)
                    fr.append(f)
                sm["color"] = fr
            elif tt == 0:
                sm["attachment"] = [{"time": r.float(), "name": r.string()} for _ in range(fc)]
            else:
                raise ValueError("未知槽时间线 %d（位置 %d）" % (tt, r.p))
    for _ in range(r.varint()):   # 骨
        bn = bones[r.varint()]
        bm = an.setdefault("bones", {}).setdefault(bn, {})
        for _ in range(r.varint()):
            tt, fc = r.byte(), r.varint()
            fr = []
            for k in range(fc):
                if tt == 0:
                    f = {"time": r.float(), "angle": r.float()}
                elif tt in (1, 2, 3):
                    f = {"time": r.float(), "x": r.float(), "y": r.float()}
                else:
                    raise ValueError("未知骨时间线 %d（位置 %d）" % (tt, r.p))
                if k < fc - 1:
                    curve(r, f)
                fr.append(f)
            bm[["rotate", "translate", "scale", "shear"][tt]] = fr
    for _ in range(r.varint()):   # IK
        nm, fc = iks[r.varint()], r.varint()
        fr = []
        for k in range(fc):
            f = {"time": r.float(), "mix": r.float(), "bendPositive": r.sbyte() >= 0}
            if k < fc - 1:
                curve(r, f)
            fr.append(f)
        an.setdefault("ik", {})[nm] = fr
    for _ in range(r.varint()):   # 变换约束
        nm, fc = tcs[r.varint()], r.varint()
        fr = []
        for k in range(fc):
            f = {"time": r.float()}
            f["rotateMix"], f["translateMix"], f["scaleMix"], f["shearMix"] = r.floats(4)
            if k < fc - 1:
                curve(r, f)
            fr.append(f)
        an.setdefault("transform", {})[nm] = fr
    for _ in range(r.varint()):   # 路径约束
        nm = pcs[r.varint()]
        pm = an.setdefault("paths", {}).setdefault(nm, {})
        for _ in range(r.varint()):
            tt, fc = r.sbyte(), r.varint()
            fr = []
            for k in range(fc):
                if tt in (0, 1):
                    key = ["position", "spacing"][tt]
                    f = {"time": r.float(), key: r.float()}
                elif tt == 2:
                    f = {"time": r.float(), "rotateMix": r.float(), "translateMix": r.float()}
                else:
                    raise ValueError("未知路径时间线 %d（位置 %d）" % (tt, r.p))
                if k < fc - 1:
                    curve(r, f)
                fr.append(f)
            pm[["position", "spacing", "mix"][tt]] = fr
    for _ in range(r.varint()):   # 网格变形
        sk = skin_names[r.varint()]
        dm = an.setdefault("deform", {}).setdefault(sk, {})
        for _ in range(r.varint()):
            si = r.varint()
            sn = slots[si]
            for _ in range(r.varint()):
                att = r.string()
                fc = r.varint()
                fr = []
                for k in range(fc):
                    f = {"time": r.float()}
                    end = r.varint()
                    if end:
                        start = r.varint()
                        if start:
                            f["offset"] = start
                        f["vertices"] = r.floats(end)
                    if k < fc - 1:
                        curve(r, f)
                    fr.append(f)
                dm.setdefault(sn, {})[att] = fr
    n = r.varint()   # 绘制顺序
    if n:
        fr = []
        for _ in range(n):
            f = {"time": r.float()}
            offs = []
            for _ in range(r.varint()):
                offs.append({"slot": slots[r.varint()], "offset": r.varint()})
            f["offsets"] = offs
            fr.append(f)
        an["drawOrder"] = fr
    n = r.varint()   # 事件
    if n:
        fr = []
        for _ in range(n):
            f = {"time": r.float()}
            ed = events[r.varint()]
            f["name"] = ed[0]
            f["int"] = r.varint(False)
            f["float"] = r.float()
            f["string"] = r.string() if r.bool() else ed[1]
            fr.append(f)
        an["events"] = fr
    return an


def convert(data):
    r = R(data)
    sk = {"hash": r.string(), "spine": r.string(), "width": r.float(), "height": r.float()}
    if not (sk["spine"] or "").startswith("3.5"):
        raise ValueError("不是 Spine 3.5 二进制：版本 %r" % sk["spine"])
    ne = r.bool()
    if ne:
        sk["fps"] = r.float()
        sk["images"] = r.string()
    out = {"skeleton": sk}
    bones = []
    for i in range(r.varint()):
        b = {"name": r.string()}
        if i:
            b["parent"] = bones[r.varint()]["name"]
        b["rotation"], b["x"], b["y"], b["scaleX"], b["scaleY"], b["shearX"], b["shearY"], b["length"] = r.floats(8)
        b["transform"] = TRANSFORM[r.varint()]
        if ne:
            r.int()
        bones.append(b)
    out["bones"] = bones
    bn = [b["name"] for b in bones]
    slots = []
    for _ in range(r.varint()):
        s = {"name": r.string(), "bone": bn[r.varint()], "color": color(r.int())}
        att = r.string()
        if att is not None:
            s["attachment"] = att
        s["blend"] = BLEND[r.varint()]
        slots.append(s)
    out["slots"] = slots
    sn = [s["name"] for s in slots]
    ik = []
    for _ in range(r.varint()):
        c = {"name": r.string(), "order": r.varint()}
        c["bones"] = [bn[r.varint()] for _ in range(r.varint())]
        c["target"] = bn[r.varint()]
        c["mix"] = r.float()
        c["bendPositive"] = r.sbyte() >= 0
        ik.append(c)
    out["ik"] = ik
    tc = []
    for _ in range(r.varint()):
        c = {"name": r.string(), "order": r.varint()}
        c["bones"] = [bn[r.varint()] for _ in range(r.varint())]
        c["target"] = bn[r.varint()]
        (c["rotation"], c["x"], c["y"], c["scaleX"], c["scaleY"], c["shearY"],
         c["rotateMix"], c["translateMix"], c["scaleMix"], c["shearMix"]) = r.floats(10)
        tc.append(c)
    out["transform"] = tc
    pc = []
    for _ in range(r.varint()):
        c = {"name": r.string(), "order": r.varint()}
        c["bones"] = [bn[r.varint()] for _ in range(r.varint())]
        c["target"] = sn[r.varint()]
        c["positionMode"] = POSITION[r.varint()]
        c["spacingMode"] = SPACING[r.varint()]
        c["rotateMode"] = ROTATE[r.varint()]
        c["rotation"], c["position"], c["spacing"], c["rotateMix"], c["translateMix"] = r.floats(5)
        pc.append(c)
    out["path"] = pc
    skins, skin_names = {}, []
    d = skin(r, ne, sn, {})
    if d is not None:
        skins["default"] = d
        skin_names.append("default")
    for _ in range(r.varint()):
        nm = r.string()
        skins[nm] = skin(r, ne, sn, {}) or {}
        skin_names.append(nm)
    out["skins"] = skins
    evs, evl = {}, []
    for _ in range(r.varint()):
        nm = r.string()
        e = {"int": r.varint(False), "float": r.float(), "string": r.string()}
        evs[nm] = e
        evl.append((nm, e["string"]))
    out["events"] = evs
    anims = {}
    for _ in range(r.varint()):
        nm = r.string()
        anims[nm] = animation(r, out, skin_names, skins, sn, bn, [c["name"] for c in ik], [c["name"] for c in tc], [c["name"] for c in pc], evl)
    out["animations"] = anims
    if r.p != len(data):
        raise ValueError("没读到文件末尾：停在 %d / %d 字节（格式不符）" % (r.p, len(data)))
    return out


def main():
    src, dst = sys.argv[1], sys.argv[2]
    out = convert(open(src, "rb").read())
    json.dump(out, open(dst, "w", encoding="utf-8"), ensure_ascii=False)
    print("%s：骨 %d、槽 %d、动画 %d（%s）" % (out["skeleton"]["spine"], len(out["bones"]), len(out["slots"]), len(out["animations"]),
                                         " ".join(out["animations"])))


if __name__ == "__main__":
    main()
