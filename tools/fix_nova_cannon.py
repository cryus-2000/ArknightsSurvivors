# -*- coding: utf-8 -*-
"""两处修图（docs/41 记的 Codex v14/v15 可选项，10-11 自己做）：

  python tools/fix_nova_cannon.py nova      新星弹 proj_nova / @2x 四帧：中心偏暗 → 按到中心的距离把核心提亮到近白（外圈与 alpha 不动）
  python tools/fix_nova_cannon.py cannon    圣徒手炮像大号手枪 → e_saint* / e_saint_dark* 里露出枪管的 7 个姿势（attack 0–2、reload 3、melee 0–2）
                                            枪管加粗加长、枪口外扩成喇叭口、靠手处一圈箍；只改武器像素（搜索框内的旧枪管 + 透明像素），人物像素不动
  python tools/fix_nova_cannon.py all       两样都做
  python tools/fix_nova_cannon.py sheet     出前后对照表 build/portraits_out/cannon_strips.png / nova_strips.png（先于 all 跑一次记「前」）

枪管做法：每个姿势给一个 @2x 帧内的搜索框（只框住伸出手外的枪管）；框内不透明像素做 PCA 得到枪管轴向、长度与半厚，
按同一套参数（内部半厚固定 3.5、长度 +4、末 4 px 锥形外扩成炮口、离手 4–6 px 一圈箍）重新光栅化一根粗枪管，描 1 px 轮廓 #080E18，
明暗按轴向垂直方向分四档（上亮下暗，来光左上），只写到透明像素或旧枪管像素上。1x 帧条按 @2x 结果 2×2 取多数色缩回去，
同样只写到透明 / 旧枪管像素。两个变体（卡门 e_saint、伊比利亚 e_saint_dark）姿势相同、搜索框按各自像素略有偏移。
"""
import os, sys, math
from collections import Counter
import numpy as np
from PIL import Image, ImageDraw

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
INC = os.path.join(ROOT, "art", "incoming")
OUT = os.path.join(ROOT, "build", "portraits_out")
FW, FH = 80, 96   # @2x 单帧
OUTLINE = (8, 14, 24, 255)

# 搜索框（@2x 帧内坐标，x0, y0, x1, y1 含端点）：(变体, 帧条后缀, 帧号) → 框
BOXES = {
	("", "_attack", 0): (57, 35, 78, 45), ("_dark", "_attack", 0): (57, 35, 78, 45),
	("", "_attack", 1): (51, 35, 72, 42), ("_dark", "_attack", 1): (51, 35, 72, 42),
	("", "_attack", 2): (56, 21, 73, 31), ("_dark", "_attack", 2): (58, 22, 73, 31),
	("", "_reload", 3): (52, 42, 71, 50), ("_dark", "_reload", 3): (52, 42, 72, 50),
	("", "_melee", 2): (66, 40, 79, 50), ("_dark", "_melee", 2): (66, 40, 79, 50),
	("", "_melee", 0): (14, 16, 23, 30), ("_dark", "_melee", 0): (11, 17, 22, 30),
	("", "_melee", 1): (7, 24, 18, 32), ("_dark", "_melee", 1): (5, 25, 17, 33),
}
HALF = 3.5    # 新枪管内部半厚（@2x px；旧枪管内部约 5 px 高 → 新 7–8 px，连轮廓约 10 px）
EXT = 4       # 枪口方向加长
EXT_UP = 2    # 举起的姿势（melee 0/1）只加长 2、不做喇叭口，别顶到帧边
FLARE = 1.5   # 枪口喇叭口：末 4 px 内锥形外扩到 +1.5
FLARE_LEN = 4
BODY_C = (40.0, 52.0)   # 人物中心（判断哪头是握持端）

# 枪管明暗（轴向垂直方向从亮到暗；来光左上 = 上侧亮）
SHADES = [(216, 216, 216), (168, 168, 168), (144, 144, 144), (96, 96, 96)]
SHADES_BAND = [(192, 192, 192), (144, 144, 144), (120, 120, 120), (72, 72, 72)]


def _frames(path):
	im = Image.open(path).convert("RGBA")
	n = im.width // (FW if "@2x" in path else FW // 2)
	return im, n


def _pca(pts):
	a = np.asarray(pts, dtype=float)
	c = a.mean(axis=0)
	cov = np.cov((a - c).T)
	w, v = np.linalg.eigh(cov)
	u = v[:, int(np.argmax(w))]
	if np.dot(u, c - np.asarray(BODY_C)) < 0:
		u = -u
	vv = np.array([-u[1], u[0]])
	al = (a - c) @ u
	ac = (a - c) @ vv
	return c, u, vv, al.min(), al.max(), float(np.abs(ac).max())


def _raster(px_old, w, h, c, u, vv, amin, amax, bmax, ext):
	"""返回 {(x,y): rgba} 新枪管像素（含轮廓）；只覆盖透明或旧枪管像素"""
	half = HALF                 # 固定半厚，各姿势一致（bmax 只用来看旧枪管多粗）
	a_end = amax + ext
	inside = {}
	for y in range(h):
		for x in range(w):
			p = np.array([x, y], dtype=float) - c
			al = float(p @ u)
			ac = float(p @ vv)
			if al < amin + 0.5 or al > a_end:
				continue
			hw = half
			band = ext >= EXT and amin + 4.0 <= al <= amin + 6.0
			flare = ext >= EXT and al >= a_end - FLARE_LEN   # 举起的斜姿势不做喇叭口（斜向光栅化锯齿明显）
			if flare:
				hw += FLARE * (al - (a_end - FLARE_LEN)) / FLARE_LEN
			elif band:
				hw += 1.0
			if abs(ac) > hw:
				continue
			t = (ac + hw) / (2.0 * hw)   # 0 = 上（亮）… 1 = 下（暗）
			sh = SHADES_BAND if (band or flare) else SHADES
			k = 0 if t < 0.22 else (1 if t < 0.5 else (2 if t < 0.78 else 3))
			col = sh[k]
			if flare and al >= a_end - 1.5:
				col = (72, 72, 72)   # 口沿一线压暗，读成炮口
			inside[(x, y)] = col + (255,)
	out = dict(inside)
	for (x, y) in list(inside):
		for dx in (-1, 0, 1):
			for dy in (-1, 0, 1):
				q = (x + dx, y + dy)
				if q not in inside and 0 <= q[0] < w and 0 <= q[1] < h:
					out[q] = OUTLINE
	return out


def fix_cannon(variant, suffix, fi, im2, im1, nf):
	box = BOXES[(variant, suffix, fi)]
	x0, y0, x1, y1 = box
	ox = fi * FW
	fr = im2.crop((ox, 0, ox + FW, FH))
	px = fr.load()
	old = [(x, y) for y in range(y0, y1 + 1) for x in range(x0, x1 + 1) if px[x, y][3] > 0]
	assert len(old) >= 20, (variant, suffix, fi, len(old))
	c, u, vv, amin, amax, bmax = _pca(old)
	ext = EXT_UP if (suffix == "_melee" and fi in (0, 1)) else EXT
	new = _raster(px, FW, FH, c, u, vv, amin, amax, bmax, ext)
	oldset = set(old)
	n = 0
	for (x, y), col in new.items():
		if px[x, y][3] == 0 or (x, y) in oldset:
			px[x, y] = col
			n += 1
	im2.paste(fr, (ox, 0))
	# 1x：把 @2x 改动区（新像素范围）2×2 取多数色缩回去，只写透明 / 旧枪管像素
	fw1, fh1 = FW // 2, FH // 2
	fr1 = im1.crop((fi * fw1, 0, (fi + 1) * fw1, fh1))
	p1 = fr1.load()
	old1 = set((x // 2, y // 2) for (x, y) in old)
	touched = set((x // 2, y // 2) for (x, y) in new)
	for (X, Y) in touched:
		if not (p1[X, Y][3] == 0 or (X, Y) in old1):
			continue
		quad = [px[2 * X + dx, 2 * Y + dy] for dx in (0, 1) for dy in (0, 1)]
		op = [q for q in quad if q[3] > 0]
		if len(op) < 2:
			if p1[X, Y][3] > 0 and (X, Y) in old1 and not op:
				p1[X, Y] = (0, 0, 0, 0)
			continue
		p1[X, Y] = Counter(op).most_common(1)[0][0]
	im1.paste(fr1, (fi * fw1, 0))
	return n, (round(math.degrees(math.atan2(u[1], u[0]))), round(amax - amin, 1), round(bmax, 1))


def cmd_cannon():
	done = {}
	for variant in ["", "_dark"]:
		for suffix in ["_attack", "_reload", "_melee"]:
			base = "e_saint%s%s" % (variant, suffix)
			p2, p1 = os.path.join(INC, base + "@2x.png"), os.path.join(INC, base + ".png")
			im2, nf = _frames(p2)
			im1, _ = _frames(p1)
			for fi in range(nf):
				if (variant, suffix, fi) in BOXES:
					n, info = fix_cannon(variant, suffix, fi, im2, im1, nf)
					done[base + " f%d" % fi] = (n, info)
			im2.save(p2)
			im1.save(p1)
	for k, (n, info) in done.items():
		print("%-28s 写 %3d px  轴向 %d°  旧长 %.1f  旧半厚 %.1f" % (k, n, info[0], info[1], info[2]))


def cmd_nova():
	for name in ["proj_nova", "proj_nova@2x"]:
		p = os.path.join(INC, name + ".png")
		im = Image.open(p).convert("RGBA")
		s = im.height
		nf = im.width // s
		px = im.load()
		R = s * 0.3
		for fi in range(nf):
			cx = fi * s + (s - 1) / 2.0
			cy = (s - 1) / 2.0
			for y in range(s):
				for x in range(fi * s, (fi + 1) * s):
					c = px[x, y]
					if c[3] == 0 or (c[0] + c[1] + c[2]) < 240:
						continue   # 透明与深色轮廓 / 暗芒不动，只提亮发光的核心
					d = math.hypot(x - cx, y - cy)
					w = max(0.0, 1.0 - d / R) ** 1.8 * 0.9
					if w <= 0.0:
						continue
					col = tuple(min(255, int(round((c[i] + (tgt - c[i]) * w) / 24.0) * 24)) for i, tgt in enumerate((255, 240, 255)))
					px[x, y] = col + (c[3],)
		im.save(p)
		print(name, "%d 帧 %dx%d 核心提亮 R=%.1f" % (nf, s, s, R))


def cmd_sheet(tag):
	"""前后对照表：每个姿势 @2x 放大 4 倍并排；tag = before / after（after 时把 before 拼在上面）"""
	os.makedirs(OUT, exist_ok=True)
	S = 4
	items = [(v, suf, fi) for v in ["", "_dark"] for (vv, suf, fi) in sorted(BOXES) if vv == v]
	items = sorted(set(items), key=lambda t: (t[0], t[1], t[2]))
	tiles = []
	for v, suf, fi in items:
		im, nf = _frames(os.path.join(INC, "e_saint%s%s@2x.png" % (v, suf)))
		fr = im.crop((fi * FW, 0, (fi + 1) * FW, FH)).resize((FW * S, FH * S), Image.NEAREST)
		bg = Image.new("RGBA", fr.size, (40, 44, 52, 255))
		bg.alpha_composite(fr)
		ImageDraw.Draw(bg).text((3, 3), "saint%s%s f%d" % (v, suf, fi), fill=(255, 255, 0, 255))
		tiles.append(bg)
	row = Image.new("RGBA", (sum(t.width + 4 for t in tiles), FH * S), (20, 20, 24, 255))
	x = 0
	for t in tiles:
		row.alpha_composite(t, (x, 0))
		x += t.width + 4
	nt = []
	for name in ["proj_nova@2x"]:
		im = Image.open(os.path.join(INC, name + ".png")).convert("RGBA")
		s = im.height
		for fi in range(im.width // s):
			fr = im.crop((fi * s, 0, (fi + 1) * s, s)).resize((s * 8, s * 8), Image.NEAREST)
			bg = Image.new("RGBA", fr.size, (40, 44, 52, 255))
			bg.alpha_composite(fr)
			nt.append(bg)
	nrow = Image.new("RGBA", (sum(t.width + 4 for t in nt), nt[0].height), (20, 20, 24, 255))
	x = 0
	for t in nt:
		nrow.alpha_composite(t, (x, 0))
		x += t.width + 4
	for fn, img in [("cannon_strips", row), ("nova_strips", nrow)]:
		p = os.path.join(OUT, fn + "_%s.png" % tag)
		img.save(p)
		if tag == "after" and os.path.exists(os.path.join(OUT, fn + "_before.png")):
			b = Image.open(os.path.join(OUT, fn + "_before.png")).convert("RGBA")
			both = Image.new("RGBA", (max(b.width, img.width), b.height + img.height + 6), (20, 20, 24, 255))
			both.alpha_composite(b, (0, 0))
			both.alpha_composite(img, (0, b.height + 6))
			both.save(os.path.join(OUT, fn + ".png"))
			p = os.path.join(OUT, fn + ".png")
		print(p)


if __name__ == "__main__":
	cmd = sys.argv[1] if len(sys.argv) > 1 else ""
	if cmd == "nova":
		cmd_nova()
	elif cmd == "cannon":
		cmd_cannon()
	elif cmd == "all":
		cmd_nova()
		cmd_cannon()
	elif cmd == "sheet":
		cmd_sheet(sys.argv[2] if len(sys.argv) > 2 else "after")
	else:
		sys.exit(__doc__)
