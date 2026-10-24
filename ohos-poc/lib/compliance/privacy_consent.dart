import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_ce/hive.dart';

import 'legal_pages.dart';
import 'release_metadata.dart';

/// Only local storage is touched until this version of the policy is accepted.
abstract final class PrivacyConsentStore {
  static const boxName = 'privacy_consent';

  static Future<bool> hasAcceptedCurrentPolicy() async {
    final box = await Hive.openBox<String>(boxName);
    return box.get('accepted_version') == ReleaseMetadata.policyVersion;
  }

  static Future<void> acceptCurrentPolicy() async {
    final box = await Hive.openBox<String>(boxName);
    await box.put('accepted_version', ReleaseMetadata.policyVersion);
    await box.put('accepted_at', DateTime.now().toUtc().toIso8601String());
  }

  static Future<void> withdraw() async {
    final box = await Hive.openBox<String>(boxName);
    await box.clear();
  }
}

class PrivacyConsentPage extends StatefulWidget {
  const PrivacyConsentPage({super.key, required this.onAccepted});
  final Future<void> Function() onAccepted;

  @override
  State<PrivacyConsentPage> createState() => _PrivacyConsentPageState();
}

class _PrivacyConsentPageState extends State<PrivacyConsentPage> {
  bool _saving = false;
  bool _declined = false;
  String? _error;

  Future<void> _accept() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    var consentSaved = false;
    try {
      await PrivacyConsentStore.acceptCurrentPolicy();
      consentSaved = true;
      await widget.onAccepted();
    } catch (error, stackTrace) {
      assert(() {
        debugPrint('Privacy consent failed (${error.runtimeType}): $error');
        debugPrintStack(stackTrace: stackTrace);
        return true;
      }());
      if (mounted) {
        setState(() {
          _error = consentSaved ? '同意记录已保存，应用启动失败，请重试' : '无法保存选择，请重试';
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _decline() async {
    setState(() => _declined = true);
    // Flutter-OH handles this through its platform channel. If an embedding
    // keeps the page open, it remains offline and the reader is not trapped.
    try {
      await SystemNavigator.pop();
    } on PlatformException {
      /* Stay offline. */
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('欢迎使用跃映')),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const Icon(Icons.privacy_tip_outlined, size: 56),
              const SizedBox(height: 20),
              Text(
                '先了解信息如何使用',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 16),
              const Text(
                '本应用用于浏览 B站视频并控制同一局域网的电视。'
                '浏览、搜索和可选扫码登录会连接 B站服务；电视发现与遥控会处理局域网地址、'
                '随机连接标识和播放状态。登录凭据、搜索历史和连接记录保存在本机应用私有目录。'
                '手机不播放视频，也不向电视发送手机的 B站登录凭据。',
              ),
              const SizedBox(height: 16),
              const Text(
                '在你同意前，不初始化视频浏览、电视自动发现或自动重连。'
                '你可以先离线阅读以下文件；不同意将退出。之后可在“我的 → 关于与隐私”中查看和撤回。',
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('隐私政策'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => openLegalDocument(context, LegalDocument.privacy),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('用户协议'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => openLegalDocument(context, LegalDocument.terms),
              ),
              if (_declined) ...[
                const SizedBox(height: 12),
                const Text('你尚未同意，应用保持离线；可以关闭应用或继续阅读。'),
              ],
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _saving ? null : _accept,
                child: Text(_saving ? '正在保存…' : '同意隐私政策及用户协议并继续'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _saving ? null : _decline,
                child: const Text('不同意并退出'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
