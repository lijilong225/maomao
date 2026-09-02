import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'maomao'**
  String get appTitle;

  /// No description provided for @navHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get navHome;

  /// No description provided for @navProxies.
  ///
  /// In en, this message translates to:
  /// **'Proxies'**
  String get navProxies;

  /// No description provided for @navProfiles.
  ///
  /// In en, this message translates to:
  /// **'Profiles'**
  String get navProfiles;

  /// No description provided for @navActivity.
  ///
  /// In en, this message translates to:
  /// **'Activity'**
  String get navActivity;

  /// No description provided for @navSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get navSettings;

  /// No description provided for @titleDashboard.
  ///
  /// In en, this message translates to:
  /// **'Dashboard'**
  String get titleDashboard;

  /// No description provided for @titleProxies.
  ///
  /// In en, this message translates to:
  /// **'Proxies'**
  String get titleProxies;

  /// No description provided for @titleProfiles.
  ///
  /// In en, this message translates to:
  /// **'Profiles'**
  String get titleProfiles;

  /// No description provided for @titleActivity.
  ///
  /// In en, this message translates to:
  /// **'Activity'**
  String get titleActivity;

  /// No description provided for @titleSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get titleSettings;

  /// No description provided for @stateConnected.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get stateConnected;

  /// No description provided for @stateConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting…'**
  String get stateConnecting;

  /// No description provided for @stateDisconnected.
  ///
  /// In en, this message translates to:
  /// **'Disconnected'**
  String get stateDisconnected;

  /// No description provided for @noProfileSelected.
  ///
  /// In en, this message translates to:
  /// **'No profile selected'**
  String get noProfileSelected;

  /// No description provided for @trafficUpload.
  ///
  /// In en, this message translates to:
  /// **'Upload'**
  String get trafficUpload;

  /// No description provided for @trafficDownload.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get trafficDownload;

  /// No description provided for @sessionTotal.
  ///
  /// In en, this message translates to:
  /// **'Session total'**
  String get sessionTotal;

  /// No description provided for @activeConnections.
  ///
  /// In en, this message translates to:
  /// **'Active connections'**
  String get activeConnections;

  /// No description provided for @coreLabel.
  ///
  /// In en, this message translates to:
  /// **'Core'**
  String get coreLabel;

  /// No description provided for @coreVersion.
  ///
  /// In en, this message translates to:
  /// **'mihomo {version}'**
  String coreVersion(String version);

  /// No description provided for @loading.
  ///
  /// In en, this message translates to:
  /// **'loading…'**
  String get loading;

  /// No description provided for @unavailable.
  ///
  /// In en, this message translates to:
  /// **'unavailable'**
  String get unavailable;

  /// No description provided for @proxiesUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Unavailable: {error}'**
  String proxiesUnavailable(String error);

  /// No description provided for @proxiesEmpty.
  ///
  /// In en, this message translates to:
  /// **'Connect to load policy groups.'**
  String get proxiesEmpty;

  /// No description provided for @proxiesPreviewOnly.
  ///
  /// In en, this message translates to:
  /// **'Preview of the selected profile. Connect to switch nodes and test latency.'**
  String get proxiesPreviewOnly;

  /// No description provided for @proxiesMembersUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Members are known only after the profile has been updated once.'**
  String get proxiesMembersUnavailable;

  /// No description provided for @testLatency.
  ///
  /// In en, this message translates to:
  /// **'Test latency'**
  String get testLatency;

  /// No description provided for @latencyTestFailed.
  ///
  /// In en, this message translates to:
  /// **'Latency test failed: every node timed out.'**
  String get latencyTestFailed;

  /// No description provided for @menuProxyProviders.
  ///
  /// In en, this message translates to:
  /// **'Proxy providers'**
  String get menuProxyProviders;

  /// No description provided for @menuRuleProviders.
  ///
  /// In en, this message translates to:
  /// **'Rule providers'**
  String get menuRuleProviders;

  /// No description provided for @providersPreviewOnly.
  ///
  /// In en, this message translates to:
  /// **'Read from the selected profile and its cached files.'**
  String get providersPreviewOnly;

  /// No description provided for @providersEmpty.
  ///
  /// In en, this message translates to:
  /// **'This profile declares no providers.'**
  String get providersEmpty;

  /// No description provided for @providersUpdateAll.
  ///
  /// In en, this message translates to:
  /// **'Update all'**
  String get providersUpdateAll;

  /// No description provided for @providerNotDownloaded.
  ///
  /// In en, this message translates to:
  /// **'Not downloaded yet'**
  String get providerNotDownloaded;

  /// No description provided for @providerNodeCount.
  ///
  /// In en, this message translates to:
  /// **'{count} nodes'**
  String providerNodeCount(int count);

  /// No description provided for @providerRuleCount.
  ///
  /// In en, this message translates to:
  /// **'{count} rules'**
  String providerRuleCount(int count);

  /// No description provided for @providerUpdateFailed.
  ///
  /// In en, this message translates to:
  /// **'{name}: {error}'**
  String providerUpdateFailed(String name, String error);

  /// No description provided for @providersUpdated.
  ///
  /// In en, this message translates to:
  /// **'Updated {count} providers.'**
  String providersUpdated(int count);

  /// No description provided for @providersUpdatePartial.
  ///
  /// In en, this message translates to:
  /// **'Updated {done}, {failed} failed.'**
  String providersUpdatePartial(int done, int failed);

  /// No description provided for @providerNotUpdatable.
  ///
  /// In en, this message translates to:
  /// **'Declared in the config file'**
  String get providerNotUpdatable;

  /// No description provided for @profilesEmpty.
  ///
  /// In en, this message translates to:
  /// **'Add a subscription to get started.'**
  String get profilesEmpty;

  /// No description provided for @profileUpdated.
  ///
  /// In en, this message translates to:
  /// **'Updated {time}'**
  String profileUpdated(String time);

  /// No description provided for @profileExpires.
  ///
  /// In en, this message translates to:
  /// **'expires {date}'**
  String profileExpires(String date);

  /// No description provided for @actionUpdate.
  ///
  /// In en, this message translates to:
  /// **'Update'**
  String get actionUpdate;

  /// No description provided for @actionEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get actionEdit;

  /// No description provided for @actionDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get actionDelete;

  /// No description provided for @actionCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get actionCancel;

  /// No description provided for @actionAdd.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get actionAdd;

  /// No description provided for @actionSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get actionSave;

  /// No description provided for @actionClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get actionClose;

  /// No description provided for @addSubscription.
  ///
  /// In en, this message translates to:
  /// **'Add subscription'**
  String get addSubscription;

  /// No description provided for @subscriptionUrl.
  ///
  /// In en, this message translates to:
  /// **'URL'**
  String get subscriptionUrl;

  /// No description provided for @editProfile.
  ///
  /// In en, this message translates to:
  /// **'Edit config'**
  String get editProfile;

  /// No description provided for @editProfileHelper.
  ///
  /// In en, this message translates to:
  /// **'Updating from the subscription URL overwrites these edits'**
  String get editProfileHelper;

  /// No description provided for @profileNotDownloaded.
  ///
  /// In en, this message translates to:
  /// **'This profile has not been downloaded yet.'**
  String get profileNotDownloaded;

  /// No description provided for @tabConnections.
  ///
  /// In en, this message translates to:
  /// **'Connections'**
  String get tabConnections;

  /// No description provided for @tabLogs.
  ///
  /// In en, this message translates to:
  /// **'Logs'**
  String get tabLogs;

  /// No description provided for @connectionsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No active connections.'**
  String get connectionsEmpty;

  /// No description provided for @closeAllConnections.
  ///
  /// In en, this message translates to:
  /// **'Close all'**
  String get closeAllConnections;

  /// No description provided for @logsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No logs yet.'**
  String get logsEmpty;

  /// No description provided for @sectionTunnel.
  ///
  /// In en, this message translates to:
  /// **'Tunnel'**
  String get sectionTunnel;

  /// No description provided for @sectionPerAppProxy.
  ///
  /// In en, this message translates to:
  /// **'Per-app proxy'**
  String get sectionPerAppProxy;

  /// No description provided for @sectionProfiles.
  ///
  /// In en, this message translates to:
  /// **'Profiles'**
  String get sectionProfiles;

  /// No description provided for @sectionDiagnostics.
  ///
  /// In en, this message translates to:
  /// **'Diagnostics'**
  String get sectionDiagnostics;

  /// No description provided for @sectionAppearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get sectionAppearance;

  /// No description provided for @tunStack.
  ///
  /// In en, this message translates to:
  /// **'TUN stack'**
  String get tunStack;

  /// No description provided for @ipv6.
  ///
  /// In en, this message translates to:
  /// **'IPv6'**
  String get ipv6;

  /// No description provided for @ipv6Subtitle.
  ///
  /// In en, this message translates to:
  /// **'Route IPv6 traffic through the tunnel'**
  String get ipv6Subtitle;

  /// No description provided for @bypassPrivateRoutes.
  ///
  /// In en, this message translates to:
  /// **'Bypass private routes'**
  String get bypassPrivateRoutes;

  /// No description provided for @bypassPrivateRoutesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Keep LAN traffic outside the tunnel'**
  String get bypassPrivateRoutesSubtitle;

  /// No description provided for @tunnelledApps.
  ///
  /// In en, this message translates to:
  /// **'Tunnelled apps'**
  String get tunnelledApps;

  /// No description provided for @allApps.
  ///
  /// In en, this message translates to:
  /// **'All apps'**
  String get allApps;

  /// No description provided for @appsSelected.
  ///
  /// In en, this message translates to:
  /// **'{count} selected'**
  String appsSelected(int count);

  /// No description provided for @tunnelAllApps.
  ///
  /// In en, this message translates to:
  /// **'Tunnel all apps'**
  String get tunnelAllApps;

  /// No description provided for @updateOnLaunch.
  ///
  /// In en, this message translates to:
  /// **'Update on launch'**
  String get updateOnLaunch;

  /// No description provided for @updateOnLaunchSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Refresh subscriptions whose interval elapsed'**
  String get updateOnLaunchSubtitle;

  /// No description provided for @globalOverride.
  ///
  /// In en, this message translates to:
  /// **'Global override'**
  String get globalOverride;

  /// No description provided for @overrideNone.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get overrideNone;

  /// No description provided for @overrideLines.
  ///
  /// In en, this message translates to:
  /// **'{count} lines'**
  String overrideLines(int count);

  /// No description provided for @overrideHelper.
  ///
  /// In en, this message translates to:
  /// **'YAML patch merged onto every profile'**
  String get overrideHelper;

  /// No description provided for @logLevel.
  ///
  /// In en, this message translates to:
  /// **'Log level'**
  String get logLevel;

  /// No description provided for @applyToRunningTunnel.
  ///
  /// In en, this message translates to:
  /// **'Apply to running tunnel'**
  String get applyToRunningTunnel;

  /// No description provided for @geoAssets.
  ///
  /// In en, this message translates to:
  /// **'Static resources'**
  String get geoAssets;

  /// No description provided for @geoAssetsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'GeoIP and GeoSite databases'**
  String get geoAssetsSubtitle;

  /// No description provided for @geoAssetMissing.
  ///
  /// In en, this message translates to:
  /// **'Not downloaded'**
  String get geoAssetMissing;

  /// No description provided for @geoAssetsUpdate.
  ///
  /// In en, this message translates to:
  /// **'Update databases'**
  String get geoAssetsUpdate;

  /// No description provided for @geoAssetsUpdated.
  ///
  /// In en, this message translates to:
  /// **'Databases updated.'**
  String get geoAssetsUpdated;

  /// No description provided for @geoAssetsRequireCore.
  ///
  /// In en, this message translates to:
  /// **'Connect to update the databases.'**
  String get geoAssetsRequireCore;

  /// No description provided for @sectionAbout.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get sectionAbout;

  /// No description provided for @checkForUpdates.
  ///
  /// In en, this message translates to:
  /// **'Check for updates'**
  String get checkForUpdates;

  /// No description provided for @currentVersion.
  ///
  /// In en, this message translates to:
  /// **'Version {version}'**
  String currentVersion(String version);

  /// No description provided for @updateUpToDate.
  ///
  /// In en, this message translates to:
  /// **'You are on the latest version.'**
  String get updateUpToDate;

  /// No description provided for @updateAvailable.
  ///
  /// In en, this message translates to:
  /// **'New version available'**
  String get updateAvailable;

  /// No description provided for @updateAvailableBody.
  ///
  /// In en, this message translates to:
  /// **'{version} has been released. Open the download page?'**
  String updateAvailableBody(String version);

  /// No description provided for @updateDownload.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get updateDownload;

  /// No description provided for @updateCheckFailed.
  ///
  /// In en, this message translates to:
  /// **'Update check failed: {error}'**
  String updateCheckFailed(String error);

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @languageSystem.
  ///
  /// In en, this message translates to:
  /// **'System default'**
  String get languageSystem;

  /// No description provided for @relativeNever.
  ///
  /// In en, this message translates to:
  /// **'never'**
  String get relativeNever;

  /// No description provided for @relativeJustNow.
  ///
  /// In en, this message translates to:
  /// **'just now'**
  String get relativeJustNow;

  /// No description provided for @relativeMinutesAgo.
  ///
  /// In en, this message translates to:
  /// **'{count}m ago'**
  String relativeMinutesAgo(int count);

  /// No description provided for @relativeHoursAgo.
  ///
  /// In en, this message translates to:
  /// **'{count}h ago'**
  String relativeHoursAgo(int count);

  /// No description provided for @relativeDaysAgo.
  ///
  /// In en, this message translates to:
  /// **'{count}d ago'**
  String relativeDaysAgo(int count);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
