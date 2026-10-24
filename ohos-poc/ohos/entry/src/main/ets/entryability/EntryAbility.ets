import {
  FlutterAbility,
  FlutterEngine,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult
} from '@ohos/flutter_ohos';
import { GeneratedPluginRegistrant } from '../plugins/GeneratedPluginRegistrant';

export default class EntryAbility extends FlutterAbility implements MethodCallHandler {
  private platformChannel: MethodChannel | null = null;

  configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine);
    GeneratedPluginRegistrant.registerWith(flutterEngine);
    this.platformChannel = new MethodChannel(
      flutterEngine.getDartExecutor(),
      'dev.biliremote/platform'
    );
    this.platformChannel.setMethodCallHandler(this);
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    if (call.method === 'filesDirectory') {
      // The app's private persistent directory needs no storage permission.
      result.success(this.context.filesDir);
      return;
    }
    result.notImplemented();
  }

  cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
    this.platformChannel?.setMethodCallHandler(null);
    this.platformChannel = null;
    super.cleanUpFlutterEngine(flutterEngine);
  }
}
