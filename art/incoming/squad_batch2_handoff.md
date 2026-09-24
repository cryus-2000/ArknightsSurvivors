# 编队美术第二批：维什戴尔

依据 `docs/24_squad_art_brief.md`。新增4条 / 22帧，均为48×48，脚底 `(24,46)`。

| 文件 | 帧数 | fps | 出手帧（从0计） | 人工数帧 |
|---|---|---|---|---|
| op_wisadel_idle.png | 4 | 4 | 无 | 无 |
| op_wisadel_run.png | 6 | 10 | 无 | 无 |
| op_wisadel_attack.png | 5 | 14 | 2 | 第3帧 |
| op_wisadel_skill.png | 7 | 12 | 4 | 第5帧 |

idle/run循环；attack/skill单次。普攻为架炮、蓄势、后坐、硬直、复位；技能包含压低炮口、抬炮、强后坐与收势。每帧只有一把本体武器，发射帧没有额外背炮；炮口火焰、弹道和爆炸由 Claude 制作。

配套：`squad_batch2_manifest.json`、`squad_batch2_preview.png`、`squad_batch2_qa.json`。预览里的星号标注出手帧，数字从0开始。游戏按事件帧生成弹道，不要把第3帧误写成索引3。

已检查本批4条的尺寸、二值透明、24色共享色板、#080E18边缘、脚底基线与帧差异。未修改 game/；游戏内射击时机和镜像效果待接入验收。
