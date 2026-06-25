# 记账助手 (Expense Tracker)

纯本地记账 Flutter App，支持手动记账和拍照 OCR 识别票据，数据完全存储在本地 SQLite 数据库，无需联网。

## 功能特性

- **多账本管理**：支持创建多个账本，在设置页面管理账本和分类
- **收支记录**：支持收入/支出记录，自定义金额、日期、备注
- **分类管理**：预设餐饮、交通、购物等常用分类，支持自定义
- **拍照 OCR 识别**：拍照或相册选择票据图片，自动识别金额和商户信息并填充表单
- **统计分析**：按月份/年份查看收支趋势，饼图展示分类占比，柱状图展示收支趋势
- **预算管理**：支持按月/按年设置预算，可按分类设置分类预算
- **CSV 导出**：将记账记录导出为 CSV 文件，方便在 Excel 中查看
- **多平台支持**：Android / Windows / Linux / macOS（iOS 需自行配置 ML Kit）

## 技术栈

| 技术 | 用途 |
|------|------|
| Flutter 3.x | 跨平台 UI 框架 |
| Dart 3.x | 编程语言 |
| SQLite (sqflite) | 本地数据存储 |
| Google ML Kit Text Recognition | 离线 OCR 票据识别 |
| fl_chart | 统计图表（饼图、柱状图） |
| image_picker | 拍照/相册选择 |
| csv | CSV 导出 |
| share_plus | 分享导出文件 |
| permission_handler | 权限管理 |

## 项目结构

```
ocr_app/
├── lib/
│   ├── main.dart                  # 应用入口，底部导航壳
│   ├── database/
│   │   └── database_helper.dart   # SQLite 初始化、表结构、默认数据
│   ├── models/
│   │   ├── account_book.dart      # 账本模型
│   │   ├── budget.dart            # 预算模型
│   │   ├── category.dart          # 分类模型
│   │   └── transaction.dart       # 收支记录模型
│   ├── pages/
│   │   ├── home_page.dart         # 首页：本月收支概览、分类统计、最近记录
│   │   ├── add_transaction_page.dart  # 记账页：手动输入 + 拍照 OCR
│   │   ├── statistics_page.dart   # 统计页：饼图、柱状图、收支趋势
│   │   ├── budget_page.dart       # 预算页：设置和管理预算
│   │   └── settings_page.dart    # 设置页：账本管理、分类管理、CSV 导出
│   ├── services/
│   │   └── ocr_service.dart      # OCR 服务：识别票据金额和商户
│   └── utils/
│       └── app_state.dart         # 全局状态通知（跨页面刷新）
├── android/                       # Android 平台配置
├── windows/                       # Windows 平台配置
├── linux/                         # Linux 平台配置
├── macos/                         # macOS 平台配置
├── pubspec.yaml                   # 依赖配置
└── README.md
```

## 环境要求

- Flutter 3.0+
- Dart 3.0+
- Android SDK 21+（Android）
- JDK 17+（Android 构建）
- Google ML Kit 依赖（OCR 功能，Android 自动配置）

## 快速开始

```bash
# 克隆项目
git clone https://github.com/Leiceco/ocr-miniapp.git
cd ocr_app

# 安装依赖
flutter pub get

# 运行（连接设备或启动模拟器）
flutter run

# 构建 Android APK
flutter build apk --debug

# 构建 Android APK（release）
flutter build apk --release
```

## 使用说明

### 首页
查看当月收支总额、分类支出占比、最近收支记录，支持切换账本。

### 记账
- 手动输入：选择分类、输入金额、日期、备注，点击保存
- 拍照识别：点击相机按钮拍照或从相册选择票据图片，OCR 自动识别金额和商户并填充表单

### 统计
切换月份/年份查看收支趋势，饼图展示各分类支出占比，柱状图展示每日收支情况。

### 预算
设置月度或年度预算，支持为特定分类设置分类预算，实时显示预算使用进度。

### 设置
- 管理账本（新建、重命名、删除）
- 管理分类（新增、编辑、删除收支分类）
- 导出数据为 CSV 文件并分享

## 数据存储

所有数据存储在本地 SQLite 数据库 `expense_tracker.db`，路径因平台而异：
- Android：`/data/data/com.example.ocr_app/databases/`
- Windows：`%LOCALAPPDATA%\ocr_app\`
- 可通过设置页导出 CSV 备份数据

## 开源协议

MIT License

## 作者

Leiceco

> 项目仅供学习交流使用。
