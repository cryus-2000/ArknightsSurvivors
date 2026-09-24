# 博士与坎诺特 NPC 像素美术（V10）

本轮交付两张原创 Q 版 48px 双帧待机横条，仅为美术，不改游戏代码。

| 文件 | 单帧 | 帧数 | 建议播放 | 说明 |
|---|---:|---:|---|---|
| `doctor.png` | 48×48 | 2 | 2 fps 循环 | 博士：遮面兜帽、深色罗德岛长外套、浅灰内层、青色衣领 |
| `merchant.png` | 48×48 | 2 | 2 fps 循环 | 坎诺特：神秘兜帽／头盔、厚旅行衣、货袋与暖色提灯 |

通用规则：透明 PNG、alpha 仅 0/255、1 像素深色外描边，正面略朝右；底部中心锚点 `(24,45)`，2× 最近邻采样。左侧视角可镜像。`merchant.png` 对应游戏当前 `game/art/px/merchant.png` 的 NPC，但**新图尺寸为每帧 48×48**，旧占位图为每帧 16×20；Claude 接入时需同步调整导入切帧参数、绘制偏移和显示倍率，不能只复制覆盖。`doctor.png` 为新增 NPC 素材，是否加入场景与行为由开发侧决定。

形象参考：[PRTS「水月与深蓝之树」诡意行商](https://prts.wiki/w/%E6%B0%B4%E6%9C%88%E8%82%89%E9%B8%BD)、[Arknights Terra Wiki「Doctor」](https://arknights.wiki.gg/wiki/Doctor)。使用内置 imagegen 绘制像素原稿，再缩放、量化和描边；未直接使用游戏原图。具体逐帧尺寸、SHA-256 和像素检查见 `npc_v10_manifest.json`；放大预览见 `npc_v10_preview.png`。
