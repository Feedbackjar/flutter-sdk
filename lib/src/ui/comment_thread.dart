import 'package:flutter/material.dart';

import '../models.dart';
import 'rich_text.dart';
import 'theme.dart';

/// Two-level comment threads. Root comments carry their [FeedbackComment.replies];
/// each reply is indented one step under its root with the same layout.
/// An `authorRole` shows a tiny accent "TEAM" tag after the name.
class CommentThread extends StatelessWidget {
  final List<FeedbackComment> comments;
  final FbTheme theme;

  /// When set, root comments show a "Reply" action.
  final void Function(FeedbackComment comment)? onReply;

  /// Open a post referenced by a `#[…]` mention in a comment.
  final void Function(String postId)? onPostPress;

  const CommentThread({
    super.key,
    required this.comments,
    required this.theme,
    this.onReply,
    this.onPostPress,
  });

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (final c in comments) {
      rows.add(_CommentRow(
        comment: c,
        theme: theme,
        indented: false,
        onReply: onReply == null ? null : () => onReply!(c),
        onPostPress: onPostPress,
      ));
      for (final r in c.replies) {
        rows.add(_CommentRow(
          comment: r,
          theme: theme,
          indented: true,
          onPostPress: onPostPress,
        ));
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const SizedBox(height: 18),
          rows[i],
        ],
      ],
    );
  }
}

class _CommentRow extends StatelessWidget {
  final FeedbackComment comment;
  final FbTheme theme;
  final bool indented;
  final VoidCallback? onReply;
  final void Function(String postId)? onPostPress;

  const _CommentRow({
    required this.comment,
    required this.theme,
    required this.indented,
    this.onReply,
    this.onPostPress,
  });

  @override
  Widget build(BuildContext context) {
    final t = theme;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(
            style: const TextStyle(fontSize: kFontSmall),
            children: [
              TextSpan(
                text: comment.authorName,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: t.text,
                ),
              ),
              if (comment.authorRole != null)
                TextSpan(
                  text: '  TEAM',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: kFontSmall - 1,
                    color: t.accent,
                  ),
                ),
              TextSpan(
                text: '  ${relativeTime(comment.createdAt)}',
                style: TextStyle(color: t.textDim),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        FbRichText(
          content: comment.content,
          theme: t,
          onPostPress: onPostPress,
        ),
        if (onReply != null) ...[
          const SizedBox(height: 2),
          Semantics(
            button: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onReply,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  'Reply',
                  style: TextStyle(
                    fontSize: kFontSmall,
                    fontWeight: FontWeight.w700,
                    color: t.accent,
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );

    if (!indented) return content;
    return Container(
      margin: const EdgeInsets.only(left: 16),
      padding: const EdgeInsets.only(left: 12),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: t.divider)),
      ),
      child: content,
    );
  }
}
