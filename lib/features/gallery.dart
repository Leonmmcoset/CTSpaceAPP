import 'dart:convert';
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

class GalleryPage extends ConsumerStatefulWidget {
  const GalleryPage({
    super.key,
    this.mine = false,
    this.initialKind = ContentKind.project,
  });
  final bool mine;
  final ContentKind initialKind;
  @override
  ConsumerState<GalleryPage> createState() => _GalleryPageState();
}

class _GalleryPageState extends ConsumerState<GalleryPage> {
  late ContentKind kind = widget.initialKind;
  String sort = 'score';
  String? category;
  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appProvider);
    final categories = kind == ContentKind.project
        ? projectCategories
        : extensionCategories;
    final child = FeaturePage(
      title: widget.mine ? '我的创作' : '广场',
      actions: [
        IconButton(
          tooltip: '搜索',
          onPressed: () => context.push('/search'),
          icon: const Icon(Icons.search_rounded),
        ),
      ],
      fab: FloatingActionButton.extended(
        onPressed: () async {
          if (!await requireSignIn(context, ref) || !context.mounted) return;
          await context.push('/compose', extra: ComposeRequest(kind.name));
        },
        icon: const Icon(Icons.add_rounded),
        label: Text(kind == ContentKind.project ? '发布作品' : '发布扩展'),
      ),
      child: PagedList(
        grid: true,
        cacheKey: '${kind.name}-$sort-$category-${app.revision}',
        load: (page) async => PageResult.fromJson(
          await app.api.get('/${kind.name}s${widget.mine ? '/my' : ''}', {
            'page': page,
            'pageSize': 24,
            'sort': sort,
            if (category != null) 'category': category,
          }),
          (e) => e,
        ),
        header: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<ContentKind>(
                segments: const [
                  ButtonSegment(
                    value: ContentKind.project,
                    icon: Icon(Icons.widgets_outlined),
                    label: Text('作品'),
                  ),
                  ButtonSegment(
                    value: ContentKind.extension,
                    icon: Icon(Icons.extension_outlined),
                    label: Text('扩展'),
                  ),
                ],
                selected: {kind},
                onSelectionChanged: (value) => setState(() {
                  kind = value.first;
                  category = null;
                }),
              ),
              const SizedBox(height: 16),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    ChoiceChip(
                      label: const Text('推荐'),
                      selected: sort == 'score',
                      onSelected: (_) => setState(() => sort = 'score'),
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text('最新'),
                      selected: sort == 'new',
                      onSelected: (_) => setState(() => sort = 'new'),
                    ),
                    const SizedBox(width: 16),
                    FilterChip(
                      label: const Text('全部'),
                      selected: category == null,
                      onSelected: (_) => setState(() => category = null),
                    ),
                    for (final e in categories.entries) ...[
                      const SizedBox(width: 8),
                      FilterChip(
                        label: Text(e.value),
                        selected: category == e.key,
                        onSelected: (_) => setState(() => category = e.key),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        itemBuilder: (row, index) => GalleryCard(ContentItem(row, kind)),
      ),
    );
    return widget.mine ? AuthGate(child: child) : child;
  }
}

class GalleryCard extends StatelessWidget {
  const GalleryCard(this.item, {super.key});
  final ContentItem item;
  @override
  Widget build(BuildContext context) => SurfaceCard(
    padding: EdgeInsets.zero,
    onTap: () => context.push('/${item.kind.name}/${item.id}'),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Hero(
            tag: 'cover-${item.kind.name}-${item.id}',
            child: ContentCover(item),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(
                item.summary,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  MemberAvatar(item.author, radius: 12),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      item.author.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ),
                  StatPill(
                    Icons.favorite_border_rounded,
                    compactNumber(item.likes),
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

class GalleryDetailPage extends ConsumerStatefulWidget {
  const GalleryDetailPage({super.key, required this.id, required this.kind});
  final String id;
  final ContentKind kind;
  @override
  ConsumerState<GalleryDetailPage> createState() => _GalleryDetailPageState();
}

class _GalleryDetailPageState extends ConsumerState<GalleryDetailPage> {
  final panel = GlobalKey<AsyncPanelState<Json>>();
  @override
  Widget build(BuildContext context) => FeaturePage(
    title: widget.kind == ContentKind.project ? '作品' : '扩展',
    actions: [
      IconButton(
        tooltip: '刷新',
        onPressed: () => panel.currentState?.reload(),
        icon: const Icon(Icons.refresh_rounded),
      ),
    ],
    child: AsyncPanel<Json>(
      key: panel,
      load: () async => object(
        await ref.read(apiProvider).get('/${widget.kind.name}s/${widget.id}'),
      ),
      builder: (data) {
        final item = ContentItem(data, widget.kind);
        final app = ref.watch(appProvider);
        final own = app.user?.id == data['authorId'];
        final project = widget.kind == ContentKind.project;
        return SingleChildScrollView(
          child: ReadingWidth(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Hero(
                  tag: 'cover-${item.kind.name}-${item.id}',
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: SizedBox(height: 240, child: ContentCover(item)),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        item.title,
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                    ),
                    PopupMenuButton<String>(
                      onSelected: (action) async {
                        if (action == 'edit') {
                          final result = await context.push<bool>(
                            '/compose',
                            extra: ComposeRequest(
                              widget.kind.name,
                              id: widget.id,
                              initial: data,
                            ),
                          );
                          if (result == true) panel.currentState?.reload();
                        }
                        if (action == 'delete' &&
                            context.mounted &&
                            await confirm(
                              context,
                              '删除这个${project ? '作品' : '扩展'}？',
                            ) &&
                            context.mounted) {
                          final ok = await perform(context, () async {
                            await app.api.delete(
                              '/${widget.kind.name}s/${widget.id}',
                            );
                            return true;
                          });
                          if (ok == true && context.mounted) {
                            app.changed();
                            context.pop();
                          }
                        }
                        if (action == 'report' && context.mounted)
                          await reportContent(
                            context,
                            ref,
                            widget.kind.name,
                            widget.id,
                          );
                      },
                      itemBuilder: (_) => [
                        if (own) ...[
                          const PopupMenuItem(value: 'edit', child: Text('编辑')),
                          const PopupMenuItem(
                            value: 'delete',
                            child: Text('删除'),
                          ),
                        ],
                        const PopupMenuItem(value: 'report', child: Text('举报')),
                      ],
                    ),
                  ],
                ),
                if (item.summary.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    item.summary,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ],
                const SizedBox(height: 20),
                Row(
                  children: [
                    MemberAvatar(item.author),
                    const SizedBox(width: 12),
                    Expanded(child: Text(item.author.name)),
                    StatPill(Icons.visibility_outlined, '${item.views}'),
                  ],
                ),
                const SizedBox(height: 24),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    if (project)
                      FilledButton.icon(
                        onPressed: () => runProject(data),
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: const Text('运行作品'),
                      ),
                    if (project &&
                        data['allowDownload'] == true &&
                        textOf(data['sb3Url']).isNotEmpty)
                      OutlinedButton.icon(
                        onPressed: () => saveRemote(
                          context,
                          app.api,
                          textOf(data['sb3Url']),
                          textOf(data['sb3Filename'], '作品.sb3'),
                        ),
                        icon: const Icon(Icons.download_rounded),
                        label: const Text('下载源文件'),
                      ),
                    if (!project)
                      FilledButton.tonalIcon(
                        onPressed: () => saveRemote(
                          context,
                          app.api,
                          '/api/extensions/${widget.id}/raw',
                          textOf(data['fileName'], '${item.title}.js'),
                        ),
                        icon: const Icon(Icons.download_rounded),
                        label: const Text('下载源码'),
                      ),
                    OutlinedButton.icon(
                      onPressed: () => copyText(
                        context,
                        project && textOf(data['shortLinkSlug']).isNotEmpty
                            ? absoluteUrl('/g/${data['shortLinkSlug']}')
                            : absoluteUrl('/${widget.kind.name}/${widget.id}'),
                      ),
                      icon: const Icon(Icons.ios_share_rounded),
                      label: const Text('分享'),
                    ),
                    if (!project)
                      OutlinedButton.icon(
                        onPressed: () => copyText(
                          context,
                          absoluteUrl('/api/extensions/${widget.id}/raw.js'),
                        ),
                        icon: const Icon(Icons.link_rounded),
                        label: const Text('加载地址'),
                      ),
                  ],
                ),
                const SizedBox(height: 24),
                MarkdownContent(
                  textOf(data[project ? 'content' : 'description']),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    LikeButton(
                      type: widget.kind.name,
                      id: widget.id,
                      count: item.likes,
                      liked: boolOf(data['likedByMe']),
                    ),
                    if (!project && data['license'] != null)
                      Chip(label: Text(textOf(data['license']))),
                  ],
                ),
                ReactionBar(type: widget.kind.name, id: widget.id),
                if (project) ...[
                  if (own) ...[
                    const SectionTitle('作品网址'),
                    ShortLinksSection(projectId: widget.id),
                  ],
                  const SectionTitle('版本记录'),
                  for (final version in objects(data['versions']))
                    SurfaceCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  textOf(version['versionLabel']),
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                              ),
                              Text(
                                relativeTime(version['createdAt']),
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                              if (data['allowDownload'] == true)
                                IconButton(
                                  tooltip: '下载此版本',
                                  onPressed: () => saveRemote(
                                    context,
                                    app.api,
                                    textOf(
                                      object(version['sb3Resource'])['url'],
                                    ),
                                    textOf(
                                      object(
                                        version['sb3Resource'],
                                      )['filename'],
                                      '作品.sb3',
                                    ),
                                  ),
                                  icon: const Icon(Icons.download_outlined),
                                ),
                            ],
                          ),
                          if (textOf(version['changelog']).isNotEmpty)
                            Text(textOf(version['changelog'])),
                        ],
                      ),
                    ),
                  if (data['forumDiscussionId'] != null)
                    TextButton.icon(
                      onPressed: () => context.push(
                        '/discussion/${data['forumDiscussionId']}',
                      ),
                      icon: const Icon(Icons.forum_outlined),
                      label: const Text('查看关联讨论'),
                    ),
                ] else ...[
                  SectionTitle(
                    'JavaScript',
                    trailing: TextButton.icon(
                      onPressed: () => copyText(context, textOf(data['code'])),
                      icon: const Icon(Icons.copy_rounded, size: 18),
                      label: const Text('复制'),
                    ),
                  ),
                  CodeView(textOf(data['code'])),
                ],
                const SizedBox(height: 24),
                CommentsSection(type: widget.kind.name, id: widget.id),
                const SizedBox(height: 80),
              ],
            ),
          ),
        );
      },
    ),
  );
  Future<void> runProject(Json data) async {
    if (textOf(data['shortLinkSlug']).isNotEmpty) {
      await openLink(context, absoluteUrl('/g/${data['shortLinkSlug']}'));
      return;
    }
    var editors = objects(data['editors']);
    if (editors.isEmpty) {
      try {
        editors = objects(
          jsonDecode(textOf(ref.read(appProvider).settings['editors'], '[]')),
        );
      } catch (_) {}
    }
    if (editors.isEmpty) {
      toast(context, '暂无可用播放器');
      return;
    }
    final editor = editors.first;
    final template = textOf(editor['embedTemplate']).trim();
    final url = template.replaceAll(
      '{url}',
      Uri.encodeComponent(absoluteUrl(textOf(data['sb3Url']))),
    );
    await openLink(context, url);
  }
}

class CodeView extends StatelessWidget {
  const CodeView(this.code, {super.key});
  final String code;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final regex = RegExp(
      r'\b(const|let|var|function|return|if|else|class|new|true|false|null|async|await|throw|try|catch)\b|//[^\n]*',
    );
    final spans = <TextSpan>[];
    var offset = 0;
    for (final m in regex.allMatches(code)) {
      if (m.start > offset)
        spans.add(TextSpan(text: code.substring(offset, m.start)));
      spans.add(
        TextSpan(
          text: m.group(0),
          style: TextStyle(
            color: m.group(0)!.startsWith('//')
                ? scheme.outline
                : scheme.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
      offset = m.end;
    }
    spans.add(TextSpan(text: code.substring(offset)));
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      constraints: const BoxConstraints(maxHeight: 500),
      child: SingleChildScrollView(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SelectableText.rich(
            TextSpan(children: spans),
            style: TextStyle(
              fontFamily: 'monospace',
              fontFamilyFallback: const ['NotoSansSC'],
              fontSize: 13,
              height: 1.65,
              color: scheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

class ShortLinksSection extends ConsumerStatefulWidget {
  const ShortLinksSection({super.key, required this.projectId});
  final String projectId;
  @override
  ConsumerState<ShortLinksSection> createState() => _ShortLinksSectionState();
}

class _ShortLinksSectionState extends ConsumerState<ShortLinksSection> {
  int revision = 0;
  Future<void> edit({Json? link}) async {
    final data = await showFields(
      context,
      link == null ? '创建作品网址' : '修改作品网址',
      [
        FieldSpec(
          'slug',
          '短码',
          initial: link?['slug'],
          hint: '3–32 位小写字母、数字和连字符',
        ),
      ],
      onSubmit: (data) async {
        final slug = textOf(data['slug']);
        if (!RegExp(r'^[a-z0-9](?:[a-z0-9-]{1,30})[a-z0-9]$').hasMatch(slug) ||
            !RegExp('[a-z]').hasMatch(slug) ||
            slug.contains('--'))
          throw const ApiFailure('短码格式不正确');
        final api = ref.read(apiProvider);
        final check = object(await api.get('/shortlink/check', {'slug': slug}));
        if (check['available'] != true)
          throw ApiFailure(textOf(check['message'], '此短码不可用'));
        if (link == null)
          await api.post('/shortlink', {
            'projectId': widget.projectId,
            'slug': slug,
          });
        else
          await api.patch(
            '/shortlink/${Uri.encodeComponent(textOf(link['slug']))}',
            data,
          );
      },
    );
    if (data != null && mounted) setState(() => revision++);
  }

  @override
  Widget build(BuildContext context) => AsyncPanel<dynamic>(
    cacheKey: revision,
    load: () => ref.read(apiProvider).get('/shortlink/mine', {
      'projectId': widget.projectId,
    }),
    builder: (data) {
      final rows = objects(
        data is List ? data : object(data)['items'] ?? object(data)['links'],
      );
      return Column(
        children: [
          for (final link in rows)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(textOf(link['slug'])),
              subtitle: Text(link['disabled'] == true ? '已停用' : '可访问'),
              onTap: () => copyText(context, absoluteUrl('/g/${link['slug']}')),
              trailing: PopupMenuButton<String>(
                onSelected: (action) async {
                  if (action == 'edit') await edit(link: link);
                  if (action == 'toggle' && context.mounted) {
                    await perform(
                      context,
                      () => ref.read(apiProvider).post(
                        '/shortlink/${link['slug']}/disabled',
                        {'disabled': link['disabled'] != true},
                      ),
                    );
                    if (mounted) setState(() => revision++);
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'edit', child: Text('改名')),
                  if (link['isSystem'] != true)
                    PopupMenuItem(
                      value: 'toggle',
                      child: Text(link['disabled'] == true ? '恢复' : '停用'),
                    ),
                ],
              ),
            ),
          if (rows.length < 3)
            OutlinedButton.icon(
              onPressed: () => edit(),
              icon: const Icon(Icons.add_link_rounded),
              label: const Text('创建网址'),
            ),
        ],
      );
    },
  );
}
