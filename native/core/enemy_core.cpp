// 敌人运动核心：与 GDScript 版 run/enemies.gd _motion_core / world/map.gd push_out 逐位等价（见 enemy_core.h 头注）。
// 每个表达式旁注了对应的 GDScript；改 GDScript 版时两边一起改，native_eq 同 seed 对照兜底。
#include "enemy_core.h"

#include <algorithm>
#include <cmath>
#include <unordered_map>

namespace ark {

namespace {

inline Vec2 v_add(Vec2 a, Vec2 b) { return Vec2{ a.x + b.x, a.y + b.y }; }
inline Vec2 v_sub(Vec2 a, Vec2 b) { return Vec2{ a.x - b.x, a.y - b.y }; }
inline Vec2 v_mul(Vec2 a, float s) { return Vec2{ a.x * s, a.y * s }; }   // Vector2 * real_t
inline Vec2 v_div(Vec2 a, float s) { return Vec2{ a.x / s, a.y / s }; }   // Vector2 / real_t
inline float v_len(Vec2 a) { return std::sqrt(a.x * a.x + a.y * a.y); }   // Vector2.length()（float sqrt）
inline float v_len2(Vec2 a) { return a.x * a.x + a.y * a.y; }             // Vector2.length_squared()
inline Vec2 v_norm(Vec2 a) {                                              // Vector2.normalized()
	float l = a.x * a.x + a.y * a.y;
	if (l != 0.0f) {
		l = std::sqrt(l);
		a.x /= l;
		a.y /= l;
	}
	return a;
}
inline int64_t floori(double x) { return (int64_t)std::floor(x); }        // GDScript floori()
inline int64_t key2(int64_t x, int64_t y) { return (x << 32) ^ (y & 0xffffffffLL); }

struct PropMap {
	std::unordered_map<int64_t, const PushProp *> m;
	int32_t x0, x1, y0, y1;
};

// map.gd push_out(pos, r)
Vec2 push_out(const MotionIn &in, const PropMap &pm, Vec2 pos, double r, int32_t &err) {
	if (!in.po_on) {
		return pos;
	}
	const double cell = in.po_cell;
	const int64_t cx = floori((double)pos.x / cell);   // floori(pos.x / cell)
	const int64_t cy = floori((double)pos.y / cell);
	const double mx = in.po_rx + r + 1.0;               // _po_rx + r + 1.0
	const double my = in.po_ry + r * 0.6 + in.po_ry * 0.6 + 1.0;
	for (int dx = -1; dx <= 1; ++dx) {
		for (int dy = -1; dy <= 1; ++dy) {
			// 推挤会改 pos，所以每格用当前 pos 判
			if (dx == -1 && (double)pos.x - ((double)(cx - 1) * cell + 469.0) >= mx) {
				continue;
			}
			if (dx == 1 && ((double)(cx + 1) * cell + 90.0) - (double)pos.x >= mx) {
				continue;
			}
			if (dy == -1 && (double)pos.y - ((double)(cy - 1) * cell + 469.0) >= my) {
				continue;
			}
			if (dy == 1 && ((double)(cy + 1) * cell + 90.0) - (double)pos.y >= my) {
				continue;
			}
			const int64_t qx = cx + dx, qy = cy + dy;
			if (qx < pm.x0 || qx > pm.x1 || qy < pm.y0 || qy > pm.y1) {
				err = 1;   // 预查范围外：调用方整帧回退 GDScript
				return pos;
			}
			auto it = pm.m.find(key2(qx, qy));
			if (it == pm.m.end()) {
				continue;   // 这格没有景物
			}
			const PushProp &bp = *it->second;
			const Vec2 c = bp.c;                           // bp[1] + Vector2(0, -bp[4] * 0.6)（GDScript 侧算好）
			const double rx = bp.rx + r;                   // bp[3] + r
			const double ry = bp.ry + r * 0.6;             // bp[4] + r * 0.6
			const Vec2 d = v_sub(pos, c);                  // pos - c
			Vec2 q{ (float)((double)d.x / rx), (float)((double)d.y / ry) };   // Vector2(d.x / rx, d.y / ry)
			double ql = (double)v_len(q);                  // q.length()
			if (ql < 1.0) {
				if (ql < 0.001) {
					q = Vec2{ 1.0f, 0.0f };
					ql = 1.0;
				}
				const Vec2 qn = v_div(q, (float)ql);          // q / ql
				pos = v_add(c, Vec2{ (float)((double)qn.x * rx), (float)((double)qn.y * ry) });   // c + Vector2(qn.x * rx, qn.y * ry)
			}
		}
	}
	return pos;
}

} // namespace

void motion_step(MotionIn &in, MotionOut &out) {
	const int32_t n = in.n;
	out.err = 0;
	// 分离网格：与 build_grid 相同的格子归属与次序（按下标升序追加）
	std::unordered_map<int64_t, std::vector<int32_t>> grid;
	grid.reserve((size_t)n);
	for (int32_t i = 0; i < n; ++i) {
		if (in.gin[i]) {
			grid[key2(in.gx[i], in.gy[i])].push_back(i);
		}
	}
	PropMap pm;
	pm.x0 = in.prop_x0;
	pm.x1 = in.prop_x1;
	pm.y0 = in.prop_y0;
	pm.y1 = in.prop_y1;
	pm.m.reserve((size_t)in.n_props);
	for (int32_t k = 0; k < in.n_props; ++k) {
		pm.m[key2(in.props[k].cx, in.props[k].cy)] = &in.props[k];
	}
	const float dtf = (float)in.dt;
	const double cell = in.cell;
	for (int32_t i = 0; i < n; ++i) {
		if (!in.on[i]) {
			continue;
		}
		const int32_t fi = in.flags[i];
		if (fi & HF_DEAD) {   // A 段里被别的单位打死
			in.on[i] = 0;
			continue;
		}
		Vec2 p = in.pos[i];
		const double ri = in.r[i];
		bool absorbed = false;
		if (!(fi & HF_STATIC)) {
			const double qr = ri + 20.0;
			const Vec2 qp = p;
			const int64_t x0 = floori(((double)qp.x - qr) / cell);
			const int64_t x1 = floori(((double)qp.x + qr) / cell);
			const int64_t y0 = floori(((double)qp.y - qr) / cell);
			const int64_t y1 = floori(((double)qp.y + qr) / cell);
			bool stop = false;
			for (int64_t cx = x0; cx <= x1 && !stop; ++cx) {
				for (int64_t cy = y0; cy <= y1 && !stop; ++cy) {
					auto it = grid.find(key2(cx, cy));
					if (it == grid.end()) {
						continue;
					}
					for (int32_t j : it->second) {
						if (j < 0 || j >= n || j == i) {
							continue;
						}
						const int32_t fj = in.flags[j];
						if (fj & (HF_FRIENDLY | HF_DEAD)) {
							continue;
						}
						const Vec2 diff = v_sub(p, in.pos[j]);   // p - _hp[j]
						const double d = (double)v_len(diff);    // diff.length()
						const double min_d = ri + in.r[j];
						if (d < min_d && d > 0.01) {
							if ((fi & HF_EVO) && !(fj & (HF_EVO | HF_ELITE | HF_BOSS | HF_CHEST | HF_STATIC)) && d < ri) {
								out.dv_e.push_back(i);
								out.dv_o.push_back(j);
							}
							if ((fi & HF_FEED) && (fj & HF_IZUMIK1)) {
								out.ab_e.push_back(i);
								out.ab_o.push_back(j);
								absorbed = true;
								stop = true;
								break;
							}
							if (!(fi & HF_BOSS)) {
								// p += diff / d * (min_d - d) * 0.3
								Vec2 t = v_div(diff, (float)d);
								t = v_mul(t, (float)(min_d - d));
								t = v_mul(t, (float)0.3);
								p = v_add(p, t);
							}
						}
					}
				}
			}
			if (absorbed) {
				in.pos[i] = p;
				continue;
			}
		}
		p = v_add(p, v_mul(in.vel[i], dtf));   // p += _seg_v[i] * dt
		if ((fi & HF_BOSS) && in.zone_on) {
			const double limit = std::max(0.0, in.zone_r - in.zmargin[i]);   // maxf(0.0, zr - _hz[i])
			const Vec2 offset = v_sub(p, in.zone_c);
			if ((double)v_len2(offset) > limit * limit) {
				p = v_add(in.zone_c, v_mul(v_norm(offset), (float)limit));   // zc + offset.normalized() * limit
			}
		}
		if (!(fi & HF_BOSS) && !(fi & HF_STATIC) && ((int64_t)i + in.frame_n) % 2 == 0) {
			p = push_out(in, pm, p, ri * 0.8, out.err);
			if (out.err) {
				return;
			}
		}
		in.pos[i] = p;
	}
}

} // namespace ark
