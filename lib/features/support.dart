import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/app_state.dart';
import '../core/im_store.dart';
import '../core/models.dart';
import '../ui/forms.dart';
import '../ui/widgets.dart';

class SupportPage extends ConsumerStatefulWidget {
  const SupportPage({super.key});
  @override
  ConsumerState<SupportPage> createState() => _SupportPageState();
}

class _SupportPageState extends ConsumerState<SupportPage> {
  int revision = 0;
  @override
  Widget build(BuildContext context) => FeaturePage(
    title: '客服',
    fab: FloatingActionButton.extended(
      onPressed: () async {
        if (!await requireSignIn(context, ref) || !context.mounted) return;
        String? id;
        await showFields(
          context,
          '新建咨询',
          const [FieldSpec('subject', '主题')],
          submitLabel: '开始咨询',
          onSubmit: (d) async {
            final result = object(
              await ref.read(apiProvider).post('/chat/conversations', d),
            );
            id = textOf(result['id']);
          },
        );
        if (!context.mounted) return;
        if (id != null && id!.isNotEmpty) await context.push('/support/$id');
        if (mounted) setState(() => revision++);
      },
      icon: const Icon(Icons.add_rounded),
      label: const Text('新建咨询'),
    ),
    child: AuthGate(
      child: AsyncPanel<dynamic>(
        cacheKey: revision,
        load: () => ref.read(apiProvider).get('/chat/conversations'),
        builder: (d) {
          final rows = objects(d is List ? d : object(d)['items']);
          if (rows.isEmpty)
            return const EmptyState(
              title: '暂无咨询',
              icon: Icons.support_agent_rounded,
            );
          return ListView.separated(
            padding: const EdgeInsets.all(24),
            itemCount: rows.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, i) {
              final c = rows[i];
              return SurfaceCard(
                onTap: () async {
                  await context.push('/support/${c['id']}');
                  if (mounted) setState(() => revision++);
                },
                child: Row(
                  children: [
                    const Icon(Icons.support_agent_rounded, size: 28),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            textOf(c['subject'], '咨询'),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            textOf(
                              object(c['lastMessage'])['content'],
                              relativeTime(c['createdAt']),
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Chip(label: Text(c['status'] == 'open' ? '进行中' : '已关闭')),
                  ],
                ),
              );
            },
          );
        },
      ),
    ),
  );
}

class SupportConversationPage extends ConsumerStatefulWidget {
  const SupportConversationPage({super.key, required this.id});
  final String id;
  @override
  ConsumerState<SupportConversationPage> createState() =>
      _SupportConversationPageState();
}

class _SupportConversationPageState
    extends ConsumerState<SupportConversationPage>
    with WidgetsBindingObserver {
  final input = TextEditingController(), scroll = ScrollController();
  Timer? timer;
  List<Json> messages = [];
  bool active = true, refreshing = false, loading = true, sending = false;
  String? error;
  String get path => '/chat/conversations/${widget.id}';
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    refresh();
    timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (active) refresh();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    timer?.cancel();
    input.dispose();
    scroll.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    active = state == AppLifecycleState.resumed;
    if (active) refresh();
  }

  Future<void> refresh() async {
    if (refreshing || !ref.read(appProvider).signedIn) return;
    refreshing = true;
    try {
      final result = object(await ref.read(apiProvider).get('$path/messages'));
      if (!mounted) return;
      final near =
          !scroll.hasClients ||
          scroll.position.maxScrollExtent - scroll.offset < 100;
      setState(() {
        messages = mergeMessages(messages, objects(result['messages']));
        error = null;
        loading = false;
      });
      if (near)
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && scroll.hasClients)
            scroll.animateTo(
              scroll.position.maxScrollExtent,
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
            );
        });
    } catch (e) {
      if (mounted)
        setState(() {
          error = friendlyError(e);
          loading = false;
        });
    } finally {
      refreshing = false;
    }
  }

  Future<void> send() async {
    if (sending || input.text.trim().isEmpty) return;
    setState(() => sending = true);
    final ok = await perform(context, () async {
      await ref.read(apiProvider).post('$path/messages', {
        'content': input.text.trim(),
      });
      return true;
    });
    if (!mounted) return;
    if (ok == true) {
      input.clear();
      await refresh();
    }
    if (mounted) setState(() => sending = false);
  }

  @override
  Widget build(BuildContext context) => FeaturePage(
    title: '咨询',
    actions: [
      IconButton(
        tooltip: '结束咨询',
        icon: const Icon(Icons.task_alt_rounded),
        onPressed: () async {
          if (!await confirm(context, '结束本次咨询？') || !context.mounted) return;
          final ok = await perform(context, () async {
            await ref.read(apiProvider).patch('$path/close');
            return true;
          });
          if (ok == true && context.mounted) context.pop();
        },
      ),
    ],
    child: AuthGate(
      child: Column(
        children: [
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : messages.isEmpty && error != null
                ? ErrorState(ApiFailure(error!), retry: refresh)
                : messages.isEmpty
                ? const EmptyState(
                    title: '发送消息开始咨询',
                    icon: Icons.support_agent_rounded,
                  )
                : ListView.builder(
                    controller: scroll,
                    padding: const EdgeInsets.all(24),
                    itemCount: messages.length,
                    itemBuilder: (context, i) {
                      final m = messages[i],
                          own =
                              (messages[i]['senderId'] ??
                                  messages[i]['userId']) ==
                              ref.read(appProvider).user?.id;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Align(
                          alignment: own
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 560),
                            child: SurfaceCard(
                              color: own
                                  ? Theme.of(
                                      context,
                                    ).colorScheme.primaryContainer
                                  : null,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (!own) ...[
                                    Text(
                                      '客服',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.labelSmall,
                                    ),
                                    const SizedBox(height: 6),
                                  ],
                                  SelectableText(textOf(m['content'])),
                                  const SizedBox(height: 8),
                                  Text(
                                    relativeTime(m['createdAt']),
                                    style: Theme.of(
                                      context,
                                    ).textTheme.labelSmall,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          if (error != null && messages.isNotEmpty)
            Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: input,
                    minLines: 1,
                    maxLines: 5,
                    decoration: const InputDecoration(hintText: '发送消息'),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton.filled(
                  tooltip: '发送',
                  onPressed: sending ? null : send,
                  icon: const Icon(Icons.arrow_upward_rounded),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
