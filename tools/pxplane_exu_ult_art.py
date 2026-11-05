"""能天使终结技转平面（docs/262 §11，开关 ult/px_plane）的像素图形：举枪大闪光、脚下光柱、头顶大光环、爆裂弹爆点、焦痕（帧条，pxplane_bake_exusiai.py 烤），
以及锁定范围环、锁定框（运行时逐格画，game/scripts/run/ult_px_exusiai.gd 同算法，改一边要改另一边）。单位：美术像素（1 = g.PX = 2 世界像素）。"""
import math

from pxplane_exu_art import Buf, RAMP, GOLD, SMOKE, CHIP, SQ, hsh, _spike, _rot

N = RAMP["n"]
G = RAMP["g"]


def ult_raise():
    """举枪大闪光（原点 = 枪口，朝右上 -60°；左枪水平翻转）：3 拍。白芯 5×5 + 前向长芒 22 格（根部 5 宽）+ 四道侧芒 10 + 后芒 6；第 1 拍缩一半；第 2 拍一圈余烬"""
    a = math.radians(-60)
    d = (math.cos(a), math.sin(a))
    nv = (-d[1], d[0])
    fr = [Buf(), Buf(), Buf()]
    for k, sc in enumerate((1.0, 0.55)):
        b = fr[k]
        L = int(22 * sc)
        _spike(b, (d[0] * 2, d[1] * 2), d, L, [G[6], G[6], G[6], G[5], G[5], G[5], G[4], G[4], G[3]])
        for q in (-2, -1, 1, 2):
            _spike(b, (d[0] * 2 + nv[0] * q, d[1] * 2 + nv[1] * q), d, max(2, L // (3 if abs(q) == 1 else 5)), [G[5], G[4]], keep=True)
        for sd in (nv, (-nv[0], -nv[1]), _rot(d, 0.6), _rot(d, -0.6)):
            _spike(b, (sd[0] * 3, sd[1] * 3), sd, int(10 * sc), [G[5], G[4], G[3]])
        _spike(b, (-d[0] * 2, -d[1] * 2), (-d[0], -d[1]), int(6 * sc), [G[4], G[3]])
        R = 2 if k == 0 else 1
        for x in range(-R - 1, R + 2):
            for y in range(-R - 1, R + 2):
                if abs(x) + abs(y) <= R + 1:
                    b.put(x, y, G[6] if abs(x) + abs(y) <= R else G[5])
    for i in range(6):
        t = i / 6 * math.tau + 0.3
        fr[2].put(math.cos(t) * 6, math.sin(t) * 6 + 2, G[3])
    return fr


def ult_pillar():
    """脚下竖光柱（原点 = 脚底）：4 拍，宽 7 → 5 → 3 → 1 格、高 90 → 56 格；白芯、两侧金、外缘朱橙，上段收窄；底部一圈压扁小环"""
    fr = []
    for k, (w, h) in enumerate(((7, 90), (5, 80), (3, 70), (1, 56))):
        b = Buf()
        hw = w // 2
        for y in range(h):
            u = y / h
            for q in range(-hw, hw + 1):
                if u > 0.85 and abs(q) == hw and hw > 0:
                    continue
                col = G[6] if q == 0 else (G[5] if abs(q) < hw else N[4])
                if u > 0.7:
                    col = G[5] if q == 0 else N[4]
                b.put(q, -y, col)
        for i in range(28):
            t = i / 28 * math.tau
            if hsh(i, k, 2) % 4:
                b.put(math.cos(t) * (10 + 3 * k), math.sin(t) * (10 + 3 * k) * SQ, N[4] if k < 2 else N[3])
        fr.append(b)
    return fr


def ult_halo():
    """头顶大光环（原点 = 环心）：8 拍循环。椭圆环 rx 15 / ry 4、两层（白金 / 金），一段亮光绕环走；外圈 16 道光刺按拍长短闪（原作 angel_02 的放大版）"""
    fr = []
    for k in range(8):
        b = Buf()
        n = 96
        for i in range(n):
            t = i / n * math.tau
            hot = ((i - k * n / 8) % n) < 10
            b.put(math.cos(t) * 15, math.sin(t) * 4, GOLD[6] if hot else GOLD[5])
            b.put_if_empty(math.cos(t) * 14, math.sin(t) * 3.4, GOLD[5] if hot else GOLD[4])
        for i in range(16):
            if hsh(i, k, 7) % 4 == 0:
                continue
            t = i / 16 * math.tau + 0.1
            L = 2 + hsh(i, k, 3) % 4
            for s in range(1, L + 1):
                b.put(math.cos(t) * (15 + s * 1.2), math.sin(t) * (4 + s * 0.9), GOLD[5] if s < L else GOLD[4])
        fr.append(b)
    return fr


def ult_burst(var=0):
    """路上的爆裂弹爆点芯（原点 = 爆心，立起层）：2 拍硬星芯。第 0 拍 9×9 白金芯 + 8 道硬芒（朱橙 / 金交替，12 / 9 格）；第 1 拍芯暗一阶 + 芒外移断开 + 一圈火星。
    不画烟团（11-05 用户：路上的爆炸用粒子云，不要烟）；体量交给运行时的闪烁粒子云 cloud_px()。var 1 芒转 22.5°"""
    fr = [Buf() for _ in range(2)]
    off = math.pi / 8 if var else 0.0
    for i in range(8):
        a = off + i / 8 * math.tau
        d = (math.cos(a), math.sin(a))
        C = N if i % 2 == 0 else G
        L = 12 if i % 2 == 0 else 9
        _spike(fr[0], (d[0] * 4, d[1] * 4), d, L, [C[6], C[6], C[5], C[5], C[4], C[4], C[3]])
        for s2 in range(L // 2 + 4, L + 6):
            fr[1].put(d[0] * s2, d[1] * s2, C[4] if s2 < L + 3 else C[3])
    for x in range(-5, 6):
        for y in range(-5, 6):
            r = abs(x) + abs(y)
            if r <= 4:
                fr[0].put(x, y, G[6] if r <= 3 else G[5])
            if r <= 3 and hsh(x, y, 1) % 4:
                fr[1].put(x, y, G[5] if r <= 1 else N[4])
    for i in range(16):
        t = i / 16 * math.tau + 0.2
        fr[1].put_if_empty(math.cos(t) * 8, math.sin(t) * 8, G[5] if i % 2 else N[5])
    return fr


def ult_scorch():
    """爆点地上的焦痕（贴地，压扁）：4 拍。断续朱橙边环 r 14 → 18，内侧一圈深色；最后一拍只剩几点余烬"""
    fr = []
    for k in range(4):
        b = Buf()
        rr = 14 + k * 1.4
        n = 72
        for i in range(n):
            t = i / n * math.tau
            if k < 3:
                if hsh(i, k, 9) % 4:
                    b.put(math.cos(t) * rr, math.sin(t) * rr * SQ, (N[5], N[4], N[3])[k])
                    b.put_if_empty(math.cos(t) * (rr - 1.3), math.sin(t) * (rr - 1.3) * SQ, N[1])
            elif i % 6 == 0:
                b.put(math.cos(t) * rr, math.sin(t) * rr * SQ, N[2])
        fr.append(b)
    return fr


RING_COLS = [GOLD[6], GOLD[5], N[4], N[2]]


def ring_px(r_world, age_beats, seed=0):
    """锁定范围环（运行时逐格画，贴地压扁）：半径 r（世界像素），按美术像素沿周长取点，断续（每 7 点缺 1）；
    颜色按年龄（拍）由亮到暗：白金 → 金 → 朱橙 → 暗朱，4 拍后不画。返回 [(x, y, 色)]（世界像素偏移，已对齐 2 像素格）"""
    if age_beats < 0 or age_beats >= len(RING_COLS):
        return []
    n = max(24, int(math.tau * r_world / 2.0))
    out = []
    for i in range(n):
        if (i + age_beats * 3 + seed) % 7 == 0:
            continue
        t = i / n * math.tau
        out.append((round(math.cos(t) * r_world / 2) * 2, round(math.sin(t) * r_world * SQ / 2) * 2, RING_COLS[age_beats]))
    return out


def reticle_px(h_world, f, elite):
    """锁定框（运行时逐格画，立起）：四角括号。f = 帧号（0–3 锁上：从 1.6h 收到 h；4–5 保持、5 拍胀 1 格；6–7 碎：括号往外弹开、变暗）；
    括号每臂 3 格（精英 4 格、2 格粗），金色；中心一点朱橙（精英 2×2）。返回 [(x, y, 色)]（世界像素偏移）"""
    if f <= 3:
        h = h_world * (1.6 - 0.6 * f / 3.0)
    elif f <= 5:
        h = h_world + (2 if f == 5 else 0)
    else:
        h = h_world * (1.3 if f == 6 else 1.7)
    arm = 4 if elite else 3
    th = 2 if elite else 1
    col = GOLD[6] if f in (3, 6) else (GOLD[5] if f < 6 else GOLD[3])
    out = []
    hp = round(h / 2)
    for sx in (-1, 1):
        for sy in (-1, 1):
            for j in range(arm):
                for w in range(th):
                    out.append(((sx * hp - sx * j) * 2, (sy * hp - sy * w) * 2, col))
                    out.append(((sx * hp - sx * w) * 2, (sy * hp - sy * j) * 2, col))
    if f < 6:
        out += [(0, 0, N[4]), (2, 0, N[4]), (0, 2, N[4]), (2, 2, N[4])] if elite else [(0, 0, N[4])]
    return out


def hf01(k, sd, salt):
    """0–1 的坐标哈希（同 GDScript _hf）"""
    return (hsh(k, sd, salt) % 1000) / 1000.0


CLOUD_COLS = [GOLD[6], GOLD[5], N[5], N[4], GOLD[4]]


def cloud_px(age, sd, size, n):
    """闪烁粒子云（运行时，立起层；同 ult_px_exusiai._cloud）：n 颗 1–2 格的小亮点（白金 / 金 / 浅朱 / 朱橙，少量暗金），0.35 秒内往外炸开到 size（美术像素，按面积均匀铺满），
    之后逐拍闪烁（每拍三分之一不亮）、慢慢漂上去、越剩越少，1.2 秒散完。返回 [(x, y, 色, 是否进发光层, 边长格)]（美术像素偏移，y 已压扁）"""
    out = []
    if age < 0.0 or age > 1.2:
        return out
    fr = int(age * 15.0)
    u = min(1.0, age / 0.35)
    grow = 1.0 - (1.0 - u) ** 2
    for k in range(n):
        if age > 0.25 and (fr + k) % 3 == 0:
            continue
        if hf01(k, sd, 84) < age / 1.2:
            continue
        a = math.tau * hf01(k, sd, 81)
        r = size * math.sqrt(hf01(k, sd, 82)) * grow + age * 4.0
        x = math.cos(a) * r
        y = math.sin(a) * r * SQ - age * 10.0 * hf01(k, sd, 83)
        hc = hf01(k, sd, 85)
        ci = 0 if hc < 0.3 else (1 if hc < 0.6 else (2 if hc < 0.8 else (3 if hc < 0.95 else 4)))
        if age > 0.6:
            ci = min(4, ci + 1)
        out.append((x, y, CLOUD_COLS[ci], ci == 0 and age < 0.3, 2 if k % 3 == 0 else 1))
    return out


def blast_core(beat):
    """最大爆炸的亮核（美术像素，原点 = 爆心）：只有中心小一圈（半径 14 格，按坐标哈希毛边），白芯 → 金 → 朱橙，亮 2 拍（第 1 拍缩小变暗）；不做整块平涂的大圆"""
    out = []
    if beat < 0 or beat > 1:
        return out
    R = 14 if beat == 0 else 9
    for x in range(-R, R + 1):
        for y in range(-R, R + 1):
            yy = y / SQ
            r = math.sqrt(x * x + yy * yy)
            if r > R - (hsh(x, y, 31) % 3):
                continue
            u = r / R
            c = (G[6] if u < 0.35 else (G[5] if u < 0.65 else N[4])) if beat == 0 else (G[5] if u < 0.4 else N[4])
            out.append((x, y, c, u < 0.35))
    return out


def blast_ring(R0, R1, t):
    """最大爆炸的冲击环（贴地压扁，美术像素）：t = 起爆后的拍数（可小数）；3.5 拍从 R0 推到 R1（先快后慢），8 格厚（外缘白金 → 金 → 朱橙 → 暗朱），
    环后 6–14 格的地面一闪（淡金点，隔行）；到边后 2 拍淡掉。返回 [(x, y, 色, 不透明度)]"""
    out = []
    if t < 0 or t > 5.5:
        return out
    u = min(1.0, t / 3.5)
    r = R0 + (R1 - R0) * (1 - (1 - u) ** 2)
    al = 1.0 if t <= 3.5 else max(0.0, 1.0 - (t - 3.5) / 2.0)
    n = max(48, int(math.tau * r))
    cols = [G[6], G[6], G[5], G[5], N[5], N[4], N[3], N[2]]
    for i in range(n):
        th = i / n * math.tau
        ct, sn = math.cos(th), math.sin(th)
        for j in range(8):
            rr = r - j
            out.append((round(ct * rr), round(sn * rr * SQ), cols[j], al))
        if t <= 4.0:
            for j2 in range(6, 15, 2):
                if (i + j2) % 3:
                    continue
                rr = r - j2 - 2
                out.append((round(ct * rr), round(sn * rr * SQ), G[4], 0.45 * al * (1.0 - (j2 - 6) / 9.0)))
    return out


def spray_px(age, sd, out_dir, n=22, k=1.0, cols=None):
    """怪物崩解的本色像素喷散（同艾丽妮 _draw_sprays）：n 颗，沿 out_dir ± 63° 往外喷，有重量（G 260）、落地停一下熄灭；头两拍每 3 颗一颗白芯。
    cols = 怪物代表色的亮 / 稍亮 / 本色 / 暗四阶。返回 [(x, y, 色, 不透明度, 边长格)]（世界像素偏移）"""
    out = []
    if age < 0 or age > 1.3:
        return out
    base = math.atan2(out_dir[1], out_dir[0])
    for q in range(int(n * min(1.4, k))):
        ang = base + (hf01(q, sd, 71) - 0.5) * 2.2
        spd = (30.0 + 70.0 * hf01(q, sd, 72)) * k
        vh = 30.0 + 60.0 * hf01(q, sd, 73)
        Gv = 260.0
        tl = 2.0 * vh / Gv
        t = min(age, 0.9)
        tt = min(t, tl)
        h = max(0.0, vh * tt - 0.5 * Gv * tt * tt) if t < tl else 0.0
        x = math.cos(ang) * spd * tt
        y = math.sin(ang) * spd * tt * SQ - h
        c = cols[q % 4]
        if age < 2.0 / 15.0 and q % 3 == 0:
            c = "#ffffff"
        al = 1.0 if age < 0.9 else max(0.0, (1.3 - age) / 0.4)
        out.append((x, y, c, al, 2 if q % 3 != 2 else 1))
    return out
