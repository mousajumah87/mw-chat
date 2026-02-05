// lib/calls/call_signaling_service.dart
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class CallSignalingService {
  CallSignalingService(this._db);

  final FirebaseFirestore _db;

  RTCPeerConnection? _pc;
  MediaStream? _localStream;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _callSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _remoteCandSub;

  bool _hasRemoteDesc = false;

  // Optional: dedup ICE docChanges
  final Set<String> _seenRemoteCandidateDocIds = <String>{};

  String? _activeCallId;
  String? _activeCallerId;
  String? _activeCalleeId;

  // ✅ Disconnected grace timer (prevents false "connection issue" endings)
  Timer? _disconnectTimer;
  void _cancelDisconnectTimer() {
    _disconnectTimer?.cancel();
    _disconnectTimer = null;
  }

  // ----------------------------
  // Status helpers
  // ----------------------------
  static const Set<String> _terminalStatuses = <String>{
    'ended',
    'declined',
    'canceled',
    'missed',
    'busy',
  };

  bool _isTerminalStatus(String status) => _terminalStatuses.contains(status);

  // ----------------------------
  // UI State (timer / speaker / mute)
  // ----------------------------
  final StreamController<CallUiState> _uiStateCtrl =
  StreamController<CallUiState>.broadcast();

  CallUiState _uiState = CallUiState.initial;

  Stream<CallUiState> get uiStateStream => _uiStateCtrl.stream;
  CallUiState get uiState => _uiState;

  Timer? _durationTimer;

  // ✅ Improved: pause/resume duration instead of “start once forever”
  DateTime? _connectedAt; // when current connected segment started
  Duration _accumulated = Duration.zero; // previous connected time

  void _emitUiState(CallUiState next) {
    _uiState = next;
    if (!_uiStateCtrl.isClosed) {
      _uiStateCtrl.add(next);
    }
  }

  void _resetUiState() {
    _pauseDurationTimer(reset: true);
    _emitUiState(CallUiState.initial);
  }

  void _resumeDurationTimer() {
    // if already running, no-op
    if (_durationTimer != null) return;

    _connectedAt ??= DateTime.now();

    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final start = _connectedAt;
      if (start == null) return;

      final now = DateTime.now();
      final d = _accumulated + now.difference(start);

      // only emit duration update (don’t touch other flags)
      _emitUiState(_uiState.copyWith(duration: d));
    });
  }

  void _pauseDurationTimer({bool reset = false}) {
    _durationTimer?.cancel();
    _durationTimer = null;

    final start = _connectedAt;
    if (start != null) {
      _accumulated += DateTime.now().difference(start);
    }
    _connectedAt = null;

    if (reset) {
      _accumulated = Duration.zero;
      _connectedAt = null;
    }
  }

  // ----------------------------
  // Room helpers
  // ----------------------------
  static String buildRoomId(String uid1, String uid2) {
    final a = uid1.trim();
    final b = uid2.trim();
    if (a.isEmpty || b.isEmpty) return '';
    if (a == b) return a;
    return (a.compareTo(b) <= 0) ? '${a}_$b' : '${b}_$a';
  }

  Future<String> startAudioCallToUser({
    required String calleeId,
    required Map<String, dynamic> pcConfig,
    required void Function(MediaStream stream) onLocalStream,
    required void Function(MediaStream stream) onRemoteStream,
  }) async {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) throw StateError('Not signed in');
    final roomId = buildRoomId(me.uid, calleeId);
    if (roomId.isEmpty) throw StateError('Invalid roomId');
    return startCall(
      callerId: me.uid,
      calleeId: calleeId,
      roomId: roomId,
      video: false,
      pcConfig: pcConfig,
      onLocalStream: onLocalStream,
      onRemoteStream: onRemoteStream,
    );
  }

  Future<void> setSpeakerOn(bool on) async {
    if (kIsWeb) {
      // flutter_webrtc speaker routing not supported on web
      _emitUiState(_uiState.copyWith(speakerOn: on));
      return;
    }
    try {
      await Helper.setSpeakerphoneOn(on);
      _emitUiState(_uiState.copyWith(speakerOn: on));
    } catch (e) {
      debugPrint('[CALL] setSpeakerOn failed: $e');
    }
  }


  Future<void> toggleSpeaker() async {
    await setSpeakerOn(!_uiState.speakerOn);
  }

  Future<void> setMuted(bool muted) async {
    try {
      final stream = _localStream;
      if (stream != null) {
        final audioTracks = stream.getAudioTracks();
        for (final t in audioTracks) {
          t.enabled = !muted; // enabled=false => muted
        }
      }
      _emitUiState(_uiState.copyWith(muted: muted));
    } catch (e) {
      debugPrint('[CALL] setMuted failed: $e');
    }
  }

  Future<void> toggleMute() async {
    await setMuted(!_uiState.muted);
  }

  Future<String> startVideoCallToUser({
    required String calleeId,
    required Map<String, dynamic> pcConfig,
    required void Function(MediaStream stream) onLocalStream,
    required void Function(MediaStream stream) onRemoteStream,
  }) async {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) throw StateError('Not signed in');
    final roomId = buildRoomId(me.uid, calleeId);
    if (roomId.isEmpty) throw StateError('Invalid roomId');
    return startCall(
      callerId: me.uid,
      calleeId: calleeId,
      roomId: roomId,
      video: true,
      pcConfig: pcConfig,
      onLocalStream: onLocalStream,
      onRemoteStream: onRemoteStream,
    );
  }

  // ----------------------------
  // Name helpers
  // ----------------------------
  static String _extractDisplayName(Map<String, dynamic>? u) {
    if (u == null) return '';

    String s(Object? v) => (v ?? '').toString().trim();

    final first = s(u['firstName']);
    final last = s(u['lastName']);
    final combined = [first, last].where((x) => x.isNotEmpty).join(' ').trim();
    if (combined.isNotEmpty) return combined;

    final candidates = <String>[
      s(u['displayName']),
      s(u['fullName']),
      s(u['name']),
    ];
    for (final c in candidates) {
      if (c.isNotEmpty) return c;
    }

    final username = s(u['username']);
    if (_looksLikeHumanName(username)) return username;

    final email = s(u['email']);
    final pretty = _prettyNameFromEmail(email);
    if (pretty.isNotEmpty) return pretty;

    return '';
  }

  static bool _looksLikeHumanName(String v) {
    final s = v.trim();
    if (s.isEmpty) return false;
    return s.contains(' ') && RegExp(r'[A-Za-z]').hasMatch(s);
  }

  static String _prettyNameFromEmail(String email) {
    final e = email.trim();
    if (!e.contains('@')) return '';
    final local = e.split('@').first;

    final parts = local
        .split(RegExp(r'[._\\-]+'))
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();

    if (parts.isEmpty) return '';

    String cap(String x) =>
        x.isEmpty ? x : (x[0].toUpperCase() + x.substring(1).toLowerCase());

    return parts.map(cap).join(' ');
  }

  String _authDisplayNameFallback(User? u) {
    if (u == null) return '';

    final dn = (u.displayName ?? '').trim();
    if (dn.isNotEmpty) return dn;

    final email = (u.email ?? '').trim();
    final pretty = _prettyNameFromEmail(email);
    if (pretty.isNotEmpty) return pretty;

    if (email.contains('@')) return email.split('@').first;
    return '';
  }

  Future<String> _fetchUserNameBestEffort(String uid) async {
    final id = uid.trim();
    if (id.isEmpty) return '';
    try {
      final snap = await _db.collection('users').doc(id).get();
      return _extractDisplayName(snap.data());
    } catch (_) {
      return '';
    }
  }

  Future<String> _fetchMyNameBestEffort() async {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) return '';
    final fromDb = await _fetchUserNameBestEffort(me.uid);
    if (fromDb.trim().isNotEmpty) return fromDb.trim();
    return _authDisplayNameFallback(me).trim();
  }

  // ----------------------------
  // Media
  // ----------------------------
  Future<MediaStream> _openUserMedia({required bool video}) async {
    final constraints = <String, dynamic>{
      'audio': true,
      'video': video ? <String, dynamic>{'facingMode': 'user'} : false,
    };
    return navigator.mediaDevices.getUserMedia(constraints);
  }

  Future<RTCPeerConnection> _createPeerConnection({
    required Map<String, dynamic> pcConfig,
    required MediaStream localStream,
    required void Function(MediaStream stream) onRemoteStream,
    required Future<void> Function() onPeerFailed,
  }) async {
    final pc = await createPeerConnection(pcConfig);

    for (final track in localStream.getTracks()) {
      await pc.addTrack(track, localStream);
    }

    pc.onTrack = (RTCTrackEvent event) {
      if (event.streams.isNotEmpty) {
        onRemoteStream(event.streams.first);
      }
    };

    // Older plugin support
    pc.onAddStream = (MediaStream stream) {
      onRemoteStream(stream);
    };

    pc.onConnectionState = (RTCPeerConnectionState s) async {
      debugPrint('[CALL] pc.onConnectionState=$s');
      if (s == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          s == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        _cancelDisconnectTimer();
        _emitUiState(_uiState.copyWith(connected: false));
        _pauseDurationTimer(); // ✅ stop ticking
        await onPeerFailed();
      }
    };

    pc.onIceConnectionState = (RTCIceConnectionState s) async {
      debugPrint('[CALL] pc.onIceConnectionState=$s');

      if (s == RTCIceConnectionState.RTCIceConnectionStateConnected ||
          s == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        _cancelDisconnectTimer();

        // ✅ mark connected + resume timer
        _emitUiState(_uiState.copyWith(connected: true));
        _resumeDurationTimer();
        return;
      }

      if (s == RTCIceConnectionState.RTCIceConnectionStateFailed) {
        _cancelDisconnectTimer();
        _emitUiState(_uiState.copyWith(connected: false));
        _pauseDurationTimer(); // ✅ stop ticking
        await onPeerFailed();
        return;
      }

      if (s == RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
        // show disconnected immediately
        _emitUiState(_uiState.copyWith(connected: false));
        _pauseDurationTimer(); // ✅ stop ticking while disconnected

        _disconnectTimer ??= Timer(const Duration(seconds: 8), () async {
          _disconnectTimer = null;
          debugPrint('[CALL] ice disconnected grace expired -> onPeerFailed()');
          await onPeerFailed();
        });
      }
    };

    return pc;
  }

  Future<void> _resetSession() async {
    _cancelDisconnectTimer();

    // ✅ Stop duration + reset UI
    _resetUiState();

    _hasRemoteDesc = false;
    _seenRemoteCandidateDocIds.clear();

    await _callSub?.cancel();
    await _remoteCandSub?.cancel();
    _callSub = null;
    _remoteCandSub = null;

    try {
      await _pc?.close();
    } catch (_) {}
    _pc = null;

    try {
      await _localStream?.dispose();
    } catch (_) {}
    _localStream = null;

    _activeCallId = null;
    _activeCallerId = null;
    _activeCalleeId = null;
  }

  Future<void> _clearActiveCallsBestEffort({
    String? callerId,
    String? calleeId,
  }) async {
    try {
      if (callerId != null && callerId.isNotEmpty) {
        await _db.collection('active_calls').doc(callerId).delete();
      }
    } catch (_) {}

    try {
      if (calleeId != null && calleeId.isNotEmpty) {
        await _db.collection('active_calls').doc(calleeId).delete();
      }
    } catch (_) {}
  }

  // ----------------------------
  // Missed-calls UI helpers
  // ----------------------------
  Future<void> markCallLogRead({required String callId}) async {
    final me = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (me.isEmpty) return;

    final ref =
    _db.collection('users').doc(me).collection('call_logs').doc(callId);

    try {
      await ref.set(<String, dynamic>{
        'isRead': true,
        'readAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[Calls] markCallLogRead failed: $e');
    }
  }

  // ----------------------------
  // Caller flow
  // ----------------------------
  Future<String> startCall({
    required String callerId,
    required String calleeId,
    required String roomId,
    required bool video,
    required Map<String, dynamic> pcConfig,
    required void Function(MediaStream stream) onLocalStream,
    required void Function(MediaStream stream) onRemoteStream,
  }) async {
    final u = FirebaseAuth.instance.currentUser;
    debugPrint('[AUTH] uid=${u?.uid} email=${u?.email}');
    if (u == null) throw StateError('Not signed in');
    if (u.uid != callerId) {
      throw StateError('callerId mismatch: param=$callerId auth=${u.uid}');
    }
    if (calleeId.isEmpty || calleeId == callerId) {
      throw StateError('Invalid calleeId');
    }
    if (roomId.isEmpty) {
      throw StateError('Invalid roomId');
    }

    // Busy check
    try {
      final activeSnap = await _db.collection('active_calls').doc(calleeId).get();
      final active = activeSnap.data();
      if (activeSnap.exists && active != null) {
        final existingCallId = (active['callId'] ?? '').toString();
        final st = (active['status'] ?? '').toString();
        if (existingCallId.isNotEmpty &&
            st.isNotEmpty &&
            !_terminalStatuses.contains(st)) {
          throw StateError('User is busy');
        }
      }
    } catch (e) {
      if (e is StateError && e.message == 'User is busy') rethrow;
    }

    await _resetSession();

    final callRef = _db.collection('calls').doc();
    _activeCallId = callRef.id;
    _activeCallerId = callerId;
    _activeCalleeId = calleeId;

    final callerName = (await _fetchMyNameBestEffort()).trim();
    final calleeName = (await _fetchUserNameBestEffort(calleeId)).trim();

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final type = video ? 'video' : 'audio';

    await callRef.set(<String, dynamic>{
      'callerId': callerId,
      'calleeId': calleeId,
      'roomId': roomId,
      'type': type,
      'status': 'ringing',
      'createdAt': FieldValue.serverTimestamp(),
      'createdAtMs': nowMs,
      'updatedAt': FieldValue.serverTimestamp(),
      'logWritten': false,
      'callerName': callerName,
      'calleeName': calleeName,
      'notify': true,
      'pushSentAt': null,
    });

    await _db.collection('active_calls').doc(calleeId).set(<String, dynamic>{
      'callId': callRef.id,
      'callerId': callerId,
      'calleeId': calleeId,
      'roomId': roomId,
      'type': type,
      'status': 'ringing',
      'createdAt': FieldValue.serverTimestamp(),
      'createdAtMs': nowMs,
      'callerName': callerName,
      'calleeName': calleeName,
    }, SetOptions(merge: true));

    await _db.collection('active_calls').doc(callerId).set(<String, dynamic>{
      'callId': callRef.id,
      'peerId': calleeId,
      'status': 'outgoing',
      'createdAtMs': nowMs,
    }, SetOptions(merge: true));

    debugPrint(
      '[CALL] created callId=${callRef.id} caller=$callerId callee=$calleeId roomId=$roomId',
    );

    _localStream = await _openUserMedia(video: video);
    onLocalStream(_localStream!);

    _pc = await _createPeerConnection(
      pcConfig: pcConfig,
      localStream: _localStream!,
      onRemoteStream: onRemoteStream,
      onPeerFailed: () async {
        final id = _activeCallId;
        if (id == null) {
          await _resetSession();
          return;
        }
        final status = await _getCallStatusBestEffort(id);
        if (status == 'ringing') {
          await cancelCall(id);
        } else {
          await endCall(id);
        }
      },
    );

    final pc = _pc!;
    final callerCandidates = callRef.collection('callerCandidates');

    pc.onIceCandidate = (RTCIceCandidate c) {
      final cand = c.candidate;
      if (cand == null || cand.isEmpty) return;

      final data = <String, dynamic>{
        'candidate': cand,
        if (c.sdpMid != null) 'sdpMid': c.sdpMid,
        if (c.sdpMLineIndex != null) 'sdpMLineIndex': c.sdpMLineIndex,
      };

      callerCandidates.add(data);
    };

    final offer = await pc.createOffer({
      'offerToReceiveAudio': 1,
      'offerToReceiveVideo': video ? 1 : 0,
    });
    await pc.setLocalDescription(offer);

    await callRef.update(<String, dynamic>{
      'status': 'ringing',
      'offer': {'type': offer.type, 'sdp': offer.sdp},
      'updatedAt': FieldValue.serverTimestamp(),
    });

    _callSub = callRef.snapshots().listen((snap) async {
      final data = snap.data();
      if (data == null) return;

      final status = (data['status'] ?? '').toString();
      _emitUiState(_uiState.copyWith(status: status));

      if (_isTerminalStatus(status)) {
        await _clearActiveCallsBestEffort(
          callerId: _activeCallerId,
          calleeId: _activeCalleeId,
        );
        await _resetSession();
        return;
      }

      final ansRaw = data['answer'];
      if (ansRaw is! Map) return;

      final pc = _pc;
      if (pc == null) return;

      if (!_hasRemoteDesc) {
        final sdp = (ansRaw['sdp'] ?? '').toString();
        final type = (ansRaw['type'] ?? '').toString();
        if (sdp.isEmpty || type.isEmpty) return;

        try {
          await pc.setRemoteDescription(RTCSessionDescription(sdp, type));
          _hasRemoteDesc = true;
        } catch (e) {
          debugPrint('[CALL] setRemoteDescription(answer) failed: $e');
        }
      }
    });

    _remoteCandSub =
        callRef.collection('calleeCandidates').snapshots().listen((qs) async {
          final pc = _pc;
          if (pc == null) return;

          for (final ch in qs.docChanges) {
            if (ch.type != DocumentChangeType.added) continue;
            if (_seenRemoteCandidateDocIds.contains(ch.doc.id)) continue;
            _seenRemoteCandidateDocIds.add(ch.doc.id);

            final d = ch.doc.data();
            if (d == null) continue;

            final cand = (d['candidate'] ?? '').toString();
            if (cand.isEmpty) continue;

            final sdpMid = d['sdpMid']?.toString();
            final idxRaw = d['sdpMLineIndex'];
            final sdpMLineIndex =
            (idxRaw is int) ? idxRaw : (idxRaw is num) ? idxRaw.toInt() : null;

            try {
              await pc.addCandidate(RTCIceCandidate(cand, sdpMid, sdpMLineIndex));
            } catch (e) {
              debugPrint('[CALL] addCandidate(callee) failed: $e');
            }
          }
        });

    return callRef.id;
  }

  Future<String> _getCallStatusBestEffort(String callId) async {
    try {
      final snap = await _db.collection('calls').doc(callId).get();
      return (snap.data()?['status'] ?? '').toString();
    } catch (_) {
      return '';
    }
  }

  // ----------------------------
  // Callee flow
  // ----------------------------
  Future<void> acceptCall({
    required String callId,
    required bool video,
    required Map<String, dynamic> pcConfig,
    required void Function(MediaStream stream) onLocalStream,
    required void Function(MediaStream stream) onRemoteStream,
  }) async {
    await _resetSession();

    final callRef = _db.collection('calls').doc(callId);

    final snap = await callRef.get();
    final data = snap.data();
    if (data == null) throw StateError('Call not found');

    final callerId = (data['callerId'] ?? '').toString();
    final calleeId = (data['calleeId'] ?? '').toString();
    _activeCallId = callId;
    _activeCallerId = callerId;
    _activeCalleeId = calleeId;

    final status = (data['status'] ?? '').toString();
    if (status != 'ringing') {
      throw StateError('Call not joinable (status=$status)');
    }

    final offerRaw = data['offer'];
    if (offerRaw is! Map) throw StateError('Offer missing');

    final offerSdp = (offerRaw['sdp'] ?? '').toString();
    final offerType = (offerRaw['type'] ?? '').toString();
    if (offerSdp.isEmpty || offerType.isEmpty) throw StateError('Offer invalid');

    final myName = (await _fetchMyNameBestEffort()).trim();
    final existingCalleeName = (data['calleeName'] ?? '').toString().trim();
    if (existingCalleeName.isEmpty && myName.isNotEmpty) {
      try {
        await callRef.update({
          'calleeName': myName,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } catch (_) {}
    }

    _localStream = await _openUserMedia(video: video);
    onLocalStream(_localStream!);

    _pc = await _createPeerConnection(
      pcConfig: pcConfig,
      localStream: _localStream!,
      onRemoteStream: onRemoteStream,
      onPeerFailed: () async {
        final id = _activeCallId;
        if (id == null) {
          await _resetSession();
          return;
        }
        await endCall(id);
      },
    );

    final pc = _pc!;
    final calleeCandidates = callRef.collection('calleeCandidates');

    pc.onIceCandidate = (RTCIceCandidate c) {
      final cand = c.candidate;
      if (cand == null || cand.isEmpty) return;

      final data = <String, dynamic>{
        'candidate': cand,
        if (c.sdpMid != null) 'sdpMid': c.sdpMid,
        if (c.sdpMLineIndex != null) 'sdpMLineIndex': c.sdpMLineIndex,
      };

      calleeCandidates.add(data);
    };

    await pc.setRemoteDescription(RTCSessionDescription(offerSdp, offerType));
    _hasRemoteDesc = true;

    final answer = await pc.createAnswer({
      'offerToReceiveAudio': 1,
      'offerToReceiveVideo': video ? 1 : 0,
    });
    await pc.setLocalDescription(answer);

    await callRef.update({
      'status': 'accepted',
      'answeredAt': FieldValue.serverTimestamp(),
      'answer': {'type': answer.type, 'sdp': answer.sdp},
      'updatedAt': FieldValue.serverTimestamp(),
    });

    if (calleeId.isNotEmpty) {
      await _db.collection('active_calls').doc(calleeId).set({
        'status': 'accepted',
      }, SetOptions(merge: true));
    }

    _remoteCandSub =
        callRef.collection('callerCandidates').snapshots().listen((qs) async {
          final pc = _pc;
          if (pc == null) return;

          for (final ch in qs.docChanges) {
            if (ch.type != DocumentChangeType.added) continue;
            if (_seenRemoteCandidateDocIds.contains(ch.doc.id)) continue;
            _seenRemoteCandidateDocIds.add(ch.doc.id);

            final d = ch.doc.data();
            if (d == null) continue;

            final cand = (d['candidate'] ?? '').toString();
            if (cand.isEmpty) continue;

            final sdpMid = d['sdpMid']?.toString();
            final idxRaw = d['sdpMLineIndex'];
            final sdpMLineIndex =
            (idxRaw is int) ? idxRaw : (idxRaw is num) ? idxRaw.toInt() : null;

            try {
              await pc.addCandidate(RTCIceCandidate(cand, sdpMid, sdpMLineIndex));
            } catch (e) {
              debugPrint('[CALL] addCandidate(caller) failed: $e');
            }
          }
        });

    _callSub = callRef.snapshots().listen((snap) async {
      final data = snap.data();
      if (data == null) return;

      final s = (data['status'] ?? '').toString();
      _emitUiState(_uiState.copyWith(status: s));

      if (_isTerminalStatus(s)) {
        await _clearActiveCallsBestEffort(
          callerId: _activeCallerId,
          calleeId: _activeCalleeId,
        );
        await _resetSession();
      }
    });
  }

  // ----------------------------
  // End / cleanup
  // ----------------------------
  Future<void> endCall(String callId) async {
    String callerId = '';
    String calleeId = '';

    try {
      final snap = await _db.collection('calls').doc(callId).get();
      final data = snap.data();
      if (data != null) {
        callerId = (data['callerId'] ?? '').toString();
        calleeId = (data['calleeId'] ?? '').toString();
      }
    } catch (_) {}

    await _finalizeCallOnce(
      callId: callId,
      newStatus: 'ended',
      extraFields: {'endedAt': FieldValue.serverTimestamp()},
      requireCurrentStatus: null,
    );

    await _clearActiveCallsBestEffort(
      callerId: callerId.isNotEmpty ? callerId : _activeCallerId,
      calleeId: calleeId.isNotEmpty ? calleeId : _activeCalleeId,
    );

    await _resetSession();
  }

  Future<void> cancelCall(String callId) async {
    String callerId = '';
    String calleeId = '';

    try {
      final snap = await _db.collection('calls').doc(callId).get();
      final data = snap.data();
      if (data != null) {
        callerId = (data['callerId'] ?? '').toString();
        calleeId = (data['calleeId'] ?? '').toString();
      }
    } catch (_) {}

    await _finalizeCallOnce(
      callId: callId,
      newStatus: 'canceled',
      extraFields: {'canceledAt': FieldValue.serverTimestamp()},
      requireCurrentStatus: 'ringing',
    );

    await _clearActiveCallsBestEffort(
      callerId: callerId.isNotEmpty ? callerId : _activeCallerId,
      calleeId: calleeId.isNotEmpty ? calleeId : _activeCalleeId,
    );

    await _resetSession();
  }

  Future<void> declineCall(String callId) async {
    String callerId = '';
    String calleeId = '';

    try {
      final snap = await _db.collection('calls').doc(callId).get();
      final data = snap.data();
      if (data != null) {
        callerId = (data['callerId'] ?? '').toString();
        calleeId = (data['calleeId'] ?? '').toString();
      }
    } catch (_) {}

    await _finalizeCallOnce(
      callId: callId,
      newStatus: 'declined',
      extraFields: {'declinedAt': FieldValue.serverTimestamp()},
      requireCurrentStatus: 'ringing',
    );

    await _clearActiveCallsBestEffort(
      callerId: callerId.isNotEmpty ? callerId : _activeCallerId,
      calleeId: calleeId.isNotEmpty ? calleeId : _activeCalleeId,
    );

    await _resetSession();
  }

  Future<void> markMissedIfRinging(String callId) async {
    String callerId = '';
    String calleeId = '';

    try {
      final snap = await _db.collection('calls').doc(callId).get();
      final data = snap.data();
      if (data != null) {
        callerId = (data['callerId'] ?? '').toString();
        calleeId = (data['calleeId'] ?? '').toString();
      }
    } catch (_) {}

    await _finalizeCallOnce(
      callId: callId,
      newStatus: 'missed',
      extraFields: {'missedAt': FieldValue.serverTimestamp()},
      requireCurrentStatus: 'ringing',
    );

    await _clearActiveCallsBestEffort(
      callerId: callerId.isNotEmpty ? callerId : _activeCallerId,
      calleeId: calleeId.isNotEmpty ? calleeId : _activeCalleeId,
    );

    await _resetSession();
  }

  Future<void> dispose() async {
    await _resetSession();
    await _uiStateCtrl.close();
  }

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>> listenCallStatus(
      String callId, {
        required void Function(String status, Map<String, dynamic> data) onChanged,
      }) {
    return _db.collection('calls').doc(callId).snapshots().listen((snap) {
      final data = snap.data();
      if (data == null) return;

      final status = (data['status'] ?? '').toString();
      if (status.isEmpty) return;

      onChanged(status, data);
    });
  }

  // ----------------------------
  // Finalize: write logs ONCE
  // ----------------------------
  Future<void> _finalizeCallOnce({
    required String callId,
    required String newStatus,
    Map<String, dynamic>? extraFields,
    required String? requireCurrentStatus,
  }) async {
    final callRef = _db.collection('calls').doc(callId);

    try {
      await _db.runTransaction((tx) async {
        final snap = await tx.get(callRef);
        final data = snap.data();
        if (data == null) return;

        final currentStatus = (data['status'] ?? '').toString();
        final logWritten = (data['logWritten'] == true);

        if (requireCurrentStatus != null &&
            currentStatus != requireCurrentStatus) {
          return;
        }

        final roomId = (data['roomId'] ?? '').toString();
        final callerId = (data['callerId'] ?? '').toString();
        final calleeId = (data['calleeId'] ?? '').toString();
        final type = (data['type'] ?? 'audio').toString();

        if (_isTerminalStatus(currentStatus) && logWritten) return;

        if (_isTerminalStatus(currentStatus) && currentStatus != newStatus) {
          if (!logWritten) {
            tx.update(callRef, <String, dynamic>{
              'updatedAt': FieldValue.serverTimestamp(),
              'logWritten': true,
            });
          }
          return;
        }

        final callerName = (data['callerName'] ?? '').toString().trim();
        final calleeName = (data['calleeName'] ?? '').toString().trim();

        tx.update(callRef, <String, dynamic>{
          'status': newStatus,
          'updatedAt': FieldValue.serverTimestamp(),
          if (extraFields != null) ...extraFields,
          if (!logWritten) 'logWritten': true,
        });

        if (!logWritten) {
          final createdAtMsRaw = data['createdAtMs'];
          final createdAtMs = (createdAtMsRaw is int)
              ? createdAtMsRaw
              : (createdAtMsRaw is num)
              ? createdAtMsRaw.toInt()
              : DateTime.now().millisecondsSinceEpoch;

          if (roomId.isNotEmpty) {
            final msgRef = _db
                .collection('privateChats')
                .doc(roomId)
                .collection('messages')
                .doc();

            tx.set(msgRef, <String, dynamic>{
              'type': 'call',
              'callId': callId,
              'callType': type,
              'result': newStatus,
              'callerId': callerId,
              'calleeId': calleeId,
              'createdAt': FieldValue.serverTimestamp(),
              'createdAtMs': createdAtMs,
            });
          }

          void writeCallLogForUser({
            required String userId,
            required String direction,
          }) {
            if (userId.isEmpty) return;

            final logRef = _db
                .collection('users')
                .doc(userId)
                .collection('call_logs')
                .doc(callId);

            String resultForUser = newStatus;
            if (direction == 'incoming' && newStatus == 'canceled') {
              resultForUser = 'missed';
            }

            final unreadForThisUser =
                (direction == 'incoming') && (resultForUser == 'missed');

            final peerId = direction == 'incoming' ? callerId : calleeId;
            final rawPeerName =
            direction == 'incoming' ? callerName : calleeName;

            tx.set(logRef, <String, dynamic>{
              'callId': callId,
              'roomId': roomId,
              'callerId': callerId,
              'calleeId': calleeId,
              'callerName': callerName,
              'calleeName': calleeName,
              'peerId': peerId,
              'peerName': rawPeerName,
              'type': type,
              'result': resultForUser,
              'direction': direction,
              'isRead': !unreadForThisUser,
              'createdAt': FieldValue.serverTimestamp(),
              'createdAtMs': createdAtMs,
              'updatedAt': FieldValue.serverTimestamp(),
            });
          }

          writeCallLogForUser(userId: callerId, direction: 'outgoing');
          writeCallLogForUser(userId: calleeId, direction: 'incoming');

          if (kDebugMode) {
            debugPrint(
              '[Calls] names from call doc callerName="$callerName" calleeName="$calleeName"',
            );
          }
        }
      });
    } catch (e) {
      debugPrint('[Calls] finalizeCallOnce failed: $e');
      try {
        await callRef.update({
          'status': newStatus,
          'updatedAt': FieldValue.serverTimestamp(),
          if (extraFields != null) ...extraFields,
        });
      } catch (_) {}
    }
  }
}

class CallUiState {
  final String status; // ringing, accepted, ended, etc.
  final bool connected; // true when ICE connected/completed
  final bool speakerOn;
  final bool muted;
  final Duration duration; // call duration once connected

  const CallUiState({
    required this.status,
    required this.connected,
    required this.speakerOn,
    required this.muted,
    required this.duration,
  });

  CallUiState copyWith({
    String? status,
    bool? connected,
    bool? speakerOn,
    bool? muted,
    Duration? duration,
  }) {
    return CallUiState(
      status: status ?? this.status,
      connected: connected ?? this.connected,
      speakerOn: speakerOn ?? this.speakerOn,
      muted: muted ?? this.muted,
      duration: duration ?? this.duration,
    );
  }

  static const initial = CallUiState(
    status: '',
    connected: false,
    speakerOn: false,
    muted: false,
    duration: Duration.zero,
  );
}
