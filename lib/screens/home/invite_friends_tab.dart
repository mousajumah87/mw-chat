// lib/screens/home/invite_friends_tab.dart
// Invite Friends tab – polished UI, safe permissions, search over contacts.

import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../../l10n/app_localizations.dart';
import '../../widgets/ui/mw_side_panel.dart';

class InviteFriendsTab extends StatefulWidget {
  const InviteFriendsTab({super.key});

  @override
  State<InviteFriendsTab> createState() => _InviteFriendsTabState();
}

class _InviteFriendsTabState extends State<InviteFriendsTab> {
  bool _loadingContacts = true;
  bool _contactsPermissionDenied = false;
  List<Contact> _contacts = [];
  String _searchQuery = '';

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
      // Ask for permission
      final granted = await FlutterContacts.requestPermission(readonly: true);
      if (!mounted) return;

      if (!granted) {
        setState(() {
          _contactsPermissionDenied = true;
          _loadingContacts = false;
        });
        return;
      }

      // Load contacts with phone numbers
      final contacts = await FlutterContacts.getContacts(
        withProperties: true,
        withThumbnail: true,
      );
      if (!mounted) return;

      final withPhones =
      contacts.where((c) => c.phones.isNotEmpty).toList()
        ..sort((a, b) =>
            a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));

      setState(() {
        _contacts = withPhones;
        _loadingContacts = false;
      });
    } catch (e, st) {
      // In case the plugin throws, just show a friendly error state
      debugPrint('Error loading contacts: $e\n$st');
      if (!mounted) return;
      setState(() {
        _contactsPermissionDenied = true;
        _loadingContacts = false;
      });
    }
  }

  void _sendInvite(Contact contact) {
    final l10n = AppLocalizations.of(context)!;
    final name = contact.displayName;

    // TODO: replace with your real store links when published
    const androidLink =
        'https://play.google.com/store/apps/details?id=com.mw.chat';
    const iosLink = 'https://apps.apple.com/app/id1234567890';

    final message = l10n.inviteMessageTemplate(
      name,
      androidLink,
      iosLink,
    );

    Share.share(
      message,
      subject: l10n.inviteSubject,
    );
  }

  Widget _buildContactTile(Contact c) {
    final name = c.displayName;
    final phone = c.phones.isNotEmpty ? c.phones.first.number : '';

    String initials = '';
    if (name.isNotEmpty) {
      final parts = name.trim().split(RegExp(r'\s+'));
      initials = parts.map((p) => p[0].toUpperCase()).take(2).join();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Card(
        color: Colors.black.withOpacity(0.6),
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.white.withOpacity(0.08)),
        ),
        child: ListTile(
          leading: CircleAvatar(
            radius: 24,
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
          trailing: ElevatedButton.icon(
            onPressed: () => _sendInvite(c),
            icon: const Icon(Icons.share, size: 16),
            label: Text(AppLocalizations.of(context)!.invite),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white.withOpacity(0.15),
              foregroundColor: Colors.white,
              textStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContactsList() {
    final l10n = AppLocalizations.of(context)!;

    if (_loadingContacts) {
      return const Center(child: CircularProgressIndicator());
    }

    if (kIsWeb) {
      return _buildMessage(l10n.inviteWebNotSupported);
    }

    if (_contactsPermissionDenied) {
      return _buildMessage(l10n.contactsPermissionDenied);
    }

    if (_contacts.isEmpty) {
      return _buildMessage(l10n.noContactsFound);
    }

    final query = _searchQuery.trim().toLowerCase();
    final filtered = query.isEmpty
        ? _contacts
        : _contacts.where((c) {
      final name = c.displayName.toLowerCase();
      final phone = c.phones.isNotEmpty
          ? c.phones.first.number.toLowerCase()
          : '';
      return name.contains(query) || phone.contains(query);
    }).toList();

    if (filtered.isEmpty) {
      // Re-use the same string for "no matches"
      return _buildMessage(l10n.noContactsFound);
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: TextField(
            onChanged: (value) {
              setState(() {
                _searchQuery = value;
              });
            },
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: l10n.search ?? 'Search contacts',
              hintStyle: const TextStyle(color: Colors.white54),
              prefixIcon: const Icon(Icons.search, color: Colors.white70),
              filled: true,
              fillColor: Colors.white.withOpacity(0.06),
              contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide:
                BorderSide(color: Colors.white.withOpacity(0.15)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide:
                BorderSide(color: Colors.white.withOpacity(0.15)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide:
                BorderSide(color: Colors.white.withOpacity(0.35)),
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: filtered.length,
            separatorBuilder: (_, __) => const SizedBox(height: 6),
            itemBuilder: (context, index) => _buildContactTile(filtered[index]),
          ),
        ),
      ],
    );
  }

  Widget _buildMessage(String text) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final contactsList = _buildContactsList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 900;

        // Phone / narrow layout: MW card on top, contacts underneath
        if (!isWide) {
          return Column(
            children: [
              const Padding(
                padding: EdgeInsets.all(12),
                child: MwSidePanel(),
              ),
              Expanded(child: contactsList),
            ],
          );
        }

        // Wide layout: contacts left, card right
        return Row(
          children: [
            Expanded(flex: 3, child: contactsList),
            const SizedBox(width: 16),
            const SizedBox(
              width: 320,
              child: MwSidePanel(),
            ),
          ],
        );
      },
    );
  }
}
