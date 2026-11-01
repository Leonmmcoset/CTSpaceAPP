import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/api.dart';
import '../core/app_state.dart';
import '../core/models.dart';
import '../ui/forms.dart';
import '../ui/platform.dart';
import '../ui/widgets.dart';

class LibraryPage extends ConsumerStatefulWidget {
  const LibraryPage({super.key, this.games = false});
  final bool games;
  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage> {
  String query = '', sort = 'hot', kind = 'all';
  bool mine = false, uploading = false;
  double? progress;
  Timer? debounce;
  String get base => widget.games ? '/games' : '/assets';
  int revision = 0;
  @override
  void dispose() {
    debounce?.cancel();
    super.dispose();
  }

  Future<void> upload() async {
    if (!await requireSignIn(context, ref) || !mounted) return;
    final data = await showFields(context, widget.games ? '发布小游戏' : '发布素材', [
      const FieldSpec('title', '名称'),
      const FieldSpec('summary', '简介', required: false, lines: 2),
      if (!widget.games)
        const FieldSpec(
          'kind',
          '类型',
          options: {'sprite': 'Scratch 角色', 'icon': 'SVG 图标'},
        ),
      if (widget.games)
        const FieldSpec('description', '说明', required: false, lines: 3),
    ], submitLabel: '选择文件');
    if (data == null || !mounted) return;
    final file = await pickFile(
      extensions: widget.games
          ? ['html', 'htm', 'zip']
          : data['kind'] == 'icon'
          ? ['svg']
          : ['sprite3'],
    );
    if (file == null || !mounted) return;
    final maxBytes = widget.games
        ? 100 * 1024 * 1024
        : data['kind'] == 'icon'
        ? 512 * 1024
        : 20 * 1024 * 1024;
    if ((await file.length() ?? 0) > maxBytes) {
      if (mounted) toast(context, '文件不能超过 ${fileSize(maxBytes)}');
      return;
    }
    if (!mounted) return;
    setState(() {
      uploading = true;
      progress = null;
    });
    await perform(
      context,
      () => ref
          .read(apiProvider)
          .upload(
            file,
            path: base,
            fields: data,
            onProgress: (sent, total) {
              if (mounted)
                setState(() => progress = total > 0 ? sent / total : null);
            },
          ),
      success: '发布成功',
    );
    if (mounted)
      setState(() {
        uploading = false;
        revision++;
      });
  }

  @override
  Widget build(BuildContext context) => FeaturePage(
    title: widget.games ? '小游戏' : '素材库',
    actions: [
      IconButton(
        tooltip: '我的发布',
        isSelected: mine,
        onPressed: () async {
          if (mine || await requireSignIn(context, ref)) {
            if (mounted) setState(() => mine = !mine);
          }
        },
        icon: const Icon(Icons.person_outline_rounded),
        selectedIcon: const Icon(Icons.person_rounded),
      ),
    ],
    fab: FloatingActionButton.extended(
      onPressed: uploading ? null : upload,
      icon: const Icon(Icons.upload_rounded),
      label: const Text('发布'),
    ),
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: SearchBar(
            leading: const Icon(Icons.search_rounded),
            hintText: widget.games ? '搜索小游戏' : '搜索素材',
            onChanged: (v) {
              debounce?.cancel();
              debounce = Timer(const Duration(milliseconds: 400), () {
                if (mounted) setState(() => query = v.trim());
              });
            },
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                for (final e in const {'hot': '热门', 'new': '最新'}.entries)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(e.value),
                      selected: sort == e.key,
                      onSelected: (_) => setState(() => sort = e.key),
                    ),
                  ),
                if (!widget.games) ...[
                  const SizedBox(width: 12),
                  for (final e in const {
                    'all': '全部',
                    'sprite': '角色',
                    'icon': '图标',
                  }.entries)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(e.value),
                        selected: kind == e.key,
                        onSelected: (_) => setState(() => kind = e.key),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
        if (uploading)
          Padding(
            padding: const EdgeInsets.all(20),
            child: LinearProgressIndicator(value: progress),
          ),
        Expanded(
          child: PagedList(
            grid: true,
            cacheKey: '$query:$sort:$kind:$mine:$revision',
            load: (page) async => PageResult.fromJson(
              await ref.read(apiProvider).get(base, {
                'q': query,
                'sort': sort,
                'kind': kind,
                'page': page,
                'pageSize': 24,
                if (mine) 'authorId': ref.read(appProvider).user?.id,
              }),
              (e) => e,
              page: page,
            ),
            itemBuilder: (row, _) => SurfaceCard(
              padding: EdgeInsets.zero,
              onTap: () => context.push('$base/${row['id']}'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(24),
                      ),
                      child: AppImage(
                        textOf(
                          row['thumbUrl'] ??
                              object(row['cover'])['url'] ??
                              row['coverUrl'],
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          textOf(row['title']),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          Member(object(row['author'])).name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Icon(
                              widget.games
                                  ? Icons.play_arrow_rounded
                                  : Icons.download_rounded,
                              size: 16,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '${intOf(row[widget.games ? 'playCount' : 'downloadCount'])}',
                            ),
                            const Spacer(),
                            Text(
                              widget.games
                                  ? 'HTML'
                                  : row['kind'] == 'icon'
                                  ? 'SVG'
                                  : '角色',
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class LibraryDetailPage extends ConsumerStatefulWidget {
  const LibraryDetailPage({super.key, required this.id, this.games = false});
  final String id;
  final bool games;
  @override
  ConsumerState<LibraryDetailPage> createState() => _LibraryDetailPageState();
}

class _LibraryDetailPageState extends ConsumerState<LibraryDetailPage> {
  String get path => '/${widget.games ? 'games' : 'assets'}/${widget.id}';
  bool downloading = false;
  @override
  Widget build(BuildContext context) => FeaturePage(
    title: widget.games ? '小游戏' : '素材',
    child: AsyncPanel<dynamic>(
      load: () => ref.read(apiProvider).get(path),
      builder: (data) {
        final row = object(data), author = Member(object(data['author']));
        return SingleChildScrollView(
          child: ReadingWidth(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (textOf(
                  row['thumbUrl'] ??
                      object(row['cover'])['url'] ??
                      row['coverUrl'],
                ).isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: SizedBox(
                      height: 240,
                      child: AppImage(
                        textOf(
                          row['thumbUrl'] ??
                              object(row['cover'])['url'] ??
                              row['coverUrl'],
                        ),
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                const SizedBox(height: 24),
                Text(
                  textOf(row['title']),
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    MemberAvatar(author, radius: 18),
                    const SizedBox(width: 12),
                    Expanded(child: Text(author.name)),
                    Text(relativeTime(row['createdAt'])),
                  ],
                ),
                const SizedBox(height: 24),
                if (textOf(row['summary']).isNotEmpty)
                  Text(textOf(row['summary'])),
                const SizedBox(height: 16),
                if (textOf(row['description']).isNotEmpty)
                  MarkdownContent(textOf(row['description'])),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: downloading
                      ? null
                      : () async {
                          final api = ref.read(apiProvider);
                          if (widget.games) {
                            // Keep untrusted game code in the site's isolated player.
                            await openLink(
                              context,
                              absoluteUrl('/games/${widget.id}'),
                              external: true,
                            );
                          } else {
                            final file = object(row['file']);
                            if (textOf(file['url']).isEmpty) {
                              toast(context, '文件暂不可用');
                              return;
                            }
                            setState(() => downloading = true);
                            await saveRemote(
                              context,
                              api,
                              textOf(file['url']),
                              textOf(file['filename'], '素材'),
                            );
                            if (mounted) setState(() => downloading = false);
                          }
                        },
                  icon: Icon(
                    widget.games
                        ? Icons.play_arrow_rounded
                        : Icons.download_rounded,
                  ),
                  label: Text(widget.games ? '开始游戏' : '下载素材'),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => copyText(
                    context,
                    absoluteUrl(
                      widget.games
                          ? '/games/${widget.id}'
                          : textOf(object(row['file'])['url'], '/assets'),
                    ),
                  ),
                  icon: const Icon(Icons.link_rounded),
                  label: const Text('分享'),
                ),
                if (author.id == ref.watch(appProvider).user?.id)
                  Padding(
                    padding: const EdgeInsets.only(top: 24),
                    child: TextButton(
                      onPressed: () async {
                        if (!await confirm(
                              context,
                              '删除这个${widget.games ? '游戏' : '素材'}？',
                            ) ||
                            !context.mounted)
                          return;
                        final ok = await perform(context, () async {
                          await ref.read(apiProvider).delete(path);
                          return true;
                        });
                        if (ok == true && context.mounted) context.pop();
                      },
                      child: const Text('删除'),
                    ),
                  ),
                const SizedBox(height: 64),
              ],
            ),
          ),
        );
      },
    ),
  );
}
