# Spine 部件跑步试做（2026-10-20，干员）

目标：看能不能用原生 Spine 骨骼和部件直接调出像素小人的跑步，代替逐帧手绘。只试做和出图，不接入游戏、不改 game/。

## 1. 结论

| 干员 | 结论 |
|---|---|
| 推进之王 | 可用（10-20 用户反馈抬腿偏高，lift 1.3 → 0.8，摆动腿离地峰值约 31 原生单位 ≈ 6 像素）。扛锤跑步：承重、后蹬、屈膝回收都看得出来，锤子跟着手走。同一份姿势导进编辑台后导出，两边轮廓一致（逐帧包围盒相同）。持锤手在大头前面，会挡住下巴，要逐帧手调层序或握点 |
| 水月 | 可用，比现有 run 条动作幅度大：腿有完整步序，伞跟着手走，帽绳和衣摆会拖。帽子和身体整块刚性，看着略僵 |
| 铃兰 | 能跑，但裙摆盖住大腿，步子小，读起来更像碎步。颜色比现有 run 条淡，因为调色板取自 bz_18 部件包（PRTS 原色），旧条是手绘暖色。大尾巴摆动效果好 |

总体看：步态、前倾和次级摆动可以全自动生成，适合批量出初稿。剩下的问题（遮挡、手挡脸、裙子）每人 2–4 帧的手调就能解决。

图在 `build/spine_run_trial/<id>/`：`*_run.gif`（0.6 秒）、`*_run_slow.gif`（4 倍慢放）、`*_x8.png`（8 倍逐帧带网格）、`*_vs_old.png/.gif`（与现有 run 条对照）、`*_strip@2x.png`（1024×128 帧条）。推进之王另有 `editor_export/`（编辑台原样导出）。

## 2. 方法

脚本在 `tools/spine_run_trial/`（只读素材，输出到 build/）：

1. **读原生骨架**：`load.js` 读 PRTS 原生 skel / atlas（推进之王用 3.5 转出的 JSON，水月、铃兰用 3.8 二进制），基础姿势取 Idle t=0。
2. **步态表**（`run_trial.js`，8 帧）：每条腿 8 个相位（触地、下压承重、经过、后蹬、离地后踢、屈膝回收、前摆、前伸），用脚踝相对髋的位置和脚掌转角表示，单位是本人腿长。两腿相差 4 帧。双节 IK 保持骨长，膝盖始终朝前；支撑相反复迭代，把鞋底网格的最低点贴到 Idle 地面。
3. **躯干**：髋部整体前倾，胸部再加一点前倾，头部回正一部分（保住脸的可读性）；身体在下压帧最低、腾空帧最高。
4. **手臂**：空手和同侧腿反向摆动，肘部角度跟着摆动变化。持武器的手可以用 `holdPose` 指定上臂 / 前臂的绝对角度（推进之王扛锤），也可以只做小幅摆动（水月、铃兰）。武器绕握点转到指定角度，握点不漂移。
5. **次级摆动**：头发、尾巴、衣摆、绳带按骨骼名正则匹配；链根向后拖，各节按链深度滞后做 2 倍频摆动。
6. **像素化**：每个附件单独渲染 4 倍图 → 按 alpha 加权做 4×4 BOX 平均 → 二值透明（阈值 96；整件低于阈值的细节保留最大覆盖的格子）→ 映射到 bz_18 部件包的原色调色板 → 按层序合成。坐标映射和 bz_18 静态包一致（`mapped_root + bz_scale × source_scale × 世界坐标`），画布 128 @2x，原点约 (64,119)。Idle 自检：三人和 bz_18 full@2x 基本重合（`build/spine_run_trial/_idle_check.png`）。
7. **进编辑台**（目前只有推进之王）：`--editor-ops <Codex Run raw 目录>` 把生成的世界姿势换算成编辑台的旋转 / 平移操作（相对 Codex 已烘焙的 Run 骨骼，每帧约 41 条）。写进 `build/spine_editor/draft.json` 后，编辑台打开就自动载入，可以继续手调后再导出。本次就是按这个流程，用编辑台按钮导出到 `export_*`。

每人一个配置 `cfg/<id>.json`：躯干、腿、手臂的骨骼名，持武器的手，武器骨骼，次级骨骼正则，以及参数（前倾、步幅、抬腿、起伏、摆臂、肘角）。

## 3. 编辑台不支持 / 遇到的限制

- **只认推进之王一份 3.5 数据包**：`load_project` 写死了 siege、Run、单张图集、手脚 IK 链名（F_X_Arm/Shoulder/Hand）。水月、铃兰是 3.8 二进制，骨骼名也不同（Forearm / Hand_Close / Hand_b），编辑台打不开，只能用脚本出图。
- **以 Codex 烘焙的 Run 骨骼为底**：编辑台的修正叠加在已有八帧上，没有「从 Idle 起摆一套新动作」的入口；换角色得先有一份 raw/<帧>/bones.json。
- **没有批量 / 全帧操作**：所有修改只作用于当前帧，没有「八帧一起前倾 5 度」这类操作，也没有按相位的曲线；调步态得逐帧拖。本次绕开的办法是由脚本生成姿势，再导入编辑台。
- **导入只能走文件选择或 draft.json**：没有命令行接口。本次通过 `/save` 写 draft 后刷新页面载入。
- **导出规格**：编辑台导出 256 场景、原点 (128,180)，不是 128 @2x 帧条；嘴部等细件没有 bz_18 的 mouth_sampling 特殊处理（脚本同样没有）。
- **共同限制**：网格变形（deform）停在 Idle t=0，衣摆、裙子只能跟着骨骼转，没有布料的形变；手放到大头前面时会挡住脸，要手调层序或握点；胸、胯的侧向转身（两条腿前后交叠时的透视）做不出来，只能靠层序。

## 4. 建议的批量流程

1. 每人写一份 `cfg/<id>.json`（约 15 分钟：从 `node load.js cfg/<id>.src.json` 的骨骼清单里挑名字）。
2. `node run_trial.js cfg/<id>.json` → `python sheet.py ...` 出初稿，看 x8 和对照 GIF，调参数（前倾、步幅、持武器的姿势、次级幅度），一般 2–3 轮。
3. 有问题的帧（手挡脸、遮挡、裙子穿模）再进编辑台手调。前提是编辑台扩展为按配置加载任意角色、支持 3.8，并能以脚本生成的姿势为底，见第 3 节。
4. 导出 128 @2x 帧条 → 按 docs/104 §4 三层验收（人眼先行）→ 用户批准后再接入。

想让编辑台覆盖 18 人，建议的改动（交给编辑台作者，Codex 或干员会话）：project 由配置驱动（角色、运行库版本、链名、武器骨骼）；新增「从 Idle + 步态表生成」作为底稿；加一个「对全部帧应用」开关；导出加 128 @2x 规格。

## 5. 复现

```bash
export NODE_PATH=E:/ArknightsSurvivors/build/prts_ref/_node/node_modules
node tools/spine_run_trial/run_trial.js tools/spine_run_trial/cfg/siege.json --editor-ops E:/ArknightsSurvivors/.worktrees/codex-art/art/incoming/cy_siege_all_actions_1020/raw
python tools/spine_run_trial/sheet.py build/spine_run_trial/siege/frames build/spine_run_trial/siege/siege --old art/incoming/op_siege_run@2x.png --old-origin 64 120
```

水月：`--old art/incoming/mizuki_runtime_run@2x.png --old-size 192 --old-origin 96 152`；铃兰：`--old art/incoming/op_suzuran_run@2x.png --old-origin 64 120`。
