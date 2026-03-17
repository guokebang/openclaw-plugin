# ADN Bridge

OpenClaw 插件：在 Telegram Forum Topic 中一键绑定 GitHub repo，启动 Claude Code / Codex coding session。

## 功能

- `/adn_bridge bind <org/repo>` — 绑定 topic 到 repo（自动 clone + SSH 转换 + 显示 runtime 选择按钮）
- `/adn_bridge unbind` — 解绑当前 topic
- `/adn_bridge status` — 查看当前 topic 绑定状态
- `/adn_bridge list` — 查看所有绑定
- `/adn_bridge runtime <claude|codex>` — 切换 runtime

## 工作流程

1. 在 Telegram 群组创建一个 Forum Topic（每个 topic = 一个项目）
2. 在 topic 中执行 `/adn_bridge bind org/repo`
3. 插件自动 clone repo 到 `~/repos/<repo>/`
4. 显示 runtime 选择按钮（Claude Code / Codex）
5. 点击按钮启动 ACP coding session
6. 直接在 topic 中发消息跟 coding agent 对话

## 前置条件

- OpenClaw ACP 已启用 (`acp.enabled: true`)
- acpx 插件已启用
- Telegram thread bindings 已开启
- GitHub SSH key 已配置
- Claude Code 或 Codex 已安装

## 配置

```json5
{
  "plugins": {
    "entries": {
      "adn-bridge": {
        "enabled": true,
        "config": {
          "reposDir": "/home/user/repos",    // 可选，默认 ~/repos
          "defaultRuntime": "claude"          // 可选，默认 claude
        }
      }
    }
  }
}
```

## Repo 格式支持

- `org/repo` → `git@github.com:org/repo.git`
- `https://github.com/org/repo` → 自动转 SSH
- `git@github.com:org/repo.git` → 原样使用

## 已知限制

- Telegram inline button 的 `callback_data` 限制 64 字节，所以使用 `switch_inline_query_current_chat` 方式（点击后填充到输入框）
- Telegram 群组 topic 的 ACP thread binding 需要 `session.threadBindings.enabled: true` 和 `channels.telegram.threadBindings.enabled: true`
