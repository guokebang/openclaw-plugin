#!/usr/bin/env python3
"""
GitHub Pre-Push Guard - AI 友好的推送前检查
返回结构化结果，便于 AI 理解和展示给用户
"""

import subprocess
import sys
import os
import json

def run(cmd, timeout=15):
    """执行命令并返回输出"""
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return result.returncode, result.stdout.strip(), result.stderr.strip()
    except Exception as e:
        return 1, "", str(e)

def get_repo_visibility():
    """获取 GitHub 仓库可见性"""
    rc, out, _ = run(['git', 'remote', 'get-url', 'origin'])
    if rc != 0:
        return None, "无法获取远程仓库地址"

    url = out.strip()
    if 'github.com' not in url:
        return None, "非 GitHub 仓库"

    # 解析 owner/repo
    if ':' in url:
        colon_part = url.split(':')[-1].rstrip('.git')
    else:
        colon_part = url.rstrip('.git').split('/')[-1]
    
    parts = colon_part.split('/')
    if len(parts) == 2:
        owner, repo = parts
    else:
        return None, "无法解析仓库地址"

    # 使用 gh CLI 查询可见性
    rc, out, _ = run(['gh', 'api', f'repos/{owner}/{repo}', '--jq', '.visibility'])
    if rc == 0:
        return out.strip(), None

    return None, "无法确定可见性（需要安装 gh CLI）"

def check_secrets_staged():
    """扫描 staged 文件的敏感信息"""
    script_dir = os.path.dirname(os.path.abspath(__file__))
    check_script = os.path.join(script_dir, 'check_secrets.py')

    rc, out, err = run([sys.executable, check_script, '--staged', '--commits', '3', '--json'])
    return rc, out

def main():
    print("🛡️  GitHub Pre-Push Guard")
    print("=" * 40)
    print()

    # 1. 检查是否在 git 仓库中
    rc, _, _ = run(['git', 'rev-parse', '--is-inside-work-tree'])
    if rc != 0:
        print("❌ 当前目录不是 git 仓库")
        sys.exit(1)

    # 2. 检查是否有 staged 内容
    rc, out, _ = run(['git', 'diff', '--cached', '--name-only'])
    if rc != 0 or not out.strip():
        print("ℹ️  没有 staged 的内容，跳过检查")
        sys.exit(0)

    print("📂 检测到 staged 文件")
    print()

    # 3. 检查仓库可见性
    print("🔍 检查仓库可见性...")
    visibility, err = get_repo_visibility()

    if err:
        print(f"   ⚠️  {err}")
        print("   继续执行敏感信息扫描（保守策略）...")
        visibility = "public"

    print(f"   可见性: {visibility}")
    print()

    # 4. 如果是私有仓库，可选跳过
    if visibility == "private":
        print("🔒 私有仓库，跳过敏感信息检查")
        sys.exit(0)

    # 5. 扫描敏感信息（JSON 输出）
    print("🔎 扫描敏感信息...")
    rc, findings_json, _ = check_secrets_staged()

    if rc == 0:
        print("   ✅ 未发现敏感信息")
        print()
        print("🚀 可以安全推送")
        sys.exit(0)

    # 6. 发现敏感信息，展示报告
    findings = json.loads(findings_json)
    high = [f for f in findings if f['risk'] == 'HIGH']
    medium = [f for f in findings if f['risk'] == 'MEDIUM']

    print(f"\n⚠️  发现 {len(findings)} 个潜在敏感信息：")
    print(f"🔴 HIGH:   {len(high)}")
    print(f"🟡 MEDIUM: {len(medium)}")
    print()

    # 按文件分组展示
    current_file = None
    for i, f in enumerate(findings, 1):
        if f['file'] != current_file:
            print(f"📁 {f['file']}")
            current_file = f['file']
        icon = "🔴" if f['risk'] == 'HIGH' else "🟡"
        print(f"  {i:>3}. [{icon} {f['risk']}] {f['pattern']}")
        print(f"       行 {f['line']}: {f['preview'][:80]}")
        print()

    print("═" * 60)
    print("  ⛔ 推送已暂停")
    print("═" * 60)
    print()
    print("请输入以下之一：")
    print('  • "确认" / "push" / "继续" → 强制推送（不推荐）')
    print('  • "取消" / "不推了" / "先修复" → 中止推送')
    print()

    try:
        answer = input("你的选择：").strip().lower()
    except (EOFError, KeyboardInterrupt):
        answer = ""

    if answer in ('确认', 'push', '继续', 'yes', 'y'):
        print()
        print("⚠️  用户确认强制推送，继续执行...")
        sys.exit(0)
    else:
        print()
        print("❌ 推送已取消")
        print()
        print("建议操作：")
        print("  1. 使用 .gitignore 排除敏感文件")
        print("  2. 使用环境变量代替硬编码密钥")
        print("  3. 使用 git-crypt 或 SOPS 加密敏感文件")
        sys.exit(1)

if __name__ == '__main__':
    main()
