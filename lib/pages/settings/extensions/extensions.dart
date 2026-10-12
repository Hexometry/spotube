import 'package:auto_route/auto_route.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:spotube/components/titlebar/titlebar.dart';
import 'package:spotube/provider/extensions/extension_host.dart';
import 'package:spotube/services/extensions/extension_marketplace.dart';
import 'package:spotube/services/extensions/extension_models.dart';

const _bold = TextStyle(fontWeight: FontWeight.w600);

@RoutePage()
class ExtensionsPage extends HookConsumerWidget {
  static const name = 'extensions';

  const ExtensionsPage({super.key});

  @override
  Widget build(BuildContext context, ref) {
    final host = ref.watch(extensionHostProvider);
    final notifier = ref.watch(extensionHostProvider.notifier);

    final tab = useState(0);

    return SafeArea(
      bottom: false,
      child: Scaffold(
        headers: [
          TitleBar(title: const Text('Extensions')),
        ],
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!notifier.supported)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Extensions can only run in the Android and iOS builds.',
                  ),
                ),
              Row(
                children: [
                  tab.value == 0
                      ? Button.primary(
                          onPressed: () {},
                          child: const Text('Marketplace'),
                        )
                      : Button.secondary(
                          onPressed: () => tab.value = 0,
                          child: const Text('Marketplace'),
                        ),
                  const SizedBox(width: 8),
                  tab.value == 1
                      ? Button.primary(
                          onPressed: () {},
                          child: Text('Installed (${host.records.length})'),
                        )
                      : Button.secondary(
                          onPressed: () => tab.value = 1,
                          child: Text('Installed (${host.records.length})'),
                        ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: tab.value == 0
                    ? const _MarketplaceTab()
                    : const _InstalledTab(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MarketplaceTab extends HookConsumerWidget {
  const _MarketplaceTab();

  @override
  Widget build(BuildContext context, ref) {
    final query = useTextEditingController();
    final repos = useState<List<MarketplaceRepo>>([]);
    final loading = useState(false);
    final error = useState<String?>(null);
    final page = useState(1);
    final hasMore = useState(false);

    Future<void> load({required bool reset}) async {
      if (reset) page.value = 1;
      loading.value = true;
      error.value = null;
      try {
        final found = await ExtensionMarketplace.search(query.text, page.value);
        repos.value = reset ? found : [...repos.value, ...found];
        hasMore.value = found.length >= 20;
      } catch (e) {
        error.value = e.toString().replaceFirst('Exception: ', '');
      } finally {
        loading.value = false;
      }
    }

    useEffect(() {
      load(reset: true);
      return null;
    }, []);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: query,
                placeholder: const Text('Search extensions on GitHub'),
                onSubmitted: (_) => load(reset: true),
              ),
            ),
            const SizedBox(width: 8),
            Button.primary(
              onPressed: () => load(reset: true),
              child: const Text('Search'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Opacity(
          opacity: .7,
          child: Text(
            'Extensions are third-party code. They can see what is playing '
            'and use the internet, so install only ones you trust. Many '
            'extensions written for the Spotify desktop app will not work '
            'here.',
            style: TextStyle(fontSize: 12),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView(
            children: [
              if (error.value != null)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    error.value!,
                    style: const TextStyle(color: Color(0xFFE5484D)),
                  ),
                ),
              for (final repo in repos.value) _RepoCard(repo: repo),
              if (loading.value)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                ),
              if (!loading.value && repos.value.isEmpty && error.value == null)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Nothing found.'),
                ),
              if (!loading.value && hasMore.value)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Button.secondary(
                    onPressed: () {
                      page.value += 1;
                      load(reset: false);
                    },
                    child: const Text('Load more'),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RepoCard extends HookConsumerWidget {
  final MarketplaceRepo repo;

  const _RepoCard({required this.repo});

  @override
  Widget build(BuildContext context, ref) {
    final notifier = ref.watch(extensionHostProvider.notifier);
    final host = ref.watch(extensionHostProvider);
    final items = useState<List<MarketplaceItem>?>(null);
    final loading = useState(false);
    final error = useState<String?>(null);
    final installing = useState<String?>(null);

    Future<void> showItems() async {
      loading.value = true;
      error.value = null;
      try {
        items.value = await ExtensionMarketplace.items(repo);
      } catch (e) {
        error.value = e.toString().replaceFirst('Exception: ', '');
      } finally {
        loading.value = false;
      }
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(repo.name, style: _bold),
            if (repo.description.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Opacity(opacity: .75, child: Text(repo.description)),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 8),
              child: Opacity(
                opacity: .6,
                child: Text(
                  '${repo.owner} · ${repo.stars} stars',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ),
            if (items.value == null)
              Align(
                alignment: Alignment.centerLeft,
                child: Button.secondary(
                  enabled: !loading.value,
                  onPressed: showItems,
                  child: Text(loading.value ? 'Loading…' : 'See extensions'),
                ),
              ),
            if (error.value != null)
              Text(
                error.value!,
                style: const TextStyle(color: Color(0xFFE5484D)),
              ),
            if (items.value != null && items.value!.isEmpty)
              const Text('No installable extension files in this repository.'),
            for (final item in items.value ?? const <MarketplaceItem>[])
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.name, style: _bold),
                          if (item.description.isNotEmpty)
                            Opacity(
                              opacity: .75,
                              child: Text(
                                item.description,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Button.primary(
                      enabled: installing.value == null,
                      onPressed: () async {
                        installing.value = item.rawUrl;
                        try {
                          await notifier.install(
                            name: item.name,
                            url: item.rawUrl,
                            repo: item.repo,
                          );
                        } catch (e) {
                          error.value =
                              e.toString().replaceFirst('Exception: ', '');
                        } finally {
                          installing.value = null;
                        }
                      },
                      child: Text(
                        installing.value == item.rawUrl
                            ? 'Installing…'
                            : host.records.any((r) => r.url == item.rawUrl)
                                ? 'Reinstall'
                                : 'Install',
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _InstalledTab extends HookConsumerWidget {
  const _InstalledTab();

  @override
  Widget build(BuildContext context, ref) {
    final host = ref.watch(extensionHostProvider);
    final notifier = ref.watch(extensionHostProvider.notifier);
    final url = useTextEditingController();
    final busy = useState(false);
    final error = useState<String?>(null);

    Future<void> run(Future<void> Function() job) async {
      busy.value = true;
      error.value = null;
      try {
        await job();
      } catch (e) {
        error.value = e.toString().replaceFirst('Exception: ', '');
      } finally {
        busy.value = false;
      }
    }

    return ListView(
      children: [
        Text('Install from a link', style: _bold),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: url,
                placeholder: const Text('https://github.com/user/repo/blob/…'),
              ),
            ),
            const SizedBox(width: 8),
            Button.primary(
              enabled: !busy.value,
              onPressed: () => run(() async {
                final link = ExtensionMarketplace.normalizeUrl(url.text);
                final file = link.split('/').last.split('?').first;
                await notifier.install(
                  name: file.replaceAll(RegExp(r'\.js$'), ''),
                  url: link,
                );
                url.clear();
              }),
              child: const Text('Install'),
            ),
          ],
        ),
        if (error.value != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              error.value!,
              style: const TextStyle(color: Color(0xFFE5484D)),
            ),
          ),
        const SizedBox(height: 16),
        Text('Installed', style: _bold),
        const SizedBox(height: 4),
        if (host.records.isEmpty)
          const Text('No extensions yet. Install one from the Marketplace.'),
        for (final record in host.records)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: SurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(record.name, style: _bold)),
                      Switch(
                        value: record.enabled,
                        onChanged: (value) => run(
                          () => notifier.setEnabled(record, value),
                        ),
                      ),
                    ],
                  ),
                  Opacity(
                    opacity: .6,
                    child: Text(
                      record.repo.isEmpty ? record.url : record.repo,
                      style: const TextStyle(fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final action in host.actions
                          .where((a) => a.extensionId == record.id))
                        Button.secondary(
                          onPressed: () => notifier.runAction(action),
                          child: Text(action.label),
                        ),
                      Button.secondary(
                        enabled: !busy.value,
                        onPressed: () => run(() => notifier.update(record)),
                        child: const Text('Update'),
                      ),
                      Button.destructive(
                        enabled: !busy.value,
                        onPressed: () => run(() => notifier.remove(record)),
                        child: const Text('Remove'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 16),
        Text('Extension log', style: _bold),
        const SizedBox(height: 4),
        if (host.logs.isEmpty)
          const Opacity(opacity: .7, child: Text('Nothing logged yet.')),
        for (final line in host.logs.reversed.take(40))
          Text(
            '[${line.extensionName}] ${line.message}',
            style: TextStyle(
              fontSize: 12,
              color: line.level == 'error' ? const Color(0xFFE5484D) : null,
            ),
          ),
        const SizedBox(height: 120),
      ],
    );
  }
}
