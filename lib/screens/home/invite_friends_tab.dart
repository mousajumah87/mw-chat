//lib/screens/home/invite_friends_tab.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:vibration/vibration.dart';

import '../../l10n/app_localizations.dart';
import '../../widgets/ui/mw_side_panel.dart';

class InviteFriendsTab extends StatefulWidget {
  const InviteFriendsTab({super.key});

  @override
  State<InviteFriendsTab> createState() => _InviteFriendsTabState();
}

class _InviteFriendsTabState extends State<InviteFriendsTab>
    with AutomaticKeepAliveClientMixin {
  bool _loadingContacts = true;
  bool _contactsPermissionDenied = false;
  List<Contact> _contacts = [];
  String _searchQuery = '';
  Timer? _debounce;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  Future<void> _loadContacts() async {
    if (kIsWeb) {
      setState(() {
        _loadingContacts = false;
        _contactsPermissionDenied = true;
      });
      return;
    }

    try {
      final granted = await FlutterContacts.requestPermission(readonly: true);
      if (!mounted) return;

      if (!granted) {
        setState(() {
          _contactsPermissionDenied = true;
          _loadingContacts = false;
        });
        return;
      }

      await Future.delayed(const Duration(milliseconds: 250));
      final contacts = await FlutterContacts.getContacts(
        withProperties: true,
        withThumbnail: true,
      );

      final filtered = contacts
          .where((c) => c.phones.isNotEmpty)
          .toList()
        ..sort((a, b) => a.displayName
            .toLowerCase()
            .compareTo(b.displayName.toLowerCase()));

      if (!mounted) return;
      setState(() {
        _contacts = filtered;
        _loadingContacts = false;
      });
    } catch (e, st) {
      debugPrint('Error loading contacts: $e\n$st');
      if (!mounted) return;
      setState(() {
        _contactsPermissionDenied = true;
        _loadingContacts = false;
      });
    }
  }

  Future<void> _sendInvite(Contact contact) async {
    final l10n = AppLocalizations.of(context)!;
    final name = contact.displayName;

    const androidLink =
        'https://play.google.com/store/apps/details?id=com.mw.chat';
    const iosLink = 'https://apps.apple.com/app/id1234567890';

    final message = l10n.inviteMessageTemplate(
      name,
      androidLink,
      iosLink,
    );

    if (!kIsWeb && (await Vibration.hasVibrator() ?? false)) {
      Vibration.vibrate(duration: 40);
    }

    await Share.share(message, subject: l10n.inviteSubject);

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.inviteSent(name)),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 220), () {
      if (mounted) setState(() => _searchQuery = query);
    });
  }

  Widget _buildContactTile(Contact c) {
    final name = c.displayName;
    final phone = c.phones.isNotEmpty ? c.phones.first.number : '';
    String initials = '';

    if (name.isNotEmpty) {
      final parts = name.trim().split(RegExp(r'\s+'));
      initials = parts.map((p) => p[0].toUpperCase()).take(2).join();
    }

    return Card(
      color: Colors.black.withOpacity(0.55),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.white.withOpacity(0.08)),
      ),
      child: ListTile(
        contentPadding:
        const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: CircleAvatar(
          radius: 22,
          backgroundColor: Colors.white.withOpacity(0.1),
          child: Text(
            initials,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Text(
          name,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          phone,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 12,
          ),
        ),
        trailing: IconButton(
          tooltip: AppLocalizations.of(context)!.invite,
          icon: const Icon(Icons.send_rounded, color: Colors.white70),
          onPressed: () => _sendInvite(c),
        ),
      ),
    );
  }

  Widget _buildContactsList() {
    final l10n = AppLocalizations.of(context)!;

    if (_loadingContacts) return const Center(child: CircularProgressIndicator());
    if (kIsWeb) return _buildMessage(l10n.inviteWebNotSupported);
    if (_contactsPermissionDenied) {
      return _buildMessageWithAction(
        text: l10n.contactsPermissionDenied,
        buttonLabel: l10n.retry,
        onPressed: _loadContacts,
      );
    }
    if (_contacts.isEmpty) return _buildMessage(l10n.noContactsFound);

    final query = _searchQuery.trim().toLowerCase();
    final filtered = query.isEmpty
        ? _contacts
        : _contacts.where((c) {
      final name = c.displayName.toLowerCase();
      final phone =
      c.phones.isNotEmpty ? c.phones.first.number.toLowerCase() : '';
      return name.contains(query) || phone.contains(query);
    }).toList();

    if (filtered.isEmpty) return _buildMessage(l10n.noContactsFound);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: TextField(
            onChanged: _onSearchChanged,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: l10n.search,
              hintStyle: const TextStyle(color: Colors.white54),
              prefixIcon: const Icon(Icons.search, color: Colors.white70),
              filled: true,
              fillColor: Colors.white.withOpacity(0.06),
              contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: Colors.white.withOpacity(0.15)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: Colors.white.withOpacity(0.35)),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: ListView.builder(
            physics: const BouncingScrollPhysics(),
            itemCount: filtered.length,
            itemBuilder: (context, index) => _buildContactTile(filtered[index]),
          ),
        ),
      ],
    );
  }

  Widget _buildMessage(String text) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24.0),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white70, fontSize: 14),
      ),
    ),
  );

  Widget _buildMessageWithAction({
    required String text,
    required String buttonLabel,
    required VoidCallback onPressed,
  }) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: onPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white.withOpacity(0.15),
              foregroundColor: Colors.white,
            ),
            child: Text(buttonLabel),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final contactsList = _buildContactsList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 900;

        // === MOBILE / NARROW layout ===
        if (!isWide) {
          // MOBILE / NARROW layout — scroll-safe, no overflow
          return SafeArea(
            child: LayoutBuilder(
              builder: (context, box) {
                return SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // === CONTACTS LIST ===
                        Container(
                          constraints: BoxConstraints(
                            // Responsive: contact list takes up to 65% of screen height
                            maxHeight: box.maxHeight * 0.65,
                          ),
                          child: ScrollConfiguration(
                            behavior: ScrollConfiguration.of(context)
                                .copyWith(scrollbars: false),
                            child: contactsList,
                          ),
                        ),

                        const SizedBox(height: 12),

                        // === MW CHAT PANEL BELOW ===
                        const RepaintBoundary(
                          child: MwSidePanel(),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        }

        // === DESKTOP / WIDE layout ===
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: ScrollConfiguration(
                behavior: ScrollConfiguration.of(context).copyWith(
                  scrollbars: false,
                  physics: const BouncingScrollPhysics(),
                ),
                child: contactsList,
              ),
            ),
            const SizedBox(width: 16),
            Flexible(
              flex: 2,
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Padding(
                  padding: const EdgeInsets.only(right: 12, top: 8),
                  child: RepaintBoundary(child: MwSidePanel()),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
