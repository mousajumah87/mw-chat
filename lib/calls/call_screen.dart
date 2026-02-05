//lib/calls/call_screen.dart

import 'dart:async';
import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../l10n/app_localizations.dart';
import '../widgets/ui/mw_feedback.dart';
import 'call_signaling_service.dart';

enum CallMode { outgoing, incoming }

class CallScreen extends StatefulWidget {
  final CallMode mode;
  final String roomId;
  final String callerId;
  final String calleeId;

  /// Outgoing: null (created inside)
  /// Incoming: must be provided
  final String? callId;

  final bool video;

  /// ✅ NEW: allow callers (HomeScreen/OutgoingCallScreen) to pass the ICE/TURN config.
  /// If null, CallScreen falls back to its internal default.
  final Map<String, dynamic>? pcConfig;

  const CallScreen.outgoing({
    super.key,
    required this.roomId,
    required this.callerId,
    required this.calleeId,
    this.video = false,
    this.pcConfig,
  })  : mode = CallMode.outgoing,
        callId = null;

  const CallScreen.incoming({
    super.key,
    required this.roomId,
    required this.callerId,
    required this.calleeId,
    required this.callId,
    this.video = false,
    this.pcConfig,
  }) : mode = CallMode.incoming;

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  late final CallSignalingService _sig =
  CallSignalingService(FirebaseFirestore.instance);

  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _statusSub;

  // ✅ Listen to signaling UI state (timer/speaker/mute/connected/status)
  StreamSubscription<CallUiState>? _uiStateSub;

  // ✅ Never read AppLocalizations in initState.
  AppLocalizations? _l10n;

  String _statusLabel = '';

  /// ✅ Firestore is the source of truth.
  /// Keep empty until we receive the first real status from Firestore.
  String _fsStatus = '';

  bool _ended = false;

  /// ✅ This becomes non-null once outgoing call doc is created OR incoming callId is assigned.
  String? _callId;

  /// ✅ If user taps hangup while start/accept is still running,
  /// we queue the hangup and execute it as soon as callId is known.
  bool _hangupRequested = false;

  /// ✅ Track whether we are still doing async start/accept work.
  bool _starting = false;

  /// ✅ Prevent double-dispose (listener -> close -> dispose()).
  bool _disposedMedia = false;

  // ✅ local snapshot of signaling UI state
  CallUiState _ui = CallUiState.initial;

  // iOS CallKit channel (optional end-call sync)
  static const MethodChannel _voipChannel = MethodChannel('mw.voip');

  // ✅ Default ICE config (fallback)
  Map<String, dynamic> get _pcConfig => {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ],
    'sdpSemantics': 'unified-plan',
  };

  @override
  void initState() {
    super.initState();
    _statusLabel = 'Connecting…';
    _boot();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    _l10n = AppLocalizations.of(context);

    if (_statusLabel == 'Connecting…' && _l10n != null) {
      _statusLabel = _l10n!.outgoingCall_connecting;
      if (mounted) setState(() {});
    }
  }

  String _t(String fallback, String Function(AppLocalizations l) pick) {
    final l = _l10n;
    return l == null ? fallback : pick(l);
  }

  Future<void> _boot() async {
    _starting = true;
    try {
      await _initRenderers();
      _attachUiStateListener(); // ✅ start listening before start/accept
      await _start();
    } finally {
      _starting = false;
      if (_hangupRequested && !_ended) {
        unawaited(_endAndClose());
      }
    }
  }

  Future<void> _initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
  }

  void _setUiStatus(String label) {
    if (!mounted) return;
    setState(() => _statusLabel = label);
  }

  bool get _isRingingLike {
    if (_fsStatus.isEmpty) return true;
    return _fsStatus == 'ringing';
  }

  // ✅ Format call duration (mm:ss or hh:mm:ss)
  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);

    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  // ✅ Listen to CallSignalingService.uiStateStream (timer/speaker/mute/connected/status)
  void _attachUiStateListener() {
    _uiStateSub?.cancel();
    _uiStateSub = _sig.uiStateStream.listen((st) {
      if (_ended || !mounted) return;

      setState(() {
        _ui = st;
      });

      // If connected, show the timer in the status line (WhatsApp-like)
      if (st.connected) {
        _setUiStatus(_formatDuration(st.duration));
      }
    });
  }

  Future<void> _start() async {
    // ✅ pick config passed from caller or fallback
    final pcConfig = widget.pcConfig ?? _pcConfig;

    try {
      if (widget.mode == CallMode.outgoing) {
        _setUiStatus(_t('Ringing…', (l) => l.call_status_ringing));

        final id = await _sig.startCall(
          callerId: widget.callerId,
          calleeId: widget.calleeId,
          roomId: widget.roomId,
          video: widget.video,
          pcConfig: pcConfig,
          onLocalStream: (s) => _localRenderer.srcObject = s,
          onRemoteStream: (s) {
            _remoteRenderer.srcObject = s;
            _setUiStatus(_t('In call', (l) => l.call_status_inCall));
          },
        );

        _callId = id;
        _attachStatusListener(id);

        if (_hangupRequested && !_ended) {
          await _endAndClose();
        }
      } else {
        final id = widget.callId!;
        _callId = id;

        _attachStatusListener(id);

        _setUiStatus(_t('Answering…', (l) => l.call_status_answering));

        await _sig.acceptCall(
          callId: id,
          video: widget.video,
          pcConfig: pcConfig,
          onLocalStream: (s) => _localRenderer.srcObject = s,
          onRemoteStream: (s) {
            _remoteRenderer.srcObject = s;
            _setUiStatus(_t('In call', (l) => l.call_status_inCall));
          },
        );

        if (_hangupRequested && !_ended) {
          await _endAndClose();
        }
      }
    } catch (e) {
      debugPrint('[CallScreen] start failed: $e');
      if (!mounted) return;

      final msg = _t(
        'Call failed: ${e.toString()}',
            (l) => l.call_failedWithError(e.toString()),
      );

      await MwFeedback.show(
        context,
        message: msg,
        type: MwFeedbackType.error,
      );

      await _disposeMedia();
      _safePop();
    }
  }

  void _attachStatusListener(String callId) {
    _statusSub?.cancel();

    _statusSub = _sig.listenCallStatus(
      callId,
      onChanged: (status, data) async {
        if (_ended) return;

        _fsStatus = status;

        // If connected, timer owns the label
        void setIfNotConnected(String label) {
          if (!_ui.connected) _setUiStatus(label);
        }

        if (status == 'ringing') {
          setIfNotConnected(_t('Ringing…', (l) => l.call_status_ringing));
          return;
        }

        if (status == 'accepted') {
          setIfNotConnected(_t('In call', (l) => l.call_status_inCall));
          return;
        }

        Future<void> closeWithLabel(String label, Duration d) async {
          _setUiStatus(label);
          await Future<void>.delayed(d);
          await _endAndClose(closeOnly: true);
        }

        if (status == 'declined') {
          await closeWithLabel(
            _t('Declined', (l) => l.call_status_declined),
            const Duration(milliseconds: 600),
          );
          return;
        }

        if (status == 'missed') {
          await closeWithLabel(
            _t('Missed', (l) => l.call_status_missed),
            const Duration(milliseconds: 700),
          );
          return;
        }

        if (status == 'canceled') {
          await closeWithLabel(
            _t('Canceled', (l) => l.call_status_canceled),
            const Duration(milliseconds: 600),
          );
          return;
        }

        if (status == 'busy') {
          await closeWithLabel(
            _t('Busy', (l) => l.call_status_busy),
            const Duration(milliseconds: 700),
          );
          return;
        }

        if (status == 'ended') {
          await closeWithLabel(
            _t('Ended', (l) => l.call_status_ended),
            const Duration(milliseconds: 400),
          );
          return;
        }
      },
    );
  }

  Future<void> _endCallKitIfNeeded() async {
    if (kIsWeb) return;
    if (!Platform.isIOS) return;

    final id = _callId;
    if (id == null || id.isEmpty) return;

    try {
      await _voipChannel.invokeMethod('callkitEndByCallId', {'callId': id});
    } catch (e) {
      debugPrint('[CallScreen] callkitEndByCallId failed: $e');
    }
  }

  Future<void> _endAndClose({bool closeOnly = false}) async {
    if (_ended) return;

    if (_callId == null) {
      _hangupRequested = true;
      _setUiStatus(_t('Canceling…', (l) => l.call_status_canceling));

      if (!_starting) {
        await _disposeMedia();
        await _endCallKitIfNeeded();
        _safePop();
      }
      return;
    }

    _ended = true;
    final id = _callId!;

    try {
      await _statusSub?.cancel();
    } catch (_) {}
    _statusSub = null;

    try {
      await _uiStateSub?.cancel();
    } catch (_) {}
    _uiStateSub = null;

    try {
      if (!closeOnly) {
        final isOutgoing = widget.mode == CallMode.outgoing;

        if (_isRingingLike) {
          if (isOutgoing) {
            await _sig.cancelCall(id);
          } else {
            await _sig.declineCall(id);
          }
        } else {
          await _sig.endCall(id);
        }
      }
    } catch (_) {}

    await _disposeMedia();
    await _endCallKitIfNeeded();
    _safePop();
  }

  Future<void> _disposeMedia() async {
    if (_disposedMedia) return;
    _disposedMedia = true;

    try {
      await _statusSub?.cancel();
    } catch (_) {}
    _statusSub = null;

    try {
      await _uiStateSub?.cancel();
    } catch (_) {}
    _uiStateSub = null;

    try {
      await _sig.dispose();
    } catch (_) {}

    try {
      _localRenderer.srcObject = null;
      _remoteRenderer.srcObject = null;
      await _localRenderer.dispose();
      await _remoteRenderer.dispose();
    } catch (_) {}
  }

  void _safePop() {
    if (!mounted) return;
    Navigator.of(context).maybePop();
  }

  @override
  void dispose() {
    _ended = true;
    unawaited(_disposeMedia());
    super.dispose();
  }

  // ----------------------------
  // Controls (mute / speaker)
  // ----------------------------
  Future<void> _toggleMute() async {
    if (!kIsWeb) HapticFeedback.selectionClick();
    await _sig.toggleMute();
  }

  Future<void> _toggleSpeaker() async {
    if (!kIsWeb) HapticFeedback.selectionClick();
    await _sig.toggleSpeaker();
  }

  @override
  Widget build(BuildContext context) {
    final l = _l10n;

    final title = widget.video
        ? (l?.callLogs_tooltip_videoCall ?? 'Video Call')
        : (l?.callLogs_tooltip_voiceCall ?? 'Voice Call');

    final isConnected = _ui.connected;

    return Scaffold(
      backgroundColor: const Color(0xFF0B0B12),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(title),
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 22),

            // Status / Timer line
            Text(
              _statusLabel,
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),

            const SizedBox(height: 18),

            Expanded(
              child: Center(
                child: Icon(
                  widget.video ? Icons.videocam_rounded : Icons.call_rounded,
                  size: 90,
                  color: Colors.white.withOpacity(0.25),
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedOpacity(
                    opacity: (_fsStatus == 'accepted' || isConnected) ? 1 : 0.45,
                    duration: const Duration(milliseconds: 180),
                    child: IgnorePointer(
                      ignoring: !(_fsStatus == 'accepted' || isConnected),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _RoundToggleButton(
                            label: 'Mute',
                            icon: _ui.muted
                                ? Icons.mic_off_rounded
                                : Icons.mic_rounded,
                            selected: _ui.muted,
                            onTap: _toggleMute,
                          ),
                          _RoundToggleButton(
                            label: 'Speaker',
                            icon: _ui.speakerOn
                                ? Icons.volume_up_rounded
                                : Icons.volume_mute_rounded,
                            selected: _ui.speakerOn,
                            onTap: _toggleSpeaker,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent,
                          shape: const CircleBorder(),
                          padding: const EdgeInsets.all(18),
                        ),
                        onPressed: () {
                          if (!kIsWeb) HapticFeedback.selectionClick();
                          _hangupRequested = true;
                          unawaited(_endAndClose());
                        },
                        child: const Icon(
                          Icons.call_end_rounded,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoundToggleButton extends StatelessWidget {
  const _RoundToggleButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bg = selected
        ? Colors.white.withOpacity(0.18)
        : Colors.white.withOpacity(0.10);

    final fg = selected ? Colors.white : Colors.white.withOpacity(0.85);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(40),
          onTap: onTap,
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: bg,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: fg),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ],
    );
  }
}
