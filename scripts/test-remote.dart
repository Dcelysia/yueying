import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Uses a test TV: plays the supplied video, tests controls, then stops playback.
class RemoteProbe {
  final WebSocket socket;
  final welcome = Completer<Map<String, dynamic>>();
  final pending = <String, Completer<Map<String, dynamic>>>{};
  Map<String, dynamic> state = {};
  int requestNumber = 0;

  RemoteProbe(this.socket) {
    socket.listen((raw) {
      final message = jsonDecode(raw as String) as Map<String, dynamic>;
      switch (message['type']) {
        case 'welcome':
          welcome.complete(message);
        case 'state':
          if ((message['revision'] as int) > (state['revision'] as int? ?? -1))
            state = message;
        case 'ack':
        case 'error':
          pending.remove(message['requestId'])?.complete(message);
          if (!welcome.isCompleted && message['type'] == 'error')
            welcome.completeError(StateError(message['message'] as String));
      }
    });
  }

  static Future<RemoteProbe> connect(
    Uri address, {
    String? pin,
    String? token,
  }) async {
    final probe = RemoteProbe(
      await WebSocket.connect(address.replace(path: '/remote/v1').toString()),
    );
    probe.socket.add(
      jsonEncode({
        'type': 'hello',
        'protocol': 1,
        'clientId': 'bili-remote-runtime-test',
        if (pin != null) 'pin': pin,
        if (token != null) 'token': token,
      }),
    );
    await probe.welcome.future.timeout(const Duration(seconds: 10));
    await probe.waitFor((state) => state.isNotEmpty);
    return probe;
  }

  Future<Map<String, dynamic>> command(
    String action, [
    Map<String, dynamic> payload = const {},
    String? playbackId,
  ]) async {
    final requestId =
        'probe-${DateTime.now().microsecondsSinceEpoch}-${++requestNumber}';
    final completed = Completer<Map<String, dynamic>>();
    pending[requestId] = completed;
    socket.add(
      jsonEncode({
        'type': 'command',
        'requestId': requestId,
        'action': action,
        'playbackId': playbackId ?? state['playbackId'],
        'payload': payload,
      }),
    );
    return completed.future.timeout(const Duration(seconds: 15));
  }

  Future<void> apply(
    String action, [
    Map<String, dynamic> payload = const {},
  ]) async {
    final response = await command(action, payload);
    if (response['type'] != 'ack')
      throw StateError('$action: ${response['message']}');
  }

  Future<void> waitFor(bool Function(Map<String, dynamic>) check) async {
    final deadline = DateTime.now().add(const Duration(seconds: 45));
    while (!check(state)) {
      if (state['state'] == 'ERROR') throw StateError('${state['error']}');
      if (DateTime.now().isAfter(deadline))
        throw StateError('Timed out: $state');
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }
}

Future<void> main(List<String> arguments) async {
  if (arguments.length != 3 ||
      Platform.environment['BILI_REMOTE_PIN'] == null) {
    stderr.writeln(
      'Set BILI_REMOTE_PIN; arguments: ws://TV_IP:9838 AID CID. Use a test video longer than 30 seconds.',
    );
    exitCode = 2;
    return;
  }
  final address = Uri.parse(arguments[0]);
  var probe = await RemoteProbe.connect(
    address,
    pin: Platform.environment['BILI_REMOTE_PIN'],
  );
  final token = (await probe.welcome.future)['token'] as String;
  try {
    final rejected = await probe.command('pause', const {}, 'obsolete-session');
    if (rejected['type'] != 'error')
      throw StateError('An obsolete playback ID was accepted.');
    await probe.apply('load', {
      'aid': int.parse(arguments[1]),
      'cid': int.parse(arguments[2]),
      'title': '遥控联调',
      'positionMs': 0,
    });
    await probe.waitFor(
      (state) =>
          state['state'] == 'PLAYING' && (state['positionMs'] as int) > 1000,
    );
    stdout.writeln(
      'PASS: pairing, obsolete command rejection, TV independent playback',
    );
    final originalVolume = probe.state['volume'];
    final originalDanmaku = probe.state['danmakuEnabled'];
    await probe.apply('pause');
    await probe.waitFor((state) => state['state'] == 'PAUSED');
    await probe.apply('seek', {'positionMs': 20000});
    await probe.waitFor(
      (state) => ((state['positionMs'] as int) - 20000).abs() < 2000,
    );
    await probe.apply('volume', {'value': 50});
    await probe.apply('speed', {'value': 1.25});
    await probe.apply('danmaku', {'enabled': false});
    await probe.waitFor(
      (state) => state['speed'] == 1.25 && state['danmakuEnabled'] == false,
    );
    await probe.apply('volume', {'value': originalVolume});
    await probe.apply('danmaku', {'enabled': originalDanmaku});
    await probe.apply('speed', {'value': 1.0});
    await probe.apply('play');
    await probe.waitFor(
      (state) =>
          state['state'] == 'PLAYING' && (state['positionMs'] as int) > 21000,
    );
    stdout.writeln('PASS: pause, seek, volume, speed, danmaku commands');
    final playbackId = probe.state['playbackId'];
    final position = probe.state['positionMs'] as int;
    await probe.socket.close();
    await Future<void>.delayed(const Duration(seconds: 3));
    probe = await RemoteProbe.connect(address, token: token);
    await probe.waitFor(
      (state) =>
          state['state'] == 'PLAYING' &&
          (state['positionMs'] as int) > position,
    );
    if (probe.state['playbackId'] != playbackId)
      throw StateError('Reconnection restarted playback.');
    final originalAid = probe.state['aid'];
    final originalCid = probe.state['cid'];
    final queue = probe.state['queue'] as List;
    final current = queue.indexWhere(
      (item) => item['aid'] == originalAid && item['cid'] == originalCid,
    );
    if (current >= 0 && current + 1 < queue.length) {
      final next = queue[current + 1] as Map;
      bool nextIsPlaying(Map<String, dynamic> state) =>
          state['aid'] == next['aid'] &&
          state['cid'] == next['cid'] &&
          state['state'] == 'PLAYING' &&
          (state['positionMs'] as int) > 1000;
      await probe.apply('next');
      await probe.waitFor(nextIsPlaying);
      await probe.apply('previous');
      await probe.waitFor(
        (state) =>
            state['aid'] == originalAid &&
            state['cid'] == originalCid &&
            state['state'] == 'PLAYING',
      );
      await probe.apply('episode', {'aid': next['aid'], 'cid': next['cid']});
      await probe.waitFor(nextIsPlaying);
      stdout.writeln('PASS: next, previous and exact episode selection');
    } else {
      stdout.writeln(
        'SKIP: episode switching (no next episode in this test video)',
      );
    }
    await probe.apply('back');
    await probe.waitFor((state) => state['state'] == 'STOPPED');
    stdout.writeln(
      'PASS: disconnect keeps playing, token reconnect, actual state, TV return',
    );
  } finally {
    await probe.socket.close();
  }
}
