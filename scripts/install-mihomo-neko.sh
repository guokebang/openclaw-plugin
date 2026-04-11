#!/usr/bin/env bash
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "请用 root 运行"; exit 1; }

# ═══════════════════════════════════════════
#  参数解析
# ═══════════════════════════════════════════
MODE="install"
UPDATE_MIHOMO=false
UPDATE_NEKO=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --update|-u)
      MODE="update"
      UPDATE_MIHOMO=true
      UPDATE_NEKO=true
      shift
      ;;
    --update-mihomo)
      MODE="update"
      UPDATE_MIHOMO=true
      shift
      ;;
    --update-neko)
      MODE="update"
      UPDATE_NEKO=true
      shift
      ;;
    --help|-h)
      echo "用法: $0 [选项]"
      echo ""
      echo "选项:"
      echo "  (无参数)          进入交互式菜单"
      echo "  install           全新安装 Mihomo + Neko Master"
      echo "  --update, -u      检查并更新 Mihomo 和 Neko Master"
      echo "  --update-mihomo   仅检查并更新 Mihomo"
      echo "  --update-neko     仅检查并更新 Neko Master"
      echo "  --help, -h        显示帮助"
      echo ""
      echo "环境变量:"
      echo "  LAN_IFACE         网卡名称 (默认自动检测)"
      echo "  HTTP_PORT         HTTP 代理端口 (默认 7890)"
      echo "  API_PORT          Mihomo API 端口 (默认 9090)"
      echo "  NEKO_WEB_PORT     Neko Web 端口 (默认 3000)"
      exit 0
      ;;
    install)
      MODE="install"
      shift
      ;;
    *)
      echo "未知参数: $1"
      echo "使用 --help 查看帮助"
      exit 1
      ;;
  esac
done

# ═══════════════════════════════════════════
#  菜单模式
# ═══════════════════════════════════════════
show_menu() {
  echo "╔══════════════════════════════════════════════════════╗"
  echo "║        Mihomo + Neko Master 管理菜单                  ║"
  echo "╠══════════════════════════════════════════════════════╣"
  echo "║                                                      ║"
  echo "║  1) 全新安装 Mihomo + Neko Master                    ║"
  echo "║  2) 更新 Mihomo                                      ║"
  echo "║  3) 更新 Neko Master                                 ║"
  echo "║  4) 更新全部 (Mihomo + Neko)                         ║"
  echo "║  5) 检查状态                                         ║"
  echo "║  6) 清理 iptables 规则                               ║"
  echo "║  7) 重启服务                                         ║"
  echo "║  8) 查看日志                                         ║"
  echo "║  0) 退出                                             ║"
  echo "║                                                      ║"
  echo "╚══════════════════════════════════════════════════════╝"
  echo ""
  read -rp "请选择 [0-8]: " choice

  case "$choice" in
    1) MODE="install" ;;
    2) MODE="update"; UPDATE_MIHOMO=true ;;
    3) MODE="update"; UPDATE_NEKO=true ;;
    4) MODE="update"; UPDATE_MIHOMO=true; UPDATE_NEKO=true ;;
    5) show_status; exit 0 ;;
    6) clear_rules; exit 0 ;;
    7) restart_services; exit 0 ;;
    8) view_logs; exit 0 ;;
    0) echo "退出"; exit 0 ;;
    *) echo "无效选择"; exit 1 ;;
  esac
}

show_status() {
  echo "╔══════════════════════════════════════════════╗"
  echo "║               系统状态检查                    ║"
  echo "╚══════════════════════════════════════════════╝"
  echo ""

  echo "── Mihomo ──"
  if [[ -x "${MIHOMO_BIN:-/usr/local/bin/mihomo}" ]]; then
    echo "  状态: ✅ 已安装"
    echo "  版本: $($MIHOMO_BIN -v 2>/dev/null | head -1)"
    systemctl is-active --quiet mihomo && echo "  服务: ✅ 运行中" || echo "  服务: ❌ 未运行"
  else
    echo "  状态: ❌ 未安装"
  fi
  echo ""

  echo "── Neko Master ──"
  if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "neko-master"; then
    echo "  状态: ✅ 运行中"
    echo "  镜像: $(docker inspect neko-master --format '{{.Config.Image}}' 2>/dev/null)"
  else
    echo "  状态: ❌ 未运行"
  fi
  echo ""

  echo "── iptables 规则 ──"
  iptables -t nat -L MIHOMO_PREROUTING -n &>/dev/null && echo "  规则: ✅ 已配置" || echo "  规则: ❌ 未配置"
  echo ""
}

clear_rules() {
  echo "清理 iptables 规则..."
  if [[ -x /usr/local/sbin/mihomo-bypass-clear.sh ]]; then
    /usr/local/sbin/mihomo-bypass-clear.sh
    echo "✅ 清理完成"
  else
    echo "❌ 清理脚本不存在"
  fi
}

restart_services() {
  echo "重启服务..."
  systemctl restart mihomo && echo "✅ Mihomo 已重启" || echo "❌ Mihomo 重启失败"
  cd "${MIHOMO_DIR:-/etc/mihomo}" && docker compose restart 2>/dev/null && echo "✅ Neko Master 已重启" || echo "⚠️  Neko Master 未运行"
}

view_logs() {
  echo "── 最近 50 行 Mihomo 日志 ──"
  journalctl -u mihomo -n 50 --no-pager
  echo ""
  echo "── Neko Master 日志 (最近 20 行) ──"
  docker logs neko-master --tail 20 2>/dev/null || echo "Neko Master 未运行"
}

# 如果没有指定模式，显示菜单
if [[ "$MODE" == "install" ]] && [[ "$UPDATE_MIHOMO" == "false" ]] && [[ "$UPDATE_NEKO" == "false" ]]; then
  # 检查是否已安装
  if [[ -x "${MIHOMO_BIN:-/usr/local/bin/mihomo}" ]] || docker ps --format '{{.Names}}' 2>/dev/null | grep -q "neko-master"; then
    show_menu
  fi
fi

# ═══════════════════════════════════════════
#  更新模式
# ═══════════════════════════════════════════
if [[ "$MODE" == "update" ]]; then
  echo "╔══════════════════════════════════════════════╗"
  echo "║         Mihomo + Neko Master 更新检查         ║"
  echo "╚══════════════════════════════════════════════╝"
  echo ""

  # ── 更新 Mihomo ──
  if [[ "$UPDATE_MIHOMO" == "true" ]]; then
    echo "[1/2] 检查 Mihomo 更新..."

    MIHOMO_BIN="${MIHOMO_BIN:-/usr/local/bin/mihomo}"

    if [[ -x "$MIHOMO_BIN" ]]; then
      CURRENT_VERSION="$($MIHOMO_BIN -v 2>/dev/null | head -1 || echo "unknown")"
      echo "  当前版本: $CURRENT_VERSION"
    else
      echo "  ⚠️  未找到 mihomo: $MIHOMO_BIN"
      CURRENT_VERSION=""
    fi

    # 获取最新版本
    LATEST_VERSION="$(curl -fsSL --max-time 10 \
      https://api.github.com/repos/MetaCubeX/mihomo/releases/latest \
      | grep -oP '"tag_name":\s*"v?\K[^"]+' || echo "")"

    if [[ -n "$LATEST_VERSION" ]]; then
      echo "  最新版本: $LATEST_VERSION"

      if [[ "$CURRENT_VERSION" == *"$LATEST_VERSION"* ]] || [[ "$CURRENT_VERSION" == *"v${LATEST_VERSION}"* ]]; then
        echo "  ✅ Mihomo 已是最新版本"
      else
        echo "  🔄 发现新版本，开始更新..."

        # 检测架构
        ARCH="$(uname -m)"
        case "$ARCH" in
          x86_64|amd64) MIHOMO_ARCH="amd64" ;;
          aarch64|arm64) MIHOMO_ARCH="arm64" ;;
          armv7l|armhf)  MIHOMO_ARCH="armv7" ;;
          *) echo "  ❌ 不支持的架构: $ARCH"; exit 1 ;;
        esac

        # 备份旧版本
        backup_file "$MIHOMO_BIN"

        # 下载新版本
        DOWNLOAD_URL="https://github.com/MetaCubeX/mihomo/releases/download/v${LATEST_VERSION}/mihomo-linux-${MIHOMO_ARCH}-v${LATEST_VERSION}.gz"
        echo "  下载: $DOWNLOAD_URL"

        if curl -fsSL --max-time 30 "$DOWNLOAD_URL" -o /tmp/mihomo-new.gz; then
          gzip -df /tmp/mihomo-new.gz
          mv /tmp/mihomo-new "$MIHOMO_BIN"
          chmod +x "$MIHOMO_BIN"

          # 验证
          NEW_VERSION="$($MIHOMO_BIN -v 2>/dev/null | head -1 || echo "unknown")"
          echo "  ✅ 更新成功: $NEW_VERSION"

          # 重启 mihomo 服务
          if systemctl is-active --quiet mihomo; then
            echo "  🔄 重启 mihomo 服务..."
            systemctl restart mihomo
          fi
        else
          echo "  ❌ 下载失败，已恢复备份"
          exit 1
        fi
      fi
    else
      echo "  ⚠️  无法获取最新版本信息"
    fi
    echo ""
  fi

  # ── 更新 Neko Master ──
  if [[ "$UPDATE_NEKO" == "true" ]]; then
    echo "[2/2] 检查 Neko Master 更新..."

    MIHOMO_DIR="${MIHOMO_DIR:-/etc/mihomo}"

    if command -v docker &>/dev/null && docker ps --format '{{.Names}}' | grep -q "neko-master"; then
      # 获取当前镜像
      CURRENT_IMAGE="$(docker inspect neko-master --format '{{.Config.Image}}' 2>/dev/null || echo "unknown")"
      echo "  当前镜像: $CURRENT_IMAGE"

      # 检查更新
      cd "$MIHOMO_DIR" 2>/dev/null || { echo "  ⚠️  未找到 $MIHOMO_DIR"; exit 1; }

      echo "  🔄 拉取最新镜像..."
      if docker compose pull neko-master 2>/dev/null || docker-compose pull neko-master 2>/dev/null; then
        echo "  🔄 重启 Neko Master..."
        docker compose up -d 2>/dev/null || docker-compose up -d 2>/dev/null
        echo "  ✅ Neko Master 已更新"
      else
        echo "  ⚠️  拉取失败，可能已是最新版本"
      fi
    else
      echo "  ⚠️  Neko Master 未运行或 Docker 未安装"
    fi
    echo ""
  fi

  echo "╔══════════════════════════════════════════════╗"
  echo "║                 更新完成                       ║"
  echo "╚══════════════════════════════════════════════╝"
  exit 0
fi

# ═══════════════════════════════════════════
#  变量配置（安装模式）
# ═══════════════════════════════════════════
MIHOMO_BIN="${MIHOMO_BIN:-/usr/local/bin/mihomo}"
MIHOMO_USER="${MIHOMO_USER:-mihomo}"
MIHOMO_DIR="${MIHOMO_DIR:-/etc/mihomo}"
STATE_DIR="${STATE_DIR:-/var/lib/mihomo}"

HTTP_PORT="${HTTP_PORT:-7890}"
SOCKS_PORT="${SOCKS_PORT:-7891}"
REDIR_PORT="${REDIR_PORT:-7892}"
DNS_PORT="${DNS_PORT:-1053}"
API_PORT="${API_PORT:-9090}"
API_SECRET="${API_SECRET:-}"

BLOCK_QUIC="${BLOCK_QUIC:-1}"

# Neko Master 配置
NEKO_WEB_PORT="${NEKO_WEB_PORT:-3000}"
NEKO_WS_PORT="${NEKO_WS_PORT:-3002}"

# ═══════════════════════════════════════════
#  自动检测
# ═══════════════════════════════════════════
detect_iface() {
  ip route get 1.1.1.1 2>/dev/null | awk '
    /dev/ { for (i=1;i<=NF;i++) { if ($i=="dev") { print $(i+1); exit } } }
  '
}

LAN_IFACE="${LAN_IFACE:-$(detect_iface)}"
[[ -n "${LAN_IFACE}" ]] || {
  echo "无法自动识别网卡，请手动指定: LAN_IFACE=ens160 bash $0"
  exit 1
}

CLIENT_CIDR="${CLIENT_CIDR:-$(ip -o -4 addr show dev "$LAN_IFACE" | awk '{print $4}' | head -n1)}"
UPSTREAM_GW="${UPSTREAM_GW:-$(ip route | awk '/default via/ {print $3; exit}')}"
UPSTREAM_DNS="${UPSTREAM_DNS:-$UPSTREAM_GW}"

[[ -x "$MIHOMO_BIN" ]] || {
  echo "未发现 mihomo: $MIHOMO_BIN (请自行下载并 chmod +x)"
  exit 1
}

# 检查 Docker
if ! command -v docker &>/dev/null; then
  echo "未检测到 Docker，是否现在安装？[y/N]"
  read -r answer
  if [[ "$answer" =~ ^[yY] ]]; then
    curl -fsSL https://get.docker.com | sh
    systemctl enable --now docker
  else
    echo "请先安装 Docker 再运行此脚本"
    exit 1
  fi
fi

backup_file() {
  local f="$1"
  [[ -e "$f" ]] && cp -a "$f" "$f.bak.$(date +%F-%H%M%S)"
}

# ═══════════════════════════════════════════
#  安装流程
# ═══════════════════════════════════════════

echo "[1/9] 安装依赖..."
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
  ca-certificates curl iproute2 iptables

echo "[2/9] 创建用户与目录..."
id -u "$MIHOMO_USER" >/dev/null 2>&1 || \
  useradd --system --home "$STATE_DIR" --shell /usr/sbin/nologin "$MIHOMO_USER"

mkdir -p "$MIHOMO_DIR" "$STATE_DIR" /usr/local/sbin /etc/default /etc/sysctl.d
chown -R "$MIHOMO_USER":"$MIHOMO_USER" "$MIHOMO_DIR" "$STATE_DIR"

echo "[3/9] 写入环境变量..."
backup_file /etc/default/mihomo-bypass
cat > /etc/default/mihomo-bypass <<EOF
LAN_IFACE=${LAN_IFACE}
CLIENT_CIDR=${CLIENT_CIDR}
UPSTREAM_GW=${UPSTREAM_GW}
UPSTREAM_DNS=${UPSTREAM_DNS}
REDIR_PORT=${REDIR_PORT}
DNS_PORT=${DNS_PORT}
API_PORT=${API_PORT}
BLOCK_QUIC=${BLOCK_QUIC}
EOF

echo "[4/9] 写入 Mihomo 配置..."
backup_file "${MIHOMO_DIR}/config.yaml"

# 生成 secret（如果没设置）
if [[ -z "${API_SECRET}" ]]; then
  API_SECRET="$(openssl rand -hex 16)"
fi

cat > "${MIHOMO_DIR}/config.yaml" <<EOF
# ── 基础 ──
port: ${HTTP_PORT}
socks-port: ${SOCKS_PORT}
redir-port: ${REDIR_PORT}
allow-lan: true
bind-address: "*"
mode: rule
log-level: info
ipv6: false
unified-delay: true
tcp-concurrent: true
find-process-mode: off

# ── 外部控制 (Neko Master 连接用) ──
external-controller: 0.0.0.0:${API_PORT}
secret: "${API_SECRET}"

# ── DNS ──
dns:
  enable: true
  listen: 0.0.0.0:${DNS_PORT}
  ipv6: false
  enhanced-mode: fake-ip
  fake-ip-range: 198.18.0.1/16
  use-hosts: true
  default-nameserver:
    - ${UPSTREAM_DNS}
    - 1.1.1.1
  nameserver:
    - ${UPSTREAM_DNS}
    - 223.5.5.5
    - 1.1.1.1
    - 8.8.8.8
  fallback:
    - 1.0.0.1
    - 8.8.4.4
  fake-ip-filter:
    - "*.lan"
    - "*.local"
    - "localhost.ptlogin2.qq.com"
    - "*.msftconnecttest.com"
    - "time.*"
    - "time.*.*"
    - "ntp.*"
    - "*.ntp.org"
    - "*.pool.ntp.org"

# ── 代理节点 (请替换为你自己的节点) ──
proxies:
  - { name: "your-node", type: direct }

# ── 节点组 ──
proxy-groups:
  - name: "PROXY"
    type: select
    proxies:
      - "your-node"
      - "DIRECT"

# ── 规则 ──
rules:
  - IP-CIDR,0.0.0.0/8,DIRECT,no-resolve
  - IP-CIDR,10.0.0.0/8,DIRECT,no-resolve
  - IP-CIDR,100.64.0.0/10,DIRECT,no-resolve
  - IP-CIDR,127.0.0.0/8,DIRECT,no-resolve
  - IP-CIDR,169.254.0.0/16,DIRECT,no-resolve
  - IP-CIDR,172.16.0.0/12,DIRECT,no-resolve
  - IP-CIDR,192.168.0.0/16,DIRECT,no-resolve
  - IP-CIDR,224.0.0.0/4,DIRECT,no-resolve
  - IP-CIDR,240.0.0.0/4,DIRECT,no-resolve
  - IP-CIDR6,::1/128,DIRECT,no-resolve
  - IP-CIDR6,fc00::/7,DIRECT,no-resolve
  - IP-CIDR6,fe80::/10,DIRECT,no-resolve
  - MATCH,PROXY
EOF

chown "$MIHOMO_USER":"$MIHOMO_USER" "${MIHOMO_DIR}/config.yaml"
chmod 640 "${MIHOMO_DIR}/config.yaml"

echo "[5/9] 写入 iptables 规则脚本..."
cat > /usr/local/sbin/mihomo-bypass-apply.sh <<'APPLYEOF'
#!/usr/bin/env bash
set -euo pipefail
source /etc/default/mihomo-bypass

sysctl -w net.ipv4.ip_forward=1 >/dev/null

iptables -t nat -N MIHOMO_PREROUTING 2>/dev/null || true
iptables -t nat -F MIHOMO_PREROUTING
iptables -t nat -N MIHOMO_TCP 2>/dev/null || true
iptables -t nat -F MIHOMO_TCP
iptables -N MIHOMO_FWD 2>/dev/null || true
iptables -F MIHOMO_FWD

# DNS 劫持
iptables -t nat -A MIHOMO_PREROUTING -p udp --dport 53 -j REDIRECT --to-ports "${DNS_PORT}"
iptables -t nat -A MIHOMO_PREROUTING -p tcp --dport 53 -j REDIRECT --to-ports "${DNS_PORT}"
iptables -t nat -A MIHOMO_PREROUTING -p tcp -j MIHOMO_TCP

# 私有地址白名单
for cidr in 0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 \
            169.254.0.0/16 172.16.0.0/12 192.168.0.0/16 224.0.0.0/4 240.0.0.0/4; do
  iptables -t nat -A MIHOMO_TCP -d "$cidr" -j RETURN
done

iptables -t nat -A MIHOMO_TCP -p tcp -j REDIRECT --to-ports "${REDIR_PORT}"

iptables -t nat -C POSTROUTING -s "${CLIENT_CIDR}" -o "${LAN_IFACE}" -j MASQUERADE 2>/dev/null || \
iptables -t nat -I POSTROUTING 1 -s "${CLIENT_CIDR}" -o "${LAN_IFACE}" -j MASQUERADE

iptables -C FORWARD -i "${LAN_IFACE}" -o "${LAN_IFACE}" -j MIHOMO_FWD 2>/dev/null || \
iptables -I FORWARD 1 -i "${LAN_IFACE}" -o "${LAN_IFACE}" -j MIHOMO_FWD

iptables -A MIHOMO_FWD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A MIHOMO_FWD -s "${CLIENT_CIDR}" -j ACCEPT

if [[ "${BLOCK_QUIC}" == "1" ]]; then
  iptables -C FORWARD -i "${LAN_IFACE}" -p udp --dport 443 -j REJECT 2>/dev/null || \
  iptables -I FORWARD 1 -i "${LAN_IFACE}" -p udp --dport 443 -j REJECT
fi

iptables -t nat -C PREROUTING -i "${LAN_IFACE}" -j MIHOMO_PREROUTING 2>/dev/null || \
iptables -t nat -I PREROUTING 1 -i "${LAN_IFACE}" -j MIHOMO_PREROUTING
APPLYEOF
chmod +x /usr/local/sbin/mihomo-bypass-apply.sh

echo "[6/9] 写入清理脚本..."
cat > /usr/local/sbin/mihomo-bypass-clear.sh <<'CLEAREOF'
#!/usr/bin/env bash
set -euo pipefail
source /etc/default/mihomo-bypass

iptables -t nat -D PREROUTING -i "${LAN_IFACE}" -j MIHOMO_PREROUTING 2>/dev/null || true
iptables -D FORWARD -i "${LAN_IFACE}" -o "${LAN_IFACE}" -j MIHOMO_FWD 2>/dev/null || true
iptables -D FORWARD -i "${LAN_IFACE}" -p udp --dport 443 -j REJECT 2>/dev/null || true
iptables -t nat -D POSTROUTING -s "${CLIENT_CIDR}" -o "${LAN_IFACE}" -j MASQUERADE 2>/dev/null || true

iptables -t nat -F MIHOMO_PREROUTING 2>/dev/null || true
iptables -t nat -X MIHOMO_PREROUTING 2>/dev/null || true
iptables -t nat -F MIHOMO_TCP 2>/dev/null || true
iptables -t nat -X MIHOMO_TCP 2>/dev/null || true
iptables -F MIHOMO_FWD 2>/dev/null || true
iptables -X MIHOMO_FWD 2>/dev/null || true
CLEAREOF
chmod +x /usr/local/sbin/mihomo-bypass-clear.sh

echo "[7/9] 写入 sysctl + systemd..."
backup_file /etc/sysctl.d/90-mihomo-bypass.conf
cat > /etc/sysctl.d/90-mihomo-bypass.conf <<EOF
net.ipv4.ip_forward=1
EOF
sysctl --system >/dev/null

# Mihomo 服务
backup_file /etc/systemd/system/mihomo.service
cat > /etc/systemd/system/mihomo.service <<EOF
[Unit]
Description=Mihomo
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${MIHOMO_USER}
Group=${MIHOMO_USER}
WorkingDirectory=${MIHOMO_DIR}
ExecStart=${MIHOMO_BIN} -d ${MIHOMO_DIR}
Restart=on-failure
RestartSec=3
LimitNOFILE=1048576
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF

# 旁路规则服务
backup_file /etc/systemd/system/mihomo-bypass.service
cat > /etc/systemd/system/mihomo-bypass.service <<'EOF'
[Unit]
Description=Mihomo Bypass Router Rules
After=network-online.target mihomo.service
Wants=network-online.target mihomo.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/sbin/mihomo-bypass-apply.sh
ExecStop=/usr/local/sbin/mihomo-bypass-clear.sh

[Install]
WantedBy=multi-user.target
EOF

echo "[8/9] 部署 Neko Master..."

mkdir -p "$MIHOMO_DIR/neko-data"

COOKIE_SECRET="$(openssl rand -hex 32)"

cat > "$MIHOMO_DIR/docker-compose.yml" <<NEKOEOF
services:
  neko-master:
    image: foru17/neko-master:latest
    container_name: neko-master
    restart: unless-stopped
    network_mode: host
    volumes:
      - ./neko-data:/app/data
    environment:
      - NODE_ENV=production
      - DB_PATH=/app/data/stats.db
      - COOKIE_SECRET=${COOKIE_SECRET}
NEKOEOF

# 启动 Neko Master
cd "$MIHOMO_DIR" && docker compose up -d

echo "[9/9] 校验并启动 Mihomo..."
"${MIHOMO_BIN}" -t -d "${MIHOMO_DIR}"

systemctl daemon-reload
systemctl enable --now mihomo.service
systemctl enable --now mihomo-bypass.service

# 等待 Neko Master 启动
sleep 3

# ═══════════════════════════════════════════
#  输出摘要
# ═══════════════════════════════════════════
HOST_IP="$(hostname -I | awk '{print $1}')"

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║           安装完成！Mihomo + Neko Master             ║"
echo "╠══════════════════════════════════════════════════════╣"
echo "║                                                      ║"
echo "║  网卡:        ${LAN_IFACE}"
echo "║  客户端网段:  ${CLIENT_CIDR}"
echo "║  上游网关:    ${UPSTREAM_GW}"
echo "║                                                      ║"
echo "║  ── 代理端口 ──                                      ║"
echo "║  HTTP 代理:   0.0.0.0:${HTTP_PORT}"
echo "║  SOCKS 代理:  0.0.0.0:${SOCKS_PORT}"
echo "║  透明代理:    TCP REDIRECT → ${REDIR_PORT}"
echo "║  DNS 劫持:    TCP/UDP 53 → ${DNS_PORT}"
echo "║                                                      ║"
echo "║  ── Mihomo API (Neko 连接用) ──                      ║"
echo "║  地址:        ${HOST_IP}:${API_PORT}"
echo "║  Secret:      ${API_SECRET}"
echo "║                                                      ║"
echo "║  ── Neko Master 面板 ──                              ║"
echo "║  Web UI:      http://${HOST_IP}:${NEKO_WEB_PORT}"
echo "║  WebSocket:   :${NEKO_WS_PORT}"
echo "║                                                      ║"
echo "╠══════════════════════════════════════════════════════╣"
echo "║                                                      ║"
echo "║  📋 下一步:                                           ║"
echo "║                                                      ║"
echo "║  1. 打开 Neko Master: http://${HOST_IP}:${NEKO_WEB_PORT}"
echo "║  2. Settings → Backends → Add Backend                ║"
echo "║  3. 填写:                                             ║"
echo "║     类型:  Mihomo                                    ║"
echo "║     地址:  127.0.0.1                                 ║"
echo "║     端口:  ${API_PORT}"
echo "║     Token: ${API_SECRET}"
echo "║  4. 点击 Test Connection → Save                      ║"
echo "║                                                      ║"
echo "║  📋 其他命令:                                         ║"
echo "║  查看状态:  systemctl status mihomo                   ║"
echo "║  查看日志:  journalctl -u mihomo -f                   ║"
echo "║  清理规则:  /usr/local/sbin/mihomo-bypass-clear.sh    ║"
echo "║  重启面板:  cd /etc/mihomo && docker compose restart   ║"
echo "║  更新全部:  bash $0 --update                          ║"
echo "║  更新 Mihomo:  bash $0 --update-mihomo               ║"
echo "║  更新 Neko:    bash $0 --update-neko                 ║"
echo "║  管理菜单:    bash $0                                ║"
echo "║                                                      ║"
echo "╚══════════════════════════════════════════════════════╝"
