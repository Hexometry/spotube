import 'dart:convert';

class ExtensionRecord {
  final String id;
  final String name;
  final String url;
  final String repo;
  final bool enabled;

  const ExtensionRecord({
    required this.id,
    required this.name,
    required this.url,
    this.repo = '',
    this.enabled = true,
  });

  ExtensionRecord copyWith({String? name, bool? enabled}) => ExtensionRecord(
        id: id,
        name: name ?? this.name,
        url: url,
        repo: repo,
        enabled: enabled ?? this.enabled,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'url': url,
        'repo': repo,
        'enabled': enabled,
      };

  factory ExtensionRecord.fromJson(Map<String, dynamic> json) =>
      ExtensionRecord(
        id: json['id'] as String,
        name: json['name'] as String,
        url: json['url'] as String,
        repo: (json['repo'] as String?) ?? '',
        enabled: (json['enabled'] as bool?) ?? true,
      );

  static List<ExtensionRecord> decodeList(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => ExtensionRecord.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static String encodeList(List<ExtensionRecord> list) =>
      jsonEncode(list.map((e) => e.toJson()).toList());
}

/// A button or menu entry an extension registered through the Spicetify API.
class ExtensionAction {
  final String extensionId;
  final int id;
  final String kind; // 'topbar' or 'menu'
  final String label;

  const ExtensionAction({
    required this.extensionId,
    required this.id,
    required this.kind,
    required this.label,
  });
}

class ExtensionLogLine {
  final String extensionName;
  final String level;
  final String message;

  const ExtensionLogLine(this.extensionName, this.level, this.message);
}

/// One installable file found in a GitHub repository.
class MarketplaceItem {
  final String name;
  final String description;
  final String rawUrl;
  final String repo;

  const MarketplaceItem({
    required this.name,
    required this.description,
    required this.rawUrl,
    required this.repo,
  });
}

class MarketplaceRepo {
  final String name;
  final String fullName;
  final String defaultBranch;
  final String description;
  final String owner;
  final int stars;

  const MarketplaceRepo({
    required this.name,
    required this.fullName,
    required this.defaultBranch,
    required this.description,
    required this.owner,
    required this.stars,
  });

  factory MarketplaceRepo.fromJson(Map<String, dynamic> j) => MarketplaceRepo(
        name: j['name'] as String,
        fullName: j['full_name'] as String,
        defaultBranch: (j['default_branch'] as String?) ?? 'main',
        description: (j['description'] as String?) ?? '',
        owner: ((j['owner'] as Map?)?['login'] as String?) ?? '',
        stars: (j['stargazers_count'] as int?) ?? 0,
      );
}
