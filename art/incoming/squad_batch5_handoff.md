# squad_batch5 五人交付（2026-10-11）
- 浊心斯卡蒂、德克萨斯、星熊、能天使、安洁莉娜各 idle/run/attack/skill，20 条帧条、40 PNG，含 1× 和 @2x。
- 48×48 / 96×96，锚点 (24,46) / (48,92)；帧数、fps、出手帧按 squad_batch5_manifest.json。
- 用户已批准五人精零与装备；浊心斯卡蒂增加参考手持物，见 reference_feedback / approval。
- 静态检查 40 PNG / 218 帧通过：尺寸、帧差异、透明边界、二值 alpha、脚底与每人 ≤24 色。
- 全帧条非描边平均明度 ≥0.41、@2x 外缘深色比例 1.00、外缘洋红残留 0；详见 squad_batch5_qa.json。
- idle 固定 f0，仅合成母图中的局部变化；skill 末帧等于 idle f0。出手帧星号见 preview。
- 原作与生成来源、完整提示词、母图哈希及分割坐标见 sources / generation；源图留本机，不入库。
- squad_overview.png 含已有 13 人与新增 5 人的同尺度 48px / 96px 对照。
- 未改代码、未跑游戏，接入方需按 manifest 设置时机，并做图鉴和同 seed 实机验收。
