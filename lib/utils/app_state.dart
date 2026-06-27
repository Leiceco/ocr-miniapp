import 'package:flutter/material.dart';

/// 轻量级全局状态通知 —— 用于跨页面通知数据变更（新增/修改/删除记录、账本变更等）。
///
/// 用法：
///   AppState.notify();            // 发送通知
///   AppState.addListener(fn);     // 订阅（记得在 dispose 中 removeListener）
///
/// 注意：notify() 使用 addPostFrameCallback 延迟到当前帧结束后触发，
/// 避免 InheritedWidget 停用过程中触发 setState 导致 _dependents.isEmpty 断言失败。
class AppState {
  AppState._();

  static final _notifier = ValueNotifier<int>(0);

  /// 发送一次全局刷新通知（延迟到当前帧结束后）。
  static void notify() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _notifier.value++;
    });
  }

  /// 订阅刷新通知。
  static void addListener(VoidCallback listener) {
    _notifier.addListener(listener);
  }

  /// 取消订阅。
  static void removeListener(VoidCallback listener) {
    _notifier.removeListener(listener);
  }
}
