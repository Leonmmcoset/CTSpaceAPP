import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../core/api.dart';
import '../core/app_state.dart';
import '../core/im_store.dart';
import '../core/models.dart';
import '../ui/forms.dart';
import '../ui/platform.dart';
import '../ui/widgets.dart';

class LivePage extends ConsumerStatefulWidget {
  const LivePage({super.key});
  @override
  ConsumerState<LivePage> createState() => _LivePageState();
}

class _LivePageState extends ConsumerState<LivePage>
    with WidgetsBindingObserver {
  io.Socket? socket;
  Timer? timer;
  Json? session;
  List<Json> messages = [], questions = [], lotteries = [];
  bool active = true,
      loading = true,
      refreshing = false,
      connected = false,
      sending = false;
  String? error;
  int tab = 0, viewers = 0, ticks = 0, historyPage = 1;
  bool olderAvailable = false, loadingOlder = false;
  final input = TextEditingController();
  final scroll = ScrollController();
  String get path => '/live/session/${session!['id']}';
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(refresh());
    timer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (active)
        unawaited(
          refresh(checkCurrent: ticks++ % 2 == 0, interactions: !connected),
        );
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    timer?.cancel();
    socket?.dispose();
    input.dispose();
    scroll.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    active = state == AppLifecycleState.resumed;
    if (active) {
      socket?.connect();
      unawaited(refresh());
    } else {
      socket?.disconnect();
    }
  }

  Future<void> refresh({
    bool checkCurrent = true,
    bool interactions = true,
  }) async {
    if (refreshing || !active || !mounted) return;
    refreshing = true;
    try {
      if (checkCurrent) {
        final next = object(
          (await ref.read(apiProvider).get('/live/current'))['session'],
        );
        if (!mounted) return;
        final changed = next['id'] != session?['id'];
        session = next.isEmpty ? null : next;
        if (changed) {
          messages = [];
          questions = [];
          lotteries = [];
          historyPage = 1;
          socket?.dispose();
          socket = null;
          connected = false;
          if (session != null) connect();
        }
      }
      if (session != null && interactions) {
        final id = session!['id'];
        final data = await Future.wait([
          ref.read(apiProvider).get('$path/chat', {'page': 1}),
          ref.read(apiProvider).get('$path/qa'),
          ref.read(apiProvider).get('$path/lotteries'),
        ]);
        if (!mounted || session?['id'] != id) return;
        final shouldScroll =
            !scroll.hasClients ||
            scroll.position.maxScrollExtent - scroll.offset < 100;
        messages = mergeMessages(
          messages,
          objects(object(data[0])['messages']),
        );
        questions = mergeMessages(
          questions,
          objects(object(data[1])['questions']),
        );
        lotteries = mergeMessages(
          lotteries,
          objects(object(data[2])['lotteries']),
        );
        olderAvailable = objects(object(data[0])['messages']).length >= 50;
        if (shouldScroll) toBottom();
      }
      error = null;
    } catch (e) {
      if (mounted) error = friendlyError(e);
    } finally {
      refreshing = false;
      if (mounted) setState(() => loading = false);
    }
  }

  void connect() {
    final id = session?['id'];
    if (id == null || !active) return;
    socket?.dispose();
    socket = io.io(
      siteUri.origin,
      io.OptionBuilder()
          .setPath('/api/live/ws')
          .setTransports(['websocket'])
          .setAuth({'token': ref.read(apiProvider).token ?? ''})
          .setQuery({'sessionId': id})
          .disableAutoConnect()
          .enableForceNew()
          .enableReconnection()
          .build(),
    );
    void update(void Function() change) {
      if (mounted && session?['id'] == id) setState(change);
    }

    socket!.onConnect((_) {
      update(() => connected = true);
      unawaited(refresh(checkCurrent: false));
    });
    socket!.onDisconnect((_) => update(() => connected = false));
    socket!.onConnectError((_) => update(() => connected = false));
    socket!.on(
      'viewers',
      (e) => update(() => viewers = intOf(object(e)['count'])),
    );
    socket!.on('chat', (e) {
      final near =
          !scroll.hasClients ||
          scroll.position.maxScrollExtent - scroll.offset < 100;
      update(() => messages = mergeMessages(messages, [object(e)]));
      if (near) toBottom();
    });
    for (final event in ['qa:new', 'qa:answered']) {
      socket!.on(
        event,
        (e) => update(() => questions = mergeMessages(questions, [object(e)])),
      );
    }
    for (final event in ['lottery:new', 'lottery:drawn']) {
      socket!.on(
        event,
        (e) => update(() => lotteries = mergeMessages(lotteries, [object(e)])),
      );
    }
    socket!.on('stream:start', (_) => unawaited(refresh()));
    socket!.on(
      'stream:end',
      (_) => update(() => session = {...?session, 'status': 'ended'}),
    );
    socket!.connect();
  }

  void toBottom() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted && scroll.hasClients)
      scroll.animateTo(
        scroll.position.maxScrollExtent,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
  });
  Future<void> older() async {
    if (loadingOlder) return;
    setState(() => loadingOlder = true);
    final id = session?['id'];
    final data = await perform(
      context,
      () => ref.read(apiProvider).get('$path/chat', {'page': historyPage + 1}),
    );
    if (!mounted) return;
    if (data != null && session?['id'] == id) {
      final rows = objects(object(data)['messages']);
      final extent = scroll.hasClients ? scroll.position.maxScrollExtent : 0.0;
      final offset = scroll.hasClients ? scroll.offset : 0.0;
      setState(() {
        messages = mergeMessages(messages, rows);
        historyPage++;
        olderAvailable = rows.length >= 50;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && scroll.hasClients)
          scroll.jumpTo(offset + scroll.position.maxScrollExtent - extent);
      });
    }
    setState(() => loadingOlder = false);
  }

  Future<void> send() async {
    if (sending || input.text.trim().isEmpty) return;
    if (!await requireSignIn(context, ref) || !mounted || session == null)
      return;
    setState(() => sending = true);
    final content = input.text.trim();
    final ok = await perform(context, () async {
      await ref.read(apiProvider).post('$path/chat', {'content': content});
      return true;
    });
    if (!mounted) return;
    if (ok == true) {
      input.clear();
      await refresh(checkCurrent: false);
      toBottom();
    }
    if (mounted) setState(() => sending = false);
  }

  Future<void> ask() async {
    if (!await requireSignIn(context, ref) || !mounted) return;
    await showFields(
      context,
      '向主播提问',
      const [FieldSpec('question', '问题', lines: 3)],
      submitLabel: '提问',
      onSubmit: (d) async {
        await ref.read(apiProvider).post('$path/qa', d);
      },
    );
    await refresh(checkCurrent: false);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(appProvider.select((a) => a.user?.id), (_, _) => connect());
    return FeaturePage(
      title: '直播',
      actions: [
        IconButton(
          tooltip: '刷新',
          onPressed: () => refresh(),
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
      child: loading
          ? const Center(child: CircularProgressIndicator())
          : session == null
          ? error != null
                ? ErrorState(ApiFailure(error!), retry: refresh)
                : const EmptyState(title: '暂无直播', icon: Icons.live_tv_rounded)
          : LayoutBuilder(
              builder: (context, box) {
                final wide = box.maxWidth >= 900;
                final overview = SurfaceCard(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Center(
                        child: Icon(Icons.live_tv_rounded, size: 56),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        textOf(session!['title'], '创客次元直播'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Icon(
                            connected ? Icons.wifi_rounded : Icons.sync_rounded,
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${const {'live': '直播中', 'idle': '准备中', 'ended': '已结束'}[session!['status']] ?? '准备中'} · $viewers 人',
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: () => openLink(
                          context,
                          absoluteUrl('/live'),
                          external: true,
                        ),
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: const Text('观看直播'),
                      ),
                    ],
                  ),
                );
                final interactive = Column(
                  children: [
                    const SizedBox(height: 12),
                    SegmentedButton<int>(
                      segments: const [
                        ButtonSegment(value: 0, label: Text('聊天')),
                        ButtonSegment(value: 1, label: Text('问答')),
                        ButtonSegment(value: 2, label: Text('抽奖')),
                      ],
                      selected: {tab},
                      onSelectionChanged: (v) => setState(() => tab = v.first),
                    ),
                    if (error != null)
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(
                          error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: switch (tab) {
                        0 => chat(),
                        1 => qa(),
                        _ => lottery(),
                      },
                    ),
                  ],
                );
                return wide
                    ? Padding(
                        padding: const EdgeInsets.all(24),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(child: overview),
                            const SizedBox(width: 24),
                            Expanded(child: interactive),
                          ],
                        ),
                      )
                    : Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                            child: overview,
                          ),
                          Expanded(child: interactive),
                        ],
                      );
              },
            ),
    );
  }

  Widget chat() => Column(
    children: [
      Expanded(
        child: messages.isEmpty
            ? const EmptyState(
                title: '来聊聊吧',
                icon: Icons.chat_bubble_outline_rounded,
              )
            : ListView.builder(
                controller: scroll,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: messages.length + 1,
                itemBuilder: (context, i) {
                  if (i == 0)
                    return olderAvailable
                        ? Center(
                            child: TextButton(
                              onPressed: loadingOlder ? null : older,
                              child: const Text('更早的消息'),
                            ),
                          )
                        : const SizedBox(height: 4);
                  final m = messages[i - 1],
                      member = Member(
                        object(
                          messages[i - 1]['user'] ?? messages[i - 1]['author'],
                        ),
                      );
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        MemberAvatar(member, radius: 15),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                member.name,
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                              const SizedBox(height: 4),
                              SelectableText(textOf(m['content'])),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
      Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: input,
                minLines: 1,
                maxLines: 3,
                onSubmitted: (_) => send(),
                decoration: const InputDecoration(hintText: '聊点什么'),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              tooltip: '发送',
              onPressed: sending || session?['status'] == 'ended' ? null : send,
              icon: const Icon(Icons.arrow_upward_rounded),
            ),
          ],
        ),
      ),
    ],
  );
  Widget qa() => Column(
    children: [
      Expanded(
        child: questions.isEmpty
            ? const EmptyState(
                title: '暂无提问',
                icon: Icons.question_answer_outlined,
              )
            : ListView.separated(
                padding: const EdgeInsets.all(20),
                itemCount: questions.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, i) {
                  final q = questions[i];
                  return SurfaceCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          textOf(q['question']),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        if (q['answer'] != null) ...[
                          const SizedBox(height: 12),
                          Text(textOf(q['answer'])),
                        ] else ...[
                          const SizedBox(height: 10),
                          const Text('等待回答'),
                        ],
                      ],
                    ),
                  );
                },
              ),
      ),
      Padding(
        padding: const EdgeInsets.all(12),
        child: FilledButton.tonalIcon(
          onPressed: session?['status'] == 'ended' ? null : ask,
          icon: const Icon(Icons.add_rounded),
          label: const Text('提问'),
        ),
      ),
    ],
  );
  Widget lottery() => lotteries.isEmpty
      ? const EmptyState(title: '暂无抽奖', icon: Icons.redeem_rounded)
      : ListView.separated(
          padding: const EdgeInsets.all(20),
          itemCount: lotteries.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (context, i) {
            final l = lotteries[i], winners = objects(lotteries[i]['winners']);
            final drawn = l['drawnAt'] != null || l['status'] == 'drawn';
            return SurfaceCard(
              color: Theme.of(context).colorScheme.tertiaryContainer,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.redeem_rounded, size: 32),
                  const SizedBox(height: 16),
                  Text(
                    textOf(l['title']),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  Text('${intOf(l['prizeCount'])} 个名额'),
                  const SizedBox(height: 16),
                  if (drawn)
                    Text(
                      winners.isEmpty
                          ? '已开奖'
                          : '中奖：${winners.map((e) => Member(object(e['user']).isEmpty ? e : object(e['user'])).name).join('、')}',
                    )
                  else
                    FilledButton(
                      onPressed: () async {
                        if (!await requireSignIn(context, ref) ||
                            !context.mounted)
                          return;
                        await perform(context, () async {
                          await ref
                              .read(apiProvider)
                              .post('/live/lottery/${l['id']}/enter');
                          return true;
                        }, success: '已参与');
                        await refresh(checkCurrent: false);
                      },
                      child: const Text('参与抽奖'),
                    ),
                ],
              ),
            );
          },
        );
}
