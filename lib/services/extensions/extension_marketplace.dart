import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:spotube/services/extensions/extension_models.dart';

/// Searches GitHub for Spicetify extensions (repositories tagged
/// `spicetify-extensions`) and downloads their files.
abstract class ExtensionMarketplace {
  static final Dio _dio = Dio(
    BaseOptions(
      headers: {'Accept': 'application/vnd.github+json'},
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      validateStatus: (_) => true,
    ),
  );

  static const _topic = 'spicetify-extensions';

  static Never _fail(int? status) {
    if (status == 403 || status == 429) {
      throw Exception(
        'GitHub rate limit reached. Try again in a few minutes.',
      );
    }
    throw Exception('GitHub returned ${status ?? 'an error'}.');
  }

  static Future<List<MarketplaceRepo>> search(String query, int page) async {
    final q = query.trim();
    final res = await _dio.get<dynamic>(
      'https://api.github.com/search/repositories',
      queryParameters: {
        'q': '${q.isEmpty ? '' : '$q '}topic:$_topic',
        'sort': 'stars',
        'per_page': 20,
        'page': page,
      },
    );
    if (res.statusCode != 200) _fail(res.statusCode);

    final items = (res.data as Map)['items'] as List;
    return items
        .map((e) => MarketplaceRepo.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  static String _rawBase(MarketplaceRepo repo) =>
      'https://raw.githubusercontent.com/${repo.fullName}/${repo.defaultBranch}/';

  /// Lists the extension files in a repository. Uses the Spicetify
  /// `manifest.json` when present, otherwise lists top-level `.js` files.
  static Future<List<MarketplaceItem>> items(MarketplaceRepo repo) async {
    final base = _rawBase(repo);

    final manifestRes = await _dio.get<String>(
      '${base}manifest.json',
      options: Options(responseType: ResponseType.plain),
    );
    if (manifestRes.statusCode == 200 && manifestRes.data != null) {
      try {
        final decoded = jsonDecode(manifestRes.data!);
        final entries = decoded is List ? decoded : [decoded];
        final found = <MarketplaceItem>[];
        for (final e in entries) {
          if (e is! Map || e['main'] is! String) continue;
          found.add(
            MarketplaceItem(
              name: (e['name'] as String?) ?? repo.name,
              description: (e['description'] as String?) ?? repo.description,
              rawUrl: _abs(base, e['main'] as String),
              repo: repo.fullName,
            ),
          );
        }
        if (found.isNotEmpty) return found;
      } catch (_) {
        // fall through to the file listing
      }
    }

    final contents = await _dio.get<dynamic>(
      'https://api.github.com/repos/${repo.fullName}/contents',
    );
    if (contents.statusCode != 200) _fail(contents.statusCode);

    final skip = RegExp(r'(config|webpack|rollup|eslint|vite|gulp|babel)',
        caseSensitive: false);
    return (contents.data as List)
        .whereType<Map>()
        .where((f) =>
            f['type'] == 'file' &&
            (f['name'] as String).toLowerCase().endsWith('.js') &&
            !skip.hasMatch(f['name'] as String))
        .map((f) => MarketplaceItem(
              name: (f['name'] as String).replaceAll(
                RegExp(r'\.js$', caseSensitive: false),
                '',
              ),
              description: repo.description,
              rawUrl: _abs(base, f['path'] as String),
              repo: repo.fullName,
            ))
        .toList();
  }

  static String _abs(String base, String path) {
    if (path.startsWith('http')) return path;
    return base + path.replaceFirst(RegExp(r'^\.?/'), '');
  }

  /// Turns a github.com `blob` link into its raw file URL.
  static String normalizeUrl(String url) {
    final u = url.trim();
    final m = RegExp(r'^https://github\.com/([^/]+/[^/]+)/blob/(.+)$')
        .firstMatch(u);
    if (m != null) {
      return 'https://raw.githubusercontent.com/${m.group(1)}/${m.group(2)}';
    }
    return u;
  }

  static Future<String> download(String url) async {
    if (!url.startsWith('https://')) {
      throw Exception('Only https links are supported.');
    }
    final res = await _dio.get<String>(
      url,
      options: Options(responseType: ResponseType.plain),
    );
    if (res.statusCode != 200 || res.data == null) {
      throw Exception('Could not download the file (${res.statusCode}).');
    }
    return res.data!;
  }
}
