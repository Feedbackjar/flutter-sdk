import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'theme.dart';

/// Dependency-free renderer for the subset of Markdown feedback posts and
/// comments use, plus FeedbackJar mention tokens:
///
/// - `#[Post title](postId)`                    -> post reference chip (tappable)
/// - `@[Name](user:id | guest:id | post:id)`    -> user mention
/// - **bold**, *italic*, `code`, [links](url), bare URLs
/// - headings, `-`/`1.` lists, `>` quotes, ``` fenced code
///
/// Single newlines are hard breaks (matches the web renderer's `remark-breaks`).

// ---------------------------------------------------------------------------
// Parser
// ---------------------------------------------------------------------------

sealed class _Inline {
  const _Inline();
}

class _Text extends _Inline {
  final String value;
  const _Text(this.value);
}

class _Strong extends _Inline {
  final List<_Inline> children;
  const _Strong(this.children);
}

class _Em extends _Inline {
  final List<_Inline> children;
  const _Em(this.children);
}

class _Code extends _Inline {
  final String value;
  const _Code(this.value);
}

class _Link extends _Inline {
  final String href;
  final List<_Inline> children;
  const _Link(this.href, this.children);
}

class _PostMention extends _Inline {
  final String title;
  final String postId;
  const _PostMention(this.title, this.postId);
}

class _UserMention extends _Inline {
  final String name;
  const _UserMention(this.name);
}

sealed class _Block {
  const _Block();
}

class _Paragraph extends _Block {
  final List<_Inline> children;
  const _Paragraph(this.children);
}

class _Heading extends _Block {
  final int level;
  final List<_Inline> children;
  const _Heading(this.level, this.children);
}

class _BulletList extends _Block {
  final List<List<_Inline>> items;
  const _BulletList(this.items);
}

class _OrderedList extends _Block {
  final List<List<_Inline>> items;
  const _OrderedList(this.items);
}

class _Quote extends _Block {
  final List<_Inline> children;
  const _Quote(this.children);
}

class _CodeBlock extends _Block {
  final String value;
  const _CodeBlock(this.value);
}

final _postMention = RegExp(r'^#\[([^\]]+)\]\(([^)]+)\)');
final _userMention = RegExp(r'^@\[([^\]]+)\]\((?:user|guest|post):([^)]+)\)');
final _codeSpan = RegExp(r'^(`+)([\s\S]+?)\1');
final _link = RegExp(r'^\[([^\]]+)\]\(([^)\s]+)(?:\s+"[^"]*")?\)');
final _strong = RegExp(r'^(\*\*|__)([\s\S]+?)\1');
final _em = RegExp(r'^(\*|_)(\S(?:[\s\S]*?\S)?|\S)\1');
final _autolink = RegExp(r'''^(https?://[^\s<]+[^\s<.,:;"'!?)\]])''');
final _nextSpecial = RegExp(r'[`#@[*_]|https?://');

List<_Inline> _parseInline(String src) {
  final out = <_Inline>[];
  var rest = src;
  final buf = StringBuffer();
  void flush() {
    if (buf.isNotEmpty) {
      out.add(_Text(buf.toString()));
      buf.clear();
    }
  }

  while (rest.isNotEmpty) {
    var m = _codeSpan.firstMatch(rest);
    if (m != null) {
      flush();
      out.add(_Code(m.group(2)!.trim()));
      rest = rest.substring(m.end);
      continue;
    }
    m = _postMention.firstMatch(rest);
    if (m != null) {
      flush();
      out.add(_PostMention(m.group(1)!.trim(), m.group(2)!.trim()));
      rest = rest.substring(m.end);
      continue;
    }
    m = _userMention.firstMatch(rest);
    if (m != null) {
      flush();
      out.add(_UserMention(m.group(1)!.trim()));
      rest = rest.substring(m.end);
      continue;
    }
    m = _link.firstMatch(rest);
    if (m != null) {
      flush();
      out.add(_Link(m.group(2)!, _parseInline(m.group(1)!)));
      rest = rest.substring(m.end);
      continue;
    }
    m = _strong.firstMatch(rest);
    if (m != null) {
      flush();
      out.add(_Strong(_parseInline(m.group(2)!)));
      rest = rest.substring(m.end);
      continue;
    }
    m = _em.firstMatch(rest);
    if (m != null) {
      flush();
      out.add(_Em(_parseInline(m.group(2)!)));
      rest = rest.substring(m.end);
      continue;
    }
    m = _autolink.firstMatch(rest);
    if (m != null) {
      flush();
      final url = m.group(1)!;
      out.add(_Link(url, [_Text(url)]));
      rest = rest.substring(m.end);
      continue;
    }

    final next = _nextSpecial.firstMatch(rest.substring(1));
    if (next == null) {
      buf.write(rest);
      rest = '';
    } else {
      final cut = next.start + 1;
      buf.write(rest.substring(0, cut));
      rest = rest.substring(cut);
    }
  }
  flush();
  return out;
}

final _heading = RegExp(r'^(#{1,6})\s+(.*)$');
final _fence = RegExp(r'^(```|~~~)');
final _quote = RegExp(r'^>\s?');
final _bullet = RegExp(r'^\s*[-*+]\s+');
final _ordered = RegExp(r'^\s*\d+[.)]\s+');

List<_Block> _parseBlocks(String md) {
  final lines = md.replaceAll(RegExp(r'\r\n?'), '\n').split('\n');
  final blocks = <_Block>[];
  var i = 0;

  while (i < lines.length) {
    final line = lines[i];

    if (line.trim().isEmpty) {
      i++;
      continue;
    }

    if (_fence.hasMatch(line.trim())) {
      i++;
      final body = <String>[];
      while (i < lines.length && !_fence.hasMatch(lines[i].trim())) {
        body.add(lines[i]);
        i++;
      }
      i++; // closing fence
      blocks.add(_CodeBlock(body.join('\n')));
      continue;
    }

    final h = _heading.firstMatch(line);
    if (h != null) {
      blocks
          .add(_Heading(h.group(1)!.length, _parseInline(h.group(2)!.trim())));
      i++;
      continue;
    }

    if (_quote.hasMatch(line)) {
      final q = <String>[];
      while (i < lines.length && _quote.hasMatch(lines[i])) {
        q.add(lines[i].replaceFirst(_quote, ''));
        i++;
      }
      blocks.add(_Quote(_parseInline(q.join('\n'))));
      continue;
    }

    if (_bullet.hasMatch(line)) {
      final items = <List<_Inline>>[];
      while (i < lines.length && _bullet.hasMatch(lines[i])) {
        items.add(_parseInline(lines[i].replaceFirst(_bullet, '')));
        i++;
      }
      blocks.add(_BulletList(items));
      continue;
    }

    if (_ordered.hasMatch(line)) {
      final items = <List<_Inline>>[];
      while (i < lines.length && _ordered.hasMatch(lines[i])) {
        items.add(_parseInline(lines[i].replaceFirst(_ordered, '')));
        i++;
      }
      blocks.add(_OrderedList(items));
      continue;
    }

    final para = <String>[];
    while (i < lines.length &&
        lines[i].trim().isNotEmpty &&
        !_heading.hasMatch(lines[i]) &&
        !_bullet.hasMatch(lines[i]) &&
        !_ordered.hasMatch(lines[i]) &&
        !_quote.hasMatch(lines[i]) &&
        !_fence.hasMatch(lines[i].trim())) {
      para.add(lines[i]);
      i++;
    }
    blocks.add(_Paragraph(_parseInline(para.join('\n'))));
  }

  return blocks;
}

/// Flatten Markdown + mention tokens to readable one-line text (list previews).
String toPlainText(String md) {
  return md
      .replaceAll(RegExp(r'```[\s\S]*?```'), ' ')
      .replaceAllMapped(RegExp(r'`([^`]+)`'), (m) => m.group(1)!)
      .replaceAllMapped(RegExp(r'#\[([^\]]+)\]\([^)]+\)'), (m) => m.group(1)!)
      .replaceAllMapped(
        RegExp(r'@\[([^\]]+)\]\((?:user|guest|post):[^)]+\)'),
        (m) => m.group(1)!,
      )
      .replaceAllMapped(RegExp(r'\[([^\]]+)\]\([^)]+\)'), (m) => m.group(1)!)
      .replaceAll(RegExp(r'(\*\*|__|~~|\*|_)'), '')
      .replaceAll(RegExp(r'^\s{0,3}#{1,6}\s+', multiLine: true), '')
      .replaceAll(RegExp(r'^\s*[-*+]\s+', multiLine: true), '')
      .replaceAll(RegExp(r'^\s*\d+[.)]\s+', multiLine: true), '')
      .replaceAll(RegExp(r'^\s*>\s?', multiLine: true), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

// ---------------------------------------------------------------------------
// Widget
// ---------------------------------------------------------------------------

/// Render feedback post / comment content with mentions and light Markdown.
class FbRichText extends StatefulWidget {
  final String content;
  final FbTheme theme;

  /// Called with the target post id when a `#[…]` reference is tapped.
  final void Function(String postId)? onPostPress;

  const FbRichText({
    super.key,
    required this.content,
    required this.theme,
    this.onPostPress,
  });

  @override
  State<FbRichText> createState() => _FbRichTextState();
}

class _FbRichTextState extends State<FbRichText> {
  final _recognizers = <TapGestureRecognizer>[];

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  TapGestureRecognizer _tap(VoidCallback onTap) {
    final r = TapGestureRecognizer()..onTap = onTap;
    _recognizers.add(r);
    return r;
  }

  @override
  Widget build(BuildContext context) {
    _disposeRecognizers();
    final blocks = _parseBlocks(widget.content);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < blocks.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          _block(blocks[i]),
        ],
      ],
    );
  }

  Widget _block(_Block block) {
    final t = widget.theme;
    final base = TextStyle(fontSize: kFontBody, height: 1.4, color: t.text);

    switch (block) {
      case _Paragraph(:final children):
        return Text.rich(TextSpan(style: base, children: _spans(children)));
      case _Heading(:final level, :final children):
        return Text.rich(TextSpan(
          style: base.copyWith(
            fontWeight: FontWeight.w700,
            fontSize: level <= 1 ? kFontBody + 2 : kFontBody,
          ),
          children: _spans(children),
        ));
      case _Quote(:final children):
        return Container(
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: t.fieldBg, width: 2)),
          ),
          padding: const EdgeInsets.only(left: 10),
          child: Text.rich(TextSpan(
            style: base.copyWith(color: t.textDim),
            children: _spans(children),
          )),
        );
      case _BulletList(:final items):
        return _list([for (final _ in items) '•'], items, base);
      case _OrderedList(:final items):
        return _list(
            [for (var i = 0; i < items.length; i++) '${i + 1}.'], items, base);
      case _CodeBlock(:final value):
        return Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: t.fieldBg,
            borderRadius: BorderRadius.circular(kRadius),
          ),
          padding: const EdgeInsets.all(10),
          child: Text(
            value,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: kFontSmall,
              height: 1.35,
              color: t.text,
            ),
          ),
        );
    }
  }

  Widget _list(
      List<String> markers, List<List<_Inline>> items, TextStyle base) {
    final t = widget.theme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(markers[i], style: base.copyWith(color: t.textDim)),
              const SizedBox(width: 8),
              Expanded(
                child: Text.rich(
                  TextSpan(style: base, children: _spans(items[i])),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  List<InlineSpan> _spans(List<_Inline> nodes) {
    final t = widget.theme;
    final out = <InlineSpan>[];
    for (final n in nodes) {
      switch (n) {
        case _Text(:final value):
          out.add(TextSpan(text: value));
        case _Strong(:final children):
          out.add(TextSpan(
            style: const TextStyle(fontWeight: FontWeight.w700),
            children: _spans(children),
          ));
        case _Em(:final children):
          out.add(TextSpan(
            style: const TextStyle(fontStyle: FontStyle.italic),
            children: _spans(children),
          ));
        case _Code(:final value):
          out.add(TextSpan(
            text: value,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: kFontSmall,
              backgroundColor: t.fieldBg,
            ),
          ));
        case _Link(:final href, :final children):
          out.add(TextSpan(
            style: TextStyle(color: t.accent),
            recognizer: _tap(() => _openUrl(href)),
            children: _spans(children),
          ));
        case _UserMention(:final name):
          out.add(TextSpan(
            text: '@$name',
            style: TextStyle(fontWeight: FontWeight.w700, color: t.accent),
          ));
        case _PostMention(:final title, :final postId):
          out.add(TextSpan(
            text: ' #$title ',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: kFontSmall,
              color: t.accent,
              backgroundColor: t.accent.withAlpha(31), // ~12%
            ),
            recognizer: widget.onPostPress == null
                ? null
                : _tap(() => widget.onPostPress!(postId)),
          ));
      }
    }
    return out;
  }

  void _openUrl(String href) {
    // Defer to the host app's URL handling if it wired one; otherwise no-op.
    // Kept dependency-free — the SDK does not bundle url_launcher.
    debugPrint('[FeedbackJar] link tapped: $href');
  }
}
