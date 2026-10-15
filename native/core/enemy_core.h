// 敌人运动核心（docs/101 §4.2 ①、B8）：纯 C++，不包含任何 Godot 头文件，只收指针 + 长度。
// 与 GDScript 版 run/enemies.gd 的 _motion_core 逐位等价：Vector2 分量用 float（与引擎 real_t 一致），标量用 double（与 GDScript float 一致），
// 运算次序与类型转换照搬；编译时不开 -ffast-math、加 -ffp-contract=off（不合成 FMA）。
#pragma once
#include <cstdint>
#include <vector>

namespace ark {

struct Vec2 {
	float x, y;
};

// 与 run/enemies.gd 的 HF_* 一致
enum : int32_t {
	HF_DEAD = 1,
	HF_FRIENDLY = 2,
	HF_STATIC = 4,
	HF_BOSS = 8,
	HF_EVO = 16,
	HF_ELITE = 32,
	HF_CHEST = 64,
	HF_FEED = 128,
	HF_IZUMIK1 = 256,
};

// 景物底座（map._big_prop，GDScript 每帧按敌人所在范围预先查好）：中心 c（已含 -ry·0.6 的上移）、半轴 rx / ry
struct PushProp {
	int32_t cx, cy;
	Vec2 c;
	double rx, ry;
};

struct MotionIn {
	int32_t n = 0;
	Vec2 *pos = nullptr;              // 读写，n
	const double *r = nullptr;        // n
	const double *zmargin = nullptr;  // n（Boss 场地留边）
	const int32_t *flags = nullptr;   // n
	uint8_t *on = nullptr;            // 读写，n（A 段之后参与 B / C 的）
	const Vec2 *vel = nullptr;        // n（A 段算出的本帧速度）
	const int32_t *gx = nullptr;      // n：本帧网格（A 段之前建）里所在格子；gin[i] = 0 表示不在格里
	const int32_t *gy = nullptr;
	const uint8_t *gin = nullptr;
	double dt = 0.0;
	double cell = 48.0;               // 分离网格 CELL
	bool zone_on = false;
	double zone_r = 0.0;
	Vec2 zone_c{ 0.0f, 0.0f };
	int64_t frame_n = 0;
	// 景物推出（map.push_out）
	bool po_on = false;
	double po_cell = 560.0, po_rx = 0.0, po_ry = 0.0;
	const PushProp *props = nullptr;
	int32_t n_props = 0;
	int32_t prop_x0 = 0, prop_x1 = -1, prop_y0 = 0, prop_y1 = -1;   // 预查覆盖的格子范围（越界即报错，调用方回退 GDScript）
};

struct MotionOut {
	std::vector<int32_t> dv_e, dv_o;   // 吞噬候选（捕食者 i、猎物 j），按分离次序
	std::vector<int32_t> ab_e, ab_o;   // 伊祖米克吸收（子代 i、Boss j）
	int32_t err = 0;                   // 1 = 景物查询越出预查范围（结果作废）
};

void motion_step(MotionIn &in, MotionOut &out);

} // namespace ark
