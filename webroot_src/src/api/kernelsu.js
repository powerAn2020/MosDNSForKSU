import { exec } from 'kernelsu'

// 判断是否真机环境 (尝试执行一个简单的 KernelSU API)
let isKsuEnv = false
try {
    const testCmd = exec('echo test')
    if (testCmd && testCmd.stdout === 'test\n') {
        isKsuEnv = true
    }
} catch (e) {
    console.log('Not running in KernelSU environment, using Mock API.')
}

const MODDIR = '/data/adb/modules/MosdnsForKSU'
const API_SCRIPT = `sh ${MODDIR}/scripts/api.sh`

// 执行命令封装 (自动处理 Mock 和真实调用)
export const execApi = async (cmd, args = '') => {
    const fullCmd = `${API_SCRIPT} ${cmd} ${args}`

    if (isKsuEnv) {
        return new Promise((resolve, reject) => {
            try {
                const result = exec(fullCmd)
                // 尝试解析 JSON
                if (result.errno !== 0 && result.errno !== undefined) {
                    console.error('[API Error]', result)
                    reject(new Error(`Exit code: ${result.errno}`))
                    return
                }
                try {
                    const json = JSON.parse(result.stdout)
                    resolve(json)
                } catch (e) {
                    resolve({ code: -1, msg: 'Invalid JSON response', raw: result.stdout })
                }
            } catch (err) {
                reject(err)
            }
        })
    } else {
        // ---- Mock 环境模拟延迟和返回值 ----
        console.log(`[Mock API] Executing: ${fullCmd}`)
        return new Promise((resolve) => {
            setTimeout(() => {
                resolve(getMockResponse(cmd))
            }, 500) // 模拟 500ms 延迟
        })
    }
}

// ==========================================
// Mock 数据生成
// ==========================================
let mockState = {
    running: true,
    pid: 12345,
    uptime: 3600,
    version: 'mosdns 5.x.x',
    listen: ':5335',
    dns_redirect: false
}

function getMockResponse(cmd) {
    switch (cmd) {
        case 'status':
            return { code: 0, data: { ...mockState } }

        case 'stop':
            mockState.running = false
            mockState.pid = 0
            return { code: 0, msg: 'mosdns stopped' }

        case 'start':
            mockState.running = true
            mockState.pid = 12346
            mockState.uptime = 0
            return { code: 0, msg: 'mosdns started', pid: 12346 }

        case 'get_settings':
            return {
                code: 0,
                data: {
                    auto_start: true,
                    dns_redirect: false,
                    listen_port: '5335',
                    log_level: 'warn',
                    api_listen: '127.0.0.1:8338',
                    proxy_port: '7874',
                    ad_block: true,
                    ipv4_prefer: false,
                    fallback_policy: 'remote',
                    cache_lan_size: 8192,
                    cache_wan_size: 131072,
                    lazy_cache_ttl: 86400,
                    auto_update_geodata: false
                }
            }

        case 'get_metrics':
            // 模拟简单的 Prometheus 输出
            const metricsText = `
# HELP mosdns_query_total Total queries
# TYPE mosdns_query_total counter
mosdns_query_total{type="udp"} 12503
mosdns_query_total{type="tcp"} 432
# HELP plugin_query_total Total queries matched
# TYPE plugin_query_total counter
plugin_query_total{plugin="dns_cn"} 8432
plugin_query_total{plugin="dns_nocn"} 4021
plugin_query_total{plugin="cache_lan"} 211
plugin_query_total{plugin="reject_ad"} 132
      `.trim()
            return { code: 0, data: metricsText }

        case 'get_log':
            return {
                code: 0,
                data: "2023-10-27T10:00:00Z INFO mosdns started\n2023-10-27T10:01:00Z WARN something happened\n"
            }

        default:
            return { code: 0, msg: 'mock OK' }
    }
}
