import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:PiliPlus/services/remote_playback/remote_playback_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:PiliPlus/pages/remote_playback/shared_video_receiver.dart';

class _ShareTestRemote extends RemotePlaybackController {
  final loads = <Map<String, dynamic>>[];
  @override
  void onInit() {}
  @override
  void onClose() {}
  @override
  Future<bool> connectLastDevice() async => true;
  @override
  Future<void> playVideo(Map<String, dynamic> media) async {
    loads.add(Map.of(media));
  }
}

void main() {
  testWidgets('cold and warm shares are forwarded once', (tester) async {
    SmartDialog.config.toast = SmartConfigToast(displayType: .onlyRefresh);
    const channel = MethodChannel('dev.biliremote/shared_video');
    const codec = StandardMethodCodec();
    final remote = _ShareTestRemote();
    remote.controlsVisible.value = true;
    Get.put<RemotePlaybackController>(remote);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      if (call.method == 'getPendingShare') {
        return {
          'id': 'cold',
          'text': 'https://www.bilibili.com/video/av42?p=2',
        };
      }
      return null;
    });
    try {
      await tester.pumpWidget(
        GetMaterialApp(
          builder: FlutterSmartDialog.init(),
          home: const SharedVideoReceiver(child: SizedBox()),
        ),
      );
      await tester.pumpAndSettle();
      expect(remote.loads.single['aid'], 42);
      expect(remote.loads.single['page'], 2);
      Future<void> deliver(String id) async {
        await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
          channel.name,
          codec.encodeMethodCall(
            MethodCall('shareReceived', {
              'id': id,
              'text': 'https://www.bilibili.com/bangumi/play/ep55',
            }),
          ),
          (_) {},
        );
        await tester.pumpAndSettle();
      }

      await deliver('warm');
      await deliver('warm');
      expect(remote.loads.length, 2);
      expect(remote.loads.last['epid'], 55);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
    } finally {
      await tester.pumpWidget(const SizedBox());
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      );
      Get.reset();
    }
  });

  test(
    'official share text preserves video, part and start time locally',
    () async {
      final media = await parseSharedBilibiliVideo(
        '【测试视频】 https://www.bilibili.com/video/av170001?p=2&t=12.5',
      );
      expect(media, {'aid': 170001, 'cid': 0, 'page': 2, 'positionMs': 12500});
      final bv = await parseSharedBilibiliVideo(
        'https://www.bilibili.com/video/BV17x411w7KC',
      );
      expect(bv['aid'], 170001);
    },
  );

  test(
    'short links only expand once before forwarding the video identifier',
    () async {
      var expansions = 0;
      final media = await parseSharedBilibiliVideo(
        '【视频标题】 https://b23.tv/AbCd。',
        expandShortLink: (uri) async {
          expect(uri.toString(), 'https://b23.tv/AbCd');
          expansions++;
          return Uri.parse('https://m.bilibili.com/video/av42?p=3');
        },
      );
      expect(expansions, 1);
      expect(media['aid'], 42);
      expect(media['page'], 3);
    },
  );

  test(
    'episode and season shares need no phone-side video detail request',
    () async {
      final episode = await parseSharedBilibiliVideo(
        'https://www.bilibili.com/bangumi/play/ep55',
      );
      final season = await parseSharedBilibiliVideo(
        'https://m.bilibili.com/bangumi/play/ss8',
      );
      expect(episode['epid'], 55);
      expect(season['seasonId'], 8);
      expect(episode['aid'], 0);
      expect(episode['cid'], 0);
    },
  );

  test(
    'rejects lookalike hosts, unrelated links and invalid playback offsets',
    () async {
      for (final text in [
        'https://www.bilibili.com.evil.example/video/av42',
        'https://bilibili.com@evil.example/video/av42',
        'https://live.bilibili.com/123',
        'https://www.bilibili.com/video/av42?p=0',
        'https://www.bilibili.com/video/av42?t=NaN',
      ]) {
        await expectLater(
          parseSharedBilibiliVideo(text),
          throwsFormatException,
        );
      }
      await expectLater(
        parseSharedBilibiliVideo(
          'https://b23.tv/AbCd',
          expandShortLink: (_) async =>
              Uri.parse('https://evil.example/video/av42'),
        ),
        throwsFormatException,
      );
    },
  );
}
