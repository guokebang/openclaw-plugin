# OpenClaw Plugins

OpenClaw 插件集合，每个子目录是一个独立插件。

## 插件列表

| 插件 | 说明 | 状态 |
|---|---|---|
| [adn-bridge](./adn-bridge/) | Telegram Topic ↔ GitHub Repo 绑定，一键启动 ACP coding session | ✅ 可用 |

## 安装方式

```bash
# 安装单个插件
openclaw plugins install ./adn-bridge

# 或手动复制到 extensions 目录
cp -r adn-bridge ~/.openclaw/extensions/
openclaw plugins enable adn-bridge
openclaw gateway restart
```

## 目录结构

参照 OpenClaw 官方 `extensions/` 目录结构，每个插件包含：

```
<plugin-name>/
├── openclaw.plugin.json    ← 插件清单（必须）
├── package.json
├── index.ts                ← 入口文件
├── README.md               ← 使用说明
└── src/                    ← 源码
```

## 开发指南

参考 [OpenClaw 插件文档](https://docs.openclaw.ai/tools/plugin)

## License

MIT
