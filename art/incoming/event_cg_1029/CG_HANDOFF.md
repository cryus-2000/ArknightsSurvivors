# 事件插画 1029 · 六张定稿

分支：`codex/event-cg-1029`。基线：`d88b56b56`。用户于 2026-10-29 确认画面并要求提交；尚未接入游戏。

## 交付

`generated/` 含 task、vanguard、sellout、craft、homecoming、scholar 六张 1327×1185 RGB PNG。`approved_manifest.json` 沿用上批文件名与字段，但 status 为 visual_approved_2026-10-29_not_integrated。

以任务单 codex_event_cg_1029_ORDER.md 的新规格为准，不使用 docs/156 早期 140×125 / 64 色草案。采用 built-in image_gen 逐张重新绘制，原作 CG 为构图参照，1026 批 rest / tinder 为风格参照。生成提示保存在 prompts.json，来源及哈希见 provenance.json。导出只统一 RGB 和要求的尺寸，不对原图量化冒充重绘。

## 视觉自检

- task：对照 PRTS 郁金香立绘的灰银发、黑帽、眼罩和青色饰件；三图标并排，最右红色。首稿误带入休息室背景，最终稿修为暗桌面并上移图标。
- vanguard：暖橙制式火盆与金属架；没有晶树，和引火之木区分。支架顶部延伸至画外，不影响火盆主体。
- sellout：细线吊起多层仪器，保留青蓝光和下方海水高光。
- craft：两匣并排，矛尖与巨锤头在上部可区分；柄尾延伸下方。
- homecoming：保留日光、白墙、蓝紫花和巷道纵深。
- scholar：红布桌和烛光为焦点；布下骨鳞装备是任务单允许的本作拟造，非原作装备复刻。

## 检查与边界

六张母稿、1120×1000 / 560×500 缩览和下部压暗叠字模拟分别检查；具体尺寸、模式、哈希由 manifest 记录。预览在 build/event_cg_1029_review/review.html。原作裁切对照只在 build 下；原图不进入交付目录、不入包。

叠字图使用检查占位文案，不是新剧情文案，也不是实机截图。尚未验证游戏接入、实际撕纸裁切、电脑 / --touch 截图、运行时显存与包体。本次按用户确认提交；由 Claude 按 docs/156 接入 hi q90 / web q88，运行 tests/event_cg_shots.tscn --ids=task,vanguard,sellout,craft,homecoming,scholar，并检查 --touch。未修改 game/。

## 2026-10-29 像素风格修订

用户要求统一修正风格偏差。重绘 task / sellout / craft / homecoming / scholar 的像素色块、轮廓和材质明暗；vanguard 保持原稿。修订提示见 style_revision_prompts.json。旧稿只留 build/before_style_revision，不提交。新增独立 event-cg-pipeline skill，并在原角色像素 skill 中增加路由；不改角色 Spine 规则。用户已于 2026-10-29 确认本轮画面。
