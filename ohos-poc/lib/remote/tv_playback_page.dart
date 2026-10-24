import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'remote_playback_controller.dart';
import 'tv_controls_panel.dart';

/// Follows the receiver's current session. Entering or leaving never loads media.
class TvPlaybackPage extends StatelessWidget {
  const TvPlaybackPage({super.key});

  @override
  Widget build(BuildContext context) {
    final remote = Get.find<RemotePlaybackController>();
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: LayoutBuilder(
              builder: (context, constraints) => Column(
                children: [
                  SizedBox(
                    height: (constraints.maxWidth * 9 / 16).clamp(
                      0,
                      constraints.maxHeight,
                    ),
                    child: const TvVideoPlaceholder(),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                            child: Obx(() {
                              final state = remote.state.value;
                              final colors = Theme.of(context).colorScheme;
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    state.title.isEmpty
                                        ? '选择视频后在电视上观看'
                                        : state.title,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w600),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    remote.connected.value
                                        ? '视频由电视播放，手机用于选集和遥控。'
                                        : '电视会继续播放，恢复连接后自动同步当前进度。',
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: colors.onSurfaceVariant,
                                        ),
                                  ),
                                ],
                              );
                            }),
                          ),
                          const Divider(height: 1),
                          const TvControlsPanel(),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
