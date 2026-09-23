import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

const _anonIdKey = 'com.feedbackjar.sdk.anonId';

/// A stable per-install anonymous id, persisted via `shared_preferences` and
/// cached in memory.
///
/// Used to attribute guest votes/comments to the same install. Not a device id —
/// a fresh random UUIDv4 that resets on reinstall / clear-data. The server HMACs
/// it before storage, so it only needs to be unique, not unguessable.
class AnonId {
  AnonId._();

  static String? _cached;
  static Future<String>? _pending;

  /// The current install's anonymous id, generating and persisting one on first
  /// use. Concurrent callers share a single generate/persist pass.
  static Future<String> get() async {
    final cached = _cached;
    if (cached != null) return cached;
    return _pending ??= _load();
  }

  static Future<String> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final existing = prefs.getString(_anonIdKey);
      if (existing != null && existing.isNotEmpty) {
        _cached = existing;
        return existing;
      }
      final fresh = _uuidv4();
      await prefs.setString(_anonIdKey, fresh);
      _cached = fresh;
      return fresh;
    } finally {
      _pending = null;
    }
  }

  /// RFC-4122 v4, from [Random]. This id only needs to be unique, not
  /// unguessable (the server HMACs it before storage).
  static String _uuidv4() {
    final rng = Random();
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 10
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}
