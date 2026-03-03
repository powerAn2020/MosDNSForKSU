<script setup>
import { onMounted, onUnmounted, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { useAppStore } from '@/stores/app'
import { useThemeStore } from '@/stores/theme'
import { execApi } from '@/api/kernelsu'
import { 
  PlayIcon, 
  StopIcon, 
  ArrowPathIcon,
  ShieldCheckIcon,
  GlobeAltIcon
} from '@heroicons/vue/24/solid'

const { t } = useI18n()
const appStore = useAppStore()
const themeStore = useThemeStore()
let pollTimer = null

const stats = ref({ total: 0, cn: 0, nocn: 0, reject: 0, cache: 0 })

const fetchMetrics = async () => {
  if (!appStore.isRunning) return
  try {
    const res = await execApi('get_metrics')
    if (res.code === 0 && res.data) {
      const lines = res.data.split('\n')
      let total = 0, cn = 0, nocn = 0, reject = 0, cache = 0
      lines.forEach(line => {
        if (line.startsWith('mosdns_query_total')) {
          const match = line.match(/ (\d+)$/)
          if (match) total += parseInt(match[1])
        }
        if (line.startsWith('plugin_query_total')) {
          const val = parseInt(line.match(/ (\d+)$/)?.[1] || 0)
          if (line.includes('plugin="dns_cn"')) cn += val
          if (line.includes('plugin="dns_nocn"')) nocn += val
          if (line.includes('reject')) reject += val
          if (line.includes('cache')) cache += val
        }
      })
      stats.value = { total, cn, nocn, reject, cache }
    }
  } catch (e) {
    console.error('Failed to fetch metrics', e)
  }
}

onMounted(() => {
  appStore.fetchStatus()
  fetchMetrics()
  pollTimer = setInterval(() => {
    appStore.fetchStatus()
    fetchMetrics()
  }, 3000)
})

onUnmounted(() => {
  if (pollTimer) clearInterval(pollTimer)
})

const formatUptime = (seconds) => {
  if (!seconds) return '0s'
  const h = Math.floor(seconds / 3600)
  const m = Math.floor((seconds % 3600) / 60)
  const s = seconds % 60
  return `${h > 0 ? h + 'h ' : ''}${m > 0 ? m + 'm ' : ''}${s}s`
}

const isReloading = ref(false)
const reloadService = async () => {
  isReloading.value = true
  await execApi('reload')
  await appStore.fetchStatus()
  isReloading.value = false
}
</script>

<template>
  <div class="px-4 py-6 max-w-lg mx-auto space-y-6">
    
    <!-- 状态卡片 -->
    <div 
      class="rounded-3xl p-6 relative overflow-hidden transition-all duration-500 border"
      :class="appStore.isRunning 
        ? (themeStore.isDark() 
            ? 'bg-gradient-to-br from-indigo-900/80 to-indigo-950/50 border-indigo-500/30' 
            : 'bg-gradient-to-br from-indigo-50 to-blue-50 border-indigo-200 shadow-lg shadow-indigo-100/50') 
        : 'theme-bg-card theme-border-secondary'"
    >
      <div class="flex items-center justify-between mb-4">
        <div class="flex items-center space-x-3">
          <div class="relative flex h-4 w-4">
            <span v-if="appStore.isRunning" class="animate-ping absolute inline-flex h-full w-full rounded-full bg-emerald-400 opacity-75"></span>
            <span class="relative inline-flex rounded-full h-4 w-4" :class="appStore.isRunning ? 'bg-emerald-500' : 'bg-rose-500'"></span>
          </div>
          <h2 class="text-xl font-bold tracking-tight" :class="appStore.isRunning && !themeStore.isDark() ? 'text-indigo-900' : 'theme-text-heading'">{{ t('dashboard.title') }}</h2>
        </div>
        <div class="text-xs font-medium px-2 py-1 rounded" :class="themeStore.isDark() ? 'bg-black/20 text-zinc-300' : 'bg-indigo-100 text-indigo-700'">
          {{ appStore.version }}
        </div>
      </div>
      
      <div class="space-y-1 mb-8">
        <p class="text-sm flex justify-between" :class="appStore.isRunning && !themeStore.isDark() ? 'text-indigo-600/70' : 'theme-text-secondary'">
          <span>{{ t('dashboard.status') }}</span> 
          <span :class="appStore.isRunning ? (themeStore.isDark() ? 'text-emerald-400' : 'text-emerald-600 font-semibold') : 'text-rose-500 font-medium'">
            {{ appStore.isRunning ? t('dashboard.running') : t('dashboard.stopped') }}
          </span>
        </p>
        <p v-if="appStore.isRunning" class="text-sm flex justify-between" :class="appStore.isRunning && !themeStore.isDark() ? 'text-indigo-600/70' : 'theme-text-secondary'">
          <span>{{ t('dashboard.uptime') }}</span>
          <span class="font-mono" :class="themeStore.isDark() ? 'theme-text' : 'text-indigo-900 font-semibold'">{{ formatUptime(appStore.uptime) }}</span>
        </p>
      </div>

      <div class="flex space-x-3">
        <button 
          @click="appStore.toggleService"
          :disabled="appStore.isLoading"
          class="flex-1 rounded-xl py-3 px-4 font-semibold text-sm flex justify-center items-center space-x-2 transition-all"
          :class="appStore.isRunning 
            ? (themeStore.isDark() ? 'bg-rose-500/10 text-rose-400 hover:bg-rose-500/20' : 'bg-rose-50 text-rose-600 border border-rose-200 hover:bg-rose-100') 
            : 'bg-indigo-600 text-white hover:bg-indigo-500'"
        >
          <StopIcon v-if="appStore.isRunning" class="w-5 h-5" />
          <PlayIcon v-else class="w-5 h-5" />
          <span>{{ appStore.isRunning ? t('dashboard.stop') : t('dashboard.start') }}</span>
        </button>
        
        <button 
          v-if="appStore.isRunning"
          @click="reloadService"
          :disabled="isReloading"
          class="rounded-xl p-3 theme-bg-card border theme-border-input theme-text-secondary hover:theme-text transition-all"
        >
          <ArrowPathIcon class="w-5 h-5" :class="{'animate-spin': isReloading}" />
        </button>
      </div>
    </div>

    <!-- 实时指标 -->
    <div v-if="appStore.isRunning" class="space-y-4">
      <h3 class="text-sm font-semibold theme-text-secondary uppercase tracking-wider px-1">{{ t('dashboard.stats') }}</h3>
      
      <div class="grid grid-cols-2 gap-3">
        <div class="theme-bg-card rounded-2xl p-4 border theme-border">
          <div class="theme-text-muted text-xs font-medium mb-1">{{ t('dashboard.totalQueries') }}</div>
          <div class="text-2xl font-bold theme-text-heading font-mono">{{ stats.total }}</div>
        </div>
        <div class="theme-bg-card rounded-2xl p-4 border theme-border">
          <div class="theme-text-muted text-xs font-medium mb-1">{{ t('dashboard.cacheHit') }}</div>
          <div class="text-2xl font-bold text-emerald-500 font-mono">{{ stats.cache }}</div>
        </div>
      </div>

      <div class="theme-bg-card rounded-2xl p-5 border theme-border space-y-4">
        <div class="flex items-center justify-between">
          <div class="flex items-center space-x-3">
            <div class="bg-blue-500/20 p-2 rounded-lg"><GlobeAltIcon class="w-5 h-5 text-blue-400" /></div>
            <div>
              <div class="text-sm font-medium theme-text">{{ t('dashboard.cnRoute') }}</div>
              <div class="text-xs theme-text-muted">{{ t('dashboard.cnRouteSub') }}</div>
            </div>
          </div>
          <div class="font-mono text-lg theme-text-heading">{{ stats.cn }}</div>
        </div>
        
        <div class="flex items-center justify-between">
          <div class="flex items-center space-x-3">
            <div class="bg-purple-500/20 p-2 rounded-lg"><GlobeAltIcon class="w-5 h-5 text-purple-400" /></div>
            <div>
              <div class="text-sm font-medium theme-text">{{ t('dashboard.nocnRoute') }}</div>
              <div class="text-xs theme-text-muted">{{ t('dashboard.nocnRouteSub') }}</div>
            </div>
          </div>
          <div class="font-mono text-lg theme-text-heading">{{ stats.nocn }}</div>
        </div>

        <div class="flex items-center justify-between">
          <div class="flex items-center space-x-3">
            <div class="bg-rose-500/20 p-2 rounded-lg"><ShieldCheckIcon class="w-5 h-5 text-rose-400" /></div>
            <div>
              <div class="text-sm font-medium theme-text">{{ t('dashboard.reject') }}</div>
              <div class="text-xs theme-text-muted">{{ t('dashboard.rejectSub') }}</div>
            </div>
          </div>
          <div class="font-mono text-lg theme-text-heading">{{ stats.reject }}</div>
        </div>
      </div>
    </div>
  </div>
</template>
