# 2026-10-12 服饰及配色返修：specter_unchained

归溟幽灵鲨：四组本体动作统一连裤黑丝，无裸腿断口或长袜顶边；红瞳、冷银灰头发、冷黑/海军蓝服装、深蓝飘带。追加倒下过渡，本体首帧与新 idle0 相同，末两帧沿用修女替身造型并归并冷色调；独立 doll 帧条未重画。

规格保留原 48/96px、帧数、fps、事件帧和锚点；skill 末帧 = idle0。内置 imagegen 编辑，导出机械切帧、统一调色板与描边。

## QA

`costume_1012_specter_unchained_qa.json` 保存数值检查；二值透明、尺寸、边界描边、脚底锚点、共享调色板 ≤24 色及哈希已检查。仅图片验证，未在引擎运行。

## 预览

`costume_1012_specter_unchained_preview.png` 单独提供四组动作预览。

## 接入

仅 art/incoming/，未改 game/。Claude 从干净 main 按提交顺序接收，并实机检查腿部、瞳色、动画节拍。本轮随后还有 docs/73 待机提交，覆盖能天使 idle 时请一起接收。

倒下预览：`costume_1012_specter_fall_preview.png`；其独立 manifest 为 `specter_costume_1012_fall_manifest.json`。
