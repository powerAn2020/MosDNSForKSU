#!/system/bin/sh
# MosdnsForKSU - 开机服务脚本（late_start service）

# 动态获取模块目录（KernelSU 标准变量 MODDIR 可用，否则从脚本位置推导）
MODDIR="${0%/*}"
DATADIR="/data/adb/mosdns"
SCRIPTS_DIR="${MODDIR}/scripts"
SETTINGS_FILE="${DATADIR}/settings.json"

mkdir -p "${DATADIR}/run"

# ============================================================
# 工具函数
# ============================================================

get_setting() {
    local key="$1"
    local default="$2"
    if [ -f "$SETTINGS_FILE" ]; then
        val=$(grep -o "\"$key\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" "$SETTINGS_FILE" 2>/dev/null | head -1 | sed 's/.*:[[:space:]]*"\(.*\)"/\1/')
        if [ -n "$val" ]; then echo "$val"; return; fi
        val=$(grep -o "\"$key\"[[:space:]]*:[[:space:]]*[^,}]*" "$SETTINGS_FILE" 2>/dev/null | head -1 | sed 's/.*:[[:space:]]*//' | tr -d ' ')
        if [ -n "$val" ]; then echo "$val"; return; fi
    fi
    echo "$default"
}

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] MosdnsForKSU: $1" >> "${DATADIR}/run/service.log"
}

# ============================================================
# 启动逻辑
# ============================================================

# 检查开机自启
auto_start=$(get_setting "auto_start" "true")
if [ "$auto_start" != "true" ]; then
    log "auto_start disabled, skipping"
    exit 0
fi

log "waiting for network..."

# 等待网络（最多 60 秒）
for i in $(seq 1 60); do
    ping -c 1 -W 1 223.5.5.5 > /dev/null 2>&1 && break
    sleep 1
done

log "starting mosdns..."

# 调用 api.sh start
result=$(sh "${SCRIPTS_DIR}/api.sh" start 2>&1)
log "start result: $result"
