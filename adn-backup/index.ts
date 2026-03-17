import { execFileSync } from "node:child_process";
import fs from "node:fs/promises";
import path from "node:path";
import os from "node:os";
import type { OpenClawPluginApi } from "openclaw/plugin-sdk/core";

// ─── Config ───

interface AdnBackupConfig {
  backupDir?: string;  // Default: ~/.openclaw/backups
}

function resolveBackupDir(cfg: AdnBackupConfig): string {
  return cfg.backupDir ?? path.join(os.homedir(), ".openclaw", "backups");
}

// ─── Helpers ───

function formatBytes(bytes: number): string {
  const units = ["B", "KB", "MB", "GB"];
  let i = 0;
  let n = bytes;
  while (n >= 1024 && i < units.length - 1) {
    n /= 1024;
    i++;
  }
  return `${n.toFixed(1)} ${units[i]}`;
}

function formatDate(ts: number): string {
  return new Date(ts).toLocaleString("zh-CN", {
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
  });
}

async function getDirSize(dir: string): Promise<number> {
  let size = 0;
  try {
    const entries = await fs.readdir(dir, { withFileTypes: true });
    for (const entry of entries) {
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) {
        size += await getDirSize(full);
      } else {
        const stat = await fs.stat(full);
        size += stat.size;
      }
    }
  } catch {
    // ignore
  }
  return size;
}

// ─── Backup Operations ───

interface BackupManifest {
  version: number;
  createdAt: number;
  openclawVersion: string;
  includes: {
    config: boolean;
    extensions: boolean;
    workspace: boolean;
    sessions: boolean;
    memory: boolean;
  };
  sizes: Record<string, number>;
}

async function createBackup(params: {
  outputDir: string;
  includeSessions: boolean;
  includeMemory: boolean;
}): Promise<{ archivePath: string; manifest: BackupManifest }> {
  const { outputDir, includeSessions, includeMemory } = params;
  const homeDir = os.homedir();
  const openclawDir = path.join(homeDir, ".openclaw");
  const timestamp = Date.now();
  const archiveName = `openclaw-backup-${timestamp}.tar.gz`;
  const archivePath = path.join(outputDir, archiveName);

  // Build file list
  const filesToBackup: string[] = [];
  const sizes: Record<string, number> = {};

  // Always include: config, extensions, workspace
  filesToBackup.push("openclaw.json");
  filesToBackup.push("extensions/");
  filesToBackup.push("workspace/");

  sizes["openclaw.json"] = (await fs.stat(path.join(openclawDir, "openclaw.json"))).size;
  sizes["extensions"] = await getDirSize(path.join(openclawDir, "extensions"));
  sizes["workspace"] = await getDirSize(path.join(openclawDir, "workspace"));

  // Optional: sessions
  if (includeSessions) {
    filesToBackup.push("agents/");
    sizes["agents"] = await getDirSize(path.join(openclawDir, "agents"));
  }

  // Optional: memory
  if (includeMemory) {
    filesToBackup.push("memory/");
    const memPath = path.join(openclawDir, "memory");
    try {
      sizes["memory"] = await getDirSize(memPath);
    } catch {
      sizes["memory"] = 0;
    }
  }

  // Get OpenClaw version
  let openclawVersion = "unknown";
  try {
    const pkg = JSON.parse(await fs.readFile(path.join(openclawDir, "..", "package.json"), "utf8"));
    openclawVersion = pkg.version || "unknown";
  } catch {
    try {
      const v = execFileSync("openclaw", ["--version"], { encoding: "utf8" }).trim();
      openclawVersion = v;
    } catch {
      // ignore
    }
  }

  // Create manifest
  const manifest: BackupManifest = {
    version: 1,
    createdAt: timestamp,
    openclawVersion,
    includes: {
      config: true,
      extensions: true,
      workspace: true,
      sessions: includeSessions,
      memory: includeMemory,
    },
    sizes,
  };

  // Write manifest to temp file
  const manifestPath = path.join(outputDir, `manifest-${timestamp}.json`);
  await fs.writeFile(manifestPath, JSON.stringify(manifest, null, 2));

  // Create tar archive
  const tarArgs = [
    "-czf",
    archivePath,
    "-C",
    openclawDir,
    ...filesToBackup,
  ];
  execFileSync("tar", tarArgs);

  // Clean up manifest temp file
  await fs.unlink(manifestPath);

  return { archivePath, manifest };
}

async function inspectBackup(archivePath: string): Promise<BackupManifest | null> {
  try {
    // Extract manifest from archive
    const tempDir = await fs.mkdtemp(path.join(os.tmpdir(), "adn-backup-"));
    try {
      execFileSync("tar", ["-xzf", archivePath, "-C", tempDir, "openclaw.json"]);
      // For now, just return basic info since we don't have embedded manifest
      const stat = await fs.stat(archivePath);
      return {
        version: 1,
        createdAt: stat.mtimeMs,
        openclawVersion: "unknown",
        includes: {
          config: true,
          extensions: true,
          workspace: true,
          sessions: false,
          memory: false,
        },
        sizes: {
          archive: stat.size,
        },
      };
    } finally {
      await fs.rm(tempDir, { recursive: true, force: true });
    }
  } catch {
    return null;
  }
}

async function restoreBackup(params: {
  archivePath: string;
  targetDir: string;
  dryRun: boolean;
}): Promise<{ restored: string[]; skipped: string[]; errors: string[] }> {
  const { archivePath, targetDir, dryRun } = params;
  const restored: string[] = [];
  const skipped: string[] = [];
  const errors: string[] = [];

  if (dryRun) {
    // Just list what would be restored
    try {
      const output = execFileSync("tar", ["-tzf", archivePath], { encoding: "utf8" });
      const files = output.trim().split("\n").filter(Boolean);
      restored.push(...files);
    } catch (e: any) {
      errors.push(`无法读取备份文件：${e.message}`);
    }
    return { restored, skipped, errors };
  }

  // Extract archive
  try {
    execFileSync("tar", ["-xzf", archivePath, "-C", targetDir]);
    restored.push("openclaw.json", "extensions/", "workspace/");
  } catch (e: any) {
    errors.push(`解压失败：${e.message}`);
  }

  return { restored, skipped, errors };
}

async function listBackups(backupDir: string): Promise<Array<{ path: string; name: string; size: number; createdAt: number }>> {
  const backups: Array<{ path: string; name: string; size: number; createdAt: number }> = [];
  try {
    const entries = await fs.readdir(backupDir, { withFileTypes: true });
    for (const entry of entries) {
      if (entry.isFile() && entry.name.startsWith("openclaw-backup-") && entry.name.endsWith(".tar.gz")) {
        const fullPath = path.join(backupDir, entry.name);
        const stat = await fs.stat(fullPath);
        // Extract timestamp from filename
        const tsMatch = entry.name.match(/openclaw-backup-(\d+)\.tar\.gz/);
        const createdAt = tsMatch ? Number.parseInt(tsMatch[1]) : stat.mtimeMs;
        backups.push({
          path: fullPath,
          name: entry.name,
          size: stat.size,
          createdAt,
        });
      }
    }
    backups.sort((a, b) => b.createdAt - a.createdAt);
  } catch {
    // ignore
  }
  return backups;
}

// ─── Plugin Entry ───

export default function register(api: OpenClawPluginApi) {
  const pluginCfg = (api.pluginConfig ?? {}) as AdnBackupConfig;
  const backupDir = resolveBackupDir(pluginCfg);

  api.registerCommand({
    name: "adn_backup",
    description: "备份和恢复 OpenClaw 配置、插件、工作区。",
    acceptsArgs: true,
    handler: async (ctx) => {
      const args = ctx.args?.trim() ?? "";
      const tokens = args.split(/\s+/).filter(Boolean);
      const action = tokens[0]?.toLowerCase() ?? "";

      // ── help ──
      if (!action || action === "help") {
        return {
          text: [
            "🛠️ ADN Backup 命令：",
            "",
            "/adn_backup export [--sessions] [--memory] [--output /path]",
            "  导出备份（默认 ~/.openclaw/backups/）",
            "",
            "/adn_backup import <backup.tar.gz> [--dry-run]",
            "  导入备份（--dry-run 预览不实际恢复）",
            "",
            "/adn_backup list",
            "  列出历史备份",
            "",
            "/adn_backup info <backup.tar.gz>",
            "  查看备份详情",
          ].join("\n"),
        };
      }

      // ── export ──
      if (action === "export") {
        const includeSessions = tokens.includes("--sessions");
        const includeMemory = tokens.includes("--memory");
        const outputIdx = tokens.indexOf("--output");
        const outputDir = outputIdx !== -1 && tokens[outputIdx + 1] ? tokens[outputIdx + 1] : backupDir;

        // Ensure output dir exists
        await fs.mkdir(outputDir, { recursive: true });

        const lines = ["📦 开始备份...", ""];

        try {
          const { archivePath, manifest } = await createBackup({
            outputDir,
            includeSessions,
            includeMemory,
          });

          const totalSize = Object.values(manifest.sizes).reduce((a, b) => a + b, 0);

          lines.push(
            "✅ 备份完成！",
            "",
            `📂 备份文件：${archivePath}`,
            `📊 总大小：${formatBytes(totalSize)}`,
            `🕐 创建时间：${formatDate(manifest.createdAt)}`,
            `📦 OpenClaw 版本：${manifest.openclawVersion}`,
            "",
            "包含内容：",
            `  ✅ 配置 (openclaw.json)`,
            `  ✅ 插件 (extensions/)`,
            `  ✅ 工作区 (workspace/)`,
            includeSessions ? `  ✅ 会话历史 (agents/)` : `  ⬜ 会话历史 (未包含)`,
            includeMemory ? `  ✅ 长期记忆 (memory/)` : `  ⬜ 长期记忆 (未包含)`,
            "",
            "💡 提示：恢复时使用 /adn_backup import <备份文件路径>",
          );

          return { text: lines.join("\n") };
        } catch (e: any) {
          return { text: `❌ 备份失败：${e.message ?? e}` };
        }
      }

      // ── import ──
      if (action === "import") {
        const archivePath = tokens[1];
        if (!archivePath) {
          return { text: "用法：/adn_backup import <backup.tar.gz> [--dry-run]" };
        }

        const dryRun = tokens.includes("--dry-run");
        const homeDir = os.homedir();
        const openclawDir = path.join(homeDir, ".openclaw");

        if (dryRun) {
          const result = await restoreBackup({ archivePath, targetDir: openclawDir, dryRun: true });
          if (result.errors.length > 0) {
            return { text: `❌ 检查失败：${result.errors.join("\n")}` };
          }
          return {
            text: [
              "🔍 备份预览（dry-run）：",
              "",
              "将恢复以下内容：",
              ...result.restored.map((f) => `  • ${f}`),
              "",
              "⚠️ 这是预览模式，没有实际恢复。",
              "要实际恢复，去掉 --dry-run 参数重新执行。",
              "",
              "⚠️ 恢复后需要重启 gateway：openclaw gateway restart",
            ].join("\n"),
          };
        }

        // Actual restore
        const result = await restoreBackup({ archivePath, targetDir: openclawDir, dryRun: false });
        if (result.errors.length > 0) {
          return { text: `❌ 恢复失败：${result.errors.join("\n")}` };
        }

        return {
          text: [
            "✅ 恢复完成！",
            "",
            "已恢复：",
            ...result.restored.map((f) => `  • ${f}`),
            "",
            "⚠️ 请重启 gateway 使配置生效：",
            "```",
            "openclaw gateway restart",
            "```",
          ].join("\n"),
        };
      }

      // ── list ──
      if (action === "list") {
        const backups = await listBackups(backupDir);
        if (backups.length === 0) {
          return { text: `📂 备份目录：${backupDir}\n\n没有找到备份文件。` };
        }

        const lines = [
          `📂 备份目录：${backupDir}`,
          "",
          `共 ${backups.length} 个备份：`,
          "",
        ];

        for (const b of backups) {
          lines.push(
            `📦 ${b.name}`,
            `   大小：${formatBytes(b.size)}`,
            `   时间：${formatDate(b.createdAt)}`,
            `   路径：${b.path}`,
            "",
          );
        }

        return { text: lines.join("\n") };
      }

      // ── info ──
      if (action === "info") {
        const archivePath = tokens[1];
        if (!archivePath) {
          return { text: "用法：/adn_backup info <backup.tar.gz>" };
        }

        const manifest = await inspectBackup(archivePath);
        if (!manifest) {
          return { text: `❌ 无法读取备份文件：${archivePath}` };
        }

        const totalSize = Object.values(manifest.sizes).reduce((a, b) => a + b, 0);

        return {
          text: [
            "📋 备份详情：",
            "",
            `📦 文件：${archivePath}`,
            `📊 大小：${formatBytes(totalSize)}`,
            `🕐 创建时间：${formatDate(manifest.createdAt)}`,
            `📦 OpenClaw 版本：${manifest.openclawVersion}`,
            "",
            "包含内容：",
            manifest.includes.config ? "  ✅ 配置" : "  ⬜ 配置",
            manifest.includes.extensions ? "  ✅ 插件" : "  ⬜ 插件",
            manifest.includes.workspace ? "  ✅ 工作区" : "  ⬜ 工作区",
            manifest.includes.sessions ? "  ✅ 会话历史" : "  ⬜ 会话历史",
            manifest.includes.memory ? "  ✅ 长期记忆" : "  ⬜ 长期记忆",
          ].join("\n"),
        };
      }

      return { text: "未知命令。用 /adn_backup help 查看帮助。" };
    },
  });
}
