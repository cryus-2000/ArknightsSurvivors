#include "enemy_core_bind.h"

#include <godot_cpp/core/class_db.hpp>

#include <vector>

#include "../core/enemy_core.h"

using namespace godot;

static_assert(sizeof(Vector2) == 2 * sizeof(float), "Vector2 必须是两个 float（引擎 real_t = float）");
static_assert(sizeof(ark::Vec2) == sizeof(Vector2), "ark::Vec2 与 Vector2 布局一致");

void EnemyCore::_bind_methods() {
	ClassDB::bind_method(D_METHOD("version"), &EnemyCore::version);
	ClassDB::bind_method(D_METHOD("step", "pos", "r", "zmargin", "flags", "on", "vel", "grid", "params", "prop_cells", "prop_c", "prop_r"), &EnemyCore::step);
}

String EnemyCore::version() const {
	return String("ark_native enemy_core 1");
}

// params：[dt, cell, zone_on, zone_r, zone_cx, zone_cy, frame_n, po_on, po_cell, po_rx, po_ry, prop_x0, prop_x1, prop_y0, prop_y1]
// grid：每个下标 3 个 int（gx, gy, gin）
Array EnemyCore::step(PackedVector2Array pos, const PackedFloat64Array &r, const PackedFloat64Array &zmargin, const PackedInt32Array &flags,
		PackedByteArray on, const PackedVector2Array &vel, const PackedInt32Array &grid, const PackedFloat64Array &params,
		const PackedInt32Array &prop_cells, const PackedVector2Array &prop_c, const PackedFloat64Array &prop_r) {
	Array res;
	const int64_t n = pos.size();
	if (r.size() != n || zmargin.size() != n || flags.size() != n || on.size() != n || vel.size() != n || grid.size() != n * 3 || params.size() < 15) {
		res.append(pos);
		res.append(on);
		res.append(PackedInt32Array());
		res.append(PackedInt32Array());
		res.append(2);   // 参数长度不对
		return res;
	}
	const int64_t np = prop_c.size();
	std::vector<ark::PushProp> props((size_t)np);
	for (int64_t k = 0; k < np; ++k) {
		props[(size_t)k].cx = prop_cells[k * 2];
		props[(size_t)k].cy = prop_cells[k * 2 + 1];
		props[(size_t)k].c = ark::Vec2{ prop_c[k].x, prop_c[k].y };
		props[(size_t)k].rx = prop_r[k * 2];
		props[(size_t)k].ry = prop_r[k * 2 + 1];
	}
	std::vector<int32_t> gx((size_t)n), gy((size_t)n);
	std::vector<uint8_t> gin((size_t)n);
	const int32_t *gp = grid.ptr();
	for (int64_t i = 0; i < n; ++i) {
		gx[(size_t)i] = gp[i * 3];
		gy[(size_t)i] = gp[i * 3 + 1];
		gin[(size_t)i] = gp[i * 3 + 2] != 0 ? 1 : 0;
	}
	const double *pr = params.ptr();
	ark::MotionIn in;
	in.n = (int32_t)n;
	in.pos = reinterpret_cast<ark::Vec2 *>(pos.ptrw());
	in.r = r.ptr();
	in.zmargin = zmargin.ptr();
	in.flags = flags.ptr();
	in.on = on.ptrw();
	in.vel = reinterpret_cast<const ark::Vec2 *>(vel.ptr());
	in.gx = gx.data();
	in.gy = gy.data();
	in.gin = gin.data();
	in.dt = pr[0];
	in.cell = pr[1];
	in.zone_on = pr[2] != 0.0;
	in.zone_r = pr[3];
	in.zone_c = ark::Vec2{ (float)pr[4], (float)pr[5] };
	in.frame_n = (int64_t)pr[6];
	in.po_on = pr[7] != 0.0;
	in.po_cell = pr[8];
	in.po_rx = pr[9];
	in.po_ry = pr[10];
	in.prop_x0 = (int32_t)pr[11];
	in.prop_x1 = (int32_t)pr[12];
	in.prop_y0 = (int32_t)pr[13];
	in.prop_y1 = (int32_t)pr[14];
	in.props = props.data();
	in.n_props = (int32_t)np;
	ark::MotionOut out;
	ark::motion_step(in, out);
	PackedInt32Array dv, ab;
	dv.resize((int64_t)out.dv_e.size() * 2);
	for (size_t k = 0; k < out.dv_e.size(); ++k) {
		dv[(int64_t)k * 2] = out.dv_e[k];
		dv[(int64_t)k * 2 + 1] = out.dv_o[k];
	}
	ab.resize((int64_t)out.ab_e.size() * 2);
	for (size_t k = 0; k < out.ab_e.size(); ++k) {
		ab[(int64_t)k * 2] = out.ab_e[k];
		ab[(int64_t)k * 2 + 1] = out.ab_o[k];
	}
	res.append(pos);
	res.append(on);
	res.append(dv);
	res.append(ab);
	res.append(out.err);
	return res;
}
