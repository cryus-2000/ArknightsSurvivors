#include "enemy_render_bind.h"

#include <godot_cpp/classes/rendering_server.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/rect2.hpp>
#include <godot_cpp/variant/transform2d.hpp>

using namespace godot;

static_assert(sizeof(Vector2) == sizeof(ark::V2), "Vector2 与 ark::V2 布局一致（real_t = float）");
static_assert(sizeof(Color) == sizeof(ark::C4), "Color 与 ark::C4 布局一致");

void EnemyRender::_bind_methods() {
	ClassDB::bind_method(D_METHOD("version"), &EnemyRender::version);
	ClassDB::bind_method(D_METHOD("clear"), &EnemyRender::clear);
	ClassDB::bind_method(D_METHOD("set_textures", "body", "white", "shadow"), &EnemyRender::set_textures);
	ClassDB::bind_method(D_METHOD("add_strip", "ox", "oy", "w", "h"), &EnemyRender::add_strip);
	ClassDB::bind_method(D_METHOD("add_glow", "per_frame", "offs", "pts"), &EnemyRender::add_glow);
	ClassDB::bind_method(D_METHOD("set_type", "ti", "full", "foot", "tint"), &EnemyRender::set_type);
	ClassDB::bind_method(D_METHOD("set_variant", "ti", "vb", "p"), &EnemyRender::set_variant);
	ClassDB::bind_method(D_METHOD("frame_begin", "p", "lut", "glow_cols"), &EnemyRender::frame_begin);
	ClassDB::bind_method(D_METHOD("set_cols", "pos", "r", "kb", "fx", "flash", "id", "type", "meta", "dpos", "mv", "rc", "rcdir"), &EnemyRender::set_cols);
	ClassDB::bind_method(D_METHOD("emit_shadows", "item", "doff", "sw", "sh", "alpha"), &EnemyRender::emit_shadows);
	ClassDB::bind_method(D_METHOD("sort", "other_keys"), &EnemyRender::sort);
	ClassDB::bind_method(D_METHOD("emit_run", "item", "a", "b"), &EnemyRender::emit_run);
	ClassDB::bind_method(D_METHOD("glow_add", "p", "sz", "c"), &EnemyRender::glow_add);
	ClassDB::bind_method(D_METHOD("glow_swap"), &EnemyRender::glow_swap);
	ClassDB::bind_method(D_METHOD("glow_emit", "item"), &EnemyRender::glow_emit);
	ClassDB::bind_method(D_METHOD("weak_add", "p", "kind"), &EnemyRender::weak_add);
	ClassDB::bind_method(D_METHOD("weak_take"), &EnemyRender::weak_take);
}

String EnemyRender::version() const {
	return String("ark_native enemy_render 1");
}

void EnemyRender::clear() {
	core.strips.clear();
	core.glows.clear();
	core.types.clear();
}

void EnemyRender::set_textures(const RID &body, const RID &white, const RID &shadow) {
	tex[0] = body;
	tex[1] = white;
	tex[2] = shadow;
}

int EnemyRender::add_strip(int ox, int oy, int w, int h) {
	core.strips.push_back(ark::Strip{ ox, oy, w, h });
	return (int)core.strips.size() - 1;
}

// pts：每点 5 个 double（qx, qy, fsx, fsy, dens）；offs：每帧起点（per_frame 时 frames + 1 个，否则 [0, n]）
int EnemyRender::add_glow(bool per_frame, const PackedInt32Array &offs, const PackedFloat64Array &pts) {
	ark::GlowTab gt;
	gt.per_frame = per_frame;
	for (int64_t k = 0; k < offs.size(); ++k) {
		gt.frame_off.push_back(offs[k]);
	}
	const int64_t np = pts.size() / 5;
	for (int64_t k = 0; k < np; ++k) {
		ark::GlowPt p;
		p.q = ark::V2{ (float)pts[k * 5], (float)pts[k * 5 + 1] };
		p.fs = ark::V2{ (float)pts[k * 5 + 2], (float)pts[k * 5 + 3] };
		p.dens = pts[k * 5 + 4];
		gt.pts.push_back(p);
	}
	if (gt.frame_off.size() < 2) {
		gt.frame_off = { 0, (int32_t)np };
	}
	core.glows.push_back(gt);
	return (int)core.glows.size() - 1;
}

void EnemyRender::set_type(int ti, bool full, bool foot, const Color &tint) {
	if (ti < 0) {
		return;
	}
	if ((size_t)ti >= core.types.size()) {
		core.types.resize((size_t)ti + 1);
	}
	ark::TypeInfo &tp = core.types[(size_t)ti];
	tp.known = true;
	tp.full = full;
	tp.foot = foot;
	tp.tint = ark::C4{ tint.r, tint.g, tint.b, tint.a };
}

// p：[strip, white, frames, fps, wound, wound_white, wound_bad, anc.x, anc.y, sc, has_white_tex, glow, wound_glow]
void EnemyRender::set_variant(int ti, int vb, const PackedFloat64Array &p) {
	if (ti < 0 || (size_t)ti >= core.types.size() || vb < 0 || vb > 3 || p.size() < 13) {
		return;
	}
	ark::Variant &v = core.types[(size_t)ti].v[vb];
	v.strip = (int32_t)p[0];
	v.white = p[1] != 0.0;
	v.frames = (int32_t)p[2] > 0 ? (int32_t)p[2] : 1;
	v.fps = p[3];
	v.wound = (int32_t)p[4];
	v.wound_white = p[5] != 0.0;
	v.wound_bad = p[6] != 0.0;
	v.anc = ark::V2{ (float)p[7], (float)p[8] };
	v.sc = p[9];
	v.has_white_tex = p[10] != 0.0;
	v.glow = (int32_t)p[11];
	v.wound_glow = (int32_t)p[12];
	core.types[(size_t)ti].has_v[vb] = true;
}

// p：[t, flash_a, am_mode, lt_inv, lpos.x, lpos.y, lamp_rim, optical, elite_rim, rc_px, rc_t, px]；glow_cols：[敌人, 精英]
void EnemyRender::frame_begin(const PackedFloat64Array &p, const PackedColorArray &lut, const PackedColorArray &glow_cols) {
	ark::FrameIn &f = core.fr;
	if (p.size() < 12) {
		return;
	}
	f.t = p[0];
	f.flash_a = p[1];
	f.am_mode = (int32_t)p[2];
	f.lt_inv = p[3];
	f.lpos = ark::V2{ (float)p[4], (float)p[5] };
	f.lamp_rim = p[6] != 0.0;
	f.optical = p[7] != 0.0;
	f.elite_rim = p[8] != 0.0;
	f.rc_px = p[9];
	f.rc_t = p[10];
	f.px = p[11];
	f.lut.resize((size_t)lut.size());
	for (int64_t k = 0; k < lut.size(); ++k) {
		const Color c = lut[k];
		f.lut[(size_t)k] = ark::C4{ c.r, c.g, c.b, c.a };
	}
	if (glow_cols.size() >= 2) {
		f.glow_enemy = ark::C4{ glow_cols[0].r, glow_cols[0].g, glow_cols[0].b, glow_cols[0].a };
		f.glow_elite = ark::C4{ glow_cols[1].r, glow_cols[1].g, glow_cols[1].b, glow_cols[1].a };
	}
	core.wk_pos.clear();
	core.wk_kind.clear();
}

Array EnemyRender::set_cols(const PackedVector2Array &pos, const PackedFloat64Array &r, const PackedVector2Array &kb, const PackedFloat64Array &fx,
		const PackedFloat64Array &flash, const PackedInt32Array &id, const PackedInt32Array &type, const PackedInt32Array &meta,
		const PackedVector2Array &dpos, const PackedFloat64Array &mv, const PackedFloat64Array &rc, const PackedVector2Array &rcdir) {
	Array res;
	const int64_t n = pos.size();
	if (r.size() != n || kb.size() != n || fx.size() != n || flash.size() != n || id.size() != n || type.size() != n || meta.size() != n ||
			dpos.size() != n || mv.size() != n || rc.size() != n * 3 || rcdir.size() != n) {
		ark::EnemyCols empty;
		core.frame_cols(empty);
		res.append(PackedByteArray());
		res.append(PackedFloat64Array());
		return res;
	}
	c_pos = pos;
	c_r = r;
	c_kb = kb;
	c_fx = fx;
	c_flash = flash;
	c_id = id;
	c_type = type;
	c_meta = meta;
	c_dpos = dpos;
	c_mv = mv;
	c_rc = rc;
	c_rcdir = rcdir;
	ark::EnemyCols c;
	c.n = (int32_t)n;
	c.pos = reinterpret_cast<const ark::V2 *>(c_pos.ptr());
	c.r = c_r.ptr();
	c.kb = reinterpret_cast<const ark::V2 *>(c_kb.ptr());
	c.fx = c_fx.ptr();
	c.flash = c_flash.ptr();
	c.id = c_id.ptr();
	c.type = c_type.ptr();
	c.meta = c_meta.ptr();
	c.dpos = reinterpret_cast<const ark::V2 *>(c_dpos.ptr());
	c.mv = c_mv.ptr();
	c.rc = c_rc.ptr();
	c.rcdir = reinterpret_cast<const ark::V2 *>(c_rcdir.ptr());
	core.frame_cols(c);
	PackedByteArray el;
	el.resize(n);
	PackedFloat64Array mo;
	mo.resize(n);
	uint8_t *ep = el.ptrw();
	double *mp = mo.ptrw();
	for (int64_t i = 0; i < n; ++i) {
		ep[i] = core.elig[(size_t)i];
		mp[i] = core.mv_out[(size_t)i];
	}
	res.append(el);
	res.append(mo);
	return res;
}

void EnemyRender::flush_ops(const RID &item) {
	RenderingServer *rs = RenderingServer::get_singleton();
	for (const ark::Op &op : core.ops) {
		switch (op.kind) {
			case ark::OP_TEX:
				rs->canvas_item_add_texture_rect_region(item, Rect2(op.rect.x, op.rect.y, op.rect.w, op.rect.h), tex[op.tex],
						Rect2(op.src.x, op.src.y, op.src.w, op.src.h), Color(op.col.r, op.col.g, op.col.b, op.col.a), false, true);
				break;
			case ark::OP_XFORM:
				// draw_set_transform(p.round(), 0, Vector2(-1, 1))
				rs->canvas_item_add_set_transform(item, Transform2D(Vector2(-1, 0), Vector2(0, 1), Vector2(op.rect.x, op.rect.y)));
				break;
			case ark::OP_RESET:
				rs->canvas_item_add_set_transform(item, Transform2D(Vector2(1, 0), Vector2(0, 1), Vector2(0, 0)));
				break;
			case ark::OP_RECT:
				rs->canvas_item_add_rect(item, Rect2(op.rect.x, op.rect.y, op.rect.w, op.rect.h), Color(op.col.r, op.col.g, op.col.b, op.col.a), false);
				break;
		}
	}
	core.ops.clear();
}

void EnemyRender::emit_shadows(const RID &item, const Vector2 &doff, double sw, double sh, double alpha) {
	core.emit_shadows(ark::V2{ doff.x, doff.y }, (float)sw, (float)sh, (float)alpha);
	flush_ops(item);
}

PackedInt32Array EnemyRender::sort(const PackedFloat64Array &other_keys) {
	core.sort(other_keys.ptr(), (int32_t)other_keys.size());
	PackedInt32Array out;
	out.resize((int64_t)core.seg.size());
	int32_t *op = out.ptrw();
	for (size_t k = 0; k < core.seg.size(); ++k) {
		op[k] = core.seg[k];
	}
	return out;
}

PackedFloat32Array EnemyRender::emit_run(const RID &item, int a, int b) {
	core.emit_run(a, b);
	flush_ops(item);
	PackedFloat32Array out;
	if (!core.affix.empty()) {
		out.resize((int64_t)core.affix.size());
		float *op = out.ptrw();
		for (size_t k = 0; k < core.affix.size(); ++k) {
			op[k] = core.affix[k];
		}
	}
	return out;
}

void EnemyRender::glow_add(const Vector2 &p, double sz, const Color &c) {
	core.glow_add(ark::V2{ p.x, p.y }, sz, ark::C4{ c.r, c.g, c.b, c.a });
}

void EnemyRender::glow_swap() {
	core.glow_swap();
}

void EnemyRender::glow_emit(const RID &item) {
	core.glow_emit();
	flush_ops(item);
}

void EnemyRender::weak_add(const Vector2 &p, int kind) {
	core.wk_pos.push_back(ark::V2{ p.x, p.y });
	core.wk_kind.push_back(kind);
}

// 返回 [位置: PackedVector2Array, 种类: PackedInt32Array]，并清空
Array EnemyRender::weak_take() {
	Array res;
	PackedVector2Array ps;
	PackedInt32Array ks;
	ps.resize((int64_t)core.wk_pos.size());
	ks.resize((int64_t)core.wk_kind.size());
	for (size_t k = 0; k < core.wk_pos.size(); ++k) {
		ps.set((int64_t)k, Vector2(core.wk_pos[k].x, core.wk_pos[k].y));
		ks.set((int64_t)k, core.wk_kind[k]);
	}
	core.wk_pos.clear();
	core.wk_kind.clear();
	res.append(ps);
	res.append(ks);
	return res;
}
