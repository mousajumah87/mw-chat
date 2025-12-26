// lib/screens/home/mw_friend_requests_screen.dart
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../widgets/ui/mw_background.dart';
import '../../widgets/ui/mw_search_field.dart';
import '../../widgets/ui/mw_avatar.dart';

class MwFriendRequestsScreen extends StatefulWidget {
  final String currentUserId;

  /// current map uid -> status (accepted/requested/incoming) (used by tile builder)
  final Map<String, String> friendStatuses;

  /// Kept for API compatibility, but this screen uses its own MW request tile UI
  final Widget Function(
      BuildContext context,
      Map<String, dynamic> data,
      String userId, {
      required String? friendStatus,
      bool hideIncomingActions,
      }) buildUserTile;

  /// Actions (provided by MwFriendsTab)
  final Future<void> Function(String uid) acceptFriend;
  final Future<void> Function(String uid) declineFriend;

  const MwFriendRequestsScreen({
    super.key,
    required this.currentUserId,
    required this.friendStatuses,
    required this.buildUserTile,
    required this.acceptFriend,
    required this.declineFriend,
  });

  @override
  State<MwFriendRequestsScreen> createState() => _MwFriendRequestsScreenState();
}

class _MwFriendRequestsScreenState extends State<MwFriendRequestsScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _incomingSub;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _incomingDocs = const [];

  /// Optimistic removal so UI updates instantly
  final Set<String> _optimisticallyRemoved = <String>{};

  static const String _fieldFriendRequestsLastSeenAt = 'friendRequestsLastSeenAt';

  @override
  void initState() {
    super.initState();
    _markRequestsSeen();
    _listenIncomingRequests();
  }

  void _listenIncomingRequests() {
    _incomingSub?.cancel();

    // ✅ IMPORTANT: No orderBy -> avoids composite index requirement.
    _incomingSub = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.currentUserId)
        .collection('friends')
        .where('status', isEqualTo: 'incoming')
        .snapshots()
        .listen(
          (snap) {
        if (!mounted) return;

        final docs = snap.docs.toList(growable: false);

        // ✅ Local sort by updatedAt desc (null-safe)
        docs.sort((a, b) {
          final ta = a.data()['updatedAt'];
          final tb = b.data()['updatedAt'];

          DateTime? da;
          DateTime? db;

          if (ta is Timestamp) da = ta.toDate();
          if (tb is Timestamp) db = tb.toDate();

          if (da == null && db == null) return 0;
          if (da == null) return 1;
          if (db == null) return -1;

          return db.compareTo(da);
        });

        setState(() => _incomingDocs = docs);
      },
      onError: (e, st) {
        debugPrint('[MwFriendRequestsScreen] incoming stream error: $e');
        if (!mounted) return;
        setState(() => _incomingDocs = const []);
      },
    );
  }

  Future<void> _markRequestsSeen() async {
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.currentUserId)
          .set(
        {_fieldFriendRequestsLastSeenAt: FieldValue.serverTimestamp()},
        SetOptions(merge: true),
      );
    } catch (_) {
      // ignore
    }
  }

  @override
  void dispose() {
    _incomingSub?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  // ----------------------------
  // Theme helpers
  // ----------------------------

  /// ✅ A warmer, more “MW glass” ring (less harsh than solid kPrimaryGold)
  Color _mwRingColorForTheme() {
    // slightly deeper gold reads better on dark glass cards
    return kGoldDeep.withOpacity(0.85);
  }

  // ----------------------------
  // Search
  // ----------------------------

  Widget _buildSearchBar(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: MwSearchField(
        controller: _searchController,
        hintText: l10n.friendRequestsSearchHint,
        onChanged: (v) {
          if (!mounted) return;
          setState(() => _searchQuery = v);
        },
        onClear: () {
          if (!mounted) return;
          setState(() => _searchQuery = '');
        },
      ),
    );
  }

  bool _matchesLocalSearch(Map<String, dynamic> data, String userId) {
    final q = _searchQuery.trim().toLowerCase();
    if (q.isEmpty) return true;

    final email = (data['email'] as String?) ?? '';
    final displayName = (data['displayName'] as String?) ?? '';
    final username = (data['username'] as String?) ?? '';
    final fullName = (data['fullName'] as String?) ?? '';

    final haystack = [
      userId,
      email,
      displayName,
      username,
      fullName,
    ].join(' ').toLowerCase();

    return haystack.contains(q);
  }

  // ----------------------------
  // Actions (optimistic)
  // ----------------------------

  Future<void> _acceptAndRemove(String uid) async {
    if (uid.isEmpty) return;

    setState(() => _optimisticallyRemoved.add(uid));
    try {
      await widget.acceptFriend(uid);
    } catch (_) {
      if (!mounted) return;
      setState(() => _optimisticallyRemoved.remove(uid));
    }
  }

  Future<void> _declineAndRemove(String uid) async {
    if (uid.isEmpty) return;

    setState(() => _optimisticallyRemoved.add(uid));
    try {
      await widget.declineFriend(uid);
    } catch (_) {
      if (!mounted) return;
      setState(() => _optimisticallyRemoved.remove(uid));
    }
  }

  // ----------------------------
  // UI bits
  // ----------------------------

  Widget _buildTopPill(BuildContext context, int count) {
    final l10n = AppLocalizations.of(context)!;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.65),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.10)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.35),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: kSurfaceColor.withOpacity(0.9),
              border: Border.all(color: Colors.white.withOpacity(0.12)),
            ),
            child: const Icon(Icons.person_add_alt_1, color: kPrimaryGold),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.friendRequestsTitle,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  l10n.friendRequestsSubtitle(count),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.white70,
                    height: 1.3,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: kPrimaryGold.withOpacity(0.14),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: kPrimaryGold.withOpacity(0.30)),
            ),
            child: Text(
              '$count',
              style: const TextStyle(
                color: kPrimaryGold,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _primaryLabel(Map<String, dynamic> data, String fallback) {
    final displayName = (data['displayName'] as String?)?.trim() ?? '';
    final fullName = (data['fullName'] as String?)?.trim() ?? '';
    final username = (data['username'] as String?)?.trim() ?? '';
    final email = (data['email'] as String?)?.trim() ?? '';

    if (displayName.isNotEmpty) return displayName;
    if (fullName.isNotEmpty) return fullName;
    if (username.isNotEmpty) return username;
    if (email.isNotEmpty) return email;
    return fallback;
  }

  String _secondaryLabel(Map<String, dynamic> data) {
    final email = (data['email'] as String?)?.trim() ?? '';
    final username = (data['username'] as String?)?.trim() ?? '';
    if (email.isNotEmpty) return email;
    if (username.isNotEmpty) return '@$username';
    return '';
  }

  String? _extractProfileUrl(Map<String, dynamic> data) {
    // Matches your MwAvatar: profileUrl (real photo)
    final candidates = <String>[
      'profileUrl',
      'profileURL',
      'photoUrl',
      'photoURL',
      'profilePhotoUrl',
      'profilePhotoURL',
      'avatarUrl',
      'avatarURL',
      'picture',
      'imageUrl',
      'imageURL',
    ];

    for (final k in candidates) {
      final v = data[k];
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    return null;
  }

  String _extractAvatarType(Map<String, dynamic> data) {
    final candidates = <String>[
      'avatarType',
      'avatar',
      'selectedAvatar',
      'defaultAvatar',
    ];

    for (final k in candidates) {
      final v = data[k];
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    // ✅ safe fallback
    return 'bear';
  }

  Widget _actionCircle({
    required BuildContext context,
    required IconData icon,
    required VoidCallback onTap,
    required Color bg,
    required Color fg,
    String? tooltip,
  }) {
    const double size = 40;

    final child = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Ink(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: bg,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withOpacity(0.10)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.25),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Icon(icon, size: 18, color: fg),
        ),
      ),
    );

    final msg = (tooltip ?? '').trim();
    if (msg.isEmpty) return child;
    return Tooltip(message: msg, child: child);
  }

  Widget _buildRequestTile(
      BuildContext context, {
        required Map<String, dynamic> data,
        required String uid,
      }) {
    final l10n = AppLocalizations.of(context)!;

    final title = _primaryLabel(data, uid);
    final subtitle = _secondaryLabel(data);
    final profileUrl = _extractProfileUrl(data);
    final avatarType = _extractAvatarType(data);

    final border = Colors.white.withOpacity(0.12);

    return Container(
      margin: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.55),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          MwAvatar(
            avatarType: avatarType,
            profileUrl: profileUrl,
            radius: 22,

            // ✅ MW theme ring
            showRing: true,
            ringColor: _mwRingColorForTheme(),
            ringWidth: 2.2,

            // friend-requests page: keep clean (no presence UI)
            isOnline: false,
            showOnlineDot: false,
            showOnlineGlow: false,

            // ✅ nicer glass read than pure white
            backgroundColor: kSurfaceAltColor.withOpacity(0.85),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle.isNotEmpty ? subtitle : ' ',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.white70,
                    height: 1.2,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _actionCircle(
                context: context,
                icon: Icons.close_rounded,
                tooltip: l10n.friendDeclineTooltip,
                onTap: () => _declineAndRemove(uid),
                bg: Colors.white.withOpacity(0.06),
                fg: Colors.redAccent.withOpacity(0.95),
              ),
              const SizedBox(width: 10),
              _actionCircle(
                context: context,
                icon: Icons.check_rounded,
                tooltip: l10n.friendAcceptTooltip,
                onTap: () => _acceptAndRemove(uid),
                bg: kPrimaryGold,
                fg: Colors.black,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDeletedAccountTile(
      BuildContext context, {
        required String uid,
      }) {
    final l10n = AppLocalizations.of(context)!;

    // Search: for deleted accounts we can only match uid (no profile data)
    final q = _searchQuery.trim().toLowerCase();
    if (q.isNotEmpty && !uid.toLowerCase().contains(q)) {
      return const SizedBox.shrink();
    }

    final border = Colors.white.withOpacity(0.12);

    return Container(
      margin: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.55),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          MwAvatar(
            avatarType: 'bear',
            profileUrl: null,
            radius: 22,
            showRing: true,
            ringColor: _mwRingColorForTheme(),
            ringWidth: 2.2,
            isOnline: false,
            showOnlineDot: false,
            showOnlineGlow: false,
            backgroundColor: kSurfaceAltColor.withOpacity(0.85),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (l10n.deletedAccount ?? 'Deleted account'),
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
                const SizedBox(height: 2),
                Text(
                  (l10n.accountUnavailableSubtitle ??
                      'This account is no longer available.'),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.white70,
                    height: 1.2,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),

          // Only action: remove/decline (cleans both sides)
          _actionCircle(
            context: context,
            icon: Icons.delete_outline_rounded,
            tooltip: (l10n.removeFriendConfirm ?? 'Remove'),
            onTap: () => _declineAndRemove(uid),
            bg: Colors.white.withOpacity(0.06),
            fg: Colors.redAccent.withOpacity(0.95),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final width = MediaQuery.of(context).size.width;
    final isWide = width >= 900;

    final incoming = _incomingDocs
        .where((d) => d.id != widget.currentUserId)
        .where((d) => !_optimisticallyRemoved.contains(d.id))
        .toList(growable: false);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black.withOpacity(0.85),
        elevation: 0,
        centerTitle: true,
        title: Text(
          l10n.friendRequestsTitle,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        leading: Navigator.of(context).canPop()
            ? IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.of(context).maybePop(),
        )
            : null,
      ),
      body: MwBackground(
        child: SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  Expanded(
                    child: Container(
                      margin: EdgeInsets.symmetric(
                        horizontal: isWide ? 32 : 16,
                        vertical: 8,
                      ),
                      padding: EdgeInsets.symmetric(
                        horizontal: isWide ? 22 : 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.65),
                        borderRadius: BorderRadius.circular(24),
                        border:
                        Border.all(color: Colors.white.withOpacity(0.08)),
                      ),
                      child: Column(
                        children: [
                          _buildTopPill(context, incoming.length),
                          _buildSearchBar(context),
                          const SizedBox(height: 6),
                          Divider(color: Colors.white.withOpacity(0.18)),
                          const SizedBox(height: 6),
                          if (incoming.isEmpty)
                            Expanded(
                              child: Center(
                                child: Text(
                                  l10n.friendRequestsEmpty,
                                  style:
                                  const TextStyle(color: Colors.white70),
                                ),
                              ),
                            )
                          else
                            Expanded(
                              child: ListView.builder(
                                padding:
                                const EdgeInsets.fromLTRB(4, 6, 4, 16),
                                physics: const BouncingScrollPhysics(),
                                itemCount: incoming.length,
                                itemBuilder: (context, index) {
                                  final doc = incoming[index];
                                  final uid = doc.id;

                                  final rawStatus =
                                      (doc.data()['status'] as String?) ?? '';
                                  if (rawStatus.toLowerCase() != 'incoming') {
                                    return const SizedBox.shrink();
                                  }

                                  return StreamBuilder<
                                      DocumentSnapshot<Map<String, dynamic>>>(
                                    stream: FirebaseFirestore.instance
                                        .collection('users')
                                        .doc(uid)
                                        .snapshots(),
                                    builder: (context, snap) {
                                      if (snap.hasError) {
                                        return const SizedBox.shrink();
                                      }
                                      if (!snap.hasData) {
                                        return const SizedBox.shrink();
                                      }

                                      final data = snap.data!.data();
                                      if (data == null) {
                                        // ✅ Account deleted (profile doc missing)
                                        return _buildDeletedAccountTile(
                                          context,
                                          uid: uid,
                                        );
                                      }

                                      if (!_matchesLocalSearch(data, uid)) {
                                        return const SizedBox.shrink();
                                      }

                                      return _buildRequestTile(
                                        context,
                                        data: data,
                                        uid: uid,
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
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
