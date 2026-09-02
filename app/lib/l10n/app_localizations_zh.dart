// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => 'maomao';

  @override
  String get navHome => '首页';

  @override
  String get navProxies => '代理';

  @override
  String get navProfiles => '配置';

  @override
  String get navActivity => '活动';

  @override
  String get navSettings => '设置';

  @override
  String get titleDashboard => '概览';

  @override
  String get titleProxies => '代理';

  @override
  String get titleProfiles => '配置';

  @override
  String get titleActivity => '活动';

  @override
  String get titleSettings => '设置';

  @override
  String get stateConnected => '已连接';

  @override
  String get stateConnecting => '正在连接…';

  @override
  String get stateDisconnected => '未连接';

  @override
  String get noProfileSelected => '未选择配置';

  @override
  String get trafficUpload => '上传';

  @override
  String get trafficDownload => '下载';

  @override
  String get sessionTotal => '本次累计';

  @override
  String get activeConnections => '活动连接';

  @override
  String get coreLabel => '内核';

  @override
  String coreVersion(String version) {
    return 'mihomo $version';
  }

  @override
  String get loading => '加载中…';

  @override
  String get unavailable => '不可用';

  @override
  String proxiesUnavailable(String error) {
    return '不可用：$error';
  }

  @override
  String get proxiesEmpty => '连接后加载策略组。';

  @override
  String get proxiesPreviewOnly => '当前配置的预览。连接后可切换节点并测速。';

  @override
  String get proxiesMembersUnavailable => '成员需在配置更新一次后才可查看。';

  @override
  String get testLatency => '测试延迟';

  @override
  String get latencyTestFailed => '测速失败：所有节点均超时。';

  @override
  String get menuProxyProviders => '代理集合';

  @override
  String get menuRuleProviders => '规则集合';

  @override
  String get providersPreviewOnly => '当前配置的预览。连接后可更新集合。';

  @override
  String get providersEmpty => '当前配置未声明集合。';

  @override
  String get providersUpdateAll => '全部更新';

  @override
  String get providerNotDownloaded => '尚未下载';

  @override
  String providerNodeCount(int count) {
    return '$count 个节点';
  }

  @override
  String providerRuleCount(int count) {
    return '$count 条规则';
  }

  @override
  String providerUpdateFailed(String name, String error) {
    return '$name：$error';
  }

  @override
  String providersUpdated(int count) {
    return '已更新 $count 个集合。';
  }

  @override
  String providersUpdatePartial(int done, int failed) {
    return '已更新 $done 个，$failed 个失败。';
  }

  @override
  String get providerNotUpdatable => '在配置文件中声明';

  @override
  String get profilesEmpty => '添加订阅后开始使用。';

  @override
  String profileUpdated(String time) {
    return '更新于 $time';
  }

  @override
  String profileExpires(String date) {
    return '$date 到期';
  }

  @override
  String get actionUpdate => '更新';

  @override
  String get actionEdit => '编辑';

  @override
  String get actionDelete => '删除';

  @override
  String get actionCancel => '取消';

  @override
  String get actionAdd => '添加';

  @override
  String get actionSave => '保存';

  @override
  String get actionClose => '关闭';

  @override
  String get addSubscription => '添加订阅';

  @override
  String get subscriptionUrl => '链接';

  @override
  String get editProfile => '编辑配置';

  @override
  String get editProfileHelper => '从订阅链接更新会覆盖这里的修改';

  @override
  String get profileNotDownloaded => '该配置尚未下载。';

  @override
  String get tabConnections => '连接';

  @override
  String get tabLogs => '日志';

  @override
  String get connectionsEmpty => '暂无活动连接。';

  @override
  String get closeAllConnections => '全部关闭';

  @override
  String get logsEmpty => '暂无日志。';

  @override
  String get sectionTunnel => '隧道';

  @override
  String get sectionPerAppProxy => '分应用代理';

  @override
  String get sectionProfiles => '配置';

  @override
  String get sectionDiagnostics => '诊断';

  @override
  String get sectionAppearance => '外观';

  @override
  String get tunStack => 'TUN 栈';

  @override
  String get ipv6 => 'IPv6';

  @override
  String get ipv6Subtitle => '让 IPv6 流量经过隧道';

  @override
  String get bypassPrivateRoutes => '绕过内网地址';

  @override
  String get bypassPrivateRoutesSubtitle => '局域网流量不进入隧道';

  @override
  String get tunnelledApps => '代理的应用';

  @override
  String get allApps => '全部应用';

  @override
  String appsSelected(int count) {
    return '已选 $count 个';
  }

  @override
  String get tunnelAllApps => '代理全部应用';

  @override
  String get updateOnLaunch => '启动时更新';

  @override
  String get updateOnLaunchSubtitle => '刷新已到更新间隔的订阅';

  @override
  String get globalOverride => '全局覆写';

  @override
  String get overrideNone => '无';

  @override
  String overrideLines(int count) {
    return '$count 行';
  }

  @override
  String get overrideHelper => '合并到每个配置的 YAML 补丁';

  @override
  String get logLevel => '日志级别';

  @override
  String get applyToRunningTunnel => '应用到运行中的隧道';

  @override
  String get geoAssets => '静态资源';

  @override
  String get geoAssetsSubtitle => 'GeoIP 与 GeoSite 数据库';

  @override
  String get geoAssetMissing => '尚未下载';

  @override
  String get geoAssetsUpdate => '更新数据库';

  @override
  String get geoAssetsUpdated => '数据库已更新。';

  @override
  String get geoAssetsRequireCore => '连接后可更新数据库。';

  @override
  String get sectionAbout => '关于';

  @override
  String get checkForUpdates => '检测新版';

  @override
  String currentVersion(String version) {
    return '当前版本 $version';
  }

  @override
  String get updateUpToDate => '已是最新版本。';

  @override
  String get updateAvailable => '发现新版本';

  @override
  String updateAvailableBody(String version) {
    return '$version 已发布，是否打开下载页面？';
  }

  @override
  String get updateDownload => '下载';

  @override
  String updateCheckFailed(String error) {
    return '检测失败：$error';
  }

  @override
  String get language => '语言';

  @override
  String get languageSystem => '跟随系统';

  @override
  String get relativeNever => '从未';

  @override
  String get relativeJustNow => '刚刚';

  @override
  String relativeMinutesAgo(int count) {
    return '$count 分钟前';
  }

  @override
  String relativeHoursAgo(int count) {
    return '$count 小时前';
  }

  @override
  String relativeDaysAgo(int count) {
    return '$count 天前';
  }
}
