import 'package:bili_remote_core/remote_playback_controller.dart' as shared;
import 'package:PiliPlus/plugin/pl_player/controller.dart';

/// Keep Android's local-player handoff and hardware media controls while the
/// TV protocol, discovery and synchronized state are shared with HarmonyOS.
class RemotePlaybackController extends shared.RemotePlaybackController {
  RemotePlaybackController()
    : super(
        onRemotePlaybackChanged: PlPlayerController.setRemotePlaybackActive,
        enableAndroidNativeControls: true,
      );
}
