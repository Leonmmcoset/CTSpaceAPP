import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/app_state.dart';
import '../core/models.dart';
import '../ui/forms.dart';
import '../ui/widgets.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appProvider);
    return FeaturePage(
      title: '设置',
      child: SingleChildScrollView(
        child: ReadingWidth(
          width: 720,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionTitle('外观'),
              SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment(
                    value: ThemeMode.system,
                    icon: Icon(Icons.brightness_auto_outlined),
                    label: Text('系统'),
                  ),
                  ButtonSegment(
                    value: ThemeMode.light,
                    icon: Icon(Icons.light_mode_outlined),
                    label: Text('浅色'),
                  ),
                  ButtonSegment(
                    value: ThemeMode.dark,
                    icon: Icon(Icons.dark_mode_outlined),
                    label: Text('深色'),
                  ),
                ],
                selected: {app.themeMode},
                onSelectionChanged: (v) => app.setTheme(v.first),
              ),
              const SizedBox(height: 20),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('系统动态取色'),
                value: app.dynamicColor,
                onChanged: app.setDynamicColor,
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 16,
                runSpacing: 16,
                children:
                    const [
                          Color(0xff7056e8),
                          Color(0xff008577),
                          Color(0xffcc5a24),
                          Color(0xff3975d3),
                          Color(0xffb94483),
                          Color(0xff657537),
                        ]
                        .map(
                          (color) => Semantics(
                            label: '主题颜色',
                            selected: app.seed == color,
                            button: true,
                            child: InkWell(
                              onTap: () => app.setSeed(color),
                              borderRadius: BorderRadius.circular(32),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 250),
                                width: 52,
                                height: 52,
                                decoration: BoxDecoration(
                                  color: color,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    width: app.seed == color ? 4 : 0,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurface,
                                  ),
                                ),
                                child: app.seed == color
                                    ? const Icon(
                                        Icons.check_rounded,
                                        color: Colors.white,
                                      )
                                    : null,
                              ),
                            ),
                          ),
                        )
                        .toList(),
              ),
              const SizedBox(height: 24),
              const SectionTitle('社区与应用'),
              for (final e in const {
                'privacyPolicy': '隐私政策',
                'serviceTerms': '服务条款',
                'communityGuidelines': '社区公约',
              }.entries)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(e.value),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push('/policy/${e.key}'),
                ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('更新日志'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push('/changelogs'),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('开源许可'),
                subtitle: const Text('Apache License 2.0'),
                trailing: const Icon(Icons.open_in_new_rounded),
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: '创客次元',
                  applicationVersion: '0.1.0',
                  applicationLegalese: 'Apache License 2.0',
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('清理临时文件'),
                trailing: const Icon(Icons.cleaning_services_outlined),
                onTap: () async {
                  PaintingBinding.instance.imageCache.clear();
                  PaintingBinding.instance.imageCache.clearLiveImages();
                  toast(context, '图片缓存已清理');
                },
              ),
              const SizedBox(height: 32),
              Text(
                '创客次元  0.1.0',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelMedium,
              ),
              const SizedBox(height: 48),
            ],
          ),
        ),
      ),
    );
  }
}

class SecurityPage extends ConsumerStatefulWidget {
  const SecurityPage({super.key});
  @override
  ConsumerState<SecurityPage> createState() => _SecurityPageState();
}

class _SecurityPageState extends ConsumerState<SecurityPage> {
  int revision = 0;
  Future<void> form(String title, String path, List<FieldSpec> fields) async {
    await showFields(
      context,
      title,
      fields,
      onSubmit: (data) async {
        await ref.read(apiProvider).post(path, data);
      },
    );
  }

  @override
  Widget build(BuildContext context) => FeaturePage(
    title: '账号与安全',
    child: AuthGate(
      child: SingleChildScrollView(
        child: ReadingWidth(
          width: 720,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ListTile(
                leading: const Icon(Icons.password_rounded),
                title: const Text('修改密码'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => form('修改密码', '/auth/change-password', const [
                  FieldSpec('oldPassword', '当前密码', secret: true),
                  FieldSpec('newPassword', '新密码', secret: true, minLength: 6),
                ]),
              ),
              ListTile(
                leading: const Icon(Icons.alternate_email_rounded),
                title: const Text('修改邮箱'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => form('修改邮箱', '/auth/change-email', const [
                  FieldSpec('password', '当前密码', secret: true),
                  FieldSpec('newEmail', '新邮箱'),
                ]),
              ),
              ListTile(
                leading: const Icon(Icons.person_outline_rounded),
                title: const Text('修改用户名'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => form('修改用户名', '/auth/change-username', const [
                  FieldSpec('password', '当前密码', secret: true),
                  FieldSpec('newUsername', '新用户名', minLength: 2),
                ]),
              ),
              const SectionTitle('安全问题'),
              AsyncPanel<dynamic>(
                cacheKey: revision,
                load: () =>
                    ref.read(apiProvider).get('/auth/security-question'),
                builder: (d) {
                  final data = object(d);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (data['enabled'] == true)
                        Text(textOf(data['question'])),
                      Wrap(
                        spacing: 12,
                        children: [
                          OutlinedButton(
                            onPressed: () async {
                              await form(
                                '设置安全问题',
                                '/auth/security-question',
                                const [
                                  FieldSpec('password', '当前密码', secret: true),
                                  FieldSpec('question', '问题', minLength: 4),
                                  FieldSpec(
                                    'answer',
                                    '答案',
                                    secret: true,
                                    minLength: 2,
                                  ),
                                ],
                              );
                              if (mounted) setState(() => revision++);
                            },
                            child: const Text('设置问题'),
                          ),
                          if (data['enabled'] == true)
                            TextButton(
                              onPressed: () async {
                                await form(
                                  '关闭安全问题',
                                  '/auth/security-question/clear',
                                  const [
                                    FieldSpec('password', '当前密码', secret: true),
                                  ],
                                );
                                if (mounted) setState(() => revision++);
                              },
                              child: const Text('关闭'),
                            ),
                        ],
                      ),
                    ],
                  );
                },
              ),
              SectionTitle(
                '登录设备',
                trailing: TextButton(
                  onPressed: () async {
                    if (await confirm(context, '退出其他设备？') && context.mounted) {
                      await perform(
                        context,
                        () => ref
                            .read(apiProvider)
                            .post('/auth/sessions/revoke-others'),
                      );
                      if (mounted) setState(() => revision++);
                    }
                  },
                  child: const Text('退出其他设备'),
                ),
              ),
              AsyncPanel<dynamic>(
                cacheKey: revision,
                load: () => ref.read(apiProvider).get('/auth/sessions'),
                builder: (d) {
                  final rows = objects(
                    d is List ? d : object(d)['items'] ?? object(d)['sessions'],
                  );
                  return Column(
                    children: rows
                        .map(
                          (session) => ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.devices_rounded),
                            title: Text(
                              textOf(
                                session['deviceName'] ?? session['userAgent'],
                                '设备',
                              ),
                            ),
                            subtitle: Text(
                              '${textOf(session['ip'])}\n${relativeTime(session['lastSeenAt'] ?? session['createdAt'])}',
                            ),
                            trailing: session['isCurrent'] == true
                                ? const Chip(label: Text('当前设备'))
                                : IconButton(
                                    tooltip: '退出此设备',
                                    icon: const Icon(Icons.logout_rounded),
                                    onPressed: () async {
                                      if (await confirm(context, '退出此设备？') &&
                                          context.mounted) {
                                        await perform(
                                          context,
                                          () => ref
                                              .read(apiProvider)
                                              .post(
                                                '/auth/sessions/${session['id']}/revoke',
                                              ),
                                        );
                                        if (mounted) setState(() => revision++);
                                      }
                                    },
                                  ),
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
      ),
    ),
  );
}

class ChangelogsPage extends ConsumerWidget {
  const ChangelogsPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => FeaturePage(
    title: '更新日志',
    child: AsyncPanel<dynamic>(
      load: () => ref.read(apiProvider).get('/changelogs'),
      builder: (d) {
        final rows = objects(d is List ? d : object(d)['items']);
        return ListView.separated(
          padding: const EdgeInsets.all(24),
          itemCount: rows.length,
          separatorBuilder: (_, _) => const SizedBox(height: 16),
          itemBuilder: (context, i) => SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  textOf(rows[i]['title'] ?? rows[i]['version']),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  relativeTime(rows[i]['createdAt']),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                const SizedBox(height: 16),
                MarkdownContent(textOf(rows[i]['content'])),
              ],
            ),
          ),
        );
      },
    ),
  );
}
