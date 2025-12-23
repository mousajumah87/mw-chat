// lib/widgets/chat/mw_token_text.dart
import 'package:flutter/material.dart';

class MwTokenText extends StatelessWidget {
  final String text;
  final TextStyle style;
  final TextDirection textDirection;
  final TextAlign textAlign;

  /// Inline emoji size inside message bubble
  final double emojiSize;

  /// Optional baseline tweak (usually not needed)
  final double emojiVPad;

  const MwTokenText({
    super.key,
    required this.text,
    required this.style,
    required this.textDirection,
    required this.textAlign,
    this.emojiSize = 96,
    this.emojiVPad = 0,
  });

  /// MUST match EXACT token strings you insert from MwEmojiPanel
  /// MUST match EXACT file names (case sensitive)
  static const Map<String, String> tokenToAsset = {
    // 🌟 General
    ':mw_love:': 'assets/emojis/love.webp',
    ':mw_happy:': 'assets/emojis/happy.webp',
    ':mw_laugh:': 'assets/emojis/laugh.webp',
    ':mw_cry:': 'assets/emojis/cry.webp',
    ':mw_angry:': 'assets/emojis/angry.webp',
    ':mw_chock:': 'assets/emojis/chock.webp',
    ':mw_cool:': 'assets/emojis/cool.webp',
    ':mw_shy:': 'assets/emojis/shy.webp',
    ':mw_like:': 'assets/emojis/like.webp',
    ':mw_passion:': 'assets/emojis/passion.webp',
    ':mw_sleep:': 'assets/emojis/sleep.webp',

    // 🐻 Bear
    ':mw_bear_love:': 'assets/emojis/bearlove.webp',
    ':mw_bear_angry:': 'assets/emojis/bearangry.webp',

    // 👧 Smurf (girl)
    ':mw_smurf_happy:': 'assets/emojis/smurfhappy.webp',
    ':mw_smurf_love:': 'assets/emojis/smurflove.webp',
    ':mw_smurf_angry:': 'assets/emojis/smurfangry.webp',
  };

  static final RegExp _tokenRegex = RegExp(r'(:[a-zA-Z0-9_]+:)');

  @override
  Widget build(BuildContext context) {
    if (text.trim().isEmpty) return const SizedBox.shrink();

    // Keep delimiters by splitting with regex, then re-inserting tokens by index.
    final rawParts = text.split(_tokenRegex);
    final tokens = _tokenRegex.allMatches(text).map((m) => m.group(0)!).toList();

    final spans = <InlineSpan>[];

    for (int i = 0; i < rawParts.length; i++) {
      // ✅ IMPORTANT: render plain text too
      final plain = rawParts[i];
      if (plain.isNotEmpty) {
        spans.add(TextSpan(text: plain, style: style));
      }

      if (i < tokens.length) {
        final token = tokens[i];
        final asset = tokenToAsset[token];

        if (asset != null) {
          spans.add(
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 2, vertical: emojiVPad),
                child: Image.asset(
                  asset,
                  width: emojiSize,
                  height: emojiSize,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                  // Note: if your image itself has white background baked-in,
                  // code cannot remove it. You must use transparent assets.
                  errorBuilder: (_, __, ___) => Text(token, style: style),
                ),
              ),
            ),
          );
        } else {
          // Unknown token -> show raw token so you notice
          spans.add(TextSpan(text: token, style: style));
        }
      }
    }

    return RichText(
      textDirection: textDirection,
      textAlign: textAlign,
      text: TextSpan(style: style, children: spans),
    );
  }
}

/// ✅ helper you can use in MessageBubble
bool mwContainsAnyToken(String s) {
  for (final t in MwTokenText.tokenToAsset.keys) {
    if (s.contains(t)) return true;
  }
  return false;
}
