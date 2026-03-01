#!/system/bin/sh
# MosdnsForKSU - 安装脚本

SKIPUNZIP=1

# 数据目录（独立于模块目录）
DATADIR="/data/adb/mosdns"

# ============================================================
# 架构检测
# ============================================================

ARCH=$(getprop ro.product.cpu.abi)
# if [ "$ARCH" != "arm64-v8a" ]; then
#     ui_print "! 不支持的架构: $ARCH"
#     ui_print "! 本模块仅支持 arm64 设备"
#     abort "安装中止"
# fi

ui_print "- 设备架构: $ARCH ✓"

# ============================================================
# 解压文件
# ============================================================

ui_print "- 解压模块文件..."
unzip -o "$ZIPFILE" -x 'META-INF/*' -d "$MODPATH" >&2

# ============================================================
# 创建数据目录
# ============================================================

ui_print "- 初始化数据目录: $DATADIR"
mkdir -p "${DATADIR}/conf/rule"
mkdir -p "${DATADIR}/dat"
mkdir -p "${DATADIR}/run"

# 首次安装：复制默认配置到数据目录
if [ ! -f "${DATADIR}/conf/config.yaml" ]; then
    ui_print "- 写入默认配置..."
    cp -r "${MODPATH}/conf/"* "${DATADIR}/conf/"
else
    ui_print "- 检测到已有配置，保留不覆盖"
fi

# 确保规则文件存在
[ ! -f "${DATADIR}/conf/rule/whitelist.txt" ] && cp "${MODPATH}/conf/rule/whitelist.txt" "${DATADIR}/conf/rule/"
[ ! -f "${DATADIR}/conf/rule/greylist.txt" ] && cp "${MODPATH}/conf/rule/greylist.txt" "${DATADIR}/conf/rule/"

# ============================================================
# 设置权限
# ============================================================

ui_print "- 设置文件权限..."
set_perm_recursive "$MODPATH" 0 0 0755 0644
set_perm_recursive "$MODPATH/bin" 0 0 0755 0755
set_perm_recursive "$MODPATH/scripts" 0 0 0755 0755
set_perm "$MODPATH/bin/mosdns" 0 0 0755
set_perm "$MODPATH/service.sh" 0 0 0755

for script in "$MODPATH/scripts/"*.sh; do
    [ -f "$script" ] && set_perm "$script" 0 0 0755
done

# 数据目录权限
set_perm_recursive "$DATADIR" 0 0 0755 0644

# ============================================================
# 默认设置
# ============================================================

if [ ! -f "${DATADIR}/settings.json" ]; then
    cat > "${DATADIR}/settings.json" <<'SETTINGS'
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
SETTINGS
fi

# ============================================================
# GeoData 检查
# ============================================================

ui_print "- 检查 GeoData 数据文件..."
missing=0
for f in geoip_cn.txt geoip_private.txt geosite_cn.txt geosite_gfw.txt "geosite_geolocation-!cn.txt" geosite_category-ads-all.txt; do
    if [ ! -f "${DATADIR}/dat/$f" ]; then
        ui_print "  ! 缺少: $f"
        missing=$((missing + 1))
    fi
done

[ $missing -gt 0 ] && ui_print "- 部分 GeoData 缺失，可在 WebUI 中更新"

# ============================================================
# 完成
# ============================================================

ui_print "- mosdns 版本: $($MODPATH/bin/mosdns version 2>/dev/null | head -1 || echo 'unknown')"
ui_print "- 模块目录: $MODPATH"
ui_print "- 数据目录: $DATADIR"
ui_print "- 安装完成！请在 KernelSU 管理器中打开 WebUI 配置"
