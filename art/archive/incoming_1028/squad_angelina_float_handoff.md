# Codex: 安洁莉娜浮空帧条（docs/92）

交付 8 PNG（48×48 / 96×96 横排）、manifest、完整流程预览 GIF、原样 art_lint QA 与补充 QA。仅 art/incoming/，未改 game/ 或检查器。原四组动作保持不变。沿用已批准精零造型、法杖和原有 23 色色板。

## 动作与锚点
- float_in：4帧12fps，f0=原idle f0，f1屈膝蓄力，f2离地，f3=float f0。最低行 1x [46,46,42,38]，@2x [92,92,84,76]。
- float：6帧8fps，循环，双腿下垂、脚尖向下。最低行 [38,37,37,38,39,39] / [76,74,74,76,78,78]；后侧衣发随动延后，头脸与法杖沿用相同像素。
- float_move：6帧10fps，循环，整体前倾滑行，腿并拢后拖，不交替迈步。最低行 [38,37,38,39,38,37] / [76,74,76,78,76,74]。为避免杖头出格收敛横向幅度。
- float_attack：5帧12fps，出手 f2；使用原attack各帧上身挥杖动作，悬垂腿替换落地腿。杖头仰角和横向幅度调整以容纳离地后的画布。末帧=float f0。全部最低行38 / 76。
- 画布锚点保持(24,46)/(48,92)，实际脚底中心1x约23.0–23.5，@2x折算23.25–24.0，符合24±2。不画阴影、弹体、重力球或光效。
- 起飞f0、起飞f3与float f0、attack末帧与float f0：两种分辨率逐像素相等。帧边界检查通过，无武器截断。

## 检查结果（区分旧动作与新交付）
执行 python tools/art_lint.py --ops angelina --json <qa>，退出0，未豁免FAIL=0；输出原样在 squad_angelina_float_qa.json。
当前检查器按 game/data 配置只读旧四组动作；不能把上述结果当作新浮空组已自动覆盖。本次额外用未改动的 lint_op 把每条新帧条作为主体动作检查，结果在 squad_angelina_float_extra_qa.json：files/size/pair/alpha/outline/colors/magenta 全PASS。配对剪影差最大0.054；每条22–23色；总色板仍23色；二值透明；外圈100% #080E18。另验证38±1离地、四边不截断和三处精确衔接。
朝向目测仍为原有朝右3/4，法杖在身前右侧，头颈随躯干倾斜。新增动作未套用地面跑步交替腿判据。

### 旧动作的三项WARN（本单不改）
1. outline：原有@2x第二圈0.969，外圈1.000。新增帧条单独检查为PASS。
2. skill_end：原有48px skill末帧不等于idle f0，@2x相同。本单起飞f0严格保留各自idle f0。
3. tone：原有idle近黑8%，低于10%建议值；HSL0.461、亮部21%、受光变亮8%。本单保持批准配色，不擅自压暗旧动作。
因此不能称整个人物所有检查无WARN，但无FAIL；新增基础检查均PASS。ground离地按docs/92设计，待Claude接入新sprites后登记例外。

## 预览与来源
GIF按 idle→skill→float_in→float两轮→float_move两轮→float_attack→float_in倒放→idle；最后附工具生成的compare_angelina缩略页，不额外增加第9张PNG。96px为主，预览最近邻放大。已目测对照图和动作联系表。
内置imagegen用于浮空/滑行腿部姿态母图，保留现有上身与脸部像素来避免逐帧闪烁；源文件哈希与提示摘要在manifest。48px由96px对应导出，起飞首帧例外直接复制原48px以保证精确衔接。
未验证引擎实机；请Claude接入四条sprites、出手f2、倒放落地和ground例外。本美术提交号由本文件所在提交确定，交回时单独给出。
