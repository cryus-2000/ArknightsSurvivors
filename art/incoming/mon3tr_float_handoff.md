# Mon3tr 无脚悬浮修正

按用户2026-09-25提供的原作立绘重做：黑色晶体棘冠、绿色裂纹、弯曲节状悬浮躯干与镰刃，无腿、脚掌或落地步态。不包含立绘中的凯尔希。

替换 op_mon3tr_{idle,run,attack}.png 及同名@2x共6文件。64px与128px均修正，4/6/4帧、fps4/10/14、攻击出手索引2保持不变。run文件名保留兼容代码，内容改为浮游。

逻辑锚点仍为(32,60)/(64,120)，不是身体的接地点。悬浮轮廓底端约在104–108新像素，锚点上方留空。已明确允许悬浮，因此验收使用SkipBaseline；其他尺寸、二值alpha、边缘、描边、48色和帧差异检查均通过。用户要求重做解剖，旧剪影2像素限制不适用于此修正。

本次mon3tr_float_manifest.json和mon3tr_float_qa.json是Mon3tr现行数据；squad_2x_manifest.json、squad_batch3_manifest.json中相应文件hash已更新。以前整队QA和预览属于历史验收，不代表本次修正后的Mon3tr。mon3tr_float_frames.png为本批全部帧，mon3tr_float_preview.png为精选动作。

源图由内置imagegen依据用户立绘生成：C:/Users/colafax/.codex/generated_images/01a08159-bde5-7d50-b7e0-571e2eeb3a31/exec-f341b973-059e-420f-8b18-02498b373916.png。详细生成提示见mon3tr_float_prompt.txt。机械导出使用新矩形裁切，未套用锁定旧带脚轮廓的legacy导出器。

已同步main，当前USE_HIRES=true。Claude接收此美术提交后检查移动/攻击播放和场景悬浮观感；Codex未修改game/，未进行引擎内验证。
