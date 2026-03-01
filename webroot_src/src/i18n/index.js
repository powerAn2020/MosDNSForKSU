import { createI18n } from 'vue-i18n'
import zhCN from './zh-CN'
import en from './en'

const savedLocale = localStorage.getItem('mosdns-locale') || 'zh-CN'

const i18n = createI18n({
    legacy: false, // 使用 Composition API 模式
    locale: savedLocale,
    fallbackLocale: 'zh-CN',
    messages: {
        'zh-CN': zhCN,
        'en': en
    }
})

export default i18n
