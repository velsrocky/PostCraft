import 'dart:convert';
import 'dart:io';

import 'app_version.dart';

sealed class UpdateCheckResult {
  const UpdateCheckResult();
}

class UpToDate extends UpdateCheckResult {
  const UpToDate({required this.version});

  final String version;
}

class UpdateAvailable extends UpdateCheckResult {
  const UpdateAvailable({required this.tag, required this.url});

  final String tag;
  final String url;
}

class UpdateCheckFailed extends UpdateCheckResult {
  const UpdateCheckFailed({required this.reason});

  final String reason;
}

/// Queries GitHub Releases for the latest PostCraft tag.
///
/// Never throws: transport, timeout, and payload problems are reported as
/// [UpdateCheckFailed]. The GitHub `tag_name` is normalized by stripping a
/// leading `v`, so `v1.2.3` compares against [AppVersion.string] as `1.2.3`.
class UpdateCheckService {
  const UpdateCheckService._();

  static const defaultRepoSlug = 'velsrocky/PostCraft';
  static const timeout = Duration(seconds: 5);

  static Future<UpdateCheckResult> check({
    String currentVersion = AppVersion.string,
    String repoSlug = defaultRepoSlug,
  }) async {
    final client = HttpClient();
    try {
      client.connectionTimeout = timeout;
      final uri = Uri.parse(
        'https://api.github.com/repos/$repoSlug/releases/latest',
      );
      final request = await client.getUrl(uri).timeout(timeout);
      request.headers.set(
        HttpHeaders.acceptHeader,
        'application/vnd.github+json',
      );
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'PostCraft/$currentVersion',
      );
      final response = await request.close().timeout(timeout);
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(timeout);
      if (response.statusCode != HttpStatus.ok) {
        return UpdateCheckFailed(
          reason: 'GitHub responded with HTTP ${response.statusCode}.',
        );
      }
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        return const UpdateCheckFailed(
          reason: 'GitHub returned an unexpected response.',
        );
      }
      final tagName = decoded['tag_name'];
      if (tagName is! String || tagName.isEmpty) {
        return const UpdateCheckFailed(
          reason: 'The latest release has no tag name.',
        );
      }
      final tag = tagName.startsWith('v') ? tagName.substring(1) : tagName;
      if (_compare(tag, currentVersion) <= 0) {
        return UpToDate(version: currentVersion);
      }
      final htmlUrl = decoded['html_url'];
      return UpdateAvailable(
        tag: tag,
        url: htmlUrl is String && htmlUrl.isNotEmpty
            ? htmlUrl
            : 'https://github.com/$repoSlug/releases/latest',
      );
    } on Object catch (error) {
      return UpdateCheckFailed(reason: '$error');
    } finally {
      client.close(force: true);
    }
  }

  static int _compare(String a, String b) {
    final aParts = a.split('-');
    final bParts = b.split('-');
    final aNumbers = _numbers(aParts.first);
    final bNumbers = _numbers(bParts.first);
    for (var i = 0; i < aNumbers.length || i < bNumbers.length; i++) {
      final x = i < aNumbers.length ? aNumbers[i] : 0;
      final y = i < bNumbers.length ? bNumbers[i] : 0;
      if (x != y) return x.compareTo(y);
    }
    final aPre = aParts.length > 1 ? aParts.sublist(1).join('-') : null;
    final bPre = bParts.length > 1 ? bParts.sublist(1).join('-') : null;
    if (aPre == null && bPre == null) return 0;
    if (aPre == null) return 1;
    if (bPre == null) return -1;
    return aPre.compareTo(bPre);
  }

  static List<int> _numbers(String value) =>
      value.split('.').map((part) => int.tryParse(part) ?? 0).toList();
}
