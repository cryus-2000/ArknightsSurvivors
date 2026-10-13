# docs/93 第2批

乌尔比安沿用四爪锚造型，出手3/回拉6；斯卡蒂沿用原大剑，出手4。新增动作首末为原idle逐像素复制，存量端点色数如实保留，中间帧收敛24色。逻各斯链段左右接缝循环平铺；艾雅法拉按审定低抛熔岩，不交旧落点预示圈。

每条尺寸、帧数、fps、原点、层和sha256见manifest。FX每条<=16色、二值alpha；光水不描边，实体1px/@2x2px。特效基于生图母版旋转/缩放/位移/抖动导出，@2x FX为最近邻放大；人物以高密度母版为主。预览为人物旁合成，2倍最近邻显示，GIF80ms近似帧间隔，运行时按manifest。所有帧非空、尺寸、透明检查通过；未改game/、未做引擎集成测试。

## 人物检查
常规art_lint另存lint_qa；本次新动作内存追加后使用未修改lint_op检查，未豁免FAIL 0。WARN如下（旧动作未改）：
- ulpianus colors: 1x 86 色 / @2x 91 色（存量，不卡）
- skadi colors: 1x 122 色 / @2x 139 色（存量，不卡）
- skadi skill_end: skill 末帧 ≠ idle f0（@2x 不同像素 26.6%；存量，重画 idle / skill 时对齐）
- skadi idle: 注意：身体起伏 0.5px；起伏 0.5px 剪影变化 0.122 停顿对 0
- skadi foot: idle 量得 x 25.9 vs json 22；run 量得 x 32.8 vs json 24

## Logos最新参考覆盖
用户要求使用悬浮白色萨卡兹经文，无黑底；已覆盖工单原黑带/暗金要求。形状参考用户字母表A/E/V，采用生图校正后的母版机械裁切、排版与滚动；不是通用星形符文。1x只保留可读几何轮廓，@2x最近邻对应。没有声称符号组合具有可验证的原作译文。材质仍为二值alpha，整体透明度由程序设置。

## 白色经文密排返修
chain_tile/pulse/anchor 已按用户反馈收紧；规格不变，详见 logos_dense_handoff.md 和 logos_dense_preview.gif。
