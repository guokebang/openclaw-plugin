# ADN Backup

OpenClaw 备份插件：一键导出/导入配置、插件、工作区、会话历史。

## 功能

- `/adn_backup export [--sessions] [--memory] [--output /path]` — 导出备份
- `/adn_backup import <backup.tar.gz> [--dry-run]` — 导入备份
- `/adn_backup list` — 列出历史备份
- `/adn_backup info <backup.tar.gz>` — 查看备份详情

## 使用示例

### 导出备份（推荐）

```bash
# 基本备份（配置 + 插件 + 工作区）
/adn_backup export

# 完整备份（包含会话历史和记忆）
/adn_backup export --sessions --memory

# 指定输出目录
/adn_backup export --output /mnt/backup/openclaw
```

### 导入备份

```bash
# 预览（不实际恢复）
/adn_backup import /path/to/openclaw-backup-1234567890.tar.gz --dry-run

# 实际恢复
/adn_backup import /path/to/openclaw-backup-1234567890.tar.gz
```

恢复后重启 gateway：
```bash
openclaw gateway restart
```

### 查看备份

```bash
# 列出所有备份
/adn_backup list

# 查看备份详情
/adn_backup info /path/to/openclaw-backup-1234567890.tar.gz
```

## 备份内容

| 内容 | 默认 | 可选 | 说明 |
|---|---|---|---|
| `openclaw.json` | ✅ | - | 主配置 |
| `extensions/` | ✅ | - | 所有插件 |
| `workspace/` | ✅ | - | 工作区（SOUL.md、USER.md、skills/等） |
| `agents/*/sessions/` | ❌ | `--sessions` | 会话历史（可能很大） |
| `memory/` | ❌ | `--memory` | 长期记忆 |

## 配置

```json5
{
  "plugins": {
    "entries": {
      "adn-backup": {
        "enabled": true,
        "config": {
          "backupDir": "/mnt/backup/openclaw"  // 可选，默认 ~/.openclaw/backups/
        }
      }
    }
  }
}
```

## 迁移场景

### 场景一：整机迁移

```bash
# 旧机器
/adn_backup export --sessions

# 复制备份文件到新机器
scp ~/.openclaw/backups/openclaw-backup-*.tar.gz user@new-host:~/

# 新机器
/adn_backup import ~/openclaw-backup-*.tar.gz
openclaw gateway restart
```

### 场景二：多机器同步

```bash
# 机器 A
/adn_backup export

# 上传到云存储（Google Drive、Dropbox、iCloud 等）

# 机器 B
# 从云存储下载备份文件
/adn_backup import /path/to/backup.tar.gz
openclaw gateway restart
```

### 场景三：版本回滚

```bash
# 更新前备份
/adn_backup export

# 更新后发现问题...

# 回滚到更新前
/adn_backup import /path/to/pre-update-backup.tar.gz
openclaw gateway restart
```

## 备份文件位置

默认：`~/.openclaw/backups/`

文件名格式：`openclaw-backup-<timestamp>.tar.gz`

## 注意事项

1. **会话历史可能很大** — 默认不包含，需要时加 `--sessions`
2. **敏感信息** — 备份包含 `openclaw.json` 里的 API keys，请妥善保管
3. **版本兼容** — 不同 OpenClaw 版本之间恢复可能有问题，建议先 `--dry-run` 预览
4. **恢复后重启** — 恢复配置后必须重启 gateway 才能生效

## License

MIT
