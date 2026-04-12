---
name: git-pre-push-guard
description: >
  在 git push 前自动检查仓库可见性和提交内容中的敏感信息。支持所有 Git 平台
  (GitHub/GitLab/Gitee/Bitbucket 等)。Use when: (1) 准备执行 git push,
  (2) 用户要求推送代码到远程仓库, (3) 任何涉及 git push 的操作（包括模型自动推送、
  系统定时推送）。自动检测仓库是否为公开仓库，如果是公开仓库则扫描待推送内容是否
  包含敏感信息（API Key、密码、Token、密钥、个人信息等）。发现敏感信息时必须暂停
  并等待用户确认后才能继续推送。NOT for: 私有仓库推送（仅检测不拦截）。
---

# Git Pre-Push Guard

在执行 `git push` 前自动检查敏感信息，保护你的代码和隐私。

## 支持的平台

GitHub / GitLab / Gitee / Bitbucket / 任何 Git 远程仓库

## 首次使用

安装 git pre-push hook：

```bash
mkdir -p ~/.git-templates/hooks
cp scripts/pre-push-hook ~/.git-templates/hooks/pre-push
chmod +x ~/.git-templates/hooks/pre-push
git config --global core.hooksPath ~/.git-templates/hooks
```

安装后，**所有仓库**（包括新 clone 的）自动启用推送前检查。

## 工作流程

```
任何推送请求
    │
    ├─ 1. 自动检测仓库可见性
    │     ├─ private → 跳过扫描
    │     └─ public → 进入敏感信息检测
    │
    ├─ 2. 调用检测脚本
    │     python3 scripts/check_secrets.py --staged --commits 3
    │
    ├─ 3. 无敏感信息 → 直接推送
    │
    └─ 4. 发现敏感信息 → 列出详情 → 等待用户确认
          ├─ "确认" / "push" / "继续" → 执行 git push
          └─ "取消" / "不推了" / "先修复" → 中止推送
```

## 自动触发条件

以下自然语言会自动触发本 Skill：

- "推送代码"、"提交到远程"、"push"
- "发布到远程仓库"、"同步代码"
- "把代码推上去"、"更新远程仓库"
- 模型自动执行 git push 前

## 检测脚本

```bash
# 检查 staged 文件和最近 3 次提交
python3 scripts/check_secrets.py --staged --commits 3
```

## 检测类别

| 类别 | 示例 | 风险等级 |
|---|---|---|
| 个人信息 | 身份证号、手机号、银行卡 | HIGH |
| 云服务密钥 | AWS、阿里云、腾讯云、GCP | HIGH |
| API Key | OpenAI、Anthropic、各地图服务 | HIGH |
| 数据库连接串 | MySQL/PostgreSQL/MongoDB/Redis | HIGH |
| Token | GitHub、Slack、Discord、Telegram | HIGH |
| 私钥 | RSA/SSH/PGP Private Key | HIGH |
| 支付服务 | Stripe、微信、支付宝 | HIGH |
| 密码/密钥 | password=、secret=、api_key= | MEDIUM |
| 疑似信息 | 注释中的 key、环境变量占位符 | LOW |

## 用户确认流程

发现敏感信息时，**必须**使用 Telegram 按钮让用户选择，而不是让用户输入文字。

使用 `message` tool 发送带按钮的消息：

```
message action=send
  text: "⚠️ 发现 {N} 个潜在敏感信息：\n🔴 HIGH: {high}\n🟡 MEDIUM: {medium}\n\n📁 {file}\n  {line} | [{risk}] {pattern}\n  {preview}\n\n是否确认推送？"
  buttons: [[{"text":"✅ 确认推送","callback_data":"confirm_push"},{"text":"❌ 取消推送","callback_data":"cancel_push"}]]
```

**按钮行为：**
- 用户点击"确认推送" → AI 执行 `git push`
- 用户点击"取消推送" → AI 中止推送，给出修复建议

**注意：按钮样式可选**
- `style: "success"` → 绿色（确认按钮）
- `style: "danger"` → 红色（取消按钮）

完整示例：
```
buttons: [[
  {"text":"✅ 确认推送","callback_data":"confirm_push","style":"success"},
  {"text":"❌ 取消推送","callback_data":"cancel_push","style":"danger"}
]]
```

**只有用户点击"确认推送"后才能继续推送。**

## Git Hook（最终防线）

即使 Skill 未被触发，git pre-push hook 也会自动拦截：

```bash
# 安装 hook（已配置全局 hooksPath 时自动生效）
cp scripts/pre-push-hook ~/.git-templates/hooks/pre-push
chmod +x ~/.git-templates/hooks/pre-push
```

## 白名单

以下文件默认跳过扫描：
- `node_modules/`, `vendor/`, `.git/`
- `*.lock`, `*.min.js`, 图片文件
