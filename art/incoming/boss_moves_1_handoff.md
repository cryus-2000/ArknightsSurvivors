# Boss 招式第 1 批 + 现有动作 @2x 交接

本批仅本体素材，按用户本轮明确要求交 6 条新招式（1x + @2x）及 22 条现有动作 @2x，共 34 张 PNG；不包含 docs/95 的 FX 表，不修改 game/。

## 新招式
|帧条|单帧 1x|帧数|fps|原点|出手帧（从 0 起）|
|---|---|---:|---:|---|---|
|e_paranoia_gaze|[72, 72]|4|10|[36, 69]|[2]|
|e_paranoia_phase2_howl|[72, 72]|4|10|[36, 69]|[2]|
|e_ishar_t_sing|[112, 96]|4|8|[56, 93]|[2]|
|e_izumik_share|[72, 72]|4|10|[36, 69]|[2]|
|e_knight_spin|[96, 80]|6|12|[48, 77]|[2, 3, 4]|
|e_knight_thrust|[96, 80]|3|14|[48, 77]|[1]|

全部新招式为单次播放；帧条横排，@2x 各维度翻倍。保留本体清楚的收缩/蓄力/出手/收势，不烘焙刀光、声波或水流。泡影呼号只保留嘴边两个小泡。

## 原作核对与修正
伊祖米克是水母形态：废弃曾生成的侧向管状炮口，交付版保留闭合天然伞体和触须，以收缩、舒展及朝右倾斜表达动作。原作「分享」在吸收子代后造成全场法术伤害，工单窄扇形水流是本项目改编，不能视作原作炮口喷射。仅交本体动作，不更改攻击逻辑。
出处：https://prts.wiki/w/伊祖米克（2026-10-14 核对）。
骑士回旋保留马身驻足，枪尖前/后/前；前刺收势复用蓄势帧，避免生成候选末帧突然转头。伊莎玛拉保持白壳、金棘和青色口部。

## 现有动作 @2x 清单
- e_paranoia@2x.png
- e_paranoia_move@2x.png
- e_paranoia_phase2@2x.png
- e_paranoia_phase2_move@2x.png
- e_ishar@2x.png
- e_ishar_attack@2x.png
- e_ishar_move@2x.png
- e_ishar_t@2x.png
- e_ishar_t_attack@2x.png
- e_ishar_t_move@2x.png
- e_ishar_transform@2x.png
- e_izumik@2x.png
- e_izumik_attack@2x.png
- e_izumik_move@2x.png
- e_izumik_rooting@2x.png
- e_knight@2x.png
- e_knight_attack@2x.png
- e_knight_charge@2x.png
- e_knight_charge_form@2x.png
- e_knight_death@2x.png
- e_knight_move@2x.png
- e_knight_plant@2x.png

现有动作仅增加或替换同名 @2x；原 1x 文件 SHA256 不变。帧序、画布、原剪影和脚底行随原图保持。重制细节来自生图候选，逐格注册到原轮廓；非最近邻放大交付。旧动作 fps / 出手帧继续由现有程序决定，本次不改元数据。
docs/95 §13.1 的宽度表有笔误：实际采用泡影 72×72、人形伊莎玛拉 80×80、变身伊莎玛拉 112×96；与已有文件、帧数及 §1.4 / §2.4 一致。

## QA（与预览分开）
boss_moves_1_qa.json：28 条动画 / 34 张 PNG 通过画布、帧数、二值透明、2px 外描边、逐帧剪影配对与新招式脚底行检查。每 Boss 本批 @2x 共 31 色（≤32）；新 1x 对应导出。原有 1x 色数超标仍保留，因 §13.1 明确只重出 @2x，具体原色数已记录在 QA。
tools/art_lint.py 仅支持干员 roster，因此未冒称 Boss 通过 --ops；Boss 采用本批 manifest 检查。干员 E 批另有 art_lint 输出。
颜色内部有 2×2 非均匀细节块，证明 @2x 非简单最近邻放大；alpha 轮廓则按原版锁定，避免切换抖动。
未启动游戏或宣称引擎接入通过；Claude 接入后需检查新动作触发时机、骑士本体驻足、1x/@2x 切换和场景暗处可读性。

## 预览
boss_moves_1_preview.gif：6 条新招式，实际帧率，末尾附短暂收势停顿。
boss_moves_1_existing_preview.gif：22 条存量动作概览（预览用默认速度，不覆盖运行时 fps）。
boss_moves_1_lineup.png：原 1x 最近邻放大与 @2x 重制并排，亮/暗两行。

## 工序与出处
生图候选沿用已确认本体设计；按原像素色板收敛、二值透明、2px 描边、分格/注册/导出，再独立 QA。候选源文件 ID、导出脚本 SHA256 和每张交付 SHA256 见 manifest。
