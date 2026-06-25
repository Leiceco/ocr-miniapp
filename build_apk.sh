#!/bin/bash
# Android APK 构建脚本
# SQLITE3_NO_DOWNLOAD=1 禁止 sqlite3 从 GitHub 下载预编译库
# 改由 sqlite3_flutter_libs 提供各平台原生 SQLite 动态库
export SQLITE3_NO_DOWNLOAD=1
flutter build apk "$@"
