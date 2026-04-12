#!/usr/bin/env bash
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "请用 root 运行"; exit 1; }

# ═══════════════════════════════════════════
#  变量与工具
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

NEKO_WEB_PORT="${NEKO_WEB_PORT:-3000}"
NEKO_WS_PORT="${NEKO_WS_PORT:-3002}"

# 订阅配置
SUB_URL="${SUB_URL:-}"
SUB_INTERVAL="${SUB_INTERVAL:-86400}"  # 默认 24 小时更新一次

MODE=""
UPDATE_MIHOMO=false
UPDATE_NEKO=false

backup_file() {
  local f="$1"
  [[ -e "$f" ]] && cp -a "$f" "$f.bak.$(date +%F-%H%M%S)"
}

detect_iface() {
  ip route get 1.1.1.1 2>/dev/null | awk '
    /dev/ { for (i=1;i<=NF;i++) { if ($i=="dev") { print $(i+1); exit } } }
  '
}

# ═══════════════════════════════════════════
#  参数解析
# ═══════════════════════════════════════════
while [[ $# -gt 0 ]]; do
  case "$1" in
    install-mihomo)  MODE="install-mihomo"; shift ;;
    install-neko)    MODE="install-neko"; shift ;;
    enable-bypass)   MODE="enable-bypass"; shift ;;
    disable-bypass)  MODE="disable-bypass"; shift ;;
    --update|-u)     MODE="update"; UPDATE_MIHOMO=true; UPDATE_NEKO=true; shift ;;
    --update-mihomo) MODE="update"; UPDATE_MIHOMO=true; shift ;;
    --update-neko)   MODE="update"; UPDATE_NEKO=true; shift ;;
    --help|-h)
      echo "用法: $0 [命令]"
      echo ""
      echo "命令:"
      echo "  (无参数)              进入交互式菜单"
      echo "  install-mihomo        安装 Mihomo (旁路代理核心)"
      echo "  install-neko          安装 Neko Master (流量可视化面板)"
      echo "  enable-bypass         开启旁路模式 (iptables 透明代理)"
      echo "  disable-bypass        关闭旁路模式"
      echo "  --update, -u          更新全部"
      echo "  --update-mihomo       仅更新 Mihomo"
      echo "  --update-neko         仅更新 Neko"
      echo "  --help, -h            显示帮助"
      echo ""
      echo "环境变量:"
      echo "  SUB_URL              订阅链接 (可选)"
      echo "  SUB_INTERVAL         订阅更新间隔 (秒，默认 86400=24小时)"
      echo "  LAN_IFACE            网卡名称 (默认自动检测)"
      echo "  HTTP_PORT            HTTP 代理端口 (默认 7890)"
      echo "  API_PORT             Mihomo API 端口 (默认 9090)"
      echo "  NEKO_WEB_PORT        Neko Web 端口 (默认 3000)"
      exit 0
      ;;
    *) echo "未知参数: $1"; exit 1 ;;
  esac
done

# ═══════════════════════════════════════════
#  安装 Mihomo
# ═══════════════════════════════════════════
install_mihomo() {
  echo "╔══════════════════════════════════════════════╗"
  echo "║              安装 Mihomo                      ║"
  echo "╚══════════════════════════════════════════════╝"
  echo ""

  # 检查是否已安装
  if [[ -x "$MIHOMO_BIN" ]]; then
    echo "✅ Mihomo 已安装: $($MIHOMO_BIN -v 2>/dev/null | head -1)"
    echo "   如需重新安装，请先卸载: rm $MIHOMO_BIN"
    return 0
  fi

  echo "❌ 未发现 mihomo 可执行文件"
  echo ""
  echo "请手动下载 mihomo:"
  echo "  1. 访问 https://github.com/MetaCubeX/mihomo/releases"
  echo "  2. 下载适合你架构的版本"
  echo "  3. 解压并重命名为 mihomo"
  echo "  4. 移动到 $MIHOMO_BIN"
  echo "  5. chmod +x $MIHOMO_BIN"
  echo ""
  echo "或者使用自动安装:"
  echo "  curl -fsSL https://raw.githubusercontent.com/guokebang/openclaw-plugin/master/scripts/install-mihomo-neko.sh | bash"
  echo ""
}

# ═══════════════════════════════════════════
#  安装 Neko Master
# ═══════════════════════════════════════════
install_neko() {
  echo "╔══════════════════════════════════════════════╗"
  echo "║           安装 Neko Master                    ║"
  echo "╚══════════════════════════════════════════════╝"
  echo ""

  if ! command -v docker &>/dev/null; then
    echo "❌ Docker 未安装"
    read -rp "是否现在安装 Docker？[y/N] " answer
    if [[ "$answer" =~ ^[yY] ]]; then
      curl -fsSL https://get.docker.com | sh
      systemctl enable --now docker
    else
      exit 1
    fi
  fi

  if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "neko-master"; then
    echo "✅ Neko Master 已安装并运行"
    return 0
  fi

  echo "[1/3] 准备目录..."
  mkdir -p "$MIHOMO_DIR/neko-data"

  COOKIE_SECRET="$(openssl rand -hex 32)"

  echo "[2/3] 写入 docker-compose.yml..."
  cat > "$MIHOMO_DIR/docker-compose.yml" <<EOF
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
EOF

  echo "[3/3] 启动 Neko Master..."
  cd "$MIHOMO_DIR" && docker compose up -d

  HOST_IP="$(hostname -I | awk '{print $1}')"
  echo ""
  echo "✅ Neko Master 已安装！"
  echo "   访问: http://${HOST_IP}:${NEKO_WEB_PORT}"
  echo ""
  echo "   连接 Mihomo API:"
  echo "   类型:  Mihomo"
  echo "   地址:  127.0.0.1"
  echo "   端口:  ${API_PORT}"
}

# ═══════════════════════════════════════════
#  开启旁路模式
# ═══════════════════════════════════════════
enable_bypass() {
  echo "╔══════════════════════════════════════════════╗"
  echo "║              开启旁路模式                     ║"
  echo "╚══════════════════════════════════════════════╝"
  echo ""

  if [[ ! -x "$MIHOMO_BIN" ]]; then
    echo "❌ Mihomo 未安装，请先安装 (菜单选项 1)"
    exit 1
  fi

  if ! systemctl is-active --quiet mihomo; then
    echo "❌ Mihomo 服务未运行"
    exit 1
  fi

  echo "[1/3] 检测网络参数..."
  LAN_IFACE="$(detect_iface)"
  [[ -n "$LAN_IFACE" ]] || { echo "❌ 无法识别网卡"; exit 1; }
  CLIENT_CIDR="$(ip -o -4 addr show dev "$LAN_IFACE" | awk '{print $4}' | head -n1)"
  UPSTREAM_GW="$(ip route | awk '/default via/ {print $3; exit}')"

  echo "  网卡: $LAN_IFACE"
  echo "  客户端网段: $CLIENT_CIDR"
  echo "  上游网关: $UPSTREAM_GW"
  echo ""

  # 如果 config.yaml 不存在，创建它
  if [[ ! -f "${MIHOMO_DIR}/config.yaml" ]]; then
    echo "[1.5/3] 创建 Mihomo 配置..."
    if [[ -z "${API_SECRET}" ]]; then
      API_SECRET="$(openssl rand -hex 16)"
    fi

    UPSTREAM_DNS="${UPSTREAM_GW}"

    # 生成订阅相关配置
    PROXIES_CONFIG=""
    PROXY_GROUPS_CONFIG=""
    PROXY_PROVIDERS=""

    if [[ -n "$SUB_URL" ]]; then
      PROXIES_CONFIG="
# 代理节点由订阅自动更新
proxies: []
"
      PROXY_GROUPS_CONFIG='
proxy-groups:
  - name: "AUTO"
    type: url-test
    proxies:
      - "DIRECT"
    url: "http://www.gstatic.com/generate_204"
    interval: 300
    tolerance: 50
    use:
      - "Subscription"

  - name: "PROXY"
    type: select
    proxies:
      - "AUTO"
      - "DIRECT"
    use:
      - "Subscription"
'
      PROXY_PROVIDERS="
proxy-providers:
  Subscription:
    type: http
    url: \"${SUB_URL}\"
    interval: ${SUB_INTERVAL}
    health-check:
      enable: true
      url: http://www.gstatic.com/generate_204
      interval: 300
    proxy: DIRECT
"
    else
      PROXIES_CONFIG='
proxies:
  - { name: "your-node", type: direct }
'
      PROXY_GROUPS_CONFIG='
proxy-groups:
  - name: "PROXY"
    type: select
    proxies:
      - "your-node"
      - "DIRECT"
'
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

${PROXIES_CONFIG}

${PROXY_GROUPS_CONFIG}

${PROXY_PROVIDERS}

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

    if [[ -n "$SUB_URL" ]]; then
      echo "   ✅ 订阅已配置: $SUB_URL"
      echo "   自动更新间隔: ${SUB_INTERVAL}秒 ($((SUB_INTERVAL / 3600)) 小时)"
    fi

    # 验证配置
    if "${MIHOMO_BIN}" -t -d "${MIHOMO_DIR}" &>/dev/null; then
      echo "   ✅ 配置验证通过"
    else
      echo "   ⚠️  配置验证失败，请检查 config.yaml"
    fi

    # 启动 mihomo 服务
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

    systemctl daemon-reload
    systemctl enable --now mihomo.service
    sleep 2
  fi

  echo "[2/3] 写入 iptables 规则..."
  backup_file /etc/default/mihomo-bypass
  cat > /etc/default/mihomo-bypass <<EOF
LAN_IFACE=${LAN_IFACE}
CLIENT_CIDR=${CLIENT_CIDR}
UPSTREAM_GW=${UPSTREAM_GW}
UPSTREAM_DNS=${UPSTREAM_GW}
REDIR_PORT=${REDIR_PORT}
DNS_PORT=${DNS_PORT}
BLOCK_QUIC=${BLOCK_QUIC:-1}
EOF

  # 写入 apply 脚本
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

  # 清理脚本
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

  # sysctl
  backup_file /etc/sysctl.d/90-mihomo-bypass.conf
  cat > /etc/sysctl.d/90-mihomo-bypass.conf <<EOF
net.ipv4.ip_forward=1
EOF
  sysctl --system >/dev/null

  # systemd
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

  echo "[3/3] 启用旁路服务..."
  systemctl daemon-reload
  systemctl enable --now mihomo-bypass.service

  echo ""
  echo "✅ 旁路模式已开启！"
  echo "   网卡: ${LAN_IFACE}"
  echo "   客户端网段: ${CLIENT_CIDR}"
  echo ""
  echo "   让需要走旁路的设备把默认网关改为本机 IP"
  echo "   关闭旁路: bash $0 disable-bypass"
}

# ═══════════════════════════════════════════
#  关闭旁路模式
# ═══════════════════════════════════════════
disable_bypass() {
  echo "╔══════════════════════════════════════════════╗"
  echo "║              关闭旁路模式                     ║"
  echo "╚══════════════════════════════════════════════╝"
  echo ""

  if [[ -x /usr/local/sbin/mihomo-bypass-clear.sh ]]; then
    /usr/local/sbin/mihomo-bypass-clear.sh
    systemctl stop mihomo-bypass.service 2>/dev/null || true
    systemctl disable mihomo-bypass.service 2>/dev/null || true
    echo ""
    echo "✅ 旁路模式已关闭，所有流量恢复直连"
  else
    echo "⬜ 旁路模式未启用"
  fi
}

# ═══════════════════════════════════════════
#  状态检查
# ═══════════════════════════════════════════
show_status() {
  echo "╔══════════════════════════════════════════════╗"
  echo "║               系统状态检查                    ║"
  echo "╚══════════════════════════════════════════════╝"
  echo ""

  echo "── Mihomo ──"
  if [[ -x "$MIHOMO_BIN" ]]; then
    echo "  状态: ✅ 已安装"
    echo "  版本: $($MIHOMO_BIN -v 2>/dev/null | head -1)"
    systemctl is-active --quiet mihomo && echo "  服务: ✅ 运行中" || echo "  服务: ❌ 未运行"
  else
    echo "  状态: ❌ 未安装"
  fi
  echo ""

  echo "── 旁路模式 ──"
  if systemctl is-active --quiet mihomo-bypass 2>/dev/null; then
    echo "  状态: ✅ 已开启"
  else
    echo "  状态: ⬜ 未开启"
  fi
  echo ""

  echo "── Neko Master ──"
  if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "neko-master"; then
    echo "  状态: ✅ 运行中"
    echo "  镜像: $(docker inspect neko-master --format '{{.Config.Image}}' 2>/dev/null)"
  else
    echo "  状态: ⬜ 未安装"
  fi
  echo ""
}

# ═══════════════════════════════════════════
#  更新功能
# ═══════════════════════════════════════════
run_update() {
  echo "╔══════════════════════════════════════════════╗"
  echo "║              更新检查                        ║"
  echo "╚══════════════════════════════════════════════╝"
  echo ""

  if [[ "$UPDATE_MIHOMO" == "true" ]]; then
    echo "[1/2] 检查 Mihomo 更新..."
    if [[ -x "$MIHOMO_BIN" ]]; then
      CURRENT_VERSION="$($MIHOMO_BIN -v 2>/dev/null | head -1 || echo "unknown")"
      echo "  当前版本: $CURRENT_VERSION"
      LATEST_VERSION="$(curl -fsSL --max-time 10 \
        https://api.github.com/repos/MetaCubeX/mihomo/releases/latest \
        | grep -oP '"tag_name":\s*"v?\K[^"]+' || echo "")"
      if [[ -n "$LATEST_VERSION" ]]; then
        echo "  最新版本: $LATEST_VERSION"
        if [[ "$CURRENT_VERSION" == *"$LATEST_VERSION"* ]]; then
          echo "  ✅ 已是最新"
        else
          echo "  🔄 开始更新..."
          ARCH="$(uname -m)"
          case "$ARCH" in
            x86_64|amd64) MIHOMO_ARCH="amd64" ;;
            aarch64|arm64) MIHOMO_ARCH="arm64" ;;
            *) echo "  ❌ 不支持的架构: $ARCH"; exit 1 ;;
          esac
          backup_file "$MIHOMO_BIN"
          DOWNLOAD_URL="https://github.com/MetaCubeX/mihomo/releases/download/v${LATEST_VERSION}/mihomo-linux-${MIHOMO_ARCH}-v${LATEST_VERSION}.gz"
          if curl -fsSL --max-time 30 "$DOWNLOAD_URL" -o /tmp/mihomo-new.gz; then
            gzip -df /tmp/mihomo-new.gz
            mv /tmp/mihomo-new "$MIHOMO_BIN"
            chmod +x "$MIHOMO_BIN"
            systemctl restart mihomo 2>/dev/null || true
            echo "  ✅ 更新成功: $($MIHOMO_BIN -v 2>/dev/null | head -1)"
          else
            echo "  ❌ 下载失败"
          fi
        fi
      else
        echo "  ⚠️ 无法获取最新版本"
      fi
    else
      echo "  ⚠️ Mihomo 未安装"
    fi
    echo ""
  fi

  if [[ "$UPDATE_NEKO" == "true" ]]; then
    echo "[2/2] 检查 Neko Master 更新..."
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "neko-master"; then
      cd "$MIHOMO_DIR" 2>/dev/null || { echo "  ⚠️  未找到 $MIHOMO_DIR"; exit 1; }
      if docker compose pull neko-master 2>/dev/null; then
        docker compose up -d
        echo "  ✅ Neko Master 已更新"
      else
        echo "  ⚠️ 拉取失败或已是最新"
      fi
    else
      echo "  ⚠️ Neko Master 未运行"
    fi
    echo ""
  fi

  echo "✅ 更新完成"
}

# ═══════════════════════════════════════════
#  辅助命令
# ═══════════════════════════════════════════
restart_services() {
  systemctl restart mihomo && echo "✅ Mihomo 已重启" || echo "❌ Mihomo 重启失败"
  cd "$MIHOMO_DIR" && docker compose restart 2>/dev/null && echo "✅ Neko 已重启" || echo "⚠️  Neko 未运行"
}

view_logs() {
  echo "── Mihomo 日志 (最近 50 行) ──"
  journalctl -u mihomo -n 50 --no-pager
  echo ""
  echo "── Neko Master 日志 (最近 20 行) ──"
  docker logs neko-master --tail 20 2>/dev/null || echo "Neko 未运行"
}

# ═══════════════════════════════════════════
#  菜单
# ═══════════════════════════════════════════
show_menu() {
  echo "╔══════════════════════════════════════════════════════╗"
  echo "║        Mihomo + Neko Master 管理菜单                  ║"
  echo "╠══════════════════════════════════════════════════════╣"
  echo "║                                                      ║"
  echo "║  ── 安装 ──                                          ║"
  echo "║  1) 安装 Mihomo (旁路代理核心)                        ║"
  echo "║  2) 安装 Neko Master (流量可视化面板)                  ║"
  echo "║                                                      ║"
  echo "║  ── 旁路模式 ──                                      ║"
  echo "║  3) 开启旁路模式 (iptables 透明代理)                   ║"
  echo "║  4) 关闭旁路模式 (恢复直连)                            ║"
  echo "║                                                      ║"
  echo "║  ── 更新 ──                                          ║"
  echo "║  5) 更新 Mihomo                                      ║"
  echo "║  6) 更新 Neko Master                                 ║"
  echo "║  7) 更新全部                                         ║"
  echo "║                                                      ║"
  echo "║  ── 管理 ──                                          ║"
  echo "║  8) 检查状态                                         ║"
  echo "║  9) 重启服务                                         ║"
  echo "║  10) 查看日志                                        ║"
  echo "║                                                      ║"
  echo "║  0) 退出                                             ║"
  echo "║                                                      ║"
  echo "╚══════════════════════════════════════════════════════╝"
  echo ""
  read -rp "请选择 [0-10]: " choice
  case "$choice" in
    1) install_mihomo ;;
    2) install_neko ;;
    3) enable_bypass ;;
    4) disable_bypass ;;
    5) MODE="update"; UPDATE_MIHOMO=true; run_update ;;
    6) MODE="update"; UPDATE_NEKO=true; run_update ;;
    7) MODE="update"; UPDATE_MIHOMO=true; UPDATE_NEKO=true; run_update ;;
    8) show_status ;;
    9) restart_services ;;
    10) view_logs ;;
    0) echo "退出"; exit 0 ;;
    *) echo "无效选择"; exit 1 ;;
  esac
}

# ═══════════════════════════════════════════
#  入口
# ═══════════════════════════════════════════
case "$MODE" in
  install-mihomo)  install_mihomo ;;
  install-neko)    install_neko ;;
  enable-bypass)   enable_bypass ;;
  disable-bypass)  disable_bypass ;;
  update)          run_update ;;
  "")              show_menu ;;
  *)               show_menu ;;
esac
