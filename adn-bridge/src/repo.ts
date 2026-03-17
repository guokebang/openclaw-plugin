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
 * Convert HTTPS GitHub URL to SSH URL for key-based auth.
 */
function httpsToSsh(url: string): string {
  const m = url.match(/^https?:\/\/github\.com\/([^/]+\/[^/]+?)(?:\.git)?$/);
  if (m) {
    return `git@github.com:${m[1]}.git`;
  }
  return url;
}

/**
 * Resolve a repo spec to a clone-able SSH URL and local dir name.
 *
 * Supported formats:
 * - "org/repo"                          → git@github.com:org/repo.git
 * - "https://github.com/org/repo"       → git@github.com:org/repo.git
 * - "https://github.com/org/repo.git"   → git@github.com:org/repo.git
 * - "git@github.com:org/repo.git"       → as-is
 */
export function resolveRepoSpec(spec: string): { cloneUrl: string; dirName: string } {
  // HTTPS GitHub URL → convert to SSH
  if (spec.startsWith("https://") || spec.startsWith("http://")) {
    const sshUrl = httpsToSsh(spec);
    const dirName = path.basename(spec.replace(/\.git$/, ""));
    return { cloneUrl: sshUrl, dirName };
  }
  // Already SSH
  if (spec.startsWith("git@")) {
    const dirName = path.basename(spec.replace(/\.git$/, ""));
    return { cloneUrl: spec, dirName };
  }
  // org/repo shorthand
  const parts = spec.split("/");
  if (parts.length === 2) {
    return {
      cloneUrl: `git@github.com:${spec}.git`,
      dirName: parts[1]!,
    };
  }
  // bare repo name
  return {
    cloneUrl: `git@github.com:${spec}.git`,
    dirName: spec,
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
export async function ensureRepo(reposDir: string, spec: string): Promise<{ repoPath: string; cloned: boolean }> {
  const { cloneUrl, dirName } = resolveRepoSpec(spec);
  const repoPath = path.join(reposDir, dirName);

  // Already exists and is a git repo
  if (await isGitRepo(repoPath)) {
    return { repoPath, cloned: false };
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
  await exec("git", ["clone", cloneUrl, repoPath]);
  return { repoPath, cloned: true };
}
