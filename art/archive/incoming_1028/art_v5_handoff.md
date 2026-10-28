# 美术 V5：援护动作、无人机、Boss 移动

本轮17张生产PNG，共68帧。全部为横向4帧，二值透明，最近邻像素，外轮廓#080E18。原来的待机、本体不覆盖。未修改游戏代码、未运行Godot实机验收。

## 援护攻击

| 文件 | 单帧 | 动作 |
|---|---|---|
| ally_sniper_attack.png | 72×48 | 准备→拉弓→放箭→收弓 |
| ally_caster_attack.png | 72×48 | 准备→举杖→施术→恢复 |
| ally_medic_attack.png | 72×48 | 准备→取医疗工具→治疗→恢复 |
| ally_support_attack.png | 72×48 | 准备→蓄能→释放辅助术式→恢复 |

画布横向加宽，为伸手/武器留空间；不应按72宽把人物整体缩回48宽。脚底锚点(24,45)，归一化(1/3,45/48)，保持与待机同一世界脚底位置。镜像时同时镜像绘制偏移，不能继续将24当镜像后的局部锚点。建议8fps单次播放，零基第2帧触发投射物/治疗/辅助效果。这里提供动作及局部小特效，远距离箭矢、光束、爆炸、治疗判定仍由开发端实现。保持当前职业名称，医疗不变成伤害攻击。

## 无人机

| 文件 | 单帧 | 外观 |
|---|---|---|
| drone_bullet.png | 48×40 | 双涵道旋翼、小口径枪管、橙色枪焰 |
| drone_laser.png | 48×40 | 青色聚焦镜、短激光发射效果 |
| drone_missile.png | 48×40 | 双侧导弹舱、发射瞬间 |

0/1帧用于悬浮循环，2帧为发射，3帧回稳。建议悬浮6fps，发射8fps。中心锚点(24,20)。帧条中短光束、离架导弹是发射局部表现，持续光束长度、飞行导弹和命中爆炸需要另行实现，不可通过拉伸整架无人机实现光束。

造型采用方舟无人机的工业机械语言做本作友方适配，不标称某款原作无人机的逐像素复刻。“子弹→激光→导弹”为本作升级路线，不是原作统一进化链。御4本身是支援无人机，不把它称为原作机枪机。法术攻击也不直接等同原作激光武器。
设定核对来源：[御4](https://prts.wiki/w/御4)、[法术大师A1](https://prts.wiki/w/法术大师A1)、[暴鸰](https://prts.wiki/w/暴鸰)。
当前核对到的game/scripts中尚未找到drone实体资源名，因此三个文件是新增预备资产，需要开发端注册和接入。

## Boss 移动

| 文件 | 单帧 | 动作 |
|---|---|---|
| e_carmen_move.png | 40×48 | 迈步、衣摆摆动 |
| e_iberia_move.png | 40×48 | 迈步、披衣和帽羽摆动 |
| e_bishop_move.png | 40×48 | 持杖慢行、袍摆移动 |
| e_archon_move.png | 44×44 | 恐鱼交替足爬行 |
| e_immortal_move.png | 42×40 | 快速伸展/收拢四肢 |
| e_path_move.png | 56×56 | 低伏爬行、背部触须摆动 |
| e_paranoia_move.png | 72×72 | 悬浮、触须左右扫动 |
| e_paranoia_phase2_move.png | 72×72 | 二阶段触须展开循环 |
| e_izumik_move.png | 72×72 | 伞体收缩、触须游动 |
| e_ishar_move.png | 80×80 | 漂浮、裙摆与青色飘带摆动 |

覆盖当前data.gd的9种Boss，加偏执泡影二阶段。最后的骑士、延命塑路者不在当前9种Boss表内，本次不新增它们的本体或移动资产。
建议一般移动6fps，斥亡体8fps，悬浮4~6fps。保持原本体尺寸和绘制倍率。停下时使用已有本体/待机，不把移动循环用作攻击、眩晕或死亡。移动图不包含世界坐标位移。
注意当前代码中有 e_paranoia2 名称，而已有交付素材是 e_paranoia_phase2。本次沿用已交付素材名，不擅自改代码；开发端须显式建立二阶段映射。

## 预览、验证、制作

- art_v5_preview.html：自包含动画预览，可暂停、逐帧和调速，非游戏截图。
- allies_attack_preview.png / drone_preview.png / boss_move_preview.png：静态帧条检查图。
- art_v5_manifest.json：精确尺寸、锚点、建议帧率、触发帧、每帧边界、相邻帧差异、SHA256及生成源编号。
- 17张全部通过尺寸、每帧非空、alpha仅0/255、四周留白、每对相邻帧实际变化检查；已目视检查三张联系表。游戏中动画切换、战斗时序、碰撞与性能由开发端验证。
- 使用内置imagegen基于现有美术参考生成，随后像素采样、锚点整理、描边与透明背景清理。一些生成底稿带绘制的棋盘格，已清理外部相连背景，保留角色内部浅色区域。未交付这些生成底稿。

### 提示词集
共同约束：FOUR FRAME horizontal strip in four equal cells, transparent background, preserve approved identity/costume/palette, full body in every cell, fixed scale and baseline, coarse pixel art, #080E18 outline, no text, no antialiasing.
援护动作：bow ready/draw/release/recovery；wand ready/raise/cast/recovery；medical bag ready/reach/heal/recovery；support focus ready/charge/release/recovery。现有ally_*为身份参考。
无人机：Rhodes Island friendly adaptation of Arknights industrial drones; offwhite/charcoal armor, twin ducted rotors, cyan sensors, orange safety marks; light gun / cyan focusing lens / twin missile pods; hover1/hover2/fire/recover。
Boss：animate existing approved e_* sprite without redesign; alternating steps/robe sway for humanoids, articulated quadruped gait for fish, tentacle sweep or jellyfish bell contraction for hovering units; no baked world translation。
