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
  bool _sending = false;

  String? _loadedKey;

  bool _isActive(VoiceRecorderController c) => c.isRecording || c.isPreparing;

  // =========================
  // ✅ RTL-safe direction
  // =========================
  TextDirection _effectiveDir(BuildContext context) {
    final locale = Localizations.localeOf(context);
    final lang = locale.languageCode.toLowerCase();

    const rtlLangs = {'ar', 'he', 'fa', 'ur'};
    if (rtlLangs.contains(lang)) return TextDirection.rtl;

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
      _stopAndResetPlayerUi(setStateToo: true);
    }
  }

  void _onControllerChanged() {
    if (!mounted) return;

    final draft = widget.controller.draft;
    final key = draft == null
        ? null
        : '${draft.fileName}|${draft.path ?? ''}|${draft.bytes?.length ?? 0}';

    if (key != _loadedKey) {
      _stopAndResetPlayerUi(setStateToo: false);
      _loadedKey = key;
    }

    setState(() {});
  }

  void _stopAndResetPlayerUi({required bool setStateToo}) {
    _player.stop().catchError((_) {});
    _pos = Duration.zero;
    _dur = Duration.zero;
    _playing = false;
    _loading = false;

    if (setStateToo && mounted) setState(() {});
  }

  @override
  void dispose() {
    if (_isActive(widget.controller)) {
      widget.onRecordStop?.call();
    }

    widget.controller.removeListener(_onControllerChanged);

    _posSub?.cancel();
    _durSub?.cancel();
    _stateSub?.cancel();

    _player.stop().catchError((_) {});
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
    if (_loading || _sending) return;

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

  Widget _playButtonIcon() {
    // ✅ Keep icon LTR-stable (mostly cosmetic, but safe in RTL)
    return Directionality(
      textDirection: TextDirection.ltr,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        child: _loading
            ? SizedBox(
          key: const ValueKey('loading'),
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: kPrimaryGold.withOpacity(0.95),
          ),
        )
            : Icon(
          _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
          key: ValueKey(_playing ? 'pause' : 'play'),
          color: kTextPrimary,
          size: 22,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final c = widget.controller;

    final dir = _effectiveDir(context);

    if (!c.isRecording && !c.isPreparing && !c.hasDraft) {
      return const SizedBox.shrink();
    }

    // PREPARING STATE
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
                  try {
                    await c.cancel();
                  } catch (_) {
                    // ignore
                  } finally {
                    widget.onRecordStop?.call();
                  }
                  _stopAndResetPlayerUi(setStateToo: true);
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
                  try {
                    await c.cancel();
                  } catch (_) {
                    // ignore
                  } finally {
                    widget.onRecordStop?.call();
                  }
                  _stopAndResetPlayerUi(setStateToo: true);
                },
                icon: const Icon(Icons.delete_outline, color: kTextPrimary),
              ),
              IconButton(
                tooltip: l10n.stopLabel,
                onPressed: () async {
                  try {
                    await c.stopToPreview();
                  } catch (_) {
                    // ignore
                  } finally {
                    widget.onRecordStop?.call();
                  }
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
        textDirection: dir,
        child: Row(
          textDirection: dir,
          children: [
            InkWell(
              onTap: () => _togglePreviewPlay(draft),
              borderRadius: BorderRadius.circular(999),
              child: Container(
                width: 44,
                height: 44,
                decoration:
                _circleGlassDecoration(highlight: _playing || _loading),
                child: Center(child: _playButtonIcon()),
              ),
            ),
            const SizedBox(width: 10),
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
                        thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 7),
                      ),
                      child: Slider(
                        value: canSeek ? pos.inMilliseconds.toDouble() : 0,
                        min: 0,
                        max: canSeek ? total.inMilliseconds.toDouble() : 1,
                        onChanged: (canSeek && !_sending)
                            ? (v) => _seek(Duration(milliseconds: v.round()))
                            : null,
                      ),
                    ),
                    Row(
                      children: [
                        Text(
                          _isolateLtr(_fmt(pos)),
                          textDirection: TextDirection.ltr,
                          style:
                          Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: kTextSecondary.withOpacity(0.92),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          _isolateLtr(_fmt(total)),
                          textDirection: TextDirection.ltr,
                          style:
                          Theme.of(context).textTheme.bodySmall?.copyWith(
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
              onPressed: _sending
                  ? null
                  : () async {
                await _player.stop().catchError((_) {});
                try {
                  await c.discardDraft();
                } catch (_) {
                  // ignore
                }
                _stopAndResetPlayerUi(setStateToo: true);
              },
              icon: const Icon(Icons.delete_outline, color: kTextPrimary),
            ),
            IconButton(
              tooltip: l10n.sendLabel,
              onPressed: (_sending || _loading)
                  ? null
                  : () async {
                if (_sending) return;
                setState(() => _sending = true);

                await _player.stop().catchError((_) {});

                try {
                  await widget.onSend(draft);
                  await c.markSentAndCleanup();
                } catch (_) {
                  // ignore
                } finally {
                  if (mounted) setState(() => _sending = false);
                }

                _stopAndResetPlayerUi(setStateToo: true);
              },
              icon: Icon(
                Icons.send_rounded,
                color: _sending ? kTextSecondary : kPrimaryGold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
