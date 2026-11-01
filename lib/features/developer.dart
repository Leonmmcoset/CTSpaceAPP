import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/api.dart';
import '../core/app_state.dart';
import '../core/models.dart';
import '../ui/forms.dart';
import '../ui/platform.dart';
import '../ui/widgets.dart';

Future<void> showSecret(
  BuildContext context,
  String secret, {
  String title = '接入密钥',
}) async {
  if (secret.isEmpty) return;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('请保存，此密钥仅显示一次'),
            const SizedBox(height: 16),
            SelectableText(
              secret,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => copyText(dialogContext, secret),
          child: const Text('复制'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('完成'),
        ),
      ],
    ),
  );
}

class DeveloperPage extends ConsumerWidget {
  const DeveloperPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => FeaturePage(
    title: '开发者工具',
    child: AuthGate(
      child: SingleChildScrollView(
        child: ReadingWidth(
          child: Column(
            children: [
              SurfaceCard(
                color: Theme.of(context).colorScheme.primaryContainer,
                onTap: () => context.push('/api-keys'),
                child: const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.key_rounded, size: 32),
                  title: Text('API 密钥'),
                  trailing: Icon(Icons.arrow_forward_rounded),
                ),
              ),
              const SizedBox(height: 16),
              SurfaceCard(
                color: Theme.of(context).colorScheme.tertiaryContainer,
                onTap: () => context.push('/cloud'),
                child: const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.cloud_sync_outlined, size: 32),
                  title: Text('云变量'),
                  trailing: Icon(Icons.arrow_forward_rounded),
                ),
              ),
              const SizedBox(height: 24),
              ListTile(
                leading: const Icon(Icons.menu_book_outlined),
                title: const Text('接口文档'),
                trailing: const Icon(Icons.open_in_new_rounded),
                onTap: () =>
                    openLink(context, absoluteUrl('/docs'), external: true),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class ApiKeysPage extends ConsumerStatefulWidget {
  const ApiKeysPage({super.key});
  @override
  ConsumerState<ApiKeysPage> createState() => _ApiKeysPageState();
}

class _ApiKeysPageState extends ConsumerState<ApiKeysPage> {
  int revision = 0;
  @override
  Widget build(BuildContext context) => FeaturePage(
    title: 'API 密钥',
    fab: FloatingActionButton.extended(
      onPressed: () async {
        String? secret;
        final d = await showFields(
          context,
          '创建密钥',
          const [FieldSpec('name', '密钥名称')],
          submitLabel: '创建',
          onSubmit: (d) async {
            final result = object(
              await ref.read(apiProvider).post('/api-keys', d),
            );
            secret = textOf(result['key']);
          },
        );
        if (d != null && context.mounted) {
          setState(() => revision++);
          await showSecret(context, secret ?? '', title: 'API 密钥');
        }
      },
      icon: const Icon(Icons.add_rounded),
      label: const Text('创建密钥'),
    ),
    child: AuthGate(
      child: AsyncPanel<dynamic>(
        cacheKey: revision,
        load: () => ref.read(apiProvider).get('/api-keys'),
        builder: (d) {
          final rows = objects(d is List ? d : object(d)['items']);
          return rows.isEmpty
              ? const EmptyState(title: '还没有 API 密钥', icon: Icons.key_rounded)
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 110),
                  itemCount: rows.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, i) {
                    final key = rows[i];
                    return SurfaceCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.key_rounded),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  textOf(key['name'], 'API 密钥'),
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                              ),
                              IconButton(
                                tooltip: '撤销密钥',
                                onPressed: () async {
                                  if (await confirm(
                                        context,
                                        '撤销此密钥？',
                                        message: '使用该密钥的应用将无法继续访问',
                                      ) &&
                                      context.mounted) {
                                    await perform(
                                      context,
                                      () => ref
                                          .read(apiProvider)
                                          .delete('/api-keys/${key['id']}'),
                                    );
                                    if (mounted) setState(() => revision++);
                                  }
                                },
                                icon: const Icon(Icons.delete_outline_rounded),
                              ),
                            ],
                          ),
                          Text(
                            textOf(key['prefix'] ?? key['keyPrefix']),
                            style: const TextStyle(fontFamily: 'monospace'),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '创建于 ${relativeTime(key['createdAt'])}',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                          if (key['scopes'] is List)
                            Wrap(
                              spacing: 6,
                              children: (key['scopes'] as List)
                                  .map((e) => Chip(label: Text('$e')))
                                  .toList(),
                            ),
                          TextButton(
                            onPressed: () => openLink(
                              context,
                              absoluteUrl('/developer'),
                              external: true,
                            ),
                            child: const Text('权限管理'),
                          ),
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

class CloudProjectsPage extends ConsumerStatefulWidget {
  const CloudProjectsPage({super.key});
  @override
  ConsumerState<CloudProjectsPage> createState() => _CloudProjectsPageState();
}

class _CloudProjectsPageState extends ConsumerState<CloudProjectsPage> {
  int revision = 0;
  @override
  Widget build(BuildContext context) => FeaturePage(
    title: '云变量',
    fab: FloatingActionButton.extended(
      onPressed: () async {
        Json result = {};
        final d = await showFields(
          context,
          '新建云变量项目',
          const [FieldSpec('name', '项目名称')],
          submitLabel: '创建',
          onSubmit: (d) async {
            result = object(
              await ref.read(apiProvider).post('/cloud/projects', d),
            );
          },
        );
        if (d != null && context.mounted) {
          setState(() => revision++);
          await showSecret(context, textOf(result['accessToken']));
        }
      },
      icon: const Icon(Icons.add_rounded),
      label: const Text('新建项目'),
    ),
    child: AuthGate(
      child: AsyncPanel<dynamic>(
        cacheKey: revision,
        load: () => ref.read(apiProvider).get('/cloud/projects'),
        builder: (d) {
          final rows = objects(d is List ? d : object(d)['items']);
          return rows.isEmpty
              ? const EmptyState(title: '还没有云变量项目', icon: Icons.cloud_outlined)
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 110),
                  itemCount: rows.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, i) {
                    final p = rows[i];
                    return SurfaceCard(
                      onTap: () async {
                        await context.push(
                          '/cloud/${p['projectId'] ?? p['id']}',
                        );
                        if (mounted) setState(() => revision++);
                      },
                      child: Row(
                        children: [
                          const Icon(Icons.cloud_sync_outlined, size: 32),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  textOf(p['name']),
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  '${intOf(p['variablesCount'])} 个变量 · ${intOf(p['connections'])} 个连接',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right_rounded),
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

class CloudProjectPage extends ConsumerStatefulWidget {
  const CloudProjectPage({super.key, required this.id});
  final String id;
  @override
  ConsumerState<CloudProjectPage> createState() => _CloudProjectPageState();
}

class _CloudProjectPageState extends ConsumerState<CloudProjectPage> {
  int revision = 0;
  bool dev = false;
  String? token;
  String get prefix => '/cloud/projects/${widget.id}';
  String get environment => dev ? '/dev' : '';
  Future<dynamic> read(String suffix) => ref
      .read(apiProvider)
      .request(
        'GET',
        '$prefix$environment/$suffix',
        headers: dev ? {'x-cloud-token': token} : null,
      );
  Future<dynamic> write(String suffix, Json body) => ref
      .read(apiProvider)
      .request(
        'POST',
        '$prefix$environment/$suffix',
        data: body,
        headers: dev ? {'x-cloud-token': token} : null,
      );
  Future<void> variable({String? name, dynamic value}) async {
    await showFields(
      context,
      name == null ? '新增变量' : '修改变量',
      [
        FieldSpec('name', '变量名', initial: name),
        FieldSpec('value', '变量值', required: false, lines: 3, initial: value),
      ],
      onSubmit: (d) async {
        await write('variables', d);
      },
    );
    if (mounted) setState(() => revision++);
  }

  @override
  Widget build(BuildContext context) => FeaturePage(
    title: '云变量项目',
    actions: [
      IconButton(
        tooltip: '刷新',
        onPressed: () => setState(() => revision++),
        icon: const Icon(Icons.refresh_rounded),
      ),
    ],
    child: AuthGate(
      child: AsyncPanel<Json>(
        cacheKey: revision,
        load: () async => object(await ref.read(apiProvider).get(prefix)),
        builder: (project) {
          token = textOf(project['accessToken'], token ?? '');
          return SingleChildScrollView(
            child: ReadingWidth(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    textOf(project['name']),
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    textOf(project['projectId'], widget.id),
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  const SizedBox(height: 24),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => copyText(
                          context,
                          textOf(project['wsHost'], 'wss://vable.ctspace.xyz'),
                        ),
                        icon: const Icon(Icons.link_rounded),
                        label: const Text('复制服务器地址'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => copyText(context, widget.id),
                        icon: const Icon(Icons.copy_rounded),
                        label: const Text('复制项目 ID'),
                      ),
                      TextButton(
                        onPressed: () async {
                          if (await confirm(
                                context,
                                '轮换接入密钥？',
                                message: '旧密钥将立即失效',
                              ) &&
                              context.mounted) {
                            final d = await perform(
                              context,
                              () => ref
                                  .read(apiProvider)
                                  .post('$prefix/token/regenerate'),
                            );
                            if (d != null && context.mounted) {
                              await showSecret(
                                context,
                                textOf(object(d)['accessToken']),
                              );
                              if (mounted) setState(() => revision++);
                            }
                          }
                        },
                        child: const Text('轮换密钥'),
                      ),
                    ],
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('允许匿名读取'),
                    value: project['allowAnonymousRead'] == true,
                    onChanged: (v) async {
                      await perform(
                        context,
                        () => ref.read(apiProvider).patch(prefix, {
                          'allowAnonymousRead': v,
                        }),
                      );
                      if (mounted) setState(() => revision++);
                    },
                  ),
                  OutlinedButton(
                    onPressed: () async {
                      await showFields(
                        context,
                        '项目设置',
                        [
                          FieldSpec('name', '名称', initial: project['name']),
                          FieldSpec(
                            'webhookUrl',
                            'Webhook URL',
                            initial: project['webhookUrl'],
                            required: false,
                          ),
                        ],
                        onSubmit: (d) async {
                          await ref.read(apiProvider).patch(prefix, d);
                        },
                      );
                      if (mounted) setState(() => revision++);
                    },
                    child: const Text('项目设置'),
                  ),
                  const SizedBox(height: 24),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('生产环境')),
                      ButtonSegment(value: true, label: Text('开发环境')),
                    ],
                    selected: {dev},
                    onSelectionChanged: (v) => setState(() => dev = v.first),
                  ),
                  SectionTitle(
                    '变量',
                    trailing: TextButton.icon(
                      onPressed: () => variable(),
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('新增'),
                    ),
                  ),
                  AsyncPanel<dynamic>(
                    cacheKey: '$revision-$dev',
                    load: () => read('variables'),
                    builder: (d) {
                      final variables = object(object(d)['variables']);
                      return variables.isEmpty
                          ? const Padding(
                              padding: EdgeInsets.all(24),
                              child: Text('还没有变量'),
                            )
                          : Column(
                              children: variables.entries
                                  .map(
                                    (e) => Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: SurfaceCard(
                                        onTap: () => variable(
                                          name: e.key,
                                          value: e.value,
                                        ),
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                e.key,
                                                style: Theme.of(
                                                  context,
                                                ).textTheme.titleSmall,
                                              ),
                                            ),
                                            const SizedBox(width: 16),
                                            Flexible(
                                              child: Text(
                                                textOf(e.value),
                                                maxLines: 3,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            const Icon(
                                              Icons.edit_outlined,
                                              size: 18,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  )
                                  .toList(),
                            );
                    },
                  ),
                  const SectionTitle('变量历史'),
                  AsyncPanel<dynamic>(
                    cacheKey: '$revision-$dev',
                    load: () => read('history'),
                    builder: (d) {
                      final rows = objects(object(d)['history'] ?? d);
                      return Column(
                        children: rows.reversed
                            .take(50)
                            .map(
                              (e) => ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(
                                  '${textOf(e['name'])} → ${textOf(e['value'])}',
                                ),
                                subtitle: Text(
                                  '${relativeTime(e['ts'] ?? e['createdAt'])} · ${textOf(e['source'])}',
                                ),
                              ),
                            )
                            .toList(),
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                  Wrap(
                    spacing: 12,
                    children: [
                      OutlinedButton(
                        onPressed: () async {
                          if (await confirm(
                                context,
                                '重置${dev ? '开发' : '生产'}环境的全部变量？',
                              ) &&
                              context.mounted) {
                            await perform(context, () => write('reset', {}));
                            if (mounted) setState(() => revision++);
                          }
                        },
                        child: const Text('重置变量'),
                      ),
                      TextButton(
                        onPressed: () async {
                          if (await confirm(context, '删除云变量项目？') &&
                              context.mounted) {
                            final ok = await perform(context, () async {
                              await ref.read(apiProvider).delete(prefix);
                              return true;
                            });
                            if (ok == true && context.mounted) context.pop();
                          }
                        },
                        child: Text(
                          '删除项目',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 80),
                ],
              ),
            ),
          );
        },
      ),
    ),
  );
}
