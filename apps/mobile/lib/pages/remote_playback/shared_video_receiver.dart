import 'dart:async';
import 'dart:io';

import 'package:PiliPlus/pages/remote_playback/view.dart';
import 'package:PiliPlus/services/remote_playback/remote_playback_controller.dart';
import 'package:PiliPlus/utils/id_utils.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

bool _isBilibiliLink(Uri uri) =>
    (uri.scheme == 'https' || uri.scheme == 'http') &&
    uri.userInfo.isEmpty &&
    (!uri.hasPort || uri.port == 80 || uri.port == 443) &&
    (uri.host == 'b23.tv' ||
        uri.host == 'bilibili.com' ||
        uri.host.endsWith('.bilibili.com'));

/// Extracts identifiers locally. Only b23.tv needs an anonymous redirect request.
Future<Map<String, dynamic>> parseSharedBilibiliVideo(
  String text, {
  Future<Uri> Function(Uri)? expandShortLink,
}) async {
  Uri? uri;
  for (final match in RegExp(r'https?://[^\s<>"“”]+').allMatches(text)) {
    final candidate = Uri.tryParse(
      match.group(0)!.replaceFirst(RegExp(r'[)\]}>，。！？、；”’]+$'), ''),
    );
    if (candidate != null && _isBilibiliLink(candidate)) {
      uri = candidate;
      break;
    }
  }
  if (uri == null) {
    final identity = text.trim();
    if (IdUtils.bvRegexExact.hasMatch(identity) ||
        IdUtils.avRegexExact.hasMatch(identity)) {
      uri = Uri.https('www.bilibili.com', '/video/$identity');
    } else {
      throw const FormatException('请分享 B 站视频、番剧链接或 BV/AV 编号');
    }
  }
  if (uri.host == 'b23.tv') {
    uri = await (expandShortLink ?? _expandBilibiliShortLink)(uri);
  }
  if (!_isBilibiliLink(uri) || uri.host == 'b23.tv') {
    throw const FormatException('短链接没有指向可播放的 B 站视频');
  }
  final segments = uri.pathSegments;
  final media = <String, dynamic>{'aid': 0, 'cid': 0};
  if (segments.length >= 2 && segments[0] == 'video') {
    final identity = segments[1];
    if (IdUtils.bvRegexExact.hasMatch(identity)) {
      try {
        media['aid'] = IdUtils.bv2av(identity);
      } catch (_) {
        throw const FormatException('BV 编号无效');
      }
    } else if (IdUtils.avRegexExact.hasMatch(identity)) {
      media['aid'] = int.parse(identity.substring(2));
    } else {
      throw const FormatException('视频链接中的编号无效');
    }
    if ((media['aid'] as int) <= 0) throw const FormatException('视频编号无效');
    final page = int.tryParse(uri.queryParameters['p'] ?? '1');
    if (page == null || page < 1 || page > 10000) {
      throw const FormatException('视频分 P 序号无效');
    }
    media['page'] = page;
  } else if (segments.length >= 3 &&
      segments[0] == 'bangumi' &&
      segments[1] == 'play') {
    final episode = RegExp(r'^(ep|ss)([1-9]\d*)$').firstMatch(segments[2]);
    if (episode == null) throw const FormatException('番剧链接中的编号无效');
    final id = int.tryParse(episode.group(2)!);
    if (id == null || id > 0x7fffffff) throw const FormatException('番剧编号无效');
    media[episode.group(1) == 'ep' ? 'epid' : 'seasonId'] = id;
  } else {
    throw const FormatException('暂不支持这个链接，请分享视频或番剧的播放链接');
  }
  final seconds = double.tryParse(uri.queryParameters['t'] ?? '0');
  if (seconds == null ||
      !seconds.isFinite ||
      seconds < 0 ||
      seconds * 1000 > 0x7fffffff) {
    throw const FormatException('视频开始时间无效');
  }
  media['positionMs'] = (seconds * 1000).round();
  return media;
}

Future<Uri> _expandBilibiliShortLink(Uri uri) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
  Future<Uri> followRedirects() async {
    var current = uri;
    for (var attempt = 0; attempt < 5; attempt++) {
      if (!_isBilibiliLink(current)) {
        throw const FormatException('短链接跳转到了非 B 站地址');
      }
      if (current.host != 'b23.tv') return current;
      final request = await client.getUrl(current);
      request.followRedirects = false;
      final response = await request.close();
      final location = response.headers.value(HttpHeaders.locationHeader);
      if (response.statusCode < 300 ||
          response.statusCode >= 400 ||
          location == null) {
        throw const FormatException('无法展开 B 站短链接，请重试或分享完整链接');
      }
      current = current.resolve(location);
      await response.drain<void>();
    }
    throw const FormatException('B 站短链接跳转次数过多');
  }

  try {
    return await followRedirects().timeout(const Duration(seconds: 10));
  } finally {
    client.close(force: true);
  }
}

/// Owns Android share delivery for this application widget, including cold launch.
class SharedVideoReceiver extends StatefulWidget {
  const SharedVideoReceiver({required this.child, super.key});
  final Widget child;
  @override
  State<SharedVideoReceiver> createState() => _SharedVideoReceiverState();
}

class _SharedVideoReceiverState extends State<SharedVideoReceiver> {
  final _channel = const MethodChannel('dev.biliremote/shared_video');
  String? _lastShareId;
  Map<String, dynamic>? _nextShare;
  bool _processing = false;

  @override
  void initState() {
    super.initState();
    if (defaultTargetPlatform != TargetPlatform.android) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'shareReceived') _receive(call.arguments);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        _receive(await _channel.invokeMethod<dynamic>('getPendingShare'));
      } on MissingPluginException {
        // Other platforms and widget tests have no Android sharing channel.
      }
    });
  }

  void _receive(dynamic value) {
    if (!mounted || value is! Map) return;
    final id = value['id'] as String?;
    final text = value['text'] as String?;
    if (id == null || text == null || id == _lastShareId) return;
    _lastShareId = id;
    _nextShare = {'id': id, 'text': text};
    unawaited(_channel.invokeMethod<void>('acknowledgeShare', id));
    if (!_processing) unawaited(_processShares());
  }

  Future<void> _processShares() async {
    _processing = true;
    try {
      while (mounted && _nextShare != null) {
        final share = _nextShare!;
        _nextShare = null;
        try {
          SmartDialog.showToast('正在准备电视播放…');
          final media = await parseSharedBilibiliVideo(share['text'] as String);
          if (!mounted) return;
          if (_nextShare != null) continue;
          await _sendToTelevision(media);
        } catch (error) {
          if (mounted) SmartDialog.showToast('$error');
        }
      }
    } finally {
      _processing = false;
    }
  }

  Future<void> _sendToTelevision(Map<String, dynamic> media) async {
    final remote = Get.find<RemotePlaybackController>();
    while (mounted) {
      try {
        final connected = await remote.connectLastDevice();
        if (!mounted || _nextShare != null) return;
        if (!connected) {
          final selected = await Get.to<bool>(
            () => const RemoteConnectionPage(),
          );
          if (selected != true || !mounted || _nextShare != null) return;
        }
        await remote.playVideo(media);
        if (mounted && !remote.controlsVisible.value) {
          unawaited(showRemoteControls());
        }
        return;
      } catch (error) {
        if (!mounted || _nextShare != null) return;
        final action = await showDialog<String>(
          context: Get.context!,
          builder: (context) => AlertDialog(
            title: const Text('未能在电视播放'),
            content: Text('$error\n分享的视频已保留，可以重试或选择其他电视。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, 'select'),
                child: const Text('选择电视'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, 'retry'),
                child: const Text('重试'),
              ),
            ],
          ),
        );
        if (!mounted || action == null) return;
        if (action == 'select') {
          final selected = await Get.to<bool>(
            () => const RemoteConnectionPage(),
          );
          if (selected != true) return;
        }
      }
    }
  }

  @override
  void dispose() {
    if (defaultTargetPlatform == TargetPlatform.android)
      _channel.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
