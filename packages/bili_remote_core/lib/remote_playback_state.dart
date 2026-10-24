import 'dart:io';

/// Only private/link-local endpoints may receive the receiver's pairing credential.
void validateRemoteAddress(Uri address) {
  final ip = InternetAddress.tryParse(address.host);
  if (address.scheme != 'http' || address.userInfo.isNotEmpty || ip == null) {
    throw const FormatException('请输入电视的局域网 IP 和端口');
  }
  final bytes = ip.rawAddress;
  final local =
      ip.isLoopback ||
      (bytes.length == 4
          ? bytes[0] == 10 ||
                (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31) ||
                (bytes[0] == 192 && bytes[1] == 168) ||
                (bytes[0] == 169 && bytes[1] == 254)
          : (bytes[0] & 0xfe) == 0xfc ||
                (bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80));
  if (!local) throw const FormatException('遥控只允许连接局域网电视');
}

class RemotePlaybackState {
  final Map<String, dynamic> data;
  const RemotePlaybackState([this.data = const {}]);
  String get playbackId => data['playbackId'] as String? ?? '';
  int get revision => (data['revision'] as num?)?.toInt() ?? 0;
  String get status => data['state'] as String? ?? 'STOPPED';
  String get title => data['title'] as String? ?? '';
  int get aid => (data['aid'] as num?)?.toInt() ?? 0;
  int get cid => (data['cid'] as num?)?.toInt() ?? 0;
  int? get epid => _currentEpisodeNumber('epid');
  int? get seasonId => _currentEpisodeNumber('seasonId');

  int? _currentEpisodeNumber(String key) {
    final direct = (data[key] as num?)?.toInt();
    if (direct != null && direct > 0) return direct;
    // Older receivers include episode identity only in the current queue item.
    for (final item in data['queue'] as List? ?? const []) {
      if (item['aid'] == aid && item['cid'] == cid) {
        final value = (item[key] as num?)?.toInt();
        return value != null && value > 0 ? value : null;
      }
    }
    return null;
  }

  int get positionMs =>
      ((data['positionMs'] as num?)?.toInt() ?? 0).clamp(0, 2147483647);
  int get durationMs =>
      ((data['durationMs'] as num?)?.toInt() ?? 0).clamp(0, 2147483647);
  int get volume => ((data['volume'] as num?)?.toInt() ?? 100).clamp(0, 100);
  String get volumeMode => data['volumeMode'] as String? ?? 'unavailable';
  bool get danmakuEnabled => data['danmakuEnabled'] == true;
  bool get supportsDanmakuSettings => data['danmakuSettings'] is Map;
  Map get _danmakuSettings => data['danmakuSettings'] as Map? ?? const {};
  double get danmakuScale =>
      (_danmakuSettings['scale'] as num?)?.toDouble() ?? 1.5;
  double get danmakuArea =>
      (_danmakuSettings['area'] as num?)?.toDouble() ?? 0.5;
  double get danmakuOpacity =>
      (_danmakuSettings['opacity'] as num?)?.toDouble() ?? 0.5;
  double get danmakuDensity =>
      (_danmakuSettings['density'] as num?)?.toDouble() ?? 1;
  Set<String> get danmakuTypes =>
      Set<String>.from(_danmakuSettings['types'] as List? ?? const []);
  double get speed => (data['speed'] as num?)?.toDouble() ?? 1;
  int get qualityId => (data['qualityId'] as num?)?.toInt() ?? 0;
  String? get error => data['error'] as String?;
  String? get sponsorSkipMode => data['sponsorSkipMode'] as String?;
  String? get sponsorSkipNotice => data['sponsorSkipNotice'] as String?;
  Map? get _sponsorSegment => data['sponsorSegment'] as Map?;
  String? get sponsorSegmentId => _sponsorSegment?['id'] as String?;
  String? get sponsorCategory => _sponsorSegment?['category'] as String?;
  int get sponsorStartMs => (_sponsorSegment?['startMs'] as num?)?.toInt() ?? 0;
  int get sponsorEndMs => (_sponsorSegment?['endMs'] as num?)?.toInt() ?? 0;
  bool get hasSponsorPrompt =>
      status != 'TRANSITIONING' &&
      sponsorSegmentId != null &&
      positionMs >= sponsorStartMs &&
      positionMs < sponsorEndMs;

  Map<String, String> get qualities =>
      (data['qualities'] as Map?)?.map(
        (key, value) => MapEntry('$key', '$value'),
      ) ??
      {};
  List<Map<String, dynamic>> get queue => [
    for (final item in data['queue'] as List? ?? const [])
      Map<String, dynamic>.from(item as Map),
  ];
}
