import 'package:cloud_firestore/cloud_firestore.dart';
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
    if (now.month < dob.month || (now.month == dob.month && now.day < dob.day)) {
      years--;
    }
    return years.toString();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

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

              final rawIsOnline = data['isOnline'] == true && isActive;
              final lastSeen = data['lastSeen'] is Timestamp
                  ? data['lastSeen'] as Timestamp
                  : null;
              final effectiveOnline =
              _isOnlineWithTtl(rawIsOnline: rawIsOnline, lastSeen: lastSeen);
              final (presenceLabel, presenceColor) = _buildPresenceStatus(
                l10n,
                isActive: isActive,
                effectiveOnline: effectiveOnline,
              );

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

              // --- Avatar Section ---
              Widget avatar = AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: profileUrl.isNotEmpty
                    ? CircleAvatar(
                  key: ValueKey(profileUrl),
                  radius: 60,
                  backgroundImage: NetworkImage(profileUrl),
                )
                    : CircleAvatar(
                  key: ValueKey(avatarType),
                  radius: 60,
                  backgroundColor: kSurfaceAltColor,
                  child: Text(
                    avatarType == 'smurf' ? '🧜‍♀️' : '🐻',
                    style: const TextStyle(fontSize: 42),
                  ),
                ),
              );

              // --- Card Content (no blur, solid layers) ---
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
                                : gender[0].toUpperCase() + gender.substring(1),
                          ),
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
