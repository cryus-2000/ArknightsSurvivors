// EnemyCore 的 godot-cpp 薄绑定（docs/101 §4.7）：把 Packed 数组的裸指针交给纯 C++ 内核 core/enemy_core，一帧调一次。
#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/string.hpp>

namespace godot {

class EnemyCore : public RefCounted {
	GDCLASS(EnemyCore, RefCounted)

protected:
	static void _bind_methods();

public:
	String version() const;
	// 返回 [pos: PackedVector2Array, on: PackedByteArray, dv: PackedInt32Array（i, j 交替）, ab: PackedInt32Array（i, j 交替）, err: int]
	Array step(PackedVector2Array pos, const PackedFloat64Array &r, const PackedFloat64Array &zmargin, const PackedInt32Array &flags,
			PackedByteArray on, const PackedVector2Array &vel, const PackedInt32Array &grid, const PackedFloat64Array &params,
			const PackedInt32Array &prop_cells, const PackedVector2Array &prop_c, const PackedFloat64Array &prop_r);
};

} // namespace godot
