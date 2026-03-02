# MosdnsForKSU

[![Build Module](https://github.com/powerAn2020/MosDNSForKSU/actions/workflows/build.yml/badge.svg)](https://github.com/powerAn2020/MosDNSForKSU/actions/workflows/build.yml)

基于 [mosdns v5](https://github.com/IrineSistiana/mosdns) 的 KernelSU 模块，提供**无泄漏 DNS 智能分流**与 **WebUI 可视化管理**。

## ✨ 特性

- **五级队列无泄漏 DNS 分流** — GFW → 白名单 → !CN → CN → Fallback（严格境外）
- **污染 IP 过滤** — 自动丢弃已知 GFW 污染 IP 和江苏反诈墙 CIDR 段
- **GeoIP 反向验证** — 非 CN 查询返回 CN IP 时丢弃，防止 DNS 劫持
- **ECS 隔离** — 国内查询附加 ECS，境外查询不附加
- **WebUI 管理** — 仪表盘实时监控 + 设置面板 + 日志查看
- **国际化** — 中文 / English 双语支持
- **深色 / 亮色主题** — 自动适配，一键切换
- **GeoData 在线更新** — 一键从 GitHub 拉取最新 GeoSite/GeoIP 规则

## 📦 安装

1. 从 [Releases](https://github.com/powerAn2020/MosDNSForKSU/releases) 下载最新 `.zip` 模块包
2. 在 KernelSU 管理器中安装模块
3. 重启设备
4. 在 KernelSU WebUI 中打开模块进行管理

> **要求**：arm64 设备 + KernelSU

## 🏗️ 项目结构

```
MosdnsForKSU/
├── module.prop            # KernelSU 模块元信息
├── customize.sh           # 安装脚本
├── service.sh             # 开机自启服务
├── action.sh              # WebUI 条目快速操作脚本 (Start/Stop)
├── conf/                  # mosdns 默认配置模板
│   ├── config.yaml        # 主配置（五级队列分流）
│   ├── dns.yaml           # 上游 DNS 定义
│   ├── dat_exec.yaml      # 规则/缓存/ECS 插件
│   └── rule/              # 白名单 & 灰名单
├── scripts/
│   └── api.sh             # WebUI Shell RPC 后端（16 条命令）
├── ui-src/                # 前端源码 (Vue 3 + Vite + Tailwind CSS)
└── .github/workflows/
    └── build.yml          # CI：下载 mosdns + 构建 WebUI + 打包发布
```

运行时数据存放于 `/data/adb/mosdns/`（独立于模块目录，升级不丢配置）。

## 🔧 DNS 分流架构

采用**三文件分离 + 五级队列**设计：

```
DNS 查询 → pre_sequence (预处理/拒绝/广告过滤)
         → main_sequence:
           ❶ GFW 域名     → 境外 DNS (经本地代理)
           ❷ 白名单域名    → 国内 DNS (直连)
           ❸ !CN 域名     → 境外 DNS (经本地代理)
           ❹ CN 域名      → 国内 DNS (直连)
           ❺ 未知域名     → Fallback (严格走境外)
```

每级查询均包含**污染 IP 过滤 + GeoIP 反向验证**，确保无泄漏。

## 🖥️ WebUI

| 页面 | 功能 |
|------|------|
| **仪表盘** | 服务状态、启停控制、实时流量统计（总查询/国内/境外/拦截/缓存） |
| **设置** | 基础配置、DNS 重定向开关、端口设置、GeoData 更新、黑白名单编辑、YAML 专家模式 |
| **日志** | 实时终端风格日志查看，支持自动刷新和关键字高亮 |

技术栈：Vue 3 (Composition API) + Vite + Tailwind CSS + Pinia + vue-i18n

## 🔨 本地开发

```bash
# 前端开发
cd ui-src
npm install
npm run dev       # 启动 Vite 开发服务器 (含 Mock 数据)
npm run build     # 构建到 ../webroot/
```

开发模式下自动使用 Mock 数据，无需真机环境即可调试 UI。

## 📝 参考资料

- [mosdns v5](https://github.com/IrineSistiana/mosdns) — DNS 转发/分流核心引擎
- [moreoronce/MosDNS-Config](https://github.com/moreoronce/MosDNS-Config) — 三文件分离配置架构参考
- [MosDNS 无泄漏配置指南](https://deeprouter.org/article/mosdns-config-with-no-leak) — 防泄漏规则设计参考
- [Loyalsoldier/v2ray-rules-dat](https://github.com/Loyalsoldier/v2ray-rules-dat) — GeoSite 规则数据源
- [Hackl0us/GeoIP2-CN](https://github.com/Hackl0us/GeoIP2-CN) — GeoIP CN 数据源
- [KernelSU Module WebUI](https://kernelsu.org/guide/module-webui.html) — WebUI 开发文档

## 📄 License

GPL-3.0
