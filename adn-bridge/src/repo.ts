import { execFile } from "node:child_process";
import fs from "node:fs/promises";
import path from "node:path";

function exec(cmd: string, args: string[], cwd?: string): Promise<{ stdout: string; stderr: string }> {
  return new Promise((resolve, reject) => {
    execFile(cmd, args, { cwd, timeout: 120_000 }, (err, stdout, stderr) => {
      if (err) reject(Object.assign(err, { stdout, stderr }));
      else resolve({ stdout: stdout?.toString() ?? "", stderr: stderr?.toString() ?? "" });
    });
  });
}

/**
 * Convert HTTPS Git URL to SSH URL.
 * Supports GitHub, GitLab, and any custom Git host.
 *
 * Examples:
 * - https://github.com/org/repo → git@github.com:org/repo.git
 * - https://gitlab.com/group/project → git@gitlab.com:group/project.git
 * - https://gitlab.company.com/group/project → git@gitlab.company.com:group/project.git
 */
export function httpsToSsh(url: string): string {
  // Match: https://<host>/<path>
  const m = url.match(/^https?:\/\/([^/]+)\/(.+?)(?:\.git)?$/);
  if (!m) return url;

  const host = m[1]!;
  const repoPath = m[2]!;

  // Remove trailing .git from path if present
  const cleanPath = repoPath.replace(/\.git$/, "");

  return `git@${host}:${cleanPath}.git`;
}

/**
 * Extract host from a Git URL or SSH spec.
 */
export function extractGitHost(spec: string): string | null {
  if (spec.startsWith("git@")) {
    // git@host:path.git
    const m = spec.match(/^git@([^:]+):/);
    return m ? m[1]! : null;
  }
  if (spec.startsWith("https://") || spec.startsWith("http://")) {
    // https://host/path
    const m = spec.match(/^https?:\/\/([^/]+)/);
    return m ? m[1]! : null;
  }
  return null;
}

/**
 * Resolve a repo spec to a clone-able SSH URL and local dir name.
 *
 * Supported formats:
 * - "org/repo"                          → git@github.com:org/repo.git (default GitHub)
 * - "github:org/repo"                   → git@github.com:org/repo.git
 * - "gitlab:group/project"              → git@gitlab.com:group/project.git
 * - "gitlab.company.com:group/project"  → git@gitlab.company.com:group/project.git
 * - "https://github.com/org/repo"       → git@github.com:org/repo.git
 * - "https://gitlab.com/group/project"  → git@gitlab.com:group/project.git
 * - "https://gitlab.company.com/g/p"    → git@gitlab.company.com:g/p.git
 * - "git@github.com:org/repo.git"       → as-is
 * - "git@gitlab.com:group/project.git"  → as-is
 */
export function resolveRepoSpec(spec: string, defaultHost: string = "github.com"): {
  cloneUrl: string;
  dirName: string;
  host: string;
} {
  // Already SSH format: git@host:path.git
  if (spec.startsWith("git@")) {
    const dirName = path.basename(spec.replace(/\.git$/, ""));
    const host = extractGitHost(spec)!;
    return { cloneUrl: spec, dirName, host };
  }

  // HTTPS URL
  if (spec.startsWith("https://") || spec.startsWith("http://")) {
    const sshUrl = httpsToSsh(spec);
    const host = extractGitHost(sshUrl)!;
    const dirName = path.basename(spec.replace(/\.git$/, ""));
    return { cloneUrl: sshUrl, dirName, host };
  }

  // Platform prefix: github:org/repo, gitlab:group/project
  const prefixMatch = spec.match(/^(github|gitlab):(.+)$/);
  if (prefixMatch) {
    const platform = prefixMatch[1]!;
    const repoPath = prefixMatch[2]!;
    const host = platform === "github" ? "github.com" : "gitlab.com";
    return {
      cloneUrl: `git@${host}:${repoPath}.git`,
      dirName: path.basename(repoPath),
      host,
    };
  }

  // Custom host prefix: gitlab.company.com:group/project
  const hostMatch = spec.match(/^([^:]+):(.+)$/);
  if (hostMatch && hostMatch[1]?.includes(".")) {
    const host = hostMatch[1]!;
    const repoPath = hostMatch[2]!;
    return {
      cloneUrl: `git@${host}:${repoPath}.git`,
      dirName: path.basename(repoPath),
      host,
    };
  }

  // Plain org/repo shorthand → default to GitHub
  const parts = spec.split("/");
  if (parts.length === 2) {
    return {
      cloneUrl: `git@${defaultHost}:${spec}.git`,
      dirName: parts[1]!,
      host: defaultHost,
    };
  }

  // Fallback: treat as bare repo name
  return {
    cloneUrl: `git@${defaultHost}:${spec}.git`,
    dirName: spec,
    host: defaultHost,
  };
}

/**
 * Check if a directory is a git repo.
 */
export async function isGitRepo(dir: string): Promise<boolean> {
  try {
    await exec("git", ["rev-parse", "--git-dir"], dir);
    return true;
  } catch {
    return false;
  }
}

/**
 * Clone a repo if it doesn't exist locally. Returns the local path.
 */
export async function ensureRepo(reposDir: string, spec: string, defaultHost?: string): Promise<{
  repoPath: string;
  cloned: boolean;
  host: string;
}> {
  const resolved = resolveRepoSpec(spec, defaultHost);
  const repoPath = path.join(reposDir, resolved.dirName);

  // Already exists and is a git repo
  if (await isGitRepo(repoPath)) {
    return { repoPath, cloned: false, host: resolved.host };
  }

  // Directory exists but not a git repo — don't touch it
  try {
    const stat = await fs.stat(repoPath);
    if (stat.isDirectory()) {
      throw new Error(`目录 ${repoPath} 已存在但不是 git repo`);
    }
  } catch (e: any) {
    if (e.code !== "ENOENT") throw e;
  }

  // Clone
  await fs.mkdir(reposDir, { recursive: true });
  await exec("git", ["clone", resolved.cloneUrl, repoPath]);
  return { repoPath, cloned: true, host: resolved.host };
}
