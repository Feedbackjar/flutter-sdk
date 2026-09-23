import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models.dart';
import 'sdk_info.dart';

class ApiClient {
  static const _baseUrl = 'https://api.feedbackjar.com';

  final _http = http.Client();
  final String? appId;

  ApiClient({this.appId});

  /// [identity] is the org-signed `{userId, email, timestamp, signature}`
  /// payload — mirrors the JS widget's `identify()` / portal auto-login
  /// payload. Sent as `X-FeedbackJar-Identity` (base64 JSON) so the server
  /// attributes the vote/comment/`hasVoted` lookup to this real user instead
  /// of the anonymous id. Omitted (falls back to anonymous) when null.
  Map<String, String> _headers({
    bool json = false,
    String? anonId,
    Map<String, dynamic>? identity,
  }) {
    return {
      'X-FeedbackJar-SDK': sdkIdentifier,
      if (json) 'Content-Type': 'application/json',
      if (appId != null && appId!.isNotEmpty) 'X-FeedbackJar-App-Id': appId!,
      if (anonId != null && anonId.isNotEmpty) 'X-FeedbackJar-Anon-Id': anonId,
      if (identity != null)
        'X-FeedbackJar-Identity': base64Encode(utf8.encode(jsonEncode(identity))),
    };
  }

  /// Turns a non-2xx response into an [Exception] carrying the server's
  /// `{"error": "..."}` message verbatim, falling back to the status code.
  Exception _errorFrom(http.Response response, String fallback) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        final error = decoded['error'];
        if (error is String && error.isNotEmpty) return Exception(error);
      }
    } catch (_) {
      // Non-JSON body — fall through to the generic message.
    }
    return Exception('$fallback: HTTP ${response.statusCode}');
  }

  Future<FeedbackResult<FeedbackResponse>> submit(
    String widgetId,
    String content,
    Map<String, dynamic> metadata, {
    String? email,
    String? name,
    Map<String, dynamic>? identity,
  }) async {
    try {
      final uri = Uri.parse('$_baseUrl/widget/$widgetId/submit');
      final body = <String, dynamic>{
        'content': content,
        'metadata': metadata,
        if (email != null && email.isNotEmpty) 'email': email,
        if (name != null && name.isNotEmpty) 'userName': name,
        if (identity != null) 'identity': identity,
      };
      final response = await _http.post(
        uri,
        headers: _headers(json: true),
        body: jsonEncode(body),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw _errorFrom(response, 'Submit failed');
      }
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return FeedbackSuccess(FeedbackResponse(
        postId: json['postId'] as String,
        title: json['title'] as String,
        type: json['type'] as String,
        boardId: json['boardId'] as String,
      ));
    } catch (e) {
      return FeedbackFailure(e);
    }
  }

  Future<FeedbackResult<FeedbackListResult>> listFeedback(
    String widgetId,
    String? boardId,
    int limit,
    String? cursor,
    String? anonId, [
    Map<String, dynamic>? identity,
  ]) async {
    try {
      final queryParams = <String, String>{
        'limit': '$limit',
        if (boardId != null) 'boardId': boardId,
        if (cursor != null) 'cursor': cursor,
      };
      final uri = Uri.parse('$_baseUrl/widget/$widgetId/posts')
          .replace(queryParameters: queryParams);
      final response = await _http.get(
        uri,
        headers: _headers(anonId: anonId, identity: identity),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw _errorFrom(response, 'List failed');
      }
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final posts = (json['posts'] as List)
          .map((p) => _postFrom(p as Map<String, dynamic>))
          .toList();
      return FeedbackSuccess(FeedbackListResult(
        posts: posts,
        nextCursor: json['nextCursor'] as String?,
      ));
    } catch (e) {
      return FeedbackFailure(e);
    }
  }

  static FeedbackPost _postFrom(Map<String, dynamic> post) => FeedbackPost(
        id: post['id'] as String,
        title: post['title'] as String,
        content: post['content'] as String,
        type: post['type'] as String,
        status: post['status'] as String,
        slug: post['slug'] as String,
        boardId: post['boardId'] as String,
        voteCount: post['voteCount'] as int,
        commentCount: post['commentCount'] as int,
        upvotes: post['upvotes'] as int,
        hasVoted: post['hasVoted'] as bool? ?? false,
        authorName: post['authorName'] as String?,
        createdAt: post['createdAt'] as String,
        updatedAt: post['updatedAt'] as String,
      );

  /// One public post by id — resolves `#[title](postId)` mention jump-links.
  Future<FeedbackResult<FeedbackPost>> getPost(
    String widgetId,
    String postId,
    String? anonId, [
    Map<String, dynamic>? identity,
  ]) async {
    try {
      final uri = Uri.parse(
        '$_baseUrl/widget/$widgetId/posts/${Uri.encodeComponent(postId)}',
      );
      final response = await _http.get(
        uri,
        headers: _headers(anonId: anonId, identity: identity),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw _errorFrom(response, 'Post fetch failed');
      }
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return FeedbackSuccess(_postFrom(json));
    } catch (e) {
      return FeedbackFailure(e);
    }
  }

  Future<FeedbackResult<WidgetConfig>> getConfig(String widgetId) async {
    try {
      final uri = Uri.parse('$_baseUrl/widget/$widgetId/config');
      final response = await _http.get(uri, headers: _headers());
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw _errorFrom(response, 'Config fetch failed');
      }
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return FeedbackSuccess(WidgetConfig(
        collectName: json['collectName'] as bool? ?? false,
        collectEmail: json['collectEmail'] as bool? ?? false,
        allowVotes: json['allowVotes'] as bool? ?? false,
        allowComments: json['allowComments'] as bool? ?? false,
      ));
    } catch (e) {
      return FeedbackFailure(e);
    }
  }

  Future<FeedbackResult<VoteState>> voteOnPost(
    String widgetId,
    String postId,
    String anonId, [
    Map<String, dynamic>? identity,
  ]) =>
      _vote(widgetId, postId, anonId, 'vote', identity);

  Future<FeedbackResult<VoteState>> unvotePost(
    String widgetId,
    String postId,
    String anonId, [
    Map<String, dynamic>? identity,
  ]) =>
      _vote(widgetId, postId, anonId, 'unvote', identity);

  Future<FeedbackResult<VoteState>> _vote(
    String widgetId,
    String postId,
    String anonId,
    String action, [
    Map<String, dynamic>? identity,
  ]) async {
    try {
      final uri = Uri.parse('$_baseUrl/widget/$widgetId/posts/$postId/$action');
      final response = await _http.post(
        uri,
        headers: _headers(anonId: anonId, identity: identity),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw _errorFrom(response, '$action failed');
      }
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return FeedbackSuccess(_voteStateFrom(json));
    } catch (e) {
      return FeedbackFailure(e);
    }
  }

  Future<FeedbackResult<VoteState>> getVoteState(
    String widgetId,
    String postId,
    String anonId, [
    Map<String, dynamic>? identity,
  ]) async {
    try {
      final uri = Uri.parse('$_baseUrl/widget/$widgetId/posts/$postId/vote');
      final response = await _http.get(
        uri,
        headers: _headers(anonId: anonId, identity: identity),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw _errorFrom(response, 'Vote state fetch failed');
      }
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return FeedbackSuccess(_voteStateFrom(json));
    } catch (e) {
      return FeedbackFailure(e);
    }
  }

  Future<FeedbackResult<FeedbackCommentListResult>> listComments(
    String widgetId,
    String postId,
    int limit,
    String? cursor,
  ) async {
    try {
      final queryParams = <String, String>{
        'limit': '$limit',
        if (cursor != null) 'cursor': cursor,
      };
      final uri = Uri.parse('$_baseUrl/widget/$widgetId/posts/$postId/comments')
          .replace(queryParameters: queryParams);
      final response = await _http.get(uri, headers: _headers());
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw _errorFrom(response, 'Comment list failed');
      }
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final comments = (json['comments'] as List)
          .map((c) => _commentFrom(c as Map<String, dynamic>))
          .toList();
      return FeedbackSuccess(FeedbackCommentListResult(
        comments: comments,
        nextCursor: json['nextCursor'] as String?,
      ));
    } catch (e) {
      return FeedbackFailure(e);
    }
  }

  /// Returns the new comment's id on success.
  Future<FeedbackResult<String>> createComment(
    String widgetId,
    String postId,
    String anonId, {
    required String content,
    String? parentId,
    String? name,
    String? email,
    Map<String, dynamic>? identity,
  }) async {
    try {
      final uri =
          Uri.parse('$_baseUrl/widget/$widgetId/posts/$postId/comments');
      final body = <String, dynamic>{
        'content': content,
        if (parentId != null && parentId.isNotEmpty) 'parentId': parentId,
        if (name != null && name.isNotEmpty) 'name': name,
        if (email != null && email.isNotEmpty) 'email': email,
      };
      final response = await _http.post(
        uri,
        headers: _headers(json: true, anonId: anonId, identity: identity),
        body: jsonEncode(body),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw _errorFrom(response, 'Comment failed');
      }
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return FeedbackSuccess(json['id'] as String);
    } catch (e) {
      return FeedbackFailure(e);
    }
  }

  Future<FeedbackResult<void>> identify(
    String widgetId,
    String anonId, {
    String? name,
    String? email,
  }) async {
    try {
      final uri = Uri.parse('$_baseUrl/widget/$widgetId/identify');
      final body = <String, dynamic>{
        if (name != null && name.isNotEmpty) 'name': name,
        if (email != null && email.isNotEmpty) 'email': email,
      };
      final response = await _http.post(
        uri,
        headers: _headers(json: true, anonId: anonId),
        body: jsonEncode(body),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw _errorFrom(response, 'Identify failed');
      }
      return const FeedbackSuccess<void>(null);
    } catch (e) {
      return FeedbackFailure(e);
    }
  }

  VoteState _voteStateFrom(Map<String, dynamic> json) => VoteState(
        upvotes: json['upvotes'] as int? ?? 0,
        hasVoted: json['hasVoted'] as bool? ?? false,
      );

  FeedbackComment _commentFrom(Map<String, dynamic> json) => FeedbackComment(
        id: json['id'] as String,
        content: json['content'] as String,
        authorName: json['authorName'] as String,
        authorRole: json['authorRole'] as String?,
        isBot: json['isBot'] as bool? ?? false,
        parentId: json['parentId'] as String?,
        createdAt: json['createdAt'] as String,
        replies: (json['replies'] as List?)
                ?.map((r) => _commentFrom(r as Map<String, dynamic>))
                .toList() ??
            const [],
      );
}
