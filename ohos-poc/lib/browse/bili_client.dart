// Adapted from PiliPlus HTTP endpoints and WBI signing (GPL-3.0).
// Browsing never requests stream URLs or sends account cookies to the TV.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:hive_ce/hive.dart';

Map<String, dynamic> _map(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
int _number(dynamic value) =>
    value is num ? value.toInt() : int.tryParse('$value') ?? 0;
String _text(dynamic value) => value is String ? value : '';
// Search returns a clock string; recommendation and detail return seconds.
int _videoDurationSeconds(dynamic value) {
  if (value is num) return value.toInt().clamp(0, 2147483647);
  if (value is! String) return 0;
  final parts = value.trim().split(':');
  if (parts.length > 3) return 0;
  var seconds = 0;
  for (final part in parts) {
    final number = int.tryParse(part);
    if (number == null || number < 0) return 0;
    seconds = seconds * 60 + number;
  }
  return seconds;
}

String _image(dynamic value) {
  final url = _text(value);
  return url.startsWith('//')
      ? 'https:$url'
      : url.replaceFirst('http://', 'https://');
}

String _plainTitle(dynamic value) => _text(value)
    .replaceAll(RegExp('<[^>]*>'), '')
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'");

class BiliRequestException implements Exception {
  const BiliRequestException(this.message);
  final String message;
  @override
  String toString() => message;
}

class BiliVideo {
  const BiliVideo({
    required this.aid,
    required this.bvid,
    required this.title,
    required this.cover,
    required this.author,
    this.duration = 0,
    this.views = 0,
    this.danmaku = 0,
    this.historyCid = 0,
    this.historyPositionMs,
  });
  final int aid;
  final String bvid;
  final String title;
  final String cover;
  final String author;
  final int duration;
  final int views;
  final int danmaku;
  final int historyCid;
  // null means no known history; zero explicitly restarts a completed video.
  final int? historyPositionMs;

  factory BiliVideo.fromVideo(Map<String, dynamic> data) => BiliVideo(
    aid: _number(data['aid'] ?? data['id']),
    bvid: _text(data['bvid']),
    title: _plainTitle(data['title']),
    cover: _image(data['pic'] ?? data['cover']),
    author: _text(
      data['author'] ?? _map(data['owner'] ?? data['upper'])['name'],
    ),
    duration: _videoDurationSeconds(data['duration']),
    views: _number(
      data['play'] ??
          _map(data['stat'] ?? data['cnt_info'])['view'] ??
          _map(data['cnt_info'])['play'],
    ),
    danmaku: _number(data['video_review'] ?? _map(data['stat'])['danmaku']),
  );

  factory BiliVideo.fromHistory(Map<String, dynamic> data) {
    final history = _map(data['history']);
    final progress = _number(data['progress']);
    return BiliVideo(
      aid: _number(history['oid']),
      bvid: _text(history['bvid']),
      title: _plainTitle(data['title']),
      cover: _image(data['cover']),
      author: _text(data['author_name']),
      duration: _number(data['duration']),
      historyCid: _number(history['cid']),
      historyPositionMs: progress < 0 ? 0 : progress * 1000,
    );
  }
}

class BiliPart {
  const BiliPart({
    required this.cid,
    required this.page,
    required this.title,
    required this.duration,
  });
  final int cid;
  final int page;
  final String title;
  final int duration;
}

class BiliVideoDetails {
  const BiliVideoDetails({
    required this.video,
    required this.description,
    required this.parts,
    required this.resumeCid,
    required this.resumePositionMs,
  });
  final BiliVideo video;
  final String description;
  final List<BiliPart> parts;
  final int resumeCid;
  final int resumePositionMs;
}

class BiliVideoPage {
  const BiliVideoPage(
    this.items, {
    required this.hasMore,
    this.historyMax = 0,
    this.historyViewAt = 0,
  });
  final List<BiliVideo> items;
  final bool hasMore;
  final int historyMax;
  final int historyViewAt;
}

class BiliFavoriteFolder {
  const BiliFavoriteFolder(this.id, this.title, this.count);
  final int id;
  final String title;
  final int count;
}

class BiliAccount {
  const BiliAccount(
    this.mid,
    this.name,
    this.face, {
    this.coins = 0,
    this.level = 0,
    this.currentExperience = 0,
    this.nextExperience = 0,
  });
  final int mid;
  final String name;
  final String face;
  final int coins;
  final int level;
  final int currentExperience;
  final int nextExperience;
}

class BiliQrCode {
  const BiliQrCode(this.key, this.url);
  final String key;
  final String url;
}

class BiliClient {
  BiliClient() {
    _http.connectionTimeout = const Duration(seconds: 12);
    _http.idleTimeout = const Duration(seconds: 15);
    _http.maxConnectionsPerHost = 4;
  }
  final HttpClient _http = HttpClient();
  final Map<String, String> _cookies = {};
  Box<dynamic>? _accountStorage;
  Future<void>? _initialization;
  Future<String>? _wbiKeyRequest;
  String? _wbiKey;
  DateTime? _wbiKeyTime;
  bool _closed = false;
  int _accountGeneration = 0;
  BiliAccount? account;
  bool get loggedIn => account != null;

  Future<void> initialize() async {
    final initialization = _initialization ??= _initialize();
    try {
      await initialization;
    } catch (_) {
      if (identical(_initialization, initialization)) _initialization = null;
      rethrow;
    }
  }

  Future<void> _initialize() async {
    _accountStorage = await Hive.openBox<dynamic>('bili_browser_account');
    if (_closed) return;
    final stored = _accountStorage!.get('cookies');
    if (stored is Map) {
      for (final entry in stored.entries) {
        if (entry.key is String && entry.value is String) {
          _cookies[entry.key as String] = entry.value as String;
        }
      }
    }
    await refreshAccount();
  }

  Future<BiliAccount?> refreshAccount() async {
    final generation = _accountGeneration;
    final response = await _request(
      '/x/web-interface/nav',
      requireSuccess: false,
    );
    if (_closed || generation != _accountGeneration) return account;
    final data = _map(response['data']);
    account = data['isLogin'] == true
        ? BiliAccount(
            _number(data['mid']),
            _text(data['uname']),
            _image(data['face']),
            coins: _number(data['money']),
            level: _number(_map(data['level_info'])['current_level']),
            currentExperience: _number(_map(data['level_info'])['current_exp']),
            nextExperience: _number(_map(data['level_info'])['next_exp']),
          )
        : null;
    _rememberWbiKey(data);
    return account;
  }

  // Credential changes invalidate in-flight login/profile results.
  Future<void> logout() async {
    _accountGeneration++;
    account = null;
    _cookies.clear();
    _wbiKey = null;
    _wbiKeyRequest = null;
    await _accountStorage?.delete('cookies');
  }

  Future<Map<String, dynamic>> _request(
    String path, {
    String host = 'api.bilibili.com',
    Map<String, Object> parameters = const {},
    bool requireSuccess = true,
    Map<String, String>? responseCookies,
  }) async {
    if (_closed) throw const BiliRequestException('页面已关闭');
    final uri = Uri.https(host, path, {
      for (final entry in parameters.entries) entry.key: '${entry.value}',
    });
    try {
      final request = await _http
          .getUrl(uri)
          .timeout(const Duration(seconds: 15));
      request.followRedirects = false;
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'Mozilla/5.0 (Linux; Android 12) AppleWebKit/537.36 Chrome/124.0.0.0 Mobile Safari/537.36',
      );
      request.headers.set(
        HttpHeaders.refererHeader,
        'https://www.bilibili.com/',
      );
      if (_cookies.isNotEmpty) {
        request.headers.set(
          HttpHeaders.cookieHeader,
          _cookies.entries
              .map((entry) => '${entry.key}=${entry.value}')
              .join('; '),
        );
      }
      final response = await request.close().timeout(
        const Duration(seconds: 15),
      );
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        throw BiliRequestException('请求失败（HTTP ${response.statusCode}），请稍后重试');
      }
      if (responseCookies != null) {
        for (final cookie in response.cookies) {
          responseCookies[cookie.name] = cookie.value;
        }
      }
      final body = await utf8.decoder
          .bind(response)
          .join()
          .timeout(const Duration(seconds: 20));
      final result = _map(jsonDecode(body));
      if (requireSuccess && _number(result['code']) != 0) {
        final code = _number(result['code']);
        throw BiliRequestException(switch (code) {
          -101 => '请先登录 B站账号',
          -352 || -412 => 'B站暂时限制了请求，请稍后重试',
          _ =>
            _text(result['message']).isNotEmpty
                ? _text(result['message'])
                : 'B站暂未返回可用数据（$code）',
        });
      }
      return result;
    } on TimeoutException {
      throw const BiliRequestException('网络请求超时，请检查网络后重试');
    } on SocketException {
      throw const BiliRequestException('无法连接 B站，请检查网络');
    } on FormatException {
      throw const BiliRequestException('B站返回的数据无法读取，请稍后重试');
    } on HttpException {
      throw const BiliRequestException('网络连接中断，请重试');
    }
  }

  void _rememberWbiKey(Map<String, dynamic> data) {
    final images = _map(data['wbi_img']);
    String filename(dynamic value) {
      final uri = Uri.tryParse(_text(value));
      if (uri == null || uri.pathSegments.isEmpty) return '';
      return uri.pathSegments.last.split('.').first;
    }

    final source = filename(images['img_url']) + filename(images['sub_url']);
    if (source.length < 64) return;
    // Same 32-character permutation as apps/mobile/lib/utils/wbi_sign.dart.
    const indices = [
      46,
      47,
      18,
      2,
      53,
      8,
      23,
      32,
      15,
      50,
      10,
      31,
      58,
      3,
      45,
      35,
      27,
      43,
      5,
      49,
      33,
      9,
      42,
      19,
      29,
      28,
      14,
      39,
      12,
      38,
      41,
      13,
    ];
    _wbiKey = String.fromCharCodes(indices.map(source.codeUnitAt));
    _wbiKeyTime = DateTime.now();
  }

  Future<String> _getWbiKey() async {
    if (_wbiKey != null &&
        _wbiKeyTime != null &&
        DateTime.now().difference(_wbiKeyTime!) < const Duration(hours: 6)) {
      return _wbiKey!;
    }
    final pending = _wbiKeyRequest;
    if (pending != null) return pending;
    final request = () async {
      final response = await _request(
        '/x/web-interface/nav',
        requireSuccess: false,
      );
      _rememberWbiKey(_map(response['data']));
      if (_wbiKey == null) throw const BiliRequestException('暂时无法获取视频请求签名，请重试');
      return _wbiKey!;
    }();
    _wbiKeyRequest = request;
    try {
      return await request;
    } finally {
      _wbiKeyRequest = null;
    }
  }

  Future<Map<String, Object>> _signed(Map<String, Object> parameters) async {
    final key = await _getWbiKey();
    final values = <String, Object>{
      ...parameters,
      'wts': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    };
    final names = values.keys.toList()..sort();
    final filter = RegExp(r"[!\'\(\)\*]");
    final query = names
        .map(
          (name) =>
              '${Uri.encodeComponent(name)}='
              '${Uri.encodeComponent('${values[name]}'.replaceAll(filter, ''))}',
        )
        .join('&');
    values['w_rid'] = md5.convert(utf8.encode(query + key)).toString();
    return values;
  }

  Future<BiliVideoPage> recommended(int page) async {
    final response = await _request(
      '/x/web-interface/wbi/index/top/feed/rcmd',
      parameters: await _signed({
        'version': 1,
        'feed_version': 'V8',
        'homepage_ver': 1,
        'ps': 20,
        'fresh_idx': page,
        'brush': page,
        'fresh_type': 4,
      }),
    );
    final raw = _map(response['data'])['item'] as List? ?? const [];
    final videos = <BiliVideo>[];
    for (final value in raw) {
      final item = _map(value);
      if (item['goto'] == 'av' && item['ad_info'] == null) {
        final video = BiliVideo.fromVideo(item);
        if (video.aid > 0) videos.add(video);
      }
    }
    return BiliVideoPage(videos, hasMore: raw.isNotEmpty);
  }

  Future<BiliVideoPage> popular(int page) async {
    final response = await _request(
      '/x/web-interface/popular',
      parameters: {'pn': page, 'ps': 20},
    );
    final data = _map(response['data']);
    final items = <BiliVideo>[];
    for (final raw in data['list'] as List? ?? const []) {
      final item = _map(raw);
      if (item['ad_info'] != null) continue;
      final video = BiliVideo.fromVideo(item);
      if (video.aid > 0) items.add(video);
    }
    return BiliVideoPage(
      items,
      hasMore: data['no_more'] != true && items.isNotEmpty,
    );
  }

  Future<List<String>> trendingSearches() async {
    final response = await _request(
      '/x/v2/search/trending/ranking',
      parameters: {'limit': 20},
    );
    final keywords = <String>[];
    for (final raw in _map(response['data'])['list'] as List? ?? const []) {
      final keyword = _text(_map(raw)['keyword']).trim();
      if (keyword.isNotEmpty) keywords.add(keyword);
    }
    return keywords;
  }

  List<String> get searchHistory {
    final stored = _accountStorage?.get('search_history');
    return stored is List ? stored.whereType<String>().toList() : const [];
  }

  Future<void> rememberSearch(String keyword) async {
    final history = <String>[keyword];
    for (final previous in searchHistory) {
      if (previous != keyword && history.length < 30) history.add(previous);
    }
    await _accountStorage?.put('search_history', history);
  }

  Future<void> clearSearchHistory() async {
    await _accountStorage?.delete('search_history');
  }

  Future<void> _ensureAnonymousCookie() async {
    if (_cookies.containsKey('buvid3')) return;
    final response = await _request('/x/frontend/finger/spi');
    final buvid = _text(_map(response['data'])['b_3']);
    if (buvid.isNotEmpty) _cookies['buvid3'] = buvid;
  }

  Future<BiliVideoPage> search(String keyword, int page) async {
    await _ensureAnonymousCookie();
    final response = await _request(
      '/x/web-interface/wbi/search/type',
      parameters: await _signed({
        'search_type': 'video',
        'keyword': keyword,
        'page': page,
        'page_size': 20,
        'platform': 'pc',
        'web_location': 1430654,
      }),
    );
    final data = _map(response['data']);
    if (data['v_voucher'] != null) {
      throw const BiliRequestException('B站暂时要求安全验证，请稍后重试');
    }
    final videos = <BiliVideo>[];
    for (final raw in data['result'] as List? ?? const []) {
      final video = BiliVideo.fromVideo(_map(raw));
      if (video.aid > 0) videos.add(video);
    }
    return BiliVideoPage(videos, hasMore: page < _number(data['numPages']));
  }

  Future<BiliVideoPage> history({int max = 0, int viewAt = 0}) async {
    _requireAccount();
    final response = await _request(
      '/x/web-interface/history/cursor',
      parameters: {'type': 'archive', 'ps': 20, 'max': max, 'view_at': viewAt},
    );
    final data = _map(response['data']);
    final raw = data['list'] as List? ?? const [];
    final videos = <BiliVideo>[];
    for (final value in raw) {
      final item = _map(value);
      if (_map(item['history'])['business'] != 'archive') continue;
      final video = BiliVideo.fromHistory(item);
      if (video.aid > 0) videos.add(video);
    }
    final cursor = _map(data['cursor']);
    final nextMax = _number(cursor['max']);
    final nextViewAt = _number(cursor['view_at']);
    return BiliVideoPage(
      videos,
      hasMore: raw.isNotEmpty && (nextMax != max || nextViewAt != viewAt),
      historyMax: nextMax,
      historyViewAt: nextViewAt,
    );
  }

  Future<List<BiliFavoriteFolder>> favoriteFolders() async {
    _requireAccount();
    final response = await _request(
      '/x/v3/fav/folder/created/list-all',
      parameters: {'up_mid': account!.mid, 'type': 2},
    );
    final folders = <BiliFavoriteFolder>[];
    for (final raw in _map(response['data'])['list'] as List? ?? const []) {
      final item = _map(raw);
      folders.add(
        BiliFavoriteFolder(
          _number(item['id']),
          _text(item['title']),
          _number(item['media_count']),
        ),
      );
    }
    return folders;
  }

  Future<BiliVideoPage> favorites(int folderId, int page) async {
    _requireAccount();
    final response = await _request(
      '/x/v3/fav/resource/list',
      parameters: {
        'media_id': folderId,
        'pn': page,
        'ps': 20,
        'order': 'mtime',
        'type': 0,
        'tid': 0,
        'platform': 'web',
      },
    );
    final data = _map(response['data']);
    final videos = <BiliVideo>[];
    for (final raw in data['medias'] as List? ?? const []) {
      final item = _map(raw);
      // Audio, articles and deleted/private resources cannot be sent as UGC.
      if (_number(item['type']) != 2 || (_number(item['attr']) & 1) != 0) {
        continue;
      }
      final video = BiliVideo.fromVideo(item);
      if (video.aid > 0) videos.add(video);
    }
    return BiliVideoPage(
      videos,
      hasMore: data['has_more'] == true || data['has_more'] == 1,
    );
  }

  Future<BiliVideoDetails> videoDetails(BiliVideo selected) async {
    final response = await _request(
      '/x/web-interface/view',
      parameters: {'aid': selected.aid},
    );
    final data = _map(response['data']);
    final parts = <BiliPart>[];
    for (final raw in data['pages'] as List? ?? const []) {
      final item = _map(raw);
      final cid = _number(item['cid']);
      if (cid > 0) {
        parts.add(
          BiliPart(
            cid: cid,
            page: _number(item['page']),
            title: _text(item['part']),
            duration: _number(item['duration']),
          ),
        );
      }
    }
    if (parts.isEmpty) throw const BiliRequestException('这个视频暂时没有可播放的分 P');
    var resumeCid = selected.historyCid;
    var position = selected.historyPositionMs ?? 0;
    if (selected.historyPositionMs == null && loggedIn) {
      try {
        final playback = await _request(
          '/x/player/wbi/v2',
          parameters: await _signed({
            'aid': selected.aid,
            'cid': parts.first.cid,
          }),
        );
        final progress = _map(playback['data']);
        resumeCid = _number(progress['last_play_cid']);
        position = _number(
          progress['last_play_time'],
        ); // API returns milliseconds.
      } on BiliRequestException {
        // Optional history failure must not block selecting a video for TV.
      }
    }
    if (!parts.any((part) => part.cid == resumeCid)) {
      resumeCid = parts.first.cid;
      position = 0;
    }
    return BiliVideoDetails(
      video: BiliVideo.fromVideo(data),
      description: _text(data['desc']),
      parts: parts,
      resumeCid: resumeCid,
      resumePositionMs: position.clamp(0, 0x7fffffff),
    );
  }

  Future<BiliQrCode> createQrCode() async {
    final response = await _request(
      '/x/passport-login/web/qrcode/generate',
      host: 'passport.bilibili.com',
    );
    final data = _map(response['data']);
    final key = _text(data['qrcode_key']);
    final url = _text(data['url']);
    if (key.isEmpty || url.isEmpty) {
      throw const BiliRequestException('暂时无法生成登录二维码');
    }
    return BiliQrCode(key, url);
  }

  // Returns official status: 86101 waiting, 86090 scanned, 86038 expired, 0 done.
  Future<int> pollQrCode(
    String key, {
    required bool Function() isActive,
  }) async {
    final generation = _accountGeneration;
    final cookies = <String, String>{};
    final response = await _request(
      '/x/passport-login/web/qrcode/poll',
      host: 'passport.bilibili.com',
      parameters: {'qrcode_key': key},
      responseCookies: cookies,
    );
    final code = _number(_map(response['data'])['code']);
    if (code == 0 &&
        !_closed &&
        isActive() &&
        generation == _accountGeneration) {
      if (!cookies.containsKey('SESSDATA')) {
        throw const BiliRequestException('登录凭据未返回，请重新扫码');
      }
      _cookies.addAll(cookies);
      await _accountStorage!.put('cookies', Map<String, String>.from(_cookies));
      await refreshAccount();
      if (account == null) throw const BiliRequestException('登录未完成，请重新扫码');
    }
    return code;
  }

  void _requireAccount() {
    if (!loggedIn) throw const BiliRequestException('请先登录 B站账号');
  }

  void dispose() {
    _closed = true;
    _accountGeneration++;
    _http.close(force: true);
    // Hive manages the shared box; closing a page must not close another view's box.
  }
}
