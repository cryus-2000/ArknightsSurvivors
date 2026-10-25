# 寻访职业标志与卡片修订

分支 codex/headhunt-professions，基于 main 92e5c9bc。交由 Claude/协调人审阅合入；未合并 main、未发版。

## 最终范围

- 寻访界面八职业标志替换为原作线稿，覆盖职业选择、指定干员、揭示、结果页；其他页面公共 UI.class_glyph 不变。
- 只删除八职业选择卡底部的小剪影。指定干员页卡内小人及右侧人物均保留（用户后续明确要求）。
- 指定干员卡加宽：内部宽度不再被斜切量占用。保留单行完整名字，优先28号，长名字适配至22号；未采用换行方案。
- 标题信息和名字按斜卡真实截面居中。点击按真实斜卡范围判定，避免加宽后外接矩形相交而选错邻卡。
- 寻访券消耗、抽取/解锁规则、技能信息及流程未修改。

## 素材

八枚42×42透明白图为 PRTS Design 收录的原作 line_* 图标原件，未AI重绘；固定来源版本及SHA256见 sources.json。incoming原件与 game/art/ui/professions 运行时副本逐字节一致。本次用户明确要求采用原作职业标志，覆盖 docs/37 旧版不用原作图标的约定，其他素材不扩大范围。

来源：https://mooncellwiki.github.io/prts-design/arknights/profession

## 验证

- check.py --auto --jobs 3：110项通过，0失败；原生核心项因本机未编译扩展跳过。美术既有WARN/豁免见完整日志。
- 固定基线92e5c9bc、seed1、水月60秒：61行TRACE相同。
- 检查运行期间按用户追加要求修改了保留人物与卡框排版；这些最终修订额外运行真实宿主界面回归，桌面1280×720、手机横屏1480×720均通过，无脚本/解析错误。
- 实机检查职业选择、先锋单卡、近卫四卡、特种三卡；完整名字单行显示，指定页人物保留。
- 加宽斜卡重叠外接矩形处实际点击测试通过，选中正确干员并只扣2张凭证。
- 可复现入口 game/tests/headhunt_professions_preview.tscn，参数 --roster=start5 --shotdir=<已存在目录>，手机加 --touch；必须经tools/godot_runner.py静音离屏启动。
- 图片及日志在 build/headhunt_professions/desktop、phone，不提交build输出。

旧 --huntshot 探针当前未打开寻访层，截到结算，且退出有资源泄漏诊断；此次不以旧探针作为视觉验收依据。新独立宿主探针最终无警告/错误。未做浏览器/Web导出或手机实机验收。
