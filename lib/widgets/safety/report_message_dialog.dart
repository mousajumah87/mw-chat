// lib/widgets/safety/report_message_dialog.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../ui/mw_feedback.dart';

class ReportMessageDialog {
  static Future<void> open(
      BuildContext context, {
        required String roomId,
        required DocumentSnapshot<Map<String, dynamic>> messageDoc,
      }) async {
    final l10n = AppLocalizations.of(context);
    if (l10n == null) return;

    await showDialog<void>(
      context: context,
      useRootNavigator: true,
      builder: (_) => _ReportMessageDialogContent(
        roomId: roomId,
        messageDoc: messageDoc,
      ),
    );
  }
}

class _ReportMessageDialogContent extends StatefulWidget {
  final String roomId;
  final DocumentSnapshot<Map<String, dynamic>> messageDoc;

  const _ReportMessageDialogContent({
    required this.roomId,
    required this.messageDoc,
  });

  @override
  State<_ReportMessageDialogContent> createState() =>
      _ReportMessageDialogContentState();
}

class _ReportMessageDialogContentState extends State<_ReportMessageDialogContent> {
  late final TextEditingController _reasonController;

  String? _selectedCategory;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _reasonController = TextEditingController();
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  List<String> _reasonCategories(AppLocalizations l10n) => <String>[
    l10n.reasonHarassment,
    l10n.reasonSpam,
    l10n.reasonHate,
    l10n.reasonSexual,
    l10n.reasonOther,
  ];

  InputDecoration _fieldDecoration(
      BuildContext context, {
        required String label,
        String? hint,
      }) {
    // Build InputDecoration (Flutter will merge with theme.inputDecorationTheme).
    return InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: kSurfaceAltColor.withOpacity(0.65),
    );
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    if (l10n == null) return;

    if (_saving || _selectedCategory == null) return;

    // Capture a safe root context BEFORE closing the dialog
    final rootCtx = Navigator.of(context, rootNavigator: true).context;

    String msg = l10n.generalErrorMessage;
    bool ok = false;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      msg = l10n.generalErrorMessage;
    } else {
      setState(() => _saving = true);

      final detailsRaw = _reasonController.text.trim();
      final details = detailsRaw.isEmpty ? null : detailsRaw;

      final data = widget.messageDoc.data() ?? const <String, dynamic>{};
      final type = (data['type'] ?? 'text').toString();

      try {
        await FirebaseFirestore.instance.collection('contentReports').add({
          'type': type,
          'roomId': widget.roomId,
          'messageId': widget.messageDoc.id,

          'senderId': data['senderId'],
          'senderEmail': data['senderEmail'],

          'reporterId': user.uid,
          'reasonCategory': _selectedCategory,
          'reasonDetails': details,

          // Keep this field if you use it elsewhere
          'reason': details == null ? _selectedCategory : '$_selectedCategory – $details',

          'text': (data['text'] ?? '').toString(),
          'fileUrl': data['fileUrl'],
          'fileName': data['fileName'],

          'createdAt': FieldValue.serverTimestamp(),
          'status': 'open',
        });

        ok = true;
        msg = l10n.reportSubmitted;
      } catch (e, st) {
        debugPrint('[ReportMessageDialog] submit error: $e\n$st');
        msg = l10n.generalErrorMessage;
      } finally {
        if (mounted) setState(() => _saving = false);
      }
    }

    // Close dialog first (prevents rebuild/dispose race)
    if (mounted) Navigator.of(context).pop();

    // Toast after close using safe root context
    if (!rootCtx.mounted) return;

    if (ok) {
      await MwFeedback.success(rootCtx, message: msg);
    } else {
      await MwFeedback.error(rootCtx, message: msg);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (l10n == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final media = MediaQuery.of(context);

    final maxDialogH = media.size.height * 0.72;
    final maxDialogW = media.size.width >= 520 ? 420.0 : media.size.width * 0.92;

    final canSave = _selectedCategory != null && !_saving;

    return AlertDialog(
      backgroundColor: kSurfaceAltColor,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: kBorderColor.withOpacity(0.55)),
      ),
      title: Text(
        l10n.reportMessageTitle,
        style: theme.textTheme.titleMedium?.copyWith(
          color: kTextPrimary,
          fontWeight: FontWeight.w700,
        ),
      ),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: maxDialogH,
          maxWidth: maxDialogW,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: _selectedCategory,
                isExpanded: true,
                dropdownColor: kSurfaceAltColor,
                iconEnabledColor: kTextSecondary,
                decoration: _fieldDecoration(
                  context,
                  label: l10n.reportUserReasonLabel,
                ),
                items: _reasonCategories(l10n)
                    .map(
                      (r) => DropdownMenuItem<String>(
                    value: r,
                    child: Text(
                      r,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: kTextPrimary,
                      ),
                    ),
                  ),
                )
                    .toList(),
                onChanged: _saving
                    ? null
                    : (val) => setState(() => _selectedCategory = val),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _reasonController,
                maxLines: 4,
                enabled: !_saving,
                style: theme.textTheme.bodyMedium?.copyWith(color: kTextPrimary),
                decoration: _fieldDecoration(
                  context,
                  label: l10n.reasonOther, // if you don't have it, see note below
                  hint: l10n.reportMessageHint,
                ),
              ),
              if (_saving) ...[
                const SizedBox(height: 14),
                const LinearProgressIndicator(
                  color: kGoldDeep,
                  backgroundColor: kBorderColor,
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: Text(
            l10n.cancel,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: kTextSecondary.withOpacity(0.95),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        TextButton(
          onPressed: canSave ? _submit : null,
          child: _saving
              ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: kGoldDeep,
            ),
          )
              : Text(
            l10n.save,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: canSave ? kGoldDeep : kGoldDeep.withOpacity(0.4),
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}
