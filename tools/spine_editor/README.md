# 本地 Spine 姿势编辑台

支持 Spine 3.5 与 3.8（按骨架文件头自动选运行库）。默认打开推进之王 Run，八帧 / 0.6 秒；也可打开 `tools/spine_run_trial` 生成的任意干员数据包（`--source build/spine_run_trial/<id>/editor_pack`）。原生贴图、网格、权重、动画 deformation 为只读；在现有已烘焙骨骼姿势上增加世界坐标姿势修正。不是官方 Spine 软件，也不是 `.spine` 工程导出器。

## 打开

本机双击 `Open-Editor.cmd`。服务只监听 `127.0.0.1:8876`，不提供手机远程访问。关闭网页后后台服务仍可供再次打开；重启电脑后重新双击启动即可。

也可以显式启动（Python 需要已安装 Pillow；本机 Anaconda 已有）：

```powershell
D:/Anaconda/python.exe -X utf8 tools/spine_editor/server.py --source E:/ArknightsSurvivors/.worktrees/codex-art/art/incoming/cy_siege_all_actions_1020 --runtime E:/ArknightsSurvivors/build/prts_ref/_node/spine-canvas-3.5.51.js
```

### 按干员打开（`--operator`）

```powershell
python -X utf8 tools/spine_editor/server.py --operator mizuki            # 有步态数据包用数据包，否则原生 Idle
python -X utf8 tools/spine_editor/server.py --operator wisadel --base native
python -X utf8 tools/spine_editor/server.py --operator irene --anim Attack --spread --port 8877
```

也可 `powershell -File tools/spine_editor/Start-Editor.ps1 -Operator suzuran`（同时开几个人时加 `-Port`）。

- 骨架 / 图集：主工作区 `build/prts_ref/_raw/<id>/`（单个 `.skel` + `.atlas`）；比例 = bz_18 `manifest.json` 的 `global_transform.scale` × bt_18 `source/catalog.json` 的 `scale`；调色板 = bz_18 `parts/*.png` 全部不透明色。与 `tools/spine_run_trial` 同口径。Codex 工作树只读。
- `--base auto`（默认）：若主工作区或任一 `.claude/worktrees/*/build/spine_run_trial/<id>/editor_pack` 有数据包，取最新的那份当八帧底稿（启动时打印路径）；`pack` 只用数据包；`native` 由浏览器用运行库算底稿：`--anim`（默认 Idle）的 t=0 ×8，或 `--spread` 按动画时长八等分。原生底稿把脚部附件最低点平移到地线，水平按部件包 `mapped_root` 对齐。
- 3.8 关节链按 PRTS 命名自动识别（`F_L/R_` + Arm/Forearm/Hand、Leg/Calf/Foot，含小写 thigh / shin / shoes、arm_A / arm_B / palm 等变体，跳过 IK / Armour 骨骼）；手的直接子骨骼名含 Weapon / Umbrella / Knife 等时作为握持武器。同名有两套骨骼（如 specter_unchained 的第二形态）时都可解算，标签给底稿里可见的那套。识别不到的部位仍可在列表里按骨骼名选，用旋转 / 移动。
- `--operator` 默认输出到 `build/spine_editor/<id>/`，草稿和导出按人分开。`siege` 映射到上面的 Codex 推进之王动作包；其余 3.5 干员（`_raw` 里是 3.5 二进制）需先用 `tools/spine_run_trial` 生成数据包再 `--source`。
- 已验证可打开 / 拖动 / 导出：irene、logos、lumen、mizuki、specter_unchained、suzuran、ulpianus、wisadel（2026-10-20）。未编辑帧与 spine_run_trial 脚本版对比：水月、铃兰数据包八帧与原生 Idle、维什戴尔原生 Idle，128 @2x 包围盒一致（仅水月 f03 左缘差 1 px），不透明像素 IoU 0.989–0.997。

原生运行库和游戏素材从已存在的本机目录加载，不拷贝进工具源码，不从网络下载依赖。`--runtime` 可省略：按 `.skel` / `.json` 文件头版本从 `--runtime-dir`（默认主工作区 `build/prts_ref/_node`）选 `spine-canvas-3.5.51.js` 或 `spine-canvas-3.8.js`。不支持 4.x、多图集、权重编辑；3.8 剪裁附件按层序裁切。

## 使用

1. 左侧选择关节，默认是持锤手。拖动圆点，或用四个方向按钮微调 1 个输出像素。
2. 手腕与脚踝采用双节 IK，保持骨长与原肘膝弯曲方向；手移动时锤子保留方向、跟随握点。超出可达范围时会限幅。
3. 修改躯干等部位，切换“围绕关节旋转”，在关节外拖动，或输入旋转增量后应用。“移动整支骨骼”是自由移动，可能产生接缝，应谨慎使用。
4. 列表越上方越靠前，用上下移调整层序；隐藏选中部件仅供观察，不影响导出。
5. 每次修改仅作用于当前帧。通过八个帧按钮切换；播放、慢放、上一帧轮廓用于检查循环。工具不自动补帧，也不自动修改其他七帧。
6. 点击“保存姿势”写入 `build/spine_editor/draft.json`，每次另存带时间的备份。刷新会自动载入匹配源指纹的草稿。“下载 / 导入 JSON”用于携带同源修正。退出未保存时浏览器会提示。
7. “导出像素动画”创建独立 `export_*` 文件夹：8 个透明 PNG、2048×256 帧条、128 @2x 游戏口径帧条 `strip@2x.png`（原点 (64,120)）、0.6 秒 GIF、姿势 JSON 和 manifest。超出场景边缘的像素会阻止导出，不静默裁剪。

修改文件包含来源 SHA256、八帧各自的操作序列和可选完整层序。原生 source JSON、atlas、raw/bones 和原有交付 PNG 不写入。骨架 / 来源改变会拒绝套用旧修正，以免误配。

## 像素和接入边界

浏览器逐附件渲染 4×，分别降采样、映射原作调色板、二值透明，再按层序合成；没有把整个人缩小后冒充部件像素化。Canvas 采样与 Python BOX / 局部碎色清理不完全相同，因此当前导出是审阅素材（与脚本版像素 IoU 约 0.99，见上），未宣称离线成品逐像素一致。

输出 256 场景原点 [128,180] 保留长锤范围，不是旧版 128 身体帧条；未自动写入游戏或修改攻击时序。没有像素绘笔、网格权重编辑、自动帧间插值、官方工程导出。保存的姿势可继续由同一工具重开和重导出。

## 验证

```powershell
node tools/spine_editor/test_core.cjs
D:/Anaconda/python.exe -X utf8 tools/spine_editor/test_server.py
```

测试覆盖层级变换、IK 骨长、武器握点、不可达目标、数据验证、PNG/GIF 输出与来源标识；3.8：最小二进制骨骼 / 槽解析（含 nonessential）、关节链与武器识别、数据包查找、干员 id 校验，以及本机有 PRTS 参照时水月 / 铃兰 / 维什戴尔真实骨架的加载、顶点、IK 骨长和默认握持手（无参照时跳过）。实际浏览器还需检查拖动、遮挡、撤销、保存后刷新及导出。自动检查不能代替动作视觉验收。
