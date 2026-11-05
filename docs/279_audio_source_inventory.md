# 279 音频来源清单（11-05，备查）

> 用户 11-05：「原作的音源没问题，我问过了可以用」。本页只记来源、不标「需替换」。原标题：方舟幸存者 音频来源盘点（integ-1101 工作树，claude/integ-1105 @ 36b8c52fb；对照 origin/main 10209a8b6）


**结论摘要**

- 游戏内音频文件共 **620** 个（game/audio 下 .wav / .ogg；另有 4 个元数据文件 voice_manifest.json、voice_pools.json、voice/README.md、music/suno_layers.json 不计）：sfx 356、voice 237、music 27。
- **A 原作客户端 336**（其中音效 99：能天使普攻 / 倾泻 4 个 + 终结技 95 个；干员语音 237：原作中文语音，经第三方 Ark-Voice 仓库取得）；**B 授权录音 83**；**C 程序合成 178**；**D 待查 1**（商人曲 shop.ogg）；另有 **E 不属 A/B/C 的已知来源 22**（Suno AI 生成配乐）。
- integ 与 main **一致**：`git diff --name-only origin/main HEAD -- game/audio` 只有 .import 差异、没有音频文件差异；两边音频文件清单相同（各 624 个含元数据）。流明 op_lumen_atk / op_lumen_hit 的原作剪辑版（e2cc16f93）在两边都已被 0d0517382 退回，现版 blob 分别 = 4e648a32e 合成版 / b3d466a19 去叮合成版。
- 注意：`game/data/credits.json`「音乐与音效」一栏写「配乐与大部分音效由 AI 程序化合成…不含原声音频」，**没有提到 A 类原作音效（99 个）和 Suno 配乐**；语音一栏有 Ark-Voice 声明。

判定办法：终结技文件按写入提交时的 `game/tools/gen_sfx_ult_seg_1030.py` 逐人核对（每人函数在写入提交与现版的槽位表达式一致；德克萨斯 / 能天使的 sf 走 FLASH 合成；df767fd5c 的 ①/② 两版取写进游戏的缺省 ①，e51b5a751 定稿未改这些文件），读 `akd()`（主仓库 build/ak_src/flat 或 build/ak_exu_candidates，原作客户端热更新 26-10-22-14-02-11-51447808 导出）记 A，读 `lib()/sn()`（build/sfx_lib/sonniss_gdc2026）或 `fsd()`（Freesound CC0）记 B，纯函数合成记 C。混合文件只要含原作层就记 A，原作源名列中括号注明叠加的录音层。

## 表 1　A 类：原作客户端来源

### 1a　音效（99）

| 文件 | 原作源名 | 依据 | 用在哪里 |
|---|---|---|---|
| `sfx/op_exusiai_atk.wav` | p_atk_handgun_n（原作 Q 套） | gen_sfx_exu5_1026.py --apply Q；221397e14；docs/113_exusiai*.md §19.x | game/scripts/sfx.gd:33 OP_SFX["exusiai"]、:52 OP_ROT；characters/blocks/seg_exusiai.gd:313 o._sfx_op("atk") |
| `sfx/op_exusiai_atk_b.wav` | p_atk_handgun_s | 同上 | game/scripts/sfx.gd:33、:52 OP_ROT 轮换（seg_exusiai.gd:313 出手时轮到） |
| `sfx/op_exusiai_atk_c.wav` | p_atk_handgun_h | 同上 | game/scripts/sfx.gd:33、:52 OP_ROT 轮换（seg_exusiai.gd:313 出手时轮到） |
| `sfx/op_exusiai_big.wav` | p_atk_handgun_s（Q 套 big 末尾重击 + 3 声 atk_b 轻弹重拼） | gen_sfx_exu_sync_1028.py new_big() 读 1b64c476f（= 221397e14 Q 版）；cc9d28848 | game/scripts/sfx.gd:33、:45 OP_DB、:47 OP_GAP；characters/blocks/seg_exusiai.gd:215 o._sfx_op("big") |
| `sfx/ult_exusiai_cast.wav` | p_atk_pistolup_dreload | gen_sfx_ult_seg_1030.py exusiai() akd()；6a3695c76；docs/113 §20 | game/scripts/run/ult.gd:595 _ua("cast") |
| `sfx/ult_exusiai_charge.wav` | p_atk_pistolup_sreload | gen_sfx_ult_seg_1030.py exusiai() akd()；6a3695c76；docs/113 §20 | game/scripts/run/ult.gd:506 _ua("charge") |
| `sfx/ult_gladiia_cast.wav` | p_skill_seasummon | gen_sfx_ult_seg_1030.py gladiia() akd()；2fc201977；docs/113 §20 | game/scripts/run/ult.gd:595 _ua("cast") |
| `sfx/ult_gladiia_crush.wav` | p_skill_bigwatercannon | gen_sfx_ult_seg_1030.py gladiia() akd()；2fc201977；docs/113 §20 | game/data/ult_audio.json:23 ops.gladiia.seg.收拢.on（ult.gd:2007/2011 分段） |
| `sfx/ult_gladiia_loop.wav` | p_skill_tidesurging_1 | gen_sfx_ult_seg_1030.py gladiia() akd()；2fc201977；docs/113 §20 | game/data/ult_audio.json:23 ops.gladiia.fx.strip:fx_gladiia_tornado_loop.slot（ult.gd:2075 画面单元） |
| `sfx/ult_gladiia_open.wav` | p_skill_seasummon | gen_sfx_ult_seg_1030.py gladiia() akd()；2fc201977；docs/113 §20 | game/data/ult_audio.json:23 ops.gladiia.fx.strip:fx_gladiia_tornado_open.slot（ult.gd:2075 画面单元） |
| `sfx/ult_gladiia_sf.wav` | p_skill_bigwatercannon | gen_sfx_ult_seg_1030.py gladiia() akd()；2fc201977；docs/113 §20 | game/scripts/run/ult.gd:2197（ult_%s_sf 超必杀暂停提示） |
| `sfx/ult_gladiia_surge.wav` | p_skill_bigwatercannon + p_skill_tidesurging（叠 Sonniss Booms_Vol2_214） | gen_sfx_ult_seg_1030.py gladiia() akd()；2fc201977；docs/113 §20 | game/data/ult_audio.json:23 ops.gladiia.hf_slot（ult.gd:1492 冲击帧）；game/data/ult_audio.json:23 ops.gladiia.fx.strip:fx_skadi_surge.slot（ult.gd:2075 画面单元） |
| `sfx/ult_gladiia_swirl_1.wav` | p_skill_waterbubble | gen_sfx_ult_seg_1030.py gladiia() akd()；2fc201977；docs/113 §20 | game/data/ult_audio.json:23 ops.gladiia.fx.ring.slot（ult.gd:2075 画面单元） |
| `sfx/ult_gladiia_swirl_2.wav` | p_skill_waterbubble | gen_sfx_ult_seg_1030.py gladiia() akd()；2fc201977；docs/113 §20 | game/data/ult_audio.json:23 ops.gladiia.fx.ring.slot（ult.gd:2075 画面单元） |
| `sfx/ult_gladiia_swirl_3.wav` | p_skill_waterbubble | gen_sfx_ult_seg_1030.py gladiia() akd()；2fc201977；docs/113 §20 | game/data/ult_audio.json:23 ops.gladiia.fx.ring.slot（ult.gd:2075 画面单元） |
| `sfx/ult_hoshiguma_boom.wav` | p_skill_fireboomexplo + p_skill_robotexplo（叠 Sonniss Impact Cut Sweep / Booms_Vol2_214 / 冰裂） | gen_sfx_ult_seg_1030.py hoshiguma() akd()；e51b5a751；docs/113 §20 | game/data/ult_audio.json:61 ops.hoshiguma.hf_slot（ult.gd:1492 冲击帧）；game/data/ult_audio.json:61 ops.hoshiguma.fx.blade+v.slot（ult.gd:2075 画面单元） |
| `sfx/ult_irene_seal.wav` | p_skill_copperseal（叠 Sonniss 金属重击共鸣） | gen_sfx_ult_seg_1030.py irene() akd()；b50ca496a；docs/113 §20 | game/data/ult_audio.json:70 ops.irene.fx.strip:fx_irv_seal.slot（ult.gd:2075 画面单元） |
| `sfx/ult_irene_sf.wav` | p_skill_lightsword | gen_sfx_ult_seg_1030.py irene() akd()；b50ca496a；docs/113 §20 | game/scripts/run/ult.gd:2197（ult_%s_sf 超必杀暂停提示） |
| `sfx/ult_kaltsit_impact.wav` | p_skill_Mon3trburst（前段，叠 Sonniss Booms_Vol2_075） | gen_sfx_ult_seg_1030.py kaltsit() akd()；04402c51e；docs/113 §20 | game/scripts/run/ult.gd:1851 / 2488 _ua("impact") |
| `sfx/ult_kaltsit_land.wav` | p_skill_shieldhitground | gen_sfx_ult_seg_1030.py kaltsit() akd()；04402c51e；docs/113 §20 | game/data/ult_audio.json:16 ops.kaltsit.fx.strip:fx_ult_kaltsit_melt_front.slot（ult.gd:2075 画面单元） |
| `sfx/ult_kaltsit_ring_hit.wav` | p_skill_Mon3trburst（后段） | gen_sfx_ult_seg_1030.py kaltsit() akd()；04402c51e；docs/113 §20 | game/data/ult_audio.json:16 ops.kaltsit.seg.熔毁.hit（ult.gd:2007/2011 分段） |
| `sfx/ult_lappland_air.wav` | p_skill_MHshieldaxe_ground（叠 Sonniss Woosh Debris） | gen_sfx_ult_seg_1030.py lappland() akd()；df767fd5c；docs/113 §20 | game/data/ult_audio.json:72 ops.lappland.fx.ring.slot（ult.gd:2075 画面单元） |
| `sfx/ult_lappland_cast.wav` | p_skill_MHdualswords_on | gen_sfx_ult_seg_1030.py lappland() akd()；df767fd5c；docs/113 §20 | game/scripts/run/ult.gd:595 _ua("cast") |
| `sfx/ult_lappland_final.wav` | p_skill_reticentsword_h + p_skill_MHdualswords_on（叠 Sonniss Booms_Vol2_075） | gen_sfx_ult_seg_1030.py lappland() akd()；df767fd5c；docs/113 §20 | game/data/ult_audio.json:72 ops.lappland.hf_slot（ult.gd:1492 冲击帧） |
| `sfx/ult_lappland_impact.wav` | p_skill_arccutting | gen_sfx_ult_seg_1030.py lappland() akd()；df767fd5c；docs/113 §20 | game/scripts/run/ult.gd:1851 / 2488 _ua("impact") |
| `sfx/ult_lappland_sf.wav` | p_skill_arccutting | gen_sfx_ult_seg_1030.py lappland() akd()；df767fd5c；docs/113 §20 | game/scripts/run/ult.gd:2197（ult_%s_sf 超必杀暂停提示） |
| `sfx/ult_lappland_slash_1.wav` | p_skill_arccutting | gen_sfx_ult_seg_1030.py lappland() akd()；df767fd5c；docs/113 §20 | game/data/ult_audio.json:72 ops.lappland.fx.strip:fx_ir_slash1+v.slot（ult.gd:2075 画面单元）；game/data/ult_audio.json:72 ops.lappland.fx.strip:fx_ir_slash2+v.slot（ult.gd:2075 画面单元）；game/data/ult_audio.json:72 ops.lappland.fx.strip:fx_ir_slash3+v.slot（ult.gd:2075 画面单元） |
| `sfx/ult_lappland_slash_2.wav` | p_skill_arccutting | gen_sfx_ult_seg_1030.py lappland() akd()；df767fd5c；docs/113 §20 | game/data/ult_audio.json:72 ops.lappland.fx.strip:fx_ir_slash1+v.slot（ult.gd:2075 画面单元）；game/data/ult_audio.json:72 ops.lappland.fx.strip:fx_ir_slash2+v.slot（ult.gd:2075 画面单元）；game/data/ult_audio.json:72 ops.lappland.fx.strip:fx_ir_slash3+v.slot（ult.gd:2075 画面单元） |
| `sfx/ult_lappland_slash_3.wav` | p_skill_arccutting | gen_sfx_ult_seg_1030.py lappland() akd()；df767fd5c；docs/113 §20 | game/data/ult_audio.json:72 ops.lappland.fx.strip:fx_ir_slash1+v.slot（ult.gd:2075 画面单元）；game/data/ult_audio.json:72 ops.lappland.fx.strip:fx_ir_slash2+v.slot（ult.gd:2075 画面单元）；game/data/ult_audio.json:72 ops.lappland.fx.strip:fx_ir_slash3+v.slot（ult.gd:2075 画面单元） |
| `sfx/ult_lappland_slash_4.wav` | p_skill_arccutting | gen_sfx_ult_seg_1030.py lappland() akd()；df767fd5c；docs/113 §20 | game/data/ult_audio.json:72 ops.lappland.fx.strip:fx_ir_slash1+v.slot（ult.gd:2075 画面单元）；game/data/ult_audio.json:72 ops.lappland.fx.strip:fx_ir_slash2+v.slot（ult.gd:2075 画面单元）；game/data/ult_audio.json:72 ops.lappland.fx.strip:fx_ir_slash3+v.slot（ult.gd:2075 画面单元） |
| `sfx/ult_logos_impact.wav` | p_skill_darkholespell（叠 Sonniss 电光 / Booms_Vol2_214 / 风冲） | gen_sfx_ult_seg_1030.py logos() akd()；519b22240；docs/113 §20 | game/scripts/run/ult.gd:1851 / 2488 _ua("impact") |
| `sfx/ult_lumen_cast.wav` | p_skill_lantern_cast | gen_sfx_ult_seg_1030.py lumen() akd()；2fc201977；docs/113 §20 | game/scripts/run/ult.gd:595 _ua("cast") |
| `sfx/ult_lumen_ignite.wav` | p_skill_lantern | gen_sfx_ult_seg_1030.py lumen() akd()；2fc201977；docs/113 §20 | game/data/ult_audio.json:75 ops.lumen.fx.strip:fx_beacon_ignite.slot（ult.gd:2075 画面单元） |
| `sfx/ult_lumen_impact.wav` | p_skill_lanternevolution（叠 Sonniss Booms_Vol2_075） | gen_sfx_ult_seg_1030.py lumen() akd()；2fc201977；docs/113 §20 | game/scripts/run/ult.gd:1851 / 2488 _ua("impact") |
| `sfx/ult_lumen_pulse_1.wav` | p_skill_recallbell | gen_sfx_ult_seg_1030.py lumen() akd()；2fc201977；docs/113 §20 | game/data/ult_audio.json:75 ops.lumen.fx.dots.slot（ult.gd:2075 画面单元） |
| `sfx/ult_lumen_pulse_2.wav` | p_skill_recallbell | gen_sfx_ult_seg_1030.py lumen() akd()；2fc201977；docs/113 §20 | game/data/ult_audio.json:75 ops.lumen.fx.dots.slot（ult.gd:2075 画面单元） |
| `sfx/ult_lumen_pulse_3.wav` | p_skill_recallbell | gen_sfx_ult_seg_1030.py lumen() akd()；2fc201977；docs/113 §20 | game/data/ult_audio.json:75 ops.lumen.fx.dots.slot（ult.gd:2075 画面单元） |
| `sfx/ult_lumen_rain_1.wav` | p_skill_shinestar | gen_sfx_ult_seg_1030.py lumen() akd()；2fc201977；docs/113 §20 | game/data/ult_audio.json:75 ops.lumen.fx.line+v.slot（ult.gd:2075 画面单元） |
| `sfx/ult_lumen_rain_2.wav` | p_skill_shinestar | gen_sfx_ult_seg_1030.py lumen() akd()；2fc201977；docs/113 §20 | game/data/ult_audio.json:75 ops.lumen.fx.line+v.slot（ult.gd:2075 画面单元） |
| `sfx/ult_lumen_rain_3.wav` | p_skill_shinestar | gen_sfx_ult_seg_1030.py lumen() akd()；2fc201977；docs/113 §20 | game/data/ult_audio.json:75 ops.lumen.fx.line+v.slot（ult.gd:2075 画面单元） |
| `sfx/ult_lumen_sf.wav` | p_skill_shinestar | gen_sfx_ult_seg_1030.py lumen() akd()；2fc201977；docs/113 §20 | game/scripts/run/ult.gd:2197（ult_%s_sf 超必杀暂停提示） |
| `sfx/ult_mizuki_burst.wav` | p_skill_bigwatercannon + p_skill_tidesurging（叠 Sonniss Booms_Vol2_075） | gen_sfx_ult_seg_1030.py mizuki() akd()；f474005ba；docs/113 §20 | game/data/ult_audio.json:45 ops.mizuki.fx.ring#2.slot（ult.gd:2075 画面单元） |
| `sfx/ult_mizuki_cast.wav` | p_skill_seasummon | gen_sfx_ult_seg_1030.py mizuki() akd()；f474005ba；docs/113 §20 | game/scripts/run/ult.gd:595 _ua("cast") |
| `sfx/ult_mizuki_compress.wav` | p_skill_darkholespell | gen_sfx_ult_seg_1030.py mizuki() akd()；f474005ba；docs/113 §20 | game/data/ult_audio.json:45 ops.mizuki.fx.ring.slot（ult.gd:2075 画面单元） |
| `sfx/ult_mizuki_pop_1.wav` | p_skill_waterbubble | gen_sfx_ult_seg_1030.py mizuki() akd()；f474005ba；docs/113 §20 | game/data/ult_audio.json:45 ops.mizuki.fx.circle#2.slot（ult.gd:2075 画面单元） |
| `sfx/ult_mizuki_pop_2.wav` | p_skill_waterbubble | gen_sfx_ult_seg_1030.py mizuki() akd()；f474005ba；docs/113 §20 | game/data/ult_audio.json:45 ops.mizuki.fx.circle#2.slot（ult.gd:2075 画面单元） |
| `sfx/ult_mizuki_pop_3.wav` | p_skill_waterbubble | gen_sfx_ult_seg_1030.py mizuki() akd()；f474005ba；docs/113 §20 | game/data/ult_audio.json:45 ops.mizuki.fx.circle#2.slot（ult.gd:2075 画面单元） |
| `sfx/ult_mizuki_rise_1.wav` | p_skill_waterbubble | gen_sfx_ult_seg_1030.py mizuki() akd()；f474005ba；docs/113 §20 | game/data/ult_audio.json:45 ops.mizuki.fx.circle.slot（ult.gd:2075 画面单元） |
| `sfx/ult_mizuki_rise_2.wav` | p_skill_waterbubble | gen_sfx_ult_seg_1030.py mizuki() akd()；f474005ba；docs/113 §20 | game/data/ult_audio.json:45 ops.mizuki.fx.circle.slot（ult.gd:2075 画面单元） |
| `sfx/ult_mizuki_rise_3.wav` | p_skill_waterbubble | gen_sfx_ult_seg_1030.py mizuki() akd()；f474005ba；docs/113 §20 | game/data/ult_audio.json:45 ops.mizuki.fx.circle.slot（ult.gd:2075 画面单元） |
| `sfx/ult_mizuki_sf.wav` | p_skill_waterbubble | gen_sfx_ult_seg_1030.py mizuki() akd()；f474005ba；docs/113 §20 | game/scripts/run/ult.gd:2197（ult_%s_sf 超必杀暂停提示） |
| `sfx/ult_saria_gather.wav` | p_skill_rockboost | gen_sfx_ult_seg_1030.py saria() akd()；758493727；docs/113 §20 | game/data/ult_audio.json:50 ops.saria.fx.line+v.slot（ult.gd:2075 画面单元） |
| `sfx/ult_saria_rock_1.wav` | p_skill_rocksleep | gen_sfx_ult_seg_1030.py saria() akd()；cf8f70f79；docs/113 §20 | game/data/ult_audio.json:50 ops.saria.fx.strip:fx_saria_pillar_break.slot（ult.gd:2075 画面单元）；game/data/ult_audio.json:50 ops.saria.fx.strip:fx_ul_rock+v.slot（ult.gd:2075 画面单元） |
| `sfx/ult_saria_rock_2.wav` | p_skill_rocksleep | gen_sfx_ult_seg_1030.py saria() akd()；cf8f70f79；docs/113 §20 | game/data/ult_audio.json:50 ops.saria.fx.strip:fx_saria_pillar_break.slot（ult.gd:2075 画面单元）；game/data/ult_audio.json:50 ops.saria.fx.strip:fx_ul_rock+v.slot（ult.gd:2075 画面单元） |
| `sfx/ult_saria_rock_3.wav` | p_skill_rocksleep | gen_sfx_ult_seg_1030.py saria() akd()；cf8f70f79；docs/113 §20 | game/data/ult_audio.json:50 ops.saria.fx.strip:fx_saria_pillar_break.slot（ult.gd:2075 画面单元）；game/data/ult_audio.json:50 ops.saria.fx.strip:fx_ul_rock+v.slot（ult.gd:2075 画面单元） |
| `sfx/ult_saria_rock_4.wav` | p_skill_rocksleep | gen_sfx_ult_seg_1030.py saria() akd()；cf8f70f79；docs/113 §20 | game/data/ult_audio.json:50 ops.saria.fx.strip:fx_saria_pillar_break.slot（ult.gd:2075 画面单元）；game/data/ult_audio.json:50 ops.saria.fx.strip:fx_ul_rock+v.slot（ult.gd:2075 画面单元） |
| `sfx/ult_saria_sf.wav` | p_skill_rocksleep | gen_sfx_ult_seg_1030.py saria() akd()；cf8f70f79；docs/113 §20 | game/scripts/run/ult.gd:2197（ult_%s_sf 超必杀暂停提示） |
| `sfx/ult_saria_slam.wav` | p_skill_jumphammer_2（叠 Sonniss Booms_Vol2_214） | gen_sfx_ult_seg_1030.py saria() akd()；758493727；docs/113 §20 | game/data/ult_audio.json:50 ops.saria.fx.circle.slot（ult.gd:2075 画面单元） |
| `sfx/ult_siege_cast.wav` | p_skill_jumphammer_1 | gen_sfx_ult_seg_1030.py siege() akd()；9c64d4f2c；docs/113 §20 | game/scripts/run/ult.gd:595 _ua("cast") |
| `sfx/ult_siege_land.wav` | p_skill_MHshieldaxe_end | gen_sfx_ult_seg_1030.py siege() akd()；df767fd5c；docs/113 §20 | game/data/ult_audio.json:67 ops.siege.seg.落地.on（ult.gd:2007/2011 分段） |
| `sfx/ult_siege_rock_1.wav` | p_skill_shieldbreak | gen_sfx_ult_seg_1030.py siege() akd()；df767fd5c；docs/113 §20 | game/data/ult_audio.json:67 ops.siege.fx.strip:fx_rock_burst.slot（ult.gd:2075 画面单元） |
| `sfx/ult_siege_rock_2.wav` | p_skill_shieldbreak | gen_sfx_ult_seg_1030.py siege() akd()；df767fd5c；docs/113 §20 | game/data/ult_audio.json:67 ops.siege.fx.strip:fx_rock_burst.slot（ult.gd:2075 画面单元） |
| `sfx/ult_siege_rock_3.wav` | p_skill_shieldbreak | gen_sfx_ult_seg_1030.py siege() akd()；df767fd5c；docs/113 §20 | game/data/ult_audio.json:67 ops.siege.fx.strip:fx_rock_burst.slot（ult.gd:2075 画面单元） |
| `sfx/ult_siege_sf.wav` | p_skill_magnetichammer | gen_sfx_ult_seg_1030.py siege() akd()；9c64d4f2c；docs/113 §20 | game/scripts/run/ult.gd:2197（ult_%s_sf 超必杀暂停提示） |
| `sfx/ult_siege_smash.wav` | p_skill_MHshieldaxe_ground2 + p_skill_magnetichammer（叠 Sonniss Woosh Debris） | gen_sfx_ult_seg_1030.py siege() akd()；df767fd5c；docs/113 §20 | game/data/ult_audio.json:67 ops.siege.fx.circle.slot（ult.gd:2075 画面单元） |
| `sfx/ult_siege_smash2.wav` | p_skill_MHshieldaxe_h2 | gen_sfx_ult_seg_1030.py siege() akd()；df767fd5c；docs/113 §20 | game/data/ult_audio.json:67 ops.siege.fx.circle.then（ult.gd:2075 画面单元） |
| `sfx/ult_skadi_cast.wav` | p_skill_reticentsword_h | gen_sfx_ult_seg_1030.py skadi() akd()；df767fd5c；docs/113 §20 | game/scripts/run/ult.gd:595 _ua("cast") |
| `sfx/ult_skadi_crash.wav` | p_skill_bigwatercannon + p_skill_MHshieldaxe_ground2（叠 Sonniss 深水冲击） | gen_sfx_ult_seg_1030.py skadi() akd()；df767fd5c；docs/113 §20 | game/data/ult_audio.json:22 ops.skadi.hf_slot（ult.gd:1492 冲击帧） |
| `sfx/ult_skadi_impact.wav` | p_skill_reticentsword_h（叠 Sonniss 液体冲击） | gen_sfx_ult_seg_1030.py skadi() akd()；df767fd5c；docs/113 §20 | game/scripts/run/ult.gd:1851 / 2488 _ua("impact") |
| `sfx/ult_skadi_sf.wav` | p_skill_reticentsword_s | gen_sfx_ult_seg_1030.py skadi() akd()；df767fd5c；docs/113 §20 | game/scripts/run/ult.gd:2197（ult_%s_sf 超必杀暂停提示） |
| `sfx/ult_skadi_wave.wav` | p_skill_tidesurging_2 | gen_sfx_ult_seg_1030.py skadi() akd()；df767fd5c；docs/113 §20 | game/data/ult_audio.json:22 ops.skadi.seg.浪头.on（ult.gd:2007/2011 分段） |
| `sfx/ult_skalter_blast_1.wav` | p_skill_spiritexplo | gen_sfx_ult_seg_1030.py skalter() akd()；2fc201977；docs/113 §20 | game/data/ult_audio.json:12 ops.skalter.fx.strip:fx_sk_blast.slot（ult.gd:2075 画面单元） |
| `sfx/ult_skalter_blast_2.wav` | p_skill_spiritexplo | gen_sfx_ult_seg_1030.py skalter() akd()；2fc201977；docs/113 §20 | game/data/ult_audio.json:12 ops.skalter.fx.strip:fx_sk_blast.slot（ult.gd:2075 画面单元） |
| `sfx/ult_skalter_blast_3.wav` | p_skill_spiritexplo | gen_sfx_ult_seg_1030.py skalter() akd()；2fc201977；docs/113 §20 | game/data/ult_audio.json:12 ops.skalter.fx.strip:fx_sk_blast.slot（ult.gd:2075 画面单元） |
| `sfx/ult_skalter_cast.wav` | p_field_elefield_loop | gen_sfx_ult_seg_1030.py skalter() akd()；2fc201977；docs/113 §20 | game/scripts/run/ult.gd:595 _ua("cast") |
| `sfx/ult_skalter_final.wav` | p_skill_aeroliteexplo + p_skill_darkholeboost（叠 Sonniss Booms_Vol2_214） | gen_sfx_ult_seg_1030.py skalter() akd()；2fc201977；docs/113 §20 | game/data/ult_audio.json:12 ops.skalter.hf_slot（ult.gd:1492 冲击帧）；game/data/ult_audio.json:12 ops.skalter.fx.strip:fx_sk_flash.slot（ult.gd:2075 画面单元） |
| `sfx/ult_skalter_rise.wav` | p_skill_seasummon | gen_sfx_ult_seg_1030.py skalter() akd()；2fc201977；docs/113 §20 | game/data/ult_audio.json:12 ops.skalter.fx.strip:fx_ult_skalter_seaborn_front.slot（ult.gd:2075 画面单元） |
| `sfx/ult_skalter_sf.wav` | p_skill_seasummon | gen_sfx_ult_seg_1030.py skalter() akd()；2fc201977；docs/113 §20 | game/scripts/run/ult.gd:2197（ult_%s_sf 超必杀暂停提示） |
| `sfx/ult_specter_unchained_cast.wav` | p_skill_chainsawulmextension_1_intro | gen_sfx_ult_seg_1030.py specter_unchained() akd()；df767fd5c；docs/113 §20 | game/scripts/run/ult.gd:595 _ua("cast") |
| `sfx/ult_specter_unchained_impact.wav` | p_skill_chainsawulmextension_3 + p_skill_MHshieldaxe_ground2 | gen_sfx_ult_seg_1030.py specter_unchained() akd()；df767fd5c；docs/113 §20 | game/scripts/run/ult.gd:1851 / 2488 _ua("impact") |
| `sfx/ult_specter_unchained_sf.wav` | p_skill_chainsawextension | gen_sfx_ult_seg_1030.py specter_unchained() akd()；df767fd5c；docs/113 §20 | game/scripts/run/ult.gd:2197（ult_%s_sf 超必杀暂停提示） |
| `sfx/ult_specter_unchained_warn.wav` | p_skill_chainsawulmextension_2 | gen_sfx_ult_seg_1030.py specter_unchained() akd()；df767fd5c；docs/113 §20 | game/data/ult_audio.json:42 ops.specter_unchained.fx.strip:fx_sp_saw+v.slot（ult.gd:2075 画面单元） |
| `sfx/ult_specter_unchained_zip_1.wav` | p_skill_chainsawextension | gen_sfx_ult_seg_1030.py specter_unchained() akd()；df767fd5c；docs/113 §20 | game/data/ult_audio.json:42 ops.specter_unchained.fx.strip:fx_sp_saw.slot（ult.gd:2075 画面单元） |
| `sfx/ult_specter_unchained_zip_2.wav` | p_skill_chainsawextension | gen_sfx_ult_seg_1030.py specter_unchained() akd()；df767fd5c；docs/113 §20 | game/data/ult_audio.json:42 ops.specter_unchained.fx.strip:fx_sp_saw.slot（ult.gd:2075 画面单元） |
| `sfx/ult_specter_unchained_zip_3.wav` | p_skill_chainsawextension | gen_sfx_ult_seg_1030.py specter_unchained() akd()；df767fd5c；docs/113 §20 | game/data/ult_audio.json:42 ops.specter_unchained.fx.strip:fx_sp_saw.slot（ult.gd:2075 画面单元） |
| `sfx/ult_suzuran_flash.wav` | p_skill_ninjasword | gen_sfx_ult_seg_1030.py suzuran() akd()；b50ca496a；docs/113 §20 | game/data/ult_audio.json:56 ops.suzuran.seg.瞬身.on（ult.gd:2007/2011 分段） |
| `sfx/ult_suzuran_impact.wav` | p_skill_darkatana（叠 Sonniss Impact Cut Sweep + Booms_Vol2_075） | gen_sfx_ult_seg_1030.py suzuran() akd()；b50ca496a；docs/113 §20 | game/scripts/run/ult.gd:1851 / 2488 _ua("impact") |
| `sfx/ult_suzuran_rupt.wav` | p_skill_spiritexplo + p_skill_ninjasword_imp | gen_sfx_ult_seg_1030.py suzuran() akd()；df767fd5c；docs/113 §20 | game/data/ult_audio.json:56 ops.suzuran.fx.band.slot（ult.gd:2075 画面单元） |
| `sfx/ult_suzuran_sf.wav` | p_skill_ninjasword_imp | gen_sfx_ult_seg_1030.py suzuran() akd()；b50ca496a；docs/113 §20 | game/scripts/run/ult.gd:2197（ult_%s_sf 超必杀暂停提示） |
| `sfx/ult_wisadel_after_1.wav` | p_skill_fireboomshot | gen_sfx_ult_seg_1030.py wisadel() akd()；2fc201977；docs/113 §20 | game/data/ult_audio.json:36 ops.wisadel.fx.strip:fx_ul_rock+v.slot（ult.gd:2075 画面单元）；game/data/ult_audio.json:36 ops.wisadel.fx.strip:fx_missile_explode.slot（ult.gd:2075 画面单元） |
| `sfx/ult_wisadel_after_2.wav` | p_skill_fireboomshot | gen_sfx_ult_seg_1030.py wisadel() akd()；2fc201977；docs/113 §20 | game/data/ult_audio.json:36 ops.wisadel.fx.strip:fx_ul_rock+v.slot（ult.gd:2075 画面单元）；game/data/ult_audio.json:36 ops.wisadel.fx.strip:fx_missile_explode.slot（ult.gd:2075 画面单元） |
| `sfx/ult_wisadel_after_3.wav` | p_skill_fireboomshot | gen_sfx_ult_seg_1030.py wisadel() akd()；2fc201977；docs/113 §20 | game/data/ult_audio.json:36 ops.wisadel.fx.strip:fx_ul_rock+v.slot（ult.gd:2075 画面单元）；game/data/ult_audio.json:36 ops.wisadel.fx.strip:fx_missile_explode.slot（ult.gd:2075 画面单元） |
| `sfx/ult_wisadel_cast.wav` | p_skill_launcher_cast | gen_sfx_ult_seg_1030.py wisadel() akd()；2fc201977；docs/113 §20 | game/scripts/run/ult.gd:595 _ua("cast") |
| `sfx/ult_wisadel_fire.wav` | p_skill_blackcannonfull | gen_sfx_ult_seg_1030.py wisadel() akd()；2fc201977；docs/113 §20 | game/data/ult_audio.json:36 ops.wisadel.fx.strip:fx_cannon_burst.slot（ult.gd:2075 画面单元） |
| `sfx/ult_wisadel_impact.wav` | p_skill_aeroliteexplo（叠 Sonniss Booms_Vol2_214） | gen_sfx_ult_seg_1030.py wisadel() akd()；2fc201977；docs/113 §20 | game/scripts/run/ult.gd:1851 / 2488 _ua("impact") |
| `sfx/ult_wisadel_sf.wav` | p_skill_blackcannonfull_cast | gen_sfx_ult_seg_1030.py wisadel() akd()；2fc201977；docs/113 §20 | game/scripts/run/ult.gd:2197（ult_%s_sf 超必杀暂停提示） |
| `sfx/ult_wisadel_shell_1.wav` | p_skill_fireboomexplo | gen_sfx_ult_seg_1030.py wisadel() akd()；2fc201977；docs/113 §20 | game/data/ult_audio.json:36 ops.wisadel.fx.strip:fx_wd_cannon.slot（ult.gd:2075 画面单元）；game/data/ult_audio.json:36 ops.wisadel.fx.strip:fx_wisadel_cannon.slot（ult.gd:2075 画面单元） |
| `sfx/ult_wisadel_shell_2.wav` | p_skill_fireboomexplo | gen_sfx_ult_seg_1030.py wisadel() akd()；2fc201977；docs/113 §20 | game/data/ult_audio.json:36 ops.wisadel.fx.strip:fx_wd_cannon.slot（ult.gd:2075 画面单元）；game/data/ult_audio.json:36 ops.wisadel.fx.strip:fx_wisadel_cannon.slot（ult.gd:2075 画面单元） |
| `sfx/ult_wisadel_shell_3.wav` | p_skill_fireboomexplo | gen_sfx_ult_seg_1030.py wisadel() akd()；2fc201977；docs/113 §20 | game/data/ult_audio.json:36 ops.wisadel.fx.strip:fx_wd_cannon.slot（ult.gd:2075 画面单元）；game/data/ult_audio.json:36 ops.wisadel.fx.strip:fx_wisadel_cannon.slot（ult.gd:2075 画面单元） |

### 1b　干员语音（237）

来源：`game/audio/voice/voice_manifest.json`（237 条全部登记，source = https://github.com/isHarryh/Ark-Voice/tree/main/voice_cn，source_note「Original voice recordings are copyrighted by Hypergryph」）与 voice/README.md「素材来源」。每条有 source_operator（char_xxx）与 source_clip（CN_0xx 原语音索引）及截取区间。播放：`game/scripts/sfx.gd:661` 读 `res://audio/voice/<主名>.ogg`，池表 `voice_pools.json`（sfx.gd:688），终结技台词 `game/data/ult_audio.json` 的 voice。

| 文件 | 原作源（干员 / 语音索引） | 用在哪里 |
|---|---|---|
| `voice/angelina_battle.ogg` | char_291_aglina CN_028 | ult_audio.json ops.angelina.voice |
| `voice/angelina_battle_2.ogg` | char_291_aglina CN_020 | voice_pools.json pools.angelina.skill；voice_pools.json pools.angelina.battle |
| `voice/angelina_command.ogg` | char_291_aglina CN_021 | voice_pools.json pools.angelina.command |
| `voice/angelina_command_2.ogg` | char_291_aglina CN_022 | voice_pools.json pools.angelina.command |
| `voice/angelina_command_3.ogg` | char_291_aglina CN_018 | voice_pools.json pools.angelina.command |
| `voice/angelina_entry.ogg` | char_291_aglina CN_023 | voice_pools.json pools.angelina.entry |
| `voice/angelina_entry_2.ogg` | char_291_aglina CN_024 | voice_pools.json pools.angelina.entry；voice_pools.json pools.angelina.command；voice_pools.json pools.angelina.battle |
| `voice/angelina_entry_3.ogg` | char_291_aglina CN_017 | voice_pools.json pools.angelina.entry；ult_audio.json ops.angelina.voice_alt |
| `voice/angelina_entry_4.ogg` | char_291_aglina CN_019 | voice_pools.json pools.angelina.entry；voice_pools.json pools.angelina.battle |
| `voice/angelina_skill_1.ogg` | char_291_aglina CN_025 | voice_pools.json pools.angelina.skill |
| `voice/angelina_skill_2.ogg` | char_291_aglina CN_026 | voice_pools.json pools.angelina.skill |
| `voice/angelina_skill_3.ogg` | char_291_aglina CN_027 | voice_pools.json pools.angelina.skill；ult_audio.json ops.angelina.voice_alt |
| `voice/exusiai_battle.ogg` | char_103_angel CN_028 | voice_pools.json pools.exusiai.skill；voice_pools.json pools.exusiai.battle |
| `voice/exusiai_battle_2.ogg` | char_103_angel CN_020 | voice_pools.json pools.exusiai.battle |
| `voice/exusiai_command.ogg` | char_103_angel CN_021 | voice_pools.json pools.exusiai.entry；voice_pools.json pools.exusiai.command |
| `voice/exusiai_command_2.ogg` | char_103_angel CN_022 | voice_pools.json pools.exusiai.command |
| `voice/exusiai_command_3.ogg` | char_103_angel CN_018 | voice_pools.json pools.exusiai.command |
| `voice/exusiai_entry.ogg` | char_103_angel CN_023 | voice_pools.json pools.exusiai.entry |
| `voice/exusiai_entry_2.ogg` | char_103_angel CN_024 | voice_pools.json pools.exusiai.entry；voice_pools.json pools.exusiai.command |
| `voice/exusiai_entry_3.ogg` | char_103_angel CN_019 | voice_pools.json pools.exusiai.entry；voice_pools.json pools.exusiai.battle；ult_audio.json ops.exusiai.voice_alt |
| `voice/exusiai_skill_1.ogg` | char_103_angel CN_025 | voice_pools.json pools.exusiai.skill |
| `voice/exusiai_skill_2.ogg` | char_103_angel CN_026 | voice_pools.json pools.exusiai.skill |
| `voice/exusiai_skill_3.ogg` | char_103_angel CN_027 | voice_pools.json pools.exusiai.skill；ult_audio.json ops.exusiai.voice_alt |
| `voice/exusiai_syn_team.ogg` | char_103_angel CN_017 | （未在池表 / 终结技表中引用；sfx.gd:661 按 <干员>_<事件> 主名直接加载） |
| `voice/exusiai_ult.ogg` | char_103_angel CN_030 | ult_audio.json ops.exusiai.voice |
| `voice/eyjafjalla_battle.ogg` | char_180_amgoat CN_028 | voice_pools.json pools.eyjafjalla.skill；voice_pools.json pools.eyjafjalla.battle；ult_audio.json ops.eyjafjalla.voice |
| `voice/eyjafjalla_battle_2.ogg` | char_180_amgoat CN_020 | voice_pools.json pools.eyjafjalla.battle |
| `voice/eyjafjalla_command.ogg` | char_180_amgoat CN_017 | voice_pools.json pools.eyjafjalla.entry；voice_pools.json pools.eyjafjalla.command |
| `voice/eyjafjalla_command_2.ogg` | char_180_amgoat CN_021 | voice_pools.json pools.eyjafjalla.command |
| `voice/eyjafjalla_command_3.ogg` | char_180_amgoat CN_022 | voice_pools.json pools.eyjafjalla.command |
| `voice/eyjafjalla_command_4.ogg` | char_180_amgoat CN_018 | voice_pools.json pools.eyjafjalla.command |
| `voice/eyjafjalla_entry.ogg` | char_180_amgoat CN_023 | voice_pools.json pools.eyjafjalla.entry |
| `voice/eyjafjalla_entry_2.ogg` | char_180_amgoat CN_024 | voice_pools.json pools.eyjafjalla.entry；ult_audio.json ops.eyjafjalla.voice_alt |
| `voice/eyjafjalla_entry_3.ogg` | char_180_amgoat CN_019 | voice_pools.json pools.eyjafjalla.entry；voice_pools.json pools.eyjafjalla.battle |
| `voice/eyjafjalla_skill_1.ogg` | char_180_amgoat CN_025 | voice_pools.json pools.eyjafjalla.skill |
| `voice/eyjafjalla_skill_2.ogg` | char_180_amgoat CN_026 | voice_pools.json pools.eyjafjalla.skill；ult_audio.json ops.eyjafjalla.voice_alt |
| `voice/eyjafjalla_skill_3.ogg` | char_180_amgoat CN_027 | voice_pools.json pools.eyjafjalla.skill |
| `voice/gladiia_battle.ogg` | char_474_glady CN_028 | ult_audio.json ops.gladiia.voice |
| `voice/gladiia_battle_2.ogg` | char_474_glady CN_020 | voice_pools.json pools.gladiia.skill；voice_pools.json pools.gladiia.battle |
| `voice/gladiia_command.ogg` | char_474_glady CN_022 | voice_pools.json pools.gladiia.command |
| `voice/gladiia_command_2.ogg` | char_474_glady CN_021 | voice_pools.json pools.gladiia.command |
| `voice/gladiia_entry.ogg` | char_474_glady CN_023 | voice_pools.json pools.gladiia.entry |
| `voice/gladiia_entry_2.ogg` | char_474_glady CN_024 | voice_pools.json pools.gladiia.entry；voice_pools.json pools.gladiia.command；voice_pools.json pools.gladiia.battle；ult_audio.json ops.gladiia.voice_alt |
| `voice/gladiia_entry_3.ogg` | char_474_glady CN_017 | voice_pools.json pools.gladiia.entry |
| `voice/gladiia_entry_4.ogg` | char_474_glady CN_019 | voice_pools.json pools.gladiia.entry；voice_pools.json pools.gladiia.command；voice_pools.json pools.gladiia.battle |
| `voice/gladiia_skill_1.ogg` | char_474_glady CN_025 | voice_pools.json pools.gladiia.skill |
| `voice/gladiia_skill_2.ogg` | char_474_glady CN_026 | voice_pools.json pools.gladiia.skill |
| `voice/gladiia_skill_3.ogg` | char_474_glady CN_027 | voice_pools.json pools.gladiia.skill |
| `voice/hoshiguma_battle.ogg` | char_136_hsguma CN_028 | ult_audio.json ops.hoshiguma.voice_alt |
| `voice/hoshiguma_battle_2.ogg` | char_136_hsguma CN_020 | voice_pools.json pools.hoshiguma.skill；voice_pools.json pools.hoshiguma.battle |
| `voice/hoshiguma_command.ogg` | char_136_hsguma CN_022 | voice_pools.json pools.hoshiguma.command |
| `voice/hoshiguma_command_2.ogg` | char_136_hsguma CN_021 | voice_pools.json pools.hoshiguma.command |
| `voice/hoshiguma_command_3.ogg` | char_136_hsguma CN_018 | voice_pools.json pools.hoshiguma.command |
| `voice/hoshiguma_entry.ogg` | char_136_hsguma CN_023 | voice_pools.json pools.hoshiguma.entry |
| `voice/hoshiguma_entry_2.ogg` | char_136_hsguma CN_024 | voice_pools.json pools.hoshiguma.entry；voice_pools.json pools.hoshiguma.command；voice_pools.json pools.hoshiguma.battle |
| `voice/hoshiguma_entry_3.ogg` | char_136_hsguma CN_017 | voice_pools.json pools.hoshiguma.entry |
| `voice/hoshiguma_entry_4.ogg` | char_136_hsguma CN_019 | voice_pools.json pools.hoshiguma.entry；voice_pools.json pools.hoshiguma.battle |
| `voice/hoshiguma_skill_1.ogg` | char_136_hsguma CN_025 | voice_pools.json pools.hoshiguma.skill；ult_audio.json ops.hoshiguma.voice |
| `voice/hoshiguma_skill_2.ogg` | char_136_hsguma CN_026 | voice_pools.json pools.hoshiguma.skill；ult_audio.json ops.hoshiguma.voice_alt |
| `voice/hoshiguma_skill_3.ogg` | char_136_hsguma CN_027 | voice_pools.json pools.hoshiguma.skill |
| `voice/irene_battle.ogg` | char_4009_irene CN_028 | ult_audio.json ops.irene.voice |
| `voice/irene_battle_2.ogg` | char_4009_irene CN_020 | voice_pools.json pools.irene.skill；voice_pools.json pools.irene.battle |
| `voice/irene_command.ogg` | char_4009_irene CN_024 | voice_pools.json pools.irene.entry；voice_pools.json pools.irene.command；voice_pools.json pools.irene.battle |
| `voice/irene_command_2.ogg` | char_4009_irene CN_021 | voice_pools.json pools.irene.command |
| `voice/irene_command_3.ogg` | char_4009_irene CN_022 | voice_pools.json pools.irene.command |
| `voice/irene_entry.ogg` | char_4009_irene CN_023 | voice_pools.json pools.irene.entry |
| `voice/irene_entry_2.ogg` | char_4009_irene CN_017 | voice_pools.json pools.irene.entry |
| `voice/irene_entry_3.ogg` | char_4009_irene CN_019 | voice_pools.json pools.irene.entry；voice_pools.json pools.irene.command；voice_pools.json pools.irene.battle |
| `voice/irene_skill_1.ogg` | char_4009_irene CN_025 | voice_pools.json pools.irene.skill |
| `voice/irene_skill_2.ogg` | char_4009_irene CN_026 | voice_pools.json pools.irene.skill；ult_audio.json ops.irene.voice_alt |
| `voice/irene_skill_3.ogg` | char_4009_irene CN_027 | voice_pools.json pools.irene.skill |
| `voice/kaltsit_battle.ogg` | char_003_kalts CN_028 | voice_pools.json pools.kaltsit.skill；voice_pools.json pools.kaltsit.battle |
| `voice/kaltsit_battle_2.ogg` | char_003_kalts CN_020 | voice_pools.json pools.kaltsit.battle |
| `voice/kaltsit_command.ogg` | char_003_kalts CN_019 | voice_pools.json pools.kaltsit.entry；voice_pools.json pools.kaltsit.command；voice_pools.json pools.kaltsit.battle |
| `voice/kaltsit_command_2.ogg` | char_003_kalts CN_021 | voice_pools.json pools.kaltsit.command |
| `voice/kaltsit_command_3.ogg` | char_003_kalts CN_022 | voice_pools.json pools.kaltsit.command |
| `voice/kaltsit_command_4.ogg` | char_003_kalts CN_018 | voice_pools.json pools.kaltsit.command |
| `voice/kaltsit_entry.ogg` | char_003_kalts CN_023 | voice_pools.json pools.kaltsit.entry |
| `voice/kaltsit_entry_2.ogg` | char_003_kalts CN_024 | voice_pools.json pools.kaltsit.entry |
| `voice/kaltsit_entry_3.ogg` | char_003_kalts CN_017 | voice_pools.json pools.kaltsit.entry |
| `voice/kaltsit_skill_1.ogg` | char_003_kalts CN_025 | voice_pools.json pools.kaltsit.skill；ult_audio.json ops.kaltsit.voice |
| `voice/kaltsit_skill_2.ogg` | char_003_kalts CN_026 | voice_pools.json pools.kaltsit.skill；ult_audio.json ops.kaltsit.voice_alt |
| `voice/kaltsit_skill_3.ogg` | char_003_kalts CN_027 | voice_pools.json pools.kaltsit.skill；ult_audio.json ops.kaltsit.voice_alt |
| `voice/lappland_battle.ogg` | char_140_whitew CN_028 | voice_pools.json pools.lappland.skill；voice_pools.json pools.lappland.battle |
| `voice/lappland_battle_2.ogg` | char_140_whitew CN_020 | voice_pools.json pools.lappland.battle；ult_audio.json ops.lappland.voice_alt |
| `voice/lappland_command.ogg` | char_140_whitew CN_021 | voice_pools.json pools.lappland.entry；voice_pools.json pools.lappland.command |
| `voice/lappland_command_2.ogg` | char_140_whitew CN_022 | voice_pools.json pools.lappland.command |
| `voice/lappland_entry.ogg` | char_140_whitew CN_023 | voice_pools.json pools.lappland.entry；voice_pools.json pools.lappland.command |
| `voice/lappland_entry_2.ogg` | char_140_whitew CN_024 | voice_pools.json pools.lappland.entry；voice_pools.json pools.lappland.command；voice_pools.json pools.lappland.battle；ult_audio.json ops.lappland.voice |
| `voice/lappland_entry_3.ogg` | char_140_whitew CN_017 | voice_pools.json pools.lappland.entry |
| `voice/lappland_skill_1.ogg` | char_140_whitew CN_025 | voice_pools.json pools.lappland.skill |
| `voice/lappland_skill_2.ogg` | char_140_whitew CN_026 | voice_pools.json pools.lappland.skill |
| `voice/lappland_skill_3.ogg` | char_140_whitew CN_027 | voice_pools.json pools.lappland.skill；ult_audio.json ops.lappland.voice_alt |
| `voice/lappland_syn_rival.ogg` | char_140_whitew CN_018 | （未在池表 / 终结技表中引用；sfx.gd:661 按 <干员>_<事件> 主名直接加载） |
| `voice/lappland_ult.ogg` | char_140_whitew CN_029 | ult_audio.json ops.lappland.voice_alt |
| `voice/logos_battle.ogg` | char_4133_logos CN_028 | voice_pools.json pools.logos.skill；voice_pools.json pools.logos.battle；ult_audio.json ops.logos.voice_alt |
| `voice/logos_battle_2.ogg` | char_4133_logos CN_020 | voice_pools.json pools.logos.battle |
| `voice/logos_command.ogg` | char_4133_logos CN_018 | voice_pools.json pools.logos.command |
| `voice/logos_command_2.ogg` | char_4133_logos CN_021 | voice_pools.json pools.logos.entry；voice_pools.json pools.logos.command |
| `voice/logos_command_3.ogg` | char_4133_logos CN_022 | voice_pools.json pools.logos.command |
| `voice/logos_entry.ogg` | char_4133_logos CN_023 | voice_pools.json pools.logos.entry |
| `voice/logos_entry_2.ogg` | char_4133_logos CN_024 | ult_audio.json ops.logos.voice |
| `voice/logos_entry_3.ogg` | char_4133_logos CN_017 | voice_pools.json pools.logos.entry |
| `voice/logos_entry_4.ogg` | char_4133_logos CN_019 | voice_pools.json pools.logos.entry；voice_pools.json pools.logos.command；voice_pools.json pools.logos.battle |
| `voice/logos_skill_1.ogg` | char_4133_logos CN_025 | voice_pools.json pools.logos.skill |
| `voice/logos_skill_2.ogg` | char_4133_logos CN_026 | voice_pools.json pools.logos.skill |
| `voice/logos_skill_3.ogg` | char_4133_logos CN_027 | voice_pools.json pools.logos.skill |
| `voice/lumen_battle.ogg` | char_4042_lumen CN_028 | voice_pools.json pools.lumen.skill；voice_pools.json pools.lumen.battle |
| `voice/lumen_battle_2.ogg` | char_4042_lumen CN_020 | voice_pools.json pools.lumen.battle；ult_audio.json ops.lumen.voice |
| `voice/lumen_command.ogg` | char_4042_lumen CN_021 | voice_pools.json pools.lumen.command |
| `voice/lumen_command_2.ogg` | char_4042_lumen CN_022 | voice_pools.json pools.lumen.command |
| `voice/lumen_entry.ogg` | char_4042_lumen CN_023 | voice_pools.json pools.lumen.entry；ult_audio.json ops.lumen.voice_alt |
| `voice/lumen_entry_2.ogg` | char_4042_lumen CN_024 | voice_pools.json pools.lumen.entry；voice_pools.json pools.lumen.command；ult_audio.json ops.lumen.voice_alt |
| `voice/lumen_entry_3.ogg` | char_4042_lumen CN_017 | voice_pools.json pools.lumen.entry |
| `voice/lumen_entry_4.ogg` | char_4042_lumen CN_019 | voice_pools.json pools.lumen.entry；voice_pools.json pools.lumen.command；voice_pools.json pools.lumen.battle |
| `voice/lumen_skill_1.ogg` | char_4042_lumen CN_025 | voice_pools.json pools.lumen.skill |
| `voice/lumen_skill_2.ogg` | char_4042_lumen CN_026 | voice_pools.json pools.lumen.skill |
| `voice/lumen_skill_3.ogg` | char_4042_lumen CN_027 | voice_pools.json pools.lumen.skill |
| `voice/mizuki_battle.ogg` | char_437_mizuki CN_028 | voice_pools.json pools.mizuki.skill；voice_pools.json pools.mizuki.battle；ult_audio.json ops.mizuki.voice_alt |
| `voice/mizuki_battle_2.ogg` | char_437_mizuki CN_020 | voice_pools.json pools.mizuki.battle |
| `voice/mizuki_battle_3.ogg` | char_437_mizuki CN_019 | voice_pools.json pools.mizuki.battle |
| `voice/mizuki_command.ogg` | char_437_mizuki CN_022 | voice_pools.json pools.mizuki.command |
| `voice/mizuki_command_2.ogg` | char_437_mizuki CN_018 | voice_pools.json pools.mizuki.command |
| `voice/mizuki_entry.ogg` | char_437_mizuki CN_023 | voice_pools.json pools.mizuki.entry |
| `voice/mizuki_entry_2.ogg` | char_437_mizuki CN_024 | voice_pools.json pools.mizuki.entry；voice_pools.json pools.mizuki.command |
| `voice/mizuki_entry_3.ogg` | char_437_mizuki CN_017 | voice_pools.json pools.mizuki.entry |
| `voice/mizuki_entry_4.ogg` | char_437_mizuki CN_021 | voice_pools.json pools.mizuki.entry；voice_pools.json pools.mizuki.command |
| `voice/mizuki_skill_1.ogg` | char_437_mizuki CN_025 | voice_pools.json pools.mizuki.skill |
| `voice/mizuki_skill_2.ogg` | char_437_mizuki CN_026 | voice_pools.json pools.mizuki.skill |
| `voice/mizuki_skill_3.ogg` | char_437_mizuki CN_027 | voice_pools.json pools.mizuki.skill；ult_audio.json ops.mizuki.voice |
| `voice/saria_battle.ogg` | char_202_demkni CN_028 | voice_pools.json pools.saria.skill；voice_pools.json pools.saria.battle |
| `voice/saria_battle_2.ogg` | char_202_demkni CN_020 | voice_pools.json pools.saria.battle |
| `voice/saria_command.ogg` | char_202_demkni CN_021 | voice_pools.json pools.saria.command |
| `voice/saria_command_2.ogg` | char_202_demkni CN_022 | voice_pools.json pools.saria.command；ult_audio.json ops.saria.voice_alt |
| `voice/saria_command_3.ogg` | char_202_demkni CN_018 | voice_pools.json pools.saria.command |
| `voice/saria_entry.ogg` | char_202_demkni CN_023 | voice_pools.json pools.saria.entry |
| `voice/saria_entry_2.ogg` | char_202_demkni CN_024 | voice_pools.json pools.saria.entry；voice_pools.json pools.saria.command；ult_audio.json ops.saria.voice |
| `voice/saria_entry_3.ogg` | char_202_demkni CN_017 | voice_pools.json pools.saria.entry |
| `voice/saria_entry_4.ogg` | char_202_demkni CN_019 | voice_pools.json pools.saria.entry；voice_pools.json pools.saria.battle |
| `voice/saria_skill_1.ogg` | char_202_demkni CN_025 | voice_pools.json pools.saria.skill；ult_audio.json ops.saria.voice_alt |
| `voice/saria_skill_2.ogg` | char_202_demkni CN_026 | voice_pools.json pools.saria.skill |
| `voice/saria_skill_3.ogg` | char_202_demkni CN_027 | voice_pools.json pools.saria.skill |
| `voice/siege_battle.ogg` | char_112_siege CN_028 | voice_pools.json pools.siege.skill；voice_pools.json pools.siege.battle |
| `voice/siege_battle_2.ogg` | char_112_siege CN_020 | voice_pools.json pools.siege.battle |
| `voice/siege_command.ogg` | char_112_siege CN_024 | voice_pools.json pools.siege.entry；voice_pools.json pools.siege.command；ult_audio.json ops.siege.voice_alt |
| `voice/siege_command_2.ogg` | char_112_siege CN_021 | voice_pools.json pools.siege.command |
| `voice/siege_command_3.ogg` | char_112_siege CN_022 | voice_pools.json pools.siege.command |
| `voice/siege_command_4.ogg` | char_112_siege CN_018 | voice_pools.json pools.siege.command |
| `voice/siege_entry.ogg` | char_112_siege CN_023 | voice_pools.json pools.siege.entry |
| `voice/siege_entry_2.ogg` | char_112_siege CN_017 | voice_pools.json pools.siege.entry |
| `voice/siege_entry_3.ogg` | char_112_siege CN_019 | voice_pools.json pools.siege.entry；voice_pools.json pools.siege.battle |
| `voice/siege_skill_1.ogg` | char_112_siege CN_025 | voice_pools.json pools.siege.skill |
| `voice/siege_skill_2.ogg` | char_112_siege CN_026 | voice_pools.json pools.siege.skill |
| `voice/siege_skill_3.ogg` | char_112_siege CN_027 | voice_pools.json pools.siege.skill；ult_audio.json ops.siege.voice_alt |
| `voice/siege_ult.ogg` | char_112_siege CN_030 | ult_audio.json ops.siege.voice |
| `voice/skadi_battle.ogg` | char_263_skadi CN_028 | voice_pools.json pools.skadi.skill；voice_pools.json pools.skadi.battle；ult_audio.json ops.skadi.voice |
| `voice/skadi_battle_2.ogg` | char_263_skadi CN_020 | voice_pools.json pools.skadi.battle |
| `voice/skadi_command.ogg` | char_263_skadi CN_021 | voice_pools.json pools.skadi.command |
| `voice/skadi_command_2.ogg` | char_263_skadi CN_022 | voice_pools.json pools.skadi.command |
| `voice/skadi_command_3.ogg` | char_263_skadi CN_018 | voice_pools.json pools.skadi.command |
| `voice/skadi_entry.ogg` | char_263_skadi CN_023 | voice_pools.json pools.skadi.entry；ult_audio.json ops.skadi.voice_alt |
| `voice/skadi_entry_2.ogg` | char_263_skadi CN_024 | voice_pools.json pools.skadi.entry；voice_pools.json pools.skadi.command |
| `voice/skadi_entry_3.ogg` | char_263_skadi CN_017 | voice_pools.json pools.skadi.entry |
| `voice/skadi_entry_4.ogg` | char_263_skadi CN_019 | voice_pools.json pools.skadi.entry；voice_pools.json pools.skadi.battle |
| `voice/skadi_skill_1.ogg` | char_263_skadi CN_025 | voice_pools.json pools.skadi.skill |
| `voice/skadi_skill_2.ogg` | char_263_skadi CN_026 | voice_pools.json pools.skadi.skill |
| `voice/skadi_skill_3.ogg` | char_263_skadi CN_027 | voice_pools.json pools.skadi.skill |
| `voice/skalter_battle.ogg` | char_1012_skadi2 CN_028 | voice_pools.json pools.skalter.skill；voice_pools.json pools.skalter.battle |
| `voice/skalter_battle_2.ogg` | char_1012_skadi2 CN_020 | voice_pools.json pools.skalter.battle |
| `voice/skalter_command.ogg` | char_1012_skadi2 CN_024 | voice_pools.json pools.skalter.entry；voice_pools.json pools.skalter.command |
| `voice/skalter_command_2.ogg` | char_1012_skadi2 CN_018 | voice_pools.json pools.skalter.command；voice_pools.json pools.skalter.battle；ult_audio.json ops.skalter.voice |
| `voice/skalter_entry.ogg` | char_1012_skadi2 CN_023 | voice_pools.json pools.skalter.entry；voice_pools.json pools.skalter.command；ult_audio.json ops.skalter.voice_alt |
| `voice/skalter_entry_2.ogg` | char_1012_skadi2 CN_021 | voice_pools.json pools.skalter.entry；voice_pools.json pools.skalter.command |
| `voice/skalter_skill_1.ogg` | char_1012_skadi2 CN_025 | voice_pools.json pools.skalter.skill |
| `voice/skalter_skill_2.ogg` | char_1012_skadi2 CN_026 | voice_pools.json pools.skalter.skill |
| `voice/skalter_skill_3.ogg` | char_1012_skadi2 CN_027 | voice_pools.json pools.skalter.skill；ult_audio.json ops.skalter.voice_alt |
| `voice/specter_unchained_battle.ogg` | char_1023_ghost2 CN_028 | voice_pools.json pools.specter_unchained.skill；voice_pools.json pools.specter_unchained.battle；ult_audio.json ops.specter_unchained.voice |
| `voice/specter_unchained_battle_2.ogg` | char_1023_ghost2 CN_020 | voice_pools.json pools.specter_unchained.battle |
| `voice/specter_unchained_command.ogg` | char_1023_ghost2 CN_017 | voice_pools.json pools.specter_unchained.entry；voice_pools.json pools.specter_unchained.command |
| `voice/specter_unchained_command_2.ogg` | char_1023_ghost2 CN_021 | voice_pools.json pools.specter_unchained.command |
| `voice/specter_unchained_command_3.ogg` | char_1023_ghost2 CN_022 | voice_pools.json pools.specter_unchained.command |
| `voice/specter_unchained_command_4.ogg` | char_1023_ghost2 CN_018 | voice_pools.json pools.specter_unchained.command |
| `voice/specter_unchained_entry.ogg` | char_1023_ghost2 CN_023 | voice_pools.json pools.specter_unchained.entry |
| `voice/specter_unchained_entry_2.ogg` | char_1023_ghost2 CN_024 | voice_pools.json pools.specter_unchained.entry；ult_audio.json ops.specter_unchained.voice_alt |
| `voice/specter_unchained_entry_3.ogg` | char_1023_ghost2 CN_019 | voice_pools.json pools.specter_unchained.entry；voice_pools.json pools.specter_unchained.battle |
| `voice/specter_unchained_skill_1.ogg` | char_1023_ghost2 CN_025 | voice_pools.json pools.specter_unchained.skill |
| `voice/specter_unchained_skill_2.ogg` | char_1023_ghost2 CN_026 | voice_pools.json pools.specter_unchained.skill |
| `voice/specter_unchained_skill_3.ogg` | char_1023_ghost2 CN_027 | voice_pools.json pools.specter_unchained.skill；ult_audio.json ops.specter_unchained.voice_alt |
| `voice/suzuran_battle.ogg` | char_358_lisa CN_028 | voice_pools.json pools.suzuran.skill；voice_pools.json pools.suzuran.battle |
| `voice/suzuran_battle_2.ogg` | char_358_lisa CN_020 | voice_pools.json pools.suzuran.battle |
| `voice/suzuran_command.ogg` | char_358_lisa CN_021 | voice_pools.json pools.suzuran.command |
| `voice/suzuran_command_2.ogg` | char_358_lisa CN_022 | voice_pools.json pools.suzuran.command |
| `voice/suzuran_entry.ogg` | char_358_lisa CN_023 | voice_pools.json pools.suzuran.entry |
| `voice/suzuran_entry_2.ogg` | char_358_lisa CN_024 | voice_pools.json pools.suzuran.entry；voice_pools.json pools.suzuran.command；ult_audio.json ops.suzuran.voice_alt |
| `voice/suzuran_entry_3.ogg` | char_358_lisa CN_017 | voice_pools.json pools.suzuran.entry；ult_audio.json ops.suzuran.voice_alt |
| `voice/suzuran_entry_4.ogg` | char_358_lisa CN_019 | voice_pools.json pools.suzuran.entry；voice_pools.json pools.suzuran.command；voice_pools.json pools.suzuran.battle |
| `voice/suzuran_skill_1.ogg` | char_358_lisa CN_025 | voice_pools.json pools.suzuran.skill；ult_audio.json ops.suzuran.voice |
| `voice/suzuran_skill_2.ogg` | char_358_lisa CN_026 | voice_pools.json pools.suzuran.skill |
| `voice/suzuran_skill_3.ogg` | char_358_lisa CN_027 | voice_pools.json pools.suzuran.skill；ult_audio.json ops.suzuran.voice_alt |
| `voice/texas_battle.ogg` | char_102_texas CN_028 | voice_pools.json pools.texas.skill；voice_pools.json pools.texas.battle |
| `voice/texas_battle_2.ogg` | char_102_texas CN_020 | voice_pools.json pools.texas.battle |
| `voice/texas_command.ogg` | char_102_texas CN_022 | voice_pools.json pools.texas.command |
| `voice/texas_command_2.ogg` | char_102_texas CN_021 | voice_pools.json pools.texas.command |
| `voice/texas_command_3.ogg` | char_102_texas CN_018 | voice_pools.json pools.texas.command |
| `voice/texas_entry.ogg` | char_102_texas CN_023 | voice_pools.json pools.texas.entry；ult_audio.json ops.texas.voice_alt |
| `voice/texas_entry_2.ogg` | char_102_texas CN_024 | voice_pools.json pools.texas.entry；voice_pools.json pools.texas.command |
| `voice/texas_entry_3.ogg` | char_102_texas CN_017 | voice_pools.json pools.texas.entry |
| `voice/texas_entry_4.ogg` | char_102_texas CN_019 | voice_pools.json pools.texas.entry；voice_pools.json pools.texas.battle |
| `voice/texas_skill_1.ogg` | char_102_texas CN_025 | voice_pools.json pools.texas.skill |
| `voice/texas_skill_2.ogg` | char_102_texas CN_026 | voice_pools.json pools.texas.skill |
| `voice/texas_skill_3.ogg` | char_102_texas CN_027 | voice_pools.json pools.texas.skill；ult_audio.json ops.texas.voice_alt |
| `voice/texas_ult.ogg` | char_102_texas CN_030 | ult_audio.json ops.texas.voice |
| `voice/ulpianus_battle.ogg` | char_4145_ulpia CN_028 | voice_pools.json pools.ulpianus.skill；voice_pools.json pools.ulpianus.battle；ult_audio.json ops.ulpianus.voice_alt |
| `voice/ulpianus_battle_2.ogg` | char_4145_ulpia CN_020 | voice_pools.json pools.ulpianus.battle |
| `voice/ulpianus_command.ogg` | char_4145_ulpia CN_021 | voice_pools.json pools.ulpianus.command |
| `voice/ulpianus_command_2.ogg` | char_4145_ulpia CN_022 | voice_pools.json pools.ulpianus.command；ult_audio.json ops.ulpianus.voice |
| `voice/ulpianus_command_3.ogg` | char_4145_ulpia CN_018 | voice_pools.json pools.ulpianus.command |
| `voice/ulpianus_entry.ogg` | char_4145_ulpia CN_023 | voice_pools.json pools.ulpianus.entry |
| `voice/ulpianus_entry_2.ogg` | char_4145_ulpia CN_024 | voice_pools.json pools.ulpianus.entry；voice_pools.json pools.ulpianus.command；ult_audio.json ops.ulpianus.voice_alt |
| `voice/ulpianus_entry_3.ogg` | char_4145_ulpia CN_017 | voice_pools.json pools.ulpianus.entry |
| `voice/ulpianus_entry_4.ogg` | char_4145_ulpia CN_019 | voice_pools.json pools.ulpianus.entry；voice_pools.json pools.ulpianus.battle |
| `voice/ulpianus_skill_1.ogg` | char_4145_ulpia CN_025 | voice_pools.json pools.ulpianus.skill |
| `voice/ulpianus_skill_2.ogg` | char_4145_ulpia CN_026 | voice_pools.json pools.ulpianus.skill |
| `voice/ulpianus_skill_3.ogg` | char_4145_ulpia CN_027 | voice_pools.json pools.ulpianus.skill；ult_audio.json ops.ulpianus.voice_alt |
| `voice/wisadel_battle.ogg` | char_1035_wisdel CN_028 | voice_pools.json pools.wisadel.skill；voice_pools.json pools.wisadel.battle |
| `voice/wisadel_battle_2.ogg` | char_1035_wisdel CN_020 | voice_pools.json pools.wisadel.battle；ult_audio.json ops.wisadel.voice |
| `voice/wisadel_command.ogg` | char_1035_wisdel CN_024 | voice_pools.json pools.wisadel.entry；voice_pools.json pools.wisadel.command |
| `voice/wisadel_command_2.ogg` | char_1035_wisdel CN_021 | voice_pools.json pools.wisadel.command |
| `voice/wisadel_command_3.ogg` | char_1035_wisdel CN_022 | voice_pools.json pools.wisadel.command |
| `voice/wisadel_command_4.ogg` | char_1035_wisdel CN_018 | voice_pools.json pools.wisadel.command |
| `voice/wisadel_entry.ogg` | char_1035_wisdel CN_023 | voice_pools.json pools.wisadel.entry |
| `voice/wisadel_entry_2.ogg` | char_1035_wisdel CN_017 | voice_pools.json pools.wisadel.entry |
| `voice/wisadel_entry_3.ogg` | char_1035_wisdel CN_019 | voice_pools.json pools.wisadel.entry；voice_pools.json pools.wisadel.battle |
| `voice/wisadel_skill_1.ogg` | char_1035_wisdel CN_025 | voice_pools.json pools.wisadel.skill |
| `voice/wisadel_skill_2.ogg` | char_1035_wisdel CN_026 | voice_pools.json pools.wisadel.skill；ult_audio.json ops.wisadel.voice_alt |
| `voice/wisadel_skill_3.ogg` | char_1035_wisdel CN_027 | voice_pools.json pools.wisadel.skill；ult_audio.json ops.wisadel.voice_alt |
| `voice/wisadel_w_laugh.ogg` | char_113_cqbw CN_028 | （未在池表 / 终结技表中引用；sfx.gd:661 按 <干员>_<事件> 主名直接加载） |

## 表 2　B 类：有授权的录音素材（83）

授权依据：Sonniss GDC 2026 Game Audio Bundle 免版税可商用、不需署名、不得再分发 / AI 训练（docs/113 §20）；Freesound / Kenney 条目为 CC0 1.0（docs/113 §7–§8、§14–§15、§20，脚本内逐条核对许可页）。

| 文件 | 授权来源 | 依据 |
|---|---|---|
| `sfx/lamp_heart.wav` | Sonniss GDC 2026（344 Audio Cinematic Fight Vol.1「FGHTImpt_4 x Punch, Body 02」） | game/tools/gen_sfx_lamp_heart.py；f5aa99181 |
| `sfx/op_hoshiguma_hit.wav` | Kenney「Impact Sounds」impactMetal_heavy_001（CC0） | game/tools/import_sfx_cc0.py；547edc5f1；docs/113 §8 |
| `sfx/op_ulpianus_atk.wav` | Freesound 448917 Kp69606「Chain Rattling」CC0（叠合成风声 / 砸地） | game/tools/import_sfx_cc0.py；547edc5f1；docs/113 §8 / §11 |
| `sfx/op_ulpianus_s1.wav` | Freesound 541975 16bitstudios「grappling hook」CC0 | bf1a9d003；docs/113 §15 |
| `sfx/op_ulpianus_s3.wav` | Freesound 819711 DaVoiceActor「Chain Impact」CC0 | bf1a9d003；docs/113 §15 |
| `sfx/ult_angelina_*`（12：cast、lift、open、pulse_1、pulse_2、sf、slam_1、slam_2、slam_3、streak_1、streak_2、streak_3） | Sonniss GDC 2026 | gen_sfx_ult_seg_1030.py / gen_sfx_ult_cue_1101.py；2fc201977；docs/113 §20 |
| `sfx/ult_exusiai_*`（4：impact、pop_1、pop_2、pop_3） | Sonniss GDC 2026（ESM Explosion Small Blast + Booms_Vol2_214）；Sonniss GDC 2026（ESM Explosion Small Blast） | gen_sfx_ult_seg_1030.py / gen_sfx_ult_cue_1101.py；6a3695c76；docs/113 §20 |
| `sfx/ult_eyjafjalla_*`（10：bomb_1、bomb_2、bomb_3、cast、charge、ground、impact、lava_hit、sf、steam） | Sonniss GDC 2026 | gen_sfx_ult_seg_1030.py / gen_sfx_ult_cue_1101.py；e3397f4ba；docs/113 §20 |
| `sfx/ult_hoshiguma_*`（11：block、cast、charge、crack_1、crack_2、crack_3、crack_4、crack_5、pull、sf、sizzle） | Sonniss GDC 2026 | gen_sfx_ult_seg_1030.py / gen_sfx_ult_cue_1101.py；04402c51e；docs/113 §20 |
| `sfx/ult_irene_*`（7：boom_1、boom_hit、cast、cut_1、cut_2、cut_3、impact） | Sonniss GDC 2026 | gen_sfx_ult_seg_1030.py / gen_sfx_ult_cue_1101.py；b50ca496a；docs/113 §20 |
| `sfx/ult_kaltsit_*`（6：cast、charge、gather_1、gather_2、gather_3、sf） | Sonniss GDC 2026 | gen_sfx_ult_seg_1030.py / gen_sfx_ult_cue_1101.py；04402c51e；docs/113 §20 |
| `sfx/ult_logos_*`（5：cast、charge、glyph_1、glyph_2、glyph_3） | Sonniss GDC 2026；Sonniss GDC 2026（低音下坠 / 钟 / 闩扣 / 冰箱嗡鸣等）；Sonniss GDC 2026（教堂钟 / 碎钹 / 古董钟） | gen_sfx_ult_seg_1030.py / gen_sfx_ult_cue_1101.py；519b22240；docs/113 §20；gen_sfx_ult_seg_1030.py / gen_sfx_ult_cue_1101.py；b50ca496a；docs/113 §20；gen_sfx_ult_seg_1030.py / gen_sfx_ult_cue_1101.py；b7bb52803；docs/113 §20 |
| `sfx/ult_ready.wav` | Sonniss GDC 2026（CB Sounddesign Kalimba + CSD Ting Coins，gen_sfx_ult_cue_1101.py） | gen_sfx_ult_seg_1030.py / gen_sfx_ult_cue_1101.py；50ce27c64；docs/113 §20 |
| `sfx/ult_saria_air.wav` | Sonniss GDC 2026（CSD Woosh Debris） | gen_sfx_ult_seg_1030.py / gen_sfx_ult_cue_1101.py；f474005ba；docs/113 §20 |
| `sfx/ult_super_5.wav` | Sonniss GDC 2026（344 Audio 风冲 + CSD Glassy Snap + Arp Reveal，gen_sfx_ult_cue_1101.py） | gen_sfx_ult_seg_1030.py / gen_sfx_ult_cue_1101.py；38e35d098；docs/113 §20 |
| `sfx/ult_suzuran_cast.wav` | Sonniss GDC 2026（Kopeikin astral travel） | gen_sfx_ult_seg_1030.py / gen_sfx_ult_cue_1101.py；b50ca496a；docs/113 §20 |
| `sfx/ult_texas_*`（9：cast、cut、impact、mark_1、mark_2、mark_3、mark_4、mark_5、mark_6） | Freesound 611310 IENBA「Dagger」CC0；Sonniss GDC 2026 | gen_sfx_ult_seg_1030.py / gen_sfx_ult_cue_1101.py；485682bfe；docs/113 §20；gen_sfx_ult_seg_1030.py / gen_sfx_ult_cue_1101.py；916986945；docs/113 §20 |
| `sfx/ult_ulpianus_*`（10：anchor、cast、charge、crack_hit、dash、impact、sf、splash_1、splash_2、splash_3） | Sonniss GDC 2026；游戏内 op_ulpianus_s1（Freesound 541975 16bitstudios「grappling hook」CC0） | gen_sfx_ult_seg_1030.py / gen_sfx_ult_cue_1101.py；758493727；docs/113 §20 |

## 表 3　C 类：程序合成（178）

| 文件 | 生成脚本（依据） | 写入提交 |
|---|---|---|
| archive_v2.ogg、boss_down.ogg、boss_in.ogg、opening.ogg（4） | `game/tools/gen_music.py（docs/21「原有曲目程序化合成」）` | 878e31341 |
| boom.wav、dodge.wav、heartbeat.wav、hit.wav、hurt.wav、kill.wav、levelup.wav、oil.wav、pickup.wav、relic.wav、roar.wav、skill.wav、start.wav、swing.wav、swing_heavy.wav、tentacle.wav、ui_move.wav、ui_ok.wav（18） | `game/tools/gen_sfx.py（脚本头「原创音效合成」）` | 303e6e3c6、e45320fad |
| apop_pause.wav、apop_resume.wav、bishop_panic.wav、carmen_sword.wav、cocoon_form.wav、cocoon_revive.wav、ishar_land_break.wav、izu_absorb.wav、izu_lamp_lit.wav、izu_wave_count.wav、paranoia_land_break.wav、shell_break.wav、stake_hit.wav、stake_shatter.wav（14） | `game/tools/gen_sfx_boss_events.py` | 0e60dd5df、3ad2726f8、fb4f911a8 |
| break_hit.wav（1） | `game/tools/gen_sfx_break_hit_1028.py（be5f26f28 候选 C）` | be5f26f28 |
| op_siege_s1_soft.wav、op_texas_s2_soft.wav（2） | `game/tools/gen_sfx_cmd_cue_1028.py（1e8c83858）` | 1e8c83858 |
| enemy_bite.wav、enemy_screech.wav、enemy_spit.wav、op_wisadel_atk.wav、op_wisadel_big.wav、op_wisadel_hit.wav（6） | `game/tools/gen_sfx_combat.py（脚本头「no sampled game recordings」；4d5f3873c）` | 4d5f3873c |
| boss_archon.wav、boss_bishop.wav、boss_carmen.wav、boss_iberia.wav、boss_immortal.wav、boss_ishar.wav、boss_izumik.wav、boss_knight_boss.wav、boss_paranoia.wav、boss_path.wav、cue_beam_hit.wav、cue_beam_start.wav、cue_charge_hit.wav、cue_charge_start.wav、cue_global_hit.wav、cue_global_start.wav、cue_land_hit.wav、cue_land_start.wav、cue_melee_hit.wav、cue_melee_start.wav、cue_phase_start.wav（21） | `game/tools/gen_sfx_cues.py` | 9560d1a6b、9fdaecf31 |
| atk_gate.wav、beacon_end.wav、beacon_fizzle.wav、beacon_lit.wav、beacon_tick.wav、break_open.wav、crit_tick.wav、enemy_acid.wav、enemy_elite.wav、enemy_nerve.wav、heartbeat_hi.wav、hunt_break.wav、hunt_close.wav、hunt_warn.wav、knight_charge.wav、knight_frost.wav、knight_stab.wav、lamp_empty.wav、mire_clear.wav、mire_splat.wav、nerve_burst.wav、ulp_charge_loop.wav、ulp_release.wav（23） | `game/tools/gen_sfx_events.py` | 0fe0d3220、2cc843fcb、3adead6c8、5e137c828、9a8d3d48a、b3aa1214b |
| op_exusiai_hit.wav（1） | `game/tools/gen_sfx_exu_hit_1027.py（hit_a）（221397e14 / docs/113_exusiai*.md §19.x「无音高闷响」）` | 221397e14 |
| op_exusiai_s1.wav、op_exusiai_s2.wav、op_exusiai_s3.wav（3） | `game/tools/gen_sfx_exu_sync_1028.py --apply（cc9d28848 机械「咔」提示，cue_s1/2/3 纯噪声 + 正弦）` | cc9d28848 |
| op_irene_hit.wav、op_suzuran_hit.wav、op_texas_hit.wav（3） | `game/tools/gen_sfx_hit_dding_1028.py（b3d466a19 去「叮」命中音）` | b3d466a19 |
| op_lumen_hit.wav（1） | `game/tools/gen_sfx_hit_dding_1028.py（现版 blob a323fe53 = b3d466a19 去叮合成版；e2cc16f93 原作剪辑版已由 0d0517382 退回，main 同）` | 0d0517382 |
| hurt_heavy.wav、kill_big.wav、kill_shell.wav、op_logos_hit.wav（4） | `game/tools/gen_sfx_hitfeel.py（0cc949ea2「合成…四个正式音」）` | 0cc949ea2 |
| lamp_out.wav（1） | `game/tools/gen_sfx_lamp.py` | 81f44c3ba |
| op_lumen_atk.wav（1） | `game/tools/gen_sfx_ops.py（现版 blob 0b481a60 = 4e648a32e 合成版；e2cc16f93 原作剪辑版已由 0d0517382 退回，main 同）` | 0d0517382 |
| op_eyjafjalla_atk.wav、op_eyjafjalla_big.wav、op_eyjafjalla_hit.wav、op_eyjafjalla_s1.wav、op_eyjafjalla_s2.wav、op_eyjafjalla_s3.wav、op_irene_atk.wav、op_irene_big.wav、op_irene_s1.wav、op_irene_s2.wav、op_irene_s3.wav、op_kaltsit_atk.wav、op_kaltsit_big.wav、op_kaltsit_heal.wav、op_kaltsit_s1.wav、op_kaltsit_s2.wav、op_kaltsit_s3.wav、op_logos_atk.wav、op_logos_big.wav、op_logos_s1.wav、op_logos_s2.wav、op_logos_s3.wav、op_lumen_big.wav、op_lumen_s1.wav、op_lumen_s2.wav、op_lumen_s3.wav、op_mizuki_atk.wav、op_mizuki_hit.wav、op_mizuki_s1.wav、op_mizuki_s2.wav、op_mizuki_s3.wav、op_saria_atk.wav、op_saria_hit.wav、op_saria_s1.wav、op_saria_s2.wav、op_saria_s3.wav、op_siege_atk.wav、op_siege_big.wav、op_siege_hit.wav、op_siege_s1.wav、op_siege_s2.wav、op_siege_s3.wav、op_skadi_atk.wav、op_skadi_big.wav、op_skadi_hit.wav、op_skadi_s1.wav、op_skadi_s2.wav、op_skadi_s3.wav、op_specter_unchained_atk.wav、op_specter_unchained_s1.wav、op_specter_unchained_s2.wav、op_specter_unchained_s3.wav、op_suzuran_atk.wav、op_suzuran_s1.wav、op_suzuran_s2.wav、op_suzuran_s3.wav、op_ulpianus_big.wav、op_ulpianus_s2.wav、op_wisadel_quake.wav、op_wisadel_s1.wav、op_wisadel_s2.wav、op_wisadel_s3.wav（62） | `game/tools/gen_sfx_ops.py（脚本头「全部程序合成…不使用任何游戏原始音频」；4e648a32e）` | 4e648a32e |
| op_texas_atk.wav（1） | `game/tools/gen_sfx_review_texas_1024.py --apply（0753ae893「换合成版起冲」）` | 0753ae893 |
| ult_texas_sf.wav（1） | `gen_sfx_ult_seg_1030.py（FLASH 程序合成（_sf_core + slash + metal））` | 916986945 |
| ult_exusiai_sf.wav（1） | `gen_sfx_ult_seg_1030.py（FLASH 程序合成）` | 6a3695c76 |
| ult_texas_charge.wav（1） | `gen_sfx_ult_seg_1030.py（程序合成 sweep_noise + metal）` | 916986945 |
| hh_burst.wav、hh_card.wav、hh_done.wav、hh_drop.wav、hh_hum.wav、hh_reveal.wav、hh_star6.wav、hh_zip.wav（8） | `tools/gen_hh_sfx.py（脚本头「全部程序合成…不含任何原作音频」）` | f992fab77 |
| ui_shutter.wav（1） | `tools/gen_shutter_sfx.py` | 5264a3b0e |

## 表 4　D 类：待查（1）

| 文件 | 已知情况 | 为什么查不清 |
|---|---|---|
| `music/shop.ogg` | fa57a8c21 / 36867d2c7（10-27）「replace merchant BGM with supplied intro and loop」；docs/21_music_design.md §商人配乐替换：来源为用户指定的 `E:/download_chrome/m_sys_rglk1shop_intro.mp3` + `m_sys_rglk1shop_loop.mp3`，拼接后降采样 32 kHz。调用：game/scripts/sfx.gd:96 `'shop': ['shop']`、:219 商店分支（docs/21 表 `S.SHOP`） | 仓库只记「用户提供的 mp3」，没写这两个 mp3 从哪来、有无授权。文件名 `m_sys_rglk1shop_*` 与明日方舟客户端音乐资源命名一致（rglk1 = 集成战略第一期商店曲），**高度疑似原作客户端 BGM**，但仓库内没有直接证据，按要求不归 A，需向用户确认出处 |

## 附　E 类：不属 A/B/C 的已知来源（22，Suno AI 生成配乐）

依据：提交说明 70417b729「Suno 新配乐接入」、916a22501「结局二 / 三 / 四最终 Boss 接 Suno 分轨分层曲」、7e8296b92「配乐换 Suno 第一批」、5fb1e37d3「标题曲换 Suno《Deep Ocean Drift》」；处理脚本 tools/suno_track.py、tools/suno_layers.py；docs/164_suno_layers.md。仓库内未找到 Suno 订阅档 / 商用条款的记录，credits.json 也未提 Suno。

| 文件 | 依据 |
|---|---|
| `music/deploy.ogg` | 7e8296b92「标题曲与出发前重做」 |
| `music/final_suno.ogg` | 7e8296b92《The Deep Sea Awakens》 |
| `music/suno_archive_full.ogg` | 70417b729 |
| `music/suno_battle1_base.ogg` | 70417b729 |
| `music/suno_battle1_drive.ogg` | 70417b729 |
| `music/suno_battle1_pulse.ogg` | 70417b729 |
| `music/suno_battle2_base.ogg` | 70417b729 |
| `music/suno_battle2_drive.ogg` | 70417b729 |
| `music/suno_battle2_pulse.ogg` | 70417b729 |
| `music/suno_battle3_base.ogg` | 70417b729 |
| `music/suno_battle3_drive.ogg` | 70417b729 |
| `music/suno_battle3_pulse.ogg` | 70417b729 |
| `music/suno_boss_full.ogg` | 70417b729 |
| `music/suno_final_ishar_p1.ogg` | 916a22501 |
| `music/suno_final_ishar_p2.ogg` | 916a22501 |
| `music/suno_final_izumik_p1.ogg` | 916a22501 |
| `music/suno_final_izumik_p2.ogg` | 916a22501 |
| `music/suno_final_knight_p1.ogg` | 916a22501 |
| `music/suno_final_knight_p2.ogg` | 916a22501 |
| `music/suno_final_p1.ogg` | 70417b729 |
| `music/suno_final_p2.ogg` | 70417b729 |
| `music/title.ogg` | 5fb1e37d3 / 7e8296b92 Suno《Deep Ocean Drift》 |

