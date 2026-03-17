import { execFileSync } from "node:child_process";
import os from "node:os";
import path from "node:path";
import type { OpenClawPluginApi } from "openclaw/plugin-sdk/core";
import { BindingStore } from "./src/store.js";
import { ensureRepo } from "./src/repo.js";

// ─── Config ───

interface AdnBridgeConfig {
  reposDir?: string;
  defaultRuntime?: string;
}

function resolveReposDir(cfg: AdnBridgeConfig): string {
  return cfg.reposDir ?? path.join(os.homedir(), "repos");
}

function resolveDefaultRuntime(cfg: AdnBridgeConfig): string {
  return cfg.defaultRuntime ?? "claude";
}

// ─── Runtime detection ───

const RUNTIME_LABELS: Record<string, string> = {
  claude: "🟣 Claude Code",
  codex: "🟢 Codex",
  opencode: "🔵 OpenCode",
  pi: "🟡 Pi",
  gemini: "🔴 Gemini CLI",
  kimi: "🟠 Kimi",
};

/**
 * Detect available runtimes: intersection of acp.allowedAgents and locally installed binaries.
 */
function detectAvailableRuntimes(config: any): string[] {
  const allowed: string[] = config?.acp?.allowedAgents ?? ["claude", "codex"];
  const available: string[] = [];
  for (const agent of allowed) {
    try {
      execFileSync("which", [agent], { stdio: "ignore" });
      available.push(agent);
    } catch {
      // not installed
    }
  }
  return available.length > 0 ? available : allowed;
}

// ─── Telegram helpers ───

/**
 * Extract chatId and threadId from plugin command context.
 * ctx.from format: "telegram:group:-1003833456438:topic:4"
 * ctx.messageThreadId: 4
 */
function extractTopicInfo(ctx: any): { chatId: string; threadId: string; topicKey: string } | null {
  const from = ctx.from ?? "";
  const messageThreadId = ctx.messageThreadId;

  const chatMatch = from.match(/telegram:(?:group:)?(-?\d+)/);
  const chatId = chatMatch ? chatMatch[1] : "";
  const threadId = messageThreadId != null ? String(messageThreadId) : "";

  if (chatId && threadId) {
    return { chatId, threadId, topicKey: `${chatId}:${threadId}` };
  }
  return null;
}

/**
 * Send a message with inline keyboard buttons via Telegram Bot API.
 * Uses switch_inline_query_current_chat so clicking a button fills the command in the input box.
 */
async function sendTelegramButtons(params: {
  botToken: string;
  chatId: string;
  threadId: string;
  text: string;
  buttons: Array<{ text: string; switch_inline_query_current_chat: string }>;
}): Promise<void> {
  const { botToken, chatId, threadId, text, buttons } = params;
  const url = `https://api.telegram.org/bot${botToken}/sendMessage`;
  const resp = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      chat_id: chatId,
      message_thread_id: Number(threadId),
      text,
      reply_markup: {
        inline_keyboard: [buttons],
      },
    }),
  });
  if (!resp.ok) {
    const body = await resp.text();
    throw new Error(`Telegram API error ${resp.status}: ${body}`);
  }
}

// ─── Preflight checks ───

interface CheckResult {
  ok: boolean;
  message: string;
}

async function runPreflightChecks(config: any): Promise<CheckResult[]> {
  const results: CheckResult[] = [];

  // 1. ACP enabled
  if (config?.acp?.enabled) {
    results.push({ ok: true, message: "✅ ACP 已启用" });
  } else {
    results.push({ ok: false, message: "❌ ACP 未启用\n修复: openclaw config set acp.enabled true" });
  }

  // 2. ACP backend configured
  if (config?.acp?.backend) {
    results.push({ ok: true, message: `✅ ACP backend: ${config.acp.backend}` });
  } else {
    results.push({ ok: false, message: "❌ ACP backend 未配置\n修复: openclaw config set acp.backend acpx" });
  }

  // 3. acpx plugin enabled
  const acpxEntry = config?.plugins?.entries?.acpx;
  if (acpxEntry?.enabled !== false) {
    results.push({ ok: true, message: "✅ acpx 插件已启用" });
  } else {
    results.push({ ok: false, message: "❌ acpx 插件未启用\n修复: openclaw plugins enable acpx" });
  }

  // 4. Git installed
  try {
    execFileSync("git", ["--version"], { stdio: "ignore" });
    results.push({ ok: true, message: "✅ Git 已安装" });
  } catch {
    results.push({ ok: false, message: "❌ Git 未安装\n修复: sudo apt install git" });
  }

  // 5. SSH key configured for GitHub
  try {
    execFileSync("ssh", ["-T", "-o", "StrictHostKeyChecking=no", "-o", "ConnectTimeout=5", "git@github.com"], {
      stdio: "ignore",
      timeout: 10_000,
    });
    results.push({ ok: true, message: "✅ GitHub SSH 已配置" });
  } catch (e: any) {
    // ssh -T git@github.com exits with code 1 on success ("Hi user! ... does not provide shell access")
    if (e.status === 1) {
      results.push({ ok: true, message: "✅ GitHub SSH 已配置" });
    } else {
      results.push({ ok: false, message: "❌ GitHub SSH 未配置\n修复: ssh-keygen -t ed25519 然后添加到 GitHub" });
    }
  }

  // 6. Runtime detection — show each one, but only fail if none of the required ones are installed
  const REQUIRED_RUNTIMES = ["claude", "codex", "gemini"];
  const ALL_RUNTIMES: Array<{ id: string; label: string; install: string }> = [
    { id: "claude", label: "Claude Code", install: "npm i -g @anthropics/claude-code" },
    { id: "codex", label: "Codex", install: "npm i -g @openai/codex" },
    { id: "gemini", label: "Gemini CLI", install: "npm i -g @anthropic-ai/gemini-cli 或参考官方文档" },
    { id: "opencode", label: "OpenCode", install: "npm i -g opencode" },
    { id: "pi", label: "Pi", install: "npm i -g @mariozechner/pi-coding-agent" },
    { id: "kimi", label: "Kimi", install: "go install github.com/anthropic-ai/kimi@latest" },
  ];

  let hasRequiredRuntime = false;
  for (const rt of ALL_RUNTIMES) {
    let installed = false;
    try {
      execFileSync("which", [rt.id], { stdio: "ignore" });
      installed = true;
    } catch {}

    if (installed) {
      results.push({ ok: true, message: `✅ ${rt.label} 已安装` });
      if (REQUIRED_RUNTIMES.includes(rt.id)) hasRequiredRuntime = true;
    } else {
      // Not installed — only informational, not a blocker per se
      results.push({ ok: true, message: `⬜ ${rt.label} 未安装 (${rt.install})` });
    }
  }

  if (!hasRequiredRuntime) {
    results.push({ ok: false, message: "❌ 至少需要安装 Claude Code、Codex、Gemini CLI 其中一个" });
  }

  // 7. Telegram threadBindings
  const tgBindings = config?.channels?.telegram?.threadBindings;
  const sessionBindings = config?.session?.threadBindings;
  if (tgBindings?.spawnAcpSessions && tgBindings?.enabled !== false && sessionBindings?.enabled !== false) {
    results.push({ ok: true, message: "✅ Telegram thread bindings 已开启" });
  } else {
    const fixes: string[] = [];
    if (!sessionBindings?.enabled) fixes.push("openclaw config set session.threadBindings.enabled true");
    if (!tgBindings?.enabled) fixes.push("openclaw config set channels.telegram.threadBindings.enabled true");
    if (!tgBindings?.spawnAcpSessions) fixes.push("openclaw config set channels.telegram.threadBindings.spawnAcpSessions true");
    results.push({ ok: false, message: `❌ Telegram thread bindings 未完全开启\n修复:\n${fixes.join("\n")}` });
  }

  return results;
}

// ─── Plugin entry ───

export default function register(api: OpenClawPluginApi) {
  const pluginCfg = (api.pluginConfig ?? {}) as AdnBridgeConfig;
  const stateDir = api.runtime.state.resolveStateDir();
  const store = new BindingStore(stateDir);

  api.registerCommand({
    name: "adn_bridge",
    description: "绑定 Telegram topic 到 coding repo，一键启动 ACP coding session。",
    acceptsArgs: true,
    handler: async (ctx) => {
      const args = ctx.args?.trim() ?? "";
      const tokens = args.split(/\s+/).filter(Boolean);
      const action = tokens[0]?.toLowerCase() ?? "";

      const topicInfo = extractTopicInfo(ctx);
      const topicKey = topicInfo?.topicKey ?? "";

      // ── help ──
      if (!action || action === "help") {
        return {
          text: [
            "🛠️ ADN Bridge 命令：",
            "",
            "/adn_bridge bind <org/repo> [--runtime claude|codex]",
            "  绑定当前 topic 到 repo（自动 clone + 显示启动按钮）",
            "",
            "/adn_bridge unbind",
            "  解绑当前 topic",
            "",
            "/adn_bridge status",
            "  查看当前 topic 绑定状态",
            "",
            "/adn_bridge list",
            "  查看所有绑定",
            "",
            "/adn_bridge runtime <claude|codex>",
            "  切换当前 topic 的 coding runtime",
            "",
            "/adn_bridge check",
            "  检查环境配置是否就绪",
          ].join("\n"),
        };
      }

      // ── check ──
      if (action === "check") {
        const results = await runPreflightChecks((ctx as any).config);
        const allOk = results.every((r) => r.ok);
        const lines = [
          allOk ? "🎉 所有检查通过，可以正常使用！" : "⚠️ 以下问题需要修复：",
          "",
          ...results.map((r) => r.message),
        ];
        return { text: lines.join("\n") };
      }

      // ── bind ──
      if (action === "bind") {
        // Run preflight checks first
        const checks = await runPreflightChecks((ctx as any).config);
        const failures = checks.filter((c) => !c.ok);
        if (failures.length > 0) {
          return {
            text: [
              "❌ 环境检查未通过，请先修复以下问题：",
              "",
              ...failures.map((f) => f.message),
              "",
              "修复后重启 gateway 再试。",
            ].join("\n"),
          };
        }

        const repoSpec = tokens[1];
        if (!repoSpec) {
          return { text: "用法：/adn_bridge bind <org/repo>\n例如：/adn_bridge bind guokebang/cc-PhonePilot" };
        }

        // Parse optional --runtime flag
        let runtime = resolveDefaultRuntime(pluginCfg);
        const rtIdx = tokens.indexOf("--runtime");
        if (rtIdx !== -1 && tokens[rtIdx + 1]) {
          const rt = tokens[rtIdx + 1]!.toLowerCase();
          if (rt === "claude" || rt === "codex") {
            runtime = rt;
          } else {
            return { text: `不支持的 runtime: ${rt}，可选 claude 或 codex` };
          }
        }

        const reposDir = resolveReposDir(pluginCfg);

        // Clone if needed
        let repoPath: string;
        let cloned = false;
        try {
          const result = await ensureRepo(reposDir, repoSpec);
          repoPath = result.repoPath;
          cloned = result.cloned;
        } catch (e: any) {
          return { text: `❌ Clone 失败：${e.message ?? e}` };
        }

        // Save binding to plugin store
        const binding = {
          topicKey: topicKey || `manual:${repoSpec}`,
          repo: repoSpec,
          repoPath,
          runtime,
          boundAt: new Date().toISOString(),
        };
        await store.set(binding);

        const lines = [
          `✅ 绑定成功！`,
          "",
          `📦 Repo: ${repoSpec}`,
          `📂 路径: ${repoPath}`,
          `🤖 Runtime: ${runtime}`,
          cloned ? `📥 已自动 clone` : `📁 使用已有 repo`,
        ];

        // Send runtime selection buttons
        if (topicInfo) {
          const runtimes = detectAvailableRuntimes((ctx as any).config);
          const botToken = (ctx as any).config?.channels?.telegram?.botToken ?? "";

          if (botToken && runtimes.length > 0) {
            const buttons = runtimes.map((rt) => ({
              text: RUNTIME_LABELS[rt] ?? `🚀 ${rt}`,
              switch_inline_query_current_chat: `/acp spawn ${rt} --cwd ${repoPath} --thread here --mode persistent`,
            }));

            sendTelegramButtons({
              botToken,
              chatId: topicInfo.chatId,
              threadId: topicInfo.threadId,
              text: "👇 选择 runtime 启动 coding session：",
              buttons,
            }).catch((e) => {
              api.logger.error(`adn-bridge: sendTelegramButtons failed: ${e}`);
            });
          }
        } else {
          lines.push(
            "",
            `⚠️ 未检测到 topic 上下文，请在 Telegram Forum Topic 中使用`,
            `手动启动：/acp spawn ${runtime} --cwd ${repoPath}`,
          );
        }

        return { text: lines.join("\n") };
      }

      // ── unbind ──
      if (action === "unbind") {
        if (!topicKey) {
          return { text: "⚠️ 未检测到 topic 上下文，无法解绑。" };
        }
        const removed = await store.remove(topicKey);
        if (removed) {
          return { text: "✅ 已解绑当前 topic。\n如果有运行中的 coding session，用 /acp close 关闭。" };
        }
        return { text: "当前 topic 没有绑定。" };
      }

      // ── status ──
      if (action === "status") {
        if (!topicKey) {
          return { text: "⚠️ 未检测到 topic 上下文。" };
        }
        const binding = await store.get(topicKey);
        if (!binding) {
          return { text: "当前 topic 未绑定。\n用 /adn_bridge bind <repo> 绑定。" };
        }
        return {
          text: [
            `📋 当前 topic 绑定：`,
            "",
            `📦 Repo: ${binding.repo}`,
            `📂 路径: ${binding.repoPath}`,
            `🤖 Runtime: ${binding.runtime}`,
            `🕐 绑定时间: ${binding.boundAt}`,
          ].join("\n"),
        };
      }

      // ── list ──
      if (action === "list") {
        const all = await store.list();
        if (all.length === 0) {
          return { text: "没有任何绑定。" };
        }
        const lines = ["📋 所有绑定：", ""];
        for (const b of all) {
          lines.push(`• ${b.repo} (${b.runtime}) → ${b.repoPath}`);
        }
        return { text: lines.join("\n") };
      }

      // ── runtime ──
      if (action === "runtime") {
        if (!topicKey) {
          return { text: "⚠️ 未检测到 topic 上下文。" };
        }
        const binding = await store.get(topicKey);
        if (!binding) {
          return { text: "当前 topic 未绑定。先用 /adn_bridge bind <repo> 绑定。" };
        }
        const rt = tokens[1]?.toLowerCase();
        if (rt !== "claude" && rt !== "codex") {
          return { text: `用法：/adn_bridge runtime <claude|codex>\n当前: ${binding.runtime}` };
        }
        binding.runtime = rt;
        await store.set(binding);
        return { text: `✅ Runtime 已切换为 ${rt}` };
      }

      return { text: "未知命令。用 /adn_bridge help 查看帮助。" };
    },
  });
}
