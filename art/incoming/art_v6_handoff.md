# V6 美术交付

依据 main 的 a227f75 / docs/10_art_v6_spec.md。共 20 张 PNG、83 帧。仅美术交付，未修改游戏代码。

## 文件

- ally_sniper_move / ally_caster_move / ally_medic_move / ally_support_move：48×48，6 帧，10fps，循环，锚点 (24,45)，倍率 1.4。
- proj_arrow：16×8，1 帧；proj_fireball：16×16，4 帧，12fps；proj_arcane：12×12，4 帧，12fps；proj_drone_bullet：8×4，1 帧；proj_missile：16×8，2 帧，16fps；proj_tide：12×12，4 帧，10fps。均朝右、中心锚点，倍率 2；多帧循环。
- fx_fire_explode / fx_missile_explode：64×64，6 帧，15fps，播一次，锚点 (32,32)。两者 radius_px 均为 26；按伤害半径 / 26 缩放并限制 1.5–3.0。火球橙红火焰，导弹白黄闪光、金属碎片和灰烟。
- fx_arrow_hit：16×16，4 帧，20fps；fx_bullet_hit：12×12，3 帧，24fps；fx_arcane_hit / fx_tide_hit：24×24，4 帧，20fps；fx_heal_cross：12×12，4 帧，10fps。均播一次、中心锚点、倍率 2；箭矢命中随箭方向旋转。
- fx_laser_start / fx_laser_end：16×16，4 帧，20fps，锚点 (8,8)。fx_laser_mid：16×8，4 帧，20fps，锚点 (0,4)。均循环、倍率 2。

完整逐文件参数与生成来源 ID 见 art_v6_manifest.json。单帧资源 fps=0、loop=false，直接作为静态纹理使用。

## 验证

- 20 项尺寸、帧数、非空帧、二值 Alpha (0/255) 检查通过；多帧资源的各帧均不同。
- 新增移动与已有待机、攻击最大脚底 Y 均为 45。实际切换时的角色尺寸、动作连贯性仍需在 Godot 中验收。
- 爆炸使用统一比例，保留从小到大再消散的过程；radius_px 取六帧中最大连通主体的最远像素到锚点距离向上取整。
- 激光中段四帧逐像素左右边缘相同；16 段平铺静态检查通过。
- art_v6_qa.png 展示投射物 0/45/90 度、爆炸 1.5/3 倍与四相激光平铺。
- art_v6_preview.png 为整批帧条预览；art_v6_preview.html 是离线动画预览，可暂停，预览中的一次性特效为便于检查而重复播放。

## Claude 接入

按 docs/10_art_v6_spec.md 切帧、设置锚点和状态优先级。移动中攻击仍继续跟随；攻击朝目标、移动朝速度方向、待机朝水月。干员无受击/倒地动画。

程序继续负责拖尾、医疗连线、辅助光环、流血地面、爆炸伤害圈、旋转缩放、激光平铺裁切和淡入淡出。激光中段不要拉伸整图，按帧裁切后平铺。

本轮未运行 Godot 接入测试；请重点验收状态切换脚底、碰撞与视觉范围、动态旋转采样和光束首尾衔接。PNG 原稿经图像生成后以最近邻导出，添加 #080E18 像素外描边；预览不代表运行时最终发光效果。
