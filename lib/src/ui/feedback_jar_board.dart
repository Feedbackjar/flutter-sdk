import 'package:flutter/material.dart';

import '../feedbackjar_sdk.dart';
import '../models.dart';
import 'feedback_detail.dart';
import 'new_feedback.dart';
import 'rich_text.dart';
import 'theme.dart';
import 'vote_pill.dart';

const int _pageSize = 20;

/// A complete, drop-in feedback board: list + upvote + detail + comments +
/// submission. Built only on Flutter's own Material widgets — no extra
/// package dependency.
///
/// ```dart
/// FeedbackJarBoard(accentColor: Color(0xFFE5484D))
/// ```
///
/// To push it as a full route, use [showFeedbackJar].
///
/// To drive an already-mounted board from the host (reset identity, jump to
/// a post), attach a [GlobalKey] and call the [FeedbackJarBoardState] methods:
/// ```dart
/// final boardKey = GlobalKey<FeedbackJarBoardState>();
/// FeedbackJarBoard(key: boardKey)
/// // later
/// boardKey.currentState?.resetIdentity();
/// boardKey.currentState?.openPost('post_123');
/// ```
class FeedbackJarBoard extends StatefulWidget {
  /// Accent colour for the vote state, primary button and links.
  /// Defaults to FeedbackJar red.
  final Color? accentColor;

  /// Restrict the feed to a single board.
  final String? boardId;

  /// When provided, a "Close" affordance is shown in the header.
  final VoidCallback? onClose;

  /// Called each time the board's own "New feedback" screen sends feedback,
  /// to get fresh custom key/value pairs (e.g. `{'flavor': 'foss'}`) merged
  /// into the auto-collected metadata. Forwarded verbatim to
  /// [FeedbackJar.submit]'s `properties` param.
  final Map<String, dynamic>? Function()? properties;

  /// Called each time a comment is sent from a post's detail screen, to get
  /// the name/email to attach to it. Return `null` fields (or omit this
  /// param entirely) to fall back to the remembered identity.
  final ({String? name, String? email}) Function()? commentIdentity;

  const FeedbackJarBoard({
    super.key,
    this.accentColor,
    this.boardId,
    this.onClose,
    this.properties,
    this.commentIdentity,
  });

  @override
  State<FeedbackJarBoard> createState() => FeedbackJarBoardState();
}

enum _ScreenName { board, detail, newFeedback }

/// State for [FeedbackJarBoard], public so a host can drive it imperatively
/// via a [GlobalKey] — see [FeedbackJarBoard]'s class doc.
class FeedbackJarBoardState extends State<FeedbackJarBoard> {
  final _scroll = ScrollController();

  _ScreenName _screen = _ScreenName.board;
  FeedbackPost? _selected;

  WidgetConfig _config = const WidgetConfig(
    collectName: false,
    collectEmail: false,
    allowVotes: false,
    allowComments: false,
  );

  List<FeedbackPost> _posts = [];
  String? _cursor;
  bool _loading = true;
  bool _refreshing = false;
  bool _loadingMore = false;
  String? _error;

  // Bumped on [resetIdentity] to force a fresh NewFeedbackScreen (fresh
  // prefilled name/email) after the remembered identity is cleared.
  int _newFeedbackToken = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    FeedbackJar.shared.getConfig().then((result) {
      if (!mounted) return;
      if (result case FeedbackSuccess(:final value)) {
        setState(() => _config = value);
      }
    });
    _load(reset: true).then((_) {
      if (mounted) setState(() => _loading = false);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final nearBottom =
        _scroll.position.pixels >= _scroll.position.maxScrollExtent - 300;
    if (nearBottom) _loadMore();
  }

  Future<void> _load({required bool reset}) async {
    final result = await FeedbackJar.shared.listFeedback(
      limit: _pageSize,
      boardId: widget.boardId,
      cursor: reset ? null : _cursor,
    );
    if (!mounted) return;
    setState(() {
      switch (result) {
        case FeedbackSuccess(:final value):
          _error = null;
          _posts = reset ? value.posts : [..._posts, ...value.posts];
          _cursor = value.nextCursor;
        case FeedbackFailure(:final error):
          _error = errorText(error);
      }
    });
  }

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    await _load(reset: true);
    if (mounted) setState(() => _refreshing = false);
  }

  Future<void> _loadMore() async {
    if (_cursor == null || _loadingMore || _refreshing) return;
    setState(() => _loadingMore = true);
    await _load(reset: false);
    if (mounted) setState(() => _loadingMore = false);
  }

  // Jump to a post referenced by a `#[title](postId)` mention — use the loaded
  // copy if we have it, otherwise fetch it.
  Future<void> _openPost(String postId) async {
    FeedbackPost? known;
    for (final p in _posts) {
      if (p.id == postId) {
        known = p;
        break;
      }
    }
    if (known != null) {
      setState(() {
        _selected = known;
        _screen = _ScreenName.detail;
      });
      return;
    }
    final result = await FeedbackJar.shared.getPost(postId);
    if (!mounted) return;
    if (result case FeedbackSuccess(:final value)) {
      setState(() {
        _selected = value;
        _screen = _ScreenName.detail;
      });
    }
  }

  /// Jump straight to [postId]'s detail screen (e.g. from a push
  /// notification tap) — reuses the same lookup/fetch as an in-app mention.
  Future<void> openPost(String postId) => _openPost(postId);

  /// Forget the remembered submitter identity (e.g. on logout) and refresh
  /// this board as a clean anonymous guest: reloads the feed and clears any
  /// prefilled name/email in the New Feedback screen.
  Future<void> resetIdentity() async {
    await FeedbackJar.shared.clearIdentity();
    if (!mounted) return;
    setState(() {
      _newFeedbackToken++;
      _screen = _ScreenName.board;
      _selected = null;
    });
    await _refresh();
  }

  void _patchPost(String id, int upvotes, bool hasVoted) {
    setState(() {
      _posts = _posts
          .map((p) => p.id == id ? _copyVote(p, upvotes, hasVoted) : p)
          .toList();
    });
  }

  FeedbackPost _copyVote(FeedbackPost p, int upvotes, bool hasVoted) {
    return FeedbackPost(
      id: p.id,
      title: p.title,
      content: p.content,
      type: p.type,
      status: p.status,
      slug: p.slug,
      boardId: p.boardId,
      voteCount: p.voteCount,
      commentCount: p.commentCount,
      upvotes: upvotes,
      hasVoted: hasVoted,
      authorName: p.authorName,
      createdAt: p.createdAt,
      updatedAt: p.updatedAt,
    );
  }

  @override
  Widget build(BuildContext context) {
    final brightness = MediaQuery.platformBrightnessOf(context);
    final theme = FbTheme.resolve(
      brightness,
      widget.accentColor ?? kDefaultAccent,
    );

    return Material(
      color: theme.bg,
      child: _buildScreen(theme),
    );
  }

  Widget _buildScreen(FbTheme theme) {
    switch (_screen) {
      case _ScreenName.newFeedback:
        return NewFeedbackScreen(
          // Key bumped by resetIdentity() so a fresh guest gets a clean
          // screen (no stale prefilled name/email).
          key: ValueKey(_newFeedbackToken),
          config: _config,
          theme: theme,
          properties: widget.properties,
          onCancel: () => setState(() => _screen = _ScreenName.board),
          onDone: () {
            setState(() => _screen = _ScreenName.board);
            _refresh();
          },
        );
      case _ScreenName.detail:
        final live = _posts.firstWhere(
          (p) => p.id == _selected!.id,
          orElse: () => _selected!,
        );
        return FeedbackDetailScreen(
          // Key by post id so a jump-link to another post gets a fresh State
          // (re-runs initState -> reloads that post's comments).
          key: ValueKey(live.id),
          post: live,
          config: _config,
          theme: theme,
          commentIdentity: widget.commentIdentity,
          onBack: () => setState(() => _screen = _ScreenName.board),
          onVoteChange: (u, v) => _patchPost(live.id, u, v),
          onPostPress: _openPost,
        );
      case _ScreenName.board:
        return _board(theme);
    }
  }

  Widget _board(FbTheme t) {
    if (_loading) {
      return Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(t.accent),
          ),
        ),
      );
    }

    return SafeArea(
      child: RefreshIndicator(
        color: t.accent,
        onRefresh: _refresh,
        child: ListView.builder(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          itemCount: _posts.length + 2,
          itemBuilder: (context, index) {
            if (index == 0) return _header(t);
            if (index == _posts.length + 1) return _footer(t);
            return _row(t, _posts[index - 1]);
          },
        ),
      ),
    );
  }

  Widget _header(FbTheme t) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Feedback',
            style: TextStyle(
              fontSize: kFontBody,
              fontWeight: FontWeight.w700,
              color: t.text,
            ),
          ),
          Row(
            children: [
              _HeaderButton(
                label: 'New',
                color: t.accent,
                onTap: () => setState(() {
                  _screen = _ScreenName.newFeedback;
                }),
              ),
              if (widget.onClose != null) ...[
                const SizedBox(width: 16),
                _HeaderButton(
                  label: 'Close',
                  color: t.textDim,
                  onTap: widget.onClose!,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _footer(FbTheme t) {
    if (_loadingMore) {
      return Padding(
        padding: const EdgeInsets.all(16),
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
    if (_posts.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 40),
        child: Column(
          children: [
            Text(
              _error ?? 'No feedback yet.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: kFontSmall,
                color: _error != null ? t.accent : t.textDim,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              _HeaderButton(
                label: 'Retry',
                color: t.accent,
                onTap: _refresh,
              ),
            ],
          ],
        ),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Text(
          _error!,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: kFontSmall, color: t.accent),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _row(FbTheme t, FeedbackPost post) {
    return InkWell(
      onTap: () => setState(() {
        _selected = post;
        _screen = _ScreenName.detail;
      }),
      child: Container(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: t.divider)),
        ),
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    post.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: kFontBody,
                      fontWeight: FontWeight.w700,
                      color: t.text,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    toPlainText(post.content),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: kFontBody,
                      height: 1.35,
                      color: t.textDim,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${humanStatus(post.status)} · ${post.commentCount} comments',
                    style: TextStyle(fontSize: kFontSmall, color: t.textDim),
                  ),
                ],
              ),
            ),
            if (_config.allowVotes) ...[
              const SizedBox(width: 12),
              VotePill(
                postId: post.id,
                upvotes: post.upvotes,
                hasVoted: post.hasVoted,
                theme: t,
                onChange: (u, v) => _patchPost(post.id, u, v),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _HeaderButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _HeaderButton({
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
          child: Text(
            label,
            style: TextStyle(
              fontSize: kFontBody,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ),
      ),
    );
  }
}

/// Push [FeedbackJarBoard] as a full-screen route with a close affordance.
///
/// ```dart
/// showFeedbackJar(context, accentColor: Color(0xFFE5484D));
/// ```
Future<void> showFeedbackJar(
  BuildContext context, {
  Color? accentColor,
  String? boardId,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (routeContext) => Scaffold(
        body: FeedbackJarBoard(
          accentColor: accentColor,
          boardId: boardId,
          onClose: () => Navigator.of(routeContext).maybePop(),
        ),
      ),
    ),
  );
}
