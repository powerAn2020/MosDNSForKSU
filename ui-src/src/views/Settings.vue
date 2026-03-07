<script setup>
import { ref, onMounted, computed, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { useAppStore } from '@/stores/app'
import { execApi, spawnApi, setDebug, getDebug } from '@/api/kernelsu'
import { 
  ArrowDownTrayIcon,
  CheckCircleIcon,
  ExclamationTriangleIcon,
  Cog6ToothIcon,
  DocumentTextIcon,
  ShieldExclamationIcon,
  ListBulletIcon,
  ArrowPathIcon,
  InformationCircleIcon
} from '@heroicons/vue/24/outline'

const { t } = useI18n()
const appStore = useAppStore()

const localSettings = ref({})
const isSaving = ref(false)
const isUpdatingGeo = ref(false)
const showGeoModal = ref(false)
const geoUpdateLogs = ref('')
const toast = ref({ show: false, msg: '', type: 'success' })
const confirmModal = ref({ show: false, title: '', msg: '', onConfirm: null })
const rawConfigs = ref({ whitelist: '', greylist: '', config: '', dns: '', dat_exec: '' })
const activeTab = ref('basic')
const activeTabConfigs = ref('dns')
const debugMode = ref(getDebug())

const toggleDebug = (val) => {
  debugMode.value = val
  setDebug(val)
}

const showToast = (msg, type = 'success') => {
  toast.value = { show: true, msg, type }
  setTimeout(() => { toast.value.show = false }, 3000)
}

const openConfirm = (title, msg, onConfirm) => {
  confirmModal.value = { show: true, title, msg, onConfirm }
}

const closeConfirm = (isConfirm) => {
  const { onConfirm } = confirmModal.value
  confirmModal.value.show = false
  if (isConfirm && onConfirm) onConfirm()
}

onMounted(async () => {
  await appStore.fetchSettings()
  localSettings.value = JSON.parse(JSON.stringify(appStore.settings))
  await fetchRawConfigs()
})

watch(() => appStore.settings, (newVal) => {
  if (Object.keys(localSettings.value).length === 0)
    localSettings.value = JSON.parse(JSON.stringify(newVal))
}, { deep: true })

const fetchRawConfigs = async () => {
  try {
    const res = await execApi('get_config')
    if (res.code === 0 && res.data) {
       const decode = (b64) => b64 ? decodeURIComponent(escape(atob(b64))) : ''
       rawConfigs.value.whitelist = decode(res.data.whitelist)
       rawConfigs.value.greylist = decode(res.data.greylist)
       rawConfigs.value.config = decode(res.data.config)
       rawConfigs.value.dns = decode(res.data.dns)
       rawConfigs.value.dat_exec = decode(res.data.dat_exec)
    }
  } catch (e) { console.error('Failed to fetch configs', e) }
}

const isDirty = computed(() => {
  if (activeTab.value !== 'basic' || Object.keys(localSettings.value).length === 0) return false
  const s1 = localSettings.value
  const s2 = appStore.settings
  const fields = ['auto_start', 'dns_redirect', 'ipv6_support', 'ad_block', 'listen_port', 'proxy_port']
  return fields.some(k => s1[k] != s2[k])
})

const saveSettings = async () => {
  if (isSaving.value) return
  isSaving.value = true
  try {
    // 1. 停止服务
    await execApi('stop')
    
    // 2. 保存设置
    const jsonStr = JSON.stringify(localSettings.value)
    const res = await execApi('save_settings', `'${jsonStr}'`)
    
    // 3. 启动服务 (无论保存成功与否，由于已经停止，尝试重新拉起)
    await execApi('start')
    
    if (res.code === 0) {
      // 成功后立即同步本地状态，避免 isDirty 竞态
      await appStore.fetchSettings()
      localSettings.value = JSON.parse(JSON.stringify(appStore.settings))
      showToast(t('settings.saveSuccess'))
    } else {
      showToast(res.msg || t('settings.saveFail'), 'error')
    }
    // 4. 刷新状态
    await appStore.fetchStatus()
  } catch (e) { 
    console.error('Save failed', e)
    showToast(t('settings.saveFail'), 'error')
  }
  finally { isSaving.value = false }
}

const updateGeoData = async () => {
  if (isUpdatingGeo.value) return
  isUpdatingGeo.value = true
  showGeoModal.value = true
  geoUpdateLogs.value = t('settings.updatingGeodata') + '\n\n'
  
  try {
    const res = await spawnApi('update_geodata', '', { 
      timeout: 5*60*1000,//超时时间
      onStdout: (data) => {
        geoUpdateLogs.value += data
      }
    })
    geoUpdateLogs.value += `\n[Result] ${res.msg || (res.code === 0 ? '✓ OK' : '⚠ partial')}`
  } catch (e) {
    geoUpdateLogs.value += `\n[Error] ✗ ${e.message}`
  } finally {
    isUpdatingGeo.value = false
  }
}

const saveSingleConfig = async (type, content) => {
  try {
    // 1. 编码为 base64
    const b64 = btoa(unescape(encodeURIComponent(content)))
    
    // 2. 保存文件
    const res = await execApi('save_config', `${type} '${b64}'`)
    
    if (res.code === 0) {
      showToast(`${type} ${t('settings.saveSuccess')}`)
      await fetchRawConfigs() // 刷新本地缓存
    } else {
      showToast(`${type} ${t('settings.saveFail')}: ${res.msg}`, 'error')
    }
    // 3. 刷新状态
    await appStore.fetchStatus()
  } catch(e) { 
    console.error(e)
    showToast(t('settings.saveFail'), 'error')
  }
}



const applyConfig = async () => {
  openConfirm(t('settings.confirmTitle'), t('settings.applyConfirm'), async () => {
    const res = await execApi('apply_config')
    if (res.code === 0) {
      showToast(t('settings.applySuccess'))
      appStore.fetchStatus()
    } else {
      showToast(`${t('settings.applyFail')} ${res.msg}`, 'error')
    }
  })
}
</script>

<template>
  <div class="max-w-lg mx-auto px-4 py-6 pb-24 h-full flex flex-col items-stretch space-y-6">
    
    <div class="flex items-center space-x-2 theme-text-heading font-bold text-xl px-1">
      <Cog6ToothIcon class="w-6 h-6 text-indigo-500" />
      <h2>{{ t('settings.title') }}</h2>
    </div>

    <!-- Tabs -->
    <div class="flex space-x-1 p-1 theme-bg-card rounded-xl border theme-border-secondary">
      <button 
        v-for="(label, key) in { basic: t('settings.tabBasic'), rules: t('settings.tabRules'), advanced: t('settings.tabAdvanced') }"
        :key="key"
        @click="activeTab = key"
        class="flex-1 py-1.5 px-3 text-sm font-medium rounded-lg transition-colors"
        :class="activeTab === key ? 'theme-tab-active shadow-sm' : 'theme-text-secondary'"
      >
        {{ label }}
      </button>
    </div>

    <!-- ===== 1. 基础设置 ===== -->
    <div v-show="activeTab === 'basic'" class="space-y-6 flex-1 overflow-y-auto pb-6">
      <div class="theme-bg-card rounded-3xl p-5 border theme-border-secondary space-y-5">
        <h3 class="text-sm font-semibold theme-text-secondary tracking-wider">{{ t('settings.controlTitle') }}</h3>
        
        <!-- Toggle: 开机自启 -->
        <div class="flex items-center justify-between">
          <div>
            <div class="theme-text font-medium">{{ t('settings.autoStart') }}</div>
            <div class="text-xs theme-text-muted">{{ t('settings.autoStartDesc') }}</div>
          </div>
          <label class="relative inline-flex items-center cursor-pointer">
            <input type="checkbox" v-model="localSettings.auto_start" class="sr-only peer">
            <div class="w-11 h-6 bg-gray-300 dark:bg-zinc-700 peer-focus:outline-none rounded-full peer peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:border-gray-300 after:border after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-emerald-500"></div>
          </label>
        </div>

        <!-- Toggle: DNS 重定向 -->
        <div class="flex items-center justify-between pt-2 border-t theme-border-secondary">
          <div>
            <div class="theme-text font-medium">{{ t('settings.dnsRedirect') }}</div>
            <div class="text-xs theme-text-muted">{{ t('settings.dnsRedirectDesc') }}</div>
          </div>
          <label class="relative inline-flex items-center cursor-pointer">
            <input type="checkbox" v-model="localSettings.dns_redirect" class="sr-only peer">
            <div class="w-11 h-6 bg-gray-300 dark:bg-zinc-700 peer-focus:outline-none rounded-full peer peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:border-gray-300 after:border after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-indigo-500"></div>
          </label>
        </div>

        <!-- Toggle: IPv6 支持 -->
        <div class="flex items-center justify-between pt-2 border-t theme-border-secondary">
          <div>
            <div class="theme-text font-medium">{{ t('settings.ipv6Support') }}</div>
            <div class="text-xs theme-text-muted">{{ t('settings.ipv6SupportDesc') }}</div>
          </div>
          <label class="relative inline-flex items-center cursor-pointer">
            <input type="checkbox" v-model="localSettings.ipv6_support" class="sr-only peer">
            <div class="w-11 h-6 bg-gray-300 dark:bg-zinc-700 peer-focus:outline-none rounded-full peer peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:border-gray-300 after:border after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-indigo-500"></div>
          </label>
        </div>
        
        <!-- Toggle: 广告拦截 -->
        <div class="flex items-center justify-between pt-2 border-t theme-border-secondary">
          <div>
            <div class="theme-text font-medium">{{ t('settings.adBlock') }}</div>
            <div class="text-xs theme-text-muted">{{ t('settings.adBlockDesc') }}</div>
          </div>
          <label class="relative inline-flex items-center cursor-pointer">
            <input type="checkbox" v-model="localSettings.ad_block" class="sr-only peer">
            <div class="w-11 h-6 bg-gray-300 dark:bg-zinc-700 peer-focus:outline-none rounded-full peer peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:border-gray-300 after:border after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-emerald-500"></div>
          </label>
        </div>

        <!-- Toggle: 调试模式 -->
        <div class="flex items-center justify-between pt-2 border-t theme-border-secondary">
          <div>
            <div class="theme-text font-medium">{{ t('settings.debug') }}</div>
            <div class="text-xs theme-text-muted">{{ t('settings.debugDesc') }}</div>
          </div>
          <label class="relative inline-flex items-center cursor-pointer">
            <input type="checkbox" :checked="debugMode" @change="toggleDebug($event.target.checked)" class="sr-only peer">
            <div class="w-11 h-6 bg-gray-300 dark:bg-zinc-700 peer-focus:outline-none rounded-full peer peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:border-gray-300 after:border after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-amber-500"></div>
          </label>
        </div>
      </div>

      <!-- 端口配置 -->
      <div class="theme-bg-card rounded-3xl p-5 border theme-border-secondary space-y-4">
        <h3 class="text-sm font-semibold theme-text-secondary tracking-wider">{{ t('settings.networkTitle') }}</h3>
        <div class="space-y-3">
          <div>
            <label class="block text-xs theme-text-secondary mb-1">{{ t('settings.listenPort') }}</label>
            <input v-model.number="localSettings.listen_port" type="number" class="w-full theme-bg-input border theme-border-input rounded-xl px-3 py-2 theme-text text-sm focus:outline-none focus:border-indigo-500 transition-colors">
          </div>
          <div>
            <label class="block text-xs theme-text-secondary mb-1 flex justify-between">
              <span>{{ t('settings.proxyPort') }}</span>
              <span class="text-indigo-500">{{ t('settings.proxyPortPrefix') }}</span>
            </label>
            <input v-model.number="localSettings.proxy_port" type="number" class="w-full theme-bg-input border theme-border-input rounded-xl px-3 py-2 theme-text text-sm focus:outline-none focus:border-indigo-500 transition-colors">
          </div>
        </div>
      </div>

      <!-- GeoData -->
      <div class="theme-bg-card rounded-3xl p-5 border theme-border-secondary space-y-4">
        <h3 class="text-sm font-semibold theme-text-secondary tracking-wider">{{ t('settings.geodataTitle') }}</h3>
        <button @click="updateGeoData"
          class="w-full rounded-xl py-3 px-4 font-semibold text-sm flex justify-center items-center space-x-2 transition-all border focus:outline-none theme-bg-input theme-text hover:bg-indigo-600 hover:text-white theme-border-input">
          <ArrowDownTrayIcon class="w-5 h-5" />
          <span>{{ t('settings.updateGeodata') }}</span>
        </button>
      </div>
    </div>

    <!-- ===== 2. 黑白名单 ===== -->
    <div v-show="activeTab === 'rules'" class="flex-1 flex flex-col space-y-4 h-full pb-4">
      <div class="theme-bg-card rounded-3xl flex flex-col flex-1 border theme-border-secondary overflow-hidden">
        <div class="theme-bg-card px-4 py-3 border-b theme-border flex justify-between items-center">
          <div class="flex items-center space-x-2 theme-text">
            <ListBulletIcon class="w-5 h-5 text-emerald-500" />
            <span class="text-sm font-semibold">{{ t('settings.whitelist') }}</span>
          </div>
          <button @click="saveSingleConfig('whitelist', rawConfigs.whitelist)" class="text-xs bg-emerald-500/20 text-emerald-500 px-3 py-1.5 rounded-lg hover:bg-emerald-500/30">
            {{ t('settings.save') }}
          </button>
        </div>
        <textarea v-model="rawConfigs.whitelist" class="flex-1 w-full min-h-[30vh] theme-bg-terminal theme-text-secondary font-mono text-xs p-4 focus:outline-none resize-none leading-relaxed" :placeholder="t('settings.whitelistPlaceholder')"></textarea>
      </div>

      <div class="theme-bg-card rounded-3xl flex flex-col flex-1 border theme-border-secondary overflow-hidden">
        <div class="theme-bg-card px-4 py-3 border-b theme-border flex justify-between items-center">
          <div class="flex items-center space-x-2 theme-text">
            <ShieldExclamationIcon class="w-5 h-5 text-purple-500" />
            <span class="text-sm font-semibold">{{ t('settings.greylist') }}</span>
          </div>
          <button @click="saveSingleConfig('greylist', rawConfigs.greylist)" class="text-xs bg-purple-500/20 text-purple-500 px-3 py-1.5 rounded-lg hover:bg-purple-500/30">
            {{ t('settings.save') }}
          </button>
        </div>
        <textarea v-model="rawConfigs.greylist" class="flex-1 w-full min-h-[30vh] theme-bg-terminal theme-text-secondary font-mono text-xs p-4 focus:outline-none resize-none leading-relaxed" :placeholder="t('settings.greylistPlaceholder')"></textarea>
      </div>
    </div>

    <!-- ===== 3. 专家模式 ===== -->
    <div v-show="activeTab === 'advanced'" class="flex-1 flex flex-col space-y-4 h-full pb-4">
      <div class="bg-amber-50 dark:bg-amber-900/10 border border-amber-200/60 dark:border-amber-500/20 rounded-2xl p-4 flex items-start space-x-3 shadow-sm">
        <ExclamationTriangleIcon class="w-6 h-6 text-amber-600 dark:text-amber-500 flex-shrink-0" />
        <div class="text-[13px] text-black dark:text-amber-200 leading-relaxed font-medium">
          <strong class="text-amber-700 dark:text-amber-400 font-bold text-sm">{{ t('settings.dangerWarning') }}</strong>：{{ t('settings.advancedWarning') }}
        </div>
      </div>

      <div class="flex-1 theme-bg-terminal border theme-border-secondary rounded-2xl flex flex-col overflow-hidden shadow-inner relative">
        <div class="flex items-center theme-bg-card px-2 border-b theme-border">
          <select v-model="activeTabConfigs" class="bg-transparent text-sm theme-text py-2.5 px-2 focus:outline-none cursor-pointer flex-1 font-mono">
            <option value="dns">{{ t('settings.dnsYaml') }}</option>
            <option value="dat_exec">{{ t('settings.datExecYaml') }}</option>
            <option value="config">{{ t('settings.configYaml') }}</option>
          </select>
          <button @click="saveSingleConfig(activeTabConfigs, rawConfigs[activeTabConfigs])"
            class="ml-2 text-xs bg-indigo-600 hover:bg-indigo-500 text-white px-4 py-1.5 rounded-lg transition-colors font-medium shadow">
            {{ t('settings.saveFile') }}
          </button>
        </div>
        <textarea v-model="rawConfigs[activeTabConfigs]"
          class="flex-1 w-full min-h-[50vh] bg-transparent text-emerald-600 dark:text-emerald-400/90 font-mono text-[11px] p-4 focus:outline-none resize-none leading-relaxed"
          spellcheck="false"></textarea>
      </div>

      <button @click="applyConfig"
        class="w-full theme-bg-card hover:bg-indigo-600 hover:text-white border theme-border-input theme-text rounded-2xl py-4 font-bold flex justify-center items-center space-x-2 transition-all shadow-lg active:scale-[0.98]">
        <DocumentTextIcon class="w-6 h-6 text-emerald-500" />
        <span>{{ t('settings.applyNow') }}</span>
      </button>
    </div>

    <!-- 悬浮保存按钮 -->
    <div class="fixed bottom-20 left-1/2 -translate-x-1/2 w-[calc(100%-2rem)] max-w-lg z-40 transition-all duration-300"
      :class="isDirty ? 'opacity-100 translate-y-0' : 'opacity-0 translate-y-8 pointer-events-none'">
      <button @click="saveSettings" :disabled="isSaving"
        class="w-full bg-indigo-600 hover:bg-indigo-500 text-white shadow-xl shadow-indigo-500/20 py-3.5 rounded-2xl font-bold flex justify-center items-center space-x-2">
        <span v-if="isSaving" class="w-5 h-5 border-2 border-white/20 border-t-white rounded-full animate-spin"></span>
        <CheckCircleIcon v-else class="w-5 h-5" />
        <span>{{ isSaving ? t('settings.saving') : t('settings.saveApply') }}</span>
      </button>
    </div>

    <!-- ===== GeoData 更新日志弹窗 ===== -->
    <div v-show="showGeoModal" class="fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-sm p-4 transition-all duration-300">
      <div class="theme-bg-card w-full max-w-md rounded-3xl shadow-2xl flex flex-col overflow-hidden max-h-[80vh] border theme-border-secondary transition-transform scale-100">
        <!-- Header -->
        <div class="p-5 border-b theme-border flex items-center space-x-3 bg-indigo-500/5 dark:bg-indigo-500/10">
          <div class="w-10 h-10 rounded-xl bg-indigo-500/20 flex items-center justify-center">
            <ArrowPathIcon v-if="isUpdatingGeo" class="w-6 h-6 text-indigo-600 dark:text-indigo-400 animate-spin" />
            <CheckCircleIcon v-else class="w-6 h-6 text-emerald-600 dark:text-emerald-400" />
          </div>
          <div>
            <h3 class="font-bold theme-text text-lg leading-tight">{{ t('settings.geodataUpdateLogTitle') || 'GeoData Update Log' }}</h3>
            <p class="text-xs theme-text-secondary mt-0.5">{{ isUpdatingGeo ? t('settings.updatingGeodata') : t('settings.updateSuccess') || 'Updated successfully' }}</p>
          </div>
        </div>
        <!-- Terminal / Content -->
        <div class="p-4 flex-1 overflow-y-auto theme-bg-terminal border-b theme-border-secondary">
          <pre class="text-[11px] font-mono theme-text-secondary whitespace-pre-wrap break-all leading-relaxed">{{ geoUpdateLogs }}</pre>
        </div>
        <!-- Footer -->
        <div class="p-5 bg-gray-50/50 dark:bg-zinc-900/50 flex justify-end">
          <button @click="showGeoModal = false" :disabled="isUpdatingGeo"
            class="w-full sm:w-auto px-10 py-3 rounded-2xl font-bold transition-all shadow-lg active:scale-95 disabled:opacity-50 disabled:cursor-not-allowed"
            :class="isUpdatingGeo 
              ? 'bg-indigo-600/20 text-indigo-400' 
              : 'bg-indigo-600 text-white hover:bg-indigo-500 shadow-indigo-500/25'">
            {{ isUpdatingGeo ? t('settings.updating') : t('settings.close') || 'Close' }}
          </button>
        </div>
      </div>
    </div>

    <!-- ===== Toast 通知 ===== -->
    <transition name="fade">
      <div v-if="toast.show" class="fixed top-8 left-1/2 -translate-x-1/2 z-[100] px-6 py-3 rounded-2xl shadow-2xl flex items-center space-x-3 backdrop-blur-md min-w-[200px]"
        :class="toast.type === 'error' ? 'bg-red-500/90 text-white' : 'bg-emerald-500/90 text-white'">
        <CheckCircleIcon v-if="toast.type === 'success'" class="w-6 h-6" />
        <ExclamationTriangleIcon v-else class="w-6 h-6" />
        <span class="font-bold">{{ toast.msg }}</span>
      </div>
    </transition>

    <!-- ===== 确认弹窗 ===== -->
    <transition name="fade">
      <div v-if="confirmModal.show" class="fixed inset-0 z-50 flex items-center justify-center bg-black/50 backdrop-blur-sm p-4">
        <div class="theme-bg-card w-full max-w-sm rounded-3xl shadow-2xl overflow-hidden border theme-border-secondary">
          <div class="p-6 text-center space-y-4">
            <div class="bg-indigo-50 dark:bg-indigo-900/30 w-16 h-16 rounded-2xl flex items-center justify-center mx-auto text-indigo-500">
              <InformationCircleIcon class="w-10 h-10" />
            </div>
            <h3 class="text-xl font-bold theme-text">{{ confirmModal.title }}</h3>
            <p class="theme-text-secondary text-sm">{{ confirmModal.msg }}</p>
          </div>
          <div class="p-4 bg-gray-50/50 dark:bg-zinc-900/50 flex space-x-3">
            <button @click="closeConfirm(false)" class="flex-1 py-3 font-bold theme-text-secondary hover:theme-bg-input rounded-2xl transition-all">
              {{ t('settings.cancel') }}
            </button>
            <button @click="closeConfirm(true)" class="flex-1 py-3 font-bold bg-indigo-600 text-white hover:bg-indigo-500 rounded-2xl shadow-lg shadow-indigo-500/20 transition-all">
              {{ t('settings.confirm') || 'OK' }}
            </button>
          </div>
        </div>
      </div>
    </transition>

  </div>
</template>
