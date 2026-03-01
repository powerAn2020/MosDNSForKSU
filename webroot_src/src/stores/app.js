import { defineStore } from 'pinia'
import { ref } from 'vue'
import { execApi } from '@/api/kernelsu'

export const useAppStore = defineStore('app', () => {
    const isRunning = ref(false)
    const pid = ref(0)
    const uptime = ref(0)
    const version = ref('loading...')
    const isLoading = ref(false)

    // Settings 数据
    const settings = ref({})

    // 刷新全局状态
    const fetchStatus = async () => {
        try {
            const res = await execApi('status')
            if (res.code === 0 && res.data) {
                isRunning.value = res.data.running
                pid.value = res.data.pid
                uptime.value = res.data.uptime
                version.value = res.data.version
            }
        } catch (e) {
            console.error('Failed to fetch status', e)
        }
    }

    // 获取应用设置
    const fetchSettings = async () => {
        try {
            const res = await execApi('get_settings')
            if (res.code === 0 && res.data) {
                settings.value = res.data
            }
        } catch (e) {
            console.error('Failed to fetch settings', e)
        }
    }

    // 启停控制
    const toggleService = async () => {
        isLoading.value = true
        try {
            if (isRunning.value) {
                await execApi('stop')
            } else {
                await execApi('start')
            }
            await fetchStatus()
        } finally {
            isLoading.value = false
        }
    }

    return {
        isRunning,
        pid,
        uptime,
        version,
        isLoading,
        settings,
        fetchStatus,
        fetchSettings,
        toggleService
    }
})
