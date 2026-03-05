import 'dart:async';
import 'package:flutter/foundation.dart';

class OtpCooldownController {
  Timer? _t;

  /// Remaining seconds
  final ValueNotifier<int> seconds = ValueNotifier<int>(0);

  bool get isActive => seconds.value > 0;
  bool get canSend => seconds.value == 0;

  void start([int initialSeconds = 45]) {
    cancel();
    seconds.value = initialSeconds;

    _t = Timer.periodic(const Duration(seconds: 1), (t) {
      final v = seconds.value;
      if (v <= 1) {
        cancel();
      } else {
        seconds.value = v - 1;
      }
    });
  }

  void cancel() {
    _t?.cancel();
    _t = null;
    seconds.value = 0;
  }

  void dispose() {
    cancel();
    seconds.dispose();
  }
}