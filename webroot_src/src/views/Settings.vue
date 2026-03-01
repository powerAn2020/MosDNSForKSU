<script setup>
import { ref, onMounted, computed, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { useAppStore } from '@/stores/app'
import { execApi } from '@/api/kernelsu'
import { 
  ArrowDownTrayIcon,
  CheckCircleIcon,
  ExclamationTriangleIcon,
  Cog6ToothIcon,
  DocumentTextIcon,
  ShieldExclamationIcon,
  ListBulletIcon
} from '@heroicons/vue/24/outline'

const { t } = useI18n()
const appStore = useAppStore()

const localSettings = ref({})
const isSaving = ref(false)
const isUpdatingGeo = ref(false)
const geoUpdateStatus = ref('')
const rawConfigs = ref({ whitelist: '', greylist: '', config: '', dns: '', dat_exec: '' })
const activeTab = ref('basic')
const activeTabConfigs = ref('dns')

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
       const unescape = (str) => str ? str.replace(/\\n/g, '\n') : ''
       rawConfigs.value.whitelist = unescape(res.data.whitelist)
       rawConfigs.value.greylist = unescape(res.data.greylist)
       rawConfigs.value.config = unescape(res.data.config)
       rawConfigs.value.dns = unescape(res.data.dns)
       rawConfigs.value.dat_exec = unescape(res.data.dat_exec)
    }
  } catch (e) { console.error('Failed to fetch configs', e) }
}

const isDirty = computed(() => {
  return JSON.stringify(localSettings.value) !== JSON.stringify(appStore.settings) && activeTab.value === 'basic'
})

const saveSettings = async () => {
  if (isSaving.value) return
  isSaving.value = true
  try {
    const jsonStr = JSON.stringify(localSettings.value)
    const res = await execApi('save_settings', `'${jsonStr}'`)
    if (res.code === 0) await appStore.fetchSettings()
  } catch (e) { console.error('Save failed', e) }
  finally { isSaving.value = false }
}

const updateGeoData = async () => {
  if (isUpdatingGeo.value) return
  isUpdatingGeo.value = true
  geoUpdateStatus.value = t('settings.updatingGeodata')
  try {
    const res = await execApi('update_geodata')
    geoUpdateStatus.value = res.msg || (res.code === 0 ? '✓ OK' : '⚠ partial')
    setTimeout(() => { geoUpdateStatus.value = '' }, 3000)
  } catch (e) { geoUpdateStatus.value = '✗ ' + e.message }
  finally { isUpdatingGeo.value = false }
}

const saveSingleConfig = async (type, content) => {
  try {
    const safeContent = content.replace(/'/g, "'\\''")
    const res = await execApi('save_config', `${type} '${safeContent}'`)
    alert(res.code === 0 ? `${type} ✓` : `✗: ${res.msg}`)
  } catch(e) { console.error(e); alert('✗') }
}

const applyConfig = async () => {
  if (confirm(t('settings.applyConfirm'))) {
    const res = await execApi('apply_config')
    alert(res.code === 0 ? t('settings.applySuccess') : `${t('settings.applyFail')}\n${res.msg}`)
    if (res.code === 0) appStore.fetchStatus()
  }
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
      </div>

      <!-- 端口配置 -->
      <div class="theme-bg-card rounded-3xl p-5 border theme-border-secondary space-y-4">
        <h3 class="text-sm font-semibold theme-text-secondary tracking-wider">{{ t('settings.networkTitle') }}</h3>
        <div class="space-y-3">
          <div>
            <label class="block text-xs theme-text-secondary mb-1">{{ t('settings.listenPort') }}</label>
            <input v-model="localSettings.listen_port" type="text" class="w-full theme-bg-input border theme-border-input rounded-xl px-3 py-2 theme-text text-sm focus:outline-none focus:border-indigo-500 transition-colors">
          </div>
          <div>
            <label class="block text-xs theme-text-secondary mb-1 flex justify-between">
              <span>{{ t('settings.proxyPort') }}</span>
              <span class="text-indigo-500">{{ t('settings.proxyPortPrefix') }}</span>
            </label>
            <input v-model="localSettings.proxy_port" type="text" class="w-full theme-bg-input border theme-border-input rounded-xl px-3 py-2 theme-text text-sm focus:outline-none focus:border-indigo-500 transition-colors">
          </div>
        </div>
      </div>

      <!-- GeoData -->
      <div class="theme-bg-card rounded-3xl p-5 border theme-border-secondary space-y-4">
        <h3 class="text-sm font-semibold theme-text-secondary tracking-wider">{{ t('settings.geodataTitle') }}</h3>
        <button @click="updateGeoData" :disabled="isUpdatingGeo"
          class="w-full rounded-xl py-3 px-4 font-semibold text-sm flex justify-center items-center space-x-2 transition-all theme-bg-input theme-text hover:bg-indigo-600 hover:text-white border theme-border-input focus:outline-none">
          <ArrowDownTrayIcon class="w-5 h-5" :class="{ 'animate-bounce': isUpdatingGeo }" />
          <span>{{ isUpdatingGeo ? t('settings.updatingGeodata') : t('settings.updateGeodata') }}</span>
        </button>
        <div v-if="geoUpdateStatus" class="flex items-center space-x-1 mt-2 px-1">
          <CheckCircleIcon v-if="geoUpdateStatus.includes('✓')" class="w-4 h-4 text-emerald-400" />
          <ExclamationTriangleIcon v-else class="w-4 h-4 text-amber-400" />
          <span class="text-xs theme-text-secondary">{{ geoUpdateStatus }}</span>
        </div>
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
        <textarea v-model="rawConfigs.whitelist" class="flex-1 w-full theme-bg-terminal theme-text-secondary font-mono text-xs p-4 focus:outline-none resize-none leading-relaxed" :placeholder="t('settings.whitelistPlaceholder')"></textarea>
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
        <textarea v-model="rawConfigs.greylist" class="flex-1 w-full theme-bg-terminal theme-text-secondary font-mono text-xs p-4 focus:outline-none resize-none leading-relaxed" :placeholder="t('settings.greylistPlaceholder')"></textarea>
      </div>
    </div>

    <!-- ===== 3. 专家模式 ===== -->
    <div v-show="activeTab === 'advanced'" class="flex-1 flex flex-col space-y-4 h-full pb-4">
      <div class="bg-amber-500/10 border border-amber-500/20 rounded-xl p-4 flex items-start space-x-3">
        <ExclamationTriangleIcon class="w-6 h-6 text-amber-500 flex-shrink-0" />
        <div class="text-xs text-amber-700 dark:text-amber-200/80 leading-relaxed">
          <strong class="text-amber-600 dark:text-amber-400">{{ t('settings.dangerWarning') }}</strong>：{{ t('settings.advancedWarning') }}
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
          class="flex-1 w-full bg-transparent text-emerald-600 dark:text-emerald-400/90 font-mono text-[11px] p-4 focus:outline-none resize-none leading-relaxed"
          spellcheck="false"></textarea>
      </div>

      <button @click="applyConfig"
        class="w-full theme-bg-card hover:bg-indigo-600 hover:text-white border theme-border-input theme-text rounded-xl py-3.5 font-bold flex justify-center items-center space-x-2 transition-all shadow-lg">
        <DocumentTextIcon class="w-5 h-5 text-emerald-500" />
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
  </div>
</template>
