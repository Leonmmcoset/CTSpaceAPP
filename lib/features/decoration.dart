import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/app_state.dart';
import '../core/models.dart';
import '../ui/platform.dart';
import '../ui/widgets.dart';

List<Color> decorationColors(dynamic value, Color fallback) {
  final values = value is List
      ? value.map((e) => textOf(e)).toList()
      : RegExp(
          r'#[a-fA-F0-9]{6}\b',
        ).allMatches(textOf(value)).map((e) => e.group(0)!).toList();
  final colors = values
      .map((e) => int.tryParse(e.replaceFirst('#', ''), radix: 16))
      .whereType<int>()
      .map((e) => Color(0xff000000 | e))
      .toList();
  return colors.isEmpty
      ? [fallback, fallback]
      : colors.length == 1
      ? [colors.first, colors.first]
      : colors;
}

class ProfileBanner extends ConsumerWidget {
  const ProfileBanner({super.key, required this.user});
  final Member user;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(decorationProvider).valueOrNull ?? {};
    final refKey = textOf(user.raw['bannerRef']);
    final preset = objects(
      catalog['bannerPresets'],
    ).where((e) => e['key'] == refKey).firstOrNull;
    final custom =
        ['custom', 'shop'].contains(user.raw['bannerKind']) &&
        RegExp(r'^/uploads/banners/[\w-]+\.webp$').hasMatch(refKey);
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: SizedBox(
        height: 112,
        width: double.infinity,
        child: custom
            ? AppImage(refKey)
            : DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: decorationColors(
                      preset?['css'],
                      Theme.of(context).colorScheme.primaryContainer,
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

class DecorationPage extends ConsumerStatefulWidget {
  const DecorationPage({super.key});
  @override
  ConsumerState<DecorationPage> createState() => _DecorationPageState();
}

class _DecorationPageState extends ConsumerState<DecorationPage> {
  bool busy = false;
  Future<void> change(Future<void> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    await perform(context, () async {
      await action();
      await ref.read(appProvider).refreshUser();
      ref.invalidate(decorationProvider);
      return true;
    }, success: '已更新');
    if (mounted) setState(() => busy = false);
  }

  Widget presetTile(Json banner, double width) => SizedBox(
    width: width,
    height: 100,
    child: Material(
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: decorationColors(
              banner['css'],
              Theme.of(context).colorScheme.primaryContainer,
            ),
          ),
        ),
        child: InkWell(
          onTap: busy
              ? null
              : () => change(() async {
                  await ref.read(apiProvider).patch('/deco/banner', {
                    'kind': 'preset',
                    'ref': banner['key'],
                  });
                }),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Align(
              alignment: Alignment.bottomLeft,
              child: Text(
                textOf(banner['label']),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  shadows: [Shadow(blurRadius: 5, color: Colors.black)],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(decorationProvider);
    final scheme = Theme.of(context).colorScheme;
    return FeaturePage(
      title: '装扮主页',
      child: AuthGate(
        child: catalog.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) =>
              ErrorState(e, retry: () => ref.invalidate(decorationProvider)),
          data: (data) {
            final equipped = object(data['equipped']);
            final owned = objects(
              data['ownedFrames'],
            ).map((e) => textOf(e['ref'])).toSet();
            final custom = object(data['customBanner']);
            return SingleChildScrollView(
              child: ReadingWidth(
                width: 1000,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        MemberAvatar(
                          ref.watch(appProvider).user ?? Member({}),
                          radius: 32,
                        ),
                        const SizedBox(width: 20),
                        Text(
                          '${intOf(data['points'])} 积分',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () => context.push('/shop'),
                          child: const Text('去商城'),
                        ),
                      ],
                    ),
                    const SectionTitle('头像框'),
                    LayoutBuilder(
                      builder: (context, box) {
                        final width =
                            (box.maxWidth - 24) / (box.maxWidth < 500 ? 3 : 5);
                        return Wrap(
                          spacing: 6,
                          runSpacing: 12,
                          children: [
                            for (final frame in <Json>[
                              {'key': '', 'label': '无'},
                              ...objects(data['frames']),
                            ])
                              SizedBox(
                                width: width,
                                child: SurfaceCard(
                                  padding: const EdgeInsets.all(12),
                                  color: equipped['avatarFrame'] == frame['key']
                                      ? scheme.secondaryContainer
                                      : null,
                                  onTap: busy
                                      ? null
                                      : () {
                                          if (frame['tier'] == 'shop' &&
                                              !owned.contains(frame['key'])) {
                                            context.push('/shop');
                                            return;
                                          }
                                          change(() async {
                                            await ref.read(apiProvider).patch(
                                              '/deco/frame',
                                              {'frame': frame['key']},
                                            );
                                          });
                                        },
                                  child: Column(
                                    children: [
                                      Container(
                                        width: 54,
                                        height: 54,
                                        padding: const EdgeInsets.all(4),
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          gradient: SweepGradient(
                                            colors: decorationColors(
                                              frame['ring'],
                                              scheme.outlineVariant,
                                            ),
                                          ),
                                        ),
                                        child: CircleAvatar(
                                          backgroundColor: scheme.surface,
                                          child: Icon(
                                            frame['tier'] == 'shop' &&
                                                    !owned.contains(
                                                      frame['key'],
                                                    )
                                                ? Icons.lock_outline_rounded
                                                : Icons.person_outline_rounded,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                      Text(
                                        textOf(frame['label']),
                                        style: Theme.of(
                                          context,
                                        ).textTheme.labelMedium,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                    const SectionTitle('主页横幅'),
                    LayoutBuilder(
                      builder: (context, box) {
                        final width = (box.maxWidth - 12) / 2;
                        return Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            for (final banner in objects(data['bannerPresets']))
                              presetTile(banner, width),
                            for (final banner in objects(data['ownedBanners']))
                              SizedBox(
                                width: width,
                                height: 100,
                                child: GestureDetector(
                                  onTap: busy
                                      ? null
                                      : () => change(() async {
                                          await ref.read(apiProvider).patch(
                                            '/deco/banner',
                                            {
                                              'kind': 'shop',
                                              'ref': banner['ref'],
                                            },
                                          );
                                        }),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(20),
                                    child: AppImage(
                                      textOf(banner['url'] ?? banner['ref']),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                    const SectionTitle('自定义横幅'),
                    if (custom['active'] == true) ...[
                      Text(
                        '有效期至 ${textOf(custom['expiresAt']).split('T').first}',
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: busy
                            ? null
                            : () async {
                                final file = await pickFile(
                                  extensions: [
                                    'png',
                                    'jpg',
                                    'jpeg',
                                    'gif',
                                    'webp',
                                  ],
                                );
                                if (file == null || !mounted) return;
                                if ((await file.length() ?? 0) >
                                    intOf(custom['maxBytes'])) {
                                  if (context.mounted)
                                    toast(
                                      context,
                                      '图片不能超过 ${fileSize(custom['maxBytes'])}',
                                    );
                                  return;
                                }
                                if (!mounted) return;
                                await change(() async {
                                  await ref
                                      .read(apiProvider)
                                      .upload(file, path: '/deco/banner');
                                });
                              },
                        icon: const Icon(Icons.image_outlined),
                        label: const Text('上传横幅'),
                      ),
                    ],
                    FilledButton.tonal(
                      onPressed: busy
                          ? null
                          : () async {
                              if (!await confirm(
                                    context,
                                    '${custom['active'] == true ? '续费' : '开通'} ${intOf(custom['days'])} 天？',
                                    message: '消耗 ${intOf(custom['price'])} 积分',
                                  ) ||
                                  !mounted)
                                return;
                              await change(() async {
                                await ref
                                    .read(apiProvider)
                                    .post('/deco/banner/unlock');
                              });
                            },
                      child: Text(
                        '${custom['active'] == true ? '续费' : '开通'} · ${intOf(custom['price'])} 积分 / ${intOf(custom['days'])} 天',
                      ),
                    ),
                    if (busy)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: LinearProgressIndicator(),
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
  }
}
