# ADN Bridge

OpenClaw 插件：在 Telegram Forum Topic 中一键绑定 Git repo（GitHub/GitLab/私有部署），启动 Claude Code / Codex coding session。

## 功能

- `/adn_bridge bind <repo>` — 绑定 topic 到 repo（自动 clone + SSH 转换 + 显示 runtime 选择按钮）
- `/adn_bridge unbind` — 解绑当前 topic
- `/adn_bridge status` — 查看当前 topic 绑定状态
- `/adn_bridge list` — 查看所有绑定
- `/adn_bridge runtime <claude|codex>` — 切换 runtime
- `/adn_bridge check` — 检查环境配置是否就绪

## 支持的 Repo 格式

```
# GitHub
org/repo
github:org/repo
https://github.com/org/repo
git@github.com:org/repo.git

# GitLab (gitlab.com)
gitlab:group/project
https://gitlab.com/group/project
git@gitlab.com:group/project.git

# 私有 GitLab
gitlab.company.com:group/project
https://gitlab.company.com/group/project
git@gitlab.company.com:group/project.git

# 其他 Git host
git.example.com:group/project
https://git.example.com/group/project
```

## 工作流程

1. 在 Telegram 群组创建一个 Forum Topic（每个 topic = 一个项目）
2. 在 topic 中执行 `/adn_bridge bind <repo>`
3. 插件自动 clone repo 到 `~/repos/<repo>/`，自动转换 HTTPS → SSH
4. 显示 runtime 选择按钮（Claude Code / Codex / 其他已安装的）
5. 点击按钮启动 ACP coding session
6. 直接在 topic 中发消息跟 coding agent 对话

## 配置

```json5
{
  "plugins": {
    "entries": {
      "adn-bridge": {
        "enabled": true,
        "config": {
          "reposDir": "/home/user/repos",           // 可选，默认 ~/repos
          "defaultRuntime": "claude",                // 可选，默认 claude
          "defaultGitHost": "gitlab.company.com",    // 可选，默认 github.com
          "gitHosts": ["github.com", "gitlab.company.com"]  // 可选，自动推断
        }
      }
    }
  }
}
```

### 配置说明

| 字段 | 说明 | 默认值 |
|---|---|---|
| `reposDir` | repo 克隆目录 | `~/repos` |
| `defaultRuntime` | 默认 runtime | `claude` |
| `defaultGitHost` | 短格式 repo 的默认 Git host（如 `org/repo`） | `github.com` |
| `gitHosts` | 检查 SSH key 的 Git host 列表 | `["github.com"]` + `defaultGitHost` |

## 私有 GitLab 配置示例

```json5
{
  "plugins": {
    "entries": {
      "adn-bridge": {
        "enabled": true,
        "config": {
          "defaultGitHost": "gitlab.company.com",
          "gitHosts": ["github.com", "gitlab.company.com"]
        }
      }
    }
  }
}
```

然后绑定私有 GitLab repo：

```
/adn_bridge bind gitlab.company.com:group/project
/adn_bridge bind https://gitlab.company.com/group/project
```

## SSH Key 配置

插件会自动检查配置的 Git host 的 SSH key。如果没有，会提示你生成并添加：

```bash
# GitHub
ssh-keygen -t ed25519 -C "your@email" -f ~/.ssh/id_ed25519_github_com
# 然后添加到 https://github.com/settings/keys

# GitLab (私有)
ssh-keygen -t ed25519 -C "your@email" -f ~/.ssh/id_ed25519_gitlab_company_com
# 然后添加到 https://gitlab.company.com/-/profile/keys
```

## 前置条件

- OpenClaw ACP 已启用 (`acp.enabled: true`)
- acpx 插件已启用
- Telegram thread bindings 已开启
- Git 已安装
- 至少一个 coding runtime 已安装（Claude Code / Codex / Gemini CLI）
- Git host 的 SSH key 已配置

## 已知限制

- Telegram inline button 使用 `switch_inline_query_current_chat`（点击后填充到输入框，按回车发送）
- Telegram 群组 topic 的 ACP thread binding 需要 `session.threadBindings.enabled: true`

## License

MIT
