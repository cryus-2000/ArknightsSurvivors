# 博士新画风接入 · 2026-10-18

用户已确认第二版大兜帽、短身比例和 run_pose_reference_01 跑步姿势，并批准三套像素候选接入游戏。

- 权威素材：doctor_idle、doctor_run、doctor_death，各含 1x / @2x。对应文件 SHA256 和源稿记录见 doctor_style_manifest.json。
- 1x 每帧 64×64，脚底 (32,60)；@2x 每帧 128×128，脚底 (64,120)，待机可见高约 80 px。
- 待机 4 帧 / 4 fps；跑步 8 帧 / 10 fps（0.8 秒）；倒下 4 帧 / 6 fps，末帧保持。倒下首帧与待机首帧完全相同。
- 替换三套完整动作；hurt 保留旧素材及 hurt_foot (24,46)，运行时仍不调用。
- 局内和主页封面都读 doctor.json 的新原点；缺图退回旧 doctor 贴图时仍用其原点 (24,45)。
- 移除旧版 outline / frontal / run 临时豁免。新版 art_lint 无 FAIL，明度与相对旧图亮度两项 WARN 保留原作深色服装和用户已确认色块，不改变通用门限。
- 生成参考与候选预览：codex-art/art/incoming/co_doctor_style_rework_1018/；本分支只交付权威 PNG 和元数据，不打包源稿/审阅大图。
- 运行时验收与测试包记录见 docs/plans/2026-10-18-doctor-style-integration.md。不修改玩法参数或随机数。
