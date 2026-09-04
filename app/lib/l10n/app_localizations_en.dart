// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'maomao';

  @override
  String get navHome => 'Home';

  @override
  String get navProxies => 'Proxies';

  @override
  String get navProfiles => 'Profiles';

  @override
  String get navActivity => 'Activity';

  @override
  String get navSettings => 'Settings';

  @override
  String get titleDashboard => 'Dashboard';

  @override
  String get titleProxies => 'Proxies';

  @override
  String get titleProfiles => 'Profiles';

  @override
  String get titleActivity => 'Activity';

  @override
  String get titleSettings => 'Settings';

  @override
  String get stateConnected => 'Connected';

  @override
  String get stateConnecting => 'Connecting…';

  @override
  String get stateDisconnected => 'Disconnected';

  @override
  String get noProfileSelected => 'No profile selected';

  @override
  String get trafficUpload => 'Upload';

  @override
  String get trafficDownload => 'Download';

  @override
  String get sessionTotal => 'Session total';

  @override
  String get activeConnections => 'Active connections';

  @override
  String get coreLabel => 'Core';

  @override
  String coreVersion(String version) {
    return 'mihomo $version';
  }

  @override
  String get loading => 'loading…';

  @override
  String get unavailable => 'unavailable';

  @override
  String proxiesUnavailable(String error) {
    return 'Unavailable: $error';
  }

  @override
  String get proxiesEmpty => 'Connect to load policy groups.';

  @override
  String get proxiesPreviewOnly =>
      'Preview of the selected profile. A node picked here applies on the next connect.';

  @override
  String get proxiesMembersUnavailable =>
      'Members are known only after the profile has been updated once.';

  @override
  String get testLatency => 'Test latency';

  @override
  String get latencyTestFailed => 'Latency test failed: every node timed out.';

  @override
  String get offlineLatencyHint =>
      'Latency can be measured offline too: the core dials each node in turn without bringing up the tunnel.';

  @override
  String get nodeUnreachable => 'unreachable';

  @override
  String get menuProxyProviders => 'Proxy providers';

  @override
  String get menuRuleProviders => 'Rule providers';

  @override
  String get providersPreviewOnly =>
      'Read from the selected profile and its cached files.';

  @override
  String get providersEmpty => 'This profile declares no providers.';

  @override
  String get providersUpdateAll => 'Update all';

  @override
  String get providerNotDownloaded => 'Not downloaded yet';

  @override
  String providerNodeCount(int count) {
    return '$count nodes';
  }

  @override
  String providerRuleCount(int count) {
    return '$count rules';
  }

  @override
  String providerUpdateFailed(String name, String error) {
    return '$name: $error';
  }

  @override
  String providersUpdated(int count) {
    return 'Updated $count providers.';
  }

  @override
  String providersUpdatePartial(int done, int failed) {
    return 'Updated $done, $failed failed.';
  }

  @override
  String get providerNotUpdatable => 'Declared in the config file';

  @override
  String get profilesEmpty => 'Add a subscription to get started.';

  @override
  String profileUpdated(String time) {
    return 'Updated $time';
  }

  @override
  String profileExpires(String date) {
    return 'expires $date';
  }

  @override
  String get actionUpdate => 'Update';

  @override
  String get actionEdit => 'Edit';

  @override
  String get actionRename => 'Rename';

  @override
  String get actionDelete => 'Delete';

  @override
  String get actionCancel => 'Cancel';

  @override
  String get actionAdd => 'Add';

  @override
  String get actionSave => 'Save';

  @override
  String get actionClose => 'Close';

  @override
  String get addSubscription => 'Add subscription';

  @override
  String get subscriptionUrl => 'URL';

  @override
  String get profileName => 'Name';

  @override
  String get profileNameOptional =>
      'Optional; defaults to the subscription host';

  @override
  String get editProfile => 'Edit config';

  @override
  String get editProfileHelper =>
      'Updating from the subscription URL overwrites these edits';

  @override
  String get profileNotDownloaded =>
      'This profile has not been downloaded yet.';

  @override
  String get tabConnections => 'Connections';

  @override
  String get tabLogs => 'Logs';

  @override
  String get connectionsEmpty => 'No active connections.';

  @override
  String get closeAllConnections => 'Close all';

  @override
  String get logsEmpty => 'No logs yet.';

  @override
  String get sectionTunnel => 'Tunnel';

  @override
  String get sectionPerAppProxy => 'Per-app proxy';

  @override
  String get sectionProfiles => 'Profiles';

  @override
  String get sectionDiagnostics => 'Diagnostics';

  @override
  String get sectionAppearance => 'Appearance';

  @override
  String get tunStack => 'TUN stack';

  @override
  String get ipv6 => 'IPv6';

  @override
  String get ipv6Subtitle => 'Route IPv6 traffic through the tunnel';

  @override
  String get bypassPrivateRoutes => 'Bypass private routes';

  @override
  String get bypassPrivateRoutesSubtitle =>
      'Keep LAN traffic outside the tunnel';

  @override
  String get tunnelledApps => 'Tunnelled apps';

  @override
  String get allApps => 'All apps';

  @override
  String appsSelected(int count) {
    return '$count selected';
  }

  @override
  String get tunnelAllApps => 'Tunnel all apps';

  @override
  String get updateOnLaunch => 'Update on launch';

  @override
  String get updateOnLaunchSubtitle =>
      'Refresh subscriptions whose interval elapsed';

  @override
  String get globalOverride => 'Global override';

  @override
  String get overrideNone => 'None';

  @override
  String overrideLines(int count) {
    return '$count lines';
  }

  @override
  String get overrideHelper => 'YAML patch merged onto every profile';

  @override
  String get logLevel => 'Log level';

  @override
  String get applyToRunningTunnel => 'Apply to running tunnel';

  @override
  String get geoAssets => 'Static resources';

  @override
  String get geoAssetsSubtitle => 'GeoIP and GeoSite databases';

  @override
  String get geoAssetMissing => 'Not downloaded';

  @override
  String get geoAssetsUpdate => 'Update databases';

  @override
  String get geoAssetsUpdated => 'Databases updated.';

  @override
  String get geoAssetsRequireCore => 'Connect to update the databases.';

  @override
  String get sectionAbout => 'About';

  @override
  String get checkForUpdates => 'Check for updates';

  @override
  String currentVersion(String version) {
    return 'Version $version';
  }

  @override
  String get updateUpToDate => 'You are on the latest version.';

  @override
  String get updateAvailable => 'New version available';

  @override
  String updateAvailableBody(String version) {
    return '$version has been released. Open the download page?';
  }

  @override
  String get updateDownload => 'Download';

  @override
  String updateCheckFailed(String error) {
    return 'Update check failed: $error';
  }

  @override
  String get language => 'Language';

  @override
  String get languageSystem => 'System default';

  @override
  String get relativeNever => 'never';

  @override
  String get relativeJustNow => 'just now';

  @override
  String relativeMinutesAgo(int count) {
    return '${count}m ago';
  }

  @override
  String relativeHoursAgo(int count) {
    return '${count}h ago';
  }

  @override
  String relativeDaysAgo(int count) {
    return '${count}d ago';
  }
}
