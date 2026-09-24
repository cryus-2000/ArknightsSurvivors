# 参考资料 (reference)

存放用户提供的参考资料和设计要求。做设计/实现前先查这里。

## 目录约定

- `README.md` — 本索引，新增文件时在下面登记
- 原作资料（数据表、截图、wiki 摘录）直接放本目录，文件名写清来源和内容
- 用户的设计要求 / 口头需求整理成 `design_requirements.md`（按日期追加）

## 文件索引

| 文件 | 内容 | 来源 / 备注 |
|---|---|---|
| `mizuki_collectibles_zh_262.json` | 明日方舟「水月与深蓝之树」全部 262 件收藏品（id / name / effect） | 用户提供；以 BWIKI/PRTS 核对，MAA shopping.json 作底表。可作为本项目藏品设计的参考池 |
| `global_design_framework_v1.0.md` | **全局游戏设计框架 v1.0（最高设计依据）**：Build 系统、藏品 Tag / 等级、商店、Boss 奖励、灯火、架构、开发优先级 | 用户与 GPT 讨论产出（2026-09-24） |
| `mizuki_collectibles_adaptation.json` | 262 件藏品在本作中的改编效果、实现难度、等级、流派、Tag | 由 Claude 生成，与 `docs/08_relic_adaptation.md` 同步；复制为 `game/data/relics.json` 供游戏读取 |
| `icons/`（262 张 PNG，不入库） | 用户收集的藏品图标，按「编号_名称」命名 | 抽查后判断为官方游戏素材风格：**只用于核对编号与名称，不作为美术参考，不描摹、不改绘**；已加入 `.gitignore` |
