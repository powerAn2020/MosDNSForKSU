import { createRouter, createWebHashHistory } from 'vue-router'

const routes = [
    {
        path: '/',
        redirect: '/dashboard'
    },
    {
        path: '/dashboard',
        name: 'Dashboard',
        component: () => import('@/views/Dashboard.vue'),
        meta: { title: '仪表盘' }
    },
    {
        path: '/settings',
        name: 'Settings',
        component: () => import('@/views/Settings.vue'),
        meta: { title: '设置' }
    },
    {
        path: '/log',
        name: 'Log',
        component: () => import('@/views/Log.vue'),
        meta: { title: '日志' }
    },
]

const router = createRouter({
    // KernelSU WebView 中推荐使用 Hash 模式以防路由寻址失败
    history: createWebHashHistory(),
    routes,
})

// 可选：动态更新标题
router.afterEach((to) => {
    if (to.meta.title) {
        document.title = `${to.meta.title} - MosdnsForKSU`
    }
})

export default router
