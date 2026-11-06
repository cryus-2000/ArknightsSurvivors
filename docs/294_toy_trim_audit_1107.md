# 294 · Toy 网页包「白占地方」盘点（11-07）

状态：**盘点结论，待用户审；没删任何东西**。来源：用户「看看 toy 包里有没有一些没有用的东西可以删掉的」。包：main 9ce91dd8d 的 Toy 导出（`build/websize_9ce91dd8d`，zip 52.14 MB，线 50 MB）。
方法：`tools/web_pck_report.py` 拆 pck（11 090 条，zlib 估算 44.58 MiB + wasm 6.7）；对每一类做**静态引用核对**（含动态拼名规则）、**逐字节哈希查重**、**按元数据键对帧条查孤儿**。

## 0. 结论（先说不好听的）

1. **包里几乎没有「死文件」**。这个包已经被 10-28 / 10-31 / 11-02 / 11-06 几轮整理过，剩下的素材都能在代码或数据里找到引用（多数是拼名加载）。
2. **能干净省掉的只有约 0.3–0.4 MiB**（开发用脚本 + 缺省关的配方路线 + 几条小项），而且大头（0.29 MiB）要先把 `game.gd` 对 `autotest` 等的静态 `preload` 拆掉，不是改个排除表就行。
3. 想从 52.14 MB 降到 50 MB 以下（要省约 2.2 MB zip），**盘点出来的无用物远远不够**，必须靠 docs/285 §3 的有损项（配乐降档、斯卡蒂大图集、字体 / 语音取舍）。帧率会话正在做的最终 Boss 配乐降档（≈ −2.4 MiB）本身就刚好够，把这份盘点的 0.3–0.4 当作余量。
4. 我没有在 GCP 上做全局「运行时加载追踪」。动态拼名的素材（pxp 方向变体、op_/ult_ 音效、语音池）静态上都有引用；要证明「某张图一局也不会加载」只能靠运行时追踪，覆盖不全的话有误删风险，所以**不建议靠它删**（见 §3）。

## 1. 逐类核对

| 类别（pck 内压缩后） | 核对方法 | 结果 | 能省 |
|---|---|---|---:|
| **转平面 pxp 帧条** 2675 张 7.26 MiB | ① 对每份 `pxp_*.json` 的键拼出应有文件名（含负方向 `_d-` → `_dm`），与磁盘对照；② 看 `fx_pxplane*.gd` 里直接拼路径的加载 | 每个元数据键都有文件；没有元数据键的 51 个文件（`ul_orcam_*` 26、`ka_rima/rimb_op_mon3tr_*` 24、`ult_ir_seal` 1）都是代码里直接拼路径加载（`fx_pxplane_ul.gd:736`、`fx_pxplane_kal.gd:52`、`ult_px_ir.gd:315`）→ **都在用**。旧做法对照 `*_raw*` 11-06 已经不进包（docs/285 §9） | 0 |
| **配乐** 25 首 16.72 MiB | 逐首查 `sfx.gd` / `suno_layers.json` 引用 | 全部在用（最终 Boss 8 首降档另有会话在做） | 0 |
| **语音** 237 条 2.65 MiB | 与 `voice_pools.json` 对照 | 237 条里 12 条不在池里（0.22 MB 原始），其中 9 条是 `<id>_battle` / `<id>_ult` 一类按名字拼接加载的，**只有 3 条没有任何引用**：`exusiai_syn_team`、`lappland_syn_rival`、`wisadel_w_laugh` | ≈ 0.05 |
| **干员专属音效** 112 条 | 对 `sfx.gd` 的 `OP_SFX` 表 + `OP_ROT` + 拼名（`melee_impact.gd` 的 `op_<id>_flesh_<n>`、`seg_texas.gd` 的 `op_texas_s3_cut_<n>`） | 全部有加载路径，没有死文件 | 0 |
| **终结技音效** 177 条 1.48 MiB | 11-02 已把没选中的超必杀提示音删出包（只留 `ult_super_5`） | 无新增死文件 | 0 |
| **字体** 8 个 2.02 MiB | 逐个看加载处：`ui.ttf`（基础）、`ui_regular.ttf`（桌面正文，`settings.gd:398`）、`ui_heavy.ttf`（名字 / 标题，`ui.gd:94`）、`ui_phone.ttf`（触屏）、`serif.ttf`、`ui_fallback.otf`、`montserrat_bold/semibold` | 都有加载处；`ui_regular` 只桌面用、`ui_phone` 只触屏用，但网页包两种设备都要服务，**不能按设备拆** | 0 |
| **贴图**（非 pxp）1881 张 6.29 MiB | 动态 / 静态引用核对（`tools/asset_unref_scan.py`） + 前 30 大逐张查（`bg_src`、`fx_wd_cannon*`、`fx_nest_aura_big`、`fx_skalter_wave_big_dim`、`ritual`…） | 全部有引用 | 0 |
| **重复内容**（逐字节哈希）ctex / ogg / sample / 字体 | 对 pck 里所有 ≥ 2 KB 的二进制条目算 MD5 | 只有 15 组重复，合计 **0.05 MiB**（如 `op_specter_unchained_death` = `_fall`、`pxp_swell_e0/e1/e2_gd`）；合并要改读图代码，不值 | ≈ 0.05（不建议） |
| **JSON 数据** 93 个 0.90 MiB（原始 5.45 MB） | 去掉 `_` 开头的说明字段（219 种键，脚本里只读 `_doc`、`_fb` 两个）+ 压成单行 | zlib 后 0.85 → 0.78 MiB | ≈ 0.07 |
| **`.png.import` / `.import` 文本** 4533 + 676 条 0.89 MiB | 每条含 32 位哈希 ×2 与 uid，几乎不可压；引擎靠它定位 `.godot/imported/*.ctex` | 运行时必需 | 0 |
| **脚本** 279 个 4.99 MiB | 按名字挑开发 / 测试 / 缺省关的脚本，再查谁引用它们 | 见 §2：约 0.29 MiB 是开发 / 缺省关代码，但被静态 `preload` 绑住 | ≈ 0.29（要先改代码） |
| 其它（shader、uid_cache、scn） | — | 全部运行时必需 | 0 |

## 2. 可以不进包的（按把握排序）

| # | 项 | 大小（pck 内） | 为什么没用 | 证据 | 建议 | 前提 |
|---|---|---:|---|---|---|---|
| 1 | 开发 / 测试脚本 `autotest`（82 KB）、`ak_mock`（76 KB）、`bot`（24 KB）、`boss_bench`（14 KB）、`motion_shot`（12 KB）、`perf_report`（12 KB）、`frame_rec`（9 KB）、`ult_bench`（8 KB）、`outwin_probe`（2 KB） | **≈ 0.24 MiB** | 只在开发参数（`--balance` / `--autotest` / `--bossbench` …）下用，发布版读不到开发参数（`Cfg.dev_args()` 守卫） | `game.gd:64–69` 静态 `const … = preload(…)`；`autotest.gd:64`、`autotest.gd:1556` 又静态 `preload` 了 `outwin_probe`、`ak_mock` | **不进包**，但要先把 `game.gd` 里这几条 `preload` 改成运行时 `load()` + 开发版守卫（code-cleanup 会话，约 20 行） | 需改代码；改完跑 `check_release` + 全快检 |
| 2 | 缺省关的特效配方路线 `fx_recipe.gd`（54 KB）+ `data/fx_recipes/*.json`（16 KB） | ≈ 0.04 MiB | `fx/recipe` 缺省 0，11-05 用户叫停，被转平面路线取代（docs/245 文首已标「已被取代」） | `balance.json` `fx/recipe: 0`；`ob_fx.gd:46`、`op_api.gd:9` 静态 `preload` | 同上先改成运行时 `load()`；或干脆整条路线从仓库删（先问用户是否彻底放弃） | 需改代码 / 要用户定 |
| 3 | 3 条无引用语音（`exusiai_syn_team`、`lappland_syn_rival`、`wisadel_w_laugh`） | ≈ 0.05 MiB | 池里没有，代码里没有 | §1 语音行 | 可以删，但它们是 PRTS 原作台词素材（docs/160 §9.3 当年新切的两条），删前问用户 | 要用户定 |
| 4 | JSON 去说明字段 + 压成单行（只改打包副本） | ≈ 0.07 MiB | `_doc` 之类设计说明在发布版没有读者 | 脚本里只读 `_doc`、`_fb` 两个下划线键 | 可以做，写进 `export_web.py`（同字体子集的做法） | 低风险，收益太小 |

合计：**约 0.3–0.4 MiB**（不含 §1 里「不建议」的合并重复）。

## 3. 为什么没有做运行时追踪

- 素材加载基本都是拼名（`pxp_` + 干员缩写 + 键 + 方向后缀、`op_<id>_<kind>`、`ult_<id>_…`、`<id>_<kind>_<n>` 语音池）。静态核对已经把拼名规则都对上了，**没有发现无引用文件**。
- 想靠「跑一遍看哪些没加载过」来找死文件，需要全员入队 + 全招式 + 全 Boss + 各结局都覆盖到；覆盖不全就会把罕见路径的素材误判成无用。这件事的风险大于收益（本盘点里能省的上限就 0.3–0.4 MiB）。
- 如果用户仍然想要，我可以在 GCP 上做：窗口局 + `--verbose`（引擎打印每次 `Loading resource`）+ 图鉴「全招式演示」全跑，汇总被加载过的路径；删之前只当「候选」，再对每个候选人工看一眼。

## 4. 建议

1. **不要指望靠清理死文件把 Toy 包压进 50 MB**：盘点后能省 0.3–0.4 MiB，≈ 0.4 MB zip。
2. 52.14 MB → ≤ 50 MB 需要省约 2.2 MB zip：用帧率会话正在做的最终 Boss 8 首配乐降档（≈ −2.4 MiB）就够；再叠 docs/285 §3.1 的斯卡蒂大图集减方向（−0.9）当余量。
3. 开发脚本不进包（§2 #1）值得做，因为它顺带让发布包少带一堆不该出现的代码；但要由 code-cleanup 会话改 `preload`，我这边没动。
4. 以后每交一批 pixelfx 帧条 / 终结技都会再涨（本批 +8.5 MiB 就是这么来的），建议给 pxp 帧条定总体积预算（docs/285 §7 第 4 条，还没定）。

## 5. 复现

```bash
python tools/web_pck_report.py build/websize_9ce91dd8d   # 先把 index.NN.pck 复制改名成 index.pck.NN.gz 目录（Toy 分片名不同）
```

重复内容、拼名核对的脚本都是一次性的，逻辑见 §1 方法一栏。
