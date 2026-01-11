// lib/widgets/chat/message_bubble.dart
import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // ✅ haptics (kept)
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import 'message_reactions.dart';
import 'mw_token_text.dart'; // ✅ IMPORTANT: unified token rendering

class MessageBubble extends StatefulWidget {
  final String text;
  final String timeLabel;
  final bool isMe;
  final bool isSeen;
  final String? fileUrl;
  final String? fileName;
  final String? fileType; // "image", "video", "audio", "file", "voice"
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
    required this.text,
    required this.timeLabel,
    required this.isMe,
    required this.isSeen,
    this.fileUrl,
    this.fileName,
    this.fileType,
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
  final AudioPlayer _player = AudioPlayer();

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
  // So we make the LayerLink replaceable, and reset it when bubble identity changes.
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
    final noText = widget.text.trim().isEmpty;
    final noFile = (widget.fileUrl ?? '').trim().isEmpty;
    final noType = (widget.fileType ?? '').trim().isEmpty;
    final noReply = widget.replyTo == null;
    return noText && noFile && noType && noReply && !hasAnyReactions;
  }

  String _deletedPlaceholder(AppLocalizations l10n) {
    final maybe = (l10n.thisMessageWasDeleted ?? '').toString().trim();
    if (maybe.isNotEmpty) return maybe;
    return 'This message was deleted';
  }

  // ---------------------------------------------------------------------------
  // Audio
  // ---------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();

    _identitySig = _makeIdentitySig(widget);

    _stateSub = _player.onPlayerStateChanged.listen((s) {
      if (!mounted) return;
      setState(() => _playing = s == PlayerState.playing);
    });

    _posSub = _player.onPositionChanged.listen((p) {
      if (!mounted) return;
      setState(() => _pos = p);
    });

    _durSub = _player.onDurationChanged.listen((d) {
      if (!mounted) return;
      setState(() => _dur = d);
    });

    _completeSub = _player.onPlayerComplete.listen((_) {
      if (!mounted) return;
      setState(() {
        _playing = false;
        _pos = _dur == Duration.zero ? Duration.zero : _dur;
      });
    });

    _player.setReleaseMode(ReleaseMode.stop);
  }

  String _makeIdentitySig(MessageBubble w) {
    // NOTE: This is a fallback safety net in case parent didn't pass stable keys.
    // If you DO have messageId, your parent SHOULD pass ValueKey(messageId).
    final parts = [
      w.text,
      w.timeLabel,
      w.fileUrl ?? '',
      w.fileType ?? '',
      w.fileName ?? '',
      (w.isMe ? 'me' : 'other'),
    ];
    return parts.join('|');
  }

  @override
  void didUpdateWidget(covariant MessageBubble oldWidget) {
    super.didUpdateWidget(oldWidget);

    // ✅ Protect overlay correctness when State is reused for a different message.
    final newSig = _makeIdentitySig(widget);
    if (newSig != _identitySig) {
      _identitySig = newSig;
      MwReactionOverlay.hide();
      _reactionLink = LayerLink(); // ✅ new anchor for the new message
      _resetSwipe();
    }

    final oldUrl = (oldWidget.fileUrl ?? '').trim();
    final newUrl2 = (widget.fileUrl ?? '').trim();

    final oldType = (oldWidget.fileType ?? '').trim().toLowerCase();
    final newType = (widget.fileType ?? '').trim().toLowerCase();

    final urlChanged = oldUrl != newUrl2;
    final typeChanged = oldType != newType;

    if (urlChanged || (typeChanged && !isAudio)) {
      _stopAndResetAudioUi();
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

    try {
      if (_playing) {
        await _player.pause();
        return;
      }

      setState(() {
        _loading = true;
        _audioError = false;
      });

      final ok = await _ensureAudioReady(url);
      if (!ok) return;

      final total = _dur;
      if (total != Duration.zero &&
          _pos >= total - const Duration(milliseconds: 300)) {
        await _player.seek(Duration.zero);
        if (mounted) setState(() => _pos = Duration.zero);
      }

      try {
        await _player.resume().timeout(const Duration(seconds: 5));
      } catch (_) {
        await _player.stop().catchError((_) {});
        await _player.play(UrlSource(url)).timeout(const Duration(seconds: 6));
      }
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

  Widget _buildVideoBubbleLightweight() {
    final l10n = AppLocalizations.of(context)!;
    final url = widget.fileUrl ?? '';
    final title = _attachmentLabel(l10n);

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
                child: Opacity(
                  opacity: 0.10,
                  child: Image.network(
                    url,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
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

  // ---------------------------------------------------------------------------
  // ✅ Linkify (URLs clickable) while preserving MwTokenText for non-link chunks
  // ---------------------------------------------------------------------------

  static final RegExp _urlRegex = RegExp(
    r'((https?:\/\/|www\.)[^\s<>()]+)',
    caseSensitive: false,
  );

  String _normalizeUrl(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return t;
    final low = t.toLowerCase();
    if (low.startsWith('http://') || low.startsWith('https://')) return t;
    if (low.startsWith('www.')) return 'https://$t';
    return t;
  }

  Future<void> _openUrl(String raw) async {
    final normalized = _normalizeUrl(raw);
    final uri = Uri.tryParse(normalized);
    if (uri == null) return;

    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      // no-op
    }
  }

  Widget _buildLinkifiedBody({
    required String text,
    required TextStyle style,
    required TextDirection textDirection,
    required TextAlign textAlign,
    required bool disableLinks,
  }) {
    if (!_urlRegex.hasMatch(text) || disableLinks) {
      return MwTokenText(
        text: text,
        style: style,
        textDirection: textDirection,
        textAlign: textAlign,
      );
    }

    final matches = _urlRegex.allMatches(text).toList();
    if (matches.isEmpty) {
      return MwTokenText(
        text: text,
        style: style,
        textDirection: textDirection,
        textAlign: textAlign,
      );
    }

    final segments = <Widget>[];
    int cursor = 0;

    for (final m in matches) {
      final start = m.start;
      final end = m.end;

      if (start > cursor) {
        final normalChunk = text.substring(cursor, start);
        if (normalChunk.trim().isNotEmpty || normalChunk.contains('\n')) {
          segments.add(
            MwTokenText(
              text: normalChunk,
              style: style,
              textDirection: textDirection,
              textAlign: textAlign,
            ),
          );
        }
      }

      final urlChunk = text.substring(start, end);
      segments.add(
        InkWell(
          onTap: () => _openUrl(urlChunk),
          borderRadius: BorderRadius.circular(6),
          child: Text(
            urlChunk,
            textDirection: TextDirection.ltr,
            style: style.copyWith(
              decoration: TextDecoration.underline,
              color: kPrimaryGold.withOpacity(0.95),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );

      cursor = end;
    }

    if (cursor < text.length) {
      final tail = text.substring(cursor);
      if (tail.trim().isNotEmpty || tail.contains('\n')) {
        segments.add(
          MwTokenText(
            text: tail,
            style: style,
            textDirection: textDirection,
            textAlign: textAlign,
          ),
        );
      }
    }

    return Directionality(
      textDirection: textDirection,
      child: Align(
        alignment:
        textAlign == TextAlign.right ? Alignment.centerRight : Alignment.centerLeft,
        child: Wrap(
          alignment:
          textAlign == TextAlign.right ? WrapAlignment.end : WrapAlignment.start,
          runAlignment: WrapAlignment.center,
          spacing: 0,
          runSpacing: 0,
          children: segments,
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
    final canSeek = total.inMilliseconds > 0;

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
                      value: canSeek ? pos.inMilliseconds.toDouble() : 0,
                      min: 0,
                      max: canSeek ? total.inMilliseconds.toDouble() : 1,
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
    _player.stop().catchError((_) {});
    _stateSub?.cancel();
    _posSub?.cancel();
    _durSub?.cancel();
    _completeSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  late bool _effectiveIsDeleted;

  bool get _canReact =>
      !(_effectiveIsDeleted) &&
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
        if (picked == null || picked.trim().isEmpty) return;

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

    // ✅ If bubble is already selected, don't open emoji overlay again.
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

    // ✅ IMPORTANT:
    // We DO NOT use margin inside bubble decoration anymore.
    // Margin created confusing “floating space” and reactions looked detached.
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

          if (!_effectiveIsDeleted && hasAttachment && isImage) _buildImageBubble(),
          if (!_effectiveIsDeleted && hasAttachment && isVideo)
            _buildVideoBubbleLightweight(),
          if (!_effectiveIsDeleted && hasAttachment && isAudio) _buildAudioBubble(),
          if (!_effectiveIsDeleted && hasAttachment && isGenericFile) _buildFileBubble(),

          if (_effectiveIsDeleted)
            deletedBody
          else if (displayText.isNotEmpty)
            _buildLinkifiedBody(
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

    // ✅ Outer spacing: this reserves room for reactions (so next message never overlaps)
    final bubbleWithOuterSpacing = Padding(
      padding: EdgeInsets.fromLTRB(
        6,
        4,
        6,
        hasReactions ? 16 : 6, // ✅ space for reactions below
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

      onHorizontalDragStart: _canSwipeReply ? (_) => _replyTriggered = false : null,
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

    // ✅ This Stack is now tight to the bubble itself (no weird margin space),
    // so reactions visually belong to the correct message.
    final stacked = Stack(
      clipBehavior: Clip.none,
      children: [
        gesture,

        if (hasReactions)
          PositionedDirectional(
            // ✅ attach closer to bubble edge (NOT floating in the gap)
            bottom: 2,
            start: widget.isMe ? null : 18,
            end: widget.isMe ? 18 : null,
            child: Material(
              color: Colors.transparent,
              child: DecoratedBox(
                // subtle backing makes it obviously attached to the message
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: MwMessageReactions(
                    reactions: rx,
                    currentUserId: currentUserId,
                    onTap: (widget.onReactionTapAsync == null || _effectiveIsDeleted)
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

    c.initialize().then((_) {
      if (!mounted) return;
      setState(() => _initialized = true);
      c.play();
    }).catchError((_) {
      if (!mounted) return;
      setState(() => _error = true);
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;

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
            : AspectRatio(
          aspectRatio: c.value.aspectRatio,
          child: VideoPlayer(c),
        ),
      ),
    );
  }
}
