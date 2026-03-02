import { defineStore } from 'pinia'
import { ref, watch } from 'vue'

export const useThemeStore = defineStore('theme', () => {
    const savedTheme = localStorage.getItem('mosdns-theme') || 'dark'
    const theme = ref(savedTheme)

    const isDark = () => theme.value === 'dark'

    const toggleTheme = () => {
        theme.value = theme.value === 'dark' ? 'light' : 'dark'
    }

    // 监听变化并持久化 + 同步到 DOM
    watch(theme, (val) => {
        localStorage.setItem('mosdns-theme', val)
        applyTheme(val)
    }, { immediate: true })

    function applyTheme(t) {
        const root = document.documentElement
        if (t === 'dark') {
            root.classList.add('dark')
            root.classList.remove('light')
        } else {
            root.classList.add('light')
            root.classList.remove('dark')
        }
    }

    return { theme, isDark, toggleTheme }
})
