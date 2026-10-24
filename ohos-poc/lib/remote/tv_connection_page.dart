import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:hive_ce/hive.dart';

import 'remote_device_discovery.dart';
import 'remote_playback_controller.dart';

/// Ported from the PiliPlus remote module.
///
/// Differences from the phone app: the manual IP/port form is persisted with
/// Hive instead of GStorage, and the icon font is the Material set because the
/// PiliPlus custom icon package is not part of this proof of concept.
class TvConnectionPage extends StatefulWidget {
  const TvConnectionPage({super.key});

  @override
  State<TvConnectionPage> createState() => _TvConnectionPageState();
}

class _TvConnectionPageState extends State<TvConnectionPage> {
  static const _manualBoxName = 'remoteManualConnection';

  final _address = TextEditingController();
  final _port = TextEditingController();
  final _remote = Get.find<RemotePlaybackController>();
  String? _message;
  Box<dynamic>? _form;

  @override
  void initState() {
    super.initState();
    unawaited(_loadForm());
    unawaited(_search());
  }

  Future<void> _loadForm() async {
    final box = await _openBox();
    final saved = _remote.savedDevice.value?.address;
    if (!mounted) return;
    setState(() {
      _form = box;
      _address.text = box.get('ip') as String? ?? saved?.host ?? '';
      _port.text =
          box.get('port') as String? ?? (saved == null ? '' : '${saved.port}');
    });
  }

  Future<Box<dynamic>> _openBox() async {
    final existing = _form;
    if (existing != null) return existing;
    return Hive.openBox(_manualBoxName);
  }

  Future<void> _saveManualConnection() async {
    final box = await _openBox();
    await box.putAll({'ip': _address.text.trim(), 'port': _port.text.trim()});
  }

  Future<void> _search() async {
    if (!mounted) return;
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
      if (mounted && _remote.connected.value) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) setState(() => _message = '$error');
    }
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
          ? '已连接'
          : busy
          ? '正在连接…'
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
            Card(
              margin: EdgeInsets.zero,
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                leading: Icon(connected ? Icons.tv : Icons.tv_off),
                title: Text(saved.name),
                subtitle: Text('$savedStatus\n${saved.address.authority}'),
                isThreeLine: true,
                trailing: busy || checking
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        connected ? Icons.check_circle : Icons.chevron_right,
                      ),
                onTap: busy || checking
                    ? null
                    : () => unawaited(_connect(saved: saved)),
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
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('自动搜索未找到时，可手动输入电视地址。'),
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
            onPressed: busy ? null : () => unawaited(_connect()),
            child: Text(busy ? '正在连接…' : '连接电视'),
          ),
          if (_message != null || connectionError.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(_message ?? connectionError),
            ),
          const SizedBox(height: 16),
          const Text('连接成功后会记住电视。电视的 B 站账号在电视内扫码登录，手机只发送视频编号。'),
        ],
      );
    }),
  );
}
