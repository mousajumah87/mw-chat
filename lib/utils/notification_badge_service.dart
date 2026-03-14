import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app_badger/flutter_app_badger.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationBadgeService with WidgetsBindingObserver {
  NotificationBadgeService._();
  static final NotificationBadgeService instance = NotificationBadgeService._();

  bool _started = false;
  FlutterLocalNotificationsPlugin? _fln;
  int _lastAppliedBadgeCount = -1;

  bool get _supportsNativeBadge {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
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
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Do NOT blindly clear all badges on resume.
    // That was causing state fights and hiding real unread logic.
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

    try {
      final supported = await FlutterAppBadger.isAppBadgeSupported();
      if (!supported) return;

      FlutterAppBadger.removeBadge();
      _lastAppliedBadgeCount = 0;
    } catch (e) {
      debugPrint('⚠️ removeBadge failed: $e');
    }
  }

  Future<void> setBadgeCount(int count) async {
    if (!_supportsNativeBadge) return;

    final safeCount = count < 0 ? 0 : count;
    if (_lastAppliedBadgeCount == safeCount) return;

    try {
      final supported = await FlutterAppBadger.isAppBadgeSupported();
      if (!supported) return;

      if (safeCount <= 0) {
        FlutterAppBadger.removeBadge();
      } else {
        FlutterAppBadger.updateBadgeCount(safeCount);
      }

      _lastAppliedBadgeCount = safeCount;
    } catch (e) {
      debugPrint('⚠️ setBadgeCount failed: $e');
    }
  }
}