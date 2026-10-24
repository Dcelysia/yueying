import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_ce/hive.dart';
import 'package:get/get.dart';

import 'browse/bili_browse_page.dart';
import 'compliance/legal_pages.dart';
import 'compliance/privacy_consent.dart';
import 'compliance/release_metadata.dart';
import 'platform/ohos_storage.dart';
import 'remote/remote_playback_controller.dart';
import 'remote/tv_connection_page.dart';
import 'remote/tv_playback_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  registerProjectLicense();
  runApp(const OhosPocApp());
}

/// The HarmonyOS build contains browsing and TV controls, with no local player.
class OhosPocApp extends StatelessWidget {
  const OhosPocApp({super.key});

  @override
  Widget build(BuildContext context) => GetMaterialApp(
    title: '跃映',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorSchemeSeed: const Color(0xffd8353f),
      scaffoldBackgroundColor: Colors.white,
    ),
    darkTheme: ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorSchemeSeed: const Color(0xffd8353f),
    ),
    home: const _StartupPage(),
  );
}

class _StartupPage extends StatefulWidget {
  const _StartupPage();

  @override
  State<_StartupPage> createState() => _StartupPageState();
}

class _StartupPageState extends State<_StartupPage> {
  late Future<bool> _startup = _initialize();

  Future<bool> _initialize() async {
    ReleaseMetadata.checkReleaseConfiguration();
    await initializeOhosStorage();
    if (!await PrivacyConsentStore.hasAcceptedCurrentPolicy()) return false;
    final remote = Get.isRegistered<RemotePlaybackController>()
        ? Get.find<RemotePlaybackController>()
        : Get.put(RemotePlaybackController(), permanent: true);
    try {
      await remote.restore();
    } catch (_) {
      await Get.delete<RemotePlaybackController>(force: true);
      rethrow;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<bool>(
    future: _startup,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      if (snapshot.hasError) {
        return Scaffold(
          appBar: AppBar(title: const Text('跃映')),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 48),
                  const SizedBox(height: 16),
                  const Text('应用初始化失败，请重试'),
                  const SizedBox(height: 8),
                  Text('${snapshot.error}', textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => setState(() {
                      _startup = _initialize();
                    }),
                    child: const Text('重试'),
                  ),
                ],
              ),
            ),
          ),
        );
      }
      if (snapshot.data != true) {
        return PrivacyConsentPage(
          onAccepted: () async {
            if (mounted) {
              setState(() {
                _startup = _initialize();
              });
            }
          },
        );
      }
      return const HomePage();
    },
  );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _remote = Get.find<RemotePlaybackController>();

  Future<void> _openConnection() => Navigator.of(
    context,
  ).push<void>(MaterialPageRoute(builder: (_) => const TvConnectionPage()));

  Future<void> _openPlayback() => Navigator.of(
    context,
  ).push<void>(MaterialPageRoute(builder: (_) => const TvPlaybackPage()));

  Future<void> _playOnTelevision(Map<String, dynamic> media) async {
    if (!_remote.connected.value) {
      try {
        await _remote.connectLastDevice();
      } catch (_) {
        // Let the user select a receiver if the saved TV is unavailable.
      }
    }
    if (!mounted) return;
    if (!_remote.connected.value) await _openConnection();
    if (!mounted) return;
    if (!_remote.connected.value) throw StateError('请先连接电视，再选择播放');
    await _remote.playVideo(media);
    if (mounted) await _openPlayback();
  }

  Future<void> _clearTelevisionStorage() async {
    await _remote.disconnect();
    await Get.delete<RemotePlaybackController>(force: true);
    await (await Hive.openBox<String>('remote_pairing')).clear();
    await (await Hive.openBox<dynamic>('remoteManualConnection')).clear();
  }

  void _restartAtConsentGate() {
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil<void>(
      MaterialPageRoute(builder: (_) => const _StartupPage()),
      (_) => false,
    );
  }

  Future<void> _clearTelevisionRecords() async {
    await _clearTelevisionStorage();
    _restartAtConsentGate();
  }

  Future<void> _withdrawPrivacyConsent() async {
    await _clearTelevisionStorage();
    await PrivacyConsentStore.withdraw();
    _restartAtConsentGate();
    try {
      await SystemNavigator.pop();
    } on PlatformException {
      /* Remain offline. */
    }
  }

  @override
  Widget build(BuildContext context) => BiliBrowsePage(
    onPlayOnTelevision: _playOnTelevision,
    onClearTelevisionRecords: _clearTelevisionRecords,
    onWithdrawPrivacy: _withdrawPrivacyConsent,
    floatingActionButton: Obx(() {
      final state = _remote.state.value;
      final hasPlayback =
          _remote.remoteMode.value &&
          state.playbackId.isNotEmpty &&
          state.aid > 0;
      final label = hasPlayback
          ? _remote.connected.value
                ? '电视播放'
                : '正在重连'
          : _remote.connected.value
          ? '已连接电视'
          : '连接电视';
      return FloatingActionButton.extended(
        tooltip: hasPlayback && state.title.isNotEmpty ? state.title : label,
        onPressed: hasPlayback ? _openPlayback : _openConnection,
        icon: Icon(_remote.connected.value ? Icons.cast_connected : Icons.cast),
        label: Text(label),
      );
    }),
  );
}
