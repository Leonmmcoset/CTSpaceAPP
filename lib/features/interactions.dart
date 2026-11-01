import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/app_state.dart';
import '../core/models.dart';
import '../ui/forms.dart';
import '../ui/widgets.dart';
import 'composer.dart';

class LikeButton extends ConsumerStatefulWidget {
  const LikeButton({
    super.key,
    required this.type,
    required this.id,
    required this.count,
    this.liked = false,
  });
  final String type, id;
  final int count;
  final bool liked;
  @override
  ConsumerState<LikeButton> createState() => _LikeButtonState();
}

class _LikeButtonState extends ConsumerState<LikeButton> {
  late int count = widget.count;
  late bool liked = widget.liked;
  @override
  Widget build(BuildContext context) => SpringIconButton(
    icon: liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
    tooltip: '点赞',
    selected: liked,
    count: count,
    onPressed: () async {
      if (!await requireSignIn(context, ref)) return;
      final api = ref.read(apiProvider);
      final result = object(
        widget.type == 'project' || widget.type == 'extension'
            ? await api.post('/${widget.type}s/${widget.id}/like')
            : await api.post('/likes', {
                'targetType': widget.type,
                'targetId': widget.id,
              }),
      );
      if (mounted)
        setState(() {
          liked = boolOf(result['liked'] ?? result['likedByMe']);
          count = intOf(result['likeCount']);
        });
    },
  );
}

class BookmarkButton extends ConsumerStatefulWidget {
  const BookmarkButton(this.discussionId, {super.key});
  final String discussionId;
  @override
  ConsumerState<BookmarkButton> createState() => _BookmarkButtonState();
}

class _BookmarkButtonState extends ConsumerState<BookmarkButton> {
  bool selected = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!ref.read(appProvider).signedIn) return;
    try {
      final result = await ref.read(apiProvider).get('/bookmarks/check', {
        'discussionId': widget.discussionId,
      });
      if (mounted)
        setState(
          () =>
              selected = result == true || boolOf(object(result)['bookmarked']),
        );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) => SpringIconButton(
    icon: selected ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
    tooltip: selected ? '已收藏' : '收藏',
    selected: selected,
    onPressed: () async {
      if (!await requireSignIn(context, ref)) return;
      final result = await ref.read(apiProvider).post('/bookmarks', {
        'discussionId': widget.discussionId,
      });
      if (mounted)
        setState(
          () => selected = result is bool
              ? result
              : boolOf(object(result)['bookmarked']),
        );
    },
  );
}

class ReactionBar extends ConsumerStatefulWidget {
  const ReactionBar({super.key, required this.type, required this.id});
  final String type, id;
  @override
  ConsumerState<ReactionBar> createState() => _ReactionBarState();
}

class _ReactionBarState extends ConsumerState<ReactionBar> {
  Json counts = {};
  Set<String> mine = {};
  bool busy = false;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final result = object(
        await ref.read(apiProvider).get('/reactions/summary', {
          'targetType': widget.type,
          'ids': widget.id,
        }),
      );
      apply(object(result[widget.id]));
    } catch (_) {}
  }

  void apply(Json result) {
    if (mounted)
      setState(() {
        counts = object(result['counts']);
        mine = (result['mine'] as List? ?? []).map((e) => '$e').toSet();
      });
  }

  Future<void> react(String emoji) async {
    if (busy || !await requireSignIn(context, ref)) return;
    busy = true;
    try {
      apply(
        object(
          await ref.read(apiProvider).post('/reactions', {
            'targetType': widget.type,
            'targetId': widget.id,
            'emoji': emoji,
          }),
        ),
      );
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    } finally {
      busy = false;
    }
  }

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 6,
    runSpacing: 6,
    children: [
      for (final emoji in [
        '👍',
        '❤️',
        '😂',
        '🎉',
        '😮',
        '😢',
        '🔥',
        '🚀',
      ].where((e) => intOf(counts[e]) > 0))
        FilterChip(
          label: Text('$emoji ${counts[emoji]}'),
          selected: mine.contains(emoji),
          onSelected: (_) => react(emoji),
        ),
      ActionChip(
        avatar: const Icon(Icons.add_reaction_outlined, size: 18),
        label: const Text('表态'),
        onPressed: () async {
          final emoji = await showModalBottomSheet<String>(
            context: context,
            builder: (context) => Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                children: ['👍', '❤️', '😂', '🎉', '😮', '😢', '🔥', '🚀']
                    .map(
                      (e) => TextButton(
                        onPressed: () => Navigator.pop(context, e),
                        child: Text(e, style: const TextStyle(fontSize: 30)),
                      ),
                    )
                    .toList(),
              ),
            ),
          );
          if (emoji != null) await react(emoji);
        },
      ),
    ],
  );
}

Future<void> reportContent(
  BuildContext context,
  WidgetRef ref,
  String type,
  String id,
) async {
  if (!await requireSignIn(context, ref) || !context.mounted) return;
  await showFields(
    context,
    '举报',
    const [FieldSpec('reason', '举报原因', lines: 3)],
    submitLabel: '提交举报',
    onSubmit: (data) async {
      await ref.read(apiProvider).post('/reports', {
        'targetType': type,
        'targetId': id,
        ...data,
      });
    },
  );
}

class CommentsSection extends ConsumerStatefulWidget {
  const CommentsSection({super.key, required this.type, required this.id});
  final String type, id;
  @override
  ConsumerState<CommentsSection> createState() => _CommentsSectionState();
}

class _CommentsSectionState extends ConsumerState<CommentsSection> {
  int revision = 0;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SectionTitle(
        '评论',
        trailing: TextButton.icon(
          icon: const Icon(Icons.edit_outlined, size: 18),
          label: const Text('写评论'),
          onPressed: () async {
            if (!await requireSignIn(context, ref) || !context.mounted) return;
            final result = await context.push<bool>(
              '/compose',
              extra: ComposeRequest(
                'comment',
                targetType: widget.type,
                targetId: widget.id,
              ),
            );
            if (result == true && mounted) setState(() => revision++);
          },
        ),
      ),
      AsyncPanel<dynamic>(
        cacheKey: revision,
        load: () => ref.read(apiProvider).get('/comments', {
          'targetType': widget.type,
          'targetId': widget.id,
        }),
        builder: (data) {
          final rows = objects(data is List ? data : object(data)['items']);
          return rows.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text('还没有评论'),
                )
              : Column(children: rows.map((row) => _comment(row)).toList());
        },
      ),
    ],
  );
  Widget _comment(Json row, {int depth = 0}) {
    final author = Member(object(row['author'] ?? row['user']));
    final own =
        ref.watch(appProvider).user?.id ==
        (row['authorId'] ?? row['userId'] ?? author.id);
    return Padding(
      padding: EdgeInsets.only(left: depth > 0 ? 20 : 0, bottom: 16),
      child: SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                MemberAvatar(author, radius: 15),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    author.name,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
                Text(
                  relativeTime(row['createdAt']),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                PopupMenuButton<String>(
                  onSelected: (action) async {
                    if (action == 'edit') {
                      final ok = await context.push<bool>(
                        '/compose',
                        extra: ComposeRequest(
                          'comment',
                          id: textOf(row['id']),
                          initial: row,
                          targetType: widget.type,
                          targetId: widget.id,
                        ),
                      );
                      if (ok == true && mounted) setState(() => revision++);
                    } else if (action == 'delete') {
                      if (await confirm(context, '删除这条评论？') && mounted) {
                        await perform(
                          context,
                          () => ref
                              .read(apiProvider)
                              .delete('/comments/${row['id']}'),
                        );
                        if (mounted) setState(() => revision++);
                      }
                    } else {
                      await reportContent(
                        context,
                        ref,
                        'comment',
                        textOf(row['id']),
                      );
                    }
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
            const SizedBox(height: 12),
            MarkdownContent(textOf(row['content'])),
            TextButton(
              onPressed: () async {
                if (!await requireSignIn(context, ref) || !mounted) return;
                final ok = await context.push<bool>(
                  '/compose',
                  extra: ComposeRequest(
                    'comment',
                    targetType: widget.type,
                    targetId: widget.id,
                    parentId: textOf(row['id']),
                  ),
                );
                if (ok == true && mounted) setState(() => revision++);
              },
              child: const Text('回复'),
            ),
            if (depth < 3)
              for (final child in objects(row['replies'] ?? row['children']))
                _comment(child, depth: depth + 1),
          ],
        ),
      ),
    );
  }
}

class PollSection extends ConsumerStatefulWidget {
  const PollSection(this.discussionId, {super.key, this.canManage = false});
  final String discussionId;
  final bool canManage;
  @override
  ConsumerState<PollSection> createState() => _PollSectionState();
}

class _PollSectionState extends ConsumerState<PollSection> {
  Json? poll;
  Set<String> selected = {};
  bool busy = false;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final result = await ref.read(apiProvider).get('/polls', {
        'discussionId': widget.discussionId,
      });
      if (mounted)
        setState(() {
          poll = result == null ? null : object(result);
          selected = (poll?['mine'] as List? ?? []).map((e) => '$e').toSet();
        });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (poll == null || poll!.isEmpty)
      return widget.canManage
          ? TextButton.icon(
              onPressed: () async {
                final data = await showFields(context, '添加投票', const [
                  FieldSpec('question', '问题'),
                  FieldSpec('options', '选项（每行一个）', lines: 4),
                  FieldSpec(
                    'multiple',
                    '方式',
                    options: {'false': '单选', 'true': '多选'},
                  ),
                ]);
                if (data == null || !context.mounted) return;
                final options = textOf(data['options'])
                    .split('\n')
                    .map((e) => e.trim())
                    .where((e) => e.isNotEmpty)
                    .toSet()
                    .toList();
                if (options.length < 2) {
                  toast(context, '至少填写两个选项');
                  return;
                }
                await perform(
                  context,
                  () => ref.read(apiProvider).post('/polls', {
                    'discussionId': widget.discussionId,
                    'question': data['question'],
                    'options': options,
                    'multiple': data['multiple'] == 'true',
                  }),
                );
                await load();
              },
              icon: const Icon(Icons.poll_outlined),
              label: const Text('添加投票'),
            )
          : const SizedBox.shrink();
    final options = objects(poll!['options']);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: SurfaceCard(
        color: Theme.of(
          context,
        ).colorScheme.secondaryContainer.withValues(alpha: .45),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              textOf(poll!['question']),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            for (final o in options)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: selected.contains(o['id']),
                title: Text(textOf(o['text'] ?? o['label'])),
                subtitle: Text(
                  '${intOf(o['votes'] ?? o['voteCount'] ?? object(o['_count'])['votes'])} 票',
                ),
                onChanged: (value) => setState(() {
                  if (poll!['multiple'] != true) selected.clear();
                  if (value == true)
                    selected.add(textOf(o['id']));
                  else
                    selected.remove(o['id']);
                }),
              ),
            Row(
              children: [
                FilledButton.tonal(
                  onPressed: busy || selected.isEmpty
                      ? null
                      : () async {
                          if (!await requireSignIn(context, ref) ||
                              !context.mounted)
                            return;
                          setState(() => busy = true);
                          await perform(
                            context,
                            () => ref.read(apiProvider).post(
                              '/polls/${poll!['id']}/vote',
                              {'optionIds': selected.toList()},
                            ),
                          );
                          await load();
                          if (mounted) setState(() => busy = false);
                        },
                  child: const Text('投票'),
                ),
                const Spacer(),
                if (widget.canManage)
                  TextButton(
                    onPressed: () async {
                      if (await confirm(context, '删除投票？') && context.mounted) {
                        await perform(
                          context,
                          () => ref
                              .read(apiProvider)
                              .delete('/polls/${poll!['id']}'),
                        );
                        await load();
                      }
                    },
                    child: const Text('删除投票'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
