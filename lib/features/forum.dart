import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/api.dart';
import '../core/app_state.dart';
import '../core/models.dart';
import '../ui/forms.dart';
import '../ui/platform.dart';
import '../ui/widgets.dart';
import 'composer.dart';
import 'interactions.dart';

class CommunityPage extends ConsumerStatefulWidget {
  const CommunityPage({super.key});
  @override
  ConsumerState<CommunityPage> createState() => _CommunityPageState();
}

class _CommunityPageState extends ConsumerState<CommunityPage> {
  String sort = 'new';
  String? tagId, selected;
  List<Json> tags = [];
  @override
  void initState() {
    super.initState();
    _tags();
  }

  Future<void> _tags() async {
    try {
      final data = objects(await ref.read(apiProvider).get('/tags'));
      if (mounted) setState(() => tags = data);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appProvider);
    return LayoutBuilder(
      builder: (context, box) {
        final split =
            MediaQuery.sizeOf(context).width >= 1000 && selected != null;
        return Row(
          children: [
            SizedBox(
              width: split ? 340 : box.maxWidth,
              child: FeaturePage(
                title: '社区',
                actions: [
                  IconButton(
                    tooltip: '搜索',
                    onPressed: () => context.push('/search'),
                    icon: const Icon(Icons.search_rounded),
                  ),
                  IconButton(
                    tooltip: '按帖号打开',
                    onPressed: () async {
                      final value = await showFields(context, '跳转帖子', const [
                        FieldSpec('seq', '帖号', number: true),
                      ], submitLabel: '打开');
                      if (value != null && context.mounted)
                        context.push('/seq/${value['seq']}');
                    },
                    icon: const Icon(Icons.tag_rounded),
                  ),
                ],
                fab: FloatingActionButton.extended(
                  onPressed: () async {
                    if (!await requireSignIn(context, ref) || !context.mounted)
                      return;
                    await context.push(
                      '/compose',
                      extra: const ComposeRequest('discussion'),
                    );
                  },
                  icon: const Icon(Icons.edit_rounded),
                  label: const Text('发帖'),
                ),
                child: PagedList(
                  cacheKey: '$sort-$tagId-${app.revision}',
                  load: (page) async => PageResult.fromJson(
                    await app.api.get('/discussions', {
                      'sort': sort,
                      'page': page,
                      'pageSize': 24,
                      if (tagId != null) 'tagId': tagId,
                    }),
                    (e) => e,
                  ),
                  header: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (!split)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                          child: _CommunityHero(),
                        ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              ChoiceChip(
                                label: const Text('最新'),
                                selected: sort == 'new',
                                onSelected: (_) => setState(() => sort = 'new'),
                              ),
                              const SizedBox(width: 8),
                              ChoiceChip(
                                label: const Text('热门'),
                                selected: sort == 'hot',
                                onSelected: (_) => setState(() => sort = 'hot'),
                              ),
                              const SizedBox(width: 16),
                              FilterChip(
                                label: const Text('全部'),
                                selected: tagId == null,
                                onSelected: (_) => setState(() => tagId = null),
                              ),
                              for (final tag in tags) ...[
                                const SizedBox(width: 8),
                                FilterChip(
                                  label: Text(textOf(tag['name'])),
                                  selected: tagId == tag['id'],
                                  onSelected: (_) =>
                                      setState(() => tagId = textOf(tag['id'])),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  itemBuilder: (row, index) => DiscussionCard(
                    ContentItem(row, ContentKind.discussion),
                    selected: selected == row['id'],
                    onTap: () {
                      if (MediaQuery.sizeOf(context).width >= 1000) {
                        setState(() => selected = textOf(row['id']));
                      } else {
                        context.push('/discussion/${row['id']}');
                      }
                    },
                  ),
                ),
              ),
            ),
            if (split) ...[
              const VerticalDivider(width: 1),
              Expanded(
                child: DiscussionPage(
                  key: ValueKey(selected),
                  id: selected!,
                  embedded: true,
                  onClose: () => setState(() => selected = null),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _CommunityHero extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Theme.of(context).colorScheme;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: c.primaryContainer,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -28,
            top: -38,
            child: Transform.rotate(
              angle: .3,
              child: Container(
                width: 170,
                height: 170,
                decoration: BoxDecoration(
                  color: c.tertiaryContainer.withValues(alpha: .8),
                  borderRadius: BorderRadius.circular(52),
                ),
              ),
            ),
          ),
          Positioned(
            right: 36,
            bottom: -34,
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: c.primary.withValues(alpha: .13),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(26),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '创作，在这里发生。',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: c.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Icon(
                      Icons.bubble_chart_rounded,
                      size: 20,
                      color: c.onPrimaryContainer,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '创客次元',
                      style: TextStyle(
                        color: c.onPrimaryContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    FilledButton.tonal(
                      onPressed: () => context.push('/tags'),
                      child: const Text('探索话题'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class DiscussionCard extends StatelessWidget {
  const DiscussionCard(
    this.item, {
    super.key,
    required this.onTap,
    this.selected = false,
  });
  final ContentItem item;
  final VoidCallback onTap;
  final bool selected;
  @override
  Widget build(BuildContext context) => SurfaceCard(
    onTap: onTap,
    color: selected ? Theme.of(context).colorScheme.secondaryContainer : null,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            MemberAvatar(item.author, radius: 15),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                item.author.name,
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
            Text(
              relativeTime(item.createdAt),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (item.pinned)
              const Padding(
                padding: EdgeInsets.only(right: 6, top: 2),
                child: Icon(Icons.push_pin_rounded, size: 18),
              ),
            Expanded(
              child: Text(
                item.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(height: 1.5),
              ),
            ),
            if (item.locked) const Icon(Icons.lock_outline_rounded, size: 16),
          ],
        ),
        if (item.summary.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            item.summary
                .replaceAll(RegExp(r'[#*>`\[\]]'), '')
                .replaceAll('\n', ' '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 16),
        Wrap(
          spacing: 16,
          runSpacing: 8,
          children: [
            for (final tag in item.tags)
              Text(
                '# ${textOf(tag['name'])}',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            StatPill(
              Icons.chat_bubble_outline_rounded,
              compactNumber(item.replies),
            ),
            StatPill(Icons.favorite_border_rounded, compactNumber(item.likes)),
            StatPill(Icons.visibility_outlined, compactNumber(item.views)),
          ],
        ),
      ],
    ),
  );
}

class DiscussionPage extends ConsumerStatefulWidget {
  const DiscussionPage({
    super.key,
    required this.id,
    this.bySeq = false,
    this.embedded = false,
    this.onClose,
  });
  final String id;
  final bool bySeq, embedded;
  final VoidCallback? onClose;
  @override
  ConsumerState<DiscussionPage> createState() => _DiscussionPageState();
}

class _DiscussionPageState extends ConsumerState<DiscussionPage> {
  final panel = GlobalKey<AsyncPanelState<Json>>();
  void reload() => panel.currentState?.reload();
  @override
  Widget build(BuildContext context) => FeaturePage(
    title: widget.embedded ? '讨论' : '帖子',
    actions: [
      IconButton(
        tooltip: '刷新',
        onPressed: reload,
        icon: const Icon(Icons.refresh_rounded),
      ),
      if (widget.onClose != null)
        IconButton(
          tooltip: '关闭详情',
          onPressed: widget.onClose,
          icon: const Icon(Icons.close_rounded),
        ),
    ],
    child: AsyncPanel<Json>(
      key: panel,
      load: () async => object(
        await ref
            .read(apiProvider)
            .get(
              widget.bySeq
                  ? '/discussions/seq/${widget.id}'
                  : '/discussions/${widget.id}',
            ),
      ),
      builder: (data) {
        final item = ContentItem(data, ContentKind.discussion);
        final app = ref.watch(appProvider);
        final own = app.user?.id == data['authorId'];
        final posts = objects(data['posts']);
        return RefreshIndicator(
          onRefresh: () async => reload(),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: ReadingWidth(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: 8,
                    children: [
                      if (data['seq'] != null)
                        Chip(label: Text('#${data['seq']}')),
                      if (item.pinned) const Chip(label: Text('置顶')),
                      if (item.locked) const Chip(label: Text('已锁定')),
                      for (final tag in item.tags)
                        ActionChip(
                          label: Text(textOf(tag['name'])),
                          onPressed: () => context.push('/tags'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    item.title,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      MemberAvatar(item.author),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.author.name,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            Text(
                              '${relativeTime(item.createdAt)} · ${item.views} 次浏览',
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ],
                        ),
                      ),
                      PopupMenuButton<String>(
                        onSelected: (action) async {
                          if (action == 'share') {
                            await copyText(
                              context,
                              absoluteUrl('/ts/${data['seq'] ?? item.id}'),
                            );
                          }
                          if (action == 'edit') {
                            if (!context.mounted) return;
                            final ok = await context.push<bool>(
                              '/compose',
                              extra: ComposeRequest(
                                'discussion',
                                id: item.id,
                                initial: data,
                              ),
                            );
                            if (ok == true) reload();
                          }
                          if (action == 'delete' &&
                              context.mounted &&
                              await confirm(context, '删除这个帖子？') &&
                              context.mounted) {
                            final result = await perform(context, () async {
                              await app.api.delete('/discussions/${item.id}');
                              return true;
                            });
                            if (result == true && context.mounted) {
                              app.changed();
                              if (widget.onClose != null)
                                widget.onClose!();
                              else
                                context.pop();
                            }
                          }
                          if (action == 'report' && context.mounted)
                            await reportContent(
                              context,
                              ref,
                              'discussion',
                              item.id,
                            );
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                            value: 'share',
                            child: Text('复制链接'),
                          ),
                          if (own) ...[
                            const PopupMenuItem(
                              value: 'edit',
                              child: Text('编辑'),
                            ),
                            const PopupMenuItem(
                              value: 'delete',
                              child: Text('删除'),
                            ),
                          ],
                          const PopupMenuItem(
                            value: 'report',
                            child: Text('举报'),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),
                  MarkdownContent(textOf(data['content'])),
                  const SizedBox(height: 24),
                  ResourceAttachments(discussionId: item.id),
                  Row(
                    children: [
                      LikeButton(
                        type: 'discussion',
                        id: item.id,
                        count: item.likes,
                        liked: boolOf(data['likedByMe']),
                      ),
                      BookmarkButton(item.id),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: item.locked ? null : () => reply(item.id),
                        icon: const Icon(Icons.reply_rounded),
                        label: const Text('回复'),
                      ),
                    ],
                  ),
                  ReactionBar(type: 'discussion', id: item.id),
                  PollSection(item.id, canManage: own),
                  const SizedBox(height: 20),
                  SectionTitle('回复 · ${posts.length}'),
                  if (posts.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 28),
                      child: Text('还没有回复'),
                    ),
                  for (final post in posts) _post(post, item),
                  if (!item.locked)
                    FilledButton.tonalIcon(
                      onPressed: () => reply(item.id),
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('写回复'),
                    ),
                  const SizedBox(height: 40),
                  CommentsSection(type: 'discussion', id: item.id),
                  const SizedBox(height: 80),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
  Future<void> reply(String discussionId, {String? replyTo}) async {
    if (!await requireSignIn(context, ref) || !mounted) return;
    final ok = await context.push<bool>(
      '/compose',
      extra: ComposeRequest(
        'reply',
        discussionId: discussionId,
        replyToId: replyTo,
      ),
    );
    if (ok == true) reload();
  }

  Widget _post(Json post, ContentItem discussion) {
    final author = Member(object(post['author']));
    final own =
        ref.watch(appProvider).user?.id == (post['authorId'] ?? author.id);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                MemberAvatar(author, radius: 16),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    author.name,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                Text(
                  relativeTime(post['createdAt']),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                PopupMenuButton<String>(
                  onSelected: (action) async {
                    if (action == 'edit') {
                      final ok = await context.push<bool>(
                        '/compose',
                        extra: ComposeRequest(
                          'reply',
                          id: textOf(post['id']),
                          initial: post,
                          discussionId: discussion.id,
                        ),
                      );
                      if (ok == true) reload();
                    }
                    if (action == 'delete' &&
                        mounted &&
                        await confirm(context, '删除回复？') &&
                        mounted) {
                      await perform(
                        context,
                        () => ref
                            .read(apiProvider)
                            .delete('/posts/${post['id']}'),
                      );
                      reload();
                    }
                    if (action == 'report' && mounted)
                      await reportContent(
                        context,
                        ref,
                        'post',
                        textOf(post['id']),
                      );
                  },
                  itemBuilder: (_) => [
                    if (own) ...[
                      const PopupMenuItem(value: 'edit', child: Text('编辑')),
                      const PopupMenuItem(value: 'delete', child: Text('删除')),
                    ],
                    const PopupMenuItem(value: 'report', child: Text('举报')),
                  ],
                ),
              ],
            ),
            if (post['replyTo'] != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  '引用：${textOf(object(post['replyTo'])['content'])}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            const SizedBox(height: 16),
            MarkdownContent(textOf(post['content'])),
            const SizedBox(height: 12),
            ResourceAttachments(postId: textOf(post['id'])),
            Wrap(
              spacing: 8,
              children: [
                LikeButton(
                  type: 'post',
                  id: textOf(post['id']),
                  count: intOf(post['likeCount']),
                  liked: boolOf(post['likedByMe']),
                ),
                TextButton.icon(
                  onPressed: discussion.locked
                      ? null
                      : () => reply(discussion.id, replyTo: textOf(post['id'])),
                  icon: const Icon(Icons.reply_rounded, size: 18),
                  label: const Text('引用'),
                ),
              ],
            ),
            ReactionBar(type: 'post', id: textOf(post['id'])),
          ],
        ),
      ),
    );
  }
}

class ResourceAttachments extends ConsumerWidget {
  const ResourceAttachments({super.key, this.discussionId, this.postId});
  final String? discussionId, postId;
  @override
  Widget build(BuildContext context, WidgetRef ref) => AsyncPanel<dynamic>(
    load: () => ref.read(apiProvider).get('/resources', {
      if (discussionId != null) 'discussionId': discussionId,
      if (postId != null) 'postId': postId,
    }),
    builder: (data) {
      final rows = objects(data is List ? data : object(data)['items']);
      return Column(
        children: rows
            .map(
              (r) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  tileColor: Theme.of(context).colorScheme.surfaceContainerLow,
                  leading: const Icon(Icons.attach_file_rounded),
                  title: Text(textOf(r['name'] ?? r['filename'], '附件')),
                  subtitle: Text(fileSize(r['size'])),
                  trailing: const Icon(Icons.download_outlined),
                  onTap: () {
                    final url = textOf(r['url'] ?? r['link']);
                    if (url.isEmpty) return;
                    if (r['fileType'] == 'netdisk' || r['provider'] != null)
                      openLink(context, url, external: true);
                    else
                      saveRemote(
                        context,
                        ref.read(apiProvider),
                        url,
                        textOf(r['filename'], '附件'),
                      );
                  },
                ),
              ),
            )
            .toList(),
      );
    },
  );
}
