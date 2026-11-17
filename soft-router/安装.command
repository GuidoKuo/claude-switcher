#!/bin/bash
# 独立的软路由试用安装器：不安装 root 守护进程、不改网络和时区。
set -euo pipefail
cd "$(dirname "$0")"
if [ "$(uname -s)" != Darwin ] || [ "$(uname -m)" != x86_64 ]; then echo '此安装包仅支持 Intel macOS。'; exit 1; fi
for cmd in python3 route ipconfig launchctl dig ditto; do
    command -v "$cmd" >/dev/null 2>&1 || { echo "缺少 ${cmd}，安装已停止。python3 可能需要安装 Apple 命令行工具。"; exit 1; }
done
[ -d /Applications/Claude.app ] || { echo '请先将 Claude 安装到 /Applications。'; exit 1; }
[ -x 'Claude切换器.app/Contents/MacOS/ClaudeSwitcher' ] && [ -f claude-switch.sh ] && [ -f stun-probe.py ] || { echo '安装包不完整'; exit 1; }
BASE="$HOME/.claude-switcher"; BIN="$HOME/.local/bin/claude-switch.sh"; APP="$HOME/Applications/Claude切换器.app"
# 不覆盖既有安装，避免触发旧版自动更新、保镖和无法预期的数据迁移。
for file in "$BIN" "$BASE/router-network" "$BASE/stun-probe.py" "$BASE/current" "$BASE/accounts" "$BASE/checks.json" "$APP" "$HOME/Library/LaunchAgents/local.claude-update.plist" /Library/LaunchDaemons/local.claude-bodyguard.plist /Library/LaunchDaemons/local.tz-watchdog.plist /Library/LaunchDaemons/local.claude-update.plist; do
    [ ! -e "$file" ] || { echo "发现已有安装或守护进程：$file"; echo '已停止，未修改文件；请先确认旧版卸载和账号备份。'; exit 1; }
done
for label in system/local.claude-bodyguard system/local.tz-watchdog system/local.claude-update "gui/$(id -u)/local.claude-update"; do
    if launchctl print "$label" >/dev/null 2>&1; then echo "检测到运行中的旧服务 ${label}，安装已停止。"; exit 1; fi
done
route_info=$(route -n get default 2>/dev/null) || { echo '读取默认路由失败'; exit 1; }
gw=$(printf '%s\n' "$route_info" | awk '$1=="gateway:" {print $2;exit}')
iface=$(printf '%s\n' "$route_info" | awk '$1=="interface:" {print $2;exit}')
[ -n "$gw" ] && [ -n "$iface" ] || { echo '默认路由不完整'; exit 1; }
ip=$(ipconfig getifaddr "$iface" 2>/dev/null) || { echo '未检测到接口 IPv4 地址'; exit 1; }
[ -n "$ip" ] || { echo '未检测到接口 IPv4 地址'; exit 1; }
echo "检测到：网关 ${gw}，接口 ${iface}，本机 IP $ip"
echo '安装后这些地址发生变化时将阻止切换，需要重新配置。'
echo '警告：本版没有故障断网保护；DNS/HTTPS 检测会访问外部服务，WebRTC 未验证。'
echo '不安装 root 守护进程，不自动改路由器、时区、地区或 IPv6。'
read -r -p '确认这是软路由网关且接受上述风险？输入 YES 继续：' ans
[ "$ans" = YES ] || { echo '已取消，未安装。'; exit 1; }
read -r -p '请输入期望的出口国家两位代码（例如 US）：' country
case "$country" in [A-Z][A-Z]) ;; *) echo '国家代码无效，已取消。'; exit 1 ;; esac
umask 077
mkdir -p "$HOME/.local/bin" "$HOME/Applications" "$BASE" "$HOME/Library/Logs"
tmp=$(mktemp -d "${TMPDIR:-/tmp}/claude-router.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
sed -e 's/^PROXY_MODE="[^"]*"/PROXY_MODE="router"/' -e "s/^COUNTRY_TARGET=\"[^\"]*\"/COUNTRY_TARGET=\"$country\"/" claude-switch.sh > "$tmp/claude-switch.sh"
grep -q '^PROXY_MODE="router"' "$tmp/claude-switch.sh" || { echo '配置生成失败'; exit 1; }
chmod 700 "$tmp/claude-switch.sh"
printf '%s\n%s\n%s\n' "$gw" "$iface" "$ip" > "$tmp/router-network"
ditto 'Claude切换器.app' "$tmp/Claude切换器.app"
# 文件不存在时才落盘；不触碰已有账号和应用数据。
cp -n "$tmp/router-network" "$BASE/router-network"
cp -n stun-probe.py "$BASE/stun-probe.py"
cp -n "$tmp/claude-switch.sh" "$BIN"
ditto "$tmp/Claude切换器.app" "$APP"
echo "安装完成：$APP"
echo '首次启动前请确认 OpenClash 已运行；仍无故障断网保护。'
echo '应用为 ad-hoc 签名，未经 Apple 公证。'
read -r -p '按回车退出。' _
