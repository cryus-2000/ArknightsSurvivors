# docs/69 B — hoshiguma 配色返修

范围：四组动作各1x / @2x，共8张PNG，逐帧色板归一化；剪影、透明区域、原描边像素、锚点、帧数/fps/出手帧未变，skill末帧仍与idle首帧逐像素相同。manifest哈希已更新。只动art/incoming。

idle@2x非描边：近黑 30.45%，亮部 23.92%，诊断灯光模型受光晋升 11.05%，HSL均值 0.3558。
头发平均Y 133.79，亮部占头发 41.61%。

完整逐条测量及实际色表见独立color_qa.json；独立color_preview.png为深蓝底前后对照。配色和后续C跑步是分项交付，不用跑步指标判这项。

未运行Godot；受光晋升沿用docs/64的R1.6/G1.5/B1.3诊断计算，不冒充L4实机测量。Claude合入后依docs/69做实机验收。

严格使用tools/op_bright_mockup.py中的V5整色色板映射，按docs/69保留白盾沿、肤色、角、眼睛；因几何零变化，盾沿发射点未变。
