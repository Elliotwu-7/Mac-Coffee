# Mac Coffee

[English](README.md) · [Русский](README.ru.md) · **简体中文**

![Mac Coffee 菜单栏面板](docs/images/panel-en.png)

Mac Coffee 是一款轻量的原生 macOS 菜单栏应用。只有在你明确启用唤醒模式时，它才会阻止 Mac 因闲置而自动睡眠。应用使用归属于进程的公开 IOKit 电源断言，无需特权 helper、永久修改 `pmset`、账户、分析服务或后端。

## 功能

- 关闭、保持 Mac 唤醒、保持显示器唤醒三种模式。
- 30 分钟、1/2/4/8 小时或无限时长。
- 10%–30% 可调电量保护，默认 15%，并带迟滞保护。
- 通过 `SMAppService` 登录时启动、本地通知和完整 VoiceOver 标签。
- 系统语言、英语、俄语、德语、法语、简体中文、日语、韩语和西班牙语即时切换；无需重启，也不会中断活动会话。
- 面板退出按钮与 `⌘Q` 使用同一个确认流程。
- Direct 版本支持后台更新检查、独立的新版本提示卡，以及“设置”中的手动检查。
- Direct 版本提供可选的本地 MCP 服务器，可供 Codex、Claude Desktop 和其他 stdio 客户端使用。
- Mac App Store 版本在沙盒中运行，不包含 Sparkle 或 MCP。

Mac Coffee 只阻止因闲置而进入睡眠。手动睡眠、合上盖子、关机、重启以及 macOS 的安全保护始终有效。

## 安装

需要 macOS 13 Ventura 或更高版本。

使用 Homebrew 安装：

```sh
brew tap rekurt/maccoffee
brew install --cask maccoffee
```

也可以从[最新版本](https://github.com/rekurt/Mac-Coffee/releases/latest)下载已签名并经过公证的 DMG。

本地构建方式：

```sh
brew bundle
./scripts/build-local.sh direct
open "dist/local/Mac Coffee.app"
```

## 使用

打开菜单栏中的 Mac Coffee 图标，选择模式和时长。你可以在“设置”中更改语言、电量阈值、登录启动、更新和 MCP 集成。关闭模式或确认退出时，应用会立即释放唤醒请求。

本地构建仅使用 ad-hoc 签名，适合在当前 Mac 上测试，不应作为正式版本分发。

## 本地 MCP 服务器

MCP 默认关闭，并且只存在于 Direct 版本。前往 **设置 → AI 与自动化** 启用集成，打开安装向导，检查建议的配置差异，然后确认配置 Codex 或 Claude Desktop。其他客户端可以复制通用 stdio 配置。

MCP 服务器不会自动启动 Mac Coffee。新客户端必须与正在运行的应用配对。设置中可以查看待处理请求、受信任客户端、撤销控制和有界的本地活动记录；凭据保存在 Keychain 中。

服务器工具可以读取状态、设置或停止唤醒会话、更改电量阈值、登录启动和界面语言。资源 `maccoffee://status`、`maccoffee://capabilities` 和 `maccoffee://activity` 提供状态与能力信息。

详细说明请参阅 [MCP 配置、安全模型和故障排除](docs/MCP.zh-Hans.md)。

## 开发与发布

```sh
brew bundle
xcodegen generate
./scripts/build-local.sh direct
./scripts/build-local.sh app-store
./scripts/verify-release-assets.sh
./scripts/verify-bundles.sh
```

App Store 截图仅维护英语、俄语和简体中文版本；应用界面仍完整支持八种语言。运行 `./scripts/generate-screenshots.sh` 可从 production SwiftUI 视图重新生成图片。

完整的构建、测试、隐私和发布说明请参阅[英文 README](README.md)、[架构文档](docs/ARCHITECTURE.md)、[隐私政策](PRIVACY.md)、[App Store 指南](docs/APP_STORE_SUBMISSION.md)和[发布检查清单](docs/RELEASE_CHECKLIST.md)。

帮助与错误报告：[GitHub Issues](https://github.com/rekurt/Mac-Coffee/issues)。许可证：[MIT](LICENSE)。
