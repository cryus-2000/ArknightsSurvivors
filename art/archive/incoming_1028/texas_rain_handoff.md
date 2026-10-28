# 德克萨斯金色剑雨返修交接 · 2026-10-12

## 范围与优先依据
执行 docs/70 三条素材；用户本轮明确「剑雨用金黄色的」，覆盖工单第3节朱红橙色要求。金黄刃口、浅金高光、白热芯、深棕钢色柄与描边，预兆/冲击/余烬同色系。只改 art/incoming，不改game/。

## 素材
- fx_texas_blade：16×40，6帧，锚点(8,38)；@2x锚点(16,76)。0–1下落循环20fps，2–5由程序按插地时间铺开。
- fx_texas_rain_hit：32×24，5帧，24fps，锚点(16,20)；@2x(32,40)。
- fx_texas_rain_mark：24×12，6帧，锚点(12,6)；@2x(24,12)。0–2预兆，3–5焦痕，按程序时间铺开。
- 六张PNG均二值透明，共用9色色板，@2x为工单允许的最近邻放大，不声称增加高清细节。

## QA（独立于预览）
texas_rain_qa.json记录尺寸、哈希和透明检查。17帧均非空，插地帧地面线y38以下无像素；两种尺寸严格对应。源图由built-in image_gen绘制，导出时做裁框、定尺寸、限色和alpha二值化。具体来源hash记录于manifest。
视觉已检查联系表。低分辨率下火星与消散作简化表达，仍需实机比较密度和亮度。没有运行Godot，不把素材检查当成实机验收。

## 预览
texas_rain_contact.png：三条帧条4倍展示，背景#1e3034。
texas_rain_s1_preview.gif：21柄、r130、0.4秒错落、96px加速落差、0.35秒插地与地面焦痕的离线示意。预览没有敌人，不模拟敌人目标分配、程序残影和后期fx_dim，不是实机截图。

## Claude接入
直接采用六张同名PNG替换游戏素材，保持现有V6_FRAMES、锚点与verb.fx_rain编排。S3密集叠加检查金色是否过亮，再调程序alpha而非更改帧数。无需将本离线GIF作为游戏资源。

## 生成提示摘要
Golden sword rain, crisp pixel art, transparent sprite atlas: six falling/embedded/cooling/dissolving sword frames, five impact frames, six warning/scorch frames; dark brown outline, gold blade, pale gold and ivory hot core; no magenta/purple/red; remove broad haze; retain small isolated sparks. Built-in image_gen, then mechanical export to docs/70 frame contracts.
