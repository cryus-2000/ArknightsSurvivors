# 本地 Git 协作：Codex 美术 / Claude 开发

## 工作目录

| 角色 | 目录 | 分支 | 主要范围 |
|---|---|---|---|
| Claude | E:\ArknightsSurvivors | main | game/、接入、测试、构建 |
| Codex | E:\ArknightsSurvivors\.worktrees\codex-art | codex/art | art/incoming/、美术交接说明 |

两个工作目录共享本地 Git 提交历史，但文件各自独立。Codex 在美术目录修改不会立刻改变原目录里的游戏。不要在另一个代理的工作目录切换分支。

## 交接步骤

1. Codex 在自己的 worktree 内制作、检查美术，只暂存本次相关素材和交接文档，提交后提供提交编号与文件清单。
2. Claude 在原目录先检查 git status，提交或妥善保存自己的未提交修改，再查看待接收提交：

```powershell
git -C E:\ArknightsSurvivors show --stat <提交编号>
git -C E:\ArknightsSurvivors cherry-pick <提交编号>
```

3. Claude 按交接文档检查切帧、尺寸、动画和运行效果，完成接入后提交代码。
4. Codex 开始下一轮前，先确认自己的工作树干净，再在美术 worktree 执行 git merge main 同步开发结果。有冲突就检查并解决，不能用强制覆盖掩盖冲突。

不要直接照抄尖括号占位符；使用实际提交编号。不要跨工作树执行 reset --hard 或 git clean。

## 查看状态

```powershell
git -C E:\ArknightsSurvivors status --short --branch
git -C E:\ArknightsSurvivors worktree list
git -C E:\ArknightsSurvivors log --oneline --all --graph -12
```

## 初始版本与范围

初始提交是现有文件快照，包含已交付的怪物 V2、美术文档及当前游戏源码，不代表代码已经通过测试。
第三方工具 tools/godot-mcp/、Godot 缓存、node_modules、build/ 和 art/backup_*/ 保留在本机但不纳入 Git。游戏实际使用的 game/addons/ 仍纳入版本控制。

当前没有远程仓库，不会上传文件，也不会自动启动 Claude 或传递聊天消息。用户可以将提交编号和交接说明转给另一方。若未来需要跨电脑协作，再单独配置远程仓库。
