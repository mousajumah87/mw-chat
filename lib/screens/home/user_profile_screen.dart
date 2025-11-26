import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/ui/mw_background.dart';

class UserProfileScreen extends StatelessWidget {
  final String userId;

  const UserProfileScreen({super.key, required this.userId});

  static const int _onlineTtlSeconds = 300;

  String _buildAgeLabel(DateTime? dob, AppLocalizations l10n) {
    if (dob == null) return l10n.unknown;
    final now = DateTime.now();
    int years = now.year - dob.year;
    if (now.month < dob.month ||
        (now.month == dob.month && now.day < dob.day)) {
      years--;
    }
    return years.toString();
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
    if (!isActive) return (l10n.accountNotActive, Colors.orange);
    if (effectiveOnline) return (l10n.online, Colors.greenAccent.shade400);
    return (l10n.offline, Colors.grey);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(l10n.userProfileTitle),
        centerTitle: true,
        backgroundColor: Colors.black.withOpacity(0.5),
        elevation: 0,
      ),
      body: MwBackground(
        child: Center(
          child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('users')
                .doc(userId)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const CircularProgressIndicator();
              }
              if (!snapshot.hasData || !snapshot.data!.exists) {
                return Center(child: Text(l10n.userNotFound));
              }

              final data = snapshot.data!.data()!;
              final firstName = data['firstName'] ?? '';
              final lastName = data['lastName'] ?? '';
              final fullName = '$firstName $lastName'.trim();
              final avatarType = data['avatarType'] ?? 'bear';
              final profileUrl = data['profileUrl'] ?? '';
              final gender = data['gender'] ?? '';
              final isActive = data['isActive'] != false;

              // Online state
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

              // Birthday & Age
              DateTime? dob;
              final rawBirthday = data['birthday'];
              if (rawBirthday is Timestamp) {
                dob = rawBirthday.toDate();
              } else if (rawBirthday is String) {
                dob = DateTime.tryParse(rawBirthday);
              }

              final ageLabel = _buildAgeLabel(dob, l10n);
              final birthdayLabel = dob != null
                  ? DateFormat.yMMMd(l10n.localeName).format(dob)
                  : l10n.unknown;

              // Avatar
              Widget avatar;
              if (profileUrl.isNotEmpty) {
                avatar = CircleAvatar(
                  radius: 60,
                  backgroundImage: NetworkImage(profileUrl),
                );
              } else {
                final emoji = avatarType == 'smurf' ? '🧜‍♀️' : '🐻';
                avatar = CircleAvatar(
                  radius: 60,
                  backgroundColor: Colors.black.withOpacity(0.3),
                  child: Text(emoji, style: const TextStyle(fontSize: 42)),
                );
              }

              return SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0x660057FF),
                          Color(0x66FFB300),
                          Colors.transparent
                        ],
                      ),
                      color: Colors.black.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(color: Colors.white.withOpacity(0.1)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.6),
                          blurRadius: 40,
                          offset: const Offset(0, 20),
                        ),
                      ],
                    ),
                    child: Padding(
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
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.4),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                  color: presenceColor.withOpacity(0.8)),
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
                              value: ageLabel),
                          const SizedBox(height: 12),
                          _InfoRow(
                              icon: Icons.calendar_today_outlined,
                              label: l10n.birthdayLabel,
                              value: birthdayLabel),
                          const SizedBox(height: 12),
                          _InfoRow(
                              icon: Icons.person_outline,
                              label: l10n.genderLabel,
                              value: gender.isEmpty
                                  ? l10n.notSpecified
                                  : (gender[0].toUpperCase() +
                                  gender.substring(1))),
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
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.white70),
        const SizedBox(width: 10),
        Text(
          label,
          style: const TextStyle(fontSize: 14, color: Colors.white70),
        ),
        const Spacer(),
        Text(
          value,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: Colors.white,
          ),
        ),
      ],
    );
  }
}
