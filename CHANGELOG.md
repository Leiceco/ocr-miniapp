# Changelog

## [2.0.2] - 2026-06-27

### 🐛 全局修复：`_dependents.isEmpty` 断言崩溃

**问题：** `AppState.notify()` 同步触发所有监听页面的 `_onDataChanged`，当 `notify()` 在对话框弹出/关闭、页面切换等过渡动画中调用时，各页面的 `setState` 可能在 InheritedWidget 停用过程中执行，导致 `framework.dart:6268` 断言失败

**双层修复：**
1. **`AppState.notify()`** 改用 `addPostFrameCallback` 延迟到帧结束后触发，消除"停用中重建"窗口期
2. **全部 5 个页面** 添加 `_disposed` 防御标志位：`settings_page`、`home_page`、`budget_page`、`statistics_page`、`add_transaction_page`

**触发场景：** 创建/删除账本、添加分类、保存记录等操作后弹 SnackBar 期间最容易触发

---

## [2.0.1] - 2026-06-27

### 🐛 Bug 修复

#### 语音回调竞态崩溃（`_dependents.isEmpty` 断言失败）
- **问题：** 在记账页将 `_speech.initialize()` 从懒加载移到 `initState()` 预加载后，语音插件的异步回调（`onStatus` / `onResult`）可能在 Widget 停用后、dispose 前触发，此时 `mounted` 仍为 `true` 但 InheritedWidget 已开始拆解，导致 `setState` 触发 Flutter 框架断言 `_dependents.isEmpty: is not true`
- **修复：** 添加 `_disposed` 标志位，在 `dispose()` 第一行置为 `true`，所有语音回调同时检查 `mounted && !_disposed`，确保回调在 dispose 过程中立即退出
- **影响文件：** `lib/pages/add_transaction_page.dart`

### 🔧 权限补全

- **Android：** 在 `AndroidManifest.xml` 中添加 `RECORD_AUDIO` 权限，修复语音录入功能在 Android 设备上无法启动的问题
- **iOS：** 在 `Info.plist` 中添加 `NSMicrophoneUsageDescription` 和 `NSSpeechRecognitionUsageDescription`，满足 App Store 隐私审核要求

### ⚙️ 构建优化

- **pubspec.yaml：** 添加 `sqlite3` hooks 配置（`source: system`），禁止 sqlite3 构建钩子从 GitHub 下载预编译库，强制使用项目自带的原生 SQLite 动态库，避免国内网络环境下载失败导致构建中断

---

## [2.0.0] - 2026-06-26

### ✨ 新功能

- **🤖 AI 智能记账**：基于 NLP 的账单文本解析，自动从描述中提取金额、类型（收入/支出）和分类
- **🎤 语音录入**：集成 `speech_to_text` 插件，支持中文语音转文字后自动触发智能解析
- **📸 拍照 OCR 识别**：集成 Google ML Kit 文字识别，拍照自动提取金额和商户信息
- **⚠️ 异常检测**：记录保存时自动检测金额、分类异常并弹窗提醒
- **🔔 智能通知**：基于用户活跃时间窗口的定时记账提醒
- **📊 账单推荐**：根据使用频率智能推荐最常用账本
- **📁 Excel 导入导出**：支持账单数据的批量导入导出

### 🔧 技术改进

- Android 启用 core library desugaring 以支持 `flutter_local_notifications`
- sqlite3 构建跳过 GitHub 下载
- 语音清理安全保护（`mounted` 检查）
