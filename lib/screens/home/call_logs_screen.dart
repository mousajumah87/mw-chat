// lib/screens/home/call_logs_screen.dart
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../widgets/ui/mw_background.dart';

enum _CallsFilter { all, missed, incoming, outgoing }

/// Callback used by CallLogsScreen to start a call.
/// Implement this in the parent using your CallSignalingService / navigation logic.
typedef StartCallFromLogs = Future<void> Function({
required String peerId,
required bool video,
});

typedef OpenChatFromLogs = void Function({
required String peerId,
required String displayName,
});

class CallLogsScreen extends StatefulWidget {
  final OpenChatFromLogs? onOpenChat;

  const CallLogsScreen({
    super.key,
    this.onStartCall,
    this.onOpenChat,
    this.enableVideoButton = true,
  });

  /// Provide this to actually start the call from call logs.
  /// If null: call buttons will still render but disabled (so UI is consistent).
  final StartCallFromLogs? onStartCall;

  /// If true and onStartCall is provided, show video icon too.
  /// If you want only voice calls from this screen, set false.
  final bool enableVideoButton;

  @override
  State<CallLogsScreen> createState() => _CallLogsScreenState();
}

class _CallLogsScreenState extends State<CallLogsScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  // ✅ Names: stable cache + avoid flicker
  final Map<String, String> _nameCache = <String, String>{}; // uid -> name
  final Set<String> _inflight = <String>{}; // uid(s) being fetched
  final ValueNotifier<int> _nameRev = ValueNotifier<int>(0);

  _CallsFilter _filter = _CallsFilter.all;

  bool _autoMarkRan = false;
  Timer? _autoMarkDebounce;
  bool _isClearing = false;

  // ✅ Streams cached per filter
  final Map<_CallsFilter, Stream<QuerySnapshot<Map<String, dynamic>>>> _streamCache =
  <_CallsFilter, Stream<QuerySnapshot<Map<String, dynamic>>>>{};

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _missedSub;
  DateTime _lastDebugPrint = DateTime.fromMillisecondsSinceEpoch(0);

  // ✅ Avoid spamming denied writes (peer backfill)
  final Set<String> _denyBackfill = <String>{}; // docId (callId)

  // ✅ NEW: avoid repeated backfill attempts on rebuilds (per session)
  final Set<String> _peerIdBackfilled = <String>{}; // docId
  final Set<String> _peerNameBackfilled = <String>{}; // docId

  // Results written by CallSignalingService for call_logs
  static const String _rEnded = 'ended';
  static const String _rDeclined = 'declined';
  static const String _rCanceled = 'canceled';
  static const String _rMissed = 'missed';
  static const String _rBusy = 'busy';

  AppLocalizations get _l10n => AppLocalizations.of(context)!;

  Query<Map<String, dynamic>> _base(String uid) => FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .collection('call_logs');

  Query<Map<String, dynamic>> _queryFor(String uid, _CallsFilter f) {
    final base = _base(uid);

    switch (f) {
      case _CallsFilter.all:
        return base.orderBy('createdAtMs', descending: true).limit(100);

      case _CallsFilter.missed:
        return base
            .where('direction', isEqualTo: 'incoming')
            .where('result', isEqualTo: _rMissed)
            .orderBy('createdAtMs', descending: true)
            .limit(100);

      case _CallsFilter.incoming:
      // ✅ FIX: Incoming should include ALL incoming results (including missed)
        return base
            .where('direction', isEqualTo: 'incoming')
            .where('result', whereIn: const [_rEnded, _rDeclined, _rBusy, _rMissed])
            .orderBy('createdAtMs', descending: true)
            .limit(100);

      case _CallsFilter.outgoing:
        return base
            .where('direction', isEqualTo: 'outgoing')
            .where(
          'result',
          whereIn: const [_rEnded, _rCanceled, _rDeclined, _rMissed, _rBusy],
        )
            .orderBy('createdAtMs', descending: true)
            .limit(100);
    }
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _streamFor(
      String uid,
      _CallsFilter f,
      ) {
    return _streamCache.putIfAbsent(
      f,
          () => _queryFor(uid, f).snapshots(includeMetadataChanges: false),
    );
  }

  bool _looksLikeIndexError(Object err) {
    final s = err.toString().toLowerCase();
    return s.contains('failed-precondition') ||
        s.contains('requires an index') ||
        s.contains('index');
  }

  bool _isPermissionDenied(Object e) {
    final s = e.toString().toLowerCase();
    return s.contains('permission-denied') ||
        s.contains('missing or insufficient permissions');
  }

  // ----------------------------
  // PeerId resolution (IMPORTANT for old logs)
  // ----------------------------
  String _resolvePeerIdFromLog(Map<String, dynamic> d, String myUid) {
    String t(Object? v) => (v ?? '').toString().trim();

    final explicitPeerId = t(d['peerId']);
    if (explicitPeerId.isNotEmpty && explicitPeerId != myUid) {
      return explicitPeerId;
    }

    final direction = t(d['direction']);
    final callerId = t(d['callerId']);
    final calleeId = t(d['calleeId']);

    String derived = '';
    if (direction == 'incoming') {
      derived = callerId;
    } else if (direction == 'outgoing') {
      derived = calleeId;
    }

    // If derived accidentally equals me, try the other side.
    if (derived == myUid) {
      if (callerId.isNotEmpty && callerId != myUid) derived = callerId;
      if (calleeId.isNotEmpty && calleeId != myUid) derived = calleeId;
    }

    return derived.trim();
  }

  Future<void> _backfillPeerIdBestEffort({
    required DocumentReference<Map<String, dynamic>> ref,
    required Map<String, dynamic> currentData,
    required String myUid,
    required String resolvedPeerId,
  }) async {
    final docId = ref.id;
    if (_denyBackfill.contains(docId)) return;

    final peerId = resolvedPeerId.trim();
    if (peerId.isEmpty) return;

    String t(Object? v) => (v ?? '').toString().trim();
    final existing = t(currentData['peerId']);

    // ✅ Only backfill when field is missing/blank
    if (existing.isNotEmpty) return;

    try {
      await ref.set(
        {
          'peerId': peerId,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } catch (e) {
      debugPrint('[CallLogs] backfill peerId failed: $e');
      if (_isPermissionDenied(e)) {
        _denyBackfill.add(docId);
      }
    }
  }

  // ----------------------------
  // Read helpers
  // ----------------------------
  Future<void> _markAllAsReadBestEffort(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
      ) async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) return;

    const maxToMark = 120;
    final batch = FirebaseFirestore.instance.batch();
    var changed = 0;

    for (final d in docs) {
      if (changed >= maxToMark) break;

      final data = d.data();
      final isRead = data['isRead'] == true;
      final isReadMissing = !data.containsKey('isRead');
      if (isRead && !isReadMissing) continue;

      batch.set(
        d.reference,
        {
          'isRead': true,
          'readAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      changed++;
    }

    if (changed == 0) return;

    try {
      await batch.commit();
      if (kDebugMode) debugPrint('[CallLogs] auto-marked $changed docs as read');
    } catch (e) {
      debugPrint('[CallLogs] markAll commit failed (best-effort): $e');
    }
  }

  Future<void> _markOneAsReadBestEffort(
      DocumentReference<Map<String, dynamic>> ref,
      Map<String, dynamic> currentData,
      ) async {
    try {
      final isRead = currentData['isRead'] == true;
      final isReadMissing = !currentData.containsKey('isRead');
      if (isRead && !isReadMissing) return;

      await ref.set(
        {
          'isRead': true,
          'readAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } catch (e) {
      debugPrint('[CallLogs] markOne failed: $e');
    }
  }

  // ----------------------------
  // Name resolution (stable + consistent across incoming/outgoing)
  // ----------------------------

  String _normName(String v) {
    return v.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  }

  bool _looksLikeEmailLocalPart(String v) {
    final s = v.trim();
    if (s.isEmpty) return false;
    if (s.contains(' ')) return false;
    if (!RegExp(r'^[a-z0-9._-]+$').hasMatch(s)) return false;
    return s.contains('.') || s.contains('_') || s.contains('-');
  }

  bool _isBadNameCandidate({
    required String name,
    required String peerId,
  }) {
    final n = name.trim();
    if (n.isEmpty) return true;
    if (peerId.trim().isNotEmpty && n == peerId.trim()) return true;
    if (_looksLikeEmailLocalPart(n)) return true;
    if (n.length >= 22 && !n.contains(' ')) return true;
    return false;
  }

  bool _shouldUpgradeName({
    required String existing,
    required String candidate,
    required String peerId,
  }) {
    final ex = existing.trim();
    final ca = candidate.trim();
    if (ca.isEmpty) return false;

    if (ex.isEmpty) return true;
    if (_isBadNameCandidate(name: ex, peerId: peerId)) return true;

    if (_normName(ex) == _normName(ca) && ex != ca) return true;
    if (ca.length > ex.length + 2) return true;

    return false;
  }

  Future<void> _backfillPeerNameBestEffort({
    required DocumentReference<Map<String, dynamic>> ref,
    required Map<String, dynamic> currentData,
    required String resolvedPeerId,
    required String resolvedName,
  }) async {
    final docId = ref.id;
    if (_denyBackfill.contains(docId)) return;

    final peerId = resolvedPeerId.trim();
    final name = resolvedName.trim();
    if (peerId.isEmpty || name.isEmpty) return;

    String t(Object? v) => (v ?? '').toString().trim();
    final existing = t(currentData['peerName']);

    if (!_shouldUpgradeName(existing: existing, candidate: name, peerId: peerId)) {
      return;
    }

    try {
      await ref.set(
        {
          'peerName': name,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } catch (e) {
      debugPrint('[CallLogs] backfill peerName failed: $e');
      if (_isPermissionDenied(e)) {
        _denyBackfill.add(docId);
      }
    }
  }

  String _pickNameFromLog(Map<String, dynamic> d) {
    String t(Object? v) => (v ?? '').toString().trim();

    final peerName = t(d['peerName']);
    if (peerName.isNotEmpty) return peerName;

    final callerName = t(d['callerName']);
    if (callerName.isNotEmpty) return callerName;

    final calleeName = t(d['calleeName']);
    if (calleeName.isNotEmpty) return calleeName;

    return '';
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

    final email = s(u['email']);
    final pretty = _prettyNameFromEmail(email);
    if (pretty.isNotEmpty) return pretty;

    final username = s(u['username']);
    if (username.isNotEmpty) return username;

    return '';
  }

  void _ensureNameFetched({
    required String docId,
    required String peerId,
    required DocumentReference<Map<String, dynamic>> docRef,
    required Map<String, dynamic> currentData,
  }) {
    final id = peerId.trim();
    if (id.isEmpty) return;

    final cached = _nameCache[id];
    if (cached != null && cached.trim().isNotEmpty) return;

    if (_inflight.contains(id)) return;
    _inflight.add(id);

    FirebaseFirestore.instance.collection('users').doc(id).get().then((snap) async {
      final name = _extractDisplayName(snap.data()).trim();
      if (name.isNotEmpty) {
        _nameCache[id] = name;
        _nameRev.value++;

        // ✅ Backfill peerName (upgrade-safe), but only once per doc per session
        if (!_peerNameBackfilled.contains(docId)) {
          _peerNameBackfilled.add(docId);
          await _backfillPeerNameBestEffort(
            ref: docRef,
            currentData: currentData,
            resolvedPeerId: id,
            resolvedName: name,
          );
        }
      }
    }).catchError((e) {
      debugPrint('[CallLogs] name lookup failed for uid=$id: $e');
    }).whenComplete(() {
      _inflight.remove(id);
    });
  }

  void _prefetchNamesForDocs(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
      String myUid,
      ) {
    const maxPrefetch = 25;
    var n = 0;

    for (final doc in docs) {
      if (n >= maxPrefetch) break;

      final d = doc.data();
      final resolvedPeerId = _resolvePeerIdFromLog(d, myUid);
      if (resolvedPeerId.isEmpty) continue;

      if (_nameCache.containsKey(resolvedPeerId)) continue;

      _ensureNameFetched(
        docId: doc.id,
        peerId: resolvedPeerId,
        docRef: doc.reference,
        currentData: d,
      );
      n++;
    }
  }

  // ----------------------------
  // Auto-mark missed once
  // ----------------------------
  void _scheduleAutoMarkOnce(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    if (_autoMarkRan) return;

    final hasAnyUnread = docs.any((d) {
      final data = d.data();
      final isRead = data['isRead'] == true;
      final isReadMissing = !data.containsKey('isRead');
      return !isRead || isReadMissing;
    });

    if (!hasAnyUnread) {
      _autoMarkRan = true;
      return;
    }

    _autoMarkDebounce?.cancel();
    _autoMarkDebounce = Timer(const Duration(milliseconds: 350), () async {
      if (!mounted) return;
      _autoMarkRan = true;
      await _markAllAsReadBestEffort(docs);
    });
  }

  void _attachMissedSubscriptionIfNeeded() {
    _missedSub?.cancel();
    _missedSub = null;

    final me = FirebaseAuth.instance.currentUser;
    if (me == null) return;
    if (_filter != _CallsFilter.missed) return;

    _missedSub = _streamFor(me.uid, _CallsFilter.missed).listen((snap) {
      if (_filter != _CallsFilter.missed) return;
      _scheduleAutoMarkOnce(snap.docs);
    });
  }

  // ----------------------------
  // Formatting
  // ----------------------------
  String _formatWhen(int createdAtMs) {
    if (createdAtMs <= 0) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(createdAtMs).toLocal();
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$y-$m-$d  $hh:$mm';
  }

  // ----------------------------
  // Lifecycle
  // ----------------------------
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _attachMissedSubscriptionIfNeeded();
    });
  }

  @override
  void dispose() {
    _autoMarkDebounce?.cancel();
    _missedSub?.cancel();
    _nameRev.dispose();
    super.dispose();
  }

  // ----------------------------
  // UI helpers
  // ----------------------------
  Widget _buildGlassShell({
    required BuildContext context,
    required bool isWide,
    required Widget child,
  }) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: Container(
          margin: EdgeInsets.symmetric(
            horizontal: isWide ? 24 : 14,
            vertical: 10,
          ),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.65),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          child: child,
        ),
      ),
    );
  }

  Future<void> _markMissedAllRead() async {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) return;

    final q = _queryFor(me.uid, _CallsFilter.missed);

    try {
      final snap = await q.get();
      await _markAllAsReadBestEffort(snap.docs);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_l10n.callLogs_snack_markedMissedRead)),
      );
    } catch (e) {
      debugPrint('[CallLogs] markAll get() failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_l10n.callLogs_snack_failedWithError(e.toString())),
        ),
      );
    }
  }

  void _setFilter(_CallsFilter f) {
    if (_filter == f) return;

    setState(() {
      _filter = f;
      if (_filter == _CallsFilter.missed) _autoMarkRan = false;
    });

    _attachMissedSubscriptionIfNeeded();
  }

  String _filterLabel(_CallsFilter f) {
    switch (f) {
      case _CallsFilter.all:
        return _l10n.callLogs_filter_all;
      case _CallsFilter.missed:
        return _l10n.callLogs_filter_missed;
      case _CallsFilter.incoming:
        return _l10n.callLogs_filter_incoming;
      case _CallsFilter.outgoing:
        return _l10n.callLogs_filter_outgoing;
    }
  }

  Future<void> _clearLogsForCurrentFilter() async {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) return;
    if (_isClearing) return;

    final label = _filterLabel(_filter);

    final ok = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final l10n = AppLocalizations.of(ctx)!;
        return Container(
          margin: const EdgeInsets.all(14),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.92),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withOpacity(0.10)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.callLogs_confirm_clearTitle(label),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _filter == _CallsFilter.all
                    ? l10n.callLogs_confirm_clearAllBody
                    : l10n.callLogs_confirm_clearFilterBody(label),
                style: TextStyle(
                  color: Colors.white.withOpacity(0.65),
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: Text(l10n.common_cancel),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () => Navigator.pop(ctx, true),
                      child: Text(l10n.common_clear),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );

    if (ok != true) return;

    setState(() => _isClearing = true);

    try {
      Query<Map<String, dynamic>> q;
      if (_filter == _CallsFilter.all) {
        q = _base(me.uid).orderBy('createdAtMs', descending: true);
      } else if (_filter == _CallsFilter.missed) {
        q = _base(me.uid)
            .where('direction', isEqualTo: 'incoming')
            .where('result', isEqualTo: _rMissed)
            .orderBy('createdAtMs', descending: true);
      } else if (_filter == _CallsFilter.incoming) {
        q = _base(me.uid)
            .where('direction', isEqualTo: 'incoming')
            .where('result', whereIn: const [_rEnded, _rDeclined, _rBusy, _rMissed])
            .orderBy('createdAtMs', descending: true);
      } else {
        q = _base(me.uid)
            .where('direction', isEqualTo: 'outgoing')
            .where(
          'result',
          whereIn: const [_rEnded, _rCanceled, _rDeclined, _rMissed, _rBusy],
        )
            .orderBy('createdAtMs', descending: true);
      }

      const pageSize = 400;
      DocumentSnapshot<Map<String, dynamic>>? last;
      var totalDeleted = 0;

      while (true) {
        var pageQuery = q.limit(pageSize);
        if (last != null) pageQuery = pageQuery.startAfterDocument(last);

        final snap = await pageQuery.get();
        if (snap.docs.isEmpty) break;

        final batch = FirebaseFirestore.instance.batch();
        for (final d in snap.docs) {
          batch.delete(d.reference);
        }
        await batch.commit();

        totalDeleted += snap.docs.length;
        last = snap.docs.last;
        if (snap.docs.length < pageSize) break;
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_l10n.callLogs_snack_clearedWithCount(totalDeleted, label)),
        ),
      );

      setState(() {});
    } catch (e) {
      debugPrint('[CallLogs] clear logs failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_l10n.callLogs_snack_clearFailedWithError(e.toString())),
        ),
      );
    } finally {
      if (mounted) setState(() => _isClearing = false);
    }
  }

  Widget _filterChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          gradient: selected ? mwGradient : null,
          color: selected ? null : kSurfaceAltColor.withOpacity(0.55),
          border: Border.all(
            color: selected ? Colors.transparent : kBorderColor.withOpacity(0.6),
          ),
          boxShadow: selected
              ? [
            BoxShadow(
              color: kGoldDeep.withOpacity(0.14),
              blurRadius: 14,
              spreadRadius: 1,
              offset: const Offset(0, 5),
            ),
          ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.black : Colors.white70,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.15,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  String _screenTitle() => _l10n.callLogs_title;

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final me = FirebaseAuth.instance.currentUser;
    final width = MediaQuery.of(context).size.width;
    final isWide = width >= 900;

    if (me == null) {
      return Scaffold(body: Center(child: Text(_l10n.callLogs_notSignedIn)));
    }

    final stream = _streamFor(me.uid, _filter);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black.withOpacity(0.85),
        elevation: 0,
        centerTitle: true,
        title: Text(
          _screenTitle(),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        leading: Navigator.of(context).canPop()
            ? IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.of(context).maybePop(),
        )
            : null,
        actions: [
          IconButton(
            tooltip: _l10n.callLogs_tooltip_retry,
            onPressed: _isClearing
                ? null
                : () {
              setState(() => _autoMarkRan = false);
              _attachMissedSubscriptionIfNeeded();
            },
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: _l10n.callLogs_tooltip_markMissedRead,
            onPressed: _isClearing ? null : _markMissedAllRead,
            icon: const Icon(Icons.done_all_rounded),
          ),
          IconButton(
            tooltip: _l10n.callLogs_tooltip_clearLogs,
            onPressed: _isClearing ? null : _clearLogsForCurrentFilter,
            icon: const Icon(Icons.delete_sweep_rounded),
          ),
        ],
      ),
      body: MwBackground(
        child: SafeArea(
          top: false,
          child: _buildGlassShell(
            context: context,
            isWide: isWide,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    child: Row(
                      children: [
                        _filterChip(
                          label: _l10n.callLogs_filter_all,
                          selected: _filter == _CallsFilter.all,
                          onTap: _isClearing ? () {} : () => _setFilter(_CallsFilter.all),
                        ),
                        const SizedBox(width: 10),
                        _filterChip(
                          label: _l10n.callLogs_filter_missed,
                          selected: _filter == _CallsFilter.missed,
                          onTap: _isClearing ? () {} : () => _setFilter(_CallsFilter.missed),
                        ),
                        const SizedBox(width: 10),
                        _filterChip(
                          label: _l10n.callLogs_filter_incoming,
                          selected: _filter == _CallsFilter.incoming,
                          onTap:
                          _isClearing ? () {} : () => _setFilter(_CallsFilter.incoming),
                        ),
                        const SizedBox(width: 10),
                        _filterChip(
                          label: _l10n.callLogs_filter_outgoing,
                          selected: _filter == _CallsFilter.outgoing,
                          onTap:
                          _isClearing ? () {} : () => _setFilter(_CallsFilter.outgoing),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: stream,
                    builder: (context, snap) {
                      if (kDebugMode) {
                        final now = DateTime.now();
                        if (now.difference(_lastDebugPrint).inMilliseconds > 800) {
                          _lastDebugPrint = now;
                          debugPrint(
                            '[CallLogs] filter=$_filter state=${snap.connectionState} '
                                'hasData=${snap.hasData} hasError=${snap.hasError} '
                                'docs=${snap.data?.docs.length ?? 0}',
                          );
                        }
                      }

                      if (snap.hasError) {
                        final err = snap.error!;
                        final isIndex = _looksLikeIndexError(err);

                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(18),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  isIndex
                                      ? Icons.account_tree_rounded
                                      : Icons.error_outline_rounded,
                                  size: 30,
                                  color: isIndex ? Colors.orangeAccent : Colors.redAccent,
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  isIndex
                                      ? _l10n.callLogs_error_indexRequired
                                      : _l10n.callLogs_error_failedToLoad,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: kTextSecondary.withOpacity(0.92),
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                SelectableText(
                                  err.toString(),
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: kTextSecondary.withOpacity(0.72),
                                    fontSize: 12.5,
                                    height: 1.35,
                                  ),
                                ),
                                const SizedBox(height: 14),
                                if (isIndex)
                                  Text(
                                    _l10n.callLogs_error_createIndexHint,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: kTextSecondary.withOpacity(0.75),
                                      fontSize: 12.5,
                                      height: 1.35,
                                    ),
                                  ),
                                const SizedBox(height: 16),
                                OutlinedButton.icon(
                                  onPressed: () => setState(() {}),
                                  icon: const Icon(Icons.refresh_rounded),
                                  label: Text(_l10n.common_retry),
                                ),
                              ],
                            ),
                          ),
                        );
                      }

                      if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final docs = snap.data?.docs ??
                          const <QueryDocumentSnapshot<Map<String, dynamic>>>[];

                      if (docs.isEmpty) {
                        final emptyText = switch (_filter) {
                          _CallsFilter.all => _l10n.callLogs_empty_all,
                          _CallsFilter.missed => _l10n.callLogs_empty_missed,
                          _CallsFilter.incoming => _l10n.callLogs_empty_incoming,
                          _CallsFilter.outgoing => _l10n.callLogs_empty_outgoing,
                        };
                        return Center(
                          child: Text(
                            emptyText,
                            style: TextStyle(color: kTextSecondary.withOpacity(0.85)),
                          ),
                        );
                      }

                      // ✅ Prefetch profile names to unify incoming/outgoing labels.
                      _prefetchNamesForDocs(docs, me.uid);

                      return ValueListenableBuilder<int>(
                        valueListenable: _nameRev,
                        builder: (_, __, ___) {
                          return ListView.separated(
                            key: PageStorageKey<String>('call_logs_${_filter.name}'),
                            cacheExtent: 900,
                            padding: const EdgeInsets.fromLTRB(14, 4, 14, 18),
                            itemCount: docs.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 10),
                            itemBuilder: (context, i) {
                              final doc = docs[i];
                              final d = doc.data();

                              String t(Object? v) => (v ?? '').toString().trim();

                              final createdAtMs = (d['createdAtMs'] is num)
                                  ? (d['createdAtMs'] as num).toInt()
                                  : 0;

                              final result = t(d['result']);
                              final direction = t(d['direction']);
                              final type = t(d['type']).isEmpty ? 'audio' : t(d['type']);

                              final isRead = d['isRead'] == true;
                              final isReadMissing = !d.containsKey('isRead');
                              final effectiveUnread = !isRead || isReadMissing;

                              final resolvedPeerId = _resolvePeerIdFromLog(d, me.uid);

                              // ✅ peerId backfill: do it at most once per doc per session
                              if (resolvedPeerId.isNotEmpty &&
                                  !_peerIdBackfilled.contains(doc.id)) {
                                _peerIdBackfilled.add(doc.id);
                                unawaited(
                                  _backfillPeerIdBestEffort(
                                    ref: doc.reference,
                                    currentData: d,
                                    myUid: me.uid,
                                    resolvedPeerId: resolvedPeerId,
                                  ),
                                );
                              }

                              final logName = _pickNameFromLog(d);
                              final logNameOk = resolvedPeerId.isNotEmpty
                                  ? !_isBadNameCandidate(name: logName, peerId: resolvedPeerId)
                                  : logName.trim().isNotEmpty;

                              final profileName = resolvedPeerId.isNotEmpty
                                  ? (_nameCache[resolvedPeerId] ?? '').trim()
                                  : '';

                              // ✅ Display name rule:
                              // profileName (canonical) → logName (if ok) → unknown
                              final displayName = profileName.isNotEmpty
                                  ? profileName
                                  : (logNameOk ? logName : _l10n.callLogs_unknownUser);

                              // ✅ Upgrade peerName when we have canonical name, but only once per doc per session
                              if (resolvedPeerId.isNotEmpty &&
                                  profileName.isNotEmpty &&
                                  !_peerNameBackfilled.contains(doc.id)) {
                                _peerNameBackfilled.add(doc.id);
                                unawaited(
                                  _backfillPeerNameBestEffort(
                                    ref: doc.reference,
                                    currentData: d,
                                    resolvedPeerId: resolvedPeerId,
                                    resolvedName: profileName,
                                  ),
                                );
                              } else if (resolvedPeerId.isNotEmpty && profileName.isEmpty) {
                                _ensureNameFetched(
                                  docId: doc.id,
                                  peerId: resolvedPeerId,
                                  docRef: doc.reference,
                                  currentData: d,
                                );
                              }

                              return _CallLogTile(
                                d: d,
                                docRef: doc.reference,
                                createdAtMs: createdAtMs,
                                whenStr: _formatWhen(createdAtMs),
                                result: result,
                                direction: direction,
                                type: type,
                                effectiveUnread: effectiveUnread,
                                peerId: resolvedPeerId,
                                displayName: displayName,
                                isClearing: _isClearing,
                                onMarkRead: _markOneAsReadBestEffort,
                                onStartCall: widget.onStartCall,
                                enableVideoButton: widget.enableVideoButton,
                                onOpenChat: widget.onOpenChat,
                              );
                            },
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CallLogTile extends StatelessWidget {
  const _CallLogTile({
    required this.d,
    required this.docRef,
    required this.createdAtMs,
    required this.whenStr,
    required this.result,
    required this.direction,
    required this.type,
    required this.effectiveUnread,
    required this.peerId,
    required this.displayName,
    required this.isClearing,
    required this.onMarkRead,
    required this.onStartCall,
    required this.enableVideoButton,
    required this.onOpenChat,
  });

  final Map<String, dynamic> d;
  final DocumentReference<Map<String, dynamic>> docRef;

  final int createdAtMs;
  final String whenStr;
  final String result;
  final String direction;
  final String type;
  final bool effectiveUnread;

  final String peerId;
  final String displayName;

  final bool isClearing;

  final Future<void> Function(
      DocumentReference<Map<String, dynamic>> ref,
      Map<String, dynamic> currentData,
      ) onMarkRead;

  final StartCallFromLogs? onStartCall;
  final bool enableVideoButton;

  final OpenChatFromLogs? onOpenChat;

  static const String _rEnded = 'ended';
  static const String _rDeclined = 'declined';
  static const String _rCanceled = 'canceled';
  static const String _rMissed = 'missed';
  static const String _rBusy = 'busy';

  String _resultLabel(AppLocalizations l10n, String r) {
    switch (r) {
      case _rEnded:
        return l10n.callLogs_result_ended;
      case _rDeclined:
        return l10n.callLogs_result_declined;
      case _rCanceled:
        return l10n.callLogs_result_canceled;
      case _rMissed:
        return l10n.callLogs_result_missed;
      case _rBusy:
        return l10n.callLogs_result_busy;
      default:
        return r;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    String initialsFrom(String nameOrId) {
      final x = nameOrId.trim();
      if (x.isEmpty) return '?';
      final parts = x.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
      if (parts.isEmpty) return '?';
      if (parts.length == 1) {
        return parts.first.characters.take(1).toString().toUpperCase();
      }
      final a = parts[0].characters.take(1).toString().toUpperCase();
      final b = parts[1].characters.take(1).toString().toUpperCase();
      return '$a$b';
    }

    final isIncoming = direction == 'incoming';
    final statusLabel = _resultLabel(l10n, result);

    Color accent;
    if (isIncoming && result == _rMissed) {
      accent = Colors.redAccent;
    } else if (result == _rDeclined || result == _rBusy) {
      accent = Colors.orangeAccent;
    } else if (result == _rEnded) {
      accent = kPrimaryGold;
    } else if (result == _rCanceled) {
      accent = Colors.white70;
    } else {
      accent = Colors.white70;
    }

    final isMissedUnread = isIncoming && result == _rMissed && effectiveUnread;
    final canTapMarkRead = isIncoming && result == _rMissed && effectiveUnread;

    final initialsSource =
    displayName.isNotEmpty ? displayName : (peerId.isNotEmpty ? peerId : '?');

    final arrowIcon =
    isIncoming ? Icons.call_received_rounded : Icons.call_made_rounded;
    final dirLabel = isIncoming
        ? l10n.callLogs_direction_incoming
        : l10n.callLogs_direction_outgoing;
    final typeIcon =
    (type == 'video') ? Icons.videocam_rounded : Icons.call_rounded;

    final statusChip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withOpacity(0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(typeIcon, size: 14, color: accent),
          const SizedBox(width: 6),
          Text(
            statusLabel,
            style: TextStyle(
              color: accent,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );

    final hasPeer = peerId.trim().isNotEmpty;
    final canShowButtons = !isClearing;
    final canActuallyCall = !isClearing && hasPeer && onStartCall != null;

    Widget compactActionIcon({
      required String tooltip,
      required IconData icon,
      required VoidCallback? onPressed,
    }) {
      final enabled = onPressed != null;
      return IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(
          icon,
          color: enabled ? Colors.white70 : Colors.white24,
          size: 20,
        ),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 38, height: 38),
        visualDensity: VisualDensity.compact,
      );
    }

    Future<void> startCall(bool video) async {
      if (!canActuallyCall) return;

      if (canTapMarkRead) {
        await onMarkRead(docRef, d);
      }

      HapticFeedback.selectionClick();

      try {
        await onStartCall!.call(peerId: peerId.trim(), video: video);
      } catch (e) {
        debugPrint('[CallLogs] startCall failed: $e');
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to start call: $e')),
        );
      }
    }

    Future<void> openChat() async {
      if (!hasPeer) return;
      if (onOpenChat == null) return;

      HapticFeedback.selectionClick();
      onOpenChat!.call(peerId: peerId.trim(), displayName: displayName.trim());
    }

    Future<void> markReadWithSnack() async {
      await onMarkRead(docRef, d);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.callLogs_snack_markedAsRead)),
      );
    }

    final VoidCallback? tileOnTap = isClearing
        ? null
        : (canTapMarkRead
        ? () async => markReadWithSnack()
        : (onOpenChat != null && hasPeer ? () async => openChat() : null));

    return RepaintBoundary(
      child: Container(
        decoration: BoxDecoration(
          color: kSurfaceAltColor.withOpacity(0.55),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isMissedUnread
                ? Colors.redAccent.withOpacity(0.55)
                : kBorderColor.withOpacity(0.55),
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: tileOnTap,
          onLongPress: (!isClearing && hasPeer)
              ? () async {
            await Clipboard.setData(ClipboardData(text: peerId.trim()));
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Copied peerId')),
            );
          }
              : null,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: Row(
              children: [
                // Avatar
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: mwGradient,
                    boxShadow: [
                      BoxShadow(
                        color: kGoldDeep.withOpacity(0.10),
                        blurRadius: 12,
                        offset: const Offset(0, 7),
                      ),
                    ],
                  ),
                  child: Container(
                    margin: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.black.withOpacity(0.65),
                      border: Border.all(color: Colors.white.withOpacity(0.10)),
                    ),
                    child: Center(
                      child: Text(
                        initialsFrom(initialsSource),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(arrowIcon, size: 14, color: Colors.white38),
                          const SizedBox(width: 6),
                          Text(
                            '$dirLabel • $statusLabel',
                            style: const TextStyle(
                              color: Colors.white60,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        whenStr,
                        style: TextStyle(
                          color: kTextSecondary.withOpacity(0.75),
                          fontSize: 12,
                          height: 1.15,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 10),

                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    statusChip,
                    if (isMissedUnread) ...[
                      const SizedBox(height: 10),
                      const Icon(Icons.circle,
                          size: 10, color: Colors.redAccent),
                    ],
                    if (canShowButtons) ...[
                      const SizedBox(height: 8),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          compactActionIcon(
                            tooltip: canActuallyCall
                                ? l10n.callLogs_tooltip_voiceCall
                                : 'Wire onStartCall to enable',
                            icon: Icons.call_rounded,
                            onPressed:
                            canActuallyCall ? () => startCall(false) : null,
                          ),
                          if (enableVideoButton) ...[
                            const SizedBox(width: 2),
                            compactActionIcon(
                              tooltip: canActuallyCall
                                  ? l10n.callLogs_tooltip_videoCall
                                  : 'Wire onStartCall to enable',
                              icon: Icons.videocam_rounded,
                              onPressed:
                              canActuallyCall ? () => startCall(true) : null,
                            ),
                          ],
                        ],
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
