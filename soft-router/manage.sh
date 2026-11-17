#!/bin/bash
# 只处理本项目已知路径；先停服务、备份原件，不删除 Claude 用户资料。
set -euo pipefail
SYSTEM=""; ADMIN="sudo"
ROOT_PLISTS="$SYSTEM/Library/LaunchDaemons"
ROOT_APP="$SYSTEM/Applications/Claude切换器.app"
BASE="$HOME/.claude-switcher"
BIN="$HOME/.local/bin/claude-switch.sh"
USER_APP="$HOME/Applications/Claude切换器.app"
AGENT="$HOME/Library/LaunchAgents/local.claude-update.plist"
BACKUP=""
admin() { if [ -n "$ADMIN" ]; then sudo "$@"; else "$@"; fi; }
service_state() {
    local output
    if output=$(launchctl print "$1" 2>&1); then return 0; fi
    case "$output" in *'Bad request'*|*'Could not find service'*|*'not found'*|*'No such process'*) return 1;; esac
    echo "无法确认服务状态 $1：$output" >&2; return 2
}
stop_one() {
    local label="$1" kind="$2" rc=0
    service_state "$label" || rc=$?
    [ "$rc" -ne 2 ] || return 1
    if [ "$rc" -eq 0 ]; then
        if [ "$kind" = system ]; then admin launchctl bootout "$label"; else launchctl bootout "$label"; fi
        rc=0; service_state "$label" || rc=$?
        [ "$rc" -eq 1 ] || { echo "无法确认已停止 $label" >&2; return 1; }
    fi
}
cleanup_old() {
    local f name
    echo '正在停止旧服务（如需要，将提示输入 Mac 管理员密码）…'
    # 无论 plist 是否存在，都检查已加载服务。
    stop_one system/local.claude-bodyguard system
    stop_one system/local.tz-watchdog system
    stop_one system/local.claude-update system
    stop_one "gui/$(id -u)/local.claude-update" user
    mkdir -p "$HOME/.claude-switcher-backups"
    chmod 700 "$HOME/.claude-switcher-backups"
    BACKUP=$(mktemp -d "$HOME/.claude-switcher-backups/old.XXXXXX")
    chmod 700 "$BACKUP"
    mkdir -p "$BACKUP/user" "$BACKUP/system"
    echo "旧文件备份目录：$BACKUP"
    # 移动而非删除，即使中途失败也能从备份找回。
    for f in "$BASE" "$BIN" "$USER_APP" "$AGENT"; do
        if [ -e "$f" ] || [ -L "$f" ]; then mv "$f" "$BACKUP/user/"; fi
    done
    for name in local.claude-bodyguard local.tz-watchdog local.claude-update; do
        f="$ROOT_PLISTS/$name.plist"
        if [ -e "$f" ] || [ -L "$f" ]; then admin mv "$f" "$BACKUP/system/"; fi
    done
    if [ -e "$ROOT_APP" ] || [ -L "$ROOT_APP" ]; then admin mv "$ROOT_APP" "$BACKUP/system/"; fi
    echo '旧版入口与启动配置已移走；系统中旧服务脚本可能仍留存，但不会自动启动。'
}
