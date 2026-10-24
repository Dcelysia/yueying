import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'remote_playback_state.dart';

final defaultRemoteAddress = Uri(
  scheme: 'http',
  host: '192.168.5.228',
  port: 9838,
);

class RemoteDevice {
  final String name;
  final Uri address;
  final String deviceId;
  const RemoteDevice(this.name, this.address, {required this.deviceId});
}

Future<RemoteDevice> readRemoteDevice(Uri address) async {
  validateRemoteAddress(address);
  final http = HttpClient()..connectionTimeout = const Duration(seconds: 2);
  Future<RemoteDevice> readInfo() async {
    final request = await http.getUrl(
      address.replace(path: '/remote/v1/info', query: null, fragment: ''),
    );
    request.followRedirects = false;
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      throw const FormatException('电视连接服务尚未就绪');
    }
    final data = jsonDecode(
      await response.transform(utf8.decoder).join(),
    ) as Map<String, dynamic>;
    final deviceId = data['deviceId'] as String?;
    if (data['protocol'] != 1 || deviceId == null || deviceId.isEmpty) {
      throw const FormatException('此设备不是 Bili Remote 电视');
    }
    return RemoteDevice(
      data['name'] as String? ?? 'Bili Remote TV',
      address.replace(path: '', query: null, fragment: ''),
      deviceId: deviceId,
    );
  }

  try {
    return await readInfo().timeout(const Duration(seconds: 2));
  } finally {
    http.close(force: true);
  }
}

/// Emit verified receivers immediately, then drain pending checks before finishing.
Stream<RemoteDevice> discoverRemoteDevices({
  Iterable<Uri> knownAddresses = const [],
}) async* {
  final updates = StreamController<RemoteDevice>();
  final attemptedAddresses = <String>{};
  final deviceIds = <String>{};
  final pendingProbes = <Future<void>>{};
  final timers = <Timer>[];
  final sockets = <RawDatagramSocket>[];
  final subscriptions = <StreamSubscription<RawSocketEvent>>[];
  final locationHeader = RegExp(
    r'^location:\s*(.+)$',
    multiLine: true,
    caseSensitive: false,
  );
  var acceptingReplies = true;
  var stopped = false;

  Future<void> probe(Uri address) async {
    for (var attempt = 0; attempt < 2 && !stopped; attempt++) {
      try {
        final device = await readRemoteDevice(address);
        if (!stopped && !updates.isClosed && deviceIds.add(device.deviceId)) {
          updates.add(device);
        }
        return;
      } catch (_) {
        if (attempt == 0 && !stopped) {
          await Future<void>.delayed(const Duration(milliseconds: 250));
        }
      }
    }
  }

  void queueProbe(Uri address) {
    if (stopped ||
        !acceptingReplies ||
        !attemptedAddresses.add(address.authority)) {
      return;
    }
    final work = probe(address);
    pendingProbes.add(work);
    unawaited(work.whenComplete(() => pendingProbes.remove(work)));
  }

  Future<void> openSearchSocket(InternetAddress address) async {
    RawDatagramSocket? socket;
    try {
      socket = await RawDatagramSocket.bind(address, 0);
      if (stopped || !acceptingReplies) {
        socket.close();
        return;
      }
      if (address != InternetAddress.anyIPv4) {
        socket.setRawOption(
          RawSocketOption(
            RawSocketOption.levelIPv4,
            RawSocketOption.IPv4MulticastInterface,
            address.rawAddress,
          ),
        );
      }
      final discoverySocket = socket;
      sockets.add(discoverySocket);
      subscriptions.add(
        discoverySocket.listen(
          (event) {
            if (event != RawSocketEvent.read || stopped || !acceptingReplies) {
              return;
            }
            Datagram? packet;
            while ((packet = discoverySocket.receive()) != null) {
              final body = utf8.decode(packet!.data, allowMalformed: true);
              final location = locationHeader
                  .firstMatch(body)
                  ?.group(1)
                  ?.trim();
              final receiver = Uri.tryParse(location ?? '');
              if (receiver != null &&
                  receiver.scheme == 'http' &&
                  receiver.host.isNotEmpty) {
                queueProbe(receiver);
              }
            }
          },
          onError: (Object error) {
            if (!stopped) updates.addError(error);
          },
        ),
      );
    } on SocketException {
      socket?.close();
      // Another LAN interface or the default route may still work.
    } on UnsupportedError {
      socket?.close();
    }
  }

  void sendSearch() {
    if (stopped || !acceptingReplies) return;
    const message =
        'M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: "ssdp:discover"\r\nMX: 2\r\nST: urn:schemas-upnp-org:device:MediaRenderer:1\r\n\r\n';
    final bytes = utf8.encode(message);
    for (final socket in sockets) {
      try {
        socket.send(bytes, InternetAddress('239.255.255.250'), 1900);
      } on SocketException catch (error) {
        if (!stopped) updates.addError(error);
      }
    }
  }

  try {
    for (final address in knownAddresses) {
      queueProbe(address);
    }
    try {
      final networks = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      );
      for (final network in networks) {
        for (final address in network.addresses) {
          if (address.isLoopback) continue;
          try {
            validateRemoteAddress(
              Uri(scheme: 'http', host: address.address, port: 9838),
            );
          } on FormatException {
            continue;
          }
          await openSearchSocket(address);
        }
      }
    } on SocketException {
      // Interface enumeration can fail on a platform that still supports UDP.
    } on UnsupportedError {
      // Fall back to the default route when interface enumeration is unsupported.
    }
    if (sockets.isEmpty) await openSearchSocket(InternetAddress.anyIPv4);
    if (sockets.isEmpty) updates.addError(const SocketException('无法创建局域网搜索连接'));
    sendSearch();
    for (final delayMs in [600, 1500, 3000]) {
      timers.add(Timer(Duration(milliseconds: delayMs), sendSearch));
    }
    timers.add(
      Timer(const Duration(seconds: 6), () async {
        acceptingReplies = false;
        // Replies received near the deadline get their full HTTP validation budget.
        await Future.wait(pendingProbes.toList());
        if (!stopped) unawaited(updates.close());
      }),
    );
    yield* updates.stream;
  } finally {
    stopped = true;
    acceptingReplies = false;
    for (final timer in timers) {
      timer.cancel();
    }
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
    for (final socket in sockets) {
      socket.close();
    }
    unawaited(updates.close());
  }
}
