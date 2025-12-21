// lib/widgets/ui/mw_search_field.dart
import 'dart:async';
import 'package:flutter/material.dart';

class MwSearchField extends StatefulWidget {
  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String> onChanged;

  /// Optional debounce (default 250ms)
  final Duration debounce;

  /// If you want it to look like MW glass cards
  final bool glass;

  /// Optional: called when user hits submit/search on keyboard
  final ValueChanged<String>? onSubmitted;

  /// Optional: called when clear button pressed
  final VoidCallback? onClear;

  /// Optional: autofocus
  final bool autofocus;

  /// Optional: force RTL/LTR if you want
  final TextDirection? textDirection;

  /// Optional: enable/disable
  final bool enabled;

  const MwSearchField({
    super.key,
    required this.controller,
    required this.hintText,
    required this.onChanged,
    this.debounce = const Duration(milliseconds: 250),
    this.glass = true,
    this.onSubmitted,
    this.onClear,
    this.autofocus = false,
    this.textDirection,
    this.enabled = true,
  });

  @override
  State<MwSearchField> createState() => _MwSearchFieldState();
}

class _MwSearchFieldState extends State<MwSearchField> {
  Timer? _debounce;

  void _emit(String v) {
    _debounce?.cancel();
    _debounce = Timer(widget.debounce, () {
      if (!mounted) return;
      widget.onChanged(v);
    });
  }

  void _clear() {
    widget.controller.clear();
    widget.onChanged('');
    widget.onClear?.call();
    FocusScope.of(context).unfocus();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final effectiveDir = widget.textDirection ?? Directionality.of(context);

    return Directionality(
      textDirection: effectiveDir,
      child: TextField(
        controller: widget.controller,
        enabled: widget.enabled,
        autofocus: widget.autofocus,
        textInputAction: TextInputAction.search,
        onChanged: _emit,
        onSubmitted: (v) => widget.onSubmitted?.call(v),
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: widget.hintText,
          hintStyle: const TextStyle(color: Colors.white54),
          prefixIcon: const Icon(Icons.search, color: Colors.white70),
          suffixIcon: ValueListenableBuilder<TextEditingValue>(
            valueListenable: widget.controller,
            builder: (_, value, __) {
              final hasText = value.text.trim().isNotEmpty;
              if (!hasText) return const SizedBox.shrink();
              return IconButton(
                tooltip: 'Clear',
                icon: const Icon(Icons.close, color: Colors.white70),
                onPressed: _clear,
              );
            },
          ),
          filled: true,
          fillColor: widget.glass ? Colors.white.withOpacity(0.08) : Colors.white10,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(999),
            borderSide: const BorderSide(color: Colors.white24),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(999),
            borderSide: BorderSide(
              color: theme.colorScheme.secondary.withOpacity(0.9),
            ),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
      ),
    );
  }
}
