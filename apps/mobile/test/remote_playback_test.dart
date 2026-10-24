import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:PiliPlus/services/remote_playback/remote_playback_controller.dart';
import 'package:PiliPlus/services/remote_playback/remote_playback_state.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final defaultHttpOverrides = HttpOverrides.current;
  const connectivityEvents = MethodChannel(
    'dev.fluttercommunity.plus/connectivity_status',
  );
  setUp(() {
    // These protocol tests use a real loopback HTTP/WebSocket receiver.
    HttpOverrides.global = null;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      connectivityEvents,
      (_) async => null,
    );
  });
  tearDown(() {
    HttpOverrides.global = defaultHttpOverrides;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      connectivityEvents,
      null,
    );
  });

  test('only local TV addresses can receive pairing tokens', () {
    for (final value in [
      'http://192.168.1.4:9837',
      'http://10.0.2.2:9837',
      'http://172.16.0.1:9837',
      'http://[fd00::1]:9837',
    ]) {
      expect(() => validateRemoteAddress(Uri.parse(value)), returnsNormally);
    }
    for (final value in [
      'http://8.8.8.8',
      'http://example.com',
      'http://user@192.168.1.4',
      'https://192.168.1.4',
      'http://172.32.0.1',
    ]) {
      expect(
        () => validateRemoteAddress(Uri.parse(value)),
        throwsFormatException,
      );
    }
  });

  test('TV state, command acknowledgement and disconnect preserve independent playback', () async {
    final storage = await Directory.systemTemp.createTemp('bili-remote-test-');
    Hive.init(storage.path);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final received = <Map<String, dynamic>>[];
    final socketReady = Completer<WebSocket>();
    final subscription = server.listen((request) async {
      if (request.uri.path == '/remote/v1/info') {
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'protocol': 1,
            'deviceId': 'test-device-0001',
            'name': '测试电视',
          }),
        );
        await request.response.close();
        return;
      }
      final socket = await WebSocketTransformer.upgrade(request);
      socketReady.complete(socket);
      socket.listen((message) {
        final data = jsonDecode(message as String) as Map<String, dynamic>;
        received.add(data);
        if (data['type'] == 'hello') {
          socket
            ..add(
              jsonEncode({
                'type': 'welcome',
                'protocol': 1,
                'deviceId': 'test-device-0001',
                'token': 'test-token',
                'name': '测试电视',
              }),
            )
            ..add(
              jsonEncode({
                'type': 'state',
                'playbackId': 'episode-a',
                'revision': 2,
                'state': 'PLAYING',
                'aid': 42,
                'cid': 99,
                'positionMs': 10000,
                'durationMs': 120000,
                'volume': 60,
              }),
            );
        } else if (data['action'] == 'next') {
          socket.add(
            jsonEncode({
              'type': 'error',
              'requestId': data['requestId'],
              'message': '没有可切换的剧集',
            }),
          );
        } else {
          socket.add(
            jsonEncode({
              'type': 'ack',
              'requestId': data['requestId'],
              'status': 'applied',
            }),
          );
        }
      });
    });
    final remote = RemotePlaybackController()..onInit();
    try {
      await remote.restore();
      await remote.connect(
        Uri.parse('http://127.0.0.1:${server.port}'),
      );
      final socket = await socketReady.future;
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(remote.connected.value, isTrue);
      expect(remote.remoteMode.value, isTrue);
      expect(remote.state.value.cid, 99);
      await remote.command('seek', {'positionMs': 30000});
      expect(received.last['playbackId'], 'episode-a');
      expect(received.last['payload'], {'positionMs': 30000});
      socket.add(
        jsonEncode({
          'type': 'state',
          'revision': 1,
          'cid': 100,
          'state': 'PAUSED',
        }),
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(
        remote.state.value.cid,
        99,
        reason: 'Old TV snapshots must not overwrite newer state.',
      );
      await remote.perform('next');
      expect(remote.error.value, 'Bad state: 没有可切换的剧集');
      socket.add(
        jsonEncode({
          'type': 'state',
          'playbackId': 'episode-a',
          'revision': 3,
          'state': 'PLAYING',
          'aid': 42,
          'cid': 99,
        }),
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(
        remote.error.value,
        'Bad state: 没有可切换的剧集',
        reason: 'An update in the same TV session must preserve its error.',
      );
      socket.add(
        jsonEncode({
          'type': 'state',
          'playbackId': 'episode-b',
          'revision': 4,
          'state': 'PLAYING',
          'aid': 43,
          'cid': 102,
          'title': '另一台手机切换的新视频',
        }),
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(remote.state.value.playbackId, 'episode-b');
      expect(remote.state.value.title, '另一台手机切换的新视频');
      expect(
        remote.error.value,
        isEmpty,
        reason: 'A new TV session must discard the previous session error.',
      );
      await remote.playVideo({
        'aid': 42,
        'cid': 101,
        'epid': 12,
        'seasonId': 3,
        'positionMs': 0,
      });
      expect(received.last['action'], 'load');
      expect((received.last['payload'] as Map).containsKey('url'), isFalse);
      await remote.disconnect();
      expect(received.where((item) => item['action'] == 'stop'), isEmpty);
    } finally {
      await remote.disconnect();
      remote.onClose();
      await subscription.cancel();
      await server.close(force: true);
      await Hive.close();
      await storage.delete(recursive: true);
    }
  });
}
