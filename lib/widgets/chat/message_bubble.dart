// lib/widgets/chat/message_bubble.dart
import 'dart:async';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // ✅ haptics (kept)
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../utils/mw_linkify.dart'; // ✅ linkify in util
import 'message_reactions.dart';
import 'mw_audio_hub.dart';
import 'mw_token_text.dart'; // ✅ IMPORTANT: unified token rendering

class MessageBubble extends StatefulWidget {
  final String messageId; // ✅ REQUIRED
  final String text;
  final String timeLabel;
  final bool isMe;
  final bool isSeen;

  final String? fileUrl;
  final String? fileName;
  final String? fileType; // "image", "video", "audio", "file", "voice"

  /// ✅ NEW: Firestore stored thumbnail url for videos (aligned with chat_message_list.dart)
  /// ✅ Video thumbnail url (supports multiple firestore keys)
  final String? thumbUrl; // newest / preferred
  final String? thumbnailUrl; // legacy
  final String? videoThumbUrl; // legacy

  /// ✅ Call event payload (stored on message doc)
  final Map<String, dynamic>? callInfo;

  final bool showTimestamp;

  /// Reply payload saved on message doc.
  final Object? replyTo;

  // Reactions
  final String? currentUserId;
  final Map<String, dynamic>? reactions; // Firestore map: {emoji: [uids]}

  /// Async reaction writer (Firestore transaction in parent)
  final Future<void> Function(String emoji)? onReactionTapAsync;

  /// ✅ NEW: after reaction is committed, ask parent to clear selection/header.
  final VoidCallback? onReactionCommitted;

  /// ✅ Tap reply-preview to scroll/jump to original message.
  final ValueChanged<String>? onReplyPreviewTap;

  // ✅ WhatsApp-style selection state + callbacks
  final bool isSelected;
  final VoidCallback? onBubbleLongPress;
  final VoidCallback? onBubbleTap;

  /// ✅ Swipe-to-reply
  final VoidCallback? onSwipeReply;

  /// ✅ When selection mode is active, disable swipe reply
  final bool disableSwipeReply;

  /// ✅ NEW: if parent passes explicit deleted state.
  final bool isDeleted;

  const MessageBubble({
    super.key,
    required this.messageId,
    required this.text,
    required this.timeLabel,
    required this.isMe,
    required this.isSeen,
    this.fileUrl,
    this.fileName,
    this.fileType,

    // ✅ thumbnails (support all possible keys)
    this.thumbUrl,
    this.thumbnailUrl,
    this.videoThumbUrl,

    // ✅ call
    this.callInfo,

    this.showTimestamp = true,
    this.replyTo,
    this.currentUserId,
    this.reactions,
    this.onReactionTapAsync,
    this.onReactionCommitted,
    this.onReplyPreviewTap,
    this.isSelected = false,
    this.onBubbleLongPress,
    this.onBubbleTap,
    this.onSwipeReply,
    this.disableSwipeReply = false,
    this.isDeleted = false,
  });

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble>
    with AutomaticKeepAliveClientMixin {
  // ✅ Shared player (single instance) - DO NOT create per bubble
  late final AudioPlayer _player = MwAudioHub.instance.player;

  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration>? _durSub;
  StreamSubscription<void>? _completeSub;

  Duration _pos = Duration.zero;
  Duration _dur = Duration.zero;

  bool _playing = false;
  bool _loading = false;
  bool _audioError = false;

  String? _preparedUrl;

  static const double _mediaSize = 220;
  static const double _bubbleRadius = 16.0;

  // Font sizing
  static const double _msgFontSize = 16;
  static const double _msgLineHeight = 1.25;
  static const double _timestampFontSize = 11;
  static const double _fileTitleFontSize = 14;
  static const double _mediaTitleFontSize = 13;
  static const double _audioTitleFontSize = 14;
  static const double _audioTimeFontSize = 12;

  bool get hasAttachment => widget.fileUrl?.isNotEmpty == true;

  String get _typeLower => (widget.fileType ?? '').trim().toLowerCase();
  bool get isImage => _typeLower == 'image' || _typeLower.startsWith('image/');
  bool get isVideo => _typeLower == 'video' || _typeLower.startsWith('video/');
  bool get isAudio {
    final t = _typeLower;
    if (t == 'audio' || t.startsWith('audio/')) return true;
    if (t == 'voice' ||
        t == 'voice_note' ||
        t == 'voicenote' ||
        t == 'voice-message') return true;
    return false;
  }

  bool get isGenericFile => hasAttachment && !isImage && !isVideo && !isAudio;

  @override
  bool get wantKeepAlive => isAudio;

  // ✅ IMPORTANT:
  // In lists, State might be reused if parent doesn't supply stable keys.
  LayerLink _reactionLink = LayerLink();
  String _identitySig = '';

  // ✅ Swipe-to-reply state
  double _swipeDx = 0.0;
  bool _replyTriggered = false;
  static const double _replyTriggerDx = 56.0;
  static const double _replyMaxDx = 72.0;

  bool get _canSwipeReply =>
      !widget.disableSwipeReply && widget.onSwipeReply != null;

  void _resetSwipe() {
    _swipeDx = 0.0;
    _replyTriggered = false;
  }

  String get _resolvedThumbUrl {
    final a = (widget.thumbUrl ?? '').trim();
    if (a.isNotEmpty) return a;

    final b = (widget.thumbnailUrl ?? '').trim();
    if (b.isNotEmpty) return b;

    final c = (widget.videoThumbUrl ?? '').trim();
    if (c.isNotEmpty) return c;

    return '';
  }

  // ---------------------------------------------------------------------------
  // ✅ Call event rendering (reuse Call Logs style)
  // ---------------------------------------------------------------------------

  bool get isCallMessage => (widget.callInfo != null && widget.callInfo!.isNotEmpty);

  String _tCall(Object? v) => (v ?? '').toString().trim();

  String _callTypeLower() {
    final m = widget.callInfo ?? const <String, dynamic>{};
    final v = _tCall(m['callType']).isNotEmpty
        ? _tCall(m['callType'])
        : (_tCall(m['type']).isNotEmpty ? _tCall(m['type']) : _tCall(m['media']));
    final s = v.toLowerCase();
    if (s.contains('video')) return 'video';
    if (s.contains('audio')) return 'audio';
    return s;
  }

  String _callResultLower() {
    final m = widget.callInfo ?? const <String, dynamic>{};

    // Support multiple schemas:
    // - result: ended/missed/declined/canceled/busy
    // - status/callStatus
    // - endedReason / endReason
    final raw = _tCall(m['result']).isNotEmpty
        ? _tCall(m['result'])
        : (_tCall(m['callStatus']).isNotEmpty
        ? _tCall(m['callStatus'])
        : (_tCall(m['status']).isNotEmpty
        ? _tCall(m['status'])
        : (_tCall(m['endedReason']).isNotEmpty
        ? _tCall(m['endedReason'])
        : _tCall(m['endReason']))));

    final s = raw.toLowerCase().trim();

    // Normalize common variants
    if (s == 'no_answer' || s == 'noanswer' || s == 'timeout') return 'missed';
    if (s == 'rejected') return 'declined';
    if (s == 'cancelled') return 'canceled';
    if (s == 'completed' || s == 'success' || s == 'ok') return 'ended';

    // Sometimes you store "missed_call"
    if (s.contains('missed')) return 'missed';
    if (s.contains('declin') || s.contains('reject')) return 'declined';
    if (s.contains('cancel')) return 'canceled';
    if (s.contains('busy')) return 'busy';
    if (s.contains('end') || s.contains('complete')) return 'ended';

    return s;
  }

  String _callDirectionForViewerLower() {
    final m = widget.callInfo ?? const <String, dynamic>{};

    // Preferred explicit direction stored in message
    final explicit = _tCall(m['direction']).toLowerCase();
    if (explicit == 'incoming' || explicit == 'outgoing') return explicit;

    // If we have caller/callee IDs, compute direction from viewer perspective
    final me = (widget.currentUserId ?? '').trim();
    final callerId = _tCall(m['callerId']).isNotEmpty ? _tCall(m['callerId']) : _tCall(m['fromId']);
    final calleeId = _tCall(m['calleeId']).isNotEmpty ? _tCall(m['calleeId']) : _tCall(m['toId']);

    if (me.isNotEmpty) {
      if (callerId.isNotEmpty && callerId == me) return 'outgoing';
      if (calleeId.isNotEmpty && calleeId == me) return 'incoming';
    }

    // Final fallback:
    // If *this bubble* is authored by me => outgoing for me, else incoming.
    return widget.isMe ? 'outgoing' : 'incoming';
  }

  bool _callIsMissed() {
    final r = _callResultLower();
    return r == 'missed';
  }

  bool _callIsDeclined() {
    final r = _callResultLower();
    return r == 'declined';
  }

  bool _callIsCanceled() {
    final r = _callResultLower();
    return r == 'canceled';
  }

  bool _callIsBusy() {
    final r = _callResultLower();
    return r == 'busy';
  }

  bool _callIsEnded() {
    final r = _callResultLower();
    return r == 'ended';
  }

  String _prettyResultLabel(AppLocalizations l10n) {
    // If your l10n has callLogs_result_* you can swap these easily later.
    final r = _callResultLower();
    switch (r) {
      case 'missed':
        return 'Missed';
      case 'declined':
        return 'Declined';
      case 'canceled':
        return 'Canceled';
      case 'busy':
        return 'Busy';
      case 'ended':
        return 'Ended';
      default:
      // Unknown => title-case-ish
        if (r.isEmpty) return '';
        return r[0].toUpperCase() + r.substring(1);
    }
  }

  Color _callAccentColor() {
    if (_callIsMissed()) return Colors.redAccent;
    if (_callIsDeclined() || _callIsBusy()) return Colors.orangeAccent;
    if (_callIsEnded()) return kPrimaryGold;
    if (_callIsCanceled()) return Colors.white70;
    return Colors.white70;
  }

  IconData _callMediaIcon() {
    final type = _callTypeLower();
    return (type == 'video') ? Icons.videocam_rounded : Icons.call_rounded;
  }

  IconData _callDirArrowIcon() {
    final dir = _callDirectionForViewerLower();
    return dir == 'incoming'
        ? Icons.call_received_rounded
        : Icons.call_made_rounded;
  }

  String _callTitleLine() {
    final dir = _callDirectionForViewerLower();
    final kind = (_callTypeLower() == 'video') ? 'Video call' : 'Voice call';
    // Keep it consistent with call logs: show Incoming/Outgoing
    return dir == 'incoming' ? 'Incoming $kind' : 'Outgoing $kind';
  }

  Widget _buildCallBubble(AppLocalizations l10n) {
    final accent = _callAccentColor();
    final title = _callTitleLine();
    final status = _prettyResultLabel(l10n);
    final when = widget.timeLabel; // already formatted by parent (chat time)

    // Same "log tile" feel (no actions)
    return Container(
      margin: const EdgeInsets.only(top: 2, bottom: 2),
      decoration: BoxDecoration(
        color: kSurfaceAltColor.withOpacity(0.55),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: _callIsMissed() ? Colors.redAccent.withOpacity(0.55) : kBorderColor.withOpacity(0.55),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Left icon (compact)
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: accent.withOpacity(0.14),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: accent.withOpacity(0.25)),
            ),
            child: Icon(_callMediaIcon(), size: 18, color: accent),
          ),
          const SizedBox(width: 10),

          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_callDirArrowIcon(), size: 14, color: Colors.white38),
                    const SizedBox(width: 6),
                    Text(
                      status.isEmpty ? 'Call' : status,
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  when,
                  style: TextStyle(
                    color: kTextSecondary.withOpacity(0.75),
                    fontSize: 12,
                    height: 1.1,
                  ),
                ),
              ],
            ),
          ),

          // Missed dot (optional)
          if (_callIsMissed()) ...[
            const SizedBox(width: 10),
            const Icon(Icons.circle, size: 10, color: Colors.redAccent),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Direction / Bidi helpers
  // ---------------------------------------------------------------------------

  bool _containsRtlChars(String s) {
    return RegExp(
      r'[\u0590-\u05FF\u0600-\u06FF\u0700-\u074F\u0750-\u077F\u08A0-\u08FF\uFB50-\uFDFF\uFE70-\uFEFF]',
    ).hasMatch(s);
  }

  TextDirection _textDirectionForMessage(String s) {
    final t = s.trim();
    if (t.isEmpty) return Directionality.of(context);
    if (_containsRtlChars(t)) return TextDirection.rtl;
    return TextDirection.ltr;
  }

  String _isolateBidi(String s, TextDirection dir) {
    const lri = '\u2066';
    const rli = '\u2067';
    const pdi = '\u2069';
    if (s.isEmpty) return s;
    return dir == TextDirection.rtl ? '$rli$s$pdi' : '$lri$s$pdi';
  }

  String _isolateLtrDigits(String s) {
    const lri = '\u2066';
    const pdi = '\u2069';
    return '$lri$s$pdi';
  }

  TextDirection _effectiveDir(BuildContext context) {
    final locale = Localizations.localeOf(context);
    final lang = locale.languageCode.toLowerCase();
    const rtlLangs = {'ar', 'he', 'fa', 'ur'};
    if (rtlLangs.contains(lang)) return TextDirection.rtl;
    return Directionality.of(context);
  }

  // ---------------------------------------------------------------------------
  // Colors
  // ---------------------------------------------------------------------------

  Color _tint(Color base, Color tint, double amount) {
    return Color.lerp(base, tint, amount.clamp(0.0, 1.0)) ?? base;
  }

  Color get _bubbleColor {
    final base = kSurfaceAltColor;
    if (!widget.isMe) return base.withOpacity(0.62);
    final tinted = _tint(base, kGoldDeep, 0.10);
    return tinted.withOpacity(0.70);
  }

  Color get _onBubblePrimary => kTextPrimary;
  Color get _onBubbleSecondary => kTextSecondary.withOpacity(0.90);

  Border? get _bubbleBorder {
    if (widget.isSelected) {
      return Border.all(color: kPrimaryGold.withOpacity(0.55), width: 1.4);
    }

    final c = widget.isMe
        ? kGoldDeep.withOpacity(0.18)
        : kBorderColor.withOpacity(0.45);
    return Border.all(color: c, width: 1);
  }

  List<BoxShadow> get _bubbleShadow {
    final base = BoxShadow(
      color: Colors.black.withOpacity(0.22),
      blurRadius: 10,
      offset: const Offset(0, 6),
    );

    if (!widget.isSelected) return [base];

    return [
      base,
      BoxShadow(
        color: kPrimaryGold.withOpacity(0.18),
        blurRadius: 18,
        spreadRadius: 1.5,
        offset: const Offset(0, 8),
      ),
    ];
  }

  // ---------------------------------------------------------------------------
  // Attachment helpers
  // ---------------------------------------------------------------------------

  String _norm(String? v) => (v ?? '').toLowerCase().trim();

  String _extFrom(String s) {
    final clean = s.split('?').first.split('#').first;
    final dot = clean.lastIndexOf('.');
    if (dot < 0 || dot == clean.length - 1) return '';
    return clean.substring(dot + 1).toLowerCase();
  }

  String _attachmentLabel(AppLocalizations l10n) {
    final type = _norm(widget.fileType);
    final name = _norm(widget.fileName);
    final url = _norm(widget.fileUrl);

    final ext = _extFrom(name).isNotEmpty ? _extFrom(name) : _extFrom(url);

    if (type == 'image' || type.startsWith('image/')) return l10n.photo;
    if (type == 'video' || type.startsWith('video/')) return l10n.videoLabel;

    if (type == 'audio' ||
        type.startsWith('audio/') ||
        type == 'voice' ||
        type == 'voice_note' ||
        type == 'voicenote' ||
        type == 'voice-message') {
      return l10n.voiceMessageLabel;
    }

    const imageExts = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'heic'};
    const videoExts = {'mp4', 'mov', 'mkv', 'avi', 'm4v', 'webm'};
    const audioExts = {'mp3', 'wav', 'm4a', 'aac', 'ogg', 'opus'};

    final looksLikeVoice = name.contains('voice') ||
        name.contains('audio') ||
        name.contains('record') ||
        name.contains('rec') ||
        name.contains('mic');

    if (ext == 'webm' && looksLikeVoice) return l10n.voiceMessageLabel;

    if (imageExts.contains(ext)) return l10n.photo;
    if (videoExts.contains(ext)) return l10n.videoLabel;
    if (audioExts.contains(ext)) return l10n.voiceMessageLabel;

    return l10n.genericFileLabel;
  }

  String _basenameFromUrl(String url) {
    final u = Uri.tryParse(url);
    if (u == null) return '';
    final segs = u.pathSegments;
    if (segs.isEmpty) return '';
    return segs.last;
  }

  String _stripExtension(String name) {
    final i = name.lastIndexOf('.');
    if (i <= 0) return name;
    return name.substring(0, i);
  }

  bool _looksLikeIdOrJunk(String s) {
    final t = s.trim();
    if (t.length < 3) return true;
    if (t.contains('/') || t.contains('\\')) return true;
    if (RegExp(r'^\d{10,}$').hasMatch(t)) return true;
    if (RegExp(r'^[a-f0-9-]{12,}$', caseSensitive: false).hasMatch(t)) {
      return true;
    }
    final letters = RegExp(r'[A-Za-z]').allMatches(t).length;
    if (t.length >= 14 && letters <= 2) return true;
    return false;
  }

  String _cleanHumanName(String raw) {
    var s = raw.trim();
    try {
      s = Uri.decodeFull(s);
    } catch (_) {}
    final q = s.indexOf('?');
    if (q >= 0) s = s.substring(0, q);

    s = s.replaceAll('\\', '/');
    if (s.contains('/')) {
      s = s.split('/').where((p) => p.trim().isNotEmpty).last;
    }
    s = s.replaceAll(RegExp(r'^\d{10,}[\s_\-]+'), '');
    s = s.replaceAll(RegExp(r'[_\-]+'), ' ');
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return s;
  }

  String _friendlyGenericFileTitle(AppLocalizations l10n) {
    final raw = (widget.fileName ?? '').trim().isNotEmpty
        ? (widget.fileName ?? '').trim()
        : _basenameFromUrl((widget.fileUrl ?? '').trim());

    if (raw.isEmpty) return l10n.genericFileLabel;

    var base = _stripExtension(raw);
    base = _cleanHumanName(base);

    if (_looksLikeIdOrJunk(base)) return l10n.genericFileLabel;

    const maxLen = 26;
    if (base.length > maxLen) base = base.substring(0, maxLen).trim();

    return base.isEmpty ? l10n.genericFileLabel : base;
  }

  String _displayTextForBubble(AppLocalizations l10n) {
    final t = widget.text.trim();
    if (t.isEmpty) return '';
    if (hasAttachment) {
      final label = _attachmentLabel(l10n).trim().toLowerCase();
      if (label.isNotEmpty && t.toLowerCase() == label) return '';
    }
    return t;
  }

  Widget _mediaTitleLine(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: kTextPrimary.withOpacity(0.92),
          fontWeight: FontWeight.w800,
          fontSize: _mediaTitleFontSize,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // ✅ Reply preview (normalized + supports both legacy + MwReplyTo snapshot)
  // ---------------------------------------------------------------------------

  Map<String, dynamic>? _normalizeReplyTo(Object? raw) {
    if (raw == null) return null;

    if (raw is Map) {
      final out = <String, dynamic>{};
      raw.forEach((k, v) {
        if (k == null) return;
        out[k.toString()] = v;
      });

      if (out.isEmpty) return null;

      final nested = out['replyTo'];
      if (nested is Map && out.length == 1) {
        final n = <String, dynamic>{};
        nested.forEach((k, v) {
          if (k == null) return;
          n[k.toString()] = v;
        });
        return n.isEmpty ? null : n;
      }

      return out;
    }

    return null;
  }

  bool _hasUsefulReply(Map<String, dynamic> r) {
    final messageId = (r['messageId'] ?? r['id'] ?? '').toString().trim();
    final previewText = (r['previewText'] ?? '').toString().trim();
    final text = (r['text'] ?? '').toString().trim();
    final fileName = (r['fileName'] ?? '').toString().trim();
    final fileUrl = (r['fileUrl'] ?? '').toString().trim();
    final type = (r['type'] ?? '').toString().trim();

    if (messageId.isNotEmpty) return true;

    return previewText.isNotEmpty ||
        text.isNotEmpty ||
        fileName.isNotEmpty ||
        fileUrl.isNotEmpty ||
        type.isNotEmpty;
  }

  String _replyMessageId(Map<String, dynamic> r) {
    return (r['messageId'] ?? r['id'] ?? '').toString().trim();
  }

  String _replyLineFromPayload(AppLocalizations l10n, Map<String, dynamic> r) {
    final previewText = (r['previewText'] ?? '').toString().trim();
    if (previewText.isNotEmpty) {
      return previewText.length > 80
          ? '${previewText.substring(0, 80)}…'
          : previewText;
    }

    final type = (r['type'] ?? '').toString().trim().toLowerCase();
    final txt = (r['text'] ?? '').toString().trim();
    final fileName = (r['fileName'] ?? '').toString().trim();
    final fileType = (r['fileType'] ?? '').toString().trim().toLowerCase();

    String line;
    if (txt.isNotEmpty) {
      line = txt;
    } else if (type == 'image' || fileType.startsWith('image/')) {
      line = l10n.photo;
    } else if (type == 'video' || fileType.startsWith('video/')) {
      line = l10n.videoLabel;
    } else if (type == 'audio' ||
        type == 'voice' ||
        fileType.startsWith('audio/')) {
      line = l10n.voiceMessageLabel;
    } else if (fileName.isNotEmpty) {
      line = fileName;
    } else {
      line = (l10n.reply ?? 'Reply').trim();
      if (line.isEmpty) line = 'Reply';
    }

    return line.length > 80 ? '${line.substring(0, 80)}…' : line;
  }

  Widget _buildReplyPreview(AppLocalizations l10n, Map<String, dynamic> r) {
    final line = _replyLineFromPayload(l10n, r).trim();
    if (line.isEmpty) return const SizedBox.shrink();

    final targetId = _replyMessageId(r);
    final canJump = targetId.isNotEmpty && widget.onReplyPreviewTap != null;

    final replyDir = _textDirectionForMessage(line);
    final replyAlign =
    replyDir == TextDirection.rtl ? TextAlign.right : TextAlign.left;

    final content = Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border(
          left: BorderSide(
            color: widget.isMe ? kPrimaryGold.withOpacity(0.85) : Colors.white24,
            width: 3,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.reply_rounded,
            size: 16,
            color: kTextSecondary.withOpacity(0.9),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: MwTokenText(
              text: line,
              style: TextStyle(
                color: kTextPrimary.withOpacity(0.92),
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
              textDirection: replyDir,
              textAlign: replyAlign,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 6),
          Icon(
            Icons.chevron_right_rounded,
            size: 18,
            color: canJump
                ? kTextSecondary.withOpacity(0.85)
                : kTextSecondary.withOpacity(0.35),
          ),
        ],
      ),
    );

    if (!canJump) return content;

    return InkWell(
      onTap: () => widget.onReplyPreviewTap?.call(targetId),
      borderRadius: BorderRadius.circular(12),
      child: content,
    );
  }

  // ---------------------------------------------------------------------------
  // ✅ Deleted message helpers
  // ---------------------------------------------------------------------------

  bool _looksLikeSoftDeletedFromContent({
    required bool hasAnyReactions,
  }) {
    // ✅ Call events can have no text + no file; never treat them as deleted.
    if (isCallMessage) return false;

    final noText = widget.text.trim().isEmpty;
    final noFile = (widget.fileUrl ?? '').trim().isEmpty;
    final noReply = widget.replyTo == null;
    return noText && noFile && noReply && !hasAnyReactions;
  }

  String _deletedPlaceholder(AppLocalizations l10n) {
    final maybe = (l10n.thisMessageWasDeleted ?? '').toString().trim();
    if (maybe.isNotEmpty) return maybe;
    return 'This message was deleted';
  }

  // ---------------------------------------------------------------------------
  // Audio (via MwAudioHub)
  // ---------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();

    _identitySig = _makeIdentitySig(widget);

    final hub = MwAudioHub.instance;

    // Ensure release mode once
    _player.setReleaseMode(ReleaseMode.stop);

    _stateSub = _player.onPlayerStateChanged.listen((s) {
      if (!mounted) return;

      if (!hub.isActive(widget.messageId)) {
        if (_playing || _loading) {
          setState(() {
            _playing = false;
            _loading = false;
          });
        }
        return;
      }

      final nextPlaying = (s == PlayerState.playing);
      if (nextPlaying == _playing) return;
      setState(() => _playing = nextPlaying);
    });

    _posSub = _player.onPositionChanged.listen((p) {
      if (!mounted) return;
      if (!hub.isActive(widget.messageId)) return;

      Duration nextPos = p;

      if (nextPos == Duration.zero && _pos > Duration.zero) {
        return;
      }

      final total = _dur;
      if (total > Duration.zero && nextPos > total) {
        nextPos = total;
      }

      if (nextPos == _pos) return;
      setState(() => _pos = nextPos);

      if (_dur == Duration.zero) {
        unawaited(_syncFromSharedPlayerIfActive());
      }
    });

    _durSub = _player.onDurationChanged.listen((d) {
      if (!mounted) return;
      if (!hub.isActive(widget.messageId)) return;

      if (d == Duration.zero) return;

      final nextDur = d;
      final nextPos = (_pos > nextDur) ? nextDur : _pos;

      if (nextDur == _dur && nextPos == _pos) return;
      setState(() {
        _dur = nextDur;
        _pos = nextPos;
      });
    });

    _completeSub = _player.onPlayerComplete.listen((_) {
      if (!mounted) return;
      if (!hub.isActive(widget.messageId)) return;

      setState(() {
        _playing = false;
        _pos = (_dur == Duration.zero) ? Duration.zero : _dur;
      });
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_syncFromSharedPlayerIfActive());
    });
  }

  String _makeIdentitySig(MessageBubble w) {
    final parts = [
      w.messageId,
      w.text,
      w.timeLabel,
      w.fileUrl ?? '',
      w.fileType ?? '',
      w.fileName ?? '',
      w.thumbUrl ?? '',
      w.thumbnailUrl ?? '',
      w.videoThumbUrl ?? '',
      (w.callInfo == null ? '' : w.callInfo.toString()),
      (w.isMe ? 'me' : 'other'),
      (w.isDeleted ? 'deleted' : 'alive'),
      (w.isSelected ? 'sel' : 'nosel'),
    ];
    return parts.join('|');
  }

  Future<void> _syncFromSharedPlayerIfActive() async {
    final hub = MwAudioHub.instance;
    if (!mounted) return;
    if (!hub.isActive(widget.messageId)) return;

    try {
      final beforeActive = hub.activeMessageId;
      final beforePrepared = _preparedUrl;

      final p = await _player.getCurrentPosition();
      final d = await _player.getDuration();
      final s = _player.state;

      if (!mounted) return;
      if (hub.activeMessageId != beforeActive) return;
      if (!hub.isActive(widget.messageId)) return;

      Duration nextDur = _dur;
      if (d != null && d > Duration.zero) {
        nextDur = d;
      }

      Duration nextPos = _pos;
      if (p != null && p >= Duration.zero) {
        nextPos = p;
      }

      if (nextDur > Duration.zero && nextPos > nextDur) {
        nextPos = nextDur;
      }

      final nextPlaying = (s == PlayerState.playing);

      if (nextDur == Duration.zero &&
          (beforePrepared ?? '').isNotEmpty &&
          beforePrepared == (widget.fileUrl ?? '').trim()) {
        unawaited(_ensureAudioReady(beforePrepared!));
      }

      final bool changed =
          nextPos != _pos || nextDur != _dur || nextPlaying != _playing;

      if (!changed) return;

      setState(() {
        _pos = nextPos;
        _dur = nextDur;
        _playing = nextPlaying;
      });
    } catch (_) {}
  }

  @override
  void didUpdateWidget(covariant MessageBubble oldWidget) {
    super.didUpdateWidget(oldWidget);

    final hub = MwAudioHub.instance;

    final newSig = _makeIdentitySig(widget);
    if (newSig != _identitySig) {
      _identitySig = newSig;
      MwReactionOverlay.hide();
      _reactionLink = LayerLink();
      _resetSwipe();
    }

    final oldUrl = (oldWidget.fileUrl ?? '').trim();
    final newUrl = (widget.fileUrl ?? '').trim();

    final oldType = (oldWidget.fileType ?? '').trim().toLowerCase();
    final newType = (widget.fileType ?? '').trim().toLowerCase();

    final bool urlChanged = oldUrl != newUrl;
    final bool typeChanged = oldType != newType;

    final bool wasActive = hub.isActive(oldWidget.messageId);
    final bool isActive = hub.isActive(widget.messageId);

    if (wasActive && !isActive) {
      if (!mounted) return;
      setState(() {
        _pos = Duration.zero;
        _dur = Duration.zero;
        _playing = false;
        _loading = false;
        _audioError = false;
        _preparedUrl = null;
      });
      return;
    }

    if (isActive) {
      if (urlChanged || (typeChanged && !isAudio)) {
        _stopAndResetAudioUi();
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          unawaited(_syncFromSharedPlayerIfActive());
        });
      }
      return;
    }

    if (urlChanged || typeChanged || oldWidget.messageId != widget.messageId) {
      if (!mounted) return;
      setState(() {
        _pos = Duration.zero;
        _dur = Duration.zero;
        _playing = false;
        _loading = false;
        _audioError = false;
        _preparedUrl = null;
      });
    }
  }

  void _stopAndResetAudioUi() {
    _player.stop().catchError((_) {});
    if (!mounted) return;
    setState(() {
      _pos = Duration.zero;
      _dur = Duration.zero;
      _playing = false;
      _loading = false;
      _audioError = false;
      _preparedUrl = null;
    });
  }

  String _fmt(Duration d) {
    final s = d.inSeconds;
    final m = (s ~/ 60).toString();
    final r = (s % 60).toString().padLeft(2, '0');
    return '$m:$r';
  }

  Future<bool> _ensureAudioReady(String url) async {
    if (url.isEmpty) return false;

    if (_preparedUrl == url && _dur != Duration.zero && !_audioError) {
      return true;
    }

    try {
      await _player.setReleaseMode(ReleaseMode.stop);
      await _player.setSourceUrl(url).timeout(const Duration(seconds: 6));

      _preparedUrl = url;
      _audioError = false;

      final d = await _player.getDuration();
      if (d != null && d != Duration.zero && mounted) {
        setState(() => _dur = d);
      }
      return true;
    } catch (_) {
      if (mounted) setState(() => _audioError = true);
      return false;
    }
  }

  Future<void> _togglePlay() async {
    final url = (widget.fileUrl ?? '').trim();
    if (url.isEmpty) return;
    if (_loading) return;

    final hub = MwAudioHub.instance;

    if (hub.isActive(widget.messageId) && _playing) {
      try {
        await _player.pause();
      } catch (_) {}
      return;
    }

    await hub.activate(widget.messageId);

    unawaited(_syncFromSharedPlayerIfActive());

    if (!mounted) return;

    setState(() {
      _loading = true;
      _audioError = false;
    });

    try {
      final ok = await _ensureAudioReady(url);
      if (!ok) return;

      final total = _dur;
      if (total != Duration.zero &&
          _pos >= total - const Duration(milliseconds: 300)) {
        await _player.seek(Duration.zero);
        if (mounted) setState(() => _pos = Duration.zero);
      }

      await _player.play(UrlSource(url)).timeout(const Duration(seconds: 6));

      unawaited(_syncFromSharedPlayerIfActive());
    } catch (_) {
      if (mounted) setState(() => _audioError = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _seek(Duration t) async {
    final total = _dur;
    if (total == Duration.zero) return;

    final clamped = t < Duration.zero ? Duration.zero : (t > total ? total : t);

    try {
      final url = (widget.fileUrl ?? '').trim();
      final ok = await _ensureAudioReady(url);
      if (!ok) return;

      await _player.seek(clamped);
      if (mounted) setState(() => _pos = clamped);
    } catch (_) {}
  }

  Future<void> _openFile() async {
    final url = widget.fileUrl;
    if (url == null || url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _openImageFullScreen() {
    final url = widget.fileUrl;
    if (url == null || url.isEmpty) return;

    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.9),
      builder: (_) {
        return GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Stack(
            children: [
              Center(
                child: Hero(
                  tag: 'image_$url',
                  child: InteractiveViewer(
                    minScale: 0.8,
                    maxScale: 4.0,
                    child: Image.network(url, fit: BoxFit.contain),
                  ),
                ),
              ),
              Positioned(
                top: MediaQuery.of(context).padding.top + 12,
                right: 12,
                child: CircleAvatar(
                  backgroundColor: kSurfaceAltColor.withOpacity(0.65),
                  child: IconButton(
                    icon: const Icon(Icons.close, color: kTextPrimary),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _openVideoFullScreen() {
    final url = widget.fileUrl;
    if (url == null || url.isEmpty) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _FullScreenVideoPage(videoUrl: url),
      ),
    );
  }

  Widget _buildImageBubble() {
    final l10n = AppLocalizations.of(context)!;
    final url = widget.fileUrl!;
    final title = _attachmentLabel(l10n);

    return GestureDetector(
      onTap: _openImageFullScreen,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Hero(
            tag: 'image_$url',
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                url,
                width: _mediaSize,
                height: _mediaSize,
                fit: BoxFit.cover,
                loadingBuilder: (_, child, progress) {
                  if (progress == null) return child;
                  return SizedBox(
                    width: _mediaSize,
                    height: _mediaSize,
                    child: Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  );
                },
                errorBuilder: (_, __, ___) => SizedBox(
                  width: _mediaSize,
                  height: _mediaSize,
                  child: Center(
                    child: Icon(
                      Icons.broken_image,
                      color: kTextSecondary.withOpacity(0.8),
                    ),
                  ),
                ),
              ),
            ),
          ),
          _mediaTitleLine(title),
        ],
      ),
    );
  }

  // ✅ UPDATED: uses thumbUrl if available, falls back safely
  Widget _buildVideoBubbleLightweight() {
    final l10n = AppLocalizations.of(context)!;
    final url = (widget.fileUrl ?? '').trim();
    final title = _attachmentLabel(l10n);
    final thumb = _resolvedThumbUrl;

    return GestureDetector(
      onTap: _openVideoFullScreen,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: _mediaSize,
          height: _mediaSize,
          decoration: BoxDecoration(
            color: kSurfaceAltColor.withOpacity(0.55),
            border: Border.all(color: kBorderColor.withOpacity(0.45)),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned.fill(
                child: _VideoThumbBackground(
                  thumbUrl: thumb,
                  fallbackUrl: url,
                ),
              ),
              Container(
                color: Colors.black.withOpacity(0.18),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: Colors.black.withOpacity(0.55),
                    child: const Icon(
                      Icons.play_arrow,
                      color: kTextPrimary,
                      size: 30,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: kTextPrimary.withOpacity(0.92),
                        fontWeight: FontWeight.w700,
                        fontSize: _mediaTitleFontSize,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.tapToPlay,
                    style: TextStyle(
                      color: kTextSecondary.withOpacity(0.85),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAudioBubble() {
    final l10n = AppLocalizations.of(context)!;
    final dir = _effectiveDir(context);

    final url = widget.fileUrl ?? '';
    if (url.isEmpty) return const SizedBox.shrink();

    final total = _dur;
    final pos = (_pos > total && total != Duration.zero) ? total : _pos;

    final totalMs = total.inMilliseconds;
    final posMs = pos.inMilliseconds;

    final hasKnownDuration = totalMs > 0;
    final sliderMax = hasKnownDuration
        ? totalMs.toDouble()
        : math.max(posMs.toDouble(), 1.0);
    final sliderValue = math.min(posMs.toDouble(), sliderMax);

    final canSeek = hasKnownDuration;

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: kSurfaceAltColor.withOpacity(0.60),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: kBorderColor.withOpacity(0.45)),
        ),
        child: Row(
          children: [
            InkWell(
              onTap: _togglePlay,
              borderRadius: BorderRadius.circular(999),
              child: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: kSurfaceAltColor.withOpacity(0.55),
                  shape: BoxShape.circle,
                  border: Border.all(color: kBorderColor.withOpacity(0.50)),
                ),
                child: Center(
                  child: _loading
                      ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  )
                      : Icon(
                    _playing ? Icons.pause : Icons.play_arrow,
                    color: kTextPrimary,
                    size: 26,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Align(
                    alignment: dir == TextDirection.rtl
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          l10n.voiceMessageLabel,
                          style: const TextStyle(
                            color: kTextPrimary,
                            fontWeight: FontWeight.w800,
                            fontSize: _audioTitleFontSize,
                          ),
                        ),
                        if (_audioError) ...[
                          const SizedBox(width: 6),
                          const Icon(
                            Icons.error_outline,
                            size: 14,
                            color: kErrorColor,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 7),
                    ),
                    child: Slider(
                      value: sliderValue,
                      min: 0,
                      max: sliderMax,
                      onChanged: canSeek
                          ? (v) => _seek(Duration(milliseconds: v.round()))
                          : null,
                    ),
                  ),
                  Row(
                    children: [
                      if (dir == TextDirection.rtl) const Spacer(),
                      Text(
                        _isolateLtrDigits(_fmt(pos)),
                        textDirection: TextDirection.ltr,
                        style: TextStyle(
                          color: kTextSecondary.withOpacity(0.90),
                          fontSize: _audioTimeFontSize,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        total == Duration.zero
                            ? _isolateLtrDigits('--:--')
                            : _isolateLtrDigits(_fmt(total)),
                        textDirection: TextDirection.ltr,
                        style: TextStyle(
                          color: kTextSecondary.withOpacity(0.90),
                          fontSize: _audioTimeFontSize,
                        ),
                      ),
                      if (dir != TextDirection.rtl) const Spacer(),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFileBubble() {
    final l10n = AppLocalizations.of(context)!;
    final title = _friendlyGenericFileTitle(l10n);

    return GestureDetector(
      onTap: _openFile,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: kSurfaceAltColor.withOpacity(0.50),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: kBorderColor.withOpacity(0.45)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.insert_drive_file,
                color: kTextSecondary.withOpacity(0.9)),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                title,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: kTextPrimary,
                  fontSize: _fileTitleFontSize,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    MwReactionOverlay.hide();

    _stateSub?.cancel();
    _posSub?.cancel();
    _durSub?.cancel();
    _completeSub?.cancel();

    super.dispose();
  }

  bool _effectiveIsDeleted = false;

  bool get _canReact =>
      !_effectiveIsDeleted &&
          (widget.currentUserId ?? '').trim().isNotEmpty &&
          widget.onReactionTapAsync != null;

  bool _bubbleHasLayout() {
    final ro = context.findRenderObject();
    return ro is RenderBox && ro.hasSize;
  }

  void _showReactionsAfterLayout({int attempt = 0}) {
    if (!mounted) return;
    if (!_canReact) return;

    if (_bubbleHasLayout()) {
      _openReactionOverlay();
      return;
    }

    if (attempt >= 3) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _showReactionsAfterLayout(attempt: attempt + 1);
    });
  }

  Future<void> _openReactionOverlay() async {
    if (!_canReact) return;

    MwReactionOverlay.hide();

    final currentUserId = (widget.currentUserId ?? '').trim();
    final rx = MwReactions.normalize(widget.reactions);

    MwReactionOverlay.showAbove(
      context: context,
      link: _reactionLink,
      currentUserId: currentUserId,
      currentReactions: rx,
      alignToRightBubble: widget.isMe,
      onSelectEmoji: (emoji) async {
        final fn = widget.onReactionTapAsync;
        if (fn == null) return;

        await fn(emoji);
        MwReactionOverlay.hide();
        widget.onReactionCommitted?.call();
      },
      onOpenPicker: () async {
        final picked = await MwFullEmojiPicker.open(context);
        if (picked == null || picked.trim().isNotEmpty == false) return;

        final fn = widget.onReactionTapAsync;
        if (fn == null) return;

        await fn(picked.trim());
        MwReactionOverlay.hide();
        widget.onReactionCommitted?.call();
      },
    );
  }

  void _handleLongPress() {
    widget.onBubbleLongPress?.call();

    if (_effectiveIsDeleted) return;
    if (widget.isSelected) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _showReactionsAfterLayout();
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final l10n = AppLocalizations.of(context)!;
    final maxWidth = MediaQuery.of(context).size.width * 0.75;

    final currentUserId = (widget.currentUserId ?? '').trim();
    final rx = MwReactions.normalize(widget.reactions);
    final hasReactions = rx.isNotEmpty;

    _effectiveIsDeleted = widget.isDeleted ||
        _looksLikeSoftDeletedFromContent(hasAnyReactions: hasReactions);

    final replyMap = _normalizeReplyTo(widget.replyTo);
    final showReply =
        !_effectiveIsDeleted && replyMap != null && _hasUsefulReply(replyMap);

    final displayText = _effectiveIsDeleted ? '' : _displayTextForBubble(l10n);

    final msgDir = _textDirectionForMessage(displayText);
    final textAlign =
    msgDir == TextDirection.rtl ? TextAlign.right : TextAlign.left;

    final messageStyle = Theme.of(context).textTheme.bodyLarge?.copyWith(
      color: _onBubblePrimary,
      fontSize: _msgFontSize,
      height: _msgLineHeight,
      fontWeight: FontWeight.w500,
    ) ??
        const TextStyle(
          color: kTextPrimary,
          fontSize: _msgFontSize,
          height: _msgLineHeight,
          fontWeight: FontWeight.w500,
        );

    final Widget deletedBody = Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 2),
      child: Text(
        _deletedPlaceholder(l10n),
        style: TextStyle(
          color: _onBubbleSecondary.withOpacity(0.85),
          fontSize: 14,
          fontStyle: FontStyle.italic,
          fontWeight: FontWeight.w600,
        ),
      ),
    );

    final bubbleDecorated = Container(
      constraints: BoxConstraints(maxWidth: maxWidth, minWidth: 70),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _bubbleColor,
        borderRadius: BorderRadius.circular(_bubbleRadius),
        border: _bubbleBorder,
        boxShadow: _bubbleShadow,
      ),
      child: Column(
        crossAxisAlignment:
        widget.isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (showReply) _buildReplyPreview(l10n, replyMap!),

          // ✅ Call event uses the SAME "call logs" style (compact)
          if (!_effectiveIsDeleted && isCallMessage) _buildCallBubble(l10n),

          if (!_effectiveIsDeleted && hasAttachment && isImage) _buildImageBubble(),
          if (!_effectiveIsDeleted && hasAttachment && isVideo)
            _buildVideoBubbleLightweight(),
          if (!_effectiveIsDeleted && hasAttachment && isAudio) _buildAudioBubble(),
          if (!_effectiveIsDeleted && hasAttachment && isGenericFile)
            _buildFileBubble(),

          if (_effectiveIsDeleted)
            deletedBody
          else if (displayText.isNotEmpty)
            MwLinkify.build(
              text: displayText,
              style: messageStyle,
              textDirection: msgDir,
              textAlign: textAlign,
              disableLinks: widget.isSelected,
            ),

          if (!_effectiveIsDeleted && widget.showTimestamp)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _isolateBidi(widget.timeLabel, TextDirection.ltr),
                    textDirection: TextDirection.ltr,
                    style: TextStyle(
                      color: _onBubbleSecondary,
                      fontSize: _timestampFontSize,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (widget.isMe)
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Icon(
                        widget.isSeen ? Icons.done_all : Icons.done,
                        size: 14,
                        color: widget.isSeen
                            ? kPrimaryGold.withOpacity(0.92)
                            : kPrimaryGold.withOpacity(0.55),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );

    final bubbleWithOuterSpacing = Padding(
      padding: EdgeInsets.fromLTRB(
        6,
        4,
        6,
        hasReactions ? 16 : 6,
      ),
      child: bubbleDecorated,
    );

    final gesture = GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: widget.onBubbleTap,
      onLongPress: _handleLongPress,
      onSecondaryTapUp: kIsWeb
          ? (_) => WidgetsBinding.instance
          .addPostFrameCallback((_) => _handleLongPress())
          : null,
      onHorizontalDragStart:
      _canSwipeReply ? (_) => _replyTriggered = false : null,
      onHorizontalDragUpdate: _canSwipeReply
          ? (d) {
        if (_effectiveIsDeleted) return;

        final dir = _effectiveDir(context);
        final dx = d.delta.dx;

        final bool allowedDirection =
        dir == TextDirection.rtl ? (dx < 0) : (dx > 0);
        if (!allowedDirection) return;

        final next = (_swipeDx + dx).clamp(-_replyMaxDx, _replyMaxDx);
        if (!mounted) return;
        setState(() => _swipeDx = next);

        final reached = _swipeDx.abs() >= _replyTriggerDx;
        if (reached && !_replyTriggered) {
          _replyTriggered = true;
          HapticFeedback.selectionClick();
          widget.onSwipeReply?.call();
        }
      }
          : null,
      onHorizontalDragEnd: _canSwipeReply
          ? (_) {
        if (!mounted) return;
        setState(() => _resetSwipe());
      }
          : null,
      onHorizontalDragCancel: _canSwipeReply
          ? () {
        if (!mounted) return;
        setState(() => _resetSwipe());
      }
          : null,
      child: Transform.translate(
        offset: Offset(_canSwipeReply ? (_swipeDx * 0.25) : 0.0, 0.0),
        child: bubbleWithOuterSpacing,
      ),
    );

    final stacked = Stack(
      clipBehavior: Clip.none,
      children: [
        gesture,
        if (hasReactions)
          Positioned(
            bottom: 2,
            left: widget.isMe ? null : 18, // incoming -> left
            right: widget.isMe ? 18 : null, // outgoing -> right
            child: Material(
              color: Colors.transparent,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: MwMessageReactions(
                    reactions: rx,
                    currentUserId: currentUserId,
                    onTap: (widget.onReactionTapAsync == null ||
                        _effectiveIsDeleted)
                        ? null
                        : (e) async {
                      await widget.onReactionTapAsync!(e);
                      widget.onReactionCommitted?.call();
                    },
                  ),
                ),
              ),
            ),
          ),
      ],
    );

    return Align(
      alignment: widget.isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: CompositedTransformTarget(
        link: _reactionLink,
        child: stacked,
      ),
    );
  }
}

class _VideoThumbBackground extends StatelessWidget {
  final String thumbUrl;
  final String fallbackUrl;

  const _VideoThumbBackground({
    required this.thumbUrl,
    required this.fallbackUrl,
  });

  @override
  Widget build(BuildContext context) {
    final t = thumbUrl.trim();

    // ✅ Primary: thumbUrl (works iOS/Android/Web)
    if (t.isNotEmpty) {
      return Image.network(
        t,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, __, ___) => _placeholder(context),
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return Stack(
            children: [
              _placeholder(context),
              Positioned.fill(
                child: Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      );
    }

    // ✅ Fallback: try rendering from video url lightly (often fails, so still safe)
    final u = fallbackUrl.trim();
    if (u.isNotEmpty) {
      return Opacity(
        opacity: 0.14,
        child: Image.network(
          u,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _placeholder(context),
        ),
      );
    }

    return _placeholder(context);
  }

  Widget _placeholder(BuildContext context) {
    return Container(
      color: kSurfaceAltColor.withOpacity(0.55),
      alignment: Alignment.center,
      child: Icon(
        Icons.videocam_rounded,
        color: kTextSecondary.withOpacity(0.75),
        size: 30,
      ),
    );
  }
}
class _FullScreenVideoPage extends StatefulWidget {
  final String videoUrl;

  const _FullScreenVideoPage({required this.videoUrl});

  @override
  State<_FullScreenVideoPage> createState() => _FullScreenVideoPageState();
}

class _FullScreenVideoPageState extends State<_FullScreenVideoPage> {
  VideoPlayerController? _controller;

  bool _initialized = false;
  bool _error = false;

  bool _controlsVisible = true;
  Timer? _hideTimer;

  Duration _pos = Duration.zero;
  Duration _dur = Duration.zero;

  @override
  void initState() {
    super.initState();

    final uri = Uri.tryParse(widget.videoUrl);
    if (uri == null) {
      _error = true;
      return;
    }

    final c = VideoPlayerController.networkUrl(uri);
    _controller = c;

    c.addListener(_onVideoTick);

    c.initialize().then((_) {
      if (!mounted) return;
      setState(() {
        _initialized = true;
        _dur = c.value.duration;
      });

      // Autoplay (optional)
      c.play();

      _showControlsAndArm();
    }).catchError((_) {
      if (!mounted) return;
      setState(() => _error = true);
    });
  }

  void _onVideoTick() {
    final c = _controller;
    if (!mounted || c == null) return;

    final v = c.value;
    if (!v.isInitialized) return;

    final nextPos = v.position;
    final nextDur = v.duration;

    if (nextPos == _pos && nextDur == _dur) return;

    setState(() {
      _pos = nextPos;
      _dur = nextDur;
    });

    // If video ended, show controls (nice UX)
    if (nextDur > Duration.zero && nextPos >= nextDur) {
      _cancelAutoHide();
      if (!_controlsVisible && mounted) {
        setState(() => _controlsVisible = true);
      }
    }
  }

  void _cancelAutoHide() {
    _hideTimer?.cancel();
    _hideTimer = null;
  }

  void _armAutoHide({Duration delay = const Duration(seconds: 3)}) {
    _cancelAutoHide();

    final c = _controller;
    if (c == null || !c.value.isInitialized) return;

    // Only auto-hide when playing
    if (!c.value.isPlaying) return;

    _hideTimer = Timer(delay, () {
      if (!mounted) return;
      setState(() => _controlsVisible = false);
    });
  }

  void _showControlsAndArm() {
    if (!mounted) return;
    setState(() => _controlsVisible = true);
    _armAutoHide();
  }

  void _toggleControlsFromTap() {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;

    if (_controlsVisible) {
      _cancelAutoHide();
      setState(() => _controlsVisible = false);
    } else {
      _showControlsAndArm();
    }
  }

  String _fmt(Duration d) {
    final totalSeconds = d.inSeconds;
    final m = (totalSeconds ~/ 60).toString();
    final s = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _togglePlayPause() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;

    if (c.value.isPlaying) {
      await c.pause();
      _cancelAutoHide(); // keep visible when paused
      if (mounted) setState(() => _controlsVisible = true);
    } else {
      await c.play();
      if (mounted) setState(() => _controlsVisible = true);
      _armAutoHide();
    }
  }

  Future<void> _stop() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;

    await c.pause();
    await c.seekTo(Duration.zero);

    _cancelAutoHide();
    if (!mounted) return;
    setState(() {
      _pos = Duration.zero;
      _controlsVisible = true;
    });
  }

  Future<void> _seekToMs(int ms) async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;

    final total = _dur;
    if (total == Duration.zero) return;

    final target = Duration(milliseconds: ms);
    final clamped =
    target < Duration.zero ? Duration.zero : (target > total ? total : target);

    await c.seekTo(clamped);

    if (!mounted) return;
    setState(() => _pos = clamped);

    _armAutoHide();
  }

  @override
  void dispose() {
    _cancelAutoHide();
    final c = _controller;
    if (c != null) {
      c.removeListener(_onVideoTick);
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;

    final canShowPlayer = !_error && c != null && _initialized;

    final totalMs = _dur.inMilliseconds;
    final posMs = _pos.inMilliseconds.clamp(0, totalMs > 0 ? totalMs : 0);

    final sliderMax = (totalMs > 0) ? totalMs.toDouble() : 1.0;
    final sliderVal = (totalMs > 0) ? posMs.toDouble() : 0.0;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        leading: const BackButton(color: kTextPrimary),
      ),
      body: Center(
        child: _error || c == null
            ? Icon(Icons.broken_image, color: kTextSecondary.withOpacity(0.8))
            : !_initialized
            ? CircularProgressIndicator(
          color: Theme.of(context).colorScheme.primary,
        )
            : Stack(
          alignment: Alignment.center,
          children: [
            // ✅ VIDEO LAYER (tap-to-toggle sits here, behind controls)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _toggleControlsFromTap,
                child: Center(
                  child: AspectRatio(
                    aspectRatio:
                    c.value.aspectRatio == 0 ? (16 / 9) : c.value.aspectRatio,
                    child: VideoPlayer(c),
                  ),
                ),
              ),
            ),

            // ✅ CONTROLS OVERLAY (above video; captures interaction)
            if (canShowPlayer)
              AnimatedOpacity(
                opacity: _controlsVisible ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 180),
                child: IgnorePointer(
                  ignoring: !_controlsVisible,
                  child: Stack(
                    children: [
                      // Soft gradient for readability
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.black.withOpacity(0.25),
                                Colors.transparent,
                                Colors.black.withOpacity(0.55),
                              ],
                            ),
                          ),
                        ),
                      ),

                      // ✅ Big center play/pause
                      Center(
                        child: InkWell(
                          onTap: () async {
                            await _togglePlayPause();
                            // Keep controls visible on interaction, then re-arm
                            if (mounted) setState(() => _controlsVisible = true);
                            _armAutoHide();
                          },
                          borderRadius: BorderRadius.circular(999),
                          child: Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.45),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white.withOpacity(0.18),
                              ),
                            ),
                            child: Icon(
                              c.value.isPlaying
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                              color: Colors.white,
                              size: 44,
                            ),
                          ),
                        ),
                      ),

                      // ✅ Bottom toolbar: slider + stop + timer + small play/pause
                      Positioned(
                        left: 14,
                        right: 14,
                        bottom: MediaQuery.of(context).padding.bottom + 10,
                        child: SafeArea(
                          top: false,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  trackHeight: 3,
                                  thumbShape: const RoundSliderThumbShape(
                                    enabledThumbRadius: 7,
                                  ),
                                ),
                                child: Slider(
                                  min: 0,
                                  max: sliderMax,
                                  value: sliderVal.clamp(0.0, sliderMax),
                                  onChangeStart: (_) {
                                    // ✅ Don’t hide while user drags
                                    _cancelAutoHide();
                                    if (mounted) {
                                      setState(() => _controlsVisible = true);
                                    }
                                  },
                                  onChanged: totalMs > 0
                                      ? (v) => _seekToMs(v.round())
                                      : null,
                                  onChangeEnd: (_) {
                                    _armAutoHide();
                                  },
                                ),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  // Stop
                                  InkWell(
                                    onTap: () async {
                                      await _stop();
                                    },
                                    borderRadius: BorderRadius.circular(10),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 6,
                                      ),
                                      child: Row(
                                        children: const [
                                          Icon(Icons.stop_rounded,
                                              color: Colors.white, size: 20),
                                          SizedBox(width: 6),
                                          Text(
                                            'Stop',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),

                                  const Spacer(),

                                  // Timer
                                  Text(
                                    '${_fmt(_pos)} / ${_dur == Duration.zero ? '--:--' : _fmt(_dur)}',
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.92),
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),

                                  const Spacer(),

                                  // small play/pause
                                  InkWell(
                                    onTap: () async {
                                      await _togglePlayPause();
                                    },
                                    borderRadius: BorderRadius.circular(10),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 6,
                                      ),
                                      child: Icon(
                                        c.value.isPlaying
                                            ? Icons.pause_rounded
                                            : Icons.play_arrow_rounded,
                                        color: Colors.white,
                                        size: 22,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

