# Codex Pet · 小柯

一个 Windows 桌面编程搭子：16 套透明 GIF 动作、本地 Codex 使用量统计、四种界面语言。PowerShell 5.1 + WPF，无需额外安装运行库。

[English](README.en.md) · [下载 Windows 便携包](https://github.com/hahahaha0123/codex-pet/releases/latest) · [MIT License](LICENSE)

![小柯招手动画](GIF动作/举手打招呼.gif)

## 开始使用

1. 从 Releases 下载 Windows ZIP，解压到固定目录。
2. 双击 `start-pet.cmd`。首次启动自动创建本机配置。
3. 右键查看菜单；按住左键拖动，双击人物收起或展开卡片。

Windows 10 / 11，使用系统自带的 Windows PowerShell 5.1。也可直接克隆源码运行：

```powershell
git clone https://github.com/hahahaha0123/codex-pet.git
cd codex-pet
.\start-pet.cmd
```

启动器默认安装“随 Codex 启动”助手：它在当前用户登录时隐藏运行，检测到 Codex 桌面窗口打开后显示桌宠。手动退出桌宠后不会在同一个窗口内反复重开。右键可关闭，也可运行 `disable-follow-codex.cmd`；重新开启用 `enable-follow-codex.cmd`。

## 功能

- 16 个六帧 GIF：招手、跳跃、两种奔跑、伸懒腰、鞠躬、思考、害羞、大笑、惊讶、生气、哭泣、哈欠、睡觉、拥抱和托起代码方块。
- 工作、完成、待机、拖动和投喂会触发连续动画；右键也可播放任意动作。
- 右键“语言 / Language”即时切换简体中文、繁體中文、English、日本語，也可跟随系统；选择会保存。
- 整体缩放支持 20%–100%，默认 80%。人物和卡片同步调整，文字按实际像素重新排版。
- 自动跟随最近活跃的本地会话，或固定某个会话；项目名从 Codex 保存的信息中读取，改名和目录信息会刷新。
- 显示上下文百分比、任务平均输出速度、当前模型使用量和历史模型合计；点击历史合计展开明细。

双击 `动作预览.html` 可以同时查看全部 GIF。

## 数据口径与隐私

只读当前用户的本地 Codex 会话索引和日志，不读取登录凭据，不修改 Codex 数据，也不调用账户接口。

| 显示 | 统计范围 |
|---|---|
| 上下文 | 最近日志中的 `last_token_usage.total_tokens / model_context_window`，可能滞后 |
| 任务输出均速 | 当前选定任务的输出 token 增量 ÷ 任务经过时间；包含推理及工具等待，是任务平均吞吐，不是瞬时解码速度 |
| 当前模型 | 选定会话中此模型的输入、输出及缓存 tokens |
| 历史合计 | 本机可读日志，包含归档及子任务；处理累计计数、重复文件和分叉继承记录 |
| 金额 | USD 官方 API 文本 token 等价估算；不是订阅实际扣款，未知模型显示未定价部分 |

价格快照与计算限制见 [PRICE-SOURCES.md](PRICE-SOURCES.md)。已删除且从未索引过的日志无法恢复；已索引内容保存在本机缓存。首次历史索引在后台进行，后续增量更新。

运行状态与历史缓存位于 `state/`；位置、缩放、语言和固定会话在 `pet.config.json`；自动启动选择在 `follow.config.json`。这些本机文件、历史 ZIP 和截图日志不会提交到仓库。配置模板为 [pet.config.example.json](pet.config.example.json)。

## 开发与验证

不需要安装 Codex，也不需要账户即可运行合成样本测试：

```powershell
.\tools\Test-Data.ps1
.\tools\Test-Usage.ps1
.\tools\Test-History.ps1
.\tools\Test-Languages.ps1
.\CodexPet.ps1 -Preview -ExpandedPreview -Language en-US
```

测试覆盖重复累计快照、模型切换、缓存计价、历史恢复、归档与分叉去重、项目改名，以及语言资源和实时切换。可用 `-SmokeSeconds 6` 检查窗口，或 `-AnimationCheck` 检查所有 GIF 的实际换帧。GitHub Actions 在 Windows 上运行离线检查与预览渲染。

生成发布包：

```powershell
.\tools\Build-Release.ps1 -Version 2.6.0
```

重新导出素材需要额外安装 Pillow：先运行 `tools/Export-AnimationFrames.ps1`，再运行 `tools/Encode-Gifs.py`。正常使用桌宠不需要 Python。

## 素材与许可

[MIT](LICENSE)。角色图和连续帧由 ImageGen 为本项目生成，提示词及原始帧图均已提供，详见 [ASSETS.md](ASSETS.md)。这是社区项目，非 OpenAI 官方产品。

欢迎通过 Issue 或 Pull Request 提交问题、语言翻译和改进。
