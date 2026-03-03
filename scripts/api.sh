#!/system/bin/sh
# MosdnsForKSU - WebUI 后端 API 脚本
# 用法: api.sh <command> [args...]
# 所有输出为 JSON 格式

# ============================================================
# 路径定义（不硬编码模块目录）
# ============================================================

# 模块目录：从脚本自身位置推导
MODDIR="$(dirname "$(dirname "$(readlink -f "$0")")")"
# 数据目录：独立于模块目录，持久化存储
DATADIR="/data/adb/mosdns"

MOSDNS_BIN="${MODDIR}/bin/mosdns"
CONF_DIR="${DATADIR}/conf"
DAT_DIR="${DATADIR}/dat"
RUN_DIR="${DATADIR}/run"
RULE_DIR="${DATADIR}/conf/rule"
CONFIG_FILE="${CONF_DIR}/config.yaml"
PID_FILE="${RUN_DIR}/mosdns.pid"
LOG_FILE="${RUN_DIR}/mosdns.log"
SETTINGS_FILE="${DATADIR}/settings.json"

# 确保目录存在
mkdir -p "$RUN_DIR" "$CONF_DIR" "$DAT_DIR" "$RULE_DIR"

# ============================================================
# 工具函数
# ============================================================

json_ok() {
    echo "{\"code\":0,\"msg\":\"$1\"}"
}

json_error() {
    echo "{\"code\":$1,\"msg\":\"$2\"}"
}

json_data() {
    echo "{\"code\":0,\"data\":$1}"
}

get_setting() {
    local key="$1"
    local default="$2"
    if [ -f "$SETTINGS_FILE" ]; then
        val=$(grep -o "\"$key\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" "$SETTINGS_FILE" 2>/dev/null | head -1 | sed 's/.*:[[:space:]]*"\(.*\)"/\1/')
        if [ -n "$val" ]; then
            echo "$val"
            return
        fi
        val=$(grep -o "\"$key\"[[:space:]]*:[[:space:]]*[^,}]*" "$SETTINGS_FILE" 2>/dev/null | head -1 | sed 's/.*:[[:space:]]*//' | tr -d ' ')
        if [ -n "$val" ]; then
            echo "$val"
            return
        fi
    fi
    echo "$default"
}

sync_settings_to_config() {
    # 从 settings.json 同步到 YAML 配置
    local listen_port=$(get_setting "listen_port" "5335")
    local proxy_port=$(get_setting "proxy_port" "7874")
    
    # 同步监听端口到 config.yaml
    if [ -f "$CONFIG_FILE" ]; then
        sed -i "s/listen: \":*.*\"/listen: \":${listen_port}\"/" "$CONFIG_FILE"
        sed -i "s/listen: :[0-9]*/listen: :${listen_port}/" "$CONFIG_FILE"
    fi
    
    # 同步代理端口到 dns.yaml
    local dns_yaml="${CONF_DIR}/dns.yaml"
    if [ -f "$dns_yaml" ]; then
        # 匹配 127.0.0.1:端口 的格式进行替换
        sed -i "s/127\.0\.0\.1:[0-9]*/127.0.0.1:${proxy_port}/g" "$dns_yaml"
    fi
}

# ============================================================
# 服务管理（原 start.sh / stop.sh / status.sh）
# ============================================================

cmd_start() {
    # 检查是否已在运行
    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE")
        if kill -0 "$PID" 2>/dev/null; then
            echo '{"code":1,"msg":"mosdns is already running","pid":'$PID'}'
            return
        fi
        rm -f "$PID_FILE"
    fi

    # 检查二进制
    if [ ! -x "$MOSDNS_BIN" ]; then
        json_error 2 "mosdns binary not found or not executable"
        return
    fi

    # 检查配置
    if [ ! -f "$CONFIG_FILE" ]; then
        json_error 3 "config file not found: $CONFIG_FILE"
        return
    fi

    # 日志轮转（保留最后 1000 行）
    if [ -f "$LOG_FILE" ]; then
        tail -n 1000 "$LOG_FILE" > "${LOG_FILE}.tmp"
        mv "${LOG_FILE}.tmp" "$LOG_FILE"
    fi

    # 同步设置到配置
    sync_settings_to_config

    # 启动 mosdns
    nohup "$MOSDNS_BIN" start -c "$CONFIG_FILE" -d "$CONF_DIR" > /dev/null 2>&1 &
    MOSDNS_PID=$!
    sleep 1

    if kill -0 "$MOSDNS_PID" 2>/dev/null; then
        echo "$MOSDNS_PID" > "$PID_FILE"

        # 检查 DNS 重定向配置
        redirect=$(get_setting "dns_redirect" "false")
        if [ "$redirect" = "true" ]; then
            cmd_redirect_enable > /dev/null 2>&1
        fi

        echo '{"code":0,"msg":"mosdns started","pid":'$MOSDNS_PID'}'
    else
        json_error 4 "mosdns failed to start, check log"
    fi
}

cmd_stop() {
    # 检查 DNS 重定向配置
    redirect=$(get_setting "dns_redirect" "false")
    if [ "$redirect" = "true" ]; then
        # 清理 iptables
        cmd_redirect_disable > /dev/null 2>&1
    fi
    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE")
        if kill -0 "$PID" 2>/dev/null; then
            kill "$PID"
            for i in $(seq 1 10); do
                kill -0 "$PID" 2>/dev/null || break
                sleep 0.5
            done
            # 强制杀死
            kill -0 "$PID" 2>/dev/null && kill -9 "$PID"
            rm -f "$PID_FILE"
            json_ok "mosdns stopped"
        else
            rm -f "$PID_FILE"
            json_ok "mosdns was not running, cleaned pid file"
        fi
    else
        PIDS=$(pidof mosdns)
        if [ -n "$PIDS" ]; then
            kill $PIDS 2>/dev/null
            sleep 1
            kill -9 $PIDS 2>/dev/null
            json_ok "mosdns stopped (found by process name)"
        else
            json_ok "mosdns is not running"
        fi
    fi
}

cmd_status() {
    local running=false
    local pid=0
    local uptime_sec=0

    if [ -f "$PID_FILE" ]; then
        pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            running=true
            if [ -d "/proc/$pid" ]; then
                start_time=$(stat -c %Y "/proc/$pid" 2>/dev/null || echo 0)
                now=$(date +%s)
                [ "$start_time" -gt 0 ] && uptime_sec=$((now - start_time))
            fi
        else
            pid=0
            rm -f "$PID_FILE"
        fi
    fi

    # 版本
    local version="unknown"
    [ -x "$MOSDNS_BIN" ] && version=$("$MOSDNS_BIN" version 2>/dev/null | head -1 || echo "unknown")

    # 监听端口
    local listen_port
    listen_port=$(grep -A1 'udp_server' "$CONFIG_FILE" 2>/dev/null | grep 'listen:' | head -1 | sed 's/.*listen:[[:space:]]*//' | tr -d '"' || echo ":5335")

    # DNS 重定向状态
    local redirect
    redirect=$(get_setting "dns_redirect" "false")

    cat <<EOF
{
  "code": 0,
  "data": {
    "running": $running,
    "pid": $pid,
    "uptime": $uptime_sec,
    "version": "$version",
    "listen": "$listen_port",
    "dns_redirect": $redirect,
    "moddir": "$MODDIR",
    "datadir": "$DATADIR"
  }
}
EOF
}

cmd_reload() {
    if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
        cmd_stop > /dev/null 2>&1
        sleep 1
        cmd_start
    else
        json_error 1 "mosdns is not running"
    fi
}

# ============================================================
# 配置管理
# ============================================================

cmd_get_config() {
    local config_content=""
    local dns_content=""
    local dat_exec_content=""
    local whitelist_content=""
    local greylist_content=""

    [ -f "${CONF_DIR}/config.yaml" ] && config_content=$(cat "${CONF_DIR}/config.yaml" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g' | awk '{printf "%s\\n", $0}')
    [ -f "${CONF_DIR}/dns.yaml" ] && dns_content=$(cat "${CONF_DIR}/dns.yaml" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g' | awk '{printf "%s\\n", $0}')
    [ -f "${CONF_DIR}/dat_exec.yaml" ] && dat_exec_content=$(cat "${CONF_DIR}/dat_exec.yaml" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g' | awk '{printf "%s\\n", $0}')
    [ -f "${RULE_DIR}/whitelist.txt" ] && whitelist_content=$(cat "${RULE_DIR}/whitelist.txt" | sed 's/\\/\\\\/g; s/"/\\"/g' | awk '{printf "%s\\n", $0}')
    [ -f "${RULE_DIR}/greylist.txt" ] && greylist_content=$(cat "${RULE_DIR}/greylist.txt" | sed 's/\\/\\\\/g; s/"/\\"/g' | awk '{printf "%s\\n", $0}')

    cat <<EOF
{
  "code": 0,
  "data": {
    "config": "$config_content",
    "dns": "$dns_content",
    "dat_exec": "$dat_exec_content",
    "whitelist": "$whitelist_content",
    "greylist": "$greylist_content"
  }
}
EOF
}

cmd_save_config() {
    local config_type="$1"
    local content="$2"

    case "$config_type" in
        config)    echo "$content" > "${CONF_DIR}/config.yaml" ;;
        dns)       echo "$content" > "${CONF_DIR}/dns.yaml" ;;
        dat_exec)  echo "$content" > "${CONF_DIR}/dat_exec.yaml" ;;
        whitelist) echo "$content" > "${RULE_DIR}/whitelist.txt" ;;
        greylist)  echo "$content" > "${RULE_DIR}/greylist.txt" ;;
        *)         json_error 1 "unknown config type: $config_type"; return ;;
    esac
    json_ok "config saved: $config_type"
}

cmd_apply_config() {
    # 验证配置语法
    if [ -x "$MOSDNS_BIN" ]; then
        result=$("$MOSDNS_BIN" start -c "$CONFIG_FILE" -d "$CONF_DIR" --dry-run 2>&1)
        if [ $? -ne 0 ]; then
            result=$(echo "$result" | sed 's/"/\\"/g' | head -5 | tr '\n' ' ')
            json_error 2 "config validation failed: $result"
            return
        fi
    fi

    # 重启服务
    if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
        cmd_reload
    else
        json_ok "config saved, service not running"
    fi
}

# ============================================================
# 设置管理
# ============================================================

cmd_get_settings() {
    if [ -f "$SETTINGS_FILE" ]; then
        content=$(cat "$SETTINGS_FILE")
        echo "{\"code\":0,\"data\":$content}"
    else
        cat <<EOF
{
  "code": 0,
  "data": {
    "auto_start": true,
    "dns_redirect": false,
    "listen_port": "5335",
    "log_level": "warn",
    "api_listen": "127.0.0.1:8338",
    "proxy_port": "7874",
    "ad_block": true,
    "ipv4_prefer": false,
    "fallback_policy": "remote",
    "cache_lan_size": 8192,
    "cache_wan_size": 131072,
    "lazy_cache_ttl": 86400,
    "auto_update_geodata": false
  }
}
EOF
    fi
}

cmd_save_settings() {
    echo "$1" > "$SETTINGS_FILE"
    json_ok "settings saved"
}

# ============================================================
# GeoData 更新
# ============================================================

cmd_update_geodata() {
    mkdir -p "$DAT_DIR"

    BASE_URL="https://raw.githubusercontent.com/Loyalsoldier/v2ray-rules-dat/release"
    GEOIP_CN_URL="https://raw.githubusercontent.com/Hackl0us/GeoIP2-CN/release/CN-ip-cidr.txt"

    local success=0
    local failed=0

    for item in \
        "geoip_cn.txt|$GEOIP_CN_URL" \
        "geosite_cn.txt|${BASE_URL}/direct-list.txt" \
        "geosite_gfw.txt|${BASE_URL}/gfw.txt" \
        "geosite_geolocation-!cn.txt|${BASE_URL}/proxy-list.txt" \
        "geosite_category-ads-all.txt|${BASE_URL}/reject-list.txt"; do

        filename=$(echo "$item" | cut -d'|' -f1)
        url=$(echo "$item" | cut -d'|' -f2)

        if wget -q -O "${DAT_DIR}/${filename}.tmp" "$url" 2>/dev/null || \
           curl -sL -o "${DAT_DIR}/${filename}.tmp" "$url" 2>/dev/null; then
            mv "${DAT_DIR}/${filename}.tmp" "${DAT_DIR}/${filename}"
            success=$((success + 1))
        else
            rm -f "${DAT_DIR}/${filename}.tmp"
            failed=$((failed + 1))
        fi
    done

    # 生成私网 IP 列表
    cat > "${DAT_DIR}/geoip_private.txt" <<'PRIVATE'
10.0.0.0/8
172.16.0.0/12
192.168.0.0/16
127.0.0.0/8
169.254.0.0/16
224.0.0.0/4
240.0.0.0/4
fd00::/8
fe80::/10
PRIVATE
    success=$((success + 1))

    if [ $failed -eq 0 ]; then
        json_ok "geodata updated: $success files"
    else
        json_error 1 "geodata update partial: $success ok, $failed failed"
    fi
}

# ============================================================
# 配置重置
# ============================================================

cmd_reset_config() {
    local backup_dir="${DATADIR}/conf_backup_$(date +%Y%m%d%H%M%S)"
    cp -r "$CONF_DIR" "$backup_dir"

    if [ -d "${MODDIR}/conf" ]; then
        cp -rf "${MODDIR}/conf/"* "$CONF_DIR/"
        json_ok "config reset to default, backup: $backup_dir"
    else
        json_error 1 "default config not found in module"
    fi
}

# ============================================================
# 日志
# ============================================================

cmd_get_log() {
    local lines="${1:-100}"
    if [ -f "$LOG_FILE" ]; then
        echo -n '{"code":0,"data":"'
        tail -n "$lines" "$LOG_FILE" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g' | awk '{printf "%s\\n", $0}' | tr -d '\n'
        echo '"}'
    else
        echo '{"code":0,"data":""}'
    fi
}

# ============================================================
# DNS 测试
# ============================================================

cmd_dns_test() {
    local server="${1:-8.8.8.8}"
    local domain="${2:-google.com}"
    local start_ms=$(date +%s%N | cut -b1-13)
    nslookup "$domain" "$server" > /dev/null 2>&1
    local end_ms=$(date +%s%N | cut -b1-13)
    local latency=$((end_ms - start_ms))
    echo "{\"code\":0,\"data\":{\"server\":\"$server\",\"domain\":\"$domain\",\"latency\":$latency}}"
}

# ============================================================
# Metrics
# ============================================================

cmd_get_metrics() {
    local api_addr
    api_addr=$(get_setting "api_listen" "127.0.0.1:8338")

    local metrics
    metrics=$(wget -q -O - "http://${api_addr}/metrics" 2>/dev/null || \
              curl -s "http://${api_addr}/metrics" 2>/dev/null || echo "")

    if [ -n "$metrics" ]; then
        metrics=$(echo "$metrics" | sed 's/\\/\\\\/g; s/"/\\"/g' | awk '{printf "%s\\n", $0}')
        echo "{\"code\":0,\"data\":\"$metrics\"}"
    else
        json_error 1 "failed to fetch metrics"
    fi
}

# ============================================================
# DNS 重定向（iptables）
# ============================================================

cmd_redirect_enable() {
    local port
    port=$(get_setting "listen_port" "5335")

    # 先清理旧规则
    cmd_redirect_disable > /dev/null 2>&1

    iptables -t nat -A OUTPUT -p tcp --dport 53 -j DNAT --to-destination "127.0.0.1:${port}" 2>/dev/null
    iptables -t nat -A OUTPUT -p udp --dport 53 -j DNAT --to-destination "127.0.0.1:${port}" 2>/dev/null

    json_ok "dns redirect enabled to port $port"
}

cmd_redirect_disable() {
    local port
    port=$(get_setting "listen_port" "5335")

    iptables -t nat -D OUTPUT -p tcp --dport 53 -j DNAT --to-destination "127.0.0.1:${port}" 2>/dev/null
    iptables -t nat -D OUTPUT -p udp --dport 53 -j DNAT --to-destination "127.0.0.1:${port}" 2>/dev/null
    iptables -t nat -D PREROUTING -p tcp --dport 53 -j DNAT --to-destination "127.0.0.1:${port}" 2>/dev/null
    iptables -t nat -D PREROUTING -p udp --dport 53 -j DNAT --to-destination "127.0.0.1:${port}" 2>/dev/null

    json_ok "dns redirect disabled"
}

# ============================================================
# 主入口
# ============================================================

CMD="$1"
[ $# -gt 0 ] && shift

case "$CMD" in
    status)           cmd_status ;;
    start)            cmd_start ;;
    stop)             cmd_stop ;;
    reload)           cmd_reload ;;
    get_config)       cmd_get_config ;;
    save_config)      cmd_save_config "$1" "$2" ;;
    apply_config)     cmd_apply_config ;;
    get_settings)     cmd_get_settings ;;
    save_settings)    cmd_save_settings "$1" ;;
    update_geodata)   cmd_update_geodata ;;
    reset_config)     cmd_reset_config ;;
    get_log)          cmd_get_log "$1" ;;
    dns_test)         cmd_dns_test "$1" "$2" ;;
    get_metrics)      cmd_get_metrics ;;
    redirect_enable)  cmd_redirect_enable ;;
    redirect_disable) cmd_redirect_disable ;;
    *)
        cat <<EOF
{
  "code": -1,
  "msg": "unknown command: $CMD",
  "available_commands": [
    "status", "start", "stop", "reload",
    "get_config", "save_config", "apply_config",
    "get_settings", "save_settings",
    "update_geodata", "reset_config",
    "get_log", "dns_test", "get_metrics",
    "redirect_enable", "redirect_disable"
  ]
}
EOF
        ;;
esac
