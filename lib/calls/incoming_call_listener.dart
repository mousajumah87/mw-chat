//lib/calls/incoming_call_listener.dart

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../main.dart' show rootNavigatorKey, isHandlingCallKitAnswer;
import 'call_screen.dart';
import 'call_signaling_service.dart';
import 'incoming_call_sheet.dart';

class IncomingCallListener extends StatefulWidget {
  const IncomingCallListener({
    super.key,
    required this.child,
    this.ringTimeout = const Duration(seconds: 45),
  });

  final Widget child;
  final Duration ringTimeout;

  @override
  State<IncomingCallListener> createState() => _IncomingCallListenerState();
}

class _IncomingCallListenerState extends State<IncomingCallListener> {
  StreamSubscription<User?>? _authSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _activeSub;

  // ✅ IMPORTANT:
  // Do NOT instantiate FirebaseFirestore.instance (or any Firebase service)
  // in a field initializer, because it can run before Firebase is configured
  // and cause: "[FirebaseCore] No app has been configured yet."
  CallSignalingService? _sig;
  CallSignalingService get _signal =>
      _sig ??= CallSignalingService(FirebaseFirestore.instance);

  bool _showingIncomingSheet = false;

  String? _lastCallIdShown;
  int _lastShownAtMs = 0;

  final Map<String, Timer> _ringTimers = <String, Timer>{};

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _openSheetCallSub;
  BuildContext? _sheetContext;

  bool _onCallScreen = false;

  BuildContext? _rootContext() => rootNavigatorKey.currentContext;

  bool _isTerminal(String s) =>
      s == 'ended' ||
          s == 'declined' ||
          s == 'canceled' ||
          s == 'missed' ||
          s == 'busy';

  String _s(Object? v) => (v ?? '').toString().trim();

  @override
  void initState() {
    super.initState();

    _authSub = FirebaseAuth.instance.idTokenChanges().listen((user) {
      _stopActiveSub();
      if (user == null) return;
      _startActiveSub(user.uid);
    });

    final u = FirebaseAuth.instance.currentUser;
    if (u != null) _startActiveSub(u.uid);
  }

  @override
  void dispose() {
    _stopActiveSub();

    _authSub?.cancel();
    _authSub = null;

    for (final t in _ringTimers.values) {
      t.cancel();
    }
    _ringTimers.clear();

    // ✅ Allow GC; avoid keeping any firebase-backed service around
    _sig = null;

    super.dispose();
  }

  void _stopActiveSub() {
    _activeSub?.cancel();
    _activeSub = null;

    _stopOpenSheetCallWatcher();

    _showingIncomingSheet = false;
    _sheetContext = null;
  }

  Future<void> _clearActiveCallDoc(String me) async {
    try {
      await FirebaseFirestore.instance.collection('active_calls').doc(me).delete();
      debugPrint('[Calls] Cleared active_calls/$me');
    } catch (e) {
      debugPrint('[Calls] clear active_calls failed: $e');
    }
  }

  void _ensureRingTimeoutScheduled({
    required String me,
    required String callId,
  }) {
    if (_ringTimers.containsKey(callId)) return;

    debugPrint(
      '[Calls] schedule ringTimeout callId=$callId in ${widget.ringTimeout.inSeconds}s',
    );

    _ringTimers[callId] = Timer(widget.ringTimeout, () async {
      _ringTimers.remove(callId);

      // ✅ Log current status BEFORE we try to mark missed
      try {
        final snap =
        await FirebaseFirestore.instance.collection('calls').doc(callId).get();
        debugPrint(
          '[Calls] ringTimeout fired callId=$callId currentStatus=${snap.data()?['status']}',
        );
      } catch (_) {}

      await _markMissedIfStillRinging(me: me, callId: callId);
    });
  }

  void _cancelRingTimeout(String callId) {
    final t = _ringTimers.remove(callId);
    t?.cancel();
  }

  Future<void> _markMissedIfStillRinging({
    required String me,
    required String callId,
  }) async {
    try {
      await _signal.markMissedIfRinging(callId);
    } catch (e) {
      debugPrint('[Calls] markMissedIfRinging failed: $e');
    } finally {
      //await _clearActiveCallDoc(me);
    }
  }

  void _stopOpenSheetCallWatcher() {
    _openSheetCallSub?.cancel();
    _openSheetCallSub = null;
  }

  void _closeIncomingSheetIfOpen() {
    final ctx = _sheetContext;
    if (ctx == null) return;

    try {
      Navigator.of(ctx, rootNavigator: true).pop();
    } catch (_) {}

    _sheetContext = null;
  }

  void _startOpenSheetCallWatcher({
    required String me,
    required String callId,
  }) {
    _stopOpenSheetCallWatcher();

    _openSheetCallSub = FirebaseFirestore.instance
        .collection('calls')
        .doc(callId)
        .snapshots()
        .listen((snap) async {
      if (!mounted) return;
      final data = snap.data();
      if (data == null) return;

      final status = (data['status'] ?? '').toString();
      if (status == 'ringing') return;

      debugPrint('[Calls] calls/$callId changed while sheet open -> $status');

      _cancelRingTimeout(callId);
      await _clearActiveCallDoc(me);

      _closeIncomingSheetIfOpen();

      _showingIncomingSheet = false;
    }, onError: (e) {
      debugPrint('[Calls] openSheet calls/$callId listener error: $e');
    });
  }

  void _startActiveSub(String me) {
    final activeRef = FirebaseFirestore.instance.collection('active_calls').doc(me);

    _activeSub = activeRef
        .snapshots(includeMetadataChanges: true)
        .listen((snap) async {
      if (!mounted) return;

      if (!snap.exists) {
        debugPrint('[Calls] active_calls/$me: (none)');
        return;
      }

      final active = snap.data() ?? <String, dynamic>{};

      // ✅ Ignore caller-side outgoing pointer (it has peerId, not calleeId/roomId/etc)
      final status = _s(active['status']);
      if (status == 'outgoing') {
        debugPrint('[Calls] active_calls/$me is outgoing pointer -> ignore');
        return;
      }

      final callId = _s(active['callId']);
      final callerId = _s(active['callerId']);
      final calleeId = _s(active['calleeId']);
      final roomId = _s(active['roomId']);
      final type = _s(active['type']).isEmpty ? 'audio' : _s(active['type']);

      // ✅ best-effort caller name (prefer active_calls fast path)
      final callerNameFromActive = _s(active['callerName']);

      debugPrint(
        '[Calls] active_calls/$me exists callId=$callId caller=$callerId callee=$calleeId room=$roomId',
      );

      if (callId.isEmpty || callerId.isEmpty || calleeId.isEmpty || roomId.isEmpty) {
        debugPrint(
          '[Calls] active_calls/$me missing incoming fields -> ignore (do not clear)',
        );
        return;
      }

      if (calleeId != me) {
        debugPrint('[Calls] active_calls calleeId != me -> clearing');
        await _clearActiveCallDoc(me);
        return;
      }

      // ✅ NEW: If CallKit is already answering from lock screen, do NOT show sheet.
      if (isHandlingCallKitAnswer) {
        debugPrint('[Calls] CallKit answer in progress -> suppress incoming sheet');
        return;
      }

      if (_onCallScreen) {
        debugPrint('[Calls] on CallScreen -> ignore incoming sheet, cleanup pointer');
        _cancelRingTimeout(callId);
        await _clearActiveCallDoc(me);
        return;
      }

      final nowMs = DateTime.now().millisecondsSinceEpoch;
      if (_lastCallIdShown == callId && (nowMs - _lastShownAtMs) < 1200) return;
      if (_showingIncomingSheet) return;

      final callSnap =
      await FirebaseFirestore.instance.collection('calls').doc(callId).get();
      final callData = callSnap.data();
      if (callData == null) {
        debugPrint('[Calls] calls/$callId missing -> clearing active_calls');
        await _clearActiveCallDoc(me);
        return;
      }

      final callStatus = _s(callData['status']);
      debugPrint('[Calls] calls/$callId status=$callStatus');

      if (callStatus != 'ringing') {
        debugPrint('[Calls] Not ringing anymore -> clearing active_calls');
        _cancelRingTimeout(callId);
        await _clearActiveCallDoc(me);
        return;
      }

      // ✅ caller name fallback from call doc
      final callerNameFromCall = _s(callData['callerName']);
      final displayCallerName = callerNameFromActive.isNotEmpty
          ? callerNameFromActive
          : (callerNameFromCall.isNotEmpty ? callerNameFromCall : '');

      _ensureRingTimeoutScheduled(me: me, callId: callId);

      final rootCtx = _rootContext();
      if (rootCtx == null) {
        debugPrint('[Calls] rootNavigatorKey.currentContext is null -> cannot show sheet');
        return;
      }

      _showingIncomingSheet = true;
      _lastCallIdShown = callId;
      _lastShownAtMs = nowMs;

      _startOpenSheetCallWatcher(me: me, callId: callId);

      try {
        await showModalBottomSheet<void>(
          context: rootCtx,
          useRootNavigator: true,
          isDismissible: false,
          enableDrag: false,
          backgroundColor: Colors.transparent,
          builder: (ctx) {
            _sheetContext = ctx;

            return IncomingCallSheet(
              title: displayCallerName,
              subtitle: 'MW Chat',
              type: type,
              onDecline: () async {
                _stopOpenSheetCallWatcher();

                Navigator.of(ctx, rootNavigator: true).pop();
                _sheetContext = null;

                _cancelRingTimeout(callId);

                try {
                  await _signal.declineCall(callId);
                } catch (e) {
                  debugPrint('[Calls] declineCall failed: $e');
                } finally {
                  await _clearActiveCallDoc(me);
                }
              },
              onAccept: () async {
                _stopOpenSheetCallWatcher();

                Navigator.of(ctx, rootNavigator: true).pop();
                _sheetContext = null;

                _cancelRingTimeout(callId);

                await _clearActiveCallDoc(me);

                final navCtx = _rootContext();
                if (navCtx == null) return;

                _onCallScreen = true;

                Navigator.of(navCtx, rootNavigator: true)
                    .push(
                  MaterialPageRoute(
                    settings: const RouteSettings(name: '/call_screen'),
                    builder: (_) => CallScreen.incoming(
                      roomId: roomId,
                      callerId: callerId,
                      calleeId: calleeId,
                      callId: callId,
                      video: type == 'video',
                    ),
                  ),
                )
                    .whenComplete(() {
                  _onCallScreen = false;
                });
              },
            );
          },
        );
      } catch (e) {
        debugPrint('[Calls] showModalBottomSheet failed: $e');
      } finally {
        _stopOpenSheetCallWatcher();
        _showingIncomingSheet = false;
        _sheetContext = null;

        debugPrint('[Calls] incoming sheet closed for callId=$callId');

        try {
          final fresh =
          await FirebaseFirestore.instance.collection('calls').doc(callId).get();
          final s = _s(fresh.data()?['status']);
          if (s.isNotEmpty && s != 'ringing' && _isTerminal(s)) {
            _cancelRingTimeout(callId);
            await _clearActiveCallDoc(me);
          }
        } catch (_) {}
      }
    }, onError: (e) {
      debugPrint('[Calls] active_calls listener error: $e');
      _showingIncomingSheet = false;
      _sheetContext = null;
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
