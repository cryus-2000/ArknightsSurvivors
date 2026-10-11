# docs/69 A — texas 配色返修

范围：四组动作各1x / @2x，共8张PNG，逐帧色板归一化；剪影、透明区域、原描边像素、锚点、帧数/fps/出手帧未变，skill末帧仍与idle首帧逐像素相同。manifest哈希已更新。只动art/incoming。

idle@2x非描边：近黑 45.18%，亮部 13.65%，诊断灯光模型受光晋升 4.93%，HSL均值 0.3137。

完整逐条测量及实际色表见独立color_qa.json；独立color_preview.png为深蓝底前后对照。配色和后续C跑步是分项交付，不用跑步指标判这项。

未运行Godot；受光晋升沿用docs/64的R1.6/G1.5/B1.3诊断计算，不冒充L4实机测量。Claude合入后依docs/69做实机验收。

依据art/reference/texas_target_1012.webp：主体发色#484050，后下发束连续阴影#26262E（约#282830），少量#696572冷灰高光；衣服#1C1A22/#0E0D12。白衬衫、徽章、橙剑橙瞳和红腰带保留；target_preview附指定目标图对照。
