// lib/screens/home/user_profile_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../widgets/ui/mw_background.dart';

class UserProfileScreen extends StatefulWidget {
  final String userId;
  const UserProfileScreen({super.key, required this.userId});

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  static const int _onlineTtlSeconds = 300;

  bool _isBlocking = false;
  bool _isReporting = false;

  bool _isOnlineWithTtl({
    required bool rawIsOnline,
    required Timestamp? lastSeen,
  }) {
    if (!rawIsOnline || lastSeen == null) return false;
    final diffSeconds = DateTime.now().difference(lastSeen.toDate()).inSeconds;
    return diffSeconds <= _onlineTtlSeconds;
  }

  (String label, Color color) _buildPresenceStatus(
      AppLocalizations l10n, {
        required bool isActive,
        required bool effectiveOnline,
      }) {
    if (!isActive) return (l10n.accountNotActive, Colors.orangeAccent);
    if (effectiveOnline) return (l10n.online, Colors.greenAccent.shade400);
    return (l10n.offline, Colors.grey);
  }

  String _ageLabel(DateTime? dob, AppLocalizations l10n) {
    if (dob == null) return l10n.unknown;
    int years = DateTime.now().year - dob.year;
    final now = DateTime.now();
    if (now.month < dob.month ||
        (now.month == dob.month && now.day < dob.day)) {
      years--;
    }
    return years.toString();
  }

  Future<bool> _isUserBlocked(String currentUid) async {
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(currentUid)
        .get();

    final data = snap.data();
    if (data == null) return false;

    final blocked =
        (data['blockedUserIds'] as List?)?.cast<String>() ?? const <String>[];
    return blocked.contains(widget.userId);
  }

  Future<void> _toggleBlockUser(
      BuildContext context, {
        required String currentUid,
        required bool currentlyBlocked,
      }) async {
    final l10n = AppLocalizations.of(context)!;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(currentlyBlocked ? 'Unblock user' : 'Block user'),
        content: Text(
          currentlyBlocked
              ? 'Do you want to unblock this user? You will be able to receive messages from them again.'
              : 'Do you want to block this user? You will no longer receive messages from them in MW Chat.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              currentlyBlocked ? 'Unblock' : 'Block',
              style: TextStyle(
                color: currentlyBlocked ? Colors.blue : Colors.red,
              ),
            ),
          ),
        ],
      ),
    ) ??
        false;

    if (!confirm) return;

    setState(() => _isBlocking = true);
    try {
      final ref =
      FirebaseFirestore.instance.collection('users').doc(currentUid);

      await ref.update({
        'blockedUserIds': currentlyBlocked
            ? FieldValue.arrayRemove([widget.userId])
            : FieldValue.arrayUnion([widget.userId]),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            currentlyBlocked
                ? 'User unblocked.'
                : 'User blocked successfully.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Failed to update block status. Please try again.',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isBlocking = false);
      }
    }
  }

  Future<void> _reportUser(
      BuildContext context, {
        required String currentUid,
      }) async {
    final l10n = AppLocalizations.of(context)!;
    final reasonCtrl = TextEditingController();

    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Report user'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Please describe why you are reporting this user. '
                  'For example: spam, bullying, hate speech, or other abusive content.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Describe the problem…',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(ctx).pop(reasonCtrl.text.trim().isEmpty
                    ? null
                    : reasonCtrl.text.trim()),
            child: const Text('Submit'),
          ),
        ],
      ),
    );

    if (reason == null) return;

    setState(() => _isReporting = true);
    try {
      await FirebaseFirestore.instance.collection('contentReports').add({
        'type': 'user',
        'reportedUserId': widget.userId,
        'reporterUserId': currentUid,
        'reason': reason,
        'createdAt': FieldValue.serverTimestamp(),
        'status': 'open',
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Report submitted. We will review it.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to submit report. Please try again.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isReporting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final currentUser = FirebaseAuth.instance.currentUser;
    final currentUid = currentUser?.uid;
    final isSelf = currentUid == widget.userId;

    return Scaffold(
      backgroundColor: kBgColor,
      appBar: AppBar(
        backgroundColor: kSurfaceColor,
        title: Text(
          l10n.userProfileTitle,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
        elevation: 0,
      ),
      body: MwBackground(
        child: Center(
          child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('users')
                .doc(widget.userId)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const _ShimmerLoader();
              }
              if (!snapshot.hasData || !snapshot.data!.exists) {
                return Center(
                  child: Text(
                    l10n.userNotFound,
                    style: const TextStyle(color: Colors.white70),
                  ),
                );
              }

              final data = snapshot.data!.data()!;
              final firstName = data['firstName'] ?? '';
              final lastName = data['lastName'] ?? '';
              final fullName = '$firstName $lastName'.trim();
              final avatarType = data['avatarType'] ?? 'bear';
              final profileUrl = data['profileUrl'] ?? '';
              final gender = data['gender'] ?? '';
              final isActive = data['isActive'] != false;

              // --- Block relationship (from their POV) ---
              final List<dynamic>? theirBlockedRaw =
              data['blockedUserIds'] as List<dynamic>?;
              final bool hasBlockedMe = currentUid != null &&
                  (theirBlockedRaw
                      ?.whereType<String>()
                      .contains(currentUid) ??
                      false);

              // --- Presence (respect blocking + TTL) ---
              final rawIsOnline = data['isOnline'] == true && isActive;
              final lastSeen = data['lastSeen'] is Timestamp
                  ? data['lastSeen'] as Timestamp
                  : null;

              final rawEffectiveOnline = _isOnlineWithTtl(
                rawIsOnline: rawIsOnline,
                lastSeen: lastSeen,
              );

              // If they blocked me, I should never see them as online.
              final effectiveOnline =
              hasBlockedMe ? false : rawEffectiveOnline;

              final (presenceLabel, presenceColor) = _buildPresenceStatus(
                l10n,
                isActive: isActive,
                effectiveOnline: effectiveOnline,
              );

              // --- DOB / Age ---
              DateTime? dob;
              final rawBirthday = data['birthday'];
              if (rawBirthday is Timestamp) {
                dob = rawBirthday.toDate();
              } else if (rawBirthday is String) {
                dob = DateTime.tryParse(rawBirthday);
              }

              final ageLabel = _ageLabel(dob, l10n);
              final birthdayLabel = dob != null
                  ? DateFormat.yMMMd(l10n.localeName).format(dob)
                  : l10n.unknown;

              // --- Avatar (hide real avatar if they blocked me) ---
              final bool hideRealAvatar = hasBlockedMe;
              final String avatarKey = hideRealAvatar
                  ? 'blocked-avatar'
                  : (profileUrl.isNotEmpty ? profileUrl : avatarType);

              Widget avatar = AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: (!hideRealAvatar && profileUrl.isNotEmpty)
                    ? CircleAvatar(
                  key: ValueKey(avatarKey),
                  radius: 60,
                  backgroundImage: NetworkImage(profileUrl),
                )
                    : CircleAvatar(
                  key: ValueKey(avatarKey),
                  radius: 60,
                  backgroundColor: kSurfaceAltColor,
                  child: Text(
                    (!hideRealAvatar && avatarType == 'smurf')
                        ? '🧜‍♀️'
                        : '🐻',
                    style: const TextStyle(fontSize: 42),
                  ),
                ),
              );

              // --- Card Content ---
              return SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                physics: const BouncingScrollPhysics(),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Container(
                      decoration: BoxDecoration(
                        color: kSurfaceAltColor,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: kBorderColor, width: 0.8),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            kSurfaceColor,
                            kSurfaceAltColor.withOpacity(0.9),
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.4),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          avatar,
                          const SizedBox(height: 16),
                          Text(
                            fullName.isNotEmpty ? fullName : l10n.unknown,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 14),
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 350),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 6),
                            decoration: BoxDecoration(
                              color: presenceColor.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                  color: presenceColor.withOpacity(0.7)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.circle,
                                    size: 10, color: presenceColor),
                                const SizedBox(width: 6),
                                Text(
                                  presenceLabel,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: presenceColor,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // Optional: small hint when they blocked you
                          if (hasBlockedMe) ...[
                            const SizedBox(height: 8),
                            Text(
                              'This user has limited what you can see.',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                color: Colors.white60,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],

                          const SizedBox(height: 28),
                          const Divider(color: Colors.white24, thickness: 0.5),
                          const SizedBox(height: 20),
                          _InfoRow(
                            icon: Icons.cake_outlined,
                            label: l10n.ageLabel,
                            value: ageLabel,
                          ),
                          const SizedBox(height: 12),
                          _InfoRow(
                            icon: Icons.calendar_today_outlined,
                            label: l10n.birthdayLabel,
                            value: birthdayLabel,
                          ),
                          const SizedBox(height: 12),
                          _InfoRow(
                            icon: Icons.person_outline,
                            label: l10n.genderLabel,
                            value: gender.isEmpty
                                ? l10n.notSpecified
                                : gender[0].toUpperCase() +
                                gender.substring(1),
                          ),

                          // ===== Safety actions: Block & Report =====
                          if (!isSelf && currentUid != null) ...[
                            const SizedBox(height: 28),
                            const Divider(
                                color: Colors.white24, thickness: 0.5),
                            const SizedBox(height: 12),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'Safety tools',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                  color: Colors.white70,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            FutureBuilder<bool>(
                              future: _isUserBlocked(currentUid),
                              builder: (context, blockSnap) {
                                final isBlocked = blockSnap.data ?? false;

                                return Column(
                                  children: [
                                    SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton.icon(
                                        onPressed: _isBlocking
                                            ? null
                                            : () => _toggleBlockUser(
                                          context,
                                          currentUid: currentUid,
                                          currentlyBlocked: isBlocked,
                                        ),
                                        icon: Icon(
                                          isBlocked
                                              ? Icons.person_remove_alt_1
                                              : Icons.block,
                                        ),
                                        label: Text(
                                          isBlocked
                                              ? 'Unblock user'
                                              : 'Block user',
                                        ),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: isBlocked
                                              ? Colors.blueGrey
                                              : Colors.redAccent,
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 12,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                            BorderRadius.circular(12),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    SizedBox(
                                      width: double.infinity,
                                      child: OutlinedButton.icon(
                                        onPressed: _isReporting
                                            ? null
                                            : () => _reportUser(
                                          context,
                                          currentUid: currentUid,
                                        ),
                                        icon:
                                        const Icon(Icons.flag_outlined),
                                        label: const Text('Report user'),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor:
                                          Colors.orangeAccent,
                                          side: const BorderSide(
                                              color: Colors.orangeAccent),
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 12,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                            BorderRadius.circular(12),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.white70),
        const SizedBox(width: 10),
        Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: Colors.white70,
            fontSize: 14,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.w500,
            color: Colors.white,
          ),
        ),
      ],
    );
  }
}

class _ShimmerLoader extends StatelessWidget {
  const _ShimmerLoader();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 100,
        height: 100,
        decoration: const BoxDecoration(
          color: kSurfaceAltColor,
          shape: BoxShape.circle,
        ),
        child: const Padding(
          padding: EdgeInsets.all(20),
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Colors.white70,
          ),
        ),
      ),
    );
  }
}
