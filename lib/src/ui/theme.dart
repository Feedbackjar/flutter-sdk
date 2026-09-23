import 'package:flutter/material.dart';

/// Default accent — FeedbackJar red. Caller-overridable via `accentColor`.
const Color kDefaultAccent = Color(0xFFE5484D);

/// One corner radius for buttons and inputs. Nothing else is rounded.
const double kRadius = 8;

/// Two font sizes only — body and small. One bold weight for titles/counts.
const double kFontBody = 15;
const double kFontSmall = 13;

/// Resolved palette: one accent, three greys, plus the surface background.
/// Follows the OS light/dark setting.
class FbTheme {
  final Color accent;
  final Color bg;
  final Color text;
  final Color textDim;
  final Color divider;
  final Color fieldBg;

  const FbTheme({
    required this.accent,
    required this.bg,
    required this.text,
    required this.textDim,
    required this.divider,
    required this.fieldBg,
  });

  factory FbTheme.resolve(Brightness brightness, Color accent) {
    if (brightness == Brightness.dark) {
      return FbTheme(
        accent: accent,
        bg: const Color(0xFF151515),
        text: const Color(0xFFF2F2F2),
        textDim: const Color(0xFF9A9A9A),
        divider: const Color(0xFF2C2C2C),
        fieldBg: const Color(0xFF242424),
      );
    }
    return FbTheme(
      accent: accent,
      bg: const Color(0xFFFFFFFF),
      text: const Color(0xFF1A1A1A),
      textDim: const Color(0xFF767676),
      divider: const Color(0xFFE6E6E6),
      fieldBg: const Color(0xFFF4F4F4),
    );
  }
}

/// Compact relative time: "just now", "3h", "2d", "5w".
String relativeTime(String iso) {
  final then = DateTime.tryParse(iso);
  if (then == null) return '';
  var s = DateTime.now().difference(then).inSeconds;
  if (s < 0) s = 0;
  if (s < 60) return 'just now';
  if (s < 3600) return '${s ~/ 60}m';
  if (s < 86400) return '${s ~/ 3600}h';
  if (s < 604800) return '${s ~/ 86400}d';
  return '${s ~/ 604800}w';
}

/// `OPEN` -> "Open", `IN_PROGRESS` -> "In progress".
String humanStatus(String status) {
  final s = status.replaceAll('_', ' ').toLowerCase();
  if (s.isEmpty) return s;
  return s[0].toUpperCase() + s.substring(1);
}

/// SDK failures arrive as `Exception('server message')`. Show the message
/// verbatim, without the `Exception: ` prefix.
String errorText(Object error) {
  final s = error.toString();
  const prefix = 'Exception: ';
  return s.startsWith(prefix) ? s.substring(prefix.length) : s;
}
