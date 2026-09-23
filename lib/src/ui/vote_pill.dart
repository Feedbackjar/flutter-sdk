import 'package:flutter/material.dart';

import '../feedbackjar_sdk.dart';
import '../models.dart';
import 'theme.dart';

/// Up-chevron glyph + count. Filled/accent when voted, outline otherwise.
/// Toggles optimistically and rolls back on failure. The chevron is drawn
/// with a [CustomPainter] — no icon font or SVG dependency.
class VotePill extends StatefulWidget {
  final String postId;
  final int upvotes;
  final bool hasVoted;
  final FbTheme theme;

  /// Called with the authoritative count/state after a successful toggle.
  final void Function(int upvotes, bool hasVoted)? onChange;

  const VotePill({
    super.key,
    required this.postId,
    required this.upvotes,
    required this.hasVoted,
    required this.theme,
    this.onChange,
  });

  @override
  State<VotePill> createState() => _VotePillState();
}

class _VotePillState extends State<VotePill> {
  late int _upvotes = widget.upvotes;
  late bool _hasVoted = widget.hasVoted;
  bool _busy = false;

  @override
  void didUpdateWidget(VotePill oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Keep in sync when the parent list refreshes.
    if (!_busy &&
        (widget.upvotes != _upvotes || widget.hasVoted != _hasVoted)) {
      _upvotes = widget.upvotes;
      _hasVoted = widget.hasVoted;
    }
  }

  Future<void> _toggle() async {
    if (_busy) return;
    final prevUpvotes = _upvotes;
    final prevVoted = _hasVoted;
    setState(() {
      _busy = true;
      _hasVoted = !prevVoted;
      _upvotes =
          prevVoted ? (prevUpvotes > 0 ? prevUpvotes - 1 : 0) : prevUpvotes + 1;
    });

    final result = prevVoted
        ? await FeedbackJar.shared.unvote(widget.postId)
        : await FeedbackJar.shared.vote(widget.postId);
    if (!mounted) return;

    setState(() {
      _busy = false;
      switch (result) {
        case FeedbackSuccess(:final value):
          _upvotes = value.upvotes;
          _hasVoted = value.hasVoted;
          widget.onChange?.call(value.upvotes, value.hasVoted);
        case FeedbackFailure():
          _upvotes = prevUpvotes;
          _hasVoted = prevVoted;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.theme;
    final active = _hasVoted;
    final glyph = active ? Colors.white : t.textDim;

    return Semantics(
      button: true,
      label: '${active ? 'Remove upvote' : 'Upvote'}, $_upvotes votes',
      child: InkWell(
        borderRadius: BorderRadius.circular(kRadius),
        onTap: _toggle,
        child: Container(
          constraints: const BoxConstraints(minWidth: 44),
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
          decoration: BoxDecoration(
            color: active ? t.accent : Colors.transparent,
            border: Border.all(color: active ? t.accent : t.divider),
            borderRadius: BorderRadius.circular(kRadius),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CustomPaint(
                size: const Size(10, 6),
                painter: _ChevronPainter(glyph),
              ),
              const SizedBox(height: 3),
              Text(
                '$_upvotes',
                style: TextStyle(
                  fontSize: kFontSmall,
                  fontWeight: FontWeight.w700,
                  color: active ? Colors.white : t.text,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChevronPainter extends CustomPainter {
  final Color color;

  _ChevronPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final path = Path()
      ..moveTo(0, size.height)
      ..lineTo(size.width / 2, 0)
      ..lineTo(size.width, size.height);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_ChevronPainter oldDelegate) => oldDelegate.color != color;
}
