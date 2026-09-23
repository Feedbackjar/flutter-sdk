import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'internal/anon_id.dart';
import 'internal/api_client.dart';
import 'internal/metadata_collector.dart';
import 'models.dart';

const _nameKey = 'com.feedbackjar.sdk.identity.name';
const _emailKey = 'com.feedbackjar.sdk.identity.email';
const _userIdKey = 'com.feedbackjar.sdk.identity.userId';
const _signatureKey = 'com.feedbackjar.sdk.identity.signature';
const _timestampKey = 'com.feedbackjar.sdk.identity.timestamp';
const _firstNameKey = 'com.feedbackjar.sdk.identity.firstName';
const _lastNameKey = 'com.feedbackjar.sdk.identity.lastName';
const _avatarKey = 'com.feedbackjar.sdk.identity.avatar';

/// 7 days — must match `WIDGET_IDENTITY_MAX_AGE_MS` on the server.
const _identityMaxAgeMs = 7 * 24 * 60 * 60 * 1000;

/// FeedbackJar Flutter SDK.
///
/// Configure once before use — typically in `main()` or your root widget:
/// ```dart
/// void main() {
///   WidgetsFlutterBinding.ensureInitialized();
///   FeedbackJar.configure('your-widget-id');
///   runApp(const MyApp());
/// }
/// ```
///
/// async/await submission:
/// ```dart
/// final result = await FeedbackJar.shared.submit('Love the dark mode!');
/// switch (result) {
///   case FeedbackSuccess(:final value):
///     print('Posted: ${value.postId} (${value.type})');
///   case FeedbackFailure(:final error):
///     print('Failed: $error');
/// }
/// ```
///
/// Callback submission:
/// ```dart
/// FeedbackJar.shared.submitCallback(content, (result) {
///   switch (result) {
///     case FeedbackSuccess(:final value): // show success
///     case FeedbackFailure(:final error): // show error
///   }
/// });
/// ```
class FeedbackJar {
  static final FeedbackJar shared = FeedbackJar._();

  String? _widgetId;
  ApiClient? _client;

  FeedbackJar._();

  /// Configure the SDK. Call once before any other method.
  static Future<void> configure(String widgetId) async {
    final packageInfo = await PackageInfo.fromPlatform();
    shared._widgetId = widgetId;
    shared._client = ApiClient(appId: packageInfo.packageName);
  }

  /// Remember a submitter's identity — plain [name]/[email] (unverified), or
  /// an org-signed [userId]/[email]/[signature]/[timestamp] payload (verified).
  /// Pass `null` to leave a field unchanged; use [clearIdentity] to remove
  /// everything.
  ///
  /// **Unverified** (just [name]/[email]): anyone can type any email. It's
  /// synced to the server against this install's anonymous id (best-effort),
  /// so guest votes/comments show the right name and can be reconciled if the
  /// user later signs into the web portal with that email.
  ///
  /// **Verified**: pass [userId], [signature], and [timestamp] together — the
  /// same org-signed payload your backend computes for portal auto-login
  /// (`HMAC-SHA256(orgSecretKey, "$userId:$email:$timestamp")`; the org secret
  /// key is in the FeedbackJar dashboard). Once set, [vote], [addComment],
  /// [submit], and `hasVoted` all attach to this real user instead of the
  /// install's anonymous id — on every device, immediately. The first
  /// vote/comment after setting it also folds in anything this device already
  /// did anonymously, so nothing doubles up. [timestamp] must be the exact
  /// millisecond value your backend signed (never a fresh client-side
  /// timestamp), and expires after 7 days — call this again (e.g. on each
  /// sign-in) to refresh it.
  Future<void> setIdentity({
    String? name,
    String? email,
    String? userId,
    String? signature,
    int? timestamp,
    String? firstName,
    String? lastName,
    String? avatar,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (name != null) await prefs.setString(_nameKey, name);
    if (email != null) await prefs.setString(_emailKey, email);
    if (userId != null) await prefs.setString(_userIdKey, userId);
    if (signature != null) await prefs.setString(_signatureKey, signature);
    if (timestamp != null) await prefs.setInt(_timestampKey, timestamp);
    if (firstName != null) await prefs.setString(_firstNameKey, firstName);
    if (lastName != null) await prefs.setString(_lastNameKey, lastName);
    if (avatar != null) await prefs.setString(_avatarKey, avatar);

    final id = _widgetId;
    final client = _client;
    // Only the unverified path syncs via identify() — a verified identity
    // attaches via the signed header/body on every subsequent call instead.
    if (id != null &&
        client != null &&
        userId == null &&
        (name != null || email != null)) {
      try {
        await client.identify(id, await AnonId.get(), name: name, email: email);
      } catch (_) {
        // Best-effort — a failed server sync must not break local identity.
      }
    }
  }

  /// The currently remembered submitter identity, if any.
  Future<FeedbackIdentity> getIdentity() async {
    final prefs = await SharedPreferences.getInstance();
    final timestamp = prefs.getInt(_timestampKey);
    return FeedbackIdentity(
      name: prefs.getString(_nameKey),
      email: prefs.getString(_emailKey),
      userId: prefs.getString(_userIdKey),
      signature: prefs.getString(_signatureKey),
      timestamp: timestamp,
      firstName: prefs.getString(_firstNameKey),
      lastName: prefs.getString(_lastNameKey),
      avatar: prefs.getString(_avatarKey),
    );
  }

  /// Forget the remembered submitter identity (e.g. on user logout).
  Future<void> clearIdentity() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_nameKey);
    await prefs.remove(_emailKey);
    await prefs.remove(_userIdKey);
    await prefs.remove(_signatureKey);
    await prefs.remove(_timestampKey);
    await prefs.remove(_firstNameKey);
    await prefs.remove(_lastNameKey);
    await prefs.remove(_avatarKey);
  }

  /// The stored identity as a wire-ready payload, or null when it isn't
  /// verified (no signature) or has aged past [_identityMaxAgeMs] — callers
  /// then fall back to the anonymous id, same as if [setIdentity] was never
  /// called with a signature.
  Future<Map<String, dynamic>?> _verifiedIdentity() async {
    final identity = await getIdentity();
    final userId = identity.userId;
    final email = identity.email;
    final signature = identity.signature;
    final timestamp = identity.timestamp;
    if (userId == null ||
        userId.isEmpty ||
        email == null ||
        email.isEmpty ||
        signature == null ||
        signature.isEmpty ||
        timestamp == null) {
      return null;
    }

    final ageMs = DateTime.now().millisecondsSinceEpoch - timestamp;
    if (ageMs < 0 || ageMs > _identityMaxAgeMs) return null;

    return {
      'userId': userId,
      'email': email,
      'timestamp': timestamp,
      'signature': signature,
      if (identity.firstName != null) 'firstName': identity.firstName,
      if (identity.lastName != null) 'lastName': identity.lastName,
      if (identity.avatar != null) 'avatar': identity.avatar,
    };
  }

  /// Submit feedback. Device metadata is collected automatically.
  ///
  /// [email] and [name] are optional and intended for headless/anonymous
  /// submissions where the user identity is not already known. Once given,
  /// they're remembered (see [setIdentity]) and reused on later calls.
  ///
  /// [properties] are your own custom key/value pairs (e.g. `{'flavor': 'foss'}`),
  /// merged into the auto-collected `app` metadata. Values should be String,
  /// num, or bool — nested maps/lists aren't supported.
  Future<FeedbackResult<FeedbackResponse>> submit(
    String content, {
    String? email,
    String? name,
    Map<String, dynamic>? properties,
  }) async {
    final id = _widgetId;
    final client = _client;
    if (id == null || client == null) {
      return FeedbackFailure(FeedbackJarError.notInitialized);
    }
    if (email != null || name != null) {
      await setIdentity(name: name, email: email);
    }
    final identity = await getIdentity();
    final metadata = await MetadataCollector.collect();
    if (properties != null && properties.isNotEmpty) {
      (metadata['app'] as Map<String, dynamic>).addAll(properties);
    }
    return client.submit(
      id,
      content,
      metadata,
      email: email ?? identity.email,
      name: name ?? identity.name,
      identity: await _verifiedIdentity(),
    );
  }

  /// Callback variant. The callback fires when the request completes.
  void submitCallback(
    String content,
    void Function(FeedbackResult<FeedbackResponse>) callback, {
    String? email,
    String? name,
    Map<String, dynamic>? properties,
  }) {
    submit(content, email: email, name: name, properties: properties)
        .then(callback);
  }

  /// List public feedback for this widget's organization.
  ///
  /// [boardId] optional — filter to a specific board.
  /// [limit] max items per page (1–50, default 20).
  /// [cursor] pagination cursor from a previous [FeedbackListResult.nextCursor].
  Future<FeedbackResult<FeedbackListResult>> listFeedback({
    String? boardId,
    int limit = 20,
    String? cursor,
  }) async {
    final id = _widgetId;
    final client = _client;
    if (id == null || client == null) {
      return FeedbackFailure(FeedbackJarError.notInitialized);
    }
    final anonId = await AnonId.get();
    return client.listFeedback(
      id,
      boardId,
      limit.clamp(1, 50),
      cursor,
      anonId,
      await _verifiedIdentity(),
    );
  }

  /// Callback variant. The callback fires when the request completes.
  void listFeedbackCallback({
    String? boardId,
    int limit = 20,
    String? cursor,
    required void Function(FeedbackResult<FeedbackListResult>) callback,
  }) {
    listFeedback(boardId: boardId, limit: limit, cursor: cursor).then(callback);
  }

  /// Fetch a single public post by id — used to resolve `#[title](postId)`
  /// mention jump-links. Same visibility rules as [listFeedback].
  Future<FeedbackResult<FeedbackPost>> getPost(String postId) async {
    final id = _widgetId;
    final client = _client;
    if (id == null || client == null) {
      return FeedbackFailure(FeedbackJarError.notInitialized);
    }
    return client.getPost(id, postId, await AnonId.get(), await _verifiedIdentity());
  }

  /// Callback variant. The callback fires when the request completes.
  void getPostCallback(
    String postId,
    void Function(FeedbackResult<FeedbackPost>) callback,
  ) {
    getPost(postId).then(callback);
  }

  /// Fetch this widget's organization config, including whether it asks submitters
  /// for their name/email ("Ask for Name" / "Ask for Email" in the dashboard).
  ///
  /// Use this to decide whether your own submission UI should show those fields —
  /// the SDK does not render any UI itself.
  Future<FeedbackResult<WidgetConfig>> getConfig() async {
    final id = _widgetId;
    final client = _client;
    if (id == null || client == null) {
      return FeedbackFailure(FeedbackJarError.notInitialized);
    }
    return client.getConfig(id);
  }

  /// Callback variant. The callback fires when the request completes.
  void getConfigCallback(
    void Function(FeedbackResult<WidgetConfig>) callback,
  ) {
    getConfig().then(callback);
  }

  /// Upvote [postId] as this install's anonymous guest. Idempotent — voting
  /// twice is a no-op. Requires guest voting to be enabled for the project
  /// ([WidgetConfig.allowVotes]). Returns the new count and vote state.
  Future<FeedbackResult<VoteState>> vote(String postId) async {
    final id = _widgetId;
    final client = _client;
    if (id == null || client == null) {
      return FeedbackFailure(FeedbackJarError.notInitialized);
    }
    return client.voteOnPost(id, postId, await AnonId.get(), await _verifiedIdentity());
  }

  /// Callback variant. The callback fires when the request completes.
  void voteCallback(
    String postId,
    void Function(FeedbackResult<VoteState>) callback,
  ) {
    vote(postId).then(callback);
  }

  /// Remove this install's upvote from [postId]. Idempotent.
  Future<FeedbackResult<VoteState>> unvote(String postId) async {
    final id = _widgetId;
    final client = _client;
    if (id == null || client == null) {
      return FeedbackFailure(FeedbackJarError.notInitialized);
    }
    return client.unvotePost(id, postId, await AnonId.get(), await _verifiedIdentity());
  }

  /// Callback variant. The callback fires when the request completes.
  void unvoteCallback(
    String postId,
    void Function(FeedbackResult<VoteState>) callback,
  ) {
    unvote(postId).then(callback);
  }

  /// Current upvote count and whether this install has voted on [postId].
  Future<FeedbackResult<VoteState>> getVoteState(String postId) async {
    final id = _widgetId;
    final client = _client;
    if (id == null || client == null) {
      return FeedbackFailure(FeedbackJarError.notInitialized);
    }
    return client.getVoteState(id, postId, await AnonId.get(), await _verifiedIdentity());
  }

  /// Callback variant. The callback fires when the request completes.
  void getVoteStateCallback(
    String postId,
    void Function(FeedbackResult<VoteState>) callback,
  ) {
    getVoteState(postId).then(callback);
  }

  /// List public comments for [postId] (two-level threads). Anonymous — no
  /// identity required.
  ///
  /// [limit] max items per page (1–50, default 20).
  /// [cursor] pagination cursor from a previous
  /// [FeedbackCommentListResult.nextCursor].
  Future<FeedbackResult<FeedbackCommentListResult>> listComments(
    String postId, {
    int limit = 20,
    String? cursor,
  }) async {
    final id = _widgetId;
    final client = _client;
    if (id == null || client == null) {
      return FeedbackFailure(FeedbackJarError.notInitialized);
    }
    return client.listComments(id, postId, limit.clamp(1, 50), cursor);
  }

  /// Callback variant. The callback fires when the request completes.
  void listCommentsCallback(
    String postId, {
    int limit = 20,
    String? cursor,
    required void Function(FeedbackResult<FeedbackCommentListResult>) callback,
  }) {
    listComments(postId, limit: limit, cursor: cursor).then(callback);
  }

  /// Add a public comment (or a reply, via [parentId]) on [postId] as this
  /// install's anonymous guest. Requires guest comments to be enabled for the
  /// project ([WidgetConfig.allowComments]).
  ///
  /// [name]/[email] fall back to the remembered identity (see [setIdentity]).
  /// [email] is used only for reply/status notification mail and is never
  /// auto-linked to a real account. [parentId] must be a root comment — you
  /// cannot reply to a reply.
  ///
  /// On success the value is the new comment's id.
  Future<FeedbackResult<String>> addComment(
    String postId,
    String content, {
    String? parentId,
    String? name,
    String? email,
  }) async {
    final id = _widgetId;
    final client = _client;
    if (id == null || client == null) {
      return FeedbackFailure(FeedbackJarError.notInitialized);
    }
    final identity = await getIdentity();
    return client.createComment(
      id,
      postId,
      await AnonId.get(),
      content: content,
      parentId: parentId,
      name: name ?? identity.name,
      email: email ?? identity.email,
      identity: await _verifiedIdentity(),
    );
  }

  /// Callback variant. The callback fires when the request completes.
  void addCommentCallback(
    String postId,
    String content, {
    String? parentId,
    String? name,
    String? email,
    required void Function(FeedbackResult<String>) callback,
  }) {
    addComment(postId, content, parentId: parentId, name: name, email: email)
        .then(callback);
  }
}

/// Errors produced by [FeedbackJar] itself (not network errors).
enum FeedbackJarError implements Exception {
  notInitialized;

  @override
  String toString() =>
      'FeedbackJarError.notInitialized: call FeedbackJar.configure() first.';
}
