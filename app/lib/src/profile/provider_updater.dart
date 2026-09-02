import 'config_outline.dart';
import 'provider_cache.dart';
import 'subscription_fetcher.dart';

/// Refreshes a provider collection while the core is down.
///
/// The core owns this job whenever it runs. Offline the app downloads the body
/// itself, under the same SSRF checks as a subscription, and stores it in the
/// very file the core reads on its next start.
class OfflineProviderUpdater {
  const OfflineProviderUpdater({required this.fetcher, required this.cache});

  final SubscriptionFetcher fetcher;
  final ProviderCache cache;

  Future<void> update(ConfigProviderRef ref) async {
    if (!ref.isDownloadable) {
      throw SubscriptionException('${ref.name} has no URL to download');
    }
    // Bytes, not text: a rule set in `mrs` format is a binary bundle.
    await cache.write(ref, await fetcher.fetchBytes(ref.url!));
  }
}
