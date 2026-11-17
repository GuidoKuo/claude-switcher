#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
. ./manage.sh
echo '卸载将停止切换器服务，并把切换器文件移入用户目录的备份。'
echo '不会删除 /Applications/Claude.app 或当前 Claude 登录资料，也不更改系统网络设置。'
echo '备份可能包含账号登录资料；需要彻底删除时请自行检查备份后删除。'
read -r -p '输入 YES 确认卸载，其余输入取消：' ans
[ "$ans" = YES ] || { echo '已取消，未修改。'; exit 0; }
cleanup_old
echo "卸载完成；旧文件备份在 $BACKUP"
read -r -p '按回车退出。' _ || true
