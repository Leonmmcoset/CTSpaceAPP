import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/app_state.dart';
import '../core/im_store.dart';
import '../core/models.dart';
import '../ui/forms.dart';
import '../ui/platform.dart';
import '../ui/widgets.dart';

class MessagesPage extends ConsumerStatefulWidget {
  const MessagesPage({super.key, this.userId});
  final String? userId;
  @override
  ConsumerState<MessagesPage> createState() => _MessagesPageState();
}

class _MessagesPageState extends ConsumerState<MessagesPage>
    with WidgetsBindingObserver {
  late ImStore store;
  String? identity;
  final input = TextEditingController();
  final scroll = ScrollController();
  final drafts = <String, String>{};
  bool sending = false;
  Json? quote;
  String? latestMessage;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    store = ImStore(ref.read(apiProvider))..addListener(update);
    WidgetsBinding.instance.addPostFrameCallback((_) => syncIdentity());
  }

  void update() {
    if (!mounted) return;
    final latest = store.messages.lastOrNull?['id']?.toString();
    final nearBottom =
        !scroll.hasClients ||
        scroll.position.maxScrollExtent - scroll.offset < 100;
    final changed = latest != latestMessage;
    latestMessage = latest;
    setState(() {});
    if (changed && nearBottom) toBottom();
  }

  Future<void> syncIdentity() async {
    if (!mounted) return;
    final user = ref.read(appProvider).user;
    if (user?.id == identity) return;
    identity = user?.id;
    store.removeListener(update);
    store.dispose();
    store = ImStore(ref.read(apiProvider))..addListener(update);
    if (user == null) {
      update();
      return;
    }
    await store.start();
    if (widget.userId != null && mounted) {
      try {
        final raw = object(
          await ref.read(apiProvider).get('/users/${widget.userId}'),
        );
        await store.openUser(Member(raw));
      } catch (e) {
        if (mounted) toast(context, friendlyError(e));
      }
    }
    update();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    store.removeListener(update);
    store.dispose();
    input.dispose();
    scroll.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    store.setActive(state == AppLifecycleState.resumed);
  }

  Future<void> open(Conversation c) async {
    if (store.current != null) drafts[store.current!.id] = input.text;
    input.text = drafts[c.id] ?? '';
    quote = null;
    await store.open(c);
    toBottom();
  }

  void toBottom() {
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
  }

  Future<void> send() async {
    if (sending || input.text.trim().isEmpty) return;
    final content = input.text.trim();
    setState(() => sending = true);
    try {
      await store.send({
        'content': content,
        if (quote != null) 'quotedId': quote!['id'],
      });
      if (mounted) {
        input.clear();
        quote = null;
        drafts.remove(store.current?.id);
        toBottom();
      }
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> image() async {
    if (sending) return;
    final file = await pickFile(
      extensions: ['jpg', 'jpeg', 'png', 'gif', 'webp'],
    );
    if (file == null || !mounted) return;
    if ((await file.length() ?? 0) > 100 * 1024 * 1024) {
      if (mounted) toast(context, '图片不能超过 100 MB');
      return;
    }
    setState(() => sending = true);
    try {
      final r = await ref.read(apiProvider).upload(file, path: '/im/upload');
      await store.send({'type': 'image', 'imageUrl': r.url});
      toBottom();
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(appProvider.select((a) => a.user?.id), (_, _) => syncIdentity());
    return AuthGate(
      child: LayoutBuilder(
        builder: (context, box) {
          final split = MediaQuery.sizeOf(context).width >= 840;
          if (!split && store.current != null) return conversation();
          return Row(
            children: [
              SizedBox(width: split ? 300 : box.maxWidth, child: inbox()),
              if (split) ...[
                const VerticalDivider(width: 1),
                Expanded(
                  child: store.current == null
                      ? const EmptyState(
                          title: '选择一个会话',
                          icon: Icons.chat_bubble_outline_rounded,
                        )
                      : conversation(),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget inbox() {
    final dm = objects(store.inbox['dm']),
        groups = objects(store.inbox['groups']);
    return FeaturePage(
      title: '消息',
      actions: [
        IconButton(
          tooltip: '通知',
          onPressed: () => context.push('/notifications'),
          icon: const Icon(Icons.notifications_outlined),
        ),
        IconButton(
          tooltip: '好友',
          onPressed: () async {
            await context.push('/friends');
            await store.refreshInbox();
          },
          icon: const Icon(Icons.group_outlined),
        ),
      ],
      fab: FloatingActionButton(
        onPressed: () async {
          await context.push('/friends');
          await store.refreshInbox();
        },
        tooltip: '发起聊天',
        child: const Icon(Icons.edit_rounded),
      ),
      child: RefreshIndicator(
        onRefresh: store.refreshInbox,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 110),
          children: [
            if (store.error != null)
              Text(
                store.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (dm.isEmpty && groups.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 80),
                child: EmptyState(
                  title: '还没有会话',
                  icon: Icons.chat_bubble_outline_rounded,
                ),
              ),
            for (final row in dm) _thread(row, false),
            if (groups.isNotEmpty) const SectionTitle('群聊'),
            for (final row in groups) _thread(row, true),
          ],
        ),
      ),
    );
  }

  Widget _thread(Json row, bool group) {
    final peer = object(row['peer'] ?? row['other'] ?? row['user']);
    final g = object(row['group']).isEmpty ? row : object(row['group']);
    final id = textOf(
      group ? row['groupId'] ?? g['id'] : row['threadId'] ?? row['id'],
    );
    final title = group
        ? textOf(g['name'] ?? row['title'], '群聊')
        : Member(peer).name;
    final member = Member({
      'id': peer['id'],
      'nickname': title,
      'avatar': group ? g['avatar'] : peer['avatar'],
    });
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        selected: store.current?.id == id,
        selectedTileColor: Theme.of(context).colorScheme.secondaryContainer,
        leading: Badge(
          isLabelVisible: intOf(row['unread']) > 0,
          label: Text('${intOf(row['unread'])}'),
          child: MemberAvatar(
            member,
            radius: 22,
            onTap: () => open(
              Conversation(
                kind: group ? 'group' : 'dm',
                id: id,
                title: title,
                avatar: member.avatar,
                raw: row,
              ),
            ),
          ),
        ),
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          textOf(
            object(row['lastMessage'])['content'] ?? row['lastContent'],
            group ? '群聊' : '私信',
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        onTap: () => open(
          Conversation(
            kind: group ? 'group' : 'dm',
            id: id,
            title: title,
            avatar: member.avatar,
            raw: row,
          ),
        ),
      ),
    );
  }

  Widget conversation() {
    final c = store.current!;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: '返回会话列表',
          onPressed: () {
            drafts[c.id] = input.text;
            store.close();
          },
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(
              store.connected ? '已连接' : '正在重新连接',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
        actions: [
          if (c.kind == 'group')
            IconButton(
              tooltip: '群设置',
              onPressed: () => context.push('/groups/${c.id}'),
              icon: const Icon(Icons.group_outlined),
            ),
          PopupMenuButton<String>(
            onSelected: (a) async {
              if (a == 'transfer') await transfer();
              if (a == 'redpacket') await redpacket();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'transfer', child: Text('转积分')),
              if (c.kind == 'group')
                const PopupMenuItem(value: 'redpacket', child: Text('发红包')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: store.loading
                ? const Center(child: CircularProgressIndicator())
                : store.error != null && store.messages.isEmpty
                ? ErrorState(
                    ApiFailure(store.error!),
                    retry: () => store.open(c),
                  )
                : ListView.builder(
                    controller: scroll,
                    padding: const EdgeInsets.all(20),
                    itemCount: store.messages.length + 1,
                    itemBuilder: (context, i) => i == 0
                        ? store.hasMore
                              ? Center(
                                  child: TextButton(
                                    onPressed: store.loadingHistory
                                        ? null
                                        : store.older,
                                    child: Text(
                                      store.loadingHistory ? '加载中' : '更早的消息',
                                    ),
                                  ),
                                )
                              : const SizedBox(height: 8)
                        : message(store.messages[i - 1]),
                  ),
          ),
          if (quote != null)
            Container(
              padding: const EdgeInsets.fromLTRB(20, 8, 12, 8),
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      textOf(quote!['content'], '图片'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    tooltip: '取消引用',
                    onPressed: () => setState(() => quote = null),
                    icon: const Icon(Icons.close_rounded, size: 18),
                  ),
                ],
              ),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    tooltip: '发送图片',
                    onPressed: sending ? null : image,
                    icon: const Icon(Icons.image_outlined),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: TextField(
                      controller: input,
                      minLines: 1,
                      maxLines: 5,
                      onChanged: (v) => drafts[c.id] = v,
                      decoration: const InputDecoration(hintText: '发送消息'),
                      textInputAction: TextInputAction.newline,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    tooltip: '发送',
                    onPressed: sending ? null : send,
                    icon: sending
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.arrow_upward_rounded),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget message(Json m) {
    final user = Member(object(m['sender'] ?? m['author']));
    final own = (m['senderId'] ?? user.id) == ref.read(appProvider).user?.id;
    final recalled = m['recalledAt'] != null;
    final type = textOf(m['type'], 'text');
    if (recalled)
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: Text('消息已撤回', style: Theme.of(context).textTheme.labelSmall),
        ),
      );
    final color = own
        ? Theme.of(context).colorScheme.primaryContainer
        : Theme.of(context).colorScheme.surfaceContainerHigh;
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: own
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          if (!own) ...[
            MemberAvatar(user, radius: 16),
            const SizedBox(width: 10),
          ],
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: own
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  if (!own && store.current?.kind == 'group')
                    Padding(
                      padding: const EdgeInsets.only(bottom: 5),
                      child: Text(
                        user.name,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ),
                  GestureDetector(
                    onLongPress: () => messageActions(m, own),
                    onSecondaryTap: () => messageActions(m, own),
                    child: Container(
                      padding: type == 'image'
                          ? const EdgeInsets.all(5)
                          : const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (m['quoted'] != null || m['quotedMessage'] != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Text(
                                textOf(
                                  object(
                                    m['quoted'] ?? m['quotedMessage'],
                                  )['content'],
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                          if (type == 'image')
                            ConstrainedBox(
                              constraints: const BoxConstraints(
                                maxHeight: 260,
                                maxWidth: 280,
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: AppImage(
                                  textOf(m['imageUrl']),
                                  fit: BoxFit.contain,
                                ),
                              ),
                            )
                          else if (type == 'redpacket')
                            TextButton.icon(
                              onPressed: () =>
                                  claimPacket(textOf(m['redPacketId'])),
                              icon: const Icon(Icons.redeem_rounded),
                              label: const Text('积分红包'),
                            )
                          else if (type == 'transfer')
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.toll_rounded),
                                const SizedBox(width: 10),
                                Flexible(
                                  child: Text(textOf(m['content'], '积分转账')),
                                ),
                              ],
                            )
                          else
                            SelectableText(textOf(m['content'])),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    relativeTime(m['createdAt']),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (own) ...[
            const SizedBox(width: 10),
            MemberAvatar(user, radius: 16),
          ],
        ],
      ),
    );
  }

  Future<void> messageActions(Json m, bool own) async {
    final canRecall =
        own &&
        DateTime.now()
                .difference(
                  DateTime.tryParse(textOf(m['createdAt'])) ?? DateTime(2000),
                )
                .inSeconds <
            120;
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final entry in {
              'copy': '复制',
              'quote': '引用',
              'forward': '转发',
              if (canRecall) 'recall': '撤回',
              'report': '举报',
            }.entries)
              ListTile(
                title: Text(entry.value),
                onTap: () => Navigator.pop(context, entry.key),
              ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'copy')
      await copyText(context, textOf(m['content'] ?? m['imageUrl']));
    else if (action == 'quote')
      setState(() => quote = m);
    else if (action == 'recall') {
      final d = await perform(
        context,
        () => ref
            .read(apiProvider)
            .post('${store.current!.path}/messages/${m['id']}/recall'),
      );
      if (d != null) store.merge([object(d)]);
    } else if (action == 'report' && mounted)
      await showFields(
        context,
        '举报消息',
        const [FieldSpec('reason', '原因', lines: 3)],
        submitLabel: '提交',
        onSubmit: (d) async {
          await ref.read(apiProvider).post('/im/report', {
            'scope': store.current!.kind,
            if (store.current!.kind == 'dm') 'threadId': store.current!.id,
            if (store.current!.kind == 'group') 'groupId': store.current!.id,
            'messageId': m['id'],
            ...d,
          });
        },
      );
    else if (action == 'forward' && mounted)
      await forward(m);
  }

  Future<void> forward(Json m) async {
    final choices = <String, String>{
      for (final row in objects(store.inbox['dm']))
        'dm:${row['threadId'] ?? row['id']}': Member(
          object(row['peer'] ?? row['other']),
        ).name,
      for (final row in objects(store.inbox['groups']))
        'group:${row['groupId'] ?? row['id']}': textOf(
          row['name'] ?? object(row['group'])['name'],
          '群聊',
        ),
    };
    if (choices.isEmpty) {
      toast(context, '没有可转发的会话');
      return;
    }
    await showFields(
      context,
      '转发消息',
      [FieldSpec('target', '会话', options: choices)],
      submitLabel: '转发',
      onSubmit: (d) async {
        final target = textOf(d['target']).split(':');
        await ref.read(apiProvider).post('/im/forward', {
          'mode': 'single',
          'items': [
            {'kind': store.current!.kind, 'id': m['id']},
          ],
          target.first == 'dm' ? 'targetThreadId' : 'targetGroupId':
              target.last,
        });
      },
    );
  }

  Future<void> transfer() async {
    final c = store.current!;
    final data = await showFields(context, '积分转账', [
      if (c.kind == 'group') const FieldSpec('toUserId', '收款人用户 ID'),
      const FieldSpec('amount', '积分', number: true),
      const FieldSpec('note', '备注', required: false),
    ], submitLabel: '下一步');
    if (data == null || !mounted) return;
    if ((data['amount'] as num) <= 0 ||
        data['amount'] != intOf(data['amount'])) {
      toast(context, '请输入正整数积分');
      return;
    }
    if (!await confirm(context, '确认转账 ${data['amount']} 积分？') || !mounted)
      return;
    await perform(
      context,
      () => ref.read(apiProvider).post('${c.path}/transfer', data),
      success: '转账成功',
    );
    await ref.read(appProvider).refreshUser();
    await store.resync();
  }

  Future<void> redpacket() async {
    final c = store.current!;
    await showFields(
      context,
      '发积分红包',
      const [
        FieldSpec('totalAmount', '总积分', number: true),
        FieldSpec('count', '红包个数', number: true),
        FieldSpec('type', '方式', options: {'random': '拼手气', 'equal': '等额'}),
        FieldSpec('message', '祝福语', required: false),
      ],
      submitLabel: '下一步',
      onSubmit: (d) async {
        if ((d['count'] as num) < 1 ||
            (d['totalAmount'] as num) < (d['count'] as num))
          throw const ApiFailure('积分应不少于红包个数');
        if (!await confirm(context, '确认发出 ${d['totalAmount']} 积分红包？'))
          throw const ApiFailure('已取消');
        await ref.read(apiProvider).post('${c.path}/redpacket', d);
        await store.resync();
        await ref.read(appProvider).refreshUser();
      },
    );
  }

  Future<void> claimPacket(String id) async {
    final d = await perform(
      context,
      () => ref.read(apiProvider).get('/im/redpacket/$id'),
    );
    if (d == null || !mounted) return;
    final packet = object(d);
    if (await confirm(
          context,
          textOf(packet['message'], '积分红包'),
          action: '领取',
        ) &&
        mounted) {
      await perform(
        context,
        () => ref.read(apiProvider).post('/im/redpacket/$id/claim'),
        success: '已领取',
      );
      await ref.read(appProvider).refreshUser();
      await store.resync();
    }
  }
}

class FriendsPage extends ConsumerStatefulWidget {
  const FriendsPage({super.key});
  @override
  ConsumerState<FriendsPage> createState() => _FriendsPageState();
}

class _FriendsPageState extends ConsumerState<FriendsPage> {
  int revision = 0;
  @override
  Widget build(BuildContext context) => FeaturePage(
    title: '好友与群聊',
    actions: [
      IconButton(
        tooltip: '添加好友',
        icon: const Icon(Icons.person_add_alt_rounded),
        onPressed: search,
      ),
      IconButton(
        tooltip: '新建群聊',
        icon: const Icon(Icons.group_add_outlined),
        onPressed: () async {
          await showFields(
            context,
            '新建群聊',
            const [
              FieldSpec('name', '群名称'),
              FieldSpec('description', '群介绍', required: false, lines: 3),
            ],
            onSubmit: (d) async {
              await ref.read(apiProvider).post('/im/groups', d);
            },
          );
          if (mounted) setState(() => revision++);
        },
      ),
    ],
    child: AuthGate(
      child: AsyncPanel<dynamic>(
        cacheKey: revision,
        load: () async {
          final api = ref.read(apiProvider);
          return await Future.wait([
            api.get('/im/friends'),
            api.get('/im/friends/requests'),
            api.get('/im/group-invites'),
            api.get('/im/groups'),
          ]);
        },
        builder: (d) {
          final friends = objects(
            d[0] is List
                ? d[0]
                : object(d[0])['items'] ?? object(d[0])['friends'],
          );
          final requests = objects(
            d[1] is List
                ? d[1]
                : object(d[1])['incoming'] ?? object(d[1])['items'],
          );
          final invites = objects(d[2] is List ? d[2] : object(d[2])['items']);
          final groups = objects(d[3] is List ? d[3] : object(d[3])['items']);
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              if (requests.isNotEmpty) const SectionTitle('好友申请'),
              for (final r in requests)
                ListTile(
                  leading: MemberAvatar(Member(object(r['requester']))),
                  title: Text(Member(object(r['requester'])).name),
                  trailing: Wrap(
                    children: [
                      TextButton(
                        onPressed: () => respond(
                          '/im/friends/${r['id'] ?? r['friendshipId']}/respond',
                          {'accept': false},
                        ),
                        child: const Text('拒绝'),
                      ),
                      FilledButton.tonal(
                        onPressed: () => respond(
                          '/im/friends/${r['id'] ?? r['friendshipId']}/respond',
                          {'accept': true},
                        ),
                        child: const Text('接受'),
                      ),
                    ],
                  ),
                ),
              if (invites.isNotEmpty) const SectionTitle('入群邀请'),
              for (final r in invites)
                ListTile(
                  title: Text(textOf(object(r['group'])['name'])),
                  trailing: Wrap(
                    children: [
                      TextButton(
                        onPressed: () =>
                            respond('/im/group-invites/${r['id']}/reject', {}),
                        child: const Text('拒绝'),
                      ),
                      FilledButton.tonal(
                        onPressed: () =>
                            respond('/im/group-invites/${r['id']}/accept', {}),
                        child: const Text('加入'),
                      ),
                    ],
                  ),
                ),
              const SectionTitle('好友'),
              if (friends.isEmpty) const Text('还没有好友'),
              for (final f in friends) _friend(f),
              const SectionTitle('群聊'),
              for (final group in groups)
                ListTile(
                  leading: const Icon(Icons.group_outlined),
                  title: Text(textOf(group['name'])),
                  onTap: () => context.push('/groups/${group['id']}'),
                ),
              const SizedBox(height: 64),
            ],
          );
        },
      ),
    ),
  );
  Widget _friend(Json f) {
    final raw = object(f['user'] ?? f['friend'] ?? f['other']);
    final user = Member(raw.isEmpty ? f : raw);
    return ListTile(
      leading: MemberAvatar(user),
      title: Text(user.name),
      subtitle: Text('@${user.username}'),
      onTap: () => context.push('/messages?user=${user.id}'),
      trailing: PopupMenuButton<String>(
        onSelected: (a) async {
          if (await confirm(context, '移除此好友？') && mounted) {
            await perform(
              context,
              () => ref.read(apiProvider).delete('/im/friends/${user.id}'),
            );
            if (mounted) setState(() => revision++);
          }
        },
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'remove', child: Text('移除好友')),
        ],
      ),
    );
  }

  Future<void> respond(String path, Json body) async {
    await perform(context, () => ref.read(apiProvider).post(path, body));
    if (mounted) setState(() => revision++);
  }

  Future<void> search() async {
    final d = await showFields(context, '查找用户', const [
      FieldSpec('q', '用户名'),
    ], submitLabel: '查找');
    if (d == null || !mounted) return;
    final raw = await perform(
      context,
      () => ref.read(apiProvider).get('/im/users/search', d),
    );
    if (raw == null || !mounted) return;
    final users = objects(raw is List ? raw : object(raw)['items']);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final r in users)
              ListTile(
                leading: MemberAvatar(Member(r)),
                title: Text(Member(r).name),
                trailing: FilledButton.tonal(
                  onPressed: () async {
                    final ok = await perform(context, () async {
                      await ref.read(apiProvider).post('/im/friends/request', {
                        'addresseeId': r['id'],
                      });
                      return true;
                    }, success: '好友申请已发送');
                    if (ok == true && context.mounted) Navigator.pop(context);
                  },
                  child: const Text('添加'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class GroupPage extends ConsumerStatefulWidget {
  const GroupPage({super.key, required this.id});
  final String id;
  @override
  ConsumerState<GroupPage> createState() => _GroupPageState();
}

class _GroupPageState extends ConsumerState<GroupPage> {
  int revision = 0;
  String get path => '/im/groups/${widget.id}';
  @override
  Widget build(BuildContext context) => FeaturePage(
    title: '群设置',
    child: AuthGate(
      child: AsyncPanel<dynamic>(
        cacheKey: revision,
        load: () => ref.read(apiProvider).get(path),
        builder: (raw) {
          final group = object(raw);
          final role = textOf(group['myRole']);
          final manage = role == 'owner' || role == 'admin';
          final members = objects(group['members']);
          return SingleChildScrollView(
            child: ReadingWidth(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    textOf(group['name']),
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 16),
                  Text(textOf(group['description'])),
                  if (manage)
                    TextButton(
                      onPressed: () async {
                        await showFields(
                          context,
                          '编辑群资料',
                          [
                            FieldSpec('name', '名称', initial: group['name']),
                            FieldSpec(
                              'description',
                              '介绍',
                              required: false,
                              lines: 3,
                              initial: group['description'],
                            ),
                          ],
                          onSubmit: (d) async {
                            await ref.read(apiProvider).patch(path, d);
                          },
                        );
                        if (mounted) setState(() => revision++);
                      },
                      child: const Text('编辑群资料'),
                    ),
                  SectionTitle(
                    '成员 · ${members.length}',
                    trailing: TextButton.icon(
                      onPressed: invite,
                      icon: const Icon(Icons.person_add_alt_rounded),
                      label: const Text('邀请'),
                    ),
                  ),
                  for (final m in members)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: MemberAvatar(Member(object(m['user']))),
                      title: Text(Member(object(m['user'])).name),
                      subtitle: Text(
                        const {
                              'owner': '群主',
                              'admin': '管理员',
                              'member': '成员',
                            }[textOf(m['role'])] ??
                            '成员',
                      ),
                      trailing: manage && m['role'] != 'owner'
                          ? PopupMenuButton<String>(
                              onSelected: (a) async {
                                final id = textOf(
                                  m['userId'] ?? object(m['user'])['id'],
                                );
                                if (a == 'remove') {
                                  if (!await confirm(context, '移除此成员？') ||
                                      !context.mounted)
                                    return;
                                  await perform(
                                    context,
                                    () => ref
                                        .read(apiProvider)
                                        .delete('$path/members/$id'),
                                  );
                                } else if (a == 'admin') {
                                  await perform(
                                    context,
                                    () => ref
                                        .read(apiProvider)
                                        .patch('$path/members/$id/role', {
                                          'role': m['role'] == 'admin'
                                              ? 'member'
                                              : 'admin',
                                        }),
                                  );
                                }
                                if (mounted) setState(() => revision++);
                              },
                              itemBuilder: (_) => [
                                if (role == 'owner')
                                  PopupMenuItem(
                                    value: 'admin',
                                    child: Text(
                                      m['role'] == 'admin' ? '取消管理员' : '设为管理员',
                                    ),
                                  ),
                                const PopupMenuItem(
                                  value: 'remove',
                                  child: Text('移除成员'),
                                ),
                              ],
                            )
                          : null,
                    ),
                  const SizedBox(height: 24),
                  TextButton(
                    onPressed: () async {
                      if (await confirm(
                            context,
                            role == 'owner' ? '解散群聊？' : '退出群聊？',
                          ) &&
                          context.mounted) {
                        final ok = await perform(context, () async {
                          if (role == 'owner')
                            await ref.read(apiProvider).delete(path);
                          else
                            await ref.read(apiProvider).post('$path/leave');
                          return true;
                        });
                        if (ok == true && context.mounted) context.pop();
                      }
                    },
                    child: Text(
                      role == 'owner' ? '解散群聊' : '退出群聊',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                  const SizedBox(height: 64),
                ],
              ),
            ),
          );
        },
      ),
    ),
  );
  Future<void> invite() async {
    final d = await showFields(
      context,
      '邀请成员',
      const [FieldSpec('userIds', '用户 ID（每行一个）', lines: 4)],
      submitLabel: '邀请',
      onSubmit: (d) async {
        final ids = textOf(
          d['userIds'],
        ).split(RegExp(r'[\s,]+')).where((e) => e.isNotEmpty).toList();
        await ref.read(apiProvider).post('$path/invites', {'userIds': ids});
      },
    );
    if (d != null && mounted) toast(context, '邀请已发送');
  }
}
