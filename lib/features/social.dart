import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/app_state.dart';
import '../core/models.dart';
import '../ui/forms.dart';
import '../ui/platform.dart';
import '../ui/widgets.dart';
import 'forum.dart';
import 'decoration.dart';

class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});
  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final query = TextEditingController();
  Timer? timer;
  String q = '', type = 'all';
  static const kinds = {
    'discussions': '讨论',
    'posts': '回复',
    'projects': '作品',
    'extensions': '扩展',
    'users': '用户',
  };
  @override
  void dispose() {
    timer?.cancel();
    query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FeaturePage(
    title: '搜索',
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: SearchBar(
            controller: query,
            autoFocus: true,
            hintText: '搜索讨论、回复、作品、用户',
            leading: const Icon(Icons.search_rounded),
            onSubmitted: (v) {
              timer?.cancel();
              setState(() => q = v.trim());
            },
            onChanged: (v) {
              timer?.cancel();
              timer = Timer(const Duration(milliseconds: 400), () {
                if (mounted) setState(() => q = v.trim());
              });
            },
            trailing: [
              IconButton(
                tooltip: '清空',
                onPressed: () {
                  timer?.cancel();
                  query.clear();
                  setState(() => q = '');
                },
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                for (final e in {'all': '全部', ...kinds}.entries)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(e.value),
                      selected: type == e.key,
                      onSelected: (_) => setState(() => type = e.key),
                    ),
                  ),
              ],
            ),
          ),
        ),
        Expanded(
          child: q.isEmpty
              ? const EmptyState(title: '搜索感兴趣的内容', icon: Icons.search_rounded)
              : PagedList(
                  cacheKey: '$q:$type',
                  emptyTitle: '没有找到相关内容',
                  load: (page) async {
                    final data = object(
                      await ref.read(apiProvider).get('/search', {
                        'q': q,
                        'type': type,
                        'page': page,
                        'pageSize': 20,
                      }),
                    );
                    final rows = <Json>[];
                    var total = 0;
                    for (final kind in kinds.keys) {
                      if (type != 'all' && type != kind) continue;
                      final group = object(data[kind]);
                      final items = objects(
                        data[kind] is List ? data[kind] : group['items'],
                      );
                      rows.addAll(items.map((e) => {...e, '_kind': kind}));
                      final count = intOf(group['total']);
                      if (count > total) total = count;
                    }
                    return PageResult(
                      rows,
                      page: page,
                      pageSize: 20,
                      total: total,
                    );
                  },
                  itemBuilder: (row, _) {
                    final kind = textOf(row['_kind']);
                    if (kind == 'users') return _MemberTile(Member(row));
                    if (kind == 'discussions')
                      return DiscussionCard(
                        ContentItem(row, ContentKind.discussion),
                        onTap: () => context.push('/discussion/${row['id']}'),
                      );
                    final post = kind == 'posts';
                    final route = post
                        ? '/discussion/${row['discussionId'] ?? object(row['discussion'])['id']}'
                        : '/${kind == 'projects' ? 'project' : 'extension'}/${row['id']}';
                    return SurfaceCard(
                      onTap: () => context.push(route),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                post
                                    ? Icons.chat_bubble_outline_rounded
                                    : kind == 'projects'
                                    ? Icons.widgets_outlined
                                    : Icons.extension_outlined,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                kinds[kind] ?? '',
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            textOf(
                              post
                                  ? object(row['discussion'])['title']
                                  : row['title'],
                              post ? '讨论中的回复' : '',
                            ),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            textOf(post ? row['content'] : row['summary']),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    ),
  );
}

class TagsPage extends ConsumerStatefulWidget {
  const TagsPage({super.key});
  @override
  ConsumerState<TagsPage> createState() => _TagsPageState();
}

class _TagsPageState extends ConsumerState<TagsPage> {
  int revision = 0;
  @override
  Widget build(BuildContext context) => FeaturePage(
    title: '话题',
    child: AsyncPanel<dynamic>(
      cacheKey: revision,
      load: () async {
        final api = ref.read(apiProvider);
        final tags = objects(await api.get('/tags'));
        dynamic followed = [];
        if (ref.read(appProvider).signedIn)
          followed = await api.get('/follow-tags');
        return {'tags': tags, 'followed': followed};
      },
      builder: (data) {
        final rows = objects(data['tags']);
        final following =
            objects(
                  data['followed'] is List
                      ? data['followed']
                      : object(data['followed'])['items'],
                )
                .map(
                  (e) =>
                      textOf(e['tagId'] ?? object(e['tag'])['id'] ?? e['id']),
                )
                .toSet();
        return ListView.separated(
          padding: const EdgeInsets.all(20),
          itemCount: rows.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final tag = rows[index];
            final id = textOf(tag['id']);
            return SurfaceCard(
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.tertiaryContainer,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(Icons.tag_rounded),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          textOf(tag['name']),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        if (textOf(tag['description']).isNotEmpty)
                          Text(
                            textOf(tag['description']),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                      ],
                    ),
                  ),
                  FilledButton.tonal(
                    onPressed: () async {
                      if (!await requireSignIn(context, ref) ||
                          !context.mounted)
                        return;
                      await perform(
                        context,
                        () => ref.read(apiProvider).post('/follow-tags', {
                          'tagId': id,
                        }),
                      );
                      if (mounted) setState(() => revision++);
                    },
                    child: Text(following.contains(id) ? '已关注' : '关注'),
                  ),
                ],
              ),
            );
          },
        );
      },
    ),
  );
}

class NotificationsPage extends ConsumerStatefulWidget {
  const NotificationsPage({super.key});
  @override
  ConsumerState<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends ConsumerState<NotificationsPage> {
  int revision = 0;
  @override
  Widget build(BuildContext context) => FeaturePage(
    title: '通知',
    actions: [
      TextButton(
        onPressed: () async {
          await perform(
            context,
            () => ref.read(apiProvider).post('/notifications/read-all'),
          );
          if (mounted) setState(() => revision++);
        },
        child: const Text('全部已读'),
      ),
    ],
    child: AuthGate(
      child: PagedList(
        cacheKey: revision,
        load: (page) async => PageResult.fromJson(
          await ref.read(apiProvider).get('/notifications', {
            'page': page,
            'pageSize': 24,
          }),
          (e) => e,
        ),
        itemBuilder: (n, i) => SurfaceCard(
          color: n['isRead'] == true
              ? null
              : Theme.of(
                  context,
                ).colorScheme.secondaryContainer.withValues(alpha: .5),
          onTap: () async {
            await perform(
              context,
              () =>
                  ref.read(apiProvider).post('/notifications/${n['id']}/read'),
            );
            if (!context.mounted) return;
            if (n['discussionId'] != null)
              context.push('/discussion/${n['discussionId']}');
            else if (n['projectId'] != null)
              context.push('/project/${n['projectId']}');
            else if (n['extensionId'] != null)
              context.push('/extension/${n['extensionId']}');
            if (mounted) setState(() => revision++);
          },
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MemberAvatar(Member(object(n['fromUser'] ?? n['actor']))),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      textOf(
                        n['title'] ?? n['content'] ?? n['message'],
                        notificationTitle(textOf(n['type'])),
                      ),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    if (n['discussion'] != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(textOf(object(n['discussion'])['title'])),
                      ),
                    const SizedBox(height: 8),
                    Text(
                      relativeTime(n['createdAt']),
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

String notificationTitle(String type) =>
    const {
      'reply': '有了新回复',
      'like': '收到了赞',
      'follow': '有了新关注',
      'mention': '有人提到了你',
      'comment': '有了新评论',
      'system': '系统通知',
    }[type] ??
    '社区有了新动态';

class MePage extends ConsumerWidget {
  const MePage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appProvider);
    final user = app.user;
    final c = Theme.of(context).colorScheme;
    return FeaturePage(
      title: '我的',
      actions: [
        IconButton(
          tooltip: '设置',
          onPressed: () => context.push('/settings'),
          icon: const Icon(Icons.settings_outlined),
        ),
      ],
      child: SingleChildScrollView(
        child: ReadingWidth(
          width: 920,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SurfaceCard(
                color: c.primaryContainer,
                onTap: () =>
                    context.push(user == null ? '/login' : '/user/${user.id}'),
                child: Row(
                  children: [
                    MemberAvatar(
                      user ?? Member({'nickname': '创'}),
                      radius: 32,
                      onTap: () => context.push(
                        user == null ? '/login' : '/user/${user.id}',
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user?.name ?? '登录创客次元',
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(color: c.onPrimaryContainer),
                          ),
                          if (user != null) ...[
                            const SizedBox(height: 6),
                            Text(
                              '@${user.username}',
                              style: TextStyle(color: c.onPrimaryContainer),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: c.onPrimaryContainer,
                    ),
                  ],
                ),
              ),
              if (user != null) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _Metric(
                        '积分',
                        '${user.points}',
                        Icons.toll_rounded,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _Metric(
                        '等级',
                        'Lv.${user.level}',
                        Icons.auto_awesome_rounded,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SurfaceCard(
                        onTap: () async {
                          await perform(
                            context,
                            () => app.api.post('/checkin'),
                            success: '签到成功',
                          );
                          await app.refreshUser();
                        },
                        child: const Column(
                          children: [
                            Icon(Icons.event_available_rounded),
                            SizedBox(height: 8),
                            Text('签到'),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                AsyncPanel<dynamic>(
                  load: () => app.api.get('/checkin/status'),
                  builder: (data) {
                    final d = object(data);
                    return Text(
                      d['checkedIn'] == true || d['checkedToday'] == true
                          ? '今日已签到'
                          : '',
                      style: Theme.of(context).textTheme.labelMedium,
                    );
                  },
                ),
              ],
              const SectionTitle('创作与收藏'),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _QuickLink(
                    '我的创作',
                    Icons.widgets_outlined,
                    '/my-creations',
                    c.secondaryContainer,
                  ),
                  _QuickLink(
                    '我的收藏',
                    Icons.bookmark_border_rounded,
                    '/bookmarks',
                    c.tertiaryContainer,
                  ),
                  _QuickLink(
                    '云盘',
                    Icons.cloud_outlined,
                    '/drive',
                    c.primaryContainer,
                  ),
                  _QuickLink(
                    '开发者工具',
                    Icons.terminal_rounded,
                    '/developer',
                    c.secondaryContainer,
                  ),
                ],
              ),
              const SizedBox(height: 24),
              for (final entry in <(String, IconData, String)>[
                ('通知', Icons.notifications_outlined, '/notifications'),
                ('我的订单', Icons.shopping_bag_outlined, '/orders'),
                ('收货地址', Icons.location_on_outlined, '/addresses'),
                ('原创存证', Icons.verified_outlined, '/origmark'),
                ('关注的话题', Icons.tag_rounded, '/tags'),
                ('排行榜', Icons.leaderboard_outlined, '/leaderboard'),
                ('装扮主页', Icons.palette_outlined, '/decoration'),
                ('客服', Icons.support_agent_rounded, '/support'),
                ('账号与安全', Icons.shield_outlined, '/security'),
                ('设置', Icons.tune_rounded, '/settings'),
              ])
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  leading: Icon(entry.$2),
                  title: Text(entry.$1),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push(entry.$3),
                ),
              if (user != null)
                Padding(
                  padding: const EdgeInsets.only(top: 24),
                  child: TextButton(
                    onPressed: () async {
                      if (await confirm(context, '退出当前账号？'))
                        await app.signOut();
                    },
                    child: const Text('退出登录'),
                  ),
                ),
              const SizedBox(height: 64),
            ],
          ),
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.value, this.icon);
  final String label, value;
  final IconData icon;
  @override
  Widget build(BuildContext context) => SurfaceCard(
    child: Column(
      children: [
        Icon(icon, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 8),
        Text(value, style: Theme.of(context).textTheme.titleLarge),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ],
    ),
  );
}

class _QuickLink extends StatelessWidget {
  const _QuickLink(this.label, this.icon, this.path, this.color);
  final String label, path;
  final IconData icon;
  final Color color;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: MediaQuery.sizeOf(context).width < 600
        ? (MediaQuery.sizeOf(context).width - 60) / 2
        : 180,
    child: SurfaceCard(
      color: color,
      onTap: () => context.push(path),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 28),
          const SizedBox(height: 24),
          Text(label, style: Theme.of(context).textTheme.titleSmall),
        ],
      ),
    ),
  );
}

class UserPage extends ConsumerStatefulWidget {
  const UserPage({super.key, required this.id});
  final String id;
  @override
  ConsumerState<UserPage> createState() => _UserPageState();
}

class _UserPageState extends ConsumerState<UserPage> {
  int revision = 0;
  @override
  Widget build(BuildContext context) => FeaturePage(
    title: '个人主页',
    child: AsyncPanel<dynamic>(
      cacheKey: revision,
      load: () => ref.read(apiProvider).get('/users/${widget.id}'),
      builder: (data) {
        final raw = object(data);
        final user = Member(raw['user'] is Map ? object(raw['user']) : raw);
        final app = ref.watch(appProvider);
        final own = app.user?.id == user.id;
        return SingleChildScrollView(
          child: ReadingWidth(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SurfaceCard(
                  child: Column(
                    children: [
                      ProfileBanner(user: user),
                      const SizedBox(height: 20),
                      MemberAvatar(user, radius: 42),
                      const SizedBox(height: 20),
                      Text(
                        user.name,
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 6),
                      Text('@${user.username}'),
                      if (user.signature.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Text(user.signature, textAlign: TextAlign.center),
                      ],
                      const SizedBox(height: 20),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        alignment: WrapAlignment.center,
                        children: [
                          Chip(label: Text('Lv.${user.level}')),
                          Chip(label: Text('${user.points} 积分')),
                          TextButton(
                            onPressed: () =>
                                context.push('/user/${user.id}/followers'),
                            child: const Text('粉丝'),
                          ),
                          TextButton(
                            onPressed: () =>
                                context.push('/user/${user.id}/following'),
                            child: const Text('关注'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (own)
                        FilledButton.tonal(
                          onPressed: () => editProfile(user),
                          child: const Text('编辑资料'),
                        )
                      else
                        Wrap(
                          spacing: 12,
                          runSpacing: 8,
                          children: [
                            _FollowButton(user.id),
                            OutlinedButton(
                              onPressed: () async {
                                if (!await requireSignIn(context, ref) ||
                                    !context.mounted)
                                  return;
                                context.push('/messages?user=${user.id}');
                              },
                              child: const Text('私信'),
                            ),
                            TextButton(
                              onPressed: () async {
                                if (!await requireSignIn(context, ref) ||
                                    !context.mounted)
                                  return;
                                await showFields(
                                  context,
                                  '转账给 ${user.name}',
                                  const [
                                    FieldSpec('amount', '积分数量', number: true),
                                    FieldSpec('note', '备注', required: false),
                                  ],
                                  submitLabel: '确认转账',
                                  onSubmit: (d) async {
                                    if ((d['amount'] as num) <= 0)
                                      throw const ApiFailure('积分必须大于零');
                                    await app.api.post('/transfer', {
                                      'toUserId': user.id,
                                      ...d,
                                    });
                                    await app.refreshUser();
                                  },
                                );
                              },
                              child: const Text('转积分'),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
                const SectionTitle('最近讨论'),
                AsyncPanel<dynamic>(
                  load: () => app.api.get('/discussions', {
                    'authorId': user.id,
                    'page': 1,
                    'pageSize': 24,
                    'sort': 'new',
                  }),
                  builder: (d) {
                    final rows = objects(object(d)['items']);
                    return Column(
                      children: rows
                          .map(
                            (r) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: DiscussionCard(
                                ContentItem(r, ContentKind.discussion),
                                onTap: () =>
                                    context.push('/discussion/${r['id']}'),
                              ),
                            ),
                          )
                          .toList(),
                    );
                  },
                ),
                const SectionTitle('作品集'),
                AsyncPanel<dynamic>(
                  load: () =>
                      app.api.get('/resources/works', {'userId': user.id}),
                  builder: (d) {
                    final rows = objects(d is List ? d : object(d)['items']);
                    return Column(
                      children: rows
                          .map(
                            (r) => ListTile(
                              leading: const Icon(Icons.widgets_outlined),
                              title: Text(textOf(r['title'] ?? r['filename'])),
                              onTap: () => openLink(context, textOf(r['url'])),
                            ),
                          )
                          .toList(),
                    );
                  },
                ),
                const SizedBox(height: 64),
              ],
            ),
          ),
        );
      },
    ),
  );
  Future<void> editProfile(Member user) async {
    final d = await showFields(
      context,
      '编辑资料',
      [
        FieldSpec('nickname', '昵称', initial: user.name),
        FieldSpec(
          'bio',
          '签名',
          required: false,
          lines: 3,
          initial: user.signature,
        ),
      ],
      header: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: OutlinedButton.icon(
          onPressed: () async {
            final file = await pickFile(
              extensions: ['png', 'jpg', 'jpeg', 'webp'],
            );
            if (file == null || !mounted) return;
            await perform(context, () async {
              final resource = await ref.read(apiProvider).upload(file);
              await ref.read(apiProvider).patch('/auth/me', {
                'avatar': resource.url,
              });
              await ref.read(appProvider).refreshUser();
            }, success: '头像已更新');
          },
          icon: const Icon(Icons.photo_camera_outlined),
          label: const Text('更换头像'),
        ),
      ),
      onSubmit: (d) async {
        await ref.read(apiProvider).patch('/auth/me', d);
        await ref.read(appProvider).refreshUser();
      },
    );
    if (d != null && mounted) setState(() => revision++);
  }
}

class _FollowButton extends ConsumerStatefulWidget {
  const _FollowButton(this.id);
  final String id;
  @override
  ConsumerState<_FollowButton> createState() => _FollowButtonState();
}

class _FollowButtonState extends ConsumerState<_FollowButton> {
  bool followed = false, busy = false;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    if (!ref.read(appProvider).signedIn) return;
    try {
      final d = await ref
          .read(apiProvider)
          .get('/users/${widget.id}/is-following');
      if (mounted)
        setState(
          () => followed =
              d == true ||
              boolOf(object(d)['following'] ?? object(d)['isFollowing']),
        );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) => FilledButton(
    onPressed: busy
        ? null
        : () async {
            if (!await requireSignIn(context, ref) || !context.mounted) return;
            setState(() => busy = true);
            await perform(
              context,
              () => ref.read(apiProvider).post('/users/${widget.id}/follow'),
            );
            await load();
            if (mounted) setState(() => busy = false);
          },
    child: Text(followed ? '已关注' : '关注'),
  );
}

class MembersPage extends ConsumerWidget {
  const MembersPage({
    super.key,
    this.id,
    this.following = false,
    this.leaderboard = false,
  });
  final String? id;
  final bool following, leaderboard;
  @override
  Widget build(BuildContext context, WidgetRef ref) => FeaturePage(
    title: leaderboard
        ? '排行榜'
        : following
        ? '关注'
        : '粉丝',
    child: AsyncPanel<dynamic>(
      load: () => ref
          .read(apiProvider)
          .get(
            leaderboard
                ? '/users/leaderboard'
                : '/users/$id/${following ? 'following' : 'followers'}',
            leaderboard ? {'limit': 100} : null,
          ),
      builder: (d) {
        final rows = objects(
          d is List ? d : object(d)['items'] ?? object(d)['users'],
        );
        return rows.isEmpty
            ? const EmptyState()
            : ListView.builder(
                padding: const EdgeInsets.all(20),
                itemCount: rows.length,
                itemBuilder: (context, i) => _MemberTile(
                  Member(
                    object(
                          rows[i]['user'] ??
                              rows[i]['follower'] ??
                              rows[i]['following'],
                        ).isEmpty
                        ? rows[i]
                        : object(
                            rows[i]['user'] ??
                                rows[i]['follower'] ??
                                rows[i]['following'],
                          ),
                  ),
                  rank: leaderboard ? i + 1 : null,
                ),
              );
      },
    ),
  );
}

class _MemberTile extends StatelessWidget {
  const _MemberTile(this.member, {this.rank});
  final Member member;
  final int? rank;
  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    leading: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (rank != null) ...[
          SizedBox(
            width: 26,
            child: Text(
              '$rank',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          const SizedBox(width: 8),
        ],
        MemberAvatar(member),
      ],
    ),
    title: Text(member.name),
    subtitle: Text('@${member.username}'),
    trailing: Text('Lv.${member.level}'),
    onTap: () => context.push('/user/${member.id}'),
  );
}

class BookmarksPage extends ConsumerWidget {
  const BookmarksPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => FeaturePage(
    title: '我的收藏',
    child: AuthGate(
      child: PagedList(
        cacheKey: ref.watch(appProvider).revision,
        load: (page) async => PageResult.fromJson(
          await ref.read(apiProvider).get('/bookmarks', {
            'page': page,
            'pageSize': 24,
          }),
          (e) => e,
        ),
        itemBuilder: (r, i) {
          final d = object(r['discussion']).isEmpty
              ? r
              : object(r['discussion']);
          return DiscussionCard(
            ContentItem(d, ContentKind.discussion),
            onTap: () => context.push('/discussion/${d['id']}'),
          );
        },
      ),
    ),
  );
}
