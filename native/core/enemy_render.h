// 敌人绘制内核（docs/50 §28，claude/enemy-native）：排序实体里普通怪的「缓存路径」（world.gd draw_enemy → _dc_ok / _dc_compute / _dc_emit）、
// 影子（_draw_shadows）、光学发光点（_glow_pts）、弱点菱形登记的逐只计算，原生化后一帧按段调用。纯 C++，不含 Godot 头文件：
// 只算出「绘制命令表」（贴图矩形 / 翻转变换 / 复位 / 纯色矩形），由 gdext 绑定逐条交给 RenderingServer——与 GDScript 的
// draw_texture_rect_region / draw_set_transform / draw_rect 是同一种画布命令，所以画面逐像素相同。
// 精度：Vector2 / Color 分量 float、GDScript 标量 double，表达式与类型转换照搬（不开 fast-math、-ffp-contract=off）。
#pragma once
#include <cstdint>
#include <vector>

namespace ark {

struct V2 {
	float x, y;
};
struct C4 {
	float r, g, b, a;
};
struct R4 {
	float x, y, w, h;
};

// 画布命令（绑定层照顺序发给 RenderingServer）
enum : uint8_t {
	OP_TEX = 0,      // canvas_item_add_texture_rect_region(rect, tex[t], src, col)
	OP_XFORM = 1,    // canvas_item_add_set_transform(Transform2D(0, (-1, 1), 0, pos = rect.xy))
	OP_RESET = 2,    // canvas_item_add_set_transform(Transform2D(0, (1, 1), 0, (0, 0)))
	OP_RECT = 3,     // canvas_item_add_rect(rect, col)
};
enum : uint8_t {
	TEX_BODY = 0,    // 敌人图集本体（EnemyAtlas.tex_body）
	TEX_WHITE = 1,   // 敌人图集白剪影（tex_white）
	TEX_SHADOW = 2,  // 影子贴图
};
struct Op {
	uint8_t kind, tex;
	R4 rect, src;
	C4 col;
};

// 图集里的一条帧条（EnemyAtlas.reg[name]：原点 + 整条宽高；本体与白剪影同一原点）
struct Strip {
	int32_t ox, oy, w, h;
};

// 发光点表（_emit_pts / _glow_cache 的结果）：每帧若干点 [q, 帧尺寸 fs, 密度]；frame_off[f]..frame_off[f+1]
struct GlowPt {
	V2 q, fs;
	double dens;
};
struct GlowTab {
	bool per_frame = false;               // true：_emit_pts（按帧）；false：_glow_cache（所有帧同一份）
	std::vector<int32_t> frame_off;       // per_frame 时 frames + 1 个；否则 2 个
	std::vector<GlowPt> pts;
};

// 一种敌人在某个画法变体下的缓存内容（_dc_compute 的结果里只依赖种类 / 帧条的部分）
struct Variant {
	int32_t strip = -1;        // 图集本体帧条；-1 = 不在图集 → 走 GDScript
	bool white = false;        // 图集里有白剪影（c[18]）
	int32_t frames = 1;
	double fps = 5.0;
	int32_t wound = -1;        // 受击姿态帧条（c[20]）；-1 = 没有
	bool wound_white = false;  // c[21]
	bool wound_bad = false;    // 有受击姿态但不在图集（c[19] != "" 且 c[20] == null）：闪白时 _dc_emit 走非图集画法 → 这一帧交回 GDScript
	V2 anc{ 0.5f, 0.5f };      // A.enemy_pixel_anchor 之后
	double sc = 2.0;           // enemy_scale / hires × pixel_scale
	bool has_white_tex = false;   // g.tex.has(name + "_white")（精英冷色描边的前提，c[15]）
	int32_t glow = -1, wound_glow = -1;   // 发光点表
};

struct TypeInfo {
	bool known = false;
	bool full = true;          // dcs：Boss / 宝箱 / 骑士帧条 / draw_full —— 一律走 GDScript
	bool foot = false;         // g.foot_anchor.has(tex)
	C4 tint{ 1, 1, 1, 1 };
	Variant v[4];              // 0 本体、1 假死（_feign）、2 移动（_move）、3 休眠（_dormant）
	bool has_v[4] = { false, false, false, false };
};

// 每只可见敌人（world._vis_ent 的次序）的元信息位
enum : int32_t {
	M_BOSS = 1 << 0,
	M_CHEST = 1 << 1,
	M_ELITE = 1 << 2,
	M_EVO = 1 << 3,
	M_INVULN = 1 << 4,
	M_STUN = 1 << 5,      // e.stun > 0
	M_COMA = 1 << 6,
	M_DORMANT = 1 << 7,
	M_TEXMOVE = 1 << 8,   // e.tex_move
	M_SPECIAL = 1 << 9,   // _dc_ok 的动态排除条件成立（形变 / 蓄力 / 冲刺 / 出招…）→ 走 GDScript
	M_FEIGN = 1 << 10,    // e.tex_feign
	M_AFFIX = 1 << 11,    // 词条要画（armor，或 shield 且潮盾 > 0）
	M_WEAK_SHIFT = 12,    // 2 位：0 无、1 物理、2 法术、3 其他
	M_RC = 1 << 14,       // 读了后坐字段（rc_at 在窗口内）
	M_SKIP = 1 << 15,     // 其他原因走 GDScript（种类未登记、tex 与登记不符…）
};

struct FrameIn {
	double t = 0.0;
	double flash_a = 0.9;
	int32_t am_mode = 1;          // 1 恒白、3 查表（world._am_mode）
	std::vector<C4> lut;          // Look._lt（LUT_N + 1 格）
	double lt_inv = 0.0;
	V2 lpos{ 0, 0 };
	bool lamp_rim = false;        // world._lamp_rim（本体色 alpha 取负）
	bool optical = false;         // g.optical_on（发光点）
	bool elite_rim = false;       // world.elite_rim > 0
	double rc_px = 0.0, rc_t = 0.1;
	double px = 2.0;              // Game.PX
	C4 glow_enemy{ 1, 1, 1, 1 }, glow_elite{ 1, 1, 1, 1 };
};

struct EnemyCols {
	int32_t n = 0;
	const V2 *pos = nullptr;
	const double *r = nullptr;
	const V2 *kb = nullptr;
	const double *fx = nullptr;
	const double *flash = nullptr;
	const int32_t *id = nullptr;
	const int32_t *type = nullptr;
	const int32_t *meta = nullptr;
	const V2 *dpos = nullptr;
	const double *mv = nullptr;
	const double *rc = nullptr;   // 每只 3 个：rc_at、rc_t、rc_k（M_RC 时有效）
	const V2 *rcdir = nullptr;
};

class EnemyRender {
public:
	std::vector<Strip> strips;
	std::vector<GlowTab> glows;
	std::vector<TypeInfo> types;
	FrameIn fr;
	// 本帧
	EnemyCols cols;
	std::vector<uint8_t> elig;      // 走原生
	std::vector<int32_t> vsel;      // 画法变体
	std::vector<double> mv_out;     // 新的 mv_until（只对 elig 且 tex_move 有意义）
	std::vector<int32_t> seg;       // sort 的输出：[类, a, b]*（0 原生段：排序后下标 a..b；1 GDScript 敌人：可见下标 a；2 其他：其他物件下标 a）
	std::vector<int32_t> order;     // 排序后：>= 0 可见敌人下标；< 0 = -(其他下标 + 1)
	std::vector<Op> ops;
	// 发光点（双缓冲，同 g.glow_next / glow_cur）与弱点菱形
	std::vector<V2> gl_pos[2];
	std::vector<double> gl_sz[2];
	std::vector<C4> gl_col[2];
	int gl_cur = 0;
	std::vector<V2> wk_pos;
	std::vector<int32_t> wk_kind;
	std::vector<float> affix;       // emit_run 输出：[可见下标, bpos.x, bpos.y]*

	void frame_cols(const EnemyCols &c);   // 设本帧列，算 elig / 变体 / 移动状态
	void sort(const double *other_keys, int32_t n_other);
	void emit_shadows(const V2 &doff, float sw, float sh, float alpha);   // 填 ops（TEX_SHADOW）
	void emit_run(int32_t a, int32_t b);   // 排序后下标 a..b-1（都是 elig 敌人）：填 ops / 发光点 / 弱点 / affix
	void glow_add(const V2 &p, double sz, const C4 &c);
	void glow_swap();
	void glow_emit();                      // 当前帧要画的发光点 → ops（OP_RECT）

private:
	C4 act_mod(const V2 &pos) const;
	void glow_pts(const Variant &vr, bool wound, int32_t frames, int32_t frame, const V2 &pos, double sc, bool flip, const V2 &anc, bool big);
};

} // namespace ark
