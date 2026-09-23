/// Result of a FeedbackJar operation — either a success value or an error.
///
/// Use Dart 3 pattern matching to handle both cases:
/// ```dart
/// switch (result) {
///   case FeedbackSuccess(:final value):
///     print('OK: $value');
///   case FeedbackFailure(:final error):
///     print('Error: $error');
/// }
/// ```
sealed class FeedbackResult<T> {
  const FeedbackResult();
}

final class FeedbackSuccess<T> extends FeedbackResult<T> {
  final T value;
  const FeedbackSuccess(this.value);
}

final class FeedbackFailure<T> extends FeedbackResult<T> {
  final Object error;
  const FeedbackFailure(this.error);
}

/// Returned when feedback is submitted successfully.
class FeedbackResponse {
  final String postId;

  /// AI-generated title for the submission.
  final String title;

  /// e.g. `FEEDBACK`, `BUG`, `FEATURE_REQUEST`
  final String type;

  final String boardId;

  const FeedbackResponse({
    required this.postId,
    required this.title,
    required this.type,
    required this.boardId,
  });
}

/// A single public feedback post.
class FeedbackPost {
  final String id;
  final String title;
  final String content;

  /// e.g. `FEEDBACK`, `BUG`, `FEATURE_REQUEST`
  final String type;

  /// e.g. `OPEN`, `IN_PROGRESS`, `COMPLETED`
  final String status;

  final String slug;
  final String boardId;
  final int voteCount;
  final int commentCount;
  final int upvotes;

  /// Whether this install's anonymous id has upvoted this post. Only ever `true`
  /// when the request carried the anon id (it always does via [FeedbackJar]).
  final bool hasVoted;

  final String? authorName;

  /// ISO-8601 timestamp.
  final String createdAt;

  /// ISO-8601 timestamp.
  final String updatedAt;

  const FeedbackPost({
    required this.id,
    required this.title,
    required this.content,
    required this.type,
    required this.status,
    required this.slug,
    required this.boardId,
    required this.voteCount,
    required this.commentCount,
    required this.upvotes,
    this.hasVoted = false,
    this.authorName,
    required this.createdAt,
    required this.updatedAt,
  });
}

/// A page of public feedback posts with a cursor for the next page.
class FeedbackListResult {
  final List<FeedbackPost> posts;

  /// Pass this to the next [FeedbackJar.listFeedback] call to load the next
  /// page. `null` means there are no more pages.
  final String? nextCursor;

  const FeedbackListResult({required this.posts, this.nextCursor});
}

/// Widget configuration for this organization, as set in the FeedbackJar dashboard.
class WidgetConfig {
  /// Whether the org asks submitters for their name ("Ask for Name").
  final bool collectName;

  /// Whether the org asks submitters for their email ("Ask for Email").
  final bool collectEmail;

  /// Whether guest upvoting is enabled for this project. Use it to show/hide
  /// your own vote UI.
  final bool allowVotes;

  /// Whether guest commenting is enabled for this project. Use it to show/hide
  /// your own comment UI.
  final bool allowComments;

  const WidgetConfig({
    required this.collectName,
    required this.collectEmail,
    this.allowVotes = false,
    this.allowComments = false,
  });
}

/// Submitter identity remembered across [FeedbackJar] calls.
///
/// [userId]/[signature]/[timestamp] are set only via a **verified**
/// `FeedbackJar.setIdentity(userId: ..., signature: ..., timestamp: ...)` call
/// — when present (and not expired), vote, comment, and submit all attach to
/// this real, server-verified user instead of the install's anonymous id.
class FeedbackIdentity {
  final String? name;
  final String? email;
  final String? userId;
  final String? signature;

  /// Milliseconds since epoch — the exact value your backend signed.
  final int? timestamp;
  final String? firstName;
  final String? lastName;
  final String? avatar;

  const FeedbackIdentity({
    this.name,
    this.email,
    this.userId,
    this.signature,
    this.timestamp,
    this.firstName,
    this.lastName,
    this.avatar,
  });
}

/// Upvote state for a single post.
class VoteState {
  /// Current upvote count.
  final int upvotes;

  /// Whether this install's anonymous id has upvoted.
  final bool hasVoted;

  const VoteState({required this.upvotes, required this.hasVoted});
}

/// A single public comment on a feedback post.
///
/// Threads are two levels deep: root comments carry their [replies]; a reply's
/// own [replies] is always empty and its [parentId] points at the root.
class FeedbackComment {
  final String id;
  final String content;
  final String authorName;

  /// Org role of the author when they're a team member (`owner`, `admin`,
  /// `member`), else `null` for a guest.
  final String? authorRole;

  /// Whether the comment was posted by an automated bot.
  final bool isBot;

  /// The root comment's id when this is a reply, else `null`.
  final String? parentId;

  /// ISO-8601 timestamp.
  final String createdAt;

  /// Nested replies (one level only; empty on a reply).
  final List<FeedbackComment> replies;

  const FeedbackComment({
    required this.id,
    required this.content,
    required this.authorName,
    this.authorRole,
    required this.isBot,
    this.parentId,
    required this.createdAt,
    this.replies = const [],
  });
}

/// A page of public comments with a cursor for the next page.
class FeedbackCommentListResult {
  final List<FeedbackComment> comments;

  /// Pass this to the next [FeedbackJar.listComments] call to load the next
  /// page. `null` means there are no more pages.
  final String? nextCursor;

  const FeedbackCommentListResult({required this.comments, this.nextCursor});
}
