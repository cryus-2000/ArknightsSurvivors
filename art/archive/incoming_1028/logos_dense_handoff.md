# Logos 白色经文密排返修 · 2026-10-13

用户确认：字距收紧，以立绘的连续文字行为准。仅修改 chain_tile / chain_pulse / chain_anchor 及各自 @2x，共 6 PNG；魂灵层数标记保持原样。

- tile / pulse：每节由单行三个大符号，改为两行错位、每行四个小字；字高 3px、字间 1px，保留整行之间的透明空隙。水平循环平移，每节可重复平铺。
- anchor：12 个小字沿紧凑椭圆排列，后灰白、前亮白，中心留空。
- 尺寸、帧数、fps、origin、layer 与第 2 批保持一致。白/灰白三色、二值 alpha、无黑底；@2x 最近邻保留一致像素网格。
- 生图母版以用户白色经文近景及字母表为参考。后期去掉母版额外泛光，仅裁切高亮字形，再缩小、密排、滚动；不声称符号串有可验证译文。
- manifest 附母版路径和 SHA256；QA 检查帧尺寸、非空、透明、白色范围、倍率对应和文件哈希。预览按 4 倍最近邻，左右为返修前/后；重复平铺展示发射文字行，不是游戏实机。
- 只交 art/incoming 素材；Claude 接收此提交后沿现有链条平铺。图中两行已包含在同一 tile，不必重复画两次。人物周身 S3 环绕及其他旧 fx_logos_script 未在本次改变。游戏运行验证由接入方执行。

校验记录：python tools/art_lint.py --ops logos --no-images 已执行，未豁免 FAIL 0、WARN 4，均为本轮未改的人物帧条存量问题（倍率剪影差、总色数、skill 末帧、run 脚底 x）。详见 logos_dense_operator_lint.json；FX 专项检查见 logos_dense_qa.json。
