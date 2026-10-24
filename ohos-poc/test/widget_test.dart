import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:ohos_poc/browse/bili_client.dart';
import 'package:ohos_poc/remote/remote_playback_controller.dart';
import 'package:ohos_poc/remote/remote_playback_state.dart';
import 'package:ohos_poc/remote/tv_playback_page.dart';

/// A disconnected transport spy: widget tests cannot make LAN/native calls.
class _TelevisionCommandSpy extends RemotePlaybackController {
  final commands = <({String action, Map<String, dynamic> payload})>[];

  @override
  Future<void> playVideo(Map<String, dynamic> media) async {
    commands.add((action: 'load', payload: media));
  }

  @override
  Future<void> seekTo(int positionMs) async {
    commands.add((action: 'seek', payload: {'positionMs': positionMs}));
  }

  @override
  Future<void> command(
    String action, [
    Map<String, dynamic> payload = const {},
  ]) async {
    commands.add((action: action, payload: payload));
  }

  @override
  Future<void> perform(
    String action, [
    Map<String, dynamic> payload = const {},
  ]) async {
    commands.add((action: action, payload: payload));
  }
}

RemotePlaybackState _snapshot(
  String playbackId,
  String title, {
  int aid = 101,
  int cid = 201,
  int positionMs = 42000,
}) => RemotePlaybackState({
  'playbackId': playbackId,
  'revision': 1,
  'state': 'PLAYING',
  'aid': aid,
  'cid': cid,
  'title': title,
  'positionMs': positionMs,
  'durationMs': 180000,
  'volume': 50,
  'volumeMode': 'system',
});

Future<_TelevisionCommandSpy> _openPlayback(WidgetTester tester) async {
  final remote = _TelevisionCommandSpy();
  remote.remoteMode.value = true;
  remote.connected.value = true;
  remote.state.value = _snapshot('video-a', '视频 A');
  Get.put<RemotePlaybackController>(remote);
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute(builder: (_) => const TvPlaybackPage()),
              ),
              child: const Text('进入电视控制页'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('进入电视控制页'));
  await tester.pumpAndSettle();
  return remote;
}

void main() {
  setUp(() {
    Get.testMode = true;
  });
  tearDown(() {
    Get.reset();
  });

  testWidgets(
    'opening and closing the TV page never loads, seeks or stops TV',
    (tester) async {
      final remote = await _openPlayback(tester);
      expect(find.text('视频 A'), findsOneWidget);
      expect(find.text('0:42'), findsOneWidget);
      expect(remote.commands, isEmpty);
      expect(
        tester
            .widget<IconButton>(
              find
                  .byWidgetPredicate(
                    (widget) => widget is IconButton && widget.tooltip == '下一集',
                  )
                  .first,
            )
            .onPressed,
        isNull,
      );

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('进入电视控制页'), findsOneWidget);
      expect(remote.commands, isEmpty);
      expect(remote.state.value.playbackId, 'video-a');
      expect(remote.connected.value, isTrue);
    },
  );

  testWidgets(
    'another phone switching A to B follows snapshots without commands',
    (tester) async {
      final remote = await _openPlayback(tester);
      remote.state.value = _snapshot('video-a', '视频 A', positionMs: 68000);
      await tester.pump();
      expect(find.text('1:08'), findsOneWidget);

      remote.state.value = _snapshot(
        'video-b',
        '视频 B',
        aid: 102,
        cid: 202,
        positionMs: 15000,
      );
      await tester.pump();
      expect(find.text('视频 A'), findsNothing);
      expect(find.text('视频 B'), findsOneWidget);
      expect(find.text('0:15'), findsOneWidget);
      expect(remote.commands, isEmpty);
    },
  );

  testWidgets(
    'a previous video queue cannot control the newly selected video',
    (tester) async {
      final remote = await _openPlayback(tester);
      remote.state.value = RemotePlaybackState({
        ..._snapshot('video-b', '视频 B', aid: 102, cid: 202).data,
        'queue': [
          {'aid': 101, 'cid': 201, 'title': '旧视频选集'},
        ],
      });
      await tester.pump();
      expect(find.text('旧视频选集'), findsNothing);
      expect(find.text('选集信息正在同步'), findsOneWidget);
      expect(remote.commands, isEmpty);
    },
  );

  testWidgets('a seek started on A cannot seek B after its session changes', (
    tester,
  ) async {
    final remote = await _openPlayback(tester);
    final initialSlider = tester.widget<Slider>(find.byType(Slider).first);
    initialSlider.onChangeStart!(90000);
    initialSlider.onChanged!(90000);
    await tester.pump();

    remote.state.value = _snapshot('video-b', '视频 B', aid: 102, cid: 202);
    await tester.pump();
    // A pointer-up callback retained by the old gesture must be harmless.
    initialSlider.onChangeEnd!(90000);
    await tester.pump();
    expect(find.text('视频 B'), findsOneWidget);
    expect(remote.commands, isEmpty);
  });

  testWidgets('an explicit seek within the same TV session sends one seek', (
    tester,
  ) async {
    final remote = await _openPlayback(tester);
    final slider = tester.widget<Slider>(find.byType(Slider).first);
    slider.onChangeStart!(90000);
    slider.onChanged!(90000);
    await tester.pump();
    slider.onChangeEnd!(90000);
    await tester.pump();
    expect(remote.commands, hasLength(1));
    expect(remote.commands.single.action, 'seek');
    expect(remote.commands.single.payload, {'positionMs': 90000});
  });

  testWidgets('losing TV connection disables playback without stopping TV', (
    tester,
  ) async {
    final remote = await _openPlayback(tester);
    remote.connected.value = false;
    await tester.pump();
    expect(find.text('连接已断开'), findsOneWidget);
    expect(tester.widget<Slider>(find.byType(Slider).first).onChanged, isNull);
    final pause = tester.widget<IconButton>(
      find.byWidgetPredicate(
        (widget) => widget is IconButton && widget.tooltip == '暂停电视',
      ),
    );
    expect(pause.onPressed, isNull);
    expect(remote.commands, isEmpty);
  });

  test(
    'Bilibili history preserves its part and converts seconds to milliseconds',
    () {
      final video = BiliVideo.fromHistory({
        'title': '分 P 视频',
        'progress': 127,
        'history': {'oid': 101, 'cid': 202, 'business': 'archive'},
      });
      expect(video.aid, 101);
      expect(video.historyCid, 202);
      expect(video.historyPositionMs, 127000);
    },
  );

  test(
    'completed history explicitly restarts while a new item has no history',
    () {
      final completed = BiliVideo.fromHistory({
        'progress': -1,
        'history': {'oid': 101, 'cid': 201},
      });
      final newVideo = BiliVideo.fromVideo({'aid': 102, 'title': '新视频'});
      expect(completed.historyPositionMs, 0);
      expect(newVideo.historyPositionMs, isNull);
    },
  );

  test(
    'video cards display both search clock strings and numeric durations',
    () {
      expect(BiliVideo.fromVideo({'duration': '03:15'}).duration, 195);
      expect(BiliVideo.fromVideo({'duration': '1:02:03'}).duration, 3723);
      expect(BiliVideo.fromVideo({'duration': 195}).duration, 195);
    },
  );

  test('only local TV endpoints may receive connection credentials', () {
    for (final value in [
      'http://192.168.1.4:9838',
      'http://10.0.2.2:9838',
      'http://172.16.0.1:9838',
      'http://[fd00::1]:9838',
    ]) {
      expect(() => validateRemoteAddress(Uri.parse(value)), returnsNormally);
    }
    for (final value in [
      'http://8.8.8.8:9838',
      'http://example.com:9838',
      'https://192.168.1.4:9838',
      'http://172.32.0.1:9838',
    ]) {
      expect(
        () => validateRemoteAddress(Uri.parse(value)),
        throwsA(isA<FormatException>()),
      );
    }
  });
}
