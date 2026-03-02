import { exec, spawn, moduleInfo } from 'kernelsu'

// ==========================================
// KernelSU API 封装
// ==========================================

const DEFAULT_MODDIR = '/data/adb/modules/MosdnsForKSU'

// 调试模式：从 localStorage 读取，默认关闭
let _debug = localStorage.getItem('mosdns-debug') === 'true'

export function setDebug(enabled) {
    _debug = enabled
    localStorage.setItem('mosdns-debug', String(enabled))
    if (enabled) console.log('[KSU] 🐛 Debug mode enabled')
}

export function getDebug() {
    return _debug
}

function log(...args) {
    if (_debug) console.log('[KSU]', ...args)
}

function isKsuEnvironment() {
    // @ts-ignore
    return typeof ksu !== 'undefined'
}

async function getModuleDir() {
    if (!isKsuEnvironment()) return DEFAULT_MODDIR
    try {
        let info = await moduleInfo()
        if (typeof info === 'string') {
            try { info = JSON.parse(info) } catch (e) { /* ignore */ }
        }
        log('moduleInfo:', info)
        return (info && info.moduleDir) ? info.moduleDir : DEFAULT_MODDIR
    } catch (e) {
        console.warn('[KSU] moduleInfo() failed, using default:', DEFAULT_MODDIR)
        return DEFAULT_MODDIR
    }
}

async function ksuExec(cmd) {
    if (isKsuEnvironment()) {
        log('>>> exec:', cmd)
        const startTime = performance.now()
        const { errno, stdout, stderr } = await exec(cmd)
        const duration = Math.round(performance.now() - startTime)
        if (errno === 0) {
            log(`<<< [${duration}ms] stdout:`, stdout?.substring(0, 500))
            return stdout
        } else {
            log(`<<< [${duration}ms] ❌ errno=${errno}, stderr:`, stderr)
            throw new Error(stderr || `Command failed with errno ${errno}`)
        }
    } else {
        if (import.meta.env.DEV) {
            log('>>> (mock) exec:', cmd)
            return ''
        }
        return ''
    }
}

// ==========================================
// API 层
// ==========================================

let _moddir = null

async function getApiScript() {
    if (!_moddir) {
        _moddir = await getModuleDir()
        log('MODDIR resolved:', _moddir)
    }
    return `${_moddir}/scripts/api.sh`
}

export const execApi = async (cmd, args = '') => {
    const env = isKsuEnvironment() ? 'KSU' : 'Mock'
    log(`⚡ execApi(${cmd}, ${args}) [${env}]`)

    if (isKsuEnvironment()) {
        const script = await getApiScript()
        const fullCmd = `${script} ${cmd} ${args}`
        try {
            const stdout = await ksuExec(fullCmd)
            try {
                const parsed = JSON.parse(stdout)
                log(`✅ ${cmd} response:`, parsed)
                return parsed
            } catch (e) {
                log(`⚠️ ${cmd} non-JSON response:`, stdout?.substring(0, 200))
                return { code: -1, msg: 'Invalid JSON', raw: stdout }
            }
        } catch (err) {
            log(`❌ ${cmd} error:`, err.message)
            return { code: -1, msg: err.message }
        }
    } else if (import.meta.env.DEV) {
        return new Promise((resolve) => {
            setTimeout(() => {
                const mock = getMockResponse(cmd)
                log(`✅ ${cmd} (mock):`, mock)
                resolve(mock)
            }, 300)
        })
    } else {
        return { code: -1, msg: 'Not in KSU environment' }
    }
}

/**
 * 非阻塞 API 调用 — 使用 spawn 避免 UI 卡死
 * 适合长时间运行的命令
 */
export const spawnApi = (cmd, args = '', { timeout = 60000, onStdout } = {}) => {
    const env = isKsuEnvironment() ? 'KSU' : 'Mock'
    log(`🚀 spawnApi(${cmd}, ${args}) [${env}]`)

    if (isKsuEnvironment()) {
        return new Promise(async (resolve, reject) => {
            const script = await getApiScript()
            const fullCmd = `${script} ${cmd} ${args}`
            log('>>> spawn:', fullCmd)

            let stdout = ''
            let stderr = ''
            let settled = false
            const startTime = performance.now()

            let timer = null
            if (timeout > 0) {
                timer = setTimeout(() => {
                    if (!settled) {
                        settled = true
                        log(`⏱️ spawn timeout after ${timeout}ms`)
                        reject(new Error('timeout'))
                    }
                }, timeout)
            }

            try {
                const argsArray = [cmd]
                if (args && typeof args === 'string') {
                    argsArray.push(...args.split(' ').filter(a => a))
                }

                log('>>> spawn:', script, argsArray)
                const child = spawn(script, argsArray)

                child.stdout.on('data', (data) => {
                    if (settled) return
                    stdout += data
                    log('📤 stdout chunk:', data.substring(0, 200))
                    if (onStdout) onStdout(data)
                })

                child.stderr.on('data', (data) => {
                    if (settled) return
                    stderr += data
                    log('📤 stderr chunk:', data.substring(0, 200))
                })

                child.on('exit', (code) => {
                    if (settled) return
                    settled = true
                    if (timer) clearTimeout(timer)
                    const duration = Math.round(performance.now() - startTime)
                    log(`<<< spawn exit [${duration}ms] code=${code}`)

                    if (code === 0) {
                        try {
                            const parsed = JSON.parse(stdout)
                            log(`✅ ${cmd} (spawn) response:`, parsed)
                            resolve(parsed)
                        } catch (e) {
                            log(`⚠️ ${cmd} (spawn) non-JSON:`, stdout.substring(0, 200))
                            resolve({ code: 0, msg: stdout.trim() || 'OK', raw: stdout })
                        }
                    } else {
                        log(`❌ ${cmd} (spawn) failed:`, stderr)
                        resolve({ code: code, msg: stderr.trim() || `exit code ${code}` })
                    }
                })

                child.on('error', (err) => {
                    if (settled) return
                    settled = true
                    if (timer) clearTimeout(timer)
                    log(`❌ ${cmd} (spawn) error:`, err)
                    reject(err)
                })
            } catch (err) {
                if (!settled) {
                    settled = true
                    clearTimeout(timer)
                    reject(err)
                }
            }
        })
    } else if (import.meta.env.DEV) {
        // Mock 环境
        return new Promise((resolve) => {
            setTimeout(() => {
                const mock = getMockResponse(cmd)
                log(`✅ ${cmd} (spawn mock):`, mock)
                resolve(mock)
            }, 2000) // 模拟稍长的延迟
        })
    } else {
        return Promise.resolve({ code: -1, msg: 'Not in KSU environment' })
    }
}

// ==========================================
// Mock 数据
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
            return {
                code: 0,
                data: `# HELP mosdns_query_total Total queries
# TYPE mosdns_query_total counter
mosdns_query_total{type="udp"} 12503
mosdns_query_total{type="tcp"} 432
# HELP plugin_query_total Total queries matched
# TYPE plugin_query_total counter
plugin_query_total{plugin="dns_cn"} 8432
plugin_query_total{plugin="dns_nocn"} 4021
plugin_query_total{plugin="cache_lan"} 211
plugin_query_total{plugin="reject_ad"} 132`
            }

        case 'get_log':
            return {
                code: 0,
                data: '2023-10-27T10:00:00Z INFO mosdns started\n2023-10-27T10:01:00Z WARN something happened\n'
            }

        case 'get_config':
            return {
                code: 0,
                data: {
                    whitelist: '# whitelist example\\ndomain: baidu.com',
                    greylist: '# greylist example\\ndomain: google.com',
                    config: '# config.yaml content',
                    dns: '# dns.yaml content',
                    dat_exec: '# dat_exec.yaml content'
                }
            }

        default:
            return { code: 0, msg: 'mock OK' }
    }
}
