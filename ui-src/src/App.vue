<script setup>
import { onMounted } from 'vue'
import { useAppStore } from '@/stores/app'
import { useThemeStore } from '@/stores/theme'
import Navigation from '@/components/layout/Navigation.vue'

const appStore = useAppStore()
const themeStore = useThemeStore()

onMounted(() => {
  appStore.fetchStatus()
  appStore.fetchSettings()
})
</script>

<template>
  <div class="min-h-screen theme-bg theme-text flex flex-col font-sans transition-colors duration-300">
    <main class="flex-1 overflow-y-auto pb-20">
      <router-view v-slot="{ Component }">
        <transition name="fade" mode="out-in">
          <component :is="Component" />
        </transition>
      </router-view>
    </main>
    <div class="fixed bottom-0 left-0 right-0 border-t theme-border theme-bg-nav backdrop-blur-md z-50">
      <Navigation />
    </div>
  </div>
</template>
