# V14 第 1 批：灯柱与冰枪桩
- 文件：prop_lamp_post、prop_ice_stake、prop_ice_stake_break，均有 1× / @2x；规格与 SHA 见 v14_batch_1_manifest.json。
- 灯柱 f0 熄灭单帧；点亮循环 f1–f2，4 fps；锚点 (10,29)。灰蓝石材、青苔、暖黄内焰。
- 冰枪桩 2 帧 4 fps；碎裂 4 帧 12 fps 单次；锚点 (12,53)，末帧仅剩碎冰，不拉伸放大残骸。
- 武器沿用已通过验收的骑士长枪元素；灯柱、冻结和碎裂按项目机制工单适配，不宣称原作逐像素复刻。
- 无光圈、预警、落点椭圆、影子或程序冰爆环；这些仍由程序绘制。
- 深蓝 @2x 原尺寸预览：v14_batch_1_preview.png；static_qa / outline_qa 为对应静态证据。
- 6 PNG / 18 帧通过基础静态检查；二值 alpha、描边中位数 1 / 2、四边留空、锚点和 SHA 符合规格。
- 未改 game/、未跑游戏；由 Claude 接入并按 V14 实机与图鉴验收。
