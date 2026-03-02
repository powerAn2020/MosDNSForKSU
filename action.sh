#!/system/bin/sh
# MosdnsForKSU - action.sh
# 点击 KernelSU 管理器中的模块条目时执行
# 功能：快速启停 mosdns 服务（Toggle）

MODDIR="${0%/*}"
DATADIR="/data/adb/mosdns"
PID_FILE="${DATADIR}/run/mosdns.pid"
SCRIPTS_DIR="${MODDIR}/scripts"

is_running() {
    [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null
}

if is_running; then
    # 当前运行中 → 停止
    result=$(sh "${SCRIPTS_DIR}/api.sh" stop 2>&1)
    echo "⏹ Mosdns 已停止"
else
    # 当前已停止 → 启动
    result=$(sh "${SCRIPTS_DIR}/api.sh" start 2>&1)
    echo "▶ Mosdns 已启动"
fi
