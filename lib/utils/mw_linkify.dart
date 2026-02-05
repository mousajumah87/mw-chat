// lib/utils/mw_linkify.dart
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_theme.dart';
import '../widgets/chat/mw_token_text.dart';

enum _LinkKind { url, email, phone }

class _Token {
  final String text;
  final bool isLink;
  final _LinkKind? kind;
  final String? payload; // the value we open (mailto/tel/https)
  const _Token.text(this.text)
      : isLink = false,
        kind = null,
        payload = null;

  const _Token.link(this.text, this.kind, this.payload) : isLink = true;
}

class MwLinkify {
  // --- Patterns ---
  static final RegExp _urlRegex = RegExp(
    r'((https?:\/\/|www\.)[^\s<>()]+)',
    caseSensitive: false,
  );

  static final RegExp _emailRegex = RegExp(
    r'([A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,})',
    caseSensitive: false,
  );

  // WhatsApp-like phone:
  // - allow +, spaces, -, (), dots
  // - must contain at least 7 digits total
  // - avoid matching inside words/emails
  static final RegExp _phoneCandidateRegex = RegExp(
    r'(?<![A-Za-z0-9@])(\+?[\d][\d\s().\-]{5,}[\d])(?![A-Za-z0-9])',
    caseSensitive: false,
  );

  static String _normalizeUrl(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return t;
    final low = t.toLowerCase();
    if (low.startsWith('http://') || low.startsWith('https://')) return t;
    if (low.startsWith('www.')) return 'https://$t';
    return t;
  }

  static String _digitsOnly(String s) => s.replaceAll(RegExp(r'[^\d+]'), '');

  static bool _looksLikePhone(String raw) {
    final cleaned = _digitsOnly(raw);
    if (cleaned.isEmpty) return false;

    // count digits (ignore +)
    final digitsCount = cleaned.replaceAll('+', '').length;

    // WhatsApp-ish: 7..15 digits is a practical bound
    if (digitsCount < 7 || digitsCount > 15) return false;

    // prevent weird "00...." extremely long already handled above
    return true;
  }

  static Future<void> _safeLaunch(Uri uri) async {
    try {
      if (kIsWeb) {
        // Web: open in new tab/window
        await launchUrl(uri, webOnlyWindowName: '_blank');
      } else {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      // Optional fallback: copy to clipboard (silent)
      try {
        await Clipboard.setData(ClipboardData(text: uri.toString()));
      } catch (_) {}
    }
  }

  static Future<void> _openUrl(String raw) async {
    final normalized = _normalizeUrl(raw);
    final uri = Uri.tryParse(normalized);
    if (uri == null) return;
    await _safeLaunch(uri);
  }

  static Future<void> _openEmail(String email) async {
    final e = email.trim();
    if (e.isEmpty) return;
    final uri = Uri(scheme: 'mailto', path: e);
    await _safeLaunch(uri);
  }

  static Future<void> _openPhone(String phoneRaw) async {
    final p = phoneRaw.trim();
    if (p.isEmpty) return;

    final normalized = _digitsOnly(p);
    if (normalized.isEmpty) return;

    final uri = Uri(scheme: 'tel', path: normalized);
    await _safeLaunch(uri);
  }

  static List<_Token> tokenize(String text) {
    if (text.isEmpty) return const [];

    // We find ALL matches for URL/email/phone and then pick the earliest-next match each step.
    final urlMatches = _urlRegex.allMatches(text).toList();
    final emailMatches = _emailRegex.allMatches(text).toList();
    final phoneMatches = _phoneCandidateRegex.allMatches(text).toList();

    int iUrl = 0, iEmail = 0, iPhone = 0;
    int cursor = 0;

    final out = <_Token>[];

    _Token? nextToken() {
      Match? mu, me, mp;

      if (iUrl < urlMatches.length) mu = urlMatches[iUrl];
      if (iEmail < emailMatches.length) me = emailMatches[iEmail];
      if (iPhone < phoneMatches.length) mp = phoneMatches[iPhone];

      // Choose earliest start
      Match? best = mu;
      if (best == null || (me != null && me.start < best.start)) best = me;
      if (best == null || (mp != null && mp.start < best.start)) best = mp;

      if (best == null) return null;

      // Advance the pointer that we used
      if (best == mu) iUrl++;
      if (best == me) iEmail++;
      if (best == mp) iPhone++;

      // Build token
      final raw = text.substring(best.start, best.end);

      // Emails should win over "phone candidate" that may overlap (rare)
      if (_emailRegex.hasMatch(raw)) {
        return _Token.link(raw, _LinkKind.email, raw);
      }

      if (_urlRegex.hasMatch(raw)) {
        return _Token.link(raw, _LinkKind.url, raw);
      }

      // Phone:
      if (_looksLikePhone(raw)) {
        return _Token.link(raw, _LinkKind.phone, raw);
      }

      // Not valid phone -> treat as normal text
      return _Token.text(raw);
    }

    while (cursor < text.length) {
      final tok = nextToken();
      if (tok == null) break;

      // If this token begins before cursor (overlap), skip it safely
      final start = text.indexOf(tok.text, cursor);
      if (start < cursor) {
        // continue scanning, ignore this overlap case
        continue;
      }

      if (start > cursor) {
        out.add(_Token.text(text.substring(cursor, start)));
      }

      out.add(tok);

      cursor = start + tok.text.length;
    }

    if (cursor < text.length) {
      out.add(_Token.text(text.substring(cursor)));
    }

    return out;
  }

  static Widget build({
    required String text,
    required TextStyle style,
    required TextDirection textDirection,
    required TextAlign textAlign,
    required bool disableLinks,
    int? maxLines,
    TextOverflow? overflow,
  }) {
    if (text.isEmpty) return const SizedBox.shrink();

    if (disableLinks) {
      return MwTokenText(
        text: text,
        style: style,
        textDirection: textDirection,
        textAlign: textAlign,
        maxLines: maxLines,
        overflow: overflow,
      );
    }

    final tokens = tokenize(text);

    // If nothing link-like, keep it simple (better layout/perf)
    final hasAnyLink = tokens.any((t) => t.isLink);
    if (!hasAnyLink) {
      return MwTokenText(
        text: text,
        style: style,
        textDirection: textDirection,
        textAlign: textAlign,
        maxLines: maxLines,
        overflow: overflow,
      );
    }

    final linkStyle = style.copyWith(
      decoration: TextDecoration.underline,
      color: kPrimaryGold.withOpacity(0.95),
      fontWeight: FontWeight.w700,
    );

    final children = <Widget>[];

    for (final t in tokens) {
      if (!t.isLink) {
        if (t.text.isEmpty) continue;
        children.add(
          MwTokenText(
            text: t.text,
            style: style,
            textDirection: textDirection,
            textAlign: textAlign,
            maxLines: maxLines,
            overflow: overflow,
          ),
        );
        continue;
      }

      final kind = t.kind!;
      final payload = (t.payload ?? '').trim();
      if (payload.isEmpty) {
        children.add(Text(t.text, style: style));
        continue;
      }

      VoidCallback onTap;
      switch (kind) {
        case _LinkKind.url:
          onTap = () => _openUrl(payload);
          break;
        case _LinkKind.email:
          onTap = () => _openEmail(payload);
          break;
        case _LinkKind.phone:
          onTap = () => _openPhone(payload);
          break;
      }

      // For phone/email/url we force LTR for the clickable chunk
      children.add(
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Text(
            t.text,
            textDirection: TextDirection.ltr,
            style: linkStyle,
          ),
        ),
      );
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
          children: children,
        ),
      ),
    );
  }
}
