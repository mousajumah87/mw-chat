// lib/widgets/chat/mw_emoji_panel.dart
import 'package:flutter/material.dart';

class MwEmojiItem {
  final String? char;
  final String? asset;
  final String token;

  const MwEmojiItem._({this.char, this.asset, required this.token});

  const MwEmojiItem.char(String c) : this._(char: c, token: c);

  const MwEmojiItem.asset(String path, {required String token})
      : this._(asset: path, token: token);

  bool get isAsset => asset != null;
}

class MwEmojiPanel extends StatelessWidget {
  final ValueChanged<String> onInsert;

  /// Full panel height override (optional)
  final double? height;

  /// Grid padding
  final EdgeInsets padding;

  /// Emoji preview size in the grid
  final double emojiSize;

  /// Grid columns
  final int columns;

  const MwEmojiPanel({
    super.key,
    required this.onInsert,
    this.height,
    this.padding = const EdgeInsets.fromLTRB(10, 10, 10, 14),
    this.emojiSize = 96,
    this.columns = 4,
  });

  static const mwItems = <MwEmojiItem>[
    // =========================
    // 🌟 MW – General emojis
    // =========================
    MwEmojiItem.asset('assets/emojis/love.webp', token: ':mw_love:'),
    MwEmojiItem.asset('assets/emojis/happy.webp', token: ':mw_happy:'),
    MwEmojiItem.asset('assets/emojis/laugh.webp', token: ':mw_laugh:'),
    MwEmojiItem.asset('assets/emojis/cry.webp', token: ':mw_cry:'),
    MwEmojiItem.asset('assets/emojis/angry.webp', token: ':mw_angry:'),
    MwEmojiItem.asset('assets/emojis/chock.webp', token: ':mw_chock:'),
    MwEmojiItem.asset('assets/emojis/cool.webp', token: ':mw_cool:'),
    MwEmojiItem.asset('assets/emojis/shy.webp', token: ':mw_shy:'),
    MwEmojiItem.asset('assets/emojis/like.webp', token: ':mw_like:'),
    MwEmojiItem.asset('assets/emojis/passion.webp', token: ':mw_passion:'),
    MwEmojiItem.asset('assets/emojis/sleep.webp', token: ':mw_sleep:'),

    // =========================
    // 🐻 MW – Bear emojis
    // =========================
    MwEmojiItem.asset('assets/emojis/bearlove.webp', token: ':mw_bear_love:'),
    MwEmojiItem.asset('assets/emojis/bearangry.webp', token: ':mw_bear_angry:'),

    // =========================
    // 👧 MW – Smurf (girl) emojis
    // =========================
    MwEmojiItem.asset('assets/emojis/smurfhappy.webp', token: ':mw_smurf_happy:'),
    MwEmojiItem.asset('assets/emojis/smurflove.webp', token: ':mw_smurf_love:'),
    MwEmojiItem.asset('assets/emojis/smurfangry.webp', token: ':mw_smurf_angry:'),
  ];

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final panelHeight = height ?? (280.0 + (bottomInset * 0.2));

    return Material(
      color: const Color(0xFF101018),
      child: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Colors.white12)),
        ),
        child: SizedBox(
          height: panelHeight,
          child: GridView.builder(
            padding: padding,
            physics: const BouncingScrollPhysics(),
            primary: false,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
            ),
            itemCount: mwItems.length,
            itemBuilder: (_, i) {
              final item = mwItems[i];

              return InkWell(
                borderRadius: BorderRadius.circular(10),
                splashColor: Colors.transparent,
                highlightColor: Colors.transparent,
                onTap: () => onInsert(item.token),
                child: Center(
                  child: item.isAsset
                      ? Image.asset(
                    item.asset!,
                    width: emojiSize,
                    height: emojiSize,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.broken_image_outlined,
                      color: Colors.white54,
                      size: 18,
                    ),
                  )
                      : Text(
                    item.char ?? "",
                    style: const TextStyle(fontSize: 22),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
