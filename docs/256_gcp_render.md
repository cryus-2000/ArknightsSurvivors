# 256 GCP 出图流程：本机只写代码，截图与录像放 GCP（11-05）

**结论摘要**
1. 11-05 协调人转述用户同意加快美术进度：特效会话只在本机写代码，截图、录像、同种子 TRACE 一律在 GCP 虚拟机上出，本机不开 Godot 渲染。
2. 一条命令：`python tools/gcp_render.py --branch <分支或提交> --job <任务> [--args "…"] [--name <名>]`，跑完图片和录像自动下载到本机 `<主仓库>/Claude outputs/render-<名>/`。
3. 实跑过一次斯卡蒂分支 `claude/pixelfx-plane-skadi`（3108c1778）：三栏对比、三档并排、8:00 开 / 关 mp4 全部拿回（23 个文件、69 MB），全程 48 分钟，约 0.07 美元；同局 TRACE 499 行、`fx/px_plane` 0 / 1 TRACE 301 行，都逐行一致，与 docs/246 §6 本机结果相同。

## 1. 怎么用

```
python tools/gcp_render.py --branch claude/pixelfx-plane-skadi --job pxplane --name skadi
python tools/gcp_render.py --branch claude/pixelfx-plane-skadi --job trace_ab --args 'cases=skadi:23:300,mizuki:11:300'
python tools/gcp_render.py --branch HEAD --job custom --cmd 'python3 tools/pxplane_shots.py demo --modes 3 --out $MEDIA'
```

- `--branch`：本机分支、origin 上的分支或提交号都可以。提交不在 origin 上时，batch.py 会自动传 bundle，所以本机还没推的提交也能跑。
- `--name`：结果名，缺省为「任务-提交前 8 位」。`--out cloud-results/render-<名>` 的写法也认。
- `--machine`：缺省 `e2-standard-8` 抢占式。GCP 配额一共 12 核，所以同时最多一台 8 核 + 一台 4 核。
- `--hours`：缺省 2，到点 GCE 强制删机。
- `--dry`：只打印要下发到虚拟机的整段命令，不开机。

## 2. 现成任务（`tools/gcp/render_jobs/`）

| 任务 | 做什么 | 参数（`--args`） | 产物 |
|---|---|---|---|
| `pxplane` | 被测提交里的 `tools/pxplane_shots.py`（docs/246）：`demo` 三栏对比 + 2 倍局部 + 三档并排；`rec` 同种子 8:00 起 20 秒左关右开 mp4，并逐行比同局 TRACE；`trace` 比较 `fx/px_plane` 0 / 1 / 2 | 分号隔开的子命令，缺省 `demo;rec --seed 11 --from 480 --secs 20;trace --seed 23 --maxt 300 --extra "--elite2 --sptest"` | `cmp_*.png`、`cmp_*_x2.png`、`tiers_*.png`、`late_8m00_onoff.mp4`；TRACE 结果在 `pxplane_rec.log` / `pxplane_trace.log` |
| `trace_ab` | 同种子 TRACE 开 / 关对比，同一提交 A / B 两组，多局并行 | `cases=队长:种子:秒数,…`、`a="--bal=…"`、`b="--bal=…"`、`extra="…"`、`windowed=1`（画画面跑；缺省 `--headless` 更快） | `trace_ab.md`（行数、是否逐行一致、第一处差异）+ `trace/*.txt`；有差异时退出码 1 |
| `custom` | `--cmd` 里写的命令 | — | PNG / MP4 写到 `$MEDIA` |

星熊、流明等新分支：把自己的出图脚本做成 `pxplane_shots.py` 的样子，即 Godot 只经 `godot_runner.run_godot` 启动，输出目录取 `--out`。然后用 `custom` 调它，或照 `pxplane.sh` 加一个任务文件。

任务脚本、准备段和辅助 Python 都总用本机这份，经虚拟机 metadata 下发，不从被测提交里读，所以老分支也能用新工具。

## 3. 虚拟机上做了什么（`tools/gcp/render_prep.sh`）

1. checkout 指定提交，然后跑 `setup_linux.sh`：装 Godot 4.7.2 并导入项目。
2. 装 xvfb、Mesa 软件 OpenGL、X11 运行库、中文字体 `fonts-noto-cjk`，以及 `imageio-ffmpeg`、numpy、pillow。
3. **生成不进 git 的本地文件**：用 `python3 tools/asset_index.py` 写 `game/art/index.json`（斯卡蒂那次 2158 项）。少了它，新帧条加载不到，会静默回退旧画面。
4. `GODOT` 换成包装脚本 `/usr/local/bin/godot-gl`，一律带 `--rendering-driver opengl3`（虚拟机没有 GPU）。Xvfb 虚拟屏 `:99` 为 1920×1080×24。
5. 写死 Windows 字体路径的脚本（如 `C:/Windows/Fonts/msyh.ttc`）：在仓库根建同名相对路径，链到 Noto CJK。
6. 任务把 PNG / MP4 写到 `$MEDIA`（= `$OUT/media`）。跑完后 `vm_startup.sh` 把 `$MEDIA` 传到 Cloud Storage `gs://<项目>-batch/render-<名>/media/`（7 天自动删）；日志、报告、`media_manifest.txt` 照旧推 `cloud-results/render-<名>` 分支。

## 4. 产物放在哪；原作一栏

- **本机**：`<主仓库>/Claude outputs/render-<名>/`。gcp_render 跑完自动下载，审片、发用户都从这里取。
- **结果分支** `cloud-results/render-<名>`：放 `build/cloud/render-<名>/` 下的日志、报告和文件清单。媒体合计 ≤ 20 MB（`--git-mb`）时也一起提交进分支的 `media/`，超过的只在本机和桶里。原因是 mp4 动辄几十 MB，进 git 会让仓库永久变大。
- **原作参照图不上 GCP**：它只在本机 build/ 下，不进 git、不进包。要「原作 / 当前 / 新版」三栏时，虚拟机只出后两栏；本机会话下载后，用自己的拼图脚本（PIL）把原作一栏贴在左边。拼图不开 Godot，本机可以跑。

## 5. 实测耗时（斯卡蒂，e2-standard-8 抢占式，软件 OpenGL）

| 段 | 时长 |
|---|---|
| 开机 + 拉提交 + 装环境 + 导入 | 约 3 分钟 |
| `demo`（27 局演示连拍 + 拼图） | 26 分钟 |
| `rec`（两局到 8:00 + 20 秒实时录制 + 合成 mp4） | 14 分钟 |
| `trace`（两局 5:00） | 3 分钟 |
| 下载 69 MB | 1 分钟 |
| 合计 | 48 分钟，约 0.07 美元 |
| `trace_ab` 单独两局（e2-standard-4） | 5 分钟 |

`pxplane_shots.py` 是串行的（照本机一次只开 1 个 Godot 写的），在 8 核机上还有提速空间：脚本自己用线程池并行跑 demo 各局即可。

## 6. 注意

- 软件渲染与本机显卡渲染逐像素不会完全相同，但构图、颜色、像素格一致。斯卡蒂三栏与 docs/246 本机图肉眼看不出区别。
- `rec` 用 `--fixed-fps 30 --realtime`。虚拟机跑不满实时也不丢帧（按帧号存图），mp4 仍是 30 帧原速。
- 抢占式机器被回收时，batch.py 自动改用标准机重跑一次。中途断了可以 `python tools/gcp/batch.py collect render-<名>` 收结果，再用 `gcloud storage cp -r gs://<项目>-batch/render-<名>/media/* <本机目录>` 取媒体。
