// lib/screens/home/invite_friends_tab.dart
// Invite Friends tab – polished UI & proper contacts loading/permissions.

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

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  Future<void> _loadContacts() async {
    // Web: contacts plugin is not supported – show info message.
    if (kIsWeb) {
      setState(() {
        _loadingContacts = false;
        _contactsPermissionDenied = true;
      });
      return;
    }

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

    final withPhones = contacts.where((c) => c.phones.isNotEmpty).toList();

    setState(() {
      _contacts = withPhones;
      _loadingContacts = false;
    });
  }

  void _sendInvite(Contact contact) {
    final l10n = AppLocalizations.of(context)!;
    final name = contact.displayName;

    // TODO: replace with your real store links when published
    const androidLink =
        'https://play.google.com/store/apps/details?id=com.mw.chat';
    const iosLink = 'https://apps.apple.com/app/id1234567890';

    // Call the generated localization function with parameters
    final message = l10n.inviteMessageTemplate(
      name,
      androidLink,
      iosLink,
    );

    // You can keep this (warning is just deprecation, not an error)
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
      // On web we just show an info message.
      return _buildMessage(l10n.inviteWebNotSupported);
    }

    if (_contactsPermissionDenied) {
      return _buildMessage(l10n.contactsPermissionDenied);
    }

    if (_contacts.isEmpty) {
      return _buildMessage(l10n.noContactsFound);
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _contacts.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (context, index) => _buildContactTile(_contacts[index]),
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

        // Phone / narrow layout: card on top, contacts list under it
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

        // Wide layout (tablet/web): contacts on left, side panel on right
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
