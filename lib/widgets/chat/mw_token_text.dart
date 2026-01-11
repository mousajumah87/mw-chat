// lib/widgets/chat/mw_token_text.dart
//
// Unified MW token -> inline image renderer.
// Usage:
//   MwTokenText(text: "Hi :mw_love:", style: ..., textDirection: ..., textAlign: ...)

import 'package:flutter/material.dart';

class MwTokenText extends StatelessWidget {
  final String text;
  final TextStyle style;
  final TextDirection? textDirection;
  final TextAlign? textAlign;

  /// ✅ New: match Text/RichText behavior (for reply preview, lists, etc.)
  final int? maxLines;
  final TextOverflow? overflow;
  final bool softWrap;
  final StrutStyle? strutStyle;

  const MwTokenText({
    super.key,
    required this.text,
    required this.style,
    this.textDirection,
    this.textAlign,
    this.maxLines,
    this.overflow,
    this.softWrap = true,
    this.strutStyle,
  });

  /// ✅ One source of truth for MW emoji tokens.
  /// Add more tokens here and they will render everywhere.
  static const Map<String, String> tokenToAsset = <String, String>{
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

    ':mw_bear_love:': 'assets/emojis/bearlove.webp',
    ':mw_bear_angry:': 'assets/emojis/bearangry.webp',

    ':mw_smurf_happy:': 'assets/emojis/smurfhappy.webp',
    ':mw_smurf_love:': 'assets/emojis/smurflove.webp',
    ':mw_smurf_angry:': 'assets/emojis/smurfangry.webp',
  };

  static final RegExp _tokenRegex =
  RegExp(r'(:mw_[a-zA-Z0-9_]+:)', multiLine: true);

  bool _isOnlyTokensMessage(String s) {
    final trimmed = s.trim();
    if (trimmed.isEmpty) return false;

    final matches = _tokenRegex.allMatches(trimmed).toList();
    if (matches.isEmpty) return false;

    // Remove all tokens and see if anything else remains
    final withoutTokens =
    trimmed.replaceAll(_tokenRegex, '').replaceAll(' ', '');

    return withoutTokens.isEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final raw = text;
    final trimmed = raw.trim();

    // ✅ Sticker mode: message is ONLY tokens (one or more)
    // Keep existing UX: bigger icons, wrap them.
    if (_isOnlyTokensMessage(trimmed)) {
      final tokens = _tokenRegex
          .allMatches(trimmed)
          .map((m) => m.group(0)!)
          .where((t) => tokenToAsset.containsKey(t))
          .toList();

      if (tokens.isEmpty) {
        return Text(
          trimmed,
          style: style,
          textDirection: textDirection,
          textAlign: textAlign,
          maxLines: maxLines,
          overflow: overflow,
          softWrap: softWrap,
          strutStyle: strutStyle,
        );
      }

      // Note: Wrap doesn't support maxLines/ellipsis (by design).
      // This is fine for sticker mode; tokens are meant to be visible.
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Wrap(
          spacing: 6,
          runSpacing: 6,
          alignment: WrapAlignment.end,
          children: tokens.map((t) {
            final asset = tokenToAsset[t]!;
            return Image.asset(
              asset,
              width: 72,
              height: 72,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
            );
          }).toList(),
        ),
      );
    }

    // Mixed text + tokens -> RichText with WidgetSpan
    final spans = _buildSpans(raw);

    // If for some reason spans are empty, fallback to normal Text
    if (spans.isEmpty) {
      return Text(
        raw,
        style: style,
        textDirection: textDirection,
        textAlign: textAlign,
        maxLines: maxLines,
        overflow: overflow,
        softWrap: softWrap,
        strutStyle: strutStyle,
      );
    }

    return RichText(
      textDirection: textDirection,
      textAlign: textAlign ?? TextAlign.start,
      softWrap: softWrap,
      maxLines: maxLines,
      overflow: overflow ?? TextOverflow.clip,
      strutStyle: strutStyle,
      text: TextSpan(style: style, children: spans),
    );
  }

  List<InlineSpan> _buildSpans(String input) {
    final List<InlineSpan> out = [];

    int last = 0;
    final matches = _tokenRegex.allMatches(input);

    for (final m in matches) {
      final start = m.start;
      final end = m.end;

      // text before token
      if (start > last) {
        out.add(TextSpan(text: input.substring(last, start)));
      }

      final token = input.substring(start, end);
      final asset = tokenToAsset[token];

      if (asset == null) {
        // Unknown token -> render as text (no crash)
        out.add(TextSpan(text: token));
      } else {
        out.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Image.asset(
                asset,
                width: 18,
                height: 18,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
              ),
            ),
          ),
        );
      }

      last = end;
    }

    // remaining text
    if (last < input.length) {
      out.add(TextSpan(text: input.substring(last)));
    }

    return out;
  }
}

class _TokenSticker extends StatelessWidget {
  final String asset;
  final double size;

  const _TokenSticker({
    required this.asset,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      asset,
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
    );
  }
}
