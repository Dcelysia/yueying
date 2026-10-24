import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:hive_ce/hive.dart';

import 'remote_playback_state.dart';
import 'remote_device_discovery.dart';

/// A selected TV session survives navigation and phone suspension.
class RemotePlaybackController extends GetxController
    with WidgetsBindingObserver {
  RemotePlaybackController({
    Future<void> Function(bool active)? onRemotePlaybackChanged,
    this.enableAndroidNativeControls = false,
  }) : _onRemotePlaybackChanged = onRemotePlaybackChanged;

  // Android releases its local player when TV playback takes over. A controller
  // without local playback does not need to supply this hook.
  final Future<void> Function(bool active)? _onRemotePlaybackChanged;
  final bool enableAndroidNativeControls;
  bool get _hasNativeVolumeControls =>
      enableAndroidNativeControls && Platform.isAndroid;

  final remoteMode = false.obs;
  final controlsVisible = false.obs;
  final connected = false.obs;
  final connecting = false.obs;
  final state = const RemotePlaybackState().obs;
  final error = ''.obs;
  final deviceName = '电视'.obs;
  final savedDevice = Rxn<RemoteDevice>();
  final nearbyDevices = <RemoteDevice>[].obs;
  final discovering = false.obs;
  final discoveryError = ''.obs;
  final discoveryStatus = ''.obs;
  final checkingConnection = false.obs;
  bool get needsPairing => _needsPairing;
  StreamSubscription<RemoteDevice>? _discoverySubscription;
  StreamSubscription<List<ConnectivityResult>>? _networkSubscription;
  Timer? _sessionCheckTimer;
  DateTime? _lastMessageAt;
  Future<void>? _connectionAttempt;
  HttpClient? _dialClient;
  Future<bool?>? _networkPermissionRequest;
  int _reconnectAttempt = 0;
  int _discoveryGeneration = 0;
  bool _resumeDiscoveryOnForeground = false;
  // The latest user target is kept until the TV acknowledges and reports its actual volume.
  final requestedVolume = RxnInt();
  final requestedPositionMs = RxnInt();
  int? _seekAcknowledgedRevision;
  int _seekGeneration = 0;
  Timer? _seekFeedbackTimer;
  int get televisionPositionMs =>
      requestedPositionMs.value ?? state.value.positionMs;
  int? _queuedVolume;
  // Kept for this TV session so reopening a panel can still undo mute.
  int? _volumeBeforeMute;
  int? _volumeAcknowledgedRevision;
  int _volumeGeneration = 0;
  bool _sendingVolume = false;
  Timer? _volumeFeedbackTimer;
  Timer? _volumeDragTimer;
  final _volumeClock = Stopwatch()..start();
  int _lastVolumeSentMs = -80;
  bool _queuedVolumeFromDrag = false;
  final volumeFeedbackVisible = false.obs;
  Timer? _volumeOverlayTimer;

  bool get canAdjustVolume =>
      connected.value &&
      remoteMode.value &&
      state.value.aid > 0 &&
      state.value.playbackId.isNotEmpty &&
      state.value.status != 'TRANSITIONING' &&
      state.value.volumeMode != 'unavailable';

  int get televisionVolume => requestedVolume.value ?? state.value.volume;
  static const _volumeChannel = MethodChannel('dev.biliremote/remote_volume');
  Box<String>? _pairing;
  WebSocket? _socket;
  StreamSubscription<dynamic>? _subscription;
  Timer? _reconnectTimer;
  final _pending = <String, Completer<void>>{};
  Completer<void>? _handshake;
  Uri? _address;
  int _connectionGeneration = 0;
  int _requestNumber = 0;
  int _loadGeneration = 0;
  bool _foreground = true;
  bool _needsPairing = false;

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
    if (!_hasNativeVolumeControls) return;
    _volumeChannel.setMethodCallHandler((call) async {
      if (!remoteMode.value) return;
      final isVolumeCommand = const {
        'adjustVolume',
        'setVolume',
        'toggleMute',
      }.contains(call.method);
      if (!connected.value) {
        if (isVolumeCommand) _showVolumeFeedback();
        return;
      }
      switch (call.method) {
        case 'adjustVolume':
          adjustTelevisionVolume(call.arguments as int);
        case 'setVolume':
          setTelevisionVolume(call.arguments as int, dragging: true);
        case 'toggleMute':
          toggleTelevisionMute();
        case 'togglePlayback':
          await perform(state.value.status == 'PLAYING' ? 'pause' : 'play');
        case 'play':
        case 'pause':
          await perform(call.method);
      }
      if (isVolumeCommand) _showVolumeFeedback();
    });
  }

  Future<void>? _restoreOperation;

  Future<void> restore() => _restoreOperation ??= _restore();

  Future<void> _restore() async {
    _pairing = await Hive.openBox<String>('remote_pairing');
    if (_pairing!.get('clientId') == null) {
      final random = Random.secure();
      await _pairing!.put(
        'clientId',
        List.generate(
          16,
          (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
        ).join(),
      );
    }
    final address = _pairing!.get('address');
    if (address != null) {
      _address = Uri.tryParse(address);
      if (_address != null) {
        savedDevice.value = RemoteDevice(
          _pairing!.get('name') ?? 'Bili Remote TV',
          _address!,
          deviceId: _pairing!.get('deviceId') ?? '',
        );
        deviceName.value = savedDevice.value!.name;
      }
    }
    if (isClosed) return;
    _networkSubscription = Connectivity().onConnectivityChanged.listen(
      (_) {
        if (!_foreground || !remoteMode.value) return;
        _reconnectAttempt = 0;
        if (connected.value) {
          unawaited(_checkConnection());
        } else {
          unawaited(searchDevices());
          _scheduleReconnect(immediate: true);
        }
      },
      onError: (Object _) {
        // Socket checks still detect disconnection if platform network events are unavailable.
      },
    );
    _sessionCheckTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      final lastMessage = _lastMessageAt;
      if (_foreground &&
          connected.value &&
          lastMessage != null &&
          DateTime.now().difference(lastMessage) > const Duration(seconds: 3)) {
        unawaited(_checkConnection());
      }
    });
    if (_pairing!.get('selected') == 'true' && _address != null) {
      remoteMode.value = true;
      _scheduleReconnect(immediate: true);
    }
  }

  Future<void> searchDevices({bool useFixedAddressFallback = false}) async {
    if (discovering.value || isClosed || !_foreground) return;
    final generation = ++_discoveryGeneration;
    final connectionGeneration = _connectionGeneration;
    discovering.value = true;
    discoveryStatus.value = '正在搜索同一局域网内的电视…';
    discoveryError.value = '';
    nearbyDevices.clear();
    try {
      await requestLocalNetworkAccess();
      if (generation != _discoveryGeneration || isClosed) return;
      await _discoverySubscription?.cancel();
      if (generation != _discoveryGeneration || isClosed) return;
      _discoverySubscription =
          discoverRemoteDevices(
            knownAddresses: [
              if (savedDevice.value case final device?) device.address,
            ],
          ).listen(
            _deviceDiscovered,
            onError: (Object _) {
              if (generation == _discoveryGeneration && nearbyDevices.isEmpty) {
                discoveryError.value = '自动发现暂不可用，仍可使用已保存的电视或手动输入地址';
              }
            },
            onDone: () async {
              if (generation != _discoveryGeneration || isClosed) return;
              _discoverySubscription = null;
              if (useFixedAddressFallback &&
                  nearbyDevices.isEmpty &&
                  _foreground &&
                  !connected.value &&
                  !connecting.value &&
                  connectionGeneration == _connectionGeneration) {
                discoveryStatus.value =
                    '未发现电视，正在尝试 ${defaultRemoteAddress.authority}…';
                discoveryError.value = '';
                try {
                  final device = await readRemoteDevice(defaultRemoteAddress);
                  if (generation != _discoveryGeneration ||
                      isClosed ||
                      !_foreground ||
                      connected.value ||
                      connecting.value ||
                      connectionGeneration != _connectionGeneration) {
                    if (generation == _discoveryGeneration && !isClosed) {
                      discovering.value = false;
                      discoveryStatus.value = '';
                    }
                    return;
                  }
                  _deviceDiscovered(device);
                  discoveryStatus.value = '已找到固定地址的电视，正在连接…';
                  await connect(device.address);
                } catch (exception) {
                  if (generation == _discoveryGeneration && !isClosed) {
                    discoveryError.value = '固定地址连接失败：$exception。仍可手动输入其他地址。';
                  }
                }
              }
              if (generation == _discoveryGeneration && !isClosed) {
                discovering.value = false;
                discoveryStatus.value = connected.value
                    ? '电视已连接，可以返回选视频'
                    : nearbyDevices.isNotEmpty
                    ? '已找到电视，点设备即可连接'
                    : '暂未发现电视，可以重新搜索或手动连接';
              }
            },
          );
    } catch (_) {
      if (generation == _discoveryGeneration) {
        discovering.value = false;
        discoveryStatus.value = '';
        discoveryError.value = '请允许局域网访问，再重新搜索电视';
      }
    }
  }

  void _deviceDiscovered(RemoteDevice device) {
    final index = nearbyDevices.indexWhere(
      (item) => item.deviceId == device.deviceId,
    );
    discoveryError.value = '';
    discoveryStatus.value = '已找到电视，点设备即可连接；仍在搜索其他设备…';
    if (index < 0) {
      nearbyDevices.add(device);
    } else {
      nearbyDevices[index] = device;
    }
    final saved = savedDevice.value;
    if (saved == null ||
        saved.deviceId.isEmpty ||
        saved.deviceId != device.deviceId) {
      return;
    }
    if (!connected.value) {
      savedDevice.value = device;
      _address = device.address;
      if (remoteMode.value) _scheduleReconnect(immediate: true);
    }
  }

  void stopDeviceSearch({bool resumeWhenForeground = false}) {
    _resumeDiscoveryOnForeground =
        resumeWhenForeground &&
        (discovering.value || _resumeDiscoveryOnForeground);
    ++_discoveryGeneration;
    unawaited(_discoverySubscription?.cancel());
    _discoverySubscription = null;
    discovering.value = false;
    discoveryStatus.value = '';
  }

  Future<void> connect(Uri address, {bool automatic = false}) {
    if (_connectionAttempt != null) {
      return Future.error(StateError('正在连接电视，请稍候'));
    }
    _reconnectTimer?.cancel();
    if (!automatic &&
        savedDevice.value?.address.authority == address.authority &&
        _pairing != null) {
      remoteMode.value = true;
      _address = address;
      unawaited(_pairing!.put('selected', 'true'));
    }
    final attempt = _connectDevice(address, automatic: automatic);
    _connectionAttempt = attempt;
    return attempt.whenComplete(() {
      _connectionAttempt = null;
      connecting.value = false;
      if (!connected.value &&
          (automatic ||
              savedDevice.value?.address.authority == address.authority)) {
        _scheduleReconnect(immediate: _address?.authority != address.authority);
      }
    });
  }

  Future<void> _connectDevice(
    Uri address, {
    required bool automatic,
  }) async {
    if (_pairing == null) throw StateError('正在准备连接，请稍后再试');
    validateRemoteAddress(address);
    final generation = ++_connectionGeneration;
    _closeTransport();
    _failPending('连接已切换');
    connected.value = false;
    connecting.value = true;
    checkingConnection.value = false;
    _resetControlCommands();
    unawaited(_syncNativeVolumeSession());
    error.value = '';
    _needsPairing = false;
    final handshake = _handshake = Completer<void>();
    // Install error handling before cancellation or socket callbacks can fail the handshake.
    unawaited(handshake.future.catchError((Object _) {}));
    HttpClient? client;
    try {
      await requestLocalNetworkAccess();
      if (generation != _connectionGeneration || isClosed) {
        throw StateError('连接已取消');
      }
      final receiver = await readRemoteDevice(address);
      if (generation != _connectionGeneration || isClosed) {
        throw StateError('连接已取消');
      }
      final saved = savedDevice.value;
      final sameDevice =
          saved != null &&
          (saved.deviceId.isNotEmpty
              ? saved.deviceId == receiver.deviceId
              : saved.address.authority == address.authority);
      if (automatic && !sameDevice) throw StateError('电视地址已变化，正在重新寻找');
      if (!sameDevice) _volumeBeforeMute = null;
      final token = sameDevice ? _pairing!.get('token') : null;
      client = _dialClient = HttpClient()
        ..connectionTimeout = const Duration(seconds: 2);
      var acceptingSocket = true;
      final openingSocket = WebSocket.connect(
        address
            .replace(scheme: 'ws', path: '/remote/v1', query: null)
            .toString(),
        customClient: client,
      );
      unawaited(
        openingSocket.then<void>((socket) {
          if (!acceptingSocket) unawaited(socket.close());
        }, onError: (Object _) {}),
      );
      final WebSocket socket;
      try {
        socket = await openingSocket.timeout(const Duration(seconds: 2));
      } finally {
        acceptingSocket = false;
      }
      if (generation != _connectionGeneration || isClosed) {
        unawaited(socket.close());
        throw StateError('连接已取消');
      }
      _socket = socket..pingInterval = const Duration(seconds: 15);
      state.value = const RemotePlaybackState();
      _lastMessageAt = DateTime.now();
      _subscription = socket.listen(
        (message) {
          if (generation == _connectionGeneration) {
            _receive(message, handshake, address, receiver.deviceId);
          }
        },
        onError: (Object exception) =>
            _connectionLost(generation, '$exception'),
        onDone: () => _connectionLost(generation, '与电视的连接已断开，电视会继续播放'),
      );
      socket.add(
        jsonEncode({
          'type': 'hello',
          'protocol': 1,
          'clientId': _pairing!.get('clientId'),
          if (token != null) 'token': token,
        }),
      );
      await handshake.future.timeout(const Duration(seconds: 3));
      if (generation != _connectionGeneration || isClosed) {
        throw StateError('连接已取消');
      }
      await _onRemotePlaybackChanged?.call(true);
      if (generation != _connectionGeneration || isClosed) {
        throw StateError('连接已取消');
      }
      _address = address;
      connected.value = true;
      remoteMode.value = true;
      _reconnectAttempt = 0;
      await _pairing!.put('selected', 'true');
      await _syncNativeVolumeSession();
    } catch (exception) {
      if (generation == _connectionGeneration) {
        ++_connectionGeneration;
        error.value = '$exception';
        connected.value = false;
        _closeTransport();
      }
      rethrow;
    } finally {
      client?.close(force: true);
      if (identical(_dialClient, client)) _dialClient = null;
    }
  }

  void _receive(
    dynamic message,
    Completer<void> handshake,
    Uri address,
    String expectedDeviceId,
  ) {
    try {
      final data = jsonDecode(message as String) as Map<String, dynamic>;
      _lastMessageAt = DateTime.now();
      switch (data['type']) {
        case 'welcome':
          if (data['protocol'] != 1) throw const FormatException('遥控协议版本不匹配');
          if (data['deviceId'] != expectedDeviceId) {
            throw const FormatException('电视身份已变化，请重新搜索');
          }
          deviceName.value = data['name'] as String? ?? '电视';
          savedDevice.value = RemoteDevice(
            deviceName.value,
            address,
            deviceId: expectedDeviceId,
          );
          unawaited(
            _pairing!.putAll({
              'token': data['token'] as String,
              'address': address.toString(),
              'deviceId': expectedDeviceId,
              'name': deviceName.value,
            }),
          );
          if (!handshake.isCompleted) handshake.complete();
          break;
        case 'state':
          final next = RemotePlaybackState(data);
          if (next.revision > state.value.revision) {
            if (next.playbackId != state.value.playbackId) {
              _resetControlCommands();
              error.value = '';
            }
            state.value = next;
            if (_seekAcknowledgedRevision != null &&
                next.revision > _seekAcknowledgedRevision!) {
              _clearSeekFeedback();
            }
            if (_volumeAcknowledgedRevision != null &&
                next.revision > _volumeAcknowledgedRevision! &&
                next.volume == requestedVolume.value &&
                !_sendingVolume &&
                _queuedVolume == null) {
              _clearVolumeFeedback();
            }
            unawaited(_syncNativeVolumeSession());
          }
          break;
        case 'ack':
          _pending.remove(data['requestId'])?.complete();
          break;
        case 'error':
          final text = data['code'] == 'PAIRING_REQUIRED'
              ? '请更新电视端以支持免配对连接'
              : data['message'] as String? ?? '电视执行失败';
          error.value = text;
          if (data['code'] == 'PAIRING_REQUIRED') {
            _needsPairing = true;
            _reconnectTimer?.cancel();
          }
          if (!handshake.isCompleted) handshake.completeError(StateError(text));
          _pending.remove(data['requestId'])?.completeError(StateError(text));
          break;
      }
    } catch (exception) {
      error.value = '$exception';
      if (!handshake.isCompleted) handshake.completeError(exception);
    }
  }

  Future<void> requestLocalNetworkAccess() async {
    if (!_hasNativeVolumeControls) return;
    final request = _networkPermissionRequest ??= _volumeChannel
        .invokeMethod<bool>('requestLocalNetwork');
    try {
      if (await request != true) throw StateError('需要局域网权限才能发现和遥控电视');
    } finally {
      if (identical(_networkPermissionRequest, request)) {
        _networkPermissionRequest = null;
      }
    }
  }

  Future<bool> connectLastDevice() async {
    await restore();
    final pendingConnection = _connectionAttempt;
    if (pendingConnection != null) {
      try {
        await pendingConnection;
      } catch (_) {
        // A share can retry the saved TV after an automatic attempt failed.
      }
    }
    if (connected.value) return true;
    final device = savedDevice.value;
    if (device == null) return false;
    await connect(device.address);
    return connected.value;
  }

  Future<void> playVideo(Map<String, dynamic> media) async {
    final generation = ++_loadGeneration;
    await _onRemotePlaybackChanged?.call(true);
    if (generation != _loadGeneration || !remoteMode.value) return;
    await command('load', media);
  }

  Future<void> command(
    String action, [
    Map<String, dynamic> payload = const {},
  ]) async {
    if (!connected.value || _socket == null) throw StateError('电视未连接，请先恢复连接');
    final requestId =
        '${DateTime.now().microsecondsSinceEpoch}-${++_requestNumber}';
    final completion = Completer<void>();
    _pending[requestId] = completion;
    try {
      _socket!.add(
        jsonEncode({
          'type': 'command',
          'requestId': requestId,
          'action': action,
          'playbackId': state.value.playbackId,
          'payload': payload,
        }),
      );
      await completion.future.timeout(const Duration(seconds: 10));
      error.value = '';
    } finally {
      _pending.remove(requestId);
    }
  }

  Future<void> perform(
    String action, [
    Map<String, dynamic> payload = const {},
  ]) async {
    try {
      await command(action, payload);
    } catch (exception) {
      error.value = '$exception';
    }
  }

  bool get canRestoreTelevisionVolume => _volumeBeforeMute != null;

  void toggleTelevisionMute() {
    if (!canAdjustVolume) return;
    final volume = televisionVolume;
    if (volume > 0) {
      _volumeBeforeMute = volume;
      setTelevisionVolume(0);
    } else if (_volumeBeforeMute != null) {
      setTelevisionVolume(_volumeBeforeMute!);
    }
  }

  void adjustTelevisionVolume(int direction) {
    if (direction != -1 && direction != 1) return;
    setTelevisionVolume(televisionVolume + direction);
  }

  Future<void> seekTo(int positionMs) async {
    if (!connected.value || state.value.playbackId.isEmpty) return;
    final generation = ++_seekGeneration;
    _clearSeekFeedback();
    requestedPositionMs.value = positionMs.clamp(0, state.value.durationMs);
    try {
      // Submit immediately; keep the preview until a post-ACK snapshot arrives.
      await command('seek', {'positionMs': requestedPositionMs.value});
      if (generation != _seekGeneration) return;
      _seekAcknowledgedRevision = state.value.revision;
      _seekFeedbackTimer = Timer(
        const Duration(seconds: 2),
        _clearSeekFeedback,
      );
    } catch (exception) {
      if (generation != _seekGeneration) return;
      error.value = '$exception';
      _clearSeekFeedback();
    }
  }

  void _clearSeekFeedback() {
    _seekFeedbackTimer?.cancel();
    _seekAcknowledgedRevision = null;
    requestedPositionMs.value = null;
  }

  void _showVolumeFeedback() {
    volumeFeedbackVisible.value = true;
    _volumeOverlayTimer?.cancel();
    _volumeOverlayTimer = Timer(const Duration(milliseconds: 1400), () {
      volumeFeedbackVisible.value = false;
    });
  }

  void setTelevisionVolume(int value, {bool dragging = false}) {
    if (!canAdjustVolume) return;
    final target = value.clamp(0, 100);
    if (requestedVolume.value == target) {
      // Release flushes a trailing drag value even when the displayed target is unchanged.
      if (!dragging) {
        _queuedVolumeFromDrag = false;
        _dispatchQueuedVolume();
      }
      return;
    }
    _volumeFeedbackTimer?.cancel();
    _volumeAcknowledgedRevision = null;
    _queuedVolume = target;
    _queuedVolumeFromDrag = dragging;
    requestedVolume.value = target;
    unawaited(_syncNativeVolumeSession());
    _dispatchQueuedVolume();
  }

  void _dispatchQueuedVolume() {
    _volumeDragTimer?.cancel();
    _volumeDragTimer = null;
    if (_sendingVolume || _queuedVolume == null || !canAdjustVolume) return;
    final remainingMs =
        80 - (_volumeClock.elapsedMilliseconds - _lastVolumeSentMs);
    if (_queuedVolumeFromDrag && remainingMs > 0) {
      _volumeDragTimer = Timer(
        Duration(milliseconds: remainingMs),
        _dispatchQueuedVolume,
      );
      return;
    }
    unawaited(_sendQueuedVolume());
  }

  Future<void> _sendQueuedVolume() async {
    final generation = _volumeGeneration;
    final target = _queuedVolume!;
    _queuedVolume = null;
    _sendingVolume = true;
    _lastVolumeSentMs = _volumeClock.elapsedMilliseconds;
    try {
      // One in-flight command; newer input replaces the queued target, never builds a backlog.
      await command('volume', {'value': target});
      if (generation != _volumeGeneration) return;
      if (_queuedVolume == null) {
        _volumeAcknowledgedRevision = state.value.revision;
        _volumeFeedbackTimer = Timer(const Duration(seconds: 2), () {
          _clearVolumeFeedback();
          unawaited(_syncNativeVolumeSession());
        });
      }
    } catch (exception) {
      if (generation != _volumeGeneration) return;
      error.value = '$exception';
      _queuedVolume = null;
      _clearVolumeFeedback();
      unawaited(_syncNativeVolumeSession());
    } finally {
      if (generation == _volumeGeneration) {
        _sendingVolume = false;
        _dispatchQueuedVolume();
      }
    }
  }

  void _clearVolumeFeedback() {
    _volumeFeedbackTimer?.cancel();
    _volumeAcknowledgedRevision = null;
    requestedVolume.value = null;
  }

  void _resetControlCommands() {
    ++_seekGeneration;
    _clearSeekFeedback();
    ++_volumeGeneration;
    _volumeDragTimer?.cancel();
    _volumeDragTimer = null;
    _volumeOverlayTimer?.cancel();
    volumeFeedbackVisible.value = false;
    _lastVolumeSentMs = -80;
    _queuedVolumeFromDrag = false;
    _queuedVolume = null;
    _sendingVolume = false;
    _clearVolumeFeedback();
  }

  void _closeTransport() {
    final socket = _socket;
    unawaited(_subscription?.cancel());
    _subscription = null;
    _socket = null;
    _dialClient?.close(force: true);
    _dialClient = null;
    if (socket != null) {
      unawaited(socket.close().then<void>((_) {}, onError: (Object _) {}));
    }
  }

  Future<void> disconnect() async {
    ++_connectionGeneration;
    _reconnectTimer?.cancel();
    stopDeviceSearch();
    if (_handshake?.isCompleted == false) {
      _handshake!.completeError(StateError('已断开遥控'));
    }
    _closeTransport();
    _failPending('已断开遥控');
    connected.value = false;
    checkingConnection.value = false;
    remoteMode.value = false;
    _volumeBeforeMute = null;
    _reconnectAttempt = 0;
    _resetControlCommands();
    state.value = const RemotePlaybackState();
    error.value = '';
    await _pairing?.put('selected', 'false');
    await _onRemotePlaybackChanged?.call(false);
    await _syncNativeVolumeSession();
  }

  void _connectionLost(int generation, String message) {
    if (generation != _connectionGeneration) return;
    ++_connectionGeneration;
    connected.value = false;
    checkingConnection.value = false;
    _closeTransport();
    _failPending(message);
    _resetControlCommands();
    unawaited(_syncNativeVolumeSession());
    if (_handshake?.isCompleted == false) {
      _handshake!.completeError(StateError(message));
    }
    if (error.value.isEmpty) error.value = message;
    _scheduleReconnect(immediate: true);
  }

  void _scheduleReconnect({bool immediate = false}) {
    if (isClosed ||
        _needsPairing ||
        connected.value ||
        _connectionAttempt != null ||
        !remoteMode.value ||
        !_foreground ||
        _address == null ||
        _pairing == null) {
      return;
    }
    if (!immediate && (_reconnectTimer?.isActive ?? false)) return;
    _reconnectTimer?.cancel();
    const retrySeconds = [1, 2, 4, 8];
    final delay = immediate
        ? Duration.zero
        : Duration(
            seconds:
                retrySeconds[(_reconnectAttempt++).clamp(
                  0,
                  retrySeconds.length - 1,
                )],
          );
    _reconnectTimer = Timer(delay, () async {
      if (!_foreground || !remoteMode.value || connected.value || isClosed) {
        return;
      }
      unawaited(searchDevices());
      try {
        await connect(_address!, automatic: true);
      } catch (_) {
        // connect schedules the next bounded retry; pairing errors stop automatic attempts.
      }
    });
  }

  Future<void> _checkConnection() async {
    if (!connected.value || checkingConnection.value || !_foreground) return;
    final generation = _connectionGeneration;
    final startedAt = DateTime.now();
    checkingConnection.value = true;
    try {
      await command('state').timeout(const Duration(seconds: 2));
    } catch (_) {
      // A pushed state also proves liveness when a command acknowledgement is delayed.
      if (generation == _connectionGeneration &&
          _foreground &&
          !(_lastMessageAt?.isAfter(startedAt) ?? false)) {
        _connectionLost(generation, '连接正在恢复，电视会继续播放');
      }
    } finally {
      if (generation == _connectionGeneration) checkingConnection.value = false;
    }
  }

  void _failPending(String message) {
    for (final request in _pending.values) {
      if (!request.isCompleted) request.completeError(StateError(message));
    }
    _pending.clear();
  }

  Future<void> _syncNativeVolumeSession() async {
    if (!_hasNativeVolumeControls) return;
    try {
      await _volumeChannel.invokeMethod<void>('updateSession', {
        'enabled': remoteMode.value,
        'available': canAdjustVolume,
        'volume': televisionVolume,
        'playing': state.value.status == 'PLAYING',
        'title': state.value.title,
        'deviceName': deviceName.value,
      });
    } on MissingPluginException {
      /* Desktop preview. */
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground && _resumeDiscoveryOnForeground) {
      _resumeDiscoveryOnForeground = false;
      unawaited(searchDevices());
    }
    if (_foreground && remoteMode.value) {
      unawaited(_syncNativeVolumeSession());
      _reconnectAttempt = 0;
      if (connected.value) {
        unawaited(_checkConnection());
      } else {
        _scheduleReconnect(immediate: true);
      }
    }
    if (!_foreground) {
      _reconnectTimer?.cancel();
      stopDeviceSearch(resumeWhenForeground: true);
    }
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    ++_connectionGeneration;
    _reconnectTimer?.cancel();
    _sessionCheckTimer?.cancel();
    unawaited(_networkSubscription?.cancel());
    stopDeviceSearch();
    if (_handshake?.isCompleted == false) {
      _handshake!.completeError(StateError('遥控会话结束'));
    }
    _closeTransport();
    _failPending('遥控会话结束');
    connected.value = false;
    remoteMode.value = false;
    _resetControlCommands();
    unawaited(_syncNativeVolumeSession());
    if (_hasNativeVolumeControls) {
      _volumeChannel.setMethodCallHandler(null);
    }
    super.onClose();
  }
}
