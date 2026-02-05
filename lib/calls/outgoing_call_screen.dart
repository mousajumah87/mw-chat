// lib/calls/outgoing_call_screen.dart
import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'call_screen.dart';
import 'call_signaling_service.dart';

class OutgoingCallScreen extends StatefulWidget {
  const OutgoingCallScreen({
    super.key,
    required this.peerId,
    required this.video,
    required this.pcConfig,
  });

  final String peerId;
  final bool video;
  final Map<String, dynamic> pcConfig; // source of truth for ICE/TURN

  @override
  State<OutgoingCallScreen> createState() => _OutgoingCallScreenState();
}

class _OutgoingCallScreenState extends State<OutgoingCallScreen> {
  AppLocalizations? _l10n;
  bool _booted = false;

  String _t(String fallback, String Function(AppLocalizations l) pick) {
    final l = _l10n;
    return l == null ? fallback : pick(l);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _l10n = AppLocalizations.of(context);

    if (_booted) return;
    _booted = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_goToCallScreen());
    });
  }

  Future<void> _goToCallScreen() async {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) {
      debugPrint('[OutgoingCallScreen] Not signed in');
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_t('Not signed in', (l) => l.outgoingCall_notSignedIn))),
      );
      Navigator.of(context).maybePop();
      return;
    }

    final peer = widget.peerId.trim();
    if (peer.isEmpty || peer == me.uid) {
      debugPrint('[OutgoingCallScreen] Invalid peerId="$peer" me="${me.uid}"');
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_t('Invalid peer', (l) => l.outgoingCall_invalidPeer))),
      );
      Navigator.of(context).maybePop();
      return;
    }

    // ✅ Build stable roomId (same regardless who starts)
    final roomId = CallSignalingService.buildRoomId(me.uid, peer);

    // ✅ Fix: avoid missing l10n getter (use existing / safe message)
    if (roomId.isEmpty) {
      debugPrint('[OutgoingCallScreen] Invalid roomId computed');
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          // Use a generic existing label to avoid adding a new localization key
          content: Text(_t('Invalid room', (l) => l.outgoingCall_invalidPeer)),
        ),
      );
      Navigator.of(context).maybePop();
      return;
    }

    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        settings: const RouteSettings(name: '/call_screen'),
        builder: (_) => CallScreen.outgoing(
          roomId: roomId,
          callerId: me.uid,
          calleeId: peer,
          video: widget.video,
          pcConfig: widget.pcConfig, // ✅ pass config to CallScreen
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.video
        ? _t('Video Call', (l) => l.callLogs_tooltip_videoCall)
        : _t('Voice Call', (l) => l.callLogs_tooltip_voiceCall);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: Text(title),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: const SafeArea(
        child: Center(
          child: CircularProgressIndicator(),
        ),
      ),
    );
  }
}
