import 'package:flutter/material.dart';

import '../feedbackjar_sdk.dart';
import '../models.dart';
import 'comment_thread.dart';
import 'rich_text.dart';
import 'theme.dart';
import 'vote_pill.dart';

/// The detail screen: title, full content, author + relative date, vote pill,
/// then the comment thread with a composer pinned to the bottom. The composer
/// is hidden when [WidgetConfig.allowComments] is false (existing comments
/// still render read-only).
class FeedbackDetailScreen extends StatefulWidget {
  final FeedbackPost post;
  final WidgetConfig config;
  final FbTheme theme;
  final VoidCallback onBack;
  final void Function(int upvotes, bool hasVoted)? onVoteChange;

  /// Open a post referenced by a `#[…]` mention in the body or a comment.
  final void Function(String postId)? onPostPress;

  const FeedbackDetailScreen({
    super.key,
    required this.post,
    required this.config,
    required this.theme,
    required this.onBack,
    this.onVoteChange,
    this.onPostPress,
  });

  @override
  State<FeedbackDetailScreen> createState() => _FeedbackDetailScreenState();
}

class _FeedbackDetailScreenState extends State<FeedbackDetailScreen> {
  final _draft = TextEditingController();
  List<FeedbackComment> _comments = const [];
  bool _loading = true;
  bool _sending = false;
  String? _error;
  FeedbackComment? _replyTo;

  @override
  void initState() {
    super.initState();
    _draft.addListener(_onChanged);
    _load();
  }

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  void _onChanged() => setState(() {});

  Future<void> _load() async {
    final result =
        await FeedbackJar.shared.listComments(widget.post.id, limit: 50);
    if (!mounted) return;
    setState(() {
      _loading = false;
      switch (result) {
        case FeedbackSuccess(:final value):
          _comments = value.comments;
          _error = null;
        case FeedbackFailure(:final error):
          _error = errorText(error);
      }
    });
  }

  Future<void> _send() async {
    final content = _draft.text.trim();
    if (content.isEmpty || _sending) return;
    setState(() => _sending = true);

    final result = await FeedbackJar.shared.addComment(
      widget.post.id,
      content,
      parentId: _replyTo?.id,
    );
    if (!mounted) return;
    setState(() => _sending = false);

    switch (result) {
      case FeedbackSuccess():
        _draft.clear();
        setState(() => _replyTo = null);
        await _load();
      case FeedbackFailure(:final error):
        setState(() => _error = errorText(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.theme;
    final post = widget.post;

    return Container(
      color: t.bg,
      child: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Semantics(
                button: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.onBack,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    child: Text(
                      '‹ Back',
                      style: TextStyle(fontSize: kFontBody, color: t.accent),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          post.title,
                          style: TextStyle(
                            fontSize: kFontBody,
                            fontWeight: FontWeight.w700,
                            height: 1.4,
                            color: t.text,
                          ),
                        ),
                      ),
                      if (widget.config.allowVotes) ...[
                        const SizedBox(width: 12),
                        VotePill(
                          postId: post.id,
                          upvotes: post.upvotes,
                          hasVoted: post.hasVoted,
                          theme: t,
                          onChange: widget.onVoteChange,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _metaLine(post),
                    style: TextStyle(fontSize: kFontSmall, color: t.textDim),
                  ),
                  const SizedBox(height: 10),
                  FbRichText(
                    content: post.content,
                    theme: t,
                    onPostPress: widget.onPostPress,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Divider(height: 1, color: t.divider),
                  ),
                  Text(
                    'Comments',
                    style: TextStyle(
                      fontSize: kFontBody,
                      fontWeight: FontWeight.w700,
                      color: t.text,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _commentsBody(t),
                ],
              ),
            ),
            if (widget.config.allowComments) _composer(t),
          ],
        ),
      ),
    );
  }

  String _metaLine(FeedbackPost post) {
    final parts = <String>[humanStatus(post.status)];
    if (post.authorName != null) parts.add(post.authorName!);
    final rel = relativeTime(post.createdAt);
    if (rel.isNotEmpty) parts.add(rel);
    return parts.join(' · ');
  }

  Widget _commentsBody(FbTheme t) {
    if (_loading) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(t.accent),
            ),
          ),
        ),
      );
    }
    if (_comments.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _error ?? 'No comments yet.',
            style: TextStyle(
              fontSize: kFontSmall,
              color: _error != null ? t.accent : t.textDim,
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            _RetryButton(theme: t, onTap: _load),
          ],
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CommentThread(
          comments: _comments,
          theme: t,
          onReply: widget.config.allowComments
              ? (c) => setState(() => _replyTo = c)
              : null,
          onPostPress: widget.onPostPress,
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(
            _error!,
            style: TextStyle(fontSize: kFontSmall, color: t.accent),
          ),
        ],
      ],
    );
  }

  Widget _composer(FbTheme t) {
    final canSend = _draft.text.trim().isNotEmpty && !_sending;
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: t.divider)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_replyTo != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Replying to ${_replyTo!.authorName}',
                        overflow: TextOverflow.ellipsis,
                        style:
                            TextStyle(fontSize: kFontSmall, color: t.textDim),
                      ),
                    ),
                    Semantics(
                      button: true,
                      label: 'Cancel reply',
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => setState(() => _replyTo = null),
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Text(
                            '×',
                            style: TextStyle(
                              fontSize: kFontBody,
                              color: t.textDim,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _draft,
                    minLines: 1,
                    maxLines: 4,
                    style: TextStyle(fontSize: kFontBody, color: t.text),
                    cursorColor: t.accent,
                    decoration: InputDecoration(
                      hintText: 'Add a comment…',
                      hintStyle:
                          TextStyle(color: t.textDim, fontSize: kFontBody),
                      filled: true,
                      fillColor: t.fieldBg,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 9,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(kRadius),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Semantics(
                  button: true,
                  label: 'Send comment',
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: canSend ? _send : null,
                    child: Opacity(
                      opacity: canSend ? 1 : 0.5,
                      child: Container(
                        width: 40,
                        height: 40,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: t.accent,
                          borderRadius: BorderRadius.circular(kRadius),
                        ),
                        child: _sending
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white),
                                ),
                              )
                            : const Text(
                                '↑',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RetryButton extends StatelessWidget {
  final FbTheme theme;
  final VoidCallback onTap;

  const _RetryButton({required this.theme, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(
            'Retry',
            style: TextStyle(
              fontSize: kFontSmall,
              fontWeight: FontWeight.w700,
              color: theme.accent,
            ),
          ),
        ),
      ),
    );
  }
}
