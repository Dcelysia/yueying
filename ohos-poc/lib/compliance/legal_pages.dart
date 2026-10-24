import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'release_metadata.dart';

enum LegalDocument {
  privacy('隐私政策', 'assets/legal/privacy-policy.md'),
  terms('用户协议', 'assets/legal/user-agreement.md'),
  notices('开源项目与第三方组件说明', 'assets/legal/NOTICE.md');

  const LegalDocument(this.title, this.asset);
  final String title;
  final String asset;
}

Future<void> openLegalDocument(BuildContext context, LegalDocument document) =>
    Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => LegalDocumentPage(document: document)),
    );

void registerProjectLicense() {
  LicenseRegistry.addLicense(() async* {
    final license = await rootBundle.loadString(
      'assets/legal/licenses/PiliPlus-GPL-3.0.txt',
    );
    yield LicenseEntryWithLineBreaks([
      'Yueying / PiliPlus-derived code',
    ], license);
  });
}

class LegalDocumentPage extends StatelessWidget {
  const LegalDocumentPage({super.key, required this.document});
  final LegalDocument document;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(document.title)),
    body: FutureBuilder<String>(
      future: rootBundle.loadString(document.asset),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Center(
            child: snapshot.hasError
                ? const Text('暂时无法读取内置文件，请重新打开')
                : const CircularProgressIndicator(),
          );
        }
        final text = ReleaseMetadata.renderDocument(snapshot.data!);
        return SelectionArea(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (ReleaseMetadata.missingPublicationFields.isNotEmpty)
                const Padding(
                  padding: EdgeInsets.only(bottom: 20),
                  child: Text('开发测试版：发布资料待补齐；此版本不得作为正式发布版本提交。'),
                ),
              for (final paragraph in text.split('\n\n'))
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    paragraph.replaceFirst(RegExp(r'^#{1,3} '), ''),
                    style: paragraph.startsWith('# ')
                        ? Theme.of(context).textTheme.headlineSmall
                        : paragraph.startsWith('## ')
                        ? Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          )
                        : Theme.of(
                            context,
                          ).textTheme.bodyMedium?.copyWith(height: 1.6),
                  ),
                ),
            ],
          ),
        );
      },
    ),
  );
}

class LegalCenterPage extends StatefulWidget {
  const LegalCenterPage({
    super.key,
    this.onClearConnections,
    this.onClearSearchHistory,
    this.onSignOut,
    this.onWithdrawConsent,
  });
  final Future<void> Function()? onClearConnections;
  final Future<void> Function()? onClearSearchHistory;
  final Future<void> Function()? onSignOut;
  final Future<void> Function()? onWithdrawConsent;

  @override
  State<LegalCenterPage> createState() => _LegalCenterPageState();
}

class _LegalCenterPageState extends State<LegalCenterPage> {
  bool _busy = false;

  Future<void> _performDataAction(
    String title,
    String explanation,
    Future<void> Function() action,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(explanation),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$title已完成')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('操作未完成，请重试')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('关于与隐私')),
    body: ListView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      children: [
        const ListTile(
          title: Text('跃映'),
          subtitle: Text('浏览视频与家庭电视控制 · 1.0.0'),
        ),
        const ListTile(
          title: Text('开源二次开发'),
          subtitle: Text(
            '基于 PiliPlus、NeoBV 等开源项目二次开发；保留原作者版权与许可证。'
            'dcelysia 维护本改版。',
          ),
        ),
        if (ReleaseMetadata.missingPublicationFields.isNotEmpty)
          const ListTile(
            leading: Icon(Icons.construction_outlined),
            title: Text('开发测试版：发布资料待补齐'),
            subtitle: Text('运营者、联系邮箱、对应版本源码和公开政策链接尚需完成配置。'),
          ),
        for (final document in LegalDocument.values)
          ListTile(
            title: Text(document.title),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => openLegalDocument(context, document),
          ),
        ListTile(
          title: const Text('第三方开源许可证'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => showLicensePage(
            context: context,
            applicationName: '跃映',
            applicationVersion: '1.0.0',
            applicationLegalese: 'PiliPlus 派生代码沿用 GPL-3.0，电视接收端另见其 MIT 许可证。',
          ),
        ),
        if (ReleaseMetadata.sourceUrl.isNotEmpty)
          ListTile(
            title: const Text('对应版本源码'),
            subtitle: SelectableText(ReleaseMetadata.sourceUrl),
          ),
        if (ReleaseMetadata.operatorName.isNotEmpty)
          ListTile(
            title: const Text('运营者'),
            subtitle: SelectableText(ReleaseMetadata.operatorName),
          ),
        if (ReleaseMetadata.contactEmail.isNotEmpty)
          ListTile(
            title: const Text('联系邮箱'),
            subtitle: SelectableText(ReleaseMetadata.contactEmail),
          ),
        const Divider(),
        if (widget.onSignOut != null)
          ListTile(
            leading: const Icon(Icons.logout_outlined),
            title: const Text('退出 B站登录并删除本机凭据'),
            subtitle: const Text('不会注销 B站账号，也不会停止电视播放。'),
            onTap: _busy
                ? null
                : () => _performDataAction(
                    '退出登录',
                    '将删除本机保存的 B站登录凭据。',
                    widget.onSignOut!,
                  ),
          ),
        if (widget.onClearSearchHistory != null)
          ListTile(
            leading: const Icon(Icons.history_outlined),
            title: const Text('清除本机搜索历史'),
            onTap: _busy
                ? null
                : () => _performDataAction(
                    '清除搜索历史',
                    '只删除本机搜索词，不删除 B站服务器上的记录。',
                    widget.onClearSearchHistory!,
                  ),
          ),
        if (widget.onClearConnections != null)
          ListTile(
            leading: const Icon(Icons.tv_off_outlined),
            title: const Text('清除本机电视连接记录'),
            subtitle: const Text('断开当前手机连接；电视和其他手机继续播放。'),
            onTap: _busy
                ? null
                : () => _performDataAction(
                    '清除电视连接记录',
                    '将删除已保存的电视地址、连接标识和令牌，之后需要重新连接。',
                    widget.onClearConnections!,
                  ),
          ),
        if (widget.onWithdrawConsent != null)
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('撤回同意并退出'),
            subtitle: const Text('清除本机登录凭据、搜索历史和电视连接记录；停止本机浏览与遥控。'),
            onTap: _busy
                ? null
                : () => _performDataAction(
                    '撤回同意',
                    '本机数据将清除，应用停止联网并退出；再次使用需重新同意。电视不会停止。',
                    widget.onWithdrawConsent!,
                  ),
          ),
      ],
    ),
  );
}
