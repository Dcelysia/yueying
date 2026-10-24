// Layout adapted from PiliPlus home/search/mine/video cards (GPL-3.0).
// HarmonyOS intentionally has no local video-player dependency.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'bili_client.dart';
import '../compliance/legal_pages.dart';

String _errorMessage(Object error) =>
    error is BiliRequestException ? error.message : '暂时无法加载，请检查网络后重试';
String _duration(int seconds) {
  final minutes = (seconds ~/ 60 % 60).toString().padLeft(2, '0');
  final tail = (seconds % 60).toString().padLeft(2, '0');
  return seconds >= 3600
      ? '${seconds ~/ 3600}:$minutes:$tail'
      : '${seconds ~/ 60}:$tail';
}

String _count(int value) =>
    value >= 10000 ? '${(value / 10000).toStringAsFixed(1)}万' : '$value';

typedef _LoadVideos =
    Future<BiliVideoPage> Function(int page, int max, int viewAt);

/// The existing Android browsing structure, without a phone video player.
class BiliBrowsePage extends StatefulWidget {
  const BiliBrowsePage({
    super.key,
    required this.onPlayOnTelevision,
    this.actions = const [],
    this.bottomAccessory,
    this.floatingActionButton,
    this.onClearTelevisionRecords,
    this.onWithdrawPrivacy,
  });
  final Future<void> Function(Map<String, dynamic> media) onPlayOnTelevision;
  final List<Widget> actions;
  final Widget? bottomAccessory;
  final Widget? floatingActionButton;
  final Future<void> Function()? onClearTelevisionRecords;
  final Future<void> Function()? onWithdrawPrivacy;
  @override
  State<BiliBrowsePage> createState() => _BiliBrowsePageState();
}

class _BiliBrowsePageState extends State<BiliBrowsePage> {
  final BiliClient _client = BiliClient();
  bool _ready = false;
  bool _loading = true;
  bool _sending = false;
  String? _error;
  int _tab = 0;
  int _feed = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _client.initialize();
      if (!mounted) return;
      setState(() {
        _ready = true;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = _errorMessage(error);
        _loading = false;
      });
    }
  }

  Future<void> _login() async {
    if (!_ready) return;
    final loggedIn = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => _BiliLoginPage(client: _client)),
    );
    if (mounted && loggedIn == true) setState(() {});
  }

  Future<void> _logout() async {
    await _client.logout();
    if (mounted) setState(() {});
  }

  Future<void> _openHistory() async {
    if (!_client.loggedIn) await _login();
    if (!mounted || !_client.loggedIn) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('历史记录')),
          body: _VideoCollection(
            load: (page, max, viewAt) =>
                _client.history(max: max, viewAt: viewAt),
            onVideo: _showVideo,
            horizontal: true,
            emptyText: '暂时没有观看历史',
          ),
        ),
      ),
    );
  }

  Future<void> _openFavorites() async {
    if (!_client.loggedIn) await _login();
    if (!mounted || !_client.loggedIn) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) =>
            _FavoriteFoldersPage(client: _client, onVideo: _showVideo),
      ),
    );
  }

  void _openSearch() {
    if (!_ready) return;
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => _SearchPage(client: _client, onVideo: _showVideo),
      ),
    );
  }

  Future<void> _showVideo(BiliVideo video) async {
    if (_sending) return;
    final media = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) => _VideoDetailsPage(client: _client, selected: video),
      ),
    );
    if (!mounted || media == null) return;
    setState(() {
      _sending = true;
    });
    try {
      await widget.onPlayOnTelevision(media);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is BiliRequestException
                  ? error.message
                  : '未能发送到电视，请确认电视已连接后重试',
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _client.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      floatingActionButton: widget.floatingActionButton,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
              child: SizedBox(
                height: 48,
                child: Row(
                  children: [
                    if (_tab == 0)
                      Expanded(
                        child: Material(
                          color: colors.onSecondaryContainer.withValues(
                            alpha: .05,
                          ),
                          borderRadius: BorderRadius.circular(25),
                          child: InkWell(
                            onTap: _ready ? _openSearch : null,
                            borderRadius: BorderRadius.circular(25),
                            child: SizedBox(
                              height: 44,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.search_outlined,
                                      semanticLabel: '搜索',
                                    ),
                                    const SizedBox(width: 10),
                                    Text(
                                      '搜索',
                                      style: TextStyle(color: colors.outline),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (_tab == 1) const Spacer(),
                    ...widget.actions,
                    const SizedBox(width: 8),
                    if (_tab == 0)
                      Semantics(
                        label: '我的',
                        button: true,
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () => setState(() {
                            _tab = 1;
                          }),
                          child: _AccountAvatar(
                            account: _client.account,
                            radius: 17,
                          ),
                        ),
                      ),
                    if (_tab == 1)
                      IconButton(
                        tooltip: '关于与隐私',
                        icon: const Icon(Icons.info_outline_rounded),
                        onPressed: () => Navigator.of(context).push<void>(
                          MaterialPageRoute(
                            builder: (_) => LegalCenterPage(
                              onClearConnections:
                                  widget.onClearTelevisionRecords,
                              onClearSearchHistory: _client.clearSearchHistory,
                              onSignOut: _client.loggedIn ? _logout : null,
                              onWithdrawConsent:
                                  widget.onWithdrawPrivacy == null
                                  ? null
                                  : () async {
                                      await _client.logout();
                                      await _client.clearSearchHistory();
                                      _client.dispose();
                                      await widget.onWithdrawPrivacy!();
                                    },
                            ),
                          ),
                        ),
                      ),
                    if (_tab == 1 && _client.loggedIn)
                      IconButton(
                        tooltip: '退出登录',
                        onPressed: _logout,
                        icon: const Icon(Icons.logout_outlined),
                      ),
                  ],
                ),
              ),
            ),
            if (_sending) const LinearProgressIndicator(),
            Expanded(
              child: !_ready
                  ? _loading
                        ? const Center(child: CircularProgressIndicator())
                        : _EmptyState(
                            icon: Icons.cloud_off_outlined,
                            title: _error ?? '暂时无法连接 B站',
                            actionLabel: '重试',
                            onAction: _initialize,
                          )
                  : IndexedStack(
                      index: _tab,
                      children: [_homePage(), _minePage()],
                    ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.bottomAccessory != null) widget.bottomAccessory!,
          NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (index) => setState(() {
              _tab = index;
            }),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home_rounded),
                label: '首页',
              ),
              NavigationDestination(
                icon: Icon(Icons.person_outline_rounded),
                selectedIcon: Icon(Icons.person_rounded),
                label: '我的',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _homePage() => DefaultTabController(
    length: 2,
    initialIndex: _feed,
    child: Column(
      children: [
        SizedBox(
          height: 46,
          child: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.center,
            dividerColor: Colors.transparent,
            splashBorderRadius: BorderRadius.circular(12),
            onTap: (index) {
              _feed = index;
            },
            tabs: const [
              Tab(text: '推荐'),
              Tab(text: '热门'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            children: [
              _VideoCollection(
                key: ValueKey('recommend-${_client.account?.mid}'),
                load: (page, _, _) => _client.recommended(page),
                onVideo: _showVideo,
              ),
              _VideoCollection(
                load: (page, _, _) => _client.popular(page),
                onVideo: _showVideo,
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _minePage() {
    final account = _client.account;
    final colors = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.only(top: 16, bottom: 24),
      children: [
        InkWell(
          onTap: account == null ? _login : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              children: [
                _AccountAvatar(account: account, radius: 27.5),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        account == null
                            ? '点击登录'
                            : '${account.name}  LV${account.level}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        account == null
                            ? '硬币 -     经验 -/-'
                            : '硬币 ${account.coins}     经验 ${account.currentExperience}/${account.nextExperience}',
                        style: TextStyle(fontSize: 12, color: colors.outline),
                      ),
                    ],
                  ),
                ),
                if (account == null) const Icon(Icons.chevron_right_rounded),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _MineAction(
              icon: Icons.star_border_rounded,
              title: '我的收藏',
              onTap: _openFavorites,
            ),
            _MineAction(
              icon: Icons.history_rounded,
              title: '观看记录',
              onTap: _openHistory,
            ),
          ],
        ),
        if (account != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
            child: Text(
              '手机账号用于浏览与历史。电视使用电视端自己的登录状态。',
              style: TextStyle(fontSize: 12, color: colors.outline),
            ),
          ),
      ],
    );
  }
}

class _AccountAvatar extends StatelessWidget {
  const _AccountAvatar({required this.account, required this.radius});
  final BiliAccount? account;
  final double radius;
  @override
  Widget build(BuildContext context) => CircleAvatar(
    radius: radius,
    backgroundImage: account?.face.isNotEmpty == true
        ? NetworkImage(account!.face)
        : null,
    child: account == null
        ? Icon(
            radius > 20 ? Icons.live_tv_rounded : Icons.person_rounded,
            size: radius,
          )
        : null,
  );
}

class _MineAction extends StatelessWidget {
  const _MineAction({
    required this.icon,
    required this.title,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(12),
    child: SizedBox(
      width: 90,
      height: 80,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.secondary),
          const SizedBox(height: 6),
          Text(title, style: const TextStyle(fontSize: 13)),
        ],
      ),
    ),
  );
}

/// Shared pagination for recommendation, search, history and folder contents.
class _VideoCollection extends StatefulWidget {
  const _VideoCollection({
    super.key,
    required this.load,
    required this.onVideo,
    this.horizontal = false,
    this.emptyText = '暂时没有视频',
  });
  final _LoadVideos load;
  final ValueChanged<BiliVideo> onVideo;
  final bool horizontal;
  final String emptyText;
  @override
  State<_VideoCollection> createState() => _VideoCollectionState();
}

class _VideoCollectionState extends State<_VideoCollection>
    with AutomaticKeepAliveClientMixin {
  final List<BiliVideo> _videos = [];
  int _page = 0;
  int _max = 0;
  int _viewAt = 0;
  int _generation = 0;
  bool _loading = false;
  bool _more = false;
  String? _error;
  @override
  bool get wantKeepAlive => true;
  @override
  void initState() {
    super.initState();
    unawaited(_load(reset: true));
  }

  Future<void> _load({required bool reset}) async {
    if (!reset && (_loading || !_more)) return;
    final generation = ++_generation;
    final page = reset ? 1 : _page + 1;
    setState(() {
      _loading = true;
      _error = null;
      if (reset) {
        _videos.clear();
        _more = false;
      }
    });
    try {
      final result = await widget.load(
        page,
        reset ? 0 : _max,
        reset ? 0 : _viewAt,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        final ids = <int>{for (final item in _videos) item.aid};
        for (final item in result.items) {
          if (ids.add(item.aid)) _videos.add(item);
        }
        _page = page;
        _max = result.historyMax;
        _viewAt = result.historyViewAt;
        _more = result.hasMore;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _error = _errorMessage(error);
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    ++_generation;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_videos.isEmpty) {
      if (_loading) return const Center(child: CircularProgressIndicator());
      return _EmptyState(
        icon: _error != null
            ? Icons.cloud_off_outlined
            : Icons.video_library_outlined,
        title: _error ?? widget.emptyText,
        actionLabel: _error != null ? '重试' : '刷新',
        onAction: () => _load(reset: true),
      );
    }
    return RefreshIndicator(
      onRefresh: () => _load(reset: true),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          if (widget.horizontal)
            SliverList.builder(
              itemCount: _videos.length,
              itemBuilder: (_, index) => _VideoRow(
                video: _videos[index],
                onTap: () => widget.onVideo(_videos[index]),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(10, 7, 10, 10),
              sliver: SliverLayoutBuilder(
                builder: (context, constraints) {
                  // Same two-column portrait cards and 16:9 covers as Android.
                  final columns = constraints.crossAxisExtent < 600
                      ? 2
                      : (constraints.crossAxisExtent / 240).ceil();
                  final width =
                      (constraints.crossAxisExtent - 8 * (columns - 1)) /
                      columns;
                  return SliverGrid.builder(
                    itemCount: _videos.length,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                      mainAxisExtent:
                          width * 9 / 16 +
                          94 * MediaQuery.textScalerOf(context).scale(1),
                    ),
                    itemBuilder: (_, index) => _VideoCard(
                      video: _videos[index],
                      onTap: () => widget.onVideo(_videos[index]),
                    ),
                  );
                },
              ),
            ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              child: Column(
                children: [
                  if (_error != null)
                    Text(_error!, textAlign: TextAlign.center),
                  if (_loading)
                    const CircularProgressIndicator()
                  else if (_more)
                    TextButton(
                      onPressed: () => _load(reset: false),
                      child: Text(_error == null ? '加载更多' : '重试加载更多'),
                    )
                  else
                    const Text('没有更多了'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VideoCard extends StatelessWidget {
  const _VideoCard({required this.video, required this.onTap});
  final BiliVideo video;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final outline = Theme.of(context).colorScheme.outline;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _VideoCover(url: video.cover),
                  if (video.duration > 0)
                    Positioned(
                      right: 7,
                      bottom: 6,
                      child: _DurationBadge(text: _duration(video.duration)),
                    ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(6, 5, 6, 5),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        video.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(height: 1.38),
                      ),
                    ),
                    _VideoStatistics(video: video),
                    Row(
                      children: [
                        Icon(
                          Icons.account_box_outlined,
                          size: 12,
                          color: outline,
                        ),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(
                            video.author,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              height: 1.5,
                              color: outline,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VideoStatistics extends StatelessWidget {
  const _VideoStatistics({required this.video});
  final BiliVideo video;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      if (video.views > 0) ...[
        const Icon(Icons.play_circle_outline_rounded, size: 12),
        const SizedBox(width: 2),
        Text(_count(video.views), style: const TextStyle(fontSize: 11)),
        const SizedBox(width: 6),
      ],
      if (video.danmaku > 0) ...[
        const Icon(Icons.subtitles_outlined, size: 12),
        const SizedBox(width: 2),
        Text(_count(video.danmaku), style: const TextStyle(fontSize: 11)),
      ],
    ],
  );
}

class _DurationBadge extends StatelessWidget {
  const _DurationBadge({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: .65),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      child: Text(
        text,
        style: const TextStyle(fontSize: 11, color: Colors.white),
      ),
    ),
  );
}

class _VideoRow extends StatelessWidget {
  const _VideoRow({required this.video, required this.onTap});
  final BiliVideo video;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: MediaQuery.sizeOf(context).width.clamp(0, 600) * .38,
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _VideoCover(url: video.cover),
                    if (video.historyPositionMs != null || video.duration > 0)
                      Positioned(
                        right: 5,
                        bottom: 5,
                        child: _DurationBadge(
                          text: video.historyPositionMs != null
                              ? video.historyPositionMs == 0
                                    ? '从头播放'
                                    : '看到 ${_duration(video.historyPositionMs! ~/ 1000)}'
                              : _duration(video.duration),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  video.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(height: 1.38),
                ),
                const SizedBox(height: 5),
                Text(
                  video.author,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
                const SizedBox(height: 4),
                _VideoStatistics(video: video),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _VideoCover extends StatelessWidget {
  const _VideoCover({required this.url});
  final String url;
  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    child: url.isEmpty
        ? const Center(child: Icon(Icons.video_library_outlined))
        : Image.network(
            url,
            fit: BoxFit.cover,
            cacheWidth: 720,
            errorBuilder: (_, _, _) =>
                const Center(child: Icon(Icons.broken_image_outlined)),
          ),
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.actionLabel,
    required this.onAction,
  });
  final IconData icon;
  final String title;
  final String actionLabel;
  final VoidCallback onAction;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 40, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 16),
          Text(title, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          TextButton(onPressed: onAction, child: Text(actionLabel)),
        ],
      ),
    ),
  );
}

class _FavoriteFoldersPage extends StatefulWidget {
  const _FavoriteFoldersPage({required this.client, required this.onVideo});
  final BiliClient client;
  final ValueChanged<BiliVideo> onVideo;
  @override
  State<_FavoriteFoldersPage> createState() => _FavoriteFoldersPageState();
}

class _FavoriteFoldersPageState extends State<_FavoriteFoldersPage> {
  late Future<List<BiliFavoriteFolder>> _folders = widget.client
      .favoriteFolders();
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('我的收藏')),
    body: FutureBuilder<List<BiliFavoriteFolder>>(
      future: _folders,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _EmptyState(
            icon: Icons.cloud_off_outlined,
            title: _errorMessage(snapshot.error!),
            actionLabel: '重试',
            onAction: () => setState(() {
              _folders = widget.client.favoriteFolders();
            }),
          );
        }
        final folders = snapshot.data ?? const [];
        if (folders.isEmpty) {
          return _EmptyState(
            icon: Icons.folder_open_outlined,
            title: '还没有收藏夹',
            actionLabel: '刷新',
            onAction: () => setState(() {
              _folders = widget.client.favoriteFolders();
            }),
          );
        }
        return RefreshIndicator(
          onRefresh: () async {
            final request = widget.client.favoriteFolders();
            setState(() {
              _folders = request;
            });
            try {
              await request;
            } catch (_) {
              // FutureBuilder displays the error and explicit retry action.
            }
          },
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(top: 7),
            itemCount: folders.length,
            itemBuilder: (context, index) {
              final folder = folders[index];
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                leading: Container(
                  width: 72,
                  height: 56,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: Theme.of(context).colorScheme.secondaryContainer,
                  ),
                  child: const Icon(Icons.folder_outlined, size: 30),
                ),
                title: Text(folder.title),
                subtitle: Text('${folder.count}个内容'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) => Scaffold(
                      appBar: AppBar(title: Text(folder.title)),
                      body: _VideoCollection(
                        load: (page, _, _) =>
                            widget.client.favorites(folder.id, page),
                        onVideo: widget.onVideo,
                        horizontal: true,
                        emptyText: '收藏夹里还没有可播放的视频',
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    ),
  );
}

class _SearchPage extends StatefulWidget {
  const _SearchPage({required this.client, required this.onVideo});
  final BiliClient client;
  final ValueChanged<BiliVideo> onVideo;
  @override
  State<_SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<_SearchPage> {
  final TextEditingController _text = TextEditingController();
  late Future<List<String>> _trending = widget.client.trendingSearches();
  Future<void> _submit([String? text]) async {
    final keyword = (text ?? _text.text).trim();
    if (keyword.isEmpty) return;
    _text.text = keyword;
    FocusScope.of(context).unfocus();
    await widget.client.rememberSearch(keyword);
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(keyword)),
          body: DefaultTabController(
            length: 1,
            child: Column(
              children: [
                const Align(
                  alignment: Alignment.centerLeft,
                  child: TabBar(
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    tabs: [Tab(text: '视频')],
                  ),
                ),
                Expanded(
                  child: _VideoCollection(
                    load: (page, _, _) => widget.client.search(keyword, page),
                    onVideo: widget.onVideo,
                    horizontal: true,
                    emptyText: '没有找到相关视频',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: TextField(
        controller: _text,
        autofocus: true,
        textInputAction: TextInputAction.search,
        onSubmitted: _submit,
        decoration: const InputDecoration(
          hintText: '搜索',
          border: InputBorder.none,
        ),
      ),
      actions: [
        IconButton(
          tooltip: '清空',
          onPressed: _text.clear,
          icon: const Icon(Icons.clear, size: 22),
        ),
        IconButton(
          tooltip: '搜索',
          onPressed: _submit,
          icon: const Icon(Icons.search, size: 22),
        ),
        const SizedBox(width: 10),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
      children: [
        Text(
          '大家都在搜',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        FutureBuilder<List<String>>(
          future: _trending,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const LinearProgressIndicator();
            }
            if (snapshot.hasError) {
              return TextButton(
                onPressed: () => setState(() {
                  _trending = widget.client.trendingSearches();
                }),
                child: const Text('热搜加载失败，点击重试'),
              );
            }
            final keywords = snapshot.data ?? const [];
            return Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (var index = 0; index < keywords.length; index++)
                  SizedBox(
                    width: (MediaQuery.sizeOf(context).width - 40) / 2,
                    child: InkWell(
                      onTap: () => _submit(keywords[index]),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 9),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                keywords[index],
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        if (widget.client.searchHistory.isNotEmpty) ...[
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: Text(
                  '搜索历史',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                tooltip: '清空搜索历史',
                onPressed: () async {
                  await widget.client.clearSearchHistory();
                  if (mounted) setState(() {});
                },
                icon: const Icon(Icons.delete_outline_rounded, size: 20),
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final keyword in widget.client.searchHistory)
                ActionChip(
                  label: Text(
                    keyword,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onPressed: () => _submit(keyword),
                ),
            ],
          ),
        ],
      ],
    ),
  );
}

class _VideoDetailsPage extends StatefulWidget {
  const _VideoDetailsPage({required this.client, required this.selected});
  final BiliClient client;
  final BiliVideo selected;
  @override
  State<_VideoDetailsPage> createState() => _VideoDetailsPageState();
}

class _VideoDetailsPageState extends State<_VideoDetailsPage> {
  BiliVideoDetails? _details;
  BiliPart? _part;
  String? _error;
  bool _loading = true;
  bool _resume = true;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final details = await widget.client.videoDetails(widget.selected);
      if (!mounted || generation != _generation) return;
      setState(() {
        _details = details;
        _part = details.parts.firstWhere(
          (part) => part.cid == details.resumeCid,
          orElse: () => details.parts.first,
        );
        _loading = false;
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _error = _errorMessage(error);
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    ++_generation;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final details = _details;
    final part = _part;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _VideoCover(
                    url: details?.video.cover ?? widget.selected.cover,
                  ),
                  ColoredBox(color: Colors.black.withValues(alpha: .6)),
                  const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.connected_tv_rounded,
                          color: Colors.white,
                          size: 40,
                        ),
                        SizedBox(height: 10),
                        Text('在电视上观看', style: TextStyle(color: Colors.white)),
                      ],
                    ),
                  ),
                  const Positioned(
                    top: 0,
                    left: 0,
                    child: BackButton(color: Colors.white),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? _EmptyState(
                      icon: Icons.cloud_off_outlined,
                      title: _error!,
                      actionLabel: '重试',
                      onAction: _load,
                    )
                  : details == null || part == null
                  ? const SizedBox.shrink()
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                      children: [
                        Text(
                          '简介',
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                              ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            const Icon(Icons.account_circle_outlined, size: 30),
                            const SizedBox(width: 10),
                            Text(details.video.author),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Text(
                          details.video.title,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        _VideoStatistics(video: details.video),
                        if (details.description.isNotEmpty)
                          ExpansionTile(
                            tilePadding: EdgeInsets.zero,
                            title: const Text('展开简介'),
                            children: [
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Text(details.description),
                              ),
                            ],
                          ),
                        const SizedBox(height: 12),
                        Text(
                          '选集（${details.parts.length}）',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 8),
                        for (final item in details.parts)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            selected: part.cid == item.cid,
                            leading: Icon(
                              part.cid == item.cid
                                  ? Icons.play_circle_outline_rounded
                                  : Icons.video_library_outlined,
                            ),
                            title: Text(
                              'P${item.page} ${item.title}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: Text(_duration(item.duration)),
                            onTap: () => setState(() {
                              _part = item;
                            }),
                          ),
                      ],
                    ),
            ),
            if (details != null && part != null && !_loading && _error == null)
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (part.cid == details.resumeCid &&
                          details.resumePositionMs > 0)
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            '从 ${_duration(details.resumePositionMs ~/ 1000)} 继续',
                          ),
                          value: _resume,
                          onChanged: (value) => setState(() {
                            _resume = value;
                          }),
                        ),
                      FilledButton.icon(
                        onPressed: () =>
                            Navigator.of(context).pop(<String, dynamic>{
                              'aid': details.video.aid,
                              'cid': part.cid,
                              'page': part.page,
                              'title': details.video.title.length > 1000
                                  ? details.video.title.substring(0, 1000)
                                  : details.video.title,
                              'positionMs':
                                  _resume && part.cid == details.resumeCid
                                  ? details.resumePositionMs
                                  : 0,
                            }),
                        icon: const Icon(Icons.connected_tv_rounded),
                        label: const Text('在电视播放'),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BiliLoginPage extends StatefulWidget {
  const _BiliLoginPage({required this.client});
  final BiliClient client;
  @override
  State<_BiliLoginPage> createState() => _BiliLoginPageState();
}

class _BiliLoginPageState extends State<_BiliLoginPage>
    with WidgetsBindingObserver {
  BiliQrCode? _code;
  Timer? _timer;
  DateTime? _expiresAt;
  bool _busy = false;
  bool _loading = true;
  bool _expired = false;
  bool _resumed = true;
  String _status = '请用 B站 App 扫描二维码并确认登录';
  String? _error;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _resumed = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    unawaited(_generate());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _resumed = state == AppLifecycleState.resumed;
    if (_resumed && !_expired && _code != null && !_loading) {
      unawaited(_poll());
    }
  }

  Future<void> _generate() async {
    final generation = ++_generation;
    _timer?.cancel();
    setState(() {
      _loading = true;
      _error = null;
      _expired = false;
      _code = null;
    });
    try {
      final code = await widget.client.createQrCode();
      if (!mounted || generation != _generation) return;
      setState(() {
        _code = code;
        _loading = false;
        _status = '请用 B站 App 扫描二维码并确认登录';
        _expiresAt = DateTime.now().add(const Duration(minutes: 3));
      });
      _timer = Timer.periodic(const Duration(seconds: 3), (_) {
        if (_resumed) unawaited(_poll());
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _error = _errorMessage(error);
        _loading = false;
      });
    }
  }

  Future<void> _poll() async {
    if (!mounted || _busy || !_resumed || _expired || _code == null) return;
    if (_expiresAt != null && DateTime.now().isAfter(_expiresAt!)) {
      _timer?.cancel();
      setState(() {
        _expired = true;
        _status = '二维码已过期，请刷新';
      });
      return;
    }
    final generation = _generation;
    _busy = true;
    try {
      final status = await widget.client.pollQrCode(
        _code!.key,
        isActive: () => mounted && generation == _generation,
      );
      if (!mounted || generation != _generation) return;
      if (status == 0) {
        _timer?.cancel();
        Navigator.of(context).pop(true);
      } else if (status == 86038) {
        _timer?.cancel();
        setState(() {
          _expired = true;
          _status = '二维码已过期，请刷新';
        });
      } else if (status == 86090 || status == 86101) {
        setState(() {
          _error = null;
          _status = status == 86090
              ? '已扫码，请在 B站 App 确认登录'
              : '请用 B站 App 扫描二维码并确认登录';
        });
      } else {
        _timer?.cancel();
        setState(() {
          _error = '登录状态已变化，请刷新二维码重试';
          _expired = true;
        });
      }
    } catch (error) {
      if (!mounted || generation != _generation) return;
      // A failure stops polling; retry is explicit rather than hammering login APIs.
      _timer?.cancel();
      setState(() {
        _error = _errorMessage(error);
        _expired = true;
      });
    } finally {
      _busy = false;
    }
  }

  @override
  void dispose() {
    ++_generation;
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final remaining = _expiresAt == null
        ? 180
        : _expiresAt!.difference(DateTime.now()).inSeconds.clamp(0, 180);
    return Scaffold(
      appBar: AppBar(title: const Text('登录')),
      body: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 20),
            const Text('使用 bilibili 官方 App 扫码登录'),
            const SizedBox(height: 20),
            Text(
              '剩余有效时间: $remaining 秒',
              style: TextStyle(color: theme.colorScheme.primary),
            ),
            const SizedBox(height: 5),
            TextButton.icon(
              onPressed: _loading ? null : _generate,
              icon: const Icon(Icons.refresh),
              label: const Text('刷新二维码'),
            ),
            if (_loading)
              const SizedBox(
                width: 200,
                height: 200,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_code != null)
              Center(
                child: Container(
                  width: 200,
                  height: 200,
                  color: Colors.white,
                  padding: const EdgeInsets.all(8),
                  child: QrImageView(
                    data: _code!.url,
                    size: 184,
                    backgroundColor: Colors.white,
                  ),
                ),
              ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                _error ?? _status,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _error != null
                      ? theme.colorScheme.error
                      : theme.colorScheme.secondary,
                ),
              ),
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                '请用另一台设备上的 B站 App 扫码确认。登录凭据仅保存在当前手机，'
                '投到电视时只发送视频编号和播放位置。',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
