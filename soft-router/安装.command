#!/bin/bash
# 专用软路由版：明确选择迁移，旧文件先备份；不更改网络配置。
set -euo pipefail
cd "$(dirname "$0")"
. ./manage.sh
[ "$(uname -s)" = Darwin ] && [ "$(uname -m)" = x86_64 ] || { echo '此安装包仅支持 Intel macOS。'; exit 1; }
for cmd in python3 route ipconfig launchctl dig ditto; do command -v "$cmd" >/dev/null 2>&1 || { echo "缺少 ${cmd}；安装已停止。"; exit 1; }; done
python_path=$(command -v python3)
"$python_path" -c 'import json, pathlib, sys; assert sys.version_info >= (3, 7)' >/dev/null 2>&1 || { echo 'Python 3 无法运行；请先安装可用的 Python 3，再重新安装。'; exit 1; }
[ -d "$SYSTEM/Applications/Claude.app" ] || { echo '请先将 Claude 安装到 /Applications。'; exit 1; }
[ -x 'Claude切换器.app/Contents/MacOS/ClaudeSwitcher' ] && [ -f claude-switch.sh ] && [ -f stun-probe.py ] || { echo '安装包不完整'; exit 1; }
route_info=$(route -n get default 2>/dev/null) || { echo '读取默认路由失败'; exit 1; }
gw=$(printf '%s\n' "$route_info" | awk '$1=="gateway:" {print $2;exit}')
iface=$(printf '%s\n' "$route_info" | awk '$1=="interface:" {print $2;exit}')
[ -n "$gw" ] && [ -n "$iface" ] || { echo '默认路由不完整'; exit 1; }
ip=$(ipconfig getifaddr "$iface" 2>/dev/null) || { echo '未检测到接口 IPv4 地址'; exit 1; }
[ -n "$ip" ] || { echo '未检测到接口 IPv4 地址'; exit 1; }
echo "检测到：网关 ${gw}，接口 ${iface}，本机 IP ${ip}"
echo '请先退出旧版切换器，再继续。'
echo '本版不会安装保镖、不更改系统网络或时区；没有故障断网保护。'
echo '网络检测会访问 DNS 和外部服务，网络故障时可能直连。'
echo '旧版会先停止服务并备份，不删除 Claude 本体或当前登录数据。'
echo '1) 迁移当前切换器资料（账号存档、当前账号、CLI账号及保留路径）'
echo '2) 全新安装（旧资料仅备份，不迁移）'
echo '3) 取消'
read -r -p '请选择 1/2/3：' choice
case "$choice" in 1|2) ;; *) echo '已取消，未修改。'; exit 1 ;; esac
read -r -p '请输入期望的出口国家两位大写代码（新加坡 SG，美国 US）：' country
case "$country" in [A-Z][A-Z]) ;; *) echo '国家代码无效，未修改。'; exit 1 ;; esac
read -r -p '确认停用旧服务并备份旧文件，输入 YES 继续：' ans
[ "$ans" = YES ] || { echo '已取消，未修改。'; exit 1; }
umask 077
cleanup_old
trap 'rc=$?; if [ "$rc" -ne 0 ]; then echo "安装未完成；旧文件备份在 ${BACKUP}，请保留并提供报错。" >&2; fi' EXIT
mkdir -p "$HOME/.local/bin" "$HOME/Applications" "$BASE" "$HOME/Library/Logs"
if [ "$choice" = 1 ] && [ -d "$BACKUP/user/.claude-switcher" ]; then
    old="$BACKUP/user/.claude-switcher"
    for name in accounts current cli-accounts keep-in-workspace.txt keep-stage; do
        if [ -e "$old/$name" ] || [ -L "$old/$name" ]; then ditto "$old/$name" "$BASE/$name"; fi
    done
fi
sed -e 's/^PROXY_MODE="[^"]*"/PROXY_MODE="router"/' -e "s/^COUNTRY_TARGET=\"[^\"]*\"/COUNTRY_TARGET=\"$country\"/" claude-switch.sh > "$BIN"
grep -q '^PROXY_MODE="router"' "$BIN" || { echo "配置生成失败；旧文件在 $BACKUP"; exit 1; }
chmod 700 "$BIN"
printf '%s\n%s\n%s\n' "$gw" "$iface" "$ip" > "$BASE/router-network"
printf '%s\n' "$python_path" > "$BASE/router-python"
cp stun-probe.py "$BASE/stun-probe.py"
ditto 'Claude切换器.app' "$USER_APP"
echo "安装完成：$USER_APP"
echo "旧文件备份：${BACKUP}（可能含登录资料，请妥善保管）"
echo '新版无故障断网保护，未公证。仅从用户目录的应用程序打开新版。'
read -r -p '按回车退出。' _ || true
