# 网页包再压缩评估（10-28）

用户 10-28：「看看网页版还能不能再压缩大小」。源码 `claude/integ-1028b` @ 5b74424f6，`python tools/export_web.py --toy`（音频 B 档）。
约束：不删曲目 / 分层、不改声道、不降画面（干员保持高清）、网页 / 移动端先压内存峰值。

## 1. 总量

| | 改前 | 第一轮（字体 + WebP 档） | **现在（+ wasm LZMA + 关渗色）** |
|---|---:|---:|---:|
| 网页目录总大小 | 41.62 MiB | 40.86 MiB | **36.10 MiB** |
| Toy zip（上限 50 MB） | 43.39 MB | 42.59 MB | **37.60 MB** |
| index.pck（原始 / 分片后） | 35.47 / 31.66 MiB | 34.67 / 30.90 | 33.09 / 29.30 |
| index.wasm（原始 / 分片后） | 37.68 / 9.59 MiB（gzip） | 同左 | 37.68 / **6.42 MiB（LZMA）** |

离 50 MB 还有约 12 MB 余量。

## 2. 按类别（pck 内条目压缩后 MiB；wasm 单列）

| 类别 | 条目 | 改前 | 现在 |
|---|---:|---:|---:|
| 引擎 wasm | 1 | 9.59 | 6.42 |
| 音乐（23 个 Suno 分层 + 局外曲，B 档） | 23 | 16.82 | 16.82 |
| 脚本（.gdc，已是 zstd 压缩的二进制令牌） | 207 | 3.26 | 3.26 |
| 音效（QOA） | 178 | 2.08 | 2.08 |
| 干员帧条 | 335 | 2.49 | 1.71 |
| 语音 | 123 | 1.47 | 1.47 |
| 字体（已子集化） | 3 | 1.37 | 1.00 |
| 特效与弹体图 | 279 | 1.51 | 0.98 |
| 怪物与 Boss 图 | 421 | 1.46 | 0.86 |
| 事件插画（网页版 webp） | 17 | 0.85 | 0.82 |
| 数据 / 场景 / 其它 | 2082 | 0.63 | 0.63 |
| 其它贴图 + 图标道具 | 431 | 0.33 | 0.29 |

音频合计约 20.4 MiB（占一半多），wasm 6.4，贴图约 4.7，脚本 3.3。

## 3. 已做（无损，`export_web.py` 缺省开，`--no-lossless` 关；只改打包副本，仓库源文件与桌面包不动）

| 项 | 省 | 影响 |
|---|---:|---|
| 子集字体转 WOFF2 容器（文件名不变，FreeType 按文件头识别） | 0.37 MiB | 字形 / 度量不变：Godot 里同串测宽一致；无窗口 Edge 标题页文字区与改前逐像素一致。内存：运行时 FreeType 解出原 TTF，比改前多留一份 WOFF2 字节，约 +1 MiB |
| 贴图 WebP 无损压缩力度 方法 2 / 系数 25 → 6 / 100（打包副本 project.godot） | 0.39 MiB | 仍是无损 WebP，像素不变；解码速度不变；导出时导入多约 1–2 分钟 |
| wasm 分片 gzip → LZMA（§5，`--wasm-gzip` 退回） | 3.17 MiB | 无损；加载时 JS 解码，桌面约 1 秒、手机估 3–4 秒；峰值内存不变 |
| art/incoming 关透明边渗色（§6，带淡像素的 40 张保留；随 `--no-lossless` 一起关） | 约 1.2 MiB | 所有可见像素逐像素一致 |

验证：`tools/test_web_boot.cjs`（无窗口 Edge）改前 / 改后都通过，加载进度单调、无脚本错误。

## 4. 待定 / 不做（10-28 协调人定）

| 项 | 能省 | 结论 |
|---|---:|---|
| 配乐 / 语音 C 档（22.05 kHz / 质量 1.0；语音 22.05 kHz / 0.9） | 2.2 MiB | 有损，等用户；要出试听 mp4 |
| 音效降到 22.05 kHz（导入 max_rate） | 约 1.0 MiB（估） | 有损（打击 / 金属类发闷），等用户 |
| 自编精简引擎模板 | 约 3 MiB（估） | 不做（用户 10-26 定不做网页自编模板） |
| 脚本改未压缩令牌 + 外层压缩 | < 0.3 MiB（估） | 收益小，不做 |

不建议：降贴图分辨率 / 有损 WebP（降画面）；语音按需下载（Toy 50 MB 按总量算，docs/121 §5）；敌人 @2x 存 1 倍图再放大（实测只省约 0.4 MiB，还要改 art.gd 读图路径）。


## 5. wasm 分片改 LZMA（协调人批「Brotli 分片」，改用 LZMA 实现）

- 为什么不是 Brotli：浏览器 DecompressionStream 不普遍支持 brotli，要内嵌第三方解码器（本机没有，需联网取 google/brotli，且要带 122 KB 静态字典）。
  LZMA 同样无损、压得更小（整块实测 brotli 6.58 / xz 6.34 MiB），解码器只有约 120 行，**本作自写**（`tools/web/lzma_dec.js`，按 LZMA 公开规格），无第三方代码、无许可证要附。
- 只压 wasm：pck 大头是 OGG / WebP，LZMA 只比 gzip 少约 0.5 MiB，却要在 JS 里逐字节解 35 MiB；pck 仍走 gzip + 浏览器原生解压。
- `export_web.py`：wasm 20 MiB 一片（压后约 3.3 MiB / 片），`.lzma` alone 格式（lc3 lp0 pb0，preset 9e），写完逐片回读校验；清单加 `"enc": "lzma"`。itch 包分片名 `index.wasm.NN.lzma`，Toy 包仍 `index.NN.wasm`。`--wasm-gzip` 退回旧做法。
- 加载器（`loader.js`）：清单标 lzma 的片收齐压缩字节后 `syLzmaDecode` **直接解进整块 wasm 的对应区间**（整块本身当滑动窗口，不另分配字典），峰值内存 = 压缩字节（约 3 MiB）+ 本来就有的整块，与 gzip 路径相同。
  若该片以 1f 8b 开头（某台服务器把它当 gzip 处理）仍走 gzip 解压；解码出错按原有逻辑重试该片。没有备用 gzip 版本（同时带两份就白压了）。
- 速度：node（V8）解两片共 37.7 MiB 约 1.0 秒；手机估计 3–4 秒，在主线程（加载页扫描动画是 CSS，照转）。用户已定不崩溃优先于加载速度。
- 验证：`python tools/test_web_lzma.py`（8 例：随机 / 长重复 / 混合 / 真 index.html，两组参数，逐字节一致）；真 wasm 两片逐字节一致；`node tools/test_web_loader.cjs` 通过。

## 6. 关透明边渗色（fix_alpha_border）

- 做法：打包副本的 project.godot 加 `[importer_defaults] texture={"process/fix_alpha_border": false}`。只影响没有 .import 的贴图，也就是拷进来的 art/incoming；其余 88 个贴图的 .import 都显式写着 true，不变。
- 发现：Godot 的渗色改的是 **alpha < 20** 的像素，不只全透明。全关时 33 张特效（`fx_kp_*`、`fx_hh_beams@2x`、`fx_felspell`、`fx_logos_s2`）的淡像素（alpha 1–19）颜色变了，屏幕贡献最多 12/255。
  所以：含 alpha 1–19 像素的贴图（40 张）单独写 .import 保留渗色，其余关。
- 贴图级逐像素对照（同一份源、开 / 关渗色两次导入，解出 1482 张）：**所有 alpha > 0 的像素 RGBA 完全一致**，alpha 通道完全一致；127 张逐字节相同，1355 张只在全透明像素的 RGB 上不同。
- 画面不受全透明像素 RGB 影响的依据（代码审计）：art/incoming 贴图全走最近邻过滤（项目缺省 nearest；线性过滤只用在前景虚化剪影 = 运行时由 alpha 生成的图、启动 / 标题标志 = art/ui 有自己的 .import）；canvas 混合下 alpha 0 的像素不贡献颜色；
  读像素颜色的 GDScript（fx_grains、optical_particles、world、vfx、art 法线 / 白剪影、look）都先判 alpha 或乘 alpha；角色着色器 actor_light 邻域只读 alpha。
- 同种子截图对照没做成：Godot 按规矩只能 --headless（不出画面），网页正式包又不能传种子 / 开发参数，两次网页运行的寻访结果与时间各不相同，整屏截图逐像素比没有意义。上面的贴图级比对 + 审计等价地说明屏幕输出不变。
- 浏览器冒烟（无窗口 Edge，最终包 build/toy/web3）：`test_web_boot.cjs` 通过；脚本点击 标题 → 寻访十连 → 结果 → 跳过引导 → 选人 → 难度 → 进局 15 秒（移动、4 击杀）→ 暂停，全程无脚本错误。结算页没走到（要打完或阵亡一局）。
- 省：贴图合计 ctex 6.89 → 5.31 MiB（约 1.6 MiB）。
