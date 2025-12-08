// lib/screens/home/user_profile_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../widgets/ui/mw_background.dart';

class UserProfileScreen extends StatefulWidget {
  final String userId;
  const UserProfileScreen({super.key, required this.userId});

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen>
    with SingleTickerProviderStateMixin {
  static const int _onlineTtlSeconds = 300;
  static const String _appVersion = 'v1.0';
  static const String _websiteUrl = 'https://www.mwchats.com';

  bool _isBlocking = false;
  bool _isReporting = false;

  late final AnimationController _glowController;

  @override
  void initState() {
    super.initState();
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _glowController.dispose();
    super.dispose();
  }

  Future<void> _openMwWebsite() async {
    final uri = Uri.parse(_websiteUrl);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      debugPrint('Could not launch $_websiteUrl');
    }
  }

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
    if (effectiveOnline) return (l10n.online, kAccentColor);
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
        backgroundColor: kSurfaceAltColor,
        shape:
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          currentlyBlocked
              ? l10n.profileBlockDialogTitleUnblock
              : l10n.profileBlockDialogTitleBlock,
          style: const TextStyle(color: Colors.white),
        ),
        content: Text(
          currentlyBlocked
              ? l10n.profileBlockDialogBodyUnblock
              : l10n.profileBlockDialogBodyBlock,
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              l10n.cancel,
              style: const TextStyle(color: Colors.white70),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              currentlyBlocked
                  ? l10n.profileBlockDialogConfirmUnblock
                  : l10n.profileBlockDialogConfirmBlock,
              style: TextStyle(
                color: currentlyBlocked ? kPrimaryBlue : Colors.redAccent,
                fontWeight: FontWeight.w600,
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
                ? l10n.profileBlockSnackbarUnblocked
                : l10n.profileBlockSnackbarBlocked,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isBlocking = false);
    }
  }

  Future<void> _reportUser(
      BuildContext context, {
        required String currentUid,
      }) async {
    final l10n = AppLocalizations.of(context)!;
    final reasonController = TextEditingController();

    final List<String> reasonCategories = <String>[
      l10n.reasonHarassment,
      l10n.reasonSpam,
      l10n.reasonHate,
      l10n.reasonSexual,
      l10n.reasonOther,
    ];

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        String? selectedCategory;

        return StatefulBuilder(
          builder: (context, setState) {
            final bool canSave = selectedCategory != null;

            return AlertDialog(
              backgroundColor: kSurfaceAltColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Text(
                l10n.reportUserTitle,
                style: const TextStyle(color: Colors.white),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    value: selectedCategory,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: l10n.reportUserReasonLabel,
                      border: const OutlineInputBorder(),
                      filled: true,
                      fillColor: kSurfaceColor.withOpacity(0.4),
                    ),
                    items: reasonCategories
                        .map(
                          (r) => DropdownMenuItem<String>(
                        value: r,
                        child: Text(r),
                      ),
                    )
                        .toList(),
                    onChanged: (val) {
                      setState(() {
                        selectedCategory = val;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: reasonController,
                    maxLines: 4,
                    decoration: InputDecoration(
                      hintText: l10n.reportUserHint,
                      filled: true,
                      fillColor: kSurfaceColor.withOpacity(0.4),
                      border: const OutlineInputBorder(),
                    ),
                    style: const TextStyle(color: Colors.white),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: Text(
                    l10n.cancel,
                    style: const TextStyle(color: Colors.white70),
                  ),
                ),
                TextButton(
                  onPressed: !canSave
                      ? null
                      : () async {
                    setState(() => _isReporting = true);

                    final details =
                    reasonController.text.trim().isEmpty
                        ? null
                        : reasonController.text.trim();

                    try {
                      await FirebaseFirestore.instance
                          .collection('userReports')
                          .add({
                        'reporterId': currentUid,
                        'reportedUserId': widget.userId,
                        'reasonCategory': selectedCategory,
                        'reasonDetails': details,
                        'createdAt': FieldValue.serverTimestamp(),
                        'status': 'open',
                      });
                    } catch (e, st) {
                      debugPrint(
                          '[UserProfile] report error: $e\n$st');
                    } finally {
                      if (mounted) {
                        setState(() => _isReporting = false);
                      }
                    }

                    if (dialogContext.mounted) {
                      Navigator.of(dialogContext).pop();
                    }

                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(l10n.reportSubmitted),
                        ),
                      );
                    }
                  },
                  child: Text(
                    l10n.save,
                    style: TextStyle(
                      color: canSave
                          ? kSecondaryAmber
                          : kSecondaryAmber.withOpacity(0.4),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildFooter(
      BuildContext context,
      AppLocalizations l10n, {
        required bool isWide,
      }) {
    final theme = Theme.of(context);
    final textStyle = theme.textTheme.bodySmall?.copyWith(
      color: Colors.white70,
      fontSize: 11,
    );
    final versionStyle = textStyle?.copyWith(
      color: Colors.white38,
    );

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: isWide ? 16 : 12,
        vertical: 8,
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 4,
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            l10n.appBrandingBeta,
            style: textStyle,
            textAlign: TextAlign.center,
          ),
          Text(
            _appVersion,
            style: versionStyle,
            textAlign: TextAlign.center,
          ),
          InkWell(
            onTap: _openMwWebsite,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Text(
                'mwchats.com',
                style: textStyle?.copyWith(
                  decoration: TextDecoration.underline,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final currentUser = FirebaseAuth.instance.currentUser;
    final currentUid = currentUser?.uid;
    final isSelf = currentUid == widget.userId;

    final media = MediaQuery.of(context);
    final width = media.size.width;
    final isWide = width >= 900;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black.withOpacity(0.85),
        elevation: 0,
        centerTitle: true,
        title: Text(
          l10n.userProfileTitle,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        leading: Navigator.of(context).canPop()
            ? IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.white,
            size: 20,
          ),
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
                  const SizedBox(height: 12),
                  Expanded(
                    child: Container(
                      margin: EdgeInsets.symmetric(
                        horizontal: isWide ? 16 : 12,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.65),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.08),
                        ),
                      ),
                      child: StreamBuilder<
                          DocumentSnapshot<Map<String, dynamic>>>(
                        stream: FirebaseFirestore.instance
                            .collection('users')
                            .doc(widget.userId)
                            .snapshots(),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const _ShimmerLoader();
                          }
                          if (!snapshot.hasData ||
                              !snapshot.data!.exists) {
                            return Center(
                              child: Text(
                                l10n.userNotFound,
                                style: const TextStyle(
                                  color: Colors.white70,
                                ),
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

                          final theirBlocked =
                              (data['blockedUserIds'] as List?)
                                  ?.cast<String>() ??
                                  [];
                          final hasBlockedMe = currentUid != null &&
                              theirBlocked.contains(currentUid);

                          final rawIsOnline =
                              data['isOnline'] == true && isActive;
                          final lastSeen = data['lastSeen'] is Timestamp
                              ? data['lastSeen'] as Timestamp
                              : null;
                          final effectiveOnline = !hasBlockedMe &&
                              _isOnlineWithTtl(
                                rawIsOnline: rawIsOnline,
                                lastSeen: lastSeen,
                              );

                          final (presenceLabel, presenceColor) =
                          _buildPresenceStatus(
                            l10n,
                            isActive: isActive,
                            effectiveOnline: effectiveOnline,
                          );

                          DateTime? dob;
                          final rawBirthday = data['birthday'];
                          if (rawBirthday is Timestamp) {
                            dob = rawBirthday.toDate();
                          }
                          final ageLabel = _ageLabel(dob, l10n);
                          final birthdayLabel = dob != null
                              ? DateFormat.yMMMd(l10n.localeName)
                              .format(dob)
                              : l10n.unknown;

                          // Avatar with glow
                          final avatar = Stack(
                            alignment: Alignment.center,
                            children: [
                              AnimatedBuilder(
                                animation: _glowController,
                                builder: (_, __) {
                                  final glow = _glowController.value;
                                  return Container(
                                    width: 130,
                                    height: 130,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      gradient: RadialGradient(
                                        colors: [
                                          kPrimaryBlue.withOpacity(
                                              0.3 + glow * 0.2),
                                          kSecondaryAmber.withOpacity(
                                              0.2 + glow * 0.2),
                                          Colors.transparent,
                                        ],
                                        stops: const [0.4, 0.8, 1],
                                      ),
                                    ),
                                  );
                                },
                              ),
                              CircleAvatar(
                                radius: 58,
                                backgroundColor: kSurfaceAltColor,
                                backgroundImage: profileUrl.isNotEmpty
                                    ? NetworkImage(profileUrl)
                                    : null,
                                child: profileUrl.isEmpty
                                    ? Text(
                                  avatarType == 'smurf'
                                      ? '🧜‍♀️'
                                      : '🐻',
                                  style: const TextStyle(fontSize: 42),
                                )
                                    : null,
                              ),
                            ],
                          );

                          return SingleChildScrollView(
                            physics: const BouncingScrollPhysics(),
                            padding: const EdgeInsets.all(24),
                            child: Align(
                              alignment: Alignment.topCenter,
                              child: ConstrainedBox(
                                constraints:
                                const BoxConstraints(maxWidth: 540),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    avatar,
                                    const SizedBox(height: 16),
                                    Text(
                                      fullName.isNotEmpty
                                          ? fullName
                                          : l10n.unknown,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 24,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 12),
                                    AnimatedContainer(
                                      duration: const Duration(
                                          milliseconds: 400),
                                      padding:
                                      const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: presenceColor
                                            .withOpacity(0.20),
                                        borderRadius:
                                        BorderRadius.circular(20),
                                        border: Border.all(
                                          color: presenceColor
                                              .withOpacity(0.8),
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: presenceColor
                                                .withOpacity(0.35),
                                            blurRadius: 10,
                                            spreadRadius: 1,
                                          ),
                                        ],
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.circle,
                                            size: 10,
                                            color: presenceColor,
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            presenceLabel,
                                            style: TextStyle(
                                              color: presenceColor,
                                              fontWeight:
                                              FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (hasBlockedMe) ...[
                                      const SizedBox(height: 10),
                                      Text(
                                        l10n
                                            .profileBlockedUserHintLimitedVisibility,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                          color: Colors.white60,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ],
                                    const SizedBox(height: 24),
                                    const Divider(
                                        color: Colors.white24),
                                    const SizedBox(height: 16),
                                    _InfoRow(
                                      icon: Icons.cake_outlined,
                                      label: l10n.ageLabel,
                                      value: ageLabel,
                                    ),
                                    const SizedBox(height: 10),
                                    _InfoRow(
                                      icon: Icons
                                          .calendar_today_outlined,
                                      label: l10n.birthdayLabel,
                                      value: birthdayLabel,
                                    ),
                                    const SizedBox(height: 10),
                                    _InfoRow(
                                      icon: Icons.person_outline,
                                      label: l10n.genderLabel,
                                      value: gender.isEmpty
                                          ? l10n.notSpecified
                                          : gender[0].toUpperCase() +
                                          gender.substring(1),
                                    ),
                                    if (!isSelf &&
                                        currentUid != null) ...[
                                      const SizedBox(height: 28),
                                      const Divider(
                                          color: Colors.white24),
                                      const SizedBox(height: 12),
                                      Align(
                                        alignment: Alignment.centerLeft,
                                        child: Text(
                                          l10n
                                              .profileSafetyToolsSectionTitle,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyMedium
                                              ?.copyWith(
                                            color: Colors.white70,
                                            fontWeight:
                                            FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                      FutureBuilder<bool>(
                                        future:
                                        _isUserBlocked(currentUid),
                                        builder:
                                            (context, blockSnap) {
                                          final isBlocked =
                                              blockSnap.data ?? false;
                                          return Column(
                                            children: [
                                              SizedBox(
                                                width: double.infinity,
                                                child:
                                                ElevatedButton.icon(
                                                  onPressed: _isBlocking
                                                      ? null
                                                      : () =>
                                                      _toggleBlockUser(
                                                        context,
                                                        currentUid:
                                                        currentUid,
                                                        currentlyBlocked:
                                                        isBlocked,
                                                      ),
                                                  icon: Icon(
                                                    isBlocked
                                                        ? Icons
                                                        .person_remove
                                                        : Icons.block,
                                                    size: 18,
                                                  ),
                                                  label: Text(
                                                    isBlocked
                                                        ? l10n
                                                        .profileBlockButtonUnblock
                                                        : l10n
                                                        .profileBlockButtonBlock,
                                                  ),
                                                  style: ElevatedButton
                                                      .styleFrom(
                                                    backgroundColor:
                                                    isBlocked
                                                        ? Colors.red
                                                        .withOpacity(
                                                        0.45)
                                                        : Colors
                                                        .redAccent,
                                                    foregroundColor:
                                                    Colors.white,
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                      vertical: 12,
                                                    ),
                                                    shape:
                                                    RoundedRectangleBorder(
                                                      borderRadius:
                                                      BorderRadius
                                                          .circular(
                                                          24),
                                                    ),
                                                    elevation: 6,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(height: 10),
                                              SizedBox(
                                                width: double.infinity,
                                                child:
                                                OutlinedButton.icon(
                                                  onPressed: _isReporting
                                                      ? null
                                                      : () =>
                                                      _reportUser(
                                                        context,
                                                        currentUid:
                                                        currentUid,
                                                      ),
                                                  icon: const Icon(
                                                    Icons.flag_outlined,
                                                    size: 18,
                                                  ),
                                                  label: Text(
                                                    l10n
                                                        .profileReportButtonLabel,
                                                  ),
                                                  style:
                                                  OutlinedButton
                                                      .styleFrom(
                                                    foregroundColor:
                                                    kSecondaryAmber,
                                                    side:
                                                    const BorderSide(
                                                      color:
                                                      kSecondaryAmber,
                                                      width: 1.4,
                                                    ),
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                      vertical: 12,
                                                    ),
                                                    shape:
                                                    RoundedRectangleBorder(
                                                      borderRadius:
                                                      BorderRadius
                                                          .circular(
                                                          24),
                                                    ),
                                                    backgroundColor:
                                                    Colors.black
                                                        .withOpacity(
                                                        0.35),
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
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  _buildFooter(context, l10n, isWide: isWide),
                ],
              ),
            ),
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
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: Colors.white70, fontSize: 14),
        ),
        const Spacer(),
        Text(
          value,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w600,
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
