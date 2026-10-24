import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:PiliPlus/services/remote_playback/remote_device_discovery.dart';
import 'package:PiliPlus/utils/theme_utils.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:PiliPlus/models/common/video/video_type.dart';
import 'package:PiliPlus/http/search.dart';
import 'package:PiliPlus/pages/sponsor_block/view.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:PiliPlus/services/remote_playback/remote_playback_controller.dart';

Future<void> openTelevisionPlayback({
  bool replace = false,
  bool fullScreen = false,
  bool Function()? canOpen,
}) async {
  final remote = Get.find<RemotePlaybackController>();
  final state = remote.state.value;
  if (!remote.remoteMode.value || state.aid <= 0 || state.cid <= 0) {
    SmartDialog.showToast('等待电视播放状态，请稍后再试');
    return;
  }
  if (state.status == 'TRANSITIONING') {
    SmartDialog.showToast('电视正在切换视频，请稍后再试');
    return;
  }
  final arguments = <String, dynamic>{
    'attachTelevisionPlayback': true,
    'televisionFullScreen': fullScreen,
  };
  if (state.epid != null) {
    final originRoute = Get.routing.current;
    try {
      final result = await SearchHttp.pgcInfo(
        seasonId: state.seasonId,
        epId: state.epid,
      );
      if (!remote.remoteMode.value ||
          canOpen?.call() == false ||
          Get.routing.current != originRoute ||
          remote.state.value.aid != state.aid ||
          remote.state.value.cid != state.cid) {
        return;
      }
      if (result case Success(:final response)) {
        arguments['pgcItem'] = response;
      } else {
        result.toast();
        return;
      }
    } catch (error) {
      SmartDialog.showToast('$error');
      return;
    }
  }
  await PageUtils.toVideoPage(
    aid: state.aid,
    cid: state.cid,
    title: state.title,
    videoType: state.epid != null ? VideoType.pgc : VideoType.ugc,
    epId: state.epid,
    seasonId: state.seasonId,
    off: replace,
    extraArguments: arguments,
  );
}

Future<void> showRemoteControls() async {
  final remote = Get.find<RemotePlaybackController>();
  if (remote.controlsVisible.value) return;
  remote.controlsVisible.value = true;
  try {
    await showModalBottomSheet<void>(
      context: Get.context!,
      builder: (context) => SliderTheme(
        data: SliderTheme.of(context).copyWith(
          trackHeight: 4,
          trackShape: const RoundedRectSliderTrackShape(),
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
          overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
          trackGap: 0,
        ),
        child: const RemoteControls(),
      ),
      isScrollControlled: true,
      useRootNavigator: true,
    );
  } finally {
    remote.controlsVisible.value = false;
  }
}

class RemoteConnectionPage extends StatefulWidget {
  const RemoteConnectionPage({super.key});
  @override
  State<RemoteConnectionPage> createState() => _RemoteConnectionPageState();
}

class _RemoteConnectionPageState extends State<RemoteConnectionPage> {
  final _address = TextEditingController();
  final _port = TextEditingController();
  final _remote = Get.find<RemotePlaybackController>();
  String? _message;

  @override
  void initState() {
    super.initState();
    final form = GStorage.localCache.get('remoteManualConnection') as Map?;
    final saved = _remote.savedDevice.value?.address;
    _address.text = form?['ip'] as String? ?? saved?.host ?? '';
    _port.text =
        form?['port'] as String? ?? (saved == null ? '' : '${saved.port}');
    unawaited(_search());
  }

  Future<void> _saveManualConnection() async {
    try {
      await GStorage.localCache.put('remoteManualConnection', {
        'ip': _address.text.trim(),
        'port': _port.text.trim(),
      });
    } catch (_) {
      if (mounted) setState(() => _message = '连接信息保存失败，请检查手机存储空间');
    }
  }

  Future<void> _search() async {
    setState(() => _message = null);
    await _remote.searchDevices(useFixedAddressFallback: true);
  }

  Future<void> _connect({RemoteDevice? saved}) async {
    _remote.stopDeviceSearch();
    try {
      var uri = saved?.address;
      if (uri == null) {
        final ipText = _address.text.trim();
        final ip = InternetAddress.tryParse(
          ipText.isEmpty ? defaultRemoteAddress.host : ipText,
        );
        if (ip == null) throw const FormatException('请输入有效的电视 IP，端口请填写在右侧');
        final portText = _port.text.trim();
        final port = portText.isEmpty
            ? defaultRemoteAddress.port
            : int.tryParse(portText);
        if (port == null || port < 1 || port > 65535) {
          throw const FormatException('端口必须是 1–65535 的数字');
        }
        uri = Uri(scheme: 'http', host: ip.address, port: port);
        await _saveManualConnection();
        if (!mounted) return;
      }
      await _remote.connect(uri);
      if (mounted) Get.back(result: true);
    } catch (error) {
      if (mounted) setState(() => _message = '$error');
    }
  }

  void _selectDevice(RemoteDevice device) {
    setState(() {
      _address.text = device.address.host;
      _port.text = '${device.address.port}';
      _message = null;
    });
    unawaited(_saveManualConnection());
  }

  @override
  void dispose() {
    _remote.stopDeviceSearch();
    _address.dispose();
    _port.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('连接电视')),
    body: Obx(() {
      final saved = _remote.savedDevice.value;
      final busy = _remote.connecting.value;
      final searching = _remote.discovering.value;
      final checking = _remote.checkingConnection.value;
      final connected = _remote.connected.value;
      final discoveryError = _remote.discoveryError.value;
      final connectionError = _remote.error.value;
      final newDevices = [
        for (final device in _remote.nearbyDevices)
          if (saved == null ||
              (saved.deviceId.isNotEmpty
                  ? device.deviceId != saved.deviceId
                  : device.address.authority != saved.address.authority))
            device,
      ];
      final savedStatus = checking
          ? '正在确认连接…'
          : connected
          ? '已连接 · 点按返回选视频'
          : busy
          ? '正在连接…'
          : _remote.needsPairing
          ? '请更新电视端以支持免配对连接'
          : _remote.remoteMode.value
          ? '等待电视上线 · 会自动重连'
          : '已保存 · 点按连接';
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('打开电视上的 Bili Remote TV，并让手机与电视连接同一局域网。选择电视即可连接，无需配对码。'),
          if (saved != null) ...[
            const SizedBox(height: 24),
            Text('我的电视', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Card.filled(
              margin: EdgeInsets.zero,
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                leading: Icon(
                  connected ? Icons.tv_rounded : Icons.tv_off_rounded,
                ),
                title: Text(saved.name),
                subtitle: Text('$savedStatus\n${saved.address.authority}'),
                isThreeLine: true,
                trailing: busy || checking
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        connected
                            ? Icons.check_circle_rounded
                            : Icons.chevron_right_rounded,
                      ),
                onTap: busy || checking
                    ? null
                    : () {
                        if (connected) {
                          Get.back(result: true);
                        } else if (_remote.needsPairing) {
                          _selectDevice(saved);
                        } else {
                          unawaited(_connect(saved: saved));
                        }
                      },
              ),
            ),
          ],
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: Text(
                  '新发现设备',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              TextButton(
                onPressed: searching ? null : _search,
                child: const Text('重新搜索'),
              ),
            ],
          ),
          if (searching) const LinearProgressIndicator(),
          if (!connected && newDevices.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('自动搜索未找到时，会尝试连接 ${defaultRemoteAddress.authority}。'),
            ),
          for (final device in newDevices)
            ListTile(
              leading: const Icon(Icons.tv),
              title: Text(device.name),
              subtitle: Text(device.address.authority),
              selected:
                  _address.text.trim() == device.address.host &&
                  int.tryParse(_port.text.trim()) == device.address.port,
              onTap: busy ? null : () => unawaited(_connect(saved: device)),
            ),
          if (_remote.discoveryStatus.value.isNotEmpty || newDevices.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                _remote.discoveryStatus.value.isNotEmpty
                    ? _remote.discoveryStatus.value
                    : '暂未发现新设备，仍可手动输入电视地址。',
              ),
            ),
          if (discoveryError.isNotEmpty) Text(discoveryError),
          const SizedBox(height: 20),
          Text('手动连接', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _address,
                  decoration: InputDecoration(
                    labelText: '电视 IP 地址',
                    hintText: defaultRemoteAddress.host,
                    hintStyle: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface
                          .withValues(alpha: 0.35),
                    ),
                  ),
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  onChanged: (_) => unawaited(_saveManualConnection()),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 100,
                child: TextField(
                  controller: _port,
                  decoration: InputDecoration(
                    labelText: '端口',
                    hintText: '${defaultRemoteAddress.port}',
                    hintStyle: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface
                          .withValues(alpha: 0.35),
                    ),
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(5),
                  ],
                  onChanged: (_) => unawaited(_saveManualConnection()),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text('留空时连接 ${defaultRemoteAddress.authority}；输入内容会自动保存。'),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: busy
                ? null
                : connected
                ? () => Get.back(result: true)
                : _connect,
            child: Text(
              busy
                  ? '正在连接…'
                  : connected
                  ? '返回选视频'
                  : '连接电视',
            ),
          ),
          if (_message != null ||
              (connectionError.isNotEmpty && _remote.needsPairing))
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(_message ?? connectionError),
            ),
          const SizedBox(height: 16),
          const Text('连接成功后会记住电视，下次自动连接。在手机点开视频即可在电视播放。电视的 B 站账号在电视内扫码登录。'),
        ],
      );
    }),
  );
}

class RemotePlaybackOverlay extends StatelessWidget {
  final Widget child;
  final ValueListenable<String> currentPage;
  const RemotePlaybackOverlay({
    required this.child,
    required this.currentPage,
    super.key,
  });
  @override
  Widget build(BuildContext context) {
    final remote = Get.find<RemotePlaybackController>();
    return ValueListenableBuilder<String>(
      valueListenable: currentPage,
      builder: (context, page, _) => Stack(
        children: [
          child,
          Positioned(
            top: 48,
            left: 16,
            right: 16,
            child: SafeArea(
              child: Obx(
                () => !remote.volumeFeedbackVisible.value
                    ? const SizedBox.shrink()
                    : IgnorePointer(
                        child: Center(
                          child: Theme(
                            data: ThemeUtils.darkTheme,
                            child: Material(
                              color: ThemeUtils
                                  .darkTheme
                                  .colorScheme
                                  .surfaceContainerHigh,
                              elevation: 6,
                              borderRadius: BorderRadius.circular(20),
                              child: Container(
                                constraints: const BoxConstraints(
                                  maxWidth: 280,
                                ),
                                padding: const EdgeInsets.all(16),
                                child: Semantics(
                                  liveRegion: true,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Row(
                                        children: [
                                          const Icon(
                                            Icons.tv_rounded,
                                            size: 20,
                                          ),
                                          const SizedBox(width: 8),
                                          const Expanded(child: Text('电视音量')),
                                          Text(
                                            remote.canAdjustVolume
                                                ? '${remote.televisionVolume}%'
                                                : '—',
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 10),
                                      LinearProgressIndicator(
                                        value: remote.canAdjustVolume
                                            ? remote.televisionVolume / 100
                                            : 0,
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        !remote.connected.value
                                            ? '电视连接中，手机音量未改变'
                                            : !remote.canAdjustVolume
                                            ? '电视音量暂不可调节'
                                            : remote.requestedVolume.value !=
                                                  null
                                            ? '正在调整电视音量'
                                            : remote.deviceName.value,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
              ),
            ),
          ),
          Positioned(
            right: 12,
            bottom: 76,
            child: SafeArea(
              child: Obx(
                () =>
                    (remote.controlsVisible.value ||
                        page == '/RemoteConnectionPage' ||
                        (page == '/videoV' && remote.remoteMode.value))
                    ? const SizedBox.shrink()
                    : Material(
                        elevation: 4,
                        borderRadius: BorderRadius.circular(24),
                        color: Theme.of(context).colorScheme.secondaryContainer,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(24),
                          onTap: () {
                            if (remote.remoteMode.value) {
                              unawaited(openTelevisionPlayback());
                            } else {
                              Get.to<void>(() => const RemoteConnectionPage());
                            }
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  remote.connected.value
                                      ? Icons.cast_connected
                                      : Icons.cast,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  remote.remoteMode.value
                                      ? (remote.connected.value
                                            ? (remote
                                                      .state
                                                      .value
                                                      .hasSponsorPrompt
                                                  ? '有片段可跳过'
                                                  : '电视遥控')
                                            : '电视待重连')
                                      : '连接电视',
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class RemoteVideoPlaceholder extends StatefulWidget {
  final double width;
  final double height;
  final int aid;
  final int cid;
  final bool isFullScreen;
  final Future<void> Function() onToggleFullScreen;

  const RemoteVideoPlaceholder({
    required this.width,
    required this.height,
    required this.aid,
    required this.cid,
    required this.isFullScreen,
    required this.onToggleFullScreen,
    super.key,
  });

  @override
  State<RemoteVideoPlaceholder> createState() => _RemoteVideoPlaceholderState();
}

class _RemoteVideoPlaceholderState extends State<RemoteVideoPlaceholder> {
  final _remote = Get.find<RemotePlaybackController>();
  late final Worker _sessionWatcher;
  double? _draftMs;
  double _dragStartX = 0;
  int _dragStartMs = 0;
  String? _dragPlaybackId;
  bool _committing = false;
  _RemoteSection? _panel;

  bool get _showingCurrentVideo =>
      widget.isFullScreen ||
      (_remote.state.value.aid == widget.aid &&
          _remote.state.value.cid == widget.cid) ||
      _remote.state.value.queue.any(
        (item) => item['aid'] == widget.aid && item['cid'] == widget.cid,
      );
  bool get _canControl =>
      _remote.connected.value &&
      _remote.state.value.aid > 0 &&
      _showingCurrentVideo &&
      _remote.state.value.playbackId.isNotEmpty &&
      _remote.state.value.status != 'TRANSITIONING';
  bool get _canSeek =>
      _canControl && _remote.state.value.durationMs > 0 && !_committing;

  String _time(int millis) {
    final seconds = millis ~/ 1000;
    final minutes = (seconds ~/ 60 % 60).toString().padLeft(2, '0');
    final remainder = (seconds % 60).toString().padLeft(2, '0');
    return seconds >= 3600
        ? '${seconds ~/ 3600}:$minutes:$remainder'
        : '${seconds ~/ 60}:$remainder';
  }

  @override
  void initState() {
    super.initState();
    _sessionWatcher = everAll([_remote.state, _remote.connected], (_) {
      if (_draftMs != null &&
          (!_canControl || _dragPlaybackId != _remote.state.value.playbackId)) {
        _cancelDrag();
      }
    });
  }

  @override
  void didUpdateWidget(covariant RemoteVideoPlaceholder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.isFullScreen) _panel = null;
    if (widget.aid != oldWidget.aid || widget.cid != oldWidget.cid) {
      _draftMs = null;
      _dragPlaybackId = null;
    }
  }

  @override
  void dispose() {
    _sessionWatcher.dispose();
    super.dispose();
  }

  void _beginSeek() {
    _dragStartMs = _remote.televisionPositionMs;
    _dragPlaybackId = _remote.state.value.playbackId;
    _draftMs = _dragStartMs.toDouble();
  }

  void _cancelDrag() {
    setState(() {
      _draftMs = null;
      _dragPlaybackId = null;
    });
  }

  Future<void> _commitSeek() async {
    if (!_canSeek ||
        _draftMs == null ||
        _dragPlaybackId != _remote.state.value.playbackId) {
      _cancelDrag();
      return;
    }
    final targetMs = _draftMs!.round();
    setState(() => _committing = true);
    try {
      await _remote.seekTo(targetMs);
    } finally {
      if (mounted) {
        setState(() {
          _committing = false;
          _draftMs = null;
          _dragPlaybackId = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Obx(() {
    final state = _remote.state.value;
    final currentVideo = _showingCurrentVideo;
    final durationMs = currentVideo ? state.durationMs : 0;
    final positionMs =
        (_draftMs?.round() ?? (currentVideo ? _remote.televisionPositionMs : 0))
            .clamp(
              0,
              math.max(0, durationMs),
            )
            .toInt();
    final changeSeconds = ((positionMs - _dragStartMs) / 1000).round();
    final status = !_remote.connected.value
        ? '连接恢复中 · 电视继续播放'
        : !currentVideo
        ? '正在切换到此视频…'
        : switch (state.status) {
            'PLAYING' => '正在电视播放',
            'PAUSED' => '电视已暂停',
            'TRANSITIONING' => '电视正在加载…',
            'ERROR' => '电视播放失败',
            _ => '已连接电视',
          };
    final controlTheme = ThemeUtils.darkTheme;
    return Theme(
      data: controlTheme,
      child: PopScope(
        canPop: !widget.isFullScreen && _panel == null,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          if (_panel != null) {
            setState(() => _panel = null);
          } else if (widget.isFullScreen) {
            unawaited(widget.onToggleFullScreen());
          }
        },
        child: SizedBox(
          width: widget.width,
          height: widget.height,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onDoubleTap: _panel == null && _canControl
                ? () => _remote.perform(
                    state.status == 'PLAYING' ? 'pause' : 'play',
                  )
                : null,
            onHorizontalDragStart: _panel == null && _canSeek
                ? (details) {
                    setState(() {
                      _beginSeek();
                      _dragStartX = details.globalPosition.dx;
                    });
                  }
                : null,
            onHorizontalDragUpdate: _panel == null && _canSeek
                ? (details) {
                    if (_draftMs == null ||
                        _dragPlaybackId != state.playbackId) {
                      return;
                    }
                    // The whole remote area is a relative seek surface: 8 logical pixels move 1 second.
                    // Do not map finger position to total duration; touching the remote area must not jump.
                    final movementMs =
                        (details.globalPosition.dx - _dragStartX) * 125;
                    setState(
                      () => _draftMs = (_dragStartMs + movementMs)
                          .clamp(0, state.durationMs)
                          .toDouble(),
                    );
                  }
                : null,
            onHorizontalDragEnd: _panel == null && _canSeek
                ? (_) => unawaited(_commitSeek())
                : null,
            onHorizontalDragCancel: _panel == null && _canSeek
                ? _cancelDrag
                : null,
            child: Stack(
              fit: StackFit.expand,
              clipBehavior: Clip.hardEdge,
              children: [
                const ColoredBox(color: Color(0xFF15161C)),
                if (widget.height >= 140)
                  Positioned(
                    top: 4,
                    left: 16,
                    right: 4,
                    child: Row(
                      children: [
                        if (widget.isFullScreen)
                          IconButton(
                            tooltip: '退出全屏',
                            onPressed: widget.onToggleFullScreen,
                            color: Colors.white,
                            icon: const Icon(Icons.arrow_back_rounded),
                          ),
                        const Icon(
                          Icons.cast_connected_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            widget.isFullScreen && state.title.isNotEmpty
                                ? '${state.title} · ${_remote.deviceName.value}'
                                : _remote.deviceName.value,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: widget.isFullScreen
                              ? () => setState(
                                  () => _panel = _RemoteSection.session,
                                )
                              : showRemoteControls,
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white,
                          ),
                          icon: const Icon(Icons.tune_rounded, size: 18),
                          label: Text(widget.isFullScreen ? '更多' : '遥控'),
                        ),
                      ],
                    ),
                  ),
                if (widget.height >= 190 && !state.hasSponsorPrompt)
                  Positioned(
                    top: widget.isFullScreen ? 56 : 48,
                    left: 16,
                    right: 16,
                    bottom: widget.isFullScreen ? 144 : 96,
                    child: Center(
                      child: _draftMs != null || _committing
                          ? IgnorePointer(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _committing
                                        ? '正在跳转…'
                                        : '${changeSeconds >= 0 ? '+' : '−'}${changeSeconds.abs()} 秒',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 24,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    '${_time(positionMs)} / ${_time(durationMs)} · 松手跳转',
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    if (widget.isFullScreen)
                                      IconButton(
                                        tooltip: '上一集',
                                        color: Colors.white,
                                        disabledColor: Colors.white38,
                                        onPressed: _canControl
                                            ? () => _remote.perform('previous')
                                            : null,
                                        icon: const Icon(
                                          Icons.skip_previous_rounded,
                                        ),
                                      ),
                                    if (widget.isFullScreen)
                                      const SizedBox(width: 24),
                                    IconButton.filledTonal(
                                      tooltip: state.status == 'PLAYING'
                                          ? '暂停电视'
                                          : '播放电视',
                                      iconSize: widget.isFullScreen ? 36 : 28,
                                      style: IconButton.styleFrom(
                                        minimumSize: Size.square(
                                          widget.isFullScreen ? 64 : 48,
                                        ),
                                      ),
                                      onPressed: _canControl
                                          ? () => _remote.perform(
                                              state.status == 'PLAYING'
                                                  ? 'pause'
                                                  : 'play',
                                            )
                                          : null,
                                      icon: Icon(
                                        state.status == 'PLAYING'
                                            ? Icons.pause_rounded
                                            : Icons.play_arrow_rounded,
                                      ),
                                    ),
                                    if (widget.isFullScreen)
                                      const SizedBox(width: 24),
                                    if (widget.isFullScreen)
                                      IconButton(
                                        tooltip: '下一集',
                                        color: Colors.white,
                                        disabledColor: Colors.white38,
                                        onPressed: _canControl
                                            ? () => _remote.perform('next')
                                            : null,
                                        icon: const Icon(
                                          Icons.skip_next_rounded,
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  widget.isFullScreen
                                      ? status
                                      : '$status · 横滑调进度',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                  ),
                                ),
                                if (widget.isFullScreen) ...[
                                  const SizedBox(height: 4),
                                  const Text(
                                    '左右滑动微调进度 · 双击播放 / 暂停',
                                    style: TextStyle(
                                      color: Colors.white60,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                    ),
                  ),
                Positioned(
                  left: 4,
                  right: 4,
                  bottom: 0,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          if (widget.height < 190)
                            IconButton(
                              onPressed: _canControl
                                  ? () => _remote.perform(
                                      state.status == 'PLAYING'
                                          ? 'pause'
                                          : 'play',
                                    )
                                  : null,
                              tooltip: state.status == 'PLAYING'
                                  ? '暂停电视'
                                  : '播放电视',
                              color: Colors.white,
                              disabledColor: Colors.white38,
                              icon: Icon(
                                state.status == 'PLAYING'
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                              ),
                            ),
                          Text(
                            '${_time(positionMs)} / ${_time(durationMs)}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                            ),
                          ),
                          const Spacer(),
                          if (!widget.isFullScreen || widget.height < 190)
                            IconButton(
                              onPressed: _canControl
                                  ? () => _remote.perform('next')
                                  : null,
                              tooltip: '下一集',
                              color: Colors.white,
                              disabledColor: Colors.white38,
                              icon: const Icon(Icons.skip_next_rounded),
                            ),
                          IconButton(
                            tooltip: widget.isFullScreen ? '退出全屏' : '全屏遥控',
                            onPressed: widget.onToggleFullScreen,
                            color: Colors.white,
                            icon: Icon(
                              widget.isFullScreen
                                  ? Icons.fullscreen_exit_rounded
                                  : Icons.fullscreen_rounded,
                            ),
                          ),
                        ],
                      ),
                      SliderTheme(
                        data: controlTheme.sliderTheme.copyWith(
                          activeTrackColor: controlTheme.colorScheme.primary,
                          thumbColor: controlTheme.colorScheme.primary,
                          trackHeight: 3,
                          trackShape: const RoundedRectSliderTrackShape(),
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 5,
                          ),
                          overlayShape: const RoundSliderOverlayShape(
                            overlayRadius: 16,
                          ),
                          inactiveTrackColor: Colors.white30,
                          disabledInactiveTrackColor: Colors.white24,
                        ),
                        child: SizedBox(
                          height: 48,
                          child: Slider(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            value: positionMs.toDouble(),
                            max: math.max(1, durationMs).toDouble(),
                            semanticFormatterCallback: (value) =>
                                _time(value.round()),
                            onChangeStart: _canSeek
                                ? (_) => setState(_beginSeek)
                                : null,
                            onChanged: _canSeek
                                ? (value) => setState(() => _draftMs = value)
                                : null,
                            onChangeEnd: _canSeek
                                ? (_) => unawaited(_commitSeek())
                                : null,
                          ),
                        ),
                      ),
                      if (widget.isFullScreen)
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              for (final section in _RemoteSection.values.where(
                                (section) => section != _RemoteSection.session,
                              ))
                                TextButton.icon(
                                  style: TextButton.styleFrom(
                                    foregroundColor: Colors.white,
                                  ),
                                  onPressed: () =>
                                      setState(() => _panel = section),
                                  icon: Icon(section.icon, size: 18),
                                  label: Text(switch (section) {
                                    _RemoteSection.speed =>
                                      '${state.speed}× 倍速',
                                    _RemoteSection.quality =>
                                      state.qualities['${state.qualityId}'] ??
                                          '画质',
                                    _RemoteSection.danmaku =>
                                      state.danmakuEnabled
                                          ? '弹幕 · 开'
                                          : '弹幕 · 关',
                                    _RemoteSection.volume =>
                                      '音量 ${state.volume}%',
                                    _ => section.label,
                                  }),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                if (_panel == null &&
                    widget.height >= 140 &&
                    (state.hasSponsorPrompt || state.sponsorSkipNotice != null))
                  Positioned(
                    left: 12,
                    right: 12,
                    top: widget.isFullScreen ? 64 : 48,
                    child: const _SponsorSkipPrompt(),
                  ),
                if (widget.isFullScreen && _panel != null) ...[
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => setState(() => _panel = null),
                      child: const ColoredBox(color: Color(0x55000000)),
                    ),
                  ),
                  Positioned(
                    top: 0,
                    right: 0,
                    bottom: 0,
                    width: math.min(360, widget.width * .55),
                    child: Theme(
                      data: controlTheme.copyWith(
                        sliderTheme: controlTheme.sliderTheme.copyWith(
                          trackHeight: 3,
                          trackShape: const RoundedRectSliderTrackShape(),
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 6,
                          ),
                          overlayShape: const RoundSliderOverlayShape(
                            overlayRadius: 16,
                          ),
                          trackGap: 0,
                        ),
                      ),
                      child: Material(
                        color: const Color(0xFF191A20),
                        borderRadius: const BorderRadius.horizontal(
                          left: Radius.circular(20),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: SafeArea(
                          left: false,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(
                                  left: 20,
                                  right: 4,
                                ),
                                child: Row(
                                  children: [
                                    Icon(_panel!.icon, size: 20),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        _panel!.label,
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: '关闭面板',
                                      onPressed: () =>
                                          setState(() => _panel = null),
                                      icon: const Icon(Icons.close_rounded),
                                    ),
                                  ],
                                ),
                              ),
                              const Divider(height: 1),
                              if (!_remote.connected.value ||
                                  state.status == 'TRANSITIONING' ||
                                  state.error != null ||
                                  _remote.error.value.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Text(
                                    !_remote.connected.value
                                        ? '连接恢复中…'
                                        : state.error ??
                                              (_remote.error.value.isNotEmpty
                                                  ? _remote.error.value
                                                  : '电视正在加载…'),
                                  ),
                                ),
                              Expanded(
                                child: LayoutBuilder(
                                  builder: (context, constraints) =>
                                      SingleChildScrollView(
                                        padding: const EdgeInsets.all(16),
                                        child: _RemoteSettingsSection(
                                          key: ValueKey(_panel),
                                          section: _panel!,
                                          expanded: true,
                                          episodeHeight: math.max(
                                            0,
                                            constraints.maxHeight - 32,
                                          ),
                                          onLeave: () async {
                                            setState(() => _panel = null);
                                            if (widget.isFullScreen) {
                                              await widget.onToggleFullScreen();
                                            }
                                          },
                                        ),
                                      ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  });
}

class RemoteSlider extends StatefulWidget {
  final double value;
  final double maximum;
  final double minimum;
  final int? divisions;
  final ValueChanged<double>? onCommitted;
  const RemoteSlider({
    required this.value,
    required this.maximum,
    this.minimum = 0,
    this.divisions,
    this.onCommitted,
    super.key,
  });
  @override
  State<RemoteSlider> createState() => _RemoteSliderState();
}

class _RemoteSliderState extends State<RemoteSlider> {
  double? _draft;
  bool _dragging = false;
  @override
  void didUpdateWidget(covariant RemoteSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_dragging) _draft = null;
  }

  @override
  Widget build(BuildContext context) => Slider(
    value: (_draft ?? widget.value).clamp(widget.minimum, widget.maximum),
    min: widget.minimum,
    max: widget.maximum,
    divisions: widget.divisions,
    onChanged: widget.onCommitted == null
        ? null
        : (value) => setState(() {
            _dragging = true;
            _draft = value;
          }),
    onChangeEnd: widget.onCommitted == null
        ? null
        : (value) {
            _dragging = false;
            widget.onCommitted!(value);
          },
  );
}

class _PlaybackProgressControl extends StatefulWidget {
  final int positionMs;
  final int durationMs;
  final Future<void> Function(int)? onSeek;

  const _PlaybackProgressControl({
    required this.positionMs,
    required this.durationMs,
    required this.onSeek,
    super.key,
  });

  @override
  State<_PlaybackProgressControl> createState() =>
      _PlaybackProgressControlState();
}

class _PlaybackProgressControlState extends State<_PlaybackProgressControl> {
  double? _draftMs;
  double _dragOriginY = 0;
  double _lastDragX = 0;
  int _precision = 0;
  bool _dragging = false;
  bool _committing = false;

  bool get _enabled =>
      widget.onSeek != null && widget.durationMs > 0 && !_committing;
  int get _displayPositionMs => (_draftMs ?? widget.positionMs.toDouble())
      .clamp(0, math.max(0, widget.durationMs))
      .round();

  String _formatTime(int millis) {
    final seconds = millis ~/ 1000;
    final minutes = (seconds ~/ 60 % 60).toString().padLeft(2, '0');
    final remainder = (seconds % 60).toString().padLeft(2, '0');
    return seconds >= 3600
        ? '${seconds ~/ 3600}:$minutes:$remainder'
        : '${seconds ~/ 60}:$remainder';
  }

  @override
  void didUpdateWidget(covariant _PlaybackProgressControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.onSeek == null && _dragging) {
      _dragging = false;
      _draftMs = null;
      _precision = 0;
    }
  }

  void _cancelDrag() {
    setState(() {
      _dragging = false;
      _draftMs = null;
      _precision = 0;
    });
  }

  Future<void> _commitSeek() async {
    final seek = widget.onSeek;
    if (!_enabled || _draftMs == null || seek == null) return;
    final positionMs = _displayPositionMs;
    setState(() {
      _dragging = false;
      _committing = true;
      _precision = 0;
    });
    try {
      await seek(positionMs);
    } finally {
      if (mounted) {
        setState(() {
          _committing = false;
          _draftMs = null;
        });
      }
    }
  }

  void _stepOneSecond(int direction) {
    if (!_enabled) return;
    _draftMs = (_displayPositionMs + direction * 1000)
        .clamp(0, widget.durationMs)
        .toDouble();
    unawaited(_commitSeek());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final duration = math.max(1, widget.durationMs).toDouble();
    return Column(
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            const trackInset = 12.0;
            final trackWidth = math.max(
              1.0,
              constraints.maxWidth - trackInset * 2,
            );
            double positionAt(double x) {
              final fraction = ((x - trackInset) / trackWidth).clamp(0.0, 1.0);
              return (rtl ? 1 - fraction : fraction) * duration;
            }

            return Semantics(
              label: '播放进度',
              value:
                  '${_formatTime(_displayPositionMs)}，共 ${_formatTime(widget.durationMs)}',
              enabled: _enabled,
              increasedValue: _formatTime(
                (_displayPositionMs + 1000).clamp(0, widget.durationMs),
              ),
              decreasedValue: _formatTime(
                (_displayPositionMs - 1000).clamp(0, widget.durationMs),
              ),
              onIncrease: _enabled ? () => _stepOneSecond(1) : null,
              onDecrease: _enabled ? () => _stepOneSecond(-1) : null,
              child: ExcludeSemantics(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  dragStartBehavior: DragStartBehavior.down,
                  onTapUp: _enabled
                      ? (details) {
                          _draftMs = positionAt(details.localPosition.dx);
                          unawaited(_commitSeek());
                        }
                      : null,
                  onHorizontalDragStart: _enabled
                      ? (details) {
                          setState(() {
                            _dragging = true;
                            _precision = 0;
                            _dragOriginY = details.localPosition.dy;
                            _lastDragX = details.localPosition.dx;
                            _draftMs = positionAt(details.localPosition.dx);
                          });
                        }
                      : null,
                  onHorizontalDragUpdate: _enabled
                      ? (details) {
                          if (!_dragging) return;
                          final distanceBelowTrack =
                              details.localPosition.dy - _dragOriginY;
                          final precision = distanceBelowTrack >= 96
                              ? 2
                              : distanceBelowTrack >= 48
                              ? 1
                              : 0;
                          final normalSpeed = duration / trackWidth;
                          final millisecondsPerPixel = switch (precision) {
                            2 => math.min(normalSpeed / 10, 100.0),
                            1 => math.min(normalSpeed / 4, 500.0),
                            _ => normalSpeed,
                          };
                          // Integrate horizontal movement so changing precision never jumps the target.
                          final movement =
                              (details.localPosition.dx - _lastDragX) *
                              (rtl ? -1 : 1);
                          _lastDragX = details.localPosition.dx;
                          setState(() {
                            _precision = precision;
                            _draftMs =
                                (_draftMs! + movement * millisecondsPerPixel)
                                    .clamp(0, duration);
                          });
                        }
                      : null,
                  onHorizontalDragEnd: _enabled
                      ? (_) => unawaited(_commitSeek())
                      : null,
                  onHorizontalDragCancel: _enabled ? _cancelDrag : null,
                  child: SizedBox(
                    height: 48,
                    child: IgnorePointer(
                      child: Slider(
                        padding: const EdgeInsets.symmetric(
                          horizontal: trackInset,
                        ),
                        value: _displayPositionMs.toDouble(),
                        max: duration,
                        onChanged: widget.onSeek == null ? null : (_) {},
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _formatTime(_displayPositionMs),
              style: theme.textTheme.bodyMedium,
            ),
            Text(
              _formatTime(widget.durationMs),
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          _committing
              ? '正在跳转…'
              : !_enabled
              ? '等待视频就绪'
              : switch (_precision) {
                  2 => '精细调整 · 松手跳转',
                  1 => '慢速调整 · 继续下移可更精细',
                  _ => '横向拖动定位 · 下移手指精调',
                },
          style: theme.textTheme.bodySmall?.copyWith(
            color: _precision > 0
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _SponsorSkipPrompt extends StatelessWidget {
  const _SponsorSkipPrompt();

  @override
  Widget build(BuildContext context) {
    final remote = Get.find<RemotePlaybackController>();
    return Obx(() {
      final state = remote.state.value;
      if (!remote.connected.value || !remote.remoteMode.value) {
        return const SizedBox.shrink();
      }
      final prompt = state.hasSponsorPrompt;
      final notice = state.sponsorSkipNotice;
      if (!prompt && notice == null) return const SizedBox.shrink();
      final seconds = ((state.sponsorEndMs - state.positionMs + 999) ~/ 1000)
          .clamp(0, 2147483647);
      final theme = Theme.of(context);
      Future<void> handleSegment(String action) async {
        final current = remote.state.value;
        if (current.playbackId != state.playbackId ||
            current.sponsorSegmentId != state.sponsorSegmentId ||
            !current.hasSponsorPrompt) {
          return;
        }
        await remote.perform(action, {'segmentId': state.sponsorSegmentId});
      }

      return Material(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  prompt
                      ? '${state.sponsorCategory == 'sponsor' ? '赞助片段' : '可跳过片段'} · 剩余 $seconds 秒'
                      : notice!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
              ),
              if (prompt) ...[
                TextButton(
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 36),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () => handleSegment('skipSponsor'),
                  child: const Text('跳过片段'),
                ),
                IconButton(
                  tooltip: '本次不跳',
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints.tightFor(
                    width: 36,
                    height: 36,
                  ),
                  onPressed: () => handleSegment('dismissSponsor'),
                  icon: const Icon(Icons.close_rounded, size: 18),
                ),
              ],
            ],
          ),
        ),
      );
    });
  }
}

enum _RemoteSection {
  episodes('选集', Icons.playlist_play_rounded),
  speed('倍速', Icons.speed_rounded),
  quality('画质', Icons.high_quality_outlined),
  danmaku('弹幕', Icons.subtitles_outlined),
  volume('音量', Icons.volume_up_rounded),
  sponsor('广告跳过', Icons.fast_forward_rounded),
  session('更多', Icons.more_horiz_rounded);

  const _RemoteSection(this.label, this.icon);
  final String label;
  final IconData icon;
}

// Both remote surfaces send the same commands and display the receiver's confirmed state.
class _RemoteSettingsSection extends StatelessWidget {
  const _RemoteSettingsSection({
    required this.section,
    this.expanded = false,
    this.episodeHeight = 140,
    this.onLeave,
    super.key,
  });

  final _RemoteSection section;
  final bool expanded;
  final double episodeHeight;
  final Future<void> Function()? onLeave;

  @override
  Widget build(BuildContext context) {
    final remote = Get.find<RemotePlaybackController>();
    return Obx(() {
      final state = remote.state.value;
      final ready =
          remote.connected.value &&
          state.aid > 0 &&
          state.playbackId.isNotEmpty &&
          state.status != 'TRANSITIONING';
      switch (section) {
        case _RemoteSection.volume:
          return const _TelevisionVolumeControls();
        case _RemoteSection.sponsor:
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('电视赞助片段'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final mode in const {
                    'prompt': '提示跳过',
                    'auto': '自动跳过',
                    'off': '关闭',
                  }.entries)
                    ChoiceChip(
                      label: Text(mode.value),
                      selected: state.sponsorSkipMode == mode.key,
                      onSelected: ready && state.sponsorSkipMode != null
                          ? (_) => remote.perform('sponsorSkipMode', {
                              'mode': mode.key,
                            })
                          : null,
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                state.sponsorSkipMode == null
                    ? '电视版本暂不支持，请更新电视 APK'
                    : '自动模式由电视执行，手机锁屏或断开后仍生效；仅跳过社区标注的赞助片段。',
              ),
              TextButton(
                onPressed: () => Get.to<void>(() => const SponsorBlockPage()),
                child: const Text('手机本地播放的空降助手设置'),
              ),
            ],
          );
        case _RemoteSection.danmaku:
          final styleControls = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('字号 ${(state.danmakuScale * 100).round()}%'),
              RemoteSlider(
                value: state.danmakuScale,
                minimum: 0.5,
                maximum: 4,
                divisions: 35,
                onCommitted: ready && state.danmakuEnabled
                    ? (value) => remote.perform('danmakuSettings', {
                        'scale': value,
                      })
                    : null,
              ),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('显示区域'),
              ),
              Wrap(
                spacing: 8,
                children: [
                  for (final area in {
                    0.25: '1/4 屏',
                    0.5: '半屏',
                    0.75: '3/4 屏',
                    1.0: '全屏',
                  }.entries)
                    ChoiceChip(
                      label: Text(area.value),
                      selected: (state.danmakuArea - area.key).abs() < 0.01,
                      onSelected: ready && state.danmakuEnabled
                          ? (_) => remote.perform('danmakuSettings', {
                              'area': area.key,
                            })
                          : null,
                    ),
                ],
              ),
              Text('不透明度 ${(state.danmakuOpacity * 100).round()}%'),
              RemoteSlider(
                value: state.danmakuOpacity,
                minimum: 0.1,
                maximum: 1,
                divisions: 9,
                onCommitted: ready && state.danmakuEnabled
                    ? (value) => remote.perform('danmakuSettings', {
                        'opacity': value,
                      })
                    : null,
              ),

              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('更多设置'),
                subtitle: const Text('弹幕类型、密度'),
                children: [
                  const SizedBox(height: 8),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('弹幕类型'),
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final type in {
                        'rolling': '滚动',
                        'top': '顶部固定',
                        'bottom': '底部固定',
                      }.entries)
                        FilterChip(
                          label: Text(type.value),
                          selected: state.danmakuTypes.contains(type.key),
                          onSelected: ready && state.danmakuEnabled
                              ? (selected) {
                                  final types = state.danmakuTypes;
                                  if (selected) {
                                    types.add(type.key);
                                  } else {
                                    types.remove(type.key);
                                  }
                                  remote.perform('danmakuSettings', {
                                    'types': types.toList(),
                                  });
                                }
                              : null,
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('密度 ${(state.danmakuDensity * 100).round()}%'),
                  RemoteSlider(
                    value: state.danmakuDensity,
                    minimum: 0.2,
                    maximum: 1,
                    divisions: 4,
                    onCommitted: ready && state.danmakuEnabled
                        ? (value) => remote.perform('danmakuSettings', {
                            'density': value,
                          })
                        : null,
                  ),
                  const Text('密度越低，密集场景显示的弹幕越少。'),
                  const SizedBox(height: 12),
                ],
              ),
            ],
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('电视弹幕'),
                value: state.danmakuEnabled,
                onChanged: ready
                    ? (enabled) =>
                          remote.perform('danmaku', {'enabled': enabled})
                    : null,
              ),
              if (state.supportsDanmakuSettings)
                if (expanded)
                  styleControls
                else
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: const Text('弹幕样式'),
                    children: [styleControls],
                  )
              else if (state.aid > 0)
                const Text('更新电视端后，可在这里调节弹幕样式。'),
            ],
          );
        case _RemoteSection.speed:
          return Wrap(
            spacing: 8,
            children: [
              for (final speed in [0.5, 1.0, 1.25, 1.5, 2.0])
                ChoiceChip(
                  label: Text('$speed×'),
                  selected: state.speed == speed,
                  onSelected: ready
                      ? (_) => remote.perform('speed', {'value': speed})
                      : null,
                ),
            ],
          );
        case _RemoteSection.quality:
          if (state.qualities.isEmpty) return const Text('电视尚未返回可用画质');
          return Wrap(
            spacing: 8,
            children: [
              for (final quality in state.qualities.entries)
                ChoiceChip(
                  label: Text(quality.value),
                  selected: '${state.qualityId}' == quality.key,
                  onSelected: ready
                      ? (_) => remote.perform('quality', {
                          'value': int.parse(quality.key),
                        })
                      : null,
                ),
            ],
          );
        case _RemoteSection.episodes:
          final queue = state.queue;
          if (queue.isEmpty) return const Text('当前视频没有其他分集');
          return SizedBox(
            height: episodeHeight,
            child: ListView.builder(
              itemCount: queue.length,
              itemBuilder: (context, index) {
                final item = queue[index];
                final selected =
                    item['aid'] == state.aid && item['cid'] == state.cid;
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  selected: selected,
                  selectedTileColor: Theme.of(context)
                      .colorScheme
                      .secondaryContainer,
                  leading: selected
                      ? const Icon(Icons.equalizer_rounded, size: 20)
                      : Text('${index + 1}'.padLeft(2, '0')),
                  title: Text(
                    '${item['title']}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: ready
                      ? () => remote.perform('episode', {
                          'aid': item['aid'],
                          'cid': item['cid'],
                        })
                      : null,
                );
              },
            ),
          );
        case _RemoteSection.session:
          return Wrap(
            spacing: 8,
            children: [
              OutlinedButton(
                onPressed: ready ? () => remote.perform('back') : null,
                child: const Text('电视返回 / 停止播放'),
              ),
              TextButton(
                onPressed: () async {
                  await onLeave!();
                  await remote.disconnect();
                },
                child: const Text('断开遥控，电视继续播'),
              ),
              TextButton(
                onPressed: () async {
                  await onLeave!();
                  Get.to<void>(() => const RemoteConnectionPage());
                },
                child: const Text('重新连接 / 换电视'),
              ),
            ],
          );
      }
    });
  }
}

class RemoteControls extends StatelessWidget {
  const RemoteControls({super.key});

  @override
  Widget build(BuildContext context) {
    final remote = Get.find<RemotePlaybackController>();
    return Material(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        child: Obx(() {
          final state = remote.state.value;
          final ready =
              remote.connected.value &&
              state.aid > 0 &&
              state.playbackId.isNotEmpty &&
              state.status != 'TRANSITIONING';
          final queue = state.queue;
          return ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * .85,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    remote.deviceName.value,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    state.title.isEmpty ? '返回手机列表，点选要在电视播放的视频' : state.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (!remote.connected.value) const Text('连接已断开；电视会继续播放。'),
                  if (state.status == 'TRANSITIONING')
                    const LinearProgressIndicator(),
                  if (state.error != null || remote.error.value.isNotEmpty)
                    Text(
                      state.error ?? remote.error.value,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  _PlaybackProgressControl(
                    key: ValueKey(state.playbackId),
                    positionMs: remote.televisionPositionMs,
                    durationMs: state.durationMs,
                    onSeek: ready && state.durationMs > 0
                        ? remote.seekTo
                        : null,
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        tooltip: '上一集',
                        onPressed: ready
                            ? () => remote.perform('previous')
                            : null,
                        icon: const Icon(Icons.skip_previous),
                      ),
                      IconButton(
                        tooltip: state.status == 'PLAYING' ? '暂停' : '播放',
                        iconSize: 40,
                        onPressed: ready
                            ? () => remote.perform(
                                state.status == 'PLAYING' ? 'pause' : 'play',
                              )
                            : null,
                        icon: Icon(
                          state.status == 'PLAYING'
                              ? Icons.pause_circle
                              : Icons.play_circle,
                        ),
                      ),
                      IconButton(
                        tooltip: '下一集',
                        onPressed: ready ? () => remote.perform('next') : null,
                        icon: const Icon(Icons.skip_next),
                      ),
                    ],
                  ),
                  const _SponsorSkipPrompt(),
                  const _TelevisionVolumeControls(),
                  const _RemoteSettingsSection(section: _RemoteSection.sponsor),
                  const _RemoteSettingsSection(section: _RemoteSection.danmaku),
                  const _RemoteSettingsSection(section: _RemoteSection.speed),
                  const _RemoteSettingsSection(section: _RemoteSection.quality),
                  if (queue.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const Text('选集'),
                    const _RemoteSettingsSection(
                      section: _RemoteSection.episodes,
                    ),
                  ],
                  const SizedBox(height: 12),
                  _RemoteSettingsSection(
                    section: _RemoteSection.session,
                    onLeave: () async {
                      Get.back();
                    },
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _TelevisionVolumeControls extends StatefulWidget {
  const _TelevisionVolumeControls();

  @override
  State<_TelevisionVolumeControls> createState() =>
      _TelevisionVolumeControlsState();
}

class _TelevisionVolumeControlsState extends State<_TelevisionVolumeControls> {
  int? _draft;

  @override
  Widget build(BuildContext context) {
    final remote = Get.find<RemotePlaybackController>();
    final theme = Theme.of(context);
    return Obx(() {
      final enabled = remote.canAdjustVolume;
      final volume = enabled
          ? (_draft ?? remote.televisionVolume)
          : remote.state.value.volume;
      final pending = remote.requestedVolume.value != null;
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.tv_rounded, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('电视音量', style: theme.textTheme.titleMedium),
                      Text(
                        remote.state.value.volumeMode == 'player'
                            ? '播放器音量 · 手机音量不变'
                            : '手机音量保持不变',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Semantics(
                  label: '电视音量',
                  value: enabled ? '$volume%' : '暂不可调节',
                  child: Text(
                    enabled ? '$volume%' : '—',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: enabled ? theme.colorScheme.primary : null,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                IconButton.filledTonal(
                  tooltip: '电视音量减 1%',
                  onPressed: enabled && volume > 0
                      ? () => remote.adjustTelevisionVolume(-1)
                      : null,
                  icon: const Icon(Icons.remove_rounded),
                ),
                Expanded(
                  child: Slider(
                    value: volume.toDouble(),
                    max: 100,
                    divisions: 100,
                    label: '$volume%',
                    semanticFormatterCallback: (value) => '${value.round()}%',
                    onChanged: enabled
                        ? (value) {
                            setState(() => _draft = value.round());
                            remote.setTelevisionVolume(
                              value.round(),
                              dragging: true,
                            );
                          }
                        : null,
                    onChangeEnd: enabled
                        ? (value) {
                            remote.setTelevisionVolume(value.round());
                            setState(() => _draft = null);
                          }
                        : null,
                  ),
                ),
                IconButton.filledTonal(
                  tooltip: '电视音量加 1%',
                  onPressed: enabled && volume < 100
                      ? () => remote.adjustTelevisionVolume(1)
                      : null,
                  icon: const Icon(Icons.add_rounded),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    !remote.connected.value
                        ? '电视未连接'
                        : !enabled
                        ? '等待电视开始播放'
                        : _draft != null
                        ? '松手应用 · 微调每次 1%'
                        : pending
                        ? '正在同步到电视…'
                        : '实体音量键每次 1%',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed:
                      enabled &&
                          (volume > 0 || remote.canRestoreTelevisionVolume)
                      ? remote.toggleTelevisionMute
                      : null,
                  icon: Icon(
                    volume == 0
                        ? Icons.volume_up_rounded
                        : Icons.volume_off_rounded,
                    size: 20,
                  ),
                  label: Text(
                    volume > 0
                        ? '静音'
                        : remote.canRestoreTelevisionVolume
                        ? '恢复'
                        : '已静音',
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    });
  }
}
