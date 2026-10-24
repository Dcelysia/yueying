import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import 'remote_playback_controller.dart';
import 'remote_playback_state.dart';
import 'tv_connection_page.dart';

bool _canControl(
  RemotePlaybackController remote,
  RemotePlaybackState snapshot,
) =>
    remote.connected.value &&
    remote.remoteMode.value &&
    snapshot.aid > 0 &&
    snapshot.playbackId.isNotEmpty &&
    snapshot.status != 'TRANSITIONING' &&
    remote.state.value.status != 'TRANSITIONING' &&
    remote.state.value.playbackId == snapshot.playbackId;

bool _hasAdjacentEpisode(RemotePlaybackState state, int step) {
  final queue = state.queue;
  final currentIndex = queue.indexWhere(
    (item) => item['aid'] == state.aid && item['cid'] == state.cid,
  );
  final targetIndex = currentIndex + step;
  return currentIndex >= 0 && targetIndex >= 0 && targetIndex < queue.length;
}

void _send(
  RemotePlaybackController remote,
  RemotePlaybackState snapshot,
  String action, [
  Map<String, dynamic> payload = const {},
]) {
  if (_canControl(remote, snapshot)) remote.perform(action, payload);
}

String televisionTime(int milliseconds) {
  final seconds = milliseconds.clamp(0, 2147483647) ~/ 1000;
  final minutes = (seconds ~/ 60 % 60).toString().padLeft(2, '0');
  final remainder = (seconds % 60).toString().padLeft(2, '0');
  return seconds >= 3600
      ? '${seconds ~/ 3600}:$minutes:$remainder'
      : '${seconds ~/ 60}:$remainder';
}

/// The same dark receiver placeholder used by the Android video page.
class TvVideoPlaceholder extends StatefulWidget {
  const TvVideoPlaceholder({super.key, this.isFullScreen = false});
  final bool isFullScreen;

  @override
  State<TvVideoPlaceholder> createState() => _TvVideoPlaceholderState();
}

class _TvVideoPlaceholderState extends State<TvVideoPlaceholder> {
  final remote = Get.find<RemotePlaybackController>();
  double? _draftPosition;
  double _dragStartX = 0;
  int _dragStartMs = 0;
  String? _dragPlaybackId;
  Worker? _sessionWatcher;
  TvControlSection? _panel;
  bool _openingFullScreen = false;

  @override
  void initState() {
    super.initState();
    _sessionWatcher = everAll([remote.state, remote.connected], (_) {
      if (_draftPosition != null &&
          (!remote.connected.value ||
              remote.state.value.status == 'TRANSITIONING' ||
              remote.state.value.playbackId != _dragPlaybackId)) {
        _cancelDrag();
      }
    });
  }

  @override
  void dispose() {
    _sessionWatcher?.dispose();
    super.dispose();
  }

  void _cancelDrag() {
    if (!mounted) return;
    setState(() {
      _draftPosition = null;
      _dragPlaybackId = null;
    });
  }

  Future<void> _openFullScreen() async {
    if (widget.isFullScreen) {
      Navigator.of(context).pop();
      return;
    }
    if (_openingFullScreen) return;
    _openingFullScreen = true;
    try {
      await SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => const Scaffold(
            key: ValueKey('tv-fullscreen-page'),
            backgroundColor: Color(0xFF15161C),
            body: SafeArea(child: TvVideoPlaceholder(isFullScreen: true)),
          ),
        ),
      );
    } finally {
      // The application is normally free to rotate; fullscreen does not change
      // playback or impose a permanent orientation on browsing pages.
      await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      _openingFullScreen = false;
    }
  }

  void _openSection(TvControlSection section) {
    if (widget.isFullScreen) {
      setState(() => _panel = section);
    } else {
      showTvRemoteSettings(context);
    }
  }

  @override
  Widget build(BuildContext context) => Obx(() {
    final snapshot = remote.state.value;
    final ready = _canControl(remote, snapshot);
    final canSeek = ready && snapshot.durationMs > 0;
    final label = !remote.connected.value
        ? '连接已断开'
        : snapshot.aid <= 0
        ? '等待选择视频'
        : switch (snapshot.status) {
            'PLAYING' => '正在电视播放',
            'PAUSED' => '电视已暂停',
            'TRANSITIONING' => '电视正在加载…',
            'ERROR' => '电视播放失败',
            _ => '已连接电视',
          };
    final darkTheme = ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: Theme.of(context).colorScheme.primary,
        brightness: Brightness.dark,
      ),
    );
    return Theme(
      data: darkTheme,
      child: PopScope(
        canPop: _panel == null,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && _panel != null) setState(() => _panel = null);
        },
        child: ColoredBox(
          color: const Color(0xFF15161C),
          child: LayoutBuilder(
            builder: (context, constraints) => Stack(
              fit: StackFit.expand,
              children: [
                // The seek surface is a sibling of the controls so their taps
                // never wait for the background double-tap recognizer.
                Positioned.fill(
                  top: widget.isFullScreen ? 56 : 44,
                  bottom: widget.isFullScreen ? 144 : 80,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onDoubleTap: ready
                        ? () => _send(
                            remote,
                            snapshot,
                            snapshot.status == 'PLAYING' ? 'pause' : 'play',
                          )
                        : null,
                    onHorizontalDragStart: canSeek
                        ? (details) {
                            _dragStartX = details.globalPosition.dx;
                            _dragStartMs = remote.televisionPositionMs;
                            _dragPlaybackId = snapshot.playbackId;
                            setState(
                              () => _draftPosition = _dragStartMs.toDouble(),
                            );
                          }
                        : null,
                    onHorizontalDragUpdate: canSeek
                        ? (details) {
                            if (_dragPlaybackId != snapshot.playbackId ||
                                !_canControl(remote, snapshot)) {
                              return;
                            }
                            final movementMs =
                                (details.globalPosition.dx - _dragStartX) * 125;
                            setState(() {
                              _draftPosition = (_dragStartMs + movementMs)
                                  .clamp(0, snapshot.durationMs)
                                  .toDouble();
                            });
                          }
                        : null,
                    onHorizontalDragEnd: canSeek
                        ? (_) {
                            final position = _draftPosition;
                            final session = _dragPlaybackId;
                            _cancelDrag();
                            if (position != null &&
                                session == snapshot.playbackId &&
                                _canControl(remote, snapshot)) {
                              remote.seekTo(position.round());
                            }
                          }
                        : null,
                    onHorizontalDragCancel: _cancelDrag,
                  ),
                ),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 4,
                  child: Row(
                    children: [
                      if (widget.isFullScreen)
                        IconButton(
                          tooltip: '退出全屏',
                          color: Colors.white,
                          onPressed: _openFullScreen,
                          icon: const Icon(Icons.arrow_back_rounded),
                        )
                      else
                        const BackButton(color: Colors.white),
                      const Icon(
                        Icons.cast_connected_rounded,
                        size: 18,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.isFullScreen && snapshot.title.isNotEmpty
                              ? '${snapshot.title} · ${remote.deviceName.value}'
                              : remote.deviceName.value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () => _openSection(TvControlSection.session),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                        ),
                        icon: const Icon(Icons.tune_rounded, size: 18),
                        label: Text(widget.isFullScreen ? '更多' : '遥控'),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  top: widget.isFullScreen ? 56 : 44,
                  left: 16,
                  right: 16,
                  bottom: widget.isFullScreen ? 144 : 80,
                  child:
                      snapshot.hasSponsorPrompt ||
                          snapshot.sponsorSkipNotice != null
                      ? SingleChildScrollView(
                          child: _SponsorPrompt(
                            remote: remote,
                            state: snapshot,
                            enabled: ready,
                          ),
                        )
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (_draftPosition == null &&
                                constraints.maxHeight >= 200)
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  if (widget.isFullScreen) ...[
                                    IconButton(
                                      tooltip: '上一集',
                                      onPressed:
                                          ready &&
                                              _hasAdjacentEpisode(snapshot, -1)
                                          ? () => _send(
                                              remote,
                                              snapshot,
                                              'previous',
                                            )
                                          : null,
                                      icon: const Icon(
                                        Icons.skip_previous_rounded,
                                      ),
                                    ),
                                    const SizedBox(width: 24),
                                  ],
                                  IconButton.filledTonal(
                                    tooltip: snapshot.status == 'PLAYING'
                                        ? '暂停电视'
                                        : '继续播放',
                                    iconSize: widget.isFullScreen ? 36 : 28,
                                    style: IconButton.styleFrom(
                                      minimumSize: Size.square(
                                        widget.isFullScreen ? 64 : 48,
                                      ),
                                    ),
                                    onPressed: ready
                                        ? () => _send(
                                            remote,
                                            snapshot,
                                            snapshot.status == 'PLAYING'
                                                ? 'pause'
                                                : 'play',
                                          )
                                        : null,
                                    icon: Icon(
                                      snapshot.status == 'PLAYING'
                                          ? Icons.pause_rounded
                                          : Icons.play_arrow_rounded,
                                    ),
                                  ),
                                  if (widget.isFullScreen) ...[
                                    const SizedBox(width: 24),
                                    IconButton(
                                      tooltip: '下一集',
                                      onPressed:
                                          ready &&
                                              _hasAdjacentEpisode(snapshot, 1)
                                          ? () =>
                                                _send(remote, snapshot, 'next')
                                          : null,
                                      icon: const Icon(Icons.skip_next_rounded),
                                    ),
                                  ],
                                ],
                              ),
                            const SizedBox(height: 4),
                            Text(
                              _draftPosition == null
                                  ? label
                                  : '${((_draftPosition! - _dragStartMs) / 1000).round()} 秒 · 松手跳转',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                            if (constraints.maxHeight >= 240)
                              const Text(
                                '左右滑动微调进度 · 双击播放 / 暂停',
                                style: TextStyle(
                                  color: Colors.white60,
                                  fontSize: 12,
                                ),
                              ),
                          ],
                        ),
                ),
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 0,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _ProgressControl(
                        remote: remote,
                        state: snapshot,
                        enabled: ready,
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (constraints.maxHeight < 200)
                              IconButton(
                                tooltip: snapshot.status == 'PLAYING'
                                    ? '暂停电视'
                                    : '继续播放',
                                onPressed: ready
                                    ? () => _send(
                                        remote,
                                        snapshot,
                                        snapshot.status == 'PLAYING'
                                            ? 'pause'
                                            : 'play',
                                      )
                                    : null,
                                icon: Icon(
                                  snapshot.status == 'PLAYING'
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                ),
                              ),
                            if (!widget.isFullScreen ||
                                constraints.maxHeight < 200)
                              IconButton(
                                tooltip: '下一集',
                                onPressed:
                                    ready && _hasAdjacentEpisode(snapshot, 1)
                                    ? () => _send(remote, snapshot, 'next')
                                    : null,
                                icon: const Icon(Icons.skip_next_rounded),
                              ),
                            IconButton(
                              tooltip: widget.isFullScreen ? '退出全屏' : '全屏遥控',
                              onPressed: _openFullScreen,
                              icon: Icon(
                                widget.isFullScreen
                                    ? Icons.fullscreen_exit_rounded
                                    : Icons.fullscreen_rounded,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (widget.isFullScreen)
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              for (final section in TvControlSection.values)
                                if (section != TvControlSection.session)
                                  TextButton.icon(
                                    onPressed: () => _openSection(section),
                                    style: TextButton.styleFrom(
                                      foregroundColor: Colors.white,
                                    ),
                                    icon: Icon(section.icon, size: 18),
                                    label: Text(switch (section) {
                                      TvControlSection.speed =>
                                        '${snapshot.speed}× 倍速',
                                      TvControlSection.quality =>
                                        snapshot.qualities['${snapshot.qualityId}'] ??
                                            '画质',
                                      TvControlSection.danmaku =>
                                        snapshot.danmakuEnabled
                                            ? '弹幕 · 开'
                                            : '弹幕 · 关',
                                      TvControlSection.volume =>
                                        '音量 ${remote.televisionVolume}%',
                                      _ => section.label,
                                    }),
                                  ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                if (widget.isFullScreen && _panel != null) ...[
                  Positioned.fill(
                    child: GestureDetector(
                      onTap: () => setState(() => _panel = null),
                      behavior: HitTestBehavior.opaque,
                      child: const ColoredBox(color: Color(0x55000000)),
                    ),
                  ),
                  Positioned(
                    top: 0,
                    right: 0,
                    bottom: 0,
                    width: constraints.maxWidth * .55 > 360
                        ? 360
                        : constraints.maxWidth * .55,
                    child: Material(
                      key: const ValueKey('tv-fullscreen-settings'),
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
                            Expanded(
                              child: LayoutBuilder(
                                builder: (context, panelConstraints) =>
                                    SingleChildScrollView(
                                      child: TvControlsPanel(
                                        key: ValueKey(
                                          '${_panel!.name}:${snapshot.playbackId}',
                                        ),
                                        initialSection: _panel!,
                                        expanded: true,
                                        episodeHeight:
                                            (panelConstraints.maxHeight - 48)
                                                .clamp(0, double.infinity),
                                        onLeave: () =>
                                            Navigator.of(context).pop(),
                                      ),
                                    ),
                              ),
                            ),
                          ],
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

Future<void> showTvRemoteSettings(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .8,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      const Expanded(child: Text('电视遥控')),
                      IconButton(
                        tooltip: '关闭遥控设置',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                const TvControlsPanel(initialSection: TvControlSection.volume),
              ],
            ),
          ),
        ),
      ),
    );

enum TvControlSection {
  episodes('选集', Icons.playlist_play_rounded),
  speed('倍速', Icons.speed_rounded),
  quality('画质', Icons.high_quality_outlined),
  danmaku('弹幕', Icons.subtitles_outlined),
  volume('音量', Icons.volume_up_rounded),
  sponsor('广告跳过', Icons.fast_forward_rounded),
  session('更多', Icons.more_horiz_rounded);

  const TvControlSection(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// Compact receiver settings, following Android's settings categories.
class TvControlsPanel extends StatefulWidget {
  const TvControlsPanel({
    super.key,
    this.initialSection = TvControlSection.episodes,
    this.expanded = false,
    this.episodeHeight = 140,
    this.onLeave,
  });
  final TvControlSection initialSection;
  final bool expanded;
  final double episodeHeight;
  final VoidCallback? onLeave;

  @override
  State<TvControlsPanel> createState() => _TvControlsPanelState();
}

class _TvControlsPanelState extends State<TvControlsPanel> {
  late TvControlSection _section = widget.initialSection;

  @override
  Widget build(BuildContext context) {
    final remote = Get.find<RemotePlaybackController>();
    return Obx(() {
      final state = remote.state.value;
      final enabled = _canControl(remote, state);
      final colors = Theme.of(context).colorScheme;
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (state.error != null || remote.error.value.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  state.error?.contains('MediaCodec') == true
                      ? '电视暂时无法解码这个视频，请尝试切换画质或重新播放。'
                      : state.error ?? remote.error.value,
                  style: TextStyle(color: colors.error),
                ),
              ),
            if (!widget.expanded)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final section in TvControlSection.values)
                      if (section != TvControlSection.session)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: TextButton.icon(
                            onPressed: () => setState(() => _section = section),
                            style: TextButton.styleFrom(
                              foregroundColor: _section == section
                                  ? colors.primary
                                  : colors.onSurfaceVariant,
                              backgroundColor: _section == section
                                  ? colors.secondaryContainer
                                  : null,
                            ),
                            icon: Icon(section.icon, size: 18),
                            label: Text(switch (section) {
                              TvControlSection.speed => '${state.speed}× 倍速',
                              TvControlSection.quality =>
                                state.qualities['${state.qualityId}'] ?? '画质',
                              TvControlSection.danmaku =>
                                state.danmakuEnabled ? '弹幕 · 开' : '弹幕 · 关',
                              TvControlSection.volume =>
                                '音量 ${remote.televisionVolume}%',
                              _ => section.label,
                            }),
                          ),
                        ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            switch (_section) {
              TvControlSection.episodes =>
                state.queue.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: Text('当前视频没有其他选集'),
                      )
                    : _Episodes(
                        remote: remote,
                        state: state,
                        enabled: enabled,
                        vertical: widget.expanded,
                        height: widget.episodeHeight,
                      ),
              TvControlSection.speed => _ChoiceSection(
                title: '播放速度',
                children: [
                  for (final speed in [0.5, 0.75, 1.0, 1.25, 1.5, 2.0])
                    ChoiceChip(
                      label: Text('${speed}x'),
                      selected: (state.speed - speed).abs() < 0.01,
                      onSelected: enabled
                          ? (_) =>
                                _send(remote, state, 'speed', {'value': speed})
                          : null,
                    ),
                ],
              ),
              TvControlSection.quality =>
                state.qualities.isEmpty
                    ? const Text('电视开始播放后可选择画质')
                    : _ChoiceSection(
                        title: '电视画质',
                        children: [
                          for (final quality in state.qualities.entries)
                            ChoiceChip(
                              label: Text(quality.value),
                              selected: '${state.qualityId}' == quality.key,
                              onSelected:
                                  enabled && int.tryParse(quality.key) != null
                                  ? (_) => _send(remote, state, 'quality', {
                                      'value': int.parse(quality.key),
                                    })
                                  : null,
                            ),
                        ],
                      ),
              TvControlSection.volume =>
                widget.expanded
                    ? _VolumeControl(
                        key: ValueKey('${state.playbackId}:volume'),
                        remote: remote,
                        state: state,
                      )
                    : _ControlCard(
                        child: _VolumeControl(
                          key: ValueKey('${state.playbackId}:volume'),
                          remote: remote,
                          state: state,
                        ),
                      ),
              TvControlSection.danmaku => _DanmakuControl(
                remote: remote,
                state: state,
                enabled: enabled,
              ),
              TvControlSection.sponsor => _SponsorSettings(
                remote: remote,
                state: state,
                enabled: enabled,
              ),
              TvControlSection.session => Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: enabled
                        ? () => _send(remote, state, 'back')
                        : null,
                    child: const Text('电视返回 / 停止播放'),
                  ),
                  TextButton(
                    onPressed: () async {
                      widget.onLeave?.call();
                      await remote.disconnect();
                    },
                    child: const Text('断开遥控，电视继续播'),
                  ),
                  TextButton(
                    onPressed: () {
                      final navigator = Navigator.of(context);
                      widget.onLeave?.call();
                      navigator.push<void>(
                        MaterialPageRoute(
                          builder: (_) => const TvConnectionPage(),
                        ),
                      );
                    },
                    child: const Text('重新连接 / 换电视'),
                  ),
                ],
              ),
            },
            if (!widget.expanded) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  IconButton(
                    tooltip: '上一集',
                    onPressed: enabled && _hasAdjacentEpisode(state, -1)
                        ? () => _send(remote, state, 'previous')
                        : null,
                    icon: const Icon(Icons.skip_previous_rounded),
                  ),
                  IconButton(
                    tooltip: '后退 10 秒',
                    onPressed: enabled && state.durationMs > 0
                        ? () {
                            if (_canControl(remote, state)) {
                              remote.seekTo(
                                (remote.televisionPositionMs - 10000).clamp(
                                  0,
                                  state.durationMs,
                                ),
                              );
                            }
                          }
                        : null,
                    icon: const Icon(Icons.replay_10_rounded),
                  ),
                  IconButton(
                    tooltip: '前进 10 秒',
                    onPressed: enabled && state.durationMs > 0
                        ? () {
                            if (_canControl(remote, state)) {
                              remote.seekTo(
                                (remote.televisionPositionMs + 10000).clamp(
                                  0,
                                  state.durationMs,
                                ),
                              );
                            }
                          }
                        : null,
                    icon: const Icon(Icons.forward_10_rounded),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: enabled
                        ? () => _send(remote, state, 'stop')
                        : null,
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: const Text('停止电视播放'),
                  ),
                ],
              ),
            ],
          ],
        ),
      );
    });
  }
}

class _ControlCard extends StatelessWidget {
  const _ControlCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    borderRadius: BorderRadius.circular(24),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: child,
    ),
  );
}

class _ProgressControl extends StatefulWidget {
  const _ProgressControl({
    required this.remote,
    required this.state,
    required this.enabled,
    this.trailing,
  });
  final RemotePlaybackController remote;
  final RemotePlaybackState state;
  final bool enabled;
  final Widget? trailing;

  @override
  State<_ProgressControl> createState() => _ProgressControlState();
}

class _ProgressControlState extends State<_ProgressControl> {
  double? _dragPosition;
  String? _dragPlaybackId;

  @override
  void didUpdateWidget(covariant _ProgressControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled ||
        oldWidget.state.playbackId != widget.state.playbackId) {
      _dragPosition = null;
      _dragPlaybackId = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final duration = widget.state.durationMs;
    final position =
        (_dragPosition ?? widget.remote.televisionPositionMs.toDouble())
            .clamp(0, duration)
            .toDouble();
    final enabled = widget.enabled && duration > 0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 40,
          child: Row(
            children: [
              Text(
                televisionTime(position.round()),
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
              const Text(
                ' / ',
                style: TextStyle(color: Colors.white, fontSize: 12),
              ),
              Text(
                televisionTime(duration),
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
              const Spacer(),
              if (widget.trailing != null) widget.trailing!,
            ],
          ),
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3,
            trackShape: const RoundedRectSliderTrackShape(),
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
            inactiveTrackColor: Colors.white30,
            disabledInactiveTrackColor: Colors.white24,
          ),
          child: SizedBox(
            height: 40,
            child: Slider(
              value: position,
              max: duration > 0 ? duration.toDouble() : 1,
              semanticFormatterCallback: (value) =>
                  televisionTime(value.round()),
              onChangeStart: enabled
                  ? (_) => _dragPlaybackId = widget.state.playbackId
                  : null,
              onChanged: enabled
                  ? (value) => setState(() => _dragPosition = value)
                  : null,
              onChangeEnd: enabled
                  ? (value) {
                      final playbackId = _dragPlaybackId;
                      setState(() {
                        _dragPosition = null;
                        _dragPlaybackId = null;
                      });
                      if (playbackId == widget.state.playbackId &&
                          _canControl(widget.remote, widget.state)) {
                        widget.remote.seekTo(value.round());
                      }
                    }
                  : null,
            ),
          ),
        ),
      ],
    );
  }
}

class _VolumeControl extends StatefulWidget {
  const _VolumeControl({super.key, required this.remote, required this.state});
  final RemotePlaybackController remote;
  final RemotePlaybackState state;

  @override
  State<_VolumeControl> createState() => _VolumeControlState();
}

class _VolumeControlState extends State<_VolumeControl> {
  String? _dragPlaybackId;

  @override
  Widget build(BuildContext context) {
    final remote = widget.remote;
    final state = widget.state;
    final theme = Theme.of(context);
    final enabled = _canControl(remote, state) && remote.canAdjustVolume;
    final volume = remote.televisionVolume;
    void setVolume(double value, {required bool dragging}) {
      if (_dragPlaybackId == state.playbackId &&
          _canControl(remote, state) &&
          remote.canAdjustVolume) {
        remote.setTelevisionVolume(value.round(), dragging: dragging);
      }
    }

    return Column(
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
                    state.volumeMode == 'player'
                        ? '播放器音量 · 手机音量不变'
                        : '手机音量保持不变',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              enabled ? '$volume%' : '—',
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: enabled ? theme.colorScheme.primary : null,
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
                  ? () {
                      if (_canControl(remote, state)) {
                        remote.adjustTelevisionVolume(-1);
                      }
                    }
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
                onChangeStart: enabled
                    ? (_) => _dragPlaybackId = state.playbackId
                    : null,
                onChanged: enabled
                    ? (value) => setVolume(value, dragging: true)
                    : null,
                onChangeEnd: enabled
                    ? (value) {
                        setVolume(value, dragging: false);
                        _dragPlaybackId = null;
                      }
                    : null,
              ),
            ),
            IconButton.filledTonal(
              tooltip: '电视音量加 1%',
              onPressed: enabled && volume < 100
                  ? () {
                      if (_canControl(remote, state)) {
                        remote.adjustTelevisionVolume(1);
                      }
                    }
                  : null,
              icon: const Icon(Icons.add_rounded),
            ),
          ],
        ),
        Row(
          children: [
            Expanded(
              child: Text(
                !remote.connected.value
                    ? '电视未连接'
                    : !enabled
                    ? '等待电视开始播放'
                    : remote.requestedVolume.value != null
                    ? '正在同步到电视…'
                    : '微调每次 1%',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            TextButton.icon(
              onPressed:
                  enabled && (volume > 0 || remote.canRestoreTelevisionVolume)
                  ? () {
                      if (_canControl(remote, state)) {
                        remote.toggleTelevisionMute();
                      }
                    }
                  : null,
              icon: Icon(
                volume > 0 ? Icons.volume_off_rounded : Icons.volume_up_rounded,
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
    );
  }
}

class _ChoiceSection extends StatelessWidget {
  const _ChoiceSection({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 4, children: children),
      ],
    ),
  );
}

class _Episodes extends StatelessWidget {
  const _Episodes({
    required this.remote,
    required this.state,
    required this.enabled,
    this.vertical = false,
    this.height = 140,
  });
  final RemotePlaybackController remote;
  final RemotePlaybackState state;
  final bool enabled;
  final bool vertical;
  final double height;

  @override
  Widget build(BuildContext context) {
    final queue = state.queue;
    final colors = Theme.of(context).colorScheme;
    const episodeAccent = Color(0xFFD8353F);
    if (queue.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Text(state.status == 'TRANSITIONING' ? '选集信息正在同步' : '暂无可用选集'),
      );
    }
    // A receiver can briefly retain the previous video's queue after a switch.
    if (!queue.any((item) => (item['aid'] as num?)?.toInt() == state.aid)) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Text('选集信息正在同步'),
      );
    }
    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: vertical ? Axis.vertical : Axis.horizontal,
        itemCount: queue.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final item = queue[index];
          final aid = (item['aid'] as num?)?.toInt() ?? 0;
          final cid = (item['cid'] as num?)?.toInt() ?? 0;
          final selected = aid == state.aid && cid == state.cid;
          if (vertical) {
            return ListTile(
              key: ValueKey('tv-episode:$aid:$cid'),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: selected
                      ? episodeAccent.withValues(alpha: .45)
                      : Colors.transparent,
                ),
              ),
              selected: selected,
              selectedColor: episodeAccent,
              selectedTileColor: episodeAccent.withValues(alpha: .12),
              leading: selected
                  ? const Icon(Icons.equalizer_rounded, size: 20)
                  : Text('${index + 1}'.padLeft(2, '0')),
              title: Text(
                item['title'] as String? ?? '第 ${index + 1} 集',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: enabled && !selected && aid > 0 && cid > 0
                  ? () => _send(remote, state, 'episode', {
                      'aid': aid,
                      'cid': cid,
                    })
                  : null,
            );
          }
          return Center(
            child: SizedBox(
              width: queue.length == 1 ? 220 : 180,
              height: 104,
              child: Material(
                color: selected
                    ? Color.alphaBlend(
                        episodeAccent.withValues(alpha: .08),
                        colors.surface,
                      )
                    : colors.surfaceContainerLow,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: selected
                        ? episodeAccent.withValues(alpha: .5)
                        : colors.outlineVariant,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: enabled && !selected && aid > 0 && cid > 0
                      ? () => _send(remote, state, 'episode', {
                          'aid': aid,
                          'cid': cid,
                        })
                      : null,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item['title'] as String? ?? '第 ${index + 1} 集',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colors.onSurface,
                            fontWeight: selected
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                        ),
                        const Spacer(),
                        if (selected)
                          Text(
                            state.status == 'PLAYING' ? '播放中' : '当前选集',
                            style: const TextStyle(
                              color: episodeAccent,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          )
                        else
                          Text(
                            '第 ${index + 1} 集',
                            style: TextStyle(
                              color: colors.onSurfaceVariant,
                              fontSize: 11,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SettingSlider extends StatefulWidget {
  const _SettingSlider({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onCommitted,
  });
  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double>? onCommitted;

  @override
  State<_SettingSlider> createState() => _SettingSliderState();
}

class _SettingSliderState extends State<_SettingSlider> {
  double? _preview;
  @override
  void didUpdateWidget(covariant _SettingSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.onCommitted == null) _preview = null;
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('${widget.label} ${((_preview ?? widget.value) * 100).round()}%'),
      Slider(
        value: (_preview ?? widget.value)
            .clamp(widget.min, widget.max)
            .toDouble(),
        min: widget.min,
        max: widget.max,
        divisions: widget.divisions,
        onChanged: widget.onCommitted == null
            ? null
            : (value) => setState(() => _preview = value),
        onChangeEnd: widget.onCommitted == null
            ? null
            : (value) {
                setState(() => _preview = null);
                widget.onCommitted?.call(value);
              },
      ),
    ],
  );
}

class _DanmakuControl extends StatelessWidget {
  const _DanmakuControl({
    required this.remote,
    required this.state,
    required this.enabled,
  });
  final RemotePlaybackController remote;
  final RemotePlaybackState state;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final canStyle = enabled && state.danmakuEnabled;
    return Column(
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.subtitles_outlined),
          title: const Text('电视弹幕'),
          value: state.danmakuEnabled,
          onChanged: enabled
              ? (value) => _send(remote, state, 'danmaku', {'enabled': value})
              : null,
        ),
        if (state.supportsDanmakuSettings)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('弹幕样式'),
            initiallyExpanded: true,
            childrenPadding: const EdgeInsets.only(bottom: 12),
            children: [
              _SettingSlider(
                key: ValueKey('${state.playbackId}:scale'),
                label: '字号',
                value: state.danmakuScale,
                min: 0.5,
                max: 4,
                divisions: 35,
                onCommitted: canStyle
                    ? (value) => _send(remote, state, 'danmakuSettings', {
                        'scale': value,
                      })
                    : null,
              ),
              _ChoiceSection(
                title: '显示区域',
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
                      onSelected: canStyle
                          ? (_) => _send(remote, state, 'danmakuSettings', {
                              'area': area.key,
                            })
                          : null,
                    ),
                ],
              ),
              const SizedBox(height: 16),
              _SettingSlider(
                key: ValueKey('${state.playbackId}:opacity'),
                label: '不透明度',
                value: state.danmakuOpacity,
                min: 0.1,
                max: 1,
                divisions: 9,
                onCommitted: canStyle
                    ? (value) => _send(remote, state, 'danmakuSettings', {
                        'opacity': value,
                      })
                    : null,
              ),
              _SettingSlider(
                key: ValueKey('${state.playbackId}:density'),
                label: '密度',
                value: state.danmakuDensity,
                min: 0.2,
                max: 1,
                divisions: 4,
                onCommitted: canStyle
                    ? (value) => _send(remote, state, 'danmakuSettings', {
                        'density': value,
                      })
                    : null,
              ),
              _ChoiceSection(
                title: '弹幕类型',
                children: [
                  for (final type in {
                    'rolling': '滚动',
                    'top': '顶部固定',
                    'bottom': '底部固定',
                  }.entries)
                    FilterChip(
                      label: Text(type.value),
                      selected: state.danmakuTypes.contains(type.key),
                      onSelected: canStyle
                          ? (selected) {
                              final types = state.danmakuTypes;
                              if (selected) {
                                types.add(type.key);
                              } else {
                                types.remove(type.key);
                              }
                              _send(remote, state, 'danmakuSettings', {
                                'types': types.toList(),
                              });
                            }
                          : null,
                    ),
                ],
              ),
            ],
          ),
      ],
    );
  }
}

class _SponsorPrompt extends StatelessWidget {
  const _SponsorPrompt({
    required this.remote,
    required this.state,
    required this.enabled,
  });
  final RemotePlaybackController remote;
  final RemotePlaybackState state;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final prompt = state.hasSponsorPrompt;
    final notice = state.sponsorSkipNotice;
    if (!enabled || (!prompt && notice == null)) return const SizedBox.shrink();
    void handle(String action) {
      final current = remote.state.value;
      if (current.sponsorSegmentId == state.sponsorSegmentId &&
          current.hasSponsorPrompt) {
        _send(remote, state, action, {'segmentId': state.sponsorSegmentId});
      }
    }

    final seconds = ((state.sponsorEndMs - state.positionMs + 999) ~/ 1000)
        .clamp(0, 2147483647);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _ControlCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              prompt
                  ? '${state.sponsorCategory == 'sponsor' ? '赞助片段' : '可跳过片段'} · 剩余 $seconds 秒'
                  : notice!,
            ),
            if (prompt)
              Row(
                children: [
                  TextButton.icon(
                    onPressed: () => handle('skipSponsor'),
                    icon: const Icon(Icons.fast_forward_rounded),
                    label: const Text('跳过片段'),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => handle('dismissSponsor'),
                    child: const Text('本次不跳'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _SponsorSettings extends StatelessWidget {
  const _SponsorSettings({
    required this.remote,
    required this.state,
    required this.enabled,
  });
  final RemotePlaybackController remote;
  final RemotePlaybackState state;
  final bool enabled;

  @override
  Widget build(BuildContext context) => ExpansionTile(
    tilePadding: EdgeInsets.zero,
    leading: const Icon(Icons.fast_forward_rounded),
    title: const Text('电视赞助片段'),
    initiallyExpanded: true,
    childrenPadding: const EdgeInsets.only(bottom: 12),
    children: [
      Wrap(
        spacing: 8,
        children: [
          for (final mode in {
            'prompt': '提示跳过',
            'auto': '自动跳过',
            'off': '关闭',
          }.entries)
            ChoiceChip(
              label: Text(mode.value),
              selected: state.sponsorSkipMode == mode.key,
              onSelected: enabled && state.sponsorSkipMode != null
                  ? (_) => _send(remote, state, 'sponsorSkipMode', {
                      'mode': mode.key,
                    })
                  : null,
            ),
        ],
      ),
      const SizedBox(height: 8),
      Text(
        state.sponsorSkipMode == null
            ? '当前电视版本暂不支持此设置。'
            : '由电视跳过社区标注片段，手机锁屏或退出后仍可自动跳过。',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ],
  );
}
