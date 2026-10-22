# openGym 个人长期可用 iOS App 设计

- 日期：2026-10-21
- 状态：设计已确认，待实施
- 目标设备：iPhone 11 Pro
- 最低 iOS 版本：16.1

## 1. 背景与目标

openGym 当前已经使用 React + Capacitor 提供 Android 原生壳，并且仓库中已经存在 `frontend/ios` 工程。本项目不重写 iOS 前端，而是在现有 Capacitor 架构上补齐 iOS 原生能力，使 openGym 成为适合个人长期使用的 iPhone App。

目标是让 iOS 与 Android 在用户可完成的训练任务上保持一致：离线训练、数据持久化、媒体、备份、通知、Rest Timer、HealthKit/Health Connect、服务器配对与同步均可用。由于 iOS 与 Android 的系统机制不同，底层实现可以不同，但用户可见的结果和数据语义应保持一致。

本阶段不以 App Store 发布为目标，采用 Apple Developer Team + Xcode 真机安装。签名周期受 Apple 限制，不能设置为十年；同一 Bundle ID、Team 和数据容器下覆盖安装应保留用户数据。

## 2. 技术路线

```text
React 19 前端
    -> Vite mobile build
    -> Capacitor 7
    -> Xcode iOS App
    -> iPhone 11 Pro
```

继续复用现有前端、训练逻辑、数据模型和备份格式，不复制一套 Swift 训练业务层。Swift 代码只负责系统能力和 Capacitor bridge。

当前 iOS 工程已有：

- Capacitor iOS 壳；
- iOS 15.5 部署目标（本项目提升到 16.1）；
- Capacitor Filesystem、Local Notifications、Share、App 等插件；
- 相机和麦克风用途说明；
- Print 插件；
- `ch.duartesantos.opengym` 现有 Bundle ID（实施时确认个人 Team 下可用，并固定下来）。

## 3. 功能范围

### 3.1 第一阶段必须支持

- 本地离线训练；
- 训练记录、计划、进度、体重和设置持久化；
- 自定义动作照片和视频；
- JSON 和包含媒体的 ZIP 备份/恢复；
- iOS 文件、iCloud Drive、AirDrop 和系统分享；
- 相机和二维码扫描；
- 训练日提醒；
- Rest Timer；
- iOS 锁屏 Live Activity；
- Apple HealthKit 写入训练和体重；
- 连接自建 openGym 服务端并配对；
- 离线变更排队和恢复网络后的同步；
- iPhone 11 Pro 真机安装和覆盖更新。

### 3.2 不采用的方案

- 不重写为纯 SwiftUI 应用；
- 不使用企业证书、第三方签名服务或越狱方案；
- 不把 Apple Health 数据上传到 openGym 服务端；
- 不在 iOS 复制 Android 前台服务；
- 不在第一阶段做 App Store 审核和公开发布；
- 不承诺超出 Apple 规则的十年签名。

## 4. 跨平台能力对齐

| Android 能力 | iOS 实现 | 对齐要求 |
|---|---|---|
| Capacitor Filesystem 数据文件 | Capacitor Filesystem，App 私有目录 | `opengym-state.json` 能恢复 |
| 相机、媒体 | iOS 相机/相册/麦克风权限 | 照片和视频可创建、播放和备份 |
| ML Kit 扫码 | ML Kit iOS 插件 | 扫码流程可用 |
| Local Notifications | iOS Local Notifications | 训练日和漏训提醒可用 |
| RestAlert / 前台服务 | ActivityKit Live Activity + 本地通知 | 锁屏可继续观察并操作计时 |
| Health Connect | HealthKit | 写入训练和体重、去重、更新、删除 |
| Android 备份文件夹 | `Documents/openGym` + Files/iCloud/分享 | 用户可访问并恢复备份 |
| Android 打印 | iOS 打印/分享面板 | 可保存 PDF 或打印 |
| 配对服务器 | Capacitor WebView + bearer token | 配对、离线同步、续期正常 |
| APK 自动更新 | Xcode/TestFlight/App Store 的 iOS 更新方式 | 不在 App 内安装 IPA |

iOS 没有 Android 前台服务和完全等价的任意文件夹授权，因此采用平台合适的实现；不得把这些限制伪装成已经完全相同的底层行为。

## 5. 原生模块设计

### 5.1 Live Activity

新增 `OpenGymLiveActivity` Widget Extension 和 `RestActivityPlugin.swift`。

Activity 状态至少包含：

- 训练/动作标题；
- 总时长；
- 结束时间或剩余时间；
- 暂停状态；
- 当前主题颜色；
- 可用操作状态。

插件接口覆盖：

- start；
- update；
- pause；
- resume；
- add 15 seconds；
- subtract 15 seconds；
- skip；
- stop。

Live Activity 按钮通过 App Intents 与 App Group 共享状态传回主 App。主 App 回到前台时读取最近一次原生操作并与 JavaScript 状态合并，避免锁屏操作和 WebView 状态分叉。

普通通知作为 Live Activity 不可用或权限不足时的降级路径。通知声音遵守 iOS 权限限制，不假设可以使用 Android 的静音穿透能力。

### 5.2 HealthKit

新增 iOS HealthKit Capacitor 插件，并让共享 JavaScript 层按平台选择：

```text
共享健康数据映射
    -> Android Health Connect
    -> iOS HealthKit
```

写入：

- 力量或有氧训练；
- 训练开始和结束时间；
- 训练名称和类型；
- 体重。

行为：

- 默认关闭；
- 开启时请求最小必要权限；
- 使用 openGym 外部记录标识实现幂等；
- 编辑时更新；
- 删除时删除对应的 openGym 记录；
- 关闭时询问是否删除由 openGym 写入的记录；
- 权限拒绝或系统不可用时不阻断训练保存。

设备专属的同步指纹和映射保留在 `opengym-health.json`，不进入同步状态和导出备份。

### 5.3 备份与媒体

保留现有跨平台 JSON/ZIP 格式。iOS 自动备份写入 `Documents/openGym/`，手动导出通过系统分享面板交给用户保存到 Files、iCloud Drive 或其他 App。照片和视频继续使用现有媒体存储和哈希引用，不把平台路径写入共享训练数据。

## 6. 数据安全与更新

共享训练数据继续使用 `opengym-state.json`；平台状态单独存储：

- `opengym-health.json`：HealthKit 开关、外部 ID 和同步指纹；
- `opengym-rest.json` 或 App Group 状态：Live Activity 标识和最近原生操作；
- `opengym-remote.json`：现有服务器配对信息。

安装更新必须保持：

- Bundle ID 不变；
- Apple Developer Team 不变；
- App Group 标识不变；
- 不先删除旧 App；
- 备份格式向后兼容。

首次真机安装和每次大版本升级前都应导出 JSON 或 ZIP 备份。Mac Docker 服务端可作为第二份数据，但尚未同步的本地变更仍以本地备份为准。

## 7. 测试策略

### 7.1 JavaScript 测试

增加或扩展测试覆盖：

- iOS/Android 平台能力选择；
- HealthKit 数据映射；
- 外部记录去重、更新和删除；
- Live Activity payload；
- Rest Timer 暂停、继续、加减、跳过；
- 原生按钮事件回写 WebView；
- iOS 备份导入导出；
- 媒体 ZIP 导入导出；
- 离线同步恢复。

### 7.2 Swift 测试

为 iOS 原生模块增加测试或可重复的真机检查：

- Live Activity 生命周期；
- App Group 状态读写；
- 通知操作事件；
- HealthKit 授权、拒绝和重试；
- HealthKit 写入失败降级；
- 插件不可用时的安全返回。

### 7.3 iPhone 11 Pro 验收

至少验证：

1. 全新安装和首次启动；
2. 覆盖安装后数据完整；
3. App 被系统杀掉后状态恢复；
4. 手机锁屏时 Rest Timer；
5. Live Activity 全部按钮；
6. HealthKit 授权、同步、去重、删除；
7. 相机、相册、视频和麦克风；
8. JSON/ZIP 备份、Files 和 iCloud Drive；
9. 扫码、打印和分享；
10. Mac Docker 服务端配对；
11. 无网络训练和恢复同步；
12. 签名续期后的覆盖更新。

## 8. 实施阶段

### 阶段 0：构建基线

- 确认 Node、Xcode、CocoaPods、Capacitor 环境；
- 执行 mobile build 和 iOS cap sync；
- 把现有 iOS 壳成功安装到真机；
- 记录 Android/iOS 当前差异。

### 阶段 1：iOS 基础稳定性

- 将部署目标从 15.5 提升到 16.1；
- 固定 Bundle ID、签名 Team 和版本号策略；
- 验证 Filesystem、Share、Notifications、相机和媒体；
- 验证数据恢复与覆盖安装；
- 完善 iOS 备份文档和入口。

### 阶段 2：Live Activity Rest Timer

- 新增 Widget Extension；
- 新增 ActivityKit 数据模型；
- 新增 Capacitor 原生插件；
- 接入 App Group 和 App Intents；
- 完成锁屏、Dynamic Island、后台和恢复测试。

### 阶段 3：HealthKit

- 添加 Capability 和 Entitlements；
- 实现授权和最小权限请求；
- 复用 Android 映射语义；
- 完成幂等、更新、删除和权限失败处理。

### 阶段 4：备份和长期维护

- 完善 `Documents/openGym`；
- 验证 Files、iCloud Drive、分享和大媒体 ZIP；
- 增加迁移保护；
- 编写个人续签、更新和恢复手册。

### 阶段 5：个人稳定版

- 完成真机回归；
- 生成 Release Archive；
- 使用个人 Apple Developer Team 签名；
- 保存 Bundle ID、App Group、签名和恢复信息；
- 记录每年重新签名的操作步骤。

## 9. 完成标准

个人长期可用版完成的条件：

- iPhone 11 Pro 可安装并正常启动；
- 训练数据在覆盖更新后完整保留；
- 无网络时可正常训练；
- JSON/ZIP 备份可导出和恢复；
- Live Activity 可完成完整 Rest Timer 流程；
- HealthKit 可控、可去重、可更新和可删除；
- Mac Docker 服务端配对和同步正常；
- Android 与 iOS 备份互相兼容；
- 不依赖第三方签名服务；
- 续签不要求删除 App；
- 所有限制和降级行为在设置或文档中明确说明。
