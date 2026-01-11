// lib/widgets/chat/message_reactions.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Firestore field:
/// reactions: { "👍": ["uid1","uid2"], "❤️": ["uid3"] }
///
/// WhatsApp-like mode:
/// - Only ONE reaction per user
/// - Switching emoji replaces old
/// - Selecting same emoji again removes it
class MwReactions {
  static const String fieldReactions = 'reactions';

  /// Defensive normalize:
  /// - trims keys
  /// - removes empty keys
  /// - ensures unique uids per emoji
  /// - drops empty uid entries
  static Map<String, List<String>> normalize(dynamic raw) {
    final Map<String, List<String>> out = {};
    if (raw is! Map) return out;

    for (final entry in raw.entries) {
      final key = (entry.key?.toString() ?? '').trim();
      if (key.isEmpty) continue;

      final v = entry.value;
      if (v is List) {
        final seen = <String>{};
        final list = <String>[];
        for (final x in v) {
          final uid = x.toString().trim();
          if (uid.isEmpty) continue;
          if (seen.add(uid)) list.add(uid);
        }
        if (list.isNotEmpty) out[key] = list;
      }
    }
    return out;
  }

  static String? findUserReactionEmoji({
    required Map<String, List<String>> reactions,
    required String userId,
  }) {
    final uid = userId.trim();
    if (uid.isEmpty) return null;

    for (final e in reactions.entries) {
      if (e.value.contains(uid)) return e.key;
    }
    return null;
  }

  /// ✅ Remove user from ALL emojis (cleans "dirty" data where user has 2+ reactions).
  static void _removeUserFromAll({
    required Map<String, List<String>> reactions,
    required String userId,
  }) {
    final keys = reactions.keys.toList(growable: false);
    for (final k in keys) {
      final list = List<String>.from(reactions[k] ?? const <String>[]);
      list.removeWhere((x) => x == userId);
      if (list.isEmpty) {
        reactions.remove(k);
      } else {
        reactions[k] = list;
      }
    }
  }

  /// ✅ WhatsApp-like single reaction per user:
  /// - If user taps same emoji -> remove reaction
  /// - If user taps different emoji -> remove old (even if multiple) and add new
  ///
  /// NOTE: This writes the whole reactions map (simple + robust).
  static Future<void> setSingleReaction({
    required DocumentReference<Map<String, dynamic>> messageRef,
    required String userId,
    required String emoji,
  }) async {
    final uid = userId.trim();
    final e = emoji.trim();
    if (uid.isEmpty || e.isEmpty) return;

    await FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(messageRef);
      if (!snap.exists) return;

      final data = snap.data() ?? const <String, dynamic>{};
      final raw = data[fieldReactions];
      final current = normalize(raw);

      // ✅ decide toggle BEFORE cleanup
      final hadThisEmoji = (current[e]?.contains(uid) ?? false);

      // ✅ Always clean user from ALL emojis
      _removeUserFromAll(reactions: current, userId: uid);

      // Toggle off
      if (hadThisEmoji) {
        tx.update(messageRef, {fieldReactions: current});
        return;
      }

      // Add new emoji (single reaction)
      final newList = List<String>.from(current[e] ?? const <String>[]);
      if (!newList.contains(uid)) newList.add(uid);
      current[e] = newList;

      tx.update(messageRef, {fieldReactions: current});
    });
  }

  /// Top emojis by count. Stable tie-breaker keeps UI from jittering.
  static List<MapEntry<String, List<String>>> topByCount(
      Map<String, List<String>> m, {
        int max = 3,
      }) {
    if (m.isEmpty) return const [];

    final list = m.entries.toList()
      ..sort((a, b) {
        final c = b.value.length.compareTo(a.value.length);
        if (c != 0) return c;
        return a.key.compareTo(b.key);
      });

    if (list.length <= max) return list;
    return list.take(max).toList();
  }
}

/// Small reaction summary chips (emoji-only) shown attached to the message.
class MwMessageReactions extends StatelessWidget {
  final Map<String, List<String>> reactions;
  final String currentUserId;

  /// Optional: allow parent to react to taps (e.g. open overlay).
  final void Function(String emoji)? onTap;

  final int maxShown;
  final bool singleLine;
  final bool compact;

  const MwMessageReactions({
    super.key,
    required this.reactions,
    required this.currentUserId,
    this.onTap,
    this.maxShown = 3,
    this.singleLine = true,
    this.compact = true,
  });

  @override
  Widget build(BuildContext context) {
    if (reactions.isEmpty) return const SizedBox.shrink();
    final top = MwReactions.topByCount(reactions, max: maxShown);
    if (top.isEmpty) return const SizedBox.shrink();

    final chips = <Widget>[
      for (final entry in top)
        _ReactionChip(
          emoji: entry.key,
          mine: entry.value.contains(currentUserId.trim()),
          onTap: onTap,
          compact: compact,
        ),
    ];

    if (singleLine) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < chips.length; i++) ...[
            chips[i],
            if (i != chips.length - 1) const SizedBox(width: 6),
          ],
        ],
      );
    }

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: chips,
    );
  }
}

class _ReactionChip extends StatelessWidget {
  final String emoji;
  final bool mine;
  final void Function(String emoji)? onTap;
  final bool compact;

  const _ReactionChip({
    required this.emoji,
    required this.mine,
    required this.onTap,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    final bg =
    mine ? kPrimaryGold.withOpacity(0.22) : kSurfaceAltColor.withOpacity(0.60);

    final border =
    mine ? kPrimaryGold.withOpacity(0.65) : kBorderColor.withOpacity(0.45);

    final pad = compact ? const EdgeInsets.all(6) : const EdgeInsets.all(8);

    return InkWell(
      onTap: onTap == null ? null : () => onTap!(emoji),
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: pad,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: border),
        ),
        child: Text(
          emoji,
          style: const TextStyle(fontSize: 15),
        ),
      ),
    );
  }
}

/// ✅ Floating overlay bar above the message bubble.
/// Fix: do NOT cover the AppBar area with the dismiss barrier.
/// This makes AppBar icons (Delete/Report/Copy) work on FIRST tap.
class MwReactionOverlay {
  static OverlayEntry? _entry;

  static bool get isShowing => _entry != null;

  static void hide() {
    _entry?.remove();
    _entry = null;
  }

  static double _appBarBlockHeight(BuildContext ctx) {
    final media = MediaQuery.of(ctx);
    // Safe top (status bar) + standard toolbar height
    return media.padding.top + kToolbarHeight;
  }

  /// ✅ Keep the FIRST quick bar the same (small).
  static const List<String> kDefaultQuickEmojis = ['👍', '❤️', '😂', '😮', '😢', '🙏'];

  /// ✅ Full set used ONLY when pressing "+" (more picker).
  static const List<String> kFullEmojis = [
    '👍','❤️','😂','😮','😢','🙏','🔥','🎉','👏','✅','❌','😡','💯','✨','🤝','😍',
    '😎','😭','😁','😅','😆','😉','😊','🙂','🙃','😘','🤗','🤔','😴','😬','🥳','🤩',
    '😇','😈','🤯','😤','😱','🤦‍♂️','🤦‍♀️','🙌','💪','👀','💔','💙','💚','💛','🧡','💜',
    '⭐','🌟','⚡','☕','🍕','🍔','🍟','🍿','🥤','🎁','🎈','🏆','📌','📎','🧠','📣',
  ];

  /// ✅ anchor-by-position API
  static void show({
    required BuildContext context,
    required Offset? anchor,
    required String currentUserId,
    required Map<String, List<String>> currentReactions,
    required Future<void> Function(String emoji) onSelectEmoji,
    required Future<void> Function() onOpenPicker,
    required bool alignToRightBubble,
    List<String> quickEmojis = kDefaultQuickEmojis,
  }) {
    hide();

    final overlay = Overlay.of(context, rootOverlay: true);
    if (overlay == null) return;

    _entry = OverlayEntry(
      builder: (ctx) {
        final media = MediaQuery.of(ctx);
        final size = media.size;

        const horizontalSafe = 12.0;
        final maxBarWidth =
        (size.width - (horizontalSafe * 2)).clamp(220.0, size.width);

        final a = anchor ??
            Offset(
              size.width / 2,
              (size.height * 0.55).clamp(120.0, size.height - 120.0),
            );

        const barHeightGuess = 54.0;
        final double desiredLeft =
        alignToRightBubble ? (a.dx - maxBarWidth + 30) : (a.dx - 30);
        final double desiredTop = a.dy - barHeightGuess - 18;

        final left = desiredLeft.clamp(
          horizontalSafe,
          size.width - maxBarWidth - horizontalSafe,
        );
        final top = desiredTop.clamp(12.0, size.height - barHeightGuess - 12.0);

        final appBarH = _appBarBlockHeight(ctx);

        return Stack(
          children: [
            // ✅ Barrier ONLY below the app bar (so header buttons get the tap)
            Positioned(
              left: 0,
              right: 0,
              top: appBarH,
              bottom: 0,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: hide,
                child: const SizedBox.expand(),
              ),
            ),

            // Reaction bar
            Positioned(
              left: left,
              top: top,
              width: maxBarWidth,
              child: SafeArea(
                child: Material(
                  color: Colors.transparent,
                  child: _ReactionBar(
                    currentUserId: currentUserId,
                    currentReactions: currentReactions,
                    quickEmojis: quickEmojis,
                    onEmojiTap: (e) async {
                      await onSelectEmoji(e);
                      hide();
                    },
                    onPlusTap: () async {
                      hide();
                      await onOpenPicker();
                    },
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );

    overlay.insert(_entry!);
  }

  /// ✅ LayerLink anchored
  static void showAbove({
    required BuildContext context,
    required LayerLink link,
    required String currentUserId,
    required Map<String, List<String>> currentReactions,
    required Future<void> Function(String emoji) onSelectEmoji,
    required Future<void> Function() onOpenPicker,
    required bool alignToRightBubble,
    List<String> quickEmojis = kDefaultQuickEmojis,
  }) {
    hide();

    final overlay = Overlay.of(context, rootOverlay: true);
    if (overlay == null) return;

    _entry = OverlayEntry(
      builder: (ctx) {
        final media = MediaQuery.of(ctx);
        final w = media.size.width;

        const horizontalSafe = 12.0;
        final maxBarWidth = (w - (horizontalSafe * 2)).clamp(220.0, w);

        final followerAnchor =
        alignToRightBubble ? Alignment.bottomRight : Alignment.bottomLeft;
        final targetAnchor =
        alignToRightBubble ? Alignment.topRight : Alignment.topLeft;

        final appBarH = _appBarBlockHeight(ctx);

        return Stack(
          children: [
            // ✅ Barrier ONLY below the app bar
            Positioned(
              left: 0,
              right: 0,
              top: appBarH,
              bottom: 0,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: hide,
                child: const SizedBox.expand(),
              ),
            ),

            CompositedTransformFollower(
              link: link,
              showWhenUnlinked: false,
              followerAnchor: followerAnchor,
              targetAnchor: targetAnchor,
              offset: const Offset(0, -10),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: horizontalSafe),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: maxBarWidth),
                    child: Material(
                      color: Colors.transparent,
                      child: _ReactionBar(
                        currentUserId: currentUserId,
                        currentReactions: currentReactions,
                        quickEmojis: quickEmojis,
                        onEmojiTap: (e) async {
                          await onSelectEmoji(e);
                          hide();
                        },
                        onPlusTap: () async {
                          hide();
                          await onOpenPicker();
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );

    overlay.insert(_entry!);
  }
}

class _ReactionBar extends StatelessWidget {
  final String currentUserId;
  final Map<String, List<String>> currentReactions;
  final List<String> quickEmojis;
  final void Function(String emoji) onEmojiTap;
  final VoidCallback onPlusTap;

  const _ReactionBar({
    required this.currentUserId,
    required this.currentReactions,
    required this.quickEmojis,
    required this.onEmojiTap,
    required this.onPlusTap,
  });

  @override
  Widget build(BuildContext context) {
    final mine = MwReactions.findUserReactionEmoji(
      reactions: currentReactions,
      userId: currentUserId,
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: kSurfaceAltColor.withOpacity(0.92),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.30),
            blurRadius: 16,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (int i = 0; i < quickEmojis.length; i++) ...[
                _EmojiButton(
                  emoji: quickEmojis[i],
                  selected: mine == quickEmojis[i],
                  onTap: () => onEmojiTap(quickEmojis[i]),
                ),
                if (i != quickEmojis.length - 1) const SizedBox(width: 6),
              ],
              const SizedBox(width: 6),
              _PlusButton(onTap: onPlusTap),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmojiButton extends StatelessWidget {
  final String emoji;
  final bool selected;
  final VoidCallback onTap;

  const _EmojiButton({
    required this.emoji,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = selected
        ? kPrimaryGold.withOpacity(0.20)
        : Colors.white.withOpacity(0.06);
    final border = selected
        ? kPrimaryGold.withOpacity(0.65)
        : Colors.white.withOpacity(0.10);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: border),
        ),
        child: Text(emoji, style: const TextStyle(fontSize: 18)),
      ),
    );
  }
}

class _PlusButton extends StatelessWidget {
  final VoidCallback onTap;

  const _PlusButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withOpacity(0.10)),
        ),
        child: Icon(
          Icons.add,
          size: 18,
          color: kTextPrimary.withOpacity(0.92),
        ),
      ),
    );
  }
}

/// ✅ Full picker (no emoji_picker_flutter dependency)
/// Used for "+" only. Shows your FULL emoji list, without changing workflow.
class MwFullEmojiPicker {
  static const List<String> _fullEmojis = MwReactionOverlay.kFullEmojis;

  static Future<String?> open(BuildContext context) async {
    String? selected;

    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        final media = MediaQuery.of(ctx);
        final h = media.size.height;
        final sheetH = (h * 0.55).clamp(340.0, 520.0);

        return SafeArea(
          child: Container(
            height: sheetH,
            decoration: BoxDecoration(
              color: kSurfaceAltColor.withOpacity(0.98),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
              border: Border.all(color: Colors.white.withOpacity(0.10)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.35),
                  blurRadius: 18,
                  offset: const Offset(0, -10),
                ),
              ],
            ),
            child: _MwEmojiGridPicker(
              emojis: _fullEmojis,
              onPick: (emoji) {
                selected = emoji;
                Navigator.of(ctx).pop();
              },
            ),
          ),
        );
      },
    );

    return selected;
  }
}

/// Internal grid picker used by MwFullEmojiPicker.
class _MwEmojiGridPicker extends StatelessWidget {
  final List<String> emojis;
  final void Function(String emoji) onPick;

  const _MwEmojiGridPicker({
    required this.emojis,
    required this.onPick,
  });

  int _crossAxisCountForWidth(double w) {
    if (w >= 900) return 12;
    if (w >= 600) return 10;
    return 8;
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final crossAxisCount = _crossAxisCountForWidth(w);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'More reactions',
                  style: TextStyle(
                    color: kTextPrimary.withOpacity(0.92),
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: Icon(Icons.close, color: kTextPrimary.withOpacity(0.85)),
                splashRadius: 18,
              ),
            ],
          ),
        ),
        Divider(height: 1, color: Colors.white.withOpacity(0.08)),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
            ),
            itemCount: emojis.length,
            itemBuilder: (ctx, i) {
              final e = emojis[i];
              return InkWell(
                onTap: () => onPick(e),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withOpacity(0.10)),
                  ),
                  alignment: Alignment.center,
                  child: Text(e, style: const TextStyle(fontSize: 20)),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
