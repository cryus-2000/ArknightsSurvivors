// 敌人绘制内核（见 enemy_render.h）。每段注明对应的 GDScript（render/world.gd、render/look.gd、data.gd）。
#include "enemy_render.h"

#include <algorithm>
#include <cmath>

namespace ark {

static inline float vlen(float x, float y) {
	return std::sqrt(x * x + y * y);   // Vector2.length()：real_t（float）
}

static inline C4 cmul(const C4 &a, const C4 &b) {
	return C4{ a.r * b.r, a.g * b.g, a.b * b.b, a.a * b.a };   // Color * Color
}

static inline C4 clerp(const C4 &a, const C4 &b, float w) {
	return C4{ a.r + w * (b.r - a.r), a.g + w * (b.g - a.g), a.b + w * (b.b - a.b), a.a + w * (b.a - a.a) };   // Color.lerp（Math::lerp）
}

// Look.actor_mod_lut(pos)：f = (pos + (0, -16) - lpos).length() × _lt_inv；f ≥ LUT_N 取末格，否则相邻两格插值
C4 EnemyRender::act_mod(const V2 &pos) const {
	if (fr.am_mode != 3 || fr.lut.empty()) {
		return C4{ 1, 1, 1, 1 };
	}
	const float cx = (pos.x + 0.0f) - fr.lpos.x;
	const float cy = (pos.y + -16.0f) - fr.lpos.y;
	const double f = (double)vlen(cx, cy) * fr.lt_inv;
	const int32_t last = (int32_t)fr.lut.size() - 1;
	if (f >= (double)last) {
		return fr.lut[(size_t)last];
	}
	const int32_t i = (int32_t)f;
	return clerp(fr.lut[(size_t)i], fr.lut[(size_t)i + 1], (float)(f - (double)i));
}

// world.draw_enemy 的缓存路径前半：哪些走原生、用哪个变体、移动判定（e.dpos / e.mv_until 由 GDScript 按 mv_out 写回）
void EnemyRender::frame_cols(const EnemyCols &c) {
	cols = c;
	const int32_t n = c.n;
	elig.assign((size_t)n, 0);
	vsel.assign((size_t)n, 0);
	mv_out.assign((size_t)n, 0.0);
	for (int32_t i = 0; i < n; ++i) {
		const int32_t m = c.meta[i];
		mv_out[(size_t)i] = c.mv[i];
		if (m & (M_SPECIAL | M_SKIP | M_BOSS | M_CHEST)) {
			continue;
		}
		const int32_t ti = c.type[i];
		if (ti < 0 || ti >= (int32_t)types.size() || !types[(size_t)ti].known || types[(size_t)ti].full) {
			continue;
		}
		const TypeInfo &tp = types[(size_t)ti];
		// 移动判定：if e.tex_move: if e.pos.distance_squared_to(e.dpos) > 0.04: e.mv_until = g.t + 0.2；e.dpos = e.pos
		double mv = c.mv[i];
		if (m & M_TEXMOVE) {
			const float dx = c.pos[i].x - c.dpos[i].x;
			const float dy = c.pos[i].y - c.dpos[i].y;
			const float d2 = dx * dx + dy * dy;
			if ((double)d2 > 0.04) {
				mv = fr.t + 0.2;
			}
		}
		const bool moving = (m & M_TEXMOVE) && fr.t < mv && !(m & M_STUN) && !(m & M_COMA);
		// _dc_compute 的帧条选择：休眠优先，其次移动，其次假死
		int32_t vb = 0;
		if ((m & M_DORMANT) && tp.has_v[3]) {
			vb = 3;
		} else if (moving && tp.has_v[2]) {
			vb = 2;
		} else if ((m & M_COMA) && (m & M_FEIGN) && tp.has_v[1]) {
			vb = 1;
		}
		const Variant &vr = tp.v[vb];
		// 图集快速路径的前提：本体在图集里（c[17] != null）；精英冷色描边（c[15]）要画描边贴图 → 走 GDScript
		if (vr.strip < 0) {
			continue;
		}
		if (vr.has_white_tex && fr.elite_rim && (m & M_ELITE)) {
			continue;
		}
		if (vr.wound_bad && c.flash[i] > 0.0) {
			continue;
		}
		elig[(size_t)i] = 1;
		vsel[(size_t)i] = vb;
		mv_out[(size_t)i] = mv;
	}
}

// world._sorted_fast：敌人键 = pos.y + r × 0.8（double），再接 GDScript 给的其他物件键；稳定排序（同键按加入次序，同 _se_at 的分组）
void EnemyRender::sort(const double *other_keys, int32_t n_other) {
	const int32_t n = cols.n;
	std::vector<std::pair<double, int32_t>> ks;
	ks.reserve((size_t)(n + n_other));
	for (int32_t i = 0; i < n; ++i) {
		ks.emplace_back((double)cols.pos[i].y + cols.r[i] * 0.8, i);
	}
	for (int32_t k = 0; k < n_other; ++k) {
		ks.emplace_back(other_keys[k], -(k + 1));
	}
	std::stable_sort(ks.begin(), ks.end(), [](const std::pair<double, int32_t> &a, const std::pair<double, int32_t> &b) { return a.first < b.first; });
	order.clear();
	seg.clear();
	order.reserve(ks.size());
	int32_t run0 = -1;
	for (size_t s = 0; s < ks.size(); ++s) {
		const int32_t o = ks[s].second;
		order.push_back(o);
		const bool nat = o >= 0 && elig[(size_t)o];
		if (nat) {
			if (run0 < 0) {
				run0 = (int32_t)s;
			}
			continue;
		}
		if (run0 >= 0) {
			seg.push_back(0);
			seg.push_back(run0);
			seg.push_back((int32_t)s);
			run0 = -1;
		}
		seg.push_back(o >= 0 ? 1 : 2);
		seg.push_back(o >= 0 ? o : -o - 1);
		seg.push_back(0);
	}
	if (run0 >= 0) {
		seg.push_back(0);
		seg.push_back(run0);
		seg.push_back((int32_t)order.size());
	}
}

// world._draw_shadows（有影子贴图时的内联写法）：
//   sc2 = PX × r / 10 × (1 − min(kb.length() × 0.03, 14) / 40)；size = Vector2(sw, sh) × sc2
//   Rect2((ep + Vector2(0, r × 0.8) + doff − size × (0.5, 0.5)).round(), size)，色 (1, 1, 1, alpha)
void EnemyRender::emit_shadows(const V2 &doff, float sw, float sh, float alpha) {
	ops.clear();
	for (int32_t i = 0; i < cols.n; ++i) {
		const V2 ep = cols.pos[i];
		const double er = cols.r[i];
		const double hop = std::min((double)vlen(cols.kb[i].x, cols.kb[i].y) * 0.03, 14.0);
		const double sc2 = fr.px * er / 10.0 * (1.0 - hop / 40.0);
		const float fs = (float)sc2;
		const float szx = sw * fs, szy = sh * fs;
		const float y08 = (float)(er * 0.8);
		float x = ((ep.x + 0.0f) + doff.x) - szx * 0.5f;
		float y = ((ep.y + y08) + doff.y) - szy * 0.5f;
		Op op;
		op.kind = OP_TEX;
		op.tex = TEX_SHADOW;
		op.rect = R4{ std::round(x), std::round(y), szx, szy };
		op.src = R4{ 0, 0, sw, sh };
		op.col = C4{ 1, 1, 1, alpha };
		ops.push_back(op);
	}
}

// world._glow_pts 末段：d = (q − anc × fs) × sc / dens（翻转取负 x）；sz = max(2, sc) × (1.5 if big)；
//   g.glow_next.append([(pos + d − Vector2(sz, sz) × 0.5).round(), sz, cc])
void EnemyRender::glow_pts(const Variant &vr, bool wound, int32_t frames, int32_t frame, const V2 &pos, double sc, bool flip, const V2 &anc, bool big) {
	const int32_t gi = wound ? vr.wound_glow : vr.glow;
	if (gi < 0 || gi >= (int32_t)glows.size()) {
		return;
	}
	const GlowTab &gt = glows[(size_t)gi];
	int32_t f = 0;
	if (gt.per_frame) {
		const int32_t nf = (int32_t)gt.frame_off.size() - 1;
		f = std::max(0, std::min(frame, nf - 1));
	}
	(void)frames;
	const int32_t p0 = gt.frame_off[(size_t)f], p1 = gt.frame_off[(size_t)f + 1];
	const int32_t npt = std::min(p1 - p0, big ? 4 : 3);
	const C4 cc = big ? fr.glow_elite : fr.glow_enemy;
	const float fsc = (float)sc;
	const double szd = std::max(2.0, sc) * (big ? 1.5 : 1.0);
	const float hs = (float)szd * 0.5f;   // Vector2(sz, sz) × 0.5
	for (int32_t k = 0; k < npt; ++k) {
		const GlowPt &pt = gt.pts[(size_t)(p0 + k)];
		float dx = (pt.q.x - anc.x * pt.fs.x) * fsc;
		float dy = (pt.q.y - anc.y * pt.fs.y) * fsc;
		const float dd = (float)pt.dens;
		dx = dx / dd;
		dy = dy / dd;
		if (flip) {
			dx = -dx;
		}
		const float gx = std::round((pos.x + dx) - hs);
		const float gy = std::round((pos.y + dy) - hs);
		glow_add(V2{ gx, gy }, szd, cc);
	}
}

void EnemyRender::glow_add(const V2 &p, double sz, const C4 &c) {
	const int nx = 1 - gl_cur;
	gl_pos[nx].push_back(p);
	gl_sz[nx].push_back(sz);
	gl_col[nx].push_back(c);
}

// optical._process：g.glow_cur = g.glow_next；g.glow_next = []
void EnemyRender::glow_swap() {
	gl_cur = 1 - gl_cur;
	const int nx = 1 - gl_cur;
	gl_pos[nx].clear();
	gl_sz[nx].clear();
	gl_col[nx].clear();
}

// optical._draw_glow：for p in g.glow_cur: glow_node.draw_rect(Rect2(p[0], Vector2(p[1], p[1])), p[2])
void EnemyRender::glow_emit() {
	ops.clear();
	const std::vector<V2> &ps = gl_pos[gl_cur];
	for (size_t k = 0; k < ps.size(); ++k) {
		Op op;
		op.kind = OP_RECT;
		op.tex = 0;
		const float s = (float)gl_sz[gl_cur][k];
		op.rect = R4{ ps[k].x, ps[k].y, s, s };
		op.src = R4{ 0, 0, 0, 0 };
		op.col = gl_col[gl_cur][k];
		ops.push_back(op);
	}
}

// world.draw_enemy 缓存路径后半 + _dc_emit（图集快速路径）：
//   frame = int(g.t × fps + e.id × 0.37) % frames；flash > 0 且有受击姿态 → 换受击帧条、1 帧
//   draw_off = D.enemy_offset(e)；flip = e.fx < 0；bpos = e.pos + 落点偏移；p = bpos + draw_off
//   本体色 _rimc(c[11] × act_mod)；白闪色 Color(1, 1, 1, 0.9 if elite else flash_a) × act_mod
void EnemyRender::emit_run(int32_t a, int32_t b) {
	ops.clear();
	affix.clear();
	for (int32_t s = a; s < b; ++s) {
		const int32_t i = order[(size_t)s];
		const int32_t m = cols.meta[i];
		const TypeInfo &tp = types[(size_t)cols.type[i]];
		const Variant &vr = tp.v[vsel[(size_t)i]];
		const V2 pos = cols.pos[i];
		const double r = cols.r[i];
		const C4 am = act_mod(pos);
		// c[11]：tint → 进化体偏红 → 无敌蓝灰半透明 → 晕眩偏蓝
		C4 col = tp.tint;
		if (m & M_EVO) {
			col = cmul(col, C4{ 1.0f, 0.62f, 0.68f, 1.0f });
		}
		if (m & M_INVULN) {
			col = C4{ 0.7f, 0.85f, 1.0f, 0.75f };
		}
		if (m & M_STUN) {
			col = cmul(col, C4{ 0.65f, 0.75f, 1.0f, 1.0f });
		}
		int32_t frames = vr.frames;
		int32_t frame = (int32_t)((int64_t)(fr.t * vr.fps + (double)cols.id[i] * 0.37) % (int64_t)frames);
		int32_t strip = vr.strip;
		bool white = vr.white;
		bool wound = false;
		const double flash = cols.flash[i];
		if (flash > 0.0 && vr.wound >= 0) {
			strip = vr.wound;
			white = vr.wound_white;
			frames = 1;
			frame = 0;
			wound = true;
		}
		// D.enemy_offset：off = (0, −min(kb.length() × 0.03, 14))；后坐窗口内 off += rc_dir × (rc_px × rc_k × (1 − k))
		float offx = 0.0f;
		float offy = (float)(-std::min((double)vlen(cols.kb[i].x, cols.kb[i].y) * 0.03, 14.0));
		if (fr.rc_px > 0.0 && (m & M_RC)) {
			const double ra = cols.rc[i * 3];
			const double rt = cols.rc[i * 3 + 1];
			const double rk = cols.rc[i * 3 + 2];
			const double k = (fr.t - ra) / rt;
			if (k >= 0.0 && k < 1.0) {
				const float s2 = (float)(fr.rc_px * rk * (1.0 - k));
				offx = offx + cols.rcdir[i].x * s2;
				offy = offy + cols.rcdir[i].y * s2;
			}
		}
		const bool flip = cols.fx[i] < 0.0;
		V2 bpos = pos;
		if (tp.foot) {
			bpos.y = pos.y + (float)(r * 0.8 + 3.0 * fr.px);
		}
		const double sc = vr.sc;
		const V2 anc = vr.anc;
		const Strip &st = strips[(size_t)strip];
		const int32_t fw = st.w / frames;
		const R4 src{ (float)(st.ox + fw * frame), (float)st.oy, (float)fw, (float)st.h };
		const float fsc = (float)sc;
		const float szx = (float)fw * fsc, szy = (float)st.h * fsc;
		const V2 p{ bpos.x + offx, bpos.y + offy };
		C4 bc = cmul(col, am);
		if (fr.lamp_rim) {
			bc.a = -bc.a;
		}
		const bool draw_white = flash > 0.0 && white;
		const C4 wc = cmul(C4{ 1.0f, 1.0f, 1.0f, (float)((m & M_ELITE) ? 0.9 : fr.flash_a) }, am);
		if (flip) {
			Op x;
			x.kind = OP_XFORM;
			x.tex = 0;
			x.rect = R4{ std::round(p.x), std::round(p.y), 0, 0 };
			x.src = R4{ 0, 0, 0, 0 };
			x.col = C4{ 1, 1, 1, 1 };
			ops.push_back(x);
			const R4 rf{ -(szx * anc.x), -(szy * anc.y), szx, szy };
			Op o;
			o.kind = OP_TEX;
			o.tex = TEX_BODY;
			o.rect = rf;
			o.src = src;
			o.col = bc;
			ops.push_back(o);
			if (draw_white) {
				o.tex = TEX_WHITE;
				o.col = wc;
				ops.push_back(o);
			}
			Op rz;
			rz.kind = OP_RESET;
			rz.tex = 0;
			rz.rect = R4{ 0, 0, 0, 0 };
			rz.src = R4{ 0, 0, 0, 0 };
			rz.col = C4{ 1, 1, 1, 1 };
			ops.push_back(rz);
		} else {
			const R4 rn{ std::round(p.x - szx * anc.x), std::round(p.y - szy * anc.y), szx, szy };
			Op o;
			o.kind = OP_TEX;
			o.tex = TEX_BODY;
			o.rect = rn;
			o.src = src;
			o.col = bc;
			ops.push_back(o);
			if (draw_white) {
				o.tex = TEX_WHITE;
				o.col = wc;
				ops.push_back(o);
			}
		}
		if (fr.optical) {
			glow_pts(vr, wound, frames, frame, p, sc, flip, anc, (m & M_ELITE) != 0);
		}
		if (m & M_AFFIX) {
			affix.push_back((float)i);
			affix.push_back(bpos.x);
			affix.push_back(bpos.y);
		}
		const int32_t wk = (m >> M_WEAK_SHIFT) & 3;
		if (wk != 0) {
			// wp = e.pos + Vector2(e.r × 0.8 + 6, −e.r − 4)
			wk_pos.push_back(V2{ pos.x + (float)(r * 0.8 + 6.0), pos.y + (float)(-r - 4.0) });
			wk_kind.push_back(wk);
		}
	}
}

} // namespace ark
