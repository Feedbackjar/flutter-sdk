/// SDK identity, sent on every request as `X-FeedbackJar-SDK: <name>/<version>`
/// and mirrored into submission metadata (`sdk` / `sdkVersion`).
///
/// Keep [sdkVersion] in sync with `pubspec.yaml` on every release.
const String sdkName = 'flutter';
const String sdkVersion = '1.7.0';

/// e.g. `"flutter/1.7.0"`.
const String sdkIdentifier = '$sdkName/$sdkVersion';
