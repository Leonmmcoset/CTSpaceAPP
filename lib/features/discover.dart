import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/app_state.dart';
import '../core/models.dart';
import '../ui/widgets.dart';
import '../core/api.dart';
import '../ui/platform.dart';

class DiscoverPage extends ConsumerWidget {
  const DiscoverPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return FeaturePage(
      title: '发现',
      actions: [
        IconButton(
          tooltip: '搜索',
          onPressed: () => context.push('/search'),
          icon: const Icon(Icons.search_rounded),
        ),
      ],
      child: SingleChildScrollView(
        child: ReadingWidth(
          width: 1100,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LayoutBuilder(
                builder: (context, box) {
                  final columns = box.maxWidth < 520 ? 2 : 3;
                  final width = (box.maxWidth - 16 * (columns - 1)) / columns;
                  return Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: [
                      for (final entry in <(String, IconData, String, Color)>[
                        (
                          '商城',
                          Icons.shopping_bag_outlined,
                          '/shop',
                          scheme.primaryContainer,
                        ),
                        (
                          '原创存证',
                          Icons.verified_outlined,
                          '/origmark',
                          scheme.tertiaryContainer,
                        ),
                        (
                          '直播',
                          Icons.live_tv_rounded,
                          '/live',
                          scheme.secondaryContainer,
                        ),
                        (
                          '云盘',
                          Icons.cloud_outlined,
                          '/drive',
                          scheme.secondaryContainer,
                        ),
                        (
                          '开发者工具',
                          Icons.terminal_rounded,
                          '/developer',
                          scheme.primaryContainer,
                        ),
                        (
                          '排行榜',
                          Icons.leaderboard_outlined,
                          '/leaderboard',
                          scheme.tertiaryContainer,
                        ),
                      ])
                        SizedBox(
                          width: width,
                          child: Entrance(
                            child: SurfaceCard(
                              color: entry.$4,
                              onTap: () => context.push(entry.$3),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(entry.$2, size: 32),
                                  const SizedBox(height: 32),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          entry.$1,
                                          style: Theme.of(
                                            context,
                                          ).textTheme.titleMedium,
                                        ),
                                      ),
                                      const Icon(
                                        Icons.arrow_outward_rounded,
                                        size: 20,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
              const SectionTitle('社区动态'),
              AsyncPanel<dynamic>(
                load: () => ref.read(apiProvider).get('/stats/public'),
                builder: (d) {
                  final data = object(d);
                  return SurfaceCard(
                    child: Wrap(
                      spacing: 32,
                      runSpacing: 20,
                      children: [
                        for (final e in const {
                          'users': '创作者',
                          'discussions': '讨论',
                          'posts': '回复',
                          'todayVisits': '今日访问',
                        }.entries)
                          SizedBox(
                            width: 120,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  compactNumber(data[e.key]),
                                  style: Theme.of(
                                    context,
                                  ).textTheme.headlineMedium,
                                ),
                                Text(
                                  e.value,
                                  style: Theme.of(
                                    context,
                                  ).textTheme.labelMedium,
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
              const SectionTitle('更多'),
              for (final e in <(String, IconData, VoidCallback)>[
                (
                  '财务公开',
                  Icons.receipt_long_outlined,
                  () => context.push('/finance'),
                ),
                (
                  '客服',
                  Icons.support_agent_rounded,
                  () => openLink(context, absoluteUrl('/chat'), external: true),
                ),
                (
                  '素材库',
                  Icons.perm_media_outlined,
                  () => context.push('/assets'),
                ),
                (
                  '小游戏',
                  Icons.sports_esports_outlined,
                  () => context.push('/games'),
                ),
                (
                  '更新日志',
                  Icons.history_rounded,
                  () => context.push('/changelogs'),
                ),
                (
                  '社区公约',
                  Icons.menu_book_outlined,
                  () => context.push('/policy/communityGuidelines'),
                ),
              ])
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  leading: Icon(e.$2),
                  title: Text(e.$1),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: e.$3,
                ),
              const SizedBox(height: 64),
            ],
          ),
        ),
      ),
    );
  }
}

class FinancePage extends ConsumerWidget {
  const FinancePage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => FeaturePage(
    title: '财务公开',
    child: AsyncPanel<dynamic>(
      load: () async => await Future.wait([
        ref.read(apiProvider).get('/finance/summary'),
        ref.read(apiProvider).get('/finance'),
      ]),
      builder: (d) {
        final summary = object(d[0]);
        final totals = object(summary['totals']);
        final rows = objects(d[1] is List ? d[1] : object(d[1])['items']);
        return SingleChildScrollView(
          child: ReadingWidth(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final e in const {
                      'income': '收入',
                      'expense': '支出',
                      'net': '结余',
                    }.entries)
                      SurfaceCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(e.value),
                            const SizedBox(height: 10),
                            Text(
                              '¥${(intOf(totals[e.key]) / 100).toStringAsFixed(2)}',
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SectionTitle('明细'),
                for (final row in rows)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      row['type'] == 'expense'
                          ? Icons.north_east_rounded
                          : Icons.south_west_rounded,
                    ),
                    title: Text(
                      textOf(
                        row['title'] ?? row['description'] ?? row['category'],
                      ),
                    ),
                    subtitle: Text(
                      relativeTime(row['occurredAt'] ?? row['createdAt']),
                    ),
                    trailing: Text(
                      '¥${(intOf(row['amount']) / 100).toStringAsFixed(2)}',
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
