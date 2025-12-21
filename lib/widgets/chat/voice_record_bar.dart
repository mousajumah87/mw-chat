// lib/widgets/chat/voice_record_bar.dart

import 'dart:async';
import 'dart:ui';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../utils/voice_recorder_controller.dart';

class VoiceRecordBar extends StatefulWidget {
  final VoiceRecorderController controller;

  /// Call when user taps Send on the preview
  final Future<void> Function(VoiceDraft draft) onSend;

  /// ✅ OPTIONAL: lets parent (ChatInputBar/ChatScreen) update Firestore
  /// e.g. set recording_<uid> true/false
  final VoidCallback? onRecordStart;
  final VoidCallback? onRecordStop;

  const VoiceRecordBar({
    super.key,
    required this.controller,
    required this.onSend,
    this.onRecordStart,
    this.onRecordStop,
  });

  @override
  State<VoiceRecordBar> createState() => _VoiceRecordBarState();
}

class _VoiceRecordBarState extends State<VoiceRecordBar> {
  final AudioPlayer _player = AudioPlayer();

  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration>? _durSub;
  StreamSubscription<PlayerState>? _stateSub;

  Duration _pos = Duration.zero;
  Duration _dur = Duration.zero;
  bool _playing = false;
  bool _loading = false;

  // Track which draft we loaded so switching drafts resets player state
  String? _loadedKey;

  // ✅ Track ACTIVE voice session transitions (recording OR preparing)
  bool _lastIsActive = false;

  bool _isActive(VoiceRecorderController c) => c.isRecording || c.isPreparing;

  // =========================
  // ✅ RTL-safe direction
  // =========================
  TextDirection _effectiveDir(BuildContext context) {
    // Locale-first (handles cases where parent forces LTR Directionality)
    final locale = Localizations.localeOf(context);
    final lang = locale.languageCode.toLowerCase();

    const rtlLangs = {'ar', 'he', 'fa', 'ur'};
    if (rtlLangs.contains(lang)) return TextDirection.rtl;

    // fallback to ambient Directionality
    return Directionality.of(context);
  }

  // Keep numbers stable regardless of surrounding bidi
  String _isolateLtr(String s) {
    const lri = '\u2066'; // Left-to-Right Isolate
    const pdi = '\u2069'; // Pop Directional Isolate
    return '$lri$s$pdi';
  }

  @override
  void initState() {
    super.initState();

    _lastIsActive = _isActive(widget.controller);
    if (_lastIsActive) {
      widget.onRecordStart?.call();
    }

    widget.controller.addListener(_onControllerChanged);

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
  }

  @override
  void didUpdateWidget(covariant VoiceRecordBar oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
      _stopAndResetPlayerUi();

      // ✅ reset transition tracking for new controller
      _lastIsActive = _isActive(widget.controller);
      if (_lastIsActive) {
        widget.onRecordStart?.call();
      } else {
        widget.onRecordStop?.call();
      }
    }
  }

  void _onControllerChanged() {
    if (!mounted) return;

    // ✅ Active session transition callbacks (recording OR preparing)
    final nowActive = _isActive(widget.controller);
    if (nowActive != _lastIsActive) {
      _lastIsActive = nowActive;
      if (nowActive) {
        widget.onRecordStart?.call();
      } else {
        widget.onRecordStop?.call();
      }
    }

    final draft = widget.controller.draft;
    final key = draft == null
        ? null
        : '${draft.fileName}|${draft.path ?? ''}|${draft.bytes?.length ?? 0}';

    if (key != _loadedKey) {
      _stopAndResetPlayerUi();
      _loadedKey = key;
    }

    setState(() {});
  }

  void _stopAndResetPlayerUi() {
    _player.stop().catchError((_) {});
    _pos = Duration.zero;
    _dur = Duration.zero;
    _playing = false;
    _loading = false;
  }

  @override
  void dispose() {
    // ✅ If we're being disposed while active (recording/preparing),
    // best-effort stop callback so Firestore flag won't stick
    if (_lastIsActive) {
      widget.onRecordStop?.call();
    }

    widget.controller.removeListener(_onControllerChanged);

    _posSub?.cancel();
    _durSub?.cancel();
    _stateSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  String _fmt(Duration d) {
    final s = d.inSeconds;
    final m = (s ~/ 60).toString();
    final r = (s % 60).toString().padLeft(2, '0');
    return '$m:$r';
  }

  Future<void> _togglePreviewPlay(VoiceDraft draft) async {
    if (_loading) return;

    try {
      if (_playing) {
        await _player.pause();
        return;
      }

      setState(() => _loading = true);

      // If already loaded, resume
      if (_dur != Duration.zero && _loadedKey != null) {
        await _player.resume();
        return;
      }

      // Prefer bytes source when available (especially on Web)
      final bytes = draft.bytes;
      if (bytes != null && bytes.isNotEmpty) {
        await _player.setSourceBytes(bytes, mimeType: draft.mimeType);
        await _player.resume();
        return;
      }

      // Otherwise fallback to path/url
      final p = draft.path;
      if (p == null || p.isEmpty) return;

      final looksLikeUrl =
          p.startsWith('http') || p.startsWith('https') || p.startsWith('blob:');

      if (kIsWeb || looksLikeUrl) {
        await _player.setSourceUrl(p);
      } else {
        await _player.setSourceDeviceFile(p);
      }

      await _player.resume();
    } catch (_) {
      // ignore
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _seek(Duration t) async {
    if (_dur == Duration.zero) return;
    final clamped = t < Duration.zero ? Duration.zero : (t > _dur ? _dur : t);
    await _player.seek(clamped);
  }

  // === MW glass wrapper for the bar (consistent with MW theme) ===
  Widget _glassBar({
    required Widget child,
    EdgeInsets margin = const EdgeInsets.fromLTRB(12, 6, 12, 8),
  }) {
    return Container(
      margin: margin,
      decoration: mwTypingGlassDecoration(radius: 16).copyWith(
        // make it align more with input bar tokens
        color: kChatInputBarBg.withOpacity(0.62),
        border: Border.all(
          color: kChatInputBarBorder.withOpacity(0.65),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: kGoldDeep.withOpacity(0.18),
            blurRadius: 18,
            spreadRadius: 1,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: child,
          ),
        ),
      ),
    );
  }

  BoxDecoration _circleGlassDecoration({bool highlight = false}) {
    return BoxDecoration(
      color: kChatInputFieldBg.withOpacity(0.55),
      shape: BoxShape.circle,
      border: Border.all(
        color: (highlight ? kPrimaryGold : kChatInputBarBorder).withOpacity(0.60),
        width: 1,
      ),
      boxShadow: highlight
          ? [
        BoxShadow(
          color: kGoldDeep.withOpacity(0.20),
          blurRadius: 16,
          spreadRadius: 1,
          offset: const Offset(0, 6),
        ),
      ]
          : [],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final c = widget.controller;

    final dir = _effectiveDir(context);

    // ✅ FIX: Keep bar visible during preparing too.
    if (!c.isRecording && !c.isPreparing && !c.hasDraft) {
      return const SizedBox.shrink();
    }

    // PREPARING STATE (permissions / init)
    if (c.isPreparing && !c.isRecording && !c.hasDraft) {
      return _glassBar(
        child: Directionality(
          textDirection: dir,
          child: Row(
            textDirection: dir,
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: kPrimaryGold.withOpacity(0.95),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${l10n.recordingLabel}…',
                  textAlign: TextAlign.start,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: kTextPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              IconButton(
                tooltip: l10n.cancelLabel,
                onPressed: () async {
                  await _player.stop().catchError((_) {});
                  await c.cancel(); // triggers transition => onRecordStop
                  _stopAndResetPlayerUi();
                  if (mounted) setState(() {});
                },
                icon: const Icon(Icons.delete_outline, color: kTextPrimary),
              ),
            ],
          ),
        ),
      );
    }

    // RECORDING STATE
    if (c.isRecording) {
      final seconds = c.elapsed.inSeconds;
      final progress = (seconds % 60) / 60.0;

      return _glassBar(
        child: Directionality(
          textDirection: dir,
          child: Row(
            textDirection: dir,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: kErrorColor,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: kErrorColor.withOpacity(0.35),
                      blurRadius: 10,
                      spreadRadius: 1,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      l10n.recordingLabel,
                      textAlign: TextAlign.start,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: kTextPrimary,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 6,
                        backgroundColor: Colors.black.withOpacity(0.22),
                        color: kPrimaryGold.withOpacity(0.92),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                _isolateLtr(_fmt(c.elapsed)),
                textDirection: TextDirection.ltr,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: kTextSecondary.withOpacity(0.92),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 10),
              IconButton(
                tooltip: l10n.cancelLabel,
                onPressed: () async {
                  await _player.stop().catchError((_) {});
                  await c.cancel(); // triggers transition => onRecordStop
                  _stopAndResetPlayerUi();
                  if (mounted) setState(() {});
                },
                icon: const Icon(Icons.delete_outline, color: kTextPrimary),
              ),
              IconButton(
                tooltip: l10n.stopLabel,
                onPressed: () async {
                  await c.stopToPreview(); // triggers transition => onRecordStop
                },
                icon: const Icon(Icons.stop_circle, color: kPrimaryGold),
              ),
            ],
          ),
        ),
      );
    }

    // PREVIEW STATE
    final draft = c.draft!;
    final total = _dur == Duration.zero ? draft.duration : _dur;
    final pos = _pos > total ? total : _pos;
    final canSeek = total.inMilliseconds > 0;

    return _glassBar(
      child: Directionality(
        textDirection: dir, // keep overall bar RTL/LTR for spacing of send/delete if you want
        child: Row(
          textDirection: dir,
          children: [
            // ✅ Keep the play button circle position as your current layout
            InkWell(
              onTap: () => _togglePreviewPlay(draft),
              borderRadius: BorderRadius.circular(999),
              child: Container(
                width: 44,
                height: 44,
                decoration: _circleGlassDecoration(highlight: _playing || _loading),
                child: Center(
                  child: _loading
                      ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: kPrimaryGold.withOpacity(0.95),
                    ),
                  )
                      : Directionality(
                    // ✅ FIX: always keep media icon LTR (no mirroring)
                    textDirection: TextDirection.ltr,
                    child: Icon(
                      _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      color: kTextPrimary,
                      size: 26,
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(width: 10),

            // ✅ BUT: make the slider + time ALWAYS LTR to avoid confusion/double-mirror
            Expanded(
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 3,
                        activeTrackColor: kPrimaryGold.withOpacity(0.85),
                        inactiveTrackColor: kChatInputBarBorder.withOpacity(0.55),
                        thumbColor: kPrimaryGold.withOpacity(0.95),
                        overlayColor: kPrimaryGold.withOpacity(0.12),
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
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
                        Text(
                          _isolateLtr(_fmt(pos)),
                          textDirection: TextDirection.ltr,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: kTextSecondary.withOpacity(0.92),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          _isolateLtr(_fmt(total)),
                          textDirection: TextDirection.ltr,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: kTextSecondary.withOpacity(0.92),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(width: 8),

            IconButton(
              tooltip: l10n.cancelLabel,
              onPressed: () async {
                await _player.stop();
                await c.discardDraft();
                _stopAndResetPlayerUi();
                if (mounted) setState(() {});
              },
              icon: const Icon(Icons.delete_outline, color: kTextPrimary),
            ),
            IconButton(
              tooltip: l10n.sendLabel,
              onPressed: () async {
                await _player.stop();
                try {
                  await widget.onSend(draft);
                  await c.markSentAndCleanup();
                } catch (_) {}
                _stopAndResetPlayerUi();
                if (mounted) setState(() {});
              },
              icon: const Icon(Icons.send_rounded, color: kPrimaryGold),
            ),
          ],
        ),
      ),
    );
  }
}
