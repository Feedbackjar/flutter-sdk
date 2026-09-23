# FeedbackJar Flutter SDK

[![pub package](https://img.shields.io/pub/v/feedbackjar.svg)](https://pub.dev/packages/feedbackjar)

A lightweight Flutter SDK for collecting user feedback. You build your own form — the SDK handles submission (enriched with device metadata) and fetching the public feedback list.

- **Min SDK:** Dart 3.0 / Flutter 3.10
- **Platforms:** Android, iOS
- **Package:** pub.dev
- **License:** MIT

## Installation

```sh
flutter pub add feedbackjar
```

## Setup

Initialize once before use — call `configure` in `main()` before `runApp`, or in your root widget's constructor. You need your **widget ID** from the FeedbackJar dashboard.

```dart
import 'package:feedbackjar/feedbackjar.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  FeedbackJar.configure('your-widget-id');
  runApp(const MyApp());
}
```

## Prebuilt UI

Don't want to build a form? Drop in `FeedbackJarBoard` and you get a working
feedback board — list, upvoting, a detail screen with comments, and a
new-feedback form — built only on Flutter's own Material widgets (no extra
package).

```dart
import 'package:feedbackjar/feedbackjar.dart';

// Anywhere in your widget tree:
const FeedbackJarBoard()
```

Or push it as a full screen from a button:

```dart
showFeedbackJar(context);
```

Recolour the vote state, primary button and links with `accentColor` (defaults
to FeedbackJar red). Both entry points also take an optional `boardId` filter:

```dart
FeedbackJarBoard(accentColor: const Color(0xFFE5484D), boardId: 'board-id')

showFeedbackJar(context, accentColor: const Color(0xFFE5484D));
```

The board follows the OS light/dark setting and respects your dashboard config:
vote pills hide when guest voting is off, the comment composer hides when guest
commenting is off, and the Name/Email fields appear on the new-feedback form only
when "Ask for Name" / "Ask for Email" are enabled (prefilled from a remembered
identity). Every call is handled as a `FeedbackResult` — the UI never throws and
shows the server's error message inline with a retry.

Prefer to build your own UI? The rest of this README covers the data API it's
built on.

## Submitting feedback

Submissions can be anonymous, or include a submitter name/email if you collect them in your own form. Each submission automatically carries device metadata (OS version, device model, screen size, app version, locale).

### async/await (recommended)

```dart
final result = await FeedbackJar.shared.submit(userText);

switch (result) {
  case FeedbackSuccess(:final value):
    print('Submitted: ${value.postId} (${value.type})');
    // show a success state in your UI
  case FeedbackFailure(:final error):
    print('Failed: $error');
    // show an error state
}
```

### Callback (no async context needed)

```dart
FeedbackJar.shared.submitCallback(userText, (result) {
  switch (result) {
    case FeedbackSuccess(:final value):
      // show success state
    case FeedbackFailure(:final error):
      // show error state
  }
});
```

> **Note:** the server applies rate limiting (5 submissions per 15 minutes per IP). Handle the failure case in your UI.

## Custom properties

Attach your own key/value context to a submission — merged into the auto-collected `app` metadata (alongside `packageName`, `versionName`, `versionCode`). Values should be `String`, `num`, or `bool`; nested maps/lists aren't supported.

```dart
final result = await FeedbackJar.shared.submit(
  userText,
  properties: {'flavor': 'foss', 'plan': 'pro'},
);
```

<a id="checking-config"></a>

## Checking config

`getConfig()` returns the org's dashboard settings. "Ask for Name" / "Ask for Email" control whether submitters should be prompted; `allowVotes` / `allowComments` control whether guest voting and commenting are enabled. The SDK doesn't render any UI itself, so read this before building your own form or vote/comment UI:

```dart
final result = await FeedbackJar.shared.getConfig();
if (result case FeedbackSuccess(:final value)) {
  showNameField = value.collectName;
  showEmailField = value.collectEmail;
  showVoteButton = value.allowVotes;
  showCommentBox = value.allowComments;
}
```

## Remembering submitter identity

Name/email passed to `submit` are automatically remembered and reused on later calls, so you only need to ask once. Manage this directly with `setIdentity` / `getIdentity` / `clearIdentity`:

```dart
await FeedbackJar.shared.setIdentity(name: 'Ada Lovelace', email: 'ada@example.com');

final identity = await FeedbackJar.shared.getIdentity();
print(identity.name);

// e.g. on logout
await FeedbackJar.shared.clearIdentity();
```

This is unverified — anyone can type any email. It's stored per-install, so votes/comments still key on this device's anonymous id, not this identity.

### Verified identity (signed-in users)

If your app has its own signed-in users and you want their votes/comments attributed to a real, verifiable account — consistent across every device they use, not just the one they voted from — pass a signed identity instead, via the same `setIdentity`. Your **backend** computes the signature (never the app):

```dart
// Your backend, once the user is authenticated:
//   timestamp = DateTime.now().millisecondsSinceEpoch
//   signature = HMAC-SHA256(orgSecretKey, "$userId:$email:$timestamp")
// (org secret key is in the FeedbackJar dashboard — the same one used for portal auto-login)

await FeedbackJar.shared.setIdentity(
  userId: 'user_123',
  email: 'ada@example.com',
  signature: signatureFromYourBackend,
  timestamp: timestampFromYourBackend,
);
```

Once set, `vote`, `addComment`, `submit`, and `hasVoted` all attach to this real user — on every device, immediately, not just the one that called `setIdentity`. The first vote/comment after setting it also folds in anything this device already did anonymously, so nothing doubles up. `timestamp` must be the exact value your backend signed (never a fresh client-side timestamp), and expires after 7 days — call `setIdentity` again on each sign-in to refresh it. `clearIdentity()` removes this too (e.g. on logout).

## Listing feedback

Fetch the public feedback feed for your organization. Supports pagination via a cursor.

### async/await

```dart
final result = await FeedbackJar.shared.listFeedback(limit: 20);

if (result case FeedbackSuccess(:final value)) {
  for (final post in value.posts) {
    print('${post.title} — ${post.upvotes} upvotes, ${post.status}');
  }
  // value.nextCursor is non-null when more pages exist
}
```

### Pagination

```dart
String? cursor;

Future<void> loadNextPage() async {
  final result = await FeedbackJar.shared.listFeedback(
    limit: 20,
    cursor: cursor,
  );
  if (result case FeedbackSuccess(:final value)) {
    renderPosts(value.posts);
    cursor = value.nextCursor; // pass this back in for the next page
  }
}
```

### Callback

```dart
FeedbackJar.shared.listFeedbackCallback(
  limit: 20,
  callback: (result) {
    if (result case FeedbackSuccess(:final value)) {
      // render value.posts
    }
  },
);
```

## Voting

Guests can upvote a post without signing in. Each install generates a random anonymous id once (a UUIDv4, persisted via `shared_preferences` — not a device identifier) and sends it with every vote, so the same install's votes are counted once and `hasVoted` is populated on `listFeedback` results.

Voting must be enabled for the project — check `WidgetConfig.allowVotes` (see [Checking config](#checking-config)) before showing your vote UI.

```dart
// Toggle a vote
final state = await FeedbackJar.shared.getVoteState(post.id);
if (state case FeedbackSuccess(:final value)) {
  final result = value.hasVoted
      ? await FeedbackJar.shared.unvote(post.id)
      : await FeedbackJar.shared.vote(post.id);

  if (result case FeedbackSuccess(:final value)) {
    print('${value.upvotes} upvotes, hasVoted=${value.hasVoted}');
  }
}
```

`vote` and `unvote` are idempotent — calling them twice is a no-op. Both return the new `VoteState`. If guest voting is disabled the result is a `FeedbackFailure` carrying the server's message (e.g. `Guest voting is disabled for this project.`).

## Comments

Fetch and add public comments on a post. Comment threads are two levels deep — each root comment carries its `replies`, and a reply's `parentId` points at the root.

```dart
final result = await FeedbackJar.shared.listComments(post.id, limit: 20);

if (result case FeedbackSuccess(:final value)) {
  for (final comment in value.comments) {
    print('${comment.authorName}: ${comment.content}');
    for (final reply in comment.replies) {
      print('  ↳ ${reply.authorName}: ${reply.content}');
    }
  }
  // value.nextCursor is non-null when more pages exist
}
```

Adding a comment or reply uses this install's anonymous id. `name`/`email` fall back to the remembered identity (see [Remembering submitter identity](#remembering-submitter-identity)); `email` is used only for reply notifications and is never linked to a real account. Commenting must be enabled — check `WidgetConfig.allowComments`.

```dart
// A top-level comment
final result = await FeedbackJar.shared.addComment(post.id, 'Please add this!');
if (result case FeedbackSuccess(:final value)) {
  print('New comment id: $value');
}

// A reply to a root comment
await FeedbackJar.shared.addComment(
  post.id,
  'Agreed — this would help a lot.',
  parentId: rootComment.id,
);
```

`parentId` must be a root comment; you cannot reply to a reply.

## Rich text

Post and comment content can contain light Markdown (**bold**, *italic*, `code`,
`[links](url)`, headings, lists, quotes, fenced code) and FeedbackJar mention
tokens — `#[Post title](postId)` for a post reference and `@[Name](user:id)` for
a person. `FeedbackJarBoard` renders all of this; list previews are flattened to
plain text, and tapping a `#[…]` reference opens that post's detail screen
(fetched via `getPost` when it isn't already loaded).

Building your own UI? The renderer and the flattener are exported — no extra
package:

```dart
import 'package:feedbackjar/feedbackjar.dart';

FbRichText(
  content: post.content,
  theme: FbTheme.resolve(Theme.of(context).brightness, const Color(0xFFE5484D)),
  onPostPress: (postId) async {
    final res = await FeedbackJar.shared.getPost(postId);
    if (res case FeedbackSuccess(:final value)) openDetail(value);
  },
);

final preview = toPlainText(post.content); // for a truncated row
```

## API reference

### `FeedbackJar`

| Method | Description |
| --- | --- |
| `configure(widgetId)` | Configure the SDK. Call once before anything else. |
| `shared.submit(content, {email?, name?, properties?})` | Submit feedback, optionally with custom properties merged into `app` metadata. Returns `Future<FeedbackResult<FeedbackResponse>>`. |
| `shared.submitCallback(content, callback, {email?, name?, properties?})` | Callback variant. |
| `shared.listFeedback({boardId?, limit = 20, cursor?})` | List public feedback. `limit` is clamped to 1–50. |
| `shared.listFeedbackCallback({boardId?, limit, cursor?, callback})` | Callback variant. |
| `shared.getPost(postId)` | Fetch one public post — used to resolve `#[…]` mention jump-links. Returns `Future<FeedbackResult<FeedbackPost>>`. |
| `shared.getPostCallback(postId, callback)` | Callback variant. |
| `shared.getConfig()` | Fetch the org config (name/email prompts, `allowVotes`, `allowComments`). Returns `Future<FeedbackResult<WidgetConfig>>`. |
| `shared.getConfigCallback(callback)` | Callback variant. |
| `shared.vote(postId)` / `shared.unvote(postId)` | Add/remove this install's guest upvote. Idempotent. Returns `Future<FeedbackResult<VoteState>>`. |
| `shared.getVoteState(postId)` | Current upvote count and whether this install voted. |
| `shared.voteCallback` / `unvoteCallback` / `getVoteStateCallback` | Callback variants. |
| `shared.listComments(postId, {limit = 20, cursor?})` | List public comments (two-level threads). `limit` clamped to 1–50. |
| `shared.addComment(postId, content, {parentId?, name?, email?})` | Add a guest comment or reply. Returns `Future<FeedbackResult<String>>` (the new comment id). |
| `shared.listCommentsCallback` / `addCommentCallback` | Callback variants. |
| `shared.setIdentity({name?, email?})` | Remember a submitter's name/email for future `submit` calls; also best-effort synced to the server. |
| `shared.setIdentity({userId, email, signature, timestamp, name?, firstName?, lastName?, avatar?})` | Set a **verified**, org-signed identity — see [Verified identity](#verified-identity-signed-in-users). |
| `shared.getIdentity()` | The currently remembered identity, if any. Returns `Future<FeedbackIdentity>`. |
| `shared.clearIdentity()` | Forget the remembered identity. |

### `FeedbackResult<T>`

A sealed class with two subtypes. Use Dart 3 pattern matching:

```dart
switch (result) {
  case FeedbackSuccess(:final value):
    // T value
  case FeedbackFailure(:final error):
    // Object error
}
```

### `FeedbackResponse`

```dart
class FeedbackResponse {
  final String postId;
  final String title;    // AI-generated title for the submission
  final String type;     // e.g. FEEDBACK, BUG, FEATURE_REQUEST
  final String boardId;
}
```

### `FeedbackPost`

```dart
class FeedbackPost {
  final String id;
  final String title;
  final String content;
  final String type;
  final String status;       // OPEN, IN_PROGRESS, COMPLETED, ...
  final String slug;
  final String boardId;
  final int voteCount;
  final int commentCount;
  final int upvotes;
  final bool hasVoted;       // whether this install's anon id upvoted
  final String? authorName;
  final String createdAt;    // ISO-8601
  final String updatedAt;    // ISO-8601
}
```

### `FeedbackListResult`

```dart
class FeedbackListResult {
  final List<FeedbackPost> posts;
  final String? nextCursor;  // null when there are no more pages
}
```

### `WidgetConfig`

```dart
class WidgetConfig {
  final bool collectName;    // org asks for the submitter's name
  final bool collectEmail;   // org asks for the submitter's email
  final bool allowVotes;     // guest upvoting enabled for the project
  final bool allowComments;  // guest commenting enabled for the project
}
```

### `FeedbackIdentity`

```dart
class FeedbackIdentity {
  final String? name;
  final String? email;
  final String? userId;      // set only via a verified setIdentity() call
  final String? signature;
  final int? timestamp;      // milliseconds since epoch — the value your backend signed
  final String? firstName;
  final String? lastName;
  final String? avatar;
}
```

### `VoteState`

```dart
class VoteState {
  final int upvotes;    // current upvote count
  final bool hasVoted;  // whether this install's anon id upvoted
}
```

### `FeedbackComment`

```dart
class FeedbackComment {
  final String id;
  final String content;
  final String authorName;
  final String? authorRole;  // owner / admin / member, or null for a guest
  final bool isBot;
  final String? parentId;    // root comment id when this is a reply
  final String createdAt;    // ISO-8601
  final List<FeedbackComment> replies;  // one level; empty on a reply
}
```

### `FeedbackCommentListResult`

```dart
class FeedbackCommentListResult {
  final List<FeedbackComment> comments;
  final String? nextCursor;  // null when there are no more pages
}
```

## Notes

- Feedback can be submitted anonymously, or with a name/email — the SDK never requires either.
- Name/email are persisted on-device via `shared_preferences` so they survive app restarts.
- Guest votes/comments are attributed to a per-install anonymous id (a random UUIDv4, also stored in `shared_preferences`). It is not a device identifier and resets on reinstall or clear-data.
- The server rate-limits vote/unvote (60/min) and comment creation (10/min) per IP. Handle the failure case in your UI.
- Private boards and non-public posts are never returned by `listFeedback` or `getPost`.
- Every request carries an `X-FeedbackJar-SDK: flutter/<version>` header; submissions also include `sdk` / `sdkVersion` in metadata.
- All methods return a `FeedbackResult`; nothing throws on network or HTTP errors.
- Requires `WidgetsFlutterBinding.ensureInitialized()` before `configure` if called before `runApp`.
