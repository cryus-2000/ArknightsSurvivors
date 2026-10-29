# 第一批完整动画交接

依据 claude/ultimate-design 提交 975cfaf31 动画单与 v2 规格，承接关键帧提交 9f956fcf0。16 条完整 @2x 横排帧条、106 帧、16 个 MP4、一张总览均完成。review.html 只展示最终动画。

生产纹理位于本目录 fx_ult_*@2x.png，规格见 manifest.json。RGBA 合计 17.5234375 MiB，各文件低于 5 MiB。animation_previews 视频无声、30 fps，先黑底后当前游戏 tiles.png 暗地面，按源 fps 原速播放；最大 749002 bytes。巨锚为四个角度帧，原规格 fps 为 null，预览标明程序旋转示意 180°/s，此速度不是玩法参数。

- 光束保留用户确认 review_draw_width=80；纹理仍为192×80 @2x。显示宽度与纹理大小分开记录。
- 剑雨保留原素材0–4帧顺序及20fps，第6帧追加插地屑。代表帧由旧快照f3改为完整条f4，避免打乱原动作顺序。
- 六个拼接段每帧两端RGBA一致；参考半径、角度见metadata。任意半径或缩放仍需引擎检查。
- 海嗣 front/back 局部原点分别为[160,316]/[160,48]，绑定同一世界脚底。front0–9到back映射为[0,0,1,1,2,2,3,4,5,5]；front6–7与back3–4同步循环。
- Mon3tr melt/rebuild为FX-only；同索引原骨架guide仅供预览，实机不要重复叠第二只本体。melt guide只在0–4帧可见。重构原点[128,253]统一上移1物理像素，避免中途脚底裁切。
- 原骨架动作按任务单时长取样，时间映射在source_time_mapping_note；不宣称保留原动作总时长。全部源与哈希在分组metadata。

animation_qa.json记录16条尺寸/帧数/输出哈希、逐帧接缝、透明RGB、预算和16个视频完整解码/30fps通过。已复看全帧接触表、海嗣对位和Mon3tr组合。

重建用D:/Anaconda/python.exe -X utf8执行 animation_work 下三组build，再执行assemble_animation.py、render_animation_previews.py、verify_animation.py。分组构建读取冻结的animation_keyframe_manifest.json，避免误读已升级的manifest。

完整素材与预览已交，尚待Claude接入claude/ult-proto实机验收；未修改game/，本交接随完整动画提交，未合并main。旧handoff.md与关键帧留作历史，当前交接以本文件为准。
