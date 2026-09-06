# Mac Coffee MCP 集成

[English](MCP.md) · [Русский](MCP.ru.md) · **简体中文**

Mac Coffee Direct 包含一个本地 MCP 服务器，可供 Codex、Claude Desktop 和其他 stdio 客户端控制正在运行的应用。该集成默认关闭，并且完全不包含在 Mac App Store 版本中。

## 快速配置

1. 安装并启动 Mac Coffee Direct。
2. 打开 **设置 → AI 与自动化**。
3. 启用 MCP。
4. 打开 MCP 客户端设置向导。
5. 选择 Codex、Claude Desktop 或 Generic stdio。
6. 检查配置路径、内置 helper 路径和完整差异。
7. 确认安装，然后重新启动 MCP 客户端。
8. 发起第一次请求，并在 Mac Coffee 中批准配对。

向导会保留无关配置、验证结果，并在替换现有文件前创建带时间戳的备份。对于损坏的文件、冲突条目、符号链接或不可安全写入的目标，向导只显示手动说明，不会修改原文件。

## 客户端配置

标准安装中的 MCP helper 路径：

```text
/Applications/Mac Coffee.app/Contents/Helpers/MacCoffeeMCP
```

如果应用位于其他目录，请使用向导显示的路径。

Codex 的 `~/.codex/config.toml` 配置：

```toml
[mcp_servers.mac_coffee]
command = "/Applications/Mac Coffee.app/Contents/Helpers/MacCoffeeMCP"
```

Claude Desktop 的 `~/Library/Application Support/Claude/claude_desktop_config.json` 配置：

```json
{
  "mcpServers": {
    "mac-coffee": {
      "command": "/Applications/Mac Coffee.app/Contents/Helpers/MacCoffeeMCP",
      "args": []
    }
  }
}
```

其他客户端应添加一个本地 stdio MCP 服务器，命令为该 executable，参数为空。Mac Coffee 必须已经运行；helper 不会自动启动应用。

## 工具与资源

服务器提供 `maccoffee_get_status`、`maccoffee_set_session`、`maccoffee_stop_session`、`maccoffee_set_battery_threshold`、`maccoffee_set_launch_at_login` 和 `maccoffee_set_language`。

`maccoffee_set_session` 的模式接受 `system` 或 `display`；时长接受 `minutes30`、`hours1`、`hours2`、`hours4`、`hours8` 或 `indefinite`。电量阈值限制为 10–30%。语言接受 `system`、`en`、`ru`、`de`、`fr`、`zh-Hans`、`ja`、`ko` 或 `es`。

修改操作可带最长 128 字符的 `requestId`。同一客户端重复相同请求时会返回缓存结果，不会重复执行。

资源：

- `maccoffee://status`：当前应用状态；
- `maccoffee://capabilities`：能力和协议版本；
- `maccoffee://activity`：有界的本地活动记录。

服务器支持状态订阅。

## 安全模型

- 只有用户明确启用后 MCP 才会运行。
- XPC 限制为当前 macOS 用户；broker 会验证 executable 的位置和代码签名身份。
- 新客户端通过 P-256 challenge-response，并需要在应用中明确批准。
- 未完成的挑战会在 120 秒后过期；挑战、待审批客户端和重放记录都采用固定内存上限。
- 受信任凭据保存在 Keychain，并绑定到客户端 code identity。
- 可以在设置中立即撤销访问或完全删除信任记录。
- MCP 无法绕过电池保护或 macOS 的电源安全决策。
- 活动记录有数量上限，只保存在内存中，并在 Mac Coffee 退出时清除。
- App Store 版本不包含 MCP helper、broker、设置或 MCP 符号。

## 故障排除与移除

如果客户端提示 Mac Coffee 不可用，请先启动应用，确认 MCP 状态为 Ready；移动应用后应重新运行设置向导。如果需要 approval，请在设置中批准待处理的配对。客户端更新导致 code identity 改变时，需要撤销旧记录并重新配对。

如需移除集成，请关闭 MCP，从 Codex 删除 `mac_coffee` 表或从 Claude Desktop 删除 `mac-coffee` 对象，重新启动客户端，并按需在 Mac Coffee 中删除受信任客户端。
