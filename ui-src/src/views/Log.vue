<script setup>
import { ref, onMounted, onUnmounted, nextTick } from 'vue'
import { useI18n } from 'vue-i18n'
import { execApi, spawnApi } from '@/api/kernelsu'
import { 
  ArrowPathIcon,
  TrashIcon,
  PauseIcon,
  PlayIcon
} from '@heroicons/vue/24/outline'

const { t } = useI18n()
const logs = ref([])
const isLoading = ref(false)
const isAutoRefresh = ref(true)
const logContainer = ref(null)
let pollTimer = null

const fetchLogs = async () => {
  if (isLoading.value) return
  isLoading.value = true
  try {
    // 使用 spawnApi 非阻塞调用，设置 30s 超时
    const res = await spawnApi('get_log', '100', { timeout: 30000 })
    
    if (res.code === 0) {
      // spawnApi 在 JSON 解析失败时会将原始输出放在 res.raw 中
      const rawData = res.data || res.raw || ''
      // base64 解码
      const logData = rawData ? decodeURIComponent(escape(atob(rawData))) : ''
      logs.value = logData.split('\n').filter(l => l.trim() !== '')
      if (isAutoRefresh.value) scrollToBottom()
    } else {
      // 显示错误信息
      logs.value = [`ERROR (Spawn API): ${res.msg || 'Process failed'}`, `Code: ${res.code}`]
    }
  } catch (e) {
    console.error('Failed to fetch logs via spawnApi', e)
    logs.value = [`ERROR (Exception): ${e.message}`]
  } finally {
    isLoading.value = false
  }
}

const scrollToBottom = async () => {
  await nextTick()
  if (logContainer.value) logContainer.value.scrollTop = logContainer.value.scrollHeight
}

const toggleAutoRefresh = () => { isAutoRefresh.value = !isAutoRefresh.value }
const clearLogs = () => { logs.value = [] }

const formatLog = (logLine) => {
  // 处理解析失败的情况
  if (logLine.startsWith('ERROR (JSON Parse):')) {
    return `<span class="text-rose-500 font-bold underline">${logLine}</span>`
  }

  // MosDNS 日志通常格式: 2024-03-02T12:34:56.789Z INFO ...
  if (/\b(error|ERROR)\b/.test(logLine))
    return `<span class="text-rose-400 font-medium">${logLine}</span>`
  if (/\b(warn|WARN)\b/.test(logLine))
    return `<span class="text-amber-400">${logLine}</span>`
  if (/\b(info|INFO)\b/.test(logLine)) {
    // 突出显示 INFO 标签，但不删除它，保留原始完整性
    return logLine.replace(/\b(info|INFO)\b/g, '<span class="text-emerald-500 font-bold px-1">INFO</span>')
  }
  return `<span class="theme-text-secondary">${logLine}</span>`
}

onMounted(() => {
  fetchLogs()
  pollTimer = setInterval(() => { if (isAutoRefresh.value) fetchLogs() }, 2000)
})

onUnmounted(() => { if (pollTimer) clearInterval(pollTimer) })
</script>

<template>
  <div class="h-full max-w-lg mx-auto flex flex-col pt-4 px-4 pb-6">
    <div class="flex items-center justify-between mb-4">
      <h2 class="text-lg font-bold theme-text-heading tracking-tight flex items-center space-x-2">
        <span class="w-2 h-2 rounded-full" :class="isAutoRefresh ? 'bg-emerald-500 animate-pulse' : 'theme-text-muted'"></span>
        <span>{{ t('log.title') }}</span>
      </h2>
      <div class="flex space-x-2">
        <button @click="toggleAutoRefresh"
          class="p-2 rounded-xl border transition-colors"
          :class="isAutoRefresh ? 'bg-emerald-500/10 border-emerald-500/30 text-emerald-400' : 'theme-bg-card theme-border-input theme-text-secondary'">
          <PauseIcon v-if="isAutoRefresh" class="w-4 h-4" />
          <PlayIcon v-else class="w-4 h-4" />
        </button>
        <button @click="fetchLogs" class="p-2 rounded-xl theme-bg-card border theme-border-input theme-text-secondary hover:theme-text transition-colors" :class="{ 'opacity-50': isLoading }">
          <ArrowPathIcon class="w-4 h-4" :class="{ 'animate-spin': isLoading }" />
        </button>
        <button @click="clearLogs" class="p-2 rounded-xl bg-rose-500/10 border border-rose-500/20 text-rose-400 hover:bg-rose-500/20 transition-colors">
          <TrashIcon class="w-4 h-4" />
        </button>
      </div>
    </div>

    <div class="flex-1 theme-bg-terminal border theme-border rounded-2xl overflow-hidden flex flex-col relative shadow-inner">
      <div class="theme-bg-card px-4 py-2 text-xs font-medium theme-text-muted border-b theme-border flex space-x-2">
        <div class="w-2.5 h-2.5 rounded-full bg-rose-500/80"></div>
        <div class="w-2.5 h-2.5 rounded-full bg-amber-500/80"></div>
        <div class="w-2.5 h-2.5 rounded-full bg-emerald-500/80"></div>
        <span class="ml-2 font-mono">mosdns.log</span>
      </div>
      <div ref="logContainer" class="flex-1 overflow-y-auto p-4 font-mono text-[11px] leading-relaxed break-all"
        style="font-family: 'JetBrains Mono', 'Fira Code', monospace;">
        <div v-if="logs.length === 0" class="theme-text-muted flex items-center justify-center h-full italic">
          {{ t('log.noLogs') }}
        </div>
        <template v-else>
          <div v-for="(line, index) in logs" :key="index" class="hover:bg-indigo-500/5 px-1 -mx-1 rounded" v-html="formatLog(line)"></div>
        </template>
      </div>
    </div>
  </div>
</template>
