V12 第 1 组 · 第 1 批：巨海漂流体（3 个文件组，含 @2x）。
交付：e_hulk、e_hulk_move、e_hulk_attack；透明横向帧条，朝右。
单帧：1× 64×52，@2x 128×104；锚点分别 (32,49)、(64,98)。
待机 2 帧 4fps；移动 4 帧 6fps；攻击 4 帧 10fps，第 2 帧落地（从 0 计数）。
暗骨白甲壳、土黄关节；1× 1px / @2x 2px 深色描边，未加图内冲击特效。
v12_hulk_manifest.json 含尺寸、帧数、帧率、锚点、SHA-256 与逐帧检查；v12_hulk_contact_preview.png 为接触表。
检查通过：尺寸、锚点、二值 alpha、共用 ≤48 色、紫色残留 0、帧间非重复；未运行游戏。
下一批：第 1 组暗海撕裂者 e_ripper / e_ripper_move / e_ripper_attack。
