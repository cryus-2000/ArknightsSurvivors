// EnemyRender 的 godot-cpp 薄绑定（docs/50 §30）：把 Packed 列交给纯 C++ 内核 core/enemy_render，内核算出的画布命令在这里逐条发给 RenderingServer。
// 列在本对象里留一份引用（GDScript 下一帧改自己的数组时写时复制，不影响这里的指针）。
#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/color.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_color_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/rid.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/vector2.hpp>

#include "../core/enemy_render.h"

namespace godot {

class EnemyRender : public RefCounted {
	GDCLASS(EnemyRender, RefCounted)

	ark::EnemyRender core;
	RID tex[3];
	// 本帧列（保留引用，内核持有其裸指针）
	PackedVector2Array c_pos, c_kb, c_dpos, c_rcdir;
	PackedFloat64Array c_r, c_fx, c_flash, c_mv, c_rc;
	PackedInt32Array c_id, c_type, c_meta;

	void flush_ops(const RID &item);

protected:
	static void _bind_methods();

public:
	String version() const;
	void clear();
	void set_textures(const RID &body, const RID &white, const RID &shadow);
	int add_strip(int ox, int oy, int w, int h);
	int add_glow(bool per_frame, const PackedInt32Array &offs, const PackedFloat64Array &pts);
	void set_type(int ti, bool full, bool foot, const Color &tint);
	void set_variant(int ti, int vb, const PackedFloat64Array &p);
	void frame_begin(const PackedFloat64Array &p, const PackedColorArray &lut, const PackedColorArray &glow_cols);
	// 返回 [elig: PackedByteArray, mv_out: PackedFloat64Array]
	Array set_cols(const PackedVector2Array &pos, const PackedFloat64Array &r, const PackedVector2Array &kb, const PackedFloat64Array &fx,
			const PackedFloat64Array &flash, const PackedInt32Array &id, const PackedInt32Array &type, const PackedInt32Array &meta,
			const PackedVector2Array &dpos, const PackedFloat64Array &mv, const PackedFloat64Array &rc, const PackedVector2Array &rcdir);
	void emit_shadows(const RID &item, const Vector2 &doff, double sw, double sh, double alpha);
	PackedInt32Array sort(const PackedFloat64Array &other_keys);
	PackedFloat32Array emit_run(const RID &item, int a, int b);
	void glow_add(const Vector2 &p, double sz, const Color &c);
	void glow_swap();
	void glow_emit(const RID &item);
	void weak_add(const Vector2 &p, int kind);
	Array weak_take();
};

} // namespace godot
