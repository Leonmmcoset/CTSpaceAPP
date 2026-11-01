import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/app_state.dart';
import '../core/models.dart';
import '../ui/forms.dart';
import '../ui/platform.dart';
import '../ui/widgets.dart';

const origMarkSite = 'https://origmark.ctspace.xyz';
String certificateStatus(dynamic value) =>
    const {
      'certified': '已存证',
      'pending': '审核中',
      'rejected': '未通过',
      'revoked': '已撤销',
    }[value] ??
    '待确认';

class OrigMarkPage extends ConsumerStatefulWidget {
  const OrigMarkPage({super.key});
  @override
  ConsumerState<OrigMarkPage> createState() => _OrigMarkPageState();
}

class _OrigMarkPageState extends ConsumerState<OrigMarkPage> {
  Timer? debounce;
  String query = '';
  bool mine = false;
  @override
  void dispose() {
    debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final list = PagedList(
      cacheKey: '$mine:$query',
      load: (page) async => PageResult.fromJson(
        await ref
            .read(apiProvider)
            .get(
              mine ? '/origmark/me/registrations' : '/origmark/registrations',
              mine ? null : {'q': query, 'page': page, 'pageSize': 20},
            ),
        (e) => e,
        page: page,
        pageSize: 20,
      ),
      itemBuilder: (row, i) => Entrance(
        index: i,
        child: SurfaceCard(
          onTap: () => context.push('/origmark/registration/${row['id']}'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.verified_outlined,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      textOf(row['certNumber']),
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ),
                  Text(
                    certificateStatus(row['status']),
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                textOf(row['title']),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  MemberAvatar(Member(object(row['author'])), radius: 14),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      Member(object(row['author'])).name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    relativeTime(row['certifiedAt'] ?? row['createdAt']),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    return FeaturePage(
      title: '原创存证',
      actions: [
        IconButton(
          tooltip: '验证证书',
          onPressed: () => context.push('/origmark/verify'),
          icon: const Icon(Icons.fact_check_outlined),
        ),
        IconButton(
          tooltip: '审批申请',
          onPressed: () => context.push('/origmark/requests'),
          icon: const Icon(Icons.task_alt_rounded),
        ),
      ],
      fab: FloatingActionButton.extended(
        onPressed: () => openLink(context, origMarkSite, external: true),
        icon: const Icon(Icons.add_rounded),
        label: const Text('登记作品'),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: SearchBar(
              hintText: '搜索作品或证书',
              leading: const Icon(Icons.search_rounded),
              onChanged: (v) {
                debounce?.cancel();
                debounce = Timer(const Duration(milliseconds: 400), () {
                  if (mounted) setState(() => query = v.trim());
                });
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('全部作品')),
                ButtonSegment(value: true, label: Text('我的存证')),
              ],
              selected: {mine},
              onSelectionChanged: (v) => setState(() => mine = v.first),
            ),
          ),
          Expanded(child: mine ? AuthGate(child: list) : list),
        ],
      ),
    );
  }
}

class OrigMarkDetailPage extends ConsumerStatefulWidget {
  const OrigMarkDetailPage({super.key, required this.id});
  final String id;
  @override
  ConsumerState<OrigMarkDetailPage> createState() => _OrigMarkDetailPageState();
}

class _OrigMarkDetailPageState extends ConsumerState<OrigMarkDetailPage> {
  int revision = 0;
  @override
  Widget build(BuildContext context) => FeaturePage(
    title: '存证详情',
    child: AsyncPanel<dynamic>(
      cacheKey: revision,
      load: () =>
          ref.read(apiProvider).get('/origmark/registrations/${widget.id}'),
      builder: (data) {
        final row = object(data), author = Member(object(data['author']));
        final cert = textOf(row['certNumber']);
        final own = author.id == ref.watch(appProvider).user?.id;
        return SingleChildScrollView(
          child: ReadingWidth(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SurfaceCard(
                  color: Theme.of(context).colorScheme.tertiaryContainer,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.verified_rounded, size: 42),
                      const SizedBox(height: 24),
                      Text(
                        textOf(row['title']),
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 12),
                      SelectableText(cert),
                      const SizedBox(height: 8),
                      Text(
                        '${certificateStatus(row['status'])} · 版本 ${intOf(row['version'])}',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    MemberAvatar(author),
                    const SizedBox(width: 12),
                    Expanded(child: Text(author.name)),
                    Text(relativeTime(row['certifiedAt'] ?? row['createdAt'])),
                  ],
                ),
                if (textOf(row['summary']).isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Text(textOf(row['summary'])),
                  ),
                const SizedBox(height: 24),
                Wrap(
                  spacing: 10,
                  runSpacing: 12,
                  children: [
                    FilledButton.icon(
                      onPressed: () => context.push(
                        '/origmark/verify?cert=${Uri.encodeComponent(cert)}',
                      ),
                      icon: const Icon(Icons.fact_check_outlined),
                      label: const Text('验证证书'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () =>
                          copyText(context, '$origMarkSite/verify/$cert'),
                      icon: const Icon(Icons.link_rounded),
                      label: const Text('分享'),
                    ),
                    if (row['forumProjectId'] != null)
                      OutlinedButton.icon(
                        onPressed: () =>
                            context.push('/project/${row['forumProjectId']}'),
                        icon: const Icon(Icons.widgets_outlined),
                        label: const Text('论坛作品'),
                      ),
                    if (boolOf(row['allowPreview']))
                      OutlinedButton.icon(
                        onPressed: () => openLink(
                          context,
                          '$origMarkSite/verify/$cert',
                          external: true,
                        ),
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: const Text('预览'),
                      ),
                    if (!own)
                      OutlinedButton.icon(
                        onPressed: () async {
                          if (!await requireSignIn(context, ref) ||
                              !context.mounted)
                            return;
                          await perform(context, () async {
                            await ref
                                .read(apiProvider)
                                .post(
                                  '/origmark/registrations/${widget.id}/download-request',
                                );
                            return true;
                          }, success: '已申请，等待作者审批');
                        },
                        icon: const Icon(Icons.send_outlined),
                        label: const Text('申请下载'),
                      ),
                    OutlinedButton.icon(
                      onPressed: () async {
                        if (!await requireSignIn(context, ref) ||
                            !context.mounted)
                          return;
                        await saveRemote(
                          context,
                          ref.read(apiProvider),
                          '/api/origmark/raw/$cert?download=1',
                          '${textOf(row['title'], '作品')}.sb3',
                        );
                      },
                      icon: const Icon(Icons.download_rounded),
                      label: const Text('下载原文件'),
                    ),
                  ],
                ),
                const SectionTitle('作品指纹'),
                for (final e in object(row['fingerprint']).entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          const {
                                'contentHash': '内容哈希',
                                'structureHash': '结构哈希',
                                'assetCount': '素材数',
                              }[e.key] ??
                              e.key,
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                        const SizedBox(height: 6),
                        SelectableText(
                          textOf(e.value),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                if (own)
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('允许预览'),
                    value: boolOf(row['allowPreview']),
                    onChanged: (v) async {
                      final ok = await perform(context, () async {
                        await ref.read(apiProvider).patch(
                          '/origmark/me/registrations/${widget.id}/preview',
                          {'allowPreview': v},
                        );
                        return true;
                      });
                      if (ok == true && mounted) setState(() => revision++);
                    },
                  ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () async {
                    if (!await requireSignIn(context, ref) || !context.mounted)
                      return;
                    await showFields(
                      context,
                      '举报侵权',
                      const [FieldSpec('reason', '原因', lines: 4)],
                      submitLabel: '提交',
                      onSubmit: (d) async {
                        await ref
                            .read(apiProvider)
                            .post(
                              '/origmark/registrations/${widget.id}/report',
                              d,
                            );
                      },
                    );
                  },
                  child: const Text('举报侵权'),
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

class CertificatePage extends ConsumerStatefulWidget {
  const CertificatePage({super.key, this.initial = ''});
  final String initial;
  @override
  ConsumerState<CertificatePage> createState() => _CertificatePageState();
}

class _CertificatePageState extends ConsumerState<CertificatePage> {
  late final input = TextEditingController(text: widget.initial);
  late String cert = widget.initial;
  int revision = 0;
  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FeaturePage(
    title: '验证证书',
    child: SingleChildScrollView(
      child: ReadingWidth(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: input,
              decoration: const InputDecoration(
                labelText: '证书编号',
                hintText: 'OM-…',
                prefixIcon: Icon(Icons.verified_outlined),
              ),
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => verify(),
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: verify, child: const Text('验证')),
            const SizedBox(height: 24),
            if (cert.isNotEmpty)
              AsyncPanel<dynamic>(
                cacheKey: '$cert:$revision',
                load: () => ref
                    .read(apiProvider)
                    .get('/origmark/verify/${Uri.encodeComponent(cert)}'),
                builder: (data) {
                  final d = object(data), verified = d['verified'] == true;
                  return SurfaceCard(
                    color: verified
                        ? Theme.of(context).colorScheme.primaryContainer
                        : Theme.of(context).colorScheme.errorContainer,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          verified
                              ? Icons.verified_rounded
                              : Icons.gpp_bad_outlined,
                          size: 44,
                        ),
                        const SizedBox(height: 20),
                        Text(
                          verified ? '签名有效' : '验证未通过',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          textOf(d['title']),
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${Member(object(d['author'])).name} · ${certificateStatus(d['status'])}',
                        ),
                        const SizedBox(height: 20),
                        SelectableText(textOf(d['certNumber'])),
                        if (d['signature'] != null)
                          ExpansionTile(
                            tilePadding: EdgeInsets.zero,
                            title: const Text('签名与公钥'),
                            children: [
                              SelectableText(
                                textOf(d['signature']),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              const SizedBox(height: 16),
                              SelectableText(
                                textOf(d['publicKey']),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              TextButton(
                                onPressed: () =>
                                    copyText(context, textOf(d['publicKey'])),
                                child: const Text('复制公钥'),
                              ),
                            ],
                          ),
                      ],
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    ),
  );
  void verify() => setState(() {
    cert = input.text.trim();
    revision++;
  });
}

class OrigMarkRequestsPage extends ConsumerStatefulWidget {
  const OrigMarkRequestsPage({super.key});
  @override
  ConsumerState<OrigMarkRequestsPage> createState() =>
      _OrigMarkRequestsPageState();
}

class _OrigMarkRequestsPageState extends ConsumerState<OrigMarkRequestsPage> {
  String type = 'download';
  int revision = 0;
  @override
  Widget build(BuildContext context) => FeaturePage(
    title: '审批申请',
    child: AuthGate(
      child: Column(
        children: [
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'download', label: Text('下载申请')),
              ButtonSegment(value: 'sync', label: Text('同步申请')),
            ],
            selected: {type},
            onSelectionChanged: (v) => setState(() => type = v.first),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: AsyncPanel<dynamic>(
              cacheKey: '$type:$revision',
              load: () =>
                  ref.read(apiProvider).get('/origmark/me/$type-requests'),
              builder: (d) {
                final rows = objects(d is List ? d : object(d)['items']);
                if (rows.isEmpty)
                  return const EmptyState(
                    title: '暂无申请',
                    icon: Icons.task_alt_rounded,
                  );
                return ListView.separated(
                  padding: const EdgeInsets.all(24),
                  itemCount: rows.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, i) {
                    final row = rows[i],
                        member = Member(
                          object(rows[i]['requester'] ?? rows[i]['user']),
                        );
                    return SurfaceCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            textOf(
                              object(row['registration'])['title'],
                              '作品申请',
                            ),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 12),
                          Text(member.name),
                          const SizedBox(height: 12),
                          if (row['status'] == null ||
                              row['status'] == 'pending')
                            Wrap(
                              spacing: 8,
                              children: [
                                TextButton(
                                  onPressed: () => respond(row, false),
                                  child: const Text('拒绝'),
                                ),
                                FilledButton.tonal(
                                  onPressed: () => respond(row, true),
                                  child: const Text('批准'),
                                ),
                              ],
                            )
                          else
                            Text(row['status'] == 'approved' ? '已批准' : '已拒绝'),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
  Future<void> respond(Json row, bool accept) async {
    if (!await confirm(context, accept ? '批准此申请？' : '拒绝此申请？') || !mounted)
      return;
    final ok = await perform(context, () async {
      await ref
          .read(apiProvider)
          .post(
            '/origmark/me/$type-requests/${row['id']}/${accept ? 'approve' : 'reject'}',
          );
      return true;
    });
    if (ok == true && mounted) setState(() => revision++);
  }
}
