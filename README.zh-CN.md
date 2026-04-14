<h1 align="center">
  <a href="https://github.com/Elliotwu-7/Mac-Coffee">
    <img src="docs/images/logo.png" alt="Mac Coffee 图标" width="100" height="100">
  </a>
</h1>

<div align="center">
  Mac Coffee
  <br />
  一个原生 macOS 菜单栏工具，用来保持 Mac 唤醒、按计划恢复正常休眠，并在切到电池供电时安全回退。
  <br />
  <br />
  <a href="README.md">English</a>
  ·
  <a href="https://github.com/Elliotwu-7/Mac-Coffee/releases">下载 DMG</a>
  ·
  <a href="https://github.com/Elliotwu-7/Mac-Coffee/issues/new?assignees=&labels=bug&template=01_BUG_REPORT.md&title=bug%3A+">报告问题</a>
  ·
  <a href="https://github.com/Elliotwu-7/Mac-Coffee/issues/new?assignees=&labels=enhancement&template=02_FEATURE_REQUEST.md&title=feat%3A+">功能建议</a>
</div>

## 项目简介

Mac Coffee 是一个原生菜单栏应用，帮你在不打开终端的情况下快速切换“保持唤醒”和“恢复正常休眠”。它适合偶尔需要防止合盖休眠的场景，同时提供定时恢复、电池供电自动恢复休眠、登录时启动等安全保护能力。

## 运行截图

![Mac Coffee 截图](docs/images/screenshot.png)

## 功能特性

- 在菜单栏中一键切换保持唤醒 / 恢复休眠
- 支持预设时长或指定日期时间后自动恢复休眠
- 支持“切到电池供电后立即恢复休眠”
- 支持登录时启动
- 首次授权后通过 helper 执行系统休眠设置，避免重复输入密码

## 安装

### 通过发行版安装

1. 从最新 release 下载 `MacCoffee.dmg`
2. 打开 DMG
3. 将 `Mac Coffee.app` 拖入 `Applications`
4. 从 `Applications` 启动

### 从源码构建

```sh
cd /Users/elliotwu/MacCoffee
chmod +x build.sh install.sh package_dmg.sh
./build.sh
./install.sh
```

如需本地生成 DMG：

```sh
./package_dmg.sh
open dist/MacCoffee.dmg
```

## 环境要求

- macOS 13 或更高版本
- Xcode Command Line Tools（`xcode-select --install`）
- 首次切换时允许管理员授权安装 helper

## 使用说明

Mac Coffee 常驻在菜单栏，当前版本支持：

- 保持唤醒 / 恢复休眠
- 定时恢复休眠
- 指定日期时间恢复休眠
- 电池供电立即恢复休眠
- 登录时启动

首次切换时，系统会请求管理员授权安装 helper；安装完成后，后续切换通常不会再次弹出密码框。

## 路线图

- 完善 release 自动化，减少手动发布步骤
- 增加定时完成与电池触发恢复时的本地通知
- 继续优化不同 Mac 机型上的状态检测与兼容性

## 支持

- 通过 GitHub issue 提交问题或建议
- 使用 [Elliotwu-7](https://github.com/Elliotwu-7) 主页上的联系方式

## 贡献

欢迎阅读 [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md) 后提交 issue 或 pull request。

## 安全

如发现安全问题，请先不要公开披露，参考 [docs/SECURITY.md](docs/SECURITY.md) 中的方式私下联系。

## 许可证

本项目基于 [MIT License](LICENSE) 开源。

## 致谢

- [dec0dOS/amazing-github-template](https://github.com/dec0dOS/amazing-github-template)
- Apple 的 macOS 开发工具与系统框架
