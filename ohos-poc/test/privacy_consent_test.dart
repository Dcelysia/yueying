import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive_ce/hive.dart';
import 'package:ohos_poc/compliance/legal_pages.dart';
import 'package:ohos_poc/compliance/privacy_consent.dart';
import 'package:ohos_poc/compliance/release_metadata.dart';
import 'package:ohos_poc/main.dart';
import 'package:ohos_poc/remote/remote_playback_controller.dart';

class _NoNetworkBeforeConsent extends HttpOverrides {
  int clientCreations = 0;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    clientCreations++;
    throw StateError('Network client created before consent');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory storage;
  late _NoNetworkBeforeConsent network;
  late HttpOverrides? previousOverrides;
  var exitRequests = 0;

  setUp(() async {
    storage = await Directory.systemTemp.createTemp('bili-privacy-test-');
    Hive.init(storage.path);
    await Hive.openBox<String>(PrivacyConsentStore.boxName);
    Get.testMode = true;
    network = _NoNetworkBeforeConsent();
    previousOverrides = HttpOverrides.current;
    HttpOverrides.global = network;
    exitRequests = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dev.fluttercommunity.plus/connectivity_status'),
          (call) async => null,
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dev.biliremote/platform'),
          (call) async => call.method == 'filesDirectory' ? storage.path : null,
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'SystemNavigator.pop') exitRequests++;
          return null;
        });
  });

  tearDown(() async {
    HttpOverrides.global = previousOverrides;
    Get.reset();
    await Hive.close();
    await storage.delete(recursive: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dev.biliremote/platform'),
          null,
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets(
    'startup, offline policy reading and declining make no network client',
    (tester) async {
      await tester.pumpWidget(const OhosPocApp());
      await tester.pumpAndSettle();
      expect(find.text('先了解信息如何使用'), findsOneWidget);
      expect(Get.isRegistered<RemotePlaybackController>(), isFalse);
      expect(network.clientCreations, 0);

      await tester.tap(find.text('隐私政策'));
      await tester.pumpAndSettle();
      expect(find.byType(LegalDocumentPage), findsOneWidget);
      expect(find.text('1. 适用范围'), findsOneWidget);
      expect(network.clientCreations, 0);
      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('不同意并退出'));
      await tester.tap(find.text('不同意并退出'));
      await tester.pumpAndSettle();
      expect(exitRequests, 1);
      expect(find.textContaining('你尚未同意'), findsOneWidget);
      expect(Get.isRegistered<RemotePlaybackController>(), isFalse);
      expect(network.clientCreations, 0);
      expect(await PrivacyConsentStore.hasAcceptedCurrentPolicy(), isFalse);
    },
  );

  testWidgets('first consent transitions through the actual startup callback', (
    tester,
  ) async {
    await tester.pumpWidget(const OhosPocApp());
    await tester.pumpAndSettle();
    final agree = find.text('同意隐私政策及用户协议并继续');
    HttpOverrides.global = previousOverrides;
    await tester.ensureVisible(agree);
    await tester.runAsync(() async {
      await tester.tap(agree);
      await Future<void>.delayed(const Duration(milliseconds: 80));
    });
    for (var attempt = 0; attempt < 10; attempt++) {
      await tester.pump();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      if (find.byType(HomePage).evaluate().isNotEmpty) break;
    }
    await tester.pump();
    expect(find.byType(HomePage), findsOneWidget);
    expect(find.text('无法保存选择，请重试'), findsNothing);
    expect(find.byType(PrivacyConsentPage), findsNothing);
    expect(Get.isRegistered<RemotePlaybackController>(), isTrue);
    expect(await PrivacyConsentStore.hasAcceptedCurrentPolicy(), isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    await Get.delete<RemotePlaybackController>(force: true);
    await tester.pumpAndSettle();
  });

  testWidgets('consent is stored before the network-enabled callback can run', (
    tester,
  ) async {
    var acceptedInCallback = false;
    await tester.pumpWidget(
      MaterialApp(
        home: PrivacyConsentPage(
          onAccepted: () async {
            acceptedInCallback =
                await PrivacyConsentStore.hasAcceptedCurrentPolicy();
          },
        ),
      ),
    );
    final agree = find.text('同意隐私政策及用户协议并继续');
    await tester.ensureVisible(agree);
    await tester.runAsync(() async {
      await tester.tap(agree);
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pumpAndSettle();
    expect(acceptedInCallback, isTrue);
    expect(await PrivacyConsentStore.hasAcceptedCurrentPolicy(), isTrue);
    await tester.runAsync(PrivacyConsentStore.withdraw);
    expect(await PrivacyConsentStore.hasAcceptedCurrentPolicy(), isFalse);
    expect(network.clientCreations, 0);
  });

  test(
    'release metadata rejects missing fields and private or placeholder URLs',
    () {
      expect(ReleaseMetadata.publicationIssues({}), hasLength(5));
      final valid = <String, String>{
        'operator': '测试维护者',
        'contact_email': 'support@biliremote.org',
        'source_url': 'https://github.com/owner/bili-remote/tree/commit',
        'privacy_url': 'https://biliremote.org/privacy',
        'terms_url': 'https://biliremote.org/terms',
      };
      expect(ReleaseMetadata.publicationIssues(valid), isEmpty);
      for (final url in [
        'http://biliremote.org/privacy',
        'https://192.168.5.223/privacy',
        'https://example.com/privacy',
        'https://user:password@biliremote.org/privacy',
      ]) {
        expect(
          ReleaseMetadata.publicationIssues({...valid, 'privacy_url': url}),
          hasLength(1),
        );
      }
    },
  );
}
