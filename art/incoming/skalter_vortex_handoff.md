# 浊心斯卡蒂 S3 地面漩涡交接 — docs/66

## 交付
- fx_skalter_vortex_floor.png：2560×176，8 帧，每帧320×176，10 fps 循环，原点(160,88)。
- fx_skalter_vortex_floor@2x.png：5120×352，每帧640×352，原点(320,176)，精确 nearest 放大；世界尺寸与1x相同。
- skalter_vortex_manifest.json：规格、色板及 PNG SHA256。
- skalter_vortex_preview_50.gif / .png：深色地板，50%透明度合成。
- skalter_vortex_preview_100.gif / .png：100%透明度合成。
- skalter_vortex_qa.json / skalter_vortex_generation.json：检查数据与来源、导出参数。

## 视觉修改
大面积压扁的地面水纹，细而断续的青色弧线、少量暗红流线，中心留空，无音符、人物、投影或完整外边界环。保留已交付的贴身 S3 back/front/orbit。本次没有改动那些资产。

## Claude 接入
画在单位下方地面层，normal alpha / nearest；1x像素比例=歌域外半径/160，整体alpha起始值0.5，开关淡入淡出0.4–0.5秒。原程序漩涡减为光点或关闭主体，保留缺图回退。本次不交可选motes，继续使用程序光点。

## 检查与边界
二值alpha、6个实际颜色、8个独立帧、中心1/4半径无实色、红色占2.7%–6.0%、无边缘裁切、精确2x已检查。循环末首像素变化量为相邻平均的1.019倍，无额外空帧或淡出帧；该数值不替代实机动画验收。
预览为离线地面合成，不是实机截图。本次只交美术，未改game/，未运行引擎或打包；持续向内流动观感、接缝和与现有贴身层的叠加请接入后审查。
