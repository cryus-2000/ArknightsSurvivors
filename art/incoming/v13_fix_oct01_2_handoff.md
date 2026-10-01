# V13 描边返修 2 + V14 骑士长枪（2026-10-01）
- 文件：e_izumik_rooting、e_path_charge、proj_knight_spear，各含 1× / @2x。
- 两条 Boss 动作只修正导出叠厚的描边；轮廓、动作、脚底不变；未扩大范围重设计怪物。
- 长枪以本地原作 knight_atlas.png 底部武器为参考，细长深灰杆、不规则银灰枪刃，朝右两帧冰光细变；不画光圈 / 拖尾。
- manifest：v13_fix_oct01_2_manifest.json、v14_spear_manifest.json（参考和生成源 SHA 已记录）；预览为对应 *_preview.png。
- 检查：6 PNG / 20 帧静态通过；描边中位数 1× 1px / @2x 2px；Boss alpha 变化 0；长枪飞行物按中心锚点，跳过脚底检查。
- 证据：对应 *_outline_qa.json 与 *_static_qa.json；未跑游戏，Claude 接入、复核实机。
- V14 灯柱 / 冰枪桩 / 碎裂、新星弹及酸液与碎石仍待原作外观依据核对；此提交不代表 V14 全部完成。
- V13 伊比利亚装填、伊祖米克攻击接缝、泡影二阶段仍未完成；不采用未经原作核对的破壳肉质改造。
