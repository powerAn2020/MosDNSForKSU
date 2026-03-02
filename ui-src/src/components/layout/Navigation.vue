<script setup>
import { useRoute } from 'vue-router'
import { useI18n } from 'vue-i18n'
import { useThemeStore } from '@/stores/theme'
import { 
  HomeIcon, 
  Cog6ToothIcon, 
  DocumentTextIcon,
  SunIcon,
  MoonIcon,
  LanguageIcon
} from '@heroicons/vue/24/outline'

const route = useRoute()
const { t, locale } = useI18n()
const themeStore = useThemeStore()

const navItems = [
  { name: 'nav.dashboard', path: '/dashboard', icon: HomeIcon },
  { name: 'nav.settings', path: '/settings', icon: Cog6ToothIcon },
  { name: 'nav.log', path: '/log', icon: DocumentTextIcon },
]

const toggleLocale = () => {
  const next = locale.value === 'zh-CN' ? 'en' : 'zh-CN'
  locale.value = next
  localStorage.setItem('mosdns-locale', next)
}
</script>

<template>
  <nav class="flex items-center justify-between h-16 max-w-lg mx-auto px-2">
    <!-- 左侧：语言切换 -->
    <button 
      @click="toggleLocale"
      class="p-2 rounded-xl theme-text-muted hover:theme-text transition-colors"
      :title="locale === 'zh-CN' ? 'Switch to English' : '切换为中文'"
    >
      <LanguageIcon class="w-5 h-5" />
    </button>

    <!-- 中间：导航链接 -->
    <div class="flex justify-center items-center space-x-1 flex-1">
      <router-link
        v-for="item in navItems"
        :key="item.path"
        :to="item.path"
        class="flex flex-col items-center justify-center px-4 h-full space-y-1 transition-colors duration-200"
        :class="[
          route.path === item.path 
            ? 'text-indigo-500' 
            : 'theme-text-muted'
        ]"
      >
        <component 
          :is="item.icon" 
          class="w-5 h-5 transition-transform duration-200"
          :class="{ 'scale-110': route.path === item.path }"
        />
        <span class="text-[10px] font-medium tracking-wide">{{ t(item.name) }}</span>
      </router-link>
    </div>

    <!-- 右侧：主题切换 -->
    <button 
      @click="themeStore.toggleTheme()"
      class="p-2 rounded-xl theme-text-muted hover:theme-text transition-colors"
    >
      <MoonIcon v-if="themeStore.theme === 'light'" class="w-5 h-5" />
      <SunIcon v-else class="w-5 h-5" />
    </button>
  </nav>
</template>
