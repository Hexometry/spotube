import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter_inappwebview/flutter_inappwebview.dart'
    show
        HeadlessInAppWebView,
        InAppWebViewInitialData,
        InAppWebViewSettings,
        UserScript,
        UserScriptInjectionTime,
        WebUri;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:media_kit/media_kit.dart' show PlaylistMode;
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:spotube/collections/routes.dart';
import 'package:spotube/collections/spotube_icons.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/audio_player/audio_player.dart';
import 'package:spotube/services/audio_player/audio_player.dart';
import 'package:spotube/services/extensions/extension_marketplace.dart';
import 'package:spotube/services/extensions/extension_models.dart';
import 'package:spotube/services/extensions/spicetify_shim.dart';
import 'package:spotube/services/kv_store/kv_store.dart';
import 'package:spotube/services/logger/logger.dart';
import 'package:spotube/utils/platform.dart';

class ExtensionHostState {
  final List<ExtensionRecord> records;
  final List<ExtensionAction> actions;
  final List<ExtensionLogLine> logs;

  const ExtensionHostState({
    this.records = const [],
    this.actions = const [],
    this.logs = const [],
  });

  ExtensionHostState copyWith({
    List<ExtensionRecord>? records,
    List<ExtensionAction>? actions,
    List<ExtensionLogLine>? logs,
  }) =>
      ExtensionHostState(
        records: records ?? this.records,
        actions: actions ?? this.actions,
        logs: logs ?? this.logs,
      );
}

/// Runs Spicetify-style extensions. Every extension lives in its own hidden
/// WebView with the Spicetify compatibility layer injected, so extension code
/// never shares a JavaScript context with the app or with other extensions.
class ExtensionHostNotifier extends Notifier<ExtensionHostState> {
  static const _listKey = 'extensions.list';
  static String _codeKey(String id) => 'extensions.code.$id';
  static String _lsKey(String id) => 'extensions.ls.$id';

  final Map<String, HeadlessInAppWebView> _views = {};
  final List<StreamSubscription> _subs = [];
  Timer? _syncTimer;

  /// Hidden WebViews are only available on mobile builds.
  bool get supported => kIsMobile;

  @override
  ExtensionHostState build() {
    final prefs = KVStoreService.sharedPreferences;
    final records = ExtensionRecord.decodeList(prefs.getString(_listKey));

    if (supported) {
      _subs.add(audioPlayer.playingStream.listen((_) => _emit('onplaypause')));
      ref.listen(audioPlayerProvider, (prev, next) {
        if (prev?.activeTrack?.id != next.activeTrack?.id) {
          _emit('songchange');
        }
      });
      _syncTimer = Timer.periodic(const Duration(seconds: 5), (_) {
        if (audioPlayer.isPlaying) _emit('sync');
      });

      Future.microtask(() {
        for (final r in records.where((r) => r.enabled)) {
          _start(r);
        }
      });
    }

    ref.onDispose(() {
      for (final s in _subs) {
        s.cancel();
      }
      _syncTimer?.cancel();
      for (final v in _views.values) {
        v.dispose();
      }
      _views.clear();
    });

    return ExtensionHostState(records: records);
  }

  // ---- persistence ------------------------------------------------------

  Future<void> _saveRecords(List<ExtensionRecord> records) async {
    await KVStoreService.sharedPreferences
        .setString(_listKey, ExtensionRecord.encodeList(records));
    state = state.copyWith(records: records);
  }

  Map<String, dynamic> _loadLs(String id) {
    final raw = KVStoreService.sharedPreferences.getString(_lsKey(id));
    if (raw == null) return {};
    try {
      return Map<String, dynamic>.from(jsonDecode(raw));
    } catch (_) {
      return {};
    }
  }

  Future<void> _saveLs(String id, Map<String, dynamic> map) =>
      KVStoreService.sharedPreferences.setString(_lsKey(id), jsonEncode(map));

  // ---- public API -------------------------------------------------------

  Future<void> install({
    required String name,
    required String url,
    String repo = '',
  }) async {
    final code = await ExtensionMarketplace.download(url);
    final existing = state.records.where((r) => r.url == url).toList();
    final id = existing.isNotEmpty
        ? existing.first.id
        : 'x${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';

    await KVStoreService.sharedPreferences.setString(_codeKey(id), code);

    await _stop(id);
    final record = ExtensionRecord(id: id, name: name, url: url, repo: repo);
    await _saveRecords([
      ...state.records.where((r) => r.id != id),
      record,
    ]);
    await _start(record);
    _toast('$name installed');
  }

  Future<void> update(ExtensionRecord record) async {
    final code = await ExtensionMarketplace.download(record.url);
    await KVStoreService.sharedPreferences.setString(_codeKey(record.id), code);
    await _stop(record.id);
    if (record.enabled) await _start(record);
    _toast('Updated ${record.name}');
  }

  Future<void> setEnabled(ExtensionRecord record, bool enabled) async {
    await _saveRecords([
      for (final r in state.records)
        if (r.id == record.id) r.copyWith(enabled: enabled) else r,
    ]);
    if (enabled) {
      await _start(record.copyWith(enabled: true));
    } else {
      await _stop(record.id);
    }
  }

  Future<void> remove(ExtensionRecord record) async {
    await _stop(record.id);
    final prefs = KVStoreService.sharedPreferences;
    await prefs.remove(_codeKey(record.id));
    await prefs.remove(_lsKey(record.id));
    await _saveRecords(state.records.where((r) => r.id != record.id).toList());
  }

  Future<void> runAction(ExtensionAction action) async {
    final view = _views[action.extensionId];
    await view?.webViewController
        ?.evaluateJavascript(source: 'window.__spAction(${action.id});');
  }

  // ---- WebView lifecycle ------------------------------------------------

  Future<void> _start(ExtensionRecord record) async {
    if (!supported || _views.containsKey(record.id)) return;

    final code =
        KVStoreService.sharedPreferences.getString(_codeKey(record.id));
    if (code == null) return;

    final init = jsonEncode({
      'state': _snapshot(),
      'ls': _loadLs(record.id),
    }).replaceAll('<', r'<');

    final safeCode =
        code.replaceAll(RegExp(r'</script', caseSensitive: false), r'<\/script');
    final html = '<!doctype html><html><head><meta charset="utf-8"></head>'
        '<body><script>\n$safeCode\n</script></body></html>';

    final view = HeadlessInAppWebView(
      initialData: InAppWebViewInitialData(
        data: html,
        baseUrl: WebUri('https://spicetify-extension.invalid/'),
      ),
      initialSettings: InAppWebViewSettings(javaScriptEnabled: true),
      initialUserScripts: UnmodifiableListView<UserScript>([
        UserScript(
          source: 'window.__INIT = $init;',
          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
        ),
        UserScript(
          source: spicetifyShimSource,
          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
        ),
      ]),
      onWebViewCreated: (controller) {
        controller.addJavaScriptHandler(
          handlerName: 'sp',
          callback: (args) => _handle(record, args),
        );
      },
      onConsoleMessage: (controller, message) {
        _log(record, 'log', message.message);
      },
    );

    _views[record.id] = view;
    try {
      await view.run();
    } catch (e, stack) {
      _views.remove(record.id);
      _log(record, 'error', 'Could not start: $e');
      AppLogger.reportError(e, stack);
    }
  }

  Future<void> _stop(String id) async {
    final view = _views.remove(id);
    if (view != null) {
      try {
        await view.dispose();
      } catch (_) {
        // already gone
      }
    }
    state = state.copyWith(
      actions: state.actions.where((a) => a.extensionId != id).toList(),
    );
  }

  // ---- host <-> extension bridge ---------------------------------------

  Future<dynamic> _handle(ExtensionRecord record, List<dynamic> args) async {
    try {
      final method = args.first as String;
      switch (method) {
        case 'log':
          _log(record, args[1] as String, args[2].toString());
          return {'v': null};
        case 'notify':
          _toast(args[1].toString(), error: args[2] == true);
          return {'v': null};
        case 'action':
          state = state.copyWith(actions: [
            ...state.actions,
            ExtensionAction(
              extensionId: record.id,
              id: (args[1] as num).toInt(),
              kind: args[2] as String,
              label: args[3] as String,
            ),
          ]);
          return {'v': null};
        case 'ls':
          final map = _loadLs(record.id);
          switch (args[1]) {
            case 'set':
              map[args[2] as String] = args[3];
            case 'remove':
              map.remove(args[2]);
            default:
              map.clear();
          }
          await _saveLs(record.id, map);
          return {'v': null};
        case 'player':
          await _player(args[1] as String, args.length > 2 ? args[2] : null);
          return {'v': null};
        default:
          throw Exception('Unknown call $method');
      }
    } catch (e) {
      _log(record, 'error', e.toString());
      return {'__err': e.toString().replaceFirst('Exception: ', '')};
    }
  }

  Future<void> _player(String op, dynamic arg) async {
    switch (op) {
      case 'play':
        await audioPlayer.resume();
      case 'pause':
        await audioPlayer.pause();
      case 'next':
        await audioPlayer.skipToNext();
      case 'prev':
        await audioPlayer.skipToPrevious();
      case 'seek':
        await audioPlayer.seek(Duration(milliseconds: (arg as num).round()));
      case 'volume':
        await audioPlayer
            .setVolume(((arg as num) / 100).clamp(0.0, 1.0).toDouble());
      case 'shuffle':
        await audioPlayer.setShuffle(!audioPlayer.isShuffled);
      case 'repeat':
        await audioPlayer.setLoopMode(switch (audioPlayer.loopMode) {
          PlaylistMode.none => PlaylistMode.loop,
          PlaylistMode.loop => PlaylistMode.single,
          PlaylistMode.single => PlaylistMode.none,
        });
      default:
        throw Exception('Unsupported player call: $op');
    }
  }

  Map<String, dynamic> _snapshot() {
    final track = ref.read(audioPlayerProvider).activeTrack;

    return {
      'playing': audioPlayer.isPlaying,
      'progress': audioPlayer.position.inMilliseconds,
      'duration': audioPlayer.duration.inMilliseconds,
      'volume': (audioPlayer.volume * 100).round(),
      'shuffle': audioPlayer.isShuffled,
      'repeat': switch (audioPlayer.loopMode) {
        PlaylistMode.none => 'off',
        PlaylistMode.loop => 'context',
        PlaylistMode.single => 'track',
      },
      'item': track == null ? null : _trackJson(track),
    };
  }

  Map<String, dynamic> _trackJson(SpotubeTrackObject t) {
    final scheme = t.externalUri.startsWith('https://open.spotify.com/')
        ? 'spotify'
        : 'spotube';

    return {
      'uri': '$scheme:track:${t.id}',
      'name': t.name,
      'duration_ms': t.durationMs,
      'artists': [
        for (final a in t.artists) {'name': a.name, 'uri': '$scheme:artist:${a.id}'},
      ],
      'album': {
        'name': t.album.name,
        'uri': '$scheme:album:${t.album.id}',
        'images': [
          for (final i in t.album.images) {'url': i.url},
        ],
      },
    };
  }

  void _emit(String event) {
    if (_views.isEmpty) return;
    final js =
        'window.__spEmit && window.__spEmit(${jsonEncode(event)}, ${jsonEncode(_snapshot())});';
    for (final view in _views.values) {
      view.webViewController?.evaluateJavascript(source: js);
    }
  }

  void _log(ExtensionRecord record, String level, String message) {
    final logs = [
      ...state.logs,
      ExtensionLogLine(record.name, level, message),
    ];
    state = state.copyWith(
      logs: logs.length > 200 ? logs.sublist(logs.length - 200) : logs,
    );
  }

  void _toast(String message, {bool error = false}) {
    final context = rootNavigatorKey.currentContext;
    if (context == null) return;

    showToast(
      context: context,
      builder: (context, overlay) {
        return SurfaceCard(
          child: Basic(
            leading: Icon(
              error ? SpotubeIcons.error : SpotubeIcons.plugin,
              color: error ? Colors.red : null,
            ),
            title: Text(message),
            leadingAlignment: Alignment.center,
          ),
        );
      },
    );
  }
}

final extensionHostProvider =
    NotifierProvider<ExtensionHostNotifier, ExtensionHostState>(
  ExtensionHostNotifier.new,
);
