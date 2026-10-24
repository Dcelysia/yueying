import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:ohos_poc/remote/remote_playback_controller.dart';
import 'package:ohos_poc/remote/remote_playback_state.dart';
import 'package:ohos_poc/remote/tv_playback_page.dart';

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
  Future<void> perform(
    String action, [
    Map<String, dynamic> payload = const {},
  ]) async {
    commands.add((action: action, payload: payload));
  }

  @override
  void setTelevisionVolume(int value, {bool dragging = false}) {
    commands.add((action: 'volume', payload: {'value': value}));
  }
}

RemotePlaybackState _snapshot(String id, {int aid = 101, int volume = 50}) =>
    RemotePlaybackState({
      'playbackId': id,
      'revision': 1,
      'state': 'PLAYING',
      'aid': aid,
      'cid': aid + 100,
      'title': '视频 $id',
      'positionMs': 42000,
      'durationMs': 180000,
      'volume': volume,
      'volumeMode': 'system',
      'danmakuEnabled': true,
      'queue': [
        {'aid': aid, 'cid': aid + 100, 'title': '$id 第一集'},
        {'aid': aid, 'cid': aid + 101, 'title': '$id 第二集'},
      ],
    });

Future<_TelevisionCommandSpy> _openFullscreen(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1000, 700);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final remote = _TelevisionCommandSpy();
  remote.remoteMode.value = true;
  remote.connected.value = true;
  remote.state.value = _snapshot('A');
  Get.put<RemotePlaybackController>(remote);
  await tester.pumpWidget(const MaterialApp(home: TvPlaybackPage()));
  await tester.tap(find.byTooltip('全屏遥控'));
  await tester.pumpAndSettle();
  return remote;
}

Finder get _panel => find.byKey(const ValueKey('tv-fullscreen-settings'));
Finder get _fullscreen => find.byKey(const ValueKey('tv-fullscreen-page'));
Finder get _panelSliders =>
    find.descendant(of: _panel, matching: find.byType(Slider));

void main() {
  final platformCalls = <MethodCall>[];
  setUp(() {
    Get.testMode = true;
    platformCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          platformCalls.add(call);
          return null;
        });
  });
  tearDown(() {
    Get.reset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets(
    'attaching and fullscreen preserve TV session and request immersive landscape',
    (tester) async {
      final remote = await _openFullscreen(tester);
      expect(_fullscreen, findsOneWidget);
      expect(find.textContaining('视频 A ·'), findsOneWidget);
      expect(remote.commands, isEmpty);
      expect(
        platformCalls.any(
          (call) =>
              call.method == 'SystemChrome.setPreferredOrientations' &&
              (call.arguments as List).contains(
                'DeviceOrientation.landscapeLeft',
              ),
        ),
        isTrue,
      );
      expect(
        platformCalls.any(
          (call) =>
              call.method == 'SystemChrome.setEnabledSystemUIMode' &&
              call.arguments == 'SystemUiMode.immersiveSticky',
        ),
        isTrue,
      );

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(_fullscreen, findsNothing);
      expect(find.text('视频 A'), findsOneWidget);
      expect(remote.state.value.playbackId, 'A');
      expect(remote.commands, isEmpty);
      expect(
        platformCalls
            .lastWhere(
              (call) => call.method == 'SystemChrome.setEnabledSystemUIMode',
            )
            .arguments,
        'SystemUiMode.edgeToEdge',
      );
    },
  );

  testWidgets(
    'fullscreen volume opens Android style right panel and controls only television',
    (tester) async {
      final remote = await _openFullscreen(tester);
      for (final label in ['选集', '1.0× 倍速', '画质', '弹幕 · 开', '音量 50%', '广告跳过']) {
        expect(find.text(label), findsOneWidget);
      }
      await tester.tap(find.text('音量 50%'));
      await tester.pumpAndSettle();
      expect(_panel, findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
      final bounds = tester.getRect(_panel);
      expect(bounds.right, 1000);
      expect(bounds.width, 360);
      final volume = tester.widget<Slider>(_panelSliders);
      volume.onChangeStart!(75);
      volume.onChangeEnd!(75);
      expect(remote.commands, hasLength(1));
      expect(remote.commands.single.action, 'volume');
      expect(remote.commands.single.payload, {'value': 75});
      expect(remote.state.value.playbackId, 'A');
    },
  );

  testWidgets(
    'another phone switching video updates open panel and cancels old volume gesture',
    (tester) async {
      final remote = await _openFullscreen(tester);
      await tester.tap(find.text('音量 50%'));
      await tester.pumpAndSettle();
      final oldVolume = tester.widget<Slider>(_panelSliders);
      oldVolume.onChangeStart!(85);
      remote.state.value = _snapshot('B', aid: 102, volume: 60);
      await tester.pumpAndSettle();
      expect(find.textContaining('视频 B ·'), findsOneWidget);
      expect(find.textContaining('视频 A ·'), findsNothing);
      expect(_panel, findsOneWidget);
      expect(tester.widget<Slider>(_panelSliders).value, 60);
      oldVolume.onChangeEnd!(85);
      await tester.pump();
      expect(remote.commands, isEmpty);

      await tester.tap(find.byTooltip('关闭面板'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('选集'));
      await tester.pumpAndSettle();
      expect(find.text('A 第二集'), findsNothing);
      expect(find.text('B 第二集'), findsOneWidget);
      await tester.tap(find.text('B 第二集'));
      await tester.pump();
      expect(remote.commands, hasLength(1));
      expect(remote.commands.single.action, 'episode');
      expect(remote.commands.single.payload, {'aid': 102, 'cid': 203});
    },
  );

  testWidgets('narrow landscape retains usable fullscreen controls', (
    tester,
  ) async {
    final remote = await _openFullscreen(tester);
    tester.view.physicalSize = const Size(840, 390);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('音量 50%'));
    await tester.pumpAndSettle();
    expect(_panel, findsOneWidget);
    expect(_panelSliders, findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.binding.handlePopRoute();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(remote.commands, isEmpty);
  });

  testWidgets('back closes settings before leaving fullscreen', (tester) async {
    final remote = await _openFullscreen(tester);
    await tester.tap(find.text('选集'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(_panel, findsNothing);
    expect(_fullscreen, findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(_fullscreen, findsNothing);
    expect(remote.commands, isEmpty);
  });
}
