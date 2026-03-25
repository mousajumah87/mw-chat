import 'dart:io' show Platform;

import 'package:app_badge_plus/app_badge_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationBadgeService with WidgetsBindingObserver {
  NotificationBadgeService._();
  static final NotificationBadgeService instance = NotificationBadgeService._();

  bool _started = false;
  FlutterLocalNotificationsPlugin? _fln;
  int _lastAppliedBadgeCount = -1;

  bool get _supportsNativeBadge {
    if (kIsWeb) return false;
    return Platform.isAndroid || Platform.isIOS || Platform.isMacOS;
  }

  void start(FlutterLocalNotificationsPlugin fln) {
    if (_started) return;
    _started = true;
    _fln = fln;
    WidgetsBinding.instance.addObserver(this);
  }

  void dispose() {
    if (!_started) return;
    WidgetsBinding.instance.removeObserver(this);
    _started = false;
    _fln = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Intentionally do nothing here.
    // Do NOT blindly clear all badges on resume,
    // because that can fight with real unread state.
  }

  Future<bool> _isBadgeSupported() async {
    if (!_supportsNativeBadge) return false;

    try {
      // Future.sync keeps this safe whether the plugin method is sync or async.
      final supported = await Future.sync(() => AppBadgePlus.isSupported());
      return supported == true;
    } catch (e) {
      debugPrint('⚠️ badge support check failed: $e');
      return false;
    }
  }

  Future<void> _applyBadge(int count) async {
    final safeCount = count < 0 ? 0 : count;

    try {
      // app_badge_plus uses updateBadge(0) to remove the badge.
      await Future.sync(() => AppBadgePlus.updateBadge(safeCount));
      _lastAppliedBadgeCount = safeCount;
    } catch (e) {
      debugPrint('⚠️ applyBadge failed: $e');
    }
  }

  Future<void> clearChatBadgeAndNotifications({
    bool clearSystemNotifications = true,
  }) async {
    if (!_supportsNativeBadge) return;

    if (clearSystemNotifications) {
      try {
        await _fln?.cancelAll();
      } catch (e) {
        debugPrint('⚠️ cancelAll notifications failed: $e');
      }
    }

    final supported = await _isBadgeSupported();
    if (!supported) return;

    if (_lastAppliedBadgeCount == 0) return;
    await _applyBadge(0);
  }

  Future<void> setBadgeCount(int count) async {
    if (!_supportsNativeBadge) return;

    final safeCount = count < 0 ? 0 : count;
    if (_lastAppliedBadgeCount == safeCount) return;

    final supported = await _isBadgeSupported();
    if (!supported) return;

    await _applyBadge(safeCount);
  }
}