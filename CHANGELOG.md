## 1.7.0

- Add verified identity: `setIdentity` now also accepts an org-signed `userId`/`email`/`signature`/`timestamp` payload (the same HMAC scheme as portal auto-login). Once set, `vote`, `addComment`, `submit`, and `hasVoted` attach to that real, verified user instead of the install's anonymous id — consistent across every device, not just the one that called `setIdentity` — and any votes/comments already made anonymously on that device are folded onto the verified user the first time it resolves. Fully backward compatible; the plain `setIdentity(name:, email:)` call is unchanged.

## 1.6.1

- Fix: following a `#[…]` post jump-link kept the previous post's comments on screen — the detail screen is now keyed by post id so it reloads.

## 1.6.0

- Post and comment content now render light Markdown (**bold**, *italic*, `code`, links, headings, lists, quotes, fenced code) and FeedbackJar mention tokens — `#[Post title](postId)` and `@[Name](user:id)`. New exported `FbRichText` widget and `toPlainText()` helper; no new package dependency.
- Tapping a `#[…]` post reference in the board opens that post's detail screen. New `FeedbackJar.shared.getPost(postId)` (and `getPostCallback`) — same visibility rules as `listFeedback`.

## 1.5.0

- Prebuilt comment thread now shows a "Reply" action on root comments. Tapping it sets a "Replying to <name>" target above the composer (with a cancel control); sending posts the comment as a reply via `parentId`. Hidden when `allowComments` is off.
- Every request now carries an `X-FeedbackJar-SDK: flutter/<version>` header; submissions include `sdk` / `sdkVersion` in metadata.

## 1.4.0

- Add a prebuilt feedback board UI — `FeedbackJarBoard` widget and the `showFeedbackJar(context)` route helper. Drop it in and get a working votable board with detail, comments and submission screens.
- Built only on Flutter's own Material widgets — no new package dependency.
- `accentColor` recolours the vote state, primary button and links (defaults to FeedbackJar red). Follows the OS light/dark setting.
- Respects `getConfig()`: hides vote pills when `allowVotes` is off, hides the comment composer when `allowComments` is off, shows Name/Email fields on the new-feedback form only per `collectName` / `collectEmail` (prefilled from `getIdentity()`, persisted via `setIdentity`).
- The UI never throws — every SDK call is a `FeedbackResult`; failures show an inline error with the server message verbatim plus a retry where sensible.

## 1.3.0

- Add guest upvoting: `vote()`, `unvote()`, `getVoteState()` (and callback variants). Votes are attributed to a per-install anonymous id (random UUIDv4, persisted via `shared_preferences`, sent as the `X-FeedbackJar-Anon-Id` header) — never a device identifier.
- Add guest comments: `listComments()` and `addComment()` (and callback variants) for two-level public comment threads. `addComment()` reuses the remembered identity for name/email.
- `FeedbackPost` gains `hasVoted`; `listFeedback()` now populates it for this install.
- `WidgetConfig` gains `allowVotes` / `allowComments` — use them to show/hide your vote and comment UI.
- `setIdentity()` now also best-effort syncs the name/email to the server for this install's anonymous id. A failed sync never breaks local identity storage.
- New models: `VoteState`, `FeedbackComment`, `FeedbackCommentListResult`.
- API errors are now surfaced with the server's message verbatim.

## 1.2.0

- Add `properties` parameter to `submit()`/`submitCallback()` — custom key/value context merged into the auto-collected `app` metadata.

## 1.1.0

- Add `getConfig()` to fetch whether the org asks submitters for their name/email ("Ask for Name" / "Ask for Email" in the dashboard).
- Add `setIdentity()`/`getIdentity()`/`clearIdentity()` to remember a submitter's name/email (persisted via `shared_preferences`) and reuse them across `submit()` calls.
- `submit()` now automatically reuses a remembered identity and persists any name/email passed to it.

## 1.0.0

- Initial release.
- Submit anonymous feedback enriched with device metadata (OS, device model, screen, locale, app version).
- List public feedback with cursor-based pagination.
- Sealed `FeedbackResult<T>` type — `FeedbackSuccess` and `FeedbackFailure` — for safe error handling without exceptions.
- Both async/await and callback variants for all operations.
- Supports Android and iOS.
