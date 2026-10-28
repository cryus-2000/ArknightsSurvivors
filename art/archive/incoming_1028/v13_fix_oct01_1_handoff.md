# V13 描边返修 1（2026-10-01）
- 文件：e_carmen_slash、e_iberia_attack，各含 1× / @2x。
- 保留已验收动作、服装、刺剑 / 枪械、脚底及逐帧 alpha 轮廓；未采用新增金饰的生成稿。
- 修正导出叠厚的黑边；透明边界距离内归一为 1× 1px、@2x 2px，内侧多余黑边用原帧邻近色回填。
- manifest：v13_fix_oct01_1_manifest.json；预览：v13_fix_oct01_1_preview.png（深蓝底、@2x 原尺寸）。
- 检查：4 PNG / 16 帧通过尺寸、透明度、边界、脚底、色数、帧差异、SHA；独立外描边中位数 1 / 2，alpha 变化 0。
- 证据：v13_fix_oct01_1_outline_qa.json、v13_fix_oct01_1_static_qa.json。
- 不包含伊比利亚装填返修；未跑游戏，接入及实机复核由 Claude 完成。
