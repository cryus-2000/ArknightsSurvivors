# 怪物尺寸实机测试 · 2026-10-18

用户批准 cl_enemy_scale_trial_1018 候选大小，并明确人形Boss不缩小；随后授权接入游戏实机试验。

基线：codex/doctor-runtime 87d5cf61（含上一轮怪物与博士测试资源）。尺寸依据：codex/art aef14e58；逐项倍率见 approved_sizes.json。

## 接入

复用现有 enemies.json.draw_scale，23槽位按批准倍率增大12%–40%；六个人形／类人Boss槽位保持原值。骑士精英0.7→0.945，Boss骑士0.7→0.98。该现有字段同时用于基础／移动／攻击、死亡、可见顶部及枪口特效的显示缩放，无新增渲染逻辑。源PNG、密度、帧数、fps、脚底锚点均不变；未改半径、伤害、AI、技能或预警判定。

## 实机查看

- build/enemy_scale_review/review.html：五段录像总览。
- build/enemy_scale_field/preview.gif：固定初始怪群的正式战斗更新，12只普通／精英使用常规1.5刷怪体型；水月／塞雷娅／斯卡蒂，起始t=180，观察者不死，5秒，10fps录像。
- build/enemy_animation_captures/{iberia,knight_boss,path,izumik}/preview.gif：已有图鉴真实AI、地图照明与绘制路径，初始5秒，原相机0.8缩放。
- 所有初始状态、半径、显示倍率和时间线见各目录evidence.json。它们是引擎截图，无外部图片代替。

人工已查看混合怪群、骑士Boss及圣徒伊比利亚代表帧：轮廓更大，近身脚部遮挡更明显，尚待用户实玩判断。并未宣称所有招式、全部阶段、死亡或拥挤场景均已通过视觉验收。

## 检查

新增已确认尺寸的断言并先在旧配置观察到失败，再接入数据。seed1/saria/45秒TRACE的46行与main 6b697796一致，结束BALANCE JSON复核无差异。当前全套检查结果与版本号由交付消息给出。技术检查保留博士等既有明确豁免，不将其视为新一轮美术通过。

实测：check.py --auto --jobs 3（预加载numpy后执行）77项、0失败，日志 build/check/quick_1018_115319；尺寸专项复查2项0失败（quick_1018_115757）。本机未编原生核心与14个过期金样对照由既有检查跳过。正式战斗录像和四个Boss演示均成功录得50帧、无脚本错误。未做全招式、全阶段视觉验收。
