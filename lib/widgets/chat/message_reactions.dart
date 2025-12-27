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

  /// ✅ WhatsApp-like single reaction per user:
  /// - If user taps same emoji -> remove reaction
  /// - If user taps different emoji -> remove old and add new
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

      final oldEmoji = findUserReactionEmoji(reactions: current, userId: uid);

      // Remove user from old emoji list if exists
      if (oldEmoji != null) {
        final oldList = List<String>.from(current[oldEmoji] ?? const <String>[]);
        oldList.removeWhere((x) => x == uid);
        if (oldList.isEmpty) {
          current.remove(oldEmoji);
        } else {
          current[oldEmoji] = oldList;
        }
      }

      // Toggle off if same emoji
      if (oldEmoji == e) {
        tx.update(messageRef, {fieldReactions: current});
        return;
      }

      // Add new emoji
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
    final bg = mine
        ? kPrimaryGold.withOpacity(0.22)
        : kSurfaceAltColor.withOpacity(0.60);

    final border = mine
        ? kPrimaryGold.withOpacity(0.65)
        : kBorderColor.withOpacity(0.45);

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
/// FIXED:
/// - Can align left/right based on bubble
/// - Never clips off screen (constrained + horizontal scroll)
class MwReactionOverlay {
  static OverlayEntry? _entry;

  static bool get isShowing => _entry != null;

  static void hide() {
    _entry?.remove();
    _entry = null;
  }

  static void showAbove({
    required BuildContext context,
    required LayerLink link,
    required String currentUserId,
    required Map<String, List<String>> currentReactions,
    required Future<void> Function(String emoji) onSelectEmoji,
    required Future<void> Function() onOpenPicker,

    /// ✅ pass from MessageBubble (isMe) so we align correctly
    required bool alignToRightBubble,

    List<String> quickEmojis = const ['👍', '❤️', '😂', '😮', '😢', '🙏'],
  }) {
    hide();

    final overlay = Overlay.of(context, rootOverlay: true);
    if (overlay == null) return;

    _entry = OverlayEntry(
      builder: (ctx) {
        final media = MediaQuery.of(ctx);
        final w = media.size.width;

        // Keep bar fully inside screen
        const horizontalSafe = 12.0;
        final maxBarWidth = (w - (horizontalSafe * 2)).clamp(220.0, w);

        // Align to same side as bubble to avoid going خارج الشاشة
        final followerAnchor =
        alignToRightBubble ? Alignment.bottomRight : Alignment.bottomLeft;
        final targetAnchor =
        alignToRightBubble ? Alignment.topRight : Alignment.topLeft;

        return Stack(
          children: [
            Positioned.fill(
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
              // lift it a bit above bubble
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

/// ✅ Full emoji picker (opened via "+" button).
class MwFullEmojiPicker {
  static Future<String?> open(BuildContext context) async {
    const emojis = [
      '👍','❤️','😂','😮','😢','🙏','🔥','🎉','👏','✅','❌','😡','💯','✨','🤝','😍',
      '😎','😭','😁','😅','😆','😉','😊','🙂','🙃','😘','🤗','🤔','😴','😬','🥳','🤩',
      '😇','😈','🤯','😤','😱','🤦‍♂️','🤦‍♀️','🙌','💪','👀','💔','💙','💚','💛','🧡','💜',
      '⭐','🌟','⚡','☕','🍕','🍔','🍟','🍿','🥤','🎁','🎈','🏆','📌','📎','🧠','📣',
    ];

    return showDialog<String>(
      context: context,
      useRootNavigator: true,
      barrierColor: Colors.black.withOpacity(0.55),
      builder: (ctx) {
        final w = MediaQuery.of(ctx).size.width;
        final maxW = w > 560 ? 560.0 : double.infinity;

        return Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxW),
            child: Material(
              color: kSurfaceAltColor.withOpacity(0.98),
              borderRadius: BorderRadius.circular(18),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Pick an emoji',
                      style: TextStyle(
                        color: kTextPrimary.withOpacity(0.95),
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 320,
                      child: GridView.builder(
                        itemCount: emojis.length,
                        gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 8,
                          mainAxisSpacing: 10,
                          crossAxisSpacing: 10,
                        ),
                        itemBuilder: (_, i) {
                          final e = emojis[i];
                          return InkWell(
                            onTap: () => Navigator.of(ctx).pop(e),
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.06),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.10),
                                ),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                e,
                                style: const TextStyle(fontSize: 22),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        child: Text(
                          'Cancel',
                          style: TextStyle(
                            color: kTextPrimary.withOpacity(0.9),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
