import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class VoipTokenSync {
  static const _ch = MethodChannel('mw.voip');
  static bool _inited = false;

  static void ensureInit() {
    if (_inited) return;
    _inited = true;

    _ch.setMethodCallHandler((call) async {
      if (call.method != 'voipToken') return;
      final token = (call.arguments ?? '').toString().trim();
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'voipToken': token,
        'voipUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
  }
}
